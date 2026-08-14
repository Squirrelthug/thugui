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

-- Single switch that drives every ThugUI debug output: the aura DebugLog and
-- init chatter. Tied to the "Debug Mode" checkbox and the /thugdebug command.
function ER:SetDebugMode(enabled)
    enabled = not not enabled
    ThugUI_Config = ThugUI_Config or {}
    ThugUI_Config.debugMode = enabled
    DebugLog.enabled = enabled
    if enabled then
        ThugUI_DebugLog = {}  -- clear on enable
        DebugLog.didCombatDump = false  -- reset one-time dump flag
        print("|cff00ff00ThugUI Debug:|r Debug mode ON — aura queries will be logged.")
        print("|cff00ff00ThugUI Debug:|r Enter combat with buffs, then /reload to save log; /thuglog to view.")
    else
        print("|cff00ff00ThugUI Debug:|r Debug mode OFF.")
    end
    if ER.debugModeCheckbox then
        ER.debugModeCheckbox:SetChecked(enabled)
    end
end

SLASH_THUGDEBUG1 = "/thugdebug"
SlashCmdList["THUGDEBUG"] = function()
    ER:SetDebugMode(not (ThugUI_Config and ThugUI_Config.debugMode))
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

-- ============================================================================
-- BCV iteration dump — writes to the ThugUI_BCVDump SavedVariable (declared in
-- the .toc) so the results can be read straight off disk after a /reload, with
-- no copy/paste. Everything is stored via SafeStr (plain strings) so secret
-- values from instanced combat can't break SavedVariables serialization.
-- ============================================================================

-- Probe one spell/aura by name or numeric ID. Returns a flat table of strings:
-- whether the texture resolves, whether the player knows it, and the cooldown /
-- charge data the game exposes (tells us how Eclipse etc. can be displayed).
local function ProbeSpell(query)
    local entry = { query = SafeStr(query) }

    entry.texture = SafeStr(C_Spell.GetSpellTexture(query))

    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(query)
    if info then
        entry.resolvedName = SafeStr(info.name)
        entry.resolvedID = SafeStr(info.spellID)
    else
        entry.resolvedName = "nil"
        entry.resolvedID = "nil"
    end

    local resolvedID = (info and info.spellID) or (type(query) == "number" and query) or nil
    entry.known = resolvedID and SafeStr(IsPlayerSpell and IsPlayerSpell(resolvedID)) or "n/a"

    local okC, cd = pcall(C_Spell.GetSpellCooldown, query)
    if okC and cd then
        entry.cdIsActive = SafeStr(cd.isActive)
        entry.cdIsOnGCD  = SafeStr(cd.isOnGCD)
        entry.cdStart    = SafeStr(cd.startTime)
        entry.cdDuration = SafeStr(cd.duration)
    else
        entry.cooldown = okC and "nil" or ("pcall failed " .. SafeStr(cd))
    end

    local okCh, ch = pcall(C_Spell.GetSpellCharges, query)
    if okCh and ch then
        entry.chCurrent  = SafeStr(ch.currentCharges)
        entry.chMax      = SafeStr(ch.maxCharges)
        entry.chCdStart  = SafeStr(ch.cooldownStartTime)
        entry.chCdLength = SafeStr(ch.cooldownDuration)
    else
        entry.charges = okCh and "nil (not a charge spell)" or ("pcall failed " .. SafeStr(ch))
    end

    return entry
end

-- The decisive in-combat test: does GetPlayerAuraBySpellID return a usable
-- table for a known buff ID while in combat? Reports presence, whether the
-- fields are secret, and whether the icon can even be compared (which is what
-- the show/hide logic needs). Run /thugbcv WHILE the buff is up.
local function TestAuraRead(id)
    local r = { id = SafeStr(id) }
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        r.result = "API missing"
        return r
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok then
        r.result = "pcall failed: " .. SafeStr(aura)
        return r
    end
    if not aura then
        r.result = "nil (not present, or blocked in combat)"
        return r
    end
    r.result      = "TABLE returned"
    r.nameSecret  = SafeStr(issecretvalue and issecretvalue(aura.name))
    r.iconSecret  = SafeStr(issecretvalue and issecretvalue(aura.icon))
    r.iconValue   = SafeStr(aura.icon)
    -- Can we branch on the icon? (secret values error on comparison)
    local eqOk = pcall(function() return aura.icon == 0 end)
    r.iconComparable = eqOk and "yes" or "no (secret)"
    return r
end

-- Buff IDs to test reads on. Includes the eclipse/proc IDs plus likely always-up
-- control buffs (Mark of the Wild 1126, Moonkin Form 24858) so we get a signal
-- even if the eclipse/proc buffs happen not to be up at capture time.
local AURA_READ_IDS = { 48517, 48518, 393944, 393942, 450360, 1126, 24858 }

-- Names/IDs auto-probed by /thugbcv so we capture Eclipse + the proc buffs in
-- one shot without the user typing anything.
local BCV_PROBE_LIST = {
    "Eclipse", "Eclipse (Solar)", "Eclipse (Lunar)",
    "Starweaver's Weft", "Starweaver's Warp", "Touch the Cosmos",
    "Starsurge", "Starfall",
    48517, 48518, 393944, 393942, 450360,
}

