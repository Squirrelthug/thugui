# Task 14 — Item-backed cells, and a "show while recharging" mode

Read `00-AGENT-BRIEF.md` first.

Two changes that share a cause. Do both; they are one task because the second is
the mode the first one needs to be useful.

## Background, measured this session

12.1 puts equipped items in the Cooldown Manager. The player placed their
trinket's on-use — **Radiant Blessing, spell 1254624, `equipSlot = 13`,
category `EquipSlotEssential`, cooldownID 198603** — on the grid. It draws in
`always` mode and **draws nothing at all in `cooldown` mode.**

That is not a mystery, it is the code doing what it says:

- `Core.lua:773` — *"Adoption outranks our own IsSpellAvailable check"* — sits
  above the availability gate at `Core.lua:785`, and the mode branches are below
  at `:840`.
- In `always` mode `BB:ShouldAdopt` returns true on the mode alone, the cell is
  adopted, the gate is skipped, and Blizzard's frame draws it.
- In `cooldown` mode nothing adopts it, so it reaches
  `IsSpellAvailable(spellName)` — which calls `C_Spell.GetSpellInfo` **by name**.
  Name resolution is spellbook-scoped, and a trinket's on-use spell is not in the
  spellbook. It answers "not talented" and the icon never draws.

The by-name rule (`DECISIONS.md` §5) is right for spells and is why Swiftmend
gaining a charge in this patch needed no code change. It is simply wrong for
items, which are identified by the slot they sit in.

**Item cooldowns are not secret.** `C_Item.GetItemCooldown` carries no
`SecretWhen*` flag, and Blizzard's own `CooldownViewer.lua:1020` reads an item
cooldown with `GetInventoryItemCooldown("player", equipSlot)`. So an item cell
needs none of the secret-value machinery a spell cell needs — including in
combat, where it can sweep with plain `SetCooldown`.

## Change 1 — item-backed cells

**An icon is item-backed when its Cooldown Manager entry carries `equipSlot`.**
`Data.GetCooldownInfoForSpell(icon.spellID)` already returns that entry, and
`equipSlot` is already dumped by the probe. Capture it onto the icon where the
other per-icon fields are set, and branch on it.

`spellCategoryID` entries — the potions and the healthstone — are **out of
scope**. They have no spell ID at all and need a placement-model change that is
its own task. Do not attempt them. If you find yourself adding a second
placement kind, stop and report.

### Availability

An item cell must not be gated on a spellbook name lookup. It is available when
something is actually equipped in that slot. Blizzard's own test is
`ItemLocation:CreateFromEquipmentSlot(equipSlot)` followed by
`itemLocation:IsValid()` (`CooldownViewerItemData.lua:286`). Use that, guarded so
a missing `ItemLocation` global cannot throw.

### Readiness

Add a separate readiness function for items rather than branching inside
`IsSpellReady` — the two share no logic and `IsSpellReady`'s comment block is
load-bearing documentation about secret values that does not apply to items.

Read the cooldown with `GetInventoryItemCooldown("player", equipSlot)`, which is
what Blizzard uses for exactly this. Ready means no cooldown is running.

**Route every value through the existing `Readable()` helper anyway.** That
global is not in the generated API documentation, so it has no measured secrecy
posture and this session measured nothing about it. If a value is unreadable,
**fail visible** — treat the item as ready and draw the icon — and log it once
through `ThugUI.Diagnostics:LogOnce`. A reminder that shows too eagerly beats one
that vanishes mid-fight; that is the rule `IsSpellReady` already follows and the
reason is in its comment.

`Readable()` asks `issecretvalue` **first** and tests nil **second**, because
comparing a secret is the operation that errors. Do not write your own nil test
on a value that came from the game.

### Sweep

`ApplySweep` reads `C_Spell.GetSpellCooldown`, which is meaningless for an item.
Give item cells their sweep from the same `GetInventoryItemCooldown` values.
Unlike the spell path, these are ordinary numbers, so plain `SetCooldown` works
**including in combat** — but keep the existing `pcall` discipline around it.
`DECISIONS.md` §19: an uncaught throw inside the per-icon loop leaves every icon
the loop has not reached yet frozen at its previous state, and `pairs()` ordering
makes which ones freeze change between sessions.

### Deliberately unchanged

- **Artwork stays as it is.** The icon currently resolves from the spell and the
  player has seen it and not objected. Switching to the item texture is a visible
  change and this task must not make one beyond the trinket starting to appear.
- **`BB:ShouldAdopt` is unchanged.** The player's two trinket *buffs* (Alnsight,
  Alnscorned Essence) work today in `aura` mode through adoption. Do not disturb
  that path.

## Change 2 — a "recharging" mode

`cooldown` mode means *show while ready, hide once spent*. There is no mode
meaning the inverse, and for a trinket or a potion timer the inverse is what you
want: show it while it is coming back, hide it once it is up.

Add mode **`recharging`**, labelled **"Show while recharging"**.

- Semantics: the exact inverse of `cooldown` — visible when the ability is *not*
  ready, hidden when it is. Derive it from the same readiness answer rather than
  writing a second test, so the two can never disagree.
- It gets a sweep, for both spells and items. The sweep is the whole point.
- `BB:ShouldAdopt` must return **false** for it, like `cooldown`. Do not add it
  to the adopted set. For a spell, `isActive` is readable in combat so our own
  rendering is already correct; for an item nothing is secret at all.
- Register it everywhere the existing modes are registered — `Data.ModeText`,
  whatever validates a stored mode, and the mode selector in the config UI. Find
  them all; a mode that exists in the data and not in the picker is unreachable,
  and one that exists in the picker and not in the validator gets silently
  rewritten on load.

## Verify

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Baseline is **180 passing, 0 failures**. It must not go down.

Add cases covering:

1. An icon whose entry has `equipSlot` is **not** gated on the spellbook name
   lookup — the case that is broken today. Assert it draws where the current code
   does not.
2. An item cell with an empty equipment slot is treated as unavailable.
3. An unreadable item cooldown value fails **visible** and does not throw.
4. `recharging` is the inverse of `cooldown` for the same readiness answer.
5. `BB:ShouldAdopt` returns false for `recharging`.

**Add cases. Never rewrite an existing one in place** — the coordinator diffs the
`ok` lines against a stashed clean tree and will find it. Before claiming a test
proves anything, run it against the **unmodified** files and confirm it fails.
State the exact failing assertion in your report.

The harness stubs are a hazard in their own right: §19 records that
`SetCooldown` in `loadtest.lua` accepted secrets when the real client refuses
them, so no test could have caught a real bug. If you add a stub for
`GetInventoryItemCooldown` or `ItemLocation`, make it behave like the game,
including the ways it fails.

## Boundaries

- Do not touch `modules/SecretProbe.lua`.
- Do not change `BB:ShouldAdopt`'s existing branches; only ensure `recharging`
  is not adopted.
- Do not add a second placement kind. Potions are a later task.
- Do not edit anything in `docs/`. Draft proposed entries into your report.
- Do not run any state-changing git command. Leave the work uncommitted on branch
  `charge-spells-can-hide`.

## Report

Write `tasks/reports/14-item-cells-and-recharging-mode.md`. **No report file
means the task did not happen.**

Include the diff in prose, the before/after test output with the exact assertion
that failed against the unmodified code, every place you had to register the new
mode (so the coordinator can check none was missed), and **anything in this task
file that turned out to be wrong** — two previous agents found errors in their
task files and both were the most useful thing in the report.
