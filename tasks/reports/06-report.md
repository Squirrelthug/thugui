# 06 — An adopted cell must collapse when the buff is down — report

**Status:** complete

## What I changed

`CV:UpdateState`'s adopted branch no longer sets `show = true` unconditionally.
It now calls a new file-local `AdoptedCellWanted(icon, item)` in `Core.lua`,
which asks three sources in the order the task specified: Blizzard's item frame
first (via a new `BB:ItemIsShown`, which returns `true` / `false` / `nil` for
"cannot tell"), our own `ResolveAura` second but only out of combat, and
otherwise reserves the cell. `BB:ItemIsShown` reads the item with `pcall` and
screens the result with `issecretvalue`, declining to trust the value when no
screening function exists. `BB:Apply` now logs, once per session per combat
state, whether that shown state came back readable — the measurement that says
whether accurate in-combat collapse is reachable at all. The adopted branch is
still first, ahead of `IsSpellAvailable`, and the existing comment block was
extended rather than replaced.

## Files touched

| File | What |
|---|---|
| `modules/CooldownViewer/BlizzBuffs.lua` | New `BB:ItemIsShown`; new file-local `InCombat()` and `SpellLabel()`; the `blizzbuffs-shown-readable-<combat>` measurement in `BB:Apply` |
| `modules/CooldownViewer/Core.lua` | New file-local `AdoptedCellWanted` after `ResolveAura`; `show = AdoptedCellWanted(icon, adopted)` in `CV:UpdateState`; comment block extended |
| `Tests/loadtest.lua` | Stub buff item now defaults to shown, plus an `ItemShown(true/false/"secret")` driver; seven new cases |
| `tasks/reports/06-report.md` | This report |

Nothing under `docs/` was touched. No git state-changing command was run; the
work is uncommitted in the working tree (`git status` shows only the three
source files plus the untracked task file).

## Verification

```
$ luac -p modules/CooldownViewer/Core.lua modules/CooldownViewer/BlizzBuffs.lua Tests/loadtest.lua
SYNTAX_OK
```

(`luac -p` printed nothing, which is its success case; `SYNTAX_OK` is my own
echo on exit 0.)

```
$ lua Tests/loadtest.lua .

-- blizzard buff items --
ok         an aura icon is adopted by its Blizzard item
ok         the item is anchored over the cell
ok         our own art is suppressed but the cell is kept
ok         nothing is written onto Blizzard's frames
ok         our icon is lowered, their viewer is left alone
ok         a hidden grid hands the buffs back
ok         switching it off restores the aura path
ok         an unmatched spell logs no item frame stage once
ok         an adopted icon is shown even when its spell name does not resolve
ok         an adopted cell keeps its slot under columns collapse
ok         an item Blizzard is showing keeps its cell, aura or no aura
ok         an item Blizzard has hidden gives up its cell, even in combat
ok         an unreadable shown state reserves the cell in combat
ok         out of combat an unreadable item falls back to our aura lookup
ok         out of combat with the buff down and the item unreadable, the cell goes
ok         the column actually closes when the buff is down
ok         no issecretvalue at all degrades safely
ok         an unmatched spell is left to the aura path
ok         a non-adopted icon whose spell does not resolve is still hidden
ok         an Apply error is logged and applying flag is cleared
ok         restore

-- combo pips --
...
-- secret probe --
ok         records a sample with readable values
ok         a secret power value is described, not read
ok         a secret aura struct does not throw
ok         a missing API is reported, not fatal
ok         a thin sample never buries a rich one

0 failure(s)
```

Exit code 0. Task 05's three cases ("an adopted icon is shown even when its
spell name does not resolve", "an adopted cell keeps its slot under columns
collapse", "an unmatched spell is left to the aura path") are still listed and
still passing, **unchanged** — the default-shown stub is what keeps them so.

## Tests added

Seven cases, all in the `-- blizzard buff items --` block, plus one change to
the shared stub (`item.__shown = true` by default, and an `ItemShown` helper
that drives `true`, `false`, or `"secret"`):

