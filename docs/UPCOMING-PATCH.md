# Upcoming patch — 12.1

**Current live version: 12.0.7 (Interface 120007).** This file accrues what we
learn about 12.1 *before* it ships, so patch day is a checklist rather than a
scramble.

**On patch day:** work the checklist, move anything still true into
`docs/DECISIONS.md` or into code comments, delete this file, and start a fresh
one for the patch after.

Every entry needs a **source**. See `docs/SOURCES.md`.

**Re-verified 2026-08-09 against Blizzard's own source**, not the wiki:
`Gethe/wow-ui-source`, `ptr` @ `a520b6c` (12.1.0 build 69189, 2026-08-07) diffed
against `live` @ `c878310` (12.0.7 build 68974). Several claims in the earlier
wiki-sourced version of this file were wrong and are corrected below. Prefer the
generated documentation in `Blizzard_APIDocumentationGenerated/` over the wiki
for anything in this file — the wiki has been wrong about this exact system more
than once.

---

## Cooldown Manager — new categories

`Enum.CooldownViewerCategory` gains five values, confirmed from
`CooldownViewerConstantsDocumentation.lua` on both branches (`NumValues` goes
4 → 9):

| Value | Field | |
|---|---|---|
| 0–3 | Essential, Utility, TrackedBuff, TrackedBar | existing |
| 4 | `GroupBuff` | new |
| 5 | `SpecAgnosticEssential` | new |
| 6 | `SpecAgnosticTracked` | new |
| 7 | `EquipSlotEssential` | new |
| 8 | `EquipSlotTracked` | new |

**Handled already.** `modules/CooldownViewer/Data.lua` iterates the enum rather
than naming categories, so all five are picked up for free by the cache, the
probe dump and the "Everything" picker source. The curated source menu stays
hand-written on purpose. Reasoning: `DECISIONS.md` §8.

**Also handled: the enum carries two negative fakes at runtime**
(`HiddenSpell`/`HiddenAura` on live, renamed `HiddenActive`/`HiddenPassive` on
ptr). They are filtered by value. `DECISIONS.md` §8 has why this matters and why
filtering by name would have broken on patch day.

Two cautions from the earlier version, re-checked:

- `SpecAgnostic*` entries are presumably not per-spec. The earlier note said this
  "breaks the assumption behind the per-spec cache key" — **overstated.** The
  cache is keyed by spec and rebuilt on spec change, so a spec-agnostic entry
  sitting in it is merely rebuilt more often than necessary. Harmless. Do not
  restructure `Data.GetCooldownInfoForSpell` for it.
- `EquipSlot*` entries pair with the new `equipSlot` field and are trinkets
  rather than spells, and `spellID` is now nilable (below). `Data.PickerSpellIDFor`
  already falls back through `overrideSpellID` → `spellID` →
  `overrideTooltipSpellID` → first linked ID and returns nil if all are absent,
  so a trinket with no spell ID is dropped rather than crashing. **Verify that is
  what we want** before exposing those categories — a silently dropped trinket is
  the same failure shape as the Roll the Bones entry that went missing.

## Cooldown Manager — cooldown structure changes

From `CooldownViewerDocumentation.lua`, both branches:

| Field | Change |
|---|---|
| `spellID` | **now nilable** — was non-nilable on live |
| `spellCategoryID` | **new**, number, nilable — *not previously recorded here* |
| `equipSlot` | new, luaIndex, nilable |
| `buffSlot` | new, luaIndex, nilable |
| `isInvisible` | new, bool, non-nilable |
| `overrideSpellID`, `overrideTooltipSpellID` | **unchanged, present on both** |

**The wiki was wrong about the override fields.** It marks them as 12.1
additions; they are in the generated docs on `live` too, which is why our 12.0.7
code reads them and works. Do not "fix" that code on the strength of the wiki.

### `isInvisible` — do not filter on it

The earlier guess here was "in the data but should not be shown", with a note to
verify. Verified, and the answer is **do nothing**.

Blizzard's own reads of it are hard-gated:

```lua
-- CooldownViewerSettingsConstants.lua
-- DEBUG/TESTING constants slated for removal
CDM_HIDE_INVISIBLE_ITEMS = false;

-- CooldownViewerSettings.lua
local isInvisible = CDM_HIDE_INVISIBLE_ITEMS and cooldownInfo.isInvisible;
```

With that constant `false`, `isInvisible` changes nothing in 12.1, and Blizzard
flag the constant itself as debug code slated for removal. Filtering on the field
would implement a behaviour the game does not have. Re-check on a later build.

