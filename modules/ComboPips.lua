-- ============================================================================
-- ThugUI: Combo Pips
--
-- The class's secondary resource as N dots evenly spaced around the cursor
-- ring, lit as points are gained. Combo points for a rogue, Holy Power for a
-- paladin, Soul Shards, Chi, Arcane Charges, Essence.
--
-- WHY PIPS AND NOT A SEGMENTED ARC
--
-- The maximum changes: Deeper Stratagem and its equivalents add a point, and
-- some specs gain one temporarily. A ring of discrete pips absorbs that for
-- free -- lay out however many there are -- where a segmented arc has to be
-- rebuilt every time the max moves. Per-point colour also falls out, which is
-- what death knight runes would eventually need.
--
-- WHICH RESOURCE, WITHOUT A SPEC TABLE
--
-- The mapping mirrors libs/oUF/elements/classpower.lua, which is the reference
-- for this and is vendored here already. The spec-by-spec conditions in it are
-- deliberately NOT copied: `UnitPowerMax` already returns 0 for a spec that
-- does not have the resource -- a fire mage has no Arcane Charges -- so gating
-- on the maximum gets every spec right with no table to maintain per patch.
-- The one exception is the druid, where combo points exist in the API outside
-- cat form; oUF's test for that (primary power is energy) is copied verbatim.
--
-- Deliberately not handled: death knight runes, which have per-rune cooldowns
-- rather than a count and need a different widget; and the aura-backed
-- pseudo-resources oUF supports (Hunter's Tip of the Spear, Shaman's Maelstrom
-- Weapon). Those are read from auras, which is exactly what an addon cannot do
-- in combat -- see docs/DECISIONS.md §12.
--
-- SECRET VALUES
--
-- `UnitPower` is `SecretWhenUnitPowerRestricted`. Primary resources stay secret
-- to addons; Blizzard's 12.1 notes say SECONDARY resources stop being, which is
-- precisely what this reads. So this is expected to work from 12.1 and to sit
-- frozen on 12.0.7, and it is written to do the second gracefully rather than
-- error: same screen-before-use guard as the resource ring.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local CP = {}
ThugUI.ComboPips = CP

CP.frame = nil
CP.pips = {}
CP.lastCount = nil
CP.lastMax = nil
CP.lastToken = nil

local DEFAULT_SIZE = 9
local DEFAULT_OFFSET = 7
local DEFAULT_DIM = 0.25

-- ----------------------------------------------------------------------------
-- Which resource
-- ----------------------------------------------------------------------------

--- Name in Enum.PowerType, and the PowerBarColor key that goes with it.
--- Resolved by NAME rather than by number: the numeric values are stable in
--- practice but the enum is the documented interface, and a missing entry then
--- degrades to "this class has no pips" instead of colouring the wrong bar.
local CLASS_POWER = {
    ROGUE   = { power = "ComboPoints",    token = "COMBO_POINTS" },
    DRUID   = { power = "ComboPoints",    token = "COMBO_POINTS", catOnly = true },
    PALADIN = { power = "HolyPower",      token = "HOLY_POWER" },
    WARLOCK = { power = "SoulShards",     token = "SOUL_SHARDS" },
    MONK    = { power = "Chi",            token = "CHI" },
    MAGE    = { power = "ArcaneCharges",  token = "ARCANE_CHARGES" },
    EVOKER  = { power = "Essence",        token = "ESSENCE" },
}

--- Returns powerType, powerToken, or nil when this class has no pip resource.
function CP:GetPowerType()
    local _, class = UnitClass("player")
    local entry = CLASS_POWER[class]
    if not entry then return nil end

    local powerType = Enum and Enum.PowerType and Enum.PowerType[entry.power]
    if powerType == nil then return nil end

    -- Combo points exist for a druid in any form as far as the API is
    -- concerned. oUF settles it by asking what the PRIMARY power is: energy
    -- means cat form, and cat form is the only one that generates them.
    if entry.catOnly then
        local energy = Enum.PowerType.Energy
        local primary = UnitPowerType and UnitPowerType("player")
        if energy == nil or primary ~= energy then return nil end
    end

    return powerType, entry.token
end

--- Colour for pip `index`. Per-index today only so that runes -- which need a
--- different colour per rune -- can be added later without reshaping anything.
function CP:GetColor(powerToken, _index)
    local mode = ThugUI_Config.comboPipColorMode or "power"

    if mode == "class" then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return 1, 1, 1
    end

    if mode == "custom" then
        local c = ThugUI_Config.comboPipCustomColor
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end

    local color = powerToken and PowerBarColor and PowerBarColor[powerToken]
    if color and color.r then return color.r, color.g, color.b end
    return 1, 0.85, 0.3
end

-- ----------------------------------------------------------------------------
-- Frames
-- ----------------------------------------------------------------------------

function CP:EnsureFrame()
    if self.frame then return self.frame end
    if not ThugUI_CursorFrame then return nil end

    -- Anchored to the cursor frame, not parented to it, for the reason spelled
    -- out in ResourceRing.lua: a child of a hidden frame never draws, and the
    -- cursor rings are usually combat-only, which would make "always show the
    -- pips" impossible.
    local f = CreateFrame("Frame", "ThugUI_ComboPips", UIParent)
    f:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    f:SetSize(1, 1)
    -- Above the resource ring's MEDIUM so a pip is never swallowed by the arc.
    f:SetFrameStrata("HIGH")
    f:Hide()

    self.frame = f
    return f
end

