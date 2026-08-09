# Upcoming patch — 12.1

**Current live version: 12.0.7 (Interface 120007).** This file accrues what we
learn about 12.1 *before* it ships, so patch day is a checklist rather than a
scramble.

**On patch day:** work the checklist, move anything still true into
`docs/DECISIONS.md` or into code comments, delete this file, and start a fresh
one for the patch after.

Every entry needs a **source**. See `docs/SOURCES.md` for the vetted list; the
two that matter most here are townlong-yak's build **Compare** view (diff the
live build against the PTR one directly) and the `ptr` branch of
`Gethe/wow-ui-source`. Do not record rumours.

As of 2026-08-08 townlong-yak carries **build 69189 (12.1.0) PTR**, so the diff
against live is already available — that is the fastest way to extend this file.

---

## Cooldown Manager — new categories

`Enum.CooldownViewerCategory` gains five values in 12.1.0:

| Value | Field | |
|---|---|---|
| 0–3 | Essential, Utility, TrackedBuff, TrackedBar | existing |
| 4 | `GroupBuff` | new |
| 5 | `SpecAgnosticEssential` | new |
| 6 | `SpecAgnosticTracked` | new |
| 7 | `EquipSlotEssential` | new |
| 8 | `EquipSlotTracked` | new |

*Source: warcraft.wiki.gg API_C_CooldownViewer.GetCooldownViewerCategorySet,
"Added in 12.1.0".*

**Impact.** `modules/CooldownViewer/Data.lua` names its categories as literal
strings in three places — `CATEGORY_BY_SOURCE`, `BuildCooldownInfoCache` and
`DumpCooldownViewer`. New categories will be silently ignored.

**Action when it lands:** iterate `Enum.CooldownViewerCategory` instead of
hardcoding names, so a future patch adding a category is picked up for free.
The picker's source dropdown should grow itself.

Two cautions:
- `SpecAgnostic*` entries are presumably *not* per-spec, which breaks the
  assumption behind the per-spec cache key in `Data.GetCooldownInfoForSpell`.
- `EquipSlot*` entries pair with the new `equipSlot` field and are trinkets
  rather than spells. They may have no usable spellID at all — the same shape
  of problem that hid Roll the Bones. Check `Data.PickerSpellIDFor` handles
  them before exposing those categories.
- **Do not add `TrackedBar` as a picker source** even though it looks like a
  gap. Tracked bars are drawn from the same pool as tracked buffs; it would
  duplicate the list. See `DECISIONS.md` §8.

## Cooldown Manager — new cooldown fields

`CooldownViewerCooldown` gains in 12.1.0:

| Field | Type | Note |
|---|---|---|
| `overrideSpellID` | number? | **already used** by us |
| `overrideTooltipSpellID` | number? | **already used** by us |
| `equipSlot` | luaIndex? | trinket slot |
| `buffSlot` | luaIndex? | |
| `isInvisible` | boolean | |

*Source: warcraft.wiki.gg API_C_CooldownViewer.GetCooldownViewerCooldownInfo.*

**Note the wiki marks `overrideSpellID` / `overrideTooltipSpellID` as 12.1
additions, yet our 12.0.7 code already reads them and works.** Either the
annotation is wrong or they arrived early. Harmless — both reads are guarded —
but do not "fix" that code on the strength of the wiki alone.

**`isInvisible`** looks like "in the data but should not be shown". Worth
filtering in `Data.BuildSpellList` so hidden entries stay out of the picker.
Verify what it actually means before relying on it.

## Cooldown Manager — new source files on PTR

`Gethe/wow-ui-source` `ptr` branch has files absent from `live`:

- `CooldownViewerSecure.lua`
- `CooldownViewerDraggedItemBase.lua` / `.xml`
- `CooldownViewerEditAlertBase.lua` / `.xml`

`CooldownViewerSecure.lua` is the one to read first — if any of the viewer moves
into a secure/protected path, addon interaction with it may change. Read it
before 12.1 goes live:

```sh
gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSecure.lua?ref=ptr" --jq .content
```

---

## Patch-day checklist

- [ ] Bump `## Interface:` in `ThugUI.toc`
- [ ] `lua Tests/loadtest.lua .` — expect breakage in the stubbed APIs first
- [ ] `/thugcv probe` on each played spec; diff against pre-patch output
- [ ] Confirm the picker still lists everything it did before
- [ ] Confirm Roll the Bones still resolves through `linkedSpellIDs`
- [ ] Re-check `isActive` / `isOnGCD` still exist and are non-secret
      (`DECISIONS.md` §5 — the whole readiness path rests on this)
- [ ] Read `CooldownViewerSecure.lua` for protected-path changes
- [ ] Iterate the category enum rather than naming categories
- [ ] Re-check every entry in `docs/SOURCES.md` and update its last-checked date
- [ ] Move anything still true into `DECISIONS.md`, delete this file, start 12.2
