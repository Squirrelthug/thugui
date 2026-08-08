-- ============================================================================
-- ThugUI: Cooldown Viewer -- data layer
--
-- Owns everything about a cooldown-viewer layout that is not a frame: the
-- per-spec profiles, the 10x10 grid model, and the spell catalogue the picker
-- reads from.
--
-- WHY PER-SPEC PROFILES
--
-- The original bars (ECV/BCV/GCV) were three near-identical code paths with
-- flat `ecv*`/`bcv*`/`gcv*` config keys and hardcoded `IsRestoSpec()` gates.
-- That does not survive contact with 40 specs. A profile here is keyed by
-- specID -- the globally unique number from GetSpecializationInfo, not the
-- 1-4 spec index, which repeats across classes -- so every spec on every alt
-- gets its own independent layout with no new code.
--
-- THE GRID
--
-- A layout is a 10x10 grid of cells. Icons occupy cells; the grid itself is
-- invisible at runtime. The cursor attaches to one of the 11x11 *intersections*
-- of the grid lines (anchorCol/anchorRow, both 0-based), which is what lets a
-- player build an arbitrary shape and then decide which part of it the cursor
-- sits on.
-- ============================================================================

ThugUI = ThugUI or {}
ThugUI_Config = ThugUI_Config or {}

ThugUI.CooldownViewer = ThugUI.CooldownViewer or {}
local CV = ThugUI.CooldownViewer

local Data = {}
CV.Data = Data

Data.GRID_COLS = 10
Data.GRID_ROWS = 10

-- How a placed icon decides whether to draw.
--   cooldown -- visible while the spell is READY, hidden while on cooldown.
--               This is the "use it now" signal the original bars were built
--               around and stays the default.
--   always   -- always visible, with a cooldown sweep over it.
--   aura     -- visible only while its buff is on the player (procs).
Data.MODES = {
    { value = "cooldown", text = "Show when ready" },
    { value = "always",   text = "Always show (with sweep)" },
    { value = "aura",     text = "Show while buff active" },
}

-- What happens to the hole when an icon goes on cooldown.
--   none -- the gap stays; every icon keeps the cell it was placed in.
--   rows -- each row compacts horizontally on its own. Rows keep their row,
--           so an icon never changes height and muscle memory survives.
--
-- Rows pack from the row's own outermost placed column rather than from the
-- grid edge, so a row at full strength sits exactly where the editor drew it.
-- Within a row the whole thing is treated as ONE run: a deliberate horizontal
-- gap between two clusters does not survive a collapse. That is a chosen
-- trade -- it keeps the rule "a row is never gappy" simple and total.
Data.COLLAPSE_MODES = {
    { value = "none", text = "Leave the gap" },
    { value = "rows", text = "Rows collapse sideways" },
}

Data.COLLAPSE_DIRECTIONS = {
    { value = "auto",  text = "Auto (from anchor)" },
    { value = "left",  text = "Always left" },
    { value = "right", text = "Always right" },
}

--- "left" or "right" -- the direction rows pack toward.
function Data.ResolveCollapseDirection(profile)
    local direction = profile.collapseDirection or "auto"
    if direction == "left" or direction == "right" then return direction end

    -- An anchor right of centre means the shape hangs to the LEFT of the
    -- cursor, so its icons should pack rightwards, towards the cursor. Dead
    -- centre is genuinely ambiguous; it falls to "left" and the explicit
    -- override exists for exactly that case.
    return (profile.anchorCol or 0) > Data.GRID_COLS / 2 and "right" or "left"
end

function Data.ModeText(mode)
    for _, m in ipairs(Data.MODES) do
        if m.value == mode then return m.text end
    end
    return mode or "?"
end

-- ----------------------------------------------------------------------------
-- Grid helpers
-- ----------------------------------------------------------------------------

function Data.CellKey(row, col)
    return row .. ":" .. col
end

function Data.ParseCellKey(key)
    local row, col = key:match("^(%d+):(%d+)$")
    return tonumber(row), tonumber(col)
end

-- ----------------------------------------------------------------------------
-- Spec identity
-- ----------------------------------------------------------------------------

