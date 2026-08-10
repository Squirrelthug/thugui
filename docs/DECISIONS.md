# ThugUI — decisions and reasoning

Why the addon is the way it is. Read this before changing anything structural;
most entries exist because something failed in a way that was not obvious.

Add to it when you solve something non-obvious. The rule of thumb: if you had
to work something out, and the code alone would not tell the next person, it
belongs here.

---

## 1. There are three halves, and two config stores

The addon grew in layers and they do not know about each other.

| | Config store | Defaults | Bootstrap | Owns |
|---|---|---|---|---|
| **A** — original | `ThugUI_Config` (flat keys) | `ER.defaults` in `modules/EssentialRings.lua` | `LoaderFrame` at the bottom of that file | EssentialRings, RaidFrames, TargetOfTarget, FrameHider, CooldownViewer |
| **B** — module system | `ThugUIDB` (nested per module) | `ThugUI.defaults` in `core.lua` | `core.lua` ADDON_LOADED | OrbAnchors |
| **C** — config window | *reads both* | — | page files register on load | `ui/` |

Half C is a UI layer, **not** a third store. Do not create one.

**Load-order trap:** `core.lua` assigns `ThugUI.modules = {}` unconditionally,
and `modules/OrbAnchors.lua` calls `RegisterModule` at file scope. Load core
after a module and the registry is wiped. The TOC comments spell out every such
constraint — read them before reordering anything.

## 2. Why the config window rebuilds nothing

The old `options.lua` had three hardcoded categories and a `RefreshContent()`
that destroyed every control on each tab switch using `SetParent(nil)`.

**`SetParent(nil)` does not free a frame in WoW.** It orphans it. Every visit to
a page leaked a full set of controls for the session.

`ui/Window.lua` builds each page **once** into a persistent container and then
shows/hides it. `panel:Refresh()` re-reads config into the existing widgets.
Switching pages costs nothing and leaks nothing.

Dropdowns use `DropdownButton` / `WowStyle1DropdownTemplate` / `MenuUtil`.
`UIDropDownMenu` was deprecated in 11.0 with no shim. The older panels under
`modules/` still use it; nothing new should.

## 3. The cooldown viewer is a per-spec grid

The original design was three near-identical code paths (ECV/BCV/GCV) with flat
`ecv*`/`bcv*`/`gcv*` keys and hardcoded `IsRestoSpec()` gates. That does not
survive 40 specs.

Profiles are keyed by **specID** — the globally unique number from
`GetSpecializationInfo`, *not* the 1–4 spec index, which repeats across classes.
Adding a spec is now a player dragging icons, not new Lua.

A layout is a 10×10 grid. The cursor attaches to one of the **11×11
intersections** of the grid lines, which is what lets a player draw a shape and
then choose which part of it rides the pointer. The grid is editor-only
furniture; at runtime only the icons draw.

The anchor picker — a radio at every intersection, exclusive selection, live
marker — is deliberately the same idiom as the eight-point picker in the
player's other addon, so the two feel like one system.

**Preview draws through the same layout path as combat.** It must tell the
truth, including unflattering truths like a deliberate gap being closed by
collapse.

## 4. Collapse: one function, three modes

Rows and columns are mirror images, so `CV:ApplyLayout` has ONE generic
`Pass(major, minor, ...)`: `major` is the axis icons are grouped by, `minor`
the axis they slide along. Stage 1 compacts each group along `minor`; stage 2
vacates a group with nothing live and closes survivors along `major`.

Do not write a per-axis variant. Swap the axes.

- **rows** — group by row, slide along col. For layouts built across.
- **columns** — group by col, slide along row. For layouts built up/down.
- **both** — a row pass then a column pass, over a shared working-position
  table. That table is why pass 2 can build on pass 1 instead of re-reading
  the stored placements.

Two rules chosen deliberately, both of which constrain the design:

1. **A group packs from its own outermost occupied slot, never the grid edge.**
   This is what keeps a full-strength layout sitting exactly where it was drawn.
   It is also why "both" is not a globally minimal repack — an icon never
   teleports across the shape. That trade was made knowingly: predictability
   beats squeezing out the last cell.
2. **A group is one run.** A deliberate mid-group gap closes too. Keeps the rule
   "a group is never gappy" total.

