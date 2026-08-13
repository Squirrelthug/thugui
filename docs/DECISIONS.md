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
| **A** — original | `ThugUI_Config` (flat keys) | `ER.defaults` in `modules/EssentialRings.lua` | `LoaderFrame` at the bottom of that file | EssentialRings, TargetOfTarget, FrameHider, CooldownViewer |
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

Reading secret values yourself is what breaks. Aura timing and stack reads are
`pcall`-guarded for the same reason.

**Correction, 2026-08-10.** This section used to say that passing secrets *to*
Blizzard's API is fine and that
`cooldown:SetCooldown(cd.startTime, cd.duration, cd.modRate)` works. **It does
not.** BugGrabber session 150 carried 36 copies of

```
Core.lua:126: bad argument #1 to 'SetCooldown' (Secret values are only allowed
during untainted execution for this argument.)
```

with the locals showing `startTime`, `duration` and `modRate` all secret and
`isActive`/`isOnGCD` plain. §12 had **already measured** `SetCooldownDuration`
refusing secrets; nobody joined that to the claim here, and the wrong sentence
survived in the file the project treats as its reasoning log. The general rule
is narrower than it looked: *some* setters are `AllowedWhenTainted`
(`SetAlpha`, `StatusBar:SetValue`), and **the Cooldown radial setters are not
among them**. Check the specific setter; do not generalise from another one.

The throw was uncaught, which cost more than the missing sweep — see §19.

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

### The category list is derived; the source menu is not

Added 2026-08-09, ahead of 12.1 adding five categories.

`BuildCooldownInfoCache`, `DumpCooldownViewer` and the "Everything" picker source
**iterate `Enum.CooldownViewerCategory`** instead of naming the four categories
they used to. All three mean "whatever the Cooldown Manager has", so a category
added by a patch belongs in them automatically. Hardcoded names do not fail
loudly when a patch adds one — they just quietly lose entries, which is the same
shape of silent loss that hid the Roll the Bones outcome buffs above.

`CATEGORIES_BY_SOURCE` and `Data.SOURCES` stay **hand-written**, and that is not
an oversight to finish tidying. Which categories a player-facing menu entry pools
together is a product decision: `TrackedBuff` and `TrackedBar` are two categories
deliberately presented as one "Tracked buffs" source, and a menu entry per enum
value would undo exactly that. A category no source names yet stays reachable
through "Everything", and is logged once so the next patch announces itself.

### `Enum.CooldownViewerCategory` is not a clean enum at runtime

This one cost a defect, and it is invisible from the generated documentation.

`Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua` writes two fake
entries into the enum at load:

```lua
--- These values aren't actually part of the enum
--- They exist so that disabled states can be managed using the same category enums
Enum.CooldownViewerCategory.HiddenSpell = -1;
Enum.CooldownViewerCategory.HiddenAura = -2;
```

That file is the **first line of `Blizzard_CooldownViewer.toc`**, and that addon
is the Cooldown Manager itself — not a load-on-demand settings panel. So both
keys are present in every session on 12.0.7, and anything walking the enum sees
them. Blizzard reads them back through `CooldownViewerUtil.IsDisabledCategory`;
they are markers for "the player switched this off", not category sets.

**Filter on the value, never the name.** They are renamed on the 12.1 PTR
(`HiddenActive = -1`, `HiddenPassive = -2`), so a name blocklist would have
broken at the patch — which is the exact failure the enum iteration exists to
prevent. Real categories start at 0 and count up, and Blizzard's own comment
promises the fakes never collide with them.

Left unfiltered this did three things, all live on 12.0.7: two pointless
`GetCooldownViewerCategorySet(-1)` calls per pass; a route for deliberately
disabled spells to leak into the cache and the picker; and worst, it made the
"new category appeared" log fire on day one, discrediting the signal before the
patch it was built for ever arrived.

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

## 13. Buff icons are Blizzard's own frames, sitting in our cells

**Verified working in game 2026-08-09.** `modules/CooldownViewer/BlizzBuffs.lua`.

§12 establishes that an addon cannot identify an aura during combat: the list
comes back, the structs can be indexed, `aura.spellId` is right there, and
comparing it errors. Every other piece of the aura system is reachable. That one
is the choke point, and it is deliberate.

So ThugUI stopped asking. Each aura-mode placement is matched to the item frame
in Blizzard's buff viewer carrying the same **`cooldownID`** — cooldown IDs stay
plain numbers in combat, since the `CooldownViewerCooldown` structure carries no
secret predicates at all — and that item is anchored over the assigned cell.
Blizzard's untainted code decides shown/artwork/timer; ThugUI decides where it
sits and how big it is.

### What the player has to do for it to work

**The buff must be in one of the two *active* lists in the game's own Cooldown
Manager settings**, and it will look different depending on which:

| List it is in | What lands in the cell |
|---|---|
| **Tracked Buffs** | icon with a countdown timer on it |
| **Tracked Bars** | icon with an animated bar to its right |
| Neither (just the buff list) | nothing — there is no item frame to adopt |

Both lists live in the same Essential Cooldowns window, on different tabs. The
player confirmed the mechanism directly: dragging Roll the Bones from the bar
list to the icon list changed what appeared in the cell, live.

This is not a limitation to design around — it is how the feature works, and it
means **the addon can only show what Blizzard is already tracking**. It needs
saying in the UI next to the tracked-buff picker, which is queued in
`HANDOFF.md` §4.

The grid is stacked cells, so a bar shoved into one cell is fine and never
occupies more than one. The player likes the animation and does not want it
scaled up.

### Three deliberate restraints

