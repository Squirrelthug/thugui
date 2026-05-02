-- Essential Rings Module for ThugUI
-- Provides cursor-centered GCD and Cast bar tracking

ThugUI = ThugUI or {}
ThugUI.EssentialRings = {}

local ER = ThugUI.EssentialRings

local TrackerFrame = CreateFrame("Frame", "ThugUI_TrackerFrame", UIParent)
local LoaderFrame = CreateFrame("Frame")

local GCD_SPELL_ID = 61304
local _, _, _, interfaceVersion = GetBuildInfo()
local CURRENT_API = interfaceVersion

-- Frame references
ER.GCDCooldownFrame = nil
ER.GCDBackgroundFrame = nil
ER.CastFrame = nil
ER.CastBackgroundFrame = nil

-- State tracking
ER.currentGroupScale = 1.0
ER.lastGCDTime = 0
ER.isGCDAnimating = false
ER.isCasting = false

-- Essential Cooldown Viewer
ER.ecvOriginalPoint = nil
ER.ecvAnchored = false
ER.ecvContainer = nil
ER.ecvIcons = {}
ER.ecvUpdateTimer = 0
ER.ecvUpdateInterval = 0.15

-- ============================================================================
-- DEBUG LOGGER — writes to ThugUI_DebugLog SavedVariable
-- Toggle with /thugdebug, view last entries with /thuglog
-- ============================================================================
local DebugLog = {}
DebugLog.enabled = false
DebugLog.throttle = 1.0      -- seconds between log batches
DebugLog.timer = 0
DebugLog.MAX_ENTRIES = 200

local function DLog(category, msg)
    if not DebugLog.enabled then return end
    if not ThugUI_DebugLog then ThugUI_DebugLog = {} end
    local t = GetTime()
    local combat = InCombatLockdown() and "COMBAT" or "NO_COMBAT"
    -- Only log during combat (we know out-of-combat works fine)
    -- Exception: log state transitions
    if not InCombatLockdown() and category ~= "TRANSITION" then return end
    local entry = string.format("[%.1f][%s][%s] %s", t, combat, category, msg)
    table.insert(ThugUI_DebugLog, entry)
    -- Trim oldest entries
    while #ThugUI_DebugLog > DebugLog.MAX_ENTRIES do
        table.remove(ThugUI_DebugLog, 1)
    end
end

-- Safe tostring that detects secrets
local function SafeStr(val)
    if val == nil then return "nil" end
    if issecretvalue and issecretvalue(val) then return "SECRET("..type(val)..")" end
    local ok, s = pcall(tostring, val)
    if ok then return s end
    return "ERROR("..type(val)..")"
end

-- Dump all fields of an aura table
local function DumpAuraFields(auraData)
    if not auraData then return "nil" end
    local parts = {}
    for k, v in pairs(auraData) do
        table.insert(parts, k .. "=" .. SafeStr(v))
    end
    return table.concat(parts, ", ")
end

SLASH_THUGDEBUG1 = "/thugdebug"
SlashCmdList["THUGDEBUG"] = function()
    DebugLog.enabled = not DebugLog.enabled
    if DebugLog.enabled then
        ThugUI_DebugLog = {}  -- clear on enable
        DebugLog.didCombatDump = false  -- reset one-time dump flag
        print("|cff00ff00ThugUI Debug:|r Logging ON — aura queries will be logged.")
        print("|cff00ff00ThugUI Debug:|r Enter combat with buffs, then /reload to save log.")
    else
        print("|cff00ff00ThugUI Debug:|r Logging OFF.")
    end
end

