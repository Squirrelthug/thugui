-- ============================================================================
-- ThugUI: Blizzard buff items in our grid cells
--
-- Takes the item frames out of Blizzard's BuffIconCooldownViewer and anchors
-- each one over the grid cell the player assigned that buff to. Blizzard's
-- untainted code decides whether it is shown, what artwork it uses and how the
-- timer sweeps; ThugUI decides where it sits and how big it is.
--
-- WHY, IN ONE PARAGRAPH
--
-- An addon cannot tell which aura is which during combat. The list comes back,
-- the structs can be indexed, and `aura.spellId` is right there -- as a secret
-- number, and comparing it errors. Every other piece is available; the one
-- operation that would let us say "this aura is that spell" is the deliberate
-- choke point. Measured, not assumed: docs/DECISIONS.md §12 has the table.
-- So our own aura-mode icons cannot work in combat by any route, and the only
-- code on the machine that CAN identify the buff is Blizzard's own.
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

-- Both buff categories, because a placement can come from either: TrackedBuff
-- draws icons and TrackedBar draws bars, and Roll the Bones lives in the
-- second one on this build (see DECISIONS.md on the duplicate entry).
local VIEWER_NAMES = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

BB.adopted = {}   -- our icon frame -> Blizzard item frame
BB.taken = {}     -- Blizzard item frame -> true, for the release pass
BB.lowered = {}   -- our icon frame -> true, for the strata restore pass

-- Everything we need to remember ABOUT a Blizzard frame, kept beside it rather
-- than on it -- see the header. Weak keys so a pooled item that Blizzard
-- discards does not stay alive because we once measured it.
local weak = { __mode = "k" }
local hookedViewers = setmetatable({}, weak)  -- viewer -> true
local baseWidth     = setmetatable({}, weak)  -- item   -> unscaled width, or false
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
local function FitItem(item, iconSize)
    if baseWidth[item] == nil then
        local width = item:GetWidth()
        baseWidth[item] = (width and width > 0) and width or false
    end

    local base = baseWidth[item]
    if base and iconSize then item:SetScale(iconSize / base) end
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

--- Anchor every aura-mode icon's Blizzard counterpart over its cell.
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
            "no Blizzard buff item frames found — is the Cooldown Manager enabled "
            .. "and are these buffs tracked in Edit Mode?")
    end

    wipe(self.adopted)

    for _, icon in pairs(CV.icons) do
        if icon.mode == "aura" and icon.spellID then
            local info = Data.GetCooldownInfoForSpell(icon.spellID)
            local item = info and info.cooldownID and map[info.cooldownID]

            if item then
                local viewer = item:GetParent()
                if viewer then
                    LowerIcon(icon, viewer)
                    stillLowered[icon] = true
                end

                RememberHome(item)
                FitItem(item, iconSize)
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
                            "spell %s: no matching item frame — buff is not in Tracked Buffs or Tracked Bars", spellStr)
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
            "adopted %d Blizzard buff item(s) into grid cells", count)
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
