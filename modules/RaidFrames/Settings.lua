-- ============================================================================
-- ThugUI: Raid Frames settings sub-panel
--
-- Option names and grouping deliberately mirror the categories a raid-frame
-- addon user already knows (Layout / Health / Buff Manager / Debuff Display /
-- Behaviour) so nothing has to be re-learned when moving off the default
-- frames. Registered as a subcategory of the existing ThugUI settings category.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local ER = ThugUI.EssentialRings
local RaidFrames = ThugUI.RaidFrames

-- ============================================================================
-- LOCAL WIDGET HELPERS
-- ============================================================================

local function AddCheckbox(content, name, label, configKey, anchorTo, xOff, yOff, onChange)
    local cb = CreateFrame("CheckButton", name, content, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOff, yOff)
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb:SetChecked(ThugUI_Config[configKey])
    cb:SetScript("OnClick", function(self)
        ThugUI_Config[configKey] = self:GetChecked()
        if onChange then onChange(self:GetChecked()) end
    end)
    cb.thugConfigKey = configKey
    return cb
end

local function AddSlider(content, name, label, configKey, minV, maxV, step, anchorTo, xOff, yOff, decimals, onChange)
    local slider = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOff, yOff)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValue(ThugUI_Config[configKey] or minV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(160)

    local fmt = decimals and "%." .. decimals .. "f" or "%d"
    _G[slider:GetName() .. "Low"]:SetText(string.format(fmt, minV))
    _G[slider:GetName() .. "High"]:SetText(string.format(fmt, maxV))
    _G[slider:GetName() .. "Text"]:SetText(label)

    local value = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    value:SetText(string.format(fmt, ThugUI_Config[configKey] or minV))

    slider:SetScript("OnValueChanged", function(self, v)
        local rounded = decimals and (math.floor(v * 100 + 0.5) / 100) or math.floor(v + 0.5)
        value:SetText(string.format(fmt, rounded))
        ThugUI_Config[configKey] = rounded
        if onChange then onChange(rounded) end
    end)

    slider.thugValueText = value
    slider.thugConfigKey = configKey
    slider.thugFormat = fmt
    return slider
end

local function AddDropdown(content, name, label, configKey, choices, anchorTo, xOff, yOff, onChange)
    local dropdown = CreateFrame("Frame", name, content, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOff, yOff)

    local labelText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 2)
    labelText:SetText(label)

    local function LabelFor(value)
        for _, choice in ipairs(choices) do
            if choice.value == value then return choice.text end
        end
        return choices[1] and choices[1].text or ""
    end

    UIDropDownMenu_SetWidth(dropdown, 140)
    UIDropDownMenu_SetText(dropdown, LabelFor(ThugUI_Config[configKey]))

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, choice in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = choice.text
            info.value = choice.value
            info.checked = (ThugUI_Config[configKey] == choice.value)
            info.func = function()
                ThugUI_Config[configKey] = choice.value
                UIDropDownMenu_SetText(dropdown, choice.text)
                CloseDropDownMenus()
                if onChange then onChange(choice.value) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    dropdown.thugConfigKey = configKey
    dropdown.thugLabelFor = LabelFor
    return dropdown
end

local function AddNote(content, text, anchorTo, xOff, yOff)
    local note = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    note:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOff, yOff)
    note:SetText(text)
    return note
end

-- ============================================================================
-- PANEL
-- ============================================================================

