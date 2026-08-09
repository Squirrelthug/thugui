-- ============================================================================
-- ThugUI: Target of Target
--
-- Blizzard's own target-of-target frame is the small 120x49 art. This module
-- draws target-of-target with the *full* target frame art instead, so the unit
-- your target is attacking reads at the same glance-distance as your target.
--
-- Built on oUF (vendored at libs/oUF), which owns the unit event routing and
-- the health/power/portrait element updates. Everything below is the ThugUI
-- layout applied on top of it.
--
-- Two things worth knowing before editing the layout:
--
--  * "targettarget" is a derived unit token -- the game fires no UNIT_HEALTH
--    for it. oUF spots the `%w+target` suffix in walkObject (ouf.lua:294) and
--    routes the frame through HandleEventlessUnit, which polls. That is why
--    onUpdateFrequency below exists and why nothing here registers events.
--
--  * every geometry number is lifted verbatim from
--    Blizzard_UnitFrame/Mainline/TargetFrame.xml (client 12.0.7), and the whole
--    anchor graph is reproduced rather than replaced with eyeballed offsets.
--    The frame art is anchored CENTER with useAtlasSize, so the art is NOT the
--    same size as the 232x100 button -- anything positioned against the button
--    box by hand would sit wrong now and drift again whenever Blizzard reissues
--    the atlas. Reproducing the graph means it lands where Blizzard's does.
-- ============================================================================

local addonName, ns = ...
local oUF = ns.oUF

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

local ToT = {}
ThugUI.TargetOfTarget = ToT

ToT.frame = nil
ToT.mover = nil
ToT.pendingApply = false

local function Cfg(key, fallback)
    local v = ThugUI_Config[key]
    if v == nil then return fallback end
    return v
end

-- ============================================================================
-- BLIZZARD ART
-- ============================================================================

local ART = "UI-HUD-UnitFrame-Target-PortraitOn"

local FRAME_W, FRAME_H = 232, 100
local PORTRAIT_SIZE    = 58
local HEALTH_W, HEALTH_H = 126, 20
local POWER_W, POWER_H   = 134, 10

-- The one number here that is not Blizzard's. Their health bar offset puts the
-- pair of bars a full resource-bar height too high on this frame -- the health
-- bar lands in the resource bar's groove and the resource bar hangs off the
-- bottom of the art. POWER_H accounts for nearly all of it; the trailing 2px
-- was measured off the live frame to seat the resource bar on the bottom of its
-- groove. Adjust this alone if the bars ever need renudging.
local BAR_DROP = POWER_H + 2

-- The plain "-Bar-Health" atlas is the finished green bar and is what Blizzard
-- draws; TargetFrameHealthBarMixin sets lockColor = true (TargetFrame.lua:1035)
-- so it is never tinted, which is why a retail target frame stays green for
-- hostile units. The "-Status" twin is the same shape drawn neutral, meant to
-- be tinted -- that is the one to use for class/reaction coloring.
local HEALTH_ATLAS        = ART .. "-Bar-Health"
local HEALTH_ATLAS_TINTED = ART .. "-Bar-Health-Status"

-- Blizzard picks the power bar art by power token rather than by tinting one
-- texture (UnitFrame.lua:527, UnitFrameManaBar_UpdateType). PowerBarColor is a
-- live global, so reading atlasElementName off it keeps rage/energy/focus/
-- runic power correct without a hardcoded table that would rot.
local function PowerAtlas(unit)
    local _, token = UnitPowerType(unit)
    local info = token and PowerBarColor and PowerBarColor[token]
    local element = info and info.atlasElementName

    if element then
        local atlas = ART .. "-Bar-" .. element
        if C_Texture.GetAtlasInfo(atlas) then
            return atlas
        end
    end

    return ART .. "-Bar-Mana"
end

-- ============================================================================
-- ELEMENT CALLBACKS
-- ============================================================================

