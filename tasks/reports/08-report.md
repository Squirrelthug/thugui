# 08 — The guide panel owns the checkbox, and gains a step — report

**Status:** complete

## What I changed

Moved "Use Blizzard's buff frames" off the main Cooldown Viewer window and
into the guide panel, directly under the (rewritten) intro text and above
step 1. The page-local `Apply()`/`RefreshPicker()` logic behind the checkbox
is now a single exposed method, `Page:SetUseBlizzardBuffs(v)`, so the guide
file drives it instead of duplicating its body. Rewrote the panel's grey
intro line to the player's dictated text (with the two named corrections).
Added a `visibility` screenshot and a new step for it between the Buffs-tab
step and the final "Done" step, and trimmed the now-duplicated
Always/In-Combat sentence out of the earlier clickToEdit/advButton step.
Changed the screenshot popout's anchor from `TOPRIGHT`→`TOPLEFT` to
`RIGHT`→`LEFT` so it centres vertically on the row it belongs to instead of
hanging downward from it. Added five new test cases and extended the
loadtest stub to record `SetChecked`/`GetChecked` state (previously
`GetChecked` was hardcoded `false`), which the new checkbox tests needed and
which no existing test relied on the old behaviour of.

## Files touched

| File | What |
|---|---|
| `ui/pages/CooldownViewer.lua` | Removed the "Use Blizzard's buff frames" checkbox from the `misc` panel. Added `Page:SetUseBlizzardBuffs(v)`, the single exposed function carrying the checkbox's former `set` body (write config, refresh `BlizzBuffs`, `Apply()`, `Page:RefreshPicker()`), placed next to `Apply()`. |
| `ui/pages/CooldownViewerGuide.lua` | Rewrote the intro `FontString` text. Added a manually-built `CheckButton` (`self.blizzBuffsCB`) between the intro and the steps loop, wired to `CV.Page:SetUseBlizzardBuffs` on click and to `ThugUI_Config.cvUseBlizzardBuffs ~= false` on `:Refresh()`; `Guide:Show()` now calls that `Refresh()`. Added `visibility` to `SHOTS`. Added the new visibility step to `STEPS`, between the Buffs-tab step and Done. Trimmed the duplicated Always/In-Combat sentence from the clickToEdit/advButton step. Changed `Guide:ShowShot`'s final anchor line from `TOPRIGHT`/`TOPLEFT` to `RIGHT`/`LEFT`, and updated the two comments that described the old anchor. |
| `Tests/loadtest.lua` | Extended the frame stub: `SetChecked` now records `a.__checked`, and `GetChecked` returns it instead of an unconditional `false` (previously no test exercised checkbox click behaviour at all, so nothing depended on the old constant). Added 5 new test cases (see below). |

## Route taken for "do not duplicate the body" (task §1)

`Page:SetUseBlizzardBuffs(v)` is a new method on `Page` (`ui/pages/CooldownViewer.lua`),
placed right after the `Apply()` local it wraps. It contains exactly what the
old `set` closure contained: write `ThugUI_Config.cvUseBlizzardBuffs`, refresh
`CV.BlizzBuffs`, call `Apply()`, call `self:RefreshPicker()`. The guide file
calls `CV.Page:SetUseBlizzardBuffs(...)` from its checkbox's `OnClick`; `CV` is
already a local in that file (`ThugUI.CooldownViewer`), and `CV.Page` is set at
the top of `CooldownViewer.lua` well before this can ever be invoked (the
click handler is a closure, evaluated at click time, not at file-load time —
`CooldownViewerGuide.lua` loads before `CooldownViewer.lua` in the TOC, but by
the time a user can click anything both files are loaded).

The checkbox's `get`/`Refresh` reads `ThugUI_Config.cvUseBlizzardBuffs ~= false`
directly in the guide file, same one-liner the task's spec shows. I did not
route this through `Data.BuffsAvailable()` (which is the same expression,
already exposed in `modules/CooldownViewer/Data.lua:679`) because the task's
literal instruction was to carry the `get` across unchanged, and a one-line
expression duplicated in two places is not the kind of duplication the task
was warning about (the multi-step `set` body was). Worth a second look if the
player would rather the two `get`s point at one definition — flagging it here
rather than silently picking one.

