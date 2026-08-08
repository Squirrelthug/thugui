-- ThugUI: OrbAnchors Module
-- Converts UI elements into movable Orb anchors (Chat, Objectives Tracker, etc.)
-- Includes Stream Text Box (transparent, artless chat) and Objectives Wrapper.

local MODULE_NAME = "OrbAnchors"
local MEDIA_PATH = "Interface\\AddOns\\ThugUI\\media\\"

-- This module originally referenced Ring_20px.tga and Ring_10px.tga, neither of
-- which ships in media/ -- SetTexture fails silently on a bad path, so the orbs
-- drew with no ring at all. Both now point at Ring_Main.tga, the ring art the
-- rest of ThugUI already uses. Swap these if dedicated orb art is added.
local ORB_RING_TEXTURE = MEDIA_PATH .. "Ring_Main.tga"
local ORB_HIGHLIGHT_TEXTURE = MEDIA_PATH .. "Ring_Main.tga"

local OrbAnchors = {}
ThugUI:RegisterModule(MODULE_NAME, OrbAnchors)

-- Local references
local db
local dbChat
local dbObj
local chatOrbFrame
local objectivesOrbFrame
local streamChatFrame
local streamMessageFrame
local optionsMenuFrame

-- Mode Constants
local CHAT_MODE_NORMAL = 1
local CHAT_MODE_STREAM = 2
local CHAT_MODE_HIDDEN = 3

-- Which stream-filter key each chat event answers to. This is the single source
-- of truth: the events registered, the filter lookup, and the checkbox list in
-- the right-click menu are all derived from it.
--
-- Deliberately an explicit table rather than the old pattern-matching chain
-- (`if key:find("WHISPER")`), which silently rewrote BN_WHISPER to WHISPER and
-- left the BN_WHISPER setting unreadable.
--
-- Grouping choices worth knowing:
--   INSTANCE_CHAT rides with PARTY. It is what LFG, delve and random-dungeon
--   groups actually use, and it was missing entirely -- group chat simply never
--   appeared in a queued group.
--   TEXT_EMOTE rides with EMOTE, so /wave and /thank show alongside /e, which
--   is what you want for RP.
--   Battle.net whispers ride with WHISPER; one toggle covers both.
local CHANNEL_KEY_BY_EVENT = {
    CHAT_MSG_SAY                  = "SAY",
    CHAT_MSG_YELL                 = "YELL",
    CHAT_MSG_EMOTE                = "EMOTE",
    CHAT_MSG_TEXT_EMOTE           = "EMOTE",
    CHAT_MSG_WHISPER              = "WHISPER",
    CHAT_MSG_WHISPER_INFORM       = "WHISPER",
    CHAT_MSG_BN_WHISPER           = "WHISPER",
    CHAT_MSG_BN_WHISPER_INFORM    = "WHISPER",
    CHAT_MSG_PARTY                = "PARTY",
    CHAT_MSG_PARTY_LEADER         = "PARTY",
    CHAT_MSG_INSTANCE_CHAT        = "PARTY",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "PARTY",
    CHAT_MSG_RAID                 = "RAID",
    CHAT_MSG_RAID_LEADER          = "RAID",
    CHAT_MSG_RAID_WARNING         = "RAID",
    CHAT_MSG_GUILD                = "GUILD",
    CHAT_MSG_OFFICER              = "OFFICER",
    CHAT_MSG_CHANNEL              = "CHANNEL",
    CHAT_MSG_SYSTEM               = "SYSTEM",
}

-- Bracket label per channel key. CHANNEL is handled separately so it can print
-- the real channel name (Trade, General, ...) instead of "Channel".
--
-- These carry no colour of their own any more. The line's colour now comes from
-- ChatTypeInfo (see GetChatColor), which is the same table the real chat window
-- reads and which the player edits under Options > Social > Chat colours. The
-- old hardcoded escape codes ignored that config and, worse, only ever tinted
-- the bracket -- the message body itself printed white, so guild/trade/raid all
-- looked identical at a glance.
local CHANNEL_LABEL = {
    SAY     = "Say",
    YELL    = "Yell",
    EMOTE   = "Emote",
    WHISPER = "Whisper",
    PARTY   = "Party",
    RAID    = "Raid",
    GUILD   = "Guild",
    OFFICER = "Officer",
    SYSTEM  = "System",
}

-- Fallback colours for the handful of chat types ChatTypeInfo may not carry.
local FALLBACK_COLOR = { r = 1, g = 1, b = 1 }