| Case | Covers |
|---|---|
| an item Blizzard is showing keeps its cell, aura or no aura | source 1 wins: shown, no aura, in combat → wanted |
| an item Blizzard has hidden gives up its cell, even in combat | source 1 wins the other way: hidden, in combat → not wanted |
| an unreadable shown state reserves the cell in combat | source 3, the safety property |
| out of combat an unreadable item falls back to our aura lookup | source 2, buff up (via linked spell 9003) → wanted |
| out of combat with the buff down and the item unreadable, the cell goes | source 2, buff down → not wanted |
| the column actually closes when the buff is down | the player's complaint. `collapse = "columns"`, three cells in column 1; asserts the **neighbour's** y moves from slot 3 to slot 2 when the adopted cell is released |
| no issecretvalue at all degrades safely | `issecretvalue` removed: nothing throws, and the cell is not reserved out of combat with no buff |

### Confirming they fail on the old code

I temporarily reverted only the one line (`show = AdoptedCellWanted(icon,
adopted)` back to `show = true`), ran the harness, then restored it and
re-verified 0 failures. Four of the seven fail on the old code — the task
predicted two, and the two it meant are the last of these:

```
STEP FAIL  an item Blizzard has hidden gives up its cell, even in combat
           Tests/loadtest.lua:1734: a cell whose Blizzard item is hidden was still wanted
STEP FAIL  out of combat with the buff down and the item unreadable, the cell goes
           Tests/loadtest.lua:1770: an adopted cell was reserved with the buff down, out of combat
STEP FAIL  the column actually closes when the buff is down
           Tests/loadtest.lua:1820: the adopted cell held its slot with the buff down
STEP FAIL  no issecretvalue at all degrades safely
           Tests/loadtest.lua:1845: a client with no secret screening still reserved the cell

4 failure(s)
```

The other three ("item shown keeps its cell", "unreadable reserves in combat",
"unreadable out of combat with the buff up") pass either way by construction —
they assert `wanted`, which the old code always produced. They are kept because
they pin the *authority order* rather than the bug: without them, a later change
that made rule 1 or rule 3 stop reserving would go unnoticed.

## Existing tests I believe need to change

None. Every existing case is untouched; the only edit inside the shared setup is
the added `item.__shown = true` default and the new `ItemShown` helper, which is
what the task specified so task 05's cases keep passing unchanged.

## Sources used

- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua`, branch `live`,
  via `gh api repos/Gethe/wow-ui-source/contents/...`. Confirms the chain the
  task cites: `CooldownViewerItemMixin:UpdateShownState` (line 337) calls
  `self:SetShown(self:ShouldBeShown())`, and `CooldownViewerBuffItemMixin:IsExpired`
  (line 1167) is `auraData.expirationTime <= GetTime()`. `ShouldBeActive` for a
  buff item (line ~1185) is built on `IsExpired`, and `SetIsActive` /
  `OnActiveStateChanged` feed it straight back into `UpdateShownState`.
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml`, branch `live`.
  `CooldownViewerBuffIconItemTemplate` and `CooldownViewerBuffBarItemTemplate`
  both set `allowHideWhenInactive = true`. Relevant — see the finding below.
- `docs/DECISIONS.md` §5, §13, §15; `docs/HANDOFF.md` §3b.

### One finding from that source that changes what the player will see

`ShouldBeShown` (CooldownViewer.lua:311) reads:

```lua
if self:GetCooldownID() then
    if not self.allowHideWhenInactive then return true end
    if not self.hideWhenInactive then return true end
    if self:IsActive() then return true end
    if CooldownViewerSettings:IsVisible() then return true end
end
```

`allowHideWhenInactive` is `true` on both buff item templates, so that first
gate passes. But `hideWhenInactive` is a **per-viewer setting the player owns**
(`CooldownViewerMixin:SetHideWhenInactive`, line 1754, pushed down to every item
frame) — the Edit Mode "Hide When Inactive" option on the buff viewer.

