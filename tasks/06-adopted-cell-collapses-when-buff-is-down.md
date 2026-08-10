# 06 — An adopted cell must collapse when the buff is down

Read `00-AGENT-BRIEF.md` first. It is not optional and it is short.

**Status of the thing you are changing: it works in game, today, and the player
is using it.** The Opportunity buff draws in its cell during combat and counts
down correctly. Your change must not cost that. If you find yourself about to
make the adopted buff stop drawing, stop and report instead.

---

## 1. The bug, stated exactly

The player has `collapse = "columns"` and put Opportunity in a column with
Pistol Shot. **The column never closes.** The gap where Opportunity sits is
present whether or not the buff is up, including out of combat when it is
definitely down.

The cause is in `modules/CooldownViewer/Core.lua`, in `CV:UpdateState`, at the
`if adopted then` branch (currently line 687):

```lua
local adopted = self.BlizzBuffs and self.BlizzBuffs:AdoptedItem(icon)

if adopted then
    show = true          -- <- this
```

`show = true` unconditionally. The cell is therefore always "wanted", always
takes a slot, and the collapse pass never reclaims it. This was a deliberate
trade at the time — `docs/HANDOFF.md` §3b calls it "the remaining cost" — made
on the belief that we can never know whether the buff is up. That belief is
right *in combat* and wrong *out of combat*.

## 2. What to build

Replace the unconditional `show = true` with a three-source decision, in this
order of authority. **The order is the design. Do not reorder it.**

1. **Blizzard's item frame.** It hides itself when the buff drops, so its shown
   state *is* the answer — when we are allowed to read it.
2. **Our own aura lookup** (`ResolveAura`, already in `Core.lua`). Truthful out
   of combat, blind in combat, so it only gets a say when it can see.
3. **Reserve the cell.** Unsure must mean "keep the slot".

Step 3 is a safety property, not a fallback of convenience. If we collapse a
cell whose buff is actually up, Blizzard's item is still anchored to our
now-hidden icon and draws at a stale coordinate — on top of a neighbouring
icon. Reserving when unsure is the difference between "a gap I did not want"
and "my UI is broken".

### 2a. `BB:ItemIsShown(item)` — new, in `BlizzBuffs.lua`

Returns `true`, `false`, or **`nil` meaning "we cannot tell"**. Three states,
not two; a boolean return would collapse "hidden" and "unknown" into the same
answer and those need opposite behaviour.

```lua
function BB:ItemIsShown(item)
    if not item or not item.IsShown then return nil end

    local ok, shown = pcall(item.IsShown, item)
    if not ok then return nil end

    -- No screening function means we cannot prove the value is safe to touch,
    -- so we decline to trust it rather than compare and hope.
    if not issecretvalue then return nil end
    if issecretvalue(shown) then return nil end

    return shown and true or false
end
```

Reading a Blizzard frame is free and taint-safe — see the brief, §5. You are
reading only. Do not write to the item, do not hook it.

**Why the secret screen is there, so you do not remove it as defensive noise:**
Blizzard's `CooldownViewerItemMixin:UpdateShownState` calls
`self:SetShown(self:ShouldBeShown())`, and for a buff item that boolean descends
from `CooldownViewerBuffItemMixin:IsExpired`, which compares
`auraData.expirationTime <= GetTime()`. In combat `expirationTime` is a secret
value, and this project has already measured that secrecy propagates through
operations (`ThugUI_DebugLog.secrets` recorded `EvaluateColorValue(secret bool)
-> SECRET number`). So `IsShown()` may well hand us a secret boolean in combat.
Source: `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` on branch
`live`, `UpdateShownState` and `CooldownViewerBuffItemMixin:IsExpired`.

Whether it *actually* comes back secret is unmeasured. §2c measures it. Write
the code so that either answer is handled without a further change.

### 2b. The decision, in `Core.lua`

Add a file-local helper next to `ResolveAura` (it needs `ResolveAura` and the
existing `InCombat()` helper, so it must come after both):

```lua
local function AdoptedCellWanted(icon, item)
    local shown = CV.BlizzBuffs and CV.BlizzBuffs:ItemIsShown(item)
    if shown ~= nil then return shown end

    -- In combat the by-ID aura lookups return nothing at all
    -- (RequiresNonSecretAura), so "no aura" and "cannot see the aura" are the
    -- same answer here. Keep the slot.
    if InCombat() then return true end

    return ResolveAura(icon) ~= nil
end
```

