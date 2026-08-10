---
name: wow-addon-dev
description: Develop and debug World of Warcraft addons on modern retail (12.x), where secret values and addon restrictions decide what an addon may read. Covers finding the truth in Blizzard's own source, the evidence loop for a game you cannot attach a debugger to, testing without launching the client, and the traps that cost real days. Use when writing Lua for WoW, debugging taint or "the value is secret", reading C_* APIs, working with the Cooldown Manager or aura APIs, or when an addon behaves differently in combat than out of it.
license: MIT
metadata:
  author: Squirrelthug + Claude
  version: "0.1.0"
  domain: game-ui
  triggers: wow addon, world of warcraft, lua 5.1, taint, secret value, C_UnitAuras, UnitPower, cooldown manager, edit mode, oUF, SavedVariables, frame strata, addon restrictions
  role: specialist
  scope: implementation
  output-format: code
  related-skills: debugging-wizard, test-master, game-developer, legacy-modernizer
  maturity: early — written from one addon's hard-won lessons. Grow it with each new one; prune anything that stops being true.
---

# WoW Addon Development (retail 12.x)

**Status: early.** Everything here was paid for with a real debugging session on
a real addon. It is not a complete guide to the API, and it is not a substitute
for reading Blizzard's source. Treat each section as a claim with evidence
behind it, and correct it when the game proves otherwise.

## The three rules that matter most

1. **The client is the final authority.** Below it, Blizzard's own Lua. Below
   that, the wiki. Never your memory — the API changes every patch and the
   training data is always stale.
2. **You cannot attach a debugger.** So build the evidence loop before you build
   the feature (see below). Every hour spent making the addon explain itself
   pays for several spent guessing.
3. **Never invent a spell ID, a frame name or an enum value.** Verify it or
   resolve it at runtime. A plausible wrong ID produces a bug that looks like a
   logic error.

## Modern taint: what actually changed in 12.0

The single most expensive misconception is that taint is a thing you clean.

**Addon code always executes tainted by its own addon.** There is no untainted
state to reach. An error reading `while execution tainted by 'YourAddon'` is the
engine saying *this is addon code*, not *you did something wrong*. If several
addons on a machine report that error, they are the several addons that touch
restricted values — not the several that are dirty.

12.0 added **secret values**. Certain API results become opaque to addon code
under certain conditions. With a secret you may:

- store it, pass it around, `type()` it, concatenate it
- hand it to a *blessed* setter that renders it without showing it to you

You may **not**: compare it, do arithmetic on it, use it as a table key, `#` it,
`tostring` it, or branch on it. Any of those throws.

### Read the flags instead of guessing

`Blizzard_APIDocumentationGenerated/*.lua` carries the answer for every
function. This is the fastest tool in the box:

```sh
gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/\
Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua?ref=live" \
  --jq .content | base64 -d | grep -n -B2 -A16 'Name = "GetUnitAuraBySpellID"'
```

| Flag | Meaning for your addon |
|---|---|
| `SecretWhen*` (`InCombat`, `UnitAuraRestricted`, `UnitPowerRestricted`, `CooldownsRestricted`) | the return becomes secret under that condition |
| **`RequiresNonSecretAura`** | returns **nothing at all** rather than a secret — an empty return is the API refusing, not a bug in your lookup |
| `SecretArguments = "AllowedWhenTainted"` | you may pass a secret **in** |
| `SecretArguments = "AllowedWhenUntainted"` | you may not; passing one throws |
| `NeverSecret` on an argument or field | always readable |

### Write every read defensively

```lua
-- issecretvalue FIRST: comparing a secret to nil is itself a comparison.
local value = UnitPower("player", powerType)
if issecretvalue and issecretvalue(value) then
    -- Hold the last known state. Do not compare, format or do maths on it.
    return
end
```

### Displaying what you cannot read

The sanctioned path is to hand the secret to the engine:

- `StatusBar:SetValue(secret)`, `StatusBar:SetMinMaxValues`
- `Frame:SetAlpha(secret)`, `SetVertexColor`, `SetDesaturated`
- `C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, ifTrue, ifFalse)` —
  branch on a secret boolean without ever seeing it
- `FontString:SetText` / `SetFormattedText`

**Verify each one on the client.** Documentation and wiki both listed the
`Cooldown` setters as accepting secrets; on 12.0.7 `SetCooldownDuration`
refuses them. `CurveObject:Evaluate` also refuses secret input from tainted
code, so curves only help where a Blizzard API evaluates the curve for you.

### When you cannot read the state at all

Some things are deliberately closed. Identifying *which aura is which* during
combat is one: the list returns, the structs index, the spell ID is right there
— and comparing it throws. Everything around it works, which is how you know
the gap is the point rather than an oversight.

When you hit one of those, stop trying to out-engineer it. **The only code that
can do it is Blizzard's, so use Blizzard's frames**: find the frame their UI
already draws for that state, and position or restyle it. Their untainted code
keeps deciding what it shows; you decide where it lives.

Caution, learned the hard way: touching frames that Edit Mode manages can make
Edit Mode stop offering them. Prefer anchoring over reparenting, change the
fewest properties you can, remember the originals, and never call their layout
methods from your own stack if you can avoid it.

