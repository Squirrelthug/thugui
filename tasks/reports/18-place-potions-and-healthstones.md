# 18 — Place potions and healthstones — report

**Status:** complete

## What I changed

12.1's potion/healthstone entries in the Cooldown Manager carry no spell ID at
all, only a `spellCategoryID`, so `Data.GetPlacements` was silently dropping
any placement made for one before anything downstream ever saw it. I gave a
category placement a second, explicit identity (`{ categoryID = n, mode }`,
never smuggled into `spellID`), fixed the drop in `GetPlacements`, and added
`Data.PlacementKey` so every keying/equality site (picker row identity, drag
payload, armed-row comparison, `Data.IsSpellPlaced`) can treat a spell and a
category the same way without a type collision (spell 4 and category 4 must
never compare equal — `PlacementKey` returns the bare number for a spell and
the string `"cat:N"` for a category, which can never collide as a table key).

Discovery is never hardcoded: `Data.DiscoverCategoryIDs` and the picker's
category collection both walk the same live sweep the addon already performs
(`C_CooldownViewer.GetCooldownViewerCategorySet` per `Enum.CooldownViewerCategory`,
reading `.spellCategoryID` off each entry where `Data.PickerSpellIDFor(info)`
returns nil) rather than trusting a list of known IDs.

Name and icon for a category placement (`Data.CategoryEntry`) follow the
three-step resolution order the task specified: Blizzard's own pooled item
frame for the category's `cooldownID` (`GetSpellTexture()`/`GetNameText()`,
read-only — nothing is written to their frame), then
`C_Spell.GetLastCategoryCooldownSource` (screened with `issecretvalue` before
any nil test, since it carries `SecretWhenCooldownsRestricted` and
`MayReturnNothing`), then a generic label so the row is never nameless. I
added `BB:ItemForCooldownID` to `BlizzBuffs.lua` as the public read-only
lookup this needed.

Drawing (`Core.lua`) follows the existing item-cell (`equipSlot`) branch as a
sibling: `icon.categoryID` is set in `Rebuild` alongside `icon.equipSlot`, and
`UpdateState` gained an `elseif icon.categoryID then` branch that resolves the
current item via `ResolveCategoryItem` (wraps `GetLastCategoryCooldownSource`,
fails open — `itemID = nil` — on nothing-returned, on a throw, and on a secret
return) and reads its cooldown via `C_Item.GetItemCooldown` (no `SecretWhen*`
flag at all, so plain numbers). An unresolved source always draws the cell,
with no sweep — never hidden, matching the item-cell precedent's "fail
visible" rule and the §13 lesson that an empty cell reads as a broken addon.

I also touched three call sites that would otherwise pass a `nil` spellID
into a `C_Spell.GetSpellInfo`/`GetSpellTexture` call once `GetPlacements`
started returning category placements: the `/thugcv status` "unknown
spells" loop and the state-snapshot capture in `modules/Diagnostics.lua`,
both now skip/branch on `placement.spellID`. The settings page
(`ui/pages/CooldownViewer.lua`) needed the largest share of this: picker row
identity, drag/drop, the armed-row toggle, the grid-cell tooltip, the
grid-cell texture, and the inspector's selected-icon label all branch on
`categoryID` vs `spellID` now, via two small helpers (`PlacementIdentity`,
`IdentityTexture`) rather than five slightly different inline checks.

Nothing under `Data.IndexableSpellIDs`/the reverse spell-ID cache was
touched — a category cache (`categoryInfoCache`) is kept entirely separate, on
purpose. `BB:ShouldAdopt` was not touched either; it already refuses any icon
with no `spellID`, which now correctly excludes every category icon without
any new code.

## Files touched

