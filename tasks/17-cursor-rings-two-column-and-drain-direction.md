# Task 17 — Cursor Rings: two-column layout, and a drain direction for the resource ring

**Read `tasks/00-AGENT-BRIEF.md` first.** It carries the house rules, the
verification gate, and the things that are forbidden. This file carries the
design decisions; they are already made. **Execute them. Do not re-decide them.**
If you hit a genuine ambiguity, **stop and report** rather than resolving it.

Baseline before you start: `lua Tests/loadtest.lua .` → **201 passing, 0
failures**. Any failure you report afterwards is one you caused, unless this file
told you to expect it.

---

## Why this task exists

The player has used this addon daily for months and **did not know the resource
ring had its own "Show:" visibility dropdown** — it sits directly above the
checkbox they did find, in a stack of roughly forty controls all left-aligned in
a single narrow column, with about 550px of empty space to the right of them.

That is the whole point of this task. **The layout is judged on whether settings
are findable, not on whether the right-hand side is full.** A prettier page that
still hides a dropdown has failed.

---

## Part 1 — make side-by-side panels work on a scrolling page

### The problem

Two column idioms exist in this repo. The one that generalises is
`ui/pages/CooldownViewer.lua:626-834`, which creates **several `W.NewPanel`
instances**, each with its own `x`/`y` origin and its own vertical cursor.

It works there because that page is registered with `scroll = false`. It does
**not** work on a scrolling page, because of `ui/Window.lua:250`:

```lua
if def.scroll ~= false then
    host:SetHeight(math.max(panel:GetHeight(), self.frame.content:GetHeight()))
end
```

`panel` is only the **first** panel. A second column's height is invisible to
that call, so the scroll area comes up short and the bottom of the taller column
cannot be reached. Cursor Rings is a scrolling page.

### What to build

1. **In `ui/Widgets.lua`, `W.NewPanel`:** register each created panel onto its
   host, e.g. appending to `host.__thugPanels` (create the table if absent).

   **This is safe and is not the §15 taint bug.** That bug was writing `__thug*`
   fields onto ***Blizzard's*** frames. These are frames we created ourselves.
   Do not skip this out of caution — but do leave a one-line comment saying why
   it is safe, because the next reader will have the same worry.

2. **In `ui/Window.lua:249-251`:** size the scroll host from the **tallest**
   registered panel rather than the first one. Preserve the existing
   `math.max(..., self.frame.content:GetHeight())` floor.

3. **Do not change** `Window:BuildPage`'s existing behaviour in any other way,
   and **do not** convert Cursor Rings to a non-scrolling page.

This must leave `ui/pages/CooldownViewer.lua` working unchanged — it already
creates multiple panels and tracks them in its own `self.panels`; your change
must not double-count or conflict with that.

---

## Part 2 — rebuild the Cursor Rings page in two columns

File: `ui/pages/CursorRings.lua`. Page is registered at the bottom of that file
(`id = "cursorrings"`, `order = 40`). **Keep it a scrolling page.**

Usable content width is **762px** (derived in `ui/Window.lua:221-254`; the
window is 1040 wide, sidebar 170). Controls currently all sit at x = 16.

### The approved layout

The pairings below were chosen by subject and **approved by the player**. Do not
re-pair them.

```
Cursor Rings
GCD and cast tracking drawn around the mouse pointer.

── Ring slots ──────────────────────  ── Colours ─────────────────────
Reticle:      [ dropdown ]            Reticle:   [ dropdown ] [swatch]
Reticle size  [ slider   ]            Main ring: [ dropdown ] [swatch]
Inner ring:   [ dropdown ]            GCD:       [ dropdown ] [swatch]
Main ring:    [ dropdown ]            Cast:      [ dropdown ] [swatch]
Outer ring:   [ dropdown ]

── Animation ───────────────────────────────────────────────────────
GCD sweep:  [ dropdown ]              Cast sweep:  [ dropdown ]
GCD start   [ slider   ]              Cast start   [ slider   ]

── Resource ring ───────────────────  ── Combo pips ──────────────────
(note text)                           (note text)
[x] Show resource ring                [x] Show combo pips
Show:     [ dropdown ]                Show:     [ dropdown ]
Colour:   [ dropdown ] [swatch]       Colour:   [ dropdown ] [swatch]
Opacity   [ slider   ]                Pip size  [ slider   ]
[x] Radial bar (…)                    Distance  [ slider   ]
Drain:    [ dropdown ]  ← NEW         Unspent   [ slider   ]

── Visibility ──────────────────────  ── Test ────────────────────────
[x] Only show in combat               [ ] Test mode
[ ] Hide the game cursor
Transparency  [ slider ]
Scale         [ slider ]
```

**Why Resource ring and Combo pips are paired:** they are structurally
near-identical — show toggle, `Show:` dropdown, colour + swatch, then sliders.
Side by side they mirror each other, and the two `Show:` dropdowns land in
matching positions. **That mirroring is the fix for the discoverability
problem.** Preserve it: keep the shared rows aligned so the eye can pair them.

### Constraints

- **Every existing control must survive** with the same label text, the same
  config key, the same `get`/`set` behaviour, and the same side effects (the
  `Call(...)` / `ThugUI.X:Update()` calls in the current setters). This is a
  layout change, not a behaviour change. The one addition is `Drain:` (Part 3).
- Column origins: left column at the existing x, right column starting around
  **x = 390**, each about **340px** wide. Adjust if controls collide; the numbers
  are a starting point, not a specification.
- Section headers: each column gets its own, as drawn above.
- **`Page:Refresh()` must refresh every panel you create.** `CooldownViewer.lua`
  does this by keeping `self.panels` and looping. Follow that pattern. A control
  that does not refresh shows a stale value after a profile change and looks like
  a settings-persistence bug.
