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

-- NOTE: Objective Tracker visibility and anchoring belong to the OrbAnchors
-- module now (modules/OrbAnchors.lua), which toggles it from the Objectives orb
-- and persists the state in ThugUIDB. The empty HideObjectiveTracker stub that
-- used to sit here has been removed -- nothing called it.

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
--
-- PlayerFrame is a SecureUnitButton. Overwriting a method on it (the old
-- `PlayerFrame.Show = function() end`) or repositioning it taints the frame,
-- and that taint surfaces later as "Interface action failed because of an
-- AddOn: ThugUI" the first time Blizzard touches PlayerFrame in combat.
--
-- The secure route is the visibility state driver. Unregistering the frame's
-- events first stops PlayerFrame_Update from calling Show() between state
-- evaluations, so the two together keep it down without ever tainting it.
function FrameHider:HideCharacterFrame()
    if self.applied.characterFrame then return end
    if not PlayerFrame then return end

    PlayerFrame:UnregisterAllEvents()
    RegisterStateDriver(PlayerFrame, "visibility", "hide")

    self.applied.characterFrame = true
end

-- NOTE: A tooltip-anchor fix for Blizzard's compact-frame auras used to live
-- here. It was dropped when ThugUI shipped its own raid frames, which owned
-- their aura icons outright and simply never wired a tooltip to them. Those
-- raid frames have since been removed too, because the tooltip problem is now
-- handled outside ThugUI. Do not re-add a tooltip fix here casually.

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
    if ThugUI_Config.hideStanceBar then
        self:HideStanceBar()
    end
    if ThugUI_Config.hideBagButtons then
        self:HideBagButtons()
    end
    if ThugUI_Config.hideCharacterFrame then
        self:HideCharacterFrame()
    end
    if ThugUI_Config.movePreyCrystal then
        self:MakePreyCrystalMovable()
    end
end

-- FrameHider:ApplyAll() is called from EssentialRings.lua during ADDON_LOADED
-- after ThugUI_Config defaults have been initialized.
