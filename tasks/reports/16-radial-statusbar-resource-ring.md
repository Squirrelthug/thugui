# 16 — A second resource ring, drawn on a radial StatusBar — report

**Status:** complete (correct in code and in the harness; unverified in game — see below)

## What I changed

`modules/ResourceRing.lua` now has two frame implementations behind one shared
module: the existing `Cooldown`-widget ring (unchanged behaviour, still the
default) and a new `StatusBar` ring rendered in
`Enum.StatusBarRenderMode.Radial`. `RR:EnsureFrame()` picks between two lazily
created, independently cached frames (`RR.cooldownFrame` / `RR.radialFrame`)
based on the new `resourceRingRadialBar` setting, swapping `RR.frame` /
`RR.frameKind` and hiding whichever frame is not active — never destroying
either. `RR:Update()` now dispatches to `RR:UpdateCooldown` (the old body,
moved verbatim) or the new `RR:UpdateRadial`, which calls
`SetMinMaxValues(0, maximum)` / `SetValue(current)` unconditionally, with no
fraction computed and no `lastFraction` short-circuit, and never calls
`GetValue()`. `GetPowerType`, `GetColor`, `ShouldShow` and the event driver
are untouched and shared by both paths.

A capability gate (`Enum.StatusBarRenderMode` present **and** the created
frame having a `SetRenderMode` method) decides whether the radial frame can
even be built; if not, it is cached as unsupported, hidden, logged once via
`ThugUI.Diagnostics:LogOnce`, and every subsequent `EnsureFrame` call falls
back to the Cooldown ring regardless of the setting.

`modules/EssentialRings.lua` gained the new flat default
`resourceRingRadialBar = false` next to the other `resourceRing*` keys.
`ui/pages/CursorRings.lua` gained a checkbox next to "Show:" that flips the
setting and calls `ThugUI.ResourceRing:Update()`, which is enough to trigger
the swap (`EnsureFrame` already re-evaluates the setting on every call).

`Tests/loadtest.lua` gained a real `StatusBar` stub — `SetRenderMode`,
`SetStatusBarTexture`, `SetMinMaxValues`, `SetValue`, `SetStatusBarColor`,
`GetStatusBarTexture` (returns a persistent object, not a fresh stub each
call), `GetValue` (echoes back whatever `SetValue` was handed, secret or
not), and `SetRotation` on the returned texture — plus
`Enum.StatusBarRenderMode = { Linear = 0, Radial = 1 }`, and six new test
cases appended to the existing "resource ring" step list.

## Files touched

| File | What |
|---|---|
| `modules/ResourceRing.lua` | Second frame implementation, capability gate, dispatch in `Update`/`SyncGeometry`/`EnsureFrame` |
| `modules/EssentialRings.lua` | New default `resourceRingRadialBar = false` (~line 363) |
| `ui/pages/CursorRings.lua` | New checkbox on the Cursor Rings page |
| `Tests/loadtest.lua` | `StatusBar` stub methods, `Enum.StatusBarRenderMode`, 6 new test cases |

## Verification

```
$ luac -p modules/ResourceRing.lua modules/EssentialRings.lua ui/pages/CursorRings.lua Tests/loadtest.lua
(no output — all four passed)
```

```
$ lua Tests/loadtest.lua .
...
ok         setting off keeps the Cooldown implementation
ok         radial setting on: a secret power reaches SetValue without throwing
ok         radial setting on but StatusBarRenderMode absent falls back to Cooldown
ok         flipping the setting swaps frame type without reusing the old one
ok         radial: a secret maximum skips the <= 0 comparison
ok         radial: colour still follows the power token
...
0 failure(s)
```

201 passing (195 baseline + 6 new), 0 failures. The pre-existing "resource
ring" cases (`initialize`, `arc matches the resource fraction`,
`power type follows the game by default`, etc.) all still pass unchanged —
they exercise `RR.frame` with the setting at its default (`false`), so they
continue to run against the Cooldown implementation exactly as before.

## Tests added

