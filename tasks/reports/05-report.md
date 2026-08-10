# 05 — An adopted cell must be reserved, whatever our own spell lookup thinks — report

**Status:** complete

## What I changed

Reordered `CV:UpdateState` in [modules/CooldownViewer/Core.lua](file:///C:/Program%20Files%20%28x86%29/World%20of%20Warcraft/_retail_/Interface/AddOns/ThugUI/modules/CooldownViewer/Core.lua#L681) so that `adopted` is evaluated before `IsSpellAvailable(spellName)`. When Blizzard's untainted frame adopts a buff item, ThugUI defers to Blizzard's authority and reserves the cell regardless of whether our by-name spell lookup (`C_Spell.GetSpellInfo`) resolves. This resolves cases like Opportunity (passive spell ID 279876 granting buff 195627) which fail by-name lookups but are actively drawn by Blizzard, ensuring the cell remains reserved in the grid and properly included during grid collapse passes. Updated inline comments above `adopted` to document why adoption outranks spell availability checks.

## Files touched

| File | What |
|---|---|
| [modules/CooldownViewer/Core.lua](file:///C:/Program%20Files%20%28x86%29/World%20of%20Warcraft/_retail_/Interface/AddOns/ThugUI/modules/CooldownViewer/Core.lua) | Reordered `adopted` check before `IsSpellAvailable` gate in `CV:UpdateState` and updated rationale comment |
| [Tests/loadtest.lua](file:///C:/Program%20Files%20%28x86%29/World%20of%20Warcraft/_retail_/Interface/AddOns/ThugUI/Tests/loadtest.lua) | Added three test cases under `blizzard buff items` covering adopted unresolved spells, column collapse reservation, and non-adopted unresolved spell hiding |
| `tasks/reports/05-report.md` | Execution report |

## Verification

```sh
$ luac -p modules/CooldownViewer/Core.lua Tests/loadtest.lua
# exit code 0, no output
```

```sh
$ lua Tests/loadtest.lua .
-- blizzard buff items --
ok         an aura icon is adopted by its Blizzard item
ok         the item is anchored over the cell
ok         our own art is suppressed but the cell is kept
ok         nothing is written onto Blizzard's frames
ok         our icon is lowered, their viewer is left alone
ok         a hidden grid hands the buffs back
ok         switching it off restores the aura path
ok         an unmatched spell logs no item frame stage once
ok         an adopted icon is shown even when its spell name does not resolve
ok         an adopted cell keeps its slot under columns collapse
ok         a non-adopted icon whose spell does not resolve is still hidden
ok         an Apply error is logged and applying flag is cleared
ok         restore

-- combo pips --
ok         initialize
ok         one pip per point of maximum
ok         gaining a point lights another pip
ok         a changed maximum re-lays out
ok         pips are evenly spaced around the ring
ok         a tight ring never flips to the other side
ok         no pips for a class without a secondary resource
ok         a druid gets pips only in cat form
ok         a secret power value holds the last layout
ok         hidden when switched off
ok         restore

-- secret probe --
ok         records a sample with readable values
ok         a secret power value is described, not read
ok         a secret aura struct does not throw
ok         a missing API is reported, not fatal
ok         a thin sample never buries a rich one

0 failure(s)
```

## Tests added

Added three test cases in [Tests/loadtest.lua](file:///C:/Program%20Files%20%28x86%29/World%20of%20Warcraft/_retail_/Interface/AddOns/ThugUI/Tests/loadtest.lua):
1. `an adopted icon is shown even when its spell name does not resolve`: Models Opportunity by setting `_G.__unknownNames["Spell 9001"] = true` for an adopted aura item. Asserts `icon.wanted` is true and `icon:IsShown()` is true.
2. `an adopted cell keeps its slot under columns collapse`: Verifies that an adopted icon whose spell name fails resolution retains its slot under `collapse = "columns"` rather than being omitted from `live` groups and left at its uncollapsed coordinate.
3. `a non-adopted icon whose spell does not resolve is still hidden`: Ensures non-adopted icons whose spell names do not resolve remain hidden (`icon.wanted == false`).

**Confirmation of failure on old code:** Reverting `Core.lua` to check `IsSpellAvailable` before `adopted` caused tests 1 and 2 to fail with:
- Test 1: `Tests/loadtest.lua:1650: an adopted cell whose spell name does not resolve was not wanted`
- Test 2: `Tests/loadtest.lua:1679: adopted cell was not wanted under columns collapse`

## Sources used

- `docs/DECISIONS.md` §5 (By-name spell availability lookup & spell readiness)
- `docs/DECISIONS.md` §13 (Adopted Blizzard buff items & cell reservation invariant)

## Proposed docs changes

### Draft for `docs/DECISIONS.md` §13 (under "The cost, stated plainly")

Add to the section note:
> Note on passive-backed placements: The invariant that an adopted cell is always reserved was previously stated but not strictly enforced because `IsSpellAvailable` (a by-name lookup) ran before the `adopted` check. Placements whose spell ID is a passive granting the buff (e.g. Opportunity 279876 granting buff 195627) do not resolve via `GetSpellInfo(name)`, causing `IsSpellAvailable` to return false and bypass the `adopted` branch. `CV:UpdateState` now checks `adopted` before `IsSpellAvailable` so Blizzard's live frame authority reserves the cell unconditionally.

### Draft for `docs/HANDOFF.md` §2 (table update)

Add row:
| Adopted passive-backed cells reserved in layout (e.g. Opportunity) | **Unverified in game** — harness proves adopted unresolved spells are wanted and reserve collapse slots; live rendering unverified |

## Could not do

None.

## Noticed but did not touch

- In `Data.SetPlacement(profile, row, col, spellID, mode)`, the parameter order is `(profile, row, col, spellID, mode)` whereas `CellKey(row, col)` uses `row .. ":" .. col`. Callers setting placements directly must be careful not to swap `row` and `col`.

## Not verified

This change is proven only in the harness. Whether Opportunity draws in the right cell, shows its radial timer, and shows stack counts of 3 and 6 can only be confirmed by the player in a live session.
