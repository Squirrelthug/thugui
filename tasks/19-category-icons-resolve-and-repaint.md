# Task 19 — Category cells: resolve their art, remember it, and repaint

**Read `tasks/00-AGENT-BRIEF.md` first.** This file carries the design
decisions. **Execute them; do not re-decide them.** On a genuine ambiguity,
**stop and report** rather than resolving it.

Baseline from a clean tree: `lua Tests/loadtest.lua .` → **213 passing, 0
failures**. Re-run it yourself before you touch anything and confirm the number.

> `ui/pages/CursorRings.lua` has uncommitted cosmetic edits that are **not
> yours and not part of this task**. Leave that file entirely alone.

---

## The problem

Task 18 made potions and healthstones placeable (`docs/DECISIONS.md` §25). The
player has now run it in game and reported three faults. All three are real and
confirmed in the code.

On a fresh login the picker lists `Consumable (category 4)`,
`Consumable (category 30)`, `Consumable (category 1711)` with question-mark
icons. After entering and leaving combat the picker list **and** the config
window's grid show correct names and icons — but **the cell drawn on screen keeps
its question mark** until the player changes any dropdown, which forces a
rebuild.

### Fault A — the drawn cell paints once and never again

`CV:Rebuild` sets `icon.tex` from `Data.CategoryEntry` at
`modules/CooldownViewer/Core.lua:763-777`. `CV:UpdateState`'s category branch
(`Core.lua:1057-1089`) resolves an item ID for the *sweep* and never touches
`icon.tex`. So the on-screen texture is frozen at whatever was resolvable during
the last rebuild. Changing a dropdown forces a rebuild, which is exactly the
workaround the player found.

### Fault B — nothing resolves at login

`Data.CategoryEntry`'s first resolution path reads Blizzard's pooled item frame
via `BB:ItemForCooldownID`, which walks `pool:EnumerateActive()`
(`BlizzBuffs.lua:243-262`) — **only frames the viewer is currently drawing**.
Before the first combat the viewer draws nothing, so there is no frame, and path
2 (`GetLastCategoryCooldownSource`) has nothing to catch up on either. Both fail
and the generic label is correct behaviour for a broken situation.

### Fault C — `Data.CategoryEntry` is uncached

`Data.lua:859-895` re-runs the whole resolution on **every call**, and
`BB:ItemForCooldownID` rebuilds the entire cooldownID→frame map each time
(`BlizzBuffs.lua:286-296`, which documents that choice as acceptable *because it
is not called every frame*). Fixing fault A means calling it from `UpdateState`,
which would make that comment false.

---

## Decision 1 — the icon is Blizzard's category art, always

**Chosen by the player on 2026-08-13, after seeing it in game.** Do not show the
real item's icon, and do not build a route to it.

The evidence, from `Blizzard_CooldownViewer/CooldownViewerItemData.lua` @ `live`:

```lua
function CooldownViewerItemDataMixin:GetSpellTexture()
	local spellCategoryIcon = self:GetSpellCategoryIcon();
	if spellCategoryIcon then
		return spellCategoryIcon;      -- returns unconditionally, before
	end                                -- any spell-based resolution
```

`GetSpellCategoryIcon` returns a hardcoded per-category texture out of a local
`spellCategoryMetadataLookup`. Blizzard record the triggering item's icon in
`cooldownInfo.lastItemIDForCategoryIcon` and then **deliberately decline to use
it**, with a comment saying so. Their own potion cell shows the same flask
forever.

So the art is a **constant per category**, it is never superseded, and matching
it makes our cell identical to the Cooldown Manager row beside it.

## Decision 2 — resolution order for a category's name and icon

Rewrite `Data.CategoryEntry`'s order to this. First that answers wins, and a
**resolved answer is sticky — never downgrade a resolved entry back to the
generic one.**

1. **The persisted cache** (Decision 3). Answers instantly at login, which is the
   entire point of fault B.
2. **Blizzard's pooled item frame**, via `BB:ItemForCooldownID(cooldownID)`.
   Prefer `item:GetSpellCategoryIcon()` — it says exactly what we want and cannot
   drift if Blizzard ever reorder `GetSpellTexture` — and fall back to
   `item:GetSpellTexture()` if that method is absent. Name still from
   `item:GetNameText()`. Keep the existing `pcall` discipline: these are
   Blizzard internals and a renamed method must degrade, not throw.
3. **`C_Spell.GetLastCategoryCooldownSource`** → `GetItemNameByID` /
   `GetItemIconByID`, unchanged from today including the `issecretvalue`
   screening, which must stay **before** any nil test. Demoted to a last resort:
   it contradicts Decision 1 by showing a specific item's icon, but a real potion
   icon beats a question mark, and it only runs when path 2 could not answer.
4. **The generic label and question mark**, exactly as today. **Never cached and
   never persisted** — it is the "we do not know yet" state and must stay
   retryable.

## Decision 3 — cache the answer, and persist it account-wide

**Store:** `ThugUI_Config`, one new flat key `cvCategoryArt`. `ThugUI_Config` is
the correct store because CooldownViewer belongs to half A (`docs/DECISIONS.md`
§1). It is one top-level key whose value is a table; that is not a third store.
Add its default alongside the other CooldownViewer defaults in `ER.defaults`
(`modules/EssentialRings.lua`) — find the existing `cv*` keys and follow them.

**Shape:**

```lua
ThugUI_Config.cvCategoryArt = {
    [4] = { name = "Combat Potion", icon = "Interface/ICONS/INV_POTION_114" },
}
```