SLASH_THUGLOG1 = "/thuglog"
SlashCmdList["THUGLOG"] = function(msg)
    if not ThugUI_DebugLog or #ThugUI_DebugLog == 0 then
        print("|cff00ff00ThugUI Debug:|r No log entries. Use /thugdebug to enable.")
        return
    end
    local count = tonumber(msg) or 20
    local start = math.max(1, #ThugUI_DebugLog - count + 1)
    print("|cff00ff00ThugUI Debug:|r Showing " .. (#ThugUI_DebugLog - start + 1) .. " of " .. #ThugUI_DebugLog .. " entries:")
    for i = start, #ThugUI_DebugLog do
        print(ThugUI_DebugLog[i])
    end
end

-- Spells shown in the ECV — looked up by name at runtime so the game
-- resolves to whatever version the player actually has talented.
ER.ecvSpellNames = {
    "Wild Growth",
    "Swiftmend",
    "Nature's Swiftness",
    "Ironbark",
    "Convoke the Spirits",
    "Tranquility",
}

-- Default settings
ER.defaults = {
    scale = 1.0,
    innerRing = "GCD",
    mainRing = "Main Ring",
    outerRing = "Cast",
    
    -- Color modes: "default", "class", or "custom"
    reticleColorMode = "default",
    reticleCustomColor = {r = 1.0, g = 1.0, b = 1.0},
    mainRingColorMode = "default",
    mainRingCustomColor = {r = 1.0, g = 1.0, b = 1.0},
    gcdColorMode = "default",
    gcdCustomColor = {r = 1.0, g = 1.0, b = 1.0},
    castColorMode = "default",
    castCustomColor = {r = 1.0, g = 1.0, b = 1.0},
    
    showOnlyInCombat = false,
    hideGameCursor = false,
    reticle = "Dot",
    reticleScale = 1.5,
    transparency = 1.0,
    
    -- GCD/Cast Animation settings
    gcdFillDrain = "fill",
    castFillDrain = "fill",
    gcdRotation = 12,
    castRotation = 12,
    
    -- ECV settings
    showECV = false,
    anchorECVToCursor = false,
    ecvShowOnlyInCombat = false,
    ecvPoint = nil,  -- saved position {point, relPoint, x, y}
    ecvScale = 1.0,
    ecvAnchorCorner = "TOPLEFT",  -- which corner of the bar attaches to cursor
    ecvShowAbundance = true,
    ecvAbundanceCorner = "TOPLEFT",
    ecvAbundanceScale = 1.0,
    ecvShowReforestation = true,
    ecvReforestationCorner = "TOPRIGHT",
    ecvReforestationScale = 1.0,
    ecvShowClearcasting = true,
    ecvClearcastingCorner = "BOTTOMLEFT",
    ecvClearcastingScale = 1.0,

    -- Tracked Buff Frame (Blizzard BuffIconCooldownViewer)
    anchorBuffFrameToCursor = false,
    buffFrameCorner = "BOTTOMRIGHT",
    buffFrameScale = 1.0,

    -- Test mode
    testMode = false,

    -- Frame Hider settings
    hideObjectiveTracker = true,
    hideStanceBar = true,
    hideBagButtons = true,
    hideCharacterFrame = false,
    fixTooltipAnchor = true,

    -- Prey Crystal (UIWidgetPowerBarContainerFrame)
    movePreyCrystal = true,
    preyCrystalPoint = nil,  -- saved position {point, relPoint, x, y}
}

-- Returns true if actually in combat OR test mode is on
function ER:IsInCombat()
    return InCombatLockdown() or (ThugUI_Config.testMode == true)
end

-- Cursor state tracking
ER.cursorHidden = false
ER.emptyCursorPath = "Interface\\AddOns\\ThugUI\\media\\Empty_Cursor"

-- Ring options
ER.ringOptions = {
    "None",
    "Main Ring",
    "GCD",
    "Cast",
}

-- Reticle options
ER.reticleOptions = {
    "Dot",
    "Chevron",
    "Crosshair",
    "Diamond",
    "Flatline",
    "Star",
    "Ring",
    "Tech Arrow",
    "X",
    "No Reticle",
}

ER.reticleTextures = {
    ["Dot"] = { path = "Interface\\AddOns\\ThugUI\\media\\Reticle_Dot", scale = 0.5 },
    ["Chevron"] = { path = "uitools-icon-chevron-down", scale = 1.0, isAtlas = true },
    ["Crosshair"] = { path = "uitools-icon-plus", scale = 1.0, isAtlas = true },
    ["Diamond"] = { path = "UF-SoulShard-FX-FrameGlow", scale = 1.0, isAtlas = true },
    ["Flatline"] = { path = "uitools-icon-minus", scale = 1.0, isAtlas = true },
    ["Star"] = { path = "AftLevelup-WhiteStarBurst", scale = 2.0, isAtlas = true },
    ["Ring"] = { path = "Interface\\AddOns\\ThugUI\\media\\Reticle_Circle", scale = 1.0 },
    ["Tech Arrow"] = { path = "ProgLan-w-4", scale = 1.0, isAtlas = true },
    ["X"] = { path = "uitools-icon-close", scale = 1.0, isAtlas = true },
    ["No Reticle"] = { path = nil, scale = 1.0 },
}

function ER:GetClassColor(ringType)
    local colorMode = "default"
    local customColor = nil
    
    if ringType == "main" then
        colorMode = ThugUI_Config.mainRingColorMode or "default"
        customColor = ThugUI_Config.mainRingCustomColor
    elseif ringType == "gcd" then
        colorMode = ThugUI_Config.gcdColorMode or "default"
        customColor = ThugUI_Config.gcdCustomColor
    elseif ringType == "cast" then
        colorMode = ThugUI_Config.castColorMode or "default"
        customColor = ThugUI_Config.castCustomColor
    elseif ringType == "reticle" then
        colorMode = ThugUI_Config.reticleColorMode or "default"
        customColor = ThugUI_Config.reticleCustomColor
    end
    
    -- Return custom color if mode is custom
    if colorMode == "custom" and customColor then
        return customColor.r or 1.0, customColor.g or 1.0, customColor.b or 1.0
    end
    
    -- Return class color if mode is class
    if colorMode == "class" then
        local _, class = UnitClass("player")
        local classColor = C_ClassColor.GetClassColor(class)
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
    end

    -- Return default color (white)
    return 1.0, 1.0, 1.0
end

function ER:ClockToRadians(clockPosition)
    -- Convert clock position (1-12) to radians for SetRotation
    -- 12 = 12 o'clock (top), 3 = 3 o'clock (right), 6 = 6 o'clock (bottom), 9 = 9 o'clock (left)
    local position = (clockPosition == 12) and 0 or clockPosition
    return (position * math.pi / 6)
end

function ER:UpdateRingColors()
    -- GCD Ring color
    if ER.GCDCooldownFrame then
        local r, g, b = ER:GetClassColor("gcd")
        ER.GCDCooldownFrame:SetSwipeColor(r, g, b, 1.0)
    end

    -- Cast Ring color
    if ER.CastFrame then
        local r, g, b = ER:GetClassColor("cast")
        ER.CastFrame:SetSwipeColor(r, g, b, 1.0)
    end

    -- Main Ring color
    if ThugUI_CursorFrame and ThugUI_CursorFrame.MainRing then
        local r, g, b = ER:GetClassColor("main")
        ThugUI_CursorFrame.MainRing:SetVertexColor(r, g, b, 1.0)
    end
end

function ER:UpdateReticle()
    if not ThugUI_CursorFrame or not ThugUI_CursorFrame.Reticle then return end
    
    local reticleName = ThugUI_Config.reticle or "Dot"
    local reticleInfo = ER.reticleTextures[reticleName]
    
    if not reticleInfo or not reticleInfo.path then
        -- No Reticle or invalid
        ThugUI_CursorFrame.Reticle:Hide()
    else
        ThugUI_CursorFrame.Reticle:Show()
        
        if reticleInfo.isAtlas then
            ThugUI_CursorFrame.Reticle:SetAtlas(reticleInfo.path)
        else
            ThugUI_CursorFrame.Reticle:SetTexture(reticleInfo.path)
        end
        
        -- Apply scale
        local globalScale = ThugUI_Config.reticleScale or 1.0
        ThugUI_CursorFrame.Reticle:SetScale(reticleInfo.scale * globalScale)
        
        -- Apply color
        local r, g, b = ER:GetClassColor("reticle")
        ThugUI_CursorFrame.Reticle:SetVertexColor(r, g, b, 1.0)
    end
end

function ER:SetGroupScale(scale)
    if type(scale) == "number" and scale > 0 then
        ER.currentGroupScale = scale
        ThugUI_CursorFrame:SetScale(scale)
    end
end

function ER:OnUpdate(elapsed)
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetScale()
    local groupScale = ER.currentGroupScale

    local correctedX = (cursorX / uiScale) / groupScale
    local correctedY = (cursorY / uiScale) / groupScale

    ThugUI_CursorFrame:ClearAllPoints()
    ThugUI_CursorFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", correctedX, correctedY)
    
    -- Update Essential Cooldown Viewer position if anchored
    ER:UpdateECVPosition()
    -- Update cursor-anchored tracker positions (every frame for smooth tracking)
    ER:UpdateAbundancePosition()
    ER:UpdateReforestationPosition()
    ER:UpdateClearcastingPosition()
    -- Anchor Blizzard tracked buff frame to cursor
    ER:UpdateBuffFramePosition()

    -- Throttled ECV cooldown refresh — polls spell states every ~0.15s
    -- so the bar stays in sync even when event-based updates miss a frame
    ER.ecvUpdateTimer = ER.ecvUpdateTimer + elapsed
    if ER.ecvUpdateTimer >= ER.ecvUpdateInterval then
        ER.ecvUpdateTimer = 0

        -- Debug logging throttle: only enable GetAuraInfo logging once per second
        DebugLog.timer = DebugLog.timer + ER.ecvUpdateInterval
        local wasEnabled = DebugLog.enabled
        if DebugLog.enabled and DebugLog.timer < DebugLog.throttle then
            DebugLog.enabled = false  -- suppress logging this tick
        elseif wasEnabled then
            DebugLog.timer = 0
            -- Log container/combat state once per log tick
            DLog("STATE", "container=" .. (ER.ecvContainer and (ER.ecvContainer:IsShown() and "SHOWN" or "HIDDEN") or "NIL")
                .. " testMode=" .. tostring(ThugUI_Config.testMode)
                .. " showECV=" .. tostring(ThugUI_Config.showECV)
                .. " combatOnly=" .. tostring(ThugUI_Config.ecvShowOnlyInCombat))
        end

        ER:UpdateECVCooldowns()
        ER:UpdateAbundanceStacks()
        ER:UpdateReforestationStacks()
        ER:UpdateClearcastingTimer()

        -- Restore debug flag if we suppressed it
        if wasEnabled then DebugLog.enabled = true end
    end

    -- Update cursor visibility
    ER:UpdateCursorVisibility()
end

-- Cursor hiding functions
function ER:UpdateCursorVisibility()
    if not ThugUI_Config.hideGameCursor then
        -- Setting is off, make sure cursor is restored
        if ER.cursorHidden then
            ER:RestoreGameCursor()
        end
        return
    end
    
    -- Check if rings are currently visible
    local ringsVisible = ThugUI_CursorFrame and ThugUI_CursorFrame:IsShown()
    
    if ringsVisible and not ER.cursorHidden then
        ER:HideGameCursor()
    elseif not ringsVisible and ER.cursorHidden then
        ER:RestoreGameCursor()
    end
end

function ER:HideGameCursor()
    SetCursor(ER.emptyCursorPath)
    ER.cursorHidden = true
end

function ER:RestoreGameCursor()
    SetCursor(nil) -- nil restores the default cursor
    ER.cursorHidden = false
end

-- Essential Cooldown Viewer functions

-- Addon Disarmament (12.0): most C_Spell cooldown fields are "secret
-- values" during combat and cannot be compared. However, 12.0.1 added
-- SpellCooldownInfo.isActive — a NON-SECRET boolean that is true exactly
-- when a real cooldown (not GCD) is running. We use that for show/hide.
-- For charge spells we also read currentCharges (non-secret in 12.0.1+).
local function IsSpellReady(spellName)
    -- Charge-based spells: ready if any charge is available
    local ok, chargeInfo = pcall(C_Spell.GetSpellCharges, spellName)
    if ok and chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
        local current = chargeInfo.currentCharges
        if current ~= nil and not (issecretvalue and issecretvalue(current)) then
            return current > 0
        end
        -- charges are secret — fall through to isActive
    end

    -- Regular cooldowns: isActive + isOnGCD (both non-secret, 12.0.1+)
    local ok2, cdInfo = pcall(C_Spell.GetSpellCooldown, spellName)
    if ok2 and cdInfo then
        -- isOnGCD is true when the spell's CD info just reflects the
        -- global cooldown — not a real spell cooldown. Skip those.
        if cdInfo.isOnGCD then
            return true
        end
        if cdInfo.isActive then
            return false -- on real cooldown
        end
    end

    return true
end

function ER:CreateECV()
    if ER.ecvContainer then return end

    local f = CreateFrame("Frame", "EssentialCooldownViewer", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    ER.ecvContainer = f

    local iconSize = 32
    local padding = 4
    local index = 0

    for _, spellName in ipairs(ER.ecvSpellNames) do
        local texture = C_Spell.GetSpellTexture(spellName)
        if texture then
            local icon = CreateFrame("Frame", nil, f)
            icon:SetSize(iconSize, iconSize)

            local bg = icon:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", -1, 1)
            bg:SetPoint("BOTTOMRIGHT", 1, -1)
            bg:SetColorTexture(0, 0, 0, 0.8)

            local tex = icon:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture(texture)
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon.tex = tex

            icon.spellName = spellName
            icon:SetPoint("TOPLEFT", f, "TOPLEFT",
                index * (iconSize + padding), 0)

            table.insert(ER.ecvIcons, icon)
            index = index + 1
        end
    end

    -- Size the container to fit the icons
    local totalW = math.max(index * (iconSize + padding) - padding, 1)
    f:SetSize(totalW, iconSize)

    -- Restore saved position or use default
    local saved = ThugUI_Config.ecvPoint
    if saved then
        f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    end

    -- Make draggable (only outside combat)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position relative to UIParent
        local point, _, relPoint, x, y = self:GetPoint()
        ThugUI_Config.ecvPoint = {
            point = point, relPoint = relPoint,
            x = x, y = y,
        }
    end)

    -- Helper: create an icon-based tracker frame with cooldown overlay
    local function CreateTrackerIcon(frameName, iconTexture, defaultScale)
        local size = 32
        local frame = CreateFrame("Frame", frameName, UIParent)
        frame:SetSize(size, size)
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(15)
        frame:SetScale(defaultScale or 1.0)

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -1, 1)
        bg:SetPoint("BOTTOMRIGHT", 1, -1)
        bg:SetColorTexture(0, 0, 0, 0.8)

        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(iconTexture)
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        frame.tex = tex

        local cd = CreateFrame("Cooldown", frameName .. "Cooldown", frame, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(true)
        cd:SetDrawSwipe(true)
        cd:SetSwipeColor(0, 0, 0, 0.6)
        cd:SetHideCountdownNumbers(false)
        frame.cooldown = cd

        frame:Hide()
        return frame
    end

    -- Abundance icon (texture 132124)
    ER.ecvAbundanceFrame = CreateTrackerIcon("ThugUI_AbundanceTracker", 132124,
        ThugUI_Config.ecvAbundanceScale or 1.0)

    -- Reforestation icon (texture 1416160)
    ER.ecvReforestationFrame = CreateTrackerIcon("ThugUI_ReforestationTracker", 1416160,
        ThugUI_Config.ecvReforestationScale or 1.0)

    -- Clearcasting icon (texture 136170)
    ER.ecvClearcastingFrame = CreateTrackerIcon("ThugUI_ClearcastingTracker", 136170,
        ThugUI_Config.ecvClearcastingScale or 1.0)

    -- Apply scale
    f:SetScale(ThugUI_Config.ecvScale or 1.0)

    -- Apply initial visibility from saved setting
    ER:UpdateECVVisibility()
end

-- Shared helper: position a frame at a corner around the cursor
local function PositionFrameAtCursor(frame, cornerSetting, gap)
    if not frame or not frame:IsShown() then return end

    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local x = cursorX / uiScale
    local y = cursorY / uiScale

    local corner = cornerSetting or "TOPLEFT"
    gap = gap or 12

    local anchor, ofsX, ofsY
    if corner == "TOPLEFT" then
        anchor = "BOTTOMRIGHT"
        ofsX, ofsY = -gap, gap
    elseif corner == "TOPRIGHT" then
        anchor = "BOTTOMLEFT"
        ofsX, ofsY = gap, gap
    elseif corner == "BOTTOMLEFT" then
        anchor = "TOPRIGHT"
        ofsX, ofsY = -gap, -gap
    elseif corner == "BOTTOMRIGHT" then
        anchor = "TOPLEFT"
        ofsX, ofsY = gap, -gap
    end

    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, "BOTTOMLEFT", x + ofsX, y + ofsY)
end

function ER:UpdateAbundancePosition()
    PositionFrameAtCursor(ER.ecvAbundanceFrame, ThugUI_Config.ecvAbundanceCorner, 12)
end

function ER:UpdateReforestationPosition()
    PositionFrameAtCursor(ER.ecvReforestationFrame, ThugUI_Config.ecvReforestationCorner, 12)
end

function ER:UpdateClearcastingPosition()
    PositionFrameAtCursor(ER.ecvClearcastingFrame, ThugUI_Config.ecvClearcastingCorner, 12)
end

-- Position the Blizzard tracked buff frame (BuffIconCooldownViewer) at cursor
-- Uses the same scale-corrected math as UpdateECVPosition.
function ER:UpdateBuffFramePosition()
    if not ThugUI_Config.anchorBuffFrameToCursor then return end

    local buffFrame = _G["BuffIconCooldownViewer"]
    if not buffFrame then return end

    -- When combat ends, restore the frame to its Edit Mode position
    if not ER:IsInCombat() then
        if ER.buffFrameAnchored then
            buffFrame:SetScale(1.0)
            -- Let Edit Mode reclaim the frame by calling its layout method
            if buffFrame.UpdateSystem then
                pcall(buffFrame.UpdateSystem, buffFrame)
            elseif EditModeManagerFrame and EditModeManagerFrame.LayoutApplied then
                pcall(EditModeManagerFrame.LayoutApplied, EditModeManagerFrame)
            end
            ER.buffFrameAnchored = false
        end
        return
    end

    local scale = ThugUI_Config.buffFrameScale or 1.0
    buffFrame:SetScale(scale)
    ER.buffFrameAnchored = true

    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    -- Divide by frame scale — SetPoint offsets are in the frame's scaled space
    local x = cursorX / uiScale / scale
    local y = cursorY / uiScale / scale

    local corner = ThugUI_Config.buffFrameCorner or "BOTTOMRIGHT"
    local gap = 16 / scale

    -- The "corner" setting means which corner of the cursor the frame sits at.
    -- We anchor the frame's nearest corner to that cursor position.
    local anchor, ofsX, ofsY
    if corner == "TOPLEFT" then
        anchor = "BOTTOMRIGHT"; ofsX, ofsY = -gap, gap
    elseif corner == "TOPRIGHT" then
        anchor = "BOTTOMLEFT"; ofsX, ofsY = gap, gap
    elseif corner == "BOTTOMLEFT" then
        anchor = "TOPRIGHT"; ofsX, ofsY = -gap, -gap
    elseif corner == "BOTTOMRIGHT" then
        anchor = "TOPLEFT"; ofsX, ofsY = gap, -gap
    end

    buffFrame:ClearAllPoints()
    buffFrame:SetPoint(anchor, UIParent, "BOTTOMLEFT", x + ofsX, y + ofsY)
end

-- ============================================================================
-- Shared aura query helper
-- GetPlayerAuraBySpellID can return nil in instanced combat.
-- SpellId fields can be secret, breaking comparisons.
-- AuraUtil.FindAuraByName works reliably as a fallback.
-- Returns: applications (stack count), expirationTime (or 0), found (bool)
-- ============================================================================
-- Addon Disarmament: aura fields (applications, expirationTime) may be
-- "secret values" during combat.  Secret values support arithmetic and can
-- be passed to blessed display helpers (AbbreviateNumbers, TruncateWhenZero,
-- SetCooldown, etc.) but fail on direct comparison (==, >, <) and on
-- tostring / string.format.  We return the RAW values here — callers must
-- use secret-safe display methods.
local function GetAuraInfo(spellID, spellName)
    local logging = DebugLog.enabled

    -- Method 1: Direct lookup by spell ID
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if logging then
            if not ok then
                DLog("AURA", spellName .. " M1-GetBySpellID: pcall FAILED, err=" .. SafeStr(auraData))
            elseif not auraData then
                DLog("AURA", spellName .. " M1-GetBySpellID: returned NIL (buff not active or blocked)")
            else
                DLog("AURA", spellName .. " M1-GetBySpellID: GOT DATA — " .. DumpAuraFields(auraData))
            end
        end
        if ok and auraData then
            return auraData.applications or 0, auraData.expirationTime or 0, true
        end
    end

    -- Method 2: Name-based lookup
    if spellName and AuraUtil and AuraUtil.FindAuraByName then
        local ok, name, icon, count, debuffType, duration, expirationTime =
            pcall(AuraUtil.FindAuraByName, spellName, "player", "HELPFUL")
        if logging then
            if not ok then
                DLog("AURA", spellName .. " M2-FindByName: pcall FAILED, err=" .. SafeStr(name))
            elseif not name then
                DLog("AURA", spellName .. " M2-FindByName: returned NIL")
            else
                DLog("AURA", spellName .. " M2-FindByName: name=" .. SafeStr(name)
                    .. " count=" .. SafeStr(count) .. " dur=" .. SafeStr(duration)
                    .. " exp=" .. SafeStr(expirationTime))
            end
        end
        if ok and name then
            return count or 0, expirationTime or 0, true
        end
    end

    -- Method 3: Index iteration with name matching
    if spellName and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local i = 1
        local foundAny = false
        -- One-time full dump: log every aura's fields during combat (first spell only to avoid spam)
        local doDump = logging and InCombatLockdown() and not DebugLog.didCombatDump and (spellName == "Abundance")
        while i <= 40 do
            local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not auraData then break end
            foundAny = true
            if doDump then
                DLog("DUMP", "Aura#" .. i .. ": " .. DumpAuraFields(auraData))
            end
            local nameOk, nameMatch = pcall(function()
                return auraData.name == spellName
            end)
            if nameOk and nameMatch then
                if logging then
                    DLog("AURA", spellName .. " M3-IndexScan: MATCH at i=" .. i .. " — " .. DumpAuraFields(auraData))
                end
                return auraData.applications or 0, auraData.expirationTime or 0, true
            end
            i = i + 1
        end
        if doDump then DebugLog.didCombatDump = true end
        if logging then
            DLog("AURA", spellName .. " M3-IndexScan: no match in " .. (i-1) .. " auras, foundAny=" .. tostring(foundAny))
        end
    end

    return 0, 0, false
end

-- ============================================================================
-- Tracked buff spell IDs & icon-based tracker updates
-- ============================================================================
ER.ABUNDANCE_SPELL_ID = 207640
ER.REFORESTATION_SPELL_ID = 392360
ER.CLEARCASTING_SPELL_ID = 16870

-- Known icon texture IDs for fallback matching during combat
-- (when name/spellId lookups are blocked by Addon Disarmament)
local TRACKER_ICONS = {
    [132124]  = { spellID = 207640, key = "abundance" },
    [1416160] = { spellID = 392360, key = "reforestation" },
    [136170]  = { spellID = 16870,  key = "clearcasting" },
}

-- Combat-safe aura lookup: tries GetAuraInfo first, then falls back
-- to scanning by icon texture ID (icons are not secret).
local function GetTrackerAura(spellID, spellName, iconID)
    -- First try the standard methods (work out of combat)
    local apps, expTime, found = GetAuraInfo(spellID, spellName)
    if found then return apps, expTime, true end

    -- Fallback: scan by icon texture (icons are numeric, not secret)
    if iconID and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local i = 1
        while i <= 40 do
            local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not auraData then break end
            local iconOk, iconMatch = pcall(function()
                return auraData.icon == iconID
            end)
            if iconOk and iconMatch then
                if DebugLog.enabled then
                    DLog("AURA", spellName .. " ICON-MATCH at i=" .. i .. " icon=" .. tostring(iconID)
                        .. " — " .. DumpAuraFields(auraData))
                end
                return auraData.applications or 0, auraData.expirationTime or 0, true
            end
            i = i + 1
        end
    end

    return 0, 0, false
end

-- Shared tracker update: show icon when buff active, set cooldown overlay
local function UpdateTrackerIcon(frame, configShowKey, spellID, spellName, iconID)
    if not frame then return end

    if not ThugUI_Config[configShowKey] or not ThugUI_Config.showECV then
        frame:Hide()
        return
    end

    if not ER.ecvContainer or not ER.ecvContainer:IsShown() then
        frame:Hide()
        return
    end

    local apps, expTime, found = GetTrackerAura(spellID, spellName, iconID)

    if found then
        -- Set cooldown sweep if the aura has a duration (e.g. Clearcasting)
        -- For permanent stacking buffs (duration=0), just show the icon
        local cd = frame.cooldown
        if cd then
            local setOk = pcall(function()
                if expTime > 0 then
                    local now = GetTime()
                    local duration = expTime - now
                    if duration > 0 then
                        cd:SetCooldown(now, duration)
                        cd:Show()
                    else
                        cd:Hide()
                    end
                else
                    cd:Hide()
                end
            end)
            if not setOk then
                -- expTime is secret — try passing raw values to SetCooldown
                -- Secret arithmetic: expTime - GetTime() should produce a secret duration
                pcall(function()
                    cd:SetCooldown(expTime - (expTime - GetTime()), expTime - GetTime())
                end)
            end
        end
        frame:Show()
    else
        frame:Hide()
    end
end

function ER:UpdateAbundanceStacks()
    UpdateTrackerIcon(ER.ecvAbundanceFrame, "ecvShowAbundance",
        ER.ABUNDANCE_SPELL_ID, "Abundance", 132124)
end

function ER:UpdateReforestationStacks()
    UpdateTrackerIcon(ER.ecvReforestationFrame, "ecvShowReforestation",
        ER.REFORESTATION_SPELL_ID, "Reforestation", 1416160)
end

function ER:UpdateClearcastingTimer()
    UpdateTrackerIcon(ER.ecvClearcastingFrame, "ecvShowClearcasting",
        ER.CLEARCASTING_SPELL_ID, "Clearcasting", 136170)
end

function ER:UpdateECVVisibility(inCombat)
    if not ER.ecvContainer then return end
    if not ThugUI_Config.showECV then
        ER.ecvContainer:Hide()
        return
    end

    if ThugUI_Config.ecvShowOnlyInCombat then
        if inCombat == nil then inCombat = ER:IsInCombat() end
        if not inCombat then
            ER.ecvContainer:Hide()
            return
        end
    end

    ER.ecvContainer:Show()
    ER:UpdateECVCooldowns()
end

function ER:UpdateECVCooldowns()
    if not ER.ecvContainer or not ER.ecvContainer:IsShown() then return end

    local iconSize = 32
    local padding = 4
    local visibleIndex = 0

    for _, icon in ipairs(ER.ecvIcons) do
        if IsSpellReady(icon.spellName) then
            icon:Show()
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", ER.ecvContainer, "TOPLEFT",
                visibleIndex * (iconSize + padding), 0)
            visibleIndex = visibleIndex + 1
        else
            icon:Hide()
        end
    end

    -- Resize container to visible icons only
    local totalW = math.max(visibleIndex * (iconSize + padding) - padding, 1)
    ER.ecvContainer:SetSize(totalW, iconSize)
end

function ER:UpdateECVPosition()
    if not ThugUI_Config.anchorECVToCursor then return end
    if not ER:IsInCombat() then return end

    local ecvFrame = ER.ecvContainer
    if not ecvFrame or not ecvFrame:IsShown() then return end

    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local ecvScale = ecvFrame:GetScale()
    local scaledX = cursorX / uiScale / ecvScale
    local scaledY = cursorY / uiScale / ecvScale

    local corner = ThugUI_Config.ecvAnchorCorner or "TOPLEFT"
    local gap = 8 / ecvScale  -- small gap so the bar doesn't sit right on the cursor

    -- Offset the bar so the chosen corner sits near the cursor
    local ofsX, ofsY = 0, 0
    if corner == "TOPLEFT" then
        ofsX, ofsY = gap, -gap
    elseif corner == "TOPRIGHT" then
        ofsX, ofsY = -gap, -gap
    elseif corner == "BOTTOMLEFT" then
        ofsX, ofsY = gap, gap
    elseif corner == "BOTTOMRIGHT" then
        ofsX, ofsY = -gap, gap
    end

    ecvFrame:ClearAllPoints()
    ecvFrame:SetPoint(corner, UIParent, "BOTTOMLEFT",
        scaledX + ofsX, scaledY + ofsY)
end

function ER:AnchorECVToCursor()
    if not ER.ecvContainer then return end

    -- Store original position before anchoring
    if not ER.ecvOriginalPoint then
        local point, relativeTo, relativePoint, xOfs, yOfs = ER.ecvContainer:GetPoint()
        ER.ecvOriginalPoint = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs,
        }
    end

    ER.ecvAnchored = true
    ER:UpdateECVCooldowns()
