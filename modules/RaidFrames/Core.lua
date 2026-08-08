-- ============================================================================
-- ThugUI: Raid Frames
--
-- Built on oUF (MIT licensed, vendored at libs/oUF). oUF owns the secure group
-- header, unit event routing, and element updates; everything below is the
-- ThugUI layout applied on top of it.
--
-- The reason this module exists: Blizzard's 12.0 raid frames render their auras
-- through the native Private Aura system, so the buff/HoT icons are mouse-
-- enabled frames we do not control. Owning the frames means we control the aura
-- buttons outright -- `disableMouse` below is what kills the tooltips AND lets
-- clicks fall through to the unit button underneath, so click-casting and
-- mouseover macros keep working with the cursor over an icon.
-- ============================================================================

local addonName, ns = ...
local oUF = ns.oUF

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local RaidFrames = {}
ThugUI.RaidFrames = RaidFrames

RaidFrames.header = nil
RaidFrames.pendingApply = false

-- ============================================================================
-- CONFIG HELPERS
-- ============================================================================

local function Cfg(key, fallback)
    local v = ThugUI_Config[key]
    if v == nil then return fallback end
    return v
end

-- Spelled out rather than borrowing a Blizzard global: CLASS_SORT_ORDER is a
-- table, not the comma-separated string groupingOrder wants, and the exact
-- global names churn between expansions.
local CLASS_ORDER =
    "WARRIOR,DEATHKNIGHT,DEMONHUNTER,PALADIN,MONK,DRUID,ROGUE,HUNTER,SHAMAN,EVOKER,MAGE,WARLOCK,PRIEST"

-- Blizzard's dispel-type colours, reused so debuff borders read the same way
-- players already expect them to.
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    none    = { 0.80, 0.00, 0.00 },
}

-- ============================================================================
-- TAGS
-- ============================================================================

-- Name truncated to the configured length. Registered once; it re-reads config
-- on every evaluation so the length slider applies without a respawn.
--
-- Guarded because a missing oUF must degrade to "raid frames unavailable"
-- rather than a load-time error that takes the rest of ThugUI down with it.
if oUF then
    oUF.Tags.Methods["thug:name"] = function(unit)
        local name = UnitName(unit)
        if not name then return "" end

        local maxLen = Cfg("rfNameLength", 6)
        if maxLen > 0 and #name > maxLen then
            name = string.sub(name, 1, maxLen)
        end
        return name
    end
    oUF.Tags.Events["thug:name"] = "UNIT_NAME_UPDATE GROUP_ROSTER_UPDATE"
end

-- ============================================================================
-- AURA CALLBACKS
-- ============================================================================

-- Colour the debuff border by dispel type so dispellable debuffs stand out
-- without needing a tooltip to identify them.
local function PostUpdateDebuff(element, button, unit, data)
    if not button.ThugBorder then return end

    local color = DISPEL_COLORS[data and data.dispelName or "none"] or DISPEL_COLORS.none
    button.ThugBorder:SetColorTexture(color[1], color[2], color[3], 1)
end

local function PostCreateAuraButton(element, button)
    -- oUF's default button has no border; add a thin one so icons stay legible
    -- against the health bar at raid-frame sizes.
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    button.ThugBorder = border

    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Count:SetFontObject("GameFontHighlightSmall")

    -- The whole point of this module is that a mouseover macro works over every
    -- pixel of the frame. oUF's `disableMouse` covers the button itself, but the
    -- cooldown spiral is a separate child frame layered on top of it -- if that
    -- ever took mouse input it would swallow the mouseover before it reached
    -- the unit button. Belt and braces; it costs nothing to be certain.
    if button.Cooldown then
        button.Cooldown:EnableMouse(false)
    end
end

-- Only show buffs the player cast. This is what makes the frames useful for a
-- healer: your own HoTs, not 39 raid buffs.
local function FilterOwnBuffs(element, unit, data)
    if element.thugOnlyMine and not data.isPlayerAura then
        return false
    end
    return true
