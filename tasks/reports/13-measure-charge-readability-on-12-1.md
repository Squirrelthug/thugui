# 13 — Measure what 12.1 will tell us about a charge spell in combat — report

**Status:** complete

## What I changed

Added measurement only, to `modules/SecretProbe.lua`, wired into the existing
`P:Run` sampling pass (login-idle, three points inside combat, combat-ended —
unchanged). Nothing about which cells Blizzard adopts (`BB:ShouldAdopt`) or how
they render changed; this file has no write path into the cooldown viewer at
all, it only calls read-only `C_Spell`/`C_CooldownViewer` getters and records
what comes back.

Two additions, both following the existing `Describe`/`Sample`/`Record` shapes:

1. **`ProbeCharges(lines)`**, plus a helper `ChargeSpellCandidates()` that walks
   `Enum.CooldownViewerCategory` (real categories only, `value >= 0`, mirroring
   the filter in `CooldownViewer/Data.lua`) and every `cooldownID` in each
   category's set, keeping entries where `info.charges == true`. Reimplemented
   locally rather than calling into `Data.lua` — this is the diagnostics path
   and should not gain a dependency on the feature it exists to evaluate. Up to
   3 unique spells (deduped by `overrideSpellID or info.spellID`, matching
   Blizzard's own `CooldownViewerItemDataMixin:GetSpellChargeInfo`) are kept,
   each resolved to a display name via `C_Spell.GetSpellInfo` so the rest of the
   probe queries by name where one resolves — per `CLAUDE.md` §3, and matching
   how `BlizzBuffs.lua`'s `DetectChargeSpell` already queries charge spells.

   For each candidate, records `charges`, `charges.current`, `charges.max`,
   `cooldownDuration`, `chargeDuration`, `isUsable`, `insufficientPower`, and
   `cd.isActive` — exactly the table in the task file. If `C_CooldownViewer` is
   missing, or no charge spell is found, one line is recorded and the function
   returns without probing further.

   Two small helpers were added alongside `Sample`/`Raw`/`SampleCall`, in the
   same style: `SamplePair` (for `IsSpellUsable`'s two meaningful returns —
   `Sample` only keeps one) and `FieldOf` (reads one field off a struct that may
   itself be secret, absent, or an error, without ever writing a fresh `== nil`
   test — it goes through `IsNothing`/`Describe`, the same as every other probe
   in this file. Indexing into a possibly-secret struct is the exact thing
   `ProbeAuraList`'s `aura[1].spellId` already proved is allowed, so `FieldOf`
   just generalises that proof for `chargeInfo.currentCharges`,
   `chargeInfo.maxCharges`, and `cd.isActive`).

2. **The duration-object setter test**, appended to the end of
   `ProbeDisplayPath`, now taking a third parameter `chargeQuery` (the first
   charge spell `ProbeCharges` found — `P:Run` threads it through). If a
   candidate exists and `C_Spell.GetSpellCooldownDuration(chargeQuery, true)`
   returns something real (not nothing, per `IsNothing`), it calls
   `Cooldown:SetCooldownFromDurationObject` and `StatusBar:SetTimerDuration` on
   the existing test widgets with that duration object, through `SampleCall` so
   a refusal is recorded rather than thrown. Both lines are individually
   guarded on the method existing (`type(...) == "function"`) and skipped
   entirely — not recorded as "absent" — when it does not, so the file still
   loads on a client that predates the API. The whole block is skipped when
   there is no charge candidate or the duration getter returned nothing.

`P:Run` now calls `ProbeCharges(lines)` between `ProbeAuraInstances` and
`ProbeDisplayPath`, and passes the first candidate's `query` into
`ProbeDisplayPath` as `chargeQuery`.

## Files touched

| File | What |
|---|---|
| `modules/SecretProbe.lua` | Added `SamplePair`, `FieldOf`, `ChargeSpellCandidates`, `ProbeCharges`; extended `ProbeDisplayPath` with the duration-object setter test; wired both into `P:Run` |
| `Tests/loadtest.lua` | Added 4 cases to the `-- secret probe --` section (see below) |

## Verification

```
$ luac -p modules/SecretProbe.lua
$ luac -p Tests/loadtest.lua
(both silent — syntax OK)

$ lua Tests/loadtest.lua .
...
-- secret probe --
ok         records a sample with readable values
ok         a secret power value is described, not read
ok         a secret aura struct does not throw
ok         a missing API is reported, not fatal
ok         a thin sample never buries a rich one
ok         a charge spell's secret maxCharges is described, not read, and does not throw
ok         GetSpellCooldownDuration returning nothing is distinguishable from secret
ok         SetCooldownFromDurationObject line depends on the method existing
ok         no C_CooldownViewer records the fact and does not throw

0 failure(s)
```

Baseline before this task, confirmed by running the unmodified tree first:
**176 passing, 0 failures.** After: **180 passing, 0 failures** (`grep -c
"^ok"` on the run output). The count went up by exactly the 4 cases added, and
did not go down.

## Tests added

All 4 required cases, added (not repurposed — `git diff Tests/loadtest.lua`
shows only new lines, four new `{ ... }` entries appended before the closing
`}` of the `steps` table; nothing existing was edited). Each was run against
the **unmodified** `modules/SecretProbe.lua` (`git show HEAD:modules/SecretProbe.lua`
copied over the working file, tests run, then the real change restored) to
confirm it fails there first:

1. **"a charge spell's secret maxCharges is described, not read, and does not
   throw."** Adds a scratch Cooldown Manager entry (`cooldownID 8`,
   `spellID 8000`, `charges = true`) to the `Essential` category, sets
   `_G.__spellCharges[8000] = { maxCharges = SECRET, currentCharges = SECRET }`,
   runs the probe inside `pcall`, and asserts the `charges.max Spell 8000` line
   reads `SECRET ...`.
   Against the unmodified file: **`Tests/loadtest.lua:3208: a secret
   maxCharges was not described as secret:`** — the line never existed at all,
   since `ProbeCharges` doesn't exist yet.

