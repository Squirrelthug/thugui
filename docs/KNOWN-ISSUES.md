# Known issues

Things that are wrong, understood, and deliberately not fixed. Each entry says
**why** it is parked and **what would have to change** for it to be fixable, so
a future patch can be checked against it rather than the whole investigation
being redone.

Re-check these on every patch (`docs/UPCOMING-PATCH.md` has it on the
checklist).

---

## Resource ring cannot show an exact level in combat

**Status: still open, checked 2026-08-09.** The ring is now switched **on**
(`showResourceRing = true`, visibility `"combat"`), so this is live, not
hypothetical.

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

1. **Untainting ThugUI. — ATTEMPTED 2026-08-08, result unknown.** The error says
   *"while execution tainted by `ThugUI`"*, which suggests the secrecy is a
   consequence of taint rather than a blanket restriction. The known source —
   `ADDON_ACTION_BLOCKED` on `ThugUI_TargetOfTargetMover:SetSize()` from
   `TargetOfTarget/Core.lua` — now defers out of combat via
   `ToT:MoverGeometryBlocked`. An oUF portrait error carried the same "tainted
   by ThugUI" wording and may be a second source, or may just be downstream of
   the first.
2. A future radial widget that takes value/max directly.
3. Blizzard reclassifying current power as non-secret for untainted addons.

**Do not** attempt to work around it by guessing the value, sampling it out of
combat and extrapolating, or reading it from a Blizzard frame's displayed text.

---

## Buff (aura) icons never draw in combat

**Status: root cause identified 2026-08-09, not yet fixed.** Almost certainly
the same underlying fault as the resource ring entry above.

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

**Leading explanation:** aura fields are secret values to a *tainted* addon,
and combat is when that applies. ThugUI is provably tainted every session
(see the resource ring entry). That would make these one bug, not two, and it
predicts that untainting fixes both. `issecretvalue` has been confirmed to be
a real global in 12.x, so the guard in `Mine()` meant to accept an unreadable
source is live rather than silently skipped — if the aura is being refused, it
is being refused for some other reason.

**Next step:** the stage-level log added in `13f852f` records whether the API
threw, returned nothing, or was refused by the source check. It has not been
captured yet — the session that would have produced it predated the commit.

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
