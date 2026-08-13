# Handoff — state as of 2026-08-12 (evening)

## START HERE — main is clean, the radial resource ring is the next job

`charge-spells-can-hide` is **merged into `main` and pushed** (`c28b1a2`).
**195 passing, 0 failures.** Nothing is in flight, nothing is half-done.

The section below this one is the full account of what that branch did and why;
read it if you are picking up anything to do with charges, items, or secret
values. It is still accurate — it has just stopped being the current job.

### Built 2026-08-12, awaiting the player's eyes

Task 16 is **done and reviewed** — `DECISIONS.md` §23, report in `tasks/reports/`.
**201 passing, 0 failures**, six added and none removed against a clean tree, all
six confirmed to fail against the unmodified module. Uncommitted work: none.

**Two things need the player in game, and they are separable:**

1. **Does the radial ring look like the old one?** Flip `resourceRingRadialBar`
   on (Cursor Rings page) **at a mid-range resource level** — at 0% or 100% a
   start-angle mismatch is invisible. `StatusBar` has no `SetRotation`, so
   alignment is attempted by rotating the managed texture and nobody knows
   whether that moves the fill's start angle or only the artwork.
2. **Does the old ring track at all?** The player reported on 2026-08-12 that the
   Cooldown ring's colour follows shapeshift form while the level never moves.
   Their visibility is `always`, so this is happening out of combat too, where
   nothing is secret. `KNOWN-ISSUES.md`, "The resource ring may never have
   tracked at all". The suspect is `Pause()` being called after every
   `SetCooldown` with `Resume()` never called anywhere. **Unverified.**

**These two settle each other.** The radial path calls `Pause` nowhere, so if the
radial ring tracks and the Cooldown ring does not, the cause is the pause rather
than secrecy. Ask the player to compare them before writing any fix.

**Unanswered as of this writing:** whether the freeze happens out of combat, and
whether the player had reloaded while the agent was mid-edit (the working tree
held 182 lines of in-progress work for a while, so an early report may have been
of half-written code). Do not assume either.

### The job as originally framed: rebuild the resource ring on a radial StatusBar

Branch: **`radial-resource-ring`**. Chosen by the player 2026-08-12.

`KNOWN-ISSUES.md`, "Resource ring cannot show an exact level in combat", has the
whole story. The short version:

- The ring cannot show an exact level in combat today because a radial swipe
  comes from a `Cooldown` widget, and `Cooldown:SetCooldownDuration(secret)` is
  **refused** from tainted code. Measured twice, on 12.0.7 and again on 12.1.
- That measurement was right and **the conclusion drawn from it was wrong.**
  "A straight bar could show exact energy where a ring cannot" treated *radial*
  as a property of the `Cooldown` widget — which it was, at the time.
- **12.1 adds `StatusBarRenderMode.Radial`**, and `StatusBar:SetValue(secret)` is
  measured **accepted in combat** (`ThugUI_DebugLog.secrets`, 2026-08-11 21:05).
  A radial StatusBar is a ring, and it takes the value we are not allowed to read.

**This is a design change, not a bug fix.** Confirm the design with the player
before building — `CLAUDE.md` §3. The existing ring works and is in daily use;
breaking something that has worked for months is much worse than shipping this
slowly.

**Do not delete the current ring while building the new one.** Same rule as the
ECV/BCV/GCV fallback: it is the escape hatch if the radial mode misbehaves.

### Still open, unclaimed, in no particular order

- **`UPCOMING-PATCH.md` should be deleted.** 12.1 is live; the file still says
  *"Current live version: 12.0.7"* and is now actively misleading. `CLAUDE.md`'s
  own process says it goes on patch day, with anything still true moved into
  `DECISIONS.md`.
- **Does a charge spell in `cooldown` mode want a sweep toward its next charge?**
  Asked twice, never answered. It needs the `SetCooldownFromDurationObject`
  route, which is measured accepted mid-combat but unbuilt. Ask; do not assume.
- **The workaround panel's rewritten text has not been seen on screen.** Three
  passages were corrected 2026-08-12 and only render in game.
- **Potions and the healthstone.** `spellCategoryID` Cooldown Manager entries
  carry no spell ID at all and need a second placement kind. Blizzard's own
  source has a matching TODO (`CooldownViewer.lua:1018`).
- **oUF `portrait.lua`** truth-tests possibly-secret booleans at `:59`, `:63`,
  `:67`. The `guid` half is guarded; `isAvailable` is not. Whether it can throw
  depends on whether `UnitIsConnected`/`UnitIsVisible` are secret — unmeasured.
- **`QA.md` has never been run.**

---

# Handoff — state as of 2026-08-12 (the charge branch)

## Merged into main — the account of `charge-spells-can-hide`

**You are not on `main`.** Three commits sit above it and a fourth change is in
flight. `main` is untouched and still good.

### The one-line story

