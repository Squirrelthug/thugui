# QA — what has to be checked in the game before a release

`Tests/loadtest.lua` proves code loads, logic is right, and nothing throws. It
cannot tell you an icon is the right size, in the right place, or that a client
delivers the event we think it does. Everything below is therefore **manual, in
the running game**, and exists because each item has either bitten this addon
already or is a known blind spot.

Run this as a pass before calling a state a release candidate. Record the date
and the client build next to each result — "it worked once" without a build
number has already misled this project.

---

## 1. UI scale — the whole matrix, not one setting

**Why this is first.** ThugUI is a personal addon built and tested on one
player's UI scale, and almost every geometry bug it has had was invisible at
that one setting. The adopted-buff sizing defect (`DECISIONS.md` §17) survived
because the only profile in daily use sat at `scale = 1`, where the grid's
coordinate space and the screen's coincide.

There are **three independent scales** and they multiply:

| Scale | Where | Typical |
|---|---|---|
| WoW UI Scale | System → Advanced → UI Scale | 0.53 – 1.0 |
| `profile.scale` | ThugUI, per spec, Cooldown Viewer page | 0.5 – 2.0 |
| Blizzard viewer scale | Edit Mode, on the Cooldown Manager | user set |

Check at minimum the corners: UI scale **minimum**, **1.0**, and **maximum**,
each against a ThugUI profile at **0.5**, **1.0** and **2.0**.

What to look at, per combination:

- [ ] An adopted buff icon is the **same size** as an ordinary cooldown icon
      beside it. This is the §17 regression and the reason this section exists.
- [ ] Icons sit on the grid, not overlapping and not gapped.
- [ ] The shape sits where the anchor says relative to the cursor.
- [ ] Collapse closes cleanly — no icon overflowing the cell reserved for it.
- [ ] Combo pips ring the cursor without drawing under the grid.

`FitItem` logs its arithmetic once per session — `CVBUFF: fit: base=… icon=…
ours=… theirs=… -> scale=…`. When a size looks wrong, read that line before
theorising: it says which of the two coordinate spaces disagreed.

**The design intent is that UI scale cancels out**, because the fit divides two
`GetEffectiveScale()` values and UIParent appears in both. That is reasoning,
not evidence — it has never been checked at a non-default UI scale.

## 2. Per-character, not just per-spec

**Profiles are keyed by spec ID and stored account-wide** (`ThugUI_Config`, via
`## SavedVariables`, with no `SavedVariablesPerCharacter`). Two characters of the
same class and spec **share one layout** and cannot be configured apart.

This is fine for one main. It is wrong the moment a player has two of the same
spec — and this player does. Any release that goes beyond one person needs this
decided, not discovered.

- [ ] Confirm the intended behaviour: shared per spec, or split per character.
- [ ] If split: a migration path that does not discard existing profiles.

## 3. Per-spec sweep

Everything below is per-profile, so a fix proven on one spec proves nothing
about the others. Walk every spec that has a profile:

- [ ] Icons draw, count down, and disappear correctly.
- [ ] `aura`-mode placements adopt a Blizzard buff frame — and the buff is in
      **Tracked Buffs** or **Tracked Bars**, or nothing can draw at all
      (`DECISIONS.md` §13).
- [ ] Charges: a spell with more than one charge shows the right count and the
      radial sweep. **Known suspect** — Guardian's Maul draws its icon with no
      radial dial, and Outlaw's Grappling Hook disappears at zero charges.
      Neither is diagnosed yet.
- [ ] Collapse direction matches the anchor. `auto` derives it from the anchor
      position, so an anchor at row 0 packs **upwards** by design — verify the
      anchor is where the player thinks before calling the direction wrong.

## 4. Evidence, every time

- [ ] `/reload` at the end of the session so SavedVariables flush.
- [ ] `ThugUI_DebugLog.events` — no unexpected `CVBUFF:` failure lines.
- [ ] `ThugUI_DebugLog.state` — every placed icon present, `linked=N` sane.
- [ ] `!BugGrabber.lua` — **zero** errors naming ThugUI, and zero errors inside
      a *Blizzard* file that name ThugUI. The second kind means we exported
      taint into their frame (`DECISIONS.md` §15).

## 5. The fallback still works

Deliberately preserved escape hatches. If these are broken, the release is not
shippable regardless of how good the new path looks.

- [ ] `/thugcv legacy` switches to the ECV/BCV/GCV bars and they draw.
- [ ] The Reforestation corner and icon-scale controls on the legacy ECV panel
      still work — they are `rf*`-prefixed locals and have been a near-miss for
      deletion once already (`DECISIONS.md` §16).
- [ ] The Blizzard settings panels are all still registered.

---

## Not covered here, and why

Anything the harness already proves belongs in `Tests/loadtest.lua`, not on this
list. A manual check that could have been automated is a manual check that will
eventually be skipped.
