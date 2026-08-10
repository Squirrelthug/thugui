# 10 — Stop expanding linked spells into the picker — report

**Status:** complete

## What I changed

`Data.BuildSpellList` no longer expands a Cooldown Manager entry's
`linkedSpellIDs` into extra picker rows. `CooldownViewerSpellIDs` lost its
`expandLinked` parameter and the expansion loop entirely; the two call sites
in `BuildSpellList` (the `all` source and the curated per-source loop) now
call it with just `categoryName`, and the now-unused `expand` local was
removed. The old comment explaining the (untestable) intent was replaced with
one explaining why it was removed: the intent was real and was tested in
game, and it fails structurally because `BlizzBuffs:Apply` maps one Blizzard
item frame per `cooldownID`, and every linked ID shares its base entry's
`cooldownID`. Nothing else changed — `Data.GetCooldownInfoForSpell`,
`BuildCooldownInfoCache`, `Data.PickerSpellIDFor`, and `ResolveAura` in
`Core.lua` are untouched and still read `linkedSpellIDs` exactly as before.

I checked every caller of `CooldownViewerSpellIDs` and `Data.PickerSpellIDFor`
first (both are only called from within `Data.lua`, at the two sites listed
above) so removing the parameter could not silently break something outside
this file.

## Files touched

| File | What |
|---|---|
| `modules/CooldownViewer/Data.lua` | Removed `expandLinked`/`expand` from `CooldownViewerSpellIDs` and its two call sites in `BuildSpellList`; replaced the comment explaining the (impossible) intent with one explaining why it was removed |
| `Tests/loadtest.lua` | Added three new cases covering the new picker behaviour; left the two existing cases that assert the old behaviour untouched (see below) |

## Verification

```
$ luac -p modules/CooldownViewer/Data.lua
(no output — syntax OK)

$ luac -p Tests/loadtest.lua
(no output — syntax OK)
```

```
$ lua Tests/loadtest.lua .
...
ok         spell catalogue
STEP FAIL  buff outcomes are offered individually, not just the set
           Tests/loadtest.lua:598: linked buff 5101 was not offered on its own
ok         an entry with linked spells yields one picker row, not one per linked id
ok         the all source likewise does not gain linked ids
ok         essential, utility and spellbook stay unaffected by the picker change
ok         unknown category reaches cache and dump
...
ok         aura mode finds a linked buff and shows its icon
...
ok         buff categories are withheld while the workaround is off
STEP FAIL  buff categories are offered when the setting is on or unset
           Tests/loadtest.lua:1529: a linked buff was missing from 'all' with the setting on
ok         the other picker sources are untouched by the buff setting
...
ok         the Always/In Combat visibility instruction appears in exactly one step

2 failure(s)
```

