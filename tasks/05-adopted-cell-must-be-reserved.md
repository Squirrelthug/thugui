# 05 — An adopted cell must be reserved, whatever our own spell lookup thinks

**Read `tasks/00-AGENT-BRIEF.md` first. It is not optional.**

**Type:** behaviour fix, deliberately one line of logic. Plus tests.

**Runs alone**, after task 04. It shares `Tests/loadtest.lua` with 03 and 04.

---

## Why this task exists

The player placed **Opportunity** in `aura` mode. It vanishes from Blizzard's
default tracked-buff bar — so ThugUI adopted it — and then never appears in the
grid. Roll the Bones, placed the same way, works.

`modules/CooldownViewer/Core.lua`, in `CV:UpdateState`, around line 681:

```lua
local adopted = self.BlizzBuffs and self.BlizzBuffs:AdoptedItem(icon)

if not IsSpellAvailable(spellName) then
    show = false
elseif adopted then
    show = true
    ...
```

`IsSpellAvailable` is evaluated **before** the `adopted` branch, and it resolves
**by name**:

```lua
local function IsSpellAvailable(spellName)
    if not spellName then return false end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellName)
    return (ok and info and info.spellID) and true or false
end
```

Per `docs/DECISIONS.md` §5 a by-name lookup answers only for a spell the player
actually has as a castable — which is exactly why it is used, since it doubles
as the talent check.

**That is the whole difference between the two buffs.** Roll the Bones is placed
under `1214909`, the spell you cast. Opportunity is placed under `279876`, the
**passive** that grants buff `195627`. A passive does not answer a by-name
lookup, so `show = false`, and the branch that would have reserved the cell is
never reached.

The consequence is worse than a hidden icon. With the player's `collapse =
"columns"`, an icon that is not `wanted` is left out of the collapse pass, so it
keeps its uncollapsed coordinate while every live cell slides away from it — and
Blizzard's adopted item is anchored to that stale cell. Adopted, drawn by
Blizzard, parked where the grid no longer is.

It also breaks an invariant `docs/DECISIONS.md` §13 states outright:

> An adopted cell is **always reserved**, buff up or not, because we cannot ask
> whether it is up.

The code does not enforce that. This task makes it true.

### The evidence, so you do not re-derive it

From `ThugUI_DebugLog`, session starting 2026-08-10 02:30:21 (53 entries, ring
cap 300, so nothing was evicted):

- Every `Opportunity` line is a `SHOWN`→`hidden` pair inside the same second —
  the Rebuild-seed-then-corrected pattern documented in `docs/KNOWN-ISSUES.md`.
  It never settles shown, in or out of combat.
- `Roll the Bones` logs three lines at 02:30:21 and then nothing for the rest of
  the session, across five combats. Only adoption holds `wanted = true` through
  combat; the plain aura path provably returns nothing there.
- The player observed Opportunity leaving Blizzard's bar in aura mode and only
  in aura mode, which is `BB:Apply` anchoring it. So `adopted` is truthy.

Adopted, and never shown. The only branch that can skip `elseif adopted` while
`adopted` is truthy is the gate above it.

## The decision — already made

**Check `adopted` first. Do not touch `IsSpellAvailable`.**

The reasoning, which is the point of the whole feature: when Blizzard's own
untainted code is already drawing that item, ThugUI has no standing to
second-guess whether the spell exists. Their code decides shown, artwork and
timer; ours decides where it sits (`docs/DECISIONS.md` §13). Our availability
check is the weaker authority and it is overriding the stronger one.

**Explicitly rejected, do not implement:** widening `IsSpellAvailable` to fall
back on the Cooldown Manager's `isKnown` flag. It would fix this case too, and
it may well be right later — but it changes availability semantics for **every**
placed icon in every mode, including the eight `cooldown`-mode icons that work
today. Not worth the blast radius for a bug with a one-branch cause.

## Files you may modify

- `modules/CooldownViewer/Core.lua`
- `Tests/loadtest.lua`
- `tasks/reports/05-report.md`

## What to change

Reorder so an adopted icon is handled before the availability gate. Keep the
`adopted` branch's body exactly as it is — `show = true`, `icon.tex:SetAlpha(0)`,
`icon.cooldown:Clear()`, `icon.count:Hide()`. Our art stays suppressed because
Blizzard's item is drawing over the cell; only the reservation changes.

`IsSpellAvailable` must still gate every **non**-adopted path exactly as now.
This is a reordering, not a removal.

Update the comment above the `adopted` local. It already explains why the cell
stays in the layout; it should now also say why adoption outranks our own
availability check, and name the case — a placement whose spell ID is a passive
that grants the buff, which no by-name lookup will resolve. That sentence is the
one that stops someone reordering it back.

## Tests

1. **An adopted icon is shown even when its spell name does not resolve.** Model
   the Opportunity shape: a placement whose spell ID has no by-name resolution,
   in `aura` mode, with a matching Blizzard item frame. Assert `icon.wanted` is
   true and the icon is shown. **Must fail before your change** — confirm it
   does, and say how.
2. **The adopted cell keeps its slot under `collapse = "columns"`** rather than
   being skipped by the pass and stranded at its uncollapsed coordinate. This is
   the invariant from §13 and it is the half of the bug the player actually saw.
3. **A non-adopted icon whose spell does not resolve is still hidden.** The gate
   must not have been weakened for anything else.
4. Existing aura-mode and BlizzBuffs cases unchanged.

## Verification gate

```sh
luac -p modules/CooldownViewer/Core.lua Tests/loadtest.lua
lua Tests/loadtest.lua .
```

## Report

`tasks/reports/05-report.md`, per brief §10.

**Not verified** must say: this is proven only in the harness. Whether
Opportunity draws in the right cell, shows its radial timer, and shows stack
counts of 3 and 6 can only be confirmed by the player in a live session. Do not
imply otherwise anywhere in the report.

In **Proposed docs changes**, draft: a correction to `docs/DECISIONS.md` §13
noting the invariant was stated but not enforced, and why a passive-backed
placement exposed it; and a `docs/HANDOFF.md` §2 row for this fix marked
**unverified in game**.