-- oUF only calls SetStatusBarColor when one of its color flags claims the bar.
-- In "blizzard" mode every flag is off, so `color` arrives nil and the bar keeps
-- whatever was last set on it -- which breaks the moment colorDisconnected
-- paints it grey, because nothing would ever paint it back. Repaint here on any
-- update where nothing else claimed the color.
local function PostUpdateHealthColor(element, unit, color)
    if color or not element.thugBlizzardColor then return end
    element:SetStatusBarColor(1, 1, 1)
end

local function PostUpdatePower(element, unit)
    local atlas = PowerAtlas(unit)
    if atlas ~= element.thugAtlas then
        element.thugAtlas = atlas
        element:SetStatusBarTexture(atlas)
        element:SetStatusBarColor(1, 1, 1)
    end
end

-- The strip behind the name is the reaction color on a real target frame, and
-- it is the only thing on the frame that shows hostility now that the health
-- bar is locked green. Tap-denied units go grey, matching CheckFaction
-- (TargetFrame.lua:303).
local function UpdateReputationColor(frame, unit)
    local rep = frame.ThugReputation
    if not rep or not rep:IsShown() then return end
    if not unit or not UnitExists(unit) then return end

    if not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
        rep:SetVertexColor(0.5, 0.5, 0.5)
        if frame.Portrait then frame.Portrait:SetVertexColor(0.5, 0.5, 0.5) end
    else
        rep:SetVertexColor(UnitSelectionColor(unit))
        if frame.Portrait then frame.Portrait:SetVertexColor(1, 1, 1) end
    end
end

-- ============================================================================
-- STYLE
-- ============================================================================

local function ThugToTStyle(self, unit)
    self:SetSize(FRAME_W, FRAME_H)
    self:SetHitRectInsets(0, 5, 4, 9)  -- Blizzard's, keeps clicks on the art
    self:RegisterForClicks("AnyUp")

    -- --------------------------------------------------------------------
    -- Frame art. Sub-levels matter: the portrait has to sit under the art so
    -- the ring in the atlas crops it, exactly as TargetFrameContainer stacks
    -- Portrait (BACKGROUND/1) beneath FrameTexture (BACKGROUND/2).
    -- --------------------------------------------------------------------

    -- Sits behind the portrait so that turning the portrait off leaves a dark
    -- socket inside the ring rather than a hole you can see the world through.
    local socket = self:CreateTexture(nil, "BACKGROUND", nil, 0)
    socket:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    socket:SetPoint("TOPRIGHT", self, "TOPRIGHT", -26, -19)
    socket:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    socket:Hide()
    self.ThugPortraitSocket = socket

    local portrait = self:CreateTexture(nil, "BACKGROUND", nil, 1)
    portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    portrait:SetPoint("TOPRIGHT", self, "TOPRIGHT", -26, -19)
    self.Portrait = portrait

    -- CircleMask is what the XML uses, but MaskTexture:SetAtlas has no wrap
    -- mode argument and a mask needs CLAMPTOBLACKADDITIVE to hide everything
    -- outside itself. TempPortraitAlphaMask is the same circle as a plain file,
    -- so it can be set with the wrap modes spelled out.
    local mask = self:CreateMaskTexture()
    mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]],
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, -1)
    mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 0)
    portrait:AddMaskTexture(mask)
    socket:AddMaskTexture(mask)

    local art = self:CreateTexture(nil, "BACKGROUND", nil, 2)
    art:SetAtlas(ART, true)
    art:SetPoint("CENTER")
    art:SetTexelSnappingBias(0)
    art:SetSnapToPixelGrid(false)
    self.ThugArt = art

    -- --------------------------------------------------------------------
    -- Content. A child frame so everything in it draws above the art, which
    -- is how Blizzard separates TargetFrameContent from TargetFrameContainer.
    -- --------------------------------------------------------------------
    local content = CreateFrame("Frame", nil, self)
    content:SetAllPoints()
    content:SetFrameLevel(self:GetFrameLevel() + 1)
    self.ThugContent = content

    local rep = content:CreateTexture(nil, "BACKGROUND")
    rep:SetAtlas(ART .. "-Type", true)
    rep:SetPoint("TOPRIGHT", self, "TOPRIGHT", -75, -25)
    self.ThugReputation = rep

    local name = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetSize(90, 12)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    name:SetPoint("TOPLEFT", rep, "TOPRIGHT", -106, -1)
    -- Deliberately NOT `ThugName`: RaidFrames:RefreshFrames walks every oUF
    -- object and treats a frame carrying that key as one of its raid buttons.
    self.ThugToTName = name

    local health = CreateFrame("StatusBar", nil, content)
    health:SetSize(HEALTH_W, HEALTH_H)
    -- Blizzard's own offset here is y = 2; see BAR_DROP for why it needs the
    -- correction. Dropping the health bar moves both bars, because the resource
    -- bar hangs off the health bar's BOTTOMRIGHT.
    health:SetPoint("BOTTOMRIGHT", self, "LEFT", 148, 2 - BAR_DROP)
    health:SetStatusBarTexture(HEALTH_ATLAS)
    health:SetStatusBarColor(1, 1, 1)
    health.colorDisconnected = true
    health.PostUpdateColor = PostUpdateHealthColor
    self.Health = health

    local power = CreateFrame("StatusBar", nil, content)
    power:SetSize(POWER_W, POWER_H)
    power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 8, -1)
    power:SetStatusBarTexture(ART .. "-Bar-Mana")
    power:SetStatusBarColor(1, 1, 1)
    power.frequentUpdates = true
    power.PostUpdate = PostUpdatePower
    self.Power = power

    self.PostUpdate = function(frame, event, u)
        UpdateReputationColor(frame, u or frame.unit)
    end

    -- Deferred on purpose. oUF runs the style function first and only then
    -- walks every element it found on the frame calling EnableElement
    -- (ouf.lua:331), so anything disabled in here is switched straight back on
    -- -- the power bar would show with totShowPowerBar off. Next frame puts our
    -- element state after oUF's.
    C_Timer.After(0, function()
        ToT:ApplySettings()
    end)
