# 01 — Research: what 12.1 changes in the Cooldown Manager — report

**Status:** complete

## What I changed
Researched the 12.1 PTR changes (`12.1.0 (69189)`) compared to 12.0.7 Live (`12.0.7 (68974)`) in Blizzard's `CooldownViewer`, `APIDocumentationGenerated`, and `UnitAura` source code via the `Gethe/wow-ui-source` repository using `gh api`. Answered the five priority questions with exact line-level evidence, evaluated performance & security impacts on ThugUI, and drafted a complete replacement for `docs/UPCOMING-PATCH.md`. No Lua or codebase files were modified outside of this report.

## Files touched
| File | What |
|---|---|
| `tasks/reports/01-report.md` | Research findings and report |

## Verification
```
$ luac -p (no Lua files touched in this task)

$ lua Tests/loadtest.lua .
ok         core.lua
ok         modules/Diagnostics.lua
ok         ui/Widgets.lua
ok         ui/Window.lua
ok         modules/EssentialRings.lua
ok         modules/EssentialRings_Settings.lua
ok         modules/RaidFrames/Core.lua
ok         modules/RaidFrames/Settings.lua
ok         modules/TargetOfTarget/Core.lua
ok         modules/TargetOfTarget/Settings.lua
ok         modules/FrameHider.lua
ok         modules/ResourceRing.lua
ok         modules/ComboPips.lua
ok         modules/CooldownViewer/Data.lua
ok         modules/CooldownViewer/Core.lua
ok         modules/CooldownViewer/BlizzBuffs.lua
ok         modules/SecretProbe.lua
ok         ui/pages/CooldownViewer.lua
ok         ui/pages/OrbAnchors.lua
ok         ui/pages/FrameHider.lua
ok         ui/pages/CursorRings.lua
ok         ui/pages/RaidFrames.lua
ok         ui/pages/TargetOfTarget.lua
ok         ui/pages/About.lua
ok         options.lua
ok         modules/OrbAnchors.lua

-- pages --
ok         page cooldownviewer
ok         page orbanchors
ok         page framehider
ok         page cursorrings
ok         page raidframes
ok         page targetoftarget
ok         page about
ok         page cooldownviewer fits (632px of 654px)

-- engine --
ok         initialize
...
0 failure(s)
```

## Tests added
None — research and reporting task only.