end

local function FilterDebuffs(element, unit, data)
    if element.thugDispellableOnly then
        -- dispelName is nil for debuffs the player cannot remove
        return data.dispelName ~= nil
    end
    return true
end

-- ============================================================================
-- STYLE
-- ============================================================================

local function BuildAuraGroup(self, key, isDebuff)
    local group = CreateFrame("Frame", nil, self)
    group:SetFrameLevel(self:GetFrameLevel() + 3)

    group.PostCreateButton = PostCreateAuraButton
    group.FilterAura = isDebuff and FilterDebuffs or FilterOwnBuffs

    if isDebuff then
        group.PostUpdateButton = PostUpdateDebuff
    end

    self[key] = group
    return group
end

local function ThugRaidStyle(self, unit)
    self:RegisterForClicks("AnyUp")

    -- Backdrop
    local bg = self:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    self.ThugBackground = bg

    -- Health
    local health = CreateFrame("StatusBar", nil, self)
    health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    health:SetPoint("TOPLEFT", 1, -1)
    health:SetPoint("BOTTOMRIGHT", -1, 1)
    health.frequentUpdates = true
    health.colorDisconnected = true
    self.Health = health

    local healthBG = health:CreateTexture(nil, "BACKGROUND")
    healthBG:SetAllPoints()
    healthBG:SetColorTexture(0.15, 0.15, 0.15, 1)
    health.ThugBG = healthBG

    -- Owns the "static" colour mode. oUF's UpdateColor only calls
    -- SetStatusBarColor when one of its colour flags claims the bar, so with
    -- all of them off `color` arrives nil and the bar keeps whatever we last
    -- set. That alone would break on reconnect -- colorDisconnected paints the
    -- bar grey, and once the unit is back nothing repaints it -- so we repaint
    -- here on every update where nothing else claimed the colour.
    health.PostUpdateColor = function(element, unit, color)
        if color or not element.thugStaticMode then return end
        local c = Cfg("rfHealthStaticColor", { r = 0.25, g = 0.25, b = 0.25 })
        element:SetStatusBarColor(c.r, c.g, c.b)
    end

    -- Power (optional, laid out in ApplyLayout)
    local power = CreateFrame("StatusBar", nil, self)
    power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    power.frequentUpdates = true
    power.colorPower = true
    self.Power = power

    -- Name
    local name = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("CENTER", health, "CENTER", 0, 0)
    name:SetJustifyH("CENTER")
    self.ThugName = name

    -- Auras
    BuildAuraGroup(self, "Buffs", false)
    BuildAuraGroup(self, "Debuffs", true)

    -- Indicators worth keeping: these are the ones that change a healer's
    -- decision, and none of them need a tooltip to read.
    local readyCheck = health:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(14, 14)
    readyCheck:SetPoint("CENTER", health, "CENTER", 0, 0)
    self.ReadyCheckIndicator = readyCheck

    local resurrect = health:CreateTexture(nil, "OVERLAY")
    resurrect:SetSize(14, 14)
    resurrect:SetPoint("CENTER", health, "CENTER", 0, 0)
    self.ResurrectIndicator = resurrect

    local raidTarget = health:CreateTexture(nil, "OVERLAY")
    raidTarget:SetSize(14, 14)
    raidTarget:SetPoint("TOP", health, "TOP", 0, 2)
    self.RaidTargetIndicator = raidTarget

    local leader = health:CreateTexture(nil, "OVERLAY")
    leader:SetSize(10, 10)
    leader:SetPoint("TOPLEFT", health, "TOPLEFT", 1, 1)
    self.LeaderIndicator = leader

    -- Out-of-range fading. Alphas are seeded here rather than left nil: oUF
    -- enables the element before our deferred ApplyUnitSettings runs, and the
    -- first range update would otherwise be handed nil alphas.
    self.Range = {
        insideAlpha = 1.0,
        outsideAlpha = Cfg("rfRangeAlpha", 0.4),
    }

    -- Selection highlight
    local highlight = self:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.10)
    highlight:Hide()
    self.ThugHighlight = highlight

    self:HookScript("OnEnter", function(f) f.ThugHighlight:Show() end)
    self:HookScript("OnLeave", function(f) f.ThugHighlight:Hide() end)

    -- Deferred deliberately. oUF calls the style function first and only then
    -- runs EnableElement over every element it found on the frame, so anything
    -- we disabled here would be switched straight back on -- the power bar
    -- would show even with rfShowPowerBar off. Running on the next frame puts
    -- our element state after oUF's.
    C_Timer.After(0, function()
        RaidFrames:ApplyUnitSettings(self)
    end)