`collapseDirection` is **per-mode** (`rows`: left/right, `columns`: up/down,
`both`: four corners). The menu is built from the mode. Never offer a direction
that silently does nothing.

## 5. Spell readiness: never from duration

**Use `isActive` and `isOnGCD`. Never `startTime`/`duration`.**

Two independent reasons, either fatal:

1. The global cooldown is a running cooldown. Judging by duration means every
   icon vanishes the instant you cast anything — and in combat you are almost
   always inside a GCD, so the whole display disappears and stays gone.
2. In 12.x `startTime`/`duration` are **secret values**. Comparing them yields a
   secret boolean, and feeding that to `SetShown` hides the icon.

Passing secret values *to* Blizzard's API is fine —
`cooldown:SetCooldown(cd.startTime, cd.duration, cd.modRate)` works. Reading
them yourself is what breaks. Aura timing and stack reads are `pcall`-guarded
for the same reason.

**Query by NAME, not ID.** `C_Spell.GetSpellInfo` resolves a name only for a
spell the player actually has, so it doubles as the talent check, and the name
maps to whichever version is currently talented. An ID check gets override
spells wrong in both directions and makes icons flicker as talents shift. The
stored ID picks the artwork; the name decides whether it draws.

## 6. UNIT_* events fire for every unit

`RegisterEvent("UNIT_SPELLCAST_STOP")` fires for **everyone in range**. The cast
ring handler read `UnitCastingInfo("player")` unconditionally and ignored the
`unit` argument, so any raid member finishing any cast wiped the player's ring.

It survived about as long as the gap between other people's casts: fine solo
for months, stuttery in dungeons, useless in a raid.

**Always `RegisterUnitEvent(event, "player")`, and keep a `unit ~= "player"`
guard in the handler.** The failure mode scales with group size, which means it
is invisible exactly where you test.

Also register `UNIT_SPELLCAST_DELAYED` / `_CHANNEL_UPDATE` (pushback moves
`endTime`; without re-reading, the sweep drifts) and `_INTERRUPTED` / `_FAILED`
(a cast can end with no `STOP`, stranding the ring).

**A stuttering `Cooldown` swipe is an event bug, not a performance one.** That
widget is rendered engine-side and is already frame-rate smooth with no
`OnUpdate`. Do not reach for a per-frame redraw.

## 7. Visibility must not be able to get stuck

The viewer was driven only by `PLAYER_REGEN_DISABLED`/`ENABLED`, and derived
combat from `InCombatLockdown()` — which is not reliably flipped yet while that
event is being handled. Guess wrong once and the grid hid, and **nothing could
bring it back**: `UpdateState` and the cursor path both bail while hidden, so
the hidden state sustained itself for the whole fight.

Two fixes, either sufficient, both kept:

1. `PLAYER_REGEN_*` **forces** the combat state rather than deriving it — which
   is what `ER:UpdateVisibility(true)` had always done in its own handler.
2. The throttled `OnUpdate` re-evaluates visibility unconditionally, *before*
   the `IsShown` bail-out. A wrong state lasts 150ms instead of forever.

Generalise: any state that gates its own recovery check needs a poll.

## 8. Picker lists come from Blizzard, on purpose

"Essential cooldowns", "Utility cooldowns" and "Tracked buffs" are
`C_CooldownViewer.GetCooldownViewerCategorySet(...)` — the same per-spec curated
sets the game's Cooldown Manager offers. New spec, new expansion, retuned
lists: Blizzard maintains it, we inherit it. This is the future-proofing
strategy and it should stay that way.

"Spellbook (all)" is our own scan; "Everything" is the union. If a category
returns nothing, we fall back to a spellbook scan so the picker is never
mysteriously empty.

**`TrackedBuff` and `TrackedBar` are read together as one "Tracked buffs"
source.** From the player's side they are one pool — the same tracked spells,
shown either as a row of icons or a stack of timer bars — so they are not
offered as two menu entries.

They are **not** the same data, though, and reading only `TrackedBuff` loses
entries outright. Roll the Bones on an Outlaw rogue is listed twice:

```
Essential   cooldownID 11860  linkedSpellIDs = {}
TrackedBar  cooldownID 42743  linkedSpellIDs = One of a Kind, Double Trouble,
                                               Triple Threat, Jackpot
```