end

function ER:ReleaseECVAnchor()
    if not ER.ecvContainer then return end

    -- Restore original position
    if ER.ecvOriginalPoint then
        local op = ER.ecvOriginalPoint
        ER.ecvContainer:ClearAllPoints()
        ER.ecvContainer:SetPoint(op.point, op.relativeTo or UIParent,
            op.relativePoint, op.xOfs, op.yOfs)
    end

    ER.ecvAnchored = false
end

function ER:StartGCDAnimation(startTime, duration)
    if not ER.GCDCooldownFrame then return end
    if not ER.enableGCD then return end
    
    ER.isGCDAnimating = true
    
    local fillDrain = ThugUI_Config.gcdFillDrain or "fill"
    ER.GCDCooldownFrame:SetReverse(fillDrain == "fill")
    
    ER.GCDCooldownFrame:SetCooldown(startTime, duration)
    ER.GCDCooldownFrame:Show()
end

function ER:StartCastAnimation(startTime, duration)
    if not ER.CastFrame then return end
    if not ER.enableCast then return end
    
    ER.isCasting = true
    
    -- Detect if this is a channel or regular cast
    local isChanneling = UnitChannelInfo("player") ~= nil
    
    local fillDrain = ThugUI_Config.castFillDrain or "fill"
    local shouldReverse = (fillDrain == "fill")
    
    -- Invert for channels
    if isChanneling then
        shouldReverse = not shouldReverse
    end
    
    ER.CastFrame:SetReverse(shouldReverse)
    ER.CastFrame:SetCooldown(startTime, duration)
    ER.CastFrame:Show()
