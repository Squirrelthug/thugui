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
-- Level with the grid (GRID_Y + 10 cells), so the settings band below starts
-- clear of both columns rather than colliding with a taller picker.
local PICKER_HEIGHT = 320
local ROW_HEIGHT    = 26

local COLS, ROWS = Data.GRID_COLS, Data.GRID_ROWS

-- Editing state. editSpecID may be any spec of the player's class, so a layout
-- can be built for a spec before ever stepping into it.
Page.editSpecID = nil
Page.selectedKey = nil
-- The armed picker row (or nil), as an IDENTITY table: { spellID = n } or
-- { categoryID = n }, never a bare number. A category placement has no spell
-- ID to be one, so a single field would have to lie about which kind it held.
-- Compared through Data.PlacementKey wherever "is this the same thing" is the
-- question -- never field-by-field. Task 18; DECISIONS.md §25.
Page.armed = nil
Page.anchorMode = false

local drag = { active = false, identity = nil, fromKey = nil }

local BuildAnchorOverlay  -- defined below, called from BuildGrid

--- The identity of whatever a placement (or a picker row -- both shapes carry
--- spellID/categoryID the same way) stands for, as {spellID=} or
--- {categoryID=}. Centralised so every drag/click/tooltip site builds the
--- same shape rather than five slightly different inline tables.
local function PlacementIdentity(placement)
    if not placement then return nil end
    if placement.categoryID then return { categoryID = placement.categoryID } end
    return { spellID = placement.spellID }
end

--- The texture for a picker row or a placement, whichever kind it is.
local function IdentityTexture(identity)
    if not identity then return nil end
    if identity.categoryID then
        local entry = Data.CategoryEntry(identity.categoryID)
        return entry and entry.icon
    end
    return C_Spell.GetSpellTexture(identity.spellID)
end

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

--- Flip whether Blizzard's tracked-buff frames are borrowed for buff-mode
--- cells. The checkbox that drives this now lives in the guide panel (a
--- different file, ui/pages/CooldownViewerGuide.lua), so this is exposed as
--- the one function it calls rather than have it copy Apply()'s effect and
--- the picker refresh inline.
function Page:SetUseBlizzardBuffs(v)
    ThugUI_Config.cvUseBlizzardBuffs = v
    if CV.BlizzBuffs then
        CV.BlizzBuffs:Refresh()
    end
    Apply()
    -- Apply() only rebuilds the live viewer. The picker offers tracked
    -- buffs only while this is on, so the list itself changes with the
    -- tick and has to be re-read here.
    self:RefreshPicker()
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

local function BeginDrag(identity, fromKey)
    drag.active, drag.identity, drag.fromKey = true, identity, fromKey
    local f = EnsureFollower()
    f.tex:SetTexture(IdentityTexture(identity))
    f:ClearAllPoints()
    f:Show()
end

local function EndDrag()
    drag.active, drag.identity, drag.fromKey = false, nil, nil
    if follower then follower:Hide() end
end

-- ----------------------------------------------------------------------------
-- Placement operations
-- ----------------------------------------------------------------------------