Six cases, appended to the existing `steps` table in the "resource ring"
block of `Tests/loadtest.lua` (never rewritten, only appended to):

1. `setting off keeps the Cooldown implementation`
2. `radial setting on: a secret power reaches SetValue without throwing` (the load-bearing case)
3. `radial setting on but StatusBarRenderMode absent falls back to Cooldown`
4. `flipping the setting swaps frame type without reusing the old one`
5. `radial: a secret maximum skips the <= 0 comparison`
6. `radial: colour still follows the power token`

**Confirmed all six fail against the unmodified files.** I copied the working
tree to a scratch directory, restored `modules/ResourceRing.lua`,
`modules/EssentialRings.lua` and `ui/pages/CursorRings.lua` to their `git
show HEAD:` content (leaving the new `Tests/loadtest.lua`, with its new stub
and new cases, in place), and ran `lua Tests/loadtest.lua <scratch>`. Result:
195 pass, 6 fail — exactly the six new cases, with these exact assertions:

```
STEP FAIL  setting off keeps the Cooldown implementation
           Tests/loadtest.lua:2530: setting off did not use the Cooldown ring, got nil
STEP FAIL  radial setting on: a secret power reaches SetValue without throwing
           Tests/loadtest.lua:2549: setting on did not switch to the radial ring
STEP FAIL  radial setting on but StatusBarRenderMode absent falls back to Cooldown
           Tests/loadtest.lua:2573: did not fall back to the Cooldown ring, got nil
STEP FAIL  flipping the setting swaps frame type without reusing the old one
           Tests/loadtest.lua:2593: did not start on the Cooldown ring
STEP FAIL  radial: a secret maximum skips the <= 0 comparison
           Tests/loadtest.lua:2617: did not take the radial path
STEP FAIL  radial: colour still follows the power token
           Tests/loadtest.lua:2639: radial ring never called SetStatusBarColor
6 failure(s)
```

(Line numbers are from the modified `loadtest.lua`; `RR.frameKind` is simply
`nil` against the unmodified module, since that field does not exist there —
which is exactly the signal that these cases test the new code, not
coincidence.)

The scratch copy was deleted after the check; no state-changing git command
was used to produce it (`git show HEAD:<path>` only).

## Sources used

- `gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua?ref=live"` —
  confirmed `SetValue`, `SetMinMaxValues`, `SetStatusBarColor` all carry
  `SecretArguments = "AllowedWhenTainted"` with a `SecretArgumentsAddAspect`;
  `SetRenderMode` and `SetStatusBarTexture` are `"AllowedWhenUntainted"`
  (irrelevant here since we only ever pass them plain values); `GetValue` and
  `GetMinMaxValues` carry `SecretReturnsForAspect = { BarValue }`, confirming
  the "never call GetValue" instruction is not paranoia — it really does hand
  back a secret.
- `gh api ".../SimpleStatusBarConstantsDocumentation.lua?ref=live"` — confirmed
  `StatusBarRenderMode.Linear = 0`, `.Radial = 1`, used verbatim in the
  `Enum` stub.
- `gh api ".../SimpleTextureBaseAPIDocumentation.lua?ref=live"` — confirmed
  `Texture:SetRotation(radians, normalizedRotationPoint)` exists as a real
  method (also `AllowedWhenTainted`, not that this path ever passes it a
  secret — `castRotation` is a plain config number), which is what
  `SyncGeometry`'s radial branch calls via `GetStatusBarTexture()`.
- `docs/DECISIONS.md` §20 (including the 21:05 measured subsection) and §22 —
  read as instructed, not re-derived. Nothing in this task contradicts either.
- `docs/KNOWN-ISSUES.md`, "Resource ring cannot show an exact level in
  combat" — read as instructed.

## Geometry outcome: **could not determine — this is outcome 2 or 3, and I cannot tell you which**

I implemented exactly the mechanism the task names as the only candidate:
`SetSize` is copied from the cast frame identically on both paths, and on the
radial path `f:GetStatusBarTexture():SetRotation(radians)` is called with the
same `ClockToRadians(castRotation)` value the Cooldown path passes to its own
`SetRotation`. This is in the code and passes the harness (`SetRotation` is
recorded on a persistent stub texture object so a test could assert it, though
none of the six required cases needed to).