end

function ER:StopCastAnimation()
    if not ER.CastFrame then return end
    
    ER.isCasting = false
    ER.CastFrame:Clear()
    ER.CastFrame:Hide()
end

function ER:GCDCastHandler(self, event, unit, spellName, spellId)
    if GetTime() - ER.lastGCDTime < 0.1 then return end

    ER.lastGCDTime = GetTime()

    local GCDInfo = C_Spell.GetSpellCooldown(GCD_SPELL_ID)

    if GCDInfo and GCDInfo.duration > 0 then
        ER:StartGCDAnimation(GCDInfo.startTime, GCDInfo.duration)
    end
end

function ER:CastEventHandler(self, event, unit)
    local startTime, endTime, infoValid = nil, nil, false

    if event == "UNIT_SPELLCAST_START" then
        local cName, cRank, cTarget, cStartTime, cEndTime = UnitCastingInfo("player")
        startTime, endTime = cStartTime, cEndTime
        infoValid = true

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local chName, chRank, chTarget, chStartTime, chEndTime, isMoving = UnitChannelInfo("player")
        startTime, endTime = chStartTime, chEndTime
        infoValid = true
    end

    if infoValid and startTime and endTime then
        local duration = (endTime - startTime) / 1000

        if duration > 0.1 then
            ER:StartCastAnimation(startTime / 1000, duration)
        end

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        ER:StopCastAnimation()
    end