- **Nothing is reparented.** Anchoring places a frame perfectly well, and 12.1
  tightens what addons may do to aura frames ("addons are no longer allowed to
  reparent aura buttons"). Cooldown viewer items are not aura buttons, but
  staying on the side of the line that needs no permission cost nothing here.
- **No fighting the layout.** Their `RefreshLayout` releases every item back to
  the pool and re-anchors it, so our anchors *will* be overwritten. We re-apply
  on a hook, deferred one frame so we are not anchoring in the middle of their
  pass.
- **The grid hands the items back the moment it hides.** They are not our
  children, so hiding the container would otherwise strand them at the
  coordinates of an invisible grid.

### The cost, stated plainly

An adopted cell is **always reserved**, buff up or not, because we cannot ask
whether it is up. With collapse on, that cell no longer closes. The alternative
is a row sliding over a cell Blizzard may fill a moment later.

### That invariant was stated here and not actually enforced

Found 2026-08-09, from a buff that adopted correctly and never appeared.

`CV:UpdateState` checked `IsSpellAvailable(spellName)` **before** the `adopted`
branch. `IsSpellAvailable` resolves **by name** — which is deliberate, since a
by-name lookup doubles as the talent check (§5) — and a name only resolves for a
spell the player has as a castable.

That is fine until the placement is not a castable. **Opportunity is placed under
`279876`, the passive that grants buff `195627`**; the Cooldown Manager lists it
under `TrackedBuff` as `cooldownID 93055`. The passive answers no by-name lookup,
so `show = false` and the branch that reserves the cell was never reached — while
`BlizzBuffs` had already anchored Blizzard's item to it. Adopted, drawn by
Blizzard, and parked on a cell the layout had disowned. With collapse on it is
worse than invisible: an icon that is not `wanted` is left out of the collapse
pass, so it keeps its uncollapsed coordinate while every live cell slides away
from it.

Roll the Bones hid the problem for months because it is placed under `1214909`,
the spell you actually cast.

**`adopted` is now checked first.** The rule it encodes is the one this whole
section rests on: when Blizzard's untainted code is already drawing the item, we
have no standing to ask whether the spell exists. Their frame is the stronger
authority and our by-name lookup was overriding it.

Rejected, deliberately: widening `IsSpellAvailable` to fall back on the Cooldown
Manager's own `isKnown` flag. It would fix this case too and may be right later,
but it changes availability semantics for every placed icon in every mode,
including the ones that work today. Not worth the blast radius for a bug with a
one-branch cause.

**Generalise: an availability check of your own must never outrank the engine's.**
If Blizzard is rendering it, it exists.

### A bare `pcall` around the main pass throws away the only evidence there is

`BB:Refresh` wrapped `Apply` in `pcall(function() self:Apply() end)` and dropped
the result. A caught error reaches neither `ThugUI_DebugLog` nor BugGrabber, so
the failure was invisible from both files this project debugs from.

It was hiding something real: in a session where adoption demonstrably happened,
the `blizzbuffs-adopted` line at the bottom of `Apply` never fired, which means
`Apply` was failing partway through every pass. Diagnosing an unrelated bug in
that same function then took an argument by elimination across three files,
because the one line that knew the answer had discarded it.

`Refresh` now records the message once per distinct error, and the adoption loop
logs **which stage** an icon failed at — no Cooldown Manager entry, no cooldown
ID, or no matching item frame. That third one is the common case and the only one
the player can act on: it means the buff is in neither of Blizzard's active
lists. See the skill file's evidence loop; this is that rule, learned again.

### And it is not free

Touching those frames appears to break Edit Mode — see `KNOWN-ISSUES.md`,
"Edit Mode cooldown windows vanish". That is the open thread as of this writing.

### Their frame's visibility is the buff state we were told we could not have

For a while the adopted cell was reserved permanently, buff up or not, on the
stated grounds that an addon cannot ask whether a buff is active. §12 proves
that about the *aura APIs*, and it is still true of them. It was quietly
generalised into "we cannot know", and that was wrong.

Blizzard's item hides itself when the buff drops —
`CooldownViewerItemMixin:UpdateShownState` calls `SetShown(self:ShouldBeShown())`
— and **reading a frame's shown state is not reading an aura**. It is an ordinary
widget query on a frame we are already allowed to read. So the answer was
sitting in the frame we had adopted the whole time.

`CV:UpdateState` now asks three sources in descending order of authority, and
the order is the design:

1. `BB:ItemIsShown(item)` — Blizzard's own answer, when readable.
2. `ResolveAura(icon)` — truthful out of combat, blind during it.
3. Reserve the cell.

`ItemIsShown` returns `true`, `false`, or **`nil` for "cannot tell"**. Three
states, not two, and the third is the whole point: "hidden" and "unknown" need
opposite handling. Step 3 is a safety property rather than a convenience —
collapsing a cell whose buff is actually up leaves Blizzard's item anchored to
our now-hidden icon, drawing at a stale coordinate on top of a neighbour. Unsure
must mean "keep the slot".

The secret screen inside `ItemIsShown` is not defensive noise. That boolean
descends from `CooldownViewerBuffItemMixin:IsExpired`, which compares
`auraData.expirationTime <= GetTime()`, and `expirationTime` is secret in combat.
Whether the derived boolean reaches us secret was unmeasured, so `BB:Apply` logs
it once per session **per combat state** — combat is in the key, because an
out-of-combat line logged first would suppress the only line worth having. That
is the `GetPlayerCastAura` `Note` lesson, learned a second time.

### Tracking one outcome of a multi-buff spell is impossible, and was tried

The picker used to expand each buff entry's `linkedSpellIDs` into rows of their
own, so a player could ask for one specific outcome — "show me only when I roll
Jackpot" rather than "show me Roll the Bones". The intent was real and the
reasoning looked sound.

It cannot work, and the player tested it: Roll the Bones plus all four outcomes,
all in `aura` mode, renders exactly **one** icon.

The cause is structural. Adoption maps **one Blizzard item frame per
`cooldownID`**, and every linked ID resolves to its base entry's `cooldownID` —
Roll the Bones and its four outcomes are all `cdID 42743`. Five cells, one frame
to borrow, one winner. No logic makes five cells share one frame, because there
is only ever one frame.

Nothing was lost by removing the expansion: `ResolveAura` already walks
`icon.linkedSpellIDs` and shows whichever outcome is live, which is why the base
placement works and reports `linked=4`.

It was not a Roll the Bones quirk either. **20 of the player's 31 tracked-buff
entries carry linked IDs**, so the picker was offering roughly twenty rows that
could never draw — and four of them under a *different name* (Gravedigger →
Palmed Bullets, Unseen Blade → Fazed, Coup de Grace → Escalating Blade, Cloud
Cover → Smokescreen), which reads as a separate trackable buff rather than a
duplicate.

**The general shape, worth carrying to any similar problem:** when the game
refuses to tell an addon a fact, check whether Blizzard's own UI has already
rendered that fact into something an addon *is* allowed to read. Their frames are
computed by untainted code from data we cannot touch, and their geometry and
visibility are readable. That is a legitimate channel, and it needs no taint and
no guessing.

## 14. Odds and ends worth not rediscovering

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

## 15. We were tainting Blizzard's frames, and their code was throwing on it

**Measured 2026-08-09, from `!BugGrabber.lua` sessions 112–115.** This is the
answer to "the cooldown feature keeps disabling itself and needs a `/reload`",
and it is a genuine exception to §12 — read both or you will draw the wrong
conclusion from either.

§12 says "tainted by 'ThugUI'" is the engine telling you *this is addon code*,
and that is right **when the erroring file is ours**. These errors were in
Blizzard's:

```
session 113  CooldownViewer.lua:904          compare a secret number            x534
session 114  CooldownViewer.lua:992          compare 'previousCooldownChargesCount' x17768
session 115  CooldownViewerItemData.lua:454  boolean test on 'hasTotem'         x1160
session 115  CooldownViewer.lua:425          compare field 'sourceUnit'         x1
```

Counts are per error *site*, and BugGrabber stores them per record — read the
`counter` that follows a message inside its own record, not the nearest one. Two
of these were first written down against the wrong lines for exactly that reason.
The `x1` on `sourceUnit` is not insignificance; it is a buff being re-applied
once and failing to attach.

Blizzard's code is not addon code. If it reports our taint, **we put it there.**
The clean control from the same log: across ~90 installed addons, exactly one
other case exists (`tRP3_Vendor` doing the same to `TextStatusBar`). Everybody
else errors in their own files.

### The mechanism, and why it looks like the feature being switched off

A frame written to by addon code is tainted, and a tainted frame runs **its own**
handlers tainted by us. Blizzard's viewer then reads fields that are secret under
taint and throws *inside its own OnEvent*. The throw aborts the function it is
in, and the two that matter are:

- `RefreshLayout` → `Pools:ReleaseAll` — aborts halfway, so the item pool empties
  and never refills. Symptom: `CVBUFF: no Blizzard buff item frames found`, an
  empty cell, and Edit Mode showing no cooldown windows at all.
- `NeedsAddedAuraUpdate` compares `auraInfo.sourceUnit` to decide whether a newly
  applied aura belongs to an item. Symptom: **a buff that counts down correctly
  but never reappears when re-applied.** An aura already attached keeps
  refreshing; a *new* one can never attach.

Both clear on `/reload`, because the frames are rebuilt untainted. That is why
the bug always looked like "it works until it doesn't".

### The two sources, in the order they were found

**1. A frame-name collision, from the first commit.**
`ER:CreateECV()` created its bar as `CreateFrame("Frame", "EssentialCooldownViewer", …)`.
That predates the Cooldown Manager; 11.1.5 then shipped a Blizzard frame with
exactly that name. Ours overwrote the global from tainted code, so Blizzard's own
code resolving the viewer by name executed tainted. It ran unconditionally at
load regardless of `showECV`, which also explains the long-standing puzzle of the
resource ring reporting an unreadable power value five seconds into a session
with no combat. Every sibling frame in that file was already `ThugUI_`-prefixed;
this one was the outlier. Renamed to `ThugUI_EssentialCooldownViewer`.

**Verified by the logs either side of the change:** session 114 (before) tainted
`EssentialCooldownViewer`; session 115 (after) tainted only
`BuffIconCooldownViewer`.

**2. `BlizzBuffs.lua` touching the buff viewer.** Four vectors; three were
avoidable and are gone:

| Was | Now |
|---|---|
| `item.__thugBaseWidth`, `viewer.__thugStrata/__thugLevel/__thugHooked` | weak-keyed side tables in the module |
| `viewer:SetFrameStrata/SetFrameLevel` to lift it above our grid | our own icon drops to the viewer's strata, which we may read freely |
| `pcall(viewer.RefreshLayout, viewer)` to put items back | the item's original anchor is recorded and restored with our own `SetPoint` |
| `item:SetScale/ClearAllPoints/SetPoint` | **kept — this is the feature** |

The general rule, worth carrying to any addon: **writing a field onto a Blizzard
frame is not free bookkeeping, it is a taint.** `hooksecurefunc` is fine; it
exists to be taint-safe. Reads are fine and cost nothing — which is why the
strata fix works from our side.

### Answered: the remaining vector is safe

`SetPoint`/`SetScale` on a pooled item does **not** taint it. Verified 2026-08-09
across a long combat test with re-application: `!BugGrabber.lua` sessions 116 and
117 recorded **zero errors of any kind**, against 534 and 1160-count runaways in
113 and 115. The design stands as built.

So the boundary is not "touching their frames" in general — it is **writing to
their tables, changing their managed properties, and calling their methods**.
Anchoring and scaling a pooled child are fine. The three regression cases in
`Tests/loadtest.lua` pin the fixed vectors open so a future change cannot quietly
reintroduce them.

### Why the addon does not add buffs to Blizzard's tracked lists for you

Asked 2026-08-09, and the answer is no — checked against the generated docs and
their settings source rather than assumed.

`C_CooldownViewer` has exactly one write in its whole surface: `SetLayoutData(data)`,
where `data` is an opaque `cstring` holding the **entire** cooldown-viewer layout.
There is no per-spell, per-category setter. Blizzard's own UI does not use it
directly either — it goes `CooldownViewerSettingsItemMixin:AssignToCategory` →
`dataProvider:SetCooldownToCategory` → serializer → `WriteData`, all inside
`Blizzard_CooldownViewerSettings`, which is load-on-demand.

Both routes are bad for us:

- **Via `SetLayoutData`:** we would read the blob, parse an undocumented and
  unversioned format, mutate it, and write the whole thing back. The failure mode
  is wiping the player's entire Cooldown Manager configuration — every viewer,
  every category — on a format change we did not anticipate.
- **Via their data provider:** force-load their settings addon and run their
  mutation and `RefreshLayout` on our tainted stack. That is precisely §15's bug,
  reintroduced deliberately, on the code path that persists settings.

So it stays manual, and the constraint is stated in the open on the Cooldown
Viewer page rather than only in a tooltip. Revisit only if Blizzard ships a
scoped setter.

## 16. The raid frames are gone, and this addon does not manage unit frames

Removed 2026-08-10. `modules/RaidFrames/` (Core + Settings) and
`ui/pages/RaidFrames.lua` are deleted, along with the 27 `rf*` keys in
`ER.defaults`, the Blizzard subpanel, and the config page.

**Why they existed at all.** One problem, and only one: mousing over the
player's own buff icons in the cells of Blizzard's default raid frames popped a
tooltip the player could not get rid of. Owning the frames meant owning the aura
icons, and an icon we create never has a tooltip wired to it. Everything else
the module did — layout, health colouring, range fading, group-by — was the cost
of that one fix, not the goal.

**Why they are gone.** The tooltip problem is now handled outside ThugUI, so the
module was paying for something already solved. ThugUI enhances the default UI;
managing unit frames is a different job with a much larger maintenance surface,
and the player does not want it.

**The removal was a no-op, and that was checked rather than assumed.**
`ThugUI_Config.rfEnabled` was already `false` in the live SavedVariables, so
nothing here had been drawing. The bar for the diff was therefore *zero visible
change*, which is a far easier thing to verify than "the replacement behaves the
same".

### What had to stay, and why each one nearly went

Removing a module built on a shared library is mostly an exercise in not
over-deleting. Four things looked like raid-frame code and were not:

- **`libs/oUF/` stays.** `modules/TargetOfTarget/Core.lua` is built on it too.
  The raid frames were its largest consumer, not its only one.
- **`ER.CreateScrollablePanel` / `ER.CreateSeparator` stay.**
  `TargetOfTarget/Settings.lua` uses both. Only the comment naming
  `RaidFrames/Settings.lua` as the sharer was wrong.
- **`rfCornerLabel`, `rfCornerDropdown`, `rfScaleSlider` and the rest of the
  `rf*` locals in `EssentialRings_Settings.lua` (~946–1180) stay.** These are
  **Reforestation** controls on the legacy ECV panel — they read
  `ecvReforestationCorner` and `ecvReforestationScale`. The `rf` prefix is a
  coincidence. A blind `rf*` sweep is the obvious way to do this job and it
  would have silently gutted the fallback bars that exist precisely to be the
  escape hatch.
- **`RAID_CLASS_COLORS` in `Tests/loadtest.lua`** is a stub the vendored oUF
  reads. Deleting it breaks the harness for Target of Target.

### Leftovers that were deliberately not cleaned

The `rf*` keys still sitting in the player's `ThugUI_Config` are left alone.
Nothing reads them now, so they are inert; WoW was running at the time, which
means any edit would have been overwritten at logout anyway (see `CLAUDE.md`);
and keeping them means a revert costs nothing.

Harness after the change: **156 passing, 0 failures**, down from 160. The four
that went are exactly the two file-load assertions, the page-load assertion, and
`page raidframes` — `loadtest.lua` derives those from `ThugUI.toc` and
`ThugUI.Window.pages`, so they disappeared mechanically. No behavioural
assertion was lost, and that was confirmed by diffing the `ok` lines against a
stashed clean tree rather than by reading the count.

## 17. An adopted buff is anchored to our cell but lives in Blizzard's frame

Symptom: on the resto druid, Abundance and Omen of Clarity drew noticeably
larger than every other icon on the grid, and collapse looked broken around them
because an oversized icon overflows the cell the layout maths reserved for it.
Changing Blizzard's own frame size did nothing. Rogue was unaffected.

### Why the rogue looked right and the druid did not

It is the same code. The difference is entirely in the profile.

`BlizzBuffs` adopts a Blizzard buff item by **anchoring** it over our cell —
`item:SetPoint("CENTER", icon, ...)` — and deliberately **not** reparenting it;
the item stays a child of Blizzard's viewer. That is on purpose (§15: writing
into their frames is what broke the cooldown viewer). The consequence is easy to
miss: our own icons are children of the grid frame, which carries
`f:SetScale(profile.scale)`, and **an adopted item inherits none of it.**

