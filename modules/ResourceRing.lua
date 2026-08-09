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

    -- Parented to UIParent, ANCHORED to the cursor frame. Not parented to it:
    -- a child of a hidden frame never draws, and the cursor rings are usually
    -- set to combat-only -- which would make an "always show" resource ring
    -- impossible. Anchors still resolve against a hidden frame, and
    -- ER:OnUpdate repositions the cursor frame every frame regardless of
    -- visibility, so this tracks the cursor either way.
    local f = CreateFrame("Cooldown", "ThugUI_RESOURCE_RING", UIParent)
    f:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    -- A strata below the cursor frame's HIGH, so the cast sweep always draws
    -- over the top of this rather than fighting it on frame level.
    f:SetFrameStrata("MEDIUM")
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

--- Combat, or test mode standing in for it.
local function InCombat()
    local ER = ThugUI.EssentialRings
    if ER and ER.IsInCombat then return ER:IsInCombat() end
    return InCombatLockdown()
end

function RR:ShouldShow()
    if not ThugUI_Config.showResourceRing then return false end
    if not ThugUI_CursorFrame then return false end

    -- Its own visibility rule rather than the cursor rings'. Riding the rings
    -- meant a combat-only ring setting silently made the resource ring
    -- combat-only too, which is not what "always show my energy" means.
    local mode = ThugUI_Config.resourceRingVisibility or "always"
    if mode == "rings" then return ThugUI_CursorFrame:IsShown() end
    if mode == "combat" then return InCombat() end
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
    local current = UnitPower("player", powerType)
    local maximum = UnitPowerMax("player", powerType)

    -- UnitPower returns a SECRET number while our execution is tainted -- the
    -- max comes back plain, the current does not. Arithmetic on a secret
    -- throws, and so does comparing one, so both have to be screened BEFORE
    -- any use. This threw on every visibility update in combat, from inside
    -- ER:UpdateVisibility, which is a path that has to stay clean.
    local unreadable = issecretvalue and (issecretvalue(current) or issecretvalue(maximum))

    if unreadable then
        -- Once a session: this condition repeats every update, and the first
        -- occurrence is the whole story. It also names the likely cause, since
        -- secret power values follow taint rather than being unconditional.
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:LogOnce("power-secret", "RING",
                "UnitPower unreadable (secret value) for %s — addon is tainted; "
                .. "resource level cannot be computed", tostring(powerToken))
        end

        -- Keep drawing whatever was last resolved. A frozen ring beats an
        -- error every frame, and the values are readable again out of combat.
        -- Colour still tracks the power type, which is never secret.
        if powerToken ~= self.lastPowerToken then
            self.lastPowerToken = powerToken
            local r, g, b = self:GetColor(powerToken)
            f:SetSwipeColor(r, g, b, ThugUI_Config.resourceRingAlpha or 0.55)
        end
        -- Never read a value yet: draw the ring full rather than hiding it.
        -- Hiding here meant that once taint made UnitPower permanently secret,
        -- lastFraction stayed nil forever and the ring simply never appeared —
        -- which looks identical to the feature being broken. A full ring is
        -- visibly wrong, which is the honest failure.
        if self.lastFraction == nil then
            f:SetCooldown(GetTime(), ARC_DURATION)
            if f.Pause then pcall(f.Pause, f) end
            self.lastFraction = 1
        end

        f:Show()
        return
    end

    current = current or 0
    maximum = maximum or 0

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