2. **"GetSpellCooldownDuration returning nothing is distinguishable from
   secret."** Same scratch entry; stubs `C_Spell.GetSpellCooldownDuration` to
   return `nil` for one sample and `_G.__SECRET` for another, and asserts the
   `cooldownDuration Spell 8000` line reads `nothing` in the first and
   `SECRET ...` in the second.
   Against the unmodified file: **`Tests/loadtest.lua:3232: a nil duration was
   not recorded as nothing:`** — same reason, the line doesn't exist pre-fix.

3. **"SetCooldownFromDurationObject line depends on the method existing."**
   Written as a from-both-sides test, not just "missing skips it" — a version
   that always skips the line would pass a naive "missing skips it" check even
   with the whole feature deleted, which is exactly the kind of check that
   passes vacuously on old code. It runs the probe once with the method present
   (the harness's frame stub auto-synthesises every capitalised method as a
   no-op the moment it is *read*, so no setup was needed to model "present") and
   asserts the line **appears**; then forces it missing by overwriting the slot
   on the already-built test widget with `false` — a plain assignment sticks
   where the metatable's `__index` would otherwise re-synthesise a no-op on any
   read of a key not already on the table — and asserts the line is **absent**.
   Against the unmodified file: **`Tests/loadtest.lua:3278: the line never
   appeared even with the method present:`** — confirms this version really
   would have caught the earlier, weaker draft of this test (which only checked
   the "missing" direction and passed trivially pre-fix, since neither branch
   of unmodified code ever produced the line either way). That weaker version
   was caught and rewritten before being reported here, not shipped.

4. **"no C_CooldownViewer records the fact and does not throw."** Sets the
   global `C_CooldownViewer = nil`, runs the probe in `pcall`, restores it, and
   asserts a `charges` line reading `C_CooldownViewer absent`.
   Against the unmodified file: **`Tests/loadtest.lua:3294: did not record the
   missing API:`** — the unmodified `ProbeCharges` doesn't exist, so nothing
   was ever recorded under the `charges` label at all.

## Sources used

