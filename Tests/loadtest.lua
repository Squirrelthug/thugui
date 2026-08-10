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
            -- Strata and scale are modelled because the Blizzard-buff tests
            -- assert on WHOSE frame changed. Lifting their viewer instead of
            -- lowering our icon is the taint bug that killed the cooldown
            -- viewer for a whole session -- a test that cannot tell the two
            -- apart cannot catch it coming back.
            if key == "SetFrameStrata" then a.__strata = a1 return end
            if key == "SetScale" then a.__scale = a1 return end
            if key == "GetFrameStrata" then return a.__strata or "MEDIUM" end
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
        { "unknown category reaches cache and dump", function()
            Enum.CooldownViewerCategory.FutureCategory = 4
            _G.__cooldownEntries[6] = { cooldownID = 6, spellID = 88888 }
            _G.__categorySets.FutureCategory = { 6 }

            Data.InvalidateCooldownInfoCache()
            local info = Data.GetCooldownInfoForSpell(88888)
            assert(info and info.cooldownID == 6, "unknown category entry not indexed in cache")

            local dump = Data.DumpCooldownViewer()
            local foundInDump = false
            for _, item in ipairs(dump) do
                if item.category == "FutureCategory" and item.cooldownID == 6 then
                    foundInDump = true
                    break
                end
            end
            assert(foundInDump, "unknown category entry not included in dump")

            Enum.CooldownViewerCategory.FutureCategory = nil
            _G.__cooldownEntries[6] = nil
            _G.__categorySets.FutureCategory = nil
            Data.InvalidateCooldownInfoCache()
        end },
        { "unknown category reaches all source and not curated sources", function()
            Enum.CooldownViewerCategory.FutureCategory = 4
            _G.__cooldownEntries[6] = { cooldownID = 6, spellID = 88888 }
            _G.__categorySets.FutureCategory = { 6 }

            local allList = Data.BuildSpellList("all", nil)
            local inAll = false
            for _, entry in ipairs(allList) do
                if entry.spellID == 88888 then
                    inAll = true
                    break
                end
            end
            assert(inAll, "unknown category spell not offered in 'all' source")

            for _, sourceKey in ipairs({ "essential", "utility", "buffs" }) do
                local list = Data.BuildSpellList(sourceKey, nil)
                for _, entry in ipairs(list) do
                    assert(entry.spellID ~= 88888,
                        ("unknown category spell leaked into curated source %s"):format(sourceKey))
                end
            end

            Enum.CooldownViewerCategory.FutureCategory = nil
            _G.__cooldownEntries[6] = nil
            _G.__categorySets.FutureCategory = nil
        end },
        { "dump is ordered deterministically by category value", function()
            Enum.CooldownViewerCategory.FutureHigh = 10
            Enum.CooldownViewerCategory.FutureLow = 4
            _G.__cooldownEntries[10] = { cooldownID = 10, spellID = 99990 }
            _G.__cooldownEntries[40] = { cooldownID = 40, spellID = 99994 }
            _G.__categorySets.FutureHigh = { 10 }
            _G.__categorySets.FutureLow = { 40 }

            local dump1 = Data.DumpCooldownViewer()
            local dump2 = Data.DumpCooldownViewer()

            assert(#dump1 == #dump2, "dump output length non-deterministic")

            local categoryValues = {
                Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3,
                FutureLow = 4, FutureHigh = 10
            }
            local lastVal = -1
            for i, item in ipairs(dump1) do
                local val = categoryValues[item.category]
                assert(val, "unknown category in dump check: " .. tostring(item.category))
                assert(val >= lastVal, ("dump not ordered by category value ascending at index %d"):format(i))
                assert(item.cooldownID == dump2[i].cooldownID, "dump mismatch between calls")
                lastVal = val
            end

            Enum.CooldownViewerCategory.FutureHigh = nil
            Enum.CooldownViewerCategory.FutureLow = nil
            _G.__cooldownEntries[10] = nil
            _G.__cooldownEntries[40] = nil
            _G.__categorySets.FutureHigh = nil
            _G.__categorySets.FutureLow = nil
        end },
        { "non-numeric keys in enum table are skipped", function()
            Enum.CooldownViewerCategory.Meta = { version = 1 }

            local dump = Data.DumpCooldownViewer()
            for _, item in ipairs(dump) do
                assert(item.category ~= "Meta", "non-numeric enum key appeared in dump")
            end

            Enum.CooldownViewerCategory.Meta = nil
        end },
        { "missing CooldownViewerCategory degrades to empty safely", function()
            local realEnumCat = Enum.CooldownViewerCategory
            Enum.CooldownViewerCategory = nil
            Data.InvalidateCooldownInfoCache()

            local dump = Data.DumpCooldownViewer()
            assert(type(dump) == "table" and #dump == 0, "dump did not degrade to empty table")

            local info = Data.GetCooldownInfoForSpell(1001)
            assert(info == nil, "cache returned info when enum was missing")

            local list = Data.BuildSpellList("all", nil)
            assert(type(list) == "table", "BuildSpellList('all') failed when enum missing")

            Enum.CooldownViewerCategory = realEnumCat
            Data.InvalidateCooldownInfoCache()
        end },
        { "Blizzard's negative pseudo-categories are ignored", function()
            Enum.CooldownViewerCategory.HiddenSpell = -1
            Enum.CooldownViewerCategory.HiddenAura = -2
            _G.__cooldownEntries[99] = { cooldownID = 99, spellID = 9999 }
            _G.__categorySets.HiddenSpell = { 99 }
            _G.__categorySets.HiddenAura = { 99 }

            Data.InvalidateCooldownInfoCache()

            local info = Data.GetCooldownInfoForSpell(9999)
            assert(info == nil, "spell in negative pseudo-category was indexed by GetCooldownInfoForSpell")

            local dump = Data.DumpCooldownViewer()
            local foundInDump = false
            for _, item in ipairs(dump) do
                if item.spellID == 9999 then
                    foundInDump = true
                    break
                end
            end
            assert(not foundInDump, "spell in negative pseudo-category appeared in DumpCooldownViewer")

            local allList = Data.BuildSpellList("all", nil)
            local foundInList = false
            for _, entry in ipairs(allList) do
                if entry.spellID == 9999 then
                    foundInList = true
                    break
                end
            end
            assert(not foundInList, "spell in negative pseudo-category appeared in BuildSpellList('all')")

            Enum.CooldownViewerCategory.HiddenSpell = nil
            Enum.CooldownViewerCategory.HiddenAura = nil
            _G.__cooldownEntries[99] = nil
            _G.__categorySets.HiddenSpell = nil
            _G.__categorySets.HiddenAura = nil
            Data.InvalidateCooldownInfoCache()
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

        -- A tracked buff can only reach a cell through Blizzard's own frame, so
        -- with that workaround off there is nothing a buff placement could ever
        -- draw. Offering one anyway produces a cell that stays empty and says
        -- nothing, which is the exact failure this whole feature is about.
        { "buff categories are withheld while the workaround is off", function()
            local restore = ThugUI_Config.cvUseBlizzardBuffs
            ThugUI_Config.cvUseBlizzardBuffs = false
            Data.InvalidateCooldownInfoCache()

            local buffs = Data.BuildSpellList("buffs", nil)
            assert(#buffs == 0,
                ("the tracked buffs source still offered %d entries"):format(#buffs))

            local inAll = {}
            for _, entry in ipairs(Data.BuildSpellList("all", nil)) do
                inAll[entry.spellID] = true
            end
            -- 9001 exists only in TrackedBuff; 5101 only as a TrackedBar linked
            -- buff. Both are unreachable by any other route, so either one
            -- surviving means a buff category was still read.
            assert(not inAll[9001], "a TrackedBuff entry survived in 'all'")
            assert(not inAll[5101], "a TrackedBar linked buff survived in 'all'")

            ThugUI_Config.cvUseBlizzardBuffs = restore
        end },

        -- nil means ON -- the module's IsEnabled reads `~= false`. Getting this
        -- backwards silently empties the picker for a player who has never
        -- touched the setting, which is most of them.
        { "buff categories are offered when the setting is on or unset", function()
            local restore = ThugUI_Config.cvUseBlizzardBuffs

            for _, state in ipairs({ "on", "unset" }) do
                ThugUI_Config.cvUseBlizzardBuffs = (state == "on") and true or nil

                local inBuffs = {}
                for _, entry in ipairs(Data.BuildSpellList("buffs", nil)) do
                    inBuffs[entry.spellID] = true
                end
                assert(inBuffs[9001],
                    ("a tracked buff was missing with the setting %s"):format(state))

                local inAll = {}
                for _, entry in ipairs(Data.BuildSpellList("all", nil)) do
                    inAll[entry.spellID] = true
                end
                assert(inAll[5101],
                    ("a linked buff was missing from 'all' with the setting %s"):format(state))
            end

            ThugUI_Config.cvUseBlizzardBuffs = restore
        end },

        { "the other picker sources are untouched by the buff setting", function()
            local restore = ThugUI_Config.cvUseBlizzardBuffs
            local sources = { "essential", "utility", "spellbook" }

            ThugUI_Config.cvUseBlizzardBuffs = true
            local before = {}
            for _, source in ipairs(sources) do
                before[source] = #Data.BuildSpellList(source, nil)
                assert(before[source] > 0, "setup: source " .. source .. " was already empty")
            end

            ThugUI_Config.cvUseBlizzardBuffs = false
            for _, source in ipairs(sources) do
                assert(#Data.BuildSpellList(source, nil) == before[source],
                    ("source %s changed when the buff setting did"):format(source))
            end

            ThugUI_Config.cvUseBlizzardBuffs = restore
        end },

        -- The guide panel. Built once with the page and shown/hidden after --
        -- never rebuilt, never SetParent(nil)'d.
        { "the buff workaround guide builds hidden and toggles", function()
            local BuffGuide = ThugUI.CooldownViewer.BuffGuide
            assert(BuffGuide, "the guide module did not load")

            local panel = BuffGuide:Ensure()
            assert(panel, "the guide panel was not built")
            assert(not panel:IsShown(), "the guide panel started visible")

            BuffGuide:Toggle()
            assert(panel:IsShown(), "the guide did not open on click")
            assert(BuffGuide:Ensure() == panel,
                "the guide built a second panel instead of reusing the first")

            BuffGuide:Toggle()
            assert(not panel:IsShown(), "the guide did not close again")
        end },

        -- Hovering is where the popout code actually runs; building the panel
        -- never touches it.
        { "hovering a step opens its screenshot, and step 1 opens none", function()
            local BuffGuide = ThugUI.CooldownViewer.BuffGuide
            BuffGuide:Ensure()

            BuffGuide:ShowShot(BuffGuide.rows[2], BuffGuide.STEPS[2])
            assert(BuffGuide.popout and BuffGuide.popout:IsShown(),
                "the screenshot popout did not open")

            BuffGuide:ShowShot(BuffGuide.rows[1], BuffGuide.STEPS[1])
            assert(not BuffGuide.popout:IsShown(),
                "a step with no screenshot still opened a popout")

            BuffGuide:HideShot()
        end },

        -- A key that does not exist draws a blank frame in game and reports
        -- nothing anywhere, so a typo would only ever be found by the player.
        { "every screenshot a guide step names exists", function()
            local BuffGuide = ThugUI.CooldownViewer.BuffGuide
            local shots, guideSteps = BuffGuide.SHOTS, BuffGuide.STEPS
            assert(shots and guideSteps, "the guide did not expose its tables")

            local named = 0
            for i, step in ipairs(guideSteps) do
                for _, key in ipairs(step.shots or {}) do
                    local shot = shots[key]
                    assert(shot, ("step %d names a screenshot that does not exist: %s")
                        :format(i, tostring(key)))
                    assert(shot.file and shot.u and shot.v and shot.aspect,
                        ("screenshot %s is missing its file or crop"):format(key))
                    named = named + 1
                end
            end
            assert(named > 0, "no step named a screenshot at all")
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

-- Blizzard buff items adopted into grid cells. The reason this exists at all is
-- that an addon cannot identify an aura in combat, so the cell has to be driven
-- by Blizzard's own frame -- which means the plumbing that finds and anchors
-- that frame is now load-bearing for the feature working at all.
if failures == 0 and ThugUI.CooldownViewer and ThugUI.CooldownViewer.BlizzBuffs then
    say("\n-- blizzard buff items --")
    local CV = ThugUI.CooldownViewer
    local Data = CV.Data
    local BB = CV.BlizzBuffs

    -- Stands in for BuffIconCooldownViewer. Cooldown ID 3 is the entry the
    -- stub data defines purely by its linked buffs, which is the Roll the Bones
    -- shape: no aura is ever named after the spell that granted it.
    local viewer = NewFrame()
    local item = NewFrame()
    item.GetCooldownID = function() return 3 end
    item.GetParent = function() return viewer end
    -- Shown by default. Blizzard's item hides itself when the buff drops, so its
    -- shown state is now what decides whether an adopted cell keeps its slot --
    -- and "the buff is up" is the resting assumption of every case here that is
    -- about adoption rather than about collapse.
    item.__shown = true

    --- Drive the item's shown state: true, false, or "secret".
    ---
    --- "secret" stands in for the client handing us a secret boolean in combat,
    --- which BB:ItemIsShown must report as "cannot tell" (nil) rather than as
    --- false -- those two need opposite handling and a boolean merges them.
    local function ItemShown(state)
        if state == "secret" then
            item.IsShown = function() return _G.__SECRET end
        else
            item.IsShown = nil    -- back to the frame stub's own modelling
            item.__shown = state and true or false
        end
    end

    viewer.itemFramePool = {
        EnumerateActive = function()
            local i = 0
            return function()
                i = i + 1
                if i == 1 then return item end
            end
        end,
    }
    _G.BuffIconCooldownViewer = viewer

    local function PlaceAura(spellID)
        local profile = Data.GetActiveProfile()
        wipe(profile.placements)
        profile.collapse = "none"
        profile.enabled, profile.onlyInCombat = true, false
        Data.SetPlacement(profile, 1, 1, spellID, "aura")
        Data.InvalidateCooldownInfoCache()
        CV:Rebuild()
        CV.container.__shown = true
        return CV.icons[Data.CellKey(1, 1)]
    end

    local steps = {
        { "an aura icon is adopted by its Blizzard item", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local icon = PlaceAura(9001)
            BB:Refresh()
            assert(BB:AdoptedItem(icon) == item, "the Blizzard item was not adopted")
        end },

        { "the item is anchored over the cell", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            local point = item.__point
            assert(point, "the adopted item was never anchored")
            assert(point[2] == icon,
                "the item was anchored to something other than its cell")
        end },

        -- Both halves matter: ours must not draw over Blizzard's, and the cell
        -- must stay reserved or collapse slides the row over the top of it.
        { "our own art is suppressed but the cell is kept", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            wipe(_G.__auras)
            CV:UpdateState()
            assert(icon.wanted, "an adopted cell stopped being wanted")
            assert(icon.tex.__alpha == 0, "our own icon art was still drawn")
        end },

        -- The three regression cases below are the taint bug of 2026-08-09,
        -- pinned open. Each one is a thing BlizzBuffs used to do to Blizzard's
        -- frames that made their own OnEvent handlers throw and emptied the
        -- item pool until /reload. See docs/DECISIONS.md §15.
        { "nothing is written onto Blizzard's frames", function()
            for key in pairs(item) do
                assert(not tostring(key):match("^__thug"),
                    "a field was set on the Blizzard item: " .. tostring(key))
            end
            for key in pairs(viewer) do
                assert(not tostring(key):match("^__thug"),
                    "a field was set on the Blizzard viewer: " .. tostring(key))
            end
        end },

        { "our icon is lowered, their viewer is left alone", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(viewer.__strata == nil,
                "the Edit Mode system frame had its strata changed")
            assert(icon.__strata == viewer:GetFrameStrata(),
                "our icon was not dropped to the viewer's strata")
        end },

        { "a hidden grid hands the buffs back", function()
            CV.container.__shown = false
            BB:Refresh()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(BB:AdoptedItem(icon) == nil, "the item was held while the grid was hidden")
            assert(item.__scale == 1, "the item kept the scale we gave it")
            -- Put back by our own SetPoint, never by calling their RefreshLayout
            -- from our stack.
            assert(item.__point and item.__point[1] == "TOPLEFT",
                "the item was not returned to the anchor Blizzard gave it")
            CV.container.__shown = true
        end },

        -- The escape hatch has to actually let go, and the old aura path has to
        -- still work when it does.
        { "switching it off restores the aura path", function()
            ThugUI_Config.cvUseBlizzardBuffs = false
            local icon = PlaceAura(9001)
            BB:Refresh()
            assert(BB:AdoptedItem(icon) == nil, "an item was adopted while disabled")

            wipe(_G.__auras)
            CV:UpdateState()
            assert(not icon.wanted, "the aura path did not resume")
            _G.__auras[9003] = { spellId = 9003, sourceUnit = "player" }
            CV:UpdateState()
            assert(icon.wanted, "the aura path did not find the linked buff")
            assert(icon.tex.__alpha ~= 0, "the aura path drew nothing")
            wipe(_G.__auras)
        end },

        { "an unmatched spell logs no item frame stage once", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local icon = PlaceAura(1001)
            BB:Refresh()
            BB:Refresh()

            local count = 0
            for _, line in ipairs(ThugUI_DebugLog.events or {}) do
                if line:find("no matching item frame", 1, true) and line:find("1001", 1, true) then
                    count = count + 1
                end
            end
            assert(count == 1, ("expected no matching item frame logged once, got %d"):format(count))
        end },

        { "an adopted icon is shown even when its spell name does not resolve", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local icon = PlaceAura(9001)
            BB:Refresh()
            assert(BB:AdoptedItem(icon) == item, "precondition: Blizzard item was not adopted")

            _G.__unknownNames["Spell 9001"] = true
            CV:UpdateState()

            assert(icon.wanted, "an adopted cell whose spell name does not resolve was not wanted")
            assert(icon:IsShown(), "an adopted cell whose spell name does not resolve was not shown")

            _G.__unknownNames["Spell 9001"] = nil
        end },

        { "an adopted cell keeps its slot under columns collapse", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "columns"
            profile.collapseDirection = "up"
            profile.enabled, profile.onlyInCombat = true, false

            Data.SetPlacement(profile, 1, 1, 1001, "always")
            Data.SetPlacement(profile, 3, 1, 9001, "aura")
            Data.InvalidateCooldownInfoCache()
            CV:Rebuild()
            CV.container.__shown = true

            local iconTop = CV.icons[Data.CellKey(1, 1)]
            local iconAdopted = CV.icons[Data.CellKey(3, 1)]

            BB:Refresh()
            assert(BB:AdoptedItem(iconAdopted) == item, "precondition: 9001 item was not adopted")

            _G.__unknownNames["Spell 9001"] = true
            CV:UpdateState()

            assert(iconAdopted.wanted, "adopted cell was not wanted under columns collapse")
            local _, cellH, _, pad = CV:GetCellSize(profile)
            local expectedY = -((2 - 1) * cellH + pad / 2)
            assert(iconAdopted.__point and iconAdopted.__point[5] == expectedY,
                ("adopted cell did not collapse into slot 2 (expected y=%.1f, got y=%s)"):format(
                    expectedY, tostring(iconAdopted.__point and iconAdopted.__point[5])))

            _G.__unknownNames["Spell 9001"] = nil
            profile.collapse = "none"
        end },

        -- The three sources that decide whether an adopted cell keeps its slot,
        -- in descending order of authority: Blizzard's item frame, then our own
        -- aura lookup, then "reserve it". Each case below pins one rung of that
        -- ladder, because the whole bug was a single unconditional `show = true`
        -- standing in for all three.
        { "an item Blizzard is showing keeps its cell, aura or no aura", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local icon = PlaceAura(9001)
            BB:Refresh()
            assert(BB:AdoptedItem(icon) == item, "precondition: item was not adopted")

            wipe(_G.__auras)
            ItemShown(true)
            _G.__inCombat = true
            CV:UpdateState()
            assert(icon.wanted, "a cell whose Blizzard item is shown was not wanted")
            _G.__inCombat = false
        end },

        { "an item Blizzard has hidden gives up its cell, even in combat", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            ItemShown(false)
            _G.__inCombat = true
            CV:UpdateState()
            assert(not icon.wanted, "a cell whose Blizzard item is hidden was still wanted")
            _G.__inCombat = false
            ItemShown(true)
        end },

        -- Unsure must mean "keep the slot": collapsing a cell whose buff is
        -- actually up leaves Blizzard's item anchored to our hidden icon, drawing
        -- at a stale coordinate on top of a neighbour.
        { "an unreadable shown state reserves the cell in combat", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            wipe(_G.__auras)
            ItemShown("secret")
            _G.__inCombat = true
            CV:UpdateState()
            assert(icon.wanted, "a cell we could not read was released in combat")
            _G.__inCombat = false
        end },

        { "out of combat an unreadable item falls back to our aura lookup", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            ItemShown("secret")
            _G.__inCombat = false
            -- 9003 is one of 9001's linked buffs, which is the Roll the Bones
            -- shape: no aura is ever named after the spell that granted it.
            _G.__auras[9003] = { spellId = 9003, sourceUnit = "player" }
            CV:UpdateState()
            assert(icon.wanted, "the aura path did not keep the cell for a buff that is up")
            wipe(_G.__auras)
        end },

        { "out of combat with the buff down and the item unreadable, the cell goes", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            ItemShown("secret")
            _G.__inCombat = false
            wipe(_G.__auras)
            CV:UpdateState()
            assert(not icon.wanted,
                "an adopted cell was reserved with the buff down, out of combat")
        end },

        -- The player's actual complaint: with columns collapse on, the gap where
        -- an adopted buff sits never closed, in or out of combat. Asserting on
        -- the NEIGHBOUR's position rather than on `wanted`, because the layout is
        -- what the player sees and `wanted` was already covered above.
        { "the column actually closes when the buff is down", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "columns"
            profile.collapseDirection = "up"
            profile.enabled, profile.onlyInCombat = true, false

            Data.SetPlacement(profile, 1, 1, 1001, "always")
            Data.SetPlacement(profile, 3, 1, 9001, "aura")
            Data.SetPlacement(profile, 5, 1, 1002, "always")
            Data.InvalidateCooldownInfoCache()
            CV:Rebuild()
            CV.container.__shown = true

            local iconAdopted = CV.icons[Data.CellKey(3, 1)]
            local iconBelow = CV.icons[Data.CellKey(5, 1)]

            BB:Refresh()
            assert(BB:AdoptedItem(iconAdopted) == item, "precondition: 9001 item was not adopted")

            local _, cellH, _, pad = CV:GetCellSize(profile)
            local function SlotY(slot) return -((slot - 1) * cellH + pad / 2) end
            local function AssertSlot(icon, slot, what)
                local got = icon.__point and icon.__point[5]
                assert(got == SlotY(slot),
                    ("%s (expected y=%.1f for slot %d, got y=%s)"):format(
                        what, SlotY(slot), slot, tostring(got)))
            end

            -- Buff up: three live cells, so the neighbour packs into slot 3.
            ItemShown(true)
            wipe(_G.__auras)
            CV:UpdateState()
            assert(iconAdopted.wanted, "precondition: adopted cell was released with its item shown")
            AssertSlot(iconBelow, 3, "neighbour did not pack behind a live adopted cell")

            -- Buff down, item unreadable, out of combat: the adopted cell is
            -- released and the neighbour takes the slot it freed.
            ItemShown("secret")
            _G.__inCombat = false
            CV:UpdateState()
            assert(not iconAdopted.wanted, "the adopted cell held its slot with the buff down")
            AssertSlot(iconBelow, 2, "the column did not close over the released cell")

            ItemShown(true)
            profile.collapse = "none"
        end },

        -- A client with no screening function cannot prove a value is safe to
        -- touch, so the item's state is refused rather than trusted. The fallback
        -- must still resolve, and nothing may throw.
        { "no issecretvalue at all degrades safely", function()
            local icon = PlaceAura(9001)
            BB:Refresh()
            assert(BB:AdoptedItem(icon) == item, "precondition: item was not adopted")

            local realScreen = _G.issecretvalue
            _G.issecretvalue = nil
            ItemShown(true)
            _G.__inCombat = false
            wipe(_G.__auras)

            local ok, err = pcall(CV.UpdateState, CV)
            _G.issecretvalue = realScreen

            assert(ok, "UpdateState threw with no issecretvalue: " .. tostring(err))
            assert(not icon.wanted,
                "a client with no secret screening still reserved the cell")
        end },

        -- Restored during review of task 05, which repurposed this case in place
        -- rather than adding alongside it. It guards the FALLBACK: a spell
        -- Blizzard is not drawing must still reach ThugUI's own aura path. That
        -- fallthrough sits directly below the branch task 05 reordered, so it is
        -- exactly the coverage a reorder there could break.
        { "an unmatched spell is left to the aura path", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local icon = PlaceAura(1001)
            BB:Refresh()
            assert(BB:AdoptedItem(icon) == nil, "an unrelated item was adopted")

            _G.__auras[1001] = { spellId = 1001, sourceUnit = "player" }
            CV:UpdateState()
            assert(icon.wanted, "the aura path did not run for an unmatched spell")
            wipe(_G.__auras)
        end },

        { "a non-adopted icon whose spell does not resolve is still hidden", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local icon = PlaceAura(1001)
            BB:Refresh()
            assert(BB:AdoptedItem(icon) == nil, "precondition: 1001 should not be adopted")

            _G.__unknownNames["Spell 1001"] = true
            CV:UpdateState()

            assert(not icon.wanted, "a non-adopted icon with unresolved spell name was wanted")
            assert(not icon:IsShown(), "a non-adopted icon with unresolved spell name was shown")

            _G.__unknownNames["Spell 1001"] = nil
        end },

        { "an Apply error is logged and applying flag is cleared", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            PlaceAura(9001)
            -- Force an error inside Apply when processing item
            item.ClearAllPoints = function() error("forced Apply failure") end

            BB:Refresh()
            assert(not BB.applying, "applying flag remained true after Apply threw")

            item.ClearAllPoints = function() end

            local foundErrorLog = false
            for _, line in ipairs(ThugUI_DebugLog.events or {}) do
                if line:find("CVBUFF", 1, true) and line:find("forced Apply failure", 1, true) then
                    foundErrorLog = true
                    break
                end
            end
            assert(foundErrorLog, "Apply error was not logged in ThugUI_DebugLog")

            -- Verify subsequent Refresh runs without early return
            local ranSecondPass = false
            local realItems = BB.ItemsByCooldownID
            BB.ItemsByCooldownID = function(self)
                ranSecondPass = true
                return realItems(self)
            end
            BB:Refresh()
            BB.ItemsByCooldownID = realItems
            assert(ranSecondPass, "subsequent BB:Refresh did not run after error")
        end },

        { "restore", function()
            ThugUI_Config.cvUseBlizzardBuffs = nil
            _G.BuffIconCooldownViewer = nil
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            CV:Rebuild()
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

        -- The offset now reaches past the centre, and a negative radius mirrors
        -- every pip a half turn instead of erroring -- which reads as the ring
        -- flipping as the slider crosses zero.
        { "a tight ring never flips to the other side", function()
            ThugUI_Config.comboPipOffset = -500
            CP:Refresh()
            for i = 1, CP.lastMax or 0 do
                local point = CP.pips[i].__point
                local radius = math.sqrt(point[4] ^ 2 + point[5] ^ 2)
                assert(radius < 0.001,
                    ("pip %d was placed at radius %.3f, expected the centre"):format(i, radius))
            end
            ThugUI_Config.comboPipOffset = nil
            CP:Refresh()
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
