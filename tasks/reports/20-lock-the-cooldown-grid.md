# 20 — Lock the cooldown grid, and show its edge when it is unlocked — report

**Status:** complete

## What I changed

Added a per-profile `locked` setting (default `true`) that makes the cooldown
grid's mouse behaviour a real three-state decision instead of a two-state one
that ignored locking entirely. `CV:UpdateVisibility` now computes a single
`draggable` boolean from `followCursor`, `previewMode`, `profile.locked` and
`InCombatLockdown()`, and drives both `EnableMouse` and a new thin teal border
frame (`f.dragBorder`) from that one value, so the grid is either fully inert
(locked) or takes the mouse with a visible edge (unlocked or previewing).
Preview deliberately overrides the lock, because the lock is set from the
settings page and a lock you cannot undo from there is a trap. A "Lock
position" checkbox was added to the Cooldown Viewer page's "This layout" panel,
and the lock state was added to both `/thugcv` and the always-on diagnostics
snapshot so it is visible in a bug report.

## Files touched

| File | What |
|---|---|
| `modules/CooldownViewer/Data.lua` | `DefaultProfile()` gains `locked = true`, next to `point` |
| `modules/CooldownViewer/Core.lua` | `EnsureContainer` builds `f.dragBorder` (a child frame with 4 one-pixel OVERLAY textures, teal, alpha 0.6); `UpdateVisibility` replaces the old `editable`/`EnableMouse` line with the three-state `draggable` logic and drives the border from it; `/thugcv` status dump gets a `locked:` line next to `follow cursor:` |
| `modules/Diagnostics.lua` | `CaptureProfiles` records `locked` beside `followCursor` |
| `ui/pages/CooldownViewer.lua` | New "Lock position" checkbox in the `misc` panel, immediately above "Show proc glow" |
| `Tests/loadtest.lua` | `EnableMouse` recorded on the frame stub; 5 new cases (below); no existing case rewritten |

No file outside this list was touched, and no legacy ECV/BCV/GCV code was
touched.

## Verification

```
$ luac -p modules/CooldownViewer/Data.lua modules/CooldownViewer/Core.lua modules/Diagnostics.lua ui/pages/CooldownViewer.lua Tests/loadtest.lua
(no output — all five files parse clean)
```

```
$ lua Tests/loadtest.lua .
... (247 lines of section output) ...
STEP FAIL  the misc panel drops the Blizzard-buffs checkbox but keeps proc glow
1 failure(s)
```

