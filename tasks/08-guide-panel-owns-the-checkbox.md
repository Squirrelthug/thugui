# 08 — The guide panel owns the checkbox, and gains a step

Read `00-AGENT-BRIEF.md` first.

Four changes to the buff workaround guide, all specified by the player. You are
implementing, not designing. Baseline: `5ccf767`, `lua Tests/loadtest.lua .` →
**0 failures**.

Files you may modify:
- `ui/pages/CooldownViewerGuide.lua`
- `ui/pages/CooldownViewer.lua`
- `Tests/loadtest.lua`
- `tasks/reports/08-report.md`

---

## 1. Move the checkbox into the guide panel

`ui/pages/CooldownViewer.lua`, in `Page:BuildInspector`, the `misc` panel
currently holds two checkboxes: "Show proc glow" and "Use Blizzard's buff
frames".

**"Use Blizzard's buff frames" moves out of the main window and into the guide
panel**, at the top of the panel, immediately below the grey intro text and
above step 1. "Show proc glow" stays exactly where it is.

Carry its behaviour across unchanged — it is already correct:

```lua
get = function() return ThugUI_Config.cvUseBlizzardBuffs ~= false end,
set = function(v)
    ThugUI_Config.cvUseBlizzardBuffs = v
    if ThugUI.CooldownViewer.BlizzBuffs then
        ThugUI.CooldownViewer.BlizzBuffs:Refresh()
    end
    Apply()
    Page:RefreshPicker()
end,
```

`Apply()` and `Page:RefreshPicker()` are locals/methods of the page file. The
guide panel is a different file, so route through whatever the guide already
uses to reach the page, or expose a single function from the page and call that.
**Do not duplicate the body.** Say in your report which route you took.

Keep the existing tooltip on the checkbox.

The checkbox must show the live setting whenever the panel is shown — if the
value changed elsewhere, opening the panel shows the current state. There is a
`Refresh` on the widget (`enabledCB:Refresh()` style, see `Page:Refresh`); wire
the guide's copy the same way.

## 2. Rewrite the grey intro text

The panel's existing intro line is replaced with, verbatim except where noted:

> The buff icon in any given cell is owned and PROTECTED by Blizzard. Below are
> the game settings needed before ThugUI is able to BORROW these assets from
> Blizzard's UI.

Two deliberate departures from what the player dictated, and **only** these two:
`icons ... is` → `icon ... is`, and `Blizzards` → `Blizzard's`. Keep `PROTECTED`
and `BORROW` capitalised — that emphasis is the point of the sentence.

## 3. Add the visibility step

A screenshot has been added and converted; **do not re-convert anything**.

| Key | File (in `media/`, no extension) | u | v | aspect |
|---|---|---|---|---|
| `visibility` | `tracked_buffs_settings_window_with_visibility_dropdown_highlighted_and_arrows_to_both_correct_options` | 0.7227 | 1.0000 | 0.723 |

Add it to `SHOTS`, then add a step to `STEPS` **after** the Buffs-tab step and
**before** the final "Done" step:

- Text: choose one of the two visibility options the arrows point at, on the
  tracked buff settings window. Say why it matters — the icon is pulled from
  that frame, so a frame that is not displayed has nothing to pull. Keep it to
  two short sentences; the picture carries the rest.
- `shots = { "visibility" }`
- A caption in the style of the others.

**Then remove the duplicated sentence.** The step that shows `clickToEdit` +
`advButton` currently also tells the player to set the frame to Always or In
Combat. That instruction now belongs to the new step and must not be stated
twice. Trim that sentence out of the earlier step and leave the rest of it
alone.

## 4. Centre the popout on its step row

Currently `Guide:ShowShot` ends with:

```lua
popout:SetPoint("TOPRIGHT", row, "TOPLEFT", -8, 0)
```

so a tall popout hangs downward from the row and a two-image step is badly off.
The player wants the popout **vertically centred on the step row it belongs to**.

```lua
popout:SetPoint("RIGHT", row, "LEFT", -8, 0)
```

**Do not hardcode per-step offsets.** The player asked for hardcoded values
assuming the combined height of a stacked pair had to be measured by hand — it
does not. The popout is already sized to its contents before this line runs, and
anchoring `RIGHT` to `LEFT` centres whatever height it ended up with, including
two stacked images of different heights. It is exact, it needs no table of
numbers, and it cannot drift when the UI scale changes. Note in your report that
you did it this way and why, so the coordinator can put it to the player.

The caption box is anchored `TOPRIGHT` to the popout's `TOPLEFT`. Leave that —
it should stay top-aligned with the images, not centred on the row.

## 5. Tests

Add to `Tests/loadtest.lua`:

- The guide's checkbox reads `true` when `cvUseBlizzardBuffs` is `nil`, `true`
  when `true`, `false` when `false`. **`nil` means ON** — inverting this silently
  empties the buff picker for anyone who never touched the setting.
- Toggling the guide's checkbox writes `ThugUI_Config.cvUseBlizzardBuffs` and
  the picker list changes accordingly.
- The main window's `misc` panel no longer builds a "Use Blizzard's buff frames"
  checkbox, and still builds "Show proc glow".
- Every `SHOTS` key named by a step exists — the existing case must now cover
  `visibility` too.
- No step mentions the visibility instruction twice (assert the Always/In Combat
  wording appears in exactly one step's text).

**Do not delete or rewrite an existing case.** If one must change, leave it and
put the before/after under **"Existing tests I believe need to change"** in your
report. This has already gone wrong once on this project.

## 6. Gate

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Paste the tail. Any failure is one you caused.

## 7. What you cannot claim

You cannot launch the game. Everything visual — the checkbox looking right in
its new home, the panel still fitting at 260 wide with a checkbox added, the
centred popout not running off the top or bottom of the screen for the first and
last steps — goes in **Not verified**. Be exhaustive.
