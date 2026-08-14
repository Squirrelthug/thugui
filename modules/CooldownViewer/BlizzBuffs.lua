-- ============================================================================
-- ThugUI: Blizzard cooldown-viewer items in our grid cells
--
-- Takes the item frames out of Blizzard's cooldown viewers -- the two buff ones
-- and the two cooldown ones -- and anchors each over the grid cell the player
-- assigned that spell to. Blizzard's untainted code decides whether it is shown,
-- what artwork it uses, how the timer sweeps and what charge count it prints;
-- ThugUI decides where it sits and how big it is.
--
-- WHY, IN ONE PARAGRAPH
--
-- Combat hides the values this addon would need. An addon cannot tell which
-- aura is which -- the list comes back, the structs index, `aura.spellId` is
-- right there as a secret number, and comparing it errors. The same wall stands
-- in front of cooldowns: `startTime` is secret so SetCooldown refuses to draw a
-- sweep, and `currentCharges` is secret so "has this spell a charge banked" has
-- no answer. Measured, not assumed: docs/DECISIONS.md §12 has the table, and
-- the charge half was confirmed in game -- Grappling Hook renders correctly out
-- of combat and lies during it. The only code on the machine that can still
-- answer any of these is Blizzard's own, because it is not tainted.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--
-- It does not reparent anything. Anchoring is enough to place a frame, and
-- 12.1 tightens what addons may do to aura frames specifically -- "addons are
-- no longer allowed to reparent aura buttons". Cooldown viewer items are not
-- aura buttons, but staying on the side of the line that needs no permission
-- costs us nothing here.
--
-- It also does not fight Blizzard for the layout. Their RefreshLayout releases
-- every item back to the pool and re-anchors it, so our anchors WILL be
-- overwritten; the answer is to re-apply afterwards, on a hook, rather than to
-- try to prevent it.
--
-- WHAT IT MUST NEVER DO, AND WHY -- read this before adding a line here
--
-- Every write to a Blizzard frame taints that frame, and a tainted frame runs
-- ITS OWN handlers tainted by us. Blizzard's cooldown viewer code then reads
-- fields that are secret under taint (`sourceUnit`, `allowAvailableAlert`,
-- `previousCooldownChargesCount`) and throws inside its own OnEvent. The throw
-- aborts RefreshLayout mid-ReleaseAll, the item pool empties, and the viewer is
-- dead until /reload. That was measured, not theorised: docs/DECISIONS.md §15
-- has the stacks. So, specifically:
--
--   * no `item.__anything = x` -- a field set on their table taints the table.
--     Bookkeeping lives in the weak side tables below instead.
--   * no SetFrameStrata/SetFrameLevel on the viewer. It is an Edit Mode system
--     frame. Our own icon is lowered to meet it instead.
--   * no calling their methods (`viewer:RefreshLayout()`) from our stack.
--
-- What is left is the anchor and the scale on the pooled item, which is the
-- feature itself and cannot be avoided while the design is "their frame, our
-- cell". hooksecurefunc is fine -- it exists to be taint-safe.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local CV = ThugUI.CooldownViewer
if not CV then return end

local BB = {}
CV.BlizzBuffs = BB