12.1 landed. The player reported two charge-spell bugs, the cause turned out to
be a rule the addon had adopted from a measurement that the patch invalidated,
and this branch is the re-measurement plus the fixes that fall out of it.

### What is on the branch

| Commit | What |
|---|---|
| `a8a7451` | `SecretProbe` extended to sample charge spells at five points around combat |
| `f725603` | **The player ran it through a real fight.** Results in `DECISIONS.md` §20, "Measured — one combat, 2026-08-11 21:05" |
| `5c05183` | Task 14 — item-backed cells (the trinket bug) and the new `recharging` mode. 189 passing |

### The measurement is the important thing on this branch

Read `DECISIONS.md` §20's "Measured" subsection before touching anything here.
It corrected two things §19 and §20 had asserted from Blizzard's generated
documentation, and everything queued below depends on it. The headlines:

- `SetShown(secret)` is **refused**; `SetAlpha(secret)` is **accepted**, at every
  phase including mid-combat. Alpha clamps to 0–1 and `currentCharges` is a
  secret 0/1/2, so `icon:SetAlpha(currentCharges)` hides a spent charge spell
  **with no comparison** — and comparison is the operation that throws.
- `SetCooldownFromDurationObject` and `SetTimerDuration` are **accepted**
  mid-combat, in the same sample where `SetCooldownDuration(secret)` is refused.
  §19's "we cannot sweep in combat" is lifted. It was never the sweep that was
  forbidden, only the route to it.
- `maxCharges` is **not** secret in combat. `BB:IsChargeSpell`'s
  out-of-combat-only cache guards against something that does not happen.
- `IsSpellUsable` cannot answer "is a charge banked" — it tracks target validity
  and form. Readiness-by-absence is dead too: both duration getters return an
  object even at full charges, idle.

### Task 14's trinket fix was broken and is now fixed — RE-TEST NEEDED

**The player tested it 2026-08-12 and reported the original symptom unchanged:
only `always` mode draws the trinket.** Diagnosed and fixed the same day —
`DECISIONS.md` §22. `ItemLocation:CreateFromEquipmentSlot` is declared with a
colon, our call omitted the `ItemLocation` argument, and the result was a silent
`false` from `IsItemAvailable` for every item cell rather than an error.

**This needs the player to look again**, and it is the top in-game item:
put **Radiant Blessing** (cell 7:1 on resto, spell 1254624, trinket slot 13) into
**`cooldown` mode** and confirm it draws. `always` mode was never affected and is
not a test of this.

The harness could not have caught it and now can — the `ItemLocation` stub was
written to match our caller instead of Blizzard's declaration, so eight cases
were green over a path that could not work. Four of them now fail against the old
call. `Tests/replay_probe.lua` was separately stale and gave a **confidently
wrong** diagnosis; it now derives its category list from the dump.

**Carry this forward:** three harness defects have each hidden a real bug behind
green output. When a fix calls a Blizzard API we have not called before, the
harness is not evidence — only the game is.

### Task 15 has landed — and is VERIFIED IN GAME, 2026-08-12

**The player tested it: the spell hides when spent, and the cell does not
collapse.** Both halves are exactly what §21 predicted, and the player accepted
the non-collapsing cell explicitly rather than having it fixed. It is written up
in `KNOWN-ISSUES.md` as a measured limit, not as a defect awaiting work — **do
not re-open it** and do not offer a workaround; one was already proposed by the
player, examined, and rejected on evidence.


`DECISIONS.md` §21. **195 passing, 0 failures.** Built by a Sonnet agent against
`tasks/15-charge-spells-hide-when-spent.md`; report in `tasks/reports/`.

What it does:

1. `BB:ShouldAdopt` stops returning `IsChargeSpell(icon)` on the fallthrough.
   Charge spells in `cooldown`/`proc` mode come back to us. `aura` and `always`
   still adopt.
2. `IsSpellReady` gains a **third return: a value always safe to hand to
   `SetAlpha`** — `1` in every case, the secret `currentCharges` on the one
   fail-open path. Never nil, deliberately, so the caller never has to test it.
3. `cooldown` and `proc` modes apply that alpha. Alpha is reset to `1` once per
   icon at the top of the `UpdateState` loop — icons are pooled and a stale
   alpha 0 would follow the frame to the next spell.

**What the player should test in game:** a two-charge spell in `cooldown` mode —
**Mangle on the Guardian druid** is the case this started from, Swiftmend on
resto is the other. Spend both charges in combat and the icon should vanish; it
should come back as a charge recharges. Out of combat it should behave exactly as
it always has, including the column closing.

Two review notes worth carrying, both mine rather than the agent's:

- **Two existing tests asserted the removed behaviour**, not the one the task
  file predicted. `"a charge spell in cooldown mode is adopted from the utility
  bar"` was **deleted** — the behaviour it asserted is gone on purpose, so there
  was nothing left for it to be true about. Its neighbour inherited its setup and
  kept passing while asserting something about a cell that was no longer adopted;
  it is now self-contained and tests `always` mode. Both are called out in
  `Tests/README.md` under "Hazards in the harness itself". The agent correctly
  refused to touch either and reported the conflict.
