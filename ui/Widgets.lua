-- ============================================================================
-- ThugUI: Widget Factory
--
-- Shared controls for the ThugUI config window (ui/Window.lua) and its pages.
--
-- Everything goes through a "panel" object rather than free functions: a panel
-- owns a parent frame, a vertical layout cursor, and the list of widgets it
-- built. That buys two things the old options.lua did not have:
--
--   * Pages lay themselves out by declaration order instead of hand-computed
--     y-offsets, so inserting a checkbox does not shift every number below it.
--   * panel:Refresh() re-reads config into the existing widgets. The old
--     RefreshContent() destroyed and rebuilt children with SetParent(nil),
--     which never frees a frame in WoW -- it just orphans it, so every visit
--     to a page leaked one full set of controls.
--
-- Dropdowns use DropdownButton/WowStyle1DropdownTemplate + MenuUtil.
-- UIDropDownMenu has been deprecated since 11.0 with no shim; the older
-- panels in modules/ still use it, but nothing new should.
-- ============================================================================

ThugUI = ThugUI or {}

local W = {}
ThugUI.Widgets = W

-- Sliders built from OptionsSliderTemplate look up $parentLow/$parentHigh/
-- $parentText by global name, which returns nothing on an anonymous frame.
-- Every slider therefore gets a real generated name.
local sliderSerial = 0
local function NextSliderName()
    sliderSerial = sliderSerial + 1
    return "ThugUI_Slider" .. sliderSerial
end

local FONT_HEADER  = "GameFontNormalLarge"
local FONT_SECTION = "GameFontNormal"
local FONT_LABEL   = "GameFontHighlight"
local FONT_NOTE    = "GameFontDisable"

local GOLD = {1.0, 0.82, 0.0}
local TEAL = {0.0, 1.0, 0.8}

-- ----------------------------------------------------------------------------
-- Tooltips
-- ----------------------------------------------------------------------------

function W.AttachTooltip(frame, title, body)
    if not title and not body then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:SetText(title, 1, 1, 1) end
        if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ----------------------------------------------------------------------------
-- Dropdown
--
-- options is either a list of {value=, text=} or a function returning one, so a
-- menu whose contents depend on live game state (the spec list, the spell
-- source list) can rebuild itself every time it opens.
-- ----------------------------------------------------------------------------

local function ResolveOptions(options)
    if type(options) == "function" then return options() or {} end
    return options or {}
end

local function OptionText(options, value)
    for _, opt in ipairs(ResolveOptions(options)) do
        if opt.value == value then return opt.text end
    end
    return nil
end

function W.CreateDropdown(parent, width, options, get, set)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width or 160)

    dd:SetupMenu(function(_, rootDescription)
        for _, opt in ipairs(ResolveOptions(options)) do
            rootDescription:CreateRadio(
                opt.text,
                function() return get() == opt.value end,
                function()
                    set(opt.value)
                    -- SetupMenu only refreshes the button text from the radio
                    -- state when the menu itself closes; setting it directly
                    -- keeps the button honest if `set` coerced the value.
                    dd:SetText(OptionText(options, get()) or opt.text)
                end
            )
        end
    end)

    function dd:Refresh()
        self:SetText(OptionText(options, get()) or "")
    end
    dd:Refresh()

    return dd
end

-- ----------------------------------------------------------------------------
-- Colour swatch. get() returns r,g,b; set(r,g,b) stores them.
-- ----------------------------------------------------------------------------

function W.CreateColorSwatch(parent, get, set)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(18, 18)

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.4, 0.4, 0.4)

    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetAllPoints()
    swatch:SetColorTexture(1, 1, 1)

    function button:Refresh()
        local r, g, b = get()
        swatch:SetVertexColor(r or 1, g or 1, b or 1)
    end

    button:SetScript("OnClick", function(self)
        local r, g, b = get()
        r, g, b = r or 1, g or 1, b or 1
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                set(nr, ng, nb)
                self:Refresh()
            end,
            cancelFunc = function()
                set(r, g, b)
                self:Refresh()
            end,
        })
    end)

    button:Refresh()
    return button
end

-- ----------------------------------------------------------------------------
-- Scroll container. Returns the scroll frame and its content child; the caller
-- sizes the child to whatever its page actually needs.
-- ----------------------------------------------------------------------------

function W.CreateScrollArea(parent, insetRight)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -(insetRight or 28), 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    return scroll, content
end

-- ============================================================================
-- PANEL -- layout cursor + widget registry
-- ============================================================================

local Panel = {}
Panel.__index = Panel

