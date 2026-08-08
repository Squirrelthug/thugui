-- Essential Rings Settings for ThugUI
-- Settings panel with subcategory architecture

ThugUI_Config = ThugUI_Config or {}

ThugUI = ThugUI or {}
local ER = ThugUI.EssentialRings

-- ============================================================================
-- SHARED HELPER FUNCTIONS
-- ============================================================================

local function CreateScrollablePanel(panel, height)
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 3, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(600, height or 700)
    scrollFrame:SetScrollChild(content)

    return content
end

local function CreateSeparator(content, text, anchor, relativeFrame, xOffset, yOffset)
    local separator = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    separator:SetPoint(anchor, relativeFrame, "BOTTOMLEFT", xOffset, yOffset)
    separator:SetText(text)
    separator:SetTextColor(1.0, 0.82, 0, 1)

    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    line:SetHeight(1)
    line:SetPoint("LEFT", separator, "RIGHT", 5, 0)
    line:SetPoint("RIGHT", content, "RIGHT", -20, 0)

    return separator
end

local function CreateSimpleDropdown(content, name, label, defaultValue)
    local dropdown = CreateFrame("Frame", name, content, "UIDropDownMenuTemplate")

    local labelText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 0)
    labelText:SetText(label)

    UIDropDownMenu_SetWidth(dropdown, 120)
    UIDropDownMenu_SetText(dropdown, defaultValue)

    return dropdown
end

local function CreateColorPickerButton(content, configKey, updateFunc)
    local button = CreateFrame("Button", nil, content)
    button:SetSize(16, 16)

    local swatch = button:CreateTexture(nil, "OVERLAY")
    swatch:SetAllPoints()
    swatch:SetColorTexture(1, 1, 1)
    button.swatch = swatch

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.5, 0.5, 0.5)

    local function UpdateButtonColor()
        local c = ThugUI_Config[configKey]
        if c then
            swatch:SetVertexColor(c.r, c.g, c.b)
        else
            swatch:SetVertexColor(1, 1, 1)
        end
    end

    button:SetScript("OnClick", function()
        local r, g, b = 1, 1, 1
        if ThugUI_Config[configKey] then
            r, g, b = ThugUI_Config[configKey].r, ThugUI_Config[configKey].g, ThugUI_Config[configKey].b
        end

        local info = {
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                ThugUI_Config[configKey] = {r = newR, g = newG, b = newB}
                UpdateButtonColor()
                if updateFunc then updateFunc() end
            end,
            cancelFunc = function()
                ThugUI_Config[configKey] = {r = r, g = g, b = b}
                UpdateButtonColor()
                if updateFunc then updateFunc() end
            end,
        }

        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    UpdateButtonColor()
    button.UpdateColor = UpdateButtonColor

    return button
end

local function CreateColorModeDropdown(content, label, colorModeKey, customColorKey, anchorPoint, relativeFrame, xOffset, yOffset, updateFunc, defaultText)
    local dropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    dropdown:SetPoint(anchorPoint, relativeFrame, "BOTTOMLEFT", xOffset, yOffset)

    local labelText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 0)
    labelText:SetText(label)

    UIDropDownMenu_SetWidth(dropdown, 120)

    local colorButton = CreateColorPickerButton(content, customColorKey, updateFunc)
    colorButton:SetPoint("LEFT", dropdown, "RIGHT", 10, 2)

    local function UpdateColorButtonState()
        local mode = ThugUI_Config[colorModeKey] or "default"
        if mode == "custom" then
            colorButton:Enable()
            colorButton:SetAlpha(1.0)
        else
            colorButton:Disable()
            colorButton:SetAlpha(0.5)
        end
    end

    local defaultOptionText = defaultText or "Default (White)"

    UIDropDownMenu_Initialize(dropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local options = {defaultOptionText, "Class Color", "Custom Color"}
        local values = {"default", "class", "custom"}

        for i, option in ipairs(options) do
            info.text = option
            info.checked = (ThugUI_Config[colorModeKey] == values[i])
            info.func = function()
                ThugUI_Config[colorModeKey] = values[i]
                UIDropDownMenu_SetText(dropdown, option)
                UpdateColorButtonState()
                if updateFunc then updateFunc() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local currentMode = ThugUI_Config[colorModeKey] or "default"
    local modeText = currentMode == "default" and defaultOptionText or
                    currentMode == "class" and "Class Color" or "Custom Color"
    UIDropDownMenu_SetText(dropdown, modeText)
    UpdateColorButtonState()

    return dropdown, colorButton
end

local function GetClockLabel(value)
    return string.format("%d o'clock", value)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function ER:InitializeSettings()
    if not ThugUI_Config then
        ThugUI_Config = {}
    end

    for key, value in pairs(ER.defaults) do
        if ThugUI_Config[key] == nil then
            ThugUI_Config[key] = value
        end
    end
end

function ER:GetConfig()
    return ThugUI_Config
end

-- Shared with modules/RaidFrames/Settings.lua so its panel is laid out with the
-- same helpers as the rest of the ThugUI options, not a second set that drifts.
ER.CreateScrollablePanel = CreateScrollablePanel
ER.CreateSeparator = CreateSeparator

-- ============================================================================
-- MAIN SETTINGS PANEL (Info Page)
-- ============================================================================

function ER:CreateSettingsPanel()
    local panel = CreateFrame("Frame", "ThugUI_SettingsPanel")
    panel.name = "ThugUI"

    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    -- Info page content
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ThugUI")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Cursor-centered cooldown tracking and UI enhancements")

    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    separator:SetPoint("RIGHT", panel, "RIGHT", -20, 0)

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    desc:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -12)
    desc:SetText("Configure features using the subcategories below:")
    desc:SetTextColor(1.0, 0.82, 0, 1)

    local features = {
        {"|cffffffffCursor Rings|r", "Ring animations for GCD, casting, and reticle customization"},
        {"|cffffffffCooldown Viewer|r", "Essential spell cooldown bar showing ready abilities"},
        {"|cffffffffRaid Frames|r", "ThugUI party/raid frames with tooltip-free, click-through auras"},
        {"|cffffffffTarget of Target|r", "Your target's target on the full-size target frame art"},
        {"|cffffffffFrame Hider|r", "Hide unwanted default UI elements"},
    }

    local lastLine = desc
    for _, feat in ipairs(features) do
        local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:SetPoint("TOPLEFT", lastLine, "BOTTOMLEFT", 10, -12)
        header:SetText(feat[1])

        local detail = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        detail:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
        detail:SetText(feat[2])

        lastLine = detail
    end

    -- Test Mode separator + toggle
    local testSep = panel:CreateTexture(nil, "ARTWORK")
    testSep:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    testSep:SetHeight(1)
    testSep:SetPoint("TOPLEFT", lastLine, "BOTTOMLEFT", -10, -20)
    testSep:SetPoint("RIGHT", panel, "RIGHT", -20, 0)

    local testCheckbox = CreateFrame("CheckButton", "ThugUI_TestModeCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    testCheckbox:SetPoint("TOPLEFT", testSep, "BOTTOMLEFT", 0, -10)
    _G[testCheckbox:GetName() .. "Text"]:SetText("|cffff8800Test Mode|r — simulate combat for previewing settings")
    testCheckbox:SetChecked(ThugUI_Config.testMode or false)
    testCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.testMode = self:GetChecked()
        ER:UpdateVisibility()
    end)

    local testNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    testNote:SetPoint("TOPLEFT", testCheckbox, "BOTTOMLEFT", 25, -2)
    testNote:SetText("Shows rings, cooldown bar, and abundance counter as if in combat.\nDisable when done — has no effect on actual gameplay.")

    -- Register main category
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category, layout = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        layout:AddAnchorPoint("TOPLEFT", 0, 0)
        layout:AddAnchorPoint("BOTTOMRIGHT", 0, 0)
        category.ID = panel.name
        Settings.RegisterAddOnCategory(category)
        ER.settingsCategory = category

        -- Create sub-panels
        ER:CreateRingsPanel(category)
        ER:CreateECVPanel(category)
        ER:CreateBCVPanel(category)
        ER:CreateGCVPanel(category)
        ER:CreateRaidFramesPanel(category)
        ER:CreateTargetOfTargetPanel(category)
        ER:CreateFrameHiderPanel(category)
    else
        InterfaceOptions_AddCategory(panel)
    end

    ER.settingsPanel = panel
    return panel
end

-- ============================================================================
-- CURSOR RINGS SUB-PANEL
-- ============================================================================