`FitItem` then computed `iconSize / base`, where `iconSize` comes from
`CV:GetCellSize` and is *unscaled*. So the item was sized in our grid's
coordinate space and applied to a frame living in Blizzard's.

At `profile.scale == 1` the two spaces coincide and the arithmetic is correct —
which is the whole reason this survived. Outlaw, the testbed for every buff
feature to date, is at scale 1. Resto is at **0.6**, where an adopted buff draws
`1 / 0.6` ≈ **1.67×** too large next to correctly-scaled neighbours.

Nothing about the *spell* differs. Abundance and Omen of Clarity are simply the
only two `aura`-mode placements in spec 105, and `aura` mode is the only path
that goes through adoption. Every other resto icon is `cooldown` mode and drawn
by us, correctly.

The fix works in screen space:

```lua
local scale = (iconSize * cell:GetEffectiveScale())
            / (baseWidth[item] * item:GetParent():GetEffectiveScale())
```

`GetEffectiveScale` on both sides cancels UIParent out, so it holds at any UI
scale, and it absorbs whatever Edit Mode did to Blizzard's viewer as well —
which the old formula also ignored.

### A second defect, found on the way and independent of the first

`FitItem` cached its width measurement as `false` when the item reported a width
of 0, and guarded re-measurement on `~= nil`. **A falsy answer therefore latched
for the life of the item**, and `SetScale` was never called again — leaving
Blizzard's native size inside a cell sized for ours. An item measured before
their layout has run is exactly that case, and it is timing-dependent, so it
would appear and disappear between sessions for no visible reason.