Only the `TrackedBar` entry knows which buffs the spell can grant. With
`TrackedBar` unread, those outcome buffs were unreachable no matter what the
player selected.

**A spell can appear in more than one category, and the entries differ.** When
two share a spell ID, the cache keeps the *richer* one — most linked spells,
then `hasAura` — because keeping whichever was scanned first let the empty
Essential entry win and silently hid the buffs.

*(An earlier version of this file asserted the opposite — that TrackedBar was a
pure duplicate and must not be read. That was wrong, and the probe dump
disproved it. Verify against `/thugcv probe` before trusting a claim about
category contents.)*

### Entries that stand for a set of spells

Some entries represent several possible buffs rather than one aura. Roll the
Bones grants one of a set of outcomes and **has no base `spellID` of its own** —
it is defined purely by `linkedSpellIDs`.

**How many outcomes is a per-build fact, not a constant.** This file used to say
six, from the classic Broadside / Grand Melee / Ruthless Precision / Skull and
Crossbones / True Bearing / Buried Treasure. On 12.0.7 the probe dump reports
**four**, and none of the classic six appear anywhere in it:

```
TrackedBar  cooldownID 42743  spellID 1214909  hasAura=false  selfAura=true
  1214933 One of a Kind   1214934 Double Trouble
  1214935 Triple Threat   1214937 Jackpot
```

Never hardcode the count or the IDs — walk `linkedSpellIDs` and let the game
say. The stale "six" cost a round of hunting for IDs that no longer exist.

Blizzard resolves this in `CooldownViewerItemDataMixin`:

```lua
function CooldownViewerItemDataMixin:FindLinkedSpellForCurrentAuras(unit)
    for _, spellID in ipairs(self.cooldownInfo.linkedSpellIDs) do
        local auraData = C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)
        if auraData and auraData.sourceUnit == "player" then
            return spellID, auraData
```

Precedence: **active aura → active linked spell → overrideTooltipSpellID →
overrideSpellID → base spellID**. `GetSpellTexture` checks the aura's spell
first, which is why the tracker shows the *buff's* icon, not the granting
spell's.

Two traps this caused:
- Taking only `overrideSpellID or spellID` **drops** an entry with no base
  spell. That is the entire reason Roll the Bones was missing from the picker
  while everything else appeared.
- Apply the same source check on **every** lookup path. A fallback that
  re-fetches without it silently re-admits what the first check just refused.

### Do not copy Blizzard's sourceUnit check verbatim

Blizzard requires `auraData.sourceUnit == "player"`. Copying that exactly made
the tracked buff never appear, because **engine code can read fields addon code
cannot**: in 12.x aura fields come back as secret values, and comparing a secret
string never yields a usable `true`.

The rule is therefore: reject only a source we can actually *read* and that is
not the player. Absent or unreadable is accepted, since the lookup is already
scoped to auras on the player and self-buffs are what the mode is for. The cost
— another player's same-named buff can slip through while the field is secret —
is far smaller than showing nothing.

**Generalise: any check copied from Blizzard's UI that reads aura or cooldown
fields needs to tolerate secret values, because their code is not subject to the
same restriction as ours.** See §5 for the same lesson on cooldown fields.

Use `/thugcv probe` to dump what the Cooldown Manager actually reports.

## 9. Migration ran once and silently did nothing

The Restoration bar stores spell **names**, and names resolve only while in that
spec. The original one-shot migration ran on whatever spec happened to be
active, resolved Restoration to an empty list, and set a global `migrated` flag
— so it never tried again.

Now: tracked **per spec**, only marked done once something was actually
written, retried on `PLAYER_SPECIALIZATION_CHANGED`, with a verified ID fallback
so it works from any spec. `/thugcv import` runs it on demand.

Generalise: a "did it once" flag on an operation that can silently no-op is a
bug waiting to happen. Mark done only on success.

## 10. Display modes

A placed icon has a mode deciding when it draws:

| Mode | Shows when |
|---|---|
| `cooldown` | the spell is off cooldown — the icon *is* the readiness signal, so nothing sweeps; it simply disappears once spent |
| `proc` | off cooldown **and** lit by a proc. Narrower than `cooldown`: a merely-usable spell stays hidden until something makes it worth pressing |
| `always` | always, with a cooldown sweep over it |
| `aura` | while its buff is on the player — see §8 for entries standing for a *set* of buffs |

