# AscensionSuite

AscensionSuite is a World of Warcraft addon for the **Ascension / Project Ebonhold** client. It layers a **player-owned Wishlist panel** and **opt-in assists** on top of Ascension’s **native Rapid Rolling UI** (Desired · Roll · Known) — it does **not** rebuild that three-column board.

**v0.2.5** ships: **Wishlist tab** in `/asuite` (works outside Wildcard), Rapid **Continue unstick**, filter-proof Desired sync, an opt-in **keep going after a Desired hit** assist, roll logbook, and guarded assists — all assists default **off**.

## In-game

```
/asuite
```

Two tabs:

### Wishlist
- Search + scrollable list (icon, name, id; Desired badge when synced)
- Add by spell / entry id (client chrome 1:1 via AscensionAPI)
- The row you just added, removed or toggled lights up — including when the edit came from the Character Advancement book
- Remove / Clear (Suite store only — Ascension Desired untouched until you push)
- **Push to Desired** — Wildcard only; hover it when it is greyed out and it says why
- Save / Load named profiles

### Assists
- Checkboxes (all default off): Auto-Roll, keep going after a Desired hit, dice/SkillCard animation skip, Wildcard popup accept, logbook capture
- **Start / Stop** for Auto-Roll, with a readable reason whenever it refuses or stops
- **Unstick** if Rapid Continue is stuck gray — confirms in chat
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
sh scripts/release.sh 0.2.5
```

`build-dist.sh` cross-checks every TOC-listed Lua file against the built archive, so a payload directory missing from the zip fails the build. Roll starters (`RollAbilities`, `StartRapidRolling`, …) and `C_*` globals are allowed **only** in `integration/AscensionAPI.lua`; `scripts/check.sh` enforces both. `tests/test_load.lua` fails a release whose version is not the same in `AscensionSuite.toc`, `core/Bootstrap.lua`, the newest `CHANGELOG.md` heading and this README.

Mockups live under `docs/sketch/`.

## License

All Rights Reserved.