function ER:CreateRingsPanel(parentCategory)
    local panel = CreateFrame("Frame", "ThugUI_RingsPanel")
    panel.name = "Cursor Rings"
    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    local content = CreateScrollablePanel(panel, 900)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Cursor Rings")

    local function OnDropdownClick(self, dropdown, configKey)
        ThugUI_Config[configKey] = self.value
        UIDropDownMenu_SetText(dropdown, self.value)
        ER:ApplySettings()
        CloseDropDownMenus()
    end

    -- =====================
    -- 1. Ring Slot Assignment
    -- =====================
    local ringSeparator = CreateSeparator(content, "Ring Slot Assignment", "TOPLEFT", title, 0, -20)

    -- Reticle Dropdown
    local reticleDropdown = CreateSimpleDropdown(content, "ThugUI_ReticleDropdown", "Reticle", ThugUI_Config.reticle)
    reticleDropdown:SetPoint("TOPLEFT", ringSeparator, "BOTTOMLEFT", 0, -20)

    UIDropDownMenu_Initialize(reticleDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(ER.reticleOptions) do
            info.text = option
            info.checked = (ThugUI_Config.reticle == option)
            info.func = function()
                ThugUI_Config.reticle = option
                UIDropDownMenu_SetText(reticleDropdown, option)
                if ER.ApplySettings then ER:ApplySettings() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(reticleDropdown, ThugUI_Config.reticle)

    -- Reticle Scale Slider
    local reticleScaleSlider = CreateFrame("Slider", "ThugUI_ReticleScaleSlider", content, "OptionsSliderTemplate")
    reticleScaleSlider:SetPoint("LEFT", reticleDropdown, "RIGHT", 20, 2)
    reticleScaleSlider:SetMinMaxValues(0.5, 3.0)
    reticleScaleSlider:SetValue(ThugUI_Config.reticleScale or 1.0)
    reticleScaleSlider:SetValueStep(0.1)
    reticleScaleSlider:SetObeyStepOnDrag(true)
    reticleScaleSlider:SetWidth(120)
    _G[reticleScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[reticleScaleSlider:GetName() .. "High"]:SetText("3.0")
    _G[reticleScaleSlider:GetName() .. "Text"]:SetText("Reticle Size")

    local reticleScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    reticleScaleValue:SetPoint("TOP", reticleScaleSlider, "BOTTOM", 0, -5)
    reticleScaleValue:SetText(string.format("%.1f", ThugUI_Config.reticleScale or 1.0))

    reticleScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 10 + 0.5) / 10
        reticleScaleValue:SetText(string.format("%.1f", rounded))
        ThugUI_Config.reticleScale = rounded
        if ER.UpdateReticle then ER:UpdateReticle() end
    end)

    -- Inner Ring Dropdown
    local innerDropdown = CreateSimpleDropdown(content, "ThugUI_InnerRingDropdown", "Inner Ring (Small)", ThugUI_Config.innerRing)
    innerDropdown:SetPoint("TOPLEFT", reticleDropdown, "BOTTOMLEFT", 0, -25)

    UIDropDownMenu_Initialize(innerDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(ER.ringOptions) do
            info.text = option
            info.checked = (ThugUI_Config.innerRing == option)
            info.func = function()
                ThugUI_Config.innerRing = option
                UIDropDownMenu_SetText(innerDropdown, option)
                if ER.ApplySettings then ER:ApplySettings() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Main Ring Dropdown
    local mainDropdown = CreateSimpleDropdown(content, "ThugUI_MainRingDropdown", "Main Ring (Medium)", ThugUI_Config.mainRing)
    mainDropdown:SetPoint("TOPLEFT", innerDropdown, "BOTTOMLEFT", 0, -25)

    UIDropDownMenu_Initialize(mainDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(ER.ringOptions) do
            info.text = option
            info.checked = (ThugUI_Config.mainRing == option)
            info.func = function()
                ThugUI_Config.mainRing = option
                UIDropDownMenu_SetText(mainDropdown, option)
                if ER.ApplySettings then ER:ApplySettings() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Outer Ring Dropdown
    local outerDropdown = CreateSimpleDropdown(content, "ThugUI_OuterRingDropdown", "Outer Ring (Large)", ThugUI_Config.outerRing)
    outerDropdown:SetPoint("TOPLEFT", mainDropdown, "BOTTOMLEFT", 0, -25)

    UIDropDownMenu_Initialize(outerDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(ER.ringOptions) do
            info.text = option
            info.value = option
            info.func = function(self) OnDropdownClick(self, outerDropdown, "outerRing") end
            info.checked = (ThugUI_Config.outerRing == option)
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- =====================
    -- 2. Rings Customization
    -- =====================
    local colorSeparator = CreateSeparator(content, "Rings Customization", "TOPLEFT", outerDropdown, 0, -40)

    -- Reticle Color
    local reticleColorDropdown, reticleColorButton = CreateColorModeDropdown(
        content, "Reticle Color:", "reticleColorMode", "reticleCustomColor",
        "TOPLEFT", colorSeparator, 0, -20,
        function() ER:UpdateReticle() end
    )

    -- Main Ring Color
    local mainRingColorDropdown, mainRingColorButton = CreateColorModeDropdown(
        content, "Main Ring Color:", "mainRingColorMode", "mainRingCustomColor",
        "TOPLEFT", reticleColorDropdown, 0, -25,
        function() ER:UpdateRingColors() end
    )

    -- GCD Color
    local gcdColorDropdown, gcdColorButton = CreateColorModeDropdown(
        content, "GCD Color:", "gcdColorMode", "gcdCustomColor",
        "TOPLEFT", mainRingColorDropdown, 0, -25,
        function() ER:UpdateRingColors() end
    )

    -- GCD Fill/Drain Dropdown
    local gcdFillDrainDropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    gcdFillDrainDropdown:SetPoint("LEFT", gcdColorButton, "RIGHT", 40, 0)
    UIDropDownMenu_SetWidth(gcdFillDrainDropdown, 120)

    local gcdFillDrainLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    gcdFillDrainLabel:SetPoint("BOTTOMLEFT", gcdFillDrainDropdown, "TOPLEFT", 20, 0)
    gcdFillDrainLabel:SetText("Fill/Drain:")

    UIDropDownMenu_Initialize(gcdFillDrainDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local options = {"Drain", "Fill (Default)"}
        local values = {"drain", "fill"}

        for i, option in ipairs(options) do
            info.text = option
            info.checked = (ThugUI_Config.gcdFillDrain == values[i])
            info.func = function()
                ThugUI_Config.gcdFillDrain = values[i]
                UIDropDownMenu_SetText(gcdFillDrainDropdown, option)
                ER:ResetCooldownFrames()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(gcdFillDrainDropdown, (ThugUI_Config.gcdFillDrain == "fill") and "Fill (Default)" or "Drain")

    -- GCD Rotation Slider
    local gcdRotationLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    gcdRotationLabel:SetPoint("LEFT", gcdFillDrainDropdown, "RIGHT", 20, 2)
    gcdRotationLabel:SetText("Start:")

    local gcdRotationSlider = CreateFrame("Slider", "ThugUI_GCDRotationSlider", content, "OptionsSliderTemplate")
    gcdRotationSlider:SetPoint("LEFT", gcdRotationLabel, "RIGHT", 10, 0)
    gcdRotationSlider:SetMinMaxValues(1, 12)
    gcdRotationSlider:SetValue(ThugUI_Config.gcdRotation or 12)
    gcdRotationSlider:SetValueStep(1)
    gcdRotationSlider:SetObeyStepOnDrag(true)
    gcdRotationSlider:SetWidth(100)
    _G[gcdRotationSlider:GetName() .. "Low"]:SetText("1")
    _G[gcdRotationSlider:GetName() .. "High"]:SetText("12")

    local gcdRotationValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    gcdRotationValue:SetPoint("TOP", gcdRotationSlider, "BOTTOM", 0, -5)
    gcdRotationValue:SetText(GetClockLabel(ThugUI_Config.gcdRotation or 12))

    gcdRotationSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value + 0.5)
        gcdRotationValue:SetText(GetClockLabel(rounded))
        ThugUI_Config.gcdRotation = rounded
        ER:ResetCooldownFrames()
    end)

    -- Cast Color
    local castColorDropdown, castColorButton = CreateColorModeDropdown(
        content, "Cast Color:", "castColorMode", "castCustomColor",
        "TOPLEFT", gcdColorDropdown, 0, -25,
        function() ER:UpdateRingColors() end
    )

    -- Cast Fill/Drain Dropdown
    local castFillDrainDropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    castFillDrainDropdown:SetPoint("LEFT", castColorButton, "RIGHT", 40, 0)
    UIDropDownMenu_SetWidth(castFillDrainDropdown, 120)

    local castFillDrainLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    castFillDrainLabel:SetPoint("BOTTOMLEFT", castFillDrainDropdown, "TOPLEFT", 20, 0)
    castFillDrainLabel:SetText("Fill/Drain:")

    UIDropDownMenu_Initialize(castFillDrainDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local options = {"Drain", "Fill (Default)"}
        local values = {"drain", "fill"}

        for i, option in ipairs(options) do
            info.text = option
            info.checked = (ThugUI_Config.castFillDrain == values[i])
            info.func = function()
                ThugUI_Config.castFillDrain = values[i]
                UIDropDownMenu_SetText(castFillDrainDropdown, option)
                ER:ResetCooldownFrames()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(castFillDrainDropdown, (ThugUI_Config.castFillDrain == "fill") and "Fill (Default)" or "Drain")

    -- Cast Rotation Slider
    local castRotationLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castRotationLabel:SetPoint("LEFT", castFillDrainDropdown, "RIGHT", 20, 2)
    castRotationLabel:SetText("Start:")

    local castRotationSlider = CreateFrame("Slider", "ThugUI_CastRotationSlider", content, "OptionsSliderTemplate")
    castRotationSlider:SetPoint("LEFT", castRotationLabel, "RIGHT", 10, 0)
    castRotationSlider:SetMinMaxValues(1, 12)
    castRotationSlider:SetValue(ThugUI_Config.castRotation or 12)
    castRotationSlider:SetValueStep(1)
    castRotationSlider:SetObeyStepOnDrag(true)
    castRotationSlider:SetWidth(100)
    _G[castRotationSlider:GetName() .. "Low"]:SetText("1")
    _G[castRotationSlider:GetName() .. "High"]:SetText("12")

    local castRotationValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    castRotationValue:SetPoint("TOP", castRotationSlider, "BOTTOM", 0, -5)
    castRotationValue:SetText(GetClockLabel(ThugUI_Config.castRotation or 12))

    castRotationSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value + 0.5)
        castRotationValue:SetText(GetClockLabel(rounded))
        ThugUI_Config.castRotation = rounded
        ER:ResetCooldownFrames()
    end)

    -- =====================
    -- 3. Visibility
    -- =====================
    local combatSeparator = CreateSeparator(content, "Visibility", "TOPLEFT", castColorDropdown, 0, -40)

    local combatDropdown = CreateFrame("Frame", "ThugUI_CombatDropdown", content, "UIDropDownMenuTemplate")
    combatDropdown:SetPoint("TOPLEFT", combatSeparator, "BOTTOMLEFT", 0, -35)
    UIDropDownMenu_SetWidth(combatDropdown, 120)

    local combatLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    combatLabel:SetPoint("BOTTOMLEFT", combatDropdown, "TOPLEFT", 20, 0)
    combatLabel:SetText("Show")

    UIDropDownMenu_Initialize(combatDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "Always"
        info.checked = (not ThugUI_Config.showOnlyInCombat)
        info.func = function()
            ThugUI_Config.showOnlyInCombat = false
            UIDropDownMenu_SetText(combatDropdown, "Always")
            ER:ApplySettings()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "In combat"
        info.checked = (ThugUI_Config.showOnlyInCombat)
        info.func = function()
            ThugUI_Config.showOnlyInCombat = true
            UIDropDownMenu_SetText(combatDropdown, "In combat")
            ER:ApplySettings()
        end
        UIDropDownMenu_AddButton(info)
    end)

    UIDropDownMenu_SetText(combatDropdown, ThugUI_Config.showOnlyInCombat and "In combat" or "Always")

    -- Hide Game Cursor Checkbox
    local hideCursorCheckbox = CreateFrame("CheckButton", "ThugUI_HideCursorCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    hideCursorCheckbox:SetPoint("LEFT", combatDropdown, "RIGHT", 140, 0)
    _G[hideCursorCheckbox:GetName() .. "Text"]:SetText("Hide game cursor when rings shown")
    hideCursorCheckbox:SetChecked(ThugUI_Config.hideGameCursor or false)
    hideCursorCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.hideGameCursor = self:GetChecked()
        ER:UpdateVisibility()
    end)

    -- Transparency Slider
    local transparencyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    transparencyLabel:SetPoint("TOPLEFT", combatDropdown, "BOTTOMLEFT", 0, -20)
    transparencyLabel:SetText("Transparency:")

    local transparencySlider = CreateFrame("Slider", "ThugUI_TransparencySlider", content, "OptionsSliderTemplate")
    transparencySlider:SetPoint("LEFT", transparencyLabel, "RIGHT", 10, 0)
    transparencySlider:SetMinMaxValues(0.1, 1.0)
    transparencySlider:SetValue(ThugUI_Config.transparency or 1.0)
    transparencySlider:SetValueStep(0.05)
    transparencySlider:SetObeyStepOnDrag(true)
    transparencySlider:SetWidth(150)
    _G[transparencySlider:GetName() .. "Low"]:SetText("10%")
    _G[transparencySlider:GetName() .. "High"]:SetText("100%")

    local transparencyValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    transparencyValue:SetPoint("TOP", transparencySlider, "BOTTOM", 0, -5)
    transparencyValue:SetText(string.format("%.0f%%", (ThugUI_Config.transparency or 1.0) * 100))

    transparencySlider:SetScript("OnValueChanged", function(self, value)
        ThugUI_Config.transparency = value
        transparencyValue:SetText(string.format("%.0f%%", value * 100))
        ER:ApplySettings()
    end)

    -- Scale Slider
    local scaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", transparencyLabel, "BOTTOMLEFT", 0, -40)
    scaleLabel:SetText("Scale:")

    local scaleSlider = CreateFrame("Slider", "ThugUI_ScaleSlider", content, "OptionsSliderTemplate")
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", 55, 0)
    scaleSlider:SetMinMaxValues(0.5, 4.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetValue(ThugUI_Config.scale)
    scaleSlider:SetWidth(150)
    _G["ThugUI_ScaleSliderLow"]:SetText("0.5")
    _G["ThugUI_ScaleSliderHigh"]:SetText("4.0")

    local scaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    scaleValue:SetPoint("TOP", scaleSlider, "BOTTOM", 0, -5)
    scaleValue:SetText(string.format("%.1f", ThugUI_Config.scale))

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 10 + 0.5) / 10
        scaleValue:SetText(string.format("%.1f", rounded))
        ThugUI_Config.scale = rounded
        ER:ApplySettings()
    end)

    -- =====================
    -- 4. Reset (Rings)
    -- =====================
    local resetSeparator = CreateSeparator(content, "Reset", "TOPLEFT", scaleLabel, -16, -50)

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(180, 25)
    resetButton:SetPoint("TOPLEFT", resetSeparator, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Ring Settings")
    resetButton:SetScript("OnClick", function()
        local ringKeys = {
            "scale", "reticle", "reticleScale", "innerRing", "mainRing", "outerRing",
            "showOnlyInCombat", "hideGameCursor", "transparency",
            "reticleColorMode", "reticleCustomColor",
            "mainRingColorMode", "mainRingCustomColor",
            "gcdColorMode", "gcdCustomColor", "gcdFillDrain", "gcdRotation",
            "castColorMode", "castCustomColor", "castFillDrain", "castRotation",
        }
        for _, key in ipairs(ringKeys) do
            ThugUI_Config[key] = ER.defaults[key]
        end

        -- Update all UI elements
        scaleSlider:SetValue(ThugUI_Config.scale)
        scaleValue:SetText(string.format("%.1f", ThugUI_Config.scale))
        UIDropDownMenu_SetText(innerDropdown, ThugUI_Config.innerRing)
        UIDropDownMenu_SetText(mainDropdown, ThugUI_Config.mainRing)
        UIDropDownMenu_SetText(outerDropdown, ThugUI_Config.outerRing)

        local reticleMode = ThugUI_Config.reticleColorMode or "default"
        local reticleModeText = reticleMode == "default" and "Default (White)" or
                               reticleMode == "class" and "Class Color" or "Custom Color"
        UIDropDownMenu_SetText(reticleColorDropdown, reticleModeText)
        reticleColorButton:UpdateColor()
        reticleColorButton:Disable()
        reticleColorButton:SetAlpha(0.5)

        local mainRingMode = ThugUI_Config.mainRingColorMode or "default"
        local mainRingModeText = mainRingMode == "default" and "Default (White)" or
                                mainRingMode == "class" and "Class Color" or "Custom Color"
        UIDropDownMenu_SetText(mainRingColorDropdown, mainRingModeText)
        mainRingColorButton:UpdateColor()
        mainRingColorButton:Disable()
        mainRingColorButton:SetAlpha(0.5)

        local gcdMode = ThugUI_Config.gcdColorMode or "default"
        local gcdModeText = gcdMode == "default" and "Default (White)" or
                           gcdMode == "class" and "Class Color" or "Custom Color"
        UIDropDownMenu_SetText(gcdColorDropdown, gcdModeText)
        gcdColorButton:UpdateColor()
        gcdColorButton:Disable()
        gcdColorButton:SetAlpha(0.5)

        local castMode = ThugUI_Config.castColorMode or "default"
        local castModeText = castMode == "default" and "Default (White)" or
                            castMode == "class" and "Class Color" or "Custom Color"
        UIDropDownMenu_SetText(castColorDropdown, castModeText)
        castColorButton:UpdateColor()
        castColorButton:Disable()
        castColorButton:SetAlpha(0.5)

        UIDropDownMenu_SetText(combatDropdown, ThugUI_Config.showOnlyInCombat and "In combat" or "Always")
        hideCursorCheckbox:SetChecked(ThugUI_Config.hideGameCursor or false)
        UIDropDownMenu_SetText(reticleDropdown, ThugUI_Config.reticle)
        reticleScaleSlider:SetValue(ThugUI_Config.reticleScale)
        reticleScaleValue:SetText(string.format("%.1f", ThugUI_Config.reticleScale))
        transparencySlider:SetValue(ThugUI_Config.transparency)
        transparencyValue:SetText(string.format("%.0f%%", ThugUI_Config.transparency * 100))

        UIDropDownMenu_SetText(gcdFillDrainDropdown, (ThugUI_Config.gcdFillDrain == "fill") and "Fill (Default)" or "Drain")
        UIDropDownMenu_SetText(castFillDrainDropdown, (ThugUI_Config.castFillDrain == "fill") and "Fill (Default)" or "Drain")
        gcdRotationSlider:SetValue(ThugUI_Config.gcdRotation or 12)
        gcdRotationValue:SetText(GetClockLabel(ThugUI_Config.gcdRotation or 12))
        castRotationSlider:SetValue(ThugUI_Config.castRotation or 12)
        castRotationValue:SetText(GetClockLabel(ThugUI_Config.castRotation or 12))

        ER:ApplySettings()
        print("|cff00ff00ThugUI:|r Ring settings reset to defaults.")
    end)

    -- Register as subcategory
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    subcategory.ID = "ThugUI_CursorRings"
end

-- ============================================================================
-- COOLDOWN VIEWER SUB-PANEL
-- ============================================================================

function ER:CreateECVPanel(parentCategory)
    local panel = CreateFrame("Frame", "ThugUI_ECVPanel")
    panel.name = "Cooldown Viewer"
    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    local content = CreateScrollablePanel(panel, 1400)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Essential Cooldown Viewer")

    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("A bar of spell icons showing which abilities are ready.")

    -- =====================
    -- Settings
    -- =====================
    local settingsSeparator = CreateSeparator(content, "Settings", "TOPLEFT", desc, 0, -20)

    local showECVCheckbox = CreateFrame("CheckButton", "ThugUI_ShowECVCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    showECVCheckbox:SetPoint("TOPLEFT", settingsSeparator, "BOTTOMLEFT", 20, -15)
    _G[showECVCheckbox:GetName() .. "Text"]:SetText("Enable Cooldown Viewer")
    showECVCheckbox:SetChecked(ThugUI_Config.showECV or false)
    showECVCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.showECV = self:GetChecked()
        ER:UpdateECVVisibility()
    end)

    local ecvCombatCheckbox = CreateFrame("CheckButton", "ThugUI_ECVCombatCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    ecvCombatCheckbox:SetPoint("TOPLEFT", showECVCheckbox, "BOTTOMLEFT", 0, -5)
    _G[ecvCombatCheckbox:GetName() .. "Text"]:SetText("Show only during combat")
    ecvCombatCheckbox:SetChecked(ThugUI_Config.ecvShowOnlyInCombat or false)
    ecvCombatCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.ecvShowOnlyInCombat = self:GetChecked()
        ER:UpdateECVVisibility()
    end)

    local ecvAnchorCheckbox = CreateFrame("CheckButton", "ThugUI_ECVAnchorCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    ecvAnchorCheckbox:SetPoint("TOPLEFT", ecvCombatCheckbox, "BOTTOMLEFT", 0, -5)
    _G[ecvAnchorCheckbox:GetName() .. "Text"]:SetText("Follow cursor during combat")
    ecvAnchorCheckbox:SetChecked(ThugUI_Config.anchorECVToCursor or false)
    ecvAnchorCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.anchorECVToCursor = self:GetChecked()
        if not self:GetChecked() then
            ER:ReleaseECVAnchor()
        end
    end)

    -- Position note
    local posNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    posNote:SetPoint("TOPLEFT", ecvAnchorCheckbox, "BOTTOMLEFT", 20, -10)
    posNote:SetText("Drag the bar to reposition when out of combat.")

    -- =====================
    -- Appearance
    -- =====================
    local appearSeparator = CreateSeparator(content, "Appearance", "TOPLEFT", posNote, -36, -20)

    -- Scale slider
    local ecvScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ecvScaleLabel:SetPoint("TOPLEFT", appearSeparator, "BOTTOMLEFT", 0, -15)
    ecvScaleLabel:SetText("Bar Scale:")

    local ecvScaleSlider = CreateFrame("Slider", "ThugUI_ECVScaleSlider", content, "OptionsSliderTemplate")
    ecvScaleSlider:SetPoint("LEFT", ecvScaleLabel, "RIGHT", 15, 0)
    ecvScaleSlider:SetMinMaxValues(0.5, 2.0)
    ecvScaleSlider:SetValue(ThugUI_Config.ecvScale or 1.0)
    ecvScaleSlider:SetValueStep(0.05)
    ecvScaleSlider:SetObeyStepOnDrag(true)
    ecvScaleSlider:SetWidth(150)
    _G[ecvScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[ecvScaleSlider:GetName() .. "High"]:SetText("2.0")
    _G[ecvScaleSlider:GetName() .. "Text"]:SetText("")

    local ecvScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ecvScaleValue:SetPoint("TOP", ecvScaleSlider, "BOTTOM", 0, -5)
    ecvScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvScale or 1.0))

    ecvScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 20 + 0.5) / 20  -- snap to 0.05
        ecvScaleValue:SetText(string.format("%.2f", rounded))
        ThugUI_Config.ecvScale = rounded
        if ER.ecvContainer then
            ER.ecvContainer:SetScale(rounded)
        end
    end)

    -- Cursor anchor corner dropdown
    local cornerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cornerLabel:SetPoint("TOPLEFT", ecvScaleLabel, "BOTTOMLEFT", 0, -25)
    cornerLabel:SetText("Cursor Anchor Corner:")

    local cornerNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    cornerNote:SetPoint("TOPLEFT", cornerLabel, "BOTTOMLEFT", 0, -3)
    cornerNote:SetText("Which corner of the bar attaches to the cursor when following.")

    local cornerDropdown = CreateFrame("Frame", "ThugUI_ECVCornerDropdown", content, "UIDropDownMenuTemplate")
    cornerDropdown:SetPoint("TOPLEFT", cornerNote, "BOTTOMLEFT", -16, -5)
    UIDropDownMenu_SetWidth(cornerDropdown, 140)

    local cornerLabels = {
        TOPLEFT = "Top Left",
        TOPRIGHT = "Top Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOMRIGHT = "Bottom Right",
    }
    local cornerOrder = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

    UIDropDownMenu_Initialize(cornerDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, corner in ipairs(cornerOrder) do
            info.text = cornerLabels[corner]
            info.checked = (ThugUI_Config.ecvAnchorCorner == corner)
            info.func = function()
                ThugUI_Config.ecvAnchorCorner = corner
                UIDropDownMenu_SetText(cornerDropdown, cornerLabels[corner])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(cornerDropdown, cornerLabels[ThugUI_Config.ecvAnchorCorner or "TOPLEFT"])

    -- =====================
    -- Abundance Tracker
    -- =====================
    local abundanceSeparator = CreateSeparator(content, "Abundance Tracker", "TOPLEFT", cornerDropdown, 0, -20)

    local abundanceCheckbox = CreateFrame("CheckButton", "ThugUI_ECVAbundanceCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    abundanceCheckbox:SetPoint("TOPLEFT", abundanceSeparator, "BOTTOMLEFT", 20, -15)
    _G[abundanceCheckbox:GetName() .. "Text"]:SetText("Show Abundance icon")
    abundanceCheckbox:SetChecked(ThugUI_Config.ecvShowAbundance)
    abundanceCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.ecvShowAbundance = self:GetChecked()
        if ER.UpdateAbundanceStacks then ER:UpdateAbundanceStacks() end
    end)

    local abundanceNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    abundanceNote:SetPoint("TOPLEFT", abundanceCheckbox, "BOTTOMLEFT", 20, -2)
    abundanceNote:SetText("Shows the Abundance spell icon near the cursor when the buff is active.")

    local abCornerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    abCornerLabel:SetPoint("TOPLEFT", abundanceNote, "BOTTOMLEFT", -20, -10)
    abCornerLabel:SetText("Cursor Corner:")

    local abCornerDropdown = CreateFrame("Frame", "ThugUI_ECVAbCornerDropdown", content, "UIDropDownMenuTemplate")
    abCornerDropdown:SetPoint("LEFT", abCornerLabel, "RIGHT", 5, -2)
    UIDropDownMenu_SetWidth(abCornerDropdown, 140)

    local abCornerLabels = {TOPLEFT = "Top Left", TOPRIGHT = "Top Right", BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right"}
    local abCornerOrder = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

    UIDropDownMenu_Initialize(abCornerDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, corner in ipairs(abCornerOrder) do
            info.text = abCornerLabels[corner]
            info.checked = (ThugUI_Config.ecvAbundanceCorner == corner)
            info.func = function()
                ThugUI_Config.ecvAbundanceCorner = corner
                UIDropDownMenu_SetText(abCornerDropdown, abCornerLabels[corner])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(abCornerDropdown, abCornerLabels[ThugUI_Config.ecvAbundanceCorner or "TOPLEFT"])

    local abScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    abScaleLabel:SetPoint("TOPLEFT", abCornerLabel, "BOTTOMLEFT", 0, -15)
    abScaleLabel:SetText("Icon Scale:")

    local abScaleSlider = CreateFrame("Slider", "ThugUI_ECVAbScaleSlider", content, "OptionsSliderTemplate")
    abScaleSlider:SetPoint("LEFT", abScaleLabel, "RIGHT", 15, 0)
    abScaleSlider:SetWidth(140)
    abScaleSlider:SetMinMaxValues(0.5, 2.5)
    abScaleSlider:SetValueStep(0.05)
    abScaleSlider:SetObeyStepOnDrag(true)
    abScaleSlider:SetValue(ThugUI_Config.ecvAbundanceScale or 1.0)
    _G[abScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[abScaleSlider:GetName() .. "High"]:SetText("2.5")

    local abScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    abScaleValue:SetPoint("LEFT", abScaleSlider, "RIGHT", 10, 0)
    abScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvAbundanceScale or 1.0))

    abScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 20 + 0.5) / 20
        ThugUI_Config.ecvAbundanceScale = rounded
        abScaleValue:SetText(string.format("%.2f", rounded))
        if ER.ecvAbundanceFrame then ER.ecvAbundanceFrame:SetScale(rounded) end
    end)

    -- =====================
    -- Reforestation Tracker
    -- =====================
    local reforestSeparator = CreateSeparator(content, "Reforestation Tracker", "TOPLEFT", abScaleLabel, 0, -20)

    local reforestCheckbox = CreateFrame("CheckButton", "ThugUI_ECVReforestCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    reforestCheckbox:SetPoint("TOPLEFT", reforestSeparator, "BOTTOMLEFT", 20, -15)
    _G[reforestCheckbox:GetName() .. "Text"]:SetText("Show Reforestation icon")
    reforestCheckbox:SetChecked(ThugUI_Config.ecvShowReforestation)
    reforestCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.ecvShowReforestation = self:GetChecked()
        if ER.UpdateReforestationStacks then ER:UpdateReforestationStacks() end
    end)

    local reforestNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    reforestNote:SetPoint("TOPLEFT", reforestCheckbox, "BOTTOMLEFT", 20, -2)
    reforestNote:SetText("Shows the Reforestation spell icon near the cursor when the buff is active.")

    local rfCornerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rfCornerLabel:SetPoint("TOPLEFT", reforestNote, "BOTTOMLEFT", -20, -10)
    rfCornerLabel:SetText("Cursor Corner:")

    local rfCornerDropdown = CreateFrame("Frame", "ThugUI_ECVRfCornerDropdown", content, "UIDropDownMenuTemplate")
    rfCornerDropdown:SetPoint("LEFT", rfCornerLabel, "RIGHT", 5, -2)
    UIDropDownMenu_SetWidth(rfCornerDropdown, 140)

    local rfCornerLabels = {TOPLEFT = "Top Left", TOPRIGHT = "Top Right", BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right"}
    local rfCornerOrder = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

    UIDropDownMenu_Initialize(rfCornerDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, corner in ipairs(rfCornerOrder) do
            info.text = rfCornerLabels[corner]
            info.checked = (ThugUI_Config.ecvReforestationCorner == corner)
            info.func = function()
                ThugUI_Config.ecvReforestationCorner = corner
                UIDropDownMenu_SetText(rfCornerDropdown, rfCornerLabels[corner])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(rfCornerDropdown, rfCornerLabels[ThugUI_Config.ecvReforestationCorner or "TOPRIGHT"])

    local rfScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rfScaleLabel:SetPoint("TOPLEFT", rfCornerLabel, "BOTTOMLEFT", 0, -15)
    rfScaleLabel:SetText("Icon Scale:")

    local rfScaleSlider = CreateFrame("Slider", "ThugUI_ECVRfScaleSlider", content, "OptionsSliderTemplate")
    rfScaleSlider:SetPoint("LEFT", rfScaleLabel, "RIGHT", 15, 0)
    rfScaleSlider:SetWidth(140)
    rfScaleSlider:SetMinMaxValues(0.5, 2.5)
    rfScaleSlider:SetValueStep(0.05)
    rfScaleSlider:SetObeyStepOnDrag(true)
    rfScaleSlider:SetValue(ThugUI_Config.ecvReforestationScale or 1.0)
    _G[rfScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[rfScaleSlider:GetName() .. "High"]:SetText("2.5")

    local rfScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rfScaleValue:SetPoint("LEFT", rfScaleSlider, "RIGHT", 10, 0)
    rfScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvReforestationScale or 1.0))

    rfScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 20 + 0.5) / 20
        ThugUI_Config.ecvReforestationScale = rounded
        rfScaleValue:SetText(string.format("%.2f", rounded))
        if ER.ecvReforestationFrame then ER.ecvReforestationFrame:SetScale(rounded) end
    end)

    -- =====================
    -- Clearcasting Tracker
    -- =====================
    local ccSeparator = CreateSeparator(content, "Clearcasting Tracker", "TOPLEFT", rfScaleLabel, 0, -20)

    local ccCheckbox = CreateFrame("CheckButton", "ThugUI_ECVClearcastCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    ccCheckbox:SetPoint("TOPLEFT", ccSeparator, "BOTTOMLEFT", 20, -15)
    _G[ccCheckbox:GetName() .. "Text"]:SetText("Show Clearcasting icon")
    ccCheckbox:SetChecked(ThugUI_Config.ecvShowClearcasting)
    ccCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.ecvShowClearcasting = self:GetChecked()
        if ER.UpdateClearcastingTimer then ER:UpdateClearcastingTimer() end
    end)

    local ccNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ccNote:SetPoint("TOPLEFT", ccCheckbox, "BOTTOMLEFT", 20, -2)
    ccNote:SetText("Shows the Clearcasting spell icon near the cursor with cooldown sweep.")

    local ccCornerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ccCornerLabel:SetPoint("TOPLEFT", ccNote, "BOTTOMLEFT", -20, -10)
    ccCornerLabel:SetText("Cursor Corner:")

    local ccCornerDropdown = CreateFrame("Frame", "ThugUI_ECVCcCornerDropdown", content, "UIDropDownMenuTemplate")
    ccCornerDropdown:SetPoint("LEFT", ccCornerLabel, "RIGHT", 5, -2)
    UIDropDownMenu_SetWidth(ccCornerDropdown, 140)

    local ccCornerLabels = {TOPLEFT = "Top Left", TOPRIGHT = "Top Right", BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right"}
    local ccCornerOrder = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

    UIDropDownMenu_Initialize(ccCornerDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, corner in ipairs(ccCornerOrder) do
            info.text = ccCornerLabels[corner]
            info.checked = (ThugUI_Config.ecvClearcastingCorner == corner)
            info.func = function()
                ThugUI_Config.ecvClearcastingCorner = corner
                UIDropDownMenu_SetText(ccCornerDropdown, ccCornerLabels[corner])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(ccCornerDropdown, ccCornerLabels[ThugUI_Config.ecvClearcastingCorner or "BOTTOMLEFT"])

    local ccScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ccScaleLabel:SetPoint("TOPLEFT", ccCornerLabel, "BOTTOMLEFT", 0, -15)
    ccScaleLabel:SetText("Icon Scale:")

    local ccScaleSlider = CreateFrame("Slider", "ThugUI_ECVCcScaleSlider", content, "OptionsSliderTemplate")
    ccScaleSlider:SetPoint("LEFT", ccScaleLabel, "RIGHT", 15, 0)
    ccScaleSlider:SetWidth(140)
    ccScaleSlider:SetMinMaxValues(0.5, 2.5)
    ccScaleSlider:SetValueStep(0.05)
    ccScaleSlider:SetObeyStepOnDrag(true)
    ccScaleSlider:SetValue(ThugUI_Config.ecvClearcastingScale or 1.0)
    _G[ccScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[ccScaleSlider:GetName() .. "High"]:SetText("2.5")

    local ccScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ccScaleValue:SetPoint("LEFT", ccScaleSlider, "RIGHT", 10, 0)
    ccScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvClearcastingScale or 1.0))

    ccScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 20 + 0.5) / 20
        ThugUI_Config.ecvClearcastingScale = rounded
        ccScaleValue:SetText(string.format("%.2f", rounded))
        if ER.ecvClearcastingFrame then ER.ecvClearcastingFrame:SetScale(rounded) end
    end)

    -- =====================
    -- Tracked Buff Frame (Blizzard)
    -- =====================
    local buffFrameSeparator = CreateSeparator(content, "Tracked Buff Frame", "TOPLEFT", ccScaleLabel, 0, -20)

    local buffFrameCheckbox = CreateFrame("CheckButton", "ThugUI_ECVBuffFrameCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    buffFrameCheckbox:SetPoint("TOPLEFT", buffFrameSeparator, "BOTTOMLEFT", 20, -15)
    _G[buffFrameCheckbox:GetName() .. "Text"]:SetText("Anchor buff frame to cursor")
    buffFrameCheckbox:SetChecked(ThugUI_Config.anchorBuffFrameToCursor)
    buffFrameCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.anchorBuffFrameToCursor = self:GetChecked()
    end)

    local buffFrameNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    buffFrameNote:SetPoint("TOPLEFT", buffFrameCheckbox, "BOTTOMLEFT", 20, -2)
    buffFrameNote:SetText("Attaches the Blizzard tracked buff bar (BuffIconCooldownViewer) to the cursor\nduring combat. Buffs you track via Edit Mode will follow your cursor.")

    local bfCornerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bfCornerLabel:SetPoint("TOPLEFT", buffFrameNote, "BOTTOMLEFT", -20, -10)
    bfCornerLabel:SetText("Cursor Corner:")

    local bfCornerDropdown = CreateFrame("Frame", "ThugUI_ECVBfCornerDropdown", content, "UIDropDownMenuTemplate")
    bfCornerDropdown:SetPoint("LEFT", bfCornerLabel, "RIGHT", 5, -2)
    UIDropDownMenu_SetWidth(bfCornerDropdown, 140)

    local bfCornerLabels = {TOPLEFT = "Top Left", TOPRIGHT = "Top Right", BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right"}
    local bfCornerOrder = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

    UIDropDownMenu_Initialize(bfCornerDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, corner in ipairs(bfCornerOrder) do
            info.text = bfCornerLabels[corner]
            info.checked = (ThugUI_Config.buffFrameCorner == corner)
            info.func = function()
                ThugUI_Config.buffFrameCorner = corner
                UIDropDownMenu_SetText(bfCornerDropdown, bfCornerLabels[corner])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(bfCornerDropdown, bfCornerLabels[ThugUI_Config.buffFrameCorner or "BOTTOMRIGHT"])

    local bfScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bfScaleLabel:SetPoint("TOPLEFT", bfCornerLabel, "BOTTOMLEFT", 0, -15)
    bfScaleLabel:SetText("Frame Scale:")

    local bfScaleSlider = CreateFrame("Slider", "ThugUI_ECVBfScaleSlider", content, "OptionsSliderTemplate")
    bfScaleSlider:SetPoint("LEFT", bfScaleLabel, "RIGHT", 15, 0)
    bfScaleSlider:SetWidth(140)
    bfScaleSlider:SetMinMaxValues(0.2, 2.5)
    bfScaleSlider:SetValueStep(0.05)
    bfScaleSlider:SetObeyStepOnDrag(true)
    bfScaleSlider:SetValue(ThugUI_Config.buffFrameScale or 1.0)
    _G[bfScaleSlider:GetName() .. "Low"]:SetText("0.2")
    _G[bfScaleSlider:GetName() .. "High"]:SetText("2.5")

    local bfScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bfScaleValue:SetPoint("LEFT", bfScaleSlider, "RIGHT", 10, 0)
    bfScaleValue:SetText(string.format("%.2f", ThugUI_Config.buffFrameScale or 1.0))

    bfScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 20 + 0.5) / 20
        ThugUI_Config.buffFrameScale = rounded
        bfScaleValue:SetText(string.format("%.2f", rounded))
        local buffFrame = _G["BuffIconCooldownViewer"]
        if buffFrame then buffFrame:SetScale(rounded) end
    end)

    -- =====================
    -- Tracked Spells
    -- =====================
    local spellsSeparator = CreateSeparator(content, "Tracked Spells", "TOPLEFT", bfScaleLabel, 0, -20)

    local spellsNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    spellsNote:SetPoint("TOPLEFT", spellsSeparator, "BOTTOMLEFT", 0, -10)
    spellsNote:SetText("Currently tracking: Wild Growth, Swiftmend, Nature's Swiftness,\nIronbark, Convoke the Spirits, Tranquility")

    local futureNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    futureNote:SetPoint("TOPLEFT", spellsNote, "BOTTOMLEFT", 0, -8)
    futureNote:SetText("Spell selection from spellbook coming in a future update.")

    -- =====================
    -- Reset
    -- =====================
    local resetSeparator = CreateSeparator(content, "Reset", "TOPLEFT", futureNote, 0, -20)

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(220, 25)
    resetButton:SetPoint("TOPLEFT", resetSeparator, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Cooldown Viewer Settings")
    resetButton:SetScript("OnClick", function()
        local ecvKeys = {
            "showECV", "ecvShowOnlyInCombat", "anchorECVToCursor", "ecvPoint",
            "ecvScale", "ecvAnchorCorner",
            "ecvShowAbundance", "ecvAbundanceCorner", "ecvAbundanceScale",
            "ecvShowReforestation", "ecvReforestationCorner", "ecvReforestationScale",
            "ecvShowClearcasting", "ecvClearcastingCorner", "ecvClearcastingScale",
            "anchorBuffFrameToCursor", "buffFrameCorner", "buffFrameScale",
        }
        for _, key in ipairs(ecvKeys) do
            ThugUI_Config[key] = ER.defaults[key]
        end

        showECVCheckbox:SetChecked(ThugUI_Config.showECV or false)
        ecvCombatCheckbox:SetChecked(ThugUI_Config.ecvShowOnlyInCombat or false)
        ecvAnchorCheckbox:SetChecked(ThugUI_Config.anchorECVToCursor or false)
        ecvScaleSlider:SetValue(ThugUI_Config.ecvScale or 1.0)
        ecvScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvScale or 1.0))
        UIDropDownMenu_SetText(cornerDropdown, cornerLabels[ThugUI_Config.ecvAnchorCorner or "TOPLEFT"])
        abundanceCheckbox:SetChecked(ThugUI_Config.ecvShowAbundance)
        UIDropDownMenu_SetText(abCornerDropdown, abCornerLabels[ThugUI_Config.ecvAbundanceCorner or "TOPLEFT"])
        abScaleSlider:SetValue(ThugUI_Config.ecvAbundanceScale or 1.0)
        abScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvAbundanceScale or 1.0))
        reforestCheckbox:SetChecked(ThugUI_Config.ecvShowReforestation)
        UIDropDownMenu_SetText(rfCornerDropdown, rfCornerLabels[ThugUI_Config.ecvReforestationCorner or "TOPRIGHT"])
        rfScaleSlider:SetValue(ThugUI_Config.ecvReforestationScale or 1.0)
        rfScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvReforestationScale or 1.0))
        ccCheckbox:SetChecked(ThugUI_Config.ecvShowClearcasting)
        UIDropDownMenu_SetText(ccCornerDropdown, ccCornerLabels[ThugUI_Config.ecvClearcastingCorner or "BOTTOMLEFT"])
        ccScaleSlider:SetValue(ThugUI_Config.ecvClearcastingScale or 1.0)
        ccScaleValue:SetText(string.format("%.2f", ThugUI_Config.ecvClearcastingScale or 1.0))
        buffFrameCheckbox:SetChecked(ThugUI_Config.anchorBuffFrameToCursor)
        UIDropDownMenu_SetText(bfCornerDropdown, bfCornerLabels[ThugUI_Config.buffFrameCorner or "BOTTOMRIGHT"])
        bfScaleSlider:SetValue(ThugUI_Config.buffFrameScale or 1.0)
        bfScaleValue:SetText(string.format("%.2f", ThugUI_Config.buffFrameScale or 1.0))

        -- Reset position and scale to default
        if ER.ecvContainer then
            ER.ecvContainer:ClearAllPoints()
            ER.ecvContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
            ER.ecvContainer:SetScale(ThugUI_Config.ecvScale or 1.0)
        end

        if ER.ecvAbundanceFrame then ER.ecvAbundanceFrame:SetScale(ThugUI_Config.ecvAbundanceScale or 1.0) end
        if ER.ecvReforestationFrame then ER.ecvReforestationFrame:SetScale(ThugUI_Config.ecvReforestationScale or 1.0) end
        if ER.ecvClearcastingFrame then ER.ecvClearcastingFrame:SetScale(ThugUI_Config.ecvClearcastingScale or 1.0) end
        if ER.UpdateAbundanceStacks then ER:UpdateAbundanceStacks() end
        if ER.UpdateReforestationStacks then ER:UpdateReforestationStacks() end
        if ER.UpdateClearcastingTimer then ER:UpdateClearcastingTimer() end
        ER:ApplySettings()
        print("|cff00ff00ThugUI:|r Cooldown viewer settings reset to defaults.")
    end)

    -- Register as subcategory
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    subcategory.ID = "ThugUI_CooldownViewer"
end