`proc` requires **both** conditions deliberately. A proc landing while the spell
is still on cooldown is not yet actionable, so it stays hidden until it is
genuinely pressable.

Proc state comes from `C_SpellActivationOverlay.IsSpellOverlayed`, which
returns a **plain bool** per Blizzard's generated docs — one of the few things
in this area safe to branch on while everything around it is secret.

The glow visual is Blizzard's own `ActionButtonSpellAlertManager`, not an
imitation, so a glow here reads identically to one on the action bars. Its
`Default` path only needs a frame with a size, and a nil `action` field
short-circuits the assisted-combat branch, so our icons qualify.

**Clear the glow whenever an icon hides.** An alert left running on a hidden
frame keeps animating and pops back when the icon returns.

## 11. Diagnostics are always on

`modules/Diagnostics.lua` writes to `ThugUI_DebugLog` with no command and no
flag. It records **evidence of behaviour**, not a version string: the snapshot
lists each placed icon with the linked-spell count actually resolved for it, so
`linked=4` proves the linked-buff code ran.

That design came from a specific failure — a fix was pushed, the player was
still running the previous build, and the behaviour was indistinguishable from
the fix not working. Nothing on disk could tell them apart, so a wrong
conclusion was reached and stated confidently.

Rules for it:
- **Event level only.** A handful of entries per session plus one snapshot at
  logout. The verbose per-aura logger in `EssentialRings` is a different thing
  and stays behind `debugMode`.
- **`LogOnce` for anything that repeats per frame.** First occurrence is the
  story; 10,000 copies are noise.
- **Never let it throw.** Always-on code must not be the reason something
  breaks — the timestamp helper is guarded for exactly this.
- The log is a ring buffer capped at 300, dropping the **oldest**: the tail
  explains whatever just went wrong.
- Cleared on login, so one session cannot bury the one being asked about.
- The snapshot is taken on `PLAYER_LOGOUT`, which fires before saved variables
  are written and so captures the session that just ran.

## 12. Taint cannot be cleaned, and was never the bug

**Checked against Blizzard's own generated docs, 2026-08-09.** This entry
exists to stop the next agent spending another three sessions on it, as this
project already has.

The theory was: ThugUI picked up a taint trace, taint is why `UnitPower`
returns a secret and why aura lookups come back empty in combat, so find the
source and both features come back. Every word of that is wrong except the
symptom.

**Addon code always executes tainted by its own addon.** There is no untainted
state for us to reach. Two independent pieces of evidence:

- `!BugGrabber.lua` carries this error shape from four different addons, and
  each names *itself*: `tRP3_Vendor`, `Listener`, `ChonkyCharacterSheet`, and
  us. Those are the four addons that do arithmetic or comparisons on secret
  values — not the four that are dirty. "While execution tainted by 'ThugUI'"
  is the engine saying *this is addon code*, not *ThugUI has a trace*.
- Blizzard's `Blizzard_APIDocumentationGenerated` flags the **APIs**, not the
  caller. From the `live` branch:

  | API | Flag | Consequence for us |
  |---|---|---|
  | `GetUnitAuraBySpellID`, `GetPlayerAuraBySpellID`, `GetAuraDataBySpellName` | `SecretWhenUnitAuraRestricted` + **`RequiresNonSecretAura`** | returns **nothing** in combat |
  | `GetAuraDataByIndex` / `BySlot` / `ByAuraInstanceID` | `SecretWhenUnitAuraRestricted` | returns a **secret struct**, so no field comparison can match |
  | `UnitPower` | `SecretWhenUnitPowerRestricted` | primary resources (energy) stay secret to addons |

That last one also explains the observation that broke the taint theory: the
ring reported an unreadable power value five seconds into a fresh session with
no combat and no blocked action. Inherent taint predicts exactly that. An
accidental trace does not.

So the buff icon was never failing *because of* something we did. Blizzard's
own `CooldownViewerBuffItemMixin:IsExpired` does `auraData.expirationTime <=
GetTime()`, which works only because their code is untainted. **A tainted addon
is not meant to be able to answer "is buff X up" during combat.** That is the
feature, not the bug.

What follows from it:

- The `ToT` mover deferral was still worth having — classic taint still exists
  and still causes `ADDON_ACTION_BLOCKED`. It just has nothing to do with
  secret values.
