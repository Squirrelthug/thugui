# Upcoming patch — 12.2

**Current live version: 12.1 (Interface 120100).** This file accrues what we
learn about the *next* patch *before* it ships, so patch day is a checklist
rather than a scramble.

**Nothing is recorded yet.** 12.2 has not been announced and no PTR branch has
been read. That is the honest state — an empty file here means "not looked at",
never "nothing is changing".

**On patch day:** work the checklist, move anything still true into
`docs/DECISIONS.md` or into code comments, delete this file, and start a fresh
one for the patch after.

Every entry needs a **source**. See `docs/SOURCES.md`. Prefer the generated
documentation in `Blizzard_APIDocumentationGenerated/` over the wiki — the wiki
has been wrong about the Cooldown Manager more than once, most recently about
which patch added `overrideSpellID` (`DECISIONS.md` §24).

---

## What 12.1 cost us, so 12.2 can be cheaper

Not predictions — the shapes of the three things that actually bit on the last
patch day. Look for each of them again.

1. **A field going nilable is enough to cause silence.** `spellID` became
   nilable and a table constructor holding maybe-nil values grew a hole that
   `ipairs` stopped dead at. Nothing errored. `DECISIONS.md` §20.
2. **A measurement can be invalidated without any API changing its signature.**
   12.1 lifted "we cannot sweep in combat" by adding a *route*, not by changing
   the refused call. Re-run `modules/SecretProbe.lua` before trusting any rule
   this addon adopted from an earlier measurement.
3. **A new entry shape can be structurally unplaceable.** The item categories
   arrived with no spell ID, and every placement here is keyed by spell ID. They
   were dropped from the picker silently.

---

## Patch-day checklist

- [ ] Bump `## Interface:` in `ThugUI.toc`
- [ ] `lua Tests/loadtest.lua .` — expect breakage in the stubbed APIs first
- [ ] `/thugcv probe` on each played spec; diff against pre-patch output
      (the dump is ordered by category value, so the diff stays readable)
- [ ] Read `ThugUI_DebugLog.secrets` — re-measure every secret-value rule this
      addon relies on rather than assuming last patch's answers hold
- [ ] Diff `CooldownViewerCooldown` field by field, **with nilability**, against
      the previous build. A field going nilable is a silent-failure risk
- [ ] Confirm the picker still lists everything it did before, and that any new
      categories arrive through "Everything" without being named anywhere
- [ ] Check the once-only "unrecognised category" log fired for genuinely new
      categories and **not** for the negative pseudo-categories
- [ ] Confirm Roll the Bones still resolves through `linkedSpellIDs`
- [ ] Confirm `BlizzBuffs` still adopts items — watch for `CVBUFF` lines naming a
      failed stage, and for `DisallowTaintedAccess` errors (`DECISIONS.md` §24)
- [ ] Re-check `isActive` / `isOnGCD` still exist and are non-secret
      (`DECISIONS.md` §5 — the whole readiness path rests on this)
- [ ] Re-check whether `isInvisible` is still inert (`CDM_HIDE_INVISIBLE_ITEMS`)
- [ ] Re-check every entry in `docs/KNOWN-ISSUES.md` — especially whether
      `UnitPower` still returns a secret number
- [ ] Re-check every entry in `docs/SOURCES.md` and update its last-checked date
- [ ] Move anything still true into `DECISIONS.md`, delete this file, start 12.3