--- @param identity table {spellID=} or {categoryID=} -- see PlacementIdentity
local function PlaceSpell(row, col, identity, fromKey)
    local profile = Profile()

    if fromKey then
        local fromRow, fromCol = Data.ParseCellKey(fromKey)
        Data.MovePlacement(profile, fromRow, fromCol, row, col)
    else
        local existing = Data.GetPlacement(profile, row, col)
        local mode = existing and existing.mode or "cooldown"
        if identity.categoryID then
            Data.SetCategoryPlacement(profile, row, col, identity.categoryID, mode)
        else
            Data.SetPlacement(profile, row, col, identity.spellID, mode)
        end
    end

    Page.selectedKey = Data.CellKey(row, col)
    Page.armed = nil
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
                if placement then BeginDrag(PlacementIdentity(placement), self.key) end
            end)

            -- Dropping is resolved here rather than in OnReceiveDrag: this fires
            -- for a drag started anywhere, and IsMouseOver tells us the target
            -- without depending on Blizzard's cursor-payload plumbing.
            cell:SetScript("OnDragStop", function()
                if not drag.active then return end
                for _, target in pairs(Page.cells) do
                    if target:IsMouseOver() then
                        PlaceSpell(target.row, target.col, drag.identity, drag.fromKey)
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

                if Page.armed and not placement then
                    PlaceSpell(self.row, self.col, Page.armed)
                elseif placement then
                    Page.selectedKey = self.key
                    Page:Refresh()
                end
            end)

            cell:SetScript("OnEnter", function(self)
                local placement = Data.GetPlacement(Profile(), self.row, self.col)
                if not placement then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if placement.categoryID then
                    -- No spell ID to hand SetSpellByID -- a category placement
                    -- is named from the same resolution the grid draws it
                    -- with, not a Blizzard tooltip.
                    GameTooltip:SetText(Data.CategoryEntry(placement.categoryID).name)
                else
                    GameTooltip:SetSpellByID(placement.spellID)
                end
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
        if self.spellID or self.categoryID then BeginDrag(PlacementIdentity(self), nil) end
    end)
    row:SetScript("OnDragStop", function()
        if not drag.active then return end
        for _, cell in pairs(Page.cells) do
            if cell:IsMouseOver() then
                PlaceSpell(cell.row, cell.col, drag.identity, nil)
                EndDrag()
                return
            end
        end
        EndDrag()
    end)

    -- Click-to-arm, then click a cell. Drag is nicer; this is the path that
    -- always works, including for anyone who finds drag fiddly.
    --
    -- Compared through Data.PlacementKey rather than a field-by-field check:
    -- a category row and a spell row can share the same NUMBER (category 4
    -- and spell 4 are unrelated), so only the string-vs-number-typed key can
    -- tell them apart.
    row:SetScript("OnClick", function(self)
        local identity = PlacementIdentity(self)
        if Data.PlacementKey(Page.armed) == Data.PlacementKey(identity) then
            Page.armed = nil
        else
            Page.armed = identity
        end
        Page:Refresh()
    end)

    row:SetScript("OnEnter", function(self)
        if not self.spellID and not self.categoryID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.categoryID then
            GameTooltip:SetText(Data.CategoryEntry(self.categoryID).name)
        else
            GameTooltip:SetSpellByID(self.spellID)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag onto the grid, or click then click a cell.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Page.pickerRows[index] = row
    return row
end

--- Which mode family a row under this picker source should grey against.
---
--- The "buffs" source shows tracked buffs, which only ever draw as an aura-
--- mode placement, so only an aura placement of the same spell means "already
--- here". Every other curated source (essential, utility, spellbook) draws a
--- spell icon, which is any non-aura mode, so only THOSE placements count --
--- Roll the Bones placed as a buff must not grey it under Essential cooldowns.
--- "all" has no single category to judge a row against, so it keeps the old,
--- broader behaviour: grey on any placement at all. This is a page-level
--- decision, not Data's -- Data has no notion of a "picker source".
local function GreyMode(source)
    if source == "buffs" then return "aura" end
    if source == "all" then return nil end
    return "other"
end

function Page:RefreshPicker()
    local entries = Data.BuildSpellList(self.pickerSource, self.pickerSearch)
    local profile = Profile()
    local greyMode = GreyMode(self.pickerSource)

    for i, entry in ipairs(entries) do
        local row = AcquirePickerRow(i)
        row.spellID = entry.spellID
        -- Rows are pooled; a row that was a category row last refresh must
        -- not leave a stale categoryID on the spell entry that reuses it.
        row.categoryID = entry.categoryID
        row.icon:SetTexture(entry.icon)

        -- Already-placed spells stay in the list but read as spent, so the
        -- catalogue does not reshuffle every time something is dropped.
        -- Keyed through PlacementKey so a category entry greys against a
        -- category placement, never against a same-numbered spell placement.
        if Data.IsSpellPlaced(profile, Data.PlacementKey(entry), greyMode) then
            row.label:SetText("|cff808080" .. entry.name .. "|r")
        else
            row.label:SetText(entry.name)
        end
        row.armedTex:SetShown(Data.PlacementKey(Page.armed) == Data.PlacementKey(entry))
        row:Show()
    end

    for i = #entries + 1, #self.pickerRows do
        self.pickerRows[i]:Hide()
    end

    self.pickerList:SetHeight(math.max(#entries * ROW_HEIGHT, 1))

    if self.pickerEmpty then
        local empty = #entries == 0
        -- An empty list has two very different causes. "Blizzard never
        -- categorised this spec" is answered by trying another source; "you
        -- turned the workaround off" is answered by turning it back on, and the
        -- generic wording sends the player hunting for a problem that is not
        -- there. This is the only place they would find out.
        if empty and self.pickerSource == "buffs" and not Data.BuffsAvailable() then
            -- Points at the red [WORKAROUND] link instead of naming a checkbox
            -- that no longer lives on this page (it moved to the guide panel).
            -- |cffff2121 is the same red CreateLink uses for that link
            -- (SetTextColor(1, 0.13, 0.13) in CooldownViewerGuide.lua) --
            -- reused rather than picking a second red for the same thing.
            self.pickerEmpty:SetText("Tracked buffs require specific settings. Look for "
                .. "|cffff2121[WORKAROUND]|r at bottom right of this window")
        else
            self.pickerEmpty:SetText("Nothing here. Try another source, or clear the search.")
        end
        self.pickerEmpty:SetShown(empty)
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
    subtitle:SetText("Per-specialization layouts. The grid is a map of what rides on your cursor - "
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
            Page.armed = nil
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

    -- Built now rather than on the first click: it hangs off the config window
    -- frame, which exists by the time a page is built, and building it once
    -- here is what lets it be shown/hidden forever after.
    if CV.BuffGuide then CV.BuffGuide:Ensure() end

    -- Preview switches itself off with the window; leaving a forced-visible
    -- overlay behind after closing settings would look like a bug.
    ThugUI.Window.frame:HookScript("OnHide", function()
        if CV.previewMode then CV:SetPreview(false) end
        Page.armedSpellID = nil
    end)
end

-- ----------------------------------------------------------------------------
-- Controls
--
-- Split across two regions rather than one tall right-hand column. Stacked
-- together they ran roughly 670px into a ~614px frame and the bottom controls
-- fell off the window.
--
-- The division is by subject, not just to save space:
--   right column  what is true of the SELECTED ICON, beside the grid it
--                 belongs to
--   bottom band   what is true of the WHOLE PROFILE, spanning the width under
--                 the grid, where wide controls like sliders actually fit
-- ----------------------------------------------------------------------------

local BAND_TOP = 436          -- below the grid (96 + 10*32 = 416) plus a gutter
local BAND_COL_1 = 0
local BAND_COL_2 = 276
local BAND_COL_3 = 552

-- Registered once at file scope rather than inside BuildInspector, which can
-- run more than once (e.g. a fresh page build) -- StaticPopupDialogs is a
-- shared Blizzard table, and re-registering the same key on every build is
-- pointless churn. OnAccept closes over Profile()/Apply()/Page the same way
-- the rest of this file does, rather than capturing anything from a build call.
StaticPopupDialogs["THUGUI_CV_CLEAR_LAYOUT"] = {
    text = "Remove every icon from %s's layout? Other specs are untouched.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        wipe(Profile().placements)
        Page.selectedKey = nil
        Apply()
        Page:Refresh()
    end,
    timeout = 0,          -- a destructive confirmation must not time out into either answer
    whileDead = true,
    hideOnEscape = true,  -- Escape has to mean "no"
    preferredIndex = 3,   -- avoids a taint error when another popup is already showing
}

function Page:BuildInspector(host)
    self.panels = {}

    local function NewPanel(x, y, width)
        local panel = W.NewPanel(host, { x = x, y = y, width = width })
        table.insert(self.panels, panel)
        return panel
    end

    -- Right column: the selected icon and where the shape hangs off the cursor.
    local right = NewPanel(GRID_X + COLS * CELL + 22, 96, 200)
    self.inspectorPanel = right

    right:Section("Selected icon")

    local sel = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sel:SetWidth(200)
    sel:SetJustifyH("LEFT")
    right:Place(sel, 34, { gap = 4 })
    self.selectedLabel = sel

    right:Dropdown{
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

    right:Button{
        label = "Remove icon",
        width = 190,
        onClick = function()
            if Page.selectedKey then RemoveAt(Page.selectedKey) end
        end,
    }

    right:Section("Anchor")

    -- Seeded with a full-length string so the layout cursor reserves the right
    -- height; Note sizes itself from the text present at build time.
    self.anchorLabel = right:Note("Cursor holds the grid at column 0, row 0.", { width = 200 })

    right:Button{
        label = "Set cursor anchor",
        width = 190,
        tooltip = "Show a marker at every grid-line intersection and pick the one the cursor holds.",
        onClick = function(btn)
            Page.anchorMode = not Page.anchorMode
            btn:SetText(Page.anchorMode and "Done choosing" or "Set cursor anchor")
            Page:Refresh()
        end,
    }

    -- Bottom band, column 1: collapse.
    local collapse = NewPanel(BAND_COL_1, BAND_TOP, 250)

    collapse:Section("Collapse")

    collapse:Dropdown{
        options = Data.COLLAPSE_MODES,
        width = 230,
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

    collapse:Dropdown{
        options = function()
            return Data.GetCollapseDirections(Profile().collapse or "rows")
        end,
        width = 230,
        get = function() return Profile().collapseDirection or "auto" end,
        set = function(v) Profile().collapseDirection = v; Apply(); Page:Refresh() end,
    }

    -- Seeded at the longest wording it can hold, because Note reserves height
    -- from the text present at build time.
    self.collapseNote = collapse:Note(
        "Rows pack left. Each row closes up on its own, so an icon never changes "
        .. "row. A gap you left between clusters closes too.",
        { width = 250 })

    -- Bottom band, column 2: geometry. Sliders are the widest controls here,
    -- which is most of why this band exists.
    local size = NewPanel(BAND_COL_2, BAND_TOP, 250)

    size:Section("Size and spacing")

    size:Slider{
        label = "Icon size", min = 16, max = 64, step = 2, width = 150, format = "%d",
        get = function() return Profile().iconSize end,
        set = function(v) Profile().iconSize = v; Apply() end,
    }
    size:Slider{
        label = "Padding", min = 0, max = 20, step = 1, width = 150, format = "%d",
        get = function() return Profile().padding end,
        set = function(v) Profile().padding = v; Apply() end,
    }
    size:Slider{
        label = "Scale", min = 0.5, max = 2.0, step = 0.05, width = 150, format = "%.2f",
        get = function() return Profile().scale end,
        set = function(v) Profile().scale = v; Apply() end,
    }

    -- Bottom band, column 3: everything else about this layout.
    local misc = NewPanel(BAND_COL_3, BAND_TOP, 260)

    misc:Section("This layout")

    misc:Checkbox{
        label = "Show proc glow",
        tooltip = "The same pulsing highlight an action button gets when a proc makes a "
            .. "spell free or empowered - Opportunity on Pistol Shot, for instance. Uses "
            .. "Blizzard's own alert art, so it reads identically to your action bars.",
        get = function() return Profile().showProcGlow ~= false end,
        set = function(v) Profile().showProcGlow = v; Apply() end,
    }

    -- This used to be a paragraph of grey text, and it was not enough. Blizzard
    -- only hands over a buff it is already tracking, the picker happily offers
    -- buffs that are in neither of the game's two lists, and the failure is
    -- silent -- an empty cell looks exactly like a broken addon. The steps are
    -- now a panel of their own with the screenshots to match; this is the way
    -- in. ui/pages/CooldownViewerGuide.lua.
    -- Section (not Label) so the red link below reads as visually separate
    -- from the layout controls above it, matching "This layout"'s own style.
    -- Section already opens with its own Gap(12), so nothing extra is added
    -- here.
    misc:Section("Enable Buffs")
    if CV.BuffGuide then CV.BuffGuide:CreateLink(misc) end

    misc:Gap(10)
    -- Stored on Page (like selectedLabel/anchorLabel/pickerEmpty above) because
    -- Panel:Button does not register itself onto panel.widgets -- nothing else
    -- would hold a reference to drive it.
    self.clearLayoutBtn = misc:Button{
        label = "Clear this layout",
        width = 200,
        tooltip = "Remove every icon from this spec's grid. Does not touch other specs.",
        onClick = function()
            StaticPopup_Show("THUGUI_CV_CLEAR_LAYOUT", Data.GetSpecName(Page.editSpecID))
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
            cell.icon:SetTexture(IdentityTexture(PlacementIdentity(placement)))
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
    local horizontal, vertical = Data.DescribeCollapse(profile)

    if mode == "rows" then
        self.collapseNote:SetText(("Rows pack %s. When a row empties, the rest close %s.")
            :format(horizontal, vertical))
    elseif mode == "columns" then
        self.collapseNote:SetText(("Columns pack %s. When a column empties, the rest close %s.")
            :format(vertical, horizontal))
    elseif mode == "both" then
        self.collapseNote:SetText(("Rows pack %s, then columns pack %s, so the shape stays as "
            .. "tight as it can. Icons can change row and column.")
            :format(horizontal, vertical))
    else
        self.collapseNote:SetText("Icons hold their cells. A spell on cooldown leaves a hole "
            .. "where it was.")
    end

    -- Inspector
    if self.selectedKey then
        local row, col = Data.ParseCellKey(self.selectedKey)
        local placement = Data.GetPlacement(profile, row, col)
        if placement then
            local name
            if placement.categoryID then
                name = Data.CategoryEntry(placement.categoryID).name
            else
                local info = C_Spell.GetSpellInfo(placement.spellID)
                name = (info and info.name) or ("#" .. placement.spellID)
            end
            self.selectedLabel:SetText(("|cffffffff%s|r\ncell %d,%d")
                :format(name, col, row))
        else
            self.selectedKey = nil
        end
    end
    if not self.selectedKey then
        self.selectedLabel:SetText("|cff808080Click an icon on the grid.|r")
    end

    for _, panel in ipairs(self.panels or {}) do panel:Refresh() end
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
