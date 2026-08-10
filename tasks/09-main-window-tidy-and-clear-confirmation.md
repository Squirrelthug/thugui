# 09 — Main window: a heading, a confirmation, and a message that points somewhere

Read `00-AGENT-BRIEF.md` first.

Three independent changes to the Cooldown Viewer page, all specified by the
player. You are implementing, not designing.

Baseline: whatever `main` is when you start, `lua Tests/loadtest.lua .` →
**0 failures**. Task 08 landed just before this one and moved the "Use Blizzard's
buff frames" checkbox off this page into the guide panel — expect it to be gone,
and do not put it back.

Files you may modify:
- `ui/pages/CooldownViewer.lua`
- `Tests/loadtest.lua`
- `tasks/reports/09-report.md`

---

## 1. "Enable Buffs" heading above the red link

In `Page:BuildInspector`, the `misc` panel currently reads:

```
[Section] This layout
  [x] Show proc glow
  ENABLE BUFFS          <- a plain Label
  [WORKAROUND]          <- red, clickable
  [Clear this layout]
```

The player wants the red link visually separated from the layout controls above
it, with a real section heading — **the same style as "This layout"**, meaning a
gold label with a rule running off to its right.

That is exactly what `Panel:Section(text)` produces (`ui/Widgets.lua:257`). So:

- Replace the plain `misc:Label("ENABLE BUFFS")` with `misc:Section("Enable Buffs")`.
- Title case, as written here — it sits beside "This layout" and should match it.
- The red `[WORKAROUND]` link stays directly beneath, unchanged.

`Section` already emits its own leading `Gap(12)`, so remove any manual gap you
would otherwise be doubling up. Check what is there before adding.

## 2. Confirm before clearing a layout

Still in `Page:BuildInspector`, the "Clear this layout" button wipes every
placement for the spec on a single click, with no way back. The player's words:
*"one button clearing would piss me off as a user"*.

Put a confirmation in front of it, **centred on the screen**.

Use Blizzard's `StaticPopupDialogs`. There is no existing use of it in this
repo, so establish the pattern cleanly:

```lua
StaticPopupDialogs["THUGUI_CV_CLEAR_LAYOUT"] = {
    text = "...",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ... end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
```

Requirements, each for a reason:

- **The key must be namespaced** — `THUGUI_` prefix. `StaticPopupDialogs` is a
  shared global table; an unprefixed key can collide with another addon's, and
  the brief's rule about namespacing globals applies to table keys in Blizzard's
  registries just as much as to frame names.
- `preferredIndex = 3` — without it, a popup shown while other popups exist can
  throw a taint error from Blizzard's own code. This is the standard workaround.
- `timeout = 0` and `hideOnEscape = true`. A destructive confirmation must not
  time out into either answer, and Escape must mean no.
- **`button1` / `button2` use the globals `YES` and `NO`**, which are already
  localised. Do not type the words.
- The message must name what is about to be lost — the spec whose layout it is,
  and that other specs are untouched. The button's existing tooltip has the
  wording: *"Remove every icon from this spec's grid. Does not touch other
  specs."* Use the spec name if it is readily to hand (`Page.editSpecID`
  resolves one — see how the page's spec dropdown labels itself); if getting it
  is awkward, a generic message is acceptable. Say which you did.
- The clearing work itself does not change. Move the existing `onClick` body
  into `OnAccept` verbatim; the button's `onClick` now only shows the popup.

Define the dialog table **once at file scope**, not inside `BuildInspector` —
that function can run more than once and re-registering on every build is
pointless churn. `OnAccept` therefore has to reach the page; use the file's
existing `Page` upvalue rather than capturing anything from the build call.

## 3. The picker's empty message should point at the fix

When "Use Blizzard's buff frames" is off and the picker's source is "buffs",
`Page:RefreshPicker` shows an explanatory message. Replace its text with, close
to verbatim:

> Tracked buffs require specific settings. Look for [WORKAROUND] at bottom right
> of this window

with **`[WORKAROUND]` in red**, matching the red of the link it refers to. Find
the colour the link actually uses and reuse the same escape rather than picking
a second red — grep the guide/page for the existing one.

Leave the other branch of that message (the generic "nothing here" text) alone.

## 4. Tests

Add to `Tests/loadtest.lua`:

- The `misc` panel builds a section titled "Enable Buffs".
- `StaticPopupDialogs["THUGUI_CV_CLEAR_LAYOUT"]` exists after the page builds,
  and has `timeout == 0` and `hideOnEscape == true`.
- Clicking "Clear this layout" does **not** wipe placements on its own; running
  the dialog's `OnAccept` does. This is the case that matters — assert
  placements survive the click and are gone after `OnAccept`.
- The buffs-off picker message contains both the word `WORKAROUND` and a red
  colour escape.

The harness may not stub `StaticPopupDialogs` or `StaticPopup_Show`. If it does
not, add the stub — that is expected and in scope. `YES` and `NO` may also need
stubbing as globals.

**Do not delete or rewrite an existing test case.** If one must change, leave it
and put the before/after under **"Existing tests I believe need to change"** in
your report.

## 5. Gate

```sh
luac -p <every file you touched>
lua Tests/loadtest.lua .
```

Paste the tail. Any failure is one you caused.

## 6. What you cannot claim

You cannot launch the game. The popup actually appearing centred, the section
rule drawing at the right width in a 260-wide panel, and the red reading as red
against that background all go in **Not verified**.
