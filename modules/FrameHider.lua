-- ============================================================================
-- ThugUI: Frame Hider Module
-- Hides unwanted default UI elements (ported from SqrlHide)
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local FrameHider = {}
ThugUI.FrameHider = FrameHider

-- Track what we've already hidden so we don't double-apply
FrameHider.applied = {}

-- ============================================================================
-- HIDE FUNCTIONS
-- ============================================================================

-- Permanently disable the Objective Tracker frame
function FrameHider:HideObjectiveTracker()
    if self.applied.objectiveTracker then return end
    if not ObjectiveTrackerFrame then return end

    ObjectiveTrackerFrame:UnregisterAllEvents()
    ObjectiveTrackerFrame.Show = function() end
    ObjectiveTrackerFrame:Hide()
    ObjectiveTrackerFrame:SetAlpha(0)
    ObjectiveTrackerFrame:EnableMouse(false)
    ObjectiveTrackerFrame:SetClampedToScreen(false)
    ObjectiveTrackerFrame:SetPoint("TOPLEFT", -5000, -5000)

    if ObjectiveTrackerFrame.AccountSettings then
        ObjectiveTrackerFrame.AccountSettings.allowDrag = false
        ObjectiveTrackerFrame.AccountSettings.enabled = false
    end

    self.applied.objectiveTracker = true
end

-- Hide the stance bar via state driver
function FrameHider:HideStanceBar()
    if self.applied.stanceBar then return end
    if not StanceBar then return end

    RegisterStateDriver(StanceBar, "visibility", "hide")
    self.applied.stanceBar = true
end

-- Hide bag buttons (backpack, reagent bag, expand toggle)
function FrameHider:HideBagButtons()
    if self.applied.bagButtons then return end

    if MainMenuBarBackpackButton then
        RegisterStateDriver(MainMenuBarBackpackButton, "visibility", "hide")
    end
    if CharacterReagentBag0Slot then
        RegisterStateDriver(CharacterReagentBag0Slot, "visibility", "hide")
    end
    if BagBarExpandToggle then
        RegisterStateDriver(BagBarExpandToggle, "visibility", "hide")
    end

    self.applied.bagButtons = true
end

-- Hide the player character frame (portrait, health, mana)
function FrameHider:HideCharacterFrame()
    if self.applied.characterFrame then return end
    if not PlayerFrame then return end

    PlayerFrame:UnregisterAllEvents()
    PlayerFrame.Show = function() end
    PlayerFrame:Hide()
    PlayerFrame:SetAlpha(0)
    PlayerFrame:EnableMouse(false)
    PlayerFrame:SetClampedToScreen(false)
    PlayerFrame:SetPoint("TOPLEFT", -5000, -5000)

    self.applied.characterFrame = true
end

-- Fix tooltip anchoring for compact unit frame (party/raid) auras
-- Redirects cursor-anchored tooltips to the Edit Mode anchor position
function FrameHider:FixTooltipAnchor()
    if self.applied.tooltipAnchor then return end
    if not GameTooltip then return end

    local origSetOwner = GameTooltip.SetOwner
    local redirecting = false

    local function IsCompactFrameChild(frame)
        local parent = frame and frame:GetParent()
        for i = 1, 5 do
            if not parent then return false end
            if parent.displayedUnit then return true end
            parent = parent:GetParent()
        end
        return false
    end

    GameTooltip.SetOwner = function(tip, owner, anchor, ofsX, ofsY)
        if not redirecting
           and owner
           and anchor
           and anchor ~= "ANCHOR_NONE"
           and IsCompactFrameChild(owner)
        then
            redirecting = true
            GameTooltip_SetDefaultAnchor(tip, owner)
            redirecting = false
            return
        end
        return origSetOwner(tip, owner, anchor, ofsX, ofsY)
    end

    self.applied.tooltipAnchor = true
end

-- Make the Prey Crystal frame (UIWidgetPowerBarContainerFrame) draggable
-- and persist its position across sessions via ThugUI_Config.preyCrystalPoint
function FrameHider:MakePreyCrystalMovable()
    if self.applied.preyCrystal then return end

    local frame = UIWidgetPowerBarContainerFrame
    if not frame then
        -- Frame may not exist yet (created by Blizzard widget system).
        -- Watch for it on PLAYER_ENTERING_WORLD / widget updates.
        if not self.preyCrystalWatcher then
            local w = CreateFrame("Frame")
            w:RegisterEvent("PLAYER_ENTERING_WORLD")
            w:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
            w:SetScript("OnEvent", function(watcher)
                if UIWidgetPowerBarContainerFrame then
                    FrameHider:MakePreyCrystalMovable()
                    watcher:UnregisterAllEvents()
                end
            end)
            self.preyCrystalWatcher = w
        end
        return
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")

    frame:HookScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self.thugUIMoving = true
            self:StartMoving()
        end
    end)

    frame:HookScript("OnDragStop", function(self)
        self.thugUIMoving = false
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ThugUI_Config.preyCrystalPoint = {
            point = point, relPoint = relPoint, x = x, y = y,
        }
    end)

    -- Prevent Blizzard layout from overriding saved position
    local isRepositioning = false
    hooksecurefunc(frame, "SetPoint", function(self)
        if isRepositioning or self.thugUIMoving then return end
        local saved = ThugUI_Config.preyCrystalPoint
        if saved then
            isRepositioning = true
            self:ClearAllPoints()
            self:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
            isRepositioning = false
        end
    end)

    -- Apply saved position now
    local saved = ThugUI_Config.preyCrystalPoint
    if saved then
        frame:ClearAllPoints()
        frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    end

    self.applied.preyCrystal = true
end

-- ============================================================================
-- APPLY ALL SETTINGS
-- ============================================================================

function FrameHider:ApplyAll()
    if ThugUI_Config.hideObjectiveTracker then
        self:HideObjectiveTracker()
    end
    if ThugUI_Config.hideStanceBar then
        self:HideStanceBar()
    end
    if ThugUI_Config.hideBagButtons then
        self:HideBagButtons()
    end
    if ThugUI_Config.hideCharacterFrame then
        self:HideCharacterFrame()
    end
    if ThugUI_Config.fixTooltipAnchor then
        self:FixTooltipAnchor()
    end
    if ThugUI_Config.movePreyCrystal then
        self:MakePreyCrystalMovable()
    end
end

-- FrameHider:ApplyAll() is called from EssentialRings.lua during ADDON_LOADED
-- after ThugUI_Config defaults have been initialized.
