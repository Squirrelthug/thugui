# 00 — Agent brief. Read this before any numbered task.

You are an **execution agent** on the ThugUI addon. A coordinator wrote your task
file and will review your work afterwards, line by line, against this brief.

**Your job is to execute a narrowly scoped task exactly as written.** You are not
being asked to design, to improve the surrounding code, or to decide anything the
task did not decide for you.

If the task is ambiguous, or the repo contradicts what the task says it will
find: **stop, and write it in your report.** Do not improvise a resolution. A
task that comes back half-done with a clear question is a good outcome. A task
that comes back complete because you guessed is not.

---

## 1. Read order

1. This file.
2. `CLAUDE.md` at the repo root.
3. `docs/HANDOFF.md` — where the work actually stands.
4. Whichever `docs/DECISIONS.md` sections your task cites. They exist so you do
   not re-derive things that cost real debugging time.

Then your numbered task file.

## 2. Environment

| | |
|---|---|
| Repo root | `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\ThugUI\` |
| Game | Retail, Interface **120007** (12.0.7) |
| Lua in game | **5.1** |
| Local `lua` / `luac` | **5.5** — mind the gap. No `goto`, no integer division, no `table.pack`; `unpack` is a global |
| Shell | Windows, PowerShell and Git Bash both present |

**The addon folder IS the git working copy.** There is no build step and no
separate checkout. Your edits are live in the player's game the moment they
`/reload`. Treat every save as shipping.

## 3. Verification gate — do not report success without this

```sh
luac -p <every file you touched>      # syntax
lua Tests/loadtest.lua .              # must print "0 failure(s)" and exit 0
```

Run both. Paste the tail of the loadtest output into your report. The current
baseline is **0 failures** — if you see any, you caused them.

`loadtest.lua` stubs the WoW API, loads every file in TOC order, builds every
config page and drives the cooldown-viewer engine. It is a smoke test, not proof.
It cannot tell you an icon is in the right place, and it cannot tell you which
events the client delivers.

**If your task fixes a bug, add a case to `Tests/loadtest.lua` that fails before
your fix and passes after.** A bug with no test is a bug that comes back. Say in
your report which case you added and how you confirmed it fails on the old code.

## 4. What you may not claim

**You cannot launch World of Warcraft, so you can never verify anything in game.**

`docs/HANDOFF.md` §2 keeps a table that separates *confirmed in the running game*
from *correct in code*. That distinction is load-bearing on this project — it is
what stopped a wrong conclusion being stated confidently for a third time. If
your task has you touch that table, your entry goes in as **unverified in game**
and nothing else. Do not upgrade someone else's row either.

Same rule in your report: say "tests pass" or "correct in code". Never "works".

## 5. Hard rules

These are not style preferences. Each one is in the docs because breaking it
cost this project a debugging session.

**Never write to a Blizzard frame.** Not `frame.__myField = x` — a field you set
on their table is a taint, not free bookkeeping. Not `SetFrameStrata`, not
calling their methods from your stack. Reads are free. `hooksecurefunc` is
taint-safe by design. `SetPoint`/`SetScale` on a pooled item is proven safe and
is the one exception already relied on. Keep bookkeeping in weak-keyed side
tables. `DECISIONS.md` §15.

**Namespace every global name you create.** `CreateFrame("Frame", "SomeName", …)`
sets `_G.SomeName` from addon code, which taints that global for everyone. A
frame named `EssentialCooldownViewer` collided with a Blizzard frame shipped
years later and broke their cooldown viewer. Prefix `ThugUI_`.

**Screen for secrets before you touch a value.**

```lua
local value = UnitPower("player", powerType)
if issecretvalue and issecretvalue(value) then
    return          -- hold last known state. No maths, no compare, no format.