--- Pips are pooled. Max changes at runtime -- a talent, a buff, a spec swap --
--- and creating fresh textures each time would bleed them for the session, the
--- same trap the cooldown viewer's icons already avoid.
function CP:AcquirePip(index)
    local existing = self.pips[index]
    if existing then return existing end

    local f = self:EnsureFrame()
    if not f then return nil end

    local pip = f:CreateTexture(nil, "OVERLAY")
    pip:SetTexture("Interface\\AddOns\\ThugUI\\media\\Reticle_Dot")
    self.pips[index] = pip
    return pip
end

--- Lay `count` pips evenly around the ring, starting at the same clock position
--- the cast ring is rotated to so the two read as one instrument.
function CP:Layout(count)
    local f = self:EnsureFrame()
    if not f then return end

    local ER = ThugUI.EssentialRings
    local cast = ER and ER.CastFrame
    local diameter = 90
    if cast and cast.GetSize then
        local width = cast:GetSize()
        if width and width > 0 then diameter = width end
    end

    local size = ThugUI_Config.comboPipSize or DEFAULT_SIZE
    local radius = diameter / 2 + (ThugUI_Config.comboPipOffset or DEFAULT_OFFSET)

    local start = 0
    if ER and ER.ClockToRadians then
        start = ER:ClockToRadians(ThugUI_Config.castRotation or 12)
    end

    for i = 1, count do
        local pip = self:AcquirePip(i)
        if pip then
            -- Clockwise from the start position, which is what "12 o'clock,
            -- then round to the right" means to a reader looking at the ring.
            local angle = start + (i - 1) * (2 * math.pi / count)
            pip:SetSize(size, size)
            pip:ClearAllPoints()
            pip:SetPoint("CENTER", f, "CENTER",
                math.sin(angle) * radius, math.cos(angle) * radius)
            pip:Show()
        end
    end

    -- Anything beyond the current max stays allocated but hidden.
    for i = count + 1, #self.pips do
        self.pips[i]:Hide()
    end
end

--- Light the first `filled` pips and dim the rest.
function CP:Paint(filled, powerToken, max)
    local dim = ThugUI_Config.comboPipDimAlpha or DEFAULT_DIM

    for i = 1, max do
        local pip = self.pips[i]
        if pip then
            local r, g, b = self:GetColor(powerToken, i)
            pip:SetVertexColor(r, g, b)
            pip:SetAlpha(i <= filled and 1 or dim)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Update
-- ----------------------------------------------------------------------------

local function InCombat()
    local ER = ThugUI.EssentialRings
    if ER and ER.IsInCombat then return ER:IsInCombat() end
    return InCombatLockdown()
end

function CP:ShouldShow()
    if not ThugUI_Config.showComboPips then return false end
    if not ThugUI_CursorFrame then return false end

    local mode = ThugUI_Config.comboPipVisibility or "combat"
    if mode == "rings" then return ThugUI_CursorFrame:IsShown() end
    if mode == "combat" then return InCombat() end
    return true
end

function CP:Update()
    local f = self:EnsureFrame()
    if not f then return end

    if not self:ShouldShow() then
        f:Hide()
        return
    end

    local powerType, powerToken = self:GetPowerType()
    if not powerType then
        -- No secondary resource for this class or form. Not an error, and not
        -- worth a log line every shapeshift.
        f:Hide()
        self.lastCount, self.lastMax = nil, nil
        return
    end

    local current = UnitPower("player", powerType)
    local maximum = UnitPowerMax("player", powerType)

    -- Screened BEFORE any comparison or arithmetic, exactly as the resource
    -- ring does: comparing a secret throws just as readily as adding to one.
    local unreadable = issecretvalue and (issecretvalue(current) or issecretvalue(maximum))

    if unreadable then
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:LogOnce("pips-secret", "PIPS",
                "UnitPower unreadable (secret value) for %s — secondary resources "
                .. "are expected to become readable in 12.1", tostring(powerToken))
        end

        -- Hold the last resolved layout rather than vanishing. Before 12.1 this
        -- is the normal state in combat, and a pip ring frozen at its last
        -- count is honest about being stale in a way an empty screen is not.
        if self.lastMax then
            f:Show()
        else
            f:Hide()
        end
        return
    end

    current = current or 0
    maximum = maximum or 0

    if maximum <= 0 then
        f:Hide()
        self.lastCount, self.lastMax = nil, nil
        return
    end

    if current < 0 then current = 0 elseif current > maximum then current = maximum end

    -- Re-laying out on every power tick would rebuild anchors several times a
    -- second in a fight. Only a changed maximum moves a pip.
    if self.lastMax ~= maximum then
        self.lastMax = maximum
        self:Layout(maximum)
        self.lastCount = nil
    end

    if self.lastCount ~= current or self.lastToken ~= powerToken then
        self.lastCount = current
        self.lastToken = powerToken
        self:Paint(current, powerToken, maximum)
    end

    f:Show()
end

--- Force colour and geometry to be recomputed on the next update. Called by the
--- config page, where any setting can have changed.
function CP:Refresh()
    self.lastCount, self.lastMax, self.lastToken = nil, nil, nil
    self:Update()
end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

local driver = CreateFrame("Frame", "ThugUI_ComboPipsDriver")
CP.driver = driver

-- Unit-filtered for the reason the other two drivers are: UNIT_POWER_UPDATE
-- fires for every unit in range, and a raid makes that a torrent.
driver:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")
driver:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
-- Form, spec and talents all change WHICH resource this is, or how many of it
-- there are, without any power event firing.
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

driver:SetScript("OnEvent", function(_, event)
    if event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- The resource itself may have changed, so nothing cached still holds.
        CP:Refresh()
        return
    end
    CP:Update()
end)

function CP:Initialize()
    self:EnsureFrame()
    self:Update()
end

return CP
