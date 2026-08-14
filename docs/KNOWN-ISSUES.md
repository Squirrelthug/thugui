# Known issues

Things that are wrong, understood, and deliberately not fixed. Each entry says
**why** it is parked and **what would have to change** for it to be fixable, so
a future patch can be checked against it rather than the whole investigation
being redone.

Re-check these on every patch (`docs/UPCOMING-PATCH.md` has it on the
checklist).

---

## "Anchor tracked buff bar to cursor" would reintroduce the taint bug

**Status: parked deliberately, setting is off, warning is in the code.**

`ER:UpdateBuffFramePosition` in `modules/EssentialRings.lua` moves and scales
`BuffIconCooldownViewer` — an Edit Mode system frame — and calls Blizzard's
`UpdateSystem` / `LayoutApplied` from our stack on the way out of combat. Those
are three of the four vectors that killed the cooldown viewer (`DECISIONS.md`
§15).

It is left alone because `anchorBuffFrameToCursor` is **off**, it is the legacy
escape hatch, and nothing in this project gets deleted without being asked.
`CooldownViewer/BlizzBuffs.lua` supersedes it and taints nothing.

**What would change this:** the player wanting that setting again. Then rewrite
it the way BlizzBuffs was rewritten — anchor from our side, bookkeeping in side
tables, never call their methods — rather than switching it on as it stands.

---

## ~~Edit Mode cooldown windows vanish after combat~~ — FIXED 2026-08-09

Removed from this list because it is fixed and verified in game (BugGrabber
sessions 116–117 clean through a long combat test). Kept as a stub only so the
name still leads somewhere.

We were exporting taint into Blizzard's frames and their own code was throwing on
it. Cause, mechanism and the general rule: `DECISIONS.md` §15. If anything in
this area regresses, the tell is an error inside a **Blizzard** file naming
ThugUI — not an error in ours.

---

## ~~Resource ring cannot show an exact level in combat~~ — SOLVED 2026-08-13

**Verified in game by the player on 2026-08-13.** They enabled
`resourceRingRadialBar` **mid-combat** and the ring tracked their resource live,
through the whole fight, **and followed shapeshift form swaps** — rage in bear,
energy in cat, changing in combat. Their words: *"It seems to function exactly
as intended."*

That answers three separate open questions in one observation:

1. **The exact level can be shown in combat.** A radial `StatusBar` fed the
   secret `UnitPower` straight into `SetValue` and the engine did the arithmetic
   we are not allowed to do. `DECISIONS.md` §23.
2. **The start angle is right.** This was the one thing that could not be
   determined outside the game — `StatusBar` has no `SetRotation` and the
   alignment was attempted by rotating the managed texture. Checked at
   mid-range levels across a fight rather than at 0% or 100%, which is the
   condition that made the check meaningful.
3. **Enabling it mid-combat works.** The creation path is not combat-gated.

The history below is kept because it is the clearest example this project has of
a correct measurement producing a wrong conclusion, and of how that got caught.

**Do not quote the "permanently impossible" framing this entry used to carry.**
It reasoned from a widget that no longer has a monopoly on drawing an arc.

**Checked and answered.** The ToT mover deferral was not sufficient. The log
shows, five seconds into a fresh session and before any combat:

```
[00:34:46] RING: UnitPower unreadable (secret value) for ENERGY
```

Two things follow. It taints on a **login** path, not a combat one — no mover
resize and no fight had happened yet. And `ADDON_ACTION_BLOCKED` for the ToT
mover has not recurred since session 82, so that fix held; it simply was not
the whole story. The oUF `portrait.lua` element — vendored under our name, so
anything it touches is attributed to us, and reporting "tainted by ThugUI" as
recently as session 90 — is the next thread. See `HANDOFF.md` §3.

The analysis below stands regardless, since it describes what happens *while*
tainted.

`UnitPower("player", powerType)` returns a **secret number** while our execution
is tainted — `UnitPowerMax` returns a plain one alongside it:

```
attempt to perform arithmetic on local 'current' (a secret number value,
while execution tainted by 'ThugUI')
    current=<secret number>   maximum=200   powerToken="ENERGY"
```

A radial arc needs `current / maximum` to seed the swipe, and arithmetic on a
secret throws. There is no radial widget that accepts a raw value/max pair the
way `StatusBar:SetValue` does, so the maths cannot be pushed engine-side.

**Current behaviour:** the read is screened before any arithmetic. When the
value is unreadable the ring holds its last resolved level and keeps its colour
(the power *type* is never secret). Out of combat it tracks normally. No errors.

**What would make it fixable, in rough order of likelihood:**

1. ~~**Untainting ThugUI.**~~ **CLOSED 2026-08-09 — impossible, and never the
   cause.** Addon code always executes tainted by its own addon; `UnitPower`
   carries `SecretWhenUnitPowerRestricted` in Blizzard's generated docs, and
   primary resources stay secret to addons regardless. Full reasoning and
   evidence in `DECISIONS.md` §12. Do not re-open this.
2. ~~**Driving the arc natively.**~~ **RE-OPENED 2026-08-11 by the 12.1 patch.**

   The 2026-08-09 measurement still holds exactly as written, and is repeated
   verbatim on 12.1: `Cooldown:SetCooldownDuration(secret)` is **refused** from
   tainted code and `CurveObject:Evaluate(secret)` is refused too. What was
   wrong was the sentence drawn from it — *"a straight bar could show exact
   energy in combat where a ring cannot"*. That treated "radial" as a property
   of the `Cooldown` widget, which was the only radial thing in the API at the
   time.

   **12.1 adds `StatusBarRenderMode.Radial`** — *"render the status bar by
   driving the managed texture's radial progress fill percent instead of
   resizing the texture anchors"* — and `StatusBar:SetValue(secret)` is still
   measured **accepted** in combat (`ThugUI_DebugLog.secrets`, 2026-08-11
   21:05). A radial StatusBar is a ring, and it takes the value we may not read.

   The premise survived the patch; the conclusion did not. `DECISIONS.md` §20.
   This is a design change rather than a bug fix, and the player has been shown
   it as an option and has not chosen it yet.
3. Blizzard reclassifying primary power as non-secret. Unlikely, and note that
   the 12.1 relaxation for *secondary* resources turns out to have shipped
   already: combo points read fine in combat on 12.0.7.

**Task 16, 2026-08-12: a second implementation is built, and unseen in game.**
`modules/ResourceRing.lua` now carries a radial `StatusBar` path alongside the
Cooldown one, opt-in via `resourceRingRadialBar` (default **off**) on the Cursor
Rings page. It hands the secret `UnitPower` straight to `SetValue` and lets the
engine compute the fill — no arithmetic, no comparison. `DECISIONS.md` §23.

**Verified in game 2026-08-13**, as described at the top of this entry. The
start-angle worry did not materialise.

---

## ~~The old Cooldown-widget resource ring never tracked~~ — DELETED 2026-08-13

**Resolved by removal, not by repair.** The player's call, same day: *"the old
cooldown ring's frozen sweep is no longer needed so we should just get rid of it
and keep going forward."* The Cooldown path and the `resourceRingRadialBar`
setting that selected it are both gone; the radial ring is the only
implementation. `DECISIONS.md` §27.

The account below is kept because the *diagnosis* is the reusable part — it is
how the cause was narrowed without ever fixing anything, and the experiment that
did it was designed before either answer was known.

**Status when it was closed: the diagnostic experiment ran on 2026-08-13 and
came back clean.**

The player reported on 2026-08-12 that the Cooldown ring's colour follows
shapeshift form correctly while the level never moves. Their
`resourceRingVisibility` is `always`, so they see it out of combat too, where
nothing is secret.

