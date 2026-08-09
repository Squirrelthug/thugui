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
| Roll the Bones via `linkedSpellIDs` | **Verified in game** 2026-08-09 — `4 linked, active via 1214933` |
| Taint fix (ToT mover deferral) | **Verified INSUFFICIENT** 2026-08-09 — taint persists, see §3 |
| Resource ring showing at all | **Still blocked** — `UnitPower` is secret again |
| Columns / both collapse | **Unverified in game** |
| Window layout reorganisation | **Unverified visually** |
| Always-on diagnostics | **Verified, after two faults were fixed** — see §3a |

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

**Answered 2026-08-09: it did not work.** The line is present, 5 seconds into a
fresh session, before any combat:

```
[00:34:46] RING: UnitPower unreadable (secret value) for ENERGY
           — addon is tainted; resource level cannot be computed
```

So the ToT mover deferral was **not** the only taint source, and the ring and
the combo point pips both stay blocked. What the evidence now says:

- It taints within seconds of login, with no combat and no mover resize, so the
  remaining source is on a **login path**, not a combat one.
- `ADDON_ACTION_BLOCKED` for `ThugUI_TargetOfTargetMover:SetSize()` has **not**
  recurred since session 82 — that fix did hold, it just was not sufficient.
- The oUF `portrait.lua:46` "tainted by ThugUI" error recurred in session 90.
  oUF is vendored under our name, so anything it touches is attributed to us.
  **That is the next thread to pull**, not the mover.

### 3a. The diagnostics themselves were broken until 2026-08-09

Worth knowing, because it invalidates earlier conclusions drawn from silence:

- The state snapshot was taken **only at `PLAYER_LOGOUT`**, when
  `GetSpecializationInfo` already returns 0. Every snapshot ever written
  described an empty `Spec 0` profile with no icons, so `linked=N` — the field
  this page calls load-bearing — had never once been recorded. Now captured on
  `PLAYER_REGEN_ENABLED` / `PLAYER_ENTERING_WORLD`, and a capture with an
  unreadable spec cannot overwrite a good one.
- `/thugcv status` printed to chat only. WoW's `/chatlog` does **not** capture
  it: that logs chat *events*, and `print()` writes to the frame without firing
  one. Status output now also goes to `ThugUI_DebugLog`.

An empty `ThugUI_DebugLog` before this date means "not loaded or not captured",
never "nothing happened".

Do not build anything that depends on reading a power value until this is
settled. See `KNOWN-ISSUES.md`.

## 3b. Buff icons do not draw in combat — probably the same bug

Tracked in `KNOWN-ISSUES.md`. Recorded here because it changes what §3 is
worth: the taint is no longer just blocking the resource ring and the combo
point pips, it is the leading explanation for `aura`-mode icons never drawing
in combat either.

If that holds, untainting fixes **three** features at once, and it stops being
a nice-to-have. Chase the oUF `portrait.lua` lead before building anything new.

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