- **`BB:IsChargeSpell` and its cache are now dead code**, deliberately left in
  place. §20 measured that its out-of-combat-only caching guards against
  something that does not happen, so if it is ever revived it should be
  simplified to `info.charges` from the Cooldown Manager. Removing it is an open,
  unclaimed call.

**The accepted cost, confirmed by the player 2026-08-12: alpha zero is not
hidden.** The cell keeps its space and its column will not collapse around it
during combat. Making it collapse would need `icon.wanted` set from a secret,
which is a branch on a secret. The player considered a 1px parking frame and
accepted the gap instead so patch-day work could move. **Do not re-open this** —
and note the client refuses `SetShown(secret)` while accepting `SetAlpha(secret)`
seconds apart, which reads as a deliberate line: visual change yes, layout change
no. Out of combat nothing is secret and collapse works normally, so the gap is
combat-only and bounded to the window between spending the last charge and the
first recharge landing.

### Queued next, in order

1. **The in-combat sweep** — `ApplySweep` moves to
   `SetCooldownFromDurationObject`, measured accepted mid-combat. It would make
   `always` mode sweep during combat and so remove the only reason `always` mode
   is adopted at all. Measured possible, **not designed, and not yet wanted by
   the player** — see the question left open below. Not started.
2. **Task 16, probe extension** — deliberately *not* run in parallel with task 15
   because both would touch `Tests/loadtest.lua`. Would measure whether a truth
   test on a secret throws, and whether `SetSize`/`SetScale`/`SetPoint` accept
   one. Only worth doing if the collapse gap is ever re-opened; the player has
   accepted it, so this is low priority now.
3. **Potions and the healthstone** — `spellCategoryID` Cooldown Manager entries
   have no spell ID at all and need a second placement kind. Task 14 explicitly
   refused to start it.

### The original bug report — both halves resolved, one into a question

From 2026-08-10, both on charge spells:

- **Grappling Hook (Outlaw) disappears when both charges are spent** — cause
  found, **fixed by task 15**. Charge spells were adopted by Blizzard's frame
  because `IsSpellReady` fails open on secret charges.
- **"Maul (Guardian) draws but never sweeps"** — **not a bug, and not Maul.**
  Confirmed against the player's SavedVariables on 2026-08-12: Maul is not placed
  on the Guardian grid at all, and the spell meant was **Mangle (33917)**. Every
  Guardian placement is in `cooldown` mode, which is *defined* as having no
  sweep — the icon is the readiness signal. `DECISIONS.md` §21. **The player
  confirmed 2026-08-12 that it was Mangle all along**; the Maul thread is closed.

### The one question left open for the player

Asked on 2026-08-12 and **not answered** — do not assume an answer, and do not
build on a guess. Now that a spent charge spell hides itself, what should a
two-charge spell in `cooldown` mode look like?

1. **Hide when spent, no sweep** — exactly what task 15 built, nothing more.
2. **Hide when spent, and sweep toward the next charge** — needs queued item 1,
   the `SetCooldownFromDurationObject` route. This is the closest reading of what
   "no radial cooldown sweep" was originally complaining about.
3. **Leave `cooldown` mode alone** and use `always` mode where a sweep is wanted,
   accepting that `always` is adopted and so does not hide when spent.

The player's stated priority on 2026-08-12 was momentum — *"get the rest of the
patch day kinks worked out"* — so ask this once, in passing, rather than blocking
on it.

---

# Handoff — state as of 2026-08-10

## Superseded: "Maul is the next job"

### 1. Repo state: clean, everything merged and pushed

`main` carries all of this session's work and is level with `origin/main`.
Harness: **165 passing, 0 failures**. Nothing is in flight.

The feature branches (`collapse-anchor-boundary`, `abundance-icon-scale`,
`raidframes-test`) are all merged or scratch and can be deleted whenever; they
are left only as a trail.

**Nothing is half-done.** Start on §2.

### 2. The open bug: Maul on the Guardian druid

Reported, **not diagnosed**, nothing written for it yet:

- **Maul (Guardian)** draws its icon but **no radial cooldown sweep**, and it has
  **two charges**.
- **Grappling Hook (Outlaw)** is a two-charge spell that **disappears entirely
  when both charges are spent**.

The player suspects a common cause in how charges are handled and asked to take
them one alt at a time, Guardian first. Nothing in `Data.lua` or `Core.lua` has
been read with charges in mind yet — treat this as unstarted.

Start from `DECISIONS.md` §5, "Spell readiness: never from duration" — charge
state is adjacent to that logic and the rules there (`isActive`/`isOnGCD`, never
`startTime`/`duration`, query by name) constrain any fix.

### 3. What changed this session, and what is verified

