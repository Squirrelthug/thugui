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
        --
        -- Secret start/duration are REFUSED, exactly as the live client refuses
        -- them. This stub used to accept anything, which is why it never caught
        -- ApplySweep handing it a secret startTime in combat -- an uncaught
        -- throw that unwound the whole UpdateState loop and froze every icon it
        -- had not reached. A stub that is more permissive than the game cannot
        -- fail a test the game fails.
        if key == "SetCooldown" and type(a) == "table" then
            if issecretvalue(a1) or issecretvalue(a2) then
                error("bad argument #1 to 'SetCooldown' (Secret values are only "
                    .. "allowed during untainted execution for this argument.)", 2)
            end
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
        -- StatusBar (radial resource ring, task 16). SetValue, SetMinMaxValues
        -- and SetStatusBarColor all carry
        -- SecretArguments = "AllowedWhenTainted" in
        -- SimpleStatusBarAPIDocumentation.lua on the live branch, so -- unlike
        -- SetCooldown above -- the real client accepts a secret here and this
        -- stub must too, or it is more restrictive than the game rather than
        -- less. What each call was handed is recorded, never coerced, so a
        -- secret stored here still throws on arithmetic/comparison exactly as
        -- _G.__SECRET already does (Tests/README.md, "Hazards in the harness
        -- itself") -- that is what proves the module never reads it back.
        if key == "SetRenderMode" and type(a) == "table" then
            a.__renderMode = a1
            return
        end
        if key == "SetStatusBarTexture" and type(a) == "table" then
            a.__statusBarTextureAsset = a1
            return true
        end
        if key == "SetMinMaxValues" and type(a) == "table" then
            a.__minMax = { a1, a2 }
            return
        end
        if key == "SetValue" and type(a) == "table" then
            a.__value = a1
            return
        end
        if key == "SetStatusBarColor" and type(a) == "table" then
            a.__statusBarColor = { a1, a2, a3, a4 }
            return
        end
        -- GetStatusBarTexture must return the SAME object every call -- a
        -- fresh stub frame each time (the generic fallback below does that)
        -- would make a texture's recorded rotation unobservable to a test
        -- that asks for the texture a second time, the way the real managed
        -- texture is a persistent object.
        if key == "GetStatusBarTexture" and type(a) == "table" then
            a.__statusBarTexture = a.__statusBarTexture or setmetatable({}, frameMT)
            return a.__statusBarTexture
        end
        if key == "SetRotation" and type(a) == "table" then
            a.__rotation = a1
            return
        end
        -- 12.1's texture-level radial API. Recorded rather than acted on, like
        -- the StatusBar setters above. Note this stub ALWAYS provides the
        -- method: the guard case that matters is a texture WITHOUT it, and a
        -- test wanting that has to remove it deliberately (see
        -- "no SetRadialProgressBarReverse: no throw, ring still draws").
        -- Blizzard's own UI uses none of this family anywhere, so the harness
        -- is the only place it has ever been exercised outside the player's
        -- client -- treat green here as weaker evidence than usual.
        if key == "SetRadialProgressBarReverse" and type(a) == "table" then
            a.__radialReverse = a1
            return
        end
        if key == "SetRadialProgressBarStartOffset" and type(a) == "table" then
            a.__radialStartOffset = a1
            return
        end
        -- FontStrings are ordinary stub frames, but they're recorded in a flat
        -- list rather than only reachable through whatever built them --
        -- Panel:Section and friends don't stash their return value anywhere,
        -- so a test that wants to read a heading's text back needs some way
        -- to find it that isn't "the caller happened to keep a handle".
        if key == "CreateFontString" and type(a) == "table" then
            local fs = setmetatable({}, frameMT)
            table.insert(_G.__fontStrings, fs)
            return fs
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
            -- Recorded so the category-cell repaint (task 19, DECISIONS.md
            -- §25) is observable: before this, SetTexture fell through to the
            -- generic no-op and no test could tell whether a resolved cache
            -- entry ever reached the drawn cell.
            if key == "SetTexture" then a.__texture = a1 return end
            -- Strata and scale are modelled because the Blizzard-buff tests
            -- assert on WHOSE frame changed. Lifting their viewer instead of
            -- lowering our icon is the taint bug that killed the cooldown
            -- viewer for a whole session -- a test that cannot tell the two
            -- apart cannot catch it coming back.
            if key == "SetFrameStrata" then a.__strata = a1 return end
            if key == "SetScale" then a.__scale = a1 return end
            if key == "GetFrameStrata" then return a.__strata or "MEDIUM" end
            -- Recorded so a checkbox's Refresh() can be proven to have set the
            -- widget to the right state, and so a simulated click can flip the
            -- state before the OnClick handler reads it back -- same order
            -- UICheckButtonTemplate does it in game.
            if key == "SetChecked" then a.__checked = a1 and true or false return end
            -- Recorded so a section heading or a message built by SetText can
            -- be read back by GetText below -- unlike SetPoint et al, nothing
            -- modelled text before this task needed it.
            if key == "SetText" then a.__text = a1 return end
            -- Paired with GetWidth/GetHeight below. SetSize sets both.
            if key == "SetWidth" then a.__width = a1 return end
            if key == "SetHeight" then a.__height = a1 return end
            if key == "SetSize" then a.__width, a.__height = a1, a2 return end
        end
        if key:match("^Get") then
            -- GetWidth/GetHeight report back what SetWidth/SetHeight recorded,
            -- falling back to a nominal 100 for a frame nobody has sized. They
            -- used to return a flat 100 unconditionally, which made SetHeight
            -- unobservable -- a whole class of layout assertion could not be
            -- written, and the scroll-height bug in Window:BuildPage sat behind
            -- it. Tests/README.md, "Hazards in the harness itself".
            if key == "GetWidth" then return a.__width or 100 end
            if key == "GetHeight" then return a.__height or 100 end
            if key == "GetFrameLevel" then return 100 end
            -- Reports back what SetScale recorded. NOT a true parent-chain
            -- product -- a test that needs an effective scale sets it on the
            -- frame it asks about. That is enough for the adopted-buff fit,
            -- whose whole question is the RATIO between two frames' scales.
            if key == "GetScale" or key == "GetEffectiveScale" then
                return a.__scale or 1
            end
            -- Roughly life-sized, so panel height maths means something. A
            -- flat 100 per line made every wrapped note absurdly tall and any
            -- layout-fits check meaningless.
            if key == "GetStringHeight" then return 14 end
            if key == "GetStringWidth" then return 60 end
            if key == "GetPoint" then return "TOPLEFT", nil, "TOPLEFT", 0, 0 end
            if key == "GetChildren" or key == "GetRegions" then return end
            if key == "GetText" then return a.__text or "" end
            if key == "GetObjectType" then return "Frame" end
            if key == "GetCenter" then return 0, 0 end
            -- Models SimpleStatusBarAPIDocumentation.lua's
            -- SecretReturnsForAspect = { BarValue }: if SetValue was handed a
            -- secret, GetValue hands the same secret back rather than a plain
            -- number. Nothing in ResourceRing.lua may call this (task 16), and
            -- this is what would punish it if something did -- comparing or
            -- doing arithmetic on the return throws exactly like the client.
            if key == "GetValue" then return a.__value end
        end
        if key == "IsMouseOver" then return false end
        if key == "GetChecked" then return a.__checked == true end
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

-- Every FontString ever built, so a test can find one by the text it was
-- given without the code under test having to keep a handle for it.
_G.__fontStrings = {}

-- ---------------------------------------------------------------- API stubs
UIParent = NewFrame()
GameTooltip = NewFrame()
ColorPickerFrame = NewFrame()
SettingsPanel = NewFrame()
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
STANDARD_TEXT_FONT = "font"

-- Blizzard's shared confirmation-dialog registry. Not stubbed before this
-- task because nothing in the addon used it -- CooldownViewer.lua's clear-
-- layout confirmation is the first. StaticPopup_Show only needs to record
-- what it was asked to show; nothing here needs an actual dialog frame.
StaticPopupDialogs = {}
YES = "Yes"
NO = "No"
_G.__lastStaticPopup = nil
function StaticPopup_Show(which, text_arg1, text_arg2)
    _G.__lastStaticPopup = { which = which, text_arg1 = text_arg1, text_arg2 = text_arg2 }
    return NewFrame()
end

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
    -- 12.1's radial-fill render mode for a plain StatusBar (task 16). Values
    -- match SimpleStatusBarConstantsDocumentation.lua on the live branch:
    -- Linear = 0, Radial = 1.
    StatusBarRenderMode = { Linear = 0, Radial = 1 },
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
        -- secretTiming models being in combat: the live client hands back a
        -- secret startTime/duration there, and SetCooldown refuses them.
        local secret = state and state.secretTiming
        return {
            isActive = state and state.isActive or false,
            isOnGCD = state and state.isOnGCD or false,
            startTime = secret and _G.__SECRET or -1,
            duration = secret and _G.__SECRET or -1,
            modRate = 1,
        }
    end,
    -- Charge spells, keyed by spell ID. A nil entry means "not a charge
    -- spell", which is what the real API returns for one -- the addon uses the
    -- table's mere presence to decide it is looking at a charge build.
    GetSpellCharges = function(q)
        local id = tonumber(q) or tonumber(tostring(q):match("^Spell (%d+)$") or "")
        return _G.__spellCharges and _G.__spellCharges[id] or nil
    end,
}
_G.__cooldownState = {}
_G.__spellCharges = {}
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
    -- A plain Utility cooldown, unique to one category. This is the Grappling
    -- Hook shape: a multi-charge spell whose charge count our own code cannot
    -- read in combat, so Blizzard's utility viewer has to draw the cell.
    [7] = { cooldownID = 7, spellID = 7000, linkedSpellIDs = {} },
}
_G.__categorySets = {
    Essential   = { 1, 2, 4 },
    Utility     = { 7 },
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
if ThugUI and ThugUI.Window then
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

    -- Task 17. A SCROLLING page can be built from several panels (Cursor Rings
    -- is two columns), and Window:BuildPage used to size the scroll child from
    -- only the first one it created. A taller second column's bottom rows were
    -- then unreachable -- the scrollbar simply stopped short, with no error and
    -- nothing visibly wrong until you went looking for a control that was not
    -- there. Fails against the old `host:SetHeight(math.max(panel:GetHeight(),
    -- ...))`, which ignores every panel but the first.
    do
        local scrolling = nil
        for _, def in ipairs(ThugUI.Window.pages) do
            if def.scroll ~= false and def.host and def.host.__thugPanels
                and #def.host.__thugPanels > 1 then
                scrolling = def
                break
            end
        end

        if not scrolling then
            say("SCROLL FAIL no multi-panel scrolling page found to check")
            failures = failures + 1
        else
            local tallest = 0
            for _, p in ipairs(scrolling.host.__thugPanels) do
                if p:GetHeight() > tallest then tallest = p:GetHeight() end
            end
            local got = scrolling.host:GetHeight()
            if got + 0.5 < tallest then
                say(("SCROLL FAIL %s: host is %dpx but its tallest panel is %dpx")
                    :format(scrolling.id, got, tallest))
                failures = failures + 1
            else
                say(("ok         page %s scrolls to its tallest panel (%dpx)")
                    :format(scrolling.id, tallest))
            end
        end
    end
end

-- Exercise the cooldown viewer engine, which PLAYER_LOGIN would normally start.
if ThugUI.CooldownViewer then
    say("\n-- engine --")
    local CV, Data = ThugUI.CooldownViewer, ThugUI.CooldownViewer.Data

    --- Place a shape and ask the shared auto axes about it, with nothing else
    --- on the grid. Used by the collapse-direction cases further down, which
    --- turn entirely on where the icons sit relative to the anchor.
    local function AxesFor(anchorRow, anchorCol, cells)
        local profile = Data.GetActiveProfile()
        wipe(profile.placements)
        profile.collapseDirection = "auto"
        profile.anchorRow, profile.anchorCol = anchorRow, anchorCol
        for _, rc in ipairs(cells) do
            Data.SetPlacement(profile, rc[1], rc[2], 555, "cooldown")
        end
        return Data.ResolveAutoAxes(profile)
    end

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
        -- Inverted by task 10. This used to assert that each outcome was offered
        -- as its own row, which was real intent and turned out to be impossible:
        -- adoption maps one Blizzard frame per cooldownID, every outcome shares
        -- the base entry's cooldownID, and five rows could only ever draw one
        -- icon. The set entry still has to be here -- that is what the player
        -- actually places.
        { "buff outcomes are no longer offered individually, only the set", function()
            local list = Data.BuildSpellList("buffs", nil)

            local byID = {}
            for _, entry in ipairs(list) do byID[entry.spellID] = true end

            assert(byID[5000], "the set entry itself vanished from the picker")
            local info = Data.GetCooldownInfoForSpell(5000)
            assert(info and #info.linkedSpellIDs > 0, "setup: no linked buffs to check")
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                assert(not byID[linkedID],
                    ("linked buff %d was still offered on its own"):format(linkedID))
            end

            -- Cooldown sources never expanded either, and still must not.
            local essentials = Data.BuildSpellList("essential", nil)
            local essentialIDs = {}
            for _, entry in ipairs(essentials) do essentialIDs[entry.spellID] = true end
            local cdInfo = Data.GetCooldownInfoForSpell(9101)
            if cdInfo and cdInfo.linkedSpellIDs and #cdInfo.linkedSpellIDs > 0 then
                assert(not essentialIDs[cdInfo.linkedSpellIDs[1]],
                    "a cooldown entry's linked spell was offered separately")
            end
        end },

        -- Task 10: the test above asserted the OLD behaviour (linked outcomes
        -- offered as their own rows) and is left in place on purpose -- it now
        -- fails, and that failure is the documented, expected result of
        -- removing the expansion, not a regression. These cases assert the
        -- NEW behaviour: one picker row per entry, no matter how many buffs
        -- it can grant. Nothing is lost by not expanding -- ResolveAura in
        -- Core.lua walks icon.linkedSpellIDs at runtime regardless of what the
        -- picker offered, and that path is covered separately below.
        { "an entry with linked spells yields one picker row, not one per linked id", function()
            Data.InvalidateCooldownInfoCache()
            local list = Data.BuildSpellList("buffs", nil)

            local byID, baseCount = {}, 0
            for _, entry in ipairs(list) do
                byID[entry.spellID] = true
                if entry.spellID == 5000 then baseCount = baseCount + 1 end
            end

            assert(byID[5000], "the base entry itself vanished from the picker")
            assert(baseCount == 1,
                ("base entry 5000 appeared %d times in the picker, expected 1"):format(baseCount))

            local info = Data.GetCooldownInfoForSpell(5000)
            assert(info and #info.linkedSpellIDs >= 2, "setup: need 2+ linked ids to prove this")
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                assert(not byID[linkedID],
                    ("linked buff %d was still offered as its own row"):format(linkedID))
            end
        end },
        { "the all source likewise does not gain linked ids", function()
            Data.InvalidateCooldownInfoCache()
            local byID = {}
            for _, entry in ipairs(Data.BuildSpellList("all", nil)) do
                byID[entry.spellID] = true
            end

            assert(byID[5000], "the base entry vanished from the 'all' source")
            local info = Data.GetCooldownInfoForSpell(5000)
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                assert(not byID[linkedID],
                    ("'all' offered linked buff %d as its own row"):format(linkedID))
            end
        end },
        -- Cooldown sources never expanded their linked spells even before this
        -- change (expansion only ever ran for "buffs" and "all"), so this is a
        -- guard against a future change reintroducing it there, not proof that
        -- anything here moved.
        { "essential, utility and spellbook stay unaffected by the picker change", function()
            Data.InvalidateCooldownInfoCache()
            for _, source in ipairs({ "essential", "utility", "spellbook" }) do
                local byID = {}
                for _, entry in ipairs(Data.BuildSpellList(source, nil)) do
                    byID[entry.spellID] = true
                end
                for _, linkedID in ipairs({ 5101, 5102, 5103, 5104 }) do
                    assert(not byID[linkedID],
                        ("%s source offered linked buff %d as its own row"):format(source, linkedID))
                end
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
        -- 12.1 made cooldownInfo.spellID nilable. An entry with no base spell
        -- but an override, and no linked spells to fall back on, used to leave a
        -- nil at index 1 of the id list -- ipairs stopped there and the entry was
        -- never indexed, so the placement resolved to no Cooldown Manager entry
        -- and the cell silently stayed empty. This is the trinket/potion shape.
        { "an entry with no base spell is still indexed by its override", function()
            _G.__cooldownEntries[98] = {
                cooldownID = 98, spellID = nil, overrideSpellID = 9801,
                linkedSpellIDs = {},
            }
            _G.__categorySets.Essential = { 1, 2, 4, 98 }
            Data.InvalidateCooldownInfoCache()

            local info = Data.GetCooldownInfoForSpell(9801)
            assert(info and info.cooldownID == 98,
                "entry with nil spellID was not indexed under its overrideSpellID")

            _G.__cooldownEntries[98] = nil
            _G.__categorySets.Essential = { 1, 2, 4 }
            Data.InvalidateCooldownInfoCache()
        end },
        { "grid page refresh after edits", function()
            ThugUI.Window:SelectPage("cooldownviewer")
        end },

        -- Task 11: a spell can legitimately be placed twice under different
        -- modes -- Roll the Bones as an Essential cooldown AND as a tracked
        -- buff -- and greying a picker row by spell ID alone made the OTHER
        -- placement's row read as "already placed" too, which is misleading:
        -- it is a genuinely different thing to place. Spell 5000 in the stub
        -- data is exactly this shape: cooldownID 4 lists it under Essential,
        -- cooldownID 5 lists it under TrackedBar (collected into "buffs").
        { "IsSpellPlaced with no mode argument behaves exactly as before", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            Data.SetPlacement(profile, 1, 1, 7777, "aura")

            assert(Data.IsSpellPlaced(profile, 7777),
                "an aura-mode placement was not found with no mode argument")
            assert(Data.IsSpellPlaced(profile, 7777, nil) == Data.IsSpellPlaced(profile, 7777),
                "passing nil explicitly changed the result from omitting it")
            assert(not Data.IsSpellPlaced(profile, 6666),
                "an unplaced spell ID reported placed")

            wipe(profile.placements)
        end },

        { "a cooldown-mode placement greys under essential, not under buffs", function()
            local Page = ThugUI.CooldownViewer.Page
            local profile = Data.GetActiveProfile()
            local restoreSource = Page.pickerSource

            wipe(profile.placements)
            Data.SetPlacement(profile, 1, 1, 5000, "cooldown")

            local function RowFor(source)
                Page.pickerSource = source
                Page:RefreshPicker()
                for _, r in ipairs(Page.pickerRows) do
                    if r.spellID == 5000 and r:IsShown() then return r end
                end
            end

            local essentialRow = RowFor("essential")
            assert(essentialRow, "setup: spell 5000 not offered under essential")
            assert(essentialRow.label:GetText():find("808080", 1, true),
                "a cooldown-mode placement did not grey its row under essential")

            local buffsRow = RowFor("buffs")
            assert(buffsRow, "setup: spell 5000 not offered under buffs")
            assert(not buffsRow.label:GetText():find("808080", 1, true),
                "a cooldown-mode placement wrongly greyed its row under buffs")

            wipe(profile.placements)
            Page.pickerSource = restoreSource
            Page:RefreshPicker()
        end },

        { "an aura-mode placement greys under buffs, not under essential", function()
            local Page = ThugUI.CooldownViewer.Page
            local profile = Data.GetActiveProfile()
            local restoreSource = Page.pickerSource

            wipe(profile.placements)
            Data.SetPlacement(profile, 1, 1, 5000, "aura")

            local function RowFor(source)
                Page.pickerSource = source
                Page:RefreshPicker()
                for _, r in ipairs(Page.pickerRows) do
                    if r.spellID == 5000 and r:IsShown() then return r end
                end
            end

            local buffsRow = RowFor("buffs")
            assert(buffsRow, "setup: spell 5000 not offered under buffs")
            assert(buffsRow.label:GetText():find("808080", 1, true),
                "an aura-mode placement did not grey its row under buffs")

            local essentialRow = RowFor("essential")
            assert(essentialRow, "setup: spell 5000 not offered under essential")
            assert(not essentialRow.label:GetText():find("808080", 1, true),
                "an aura-mode placement wrongly greyed its row under essential")

            wipe(profile.placements)
            Page.pickerSource = restoreSource
            Page:RefreshPicker()
        end },

        { "the all source greys on either mode", function()
            local Page = ThugUI.CooldownViewer.Page
            local profile = Data.GetActiveProfile()
            local restoreSource = Page.pickerSource

            local function IsGreyed(mode)
                wipe(profile.placements)
                Data.SetPlacement(profile, 1, 1, 5000, mode)
                Page.pickerSource = "all"
                Page:RefreshPicker()
                local row
                for _, r in ipairs(Page.pickerRows) do
                    if r.spellID == 5000 and r:IsShown() then row = r end
                end
                assert(row, "setup: spell 5000 not offered under all")
                return row.label:GetText():find("808080", 1, true) ~= nil
            end

            assert(IsGreyed("cooldown"), "a cooldown-mode placement did not grey its row under 'all'")
            assert(IsGreyed("aura"), "an aura-mode placement did not grey its row under 'all'")

            wipe(profile.placements)
            Page.pickerSource = restoreSource
            Page:RefreshPicker()
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

        -- Regression: BugGrabber session 150, 36 occurrences of
        --   Core.lua:126: bad argument #1 to 'SetCooldown' (Secret values are
        --   only allowed during untainted execution for this argument.)
        -- ApplySweep handed SetCooldown a secret startTime, the client refused
        -- it, and nothing caught the throw -- so UpdateState unwound and every
        -- icon the pairs() loop had not yet reached kept its previous state.
        -- Charge spells surfaced it because their recharge timer runs
        -- essentially always, so they take this path on nearly every pass.
        { "a secret cooldown start does not throw", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "always")
            CV:Rebuild()
            CV.container.__shown = true

            _G.__cooldownState[777] =
                { isOnGCD = false, isActive = true, secretTiming = true }
            local ok, err = pcall(function() CV:UpdateState() end)
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
            assert(ok, "UpdateState threw on a secret cooldown start: " .. tostring(err))

            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(icon.cooldown.__cooldown == nil,
                "a sweep was drawn from secret timing")
        end },

        { "a secret sweep does not freeze the rest of the grid", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            -- 777 is the icon that threw under the bug; 888 is the bystander.
            -- pairs() order is undefined, which is why the live symptom moved
            -- around between sessions -- so what is asserted is that the
            -- bystander is correct, which only holds if the loop ran to the end.
            Data.SetPlacement(profile, 1, 1, 777, "always")
            Data.SetPlacement(profile, 1, 2, 888, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true

            _G.__cooldownState[777] =
                { isOnGCD = false, isActive = true, secretTiming = true }
            _G.__cooldownState[888] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            assert(CV.icons[Data.CellKey(1, 2)].wanted, "a ready bystander was not shown")

            -- Spend the bystander. Under the bug this update never reached it
            -- and it stayed on screen looking permanently ready.
            _G.__cooldownState[888] = { isOnGCD = false, isActive = true }
            CV:UpdateState()
            assert(not CV.icons[Data.CellKey(1, 2)].wanted,
                "a spent bystander stayed visible -- the loop aborted early")
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
        end },

        { "a charge spell shows while a charge is banked", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            -- isActive is true throughout: a charge spell's recharge timer runs
            -- even with charges banked, which is exactly why readiness cannot
            -- come from it.
            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = 1 }
            CV:UpdateState()
            assert(icon.wanted, "a spell with a charge banked was hidden")
            -- SetText is handed the raw number, so compare as text.
            assert(tostring(icon.count.__text) == "1",
                "charge count read " .. tostring(icon.count.__text))

            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = 0 }
            CV:UpdateState()
            assert(not icon.wanted, "a spell with both charges spent stayed visible")

            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
        end },

        { "unreadable charges fail open rather than hiding", function()
            local icon = CV.icons[Data.CellKey(1, 1)]
            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = _G.__SECRET }
            CV:UpdateState()
            assert(icon.wanted,
                "a charge spell hid itself when its charge count was secret")

            -- Secret maxCharges too: issecretvalue has to be asked before the
            -- `> 1` comparison, because that comparison is what errors on the
            -- very value it is meant to be testing.
            _G.__spellCharges[777] = { maxCharges = _G.__SECRET, currentCharges = _G.__SECRET }
            local ok, err = pcall(function() CV:UpdateState() end)
            assert(ok, "UpdateState threw on a secret maxCharges: " .. tostring(err))
            assert(icon.wanted, "a charge spell hid itself when maxCharges was secret")

            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
        end },

        -- task 15: IsSpellReady's third return (Core.lua) is an alpha that is
        -- always safe to hand to icon:SetAlpha -- 1 in every case except the
        -- fail-open branch, where it is the secret currentCharges itself.
        -- SetAlpha clamps a secret 0/1/2 to invisible/opaque with no
        -- comparison, which is how a spent charge spell hides itself in
        -- combat (DECISIONS.md §20). Every case here resets the shared
        -- _G.__* stub state at the START, not only at the end -- task 14
        -- found that a case which throws unwinds past its own cleanup and
        -- leaves the next case passing for the wrong reason.
        { "task 15: charges readable and zero -- hidden, alpha stays 1", function()
            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = nil
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = 0 }
            CV:UpdateState()
            assert(not icon.wanted, "an icon with zero readable charges stayed wanted")
            -- SetShown has already done the hiding here, so alpha must stay
            -- opaque -- IsSpellReady returns 1 on the readable path.
            assert(icon.__alpha == 1,
                "a readable zero charge count should not touch alpha, got "
                .. tostring(icon.__alpha))

            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
        end },

        { "task 15: charges readable and non-zero -- shown, alpha stays 1", function()
            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = nil
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = 2 }
            CV:UpdateState()
            assert(icon.wanted, "an icon with charges banked was hidden")
            assert(icon.__alpha == 1,
                "a readable non-zero charge count should not touch alpha, got "
                .. tostring(icon.__alpha))

            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
        end },

        -- The load-bearing case: this is the whole point of the design. The
        -- icon stays "wanted" (fail-open, space reserved -- alpha zero is not
        -- hidden, DECISIONS.md §20's accepted cost) but alpha is handed the
        -- SECRET value itself, unread and uncompared.
        { "task 15: charges secret -- icon shown, space reserved, alpha IS the secret", function()
            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = nil
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = _G.__SECRET }
            local ok, err = pcall(function() CV:UpdateState() end)
            assert(ok, "UpdateState threw on a secret currentCharges: " .. tostring(err))

            assert(icon.wanted,
                "a charge spell hid its cell when charges went secret -- "
                .. "space must stay reserved (DECISIONS.md §20's accepted cost)")
            assert(icon.__alpha == _G.__SECRET,
                "alpha was not the secret currentCharges value itself, got "
                .. tostring(icon.__alpha))

            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
        end },

        -- The pooling hazard the task calls out as the likely regression: an
        -- icon left at the secret alpha by one spell must not carry it to
        -- whatever spell reuses the pooled frame next.
        { "task 15: pooling -- a spent-charge icon reused for a plain spell is alpha 1 again", function()
            _G.__spellCharges[777] = nil
            _G.__spellCharges[888] = nil
            _G.__cooldownState[777] = nil
            _G.__cooldownState[888] = nil
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            -- Drive it to the secret-charge alpha first.
            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = _G.__SECRET }
            CV:UpdateState()
            assert(icon.__alpha == _G.__SECRET,
                "setup failed: icon was not left at the secret alpha")

            -- Re-drive the SAME cell as an ordinary, non-charge spell. Icons
            -- are pooled by acquisition order (Core.lua AcquireIcon), and with
            -- exactly one placement this must land back on the same frame --
            -- confirmed below rather than assumed.
            _G.__spellCharges[777] = nil
            Data.SetPlacement(profile, 1, 1, 888, "cooldown")
            CV:Rebuild()
            local icon2 = CV.icons[Data.CellKey(1, 1)]
            assert(icon2 == icon, "test setup broken: cell 1,1 did not reuse the pooled icon")

            _G.__cooldownState[888] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            assert(icon.__alpha == 1,
                "a pooled icon carried a previous occupant's secret alpha, got "
                .. tostring(icon.__alpha))

            _G.__spellCharges[777] = nil
            _G.__spellCharges[888] = nil
            _G.__cooldownState[777] = nil
            _G.__cooldownState[888] = nil
        end },

        { "task 15: recharging mode does not apply the alpha, even for a charge spell", function()
            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = nil
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "recharging")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            _G.__spellCharges[777] = { maxCharges = 2, currentCharges = _G.__SECRET }
            local ok, err = pcall(function() CV:UpdateState() end)
            assert(ok, "UpdateState threw in recharging mode with secret charges: "
                .. tostring(err))
            -- Not an oversight: 1 - currentCharges is arithmetic on a secret
            -- and is refused, so recharging mode keeps the old fail-open
            -- behaviour and alpha is left untouched.
            assert(icon.__alpha == 1,
                "recharging mode changed alpha for a charge spell, got "
                .. tostring(icon.__alpha))

            _G.__spellCharges[777] = nil
            _G.__cooldownState[777] = nil
        end },

        { "task 15: a spell with no charge mechanic never has its alpha touched", function()
            _G.__spellCharges[888] = nil
            _G.__cooldownState[888] = nil
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 888, "cooldown")
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            -- No charge entry at all: GetSpellCharges returns nil for a plain
            -- cooldown, exactly as the real API does for a spell with no
            -- charge mechanic.
            _G.__cooldownState[888] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            assert(icon.wanted, "a ready plain spell was hidden")
            assert(icon.__alpha == 1,
                "a non-charge spell's alpha was touched, got " .. tostring(icon.__alpha))

            _G.__cooldownState[888] = { isOnGCD = false, isActive = true }
            CV:UpdateState()
            assert(not icon.wanted, "a spent plain spell stayed visible")
            assert(icon.__alpha == 1,
                "a non-charge spell's alpha was touched when spent, got "
                .. tostring(icon.__alpha))

            _G.__cooldownState[888] = nil
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

        -- Regression, and the reason both halves are asserted together: the
        -- layout decides which side of the pointer the shape sits on, and the
        -- collapse packs it "towards the cursor". They used to disagree at the
        -- exact midpoint -- `>=` when placing, strict `>` when collapsing -- so
        -- an anchor at row 5 put the shape ABOVE the pointer and then packed it
        -- upwards, away from it. Whichever way the boundary is decided, these
        -- two must decide it the same way.
        -- The real rule: intersection R is the bottom edge of cell row R, so a
        -- cell at or before the anchor is above the cursor. Packing towards the
        -- cursor is therefore the opposite of where the bulk lies.
        { "auto packs towards the cursor from where the icons actually are", function()
            -- The player's resto shape: rows 4-5 against an anchor at row 5, so
            -- entirely ABOVE the cursor and it must close downwards.
            local _, down = AxesFor(5, 3, { {4,5},{4,6},{4,7},{5,5},{5,6},{5,7},{5,9} })
            assert(down, "a shape above the cursor did not pack down towards it")

            -- Same anchor, shape moved below it. The grid-midpoint rule cannot
            -- tell these apart; that was the bug.
            local _, down2 = AxesFor(5, 3, { {6,5},{7,5},{8,5} })
            assert(not down2, "a shape below the cursor did not pack up towards it")
        end },

        -- The case the old midpoint rule got wrong even after the >= fix: an
        -- anchor low on the grid with the shape lower still.
        { "an anchor past the midpoint still follows the icons", function()
            local _, down = AxesFor(7, 3, { {8,4},{9,4} })
            assert(not down,
                "anchor row 7 with icons at rows 8-9 must pack UP towards the "
                .. "cursor, not down because the anchor is past grid centre")
        end },

        { "the horizontal axis follows the icons too", function()
            local right = AxesFor(5, 3, { {4,5},{4,6},{4,7} })
            assert(not right, "a shape right of the cursor did not pack left")

            local right2 = AxesFor(5, 8, { {4,2},{4,3} })
            assert(right2, "a shape left of the cursor did not pack right")
        end },

        -- Tie-break. A shape straddling the anchor evenly has no bulk to speak
        -- of, and an empty grid has nothing at all, so both fall back to the
        -- grid-midpoint test rather than inventing an answer.
        { "an even straddle falls back to the anchor's place on the grid", function()
            local _, down = AxesFor(5, 3, { {5,4},{6,4} })
            assert(down == ((5) >= Data.GRID_ROWS / 2),
                "an evenly straddling shape did not fall back to the midpoint")

            local _, emptyDown = AxesFor(5, 3, {})
            assert(emptyDown == ((5) >= Data.GRID_ROWS / 2),
                "an empty grid did not fall back to the midpoint")
        end },

        -- The layout and the collapse must never derive this separately again:
        -- CV:FollowCursor's gap nudge and the collapse both read ResolveAutoAxes.
        { "the layout nudge and the collapse share one source", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse, profile.collapseDirection = "columns", "auto"
            profile.anchorRow, profile.anchorCol = 5, 3
            Data.SetPlacement(profile, 4, 6, 555, "cooldown")

            local autoRight, autoDown = Data.ResolveAutoAxes(profile)
            local axesRight, axesDown = Data.ResolveCollapseAxes(profile)
            assert(autoRight == axesRight and autoDown == axesDown,
                "the collapse no longer agrees with the shared auto axes")
            assert(Data.ResolveCollapseDirection(profile)
                    == (autoDown and "down" or "up"),
                "ResolveCollapseDirection disagreed with ResolveCollapseAxes")
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

        -- Now specifically the TIE-BREAK path: placements are wiped, so there
        -- is no bulk to read and the anchor's place on the grid is all that is
        -- left to go on. With icons present the rule is the one above, which is
        -- where the real behaviour lives.
        { "auto direction follows the anchor", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapseDirection = "auto"
            profile.anchorCol = 0
            assert(Data.ResolveCollapseDirection(profile) == "left", "anchor 0 should pack left")
            profile.anchorCol = 10
            assert(Data.ResolveCollapseDirection(profile) == "right", "anchor 10 should pack right")
            -- CHANGED, deliberately. This used to assert "left", recording the
            -- arbitrary tie-break of a strict `>`. Dead centre is not actually
            -- ambiguous: CV:FollowCursor uses `>=` to decide where to put the
            -- shape, so at the midpoint it nudges the shape LEFT of the pointer,
            -- and packing towards the pointer from there is RIGHT. The old
            -- answer was the layout's opposite. See DECISIONS.md 18.
            profile.anchorCol = 5
            assert(Data.ResolveCollapseDirection(profile) == "right",
                "dead centre should pack towards the cursor, matching the layout")
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
                -- The BASE entry, not a linked one: task 10 stopped offering
                -- linked IDs at all, so their presence proves nothing now. What
                -- this case is actually about is the setting, and the base ID
                -- proves that just as well.
                assert(inAll[5000],
                    ("the base entry was missing from 'all' with the setting %s"):format(state))
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

        -- The checkbox moved to the guide panel and must not leave a second
        -- copy behind on the main window.
        { "the misc panel drops the Blizzard-buffs checkbox but keeps proc glow", function()
            local Page = ThugUI.CooldownViewer.Page
            local misc
            for _, panel in ipairs(Page.panels or {}) do
                -- The misc panel is the one built 260 wide (BuildInspector's
                -- "This layout" band) -- the only panel at that width.
                if panel.width == 260 then misc = panel end
            end
            assert(misc, "could not find the misc panel")

            -- Panel:Register only keeps widgets that carry a Refresh -- Section,
            -- Label, Button and Gap do not, so a checkbox is the only thing that
            -- would show up here. One entry means one checkbox is left, where
            -- there used to be two.
            assert(#misc.widgets == 1,
                ("misc panel has %d registered widgets, expected exactly 1 (proc glow)")
                :format(#misc.widgets))

            local profile = Data.GetActiveProfile()
            local restore = profile.showProcGlow
            profile.showProcGlow = true
            misc.widgets[1]:SetChecked(false)
            misc.widgets[1]:GetScript("OnClick")(misc.widgets[1])
            assert(profile.showProcGlow == false,
                "the one remaining checkbox did not drive showProcGlow")
            profile.showProcGlow = restore
        end },

        -- Task 09: the red [WORKAROUND] link is now set off from "This
        -- layout"'s controls above it by a real section heading, matching
        -- "This layout"'s own style, rather than a plain Label.
        { "the misc panel has an Enable Buffs section heading", function()
            local found = false
            for _, fs in ipairs(_G.__fontStrings) do
                if fs.__text == "Enable Buffs" then found = true break end
            end
            assert(found, "no 'Enable Buffs' section heading was built")
        end },

        -- Namespaced key (a shared Blizzard table other addons also populate),
        -- and the two fields that make a destructive confirmation safe: it
        -- cannot time out into either answer, and Escape has to mean no.
        { "the clear-layout confirmation is registered, namespaced and safe", function()
            local dialog = StaticPopupDialogs["THUGUI_CV_CLEAR_LAYOUT"]
            assert(dialog, "THUGUI_CV_CLEAR_LAYOUT was not registered")
            assert(dialog.timeout == 0, "clear-layout popup can time out")
            assert(dialog.hideOnEscape == true, "clear-layout popup does not close on Escape")
        end },

        -- The case that matters: a single click on the button must not
        -- destroy the layout by itself -- only accepting the confirmation may.
        { "clicking Clear this layout shows a confirmation instead of wiping; only OnAccept wipes", function()
            local Page = ThugUI.CooldownViewer.Page
            assert(Page.clearLayoutBtn, "the Clear this layout button was not exposed for the test")

            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            Data.SetPlacement(profile, 1, 1, 999, "cooldown")
            assert(next(profile.placements), "setup: nothing placed to clear")

            _G.__lastStaticPopup = nil
            Page.clearLayoutBtn:GetScript("OnClick")(Page.clearLayoutBtn)
            assert(next(profile.placements), "the click wiped the layout without confirmation")
            assert(_G.__lastStaticPopup and _G.__lastStaticPopup.which == "THUGUI_CV_CLEAR_LAYOUT",
                "the click did not show the clear-layout confirmation")

            StaticPopupDialogs["THUGUI_CV_CLEAR_LAYOUT"].OnAccept()
            assert(not next(profile.placements), "OnAccept did not clear the layout")
        end },

        -- The empty-picker message used to name a checkbox that lived on this
        -- page; task 08 moved it to the guide panel, so the old wording would
        -- have sent the player hunting for a control that is no longer here.
        { "the buffs-off picker message points at the red workaround link", function()
            local Page = ThugUI.CooldownViewer.Page
            local restoreSetting = ThugUI_Config.cvUseBlizzardBuffs
            local restoreSource = Page.pickerSource

            ThugUI_Config.cvUseBlizzardBuffs = false
            Page.pickerSource = "buffs"
            Page:RefreshPicker()

            local text = Page.pickerEmpty.__text or ""
            assert(text:find("WORKAROUND", 1, true),
                "the empty-picker message no longer points at the workaround")
            assert(text:find("|cff%x%x%x%x%x%x"),
                "the empty-picker message has no colour escape for the link")

            ThugUI_Config.cvUseBlizzardBuffs = restoreSetting
            Page.pickerSource = restoreSource
            Page:RefreshPicker()
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

        -- The checkbox moved out of the main window and into the guide panel.
        -- nil means ON -- the same polarity mistake that emptied the picker
        -- once already (see the buff-category tests above) would also leave
        -- this box unticked for every player who never touched the setting.
        { "the guide's checkbox mirrors cvUseBlizzardBuffs, and nil means on", function()
            local BuffGuide = ThugUI.CooldownViewer.BuffGuide
            BuffGuide:Ensure()
            local cb = BuffGuide.blizzBuffsCB
            assert(cb, "the guide did not expose its Blizzard-buffs checkbox")

            local restore = ThugUI_Config.cvUseBlizzardBuffs

            ThugUI_Config.cvUseBlizzardBuffs = nil
            cb:Refresh()
            assert(cb:GetChecked(), "nil should read as ticked (on)")

            ThugUI_Config.cvUseBlizzardBuffs = true
            cb:Refresh()
            assert(cb:GetChecked(), "true should read as ticked")

            ThugUI_Config.cvUseBlizzardBuffs = false
            cb:Refresh()
            assert(not cb:GetChecked(), "false should read as unticked")

            ThugUI_Config.cvUseBlizzardBuffs = restore
            cb:Refresh()
        end },

        -- The click handler routes through Page:SetUseBlizzardBuffs rather than
        -- writing the config and calling Apply()/RefreshPicker() itself -- this
        -- proves that route actually reaches the picker, not just the config
        -- table.
        { "toggling the guide's checkbox writes the setting and the picker follows", function()
            local BuffGuide = ThugUI.CooldownViewer.BuffGuide
            BuffGuide:Ensure()
            local cb = BuffGuide.blizzBuffsCB
            local restore = ThugUI_Config.cvUseBlizzardBuffs

            ThugUI_Config.cvUseBlizzardBuffs = true
            Data.InvalidateCooldownInfoCache()
            assert(#Data.BuildSpellList("buffs", nil) > 0,
                "setup: the buffs source was already empty")

            -- UICheckButtonTemplate flips its own checked state on a click
            -- before running OnClick, which is what the stub's SetChecked/
            -- GetChecked pairing models.
            cb:SetChecked(false)
            cb:GetScript("OnClick")(cb)

            assert(ThugUI_Config.cvUseBlizzardBuffs == false,
                "the click did not write cvUseBlizzardBuffs")
            assert(#Data.BuildSpellList("buffs", nil) == 0,
                "the picker still offered tracked buffs after the workaround was switched off")

            ThugUI_Config.cvUseBlizzardBuffs = restore
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

        -- The clickToEdit/advButton step used to also tell the player to set
        -- Always/In Combat; that instruction now belongs to the visibility
        -- step alone. Regression: a step that says it twice is confusing, not
        -- redundant-safe, because the two visibility screenshots point at
        -- different frames.
        { "the Always/In Combat visibility instruction appears in exactly one step", function()
            local BuffGuide = ThugUI.CooldownViewer.BuffGuide
            local matches = 0
            for _, step in ipairs(BuffGuide.STEPS) do
                if step.text:find("Always") and step.text:find("In Combat") then
                    matches = matches + 1
                end
            end
            assert(matches == 1,
                ("Always/In Combat wording appeared in %d steps, expected exactly 1")
                :format(matches))
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
if ThugUI.ResourceRing then
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

        -- Replaces "arc matches the resource fraction", which asserted the
        -- Cooldown path's seed-and-Pause arithmetic. That path was deleted on
        -- 2026-08-13 (DECISIONS.md §27) and there is no fraction computed
        -- anywhere any more -- the engine derives the fill from the raw pair.
        -- So the equivalent assertion is that both values arrive unmodified.
        { "the resource level reaches the bar unmodified", function()
            for _, level in ipairs({ 0, 25, 50, 100 }) do
                _G.__power, _G.__powerMax = level, 100
                RR:Update()
                assert(RR.frame.__value == level,
                    "level " .. level .. " did not reach SetValue, got "
                        .. tostring(RR.frame.__value))
                assert(RR.frame.__minMax and RR.frame.__minMax[2] == 100,
                    "maximum did not reach SetMinMaxValues for level " .. level)
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

        -- The radial StatusBar is now the ONLY implementation. Three cases
        -- that used to live here asserted the removed Cooldown path and the
        -- `resourceRingRadialBar` setting that chose between the two, and were
        -- deleted rather than rewritten on 2026-08-13 -- there was nothing
        -- left for them to be true about. Recorded in Tests/README.md so the
        -- deletion is visible rather than looking like coverage that drifted:
        --   "setting off keeps the Cooldown implementation"
        --   "flipping the setting swaps frame type without reusing the old one"
        --   "radial setting on but StatusBarRenderMode absent falls back to Cooldown"
        -- The third is replaced below by the no-fallback version of itself.

        -- The load-bearing case: the whole reason this implementation exists.
        { "a secret power reaches SetValue without throwing", function()
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            _G.__power = _G.__SECRET
            _G.__powerMax = 100

            local ok, err = pcall(function() RR:Update() end)

            assert(ok, "Update threw on a secret power value: " .. tostring(err))
            assert(RR.frame.__value == _G.__SECRET, "secret power did not reach SetValue")
            assert(RR.frame:IsShown(), "ring did not show with a secret power value")

            _G.__power = 50
        end },

        -- Replaces the old "falls back to Cooldown" case. There is no fallback
        -- any more, so the contract changed: no ring, no error.
        { "StatusBarRenderMode absent: no ring, and no throw", function()
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            -- Force a fresh capability check -- a working frame is already
            -- cached this session and the gate only runs on first creation.
            RR.frame, RR.radialUnsupported = nil, nil
            local realMode = Enum.StatusBarRenderMode
            Enum.StatusBarRenderMode = nil
            _G.__power, _G.__powerMax = 50, 100

            local ok, err = pcall(function() RR:Update() end)
            Enum.StatusBarRenderMode = realMode

            assert(ok, "Update threw with StatusBarRenderMode absent: " .. tostring(err))
            assert(RR.frame == nil, "a ring frame was kept despite no radial support")
            assert(RR.radialUnsupported, "the capability miss was not cached")

            -- Undo the cache so later cases see a client that does have it.
            RR.radialUnsupported = nil
        end },

        { "a secret maximum skips the <= 0 comparison", function()
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            _G.__power = 50
            _G.__powerMax = _G.__SECRET

            local ok, err = pcall(function() RR:Update() end)

            assert(ok, "Update threw comparing a secret maximum: " .. tostring(err))
            assert(RR.frame.__minMax and RR.frame.__minMax[2] == _G.__SECRET,
                "secret maximum did not reach SetMinMaxValues")
            assert(RR.frame:IsShown(),
                "ring hid on a secret maximum instead of drawing")

            _G.__powerMax = 100
        end },

        { "colour still follows the power token", function()
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            ThugUI_Config.resourceRingColorMode = "power"
            _G.__power, _G.__powerMax = 50, 100
            _G.__powerToken, _G.__form = "RAGE", 0
            RR.lastPowerToken = nil

            RR:Update()

            local expected = PowerBarColor.RAGE
            local color = RR.frame.__statusBarColor
            assert(color, "ring never called SetStatusBarColor")
            assert(math.abs(color[1] - expected.r) < 0.0001
                and math.abs(color[2] - expected.g) < 0.0001
                and math.abs(color[3] - expected.b) < 0.0001,
                "ring colour did not follow the RAGE power token")

            _G.__powerToken, _G.__form = "MANA", 0
        end },

        -- Task 17: clockwise / counter-clockwise drain direction.

        { "drain direction defaults to clockwise", function()
            ThugUI_Config.resourceRingDrainDirection = nil
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            _G.__power, _G.__powerMax = 50, 100
            RR.lastDrainDirection = nil

            RR:Update()

            local tex = RR.frame:GetStatusBarTexture()
            assert(tex.__radialReverse == false,
                "default direction did not set reverse=false, got "
                    .. tostring(tex.__radialReverse))
        end },

        { "counter-clockwise sets the texture's reverse flag", function()
            ThugUI_Config.resourceRingDrainDirection = "counterclockwise"
            RR.lastDrainDirection = nil

            RR:Update()

            local tex = RR.frame:GetStatusBarTexture()
            assert(tex.__radialReverse == true,
                "counterclockwise did not set reverse=true, got "
                    .. tostring(tex.__radialReverse))

            ThugUI_Config.resourceRingDrainDirection = "clockwise"
            RR.lastDrainDirection = nil
            RR:Update()
            assert(tex.__radialReverse == false, "switching back did not clear reverse")
        end },

        -- The most important case here. We are the FIRST consumer of this API
        -- family anywhere -- an exhaustive search of Blizzard's own live 12.1
        -- source found zero uses of any SetRadialProgressBar* method -- and it
        -- is unverified that the texture from GetStatusBarTexture() exposes
        -- them at all. So the absent-method path is the one likely to be taken
        -- on a real client, not the exotic one.
        { "no SetRadialProgressBarReverse: no throw, ring still draws", function()
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            ThugUI_Config.resourceRingDrainDirection = "counterclockwise"
            _G.__power, _G.__powerMax = 50, 100
            RR.lastDrainDirection = nil

            local tex = RR.frame:GetStatusBarTexture()
            -- rawset a false so the frame metatable's method dispatch does not
            -- manufacture one, which is what makes this a genuine absence.
            rawset(tex, "SetRadialProgressBarReverse", false)

            local ok, err = pcall(function() RR:Update() end)

            rawset(tex, "SetRadialProgressBarReverse", nil)

            assert(ok, "Update threw when the reverse method was absent: " .. tostring(err))
            assert(RR.frame:IsShown(), "ring stopped drawing when it could not set direction")

            ThugUI_Config.resourceRingDrainDirection = "clockwise"
            RR.lastDrainDirection = nil
        end },

        -- The start angle. Reported in game on 2026-08-13: the ring started at
        -- 6 o'clock and BOTH drain directions read as backwards. One cause --
        -- Blizzard's own docs for SetRadialProgressBarStartOffset say the
        -- normalized offset is measured "where 0 is at the bottom", so an
        -- untouched radial bar starts at the bottom and clockwise from there
        -- climbs the left side of the ring.

        { "the default start angle is a half turn, putting 12 o'clock at the top", function()
            ThugUI_Config.resourceRingRotation = nil
            ThugUI_Config.showResourceRing = true
            ThugUI_Config.resourceRingVisibility = "always"
            _G.__power, _G.__powerMax = 50, 100

            RR:SyncGeometry()

            local tex = RR.frame:GetStatusBarTexture()
            assert(math.abs((tex.__radialStartOffset or 0) - 0.5) < 0.0001,
                "12 o'clock should be half a turn from Blizzard's bottom start, got "
                    .. tostring(tex.__radialStartOffset))
        end },

        { "start angle follows resourceRingRotation, not castRotation", function()
            -- The old code read castRotation, and at its default of 12
            -- ClockToRadians returned 0 -- so the ring silently kept Blizzard's
            -- bottom start no matter what the player did. Moving the CAST
            -- setting must now do nothing at all here.
            ThugUI_Config.castRotation = 3
            ThugUI_Config.resourceRingRotation = 9

            RR:SyncGeometry()

            local tex = RR.frame:GetStatusBarTexture()
            assert(math.abs((tex.__radialStartOffset or 0) - 0.25) < 0.0001,
                "9 o'clock should be a quarter turn from the bottom, got "
                    .. tostring(tex.__radialStartOffset))

            ThugUI_Config.castRotation = 12
        end },

        { "6 o'clock is Blizzard's zero offset", function()
            ThugUI_Config.resourceRingRotation = 6

            RR:SyncGeometry()

            local tex = RR.frame:GetStatusBarTexture()
            assert(math.abs(tex.__radialStartOffset or -1) < 0.0001,
                "6 o'clock should be offset 0, got " .. tostring(tex.__radialStartOffset))

            ThugUI_Config.resourceRingRotation = nil
        end },

        -- Same shape as the reverse guard above, and for the same reason: the
        -- absent-method path is the likely one on a real client, not the exotic
        -- one. The fallback keeps the old texture-rotation behaviour.
        { "no SetRadialProgressBarStartOffset: falls back to rotation, no throw", function()
            ThugUI_Config.resourceRingRotation = 12

            local tex = RR.frame:GetStatusBarTexture()
            rawset(tex, "SetRadialProgressBarStartOffset", false)
            tex.__rotation = nil

            local ok, err = pcall(function() RR:SyncGeometry() end)

            rawset(tex, "SetRadialProgressBarStartOffset", nil)

            assert(ok, "SyncGeometry threw with no start-offset method: " .. tostring(err))
            assert(math.abs((tex.__rotation or 0) - math.pi) < 0.0001,
                "fallback did not rotate the texture half a turn, got "
                    .. tostring(tex.__rotation))

            ThugUI_Config.resourceRingRotation = nil
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
if ThugUI.CooldownViewer and ThugUI.CooldownViewer.BlizzBuffs then
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

    -- Stands in for UtilityCooldownViewer, where Grappling Hook lives. Cooldown
    -- ID 7 is the stub's plain Utility entry (spell 7000), which is the
    -- shape of an ordinary cooldown rather than a buff.
    local utilityViewer = NewFrame()
    local utilityItem = NewFrame()
    utilityItem.GetCooldownID = function() return 7 end
    utilityItem.GetParent = function() return utilityViewer end
    -- A cooldown item does not hide when the spell is spent -- it sweeps and
    -- dims -- so shown is its resting state, unlike a buff item.
    utilityItem.__shown = true
    utilityViewer.itemFramePool = {
        EnumerateActive = function()
            local i = 0
            return function()
                i = i + 1
                if i == 1 then return utilityItem end
            end
        end,
    }
    _G.UtilityCooldownViewer = utilityViewer

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

        -- The adopted item is anchored to our cell but stays parented to
        -- Blizzard's viewer, so it never inherits profile.scale. These assert
        -- the ON-SCREEN size rather than the raw scale number, because the
        -- former is what the player sees and the latter is only a means to it.
        { "an adopted item matches the cell's on-screen size at scale 1", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local profile = Data.GetActiveProfile()
            profile.scale, profile.iconSize = 1, 32

            BB:Release()
            local icon = PlaceAura(9001)
            icon.__scale = 1        -- the stub does not chain scale from parents
            viewer.__scale = 1
            BB:Refresh()

            local onScreen = item:GetWidth() * item.__scale * viewer:GetEffectiveScale()
            local want = profile.iconSize * icon:GetEffectiveScale()
            assert(math.abs(onScreen - want) < 0.01,
                ("adopted item drew %.2f wide, cell wanted %.2f"):format(onScreen, want))
        end },

        -- The regression. A profile at scale 0.6 drew its adopted buffs 1/0.6
        -- too large while every cooldown icon around them was correct, because
        -- the fit was computed in grid space and applied to a frame that lives
        -- in Blizzard's. Resto is at 0.6; the rogue testbed was at 1, which is
        -- the only reason this survived as long as it did.
        { "a scaled profile does not draw its adopted buff oversized", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local profile = Data.GetActiveProfile()
            profile.scale, profile.iconSize = 0.6, 42

            BB:Release()
            local icon = PlaceAura(9001)
            icon.__scale = 0.6
            viewer.__scale = 1
            BB:Refresh()

            local onScreen = item:GetWidth() * item.__scale * viewer:GetEffectiveScale()
            local want = profile.iconSize * icon:GetEffectiveScale()
            assert(math.abs(onScreen - want) < 0.01,
                ("adopted item drew %.2f wide, cell wanted %.2f"):format(onScreen, want))
        end },

        -- Their viewer carries its own Edit Mode scale, which must be divided
        -- out or it reappears as a size error in our cell.
        { "the viewer's own scale is divided out", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local profile = Data.GetActiveProfile()
            profile.scale, profile.iconSize = 0.6, 42

            BB:Release()
            local icon = PlaceAura(9001)
            icon.__scale = 0.6
            viewer.__scale = 1.4
            BB:Refresh()

            local onScreen = item:GetWidth() * item.__scale * viewer:GetEffectiveScale()
            local want = profile.iconSize * icon:GetEffectiveScale()
            assert(math.abs(onScreen - want) < 0.01,
                ("adopted item drew %.2f wide, cell wanted %.2f"):format(onScreen, want))
            viewer.__scale = 1
        end },

        -- An item measured before Blizzard has laid it out reports width 0.
        -- That answer used to be cached for the life of the item, and SetScale
        -- was then never called at all -- leaving Blizzard's native size in a
        -- cell sized for ours, which looks exactly like a scaling bug.
        { "a width of zero is retried, not cached forever", function()
            ThugUI_Config.cvUseBlizzardBuffs = true
            local profile = Data.GetActiveProfile()
            profile.scale, profile.iconSize = 0.6, 42

            BB:Release()
            local realGetWidth = item.GetWidth
            item.GetWidth = function() return 0 end

            local icon = PlaceAura(9001)
            icon.__scale = 0.6
            viewer.__scale = 1
            BB:Refresh()
            assert(item.__scale == 1,
                "an unmeasurable item was scaled off a bogus width")

            -- Their layout has run by the next pass. The item must now fit.
            item.GetWidth = realGetWidth
            BB:Refresh()

            local onScreen = item:GetWidth() * item.__scale * viewer:GetEffectiveScale()
            local want = profile.iconSize * icon:GetEffectiveScale()
            assert(math.abs(onScreen - want) < 0.01,
                ("a retried item drew %.2f wide, cell wanted %.2f"):format(onScreen, want))

            profile.scale, profile.iconSize = 1, 32
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

        -- Adoption beyond buffs. `always` mode is the remaining non-aura case:
        -- the radial sweep IS the readiness signal there, and SetCooldown
        -- refuses the secret startTime combat hands us, so the icon would draw
        -- and never sweep. Blizzard's untainted viewer draws that cell instead.
        --
        -- A multi-charge spell in `cooldown` mode used to be adopted here too,
        -- and the case asserting that was DELETED in task 15 rather than
        -- rewritten -- the behaviour it asserted was deliberately removed, so
        -- there was nothing left for it to be true about. DECISIONS.md §20
        -- measured that SetAlpha accepts a secret, so charge spells hide
        -- themselves now and are ours to draw. The replacement assertion is
        -- "task 15: a multi-charge spell in cooldown mode is NOT adopted",
        -- below in the task 15 section.
        --
        -- The cell must survive out of combat too. A cooldown item sweeps and
        -- dims rather than hiding, so the buff-shaped fallback ("is the aura
        -- up") answers no forever and would collapse the cell at rest --
        -- exactly when the player is looking at their layout. This case used to
        -- inherit its setup from the deleted one above; it builds its own now.
        { "an adopted always-mode cell is kept out of combat", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            -- 7000 is cooldownID 7 in the stub data, which utilityItem carries.
            Data.SetPlacement(profile, 1, 1, 7000, "always")
            Data.InvalidateCooldownInfoCache()
            BB:ResetChargeCache()
            CV:Rebuild()
            CV.container.__shown = true

            BB:Refresh()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(BB:AdoptedItem(icon) == utilityItem,
                "an always-mode cell was not adopted from the utility viewer")

            _G.__inCombat = false
            wipe(_G.__auras)
            ItemShown(false)
            CV:UpdateState()
            assert(icon.wanted, "an adopted always-mode cell collapsed out of combat")
            ItemShown(true)
        end },

        { "an ordinary single-charge cooldown is left to us", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            Data.SetPlacement(profile, 1, 1, 7000, "cooldown")
            Data.InvalidateCooldownInfoCache()
            BB:ResetChargeCache()
            -- No charge entry at all: GetSpellCharges returns nil, which is what
            -- the real API does for a spell with no charge mechanic.
            _G.__spellCharges[7000] = nil
            CV:Rebuild()
            CV.container.__shown = true

            BB:Refresh()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(BB:AdoptedItem(icon) == nil,
                "a plain cooldown was adopted -- isActive is readable in combat, "
                .. "so our own rendering is already correct for it")
        end },

        -- Proc mode's whole point is "show only while the proc is up", and
        -- Blizzard's item knows nothing about that. Adopting one would leave it
        -- on screen permanently and lose the only behaviour the mode has.
        { "a charge spell in proc mode is not adopted", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            Data.SetPlacement(profile, 1, 1, 7000, "proc")
            Data.InvalidateCooldownInfoCache()
            BB:ResetChargeCache()
            _G.__spellCharges[7000] = { maxCharges = 2, currentCharges = 2 }
            CV:Rebuild()
            CV.container.__shown = true

            BB:Refresh()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(BB:AdoptedItem(icon) == nil, "a proc-mode icon was adopted")
        end },

        { "an always-mode icon is adopted so it gets a real sweep", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            Data.SetPlacement(profile, 1, 1, 7000, "always")
            Data.InvalidateCooldownInfoCache()
            BB:ResetChargeCache()
            _G.__spellCharges[7000] = nil   -- not a charge spell; mode alone decides
            CV:Rebuild()
            CV.container.__shown = true

            BB:Refresh()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(BB:AdoptedItem(icon) == utilityItem,
                "an always-mode icon was not adopted, so its sweep stays broken "
                .. "in combat")
        end },

        -- A secret maxCharges must not be cached. Caching it would latch a
        -- wrong answer for the session, which is the mistake FitItem's
        -- baseWidth already made once with a falsy measurement.
        { "an unreadable charge count is never cached", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            Data.SetPlacement(profile, 1, 1, 7000, "cooldown")
            Data.InvalidateCooldownInfoCache()
            BB:ResetChargeCache()
            CV:Rebuild()
            CV.container.__shown = true
            local icon = CV.icons[Data.CellKey(1, 1)]

            _G.__spellCharges[7000] = { maxCharges = _G.__SECRET, currentCharges = _G.__SECRET }
            assert(BB:IsChargeSpell(icon) == false,
                "an unreadable charge count was treated as a charge spell")

            -- Now readable: the earlier unreadable pass must not have poisoned it.
            _G.__spellCharges[7000] = { maxCharges = 2, currentCharges = 2 }
            assert(BB:IsChargeSpell(icon) == true,
                "a secret answer was cached and outlived the fight")
            _G.__spellCharges[7000] = nil
        end },

        -- task 15: the behaviour change. BB:ShouldAdopt's charge-spell
        -- fallthrough is gone -- Blizzard no longer draws this cell, because
        -- IsSpellReady's alpha return (Core.lua) now hides a spent charge
        -- itself with no comparison. This is the mirror image of "a charge
        -- spell in cooldown mode is adopted from the utility bar" above,
        -- which asserts the OLD behaviour this task deliberately removes and
        -- is left untouched per tasks/00-AGENT-BRIEF.md's "add cases, never
        -- rewrite one in place" -- see the task 15 report for why both are in
        -- the tree and what that means for the failure count.
        { "task 15: a multi-charge spell in cooldown mode is NOT adopted", function()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 7000, "cooldown")
            Data.InvalidateCooldownInfoCache()
            BB:ResetChargeCache()
            _G.__spellCharges[7000] = { maxCharges = 2, currentCharges = 2 }
            CV:Rebuild()
            CV.container.__shown = true

            BB:Refresh()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(BB:ShouldAdopt(icon) == false,
                "BB:ShouldAdopt still adopts a charge spell in cooldown mode")
            assert(BB:AdoptedItem(icon) == nil,
                "a charge spell in cooldown mode was adopted -- task 15's whole point "
                .. "is that Blizzard no longer draws this cell")

            _G.__spellCharges[7000] = nil
        end },

        { "restore", function()
            ThugUI_Config.cvUseBlizzardBuffs = nil
            _G.BuffIconCooldownViewer = nil
            _G.UtilityCooldownViewer = nil
            wipe(_G.__spellCharges)
            BB:ResetChargeCache()
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

-- Item-backed cells and the "recharging" mode (tasks/14). An icon is
-- item-backed when its Cooldown Manager entry carries `equipSlot` -- 12.1's
-- trinkets, identified by the slot they sit in rather than a spell the player
-- knows. `recharging` is the inverse of `cooldown` mode, for spells and items
-- alike.
if ThugUI.CooldownViewer then
    say("\n-- item cells and recharging mode --")
    local CV = ThugUI.CooldownViewer
    local Data = CV.Data
    local BB = CV.BlizzBuffs

    -- Item cooldowns (GetInventoryItemCooldown). Keyed by equip slot; an
    -- absent entry means "nothing running" -- startTime 0, duration 0, exactly
    -- what the real API reports for a ready item. `secret = true` stands in
    -- for a value the client refuses to hand back, the same shape __SECRET
    -- already models for C_Spell.GetSpellCooldown above.
    _G.__itemCooldowns = {}
    function GetInventoryItemCooldown(unit, equipSlot)
        if unit ~= "player" then return 0, 0, 1 end
        local state = _G.__itemCooldowns[equipSlot]
        if not state then return 0, 0, 1 end
        if state.secret then return _G.__SECRET, _G.__SECRET, 1 end
        return state.startTime or 0, state.duration or 0, 1
    end

    -- Equipped items, keyed by slot. Mirrors Blizzard's own availability test
    -- (CooldownViewerItemData.lua:286, live branch):
    -- ItemLocation:CreateFromEquipmentSlot(equipSlot) then :IsValid(). An
    -- empty slot has nothing valid to create, which is the failure this
    -- models -- the stub must fail the way the game fails, not just accept
    -- anything (DECISIONS.md 19 on the SetCooldown stub that didn't).
    _G.__equipped = {}
    -- Declared with a COLON, exactly as Blizzard declares it, so a caller that
    -- forgets to pass ItemLocation gets the slot in `self` and nil in
    -- `equipSlot` -- and then IsValid() answers false, silently, the way the
    -- game does. The first version of this stub took the slot as its only
    -- argument, which matched the CALLER rather than the game, so the whole
    -- item path shipped broken with eight green tests over it.
    ItemLocation = {}
    function ItemLocation:CreateFromEquipmentSlot(equipSlot)
        return {
            __equipSlot = equipSlot,
            IsValid = function(loc) return _G.__equipped[loc.__equipSlot] == true end,
        }
    end

    -- cooldownID 9 stands for a trinket's on-use spell: an equipSlot entry
    -- with no base aura, unique to this section (8 is used transiently by the
    -- secret-probe section below and cleaned up there). Its name is made not
    -- to resolve in the first case below, standing in for the real shape --
    -- an on-use spell that is not in the spellbook, e.g. Radiant Blessing.
    _G.__cooldownEntries[9] = { cooldownID = 9, spellID = 8500, linkedSpellIDs = {}, equipSlot = 13 }
    _G.__categorySets.Essential = { 1, 2, 4, 9 }

    local function PlaceItem(mode)
        local profile = Data.GetActiveProfile()
        wipe(profile.placements)
        profile.collapse = "none"
        profile.enabled, profile.onlyInCombat = true, false
        Data.SetPlacement(profile, 1, 1, 8500, mode or "cooldown")
        Data.InvalidateCooldownInfoCache()
        CV:Rebuild()
        CV.container.__shown = true
        return CV.icons[Data.CellKey(1, 1)]
    end

    -- Every piece of shared stub state this section touches, put back to a
    -- known baseline at the START of each case rather than only cleaned up at
    -- the end. A case that fails and errors out skips its own trailing
    -- cleanup (Lua `error` unwinds past it), and without this the NEXT case
    -- would silently inherit whatever it left behind -- which already
    -- happened once while writing these, and made an unrelated case look
    -- like it passed for the wrong reason. Independent of run order and of
    -- any earlier case's outcome.
    local function ResetItemStubs()
        _G.__unknownNames["Spell 8500"] = nil
        _G.__equipped[13] = true
        _G.__itemCooldowns[13] = nil
        _G.__cooldownState[8500] = nil
        _G.__cooldownState[777] = nil
        _G.__spellCharges[7000] = nil
    end

    local steps = {
        -- The bug this task started from: Radiant Blessing drew in `always`
        -- mode (adopted on the mode alone) and nowhere in `cooldown` mode,
        -- because cooldown mode reaches IsSpellAvailable(spellName), which
        -- resolves by NAME -- spellbook-scoped, and a trinket's on-use spell
        -- is not in the spellbook.
        { "an item cell is not gated on the spellbook name lookup", function()
            ResetItemStubs()
            _G.__unknownNames["Spell 8500"] = true

            local icon = PlaceItem("cooldown")
            assert(icon.equipSlot == 13, "equipSlot was not captured onto the icon")
            CV:UpdateState()

            assert(icon.wanted,
                "an item cell was gated on a spellbook name lookup that can never resolve")
        end },

        { "an item cell with an empty equipment slot is unavailable", function()
            ResetItemStubs()
            _G.__equipped[13] = false
            local icon = PlaceItem("cooldown")
            CV:UpdateState()
            assert(not icon.wanted, "an empty equipment slot was treated as available")
        end },

        { "an unreadable item cooldown fails visible and does not throw", function()
            ResetItemStubs()
            _G.__itemCooldowns[13] = { secret = true }
            -- Also on cooldown by the SPELL-side stub, so a build that (like
            -- the pre-task code) has no notion of equipSlot at all and falls
            -- through to the ordinary spell path would hide this icon rather
            -- than fail visible -- making this a real discriminator instead of
            -- passing by the accident of an unrelated default.
            _G.__cooldownState[8500] = { isOnGCD = false, isActive = true }
            local icon = PlaceItem("cooldown")

            local ok = pcall(CV.UpdateState, CV)
            assert(ok, "UpdateState threw on an unreadable item cooldown")
            assert(icon.wanted,
                "an unreadable item cooldown hid the icon instead of failing visible")
        end },

        { "an item cell gets a sweep in always mode", function()
            ResetItemStubs()
            _G.__itemCooldowns[13] = { startTime = 100, duration = 20 }
            local icon = PlaceItem("always")
            CV:UpdateState()
            assert(icon.wanted, "always mode did not show the item cell")
            assert(icon.cooldown.__cooldown, "an item cell in always mode was not swept")
        end },

        -- recharging is the whole point of this task: the mode a trinket or a
        -- potion timer actually wants -- show it while it is coming back, hide
        -- it once it is up.
        { "recharging is the inverse of cooldown, for the same item readiness", function()
            ResetItemStubs()

            local cdIconReady = PlaceItem("cooldown")
            CV:UpdateState()
            local readyShownAsCooldown = cdIconReady.wanted

            local rIconReady = PlaceItem("recharging")
            CV:UpdateState()
            local readyShownAsRecharging = rIconReady.wanted

            assert(readyShownAsCooldown == true and readyShownAsRecharging == false,
                "recharging did not invert cooldown mode while the item was ready")

            _G.__itemCooldowns[13] = { startTime = 100, duration = 20 }
            local cdIconBusy = PlaceItem("cooldown")
            CV:UpdateState()
            local onCdShownAsCooldown = cdIconBusy.wanted

            local rIconBusy = PlaceItem("recharging")
            CV:UpdateState()
            local onCdShownAsRecharging = rIconBusy.wanted

            assert(onCdShownAsCooldown == false and onCdShownAsRecharging == true,
                "recharging did not invert cooldown mode while the item was on cooldown")
            assert(rIconBusy.cooldown.__cooldown, "recharging mode did not sweep an item on cooldown")
        end },

        -- Same inversion, for a SPELL this time, using the existing
        -- cooldown-state stub rather than the item one -- recharging has to
        -- work for both, from the same readiness answer.
        { "recharging is the inverse of cooldown for a spell too", function()
            ResetItemStubs()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetPlacement(profile, 1, 1, 777, "cooldown")
            Data.SetPlacement(profile, 1, 2, 777, "recharging")
            CV:Rebuild()
            CV.container.__shown = true
            local cdIcon = CV.icons[Data.CellKey(1, 1)]
            local rIcon = CV.icons[Data.CellKey(1, 2)]

            _G.__cooldownState[777] = { isOnGCD = false, isActive = true }
            CV:UpdateState()
            assert(not cdIcon.wanted and rIcon.wanted,
                "recharging did not show while a spell was on cooldown")
            assert(rIcon.cooldown.__cooldown, "recharging mode did not sweep a spell on cooldown")

            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }
            CV:UpdateState()
            assert(cdIcon.wanted and not rIcon.wanted,
                "recharging stayed shown once the spell was ready again")
        end },

        -- Without this exclusion a charge spell in recharging mode would fall
        -- through BB:ShouldAdopt to IsChargeSpell and be adopted anyway, just
        -- like the same spell in cooldown mode.
        { "BB:ShouldAdopt refuses recharging even for a charge spell", function()
            ResetItemStubs()
            local profile = Data.GetActiveProfile()
            wipe(profile.placements)
            profile.collapse = "none"
            Data.SetPlacement(profile, 1, 1, 7000, "recharging")
            Data.InvalidateCooldownInfoCache()
            BB:ResetChargeCache()
            _G.__spellCharges[7000] = { maxCharges = 2, currentCharges = 2 }
            CV:Rebuild()
            local icon = CV.icons[Data.CellKey(1, 1)]
            assert(not BB:ShouldAdopt(icon),
                "recharging mode was adopted by Blizzard's frame")
        end },

        { "recharging is registered in the mode picker", function()
            local found = false
            for _, m in ipairs(Data.MODES) do
                if m.value == "recharging" then found = true end
            end
            assert(found, "recharging is not in Data.MODES, so the picker cannot offer it")
            assert(Data.ModeText("recharging") == "Show while recharging",
                "recharging has no picker label of its own")
        end },

        { "restore", function()
            _G.__cooldownEntries[9] = nil
            _G.__categorySets.Essential = { 1, 2, 4 }
            _G.__itemCooldowns = {}
            _G.__equipped = {}
            GetInventoryItemCooldown = nil
            ItemLocation = nil
            BB:ResetChargeCache()
            wipe(_G.__spellCharges)
            _G.__cooldownState[777] = nil
            _G.__cooldownState[8500] = nil
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

-- Potions and healthstones (task 18; DECISIONS.md §25). 12.1 puts these in the
-- Cooldown Manager as entries with NO spell ID at all, identified only by
-- `spellCategoryID`. Category 4 (combat potion) stands for the documented
-- shape; category 2566 (Demonic Healthstone) stands for the one Blizzard's
-- own local table carries with no named constant anywhere, and exists here
-- specifically to prove discovery never falls back to a hardcoded list.
if ThugUI.CooldownViewer then
    say("\n-- category cells (potions and healthstones) --")
    local CV = ThugUI.CooldownViewer
    local Data = CV.Data

    -- C_Spell.GetLastCategoryCooldownSource(spellCategory) -> spellID?, itemID?
    -- MayReturnNothing = true, SecretWhenCooldownsRestricted = true. An absent
    -- entry models "not triggered this session yet" -- the normal case on a
    -- fresh login, not a failure; `secret = true` models the secrecy flag.
    _G.__categorySource = {}
    function C_Spell.GetLastCategoryCooldownSource(spellCategory)
        local state = _G.__categorySource[spellCategory]
        if not state then return nil end
        if state.secret then return _G.__SECRET, _G.__SECRET end
        return state.spellID, state.itemID
    end

    -- C_Item.GetItemCooldown(itemID) -> startTime, duration, enableCooldownTimer.
    -- Carries no SecretWhen* flag at all (DECISIONS.md §20) -- plain numbers,
    -- keyed by item ID rather than an equip slot: a category cell has no slot.
    C_Item = C_Item or {}
    _G.__itemCooldownsByID = {}
    function C_Item.GetItemCooldown(itemID)
        local state = _G.__itemCooldownsByID[itemID]
        if not state then return 0, 0, 1 end
        return state.startTime or 0, state.duration or 0, 1
    end
    _G.__itemNamesByID = {}
    _G.__itemIconsByID = {}
    function C_Item.GetItemNameByID(itemID) return _G.__itemNamesByID[itemID] end
    function C_Item.GetItemIconByID(itemID) return _G.__itemIconsByID[itemID] end

    -- cooldownID 20: category 4, the documented "combat potion" shape, filed
    -- under Essential. cooldownID 21: category 2566, filed under Utility --
    -- unnamed anywhere in Blizzard's own constants, the reason discovery has
    -- to walk the live sweep rather than trust a list.
    _G.__cooldownEntries[20] = { cooldownID = 20, spellCategoryID = 4, linkedSpellIDs = {} }
    _G.__cooldownEntries[21] = { cooldownID = 21, spellCategoryID = 2566, linkedSpellIDs = {} }
    _G.__categorySets.Essential = { 1, 2, 4, 20 }
    _G.__categorySets.Utility = { 7, 21 }

    --- Places category 4 at (row, col) -- defaults to 1,1 -- and rebuilds.
    --- Does NOT wipe existing placements first, so a caller can place a
    --- second entry beside it (see the "adjacent cells" case below).
    local function PlaceCategory(mode, row, col)
        row, col = row or 1, col or 1
        local profile = Data.GetActiveProfile()
        profile.collapse = "none"
        profile.enabled, profile.onlyInCombat = true, false
        Data.SetCategoryPlacement(profile, row, col, 4, mode or "cooldown")
        Data.InvalidateCooldownInfoCache()
        CV:Rebuild()
        CV.container.__shown = true
        return CV.icons[Data.CellKey(row, col)]
    end

    -- Reset to a known baseline at the START of each case, not only at the
    -- end -- a case that fails and errors skips its own trailing cleanup
    -- (Lua `error` unwinds past it), which would otherwise leak state into
    -- whichever case runs next. Same discipline as ResetItemStubs above.
    local function ResetCategoryStubs()
        wipe(_G.__categorySource)
        wipe(_G.__itemCooldownsByID)
        local profile = Data.GetActiveProfile()
        wipe(profile.placements)
    end

    -- ------------------------------------------------------------------
    -- Task 19 (DECISIONS.md §25): resolve category art, cache it, repaint.
    --
    -- A second pooled-item stand-in, registered under a viewer name none of
    -- the "blizzard buff items" cases above use. It answers cooldownID 20
    -- (category 4's), and is asked for the category's ART (GetSpellCategoryIcon
    -- / GetSpellTexture / GetNameText) -- it is never adopted into a cell,
    -- unlike the cooldownID-3/7 items above.
    --
    -- Presence in the pool and every method are OFF by default (ResetArtStubs)
    -- so each case opts in only what it needs, and __artPoolEnumerations makes
    -- "was the pool ever walked" observable -- Decision 4 requires proving
    -- Data.CategoryEntry does NOT discover, and asserting a global stayed nil
    -- is exactly the shape of test that was incapable of failing last time
    -- (task 18's categoryInfoCache bug, DECISIONS.md §25).
    local artViewer = NewFrame()
    local artItem = NewFrame()
    artItem.GetCooldownID = function() return 20 end
    artItem.GetParent = function() return artViewer end
    _G.__artPoolEnumerations = 0
    _G.__artItemPresent = false
    artViewer.itemFramePool = {
        EnumerateActive = function()
            _G.__artPoolEnumerations = _G.__artPoolEnumerations + 1
            local yielded = false
            return function()
                if yielded or not _G.__artItemPresent then return nil end
                yielded = true
                return artItem
            end
        end,
    }
    _G.EssentialCooldownViewer = artViewer

    --- Same discipline as ResetCategoryStubs: reset at the START of a case.
    --- rawset(..., false) rather than leaving a method undefined -- the frame
    --- stub synthesises EVERY Capitalised key as a truthy no-op
    --- (Tests/README.md, "Hazards in the harness itself"), so an
    --- un-rawset method reads as "present" here even though a real frame
    --- missing it would read nil. Only `false` reproduces "absent".
    local function ResetArtStubs()
        ThugUI_Config.cvCategoryArt = {}
        _G.__artPoolEnumerations = 0
        _G.__artItemPresent = false
        rawset(artItem, "GetSpellCategoryIcon", false)
        rawset(artItem, "GetSpellTexture", false)
        rawset(artItem, "GetNameText", false)
    end

    local steps = {
        { "a spellCategoryID-only entry appears in the picker with a name and an icon", function()
            ResetCategoryStubs()
            Data.InvalidateCooldownInfoCache()
            local list = Data.BuildSpellList("essential", nil)

            local found
            for _, entry in ipairs(list) do
                if entry.categoryID == 4 then found = entry end
            end
            assert(found, "the category-4 entry never appeared in the essential picker")
            assert(found.name and found.name ~= "", "category picker row has no name")
            assert(found.icon, "category picker row has no icon")
        end },

        -- Proof of discovery, not of the documented shape: 2566 has no named
        -- constant anywhere in Blizzard's own Lua, so finding it can only
        -- come from actually walking the sweep.
        { "discovery finds a category the code does not name (2566), never a hardcoded list", function()
            ResetCategoryStubs()
            Data.InvalidateCooldownInfoCache()
            local ids = Data.DiscoverCategoryIDs()

            local found = false
            for _, id in ipairs(ids) do
                if id == 2566 then found = true end
            end
            assert(found, "discovery did not surface category 2566 from the live sweep")
        end },

        -- Review catch, task 18: `local categoryInfoCache` was declared BELOW
        -- Data.InvalidateCooldownInfoCache, so the assignment inside that
        -- function bound to a GLOBAL of the same name. The cache was never
        -- invalidated, and the name leaked into WoW's shared namespace --
        -- which is how §15's Edit Mode collision began.
        --
        -- A "no global was written" assertion was drafted here and DELETED: it
        -- can never fail. The buggy code assigns `nil` to the global, and
        -- assigning nil does not create one, so rawget(_G, ...) reads nil
        -- either way. It was green against the bug it was written for. Left as
        -- a comment because a test that cannot fail is worse than no test, and
        -- this one looked entirely convincing.
        --
        -- What does catch it is the behaviour: a talent change fires
        -- InvalidateCooldownInfoCache WITHOUT changing spec, so the spec check
        -- in GetCategoryInfo cannot mask it and stale category data survives.
        { "invalidating rebuilds the category cache within one spec", function()
            ResetCategoryStubs()
            assert(Data.GetCategoryInfo(2566), "category 2566 missing from the initial sweep")

            -- Take 2566 away as a talent change might, with the spec unchanged.
            for id, entry in pairs(_G.__cooldownEntries) do
                if entry and entry.spellCategoryID == 2566 then
                    _G.__cooldownEntries[id] = nil
                end
            end
            for _, set in pairs(_G.__categorySets) do
                for i = #set, 1, -1 do
                    if _G.__cooldownEntries[set[i]] == nil then table.remove(set, i) end
                end
            end

            Data.InvalidateCooldownInfoCache()

            assert(Data.GetCategoryInfo(2566) == nil,
                "category 2566 survived an invalidate -- the cache was not rebuilt")
            ResetCategoryStubs()
        end },

        { "a category placement survives Data.GetPlacements rather than being dropped", function()
            ResetCategoryStubs()
            local profile = Data.GetActiveProfile()
            Data.SetCategoryPlacement(profile, 1, 1, 4, "cooldown")

            local placed = Data.GetPlacements(profile)
            assert(#placed == 1, "category placement was dropped by GetPlacements")
            assert(placed[1].categoryID == 4, "the surviving placement lost its categoryID")
        end },

        { "Data.PlacementKey is distinct for spell 4 and category 4", function()
            local spellKey = Data.PlacementKey({ spellID = 4 })
            local catKey = Data.PlacementKey({ categoryID = 4 })
            assert(spellKey ~= catKey, "a string key and a number key collided: "
                .. "spell 4 and category 4 read as the same identity")
            assert(type(spellKey) == "number", "a spell placement's key should be its bare spell ID")
            assert(type(catKey) == "string", "a category placement's key should not be a bare number")
        end },

        { "GetLastCategoryCooldownSource returning nothing draws the cell anyway, with no sweep and no error", function()
            ResetCategoryStubs()
            local icon = PlaceCategory("cooldown")
            assert(icon.categoryID == 4, "categoryID was not captured onto the icon")

            local ok = pcall(CV.UpdateState, CV)
            assert(ok, "UpdateState threw when the category source had not resolved yet")
            assert(icon.wanted, "an unresolved category source hid the cell instead of drawing it")
            assert(not icon.cooldown.__cooldown, "an unresolved category source got a sweep")
        end },

        { "a secret return from GetLastCategoryCooldownSource does not throw and does not hide the cell", function()
            ResetCategoryStubs()
            _G.__categorySource[4] = { secret = true }
            local icon = PlaceCategory("cooldown")

            local ok = pcall(CV.UpdateState, CV)
            assert(ok, "UpdateState threw on a secret GetLastCategoryCooldownSource return")
            assert(icon.wanted, "a secret category source hid the cell instead of drawing it")
        end },

        { "placing a category entry and a spell in adjacent cells leaves both drawing", function()
            ResetCategoryStubs()
            local profile = Data.GetActiveProfile()
            profile.collapse = "none"
            profile.enabled, profile.onlyInCombat = true, false
            Data.SetCategoryPlacement(profile, 1, 1, 4, "cooldown")
            Data.SetPlacement(profile, 1, 2, 777, "cooldown")
            Data.InvalidateCooldownInfoCache()
            CV:Rebuild()
            CV.container.__shown = true

            local catIcon = CV.icons[Data.CellKey(1, 1)]
            local spellIcon = CV.icons[Data.CellKey(1, 2)]
            _G.__cooldownState[777] = { isOnGCD = false, isActive = false }

            CV:UpdateState()
            assert(catIcon.wanted, "the category cell did not draw beside a spell cell")
            assert(spellIcon.wanted, "the spell cell did not draw beside a category cell")
        end },

        -- The success path, not just the fail-open one: once the category has
        -- actually been triggered this session, its cooldown drives the cell
        -- exactly like an item-backed cell's does.
        { "once resolved, the category item's own cooldown drives cooldown/recharging/always modes", function()
            ResetCategoryStubs()
            _G.__categorySource[4] = { spellID = 17545, itemID = 191545 }
            _G.__itemCooldownsByID[191545] = { startTime = 100, duration = 20 }

            local cdIcon = PlaceCategory("cooldown")
            CV:UpdateState()
            assert(not cdIcon.wanted, "cooldown mode showed a category item that is on cooldown")

            local rIcon = PlaceCategory("recharging")
            CV:UpdateState()
            assert(rIcon.wanted, "recharging mode did not show a category item that is on cooldown")
            assert(rIcon.cooldown.__cooldown, "recharging mode did not sweep a category item on cooldown")

            local aIcon = PlaceCategory("always")
            CV:UpdateState()
            assert(aIcon.wanted, "always mode did not show a category item")
            assert(aIcon.cooldown.__cooldown, "always mode did not sweep a category item")
        end },

        -- Task 19 (DECISIONS.md §25): the drawn cell keeps its question mark
        -- past login/combat until a dropdown forces a rebuild. Six cases
        -- below, one per numbered requirement in the task file.

        { "task 19 fault B: with nothing resolvable a category entry is the generic one; a persisted cache entry answers instantly", function()
            ResetCategoryStubs()
            ResetArtStubs()

            local generic = Data.CategoryEntry(4)
            assert(generic.name == "Consumable (category 4)",
                "an unresolved category should read the generic label, got " .. tostring(generic.name))
            assert(generic.icon == "Interface\\Icons\\INV_Misc_QuestionMark",
                "an unresolved category should draw the generic icon, got " .. tostring(generic.icon))

            -- The persisted cache answers on the very next call, with no
            -- viewer walk and no GetLastCategoryCooldownSource call needed --
            -- the login case fault B describes.
            ThugUI_Config.cvCategoryArt[4] = { name = "Combat Potion", icon = "cached-icon-path" }
            local cached = Data.CategoryEntry(4)
            assert(cached.name == "Combat Potion",
                "a persisted cache entry's name was not read -- got " .. tostring(cached.name))
            assert(cached.icon == "cached-icon-path",
                "a persisted cache entry's icon was not read -- got " .. tostring(cached.icon))
        end },

        { "task 19 fault A: a resolved category-art cache repaints the drawn cell via UpdateState, with no rebuild in between", function()
            ResetCategoryStubs()
            ResetArtStubs()

            local GENERIC = "Interface\\Icons\\INV_Misc_QuestionMark"
            local icon = PlaceCategory("cooldown")
            assert(icon.tex.__texture == GENERIC,
                "sanity: a category cell with nothing resolved should draw the generic icon")
            assert(icon.baseTexture == GENERIC,
                "sanity: baseTexture should start generic too")

            -- Simulates a resolve landing (Data.ResolveCategoryArt, on a
            -- combat transition) AFTER the cell was already drawn. Fault A:
            -- the old UpdateState never touched icon.tex at all, so a cache
            -- entry like this sat unused until the player forced a rebuild by
            -- touching a dropdown.
            ThugUI_Config.cvCategoryArt[4] = { name = "Combat Potion", icon = "resolved-icon-path" }

            local ok = pcall(CV.UpdateState, CV)
            assert(ok, "UpdateState threw while repainting a resolved category cell")
            assert(icon.tex.__texture == "resolved-icon-path",
                "UpdateState did not repaint icon.tex from the resolved cache -- got "
                .. tostring(icon.tex.__texture))
            assert(icon.baseTexture == "resolved-icon-path",
                "UpdateState repainted icon.tex but left icon.baseTexture stale -- aura mode would "
                .. "swap against the wrong art")
        end },

        { "task 19 decision 2: a resolved category entry is sticky -- a pass where every path fails again does not revert it", function()
            ResetCategoryStubs()
            ResetArtStubs()

            ThugUI_Config.cvCategoryArt[4] = { name = "Combat Potion", icon = "resolved-icon-path" }
            -- Nothing resolvable THIS pass: no item in the pool, no cooldown
            -- source. A correct ResolveCategoryArt must skip category 4
            -- entirely because it is already cached, not attempt-and-fail.
            Data.ResolveCategoryArt()

            local entry = Data.CategoryEntry(4)
            assert(entry.name == "Combat Potion" and entry.icon == "resolved-icon-path",
                "a resolve pass where every path failed downgraded an already-resolved category "
                .. "back toward the generic entry -- got name=" .. tostring(entry.name)
                .. " icon=" .. tostring(entry.icon))
        end },

        { "task 19 decision 1: GetSpellCategoryIcon is preferred over GetSpellTexture when both exist and differ", function()
            ResetCategoryStubs()
            ResetArtStubs()

            _G.__artItemPresent = true
            artItem.GetSpellCategoryIcon = function() return "category-art-path" end
            artItem.GetSpellTexture = function() return "item-icon-path" end
            artItem.GetNameText = function() return "Combat Potion" end

            Data.ResolveCategoryArt()

            local entry = Data.CategoryEntry(4)
            assert(entry.icon == "category-art-path",
                "GetSpellTexture's item icon was used instead of GetSpellCategoryIcon's category "
                .. "art -- got " .. tostring(entry.icon))
        end },

        { "task 19 decision 3: invalidating the cooldown-info cache does not clear cvCategoryArt, though it still clears the spec-scoped category cache", function()
            ResetCategoryStubs()
            ResetArtStubs()

            -- Spec-scoped category cache starts populated -- unaffected by
            -- this case, but confirms nothing here was left in a broken
            -- state; full coverage of THIS half is the existing
            -- "invalidating rebuilds the category cache within one spec" case
            -- above, which this one deliberately does not duplicate.
            assert(Data.GetCategoryInfo(4), "category 4 missing from the initial sweep")

            -- Persisted art cache, as if a prior resolve had already run.
            -- Nothing in the pool or the cooldown source can answer for
            -- category 4 this pass, so if Data.CategoryEntry falls back to
            -- the generic label, the persisted cache was wrongly cleared.
            ThugUI_Config.cvCategoryArt[4] = { name = "Combat Potion", icon = "resolved-icon-path" }

            Data.InvalidateCooldownInfoCache()

            local entry = Data.CategoryEntry(4)
            assert(entry.name == "Combat Potion" and entry.icon == "resolved-icon-path",
                "Data.InvalidateCooldownInfoCache cleared the persisted category-art cache -- got "
                .. "name=" .. tostring(entry.name) .. " icon=" .. tostring(entry.icon))
        end },

        { "task 19 decision 4: Data.CategoryEntry does not discover -- with the cache empty it never walks the item-frame pool", function()
            ResetCategoryStubs()
            ResetArtStubs()
            Data.InvalidateCooldownInfoCache()

            local entry = Data.CategoryEntry(4)
            assert(entry.name == "Consumable (category 4)",
                "sanity: an unresolved category should read the generic label, got " .. tostring(entry.name))
            assert(_G.__artPoolEnumerations == 0,
                "Data.CategoryEntry walked the item-frame pool on a cache miss -- it must only read "
                .. "the persisted cache and fall back to the generic entry")
        end },

        -- The regression the player reported on 2026-08-13: after task 19 the
        -- category cells stopped updating ENTIRELY, where before combat had at
        -- least refreshed the picker and a dropdown change had refreshed the
        -- drawn grid. Cause: ResolveCategoryArt only visited categories that
        -- DISCOVERY reported, and discovery is built from the Cooldown Manager
        -- sweep -- which that session logged as finding nothing. The old
        -- uncached CategoryEntry never had the hole, because it was called
        -- with the placed categoryID directly.
        { "task 19 regression: a PLACED category resolves even when discovery cannot see it", function()
            ResetCategoryStubs()
            ResetArtStubs()

            -- cooldownID 20 is what carries spellCategoryID 4 into the sweep.
            -- Without it, discovery never mentions category 4 at all.
            _G.__categorySets.Essential = { 1, 2, 4 }
            Data.InvalidateCooldownInfoCache()

            for _, id in ipairs(Data.DiscoverCategoryIDs()) do
                assert(id ~= 4, "sanity: discovery was supposed to be blind to category 4 here")
            end

            -- Path 2 can still answer, exactly as it could before the cache.
            _G.__categorySource[4] = { spellID = 5, itemID = 6 }
            _G.__itemNamesByID[6] = "Algari Healing Potion"
            _G.__itemIconsByID[6] = "placed-potion-icon"

            local icon = PlaceCategory("cooldown")

            assert(ThugUI_Config.cvCategoryArt[4],
                "a placed category was never resolved -- ResolveCategoryArt only "
                .. "looked at what discovery reported")
            assert(icon.tex.__texture == "placed-potion-icon",
                "the drawn cell did not pick up the resolved art, got "
                    .. tostring(icon.tex.__texture))
            assert(Data.CategoryEntry(4).name == "Algari Healing Potion",
                "the picker would still read the generic label, got "
                    .. tostring(Data.CategoryEntry(4).name))

            _G.__categorySets.Essential = { 1, 2, 4, 20 }
            _G.__itemNamesByID[6] = nil
            _G.__itemIconsByID[6] = nil
            Data.InvalidateCooldownInfoCache()
        end },

        { "restore", function()
            _G.__cooldownEntries[20] = nil
            _G.__cooldownEntries[21] = nil
            _G.__categorySets.Essential = { 1, 2, 4 }
            _G.__categorySets.Utility = { 7 }
            _G.__categorySource = {}
            _G.__itemCooldownsByID = {}
            C_Spell.GetLastCategoryCooldownSource = nil
            C_Item = nil
            Data.InvalidateCooldownInfoCache()
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
if ThugUI.ComboPips then
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
if ThugUI.SecretProbe then
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

        -- Task 13: what 12.1's charge-adjacent APIs actually hand back.
        -- cooldownID 8 is a scratch entry, unused by any other test, added to
        -- Essential and removed again so it cannot leak into the sections
        -- that come after this one.
        { "a charge spell's secret maxCharges is described, not read, and does not throw", function()
            ThugUI_DebugLog.secrets = {}
            _G.__cooldownEntries[8] = { cooldownID = 8, spellID = 8000, charges = true, linkedSpellIDs = {} }
            _G.__categorySets.Essential = { 1, 2, 4, 8 }
            _G.__spellCharges[8000] = { maxCharges = _G.__SECRET, currentCharges = _G.__SECRET }

            local ok, err = pcall(function() SP:Run("charge-secret-max") end)

            _G.__cooldownEntries[8] = nil
            _G.__categorySets.Essential = { 1, 2, 4 }
            _G.__spellCharges[8000] = nil

            assert(ok, "a secret maxCharges threw rather than being described: " .. tostring(err))
            local text = Lines("charge-secret-max")
            assert(text:match("charges%.max Spell 8000%s+SECRET"),
                "a secret maxCharges was not described as secret:\n" .. text)
        end },

        { "GetSpellCooldownDuration returning nothing is distinguishable from secret", function()
            ThugUI_DebugLog.secrets = {}
            _G.__cooldownEntries[8] = { cooldownID = 8, spellID = 8000, charges = true, linkedSpellIDs = {} }
            _G.__categorySets.Essential = { 1, 2, 4, 8 }
            local realDuration = C_Spell.GetSpellCooldownDuration

            C_Spell.GetSpellCooldownDuration = function() return nil end
            local ok1, err1 = pcall(function() SP:Run("charge-duration-nothing") end)

            C_Spell.GetSpellCooldownDuration = function() return _G.__SECRET end
            local ok2, err2 = pcall(function() SP:Run("charge-duration-secret") end)

            C_Spell.GetSpellCooldownDuration = realDuration
            _G.__cooldownEntries[8] = nil
            _G.__categorySets.Essential = { 1, 2, 4 }

            assert(ok1, "GetSpellCooldownDuration returning nothing threw: " .. tostring(err1))
            assert(ok2, "GetSpellCooldownDuration returning a secret threw: " .. tostring(err2))

            local nothingText = Lines("charge-duration-nothing")
            assert(nothingText:match("cooldownDuration Spell 8000%s+nothing"),
                "a nil duration was not recorded as nothing:\n" .. nothingText)

            local secretText = Lines("charge-duration-secret")
            assert(secretText:match("cooldownDuration Spell 8000%s+SECRET"),
                "a secret duration was not recorded as secret:\n" .. secretText)
        end },

        -- Both directions matter: a version that always skips the line would
        -- pass a "missing skips it" check for free even with the feature
        -- deleted entirely, which is exactly the "repurposed test" trap
        -- 00-AGENT-BRIEF.md warns about. Asserting the line APPEARS when the
        -- method is present is what makes this catch a regression instead of
        -- passing vacuously.
        { "SetCooldownFromDurationObject line depends on the method existing", function()
            _G.__cooldownEntries[8] = { cooldownID = 8, spellID = 8000, charges = true, linkedSpellIDs = {} }
            _G.__categorySets.Essential = { 1, 2, 4, 8 }
            local realDuration = C_Spell.GetSpellCooldownDuration
            C_Spell.GetSpellCooldownDuration = function() return { __duration = true } end

            -- Present: the frame stub auto-synthesises every Capitalised
            -- method as a no-op the moment it is READ (see frameMT's
            -- __index near the top of this file), so no setup is needed to
            -- model "the client has this API" -- it already does.
            ThugUI_DebugLog.secrets = {}
            local ok1, err1 = pcall(function() SP:Run("charge-duration-setter-present") end)
            local presentText = ok1 and Lines("charge-duration-setter-present")

            -- Missing: overwritten with a non-function value directly. The
            -- metatable only fires for a key that is not already present on
            -- the table, so a plain assignment sticks where deleting it
            -- (assigning nil) would not -- this is the only way this harness
            -- can model a client that genuinely lacks the 12.1 API.
            ThugUI_DebugLog.secrets = {}
            local widgets = SP:EnsureWidgets()
            widgets.cooldown.SetCooldownFromDurationObject = false
            local ok2, err2 = pcall(function() SP:Run("charge-duration-setter-missing") end)
            widgets.cooldown.SetCooldownFromDurationObject = nil
            local missingText = ok2 and Lines("charge-duration-setter-missing")

            C_Spell.GetSpellCooldownDuration = realDuration
            _G.__cooldownEntries[8] = nil
            _G.__categorySets.Essential = { 1, 2, 4 }

            assert(ok1, "SetCooldownFromDurationObject present threw: " .. tostring(err1))
            assert(ok2, "SetCooldownFromDurationObject missing threw: " .. tostring(err2))
            assert(presentText:match("SetCooldownFromDurationObject"),
                "the line never appeared even with the method present:\n" .. presentText)
            assert(not missingText:match("SetCooldownFromDurationObject"),
                "recorded a line for a method the client does not have:\n" .. missingText)
        end },

        { "no C_CooldownViewer records the fact and does not throw", function()
            ThugUI_DebugLog.secrets = {}
            local real = C_CooldownViewer
            C_CooldownViewer = nil

            local ok, err = pcall(function() SP:Run("no-cooldownviewer") end)
            C_CooldownViewer = real

            assert(ok, "a missing C_CooldownViewer took the probe down: " .. tostring(err))
            local text = Lines("no-cooldownviewer")
            assert(text:match("charges%s+C_CooldownViewer absent"),
                "did not record the missing API:\n" .. text)
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
