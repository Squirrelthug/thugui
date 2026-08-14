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
-- A RADIAL STATUSBAR, AND WHY THERE IS ONLY ONE IMPLEMENTATION NOW
--
-- UnitPower returns a secret number while tainted, so this ring cannot compute
-- its own fill fraction -- arithmetic on a secret throws. 12.1 added
-- StatusBarRenderMode.Radial, and StatusBar:SetValue/SetMinMaxValues both
-- carry SecretArguments = "AllowedWhenTainted", measured accepted at every
-- phase of a full combat (DECISIONS.md §20). So the engine computes the fill
-- from values we are never allowed to read, and the ring tracks the real level
-- in combat with no arithmetic and no comparison anywhere in this file.
--
-- **Verified in game 2026-08-13**: enabled mid-combat, tracked live through a
-- fight, and followed shapeshift form swaps (rage in Bear, energy in Cat).
--
-- This file used to carry a SECOND implementation on a Cooldown widget, which
-- was the default, with the radial bar opt-in behind `resourceRingRadialBar`.
-- **Both the Cooldown path and that setting were removed on 2026-08-13, at the
-- player's explicit instruction.** It was not a working fallback: it seeded a
-- sweep and called Pause() with Resume() never called anywhere, so it froze at
-- the first value it ever drew and never tracked at all -- out of combat too,
-- where nothing is secret. Keeping a broken escape hatch for a path verified
-- working is a cost with no benefit. DECISIONS.md §27, KNOWN-ISSUES.md.
--
-- So there is no fallback here on purpose. On a client without the radial
-- render mode the ring simply does not draw, and says so once in the log. The
-- TOC targets 12.1, which has it.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local RR = {}
ThugUI.ResourceRing = RR

RR.frame = nil
-- Cached once a client without StatusBarRenderMode.Radial is detected, so the
-- capability check (and its LogOnce) only ever runs once per session rather
-- than on every Update.
RR.radialUnsupported = nil
RR.lastPowerToken = nil
-- nil until the direction has been applied once. The reverse flag is sticky on
-- the texture, so it only needs writing when the setting actually changes --
-- but it must be written at least once, because a texture created fresh this
-- session has never been told which way to run.
RR.lastDrainDirection = nil

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

--- The ring: a StatusBar in Enum.StatusBarRenderMode.Radial (12.1+).
--- SetValue/SetMinMaxValues accept a secret from tainted code (DECISIONS.md
--- §20, measured), which is what lets this track the real resource level in
--- combat. There is no second implementation to choose between any more.
function RR:EnsureFrame()
    if self.frame then return self.frame end
    if self.radialUnsupported then return nil end
    if not ThugUI_CursorFrame then return nil end

    -- Parented to UIParent, ANCHORED to the cursor frame. Not parented to it:
    -- a child of a hidden frame never draws, and the cursor rings are usually
    -- set to combat-only -- which would make an "always show" resource ring
    -- impossible. Anchors still resolve against a hidden frame, and
    -- ER:OnUpdate repositions the cursor frame every frame regardless of
    -- visibility, so this tracks the cursor either way.
    --
    -- The global name keeps the _RADIAL suffix it was born with rather than
    -- inheriting the retired Cooldown ring's plain name. Renaming would buy
    -- nothing and risks colliding with a name some other addon or a Blizzard
    -- frame has since taken -- which is exactly how Edit Mode broke once
    -- before (DECISIONS.md §15).
    local f = CreateFrame("StatusBar", "ThugUI_RESOURCE_RING_RADIAL", UIParent)

    -- Capability gate: an older client has neither the enum nor the method.
    -- There is no fallback to drop to any more, so this means no ring at all
    -- -- say so once, because "the setting is on and nothing draws" is
    -- indistinguishable from a broken feature.
    if not (Enum and Enum.StatusBarRenderMode) or not f.SetRenderMode then
        self.radialUnsupported = true
        f:Hide()
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:LogOnce("resource-ring-radial-unsupported", "RING",
                "StatusBarRenderMode.Radial unavailable on this client -- "
                .. "the resource ring cannot draw. Requires 12.1 or later")
        end
        return nil
    end

    -- A strata below the cursor frame's HIGH, so the cast sweep always draws
    -- over the top of this rather than fighting it on frame level.
    f:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    f:SetFrameStrata("MEDIUM")
    f:SetRenderMode(Enum.StatusBarRenderMode.Radial)
    f:SetStatusBarTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    f:Hide()

    self.frame = f
    self.lastPowerToken = nil
    self.lastDrainDirection = nil
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

    local radians = (ER and ER.ClockToRadians)
        and ER:ClockToRadians(ThugUI_Config.castRotation or 12)
        or 0

    -- StatusBar has no SetRotation of its own -- that is a Cooldown method.
    -- The closest analogue is rotating the managed texture, and the player
    -- confirmed in game on 2026-08-13 that this does move the fill's start
    -- angle and not merely the artwork under it.
    --
    -- 12.1 does have a first-class version of this in
    -- SetRadialProgressBarStartOffset, and we are deliberately NOT using it --
    -- the workaround is verified working and the player chose to leave it.
    -- DECISIONS.md §23 carries the trigger for revisiting: if the start angle
    -- ever misbehaves, especially after a patch, swap to that API rather than
    -- debugging this rotation.
    local tex = f.GetStatusBarTexture and f:GetStatusBarTexture()
    if tex and tex.SetRotation then
        tex:SetRotation(radians)
    end
