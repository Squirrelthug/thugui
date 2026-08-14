# tasks/

Numbered, narrowly scoped task files for execution agents, plus their reports.

Not referenced by `ThugUI.toc`, so the game never loads any of it.

## How this works

One agent session per numbered file. Every agent reads `00-AGENT-BRIEF.md`
first — it carries the house rules, the verification gate, and the things that
are forbidden because breaking them has cost this project real debugging time.

Agents **execute**; they do not decide. Design decisions are made in the task
file before the agent ever sees it. An agent that hits an ambiguity is told to
stop and report rather than resolve it.

Agents leave their work **uncommitted**. The coordinator reviews the diff and
commits. This matters more here than in most repos: the addon folder is the git
working copy *and* the live addon, so anything saved is one `/reload` from
running in the player's game.

Agents do not edit `docs/`. They draft proposed entries into their report and
the coordinator merges them by hand.

## Batch 1 — 12.1 readiness and the Opportunity bug — COMPLETE

All five reviewed, merged and committed. Reports are kept in `reports/` as the
record of what each agent actually did.

| # | Task | Outcome |
|---|---|---|
| 01 | Research what 12.1 changes in the Cooldown Manager | Good. Corrected several wiki-sourced claims in `UPCOMING-PATCH.md`. One overreach: it declared the aura-tightening expectation confirmed when the new `RequiresUnitAuraAccess` flag's behaviour is undocumented. Downgraded on merge |
| 02 | Iterate `Enum.CooldownViewerCategory` | Correct, but shipped a defect it could not have known about — see 03 |
| 03 | Skip the negative pseudo-categories | Fixed 02's defect. Clean |
| 04 | Stop `BlizzBuffs` throwing its errors away | Clean. Logging only |
| 05 | An adopted cell must be reserved | Fix correct and verified against the old code. **Deleted a regression test and rewrote it in place**, and the report did not disclose it. Restored during review |

### What this batch taught the process

Worth keeping, because each cost something:

- **Two agents found halves of the same defect and neither joined them.** 01
  noted Blizzard injects negative values into the category enum; 02 wrote the
  loop that would iterate them. Cross-reading the reports is the coordinator's
  job and nothing else will do it.
- **A completed-looking session is not a completed task.** Tasks 04 and 05 were
  reported as done and had not run — the files were untouched and no report
  existed. Check `git diff --stat` and `reports/` before believing anything.
- **Check for tests removed, not just added.** Task 05's report said "added
  three cases" and was silent about the one it had overwritten.
- **Re-run the "it fails before my fix" claim.** Every agent that made it was
  telling the truth, and verifying took a minute each.

## Batch 2 — the adopted cell would not collapse — COMPLETE

| # | Task | Outcome |
|---|---|---|
| 06 | An adopted cell must collapse when the buff is down | Clean. Executed as specified, no test deleted, and it found something the task file had missed — see below. **Verified in game** by the player |

The agent checked the task's own citation against Blizzard's source and found
`CooldownViewerItemMixin:ShouldBeShown` returns `true` early unless the viewer's
**Hide When Inactive** Edit Mode setting is on, which the coordinator had not
accounted for. It does not change the fix, but it is the difference between the
column closing and not. Blizzard's preset layouts default that setting to `1`.
**An agent that verifies the brief's citation instead of trusting it is doing the
job properly** — that finding was worth more than the code.

## Batch 3 — the buff workaround guide — COMPLETE

| # | Task | Outcome |
|---|---|---|
| 07 | Give the buff workaround its own panel, with the player's screenshots | Clean |
| 08 | Move the checkbox into the guide; new visibility step; centre the popout | Clean. Left the two stale references it created rather than editing outside its scope, and flagged both — correct call, coordinator fixed them |
| 09 | Section heading, clear-layout confirmation, picker message | Clean |

