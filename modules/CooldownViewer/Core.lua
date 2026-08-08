-- ============================================================================
-- ThugUI: Cooldown Viewer -- runtime
--
-- One generic engine that renders whatever the active spec's profile says,
-- replacing the three hand-written bars (ECV/BCV/GCV). Adding a spec is now
-- a player dragging icons onto a grid, not ~200 lines of Lua.
--
-- The grid is invisible here. Only the icons draw -- the borders, cell lines
-- and intersection markers exist solely in the settings editor, which is the
-- whole point of designing the shape on a grid and wearing it without one.
--
-- The legacy bars still live in modules/EssentialRings.lua and are re-enabled
-- wholesale by setting ThugUI_Config.cvUseLegacy = true (/thugcv legacy).
-- Nothing in this file runs in that mode.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI.CooldownViewer = ThugUI.CooldownViewer or {}

local CV = ThugUI.CooldownViewer
local Data = CV.Data

local UPDATE_INTERVAL = 0.15   -- state refresh; cursor tracking is every frame
local CURSOR_GAP = 8           -- pixels between the cursor and the anchor point

CV.icons = {}          -- cellKey -> icon frame
CV.container = nil
CV.previewMode = false -- forced visible from the settings page

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

function CV:IsLegacyMode()
    return ThugUI_Config and ThugUI_Config.cvUseLegacy and true or false
end

--- The profile being drawn. Normally the active spec's, but while the settings
--- page previews a layout it draws whichever spec is being edited -- otherwise
--- ticking "preview" while building a layout for a spec you are not currently
--- in would show you a different spec's grid.
function CV:CurrentProfile()
    if self.previewMode and self.overrideSpecID then
        return Data.GetProfile(self.overrideSpecID)
    end
    return Data.GetActiveProfile()
end

--- Combat, or test mode standing in for it. Mirrors ER:IsInCombat so the two
--- halves of the addon agree about what "in combat" means for previewing.
local function InCombat()
    local ER = ThugUI.EssentialRings
    if ER and ER.IsInCombat then return ER:IsInCombat() end
    return InCombatLockdown() or UnitAffectingCombat("player")
end

local function IsSpellKnown(spellID)
    if not spellID then return false end
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID) then return true end
    return false
end

--- start, duration, ready, charges -- nil start means no cooldown data.
local function GetCooldown(spellID)
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then return nil end

    local charges
    if C_Spell.GetSpellCharges then
        local chargeInfo = C_Spell.GetSpellCharges(spellID)
        if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
            charges = chargeInfo.currentCharges
        end
    end

    -- A charge build is "ready" whenever a charge is banked, even though the
    -- recharge timer is always running.
    local ready
    if charges then
        ready = charges >= 1
    else
        ready = (info.duration or 0) <= 0 or (info.startTime or 0) == 0
    end

    return info.startTime, info.duration, ready, charges, info.modRate
end

local function GetAura(spellID)
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end
    return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
end

-- ----------------------------------------------------------------------------
-- Geometry
-- ----------------------------------------------------------------------------

function CV:GetCellSize(profile)
    local size = profile.iconSize or 32
    local pad = profile.padding or 4
    return size + pad, size + pad, size, pad
end

--- Container size for a full 10x10 grid. It stays constant regardless of how
--- many cells are filled, so an intersection anchor always means the same
--- place relative to the shape the player drew.
function CV:GetGridSize(profile)
    local cellW, cellH = self:GetCellSize(profile)
    return Data.GRID_COLS * cellW, Data.GRID_ROWS * cellH
end

-- ----------------------------------------------------------------------------
-- Frame construction
-- ----------------------------------------------------------------------------

function CV:EnsureContainer()
    if self.container then return self.container end

    local f = CreateFrame("Frame", "ThugUI_CooldownViewer", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    f:Hide()

    -- Drag handle used out of combat and while previewing. Deliberately not
    -- mouse-enabled the rest of the time: an invisible 10x10 grid swallowing
    -- clicks in the middle of the screen would be maddening.
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local profile = CV:CurrentProfile()
        profile.point = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 1, 0.8, 0.10)
    bg:Hide()
    f.previewBG = bg

    self.container = f
    return f
