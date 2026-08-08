-- ============================================================================
-- ThugUI: Target of Target page
--
-- Ports the "Target of Target" Blizzard subpanel. Enabling this turns off
-- Blizzard's own ToT via CVar; the module remembers the player's original CVar
-- value so unticking gives it back rather than guessing a default.
-- ============================================================================

ThugUI = ThugUI or {}

local Page = {}

local function Cfg()
    ThugUI_Config = ThugUI_Config or {}
    return ThugUI_Config
end

local function ToT()
    return ThugUI.TargetOfTarget
end

local function Call(method, ...)
    local tot = ToT()
    if tot and tot[method] then tot[method](tot, ...) end
end

function Page:Build(host, panel)
    panel:Header("Target of Target")
    panel:Note("Your target's target, drawn on the full-size target frame art.")

    panel:Section("General")

    panel:Checkbox{
        label = "Enable ThugUI target of target",
        tooltip = "Turns off Blizzard's target-of-target frame. Off by default — replacing "
            .. "a default frame should be a deliberate choice.",
        get = function() return Cfg().totEnabled end,
        set = function(v) Cfg().totEnabled = v; Call("ApplyAll") end,
    }
    panel:Checkbox{
        label = "Unlocked (show drag handle)",
        get = function() return Cfg().totUnlocked end,
        set = function(v) Cfg().totUnlocked = v; Call("SetUnlocked", v) end,
    }
    panel:Checkbox{
        label = "Hide Blizzard's target of target",
        get = function() return Cfg().totHideBlizzardToT end,
        set = function(v) Cfg().totHideBlizzardToT = v; Call("UpdateBlizzardToT") end,
    }

    panel:Section("Frame parts")

    local function Part(label, key)
        panel:Checkbox{
            label = label,
            get = function() return Cfg()[key] end,
            set = function(v) Cfg()[key] = v; Call("ApplySettings") end,
        }
    end

    Part("Health bar", "totShowHealthBar")
    Part("Power bar",  "totShowPowerBar")
    Part("Portrait",   "totShowPortrait")
    Part("Name",       "totShowName")
    Part("Reputation colouring", "totShowReputation")

    panel:Section("Appearance")

    panel:Dropdown{
        label = "Health bar colour:", width = 150,
        options = {
            { value = "blizzard", text = "Blizzard default" },
            { value = "class",    text = "Class colour" },
            { value = "reaction", text = "Reaction colour" },
        },
        get = function() return Cfg().totHealthColor or "blizzard" end,
        set = function(v) Cfg().totHealthColor = v; Call("ApplySettings") end,
    }
    panel:Slider{
        label = "Scale", min = 0.5, max = 2.0, step = 0.05, format = "%.2f",
        get = function() return Cfg().totScale or 1.0 end,
        set = function(v) Cfg().totScale = v; Call("ApplySettings") end,
    }

    panel:Gap(8)
    panel:Button{
        label = "Reset position",
        onClick = function()
            Cfg().totPoint = nil
            Call("RestorePosition")
            print("|cff00ff00ThugUI:|r Target of target position reset.")
        end,
    }
end

ThugUI.Window:RegisterPage{
    id = "targetoftarget",
    title = "Target of Target",
    order = 60,
    build = function(host, panel) Page:Build(host, panel) end,
}

return Page
