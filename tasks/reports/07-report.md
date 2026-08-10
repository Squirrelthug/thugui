# 07 — The buff workaround deserves its own panel — report

**Status:** complete

## What I changed

The grey paragraph beside "Use Blizzard's buff frames" is gone. In its place is
an all-caps `ENABLE BUFFS` header and a red, clickable `[WORKAROUND]` link that
toggles a new full-height panel hung off the right edge of the config window.
The panel carries a title, a one-line statement, a close button and the nine
numbered steps; hovering a step opens a 420px-wide screenshot popout back over
the config window, with a caption underneath. All ten screenshots live in one
`SHOTS` table keyed exactly as the task specified, each with its `SetTexCoord`
crop and aspect, and a step names only a key. Separately, the spell picker now
withholds the buff categories entirely while `cvUseBlizzardBuffs == false` —
from the `buffs` source and from `all`, never from `essential`/`utility`/
`spellbook` — and the picker's empty message says why when that is the cause.
Ticking the checkbox refreshes the picker immediately.

## Files touched

| File | What |
|---|---|
| `ui/pages/CooldownViewerGuide.lua` | **New.** `SHOTS`, `STEPS`, the guide panel, the screenshot popout, and `Guide:CreateLink(panel)` which builds the `[WORKAROUND]` link |
| `ThugUI.toc` | Registers the new file immediately before `ui\pages\CooldownViewer.lua`, with a comment saying why the order is required |
| `ui/pages/CooldownViewer.lua` | Note replaced by header + link; guide built during `Page:Build`; `Page:RefreshPicker()` added to the checkbox's `set`; picker empty message now explains the withheld-buffs case |
| `modules/CooldownViewer/Data.lua` | New `Data.BuffsAvailable()`; `BuildSpellList` skips buff categories in `buffs` and `all` when it returns false, and suppresses the spellbook fallback in that case |
| `Tests/loadtest.lua` | Six new cases appended to the cooldown-viewer engine step list. No existing case touched |

## Verification

```
$ luac -p ui/pages/CooldownViewerGuide.lua ui/pages/CooldownViewer.lua \
        modules/CooldownViewer/Data.lua Tests/loadtest.lua
(no output — clean)
```

```
$ lua Tests/loadtest.lua .
ok         ui/pages/CooldownViewerGuide.lua
...
ok         page cooldownviewer
ok         page cooldownviewer fits (642px of 654px)
...
ok         buff categories are withheld while the workaround is off
ok         buff categories are offered when the setting is on or unset
ok         the other picker sources are untouched by the buff setting
ok         the buff workaround guide builds hidden and toggles
ok         hovering a step opens its screenshot, and step 1 opens none
ok         every screenshot a guide step names exists
...
-- secret probe --
ok         records a sample with readable values
ok         a secret power value is described, not read
ok         a secret aura struct does not throw
ok         a missing API is reported, not fatal
ok         a thin sample never buries a rich one

0 failure(s)
```

