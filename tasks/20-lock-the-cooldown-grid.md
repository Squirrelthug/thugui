# Task 20 — Lock the cooldown grid, and show its edge when it is unlocked

**Read `tasks/00-AGENT-BRIEF.md` first.** This file carries the design
decisions. **Execute them; do not re-decide them.** On a genuine ambiguity,
**stop and report** rather than resolving it.

Baseline from a clean tree: `lua Tests/loadtest.lua .` → **224 passing, 0
failures**. Re-run it yourself before you touch anything and confirm the number.
The working tree is clean; every change below is yours.

---

## The problem

The cooldown viewer's container is a full 10x10 grid
(`CV:GetGridSize`) whose size never changes, however few cells the player filled.
That is deliberate — it is what makes an intersection anchor mean the same place
always — but it means the frame is mostly empty, invisible space.

`Core.lua:1277` currently reads:

```lua
f:EnableMouse(editable and not profile.followCursor)
```

So with **Follow cursor off**, the grid takes the mouse whenever the player is
out of combat. The player reported the consequence: a large invisible rectangle
sits in the middle of the game view swallowing clicks and hovers, with no visual
indication of where its edges are, so what it will eat is impossible to predict.
(With Follow cursor **on** the frame is never mouse-enabled, so this does not
arise — that half is already correct and must stay as it is.)

Dragging is the only reason the frame takes the mouse at all.

---

## Decision 1 — a per-profile `locked` setting, defaulting to locked

New key `locked` in `DefaultProfile()` (`modules/CooldownViewer/Data.lua:311`),
value `true`. Put it next to `point`, which is the other position-related key.

Per-spec profile, not global: `point` is already per-profile, and lock is a
property of a position.

**Default `true` is intentional and changes existing behaviour.** `Data.GetProfile`
fills newly-added default keys into existing profiles (`Data.lua:354-357`), so the
player's current profiles become locked on next login. That is the state they
asked for; the setting is how they get dragging back. Do not add a migration that
preserves the old unlocked behaviour.

## Decision 2 — locked means *completely* inert

Replace `Core.lua:1277` with three explicit states. The `editable` local above it
exists only to feed that line — check, and if nothing else in the function uses
it, remove it rather than leaving it dangling.

```lua
-- Three states, and the middle one is the point of the lock:
--   following the cursor -> never takes the mouse (it moves itself; unchanged)
--   unlocked, or preview -> takes the mouse, border drawn, draggable
--   locked               -> inert. Clicks, hovers and world targeting pass
--                           straight through the 10x10 grid, which is mostly
--                           empty space the player cannot see.
--
-- Preview overrides the lock deliberately: locking is done from the settings
-- page, and a lock that cannot be undone from the place it was set is a trap.
local draggable = not profile.followCursor
    and (self.previewMode or (not profile.locked and not InCombatLockdown()))
f:EnableMouse(draggable)
f.dragBorder:SetShown(draggable)
```

`f.previewBG:SetShown(self.previewMode)` on the line above is unchanged.

Nothing else may take the mouse. The pooled icons are plain `CreateFrame("Frame")`
with no `EnableMouse` call, so they are already inert — **do not add one**, and
do not enable mouse on the border frame below.

## Decision 3 — a thin border, shown exactly when the frame takes the mouse

Build it once in `CV:EnsureContainer` (`Core.lua:665`), after `previewBG`:

- A child `Frame` of the container, `SetAllPoints()`, mouse **not** enabled,
  hidden at creation, stored as `f.dragBorder`.
- Four textures on it — top, bottom, left, right — 1px thick, drawn on the
  `"OVERLAY"` layer so a border line is never lost behind an icon.
- Colour: the same teal as `previewBG` (`0, 1, 0.8`) at alpha `0.6`. It is the
  same idea as the preview tint — "this rectangle belongs to the addon" — so it
  should read as the same thing.

A frame, not four textures hung directly off the container, so one `SetShown`
drives all four and `UpdateVisibility` stays a single line.

Comment it with *why* it exists: an invisible frame that eats clicks is
indistinguishable from a broken game, and the border is what tells the player
where clicking will drag the grid rather than hit the world.

