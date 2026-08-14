-- ============================================================================
-- ThugUI: Cursor Rings page
--
-- Ports the "Cursor Rings" Blizzard subpanel. Config lives in ThugUI_Config
-- and every setter calls back into ThugUI.EssentialRings, which owns the
-- frames -- this page holds no ring state of its own.
--
-- TWO COLUMNS
--
-- This used to be ~40 controls stacked in one left-aligned column with the
-- right half of the window empty -- and the player went months without
-- noticing the resource ring had its own "Show:" visibility dropdown, sitting
-- directly above a checkbox they did find. Task 17 rebuilds it as two
-- columns, each its own W.NewPanel with an independent layout cursor (the
-- pattern CooldownViewer.lua uses for its picker/grid/inspector split).
--
-- Resource ring and Combo pips are deliberately paired side by side: both
-- are show-toggle + Show: dropdown + colour + sliders, so the two "Show:"
-- dropdowns land in matching positions and the eye can pair them. SyncColumns
-- below exists only to keep that particular pairing aligned when one side has
-- more rows than the other -- it is not needed for correctness anywhere else.
-- ============================================================================

ThugUI = ThugUI or {}

local Page = {}

-- Resolved on first build rather than at file scope, matching ui/Window.lua.
-- This page is the first to need Widgets at *build* time rather than only
-- through the panel it is handed, and a file-scope grab would bake in a load
-- order assumption for no gain.
local W

local function Cfg()
    ThugUI_Config = ThugUI_Config or {}
    return ThugUI_Config
end

local function ER()
    return ThugUI.EssentialRings
end

local function Call(method)
    local er = ER()
    if er and er[method] then er[method](er) end
end

local COLOR_MODES = {
    { value = "default", text = "Default (white)" },
    { value = "class",   text = "Class colour" },
    { value = "custom",  text = "Custom colour" },
}

local FILL_MODES = {
    { value = "fill",  text = "Fill" },
    { value = "drain", text = "Drain" },
}

-- Shared by the resource ring's and the combo pips' "Show:" dropdowns, which
-- carried this exact table twice. Same idea as COLOR_MODES/FILL_MODES above.
local VISIBILITY_MODES = {
    { value = "always", text = "Always" },
    { value = "combat", text = "Only in combat" },
    { value = "rings",  text = "With the cursor rings" },
}

local DRAIN_DIRECTIONS = {
    { value = "clockwise",        text = "Clockwise" },
    { value = "counterclockwise", text = "Counter-clockwise" },
}

--- Colour-mode dropdown plus its swatch. The swatch stays live regardless of
--- mode; disabling it just to re-enable it is more fiddle than it is worth.
local function ColorRow(panel, label, modeKey, colorKey, apply)
    panel:Dropdown{
        label = label,
        width = 150,
        options = COLOR_MODES,
        get = function() return Cfg()[modeKey] or "default" end,
        set = function(v) Cfg()[modeKey] = v; Call(apply) end,
    }
    panel:Color{
        get = function()
            local c = Cfg()[colorKey]
            if not c then return 1, 1, 1 end
            return c.r, c.g, c.b
        end,
        set = function(r, g, b)
            Cfg()[colorKey] = { r = r, g = g, b = b }
            Call(apply)
        end,
        sameLine = true,
    }
end

--- Pulls every given panel's layout cursor down to whichever is currently
--- lowest. Without this, a section with more rows than its paired column
--- (e.g. "Ring slots" has 5 rows to "Colours" 4) would leave the next pair of
--- section headers -- "Resource ring" / "Combo pips", the pairing this whole
--- layout exists for -- at two different heights.
local function SyncColumns(...)
    local panels = { ... }
    local lowest = panels[1].cursorY
    for i = 2, #panels do
        if panels[i].cursorY < lowest then lowest = panels[i].cursorY end
    end
    for _, p in ipairs(panels) do
        p.cursorY, p.rowTopY = lowest, lowest
    end
end