- Keep the two duplicated `{always, combat, rings}` option tables **as they are**
  unless pulling them into a shared local is a clean two-line change — the file
  already does this for `COLOR_MODES`/`FILL_MODES` at the top. If it is not
  clean, leave it and say so in your report.

---

## Part 3 — clockwise / counter-clockwise drain direction

### The setting

- Key: **`resourceRingDrainDirection`** in `ThugUI_Config` (flat key — this page
  uses `ThugUI_Config` throughout; see `docs/DECISIONS.md` §1).
- Values: **`"clockwise"`** (default) and **`"counterclockwise"`**.
- Default must reproduce **exactly today's behaviour**, which the player has
  confirmed working in game. A player who never touches this dropdown must see
  no change whatsoever.
- Control: a dropdown labelled **`Drain:`** in the Resource ring column, placed
  after the "Radial bar" checkbox, per the layout above.
- Its setter calls `ThugUI.ResourceRing:Update()`, matching the sibling controls.

### The implementation

File: `modules/ResourceRing.lua`. **The radial path only** — `RR:EnsureRadialFrame`
(~`:164-198`), `RR:UpdateRadial` (~`:396-429`), `RR:SyncGeometry` (~`:233-264`).

**Do not touch the Cooldown-widget path.** It is a fallback that is separately
known to be frozen (`docs/KNOWN-ISSUES.md`, "The old Cooldown-widget resource
ring never tracked"). Adding a direction control to a ring that does not move is
pointless, and touching that path risks the escape hatch. This is a decision,
not an oversight.

The API, verified against Blizzard's generated documentation on `live` (12.1),
`Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua`:

```
SetRadialProgressBarReverse(reverse: bool)
    "whether the radial progress bar fills in reverse (counterclockwise) direction."
```

It lives on the **texture**, not the StatusBar — call it on the object returned
by `bar:GetStatusBarTexture()`.

### Three things that will bite you if you assume

1. **`StatusBar:SetReverseFill` is NOT the right call.** It exists, but its only
   real use in Blizzard's entire source is on a plain horizontal bar, and there
   is no evidence it affects radial mode. Do not use it.

2. **Blizzard's own UI never uses any of this.** An exhaustive search of the live
   12.1 source found **zero** uses of `StatusBarRenderMode.Radial`,
   `SetRenderMode`, or any `SetRadialProgressBar*` call. There is no first-party
   example. Treat every one of these methods as possibly absent at runtime.

3. **It is unverified that the StatusBar's texture even exposes these methods.**
   The generated docs do not state object composition; that the texture from
   `GetStatusBarTexture()` carries `SimpleTextureBaseAPI` methods is a
   naming-convention inference. **So guard it:**
   ```lua
   local tex = bar:GetStatusBarTexture()
   if tex and tex.SetRadialProgressBarReverse then ... end
   ```
   Follow the existing `self.radialUnsupported` capability-check pattern in that
   file (~`:166`, `:179-188`). If the method is absent, the ring must keep
   working in its default direction — never error, never blank.

### Explicitly out of scope

**Do not change how the start angle is set.** The code currently rotates the
managed texture as a workaround for `StatusBar` having no `SetRotation`. There is
now a real API for it (`SetRadialProgressBarStartOffset`), and **the player has
decided not to change it in this pass** — it is verified working in game. Leave
it alone. Mentioning it in your report is welcome; changing it is not.

---

## Tests — required, not optional

`Tests/loadtest.lua`. Add cases for:

1. The scroll host takes the height of the **tallest** panel, not the first.
   Make this fail against the unmodified `ui/Window.lua`.
2. Every control on the rebuilt Cursor Rings page still exists and still reads
   and writes its config key. The page-build assertions the harness already
   derives should cover existence; add value round-trips for at least the
   `Show:` dropdowns, since a broken one is the bug this task exists to prevent.
3. `resourceRingDrainDirection` defaults to `"clockwise"` and round-trips.
4. The radial ring calls `SetRadialProgressBarReverse(true)` when the setting is
   `"counterclockwise"` and `false`/not-at-all when `"clockwise"`.
5. **A stub texture WITHOUT `SetRadialProgressBarReverse` does not throw** and
   the ring still draws. This is the capability-guard case and it is the most
   important one here, because the method's existence is unverified.

You will need to extend the StatusBar/texture stub. **`Tests/README.md` has a
"Hazards in the harness itself" section — read it.** Note in particular that the
stub's `SECRET` is a plain table, so `SECRET == nil` returns `false` quietly
where the real client throws.

**Do not repurpose an existing test.** If a current case becomes wrong because of
your change, **leave it failing and draft its replacement in your report**. Do
not edit or delete it. An agent already rewrote a regression case in place on
this project and the report did not disclose it; that is the failure mode this
paragraph exists to prevent.

---

## Deliverables

- Changes in `ui/Widgets.lua`, `ui/Window.lua`, `ui/pages/CursorRings.lua`,
  `modules/ResourceRing.lua`, `Tests/loadtest.lua`. Nothing else without saying
  why in your report.
- `luac -p` clean on every file you touched.
- `lua Tests/loadtest.lua .` — report the pass count and **the exact list of any
  failures**.
- For each test you added, state that you ran it against the **unmodified** code
  and it failed. The coordinator re-runs these claims.
- **Leave everything uncommitted.** Do not run any state-changing git command.
- **Do not edit anything in `docs/`.** Draft proposed entries into your report.
- Write your report to `tasks/reports/17-cursor-rings-two-column-and-drain-direction.md`.
  **No report file means the task did not happen.**
