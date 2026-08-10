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

## Next batch — nothing written yet, on purpose

The open thread is in `docs/HANDOFF.md`, "Read this first". It needs the player
to test in game before any further task can be specified: the Opportunity fix is
unconfirmed, and there is a second fault in `BB:Apply` that the new logging
should finally name. Writing tasks against either right now would mean
specifying work against a guess.

**The `isInvisible` task is deliberately unwritten.** Task 01 established the
field is hard-gated behind `CDM_HIDE_INVISIBLE_ITEMS = false`, which Blizzard
marks as debug code slated for removal, so filtering on it today would implement
a behaviour the game does not have.

## Baseline

`lua Tests/loadtest.lua .` → **0 failures**, from a clean tree.
Any failure an agent reports is one the agent caused.