| File | What |
|---|---|
| `modules/CooldownViewer/Data.lua` | `Data.PlacementKey`, `Data.SetCategoryPlacement`, category discovery/cache (`Data.GetCategoryInfo`, `Data.DiscoverCategoryIDs`, `Data.CategoryEntry`), fixed `Data.GetPlacements` to stop dropping category placements, `Data.IsSpellPlaced` now compares via `PlacementKey`, `Data.BuildSpellList` collects category entries alongside spell entries |
| `modules/CooldownViewer/Core.lua` | Category-cell helpers (`ResolveCategoryItem`, `IsCategoryReady`, `ApplyCategorySweep`); `Rebuild` sets/resets `icon.categoryID` and branches texture/spellName resolution; `UpdateState` gained the `elseif icon.categoryID then` drawing branch; `/thugcv status`'s unknown-spell loop skips category placements |
| `modules/CooldownViewer/BlizzBuffs.lua` | Added `BB:ItemForCooldownID(cooldownID)`, a public read-only lookup |
| `modules/Diagnostics.lua` | `CaptureProfiles` guards `C_Spell.GetSpellInfo` on `placement.spellID` and labels a category placement in the snapshot |
| `ui/pages/CooldownViewer.lua` | `Page.armed` replaces `Page.armedSpellID` as an identity table; new `PlacementIdentity`/`IdentityTexture` helpers; drag payload, picker row, grid-cell tooltip/texture, and the inspector's selected label all branch on `categoryID` vs `spellID` |
| `Tests/loadtest.lua` | New `C_Spell.GetLastCategoryCooldownSource` and `C_Item` (`GetItemCooldown`/`GetItemNameByID`/`GetItemIconByID`) stubs; new "-- category cells (potions and healthstones) --" section, 8 cases plus a restore step |

## Verification

```
$ luac -p modules/CooldownViewer/Data.lua modules/CooldownViewer/Core.lua modules/CooldownViewer/BlizzBuffs.lua modules/Diagnostics.lua ui/pages/CooldownViewer.lua Tests/loadtest.lua
(no output — all clean)
```

```
$ lua Tests/loadtest.lua .
...
-- category cells (potions and healthstones) --
ok         a spellCategoryID-only entry appears in the picker with a name and an icon
ok         discovery finds a category the code does not name (2566), never a hardcoded list
ok         a category placement survives Data.GetPlacements rather than being dropped
ok         Data.PlacementKey is distinct for spell 4 and category 4
ok         GetLastCategoryCooldownSource returning nothing draws the cell anyway, with no sweep and no error
ok         a secret return from GetLastCategoryCooldownSource does not throw and does not hide the cell
ok         placing a category entry and a spell in adjacent cells leaves both drawing
ok         once resolved, the category item's own cooldown drives cooldown/recharging/always modes
ok         restore
...
ok         page cooldownviewer fits (632px of 654px)
...
0 failure(s)
```

212 "ok" lines total (203 baseline + 9 new steps in the category-cells
section, 8 real cases plus its restore step). 0 failures.

## Tests added

All 8 in the new "-- category cells (potions and healthstones) --" section of
`Tests/loadtest.lua`, corresponding 1:1 to the task's required cases:

1. `a spellCategoryID-only entry appears in the picker with a name and an icon`
2. `discovery finds a category the code does not name (2566), never a hardcoded list`
3. `a category placement survives Data.GetPlacements rather than being dropped`
4. `Data.PlacementKey is distinct for spell 4 and category 4`
5. `GetLastCategoryCooldownSource returning nothing draws the cell anyway, with no sweep and no error`
6. `a secret return from GetLastCategoryCooldownSource does not throw and does not hide the cell`
7. `placing a category entry and a spell in adjacent cells leaves both drawing`

Plus one extra beyond the required list, covering the success path rather than
only the fail-open ones:

8. `once resolved, the category item's own cooldown drives cooldown/recharging/always modes`

**Confirmed failing against unmodified code**, not just reasoned about: I
copied the new `Tests/loadtest.lua` aside, `git stash`ed every other change
(returning `Data.lua`/`Core.lua`/`BlizzBuffs.lua`/`Diagnostics.lua`/
`ui/pages/CooldownViewer.lua` to HEAD), dropped the new test file back in
place of the reverted one, and ran the suite against that combination. All 8
cases failed:

```
STEP FAIL  a spellCategoryID-only entry appears in the picker with a name and an icon
           Tests/loadtest.lua:3783: the category-4 entry never appeared in the essential picker
STEP FAIL  discovery finds a category the code does not name (2566), never a hardcoded list
           Tests/loadtest.lua:3794: attempt to call a nil value (field 'DiscoverCategoryIDs')
STEP FAIL  a category placement survives Data.GetPlacements rather than being dropped
           Tests/loadtest.lua:3806: attempt to call a nil value (field 'SetCategoryPlacement')
STEP FAIL  Data.PlacementKey is distinct for spell 4 and category 4
           Tests/loadtest.lua:3814: attempt to call a nil value (field 'PlacementKey')
STEP FAIL  GetLastCategoryCooldownSource returning nothing draws the cell anyway, with no sweep and no error
           Tests/loadtest.lua:3755: attempt to call a nil value (field 'SetCategoryPlacement')
STEP FAIL  a secret return from GetLastCategoryCooldownSource does not throw and does not hide the cell
           Tests/loadtest.lua:3755: attempt to call a nil value (field 'SetCategoryPlacement')
STEP FAIL  placing a category entry and a spell in adjacent cells leaves both drawing
           Tests/loadtest.lua:3848: attempt to call a nil value (field 'SetCategoryPlacement')
STEP FAIL  once resolved, the category item's own cooldown drives cooldown/recharging/always modes
           Tests/loadtest.lua:3755: attempt to call a nil value (field 'SetCategoryPlacement')

8 failure(s)
```

("restore" passed trivially in both runs — it is cleanup, not an assertion.)
I then `git checkout`ed the temporary test file and `git stash pop`ped to
restore the full implementation; `diff --strip-trailing-cr` confirmed
`Tests/loadtest.lua` came back byte-identical (modulo CRLF) to what I had
before the stash, and the full suite was re-run clean (0 failures) afterward.

No existing test was repurposed or rewritten. `git diff --stat` shows only
additions inside existing functions plus new functions/sections; nothing was
deleted from `Tests/loadtest.lua` other than the lines the edits directly
replaced (documented above).

## Sources used

- `repos/Gethe/wow-ui-source` @ `live`, `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua`
  — confirmed `C_Spell.GetLastCategoryCooldownSource(spellCategory) -> spellID?, itemID?`
  with `MayReturnNothing = true` and `SecretWhenCooldownsRestricted = true`, exactly as
  `docs/DECISIONS.md` §25 records.
