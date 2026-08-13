-- ============================================================================
-- ThugUI: Cooldown Viewer -- runtime
--
-- One generic engine that renders whatever the active spec's profile says,
-- replacing the three hand-written bars (ECV/BCV/GCV). Adding a spec is now
-- a player dragging icons onto a grid, not ~200 lines of Lua.
--
-- The grid is invisible here. Only the icons draw -- the borders, cell lines
-- and intersection markers exist solely in the settings editor, which is the
-- whole point of designing the shape on a grid and wearing it without one.
--
-- The legacy bars still live in modules/EssentialRings.lua and are re-enabled
-- wholesale by setting ThugUI_Config.cvUseLegacy = true (/thugcv legacy).
-- Nothing in this file runs in that mode.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI.CooldownViewer = ThugUI.CooldownViewer or {}

local CV = ThugUI.CooldownViewer
local Data = CV.Data

local UPDATE_INTERVAL = 0.15   -- state refresh; cursor tracking is every frame
local CURSOR_GAP = 8           -- pixels between the cursor and the anchor point

CV.icons = {}          -- cellKey -> icon frame
CV.container = nil
CV.previewMode = false -- forced visible from the settings page

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

function CV:IsLegacyMode()
    return ThugUI_Config and ThugUI_Config.cvUseLegacy and true or false
end

--- The profile being drawn. Normally the active spec's, but while the settings
--- page previews a layout it draws whichever spec is being edited -- otherwise
--- ticking "preview" while building a layout for a spec you are not currently
--- in would show you a different spec's grid.
function CV:CurrentProfile()
    if self.previewMode and self.overrideSpecID then
        return Data.GetProfile(self.overrideSpecID)
    end
    return Data.GetActiveProfile()
end

--- Combat, or test mode standing in for it. Mirrors ER:IsInCombat so the two
--- halves of the addon agree about what "in combat" means for previewing.
local function InCombat()
    local ER = ThugUI.EssentialRings
    if ER and ER.IsInCombat then return ER:IsInCombat() end
    return InCombatLockdown() or UnitAffectingCombat("player")
end

--- Is this spell available to the player right now?
---
--- Asked BY NAME, because C_Spell.GetSpellInfo only resolves a name to a spell
--- the player actually has -- a nil return doubles as "not talented". By ID it
--- resolves for any spell in the game, so an ID check answers a different
--- question entirely.
---
--- This also handles override spells, which is where an ID check goes wrong in
--- both directions: a talent that replaces a base spell leaves IsPlayerSpell
--- disagreeing with itself depending on which of the pair you ask about, so
--- icons flicker in and out as talents and overrides shift. The stored ID picks
--- the artwork; the name decides whether it draws.
local function IsSpellAvailable(spellName)
    if not spellName then return false end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellName)
    return (ok and info and info.spellID) and true or false
end

--- Is the spell usable right now? Returns ready, charges, alpha -- see the
--- comment on `alpha` immediately above the function for what that third
--- return is and why it can never be nil.
---
--- Readiness is derived from `isActive` and `isOnGCD`, NEVER from startTime or
--- duration, for two independent reasons:
---
---  1. The global cooldown is a running cooldown. Judging by duration means
---     every icon on the grid vanishes the moment you cast anything, because
---     during the GCD every spell reports a cooldown. `isOnGCD` marks exactly
---     that case so it can be ignored.
---  2. In 12.x startTime/duration are *secret values*. Comparing them does not
---     yield a usable boolean -- the result is itself secret, and feeding that
---     to SetShown hides the icon. `isActive`/`isOnGCD` were added non-secret
---     in 12.0.1 for this.
---
--- This mirrors IsSpellReady in modules/EssentialRings.lua, which is the logic
--- the original druid bars have been running on all along.
--- Queried BY NAME for the same reason as IsSpellAvailable: the name resolves
--- to whichever version of the spell the player currently has talented, so the
--- cooldown read always matches the button they actually press.
--- A value we are allowed to look at: present, and not a secret.
---
--- `issecretvalue` is asked FIRST and the nil test comes second, because
--- comparing a secret against nil is itself a comparison and comparison is the
--- thing that errors. Writing it the other way round reads as harmless and is
--- not -- see tasks/00-AGENT-BRIEF.md and SecretProbe.lua, which both state the
--- ordering rule, and which this file used to get backwards.
local function Readable(v)
    if issecretvalue and issecretvalue(v) then return false end
    return v ~= nil
end

--- The third return, `alpha`, is always safe to hand straight to
--- `icon:SetAlpha` -- it is `1` on every path except one: the fail-open branch
--- below, where currentCharges could not be read. `SetAlpha` accepts a secret
--- and clamps it to 0-1 (DECISIONS.md §20, measured ACCEPTED at every phase of
--- a full combat, unlike SetShown/SetCooldown which still refuse one), so a
--- secret 0 goes invisible and a secret 1 or 2 stays opaque -- with no
--- comparison anywhere, because comparing is the operation that throws.
---
--- This return must never be nil. If a caller had to test it before using it,
--- that test would itself be a comparison against a possible secret -- the
--- exact thing this design exists to avoid -- or it would need a fourth
--- boolean return just to say "is this safe", which is worse than one function
--- that always answers safely. All secret handling for it stays in here, next
--- to the same handling for `ready`.
local function IsSpellReady(spellName)
    -- Charge builds are ready whenever a charge is banked, even though the
    -- recharge timer is always running.
    local ok, chargeInfo = pcall(C_Spell.GetSpellCharges, spellName)
    if ok and chargeInfo then
        -- A table at all means this IS a charge spell: GetSpellCharges returns
        -- nil for a spell with no charge mechanic. So when maxCharges is
        -- unreadable we still know that much, and fail open below rather than
        -- falling through to the recharge timer -- which for a charge spell is
        -- essentially always running, and would hide the icon permanently.
        local maxCharges = chargeInfo.maxCharges
        if not Readable(maxCharges) or maxCharges > 1 then
            local current = chargeInfo.currentCharges
            if Readable(current) then
                -- SetShown has already done the hiding work on this path (the
                -- caller acts on `ready`), so an icon that is shown must be
                -- fully opaque.
                return current > 0, current, 1
            end

            -- Charges are secret this tick (they often are in combat). Fail
            -- open on readiness: a reminder that shows slightly too eagerly
            -- beats one that disappears mid-fight. But hand the secret count
            -- itself back as the alpha -- issecretvalue asked first, same
            -- ordering Readable() uses -- so a spent charge still disappears
            -- even though we were never allowed to ask whether it was spent.
            if issecretvalue and issecretvalue(current) then
                return true, nil, current
            end
            -- current was nil outright (not secret, genuinely absent) rather
            -- than unreadable. Nothing to clamp on; stay opaque.
            return true, nil, 1
        end
    end

    local ok2, cdInfo = pcall(C_Spell.GetSpellCooldown, spellName)
    if ok2 and cdInfo then
        if cdInfo.isOnGCD then return true, nil, 1 end
        if cdInfo.isActive then return false, nil, 1 end
    end

    return true, nil, 1
end

