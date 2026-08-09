# Known issues

Things that are wrong, understood, and deliberately not fixed. Each entry says
**why** it is parked and **what would have to change** for it to be fixable, so
a future patch can be checked against it rather than the whole investigation
being redone.

Re-check these on every patch (`docs/UPCOMING-PATCH.md` has it on the
checklist).

---

## Resource ring cannot show an exact level in combat

**Status:** parked 2026-08-08. Ring is off by default; the crash it caused is
fixed, the feature is not.

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

1. **Untainting ThugUI.** The error says *"while execution tainted by
   `ThugUI`"*, which suggests the secrecy is a consequence of taint rather than
   a blanket restriction. There is a known taint source — `ADDON_ACTION_BLOCKED`
   on `ThugUI_TargetOfTargetMover:SetSize()` from
   `TargetOfTarget/Core.lua:432` — and an oUF portrait error carrying the same
   "tainted by ThugUI" wording. Clearing that is worth trying before anything
   else; it may restore plain numbers everywhere.
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
