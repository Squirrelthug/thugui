-- Load-order smoke test for ThugUI.
-- Stubs enough of the WoW API to execute every file at file scope in TOC order,
-- then drives the config window through building each page. Catches nil-index
-- errors, typos in function names and bad load order -- not behaviour.

local addonPath = ...
assert(addonPath, "usage: lua loadtest.lua <addon folder>")

-- ---------------------------------------------------------------- frame stub
local frameMT = {}
frameMT.__index = function(tbl, key)
    -- Only Capitalised keys are synthesised as methods. A real frame returns nil
    -- for an unset plain field, and code like `f.navButtons or {}` depends on
    -- that -- synthesising everything makes such fallbacks silently unreachable.
    if type(key) ~= "string" or not key:match("^%u") then return nil end

    -- Every unknown method is a no-op that returns another frame, so long
    -- chains like f:CreateTexture():SetPoint() work without enumerating the API.
    local fn = function(...)
        local a, a1, a2, a3, a4, a5 = ...
        -- Anchors are recorded, not discarded: the collapse tests read back
        -- where an icon actually landed.
        if key == "SetPoint" and type(a) == "table" then
            a.__point = { a1, a2, a3, a4, a5 }
            return
        end
        if key == "ClearAllPoints" and type(a) == "table" then
            a.__point = nil
            return
        end
        -- Recorded so the resource ring's arc maths can be asserted on.
        if key == "SetCooldown" and type(a) == "table" then
            a.__cooldown = { a1, a2, a3 }
            return
        end
        -- Modelled rather than swallowed, so a test can tell "the sweep was
        -- cleared" apart from "the sweep was left alone" -- which is exactly
        -- the distinction the pooled-icon staleness bug turned on.
        if key == "Clear" and type(a) == "table" then
            a.__cooldown = nil
            return
        end
        -- Shown-state is modelled, not stubbed away: several code paths early-
        -- return on IsShown, so a stub that always says false silently skips
        -- the very logic under test.
        -- Handlers are stored so tests can fire events and OnUpdate ticks
        -- directly, which is the only way to exercise the combat transitions.
        if type(a) == "table" then
            if key == "SetScript" then
                a.__scripts = a.__scripts or {}
                a.__scripts[a1] = a2
                return
            end
            if key == "GetScript" then
                return a.__scripts and a.__scripts[a1]
            end
        end
        if type(a) == "table" then
            if key == "Show" then a.__shown = true return end
            if key == "Hide" then a.__shown = false return end
            if key == "SetShown" then a.__shown = a1 and true or false return end
            if key == "IsShown" then return a.__shown == true end
            -- Alpha and vertex colour are recorded because that is the whole
            -- observable state of a combo pip: lit or dim, and what colour.
            if key == "SetAlpha" then a.__alpha = a1 return end
            if key == "GetAlpha" then return a.__alpha == nil and 1 or a.__alpha end
            if key == "SetVertexColor" then a.__color = { a1, a2, a3 } return end
        end
        if key:match("^Get") then
            if key == "GetWidth" or key == "GetHeight" or key == "GetFrameLevel" then
                return 100
            end
            if key == "GetScale" or key == "GetEffectiveScale" then return 1 end
            -- Roughly life-sized, so panel height maths means something. A
            -- flat 100 per line made every wrapped note absurdly tall and any
            -- layout-fits check meaningless.
            if key == "GetStringHeight" then return 14 end
            if key == "GetStringWidth" then return 60 end
            if key == "GetPoint" then return "TOPLEFT", nil, "TOPLEFT", 0, 0 end
            if key == "GetChildren" or key == "GetRegions" then return end
            if key == "GetText" then return "" end
            if key == "GetObjectType" then return "Frame" end
            if key == "GetCenter" then return 0, 0 end
        end
        if key == "IsMouseOver" or key == "GetChecked" then return false end
        return setmetatable({}, frameMT)
    end
    rawset(tbl, key, fn)
    return fn
end

local function NewFrame()
    return setmetatable({}, frameMT)
end

local created = {}
function CreateFrame(frameType, name, parent, template)
    local f = NewFrame()
    if name then _G[name] = f end
    table.insert(created, { type = frameType, name = name, template = template })
    return f
end

-- ---------------------------------------------------------------- API stubs
UIParent = NewFrame()
GameTooltip = NewFrame()
ColorPickerFrame = NewFrame()
SettingsPanel = NewFrame()
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
STANDARD_TEXT_FONT = "font"

-- WoW runs Lua 5.1, which has a global unpack; 5.2+ moved it to table.unpack.
unpack = unpack or table.unpack
function tinsert(t, v) table.insert(t, v) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
-- Addon chat output goes nowhere, but the harness still needs a real print.
local say = print
function print() end
function PlaySound() end
function HideUIPanel() end
_G.__inCombat = false
function InCombatLockdown() return _G.__inCombat end
function UnitAffectingCombat() return _G.__inCombat end
function UnitClass() return "Druid", "DRUID" end
function GetCursorPosition() return 500, 500 end
function GetSpecialization() return 4 end
function GetNumSpecializations() return 4 end
function GetSpecializationInfo(i) return 100 + i, "Spec" .. i, "", 12345, "HEALER", 4 end
function GetSpecializationInfoByID(id) return id, "Spec" .. id end
function IsPlayerSpell() return true end
function IsSpellKnownOrOverridesKnown() return true end
function RegisterStateDriver() end
function GetTime() return 1000 end
date = os.date  -- WoW provides this as a global

-- 12.x secret values. Anything carrying __secret stands in for a field the
-- client will not let addon code read.
function issecretvalue(v) return type(v) == "table" and v.__secret == true end

_G.__overlayed = {}
C_SpellActivationOverlay = {
    IsSpellOverlayed = function(spellID) return _G.__overlayed[spellID] == true end,
}
local SECRET = { __secret = true }
_G.__SECRET = SECRET

-- Resource ring. __powerToken is what UnitPowerType reports (it already
-- follows shapeshift form in the real game); __form drives the override path.
_G.__powerToken = "MANA"
_G.__power, _G.__powerMax = 50, 100
_G.__form = 0
-- The numeric power type has to agree with the token, because the combo pips
-- decide whether a druid is in cat form by asking whether the PRIMARY power is
-- energy -- which a stub returning a constant 0 would answer wrongly.
local POWER_IDS = { MANA = 0, RAGE = 1, ENERGY = 3, LUNAR_POWER = 8 }
function UnitPowerType() return POWER_IDS[_G.__powerToken] or 0, _G.__powerToken end

-- The class's secondary resource is tracked separately from the primary one:
-- the pips and the resource ring read different power types at the same time,
-- and a single value cannot model both.
_G.__classPower, _G.__classPowerMax = 0, 5
local function IsClassPower(powerType)
    if powerType == nil then return false end
    for _, name in ipairs({ "ComboPoints", "HolyPower", "SoulShards", "Chi",
                            "ArcaneCharges", "Essence" }) do
        if Enum.PowerType[name] == powerType then return true end
    end
    return false
end
function UnitPower(_, powerType)
    if IsClassPower(powerType) then return _G.__classPower end
    return _G.__power
end
function UnitPowerMax(_, powerType)
    if IsClassPower(powerType) then return _G.__classPowerMax end
    return _G.__powerMax
end
function GetShapeshiftFormID() return _G.__form end
MOONKIN_FORM = 31
PowerBarColor = {
    COMBO_POINTS = { r = 1, g = 0.96, b = 0.41 },
    MANA = { r = 0, g = 0, b = 1 },
    RAGE = { r = 1, g = 0, b = 0 },
    ENERGY = { r = 1, g = 1, b = 0 },
    LUNAR_POWER = { r = 0.3, g = 0.52, b = 0.9 },
}
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 } }
function hooksecurefunc() end
function GetBuildInfo() return "12.0.7", "12345", "date", 120007 end
function SetPortraitTexture() end
function IsResting() return false end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetText() end
function CloseDropDownMenus() end
function SearchBoxTemplate_OnTextChanged() end
function InterfaceOptions_AddCategory() end

Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { ID = name }, NewFrame()
    end,
    RegisterCanvasLayoutSubcategory = function() return {} end,
    RegisterAddOnCategory = function() end,
}

