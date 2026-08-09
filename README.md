# AscensionSuite

AscensionSuite is a World of Warcraft addon for the **Ascension / Project Ebonhold** client. It layers a **player-owned Wishlist panel** and **opt-in assists** on top of Ascension’s **native Rapid Rolling UI** (Desired · Roll · Known) — it does **not** rebuild that three-column board.

**v0.4.10** stops **Auto-Roll** when a keep-vs-unlearn decision is up (`DECISION_PENDING`,
`CONFIRM_UNLEARN_S`, Scroll of Fortune spend): Suite never auto-Unlearns; Cancel/Unlearn is
always yours. **v0.4.9** fixes **Wild Card dice clickability after level-ups**: when animation skip or
overlapping roll sessions left the die shown with mouse disabled, `EnsureDiceClickable`
restores native `RegisterOnClick` on `PLAYER_LEVEL_UP` / roll-open events; **Unstick**
and **auto-unstick** recover unclickable leveling dice as well as gray Rapid Continue.
**v0.4.8** fixes **Wishlist row icons**: Ascension's short `entry.Icon` filenames are prefixed like native CA/Rapid, spell textures resolve via the entry's spell id (not internal entry ids), and book rows pass the internal-id hint so spell-id collisions cannot pick the wrong art. **v0.4.7** fixes Loadouts **UI overlap**: ASUITE2 export is clipped in a scroll-wrapped edit box, **Copy share / Import** sit in a reserved footer band below section content (equipment, notes, spells), stray **Wishlist tab** chrome is corrected on show/tab switches, and the detail column anchors to the panel height. **v0.4.6** adds Loadouts **Stop Auto-Roll** on the automate strip, **remembers your last selected build** across reload, **shared ↔ character scope toggle**, **Clear Desired (filtered)** for Wildcard marks on the visible spell list, an **empty-state** hint when no builds exist, and **tag cycling** (Alt+click or tag button) on spell rows. **v0.4.5** adds Loadouts **remove** (`x` on spell rows), **Duplicate build**, **search** on Spells and Talents, **Known** badges from captured snapshots, and **ASUITE2** share strings (sections + equipment; ASUITE1 import still works). **v0.4.4** adds Loadouts spell **tooltips**, **right-click Desired toggle** on spell rows (like Wishlist), **add-by-id** (+ Add Spell box), **Rename** for builds, and colorized **Pros and Cons** preview. **v0.4.3** polishes Loadouts: live **Desired: X of N** on the automate strip (filtered spells), equipment icon rows, **Capture Known**, clearer Import Archetype errors, and clickable category/complexity chips. **v0.4.2** fixes Loadouts **Apply → Desired** (spell-first entry resolution, no more blanket Push refused), **Start Auto-Roll** auto-applies the selected build, ASUITE1 share strings, and Overview/Notes section UI (no spell filter chrome on non-Spells pages). **v0.4.1** fixes a Lua 5.1 tooltip crash when hovering unranked talents on the wishlist (`tonumber` multi-return leak from `GetTalentRank`). **v0.4.0** redesigns the **Loadouts** tab to mirror native Ascension Archetypes sections (sidebar nav, spell filters grouped by class, local notes per section) with an always-visible automation strip (Apply → Desired, Auto-Roll, Sync from Rapid, → Wishlist) and **Import Archetype…** from the active/draft build via the AscensionAPI seam. **v0.3.1** fixed Loadouts layout 0×0 issues and added auto-unstick.

## In-game

```
/asuite
```

Three tabs:

### Wishlist
- Search + scrollable list (icon, name, id; Desired badge when synced)
- **Left-click** selects a row; **right-click** toggles Desired in Wildcard
- Add by spell / entry id (client chrome 1:1 via AscensionAPI)
- The row you just added, removed or toggled lights up — including when the edit came from the Character Advancement book
- Remove / Clear (Suite store only — Ascension Desired untouched until you push)
- **Push to Desired** — merges the list into Ascension Desired in Wildcard; click it anytime the list has rows and it says why if Wildcard is not active

