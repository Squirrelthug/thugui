# 11 — A spell placed as a cooldown is not "already placed" as a buff

Read `00-AGENT-BRIEF.md` first.

Baseline: whatever `main` is when you start (task 10 lands immediately before
you and edits `Data.lua`), `lua Tests/loadtest.lua .` → **0 failures**.

Files you may modify:
- `modules/CooldownViewer/Data.lua`
- `ui/pages/CooldownViewer.lua`
- `Tests/loadtest.lua`
- `tasks/reports/11-report.md`

---

## 1. The bug

`Page:RefreshPicker` greys a row when the spell is already on the grid:

```lua
if Data.IsSpellPlaced(profile, entry.spellID) then
    row.label:SetText("|cff808080" .. entry.name .. "|r")
```

and `Data.IsSpellPlaced` (`Data.lua:346`) matches on spell ID alone.

Some spells appear in **two categories at once with the same spell ID** — an
Essential cooldown *and* a tracked buff. Roll the Bones `1214909` is one, and the
player has it placed twice on purpose: `4:3 mode=aura` and `5:3 mode=cooldown`.
Placing either greys the other, so the picker says "already placed" about a row
that is a genuinely different thing to place.

**Grey is cosmetic here — the row is still clickable.** So this is misleading,
not blocking. Do not "fix" it by disabling anything.

## 2. What to do

Grey by **spell ID and mode family**, not spell ID alone.

There are four modes (`Data.MODES`): `cooldown`, `proc`, `always`, `aura`. The
distinction that matters to the player is `aura` versus everything else — an
aura-mode placement draws a buff, the other three draw a spell. So:

- A row shown under the **`buffs` source** greys only when that spell is placed
  in `aura` mode.
- A row shown under **any other source** greys only when that spell is placed in
  a non-`aura` mode.
- The **`all` source** is the awkward one, because a row there has no single
  category. Grey it when the spell is placed in *any* mode — the current
  behaviour. A row under "Everything" makes no claim about which kind it is, so
  the honest answer is "this spell is on your grid somewhere".

Give `Data.IsSpellPlaced` an optional third argument rather than writing a
second function — something like `Data.IsSpellPlaced(profile, spellID, mode)`
where `mode` is `"aura"`, `"other"`, or `nil` for "any". `nil` must keep the
present behaviour exactly, because other callers exist: **find them all before
you change the signature** and leave them working unchanged.

`RefreshPicker` decides which to ask for, from `self.pickerSource`. Keep that
decision in the page, not in `Data` — `Data` should not know what a picker
source is.

## 3. Tests

- A spell placed in `cooldown` mode does **not** grey under the `buffs` source,
  and does grey under `essential`.
- A spell placed in `aura` mode does grey under `buffs`, and does not under
  `essential`.
- Under `all`, either placement greys it.
- `Data.IsSpellPlaced(profile, id)` with no mode argument behaves exactly as
  before — this is the compatibility guard for the other callers.

The picker rows are built by `RefreshPicker`; assert on the label text it sets
(the grey is a `|cff808080` escape), not on anything visual.

Confirm the new cases fail before your change. Quote the failure text.

**Do not delete or rewrite an existing case.** If one must change, leave it and
put the before/after under **"Existing tests I believe need to change"**.

## 4. Gate

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Paste the tail. Any failure is one you caused.

## 5. What you cannot claim

You cannot launch the game. Whether the picker now reads correctly to the player
is theirs to say, not yours.
