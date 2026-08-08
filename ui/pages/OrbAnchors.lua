-- ============================================================================
-- ThugUI: Acorn Orbs page
--
-- The acorn orbs are the addon's element-hiding handles: a floating acorn per
-- managed UI element that toggles it and marks where it lives. Config is in
-- ThugUIDB.OrbAnchors (the newer nested store), not ThugUI_Config.
-- ============================================================================

ThugUI = ThugUI or {}

local Page = {}

local function DB()
    ThugUIDB = ThugUIDB or {}
    ThugUIDB.OrbAnchors = ThugUIDB.OrbAnchors or {}
    local db = ThugUIDB.OrbAnchors
    db.chatOrb = db.chatOrb or {}
    db.objectivesOrb = db.objectivesOrb or {}
    return db, db.chatOrb, db.objectivesOrb
end

local function Module()
    return ThugUI.modules and ThugUI.modules.OrbAnchors
end

local function ApplyAnchors()
    local module = Module()
    if module and module.UpdateAnchors then module:UpdateAnchors() end
end

local CHANNELS = {
    { key = "SAY",     label = "Say" },
    { key = "YELL",    label = "Yell" },
    { key = "EMOTE",   label = "Emote" },
    { key = "WHISPER", label = "Whisper" },
    { key = "PARTY",   label = "Party" },
    { key = "RAID",    label = "Raid" },
    { key = "GUILD",   label = "Guild" },
    { key = "OFFICER", label = "Officer" },
    { key = "CHANNEL", label = "Channels (Trade/General)" },
    { key = "SYSTEM",  label = "System" },
}

function Page:Build(host, panel)
    local db, chat, obj = DB()

    panel:Header("Acorn Orbs")
    panel:Note("Floating acorns that stand in for hidden UI elements. Click one to toggle "
        .. "its element; shift-drag to move it.")

    panel:Section("General")

    panel:Checkbox{
        label = "Enable orb anchors",
        get = function() return DB().enabled end,
        set = function(v) local d = DB(); d.enabled = v; ApplyAnchors() end,
    }
    panel:Checkbox{
        label = "Lock orb positions",
        tooltip = "Locked, a plain left-click always toggles and shift-drag moves. "
            .. "Unlocked, a few pixels of movement get eaten as a drag and the click never lands.",
        get = function() return DB().locked end,
        set = function(v) DB().locked = v end,
    }

    -- Chat orb ----------------------------------------------------------
    panel:Section("Chat orb")

    panel:Checkbox{
        label = "Enable chat orb",
        get = function() local _, c = DB(); return c.enabled end,
        set = function(v) local _, c = DB(); c.enabled = v end,
    }

    panel:Dropdown{
        label = "Chat mode:",
        width = 170,
        options = {
            { value = 1, text = "Normal chat" },
            { value = 2, text = "Stream text box" },
            { value = 3, text = "Hidden" },
        },
        get = function() local _, c = DB(); return c.mode or 1 end,
        set = function(v)
            local _, c = DB()
            c.mode = v
            local module = Module()
            if module and module.SetChatMode then module:SetChatMode(v) end
        end,
    }

    panel:Slider{
        label = "Stream font size", min = 8, max = 28, step = 1, format = "%d",
        get = function() local _, c = DB(); return c.fontSize or 14 end,
        set = function(v)
            local _, c = DB()
            c.fontSize = v
            local messageFrame = _G["ThugUI_StreamChatMessageFrame"]
            if messageFrame then
                messageFrame:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", v, c.fontOutline or "OUTLINE")
            end
        end,
    }

    panel:Checkbox{
        label = "Show timestamps",
        get = function() local _, c = DB(); return c.showTimestamp end,
        set = function(v) local _, c = DB(); c.showTimestamp = v end,
    }

    panel:Label("Stream box channels:")
    panel:Note("Anything unticked is filtered out of the stream box. Trade/General is off "
        .. "by default because a city's Trade chat buries everything else.")

    -- Two columns of channel toggles: ten stacked singly would push the rest of
    -- the page below the fold for no reason.
    for i = 1, #CHANNELS, 2 do
        for offset = 0, 1 do
            local channel = CHANNELS[i + offset]
            if channel then
                panel:Checkbox{
                    label = channel.label,
                    indent = 12,
                    sameLine = offset == 1,
                    get = function()
                        local _, c = DB()
                        return c.channels and c.channels[channel.key] ~= false
                    end,
                    set = function(v)
                        local _, c = DB()
                        c.channels = c.channels or {}
                        c.channels[channel.key] = v
                    end,
                }
            end
        end
    end

    -- Objectives orb ----------------------------------------------------
    panel:Section("Objectives orb")

    panel:Checkbox{
        label = "Enable objectives orb",
        get = function() local _, _, o = DB(); return o.enabled end,
        set = function(v) local _, _, o = DB(); o.enabled = v end,
    }

    panel:Checkbox{
        label = "Objective tracker visible",
        tooltip = "Hiding reparents the tracker to a never-shown frame. Blizzard re-Show()s "
            .. "the tracker constantly, so plain Hide() and visibility state drivers both "
            .. "lose the argument; a child of a hidden parent simply never draws.",
        get = function() local _, _, o = DB(); return o.visible end,
        set = function(v)
            local module = Module()
            if module and module.SetObjectivesVisibility then
                module:SetObjectivesVisibility(v)
            else
                local _, _, o = DB()
                o.visible = v
            end
        end,
    }

    -- Appearance --------------------------------------------------------
    panel:Section("Appearance")

    panel:Slider{
        label = "Chat orb size", min = 20, max = 64, step = 2, format = "%d",
        get = function() local _, c = DB(); return c.size or 36 end,
        set = function(v) local _, c = DB(); c.size = v; ApplyAnchors() end,
    }
    panel:Color{
        label = "Chat orb colour:",
        get = function()
            local _, c = DB()
            local col = c.color or {}
            return col[1], col[2], col[3]
        end,
        set = function(r, g, b)
            local _, c = DB()
            c.color = { r, g, b, (c.color and c.color[4]) or 0.9 }
            ApplyAnchors()
        end,
    }

    panel:Slider{
        label = "Objectives orb size", min = 20, max = 64, step = 2, format = "%d",
        get = function() local _, _, o = DB(); return o.size or 36 end,
        set = function(v) local _, _, o = DB(); o.size = v; ApplyAnchors() end,
    }
    panel:Color{
        label = "Objectives orb colour:",
        get = function()
            local _, _, o = DB()
            local col = o.color or {}
            return col[1], col[2], col[3]
        end,
        set = function(r, g, b)
            local _, _, o = DB()
            o.color = { r, g, b, (o.color and o.color[4]) or 0.9 }
            ApplyAnchors()
        end,
    }

    panel:Gap(8)
    panel:Button{
        label = "Reset orb positions",
        onClick = function()
            local _, c, o = DB()
            c.point, c.x, c.y = "BOTTOMLEFT", 25, 220
            o.point, o.x, o.y = "TOPRIGHT", -260, -220
            ApplyAnchors()
            print("|cff00ff00ThugUI:|r Orb positions reset.")
        end,
    }
end

ThugUI.Window:RegisterPage{
    id = "orbanchors",
    title = "Acorn Orbs",
    order = 20,
    build = function(host, panel) Page:Build(host, panel) end,
}

return Page