end

-- ============================================================================
-- APPLYING SETTINGS
--
-- Everything that can change at runtime without respawning the header lives
-- here, so the settings panel can call ApplyAll() and see it take effect.
-- ============================================================================

function RaidFrames:ApplyUnitSettings(frame)
    if not frame then return end

    -- Health colouring
    local mode = Cfg("rfHealthColor", "class")
    local health = frame.Health
    health.colorClass = (mode == "class")
    health.colorSmooth = (mode == "gradient")
    -- Deliberately never colorHealth: that flag paints oUF's own health colour,
    -- not the one configured here. Static is handled by PostUpdateColor.
    health.colorHealth = false
    health.thugStaticMode = (mode == "static")

    if mode == "static" then
        local c = Cfg("rfHealthStaticColor", { r = 0.25, g = 0.25, b = 0.25 })
        health:SetStatusBarColor(c.r, c.g, c.b)
    end

    -- Power bar
    local showPower = Cfg("rfShowPowerBar", false)
    local powerHeight = Cfg("rfPowerBarHeight", 3)
    if showPower then
        frame.Power:ClearAllPoints()
        frame.Power:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        frame.Power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        frame.Power:SetHeight(powerHeight)
        frame.Power:Show()

        frame.Health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1 + powerHeight)
        if not frame:IsElementEnabled("Power") then frame:EnableElement("Power") end
    else
        frame.Power:Hide()
        frame.Health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        if frame:IsElementEnabled("Power") then frame:DisableElement("Power") end
    end

    -- Name
    if Cfg("rfShowName", true) then
        frame:Tag(frame.ThugName, "[thug:name]")
        frame.ThugName:Show()
    else
        frame:Untag(frame.ThugName)
        frame.ThugName:Hide()
    end

    -- Range fading
    frame.Range.insideAlpha = 1.0
    frame.Range.outsideAlpha = Cfg("rfRangeAlpha", 0.4)
    if not frame:IsElementEnabled("Range") then frame:EnableElement("Range") end

    self:ApplyAuraSettings(frame)
end