--- Drive an icon's sweep for "always" mode.
---
--- **The sweep is skipped whenever the timing is secret, which in practice
--- means "in combat".** `SetCooldown` REFUSES a secret start value. That is
--- measured, not reasoned: BugGrabber session 150 carried 36 copies of
---
---     Core.lua:126: bad argument #1 to 'SetCooldown' (Secret values are only
---     allowed during untainted execution for this argument.)
---
--- and nothing caught it, so the throw unwound the whole UpdateState loop.
--- Every icon the loop had not reached yet kept its previous state and
--- ApplyLayout never ran, which looks exactly like "the icon is stuck showing
--- ready" -- it is not reporting anything, it is frozen. The loop iterates with
--- pairs(), so which icons froze changed from session to session and made the
--- symptom look like it was moving around.
---
--- Charge spells are what surfaced it. Their recharge timer runs essentially
--- always, so isActive is true on nearly every pass and this path is taken on
--- nearly every pass, where an ordinary spell only reaches it while genuinely
--- on cooldown.
---
--- This corrects DECISIONS.md §5, which claimed handing secrets to SetCooldown
--- works. §12 had already measured SetCooldownDuration refusing them; the two
--- facts were never joined up. Passing a secret to a blessed setter is fine
--- only for the setters that are actually blessed, and the Cooldown radial
--- setters are not among them.
---
--- The pcall is a backstop for the case where issecretvalue is absent
--- altogether -- an unsweept icon is a cosmetic loss, an uncaught throw here
--- costs the entire grid.
local function ApplySweep(icon, spellName)
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellName)
    if not (ok and cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) then
        icon.cooldown:Clear()
        return
    end

    if not (Readable(cdInfo.startTime) and Readable(cdInfo.duration)) then
        icon.cooldown:Clear()
        return
    end

    if not pcall(icon.cooldown.SetCooldown, icon.cooldown,
                 cdInfo.startTime, cdInfo.duration, cdInfo.modRate) then
        icon.cooldown:Clear()
    end
end

-- ----------------------------------------------------------------------------
-- Item-backed cells
--
-- An icon is item-backed when its Cooldown Manager entry carries `equipSlot`
-- (set on the icon in Rebuild) -- 12.1 puts trinkets in the manager this way,
-- identified by the slot they sit in rather than by a spell the player knows.
--
-- Item cooldowns carry no SecretWhen* flag at all (DECISIONS.md 20; Blizzard's
-- own CooldownViewer.lua:1020 reads one with plain GetInventoryItemCooldown),
-- so none of this needs the secret-value machinery the spell path above needs
-- -- including in combat. What it CANNOT use is IsSpellAvailable: that resolves
-- by NAME, which is spellbook-scoped, and a trinket's on-use spell is not in
-- the spellbook -- it answers "not talented" and the icon never draws. That is
-- the bug this whole section exists to route around.
-- ----------------------------------------------------------------------------

--- Is something actually equipped in this slot? Blizzard's own test
--- (CooldownViewerItemData.lua:286, live branch):
--- ItemLocation:CreateFromEquipmentSlot(equipSlot) then :IsValid(). Guarded so
--- a client missing the ItemLocation global entirely cannot throw.
local function IsItemAvailable(equipSlot)
    if not equipSlot or not ItemLocation or not ItemLocation.CreateFromEquipmentSlot then
        return false
    end
    local ok, loc = pcall(ItemLocation.CreateFromEquipmentSlot, equipSlot)
    if not ok or not loc then return false end
    local ok2, valid = pcall(loc.IsValid, loc)
    return ok2 and valid and true or false
end

--- Is the item in this slot off cooldown right now?
---
--- A separate function from IsSpellReady rather than a branch inside it: the
--- two share no logic, and IsSpellReady's comment block is load-bearing
--- documentation about secret values that simply does not apply here.
---
--- GetInventoryItemCooldown is what Blizzard's own item mixin reads
--- (CooldownViewer.lua:1020) and carries no secrecy flag, so duration == 0 is
--- a plain, ordinary "nothing is running" test -- the same idiom every
--- action-button cooldown in the default UI uses, and one that needs no
--- comparison against GetTime().
---
--- Every value is still routed through Readable() anyway: that global is not
--- in the generated API documentation, so nothing was measured about its
--- secrecy posture here, and an unreadable answer fails VISIBLE (treats the
--- item as ready) rather than hiding a reminder mid-fight -- the same rule
--- IsSpellReady already follows, for the same reason.
local function IsItemReady(equipSlot)
    if not equipSlot or not GetInventoryItemCooldown then return true end

    local ok, startTime, duration = pcall(GetInventoryItemCooldown, "player", equipSlot)
    if not ok then
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:LogOnce(("item-cd-threw-%s"):format(tostring(equipSlot)),
                "CV", "GetInventoryItemCooldown threw for slot %s -- treating as ready",
                tostring(equipSlot))
        end
        return true
    end

    if not Readable(startTime) or not Readable(duration) then
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:LogOnce(("item-cd-unreadable-%s"):format(tostring(equipSlot)),
                "CV", "item cooldown for slot %s unreadable -- failing visible",
                tostring(equipSlot))
        end
        return true
    end

    return duration == 0
end

--- Drive an item cell's sweep, for "always" and "recharging" modes.
---
--- Unlike ApplySweep these are ordinary numbers even in combat, so plain
--- SetCooldown works with no secret screen -- but the pcall discipline stays:
--- DECISIONS.md 19, an uncaught throw anywhere in the per-icon loop leaves
--- every icon UpdateState has not yet reached frozen at its previous state.
local function ApplyItemSweep(icon, equipSlot)
    if not equipSlot or not GetInventoryItemCooldown then
        icon.cooldown:Clear()
        return
    end

    local ok, startTime, duration = pcall(GetInventoryItemCooldown, "player", equipSlot)
    if not ok or not Readable(startTime) or not Readable(duration) or duration == 0 then
        icon.cooldown:Clear()
        return
    end

    if not pcall(icon.cooldown.SetCooldown, icon.cooldown, startTime, duration) then
        icon.cooldown:Clear()
    end
end

