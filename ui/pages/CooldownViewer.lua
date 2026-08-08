-- ============================================================================
-- ThugUI: Cooldown Viewer settings page
--
-- The layout editor. Three columns:
--
--   left    spell picker -- everything this spec could track, from Blizzard's
--           Cooldown Manager categories or the spellbook, filtered by a search
--           box. Drag a spell onto the grid, or click it and click a cell.
--   middle  the 10x10 grid, drawn as an action-bar-like scaffold. This is a
--           WYSIWYG map of where icons land on the cursor -- with the caveat
--           that the borders, cell lines and anchor markers are editor-only
--           furniture. In combat only the icons draw.
--   right   inspector for the selected icon, plus the sliders.
--
-- ANCHOR PICKER
--
-- Clicking "Set cursor anchor" overlays a UIRadioButtonTemplate at each of the
-- 121 grid-line intersections and lets the player pick exactly one, with a live
-- reticle marking the choice. That is the same idiom as tRP3_Vendor's eight-point
-- picker around the target portrait (Core/Init.lua BuildAnchorPicker) -- radios
-- placed where the thing will actually land, exclusive selection, live preview --
-- scaled up from 8 options to 121.
-- ============================================================================

ThugUI = ThugUI or {}

local CV = ThugUI.CooldownViewer
local Data = CV.Data
local W = ThugUI.Widgets

local Page = {}
CV.Page = Page

local CELL          = 32   -- editor cell size; runtime uses profile.iconSize
local GRID_X        = 262  -- grid origin within the page
local GRID_Y        = -96
local PICKER_WIDTH  = 236
local PICKER_TOP    = -96
local PICKER_HEIGHT = 400
local ROW_HEIGHT    = 26

local COLS, ROWS = Data.GRID_COLS, Data.GRID_ROWS

-- Editing state. editSpecID may be any spec of the player's class, so a layout
-- can be built for a spec before ever stepping into it.
Page.editSpecID = nil
Page.selectedKey = nil
Page.armedSpellID = nil
Page.anchorMode = false

local drag = { active = false, spellID = nil, fromKey = nil }

local BuildAnchorOverlay  -- defined below, called from BuildGrid

local function Profile()
    return Data.GetProfile(Page.editSpecID)
end

--- True while the profile on screen is the one the runtime is actually drawing.
local function EditingActiveSpec()
    return Page.editSpecID == Data.GetActiveSpecID()
end

--- Push an edit into the live viewer, but only when it would change what is on
--- screen -- editing a dormant spec's layout must not disturb the current one.
--- Preview counts, because preview deliberately draws the spec being edited.
local function Apply()
    if EditingActiveSpec() or CV.previewMode then
        CV:Rebuild()
    end
end

-- ----------------------------------------------------------------------------
-- Drag follower
-- ----------------------------------------------------------------------------

local follower
local function EnsureFollower()
    if follower then return follower end
    follower = CreateFrame("Frame", nil, UIParent)
    follower:SetSize(CELL, CELL)
    follower:SetFrameStrata("TOOLTIP")
    follower:Hide()
    local tex = follower:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    follower.tex = tex
    follower:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
    return follower
end

local function BeginDrag(spellID, fromKey)
    drag.active, drag.spellID, drag.fromKey = true, spellID, fromKey
    local f = EnsureFollower()
    f.tex:SetTexture(C_Spell.GetSpellTexture(spellID))
    f:ClearAllPoints()
    f:Show()
end

local function EndDrag()
    drag.active, drag.spellID, drag.fromKey = false, nil, nil
    if follower then follower:Hide() end
end

-- ----------------------------------------------------------------------------
-- Placement operations
-- ----------------------------------------------------------------------------

local function PlaceSpell(row, col, spellID, fromKey)
    local profile = Profile()

    if fromKey then
        local fromRow, fromCol = Data.ParseCellKey(fromKey)
        Data.MovePlacement(profile, fromRow, fromCol, row, col)
    else
        local existing = Data.GetPlacement(profile, row, col)
        Data.SetPlacement(profile, row, col, spellID, existing and existing.mode or "cooldown")
    end

    Page.selectedKey = Data.CellKey(row, col)
    Page.armedSpellID = nil
    Apply()
    Page:Refresh()
