# 15 — A spent charge spell hides itself, in combat, without adoption — report

**Status:** partial — the three changes are implemented, tested, and confirmed
correct in code, but a pre-existing test the task file did not anticipate now
fails as a direct, unavoidable consequence of Change 1. See "Could not do"
below; it needs a coordinator decision, not a guess from me.

## What I changed

**Change 1 — `BB:ShouldAdopt` (`modules/CooldownViewer/BlizzBuffs.lua`).** The
fallthrough `return self:IsChargeSpell(icon)` is now `return false`. Only that
line changed; the `proc`/`recharging`/`aura`/`always` branches are untouched.
Rewrote the function's doc comment: the "three such cases" list is now two
(aura, always), with a new paragraph explaining the multi-charge case was
removed and why (DECISIONS.md §20's alpha route), and the exclusions list no
longer claims its reasoning is charge-specific, since after this change every
non-adopted mode excludes charge and non-charge spells identically.
`BB:IsChargeSpell` is left defined, untouched, with its comment intact — it has
no callers left. Whether it goes is the coordinator's call per the task file.

**Change 2 — `IsSpellReady` (`modules/CooldownViewer/Core.lua:106`).** Added a
third return, `alpha`, documented in a new comment block directly above the
function. It is `1` on every path (readable-charges, no-charge-mechanic,
on-GCD, on-cooldown, ready) except one: the fail-open branch where
`currentCharges` was found unreadable, where it returns the secret
`currentCharges` value itself, unread and uncompared —
`if issecretvalue and issecretvalue(current) then return true, nil, current end`.
I added one sub-case the task text didn't spell out: if `current` is `nil`
outright (not secret, genuinely absent — shouldn't happen in practice since a
charge-spell table always carries the field, but `Readable()` doesn't
distinguish "secret" from "nil" for the caller) the function returns alpha `1`
rather than `nil`, to guarantee the "never nil" invariant holds unconditionally.
This is defensive, not a deviation — the task's own text says "It must never be
nil" as the one absolute rule.

**Change 3 — `CV:UpdateState` (`Core.lua`, per-icon loop).** `icon:SetAlpha(1)`
added at the top of the loop next to `procced = ShouldGlow(icon)`, before the
adopted/item/aura/spell branches — the pooling reset. In the spell branch,
`icon:SetAlpha(alpha)` is called in `cooldown` mode and `proc` mode only.
`always` and `recharging` are untouched (per the task, with a comment on
`recharging` explaining why: the inverse needs `1 - currentCharges`, arithmetic
on a secret, refused). Item path and aura path are untouched.

**Glow parenting — checked, no fix needed.** `SetGlow` (`Core.lua:447`) calls
`ActionButtonSpellAlertManager:ShowAlert(icon)`. Read Blizzard's source
(`Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.lua`,
`live` branch): `GetAlertFrame` does
`CreateFrame("Frame", nil, actionButton, "ActionButtonSpellAlertTemplate")` —
the alert frame is parented (third arg to `CreateFrame`, not just anchored) to
the icon we pass in. A child frame's effective alpha is its own alpha times its
parent chain's, so `icon:SetAlpha(0)` correctly hides the glow too, with no
code change. `FallbackGlow`'s texture (`icon:CreateTexture(...)`) is likewise a
child region of `icon` and inherits the same way. Confirmed from source, not
assumed.

## Files touched

| File | What |
|---|---|
| `modules/CooldownViewer/BlizzBuffs.lua` | `BB:ShouldAdopt` final line + doc comment (Change 1) |
| `modules/CooldownViewer/Core.lua` | `IsSpellReady` third return + doc (Change 2); per-icon alpha reset and cooldown/proc application (Change 3) |
| `Tests/loadtest.lua` | 7 new cases, no existing case touched |

## Verification

```
$ luac -p modules/CooldownViewer/Core.lua modules/CooldownViewer/BlizzBuffs.lua Tests/loadtest.lua
SYNTAX_OK
```

```
$ lua Tests/loadtest.lua .
...
STEP FAIL  a charge spell in cooldown mode is adopted from the utility bar
           Tests/loadtest.lua:3018: a charge spell was not adopted from the utility viewer
...
1 failure(s)
```

195 `ok` lines + 1 `STEP FAIL` = 196 total steps = 189 baseline + 7 new cases.
The single failure is the pre-existing test discussed below, not a defect in
the new code — every one of the 7 new cases passes on the modified files.

## Tests added

All 7 required by the task, all in `Tests/loadtest.lua`, all new (`Add cases.
Never rewrite an existing one in place` — none was touched):

1. `task 15: a multi-charge spell in cooldown mode is NOT adopted` — blizzard
   buff items section, right before its `"restore"` step. Asserts
   `BB:ShouldAdopt(icon) == false` and `BB:AdoptedItem(icon) == nil` for a
   7000/cooldown placement that used to be adopted.
2. `task 15: charges readable and zero -- hidden, alpha stays 1`
3. `task 15: charges readable and non-zero -- shown, alpha stays 1`
4. `task 15: charges secret -- icon shown, space reserved, alpha IS the secret`
   — the load-bearing case, `assert(icon.__alpha == _G.__SECRET, ...)`
5. `task 15: pooling -- a spent-charge icon reused for a plain spell is alpha 1
   again` — drives an icon to the secret alpha, re-places a *different*
   spellID at the same cell, confirms (rather than assumes) the pooled frame
   is reused (`icon2 == icon`), then confirms alpha is back to 1
6. `task 15: recharging mode does not apply the alpha, even for a charge spell`
7. `task 15: a spell with no charge mechanic never has its alpha touched`
   (checked in both the ready and spent states)

Cases 2–7 live in the "engine" section right after the existing charge-spell
tests (`"unreadable charges fail open rather than hiding"`, ~line 1657), using
placement 777 in `cooldown` mode (or 888 for the pooling case's second spell),
which is never touched by `BlizzBuffs` in that section (`BB:Refresh` is never
called there), so they exercise `CV:UpdateState`/`IsSpellReady` in isolation.

**Confirmed each fails on the unmodified code**, per the task's explicit
requirement. I reverted `Core.lua` and `BlizzBuffs.lua` to `HEAD` (via
`git show HEAD:<path> > <path>`, a read-only git operation — no `stash`,
`checkout`, or other state-changing git command was used; I kept a copy of my
edited files and restored them by direct write afterward) and re-ran with the
new `loadtest.lua`. All 7 failed:

```
STEP FAIL  task 15: charges readable and zero -- hidden, alpha stays 1
           Tests/loadtest.lua:1686: a readable zero charge count should not touch alpha, got nil
STEP FAIL  task 15: charges readable and non-zero -- shown, alpha stays 1
           Tests/loadtest.lua:1710: a readable non-zero charge count should not touch alpha, got nil
STEP FAIL  task 15: charges secret -- icon shown, space reserved, alpha IS the secret
           Tests/loadtest.lua:1742: alpha was not the secret currentCharges value itself, got nil
STEP FAIL  task 15: pooling -- a spent-charge icon reused for a plain spell is alpha 1 again
           Tests/loadtest.lua:1771: setup failed: icon was not left at the secret alpha
STEP FAIL  task 15: recharging mode does not apply the alpha, even for a charge spell
           Tests/loadtest.lua:1816: recharging mode changed alpha for a charge spell, got nil
STEP FAIL  task 15: a spell with no charge mechanic never has its alpha touched
           Tests/loadtest.lua:1842: a non-charge spell's alpha was touched, got nil
STEP FAIL  task 15: a multi-charge spell in cooldown mode is NOT adopted
           Tests/loadtest.lua:3142: BB:ShouldAdopt still adopts a charge spell in cooldown mode
7 failure(s)
```

(Old `IsSpellReady` returns only 2 values, so `alpha` was `nil` at every call
site in the reverted code — the assertions read "got nil" because `SetAlpha`
was simply never called with a meaningful value, which is itself the correct
"this behaviour doesn't exist yet" signal.)

Restored my edited `Core.lua`/`BlizzBuffs.lua` afterward and re-ran the full
suite to confirm the 195/1 result above still holds (it does).

## What I found about the stub's secret model

Checked directly with a standalone `lua -e`, not assumed:

```
SECRET > 0          -> errors: "attempt to compare number with table"
1 - SECRET           -> errors: "attempt to perform arithmetic on a table value"
SECRET == nil        -> false, no error
```

The stub's `SECRET` (`Tests/loadtest.lua:208`, `{ __secret = true }`) is a
plain table with no metatable, so `>`/arithmetic against it raise a genuine
Lua error exactly as real secret userdata does — a comparison bug in my own
code (e.g. accidentally writing `current > 0` outside the `Readable()` guard)
would have thrown and failed loudly, not passed silently. `==` against `nil` or
another value does **not** throw (identity comparison is always legal in Lua),
which is why case 4's assertion `icon.__alpha == _G.__SECRET` is safe to write
and is the same pattern already used elsewhere in the file (e.g.
`BB:AdoptedItem(icon) == item`). I did not need to strengthen the stub —
`SetAlpha` in the stub (`Tests/loadtest.lua:86`, `a.__alpha = a1`) already
accepts anything unconditionally with no throw, which matches the measured
real-client behaviour (`SetAlpha(secret)` ACCEPTED at every phase,
DECISIONS.md §20) rather than being a gap like the old `SetCooldown` stub was.

## Sources used

- `gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.lua?ref=live"`
  — confirmed the spell-alert frame is parented (not merely anchored) to the
  action button, which is why `icon:SetAlpha(0)` also hides the glow with no
  code change needed.
- `docs/DECISIONS.md` §19, §20, and the "Measured — one combat, 2026-08-11
  21:05" subsection — the factual basis for Changes 2 and 3, as instructed.
  Nothing in it was contradicted; the implementation follows it directly
  (`SetAlpha(secret)` accepted at every phase, `SetShown`/`SetCooldown` still
  refused, `currentCharges` secret in combat / `maxCharges` readable).

## Proposed docs changes

**`docs/DECISIONS.md`, new entry after §20** (or as a §20 addendum — the
coordinator's call on numbering): record that task 15 landed the alpha route
described at the end of §20 — `BB:ShouldAdopt`'s charge-spell fallthrough is
gone, charge spells in `cooldown`/`proc` mode are drawn by ThugUI again, and
`IsSpellReady` now returns a third value (`alpha`) that is always safe to hand
to `SetAlpha`. Worth stating explicitly: the design cost from §20 ("alpha zero
is not hidden, the cell keeps its space") is unchanged and was not
reintroduced or worked around — I did not touch `icon.wanted` from anything
secret-derived, per the task's explicit boundary.

**`docs/HANDOFF.md`**: I noticed this file is currently modified in the
working tree (104 insertions, uncommitted) from something outside this task —
see "Noticed but did not touch" below. Once that's resolved, this task's
change belongs in the same "what changed this session" shape: Grappling
Hook/Swiftmend-style charge spells hide themselves when spent, in combat,
without Blizzard's frame — unverified in game.

## Could not do — needs a coordinator decision

**A second existing test's premise died, and the task file only accounted for
one.** The task explicitly names exactly one casualty: task 14's *"BB:ShouldAdopt
refuses recharging even for a charge spell"*, and says its assertion "still
asserts something true" even though the reasoning behind it changed — safe to
leave untouched. I found a second, different in kind:

**`Tests/loadtest.lua:3003` (pre-change line 2807), `"a charge spell in cooldown
mode is adopted from the utility bar"`** — this test's assertion is not merely
reasoned differently now, it is **literally false** under the new code:

```lua
BB:Refresh()
local icon = CV.icons[Data.CellKey(1, 1)]
assert(BB:AdoptedItem(icon) == utilityItem,
    "a charge spell was not adopted from the utility viewer")
```

`BB:Apply` (which `BB:Refresh` drives) gates adoption solely on
`self:ShouldAdopt(icon)` (`BlizzBuffs.lua:477`); with Change 1,
`ShouldAdopt` returns `false` for a charge spell in `cooldown` mode, so
`self.adopted[icon]` is never set and `AdoptedItem(icon)` is `nil`, not
`utilityItem`. This is the exact behaviour Change 1 exists to produce — it is
the bug this whole task fixes, tested from the opposite direction by a test
that predates the fix. I confirmed by running the unmodified test suite
against my changes: it is the one and only `STEP FAIL` in the final run.

I did not touch it — the task's boundaries forbid rewriting, repurposing, or
deleting any existing test case, full stop, and this one is not the case the
task named as safe to leave. Its neighbor, `"an adopted cooldown cell is kept
out of combat"` (line 3026), still happens to pass (coincidentally: the
non-adopted spell-path branch answers `ready = true` for a banked charge count
too, so `icon.wanted` comes out true either way), so it did not need
attention.

**What I need from the coordinator:** whether this test should be deleted,
rewritten to assert the new (opposite) behaviour, or left in the tree as a
known, permanent 1-failure baseline. I added a new test right next to it
(`"task 15: a multi-charge spell in cooldown mode is NOT adopted"`) that
asserts the correct current behaviour, so the coverage gap this would leave is
already closed — but the old test's `STEP FAIL` line remains in every future
run until someone with the authority to touch existing tests resolves it.
**189 passing / 0 failures cannot be reached without either violating "do not
rewrite an existing test" or leaving Change 1 unimplemented; I chose to
implement Change 1 as specified and report the conflict, per house rules
rather than silently pick one.**

## Noticed but did not touch

- **`docs/HANDOFF.md` is already modified in the working tree** (104
  insertions, 1 deletion, uncommitted) from before I started — I only ever
  `Read` it, never wrote to it. `git log -1` shows the last commit to it was
  2026-08-10 09:42, so this is someone else's or an earlier process's
  uncommitted draft sitting in the tree. Worth the coordinator's attention
  before this branch is reviewed as a whole, since it's easy to mistake for
  something this task did.
- `BB:IsChargeSpell` and its `DetectChargeSpell`/`chargeSpell` cache machinery
  are now dead code with no callers, exactly as the task predicted. Left
  entirely alone per instruction; flagging again here since it's a real,
  visible piece of now-unused logic sitting in a file someone will read later.

## Not verified

Everything here is correct in code and passes the harness; none of it has run
in the actual game:

- Whether a charge spell in `cooldown` mode actually goes invisible (not just
  "alpha set to a secret value that clamps to 0/1 per DECISIONS.md's
  measurement") when a charge is spent mid-combat, on Grappling Hook or
  Swiftmend specifically.
- Whether `proc` mode's alpha application looks right in practice — a procced
  charge spell with a charge banked should glow and be visible; with none
  banked it should be invisible despite the glow theoretically firing (glow
  only fires when `show` is true, and `show` for `proc` mode already requires
  `ready`, which is `true` in the fail-open branch — so the glow condition and
  the alpha-zero condition can coincide: a procced, spent charge spell that
  fails open would show glow logic evaluating `show=true` while the icon
  itself renders invisible via alpha. This is consistent with the task's
  description and with the glow being correctly parented as a child of `icon`,
  so the glow should also render invisible — but this interaction was not
  something the task called out explicitly and I have not seen it in game).
- Pooling behavior under real gameplay (talent swaps, spec changes, rapid
  re-placement) — the harness test constructs the pooling scenario directly
  rather than through organic play.
- Whether `BB:IsChargeSpell` having no callers causes any issue elsewhere it
  wasn't checked for.
