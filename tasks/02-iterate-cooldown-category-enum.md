# 02 — Iterate `Enum.CooldownViewerCategory` instead of hardcoding four names

**Read `tasks/00-AGENT-BRIEF.md` first. It is not optional.**

**Type:** code change plus tests.

**Runs in parallel with:** task 01. Stay out of its files and it stays out of yours.

---

## Why this task exists

`modules/CooldownViewer/Data.lua` names the Cooldown Manager's categories as
literal strings in three places. 12.1 adds five new categories. As the code
stands, every one of them will be **silently ignored** — no error, no log line,
just spells missing from the picker and from `/thugcv probe` with nothing to say
why.

Silent is the problem. This project has already lost a debugging round to a
feature that failed by producing nothing (`docs/DECISIONS.md` §8, where reading
only `TrackedBuff` lost the Roll the Bones outcome buffs outright, and no symptom
pointed at the cause).

**On today's 12.0.7 client this change does nothing observable**, because the
enum currently holds exactly the four names that are hardcoded. That is the
point: it ships now, safely, and stops the patch from breaking anything.

## Design decisions — already made, do not revisit

You are implementing these, not evaluating them. They are here so you understand
the shape, not so you can improve it. If you think one is wrong, **implement it
anyway and say so in your report.**

1. **The cache, the probe dump, and the "Everything" picker source iterate the
   enum.** All three mean "whatever the Cooldown Manager has". A new category
   belongs in all three automatically.

2. **`CATEGORIES_BY_SOURCE` stays an explicit, hand-written map, and the
   `Data.SOURCES` dropdown does not grow itself.** `docs/UPCOMING-PATCH.md`
   suggests otherwise; it is overruled. Which categories a player-facing menu
   entry pools together is a product decision, not a data one — `TrackedBuff`
   and `TrackedBar` are two categories deliberately presented as one source
   called "Tracked buffs" (`docs/DECISIONS.md` §8), and a menu entry per enum
   value would undo that. New categories stay reachable through "Everything"
   until someone decides where they belong.

3. **An unrecognised category gets logged, once.** That is how the next patch
   announces itself instead of going quiet. Use
   `ThugUI.Diagnostics:LogOnce(key, category, message, ...)` — it exists for
   exactly this, and the once-only key is what stops a per-frame flood
   (`docs/DECISIONS.md` §11).

4. **Iteration order is by enum value, ascending.** `pairs()` over a table is
   unordered, and `/thugcv probe` dumps get diffed against each other across
   patches — that is a line on the patch-day checklist. Nondeterministic output
   would quietly destroy that. `Preferred()` is already order-independent, so
   the cache does not care, but the dump does.

5. **Do not change the per-spec cache key.** `docs/UPCOMING-PATCH.md` warns that
   `SpecAgnostic*` entries "break the assumption behind the per-spec cache key".
   That warning is overstated and you should not act on it: the cache is keyed by
   spec and rebuilt on spec change, so a spec-agnostic entry sitting in it is
   merely rebuilt more often than strictly necessary. Harmless. Leave
   `Data.GetCooldownInfoForSpell` alone.

## Files you may modify

- `modules/CooldownViewer/Data.lua`
- `Tests/loadtest.lua`
- `tasks/reports/02-report.md`

Nothing else. In particular: **do not touch `docs/UPCOMING-PATCH.md`** — task 01
is holding that file — and do not touch `ui/pages/CooldownViewer.lua`, since
decision 2 means the dropdown does not change.

---

## What to change

Line numbers are from the current `main` at commit `3de287e`. Verify with
`git diff` that you have a clean tree before you start.

### Step 1 — add the helper

In `modules/CooldownViewer/Data.lua`, near `CATEGORIES_BY_SOURCE` (around line
394), add a local function that returns every Cooldown Manager category as a
list of `{ name = <string>, value = <number> }`, **sorted ascending by value**.

Requirements, all of which are failure modes we care about:

- Return an empty table when `Enum` or `Enum.CooldownViewerCategory` is missing.
  The existing code guards for this at every call site and so must you — a
  client where the enum was renamed must degrade to an empty picker, not an
  error.
- **Skip any key whose value is not a number.** Some WoW enums ship a companion
  table of metadata. Whether this one does is being established by task 01,
  which is running right now, so do not depend on the answer: guard with
  `type(value) == "number"` and the question stops mattering.
- Keep the **name** as well as the value. Callers log it and the probe dump
  records it as a string.

Comment it with **why** it exists — that hardcoded names silently drop new
categories — not with what it does. Match the file's voice; it is unusually
well commented and yours should not stand out.

### Step 2 — `BuildCooldownInfoCache` (line ~484)

Replace:

```lua
for _, categoryName in ipairs({ "Essential", "Utility", "TrackedBuff", "TrackedBar" }) do
    local category = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
    if category ~= nil then
```

with iteration over the helper. Everything inside the loop body stays exactly as
it is — `Preferred`, the multi-ID indexing, the `pcall`s. **Do not refactor the
body.** Note there is an existing shadowed local named `ids` inside that loop;
leave it alone, it is out of scope and changing it makes the diff harder to review.