The experiment designed to separate the two possible causes was: turn
`resourceRingRadialBar` on, because **the radial path calls `Pause` nowhere.**
If the radial ring tracks and the Cooldown ring does not, the cause is the pause
rather than secrecy.

**The radial ring tracks.** So secrecy is eliminated as the explanation, and the
remaining candidate is the one already identified: the Cooldown path calls
`f:Pause()` after every `SetCooldown`, and **`Resume()` is never called anywhere
in the file**. A paused Cooldown appears not to re-evaluate a fresh
`SetCooldown`, so the ring freezes at the first value it ever drew and every
later re-seed lands on a frozen widget. Colour keeps working because
`SetSwipeColor` is unaffected by pause. That matches the report exactly.

**What is confirmed and what is not.** Confirmed: the freeze is not caused by
secret values. Not confirmed: that removing or balancing the `Pause` fixes it —
nobody has built that and nobody has seen it. Blizzard's generated documentation
gives no semantics for `Pause`/`Resume`, so it cannot be settled from source
either.

**Do not fix this by removing `Pause`** without checking what it was for: the
comment at the top of the file says the ring is a frozen sweep on purpose, and
`ARC_DURATION` is 1000 seconds precisely so an unpaused ring drains slowly rather
than not at all.

**And consider not fixing it at all.** *(Written before the player decided. They
went further and deleted it — see the top of this entry.)* The Cooldown path
existed only as the fallback for a radial path that is verified working.
Repairing a fallback nobody uses, on a widget whose pause semantics are
undocumented, was a poor trade.

**The transferable lesson is about what "fallback" earns.** This project's
standing rule is *never break the fallback* (`CLAUDE.md` §3), and that rule was
protecting something which had never worked once. A fallback is only worth its
keep if it actually falls back; an untested one is not insurance, it is a second
thing that can be wrong. The rule still holds for the ECV/BCV/GCV bars, which are
**known** to work and are reachable with `/thugcv legacy` — the difference is
evidence, not sentiment.

---

**Do not** attempt to work around it by guessing the value, sampling it out of
combat and extrapolating, or reading it from a Blizzard frame's displayed text.

---

## Buff (aura) icons never draw in combat

**Status: cause proven, and the workaround is verified in game 2026-08-09**
through a long combat test including the buff expiring and being re-applied.
ThugUI's *own* aura icons still cannot draw in combat and never will — that part
is permanent, which is why this entry stays. `modules/CooldownViewer/BlizzBuffs.lua`
sidesteps it by anchoring Blizzard's own tracked-buff item into the assigned
grid cell, so their untainted code decides what shows. Switch it off with
"Use Blizzard's buff frames" on the Cooldown Viewer page to get the old
behaviour back.

An `aura`-mode icon resolves and draws correctly out of combat and never draws
in combat. Twelve logged transitions in one session, no exceptions:

```
00:46:53  SHOWN  at cell 4:3 (combat=false)
00:46:59  hidden at cell 4:3 (combat=true)
00:47:09  SHOWN  at cell 5:3 (combat=false)
00:47:31  hidden at cell 4:3 (combat=true)
```

**Ruled out, with evidence — do not re-investigate these:**

- *The linked-spell lookup.* `/thugcv status` reports `4 linked, active via
  1214933`, and the snapshot shows `linked=4 cat=3`. Resolution is correct.
- *Cursor anchoring.* Tested with `followCursor = false`; still never draws in
  combat. The two had been confounded because `onlyInCombat` was also on.
- *An error being swallowed.* BugGrabber sessions 91–95 are clean.
- *The set-vs-outcome distinction.* Placing an individual outcome buff
  directly behaves the same way.

**Reading the log correctly matters here.** A `SHOWN ... (combat=true)` line
followed by a `hidden` in the same second is **not** a flicker: `Rebuild` seeds
every icon `wanted = true` and `UpdateState` immediately corrects it. Each pair
follows a cooldown-cache rebuild — `SPELLS_CHANGED` firing as the buff lands,
visible as the entry count moving 62↔63. Only `combat=false` SHOWN lines are
real.

