-- ============================================================================
-- ThugUI: Diagnostics
--
-- Always-on, silent recording of what the addon is actually doing, into the
-- ThugUI_DebugLog saved variable. No command to remember, no flag to set.
--
-- WHY THIS EXISTS
--
-- Every hard problem in this addon has cost at least one round trip of "run
-- this command, then reload, then tell me what it said". Worse, one of them
-- cost a wrong conclusion: a fix was pushed, the player was still running the
-- previous build, and the resulting behaviour was indistinguishable from the
-- fix not working. There was no way to tell from the outside which code had
-- been loaded.
--
-- So this records evidence of BEHAVIOUR, not just a version string. If the
-- snapshot says an icon resolved 4 linked spells, the linked-spell code was
-- live, whatever the version claims.
--
-- WHAT IT IS NOT
--
-- Not the verbose aura logger in modules/EssentialRings.lua. That one writes
-- on every aura read and stays behind ThugUI_Config.debugMode for good reason.
-- This is event-level: a handful of entries per session, and one state
-- snapshot taken at logout. It costs nothing to leave on.
-- ============================================================================

ThugUI = ThugUI or {}

local D = {}
ThugUI.Diagnostics = D

-- Enough to see how a session unfolded, small enough to never bloat the file.
local MAX_EVENTS = 300

local function Store()
    ThugUI_DebugLog = ThugUI_DebugLog or {}
    ThugUI_DebugLog.events = ThugUI_DebugLog.events or {}
    return ThugUI_DebugLog
end

-- Guarded because this runs unconditionally: a logger that throws is strictly
-- worse than no logger, and it must never be the reason something breaks.
local function Stamp(format)
    if type(date) ~= "function" then return "?" end
    local ok, value = pcall(date, format)
    return ok and value or "?"
end

local function Now()
    return Stamp("%H:%M:%S")
end

--- Record something worth knowing later. Cheap: string format plus a table
--- insert, so call sites do not need to guard it.
--- @param category string short tag, e.g. "CV", "SPEC", "RING"
function D:Log(category, message, ...)
    local ok, text = pcall(string.format, message, ...)
    if not ok then text = tostring(message) end

    local store = Store()
    table.insert(store.events, ("[%s] %s: %s"):format(Now(), category, text))

    -- Ring buffer. Dropping the oldest keeps the tail, which is the part that
    -- explains whatever just went wrong.
    while #store.events > MAX_EVENTS do
        table.remove(store.events, 1)
    end
end

-- ----------------------------------------------------------------------------
-- State snapshot
-- ----------------------------------------------------------------------------

--- Everything the cooldown viewer resolved, per placed icon.
---
--- The linked-spell count is the load-bearing field: it is direct evidence of
--- whether the linked-buff lookup ran, which no version number can tell you.
local function CaptureProfiles()
    local CV = ThugUI.CooldownViewer
    local Data = CV and CV.Data
    if not Data then return nil end

    local out = {}
    local specID = Data.GetActiveSpecID()
    if not specID then return out end

    local profile = Data.GetProfile(specID)
    local icons = {}

    for _, placement in ipairs(Data.GetPlacements(profile)) do
        local info = C_Spell and C_Spell.GetSpellInfo(placement.spellID)
        local cooldownInfo = Data.GetCooldownInfoForSpell(placement.spellID)
        local linked = cooldownInfo and cooldownInfo.linkedSpellIDs or {}

        table.insert(icons, ("%s  %-28s id=%-9s mode=%-9s linked=%d%s")
            :format(placement.key,
                    (info and info.name) or "?",
                    tostring(placement.spellID),
                    placement.mode,
                    #linked,
                    cooldownInfo and ("  cat=" .. tostring(cooldownInfo.category)) or "  (no entry)"))
    end

    out[specID] = {
        spec = Data.GetSpecName(specID),
        enabled = profile.enabled,
        onlyInCombat = profile.onlyInCombat,
        followCursor = profile.followCursor,
        collapse = profile.collapse,
        collapseDirection = profile.collapseDirection,
        anchor = ("col %d, row %d"):format(profile.anchorCol or 0, profile.anchorRow or 0),
        showing = CV.container and CV.container:IsShown() or false,
        icons = icons,
    }
    return out
end

--- Take a snapshot of what the addon currently believes. Called at logout, so
--- it reflects the session that just ran rather than a fresh login.
function D:CaptureState()
    local store = Store()
    local _, class = UnitClass("player")

    store.version = ThugUI.version
    store.interface = select(4, GetBuildInfo())
    store.lastUpdated = Stamp("%Y-%m-%d %H:%M:%S")

    store.state = {
        class = class,
        legacyCooldownViewer = ThugUI_Config and ThugUI_Config.cvUseLegacy or false,
        resourceRing = ThugUI_Config and ThugUI_Config.showResourceRing or false,
        profiles = CaptureProfiles(),
    }
end

-- ----------------------------------------------------------------------------
-- Wiring
-- ----------------------------------------------------------------------------

local driver = CreateFrame("Frame", "ThugUI_DiagnosticsDriver")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- A fresh session starts a fresh log. Keeping several sessions of
        -- events would bury the one being asked about.
        local store = Store()
        store.events = {}
        store.sessionStarted = Stamp("%Y-%m-%d %H:%M:%S")

        local _, class = UnitClass("player")
        D:Log("SESSION", "login as %s, ThugUI v%s, interface %s",
            tostring(class), tostring(ThugUI.version), tostring(select(4, GetBuildInfo())))
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local Data = ThugUI.CooldownViewer and ThugUI.CooldownViewer.Data
        D:Log("SPEC", "changed to %s",
            Data and Data.GetSpecName(Data.GetActiveSpecID()) or "?")
        return
    end

    if event == "PLAYER_LOGOUT" then
        -- Fires before the saved variables are written, which is exactly when
        -- a snapshot of the finished session is worth taking.
        pcall(function() D:CaptureState() end)
    end
end)

--- Log something at most once a session. For conditions that would otherwise
--- repeat every frame -- an unreadable power value, a missing API -- where the
--- first occurrence is the whole story.
local seen = {}
function D:LogOnce(key, category, message, ...)
    if seen[key] then return end
    seen[key] = true
    self:Log(category, message, ...)
end

return D

