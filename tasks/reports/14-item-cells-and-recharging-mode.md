# 14 — Item cells and a "recharging" mode — report

**Status:** complete

## What I changed

Two changes, as scoped.

**Change 1 — item-backed cells.** An icon whose Cooldown Manager entry carries
`equipSlot` (Radiant Blessing's trinket slot, `equipSlot = 13`) is now captured
onto the icon in `CV:Rebuild` and, in `CV:UpdateState`, is routed through a new
item-only branch instead of the spellbook name gate
(`IsSpellAvailable(spellName)`). That gate was the whole bug: it resolves by
NAME, which only ever succeeds for a spell in the player's spellbook, and a
trinket's on-use spell never is one — so it silently answered "not talented"
and the icon never drew in `cooldown` mode, while `always` mode worked only
because adoption short-circuits the gate entirely.

The item branch adds three new functions, deliberately separate from the
spell-path equivalents rather than branched inside them (per the task, since
`IsSpellReady`'s comment block is load-bearing documentation about secrets that
does not apply to items):

- `IsItemAvailable(equipSlot)` — `ItemLocation:CreateFromEquipmentSlot(equipSlot)`
  then `:IsValid()`, Blizzard's own test, guarded against a missing
  `ItemLocation` global.
- `IsItemReady(equipSlot)` — reads `GetInventoryItemCooldown("player", equipSlot)`
  and treats `duration == 0` as ready. Every value goes through the existing
  `Readable()` helper (`issecretvalue` first, nil second) and an unreadable
  answer fails **visible** (treated as ready), logged once via
  `ThugUI.Diagnostics:LogOnce`.
- `ApplyItemSweep(icon, equipSlot)` — same source, plain `SetCooldown`, with the
  same `pcall` discipline `ApplySweep` uses (DECISIONS.md §19: nothing per-icon
  may throw uncaught).

Artwork and `BB:ShouldAdopt` are untouched for item cells specifically — an
item cell in `cooldown`/`recharging`/`always` mode is not a charge spell by
`IsChargeSpell`'s own name/ID lookup and is not `aura`/`always`-adopted unless
placed that way, so it draws itself, as intended.

**Change 2 — `recharging` mode.** Added to `Data.MODES` (label "Show while
recharging"), which is the single place the mode picker dropdown in
`ui/pages/CooldownViewer.lua` reads from — no other registration point exists
(see "Could not do" below for what I looked for and didn't find). In
`CV:UpdateState`, both the spell path and the new item path derive `show = not
ready` from the *same* `ready` local the neighbouring `cooldown` branch uses,
so the two can never disagree, and both call the sweep function for their kind
(`ApplySweep`/`ApplyItemSweep`) — the sweep is the point of the mode.
`BB:ShouldAdopt` gets one new guard line, `if icon.mode == "recharging" then
return false end`, added without touching any of its three existing branches.
Without it, a charge spell placed in `recharging` mode would have fallen
through to `IsChargeSpell` and been adopted by Blizzard's frame exactly as it
would in `cooldown` mode — Blizzard's item sweeps and dims rather than
disappearing, which is the wrong visual for a mode whose whole point is
appearing/disappearing.

## Files touched

| File | What |
|---|---|
| `modules/CooldownViewer/Core.lua` | Added `IsItemAvailable`, `IsItemReady`, `ApplyItemSweep`; capture `icon.equipSlot` in `Rebuild`; new item-cell branch and `recharging` branch in `UpdateState` |
| `modules/CooldownViewer/Data.lua` | Added `recharging` to `Data.MODES` (and its doc comment) |
| `modules/CooldownViewer/BlizzBuffs.lua` | `BB:ShouldAdopt` refuses `recharging` |
| `Tests/loadtest.lua` | New section "item cells and recharging mode" (8 cases + restore) |

## Verification

```
$ luac -p modules/CooldownViewer/Core.lua modules/CooldownViewer/Data.lua modules/CooldownViewer/BlizzBuffs.lua Tests/loadtest.lua
(no output — all four passed)
```

```
$ lua Tests/loadtest.lua .
...
-- item cells and recharging mode --
ok         an item cell is not gated on the spellbook name lookup
ok         an item cell with an empty equipment slot is unavailable
ok         an unreadable item cooldown fails visible and does not throw
ok         an item cell gets a sweep in always mode
ok         recharging is the inverse of cooldown, for the same item readiness
ok         recharging is the inverse of cooldown for a spell too
ok         BB:ShouldAdopt refuses recharging even for a charge spell
ok         recharging is registered in the mode picker
ok         restore
...
0 failure(s)
```

180 passing at the start of this session (confirmed before any edit) → **189
passing, 0 failures** now. The 9 new lines are the 8 assertion cases above plus
their own `restore` step. No existing `ok` line's wording changed —
`git diff -- Tests/loadtest.lua` is a pure insertion (245 insertions, 0
deletions) between the end of the "blizzard buff items" section and the start
of "combo pips"; no existing step body was touched.

## Tests added

All eight, in the new "item cells and recharging mode" section of
`Tests/loadtest.lua`, covering the five cases the task named plus three more
(sweep presence for items, the spell-side half of the inversion, and mode
registration):

1. **an item cell is not gated on the spellbook name lookup** — places
   `equipSlot=13` with the spell NAME marked unresolvable
   (`_G.__unknownNames["Spell 8500"] = true`), asserts the icon still draws.
2. **an item cell with an empty equipment slot is unavailable** — `__equipped[13]
   = false`, asserts hidden.
3. **an unreadable item cooldown fails visible and does not throw** —
   `GetInventoryItemCooldown` returns `__SECRET` values; also puts a
   *spell-side* cooldown state on the same spell ID so a build with no notion
   of `equipSlot` (the old code) would hide the icon via the ordinary spell
   path instead of failing visible — see below on why this mattered.
4. **an item cell gets a sweep in always mode** — item on a real (non-secret)
   cooldown, asserts `icon.cooldown.__cooldown` is set.
5. **recharging is the inverse of cooldown, for the same item readiness** —
   compares `wanted` for `cooldown` vs `recharging` at the same underlying
   state, ready and on-cooldown, plus a sweep-presence check.
6. **recharging is the inverse of cooldown for a spell too** — same inversion,
   using the existing `_G.__cooldownState` stub instead of the item one.
7. **BB:ShouldAdopt refuses recharging even for a charge spell** — a real
   charge spell (`maxCharges=2`) placed in `recharging` mode; asserts
   `ShouldAdopt` is false, where the un-excluded fallthrough (`IsChargeSpell`)
   would say true.
8. **recharging is registered in the mode picker** — `Data.MODES` contains it
   and `Data.ModeText("recharging")` returns its label, not a generic
   fallback.

### Confirming the tests actually catch the bug

Per the brief, I reverted every production edit (Data.lua's `Data.MODES`
block, all three new Core.lua functions, the `icon.equipSlot` capture, both
new `UpdateState` branches, and BlizzBuffs.lua's new guard line) while leaving
the new test section in place, and re-ran the harness. All eight new cases
failed, each with a distinct, non-coincidental assertion:

```
STEP FAIL  an item cell is not gated on the spellbook name lookup
           Tests/loadtest.lua:3034: equipSlot was not captured onto the icon
STEP FAIL  an item cell with an empty equipment slot is unavailable
           Tests/loadtest.lua:3046: an empty equipment slot was treated as available
STEP FAIL  an unreadable item cooldown fails visible and does not throw
           Tests/loadtest.lua:3062: an unreadable item cooldown hid the icon instead of failing visible
STEP FAIL  an item cell gets a sweep in always mode
           Tests/loadtest.lua:3072: an item cell in always mode was not swept
STEP FAIL  recharging is the inverse of cooldown, for the same item readiness
           Tests/loadtest.lua:3089: recharging did not invert cooldown mode while the item was ready
STEP FAIL  recharging is the inverse of cooldown for a spell too
           Tests/loadtest.lua:3124: recharging did not show while a spell was on cooldown
STEP FAIL  BB:ShouldAdopt refuses recharging even for a charge spell
           Tests/loadtest.lua:3148: recharging mode was adopted by Blizzard's frame
STEP FAIL  recharging is registered in the mode picker
           Tests/loadtest.lua:3157: recharging is not in Data.MODES, so the picker cannot offer it
```

Then re-applied every reverted edit exactly (verified with `git diff` showing
the identical hunks restored) and re-ran to get the `0 failure(s)` result
above.

**One thing worth recording because it nearly produced a false pass.** On the
first pass at this exercise, two of the eight cases (the empty-slot case and
the unreadable-cooldown case) passed even against the reverted code — not
because the fix was already present, but because an *earlier* case in the same
run had failed and `error()` had unwound past its own trailing cleanup line,
leaking dirty stub state (`_G.__unknownNames`, `_G.__cooldownState`) into the
next case, which then coincidentally satisfied its assertion for an unrelated
reason. I fixed this by adding a `ResetItemStubs()` helper called at the start
of every case (not just cleanup at the end), so each case's result is
independent of what ran before it and of whether an earlier case threw. After
that fix, all eight genuinely failed against the reverted code as shown above.
This is exactly the class of trap DECISIONS.md §19 already warns about for the
production loop ("an uncaught throw... leaves everything after it in a stale
state") — it turns out to apply to test authoring in this same harness too,
and I did not see it called out anywhere in the docs, so I've drafted an entry
below.

## Sources used

- `gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua?ref=live"` —
  `CooldownViewerItemDataMixin:GetItemLocation` (around line 283), confirming
  `ItemLocation:CreateFromEquipmentSlot(equipSlot)` then `itemLocation:IsValid()`
  is Blizzard's own availability test.
- `gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua?ref=live"` —
  `CooldownViewerCooldownItemMixin:CheckCacheCooldownValuesFromEquippedItem`
  (around line 1015), confirming `GetInventoryItemCooldown("player", equipSlot)`
  returns `startTime, duration, enable` and that Blizzard derives
  `cooldownIsActive` from `endTime > timeNow`. I used the simpler, GetTime-free
  `duration == 0` idiom instead (see "turned out to be wrong / worth
  reconsidering" below) rather than mirroring that comparison exactly.
- `docs/DECISIONS.md` §19 (per-icon throw discipline), §20 ("12.1... Items are
  not protected the way spells are" — confirms `C_Item.GetItemCooldown` and by
  extension `GetInventoryItemCooldown` carry no `SecretWhen*` flag), and the
  "Why the trinket only drew in `always` mode" addendum at the end of the file,
  which independently confirmed the exact code-line diagnosis the task file
  gives (`Core.lua:773` / `:785` / `:840` — those line numbers have since moved
  because of this change, but the pre-change diagnosis matched what I found).

## Proposed docs changes

**`docs/DECISIONS.md`**, new subsection under §19 or as its own numbered
section (task 14 is squarely in the shape of "combat/secrecy handling that
needed its own path"):

> ### Item-backed cells need none of the spell path's secret-value handling,
> and must skip its name gate entirely
>
> `C_Item.GetItemCooldown`/`GetInventoryItemCooldown` carry no `SecretWhen*`
> flag (§20), so an item cell's readiness, availability and sweep are all
> ordinary reads — no `issecretvalue` screen on the game's own account, though
> `Core.lua` still routes every value through `Readable()` since that helper's
> own secrecy posture was never separately measured and the cost of asking is
> zero.
>
> The one thing an item cell cannot use is `IsSpellAvailable`: it resolves by
> NAME, which is spellbook-scoped (§5), and an item's on-use spell (a
> trinket's, e.g. Radiant Blessing) is never in the spellbook. That gate sits
> above the mode branches in `UpdateState`, so `cooldown` mode reached it and
> always failed, while `always` mode never did — `BB:ShouldAdopt` returns true
> for `always` on the mode alone, adopting the cell and skipping the gate
> entirely, which is why the same trinket drew in one mode and not the other
> with no other difference. An icon is identified as item-backed by
> `icon.equipSlot`, captured in `Rebuild` from
> `Data.GetCooldownInfoForSpell(...).equipSlot`, and item cells are routed
> around the name gate rather than through it.

**`Tests/README.md`** (or wherever the harness's own hazards are documented —
I did not find an existing section for this, only §19's note about
`SetCooldown` being too permissive), a short addition:

> **A case that fails leaks state into the next one.** `error()` inside a step
> function unwinds past that step's own trailing cleanup lines, so any shared
> `_G.__*` stub table a step mutates and only resets at the bottom is left
> dirty for whatever runs next — which can make an unrelated, later case pass
> for the wrong reason. Reset shared stub state at the START of a case, not
> only the end, whenever a section reuses `_G.__*` tables across steps.

## Could not do

Nothing was blocked. One thing worth flagging as a judgment call rather than a
block: the task says to find "whatever validates a stored mode" and register
`recharging` there too, warning that a mode present in the picker but not the
validator "gets silently rewritten on load." I searched (`Data.SetPlacement`,
`Data.GetPlacements`, `Data.GetProfile`, `Data.IsSpellPlaced`, everywhere
`placement.mode` or `icon.mode` is read) and found **no such validator exists
in this codebase** — a stored mode string is never checked against an enum and
rewritten; `Data.SetPlacement`/`Data.GetPlacements` only default a *nil* mode
to `"cooldown"`, they never reject an unrecognized non-nil one. `Data.MODES`
feeding the picker dropdown (`ui/pages/CooldownViewer.lua:687`) is the only
registration point I could find. I'm reporting this as "found none" rather
than silently assuming the warning was satisfied by inspection alone, per the
brief's instruction to stop and report a place where the task's premise didn't
match the repo — though in this case the task said "whatever validates,
**if any**" in spirit and finding none is itself the answer, not a blocker.

## Noticed but did not touch

- `IsItemReady` and `ApplyItemSweep` both call `GetInventoryItemCooldown`
  separately per `UpdateState` pass (once for readiness, again for the sweep
  when in `always`/`recharging`). Blizzard's own read is once per item per
  pass too (their mixin caches it), so this is at most a doubled read of a
  cheap, non-secret API — not worth the complexity of threading the value
  through, but a future pass tightening the per-icon loop's call count could
  fold these into one read.
- The task's background section cites `Core.lua:773`/`:785`/`:840` for the
  three relevant lines. Those numbers were already stale relative to the
  working tree when I started (the file had grown from earlier sessions' work
  on this same branch), and are stale again now that this change added ~140
  lines above them. Not a defect — just noting line numbers in a task file are
  a snapshot, consistent with `HANDOFF.md`'s standing warning that
  SavedVariables line numbers go stale the moment the game runs; the same is
  true of source line numbers the moment another change lands.
- `docs/DECISIONS.md` and `docs/KNOWN-ISSUES.md` both changed on disk partway
  through this session (confirmed via `git log`: two new commits,
  `e7ecd66` and `a8a7451`, landed on this branch while I was working, moving
  HEAD from `6ce2b8b` to `a8a7451`). I did not read the diff of what those
  commits changed beyond what I'd already read in `DECISIONS.md` before they
  arrived, since it wasn't necessary for this task and re-reading a file that
  grows mid-task under me isn't something I want to chase. Worth knowing this
  branch had concurrent activity from another process during this task.

## Not verified

- Everything, in the sense that none of this has run in the actual game. In
  particular:
  - Whether Radiant Blessing (or any real trinket) now actually draws in
    `cooldown` mode, sweeps correctly in `always`/`recharging` mode, and hides
    correctly when unequipped.
  - Whether `GetInventoryItemCooldown`'s real return shape matches what the
    stub models — I verified the call signature and the field order against
    Blizzard's source (see Sources above), but the actual values a live client
    hands back for a real trinket, including whether `duration == 0` really is
    always exactly 0 rather than some small residual, were not measured this
    session.
  - Whether `ItemLocation:CreateFromEquipmentSlot`/`:IsValid` behave as
    documented for every equip slot on this client build, or whether either
    global is ever absent (the guard exists for that case but was never
    exercised against a real client).
  - Whether the `recharging` mode reads sensibly in the actual config UI
    dropdown (label text, ordering next to `cooldown`) — confirmed only that
    `Data.MODES` feeds it and the harness's page-build pass
    (`ok page cooldownviewer`) still succeeds.
  - Whether `BB:ShouldAdopt` returning false for `recharging` produces the
    intended visual for a real charge spell placed in that mode — confirmed
    only in the stub harness.
