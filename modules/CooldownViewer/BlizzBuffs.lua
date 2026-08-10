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
-- costs us nothing here. Frame strata is nudged on the viewer instead, which
-- is one revertible property on one frame.
--
-- It also does not fight Blizzard for the layout. Their RefreshLayout releases
-- every item back to the pool and re-anchors it, so our anchors WILL be
-- overwritten; the answer is to re-apply afterwards, on a hook, rather than to
-- try to prevent it.
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

--- Remember what we changed, once, so it can be handed back exactly.
local function RememberViewer(viewer)
    if viewer.__thugStrata == nil then
        viewer.__thugStrata = viewer:GetFrameStrata()
        viewer.__thugLevel = viewer:GetFrameLevel()
    end
end

--- Items draw at their PARENT's strata, and we are not reparenting them, so the
--- viewer is what has to be lifted above the grid. Without this the buff icon
--- sits underneath our own icons -- which the player hit immediately with the
--- combo pips and had to work around by moving the grid.
local function LiftViewer(viewer, container)
    RememberViewer(viewer)
    viewer:SetFrameStrata(container:GetFrameStrata())
    viewer:SetFrameLevel((container:GetFrameLevel() or 10) + 5)
end

local function RestoreViewer(viewer)
    if viewer.__thugStrata then
        viewer:SetFrameStrata(viewer.__thugStrata)
        viewer:SetFrameLevel(viewer.__thugLevel or 1)
    end
    -- Puts every item back where Blizzard's own layout wants it, which is also
    -- where the player put the bar in Edit Mode.
    if viewer.RefreshLayout then pcall(viewer.RefreshLayout, viewer) end
end

--- Size the item to the cell by scale rather than SetSize: the item's own
--- internal anchors are laid out against its configured size, and resizing it
--- leaves the cooldown swipe and the stack text in the wrong places.
local function FitItem(item, iconSize)
    if item.__thugBaseWidth == nil then
        local width = item:GetWidth()
        item.__thugBaseWidth = (width and width > 0) and width or false
    end

    local base = item.__thugBaseWidth
    if base and iconSize then item:SetScale(iconSize / base) end
end

--- Hand one item back to Blizzard.
local function ReleaseItem(item)
    if item.__thugBaseWidth ~= nil then
        item:SetScale(1)
        item.__thugBaseWidth = nil
    end
end

-- ----------------------------------------------------------------------------
-- The pass
-- ----------------------------------------------------------------------------

function BB:AdoptedItem(icon)
    return self.adopted[icon]
end

--- Give everything back and forget it.
function BB:Release()
    if not next(self.adopted) and not self.lifted then return end

    for item in pairs(self.taken) do ReleaseItem(item) end
    wipe(self.adopted)
    wipe(self.taken)

    if self.lifted then
        self.lifted = false
        for _, viewer in ipairs(Viewers()) do RestoreViewer(viewer) end
    end
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
    local stillTaken = {}
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
                    LiftViewer(viewer, container)
                    self.lifted = true
                end

                FitItem(item, iconSize)
                item:ClearAllPoints()
                item:SetPoint("CENTER", icon, "CENTER", 0, 0)

                self.adopted[icon] = item
                stillTaken[item] = true
                count = count + 1
            end
        end
    end

    -- Anything we held last pass and do not hold now goes back untouched.
    for item in pairs(self.taken) do
        if not stillTaken[item] then ReleaseItem(item) end
    end
    self.taken = stillTaken

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
    pcall(function() self:Apply() end)
    self.applying = false
end

function BB:HookViewer(viewer)
    if viewer.__thugHooked then return end
    viewer.__thugHooked = true

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