-- Colour for a line, straight from Blizzard's own per-type table so the stream
-- box matches the real chat window (and the player's own colour choices).
--
-- Numbered channels each get their own entry keyed CHANNEL1..CHANNEL10 by
-- channel *index*, which is why channelIndex is threaded through here: it is
-- what makes Trade and Services visually distinct rather than both landing on
-- the generic CHANNEL colour.
local function GetChatColor(event, channelIndex)
    local info
    local chatType = event and event:sub(10) -- strip the "CHAT_MSG_" prefix

    if chatType == "CHANNEL" and channelIndex and channelIndex > 0 then
        info = ChatTypeInfo["CHANNEL" .. channelIndex]
    end
    if not info and chatType then
        info = ChatTypeInfo[chatType]
    end

    info = info or FALLBACK_COLOR
    return info.r or 1, info.g or 1, info.b or 1
end

-- Values arriving from chat events can be "secret" in 12.x -- readable by
-- Blizzard code but poison to addon code, which errors on any comparison,
-- concatenation or table index involving them. An error thrown inside our
-- OnEvent aborts the handler, so a single secret GUID silently swallows the
-- whole message. That is exactly what was happening: your own messages carry
-- an accessible GUID and printed fine, while other players' emotes and most
-- Trade/Services traffic vanished. Prat and Total RP 3 both guard these same
-- args; we now do too.
local issecret = _G.issecretvalue
local canaccess = _G.canaccessvalue

local function IsUsable(value)
    if value == nil then return false end
    if issecret and issecret(value) then return false end
    if canaccess and not canaccess(value) then return false end
    return true
end

-- Order and labels for the right-click menu checkboxes.
local CHANNEL_TOGGLES = {
    { key = "SAY",     label = "Say" },
    { key = "EMOTE",   label = "Emote" },
    { key = "YELL",    label = "Yell" },
    { key = "WHISPER", label = "Whisper" },
    { key = "PARTY",   label = "Party" },
    { key = "RAID",    label = "Raid" },
    { key = "GUILD",   label = "Guild" },
    { key = "OFFICER", label = "Officer" },
    { key = "CHANNEL", label = "Trade/Gen" },
    { key = "SYSTEM",  label = "System" },
}

-- Combat lockdown queue
local pendingCombatActions = {}

local function QueueCombatAction(actionFunc)
    if InCombatLockdown() then
        table.insert(pendingCombatActions, actionFunc)
        return true
    end
    actionFunc()
    return false
end

-- Event frame for combat lockdown processing
local combatEventFrame = CreateFrame("Frame")
combatEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        for _, actionFunc in ipairs(pendingCombatActions) do
            actionFunc()
        end
        wipe(pendingCombatActions)
    end
end)

-------------------------------------------------------------------------------
-- Helper: Resolve Objectives Tracker Frame across WoW versions
-------------------------------------------------------------------------------
local function GetObjectivesTrackerFrame()
    return ObjectiveTrackerFrame or WatchFrame or QuestWatchFrame
end

-- A parent that is never shown. Anything reparented into it stops drawing and
-- stays that way even if its own Show() is called repeatedly.
local hiddenHolder
local function GetHiddenHolder()
    if not hiddenHolder then
        hiddenHolder = CreateFrame("Frame", "ThugUI_HiddenHolder", UIParent)
        hiddenHolder:Hide()
    end
    return hiddenHolder
end