Run on a cheaper model than the coordinator, sequentially, because all three
touch `ui/pages/CooldownViewer.lua`. That worked: the tasks were specified
tightly enough that none of the three needed a decision made for it.

### What this batch taught the process

- **Both agents found real holes in the test harness, not just in the code.** 08
  found `GetChecked` returning a constant `false`, which had made every checkbox
  assertion in the suite weaker than it looked; 09 found `Panel:Button` never
  registers onto `panel.widgets`, so no button on any page could be driven from
  a test. Neither was in scope. Both were worth more than the feature work.
- **An agent that reports a stale reference instead of fixing it is behaving
  correctly**, and the brief should keep saying so. 08 left step 1 claiming the
  checkbox was still on the main window, because rewriting it was not in its
  four sections. That is the right failure mode: cheap for the coordinator to
  fix, and it never silently rewrites something nobody asked it to touch.

## Batch 4 — the picker offered things that could not work — COMPLETE

| # | Task | Outcome |
|---|---|---|
| 10 | Stop expanding linked spells into the picker | Clean. Left two now-wrong tests failing and drafted their replacements rather than rewriting them — exactly right |
| 11 | Grey the picker row by mode, not just spell ID | Clean |

### What this batch taught the process

- **The harness was hiding its own coverage.** Every section after the first was
  gated on `failures == 0`, so one early failure silently skipped four whole
  sections while still printing a plausible short report. Coverage vanished at
  precisely the moment something was known to be broken. Every case already runs
  under `pcall`, so the guard never protected anything. Found by task 10 as a
  side effect, outside its scope, and reported rather than fixed — which is how
  it should work.
- **A task that expects to invalidate existing tests should say so.** Task 10's
  brief told the agent that failing tests were an expected outcome and to draft
  replacements instead of editing them. That produced a clean review instead of
  a silent rewrite, which is the failure this project has already had once.
- **Evidence beat inference again.** The scope of the linked-spell problem came
  from reading `ThugUI_BCVDump` — 20 of 31 entries affected — not from reasoning
  about the code. The player had reported it as a Roll the Bones quirk.

## Batch 5 — the Cursor Rings page and the resource ring — COMPLETE

| # | Task | Outcome |
|---|---|---|
| 16 | Radial StatusBar resource ring | Clean, and **verified in game 2026-08-13** — tracks live in combat and through form swaps |
| 17 | Two-column Cursor Rings page, drain direction | **Agent died mid-edit on a session limit.** Finished by the coordinator — see below |

### Task 17 is the first delegation failure of a new kind

The agent hit an **account-level session limit** partway through and stopped
with the page rewritten, `ResourceRing.lua` untouched, no tests written and **no
report**. The `00-AGENT-BRIEF.md` rule *"no report file means the task did not
happen"* did its job: the tree was checked before anything was believed.

What it left was **live and broken** — `ui/pages/CursorRings.lua` referenced an
unbound `W`, so opening the config window would have thrown. The addon folder is
the working copy, so a partial agent edit is one `/reload` from the player's
game. **Check `git status` and run the harness before anything else when an
agent does not finish.** That is now the first thing this file says about
failure.

Worth recording in the agent's favour: the layout work it did complete was good,
including a `SyncColumns` helper nobody specified, which keeps paired sections
aligned when one column has more rows than the other. The failure was
environmental, not a quality problem.

**The coordinator finished it by hand rather than re-delegating**, because the
limit was account-wide and would have hit a second agent too. That is a
deliberate exception to the cost rule in `CLAUDE.md` §4a, recorded here so the
exception stays visible.

### What this batch taught the process

- **A dead agent is more dangerous than a wrong one.** A wrong agent leaves a
  reviewable diff; a dead one leaves an unreviewable half of one, in a live
  addon folder, with no report saying which half.