Now only a real width is ever stored; an unmeasurable item is retried next pass.

### Testing

Four cases in `Tests/loadtest.lua`, asserting the item's **on-screen** width
against the cell's rather than the raw scale number — the former is what the
player sees, the latter is only a means to it.

Both defects were confirmed by reintroducing each one separately:

- Restoring the grid-space formula fails the three scale cases and **passes the
  scale-1 case**, which is the proof that the old code was correct at scale 1
  and that this is genuinely scale-specific.
- Restoring the `false` latch fails only the retry case.

`FitItem` also logs its numbers once per session (`CVBUFF: fit: base=… icon=…
ours=… theirs=… -> scale=…`), so a wrong size on screen can be read back from
disk instead of guessed at.

**Unverified in game.** Built on branch `abundance-icon-scale`.

## 18. The layout and the collapse must agree on where the cursor is

Symptom: on the resto druid the columns collapsed **upwards, away from the
cursor**; on the rogue, with what looked like the same settings, they collapsed
down towards it. The player's own diagnosis was exactly right — "it thinks the
cursor is above" — and it was true of the collapse only, not the layout.

Two functions decide the same fact with different comparisons.

`CV:FollowCursor` places the shape (`Core.lua`):

```lua
local gapY = (profile.anchorRow or 0) >= Data.GRID_ROWS / 2 and gap or -gap
```

`Data.ResolveCollapseAxes` packs it "towards the cursor":

```lua
local autoDown = (profile.anchorRow or 0) > Data.GRID_ROWS / 2   -- was strict
```

`>=` against `>`. At `anchorRow == 5` on a 10-row grid they disagree: the layout
nudges the shape **above** the pointer, and the collapse then packs it **up**,
away from it. Both axes had it; only the axis that landed on the boundary
misbehaved, which is why one spec looked broken and another did not.

The player's profiles made it look like a difference between specs:

| | anchorRow | `>= 5` (layout) | `> 5` (collapse) | |
|---|---|---|---|---|
| Resto | **5** | above cursor | packs up | **disagree** |
| Outlaw | 6 | above cursor | packs down | agree |

Outlaw was correct by being one row clear of the boundary, not by being
configured differently. Nothing was wrong with saving or loading the profile —
that was checked first, and `anchorCol=3, anchorRow=5` on disk matched the
picker exactly.

### Which comparison is right

**The layout is the source of truth.** It decides where the shape physically
sits; "towards the cursor" is only meaningful relative to that. So the collapse
was changed to match the layout, not the other way round.

The midpoint is a real anchor position rather than a rounding artefact — the
grid is 10×10, so intersection 5 is dead centre and is exactly what a player
gets by aiming at the middle of the picker. It is not a rare edge case.

### A test was changed, not just added

`auto direction follows the anchor` asserted `dead centre should fall to left`.
That recorded the tie-break of the old strict `>`, and this change deliberately
reverses it to `right`. Dead centre was never genuinely ambiguous: the layout
had already committed to putting the shape left of the pointer there, so the old
answer was the layout's opposite. Called out here because a changed assertion is
much easier to miss in review than an added one.

Two cases were added that assert the two functions **against each other** rather
than against a hardcoded direction, so a future change to either comparison
fails rather than silently reintroducing the split. Reverting the fix fails
exactly those two plus the changed one.

### The boundary was a symptom; the rule itself was wrong

Fixing the comparison made the player's profile behave, but only by making a bad
rule land right. The rule asked **where the anchor sits on the grid**, which is
merely a proxy for **where the shape sits relative to the anchor** — the thing
"pack towards the cursor" actually depends on. The two part company as soon as a
shape is not roughly opposite the anchor across grid centre:

> `anchorRow = 7`, icons at rows 8 and 9. They are below the cursor, so towards
> it is **up**. The midpoint test says `7 >= 5` and packs **down**, away.

That case is wrong under the `>=` fix too, so the comparison was never the whole
story.

`auto` now reads the placements. `CV:FollowCursor` offsets the container by
`anchorRow * cellH`, which makes intersection R the bottom edge of cell row R:
a cell at or before the anchor is above the cursor, one after it is below, and
the same holds on x. That is exact, not a heuristic. The bulk of the occupied
cells decides the axis, and packing towards the cursor is the opposite of where
the bulk lies.

Tie-breaks, both of which are genuine judgement rather than derivable:

- **An even straddle** — equal cells either side — falls back to the old
  grid-midpoint test.
- **An empty grid** does the same, since there is no shape to read.

### One source of truth

`Data.ResolveAutoAxes` is now the only place this is derived, and both the
collapse *and* `CV:FollowCursor`'s gap nudge call it. Two functions deriving the
same fact separately is what caused the original split, so the fix is not just
matching the comparisons but removing the second derivation entirely. A test
asserts the two agree, so re-inlining the test in either place fails.

**This changes behaviour on existing profiles** wherever the placements disagree
with the old grid-centre guess. That was accepted deliberately: the old answer
was wrong in those cases, it just was not always visible.

**Unverified in game.** Built on branch `collapse-anchor-boundary`.

## 19. Combat hides charges too, so Blizzard draws those cells as well

**Diagnosed and built 2026-08-10.** §13 established that an addon cannot
identify an aura in combat and that the answer is to borrow Blizzard's own buff
item. The same wall turns out to stand in front of *cooldowns*, and the fix
generalises to exactly the same shape.