Both `STEP FAIL` lines are the two pre-existing tests named below under
**Existing tests I believe need to change** — they assert the exact old
expansion behaviour this task removed. This is not a baseline regression I
introduced by accident; it is the documented, expected consequence described
in task section 3 ("the existing picker tests may well assert the old
expanded counts ... that is expected here, not a failure"). I did not touch
either test.

**Important side effect I want flagged explicitly:** `loadtest.lua`'s
top-level sections after "engine" (`resource ring`, `blizzard buff items`,
`combo pips`, `secret probe`) are each gated by `if failures == 0 and ...`
before running. Because the two pre-existing tests fail *inside* the
"engine" section, `failures` is non-zero by the time those later sections are
reached, so **all four of them are skipped entirely** for the rest of this
run — not just their two individual assertions. I confirmed this by diffing
the `-- section --` headers actually printed against a clean run of the old
code (baseline printed `pages / engine / resource ring / blizzard buff items
/ combo pips / secret probe`; this run printed only `pages / engine`). Nothing
in those skipped sections is affected by this change — I read them and they
do not touch the picker — but the coordinator should know the gate output is
not exercising them right now, purely as a side effect of the two intentional
failures tripping an existing `failures == 0` guard earlier in the file. That
guard predates this task and I did not add or move it.

## Tests added

Three new cases, inserted directly after the existing (now-failing)
`"buff outcomes are offered individually, not just the set"` case in
`Tests/loadtest.lua`:

1. **`"an entry with linked spells yields one picker row, not one per linked id"`**
   — builds the `buffs` source, asserts the base entry (spellID `5000`,
   which carries 4 linked outcomes in the test stub) appears exactly once,
   and that none of its linked IDs appear as their own row.
   Confirmed it fails on the pre-change code:
   `Tests/loadtest.lua:639: linked buff 5101 was still offered as its own row`
   (line number is from the temporary old-`Data.lua` run; the assertion text
   is the same either way). Passes after the fix.

2. **`"the all source likewise does not gain linked ids"`** — same shape,
   against the `all` source, since it has its own call site in
   `BuildSpellList`. Confirmed it fails on the pre-change code:
   `Tests/loadtest.lua:653: 'all' offered linked buff 5101 as its own row`.
   Passes after the fix.

3. **`"essential, utility and spellbook stay unaffected by the picker change"`**
   — asserts those three sources never surface any of entry 5000's linked
   IDs. Honestly: this passes both before and after the change, because
   expansion only ever ran for `buffs`/`all` in the old code too — the test
   stub has no linked-spell-bearing entry under `essential`/`utility`/
   `spellbook` to begin with, so this cannot presently prove a regression in
   either direction. It exists as a guard against a *future* change
   reintroducing expansion on those sources, per task section 3's bullet
   asking for it explicitly. I want this limitation on the record rather than
   silently claiming stronger coverage than it has.

I confirmed all three fail-before/pass-after (or, for #3, pass either way as
explained) by temporarily restoring the pre-change `Data.lua` via
`git stash push -- modules/CooldownViewer/Data.lua`, running the suite, then
`git stash pop` to restore the fix. `git status` after the pop confirmed both
files were back to their edited state.

I did **not** duplicate the regression guard requested in task section 3
("an `aura`-mode icon placed on the base spell still resolves a linked buff
through `ResolveAura`, and still reports its linked count") — it is already
covered by two existing, unaffected tests:
`"aura mode finds a linked buff and shows its icon"` (places spellID `9001`
in `aura` mode, confirms `icon.linkedSpellIDs` is populated and that
`CV:UpdateState` finds the live linked buff) and
`"a snapshot records linked-spell counts"` (places spellID `5000`, confirms
the state snapshot records `linked=4`). Both read through
`Data.GetCooldownInfoForSpell`/`BuildCooldownInfoCache`, which this task did
not touch, and both still pass.

## Existing tests I believe need to change

Two existing cases directly assert the old expansion behaviour and now fail
as a direct, expected result of this task. I left both alone per task
section 3's instruction.

**1. `"buff outcomes are offered individually, not just the set"`**
(`Tests/loadtest.lua:588`)

Before (asserts the removed behaviour):
```lua
{ "buff outcomes are offered individually, not just the set", function()
    local list = Data.BuildSpellList("buffs", nil)
    local byID = {}
    for _, entry in ipairs(list) do byID[entry.spellID] = true end
    assert(byID[5000], "the set entry itself vanished from the picker")
    local info = Data.GetCooldownInfoForSpell(5000)
    assert(info and #info.linkedSpellIDs > 0, "setup: no linked buffs to expand")
    for _, linkedID in ipairs(info.linkedSpellIDs) do
        assert(byID[linkedID],
            ("linked buff %d was not offered on its own"):format(linkedID))
    end
    -- ... essential-source non-expansion check, still valid, unchanged ...
end },
```

Proposed after (drop the now-false first half; keep the still-true
essential-source check, which is otherwise orphaned):
```lua
{ "buff outcomes are no longer offered individually, only the set", function()
    local list = Data.BuildSpellList("buffs", nil)
    local byID = {}
    for _, entry in ipairs(list) do byID[entry.spellID] = true end
    assert(byID[5000], "the set entry itself vanished from the picker")
    local info = Data.GetCooldownInfoForSpell(5000)
    assert(info and #info.linkedSpellIDs > 0, "setup: no linked buffs to check")
    for _, linkedID in ipairs(info.linkedSpellIDs) do
        assert(not byID[linkedID],
            ("linked buff %d was still offered on its own"):format(linkedID))
    end

    local essentials = Data.BuildSpellList("essential", nil)
    local essentialIDs = {}
    for _, entry in ipairs(essentials) do essentialIDs[entry.spellID] = true end
    local cdInfo = Data.GetCooldownInfoForSpell(9101)
    if cdInfo and cdInfo.linkedSpellIDs and #cdInfo.linkedSpellIDs > 0 then
        assert(not essentialIDs[cdInfo.linkedSpellIDs[1]],
            "a cooldown entry's linked spell was offered separately")
    end
end },
```
This would make it redundant with my new
`"an entry with linked spells yields one picker row, not one per linked id"`
— the coordinator may prefer to just delete the old one once this lands,
rather than keep both.

**2. `"buff categories are offered when the setting is on or unset"`**
(`Tests/loadtest.lua:1512` in the file as it now stands)

Before (asserts a linked ID reaches `all`):
```lua
local inAll = {}
for _, entry in ipairs(Data.BuildSpellList("all", nil)) do
    inAll[entry.spellID] = true
end
assert(inAll[5101],
    ("a linked buff was missing from 'all' with the setting %s"):format(state))
```

Proposed after (assert the base entry reaches `all` instead — `5101` was
only ever reachable through the expansion this task removed, so asserting
its *presence* is no longer a meaningful check; the setting-on/off behaviour
this test is actually about is better proven with the base ID):
```lua
local inAll = {}
for _, entry in ipairs(Data.BuildSpellList("all", nil)) do
    inAll[entry.spellID] = true
end
assert(inAll[5000],
    ("the base entry was missing from 'all' with the setting %s"):format(state))
```
Note the companion test right above it,
`"buff categories are withheld while the workaround is off"`, already
asserts `not inAll[5101]` (buff withheld while the setting is off) — that
assertion is unaffected by this task (`5101` was already reachable only
through the now-removed expansion, so it staying absent is still correct)
and needs no change.

## Sources used

None looked up externally — this task's evidence was internal: reading
`ResolveAura` and its caller in `modules/CooldownViewer/Core.lua:339-348`,
`Data.GetCooldownInfoForSpell`/`BuildCooldownInfoCache` in
`modules/CooldownViewer/Data.lua:495-577`, and grepping the whole repo for
every caller of `CooldownViewerSpellIDs` and `Data.PickerSpellIDFor` to
confirm neither is used outside `Data.lua`.

## Proposed docs changes

For `docs/DECISIONS.md`, a new entry (placement: after the existing Roll the
Bones / `linkedSpellIDs` picker-design entries, since it directly overturns
one of them — the task file points at the entry documenting
`CooldownViewerSpellIDs(categoryName, expandLinked)`):

> **Per-outcome buff tracking is impossible: one Blizzard item frame per
> `cooldownID`.**
>
> The picker used to expand a tracked entry's `linkedSpellIDs` into separate
> rows, so a player could place "Roll the Bones: Jackpot" instead of just
> "Roll the Bones" — the intent being to track one specific outcome. That
> shipped, and the player tested it: placing Roll the Bones plus all four
> outcomes in `aura` mode rendered exactly one icon, not five.
>
> The cause is structural, not a bug to fix elsewhere. `BlizzBuffs:Apply`
> (`modules/CooldownViewer/BlizzBuffs.lua`) adopts Blizzard's own buff-item
> frames by matching each `aura`-mode placement to the item frame carrying
> the same `cooldownID` — one frame per `cooldownID`. Every linked outcome
> resolves to the *same* `cooldownID` as its base entry (Roll the Bones and
> all four outcomes are all `cdID 42743` in the player's own
> `ThugUI_BCVDump`), so five picker rows for one tracked entry compete for
> one frame. No logic makes five cells share one frame; whichever placement
> is processed last wins.
>
> **Fixed by not offering the expansion at all** (task 10,
> `modules/CooldownViewer/Data.lua`, `CooldownViewerSpellIDs`). This loses
> nothing at runtime: the base entry already resolves whichever outcome is
> live. `ResolveAura` in `Core.lua` walks `icon.linkedSpellIDs` (populated
> from `Data.GetCooldownInfoForSpell`, unrelated to the picker) and shows
> whichever linked buff is currently up — that is why the player's Roll the
> Bones placement already worked and reported `linked=4` before this change,
> and continues to after it. Only the *picker's offer list* changed; nothing
> that resolves an aura at runtime was touched.
>
> `linkedSpellIDs` itself stays load-bearing in three places that did **not**
> change: `ResolveAura` (`Core.lua`), the `linked=N` field in the state
> snapshot (`docs/HANDOFF.md` §1's evidence-of-execution field), and
> `Data.GetCooldownInfoForSpell`.

## Could not do

Nothing was blocked. The task was unambiguous and the repo matched what it
described at every point I checked (the `expandLinked` parameter, the two
call sites, the `cdID 42743` Roll the Bones example, `PickerSpellIDFor`
having no other caller).

## Noticed but did not touch

- The `if failures == 0 and ...` gating pattern in `Tests/loadtest.lua`
  (`resource ring`, `blizzard buff items`, `combo pips`, `secret probe`
  sections) means one failing case anywhere in an earlier section silently
  skips entire unrelated later sections rather than just that one assertion.
  That is what happened here (see Verification above) — it is pre-existing
  behaviour, not something task 10 introduced, but it means the two expected
  failures currently hide roughly 45 unrelated `ok` cases from actually
  running in this invocation. Worth a look independently of this task.
- `tasks/11-grey-the-picker-row-by-mode-not-just-spell.md` exists as an
  untracked file in the working tree (visible in `git status`). It is not
  part of this task and I did not open or act on it.
- The Roll the Bones outcome names in the task's table (Opportunity,
  Gravedigger, Unseen Blade, Coup de Grace, Cloud Cover and their linked
  buffs) are player-specific spec data from `ThugUI_BCVDump`, not something
  I could re-verify from this environment — I took the task file's numbers
  as given, consistent with the brief's "never invent a spell ID" rule
  meaning I should not second-guess a cited in-game dump either.

## Not verified

Everything here is correct in code / passes the test harness only — none of
it has been seen in the running game:

- That the picker (Cooldown Viewer page, spell-add dropdown) now shows one
  row per tracked-buff entry instead of the old expanded list, visually.
- That Roll the Bones (and every other multi-outcome entry in the player's
  dump: Opportunity, Gravedigger, Unseen Blade, Coup de Grace, Cloud Cover)
  still resolves and draws correctly via `ResolveAura` with the picker
  change in place — the test harness proves the code path is unchanged, not
  that it renders.
- Whether the picker "reads better" now, which the task explicitly says is
  the player's call, not mine.