The non-scrolling layout assertion still passes and the guide panel does **not**
enter it — it is a child of `ThugUI.Window.frame`, not of the page host, so it
is not in `Page.panels`. The Cooldown Viewer page got *shorter* (642px of 654px;
it was over the old note's height before), so nothing was loosened.

## Tests added

Six, all appended to the end of the engine `steps` table in `Tests/loadtest.lua`.
Each was confirmed to fail by temporarily reverting the behaviour it covers and
re-running; every temporary edit was reverted and the suite is back at 0.

| Case | Confirmed by |
|---|---|
| `buff categories are withheld while the workaround is off` | Forced `Data.BuffsAvailable()` to `return true` (the old, ungated behaviour) → `STEP FAIL`, 1 failure |
| `buff categories are offered when the setting is on or unset` | Forced `Data.BuffsAvailable()` to `return ThugUI_Config.cvUseBlizzardBuffs == true` (the polarity mistake the task warns about) → `STEP FAIL`. It also cascaded 3 failures in the BlizzBuffs section, which is the same bug showing up downstream |
| `the other picker sources are untouched by the buff setting` | Forced `IsBuffCategory` to return true for every category → `STEP FAIL` |
| `the buff workaround guide builds hidden and toggles` | Not independently provable — see the caveat below |
| `hovering a step opens its screenshot, and step 1 opens none` | Removed the `#step.shots == 0` guard from `Guide:ShowShot` → `STEP FAIL  … a step with no screenshot still opened a popout` |
| `every screenshot a guide step names exists` | Typo'd `editModeTick` to `editModeTik` in a step → `STEP FAIL  … step 4 names a screenshot that does not exist: editModeTik` |

**Caveat on the "builds hidden" half.** I removed the `panel:Hide()` from
`Guide:Ensure()` and that case still passed: the frame stub's `__shown` starts
`nil`, so `IsShown()` already answers false for a frame that was never explicitly
hidden. The harness therefore cannot distinguish "hidden on purpose" from "never
shown". The *toggle* half of the case is real (it fails if `Toggle`/`Show`/`Hide`
break), and the reuse assertion is real. The starts-hidden half is only as good
as the stub. I did not change the stub to fix this — that is a harness change
outside this task's file list in spirit, and I would rather flag it than widen
the blast radius.

## Sources used

- `media/` directory listing — confirmed all ten `.tga` files named in the task's
  table exist on disk beside their `.png` originals. I did not touch either.
- `ui/pages/CooldownViewer.lua:305` — the existing media reference form
  (`marker:SetTexture("Interface\\AddOns\\ThugUI\\media\\Reticle_Dot")`), copied
  exactly rather than trusting the task's prose. My `MEDIA` constant is
  `"Interface\\AddOns\\ThugUI\\media\\"` and shots concatenate the bare filename.
- `modules/CooldownViewer/BlizzBuffs.lua:100-105` — `BB:IsEnabled()` reads
  `ThugUI_Config.cvUseBlizzardBuffs ~= false`. `Data.BuffsAvailable()` mirrors it
  deliberately so nil-means-on cannot drift between the two.
- No external lookups were needed. No wiki, no Blizzard source.

## Choices the task left to me

- **New file, and where.** `ui/pages/CooldownViewerGuide.lua`, listed in
  `ThugUI.toc` immediately **before** `ui\pages\CooldownViewer.lua`. It defines
  `CV.BuffGuide` at file scope and the page calls `CV.BuffGuide:CreateLink(misc)`
  and `:Ensure()` from `Page:Build`, so it must be defined first; it also uses
  `W.AttachTooltip`, so it must come after `ui\Widgets.lua`. The pages block was
  the only position satisfying both. The TOC comment says so. The page file was
  already 870 lines and the guide is ~330; folding it in would have made the
  page unreadable.
- **The panel is explicitly hidden on the window's `OnHide`,** not left to
  inherit. A WoW child is hidden *visually* with its parent but keeps its own
  shown flag, so re-opening settings would have dragged the guide back open with
  it. The task said "hidden again when the config window closes", which is what
  the explicit hook gives. I used the same `HookScript("OnHide", …)` idiom the
  page already uses for preview mode.
