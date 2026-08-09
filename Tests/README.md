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
