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
        local a = select(1, ...)
        if key:match("^Get") then
            if key == "GetWidth" or key == "GetHeight" or key == "GetStringWidth"
                or key == "GetStringHeight" or key == "GetFrameLevel" or key == "GetScale" then
                return 100
            end
            if key == "GetPoint" then return "TOPLEFT", nil, "TOPLEFT", 0, 0 end
            if key == "GetChildren" or key == "GetRegions" then return end
            if key == "GetText" then return "" end
            if key == "GetObjectType" then return "Frame" end
            if key == "GetCenter" then return 0, 0 end
        end
        if key == "IsShown" or key == "IsMouseOver" or key == "GetChecked" then return false end
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
function InCombatLockdown() return false end
function UnitAffectingCombat() return false end
function UnitClass() return "Druid", "DRUID" end
function GetCursorPosition() return 500, 500 end
function GetSpecialization() return 4 end
function GetNumSpecializations() return 4 end
function GetSpecializationInfo(i) return 100 + i, "Spec" .. i, "", 12345, "HEALER", 4 end
function GetSpecializationInfoByID(id) return id, "Spec" .. id end
function IsPlayerSpell() return true end
function IsSpellKnownOrOverridesKnown() return true end
function RegisterStateDriver() end
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
}

C_Spell = {
    GetSpellInfo = function(q)
        local id = tonumber(q) or 12345
        return { spellID = id, name = "Spell " .. id, iconID = 999 }
    end,
    GetSpellTexture = function() return 999 end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
    GetSpellCharges = function() return nil end,
}
C_UnitAuras = { GetPlayerAuraBySpellID = function() return nil end }
C_CooldownViewer = {
    GetCooldownViewerCategorySet = function() return { 1, 2, 3 } end,
    GetCooldownViewerCooldownInfo = function(id) return { cooldownID = id, spellID = 1000 + id } end,
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
        { "migration ran", function()
            assert(ThugUI_Config.cv and ThugUI_Config.cv.migrated, "migrated flag not set")
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