--- @param parent Frame the frame widgets are created in
--- @param opts table? { x = left margin, y = top margin, width = content width }
function W.NewPanel(parent, opts)
    opts = opts or {}
    return setmetatable({
        parent  = parent,
        originX = opts.x or 16,
        originY = -(opts.y or 14),
        width   = opts.width or (parent:GetWidth() - 32),
        cursorY = -(opts.y or 14),
        rowTopY = -(opts.y or 14),
        lastX   = opts.x or 16,
        lastW   = 0,
        widgets = {},
    }, Panel)
end

-- Place `frame` at the layout cursor and advance it.
--
-- o.sameLine keeps the cursor on the current row and places the frame to the
-- right of the previous widget, which is how "checkbox + its slider" pairs and
-- "label + dropdown" pairs are built without absolute coordinates.
function Panel:Place(frame, height, o)
    o = o or {}
    local indent = o.indent or 0

    if o.sameLine then
        local x = self.lastX + self.lastW + (o.gap or 12)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, self.rowTopY + (o.yAdjust or 0))
        self.lastX = x
        self.lastW = o.width or frame:GetWidth() or 0
        -- A taller widget on a shared row still has to push the cursor down.
        local bottom = self.rowTopY - height
        if bottom < self.cursorY then self.cursorY = bottom end
    else
        self.cursorY = self.cursorY - (o.gap or 6)
        self.rowTopY = self.cursorY
        local x = self.originX + indent
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, self.cursorY + (o.yAdjust or 0))
        self.lastX = x
        self.lastW = o.width or frame:GetWidth() or 0
        self.cursorY = self.cursorY - height
    end

    return frame
end

function Panel:Register(widget)
    if widget and widget.Refresh then
        table.insert(self.widgets, widget)
    end
    return widget
end

function Panel:Refresh()
    for _, widget in ipairs(self.widgets) do
        widget:Refresh()
    end
end

function Panel:GetHeight()
    return math.abs(self.cursorY) + 20
end

function Panel:Gap(px)
    self.cursorY = self.cursorY - (px or 10)
    self.rowTopY = self.cursorY
    return self
end

-- ----------------------------------------------------------------------------

function Panel:Header(text)
    local fs = self.parent:CreateFontString(nil, "ARTWORK", FONT_HEADER)
    fs:SetText(text)
    self:Place(fs, 22, { gap = 0 })
    return fs
end

--- A gold section title with a rule running to the right edge.
function Panel:Section(text)
    self:Gap(12)
    local fs = self.parent:CreateFontString(nil, "ARTWORK", FONT_SECTION)
    fs:SetText(text)
    fs:SetTextColor(unpack(GOLD))
    self:Place(fs, 16, { gap = 0 })

    -- Anchored by its left edge only, with an explicit width: pinning both LEFT
    -- and RIGHT to different frames makes each anchor fight over the rule's
    -- vertical centre, and it ends up off the label's baseline.
    local line = self.parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    line:SetWidth(math.max(1, self.width - fs:GetStringWidth() - 6))

    self:Gap(4)
    return fs
end

--- Dimmed explanatory text. Wraps to the panel width.
function Panel:Note(text, o)
    o = o or {}
    local fs = self.parent:CreateFontString(nil, "ARTWORK", FONT_NOTE)
    fs:SetWidth(o.width or (self.width - (o.indent or 0)))
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    self:Place(fs, fs:GetStringHeight() + 4, o)
    return fs
end

function Panel:Label(text, o)
    local fs = self.parent:CreateFontString(nil, "ARTWORK", FONT_LABEL)
    fs:SetText(text)
    self:Place(fs, 16, o)
    return fs
end

-- ----------------------------------------------------------------------------

--- opts: { label, tooltip, get, set, indent, sameLine }
function Panel:Checkbox(opts)
    local cb = CreateFrame("CheckButton", nil, self.parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)

    local label = cb:CreateFontString(nil, "OVERLAY", FONT_LABEL)
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(opts.label)

    cb:SetScript("OnClick", function(self)
        opts.set(self:GetChecked() and true or false)
    end)

    function cb:Refresh()
        self:SetChecked(opts.get() and true or false)
    end
    cb:Refresh()

    W.AttachTooltip(cb, opts.label, opts.tooltip)
    self:Place(cb, 26, {
        indent = opts.indent,
        sameLine = opts.sameLine,
        width = 28 + label:GetStringWidth(),
    })
    return self:Register(cb)
end

