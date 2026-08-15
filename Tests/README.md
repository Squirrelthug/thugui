# ThugUI tests

## loadtest.lua

Stubs the WoW API, loads every Lua file listed in `ThugUI.toc` **in TOC order**,
then builds and refreshes each config-window page and drives the cooldown-viewer
engine through migration, placement, anchoring, preview and the legacy toggle.

```sh
lua Tests/loadtest.lua .
```

Exits non-zero on failure. Not referenced by the TOC, so the game ignores it.

### What it catches

Load-order mistakes, file-scope nil-indexing, typos in function names, and
runtime errors on the paths it drives. It is a smoke test, not a behaviour
suite — it will not tell you whether an icon is in the right place, only that
asking for one does not error.

## replay_probe.lua

Replays a real `/thugcv probe` dump from SavedVariables through the **live**
`Data.lua` and reports what the cooldown-info cache actually resolves for a
spell. Only the game APIs are faked, and they are fed from the player's own
dump — the addon logic under test is the real thing.

```sh
lua Tests/replay_probe.lua \
  "<...>/WTF/Account/<ACCOUNT>/SavedVariables/ThugUI.lua" . 1214909
```

It prints every Cooldown Manager entry carrying that spell, which one the cache
picks, its linked spells, and whether the spell reaches the tracked-buffs
picker.

Use it when a spell is not behaving as expected and you want to know whether
the addon's *logic* is wrong or the player was simply running an older build —
that distinction cost a full round of debugging on Roll the Bones, whose entry
appears twice with different linked-spell lists.

### Caveats

- The interpreter is whatever `lua` resolves to (Lua 5.5 here); WoW runs 5.1.
  The harness patches the differences it needs, e.g. `unpack`. Real 5.1-only
  syntax would still slip past, so this does not replace loading the addon.
- The frame stub only synthesises `Capitalised` keys as methods, because a real
  frame returns `nil` for an unset plain field and code such as
  `f.navButtons or {}` depends on that fallback being reachable.

## Hazards in the harness itself

Each of these let a wrong thing pass, or a right thing fail, at least once.

**A stub that is more permissive than the client proves nothing.** `SetCooldown`
in this file used to accept secret values where the real client refuses them
(`DECISIONS.md` §19), so no test could have caught the bug that was actually
shipping. When you add a stub, model the ways the real API *fails*, not only the
way it succeeds.

**The secret stub does not throw on a nil comparison.** `_G.__SECRET` is a plain
table, so `SECRET > 0` and `1 - SECRET` raise genuine Lua errors exactly as the
client does — but `SECRET == nil` quietly returns `false`, where the client
throws. **Code that nil-tests a value before asking `issecretvalue` will pass
here and fail in the game.** Use `Readable()` in `Core.lua`, which asks
`issecretvalue` first; do not hand-roll the test.

**A case that fails leaks state into the next one.** `error()` inside a step
unwinds past that step's own trailing cleanup, so a shared `_G.__*` stub table
that is only reset at the bottom is left dirty for whatever runs next — which can
make a later, unrelated case pass for the wrong reason. Task 14 hit this: two
cases passed against deliberately reverted code. **Reset shared stub state at the
START of a case**, not only at the end.

**A case can silently depend on the case before it.** Steps run in order against
shared state, so a test that omits its own setup may be reading an icon the
previous test placed. Task 15 hit this: `"an adopted cooldown cell is kept out of
combat"` inherited its icon, and when the case above it was deleted as obsolete
the survivor kept passing while asserting something about a cell that was no
longer adopted. **Green does not mean the name is still true.** If you delete or
change a case, run the suite and read what its neighbours are actually doing.

**A stub written from the code under test proves nothing about the game.** The
`ItemLocation` stub took the equipment slot as its only argument, matching the
caller — which had forgotten that Blizzard declares
`ItemLocation:CreateFromEquipmentSlot` with a **colon**. Eight cases went green
over an item path that could not work in the client (`DECISIONS.md` §22). Write
stubs from Blizzard's source, and where a call convention matters, declare the
stub so that getting it wrong *fails*.

**`replay_probe.lua` must not carry its own copy of a game enum.** Its category
list was a hardcoded copy of 12.0's four categories, so after 12.1 it reported
"the spell is not indexed at all" for a trinket that indexes fine — a specific,
plausible, false diagnosis from the one tool whose job is telling you whether
your logic or the client is at fault. It now derives categories from the dump.
Anything the real input already describes should be read from it, never restated.

**`GetHeight`/`GetWidth` used to ignore `SetHeight`/`SetWidth`.** They returned a
flat `100` whatever the code had set, so a frame's size was **unobservable** and
a whole class of layout assertion simply could not be written. The scroll-height
bug in `Window:BuildPage` — a multi-panel scrolling page sized from only its
first panel, leaving a taller column's bottom rows unreachable — sat behind that
blind spot with no test able to see it. Fixed 2026-08-13: `SetWidth`/`SetHeight`/
`SetSize` record, and the getters report what was recorded, falling back to `100`
for a frame nobody sized. **When a getter cannot see what its setter did, the gap
is not neutral — it is a region of the code no test can describe.**