function RaidFrames:ApplyAuraSettings(frame)
    if not frame then return end

    local size = Cfg("rfBuffSize", 14)
    local buffs = frame.Buffs
    buffs.num = Cfg("rfShowBuffs", true) and Cfg("rfBuffCount", 3) or 0
    buffs.size = size
    buffs.spacing = 1
    buffs.thugOnlyMine = Cfg("rfBuffOnlyMine", true)
    -- The whole point of this module: no tooltip, and the mouse falls through
    -- to the unit button so click-casting still works over the icon.
    buffs.disableMouse = Cfg("rfBuffHideTooltips", true)
    buffs.disableCooldown = false
    buffs:SetSize(size * math.max(buffs.num, 1) + 4, size + 2)
    buffs:ClearAllPoints()
    buffs.initialAnchor = "BOTTOMLEFT"
    buffs.growthX = "RIGHT"
    buffs:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)

    local dSize = Cfg("rfDebuffSize", 16)
    local debuffs = frame.Debuffs
    debuffs.num = Cfg("rfShowDebuffs", true) and Cfg("rfDebuffCount", 3) or 0
    debuffs.size = dSize
    debuffs.spacing = 1
    debuffs.thugDispellableOnly = Cfg("rfDebuffDispellableOnly", false)
    debuffs.disableMouse = Cfg("rfDebuffHideTooltips", true)
    debuffs.disableCooldown = false
    debuffs:SetSize(dSize * math.max(debuffs.num, 1) + 4, dSize + 2)
    debuffs:ClearAllPoints()
    debuffs.initialAnchor = "BOTTOMRIGHT"
    debuffs.growthX = "LEFT"
    debuffs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    if buffs.num > 0 then
        if not frame:IsElementEnabled("Buffs") then frame:EnableElement("Buffs") end
        buffs:Show()
    else
        buffs:Hide()
    end

    if debuffs.num > 0 then
        if not frame:IsElementEnabled("Debuffs") then frame:EnableElement("Debuffs") end
        debuffs:Show()
    else
        debuffs:Hide()
    end

    if frame.UpdateAllElements then
        frame:UpdateAllElements("ThugUI_ConfigChanged")
    end
end

-- ============================================================================
-- HEADER
-- ============================================================================

local function BuildInitialConfig()
    -- Runs inside the secure environment for each spawned unit button, so it
    -- can only use the restricted API -- hence baking the numbers in as a
    -- formatted string rather than reading config from here.
    return string.format([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]], Cfg("rfWidth", 80), Cfg("rfHeight", 40))
end

function RaidFrames:SpawnHeader()
    if self.header then return self.header end
    if not oUF then return nil end

    oUF:RegisterStyle("ThugUIRaid", ThugRaidStyle)
    oUF:SetActiveStyle("ThugUIRaid")

    local spacing = Cfg("rfSpacing", 3)
    local groupBy = Cfg("rfGroupBy", "GROUP")

    -- Geometry, per SecureGroupHeaders.lua:
    --   point = "TOP" anchors each unit's TOP to the previous unit's BOTTOM, so
    --   units stack downward and yOffset must be NEGATIVE to open a gap. That
    --   same code multiplies xOffset by 0 for a vertical point, so it stays 0
    --   here; horizontal gaps between columns come from columnSpacing.
    --   columnAnchorPoint = "LEFT" makes each new column grow to the right.
    -- Note the capital O in xOffset/yOffset -- the header silently ignores any
    -- other spelling and falls back to 0.
    local attrs = {
        ["showRaid"]          = true,
        ["showParty"]         = Cfg("rfShowParty", true),
        ["showSolo"]          = Cfg("rfShowSolo", false),
        ["showPlayer"]        = Cfg("rfShowPlayerInParty", true),
        ["point"]             = "TOP",
        ["xOffset"]           = 0,
        ["yOffset"]           = -spacing,
        ["columnSpacing"]     = spacing,
        ["columnAnchorPoint"] = "LEFT",
        ["maxColumns"]        = Cfg("rfMaxColumns", 8),
        ["unitsPerColumn"]    = Cfg("rfUnitsPerColumn", 5),
        ["oUF-initialConfigFunction"] = BuildInitialConfig(),
    }

    if groupBy == "GROUP" then
        attrs["groupBy"] = "GROUP"
        attrs["groupingOrder"] = "1,2,3,4,5,6,7,8"
    elseif groupBy == "ROLE" then
        attrs["groupBy"] = "ASSIGNEDROLE"
        attrs["groupingOrder"] = "TANK,HEALER,DAMAGER,NONE"
    elseif groupBy == "CLASS" then
        attrs["groupBy"] = "CLASS"
        attrs["groupingOrder"] = CLASS_ORDER
    else
        attrs["sortMethod"] = "INDEX"
    end

    local header = oUF:SpawnHeader("ThugUI_RaidHeader", nil, attrs)
    self.header = header

    self:RestorePosition()
    return header
end