| Change | Where | State |
|---|---|---|
| Raid frames module deleted entirely | `main` | Verified — the module was already inert (`rfEnabled = false`) |
| Adopted buffs scale correctly on scaled profiles | `main`, `DECISIONS.md` §17 | **Verified in game** by the player on resto |
| `docs/QA.md` — pre-release in-game checklist | `main` | New file, nothing run against it yet |
| Auto collapse direction now reads the placements | `main`, `DECISIONS.md` §18 | **Verified in game** by the player |

## Things that cost time this session — do not rediscover them

**SavedVariables line numbers are void the moment the game runs.** WoW rewrites
that file at every logout. Line numbers read in one session pointed at a
different profile in the next, and a conclusion was stated confidently off the
wrong block ([102] Balance mistaken for [105] Resto). Re-derive positions from
the current file, every time, and prefer loading the file in Lua over grepping
it — the nesting makes a flat grep genuinely ambiguous.

**`sed -i` is not byte-safe on SavedVariables on Windows.** It silently stripped
all 1,660 carriage returns from `ThugUI.lua`. Harmless as it happened, but that
file makes the game discard *every* ThugUI setting if it is malformed. Check the
byte count against the expected delta afterwards, not just that it parses.

**Profiles are per-spec and account-wide.** `## SavedVariables`, no
`SavedVariablesPerCharacter`. The player has **two resto druids — Eowyn and
Ixloatel — that share one profile** and cannot be configured apart. This is a
real design limitation, is recorded in `QA.md` §2, and needs a decision before
anyone else uses this addon.

**The player scaled their UI up and down to test the §17 fix.** The fix is
designed to be UI-scale independent (it divides two `GetEffectiveScale()`
values), but that is reasoning, not evidence, and `QA.md` §1 exists to make it
evidence.

## Newest first: the raid frames are gone

`modules/RaidFrames/` and `ui/pages/RaidFrames.lua` are deleted, with every
reference — 27 `rf*` defaults, the Blizzard subpanel, the config page, the
feature rows. `DECISIONS.md` §16.

They existed to solve exactly one problem: the tooltip that popped when the
player moused over their own buff icons in the cells of Blizzard's default raid
frames. That is now handled **outside ThugUI**, so the module was paying for
something already solved, and this addon does not want to be in the unit-frame
business.

**It was a no-op and that was verified, not assumed.** `rfEnabled` was already
`false` in the live SavedVariables, so nothing had been drawing — the bar for
the diff was zero visible change. Harness went 160 → **156 passing, 0 failures**;
the four that went are file-load and page-load assertions that `loadtest.lua`
derives from the TOC, confirmed by diffing `ok` lines against a stashed clean
tree rather than by trusting the count.

**If the tooltip ever comes back, do not look in ThugUI for the fix.** There
isn't one and there hasn't been since `0c2d4e2` — `FrameHider:FixTooltipAnchor`
was deleted then and never replaced. The note at `modules/FrameHider.lua:70` now
records that history so nobody re-derives it.

The trap worth carrying: **not every `rf` prefix is a raid frame.** The
`rfCorner*`/`rfScale*` locals in `EssentialRings_Settings.lua` (~946–1180) are
*Reforestation* controls on the legacy ECV panel. A blind `rf*` sweep would have
gutted the fallback bars. `libs/oUF/` also stays — Target of Target is built on
it too.

## The buff feature is finished, and the picker was lying

**Verified in game by the player 2026-08-09:** an adopted buff draws in its cell
*and* the column collapses when the buff is down. The long-standing "adopted
cells are reserved forever" cost is gone — `DECISIONS.md` §13, "Their frame's
visibility is the buff state we were told we could not have". The short version
is worth carrying anywhere: **§12 proved the aura APIs cannot answer "is this
buff up"; that got generalised into "we cannot know", and that was wrong.**
Blizzard's item hides itself, and reading a frame's shown state is not reading an
aura.

Built since, **none of it seen in the game**:

- A workaround guide panel down the right of the config window, nine steps
  cut to seven, with the player's own screenshots. `ui/pages/CooldownViewerGuide.lua`.
  **WoW does not load PNG** — the `.tga` files beside them are what the game
  reads, generated on 512×512 power-of-two canvases, so every one needs
  `SetTexCoord` or it draws the transparent padding.
- The "Use Blizzard's buff frames" checkbox moved out of the main window and
  into that panel.
- `Clear this layout` now asks first.
- The picker stopped offering buff rows that can never draw (see below), and
  stopped greying a spell placed as a cooldown when you are looking at buffs.

**One measurement is waiting to be read.** `BB:Apply` logs
`blizzbuffs-shown-readable-<combat>` once per session per combat state. If the
`combat=true` line says *readable*, Blizzard's frame visibility is a live
buff-active signal that survives combat — new ground, and reusable well beyond
the cooldown viewer. Read it before assuming either way.

### The picker was offering ~20 rows that could not work