--- A buff on the player cast by the player, for one spell ID.
---
--- Blizzard's CooldownViewerItemDataMixin:FindLinkedSpellForCurrentAuras uses
--- GetUnitAuraBySpellID plus a sourceUnit == "player" check, so this matches
--- it: a tracked buff should mean YOUR buff, not the same-named one somebody
--- else put on you.
local function GetPlayerCastAura(spellID, spellName)
    if not spellID or not C_UnitAuras then return nil end

    -- Blizzard's own tracker requires sourceUnit == "player", but engine code
    -- can read fields that addon code cannot: in 12.x aura fields come back as
    -- SECRET values, and comparing a secret string never yields a usable true.
    -- Copying that check verbatim rejected every aura and the tracked buff
    -- simply never appeared.
    --
    -- So: reject only a source we can actually READ and that is not the player.
    -- Unreadable or absent is accepted, because the lookup is already scoped to
    -- auras on the player and self-buffs are what this mode is for. The cost is
    -- that another player's same-named buff can slip through while the field is
    -- secret, which is a far smaller failure than showing nothing at all.
    local function Mine(aura)
        if not aura then return nil end

        local source = aura.sourceUnit
        if source == nil then return aura end
        if issecretvalue and issecretvalue(source) then return aura end

        return source == "player" and aura or nil
    end

    -- Which STAGE failed, recorded once per spell per session. "The buff icon
    -- did not draw" has three causes that are identical from outside: the API
    -- threw, it returned no aura at all, or it returned one that Mine()
    -- refused. Guessing between them has already cost several round trips.
    --- Combat is part of the KEY, not just the message. The first version left
    --- it out, and the out-of-combat "api-returned-nothing" logged while no
    --- buff was up then suppressed the in-combat one -- the single line the
    --- whole capture existed to produce. The difference between the two states
    --- is the entire question here, so it cannot share a key.
    local function Note(stage)
        if ThugUI.Diagnostics then
            local inCombat = InCombat()
            ThugUI.Diagnostics:LogOnce(
                ("aura-%s-%s-%s"):format(tostring(spellID), stage, tostring(inCombat)),
                "AURA", "lookup for %s: %s (combat=%s)",
                tostring(spellID), stage, tostring(inCombat))
        end
    end

    if C_UnitAuras.GetUnitAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, "player", spellID)
        if not ok then
            Note("api-threw")
        elseif aura == nil then
            Note("api-returned-nothing")
        elseif not Mine(aura) then
            Note("rejected-by-source-check")
        else
            Note("found")
            return aura
        end
    end

    if C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and Mine(aura) then
            Note("found-via-fallback")
            return Mine(aura)
        end
        Note("fallback-empty")
    end

    -- Both by-ID lookups return nil in instanced combat. That is not a guess:
    -- modules/EssentialRings.lua:980 records it from an earlier investigation,
    -- and it matches what the log shows here exactly -- the same buff resolves
    -- out of combat and returns nothing during it.
    --
    -- Walking the aura list is a genuinely different code path rather than the
    -- same query retried, which is the point. Matching is pcall'd per field
    -- because spellId and name can both be secret values in combat, and a
    -- comparison against a secret never yields a usable boolean.
    if C_UnitAuras.GetAuraDataByIndex then
        local name = spellName
        if not name and C_Spell and C_Spell.GetSpellInfo then
            local infoOK, info = pcall(C_Spell.GetSpellInfo, spellID)
            name = infoOK and info and info.name or nil
        end

        -- Counted, because "the scan matched nothing" has two very different
        -- causes and they were indistinguishable in the first version of this
        -- log: the list came back empty (we are handed no auras at all), or the
        -- list came back full but every identifying field was a secret value so
        -- no comparison could succeed. The second is what
        -- EssentialRings.lua:985 describes as Addon Disarmament, and it needs a
        -- completely different fix from the first. Say which.
        local seen, unreadable = 0, 0

        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            seen = seen + 1

            local idOK, idMatch = pcall(function() return aura.spellId == spellID end)
            local nameOK, nameMatch = false, false
            if name then
                nameOK, nameMatch = pcall(function() return aura.name == name end)
            end

            if not idOK and not nameOK then unreadable = unreadable + 1 end

            if ((idOK and idMatch) or (nameOK and nameMatch)) and Mine(aura) then
                Note("found-by-index")
                return aura
            end
        end

        if seen == 0 then
            Note("index-scan-saw-no-auras")
        elseif unreadable > 0 then
            Note(("index-scan-%d-auras-%d-unreadable"):format(seen, unreadable))
        else
            Note(("index-scan-%d-auras-none-matched"):format(seen))
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Proc glow
--
-- The pulsing highlight an action button gets when a proc makes a spell free
-- or empowered -- Opportunity on Pistol Shot being the case that prompted it.
--
-- Driven by C_SpellActivationOverlay.IsSpellOverlayed, which returns a PLAIN
-- bool (per Blizzard's own SpellActivationOverlayDocumentation) and so is safe
-- to branch on even when everything around it has gone secret.
--
-- The visual comes from ActionButtonSpellAlertManager, Blizzard's own alert
-- pool, rather than a home-made approximation -- it is the same art the action
-- bars use, so a glow here reads identically to a glow there. Its Default path
-- only needs a frame with a size, and our icons have both; `actionButton.action`
-- being nil short-circuits the assisted-combat branch it would otherwise take.
-- ----------------------------------------------------------------------------

local function IsOverlayed(spellID)
    if not spellID or not C_SpellActivationOverlay then return false end
    local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
    return ok and overlayed or false
end

--- Last-resort glow if Blizzard's alert pool refuses our frame. Deliberately
--- plain: a static additive wash, not an imitation of the real animation.
local function FallbackGlow(icon, shown)
    if not shown and not icon.glowFallback then return end

    if not icon.glowFallback then
        local glow = icon:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("TOPLEFT", -3, 3)
        glow:SetPoint("BOTTOMRIGHT", 3, -3)
        glow:SetColorTexture(1, 0.85, 0.25, 0.35)
        glow:SetBlendMode("ADD")
        icon.glowFallback = glow
    end
    icon.glowFallback:SetShown(shown)
end

local function SetGlow(icon, shown)
    if icon.glowing == shown then return end
    icon.glowing = shown

    local manager = ActionButtonSpellAlertManager
    if shown then
        if manager and pcall(manager.ShowAlert, manager, icon) then
            FallbackGlow(icon, false)
        else
            FallbackGlow(icon, true)
        end
    else
        if manager then pcall(manager.HideAlert, manager, icon) end
        FallbackGlow(icon, false)
    end
end

--- Does this icon's spell currently have a proc glow? Checks the stored ID and
--- the currently-talented one, since a placement may hold either.
local function ShouldGlow(icon)
    if IsOverlayed(icon.spellID) then return true end

    if icon.spellName then
        local info = C_Spell.GetSpellInfo(icon.spellName)
        if info and info.spellID ~= icon.spellID and IsOverlayed(info.spellID) then
            return true
        end
    end
    return false
end

--- The aura an icon should be showing, and which spell it came from.
---
--- Some Cooldown Manager entries stand for a SET of possible buffs rather than
--- one: Roll the Bones is four on this build, and Blizzard's tracker walks
--- cooldownInfo.linkedSpellIDs to find whichever is live, then draws that
--- buff's icon and timer instead of the base spell's. Without walking the
--- linked list, tracking Roll the Bones as a buff finds nothing at all,
--- because no aura is ever named "Roll the Bones".
---
--- @return auraData, spellID that produced it
local function ResolveAura(icon)
    local aura = GetPlayerCastAura(icon.spellID, icon.spellName)
    if aura then return aura, icon.spellID end

    for _, linkedID in ipairs(icon.linkedSpellIDs or {}) do
        aura = GetPlayerCastAura(linkedID)
        if aura then return aura, linkedID end
    end
    return nil
end

--- Should a cell whose buff is drawn by Blizzard's own item keep its slot?
---
--- Three sources, in descending order of authority. The order IS the design:
---
---  1. Blizzard's item frame. It hides itself when the buff drops, so its shown
---     state is the answer -- when we are allowed to read it. Their code is
---     untainted and can see what ours cannot.
---  2. Our own aura lookup. Truthful out of combat, blind during it
---     (RequiresNonSecretAura), so it only gets a say when it can see.
---  3. Reserve the cell.
---
--- Step 3 is a safety property, not a convenient fallback. Collapsing a cell
--- whose buff is actually up leaves Blizzard's item anchored to our now-hidden
--- icon, drawing at a stale coordinate on top of a neighbour. Reserving when
--- unsure is the difference between a gap nobody wanted and a broken UI.
---
--- CV.BlizzBuffs rather than the caller's self.BlizzBuffs: both name the same
--- table (BlizzBuffs.lua assigns onto ThugUI.CooldownViewer, which is this
--- file's CV upvalue), and a file-local helper has no self.
local function AdoptedCellWanted(icon, item)
    local shown = CV.BlizzBuffs and CV.BlizzBuffs:ItemIsShown(item)
    if shown ~= nil then return shown end

    -- In combat the by-ID aura lookups return nothing at all
    -- (RequiresNonSecretAura), so "no aura" and "cannot see the aura" are the
    -- same answer here. Keep the slot.
    if InCombat() then return true end

    -- Only an aura-mode cell has an aura to fall back on. A cooldown item is
    -- shown by Blizzard whenever the spell is tracked -- it sweeps and dims
    -- rather than disappearing -- so asking "is the buff up" about one answers
    -- no forever and would collapse the cell out of combat, which is precisely
    -- when the player is looking at their layout.
    if icon.mode ~= "aura" then return true end

    return ResolveAura(icon) ~= nil
end

-- ----------------------------------------------------------------------------
-- Geometry
-- ----------------------------------------------------------------------------

function CV:GetCellSize(profile)
    local size = profile.iconSize or 32
    local pad = profile.padding or 4
    return size + pad, size + pad, size, pad
end

--- Container size for a full 10x10 grid. It stays constant regardless of how
--- many cells are filled, so an intersection anchor always means the same
--- place relative to the shape the player drew.
function CV:GetGridSize(profile)
    local cellW, cellH = self:GetCellSize(profile)
    return Data.GRID_COLS * cellW, Data.GRID_ROWS * cellH
end

-- ----------------------------------------------------------------------------
-- Frame construction
-- ----------------------------------------------------------------------------

function CV:EnsureContainer()
    if self.container then return self.container end

    local f = CreateFrame("Frame", "ThugUI_CooldownViewer", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    f:Hide()

    -- Drag handle used out of combat and while previewing. Deliberately not
    -- mouse-enabled the rest of the time: an invisible 10x10 grid swallowing
    -- clicks in the middle of the screen would be maddening.
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local profile = CV:CurrentProfile()
        profile.point = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 1, 0.8, 0.10)
    bg:Hide()
    f.previewBG = bg

    self.container = f
    return f
end

-- Icons are pooled rather than recreated. A layout edit re-runs Rebuild on
-- every slider tick, and SetParent(nil) does not free a frame in WoW -- it
-- orphans it -- so building fresh ones would bleed frames for a whole session.
CV.iconPool = {}

local function AcquireIcon(parent)
    for _, icon in ipairs(CV.iconPool) do
        if not icon.inUse then
            icon.inUse = true
            return icon
        end
    end

    local icon = CreateFrame("Frame", nil, parent)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.tex = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)
    icon.cooldown = cd

    local count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    count:Hide()
    icon.count = count

    icon:Hide()
    icon.inUse = true
    table.insert(CV.iconPool, icon)
    return icon
end

--- Rebuild every icon from the profile. Called on spec change, on any layout
--- edit, and on login.
function CV:Rebuild()
    local f = self:EnsureContainer()
    local profile = CV:CurrentProfile()

    for _, icon in ipairs(self.iconPool) do
        icon.inUse = false
        icon:Hide()
    end
    wipe(self.icons)

    local cellW, cellH, iconSize, pad = self:GetCellSize(profile)
    f:SetSize(self:GetGridSize(profile))
    f:SetScale(profile.scale or 1.0)

    for _, placement in ipairs(Data.GetPlacements(profile)) do
        local icon = AcquireIcon(f)
        icon:SetParent(f)
        icon:SetSize(iconSize, iconSize)

        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(placement.spellID)
        icon.tex:SetTexture(texture)
        -- Icons are pooled, and a cell adopted by Blizzard's buff frame leaves
        -- its texture at zero alpha. Without this reset, the next spell to
        -- reuse that frame would be invisible for reasons nothing about it
        -- explains.
        icon.tex:SetAlpha(1)
        -- Remembered so aura mode can swap to a linked buff's art and back.
        icon.baseTexture = texture
        icon.spellID = placement.spellID

        -- The set of buffs this entry can stand for, e.g. the Roll the Bones
        -- outcomes. Resolved here rather than stored in the placement,
        -- so it follows talent changes and survives a patch renumbering
        -- cooldown IDs.
        local cooldownInfo = Data.GetCooldownInfoForSpell(placement.spellID)
        icon.linkedSpellIDs = cooldownInfo and cooldownInfo.linkedSpellIDs or nil
        -- Set only when the Cooldown Manager entry actually carries one --
        -- explicitly nil otherwise, because icons are pooled and a cell that
        -- used to be item-backed must not leave a stale slot on the spell that
        -- reuses its frame next.
        icon.equipSlot = cooldownInfo and cooldownInfo.equipSlot or nil
        -- Resolved by ID (which works for any spell in the game) and cached, so
        -- the per-frame path can query by name. Rebuild re-runs on
        -- SPELLS_CHANGED / PLAYER_TALENT_UPDATE, so this stays current.
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(placement.spellID)
        icon.spellName = spellInfo and spellInfo.name
        icon.mode = placement.mode
        icon.row, icon.col = placement.row, placement.col
        -- Resting state is "everything present". UpdateState corrects it, but
        -- it early-returns while the container is hidden, so without this the
        -- icons would sit unanchored until the first pass after they show.
        icon.wanted = true
        icon.cooldown:Clear()
        icon.count:Hide()

        self.icons[placement.key] = icon
    end

    self:ApplyLayout()
    self:UpdateVisibility()
    self:UpdateState()
end

--- Position every icon. Split out of Rebuild because with collapse enabled a
--- position depends on which icons are currently live, so this has to re-run on
--- every state update, not just on a layout edit.
function CV:ApplyLayout()
    local f = self.container
    if not f then return end

    local profile = CV:CurrentProfile()
    local cellW, cellH, _, pad = self:GetCellSize(profile)

    local mode = profile.collapse or "none"

    -- Working positions, seeded from where the icons were drawn. Passes read
    -- and rewrite these rather than the placements, which is what lets "both"
    -- run a second pass over the results of the first.
    local pos = {}
    for _, icon in pairs(self.icons) do
        pos[icon] = { row = icon.row, col = icon.col }
    end

    local function Commit()
        for icon, p in pairs(pos) do
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", f, "TOPLEFT",
                (p.col - 1) * cellW + pad / 2,
                -((p.row - 1) * cellH + pad / 2))

            -- Aura mode is the only visibility here that hangs on a lookup
            -- which can fail without erroring, and from the outside "it never
            -- appeared" is indistinguishable from "it appeared in a cell I was
            -- not watching" -- collapse moves it, so the cell it was drawn in
            -- is not the cell it lands in. Logged on transition only (a handful
            -- of lines a fight) and WITH the collapsed cell, so the saved log
            -- alone separates the two.
            if icon.mode == "aura" and icon.loggedShown ~= icon.wanted then
                icon.loggedShown = icon.wanted
                if ThugUI.Diagnostics then
                    ThugUI.Diagnostics:Log("CV", "buff icon %s: %s at cell %d:%d (combat=%s)",
                        tostring(icon.spellName),
                        icon.wanted and "SHOWN" or "hidden",
                        p.row, p.col, tostring(InCombat()))
                end
            end
        end
    end

    if mode == "none" then
        Commit()
        return
    end

    --- Slot index for the i-th of n survivors packing between first and last.
    --- Packing runs from the group's own outermost occupied slot, never the
    --- grid edge, so a group at full strength lands exactly where it was drawn
    --- and an icon never teleports across the shape.
    local function Slot(i, n, first, last, packHigh)
        if packHigh then return last - (n - i) end
        return first + i - 1
    end

    --- One collapse pass. Rows and columns are mirror images of each other, so
    --- both are this function with the axes swapped:
    ---
    ---   major  the axis icons are grouped BY   (rows mode: "row")
    ---   minor  the axis icons slide ALONG      (rows mode: "col")
    ---
    --- Stage 1 compacts each group along `minor`. Stage 2 vacates any group
    --- with nothing live left and closes the survivors along `major`.
    local function Pass(major, minor, packMinorHigh, packMajorHigh)
        local groups, majors = {}, {}
        for icon in pairs(pos) do
            local key = pos[icon][major]
            if not groups[key] then
                groups[key] = {}
                table.insert(majors, key)
            end
            table.insert(groups[key], icon)
        end
        table.sort(majors)

        local liveGroups = {}
        for _, key in ipairs(majors) do
            table.sort(groups[key], function(a, b) return pos[a][minor] < pos[b][minor] end)
            for _, icon in ipairs(groups[key]) do
                if icon.wanted then
                    table.insert(liveGroups, key)
                    break
                end
            end
        end

        local firstMajor, lastMajor = majors[1], majors[#majors]

        for i, key in ipairs(liveGroups) do
            local group = groups[key]
            -- Stage 2: where this group sits along the major axis once any
            -- fully-spent groups ahead of it have vacated.
            local majorSlot = Slot(i, #liveGroups, firstMajor, lastMajor, packMajorHigh)

            -- Stage 1: the group keeps its own span along the minor axis as it
            -- moves, so the shape's profile survives the shift.
            local firstMinor = pos[group[1]][minor]
            local lastMinor = pos[group[#group]][minor]

            local live = {}
            for _, icon in ipairs(group) do
                if icon.wanted then table.insert(live, icon) end
            end

            for j, icon in ipairs(live) do
                pos[icon][major] = majorSlot
                pos[icon][minor] = Slot(j, #live, firstMinor, lastMinor, packMinorHigh)
            end
        end
    end

    local packRight, packDown = Data.ResolveCollapseAxes(profile)

    if mode == "rows" or mode == "both" then
        Pass("row", "col", packRight, packDown)
    end
    if mode == "columns" or mode == "both" then
        Pass("col", "row", packDown, packRight)
    end

    Commit()

    -- Blizzard's buff items ride on our icons, so they move when the icons do.
    -- Collapse means a cell's position depends on which icons are live, which
    -- is exactly why this belongs here rather than in Rebuild.
    if self.BlizzBuffs then self.BlizzBuffs:Refresh() end
end

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

function CV:UpdateState()
    if not self.container or not self.container:IsShown() then return end

    local glowEnabled = CV:CurrentProfile().showProcGlow ~= false

    -- Preview is about seeing the SHAPE, so every icon draws flat: cooldown and
    -- aura state are irrelevant, and an off-spec layout would otherwise render
    -- completely empty because none of its spells are known right now.
    if self.previewMode then
        for _, icon in pairs(self.icons) do
            icon.cooldown:Clear()
            icon.count:Hide()
            icon.wanted = true
            icon:Show()
            SetGlow(icon, false)
        end
        -- Laid out through the same path as combat, so preview shows the real
        -- resting shape -- including the fact that with row collapse on, a
        -- horizontal gap you drew is closed even at full strength.
        self:ApplyLayout()
        return
    end

    for _, icon in pairs(self.icons) do
        local spellID = icon.spellID
        local spellName = icon.spellName
        local show = false
        -- Resolved once: "proc" mode gates on it and the glow visual uses it.
        local procced = ShouldGlow(icon)

        -- Reset every pass, before any branch below, because icons are pooled.
        -- An icon left at alpha 0 by a spent charge spell in cooldown/proc mode
        -- would otherwise carry that invisibility to whatever spell reuses the
        -- frame next -- the exact bug shape the pooled-icon comment at
        -- Core.lua:~1000 already carries for stale sweep/stack state. Only the
        -- cooldown/proc branches in the spell path below override this; every
        -- other path (adopted, item-backed, aura, always, recharging, and a
        -- spell with no charge mechanic at all) keeps it at 1. Task 15.
        icon:SetAlpha(1)

        -- A cell whose buff is drawn by Blizzard's own item frame. Ours holds
        -- the slot -- the Blizzard item is anchored to it, so with collapse on,
        -- a cell that stops being "wanted" while the buff is still up slides the
        -- rest of the row over the top of it -- but it draws nothing itself.
        --
        -- Whether the cell is reserved is now asked rather than assumed. It used
        -- to be an unconditional yes, on the belief that we can never know if
        -- the buff is up -- true in combat, false out of it, and the player's
        -- column consequently never closed even at rest. AdoptedCellWanted asks
        -- Blizzard's frame first, our aura lookup second, and reserves the slot
        -- when neither can answer.
        --
        -- Adoption outranks our own IsSpellAvailable check. When Blizzard's
        -- untainted code is drawing the item, we have no standing to ask whether
        -- the spell exists: a placement whose spell ID is a passive that grants
        -- the buff (e.g. Opportunity 279876 -> buff 195627) will not resolve
        -- via a by-name lookup (GetSpellInfo), but Blizzard's frame is live.
        local adopted = self.BlizzBuffs and self.BlizzBuffs:AdoptedItem(icon)

        if adopted then
            show = AdoptedCellWanted(icon, adopted)
            icon.tex:SetAlpha(0)
            icon.cooldown:Clear()
            icon.count:Hide()
        elseif icon.equipSlot then
            -- Item-backed cell. MUST NOT go through IsSpellAvailable below --
            -- that resolves by NAME, which is spellbook-scoped, and an item's
            -- on-use spell is not in the spellbook: it answered "not talented"
            -- and the icon never drew (the Radiant Blessing bug task 14 exists
            -- for). An item is identified by the slot it sits in instead, and
            -- its cooldown is a plain number even in combat, so this needs none
            -- of the secret-value handling the spell path below needs.
            if not IsItemAvailable(icon.equipSlot) then
                show = false
                icon.cooldown:Clear()
                icon.count:Hide()
            else
                local ready = IsItemReady(icon.equipSlot)

                if icon.mode == "always" then
                    show = true
                    ApplyItemSweep(icon, icon.equipSlot)
                elseif icon.mode == "recharging" then
                    -- Exact inverse of "ready", from the SAME answer "cooldown"
                    -- mode uses below, so the two modes can never disagree.
                    show = not ready
                    ApplyItemSweep(icon, icon.equipSlot)
                elseif icon.mode == "proc" then
                    show = (ready and procced) and true or false
                    icon.cooldown:Clear()
                else
                    -- "cooldown" mode: nothing to sweep, it just disappears.
                    show = ready and true or false
                    icon.cooldown:Clear()
                end
                -- Items do not report a charge count through this path.
                icon.count:Hide()
            end
        elseif not IsSpellAvailable(spellName) then
            show = false
        elseif icon.mode == "aura" then
            local aura, auraSpellID = ResolveAura(icon)
            show = aura ~= nil

            -- Show the buff you actually have, not the spell that granted it.
            -- The texture is looked up from OUR spell ID rather than read off
            -- the aura, because aura fields can be secret values in combat
            -- while the ID we matched on never is.
            if aura and auraSpellID ~= icon.spellID then
                icon.tex:SetTexture(C_Spell.GetSpellTexture(auraSpellID))
            else
                icon.tex:SetTexture(icon.baseTexture)
            end

            -- Aura timing is secret-guarded: a comparison against a secret
            -- number does not yield a usable boolean, so the whole read is
            -- wrapped rather than trusted.
            -- pcall returns its SUCCESS status first and the wrapped function's
            -- own returns after it. Capturing only the first value made these
            -- read true whenever the call merely did not throw -- including the
            -- cases the inner `if` deliberately skips, an aura with no duration
            -- and an aura with no stacks. The Clear/Hide below were then skipped
            -- too, and since icons are pooled, one could keep the previous
            -- occupant's sweep and stack count. Take both values.
            local swept = false
            if aura then
                local ok, didSweep = pcall(function()
                    if aura.expirationTime and aura.duration and aura.duration > 0 then
                        icon.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
                        return true
                    end
                    return false
                end)
                swept = ok and didSweep
            end
            if not swept then icon.cooldown:Clear() end

            local stacked = false
            if aura then
                local ok, didStack = pcall(function()
                    if aura.applications and aura.applications > 1 then
                        icon.count:SetText(aura.applications)
                        icon.count:Show()
                        return true
                    end
                    return false
                end)
                stacked = ok and didStack
            end
            if not stacked then icon.count:Hide() end
        else
            local ready, charges, alpha = IsSpellReady(spellName)

            if icon.mode == "always" then
                show = true
                ApplySweep(icon, spellName)
            elseif icon.mode == "proc" then
                -- Both conditions, deliberately. A proc that lands while the
                -- spell is still on cooldown is not yet actionable, so it stays
                -- hidden until it is actually pressable.
                show = (ready and procced) and true or false
                icon.cooldown:Clear()
                -- A procced charge spell with nothing banked fails `ready` open
                -- in combat exactly as cooldown mode does below (currentCharges
                -- is secret), so it would otherwise sit on screen glowing with
                -- no charge to spend. Same alpha, same source. Task 15.
                icon:SetAlpha(alpha)
            elseif icon.mode == "recharging" then
                -- Exact inverse of "cooldown" mode below, from the SAME `ready`
                -- answer, so the two can never disagree about the same spell.
                -- Unlike cooldown mode it gets a sweep -- the sweep is the
                -- whole point of the mode.
                --
                -- Deliberately NOT given the alpha treatment. The inverse of a
                -- secret 0/1/2 needs `1 - currentCharges`, which is arithmetic
                -- on a secret and is refused -- so a charge spell placed in
                -- recharging mode keeps today's fail-open behaviour in combat.
                -- Not an oversight; see DECISIONS.md §20 and task 15.
                show = not ready
                ApplySweep(icon, spellName)
            else
                -- "cooldown" mode: the icon IS the readiness signal, so there is
                -- nothing to sweep -- it simply disappears once spent. This is
                -- the reported bug (Grappling Hook, Swiftmend): currentCharges
                -- is secret in combat, `ready` fails open, and `alpha` (1
                -- normally, the secret charge count itself when the count is
                -- unreadable) does the hiding SetShown cannot -- with no
                -- comparison anywhere. DECISIONS.md §20, task 15.
                show = ready and true or false
                icon.cooldown:Clear()
                icon:SetAlpha(alpha)
            end

            if charges then
                icon.count:SetText(charges)
                icon.count:Show()
            else
                icon.count:Hide()
            end
        end

        icon.wanted = show
        icon:SetShown(show)

        -- Glow only on a visible icon; an alert left running on a hidden frame
        -- keeps animating and pops back the next time the icon shows.
        SetGlow(icon, show and glowEnabled and procced or false)
    end

    self:ApplyLayout()
end

--- @param forceCombat boolean? treat combat as this instead of asking
function CV:ShouldShow(forceCombat)
    if self:IsLegacyMode() then return false end
    if self.previewMode then return true end

    local profile = CV:CurrentProfile()
    if not profile.enabled then return false end
    if next(profile.placements) == nil then return false end

    local inCombat = forceCombat
    if inCombat == nil then inCombat = InCombat() end
    if profile.onlyInCombat and not inCombat then return false end
    return true
end

--- @param forceCombat boolean? passed through to ShouldShow. PLAYER_REGEN_*
--- supplies it because InCombatLockdown() is not guaranteed to have flipped
--- yet while that event is being handled -- the same reason
--- ER:UpdateVisibility is called as UpdateVisibility(true) from its own
--- PLAYER_REGEN_DISABLED handler.
function CV:UpdateVisibility(forceCombat)
    local f = self.container
    if not f then return end

    if not self:ShouldShow(forceCombat) then
        f:Hide()
        self.anchoredToCursor = nil
        -- Hand Blizzard's buff items back the moment the grid stops showing.
        -- They are not our children, so hiding the container does not hide
        -- them -- without this they would hang in mid-air at the coordinates
        -- of a grid nobody can see.
        if self.BlizzBuffs then self.BlizzBuffs:Refresh() end
        return
    end

    local profile = CV:CurrentProfile()
    f:SetScale(profile.scale or 1.0)

    -- The preview tint and the drag handle travel together: both are for
    -- placing the thing, and neither belongs on screen during a pull.
    local editable = self.previewMode or not InCombatLockdown()
    f.previewBG:SetShown(self.previewMode)
    f:EnableMouse(editable and not profile.followCursor)

    f:Show()

    local inCombat = forceCombat
    if inCombat == nil then inCombat = InCombat() end

    -- Only re-anchor on a transition. This runs on a timer now, and
    -- re-issuing ReleaseAnchor every tick would ClearAllPoints out from under
    -- a drag in progress.
    local wantCursor = profile.followCursor and (self.previewMode or inCombat)
    if wantCursor then
        self:UpdateCursorPosition()
        self.anchoredToCursor = true
    elseif self.anchoredToCursor ~= false then
        self:ReleaseAnchor()
        self.anchoredToCursor = false
    end
end

--- Put the profile's chosen grid intersection under the cursor.
---
--- Offsets are divided by the container's own scale because SetPoint measures
--- them in the frame's coordinate space, the same correction the older bars
--- make in ER:UpdateBCVPosition.
function CV:UpdateCursorPosition()
    local f = self.container
    if not f or not f:IsShown() then return end

    local profile = CV:CurrentProfile()
    local scale = f:GetScale()
    if scale == 0 then return end

    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local x = cursorX / uiScale / scale
    local y = cursorY / uiScale / scale

    local cellW, cellH = self:GetCellSize(profile)
    local anchorOffsetX = (profile.anchorCol or 0) * cellW
    local anchorOffsetY = (profile.anchorRow or 0) * cellH

    -- Nudge the whole shape away from the cursor along the diagonal that points
    -- from the anchor towards the shape's bulk, so the icons never sit under
    -- the pointer itself.
    --
    -- Same source as the collapse, on purpose. This decides which side of the
    -- pointer the shape sits on and the collapse packs it back towards the
    -- pointer; when the two derived that separately they disagreed, and the
    -- shape was nudged above the cursor while its columns closed upwards, away
    -- from it. DECISIONS.md 18. Do not inline the test again here.
    local gap = CURSOR_GAP / scale
    local packRight, packDown = Data.ResolveAutoAxes(profile)
    local gapX = packRight and -gap or gap
    local gapY = packDown and gap or -gap

    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        x - anchorOffsetX + gapX,
        y + anchorOffsetY + gapY)
end

--- Back to the saved (dragged) position when the bar stops following the cursor.
function CV:ReleaseAnchor()
    local f = self.container
    if not f then return end

    local profile = CV:CurrentProfile()
    f:ClearAllPoints()
    if profile.point then
        f:SetPoint(profile.point.point, UIParent, profile.point.relPoint, profile.point.x, profile.point.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

--- Forced visibility while the settings page is open, so the player can see the
--- shape they are building without going and pulling something.
--- @param specID number? draw this spec's layout instead of the active one
function CV:SetPreview(enabled, specID)
    self.previewMode = enabled and true or false
    self.overrideSpecID = self.previewMode and specID or nil
    self:Rebuild()
end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

local driver = CreateFrame("Frame", "ThugUI_CooldownViewerDriver")
CV.driver = driver

local elapsedSinceUpdate = 0

driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= UPDATE_INTERVAL then
        elapsedSinceUpdate = 0

        -- Visibility is re-evaluated here unconditionally, and deliberately
        -- BEFORE the IsShown bail-out below. Driving it from PLAYER_REGEN_*
        -- alone means a single missed or mistimed transition leaves the viewer
        -- hidden for the rest of the fight, with nothing able to bring it back:
        -- UpdateState and the cursor path both bail while it is hidden, so the
        -- hidden state becomes self-sustaining. A poll makes wrong states last
        -- 150ms instead of forever.
        if not CV:IsLegacyMode() then
            CV:UpdateVisibility()
            CV:UpdateState()
        end
    end

    if not CV.container or not CV.container:IsShown() then return end

    -- Cursor tracking stays per-frame; anything slower visibly lags the mouse.
    local profile = CV:CurrentProfile()
    if profile.followCursor and (CV.previewMode or InCombat()) then
        CV:UpdateCursorPosition()
    end
end)

-- PLAYER_LOGIN, not ADDON_LOADED: migration reads ThugUI_Config, which
-- EssentialRings fills in from its own ADDON_LOADED handler, and
-- GetSpecialization is not dependable that early either. PLAYER_LOGIN fires
-- after every addon's ADDON_LOADED, so neither ordering question arises.
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterEvent("SPELL_UPDATE_CHARGES")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("UNIT_AURA")
-- Proc glows are synchronous events; polling alone would lag them by up to the
-- update interval, which is exactly the window where a proc matters.
driver:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
driver:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

driver:SetScript("OnEvent", function(_, event, arg1)
    if CV:IsLegacyMode() then
        if CV.container then CV.container:Hide() end
        return
    end

    if event == "PLAYER_LOGIN" then
        CV:Initialize()
        return
    end

    if event == "UNIT_AURA" then
        if arg1 == "player" then CV:UpdateState() end
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "SPELLS_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
    then
        -- Spec change swaps the whole profile, so the icon set is rebuilt from
        -- scratch rather than re-pointed. The settings page follows along:
        -- clearing editSpecID makes it re-default to the spec now active.
        -- Talents change what each category contains and which spells are
        -- overridden, so the linked-spell lookup has to be rebuilt with them.
        Data.InvalidateCooldownInfoCache()

        -- Charge-ness expires with it: a talent can add charges to a spell that
        -- had none, and that decides whether Blizzard draws the cell or we do.
        if CV.BlizzBuffs then CV.BlizzBuffs:ResetChargeCache() end

        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Retry migration for the spec just switched TO. The ECV list is
            -- spell names, and names only resolve for a spec you are actually
            -- in -- which is why the original one-shot pass silently produced
            -- an empty Restoration bar when it happened to run as Guardian.
            Data.MigrateSpec(Data.GetActiveSpecID())
            if CV.Page then
                CV.Page.editSpecID = nil
                CV.Page.selectedKey = nil
            end
        end
        CV:Rebuild()
        if ThugUI.Window then ThugUI.Window:RefreshActivePage() end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- Forced rather than derived: InCombatLockdown() is not reliably
        -- flipped yet while this event is being handled, and guessing wrong
        -- here used to strand the viewer hidden for a whole fight.
        CV:UpdateVisibility(event == "PLAYER_REGEN_DISABLED")
        CV:UpdateState()
        return
    end

    CV:UpdateState()
end)

-- ----------------------------------------------------------------------------
-- Init
-- ----------------------------------------------------------------------------

function CV:Initialize()
    Data.MigrateLegacyBars()
    self:EnsureContainer()
    self:Rebuild()
end

-- Slash command: quick escape hatch back to the old bars, and a way to force a
-- rebuild without a /reload while iterating on a layout.
SLASH_THUGCV1 = "/thugcv"
SlashCmdList["THUGCV"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "legacy" then
        ThugUI_Config.cvUseLegacy = not ThugUI_Config.cvUseLegacy
        local ER = ThugUI.EssentialRings
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:Log("CV", "legacy bars %s",
                ThugUI_Config.cvUseLegacy and "ENABLED" or "disabled")
        end
        if ThugUI_Config.cvUseLegacy then
            if CV.container then CV.container:Hide() end
            print("|cff00ff00ThugUI:|r cooldown viewer switched to the |cffffd100legacy|r ECV/BCV/GCV bars.")
        else
            CV:Rebuild()
            print("|cff00ff00ThugUI:|r cooldown viewer switched to the |cff00ffccgrid|r engine.")
        end
        if ER and ER.UpdateVisibility then ER:UpdateVisibility() end
        return
    end

    -- Pull the current spec's old ECV/BCV/GCV bar onto the grid. "import force"
    -- overwrites a layout that already has icons; plain "import" refuses, so a
    -- fat-fingered command cannot wipe a grid you spent time on.
    if msg == "import" or msg == "import force" then
        local force = (msg == "import force")
        local specID = Data.GetActiveSpecID()
        local profile = Data.GetProfile(specID)

        if next(profile.placements) and not force then
            print("|cff00ff00ThugUI:|r " .. Data.GetSpecName(specID)
                .. " already has a layout. |cffffd100/thugcv import force|r to replace it.")
            return
        end

        if Data.MigrateSpec(specID, true) then
            CV:Rebuild()
            if ThugUI.Window then ThugUI.Window:RefreshActivePage() end
            print("|cff00ff00ThugUI:|r imported the old bar for "
                .. Data.GetSpecName(specID) .. ".")
        else
            print("|cff00ff00ThugUI:|r no old bar exists for "
                .. Data.GetSpecName(specID) .. " (only Balance, Guardian and "
                .. "Restoration ever had one).")
        end
        return
    end

    -- Dump what the Cooldown Manager actually reports for this spec. The
    -- linkedSpellIDs column is the interesting one: an entry that tracks a set
    -- of possible buffs (Roll the Bones) has no aura of its own and is only
    -- findable through that list.
    if msg == "probe" then
        ThugUI_BCVDump = ThugUI_BCVDump or {}
        ThugUI_BCVDump.cooldownViewer = {
            capturedAt = date("%Y-%m-%d %H:%M:%S"),
            spec = Data.GetSpecName(Data.GetActiveSpecID()),
            entries = Data.DumpCooldownViewer(),
        }
        local count = #ThugUI_BCVDump.cooldownViewer.entries
        print(("|cff00ff00ThugUI:|r probed %d cooldown entries into ThugUI_BCVDump. "
            .. "|cffffd100/reload|r to flush it to disk."):format(count))

        -- Anything with linked spells is worth surfacing immediately.
        for _, entry in ipairs(ThugUI_BCVDump.cooldownViewer.entries) do
            if entry.linkedSpellIDs ~= "" then
                print(("  |cff00ffcc%s|r [%s] spellID=%s linked: %s")
                    :format(entry.name or "(no base spell)", entry.category,
                            tostring(entry.spellID), entry.linkedSpellIDs))
            end
        end
        return
    end

    if msg == "rebuild" then
        CV:Rebuild()
        print("|cff00ff00ThugUI:|r cooldown viewer rebuilt.")
        return
    end

    -- Every reason the viewer can decline to draw, in the order ShouldShow
    -- checks them. "It works in preview but not in combat" has half a dozen
    -- possible causes and no visible difference between them; this prints
    -- which one is actually firing.
    if msg == "status" then
        -- Everything status prints also goes into ThugUI_DebugLog, so one
        -- /reload puts the whole readout on disk. Copying it out of the chat
        -- frame by hand was costing a round trip per question, and WoW's own
        -- /chatlog does not help: it records chat EVENTS, and print() writes
        -- straight to the frame without firing one.
        --
        -- Deliberately shadows the global print for this block, so no call site
        -- below can be missed and later drift back to chat-only.
        local print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring((select(i, ...)))
            end
            local line = table.concat(parts, " ")
            _G.print(line)
            if ThugUI.Diagnostics then
                -- Colour escapes are for the chat frame; they make the saved
                -- variable unreadable. Strip them on the way to disk.
                ThugUI.Diagnostics:Log("STATUS", "%s",
                    line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            end
        end

        local specID = Data.GetActiveSpecID()
        local profile = Data.GetActiveProfile()
        local placed = 0
        for _ in pairs(profile.placements) do placed = placed + 1 end

        local function YesNo(value, goodIsTrue)
            local good = goodIsTrue and value or not value
            return (good and "|cff40ff40" or "|cffff4040") .. tostring(value and "yes" or "no") .. "|r"
        end

        print("|cff00ffccThugUI cooldown viewer|r")
        print(("  spec: %s (%s)"):format(Data.GetSpecName(specID), tostring(specID)))
        if not specID then
            print("  |cffff4040No spec ID — edits are not being saved. Relog.|r")
        end
        print("  legacy mode:      " .. YesNo(CV:IsLegacyMode(), false))
        print("  enabled:          " .. YesNo(profile.enabled, true))
        print("  icons placed:     " .. (placed > 0
            and ("|cff40ff40" .. placed .. "|r")
            or "|cffff40400|r"))
        print("  only in combat:   " .. tostring(profile.onlyInCombat)
            .. "   in combat now: " .. YesNo(InCombat(), true))
        print("  follow cursor:    " .. tostring(profile.followCursor))
        print("  preview forced:   " .. tostring(CV.previewMode))
        print("  collapse:         " .. tostring(profile.collapse)
            .. " (" .. Data.ResolveCollapseDirection(profile) .. ")")
        print("  |cffffd100would draw right now: " .. YesNo(CV:ShouldShow(), true) .. "|r")

        if not profile.enabled then
            print("  |cffffd100-> 'Enabled' is off for this spec. Tick it on the "
                .. "Cooldown Viewer page; preview ignores it, combat does not.|r")
        end

        local unknown = {}
        for _, placement in pairs(profile.placements) do
            local info = C_Spell.GetSpellInfo(placement.spellID)
            if not IsSpellAvailable(info and info.name) then
                table.insert(unknown, (info and info.name or placement.spellID))
            end
        end
        if #unknown > 0 then
            print(("  |cffffd100-> %d placed spell(s) do not resolve in this spec and will "
                .. "never draw: %s|r"):format(#unknown, table.concat(unknown, ", ")))
        end
        print("  container shown: " .. tostring(CV.container and CV.container:IsShown()))

        -- Aura-mode icons get their own readout: "buff mode shows nothing" has
        -- three distinct causes -- the entry was not found, it has no linked
        -- spells, or no linked buff is currently up -- and they look identical
        -- on screen.
        local auraIcons = {}
        for _, icon in pairs(CV.icons) do
            if icon.mode == "aura" then table.insert(auraIcons, icon) end
        end

        if #auraIcons > 0 then
            print("  |cff00ffccbuff-mode icons|r")
            for _, icon in ipairs(auraIcons) do
                local spellInfo = C_Spell.GetSpellInfo(icon.spellID)
                local linked = icon.linkedSpellIDs or {}
                local aura, auraSpellID = ResolveAura(icon)

                print(("    %s (%d): %d linked, %s")
                    :format(spellInfo and spellInfo.name or "?", icon.spellID, #linked,
                            aura and ("|cff40ff40active via " .. tostring(auraSpellID) .. "|r")
                                 or "|cffff4040no buff found|r"))

                if #linked == 0 then
                    print("      |cffffd100-> no linked spells: this entry was not matched to a "
                        .. "Cooldown Manager cooldown. Run /thugcv probe.|r")
                elseif not aura then
                    -- Show what we looked for, so a wrong ID set is obvious.
                    local names = {}
                    for _, id in ipairs(linked) do
                        local info = C_Spell.GetSpellInfo(id)
                        table.insert(names, (info and info.name or "?") .. "(" .. id .. ")")
                    end
                    print("      looked for: " .. table.concat(names, ", "))
                end
            end
        end
        return
    end

    -- An unrecognised argument used to fall straight through to opening the
    -- config window, so a mistyped subcommand was indistinguishable from a
    -- working one -- /thugcv diag looked like it had run and just showed the
    -- options menu. Bare /thugcv still opens the window; anything else has to
    -- name itself or say why not.
    if msg ~= "" then
        print("|cff00ff00ThugUI:|r unknown /thugcv command '" .. msg .. "'. Try: "
            .. "|cffffd100status|r (what the viewer thinks it is doing, including "
            .. "buff-mode icons), |cffffd100probe|r, |cffffd100rebuild|r, "
            .. "|cffffd100import|r, |cffffd100import force|r, |cffffd100legacy|r.")
        return
    end

    ThugUI:ToggleOptions("cooldownviewer")
end

return CV
