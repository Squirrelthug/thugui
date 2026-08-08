-- ============================================================================
-- ThugUI: Config Window
--
-- The standalone settings window (/thugui). Replaces the hand-rolled window in
-- options.lua, which hardcoded three categories and rebuilt every control on
-- each tab switch.
--
-- A page registers itself with ThugUI.Window:RegisterPage{...} and is built
-- lazily the first time it is shown, into its own persistent container. Pages
-- are then shown/hidden and Refresh()ed -- never destroyed -- so switching tabs
-- costs nothing and leaks nothing.
--
-- The Blizzard Settings panels under modules/ are deliberately left registered.
-- This window is additive for now; the duplicate entries come out once it has
-- been through a few play sessions.
-- ============================================================================

ThugUI = ThugUI or {}

local Window = {}
ThugUI.Window = Window

local W  -- ThugUI.Widgets, resolved on first use (load order independent)

-- Sized around the Cooldown Viewer page, which is the widest thing here:
-- 236 picker + 320 grid + 200 inspector plus gutters.
local WINDOW_WIDTH   = 1040
local WINDOW_HEIGHT  = 680
local SIDEBAR_WIDTH  = 170
local HEADER_HEIGHT  = 44

Window.pages = {}
Window.pagesByID = {}
Window.activePageID = nil

-- ----------------------------------------------------------------------------
-- Registration
-- ----------------------------------------------------------------------------

--- def: {
---   id      = unique string,
---   title   = sidebar label,
---   order   = sort key (lower first),
---   scroll  = false to opt out of the default scroll area,
---   build   = function(container, panel) -- called once
---   refresh = function(container, panel) -- called on every show (optional)
--- }
function Window:RegisterPage(def)
    assert(def and def.id and def.title and def.build, "ThugUI: bad page definition")
    if self.pagesByID[def.id] then return end

    def.order = def.order or 100
    self.pagesByID[def.id] = def
    table.insert(self.pages, def)
    table.sort(self.pages, function(a, b)
        if a.order == b.order then return a.title < b.title end
        return a.order < b.order
    end)

    -- A page registered after the window was already built still needs a tab.
    if self.frame then self:RebuildSidebar() end
end

-- ----------------------------------------------------------------------------
-- Sidebar buttons
-- ----------------------------------------------------------------------------

local function CreateNavButton(parent, text)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SIDEBAR_WIDTH - 20, 26)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.08)
    bg:Hide()
    btn.selectedBG = bg

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)

    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetColorTexture(0.0, 1.0, 0.8, 0.9)
    accent:Hide()
    btn.accent = accent

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 12, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    btn.label = label

    function btn:SetSelected(selected)
        self.selectedBG:SetShown(selected)
        self.accent:SetShown(selected)
        if selected then
            self.label:SetTextColor(1, 1, 1)
        else
            self.label:SetTextColor(0.75, 0.75, 0.75)
        end
    end
    btn:SetSelected(false)

    return btn
end

-- ----------------------------------------------------------------------------
-- Frame construction
-- ----------------------------------------------------------------------------

function Window:CreateWindow()
    if self.frame then return self.frame end
    W = W or ThugUI.Widgets

    local f = CreateFrame("Frame", "ThugUI_ConfigWindow", UIParent, "BackdropTemplate")
    f:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.96)

    -- Escape closes it, like every other panel in the game.
    tinsert(UISpecialFrames, "ThugUI_ConfigWindow")

    -- Header ------------------------------------------------------------
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText("|cff00ffccThugUI|r")

    local version = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. (ThugUI.version or "1.0.0"))

    local headerRule = f:CreateTexture(nil, "ARTWORK")
    headerRule:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    headerRule:SetHeight(1)
    headerRule:SetPoint("TOPLEFT", 14, -HEADER_HEIGHT)
    headerRule:SetPoint("TOPRIGHT", -14, -HEADER_HEIGHT)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Sidebar -----------------------------------------------------------
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", 14, -(HEADER_HEIGHT + 8))
    sidebar:SetPoint("BOTTOMLEFT", 14, 14)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    f.sidebar = sidebar

    local sidebarRule = f:CreateTexture(nil, "ARTWORK")
    sidebarRule:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    sidebarRule:SetWidth(1)
    sidebarRule:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    sidebarRule:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 6, 0)

    -- Content -----------------------------------------------------------
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 14, 0)
    content:SetPoint("BOTTOMRIGHT", -14, 14)
    f.content = content

    self.frame = f
    self:RebuildSidebar()
    return f