Enum = {
    CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3 },
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    SpellBookItemType = { None = 0, Spell = 1 },
    -- Values match the live client's. Only distinctness matters to the harness,
    -- but a stub that disagrees with the game is a trap for whoever reads it
    -- next, and the combo pips resolve these BY NAME anyway.
    PowerType = {
        Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4, SoulShards = 7,
        LunarPower = 8, HolyPower = 9, Chi = 12, ArcaneCharges = 16, Essence = 19,
    },
}

_G.__unknownNames = {}

C_Spell = {
    -- Models the asymmetry the addon depends on: by ID this resolves for any
    -- spell in the game, but by NAME only for one the player actually has.
    -- __unknownNames marks names that should not resolve, standing in for a
    -- spell that is not talented in the current spec.
    GetSpellInfo = function(q)
        local id = tonumber(q)
        if id then return { spellID = id, name = "Spell " .. id, iconID = 999 } end
        if _G.__unknownNames[q] then return nil end
        local named = tostring(q):match("^Spell (%d+)$")
        if named then return { spellID = tonumber(named), name = q, iconID = 999 } end
        return nil
    end,
    GetSpellTexture = function() return 999 end,
    -- Cooldown state is per-spell and settable by the tests. The defaults
    -- mirror a ready spell. startTime/duration are deliberately given
    -- nonsense values: in 12.x they are secret, and nothing in the addon is
    -- allowed to derive readiness from them, so a test that starts passing
    -- because of them is a test that has caught a real regression.
    GetSpellCooldown = function(q)
        -- Keyed by ID, but the addon queries by name, so map back.
        local id = tonumber(q) or tonumber(tostring(q):match("^Spell (%d+)$") or "")
        local state = _G.__cooldownState and _G.__cooldownState[id]
        return {
            isActive = state and state.isActive or false,
            isOnGCD = state and state.isOnGCD or false,
            startTime = -1, duration = -1, modRate = 1,
        }
    end,
    GetSpellCharges = function() return nil end,
}
_G.__cooldownState = {}
-- Auras present on the player, keyed by spell ID.
_G.__auras = {}
C_UnitAuras = {
    GetUnitAuraBySpellID = function(unit, spellID)
        if unit ~= "player" then return nil end
        return _G.__auras[spellID]
    end,
    GetPlayerAuraBySpellID = function(spellID) return _G.__auras[spellID] end,
    -- The list walk the by-ID lookups fall back to. Ordered by spell ID so a
    -- test can rely on the sequence; the real client's order is arbitrary,
    -- which is exactly why the code matches on fields rather than position.
    GetAuraDataByIndex = function(unit, index, filter)
        if unit ~= "player" or filter ~= "HELPFUL" then return nil end
        local ids = {}
        for id in pairs(_G.__auras) do ids[#ids + 1] = id end
        table.sort(ids)
        local id = ids[index]
        return id and _G.__auras[id] or nil
    end,
}

-- Entry 3 models an entry defined only by its linked buffs.
--
-- Entries 4 and 5 model Roll the Bones as it really appears on an Outlaw
-- rogue: the SAME spellID listed twice, once under Essential with no linked
-- spells and once under TrackedBar carrying all four outcome buffs. Whichever
-- of the two wins the cache decides whether the buffs are reachable at all.
_G.__cooldownEntries = {
    [1] = { cooldownID = 1, spellID = 1001 },
    [2] = { cooldownID = 2, spellID = 1002 },
    [3] = { cooldownID = 3, spellID = nil, linkedSpellIDs = { 9001, 9002, 9003 } },
    [4] = { cooldownID = 4, spellID = 5000, linkedSpellIDs = {} },
    [5] = { cooldownID = 5, spellID = 5000, linkedSpellIDs = { 5101, 5102, 5103, 5104 } },
}
_G.__categorySets = {
    Essential   = { 1, 2, 4 },
    Utility     = {},
    TrackedBuff = { 3 },
    TrackedBar  = { 5 },
}
C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        for name, value in pairs(Enum.CooldownViewerCategory) do
            if value == category then return _G.__categorySets[name] or {} end
        end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(id) return _G.__cooldownEntries[id] end,
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 3 } end,
    GetSpellBookItemInfo = function(slot) return { spellID = 2000 + slot, isPassive = false, isOffSpec = false } end,
    IsSpellKnown = function() return true end,
}
C_Timer = { After = function() end, NewTicker = function() return NewFrame() end }

-- ---------------------------------------------------------------- run
local function LoadTOC(path)
    local toc = assert(io.open(path .. "/ThugUI.toc"), "no TOC")
    local files = {}
    for rawLine in toc:lines() do
        -- 5.5 makes the generic-for variable const, so trim into a new local.
        local line = rawLine:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") and line:match("%.lua$") then
            table.insert(files, (line:gsub("\\", "/")))
        end
    end
    toc:close()
    return files
end

-- Turn a recorded x-offset back into the grid column an icon was drawn in,
-- inverting the placement maths in CV:ApplyLayout.
local function DisplayCols(CV, Data, row, placedCols)
    local profile = Data.GetActiveProfile()
    local cellW = (profile.iconSize or 32) + (profile.padding or 4)
    local pad = profile.padding or 4

    local out = {}
    for i, col in ipairs(placedCols) do
        local icon = CV.icons[Data.CellKey(row, col)]
        assert(icon, ("no icon at row %d col %d"):format(row, col))
        assert(icon.__point, ("icon at row %d col %d was never positioned"):format(row, col))
        out[i] = math.floor((icon.__point[4] - pad / 2) / cellW + 0.5) + 1
    end
    return out
end

--- Same idea on the vertical axis: recover the grid row an icon was drawn in.
local function DisplayRows(CV, Data, col, placedRows)
    local profile = Data.GetActiveProfile()
    local cellH = (profile.iconSize or 32) + (profile.padding or 4)
    local pad = profile.padding or 4

    local out = {}
    for i, row in ipairs(placedRows) do
        local icon = CV.icons[Data.CellKey(row, col)]
        assert(icon, ("no icon at row %d col %d"):format(row, col))
        assert(icon.__point, ("icon at row %d col %d was never positioned"):format(row, col))
        -- y offsets are negative going down, hence the sign flip.
        out[i] = math.floor((-icon.__point[5] - pad / 2) / cellH + 0.5) + 1
    end
    return out
end

