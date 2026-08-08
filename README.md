# AscensionSuite

AscensionSuite is a World of Warcraft addon for the **Ascension / Project Ebonhold** client. It layers a **player-owned Wishlist panel** and **opt-in assists** on top of Ascension’s **native Rapid Rolling UI** (Desired · Roll · Known) — it does **not** rebuild that three-column board.

**v0.2.4** ships: **Wishlist tab** in `/asuite` (works outside Wildcard), Rapid **Continue unstick**, Desired sync, roll logbook, and guarded assists — all assists default **off**.

## In-game

```
/asuite
```

Two tabs:

### Wishlist
- Search + scrollable list (icon, name, id; Desired badge when synced)
- Add by spell / entry id (client chrome 1:1 via AscensionAPI)
- Remove / Clear (Suite store only — Ascension Desired untouched until you push)
- **Push to Desired** — Wildcard only; otherwise the list stays saved locally
- Save / Load named profiles

### Assists
- Checkboxes (all default off): Auto-Roll, dice/SkillCard animation skip, Wildcard popup accept, logbook capture
- **Start / Stop** for Auto-Roll
- **Unstick** if Rapid Continue is stuck gray
- Logbook of recent rolls

## Marking wishlist entries

| Where | How |
|-------|-----|
| **`/asuite` → Wishlist** | Add by id, or manage the list |
| **Character Advancement book** | **Alt + right-click** a spell (saves to Suite wishlist; Desired only in Wildcard) |
| **Rapid Rolling → Desired** | Toggle as usual — Suite tracks it |

Auto-Roll only runs against Ascension **Desired**. Start (or **Push to Desired**) syncs your Suite wishlist into Desired while Wildcard is active.

## Assists (`AscensionSuiteDB.assists`)

| Key | Default | Job |
|-----|---------|-----|
| `autoRoll` | `false` | Auto-Roll while leveling (1–60), Desired targets only |
| `instantDiceSkip` | `false` | Speed up WildCardDice flipbooks (rapid reel is not Finish()'d) |
| `instantSkillCardSkip` | `false` | Speed up SkillCard reveal flipbooks |
| `acceptWildcardPopups` | `false` | Auto-accept Wildcard roll confirms only |
| `captureRolls` | `false` | Append roll results to logbook |

Draft / Hall of Fame / store automation stay out of scope. See `SECURITY.md`.

## Install (release zip)

1. Download **AscensionSuite.zip** from [GitHub Releases](https://github.com/Lzra2000/AscensionSuite/releases).
2. Extract so you have `Interface/AddOns/AscensionSuite/AscensionSuite.toc`.
3. Restart the client (or `/reload`) and run `/asuite`.

## Develop

```bash
sh scripts/check.sh
sh scripts/build-dist.sh
sh scripts/release.sh 0.2.4
```

`build-dist.sh` cross-checks every TOC-listed Lua file against the built archive, so a payload directory missing from the zip fails the build. Roll starters (`RollAbilities`, `StartRapidRolling`, …) and `C_*` globals are allowed **only** in `integration/AscensionAPI.lua`; `scripts/check.sh` enforces both.

Mockups live under `docs/sketch/`.

## License

All Rights Reserved.