-------------------------------------------------------------------------------
-- Generic Orb Creator Factory
-------------------------------------------------------------------------------
function OrbAnchors:CreateOrb(id, config, title, defaultIcon, onClick, onRightClick)
    local orbName = "ThugUI_Orb_" .. id
    local orb = CreateFrame("Button", orbName, UIParent)
    orb.id = id
    orb.config = config
    
    orb:SetSize(config.size or 36, config.size or 36)
    orb:SetPoint(config.point or "CENTER", UIParent, config.point or "CENTER", config.x or 0, config.y or 0)
    orb:SetFrameStrata("HIGH")
    orb:SetClampedToScreen(true)
    
    -- Background circle
    local bg = orb:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetAllPoints(orb)
    bg:SetVertexColor(0.05, 0.05, 0.08, 0.85)
    orb.bg = bg
    
    -- Outer Ring texture
    local ring = orb:CreateTexture(nil, "ARTWORK")
    ring:SetTexture(ORB_RING_TEXTURE)
    ring:SetAllPoints(orb)
    local c = config.color or {1, 1, 1, 0.9}
    ring:SetVertexColor(c[1], c[2], c[3], c[4] or 0.9)
    orb.ring = ring

    -- Inner Icon or text badge
    local icon = orb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon:SetPoint("CENTER", orb, "CENTER", 0, 0)
    icon:SetText(defaultIcon or id)
    icon:SetTextColor(1, 1, 1, 0.95)
    orb.icon = icon

    -- Optional artwork in place of the letters. Any Blizzard icon path works,
    -- e.g. "Interface\\ICONS\\INV_Misc_Food_02". Circular-cropped with SetTexCoord
    -- so a square icon does not poke out past the ring.
    local art = orb:CreateTexture(nil, "ARTWORK")
    art:SetPoint("CENTER", orb, "CENTER", 0, 0)
    art:SetSize((config.size or 36) * 0.62, (config.size or 36) * 0.62)
    art:Hide()
    orb.art = art

    orb.SetArt = function(self, texturePath)
        if texturePath and texturePath ~= "" then
            self.art:SetTexture(texturePath)
            -- Blizzard's ICONS all carry a baked-in border that has to be
            -- cropped off. ThugUI's own media already has its margin built in,
            -- so cropping it would clip the artwork.
            if texturePath:lower():find("interface\\icons\\", 1, true) then
                self.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                self.art:SetTexCoord(0, 1, 0, 1)
            end
            self.art:Show()
            self.icon:Hide()
        else
            self.art:Hide()
            self.icon:Show()
        end
    end
    orb:SetArt(config.iconTexture)

    -- Hover Highlight
    local highlight = orb:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(ORB_HIGHLIGHT_TEXTURE)
    highlight:SetAllPoints(orb)
    highlight:SetVertexColor(1, 1, 1, 0.4)
    orb.highlight = highlight

    -- Sub-label under orb
    local label = orb:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    label:SetPoint("TOP", orb, "BOTTOM", 0, -3)
    label:SetTextColor(0.8, 0.8, 0.8, 0.9)
    orb.label = label
    
    -- Drag & Click mechanics
    orb:SetMovable(true)
    orb:EnableMouse(true)
    orb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    orb:RegisterForDrag("LeftButton")

    -- Press feedback must NOT resize or move the orb.
    --
    -- This used to be self:SetScale(0.93) on mouse-down. SetScale scales a frame
    -- about its anchor point, so pressing shrank the orb away from the cursor --
    -- if you had clicked anywhere but near the anchor side, the button was no
    -- longer under the mouse when you released, the button-up never landed on
    -- it, and RegisterForClicks("LeftButtonUp") never fired OnClick. That is the
    -- "only certain parts of the circle toggle" behaviour. It also left the orb
    -- stuck at 0.93 whenever the cursor left the frame before mouse-up, since
    -- OnMouseUp then never ran.
    --
    -- Nudging the glyph and brightening the backdrop reads the same but leaves
    -- the hit rectangle untouched.
    local function SetPressed(self, pressed)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("CENTER", self, "CENTER", 0, pressed and -1 or 0)
        if pressed then
            self.bg:SetVertexColor(0.15, 0.15, 0.20, 0.95)
        else
            self.bg:SetVertexColor(0.05, 0.05, 0.08, 0.85)
        end
    end
    orb.SetPressed = SetPressed

    orb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            SetPressed(self, true)
        end
    end)

    orb:SetScript("OnMouseUp", function(self, button)
        SetPressed(self, false)
    end)

    orb:SetScript("OnDragStart", function(self)
        if not db.locked or IsShiftKeyDown() then
            self:StartMoving()
            self.isDragging = true
        end
    end)

    orb:SetScript("OnDragStop", function(self)
        SetPressed(self, false)
        if self.isDragging then
            self:StopMovingOrSizing()
            self.isDragging = false
            local point, _, relPoint, x, y = self:GetPoint()
            config.point = point
            config.x = math.floor(x + 0.5)
            config.y = math.floor(y + 0.5)
            
            -- Reposition anchored UI element
            OrbAnchors:UpdateAnchors()
        end
    end)

    orb:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if onClick then onClick(self) end
        elseif button == "RightButton" then
            if onRightClick then onRightClick(self) end
        end
    end)

    -- Tooltip
    orb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 0, 1, 0.8)
        
        if self.GetTooltipText then
            self:GetTooltipText(GameTooltip)
        end
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-Click:|r Cycle Mode / Toggle", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cff00ff00Right-Click:|r Options", 0.7, 0.7, 0.7)
        if db.locked then
            GameTooltip:AddLine("|cffffaa00Shift + Left-Drag:|r Move Orb", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("|cff00ff00Left-Drag:|r Move Orb", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)

    orb:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Mouse-up can land outside the orb, so clear the pressed look here too
        -- rather than leaving the glyph stuck offset.
        SetPressed(self, false)
    end)

    return orb
end

-------------------------------------------------------------------------------
-- Stream Text Box Setup (Artless, Transparent Floating Chat Window)
-------------------------------------------------------------------------------
function OrbAnchors:CreateStreamChatFrame()
    if streamChatFrame then return end

    local frame = CreateFrame("Frame", "ThugUI_StreamChatFrame", UIParent)
    frame:SetSize(dbChat.streamWidth or 420, dbChat.streamHeight or 220)
    frame:SetPoint("TOPLEFT", chatOrbFrame, "BOTTOMLEFT", 0, -10)
    frame:SetFrameStrata("BACKGROUND")
    
    -- Transparent background (no borders, no artwork). Nothing to do: a plain
    -- Frame has no backdrop by default. The old frame:SetBackdrop(nil) here was
    -- a hard error -- SetBackdrop only exists on frames created with
    -- "BackdropTemplate", which this one is not.

    -- Scrolling Message Frame
    local smf = CreateFrame("ScrollingMessageFrame", "ThugUI_StreamChatMessageFrame", frame)
    smf:SetAllPoints(frame)
    
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    smf:SetFont(fontPath, dbChat.fontSize or 14, dbChat.fontOutline or "OUTLINE")
    smf:SetShadowColor(0, 0, 0, 0.9)
    smf:SetShadowOffset(1, -1)
    smf:SetMaxLines(250)
    smf:SetFading(false)
    smf:SetJustifyH("LEFT")
    smf:EnableMouseWheel(true)
    
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if IsShiftKeyDown() then
                self:ScrollToTop()
            else
                self:ScrollUp()
            end
        else
            if IsShiftKeyDown() then
                self:ScrollToBottom()
            else
                self:ScrollDown()
            end
        end
    end)

    -- Resize Handle (Visible when mouse hovers or when position unlocked)
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
            frame.isResizing = true
        end
    end)
    
    resizeGrip:SetScript("OnMouseUp", function(self, button)
        if frame.isResizing then
            frame:StopMovingOrSizing()
            frame.isResizing = false
            local w, h = frame:GetSize()
            dbChat.streamWidth = math.floor(w + 0.5)
            dbChat.streamHeight = math.floor(h + 0.5)
        end
    end)
    
    frame:SetResizable(true)
    -- SetMinResize/SetMaxResize were removed from the API in Dragonflight;
    -- there are zero uses left in Blizzard's own UI and calling them here was a
    -- nil-method error that killed Stream mode the first time it was opened.
    -- SetResizeBounds(minW, minH, maxW, maxH) is the replacement.
    frame:SetResizeBounds(200, 100, 1000, 800)

    streamChatFrame = frame
    streamMessageFrame = smf

    -- Register Chat Event Listener
    self:RegisterChatEvents()
