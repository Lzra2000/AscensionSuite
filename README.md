# AscensionSuite

AscensionSuite is a World of Warcraft addon for the **Ascension / Project Ebonhold** client. It layers a **player-owned Wishlist panel** and **opt-in assists** on top of Ascension’s **native Rapid Rolling UI** (Desired · Roll · Known) — it does **not** rebuild that three-column board.

**v0.5.3** fixes the leveling die stuck on **“Click the Dice to reveal a spell”**
with mouse disabled: sticky Ascension `FadeMode OUT` no longer blocks READY_TO_ROLL
heal, Instant Skip / DiceGuard prefer click recovery over stealer-clear, and Suite
close re-enables mouse even without a demote flag.

**v0.5.2** hardens **Wild Card / Rapid Rolling dice** edge cases: fade-IN is no longer
treated as fade-out, Ascension's native `FULLSCREEN_DIALOG` is no longer rewritten to
`MEDIUM`, recovery cooldown no longer blocks healing a fresh roll die, Suite close
restores dice layering, and DiceGuard / Instant Skip share one guard mode path.

**v0.5.1** applies that native WotLK parchment / gold chrome to **every** `/asuite`
tab — Wishlist, Loadouts, and Assists — so no layer is left on flat-dark panels.

**v0.5.0** redesigns **`/asuite` Assists** as a native WotLK settings window
(Categories sidebar, parchment panels, Cancel/Save drafts, Desired/Undesired
counts and badges) while keeping all assists opt-in and safety rules unchanged.

**v0.4.18** fixes **Instant Dice Skip recovery** when the assist is enabled.

**v0.4.17** keeps **Wild Card dice under `/asuite`** (no `FULLSCREEN_DIALOG` overlay on the
Suite window), surfaces **real Push refusal reasons** (`already learned`, `bad id/type pair`,
`Desired cap reached`, etc.), and clears **stuck wishlist tooltips** on tab/window hide.
**v0.4.16** fixes **Wild Card dice linger and hover/tooltip thrash after level-up**:
DiceGuard and Instant Dice Skip no longer fight Ascension's fade-out by re-enabling
mouse, raising strata, or sanitizing hover every tick; burst events debounce, stuck
non-interactive dice hide after ~1s, and recovery backs off for 2s after a hide.
**v0.4.15** blocks Suite roll paths while a leveling die already shows a revealed spell (`internalID` set — keep-vs-unlearn), auto-**Cancels** `CONFIRM_UNLEARN_S` / Scroll of Fortune I & II confirms during Auto-Roll or Instant Dice Skip recovery (never Accept), and stops with “Unlearn confirm dismissed — Suite never spends Scroll of Fortune.” **v0.4.14** fixes **Wild Card dice hover/tooltip** after Instant Dice Skip and mouse/strata recovery: stale purple highlight or `GameTooltip` no longer stick when the cursor moves away, and hovering the die or **Unlearn & Roll** bar works again after recovery (Suite never auto-Unlearns). **v0.4.13** fixes **Wild Card dice click-stealing** after level-ups / Instant Dice Skip: stranded `WildCardDice` frames at `FULLSCREEN_DIALOG` with mouse enabled no longer block Manastorm tracker buttons and other UI — Suite disables mouse, restores native strata, and hides idle dice; **Unstick** / **auto-unstick** / DiceGuard clear click stealers before restoring a real leveling die. **v0.4.12** fixes **Push / Apply → Desired** when the wishlist was polluted with **Tag / Suggestion** rows from imports: only **Ability** and **Talent** are pushed (Tags are skipped, not blanket-refused), **Clear tags** cleans the wishlist, Auto-Roll explains tag-only lists, and Loadouts spell names no longer truncate to one letter. **v0.4.11** fixes **post-reveal Wild Card decision dice** left unclickable after Instant Dice Skip (green cage + spell icon stranded over nameplates): `EnsureDiceClickable` now covers revealed `DECISION_PENDING` / stranded `REVEALING` visuals, refreshes native RollButton enablement, raises strata, and Animation Skip / DiceGuard schedule recovery after collapse / `SetInternalID`. **v0.4.10** stops **Auto-Roll** when a keep-vs-unlearn decision is up (`DECISION_PENDING`,
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
- Parchment list inside the DialogFrame (same chrome as Assists)
- Search + scrollable list (icon, name, id; Desired / Undes. badges when synced)
- **Left-click** selects a row; **right-click** toggles Desired in Wildcard
- Add by spell / entry id (client chrome 1:1 via AscensionAPI)
- The row you just added, removed or toggled lights up — including when the edit came from the Character Advancement book
- Remove / Clear (Suite store only — Ascension Desired untouched until you push)
- **Push to Desired** — merges the list into Ascension Desired in Wildcard; click it anytime the list has rows and it says why if Wildcard is not active

### Loadouts
- Same native parchment shell as Assists; OptionsFrame-style **Sections** sidebar
- Archetype-style sections: Overview, Spells and Talents, Equipment, Pros and Cons, Itemization, Rotation, Enchants and Consumables, Macros, WeakAuras, Additional Notes
- **Import Archetype…** pulls spells + section text from the active/draft native build (C_BuildCreator / C_BuildEditor seam only)
- Automation strip: **Apply → Desired**, **Clear Desired (filtered)**, **Start / Stop Auto-Roll** (only when Auto-Roll assist is on), **Sync from Rapid**, **→ Wishlist**
- Spells and Talents: Core/Optimal/Empowering/Synergistic filters, class grouping, Desired badges, **tag cycling** (Alt+click) — only this section drives automation
- Build header: **Scope** chip toggles shared vs character storage; last selected build is remembered across reload
- Other sections: local editable notes stored on the loadout (SavedVariables)
- Saved builds list, **Save Build**, **Reset**, **Duplicate**, **Copy share** / Import string (ASUITE2; ASUITE1 import still accepted)

### Assists
- Native WotLK settings layout: **Categories** sidebar (General, Automation, Logbook, Windows & Tools, Wishlist sync)
- Toggle rows use checkbox + title + description; changes are a **draft** until **Save changes** (Cancel reverts)
- Checkboxes (all default off): Auto-Roll, keep going after a Desired hit, dice/SkillCard animation skip, Wildcard popup accept, logbook capture, **auto-unstick gray Rapid Continue**
- **Start / Stop** / **Unstick** on the Automation footer, with a readable reason whenever Auto-Roll refuses or stops
- **Sync from Rapid** under Wishlist sync (also on the Wishlist footer)
- Logbook of recent rolls (clipped inside Logbook / Automation)
- Optional: Desired/Undesired wishlist badges, click-trace pref (both under Windows & Tools)

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