function Page:Build(host, panel)
    W = W or ThugUI.Widgets
    local er = ER()

    panel:Header("Cursor Rings")
    panel:Note("GCD and cast tracking drawn around the mouse pointer.")

    local LEFT_X, RIGHT_X, COL_WIDTH = 16, 390, 340
    -- Both columns start right where the header/note left off, so widening
    -- either of those does not require re-tuning a hardcoded y.
    local colY = -panel.cursorY

    local left  = W.NewPanel(host, { x = LEFT_X,  y = colY, width = COL_WIDTH })
    local right = W.NewPanel(host, { x = RIGHT_X, y = colY, width = COL_WIDTH })
    self.panels = { left, right }

    -- ---- Ring slots / Colours ---------------------------------------------

    left:Section("Rings")

    local ringOptions = {}
    for _, name in ipairs((er and er.ringOptions) or {}) do
        table.insert(ringOptions, { value = name, text = name })
    end
    local reticleOptions = {}
    for _, name in ipairs((er and er.reticleOptions) or {}) do
        table.insert(reticleOptions, { value = name, text = name })
    end

    left:Dropdown{
        label = "Reticle:", width = 150, options = reticleOptions,
        get = function() return Cfg().reticle end,
        set = function(v) Cfg().reticle = v; Call("ApplySettings") end,
    }
    left:Slider{
        label = "Reticle size", min = 0.5, max = 3.0, step = 0.1, format = "%.1f",
        get = function() return Cfg().reticleScale or 1.0 end,
        set = function(v) Cfg().reticleScale = v; Call("UpdateReticle") end,
    }
    left:Dropdown{
        label = "Inner ring (small):", width = 150, options = ringOptions,
        get = function() return Cfg().innerRing end,
        set = function(v) Cfg().innerRing = v; Call("ApplySettings") end,
    }
    left:Dropdown{
        label = "Main ring (medium):", width = 150, options = ringOptions,
        get = function() return Cfg().mainRing end,
        set = function(v) Cfg().mainRing = v; Call("ApplySettings") end,
    }
    left:Dropdown{
        label = "Outer ring (large):", width = 150, options = ringOptions,
        get = function() return Cfg().outerRing end,
        set = function(v) Cfg().outerRing = v; Call("ApplySettings") end,
    }

    right:Section("Colours")

    ColorRow(right, "Reticle:",   "reticleColorMode",  "reticleCustomColor",  "UpdateReticle")
    ColorRow(right, "Main ring:", "mainRingColorMode", "mainRingCustomColor", "UpdateRingColors")
    ColorRow(right, "GCD:",       "gcdColorMode",      "gcdCustomColor",      "UpdateRingColors")
    ColorRow(right, "Cast:",      "castColorMode",     "castCustomColor",     "UpdateRingColors")

    SyncColumns(left, right, panel)

    -- ---- Animation: one header spanning the page, two columns beneath it --

    panel.cursorY, panel.rowTopY = left.cursorY, left.cursorY
    panel:Section("Animation")
    left.cursorY,  left.rowTopY  = panel.cursorY, panel.cursorY
    right.cursorY, right.rowTopY = panel.cursorY, panel.cursorY

    left:Dropdown{
        label = "GCD sweep:", width = 130, options = FILL_MODES,
        get = function() return Cfg().gcdFillDrain or "fill" end,
        set = function(v) Cfg().gcdFillDrain = v; Call("ResetCooldownFrames") end,
    }
    left:Slider{
        label = "GCD start (o'clock)", min = 1, max = 12, step = 1, format = "%d", width = 130,
        get = function() return Cfg().gcdRotation or 12 end,
        set = function(v) Cfg().gcdRotation = v; Call("ResetCooldownFrames") end,
    }

    right:Dropdown{
        label = "Cast sweep:", width = 130, options = FILL_MODES,
        get = function() return Cfg().castFillDrain or "fill" end,
        set = function(v) Cfg().castFillDrain = v; Call("ResetCooldownFrames") end,
    }
    right:Slider{
        label = "Cast start (o'clock)", min = 1, max = 12, step = 1, format = "%d", width = 130,
        get = function() return Cfg().castRotation or 12 end,
        set = function(v) Cfg().castRotation = v; Call("ResetCooldownFrames") end,
    }

    SyncColumns(left, right)

    -- ---- Resource ring / Combo pips ----------------------------------------

    left:Section("Resource ring")

    left:Note("A radial resource meter in the cast ring's band, with the cast sweep drawn "
        .. "over the top. The resource follows your form on its own — rage in Bear, energy "
        .. "in Cat, Astral Power in Moonkin — so there is nothing to configure per spec.")

    left:Checkbox{
        label = "Show resource ring",
        get = function() return Cfg().showResourceRing end,
        set = function(v)
            Cfg().showResourceRing = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:Update() end
        end,
    }

    left:Dropdown{
        label = "Show:", width = 170,
        options = VISIBILITY_MODES,
        get = function() return Cfg().resourceRingVisibility or "always" end,
        set = function(v)
            Cfg().resourceRingVisibility = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:Update() end
        end,
    }

    left:Dropdown{
        label = "Colour:", width = 170,
        options = {
            { value = "power",  text = "Match the resource" },
            { value = "class",  text = "Class colour" },
            { value = "custom", text = "Custom colour" },
        },
        get = function() return Cfg().resourceRingColorMode or "power" end,
        set = function(v)
            Cfg().resourceRingColorMode = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:UpdateColor() end
        end,
    }
    left:Color{
        get = function()
            local c = Cfg().resourceRingCustomColor
            if not c then return 1, 1, 1 end
            return c.r, c.g, c.b
        end,
        set = function(r, g, b)
            Cfg().resourceRingCustomColor = { r = r, g = g, b = b }
            if ThugUI.ResourceRing then ThugUI.ResourceRing:UpdateColor() end
        end,
        sameLine = true,
    }

    left:Slider{
        label = "Resource ring opacity", min = 0.1, max = 1.0, step = 0.05, format = "%.2f",
        tooltip = "Kept below full by default so the cast sweep stays legible over it.",
        get = function() return Cfg().resourceRingAlpha or 0.55 end,
        set = function(v)
            Cfg().resourceRingAlpha = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:UpdateColor() end
        end,
    }

    -- The "Radial bar" checkbox that used to sit here is gone. It chose between
    -- two implementations and there is only one left -- the Cooldown sweep was
    -- removed on 2026-08-13 because it never tracked at all. DECISIONS.md §27.

    left:Dropdown{
        label = "Drain:", width = 170,
        tooltip = "Which way round the ring empties as you spend the resource.",
        options = DRAIN_DIRECTIONS,
        get = function() return Cfg().resourceRingDrainDirection or "clockwise" end,
        set = function(v)
            Cfg().resourceRingDrainDirection = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:Update() end
        end,
    }
    left:Slider{
        label = "Resource start (o'clock)", min = 1, max = 12, step = 1, format = "%d", width = 130,
        tooltip = "Matches the GCD and cast rings. This ring used to borrow the "
            .. "cast ring's setting, which left it starting at 6 o'clock.",
        get = function() return Cfg().resourceRingRotation or 12 end,
        set = function(v)
            Cfg().resourceRingRotation = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:ApplyStartAngle() end
        end,
    }

    right:Section("Radial pips")

    right:Note("Your class's secondary resource — Combo Points, Holy Power, Soul Shards, "
        .. "Chi, Arcane Charges, Essence — as dots around the ring. Classes without one "
        .. "show nothing, and the count follows talents on its own.")

    right:Checkbox{
        label = "Show radial pips",
        get = function() return Cfg().showComboPips end,
        set = function(v)
            Cfg().showComboPips = v
            if ThugUI.ComboPips then ThugUI.ComboPips:Refresh() end
        end,
    }

    right:Dropdown{
        label = "Show:", width = 170,
        options = VISIBILITY_MODES,
        get = function() return Cfg().comboPipVisibility or "combat" end,
        set = function(v)
            Cfg().comboPipVisibility = v
            if ThugUI.ComboPips then ThugUI.ComboPips:Refresh() end
        end,
    }

    right:Dropdown{
        label = "Colour:", width = 170,
        options = {
            { value = "power",  text = "Match the resource" },
            { value = "class",  text = "Class colour" },
            { value = "custom", text = "Custom colour" },
        },
        get = function() return Cfg().comboPipColorMode or "power" end,
        set = function(v)
            Cfg().comboPipColorMode = v
            if ThugUI.ComboPips then ThugUI.ComboPips:Refresh() end
        end,
    }
    right:Color{
        get = function()
            local c = Cfg().comboPipCustomColor
            if not c then return 1, 1, 1 end
            return c.r, c.g, c.b
        end,
        set = function(r, g, b)
            Cfg().comboPipCustomColor = { r = r, g = g, b = b }
            if ThugUI.ComboPips then ThugUI.ComboPips:Refresh() end
        end,
        sameLine = true,
    }

    right:Slider{
        label = "Pip size", min = 4, max = 20, step = 1, format = "%d",
        get = function() return Cfg().comboPipSize or 9 end,
        set = function(v)
            Cfg().comboPipSize = v
            if ThugUI.ComboPips then ThugUI.ComboPips:Refresh() end
        end,
    }

    right:Slider{
        label = "Distance from the ring", min = -80, max = 40, step = 1, format = "%d",
        tooltip = "Negative values pull the pips inside the band, towards the cursor. "
            .. "Far enough in draws a tight ring near the centre rather than one that "
            .. "hugs the cast sweep.",
        get = function() return Cfg().comboPipOffset or 7 end,
        set = function(v)
            Cfg().comboPipOffset = v
            if ThugUI.ComboPips then ThugUI.ComboPips:Refresh() end
        end,
    }

    right:Slider{
        label = "Unspent pip opacity", min = 0, max = 1, step = 0.05, format = "%.2f",
        tooltip = "How visible a pip is before the point is earned.",
        get = function() return Cfg().comboPipDimAlpha or 0.25 end,
        set = function(v)
            Cfg().comboPipDimAlpha = v
            if ThugUI.ComboPips then ThugUI.ComboPips:Refresh() end
        end,
    }

    SyncColumns(left, right)

    -- ---- Visibility / Test -------------------------------------------------

    left:Section("Visibility")

    left:Checkbox{
        label = "Only show in combat",
        get = function() return Cfg().showOnlyInCombat end,
        set = function(v) Cfg().showOnlyInCombat = v; Call("ApplySettings") end,
    }
    left:Checkbox{
        label = "Hide the game cursor while rings are shown",
        get = function() return Cfg().hideGameCursor end,
        set = function(v) Cfg().hideGameCursor = v; Call("UpdateVisibility") end,
    }
    left:Slider{
        label = "Transparency", min = 0.1, max = 1.0, step = 0.05, format = "%.2f",
        get = function() return Cfg().transparency or 1.0 end,
        set = function(v) Cfg().transparency = v; Call("ApplySettings") end,
    }
    left:Slider{
        label = "Scale", min = 0.5, max = 4.0, step = 0.1, format = "%.1f",
        get = function() return Cfg().scale or 1.0 end,
        set = function(v) Cfg().scale = v; Call("ApplySettings") end,
    }

    right:Section("Test")

    right:Checkbox{
        label = "Test mode",
        tooltip = "Pretend to be in combat so combat-only elements show while you tune them.",
        get = function() return Cfg().testMode end,
        set = function(v) Cfg().testMode = v; Call("UpdateVisibility") end,
    }
end

--- Window:SelectPage already calls def.panel:Refresh() for the primary panel
--- (the header/note -- it holds no widgets, so that call is a no-op). left
--- and right are separate panels W.NewPanel does not know about, so they need
--- their own refresh pass, the same way CooldownViewer.lua's self.panels does.
function Page:Refresh()
    for _, p in ipairs(self.panels or {}) do
        p:Refresh()
    end
end

ThugUI.Window:RegisterPage{
    id = "cursorrings",
    title = "Cursor Rings",
    order = 40,
    build = function(host, panel) Page:Build(host, panel) end,
    refresh = function() Page:Refresh() end,
}

return Page