**Cause, confirmed against Blizzard's generated docs 2026-08-09:**
`GetUnitAuraBySpellID` and `GetPlayerAuraBySpellID` both carry
`RequiresNonSecretAura`, which is why they return **nothing** in combat instead
of erroring, and `GetAuraDataByIndex` carries `SecretWhenUnitAuraRestricted`,
which is why the fallback list walk sees auras it cannot match a field on. It
is one restriction, not two bugs, and **it is not fixable by untainting** —
there is no untainted state for an addon to reach (`DECISIONS.md` §12).

The route that remains is to stop asking: let Blizzard's own untainted
`BuffIconCooldownViewer` items decide visibility and duration, and use ThugUI
only for placement and skin. `EssentialRings.lua:930` already does this for the
cursor-anchored case.

**Measured directly, 2026-08-09** (`ThugUI_DebugLog.secrets`, and
`DECISIONS.md` §12 for the full table). In combat the aura list *is* returned —
9 to 11 auras — and the structs *can* be indexed, so `aura.spellId` is
reachable. It comes back as a secret number, and **comparing it errors**:

```
attempt to compare field 'spellId' (a secret number value, while execution
tainted by 'ThugUI')
```

That is the choke point, and it is deliberate. Aura instance IDs are handed
over as plain readable numbers, `IsAuraFilteredOutByInstanceID` answers with a
plain bool, and the whole display path for a secret works
(`DoesAuraHaveExpirationTime` → `EvaluateColorValueFromBoolean` → `SetAlpha`,
all fine). Everything is available *except* the one operation that would let an
addon say "this aura is that spell". No native equality helper exists:
`CurveObject:Evaluate` refuses secret input, and no API turns a secret spell ID
into a secret boolean.

**So there is no route to identifying a buff in combat from addon code, and no
amount of cleverness changes that.** Blizzard's own untainted frames are the
only way to show one.

**Earlier narrowing, kept for the record.** In combat, with the buff up,
`C_UnitAuras.GetUnitAuraBySpellID("player", <linked id>)` returns **nothing**.
It does not throw, and the aura is not refused by the source check — both of
those are separate logged outcomes and neither appeared. Out of combat, the
same call on the same buff returns it:

```
[00:59:39] CV: buff icon Roll the Bones: hidden  (combat=true)   <- buff was up
[00:59:47] AURA: lookup for 1214934: found (combat=false)        <- same buff
```

This is by elimination rather than a direct in-combat line: the first version
of the stage log keyed only on spell and stage, so an out-of-combat
"api-returned-nothing" logged while no buff was up suppressed the in-combat
one. Fixed — combat state is now part of the key — so the next capture states
it outright rather than implying it. **The conclusion is not in serious doubt,
but it has not yet been read directly.**

That the call returns empty rather than erroring is what makes taint the
leading explanation: a tainted addon is handed nothing instead of a secret it
could at least detect.

---

## A spent charge spell goes invisible but its cell does not collapse

**Status: accepted by the player, verified in game 2026-08-12.** Not a defect to
be fixed later — a measured limit, accepted knowingly so patch-day work could
continue.

The icon disappears correctly when every charge is spent during combat. The cell
keeps its space, so a column holding one does not close around it until combat
ends. `DECISIONS.md` §21.

**Why it cannot be fixed from addon code.** The hiding works because
`SetAlpha` accepts a secret value and clamps it to 0–1, so
`icon:SetAlpha(currentCharges)` never reads or compares the count. Collapse is
different in kind: `ApplyLayout` packs on `if icon.wanted then`, a plain Lua
truth test, and setting `icon.wanted` from the charge count is a branch on a
secret — the operation that throws.

