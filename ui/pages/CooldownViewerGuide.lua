-- ============================================================================
-- ThugUI: Buff workaround guide
--
-- Adopting Blizzard's buff frames (modules/CooldownViewer/BlizzBuffs.lua) is a
-- workaround for a game restriction, and it only pays off once the player has
-- made a handful of settings in BLIZZARD's own UI that ThugUI cannot make for
-- them. The failure when they have not is completely silent: the cell simply
-- stays empty, which is indistinguishable from a broken addon.
--
-- This is that explanation, with the player's own screenshots. It lives beside
-- the config window rather than inside the page so it can be full height and
-- never covers the controls it is describing.
--
-- SCREENSHOTS AND SetTexCoord
--
-- WoW does not load PNG. The .png originals in media/ are the source; the .tga
-- files beside them are what the game reads, and each was generated on a
-- 512x512 power-of-two canvas with the image anchored top-left and the rest
-- left transparent. Every one of them therefore HAS to be cropped with
-- SetTexCoord or the transparent padding is drawn as part of the picture --
-- u/v below are that crop, and aspect is the visible image's width/height.
--
-- The table is the single place a texture path appears: a step names a key,
-- and nothing else in this file knows what file that is.
-- ============================================================================

ThugUI = ThugUI or {}

local CV = ThugUI.CooldownViewer
local W = ThugUI.Widgets

local Guide = {}
CV.BuffGuide = Guide

local MEDIA = "Interface\\AddOns\\ThugUI\\media\\"

local SHOTS = {
    options = {
        file = "blizzard_menu_with_gameplay_enhancements_highlighted",
        u = 1.0000, v = 0.7871, aspect = 1.270,
    },
    cdmOption = {
        file = "blizzard_menu_with_cooldown_manager_highlighted",
        u = 0.9980, v = 0.7871, aspect = 1.268,
    },
    -- scale shrinks a shot against the standard popout width. This one is a tall
    -- narrow menu, so at full width it towered over every other step for no
    -- extra legibility.
    escMenu = {
        file = "blizzard_escape_menu_with_edit_mode_highlighted",
        u = 0.5059, v = 1.0000, aspect = 0.506, scale = 0.56,
    },
    editModeTick = {
        file = "HUD_edit_mode_with_cooldown_manager_box_checked_and_highlighted",
        u = 0.8906, v = 1.0000, aspect = 0.891,
    },
    clickToEdit = {
        file = "buff_bar_with_click_to_edit_printed_on_bar",
        u = 0.3594, v = 0.1836, aspect = 1.957,
    },
    advArrow = {
        file = "HUD_edit_mode_with_arrow_to_advanced_options",
        u = 1.0000, v = 0.7227, aspect = 1.384,
    },
    advButton = {
        file = "Tracked_buff_settings_window_with_Advanced_Cooldown_Settings_button_highlighted",
        u = 0.7266, v = 1.0000, aspect = 0.727,
    },
    buffsTab = {
        file = "advanced_cooldown_settings_window_with_buffs_tab_highlighted_and_both_"
            .. "the_tracked_buffs_and_tracked_bars_areas_highlighted",
        u = 0.7305, v = 1.0000, aspect = 0.730,
    },
    visibility = {
        file = "tracked_buffs_settings_window_with_visibility_dropdown_highlighted_and_"
            .. "arrows_to_both_correct_options",
        u = 0.7227, v = 1.0000, aspect = 0.723,
    },
    asIcon = {
        file = "buff_as_icon_with_counter",
        u = 0.6094, v = 0.4883, aspect = 1.248,
    },
    asBar = {
        file = "buff_as_icon_with_timer_bar",
        u = 0.6992, v = 0.5352, aspect = 1.307,
    },
}