- Displaying a secret is done by handing it to a blessed setter and never
  looking at it: `StatusBar:SetValue`, `Cooldown:SetCooldown*`, `SetShown`,
  `SetAlpha`, `SetVertexColor` are all `AllowedWhenTainted`.
- `CurveObject:Evaluate` is **not** — it is `AllowedWhenUntainted`, so a curve
  cannot map *our* secrets. Curves only work where a Blizzard API takes the
  curve and evaluates it internally, e.g. `GetAuraDispelTypeColor`.
- 12.1 makes this stricter, not looser: the index/slot/instanceID aura calls
  will **Lua error** rather than return secrets. The fallback list walk in
  `CooldownViewer/Core.lua` is on borrowed time.
- 12.1 relaxes one thing that matters here: secondary resources (combo points)
  stop being secret. The queued pips depend on that and nothing else.

`modules/SecretProbe.lua` measures all of this on the live client rather than
trusting the above, because the wiki has been wrong about this system before.

### Measured on 12.0.7, in combat, 2026-08-09

It was right to measure. Two of the expectations above were wrong.

| Read | In combat | Out of combat |
|---|---|---|
| `UnitPower` energy (primary) | **secret** | secret |
| `UnitPower` combo points (secondary) | **readable — `4`** | readable |
| `GetUnitAuraBySpellID` / `GetPlayerAuraBySpellID` | nothing | returns the aura |
| `GetAuraDataByIndex` list length | **9–11 auras returned** | 10 |
| `aura.spellId` / `.name` **read** | **secret, but readable as a field** | plain values |
| `aura.spellId` **compared** | **errors** | fine |
| `GetUnitAuraInstanceIDs` | **non-secret list of real IDs** | non-secret |
| `IsAuraFilteredOutByInstanceID` | **non-secret bool** | non-secret |
| `DoesAuraHaveExpirationTime` | secret bool | plain bool |
| `EvaluateColorValueFromBoolean(secret bool)` | **works, returns a secret** | works |
| `Frame:SetAlpha(secret)`, `StatusBar:SetValue(secret)` | **accepted** | accepted |
| `Cooldown:SetCooldownDuration(secret)` | **REFUSED** | refused |
| `CurveObject:Evaluate(secret)` | refused | refused |

Corrections that follow:

1. **Secondary resources are already readable on 12.0.7**, not from 12.1. The
   combo pips track live in combat today. The 12.1 note relaxed something that
   had evidently already shipped.
2. **`Cooldown:SetCooldownDuration` does not accept secrets**, despite the wiki
   listing the `Cooldown` setters as `AllowedWhenTainted`. `StatusBar:SetValue`
   and `SetAlpha` do. A radial swipe therefore cannot be driven from a secret
   at all, which closes the last route to an exact resource ring in combat.
3. **Identifying an aura in combat is genuinely impossible for an addon.** The
   list comes back and the structs can be indexed, so `aura.spellId` is
   *reachable* — but every use of it needs a comparison, and comparison is what
   errors. There is no native equality helper: `Evaluate` refuses secret input,
   and no API turns a secret spell ID into a secret boolean. Everything else
   being available makes this the deliberate choke point rather than an
   oversight.
4. What *is* available is a complete display path for a secret the engine hands
   us whole: secret bool → `EvaluateColorValueFromBoolean` → `SetAlpha`. It is
   useless here only because no per-spell secret bool exists to feed it.

## 13. Odds and ends worth not rediscovering

- **`GetProfile` must refuse specID 0/nil.** Called before spec data loads, it
  used to create and store a junk `[0]` profile that collected edits nobody
  would ever see again.
- **`UnitPowerType("player")` already follows shapeshift form and stance.** A
  druid reports rage in Bear and energy in Cat with no special-casing. Only
  override where the game's primary resource is not the one that drives the
  rotation — Moonkin form is currently the only entry.
- **A `Cooldown` widget can hold a static arc.** Seed `SetCooldown` so the
  *remaining* portion equals the fraction, then `Pause()`. That is how the
  resource ring draws a fixed level with an animating widget.
- **Icons are pooled.** A layout edit re-runs `Rebuild` on every slider tick;
  creating fresh frames would bleed them for the session.
- **Templates naming `$parentText` give nothing on anonymous frames.**
  `OptionsSliderTemplate` needs a real generated name.