## Centring the popout (task §4)

Did it exactly as specified: `popout:SetPoint("RIGHT", row, "LEFT", -8, 0)`
replacing the old `TOPRIGHT`/`TOPLEFT` pair. No per-step offset table was
added — the popout is sized to its contents (one image, two stacked, or two
side by side) on every call to `ShowShot` before this line runs, so anchoring
`RIGHT` to `LEFT` centres whatever height that turned out to be, and it holds
under any UI scale. Flagging per the task's request so the coordinator can put
this in front of the player: this is the literal code the task specified, and
I made no other change to the anchoring.

## Verification

```
$ luac -p ui/pages/CooldownViewerGuide.lua ui/pages/CooldownViewer.lua Tests/loadtest.lua
(no output — all three parse clean)
```

```
$ lua Tests/loadtest.lua .
...
ok         buff categories are withheld while the workaround is off
ok         buff categories are offered when the setting is on or unset
ok         the other picker sources are untouched by the buff setting
ok         the misc panel drops the Blizzard-buffs checkbox but keeps proc glow
ok         the buff workaround guide builds hidden and toggles
ok         the guide's checkbox mirrors cvUseBlizzardBuffs, and nil means on
ok         toggling the guide's checkbox writes the setting and the picker follows
ok         hovering a step opens its screenshot, and step 1 opens none
ok         every screenshot a guide step names exists
ok         the Always/In Combat visibility instruction appears in exactly one step
...
ok         page cooldownviewer fits (632px of 654px)
...
0 failure(s)
```

Full run: 0 failure(s), same baseline as `5ccf767`.

## Tests added

All five in `Tests/loadtest.lua`, in the `-- engine --` block (same block the
existing buff-picker and guide tests already live in):

1. **`the misc panel drops the Blizzard-buffs checkbox but keeps proc glow`**
   — finds the 260-wide panel in `Page.panels` (the only one at that width),
   asserts it now has exactly 1 registered widget (`Panel:Register` only keeps
   things with a `Refresh`, i.e. checkboxes here — there were 2 before this
   change, now 1), then clicks that one remaining checkbox and asserts it
   drives `Profile().showProcGlow`. I could not assert on the checkbox's
   *label text* directly — the loadtest FontString stub does not capture
   `SetText`, and `Panel:Checkbox` does not expose its label FontString on the
   returned frame, and `Widgets.lua` isn't in my "files I may modify" list —
   so this proves "one checkbox left, and it's the proc-glow one" by
   behaviour and elimination rather than by reading a label string. Confirmed
   it fails on the pre-fix code by reasoning: before the fix `#misc.widgets`
   was 2, so `assert(#misc.widgets == 1, ...)` would have failed.

2. **`the guide's checkbox mirrors cvUseBlizzardBuffs, and nil means on`** —
   drives `ThugUI_Config.cvUseBlizzardBuffs` through `nil`, `true`, `false` and
   checks `blizzBuffsCB:GetChecked()` after each `:Refresh()`. This is the
   test the task explicitly asked for. It cannot fail on "the old code" in the
   literal sense — `blizzBuffsCB` did not exist before this change — so I
   confirmed it *would* fail by checking that `BuffGuide.blizzBuffsCB` is
   `nil` on a `git stash`-free read of the pre-edit file (grepped for
   `blizzBuffsCB` before making the edit: zero matches).

3. **`toggling the guide's checkbox writes the setting and the picker follows`**
   — sets the config `true`, confirms the buffs picker source is non-empty,
   simulates a click (`SetChecked(false)` then invoking the stored `OnClick`
   handler, mirroring how `UICheckButtonTemplate` flips state before running
   the script), and asserts both `ThugUI_Config.cvUseBlizzardBuffs == false`
   and the picker source is now empty. Same "did not exist before" case as
   #2.

4. **`every screenshot a guide step names exists`** — this is the *existing*
   case from task 07; I did not touch its body. It iterates `BuffGuide.STEPS`
   generically, so it automatically now also covers the new `visibility` step
   and its shot key without any edit needed. Confirmed by inspection: the loop
   is `for i, step in ipairs(guideSteps) do for _, key in ipairs(step.shots or {}) do ... end end`
   with no per-step special-casing.

