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

--- Is this spell available to the player right now?
---
--- Asked BY NAME, because C_Spell.GetSpellInfo only resolves a name to a spell
--- the player actually has -- a nil return doubles as "not talented". By ID it
--- resolves for any spell in the game, so an ID check answers a different
--- question entirely.
---
--- This also handles override spells, which is where an ID check goes wrong in
--- both directions: a talent that replaces a base spell leaves IsPlayerSpell
--- disagreeing with itself depending on which of the pair you ask about, so
--- icons flicker in and out as talents and overrides shift. The stored ID picks
--- the artwork; the name decides whether it draws.
local function IsSpellAvailable(spellName)
    if not spellName then return false end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellName)
    return (ok and info and info.spellID) and true or false
end

--- Is the spell usable right now? Returns ready, charges.
---
--- Readiness is derived from `isActive` and `isOnGCD`, NEVER from startTime or
--- duration, for two independent reasons:
---
---  1. The global cooldown is a running cooldown. Judging by duration means
---     every icon on the grid vanishes the moment you cast anything, because
---     during the GCD every spell reports a cooldown. `isOnGCD` marks exactly
---     that case so it can be ignored.
---  2. In 12.x startTime/duration are *secret values*. Comparing them does not
---     yield a usable boolean -- the result is itself secret, and feeding that
---     to SetShown hides the icon. `isActive`/`isOnGCD` were added non-secret
---     in 12.0.1 for this.
---
--- This mirrors IsSpellReady in modules/EssentialRings.lua, which is the logic
--- the original druid bars have been running on all along.
--- Queried BY NAME for the same reason as IsSpellAvailable: the name resolves
--- to whichever version of the spell the player currently has talented, so the
--- cooldown read always matches the button they actually press.
local function IsSpellReady(spellName)
    -- Charge builds are ready whenever a charge is banked, even though the
    -- recharge timer is always running.
    local ok, chargeInfo = pcall(C_Spell.GetSpellCharges, spellName)
    if ok and chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
        local current = chargeInfo.currentCharges
        if current ~= nil and not (issecretvalue and issecretvalue(current)) then
            return current > 0, current
        end
        -- Charges are secret this tick (they often are in combat). Falling
        -- through to isActive would read the *recharge* timer, which for a
        -- charge spell is essentially always running, and the icon would sit
        -- hidden even with charges banked. Fail open instead: a reminder that
        -- shows slightly too eagerly beats one that disappears mid-fight.
        return true
    end

    local ok2, cdInfo = pcall(C_Spell.GetSpellCooldown, spellName)
    if ok2 and cdInfo then
        if cdInfo.isOnGCD then return true end
        if cdInfo.isActive then return false end
    end

    return true
end

--- Drive an icon's sweep for "always" mode. start/duration are passed straight
--- to SetCooldown without ever being compared here -- handing secret values to
--- Blizzard's own API is fine, inspecting them is not.
local function ApplySweep(icon, spellName)
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellName)
    if ok and cdInfo and cdInfo.isActive and not cdInfo.isOnGCD then
        icon.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration, cdInfo.modRate)
    else
        icon.cooldown:Clear()
    end
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
        -- Resolved by ID (which works for any spell in the game) and cached, so
        -- the per-frame path can query by name. Rebuild re-runs on
        -- SPELLS_CHANGED / PLAYER_TALENT_UPDATE, so this stays current.
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(placement.spellID)
        icon.spellName = spellInfo and spellInfo.name
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
        local spellName = icon.spellName
        local show = false

        if not IsSpellAvailable(spellName) then
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
            local ready, charges = IsSpellReady(spellName)

            if icon.mode == "always" then
                show = true
                ApplySweep(icon, spellName)
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

--- @param forceCombat boolean? treat combat as this instead of asking
function CV:ShouldShow(forceCombat)
    if self:IsLegacyMode() then return false end
    if self.previewMode then return true end

    local profile = CV:CurrentProfile()
    if not profile.enabled then return false end
    if next(profile.placements) == nil then return false end

    local inCombat = forceCombat
    if inCombat == nil then inCombat = InCombat() end
    if profile.onlyInCombat and not inCombat then return false end
    return true
end

