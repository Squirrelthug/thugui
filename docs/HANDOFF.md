# Handoff — state as of 2026-08-09

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
| Secret probe (`modules/SecretProbe.lua`) | **Ran 2026-08-09** — results in `DECISIONS.md` §12 |
| Combo pips | **Verified in game** 2026-08-09 — and they track live *in combat*, which was not expected |
| Blizzard buff items in grid cells (`BlizzBuffs.lua`) | **Verified working in game** 2026-08-09 — buff draws in the assigned cell, in combat. **But it breaks Edit Mode — see §3c** |
| Resource ring exact level in combat | **Permanently impossible** — measured. Energy is secret to addons and no blessed setter takes a secret for a radial swipe. A straight bar could; a ring cannot |
| Columns / both collapse | **Unverified in game** |
| Window layout reorganisation | **Unverified visually** |
| Always-on diagnostics | **Verified, after two faults were fixed** — see §3a |

Everything unverified has test coverage; tests prove it does not error and the
logic is right, not that it looks right on screen.

## 3. Closed: secret values, and why taint was a dead end

**Answered 2026-08-09. Do not chase the taint again.** The full
reasoning and the evidence are in `DECISIONS.md` §12; the short version:

Addon code always executes tainted by its own addon, so there is no untainted
state to reach and nothing to clean. `!BugGrabber.lua` shows four addons all
reporting "tainted by *themselves*" — they are the four that touch secret
values, not the four that are dirty — and Blizzard's generated docs flag the
**APIs**: `GetUnitAuraBySpellID` carries `RequiresNonSecretAura` (so it returns
nothing in combat) and `UnitPower` carries `SecretWhenUnitPowerRestricted`.

The buff icon and the ring were never broken by anything we did. A tainted
addon is not meant to be able to answer "is buff X up" in combat.

`modules/SecretProbe.lua` measured exactly what this client hands us, at five
points around combat, with no command to type — it **ran on 2026-08-09** and the
results are the table in `DECISIONS.md` §12. It is still installed and still
samples every session, so re-reading `ThugUI_DebugLog.secrets` after a patch is
a free way to see what changed.

The decisive line was `aura[1].spellId read`: the struct **can** be indexed and
the field **is** reachable — as a secret, and comparing it errors. So there is
no route to identifying a buff in combat from addon code, and Blizzard's own
frames were the only option left. That is what `BlizzBuffs.lua` now does, and it
works — see §3b.

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

## 3b. Buff icons in combat — SOLVED, by using Blizzard's frames

ThugUI's *own* aura icons still cannot draw in combat and never will: the game
will not tell an addon which aura is which while restrictions are in effect. The
by-spell lookups return nothing (`RequiresNonSecretAura`), the list returns
secret structs, and `aura.spellId` can be read but not compared. That part is
permanent and is not worth another session.

**What works instead, verified in game 2026-08-09:**
`modules/CooldownViewer/BlizzBuffs.lua` matches each aura-mode placement to the
item frame carrying the same `cooldownID` and anchors it over the cell. The buff
draws in the right place, during combat. `DECISIONS.md` §13 has the design and
the constraint the player has to satisfy for it to work (the buff must be in the
Tracked Buffs or Tracked Bars list — a bar lands in the cell as an icon plus its
animation, an icon lands as an icon plus a timer; both fit one cell, and the
player likes the bar visual as-is and does not want it enlarged).

The plan that got here, for the record:

1. ~~**Probe**~~ — ran 2026-08-09. Results in `DECISIONS.md` §12.
2. ~~**Adopt Blizzard's buff frames**~~ — built and working, one item per cell.
3. ~~Fall back to flagging the icons as combat-unavailable~~ — not needed.
4. ~~**Combo point pips**~~ — built and verified, and they track live in combat.

**The remaining cost:** with collapse on, an adopted cell is now always
reserved, buff up or not, because we cannot ask whether it is up. And Edit Mode
breaks — §3c.

## 3c. The current open thread: Edit Mode windows vanish

**This is where the work stands. Start here.** Full detail, suspect list and the
free first test are in `KNOWN-ISSUES.md` → "Edit Mode cooldown windows vanish
after combat".

The one-paragraph version: adopting Blizzard's buff items into grid cells
*works* — the buff draws in the right cell, in combat, which is the thing three
sessions were spent trying to reach. But during or after combat the Essential
Cooldowns window and its tracked buff / tracked bar tabs stop appearing in Edit
Mode, as though the Cooldown Manager had been switched off. On leaving combat
the live buff was seen to flash back at its default Edit Mode position and
vanish instantly.

Two things make this tractable rather than mysterious:

- We touch exactly four things on Blizzard's frames, and they are listed in
  `BlizzBuffs.lua`. The strongest suspect is `SetFrameStrata`/`SetFrameLevel`
  on the Edit Mode **system** frame, and second is calling their own
  `RefreshLayout` from our stack when releasing.
- `EssentialRings.lua:926` *also* moves `BuffIconCooldownViewer` in combat and
  calls `UpdateSystem` / `EditModeManagerFrame.LayoutApplied` on the way out.
  **If `anchorBuffFrameToCursor` is on, two features are fighting over one
  frame.** Test that before writing any code — it is free.

Ask for one reload and read `!BugGrabber.lua` for `ADDON_ACTION_BLOCKED` naming
ThugUI alongside EditMode or the cooldown viewer. That names the culprit
outright.

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

**A note on the tracked-buff picker — agreed with the player, not built.** The
buff icon only appears if that buff is in one of the game's two *active*
Cooldown Manager lists, and which list decides what it looks like:

| List | What lands in the cell |
|---|---|
| **Tracked Buffs** | icon with a countdown timer |
| **Tracked Bars** | icon with an animated bar beside it |
| Neither | nothing to adopt — the cell stays empty |

Both lists are in the same Essential Cooldowns window, on different tabs. The
picker in ThugUI's own config gives no hint of this, so a buff chosen there can
silently do nothing. Put the explanation next to the tracked-buff list in
`ui/pages/CooldownViewer.lua`. Reasoning is recorded in `DECISIONS.md` §13.

**Category enumeration for 12.1** — see `UPCOMING-PATCH.md`. Category names are
hardcoded in three places and will silently drop the five new 12.1 categories.

## 5. The player's current setup

Four spec profiles exist. Outlaw (260) is the active testbed:

- anchor col 3, row 6; collapse `columns`; padding 6
- 8 icons, including Pistol Shot (185763) in `proc` mode and Roll the Bones
  (1214909) in `aura` mode — now drawn by Blizzard's adopted item and
  **confirmed working in combat**
- Druid 102 / 104 / 105 hold the migrated legacy bars
- **Combo pips are on**, and the player moved the grid's cursor anchor further
  out to make room for them, having found the pips drew underneath the grid.
  They then asked for a tighter pip ring, which is why the offset slider reaches
  -80. Do not "fix" the anchor distance; it is a deliberate choice.
- The player keeps Roll the Bones in the **Tracked Buffs** list (icon plus
  timer) rather than Tracked Bars, having tried both. They liked the bar visual
  and want it available, at one cell, unenlarged — see `DECISIONS.md` §13.

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
