-- ============================================================================
-- ThugUI: Secret Probe
--
-- Automatic sampling of which 12.x APIs hand THIS addon a usable value, which
-- hand it a secret, and which hand it nothing at all. Taken at five moments --
-- after login, three points inside combat, and the instant combat drops -- and
-- written to ThugUI_DebugLog.secrets.
--
-- Nothing to type. The player fights, leaves combat, reloads, and the answer
-- is on disk.
--
-- WHY THIS EXISTS
--
-- "ThugUI is tainted; clean the taint and the buff icons come back" was the
-- working theory for several sessions, and it is wrong. Addon code ALWAYS
-- executes tainted by its own addon:
--
--   * Every error of this shape in !BugGrabber.lua names the addon it came
--     from -- tRP3_Vendor, Listener, ChonkyCharacterSheet and us all report
--     "while execution tainted by '<themselves>'". Those are the four addons
--     that do arithmetic on secret values, not the four that are dirty.
--   * Blizzard's generated docs flag the APIs, not the caller:
--     GetUnitAuraBySpellID carries RequiresNonSecretAura, which is exactly why
--     it returns NOTHING in combat instead of erroring, and UnitPower carries
--     SecretWhenUnitPowerRestricted.
--
-- So there is no untainted state to reach and nothing to clean. What is still
-- genuinely unknown is what THIS build hands us, and that decides which of the
-- remaining routes is worth building. Guessing it from the wiki has already
-- cost real time, so measure it instead.
--
-- The pivotal line in the output is `aura[1].spellId read`. If a secret aura
-- struct can still be INDEXED, the fields are reachable as secret values and a
-- native mapping could drive an icon without us ever inspecting them. If it
-- errors, that route is closed and Blizzard's own frames are the only way to
-- show a buff in combat.
-- ============================================================================

ThugUI = ThugUI or {}

local P = {}
ThugUI.SecretProbe = P

-- ----------------------------------------------------------------------------
-- Describing a value without touching it
--
-- Order matters in every one of these helpers: issecretvalue is asked FIRST,
-- because comparing a secret to nil is itself a forbidden comparison. Getting
-- this backwards turns the diagnostic into the thing that throws.
-- ----------------------------------------------------------------------------

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--- True only for a real, readable nil. A secret is never "nothing".
local function IsNothing(value)
    if IsSecret(value) then return false end
    return value == nil
end

--- type() is documented to report the real type of a secret, which makes it
--- the one thing that can be said about a value we are not allowed to read.
local function Describe(value)
    if IsSecret(value) then return "SECRET " .. type(value) end
    if value == nil then return "nothing" end

    local kind = type(value)
    if kind == "table" then return "table" end
    if kind == "string" then return ('"%s"'):format(value) end
    return tostring(value)
end

--- Call something that may not exist and may throw, and say what came back.
--- A dead API must not end the probe early -- the entries after it are usually
--- the interesting ones.
local function Sample(fn, ...)
    if type(fn) ~= "function" then return "absent" end

    local ok, value = pcall(fn, ...)
    if not ok then return "ERROR: " .. tostring(value) end
    return Describe(value)
end