and use it:

```lua
if adopted then
    show = AdoptedCellWanted(icon, adopted)
    icon.tex:SetAlpha(0)
    icon.cooldown:Clear()
    icon.count:Hide()
elseif not IsSpellAvailable(spellName) then
```

**Leave the `adopted` branch first, ahead of `IsSpellAvailable`.** That ordering
is task 05's fix for the Opportunity bug and it is the reason the buff draws at
all — a passive's name does not resolve via `GetSpellInfo`. `docs/DECISIONS.md`
§13. Keep the existing comment block above `local adopted`; extend it, do not
replace it.

Check `CV.BlizzBuffs` against how `UpdateState` already reaches it
(`self.BlizzBuffs`) and use whichever is correct in a file-local function. If
only the `self` form is available, pass the module in or move the helper — say
which you did and why.

### 2c. The measurement

One line per session per combat state, in `BB:Apply`, where both the item and
the combat state are already in hand. This is the evidence that tells us whether
exact in-combat collapse is reachable at all; today we are guessing.

Log, via `ThugUI.Diagnostics:LogOnce`, category `"CVBUFF"`:

- key: `("blizzbuffs-shown-readable-%s"):format(tostring(inCombat))`
- message: which spell, whether `ItemIsShown` returned a usable value, the value
  if so, and the combat state.

**Combat state must be part of the key, not only the message.** An
out-of-combat line logged first would otherwise suppress the in-combat one,
which is the single line the measurement exists to produce. That exact mistake
has already been made and fixed once in this codebase — `Core.lua`, the `Note`
helper inside `GetPlayerCastAura`, and the comment above it explains it.

Log for one adopted item per pass, not all ten. Reuse the `spellStr` formatting
already present in `Apply`.

## 3. Tests

`Tests/loadtest.lua`. The stub item frames need a shown state you can drive.

**Make stub items default to shown.** Task 05's three cases assume an adopted
cell is wanted, and with a default of shown they keep passing **unchanged**.

> **Do not delete or rewrite an existing test case.** Task 05's report claimed
> "added three cases" while silently overwriting a fourth, and it was caught in
> review. If you believe an existing case must change, leave it alone, and put
> the case, the reason, and the exact before/after in your report under a
> heading **"Existing tests I believe need to change"**. The coordinator
> decides.

Cases to add:

| Case | Setup | Expect |
|---|---|---|
| item shown wins over everything | adopted, item shown, no aura, in combat | wanted |
| item hidden wins over everything | adopted, item hidden, in combat | **not** wanted |
| unreadable + in combat reserves | adopted, `IsShown` returns a secret, in combat | wanted |
| unreadable + out of combat, buff up | adopted, `IsShown` secret, aura present | wanted |
| unreadable + out of combat, buff down | adopted, `IsShown` secret, no aura | **not** wanted |
| the gap actually closes | the case above, `collapse = "columns"` | the column packs; the freed slot is reclaimed |
| no `issecretvalue` degrades safely | `issecretvalue` absent, out of combat, no aura | **not** wanted, and nothing throws |

The sixth is the player's actual complaint. Make it assert the neighbour's
resulting position, not merely that `wanted` is false — `wanted` was already
testable and the layout is what the player sees.

Confirm the two collapse-related cases fail against the current `show = true`
and say so in your report, with the failure text.

## 4. Files you may modify

- `modules/CooldownViewer/Core.lua`
- `modules/CooldownViewer/BlizzBuffs.lua`
- `Tests/loadtest.lua`
- `tasks/reports/06-report.md` (your report)

Nothing else. No `docs/`. No git commands that change state.

## 5. Verification gate

```sh
luac -p modules/CooldownViewer/Core.lua modules/CooldownViewer/BlizzBuffs.lua Tests/loadtest.lua
lua Tests/loadtest.lua .
```

Baseline is **0 failures** from a clean tree at `53d2755`. Any failure is one
you caused. Paste the tail, including every case under `-- blizzard buff items --`
so the review can see task 05's cases still listed and still passing.

## 6. Known, accepted, do not fix

When an adopted cell stops being wanted, `CV:ApplyLayout`'s `Commit()` still
positions the hidden icon, and Blizzard's item stays anchored to it. If their
item is re-shown before our next `UpdateState`, it draws at the stale
coordinate for one frame. `UNIT_AURA` drives both paths, so it self-corrects
immediately. Leave it. Mention it in your report if you see a cheap fix, but do
not build one.
