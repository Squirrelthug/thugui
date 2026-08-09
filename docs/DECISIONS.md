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

**`TrackedBar` is deliberately not a separate source.** Tracked bars are drawn
from the same pool as tracked buffs — the same spells, presented either as an
icon row or as a stack of timer bars. Adding it would duplicate the list.

### Entries that stand for a set of spells

Some entries represent several possible buffs rather than one aura. Roll the
Bones grants one of six outcomes and **has no base `spellID` of its own** — it is
defined purely by `linkedSpellIDs`.

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

## 10. Odds and ends worth not rediscovering

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
