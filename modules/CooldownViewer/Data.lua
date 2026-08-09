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
--   proc     -- visible only when the spell is BOTH off cooldown and lit up by
--               a proc. Narrower than "cooldown": a spell that is merely usable
--               stays hidden until something actually makes it worth pressing,
--               e.g. Pistol Shot only once Opportunity is up.
Data.MODES = {
    { value = "cooldown", text = "Show when ready" },
    { value = "proc",     text = "Show when ready and procced" },
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
--   columns -- each column compacts vertically on its own, and a column left
--              with nothing live vacates entirely: the remaining columns then
--              close horizontally into the gap. Two stages, where rows has
--              one. This is the shape to pick when a layout is built up or
--              down rather than across.
--   both    -- a row pass followed by a column pass, so the shape closes on
--              both axes and keeps the tightest footprint it can. Not a
--              globally minimal repack: each group still packs within its own
--              span, so an icon never teleports across the shape.
Data.COLLAPSE_MODES = {
    { value = "none",    text = "Leave the gap" },
    { value = "rows",    text = "Rows collapse sideways" },
    { value = "columns", text = "Columns collapse vertically" },
    { value = "both",    text = "Both — keep the smallest shape" },
}

-- Direction is per-axis: a row can only pack left or right, a column only up
-- or down. Offering all four in one list would let you pick a direction that
-- silently does nothing, so the menu is built from the mode.
local COLLAPSE_DIRECTIONS = {
    rows = {
        { value = "auto",  text = "Auto (from anchor)" },
        { value = "left",  text = "Always left" },
        { value = "right", text = "Always right" },
    },
    columns = {
        { value = "auto", text = "Auto (from anchor)" },
        { value = "up",   text = "Always up" },
        { value = "down", text = "Always down" },
    },
    -- Collapsing on both axes needs a corner, not an edge.
    both = {
        { value = "auto",        text = "Auto (from anchor)" },
        { value = "topleft",     text = "Toward top-left" },
        { value = "topright",    text = "Toward top-right" },
        { value = "bottomleft",  text = "Toward bottom-left" },
        { value = "bottomright", text = "Toward bottom-right" },
    },
}

function Data.GetCollapseDirections(mode)
    return COLLAPSE_DIRECTIONS[mode] or COLLAPSE_DIRECTIONS.rows
end

--- Is this direction meaningful for this collapse mode?
function Data.IsDirectionValid(mode, direction)
    if direction == "auto" then return true end
    for _, option in ipairs(Data.GetCollapseDirections(mode)) do
        if option.value == direction then return true end
    end
    return false
end

--- The axis direction icons pack toward: "left"/"right" in rows mode,
--- "up"/"down" in columns mode.
---
--- Auto reads the anchor. An anchor right of centre means the shape hangs to
--- the LEFT of the cursor, so its icons pack rightwards, towards the cursor;
--- an anchor low on the grid means the shape hangs ABOVE the cursor, so its
--- icons pack downwards. Dead centre is genuinely ambiguous and falls to the
--- first option, which is what the explicit override is for.
function Data.ResolveCollapseDirection(profile)
    local mode = profile.collapse or "none"
    local direction = profile.collapseDirection or "auto"

    if mode == "columns" then
        if direction == "up" or direction == "down" then return direction end
        return (profile.anchorRow or 0) > Data.GRID_ROWS / 2 and "down" or "up"
    end

    if direction == "left" or direction == "right" then return direction end
    return (profile.anchorCol or 0) > Data.GRID_COLS / 2 and "right" or "left"
end

--- Both axes at once, as booleans the layout code consumes directly.
--- @return packRight boolean, packDown boolean
---
--- Every mode needs both: even single-axis modes use the other axis for their
--- vacate stage (an emptied row has to close *somewhere*). Only the axis the
--- player actually chose is configurable; the other is always derived from the
--- anchor, because it is the second half of one behaviour rather than a
--- separate decision.
function Data.ResolveCollapseAxes(profile)
    local mode = profile.collapse or "none"
    local direction = profile.collapseDirection or "auto"

    local autoRight = (profile.anchorCol or 0) > Data.GRID_COLS / 2
    local autoDown  = (profile.anchorRow or 0) > Data.GRID_ROWS / 2

    if mode == "both" then
        if direction == "topleft"     then return false, false end
        if direction == "topright"    then return true,  false end
        if direction == "bottomleft"  then return false, true  end
        if direction == "bottomright" then return true,  true  end
        return autoRight, autoDown
    end

    if mode == "columns" then
        local down = autoDown
        if direction == "up" then down = false
        elseif direction == "down" then down = true end
        return autoRight, down
    end

    local right = autoRight
    if direction == "left" then right = false
    elseif direction == "right" then right = true end
    return right, autoDown
end

--- Human-readable summary of where a mode packs, for the settings note.
function Data.DescribeCollapse(profile)
    local packRight, packDown = Data.ResolveCollapseAxes(profile)
    return packRight and "right" or "left", packDown and "down" or "up"
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
        showProcGlow = true,
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
---
--- A missing or zero specID means spec data has not loaded yet. That gets a
--- detached scratch profile which is deliberately NOT stored: persisting it
--- writes a junk `[0]` profile that collects edits nobody ever sees again.
function Data.GetProfile(specID)
    specID = specID or Data.GetActiveSpecID()
    if not specID or specID == 0 then return DefaultProfile() end

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

-- TrackedBuff and TrackedBar are ONE pool from the player's side: the same
-- tracked spells, shown either as a row of icons or a stack of timer bars.
-- They are emphatically not the same DATA, though, and reading only
-- TrackedBuff loses entries outright.
--
-- Roll the Bones is the proof. It appears twice on an Outlaw rogue:
--   Essential   cooldownID 11860, linkedSpellIDs = {}
--   TrackedBar  cooldownID 42743, linkedSpellIDs = One of a Kind, Double
--                                  Trouble, Triple Threat, Jackpot
-- Only the TrackedBar entry knows which buffs the spell can grant, so with
-- TrackedBar unread the outcome buffs were unreachable no matter what the
-- player picked.
local CATEGORIES_BY_SOURCE = {
    essential = { "Essential" },
    utility   = { "Utility" },
    buffs     = { "TrackedBuff", "TrackedBar" },
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
            local spellID = Data.PickerSpellIDFor(info)
            if spellID then table.insert(spellIDs, spellID) end
        end
    end
    return spellIDs
end

--- The spell ID a Cooldown Manager entry should appear under in the picker.
---
--- overrideSpellID first, so a talent that replaces a base spell shows the icon
--- the player actually casts. The linked fallback matters for entries that
--- have NO base spell of their own: Roll the Bones is tracked as its set of
--- possible buffs, so `spellID` is nil and taking only override-or-base
--- dropped it from the list entirely.
function Data.PickerSpellIDFor(info)
    if not info then return nil end
    return info.overrideSpellID
        or info.spellID
        or info.overrideTooltipSpellID
        or (info.linkedSpellIDs and info.linkedSpellIDs[1])
end

-- Cooldown Manager entries, indexed by every spell ID that can stand for them.
-- Rebuilt on demand because talents change what is in each category.
local cooldownInfoCache, cooldownInfoCacheSpec

--- Which of two entries sharing a spell ID should own it.
---
--- The same spell can appear in more than one category, and only one of those
--- entries may know about the buffs it can grant -- Roll the Bones is listed
--- under Essential with no linked spells AND under TrackedBar with all four
--- outcomes. Keeping whichever was scanned first meant the empty one won and
--- the buffs were unreachable. Prefer the entry that actually carries linked
--- spells, then one that has an aura at all.
local function Preferred(existing, candidate)
    if not existing then return candidate end

    local have = existing.linkedSpellIDs and #existing.linkedSpellIDs or 0
    local want = candidate.linkedSpellIDs and #candidate.linkedSpellIDs or 0
    if want ~= have then
        return want > have and candidate or existing
    end

    if candidate.hasAura and not existing.hasAura then return candidate end
    return existing
end

local function BuildCooldownInfoCache()
    local cache = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return cache
    end

    for _, categoryName in ipairs({ "Essential", "Utility", "TrackedBuff", "TrackedBar" }) do
        local category = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
        if category ~= nil then
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
            if ok and type(ids) == "table" then
                for _, cooldownID in ipairs(ids) do
                    local infoOK, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if infoOK and info then
                        -- Indexed under every ID that could name this entry, so
                        -- a placement made from any of them finds it again.
                        local ids = {
                            info.spellID, info.overrideSpellID, info.overrideTooltipSpellID,
                        }
                        for _, id in ipairs(info.linkedSpellIDs or {}) do
                            table.insert(ids, id)
                        end

                        for _, id in ipairs(ids) do
                            if id then
                                cache[id] = Preferred(cache[id], info)
                            end
                        end
                    end
                end
            end
        end
    end
    return cache
end

--- The Cooldown Manager entry a placed spell belongs to, or nil.
--- This is where linkedSpellIDs comes from -- the set of buffs a single
--- tracked entry can show, e.g. the six Roll the Bones outcomes.
function Data.GetCooldownInfoForSpell(spellID)
    if not spellID then return nil end

    local specID = Data.GetActiveSpecID()
    if not cooldownInfoCache or cooldownInfoCacheSpec ~= specID then
        cooldownInfoCache = BuildCooldownInfoCache()
        cooldownInfoCacheSpec = specID

        -- Recorded because the entry count is direct evidence that the
        -- Cooldown Manager was readable at all -- a zero here explains an
        -- empty picker without anyone having to reproduce it.
        local count = 0
        for _ in pairs(cooldownInfoCache) do count = count + 1 end
        if ThugUI.Diagnostics then
            ThugUI.Diagnostics:Log("CV", "cooldown cache built for %s: %d indexed spell ids",
                Data.GetSpecName(specID), count)
        end
    end
    return cooldownInfoCache[spellID]
end

function Data.InvalidateCooldownInfoCache()
    cooldownInfoCache, cooldownInfoCacheSpec = nil, nil
end

--- Everything the Cooldown Manager reports for this spec, for /thugcv probe.
function Data.DumpCooldownViewer()
    local dump = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return dump
    end

    for _, categoryName in ipairs({ "Essential", "Utility", "TrackedBuff", "TrackedBar" }) do
        local category = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
        if category ~= nil then
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
            if ok and type(ids) == "table" then
                for _, cooldownID in ipairs(ids) do
                    local infoOK, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if infoOK and info then
                        local names = {}
                        for _, id in ipairs(info.linkedSpellIDs or {}) do
                            local spellInfo = C_Spell.GetSpellInfo(id)
                            table.insert(names, id .. "=" .. ((spellInfo and spellInfo.name) or "?"))
                        end
                        local baseInfo = info.spellID and C_Spell.GetSpellInfo(info.spellID)
                        table.insert(dump, {
                            category = categoryName,
                            cooldownID = cooldownID,
                            spellID = info.spellID,
                            name = baseInfo and baseInfo.name,
                            overrideSpellID = info.overrideSpellID,
                            overrideTooltipSpellID = info.overrideTooltipSpellID,
                            hasAura = info.hasAura,
                            selfAura = info.selfAura,
                            charges = info.charges,
                            isKnown = info.isKnown,
                            linkedSpellIDs = table.concat(names, ", "),
                        })
                    end
                end
            end
        end
    end
    return dump
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
        for _, categoryNames in pairs(CATEGORIES_BY_SOURCE) do
            for _, categoryName in ipairs(categoryNames) do
                collect(CooldownViewerSpellIDs(categoryName))
            end
        end
        collect(SpellbookSpellIDs())
    else
        for _, categoryName in ipairs(CATEGORIES_BY_SOURCE[source] or {}) do
            collect(CooldownViewerSpellIDs(categoryName))
        end
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

local function MigrateBar(specID, spellIDs, legacy, force)
    if #spellIDs == 0 then return false end

    local profile = Data.GetProfile(specID)
    if next(profile.placements) and not force then
        return false  -- already laid out; leave it alone
    end
    wipe(profile.placements)

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

    return true
end

-- The ECV stores spell NAMES, not IDs. C_Spell.GetSpellInfo resolves a name
-- only for a spell the player currently HAS -- which is the whole point when
-- following talent overrides, but means the Restoration list resolves to
-- nothing at all unless you are actually in Restoration spec at the time.
--
-- The original one-shot migration ran once, on whatever spec happened to be
-- active, and set a global "migrated" flag. Log in as Guardian and the
-- Restoration bar silently migrated to an empty list and was never retried.
-- Hence the ID fallback below, and the per-spec retry in MigrateSpec.
local ECV_FALLBACK_IDS = {
    ["Wild Growth"]          = 48438,
    ["Swiftmend"]            = 18562,
    ["Nature's Swiftness"]   = 132158,
    ["Ironbark"]             = 102342,
    ["Convoke the Spirits"]  = 391528,
    ["Tranquility"]          = 740,
}

local function ResolveECVSpellIDs(ER)
    local ids = {}
    for _, name in ipairs(ER.ecvSpellNames or {}) do
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
        local id = (info and info.spellID) or ECV_FALLBACK_IDS[name]
        if id then table.insert(ids, id) end
    end
    return ids
end

--- Legacy bar definition for one spec, or nil if that spec never had one.
local function LegacyBarFor(specID)
    local cfg = ThugUI_Config
    local ER = ThugUI.EssentialRings
    if not ER then return nil end

    -- Balance and Guardian carry spell DEFS, which already hold IDs and modes.
    local function IDsAndModes(defs)
        local ids, modes = {}, {}
        for _, def in ipairs(defs or {}) do
            if def.spellID then
                table.insert(ids, def.spellID)
                -- The old "buff" mode is this module's "aura" mode.
                table.insert(modes, def.mode == "buff" and "aura" or "cooldown")
            end
        end
        return ids, modes
    end

    if specID == DRUID_SPEC_IDS.restoration then
        return ResolveECVSpellIDs(ER), {
            show = cfg.showECV, onlyInCombat = cfg.ecvShowOnlyInCombat,
            follow = cfg.anchorECVToCursor, scale = cfg.ecvScale,
            corner = cfg.ecvAnchorCorner, point = cfg.ecvPoint,
        }
    end

    if specID == DRUID_SPEC_IDS.balance then
        local ids, modes = IDsAndModes(ER.bcvSpellDefs)
        return ids, {
            show = cfg.showBCV, onlyInCombat = cfg.bcvShowOnlyInCombat,
            follow = cfg.anchorBCVToCursor, scale = cfg.bcvScale,
            corner = cfg.bcvAnchorCorner, point = cfg.bcvPoint, modes = modes,
        }
    end

    if specID == DRUID_SPEC_IDS.guardian then
        local ids, modes = IDsAndModes(ER.gcvSpellDefs)
        return ids, {
            show = cfg.showGCV, onlyInCombat = cfg.gcvShowOnlyInCombat,
            follow = cfg.anchorGCVToCursor, scale = cfg.gcvScale,
            corner = cfg.gcvAnchorCorner, point = cfg.gcvPoint, modes = modes,
        }
    end

    return nil
end

--- Import one spec's legacy bar into its grid profile.
--- @param force boolean? overwrite a profile that already has icons
--- @return boolean whether anything was written
function Data.MigrateSpec(specID, force)
    if not specID or specID == 0 then return false end

    local store = Store()
    store.migratedSpecs = store.migratedSpecs or {}
    if store.migratedSpecs[specID] and not force then return false end

    local spellIDs, legacy = LegacyBarFor(specID)
    if not spellIDs then
        store.migratedSpecs[specID] = true  -- no legacy bar; never ask again
        return false
    end

    local wrote = MigrateBar(specID, spellIDs, legacy, force)
    -- Only marked done once something was actually written, so a spec whose
    -- spells could not be resolved yet gets another go next login.
    if wrote then store.migratedSpecs[specID] = true end

    if ThugUI.Diagnostics then
        ThugUI.Diagnostics:Log("MIGRATE", "%s: %d legacy spell(s) resolved, %s",
            Data.GetSpecName(specID), #spellIDs,
            wrote and "imported" or "nothing written")
    end
    return wrote
end

--- Attempt migration for every spec that had a legacy bar. Safe to re-run.
function Data.MigrateLegacyBars()
    local store = Store()
    store.migratedSpecs = store.migratedSpecs or {}

    -- The old global flag meant "the one-shot pass already ran". Specs it
    -- actually populated are detected below by their placements, so the flag
    -- itself is no longer consulted for anything but not re-reading history.
    for _, specID in pairs(DRUID_SPEC_IDS) do
        local profile = Store().profiles[specID]
        if profile and next(profile.placements) then
            store.migratedSpecs[specID] = true
        end
    end

    for _, specID in pairs(DRUID_SPEC_IDS) do
        Data.MigrateSpec(specID)
    end

    -- A junk profile under specID 0 could be written before spec data loaded.
    -- GetProfile refuses to create one now; this clears any already saved.
    if Store().profiles[0] then Store().profiles[0] = nil end
end

Data.DRUID_SPEC_IDS = DRUID_SPEC_IDS

return Data