-- Every viewer a placement can be drawn from.
--
-- Both buff categories, because a placement can come from either: TrackedBuff
-- draws icons and TrackedBar draws bars, and Roll the Bones lives in the
-- second one on this build (see DECISIONS.md on the duplicate entry). Essential
-- and Utility followed for the cooldowns we cannot render in combat either --
-- Maul sits on Essential and Grappling Hook on Utility, so both are needed.
--
-- These are BLIZZARD's global names. Ours are all ThugUI_-prefixed, and have
-- been since the collision that killed Edit Mode for a session: ER:CreateECV
-- once created its bar as a bare "EssentialCooldownViewer", and this very
-- lookup would have found our frame instead of theirs. DECISIONS.md §15.
local VIEWER_NAMES = {
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

BB.adopted = {}   -- our icon frame -> Blizzard item frame
BB.taken = {}     -- Blizzard item frame -> true, for the release pass
BB.lowered = {}   -- our icon frame -> true, for the strata restore pass

-- Everything we need to remember ABOUT a Blizzard frame, kept beside it rather
-- than on it -- see the header. Weak keys so a pooled item that Blizzard
-- discards does not stay alive because we once measured it.
local weak = { __mode = "k" }
local hookedViewers = setmetatable({}, weak)  -- viewer -> true
-- Only ever holds a real measured width. A falsy entry is absent rather than
-- stored, so an item measured too early is retried on the next pass instead of
-- being written off for its lifetime.
local baseWidth     = setmetatable({}, weak)  -- item   -> unscaled width
local homeAnchor    = setmetatable({}, weak)  -- item   -> the anchor Blizzard gave it
local iconStrata    = setmetatable({}, weak)  -- our icon -> strata before we lowered it

--- Combat, or test mode standing in for it. Mirrors the identical helper in
--- Core.lua rather than reaching for it: that one is file-local, and both halves
--- of the addon have to agree about what "in combat" means or the measurement
--- below would be keyed on a different answer from the decision it measures.
local function InCombat()
    local ER = ThugUI.EssentialRings
    if ER and ER.IsInCombat then return ER:IsInCombat() end
    return InCombatLockdown() or UnitAffectingCombat("player")
end

--- "Name (ID n)" for the log lines, falling back to the bare ID. A placement
--- can point at a passive, which answers no by-name lookup and so has no
--- spellName -- Opportunity 279876 is exactly that case.
local function SpellLabel(icon)
    if icon.spellName then
        return ("%s (ID %s)"):format(tostring(icon.spellName), tostring(icon.spellID))
    end
    return ("ID %s"):format(tostring(icon.spellID))
end

function BB:IsEnabled()
    -- On by default: this is the only thing that makes an aura-mode icon work
    -- in combat at all. The switch exists because every other Blizzard-facing
    -- feature in this addon has one, and because "put it back the way it was"
    -- has to stay one click away.
    return ThugUI_Config.cvUseBlizzardBuffs ~= false
end

-- ----------------------------------------------------------------------------
-- Which placements Blizzard should draw
-- ----------------------------------------------------------------------------

-- spellID -> boolean, "does this spell have more than one charge".
--
-- Cached because the answer is only trustworthy OUT of combat: maxCharges is a
-- secret number mid-fight, and this decides whether a cell is adopted at all,
-- so a wrong answer latched during a fight would hold for the rest of the
-- session. An unreadable answer is deliberately NOT stored -- absent means
-- "ask again next pass", which is the same mistake FitItem's baseWidth once
-- made by caching a falsy measurement for the life of the item.
local chargeSpell = {}

--- Called from Core when the cooldown info cache is invalidated. A talent can
--- add charges to a spell that had none, so the two have to expire together.
function BB:ResetChargeCache()
    wipe(chargeSpell)
end

--- true / false / nil, where nil means "cannot tell yet, ask again".
---
--- Queried BY NAME for the reason in DECISIONS.md §5 -- the name resolves to
--- whichever version of the spell is currently talented -- falling back to the
--- ID for a placement pointing at a passive, which answers no by-name lookup.
local function DetectChargeSpell(icon)
    local query = icon.spellName or icon.spellID
    if not query then return false end

    local ok, info = pcall(C_Spell.GetSpellCharges, query)
    if not ok or not info then return false end

    -- issecretvalue FIRST: comparing a secret against nil is itself a
    -- comparison, and that is the operation that errors.
    local maxCharges = info.maxCharges
    if issecretvalue and issecretvalue(maxCharges) then return nil end
    if maxCharges == nil then return false end
    return maxCharges > 1
end

function BB:IsChargeSpell(icon)
    local id = icon.spellID
    if not id then return false end

    local known = chargeSpell[id]
    if known ~= nil then return known end

    local detected = DetectChargeSpell(icon)
    if detected == nil then return false end
    chargeSpell[id] = detected
    return detected
end

--- Should Blizzard draw this cell instead of us?
---
--- The rule is "everything our own code provably cannot render during combat",
--- and there are exactly two such cases:
---
---   * **aura mode** -- an addon cannot identify an aura in combat by any
---     route. DECISIONS.md §12. This is what the module was originally built
---     for and is unchanged.
---   * **always mode** -- the radial sweep IS the readiness signal there, and
---     SetCooldown refuses the secret startTime combat hands us, so the icon
---     draws and never sweeps. It reads as permanently ready.
---
--- **A multi-charge spell used to be a third case here (DECISIONS.md §19,
--- task 14): currentCharges is secret in combat, so IsSpellReady used to fail
--- open and the icon showed whether or not a charge was banked, so the cell was
--- handed to Blizzard rather than draw a lie. DECISIONS.md §20 measured a route
--- that does not need to read the count at all -- SetAlpha accepts a secret and
--- clamps it to 0-1, so IsSpellReady (Core.lua) now hands back the secret
--- currentCharges as an alpha and a spent charge spell hides itself with no
--- comparison anywhere. Charge spells are ours to draw again, task 15.**
---
--- The exclusions below are no longer about charges at all -- they apply to a
--- charge spell and an ordinary spell exactly alike, because neither is ever
--- reached by the removed charge check any more:
---
---   * an ordinary cooldown-mode spell (charge or not) is NOT adopted. isActive
---     is readable in combat, so our own rendering is already right, and
---     adopting would trade away the proc glow and the hide-when-spent
---     behaviour for nothing.
---   * **proc mode is NOT adopted.** Its whole point is "show only while the
---     proc is up", and Blizzard's item knows nothing about that -- it would
---     sit there permanently and the mode would lose the one behaviour it
---     exists for.
---   * **recharging mode is NOT adopted either, task 14.** For a spell, isActive
---     is readable in combat, same reasoning as an ordinary cooldown-mode spell,
---     just inverted. For an item nothing here is secret at all.
function BB:ShouldAdopt(icon)
    if not icon.spellID then return false end
    if icon.mode == "proc" then return false end
    if icon.mode == "recharging" then return false end
    if icon.mode == "aura" or icon.mode == "always" then return true end
    return false
end

-- ----------------------------------------------------------------------------
-- Finding Blizzard's frames
-- ----------------------------------------------------------------------------

local function Viewers()
    local out = {}
    for _, name in ipairs(VIEWER_NAMES) do
        local frame = _G[name]
        if frame then out[#out + 1] = frame end
    end
    return out
end

--- Every live item frame in a viewer, whatever the client gives us access to.
---
--- The pool is the direct answer and `GetItemFrames` is the documented one, so
--- try the pool and fall back. Both are Blizzard internals; a build that
--- renames either should degrade to "no buffs adopted" rather than erroring.
local function ItemFrames(viewer)
    local out = {}

    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        local ok = pcall(function()
            for item in pool:EnumerateActive() do out[#out + 1] = item end
        end)
        if ok and #out > 0 then return out end
    end

    if viewer.GetItemFrames then
        local ok, frames = pcall(viewer.GetItemFrames, viewer)
        if ok and type(frames) == "table" then
            for _, item in ipairs(frames) do out[#out + 1] = item end
        end
    end

    return out
end

--- cooldownID -> item frame, across every buff viewer.
---
--- Cooldown IDs are plain numbers even in combat -- the CooldownViewer
--- structures carry no secret predicates at all -- which is what makes this
--- matching possible when matching on the aura itself is not.
function BB:ItemsByCooldownID()
    local map = {}

    for _, viewer in ipairs(Viewers()) do
        self:HookViewer(viewer)

        for _, item in ipairs(ItemFrames(viewer)) do
            if item.GetCooldownID then
                local ok, id = pcall(item.GetCooldownID, item)
                if ok and id then map[id] = item end
            end
        end
    end

    return map
end

--- Blizzard's pooled item frame for one cooldownID, if one currently exists.
--- Read-only, and public: callers outside the adoption pass use this too --
--- Data.CategoryEntry (task 18) resolves a category placement's name and icon
--- from it, the same way BB:Apply resolves an adopted spell's. Rebuilds the
--- whole map on every call rather than caching it, matching BB:Apply, which
--- already does the same on every pass -- the pool is small (a handful of
--- items across four viewers) and this is not called every frame.
function BB:ItemForCooldownID(cooldownID)
    if not cooldownID then return nil end
    return self:ItemsByCooldownID()[cooldownID]
end

-- ----------------------------------------------------------------------------
-- Placing them
-- ----------------------------------------------------------------------------

--- Items draw at their PARENT's strata, and we are not reparenting them, so
--- without help the buff sits underneath the cell it is standing in -- which the
--- player hit immediately with the combo pips and had to work around by moving
--- the grid.
---
--- The old fix lifted their viewer to meet our grid. That taints an Edit Mode
--- system frame, so it is now done from our side: OUR icon drops to the viewer's
--- strata, which we may read freely. Their item carries frameLevel 512 within
--- that strata (CooldownViewer.xml), so it clears our icon comfortably without
--- either of us naming a number.
local function LowerIcon(icon, viewer)
    if iconStrata[icon] == nil then
        iconStrata[icon] = icon:GetFrameStrata() or false
    end
    icon:SetFrameStrata(viewer:GetFrameStrata())
end

local function RestoreIcon(icon)
    local strata = iconStrata[icon]
    if strata then icon:SetFrameStrata(strata) end
    iconStrata[icon] = nil
end

--- Where Blizzard had the item before we moved it.
---
--- Recorded so releasing can put it back with a SetPoint of our own. The old
--- code called their RefreshLayout to do the same job, which ran their function
--- on our stack -- the exact thing that kills the viewer.
local function RememberHome(item)
    if homeAnchor[item] ~= nil then return end

    local point, relativeTo, relativePoint, x, y = item:GetPoint()
    homeAnchor[item] = point and { point, relativeTo, relativePoint, x, y } or false
end

--- Size the item to the cell by scale rather than SetSize: the item's own
--- internal anchors are laid out against its configured size, and resizing it
--- leaves the cooldown swipe and the stack text in the wrong places.
---
--- THE SCALE IS WORKED OUT IN SCREEN SPACE, not in our grid's numbers. The item
--- is only *anchored* to our cell -- the adoption pass below leaves it parented
--- to Blizzard's viewer on purpose -- so unlike our own icons it never inherits
--- `profile.scale`. Dividing the two effective scales cancels UIParent out of
--- both sides and absorbs whatever Edit Mode did to their viewer, which leaves
--- the item the same on-screen size as an ordinary cooldown icon beside it.
---
--- This was invisible for as long as the only testbed was a profile at scale 1,
--- where the two coordinate spaces coincide. A resto profile at scale 0.6 drew
--- its adopted buffs 1/0.6 too large while every cooldown icon around them was
--- correct -- same code, different profile. That is the whole of why the rogue
--- looked right and the druid did not.
local function FitItem(item, iconSize, cell)
    -- Re-measured until it answers, deliberately. This used to cache `false`
    -- for a width of 0 and guard on `~= nil`, which latched that answer for the
    -- life of the item: SetScale was then never called at all and the item kept
    -- Blizzard's native size inside a cell sized for ours. An item measured
    -- before their layout has run is exactly the case that produced it.
    if not baseWidth[item] then
        local width = item:GetWidth()
        if not width or width <= 0 then return end
        baseWidth[item] = width
    end

    if not iconSize or not cell then return end

    local parent = item:GetParent()
    local theirs = (parent and parent:GetEffectiveScale()) or 1
    local ours = cell:GetEffectiveScale() or 1
    if theirs <= 0 then return end

    local scale = (iconSize * ours) / (baseWidth[item] * theirs)
    item:SetScale(scale)

    -- The numbers behind one fit, so a wrong size on screen can be read back
    -- from disk instead of guessed at. Once per session: ten items a pass and
    -- several passes a session would bury everything else in the log.
    if ThugUI.Diagnostics then
        ThugUI.Diagnostics:LogOnce("blizzbuffs-fit", "CVBUFF",
            "fit: base=%.1f icon=%d ours=%.3f theirs=%.3f -> scale=%.3f",
            baseWidth[item], iconSize, ours, theirs, scale)
    end
end

--- Hand one item back to Blizzard.
local function ReleaseItem(item)
    if baseWidth[item] ~= nil then
        item:SetScale(1)
        baseWidth[item] = nil
    end

    local home = homeAnchor[item]
    if home then
        item:ClearAllPoints()
        item:SetPoint(home[1], home[2], home[3], home[4], home[5])
    end
    homeAnchor[item] = nil
end

-- ----------------------------------------------------------------------------
-- The pass
-- ----------------------------------------------------------------------------

function BB:AdoptedItem(icon)
    return self.adopted[icon]
end

--- Is Blizzard's item currently on screen? true, false, or NIL FOR "cannot tell".
---
--- Three states, not two, and the third is the point. Blizzard's own code hides
--- the item when the buff drops, so its shown state IS the answer to "is the
--- buff up" -- the one question an addon cannot ask directly (DECISIONS.md §12).
--- But when we cannot read it, "hidden" and "unknown" need opposite handling:
--- unknown must reserve the cell, because collapsing a cell whose buff is
--- actually up leaves their item anchored to our hidden icon, drawing at a stale
--- coordinate on top of a neighbour. A boolean return would merge those two.
---
--- Read-only, deliberately. Reading a Blizzard frame is free; writing to one is
--- what killed the cooldown viewer for a session (DECISIONS.md §15).
---
--- The secret screen is not defensive noise. CooldownViewerItemMixin:UpdateShownState
--- calls SetShown(self:ShouldBeShown()), and for a buff item that boolean
--- descends from CooldownViewerBuffItemMixin:IsExpired, which compares
--- auraData.expirationTime <= GetTime(). expirationTime is secret in combat, and
--- this project has already measured secrecy propagating through operations
--- (ThugUI_DebugLog.secrets: EvaluateColorValue(secret bool) -> SECRET number).
--- So IsShown() may well hand us a secret boolean mid-fight. Whether it actually
--- does is unmeasured -- BB:Apply now logs it -- and either answer is handled
--- here without a further change.
function BB:ItemIsShown(item)
    if not item or not item.IsShown then return nil end

    local ok, shown = pcall(item.IsShown, item)
    if not ok then return nil end

    -- No screening function means we cannot prove the value is safe to touch,
    -- so we decline to trust it rather than compare and hope.
    if not issecretvalue then return nil end
    if issecretvalue(shown) then return nil end

    return shown and true or false
end

--- Give everything back and forget it.
function BB:Release()
    if not next(self.adopted) and not next(self.taken) and not next(self.lowered) then
        return
    end

    for item in pairs(self.taken) do ReleaseItem(item) end
    for icon in pairs(self.lowered) do RestoreIcon(icon) end

    wipe(self.adopted)
    wipe(self.taken)
    wipe(self.lowered)
end

--- Anchor the Blizzard counterpart of every adoptable icon over its cell.
--- BB:ShouldAdopt decides which those are, and says why.
function BB:Apply()
    local container = CV.container

    -- Nothing to attach to, or nothing that would be visible: give the buffs
    -- back so they appear wherever Edit Mode put them, rather than stranding
    -- them at the coordinates of a hidden grid.
    if not self:IsEnabled() or not container or not container:IsShown() then
        self:Release()
        return
    end

    local Data = CV.Data
    if not Data then return end

    local profile = CV:CurrentProfile()
    local _, _, iconSize = CV:GetCellSize(profile)

    local map = self:ItemsByCooldownID()
    local stillTaken, stillLowered = {}, {}
    local count = 0

    -- Said out loud, once, because the failure is otherwise invisible: with the
    -- Cooldown Manager switched off in the game's own options there are no item
    -- frames to adopt, and an empty cell looks exactly like a broken addon.
    if next(map) == nil and ThugUI.Diagnostics then
        ThugUI.Diagnostics:LogOnce("blizzbuffs-no-items", "CVBUFF",
            "no Blizzard cooldown-viewer item frames found — is the Cooldown Manager "
            .. "enabled and are these spells tracked in Edit Mode?")
    end

    wipe(self.adopted)

    for _, icon in pairs(CV.icons) do
        if self:ShouldAdopt(icon) then
            local info = Data.GetCooldownInfoForSpell(icon.spellID)
            local item = info and info.cooldownID and map[info.cooldownID]

            if item then
                local viewer = item:GetParent()
                if viewer then
                    LowerIcon(icon, viewer)
                    stillLowered[icon] = true
                end

                RememberHome(item)
                -- The cell goes through so the fit can compare our effective
                -- scale against theirs; the item never becomes its child.
                FitItem(item, iconSize, icon)
                item:ClearAllPoints()
                item:SetPoint("CENTER", icon, "CENTER", 0, 0)

                self.adopted[icon] = item
                stillTaken[item] = true
                count = count + 1

                -- The measurement behind the collapse decision in
                -- CV:UpdateState. Whether Blizzard's IsShown() survives combat
                -- as a plain boolean decides whether an adopted cell can ever
                -- collapse accurately mid-fight, or must always be reserved;
                -- today we reserve on a guess. One item per pass, not all ten.
                --
                -- Combat is in the KEY, not just the message. An out-of-combat
                -- line logged first would otherwise suppress the in-combat one,
                -- which is the single line this exists to produce -- the same
                -- mistake already made and fixed in Core.lua's GetPlayerCastAura.
                if count == 1 and ThugUI.Diagnostics then
                    local inCombat = InCombat()
                    local shown = self:ItemIsShown(item)
                    ThugUI.Diagnostics:LogOnce(
                        ("blizzbuffs-shown-readable-%s"):format(tostring(inCombat)),
                        "CVBUFF", "spell %s: item IsShown %s (combat=%s)",
                        SpellLabel(icon),
                        shown == nil and "unreadable" or ("readable = " .. tostring(shown)),
                        tostring(inCombat))
                end
            else
                if ThugUI.Diagnostics then
                    local spellStr = SpellLabel(icon)
                    if not info then
                        ThugUI.Diagnostics:LogOnce(("blizzbuffs-no-info-%s"):format(tostring(icon.spellID)), "CVBUFF",
                            "spell %s: no Cooldown Manager entry", spellStr)
                    elseif not info.cooldownID then
                        ThugUI.Diagnostics:LogOnce(("blizzbuffs-no-cdid-%s"):format(tostring(icon.spellID)), "CVBUFF",
                            "spell %s: entry has no cooldown ID", spellStr)
                    else
                        ThugUI.Diagnostics:LogOnce(("blizzbuffs-no-item-%s"):format(tostring(icon.spellID)), "CVBUFF",
                            "spell %s: no matching item frame — it is not in Tracked Buffs, Tracked Bars, "
                            .. "Essential Cooldowns or Utility Cooldowns", spellStr)
                    end
                end
            end
        end
    end

    -- Anything we held last pass and do not hold now goes back untouched.
    for item in pairs(self.taken) do
        if not stillTaken[item] then ReleaseItem(item) end
    end
    for icon in pairs(self.lowered) do
        if not stillLowered[icon] then RestoreIcon(icon) end
    end
    self.taken, self.lowered = stillTaken, stillLowered

    -- Once a session, and only the first time it succeeds: this is the line
    -- that says the feature is actually live, in the same spirit as the
    -- linked-spell count in the state snapshot.
    if count > 0 and ThugUI.Diagnostics then
        ThugUI.Diagnostics:LogOnce("blizzbuffs-adopted", "CVBUFF",
            "adopted %d Blizzard cooldown-viewer item(s) into grid cells", count)
    end
end

--- Re-apply after Blizzard has finished its own pass.
---
--- Deferred by a frame rather than run inline, for two reasons: their
--- RefreshLayout calls Layout, so an inline hook would run our anchoring in the
--- middle of theirs and immediately be overwritten; and several events can fire
--- in one frame, which would otherwise mean several full passes.
function BB:Queue()
    if self.queued then return end
    self.queued = true

    if not C_Timer or type(C_Timer.After) ~= "function" then
        self.queued = false
        self:Refresh()
        return
    end

    C_Timer.After(0, function()
        self.queued = false
        self:Refresh()
    end)
end

function BB:Refresh()
    -- Our own SetPoint calls can provoke a layout pass, which is hooked, which
    -- would call back into here. Guarded rather than made re-entrant, because
    -- the second pass would have nothing new to do.
    if self.applying then return end
    self.applying = true
    local ok, err = pcall(function() self:Apply() end)
    if not ok and ThugUI.Diagnostics then
        pcall(function()
            ThugUI.Diagnostics:LogOnce(("blizzbuffs-err-%s"):format(tostring(err)), "CVBUFF",
                "Apply failed: %s", tostring(err))
        end)
    end
    self.applying = false
end

function BB:HookViewer(viewer)
    if hookedViewers[viewer] then return end
    hookedViewers[viewer] = true

    if type(viewer.RefreshLayout) == "function" then
        hooksecurefunc(viewer, "RefreshLayout", function() BB:Queue() end)
    end

    -- The layout frame is usually the viewer itself, but ask rather than assume
    -- -- GetItemContainerFrame exists precisely so it can differ.
    local container = viewer
    if type(viewer.GetItemContainerFrame) == "function" then
        local ok, frame = pcall(viewer.GetItemContainerFrame, viewer)
        if ok and frame then container = frame end
    end

    if container ~= viewer and type(container.Layout) == "function" then
        hooksecurefunc(container, "Layout", function() BB:Queue() end)
    elseif type(viewer.Layout) == "function" then
        hooksecurefunc(viewer, "Layout", function() BB:Queue() end)
    end
end

-- ----------------------------------------------------------------------------
-- Events
--
-- Blizzard rebuilds the viewer on spec and talent changes without necessarily
-- calling anything we have hooked, so the same triggers the grid rebuilds on
-- are worth listening to directly.
-- ----------------------------------------------------------------------------

local driver = CreateFrame("Frame", "ThugUI_BlizzBuffsDriver")
BB.driver = driver

driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")

driver:SetScript("OnEvent", function() BB:Queue() end)

return BB