local function assertSame(got, want, message)
    assert(#got == #want, ("%s (length %d, wanted %d)"):format(message, #got, #want))
    for i = 1, #want do
        if got[i] ~= want[i] then
            error(("%s (position %d: got %s, wanted %s)")
                :format(message, i, tostring(got[i]), tostring(want[i])), 2)
        end
    end
end

local failures = 0
for _, file in ipairs(LoadTOC(addonPath)) do
    local chunk, err = loadfile(addonPath .. "/" .. file)
    if not chunk then
        say(("LOAD FAIL  %s\n           %s"):format(file, err))
        failures = failures + 1
    else
        local ok, runErr = pcall(chunk, "ThugUI", {})
        if not ok then
            say(("RUN FAIL   %s\n           %s"):format(file, runErr))
            failures = failures + 1
        else
            say("ok         " .. file)
        end
    end
end

-- Drive the window: build and refresh every registered page.
if failures == 0 and ThugUI and ThugUI.Window then
    say("\n-- pages --")
    local ok, err = pcall(function() ThugUI.Window:CreateWindow() end)
    if not ok then
        say("CreateWindow FAIL: " .. tostring(err))
        failures = failures + 1
    end

    for _, def in ipairs(ThugUI.Window.pages) do
        local pageOK, pageErr = pcall(function() ThugUI.Window:SelectPage(def.id) end)
        if pageOK then
            say("ok         page " .. def.id)
        else
            say(("PAGE FAIL  %s\n           %s"):format(def.id, tostring(pageErr)))
            failures = failures + 1
        end
    end

    -- Regression: the Cooldown Viewer page laid ~670px of controls into a
    -- ~614px frame and the bottom of the column fell off the window. Pages
    -- that opt out of scrolling have to fit what they draw.
    local limit = ThugUI.Window.CONTENT_HEIGHT
    for _, def in ipairs(ThugUI.Window.pages) do
        if def.scroll == false then
            local panels = {}
            local page = def.id == "cooldownviewer" and ThugUI.CooldownViewer.Page
            if page and page.panels then panels = page.panels end

            local worst, worstBottom = nil, 0
            for i, panel in ipairs(panels) do
                local bottom = panel:GetHeight()
                if bottom > worstBottom then worst, worstBottom = i, bottom end
            end

            if worstBottom > limit then
                say(("LAYOUT FAIL %s: panel %d reaches %dpx in a %dpx frame")
                    :format(def.id, worst, worstBottom, limit))
                failures = failures + 1
            else
                say(("ok         page %s fits (%dpx of %dpx)")
                    :format(def.id, worstBottom, limit))
            end
        end
    end
end

-- Exercise the cooldown viewer engine, which PLAYER_LOGIN would normally start.
if failures == 0 and ThugUI.CooldownViewer then
    say("\n-- engine --")
    local CV, Data = ThugUI.CooldownViewer, ThugUI.CooldownViewer.Data

    local steps = {
        { "initialize", function() CV:Initialize() end },
        { "migration is tracked per spec", function()
            assert(ThugUI_Config.cv and ThugUI_Config.cv.migratedSpecs,
                "per-spec migration table not created")
        end },

        -- Regression: the Restoration bar is stored as spell NAMES, which only
        -- resolve while in that spec. A one-shot pass run as another spec
        -- produced an empty bar and never retried.
        { "restoration imports even when its names do not resolve", function()
            local RESTO = Data.DRUID_SPEC_IDS.restoration
            -- Simulate being in another spec: none of the Resto names resolve.
            for _, name in ipairs(ThugUI.EssentialRings.ecvSpellNames or {}) do
                _G.__unknownNames[name] = true
            end

            ThugUI_Config.cv.migratedSpecs[RESTO] = nil
            wipe(Data.GetProfile(RESTO).placements)
            assert(Data.MigrateSpec(RESTO, true), "restoration import returned false")

            local placed = Data.GetPlacements(Data.GetProfile(RESTO))
            assert(#placed > 0, "restoration imported an empty bar")

            for _, name in ipairs(ThugUI.EssentialRings.ecvSpellNames or {}) do
                _G.__unknownNames[name] = nil
            end
        end },

        { "a spec with no legacy bar imports nothing", function()
            assert(not Data.MigrateSpec(Data.DRUID_SPEC_IDS.feral, true),
                "feral claimed to import a bar that never existed")
        end },

        { "no junk profile under specID 0", function()
            Data.GetProfile(0)
            Data.GetProfile(nil)
            assert(not ThugUI_Config.cv.profiles[0],
                "a profile was stored under specID 0")
        end },
        { "place + rebuild", function()
            local profile = Data.GetActiveProfile()
            Data.SetPlacement(profile, 3, 4, 12345, "cooldown")
            Data.SetPlacement(profile, 3, 5, 23456, "aura")
            CV:Rebuild()
            assert(CV.icons[Data.CellKey(3, 4)], "icon not built for placed cell")
        end },
        { "move placement", function()
            local profile = Data.GetActiveProfile()
            Data.MovePlacement(profile, 3, 4, 7, 7)
            assert(Data.GetPlacement(profile, 7, 7), "move lost the placement")
            assert(not Data.GetPlacement(profile, 3, 4), "move left the source occupied")
        end },
        { "anchor geometry", function()
            local profile = Data.GetActiveProfile()
            profile.anchorCol, profile.anchorRow = 5, 5
            profile.enabled, profile.onlyInCombat = true, false
            CV:UpdateVisibility()
            CV:UpdateCursorPosition()
        end },
        { "preview toggle", function()
            CV:SetPreview(true, Data.GetActiveSpecID())
            CV:UpdateState()
            CV:SetPreview(false)
        end },
        { "legacy toggle", function()
            SlashCmdList["THUGCV"]("legacy")
            assert(ThugUI_Config.cvUseLegacy, "legacy flag not set")
            SlashCmdList["THUGCV"]("legacy")
            assert(not ThugUI_Config.cvUseLegacy, "legacy flag not cleared")
        end },

        -- Regression: an unknown subcommand fell through to opening the config
        -- window, so a typo was indistinguishable from the command working.
        { "an unknown subcommand says so instead of opening the window", function()
            local opened = false
            local realToggle = ThugUI.ToggleOptions
            ThugUI.ToggleOptions = function() opened = true end

            SlashCmdList["THUGCV"]("diag")
            assert(not opened, "an unknown subcommand silently opened the options window")

            -- Bare /thugcv is still the way to open it.
            SlashCmdList["THUGCV"]("")
            assert(opened, "bare /thugcv stopped opening the options window")

            ThugUI.ToggleOptions = realToggle
        end },
        { "spell catalogue", function()
            for _, source in ipairs(Data.SOURCES) do
                local list = Data.BuildSpellList(source.value, nil)
                assert(type(list) == "table", "no list for source " .. source.value)
            end
        end },

        -- An entry standing for a SET of buffs offered only the set, so a
        -- player could track "Roll the Bones" but not "only when I roll
        -- Jackpot". The outcomes come from linkedSpellIDs, never from a list
        -- of IDs written down here -- they were six on an older build and are
        -- four now, so anything hardcoded rots without anyone noticing.
        { "buff outcomes are offered individually, not just the set", function()
            local list = Data.BuildSpellList("buffs", nil)

            local byID = {}
            for _, entry in ipairs(list) do byID[entry.spellID] = true end

            assert(byID[5000], "the set entry itself vanished from the picker")
            local info = Data.GetCooldownInfoForSpell(5000)
            assert(info and #info.linkedSpellIDs > 0, "setup: no linked buffs to expand")
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                assert(byID[linkedID],
                    ("linked buff %d was not offered on its own"):format(linkedID))
            end

            -- Cooldown sources must NOT expand: there a linked spell is the
            -- same button under another ID and would just double the list.
            local essentials = Data.BuildSpellList("essential", nil)
            local essentialIDs = {}
            for _, entry in ipairs(essentials) do essentialIDs[entry.spellID] = true end
            local cdInfo = Data.GetCooldownInfoForSpell(9101)
            if cdInfo and cdInfo.linkedSpellIDs and #cdInfo.linkedSpellIDs > 0 then
                assert(not essentialIDs[cdInfo.linkedSpellIDs[1]],
                    "a cooldown entry's linked spell was offered separately")
            end
        end },
        { "grid page refresh after edits", function()
            ThugUI.Window:SelectPage("cooldownviewer")
        end },

        -- Diagnostics are always on, so they must be safe to call from
        -- anywhere and must never grow without bound.
        { "diagnostics record without being switched on", function()
            local D = ThugUI.Diagnostics
            assert(D, "diagnostics module missing")
            assert(ThugUI_DebugLog and ThugUI_DebugLog.events,
                "nothing was recorded without a command being run")
            assert(#ThugUI_DebugLog.events > 0, "no events captured")
        end },

        { "the event log is capped", function()
            local D = ThugUI.Diagnostics
            for i = 1, 500 do D:Log("TEST", "entry %d", i) end
            assert(#ThugUI_DebugLog.events <= 300,
                ("event log grew to %d, unbounded"):format(#ThugUI_DebugLog.events))
            -- The tail is what explains a failure, so it must be the tail
            -- that survives.
            assert(ThugUI_DebugLog.events[#ThugUI_DebugLog.events]:find("entry 500"),
                "the newest entry was dropped instead of the oldest")
        end },

        { "LogOnce really only logs once", function()
            local D = ThugUI.Diagnostics
            for _ = 1, 20 do D:LogOnce("test-key", "TEST", "repeated condition") end

            -- Counted rather than measured by log length: the cap means the
            -- log can be full, and then adding entries does not grow it.
            local count = 0
            for _, line in ipairs(ThugUI_DebugLog.events) do
                if line:find("repeated condition", 1, true) then count = count + 1 end
            end
            assert(count == 1, ("a once-only condition appeared %d times"):format(count))
        end },

        { "a snapshot records linked-spell counts", function()
            local D = ThugUI.Diagnostics
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            Data.SetPlacement(profile, 1, 1, 5000, "aura")
            Data.InvalidateCooldownInfoCache()
            CV:Rebuild()

            D:CaptureState()
            local state = ThugUI_DebugLog.state
            assert(state and state.profiles, "no state captured")

            local specID = Data.GetActiveSpecID()
            local entry = state.profiles[specID]
            assert(entry and entry.icons and #entry.icons > 0, "no icons recorded")
            -- This is the field that proves the linked-buff lookup ran, which
            -- no version string can tell you from the outside.
            assert(entry.icons[1]:find("linked=4"),
                "snapshot did not record the resolved linked-spell count: " .. entry.icons[1])
        end },

        -- Regression: the snapshot was only taken at PLAYER_LOGOUT, and by then
        -- GetSpecializationInfo returns 0. Every snapshot ever written was for
        -- an empty "Spec 0" profile, so the linked-spell count -- the whole
        -- point of the thing -- had never once been recorded.
        { "a logout-time capture cannot destroy a good snapshot", function()
            local D = ThugUI.Diagnostics
            local specID = Data.GetActiveSpecID()

            -- A real capture first, exactly as leaving combat would take it.
            D:CaptureState()
            local good = ThugUI_DebugLog.state.profiles[specID]
            assert(good and #good.icons > 0, "setup: no real snapshot to protect")

            -- Now capture the way PLAYER_LOGOUT does, with the spec gone.
            local realInfo = GetSpecializationInfo
            GetSpecializationInfo = function() return 0 end
            D:CaptureState()
            GetSpecializationInfo = realInfo

            assert(not ThugUI_DebugLog.state.profiles[0],
                "a spec-0 capture wrote a junk profile over the snapshot")
            assert(ThugUI_DebugLog.state.profiles[specID],
                "the good snapshot was destroyed by the logout capture")
            assert(#ThugUI_DebugLog.state.profiles[specID].icons > 0,
                "the surviving snapshot lost its icons")
        end },

        -- Collapse: rows pack independently, from the row's own outermost
        -- placed column, treating the row as one run.
        { "collapse packs left from the row's own origin", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "rows", "left"
            -- Row 2, columns 3/4/5 -- deliberately not starting at column 1.
            Data.SetPlacement(profile, 2, 3, 111, "cooldown")
            Data.SetPlacement(profile, 2, 4, 222, "cooldown")
            Data.SetPlacement(profile, 2, 5, 333, "cooldown")
            CV:Rebuild()

            local cols = DisplayCols(CV, Data, 2, { 3, 4, 5 })
            assertSame(cols, { 3, 4, 5 }, "full-strength row moved off its resting cells")

            -- Middle one on cooldown: the tail slides in, the row's start holds.
            CV.icons[Data.CellKey(2, 4)].wanted = false
            CV.icons[Data.CellKey(2, 4)]:Hide()
            CV:ApplyLayout()
            cols = DisplayCols(CV, Data, 2, { 3, 5 })
            assertSame(cols, { 3, 4 }, "row did not close up toward its origin")
        end },

        { "collapse packs right when told to", function()
            local profile = Data.GetActiveProfile()
            profile.collapseDirection = "right"
            for _, icon in pairs(CV.icons) do icon.wanted = true end
            CV:ApplyLayout()
            local cols = DisplayCols(CV, Data, 2, { 3, 4, 5 })
            assertSame(cols, { 3, 4, 5 }, "full-strength row moved when packing right")

            CV.icons[Data.CellKey(2, 4)].wanted = false
            CV:ApplyLayout()
            cols = DisplayCols(CV, Data, 2, { 3, 5 })
            assertSame(cols, { 4, 5 }, "row did not close up toward its right edge")
        end },

        { "collapse closes a gap between clusters", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "rows", "left"
            Data.SetPlacement(profile, 1, 1, 111, "cooldown")
            Data.SetPlacement(profile, 1, 2, 222, "cooldown")
            Data.SetPlacement(profile, 1, 8, 333, "cooldown")
            Data.SetPlacement(profile, 1, 9, 444, "cooldown")
            CV:Rebuild()
            for _, icon in pairs(CV.icons) do icon.wanted = true end
            CV.icons[Data.CellKey(1, 2)].wanted = false
            CV:ApplyLayout()
            -- Whole row is one run, so the far cluster slides in to meet it.
            assertSame(DisplayCols(CV, Data, 1, { 1, 8, 9 }), { 1, 2, 3 },
                "clusters did not merge into one run")
        end },

        { "collapse none leaves the hole", function()
            local profile = Data.GetActiveProfile()
            profile.collapse = "none"
            CV:ApplyLayout()
            assertSame(DisplayCols(CV, Data, 1, { 1, 8, 9 }), { 1, 8, 9 },
                "icons moved with collapse off")
        end },

        -- Columns mode, stage 1: icons slide along their own column and never
        -- change column while anything in it is still live.
        { "columns pack vertically within a column", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "columns", "up"
            profile.anchorCol, profile.anchorRow = 0, 0
            -- One column of three, starting at row 3 rather than row 1.
            Data.SetPlacement(profile, 3, 2, 111, "cooldown")
            Data.SetPlacement(profile, 4, 2, 222, "cooldown")
            Data.SetPlacement(profile, 5, 2, 333, "cooldown")
            CV:Rebuild()

            assertSame(DisplayRows(CV, Data, 2, { 3, 4, 5 }), { 3, 4, 5 },
                "full-strength column moved off its resting cells")

            CV.icons[Data.CellKey(4, 2)].wanted = false
            CV:ApplyLayout()
            assertSame(DisplayRows(CV, Data, 2, { 3, 5 }), { 3, 4 },
                "column did not close up toward its origin")
        end },

        { "columns can pack downward", function()
            local profile = Data.GetActiveProfile()
            profile.collapseDirection = "down"
            for _, icon in pairs(CV.icons) do icon.wanted = true end
            CV:ApplyLayout()
            assertSame(DisplayRows(CV, Data, 2, { 3, 4, 5 }), { 3, 4, 5 },
                "full-strength column moved when packing down")

            CV.icons[Data.CellKey(4, 2)].wanted = false
            CV:ApplyLayout()
            assertSame(DisplayRows(CV, Data, 2, { 3, 5 }), { 4, 5 },
                "column did not close up toward its bottom")
        end },

        -- Stage 2: an entirely spent column vacates and the rest close in.
        { "an emptied column lets the others slide in", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "columns", "up"
            profile.anchorCol, profile.anchorRow = 0, 0
            -- Three columns at 2, 3 and 4, one icon each.
            Data.SetPlacement(profile, 1, 2, 111, "cooldown")
            Data.SetPlacement(profile, 1, 3, 222, "cooldown")
            Data.SetPlacement(profile, 1, 4, 333, "cooldown")
            CV:Rebuild()
            assertSame(DisplayCols(CV, Data, 1, { 2, 3, 4 }), { 2, 3, 4 },
                "full-strength columns moved")

            -- Empty the middle column entirely.
            CV.icons[Data.CellKey(1, 3)].wanted = false
            CV:ApplyLayout()
            assertSame(DisplayCols(CV, Data, 1, { 2, 4 }), { 2, 3 },
                "columns did not close the gap left by an empty column")
        end },

        { "a column with anything live does not vacate", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "columns", "up"
            Data.SetPlacement(profile, 1, 2, 111, "cooldown")
            Data.SetPlacement(profile, 1, 3, 222, "cooldown")
            Data.SetPlacement(profile, 2, 3, 444, "cooldown")
            Data.SetPlacement(profile, 1, 4, 333, "cooldown")
            CV:Rebuild()

            -- Column 3 loses one of its two, so it must hold its place.
            CV.icons[Data.CellKey(1, 3)].wanted = false
            CV:ApplyLayout()
            assertSame(DisplayCols(CV, Data, 1, { 2, 4 }), { 2, 4 },
                "a column that still had a live icon was vacated")
            assertSame(DisplayCols(CV, Data, 2, { 3 }), { 3 },
                "surviving icon left its column")
        end },

        -- Rows are now symmetric with columns: an emptied row vacates too.
        { "an emptied row lets the others close up", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "rows", "left"
            profile.anchorCol, profile.anchorRow = 0, 0
            -- Three rows at 2, 3 and 4, one icon each.
            Data.SetPlacement(profile, 2, 1, 111, "cooldown")
            Data.SetPlacement(profile, 3, 1, 222, "cooldown")
            Data.SetPlacement(profile, 4, 1, 333, "cooldown")
            CV:Rebuild()
            assertSame(DisplayRows(CV, Data, 1, { 2, 3, 4 }), { 2, 3, 4 },
                "full-strength rows moved")

            CV.icons[Data.CellKey(3, 1)].wanted = false
            CV:ApplyLayout()
            assertSame(DisplayRows(CV, Data, 1, { 2, 4 }), { 2, 3 },
                "rows did not close the gap left by an empty row")
        end },

        { "a row with anything live does not vacate", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "rows", "left"
            Data.SetPlacement(profile, 2, 1, 111, "cooldown")
            Data.SetPlacement(profile, 3, 1, 222, "cooldown")
            Data.SetPlacement(profile, 3, 2, 444, "cooldown")
            Data.SetPlacement(profile, 4, 1, 333, "cooldown")
            CV:Rebuild()

            CV.icons[Data.CellKey(3, 1)].wanted = false
            CV:ApplyLayout()
            assertSame(DisplayRows(CV, Data, 1, { 2, 4 }), { 2, 4 },
                "a row that still had a live icon was vacated")
        end },

        -- "both": a row pass then a column pass, closing on each axis.
        { "both closes an empty row and an empty column", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "both", "topleft"
            -- A 3x3 block starting at row 2, col 2.
            for row = 2, 4 do
                for col = 2, 4 do
                    Data.SetPlacement(profile, row, col, 100 + row * 10 + col, "cooldown")
                end
            end
            CV:Rebuild()
            assertSame(DisplayRows(CV, Data, 2, { 2, 3, 4 }), { 2, 3, 4 },
                "full-strength block moved vertically")
            assertSame(DisplayCols(CV, Data, 2, { 2, 3, 4 }), { 2, 3, 4 },
                "full-strength block moved horizontally")

            -- Spend the whole middle row and the whole middle column.
            for col = 2, 4 do CV.icons[Data.CellKey(3, col)].wanted = false end
            for row = 2, 4 do CV.icons[Data.CellKey(row, 3)].wanted = false end
            CV:ApplyLayout()

            -- What survives is the four corners, which must close into a 2x2
            -- block flush at the original top-left.
            local corners = {
                { 2, 2, 2, 2 }, { 2, 4, 2, 3 },
                { 4, 2, 3, 2 }, { 4, 4, 3, 3 },
            }
            for _, c in ipairs(corners) do
                local icon = CV.icons[Data.CellKey(c[1], c[2])]
                local cellW = (profile.iconSize or 32) + (profile.padding or 4)
                local pad = profile.padding or 4
                local gotRow = math.floor((-icon.__point[5] - pad / 2) / cellW + 0.5) + 1
                local gotCol = math.floor((icon.__point[4] - pad / 2) / cellW + 0.5) + 1
                assert(gotRow == c[3] and gotCol == c[4],
                    ("corner %d,%d landed at %d,%d, wanted %d,%d")
                        :format(c[1], c[2], gotRow, gotCol, c[3], c[4]))
            end
        end },

        { "both packs toward the chosen corner", function()
            local profile = Data.GetActiveProfile()
            profile.collapseDirection = "bottomright"
            for _, icon in pairs(CV.icons) do icon.wanted = true end
            CV:ApplyLayout()
            -- At full strength the block must still sit exactly where drawn,
            -- whichever corner it packs toward.
            assertSame(DisplayRows(CV, Data, 2, { 2, 3, 4 }), { 2, 3, 4 },
                "full-strength block moved when packing bottom-right")
            assertSame(DisplayCols(CV, Data, 2, { 2, 3, 4 }), { 2, 3, 4 },
                "full-strength block moved when packing bottom-right")

            for col = 2, 4 do CV.icons[Data.CellKey(3, col)].wanted = false end
            CV:ApplyLayout()
            -- Rows 2 and 4 survive; packing down means they end at rows 3 and 4.
            assertSame(DisplayRows(CV, Data, 2, { 2, 4 }), { 3, 4 },
                "rows did not close toward the bottom")
        end },

        -- Roll the Bones: one tracked entry standing for a set of possible
        -- buffs, with no aura of its own.
        { "an entry with no base spell still reaches the picker", function()
            Data.InvalidateCooldownInfoCache()
            local found = false
            for _, entry in ipairs(Data.BuildSpellList("buffs", nil)) do
                if entry.spellID == 9001 then found = true end
            end
            assert(found, "an entry defined only by linkedSpellIDs was dropped from the picker")
        end },

        -- Regression: Roll the Bones is listed under Essential with no linked
        -- spells AND under TrackedBar with its four outcomes. Reading only
        -- TrackedBuff missed the second entry entirely, and keeping whichever
        -- was scanned first let the empty one win.
        { "tracked buffs source includes tracked bars", function()
            Data.InvalidateCooldownInfoCache()
            local found = false
            for _, entry in ipairs(Data.BuildSpellList("buffs", nil)) do
                if entry.spellID == 5000 then found = true end
            end
            assert(found, "a TrackedBar entry was missing from the tracked buffs source")
        end },

        { "the richer of two entries sharing a spell ID wins", function()
            Data.InvalidateCooldownInfoCache()
            local info = Data.GetCooldownInfoForSpell(5000)
            assert(info, "no cooldown entry found for a spell listed twice")
            assert(info.linkedSpellIDs and #info.linkedSpellIDs == 4,
                "the entry with no linked spells won the cache, hiding the buffs")
        end },

        { "aura mode finds a linked buff and shows its icon", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 9001, "aura")
            Data.InvalidateCooldownInfoCache()
            CV:Rebuild()

            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(icon.linkedSpellIDs, "linked spell IDs were not cached on the icon")

            CV.container.__shown = true
            wipe(_G.__auras)
            CV:UpdateState()
            assert(not icon.wanted, "aura mode showed with no buff active")

            -- The THIRD of the linked buffs is the one running.
            _G.__auras[9003] = { spellId = 9003, sourceUnit = "player" }
            CV:UpdateState()
            assert(icon.wanted, "aura mode did not find the active linked buff")
        end },

        { "a buff from someone else does not count", function()
            wipe(_G.__auras)
            _G.__auras[9002] = { spellId = 9002, sourceUnit = "party1" }
            CV:UpdateState()
            assert(not CV.icons[Data.CellKey(1, 1)].wanted,
                "someone else's buff was treated as the player's")
            wipe(_G.__auras)
        end },

        -- Regression: copying Blizzard's sourceUnit == "player" check verbatim
        -- rejected every aura, because in 12.x that field is a secret value to
        -- addon code and the comparison can never succeed. An unreadable source
        -- must be accepted or the whole mode shows nothing.
        { "a secret sourceUnit is accepted, not rejected", function()
            wipe(_G.__auras)
            _G.__auras[9002] = { spellId = 9002, sourceUnit = _G.__SECRET }
            CV:UpdateState()
            assert(CV.icons[Data.CellKey(1, 1)].wanted,
                "a buff whose source could not be read was rejected")
            wipe(_G.__auras)
        end },

        -- The failure that made tracked buffs never work in combat. Both by-ID
        -- lookups return nil in instanced combat -- recorded at
        -- modules/EssentialRings.lua:980 from an earlier investigation, and
        -- matching the logs exactly: the same buff resolves out of combat and
        -- returns nothing during it. Walking the aura list is a different code
        -- path, not the same query retried, which is the whole point.
        { "the aura is still found when both by-ID lookups return nil", function()
            local icon = CV.icons[Data.CellKey(1, 1)]

            wipe(_G.__auras)
            _G.__auras[9003] = { spellId = 9003, name = "Linked Three" }

            local realByID = C_UnitAuras.GetUnitAuraBySpellID
            local realPlayer = C_UnitAuras.GetPlayerAuraBySpellID
            C_UnitAuras.GetUnitAuraBySpellID = function() return nil end
            C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end

            CV:UpdateState()
            local foundByIndex = icon.wanted

            C_UnitAuras.GetUnitAuraBySpellID = realByID
            C_UnitAuras.GetPlayerAuraBySpellID = realPlayer
            wipe(_G.__auras)

            assert(foundByIndex,
                "the buff was missed once the by-ID lookups stopped answering")
        end },

        { "a missing sourceUnit is accepted", function()
            wipe(_G.__auras)
            _G.__auras[9003] = { spellId = 9003 }
            CV:UpdateState()
            assert(CV.icons[Data.CellKey(1, 1)].wanted,
                "a buff with no source field was rejected")
            wipe(_G.__auras)
        end },

        -- Regression: `local ok = pcall(f)` captures pcall's SUCCESS status, not
        -- f's return. Both the sweep and the stack read did that, so they scored
        -- a hit whenever the call merely did not throw -- including the cases
        -- their inner `if` deliberately skips. Clear/Hide were then never
        -- reached, and because icons are POOLED, one could show the previous
        -- occupant's sweep and stack count over an unrelated buff.
        { "a buff with no duration and no stacks leaves nothing stale", function()
            local icon = CV.icons[Data.CellKey(1, 1)]

            -- First: a timed, stacked buff, so there is something to go stale.
            wipe(_G.__auras)
            _G.__auras[9003] = {
                spellId = 9003, expirationTime = 100, duration = 10, applications = 3,
            }
            CV:UpdateState()
            assert(icon.cooldown.__cooldown, "setup: sweep was not recorded")
            assert(icon.count.__shown, "setup: stack count was not shown")

            -- Now the same icon, a buff that is neither timed nor stacked.
            wipe(_G.__auras)
            _G.__auras[9003] = { spellId = 9003, applications = 1 }
            CV:UpdateState()

            assert(icon.wanted, "the buff itself stopped being found")
            assert(not icon.cooldown.__cooldown,
                "sweep from the previous buff was left on the icon")
            assert(not icon.count.__shown,
                "stack count from the previous buff was left on the icon")
            wipe(_G.__auras)
        end },

        { "a proc glows, and stops glowing", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            profile.showProcGlow = true
            Data.SetPlacement(profile, 1, 1, 777, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true

            wipe(_G.__overlayed)
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(not icon.glowing, "icon glowed with no proc active")

            _G.__overlayed[777] = true
            CV:UpdateState()
            assert(icon.glowing, "icon did not glow on a proc")

            wipe(_G.__overlayed)
            CV:UpdateState()
            assert(not icon.glowing, "glow did not clear when the proc ended")
        end },

        { "proc mode needs BOTH ready and procced", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 888, "proc")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            -- Ready, no proc: hidden. This is the whole point of the mode --
            -- "cooldown" would show here.
            wipe(_G.__overlayed)
            _G.__cooldownState[888] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            assert(not icon.wanted, "proc mode showed a merely-usable spell")

            -- Procced but still on cooldown: hidden, not yet actionable.
            _G.__overlayed[888] = true
            _G.__cooldownState[888] = { isOnGCD = false, isActive = true }
            CV:UpdateState()
            assert(not icon.wanted, "proc mode showed a spell that was still spent")

            -- Both: shown.
            _G.__cooldownState[888] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            assert(icon.wanted, "proc mode hid a spell that was ready and procced")

            wipe(_G.__overlayed)
            CV:UpdateState()
            assert(not icon.wanted, "proc mode kept showing after the proc ended")
        end },

        { "a hidden icon never keeps a glow", function()
            local profile = Data.GetActiveProfile()
            _G.__overlayed[777] = true
            -- Spend the spell: it hides, and must drop the glow with it.
            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            CV:UpdateState()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(not icon.wanted, "spent spell stayed visible")
            assert(not icon.glowing, "a hidden icon kept its glow")
            wipe(_G.__overlayed)
        end },

        { "proc glow can be switched off", function()
            local profile = Data.GetActiveProfile()
            profile.showProcGlow = false
            _G.__overlayed[777] = true
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            assert(not CV.icons[Data.CellKey(1, 1)].glowing,
                "glow appeared while the setting was off")
            profile.showProcGlow = true
            wipe(_G.__overlayed)
        end },

        { "direction validity is per axis", function()
            assert(Data.IsDirectionValid("rows", "left"), "left should be valid for rows")
            assert(not Data.IsDirectionValid("rows", "up"), "up should be invalid for rows")
            assert(Data.IsDirectionValid("columns", "down"), "down should be valid for columns")
            assert(not Data.IsDirectionValid("columns", "right"), "right should be invalid for columns")
            assert(Data.IsDirectionValid("columns", "auto"), "auto should always be valid")
            assert(Data.IsDirectionValid("both", "bottomright"), "corners are valid for both")
            assert(not Data.IsDirectionValid("both", "left"), "an edge is not valid for both")
        end },

        { "both derives a corner from the anchor", function()
            local profile = Data.GetActiveProfile()
            profile.collapse, profile.collapseDirection = "both", "auto"
            profile.anchorCol, profile.anchorRow = 0, 0
            local right, down = Data.ResolveCollapseAxes(profile)
            assert(not right and not down, "top-left anchor should pack up and left")

            profile.anchorCol, profile.anchorRow = 10, 10
            right, down = Data.ResolveCollapseAxes(profile)
            assert(right and down, "bottom-right anchor should pack down and right")
        end },

        { "auto direction for columns reads the anchor row", function()
            local profile = Data.GetActiveProfile()
            profile.collapse, profile.collapseDirection = "columns", "auto"
            profile.anchorRow = 0
            assert(Data.ResolveCollapseDirection(profile) == "up", "anchor at top should pack up")
            profile.anchorRow = 10
            assert(Data.ResolveCollapseDirection(profile) == "down", "anchor at bottom should pack down")
        end },

        -- Regression: the grid used to vanish wholesale in combat because
        -- readiness was derived from duration, and during the GCD every spell
        -- reports a running cooldown.
        { "global cooldown does not hide icons", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 555, "cooldown")
            Data.SetPlacement(profile, 1, 2, 666, "cooldown")
            CV:Rebuild()

            -- Everything on the GCD, nothing on a real cooldown.
            _G.__cooldownState[555] = { isOnGCD = true, isActive = true }
            _G.__cooldownState[666] = { isOnGCD = true, isActive = true }
            CV.container.__shown = true
            CV:UpdateState()

            assert(CV.icons[Data.CellKey(1, 1)].wanted, "GCD hid an icon")
            assert(CV.icons[Data.CellKey(1, 2)].wanted, "GCD hid an icon")
        end },

        { "a real cooldown does hide its icon", function()
            _G.__cooldownState[555] = { isOnGCD = false, isActive = true }
            _G.__cooldownState[666] = { isOnGCD = false, isActive = false }
            CV:UpdateState()

            assert(not CV.icons[Data.CellKey(1, 1)].wanted, "spent spell stayed visible")
            assert(CV.icons[Data.CellKey(1, 2)].wanted, "ready spell was hidden")
        end },

        { "a spell that no longer resolves by name is hidden", function()
            _G.__cooldownState[555] = { isOnGCD = false, isActive = false }
            _G.__unknownNames["Spell 555"] = true
            CV:UpdateState()
            assert(not CV.icons[Data.CellKey(1, 1)].wanted,
                "an untalented spell stayed visible")
            _G.__unknownNames["Spell 555"] = nil
            CV:UpdateState()
            assert(CV.icons[Data.CellKey(1, 1)].wanted,
                "spell did not come back once it resolved again")
        end },

        -- Regression: the viewer used to strand itself hidden for a whole
        -- fight if InCombatLockdown() had not flipped when PLAYER_REGEN_DISABLED
        -- fired, because nothing re-evaluated visibility afterwards.
        { "combat start shows the viewer even if lockdown lags", function()
            local profile = Data.GetActiveProfile()
            profile.enabled, profile.onlyInCombat = true, true
            CV.previewMode = false
            _G.__inCombat = false  -- InCombatLockdown() still reports false

            CV:UpdateVisibility()
            assert(not CV.container:IsShown(), "viewer showed while out of combat")

            -- The event fires before the lockdown flag catches up.
            CV.driver:GetScript("OnEvent")(CV.driver, "PLAYER_REGEN_DISABLED")
            assert(CV.container:IsShown(),
                "viewer stayed hidden when combat started")
        end },

        { "a hidden viewer recovers on the next poll", function()
            CV.container:Hide()
            _G.__inCombat = true
            -- The throttled branch of OnUpdate must re-evaluate visibility even
            -- though the container is hidden.
            CV.driver:GetScript("OnUpdate")(CV.driver, 10)
            assert(CV.container:IsShown(), "poll did not recover a stuck-hidden viewer")
            _G.__inCombat = false
        end },

        { "auto direction follows the anchor", function()
            local profile = Data.GetActiveProfile()
            profile.collapseDirection = "auto"
            profile.anchorCol = 0
            assert(Data.ResolveCollapseDirection(profile) == "left", "anchor 0 should pack left")
            profile.anchorCol = 10
            assert(Data.ResolveCollapseDirection(profile) == "right", "anchor 10 should pack right")
            profile.anchorCol = 5
            assert(Data.ResolveCollapseDirection(profile) == "left", "dead centre should fall to left")
        end },
    }

    for _, step in ipairs(steps) do
        local ok, err = pcall(step[2])
        if ok then
            say("ok         " .. step[1])
        else
            say(("STEP FAIL  %s\n           %s"):format(step[1], tostring(err)))
            failures = failures + 1
        end
    end
end

-- Resource ring: power resolution and the static-arc maths.
if failures == 0 and ThugUI.ResourceRing then
    say("\n-- resource ring --")
    local RR = ThugUI.ResourceRing
    _G.ThugUI_CursorFrame = _G.ThugUI_CursorFrame or NewFrame()
    ThugUI_CursorFrame:Show()

    --- The fraction of the arc actually drawn, recovered from the seeded
    --- SetCooldown. With SetReverse(false) the drawn arc is what remains.
    local function DrawnFraction()
        local cd = RR.frame and RR.frame.__cooldown
        assert(cd, "resource ring never seeded a cooldown")
        local start, duration = cd[1], cd[2]
        return (start + duration - GetTime()) / duration
    end

    local function Approx(got, want, what)
        assert(math.abs(got - want) < 0.0001,
            ("%s (got %.4f, wanted %.4f)"):format(what, got, want))
    end

    local steps = {
        { "initialize", function()
            ThugUI_Config.showResourceRing = true
            RR:Initialize()
            assert(RR.frame, "no resource ring frame")
        end },

        { "arc matches the resource fraction", function()
            for _, fraction in ipairs({ 0, 0.25, 0.5, 1 }) do
                _G.__power = fraction * 100
                RR.lastFraction = nil
                RR:Update()
                Approx(DrawnFraction(), fraction, "arc for fraction " .. fraction)
            end
        end },

        { "power type follows the game by default", function()
            _G.__powerToken, _G.__form = "RAGE", 0
            RR:UpdateColor()
            local _, token = RR:GetPowerType()
            assert(token == "RAGE", "did not follow UnitPowerType, got " .. tostring(token))
        end },

        { "moonkin form overrides to astral power", function()
            -- The game still reports MANA as primary here; the override is the
            -- whole point.
            _G.__powerToken, _G.__form = "MANA", MOONKIN_FORM
            local _, token = RR:GetPowerType()
            assert(token == "LUNAR_POWER",
                "moonkin did not override to astral power, got " .. tostring(token))
            _G.__form = 0
        end },

        { "hidden when switched off", function()
            ThugUI_Config.showResourceRing = false
            RR:Update()
            assert(not RR.frame:IsShown(), "resource ring showed while disabled")
            ThugUI_Config.showResourceRing = true
        end },

        { "hidden when the resource has no maximum", function()
            _G.__powerMax = 0
            RR:Update()
            assert(not RR.frame:IsShown(), "resource ring showed with zero max power")
            _G.__powerMax = 100
        end },

        -- Regression: once taint made UnitPower permanently secret, the guard
        -- left lastFraction nil forever and the ring never appeared at all,
        -- which is indistinguishable from the feature being broken.
        { "a secret power value does not hide the ring forever", function()
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            RR.lastFraction = nil
            _G.__power = _G.__SECRET
            RR:Update()
            assert(RR.frame:IsShown(), "an unreadable power value hid the ring")
            _G.__power = 50
        end },

        { "visibility is its own setting, not the rings'", function()
            ThugUI_Config.showResourceRing = true
            ThugUI_CursorFrame:Hide()

            ThugUI_Config.resourceRingVisibility = "always"
            RR:Update()
            assert(RR.frame:IsShown(), "always mode followed the hidden cursor rings")

            ThugUI_Config.resourceRingVisibility = "rings"
            RR:Update()
            assert(not RR.frame:IsShown(), "rings mode ignored the hidden cursor rings")

            ThugUI_CursorFrame:Show()
            ThugUI_Config.resourceRingVisibility = "always"
        end },
    }

    for _, step in ipairs(steps) do
        local ok, err = pcall(step[2])
        if ok then
            say("ok         " .. step[1])
        else
            say(("STEP FAIL  %s\n           %s"):format(step[1], tostring(err)))
            failures = failures + 1
        end
    end
end

-- Combo pips: which resource, how many, and how many are lit.
if failures == 0 and ThugUI.ComboPips then
    say("\n-- combo pips --")
    local CP = ThugUI.ComboPips
    _G.ThugUI_CursorFrame = _G.ThugUI_CursorFrame or NewFrame()
    ThugUI_CursorFrame:Show()

    local realUnitClass = UnitClass
    local function AsClass(class)
        _G.UnitClass = function() return class:lower(), class end
    end

    local function Lit()
        local count = 0
        for _, pip in ipairs(CP.pips) do
            if pip.__shown and (pip.__alpha == nil or pip.__alpha == 1) then
                count = count + 1
            end
        end
        return count
    end

    local function Visible()
        local count = 0
        for _, pip in ipairs(CP.pips) do
            if pip.__shown then count = count + 1 end
        end
        return count
    end

    local steps = {
        { "initialize", function()
            AsClass("ROGUE")
            ThugUI_Config.showComboPips = true
            ThugUI_Config.comboPipVisibility = "always"
            _G.__classPower, _G.__classPowerMax = 0, 5
            CP:Initialize()
            assert(CP.frame, "no combo pip frame")
        end },

        { "one pip per point of maximum", function()
            CP:Refresh()
            assert(Visible() == 5, "expected 5 pips, got " .. Visible())
            assert(CP.frame:IsShown(), "pips did not show")
        end },

        { "gaining a point lights another pip", function()
            _G.__classPower = 3
            CP:Update()
            assert(Lit() == 3, "expected 3 lit pips, got " .. Lit())
        end },

        -- Deeper Stratagem and its equivalents move the maximum mid-fight. The
        -- pips must re-lay out, not just light a sixth that was never placed.
        { "a changed maximum re-lays out", function()
            _G.__classPowerMax = 6
            CP:Update()
            assert(Visible() == 6, "expected 6 pips, got " .. Visible())
        end },

        { "pips are evenly spaced around the ring", function()
            _G.__classPowerMax = 4
            CP:Update()
            local seen = {}
            for i = 1, 4 do
                local point = CP.pips[i].__point
                assert(point, "pip " .. i .. " was never anchored")
                seen[i] = { x = point[4], y = point[5] }
            end
            local radius = math.sqrt(seen[1].x ^ 2 + seen[1].y ^ 2)
            assert(radius > 0, "pips were placed on top of the centre")

            -- Same distance from the centre, and a quarter turn apart. Radius
            -- alone would pass a layout that stacked every pip in one spot.
            for i = 2, 4 do
                local r = math.sqrt(seen[i].x ^ 2 + seen[i].y ^ 2)
                assert(math.abs(r - radius) < 0.001,
                    ("pip %d sits at a different radius (%.3f vs %.3f)"):format(i, r, radius))

                local previous = math.atan(seen[i - 1].x, seen[i - 1].y)
                local current = math.atan(seen[i].x, seen[i].y)
                local step = (current - previous) % (2 * math.pi)
                assert(math.abs(step - math.pi / 2) < 0.001,
                    ("pip %d is %.3f rad from the last, wanted %.3f"):format(i, step, math.pi / 2))
            end
        end },

        { "no pips for a class without a secondary resource", function()
            AsClass("WARRIOR")
            CP:Refresh()
            assert(not CP.frame:IsShown(), "a warrior was given combo pips")
            AsClass("ROGUE")
        end },

        -- Combo points exist in the API for a druid in any form. Only cat form
        -- generates them, and the primary power type is what says so.
        { "a druid gets pips only in cat form", function()
            AsClass("DRUID")
            _G.__powerToken = "MANA"
            CP:Refresh()
            assert(not CP.frame:IsShown(), "a caster-form druid was given combo pips")

            _G.__powerToken = "ENERGY"
            CP:Refresh()
            assert(CP.frame:IsShown(), "a cat-form druid was denied combo pips")

            _G.__powerToken = "MANA"
            AsClass("ROGUE")
        end },

        -- Before 12.1 this is the normal state in combat. Freezing is fine;
        -- throwing, or silently vanishing with no explanation, is not.
        { "a secret power value holds the last layout", function()
            _G.__classPowerMax = 5
            _G.__classPower = 2
            CP:Refresh()
            assert(CP.frame:IsShown(), "pips were hidden before the secret test")

            _G.__classPower = _G.__SECRET
            CP:Update()
            assert(CP.frame:IsShown(), "an unreadable power value hid the pips")
            assert(Visible() == 5, "the frozen layout lost its pips")
            _G.__classPower = 2
        end },

        { "hidden when switched off", function()
            ThugUI_Config.showComboPips = false
            CP:Update()
            assert(not CP.frame:IsShown(), "pips showed while disabled")
            ThugUI_Config.showComboPips = true
        end },

        { "restore", function()
            _G.UnitClass = realUnitClass
            ThugUI_Config.showComboPips = false
        end },
    }

    for _, step in ipairs(steps) do
        local ok, err = pcall(step[2])
        if ok then
            say("ok         " .. step[1])
        else
            say(("STEP FAIL  %s\n           %s"):format(step[1], tostring(err)))
            failures = failures + 1
        end
    end
end

-- Secret probe: it exists to be run while values are unreadable, so the thing
-- to prove is that it stays quiet and complete when every read is refused.
-- A diagnostic that throws on the exact condition it was built to record is
-- worse than no diagnostic, and this addon has already shipped one of those.
if failures == 0 and ThugUI.SecretProbe then
    say("\n-- secret probe --")
    local SP = ThugUI.SecretProbe

    local function Lines(phase)
        local sample = ThugUI_DebugLog and ThugUI_DebugLog.secrets
            and ThugUI_DebugLog.secrets[phase]
        assert(sample, "no sample recorded for " .. phase)
        return table.concat(sample.lines, "\n")
    end

    local steps = {
        { "records a sample with readable values", function()
            ThugUI_DebugLog.secrets = {}
            _G.__power = 50
            SP:Run("readable")
            local text = Lines("readable")
            assert(text:match("UnitPower primary%s+50"),
                "did not report a readable power value:\n" .. text)
        end },

        -- The whole point. A secret must be described, never compared,
        -- concatenated or tostring'd.
        { "a secret power value is described, not read", function()
            ThugUI_DebugLog.secrets = {}
            _G.__power = _G.__SECRET
            SP:Run("secret")
            local text = Lines("secret")
            assert(text:match("UnitPower primary%s+SECRET"),
                "a secret power value was not reported as secret:\n" .. text)
            _G.__power = 50
        end },

        { "a secret aura struct does not throw", function()
            ThugUI_DebugLog.secrets = {}
            local real = C_UnitAuras.GetAuraDataByIndex
            C_UnitAuras.GetAuraDataByIndex = function(unit, index)
                if index > 1 then return nil end
                return _G.__SECRET
            end

            local ok, err = pcall(function() SP:Run("secret-aura") end)
            C_UnitAuras.GetAuraDataByIndex = real
            assert(ok, "probing a secret aura struct threw: " .. tostring(err))

            local text = Lines("secret-aura")
            assert(text:match("aura list length%s+1"),
                "did not count the secret aura:\n" .. text)
        end },

        { "a missing API is reported, not fatal", function()
            ThugUI_DebugLog.secrets = {}
            local real = C_UnitAuras.GetUnitAuraBySpellID
            C_UnitAuras.GetUnitAuraBySpellID = nil

            local ok = pcall(function() SP:Run("absent-api") end)
            C_UnitAuras.GetUnitAuraBySpellID = real
            assert(ok, "a missing API took the probe down")
        end },

        -- A fight with nothing up is a valid sample and a useless one. It must
        -- not overwrite the sample that actually caught a buff.
        { "a thin sample never buries a rich one", function()
            ThugUI_DebugLog.secrets = {}
            _G.__auras[5101] = { spellId = 5101, name = "Spell 5101" }
            _G.__auras[5102] = { spellId = 5102, name = "Spell 5102" }
            SP:Run("phase")
            local rich = ThugUI_DebugLog.secrets["phase"].auras
            assert(rich == 2, "expected 2 auras, got " .. tostring(rich))

            _G.__auras[5101], _G.__auras[5102] = nil, nil
            SP:Run("phase")
            assert(ThugUI_DebugLog.secrets["phase"].auras == 2,
                "an empty sample overwrote a richer one")
        end },
    }

    for _, step in ipairs(steps) do
        local ok, err = pcall(step[2])
        if ok then
            say("ok         " .. step[1])
        else
            say(("STEP FAIL  %s\n           %s"):format(step[1], tostring(err)))
            failures = failures + 1
        end
    end
end

say(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
