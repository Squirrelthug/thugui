# Task 19 report — category cells: resolve, remember, repaint

**Written by the coordinator, not by the execution agent.** The agent that built
task 19 did the work and never filed a report — the same failure shape as task
17 (`13b3669`). This reconstructs the record from the diff, the harness, and the
player's in-game results, so the rule "no report file means the task did not
happen" does not silently write off code that demonstrably shipped.

**Treat the reconstruction itself as lower-grade evidence than a live report.**
Everything below was re-derived from what is on disk. Some of the builder's own
notes did survive, second-hand, in the 2026-08-13 handoff entry — the
`DiscoverCategoryIDs` cost note under "Still open" is theirs — so the previous
coordinator saw a report in some form. It was never written to `tasks/reports/`,
which is the only place a later reader would look.

## Harness

| Point | Count |
|---|---|
| Baseline, clean tree | 213 passing, 0 failures |
| After task 19 as built | 219 passing, 0 failures |
| After the regression fix below | **224 passing, 0 failures** |

Six cases added by task 19, one per numbered requirement in the task file. No
case was removed or renamed — checked by diffing passing-case names against a
pristine `HEAD` tree, not by trusting the count, because a rename plus an
addition nets to the same number.

## What was built, against the six decisions

All six landed as specified. Verified by reading the diff, not the (absent)
report:

1. **Icon is Blizzard's category art** — `item:GetSpellCategoryIcon()` preferred,
   `item:GetSpellTexture()` as fallback, both under `pcall`.
2. **Resolution order** — cache, then pooled item frame, then
   `GetLastCategoryCooldownSource`, then the generic label. `issecretvalue`
   screening stayed ahead of every nil test.
3. **Persisted account-wide cache** — `ThugUI_Config.cvCategoryArt`, and
   correctly **not** cleared by `Data.InvalidateCooldownInfoCache`.
4. **Cheap read split from expensive resolve** — `Data.CategoryEntry` reads only
   the cache; `Data.ResolveCategoryArt` does the discovering.
5. **Re-resolve on combat transitions** — from the existing
   `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` handler, no new registration.
6. **Repaint the drawn cell** — in `UpdateState`'s category branch, updating
   `icon.baseTexture` alongside `icon.tex`, guarded on inequality.

Two things the builder got right that the task file did not tell them to do, both
worth crediting:

- The `pcall` discipline was extended to `GetSpellCategoryIcon`, not just
  inherited on the calls that already had it.
- The `cvCategoryArt` default was raised in review as a table-vs-scalar hazard in
  `ER.defaults` — see `DECISIONS.md` §25, "A table default in `ER.defaults` is
  not the same as a scalar one". That catch is worth more than the feature.

## The regression it shipped, and the fix

**The player tested it and reported the cells stopped updating entirely** —
strictly worse than before, where combat refreshed the picker and a display-mode
change refreshed the drawn grid.

**The fault was in the task file, not the execution.** Decision 4 said
`ResolveCategoryArt` should resolve "categories not already resolved", and the
implementation reasonably read that as iterating `Data.DiscoverCategoryIDs()`.
Discovery comes from the Cooldown Manager sweep, and that session logged
`CVBUFF: no Blizzard cooldown-viewer item frames found` — so a **placed**
category was never attempted at all.

Fixed in three places, all no-ops once a category is resolved:

- `CategoriesNeedingArt` unions discovery with the categories actually placed.
- `CV:Rebuild` calls `ResolveCategoryArt` — this is what the player's
  dropdown-change workaround physically was.
- `Data.BuildSpellList` calls it when the list contains categories, restoring the
  picker's previously-free resolve.

New case: **"task 19 regression: a PLACED category resolves even when discovery
cannot see it"**. Confirmed failing against the unfixed source (`1 failure(s)`)
and passing after. That verification was run, not reasoned about.

## Still unverified in game

- Whether `item:GetSpellCategoryIcon()` exists on the live client. The player's
  Cooldown Manager sweep has been coming back empty, so path 2 has probably never
  run for real — the resolves that matter are all coming from
  `GetLastCategoryCooldownSource`.
- Whether a login → combat → `/reload` round-trip persists the cache correctly.
- Whether the repaint reaches the cursor-following grid without a rebuild. This
  is the headline claim of the whole task and it has never been seen working.

## Lesson for the next task file

**Ask what the old code was reached *with*, not only what it did.** Task 19 moved
category art from pull (resolve whenever anyone asks, with whatever ID they ask
about) to push (resolve on a schedule, for a known set) and never enumerated what
used to arrive by being asked for. `DECISIONS.md` §25 carries the general form.
