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
--   cooldown   -- visible while the spell is READY, hidden while on cooldown.
--                 This is the "use it now" signal the original bars were built
--                 around and stays the default.
--   recharging -- the exact inverse of cooldown: visible while NOT ready,
--                 hidden once it is. Derived from the same readiness answer as
--                 cooldown mode (Core.lua), so the two can never disagree. For
--                 a trinket or a potion timer the inverse is what you actually
--                 want -- show it while it is coming back, hide it once it is
--                 up -- so unlike cooldown mode it gets a sweep.
--   always     -- always visible, with a cooldown sweep over it.
--   aura       -- visible only while its buff is on the player (procs).
--   proc       -- visible only when the spell is BOTH off cooldown and lit up
--                 by a proc. Narrower than "cooldown": a spell that is merely
--                 usable stays hidden until something actually makes it worth
--                 pressing, e.g. Pistol Shot only once Opportunity is up.
Data.MODES = {
    { value = "cooldown",   text = "Show when ready" },
    { value = "recharging", text = "Show while recharging" },
    { value = "proc",       text = "Show when ready and procced" },
    { value = "always",     text = "Always show (with sweep)" },
    { value = "aura",       text = "Show while buff active" },
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

--- Which side of the cursor the shape's bulk ACTUALLY sits on, from the cells
--- the player filled rather than from the shape of the grid.
--- @return packRight boolean|nil, packDown boolean|nil  -- nil where it ties
---
--- `CV:FollowCursor` offsets the container by `anchorRow * cellH`, which makes
--- intersection R the BOTTOM edge of cell row R. So a cell at or before the
--- anchor is above the cursor and one after it is below, and the same holds on
--- x. That is exact; nothing here is a heuristic.
---
--- Returns nil for an axis that ties, including an empty grid, so the caller
--- can apply its own tie-break rather than have one invented here.
local function AutoAxesFromPlacements(profile)
    local anchorCol = profile.anchorCol or 0
    local anchorRow = profile.anchorRow or 0

    local left, right, above, below = 0, 0, 0, 0

    for key in pairs(profile.placements or {}) do
        local row, col = Data.ParseCellKey(key)
        if row and col then
            if col <= anchorCol then left = left + 1 else right = right + 1 end
            if row <= anchorRow then above = above + 1 else below = below + 1 end
        end
    end

    -- Packing towards the cursor is the OPPOSITE of where the bulk lies: a
    -- shape hanging to the right packs left, one sitting above packs down.
    local packRight, packDown
    if left ~= right then packRight = left > right end
    if above ~= below then packDown  = above > below end

    return packRight, packDown
end

--- The auto answer for both axes, before any explicit override.
--- @return autoRight boolean, autoDown boolean
---
--- ONE source of truth, deliberately. This is consumed both by the collapse and
--- by `CV:FollowCursor`'s gap nudge, and those two disagreeing about which side
--- of the pointer the shape is on is exactly the bug in DECISIONS.md 18 -- the
--- layout put the shape above the cursor while the collapse packed it upwards,
--- away from it. Route any new caller through here rather than re-deriving it.
---
--- The grid-midpoint test survives only as the tie-break for a shape that
--- straddles the anchor evenly, or for a grid with nothing on it yet. It used
--- to be the whole rule, and as a rule it was wrong: it asks where the anchor
--- sits on the GRID, which is only a proxy for where the shape sits relative to
--- the ANCHOR, and the two part company as soon as a player builds a shape that
--- is not roughly opposite the anchor across the centre of the grid.
function Data.ResolveAutoAxes(profile)
    local fromShape, fromShapeDown = AutoAxesFromPlacements(profile)

    local autoRight = fromShape
    local autoDown  = fromShapeDown

    if autoRight == nil then
        autoRight = (profile.anchorCol or 0) >= Data.GRID_COLS / 2
    end
    if autoDown == nil then
        autoDown = (profile.anchorRow or 0) >= Data.GRID_ROWS / 2
    end

    return autoRight, autoDown
end

--- The axis direction icons pack toward: "left"/"right" in rows mode,
--- "up"/"down" in columns mode.
---
--- Delegates its auto case to ResolveCollapseAxes rather than repeating the
--- derivation, so the two can never answer differently.
function Data.ResolveCollapseDirection(profile)
    local mode = profile.collapse or "none"
    local direction = profile.collapseDirection or "auto"

    if mode == "columns" then
        if direction == "up" or direction == "down" then return direction end
        local _, down = Data.ResolveCollapseAxes(profile)
        return down and "down" or "up"
    end

    if direction == "left" or direction == "right" then return direction end
    local right = Data.ResolveCollapseAxes(profile)
    return right and "right" or "left"
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

    local autoRight, autoDown = Data.ResolveAutoAxes(profile)

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
        -- Either identity counts. This used to guard on `placement.spellID`
        -- alone, which silently dropped every category placement (potions,
        -- healthstones -- 12.1, no spell ID at all) before anything
        -- downstream ever saw it. Task 18; DECISIONS.md §25.
        if row and col and placement and (placement.spellID or placement.categoryID) then
            table.insert(list, {
                row = row, col = col, key = key,
                spellID = placement.spellID,
                categoryID = placement.categoryID,
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

--- Save a placement identified by CATEGORY rather than spell -- potions and
--- healthstones, which 12.1 tracks with no spell ID at all
--- (`spellCategoryID` only). A sibling of SetPlacement rather than an
--- overload of it: smuggling a category into the `spellID` field would make
--- that field lie, and every C_Spell/C_Item call site would still need a
--- guard either way. DECISIONS.md §25, task 18.
function Data.SetCategoryPlacement(profile, row, col, categoryID, mode)
    if row < 1 or row > Data.GRID_ROWS or col < 1 or col > Data.GRID_COLS then return end
    profile.placements[Data.CellKey(row, col)] = categoryID
        and { categoryID = categoryID, mode = mode or "cooldown" }
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

--- Is this spell already on the grid?
---
--- @param mode string? Restricts which placements count.
---   nil     -- any mode counts (the original behaviour, kept exactly for the
---             callers that predate this argument).
---   "aura"  -- only an aura-mode placement counts.
---   "other" -- only a non-aura placement (cooldown/proc/always) counts.
--- The same spell ID can legitimately be placed twice with different meanings
--- -- Roll the Bones as an Essential cooldown AND as a tracked buff -- so a
--- caller that cares about one kind of placement, not merely the ID, needs a
--- way to ask for that. Data does not know what a "picker source" is; the
--- caller decides which mode family a given row's placement should be judged
--- against.
--- `spellID` here is really "an identity" -- a plain spell ID, or the string
--- key Data.PlacementKey hands back for a category placement. Comparing
--- through PlacementKey rather than `placement.spellID == spellID` directly
--- is what lets a caller ask about a category placement at all; for a plain
--- spell ID it is the exact same comparison as before, since PlacementKey
--- returns `placement.spellID` unchanged whenever one is present.
function Data.IsSpellPlaced(profile, spellID, mode)
    for _, placement in pairs(profile.placements) do
        if Data.PlacementKey(placement) == spellID then
            if mode == nil then return true end
            local placementMode = placement.mode or "cooldown"
            local isAura = placementMode == "aura"
            if mode == "aura" and isAura then return true end
            if mode == "other" and not isAura then return true end
        end
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
--
-- CATEGORIES_BY_SOURCE stays an explicit hand-written map while the cache,
-- dump, and "Everything" iterate Enum.CooldownViewerCategory. Combining
-- TrackedBuff and TrackedBar into "Tracked buffs" is a player-facing UI design
-- decision, not a data structure decision. New categories remain accessible via
-- "Everything" until explicitly added to a curated source.
local CATEGORIES_BY_SOURCE = {
    essential = { "Essential" },
    utility   = { "Utility" },
    buffs     = { "TrackedBuff", "TrackedBar" },
}

--- Every Cooldown Manager category as `{ name = <string>, value = <number> }`,
--- sorted ascending by value.
---
--- Hardcoded category names silently ignore new categories added by game patches.
--- Iterating the enum keeps internal caches, probe dumps, and "Everything" complete.
---
--- FILTERING NEGATIVE VALUES:
--- Blizzard injects negative pseudo-categories into `Enum.CooldownViewerCategory`
--- at runtime in `Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua`:
---   --- These values aren't actually part of the enum
---   --- They exist so that disabled states can be managed using the same category enums
---   --- There are checks to ensure that they don't match any of the pre-existing enum values
---   Enum.CooldownViewerCategory.HiddenSpell = -1;
---   Enum.CooldownViewerCategory.HiddenAura = -2;
--- (Renamed to `HiddenActive = -1` and `HiddenPassive = -2` on 12.1 PTR).
--- They are markers for disabled states, not real category sets. Matching on
--- name would break when names change between builds, so we filter by value:
--- real categories start at 0 and count upwards.
local function CooldownViewerCategories()
    local categories = {}
    if not Enum or not Enum.CooldownViewerCategory then
        return categories
    end

    for name, value in pairs(Enum.CooldownViewerCategory) do
        if type(value) == "number" and value >= 0 then
            table.insert(categories, { name = name, value = value })
        end
    end

    table.sort(categories, function(a, b) return a.value < b.value end)
    return categories
end

--- Spell IDs from one Cooldown Manager category. Returns an empty list on any
--- client where C_CooldownViewer is missing or the enum has been renamed.
---
--- Used to also offer each entry's linkedSpellIDs as separate picker rows, so
--- a player could track one outcome specifically -- "show me only when I roll
--- Jackpot" instead of just "show me Roll the Bones". That intent was real,
--- and it was tested in game: placing Roll the Bones plus all four outcomes
--- in `aura` mode rendered exactly one icon, not five. The reason is
--- structural, not a bug to fix here -- `BlizzBuffs:Apply` maps ONE Blizzard
--- item frame per `cooldownID`, and every linked ID resolves to the SAME
--- cooldownID as its base entry (Roll the Bones and its four outcomes are all
--- cdID 42743 in the player's own dump). Five picker rows, one frame to
--- adopt, one winner -- no logic makes five cells share one frame. Nothing is
--- lost by not expanding: the base entry already covers the linked buffs at
--- runtime, since `ResolveAura` in Core.lua walks `icon.linkedSpellIDs` and
--- shows whichever is live regardless of what the picker offered.
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

--- Same walk as CooldownViewerSpellIDs, but for the entries it has to skip:
--- ones with NO spell ID at all -- potions and healthstones on 12.1, tracked
--- only by `spellCategoryID` (DECISIONS.md §25). Which Enum category they are
--- filed under is unverified, so this asks every named source's category the
--- same question rather than assuming one.
local function CooldownViewerCategoryIDs(categoryName)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return {}
    end
    local category = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
    if category == nil then return {} end

    local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
    if not ok or type(cooldownIDs) ~= "table" then return {} end

    local categoryIDs = {}
    for _, cooldownID in ipairs(cooldownIDs) do
        local infoOK, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if infoOK and info and info.spellCategoryID and not Data.PickerSpellIDFor(info) then
            table.insert(categoryIDs, info.spellCategoryID)
        end
    end
    return categoryIDs
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

--- A non-nil identity for any placement, for keying and equality only.
--- Never pass this to a C_Spell/C_Item API -- it is not a spell ID.
---
--- A spell placement's key is its bare spell ID (a number); a category
--- placement's is the string "cat:N". The types can never collide with each
--- other in a Lua table, which is the property this exists for -- category 4
--- (combat potion) and spell 4 must never be treated as the same identity.
function Data.PlacementKey(p)
    if not p then return nil end
    if p.spellID then return p.spellID end
    if p.categoryID then return "cat:" .. p.categoryID end
    return nil
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

--- Every spell ID that could name a Cooldown Manager entry, gaps closed up.
---
--- Appended one at a time rather than written as a table constructor, because
--- `{ info.spellID, info.overrideSpellID, info.overrideTooltipSpellID }` leaves
--- a HOLE wherever one of those is nil, and ipairs stops dead at the first hole.
--- With spellID absent and an override present, that loop ran zero times and the
--- entry was never indexed under anything -- so a placement pointing at it
--- resolved to no entry at all, which surfaces as `no Cooldown Manager entry` in
--- the CVBUFF log and an empty cell in the grid.
---
--- On 12.0.7 this could not bite: `spellID` was documented non-nilable and the
--- one entry shape with no base spell (Roll the Bones) had all three absent, so
--- the hole was at index 1 and the linked IDs happened to fill it in. **On 12.1
--- `spellID` is officially nilable** -- CooldownViewerDocumentation.lua on the
--- live branch, build 69273 -- and the item entries the patch adds (trinkets
--- keyed by `equipSlot`, potions and healthstones keyed by `spellCategoryID`)
--- are exactly the shape that has no base spell.
local function IndexableSpellIDs(info)
    local ids = {}

    local function Add(id)
        if id then ids[#ids + 1] = id end
    end

    Add(info.spellID)
    Add(info.overrideSpellID)
    Add(info.overrideTooltipSpellID)
    for _, id in ipairs(info.linkedSpellIDs or {}) do
        Add(id)
    end

    return ids
end

local function BuildCooldownInfoCache()
    local cache = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return cache
    end

    for _, item in ipairs(CooldownViewerCategories()) do
        local categoryName = item.name
        local category = item.value
        if category ~= nil then
            local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
            if ok and type(cooldownIDs) == "table" then
                for _, cooldownID in ipairs(cooldownIDs) do
                    local infoOK, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if infoOK and info then
                        -- Indexed under every ID that could name this entry, so
                        -- a placement made from any of them finds it again.
                        for _, id in ipairs(IndexableSpellIDs(info)) do
                            cache[id] = Preferred(cache[id], info)
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
--- tracked entry can show, e.g. the Roll the Bones outcomes.
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

-- ----------------------------------------------------------------------------
-- Category-only entries -- potions, healthstones (12.1)
--
-- These carry no spell ID at all, only `spellCategoryID`, so they cannot live
-- in cooldownInfoCache above and must not be folded into it: IndexableSpellIDs
-- stays exactly what it is (nothing here indexes a category under a spell ID),
-- and a caller asking "what does spell 4 mean" must never collide with "what
-- does category 4 mean". DECISIONS.md §25, task 18.
-- ----------------------------------------------------------------------------

-- Declared BEFORE InvalidateCooldownInfoCache, and that ordering is
-- load-bearing. Lua binds a name at parse time: with the `local` below the
-- function, the assignment inside it would create two GLOBALS that nothing
-- reads, leaving the real cache un-invalidated on any talent change within one
-- spec -- and leaking two names into WoW's shared global namespace, which is
-- how §15's Edit Mode collision started. Shipped that way in task 18 and
-- caught in review; the harness cannot see it, because the spec check in
-- GetCategoryInfo masks the symptom whenever the spec actually changes.
local categoryInfoCache, categoryInfoCacheSpec

function Data.InvalidateCooldownInfoCache()
    cooldownInfoCache, cooldownInfoCacheSpec = nil, nil
    categoryInfoCache, categoryInfoCacheSpec = nil, nil
end

--- Every Cooldown Manager entry that names a category and no spell, indexed
--- by spellCategoryID. The FIRST entry found for a category wins -- only the
--- category's identity matters here (name/icon are resolved from its
--- cooldownID via Blizzard's own pooled frame, not from anything stored on
--- `info` itself), so which of possibly several cooldownIDs sharing a
--- category happens to be scanned first does not matter.
local function BuildCategoryInfoCache()
    local cache = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return cache
    end

    for _, item in ipairs(CooldownViewerCategories()) do
        local category = item.value
        local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
        if ok and type(cooldownIDs) == "table" then
            for _, cooldownID in ipairs(cooldownIDs) do
                local infoOK, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                if infoOK and info and info.spellCategoryID and not Data.PickerSpellIDFor(info) then
                    if not cache[info.spellCategoryID] then
                        cache[info.spellCategoryID] = info
                    end
                end
            end
        end
    end
    return cache
end

--- The Cooldown Manager entry behind a category ID, or nil. Mirrors
--- GetCooldownInfoForSpell, keyed by category instead of spell.
function Data.GetCategoryInfo(categoryID)
    if not categoryID then return nil end

    local specID = Data.GetActiveSpecID()
    if not categoryInfoCache or categoryInfoCacheSpec ~= specID then
        categoryInfoCache = BuildCategoryInfoCache()
        categoryInfoCacheSpec = specID
    end
    return categoryInfoCache[categoryID]
end

--- Every spellCategoryID actually true for this character right now,
--- discovered from the sweep above -- never a hardcoded list. Blizzard's own
--- (unexported) table carries a FOURTH category with no named constant
--- anywhere (2566, Demonic Healthstone), so a hardcoded list of the three
--- documented ones was already wrong before it was written. DECISIONS.md §25.
function Data.DiscoverCategoryIDs()
    local ids = {}
    for categoryID in pairs(BuildCategoryInfoCache()) do
        table.insert(ids, categoryID)
    end
    table.sort(ids)
    return ids
end

-- A generic WoW icon, used only when nothing else answers -- see
-- Data.CategoryEntry's resolution order below. Never a spell/item ID guess:
-- this is a plain texture path, the same kind of fallback art many addons
-- reach for, not anything read out of Blizzard's data.
local GENERIC_CATEGORY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- The persisted cache: ThugUI_Config.cvCategoryArt, categoryID -> {name, icon}.
--- Account-wide by design (DECISIONS.md §25, task 19) -- a category's
--- Blizzard-drawn icon does not vary by character, so a resolve on one alt
--- answers for all of them. Seeded HERE and nowhere else, the same way Store()
--- above lazily seeds the table-valued ThugUI_Config.cv: ER.defaults is copied
--- by reference (`ThugUI_Config[key] = value`), so a table default there would
--- alias the live config onto the defaults table. ER.defaults carries a comment
--- saying so where the key would otherwise sit.
local function CategoryArtCache()
    ThugUI_Config.cvCategoryArt = ThugUI_Config.cvCategoryArt or {}
    return ThugUI_Config.cvCategoryArt
end

--- Name and icon for a category-only placement (potions, healthstones -- no
--- spell ID exists to look either up from). CHEAP AND NON-DISCOVERING: reads
--- the persisted cache and returns the generic entry on a miss. It must
--- NEVER walk viewers or call GetLastCategoryCooldownSource -- that cost is
--- exactly why it is split out from Data.ResolveCategoryArt below
--- (DECISIONS.md §25, task 19). Safe to call from UpdateState every tick and
--- from the picker on every open.
function Data.CategoryEntry(categoryID)
    if not categoryID then return nil end

    local cached = CategoryArtCache()[categoryID]
    if cached then
        return { categoryID = categoryID, name = cached.name, icon = cached.icon }
    end

    return {
        categoryID = categoryID,
        name = ("Consumable (category %d)"):format(categoryID),
        icon = GENERIC_CATEGORY_ICON,
    }
end

--- The expensive pass Data.CategoryEntry no longer makes. Resolves every
--- category currently true for this character (Data.DiscoverCategoryIDs)
--- that is not already in the persisted cache, first that answers wins --
--- DECISIONS.md §25, task 19:
---
---   1. Blizzard's own pooled item frame for this category's cooldownID.
---      item:GetSpellCategoryIcon() is preferred -- it says exactly what we
---      want (Decision 1: the category's own art, never the triggering
---      item's) and cannot drift if Blizzard ever reorder GetSpellTexture's
---      internal fallback -- and item:GetSpellTexture() is the fallback for
---      a build where that method is absent. Name still from
---      item:GetNameText(). pcall throughout: these are Blizzard internals,
---      and a renamed method must degrade, not throw. Reading the frame is
---      fine; writing to it is what caused §15's taint bug, and nothing here
---      writes anything.
---   2. C_Spell.GetLastCategoryCooldownSource -- a catch-up call that returns
---      NOTHING until the category has actually been triggered this session
---      (MayReturnNothing = true), the normal case on a fresh login, not a
---      failure. SecretWhenCooldownsRestricted, so both returns are screened
---      with issecretvalue before any nil test. Demoted to a last resort: it
---      shows the triggering item's own icon rather than the category's,
---      which contradicts Decision 1, but a real potion icon beats a
---      question mark, and it only runs when path 1 could not answer.
---
--- A resolved entry is STICKY -- an already-cached category is skipped
--- entirely, so a pass where every path fails again can never downgrade a
--- resolved entry back to the generic one. Once every category is cached the
--- per-category work stops entirely and only the DiscoverCategoryIDs sweep
--- remains -- the same sweep Rebuild already performs, twice per fight rather
--- than per frame, which is why it is not worth a flag to skip.
--- Called only from PLAYER_REGEN_DISABLED/ENABLED
--- (Core.lua): combat entry is when Blizzard's own viewer starts drawing and
--- its item-frame pool populates, which is what turned "question marks at
--- login" out to be. Never called from UpdateState, and never polled.
--- Which categories a resolve pass should try: everything discovery can see,
--- PLUS every category the player has actually placed.
---
--- The placed half is not redundant, and leaving it out was a real regression
--- on 2026-08-13: discovery is built from the Cooldown Manager sweep, and when
--- that sweep comes back empty -- the same session logs
--- "no Blizzard cooldown-viewer item frames found" -- a placed category is not
--- in the list, so it is never even attempted. The old uncached CategoryEntry
--- never had this hole, because it was called with the placed categoryID
--- directly and tried GetLastCategoryCooldownSource on it regardless of what
--- discovery thought existed. A cell the player can SEE must always be worth a
--- resolve attempt.
local function CategoriesNeedingArt()
    local seen, ids = {}, {}

    local function add(categoryID)
        if categoryID and not seen[categoryID] then
            seen[categoryID] = true
            table.insert(ids, categoryID)
        end
    end

    for _, categoryID in ipairs(Data.DiscoverCategoryIDs()) do add(categoryID) end

    local profile = CV.CurrentProfile and CV:CurrentProfile()
    if profile and profile.placements then
        for _, placement in ipairs(Data.GetPlacements(profile)) do
            add(placement.categoryID)
        end
    end

    return ids
end

function Data.ResolveCategoryArt()
    local cache = CategoryArtCache()

    for _, categoryID in ipairs(CategoriesNeedingArt()) do
        if not cache[categoryID] then
            local resolved

            local info = Data.GetCategoryInfo(categoryID)
            local cooldownID = info and info.cooldownID
            if cooldownID and CV.BlizzBuffs and CV.BlizzBuffs.ItemForCooldownID then
                local item = CV.BlizzBuffs:ItemForCooldownID(cooldownID)
                if item then
                    local texture
                    if item.GetSpellCategoryIcon then
                        local ok, tex = pcall(item.GetSpellCategoryIcon, item)
                        if ok and tex then texture = tex end
                    end
                    if not texture then
                        local ok, tex = pcall(item.GetSpellTexture, item)
                        if ok and tex then texture = tex end
                    end
                    local nameOK, name = pcall(item.GetNameText, item)
                    if texture and nameOK and name and name ~= "" then
                        resolved = { name = name, icon = texture }
                    end
                end
            end

            if not resolved and C_Spell and C_Spell.GetLastCategoryCooldownSource then
                local ok, spellID, itemID = pcall(C_Spell.GetLastCategoryCooldownSource, categoryID)
                -- issecretvalue asked FIRST: comparing a secret against nil is
                -- itself a comparison, and comparison is the operation that
                -- throws.
                local secret = issecretvalue and (issecretvalue(spellID) or issecretvalue(itemID))
                if ok and not secret and spellID and itemID then
                    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
                    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
                    if name and icon then
                        resolved = { name = name, icon = icon }
                    end
                end
            end

            if resolved then
                cache[categoryID] = resolved
            end
        end
    end
end

--- Everything the Cooldown Manager reports for this spec, for /thugcv probe.
function Data.DumpCooldownViewer()
    local dump = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return dump
    end

    for _, item in ipairs(CooldownViewerCategories()) do
        local categoryName = item.name
        local category = item.value
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
                            -- 12.1 fields. equipSlot and spellCategoryID are how
                            -- the Cooldown Manager names an ITEM -- a trinket by
                            -- the slot it sits in, a potion or healthstone by its
                            -- shared cooldown category -- and those entries carry
                            -- no spellID at all, so these three are the only
                            -- handle on them. Dumped because a placement model
                            -- keyed on spell ID cannot see them, and the probe is
                            -- what tells us what to key on instead.
                            equipSlot = info.equipSlot,
                            spellCategoryID = info.spellCategoryID,
                            buffSlot = info.buffSlot,
                            isInvisible = info.isInvisible,
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

--- Check if a category name is included in CATEGORIES_BY_SOURCE.buffs
local function IsBuffCategory(categoryName)
    for _, name in ipairs(CATEGORIES_BY_SOURCE.buffs or {}) do
        if name == categoryName then return true end
    end
    return false
end

--- Can a tracked buff actually be drawn right now?
---
--- Only Blizzard's own frames can show a buff in combat, so with that
--- workaround switched off a buff placement has nothing to draw with and the
--- cell would simply stay empty and silent. The picker therefore stops offering
--- them. Mirrors BlizzBuffs:IsEnabled deliberately -- `nil` means ON, and
--- reading this as a plain truth test would empty the buff list for every
--- player who has never touched the setting.
function Data.BuffsAvailable()
    return ThugUI_Config.cvUseBlizzardBuffs ~= false
end

--- Check if a category name is included in any source in CATEGORIES_BY_SOURCE
local function IsKnownCategory(categoryName)
    for _, categoryNames in pairs(CATEGORIES_BY_SOURCE) do
        for _, name in ipairs(categoryNames) do
            if name == categoryName then return true end
        end
    end
    return false
end

--- The picker list for a source, de-duplicated, name-filtered, alphabetised.
--- @param source string one of Data.SOURCES values
--- @param search string? case-insensitive substring filter
function Data.BuildSpellList(source, search)
    local ids = {}
    -- Category-only entries (potions, healthstones) walk beside `ids` rather
    -- than inside it: their identity is not a spell ID, so mixing the two
    -- lists would need every consumer of `ids` to learn a second kind of
    -- value. Task 18; DECISIONS.md §25.
    local categoryIDs = {}

    local function collect(list)
        for _, id in ipairs(list) do table.insert(ids, id) end
    end
    local function collectCategories(list)
        for _, id in ipairs(list) do table.insert(categoryIDs, id) end
    end

    -- Withheld, not filtered out afterwards: a buff that cannot be drawn must
    -- never be offered, in "buffs" or in "all". Only the buff categories are
    -- affected -- essential, utility and spellbook are untouched.
    local buffsAvailable = Data.BuffsAvailable()

    if source == "spellbook" then
        collect(SpellbookSpellIDs())
    elseif source == "all" then
        for _, item in ipairs(CooldownViewerCategories()) do
            local categoryName = item.name
            if not IsKnownCategory(categoryName) then
                if ThugUI.Diagnostics and ThugUI.Diagnostics.LogOnce then
                    ThugUI.Diagnostics:LogOnce("cv-unrecognized-cat-" .. categoryName, "CV",
                        "Unrecognized CooldownViewerCategory '%s' in Enum", categoryName)
                end
            end
            local isBuff = IsBuffCategory(categoryName)
            if buffsAvailable or not isBuff then
                collect(CooldownViewerSpellIDs(categoryName))
                collectCategories(CooldownViewerCategoryIDs(categoryName))
            end
        end
        collect(SpellbookSpellIDs())
    else
        local withheld = false
        for _, categoryName in ipairs(CATEGORIES_BY_SOURCE[source] or {}) do
            if not buffsAvailable and IsBuffCategory(categoryName) then
                withheld = true
            else
                collect(CooldownViewerSpellIDs(categoryName))
                collectCategories(CooldownViewerCategoryIDs(categoryName))
            end
        end
        -- A spec Blizzard has not categorised would otherwise show an empty
        -- picker with no hint that another source would work. Not when the list
        -- was withheld on purpose, though: answering "tracked buffs" with the
        -- whole spellbook is worse than answering it with nothing and saying
        -- why, which is what the picker does instead.
        if #ids == 0 and #categoryIDs == 0 and not withheld then collect(SpellbookSpellIDs()) end
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
    -- Opening the picker is a resolve opportunity, and it used to be one for
    -- free: before the cache existed, CategoryEntry resolved on every call, so
    -- the list was as fresh as the moment you looked at it. Making that call
    -- cheap moved the cost here, deliberately -- once the cache answers this
    -- is a no-op, and the player opening the picker is not a hot path.
    if #categoryIDs > 0 then Data.ResolveCategoryArt() end

    for _, categoryID in ipairs(categoryIDs) do
        local key = Data.PlacementKey({ categoryID = categoryID })
        if not seen[key] then
            seen[key] = true
            local entry = Data.CategoryEntry(categoryID)
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