--- specID of the player's active spec, or nil before spec data has loaded.
function Data.GetActiveSpecID()
    if not GetSpecialization then return nil end
    local index = GetSpecialization()
    if not index then return nil end
    local specID = GetSpecializationInfo(index)
    return specID
end

--- Every spec of the player's class: { {specID=, name=, icon=, index=}, ... }
function Data.GetPlayerSpecs()
    local specs = {}
    if not GetNumSpecializations then return specs end

    for index = 1, GetNumSpecializations() do
        local specID, name, _, icon = GetSpecializationInfo(index)
        if specID then
            table.insert(specs, { specID = specID, name = name, icon = icon, index = index })
        end
    end
    return specs
end

function Data.GetSpecName(specID)
    if not specID then return "Unknown" end
    if GetSpecializationInfoByID then
        local _, name = GetSpecializationInfoByID(specID)
        if name then return name end
    end
    return "Spec " .. specID
end

-- ----------------------------------------------------------------------------
-- Profiles
-- ----------------------------------------------------------------------------

local function DefaultProfile()
    return {
        enabled = false,
        onlyInCombat = true,
        followCursor = true,
        iconSize = 32,
        padding = 4,
        scale = 1.0,
        collapse = "rows",
        collapseDirection = "auto",
        -- Top-left intersection: the shape hangs down and to the right of the
        -- cursor, which is where the old bars sat by default.
        anchorCol = 0,
        anchorRow = 0,
        point = nil,
        placements = {},
    }
end

Data.DefaultProfile = DefaultProfile

local function Store()
    ThugUI_Config.cv = ThugUI_Config.cv or {}
    ThugUI_Config.cv.profiles = ThugUI_Config.cv.profiles or {}
    return ThugUI_Config.cv
end

--- The profile for a spec, created on demand. Never returns nil.
function Data.GetProfile(specID)
    specID = specID or Data.GetActiveSpecID()
    if not specID then return DefaultProfile() end

    local store = Store()
    local profile = store.profiles[specID]
    if not profile then
        profile = DefaultProfile()
        store.profiles[specID] = profile
    else
        -- Fill in keys added by a later version without clobbering the player's.
        for k, v in pairs(DefaultProfile()) do
            if profile[k] == nil then profile[k] = v end
        end
        profile.placements = profile.placements or {}
    end
    return profile
end

function Data.GetActiveProfile()
    return Data.GetProfile(Data.GetActiveSpecID())
end

function Data.ResetProfile(specID)
    specID = specID or Data.GetActiveSpecID()
    if not specID then return end
    Store().profiles[specID] = DefaultProfile()
end

--- Placed icons as a sorted list, reading order (top row first, then left to
--- right) so the editor and the runtime agree on ordering.
function Data.GetPlacements(profile)
    local list = {}
    for key, placement in pairs(profile.placements) do
        local row, col = Data.ParseCellKey(key)
        if row and col and placement and placement.spellID then
            table.insert(list, {
                row = row, col = col, key = key,
                spellID = placement.spellID,
                mode = placement.mode or "cooldown",
            })
        end
    end
    table.sort(list, function(a, b)
        if a.row == b.row then return a.col < b.col end
        return a.row < b.row
    end)
    return list
end

function Data.GetPlacement(profile, row, col)
    return profile.placements[Data.CellKey(row, col)]
end

function Data.SetPlacement(profile, row, col, spellID, mode)
    if row < 1 or row > Data.GRID_ROWS or col < 1 or col > Data.GRID_COLS then return end
    profile.placements[Data.CellKey(row, col)] = spellID
        and { spellID = spellID, mode = mode or "cooldown" }
        or nil
end

function Data.ClearPlacement(profile, row, col)
    profile.placements[Data.CellKey(row, col)] = nil
end

function Data.MovePlacement(profile, fromRow, fromCol, toRow, toCol)
    local from = Data.CellKey(fromRow, fromCol)
    local to = Data.CellKey(toRow, toCol)
    if from == to then return end
    profile.placements[to], profile.placements[from] = profile.placements[from], profile.placements[to]
end

function Data.IsSpellPlaced(profile, spellID)
    for _, placement in pairs(profile.placements) do
        if placement.spellID == spellID then return true end
    end
    return false
end

