# Task 12 — Remove the Raid Frames module entirely

Read `00-AGENT-BRIEF.md` first.

## Why this is being removed

ThugUI shipped its own oUF party/raid frames for exactly one reason: the player
could not get rid of the tooltip that appeared when they moused over their own
buff icons in the cells of Blizzard's default raid frames. Owning the frames
meant owning the aura icons, and an icon we create never gets a tooltip wired to
it.

That problem is now solved outside ThugUI, so the whole module is dead weight.
This addon *enhances* the default UI; it should not be in the business of
managing unit frames.

**The module is already inert in the live game.** `ThugUI_Config.rfEnabled` is
`false` in the player's SavedVariables, so nothing here is drawing today.
Deleting it must therefore produce **zero visible change**. If your change would
alter anything the player currently sees, you have gone too far — stop and
report.

## Delete these files

```
modules/RaidFrames/Core.lua
modules/RaidFrames/Settings.lua
modules/RaidFrames/          <- the directory itself, once empty
ui/pages/RaidFrames.lua
```

## Then remove every reference to them

### 1. `ThugUI.toc`

Remove the raid-frames comment block and both file lines (currently lines
35–38):

```
# Raid frames: Core defines ThugUI.RaidFrames, Settings hangs its panel off the
# helpers exported by EssentialRings_Settings, so both come after those.
modules\RaidFrames\Core.lua
modules\RaidFrames\Settings.lua
```

and the page line (currently line 83):

```
ui\pages\RaidFrames.lua
```

The `# Target of target, same arrangement:` comment immediately below the
deleted block refers back to it with "same arrangement". Reword that comment so
it still reads correctly on its own now that the block it referenced is gone.

### 2. `modules/EssentialRings.lua`

**a.** Remove the whole `rf*` defaults block, currently lines 383–427 — from the
`-- Raid Frames (modules/RaidFrames, built on oUF)` comment down to and
including `rfHideBlizzardRaidFrames = true,`. Stop there. The next comment,
`-- Target of Target (modules/TargetOfTarget, built on oUF)`, and everything
after it stays.

That Target of Target comment says "Off by default for the same reason as the
raid frames" — reword it so the reason is stated rather than cross-referenced.

**b.** Remove the initialise call, currently lines 2276–2280:

```lua
        -- Raid frames wait on PLAYER_ENTERING_WORLD internally: the secure
        -- header must not be spawned before the roster exists.
        if ThugUI.RaidFrames then
            ThugUI.RaidFrames:Initialize()
        end
```

The `ThugUI.TargetOfTarget` block just below it opens with "Same deal as the
raid frames:" — reword it to stand alone. Keep the block itself.

### 3. `modules/EssentialRings_Settings.lua`

**a.** Line ~184, fix this comment — `RaidFrames/Settings.lua` will not exist,
but `TargetOfTarget/Settings.lua` still uses both helpers, so the two exports
themselves **must stay**:

```lua
-- Shared with modules/RaidFrames/Settings.lua so its panel is laid out with the
-- same helpers as the rest of the ThugUI options, not a second set that drifts.
ER.CreateScrollablePanel = CreateScrollablePanel
ER.CreateSeparator = CreateSeparator
```

**b.** Line ~224, remove this entry from the `features` table:

```lua
        {"|cffffffffRaid Frames|r", "ThugUI party/raid frames with tooltip-free, click-through auras"},
```

**c.** Line ~276, remove the panel construction call:

```lua
        ER:CreateRaidFramesPanel(category)
```

### 4. `ui/pages/About.lua`

Line ~20, remove the feature entry:

```lua
        { "Raid Frames",     "oUF party/raid frames with click-through auras." },
```

**Leave the oUF credit at line ~58 alone.** oUF stays vendored — see traps.

### 5. `modules/FrameHider.lua`

Lines 70–72 are a note that now points at a module that will not exist:

```lua
-- NOTE: The raid-frame aura tooltip anchor fix that used to live here has been
-- removed. ThugUI now ships its own raid frames (modules/RaidFrames), which own
-- their aura icons outright and simply never wire a tooltip to them.
```

Replace it with a note that records the real history, because this is the one
piece of context that explains why `FrameHider` no longer touches tooltips and
why nothing should re-add it casually. Say, in your own words: a tooltip-anchor
fix for Blizzard's compact-frame auras used to live here; it was dropped when
ThugUI shipped its own raid frames; those raid frames have since been removed
too, because the tooltip problem is now handled outside ThugUI.

## Traps — each of these will break something if you get it wrong

- **`libs/oUF/` stays.** `modules/TargetOfTarget/Core.lua` is built on it. Do
  not delete, prune, or touch the vendored library.

- **`ER.CreateScrollablePanel` and `ER.CreateSeparator` stay.**
  `modules/TargetOfTarget/Settings.lua:121-122` uses both. Only the *comment*
  above them is wrong.

- **Not every `rf` prefix is a raid frame.** `EssentialRings_Settings.lua`
  lines ~946–1180 contain locals named `rfCornerLabel`, `rfCornerDropdown`,
  `rfCornerLabels`, `rfCornerOrder`, `rfScaleLabel`, `rfScaleSlider`,
  `rfScaleValue`. Those are **Reforestation** controls on the legacy ECV panel
  and they read `ThugUI_Config.ecvReforestationCorner` / `ecvReforestationScale`.
  **Do not touch any of them.** The legacy ECV/BCV/GCV bars are a deliberately
  preserved fallback. A blind `rf*` sweep is the obvious way to do this task and
  it is wrong.

- **`core.lua:75` `RAID = true` is unrelated** — a group-type table entry. Leave
  it.

- **`Tests/loadtest.lua:234` `RAID_CLASS_COLORS` stays.** It is a stub the
  vendored oUF reads. Removing it breaks the harness for Target of Target.

- **Do not touch SavedVariables.** WoW is running, so any edit would be
  overwritten on logout anyway. The leftover `rf*` keys in `ThugUI_Config` are
  inert once nothing reads them; leaving them costs nothing and preserves the
  player's settings if this is ever reverted.

- **Do not renumber the config window pages.** Removing `order = 50` leaves a
  gap between Cursor Rings (40) and Target of Target (60). Gaps are fine; the
  orders are sparse by design.

## Verify before reporting

Both are required, and paste the real output into your report:

```sh
luac -p <every .lua file you edited>
lua Tests/loadtest.lua .
```

The harness baseline is **160 passing across six sections, 0 failures**. After
this change the count may legitimately drop if any case exercised the raid
frames — if it does, say so explicitly and name which cases went and why.
**Failures are not acceptable.** A drop in passing count must be explained, not
glossed over.

Also confirm by grep that no live reference survives:

```sh
grep -rn "RaidFrames\|rfEnabled\|CreateRaidFramesPanel" --include=*.lua . | grep -v "^./libs/"
```

Expect **no** hits outside `tasks/`. If something turns up that this file did
not tell you about, **stop and report it** rather than deciding what to do.

## House rules for this task

- Leave the work **uncommitted**. The coordinator reviews the diff and commits.
- **Do not edit anything in `docs/`.** Draft any doc-worthy note into your
  report instead; the coordinator merges it by hand.
- Do not run state-changing git commands. `git status` / `git diff` are fine.
- Write your report to `tasks/reports/12-report.md`. No report file means the
  task did not happen.

Your report must state, plainly:

1. Every file deleted and every file edited.
2. The `luac -p` and `loadtest` output, pasted.
3. The grep result.
4. Anything you found that this task file did not anticipate.
