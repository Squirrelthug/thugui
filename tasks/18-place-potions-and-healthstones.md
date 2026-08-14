# Task 18 — Potions and healthstones: a second kind of placement

**Read `tasks/00-AGENT-BRIEF.md` first.** This file carries the design
decisions. **Execute them; do not re-decide them.** On a genuine ambiguity,
**stop and report** rather than resolving it.

Baseline from a clean tree: `lua Tests/loadtest.lua .` → **203 passing, 0
failures**.

---

## The problem, in one line

12.1 puts potions and healthstones in the Cooldown Manager as entries with
**no spell ID at all**, identified only by `spellCategoryID` — and every
placement in this addon is keyed by spell ID, so they are dropped silently and
cannot be placed on the grid.

Full background: `docs/DECISIONS.md` §25. Read it. It records what was verified
against Blizzard's source and, just as importantly, what was **not**.

---

## Decision 1 — discover them, never hardcode them

**Do not hardcode 4 / 30 / 1711.** This is the player's explicit instruction and
the evidence backs it: Blizzard's own (unexported) table carries a **fourth**
category, **2566 Demonic Healthstone**, which has no named constant anywhere.
A hardcoded list of three was already wrong before it was written. Note that
2566 is therefore the **best** category to write a discovery test against.

There is **no API that enumerates spell categories** — confirmed absence, §25.
The only verified discovery path is the sweep this addon already performs:

> walk `cooldownID`s via `C_CooldownViewer.GetCooldownViewerCategorySet` for each
> `Enum.CooldownViewerCategory`, then read `.spellCategoryID` off each entry.

`Data.BuildCooldownInfoCache` (`modules/CooldownViewer/Data.lua:640-666`) and
`Data.DumpCooldownViewer` (~`:697-749`) already walk exactly this ground, and
the dump already reads the field. **Collect distinct `spellCategoryID` values
where `Data.PickerSpellIDFor(info)` returns nil.** That yields the categories
that are actually true for this character, which is better than any global list.

## Decision 2 — a second identity field, not a fake spell ID

A saved placement is `{ spellID = n, mode = "..." }` (`Data.SetPlacement`,
`Data.lua:398-403`). It gains an alternative:

```lua
{ categoryID = 4, mode = "cooldown" }   -- exactly one of spellID/categoryID
```

**Do not smuggle a string or a negative number into `spellID`.** The field name
would lie, and every `C_Spell.*` call site needs a guard either way.

Add one helper next to `PickerSpellIDFor`:

```lua
--- A non-nil identity for any placement, for keying and equality only.
--- Never pass this to a C_Spell/C_Item API -- it is not a spell ID.
function Data.PlacementKey(p)
    if not p then return nil end
    if p.spellID then return p.spellID end
    if p.categoryID then return "cat:" .. p.categoryID end
    return nil
end
```

Use it at the **keying and equality** sites, which then need no branching:
picker row key, drag payload, the armed-row comparison, `Data.IsSpellPlaced`.
The sites that call a game API (`C_Spell.GetSpellTexture`, `GetSpellInfo`,
`GameTooltip:SetSpellByID`) must **branch** instead.

`Data.GetPlacements` (`Data.lua:379-386`) currently guards on
`placement and placement.spellID` and so **drops a category placement before
anything downstream sees it**. That guard is the single most important line in
this task.

## Decision 3 — name and icon come from Blizzard's own frame

Blizzard's name and icon for these live in a `local`, unexported table we cannot
read. But they are exposed as **methods on their pooled item frame**, and §13's
`BlizzBuffs` already matches our placements to those frames on `cooldownID` and
calls methods on them (`item:GetCooldownID()`).

Resolution order, first that answers wins:

1. Their pooled item frame for this `cooldownID` → `GetSpellTexture()` and
   `GetNameText()`. Localised and correct for all four categories.
2. `C_Spell.GetLastCategoryCooldownSource(categoryID)` → `spellID, itemID` →
   name/icon from the item. **`MayReturnNothing = true`** — it returns nothing
   until the player has triggered that category this session, and that is the
   **normal** case on a fresh login, not an error. Blizzard's own handling is a
   bare `if spellID and itemID then`.
3. A generic label so the row is never nameless, e.g. `"Consumable (category N)"`.

**Reading their frame is fine. Writing to it is what caused §15's taint bug** —
do not set any field on a Blizzard frame, do not call their `RefreshLayout`.

## Decision 4 — drawing

Follow the existing **item-cell** branch, which is the closest relative:
`icon.equipSlot` is set at `Core.lua:706` and dispatched with
`elseif icon.equipSlot then` at `Core.lua:930`. Add `icon.categoryID` the same
way, as a sibling branch.

Cooldown comes from the resolved **item**: `C_Item.GetItemCooldown(itemID)`,
which carries **no `SecretWhen*` flag at all** (§20) — plain numbers in combat.

**`C_Spell.GetLastCategoryCooldownSource` carries `SecretWhenCooldownsRestricted`.**
Screen its returns with `issecretvalue` **before** any nil test — comparing a
secret to nil is itself the operation that throws. Use `Readable()` in
`Core.lua`; do not hand-roll it.

When nothing resolves, the cell draws its generic icon and no sweep. **Never
hide the cell on a failed resolve** — an empty cell is indistinguishable from a
broken addon, which is the §13 failure shape this project keeps hitting.

## Explicitly out of scope

- **Do not touch `Data.IndexableSpellIDs` or the reverse-lookup cache.** A
  category entry has no spell IDs to index and does not belong in it.
- **Do not add these to `BB:ShouldAdopt`.** `BlizzBuffs.lua:217-223` refuses an
  icon with no `spellID`, and that stays — we draw these ourselves.
- Do not change the curated source menu's hand-written list (§8). New rows
  arrive through the existing category sweep.

---

## Tests — required

`Tests/loadtest.lua`. The stub needs a `spellCategoryID`-only entry — it already
supports an absent `spellID` (see the entry at ~`:416`), so add:

```lua
_G.__cooldownEntries[N] = { cooldownID = N, spellCategoryID = 4, linkedSpellIDs = {} }
```

and a stub for `C_Spell.GetLastCategoryCooldownSource`, which **does not exist
in the harness today** — model both of its real behaviours: returning a pair,
and **returning nothing at all**.

Cases, each of which must fail against the unmodified code:

1. A `spellCategoryID`-only entry appears in the picker with a name and an icon.
2. Discovery finds a category the code does not name — use **2566**, not 4 —
   proving nothing is hardcoded.
3. A category placement survives `Data.GetPlacements` rather than being dropped.
4. `Data.PlacementKey` is distinct for spell `4` and category `4`. **A string
   key and a number key must not collide.**
5. `GetLastCategoryCooldownSource` returning nothing draws the cell anyway, with
   no sweep and no error.
6. A **secret** return from it does not throw and does not hide the cell.
7. Placing a category entry and a spell in adjacent cells leaves both drawing.

**Do not repurpose an existing test.** If one becomes wrong, leave it failing and
draft its replacement in your report.

---

## Deliverables

- `luac -p` clean on every file touched.
- `lua Tests/loadtest.lua .` — report the count and the exact text of any failure.
- For each added test, state that you ran it against **unmodified** code and it
  failed. The coordinator re-runs these.
- **Leave everything uncommitted. No state-changing git commands.**
- **Do not edit `docs/`.** Draft entries into your report.
- Report to `tasks/reports/18-place-potions-and-healthstones.md`.
  **No report file means the task did not happen.**