end

-- ============================================================================
-- SETTINGS
-- ============================================================================

function ToT:ApplySettings()
    local frame = self.frame
    if not frame then return end

    -- Health -------------------------------------------------------------
    local health = frame.Health
    local mode = Cfg("totHealthColor", "blizzard")

    health.colorClass    = (mode == "class")
    health.colorClassNPC = (mode == "class")
    health.colorClassPet = (mode == "class")
    health.colorReaction = (mode == "class" or mode == "reaction")
    health.colorTapping  = (mode ~= "blizzard")
    health.thugBlizzardColor = (mode == "blizzard")

    if mode == "blizzard" then
        health:SetStatusBarTexture(HEALTH_ATLAS)
        health:SetStatusBarColor(1, 1, 1)
    else
        health:SetStatusBarTexture(HEALTH_ATLAS_TINTED)
    end

    if Cfg("totShowHealthBar", true) then
        if not frame:IsElementEnabled("Health") then frame:EnableElement("Health") end
        health:Show()
    else
        if frame:IsElementEnabled("Health") then frame:DisableElement("Health") end
        health:Hide()
    end

    -- Power --------------------------------------------------------------
    if Cfg("totShowPowerBar", true) then
        if not frame:IsElementEnabled("Power") then frame:EnableElement("Power") end
        frame.Power:Show()
    else
        if frame:IsElementEnabled("Power") then frame:DisableElement("Power") end
        frame.Power:Hide()
    end

    -- Portrait -----------------------------------------------------------
    -- Only the image is dropped, never the art around it. Blizzard does ship
    -- "PortraitOff" variants of this atlas family (TargetFrame.lua:1252), but
    -- no retail frame uses the Target one, so its bar geometry is unverified --
    -- swapping to it would move the bars by an unknown amount.
    if Cfg("totShowPortrait", true) then
        if not frame:IsElementEnabled("Portrait") then frame:EnableElement("Portrait") end
        frame.Portrait:Show()
        frame.ThugPortraitSocket:Hide()
    else
        if frame:IsElementEnabled("Portrait") then frame:DisableElement("Portrait") end
        frame.Portrait:Hide()
        frame.ThugPortraitSocket:Show()
    end

    -- Name and reaction strip --------------------------------------------
    if Cfg("totShowName", true) then
        frame:Tag(frame.ThugToTName, "[name]")
        frame.ThugToTName:Show()
    else
        frame:Untag(frame.ThugToTName)
        frame.ThugToTName:Hide()
    end

    frame.ThugReputation:SetShown(Cfg("totShowReputation", true))

    if not InCombatLockdown() then
        frame:SetScale(Cfg("totScale", 1.0))
    end

    if frame.UpdateAllElements then
        frame:UpdateAllElements("ThugUI_ConfigChanged")
    end

    self:UpdateMoverGeometry()
