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

## Two ThugUI category entries in the Blizzard addon list

**Status:** deliberate, not a bug. See `DECISIONS.md`.

The feature panels under `modules/` are still registered alongside the new
config window, as the fallback while the window settles in. Remove only when
asked.