end

-------------------------------------------------------------------------------
-- Chat Event Handling for Stream Text Window
-------------------------------------------------------------------------------
function OrbAnchors:RegisterChatEvents()
    local eventFrame = CreateFrame("Frame")

    for ev in pairs(CHANNEL_KEY_BY_EVENT) do
        eventFrame:RegisterEvent(ev)
    end

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if dbChat.mode ~= CHAT_MODE_STREAM or not streamMessageFrame then return end

        -- Check channel filtering
        local channelKey = CHANNEL_KEY_BY_EVENT[event]
        if not channelKey then return end

        if dbChat.channels and dbChat.channels[channelKey] == false then
            return
        end

        -- Run the message through the same filter chain Blizzard's chat frame
        -- uses, and honour both its verdict and any rewritten arguments.
        --
        -- Without this the stream box sees a firehose that the real chat window
        -- never shows you. The clearest case: Total RP 3 bundles Chomp, which
        -- whispers other players to trade RP profiles, then registers a
        -- CHAT_MSG_SYSTEM filter to swallow the "No player named X is currently
        -- playing" errors its own traffic provokes when someone logs off. Those
        -- were reaching the box because we read the raw event.
        --
        -- ChatFrame1 is passed as the reference frame because "would the main
        -- chat window print this?" is exactly the question being asked. Filters
        -- already run inside securecallfunction, so a broken third-party filter
        -- degrades to "no opinion" rather than breaking the stream.
        -- Results are taken by multiple assignment off a single filter pass.
        -- The old code did `{ ProcessMessageEventFilters(...) }` then
        -- table.remove(_, 1) to drop the discard flag. Chat events contain
        -- interior nils (arg10 is unused, arg14-17 are frequently nil), so that
        -- table has holes, and table.remove only shifts up to whatever border
        -- `#` happens to return. When it returned short, every arg past the hole
        -- stayed put and was read one slot off -- guid came back as lineID,
        -- channelBaseName as a channel number. Multiple assignment carries nils
        -- positionally and has no such failure mode.
        --
        -- One call, not one per arg: the chain is stateful. TRP3's filter stashes
        -- npcMessageId/ownershipNameId per line and strips prefixes off the
        -- message it returns, so calling it repeatedly would feed it its own
        -- output.
        local discard, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12

        if ChatFrameUtil and ChatFrameUtil.ProcessMessageEventFilters then
            discard, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 =
                ChatFrameUtil.ProcessMessageEventFilters(ChatFrame1, event, ...)
            if discard then return end -- a filter asked for this to be dropped
        else
            a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 = ...
        end

        local message         = a1
        local sender          = a2
        local channelName     = a4
        local channelIndex    = a8
        local channelBaseName = a9
        local lineID          = a11
        local guid            = a12

        if not IsUsable(message) then return end

        -- Total RP 3 NPC-speech emotes ("|| The guard salutes") are rewritten by
        -- its message filter down to a single space, with the real text moved
        -- into the sender name so TRP3's own name filter can render it. Reading
        -- the message alone therefore printed a blank line for every RP NPC
        -- emote -- the other half of "my emotes show, other people's don't".
        -- TRP3 exposes the stashed text keyed by line ID; that is a documented
        -- entry point, unlike re-running the name-filter chain by hand.
        local npcLine
        local TRP3 = _G.TRP3_API
        if message == " " and TRP3 and TRP3.chat and TRP3.chat.getNPCMessageID then
            if TRP3.chat.getNPCMessageID() == lineID then
                local npcName = TRP3.chat.getNPCMessageName and TRP3.chat.getNPCMessageName()
                if IsUsable(npcName) and npcName ~= "" then
                    npcLine = npcName
                end
            end
        end

        -- Raw sender, class-coloured. Both the name and the GUID are guarded:
        -- an unreadable value here used to throw and take the whole message
        -- down with it.
        local shortSender = "Unknown"
        if IsUsable(sender) then
            shortSender = sender:match("([^%-]+)") or sender
        end

        local colorHex
        if IsUsable(guid) then
            local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
            if ok and IsUsable(class) and ThugUI.classColors[class] then
                local r, g, b = unpack(ThugUI.classColors[class])
                colorHex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
            end
        end

        local displaySender = colorHex
            and string.format("|cff%s%s|r", colorHex, shortSender)
            or shortSender

        -- Bracket label, driven off channelKey rather than the event name. The
        -- old chain matched raw event names and so tagged nothing at all for the
        -- events added later (INSTANCE_CHAT, TEXT_EMOTE).
        local tag = ""
        if channelKey == "CHANNEL" then
            -- Show the real channel name (Trade, General, ...) not "Channel".
            local name = IsUsable(channelBaseName) and channelBaseName
                      or IsUsable(channelName) and channelName
                      or "Chan"
            tag = string.format("[%s] ", name)
        elseif CHANNEL_LABEL[channelKey] then
            tag = string.format("[%s] ", CHANNEL_LABEL[channelKey])
        end

        local timestamp = ""
        if dbChat.showTimestamp then
            timestamp = "|cff888888" .. date("%H:%M") .. "|r "
        end

        -- Not everything is "Name: text".
        --   A recovered TRP3 NPC emote is already a complete line.
        --   TEXT_EMOTE (/wave) already arrives as a whole sentence with the
        --     name baked in -- prefixing a name would print it twice.
        --   EMOTE (/e sighs) is the emote body only, and reads as "Name sighs"
        --     with no colon.
        --   SYSTEM has no sender at all; the old format left a stray colon.
        local formattedMsg
        if npcLine then
            formattedMsg = string.format("%s%s%s", timestamp, tag, npcLine)
        elseif event == "CHAT_MSG_TEXT_EMOTE" or event == "CHAT_MSG_SYSTEM" then
            formattedMsg = string.format("%s%s%s", timestamp, tag, message)
        elseif event == "CHAT_MSG_EMOTE" then
            formattedMsg = string.format("%s%s%s %s", timestamp, tag, displaySender, message)
        else
            formattedMsg = string.format("%s%s%s: %s", timestamp, tag, displaySender, message)
        end

        -- Colour the whole line per channel. Embedded escape codes (the class
        -- colour on the name, the grey timestamp) still win for their own spans,
        -- so the body and bracket take the channel colour and the name stays
        -- class-coloured.
        local index = IsUsable(channelIndex) and tonumber(channelIndex) or nil
        streamMessageFrame:AddMessage(formattedMsg, GetChatColor(event, index))
    end)