It expanded each buff entry's `linkedSpellIDs` into rows of their own. Removed.
Adoption maps **one Blizzard frame per `cooldownID`** and every linked ID shares
its base entry's, so five cells could only ever draw one icon — the player tested
exactly that. `DECISIONS.md` §13. Four of those rows appeared under a *different
name*, which read as a separate buff rather than a duplicate.

### The test harness was hiding its own coverage

Every section after the first was gated on `failures == 0`, so **one early
failure silently skipped four whole sections** while still printing a plausible
short report. Coverage vanished exactly when something was known to be broken.
Every case already runs under `pcall`, so the guard never protected anything.
Removed, and verified by injecting a deliberate failure.

Current baseline: **160 passing across six sections, 0 failures.**

Three separate harness defects were found this way — by agents doing unrelated
work and reporting them rather than fixing them (`GetChecked` returning a
constant, `Panel:Button` never registering onto `panel.widgets`, and this). The
harness is due a pass of its own rather than another accident.

---

# Handoff — state as of 2026-08-09

Cold-start entry point. Read this, then `../CLAUDE.md`, then
`DECISIONS.md`.

**The cooldown viewer is finished, running, and verified in game.** Buff icons
draw in their assigned cell during combat, count down, and re-attach when the
buff is recast; Blizzard's Cooldown Manager is no longer damaged by us. Sessions
116–117 are clean. Treat that whole feature as working code, not as an
investigation in progress.

## Read this first: there is one open thread

The last batch of work shipped **four changes that no one has yet seen in the
game**, and one of them is a fix for a bug the player reported and has not
confirmed fixed. Nothing here is verified in game. Do not let a later reader
assume otherwise, and do not mark any of it verified yourself — only the player
can do that.

**The unfinished job, in one line:** the player placed **Opportunity** in
`aura` mode, it vanished from Blizzard's default tracked-buff bar (so ThugUI
adopted it) and never appeared in the grid. The cause was found and fixed —
`DECISIONS.md` §13, "That invariant was stated here and not actually enforced" —
but the fix is proven only in the test harness.

**What to do about it, in order:**

1. Ask the player to `/reload`, set Opportunity to **"show while buff active"**
   (it was last saved as `mode=proc`, so the adoption path will not even run
   otherwise), fight something, and `/reload` again to flush the log.
2. Read `ThugUI_DebugLog`. It now says which stage failed instead of going
   quiet — see §1.
3. **A second fault is still unexplained.** In the session of 2026-08-10
   02:30:21, `BlizzBuffs` demonstrably adopted an item, yet the
   `blizzbuffs-adopted` line at the bottom of `BB:Apply` never fired all
   session. Something in `Apply` was failing partway through, every pass, and a
   bare `pcall` was discarding the error. That `pcall` now records the message
   (`CVBUFF: Apply failed: …`). **If that line appears in the next log, that is
   the answer to a question this project has not been able to ask.** It may or
   may not be related to the Opportunity bug; treat them as separate until the
   evidence joins them.

The table in §2 is still the honest map: it separates what has been **confirmed
in the running game** from what is only **correct in code**. Keep it that way —
saying which of the two a thing is in, out loud, is what stopped a wrong
conclusion being stated confidently for a third time. §1 says how to check from
disk.

---

## 1. Check the evidence before doing anything

Two files on disk, both flushed only on `/reload` or logout:

```
WTF/Account/SQUAZZIL/SavedVariables/ThugUI.lua        settings + ThugUI_DebugLog
WTF/Account/SQUAZZIL/SavedVariables/!BugGrabber.lua   errors, stacks, locals
```

`ThugUI_DebugLog` is **always on** — no command needed. It has:

- `events` — per-session log (login, spec changes, cooldown cache size,
  migration results, once-only warnings)
- `state` — snapshot taken at logout, listing every placed icon as
  `cell  name  id=  mode=  linked=N  cat=`
- `CVBUFF:` lines — what Blizzard's buff-item adoption did. Added 2026-08-09
  because its failures used to be silent:

  | Line | Means |
  |---|---|
  | `adopted N Blizzard buff item(s)` | it worked, N cells are carrying a Blizzard item |
  | `no Blizzard buff item frames found` | the Cooldown Manager itself has nothing to adopt |
  | `spell X: no matching item frame — buff is not in Tracked Buffs or Tracked Bars` | **the common one, and the player can fix it.** The buff must be in one of the game's two active lists |
  | `spell X: no Cooldown Manager entry` / `entry has no cooldown ID` | our lookup failed, not the player's settings |
  | `Apply failed: …` | `BB:Apply` threw. See the open thread above — this line has never yet been seen and is expected to be informative |

**`linked=N` is the field that matters.** It is evidence of which code actually
ran. A version string tells you what is on disk; that number tells you what
executed. It exists because a fix was once pushed, not loaded, and the
behaviour was indistinguishable from the fix not working — a wrong conclusion
was reached and stated confidently. Do not repeat that.