end

-- Icons are pooled rather than recreated. A layout edit re-runs Rebuild on
-- every slider tick, and SetParent(nil) does not free a frame in WoW -- it
-- orphans it -- so building fresh ones would bleed frames for a whole session.
CV.iconPool = {}

local function AcquireIcon(parent)
    for _, icon in ipairs(CV.iconPool) do
        if not icon.inUse then
            icon.inUse = true
            return icon
        end
    end

    local icon = CreateFrame("Frame", nil, parent)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.tex = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)
    icon.cooldown = cd

    local count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    count:Hide()
    icon.count = count

    icon:Hide()
    icon.inUse = true
    table.insert(CV.iconPool, icon)
    return icon
end

--- Rebuild every icon from the profile. Called on spec change, on any layout
--- edit, and on login.
function CV:Rebuild()
    local f = self:EnsureContainer()
    local profile = CV:CurrentProfile()

    for _, icon in ipairs(self.iconPool) do
        icon.inUse = false
        icon:Hide()
    end
    wipe(self.icons)

    local cellW, cellH, iconSize, pad = self:GetCellSize(profile)
    f:SetSize(self:GetGridSize(profile))
    f:SetScale(profile.scale or 1.0)

    for _, placement in ipairs(Data.GetPlacements(profile)) do
        local icon = AcquireIcon(f)
        icon:SetParent(f)
        icon:SetSize(iconSize, iconSize)

        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(placement.spellID)
        icon.tex:SetTexture(texture)
        icon.spellID = placement.spellID
        icon.mode = placement.mode
        icon.row, icon.col = placement.row, placement.col
        -- Resting state is "everything present". UpdateState corrects it, but
        -- it early-returns while the container is hidden, so without this the
        -- icons would sit unanchored until the first pass after they show.
        icon.wanted = true
        icon.cooldown:Clear()
        icon.count:Hide()

        self.icons[placement.key] = icon
    end

    self:ApplyLayout()
    self:UpdateVisibility()
    self:UpdateState()
end