end

local function RemoveAt(key)
    local row, col = Data.ParseCellKey(key)
    Data.ClearPlacement(Profile(), row, col)
    if Page.selectedKey == key then Page.selectedKey = nil end
    Apply()
    Page:Refresh()
end

-- ----------------------------------------------------------------------------
-- Grid
-- ----------------------------------------------------------------------------

local function BuildGrid(host)
    local grid = CreateFrame("Frame", nil, host)
    grid:SetSize(COLS * CELL, ROWS * CELL)
    grid:SetPoint("TOPLEFT", host, "TOPLEFT", GRID_X, GRID_Y)
    Page.grid = grid

    local frame = grid:CreateTexture(nil, "BACKGROUND")
    frame:SetPoint("TOPLEFT", -2, 2)
    frame:SetPoint("BOTTOMRIGHT", 2, -2)
    frame:SetColorTexture(0, 0, 0, 0.55)

    Page.cells = {}

    for row = 1, ROWS do
        for col = 1, COLS do
            local key = Data.CellKey(row, col)

            local cell = CreateFrame("Button", nil, grid)
            cell:SetSize(CELL, CELL)
            cell:SetPoint("TOPLEFT", grid, "TOPLEFT", (col - 1) * CELL, -(row - 1) * CELL)
            cell.row, cell.col, cell.key = row, col, key

            local border = cell:CreateTexture(nil, "BACKGROUND")
            border:SetAllPoints()
            border:SetColorTexture(0.35, 0.35, 0.4, 0.5)
            local inner = cell:CreateTexture(nil, "BORDER")
            inner:SetPoint("TOPLEFT", 1, -1)
            inner:SetPoint("BOTTOMRIGHT", -1, 1)
            inner:SetColorTexture(0.08, 0.08, 0.10, 0.9)

            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", -2, 2)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:Hide()
            cell.icon = icon

            local selected = cell:CreateTexture(nil, "OVERLAY")
            selected:SetPoint("TOPLEFT", -1, 1)
            selected:SetPoint("BOTTOMRIGHT", 1, -1)
            selected:SetColorTexture(0, 1, 0.8, 0.35)
            selected:Hide()
            cell.selectedTex = selected

            cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            cell:RegisterForDrag("LeftButton")

            cell:SetScript("OnDragStart", function(self)
                local placement = Data.GetPlacement(Profile(), self.row, self.col)
                if placement then BeginDrag(placement.spellID, self.key) end
            end)

            -- Dropping is resolved here rather than in OnReceiveDrag: this fires
            -- for a drag started anywhere, and IsMouseOver tells us the target
            -- without depending on Blizzard's cursor-payload plumbing.
            cell:SetScript("OnDragStop", function()
                if not drag.active then return end
                for _, target in pairs(Page.cells) do
                    if target:IsMouseOver() then
                        PlaceSpell(target.row, target.col, drag.spellID, drag.fromKey)
                        EndDrag()
                        return
                    end
                end
                -- Dragged off the grid entirely: that means remove.
                if drag.fromKey then RemoveAt(drag.fromKey) end
                EndDrag()
            end)

            cell:SetScript("OnClick", function(self, button)
                local placement = Data.GetPlacement(Profile(), self.row, self.col)

                if button == "RightButton" then
                    if placement then RemoveAt(self.key) end
                    return
                end

                if Page.armedSpellID and not placement then
                    PlaceSpell(self.row, self.col, Page.armedSpellID)
                elseif placement then
                    Page.selectedKey = self.key
                    Page:Refresh()
                end
            end)

            cell:SetScript("OnEnter", function(self)
                local placement = Data.GetPlacement(Profile(), self.row, self.col)
                if not placement then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(placement.spellID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(Data.ModeText(placement.mode), 0, 1, 0.8)
                GameTooltip:AddLine("Right-click to remove", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

            Page.cells[key] = cell
        end
    end

    BuildAnchorOverlay(grid)
    return grid
end

-- ----------------------------------------------------------------------------
-- Anchor overlay -- 121 radios, one per grid-line intersection
-- ----------------------------------------------------------------------------

function BuildAnchorOverlay(grid)  -- luacheck: ignore (forward-declared above)
    local overlay = CreateFrame("Frame", nil, grid)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(grid:GetFrameLevel() + 10)
    overlay:Hide()
    Page.anchorOverlay = overlay

    local dim = overlay:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.45)

    Page.anchorRadios = {}

    for row = 0, ROWS do
        for col = 0, COLS do
            local radio = CreateFrame("CheckButton", nil, overlay, "UIRadioButtonTemplate")
            radio:SetPoint("CENTER", grid, "TOPLEFT", col * CELL, -row * CELL)
            radio.col, radio.row = col, row
            radio:SetScript("OnClick", function(self)
                if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
                local profile = Profile()
                profile.anchorCol, profile.anchorRow = self.col, self.row
                Apply()
                Page:Refresh()
            end)
            radio:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(("Anchor at column %d, row %d"):format(self.col, self.row))
                GameTooltip:AddLine("The cursor sits on this point.", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            radio:SetScript("OnLeave", function() GameTooltip:Hide() end)

            Page.anchorRadios[row * (COLS + 1) + col] = radio
        end
    end

    -- Live marker showing the current anchor. Always visible, not just in
    -- anchor mode, so the relationship between shape and cursor stays on screen
    -- while icons are being arranged.
    --
    -- It gets its own frame rather than being a texture on the grid: cells are
    -- child frames of the grid, and a child frame draws above every texture its
    -- parent owns regardless of draw layer, so a marker on the grid itself
    -- would sit behind the cells it is meant to point at.
    local markerHost = CreateFrame("Frame", nil, grid)
    markerHost:SetAllPoints()
    markerHost:SetFrameLevel(grid:GetFrameLevel() + 5)

    local marker = markerHost:CreateTexture(nil, "OVERLAY")
    marker:SetSize(18, 18)
    marker:SetTexture("Interface\\AddOns\\ThugUI\\media\\Reticle_Dot")
    marker:SetVertexColor(0, 1, 0.8, 1)
    Page.anchorMarker = marker
    Page.anchorMarkerHost = markerHost
end

-- ----------------------------------------------------------------------------
-- Spell picker
-- ----------------------------------------------------------------------------

local function BuildPicker(host)
    local picker = CreateFrame("Frame", nil, host, "BackdropTemplate")
    picker:SetSize(PICKER_WIDTH, PICKER_HEIGHT)
    picker:SetPoint("TOPLEFT", host, "TOPLEFT", 0, PICKER_TOP)
    picker:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    picker:SetBackdropColor(0, 0, 0, 0.4)
    picker:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    Page.picker = picker

    Page.pickerSource = Page.pickerSource or "essential"
    Page.pickerSearch = ""

    local sourceDD = W.CreateDropdown(picker, PICKER_WIDTH - 24, Data.SOURCES,
        function() return Page.pickerSource end,
        function(value)
            Page.pickerSource = value
            Page:RefreshPicker()
        end)
    sourceDD:SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -8)

    local search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    search:SetSize(PICKER_WIDTH - 24, 22)
    search:SetPoint("TOPLEFT", sourceDD, "BOTTOMLEFT", 4, -6)
    search:SetScript("OnTextChanged", function(self, userInput)
        -- SearchBoxTemplate's own handler drives the clear button and the
        -- "Search" placeholder; skipping it leaves the box looking broken.
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        if userInput then
            Page.pickerSearch = self:GetText()
            Page:RefreshPicker()
        end
    end)
    Page.pickerSearchBox = search

    local scroll = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -8)
    scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -26, 10)

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(PICKER_WIDTH - 40, 1)
    scroll:SetScrollChild(list)
    Page.pickerList = list
    Page.pickerRows = {}

    -- Shown when a source has nothing to offer -- a spec Blizzard has not
    -- categorised, or a search with no hits. An empty box with no explanation
    -- reads as a broken picker.
    local empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -10)
    empty:SetWidth(PICKER_WIDTH - 44)
    empty:SetJustifyH("LEFT")
    empty:SetText("Nothing here. Try another source, or clear the search.")
    empty:Hide()
    Page.pickerEmpty = empty

    return picker