--- As Sample, but hands back the value itself for probes that chain.
local function Raw(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

--- For setters, where the return value means nothing and the only question is
--- whether the call was refused. "Secret values are only allowed during
--- untainted execution for this argument" is the answer being looked for.
local function SampleCall(fn, ...)
    if type(fn) ~= "function" then return "absent" end

    local ok, err = pcall(fn, ...)
    if not ok then return "REFUSED: " .. tostring(err) end
    return "accepted"
end

--- As Sample, but for a two-return function. IsSpellUsable's second value
--- (insufficientPower) is exactly as interesting as the first, and Sample
--- only keeps one.
local function SamplePair(fn, ...)
    if type(fn) ~= "function" then return "absent", "absent" end

    local ok, a, b = pcall(fn, ...)
    if not ok then
        local err = "ERROR: " .. tostring(a)
        return err, err
    end
    return Describe(a), Describe(b)
end

--- Read one field off a value that may itself be secret, absent, or an error.
--- Indexing a secret struct is allowed -- ProbeAuraList already proved that
--- for `aura[1].spellId` -- only COMPARING what comes out is restricted, and
--- this never compares: IsNothing asks issecretvalue before nil, same as
--- everywhere else in this file, and the field read itself goes through a
--- pcall rather than a raw index in case the struct is a type that refuses
--- indexing outright.
local function FieldOf(ok, struct, field)
    if not ok then return "ERROR: " .. tostring(struct) end
    if IsNothing(struct) then return "nothing" end

    local fieldOK, value = pcall(function() return struct[field] end)
    if not fieldOK then return "ERROR: " .. tostring(value) end
    return Describe(value)
end

local function Record(lines, label, text)
    lines[#lines + 1] = ("%-30s %s"):format(label, text)
end

-- ----------------------------------------------------------------------------
-- The probes
-- ----------------------------------------------------------------------------

--- Power. Energy is a PRIMARY resource and stays secret to addons by design;
--- combo points are SECONDARY, and Blizzard's 12.1 notes say those stop being
--- secret. Both are sampled because the pips design in HANDOFF.md is blocked on
--- exactly that difference, and this build may already have it.
local function ProbePower(lines)
    local powerType, token = nil, nil
    local ok, a, b = Raw(UnitPowerType, "player")
    if ok then powerType, token = a, b end

    Record(lines, "UnitPowerType", tostring(token))
    Record(lines, "UnitPower primary", Sample(UnitPower, "player", powerType))
    Record(lines, "UnitPowerMax primary", Sample(UnitPowerMax, "player", powerType))

    local comboType = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
    if comboType then
        Record(lines, "UnitPower combo", Sample(UnitPower, "player", comboType))
        Record(lines, "UnitPowerMax combo", Sample(UnitPowerMax, "player", comboType))
    else
        Record(lines, "UnitPower combo", "Enum.PowerType.ComboPoints absent")
    end
end

--- The by-spell lookups the buff icons actually use. These are the ones
--- carrying RequiresNonSecretAura, so "nothing" here in combat is the expected
--- result and confirms the diagnosis rather than contradicting it.
local function ProbeAuraByID(lines, spellIDs)
    if #spellIDs == 0 then
        Record(lines, "aura by spell id", "no aura-mode icons placed")
        return
    end

    for _, spellID in ipairs(spellIDs) do
        Record(lines, ("GetUnitAuraBySpellID %d"):format(spellID),
            Sample(C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID, "player", spellID))
        Record(lines, ("GetPlayerAuraBySpellID %d"):format(spellID),
            Sample(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, spellID))
    end
end

--- The list walk, and the question the whole probe exists to answer: given an
--- aura struct we are not allowed to read, can we still reach INTO it?
---
--- Returns how many auras the walk saw, which is used to decide whether this
--- sample is worth keeping -- a probe taken during a fight with no buff up
--- says very little.
local function ProbeAuraList(lines)
    local seen, first = 0, nil

    if type(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) ~= "function" then
        Record(lines, "GetAuraDataByIndex", "absent")
        return 0
    end

    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then
            -- 12.1 turns this into a hard error while auras are secret. Say so
            -- plainly if it has already started happening here.
            Record(lines, "GetAuraDataByIndex", "ERROR: " .. tostring(aura))
            break
        end
        if IsNothing(aura) then break end

        seen = seen + 1
        if first == nil then first = aura end
    end

    Record(lines, "aura list length", tostring(seen))
    if first == nil then return seen end

    Record(lines, "aura[1] struct", Describe(first))

    local idOK, id = pcall(function() return first.spellId end)
    Record(lines, "aura[1].spellId read", idOK and Describe(id) or ("ERROR: " .. tostring(id)))

    local nameOK, name = pcall(function() return first.name end)
    Record(lines, "aura[1].name read", nameOK and Describe(name) or ("ERROR: " .. tostring(name)))

    -- Reading a field and COMPARING it are separately restricted, and the
    -- difference decides whether a match is possible at all.
    local cmpOK, cmp = pcall(function() return first.spellId == 1 end)
    Record(lines, "aura[1].spellId compare", cmpOK and ("ok, " .. tostring(cmp))
        or ("ERROR: " .. tostring(cmp)))

    return seen
end

--- Aura instance IDs are the one aura API in the generated docs carrying no
--- SecretWhen predicate at all, which suggests they stay readable as opaque
--- handles. If they do, they are the only non-secret foothold in the aura
--- system during combat, so it is worth knowing for certain.
---
--- Returns the first instance ID, if it is readable, for the chained tests.
local function ProbeAuraInstances(lines)
    local fn = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    if type(fn) ~= "function" then
        -- Worth distinguishing from an error: absent means this client predates
        -- the API, which is a different conclusion entirely.
        Record(lines, "GetUnitAuraInstanceIDs", "absent")
        return nil
    end

    local ok, ids = Raw(fn, "player", "HELPFUL")

    if not ok then
        Record(lines, "GetUnitAuraInstanceIDs", "ERROR: " .. tostring(ids))
        return nil
    end
    if IsSecret(ids) or IsNothing(ids) or type(ids) ~= "table" then
        Record(lines, "GetUnitAuraInstanceIDs", Describe(ids))
        return nil
    end

    Record(lines, "GetUnitAuraInstanceIDs", ("table, %d entries"):format(#ids))

    local firstID = ids[1]
    Record(lines, "instanceID[1]", Describe(firstID))
    if IsSecret(firstID) or IsNothing(firstID) then return nil end

    -- Non-secret bool per the docs, and the only per-aura predicate an addon
    -- could branch on in combat if it holds.
    Record(lines, "IsAuraFilteredOutByInstanceID",
        Sample(C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID,
            "player", firstID, "HELPFUL"))

    return firstID
end

--- Charge spells drawn from the Cooldown Manager itself, not from what the
--- player has placed. AuraSpellIDs (below) only sees aura-mode placements,
--- but DECISIONS.md §19's adoption rule reaches cooldown and always mode too
--- -- a charge spell can sit in either without ever being in aura mode, so
--- this has to walk the same category set BlizzBuffs and Data.lua do rather
--- than reading a placement.
---
--- Reimplemented here rather than calling into CooldownViewer/Data.lua: this
--- probe exists to keep working even if that module fails to load, and it is
--- the diagnostics path -- it must not gain a dependency on the feature it is
--- measuring.
---
--- Capped at 3 entries so a busy spec cannot bloat ThugUI_DebugLog.
local function ChargeSpellCandidates()
    local out = {}
    if not C_CooldownViewer
        or type(C_CooldownViewer.GetCooldownViewerCategorySet) ~= "function"
        or type(C_CooldownViewer.GetCooldownViewerCooldownInfo) ~= "function" then
        return out
    end
    if not Enum or not Enum.CooldownViewerCategory then
        return out
    end

    -- Real categories only. Blizzard injects negative pseudo-categories
    -- (HiddenActive/HiddenPassive on 12.1, HiddenSpell/HiddenAura before it)
    -- into this same enum for disabled-state bookkeeping -- filtering by
    -- value rather than name is what survived that rename. Mirrors
    -- CooldownViewerCategories() in CooldownViewer/Data.lua.
    local categories = {}
    for name, value in pairs(Enum.CooldownViewerCategory) do
        if type(value) == "number" and value >= 0 then
            categories[#categories + 1] = { name = name, value = value }
        end
    end
    table.sort(categories, function(a, b) return a.value < b.value end)

    local seen = {}
    for _, category in ipairs(categories) do
        local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category.value)
        if ok and type(cooldownIDs) == "table" then
            for _, cooldownID in ipairs(cooldownIDs) do
                local infoOK, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                if infoOK and info and info.charges == true then
                    -- overrideSpellID first, matching Blizzard's own
                    -- CooldownViewerItemDataMixin:GetSpellChargeInfo (live
                    -- branch, CooldownViewerItemData.lua) -- a talent-swapped
                    -- spell is probed as the version actually cast.
                    local chargeSpellID = info.overrideSpellID or info.spellID
                    if chargeSpellID and not seen[chargeSpellID] then
                        seen[chargeSpellID] = true
                        local nameOK, spellInfo = pcall(C_Spell.GetSpellInfo, chargeSpellID)
                        local name = (nameOK and spellInfo and spellInfo.name) or nil
                        out[#out + 1] = {
                            -- Queried by name where one resolved, per CLAUDE.md
                            -- §3 -- name doubles as the talent check and is
                            -- what the rest of the addon queries charge spells
                            -- by (BlizzBuffs.lua's DetectChargeSpell).
                            query = name or chargeSpellID,
                            label = name or ("ID " .. tostring(chargeSpellID)),
                        }
                        if #out >= 3 then return out end
                    end
                end
            end
        end
    end

    return out
end

--- Whether any of 12.1's new charge-adjacent APIs actually distinguish "a
--- charge is banked" from "no charge is banked" during combat is unknown, and
--- reasoning will not settle it -- DECISIONS.md §20. One combat sample
--- answers it; this is that sample.
---
--- Returns the candidate list, so ProbeDisplayPath can reuse the first one for
--- the duration-object setter test below -- probing the same spell twice from
--- two different angles is more useful than probing two different spells once
--- each.
local function ProbeCharges(lines)
    if not C_CooldownViewer then
        Record(lines, "charges", "C_CooldownViewer absent")
        return {}
    end

    local candidates = ChargeSpellCandidates()
    if #candidates == 0 then
        Record(lines, "charges", "no multi-charge spell found in Cooldown Manager")
        return candidates
    end

    for _, c in ipairs(candidates) do
        local label = c.label

        local chargesOK, chargeInfo = Raw(C_Spell.GetSpellCharges, c.query)
        Record(lines, ("charges %s"):format(label),
            chargesOK and Describe(chargeInfo) or ("ERROR: " .. tostring(chargeInfo)))
        Record(lines, ("charges.current %s"):format(label),
            FieldOf(chargesOK, chargeInfo, "currentCharges"))
        Record(lines, ("charges.max %s"):format(label),
            FieldOf(chargesOK, chargeInfo, "maxCharges"))

        -- Neither carries a SecretWhen* flag on live 12.1.0 build 69273
        -- (DECISIONS.md §20) -- MayReturnNothing is the only documented
        -- failure mode, and Sample/Describe already tell "nothing" apart from
        -- "secret" apart from "error".
        Record(lines, ("cooldownDuration %s"):format(label),
            Sample(C_Spell.GetSpellCooldownDuration, c.query, true))
        Record(lines, ("chargeDuration %s"):format(label),
            Sample(C_Spell.GetSpellChargeDuration, c.query))

        local usableDesc, insufficientDesc = SamplePair(C_Spell.IsSpellUsable, c.query)
        Record(lines, ("isUsable %s"):format(label), usableDesc)
        Record(lines, ("insufficientPower %s"):format(label), insufficientDesc)

        local cdOK, cdInfo = Raw(C_Spell.GetSpellCooldown, c.query)
        Record(lines, ("cd.isActive %s"):format(label), FieldOf(cdOK, cdInfo, "isActive"))
    end

    return candidates
end

--- Whether the sanctioned display path exists here, and whether the blessed
--- setters really do accept a secret from tainted code. Everything is fed the
--- genuine secret from UnitPower rather than a stand-in, because a setter that
--- accepts a plain number proves nothing.
---
--- `chargeQuery` is the first charge spell ProbeCharges found (its `query`
--- field, name-or-ID), used to obtain a real duration object rather than a
--- stand-in. Nil when no charge spell was found -- see the duration-object
--- block at the end of this function.
local function ProbeDisplayPath(lines, instanceID, chargeQuery)
    Record(lines, "issecretvalue", type(issecretvalue) == "function" and "present" or "absent")
    Record(lines, "C_CurveUtil", C_CurveUtil and "present" or "absent")
    Record(lines, "C_DurationUtil", C_DurationUtil and "present" or "absent")
    Record(lines, "EvaluateColorValueFromBoolean",
        type(C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean) == "function"
            and "present" or "absent")

    local powerType = select(1, UnitPowerType and UnitPowerType("player"))
    local gotPower, power = Raw(UnitPower, "player", powerType)
    local secretNumber = (gotPower and IsSecret(power)) and power or nil

    if secretNumber == nil then
        Record(lines, "blessed setters", "skipped -- no secret value to test with")
    else
        local widgets = P:EnsureWidgets()
        if not widgets then
            Record(lines, "blessed setters", "skipped -- test widgets unavailable")
        else
            Record(lines, "StatusBar:SetValue(secret)",
                SampleCall(widgets.bar.SetValue, widgets.bar, secretNumber))
            Record(lines, "Frame:SetAlpha(secret)",
                SampleCall(widgets.frame.SetAlpha, widgets.frame, secretNumber))
            Record(lines, "Cooldown:SetCooldownDuration",
                SampleCall(widgets.cooldown.SetCooldownDuration, widgets.cooldown, secretNumber))
            pcall(widgets.frame.SetAlpha, widgets.frame, 1)

            -- Expected to FAIL: Evaluate is AllowedWhenUntainted, so a tainted
            -- caller may not pass a secret x. Recorded anyway, because it is
            -- the difference between "curves can map our secrets" and "only
            -- Blizzard's own APIs can", and that shapes the resource ring.
            if C_CurveUtil and type(C_CurveUtil.CreateCurve) == "function" then
                local madeOK, curve = pcall(C_CurveUtil.CreateCurve)
                if madeOK and curve then
                    pcall(curve.AddPoint, curve, 0, 0)
                    pcall(curve.AddPoint, curve, 100, 1)
                    Record(lines, "Curve:Evaluate(secret)",
                        Sample(curve.Evaluate, curve, secretNumber))
                end
            end
        end
    end

    -- A secret BOOLEAN is the input the sanctioned show/hide primitive wants.
    -- This is the only place one is known to come from without first reading an
    -- aura, so it decides whether that primitive is reachable at all.
    if instanceID ~= nil then
        local hasOK, hasExpiry = Raw(C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime,
            "player", instanceID)
        Record(lines, "DoesAuraHaveExpirationTime",
            hasOK and Describe(hasExpiry) or ("ERROR: " .. tostring(hasExpiry)))

        if hasOK and IsSecret(hasExpiry) then
            Record(lines, "EvaluateColorValue(secret bool)",
                Sample(C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean,
                    hasExpiry, 1, 0))
        end

        Record(lines, "GetAuraApplicationDisplayCount",
            Sample(C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount,
                "player", instanceID, 2))
    end

    -- The highest-value measurement in this file. DECISIONS.md §20 reads
    -- (from Blizzard's source, never run) that the duration-object route may
    -- let ThugUI draw its own in-combat sweep for exactly the cells §19 had to
    -- hand to Blizzard's viewer -- SetCooldown refuses a secret startTime, but
    -- neither duration getter carries a SecretWhen* flag at all, so the
    -- object itself might never be a value that needs refusing.
    --
    -- Skipped entirely, not recorded as absent/nothing, when there is no
    -- charge spell to test with or the getter handed back nothing -- a line
    -- reading "skipped" every session is worse than no line, and this one is
    -- cheap to re-derive from the charges block above if it goes missing.
    if chargeQuery ~= nil then
        local gotDuration, duration = Raw(C_Spell.GetSpellCooldownDuration, chargeQuery, true)
        if gotDuration and not IsNothing(duration) then
            local widgets = P:EnsureWidgets()
            if widgets then
                -- Guarded on the method existing, not just handed to
                -- SampleCall, so this still loads on a client that predates
                -- the 12.1 duration-object API.
                if type(widgets.cooldown.SetCooldownFromDurationObject) == "function" then
                    Record(lines, "SetCooldownFromDurationObject",
                        SampleCall(widgets.cooldown.SetCooldownFromDurationObject,
                            widgets.cooldown, duration))
                end
                if type(widgets.bar.SetTimerDuration) == "function" then
                    Record(lines, "SetTimerDuration",
                        SampleCall(widgets.bar.SetTimerDuration, widgets.bar, duration))
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Which spells to ask about
-- ----------------------------------------------------------------------------

--- The aura-mode icons actually placed in the active spec, plus their linked
--- outcome buffs. Probing the real configuration is the point: a hardcoded
--- spell list would answer a question nobody asked.
local function AuraSpellIDs()
    local out = {}
    local CV = ThugUI.CooldownViewer
    local Data = CV and CV.Data
    if not Data then return out end

    local ok = pcall(function()
        local specID = Data.GetActiveSpecID()
        if not specID or specID == 0 then return end

        local profile = Data.GetProfile(specID)
        local seen = {}

        for _, placement in ipairs(Data.GetPlacements(profile)) do
            if placement.mode == "aura" and placement.spellID then
                if not seen[placement.spellID] then
                    seen[placement.spellID] = true
                    out[#out + 1] = placement.spellID
                end

                local info = Data.GetCooldownInfoForSpell(placement.spellID)
                for _, linked in ipairs(info and info.linkedSpellIDs or {}) do
                    if not seen[linked] then
                        seen[linked] = true
                        out[#out + 1] = linked
                    end
                end
            end
        end
    end)

    if not ok then return {} end
    return out
end

-- ----------------------------------------------------------------------------
-- Test widgets
--
-- Built once, hidden, never shown. Created outside combat where possible, and
-- pcall'd throughout: a probe that cannot make a StatusBar should report that
-- and carry on, not take the session down with it.
-- ----------------------------------------------------------------------------

function P:EnsureWidgets()
    if self.widgets ~= nil then return self.widgets or nil end

    local ok, widgets = pcall(function()
        local frame = CreateFrame("Frame", "ThugUI_SecretProbeFrame", UIParent)
        frame:SetSize(1, 1)
        frame:Hide()

        local bar = CreateFrame("StatusBar", nil, frame)
        bar:SetMinMaxValues(0, 1000000)

        local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")

        return { frame = frame, bar = bar, cooldown = cooldown }
    end)

    self.widgets = ok and widgets or false
    return self.widgets or nil
end

-- ----------------------------------------------------------------------------
-- Running one sample
-- ----------------------------------------------------------------------------

local function Store()
    ThugUI_DebugLog = ThugUI_DebugLog or {}
    ThugUI_DebugLog.secrets = ThugUI_DebugLog.secrets or {}
    return ThugUI_DebugLog
end

--- Take one sample and file it under `phase`.
---
--- A later fight overwrites an earlier one only when it saw at least as many
--- auras. A probe taken during a pull with nothing up is technically valid and
--- practically useless, and it must not be allowed to bury the sample that
--- caught the buff.
function P:Run(phase)
    local lines = {}
    local combat = InCombatLockdown and InCombatLockdown() or false

    Record(lines, "combat", tostring(combat))
    Record(lines, "captured", type(date) == "function" and date("%H:%M:%S") or "?")

    ProbePower(lines)
    ProbeAuraByID(lines, AuraSpellIDs())

    local seen = ProbeAuraList(lines)
    local instanceID = ProbeAuraInstances(lines)
    local chargeCandidates = ProbeCharges(lines)
    local chargeQuery = chargeCandidates[1] and chargeCandidates[1].query
    ProbeDisplayPath(lines, instanceID, chargeQuery)

    local store = Store()
    local previous = store.secrets[phase]
    if previous == nil or (previous.auras or 0) <= seen then
        store.secrets[phase] = { auras = seen, lines = lines }
    end

    if ThugUI.Diagnostics then
        ThugUI.Diagnostics:Log("SECRET", "sampled %s (combat=%s, auras seen=%d)",
            phase, tostring(combat), seen)
    end
end

--- Sample later, and only if the world still looks the way it did when this was
--- scheduled. A probe labelled "combat+5s" that runs after the fight ended
--- would be worse than no probe at all.
local function RunLater(delay, phase, requireCombat)
    if not C_Timer or type(C_Timer.After) ~= "function" then return end

    C_Timer.After(delay, function()
        if requireCombat and not (InCombatLockdown and InCombatLockdown()) then return end
        pcall(function() P:Run(phase) end)
    end)
end

-- ----------------------------------------------------------------------------
-- Wiring
--
-- Entirely automatic. Three samples inside combat rather than one, because the
-- buff being asked about is a proc with a duration -- a single sample at the
-- pull can easily land while nothing is up, and the difference between "the
-- API refused" and "there was no buff" is the entire question.
-- ----------------------------------------------------------------------------

local driver = CreateFrame("Frame", "ThugUI_SecretProbeDriver")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Fresh session, fresh answers. Stale samples from a previous build are
        -- exactly the kind of evidence that produces a confident wrong call.
        local store = Store()
        store.secrets = {}
        RunLater(5, "1-login-idle", false)
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        RunLater(1, "2-combat-1s", true)
        RunLater(5, "3-combat-5s", true)
        RunLater(12, "4-combat-12s", true)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- The most valuable single sample: the same buffs, on the same frame's
        -- worth of game state, with the restriction just lifted. Anything that
        -- reads here and not twelve seconds ago is restricted, not absent.
        pcall(function() P:Run("5-combat-ended") end)
    end
end)

return P