Also: `lua Tests/replay_probe.lua <sv-path> . <spellID>` replays a real
`/thugcv probe` dump through the live code, which separates "our logic is
wrong" from "they were on an older build".

## 2. What is verified, and what is not

| Feature | State |
|---|---|
| Config window, pages, grid editor | **Verified** — in use |
| Per-spec grid, drag/click placement, anchor picker | **Verified** |
| Druid migration (Balance 102, Guardian 104, Resto 105) | **Verified** — player confirmed |
| Rows collapse | **Verified** |
| Proc glow + `proc` mode | **Verified** — "pistol shot is working" |
| Roll the Bones via `linkedSpellIDs` | **Verified in game** 2026-08-09 — `4 linked, active via 1214933` |
| Taint fix (ToT mover deferral) | **Held, but irrelevant to secrets** — see §3 and `DECISIONS.md` §12 |
| Secret probe (`modules/SecretProbe.lua`) | **Ran 2026-08-09** — results in `DECISIONS.md` §12 |
| Combo pips | **Verified in game** 2026-08-09 — and they track live *in combat*, which was not expected |
| Blizzard buff items in grid cells (`BlizzBuffs.lua`) | **Verified working in game** 2026-08-09 — buff draws in the assigned cell, in combat, and counts down correctly |
| Taint export into Blizzard's cooldown viewer | **Fixed and verified in game** 2026-08-09 — long combat test with re-application, BugGrabber sessions 116–117 clean. `DECISIONS.md` §15 |
| Resource ring exact level in combat | **Permanently impossible** — measured. Energy is secret to addons and no blessed setter takes a secret for a radial swipe. A straight bar could; a ring cannot |
| Columns / both collapse | **Unverified in game** |
| Window layout reorganisation | **Unverified visually** |
| Always-on diagnostics | **Verified, after two faults were fixed** — see §3a |
| Category iteration for 12.1 (`Data.lua`) | **Unverified in game** — no client has the new categories yet, so the new-category path is proven only against a stub. The negative-fake filter *does* change behaviour on 12.0.7. `DECISIONS.md` §8 |
| `BlizzBuffs` failure logging | **Unverified in game** — logging only, cannot change behaviour. `DECISIONS.md` §13 |
| Adopted cell reserved regardless of `IsSpellAvailable` | **Verified in game** 2026-08-09 — the Opportunity fix. The buff draws in its cell |
| Adopted cell collapses when the buff is down | **Verified in game** 2026-08-09 — player confirmed the column now closes. `DECISIONS.md` §13 |
| Is Blizzard's `IsShown()` readable in combat? | **Measured but unread** — `BB:Apply` logs `blizzbuffs-shown-readable-<combat>` once per session per combat state. Read it before assuming either way |

Everything unverified has test coverage; tests prove it does not error and the
logic is right, not that it looks right on screen.

## 3. Closed: secret values, and why taint was a dead end

**Answered 2026-08-09. Do not chase the taint again.** The full
reasoning and the evidence are in `DECISIONS.md` §12; the short version:

Addon code always executes tainted by its own addon, so there is no untainted
state to reach and nothing to clean. `!BugGrabber.lua` shows four addons all
reporting "tainted by *themselves*" — they are the four that touch secret
values, not the four that are dirty — and Blizzard's generated docs flag the
**APIs**: `GetUnitAuraBySpellID` carries `RequiresNonSecretAura` (so it returns
nothing in combat) and `UnitPower` carries `SecretWhenUnitPowerRestricted`.

The buff icon and the ring were never broken by anything we did. A tainted
addon is not meant to be able to answer "is buff X up" in combat.

`modules/SecretProbe.lua` measured exactly what this client hands us, at five
points around combat, with no command to type — it **ran on 2026-08-09** and the
results are the table in `DECISIONS.md` §12. It is still installed and still
samples every session, so re-reading `ThugUI_DebugLog.secrets` after a patch is
a free way to see what changed.

The decisive line was `aura[1].spellId read`: the struct **can** be indexed and
the field **is** reachable — as a secret, and comparing it errors. So there is
no route to identifying a buff in combat from addon code, and Blizzard's own
frames were the only option left. That is what `BlizzBuffs.lua` now does, and it
works — see §3b.

The historical account below is kept because it explains how the wrong
conclusion was reached, and the description of behaviour *while* restricted is
still accurate.

`UnitPower` was returning a **secret number**, so the resource ring could not
compute a fill level:

```
attempt to perform arithmetic on local 'current' (a secret number value,
while execution tainted by 'ThugUI')
```

The wording says the secrecy follows **taint**, not a blanket restriction. A
taint source was found and fixed: `ToT:UpdateMoverGeometry` resized the ToT
mover while the protected oUF unit button was anchored to it, which is blocked
in combat, and the block taints the addon for the session. Both mover paths now
defer out of combat.

**Answered 2026-08-09: it did not work, and it never could have.** The line is
present 5 seconds into a fresh session, before any combat:

