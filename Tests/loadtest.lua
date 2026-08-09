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
        end
        if key:match("^Get") then
            if key == "GetWidth" or key == "GetHeight" or key == "GetStringWidth"
                or key == "GetStringHeight" or key == "GetFrameLevel" then
                return 100
            end
            if key == "GetScale" or key == "GetEffectiveScale" then return 1 end
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

-- 12.x secret values. Anything carrying __secret stands in for a field the
-- client will not let addon code read.
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
local SECRET = { __secret = true }
_G.__SECRET = SECRET

-- Resource ring. __powerToken is what UnitPowerType reports (it already
-- follows shapeshift form in the real game); __form drives the override path.
_G.__powerToken = "MANA"
_G.__power, _G.__powerMax = 50, 100
_G.__form = 0
function UnitPowerType() return 0, _G.__powerToken end
function UnitPower() return _G.__power end
function UnitPowerMax() return _G.__powerMax end
function GetShapeshiftFormID() return _G.__form end
MOONKIN_FORM = 31
PowerBarColor = {
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
    PowerType = { Mana = 0, Rage = 1, Energy = 3, LunarPower = 8 },
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
}

-- Cooldown entry 3 models Roll the Bones: no base spellID of its own, just a
-- set of possible buffs in linkedSpellIDs.
_G.__cooldownEntries = {
    [1] = { cooldownID = 1, spellID = 1001 },
    [2] = { cooldownID = 2, spellID = 1002 },
    [3] = { cooldownID = 3, spellID = nil, linkedSpellIDs = { 9001, 9002, 9003 } },
}
C_CooldownViewer = {
    GetCooldownViewerCategorySet = function() return { 1, 2, 3 } end,
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
        { "spell catalogue", function()
            for _, source in ipairs(Data.SOURCES) do
                local list = Data.BuildSpellList(source.value, nil)
                assert(type(list) == "table", "no list for source " .. source.value)
            end
        end },
        { "grid page refresh after edits", function()
            ThugUI.Window:SelectPage("cooldownviewer")
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

        { "a missing sourceUnit is accepted", function()
            wipe(_G.__auras)
            _G.__auras[9003] = { spellId = 9003 }
            CV:UpdateState()
            assert(CV.icons[Data.CellKey(1, 1)].wanted,
                "a buff with no source field was rejected")
            wipe(_G.__auras)
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