--- First free cell in reading order, so click-to-place has somewhere to go.
function Data.FindFreeCell(profile)
    for row = 1, Data.GRID_ROWS do
        for col = 1, Data.GRID_COLS do
            if not profile.placements[Data.CellKey(row, col)] then
                return row, col
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Spell catalogue
--
-- Blizzard's Cooldown Manager already curates "the cooldowns that matter" per
-- spec, so it is the primary source -- it is the same set the default Cooldown
-- Viewer shows, which is exactly the list a player expects to pick from. The
-- spellbook is the fallback and the catch-all for anything Blizzard did not
-- categorise.
-- ----------------------------------------------------------------------------

Data.SOURCES = {
    { value = "essential",  text = "Essential cooldowns" },
    { value = "utility",    text = "Utility cooldowns" },
    { value = "buffs",      text = "Tracked buffs" },
    { value = "spellbook",  text = "Spellbook (all)" },
    { value = "all",        text = "Everything" },
}

local CATEGORY_BY_SOURCE = {
    essential = "Essential",
    utility   = "Utility",
    buffs     = "TrackedBuff",
}

--- Spell IDs from one Cooldown Manager category. Returns an empty list on any
--- client where C_CooldownViewer is missing or the enum has been renamed.
local function CooldownViewerSpellIDs(categoryName)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return {}
    end
    local category = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
    if category == nil then return {} end

    local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
    if not ok or type(cooldownIDs) ~= "table" then return {} end

    local spellIDs = {}
    for _, cooldownID in ipairs(cooldownIDs) do
        local infoOK, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if infoOK and info then
            -- overrideSpellID is what the player actually casts once a talent
            -- replaces the base spell; prefer it so the icon matches the bar.
            local spellID = info.overrideSpellID or info.spellID
            if spellID then table.insert(spellIDs, spellID) end
        end
    end
    return spellIDs
end

--- Every active, non-passive spell in the player's spellbook.
local function SpellbookSpellIDs()
    local spellIDs = {}
    if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then return spellIDs end

    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0

    for line = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if lineInfo and lineInfo.itemIndexOffset and lineInfo.numSpellBookItems then
            for i = 1, lineInfo.numSpellBookItems do
                local slot = lineInfo.itemIndexOffset + i
                local ok, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                if ok and itemInfo
                    and not itemInfo.isPassive
                    and not itemInfo.isOffSpec
                    and itemInfo.spellID
                then
                    table.insert(spellIDs, itemInfo.spellID)
                end
            end
        end
    end
    return spellIDs
end

local function SpellEntry(spellID)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local name = info and info.name
    local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
        or (info and info.iconID)
    if not name or not icon then return nil end
    return { spellID = spellID, name = name, icon = icon }
end

--- The picker list for a source, de-duplicated, name-filtered, alphabetised.
--- @param source string one of Data.SOURCES values
--- @param search string? case-insensitive substring filter
function Data.BuildSpellList(source, search)
    local ids = {}

    local function collect(list)
        for _, id in ipairs(list) do table.insert(ids, id) end
    end

    if source == "spellbook" then
        collect(SpellbookSpellIDs())
    elseif source == "all" then
        for _, categoryName in pairs(CATEGORY_BY_SOURCE) do
            collect(CooldownViewerSpellIDs(categoryName))
        end
        collect(SpellbookSpellIDs())
    else
        local categoryName = CATEGORY_BY_SOURCE[source]
        if categoryName then collect(CooldownViewerSpellIDs(categoryName)) end
        -- A spec Blizzard has not categorised would otherwise show an empty
        -- picker with no hint that another source would work.
        if #ids == 0 then collect(SpellbookSpellIDs()) end
    end

    if search and search ~= "" then search = search:lower() else search = nil end

    local seen, entries = {}, {}
    for _, id in ipairs(ids) do
        if not seen[id] then
            seen[id] = true
            local entry = SpellEntry(id)
            if entry and (not search or entry.name:lower():find(search, 1, true)) then
                table.insert(entries, entry)
            end
        end
    end

    table.sort(entries, function(a, b) return a.name < b.name end)
    return entries
end

--- Resolve a player-typed spell name or ID for the "add manually" box.
function Data.ResolveSpell(query)
    local spellID = tonumber(query)
    if not spellID then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(query)
        spellID = info and info.spellID
    end
    if not spellID then return nil end
    return SpellEntry(spellID)