- `gh api repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua?ref=live`
  — confirmed the exact flags the task file quotes:
  `GetSpellCharges` carries `SecretWhenCooldownsRestricted = true`;
  `GetSpellCooldownDuration` and `GetSpellChargeDuration` carry neither
  `SecretWhen*` flag (only `SecretArguments = "AllowedWhenTainted"`, which is
  about what we may *pass in*, not what comes back) and both `MayReturnNothing`;
  `IsSpellUsable` carries `SecretArguments = "AllowedWhenTainted"` and no
  `SecretWhen*` flag, and is not documented `MayReturnNothing`.
- `gh api repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua?ref=live`
  — `CooldownViewerItemDataMixin:GetSpellChargeInfo` (line 385): `local
  chargeSpellID = info.overrideSpellID or info.spellID; ...
  C_Spell.GetSpellCharges(chargeSpellID)`. Confirms the precedence order and
  that Blizzard's own code queries by the resolved **spell ID**, not a name —
  see "Found to be wrong" below.
- `modules/CooldownViewer/Data.lua` (`CooldownViewerCategories`,
  `BuildCooldownInfoCache`) — the existing pattern for filtering real vs.
  negative pseudo-categories, mirrored rather than called into.
- `modules/CooldownViewer/BlizzBuffs.lua` (`DetectChargeSpell`,
  `BB:IsChargeSpell`) — the existing precedent for querying a charge spell by
  name where one resolves, falling back to ID.

## Proposed docs changes

**`DECISIONS.md` §20**, append a short note (not verified in game — see
below):

> **The probe now measures this — 2026-08-11.** `modules/SecretProbe.lua`
> gained `ProbeCharges`, which walks the Cooldown Manager for up to 3
> `charges == true` entries and records `GetSpellCharges`,
> `GetSpellCooldownDuration`, `GetSpellChargeDuration`, `IsSpellUsable`, and
> `GetSpellCooldown().isActive` for each, plus whether
> `Cooldown:SetCooldownFromDurationObject` and `StatusBar:SetTimerDuration`
> accept a duration object obtained from a charge spell mid-combat. Nothing
> below this line has been read from a real combat sample yet — see
> `tasks/reports/13-measure-charge-readability-on-12-1.md` for what the player
> needs to do to produce one.

**`docs/HANDOFF.md`**, queued-work entry:

> **One measurement is waiting to be read (task 13).** The next combat sample
> from a spec with a multi-charge spell (Outlaw/Grappling Hook or
> Resto/Swiftmend, see the task report) will show, in
> `ThugUI_DebugLog.secrets["2-combat-1s"|"3-combat-5s"|"4-combat-12s"].lines`,
> whether any of `GetSpellCooldownDuration`, `GetSpellChargeDuration`, or
> `IsSpellUsable` distinguish "a charge is banked" from "no charge is banked"
> during combat, and whether the duration-object route into
> `SetCooldownFromDurationObject`/`SetTimerDuration` is real. This decides
> whether the "charge spells can hide" feature (this branch) is worth
> building at all.

## Could not do

Nothing was blocked. One judgement call, not an ambiguity the task left open:
where to insert `ProbeCharges` in `P:Run` — the task says "call it ... alongside
the others, at every sample point" without specifying exact order. Placed it
between `ProbeAuraInstances` and `ProbeDisplayPath`, since `ProbeDisplayPath`
needs `ProbeCharges`'s output (the chosen `chargeQuery`) and nothing else in the
file depends on charge-probe output, so this was the only order that avoids a
forward reference.

## Noticed but did not touch