function RaidFrames:RestorePosition()
    if not self.header then return end

    local saved = ThugUI_Config.rfPoint
    self.header:ClearAllPoints()
    if saved then
        self.header:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        self.header:SetPoint("CENTER", UIParent, "CENTER", -300, -180)
    end
end

-- Applies everything the secure header can absorb without being rebuilt.
--
-- A SecureGroupHeader re-runs its layout whenever an attribute changes, so
-- spacing, columns and grouping are all live out of combat -- no /reload. The
-- one exception is unit button size: oUF-initialConfigFunction only runs once
-- per button when it is first configured, so existing buttons are resized
-- directly and the attribute is refreshed for buttons spawned later.
function RaidFrames:ApplyHeaderLayout()
    if not self.header then return end
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    local header = self.header
    local width, height = Cfg("rfWidth", 80), Cfg("rfHeight", 40)

    for i = 1, header:GetNumChildren() do
        local child = select(i, header:GetChildren())
        if child then
            child:SetWidth(width)
            child:SetHeight(height)
        end
    end

    header:SetAttribute("oUF-initialConfigFunction", BuildInitialConfig())

    local spacing = Cfg("rfSpacing", 3)
    local groupBy = Cfg("rfGroupBy", "GROUP")

    header:SetAttribute("yOffset", -spacing)
    header:SetAttribute("columnSpacing", spacing)
    header:SetAttribute("unitsPerColumn", Cfg("rfUnitsPerColumn", 5))
    header:SetAttribute("maxColumns", Cfg("rfMaxColumns", 8))
    header:SetAttribute("showParty", Cfg("rfShowParty", true))
    header:SetAttribute("showSolo", Cfg("rfShowSolo", false))
    header:SetAttribute("showPlayer", Cfg("rfShowPlayerInParty", true))

    if groupBy == "GROUP" then
        header:SetAttribute("sortMethod", nil)
        header:SetAttribute("groupBy", "GROUP")
        header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
    elseif groupBy == "ROLE" then
        header:SetAttribute("sortMethod", nil)
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    elseif groupBy == "CLASS" then
        header:SetAttribute("sortMethod", nil)
        header:SetAttribute("groupBy", "CLASS")
        header:SetAttribute("groupingOrder", CLASS_ORDER)
    else
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupingOrder", nil)
        header:SetAttribute("sortMethod", "INDEX")
    end
end

-- ============================================================================
-- MOVER
--
-- A separate overlay rather than dragging the header itself: the header is a
-- secure frame whose size is recalculated from its children, so giving it mouse
-- input and a drag script is both taint-prone and visually unstable when the
-- roster changes. The overlay writes rfPoint and repositions the header.
-- ============================================================================

function RaidFrames:EnsureMover()
    if self.mover then return self.mover end

    local mover = CreateFrame("Frame", "ThugUI_RaidFramesMover", UIParent)
    mover:SetFrameStrata("HIGH")
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetClampedToScreen(true)
    mover:Hide()

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.6, 1.0, 0.35)

    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText("ThugUI Raid Frames\n(drag to move)")
    label:SetJustifyH("CENTER")

    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
    end)

    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        local point, _, relPoint, x, y = self:GetPoint()
        ThugUI_Config.rfPoint = { point = point, relPoint = relPoint, x = x, y = y }

        if RaidFrames.header and not InCombatLockdown() then
            RaidFrames:RestorePosition()
        end
        RaidFrames:UpdateMoverGeometry()
    end)

    self.mover = mover
    return mover
end

function RaidFrames:UpdateMoverGeometry()
    if not self.mover or not self.header then return end

    -- Track the header's real footprint so the handle covers what it moves.
    local w = math.max(self.header:GetWidth() or 0, 120)
    local h = math.max(self.header:GetHeight() or 0, 40)
    self.mover:SetSize(w, h)

    local saved = ThugUI_Config.rfPoint
    self.mover:ClearAllPoints()
    if saved then
        self.mover:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        self.mover:SetPoint("CENTER", UIParent, "CENTER", -300, -180)
    end