### What was actually wrong

Two reports that looked like one bug and were two:

| Report | Path | Mechanism |
|---|---|---|
| Bear icon draws but never sweeps | `always` mode → `ApplySweep` | `SetCooldown` refuses the secret `startTime`, so the radial never draws. `always` shows the icon unconditionally, so the missing sweep IS the whole symptom |
| Grappling Hook "always ready" | `cooldown` mode → `IsSpellReady` | `currentCharges` is secret in combat, so the charge branch fails open |

Both read as "the icon lies about being ready", which is why they looked like
one fault with a shared cause in charge handling. They share a *theme* — combat
hides the value — not a code path.

**The player's own test separated them**, and it is the cleanest evidence in
this whole investigation: Grappling Hook behaves correctly out of combat and
lies during it. That is the secrecy boundary and nothing else.

### Three things that cost time, kept so they are not re-derived

**An uncaught throw in `UpdateState` is far worse than the thing that threw.**
The loop at `Core.lua` iterates `pairs(self.icons)`; the `SetCooldown` refusal
unwound it, so every icon not yet visited kept its previous state and
`ApplyLayout` never ran. `pairs()` order is undefined, so *which* icons froze
changed between sessions and the symptom appeared to move around on its own.
Anything called per-icon in that loop needs to be incapable of throwing.

**The harness stub was more permissive than the game.** `SetCooldown` in
`Tests/loadtest.lua` accepted secrets happily, so no test could ever have caught
this. It now refuses them exactly as the client does. A stub that is kinder than
reality cannot fail a test reality fails — that is worth a sweep of the other
stubs.

**"Maul" was Mangle.** The Guardian profile had no Maul in it; the icon that
threw was Mangle (33917) in `always` mode. Read the captured locals in
BugGrabber before trusting the spell name in a bug report — they carry the mode,
the cell and the whole `cdInfo` struct.

### The rule for which cells Blizzard draws

`BB:ShouldAdopt`. Adopt exactly what we provably cannot render in combat:

- **aura mode** — cannot identify an aura at all (§12, §13)
- **always mode** — the sweep is the readiness signal and it is refused
- **any multi-charge spell** — `currentCharges` is secret, readiness fails open

And deliberately not:

- **an ordinary single-charge cooldown.** `isActive` is readable in combat, so
  our own rendering is already correct. Adopting it would trade away the proc
  glow and hide-when-spent for nothing.
- **proc mode, even for a charge spell.** Its entire point is "show only while
  the proc is up", and Blizzard's item knows nothing about that — it would sit
  on screen permanently and the mode would lose the one behaviour it has. A
  charge spell the player wants borrowed belongs in `cooldown` or `always` mode.

Charge-ness is cached per spell ID and resolved **out of combat only**, because
`maxCharges` is secret mid-fight and this decides whether a cell is adopted for
the session. An unreadable answer is not stored — absent means "ask again",
which is the mistake `FitItem`'s `baseWidth` already made once by caching a
falsy measurement for the life of an item. The cache expires with
`Data.InvalidateCooldownInfoCache`, since a talent can add charges to a spell
that had none.

### Two consequences the player accepted

An adopted charge spell **stops disappearing when spent**. Blizzard's cooldown
item sweeps and dims instead of hiding, and hiding it ourselves would need the
charge count we cannot read. Better information, different look.

`AdoptedCellWanted` needed a second branch for the same reason: its fallback
asks "is the aura up", which answers no forever for a cooldown item and would
have collapsed the cell **out** of combat — precisely when the player is looking
at their layout.

### The risk to watch in game

§15 records that when we tainted Blizzard's viewer, the field their code choked
on 17,768 times in session 114 was **`previousCooldownChargesCount`**. Charges
are exactly what blew up last time. The BlizzBuffs discipline — no field writes
on their frames, no strata on the viewer, never call their methods, anchor and
scale only — is what made buff adoption safe and is unchanged here, but this
path is more likely to trip it than buffs were. Watch BugGrabber for
`Blizzard_CooldownViewer` errors on the first combat test.

**Unverified in game.** 175 passing, 0 failures.

## 20. 12.1 went live and changed the rules we built around

**Read from Blizzard's source on 2026-08-11**, `Gethe/wow-ui-source` branch
`live` @ 12.1.0 build **69273** — the exact build installed on this machine
(`.build.info`). Everything in this section was a documented flag or enum when it
was written, not an observed behaviour.

**It has since been measured.** The player ran the probe through a full combat on
2026-08-11 at 21:05 and the results are at the end of this section, under
"Measured". Where the measurement and the documentation disagree, the
measurement wins and the paragraph above it has been left standing so the
disagreement stays visible.

`## Interface:` is now **120100**, confirmed against other addons on disk rather
than assumed from the version number.

### The header: secrecy stopped being all-or-nothing

12.0.7 gave us one rule — *a tainted addon cannot read a protected value, and
cannot pass one to a setter either.* Every design decision in §5, §12, §13 and
§19 follows from that second half.

**12.1 splits the two.** A new `Enum.SecretAspect` (30 values: `Shown`, `Alpha`,
`Text`, `BarValue`, `Cooldown`, `RadialProgress`, `Desaturation`, …) names each
property of a widget that can be *holding* a secret, and every setter now
declares one of two postures:

| Declaration | Meaning for us |
|---|---|
| `SecretArguments = "AllowedWhenUntainted"` | unchanged from 12.0.7 — we may not pass a secret |
| `SecretArguments = "AllowedWhenTainted"` + `SecretArgumentsAddAspect` | **we may pass a secret.** The widget takes on that aspect: it renders correctly and we can never read the value back |

That second row did not exist before. It is the whole of "more flexibility with
your UI", and it means the addon can now *display* things it still cannot
*know*. Reading is as restricted as it ever was — the change is that we no
longer have to read in order to draw.

Setters that now accept a secret from us: `StatusBar:SetValue`,
`StatusBar:SetMinMaxValues`, `FontString:SetText`, `FontString:SetFormattedText`,
`Texture:SetDesaturated`, `Texture:SetDesaturation`, `Cooldown:SetDrawSwipe`,
`SetDrawEdge`, `SetDrawBling`, `SetSwipeColor`, `SetEdgeColor`.

Setters that **still refuse** one, so do not plan around them:
`Region:SetShown`, `Cooldown:SetCooldown`, `SetCooldownDuration`,
`SetCooldownUNIX`, `SetCooldownFromExpirationTime`.

**`SetShown` refusing a secret is the load-bearing negative.** "Hide this cell
when the buff drops" is still unanswerable from a secret boolean, which is why
§13's adoption of Blizzard's frames is not obsolete. `SetDesaturated` accepting
one is the near-miss worth knowing: we can *grey* a cell on a secret condition
even though we cannot *hide* it.

### Duration objects: an opaque handle for a timer we may not read

The other half of the change is a new object type, `LuaDurationObject` — a live
timer held without ever seeing a number in it. Two producers matter:

```
C_Spell.GetSpellCooldownDuration(spell, ignoreGCD)  -> LuaDurationObject
C_Spell.GetSpellChargeDuration(spell)               -> LuaDurationObject
```