--- opts: { label, min, max, step, get, set, format, width, indent, sameLine }
function Panel:Slider(opts)
    local name = NextSliderName()
    local slider = CreateFrame("Slider", name, self.parent, "OptionsSliderTemplate")
    slider:SetWidth(opts.width or 160)
    slider:SetMinMaxValues(opts.min, opts.max)
    slider:SetValueStep(opts.step)
    slider:SetObeyStepOnDrag(true)

    local fmt = opts.format or "%.2f"
    local low, high = _G[name .. "Low"], _G[name .. "High"]
    if low then low:SetText(string.format(fmt, opts.min)) end
    if high then high:SetText(string.format(fmt, opts.max)) end
    if _G[name .. "Text"] then _G[name .. "Text"]:SetText(opts.label) end

    local value = slider:CreateFontString(nil, "OVERLAY", FONT_LABEL)
    value:SetPoint("LEFT", slider, "RIGHT", 10, 0)

    -- Guard against the feedback loop: Refresh() -> SetValue() -> OnValueChanged
    -- -> set() would write the value straight back into config on every page
    -- visit, which matters once a setter has side effects (rebuilding the grid).
    local updating = false
    slider:SetScript("OnValueChanged", function(self, raw)
        local steps = math.floor(raw / opts.step + 0.5)
        local snapped = steps * opts.step
        value:SetText(string.format(fmt, snapped))
        if not updating then opts.set(snapped) end
    end)

    function slider:Refresh()
        updating = true
        local v = opts.get() or opts.min
        self:SetValue(v)
        value:SetText(string.format(fmt, v))
        updating = false
    end
    slider:Refresh()

    W.AttachTooltip(slider, opts.label, opts.tooltip)
    -- OptionsSliderTemplate hangs its label above the bar, so the row needs
    -- headroom that the slider's own height does not account for.
    self:Place(slider, 42, {
        indent = opts.indent,
        sameLine = opts.sameLine,
        yAdjust = -14,
        width = (opts.width or 160) + 50,
    })
    return self:Register(slider)
end

--- opts: { label, options, get, set, width, indent, sameLine }
function Panel:Dropdown(opts)
    if opts.label then
        self:Label(opts.label, {
            indent = opts.indent,
            sameLine = opts.sameLine,
            yAdjust = -6,
        })
        opts = setmetatable({ sameLine = true }, { __index = opts })
    end

    local dd = W.CreateDropdown(self.parent, opts.width or 160, opts.options, opts.get, opts.set)
    self:Place(dd, 26, {
        indent = opts.indent,
        sameLine = opts.sameLine,
        width = opts.width or 160,
    })
    return self:Register(dd)
end

--- opts: { label, width, height, onClick, indent, sameLine, tooltip }
function Panel:Button(opts)
    local btn = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
    btn:SetSize(opts.width or 150, opts.height or 24)
    btn:SetText(opts.label)
    btn:SetScript("OnClick", function(self) opts.onClick(self) end)
    W.AttachTooltip(btn, opts.label, opts.tooltip)

    self:Place(btn, (opts.height or 24) + 4, {
        indent = opts.indent,
        sameLine = opts.sameLine,
        width = opts.width or 150,
    })
    return btn
end

--- opts: { label, get, set, indent, sameLine } -- get returns r,g,b
function Panel:Color(opts)
    if opts.label then
        self:Label(opts.label, { indent = opts.indent, sameLine = opts.sameLine })
        opts = setmetatable({ sameLine = true }, { __index = opts })
    end

    local swatch = W.CreateColorSwatch(self.parent, opts.get, opts.set)
    self:Place(swatch, 22, { indent = opts.indent, sameLine = opts.sameLine, width = 18 })
    return self:Register(swatch)
end

--- opts: { label, get, set, width, numeric, onEnter, indent, sameLine }
function Panel:EditBox(opts)
    if opts.label then
        self:Label(opts.label, { indent = opts.indent, sameLine = opts.sameLine })
        opts = setmetatable({ sameLine = true }, { __index = opts })
    end

    local box = CreateFrame("EditBox", nil, self.parent, "InputBoxTemplate")
    box:SetSize(opts.width or 160, 22)
    box:SetAutoFocus(false)
    box:SetNumeric(opts.numeric and true or false)

    box:SetScript("OnEnterPressed", function(self)
        if opts.set then opts.set(self:GetText()) end
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self.Refresh then self:Refresh() end
    end)
    if opts.onTextChanged then
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then opts.onTextChanged(self:GetText()) end
        end)
    end

    function box:Refresh()
        if opts.get then self:SetText(opts.get() or "") end
    end
    box:Refresh()

    self:Place(box, 26, {
        indent = opts.indent,
        sameLine = opts.sameLine,
        width = opts.width or 160,
    })
    return self:Register(box)
end

return W
