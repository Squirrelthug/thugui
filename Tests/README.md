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