So: **if the player has "Hide When Inactive" switched off for the buff viewer,
Blizzard's item is shown whether the buff is up or not, `ItemIsShown()` returns
`true`, and the cell stays reserved exactly as it does today — the column still
will not close.** The fix is correct as specified either way (rule 1 is really
"is Blizzard drawing this item", which is the right question for "must our icon
hold the slot", since their frame is anchored to ours), but the player-visible
outcome depends on a Blizzard setting we do not control and did not ask about.
The same setting also decides whether the item is *visible but inactive* in the
cell out of combat. I did not build anything for this — it is outside the task —
but the coordinator should know before telling the player it is fixed.

There is a second, smaller consequence: `CooldownViewerSettings:IsVisible()`
forces every item shown while the Cooldown Manager settings window is open, so
adopted cells will all be reserved while the player is editing that panel. That
is harmless and self-correcting.

## Proposed docs changes

**`docs/DECISIONS.md` §13 — replace the subsection "The cost, stated plainly"
with the following** (the old text asserts the cell is always reserved, which is
no longer true):

> ### The cost, and how much of it we bought back
>
> The cell used to be **always** reserved, buff up or not, because we cannot ask
> whether the buff is up. That belief is right *in combat* and wrong *out of
> it*, and with collapse on the player's column never closed even at rest.
>
> `CV:UpdateState` now decides with three sources, in descending order of
> authority. The order is the design:
>
> 1. **Blizzard's item frame** (`BB:ItemIsShown`). Their untainted code hides
>    the item when the buff drops, so its shown state is the answer — when we
>    are allowed to read it. It returns `true`, `false`, or **`nil` for "cannot
>    tell"**; three states, because "hidden" and "unknown" need opposite
>    handling and a boolean would merge them.
> 2. **Our own `ResolveAura`.** Truthful out of combat, blind during it
>    (`RequiresNonSecretAura`), so it only gets a say when it can see.
> 3. **Reserve the cell.**
>
> Step 3 is a safety property, not a fallback of convenience. Collapsing a cell
> whose buff is actually up leaves Blizzard's item anchored to our now-hidden
> icon, drawing at a stale coordinate on top of a neighbour. Reserving when
> unsure is the difference between a gap nobody wanted and a broken UI.
>
> **What rule 1 actually answers is "is Blizzard drawing this item", not "is the
> buff up", and those differ.** `CooldownViewerItemMixin:ShouldBeShown`
> (`Blizzard_CooldownViewer/CooldownViewer.lua`, branch `live`) returns `true`
> early unless the viewer's own **Hide When Inactive** setting is on. Both buff
> item templates set `allowHideWhenInactive = true` in `CooldownViewer.xml`, so
> the gate is available — but `hideWhenInactive` is the player's Edit Mode
> choice. With it off, the item is on screen permanently, `ItemIsShown()` says
> `true`, and the cell is reserved forever exactly as before. That is correct
> behaviour (their frame is anchored to ours and must keep its slot), but it
> means **the column only closes if the player has Hide When Inactive enabled on
> the buff viewer.** Their settings window being open forces the same thing
> temporarily, via `CooldownViewerSettings:IsVisible()`.
>
> Whether `IsShown()` survives combat as a plain boolean is **unmeasured**. It
> descends from `IsExpired`, which compares `auraData.expirationTime <=
> GetTime()`, and `expirationTime` is secret in combat — and secrecy has been
> measured propagating through operations here (§12). `BB:Apply` now logs
> `blizzbuffs-shown-readable-<combat>` once per session per combat state, with
> combat in the *key* so an out-of-combat line cannot suppress the in-combat one.
> If it comes back readable in combat, accurate mid-fight collapse is reachable
> and rule 1 already delivers it with no further change. If not, rule 3 holds the
> slot and behaviour in combat is what it is today.

**`docs/HANDOFF.md` §2, new row:**

> | Adopted cell collapses when the buff is down | **Unverified in game** — three-source decision in `CV:UpdateState` / `BB:ItemIsShown`. Harness proves the column closes and the neighbour packs into the freed slot. Whether the player sees it depends on Blizzard's **Hide When Inactive** setting for the buff viewer — see `DECISIONS.md` §13 |

**`docs/HANDOFF.md` §1, add a row to the `CVBUFF:` table:**

> | `spell X: item IsShown readable = true/false (combat=…)` / `… unreadable …` | The measurement behind adopted-cell collapse. One line per combat state per session. `unreadable` in combat means the cell must stay reserved mid-fight; `readable` means accurate in-combat collapse is already happening |

**`docs/HANDOFF.md` §3b**, the paragraph beginning "The remaining cost:" — the
clause "an adopted cell is now always reserved, buff up or not" is now wrong and
should point at `DECISIONS.md` §13 instead.

## Could not do

Nothing was blocked. Two small deviations from the task text, both flagged
rather than improvised:

1. **§2c says the combat state is "already in hand" in `BB:Apply`. It is not** —
   `BlizzBuffs.lua` had no combat helper and does not compute one. I added a
   file-local `InCombat()` mirroring the identical helper in `Core.lua` (ER
   first, `InCombatLockdown() or UnitAffectingCombat("player")` as fallback),
   rather than exporting `Core.lua`'s file-local one, so both halves of the
   addon agree about what "in combat" means. Say the word if you would rather it
   were promoted to a shared helper.
2. **§2b asks me to check `CV.BlizzBuffs` against `self.BlizzBuffs`.**
   `CV.BlizzBuffs` is correct: `Core.lua` line 20 is `local CV =
   ThugUI.CooldownViewer`, and `BlizzBuffs.lua` assigns `CV.BlizzBuffs = BB` on
   that same table. The file-local form works as written; nothing was passed in
   or moved.

I also extracted a two-line `SpellLabel(icon)` file-local in `BlizzBuffs.lua`
and used it in both the new log line and the existing `spellStr` local, rather
than duplicating the format string. Behaviour is byte-identical; if you would
rather see zero churn on the existing lines, revert that hunk and inline it.

## Noticed but did not touch

- **`BB:Apply` is where the measurement lives, but `Apply` runs on every layout
  pass while `UpdateState` runs on a 0.15s timer.** They can disagree by a frame
  about combat state. Harmless for a once-per-session diagnostic, but the number
  in the log is the state at the last *adoption* pass, not at the decision.
- **`icon.loggedShown` in `ApplyLayout`'s `Commit()` will now produce real
  transition lines for adopted cells**, where before an adopted cell was
  permanently `wanted` and so logged exactly once. That is more log volume during
  a fight (a handful of lines, as its comment predicts) and is arguably a feature
  — it is now recording the collapse decision. Not changed.
- **`ThugUI_Config.cvUseBlizzardBuffs` has no bearing on `ItemIsShown`**, which
  is fine because `AdoptedCellWanted` is only reached when an item was adopted,
  and adoption is already gated on the switch.
- `docs/HANDOFF.md` §3b's "the remaining cost" sentence and `DECISIONS.md` §13's
  "The cost, stated plainly" are both now factually stale. Drafted above rather
  than edited, per §9.
- The known-and-accepted stale-coordinate frame from the task's §6 is genuinely
  present: `Commit()` still `SetPoint`s a hidden icon and Blizzard's item stays
  anchored to it. I looked for a cheap fix and do not think there is one that
  does not involve writing to their frame — releasing the item on `not wanted`
  would mean re-adopting it on the next pass, and `ReleaseItem` already sets the
  scale and anchor back, so the buff would visibly jump to Edit Mode's position
  and back. Left alone.

## Not verified

Everything below needs a running client. Nothing here is confirmed in game.

- That Blizzard's `IsShown()` is readable — or secret — for a buff item during
  combat on 12.0.7. This is the whole point of the new log line and it is
  **unmeasured**. Both answers are handled in code, but which one the client
  gives is unknown.
- That the player's column actually closes on screen. The harness proves the
  layout maths and the neighbour's new anchor; it cannot see a pixel.
- That the adopted buff still draws in its cell, in combat, with its radial
  timer and its stacks. The tests assert the item is adopted and anchored, not
  that it renders. **This is the thing the task warned must not be lost.**
- That the cell being released out of combat does not leave Blizzard's item
  parked somewhere visible. In code it stays anchored to our hidden icon and
  their own `ShouldBeShown` governs its visibility, but that is reasoning, not
  observation.
- Whether the player has **Hide When Inactive** enabled on the buff viewer,
  which per the finding above decides whether any of this is visible to them.
  Worth asking before the next reload.
- That the new log line reaches `ThugUI_DebugLog` with a sensible spell label
  for a passive placement like Opportunity (279876), whose `spellName` is nil —
  `SpellLabel` falls back to the bare ID, which is exercised in code but not in
  game.
- Combat state agreement between `ER:IsInCombat()` and the new `InCombat()` in
  `BlizzBuffs.lua` during the `PLAYER_REGEN_*` window, where `InCombatLockdown()`
  is known not to have flipped yet.
