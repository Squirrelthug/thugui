# Task 15 — A spent charge spell hides itself, in combat, without adoption

Read `00-AGENT-BRIEF.md` first.

Take charge spells back from Blizzard's frame and hide them ourselves when every
charge is spent — including during combat, where the charge count is a secret
value.

## Background, measured on 2026-08-11

`DECISIONS.md` §20, "Measured — one combat, 2026-08-11 21:05". The player ran
`SecretProbe` through a full fight on 12.1. **Do not re-derive any of this and do
not contradict it from documentation; it is measurement.**

| | |
|---|---|
| `charges.current` (Swiftmend) | **SECRET** at all four combat sample points, `2` idle |
| `charges.max` | **readable** — `2` mid-fight |
| `cd.isActive` | readable |
| `SetShown(secret)` | **REFUSED** |
| `SetAlpha(secret)` | **ACCEPTED**, at every phase including mid-combat |

Alpha clamps to 0–1 and `currentCharges` is a secret number 0, 1 or 2. So

```lua
icon:SetAlpha(chargeInfo.currentCharges)   -- 0 -> invisible, 1+ -> opaque
```

hides a spent charge spell in combat **with no comparison anywhere**. Nothing is
read and nothing is branched on; the clamp does the work. Comparison is the
operation that errors, and this design's entire value is that it never performs
one.

### Why this replaces adoption

`BB:ShouldAdopt` currently ends `return self:IsChargeSpell(icon)`
(`BlizzBuffs.lua:218`). Multi-charge spells were handed to Blizzard's item
because `IsSpellReady` fails open when charges are secret — so our icon showed
whether or not a charge was banked. That was correct given what was knowable at
the time. The measurement changed what is knowable.

The player reported the two symptoms this fixes: **Grappling Hook (Outlaw)**
disappearing wrongly, and **Maul (Guardian)** drawing with no sweep. This task
addresses the hide behaviour only. **Maul's missing sweep is a different unlock**
(`SetCooldownFromDurationObject`, also measured accepted) and is **not** in
scope — do not attempt it.

### The cost, which is accepted and must not be worked around

**Alpha zero is not hidden.** The frame keeps its cell, so a column holding a
spent charge spell will not collapse around it during combat.

That is deliberate and the player has been told. `ApplyLayout` collapses on
`if icon.wanted then` (`Core.lua:778`, `:800`) — a plain Lua truth test. Making
the cell collapse would require knowing the spell is spent, which is a branch on
a secret. **Do not attempt to make the cell collapse. Do not set `icon.wanted`
from anything secret-derived.** If you find yourself wanting to, stop and report.

Out of combat nothing is secret, so `SetShown` and collapse keep working exactly
as they do today. The gap is combat-only.

## Change 1 — stop adopting charge spells

In `BB:ShouldAdopt`, the fallthrough `return self:IsChargeSpell(icon)` becomes
`return false`. Charge spells in `cooldown` and `proc` mode are ours to draw.

**Do not touch the existing branches** — `aura` and `always` still adopt, `proc`
and `recharging` still refuse. Only the final line changes.

Update the function's comment block: its third bullet ("a multi-charge spell")
documents a rule that is being removed, and the "two exclusions" list is about to
be wrong about why. The comment explains *why* each case is what it is and that
is the part that has to stay true.

**`BB:IsChargeSpell` will have no callers left.** Leave it defined and say so in
your report — whether it goes is the coordinator's call, not yours. Do not delete
it and do not delete its comment.

**One existing test case's premise dies.** Task 14 added *"BB:ShouldAdopt refuses
recharging even for a charge spell"*, which was meaningful because the
fallthrough would otherwise have adopted it. After this change every non-`aura`,
non-`always` mode is refused, so it can no longer fail for the reason it was
written to catch. **Leave that case exactly as it is** — it still asserts
something true — and state plainly in your report that its premise changed.
Do not rewrite it, do not delete it, do not repurpose it. An agent on an earlier
task rewrote a case in place and reported it as an addition; that is the single
thing the coordinator checks hardest.

## Change 2 — `IsSpellReady` hands back an alpha

`IsSpellReady` (`Core.lua:106`) currently returns `ready, charges`. Add a **third
return: a value that is always safe to pass straight to `SetAlpha`.**

- **`1` in every case** — not a charge spell, charges readable, no charge info at
  all, every fallthrough.
- **the secret `currentCharges`** on exactly one path: the fail-open branch at
  `Core.lua:122–125`, where the value was found unreadable.

**It must never be nil.** This is the whole point of the design. If the caller
has to test the third return before using it, that test is either a comparison
against a secret (which errors) or it needs a fourth boolean return, and both are
worse than making one function always answer. All secret handling stays inside
`IsSpellReady`, whose comment block already exists to document exactly that.

Keep the existing two returns' behaviour identical. The readable path
(`return current > 0, current`) keeps reporting the count for the `count`
fontstring; it returns alpha `1`, because `SetShown` has already done the work
there and an icon that is shown must be fully opaque.

