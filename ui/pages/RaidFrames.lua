-- ============================================================================
-- ThugUI: Raid Frames page
--
-- Ports the "Raid Frames" Blizzard subpanel. The oUF header is built once from
-- the layout values, so anything that changes its geometry needs a reload --
-- those settings are grouped and labelled as such rather than silently doing
-- nothing until the next login.
-- ============================================================================

ThugUI = ThugUI or {}

local Page = {}

local function Cfg()
    ThugUI_Config = ThugUI_Config or {}
    return ThugUI_Config
end

local function RF()
    return ThugUI.RaidFrames
end

local function Call(method, ...)
    local rf = RF()
    if rf and rf[method] then rf[method](rf, ...) end
end

function Page:Build(host, panel)
    panel:Header("Raid Frames")
    panel:Note("ThugUI's own party/raid frames, built on oUF. Their aura icons are owned "
        .. "outright and never get a tooltip wired to them, which is what makes them "
        .. "click-through.")

    panel:Section("General")

    panel:Checkbox{
        label = "Enable ThugUI raid frames",
        tooltip = "Replaces the Blizzard party/raid frames. Off by default — this should be "
            .. "a choice you make, not something an update does to you.",
        get = function() return Cfg().rfEnabled end,
        set = function(v) Cfg().rfEnabled = v; Call("ApplyAll") end,
    }
    panel:Checkbox{
        label = "Unlocked (show drag handle)",
        get = function() return Cfg().rfUnlocked end,
        set = function(v) Cfg().rfUnlocked = v; Call("SetUnlocked", v) end,
    }
    panel:Checkbox{
        label = "Hide the Blizzard raid frames",
        get = function() return Cfg().rfHideBlizzardRaidFrames end,
        set = function(v) Cfg().rfHideBlizzardRaidFrames = v; Call("ApplyAll") end,
    }

    panel:Section("Layout  |cff808080(needs /reload)|r")

    local function LayoutSlider(label, key, min, max, step)
        panel:Slider{
            label = label, min = min, max = max, step = step, format = "%d",
            get = function() return Cfg()[key] end,
            set = function(v) Cfg()[key] = v; Call("ApplyHeaderLayout"); Call("UpdateMoverGeometry") end,
        }
    end

    LayoutSlider("Frame width",     "rfWidth",         40, 200, 1)
    LayoutSlider("Frame height",    "rfHeight",        20, 100, 1)
    LayoutSlider("Spacing",         "rfSpacing",        0,  20, 1)
    LayoutSlider("Units per column","rfUnitsPerColumn", 1,  40, 1)
    LayoutSlider("Max columns",     "rfMaxColumns",     1,   8, 1)

    panel:Dropdown{
        label = "Group by:", width = 140,
        options = {
            { value = "GROUP", text = "Group" },
            { value = "ROLE",  text = "Role" },
            { value = "CLASS", text = "Class" },
            { value = "NONE",  text = "None" },
        },
        get = function() return Cfg().rfGroupBy or "GROUP" end,
        set = function(v) Cfg().rfGroupBy = v; Call("ApplyHeaderLayout") end,
    }

    panel:Section("Health")

    panel:Dropdown{
        label = "Health bar colour:", width = 150,
        options = {
            { value = "class",    text = "Class colour" },
            { value = "gradient", text = "Health gradient" },
            { value = "static",   text = "Static colour" },
        },
        get = function() return Cfg().rfHealthColor or "class" end,
        set = function(v) Cfg().rfHealthColor = v; Call("RefreshFrames") end,
    }
    panel:Color{
        label = "Static colour:",
        get = function()
            local c = Cfg().rfHealthStaticColor or {}
            return c.r, c.g, c.b
        end,
        set = function(r, g, b)
            Cfg().rfHealthStaticColor = { r = r, g = g, b = b }
            Call("RefreshFrames")
        end,
    }
    panel:Checkbox{
        label = "Show power bar",
        get = function() return Cfg().rfShowPowerBar end,
        set = function(v) Cfg().rfShowPowerBar = v; Call("RefreshFrames") end,
    }
    panel:Slider{
        label = "Power bar height", min = 1, max = 12, step = 1, format = "%d",
        get = function() return Cfg().rfPowerBarHeight end,
        set = function(v) Cfg().rfPowerBarHeight = v; Call("RefreshFrames") end,
    }

    panel:Section("Text")

    panel:Checkbox{
        label = "Show names",
        get = function() return Cfg().rfShowName end,
        set = function(v) Cfg().rfShowName = v; Call("RefreshFrames") end,
    }
    panel:Slider{
        label = "Name length", min = 1, max = 12, step = 1, format = "%d",
        get = function() return Cfg().rfNameLength end,
        set = function(v) Cfg().rfNameLength = v; Call("RefreshFrames") end,
    }

    panel:Section("Buffs")

    panel:Checkbox{
        label = "Show buffs",
        get = function() return Cfg().rfShowBuffs end,
        set = function(v) Cfg().rfShowBuffs = v; Call("RefreshFrames") end,
    }
    panel:Checkbox{
        label = "Only my buffs",
        get = function() return Cfg().rfBuffOnlyMine end,
        set = function(v) Cfg().rfBuffOnlyMine = v; Call("RefreshFrames") end,
    }
    panel:Slider{
        label = "Buff count", min = 0, max = 8, step = 1, format = "%d",
        get = function() return Cfg().rfBuffCount end,
        set = function(v) Cfg().rfBuffCount = v; Call("RefreshFrames") end,
    }
    panel:Slider{
        label = "Buff size", min = 8, max = 32, step = 1, format = "%d",
        get = function() return Cfg().rfBuffSize end,
        set = function(v) Cfg().rfBuffSize = v; Call("RefreshFrames") end,
    }

    panel:Section("Debuffs")

    panel:Checkbox{
        label = "Show debuffs",
        get = function() return Cfg().rfShowDebuffs end,
        set = function(v) Cfg().rfShowDebuffs = v; Call("RefreshFrames") end,
    }
    panel:Checkbox{
        label = "Only ones I can dispel",
        get = function() return Cfg().rfDebuffDispellableOnly end,
        set = function(v) Cfg().rfDebuffDispellableOnly = v; Call("RefreshFrames") end,
    }
    panel:Slider{
        label = "Debuff count", min = 0, max = 8, step = 1, format = "%d",
        get = function() return Cfg().rfDebuffCount end,
        set = function(v) Cfg().rfDebuffCount = v; Call("RefreshFrames") end,
    }
    panel:Slider{
        label = "Debuff size", min = 8, max = 32, step = 1, format = "%d",
        get = function() return Cfg().rfDebuffSize end,
        set = function(v) Cfg().rfDebuffSize = v; Call("RefreshFrames") end,
    }

    panel:Section("Behaviour")

    panel:Checkbox{
        label = "Show while in a party",
        get = function() return Cfg().rfShowParty end,
        set = function(v) Cfg().rfShowParty = v; Call("ApplyAll") end,
    }
    panel:Checkbox{
        label = "Show while solo",
        get = function() return Cfg().rfShowSolo end,
        set = function(v) Cfg().rfShowSolo = v; Call("ApplyAll") end,
    }
    panel:Checkbox{
        label = "Include myself in party frames",
        get = function() return Cfg().rfShowPlayerInParty end,
        set = function(v) Cfg().rfShowPlayerInParty = v; Call("ApplyHeaderLayout") end,
    }
    panel:Slider{
        label = "Out-of-range alpha", min = 0.1, max = 1.0, step = 0.05, format = "%.2f",
        get = function() return Cfg().rfRangeAlpha end,
        set = function(v) Cfg().rfRangeAlpha = v; Call("RefreshFrames") end,
    }
end

ThugUI.Window:RegisterPage{
    id = "raidframes",
    title = "Raid Frames",
    order = 50,
    build = function(host, panel) Page:Build(host, panel) end,
}

return Page