end

-------------------------------------------------------------------------------
-- Chat Mode Switching
-------------------------------------------------------------------------------
function OrbAnchors:SetChatMode(mode)
    dbChat.mode = mode

    QueueCombatAction(function()
        local chatFrame1 = ChatFrame1
        local dock = GeneralDockManager

        if mode == CHAT_MODE_NORMAL then
            -- Default Normal Chat Frame
            if chatFrame1 then
                chatFrame1:Show()
                chatFrame1:ClearAllPoints()
                chatFrame1:SetPoint("TOPLEFT", chatOrbFrame, "BOTTOMLEFT", 0, -10)
            end
            if dock then dock:Show() end
            if streamChatFrame then streamChatFrame:Hide() end

            chatOrbFrame.ring:SetVertexColor(0.2, 0.7, 1.0, 0.9)
            chatOrbFrame.icon:SetText("CHAT")
            chatOrbFrame.label:SetText("Normal")
            -- The acorn texture is plain white, so the tint is what carries the
            -- mode when artwork replaces the CHAT/STRM/OFF letters.
            chatOrbFrame.art:SetDesaturated(false)
            chatOrbFrame.art:SetVertexColor(0.55, 0.82, 1.00, 1)

        elseif mode == CHAT_MODE_STREAM then
            -- Stream Text Window (Transparent, artless)
            if chatFrame1 then chatFrame1:Hide() end
            if dock then dock:Hide() end
            
            OrbAnchors:CreateStreamChatFrame()
            streamChatFrame:Show()
            streamChatFrame:ClearAllPoints()
            streamChatFrame:SetPoint("TOPLEFT", chatOrbFrame, "BOTTOMLEFT", 0, -10)

            chatOrbFrame.ring:SetVertexColor(0.2, 1.0, 0.5, 0.9)
            chatOrbFrame.icon:SetText("STRM")
            chatOrbFrame.label:SetText("Stream")
            chatOrbFrame.art:SetDesaturated(false)
            chatOrbFrame.art:SetVertexColor(0.55, 1.00, 0.72, 1)

        elseif mode == CHAT_MODE_HIDDEN then
            -- Hidden mode
            if chatFrame1 then chatFrame1:Hide() end
            if dock then dock:Hide() end
            if streamChatFrame then streamChatFrame:Hide() end

            chatOrbFrame.ring:SetVertexColor(0.5, 0.5, 0.5, 0.5)
            chatOrbFrame.icon:SetText("OFF")
            chatOrbFrame.label:SetText("Hidden")
            -- Matches the objectives orb's hidden tint, so "greyed out acorn"
            -- means the same thing on both.
            chatOrbFrame.art:SetDesaturated(true)
            chatOrbFrame.art:SetVertexColor(0.55, 0.55, 0.58, 0.85)
        end
    end)
end

function OrbAnchors:CycleChatMode()
    local nextMode = dbChat.mode + 1
    if nextMode > CHAT_MODE_HIDDEN then
        nextMode = CHAT_MODE_NORMAL
    end
    self:SetChatMode(nextMode)
end

