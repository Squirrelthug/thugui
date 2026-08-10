# 12 — Remove the Raid Frames module entirely — report

**Status:** complete

## What I changed

Deleted the `RaidFrames` module (`modules/RaidFrames/Core.lua`,
`modules/RaidFrames/Settings.lua`, the now-empty `modules/RaidFrames/`
directory, and `ui/pages/RaidFrames.lua`), then removed every reference to it:
the two `.toc` file lines and the page line, the `rf*` defaults block in
`modules/EssentialRings.lua`, the `ThugUI.RaidFrames:Initialize()` call, the
`Raid Frames` feature-table row and `ER:CreateRaidFramesPanel(category)` call
in `modules/EssentialRings_Settings.lua`, the `Raid Frames` row in
`ui/pages/About.lua`, and the stale `FrameHider.lua` note. Each comment that
cross-referenced "the raid frames" ("same arrangement", "same deal", "off by
default for the same reason") was reworded to stand on its own, per the task.
`libs/oUF/`, `ER.CreateScrollablePanel`/`ER.CreateSeparator`, the
`rfCorner*`/`rfScale*` Reforestation locals in `EssentialRings_Settings.lua`
(~946-1180), `core.lua:75`'s `RAID = true`, and `Tests/loadtest.lua`'s
`RAID_CLASS_COLORS` stub were all left untouched, as instructed.

## Files touched

| File | What |
|---|---|
| `modules/RaidFrames/Core.lua` | Deleted |
| `modules/RaidFrames/Settings.lua` | Deleted |
| `modules/RaidFrames/` | Deleted (directory, now empty) |
| `ui/pages/RaidFrames.lua` | Deleted |
| `ThugUI.toc` | Removed the raid-frames comment block and both file lines; removed the page line; reworded the Target of Target load comment to stand alone |
| `modules/EssentialRings.lua` | Removed the `rf*` defaults block (was lines 383-427); removed the `ThugUI.RaidFrames:Initialize()` call and its comment; reworded the Target of Target defaults comment and the ToT init comment to stand alone |
| `modules/EssentialRings_Settings.lua` | Reworded the `CreateScrollablePanel`/`CreateSeparator` comment to name `TargetOfTarget/Settings.lua` instead of the deleted `RaidFrames/Settings.lua`; removed the `Raid Frames` features-table row; removed `ER:CreateRaidFramesPanel(category)` |
| `ui/pages/About.lua` | Removed the `Raid Frames` feature row. Left the oUF credit line alone |
| `modules/FrameHider.lua` | Replaced the stale note (which named the now-deleted module) with one recording the real history: tooltip fix lived here, moved to ThugUI's own raid frames, those raid frames are now gone too because the tooltip problem is solved outside ThugUI |

## Verification

```
$ luac -p modules/EssentialRings.lua modules/EssentialRings_Settings.lua ui/pages/About.lua modules/FrameHider.lua
(no output, exit 0)
```

`ThugUI.toc` is not Lua and was not run through `luac`; it was checked by
`Tests/loadtest.lua`, which parses it directly to build the file list.

```
$ lua Tests/loadtest.lua .
...
-- pages --
ok         page cooldownviewer
ok         page orbanchors
ok         page framehider
ok         page cursorrings
ok         page targetoftarget
ok         page about
ok         page cooldownviewer fits (632px of 654px)

-- engine --
... (81 cases, all ok)

-- resource ring --
... (8 cases, all ok)

-- blizzard buff items --
... (21 cases, all ok)

-- combo pips --
... (11 cases, all ok)

-- secret probe --
... (5 cases, all ok)

0 failure(s)
```

Full tail matches the pasted-in-order output above; exit code was 0 and the
final line read `0 failure(s)`.

**Count dropped from the 160/six-sections baseline to 156, as anticipated by
the task file. Explained, not glossed over:**

`Tests/loadtest.lua` does not hardcode a file list or a page list — it parses
`ThugUI.toc` directly (`LoadTOC`, `Tests/loadtest.lua:361-373`) for the first
section's `ok <file>` lines, and iterates `ThugUI.Window.pages` (populated by
whichever page files actually loaded) for the `-- pages --` section
(`Tests/loadtest.lua:445-453`). Removing the raid-frames files from the `.toc`
and deleting `ui/pages/RaidFrames.lua` mechanically removed four `ok` lines
that used to exist purely because those files were there to load and register
a page — not because any assertion about raid-frame *behaviour* was deleted:

- `ok modules/RaidFrames/Core.lua`
- `ok modules/RaidFrames/Settings.lua`
- `ok ui/pages/RaidFrames.lua`
- `ok page raidframes`

No other case disappeared. `RAID_CLASS_COLORS` (`Tests/loadtest.lua:234`) is
untouched and still present as the oUF stub it always was.

```
$ grep -rn "RaidFrames\|rfEnabled\|CreateRaidFramesPanel" --include=*.lua . | grep -v "^./libs/"
./modules/TargetOfTarget/Core.lua:201:    -- Deliberately NOT `ThugName`: RaidFrames:RefreshFrames walks every oUF
```

One hit, outside `tasks/`, not anticipated by the task file — see "Noticed but
did not touch" below. It is a comment only; no executable reference to
`RaidFrames` remains anywhere in the addon outside `libs/`.

## Tests added

None. This task removes dead, disabled code (`rfEnabled = false` in the live
SavedVariables) and adds no new behaviour, so there is nothing to regress that
a new case would catch. The four `ok` lines that disappeared are explained
above rather than replaced.

## Sources used

None needed — this was a mechanical removal following the task file's exact
line references, not a Blizzard-API question.

## Proposed docs changes

`docs/DECISIONS.md` — wherever the Raid Frames module's original rationale is
recorded (its "why we built our own oUF raid frames" entry, if one exists):
add a closing note that the module was removed 2026-08-10 because the
tooltip-over-buff-icon problem it existed to solve is now handled outside
ThugUI, and `ThugUI_Config.rfEnabled` was already `false` in the player's
SavedVariables, so the removal is a no-op for anything currently drawn.

`docs/HANDOFF.md` — could note, next time it's touched, that the Raid Frames
module and its config page are gone; nothing in the "verified vs not" table
referenced it by name so no row needs editing.

## Could not do

Nothing was blocked. One thing outside my authorized file list needed a
decision rather than a fix — see below.

## Noticed but did not touch

`modules/TargetOfTarget/Core.lua:201-202` — a comment reads:

```lua
-- Deliberately NOT `ThugName`: RaidFrames:RefreshFrames walks every oUF
-- object and treats a frame carrying that key as one of its raid buttons.
self.ThugToTName = name
```

This is a live reference to `RaidFrames:RefreshFrames`, caught by the task's
own mandated grep (`grep -rn "RaidFrames\|rfEnabled\|CreateRaidFramesPanel"`),
which the task file said should produce **zero** hits outside `tasks/` and
told me to stop and report rather than decide if something turned up. It is
purely a comment — `self.ThugToTName` itself is untouched and functionally
unaffected, so nothing here changes behaviour or breaks anything — but the
rationale it documents (avoiding a field-name collision with a module that no
longer exists) is now stale. `modules/TargetOfTarget/Core.lua` was not in this
task's "Files you may modify" list, so I left it as-is rather than editing it.
Worth a follow-up: reword the comment to drop the dead reference (or simply
note that `ThugName` is avoided as a matter of oUF-object-scanning hygiene in
general, without naming a specific module).

## Not verified

Everything — this task cannot be confirmed in the running game, and the task
description itself states the module was already inert (`rfEnabled = false`)
so there is nothing to observe changing. Specifically unverified:

- That deleting the module produces zero visible change in the actual client
  (expected per the task's own premise, not observed).
- That the config window still opens and every remaining page still renders
  correctly in game (the test harness drives `ThugUI.Window:CreateWindow()`
  and `SelectPage` against a stub, not the real game).
- That `/reload` with these files removed does not throw anything the stub
  environment can't reproduce (e.g. real `Settings.RegisterCanvasLayoutCategory`
  behaviour).