--- @param forceCombat boolean? passed through to ShouldShow. PLAYER_REGEN_*
--- supplies it because InCombatLockdown() is not guaranteed to have flipped
--- yet while that event is being handled -- the same reason
--- ER:UpdateVisibility is called as UpdateVisibility(true) from its own
--- PLAYER_REGEN_DISABLED handler.
function CV:UpdateVisibility(forceCombat)
    local f = self.container
    if not f then return end

    if not self:ShouldShow(forceCombat) then
        f:Hide()
        self.anchoredToCursor = nil
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

    local inCombat = forceCombat
    if inCombat == nil then inCombat = InCombat() end

    -- Only re-anchor on a transition. This runs on a timer now, and
    -- re-issuing ReleaseAnchor every tick would ClearAllPoints out from under
    -- a drag in progress.
    local wantCursor = profile.followCursor and (self.previewMode or inCombat)
    if wantCursor then
        self:UpdateCursorPosition()
        self.anchoredToCursor = true
    elseif self.anchoredToCursor ~= false then
        self:ReleaseAnchor()
        self.anchoredToCursor = false
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
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= UPDATE_INTERVAL then
        elapsedSinceUpdate = 0

        -- Visibility is re-evaluated here unconditionally, and deliberately
        -- BEFORE the IsShown bail-out below. Driving it from PLAYER_REGEN_*
        -- alone means a single missed or mistimed transition leaves the viewer
        -- hidden for the rest of the fight, with nothing able to bring it back:
        -- UpdateState and the cursor path both bail while it is hidden, so the
        -- hidden state becomes self-sustaining. A poll makes wrong states last
        -- 150ms instead of forever.
        if not CV:IsLegacyMode() then
            CV:UpdateVisibility()
            CV:UpdateState()
        end
    end

    if not CV.container or not CV.container:IsShown() then return end

    -- Cursor tracking stays per-frame; anything slower visibly lags the mouse.
    local profile = CV:CurrentProfile()
    if profile.followCursor and (CV.previewMode or InCombat()) then
        CV:UpdateCursorPosition()
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
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Retry migration for the spec just switched TO. The ECV list is
            -- spell names, and names only resolve for a spec you are actually
            -- in -- which is why the original one-shot pass silently produced
            -- an empty Restoration bar when it happened to run as Guardian.
            Data.MigrateSpec(Data.GetActiveSpecID())
            if CV.Page then
                CV.Page.editSpecID = nil
                CV.Page.selectedKey = nil
            end
        end
        CV:Rebuild()
        if ThugUI.Window then ThugUI.Window:RefreshActivePage() end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- Forced rather than derived: InCombatLockdown() is not reliably
        -- flipped yet while this event is being handled, and guessing wrong
        -- here used to strand the viewer hidden for a whole fight.
        CV:UpdateVisibility(event == "PLAYER_REGEN_DISABLED")
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

    -- Pull the current spec's old ECV/BCV/GCV bar onto the grid. "import force"
    -- overwrites a layout that already has icons; plain "import" refuses, so a
    -- fat-fingered command cannot wipe a grid you spent time on.
    if msg == "import" or msg == "import force" then
        local force = (msg == "import force")
        local specID = Data.GetActiveSpecID()
        local profile = Data.GetProfile(specID)

        if next(profile.placements) and not force then
            print("|cff00ff00ThugUI:|r " .. Data.GetSpecName(specID)
                .. " already has a layout. |cffffd100/thugcv import force|r to replace it.")
            return
        end

        if Data.MigrateSpec(specID, true) then
            CV:Rebuild()
            if ThugUI.Window then ThugUI.Window:RefreshActivePage() end
            print("|cff00ff00ThugUI:|r imported the old bar for "
                .. Data.GetSpecName(specID) .. ".")
        else
            print("|cff00ff00ThugUI:|r no old bar exists for "
                .. Data.GetSpecName(specID) .. " (only Balance, Guardian and "
                .. "Restoration ever had one).")
        end
        return
    end

    if msg == "rebuild" then
        CV:Rebuild()
        print("|cff00ff00ThugUI:|r cooldown viewer rebuilt.")
        return
    end

    -- Every reason the viewer can decline to draw, in the order ShouldShow
    -- checks them. "It works in preview but not in combat" has half a dozen
    -- possible causes and no visible difference between them; this prints
    -- which one is actually firing.
    if msg == "status" then
        local specID = Data.GetActiveSpecID()
        local profile = Data.GetActiveProfile()
        local placed = 0
        for _ in pairs(profile.placements) do placed = placed + 1 end

        local function YesNo(value, goodIsTrue)
            local good = goodIsTrue and value or not value
            return (good and "|cff40ff40" or "|cffff4040") .. tostring(value and "yes" or "no") .. "|r"
        end

        print("|cff00ffccThugUI cooldown viewer|r")
        print(("  spec: %s (%s)"):format(Data.GetSpecName(specID), tostring(specID)))
        if not specID then
            print("  |cffff4040No spec ID — edits are not being saved. Relog.|r")
        end
        print("  legacy mode:      " .. YesNo(CV:IsLegacyMode(), false))
        print("  enabled:          " .. YesNo(profile.enabled, true))
        print("  icons placed:     " .. (placed > 0
            and ("|cff40ff40" .. placed .. "|r")
            or "|cffff40400|r"))
        print("  only in combat:   " .. tostring(profile.onlyInCombat)
            .. "   in combat now: " .. YesNo(InCombat(), true))
        print("  follow cursor:    " .. tostring(profile.followCursor))
        print("  preview forced:   " .. tostring(CV.previewMode))
        print("  collapse:         " .. tostring(profile.collapse)
            .. " (" .. Data.ResolveCollapseDirection(profile) .. ")")
        print("  |cffffd100would draw right now: " .. YesNo(CV:ShouldShow(), true) .. "|r")

        if not profile.enabled then
            print("  |cffffd100-> 'Enabled' is off for this spec. Tick it on the "
                .. "Cooldown Viewer page; preview ignores it, combat does not.|r")
        end

        local unknown = {}
        for _, placement in pairs(profile.placements) do
            local info = C_Spell.GetSpellInfo(placement.spellID)
            if not IsSpellAvailable(info and info.name) then
                table.insert(unknown, (info and info.name or placement.spellID))
            end
        end
        if #unknown > 0 then
            print(("  |cffffd100-> %d placed spell(s) do not resolve in this spec and will "
                .. "never draw: %s|r"):format(#unknown, table.concat(unknown, ", ")))
        end
        print("  container shown: " .. tostring(CV.container and CV.container:IsShown()))
        return
    end

    ThugUI:ToggleOptions("cooldownviewer")
end

return CV