```
[00:34:46] RING: UnitPower unreadable (secret value) for ENERGY
           — addon is tainted; resource level cannot be computed
```

That is inherent taint, not a trace, and no mover fix was ever going to change
it. Where the three loose ends from that theory actually landed:

- **The ring** stays unable to show an exact level in combat, permanently.
  `UnitPower` carries `SecretWhenUnitPowerRestricted` for *primary* resources.
  Not a bug, not fixable — `KNOWN-ISSUES.md`.
- **The pips** were never blocked at all. Secondary resources are readable in
  combat on 12.0.7 (`UnitPower combo 1, max 7`, measured mid-fight), and the
  pips are verified tracking live.
- **The ToT mover fix held** — `ADDON_ACTION_BLOCKED` for
  `ThugUI_TargetOfTargetMover:SetSize()` has not recurred since session 82.
- **oUF `portrait.lua:46` is a real bug, but an ordinary one.** It performs a
  boolean test on a secret boolean. oUF is vendored under our name so it reports
  as ours, and per §12 that means *addon code touching a secret* — it wants a
  defensive read, not a taint hunt. Small, unclaimed, and safe to pick up.

The taint we were genuinely exporting was elsewhere entirely, and is fixed:
§3c and `DECISIONS.md` §15.

### 3a. The diagnostics themselves were broken until 2026-08-09

Worth knowing, because it invalidates earlier conclusions drawn from silence:

- The state snapshot was taken **only at `PLAYER_LOGOUT`**, when
  `GetSpecializationInfo` already returns 0. Every snapshot ever written
  described an empty `Spec 0` profile with no icons, so `linked=N` — the field
  this page calls load-bearing — had never once been recorded. Now captured on
  `PLAYER_REGEN_ENABLED` / `PLAYER_ENTERING_WORLD`, and a capture with an
  unreadable spec cannot overwrite a good one.
- `/thugcv status` printed to chat only. WoW's `/chatlog` does **not** capture
  it: that logs chat *events*, and `print()` writes to the frame without firing
  one. Status output now also goes to `ThugUI_DebugLog`.

An empty `ThugUI_DebugLog` before this date means "not loaded or not captured",
never "nothing happened".

Both faults are fixed, and the diagnostics have been load-bearing ever since —
every conclusion in §3c was reached by reading them.

## 3b. Buff icons in combat — SOLVED, by using Blizzard's frames

ThugUI's *own* aura icons still cannot draw in combat and never will: the game
will not tell an addon which aura is which while restrictions are in effect. The
by-spell lookups return nothing (`RequiresNonSecretAura`), the list returns
secret structs, and `aura.spellId` can be read but not compared. That part is
permanent and is not worth another session.

**What works instead, verified in game 2026-08-09:**
`modules/CooldownViewer/BlizzBuffs.lua` matches each aura-mode placement to the
item frame carrying the same `cooldownID` and anchors it over the cell. The buff
draws in the right place, during combat. `DECISIONS.md` §13 has the design and
the constraint the player has to satisfy for it to work (the buff must be in the
Tracked Buffs or Tracked Bars list — a bar lands in the cell as an icon plus its
animation, an icon lands as an icon plus a timer; both fit one cell, and the
player likes the bar visual as-is and does not want it enlarged).

The plan that got here, for the record:

1. ~~**Probe**~~ — ran 2026-08-09. Results in `DECISIONS.md` §12.
2. ~~**Adopt Blizzard's buff frames**~~ — built and working, one item per cell.
3. ~~Fall back to flagging the icons as combat-unavailable~~ — not needed.
4. ~~**Combo point pips**~~ — built and verified, and they track live in combat.

**The former remaining cost, now fixed:** an adopted cell used to be reserved
permanently, buff up or not, so a column holding one never closed. The premise
was wrong — Blizzard's item hides itself when the buff drops, and reading a
frame's shown state is not reading an aura. `CV:UpdateState` now asks their frame
first, our aura lookup second, and reserves only when neither can answer.
**Verified in game 2026-08-09** by the player: the buff draws and the column
collapses. `DECISIONS.md` §13, "Their frame's visibility is the buff state we
were told we could not have". And Edit Mode breaks — §3c.

## 3c. Edit Mode windows vanish — CLOSED 2026-08-09

**Verified fixed in game.** Reasoning and stacks: `DECISIONS.md` §15. Keep the
one-line lesson even if you never read the rest: **an error inside a *Blizzard*
file that names ThugUI means we exported taint into their frame.** §12's "that
just means it is addon code" applies only when the erroring file is ours.

Two sources, both fixed: `ER:CreateECV()` had created its bar under Blizzard's
own global name `EssentialCooldownViewer` (from the first commit — the collision
arrived in a patch, not a commit); and `BlizzBuffs.lua` wrote `__thug*` fields
onto their frames, set strata on their Edit Mode system frame, and called their
`RefreshLayout` from our stack.