-- ============================================================================
-- BALANCE COOLDOWN VIEWER SUB-PANEL
-- ============================================================================

function ER:CreateBCVPanel(parentCategory)
    local panel = CreateFrame("Frame", "ThugUI_BCVPanel")
    panel.name = "Balance Cooldown Viewer"
    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    local content = CreateScrollablePanel(panel, 900)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Balance Cooldown Viewer")

    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("A second bar of ready cooldowns, shown only in Balance spec.")

    -- =====================
    -- Settings
    -- =====================
    local settingsSeparator = CreateSeparator(content, "Settings", "TOPLEFT", desc, 0, -20)

    local showBCVCheckbox = CreateFrame("CheckButton", "ThugUI_ShowBCVCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    showBCVCheckbox:SetPoint("TOPLEFT", settingsSeparator, "BOTTOMLEFT", 20, -15)
    _G[showBCVCheckbox:GetName() .. "Text"]:SetText("Enable Balance Cooldown Viewer")
    showBCVCheckbox:SetChecked(ThugUI_Config.showBCV or false)
    showBCVCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.showBCV = self:GetChecked()
        ER:UpdateBCVVisibility()
    end)

    local bcvCombatCheckbox = CreateFrame("CheckButton", "ThugUI_BCVCombatCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    bcvCombatCheckbox:SetPoint("TOPLEFT", showBCVCheckbox, "BOTTOMLEFT", 0, -5)
    _G[bcvCombatCheckbox:GetName() .. "Text"]:SetText("Show only during combat")
    bcvCombatCheckbox:SetChecked(ThugUI_Config.bcvShowOnlyInCombat or false)
    bcvCombatCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.bcvShowOnlyInCombat = self:GetChecked()
        ER:UpdateBCVVisibility()
    end)

    local bcvAnchorCheckbox = CreateFrame("CheckButton", "ThugUI_BCVAnchorCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    bcvAnchorCheckbox:SetPoint("TOPLEFT", bcvCombatCheckbox, "BOTTOMLEFT", 0, -5)
    _G[bcvAnchorCheckbox:GetName() .. "Text"]:SetText("Follow cursor during combat")
    bcvAnchorCheckbox:SetChecked(ThugUI_Config.anchorBCVToCursor or false)
    bcvAnchorCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.anchorBCVToCursor = self:GetChecked()
        if not self:GetChecked() then
            ER:ReleaseBCVAnchor()
        end
    end)

    local bcvProcCheckbox = CreateFrame("CheckButton", "ThugUI_BCVProcCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    bcvProcCheckbox:SetPoint("TOPLEFT", bcvAnchorCheckbox, "BOTTOMLEFT", 0, -5)
    _G[bcvProcCheckbox:GetName() .. "Text"]:SetText("Show free-cast proc buffs on the bar")
    bcvProcCheckbox:SetChecked(ThugUI_Config.bcvShowStarsurgeProc)
    bcvProcCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.bcvShowStarsurgeProc = self:GetChecked()
        if ER.UpdateBCVCooldowns then ER:UpdateBCVCooldowns() end
    end)

    local procNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    procNote:SetPoint("TOPLEFT", bcvProcCheckbox, "BOTTOMLEFT", 20, -2)
    procNote:SetText("Shows Starweaver's Weft (free Starsurge), Starweaver's Warp (free Starfall),\nand Touch the Cosmos as their own icons whenever those buffs are active.")

    local posNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    posNote:SetPoint("TOPLEFT", procNote, "BOTTOMLEFT", 0, -8)
    posNote:SetText("Drag the bar to reposition when out of combat.")

    -- =====================
    -- Appearance
    -- =====================
    local appearSeparator = CreateSeparator(content, "Appearance", "TOPLEFT", posNote, -20, -20)

    local bcvScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bcvScaleLabel:SetPoint("TOPLEFT", appearSeparator, "BOTTOMLEFT", 0, -15)
    bcvScaleLabel:SetText("Bar Scale:")

    local bcvScaleSlider = CreateFrame("Slider", "ThugUI_BCVScaleSlider", content, "OptionsSliderTemplate")
    bcvScaleSlider:SetPoint("LEFT", bcvScaleLabel, "RIGHT", 15, 0)
    bcvScaleSlider:SetMinMaxValues(0.5, 2.0)
    bcvScaleSlider:SetValue(ThugUI_Config.bcvScale or 1.0)
    bcvScaleSlider:SetValueStep(0.05)
    bcvScaleSlider:SetObeyStepOnDrag(true)
    bcvScaleSlider:SetWidth(150)
    _G[bcvScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[bcvScaleSlider:GetName() .. "High"]:SetText("2.0")
    _G[bcvScaleSlider:GetName() .. "Text"]:SetText("")

    local bcvScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bcvScaleValue:SetPoint("LEFT", bcvScaleSlider, "RIGHT", 10, 0)
    bcvScaleValue:SetText(string.format("%.2f", ThugUI_Config.bcvScale or 1.0))

    bcvScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 20 + 0.5) / 20
        bcvScaleValue:SetText(string.format("%.2f", rounded))
        ThugUI_Config.bcvScale = rounded
        if ER.bcvContainer then ER.bcvContainer:SetScale(rounded) end
    end)

    local bcvCornerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bcvCornerLabel:SetPoint("TOPLEFT", bcvScaleLabel, "BOTTOMLEFT", 0, -25)
    bcvCornerLabel:SetText("Cursor Anchor Corner:")

    local bcvCornerNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    bcvCornerNote:SetPoint("TOPLEFT", bcvCornerLabel, "BOTTOMLEFT", 0, -3)
    bcvCornerNote:SetText("Which corner of the bar attaches to the cursor when following.")

    local bcvCornerDropdown = CreateFrame("Frame", "ThugUI_BCVCornerDropdown", content, "UIDropDownMenuTemplate")
    bcvCornerDropdown:SetPoint("TOPLEFT", bcvCornerNote, "BOTTOMLEFT", -16, -5)
    UIDropDownMenu_SetWidth(bcvCornerDropdown, 140)

    local bcvCornerLabels = {TOPLEFT = "Top Left", TOPRIGHT = "Top Right", BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right"}
    local bcvCornerOrder = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

    UIDropDownMenu_Initialize(bcvCornerDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, corner in ipairs(bcvCornerOrder) do
            info.text = bcvCornerLabels[corner]
            info.checked = (ThugUI_Config.bcvAnchorCorner == corner)
            info.func = function()
                ThugUI_Config.bcvAnchorCorner = corner
                UIDropDownMenu_SetText(bcvCornerDropdown, bcvCornerLabels[corner])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(bcvCornerDropdown, bcvCornerLabels[ThugUI_Config.bcvAnchorCorner or "TOPLEFT"])

    -- =====================
    -- Tracked Spells
    -- =====================
    local spellsSeparator = CreateSeparator(content, "Tracked Spells", "TOPLEFT", bcvCornerDropdown, 0, -20)

    local spellsNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    spellsNote:SetPoint("TOPLEFT", spellsSeparator, "BOTTOMLEFT", 0, -10)
    spellsNote:SetText("Fury of Elune, Force of Nature, Incarnation: Chosen of Elune, Eclipse,\nplus the Starsurge proc glow.")

    local talentNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    talentNote:SetPoint("TOPLEFT", spellsNote, "BOTTOMLEFT", 0, -8)
    talentNote:SetText("Talent abilities only appear when actually talented. Each icon shows only\nwhile its ability is ready (Eclipse: while a charge is available).")

    -- =====================
    -- Reset
    -- =====================
    local resetSeparator = CreateSeparator(content, "Reset", "TOPLEFT", talentNote, 0, -20)

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(240, 25)
    resetButton:SetPoint("TOPLEFT", resetSeparator, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Balance Viewer Settings")
    resetButton:SetScript("OnClick", function()
        local bcvKeys = {
            "showBCV", "bcvShowOnlyInCombat", "anchorBCVToCursor",
            "bcvAnchorCorner", "bcvScale", "bcvPoint", "bcvShowStarsurgeProc",
        }
        for _, key in ipairs(bcvKeys) do
            ThugUI_Config[key] = ER.defaults[key]
        end

        showBCVCheckbox:SetChecked(ThugUI_Config.showBCV or false)
        bcvCombatCheckbox:SetChecked(ThugUI_Config.bcvShowOnlyInCombat or false)
        bcvAnchorCheckbox:SetChecked(ThugUI_Config.anchorBCVToCursor or false)
        bcvProcCheckbox:SetChecked(ThugUI_Config.bcvShowStarsurgeProc)
        bcvScaleSlider:SetValue(ThugUI_Config.bcvScale or 1.0)
        bcvScaleValue:SetText(string.format("%.2f", ThugUI_Config.bcvScale or 1.0))
        UIDropDownMenu_SetText(bcvCornerDropdown, bcvCornerLabels[ThugUI_Config.bcvAnchorCorner or "TOPLEFT"])

        if ER.bcvContainer then
            ER.bcvContainer:ClearAllPoints()
            ER.bcvContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
            ER.bcvContainer:SetScale(ThugUI_Config.bcvScale or 1.0)
        end
        ER:UpdateBCVVisibility()
        print("|cff00ff00ThugUI:|r Balance viewer settings reset to defaults.")
    end)

    -- Register as subcategory
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    subcategory.ID = "ThugUI_BalanceCooldownViewer"
end

-- ============================================================================
-- GUARDIAN COOLDOWN VIEWER SUB-PANEL
-- ============================================================================

function ER:CreateGCVPanel(parentCategory)
    local panel = CreateFrame("Frame", "ThugUI_GCVPanel")
    panel.name = "Guardian Cooldown Viewer"
    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    local content = CreateScrollablePanel(panel, 900)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Guardian Cooldown Viewer")

    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("A bar of ready cooldowns, shown only in Guardian spec.")

    -- =====================
    -- Settings
    -- =====================
    local settingsSeparator = CreateSeparator(content, "Settings", "TOPLEFT", desc, 0, -20)

    local showGCVCheckbox = CreateFrame("CheckButton", "ThugUI_ShowGCVCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    showGCVCheckbox:SetPoint("TOPLEFT", settingsSeparator, "BOTTOMLEFT", 20, -15)
    _G[showGCVCheckbox:GetName() .. "Text"]:SetText("Enable Guardian Cooldown Viewer")
    showGCVCheckbox:SetChecked(ThugUI_Config.showGCV or false)
    showGCVCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.showGCV = self:GetChecked()
        ER:UpdateGCVVisibility()
    end)

    local gcvCombatCheckbox = CreateFrame("CheckButton", "ThugUI_GCVCombatCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    gcvCombatCheckbox:SetPoint("TOPLEFT", showGCVCheckbox, "BOTTOMLEFT", 0, -5)
    _G[gcvCombatCheckbox:GetName() .. "Text"]:SetText("Show only during combat")
    gcvCombatCheckbox:SetChecked(ThugUI_Config.gcvShowOnlyInCombat or false)
    gcvCombatCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.gcvShowOnlyInCombat = self:GetChecked()
        ER:UpdateGCVVisibility()
    end)

    local gcvAnchorCheckbox = CreateFrame("CheckButton", "ThugUI_GCVAnchorCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    gcvAnchorCheckbox:SetPoint("TOPLEFT", gcvCombatCheckbox, "BOTTOMLEFT", 0, -5)
    _G[gcvAnchorCheckbox:GetName() .. "Text"]:SetText("Follow cursor during combat")
    gcvAnchorCheckbox:SetChecked(ThugUI_Config.anchorGCVToCursor or false)
    gcvAnchorCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.anchorGCVToCursor = self:GetChecked()
        if not self:GetChecked() then
            ER:ReleaseGCVAnchor()
        end
    end)

    local posNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    posNote:SetPoint("TOPLEFT", gcvAnchorCheckbox, "BOTTOMLEFT", 20, -10)
    posNote:SetText("Drag the bar to reposition when out of combat.")

    -- =====================
    -- Appearance
    -- =====================
    local appearSeparator = CreateSeparator(content, "Appearance", "TOPLEFT", posNote, -20, -20)

    local gcvScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    gcvScaleLabel:SetPoint("TOPLEFT", appearSeparator, "BOTTOMLEFT", 0, -15)
    gcvScaleLabel:SetText("Bar Scale:")

    local gcvScaleSlider = CreateFrame("Slider", "ThugUI_GCVScaleSlider", content, "OptionsSliderTemplate")
    gcvScaleSlider:SetPoint("LEFT", gcvScaleLabel, "RIGHT", 15, 0)
    gcvScaleSlider:SetMinMaxValues(0.5, 2.0)
    gcvScaleSlider:SetValue(ThugUI_Config.gcvScale or 1.0)
    gcvScaleSlider:SetValueStep(0.05)
    gcvScaleSlider:SetObeyStepOnDrag(true)
    gcvScaleSlider:SetWidth(150)
    _G[gcvScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[gcvScaleSlider:GetName() .. "High"]:SetText("2.0")
    _G[gcvScaleSlider:GetName() .. "Text"]:SetText("")

    local gcvScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    gcvScaleValue:SetPoint("LEFT", gcvScaleSlider, "RIGHT", 10, 0)
    gcvScaleValue:SetText(string.format("%.2f", ThugUI_Config.gcvScale or 1.0))

    gcvScaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 20 + 0.5) / 20
        gcvScaleValue:SetText(string.format("%.2f", rounded))
        ThugUI_Config.gcvScale = rounded
        if ER.gcvContainer then ER.gcvContainer:SetScale(rounded) end
    end)

    local gcvCornerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    gcvCornerLabel:SetPoint("TOPLEFT", gcvScaleLabel, "BOTTOMLEFT", 0, -25)
    gcvCornerLabel:SetText("Cursor Anchor Corner:")

    local gcvCornerNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    gcvCornerNote:SetPoint("TOPLEFT", gcvCornerLabel, "BOTTOMLEFT", 0, -3)
    gcvCornerNote:SetText("Which corner of the bar attaches to the cursor when following.")

    local gcvCornerDropdown = CreateFrame("Frame", "ThugUI_GCVCornerDropdown", content, "UIDropDownMenuTemplate")
    gcvCornerDropdown:SetPoint("TOPLEFT", gcvCornerNote, "BOTTOMLEFT", -16, -5)
    UIDropDownMenu_SetWidth(gcvCornerDropdown, 140)

    local gcvCornerLabels = {TOPLEFT = "Top Left", TOPRIGHT = "Top Right", BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right"}
    local gcvCornerOrder = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

    UIDropDownMenu_Initialize(gcvCornerDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, corner in ipairs(gcvCornerOrder) do
            info.text = gcvCornerLabels[corner]
            info.checked = (ThugUI_Config.gcvAnchorCorner == corner)
            info.func = function()
                ThugUI_Config.gcvAnchorCorner = corner
                UIDropDownMenu_SetText(gcvCornerDropdown, gcvCornerLabels[corner])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(gcvCornerDropdown, gcvCornerLabels[ThugUI_Config.gcvAnchorCorner or "TOPLEFT"])

    -- =====================
    -- Tracked Spells
    -- =====================
    local spellsSeparator = CreateSeparator(content, "Tracked Spells", "TOPLEFT", gcvCornerDropdown, 0, -20)

    local spellsNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    spellsNote:SetPoint("TOPLEFT", spellsSeparator, "BOTTOMLEFT", 0, -10)
    spellsNote:SetText("Mangle, Thrash, Convoke the Spirits, Lunar Beam, Red Moon.")

    local talentNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    talentNote:SetPoint("TOPLEFT", spellsNote, "BOTTOMLEFT", 0, -8)
    talentNote:SetText("Talent abilities (Convoke, Lunar Beam, Red Moon) only appear when actually\ntalented. Each icon shows only while its ability is ready (off cooldown).")

    -- =====================
    -- Reset
    -- =====================
    local resetSeparator = CreateSeparator(content, "Reset", "TOPLEFT", talentNote, 0, -20)

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(240, 25)
    resetButton:SetPoint("TOPLEFT", resetSeparator, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Guardian Viewer Settings")
    resetButton:SetScript("OnClick", function()
        local gcvKeys = {
            "showGCV", "gcvShowOnlyInCombat", "anchorGCVToCursor",
            "gcvAnchorCorner", "gcvScale", "gcvPoint",
        }
        for _, key in ipairs(gcvKeys) do
            ThugUI_Config[key] = ER.defaults[key]
        end

        showGCVCheckbox:SetChecked(ThugUI_Config.showGCV or false)
        gcvCombatCheckbox:SetChecked(ThugUI_Config.gcvShowOnlyInCombat or false)
        gcvAnchorCheckbox:SetChecked(ThugUI_Config.anchorGCVToCursor or false)
        gcvScaleSlider:SetValue(ThugUI_Config.gcvScale or 1.0)
        gcvScaleValue:SetText(string.format("%.2f", ThugUI_Config.gcvScale or 1.0))
        UIDropDownMenu_SetText(gcvCornerDropdown, gcvCornerLabels[ThugUI_Config.gcvAnchorCorner or "TOPLEFT"])

        if ER.gcvContainer then
            ER.gcvContainer:ClearAllPoints()
            ER.gcvContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 300)
            ER.gcvContainer:SetScale(ThugUI_Config.gcvScale or 1.0)
        end
        ER:UpdateGCVVisibility()
        print("|cff00ff00ThugUI:|r Guardian viewer settings reset to defaults.")
    end)

    -- Register as subcategory
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    subcategory.ID = "ThugUI_GuardianCooldownViewer"
end

-- ============================================================================
-- FRAME HIDER SUB-PANEL
-- ============================================================================

function ER:CreateFrameHiderPanel(parentCategory)
    local panel = CreateFrame("Frame", "ThugUI_FrameHiderPanel")
    panel.name = "Frame Hider"
    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    local content = CreateScrollablePanel(panel, 520)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Frame Hider")

    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Hide unwanted default UI elements. Changes take effect after /reload.")

    -- =====================
    -- Toggles
    -- =====================
    local toggleSeparator = CreateSeparator(content, "Hidden Elements", "TOPLEFT", desc, 0, -20)

    local hideStanceCheckbox = CreateFrame("CheckButton", "ThugUI_HideStanceCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    hideStanceCheckbox:SetPoint("TOPLEFT", toggleSeparator, "BOTTOMLEFT", 20, -15)
    _G[hideStanceCheckbox:GetName() .. "Text"]:SetText("Hide Stance Bar")
    hideStanceCheckbox:SetChecked(ThugUI_Config.hideStanceBar)
    hideStanceCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.hideStanceBar = self:GetChecked()
    end)

    local hideBagCheckbox = CreateFrame("CheckButton", "ThugUI_HideBagCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    hideBagCheckbox:SetPoint("TOPLEFT", hideStanceCheckbox, "BOTTOMLEFT", 0, -5)
    _G[hideBagCheckbox:GetName() .. "Text"]:SetText("Hide Bag Buttons")
    hideBagCheckbox:SetChecked(ThugUI_Config.hideBagButtons)
    hideBagCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.hideBagButtons = self:GetChecked()
    end)

    local hideBagNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    hideBagNote:SetPoint("TOPLEFT", hideBagCheckbox, "BOTTOMLEFT", 20, -2)
    hideBagNote:SetText("Hides backpack button, reagent bag slot, and bag bar toggle.")

    local hideCharCheckbox = CreateFrame("CheckButton", "ThugUI_HideCharCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    hideCharCheckbox:SetPoint("TOPLEFT", hideBagNote, "BOTTOMLEFT", -20, -10)
    _G[hideCharCheckbox:GetName() .. "Text"]:SetText("Hide Character Frame")
    hideCharCheckbox:SetChecked(ThugUI_Config.hideCharacterFrame)
    hideCharCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.hideCharacterFrame = self:GetChecked()
    end)

    local hideCharNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    hideCharNote:SetPoint("TOPLEFT", hideCharCheckbox, "BOTTOMLEFT", 20, -2)
    hideCharNote:SetText("Hides the player portrait, health, and mana frame.")

    -- =====================
    -- Movable Frames
    -- =====================
    local movableSeparator = CreateSeparator(content, "Movable Frames", "TOPLEFT", hideCharNote, -36, -20)

    local preyCrystalCheckbox = CreateFrame("CheckButton", "ThugUI_PreyCrystalCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    preyCrystalCheckbox:SetPoint("TOPLEFT", movableSeparator, "BOTTOMLEFT", 20, -15)
    _G[preyCrystalCheckbox:GetName() .. "Text"]:SetText("Make Prey Crystal frame movable")
    preyCrystalCheckbox:SetChecked(ThugUI_Config.movePreyCrystal)
    preyCrystalCheckbox:SetScript("OnClick", function(self)
        ThugUI_Config.movePreyCrystal = self:GetChecked()
    end)

    local preyCrystalNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    preyCrystalNote:SetPoint("TOPLEFT", preyCrystalCheckbox, "BOTTOMLEFT", 20, -2)
    preyCrystalNote:SetText("Drag the Prey Crystal power bar to reposition it.\nPosition is saved across sessions. /reload to apply changes.")

    -- =====================
    -- Debug
    -- =====================
    local debugSeparator = CreateSeparator(content, "Debug", "TOPLEFT", preyCrystalNote, -36, -20)

    local debugModeCheckbox = CreateFrame("CheckButton", "ThugUI_DebugModeCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    debugModeCheckbox:SetPoint("TOPLEFT", debugSeparator, "BOTTOMLEFT", 20, -15)
    _G[debugModeCheckbox:GetName() .. "Text"]:SetText("Debug Mode")
    debugModeCheckbox:SetChecked(ThugUI_Config.debugMode)
    debugModeCheckbox:SetScript("OnClick", function(self)
        ER:SetDebugMode(self:GetChecked())
    end)
    -- Let the slash command (/thugdebug) keep this checkbox in sync
    ER.debugModeCheckbox = debugModeCheckbox

    local debugModeNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    debugModeNote:SetPoint("TOPLEFT", debugModeCheckbox, "BOTTOMLEFT", 20, -2)
    debugModeNote:SetText("Master switch for all ThugUI debug output: the aura query log\n(/thuglog) and init messages. Same as the /thugdebug command.")

    -- =====================
    -- Reset
    -- =====================
    local resetSeparator = CreateSeparator(content, "Reset", "TOPLEFT", debugModeNote, -36, -20)

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(200, 25)
    resetButton:SetPoint("TOPLEFT", resetSeparator, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Frame Hider Settings")
    resetButton:SetScript("OnClick", function()
        ThugUI_Config.hideStanceBar = ER.defaults.hideStanceBar
        ThugUI_Config.hideBagButtons = ER.defaults.hideBagButtons
        ThugUI_Config.hideCharacterFrame = ER.defaults.hideCharacterFrame
        ThugUI_Config.movePreyCrystal = ER.defaults.movePreyCrystal
        ThugUI_Config.preyCrystalPoint = ER.defaults.preyCrystalPoint

        hideStanceCheckbox:SetChecked(ThugUI_Config.hideStanceBar)
        hideBagCheckbox:SetChecked(ThugUI_Config.hideBagButtons)
        hideCharCheckbox:SetChecked(ThugUI_Config.hideCharacterFrame)
        preyCrystalCheckbox:SetChecked(ThugUI_Config.movePreyCrystal)

        print("|cff00ff00ThugUI:|r Frame hider settings reset to defaults. /reload to apply.")
    end)

    -- Register as subcategory
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    subcategory.ID = "ThugUI_FrameHider"
end

-- ============================================================================
-- APPLY SETTINGS
-- ============================================================================

function ER:ApplySettings()
    if ThugUI_Config.scale then
        ER:SetGroupScale(ThugUI_Config.scale)
    end

    if ThugUI_CursorFrame then
        local transparency = ThugUI_Config.transparency or 1.0
        ThugUI_CursorFrame:SetAlpha(transparency)
    end

    -- Hide all frames first
    if ER.GCDCooldownFrame then ER.GCDCooldownFrame:Hide() end
    if ER.GCDBackgroundFrame then ER.GCDBackgroundFrame:Hide() end
    if ER.CastFrame then ER.CastFrame:Hide() end
    if ER.CastBackgroundFrame then ER.CastBackgroundFrame:Hide() end
    if ThugUI_CursorFrame and ThugUI_CursorFrame.MainRing then ThugUI_CursorFrame.MainRing:Hide() end

    ER.enableGCD = false
    ER.enableCast = false

    local slots = {
        {config = ThugUI_Config.innerRing, size = 50},
        {config = ThugUI_Config.mainRing, size = 70},
        {config = ThugUI_Config.outerRing, size = 90},
    }

    for _, slot in ipairs(slots) do
        local ringType = slot.config
        local size = slot.size

        if ringType == "Main Ring" then
            if ThugUI_CursorFrame and ThugUI_CursorFrame.MainRing then
                ThugUI_CursorFrame.MainRing:SetSize(size, size)
                ThugUI_CursorFrame.MainRing:Show()
            end

        elseif ringType == "GCD" then
            if ER.GCDCooldownFrame then
                ER.GCDCooldownFrame:SetSize(size, size)
                ER.GCDCooldownFrame:Show()
                ER.enableGCD = true
            end
            if size == 70 and ER.GCDBackgroundFrame then
                ER.GCDBackgroundFrame:SetSize(size, size)
                ER.GCDBackgroundFrame:Show()
            end

        elseif ringType == "Cast" then
            if ER.CastFrame then
                ER.CastFrame:SetSize(size, size)
                ER.CastFrame:Show()
                ER.enableCast = true
            end
            if size == 70 and ER.CastBackgroundFrame then
                ER.CastBackgroundFrame:SetSize(size, size)
                ER.CastBackgroundFrame:Show()
            end
        end
    end

    -- Register/unregister events based on enabled features
    if ER.TrackerFrame then
        if ER.enableGCD then
            ER.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
        else
            ER.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_SENT")
        end

        if ER.enableCast then
            ER.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_START")
            ER.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
            ER.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
            ER.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        else
            ER.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_START")
            ER.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_STOP")
            ER.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
            ER.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        end
    end

    ER:UpdateRingColors()
    ER:UpdateVisibility()
    ER:UpdateReticle()
end