-- /thugbcv — capture all player buffs + auto-probe the Balance spells into the
-- ThugUI_BCVDump SavedVariable. Run it with Eclipse active and the free-cast
-- procs up, then /reload (or log out) to flush it to disk.
SLASH_THUGBCV1 = "/thugbcv"
SlashCmdList["THUGBCV"] = function()
    ThugUI_BCVDump = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or SafeStr(GetTime()),
        inCombat = InCombatLockdown() and "yes" or "no",
        buffs = {},
        spellProbes = {},
        auraReadTests = {},
    }

    -- 1) Every HELPFUL aura on the player
    local i = 1
    while i <= 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        table.insert(ThugUI_BCVDump.buffs, {
            index  = i,
            name   = SafeStr(aura.name),
            id     = SafeStr(aura.spellId),
            icon   = SafeStr(aura.icon),
            stacks = SafeStr(aura.applications),
        })
        i = i + 1
    end

    -- 2) Auto-probe Eclipse + proc spells/buffs
    for _, q in ipairs(BCV_PROBE_LIST) do
        table.insert(ThugUI_BCVDump.spellProbes, ProbeSpell(q))
    end

    -- 3) The decisive test: can we read a known buff by ID in combat?
    for _, id in ipairs(AURA_READ_IDS) do
        table.insert(ThugUI_BCVDump.auraReadTests, TestAuraRead(id))
    end

    print(string.format("|cff00ff00ThugUI BCV:|r captured %d buffs + %d probes to ThugUI_BCVDump. "
        .. "Now /reload (or log out) to write it to disk.",
        #ThugUI_BCVDump.buffs, #ThugUI_BCVDump.spellProbes))
end

-- /thugspell <name|id> — ad-hoc probe; appends one entry to ThugUI_BCVDump.
SLASH_THUGSPELL1 = "/thugspell"
SlashCmdList["THUGSPELL"] = function(msg)
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    if msg == "" then
        print("|cff00ff00ThugUI Spell:|r usage — /thugspell <spell name or id>")
        return
    end
    ThugUI_BCVDump = ThugUI_BCVDump or { buffs = {}, spellProbes = {} }
    ThugUI_BCVDump.spellProbes = ThugUI_BCVDump.spellProbes or {}
    local query = tonumber(msg) or msg
    table.insert(ThugUI_BCVDump.spellProbes, ProbeSpell(query))
    print("|cff00ff00ThugUI Spell:|r probed '" .. msg .. "' into ThugUI_BCVDump. /reload to flush.")
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

    -- ThugUI_Config.cvCategoryArt (the CooldownViewer's persisted cache of a
    -- category-only cell's name/icon -- potions, healthstones) is deliberately
    -- NOT defaulted here. ER:InitializeSettings seeds this list with
    -- `ThugUI_Config[key] = value`, a plain reference copy, so a table default
    -- makes the live config and ER.defaults the SAME table. The *CustomColor
    -- triples above get away with it because every setter REPLACES them
    -- wholesale (`Cfg().xCustomColor = { r = r, ... }`), which breaks the
    -- alias on first write. cvCategoryArt is the opposite: it is mutated in
    -- place, one key per resolved category, so it would accumulate live data
    -- inside "the defaults" and any reset assigning it back would be a silent
    -- no-op. Data.CategoryArtCache seeds it lazily instead, exactly as
    -- Data.Store already does for the table-valued ThugUI_Config.cv.
    -- DECISIONS.md §25.

    -- Balance Cooldown Viewer (second bar, Balance spec only) — its own
    -- independent appearance/anchor settings, separate from the Resto bar.
    showBCV = false,
    bcvShowOnlyInCombat = false,
    anchorBCVToCursor = false,
    bcvAnchorCorner = "TOPLEFT",
    bcvScale = 1.0,
    bcvPoint = nil,  -- saved position {point, relPoint, x, y}
    bcvShowStarsurgeProc = true,

    -- Guardian Cooldown Viewer (Guardian spec only) — its own independent
    -- appearance/anchor settings, separate from the Resto/Balance bars.
    showGCV = false,
    gcvShowOnlyInCombat = false,
    anchorGCVToCursor = false,
    gcvAnchorCorner = "TOPLEFT",
    gcvScale = 1.0,
    gcvPoint = nil,  -- saved position {point, relPoint, x, y}

    -- Resource Ring (modules/ResourceRing.lua) — a radial resource meter
    -- sharing the cast ring's band, with the cast sweep drawn over it.
    -- Off by default: it changes what the cursor looks like, so it should be
    -- an explicit choice rather than something an update does to you.
    showResourceRing = false,
    resourceRingColorMode = "power",  -- power | class | custom
    resourceRingCustomColor = {r = 0.3, g = 0.5, b = 0.9},
    resourceRingAlpha = 0.55,
    -- always | combat | rings. Its own rule rather than the cursor rings',
    -- which are usually combat-only — that is not what "always show my
    -- resource" should mean.
    resourceRingVisibility = "always",
    -- clockwise | counterclockwise. Which way round the ring empties.
    -- Applied through the texture's SetRadialProgressBarReverse, which only
    -- the radial render mode has — see modules/ResourceRing.lua.
    --
    -- `resourceRingRadialBar` used to live here, choosing between a Cooldown
    -- ring and the radial one. Both it and the Cooldown implementation were
    -- removed on 2026-08-13 (DECISIONS.md §27) — the Cooldown path never
    -- tracked at all, so there was nothing to fall back to. A stale `true` or
    -- `false` left in a player's SavedVariables is simply ignored; it is not
    -- migrated, because neither value means anything now.
    resourceRingDrainDirection = "clockwise",
    -- Where the ring starts, as a clock position, matching gcdRotation and
    -- castRotation. Its own key rather than borrowing castRotation, which is
    -- what it did until 2026-08-13: the resource ring is a StatusBar in radial
    -- render mode, not a Cooldown, and the two do not share a start
    -- convention (DECISIONS.md §23). Blizzard start radial bars at the BOTTOM
    -- -- their own docs for SetRadialProgressBarStartOffset say "0 is at the
    -- bottom" -- so 12 here needs a real half-turn of offset, where a Cooldown
    -- at 12 needs none.
    resourceRingRotation = 12,

    -- Test mode
    testMode = false,

    -- Debug mode — single switch for all ThugUI debug output (aura logger,
    -- init chatter). Toggled by the settings checkbox or /thugdebug.
    debugMode = false,

    -- Frame Hider settings
    -- (objective tracker visibility now belongs to the OrbAnchors module,
    -- stored under ThugUIDB.OrbAnchors.objectivesOrb.visible)
    hideStanceBar = true,
    hideBagButtons = true,
    hideCharacterFrame = false,

    -- Prey Crystal (UIWidgetPowerBarContainerFrame)
    movePreyCrystal = true,
    preyCrystalPoint = nil,  -- saved position {point, relPoint, x, y}

    -- Target of Target (modules/TargetOfTarget, built on oUF)
    -- Off by default: enabling it turns off Blizzard's own target-of-target
    -- frame, which should be an explicit choice rather than something an
    -- update does to you.
    totEnabled = false,
    totUnlocked = false,  -- shows the drag handle over the frame
    totPoint = nil,  -- saved position {point, relPoint, x, y}

    -- Frame parts
    totShowHealthBar = true,
    totShowPowerBar = true,
    totShowPortrait = true,
    totShowName = true,
    totShowReputation = true,

    -- Appearance
    totHealthColor = "blizzard",  -- blizzard | class | reaction
    totScale = 1.0,

    -- Behaviour
    totHideBlizzardToT = true,
    -- Set at runtime when we turn the showTargetOfTarget CVar off, so unticking
    -- the option can give the player back the value they actually had.
    totRestoreBlizzardToT = nil,
}

-- Returns true if actually in combat OR test mode is on
function ER:IsInCombat()
    return InCombatLockdown() or (ThugUI_Config.testMode == true)
end

-- ============================================================================
-- Druid spec gating
-- The Essential (Resto) bar and the Balance bar are each tied to a single
-- Druid specialization. GetSpecialization() returns the active spec index:
--   1 = Balance, 2 = Feral, 3 = Guardian, 4 = Restoration
-- ============================================================================
local DRUID_SPEC_BALANCE = 1
local DRUID_SPEC_GUARDIAN = 3
local DRUID_SPEC_RESTORATION = 4

function ER:IsDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

function ER:GetActiveSpecIndex()
    if not GetSpecialization then return nil end
    return GetSpecialization()
end

function ER:IsRestoSpec()
    return ER:IsDruid() and ER:GetActiveSpecIndex() == DRUID_SPEC_RESTORATION
end

function ER:IsBalanceSpec()
    return ER:IsDruid() and ER:GetActiveSpecIndex() == DRUID_SPEC_BALANCE
end

function ER:IsGuardianSpec()
    return ER:IsDruid() and ER:GetActiveSpecIndex() == DRUID_SPEC_GUARDIAN
end

-- The ECV/BCV/GCV bars below have been superseded by the generic, per-spec grid
-- engine in modules/CooldownViewer. They are kept intact, not deleted, as the
-- fallback: setting ThugUI_Config.cvUseLegacy (or /thugcv legacy) hands control
-- back to them wholesale. Their settings panels are untouched too.
--
-- While the grid engine owns the cooldown viewer, every legacy bar reports
-- "should not be visible" so the two systems can never draw at once.
function ER:LegacyBarsActive()
    return ThugUI_Config and ThugUI_Config.cvUseLegacy and true or false
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
    -- Balance bar follows cursor (Balance spec, in combat, if enabled)
    ER:UpdateBCVPosition()
    -- Guardian bar follows cursor (Guardian spec, in combat, if enabled)
    ER:UpdateGCVPosition()

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
        ER:UpdateBCVCooldowns()
        ER:UpdateGCVCooldowns()

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

    -- Namespaced, and it MUST stay namespaced. This frame predates Blizzard's
    -- Cooldown Manager, and when 11.1.5 shipped one it happened to name its own
    -- frame "EssentialCooldownViewer" too. Creating ours with that name
    -- overwrote the global from tainted addon code, so every piece of Blizzard
    -- code that resolves the viewer by name executed tainted by us -- and their
    -- code reads fields that are secret under taint, so it threw. See
    -- DECISIONS.md §15. The sibling BCV/GCV frames were always ThugUI_-prefixed;
    -- this one was the outlier, from the very first commit.
    local f = CreateFrame("Frame", "ThugUI_EssentialCooldownViewer", UIParent)
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
--
-- WARNING, added 2026-08-09. This function does three of the exact things that
-- killed Blizzard's cooldown viewer for a whole session -- it moves and scales
-- an Edit Mode system frame, and it calls their `UpdateSystem` /
-- `LayoutApplied` from our stack. See DECISIONS.md §15 for what that costs:
-- their own OnEvent handlers then run tainted by us and throw on secret fields,
-- which empties the item pool until /reload.
--
-- It is left in place because the setting is **off**, it predates what we know,
-- and it is the legacy escape hatch. `CooldownViewer/BlizzBuffs.lua` is the
-- supported route now and taints nothing. If this ever needs to come back,
-- rewrite it the way BlizzBuffs was rewritten: anchor from our side, keep
-- bookkeeping in side tables, and never call their methods.
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

-- ============================================================================
-- BALANCE COOLDOWN VIEWER (BCV)
-- A second cursor-anchored bar, shown only in Balance spec. Two display modes:
--  * "cooldown" — the icon shows while the ability is usable (with a charge
--    count for charge builds like Celestial Alignment) and hides once spent.
--    Talent-gated so only the build you run resolves (Incarnation vs CA).
--  * "buff" — the free-cast proc buffs (Starweaver's Weft, Starweaver's Warp,
--    Touch the Cosmos) each show their own icon while that buff is active.
-- NOTE: Eclipse itself has no cooldown/charge/cast data the API exposes, so it
-- cannot be shown here and is intentionally not in the list.
-- ============================================================================

-- spellID drives the talent (IsPlayerSpell) gate and texture lookup; the
-- cooldown/charge state and aura presence resolve by NAME at runtime so they
-- follow whatever version the player actually has talented.
ER.bcvSpellDefs = {
    { key = "furyofelune",   name = "Fury of Elune",                spellID = 202770, mode = "cooldown", talentGated = true },
    { key = "forceofnature", name = "Force of Nature",              spellID = 205636, mode = "cooldown", talentGated = true },
    -- The two builds of the big Balance cooldown. Each is talent-gated, so only
    -- the one you actually run resolves and shows. Cooldown mode shows the icon
    -- while usable (and the charge count if it's a charge build), hiding once
    -- spent. (Eclipse itself has no cooldown/charge data, so it can't be shown
    -- this way — removed.)
    { key = "incarnation",        name = "Incarnation: Chosen of Elune", spellID = 102560, mode = "cooldown", talentGated = true, strictAvail = true },
    { key = "celestialalignment", name = "Celestial Alignment",          spellID = 194223, mode = "cooldown", talentGated = true, strictAvail = true },
    -- Free-cast proc buffs shown as their own icons while active (gated by the
    -- "show procs" checkbox). Weft = free Starsurge, Warp = free Starfall,
    -- Touch the Cosmos = next Starsurge/Starfall free & buffed.
    { key = "starweaversweft", name = "Starweaver's Weft", spellID = 393944, mode = "buff", talentGated = false,
      gateConfig = "bcvShowStarsurgeProc",
      buffAuras = { { name = "Starweaver's Weft", id = 393944, icon = 429383 } } },
    { key = "starweaverswarp", name = "Starweaver's Warp", spellID = 393942, mode = "buff", talentGated = false,
      gateConfig = "bcvShowStarsurgeProc",
      buffAuras = { { name = "Starweaver's Warp", id = 393942, icon = 1052602 } } },
    { key = "touchthecosmos",  name = "Touch the Cosmos",  spellID = 450360, mode = "buff", talentGated = false,
      gateConfig = "bcvShowStarsurgeProc",
      buffAuras = { { name = "Touch the Cosmos", id = 450360, icon = 1120185 } } },
}

local BCV_ICON_SIZE = 32
local BCV_PADDING = 4

-- Resolve a def's numeric spell ID. Defs normally hardcode one, but an entry
-- may omit it (spell added in a patch we haven't pinned an ID for yet); in that
-- case ask the game by name. C_Spell.GetSpellInfo only resolves names the
-- player actually has, so a nil return also means "not talented".
local function ResolveDefSpellID(def)
    if def.spellID then return def.spellID end
    local ok, info = pcall(C_Spell.GetSpellInfo, def.name)
    return (ok and info and info.spellID) or nil
end

-- Is a (talented) spell currently available to the player?
local function IsSpellAvailable(spellID)
    if not spellID then return true end
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID) then return true end
    return false
end

-- Create the container once. Icons are created lazily (EnsureBCVIcons) so that
-- Balance spells resolve correctly even if you logged in as another spec.
function ER:CreateBCV()
    if ER.bcvContainer then return end

    local f = CreateFrame("Frame", "ThugUI_BalanceCooldownViewer", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    ER.bcvContainer = f
    ER.bcvIcons = {}
    ER.bcvIconsByKey = {}

    local saved = ThugUI_Config.bcvPoint
    if saved then
        f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
    end

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ThugUI_Config.bcvPoint = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    f:SetScale(ThugUI_Config.bcvScale or 1.0)

    ER:EnsureBCVIcons()
    ER:UpdateBCVVisibility()
end

-- Create any not-yet-created icons whose texture now resolves. Idempotent.
function ER:EnsureBCVIcons()
    if not ER.bcvContainer then return end
    ER.bcvIconsByKey = ER.bcvIconsByKey or {}

    for _, def in ipairs(ER.bcvSpellDefs) do
        if not ER.bcvIconsByKey[def.key] then
            local texture = (def.spellID and C_Spell.GetSpellTexture(def.spellID))
                or C_Spell.GetSpellTexture(def.name)
            if texture then
                local icon = CreateFrame("Frame", "ThugUI_BCV_" .. def.key, ER.bcvContainer)
                icon:SetSize(BCV_ICON_SIZE, BCV_ICON_SIZE)

                local bg = icon:CreateTexture(nil, "BACKGROUND")
                bg:SetPoint("TOPLEFT", -1, 1)
                bg:SetPoint("BOTTOMRIGHT", 1, -1)
                bg:SetColorTexture(0, 0, 0, 0.8)

                local tex = icon:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture(texture)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                icon.tex = tex
                icon.baseTexture = texture  -- remembered so buff-mode art can swap and restore

                -- Cooldown sweep, used by "buff" mode to show time remaining.
                -- Harmless/unused for cooldown & proc modes.
                local cd = CreateFrame("Cooldown", "ThugUI_BCV_" .. def.key .. "Cooldown", icon, "CooldownFrameTemplate")
                cd:SetAllPoints()
                cd:SetDrawEdge(true)
                cd:SetHideCountdownNumbers(false)
                icon.cooldown = cd

                -- Charge-count text (bottom-right), shown for charge-build
                -- cooldowns like Celestial Alignment when current charges read.
                local count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
                count:Hide()
                icon.count = count

                icon.def = def
                icon:Hide()
                ER.bcvIconsByKey[def.key] = icon
                table.insert(ER.bcvIcons, icon)
            end
        end
    end
end

-- For "buff" mode (Eclipse, free-cast procs): find the first active buff in def.buffAuras.
-- Returns found, expirationTime, and the matched aura entry (so the caller can
-- swap to that buff's art, e.g. Solar vs Lunar).
local function GetBCVBuff(def)
    if not def.buffAuras then return false, 0, nil end
    for _, aura in ipairs(def.buffAuras) do
        local _, expTime, found = GetTrackerAura(aura.id, aura.name, aura.icon)
        if found then return true, expTime, aura end
    end
    return false, 0, nil
end

function ER:UpdateBCVCooldowns()
    if not ER.bcvContainer or not ER.bcvContainer:IsShown() then return end
    ER.bcvIconsByKey = ER.bcvIconsByKey or {}

    local visibleIndex = 0
    for _, def in ipairs(ER.bcvSpellDefs) do
        local icon = ER.bcvIconsByKey[def.key]
        if icon then
            local show = false

            -- strictAvail (Incarnation / Celestial Alignment override each
            -- other) gates on IsPlayerSpell only, so the replaced base spell
            -- doesn't also report as available and double up.
            local available
            if not def.talentGated then
                available = true
            elseif def.strictAvail then
                available = (IsPlayerSpell and IsPlayerSpell(def.spellID)) or false
            else
                available = IsSpellAvailable(def.spellID)
            end

            if not available then
                show = false
            elseif def.mode == "buff" then
                -- Buff icon (free-cast procs): show while the aura is up, with
                -- the remaining-time sweep. Optional config gate.
                local gated = def.gateConfig and not ThugUI_Config[def.gateConfig]
                local found, expTime, aura = false, 0, nil
                if not gated then
                    found, expTime, aura = GetBCVBuff(def)
                end
                show = found
                if show then
                    if aura and aura.id and icon.tex then
                        local art = C_Spell.GetSpellTexture(aura.id)
                        icon.tex:SetTexture(art or icon.baseTexture)
                    end
                    local cd = icon.cooldown
                    if cd then
                        -- secret-safe, mirrors UpdateTrackerIcon
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
                            pcall(function() cd:SetCooldown(GetTime(), expTime - GetTime()) end)
                        end
                    end
                elseif icon.cooldown then
                    icon.cooldown:Hide()
                end
            else
                -- cooldown / charge mode: show while usable, with a charge count
                -- if this is a charge build (e.g. Celestial Alignment) and the
                -- current charges are readable (not a secret value in combat).
                show = IsSpellReady(def.name)
                if show and icon.count then
                    local ok, ch = pcall(C_Spell.GetSpellCharges, def.name)
                    local cur = ok and ch and ch.currentCharges
                    local maxc = ok and ch and ch.maxCharges
                    if cur ~= nil and maxc and maxc > 1
                        and not (issecretvalue and issecretvalue(cur)) then
                        icon.count:SetText(cur)
                        icon.count:Show()
                    else
                        icon.count:Hide()
                    end
                elseif icon.count then
                    icon.count:Hide()
                end
            end

            if show then
                icon:Show()
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", ER.bcvContainer, "TOPLEFT",
                    visibleIndex * (BCV_ICON_SIZE + BCV_PADDING), 0)
                visibleIndex = visibleIndex + 1
            else
                icon:Hide()
            end
        end
    end

    local totalW = math.max(visibleIndex * (BCV_ICON_SIZE + BCV_PADDING) - BCV_PADDING, 1)
    ER.bcvContainer:SetSize(totalW, BCV_ICON_SIZE)
end

function ER:UpdateBCVVisibility(inCombat)
    if not ER.bcvContainer then return end

    if not ER:LegacyBarsActive() then
        ER.bcvContainer:Hide()
        return
    end

    if not ThugUI_Config.showBCV or not ER:IsBalanceSpec() then
        ER.bcvContainer:Hide()
        return
    end

    -- Make sure Balance icons exist now that we're in Balance spec.
    ER:EnsureBCVIcons()

    if ThugUI_Config.bcvShowOnlyInCombat then
        if inCombat == nil then inCombat = ER:IsInCombat() end
        if not inCombat then
            ER.bcvContainer:Hide()
            return
        end
    end

    ER.bcvContainer:Show()
    ER:UpdateBCVCooldowns()
end

function ER:UpdateBCVPosition()
    if not ThugUI_Config.anchorBCVToCursor then return end
    if not ER:IsBalanceSpec() then return end
    if not ER:IsInCombat() then return end

    local f = ER.bcvContainer
    if not f or not f:IsShown() then return end

    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local scale = f:GetScale()
    local scaledX = cursorX / uiScale / scale
    local scaledY = cursorY / uiScale / scale

    local corner = ThugUI_Config.bcvAnchorCorner or "TOPLEFT"
    local gap = 8 / scale
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

    f:ClearAllPoints()
    f:SetPoint(corner, UIParent, "BOTTOMLEFT", scaledX + ofsX, scaledY + ofsY)
end

-- Restore the bar to its saved (Edit Mode / dragged) position when it stops
-- following the cursor (combat ended).
function ER:ReleaseBCVAnchor()
    if not ER.bcvContainer then return end
    local saved = ThugUI_Config.bcvPoint
    ER.bcvContainer:ClearAllPoints()
    if saved then
        ER.bcvContainer:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        ER.bcvContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
    end
end

-- ============================================================================
-- GUARDIAN COOLDOWN VIEWER (GCV)
-- A cursor-anchored bar shown only in Guardian spec. Every entry is a plain
-- "cooldown" tracker: the icon shows while the ability is ready and hides once
-- it goes on cooldown — the same behaviour as the ECV/BCV cooldown icons.
-- spellID drives the texture lookup and (for talents) the IsPlayerSpell gate;
-- the cooldown state resolves BY NAME so it follows whatever the player has.
-- ============================================================================
ER.gcvSpellDefs = {
    { key = "mangle",    name = "Mangle",              spellID = 33917,  talentGated = false },
    { key = "thrash",    name = "Thrash",              spellID = 77758,  talentGated = false },
    { key = "convoke",   name = "Convoke the Spirits", spellID = 391528, talentGated = true },
    { key = "lunarbeam", name = "Lunar Beam",          spellID = 204066, talentGated = true },
    -- spellID intentionally omitted — resolved by name at runtime (see
    -- ResolveDefSpellID). Pin the number here once /thugspell reports it.
    { key = "redmoon",   name = "Red Moon",                              talentGated = true },
}

-- Create the container once. Icons are created lazily (EnsureGCVIcons) so that
-- Guardian spells resolve correctly even if you logged in as another spec.
function ER:CreateGCV()
    if ER.gcvContainer then return end

    local f = CreateFrame("Frame", "ThugUI_GuardianCooldownViewer", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    ER.gcvContainer = f
    ER.gcvIcons = {}
    ER.gcvIconsByKey = {}

    local saved = ThugUI_Config.gcvPoint
    if saved then
        f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 300)
    end

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ThugUI_Config.gcvPoint = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    f:SetScale(ThugUI_Config.gcvScale or 1.0)

    ER:EnsureGCVIcons()
    ER:UpdateGCVVisibility()
end

-- Create any not-yet-created icons whose texture now resolves. Idempotent.
function ER:EnsureGCVIcons()
    if not ER.gcvContainer then return end
    ER.gcvIconsByKey = ER.gcvIconsByKey or {}

    for _, def in ipairs(ER.gcvSpellDefs) do
        if not ER.gcvIconsByKey[def.key] then
            local texture = (def.spellID and C_Spell.GetSpellTexture(def.spellID))
                or C_Spell.GetSpellTexture(def.name)
            if texture then
                local icon = CreateFrame("Frame", "ThugUI_GCV_" .. def.key, ER.gcvContainer)
                icon:SetSize(BCV_ICON_SIZE, BCV_ICON_SIZE)

                local bg = icon:CreateTexture(nil, "BACKGROUND")
                bg:SetPoint("TOPLEFT", -1, 1)
                bg:SetPoint("BOTTOMRIGHT", 1, -1)
                bg:SetColorTexture(0, 0, 0, 0.8)

                local tex = icon:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture(texture)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                icon.tex = tex

                icon.def = def
                icon:Hide()
                ER.gcvIconsByKey[def.key] = icon
                table.insert(ER.gcvIcons, icon)
            end
        end
    end
end

function ER:UpdateGCVCooldowns()
    if not ER.gcvContainer or not ER.gcvContainer:IsShown() then return end
    ER.gcvIconsByKey = ER.gcvIconsByKey or {}

    local visibleIndex = 0
    for _, def in ipairs(ER.gcvSpellDefs) do
        local icon = ER.gcvIconsByKey[def.key]
        if icon then
            -- Talent abilities only show when actually talented; baseline
            -- spells (Mangle, Thrash) are always available. A def with no
            -- hardcoded spellID resolves one by name — if nothing resolves,
            -- the player doesn't have the talent.
            local available
            if not def.talentGated then
                available = true
            else
                local spellID = ResolveDefSpellID(def)
                available = (spellID ~= nil) and IsSpellAvailable(spellID)
            end
            local show = available and IsSpellReady(def.name)

            if show then
                icon:Show()
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", ER.gcvContainer, "TOPLEFT",
                    visibleIndex * (BCV_ICON_SIZE + BCV_PADDING), 0)
                visibleIndex = visibleIndex + 1
            else
                icon:Hide()
            end
        end
    end

    local totalW = math.max(visibleIndex * (BCV_ICON_SIZE + BCV_PADDING) - BCV_PADDING, 1)
    ER.gcvContainer:SetSize(totalW, BCV_ICON_SIZE)
end

function ER:UpdateGCVVisibility(inCombat)
    if not ER.gcvContainer then return end

    if not ER:LegacyBarsActive() then
        ER.gcvContainer:Hide()
        return
    end

    if not ThugUI_Config.showGCV or not ER:IsGuardianSpec() then
        ER.gcvContainer:Hide()
        return
    end

    -- Make sure Guardian icons exist now that we're in Guardian spec.
    ER:EnsureGCVIcons()

    if ThugUI_Config.gcvShowOnlyInCombat then
        if inCombat == nil then inCombat = ER:IsInCombat() end
        if not inCombat then
            ER.gcvContainer:Hide()
            return
        end
    end

    ER.gcvContainer:Show()
    ER:UpdateGCVCooldowns()
end

function ER:UpdateGCVPosition()
    if not ThugUI_Config.anchorGCVToCursor then return end
    if not ER:IsGuardianSpec() then return end
    if not ER:IsInCombat() then return end

    local f = ER.gcvContainer
    if not f or not f:IsShown() then return end

    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local scale = f:GetScale()
    local scaledX = cursorX / uiScale / scale
    local scaledY = cursorY / uiScale / scale

    local corner = ThugUI_Config.gcvAnchorCorner or "TOPLEFT"
    local gap = 8 / scale
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

    f:ClearAllPoints()
    f:SetPoint(corner, UIParent, "BOTTOMLEFT", scaledX + ofsX, scaledY + ofsY)
end

-- Restore the bar to its saved (Edit Mode / dragged) position when it stops
-- following the cursor (combat ended).
function ER:ReleaseGCVAnchor()
    if not ER.gcvContainer then return end
    local saved = ThugUI_Config.gcvPoint
    ER.gcvContainer:ClearAllPoints()
    if saved then
        ER.gcvContainer:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        ER.gcvContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 300)
    end
end

function ER:UpdateECVVisibility(inCombat)
    if not ER.ecvContainer then return end

    if not ER:LegacyBarsActive() then
        ER.ecvContainer:Hide()
        return
    end

    -- This bar tracks Restoration spells, so it is hidden entirely outside
    -- Restoration spec (icons, cursor-follow, and all).
    if not ER:IsRestoSpec() then
        ER.ecvContainer:Hide()
        return
    end
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
    -- Belt and braces alongside RegisterUnitEvent: if these ever get
    -- re-registered with a plain RegisterEvent, every raid member's cast would
    -- otherwise retrigger the player's GCD sweep -- and the throttle below
    -- would then swallow the player's own cast whenever somebody else cast
    -- within the preceding 100ms.
    if unit and unit ~= "player" then return end

    if GetTime() - ER.lastGCDTime < 0.1 then return end

    ER.lastGCDTime = GetTime()

    local GCDInfo = C_Spell.GetSpellCooldown(GCD_SPELL_ID)

    if GCDInfo and GCDInfo.duration > 0 then
        ER:StartGCDAnimation(GCDInfo.startTime, GCDInfo.duration)
    end
end

function ER:CastEventHandler(self, event, unit)
    -- See GCDCastHandler: these read UnitCastingInfo("player") regardless of
    -- which unit the event was about, so anything but the player must be
    -- dropped here rather than acted on.
    if unit and unit ~= "player" then return end

    local startTime, endTime, infoValid = nil, nil, false

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        -- DELAYED is pushback: the cast now ends later than it did, so the
        -- times are re-read and the sweep re-seeded rather than left to drift.
        local cName, cRank, cTarget, cStartTime, cEndTime = UnitCastingInfo("player")
        startTime, endTime = cStartTime, cEndTime
        infoValid = true

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        -- CHANNEL_UPDATE is the channel equivalent: haste procs and talents
        -- that extend or shorten a channel land here.
        local chName, chRank, chTarget, chStartTime, chEndTime, isMoving = UnitChannelInfo("player")
        startTime, endTime = chStartTime, chEndTime
        infoValid = true

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED"
    then
        ER:StopCastAnimation()
        return
    end

    if infoValid then
        if not (startTime and endTime) then
            -- The cast ended between the event firing and this read, so there
            -- is nothing to animate; leaving the ring up would strand it.
            ER:StopCastAnimation()
            return
        end

        local duration = (endTime - startTime) / 1000
        if duration > 0.1 then
            ER:StartCastAnimation(startTime / 1000, duration)
        end
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

    -- BCV follows the cursor per-frame in combat (UpdateBCVPosition); when
    -- combat ends, snap it back to its saved position.
    if ThugUI_Config.anchorBCVToCursor and not inCombat then
        ER:ReleaseBCVAnchor()
    end

    -- GCV follows the cursor per-frame in combat (UpdateGCVPosition); when
    -- combat ends, snap it back to its saved position.
    if ThugUI_Config.anchorGCVToCursor and not inCombat then
        ER:ReleaseGCVAnchor()
    end

    -- Update ECV / BCV / GCV visibility (show-only-in-combat setting)
    ER:UpdateECVVisibility(inCombat)
    ER:UpdateBCVVisibility(inCombat)
    ER:UpdateGCVVisibility(inCombat)

    -- The resource ring rides the cursor rings' visibility rather than owning
    -- a second in-combat setting that could drift out of step with them.
    if ThugUI.ResourceRing then
        ThugUI.ResourceRing:Update()
    end
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

    -- Build the Balance Cooldown Viewer (second bar)
    ER:CreateBCV()

    -- Build the Guardian Cooldown Viewer
    ER:CreateGCV()

    -- Resource ring last: it sizes itself from ER.CastFrame, which only exists
    -- once the block above has run.
    if ThugUI.ResourceRing then
        ThugUI.ResourceRing:Initialize()
    end

    -- Same dependency: the pips space themselves off the cast ring's diameter.
    if ThugUI.ComboPips then
        ThugUI.ComboPips:Initialize()
    end

    TrackerFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function ER:OnInitialize()
    ER.TrackerFrame = TrackerFrame

    TrackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    TrackerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    TrackerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    TrackerFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    -- Re-evaluate which bar (Resto vs Balance) is shown when spec/talents change
    TrackerFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    TrackerFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    TrackerFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")

    TrackerFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            if ThugUI_CursorFrame then
                ER:SetupUI()
            end

        elseif event == "UNIT_SPELLCAST_SENT" then
            -- SENT is the GCD trigger and nothing else. It used to fall into
            -- the same branch as the cast events, so every cast event ran both
            -- handlers and the GCD sweep was being re-poked by STOPs.
            ER:GCDCastHandler(self, event, ...)

        elseif event:match("^UNIT_SPELLCAST_") then
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
            ER:UpdateBCVCooldowns()
            ER:UpdateGCVCooldowns()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "ACTIVE_TALENT_GROUP_CHANGED"
            or event == "TRAIT_CONFIG_UPDATED" then
            -- Spec/talent change: refresh all bars and their spec gating.
            ER:EnsureBCVIcons()
            ER:EnsureGCVIcons()
            ER:UpdateVisibility()
        end
    end)

    TrackerFrame:SetScript("OnUpdate", function(self, elapsed)
        ER:OnUpdate(elapsed)
    end)
    TrackerFrame:Show()
    ER:OnUpdate(0)
end

LoaderFrame:SetScript("OnEvent", function(self, event, addon)
    if ThugUI_Config and ThugUI_Config.debugMode then
        print("ThugUI: ADDON_LOADED fired for: " .. tostring(addon))
    end
    if event == "ADDON_LOADED" and addon == "ThugUI" then
        ThugUI_DebugLog = ThugUI_DebugLog or {}
        ER:OnInitialize()
        ER:InitializeSettings()
        -- Sync the runtime debug flag with the saved checkbox state
        DebugLog.enabled = ThugUI_Config.debugMode and true or false
        if ThugUI_Config.debugMode then
            print("ThugUI: Initializing Essential Rings...")
        end
        ER:CreateSettingsPanel()
        if ThugUI.FrameHider then
            ThugUI.FrameHider:ApplyAll()
        end
        -- The unit button is protected, so it waits on PLAYER_ENTERING_WORLD
        -- internally rather than spawning here.
        if ThugUI.TargetOfTarget then
            ThugUI.TargetOfTarget:Initialize()
        end
        if ThugUI_Config.debugMode then
            print("ThugUI: Initialization complete!")
        end
        self:UnregisterAllEvents()
    end
end)
LoaderFrame:RegisterEvent("ADDON_LOADED")