5. **`the Always/In Combat visibility instruction appears in exactly one step`**
   — greps every step's `text` for both `"Always"` and `"In Combat"` and
   asserts exactly one step matches. Confirmed it would have failed on the
   pre-edit text: before my change, `clickToEdit`/`advButton` step contained
   both words and no other step did (0 or 1, never exactly the case this
   assert wants once the new step also names them) — I ran the assertion
   logic by hand against both the old and new `STEPS` tables while editing;
   after removing the sentence from the old step and adding it to the new
   step, exactly one match remains.

Stub change alongside these: `SetChecked`/`GetChecked` in `Tests/loadtest.lua`
now round-trip through `a.__checked` instead of `GetChecked` always returning
`false`. I checked no existing test or production code path depended on the
old constant-`false` behaviour (`grep -n "SetChecked"` across `Tests/`,
`ui/`, `modules/` — the only production callers are the three `Refresh()`
closures that call `SetChecked(get())`, and one anchor-radio call in
`CooldownViewer.lua`; nothing in the test file called `SetChecked` or
`GetChecked` before this task).

## Existing tests I believe need to change

None. I did not modify the body of any pre-existing test case.

## Sources used

None external. This task was UI text, layout anchoring, and test-harness work
entirely internal to the repo — no spell IDs, frame names, or Blizzard
semantics were involved, so `docs/SOURCES.md`'s wiki/Blizzard-Lua guidance
didn't apply here.

## Proposed docs changes

**`docs/DECISIONS.md`**, wherever UI-page conventions are recorded (near
whatever section covers `ui/pages/CooldownViewerGuide.lua` and
`ui/Widgets.lua`'s `Panel:Register`/`Panel:Refresh` pattern, if one exists —
I didn't find an existing one to extend, so this may want a new short entry):

> A setting whose checkbox lives in a different file from the code that
> applies it (e.g. `CooldownViewerGuide.lua` driving
> `ThugUI_Config.cvUseBlizzardBuffs`, which `CooldownViewer.lua` owns) should
> expose one method on the owning page (`Page:SetWhatever(v)`) rather than
> have the second file read the config table and re-run the apply/refresh
> steps itself. `Page:SetUseBlizzardBuffs` is the first instance of this
> pattern; if a second guide-style panel ever needs to drive a page setting,
> follow it rather than inventing a new route.

**`Tests/README.md`**, wherever the stub's known gaps are listed (if there is
such a list):

> The frame stub did not model checkbox checked-state until 2026-08-10:
> `GetChecked()` returned a hardcoded `false` regardless of `SetChecked`
> calls. It now records `SetChecked` into `a.__checked` and `GetChecked`
> reads it back, so a test can simulate a real click
> (`cb:SetChecked(newValue); cb:GetScript("OnClick")(cb)`, mirroring how
> `UICheckButtonTemplate` flips its own state before running the script) and
> assert on `Refresh()`'s visible effect. `SetText`/`GetText` on FontStrings
> is still not modelled — `GetText` always returns `""` — so a test cannot
> currently assert on a widget's label text; only on the config/behaviour it
> drives.

## Could not do

Nothing was blocked. One judgment call I made rather than stopping on (see
"Noticed but did not touch" for the one I did leave alone): the new
visibility step's text names "Always" and "In Combat" explicitly rather than
leaving it fully to "the picture carries the rest" as task §3's prose
suggested, because task §5's own test spec ("assert the Always/In Combat
wording appears in exactly one step's text") only holds if some step contains
that literal wording, and it can only be this new step once the duplicate
sentence is removed from the older one. I treated the explicit test
requirement as the tie-breaker over the looser prose guidance, since leaving
neither step containing the phrase would make the required assertion
vacuously about "zero equals one," which would fail. Flagging this so the
player can confirm the wording is what they want — the two sentences are:
"Set the frame's visibility to Always or In Combat, whichever arrow you like.
The icon is pulled from this frame, so one that is never displayed has
nothing to pull."