- `repos/Gethe/wow-ui-source` @ `live`, `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
  — confirmed `C_Item.GetItemCooldown(itemInfo) -> startTimeSeconds, durationSeconds, enableCooldownTimer`
  carries no `SecretWhen*` flag (only `SecretArguments = "AllowedWhenUntainted"`, which is
  about the argument, not the return), and confirmed `C_Item.GetItemIconByID`/`GetItemNameByID`
  exist with the signatures used here (`itemInfo -> icon`/`itemName`, both nilable, no
  `SecretWhen*` flag either).
- `repos/Gethe/wow-ui-source` @ `live`, `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua`
  — confirmed `CooldownViewerItemDataMixin:GetSpellTexture()` and `:GetNameText()` exist and are
  the methods §25/the task named; also confirmed the local `spellCategoryMetadataLookup` table
  (lines ~405-434) carries exactly the four categories `docs/DECISIONS.md` §25 already recorded
  (4, 30, 1711, 2566 — Demonic Healthstone with no named constant), which is what the 2566 test
  case is built against.

## Proposed docs changes

**`docs/DECISIONS.md` §25** — the section is currently marked "PROPOSED
2026-08-13, NOT YET APPROVED OR BUILT". Since this task built it, I'd propose
replacing that closing note with something like:

> ### Built — task 18, 2026-08-15 (correct in code, not yet verified in game)
>
> The design above was built as proposed, with one addition beyond what was
> specified: `Data.CategoryEntry`'s resolution order (Blizzard's pooled item
> frame → `GetLastCategoryCooldownSource` → generic label) is shared by BOTH
> the picker row and the drawn cell, via one function, rather than two
> separate implementations that could drift apart. `BB:ItemForCooldownID` was
> added to `BlizzBuffs.lua` as the public read-only lookup this needed —
> `BB:ItemsByCooldownID()` already existed but was only ever called from
> inside `BB:Apply`.
>
> Whether the resolution order actually reaches step 1 (Blizzard's pooled
> frame) or step 2 (`GetLastCategoryCooldownSource`) for a real potion or
> healthstone in the running game is **unverified** — see `docs/HANDOFF.md`.

**`docs/HANDOFF.md`** — I'd propose adding a row/entry noting: potion and
healthstone placement is *correct in code, not verified in game*. Specifically
unverified: which `Enum.CooldownViewerCategory` these actually arrive under
for a real character (§25 already flagged this as unmeasured); whether
Blizzard's pooled item frame is reliably present for these categories the way
it is for trinkets (the resolution order's step 1 has never been exercised
against a live client); and whether `C_Spell.GetLastCategoryCooldownSource`
behaves as documented once a potion/healthstone has actually been used in a
session.

## Could not do

Nothing was blocked. The task file's design decisions (1-4) were unambiguous
enough to execute without needing to stop and ask.

One judgment call worth flagging as a call, not an ambiguity: the task didn't
explicitly list `ui/pages/CooldownViewer.lua`'s picker-row/tooltip/texture/
inspector sites in its numbered decisions, but Decision 2 explicitly named
"picker row key, drag payload, the armed-row comparison" as PlacementKey
sites and "GameTooltip:SetSpellByID" as a site that "must branch instead" —
both of which only exist in that file — so I read the file as in-scope and
edited it fully rather than leaving the picker unable to place what discovery
now finds. Flagging this because the task had no "Files you may modify"
section to check against (unusual for this project's task files), so I'm
naming the reasoning rather than silently assuming it.

## Noticed but did not touch

- `ui/pages/CooldownViewer.lua`'s "Selected icon" panel and its
  `Data.MODES` dropdown work unchanged for a category placement (mode is
  stored/read the same way regardless of identity), but a category cell in
  `"aura"` mode would try to resolve a buff from a `nil` `icon.spellID` in
  `Core.lua`'s `ResolveAura`/`GetPlayerCastAura` path — this degrades safely
  (both already guard on their spellID argument being present) rather than
  drawing anything wrong, but "aura" mode is a meaningless choice for a
  potion/healthstone and the mode dropdown does not know to hide or discourage
  it. Not a bug — the task never asked for mode-list curation by placement
  kind — but worth a note if this ever gets a design pass.
- The `/thugcv probe` dump and the `/thugcv status` "buff-mode icons" readout
  both already handle `spellCategoryID` fine (the probe dumps the raw field;
  status's buff-mode loop only ever looks at aura-mode icons, which a
  category placement realistically never is), so neither needed a change.
- `Data.ResolveSpell` (the settings page's "add manually" box) still only
  resolves a typed spell name or ID — there is no equivalent manual-entry path
  for a category ID, and the task's Decision 1 explicitly rules that out
  ("discover them, never hardcode them" — a player typing a raw category
  number would be exactly the hardcoding this task exists to avoid), so this
  is expected, not an oversight.

## Not verified

Everything about how this behaves in the actual running game, per §4 of
`tasks/00-AGENT-BRIEF.md`. Specifically:

- Whether potions/healthstones actually appear in the picker for a real
  character, under whichever `Enum.CooldownViewerCategory` the client files
  them under (§25 already flagged this as unmeasured; nothing here measures
  it either — the loadtest harness's category sets are entirely synthetic).
- Whether `Data.CategoryEntry`'s resolution order actually reaches step 1
  (Blizzard's pooled item frame via `BB:ItemForCooldownID`) for a potion or
  healthstone specifically — trinkets are the only category this addon has
  ever confirmed adoption works for in game.
- Whether `C_Spell.GetLastCategoryCooldownSource` returns what the
  documentation says once a potion/healthstone has actually been used this
  session, and whether its secrecy behaves as `SecretWhenCooldownsRestricted`
  implies in actual combat.
- Whether the drawn cell's icon, cooldown sweep, and mode behavior
  (cooldown/recharging/always/proc) look correct on screen for a real potion
  or healthstone placement.
- Whether the generic fallback label/icon (`"Consumable (category N)"`,
  `INV_Misc_QuestionMark`) is ever actually seen by the player, or whether
  step 1 or step 2 always resolves first in practice.
- Whether dragging a category picker row onto the grid, and dragging a placed
  category icon between cells, behaves correctly — the loadtest harness
  exercises the underlying `Data`/`Core` functions but not the frame-level
  drag machinery in `ui/pages/CooldownViewer.lua` (`GetCursorPosition`,
  `IsMouseOver`, etc. are stubbed generically, not exercised by these tests).
