-- ============================================================================
-- ThugUI: Options entry points
--
-- This file used to BE the options window: a 640x480 frame with three hardcoded
-- category buttons and a RefreshContent() that rebuilt every control on each
-- tab switch (orphaning the old ones via SetParent(nil), which does not free a
-- frame in WoW). The window itself now lives in ui/Window.lua with pages in
-- ui/pages/, and this file is just the doors into it:
--
--   /thugui, /thug, /tui   open the window
--   Interface > AddOns     a button that opens the window
--
-- ThugUI.OptionsMenu is kept as an alias so anything still calling
-- OptionsMenu:Toggle() keeps working.
-- ============================================================================

ThugUI = ThugUI or {}

local OptionsMenu = {}
ThugUI.OptionsMenu = OptionsMenu

function OptionsMenu:Toggle(pageID)
    ThugUI.Window:Toggle(pageID)
end

function OptionsMenu:Open(pageID)
    ThugUI.Window:Open(pageID)
end

function ThugUI:ToggleOptions(pageID)
    ThugUI.Window:Toggle(pageID)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if event ~= "ADDON_LOADED" or addon ~= "ThugUI" then return end

    SLASH_THUGUI1 = "/thugui"
    SLASH_THUGUI2 = "/thug"
    SLASH_THUGUI3 = "/tui"
    SlashCmdList["THUGUI"] = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")
        -- "/thugui cooldownviewer" jumps straight to a page; bare "/thugui"
        -- toggles whatever page was last open.
        ThugUI.Window:Toggle(msg ~= "" and msg or nil)
    end

    -- A stub in the Blizzard addon list that just opens the real window.
    -- The feature panels registered by modules/ stay where they are; this is
    -- additive until the new window has proved itself.
    local panel = CreateFrame("Frame", "ThugUI_InterfaceOptionsPanel", UIParent)
    panel.name = "ThugUI"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ThugUI")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(220, 28)
    button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    button:SetText("Open ThugUI config window")
    button:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        ThugUI.Window:Open()
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -10)
    hint:SetText("Or type /thugui.")

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = "ThugUI_Launcher"
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    self:UnregisterEvent("ADDON_LOADED")
end)