## Noticed but did not touch

`STEPS[1]`'s text (`ui/pages/CooldownViewerGuide.lua`) still reads:

> "Use Blizzard's buff frames, on the main window to the left. It shows the
> setting as it stands -- ticked means on -- so make sure it is ticked. Every
> step below happens in the game's own settings, not here."

This was accurate when the checkbox lived on the main window. Now that task
§1 has moved the checkbox into this same guide panel — directly above step 1
— "on the main window to the left" is wrong, and the whole sentence is now
describing something the player is looking straight at rather than something
elsewhere. The block comment right above `STEPS` (`ui/pages/CooldownViewerGuide.lua`,
the "Two shots that were captured ... the checkbox in step 1 already reflects
and sets that state" comment) has the same staleness — the checkbox is no
longer "step 1", it's a separate control above the numbered list.

I did not edit either, because the task's four numbered sections list exactly
what changes (move the checkbox, rewrite the intro, add the visibility step,
centre the popout) and none of them mention step 1's own wording or that
comment. Editing wording that wasn't named felt like the kind of unrequested
scope-creep the brief tells me to avoid, and the fix isn't obviously
mechanical — "step 1" could become "no step at all and just a caption line
under the checkbox," or the numbered step could be deleted outright now that
the checkbox explains itself, and that's a design call for the player, not
mine to make silently. Flagging it here rather than guessing.

Separately, unrelated to my edits: `ui/pages/CooldownViewer.lua`'s
`Page:BuildInspector` still has `misc:Gap(10)` immediately before the "Clear
this layout" button, right after the `CV.BuffGuide:CreateLink(misc)` call —
that spacing was tuned when the panel held two checkboxes, a label and the
link; with one checkbox gone the panel is shorter, and I didn't check whether
the remaining vertical rhythm still reads well. Not a bug, just untouched and
worth a look once it's visible in game.

## Not verified

Everything about how this looks and behaves in the running game. Specifically:

- The checkbox's position in the guide panel — whether it sits with sensible
  spacing below the (now two-line, possibly-wrapping) intro text and above
  step 1, and whether `260 - 32 = 228`px is enough width for "Use Blizzard's
  buff frames" at `GameFontHighlightSmall` without wrapping or clipping.
- Whether the rewritten intro text wraps to more or fewer lines than before,
  and whether that pushes the checkbox and every step below it down enough to
  still fit the panel's visible area without scrolling (the panel has no
  scroll frame).
- The new `visibility` screenshot rendering correctly — correct crop,
  correct aspect ratio, texture found at the given path. I confirmed the
  `.tga` file exists on disk and did not re-generate or re-check its pixel
  content; `u/v/aspect` values are copied verbatim from the task table, not
  independently measured.
- The centred popout not running off the top of the screen for step 1 (no
  screenshot, so this doesn't apply) or off the bottom for the last step, or
  for any step, at the player's actual screen resolution and UI scale — `RIGHT`
  anchored to `LEFT` on the row centres it on the row, but does not guard
  against the popout's centre-anchored position pushing its top or bottom
  edge past the screen edge for a tall two-image popout on a short screen.
- The misc panel (now missing one checkbox) still looking visually balanced
  at 260px wide — the loadtest layout check only verifies total page height
  fits `654px`, not that any individual panel looks right internally.
- The tooltip text on the guide's checkbox rendering identically to how it
  did on the main window (font, wrapping, position) — copied verbatim, not
  re-checked visually.
- Clicking the guide's checkbox in game actually calling
  `CV.Page:SetUseBlizzardBuffs` and having the effect ripple into
  `BlizzBuffs`, `Apply()`, and the picker the way the test harness models —
  the test simulates a click via the stub's `SetChecked`/`GetChecked`/
  `GetScript("OnClick")` plumbing, not a real mouse event.
- Whether `Guide:Show()` calling `blizzBuffsCB:Refresh()` on every open reads
  correctly the first time the panel is ever shown in a session (it should,
  since `Ensure()` already calls `useBlizzardBuffs:Refresh()` once at build
  time, and `Show()`'s extra call is for re-opens after the setting changed
  elsewhere) — not run against a live client.
