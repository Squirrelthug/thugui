# 04 — Stop `BlizzBuffs` throwing its errors away

**Read `tasks/00-AGENT-BRIEF.md` first. It is not optional.**

**Type:** diagnostics only. **This task must not change what the addon does** —
only what it records. If you find yourself changing behaviour, stop and report.

**Runs alone**, after task 03. It shares `Tests/loadtest.lua` with 03 and 05.

---

## Why this task exists

`modules/CooldownViewer/BlizzBuffs.lua`:

```lua
function BB:Refresh()
    if self.applying then return end
    self.applying = true
    pcall(function() self:Apply() end)
    self.applying = false
end
```

That `pcall` discards the error. Nothing reaches `ThugUI_DebugLog`, and nothing
reaches BugGrabber either, because a caught error is not an error as far as
BugGrabber is concerned.

**We know it is hiding something real.** In the session of 2026-08-10 02:30:21,
Roll the Bones held `wanted = true` through five separate combats — behaviour
only adoption can produce, since the plain aura path provably returns nothing in
combat. So `count > 0` happened. Yet `LogOnce("blizzbuffs-adopted", ...)`, which
sits at the very bottom of `Apply`, **never fired all session**. The log held 53
entries against a 300 cap, so nothing was evicted, and `LogOnce`'s `seen` table
is a plain local reset every load, so nothing was suppressed.

Something in `Apply` is failing after the adoption loop, every pass, silently.

This also breaks the project's own rule, from `skills/wow-addon-dev/SKILL.md`:
**log the stage that failed, not the failure.** Diagnosing the Opportunity bug
took evidence-by-elimination across three separate files because this one line
threw the answer away.

## Files you may modify

- `modules/CooldownViewer/BlizzBuffs.lua`
- `Tests/loadtest.lua`
- `tasks/reports/04-report.md`

## What to change

### Step 1 — capture the error

Take both return values from the `pcall` and record the message when it fails.

Constraints, all of which matter:

- **`LogOnce`, not `Log`.** `Refresh` runs on a hook that fires on every layout
  pass. `Log` here would fill the 300-entry ring buffer within seconds and bury
  the very context that explains the failure. `docs/DECISIONS.md` §11.
- **Key it on the message**, not a constant, so a second distinct failure is not
  masked by the first.
- **`self.applying` must still be cleared on the failure path.** It is already
  outside the `pcall`; keep it that way. If that flag ever sticks true, every
  future refresh silently returns and the feature dies until `/reload`.
- **The logging itself must never throw** — always-on diagnostics must not be
  the reason something breaks. Guard the `ThugUI.Diagnostics` lookup the way the
  rest of the file does.
- Include the category prefix `"CVBUFF"` so it groups with the existing lines.

### Step 2 — say which stage failed, per icon

Inside `BB:Apply`'s loop, an aura-mode icon can fail to adopt for three reasons
that look identical from outside:

| Stage | Condition |
|---|---|
| no Cooldown Manager entry | `Data.GetCooldownInfoForSpell(icon.spellID)` gave nothing |
| entry has no cooldown ID | `info` exists, `info.cooldownID` is nil |
| no matching item frame | `map[info.cooldownID]` is nil — the buff is in neither of Blizzard's active lists |

Log each as its own `LogOnce`, keyed on **spell ID and stage together** so one
stage cannot suppress another. The third is the common one in practice and the
one the player can act on — it means the buff is not in Tracked Buffs or Tracked
Bars (`docs/DECISIONS.md` §13).

Include the spell name if `icon.spellName` is set, and the spell ID always. A
name alone is not enough: two placements can share a name.

**Do not add a success log per icon.** The existing `blizzbuffs-adopted` count
covers that, and this file is event-level by design.

### Step 3 — leave the behaviour alone

No change to what gets adopted, anchored, scaled, lowered or released. No new
early return. A reviewer should be able to read your diff and see only logging.

## Tests

Add to `Tests/loadtest.lua`:

1. **An `Apply` that throws is logged, not swallowed, and `applying` is
   cleared.** Force a throw inside the pass — the stub layer already models
   frames, so making one item's method error is the cleanest route — then assert
   a `CVBUFF` entry naming the failure was recorded, and that a subsequent
   `BB:Refresh()` still runs rather than returning early on a stuck flag.
2. **An aura-mode icon with no matching item frame logs the "no item frame"
   stage**, and does so **once**, not per pass.
3. **The existing BlizzBuffs cases still pass unchanged.** There are several
   already — including three regression cases pinning the taint fixes from
   `docs/DECISIONS.md` §15. If any of those change behaviour, you have gone
   beyond this task; stop and report.

## Verification gate

```sh
luac -p modules/CooldownViewer/BlizzBuffs.lua Tests/loadtest.lua
lua Tests/loadtest.lua .
```

All prior tests plus yours. Paste the tail.

## Report

`tasks/reports/04-report.md`, per brief §10.

In **Not verified**, state plainly that the real cause of the silent failure is
still unknown — this task only makes it visible — and that confirming it needs
the player to play a session and `/reload`.