end

-- ============================================================================
-- SPAWN
-- ============================================================================

function ToT:SpawnFrame()
    if self.frame then return self.frame end
    if not oUF then return nil end

    oUF:RegisterStyle("ThugUITargetOfTarget", ThugToTStyle)
    oUF:SetActiveStyle("ThugUITargetOfTarget")

    local frame = oUF:Spawn("targettarget", "ThugUI_TargetOfTarget")
    self.frame = frame

    -- Eventless frames default to a 0.5s poll, set before the frame exists.
    -- Blizzard's own target-of-target runs at 0.2s; 0.25 keeps a tank swap
    -- visible about as fast without doubling the work.
    frame.onUpdateFrequency = 0.25
    oUF:HandleEventlessUnit(frame)

    self:RestorePosition()
    return frame
end

-- ============================================================================
-- POSITION AND MOVER
--
-- The frame is anchored to the mover with a zero offset rather than to UIParent
-- with saved coordinates, and the mover is what carries the saved point. That
-- is what makes the scale slider safe: anchor offsets are measured in the
-- anchored frame's own coordinate space, so a scaled frame anchored to UIParent
-- drifts every time the scale changes. Zero offsets cannot drift, and the mover
-- itself is never scaled. A hidden frame still anchors, so the mover only needs
-- to be *shown* when the user wants to drag it.
-- ============================================================================

local DEFAULT_POINT = { point = "CENTER", relPoint = "CENTER", x = 300, y = 140 }

function ToT:EnsureMover()
    if self.mover then return self.mover end

    local mover = CreateFrame("Frame", "ThugUI_TargetOfTargetMover", UIParent)
    mover:SetFrameStrata("HIGH")
    mover:SetSize(FRAME_W, FRAME_H)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetClampedToScreen(true)

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.6, 1.0, 0.35)
    mover.ThugBackground = bg

    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText("ThugUI Target of Target\n(drag to move)")
    label:SetJustifyH("CENTER")
    mover.ThugLabel = label

    mover:SetScript("OnDragStart", function(f)
        f:StartMoving()
    end)

    mover:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()

        local point, _, relPoint, x, y = f:GetPoint()
        ThugUI_Config.totPoint = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Invisible but positioned from the first frame, because the unit frame
    -- hangs off it. Alpha rather than Hide(): hiding the mover would be fine
    -- for anchoring but would also hide nothing else, and keeping it shown at
    -- zero alpha means SetUnlocked only has to touch alpha and mouse input.
    mover:SetAlpha(0)
    mover:EnableMouse(false)

    self.mover = mover
    self:RestoreMoverPosition()
    return mover
end

--- True when touching the mover's geometry would be refused.
---
--- The mover itself is an ordinary frame, but the oUF unit button is ANCHORED
--- to it, and that button is protected. The game will not let an addon move or
--- resize a frame a protected frame depends on while in combat -- doing so
--- through an anchor is the same as moving the protected frame directly.
---
--- This matters far beyond a mis-sized mover. The refusal does not merely fail:
--- it raises ADDON_ACTION_BLOCKED and **taints ThugUI for the rest of the
--- session**. Tainted execution then receives SECRET values from APIs such as
--- UnitPower, which is how a mover resize during a pull ends up stopping the
--- resource ring from being able to read your energy at all.
---
--- Before the unit frame is spawned nothing protected depends on the mover, so
--- it is free to move.
function ToT:MoverGeometryBlocked()
    return self.frame ~= nil and InCombatLockdown()