-------------------------------------------------------------------------------
-- Objectives Tracker Visibility & Anchoring
-------------------------------------------------------------------------------
function OrbAnchors:SetObjectivesVisibility(visible)
    dbObj.visible = visible
    local tracker = GetObjectivesTrackerFrame()

    QueueCombatAction(function()
        if not tracker then return end

        if visible then
            tracker:SetParent(UIParent)
            tracker:Show()
            tracker:ClearAllPoints()
            tracker:SetPoint("TOPRIGHT", objectivesOrbFrame, "BOTTOMRIGHT", 0, -10)

            objectivesOrbFrame.ring:SetVertexColor(1.0, 0.82, 0.2, 0.9)
            objectivesOrbFrame.icon:SetText("OBJ")
            objectivesOrbFrame.label:SetText("Shown")
            -- Keep the state readable when artwork replaces the letters. The
            -- acorn texture is plain white, so the tint carries the state.
            objectivesOrbFrame.art:SetDesaturated(false)
            objectivesOrbFrame.art:SetVertexColor(0.95, 0.80, 0.45, 1)
        else
            -- Reparent into a permanently hidden holder rather than hiding it.
            --
            -- tracker:Hide() alone does not hold -- the tracker re-shows itself
            -- from ObjectiveTracker_Update, quest events and Edit Mode. A
            -- visibility state driver does not hold either, and that is what
            -- caused the flash: the driver's conditional is the constant
            -- "hide", so it evaluates once, hides the frame, and never fires
            -- again; Blizzard's very next Show() wins and the tracker comes
            -- straight back.
            --
            -- A child of a hidden parent is never drawn no matter how often
            -- something calls Show() on it, so this holds without overriding
            -- any method or parking the frame offscreen (either of which would
            -- taint it). Fully reversible, which a Show() override is not.
            tracker:SetParent(GetHiddenHolder())

            objectivesOrbFrame.ring:SetVertexColor(0.5, 0.5, 0.5, 0.5)
            objectivesOrbFrame.icon:SetText("OFF")
            objectivesOrbFrame.label:SetText("Hidden")
            objectivesOrbFrame.art:SetDesaturated(true)
            objectivesOrbFrame.art:SetVertexColor(0.55, 0.55, 0.58, 0.85)
        end
    end)
end

function OrbAnchors:ToggleObjectivesVisibility()
    self:SetObjectivesVisibility(not dbObj.visible)
end

