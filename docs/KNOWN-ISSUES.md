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

## Resource ring cannot show an exact level in combat

**Status: still open, re-checked 2026-08-11 on 12.1.** The ring is switched
**on** (`showResourceRing = true`, visibility `"combat"`), so this is live, not
hypothetical.

**Open, but no longer believed impossible.** 12.1 made this fixable and nobody
has built the fix — see item 2 below. Do not quote the "permanently impossible"
framing this entry used to carry; it was reasoning from a widget that no longer
has a monopoly on drawing an arc.

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

## "Follow cursor" off still tracks the cursor, at an offset

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