function ER:CreateRaidFramesPanel(parentCategory)
    local panel = CreateFrame("Frame", "ThugUI_RaidFramesPanel")
    panel.name = "Raid Frames"

    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    local content = ER.CreateScrollablePanel(panel, 1180)
    local CreateSeparator = ER.CreateSeparator

    -- Live-apply helpers. Appearance changes take effect immediately; anything
    -- that changes the secure header's geometry needs a respawn, so those show
    -- the reload hint instead of pretending to apply.
    local function ApplyLive()
        if RaidFrames then RaidFrames:RefreshFrames() end
    end

    local function ApplyToggle()
        if RaidFrames then RaidFrames:ApplyAll() end
    end

    -- Secure headers re-run their layout on any attribute change, so spacing,
    -- columns and grouping apply immediately out of combat.
    local function ApplyLayout()
        if not RaidFrames then return end
        RaidFrames:ApplyHeaderLayout()
        RaidFrames:UpdateMoverGeometry()
    end

    -- =====================
    -- Header / intro
    -- =====================
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Raid Frames")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("ThugUI's own party/raid frames, built on oUF.")

    local enableCheckbox = AddCheckbox(content, "ThugUI_RFEnabled",
        "|cff00ff00Enable ThugUI Raid Frames|r",
        "rfEnabled", subtitle, 0, -12, ApplyToggle)

    local enableNote = AddNote(content,
        "Replaces the Blizzard party and raid frames. Everything on this page\n" ..
        "applies immediately out of combat - no /reload needed.",
        enableCheckbox, 20, -2)

    local unlockCheckbox = AddCheckbox(content, "ThugUI_RFUnlock",
        "Unlock frames for moving",
        "rfUnlocked", enableNote, 0, -8, function(checked)
            if RaidFrames then RaidFrames:SetUnlocked(checked) end
        end)

    local unlockNote = AddNote(content,
        "Shows a drag handle over the frames. Position is saved automatically.",
        unlockCheckbox, 20, -2)

    -- =====================
    -- Layout
    -- =====================
    local layoutSep = CreateSeparator(content, "Layout", "TOPLEFT", unlockNote, -36, -20)

    local widthSlider = AddSlider(content, "ThugUI_RFWidth", "Frame Width",
        "rfWidth", 40, 160, 1, layoutSep, 20, -28, nil, ApplyLayout)

    local heightSlider = AddSlider(content, "ThugUI_RFHeight", "Frame Height",
        "rfHeight", 20, 100, 1, widthSlider, 0, -40, nil, ApplyLayout)

    local spacingSlider = AddSlider(content, "ThugUI_RFSpacing", "Spacing",
        "rfSpacing", 0, 20, 1, heightSlider, 0, -40, nil, ApplyLayout)

    local perColSlider = AddSlider(content, "ThugUI_RFPerCol", "Units Per Column",
        "rfUnitsPerColumn", 1, 40, 1, spacingSlider, 0, -40, nil, ApplyLayout)

    local maxColSlider = AddSlider(content, "ThugUI_RFMaxCol", "Max Columns",
        "rfMaxColumns", 1, 8, 1, perColSlider, 0, -40, nil, ApplyLayout)

    local groupByDropdown = AddDropdown(content, "ThugUI_RFGroupBy", "Group By", "rfGroupBy", {
        { text = "Group Number", value = "GROUP" },
        { text = "Role",         value = "ROLE" },
        { text = "Class",        value = "CLASS" },
        { text = "None (roster)", value = "NONE" },
    }, maxColSlider, -20, -46, ApplyLayout)

    local layoutNote = AddNote(content,
        "Layout changes are applied to the secure header directly, so they take\n" ..
        "effect at once - except during combat, where they queue until you drop out.",
        groupByDropdown, 20, -6)

    -- =====================
    -- Health
    -- =====================
    local healthSep = CreateSeparator(content, "Health", "TOPLEFT", layoutNote, -36, -20)

    local healthColorDropdown = AddDropdown(content, "ThugUI_RFHealthColor", "Bar Color", "rfHealthColor", {
        { text = "Class Color",     value = "class" },
        { text = "Health Gradient", value = "gradient" },
        { text = "Static Dark",     value = "static" },
    }, healthSep, 0, -34, ApplyLive)

    local powerCheckbox = AddCheckbox(content, "ThugUI_RFPower", "Show power bar",
        "rfShowPowerBar", healthColorDropdown, 20, -6, ApplyLive)

    local powerHeightSlider = AddSlider(content, "ThugUI_RFPowerHeight", "Power Bar Height",
        "rfPowerBarHeight", 1, 10, 1, powerCheckbox, 20, -12, nil, ApplyLive)

    -- =====================
    -- Text
    -- =====================
    local textSep = CreateSeparator(content, "Text", "TOPLEFT", powerHeightSlider, -56, -30)

    local nameCheckbox = AddCheckbox(content, "ThugUI_RFShowName", "Show unit name",
        "rfShowName", textSep, 20, -15, ApplyLive)

    local nameLenSlider = AddSlider(content, "ThugUI_RFNameLen", "Name Length",
        "rfNameLength", 0, 12, 1, nameCheckbox, 20, -12, nil, ApplyLive)

    local nameNote = AddNote(content, "0 shows the full name with no truncation.", nameLenSlider, -20, -18)

    -- =====================
    -- Buff Manager
    -- =====================
    local buffSep = CreateSeparator(content, "Buff Manager", "TOPLEFT", nameNote, -36, -20)

    local showBuffsCheckbox = AddCheckbox(content, "ThugUI_RFShowBuffs", "Show buffs",
        "rfShowBuffs", buffSep, 20, -15, ApplyLive)

    local buffMineCheckbox = AddCheckbox(content, "ThugUI_RFBuffMine", "Only show buffs I cast",
        "rfBuffOnlyMine", showBuffsCheckbox, 0, -4, ApplyLive)

    local buffTooltipCheckbox = AddCheckbox(content, "ThugUI_RFBuffTooltip", "Hide tooltips",
        "rfBuffHideTooltips", buffMineCheckbox, 0, -4, ApplyLive)

    local buffTooltipNote = AddNote(content,
        "Also lets clicks and mouseover pass through the icon to the frame\n" ..
        "underneath, so click-casting still works over your HoTs.",
        buffTooltipCheckbox, 20, -2)

    local buffCountSlider = AddSlider(content, "ThugUI_RFBuffCount", "Buff Count",
        "rfBuffCount", 1, 10, 1, buffTooltipNote, 0, -14, nil, ApplyLive)

    local buffSizeSlider = AddSlider(content, "ThugUI_RFBuffSize", "Buff Icon Size",
        "rfBuffSize", 6, 32, 1, buffCountSlider, 0, -40, nil, ApplyLive)

    -- =====================
    -- Debuff Display
    -- =====================
    local debuffSep = CreateSeparator(content, "Debuff Display", "TOPLEFT", buffSizeSlider, -36, -34)

    local showDebuffsCheckbox = AddCheckbox(content, "ThugUI_RFShowDebuffs", "Show debuffs",
        "rfShowDebuffs", debuffSep, 20, -15, ApplyLive)

    local debuffDispelCheckbox = AddCheckbox(content, "ThugUI_RFDebuffDispel",
        "Only show debuffs I can dispel",
        "rfDebuffDispellableOnly", showDebuffsCheckbox, 0, -4, ApplyLive)

    local debuffTooltipCheckbox = AddCheckbox(content, "ThugUI_RFDebuffTooltip", "Hide tooltips",
        "rfDebuffHideTooltips", debuffDispelCheckbox, 0, -4, ApplyLive)

    local debuffNote = AddNote(content,
        "Debuff borders are colored by dispel type, so you can read them\n" ..
        "at a glance without a tooltip.",
        debuffTooltipCheckbox, 20, -2)

    local debuffCountSlider = AddSlider(content, "ThugUI_RFDebuffCount", "Debuff Count",
        "rfDebuffCount", 1, 10, 1, debuffNote, 0, -14, nil, ApplyLive)

    local debuffSizeSlider = AddSlider(content, "ThugUI_RFDebuffSize", "Debuff Icon Size",
        "rfDebuffSize", 6, 32, 1, debuffCountSlider, 0, -40, nil, ApplyLive)

    -- =====================
    -- Behaviour
    -- =====================
    local behaviourSep = CreateSeparator(content, "Behaviour", "TOPLEFT", debuffSizeSlider, -36, -34)

    local rangeSlider = AddSlider(content, "ThugUI_RFRange", "Out of Range Alpha",
        "rfRangeAlpha", 0.1, 1.0, 0.05, behaviourSep, 20, -28, 2, ApplyLive)

    local partyCheckbox = AddCheckbox(content, "ThugUI_RFParty", "Use for party as well as raid",
        "rfShowParty", rangeSlider, -20, -14, ApplyToggle)

    local soloCheckbox = AddCheckbox(content, "ThugUI_RFSolo", "Show when solo",
        "rfShowSolo", partyCheckbox, 0, -4, ApplyToggle)

    local hideBlizzCheckbox = AddCheckbox(content, "ThugUI_RFHideBlizz", "Hide Blizzard raid frames",
        "rfHideBlizzardRaidFrames", soloCheckbox, 0, -4, ApplyToggle)

    local hideBlizzNote = AddNote(content,
        "Applied with a visibility state driver, never a Show() override, so it\n" ..
        "does not taint the frames. Takes effect out of combat.",
        hideBlizzCheckbox, 20, -2)

    -- =====================
    -- Reset
    -- =====================
    local resetSep = CreateSeparator(content, "Reset", "TOPLEFT", hideBlizzNote, -36, -20)

    local resetKeys = {
        "rfEnabled", "rfUnlocked", "rfWidth", "rfHeight", "rfSpacing", "rfUnitsPerColumn",
        "rfMaxColumns", "rfGroupBy", "rfHealthColor", "rfShowPowerBar",
        "rfPowerBarHeight", "rfShowName", "rfNameLength", "rfShowBuffs",
        "rfBuffOnlyMine", "rfBuffHideTooltips", "rfBuffCount", "rfBuffSize",
        "rfShowDebuffs", "rfDebuffDispellableOnly", "rfDebuffHideTooltips",
        "rfDebuffCount", "rfDebuffSize", "rfRangeAlpha", "rfShowParty",
        "rfShowSolo", "rfHideBlizzardRaidFrames",
    }

    local checkboxes = {
        enableCheckbox, unlockCheckbox, powerCheckbox, nameCheckbox,
        showBuffsCheckbox, buffMineCheckbox, buffTooltipCheckbox,
        showDebuffsCheckbox, debuffDispelCheckbox, debuffTooltipCheckbox,
        partyCheckbox, soloCheckbox, hideBlizzCheckbox,
    }

    local sliders = {
        widthSlider, heightSlider, spacingSlider, perColSlider, maxColSlider,
        powerHeightSlider, nameLenSlider, buffCountSlider, buffSizeSlider,
        debuffCountSlider, debuffSizeSlider, rangeSlider,
    }

    local dropdowns = { groupByDropdown, healthColorDropdown }

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(200, 25)
    resetButton:SetPoint("TOPLEFT", resetSep, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Raid Frame Settings")
    resetButton:SetScript("OnClick", function()
        for _, key in ipairs(resetKeys) do
            ThugUI_Config[key] = ER.defaults[key]
        end

        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(ThugUI_Config[cb.thugConfigKey])
        end
        for _, slider in ipairs(sliders) do
            local v = ThugUI_Config[slider.thugConfigKey]
            slider:SetValue(v)
            slider.thugValueText:SetText(string.format(slider.thugFormat, v))
        end
        for _, dd in ipairs(dropdowns) do
            UIDropDownMenu_SetText(dd, dd.thugLabelFor(ThugUI_Config[dd.thugConfigKey]))
        end

        ApplyToggle()
        if RaidFrames then RaidFrames:SetUnlocked(ThugUI_Config.rfUnlocked) end
        print("|cff00ff00ThugUI:|r Raid frame settings reset to defaults.")
    end)

    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    subcategory.ID = "ThugUI_RaidFrames"
end
