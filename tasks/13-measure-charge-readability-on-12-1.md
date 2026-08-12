# Task 13 — Measure what 12.1 will tell us about a charge spell in combat

Read `00-AGENT-BRIEF.md` first.

**This task adds measurement only. It changes no behaviour and must not.** If a
change you are about to make could alter what the player sees on screen, you have
gone too far — stop and report.

## Why

`DECISIONS.md` §19 concluded that a multi-charge spell cannot be rendered by us
during combat: `currentCharges` is a secret number, so `IsSpellReady` fails open
and the icon claims to be ready whether or not a charge is banked. The workaround
was to hand those cells to Blizzard's cooldown viewer, which knows the answer
because it is untainted. The cost the player accepted is that an adopted cell
**stops disappearing when spent** — it sweeps and dims instead.

The player wants that cost back: a charge spell should be able to behave like an
ordinary cooldown and hide when no charge is available.

§20 records that 12.1 added two APIs that carry **no secrecy flag at all**, where
the old charge API carries one:

```
C_Spell.GetSpellCharges(spell)                      SecretWhenCooldownsRestricted
C_Spell.GetSpellCooldownDuration(spell, ignoreGCD)  -- no flag, MayReturnNothing
C_Spell.GetSpellChargeDuration(spell)               -- no flag, MayReturnNothing
C_Spell.IsSpellUsable(spell)                        -- no flag
```

**Whether any of them actually distinguishes "a charge is banked" from "no charge
is banked" during combat is unknown, and reasoning will not settle it.** Two
things are already known and neither is encouraging on its own:

- Blizzard's own `CooldownViewerCooldownItemMixin:RefreshIconColor` uses
  `IsSpellUsable` only to pick an icon **tint**, and tracks cooldown state in a
  separate field. So `isUsable` is probably about power and form, not cooldown.
- A charge spell's recharge timer runs continuously while below maximum charges,
  so an API reporting "the active recharge time" may well return a duration in
  both states and distinguish nothing.

The feature is worth building only if one of these separates the two states. One
combat sample answers it. **Do not build the feature. Measure.**

## What to change

Exactly one file: `modules/SecretProbe.lua`.

It already samples at five points around combat, already classifies a value as
readable / secret / nothing / error via `Describe` and `Sample`, and already has
`ProbeDisplayPath` which calls setters with a secret to see whether they are
refused. Follow those existing shapes rather than inventing new ones.

### 1. Add `ProbeCharges(lines)`

Model it on the existing probe functions and call it from `P:Run` alongside the
others, at every sample point.

**Choosing which spells to probe — do not hardcode a spell ID.** That rule is
`CLAUDE.md` §3 and it is why Swiftmend gaining a charge in this patch needed no
code change. Select at runtime:

- Walk `Enum.CooldownViewerCategory` the way `Data.lua` does (real categories are
  values `>= 0`; the negative ones are Blizzard's disabled-state markers).
- For each `cooldownID` in each category set, read the entry and keep those where
  `info.charges == true`.
- Resolve a name for each via `overrideSpellID or spellID`, matching what
  Blizzard's own `CooldownViewerItemDataMixin:GetSpellChargeInfo` does.
- Probe **at most 3** of them, so a busy spec cannot bloat the log.

If `C_CooldownViewer` is missing, record one line saying so and return. Never
throw — this module runs on every session and an error here costs the player
their diagnostics.

For each chosen spell record, using `Sample`, one line per call:

| Label | Call |
|---|---|
| `charges <name>` | `C_Spell.GetSpellCharges(name)` |
| `charges.current <name>` | the `currentCharges` field of that result |
| `charges.max <name>` | the `maxCharges` field of that result |
| `cooldownDuration <name>` | `C_Spell.GetSpellCooldownDuration(name, true)` |
| `chargeDuration <name>` | `C_Spell.GetSpellChargeDuration(name)` |
| `isUsable <name>` | first return of `C_Spell.IsSpellUsable(name)` |
| `insufficientPower <name>` | second return of `C_Spell.IsSpellUsable(name)` |
| `cd.isActive <name>` | the `isActive` field of `C_Spell.GetSpellCooldown(name)` |

**Reading a field off a result that may be secret is itself the trap this
codebase has been caught by twice.** `issecretvalue` is asked FIRST and the nil
test comes second, because comparing a secret against nil is a comparison and
comparison is what errors. `Describe`/`Sample` already do this correctly — route
every value through them and never write your own `== nil` on a probed value.

`MayReturnNothing` means "no values returned", which is not the same as nil and
not the same as secret. `Describe` already distinguishes them; make sure a
no-return case lands as *nothing* and not as an error.

### 2. Add the two duration-object setters to `ProbeDisplayPath`

`ProbeDisplayPath` already tests whether a setter accepts a secret. Add two lines
testing whether the **duration-object** route is accepted from our tainted stack,
using a duration object obtained from `C_Spell.GetSpellCooldownDuration` for one
of the charge spells chosen above (skip the lines entirely if none was found or
the call returned nothing):

| Label | Call |
|---|---|
| `SetCooldownFromDurationObject` | `SampleCall(cooldown.SetCooldownFromDurationObject, cooldown, duration)` |
| `SetTimerDuration` | `SampleCall(bar.SetTimerDuration, bar, duration)` |

Guard both on the method existing, so this file still loads on a client that does
not have them. `SampleCall` already records a refusal as an error rather than
letting it throw.

This is the highest-value measurement in the task: §20 claims ThugUI could draw
its own in-combat sweep through duration objects, and that claim is read from
documentation and has never been run.

## Verify

```sh
luac -p modules/SecretProbe.lua
lua Tests/loadtest.lua .
```

Baseline is **176 passing, 0 failures**. The count must not go down.

Add cases to the `-- secret probe --` section of `Tests/loadtest.lua` covering:

1. A charge spell whose `maxCharges` is a **secret** is described, not read, and
   does not throw.
2. `GetSpellCooldownDuration` returning **nothing** is recorded as nothing, and
   is distinguishable in the output from returning a secret.
3. `SetCooldownFromDurationObject` **missing from the client** skips its line
   instead of erroring.
4. A client with **no `C_CooldownViewer`** records the fact and does not throw.

**Add cases. Do not repurpose an existing one.** An earlier agent rewrote a
regression test in place, changed what it asserted, and reported it as an
addition; the coordinator now diffs `ok` lines and will find it.

Before you claim a test proves anything, run it against the **unmodified** file
and confirm it fails there. Every agent that has made this claim has been telling
the truth and checking has cost a minute each time.

## Boundaries

- Do not touch `modules/CooldownViewer/`. Not Core, not Data, not BlizzBuffs.
- Do not change `BB:ShouldAdopt` or anything about which cells are adopted. The
  feature is a separate task that depends on what this one measures.
- Do not edit anything in `docs/`. Draft any proposed entry into your report and
  the coordinator will merge it.
- Do not run any state-changing git command. Leave your work uncommitted.
- You are on branch `charge-spells-can-hide`. Stay on it.

## Report

Write `tasks/reports/13-measure-charge-readability-on-12-1.md`. **No report file
means the task did not happen**, whatever you say in your final message.

Include:

- The diff you made, described in prose — what you added and where.
- The exact test output, both before and after, and which assertion failed
  against the unmodified file.
- Anything in the task file you found to be **wrong**. Task 06's agent checked
  this file's citations against Blizzard's source and found one that did not say
  what the task claimed. That was the most useful thing in its report.
- What the player must do to produce a reading: which spec, and what has to
  happen in the fight for the sample to be meaningful (they need to spend a
  charge and keep fighting, or the two states never both appear).