**`SetTexture` recorded nothing, so a drawn icon's texture was unobservable.**
It fell through the shared frame stub's generic no-op branch and vanished, and
only `icon.baseTexture` — a plain field, not a frame method — could be checked.
Closed 2026-08-13 (task 19) by recording it alongside the existing
`SetVertexColor`/`SetAlpha` recorders, which is what let the potion-repaint bug
get a real assertion on `icon.tex`. Exactly the same shape as the
`GetHeight`/`GetWidth` gap above, and it had gone unnoticed because nothing
before task 19 needed to tell two textures on one icon apart.

**`EnableMouse` was swallowed, so "does this frame take input" was
unobservable.** The same shape as the two gaps above: it fell through the generic
no-op branch, and the only way to describe the cooldown grid's mouse behaviour
was to assert on the profile table instead — which tests the setting, not the
frame. Closed 2026-08-15 (task 20) by recording it as `frame.__mouse`, which is
what let the locked-grid fix get a real assertion.

**A test that identifies a widget by its index in `panel.widgets` is a
tripwire.** `"the misc panel drops the Blizzard-buffs checkbox"` asserted
`#misc.widgets == 1` and drove `widgets[1]`. Task 20 added a second checkbox to
that panel and the case failed — while everything it was written to protect was
still true. Rewritten 2026-08-15 to find checkboxes by `widget.labelText` (added
to `Panel:Checkbox` for exactly this). **Assert on the thing you named in the
test's title**; a proxy for it will fail on unrelated changes and, worse, will be
"fixed" by whoever hits it next.

**The stub synthesises every Capitalised key as a truthy no-op**, so
`item.GetSpellCategoryIcon` reads as *present* on a bare stub even when it was
never defined — which is useless for testing a fallback that only runs when a
method is **absent**. Use `rawset(frame, "MethodName", false)` to reproduce a
genuinely missing method; plain `nil` or leaving it undefined will not work.
Task 19 needed this, and `SetRadialProgressBarReverse` already did.

**Deliberately deleted on 2026-08-13, when the Cooldown resource ring was
removed** (`DECISIONS.md` §27). Listed so the drop in coverage is visible rather
than looking like tests that quietly wandered off:

| Case | Why it went |
|---|---|
| `arc matches the resource fraction` | Asserted the Cooldown path's seed-and-Pause arithmetic. Nothing computes a fraction any more — the engine derives the fill from the raw value/max pair. Replaced by `the resource level reaches the bar unmodified`, which asserts both arrive unchanged |
| `setting off keeps the Cooldown implementation` | Both the setting and the implementation are gone |
| `flipping the setting swaps frame type without reusing the old one` | There is nothing left to flip between |
| `radial setting on but StatusBarRenderMode absent falls back to Cooldown` | The contract changed rather than vanished — there is no fallback now. Replaced by `StatusBarRenderMode absent: no ring, and no throw` |

**The radial texture API is exercised nowhere but here.** An exhaustive search of
Blizzard's own live 12.1 source found **zero** uses of `StatusBarRenderMode.Radial`,
`SetRenderMode`, or any `SetRadialProgressBar*` method. The stub always provides
`SetRadialProgressBarReverse` and `SetRadialProgressBarStartOffset`, so the cases
that matter are the two that remove them (`no SetRadialProgressBarReverse: no
throw, ring still draws` and `no SetRadialProgressBarStartOffset: falls back to
rotation, no throw`). **Green on this family is weaker evidence than usual — only
the game settles it.**

The one thing the game *has* now settled: `SetRadialProgressBarReverse` is
confirmed present on a live client, from the absence of its guard's `LogOnce`
line across a whole session (`DECISIONS.md` §23). `SetRadialProgressBarStartOffset`
has not been confirmed the same way and is assumed present by family.

**The stub records; it does not simulate.** `__radialStartOffset` is the value we
passed, not where the ring actually starts. The harness cannot tell you Blizzard
measure that offset from the **bottom** — that came from their generated docs,
after the ring shipped starting at 6 o'clock with four green tests over it. A
stub that only echoes arguments can never catch a wrong convention, only a wrong
call.

## What the harness does not load at all: `libs/oUF/`

`loadtest.lua` builds no oUF environment, and there are no stubs for
`UnitIsConnected`, `UnitIsVisible` or `UnitGUID`. **Nothing under `libs/oUF/` has
any coverage**, including the two things ThugUI actually depends on it for
(Target of Target, and the portrait element).

This matters because oUF is vendored **under our name**, so anything it touches
is attributed to ThugUI and any error it throws reports as ours
(`DECISIONS.md` §12). A bug in there looks exactly like a bug in our code.

The secret-value fix to `elements/portrait.lua` (2026-08-13) is therefore
**verified only by reading and by `luac -p`** — it is a ThugUI local patch,
marked as such in the file, and it has no regression test. Closing this would
mean teaching the harness to load oUF's addon-namespace files (`local _, ns = ...`)
and stubbing the unit-state API. That is real work and nobody has judged it worth
doing for a vendored library; the honest state is recorded here rather than left
looking like coverage that exists.