## The evidence loop

You cannot step through code in a running game. Build these three things early;
they repay themselves within a session.

1. **Always-on diagnostics into SavedVariables.** No slash command to remember,
   no debug flag. A short ring buffer of events plus a state snapshot. Record
   evidence of *behaviour*, not version strings — "resolved 4 linked spells" is
   proof of which code ran; a version number is proof of what is on disk.
2. **Log the stage that failed, not the failure.** "The icon did not draw" has
   several causes that look identical from outside: the API threw, it returned
   nothing, or your own filter rejected the result. Give each its own log line,
   keyed so it cannot be deduplicated against the others — *include the combat
   state in the key*, or the out-of-combat case will suppress the in-combat one
   you were trying to capture.
3. **A capability probe.** A module that samples the APIs you depend on at
   several moments (idle, entering combat, during, leaving) and records for each
   one: readable value, secret, nothing, or error. One fight and one reload then
   answers questions that otherwise take a week of inference.

Snapshot timing matters: `PLAYER_LOGOUT` is too late for anything spec-related
(`GetSpecializationInfo` has already stopped resolving). Capture on
`PLAYER_REGEN_ENABLED` and `PLAYER_ENTERING_WORLD` instead, and never let a
capture with unreadable state overwrite a good one.

Where the files live (retail):

```
WTF/Account/<ACCOUNT>/SavedVariables/<Addon>.lua      your settings + your log
WTF/Account/<ACCOUNT>/SavedVariables/!BugGrabber.lua  errors, stacks, locals
```

Both are written on `/reload` or logout only. **An error from a session still
running is not on disk.** Ask for a reload; one reload beats two rounds of
speculation. And never edit SavedVariables while the game is running — it holds
them in memory and overwrites you on exit.

## Testing without launching the game

A load-order smoke test catches a genuinely large share of real bugs. Stub
enough of the API to execute every file in TOC order, then drive the code.

- Synthesise unknown frame methods from a metatable so long call chains work,
  but **only for capitalised keys** — real frames return nil for unset plain
  fields, and code like `f.thing or {}` depends on that.
- Model, do not swallow, the state your tests need to assert on: shown state,
  anchors, alpha, vertex colour, cooldown seeding.
- Stub secret values as a sentinel table and a matching `issecretvalue`, so the
  "everything is unreadable" path is exercised on every run. That path is the
  one that only executes in combat, in the game, where you cannot look at it.
- **Add a case for every bug you fix.** A bug with no test is a bug that comes
  back.

It cannot tell you an icon is in the right place or that the client delivers the
event you expect. Say so out loud rather than letting "tests pass" imply more
than it means.

## Traps that cost real time

- **`SetParent(nil)` does not free a frame.** It orphans it. Pool and reuse
  frames instead; a settings slider that rebuilds a UI on every tick will
  otherwise bleed frames for the whole session.
- **Pooled frames carry their last life's state.** Reset alpha, texture, text,
  cooldown and shown-state on acquire, or one icon inherits another's sweep.
- **`UNIT_*` events fire for every unit in range.** Use
  `RegisterUnitEvent(event, "player")` or a raid will bury you.
- **Anchors resolve against hidden frames.** Anchor to a hidden frame freely;
  but a *child* of a hidden frame never draws. That distinction decides whether
  to parent or to anchor.
- **Frame strata comes from the parent.** If you anchor someone else's frame
  into your UI without reparenting, it still draws at *their* strata.
- **WoW runs Lua 5.1.** No `goto`, no integer division, no `table.pack`,
  `unpack` is global. Your local `lua` is probably 5.4+ and will happily accept
  code the game rejects. Run `luac -p` with a matching version if you can.
- **Windows shells mangle inline commit messages.** Write the message to a file
  and use `git commit -F`.

## Where to look things up

| Source | Use it for |
|---|---|
| `Blizzard_APIDocumentationGenerated/*.lua` | flags, fields, enums — the authority on what an addon gets |
| Blizzard's UI Lua (`Gethe/wow-ui-source`, branches `live`/`beta`/`ptr`) | semantics: what the default UI actually does with a value |
| townlong-yak.com/framexml | the same source with build-to-build **Compare**, for "what changed this patch" |
| warcraft.wiki.gg | signatures, enum values, patch API-change pages. Good orientation, verify behaviour elsewhere |
| Installed addons on the machine | a working reference that provably runs on this exact client. Check the licence before copying |

Reading a file:

```sh
gh api "repos/Gethe/wow-ui-source/git/trees/live?recursive=1" --jq '.tree[].path' | grep -i cooldownviewer
gh api "repos/Gethe/wow-ui-source/contents/<path>?ref=live" --jq .content | base64 -d
```

## Open questions this skill cannot yet answer

Kept deliberately, so the next person knows where the edge is:

- Exactly which operations on an Edit Mode managed frame cause Edit Mode to
  stop offering it, and whether anchoring alone is safe.
- Whether a frame's `IsShown()` is readable when Blizzard set it from secret
  data, which would allow mirroring their state onto your own widgets.
- How much of this 12.0 model survives 12.1, which tightens aura access further
  (index/slot/instanceID aura calls are documented to *error* rather than return
  secrets).
