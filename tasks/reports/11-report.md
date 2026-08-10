# 11 — A spell placed as a cooldown is not "already placed" as a buff — report

**Status:** complete

## What I changed

`Data.IsSpellPlaced` gained an optional third argument, `mode`, which restricts
which placements count as "placed": `nil` (unchanged — any mode), `"aura"`
(only an aura-mode placement), or `"other"` (any non-aura placement). The
picker row's grey-out check in `Page:RefreshPicker`
(`ui/pages/CooldownViewer.lua`) now decides which of those three to ask for
based on `self.pickerSource`, via a small local `GreyMode(source)` helper: the
`buffs` source asks for `"aura"`, `all` asks for `nil` (any — unchanged, since
a row there makes no claim about which kind it is), and every other source
asks for `"other"`. `Data` itself has no notion of what a picker source is —
that decision lives entirely in the page, as the task required.

## Files touched

| File | What |
|---|---|
| `modules/CooldownViewer/Data.lua` | `Data.IsSpellPlaced` gained the optional `mode` argument (`Data.lua:346`, now ~20 lines with the doc comment). Every existing call with 2 args is untouched by the new branch — `mode == nil` returns exactly the old any-mode result. |
| `ui/pages/CooldownViewer.lua` | Added local `GreyMode(source)` above `Page:RefreshPicker`; `RefreshPicker` now computes `greyMode` once per call and passes it as `Data.IsSpellPlaced`'s third argument. |
| `Tests/loadtest.lua` | Added 4 new cases to the engine `steps` table, right after "grid page refresh after edits" (so `ThugUI.CooldownViewer.Page` is guaranteed built). |

## Verification

```
$ luac -p modules/CooldownViewer/Data.lua ui/pages/CooldownViewer.lua Tests/loadtest.lua
(no output — syntax OK)
```

```
$ lua Tests/loadtest.lua .
...
-- secret probe --
ok         records a sample with readable values
ok         a secret power value is described, not read
ok         a secret aura struct does not throw
ok         a missing API is reported, not fatal
ok         a thin sample never buries a rich one

0 failure(s)
```

All six sections (pages, engine, resource ring, blizzard buff items, combo
pips, secret probe) ran and passed. 160 `ok` lines total (was 156 at the
task's stated baseline — the 4 added cases account for the difference
exactly).

## Tests added

Four cases, inserted into the engine `steps` table in `Tests/loadtest.lua`
right after `"grid page refresh after edits"`:

1. **`"IsSpellPlaced with no mode argument behaves exactly as before"`** — the
   compatibility guard from the task. Places a spell in `aura` mode and checks
   `Data.IsSpellPlaced(profile, id)` (2 args) finds it, that passing `nil`
   explicitly gives the identical result, and that an unplaced ID reports
   false. This one already passed against the old code (there was no
   regression here — it's the guard, not the bug), so it doesn't itself prove
   the fix; the other three do.
2. **`"a cooldown-mode placement greys under essential, not under buffs"`**
3. **`"an aura-mode placement greys under buffs, not under essential"`**
4. **`"the all source greys on either mode"`**

Cases 2–4 use spell ID `5000` from the existing stub data, which already
models exactly the Roll-the-Bones shape the task describes: `_G.__cooldownEntries`
entry 4 (`cooldownID = 4`) lists it under `Essential` with no linked spells,
entry 5 (`cooldownID = 5`) lists it under `TrackedBar` (folded into the
`"buffs"` source) with linked outcome buffs — the same spell ID, two
categories, exactly the ambiguity the bug was about. No new stub data was
needed.

**Confirmed failing on the old code first.** I stashed only the two source
files (`git stash push -- modules/CooldownViewer/Data.lua
ui/pages/CooldownViewer.lua`), leaving the new tests in place, and ran the
suite:

```
STEP FAIL  a cooldown-mode placement greys under essential, not under buffs
           Tests/loadtest.lua:878: a cooldown-mode placement wrongly greyed its row under buffs
STEP FAIL  an aura-mode placement greys under buffs, not under essential
           Tests/loadtest.lua:909: an aura-mode placement wrongly greyed its row under essential
ok         the all source greys on either mode
2 failure(s)
```

Exactly the two mode-crossing cases failed, with the exact wrong-grey message
the bug produces; `"all"` and the compatibility guard already passed against
the old code, as expected (their behaviour did not change). I then popped the
stash to restore the fix and re-ran — 0 failures, shown above.

## Existing tests I believe need to change

None. No existing case was touched, and none needed to be — the only existing
caller of `Data.IsSpellPlaced` (`ui/pages/CooldownViewer.lua:472`, inside
`RefreshPicker`) is the one the task asked me to change, and no test in
`Tests/loadtest.lua` called `Data.IsSpellPlaced` directly before this task.

## Sources used

None — this task was pure internal logic, no WoW API behaviour was in
question, so nothing needed checking against Blizzard's source.

## Proposed docs changes

`docs/DECISIONS.md` — a short addition near wherever the Roll-the-Bones /
picker-source reasoning already lives (it's referenced in `Data.lua`'s
`CATEGORIES_BY_SOURCE` comment, so probably close to that discussion):

> **Picker grey-out is by spell ID *and* mode family, not spell ID alone.**
> The same spell ID can be placed twice with different meanings — Roll the
> Bones as an Essential cooldown *and* as a tracked buff — and greying every
> row that shares an ID made the picker say "already placed" about a row that
> was a genuinely different thing to place. `Data.IsSpellPlaced(profile,
> spellID, mode)` takes an optional third argument (`nil` = any mode, `"aura"`,
> or `"other"`) so a caller can ask "is this placed as the kind of thing THIS
> row would draw". The decision of which mode family a picker source implies
> lives in `ui/pages/CooldownViewer.lua`'s `GreyMode(source)`, not in `Data`
> — `Data` has no notion of what a "picker source" is, only of placements and
> modes. The `all` source keeps the old any-mode behaviour deliberately: a row
> there makes no claim about which kind of thing it is, so "placed somewhere"
> is the honest answer.

## Could not do

Nothing — the task was unambiguous and the repo matched what it described
(one caller, at the exact line cited; `Data.MODES` had exactly the four modes
named).

## Noticed but did not touch

`Data.IsSpellPlaced` iterates `pairs(profile.placements)` on every call, and
`RefreshPicker` now calls it once per picker row on every refresh — same
big-O as before (it already did this per-row), just doing marginally more
comparison work per iteration (an extra mode check). Not worth flagging as a
performance concern; grids are capped at 100 cells and picker lists are
similarly small. Just noting it since I looked at it.

The `GreyMode` doc comment repeats some of the reasoning already in the task
file's §2 almost verbatim, since that reasoning is exactly why the function
exists — didn't try to be original there, just accurate.

## Not verified

Everything about how this actually reads in the picker UI: whether the grey
colour is visually distinguishable at a glance, whether a player finds the new
behaviour intuitive, and whether Roll the Bones itself (real spell ID
`1214909`, not the stub's `5000`) behaves the same way in the player's actual
Outlaw profile. The stub models the same *shape* Roll the Bones has (one spell
ID split across two Cooldown Manager categories with different linked-spell
richness), but nothing here ran against the real game's `C_CooldownViewer`
data. Correct in code; not run in game.