## Decision 4 — the setting's control

`ui/pages/CooldownViewer.lua`, the `misc` panel built at line 853 ("This
layout"), immediately **above** the "Show proc glow" checkbox. Follow that
checkbox exactly — same `misc:Checkbox{...}` shape, which `Panel:Register`
already wires into the page refresh, so no new `Refresh()` call is needed.

```lua
label   = "Lock position",
tooltip = "Locked, the grid ignores the mouse completely - clicks and hovers pass "
       .. "through it as if it were not there. Unlocked, a thin border shows the "
       .. "area you can drag. Has no effect while Follow cursor is on."
get     = function() return Profile().locked ~= false end,
set     = function(v) Profile().locked = v; Apply() end,
```

Do **not** add it to the top row of checkboxes beside "Follow cursor" — that row
already runs to x=610 plus its label and has no room.

## Decision 5 — make the state visible to diagnostics

Two one-line additions, both because the lock state is otherwise invisible in a
bug report:

- `modules/Diagnostics.lua:118` records `followCursor = profile.followCursor`;
  add `locked` beside it.
- `Core.lua:1628` prints `"  follow cursor:    "` in the `/thugcv` dump; add a
  matching `locked` line, aligned the same way.

---

## Tests

`Tests/loadtest.lua`. **Add cases; do not repurpose or rewrite existing ones.**
If an existing case now asserts something this task deliberately changes, **leave
it failing, say so in your report, and draft its replacement there** — do not
edit it. That rule exists because it has been broken twice.

Read `Tests/README.md` first, in particular "Hazards in the harness itself".

The frame stub currently swallows `EnableMouse` as a no-op, so mouse state cannot
be asserted. Record it the way `Show`/`Hide`/`SetShown` are recorded at
`loadtest.lua:139-142`:

```lua
if key == "EnableMouse" then a.__mouse = a1 and true or false return end
```

Cover, driving `CV:UpdateVisibility()` for real rather than asserting on the
profile table:

1. **Locked, not following the cursor, not previewing, out of combat** — the
   container's `__mouse` is false and `dragBorder.__shown` is false. This is the
   reported bug.
2. **Unlocked, same conditions** — `__mouse` true and the border shown.
3. **Locked *and* previewing** — `__mouse` true and the border shown. Decision 2's
   override.
4. **Follow cursor on, previewing** — `__mouse` false and the border hidden,
   whatever `locked` says. This is the half that already worked; the case exists
   so it stays working.
5. **Decision 1** — `Data.DefaultProfile().locked` is true, and a stored profile
   saved before this change (no `locked` key) comes back from `Data.GetProfile`
   with `locked == true`.

Verify each new case fails against the unmodified source and **state that in your
report, per case**. Cases 2 and 4 may well pass pre-fix once the stub records
`EnableMouse` — if a case cannot fail, say so plainly and explain what it is
guarding instead. **A test that cannot fail is worse than no test**, and a report
that claims a pre-fix failure that did not happen is worse still.

---

## Out of scope — do not do these

- **Do not change what Follow cursor does**, or when the frame anchors to the
  cursor. `UpdateCursorPosition`, `ReleaseAnchor` and the `wantCursor` block are
  untouched.
- **Do not change the drag handlers** (`OnDragStart`/`OnDragStop`) or how
  `profile.point` is saved.
- **Do not touch the legacy ECV/BCV/GCV bars** in `modules/EssentialRings.lua`.
- **Do not make the border configurable** — no colour, thickness or toggle
  option. One border, one appearance.
- **Do not edit anything in `docs/`.** Draft proposed entries into your report.
- **Do not run state-changing git commands.** Leave the work uncommitted.

## Report

`tasks/reports/20-lock-the-cooldown-grid.md`. Include the harness count before
and after, each new case with its confirmed pre-fix result, any existing case you
left failing and why, anything you found outside scope and did not fix, and a
draft `DECISIONS.md` entry for the three-state mouse rule (why preview overrides
the lock, and why the border and the mouse are driven from one condition).

**No report file means the task did not happen.**