end

function Window:RebuildSidebar()
    local f = self.frame
    if not f then return end

    f.navButtons = f.navButtons or {}
    for _, btn in pairs(f.navButtons) do
        btn:Hide()
    end

    for i, def in ipairs(self.pages) do
        local btn = f.navButtons[def.id]
        if not btn then
            btn = CreateNavButton(f.sidebar, def.title)
            btn:SetScript("OnClick", function()
                Window:SelectPage(def.id)
            end)
            f.navButtons[def.id] = btn
        end
        btn.label:SetText(def.title)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f.sidebar, "TOPLEFT", 10, -((i - 1) * 30))
        btn:SetSelected(def.id == self.activePageID)
        btn:Show()
    end
end

-- ----------------------------------------------------------------------------
-- Page lifecycle
-- ----------------------------------------------------------------------------

function Window:BuildPage(def)
    if def.container then return def.container end
    W = W or ThugUI.Widgets

    local container = CreateFrame("Frame", nil, self.frame.content)
    container:SetAllPoints()
    container:Hide()
    def.container = container

    local host, panelWidth
    if def.scroll == false then
        host = container
        panelWidth = self.frame.content:GetWidth() - 32
    else
        local scroll, scrollContent = W.CreateScrollArea(container)
        -- The scroll child needs a real width or FontString wrapping collapses.
        scrollContent:SetWidth(self.frame.content:GetWidth() - 34)
        def.scrollFrame = scroll
        host = scrollContent
        panelWidth = scrollContent:GetWidth() - 32
    end
    def.host = host

    local panel = W.NewPanel(host, { width = panelWidth })
    def.panel = panel

    def.build(host, panel)

    if def.scroll ~= false then
        host:SetHeight(math.max(panel:GetHeight(), self.frame.content:GetHeight()))
    end

    return container
end

function Window:SelectPage(id)
    local def = self.pagesByID[id]
    if not def then return end

    self:CreateWindow()

    for _, other in ipairs(self.pages) do
        if other.container and other.id ~= id then
            other.container:Hide()
        end
    end

    self:BuildPage(def)
    self.activePageID = id

    -- Widgets re-read config here rather than at build time, so a page opened
    -- after a spec change or a /reload-free settings edit shows current values.
    if def.panel then def.panel:Refresh() end
    if def.refresh then def.refresh(def.host, def.panel) end

    def.container:Show()

    for pageID, btn in pairs(self.frame.navButtons or {}) do
        btn:SetSelected(pageID == id)
    end
end

-- ----------------------------------------------------------------------------
-- Entry points
-- ----------------------------------------------------------------------------

function Window:Open(pageID)
    self:CreateWindow()
    self:SelectPage(pageID or self.activePageID or (self.pages[1] and self.pages[1].id))
    self.frame:Show()
end

function Window:Close()
    if self.frame then self.frame:Hide() end
end

function Window:Toggle(pageID)
    self:CreateWindow()
    if self.frame:IsShown() and not pageID then
        self.frame:Hide()
    else
        self:Open(pageID)
    end
end

--- Re-sync the visible page. Called when something outside the window changes
--- config that the window is displaying (spec change, slash command, orb menu).
function Window:RefreshActivePage()
    if not self.frame or not self.frame:IsShown() then return end
    local def = self.pagesByID[self.activePageID]
    if not def or not def.container then return end
    if def.panel then def.panel:Refresh() end
    if def.refresh then def.refresh(def.host, def.panel) end
end

function ThugUI:ToggleOptions(pageID)
    Window:Toggle(pageID)
end

return Window