end

function RaidFrames:SetUnlocked(unlocked)
    local mover = self:EnsureMover()
    if unlocked then
        self:UpdateMoverGeometry()
        mover:Show()
    else
        mover:Hide()
    end
end

-- ============================================================================
-- VISIBILITY
-- ============================================================================

function RaidFrames:UpdateVisibility()
    if not self.header then return end

    if not Cfg("rfEnabled", false) then
        UnregisterAttributeDriver(self.header, "state-visibility")
        self.header:Hide()
        return
    end

    self.header:Show()

    local condition
    if Cfg("rfShowSolo", false) then
        condition = "custom [group:raid][group:party][@player,exists] show; hide"
    elseif Cfg("rfShowParty", true) then
        condition = "custom [group:raid][group:party] show; hide"
    else
        condition = "custom [group:raid] show; hide"
    end

    self.header:SetVisibility(condition)
end

-- ============================================================================
-- BLIZZARD RAID FRAMES
--
-- Taint-safe: a visibility state driver, never a Show() override and never a
-- reposition. Registering the driver is itself a protected action, so it only
-- happens out of combat.
-- ============================================================================

-- Three separate frames, not one: the raid container, the party container, and
-- the raid toolbar. Hiding only CompactRaidFrameContainer leaves Blizzard party
-- frames drawing on top of ours in a 5-man.
local function BlizzardGroupFrames()
    return {
        CompactRaidFrameContainer,
        CompactPartyFrame,
        CompactRaidFrameManager,
    }
end

function RaidFrames:UpdateBlizzardFrames()
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    local hide = Cfg("rfEnabled", false) and Cfg("rfHideBlizzardRaidFrames", true)

    for _, frame in ipairs(BlizzardGroupFrames()) do
        if frame then
            if hide then
                RegisterStateDriver(frame, "visibility", "hide")
            elseif self.blizzardHidden then
                UnregisterStateDriver(frame, "visibility")
                frame:Show()
            end
        end
    end

    self.blizzardHidden = hide
end

-- ============================================================================
-- ENTRY POINTS
-- ============================================================================

-- Full apply. Header attribute changes are protected, so anything that needs a
-- respawn is deferred out of combat; per-frame appearance updates are safe and
-- run immediately.
function RaidFrames:ApplyAll()
    if not oUF then return end

    -- Everything below touches the secure header -- spawning it, hiding it, or
    -- changing its visibility driver -- and all of that is blocked in combat.
    -- Defer wholesale rather than half-applying.
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    if not Cfg("rfEnabled", false) then
        self:UpdateVisibility()
        self:UpdateBlizzardFrames()
        return
    end

    local firstSpawn = not self.header
    if firstSpawn then
        self:SpawnHeader()
    end

    self:UpdateVisibility()
    self:UpdateBlizzardFrames()

    -- SpawnHeader already baked these in, so only re-apply on later passes.
    if not firstSpawn then
        self:ApplyHeaderLayout()
    end

    self:RefreshFrames()
    self:UpdateMoverGeometry()
end

-- Re-apply appearance to every spawned unit button.
function RaidFrames:RefreshFrames()
    if not oUF or not oUF.objects then return end

    for _, frame in ipairs(oUF.objects) do
        if frame.ThugName then
            self:ApplyUnitSettings(frame)
        end
    end
end

function RaidFrames:Initialize()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if RaidFrames.pendingApply then
                RaidFrames.pendingApply = false
                RaidFrames:ApplyAll()
            end
            return
        end

        RaidFrames:ApplyAll()
        -- Restore the drag handle if the user left the frames unlocked.
        if Cfg("rfEnabled", false) and Cfg("rfUnlocked", false) then
            RaidFrames:SetUnlocked(true)
        end
    end)

    self.watcher = watcher
end