-- Deliberately terse: the picture carries the idea, the line only has to say
-- which picture you are looking at. Step 1 has no screenshot and must still
-- render -- it is the one step that happens in ThugUI rather than in the game's
-- own settings, which is exactly the distinction people miss. It points at the
-- checkbox directly above it in this panel; if that ever moves back to the main
-- window, this line has to move with it.
--
-- The order is the order the player actually walked it, taken from when the
-- screenshots were made rather than from anyone's idea of a sensible sequence.
-- Two shots that were captured -- the Options and Gameplay Enhancements route to
-- the Cooldown Manager -- are deliberately NOT used: the checkbox in step 1
-- already reflects and sets that state, so sending the player through Blizzard's
-- options menu as well would be busywork. They stay in SHOTS in case that stops
-- being true.
local STEPS = {
    {
        text = "|cffffd100Use Blizzard's buff frames|r -- the tick just above. It shows "
            .. "the setting as it stands, so make sure it is on. Everything below this "
            .. "happens in the game's own settings, not in ThugUI.",
    },
    {
        text = "|cffffd100Esc > Edit Mode.|r",
        shots = { "escMenu" },
        caption = "Edit Mode lives in the game menu",
    },
    {
        text = "|cffffd100Open Advanced Options|r, and make sure |cffffd100Cooldown "
            .. "Manager|r is ticked. The buff frames do not exist until it is.",
        shots = { "advArrow", "editModeTick" },
        caption = "Advanced Options, then the Cooldown Manager tick",
    },
    {
        text = "|cffffd100Click the buff bar|r to edit it, then |cffffd100Advanced "
            .. "Cooldown Settings|r.",
        shots = { "clickToEdit", "advButton" },
        caption = "Click the bar itself, then Advanced Cooldown Settings",
    },
    {
        text = "|cffffd100Buffs tab - drag the buff into Tracked Buffs or Tracked Bars.|r "
            .. "Either list works. ThugUI can only place a buff that is in one of them.",
        shots = { "buffsTab" },
        caption = "Both areas are highlighted. Drag any buff you want on the grid into one of them",
    },
    {
        text = "|cffffd100Set the frame's visibility|r to |cffffd100Always|r or "
            .. "|cffffd100In Combat|r, whichever arrow you like. The icon is pulled from "
            .. "this frame, so one that is never displayed has nothing to pull.",
        shots = { "visibility" },
        caption = "Either highlighted option works",
    },
    {
        text = "|cffffd100Done.|r The two areas render the buff in the cell in two "
            .. "different ways, exactly as the default UI draws it.",
        shots = { "asIcon", "asBar" },
        layout = "row",
        caption = "Tracked Buffs on the left, Tracked Bars on the right - both in one ThugUI cell",
    },
}

-- Exposed so Tests/loadtest.lua can prove every key a step names really exists.
-- A typo there would draw a blank frame in game and nowhere else.
Guide.SHOTS = SHOTS
Guide.STEPS = STEPS

local PANEL_WIDTH = 260
local PANEL_INSET = 16
local SHOT_WIDTH  = 420   -- the popout is deliberately far wider than the panel
local SHOT_GAP    = 8
local SHOT_PAD    = 12

-- The caption's own box, off to the left of the images. Narrow on purpose: it
-- holds one line about what you are looking at, and a wide box would compete
-- with the screenshot for attention.
local CAPTION_WIDTH = 190
local CAPTION_PAD   = 10

-- ----------------------------------------------------------------------------
-- Screenshot popout
--
-- Its own frame rather than GameTooltip, which has no way to size an arbitrary
-- texture usefully. Anchored RIGHT to the row's LEFT so it opens back over the
-- config window (the panel already sits at the right edge of the window, so
-- opening rightwards would run off the screen) and centres vertically on
-- whatever row it belongs to -- see the anchor comment in ShowShot.
-- ----------------------------------------------------------------------------

function Guide:EnsurePopout()
    if self.popout then return self.popout end
    if not self.panel then return nil end

    local popout = CreateFrame("Frame", "ThugUI_BuffGuideShot", self.panel, "BackdropTemplate")
    -- Above the config window (HIGH), which it is drawn on top of. A child can
    -- carry its own strata, so this still hides with the panel.
    popout:SetFrameStrata("DIALOG")
    popout:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popout:SetBackdropColor(0, 0, 0, 0.95)
    popout:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    popout:Hide()

    -- Two, because no step names more than two. Unused ones are hidden, not
    -- created and destroyed.
    popout.shots = {}
    for i = 1, 2 do
        local tex = popout:CreateTexture(nil, "ARTWORK")
        tex:Hide()
        popout.shots[i] = tex
    end

    -- The caption gets its own box, off to the left, rather than sitting under
    -- the images. Underneath it was landing against the screenshot's own
    -- background and reading as part of the picture -- the one line that says
    -- what you are looking at was the easiest thing to miss.
    local box = CreateFrame("Frame", "ThugUI_BuffGuideCaption", popout, "BackdropTemplate")
    box:SetFrameStrata("DIALOG")
    box:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0, 0, 0, 0.95)
    box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    popout.captionBox = box

    local caption = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    caption:SetPoint("TOPLEFT", box, "TOPLEFT", CAPTION_PAD, -CAPTION_PAD)
    caption:SetWidth(CAPTION_WIDTH - CAPTION_PAD * 2)
    caption:SetJustifyH("LEFT")
    popout.caption = caption

    self.popout = popout
    return popout
end

function Guide:HideShot()
    if self.popout then self.popout:Hide() end
end