**Account-wide, not per-spec and not per-character**, and this is deliberate:
category art is global truth — category 4 looks the same on every character in
the game. A fresh alt then gets correct icons with no first fight at all.

**It must NOT be cleared by `Data.InvalidateCooldownInfoCache`.** That function
exists to drop spec-dependent Cooldown Manager data on a talent change
(`Data.lua:775-778`). Category art does not vary by spec, and clearing it would
reintroduce fault B on every talent change. Adding it there is the obvious wrong
move; do not make it.

## Decision 4 — split the cheap read from the expensive resolve

This is what makes fault A fixable without making fault C worse.

- **`Data.CategoryEntry(categoryID)`** becomes **cheap and non-discovering**. It
  reads the cache and returns the generic entry on a miss. It must never walk
  viewers or call `GetLastCategoryCooldownSource`. Safe to call from
  `UpdateState` and from the picker on every open.
- **`Data.ResolveCategoryArt()`** is new and carries the expensive pass: paths 2
  and 3 of Decision 2, for **categories not already resolved**, writing results
  into the cache. A fully-resolved cache makes it a no-op, so the cost is bounded
  to the window before the first successful resolve.

## Decision 5 — when to re-resolve

Call `Data.ResolveCategoryArt()` from the existing `PLAYER_REGEN_DISABLED` /
`PLAYER_REGEN_ENABLED` handler at `Core.lua:1434`. Both events are already
registered (`Core.lua:1383-1384`); **register nothing new**.

Combat entry is when Blizzard's viewer starts drawing and its frame pool
populates, which the player's report pins down precisely. Combat exit is the
cheap second chance. Do not poll, do not hook `SPELL_UPDATE_COOLDOWN` for this
(it fires constantly), and do not call it from `UpdateState`.

If the call resolves anything that was previously unresolved, the drawn cells
must pick it up — Decision 6 is what makes that happen without a rebuild.

## Decision 6 — repaint the drawn cell

In `UpdateState`'s `elseif icon.categoryID then` branch (`Core.lua:1057`), before
the existing show/sweep logic:

```lua
local entry = Data.CategoryEntry(icon.categoryID)
local texture = entry and entry.icon
if texture and texture ~= icon.baseTexture then
    icon.tex:SetTexture(texture)
    icon.baseTexture = texture
end
```

`icon.baseTexture` must be updated too — `Rebuild` sets it at `Core.lua:777` and
aura mode swaps art against it, so leaving it stale would be a second bug of the
same shape. Guarding on inequality keeps this a no-op on every tick after the
first, which is the normal case.

**Do not otherwise change the show/sweep behaviour in that branch.** The
fail-open rule documented at `Core.lua:1062-1065` stays exactly as it is: an
unresolved source shows the cell without a sweep. Faults A–C are about *art*, not
about visibility.

---

## Tests

`Tests/loadtest.lua`. **Add cases; do not repurpose or rewrite existing ones.**
If an existing case now asserts something this task deliberately changes, **leave
it failing, say so in your report, and draft its replacement there** — do not
edit it. That rule exists because it has been broken twice.

Read `Tests/README.md` first, in particular "Hazards in the harness itself". You
will likely need to extend the stub item frame with `GetSpellCategoryIcon`; if
the stub layer cannot express something, report that rather than weakening a
test around it.

Cover at least:

1. **Fault B** — with no active item frame and no cooldown source, a category
   entry is the generic one; with a **persisted** `cvCategoryArt` entry present,
   the same call returns the real name and icon. This is the login case.
2. **Fault A** — a category-backed icon drawn while unresolved, then resolved,
   then driven through `UpdateState`, ends up with the resolved texture on
   `icon.tex` **and** on `icon.baseTexture`, with **no rebuild in between**.
3. **Decision 2, stickiness** — once resolved, a subsequent pass where every
   resolution path fails must **not** revert the entry to the generic one.
4. **Decision 1** — `GetSpellCategoryIcon` is preferred over `GetSpellTexture`
   when both exist and return different values.
5. **Decision 3** — `Data.InvalidateCooldownInfoCache()` does **not** clear
   `cvCategoryArt`, while it does still clear the spec-scoped category info
   cache.
6. **Decision 4** — `Data.CategoryEntry` does not perform discovery: with the
   cache empty it returns the generic entry without walking viewers. Assert this
   behaviourally (e.g. a viewer stub that records whether it was enumerated),
   not by asserting a global was not written.

On (6), read §25's closing subsection in `DECISIONS.md` before writing it: task
18 shipped a test for this class of bug that was **incapable of failing**,
because it asserted that no global existed and the buggy code assigned `nil`.
**A test that cannot fail is worse than no test.** Verify each new case fails
against the unmodified source, and state that in your report per case.

---

## Out of scope — do not do these

- **Do not hardcode the four category IDs or their texture paths.** Discovery is
  the player's explicit instruction (§25). The persisted cache is *remembering
  what was discovered*, which is a different thing; it must only ever be written
  from a live resolve.
- **Do not touch `ui/pages/CursorRings.lua`.**
- **Do not change which viewers `BlizzBuffs` scans**, or its adoption logic.
- **Do not add a route to the real item's icon.** Decision 1 closed that.
- **Do not edit anything in `docs/`.** Draft proposed entries into your report.
- **Do not run state-changing git commands.** Leave the work uncommitted.

## Report

`tasks/reports/19-category-icons-resolve-and-repaint.md`. Include the harness
count before and after, each new case with its confirmed pre-fix failure, any
existing case you left failing and why, anything you found outside scope and did
not fix, and a draft `DECISIONS.md` §25 addendum.

**No report file means the task did not happen.**