It carries no secret-value flags.

## Cooldown Manager — the mechanism our buff icons depend on is safe

**No `C_CooldownViewer` function and no `CooldownViewerCooldown` field gains a
`SecretWhen*` flag on ptr.** Cooldown IDs stay plain readable numbers in combat.

That is the load-bearing check: `DECISIONS.md` §13 works entirely by matching our
placements to Blizzard's item frames on `cooldownID`. If that had gone secret the
feature would be dead. It has not.

`CooldownViewerSecure.lua` (new on ptr) defines
`addonTable.CreateSecureAuraInstanceMap()` — a proxy over the viewer's internal
aura-instance-to-frame map, marked `DisallowSecretKeys` and
`DisallowTaintedAccess`. It is used only inside `CooldownViewer.lua`.
`modules/CooldownViewer/BlizzBuffs.lua` never touches that table: it enumerates
the item pool and matches on `item:GetCooldownID()`. Anchoring and scaling pooled
items, and hooking `RefreshLayout` with `hooksecurefunc`, all still appear
permitted. **Appear** — this is read from source, not run on a PTR client.

The other two new files are cosmetic: `CooldownViewerDraggedItemBase` is the
cursor-follow preview when dragging entries in settings,
`CooldownViewerEditAlertBase` is the add/edit dialog for alerts.

## Aura API — a new flag whose meaning is not documented

`DECISIONS.md` §12 records an expectation that in 12.1 the index/slot/instanceID
aura calls will **Lua error** rather than return secrets, and that the fallback
list walk in `modules/CooldownViewer/Core.lua` is on borrowed time.

What the source actually shows: a new flag, **`RequiresUnitAuraAccess = true`**,
on 16 functions on `ptr` and on **zero** on `live` — including
`GetAuraDataByIndex`, `GetAuraDataBySlot`, `GetAuraDataByAuraInstanceID`,
`GetUnitAuraInstanceIDs`, `DoesAuraHaveExpirationTime`, `GetAuraDuration`,
`IsAuraFilteredOutByInstanceID`. `GetUnitAuraBySpellID` and
`GetPlayerAuraBySpellID` do **not** get it; they keep `RequiresNonSecretAura`.

**The flag is real and new. What it does when unmet is not stated anywhere in
Blizzard's source.** The name is consistent with the expectation, and by analogy
`RequiresNonSecretAura` means "returns nothing at all" rather than "errors" —
which would be the opposite of what §12 predicts. Do not record this as settled
either way. It is a flag we found, not a behaviour we observed.

**Answer it with the probe, not by reasoning.** `modules/SecretProbe.lua` already
samples these calls every session and distinguishes readable / secret / nothing /
error. One session on a 12.1 client answers it outright.

---

## Patch-day checklist

- [ ] Bump `## Interface:` in `ThugUI.toc`
- [ ] `lua Tests/loadtest.lua .` — expect breakage in the stubbed APIs first
- [ ] `/thugcv probe` on each played spec; diff against pre-patch output
      (the dump is ordered by category value, so the diff stays readable)
- [ ] Read `ThugUI_DebugLog.secrets` — the probe answers `RequiresUnitAuraAccess`
      for free. Record what it actually did in `DECISIONS.md` §12
- [ ] Confirm the picker still lists everything it did before, and that the five
      new categories arrive through "Everything" without being named anywhere
- [ ] Check the once-only "unrecognised category" log fired for the new
      categories and **not** for the renamed negative fakes
- [ ] Decide where `GroupBuff` / `SpecAgnostic*` / `EquipSlot*` belong in the
      curated source menu — a product decision, not a code one (`DECISIONS.md` §8)
- [ ] Confirm Roll the Bones still resolves through `linkedSpellIDs`
- [ ] Confirm `BlizzBuffs` still adopts items — watch for `CVBUFF` lines naming a
      failed stage, and for `DisallowTaintedAccess` errors
- [ ] Re-check `isActive` / `isOnGCD` still exist and are non-secret
      (`DECISIONS.md` §5 — the whole readiness path rests on this)
- [ ] Re-check whether `isInvisible` is still inert (`CDM_HIDE_INVISIBLE_ITEMS`)
- [ ] Re-check every entry in `docs/KNOWN-ISSUES.md` — especially whether
      `UnitPower` still returns a secret number
- [ ] Re-check every entry in `docs/SOURCES.md` and update its last-checked date
- [ ] Move anything still true into `DECISIONS.md`, delete this file, start 12.2
