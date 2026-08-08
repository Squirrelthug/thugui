-- ThugUI: Options GUI Module
-- Graphical interface and menu panel for ThugUI configuration.

local OptionsMenu = {}
ThugUI.OptionsMenu = OptionsMenu

local frame = nil
local activeCategory = "OrbAnchors"

-------------------------------------------------------------------------------
-- Helper Controls Factory
-------------------------------------------------------------------------------
local function CreateHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    header:SetText(text)
    header:SetTextColor(0, 1, 0.8)
    return header
end

local function CreateCheckbox(parent, labelText, x, y, getValueFunc, setValueFunc)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    cb.text:SetText(labelText)
    cb:SetChecked(getValueFunc() == true)
    
    cb:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        setValueFunc(isChecked)
    end)
    return cb
end

local function CreateSlider(parent, labelText, minVal, maxVal, step, x, y, getValueFunc, setValueFunc)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(180)
    slider:SetValue(getValueFunc() or minVal)
    
    local title = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 2)
    title:SetText(labelText)
    
    local valText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 2)
    valText:SetText(tostring(getValueFunc() or minVal))
    
    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        valText:SetText(tostring(val))
        setValueFunc(val)
    end)
    return slider
end

local function CreateButton(parent, labelText, width, height, x, y, onClickFunc)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 140, height or 24)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetText(labelText)
    btn:SetScript("OnClick", onClickFunc)
    return btn
end

-------------------------------------------------------------------------------
-- Main Options Window Creation
-------------------------------------------------------------------------------
function OptionsMenu:CreateFrame()
    if frame then return frame end

    local f = CreateFrame("Frame", "ThugUI_OptionsWindow", UIParent, "BackdropTemplate")
    f:SetSize(640, 480)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- Styling / Backdrop
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)

    -- Window Title Header
    local titleBg = f:CreateTexture(nil, "ARTWORK")
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBg:SetSize(300, 64)
    titleBg:SetPoint("TOP", f, "TOP", 0, 12)

    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", titleBg, "TOP", 0, -14)
    titleText:SetText("|cff00ff00ThugUI|r Config Menu")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- Sidebar Container
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetSize(140, 410)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -45)
    sidebar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    sidebar:SetBackdropColor(0, 0, 0, 0.4)
    sidebar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

    -- Content Container Panel
    local content = CreateFrame("Frame", nil, f, "BackdropTemplate")
    content:SetSize(450, 410)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    content:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    content:SetBackdropColor(0, 0, 0, 0.4)
    content:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    f.content = content

    -- Sidebar Category Tabs
    local categories = {
        { id = "OrbAnchors", name = "Orb Anchors" },
        { id = "CursorCooldowns", name = "Cursor Rings" },
        { id = "General", name = "General" },
    }

    f.tabButtons = {}
    for i, cat in ipairs(categories) do
        local btn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
        btn:SetSize(124, 28)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -12 - ((i - 1) * 34))
        btn:SetText(cat.name)
        btn:SetScript("OnClick", function()
            activeCategory = cat.id
            OptionsMenu:RefreshContent()
        end)
        f.tabButtons[cat.id] = btn
    end

    frame = f
    return frame
end