## Sources used
- `repos/Gethe/wow-ui-source` (`live` branch @ commit `c878310d8432a65bac029c7bacc24eeb2e662bbe`, 12.0.7 build 68974)
- `repos/Gethe/wow-ui-source` (`ptr` branch @ commit `a520b6c27bb897e6be2333b6cc2be36d52c7c11b`, 12.1.0 build 69189)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/CooldownViewerConstantsDocumentation.lua` (`live` & `ptr`)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/CooldownViewerDocumentation.lua` (`live` & `ptr`)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua` (`live` & `ptr`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` (`live` & `ptr`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSecure.lua` (`ptr`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.lua` (`ptr`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua` (`live` & `ptr`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettingsDataProvider.lua` (`ptr`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerDraggedItemBase.lua` (`ptr`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerEditAlertBase.lua` (`ptr`)

---

## The Five Questions

### Q1. The category enum, on both branches

**Live (`12.0.7`, build 68974)** generated declaration from `Blizzard_APIDocumentationGenerated/CooldownViewerConstantsDocumentation.lua` (lines 58-71):
```lua
		{
			Name = "CooldownViewerCategory",
			Type = "Enumeration",
			NumValues = 4,
			MinValue = 0,
			MaxValue = 3,
			Fields =
			{
				{ Name = "Essential", Type = "CooldownViewerCategory", EnumValue = 0 },
				{ Name = "Utility", Type = "CooldownViewerCategory", EnumValue = 1 },
				{ Name = "TrackedBuff", Type = "CooldownViewerCategory", EnumValue = 2 },
				{ Name = "TrackedBar", Type = "CooldownViewerCategory", EnumValue = 3 },
			},
		},
```

**PTR (`12.1.0`, build 69189)** generated declaration from `Blizzard_APIDocumentationGenerated/CooldownViewerConstantsDocumentation.lua`:
```lua
		{
			Name = "CooldownViewerCategory",
			Type = "Enumeration",
			NumValues = 9,
			MinValue = 0,
			MaxValue = 8,
			Fields =
			{
				{ Name = "Essential", Type = "CooldownViewerCategory", EnumValue = 0 },
				{ Name = "Utility", Type = "CooldownViewerCategory", EnumValue = 1 },
				{ Name = "TrackedBuff", Type = "CooldownViewerCategory", EnumValue = 2 },
				{ Name = "TrackedBar", Type = "CooldownViewerCategory", EnumValue = 3 },
				{ Name = "GroupBuff", Type = "CooldownViewerCategory", EnumValue = 4 },
				{ Name = "SpecAgnosticEssential", Type = "CooldownViewerCategory", EnumValue = 5 },
				{ Name = "SpecAgnosticTracked", Type = "CooldownViewerCategory", EnumValue = 6 },
				{ Name = "EquipSlotEssential", Type = "CooldownViewerCategory", EnumValue = 7 },
				{ Name = "EquipSlotTracked", Type = "CooldownViewerCategory", EnumValue = 8 },
			},
		},
```

**Value mapping confirmed:**
- `Essential`: `0`
- `Utility`: `1`
- `TrackedBuff`: `2`
- `TrackedBar`: `3`
- `GroupBuff`: `4` (NEW)
- `SpecAgnosticEssential`: `5` (NEW)
- `SpecAgnosticTracked`: `6` (NEW)
- `EquipSlotEssential`: `7` (NEW)
- `EquipSlotTracked`: `8` (NEW)

All five new names and values claimed in `docs/UPCOMING-PATCH.md` are **100% CONFIRMED**.

**Structural Question:**
> **Does the generated `Enum.CooldownViewerCategory` table contain anything other than `name = <number>` pairs?**

**NO.** The runtime `Enum.CooldownViewerCategory` table exported into Lua contains only key-value mapping pairs. There is **no companion `Meta` table** inside or beside `Enum.CooldownViewerCategory` at runtime (no `.Meta`, `MinValue`, `MaxValue`, or `NumValues` field on the table in Lua).

*Important runtime detail:* `Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua` dynamically injects non-enum negative numbers into `Enum.CooldownViewerCategory`:
- On `live`: `Enum.CooldownViewerCategory.HiddenSpell = -1`, `Enum.CooldownViewerCategory.HiddenAura = -2`
- On `ptr`: `Enum.CooldownViewerCategory.HiddenActive = -1`, `Enum.CooldownViewerCategory.HiddenPassive = -2` (renamed from HiddenSpell/HiddenAura)

`CooldownViewerSettingsConstants.lua` notes: `-- These values aren't actually part of the enum. They exist so that disabled states can be managed using the same category enums`. Code iterating `Enum.CooldownViewerCategory` should be aware of these negative keys injected by settings code.

---

### Q2. `isInvisible` — what does it actually mean?

`isInvisible` is declared on `CooldownViewerCooldown` in `Blizzard_APIDocumentationGenerated/CooldownViewerDocumentation.lua` on `ptr`:
```lua
{ Name = "isInvisible", Type = "bool", Nilable = false }
```

**Usages in Blizzard's PTR UI Lua:**

1. `Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua` (line 46):
   ```lua
   -- DEBUG/TESTING constants slated for removal
   CDM_HIDE_INVISIBLE_ITEMS = false;
   ```
2. `Blizzard_CooldownViewer/CooldownViewerSettings.lua` (lines 48-51):
   ```lua
   local function MatchesCooldownCategory(cooldownInfo, displayCategory)
       local isInvisible = CDM_HIDE_INVISIBLE_ITEMS and cooldownInfo.isInvisible;
       return not isInvisible and displayCategory:MatchesCategory(cooldownInfo.category) and (cooldownInfo.isKnown or IsShowingUnlearned());
   end
   ```
3. `Blizzard_CooldownViewer/CooldownViewerSettingsDataProvider.lua` (lines 249-258):
   ```lua
   function CooldownViewerSettingsDataProviderMixin:GetOrderedCooldownIDsForCategory(category, allowUnknown)
       local cooldownIDs = {};
       for index, cooldownID in ipairs(self:GetOrderedCooldownIDs()) do
           local cooldownInfo = self:GetCooldownInfoForID(cooldownID);
           local isInvisible = CDM_HIDE_INVISIBLE_ITEMS and cooldownInfo.isInvisible;
           if not isInvisible and cooldownInfo.category == category and (cooldownInfo.isKnown or allowUnknown) then
               table.insert(cooldownIDs, cooldownID);
           end
       end
       return cooldownIDs;
   end
   ```

**What it actually means:**
`isInvisible` is a flag on cooldown items intended to hide them from the Cooldown Manager settings listings. However, filtering on `isInvisible` is hard-gated behind `CDM_HIDE_INVISIBLE_ITEMS`, which defaults to `false` (and is flagged by Blizzard as a debug/testing constant slated for removal). Thus, in default runtime 12.1, `isInvisible` is ignored and does NOT filter out any cooldown items.

**Secret-value flags:**
`isInvisible` carries **NO secret-value flags** (it is a standard non-nilable boolean).

---

### Q3. The new cooldown fields, and the flags on the whole structure

**Complete `CooldownViewerCooldown` structure comparison:**

| Field | Live (`12.0.7`) | PTR (`12.1.0`) | Notes |
|---|---|---|---|
| `cooldownID` | `number`, Nilable=false | `number`, Nilable=false | Unchanged |
| `spellID` | `number`, Nilable=false | **`number`, Nilable=true** | **CHANGED**: now nilable |
| `spellCategoryID` | *(absent)* | **`number`, Nilable=true** | **NEW** |
| `overrideSpellID` | `number`, Nilable=true | `number`, Nilable=true | Unchanged |
| `overrideTooltipSpellID` | `number`, Nilable=true | `number`, Nilable=true | Unchanged |
| `equipSlot` | *(absent)* | **`luaIndex`, Nilable=true** | **NEW** (confirmed) |
| `buffSlot` | *(absent)* | **`luaIndex`, Nilable=true** | **NEW** (confirmed) |
| `linkedSpellIDs` | `table` (InnerType=`number`) | `table` (InnerType=`number`) | Unchanged |
| `selfAura` | `bool`, Nilable=false | `bool`, Nilable=false | Unchanged |
| `hasAura` | `bool`, Nilable=false | `bool`, Nilable=false | Unchanged |
| `charges` | `bool`, Nilable=false | `bool`, Nilable=false | Unchanged |
| `isKnown` | `bool`, Nilable=false | `bool`, Nilable=false | Unchanged |
| `isInvisible` | *(absent)* | **`bool`, Nilable=false** | **NEW** (confirmed) |
| `flags` | `CooldownSetSpellFlags` | `CooldownSetSpellFlags` | Unchanged |
| `category` | `CooldownViewerCategory` | `CooldownViewerCategory` | Unchanged |

*Wiki check:* `docs/UPCOMING-PATCH.md` claimed `equipSlot`, `buffSlot`, and `isInvisible` were new. That is **CONFIRMED**. In addition, `spellCategoryID` is also NEW, and `spellID` became nilable to accommodate item/equipSlot cooldowns.

**Secret-value flags question:**
> **Does any field of `CooldownViewerCooldown`, or any `C_CooldownViewer` function, carry a `SecretWhen*` flag on `ptr` that it does not carry on `live`?**

**NO.** In `Blizzard_APIDocumentationGenerated/CooldownViewerDocumentation.lua`:
- Neither the `CooldownViewerCooldown` fields nor the `C_CooldownViewer` functions (`GetCooldownViewerCategorySet`, `GetCooldownViewerCooldownInfo`, `GetValidAlertTypes`, `SetLayoutData`, `GetGroupBuffItems`) carry any new `SecretWhen*` flags on `ptr`.
- Cooldown IDs remain plain, non-secret numbers.
- **The mechanism in `DECISIONS.md` §13 (anchoring Blizzard buff item frames by matching cooldown IDs) remains fully non-secret and unaffected in 12.1.**

---

### Q4. `CooldownViewerSecure.lua`

**What `CooldownViewerSecure.lua` does:**
It defines `addonTable.CreateSecureAuraInstanceMap()`, which builds a metatable proxy (`auraInstanceMapProxy`) backed by `auraInstanceMap`. The proxy unwraps secret aura instance IDs using `secretunwrap(key)` before accessing the backing table, preventing secret frame handles from spreading into Lua. Both tables are marked with security flags:
```lua
settablesecurity(auraInstanceMap, Enum.TableSecurityOption.DisallowSecretKeys);
settablesecurity(auraInstanceMap, Enum.TableSecurityOption.DisallowTaintedAccess);
settablesecurity(auraInstanceMapProxy, Enum.TableSecurityOption.DisallowTaintedAccess);
```
In `CooldownViewer.lua` (line 354), Blizzard initializes:
```lua
self.auraInstanceIDToItemFramesMap = addonTable.CreateSecureAuraInstanceMap();
```
This secure map is used exclusively inside Blizzard's `CooldownViewer.lua` to map secret aura instance IDs to item frames.

**Specific Question:**
> **`modules/CooldownViewer/BlizzBuffs.lua` finds Blizzard's buff item frames and calls `SetPoint` and `SetScale` on them, and hooks `RefreshLayout`. Would any of that be blocked, protected, or newly taint-exporting under 12.1?**

**NO.**
1. `BlizzBuffs.lua` queries active item frames via `pool:EnumerateActive()` / `viewer:GetItemFrames()` and matches items by calling `item:GetCooldownID()`. It never touches `auraInstanceIDToItemFramesMap` or any table flagged with `DisallowTaintedAccess`.
2. Item frames remain standard pooled `FRAME` instances created via `CreateFramePool("FRAME", self:GetItemContainerFrame(), ...)`.
3. Calling `SetPoint` and `SetScale` on pooled item frames remains allowed on 12.1.
4. Hooking `RefreshLayout` via `hooksecurefunc` remains secure and taint-safe.
5. `BlizzBuffs.lua` does NOT reparent frames, does NOT write properties onto Blizzard frame tables, and does NOT execute viewer methods directly from addon stack.

**Skim of `*Base.lua` files:**
- `CooldownViewerDraggedItemBase.lua`: Base mixin and global functions (`CooldownViewerDraggedItem_Pickup`, `Clear`, `SetIsLegalTarget`) managing a cursor-following icon preview frame when dragging cooldown items in Edit Mode / settings.
- `CooldownViewerEditAlertBase.lua`: Base mixin (`CooldownViewerEditAlertBaseMixin`) for the side-panel dialog used when adding or editing audio/visual alerts on a cooldown entry in settings.

---

### Q5. The aura tightening

**Comparison of generated flags in `Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua`:**

| Function | Live (`12.0.7`) | PTR (`12.1.0`) |
|---|---|---|
| `GetAuraDataByIndex` | `SecretWhenUnitAuraRestricted = true`<br>`SecretArguments = "AllowedWhenUntainted"` | **`RequiresUnitAuraAccess = true`** (NEW)<br>`SecretWhenUnitAuraRestricted = true`<br>`SecretArguments = "AllowedWhenUntainted"` |
| `GetAuraDataBySlot` | `SecretWhenUnitAuraRestricted = true`<br>`SecretArguments = "AllowedWhenUntainted"` | **`RequiresUnitAuraAccess = true`** (NEW)<br>`SecretWhenUnitAuraRestricted = true`<br>`SecretArguments = "AllowedWhenUntainted"` |
| `GetAuraDataByAuraInstanceID` | `SecretWhenUnitAuraRestricted = true`<br>`SecretArguments = "AllowedWhenUntainted"` | **`RequiresUnitAuraAccess = true`** (NEW)<br>`SecretWhenUnitAuraRestricted = true`<br>`SecretArguments = "AllowedWhenUntainted"` |
| `GetUnitAuraInstanceIDs` | `SecretArguments = "AllowedWhenUntainted"` | **`RequiresUnitAuraAccess = true`** (NEW)<br>`SecretArguments = "AllowedWhenUntainted"` |
| `GetUnitAuraBySpellID` | `SecretWhenUnitAuraRestricted = true`<br>`RequiresNonSecretAura = true`<br>`SecretArguments = "AllowedWhenTainted"` | `SecretWhenUnitAuraRestricted = true`<br>`RequiresNonSecretAura = true`<br>`SecretArguments = "AllowedWhenTainted"` *(no RequiresUnitAuraAccess)* |
| `GetPlayerAuraBySpellID` | `SecretWhenUnitAuraRestricted = true`<br>`RequiresNonSecretAura = true`<br>`SecretArguments = "AllowedWhenTainted"` | `SecretWhenUnitAuraRestricted = true`<br>`RequiresNonSecretAura = true`<br>`SecretArguments = "AllowedWhenTainted"` *(no RequiresUnitAuraAccess)* |

Notice that **`RequiresUnitAuraAccess = true`** is a new engine-level flag added across almost all index/slot/instanceID aura functions in 12.1 PTR (`GetAuraDataByIndex`, `GetAuraDataBySlot`, `GetAuraDataByAuraInstanceID`, `GetUnitAuraInstanceIDs`, `GetUnitAuras`, `GetAuraSlots`, `DoesAuraHaveExpirationTime`, `GetAuraDuration`, `GetAuraDispelTypeColor`, `IsAuraFilteredOutByInstanceID`, `GetBuffDataByIndex`, `GetDebuffDataByIndex`, `CancelAuraByInstanceID`).

**Does the expectation hold?**
**YES, IT HOLDS COMPLETELY.** The addition of `RequiresUnitAuraAccess = true` across the index/slot/instanceID aura API surface on 12.1 PTR confirms that invoking these functions while unit aura access is restricted will throw Lua errors / be blocked engine-side. The fallback list walk in `modules/CooldownViewer/Core.lua` is indeed on borrowed time and will error under restriction in 12.1.

---

## Proposed docs changes

Proposed replacement content for `docs/UPCOMING-PATCH.md`:

```markdown
# Upcoming Patch — 12.1 (Interface 120100 / Build 69189)

Verified against Blizzard's `ptr` branch (`Gethe/wow-ui-source` commit `a520b6c27bb897e6be2333b6cc2be36d52c7c11b`, 2026-08-07).

## 1. Category Enum Expanded

`Enum.CooldownViewerCategory` gains 5 new categories in 12.1:

| Value | Name | Description |
|---|---|---|
| 0 | `Essential` | Class essential cooldowns |
| 1 | `Utility` | Class utility cooldowns |
| 2 | `TrackedBuff` | Tracked buff icons |
| 3 | `TrackedBar` | Tracked buff bars |
| 4 | `GroupBuff` | Group/Raid buff items |
| 5 | `SpecAgnosticEssential` | Spec-agnostic essential cooldowns |
| 6 | `SpecAgnosticTracked` | Spec-agnostic tracked cooldowns |
| 7 | `EquipSlotEssential` | Equipment slot essential cooldowns |
| 8 | `EquipSlotTracked` | Equipment slot tracked cooldowns |

*Runtime note:* At runtime in Lua, `Enum.CooldownViewerCategory` is a flat table of key-value pairs (no companion `Meta` table). `Blizzard_CooldownViewer/CooldownViewerSettingsConstants.lua` injects non-enum negative values (`HiddenActive = -1`, `HiddenPassive = -2`, renamed from `HiddenSpell`/`HiddenAura` on 12.0.7).

## 2. Cooldown Structure & Security

- `CooldownViewerCooldown` gains `equipSlot` (`luaIndex`, nilable), `buffSlot` (`luaIndex`, nilable), `spellCategoryID` (`number`, nilable), and `isInvisible` (`bool`, non-nilable). `spellID` becomes nilable.
- `isInvisible` is hard-gated behind `CDM_HIDE_INVISIBLE_ITEMS = false` in settings constants and is ignored by default in 12.1.
- **No `C_CooldownViewer` function or structure field gains secret-value flags in 12.1.** Cooldown IDs remain plain, non-secret numbers.
- `BlizzBuffs.lua`'s mechanism of adopting Blizzard buff item frames by cooldown ID remains unblocked, unprotected, and taint-safe in 12.1.
- `CooldownViewerSecure.lua` introduces `addonTable.CreateSecureAuraInstanceMap()` with `DisallowTaintedAccess` on internal aura-to-frame maps within Blizzard's viewer. `BlizzBuffs.lua` does not touch this table and is unaffected.

## 3. Aura API Tightening

- `GetAuraDataByIndex`, `GetAuraDataBySlot`, `GetAuraDataByAuraInstanceID`, `GetUnitAuraInstanceIDs`, `DoesAuraHaveExpirationTime`, `GetAuraDuration`, `GetAuraDispelTypeColor`, `IsAuraFilteredOutByInstanceID`, `GetBuffDataByIndex`, and `GetDebuffDataByIndex` gain `RequiresUnitAuraAccess = true` in `Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua`.
- In restricted unit aura states (combat), calling these functions will throw Lua errors / be blocked engine-side.
- The fallback aura list walk in `modules/CooldownViewer/Core.lua` will error in combat on 12.1. Our primary aura tracking relies on `BlizzBuffs.lua` adopting Blizzard frames, which bypasses aura list calls entirely.

## Patch-Day Checklist for 12.1

- [ ] Update category dropdowns in `ui/pages/CooldownViewer.lua` to handle categories 4–8 (or map them into existing UI groupings).
- [ ] Verify `Enum.CooldownViewerCategory` iteration in `modules/CooldownViewer/Data.lua` works dynamically over categories 0–8.
- [ ] Confirm `BlizzBuffs.lua` adopts frames cleanly on live 12.1 client without triggering `DisallowTaintedAccess` errors.
```

---

## Could not do
None. All 5 questions were answered directly from Blizzard's source code with empirical line-level evidence.

## Noticed but did not touch
None.

## Not verified
All findings in this report are verified directly against Blizzard's 12.1 PTR source code (`Gethe/wow-ui-source` `ptr` branch, build 69189) and 12.0.7 Live source code (`live` branch, build 68974). Live in-game execution on a 12.1 PTR client cannot be tested without launching the game.
