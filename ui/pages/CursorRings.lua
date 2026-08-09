-- ============================================================================
-- ThugUI: Cursor Rings page
--
-- Ports the "Cursor Rings" Blizzard subpanel. Config lives in ThugUI_Config
-- and every setter calls back into ThugUI.EssentialRings, which owns the
-- frames -- this page holds no ring state of its own.
-- ============================================================================

ThugUI = ThugUI or {}

local Page = {}

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

function Page:Build(host, panel)
    local er = ER()

    panel:Header("Cursor Rings")
    panel:Note("GCD and cast tracking drawn around the mouse pointer.")

    panel:Section("Ring slots")

    local ringOptions = {}
    for _, name in ipairs((er and er.ringOptions) or {}) do
        table.insert(ringOptions, { value = name, text = name })
    end
    local reticleOptions = {}
    for _, name in ipairs((er and er.reticleOptions) or {}) do
        table.insert(reticleOptions, { value = name, text = name })
    end

    panel:Dropdown{
        label = "Reticle:", width = 150, options = reticleOptions,
        get = function() return Cfg().reticle end,
        set = function(v) Cfg().reticle = v; Call("ApplySettings") end,
    }
    panel:Slider{
        label = "Reticle size", min = 0.5, max = 3.0, step = 0.1, format = "%.1f",
        get = function() return Cfg().reticleScale or 1.0 end,
        set = function(v) Cfg().reticleScale = v; Call("UpdateReticle") end,
    }
    panel:Dropdown{
        label = "Inner ring (small):", width = 150, options = ringOptions,
        get = function() return Cfg().innerRing end,
        set = function(v) Cfg().innerRing = v; Call("ApplySettings") end,
    }
    panel:Dropdown{
        label = "Main ring (medium):", width = 150, options = ringOptions,
        get = function() return Cfg().mainRing end,
        set = function(v) Cfg().mainRing = v; Call("ApplySettings") end,
    }
    panel:Dropdown{
        label = "Outer ring (large):", width = 150, options = ringOptions,
        get = function() return Cfg().outerRing end,
        set = function(v) Cfg().outerRing = v; Call("ApplySettings") end,
    }

    panel:Section("Colours")

    ColorRow(panel, "Reticle:",   "reticleColorMode",  "reticleCustomColor",  "UpdateReticle")
    ColorRow(panel, "Main ring:", "mainRingColorMode", "mainRingCustomColor", "UpdateRingColors")
    ColorRow(panel, "GCD:",       "gcdColorMode",      "gcdCustomColor",      "UpdateRingColors")
    ColorRow(panel, "Cast:",      "castColorMode",     "castCustomColor",     "UpdateRingColors")

    panel:Section("Animation")

    panel:Dropdown{
        label = "GCD sweep:", width = 130, options = FILL_MODES,
        get = function() return Cfg().gcdFillDrain or "fill" end,
        set = function(v) Cfg().gcdFillDrain = v; Call("ResetCooldownFrames") end,
    }
    panel:Slider{
        label = "GCD start (o'clock)", min = 1, max = 12, step = 1, format = "%d", width = 130,
        get = function() return Cfg().gcdRotation or 12 end,
        set = function(v) Cfg().gcdRotation = v; Call("ResetCooldownFrames") end,
    }
    panel:Dropdown{
        label = "Cast sweep:", width = 130, options = FILL_MODES,
        get = function() return Cfg().castFillDrain or "fill" end,
        set = function(v) Cfg().castFillDrain = v; Call("ResetCooldownFrames") end,
    }
    panel:Slider{
        label = "Cast start (o'clock)", min = 1, max = 12, step = 1, format = "%d", width = 130,
        get = function() return Cfg().castRotation or 12 end,
        set = function(v) Cfg().castRotation = v; Call("ResetCooldownFrames") end,
    }

    panel:Section("Resource ring")

    panel:Note("A radial resource meter in the cast ring's band, with the cast sweep drawn "
        .. "over the top. The resource follows your form on its own — rage in Bear, energy "
        .. "in Cat, Astral Power in Moonkin — so there is nothing to configure per spec.")

    panel:Checkbox{
        label = "Show resource ring",
        get = function() return Cfg().showResourceRing end,
        set = function(v)
            Cfg().showResourceRing = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:Update() end
        end,
    }

    panel:Dropdown{
        label = "Show:", width = 170,
        options = {
            { value = "always", text = "Always" },
            { value = "combat", text = "Only in combat" },
            { value = "rings",  text = "With the cursor rings" },
        },
        get = function() return Cfg().resourceRingVisibility or "always" end,
        set = function(v)
            Cfg().resourceRingVisibility = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:Update() end
        end,
    }

    panel:Dropdown{
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
    panel:Color{
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

    panel:Slider{
        label = "Resource ring opacity", min = 0.1, max = 1.0, step = 0.05, format = "%.2f",
        tooltip = "Kept below full by default so the cast sweep stays legible over it.",
        get = function() return Cfg().resourceRingAlpha or 0.55 end,
        set = function(v)
            Cfg().resourceRingAlpha = v
            if ThugUI.ResourceRing then ThugUI.ResourceRing:UpdateColor() end
        end,
    }

    panel:Section("Visibility")

    panel:Checkbox{
        label = "Only show in combat",
        get = function() return Cfg().showOnlyInCombat end,
        set = function(v) Cfg().showOnlyInCombat = v; Call("ApplySettings") end,
    }
    panel:Checkbox{
        label = "Hide the game cursor while rings are shown",
        get = function() return Cfg().hideGameCursor end,
        set = function(v) Cfg().hideGameCursor = v; Call("UpdateVisibility") end,
    }
    panel:Slider{
        label = "Transparency", min = 0.1, max = 1.0, step = 0.05, format = "%.2f",
        get = function() return Cfg().transparency or 1.0 end,
        set = function(v) Cfg().transparency = v; Call("ApplySettings") end,
    }
    panel:Slider{
        label = "Scale", min = 0.5, max = 4.0, step = 0.1, format = "%.1f",
        get = function() return Cfg().scale or 1.0 end,
        set = function(v) Cfg().scale = v; Call("ApplySettings") end,
    }

    panel:Section("Test")

    panel:Checkbox{
        label = "Test mode",
        tooltip = "Pretend to be in combat so combat-only elements show while you tune them.",
        get = function() return Cfg().testMode end,
        set = function(v) Cfg().testMode = v; Call("UpdateVisibility") end,
    }
end

ThugUI.Window:RegisterPage{
    id = "cursorrings",
    title = "Cursor Rings",
    order = 40,
    build = function(host, panel) Page:Build(host, panel) end,
}

return Page
