# Task 16 — A second resource ring, drawn on a radial StatusBar

Read `00-AGENT-BRIEF.md` first.

Give the resource ring a second implementation that can show the player's exact
resource level **during combat**, which the current one provably cannot. Both
implementations ship. The player chooses between them with a setting.

## Background — why this is now possible

`docs/KNOWN-ISSUES.md`, "Resource ring cannot show an exact level in combat", and
`docs/DECISIONS.md` §20. **Do not re-derive any of this from documentation; it is
measured, and where measurement and documentation disagreed, measurement won.**

`UnitPower("player", …)` returns a **secret number** in combat while
`UnitPowerMax` returns a plain one. A fraction needs `current / maximum`, and
arithmetic on a secret throws — as does comparing one. The current ring is a
`Cooldown` widget, and `Cooldown:SetCooldownDuration(secret)` is **refused**.
That was measured on 12.0.7 and again, verbatim, on 12.1.

The measurement was right; the conclusion drawn from it — *"a straight bar could
show exact energy where a ring cannot"* — was wrong. It treated *radial* as a
property of the `Cooldown` widget, which was the only radial thing in the API at
the time.

**12.1 added `StatusBarRenderMode.Radial`:** *"Render the status bar by driving
the managed texture's radial progress fill percent instead of resizing the
texture anchors."* And both of these carry
`SecretArguments = "AllowedWhenTainted"` in
`Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua` on the
`live` branch, **and** were measured accepted mid-combat from our tainted stack:

- `StatusBar:SetValue(value)`
- `StatusBar:SetMinMaxValues(minValue, maxValue)`

So the engine computes the fill from values we are never allowed to read:

```lua
f:SetMinMaxValues(0, maximum)   -- plain
f:SetValue(current)             -- secret, accepted
```

No arithmetic. No comparison. That is the entire point, and any change that
reintroduces either defeats it.

## The player's two decisions, already made

1. **Both implementations ship, selected by a setting.** The existing ring is not
   deleted, not rewritten, and stays the default. It works and is in daily use.
2. **The radial ring must look identical to the current one** — same texture,
   same size, same rotation and start position. The only visible difference
   should be that it tracks the real level in combat instead of freezing.
   **If radial fill cannot reproduce the current look, STOP and report it.** Do
   not ship something that looks different and describe it as a match.

## Change 1 — the setting

New flat key in `ThugUI_Config`, defaulted in `modules/EssentialRings.lua`
alongside the other `resourceRing*` keys (~line 356): **`resourceRingRadialBar`,
default `false`.**

Flat, not nested, because every other `resourceRing*` key is flat — see
`DECISIONS.md` §1 for which store and why. Do not create a third store.

Default `false` on purpose: nothing about the player's current display changes
until they choose it. **Do not change the default**, and do not change any
existing default.

A checkbox on the Cursor Rings page (`ui/pages/CursorRings.lua`), next to the
existing `showResourceRing` / `resourceRingVisibility` controls at ~lines
143–160, matching their surrounding style. Flipping it must rebuild the ring —
the two implementations are different frame types and the old frame cannot be
reused.

**Capability gate.** If `Enum.StatusBarRenderMode` is absent, or the frame has no
`SetRenderMode` method, the radial path must not be taken **whatever the setting
says** — fall back to the existing `Cooldown` ring and log it once through
`ThugUI.Diagnostics:LogOnce`. A player on an older client must get a working
ring, not a broken one.

## Change 2 — the radial implementation

Everything in `modules/ResourceRing.lua` that is not the frame itself is shared
and must stay shared: `GetPowerType`, `GetColor`, `ShouldShow`, the event driver.
**Do not fork the module.** Branch at the frame.

### Creation

`CreateFrame("StatusBar", …)` instead of `CreateFrame("Cooldown", …)`, then
`SetRenderMode(Enum.StatusBarRenderMode.Radial)` and `SetStatusBarTexture` with
the same `media\Ring_Main` the Cooldown path uses. Keep the same parent, the same
anchor to `ThugUI_CursorFrame`, and the same strata — the comment at
`ResourceRing.lua:107` explains why it is anchored rather than parented, and that
reasoning is unchanged.

**The global frame name must differ** from `ThugUI_RESOURCE_RING`. Two frames
under one global name is exactly what broke Edit Mode in `DECISIONS.md` §15, and
here both can exist in one session if the setting is flipped.

### Update

On the radial path:

- `SetMinMaxValues(0, maximum)` then `SetValue(current)`, every update.
- **No `lastFraction` short-circuit.** The existing one exists to avoid
  re-seeding a sweep; it compares a computed fraction, and on this path there is
  no fraction to compute and nothing may be compared. Call `SetValue`
  unconditionally.
