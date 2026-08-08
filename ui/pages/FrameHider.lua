-- ============================================================================
-- ThugUI: Frame Hider page
--
-- Hiding is applied through visibility state drivers, which do not take effect
-- until a reload -- and cannot be undone in-session at all, because the module
-- only ever registers drivers, it never unregisters them. The page says so
-- rather than pretending the checkboxes are live.
-- ============================================================================

ThugUI = ThugUI or {}

local Page = {}

local function Cfg()
    ThugUI_Config = ThugUI_Config or {}
    return ThugUI_Config
end

local function Hider()
    return ThugUI.FrameHider
end

function Page:Build(host, panel)
    panel:Header("Frame Hider")
    panel:Note("Hides default UI elements you never look at. Changes here take effect on "
        .. "the next |cffffd100/reload|r — the hiding runs through secure visibility state "
        .. "drivers, which cannot be lifted mid-session without tainting the frame.")

    panel:Section("Hide")

    panel:Checkbox{
        label = "Stance bar",
        get = function() return Cfg().hideStanceBar end,
        set = function(v)
            Cfg().hideStanceBar = v
            if v then local h = Hider(); if h then h:HideStanceBar() end end
        end,
    }
    panel:Checkbox{
        label = "Bag buttons",
        tooltip = "Backpack, reagent bag and the bag-bar expand toggle.",
        get = function() return Cfg().hideBagButtons end,
        set = function(v)
            Cfg().hideBagButtons = v
            if v then local h = Hider(); if h then h:HideBagButtons() end end
        end,
    }
    panel:Checkbox{
        label = "Player frame",
        tooltip = "Portrait, health and power. PlayerFrame is a secure unit button, so this "
            .. "unregisters its events and drives visibility rather than overriding Show().",
        get = function() return Cfg().hideCharacterFrame end,
        set = function(v)
            Cfg().hideCharacterFrame = v
            if v then local h = Hider(); if h then h:HideCharacterFrame() end end
        end,
    }

    panel:Note("The objective tracker is not here — it belongs to the acorn orb that toggles "
        .. "it. See the Acorn Orbs page.", { indent = 4 })

    panel:Section("Move")

    panel:Checkbox{
        label = "Make the Prey Crystal draggable",
        tooltip = "UIWidgetPowerBarContainerFrame. Its position is remembered and reapplied "
            .. "whenever Blizzard's layout tries to move it back.",
        get = function() return Cfg().movePreyCrystal end,
        set = function(v)
            Cfg().movePreyCrystal = v
            if v then local h = Hider(); if h then h:MakePreyCrystalMovable() end end
        end,
    }

    panel:Button{
        label = "Forget Prey Crystal position",
        width = 220,
        onClick = function()
            Cfg().preyCrystalPoint = nil
            print("|cff00ff00ThugUI:|r Prey Crystal position cleared — /reload to see it back in place.")
        end,
    }

    panel:Section("Diagnostics")

    panel:Checkbox{
        label = "Debug mode",
        tooltip = "Aura logging and init chatter into ThugUI_DebugLog. Also /thugdebug.",
        get = function() return Cfg().debugMode end,
        set = function(v)
            Cfg().debugMode = v
            local ER = ThugUI.EssentialRings
            if ER and ER.SetDebugMode then ER:SetDebugMode(v) end
        end,
    }
end

ThugUI.Window:RegisterPage{
    id = "framehider",
    title = "Frame Hider",
    order = 30,
    build = function(host, panel) Page:Build(host, panel) end,
}

return Page