--- Show `step`'s screenshots beside `row`. A step with no screenshot closes the
--- popout rather than showing an empty box.
function Guide:ShowShot(row, step)
    if not row or not step or not step.shots or #step.shots == 0 then
        self:HideShot()
        return
    end

    local popout = self:EnsurePopout()
    if not popout then return end

    -- Side by side rather than stacked, for the one step whose whole point is
    -- that these are two renderings of the SAME thing. Stacked, they read as
    -- two sequential steps; beside each other, they read as a comparison.
    local sideBySide = step.layout == "row" and #step.shots > 1
    local width = SHOT_WIDTH
    if sideBySide then
        width = (SHOT_WIDTH - SHOT_GAP * (#step.shots - 1)) / #step.shots
    end

    local y = -SHOT_PAD
    local x = SHOT_PAD
    local rowHeight = 0
    local contentWidth = 0

    for i, tex in ipairs(popout.shots) do
        local shot = step.shots[i] and SHOTS[step.shots[i]]
        if shot then
            -- A scaled shot draws narrower AND makes the popout narrower with
            -- it, or a shrunken image would just sit in the same large box
            -- surrounded by empty backdrop.
            local shotWidth = width * (shot.scale or 1)
            local height = shotWidth / shot.aspect
            tex:SetTexture(MEDIA .. shot.file)
            -- Without this the transparent padding on the power-of-two canvas
            -- is drawn as if it were part of the screenshot.
            tex:SetTexCoord(0, shot.u, 0, shot.v)
            tex:SetSize(shotWidth, height)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", popout, "TOPLEFT", x, y)
            tex:Show()

            if sideBySide then
                -- One row: advance across, and the row is as tall as its
                -- tallest image so the box below clears both.
                x = x + shotWidth + SHOT_GAP
                rowHeight = math.max(rowHeight, height)
                contentWidth = x - SHOT_GAP - SHOT_PAD
            else
                y = y - height - SHOT_GAP
                contentWidth = math.max(contentWidth, shotWidth)
            end
        else
            tex:Hide()
        end
    end

    if sideBySide then y = y - rowHeight - SHOT_GAP end

    popout:SetSize(contentWidth + SHOT_PAD * 2, -y - SHOT_GAP + SHOT_PAD)

    -- Its own box, to the LEFT of the images. Sized to the text it holds, and
    -- top-aligned with the picture it describes.
    local box = popout.captionBox
    popout.caption:SetText(step.caption or "")
    box:SetSize(CAPTION_WIDTH,
        popout.caption:GetStringHeight() + CAPTION_PAD * 2)
    box:ClearAllPoints()
    box:SetPoint("TOPRIGHT", popout, "TOPLEFT", -SHOT_GAP, 0)
    box:SetShown((step.caption or "") ~= "")
    -- RIGHT to the row's LEFT, not TOPRIGHT to TOPLEFT: this centres the
    -- popout on the row regardless of how tall it ended up (one image, two
    -- stacked, or two side by side), because the popout is already sized to
    -- its contents by the time this line runs. No per-step offset table
    -- needed, and it cannot drift when the UI scale changes.
    popout:ClearAllPoints()
    popout:SetPoint("RIGHT", row, "LEFT", -8, 0)
    popout:Show()
end

-- ----------------------------------------------------------------------------
-- The panel
-- ----------------------------------------------------------------------------

--- Build the panel once, or hand back the one already built. Returns nil before
--- the config window exists, since the panel hangs off it.
function Guide:Ensure()
    if self.panel then return self.panel end

    local window = ThugUI.Window and ThugUI.Window.frame
    if not window then return nil end

    -- Outside the window's right edge, full height, so it never covers the page
    -- it is talking about.
    local panel = CreateFrame("Frame", "ThugUI_BuffGuidePanel", window, "BackdropTemplate")
    panel:SetWidth(PANEL_WIDTH)
    panel:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", 0, 0)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    panel:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
    panel:Hide()
    self.panel = panel

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PANEL_INSET, -16)
    title:SetText("|cff00ffccBUFF WORKAROUND|r")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() Guide:Hide() end)

    local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    intro:SetPoint("TOPLEFT", PANEL_INSET, -38)
    intro:SetWidth(PANEL_WIDTH - PANEL_INSET * 2)
    intro:SetJustifyH("LEFT")
    intro:SetText("The buff icon in any given cell is owned and PROTECTED by Blizzard. "
        .. "Below are the game settings needed before ThugUI is able to BORROW these "
        .. "assets from Blizzard's UI.")

    -- The checkbox that used to live on the main window. It moved here because
    -- every step below it explains what it turns on -- reading the setting and
    -- the explanation in the same place beats hunting back across the window
    -- for the tick box. Page:SetUseBlizzardBuffs is the one function this file
    -- calls so Apply() and the picker refresh do not get a second copy of
    -- their body.
    local useBlizzardBuffs = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    useBlizzardBuffs:SetSize(24, 24)
    useBlizzardBuffs:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)

    local cbLabel = useBlizzardBuffs:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbLabel:SetPoint("LEFT", useBlizzardBuffs, "RIGHT", 4, 0)
    cbLabel:SetText("Use Blizzard's buff frames")

    useBlizzardBuffs:SetScript("OnClick", function(self)
        CV.Page:SetUseBlizzardBuffs(self:GetChecked() and true or false)
    end)

    -- nil means ON -- see Data.BuffsAvailable, which this mirrors. Reading it
    -- as a plain truth test would show the checkbox unticked for every player
    -- who never touched the setting.
    function useBlizzardBuffs:Refresh()
        self:SetChecked(ThugUI_Config.cvUseBlizzardBuffs ~= false)
    end
    useBlizzardBuffs:Refresh()

    W.AttachTooltip(useBlizzardBuffs, "Use Blizzard's buff frames",
        "Buff icons cannot be drawn by an addon during combat: the game will "
            .. "not say which aura is which while you are fighting. With this on, "
            .. "Blizzard's own tracked-buff icon is placed in the cell you assigned it "
            .. "instead, so it works in combat.\n\n"
            .. "Needs the Cooldown Manager turned on, with those buffs tracked in Edit "
            .. "Mode. Turn this off to go back to ThugUI's own icons, which only draw "
            .. "out of combat.")

    self.blizzBuffsCB = useBlizzardBuffs

    self.rows = {}
    local previous = useBlizzardBuffs

    for i, step in ipairs(STEPS) do
        local row = CreateFrame("Button", nil, panel)
        row:SetWidth(PANEL_WIDTH - PANEL_INSET * 2)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)

        local number = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        number:SetPoint("TOPLEFT", 0, -1)
        number:SetWidth(16)
        number:SetJustifyH("LEFT")
        number:SetText(i .. ".")

        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 18, 0)
        text:SetWidth(PANEL_WIDTH - PANEL_INSET * 2 - 18)
        text:SetJustifyH("LEFT")
        text:SetText(step.text)

        -- Sized from the wrapped text, the same way Widgets' Note does it, so
        -- editing a line does not mean re-measuring the whole list by hand.
        row:SetHeight(math.max(text:GetStringHeight() + 6, 18))
        row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        row:SetScript("OnEnter", function(self) Guide:ShowShot(self, step) end)
        row:SetScript("OnLeave", function() Guide:HideShot() end)

        self.rows[i] = row
        previous = row
    end

    -- A child is hidden along with its parent on screen, but its own shown flag
    -- survives, so reopening settings would drag the guide back with it. It is
    -- something you open, every time.
    window:HookScript("OnHide", function() Guide:Hide() end)

    return panel
