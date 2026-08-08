-- ============================================================================
-- ThugUI: Resource Ring
--
-- A radial resource meter sharing the cast ring's band around the cursor. The
-- cast sweep draws over the top of it, so one ring of screen space carries two
-- readouts: how full you are, and how far through a cast you are.
--
-- WHY A SEPARATE FILE
--
-- The cursor rings in modules/EssentialRings.lua have worked for months. This
-- attaches to the same ThugUI_CursorFrame and borrows the cast ring's geometry
-- but owns its own frame, events and config keys, so it can be switched off
-- without touching any of that.
--
-- HOLDING A STATIC ARC
--
-- Cooldown frames animate by design; a resource level is a fixed fraction.
-- SetCooldown is seeded so the *remaining* portion equals the resource
-- fraction, then Pause() freezes it there. Re-seeding happens on power events
-- rather than per frame, which is why this costs nothing at idle.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local RR = {}
ThugUI.ResourceRing = RR

-- Arbitrary: only the ratio between elapsed and total matters for the arc.
local ARC_DURATION = 1000

RR.frame = nil
RR.lastFraction = nil
RR.lastPowerToken = nil

-- ----------------------------------------------------------------------------
-- Which resource to show
--
-- UnitPowerType("player") already follows shapeshift form and stance on its
-- own -- a druid in Bear reports RAGE, in Cat reports ENERGY, in caster form
-- reports MANA, with no help from us. So the base answer is simply whatever
-- the game says, and every class is correct without a table entry.
--
-- Overrides exist only where the game's "primary" resource is not the one that
-- actually governs the rotation. Balance is the case in point: in Moonkin form
-- the primary power is still mana, but Astral Power is what you play around.
-- ----------------------------------------------------------------------------

local POWER_OVERRIDES = {
    DRUID = function()
        local formID = GetShapeshiftFormID and GetShapeshiftFormID()
        local lunar = Enum and Enum.PowerType and Enum.PowerType.LunarPower
        if lunar and MOONKIN_FORM and formID == MOONKIN_FORM then
            return lunar, "LUNAR_POWER"
        end
        -- Anything else falls through to UnitPowerType, which already reports
        -- rage in Bear, energy in Cat and mana in caster form.
        return nil
    end,
}

--- Returns powerType, powerToken for the resource to display.
function RR:GetPowerType()
    local _, class = UnitClass("player")

    local override = POWER_OVERRIDES[class]
    if override then
        local powerType, token = override()
        if powerType then return powerType, token end
    end

    local powerType, token = UnitPowerType("player")
    return powerType, token
end

--- r, g, b for the current resource. PowerBarColor is Blizzard's own mapping,
--- so the ring matches the colour the player already associates with that bar.
function RR:GetColor(powerToken)
    local mode = ThugUI_Config.resourceRingColorMode or "power"

    if mode == "class" then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return 1, 1, 1
    end

    if mode == "custom" then
        local c = ThugUI_Config.resourceRingCustomColor
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end

    local color = powerToken and PowerBarColor and PowerBarColor[powerToken]
    if color and color.r then return color.r, color.g, color.b end
    return 0.3, 0.5, 0.9
end

-- ----------------------------------------------------------------------------
-- Frame
-- ----------------------------------------------------------------------------

function RR:EnsureFrame()
    if self.frame then return self.frame end
    if not ThugUI_CursorFrame then return nil end

    local f = CreateFrame("Cooldown", "ThugUI_RESOURCE_RING", ThugUI_CursorFrame)
    f:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    -- Below the cast ring (level 3) so the cast sweep reads over the top of it,
    -- above the background rings (level 2 at a smaller size).
    f:SetFrameLevel(2)
    f:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    f:SetHideCountdownNumbers(true)
    f:SetDrawEdge(false)
    f:SetReverse(false)
    f:Hide()

    self.frame = f
    self:SyncGeometry()
    return f
end

--- Match the cast ring's size and rotation, so the two genuinely occupy one
--- band rather than merely sitting near each other.
function RR:SyncGeometry()
    local f = self.frame
    if not f then return end

    local ER = ThugUI.EssentialRings
    local cast = ER and ER.CastFrame

    if cast then
        f:SetSize(cast:GetSize())
    else
        f:SetSize(90, 90)
    end

    f:SetRotation((ER and ER.ClockToRadians)
        and ER:ClockToRadians(ThugUI_Config.castRotation or 12)
        or 0)
end

-- ----------------------------------------------------------------------------
-- Update
-- ----------------------------------------------------------------------------

function RR:ShouldShow()
    if not ThugUI_Config.showResourceRing then return false end
    if not ThugUI_CursorFrame or not ThugUI_CursorFrame:IsShown() then return false end
    return true
end

function RR:Update()
    local f = self:EnsureFrame()
    if not f then return end

    if not self:ShouldShow() then
        f:Hide()
        self.lastFraction = nil
        return
    end

    local powerType, powerToken = self:GetPowerType()
    local current = UnitPower("player", powerType) or 0
    local maximum = UnitPowerMax("player", powerType) or 0

    if maximum <= 0 then
        f:Hide()
        self.lastFraction = nil
        return
    end

    local fraction = current / maximum
    if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end

    if powerToken ~= self.lastPowerToken then
        self.lastPowerToken = powerToken
        local r, g, b = self:GetColor(powerToken)
        f:SetSwipeColor(r, g, b, ThugUI_Config.resourceRingAlpha or 0.55)
    end

    -- Re-seeding on every power tick would restart the swipe needlessly; power
    -- changes are discrete, so only a changed fraction is worth redrawing.
    if self.lastFraction ~= fraction then
        self.lastFraction = fraction

        -- Seed so the REMAINING portion of the sweep equals the fraction, then
        -- freeze. With SetReverse(false) the drawn arc is what is left to run,
        -- so starting (1 - fraction) of the way through leaves exactly
        -- `fraction` drawn.
        f:SetCooldown(GetTime() - (1 - fraction) * ARC_DURATION, ARC_DURATION)
        if f.Pause then pcall(f.Pause, f) end
    end

    f:Show()
end

function RR:UpdateColor()
    -- Force the colour to be recomputed on the next Update.
    self.lastPowerToken = nil
    self:Update()
end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

local driver = CreateFrame("Frame", "ThugUI_ResourceRingDriver")
RR.driver = driver

-- Unit-filtered for the same reason the cast ring now is: UNIT_POWER_UPDATE
-- fires for every unit in range, and in a raid that is a torrent of events
-- this ring has no interest in.
driver:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")
-- The event for "the power type itself changed" -- shapeshift, stance, vehicle.
driver:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

driver:SetScript("OnEvent", function(_, event)
    if event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
        -- Form change swaps both the resource and its colour.
        RR:UpdateColor()
        return
    end
    RR:Update()
end)

function RR:Initialize()
    self:EnsureFrame()
    self:Update()
end

return RR
