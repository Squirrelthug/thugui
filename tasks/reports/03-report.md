# 03 — Skip the negative pseudo-categories Blizzard injects into the enum — report

**Status:** complete

## What I changed
Updated `CooldownViewerCategories()` in `modules/CooldownViewer/Data.lua` to filter out negative values (`value >= 0`) when iterating `Enum.CooldownViewerCategory`. Blizzard injects negative pseudo-category entries (`HiddenSpell = -1`, `HiddenAura = -2`, renamed on 12.1 PTR to `HiddenActive` and `HiddenPassive`) into the enum at runtime in `Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua` to manage disabled states. Filtering by non-negative numeric value prevents disabled spells from leaking into the cache, dump, and "Everything" picker, and prevents false `LogOnce` unrecognized category warnings.

## Files touched
| File | What |
|---|---|
| `modules/CooldownViewer/Data.lua` | Added `value >= 0` check to `CooldownViewerCategories()` and documented Blizzard's runtime negative pseudo-category injection behavior. |
| `Tests/loadtest.lua` | Added test case `"Blizzard's negative pseudo-categories are ignored"`. |

## Verification
```
$ luac -p modules/CooldownViewer/Data.lua Tests/loadtest.lua
<clean exit, 0 errors>

$ lua Tests/loadtest.lua .
-- secret probe --
ok         records a sample with readable values
ok         a secret power value is described, not read
ok         a secret aura struct does not throw
ok         a missing API is reported, not fatal
ok         a thin sample never buries a rich one

0 failure(s)
```

## Tests added
- `"Blizzard's negative pseudo-categories are ignored"` in `Tests/loadtest.lua`: Injects `-1` (`HiddenSpell`) and `-2` (`HiddenAura`) into `Enum.CooldownViewerCategory` with dummy category sets and asserts that spells in negative pseudo-categories are ignored by `GetCooldownInfoForSpell`, `DumpCooldownViewer`, and `BuildSpellList("all", nil)`.
- Confirmed that temporarily removing `value >= 0` (allowing negative numbers) causes this test case to fail with `Tests/loadtest.lua:697: spell in negative pseudo-category was indexed by GetCooldownInfoForSpell`.

## Sources used
- `Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua` in `repos/Gethe/wow-ui-source` (live and ptr branches) for negative pseudo-category constants (`HiddenSpell = -1`, `HiddenAura = -2`).

## Proposed docs changes
- `docs/DECISIONS.md` §8: Add a note stating that `Enum.CooldownViewerCategory` is not a pure enum at runtime. Blizzard injects negative pseudo-categories (e.g. `HiddenSpell = -1`, `HiddenAura = -2` / `HiddenActive`, `HiddenPassive`) at runtime in `CooldownViewerSettingsConstants.lua` to track disabled states. Any code iterating `Enum.CooldownViewerCategory` must filter `value >= 0` rather than matching on category names, as category names change across client builds.

## Could not do
None.

## Noticed but did not touch
- `CATEGORIES_BY_SOURCE` in `Data.lua` remains an explicit hand-written table while `CooldownViewerCategories()` iterates the runtime enum. This is deliberate per design decisions so that "Everything" catches new patch categories automatically while curated lists maintain specific groupings.

## Not verified
- Behaviour on live 12.0.7 client when player has toggled hidden spells/auras in Blizzard's Cooldown Manager settings (unverified in running game).
