-- ============================================================================
-- ThugUI: Target of Target settings sub-panel
--
-- Registered as a subcategory of the existing ThugUI settings category, and
-- built with the helpers exported by EssentialRings_Settings so it lays out the
-- same as every other ThugUI page.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local ER = ThugUI.EssentialRings
local ToT = ThugUI.TargetOfTarget

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

function ER:CreateTargetOfTargetPanel(parentCategory)
    local panel = CreateFrame("Frame", "ThugUI_TargetOfTargetPanel")
    panel.name = "Target of Target"

    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end

    local content = ER.CreateScrollablePanel(panel, 860)
    local CreateSeparator = ER.CreateSeparator

    -- Appearance changes are live; anything that spawns, shows or repositions
    -- the frame is a protected action and queues until out of combat.
    local function ApplyLive()
        if ToT then ToT:ApplySettings() end
    end

    local function ApplyToggle()
        if ToT then ToT:ApplyAll() end
    end

    -- =====================
    -- Header / intro
    -- =====================
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Target of Target")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Your target's target, drawn with the full target frame art.")

    local enableCheckbox = AddCheckbox(content, "ThugUI_ToTEnabled",
        "|cff00ff00Enable ThugUI Target of Target|r",
        "totEnabled", subtitle, 0, -12, ApplyToggle)

    local enableNote = AddNote(content,
        "Uses Blizzard's own target frame artwork at full size, instead of the\n" ..
        "small target-of-target frame. Everything here applies immediately out\n" ..
        "of combat - no /reload needed.",
        enableCheckbox, 20, -2)

    local unlockCheckbox = AddCheckbox(content, "ThugUI_ToTUnlock",
        "Unlock frame for moving",
        "totUnlocked", enableNote, 0, -8, function(checked)
            if ToT then ToT:SetUnlocked(checked) end
        end)

    local unlockNote = AddNote(content,
        "Shows a drag handle over the frame. Position is saved automatically.",
        unlockCheckbox, 20, -2)

    -- =====================
    -- Frame parts
    -- =====================
    local partsSep = CreateSeparator(content, "Frame Parts", "TOPLEFT", unlockNote, -36, -20)

    local healthCheckbox = AddCheckbox(content, "ThugUI_ToTHealth", "Show health bar",
        "totShowHealthBar", partsSep, 20, -15, ApplyLive)

    local powerCheckbox = AddCheckbox(content, "ThugUI_ToTPower", "Show resource bar",
        "totShowPowerBar", healthCheckbox, 0, -4, ApplyLive)

    local barsNote = AddNote(content,
        "The resource bar follows the unit's own power type, so it draws as\n" ..
        "mana, rage, energy, focus or runic power art the way Blizzard does.",
        powerCheckbox, 20, -2)

    local portraitCheckbox = AddCheckbox(content, "ThugUI_ToTPortrait", "Show portrait",
        "totShowPortrait", barsNote, 0, -8, ApplyLive)

    local portraitNote = AddNote(content,
        "Turning this off drops the portrait image and leaves the ring around it\n" ..
        "as an empty socket - the frame artwork itself is unchanged.",
        portraitCheckbox, 20, -2)

    local nameCheckbox = AddCheckbox(content, "ThugUI_ToTName", "Show unit name",
        "totShowName", portraitNote, 0, -8, ApplyLive)

    local repCheckbox = AddCheckbox(content, "ThugUI_ToTRep", "Show reaction strip behind the name",
        "totShowReputation", nameCheckbox, 0, -4, ApplyLive)

    local repNote = AddNote(content,
        "Red, yellow or green depending on how the unit feels about you. The\n" ..
        "health bar stays green for everyone on a retail target frame, so this\n" ..
        "strip is what tells you whether the unit is hostile.",
        repCheckbox, 20, -2)

    -- =====================
    -- Appearance
    -- =====================
    local appearanceSep = CreateSeparator(content, "Appearance", "TOPLEFT", repNote, -36, -20)

    local healthColorDropdown = AddDropdown(content, "ThugUI_ToTHealthColor", "Health Bar Color",
        "totHealthColor", {
            { text = "Blizzard (green)", value = "blizzard" },
            { text = "Class Color",      value = "class" },
            { text = "Reaction Color",   value = "reaction" },
        }, appearanceSep, 0, -34, ApplyLive)

    local healthColorNote = AddNote(content,
        "Blizzard uses the finished green bar art and never tints it. The other\n" ..
        "two swap to the neutral version of the same art so it can be colored.",
        healthColorDropdown, 20, -6)

    local scaleSlider = AddSlider(content, "ThugUI_ToTScale", "Frame Scale",
        "totScale", 0.5, 2.0, 0.05, healthColorNote, 0, -14, 2, ApplyLive)

    -- =====================
    -- Behaviour
    -- =====================
    local behaviourSep = CreateSeparator(content, "Behaviour", "TOPLEFT", scaleSlider, -20, -34)

    local hideBlizzCheckbox = AddCheckbox(content, "ThugUI_ToTHideBlizz",
        "Hide Blizzard's target-of-target frame",
        "totHideBlizzardToT", behaviourSep, 20, -15, ApplyToggle)

    local hideBlizzNote = AddNote(content,
        "Flips the same setting as Options - Interface - \"Show Target of Target\",\n" ..
        "which is the supported way to turn it off. Unticking this restores what\n" ..
        "the setting was before ThugUI touched it.",
        hideBlizzCheckbox, 20, -2)

    -- =====================
    -- Reset
    -- =====================
    local resetSep = CreateSeparator(content, "Reset", "TOPLEFT", hideBlizzNote, -36, -20)

    local resetKeys = {
        "totEnabled", "totUnlocked", "totShowHealthBar", "totShowPowerBar",
        "totShowPortrait", "totShowName", "totShowReputation", "totHealthColor",
        "totScale", "totHideBlizzardToT",
    }

    local checkboxes = {
        enableCheckbox, unlockCheckbox, healthCheckbox, powerCheckbox,
        portraitCheckbox, nameCheckbox, repCheckbox, hideBlizzCheckbox,
    }

    local sliders = { scaleSlider }
    local dropdowns = { healthColorDropdown }

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(240, 25)
    resetButton:SetPoint("TOPLEFT", resetSep, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Target of Target Settings")
    resetButton:SetScript("OnClick", function()
        for _, key in ipairs(resetKeys) do
            ThugUI_Config[key] = ER.defaults[key]
        end
        -- Position is not in resetKeys because it lives in its own table; wipe
        -- it here so the frame goes back to where a fresh install puts it.
        ThugUI_Config.totPoint = nil

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

        if ToT then
            ToT:RestorePosition()
            ToT:ApplyAll()
            ToT:SetUnlocked(ThugUI_Config.totUnlocked)
        end
        print("|cff00ff00ThugUI:|r Target of target settings reset to defaults.")
    end)

    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
    subcategory.ID = "ThugUI_TargetOfTarget"
end