-------------------------------------------------------------------------------
-- Anchor Positioning Update
-------------------------------------------------------------------------------
function OrbAnchors:UpdateAnchors()
    QueueCombatAction(function()
        if chatOrbFrame then
            chatOrbFrame:ClearAllPoints()
            chatOrbFrame:SetPoint(dbChat.point or "BOTTOMLEFT", UIParent, dbChat.point or "BOTTOMLEFT", dbChat.x or 25, dbChat.y or 220)
            
            if dbChat.mode == CHAT_MODE_NORMAL and ChatFrame1 then
                ChatFrame1:ClearAllPoints()
                ChatFrame1:SetPoint("TOPLEFT", chatOrbFrame, "BOTTOMLEFT", 0, -10)
            elseif dbChat.mode == CHAT_MODE_STREAM and streamChatFrame then
                streamChatFrame:ClearAllPoints()
                streamChatFrame:SetPoint("TOPLEFT", chatOrbFrame, "BOTTOMLEFT", 0, -10)
            end
        end

        if objectivesOrbFrame then
            objectivesOrbFrame:ClearAllPoints()
            objectivesOrbFrame:SetPoint(dbObj.point or "TOPRIGHT", UIParent, dbObj.point or "TOPRIGHT", dbObj.x or -260, dbObj.y or -220)

            local tracker = GetObjectivesTrackerFrame()
            if tracker and dbObj.visible then
                tracker:ClearAllPoints()
                tracker:SetPoint("TOPRIGHT", objectivesOrbFrame, "BOTTOMRIGHT", 0, -10)
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- Quick Options Dropdown / Dialog Frame
-------------------------------------------------------------------------------
function OrbAnchors:OpenOptionsMenu(orb)
    if not optionsMenuFrame then
        local menu = CreateFrame("Frame", "ThugUI_OrbOptionsMenu", UIParent, "BackdropTemplate")
        menu:SetSize(220, 240)
        menu:SetFrameStrata("DIALOG")
        menu:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        menu:SetBackdropColor(0.08, 0.08, 0.12, 0.95)

        local title = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", menu, "TOP", 0, -12)
        title:SetText("ThugUI Orb Settings")
        menu.title = title

        -- Close Button
        local closeBtn = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -2)

        -- Lock Toggle Button
        local lockBtn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        lockBtn:SetSize(190, 22)
        lockBtn:SetPoint("TOP", title, "BOTTOM", 0, -12)
        lockBtn:SetScript("OnClick", function()
            db.locked = not db.locked
            menu:UpdateButtons()
            print("|cff00ff00ThugUI:|r Orbs are now " .. (db.locked and "|cffff4040Locked|r" or "|cff40ff40Unlocked|r"))
        end)
        menu.lockBtn = lockBtn

        -- Font Size Label & Buttons for Stream Box
        local fontLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fontLabel:SetPoint("TOPLEFT", lockBtn, "BOTTOMLEFT", 0, -14)
        fontLabel:SetText("Stream Font Size:")
        menu.fontLabel = fontLabel

        local fontDec = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        fontDec:SetSize(28, 20)
        fontDec:SetPoint("LEFT", fontLabel, "RIGHT", 10, 0)
        fontDec:SetText("-")
        fontDec:SetScript("OnClick", function()
            dbChat.fontSize = math.max(8, (dbChat.fontSize or 14) - 1)
            if streamMessageFrame then
                local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                streamMessageFrame:SetFont(fontPath, dbChat.fontSize, dbChat.fontOutline or "OUTLINE")
            end
            menu:UpdateButtons()
        end)

        local fontVal = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fontVal:SetPoint("LEFT", fontDec, "RIGHT", 8, 0)
        menu.fontVal = fontVal

        local fontInc = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        fontInc:SetSize(28, 20)
        fontInc:SetPoint("LEFT", fontVal, "RIGHT", 8, 0)
        fontInc:SetText("+")
        fontInc:SetScript("OnClick", function()
            dbChat.fontSize = math.min(32, (dbChat.fontSize or 14) + 1)
            if streamMessageFrame then
                local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                streamMessageFrame:SetFont(fontPath, dbChat.fontSize, dbChat.fontOutline or "OUTLINE")
            end
            menu:UpdateButtons()
        end)

        -- Stream channel filters. Two columns, only shown for the chat orb --
        -- they mean nothing on the objectives orb, and the menu shrinks back
        -- when it is opened from there.
        local chanLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chanLabel:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -16)
        chanLabel:SetText("Stream Channels:")
        menu.chanLabel = chanLabel

        menu.channelChecks = {}
        for i, ch in ipairs(CHANNEL_TOGGLES) do
            local row = math.floor((i - 1) / 2)
            local col = (i - 1) % 2

            local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", chanLabel, "BOTTOMLEFT", 2 + col * 100, -4 - row * 22)

            local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            text:SetText(ch.label)

            cb.channelKey = ch.key
            cb:SetScript("OnClick", function(self)
                dbChat.channels = dbChat.channels or {}
                dbChat.channels[self.channelKey] = self:GetChecked() and true or false
            end)

            menu.channelChecks[i] = cb
        end

        menu.channelRows = math.ceil(#CHANNEL_TOGGLES / 2)

        -- Reset Positions Button
        local resetBtn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        resetBtn:SetSize(190, 22)
        resetBtn:SetPoint("BOTTOM", menu, "BOTTOM", 0, 14)
        resetBtn:SetText("Reset Orb Positions")
        resetBtn:SetScript("OnClick", function()
            dbChat.point = "BOTTOMLEFT"
            dbChat.x = 25
            dbChat.y = 220
            dbObj.point = "TOPRIGHT"
            dbObj.x = -260
            dbObj.y = -220
            OrbAnchors:UpdateAnchors()
            print("|cff00ff00ThugUI:|r Reset Orb positions to default.")
        end)

        menu.fontDec = fontDec
        menu.fontInc = fontInc

        -- forChatOrb: the menu is shared by both orbs, but the font size and
        -- channel filters only mean anything for the stream box. Hide them and
        -- shrink the frame when it is opened from the objectives orb.
        function menu:UpdateButtons(forChatOrb)
            lockBtn:SetText(db.locked and "Unlock Orbs (Allow Drag)" or "Lock Orbs (Prevent Drag)")
            fontVal:SetText(tostring(dbChat.fontSize or 14))

            local streamWidgets = {
                self.fontLabel, self.fontDec, self.fontVal, self.fontInc, self.chanLabel,
            }
            for _, w in ipairs(streamWidgets) do
                w:SetShown(forChatOrb)
            end

            for _, cb in ipairs(self.channelChecks) do
                cb:SetShown(forChatOrb)
                -- Anything not explicitly false is on, matching the filter.
                cb:SetChecked(not (dbChat.channels and dbChat.channels[cb.channelKey] == false))
            end

            if forChatOrb then
                self:SetHeight(120 + self.channelRows * 22 + 56)
            else
                self:SetHeight(130)
            end
        end

        optionsMenuFrame = menu
    end

    optionsMenuFrame:ClearAllPoints()
    optionsMenuFrame:SetPoint("TOPLEFT", orb, "TOPRIGHT", 10, 0)
    optionsMenuFrame:UpdateButtons(orb.id == "Chat")
    optionsMenuFrame:Show()
end

-------------------------------------------------------------------------------
-- Module Initialization
-------------------------------------------------------------------------------
function OrbAnchors:Initialize()
    db = ThugUIDB.OrbAnchors
    if not db or not db.enabled then return end

    dbChat = db.chatOrb
    dbObj = db.objectivesOrb

    -- Create Chat Orb Anchor
    chatOrbFrame = self:CreateOrb(
        "Chat",
        dbChat,
        "|cff00ccffChat Orb Anchor|r",
        "CHAT",
        function() OrbAnchors:CycleChatMode() end,
        function(orb) OrbAnchors:OpenOptionsMenu(orb) end
    )
    chatOrbFrame.GetTooltipText = function(self, tooltip)
        local modeStr = "Normal Chat"
        if dbChat.mode == CHAT_MODE_STREAM then modeStr = "Stream Box (Transparent)"
        elseif dbChat.mode == CHAT_MODE_HIDDEN then modeStr = "Hidden" end
        tooltip:AddLine("Current Mode: |cffffd100" .. modeStr .. "|r")
    end

    -- Create Objectives Orb Anchor
    objectivesOrbFrame = self:CreateOrb(
        "Objectives",
        dbObj,
        "|cffffd100Objectives Tracker Orb|r",
        "OBJ",
        function() OrbAnchors:ToggleObjectivesVisibility() end,
        function(orb) OrbAnchors:OpenOptionsMenu(orb) end
    )
    objectivesOrbFrame.GetTooltipText = function(self, tooltip)
        local statusStr = dbObj.visible and "Shown" or "Hidden"
        tooltip:AddLine("Tracker Status: |cffffd100" .. statusStr .. "|r")
    end

    -- Apply initial modes and positions after full frame loading
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    initFrame:SetScript("OnEvent", function(self, event)
        OrbAnchors:SetChatMode(dbChat.mode or CHAT_MODE_NORMAL)
        OrbAnchors:SetObjectivesVisibility(dbObj.visible ~= false)
        OrbAnchors:UpdateAnchors()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end)

    -- Register Slash Commands
    SLASH_THUGORB1 = "/orb"
    SLASH_THUGORB2 = "/thugorb"
    SlashCmdList["THUGORB"] = function(msg)
        local cmd, arg = msg:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()

        if cmd == "lock" or cmd == "unlock" then
            db.locked = (cmd == "lock")
            print("|cff00ff00ThugUI:|r Orbs are now " .. (db.locked and "|cffff4040Locked|r" or "|cff40ff40Unlocked|r"))
        elseif cmd == "chat" then
            if arg == "normal" or arg == "1" then OrbAnchors:SetChatMode(CHAT_MODE_NORMAL)
            elseif arg == "stream" or arg == "2" then OrbAnchors:SetChatMode(CHAT_MODE_STREAM)
            elseif arg == "hide" or arg == "3" then OrbAnchors:SetChatMode(CHAT_MODE_HIDDEN)
            else OrbAnchors:CycleChatMode() end
        elseif cmd == "obj" or cmd == "objectives" then
            if arg == "show" or arg == "1" then OrbAnchors:SetObjectivesVisibility(true)
            elseif arg == "hide" or arg == "0" then OrbAnchors:SetObjectivesVisibility(false)
            else OrbAnchors:ToggleObjectivesVisibility() end
        elseif cmd == "font" and tonumber(arg) then
            dbChat.fontSize = tonumber(arg)
            if streamMessageFrame then
                local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                streamMessageFrame:SetFont(fontPath, dbChat.fontSize, dbChat.fontOutline or "OUTLINE")
            end
            print("|cff00ff00ThugUI:|r Stream Chat Font Size set to " .. dbChat.fontSize)
        elseif cmd == "icon" then
            -- /orb icon <chat|obj> <iconName|none>
            local which, name = arg:match("^(%S*)%s*(.-)$")
            which = (which or ""):lower()

            local target, targetDB
            if which == "obj" or which == "objectives" then
                target, targetDB = objectivesOrbFrame, dbObj
            elseif which == "chat" then
                target, targetDB = chatOrbFrame, dbChat
            else
                print("|cff00ff00ThugUI:|r Usage: /orb icon <chat|obj> <iconName|none>")
                print("  e.g. /orb icon obj INV_Misc_Food_02")
                return
            end

            if name == "" or name:lower() == "none" then
                -- Stored as false, not nil. DeepMergeDefaults only fills keys
                -- that are nil, so clearing this to nil would let the acorn
                -- default reappear on the next reload; false sticks.
                targetDB.iconTexture = false
                target:SetArt(false)
                print("|cff00ff00ThugUI:|r " .. which .. " orb reverted to text badge.")
            else
                -- Accept a bare icon name or a full texture path.
                local path = name:find("\\") and name or ("Interface\\ICONS\\" .. name)
                targetDB.iconTexture = path
                target:SetArt(path)
                print("|cff00ff00ThugUI:|r " .. which .. " orb icon set to " .. path)
                print("  If the orb went blank, that icon name does not exist.")
            end
        elseif cmd == "reset" then
            dbChat.point = "BOTTOMLEFT"
            dbChat.x = 25
            dbChat.y = 220
            dbObj.point = "TOPRIGHT"
            dbObj.x = -260
            dbObj.y = -220
            OrbAnchors:UpdateAnchors()
            print("|cff00ff00ThugUI:|r Orb positions reset to defaults.")
        else
            print("|cff00ff00ThugUI Orb Commands:|r")
            print("  /orb lock | unlock - Lock or unlock orb dragging")
            print("  /orb chat [normal|stream|hide] - Switch Chat Mode")
            print("  /orb obj [show|hide] - Toggle Objectives Tracker")
            print("  /orb font <size> - Set Stream Chat Font Size")
            print("  /orb icon <chat|obj> <iconName|none> - Use artwork instead of letters")
            print("  /orb reset - Reset Orb positions")
        end
    end
end
