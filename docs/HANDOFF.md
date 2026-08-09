# Handoff — state as of 2026-08-08

Cold-start entry point. Read this, then `../CLAUDE.md`, then
`DECISIONS.md`.

The single most important thing on this page is the table in §2: several
changes are **correct in code but unverified in game**, because the author
cannot launch WoW. Do not assume they work, and do not assume they are broken.
§1 says how to find out from disk.

---

## 1. Check the evidence before doing anything

Two files on disk, both flushed only on `/reload` or logout:

```
WTF/Account/SQUAZZIL/SavedVariables/ThugUI.lua        settings + ThugUI_DebugLog
WTF/Account/SQUAZZIL/SavedVariables/!BugGrabber.lua   errors, stacks, locals
```

`ThugUI_DebugLog` is **always on** — no command needed. It has:

- `events` — per-session log (login, spec changes, cooldown cache size,
  migration results, once-only warnings)
- `state` — snapshot taken at logout, listing every placed icon as
  `cell  name  id=  mode=  linked=N  cat=`

**`linked=N` is the field that matters.** It is evidence of which code actually
ran. A version string tells you what is on disk; that number tells you what
executed. It exists because a fix was once pushed, not loaded, and the
behaviour was indistinguishable from the fix not working — a wrong conclusion
was reached and stated confidently. Do not repeat that.

Also: `lua Tests/replay_probe.lua <sv-path> . <spellID>` replays a real
`/thugcv probe` dump through the live code, which separates "our logic is
wrong" from "they were on an older build".

## 2. What is verified, and what is not

| Feature | State |
|---|---|
| Config window, pages, grid editor | **Verified** — in use |
| Per-spec grid, drag/click placement, anchor picker | **Verified** |
| Druid migration (Balance 102, Guardian 104, Resto 105) | **Verified** — player confirmed |
| Rows collapse | **Verified** |
| Proc glow + `proc` mode | **Verified** — "pistol shot is working" |
| Roll the Bones via `linkedSpellIDs` | **Code verified by replay, NOT verified in game** |
| Taint fix (ToT mover deferral) | **Unverified** — the big one, see §3 |
| Resource ring showing at all | **Unverified** — depends on the taint fix |
| Columns / both collapse | **Unverified in game** |
| Window layout reorganisation | **Unverified visually** |
| Always-on diagnostics | **Unverified** — first logout will show |

Everything unverified has test coverage; tests prove it does not error and the
logic is right, not that it looks right on screen.

## 3. The open thread: taint

This is the highest-value thing to resolve, because it gates two features.

`UnitPower` was returning a **secret number**, so the resource ring could not
compute a fill level:

```
attempt to perform arithmetic on local 'current' (a secret number value,
while execution tainted by 'ThugUI')
```

The wording says the secrecy follows **taint**, not a blanket restriction. A
taint source was found and fixed: `ToT:UpdateMoverGeometry` resized the ToT
mover while the protected oUF unit button was anchored to it, which is blocked
in combat, and the block taints the addon for the session. Both mover paths now
defer out of combat.

**To find out whether that worked:** play a fight, log out, then read
`ThugUI_DebugLog.events`.

- If `RING: UnitPower unreadable (secret value)` is **absent** → taint is gone,
  the resource ring should be tracking, and **combo point pips are unblocked**.
- If it is **present** → there is another taint source. Look for
  `ADDON_ACTION_BLOCKED` in BugGrabber; the oUF portrait element has also
  reported "tainted by ThugUI".

Do not build anything that depends on reading a power value until this is
settled. See `KNOWN-ISSUES.md`.

## 4. Queued work

**Combo point pips** — design agreed with the player, not started.

- N pips evenly spaced around the cursor ring, lit as points are gained.
- Chosen over a segmented arc because a changing max (Deeper Stratagem, procs)
  falls out for free, and per-point colour is needed for DK runes.
- Generalises to Holy Power, Soul Shards, Chi, Arcane Charges, Essence. oUF's
  vendored `classpower.lua` already maps class → power type; `runes.lua` is
  separate because runes have per-rune cooldowns rather than a count.
- **Blocked on §3.** `UnitPower` for combo points is secret in exactly the same
  way as energy.

**Category enumeration for 12.1** — see `UPCOMING-PATCH.md`. Category names are
hardcoded in three places and will silently drop the five new 12.1 categories.

## 5. The player's current setup

Four spec profiles exist. Outlaw (260) is the active testbed:

- anchor col 3, row 6; collapse `columns`; padding 6
- 8 icons, including Pistol Shot (185763) in `proc` mode and Roll the Bones
  (1214909) in `aura` mode at cell 5:8 — that last one is the unverified case
- Druid 102 / 104 / 105 hold the migrated legacy bars

Resto (105) is at scale 0.6, faithful to the old ECV, and so looks smaller than
the others. That is deliberate, and the player knows.

## 6. How this player wants to work

Recorded because it has been consistent and it matters more than any single
technical decision:

- **Confirm design before building anything large.** Present real options with
  trade-offs and a recommendation. They would rather answer a question than
  have the wrong thing built thoroughly.
- **Investigate before changing code.** They have said so explicitly. When they
  ask "did we do that right", answer from evidence on disk, not from reasoning
  about what the code should do.
- **Do not assume you are wrong because they are confused.** They have said
  this directly. Check, then answer plainly either way.
- Small obvious fixes: just do them.
