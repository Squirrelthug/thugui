# ThugUI — agent instructions

**Read `docs/HANDOFF.md` first.** It says exactly where the work stands, which
changes are verified in game and which are only correct in code, and what the
one open thread is. Then finish this file, then `docs/DECISIONS.md` — the
reasoning behind how the addon is built, which will stop you re-deriving things
that cost real debugging time to learn.

ThugUI is a personal UI suite for one player on WoW retail. It is not a public
addon. That changes the trade-offs: correctness for **this** player's setup
beats generality, and breaking something that has worked for months is much
worse than shipping a feature slowly.

---

## 1. Environment

| | |
|---|---|
| Addon path | `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\ThugUI\` |
| Repo | `github.com/Squirrelthug/thugui` (public), branch `main` |
| Game version | Retail, Interface **120007** (12.0.7) |
| Lua | WoW runs **5.1**. The local `lua` is **5.5** — mind the gap |
| Shell | Windows. PowerShell and Git Bash both available |

**The addon folder IS the git working copy.** Edits are live in-game after
`/reload`. There is no build step and no separate checkout.

---

## 2. Before you claim anything works

```sh
luac -p path/to/file.lua        # syntax; run on every file you touched
lua Tests/loadtest.lua .        # loads every TOC file in order, builds every
                                # page, drives the engine. Exits non-zero on failure
```

`Tests/loadtest.lua` is the closest thing to a smoke test that exists without
launching the game. It has caught real bugs — an unanchored-icon bug, and an
aura check that accepted other players' buffs. **Add a case for every bug you
fix.** A bug that had no test is a bug that will come back.

It is a smoke test, not proof. It cannot tell you an icon is in the right
place, and it cannot verify which events the client actually delivers.

---

## 3. The rules that matter

### Verify against Blizzard's source, do not guess

**`docs/SOURCES.md` is the list of trustworthy sources** — read it, use it, and
add to it when you find something good. Reliable WoW addon information is hard
to find and most search results are noise.

The short version: **wiki for signatures, Blizzard's own Lua for semantics.**

```sh
gh api "repos/Gethe/wow-ui-source/git/trees/live?recursive=1" \
  | ConvertFrom-Json | %{ $_.tree } | ? path -match 'CooldownViewer'
gh api "repos/Gethe/wow-ui-source/contents/<path>?ref=live" --jq .content   # base64
```

Branches: `live`, `beta`, `ptr`. Or use townlong-yak's build **Compare** view for
patch diffs. This is how the Roll the Bones buff tracking was solved after the
wiki turned out to document the fields and none of the behaviour.

**Never invent a spell ID.** Verify it, or resolve it at runtime from the game.

### Read the evidence before theorising

Two files, both on disk, both only flushed on `/reload` or logout:

| File | What |
|---|---|
| `WTF/Account/SQUAZZIL/SavedVariables/!BugGrabber.lua` | Runtime errors, with stacks and locals |
| `WTF/Account/SQUAZZIL/SavedVariables/ThugUI.lua` | Settings, plus `ThugUI_DebugLog` — **always-on** diagnostics |

`ThugUI_DebugLog` needs no command. `events` is a per-session log; `state` is a
snapshot taken at logout, listing every placed icon with its resolved
linked-spell count. **That count is evidence of which code actually ran** —
more reliable than a version string, and it exists because a fix was once
pushed, not loaded, and the resulting behaviour was indistinguishable from the
fix not working.

An error from a session still in progress is not on disk yet. Ask for a
reload — one reload beats two rounds of speculation.

`Tests/replay_probe.lua` runs a real `/thugcv probe` dump through the live
code, which separates "our logic is wrong" from "they were on an older build".

### Never break the fallback

The old ECV/BCV/GCV bars in `modules/EssentialRings.lua` still work and are
reachable with `/thugcv legacy`. The Blizzard settings panels are all still
registered. **Both are deliberate.** Do not delete either without being asked;
they are the escape hatch when something new misbehaves.

### Editing SavedVariables requires the game fully closed

WoW holds those tables in memory and writes them on logout. Edit while it is
running and your change is silently overwritten. Check first:

```powershell
Get-Process -Name Wow -ErrorAction SilentlyContinue
```

Back up before editing, and parse the result afterwards — a malformed file makes
the game discard the **whole** variable, losing every setting.

### Confirm before building anything large

The player wants to approve design decisions before implementation, in
increments, and would rather answer a question than have you build the wrong
thing thoroughly. Present real options with trade-offs. Then build the chosen
one completely.

Small fixes and obvious calls: just do them.

---

## 4. Code conventions

- **Comments explain WHY.** The code already says what. Every non-obvious
  decision in this codebase carries the reason it was made — keep that up, it
  is the thing that makes the codebase survivable.
- Match surrounding style. `modules/` uses 4-space indent, no semicolons.
- New settings go in `ThugUI_Config` (flat keys) or `ThugUIDB` (nested per
  module) — see `docs/DECISIONS.md` §1 for which and why. Do not create a third
  store.
- New config pages register themselves via `ThugUI.Window:RegisterPage{...}` in
  `ui/pages/`, and must load after the module they configure.
- Never rebuild a UI page by destroying children with `SetParent(nil)`. That
  does not free a frame in WoW, it orphans it.

## 5. Git

Commit messages explain the reasoning, not just the change — they are part of
the record this project runs on. Push to `main`.

PowerShell mangles quotes in inline commit messages. Write the message to a
file and use `git commit -F <file>`.

---

## 6. Skills

Available at `C:\Users\Squirrel\iCloudDrive\Desktop\claude-skills-main\skills`.
Ones that actually apply here:

| Skill | When |
|---|---|
| `debugging-wizard` | A symptom whose cause is not obvious — most of this project's hard problems |
| `test-master` | Extending `Tests/loadtest.lua`, especially the stub layer |
| `code-reviewer` | Before a large change lands |
| `game-developer` | Frame/render/update-loop questions |
| `legacy-modernizer` | Touching the ECV/BCV/GCV code or migrating off it |
| `code-documenter` | Keeping `docs/` current |

---

## 7. Documents

| File | What it is |
|---|---|
| `docs/HANDOFF.md` | **Start here.** Where the work stands, verified vs not, what is queued |
| `CLAUDE.md` | This. How to work on the addon |
| `docs/DECISIONS.md` | Why the addon is built the way it is. The reasoning log |
| `docs/SOURCES.md` | Where trustworthy information comes from, with last-checked dates |
| `docs/KNOWN-ISSUES.md` | Understood problems deliberately not fixed, and what would change that |
| `docs/UPCOMING-PATCH.md` | What we know about the *next* game patch, accrued before it ships |
| `Tests/README.md` | What the harness covers and what it cannot |

**Keep `DECISIONS.md` current.** When you solve something non-obvious, add the
reasoning. That file is the point of this whole arrangement.

`UPCOMING-PATCH.md` is deleted when that patch goes live — anything still true
moves into `DECISIONS.md` or the code — and a fresh one starts for the patch
after.