- **Never call `GetValue()`.** `SetValue` carries
  `SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }`, so a bar fed a
  secret hands one back. Nothing needs to read it; make sure nothing does.
- **The whole `unreadable` branch at `ResourceRing.lua:194–225` has no
  equivalent here** and must not be copied. It exists because the Cooldown path
  cannot compute a fraction from a secret. This path never computes one. Do not
  port the frozen-ring fallback, the `lastFraction = 1` seed, or the
  `power-secret` log line.
- **`maximum` still needs screening before the one comparison that remains.**
  `if maximum <= 0 then hide` is a comparison, and a secret `maximum` would throw
  — screen it with `issecretvalue` **first**, nil second, and when it is
  unreadable skip the test and feed both values to the bar. (`UnitPowerMax` was
  measured plain, so this is a guard, not an expected path.)
- Colour is `SetStatusBarColor(r, g, b, a)`, not `SetSwipeColor`. Same
  `GetColor(powerToken)` source and the same `resourceRingAlpha` default of
  `0.55`. The power *token* is never secret, so the existing
  "only recolour when the token changed" optimisation is safe to keep.

### Geometry — the part most likely to defeat this

`SyncGeometry` currently calls `f:SetSize(cast:GetSize())` and
`f:SetRotation(ER:ClockToRadians(castRotation))`. `SetRotation` is a `Cooldown`
method; a `StatusBar` has no equivalent, and the closest thing is rotating the
managed texture (`f:GetStatusBarTexture():SetRotation(…)`).

**Whether that rotates the radial fill's start angle, or merely rotates the
artwork under a fill that still starts where it always did, is unknown and cannot
be determined from the harness or from source.** Attempt the match. Then say
plainly in your report which of these you achieved:

1. Identical — same start angle, same direction, same artwork orientation.
2. Artwork matches but the fill starts or runs differently.
3. Could not reproduce the look at all.

**2 and 3 are acceptable outcomes to report and unacceptable outcomes to hide.**
The player asked to be told rather than shipped a near-miss.

## Verify

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Baseline is **195 passing, 0 failures**. It must not go down.

You will need a `StatusBar` stub. **Write it from Blizzard's generated
documentation, never from the code you are testing.** `DECISIONS.md` §22: the
`ItemLocation` stub was written to match its caller instead of the game, and
eight cases went green over a code path that could not work in the client. That
was found by the player, in game, after being reported as fixed.

Specifically, the stub must:

- accept a secret in `SetValue` / `SetMinMaxValues` without throwing, because the
  real ones do (`AllowedWhenTainted`, and measured);
- **throw on comparison and arithmetic against a secret**, as `_G.__SECRET`
  already does — see `Tests/README.md`, "Hazards in the harness itself";
- record what it was handed so a test can assert it.

Add cases covering:

1. With the setting off, the ring is still the `Cooldown` implementation and
   behaves exactly as it does today. **This is the regression test that matters
   most** — the player's daily display must not move.
2. With the setting on, a **secret** `UnitPower` reaches `SetValue` and nothing
   throws. The load-bearing case.
3. With the setting on and `Enum.StatusBarRenderMode` absent, the ring falls back
   to the `Cooldown` implementation and still draws.
4. Flipping the setting replaces the frame rather than reusing one of the wrong
   type.
5. A secret `maximum` does not reach the `<= 0` comparison.
6. Colour still follows the power token on the radial path.

**Add cases. Never rewrite an existing one in place.** Before claiming a test
proves anything, run it against the **unmodified** files and confirm it fails.
State the exact failing assertion in your report. Reset shared `_G.__*` stub
state at the START of each case, not only at the end.

## Boundaries

- **Do not delete, rewrite or "tidy" the `Cooldown` implementation.** It is the
  fallback and it is the default. `CLAUDE.md` §3, "Never break the fallback".
- Do not change any existing default, or the meaning of any existing setting.
- Do not reuse the global frame name.
- Do not touch `modules/CooldownViewer/`.
- Do not attempt the combo pips, the cast ring, or the GCD ring. Out of scope
  even though they are neighbours.
- Do not edit anything in `docs/`. Draft proposed entries into your report.
- Do not run any state-changing git command. Leave the work uncommitted on branch
  `radial-resource-ring`.

## Report

Write `tasks/reports/16-radial-statusbar-resource-ring.md`. **No report file
means the task did not happen.**

Include the diff in prose, the before/after test output with the exact assertion
that failed against the unmodified code, **which of the three geometry outcomes
above you reached**, what you wrote the StatusBar stub from, and **anything in
this task file that turned out to be wrong** — on four previous tasks that was
the most useful section in the report.