end

function ToT:RestoreMoverPosition()
    if not self.mover then return end

    if self:MoverGeometryBlocked() then
        self.pendingApply = true
        return
    end

    local saved = ThugUI_Config.totPoint or DEFAULT_POINT
    self.mover:ClearAllPoints()
    self.mover:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
end

function ToT:RestorePosition()
    -- The mover is moved first and unconditionally: it carries the saved point
    -- and is not protected, so resetting the position still works when the unit
    -- frame has not been spawned yet or we are mid-combat.
    local mover = self:EnsureMover()
    self:RestoreMoverPosition()

    if not self.frame then return end
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", mover, "CENTER", 0, 0)
end

function ToT:UpdateMoverGeometry()
    if not self.mover then return end

    -- See MoverGeometryBlocked: this exact call is what BugGrabber caught
    -- tainting the addon, and the taint is what turns UnitPower secret.
    if self:MoverGeometryBlocked() then
        self.pendingApply = true
        return
    end

    local scale = Cfg("totScale", 1.0)
    self.mover:SetSize(FRAME_W * scale, FRAME_H * scale)
end

function ToT:SetUnlocked(unlocked)
    local mover = self:EnsureMover()
    self:UpdateMoverGeometry()

    if unlocked then
        mover:SetAlpha(1)
        mover:EnableMouse(true)
    else
        mover:SetAlpha(0)
        mover:EnableMouse(false)
    end
end

-- ============================================================================
-- BLIZZARD TARGET OF TARGET
--
-- Blizzard's own frame is driven by the showTargetOfTarget CVar
-- (TargetFrame.lua:1129), which is the same switch as Interface Options ->
-- "Show Target of Target". Flipping the CVar is the supported way to turn it
-- off: no Show() override, no reparent, no taint. The previous value is saved
-- so unticking the option gives the player back exactly what they had, even
-- across a reload.
-- ============================================================================

function ToT:UpdateBlizzardToT()
    local hide = Cfg("totEnabled", false) and Cfg("totHideBlizzardToT", true)
    local current = GetCVar("showTargetOfTarget")

    if hide then
        if current ~= "0" then
            ThugUI_Config.totRestoreBlizzardToT = (current == "1")
            SetCVar("showTargetOfTarget", "0")
        end
    elseif ThugUI_Config.totRestoreBlizzardToT then
        ThugUI_Config.totRestoreBlizzardToT = nil
        SetCVar("showTargetOfTarget", "1")
    end
end

-- ============================================================================
-- ENTRY POINTS
-- ============================================================================

function ToT:ApplyAll()
    if not oUF then return end

    -- Spawning, showing and repositioning all touch a protected unit button,
    -- so defer wholesale rather than half-applying.
    if InCombatLockdown() then
        self.pendingApply = true
        return
    end

    if not Cfg("totEnabled", false) then
        if self.frame then
            UnregisterUnitWatch(self.frame)
            self.frame:Hide()
        end
        self:SetUnlocked(false)
        self:UpdateBlizzardToT()
        return
    end

    local firstSpawn = not self.frame
    if firstSpawn then
        self:SpawnFrame()
    else
        -- RegisterUnitWatch re-shows the frame by itself when the unit exists.
        RegisterUnitWatch(self.frame)
        self:RestorePosition()
        self:ApplySettings()
    end

    self:UpdateBlizzardToT()
    self:SetUnlocked(Cfg("totUnlocked", false))
end

function ToT:Initialize()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if ToT.pendingApply then
                ToT.pendingApply = false
                ToT:ApplyAll()
            end
            return
        end

        ToT:ApplyAll()
    end)

    self.watcher = watcher
end