**Neither carries a `SecretWhen*` flag.** `C_Spell.GetSpellCharges`, a few
entries above them in the same file, carries `SecretWhenCooldownsRestricted` —
so the contrast is deliberate, not an omission. Both are `MayReturnNothing`.

Consumers: `Cooldown:SetCooldownFromDurationObject`,
`StatusBar:SetTimerDuration`, and a new `DurationTextBinding` object that drives
a FontString from a duration with its own formatter, colour curve and update
interval.

This is the exact shape of §19's wall. §19 concluded that `always` mode cannot
sweep in combat because `SetCooldown` refuses the secret `startTime`, and that
Blizzard's item therefore has to draw the cell. **`SetCooldown` still refuses
it** — but we no longer need to call `SetCooldown`, because the duration-object
route never surfaces a number to refuse. If it behaves as documented, ThugUI can
draw its own sweep in combat and §19's adoption rule shrinks towards aura mode
alone.

`MayReturnNothing` is a second prize: *no duration returned* means *no cooldown
running*, which is a non-secret readiness test that does not go through
`isActive` at all.

### The ring was written off too early

`KNOWN-ISSUES.md` records the resource ring's exact level as permanently
impossible, on the reasoning that "a straight bar could take a secret; a ring
cannot". `UnitPower` is indeed still `SecretWhenUnitPowerRestricted`.

But 12.1 adds `StatusBarRenderMode.Radial` — *"render the status bar by driving
the managed texture's radial progress fill percent instead of resizing the
texture anchors"* — and `StatusBar:SetValue` is one of the setters that now
takes a secret from tainted code. **A radial StatusBar is a ring, and it accepts
the value we are not allowed to look at.** The premise held; the conclusion drawn
from it did not survive the patch.

### Items are not protected the way spells are

12.1 puts trinkets, potions and healthstones in the Cooldown Manager, in four new
categories (`EquipSlotEssential`, `EquipSlotTracked`, `SpecAgnosticEssential`,
`SpecAgnosticTracked`) plus `GroupBuff`, and they surface in Blizzard's settings
under **"Not Displayed: Items"**.

`C_Item.GetItemCooldown` carries **no `SecretWhen*` flag at all**. Item cooldowns
are plain numbers in combat. So an item cell needs none of the machinery a spell
cell needs — our own icon, our own sweep, and hide-when-used all work with the
ordinary logic that predates the whole secret-value problem.

**They cannot be placed today, and the reason is structural.** Every placement in
this addon is keyed by spell ID. These entries are identified by `equipSlot` (the
trinket in that slot, whatever it happens to be) or by `spellCategoryID` (4 =
combat potion, 30 = health potion, 1711 = healthstone — the constants are in
`CooldownViewerItemData.lua`), and their `spellID` is nil. `Data.PickerSpellIDFor`
returns nil for them and they are dropped from the picker silently, which is the
same failure shape as the Roll the Bones entry that once went missing.

Note what the shared-cooldown potion entry actually is: **one cell that tracks
whichever potion was last drunk**, resolved at use time through
`C_Spell.GetLastCategoryCooldownSource(spellCategoryID)`. There is no fixed spell
behind it, by design.

### The nilable `spellID` had already broken the cache

`CooldownViewerCooldown.spellID` became nilable in 12.1. `BuildCooldownInfoCache`
built its index list as a table constructor —
`{ info.spellID, info.overrideSpellID, info.overrideTooltipSpellID }` — which
leaves a **hole** at index 1 when `spellID` is nil, and `ipairs` stops dead at a
hole. An entry with no base spell but a non-nil override, and no linked spells to
fill the gap in, was never indexed under anything, so any placement naming it
resolved to `no Cooldown Manager entry` and drew an empty cell.

On 12.0.7 this could not bite: `spellID` was non-nilable, and the one entry shape
with no base spell (Roll the Bones) had all three fields absent, so the hole sat
at index 1 and `table.insert` happened to fill it in. Fixed by appending non-nil
IDs one at a time (`Data.IndexableSpellIDs`), with a regression case that fails
against the old constructor. **The lesson outlives the bug: a table constructor
is the wrong container for a list of maybe-nil values, and a field going nilable
in a patch is enough to turn one into silence.**

### Checklist items now answered from source, without the game

- `isInvisible` is **still inert** — `CDM_HIDE_INVISIBLE_ITEMS = false` on live,
  still flagged as debug code slated for removal.
- The negative pseudo-categories **were renamed** to `HiddenActive` /
  `HiddenPassive`, exactly as the PTR predicted. Filtering by value rather than
  by name is why nothing had to change. Blizzard's own
  `CooldownViewerUtil.IsDisabledCategory` still names the old
  `HiddenSpell`/`HiddenAura` and now compares against nil.
- No `C_CooldownViewer` function and no `CooldownViewerCooldown` field gained a
  `SecretWhen*` flag, so §13's cooldownID matching is safe.
- Still only **four** viewer frames — `BuffIcon`, `BuffBar`, `Essential`,
  `Utility`. The new categories get no frame of their own; the player assigns
  entries into one of the four, so `BB`'s `VIEWER_NAMES` needs nothing added.
- `GroupBuff` is **not** in Blizzard's own `cooldownCategories` list. It is a
  separate system (`C_CooldownViewer.GetGroupBuffItems`,
  `C_UnitAuras.SetHiddenGroupBuffs`) for filtering raid buffs, with no viewer
  frame behind it. Our "Everything" picker iterates the enum, so it will ask for
  that category — if the game answers with rows, they are rows nothing can draw.
  **Check the probe before deciding whether to exclude it.**
- `RequiresUnitAuraAccess` now has a documented failure mode: **`Error`**, not
  "return nothing". `RequiresNonSecretAura` is separately documented as returning
  no values. §12's expectation that the index/slot/instanceID aura calls would
  start erroring is now Blizzard's stated behaviour, so the fallback list walk in
  `Core.lua` is on borrowed time exactly as predicted.

### What the player confirmed on patch day, before any of this was written

Swiftmend gained a second charge overnight and **the existing code picked it up
with no change** — it is adopted as a charge spell by §19's rule, drawn by
Blizzard's item with a radial sweep and a charge count. Nothing was hardcoded and
nothing had to be. That is the §5 "resolve by name at runtime, never hardcode a
spell ID" rule paying out on a patch nobody had tested against.

**176 passing, 0 failures.**

### Measured — one combat, 2026-08-11 21:05, Restoration

`ThugUI_DebugLog.secrets`, five phases: idle, 1s / 5s / 12s into combat, and
combat end. Charge spells chosen at runtime by `info.charges == true`, which
picked Swiftmend, Mangle and Nature's Cure.

**The duration-object route works, and the refusal it replaces is in the same
sample.** Seconds apart, on the same widget, mid-combat:

```
Cooldown:SetCooldownDuration(secret)   REFUSED: Secret values are only allowed
                                                during untainted execution
SetCooldownFromDurationObject          accepted
SetTimerDuration                       accepted
StatusBar:SetValue(secret)             accepted
Frame:SetAlpha(secret)                 accepted
Curve:Evaluate(secret)                 REFUSED
```

Accepted at **every** phase, not only out of combat. §19's central constraint —
"the sweep is the readiness signal and `SetCooldown` refuses the secret
`startTime`" — is lifted. It was never the sweep that was forbidden, only the
route to it.

**`Curve:Evaluate` refusing a secret closes the obvious derivation.** Mapping a
secret number to a secret 0/1 through a curve was the natural way to compute
"should this be greyed" without comparing. It is not available.