### Loadouts
- Archetype-style sidebar: Overview, Spells and Talents, Equipment, Pros and Cons, Itemization, Rotation, Enchants and Consumables, Macros, WeakAuras, Additional Notes
- **Import Archetype…** pulls spells + section text from the active/draft native build (C_BuildCreator / C_BuildEditor seam only)
- Automation strip: **Apply → Desired**, **Clear Desired (filtered)**, **Start / Stop Auto-Roll** (only when Auto-Roll assist is on), **Sync from Rapid**, **→ Wishlist**
- Spells and Talents: Core/Optimal/Empowering/Synergistic filters, class grouping, Desired badges, **tag cycling** (Alt+click) — only this section drives automation
- Build header: **Scope** chip toggles shared vs character storage; last selected build is remembered across reload
- Other sections: local editable notes stored on the loadout (SavedVariables)
- Saved builds list, **Save Build**, **Reset**, **Duplicate**, **Copy share** / Import string (ASUITE2; ASUITE1 import still accepted)

### Assists
- Checkboxes (all default off): Auto-Roll, keep going after a Desired hit, dice/SkillCard animation skip, Wildcard popup accept, logbook capture, **auto-unstick gray Rapid Continue**
- **Start / Stop** for Auto-Roll, with a readable reason whenever it refuses or stops
- **Unstick** if Rapid Continue is stuck gray or the leveling die will not accept clicks — confirms in chat (auto-unstick uses the same recovery when opted in)
- **Sync from Rapid** to pull in marks made before the addon was watching
- Logbook of recent rolls

## Marking wishlist entries

| Where | How |
|-------|-----|
| **`/asuite` → Wishlist** | Add by id, or manage the list |
| **Character Advancement book** | **Alt + right-click** a spell (saves to Suite wishlist; Desired only in Wildcard) |
| **Rapid Rolling → Desired** | Toggle as usual — Suite tracks it |

Auto-Roll only runs against Ascension **Desired**. Start (or **Push to Desired**) merges your Suite wishlist into Desired while Wildcard is active — it only ever adds, so marks you made by hand are left alone.

**Sync from Rapid** is not limited to what the Rapid window's Desired search box is showing: it widens that list for the length of the scan, puts your search straight back, and also reads Ascension's own record of your Desired toggles.

## Assists (`AscensionSuiteDB.assists`)

| Key | Default | Job |
|-----|---------|-----|
| `autoRoll` | `false` | Auto-Roll while leveling (1–60), Desired targets only |
| `autoRollContinue` | `false` | After a Desired entry lands, close the session and start the next one |
| `instantDiceSkip` | `false` | Speed up WildCardDice flipbooks (rapid reel is not Finish()'d) |
| `instantSkillCardSkip` | `false` | Speed up SkillCard reveal flipbooks |
| `acceptWildcardPopups` | `false` | Auto-accept Wildcard roll confirms only |
| `captureRolls` | `false` | Append roll results to logbook |
| `autoUnstick` | `false` | After a short stuck window, recover gray Rapid Continue or an unclickable die (same path as **Unstick**) |

### Keep going after a Desired hit

Off by default, and off is still the behaviour from 0.2.1: a Desired entry lands, the session is closed through Ascension's own Roll button, and Auto-Roll hands control back. Switch it on and it opens the next session instead, so a wishlist of a dozen entries is one Start rather than twelve.

It ends when there is nothing Desired left on the wishlist, when you press Stop, on any error Ascension reports — and on two ceilings that keep a misbehaving session from becoming a reroll loop: the same entry landing twice, and 25 chained sessions.

Draft / Hall of Fame / store automation stay out of scope. See `SECURITY.md`.

## Install (release zip)

1. Download **AscensionSuite.zip** from [GitHub Releases](https://github.com/Lzra2000/AscensionSuite/releases).
2. Extract so you have `Interface/AddOns/AscensionSuite/AscensionSuite.toc`.
3. Restart the client (or `/reload`) and run `/asuite`.

## Develop

```bash
sh scripts/check.sh
sh scripts/build-dist.sh
sh scripts/release.sh 0.2.6
```

`build-dist.sh` cross-checks every TOC-listed Lua file against the built archive, so a payload directory missing from the zip fails the build. Roll starters (`RollAbilities`, `StartRapidRolling`, …) and `C_*` globals are allowed **only** in `integration/AscensionAPI.lua`; `scripts/check.sh` enforces both. `tests/test_load.lua` fails a release whose version is not the same in `AscensionSuite.toc`, `core/Bootstrap.lua`, the newest `CHANGELOG.md` heading and this README.

Mockups live under `docs/sketch/`.

## License

All Rights Reserved.