end

-- ----------------------------------------------------------------------------
-- Migration from the ECV/BCV/GCV era
--
-- Runs once. The three druid bars become row-1 placements in their spec's
-- profile, with the old anchorCorner translated to the equivalent grid
-- intersection, so an existing druid keeps the layout they already had.
-- The legacy config keys are left untouched -- the old bars remain available
-- via ThugUI_Config.cvUseLegacy if anything here goes wrong.
-- ----------------------------------------------------------------------------

local DRUID_SPEC_IDS = {
    balance     = 102,
    feral       = 103,
    guardian    = 104,
    restoration = 105,
}

--- Old bars anchored a bar CORNER to the cursor; the grid anchors an
--- intersection. With icons laid along row 1 in columns 1..count, the same
--- four corners are these intersections.
local function CornerToIntersection(corner, count)
    if corner == "TOPRIGHT" then return count, 0 end
    if corner == "BOTTOMLEFT" then return 0, 1 end
    if corner == "BOTTOMRIGHT" then return count, 1 end
    return 0, 0  -- TOPLEFT
end

local function MigrateBar(specID, spellIDs, legacy)
    if #spellIDs == 0 then return end

    local profile = Data.GetProfile(specID)
    if next(profile.placements) then return end  -- already laid out; leave it

    for i, spellID in ipairs(spellIDs) do
        if i <= Data.GRID_COLS then
            Data.SetPlacement(profile, 1, i, spellID, legacy.modes and legacy.modes[i] or "cooldown")
        end
    end

    profile.enabled      = legacy.show and true or false
    profile.onlyInCombat = legacy.onlyInCombat and true or false
    profile.followCursor = legacy.follow and true or false
    profile.scale        = legacy.scale or 1.0
    profile.point        = legacy.point
    profile.anchorCol, profile.anchorRow =
        CornerToIntersection(legacy.corner, math.min(#spellIDs, Data.GRID_COLS))
end

function Data.MigrateLegacyBars()
    local store = Store()
    if store.migrated then return end
    store.migrated = true

    local cfg = ThugUI_Config
    local ER = ThugUI.EssentialRings
    if not ER then return end

    -- Restoration: the ECV list is spell NAMES, resolved to IDs here.
    local ecvIDs = {}
    for _, name in ipairs(ER.ecvSpellNames or {}) do
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
        if info and info.spellID then table.insert(ecvIDs, info.spellID) end
    end
    MigrateBar(DRUID_SPEC_IDS.restoration, ecvIDs, {
        show = cfg.showECV, onlyInCombat = cfg.ecvShowOnlyInCombat,
        follow = cfg.anchorECVToCursor, scale = cfg.ecvScale,
        corner = cfg.ecvAnchorCorner, point = cfg.ecvPoint,
    })

    -- Balance and Guardian carry spell DEFS, which already hold IDs and modes.
    local function IDsAndModes(defs)
        local ids, modes = {}, {}
        for _, def in ipairs(defs or {}) do
            local id = def.spellID
            if id then
                table.insert(ids, id)
                -- The old "buff" mode is this module's "aura" mode.
                table.insert(modes, def.mode == "buff" and "aura" or "cooldown")
            end
        end
        return ids, modes
    end

    local bcvIDs, bcvModes = IDsAndModes(ER.bcvSpellDefs)
    MigrateBar(DRUID_SPEC_IDS.balance, bcvIDs, {
        show = cfg.showBCV, onlyInCombat = cfg.bcvShowOnlyInCombat,
        follow = cfg.anchorBCVToCursor, scale = cfg.bcvScale,
        corner = cfg.bcvAnchorCorner, point = cfg.bcvPoint, modes = bcvModes,
    })

    local gcvIDs, gcvModes = IDsAndModes(ER.gcvSpellDefs)
    MigrateBar(DRUID_SPEC_IDS.guardian, gcvIDs, {
        show = cfg.showGCV, onlyInCombat = cfg.gcvShowOnlyInCombat,
        follow = cfg.anchorGCVToCursor, scale = cfg.gcvScale,
        corner = cfg.gcvAnchorCorner, point = cfg.gcvPoint, modes = gcvModes,
    })
end

return Data