end

function ER:UpdateVisibility(forceState)
    if not ThugUI_CursorFrame then return end

    local inCombat = forceState
    if inCombat == nil then
        inCombat = ER:IsInCombat()
    end

    local ringsVisible = false
    
    if ThugUI_Config.showOnlyInCombat then
        if inCombat then
            ThugUI_CursorFrame:Show()
            ringsVisible = true
        else
            ThugUI_CursorFrame:Hide()
            ringsVisible = false
        end
    else
        ThugUI_CursorFrame:Show()
        ringsVisible = true
    end
    
    -- Handle cursor visibility based on rings visibility
    if ThugUI_Config.hideGameCursor then
        if ringsVisible then
            ER:HideGameCursor()
        else
            ER:RestoreGameCursor()
        end
    end
    
    -- Handle ECV anchoring based on combat state
    if ThugUI_Config.anchorECVToCursor then
        if inCombat then
            ER:AnchorECVToCursor()
        else
            ER:ReleaseECVAnchor()
        end
    end

    -- Update ECV visibility (show-only-in-combat setting)
    ER:UpdateECVVisibility(inCombat)
end

function ER:ResetCooldownFrames()
    ER.isGCDAnimating = false
    ER.isCasting = false
    
    -- Destroy old GCD frames
    if ER.GCDCooldownFrame then
        ER.GCDCooldownFrame:Hide()
        ER.GCDCooldownFrame:SetParent(nil)
        ER.GCDCooldownFrame = nil
    end
    if ER.GCDBackgroundFrame then
        ER.GCDBackgroundFrame:Hide()
        ER.GCDBackgroundFrame:SetParent(nil)
        ER.GCDBackgroundFrame = nil
    end
    
    -- Destroy old Cast frames
    if ER.CastFrame then
        ER.CastFrame:Hide()
        ER.CastFrame:SetParent(nil)
        ER.CastFrame = nil
    end
    if ER.CastBackgroundFrame then
        ER.CastBackgroundFrame:Hide()
        ER.CastBackgroundFrame:SetParent(nil)
        ER.CastBackgroundFrame = nil
    end
    
    -- Recreate GCD Background Frame
    local gcdBgFrame = CreateFrame("Cooldown", nil, ThugUI_CursorFrame)
    gcdBgFrame:SetSize(70, 70)
    gcdBgFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    gcdBgFrame:SetFrameLevel(2)
    ER.GCDBackgroundFrame = gcdBgFrame
    gcdBgFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    gcdBgFrame:SetSwipeColor(0.5, 0.5, 0.5, 0.7)
    gcdBgFrame:SetReverse(false)
    gcdBgFrame:SetHideCountdownNumbers(true)
    gcdBgFrame:SetCooldown(GetTime() - 1, 0.01)
    gcdBgFrame:Hide()

    -- Recreate GCD Cooldown Frame
    local cooldownFrame = CreateFrame("Cooldown", nil, ThugUI_CursorFrame)
    cooldownFrame:SetSize(50, 50)
    cooldownFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    cooldownFrame:SetFrameLevel(3)
    ER.GCDCooldownFrame = cooldownFrame
    cooldownFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    local r, g, b = ER:GetClassColor("gcd")
    cooldownFrame:SetSwipeColor(r, g, b, 1.0)
    cooldownFrame:SetHideCountdownNumbers(true)
    
    local gcdRotation = ThugUI_Config.gcdRotation or 12
    cooldownFrame:SetRotation(ER:ClockToRadians(gcdRotation))
    cooldownFrame:Hide()

    -- Recreate Cast Background Frame
    local castBgFrame = CreateFrame("Cooldown", nil, ThugUI_CursorFrame)
    castBgFrame:SetSize(70, 70)
    castBgFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    castBgFrame:SetFrameLevel(2)
    ER.CastBackgroundFrame = castBgFrame
    castBgFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    castBgFrame:SetSwipeColor(0.5, 0.5, 0.5, 0.7)
    castBgFrame:SetReverse(false)
    castBgFrame:SetHideCountdownNumbers(true)
    castBgFrame:SetCooldown(GetTime() - 1, 0.01)
    castBgFrame:Hide()

    -- Recreate Cast Frame
    local castFrame = CreateFrame("Cooldown", nil, ThugUI_CursorFrame)
    castFrame:SetSize(90, 90)
    castFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    castFrame:SetFrameLevel(3)
    ER.CastFrame = castFrame
    castFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    r, g, b = ER:GetClassColor("cast")
    castFrame:SetSwipeColor(r, g, b, 1.0)
    castFrame:SetHideCountdownNumbers(true)
    
    local castRotation = ThugUI_Config.castRotation or 12
    castFrame:SetRotation(ER:ClockToRadians(castRotation))
    castFrame:Hide()
    
    if ER.ApplySettings then
        ER:ApplySettings()
    end
