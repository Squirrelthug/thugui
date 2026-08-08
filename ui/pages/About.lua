-- ============================================================================
-- ThugUI: About page
-- ============================================================================

ThugUI = ThugUI or {}

local Page = {}

function Page:Build(host, panel)
    panel:Header("ThugUI")
    panel:Note("A modular UI suite. Version " .. (ThugUI.version or "1.0.0") .. ", by Thug.")

    panel:Section("Pages")

    local features = {
        { "Cooldown Viewer", "Per-spec grids of must-press cooldowns that ride your cursor." },
        { "Acorn Orbs",      "Floating acorns standing in for hidden UI elements." },
        { "Frame Hider",     "Turn off default elements you never look at." },
        { "Cursor Rings",    "GCD and cast tracking drawn around the pointer." },
        { "Raid Frames",     "oUF party/raid frames with click-through auras." },
        { "Target of Target","Your target's target on the full-size target art." },
    }

    for _, feature in ipairs(features) do
        panel:Label("|cffffffff" .. feature[1] .. "|r")
        panel:Note(feature[2], { indent = 12 })
    end

    panel:Section("Commands")

    local commands = {
        { "/thugui", "Open this window (also /thug, /tui)." },
        { "/thugcv", "Jump to the Cooldown Viewer page." },
        { "/thugcv legacy", "Switch between the grid engine and the old ECV/BCV/GCV bars." },
        { "/thugcv rebuild", "Rebuild the cooldown viewer without a reload." },
        { "/thugspell <name>", "Probe a spell's ID and texture into ThugUI_BCVDump." },
        { "/thugdebug", "Toggle debug logging." },
    }

    for _, command in ipairs(commands) do
        panel:Label("|cff00ffcc" .. command[1] .. "|r")
        panel:Note(command[2], { indent = 12 })
    end

    panel:Section("Fallback")

    panel:Note("Every setting here also still exists in its original Blizzard options panel "
        .. "under Interface > AddOns > ThugUI. Those panels are deliberately left registered "
        .. "as a safety net while this window settles in, which is why ThugUI currently "
        .. "appears twice in the addon options list.")

    panel:Note("If the new cooldown viewer misbehaves, |cffffd100/thugcv legacy|r brings back "
        .. "the original three druid bars exactly as they were — their settings were never "
        .. "removed.")

    panel:Section("Credits")

    panel:Note("oUF (MIT) by haste and contributors — vendored in libs/oUF.\n"
        .. "Acorn artwork is CC0 from Wikimedia Commons.")
end

ThugUI.Window:RegisterPage{
    id = "about",
    title = "About",
    order = 90,
    build = function(host, panel) Page:Build(host, panel) end,
}

return Page
