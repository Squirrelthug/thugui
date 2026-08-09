# Where the information comes from

Finding trustworthy WoW addon-development information is genuinely hard: most
search results are guides for players, blog posts for a six-year-old expansion,
or wiki pages that document a function's *signature* and say nothing about what
it actually does.

This is the working list. **Grow it** when something proves useful, and **prune
it** when something goes stale.

**Re-check the whole list before each patch**, and note the date. A dead source
that still looks authoritative is worse than no source.

---

## Tier 1 — Blizzard's own code and data

These are authoritative. If they disagree with anything else, they win.

| Source | What it gives | Last checked | Status |
|---|---|---|---|
| **[townlong-yak.com/framexml](https://www.townlong-yak.com/framexml/)** | Blizzard's UI source *and* generated API docs, with **build-to-build Compare links**. The best single source for "what changed in this patch" | 2026-08-08 | Live — build 69189 (12.1.0) PTR, 3,625 files |
| **[Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source)** | Same source as a git repo, branches `live` / `beta` / `ptr`. Greppable and scriptable via `gh api` | 2026-08-08 | Live |
| **`Blizzard_APIDocumentationGenerated/*.lua`** | Blizzard's *machine-generated* API documentation, shipped in the client. Where field lists and "Added in 12.1.0" annotations originate. Present in both mirrors above | 2026-08-08 | Live |
| **`/api` in-game** | The same generated docs, queryable live against your actual client. Best for "does this exist on MY build" | — | Not verified this session |

### How to use them

```sh
# What CooldownViewer files exist?
gh api "repos/Gethe/wow-ui-source/git/trees/live?recursive=1" \
  | ConvertFrom-Json | %{ $_.tree } | ? path -match 'CooldownViewer'

# Read one (content is base64)
gh api "repos/Gethe/wow-ui-source/contents/<path>?ref=live" --jq .content
```

Swap `?ref=live` for `ptr` to read the next patch before it ships. Use
townlong-yak's Compare view to see the diff between two builds directly, which
is faster than diffing branches by hand.

**The generated documentation files are the underrated one.** Searching
`Blizzard_APIDocumentationGenerated` for a system name gives you every function,
field and enum with type information, straight from Blizzard, with no community
transcription errors in between.

## Tier 2 — community reference

Good for orientation and lookup. Verify behaviour against Tier 1.

| Source | What it gives | Last checked | Status |
|---|---|---|---|
| **[warcraft.wiki.gg](https://warcraft.wiki.gg)** | API signatures, enum values, `Added in X.Y.Z` annotations. Its `Patch_X.Y.Z/API_changes` pages are a good patch-diff starting point | 2026-08-08 | Live |
| **[wowhead.com](https://www.wowhead.com)** | Spell IDs and tooltips — use it to verify an ID rather than trusting memory. Also patch/datamining news | 2026-08-08 | Live |
| **[Stanzilla/WoWUIBugs](https://github.com/Stanzilla/WoWUIBugs)** | Community UI/API bug tracker. Useful for "is this broken for everyone or just me" | 2026-08-08 | Active — 183 open issues, latest late July 2026. Blizzard engagement *not* confirmed from the issue list |
| **[wago.tools](https://wago.tools/)** | Datamined DBC/DB2 tables and build comparisons | 2026-08-08 | **Unverified** — the site is a JS app and did not render for automated fetch. Check manually before relying on it |

### Known limitation of the wiki

warcraft.wiki.gg reliably documents **what a function takes and returns**. It
frequently does **not** document what the values mean or how the default UI uses
them. Two examples from this project:

- `linkedSpellIDs` / `selfAura` / `hasAura` are listed as fields with types and
  no explanation whatsoever. The behaviour — walk the linked list looking for an
  active aura from the player — only exists in Blizzard's Lua.
- `Enum.CooldownViewerCategory` values are listed correctly, but nothing says
  that `TrackedBar` draws from the same pool as `TrackedBuff`.

**Rule: wiki for signatures, Blizzard source for semantics.**

## Tier 3 — other addons on this machine

`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`

Installed addons are a working reference for how a real, shipping addon solves
a problem — and unlike a forum post, the code in front of you demonstrably runs
on this exact client version.

Used this way already: the anchor-picker idiom in ThugUI's grid editor came from
reading `tRP3_Vendor`'s eight-point portrait picker.

Check the licence before copying code, not just before shipping it.

---

## Review log

| Date | What changed |
|---|---|
| 2026-08-08 | List created. Tier 1 and 2 verified live except `wago.tools` and in-game `/api`. townlong-yak confirmed carrying 12.1.0 PTR builds with Compare support |