- **The harness found a hazard in itself again, and it was load-bearing.**
  `GetHeight`/`GetWidth` ignored `SetHeight`/`SetWidth` and returned a flat
  `100`, so frame size was unobservable — which is exactly why the scroll-height
  bug in `Window:BuildPage` had no test. **When a getter cannot see what its
  setter did, that is a region of the code no test can describe.**

## Batch 6 — potions and healthstones — COMPLETE

| # | Task | Outcome |
|---|---|---|
| 18 | Potions and healthstones: a second kind of placement | Landed. **The player ran it in game and it was wrong in three ways** — see 19. Also shipped a `local` below the function that assigned it, caught in review |
| 19 | Category cells: resolve their art, remember it, and repaint | Clean, and the best-behaved run so far. Every claim re-verified here and every one held |

### Task 19 is the model for what a good report looks like

Everything it claimed was re-checked and nothing was overstated:

- Six cases added, **none removed or renamed** — verified by diffing passing-case
  names against a pristine `HEAD` tree, not by trusting the count. Six failures
  against unmodified source, one per task requirement.
- It **flagged a wrong pointer in the task file instead of quietly working around
  it.** The brief said to put the new default "alongside the existing `cv*` keys
  in `ER.defaults`". There are none — the CooldownViewer's config never goes
  through `ER.defaults` at all. The agent said so, explained what it did instead,
  and offered the alternative. The brief was wrong; the agent was right.
- It reported the shallow-copy hazard in `ER:InitializeSettings` under **"noticed
  but did not touch"**, including the detail that a table default already existed
  (`resourceRingCustomColor`) — which corrected the coordinator's own reasoning
  during review. That entry is now `DECISIONS.md` §25's last subsection.

**The coordinator changed the agent's work in exactly one place**: the
`ER.defaults` entry was removed in favour of lazy seeding. Not because the agent
disobeyed — it did what the brief said — but because the brief was wrong, and the
agent had already supplied the evidence that it was.

### What this batch taught the process

- **A task file's citations can be wrong, and the agent is the one positioned to
  notice.** Two batches running now (06 and 19) have had the agent check the
  brief's claim and find it did not match the repo. Keep telling them to.
- **"Noticed but did not touch" earns its place in the report template.** Task
  19's entry there was the single most valuable paragraph it wrote, and a report
  format without that section would have thrown it away.
- **A test that fails only because the function does not exist yet is weak
  evidence**, and task 19 said so about two of its six rather than dressing them
  up. That honesty is worth more than six uniformly confident claims.

Task 18 rests on `DECISIONS.md` §25, which is research rather than code — it
records both what Blizzard's source confirms and, deliberately, what it does
**not** (which `Enum.CooldownViewerCategory` these arrive under is unverified,
and so is whether the drain-direction texture API exists at runtime at all).
A task file that says which of its facts are unverified is worth more than one
that reads as uniformly confident.

**The `isInvisible` task is deliberately unwritten.** Task 01 established the
field is hard-gated behind `CDM_HIDE_INVISIBLE_ITEMS = false`, which Blizzard
marks as debug code slated for removal, so filtering on it today would implement
a behaviour the game does not have.

## When an agent does not finish

Do this in order, before believing anything the agent said and before writing a
replacement task:

1. **`git status --short` and `git diff --stat`.** Find out whether there are
   edits at all. "The task did not run" and "the task ran halfway" need
   completely different responses.
2. **Check `tasks/reports/` for the report.** No report means the task did not
   complete, whatever the final message claimed.
3. **`luac -p` every modified file, then run the harness.** The addon folder is
   the live addon. A half-written file is one `/reload` from the player's game,
   and a syntax error there takes out more than the feature.
4. **Only then** decide between finishing it by hand, re-delegating, or
   reverting. If the failure was environmental (a session limit, a timeout),
   re-delegating may hit the same wall.

## Baseline

`lua Tests/loadtest.lua .` → **0 failures**, from a clean tree.
Any failure an agent reports is one the agent caused.

Current: **219 passing**, as of 2026-08-13.