--- Position every icon. Split out of Rebuild because with collapse enabled a
--- position depends on which icons are currently live, so this has to re-run on
--- every state update, not just on a layout edit.
function CV:ApplyLayout()
    local f = self.container
    if not f then return end

    local profile = CV:CurrentProfile()
    local cellW, cellH, _, pad = self:GetCellSize(profile)

    local function Put(icon, col)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", f, "TOPLEFT",
            (col - 1) * cellW + pad / 2,
            -((icon.row - 1) * cellH + pad / 2))
    end

    if (profile.collapse or "none") ~= "rows" then
        for _, icon in pairs(self.icons) do
            Put(icon, icon.col)
        end
        return
    end

    -- Bucket by row; each row compacts independently, which is what keeps an
    -- icon at a constant height no matter what else is on cooldown.
    local rows = {}
    for _, icon in pairs(self.icons) do
        rows[icon.row] = rows[icon.row] or {}
        table.insert(rows[icon.row], icon)
    end

    local packRight = Data.ResolveCollapseDirection(profile) == "right"

    for _, list in pairs(rows) do
        table.sort(list, function(a, b) return a.col < b.col end)

        -- Pack from the row's own outermost PLACED column, not the grid edge:
        -- a row at full strength must land exactly where the editor drew it.
        local firstCol, lastCol = list[1].col, list[#list].col

        local live = {}
        for _, icon in ipairs(list) do
            if icon.wanted then table.insert(live, icon) end
        end

        for i, icon in ipairs(live) do
            Put(icon, packRight and (lastCol - (#live - i)) or (firstCol + i - 1))
        end
    end
end

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

function CV:UpdateState()
    if not self.container or not self.container:IsShown() then return end

    -- Preview is about seeing the SHAPE, so every icon draws flat: cooldown and
    -- aura state are irrelevant, and an off-spec layout would otherwise render
    -- completely empty because none of its spells are known right now.
    if self.previewMode then
        for _, icon in pairs(self.icons) do
            icon.cooldown:Clear()
            icon.count:Hide()
            icon.wanted = true
            icon:Show()
        end
        -- Laid out through the same path as combat, so preview shows the real
        -- resting shape -- including the fact that with row collapse on, a
        -- horizontal gap you drew is closed even at full strength.
        self:ApplyLayout()
        return
    end

    for _, icon in pairs(self.icons) do
        local spellID = icon.spellID
        local show = false

        if not IsSpellKnown(spellID) then
            show = false
        elseif icon.mode == "aura" then
            local aura = GetAura(spellID)
            show = aura ~= nil
            if aura and aura.expirationTime and aura.duration and aura.duration > 0 then
                icon.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            else
                icon.cooldown:Clear()
            end
            if aura and aura.applications and aura.applications > 1 then
                icon.count:SetText(aura.applications)
                icon.count:Show()
            else
                icon.count:Hide()
            end
        else
            local start, duration, ready, charges, modRate = GetCooldown(spellID)

            if icon.mode == "always" then
                show = true
                if start and duration and duration > 0 then
                    icon.cooldown:SetCooldown(start, duration, modRate)
                else
                    icon.cooldown:Clear()
                end
            else
                -- "cooldown" mode: the icon IS the readiness signal, so there is
                -- nothing to sweep -- it simply disappears once spent.
                show = ready and true or false
                icon.cooldown:Clear()
            end

            if charges then
                icon.count:SetText(charges)
                icon.count:Show()
            else
                icon.count:Hide()
            end
        end

        icon.wanted = show
        icon:SetShown(show)
    end

    self:ApplyLayout()
end

function CV:ShouldShow()
    if self:IsLegacyMode() then return false end
    if self.previewMode then return true end

    local profile = CV:CurrentProfile()
    if not profile.enabled then return false end
    if next(profile.placements) == nil then return false end
    if profile.onlyInCombat and not InCombat() then return false end
    return true
end

function CV:UpdateVisibility()
    local f = self.container
    if not f then return end

    if not self:ShouldShow() then
        f:Hide()
        return
    end

    local profile = CV:CurrentProfile()
    f:SetScale(profile.scale or 1.0)

    -- The preview tint and the drag handle travel together: both are for
    -- placing the thing, and neither belongs on screen during a pull.
    local editable = self.previewMode or not InCombatLockdown()
    f.previewBG:SetShown(self.previewMode)
    f:EnableMouse(editable and not profile.followCursor)

    f:Show()

    if profile.followCursor and (self.previewMode or InCombat()) then
        self:UpdateCursorPosition()
    else
        self:ReleaseAnchor()
    end
end

--- Put the profile's chosen grid intersection under the cursor.
---
--- Offsets are divided by the container's own scale because SetPoint measures
--- them in the frame's coordinate space, the same correction the older bars
--- make in ER:UpdateBCVPosition.
function CV:UpdateCursorPosition()
    local f = self.container
    if not f or not f:IsShown() then return end

    local profile = CV:CurrentProfile()
    local scale = f:GetScale()
    if scale == 0 then return end

    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local x = cursorX / uiScale / scale
    local y = cursorY / uiScale / scale

    local cellW, cellH = self:GetCellSize(profile)
    local anchorOffsetX = (profile.anchorCol or 0) * cellW
    local anchorOffsetY = (profile.anchorRow or 0) * cellH

    -- Nudge the whole shape away from the cursor along the diagonal that points
    -- from the anchor towards the shape's bulk, so the icons never sit under
    -- the pointer itself.
    local gap = CURSOR_GAP / scale
    local gapX = (profile.anchorCol or 0) >= Data.GRID_COLS / 2 and -gap or gap
    local gapY = (profile.anchorRow or 0) >= Data.GRID_ROWS / 2 and gap or -gap

    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        x - anchorOffsetX + gapX,
        y + anchorOffsetY + gapY)
end

--- Back to the saved (dragged) position when the bar stops following the cursor.
function CV:ReleaseAnchor()
    local f = self.container
    if not f then return end

    local profile = CV:CurrentProfile()
    f:ClearAllPoints()
    if profile.point then
        f:SetPoint(profile.point.point, UIParent, profile.point.relPoint, profile.point.x, profile.point.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

--- Forced visibility while the settings page is open, so the player can see the
--- shape they are building without going and pulling something.
--- @param specID number? draw this spec's layout instead of the active one
function CV:SetPreview(enabled, specID)
    self.previewMode = enabled and true or false
    self.overrideSpecID = self.previewMode and specID or nil
    self:Rebuild()
end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

local driver = CreateFrame("Frame", "ThugUI_CooldownViewerDriver")
CV.driver = driver

local elapsedSinceUpdate = 0

driver:SetScript("OnUpdate", function(_, elapsed)
    if not CV.container or not CV.container:IsShown() then return end

    local profile = CV:CurrentProfile()
    if profile.followCursor and (CV.previewMode or InCombat()) then
        CV:UpdateCursorPosition()
    end

    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= UPDATE_INTERVAL then
        elapsedSinceUpdate = 0
        CV:UpdateState()
    end
end)

-- PLAYER_LOGIN, not ADDON_LOADED: migration reads ThugUI_Config, which
-- EssentialRings fills in from its own ADDON_LOADED handler, and
-- GetSpecialization is not dependable that early either. PLAYER_LOGIN fires
-- after every addon's ADDON_LOADED, so neither ordering question arises.
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterEvent("SPELL_UPDATE_CHARGES")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("UNIT_AURA")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

driver:SetScript("OnEvent", function(_, event, arg1)
    if CV:IsLegacyMode() then
        if CV.container then CV.container:Hide() end
        return
    end

    if event == "PLAYER_LOGIN" then
        CV:Initialize()
        return
    end

    if event == "UNIT_AURA" then
        if arg1 == "player" then CV:UpdateState() end
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "SPELLS_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
    then
        -- Spec change swaps the whole profile, so the icon set is rebuilt from
        -- scratch rather than re-pointed. The settings page follows along:
        -- clearing editSpecID makes it re-default to the spec now active.
        if event == "PLAYER_SPECIALIZATION_CHANGED" and CV.Page then
            CV.Page.editSpecID = nil
            CV.Page.selectedKey = nil
        end
        CV:Rebuild()
        if ThugUI.Window then ThugUI.Window:RefreshActivePage() end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        CV:UpdateVisibility()
        CV:UpdateState()
        return
    end

    CV:UpdateState()
end)

-- ----------------------------------------------------------------------------
-- Init
-- ----------------------------------------------------------------------------

function CV:Initialize()
    Data.MigrateLegacyBars()
    self:EnsureContainer()
    self:Rebuild()
end

-- Slash command: quick escape hatch back to the old bars, and a way to force a
-- rebuild without a /reload while iterating on a layout.
SLASH_THUGCV1 = "/thugcv"
SlashCmdList["THUGCV"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "legacy" then
        ThugUI_Config.cvUseLegacy = not ThugUI_Config.cvUseLegacy
        local ER = ThugUI.EssentialRings
        if ThugUI_Config.cvUseLegacy then
            if CV.container then CV.container:Hide() end
            print("|cff00ff00ThugUI:|r cooldown viewer switched to the |cffffd100legacy|r ECV/BCV/GCV bars.")
        else
            CV:Rebuild()
            print("|cff00ff00ThugUI:|r cooldown viewer switched to the |cff00ffccgrid|r engine.")
        end
        if ER and ER.UpdateVisibility then ER:UpdateVisibility() end
        return
    end

    if msg == "rebuild" then
        CV:Rebuild()
        print("|cff00ff00ThugUI:|r cooldown viewer rebuilt.")
        return
    end

    ThugUI:ToggleOptions("cooldownviewer")
end

return CV
