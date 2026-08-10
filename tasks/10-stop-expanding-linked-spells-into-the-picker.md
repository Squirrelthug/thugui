# 10 — Stop offering buffs that can never draw

Read `00-AGENT-BRIEF.md` first.

Baseline: `49b34d0`, `lua Tests/loadtest.lua .` → **0 failures**.

Files you may modify:
- `modules/CooldownViewer/Data.lua`
- `Tests/loadtest.lua`
- `tasks/reports/10-report.md`

---

## 1. The bug

`Data.BuildSpellList` expands each buff entry's `linkedSpellIDs` into extra
picker rows. The comment at `CooldownViewerSpellIDs` says why:

> An entry standing for a SET of buffs offers only the set: pick "Roll the
> Bones" and you get whichever outcome is live. Listing the outcomes
> individually as well lets a player track one of them specifically -- "show me
> only when I roll Jackpot".

**That intent cannot be satisfied, and the player has now tested it.** Placing
Roll the Bones plus all four outcomes in `aura` mode renders exactly one icon.

The reason is structural, not a bug to fix elsewhere. `BB:Apply` maps **one
Blizzard item frame per `cooldownID`**, and every linked ID resolves to the base
entry's `cooldownID` — Roll the Bones and its four outcomes are all `cdID 42743`
in the player's own dump. Five cells, one frame to borrow, one winner. No logic
makes five cells share one frame.

It is also not a Roll the Bones quirk. In the player's `ThugUI_BCVDump`,
**20 of 31 tracked-buff entries carry linked spell IDs**, so the picker is
currently showing roughly twenty rows that cannot work. Four of them expand
under a *different name*, which reads as a separate trackable buff rather than a
duplicate:

| Base entry | Expanded row that cannot work |
|---|---|
| Opportunity `279876` | Opportunity `195627` |
| Gravedigger `1265863` | Palmed Bullets `1265931` |
| Unseen Blade `441146` | Fazed `441224` |
| Coup de Grace `441423` | Escalating Blade `441786` |
| Cloud Cover `441429` | Smokescreen `441640` |

## 2. What to do

**Stop expanding `linkedSpellIDs` into the picker list.** Not a special case for
spells with several outcomes — all of them. Two reasons this is safe, and both
should be checked rather than taken on faith:

1. The base entry already covers the linked buffs at runtime. `ResolveAura` in
   `modules/CooldownViewer/Core.lua` walks `icon.linkedSpellIDs` and returns
   whichever is live — that is why the player's Roll the Bones works and reports
   `linked=4`.
2. Every entry in the dump has a usable base spell ID, so nothing becomes
   unreachable by dropping the expansion.

Concretely: `CooldownViewerSpellIDs(categoryName, expandLinked)` loses its
expansion behaviour, and `BuildSpellList`'s `expand` local goes with it.

**Do not remove `linkedSpellIDs` from anywhere else.** It is load-bearing in
three places that must keep working: `ResolveAura`, the `linked=N` field in the
state snapshot (which `docs/HANDOFF.md` §1 calls the evidence of which code
actually ran), and `Data.GetCooldownInfoForSpell`. You are changing what the
*picker offers*, nothing else.

Check whether `Data.PickerSpellIDFor` or any other caller depends on the
expansion before you delete it. If something does, stop and report rather than
working around it.

Replace the old comment with one saying why the expansion was removed — that the
intent was real, that it was tested, and that one item frame per `cooldownID` is
the reason it cannot work. That comment is the thing stopping someone re-adding
this in a year.

## 3. Tests

- A category whose entries carry `linkedSpellIDs` yields **one** row per entry,
  not one per linked ID. Build the stub so an entry has two or more linked IDs
  and assert the count and that the base ID is the one kept.
- The `all` source likewise does not gain linked IDs.
- `essential`, `utility` and `spellbook` are unaffected.
- **A regression guard for the thing that must not break:** an `aura`-mode icon
  placed on the base spell still resolves a linked buff through `ResolveAura`,
  and still reports its linked count. If a case already covers this, say so and
  do not duplicate it.

Confirm your new cases fail before the change and pass after. Quote the failure
text.

**Do not delete or rewrite an existing case.** If one must change — and the
existing picker tests may well assert the old expanded counts — leave it alone
and put the before/after under **"Existing tests I believe need to change"** in
your report. That is expected here and is not a failure.

## 4. Gate

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Paste the tail. Any failure is one you caused.

## 5. Report

Include a **Proposed docs changes** entry for `docs/DECISIONS.md` recording that
per-outcome buff tracking was attempted, tested in game, and is impossible
because adoption is one frame per `cooldownID`. Write it as you would want it to
land; the coordinator merges it.

You cannot launch the game. Whether the picker now reads better is the player's
call, not yours.