-------------------------------------------------------------------------------
-- Render Options Content Panels
-------------------------------------------------------------------------------
function OptionsMenu:RefreshContent()
    if not frame or not frame.content then return end
    
    -- Clear content children
    local children = { frame.content:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local regions = { frame.content:GetRegions() }
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
            region:Hide()
        end
    end

    -- Update Tab Highlight
    for id, btn in pairs(frame.tabButtons) do
        if id == activeCategory then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end

    local c = frame.content

    if activeCategory == "OrbAnchors" then
        self:RenderOrbAnchorsPanel(c)
    elseif activeCategory == "CursorCooldowns" then
        self:RenderCursorCooldownsPanel(c)
    elseif activeCategory == "General" then
        self:RenderGeneralPanel(c)
    end
end

-------------------------------------------------------------------------------
-- Category 1: Orb Anchors Settings Panel
-------------------------------------------------------------------------------
function OptionsMenu:RenderOrbAnchorsPanel(c)
    local db = ThugUIDB.OrbAnchors
    local dbChat = db.chatOrb
    local dbObj = db.objectivesOrb

    CreateHeader(c, "Orb Shape Anchors & Floating Windows", -16)

    -- Master Enable & Lock
    CreateCheckbox(c, "Enable Orb Anchors Module", 20, -45,
        function() return db.enabled end,
        function(val)
            db.enabled = val
            if ThugUI.modules.OrbAnchors then
                ThugUI.modules.OrbAnchors:UpdateAnchors()
            end
        end
    )

    CreateCheckbox(c, "Lock Orb Positions (Prevent Dragging)", 220, -45,
        function() return db.locked end,
        function(val)
            db.locked = val
            print("|cff00ff00ThugUI:|r Orbs are now " .. (val and "|cffff4040Locked|r" or "|cff40ff40Unlocked|r"))
        end
    )

    -- Section: Chat Orb & Stream Text Window
    local chatHeader = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    chatHeader:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -80)
    chatHeader:SetText("|cff00ccffChat Orb & Stream Text Box|r")

    CreateCheckbox(c, "Enable Chat Orb", 20, -100,
        function() return dbChat.enabled end,
        function(val) dbChat.enabled = val end
    )

    -- Chat Mode Radio Buttons
    local modeLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -135)
    modeLabel:SetText("Chat Frame Mode:")

    local modes = {
        { id = 1, name = "Normal Chat" },
        { id = 2, name = "Stream Text Box" },
        { id = 3, name = "Hidden" },
    }

    for i, m in ipairs(modes) do
        local btn = CreateButton(c, m.name, 120, 22, 20 + ((i - 1) * 130), -152, function()
            dbChat.mode = m.id
            if ThugUI.modules.OrbAnchors then
                ThugUI.modules.OrbAnchors:SetChatMode(m.id)
            end
        end)
    end

    -- Stream Font Size Slider
    CreateSlider(c, "Stream Chat Font Size", 8, 28, 1, 20, -200,
        function() return dbChat.fontSize or 14 end,
        function(val)
            dbChat.fontSize = val
            local smf = _G["ThugUI_StreamChatMessageFrame"]
            if smf then
                local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                smf:SetFont(fontPath, val, dbChat.fontOutline or "OUTLINE")
            end
        end
    )

    -- Stream Channel Filters Header & Checkboxes
    local chanLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 230, -190)
    chanLabel:SetText("Stream Chat Channels:")

    local channelsList = {
        { key = "SAY", label = "Say" },
        { key = "YELL", label = "Yell" },
        { key = "PARTY", label = "Party" },
        { key = "RAID", label = "Raid" },
        { key = "GUILD", label = "Guild" },
        { key = "WHISPER", label = "Whisper" },
        { key = "SYSTEM", label = "System" },
        { key = "EMOTE", label = "Emote" },
    }

    for i, ch in ipairs(channelsList) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        CreateCheckbox(c, ch.label, 230 + (col * 95), -210 - (row * 24),
            function() return dbChat.channels and dbChat.channels[ch.key] ~= false end,
            function(val)
                if not dbChat.channels then dbChat.channels = {} end
                dbChat.channels[ch.key] = val
            end
        )
    end

    -- Section: Objectives Tracker Orb
    local objHeader = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    objHeader:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -280)
    objHeader:SetText("|cffffd100Objectives Tracker Orb|r")

    CreateCheckbox(c, "Enable Objectives Orb Anchor", 20, -300,
        function() return dbObj.enabled end,
        function(val) dbObj.enabled = val end
    )

    CreateButton(c, dbObj.visible and "Tracker: SHOWN" or "Tracker: HIDDEN", 160, 22, 230, -300, function(btn)
        local newVis = not dbObj.visible
        if ThugUI.modules.OrbAnchors then
            ThugUI.modules.OrbAnchors:SetObjectivesVisibility(newVis)
        end
        btn:SetText(newVis and "Tracker: SHOWN" or "Tracker: HIDDEN")
    end)

    -- Reset Positions Button
    CreateButton(c, "Reset Orb Positions", 180, 24, 20, -360, function()
        dbChat.point = "BOTTOMLEFT"
        dbChat.x = 25
        dbChat.y = 220
        dbObj.point = "TOPRIGHT"
        dbObj.x = -260
        dbObj.y = -220
        if ThugUI.modules.OrbAnchors then
            ThugUI.modules.OrbAnchors:UpdateAnchors()
        end
        print("|cff00ff00ThugUI:|r Reset Orb positions to default.")
    end)