end

function ER:SetupUI()
    local transparency = ThugUI_Config.transparency or 1.0
    ThugUI_CursorFrame:SetAlpha(transparency)
    ThugUI_CursorFrame:SetFrameStrata("HIGH")
    ThugUI_CursorFrame:SetToplevel(false)
    ThugUI_CursorFrame:Show()
    ER:SetGroupScale(ER.currentGroupScale)
    ThugUI_CursorFrame.MainRing:Show()
    
    ER:UpdateReticle()

    -- GCD Background Frame
    local gcdBgFrame = CreateFrame("Cooldown", "ThugUI_GCD_BG_COOLDOWN", ThugUI_CursorFrame)
    gcdBgFrame:SetSize(70, 70)
    gcdBgFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    gcdBgFrame:SetFrameLevel(2)
    ER.GCDBackgroundFrame = gcdBgFrame
    gcdBgFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    gcdBgFrame:SetSwipeColor(0.5, 0.5, 0.5, 0.7)
    gcdBgFrame:SetReverse(false)
    gcdBgFrame:SetHideCountdownNumbers(true)
    gcdBgFrame:SetCooldown(GetTime() - 1, 0.01)
    gcdBgFrame:Hide()

    -- GCD Cooldown Frame
    local cooldownFrame = CreateFrame("Cooldown", "ThugUI_GCD_COOLDOWN", ThugUI_CursorFrame)
    cooldownFrame:SetSize(50, 50)
    cooldownFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    cooldownFrame:SetFrameLevel(3)
    ER.GCDCooldownFrame = cooldownFrame
    cooldownFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    local r, g, b = ER:GetClassColor("gcd")
    cooldownFrame:SetSwipeColor(r, g, b, 1.0)
    cooldownFrame:SetHideCountdownNumbers(true)
    
    local gcdRotation = ThugUI_Config.gcdRotation or 12
    cooldownFrame:SetRotation(ER:ClockToRadians(gcdRotation))
    cooldownFrame:Hide()

    -- Cast Background Frame
    local castBgFrame = CreateFrame("Cooldown", "ThugUI_CAST_BG_COOLDOWN", ThugUI_CursorFrame)
    castBgFrame:SetSize(70, 70)
    castBgFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    castBgFrame:SetFrameLevel(2)
    ER.CastBackgroundFrame = castBgFrame
    castBgFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    castBgFrame:SetSwipeColor(0.5, 0.5, 0.5, 0.7)
    castBgFrame:SetReverse(false)
    castBgFrame:SetHideCountdownNumbers(true)
    castBgFrame:SetCooldown(GetTime() - 1, 0.01)
    castBgFrame:Hide()

    -- Cast Frame
    local castFrame = CreateFrame("Cooldown", "ThugUI_CAST_COOLDOWN", ThugUI_CursorFrame)
    castFrame:SetSize(90, 90)
    castFrame:SetPoint("CENTER", ThugUI_CursorFrame, "CENTER")
    castFrame:SetFrameLevel(3)
    ER.CastFrame = castFrame
    castFrame:SetSwipeTexture("Interface\\AddOns\\ThugUI\\media\\Ring_Main")
    r, g, b = ER:GetClassColor("cast")
    castFrame:SetSwipeColor(r, g, b, 1.0)
    castFrame:SetHideCountdownNumbers(true)
    
    local castRotation = ThugUI_Config.castRotation or 12
    castFrame:SetRotation(ER:ClockToRadians(castRotation))
    castFrame:Hide()

    if ER.ApplySettings then
        ER:ApplySettings()
    end

    -- Build the Essential Cooldown Viewer
    ER:CreateECV()

    TrackerFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function ER:OnInitialize()
    ER.TrackerFrame = TrackerFrame

    TrackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    TrackerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    TrackerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    TrackerFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

    TrackerFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            if ThugUI_CursorFrame then
                ER:SetupUI()
            end

        elseif event:match("UNIT_SPELLCAST_") then
            ER:GCDCastHandler(self, event, ...)
            ER:CastEventHandler(self, event, ...)

        elseif event == "PLAYER_REGEN_DISABLED" then
            DLog("TRANSITION", ">>> ENTERING COMBAT — container="
                .. (ER.ecvContainer and (ER.ecvContainer:IsShown() and "SHOWN" or "HIDDEN") or "NIL")
                .. " testMode=" .. tostring(ThugUI_Config.testMode)
                .. " showECV=" .. tostring(ThugUI_Config.showECV)
                .. " combatOnly=" .. tostring(ThugUI_Config.ecvShowOnlyInCombat))
            ER:UpdateVisibility(true)
            DLog("TRANSITION", ">>> AFTER UpdateVisibility(true) — container="
                .. (ER.ecvContainer and (ER.ecvContainer:IsShown() and "SHOWN" or "HIDDEN") or "NIL"))
        elseif event == "PLAYER_REGEN_ENABLED" then
            DLog("TRANSITION", "<<< LEAVING COMBAT — container="
                .. (ER.ecvContainer and (ER.ecvContainer:IsShown() and "SHOWN" or "HIDDEN") or "NIL"))
            ER:UpdateVisibility(false)
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            ER:UpdateECVCooldowns()
        end
    end)

    TrackerFrame:SetScript("OnUpdate", function(self, elapsed)
        ER:OnUpdate(elapsed)
    end)
    TrackerFrame:Show()
    ER:OnUpdate(0)
end

LoaderFrame:SetScript("OnEvent", function(self, event, addon)
    print("ThugUI: ADDON_LOADED fired for: " .. tostring(addon))
    if event == "ADDON_LOADED" and addon == "ThugUI" then
        ThugUI_DebugLog = ThugUI_DebugLog or {}
        print("ThugUI: Initializing Essential Rings...")
        ER:OnInitialize()
        ER:InitializeSettings()
        ER:CreateSettingsPanel()
        if ThugUI.FrameHider then
            ThugUI.FrameHider:ApplyAll()
        end
        print("ThugUI: Initialization complete!")
        self:UnregisterAllEvents()
    end
end)
LoaderFrame:RegisterEvent("ADDON_LOADED")