end
```

Comparing a secret to `nil` is itself a comparison. Check `issecretvalue` first.

**Spell readiness comes from `isActive` / `isOnGCD`, never `startTime`/
`duration`.** The GCD is a running cooldown, so judging by duration makes the
whole display vanish in combat — and in 12.x those fields are secret anyway.
`DECISIONS.md` §5.

**Query spells by name, not ID.** `C_Spell.GetSpellInfo` resolves a name only for
a spell the player has, so it doubles as the talent check. `DECISIONS.md` §5.

**Never invent a spell ID, a frame name, or an enum value.** Verify it against
Blizzard's source or resolve it at runtime. A plausible wrong ID produces a bug
that reads like a logic error.

**`RegisterUnitEvent(event, "player")`, plus a `unit ~= "player"` guard.**
`UNIT_*` events fire for every unit in range. The failure scales with group size,
so it is invisible exactly where you test. `DECISIONS.md` §6.

**Never `SetParent(nil)` to tear down a UI.** It orphans the frame, it does not
free it. Pages build once and are shown/hidden. `DECISIONS.md` §2.

**Two config stores exist and that is final.** `ThugUI_Config` (flat) and
`ThugUIDB` (nested per module). Do not create a third. `DECISIONS.md` §1.

**Do not delete the legacy fallback.** The old ECV/BCV/GCV bars in
`modules/EssentialRings.lua` and the Blizzard settings panels are the deliberate
escape hatch. Nothing gets removed on this project without being asked.

**Load order is a constraint, not a convention.** `ThugUI.toc` carries a comment
explaining every ordering requirement. Read them before moving a line.

## 6. Verify against Blizzard, do not guess

`docs/SOURCES.md` is the vetted list. The short version: **wiki for signatures,
Blizzard's own Lua for semantics.** The wiki documents what a function returns
and routinely says nothing about what it means — and it has been outright wrong
about secret values on this exact client.

```sh
gh api "repos/Gethe/wow-ui-source/git/trees/live?recursive=1" --jq '.tree[].path' | grep -i cooldownviewer
gh api "repos/Gethe/wow-ui-source/contents/<path>?ref=live" --jq .content | base64 -d
```

Branches: `live`, `beta`, `ptr`. `Blizzard_APIDocumentationGenerated/*.lua` is the
underrated one — it carries the flags that decide what an addon actually gets
(`RequiresNonSecretAura`, `SecretWhen*`, `SecretArguments`).

**Cite your source in your report** whenever you relied on one, with the path or
URL. "The wiki says" without a link is not evidence on this project.

## 7. Files you may not touch

- Anything under `WTF/` — **never edit SavedVariables.** WoW holds those tables
  in memory and overwrites your edit on logout. Reading them is fine and often
  the point.
- `libs/oUF/` unless your task names it explicitly. It is vendored MIT code.
- Any file not listed in your task's **Files you may modify** section. If the
  task cannot be completed without touching something else, stop and report it.

## 8. Git — read only

Run `git status`, `git diff`, `git log` freely. **Do not run any git command that
changes state.** No `commit`, no `push`, no `checkout`, no `stash`, no `reset`,
no branch creation.

Leave your work uncommitted in the working tree. The coordinator reviews the diff
and commits it. This is deliberate: it is how your work gets checked before it
reaches the player's live addon folder.

## 9. Documentation policy

This project runs on its documentation, and keeping it current is part of the
task, not an extra.

- **Comments explain WHY.** The code already says what. Every non-obvious
  decision in this codebase carries the reason it was made.
- **Match surrounding style.** `modules/` is 4-space indent, no semicolons.
- **You do not edit anything under `docs/`.** Not `DECISIONS.md`, not
  `HANDOFF.md`, not `KNOWN-ISSUES.md`, not `UPCOMING-PATCH.md`. Those files are
  the record this project runs on, several agents may be working at once, and
  the coordinator merges them by hand.
- **Instead, draft.** If you worked something out that the code alone would not
  tell the next person, write the proposed entry into the **Proposed docs
  changes** section of your report, saying which file and which section it
  belongs under. Write it as you would want it to land — the coordinator edits
  and pastes it in.
- Never state, in a draft or anywhere else, that something is verified in
  game — see §4.

## 10. Your report

Write `tasks/reports/NN-report.md`, matching your task number. This file is how
your work gets reviewed, so an accurate report of partial work beats a confident
report of complete work.

```markdown
# NN — <task title> — report

**Status:** complete | partial | blocked

## What I changed
<one paragraph, plain language>

## Files touched
| File | What |
|---|---|

## Verification
$ luac -p <files>
<output>

$ lua Tests/loadtest.lua .
<tail, including the failure count line>

## Tests added
<which case, and how you confirmed it fails without the fix — or "none, and why">

## Sources used
<path or URL for anything you looked up>

## Proposed docs changes
<the entry you would add to docs/, naming the file and section. You do not edit
docs/ yourself — see §9. Write "none" only if you genuinely learned nothing a
future reader would want.>

## Could not do
<anything blocked, ambiguous, or out of scope — with the question you need answered>

## Noticed but did not touch
<anything that looked wrong outside your scope. Do not fix it. Just say it.>

## Not verified
<everything a running game would be needed to confirm. Be exhaustive.>
```

The last two sections are the ones the coordinator reads first. An empty
"Noticed but did not touch" on a real task is usually a sign you were not
looking.