#### What the charge measurement actually said

| | idle | combat | on ending |
|---|---|---|---|
| `charges.current` Swiftmend | 2 | **SECRET** at all four combat points | 1 |
| `charges.max` Swiftmend | 2 | **2 — readable** | 2 |
| `cd.isActive` | false | true | false |
| `isUsable` | **false** | true / false / true | true |

Three conclusions, two of which correct things written above:

- **`currentCharges` is secret in combat.** §19 stands.
- **`maxCharges` is NOT secret in combat**, contrary to §19's "maxCharges is
  secret mid-fight". `BB:IsChargeSpell` caches out-of-combat-only for a reason
  that turns out not to hold. The cache is not wrong, it is unnecessary, and
  `info.charges` from the Cooldown Manager is a simpler source again — a plain
  bool, talent-aware (Swiftmend reads true), on a function with no secrecy flag.
- **`IsSpellUsable` cannot answer "is a charge banked".** Swiftmend at a full 2/2
  charges reads `isUsable = false` while idle, and Mangle reads false in every
  phase — the resto druid is not in bear form. It is tracking target validity and
  form, exactly as its tint-only use in Blizzard's own `RefreshIconColor`
  implied. §20 guessed this; it is now measured.

**And the readiness-by-absence idea is dead.** Both duration getters returned a
`LuaDurationObject` at every phase — including idle, at full charges, with
`isActive = false`. `MayReturnNothing` does not mean "nothing when ready", so the
presence of a duration object is not a readiness signal.

#### The route that is left: alpha, not visibility

`SetShown` still refuses a secret. `SetAlpha` **accepts** one, and alpha clamps
to 0–1 while `currentCharges` is a secret number 0, 1 or 2. So

```lua
icon:SetAlpha(chargeInfo.currentCharges)   -- 0 -> invisible, 1+ -> opaque
```

hides a spent charge spell during combat **without any comparison**, which is the
operation that errors. Nothing is read; the clamp does the work.

The cost is real and must be stated wherever this is used: **alpha zero is not
hidden.** The frame still occupies its cell, so a column holding a spent charge
spell will not collapse around it during combat the way §13's adopted buff cells
do. It disappears visually and keeps its space.

#### Two answers that came free with the same fight

**The aura APIs now throw, as §12 predicted and §20 could not confirm:**

```
GetAuraDataByIndex      ERROR: Auras cannot be accessed when secret
                               while tainted by 'ThugUI'
GetUnitAuraInstanceIDs  ERROR: (same)
```

`RequiresUnitAuraAccess`'s documented `FailureMode = "Error"` is what the client
does. The by-spell lookups still return `nothing` rather than erroring, matching
`RequiresNonSecretAura`. **`Core.lua:284` is `pcall`-guarded, so the grid is
safe** — but the fallback list walk is now permanently dead in combat and should
stop being described as a fallback.

**Blizzard's frame visibility is readable in combat.** The measurement the
handoff had been carrying as "taken but unread" since 2026-08-09:

```
CVBUFF: spell Abundance: item IsShown readable = false (combat=true)
```

*readable = false* means readable, value false — the buff was down. So
`IsShown()` on their item is a live, non-secret, buff-active signal that survives
combat. That is the foundation §13 was built on, now confirmed rather than
assumed, and it generalises past the cooldown viewer: **reading a frame's shown
state is not reading an aura**, and Blizzard's untainted frames will answer
questions the API will not.

#### Why the trinket only drew in `always` mode

Not a mystery once the order is read. `Core.lua:773` — "adoption outranks our own
`IsSpellAvailable` check" — sits above the availability gate at `:785`, and the
mode branches are below at `:840`.

`always` mode makes `BB:ShouldAdopt` true on the mode alone, so the cell is
adopted and the gate never runs. `cooldown` mode adopts nothing, reaches
`IsSpellAvailable(spellName)`, and that resolves **by name** — which is
spellbook-scoped, and a trinket's on-use spell is not in the spellbook. It
answers "not talented" and the icon never draws.

**The §5 by-name rule is right for spells and wrong for items.** The same rule
that let Swiftmend gain a charge with no code change is what hides a trinket. An
item is identified by the slot it sits in, and its cooldown comes from
`GetInventoryItemCooldown` — which Blizzard's own `CooldownViewer.lua:1020` uses
and which carries no secrecy flag. Task 14.

## 21. Charge spells hide themselves again, by never asking whether they are spent

**Task 15, 2026-08-12. Correct in code and in the harness; unverified in game.**

§19 handed every multi-charge spell to Blizzard's viewer, because `IsSpellReady`
fails open when `currentCharges` is secret and an icon that lies is worse than an
icon Blizzard draws. §20's combat measurement removed the reason. Charge spells
in `cooldown` and `proc` mode are ours to draw again.

The whole design is one line, and its value is what it does *not* do:

```lua
icon:SetAlpha(chargeInfo.currentCharges)   -- secret 0 -> invisible, 1 or 2 -> opaque
```

`SetAlpha` accepts a secret and clamps it to 0–1. Nothing is read, nothing is
compared, and **comparison is the operation that throws**. The spell hides when
spent without our code ever being told it was spent.

### Why the third return exists, and why it can never be nil

`IsSpellReady` returns `ready, charges, alpha`. The third value is `1` on every
path except the one fail-open branch, where it is the secret count itself.

It would have been natural to return `nil` for "no alpha needed" and let the
caller test. That test is the bug: `alpha ~= nil` against a value that may be
secret is a comparison, and it throws. The alternative — a fourth boolean return
saying "is the third one safe to use" — is worse than one function that always
answers safely. **All secret handling stays inside `IsSpellReady`, whose comment
block exists for exactly that purpose.** A caller should never have to know.

### What is deliberately not covered

- **`recharging` mode.** Its inverse needs `1 - currentCharges`, which is
  arithmetic on a secret and is refused. A charge spell placed there keeps the
  old fail-open behaviour in combat. Not an oversight.
- **`always` mode.** Still adopted, so we draw nothing to fade.
- **The cell still holds its space.** Alpha zero is not hidden. `ApplyLayout`
  collapses on `if icon.wanted then`, a plain Lua truth test, and setting
  `wanted` from a secret is a branch on a secret.

**The player was offered a workaround and declined it on 2026-08-12** — parking
a spent icon on a 1×1 frame so the grid closes around it. It fails for the same
reason everything else does: to park the icon you must first know it is spent.
The frame trick was never the hard part.

Worth carrying past this addon: **the client refuses `SetShown(secret)` and
accepts `SetAlpha(secret)`, seconds apart, on the same widget.** That is not an
inconsistency to route around. It is a deliberate line — a secret may change what
you see, never what the layout does — and any scheme that turns a secret into a
position, a size, or a frame's shown state is on the wrong side of it.

Out of combat nothing is secret, so hide-and-collapse works normally. The gap is
combat-only and bounded to the window between spending the last charge and the
first recharge landing.

### `cooldown` mode has no sweep, and that is the mode, not a bug

