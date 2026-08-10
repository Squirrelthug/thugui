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
| Taint fix (ToT mover deferral) | **Held, but irrelevant to secrets** — see §3 and `DECISIONS.md` §12 |
| Secret probe (`modules/SecretProbe.lua`) | **Built 2026-08-09, awaiting one fight + reload** |
| Resource ring showing at all | **Still blocked** — `UnitPower` is secret again |
| Columns / both collapse | **Unverified in game** |
| Window layout reorganisation | **Unverified visually** |
| Always-on diagnostics | **Verified, after two faults were fixed** — see §3a |

Everything unverified has test coverage; tests prove it does not error and the
logic is right, not that it looks right on screen.

## 3. The open thread: secret values — and taint was a dead end

**Resolved as a diagnosis, 2026-08-09. Do not chase the taint again.** The full
reasoning and the evidence are in `DECISIONS.md` §12; the short version:

Addon code always executes tainted by its own addon, so there is no untainted
state to reach and nothing to clean. `!BugGrabber.lua` shows four addons all
reporting "tainted by *themselves*" — they are the four that touch secret
values, not the four that are dirty — and Blizzard's generated docs flag the
**APIs**: `GetUnitAuraBySpellID` carries `RequiresNonSecretAura` (so it returns
nothing in combat) and `UnitPower` carries `SecretWhenUnitPowerRestricted`.

The buff icon and the ring were never broken by anything we did. A tainted
addon is not meant to be able to answer "is buff X up" in combat.

`modules/SecretProbe.lua` now measures exactly what this client hands us, at
five points around combat, with no command to type. Read
`ThugUI_DebugLog.secrets` after a fight and a reload. **The pivotal line is
`aura[1].spellId read`**: if a secret aura struct can still be indexed, a
native mapping might drive an icon without us reading it; if it errors, using
Blizzard's own `BuffIconCooldownViewer` frames is the only route left.

The historical account below is kept because it explains how the wrong
conclusion was reached, and the description of behaviour *while* restricted is
still accurate.

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

## 3b. Buff icons do not draw in combat — same cause, and by design

Tracked in `KNOWN-ISSUES.md`. It is the same restriction as the ring, but the
fix is not "untaint": there is nothing to untaint. The by-spell aura lookups
return nothing to addon code while auras are restricted, which is precisely
what `RequiresNonSecretAura` means.

Agreed plan, 2026-08-09, in order:

1. **Probe** (built) — one fight, one reload, read `ThugUI_DebugLog.secrets`.
2. **Adopt Blizzard's own buff frames** behind the existing grid, so the icons
   work the way the documentation says they can. `EssentialRings.lua:930`
   already parks `BuffIconCooldownViewer` at the cursor, so the idiom exists.
3. If that fails, park buffs and mark those icons visually as unavailable in
   combat rather than leaving them silently blank.
4. **Combo point pips**, built now against the 12.1 relaxation of secondary
   resources so they work on 12.1 launch day.

## 4. Queued work

**Combo point pips** — **built 2026-08-09**, `modules/ComboPips.lua`, off by
default. Controls are on the Cursor Rings page.

- N pips evenly spaced around the cursor ring, lit as points are gained.
- Chosen over a segmented arc because a changing max (Deeper Stratagem, procs)
  falls out for free, and per-point colour is needed for DK runes.
- Covers combo points, Holy Power, Soul Shards, Chi, Arcane Charges, Essence.
  Which resource comes from a class table mirroring oUF's `classpower.lua`, but
  the per-spec conditions are deliberately *not* copied: `UnitPowerMax` returns
  0 for a spec without the resource, so gating on the maximum is self-
  correcting. The druid is the one exception and uses oUF's test (primary power
  is energy ⇒ cat form).
- Not covered: DK runes (per-rune cooldowns, different widget) and oUF's
  aura-backed pseudo-resources (Hunter, Shaman, Devourer) — those read auras,
  which is the thing addons cannot do in combat.
- **Live behaviour depends on the patch.** Secondary resources are secret on
  12.0.7, so in combat the pips freeze at their last count; 12.1 is expected to
  make them readable and the same code then tracks live. Verified in the test
  harness both ways; **unverified in game**.

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