Do not compare, test or perform arithmetic on `currentCharges` anywhere. Do not
add a nil test to a value that came from the game — `Readable()` exists, it asks
`issecretvalue` **first** and tests nil second, and that ordering is the thing
this file has been caught by before.

## Change 3 — apply it, in two modes only

In `CV:UpdateState`'s per-icon loop, spell path (`Core.lua:971` onward):

- **`cooldown` mode** — apply the alpha. This is the reported bug.
- **`proc` mode** — apply it too. `show = ready and procced`, and `ready` fails
  open for secret charges exactly as `cooldown` does, so a procced charge spell
  with nothing banked is visible today and should not be. Same rule, same
  source, one line.
- **`always` mode** — no. Still adopted, so we draw nothing there.
- **`recharging` mode** — **no, and this one is not an oversight.** It wants the
  inverse, and the inverse of a secret 0/1/2 needs `1 - currentCharges`, which is
  arithmetic on a secret and is refused. A charge spell in `recharging` mode
  keeps today's fail-open behaviour. Note it in your report; do not try to solve
  it.
- **Item path** — untouched. Items carry no charges through it and nothing there
  is secret.

### The pooling hazard, which is the likely regression

Icons are pooled. An icon left at alpha 0 by one spell will carry it to whatever
spell reuses the frame, and the symptom is an invisible icon that every other
piece of state says is fine — hard to diagnose and it will not reproduce out of
combat.

**Reset alpha to 1 once per icon per pass, at the top of the loop, next to the
other per-icon resets — not in the branches.** Then the two modes above override
it. A branch that forgets to reset is exactly the bug shape `Core.lua:945–970`
already carries a comment about, where a pooled icon kept the previous
occupant's sweep and stack count.

Set alpha on **`icon`** (the frame), so the texture, the count text, the cooldown
and any border go together. `icon.tex:SetAlpha` is a different mechanism used by
the adopted-cell path at `Core.lua:882`; leave that alone.

**Check where the proc glow is parented.** `SetGlow(icon, …)` runs at
`Core.lua:1010` on an icon that may now be at alpha 0. If the glow frame is a
child of `icon` it inherits the alpha and is correctly invisible; if it is
parented anywhere else, a spent charge spell will show a glow floating over an
invisible icon. Find out which, state it in your report, and fix it only if it is
the second — with the smallest change that works.

## Verify

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Baseline is **189 passing, 0 failures**. It must not go down.

Add cases covering:

1. A multi-charge spell in `cooldown` mode is **not** adopted — the behaviour
   change. Assert `BB:ShouldAdopt` is false where it is true today.
2. Charges readable and zero: icon hidden by `SetShown`, alpha `1`.
3. Charges readable and non-zero: icon shown, alpha `1`.
4. **Charges secret: icon shown — space reserved — and alpha is the secret
   value.** The load-bearing case.
5. **Pooling:** an icon that took the secret-charge alpha, then re-driven as an
   ordinary non-charge spell, is back at alpha `1`.
6. `recharging` mode does not apply the alpha, even for a charge spell.
7. A spell with no charge mechanic never has its alpha changed from `1`.

**The harness stub is a hazard and this task depends on it being honest.**
`DECISIONS.md` §19 records that `loadtest.lua`'s `SetCooldown` accepted secrets
where the real client refuses them, so no test could have caught a real bug.
Before you trust case 4, **confirm the stub's secret model actually errors when
compared** — if it does not, a comparison bug in your own code passes silently
and the failure appears only in the game. Report what you found either way, and
if you have to strengthen the stub, say so explicitly and check nothing else
depended on the weaker behaviour.

**Add cases. Never rewrite an existing one in place.** The coordinator diffs the
`ok` lines against a stashed clean tree. Before claiming a test proves anything,
run it against the **unmodified** files and confirm it fails. State the exact
failing assertion in your report.

Reset shared `_G.__*` stub state at the **start** of every case, not only at the
end — task 14 found that a case which throws unwinds past its own cleanup and
leaves the next case passing for the wrong reason.

## Boundaries

- Do not touch `modules/SecretProbe.lua`. Its extension is task 16.
- Do not implement the in-combat sweep (`SetCooldownFromDurationObject`). Not
  this task, however tempting the same measurement makes it.
- Do not make the collapse work for alpha-hidden cells. See above.
- Do not change `BB:ShouldAdopt`'s existing branches; only the final line.
- Do not edit anything in `docs/`. Draft proposed entries into your report.
- Do not run any state-changing git command. Leave the work uncommitted on
  branch `charge-spells-can-hide`.

## Report

Write `tasks/reports/15-charge-spells-hide-when-spent.md`. **No report file means
the task did not happen.**

Include the diff in prose, the before/after test output with the exact assertion
that failed against the unmodified code, what you found about the stub's secret
model, where the glow is parented, and **anything in this task file that turned
out to be wrong** — three previous agents found errors in their task files and in
each case it was the most useful thing in the report.