end

function Guide:IsShown()
    return (self.panel and self.panel:IsShown()) and true or false
end

function Guide:Show()
    local panel = self:Ensure()
    if panel then panel:Show() end
    -- The setting can change from the guide's own checkbox next time too, but
    -- it can also change while the panel is closed (a fresh session, or the
    -- picker's other callers) -- read the live value every time it opens.
    if self.blizzBuffsCB then self.blizzBuffsCB:Refresh() end
end

function Guide:Hide()
    self:HideShot()
    if self.panel then self.panel:Hide() end
end

function Guide:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

--- The clickable red [WORKAROUND] link, built into `panel` (a Widgets panel) at
--- its layout cursor. A Button rather than a bare FontString because a
--- FontString cannot take a hand cursor or a highlight, and the whole point is
--- that it has to look pressable.
function Guide:CreateLink(panel)
    local host = panel.parent

    local link = CreateFrame("Button", nil, host)
    local label = link:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", link, "LEFT", 0, 0)
    label:SetText("[WORKAROUND]")
    label:SetTextColor(1, 0.13, 0.13)
    link:SetSize(label:GetStringWidth() + 6, 18)
    link:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    link:SetScript("OnEnter", function() label:SetTextColor(1, 0.45, 0.45) end)
    link:SetScript("OnLeave", function() label:SetTextColor(1, 0.13, 0.13) end)
    link:SetScript("OnClick", function() Guide:Toggle() end)

    if W and W.AttachTooltip then
        W.AttachTooltip(link, "Buff workaround",
            "The settings this needs in Blizzard's own UI, step by step, with pictures. "
            .. "Opens beside this window.")
    end

    panel:Place(link, 22, { gap = 2, width = link:GetWidth() })
    return link
end

return Guide