Chased on 2026-08-12 and worth recording so nobody re-diagnoses it. The player
reported a two-charge Guardian spell that "draws its icon but no radial cooldown
sweep". Reading their SavedVariables settled it: **every Guardian placement is in
`cooldown` mode**, and that mode is defined as *"the icon IS the readiness
signal, so there is nothing to sweep — it simply disappears once spent"*
(`Core.lua`, the `else` branch of `UpdateState`'s spell path).

Two things fell out:

- **The spell was Mangle (33917), not Maul.** Maul is not placed on that grid at
  all. Names were resolved out of `ThugUI_BCVDump` on disk rather than from
  memory — §5's "never invent a spell ID" applies just as much to reading one
  back as to writing one.
- **A charge spell in `cooldown` mode that failed to adopt looked identical to a
  bug.** Under §19 it was handed to Blizzard, and if no matching item frame
  existed the cell fell back to our render: no sweep, and fail-open so it never
  disappeared. Two correct behaviours composing into something that reads as
  broken.

### Two harness gaps found while reviewing this

Both recorded in `Tests/README.md`; noted here because the first one is the same
class of hole as §19's `SetCooldown` stub, which meant no test could have caught
a real bug.

- **The stub's secret does not throw on a nil comparison.** `SECRET` is a plain
  table, so `SECRET > 0` and arithmetic both raise real Lua errors — but
  `SECRET == nil` returns `false` quietly, where the client throws. Code that
  nil-tests a secret before asking `issecretvalue` passes the harness and fails
  in the game. `Readable()` has the ordering right; anything new must use it.
- **A test can depend on the previous test's setup.** `"an adopted cooldown cell
  is kept out of combat"` inherited its icon from the case above it. When that
  case was deleted as obsolete, the survivor kept passing while asserting
  something about a cell that was no longer adopted — a green test whose name had
  become false. It now builds its own state, in `always` mode, which is the
  remaining non-aura adoption case.

## 22. The trinket fix shipped broken under eight green tests

**Found 2026-08-12, when the player tested task 14 in game and reported that
only `always` mode still worked — the exact symptom task 14 was written to
fix.**

One character's worth of cause:

```lua
pcall(ItemLocation.CreateFromEquipmentSlot, equipSlot)            -- shipped
pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, equipSlot)  -- correct
```

`ItemLocation:CreateFromEquipmentSlot(equipmentSlotIndex)` is declared with a
**colon** (`Blizzard_ObjectAPI/Mainline/ItemLocation.lua:15`), so the slot is its
second parameter. The shipped call passed `13` as `self` and nothing as the slot.

**It did not throw, and that is the whole problem.** The function body reaches
the *global* `ItemLocation` rather than `self`, so it happily built a location
with a nil slot, whose `IsValid()` is legitimately `false`. `IsItemAvailable`
therefore answered "nothing is equipped" for every item cell, forever,
`show = false`, and the icon never drew. `always` mode was unaffected because
adoption happens above that branch and skips it — which is precisely the
before-and-after the player described, unchanged by the fix.

### Why every test passed over it

The `ItemLocation` stub was written as a **plain function taking the slot as its
only argument** — matching the *caller* instead of the game. Eight cases then
exercised a code path that could not work in the client, and all eight were
green. Fixing the stub to a colon-declared method makes four of them fail
against the shipped call.

This is §19's `SetCooldown` lesson recurring with the roles reversed, and the
stub's own comment cites §19 while making the mistake. **A stub written from the
code under test proves only that the code is self-consistent.** Write it from
Blizzard's source, and if a call convention is involved, make the stub punish
getting it wrong.

### The replay tool then answered confidently and wrongly

`Tests/replay_probe.lua` reported *"NOTHING — the spell is not indexed at all"*
for a trinket that indexes fine. Its `Enum.CooldownViewerCategory` was a
hardcoded copy of the four **12.0** categories, so `GetCooldownViewerCategorySet`
returned nothing for 12.1's `EquipSlotEssential` and the entry was never visited.
Its `info` table also dropped `equipSlot` entirely.

That tool exists to separate "our logic is wrong" from "the client is
different", so a stale copy of a game enum inside it is worse than useless — it
produced a plausible, specific, false diagnosis that would have sent the next
session rewriting the cache. It now derives the category list **from the dump**,
which cannot go stale, and carries the 12.1 item fields through.

**The general rule: a test double must not hold its own copy of anything the
real input already describes.**

### What this says about the harness as evidence

`Tests/loadtest.lua` proves the code is internally consistent. It cannot prove a
call reaches the game correctly, and on this occasion it actively concealed that
it did not. Three defects — the `SetCooldown` stub (§19), the `ItemLocation`
stub, and the replay enum — have now each hidden a real bug behind green output.

**When a fix targets a Blizzard API we have not called before, the harness is not
evidence that it works. Only the game is.** Say so in the handoff, and get the
player to look before the fix is described as done.

## 23. The resource ring gets a second implementation, and the engine does the arithmetic

**Task 16, 2026-08-12. Correct in code and in the harness; nothing seen in game,
and one question deliberately left open for the player's eyes.**

§20 measured that `StatusBar:SetValue` and `SetMinMaxValues` accept a secret from
our tainted stack — `AllowedWhenTainted` in the generated docs, and accepted at
every phase of a full combat — and that 12.1's `StatusBarRenderMode.Radial`
makes a StatusBar a second kind of ring. This built it.

```lua
f:SetMinMaxValues(0, maximum)   -- plain
f:SetValue(current)             -- secret, accepted
```

**The radial path is markedly simpler than the Cooldown path beside it**, and
that is the tell that it is right: no fraction, no `lastFraction` short-circuit,
no `unreadable` branch, no frozen-ring fallback. All of that machinery exists on
the Cooldown path to cope with not being allowed to compute `current / maximum`.
The engine now does that arithmetic on our behalf, so none of it is needed. When
a rewrite deletes a pile of defensive code rather than adding to it, that is
usually the sign the new mechanism is the right shape.

**Both implementations ship and the old one stays the default.** `CLAUDE.md`
§3 — the ring is in daily use, and this is a design change rather than a bug fix.
`resourceRingRadialBar` is a flat key defaulting to `false`, so nothing about the
player's display changes until they choose it.

**The capability gate is as load-bearing as the happy path.** A radial StatusBar
needs `Enum.StatusBarRenderMode` to exist *and* the frame to have
`SetRenderMode`; either missing must fall back to the Cooldown ring **whatever
the setting says**, and the result is cached so neither the check nor its
`LogOnce` repeats every update. "The setting is on and nothing draws" is
indistinguishable from a broken addon, which is the same failure mode §22's
silent `IsValid()` produced.

**The two frames must not share a global name.** Both can exist in one session
once the setting is flipped, and two frames under one name is what broke Edit
Mode in §15.

### The open question: does a radial fill start where a Cooldown swipe starts?

`StatusBar` has no `SetRotation` — that is a `Cooldown` method. The only
analogue is rotating the managed texture via `GetStatusBarTexture():SetRotation()`,
which is what the code does, with the same `ClockToRadians(castRotation)` value.

**Whether that rotates the fill's start angle or only the artwork beneath a fill
that still starts elsewhere is unknown**, and cannot be settled from the source
or the harness. The enum's own wording — the fill is *"the managed texture's
radial progress fill percent"*, computed rather than anchored — reads as though
the fill is independent of the texture's transform, which would mean the artwork
rotates and the start angle does not. **That is an inference from one sentence of
enum documentation, not a measurement, and it is recorded here as such.**

To check it: flip the setting on at a **mid-range** resource level. At 0% or 100%
a start-angle mismatch is invisible, which is exactly how this would ship
looking fine and be wrong.