- **Arrows.** The task's step text uses `→`. I used `>` (`Options > Gameplay
  Enhancements > Cooldown Manager`) and `-` in place of the em dash inside step
  text, because I cannot confirm U+2192 is in the game font's glyph set and a
  missing glyph renders as a blank box. The repo does use `—` elsewhere
  (`Data.COLLAPSE_MODES`), so em dashes are known-safe; arrows are not. Easy to
  change back if the player prefers.
- **Two global frame names created**, both prefixed: `ThugUI_BuffGuidePanel` and
  `ThugUI_BuffGuideShot`. Not required — I named them so `/framestack` can
  identify them if the player ever needs to debug the layout.
- **Popout parented to the guide panel with `SetFrameStrata("DIALOG")`.** DIALOG
  is above the window's HIGH, so it draws on top; parenting it to the panel means
  it hides with the panel for free rather than needing its own teardown.
- **Popout reuses two texture objects**, hiding the unused one, because no step
  names more than two images.
- **Emphasis colour** inside step text is `|cffffd100` (gold), matching the
  colour the removed note used for `Tracked Buffs` / `Tracked Bars`.
- **Row heights** are computed from `text:GetStringHeight() + 6`, floored at 18 —
  the same trick `Widgets.Panel:Note` uses, so editing a line does not mean
  re-measuring the list by hand.

## Proposed docs changes

**`docs/DECISIONS.md`, new subsection under §13 (the BlizzBuffs section):**

> **The workaround's prerequisites are a guide, not a paragraph, and the picker
> enforces them.**
>
> Adopting Blizzard's buff item only works once the player has turned the
> Cooldown Manager on, ticked it in Edit Mode, set the frame's visibility, and
> put the buff in Tracked Buffs or Tracked Bars. ThugUI cannot do any of that for
> them (`C_CooldownViewer`'s only write is `SetLayoutData`, an opaque blob — §15),
> and every one of those omissions fails the same way: the cell is empty, in
> silence. That is indistinguishable from a broken addon, and it was reported as
> one.
>
> Two changes follow from that:
>
> - The prerequisites are now a panel of their own
>   (`ui/pages/CooldownViewerGuide.lua`), opened from a red `[WORKAROUND]` link
>   under the checkbox, with the player's own screenshots. It hangs off the
>   outside right edge of the config window so it never covers the page it is
>   describing. The screenshots are `.tga` on 512×512 power-of-two canvases with
>   the image at top-left, so **every one needs `SetTexCoord`** or the
>   transparent padding is drawn as part of the picture; the crop and aspect for
>   each live in one `SHOTS` table, and a step names only a key.
> - `Data.BuildSpellList` withholds the buff categories entirely while
>   `cvUseBlizzardBuffs` is off, from the `buffs` source and from `all`. An
>   option that offers a placement which provably cannot draw is worse than one
>   that explains itself, so the `buffs` entry stays in `Data.SOURCES` and the
>   picker's empty message names the setting instead. The spellbook fallback
>   ("this spec was never categorised, try another source") is suppressed in that
>   case — answering "tracked buffs" with the whole spellbook would be a second
>   silent failure on top of the first.
>
> `Data.BuffsAvailable()` reads `~= false` to mirror `BB:IsEnabled()` exactly.
> **nil means on.** Reading it as a plain truth test would empty the buff picker
> for every player who has never touched the setting, which is most of them.

**`docs/HANDOFF.md` §2, new rows (both unverified — I cannot launch the game):**

| Feature | State |
|---|---|
| Buff workaround guide panel + `[WORKAROUND]` link | **Unverified in game** — no texture, crop, size or anchor has been seen on screen |
| Picker withholds buff categories when the workaround is off | **Unverified in game** — logic covered by tests |

## Could not do

Nothing was blocked. The repo matched the task everywhere I checked: the note was
where §3a said it would be, `IsBuffCategory` and the `all` branch were as §3e
described, `Page.pickerEmpty` exists, and all ten `.tga` files are on disk.

One thing §3e asked me to check and the answer was "no": the checkbox's `set`
calls `Apply()`, and `Apply()` only calls `CV:Rebuild()` when the edited spec is
the active one or preview is on. It never reaches `Page:RefreshPicker()`. I added
the call, as instructed.

## Noticed but did not touch

- **`Data.BuildSpellList`'s `expand` local is now partly redundant.** In the
  `all` branch the expansion flag is `IsBuffCategory(categoryName)` and in the
  curated branch it is `expand`, which is true exactly when `source == "buffs"` —
  i.e. exactly when the category is a buff category. The two could collapse into
  one rule. Left alone; it is pre-existing shape and out of scope.
- **`BuildCooldownInfoCache` shadows `ids`** (`modules/CooldownViewer/Data.lua`,
  the inner `local ids = { info.spellID, … }` inside a loop over an outer `ids`).
  Harmless today, confusing to read. Pre-existing.
- **`Page:Build`'s `MakeCheck` closures call `Apply()` then `Page:Refresh()`**
  while the "This layout" checkboxes built via `Panel:Checkbox` call only their
  own `set`. Two different refresh conventions on one page. Pre-existing; I
  followed the local one (the buff checkbox's `set`) rather than unify them.
- **The `.png` originals in `media/` are untracked in git**, alongside the
  `.tga` files. That is how I found the tree and I changed nothing there, but the
  coordinator will want to decide whether the 6MB of PNGs belong in the repo
  before committing.
- **`ui/pages/CooldownViewer.lua` is 880 lines** and `Page:BuildInspector` is now
  doing four unrelated jobs. Not mine to split.

## Not verified

I cannot launch World of Warcraft. Everything below is **correct in code** and
has been seen by nothing but the test harness. The player must check each of
these on screen:

**Textures — the highest-risk area, because the harness never loads a file.**

1. Each of the ten screenshots actually loads. A missing or misnamed `.tga` draws
   nothing at all and reports nothing anywhere. The names in `SHOTS` were typed
   from the task's table and cross-checked against the directory listing, but a
   filename is not proven until the game reads it.
2. `SetTexCoord(0, u, 0, v)` frames each image correctly — no transparent
   padding on the right or bottom edge, and no part of the picture cropped off.
   These u/v values came from the task file; I did not measure them myself.
3. Each image's aspect is right, i.e. nothing is stretched or squashed at
   420px wide. The `buffsTab` shot is the tallest at ~575px; check it fits.
4. The `advButton` shot is used by **two** steps (6 and 8), per the task table.
   Confirm that is intended and reads sensibly in step 8's context.

**Panel geometry.**

5. Width **260** is enough for the step text. Nine steps at that width, with an
   18px number gutter, is the thing most likely to need adjusting.
6. The panel is full window height and the ninth step fits without running off
   the bottom. There is **no scroll bar** — if it overflows, it is simply cut.
7. `TOPLEFT` to the window's `TOPRIGHT` puts it fully on screen. The config
   window is `SetClampedToScreen(true)`; the panel is a child and is **not**
   separately clamped, so dragging the window to the right edge of the screen
   will push the guide off it.
8. The panel's backdrop and border read correctly against whatever is behind it.

**Popout.**

9. It opens to the **left** of the hovered row, over the config window, and is
   readable against it (dark backdrop plus tooltip border).
10. It draws **above** the config window, not underneath. It is `DIALOG` strata
    against the window's `HIGH`; the window is also `SetToplevel(true)`, which
    should not matter across strata but has not been observed.
11. Two-image steps (2, 5, 9) stack vertically with an 8px gap and the frame
    grows to fit both plus the caption.
12. The popout closes on leaving the row and does not flicker or stick when
    moving between adjacent rows.
13. Step 1 shows **no** popout at all when hovered (asserted in the harness, but
    only against a stub).
14. The popout is 444px wide against a 260px panel — confirm it does not extend
    past the left edge of the config window at any row.

**Link and header.**

15. `ENABLE BUFFS` renders in caps in the right place under the checkbox, and
    the "This layout" column still fits the window with the note removed.
16. `[WORKAROUND]` is legibly red and its mouseover highlight is visible. There
    is no hand cursor — a `FontString` cannot take one and neither can a plain
    `Button`; I used a highlight texture plus a text brighten instead.
17. Clicking it toggles the panel open and shut.
18. Closing the config window closes the guide, and re-opening settings does
    **not** bring the guide back with it.
19. The close button on the panel works and does not close the config window
    too.

**Picker gating.**

20. Unticking "Use Blizzard's buff frames" empties the Tracked buffs source and
    shows the new message naming the setting, rather than the generic text.
21. The list changes **immediately** on the tick, without reopening the page.
22. `Everything` loses its tracked buffs and keeps everything else when the
    setting is off.
23. Nothing already **placed** on the grid disappears when the setting is off —
    the gate is on the picker only, not on placements. I read the code as
    leaving placements alone, and no test covers a placed buff surviving the
    toggle, so this is worth a look.

**Text.**

24. The `>` separators and `-` dashes in the step text read acceptably. If the
    player wants `→`, it needs checking against the game font first.