- **`CooldownViewerItemDataMixin:GetSpellChargeInfo` resolves an ID, not a
  name.** The task file's phrase "resolve a name for each via `overrideSpellID
  or spellID`... matching what Blizzard's own `GetSpellChargeInfo` does" is
  slightly loose: Blizzard's code takes that precedence to a numeric spell ID
  and calls `C_Spell.GetSpellCharges(chargeSpellID)` directly — it never
  resolves a name at all. I kept the *precedence* (`overrideSpellID or
  spellID`) exactly as specified, then added a separate name-resolution step
  (`C_Spell.GetSpellInfo` on that ID) so the probe's `C_Spell.*` calls go by
  name where one resolves, per `CLAUDE.md` §3 and matching
  `BlizzBuffs.lua`'s `DetectChargeSpell`. This is not a behavioural
  disagreement with the task, just worth flagging since "matching what
  `GetSpellChargeInfo` does" isn't literally true of the by-name step.
- `docs/DECISIONS.md` and `docs/UPCOMING-PATCH.md` were not re-read end to end
  beyond §19/§20 — out of scope for a measurement-only task, but worth
  someone's eventual look given §20 says "None of it has been run on the
  client yet" and this task is the first thing that runs any of it.
- `modules/SecretProbe.lua`'s module-level header comment (lines 1–37) still
  only describes the aura probe ("The pivotal line in the output is
  `aura[1].spellId read`..."). It is now slightly stale — there are two
  pivotal questions in this file, not one — but the task named exactly one
  file to change with a specific scope, and rewriting the header felt like
  scope creep for a coordinator to decide on, not an agent.

## Not verified

Everything here is unverified in game — this task cannot launch WoW:

- Whether `GetSpellCooldownDuration`, `GetSpellChargeDuration`, or
  `IsSpellUsable` actually distinguish "charge banked" from "charge spent"
  during real combat restriction. This is the entire question the task exists
  to measure, and it has only run against the test harness's stubs, which by
  construction cannot model 12.1's actual secrecy behaviour (only that the code
  doesn't throw and describes what it's given correctly).
- Whether `Cooldown:SetCooldownFromDurationObject` and
  `StatusBar:SetTimerDuration` genuinely accept a live duration object from
  ThugUI's tainted stack in combat, or refuse it the way `SetCooldown` does.
- Whether the category walk (`ChargeSpellCandidates`) actually finds the
  player's real charge spells on the live 12.1 client — the harness's
  `C_CooldownViewer` stub is hand-built and has never been cross-checked
  against a real `/thugcv probe` dump for `charges == true` entries.
- Whether resolving a name via `C_Spell.GetSpellInfo(chargeSpellID)` succeeds
  for every real charge spell the player has (it should, per the existing
  `DetectChargeSpell` precedent working for Grappling Hook, but that has not
  been re-confirmed for this code path specifically).

### What the player needs to do for a meaningful reading

**Spec:** anything with a currently-talented multi-charge spell. Two are
already documented as such: **Outlaw rogue — Grappling Hook** (`DECISIONS.md`
§19's original test case, confirmed "correct out of combat, wrong during it"
for the old `IsSpellReady` path) or **Resto druid — Swiftmend**, which
`DECISIONS.md` §20 records gained a second charge on 12.1's patch day and was
picked up automatically. Either works; the probe finds up to 3 `charges ==
true` entries at runtime regardless of spec, so no addon change is needed to
point it at a different one.

**In the fight:** the sample needs to catch the spell *mid-recharge*, not just
banked. `ProbeCharges` runs at every existing sample point (login-idle, 1s /
5s / 12s into combat, and the instant combat ends) with no new command needed.
For the reading to say anything:

1. Spend at least one charge of the chosen spell **within the first few
   seconds of a pull** — ideally spend it down to 0 charges banked, so the
   1s/5s/12s samples land while a recharge timer is actually running and not
   just idle at full charges (where every candidate API would trivially read
   "ready" regardless of whether any of them can see combat state at all).
2. **Stay in combat for at least 12 seconds** so the `4-combat-12s` phase
   fires — three combat samples exist because a single one can land on a
   moment with nothing informative happening, exactly as the header comment
   for the aura probes already explains.
3. Let combat end normally so `5-combat-ended` fires — this is the most
   valuable single sample, since it captures the same charge/cooldown state a
   few hundred milliseconds after the restriction lifts, giving ground truth
   to compare the in-combat samples against.
4. `/reload` (or log out) to flush `ThugUI_DebugLog` to
   `WTF/Account/SQUAZZIL/SavedVariables/ThugUI.lua`, then read
   `ThugUI_DebugLog.secrets["<phase>"].lines` for the `charges.*`,
   `cooldownDuration`, `chargeDuration`, `isUsable`, `insufficientPower`,
   `cd.isActive`, `SetCooldownFromDurationObject`, and `SetTimerDuration` lines.
   If any of `cooldownDuration`/`chargeDuration`/`isUsable` read as a plain
   value (not `SECRET ...`) during the mid-combat phases while a charge is
   known to be spent, that is the answer this task was built to get.
