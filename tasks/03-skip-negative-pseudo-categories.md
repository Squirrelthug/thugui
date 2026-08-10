# 03 — Skip the negative pseudo-categories Blizzard injects into the enum

**Read `tasks/00-AGENT-BRIEF.md` first. It is not optional.**

**Type:** defect fix in uncommitted work, plus a test.

**Runs alone.** It edits the same files task 02 left uncommitted in the working
tree. Do not start it while any other agent is running.

---

## Why this task exists

Task 02 replaced three hardcoded category lists with iteration over
`Enum.CooldownViewerCategory`. Task 01, running in parallel, found something
that makes that iteration wrong — and neither agent connected the two.

**Blizzard writes two fake entries into that enum at runtime.**
`Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua`:

```lua
--- These values aren't actually part of the enum
--- They exist so that disabled states can be managed using the same category enums
--- There are checks to ensure that they don't match any of the pre-existing enum values
Enum.CooldownViewerCategory.HiddenSpell = -1;
Enum.CooldownViewerCategory.HiddenAura = -2;
```

On the 12.1 PTR they are renamed to `HiddenActive = -1` and `HiddenPassive = -2`.

That file is the **first line of `Blizzard_CooldownViewer.toc`**, and that addon
is the Cooldown Manager itself — not a load-on-demand settings panel. So those
two keys are present on the live 12.0.7 client, in every session, right now.

Blizzard reads them back through `CooldownViewerUtil.IsDisabledCategory`. They
are markers for "the player switched this off", not real category sets.

**Three consequences, all live today:**

1. `CooldownViewerCategories()` returns them, so we call
   `C_CooldownViewer.GetCooldownViewerCategorySet(-1)` and `(-2)` on every cache
   build, every probe dump, and every "Everything" picker build.
2. If either call returns anything, spells the player has **deliberately
   disabled** in the Cooldown Manager leak into our cache and our picker.
3. Worst of the three: the `LogOnce` for an unrecognised category fires for
   `HiddenSpell` and `HiddenAura` **on day one**. That log line exists to make
   the next patch announce itself (task 02, decision 3). A signal that cries
   wolf immediately is worse than no signal, because the real one arrives
   already discredited.

This also means task 02 is **not** the no-op on the current client it was
described as. It changes behaviour today, and this task is what makes it safe.

## The decision — already made

**Skip any category whose value is negative.** Not a name blocklist: the names
changed between 12.0.7 and 12.1 (`HiddenSpell`→`HiddenActive`,
`HiddenAura`→`HiddenPassive`), so matching on names would have broken at the
patch, which is the exact failure mode this whole batch exists to prevent.
Blizzard's own comment promises these never collide with real enum values, and
real values start at 0 and count up.

## Files you may modify

- `modules/CooldownViewer/Data.lua`
- `Tests/loadtest.lua`
- `tasks/reports/03-report.md`

Nothing else. **The working tree already contains task 02's uncommitted changes.
Do not revert, stash, reset, or "clean up" any of it** — you are adding to it.
Run `git diff --stat` first; you should see `Data.lua` and `Tests/loadtest.lua`
already modified. If you do not, stop and report.

## What to change

### Step 1 — the filter

In `CooldownViewerCategories()` in `modules/CooldownViewer/Data.lua`, reject
values below zero as well as non-numbers.

Comment it with **why** — that Blizzard injects negative pseudo-categories for
disabled states from `CooldownViewerSettingsConstants.lua`, that they are not
real category sets, and that the names change between builds so the value is
what we filter on. Quote or cite Blizzard's own comment. Someone will otherwise
delete this filter as paranoia.

### Step 2 — the log line

Confirm the unrecognised-category `LogOnce` in the `"all"` branch of
`Data.BuildSpellList` can no longer fire for the negative entries. It should
follow automatically from Step 1; verify rather than assume, and say in your
report how you verified.

## Tests

Add a case to `Tests/loadtest.lua`, alongside task 02's:

**"Blizzard's negative pseudo-categories are ignored."** Inject the realistic
shape into the stub — `Enum.CooldownViewerCategory.HiddenSpell = -1` and
`HiddenAura = -2`, with `_G.__categorySets` entries carrying a distinctive spell
ID — and assert that spell:

- is **not** indexed by `Data.GetCooldownInfoForSpell`
- does **not** appear in `Data.DumpCooldownViewer`
- does **not** appear in `Data.BuildSpellList("all", nil)`

This case must **fail against the current working-tree code** and pass after
your fix. Confirm that it does and say how.

Restore every stub you mutate, and call `Data.InvalidateCooldownInfoCache()`
where the cooldown cache is involved — it is memoised per spec, and a test that
changes category sets without invalidating it asserts against a stale cache and
passes for the wrong reason.

## Verification gate

```sh
luac -p modules/CooldownViewer/Data.lua Tests/loadtest.lua
lua Tests/loadtest.lua .
```

Every test must pass — task 02's five and yours. Paste the tail into your report.

## Report

`tasks/reports/03-report.md`, per brief §10.

In **Proposed docs changes**, draft a short note for `docs/DECISIONS.md` §8
recording that `Enum.CooldownViewerCategory` is not a clean enum at runtime —
Blizzard injects negative disabled-state markers into it — and that anything
iterating it must filter on the value. That is a genuinely non-obvious fact that
cost this batch a defect, and it is exactly what that file is for.
