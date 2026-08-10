# 07 — The buff workaround deserves its own panel

Read `00-AGENT-BRIEF.md` first.

This is a **UI build**, not a bug fix. The player specified it; you implement it.
Where this file leaves a detail open it says so — take the obvious option and
record the choice in your report.

---

## 1. Why this exists

Adopting Blizzard's buff frames is a workaround for a game restriction, and it
only works if the player has done four things in *Blizzard's* UI that ThugUI
cannot do for them. Today that is one paragraph of grey text next to a checkbox,
and the failure is silent — an empty cell looks exactly like a broken addon.

The player has taken screenshots of the whole process. This task turns them into
a guide.

## 2. The images — already converted, do not re-convert

WoW does not load PNG. The originals in `media/*.png` are kept as source; ten
`.tga` files have been generated beside them on 512×512 power-of-two canvases
with the image anchored **top-left** and the remainder transparent.

That means **every one of these needs `SetTexCoord`**, or you will draw the
padding. Use this table verbatim:

| Key | File (in `media/`, drop the `.tga`) | u | v | aspect |
|---|---|---|---|---|
| `options` | `blizzard_menu_with_gameplay_enhancements_highlighted` | 1.0000 | 0.7871 | 1.270 |
| `cdmOption` | `blizzard_menu_with_cooldown_manager_highlighted` | 0.9980 | 0.7871 | 1.268 |
| `escMenu` | `blizzard_escape_menu_with_edit_mode_highlighted` | 0.5059 | 1.0000 | 0.506 |
| `editModeTick` | `HUD_edit_mode_with_cooldown_manager_box_checked_and_highlighted` | 0.8906 | 1.0000 | 0.891 |
| `clickToEdit` | `buff_bar_with_click_to_edit_printed_on_bar` | 0.3594 | 0.1836 | 1.957 |
| `advArrow` | `HUD_edit_mode_with_arrow_to_advanced_options` | 1.0000 | 0.7227 | 1.384 |
| `advButton` | `Tracked_buff_settings_window_with_Advanced_Cooldown_Settings_button_highlighted` | 0.7266 | 1.0000 | 0.727 |
| `buffsTab` | `advanced_cooldown_settings_window_with_buffs_tab_highlighted_and_both_the_tracked_buffs_and_tracked_bars_areas_highlighted` | 0.7305 | 1.0000 | 0.730 |
| `asIcon` | `buff_as_icon_with_counter` | 0.6094 | 0.4883 | 1.248 |
| `asBar` | `buff_as_icon_with_timer_bar` | 0.6992 | 0.5352 | 1.307 |

Texture path: `Interface\AddOns\ThugUI\media\<file>` — no extension, backslashes,
matching how `media/` art is already referenced elsewhere in this addon. Check an
existing reference and copy its form exactly rather than trusting this line.

Draw each with `tex:SetTexCoord(0, u, 0, v)` and size it from `aspect`: pick a
display width, height is `width / aspect`.

**Put the table in one place** — a single `SHOTS` table keyed as above, near the
top of the new file. A step names a key; nothing else knows about texture paths.

## 3. What to build

### 3a. Replace the note next to the checkbox

`ui/pages/CooldownViewer.lua` around line 751 currently has a `misc:Note(...)`
paragraph. It goes. In its place, under the existing "Use Blizzard's buff
frames" checkbox:

- A header line, **all caps**, reading `ENABLE BUFFS`.
- Beneath it, `[WORKAROUND]` in red, which is **clickable** and opens the panel
  in §3b. Make it obviously clickable: red (`|cffff2020` or a red `SetTextColor`),
  and a highlight on mouseover. A hand cursor is not available for a FontString,
  so use a `Button` sized to the text.

Keep the checkbox itself exactly where it is and leave its tooltip alone.

### 3b. The guide panel

A panel that **toggles** on clicking `[WORKAROUND]`:

- Anchored to the **outside right edge of the config window**, `TOPLEFT` to the
  window's `TOPRIGHT`, so it does not cover the page.
- **Full window height.** Width **260**. Not wide — the player was explicit.
- A title, a one-line statement of what this is, the numbered steps, and a close
  button. Steps are a compact vertical list; each is a hoverable row.
- Hidden by default, and hidden again when the config window closes.
- Built once, shown/hidden thereafter. **Never `SetParent(nil)`** — brief §5.

The panel is a child of the config window frame (`ThugUI.Window.frame`), so it
inherits show/hide for free. Confirm that is what happens; if the window hides
its content some other way, match it.

### 3c. The screenshot popout

Hovering a step row shows its screenshot. Build your own frame; do not fight
`GameTooltip`, which cannot size an arbitrary texture usefully.

- One reusable frame, anchored `TOPRIGHT` to the hovered row's `TOPLEFT` (so it
  opens back over the config window, never off the right of the screen).
- Displays the step's image(s) at **width 420**, height from `aspect`. A step
  with two images stacks them vertically with a small gap, and the frame grows
  to fit.
- A caption line under the image(s), from the step's `caption` field.
- Hidden on leave. Give it a solid dark backdrop and a border — it sits over the
  config window and must be readable against it.