end

local function AcquirePickerRow(index)
    local row = Page.pickerRows[index]
    if row then return row end

    row = CreateFrame("Button", nil, Page.pickerList)
    row:SetSize(PICKER_WIDTH - 44, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", Page.pickerList, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 2, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local armed = row:CreateTexture(nil, "BACKGROUND")
    armed:SetAllPoints()
    armed:SetColorTexture(0, 1, 0.8, 0.25)
    armed:Hide()
    row.armedTex = armed

    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row:RegisterForDrag("LeftButton")

    row:SetScript("OnDragStart", function(self)
        if self.spellID then BeginDrag(self.spellID, nil) end
    end)
    row:SetScript("OnDragStop", function()
        if not drag.active then return end
        for _, cell in pairs(Page.cells) do
            if cell:IsMouseOver() then
                PlaceSpell(cell.row, cell.col, drag.spellID, nil)
                EndDrag()
                return
            end
        end
        EndDrag()
    end)

    -- Click-to-arm, then click a cell. Drag is nicer; this is the path that
    -- always works, including for anyone who finds drag fiddly.
    row:SetScript("OnClick", function(self)
        Page.armedSpellID = (Page.armedSpellID ~= self.spellID) and self.spellID or nil
        Page:Refresh()
    end)

    row:SetScript("OnEnter", function(self)
        if not self.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag onto the grid, or click then click a cell.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Page.pickerRows[index] = row
    return row
end

function Page:RefreshPicker()
    local entries = Data.BuildSpellList(self.pickerSource, self.pickerSearch)
    local profile = Profile()

    for i, entry in ipairs(entries) do
        local row = AcquirePickerRow(i)
        row.spellID = entry.spellID
        row.icon:SetTexture(entry.icon)

        -- Already-placed spells stay in the list but read as spent, so the
        -- catalogue does not reshuffle every time something is dropped.
        if Data.IsSpellPlaced(profile, entry.spellID) then
            row.label:SetText("|cff808080" .. entry.name .. "|r")
        else
            row.label:SetText(entry.name)
        end
        row.armedTex:SetShown(self.armedSpellID == entry.spellID)
        row:Show()
    end

    for i = #entries + 1, #self.pickerRows do
        self.pickerRows[i]:Hide()
    end

    self.pickerList:SetHeight(math.max(#entries * ROW_HEIGHT, 1))

    if self.pickerEmpty then
        self.pickerEmpty:SetShown(#entries == 0)
    end
end

-- ----------------------------------------------------------------------------
-- Page assembly
-- ----------------------------------------------------------------------------

function Page:Build(host, panel)
    self.host = host
    self.editSpecID = self.editSpecID or Data.GetActiveSpecID()

    local title = host:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetText("Cooldown Viewer")

    local subtitle = host:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(700)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Per-specialization layouts. The grid is a map of what rides on your cursor — "
        .. "in combat the scaffold disappears and only the icons show.")

    -- Spec selector ------------------------------------------------------
    local specDD = W.CreateDropdown(host, 190,
        function()
            local options = {}
            for _, spec in ipairs(Data.GetPlayerSpecs()) do
                local label = spec.name
                if spec.specID == Data.GetActiveSpecID() then
                    label = label .. " |cff00ff88(active)|r"
                end
                table.insert(options, { value = spec.specID, text = label })
            end
            return options
        end,
        function() return Page.editSpecID end,
        function(value)
            Page.editSpecID = value
            Page.selectedKey = nil
            Page.armedSpellID = nil
            -- Keep an open preview pointed at whatever is being edited.
            if CV.previewMode then CV:SetPreview(true, value) end
            Page:Refresh()
        end)
    specDD:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -62)
    self.specDD = specDD

    local function MakeCheck(label, x, get, set, tooltip)
        local cb = CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", host, "TOPLEFT", x, -62)
        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        text:SetText(label)
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            Apply()
            Page:Refresh()
        end)
        cb.Refresh = function(self) self:SetChecked(get() and true or false) end
        W.AttachTooltip(cb, label, tooltip)
        return cb
    end

    self.enabledCB = MakeCheck("Enabled", 210,
        function() return Profile().enabled end,
        function(v) Profile().enabled = v end,
        "Turn this spec's cooldown viewer on.")

    self.combatCB = MakeCheck("Only in combat", 320,
        function() return Profile().onlyInCombat end,
        function(v) Profile().onlyInCombat = v end,
        "Hide the icons entirely while out of combat.")

    self.cursorCB = MakeCheck("Follow cursor", 470,
        function() return Profile().followCursor end,
        function(v) Profile().followCursor = v end,
        "Ride the mouse. Unticked, the shape stays where you drag it.")

    local previewCB = MakeCheck("Preview on screen", 610,
        function() return CV.previewMode end,
        function(v) CV:SetPreview(v, Page.editSpecID) end,
        "Draw this layout on screen, ignoring combat and cooldown state, so you can see "
            .. "the shape while you build it.")
    self.previewCB = previewCB

    BuildPicker(host)
    BuildGrid(host)
    self:BuildInspector(host)

    -- Preview switches itself off with the window; leaving a forced-visible
    -- overlay behind after closing settings would look like a bug.
    ThugUI.Window.frame:HookScript("OnHide", function()
        if CV.previewMode then CV:SetPreview(false) end
        Page.armedSpellID = nil
    end)
end

function Page:BuildInspector(host)
    local x = GRID_X + COLS * CELL + 22
    local panel = W.NewPanel(host, { x = x, y = 96, width = 200 })
    self.inspectorPanel = panel

    panel:Section("Selected icon")

    local sel = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sel:SetWidth(200)
    sel:SetJustifyH("LEFT")
    panel:Place(sel, 34, { gap = 4 })
    self.selectedLabel = sel

    panel:Dropdown{
        options = Data.MODES,
        width = 190,
        get = function()
            local key = Page.selectedKey
            if not key then return "cooldown" end
            local row, col = Data.ParseCellKey(key)
            local placement = Data.GetPlacement(Profile(), row, col)
            return placement and placement.mode or "cooldown"
        end,
        set = function(value)
            local key = Page.selectedKey
            if not key then return end
            local row, col = Data.ParseCellKey(key)
            local placement = Data.GetPlacement(Profile(), row, col)
            if placement then
                placement.mode = value
                Apply()
            end
        end,
    }

    panel:Button{
        label = "Remove icon",
        width = 190,
        onClick = function()
            if Page.selectedKey then RemoveAt(Page.selectedKey) end
        end,
    }

    panel:Section("Anchor")

    -- Seeded with a full-length string so the layout cursor reserves the right
    -- height; Note sizes itself from the text present at build time.
    self.anchorLabel = panel:Note("Cursor holds the grid at column 0, row 0.", { width = 200 })

    panel:Button{
        label = "Set cursor anchor",
        width = 190,
        tooltip = "Show a marker at every grid-line intersection and pick the one the cursor holds.",
        onClick = function(btn)
            Page.anchorMode = not Page.anchorMode
            btn:SetText(Page.anchorMode and "Done choosing" or "Set cursor anchor")
            Page:Refresh()
        end,
    }

    panel:Section("Collapse")

    panel:Dropdown{
        options = Data.COLLAPSE_MODES,
        width = 190,
        get = function() return Profile().collapse or "none" end,
        set = function(v)
            local profile = Profile()
            profile.collapse = v
            -- Direction is per-axis. Carrying "left" into columns mode would
            -- leave the menu showing a value that does nothing, so switching
            -- axis resets to auto.
            if not Data.IsDirectionValid(v, profile.collapseDirection) then
                profile.collapseDirection = "auto"
            end
            Apply()
            Page:Refresh()
        end,
    }

    panel:Dropdown{
        options = function()
            return Data.GetCollapseDirections(Profile().collapse or "rows")
        end,
        width = 190,
        get = function() return Profile().collapseDirection or "auto" end,
        set = function(v) Profile().collapseDirection = v; Apply(); Page:Refresh() end,
    }

    -- Seeded at the longest wording it can hold, because Note reserves height
    -- from the text present at build time.
    self.collapseNote = panel:Note(
        "Rows pack left. Icons close up as they go on cooldown, and a gap you "
        .. "left between clusters closes too — tick preview to see the real shape.",
        { width = 200 })

    panel:Section("Size and spacing")

    panel:Slider{
        label = "Icon size", min = 16, max = 64, step = 2, width = 150, format = "%d",
        get = function() return Profile().iconSize end,
        set = function(v) Profile().iconSize = v; Apply() end,
    }
    panel:Slider{
        label = "Padding", min = 0, max = 20, step = 1, width = 150, format = "%d",
        get = function() return Profile().padding end,
        set = function(v) Profile().padding = v; Apply() end,
    }
    panel:Slider{
        label = "Scale", min = 0.5, max = 2.0, step = 0.05, width = 150, format = "%.2f",
        get = function() return Profile().scale end,
        set = function(v) Profile().scale = v; Apply() end,
    }

    panel:Gap(6)
    panel:Button{
        label = "Clear this layout",
        width = 190,
        tooltip = "Remove every icon from this spec's grid. Does not touch other specs.",
        onClick = function()
            wipe(Profile().placements)
            Page.selectedKey = nil
            Apply()
            Page:Refresh()
        end,
    }
end

-- ----------------------------------------------------------------------------
-- Refresh
-- ----------------------------------------------------------------------------

function Page:Refresh()
    if not self.host then return end
    self.editSpecID = self.editSpecID or Data.GetActiveSpecID()

    local profile = Profile()

    self.specDD:Refresh()
    self.enabledCB:Refresh()
    self.combatCB:Refresh()
    self.cursorCB:Refresh()
    self.previewCB:Refresh()

    -- Grid cells
    for key, cell in pairs(self.cells) do
        local row, col = Data.ParseCellKey(key)
        local placement = Data.GetPlacement(profile, row, col)
        if placement then
            cell.icon:SetTexture(C_Spell.GetSpellTexture(placement.spellID))
            cell.icon:Show()
        else
            cell.icon:Hide()
        end
        cell.selectedTex:SetShown(self.selectedKey == key)
    end

    -- Anchor overlay and marker
    self.anchorOverlay:SetShown(self.anchorMode)
    for _, radio in pairs(self.anchorRadios) do
        radio:SetChecked(radio.col == profile.anchorCol and radio.row == profile.anchorRow)
    end
    self.anchorMarker:ClearAllPoints()
    self.anchorMarker:SetPoint("CENTER", self.grid, "TOPLEFT",
        (profile.anchorCol or 0) * CELL, -(profile.anchorRow or 0) * CELL)

    self.anchorLabel:SetText(("Cursor holds the grid at column %d, row %d.")
        :format(profile.anchorCol or 0, profile.anchorRow or 0))

    local mode = profile.collapse or "none"
    if mode == "rows" then
        self.collapseNote:SetText(("Rows pack %s. Each row closes up on its own, so an icon "
            .. "never changes row. A gap you left between clusters closes too.")
            :format(Data.ResolveCollapseDirection(profile)))
    elseif mode == "columns" then
        self.collapseNote:SetText(("Columns pack %s. When a column empties, the rest slide "
            .. "%s to fill the gap.")
            :format(Data.ResolveCollapseDirection(profile), Data.ResolveColumnShift(profile)))
    else
        self.collapseNote:SetText("Icons hold their cells. A spell on cooldown leaves a hole "
            .. "where it was.")
    end

    -- Inspector
    if self.selectedKey then
        local row, col = Data.ParseCellKey(self.selectedKey)
        local placement = Data.GetPlacement(profile, row, col)
        if placement then
            local info = C_Spell.GetSpellInfo(placement.spellID)
            self.selectedLabel:SetText(("|cffffffff%s|r\ncell %d,%d")
                :format(info and info.name or ("#" .. placement.spellID), col, row))
        else
            self.selectedKey = nil
        end
    end
    if not self.selectedKey then
        self.selectedLabel:SetText("|cff808080Click an icon on the grid.|r")
    end

    if self.inspectorPanel then self.inspectorPanel:Refresh() end
    self:RefreshPicker()
end

-- ----------------------------------------------------------------------------

ThugUI.Window:RegisterPage{
    id = "cooldownviewer",
    title = "Cooldown Viewer",
    order = 10,
    scroll = false,
    build = function(host, panel) Page:Build(host, panel) end,
    refresh = function() Page:Refresh() end,
}

return Page
