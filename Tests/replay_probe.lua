-- Replay the player's REAL /thugcv probe dump through the live Data.lua and
-- report what the cooldown-info cache actually resolves for a given spell.
-- No stubs of our own logic -- only the game APIs are faked, fed from the dump.

local svPath, addonPath, targetID = ...
targetID = tonumber(targetID)

-- ------------------------------------------------------------ load the dump
local env = {}
local chunk = assert(loadfile(svPath, "t", env))
chunk()

local dump = env.ThugUI_BCVDump and env.ThugUI_BCVDump.cooldownViewer
assert(dump and dump.entries, "no probe dump in SavedVariables")
print(("probe: %s, %s, %d entries"):format(dump.spec, dump.capturedAt, #dump.entries))

-- The dump flattens linkedSpellIDs to "id=name, id=name"; rebuild the array
-- and a name lookup so the fake API returns the same shape the game does.
local spellNames = {}
local entriesByCategory = {}
local entriesByID = {}

for i, e in ipairs(dump.entries) do
    local linked = {}
    -- 5.5 makes generic-for variables const, so copy before converting.
    for rawID, name in tostring(e.linkedSpellIDs or ""):gmatch("(%d+)=([^,]+)") do
        local id = tonumber(rawID)
        table.insert(linked, id)
        spellNames[id] = (name:gsub("^%s+", ""))
    end
    if e.name and e.spellID then spellNames[e.spellID] = e.name end

    local info = {
        cooldownID = e.cooldownID,
        spellID = e.spellID,
        overrideSpellID = e.overrideSpellID,
        overrideTooltipSpellID = e.overrideTooltipSpellID,
        hasAura = e.hasAura,
        selfAura = e.selfAura,
        linkedSpellIDs = linked,
        category = e.category,
    }
    entriesByID[i] = info
    entriesByCategory[e.category] = entriesByCategory[e.category] or {}
    table.insert(entriesByCategory[e.category], i)
end

-- ------------------------------------------------------------ fake the game
ThugUI = {}
ThugUI_Config = {}
function issecretvalue() return false end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 260, "Outlaw" end
function GetNumSpecializations() return 1 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

Enum = { CooldownViewerCategory = {
    Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3,
} }

C_Spell = {
    GetSpellInfo = function(q)
        local id = tonumber(q)
        if id then return { spellID = id, name = spellNames[id] or ("#" .. id) } end
        for sid, name in pairs(spellNames) do
            if name == q then return { spellID = sid, name = name } end
        end
        return nil
    end,
    GetSpellTexture = function() return 1 end,
}

local CATEGORY_ID_TO_NAME = {}
for name, value in pairs(Enum.CooldownViewerCategory) do CATEGORY_ID_TO_NAME[value] = name end

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        return entriesByCategory[CATEGORY_ID_TO_NAME[category]] or {}
    end,
    GetCooldownViewerCooldownInfo = function(index) return entriesByID[index] end,
}
C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end }

-- ------------------------------------------------------- run the real module
dofile(addonPath .. "/modules/CooldownViewer/Data.lua")
local Data = ThugUI.CooldownViewer.Data

print("\n== every entry carrying spell " .. targetID .. " ==")
for i, info in ipairs(entriesByID) do
    local matches = info.spellID == targetID or info.overrideSpellID == targetID
    for _, id in ipairs(info.linkedSpellIDs) do
        if id == targetID then matches = true end
    end
    if matches then
        print(("  %-12s cooldownID %-7s linked: %d")
            :format(info.category, tostring(info.cooldownID), #info.linkedSpellIDs))
    end
end

print("\n== what GetCooldownInfoForSpell picks ==")
local picked = Data.GetCooldownInfoForSpell(targetID)
if not picked then
    print("  NOTHING -- the spell is not indexed at all")
else
    print(("  category %s, cooldownID %s, %d linked spell(s)")
        :format(tostring(picked.category), tostring(picked.cooldownID), #picked.linkedSpellIDs))
    for _, id in ipairs(picked.linkedSpellIDs) do
        print(("     %d  %s"):format(id, spellNames[id] or "?"))
    end
end

print("\n== does it reach the tracked-buffs picker? ==")
local found
for _, entry in ipairs(Data.BuildSpellList("buffs", nil)) do
    if entry.spellID == targetID then found = entry end
end
print(found and ("  yes, listed as " .. found.name) or "  NO -- absent from that source")