end

--- Clockwise or counter-clockwise, per `resourceRingDrainDirection`.
---
--- SetRadialProgressBarReverse lives on the TEXTURE, not on the StatusBar.
--- StatusBar:SetReverseFill is NOT the same thing and does not apply here --
--- its only use in Blizzard's entire source is on a plain horizontal bar, and
--- there is no evidence it touches radial mode at all.
---
--- Every call is guarded because we are the first consumer of this API family
--- anywhere: an exhaustive search of Blizzard's own live 12.1 source found
--- zero uses of any SetRadialProgressBar* method. It is also unverified that
--- the texture from GetStatusBarTexture() exposes them -- the generated docs
--- never state object composition. If it does not, the ring keeps working in
--- its default direction rather than erroring or blanking.
function RR:ApplyDrainDirection(f)
    local want = ThugUI_Config.resourceRingDrainDirection or "clockwise"
    if want == self.lastDrainDirection then return end

    local tex = f.GetStatusBarTexture and f:GetStatusBarTexture()
    if not (tex and tex.SetRadialProgressBarReverse) then
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:LogOnce("resource-ring-no-reverse", "RING",
                "SetRadialProgressBarReverse unavailable -- resource ring "
                .. "drain direction cannot be changed on this client")
        end
        -- Remembered anyway, so the miss is logged once rather than per update.
        self.lastDrainDirection = want
        return
    end

    tex:SetRadialProgressBarReverse(want == "counterclockwise")
    self.lastDrainDirection = want
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
        return
    end

    local powerType, powerToken = self:GetPowerType()
    local current = UnitPower("player", powerType)
    local maximum = UnitPowerMax("player", powerType)

    self:UpdateRadial(f, current, maximum, powerToken)
end

--- The radial path. SetValue/SetMinMaxValues take a secret directly and the
--- engine computes the fill -- there is no fraction to compute, so nothing
--- here may ever be compared or have arithmetic done on it. No lastFraction
--- short-circuit either: that exists on the Cooldown path solely to avoid
--- re-seeding a sweep, and there is no sweep here to re-seed. SetValue is
--- called unconditionally, every update.
function RR:UpdateRadial(f, current, maximum, powerToken)
    -- UnitPowerMax was measured plain in combat (DECISIONS.md §20), so this
    -- is a guard against an unexpected client state, not an expected path.
    -- issecretvalue is asked FIRST, before any nil test -- comparing a secret
    -- to nil is itself a comparison, and throws exactly like any other one.
    -- When maximum is unreadable there is nothing safe to compare it to, so
    -- the <= 0 test is skipped entirely and both values go to the bar as-is.
    local maxUnreadable = issecretvalue and issecretvalue(maximum)
    if not maxUnreadable then
        local m = maximum or 0
        if m <= 0 then
            f:Hide()
            return
        end
        maximum = m
    end

    -- The power TOKEN is never secret, so this recolour optimisation carries
    -- over unchanged from the Cooldown path.
    if powerToken ~= self.lastPowerToken then
        self.lastPowerToken = powerToken
        local r, g, b = self:GetColor(powerToken)
        f:SetStatusBarColor(r, g, b, ThugUI_Config.resourceRingAlpha or 0.55)
    end

    -- Cheap after the first call -- ApplyDrainDirection returns immediately
    -- unless the setting actually changed. Done here rather than only at frame
    -- creation so flipping the dropdown takes effect on the next update,
    -- matching every other control on that page.
    self:ApplyDrainDirection(f)

    -- Never GetValue() back: SetValue carries
    -- SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }, so a bar fed
    -- a secret hands one back too, and reading it would just reintroduce the
    -- comparison/arithmetic problem this whole path exists to avoid.
    f:SetMinMaxValues(0, maximum)
    f:SetValue(current)

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