end

-------------------------------------------------------------------------------
-- Category 2: Cursor Cooldowns Settings Panel
-------------------------------------------------------------------------------
function OptionsMenu:RenderCursorCooldownsPanel(c)
    local db = ThugUIDB.CursorCooldowns

    CreateHeader(c, "Cursor Cooldown Rings", -16)

    CreateCheckbox(c, "Enable Cursor Cooldown Rings", 20, -45,
        function() return db.enabled end,
        function(val) db.enabled = val end
    )

    CreateCheckbox(c, "Show Only in Combat", 20, -75,
        function() return db.showOnlyInCombat end,
        function(val) db.showOnlyInCombat = val end
    )

    CreateSlider(c, "GCD Ring Size", 20, 80, 2, 20, -120,
        function() return db.gcdRingSize or 36 end,
        function(val) db.gcdRingSize = val end
    )

    CreateSlider(c, "Cast Ring Size", 20, 100, 2, 230, -120,
        function() return db.castRingSize or 48 end,
        function(val) db.castRingSize = val end
    )

    CreateCheckbox(c, "Use Class Color for GCD Ring", 20, -170,
        function() return db.useClassColor end,
        function(val) db.useClassColor = val end
    )
end

-------------------------------------------------------------------------------
-- Category 3: General / About Panel
-------------------------------------------------------------------------------
function OptionsMenu:RenderGeneralPanel(c)
    CreateHeader(c, "ThugUI Suite Overview", -16)

    local info = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -50)
    info:SetWidth(400)
    info:SetJustifyH("LEFT")
    info:SetText("ThugUI is a modular, high-performance UI suite for World of Warcraft.\n\n" ..
        "Features:\n" ..
        "• |cff00ff00Orb Anchors:|r Converts default frames (Chat, Objectives Tracker) into movable orb anchors with toggleable modes.\n" ..
        "• |cff00ff00Stream Text Box:|r Clean, transparent chat streaming window with adjustable font and box size.\n" ..
        "• |cff00ff00Cursor Cooldown Rings:|r Smooth GCD and cast tracking anchored directly to your cursor.\n\n" ..
        "Version: " .. (ThugUI.version or "1.0.0") .. "\nAuthor: Thug")
end

-------------------------------------------------------------------------------
-- Open / Toggle Options
-------------------------------------------------------------------------------
function OptionsMenu:Toggle()
    local f = self:CreateFrame()
    if f:IsShown() then
        f:Hide()
    else
        self:RefreshContent()
        f:Show()
    end
end

function ThugUI:ToggleOptions()
    OptionsMenu:Toggle()
end

-------------------------------------------------------------------------------
-- Integration with WoW AddOn Options (Settings Menu)
-------------------------------------------------------------------------------
local optionsInitFrame = CreateFrame("Frame")
optionsInitFrame:RegisterEvent("ADDON_LOADED")
optionsInitFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "ThugUI" then
        -- Slash commands
        SLASH_THUGUI1 = "/thugui"
        SLASH_THUGUI2 = "/thug"
        SLASH_THUGUI3 = "/tui"
        SlashCmdList["THUGUI"] = function()
            ThugUI:ToggleOptions()
        end

        -- Register in Blizzard Interface Options panel
        local panel = CreateFrame("Frame", "ThugUI_InterfaceOptionsPanel", UIParent)
        panel.name = "ThugUI"
        
        local openBtn = CreateButton(panel, "Open ThugUI Config Menu", 200, 30, 20, -20, function()
            ThugUI:ToggleOptions()
        end)

        if Settings and Settings.RegisterCanvasLayoutCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "ThugUI")
            Settings.RegisterAddOnCategory(category)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end

        self:UnregisterEvent("ADDON_LOADED")
    end
end)