**Whether this reproduces the current look cannot be determined without the
game**, and the task file says as much ("is unknown and cannot be determined
from the harness or from source"). I want to be specific about why I am not
picking outcome 1: `StatusBarRenderMode.Radial`'s documentation says it drives
"the managed texture's radial progress fill percent instead of resizing the
texture anchors" — which describes the fill as a property computed
independently of the texture's own transform, the same way the Cooldown
widget's swipe angle has historically been independent of `SetRotation` on its
texture (that split is *why* `Cooldown:SetRotation` exists as a separate call
from the swipe machinery in the first place). That makes outcome 2 (artwork
rotates, fill start does not) the more *likely* reading of the documentation
to me, but this is an inference from a one-paragraph enum comment, not a
measurement, and I am not willing to report it as more than that. It could
equally be outcome 1, or the call could have no visible effect on this render
mode at all (outcome 3, in a softer sense than "could not attempt" — I could
and did attempt it, I just cannot confirm it did anything).

**Report this to the player as: needs a `/reload` and a look**, specifically
comparing the radial ring's start position and sweep direction against the
Cooldown ring's, with `resourceRingRadialBar` flipped on and a mid-value
resource (not 0% or 100%, where a start-angle mismatch would be invisible).

## Proposed docs changes

**`docs/KNOWN-ISSUES.md`**, "Resource ring cannot show an exact level in
combat" — append (do not replace the existing "Open, but no longer believed
impossible" framing, which is already correct):

> **Task 16, 2026-08-12: built, not yet verified in game.** A second
> implementation exists — `modules/ResourceRing.lua`'s radial `StatusBar`
> path, opt-in via `resourceRingRadialBar` (default off) on the Cursor Rings
> page. Correct in code and in the harness: `SetValue`/`SetMinMaxValues`
> accept the secret `UnitPower` value with no arithmetic and no comparison,
> confirmed by a test that hands the stub `_G.__SECRET` and asserts the
> `Update` call does not throw. Falls back to the Cooldown ring automatically
> if `Enum.StatusBarRenderMode` or `SetRenderMode` is absent. **What is not
> known: whether the radial ring's visual sweep matches the Cooldown ring's
> start angle and direction** — `StatusBar` has no `SetRotation`; the closest
> analogue is rotating the managed texture via `GetStatusBarTexture():
> SetRotation()`, and whether that rotates the fill's start angle or only the
> artwork under a fill that starts elsewhere is unknown until checked in
> game. Needs a `/reload`, the setting flipped on, and a visual comparison at
> a mid-range resource value.

**`docs/DECISIONS.md`** — new entry, suggested as §23:

> ## 23. The resource ring's radial StatusBar: built on the §20 measurement, one geometry question left open
>
> Task 16, 2026-08-12. §20 established that `StatusBar:SetValue` /
> `SetMinMaxValues` accept a secret (`AllowedWhenTainted`, measured accepted
> at every phase of a full combat) and that 12.1's
> `StatusBarRenderMode.Radial` makes a `StatusBar` a second kind of ring. This
> task built the ring: `modules/ResourceRing.lua` now holds two frames behind
> one module, switched by the flat `resourceRingRadialBar` setting
> (default `false` — the Cooldown ring is unchanged and stays the default).
>
> The radial path is genuinely simpler than the Cooldown path it sits next
> to: no fraction, no `lastFraction` short-circuit, no `unreadable` branch, no
> frozen-full-ring fallback. `SetMinMaxValues(0, maximum)` then
> `SetValue(current)`, unconditionally, every update — the entire reason 12.1
> made this possible is that the engine now does the arithmetic we are not
> allowed to do ourselves.
>
> **The capability gate matters as much as the happy path.** A radial
> `StatusBar` requires both `Enum.StatusBarRenderMode` to exist and the
> created frame to have a `SetRenderMode` method; either being absent must
> fall back to the Cooldown ring *whatever the setting says*, cached after
> the first check so the fallback (and its one `LogOnce`) does not re-run
> every update. This is the same shape as the `SetCooldown` refusal in §19 and
> the `ItemLocation` colon call in §22: a setter that looks uniform across
> client versions is not.
>
> **`StatusBar` has no `SetRotation`.** `Cooldown:SetRotation` rotates the
> swipe; the closest thing on a `StatusBar` is
> `GetStatusBarTexture():SetRotation()`, which definitely exists
> (`SimpleTextureBaseAPIDocumentation.lua`, live) but whose relationship to
> the *radial fill's* start angle is not documented and could not be
> determined from source or the harness. Attempted, shipped behind the same
> geometry as the Cooldown ring (`SetSize` copied identically,
> `SetRotation(ClockToRadians(castRotation))` called on the texture), but
> **unverified whether it visually matches** — see `KNOWN-ISSUES.md`.

**`docs/HANDOFF.md`** — I did not read the exact current queue structure well
enough to draft a precise diff (out of my read list for this task), but the
open item to add is: *"Task 16's radial resource ring needs an in-game look:
flip `resourceRingRadialBar` on via the Cursor Rings page, and compare its
sweep start/direction against the Cooldown ring at a mid-range resource
value."*

## Could not do

Nothing was blocked. The one open question — which of the three geometry
outcomes was reached — is answered above as honestly as I can: attempted,
correct in code, outcome unknown without the game.

## Noticed but did not touch

- `ThugUI.Diagnostics:LogOnce` signature is `(key, category, message, ...)`
  with `%s`-style formatting for the varargs (used already by the existing
  `power-secret` log line in this same file). My new
  `resource-ring-radial-unsupported` log line passes no varargs, which is
  fine (no `%` in the message), but it's worth noting for whoever writes the
  next `LogOnce` call in this file that the format string is not optional —
  it goes straight to `string.format` internally as far as I could tell from
  usage patterns, not proven by reading `Diagnostics.lua` in full since it
  was out of scope here.
- `RR.driver`'s `OnEvent` handler calls `RR:Update()` unconditionally for
  every registered event except the two colour-affecting ones. Since
  `EnsureFrame()` now runs on every `Update()` call (not just the first), the
  frame-kind check (`f ~= self.frame`) is a very cheap comparison, but it does
  mean the setting is re-read from `ThugUI_Config` on every power tick rather
  than only when the checkbox changes. This is harmless (no allocation unless
  the setting actually changed) and matches how `ShouldShow()` already
  re-reads three other config keys every update, so I left it as the
  natural extension of the existing pattern rather than adding a "did the
  setting change" cache that nothing else in this file has.
- The `SetStatusBarTexture` stub returns `true` (matching the documented
  `success` boolean return), but nothing in `ResourceRing.lua` reads that
  return value, matching the Cooldown path's `SetSwipeTexture` call, which
  also ignores its return.

## Not verified

Everything here requires the running game:

- Whether the radial ring's sweep visually starts and runs the same way the
  Cooldown ring's does (the open geometry question above).
- Whether `StatusBar:SetValue`/`SetMinMaxValues` genuinely accept a secret
  `UnitPower` value **in this specific combination** — same render mode, same
  texture, same anchor as built here. §20's measurement was on the API in
  general, not on this exact frame construction.
- Whether the capability gate (`Enum.StatusBarRenderMode` / `SetRenderMode`
  presence check) behaves as expected on the player's actual 12.1 client —
  it should, since both are documented as present, but this was never
  exercised against the real API, only the harness's stub.
- Whether the new checkbox on the Cursor Rings page lays out correctly next
  to the existing controls, and whether flipping it in a live session
  produces a visible frame swap with no flicker or stale sweep.
- Whether `ThugUI.Diagnostics:LogOnce` actually writes to
  `ThugUI_DebugLog` the way the existing `power-secret` line does — assumed
  from the identical call shape, not tested against the real Diagnostics
  module beyond what the harness's stub proves (which is only "the call does
  not throw").