**Routing around it was considered and rejected on evidence.** The player
proposed parking a spent icon on a 1×1 frame so the grid closes over it. The
frame trick is sound; the problem is upstream of it, because parking the icon
requires first knowing it is spent. Note also that the client refuses
`SetShown(secret)` and accepts `SetAlpha(secret)` seconds apart on the same
widget: **a secret may change what you see, never what the layout does.** Any
scheme turning a secret into a position, a size, or a shown state is on the wrong
side of a line Blizzard drew deliberately.

**What would change this:** Blizzard making `currentCharges` non-secret, as they
already did for secondary resources. Nothing on our side.

Out of combat nothing is secret, so hide-and-collapse works normally. The gap is
combat-only and bounded to the window between spending the last charge and the
first recharge landing.

---

## ~~"Follow cursor" off still tracks the cursor~~ — NOT REPRODUCING 2026-08-12

**Status: could not be reproduced, closed pending a fresh sighting.** The player
re-tested on 2026-08-12 and the grid stayed where it was dragged.

Their sharper description before that test is worth keeping in case it returns:
**out of combat it stayed where dragged, and only moved during combat.** The
gate reads correctly for that shape — `Core.lua`'s `wantCursor` is
`profile.followCursor and (previewMode or inCombat)`, and the per-frame path at
the bottom of the driver repeats the same condition — so with the setting off
neither should ever run. If it comes back, that pair of conditions is where to
look first, and the combat-only detail is the clue that separates them from the
drag path.

The original report follows.

**Status: noted 2026-08-09, not investigated.** Reported by the player.

With the follow-cursor option unchecked, the grid still moves with the mouse,
just offset from it rather than centred on it. Low priority — it was noticed
while testing something else and is not in anyone's way — but it means the
setting does not currently do what it says.

---

## Two ThugUI category entries in the Blizzard addon list

**Status:** deliberate, not a bug. See `DECISIONS.md`.

The feature panels under `modules/` are still registered alongside the new
config window, as the fallback while the window settles in. Remove only when
asked.

---

## Geometry is only ever tested at one UI scale

**Status: a standing blind spot, not a specific bug.** Moved here on 2026-08-13
when `docs/QA.md` was deleted — it was the one genuinely load-bearing thing in
that file (`DECISIONS.md` §28).

Three scales multiply, and this addon is built and used at one point in that
space:

| Scale | Where | Range |
|---|---|---|
| WoW UI Scale | System → Advanced | 0.53 – 1.0 |
| `profile.scale` | ThugUI, per spec | 0.5 – 2.0 |
| Blizzard viewer scale | Edit Mode, Cooldown Manager | user set |

**This has already hidden a real bug.** The adopted-buff sizing defect
(`DECISIONS.md` §17) survived because the only profile in daily use sat at
`scale = 1`, where the grid's coordinate space and the screen's coincide. The
fix is *designed* to be UI-scale independent — it divides two
`GetEffectiveScale()` values and UIParent appears in both — but **that is
reasoning, not evidence, and it has still never been checked at a non-default UI
scale.**

**What to do about it:** nothing, until a geometry bug appears. Then the first
question is "at what scale?", and the first experiment is to change one of the
three and see whether the symptom moves. `FitItem` logs its arithmetic once per
session — `CVBUFF: fit: base=… icon=… ours=… theirs=… -> scale=…` — and that
line says which of the two coordinate spaces disagreed. **Read it before
theorising.**

---

## Two characters of the same spec share one layout

**Status: a real design limitation, deliberately not fixed.** Also moved from
`docs/QA.md` on 2026-08-13.

Profiles are keyed by **specialisation ID** and stored **account-wide** —
`## SavedVariables` in the TOC, with no `SavedVariablesPerCharacter`. So two
characters of the same class and spec share one layout and cannot be configured
apart.

The player has exactly this: **two resto druids, Eowyn and Ixloatel**, on one
profile.

Fine for one main, and it has never actually bitten. It becomes a real problem
the moment anyone wants those two set up differently — and it would need
deciding, with a migration that does not discard existing profiles, before this
addon went to anyone else. It is recorded as a limitation rather than queued as
work because **nobody has yet wanted the two configured apart.**