**Baseline before this task:** 224 passing, 0 failures (confirmed by running
the harness against the clean tree before touching anything, per the task
file's instruction).

**After this task:** 228 passing, 1 failure — the pre-existing case named
above. 224 + 5 new cases = 229 total run; 228 pass. The one failure is
addressed in "Existing case left failing" below, per the task's explicit
instruction not to edit it.

## Tests added

All 5 in `Tests/loadtest.lua`, and I verified every one of them fails against
the **unmodified source** — I temporarily reverted the `Core.lua` and
`Data.lua` edits (by hand, via the same edit tool, not `git stash`, since the
brief prohibits state-changing git commands) back to their pre-task text,
re-ran the suite with the new cases + the `EnableMouse` stub recorder already
in place, recorded the failures below, then restored the fix and re-ran to
confirm 228/1 again.

1. **`task 20 decision 1: locked defaults true, including on an old profile`**
   — asserts `Data.DefaultProfile().locked == true`, then simulates a profile
   saved before this task (`{ placements = {} }`, no `locked` key at all) and
   asserts `Data.GetProfile` backfills `locked == true`.
   Pre-fix: **fails** — `Tests/loadtest.lua:709: the default profile is not
   locked by default` (the key does not exist pre-fix, so it reads `nil`).

2. **`task 20: a locked grid takes no mouse and shows no border`** — the
   reported bug. Sets `locked = true`, `followCursor = false`, out of combat,
   not previewing, drives `CV:UpdateVisibility()` for real, asserts
   `CV.container.__mouse == false` and `CV.container.dragBorder.__shown == false`.
   Pre-fix: **fails** — `Tests/loadtest.lua:764: a locked grid still took the
   mouse`. This is the one case that catches the actual regression on the
   mouse assertion itself: pre-fix, `locked` was never consulted, so the grid
   took the mouse whenever out of combat regardless of the setting.

3. **`task 20: an unlocked grid takes the mouse and shows its border`** — same
   conditions with `locked = false`.
   Pre-fix: **fails**, but on the border assertion, not the mouse one —
   `Tests/loadtest.lua:785: attempt to index a nil value (field 'dragBorder')`.
   `f.dragBorder` does not exist pre-fix at all. The mouse assertion (line
   above, not reached as a failure) would have passed unmodified, because
   pre-fix the grid already took the mouse whenever unlocked-out-of-combat —
   `locked` did nothing, so this half of the behaviour was already correct by
   accident. **What this case actually guards going forward**, per the task's
   instruction to say so plainly: that the border exists at all and is shown
   exactly when the grid is draggable, which is the part that is genuinely new.

4. **`task 20: preview overrides the lock`** — Decision 2's override:
   `locked = true`, `previewMode = true`.
   Pre-fix: **fails** the same way — `Tests/loadtest.lua:807: attempt to index
   a nil value (field 'dragBorder')`. The mouse assertion would have passed
   pre-fix too (preview already forced `editable = true` regardless of any
   lock, since there was no lock to override). **What this case guards**: that
   the override survives the rewrite and that the border now reflects it too.

5. **`task 20: follow cursor never takes the mouse, even while previewing`** —
   "the half that already worked, kept working." `followCursor = true`,
   `locked = false`, `previewMode = true`.
   Pre-fix: **fails** the same way — `Tests/loadtest.lua:831: attempt to index
   a nil value (field 'dragBorder')`. The mouse assertion would have passed
   pre-fix (follow-cursor already suppressed `EnableMouse` unconditionally).
   **What this case guards**: that this pre-existing correct behaviour is not
   disturbed by the three-state rewrite, and that the border is correctly
   suppressed alongside it.

Summary of the nuance the task file anticipated: cases 2, 4 and 5 all fail
pre-fix, but through the border's absence (a hard error) rather than through
their own mouse-state assertion being wrong — because the mouse half of
"unlocked", "preview", and "follow cursor" was each already correct before
this task for reasons unrelated to `locked` (locked simply didn't exist, and
follow-cursor/preview already short-circuited correctly). Only case 2 (the
reported bug) exercises a mouse assertion that is actually wrong pre-fix.
Every case still fails pre-fix and passes post-fix, as required, and every
case is a real regression guard for exactly the property named in its title.

## Sources used

None looked up externally — this task only touches ThugUI's own frames
(`CreateFrame("Frame", ...)`, `CreateTexture`, `SetPoint`, `EnableMouse`,
`SetColorTexture`), all of which the codebase already uses identically
elsewhere (e.g. `f.previewBG` a few lines above the new border, `icon.tex` in
`AcquireIcon`). No new Blizzard API surface was touched.

## Proposed docs changes

**`docs/DECISIONS.md`**, new section (numbering left to the coordinator — the
handoff's most recent is §28):

> ### §29 — The cooldown grid's mouse state is one boolean, not two independent checks
>
> The grid used to take the mouse whenever `(previewMode or not
> InCombatLockdown()) and not followCursor` — two conditions ANDed together,
> neither of which was "is the player allowed to drag this right now". With
> Follow cursor off, that meant a full 10x10-cell invisible rectangle sat over
> the game view and ate every click and hover the moment combat ended, with no
> way to tell where its edges were. Task 20 replaced it with one `draggable`
> boolean and drove both `EnableMouse` and a new border frame from it, so the
> two are structurally incapable of disagreeing.
>
> **Preview overrides the lock, deliberately.** Locking is set from the
> settings page; a lock that cannot be undone from the place it was set — you'd
> have to unlock it, then re-enter preview, just to see the frame you're
> configuring move — is a trap, not a safety feature. Preview mode is already a
> deliberate, temporary, player-initiated state, so it gets the same mouse
> access unlocked does.
>
> **The border and the mouse are driven from one condition on purpose**, not
> two independently-toggled things that happen to usually agree. An invisible
> frame that eats clicks is indistinguishable from a broken game — the border
> exists specifically to answer "will clicking here drag the grid or hit the
> world", so a border that could ever show while the frame is inert (or vice
> versa) would be actively misleading, worse than no border at all.
>
> **Default `locked = true` is a deliberate behaviour change on upgrade.**
> `Data.GetProfile`'s existing key-backfill (`Data.lua:354-357`) means every
> profile saved before this task gets `locked = true` on next load — the grid
> stops taking the mouse out of combat for players who never asked for that,
> not just new ones. The setting is how they get dragging back. No migration
> preserves the old always-editable behaviour; that behaviour was the bug being
> fixed.

**`Tests/README.md`**, under "Hazards in the harness itself" (or wherever the
coordinator judges fits — it's the same shape as the existing `EnableMouse`
entry that was already missing):

> **`EnableMouse` used to be swallowed by the generic no-op branch**, so mouse
> state was unobservable and a whole class of "does this frame take input"
> assertion could not be written — the same shape as the `GetHeight`/`GetWidth`
> and `SetTexture` gaps already documented above. Closed 2026-08-15 (task 20)
> by recording it as `a.__mouse`, which is what let the locked-grid regression
> get a real assertion instead of only being inferable from the profile table.

## Could not do

Nothing. The task was fully specified and I found no genuine ambiguity in it.

## Noticed but did not touch

- **The existing case `"the misc panel drops the Blizzard-buffs checkbox but
  keeps proc glow"` (`Tests/loadtest.lua`, currently ~line 2257) now fails**,
  and per the task's explicit instruction ("leave it failing, say so in your
  report, and draft its replacement there — do not edit it") I left it as-is.
  It asserts `#misc.widgets == 1` (only "Show proc glow" registered in the
  `misc` panel) and that `misc.widgets[1]` drives `showProcGlow`. Adding "Lock
  position" to that same panel — exactly as Decision 4 instructs — makes both
  assumptions false: there are now 2 widgets, and `widgets[1]` is "Lock
  position", not "Show proc glow". **Draft replacement**, changing only the
  count and the index it reads from:

  ```lua
  { "the misc panel drops the Blizzard-buffs checkbox but keeps proc glow and lock position", function()
      local Page = ThugUI.CooldownViewer.Page
      local misc
      for _, panel in ipairs(Page.panels or {}) do
          if panel.width == 260 then misc = panel end
      end
      assert(misc, "could not find the misc panel")

      -- Panel:Register only keeps widgets that carry a Refresh -- Section,
      -- Label, Button and Gap do not, so a checkbox is the only thing that
      -- would show up here. Two entries: Lock position, then Show proc glow
      -- (build order), where there used to be three before Blizzard-buffs
      -- was dropped.
      assert(#misc.widgets == 2,
          ("misc panel has %d registered widgets, expected exactly 2 (lock position, proc glow)")
          :format(#misc.widgets))

      local profile = Data.GetActiveProfile()
      local restoreGlow = profile.showProcGlow
      profile.showProcGlow = true
      misc.widgets[2]:SetChecked(false)
      misc.widgets[2]:GetScript("OnClick")(misc.widgets[2])
      assert(profile.showProcGlow == false,
          "the second checkbox did not drive showProcGlow")
      profile.showProcGlow = restoreGlow
  end },
  ```

  I did not add this myself — it edits an existing case's assertions and
  behaviour, which is exactly what the brief says costs real trust when an
  agent does it unasked ("Watch for tests being repurposed rather than added").
  This is a draft for the coordinator to apply.

- **Nothing else looked wrong.** The rest of `UpdateVisibility`,
  `EnsureContainer`, and the misc panel's surrounding controls were read in
  full while making these changes and nothing outside this task's scope stood
  out.

## Not verified

Everything here needs the running game — nothing below was or could be
checked from the harness alone:

- **The border's actual on-screen appearance and position.** The harness
  records that `SetPoint`/`SetColorTexture`/`SetHeight`/`SetWidth` were called
  with the values I intended, not that four 1px textures actually draw a
  crisp, correctly-aligned rectangle around the container at real UI scales.
- **That the locked grid genuinely passes clicks, hovers, and world targeting
  through to the game underneath**, rather than merely reporting
  `EnableMouse(false)` was called. `EnableMouse(false)` is the documented way
  to do this and is used elsewhere in this codebase, but it has not been
  clicked through in game for this frame specifically.
- **That dragging still works exactly as before when unlocked.** The drag
  handlers (`OnDragStart`/`OnDragStop`) were not touched, but I have not seen
  a drag actually move the frame in game — only that `EnableMouse(true)` is
  now reached under the right conditions.
- **The new "Lock position" checkbox's placement, wording, and tooltip as they
  actually render** in the settings window — panel layout, spacing relative to
  "Show proc glow", and text wrap were not visually confirmed.
- **The `locked:` line in `/thugcv` and in the diagnostics snapshot**, as they
  actually appear in chat output and in `ThugUI_DebugLog` respectively.
- **The upgrade behaviour itself** — that a player's existing, previously
  unlocked-by-default profile actually comes back locked on the next real
  login, not just in the simulated `Data.GetProfile` backfill test.
- **In-combat behaviour of the lock.** `InCombatLockdown()` gating unlock is
  exercised in the harness via the `_G.__inCombat` stub, not against a real
  combat transition.