### Step 3 — `DumpCooldownViewer` (line ~549)

Same replacement. The dump record must keep `category = categoryName` as the
**name string**, not the number — existing probe dumps in the player's
SavedVariables carry names, and `Tests/replay_probe.lua` reads them back.

### Step 4 — the `"all"` branch of `Data.BuildSpellList` (line ~638)

Currently:

```lua
elseif source == "all" then
    for sourceName, categoryNames in pairs(CATEGORIES_BY_SOURCE) do
        for _, categoryName in ipairs(categoryNames) do
            collect(CooldownViewerSpellIDs(categoryName, sourceName == "buffs"))
        end
    end
    collect(SpellbookSpellIDs())
```

"Everything" must mean everything, including a category no source names yet.
Iterate the helper instead, and pass `expandLinked = true` **only** for a
category that appears in `CATEGORIES_BY_SOURCE.buffs`.

Unknown categories get `expandLinked = false`. The reason, for your comment: on
a cooldown entry a linked spell is the same button under another ID and listing
it just doubles the list; only on a buff entry is it a genuinely different thing
to track. The existing comment above `local expand` says this — do not duplicate
it, point at it.

This is where **decision 3** lands: when you meet a category that is in the enum
but named by no entry in `CATEGORIES_BY_SOURCE`, `LogOnce` it. Key it on the
category name so each new one is reported exactly once.

### Step 5 — leave a signpost on `CATEGORIES_BY_SOURCE`

Add a short comment recording decision 2: the map is deliberately hand-written
because it is a product decision about menu entries, while the cache, the dump
and "Everything" iterate the enum. Without that line, the next reader
reasonably "finishes the job" and undoes it.

---

## Tests — required, not optional

`Tests/loadtest.lua` stubs the enum at line ~220 and the category sets at line
~300:

```lua
CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3 },
...
_G.__categorySets = {
    Essential   = { 1, 2, 4 },
    Utility     = {},
    TrackedBuff = { 3 },
    TrackedBar  = { 5 },
}
```

**Do not renumber or repurpose the existing stub entries 1–5.** Several tests
depend on them — entries 4 and 5 model Roll the Bones appearing twice with
different linked-spell lists, which is the regression case for `docs/DECISIONS.md`
§8. Add new fixtures alongside them with fresh IDs.

Add cases proving:

1. **A category the code has never heard of reaches the cache and the dump.**
   Add a fake future category to the stub enum with a value of `4` or higher,
   give it a cooldown entry with a distinctive spell ID, and assert that entry
   is indexed by `Data.GetCooldownInfoForSpell` and appears in
   `Data.DumpCooldownViewer`. This case must **fail on the current code** —
   confirm that it does, and say how you confirmed it.

2. **That same unknown category reaches the "Everything" picker source** and is
   *absent* from `essential`, `utility` and `buffs`. Both halves matter:
   decision 2 says it must not leak into a curated source.

3. **The dump is ordered by category value**, deterministically, across repeated
   calls.

4. **A non-numeric key in the enum table is skipped without erroring.** Add one
   to the stub (a nested table under a `Meta`-style key is the realistic shape)
   and assert nothing throws and nothing extra is collected.

5. **A missing `Enum.CooldownViewerCategory` degrades to empty, not an error.**
   There may already be coverage near the existing `Data.BuildSpellList` tests
   around line 540 — check first and extend rather than duplicate.

Restore any stub you mutate. The existing tests follow a set-up / assert /
restore shape; match it, and keep `Data.InvalidateCooldownInfoCache()` in mind —
the cooldown cache is memoised per spec and a test that changes the category sets
without invalidating it will assert against a stale cache and pass for the wrong
reason.

## Verification gate

```sh
luac -p modules/CooldownViewer/Data.lua Tests/loadtest.lua
lua Tests/loadtest.lua .
```

Baseline before your change is **0 failures**. It must still be 0 after, with
your new cases present and passing. Paste the tail into your report.

Then, and this is the part that is easy to skip:

```sh
lua Tests/replay_probe.lua \
  "C:/Program Files (x86)/World of Warcraft/_retail_/WTF/Account/SQUAZZIL/SavedVariables/ThugUI.lua" . 1214909
```

This replays the player's **real** `/thugcv probe` dump through the live
`Data.lua`. It is the closest thing to a regression test against real client data
that exists without launching the game, and Step 3 touches the code it exercises.
Report its output. If the SavedVariables file has no probe dump in it, say so —
that is a fine outcome, not a failure, and it is not something for you to fix.
**Do not write to anything under `WTF/`** (brief §7).

## Report

`tasks/reports/02-report.md`, per brief §10.

Your **Proposed docs changes** should include a draft addendum for
`docs/DECISIONS.md` §8 recording decision 2 and its reasoning — why the category
list is derived from the enum while the source menu stays hand-written. Keep it
to a short paragraph in that file's voice. You are not editing the file (brief §9).

Flag in **Not verified** that nothing here has been seen in a running game, and
that no client in existence currently has the new categories, so the new-category
path is proven only against a stub.