- Frame strata above the config window so it is not drawn underneath.

### 3d. The steps

Keep the words short — the picture carries the idea. Text below is the intent,
not sacred; tighten it if you can without losing meaning.

| # | Text | Images | Caption |
|---|---|---|---|
| 1 | **Tick "Use Blizzard's buff frames"** above. This only tells ThugUI to use their frames — it turns nothing on in the game. Steps 2-7 are the game's own settings. | — | — |
| 2 | **Options → Gameplay Enhancements → Cooldown Manager.** Turn the Cooldown Manager on. | `options`, `cdmOption` | Game Menu, then Gameplay Enhancements, then Cooldown Manager |
| 3 | **Esc → Edit Mode.** | `escMenu` | Edit Mode lives in the game menu |
| 4 | **Tick Cooldown Manager** in the Edit Mode panel. | `editModeTick` | The frames only exist once this is ticked |
| 5 | **Click the buff frame** to edit it. | `clickToEdit`, `advArrow` | Click the frame itself, then Advanced Options |
| 6 | **Advanced Cooldown Settings.** | `advButton` | The button at the bottom of the frame's settings |
| 7 | **Buffs tab — drag the buff into Tracked Buffs or Tracked Bars.** Either list works. ThugUI can only place a buff that is in one of them. | `buffsTab` | Both lists are highlighted. Drag any buff you want on the grid into one of them |
| 8 | **Set that frame to Always or In Combat.** The icon is pulled from that frame, so if it is not displayed there is nothing to pull. | `advButton` | Visibility is on the same settings panel |
| 9 | **Done.** The buff arrives in your cell exactly as the default UI draws it — Tracked Buffs gives an icon with a timer, Tracked Bars gives an icon with its bar. | `asIcon`, `asBar` | The same buff, as an icon and as a bar, sitting in a ThugUI cell |

Step 1 has no image; the row must still render and simply show no popout.

### 3e. Gate the picker

A tracked buff cannot work while the feature is off, so it must not be offered.
In `Data.BuildSpellList` (`modules/CooldownViewer/Data.lua`):

- When `ThugUI_Config.cvUseBlizzardBuffs == false`, **skip buff categories**.
  There is already an `IsBuffCategory(categoryName)` helper and the `all` branch
  already calls it — use it, do not write a second test.
- This applies to source `"buffs"` (which then yields nothing) **and** to
  `"all"`. It must not touch `essential`, `utility` or `spellbook`.
- Do not delete the `buffs` entry from `Data.SOURCES`. An option that vanishes
  is a worse bug report than one that explains itself.
- The picker's existing empty-list message must say *why* when this is the
  cause — "Tracked buffs need Use Blizzard's buff frames" or similar — rather
  than the generic empty text. `Page.pickerEmpty` in `ui/pages/CooldownViewer.lua`.

Toggling the checkbox must refresh the picker so the list changes immediately.
The checkbox's `set` already calls `Apply()`; check whether that reaches
`Page:RefreshPicker()` and add the call if it does not.

## 4. Files you may modify

- `ui/pages/CooldownViewer.lua`
- `modules/CooldownViewer/Data.lua`
- `Tests/loadtest.lua`
- **A new file** for the guide panel, if it keeps the page file readable — your
  call. If you add one it must be listed in `ThugUI.toc`; read the ordering
  comments there before choosing a position, and say in your report where you
  put it and why.
- `tasks/reports/07-report.md`

Do not touch `media/`. The `.tga` files are generated and correct.

## 5. Tests

`Tests/loadtest.lua`. The harness builds every page, so a construction error
fails loudly on its own — that is not enough on its own here.

Add cases for:

- Buff categories are absent from `BuildSpellList("buffs", nil)` and from
  `BuildSpellList("all", nil)` when `cvUseBlizzardBuffs == false`, and present
  when it is `true` or `nil` (**nil means on** — the module's `IsEnabled` reads
  `~= false`; getting this backwards silently empties the picker for a player
  who has never touched the setting).
- `essential`, `utility` and `spellbook` are unchanged by the flag.
- The guide panel builds, starts hidden, and shows on click.
- Every `SHOTS` key referenced by a step exists in the table. A typo'd key would
  otherwise draw a blank frame in game and nowhere else.

**Do not delete or rewrite an existing case.** If one must change, leave it and
put the before/after under a heading **"Existing tests I believe need to
change"** in your report. This has already gone wrong once on this project.

## 6. Verification gate

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Baseline is **0 failures** at `cbe88c3`. Paste the tail.

The harness asserts non-scrolling pages fit inside `Window.CONTENT_HEIGHT`
(`ui/Window.lua:37`). The guide panel is a child of the window rather than of the
page, so it should not enter that check — if it does, say so rather than
loosening the assertion.

## 7. What you cannot check, and must not claim

You cannot launch the game, so you cannot see whether a texture loads, whether
`SetTexCoord` framed it correctly, or whether 260 is wide enough. Say "correct in
code". List every visual thing the player must confirm in your report's **Not
verified** section — that list is the point of this build, so be exhaustive.