Proof, not impression: BugGrabber sessions 113 and 115 carried runaways of 534
and 1160 errors inside `Blizzard_CooldownViewer`; sessions 116 and 117, after
both fixes and through a long combat test with the buff expiring and being
re-applied, recorded **zero errors of any kind**.

`anchorBuffFrameToCursor` was checked and is **off**, so `EssentialRings.lua:926`
was never part of this.

## 4. Queued work

**Combo point pips** — **built 2026-08-09**, `modules/ComboPips.lua`, off by
default. Controls are on the Cursor Rings page.

- N pips evenly spaced around the cursor ring, lit as points are gained.
- Chosen over a segmented arc because a changing max (Deeper Stratagem, procs)
  falls out for free, and per-point colour is needed for DK runes.
- Covers combo points, Holy Power, Soul Shards, Chi, Arcane Charges, Essence.
  Which resource comes from a class table mirroring oUF's `classpower.lua`, but
  the per-spec conditions are deliberately *not* copied: `UnitPowerMax` returns
  0 for a spec without the resource, so gating on the maximum is self-
  correcting. The druid is the one exception and uses oUF's test (primary power
  is energy ⇒ cat form).
- Not covered: DK runes (per-rune cooldowns, different widget) and oUF's
  aura-backed pseudo-resources (Hunter, Shaman, Devourer) — those read auras,
  which is the thing addons cannot do in combat.
- **Live behaviour depends on the patch.** Secondary resources are secret on
  12.0.7, so in combat the pips freeze at their last count; 12.1 is expected to
  make them readable and the same code then tracks live. Verified in the test
  harness both ways; **unverified in game**.

**The tracked-buff note — built 2026-08-09**, on the Cooldown Viewer page under
"Use Blizzard's buff frames". The buff icon only appears if that buff is in one
of the game's two *active* Cooldown Manager lists, and which list decides what it
looks like:

| List | What lands in the cell |
|---|---|
| **Tracked Buffs** | icon with a countdown timer |
| **Tracked Bars** | icon with an animated bar beside it |
| Neither | nothing to adopt — the cell stays empty |

It is a visible note, not a tooltip, because the failure is silent: the picker
offers buffs that are in neither list, and an empty cell looks exactly like a
broken addon.

**ThugUI will not add them to those lists for you**, and that was checked rather
than assumed — `C_CooldownViewer`'s only write is `SetLayoutData`, an opaque blob
holding the entire layout. `DECISIONS.md` §15 has why both routes are worse than
the manual step.

**Category enumeration for 12.1 — done 2026-08-09.** The three hardcoded
category lists in `Data.lua` now iterate `Enum.CooldownViewerCategory`, so the
five new 12.1 categories arrive for free. `DECISIONS.md` §8 for the design and
for the runtime trap that came with it (Blizzard writes two negative fakes into
that enum). `UPCOMING-PATCH.md` was re-verified against Blizzard's `ptr` source
at the same time and several of its wiki-sourced claims were wrong; the
corrected version is what to work from.

## 5. The player's current setup

Four spec profiles exist. Outlaw (260) is the active testbed:

- anchor col 1, row 6; collapse `columns`; padding 6
- 10 icons, including Pistol Shot (185763) in `proc` mode and Roll the Bones
  (1214909) in `aura` mode — now drawn by Blizzard's adopted item and
  **confirmed working in combat**
- **Opportunity (279876) at cell 6:4** is the one being worked on. Note the ID:
  that is the *passive*, and the buff it grants is 195627. The Cooldown Manager
  lists it as `TrackedBuff`, `cooldownID 93055`, `linked=1`, `isKnown=true`. It
  was last saved as `mode=proc`; it needs to be `aura` for adoption to run at all
- Druid 102 / 104 / 105 hold the migrated legacy bars
- **Combo pips are on**, and the player moved the grid's cursor anchor further
  out to make room for them, having found the pips drew underneath the grid.
  They then asked for a tighter pip ring, which is why the offset slider reaches
  -80. Do not "fix" the anchor distance; it is a deliberate choice.
- The player keeps Roll the Bones in the **Tracked Buffs** list (icon plus
  timer) rather than Tracked Bars, having tried both. They liked the bar visual
  and want it available, at one cell, unenlarged — see `DECISIONS.md` §13.

Resto (105) is at scale 0.6, faithful to the old ECV, and so looks smaller than
the others. That is deliberate, and the player knows.

## 6. How this player wants to work

Recorded because it has been consistent and it matters more than any single
technical decision:

- **Confirm design before building anything large.** Present real options with
  trade-offs and a recommendation. They would rather answer a question than
  have the wrong thing built thoroughly.
- **Investigate before changing code.** They have said so explicitly. When they
  ask "did we do that right", answer from evidence on disk, not from reasoning
  about what the code should do.
- **Do not assume you are wrong because they are confused.** They have said
  this directly. Check, then answer plainly either way.
- Small obvious fixes: just do them.
