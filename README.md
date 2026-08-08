# AscensionSuite

AscensionSuite is a World of Warcraft addon for the **Ascension / Project Ebonhold** client. It layers **opt-in assists** on top of Ascension’s **native Rapid Rolling UI** (Desired · Roll · Known) — it does **not** rebuild that three-column board.

**v0.2.0** ships: **AscensionAPI** wrappers, **wishlist → Desired sync**, **roll logbook**, and guarded assists (Auto-Roll, animation skip, popup accept) — all default **off**.

## In-game

```
/asuite
```

Opens the **assist overlay**:

- **Assists** (checkboxes, all default off): Auto-Roll, dice/skillcard animation skip, Wildcard popup accept, logbook capture.
- **Start / Stop** for Auto-Roll (Stop is mandatory while running).
- **Spell / entry id → Add** resolves icon/name/tooltip 1:1 via `AscensionAPI`, then calls `C_Wildcard.AddDesiredID`.
- **Save / Load** named Desired profiles (+ optional Known snapshot) in `AscensionSuiteDB`.
- **Wishlist grid** — click toggles Ascension Desired; native Rapid board stays authoritative.
- **Logbook** — recent rolls captured while the capture assist is on.

## Native Rapid Rolling

Ascension’s `WildCardRapidRollingFrame` owns Desired / Roll / Known. Suite hooks:

| Hook | Purpose |
|------|---------|
| `WILDCARD_RAPID_ROLL_LEARNED` / `WILDCARD_ENTRY_LEARNED` | Logbook capture |
| `AscensionAPI.AdvanceRapidRoll` | Auto-Roll click-equivalent (`StartRapidRolling` / `ContinueRapidRolling` / `RollAbilities`) |
| `hooksecurefunc(WildCardDice, …)` | Opt-in dice animation skip |
| `hooksecurefunc(StaticPopup_Show, …)` | Allowlisted Wildcard confirms only |

See `docs/sketch/ascension-suite-rapid-native-mockup.html`.

## Assists (`AscensionSuiteDB.assists`)

| Key | Default | Job |
|-----|---------|-----|
| `autoRoll` | `false` | Auto-Roll while leveling (1–60) against **current Ascension Desired** only |
| `instantDiceSkip` | `false` | Force-finish `WildCardDice` flipbooks (never starts a roll alone) |
| `instantSkillCardSkip` | `false` | Force-finish SkillCard reveal flipbooks |
| `acceptWildcardPopups` | `false` | Auto-accept `CONFIRM_WILDCARD_*` + `CONFIRM_UNLEARN_S` |
| `captureRolls` | `false` | Append roll results to logbook |

## Layout

```
core/           Bootstrap, Database, Wishlist, Logbook
integration/    AscensionAPI.lua (only C_* home)
automation/     AutoRoller, AnimationSkip, PopupAssist
ui/             SpellCell, MainWindow
scripts/        check.sh, release.sh
tests/          sandbox load + wishlist + assists tests
```

## Install (release zip)

1. Download **AscensionSuite.zip** from [GitHub Releases](https://github.com/Lzra2000/AscensionSuite/releases).
2. Extract so you have `Interface/AddOns/AscensionSuite/AscensionSuite.toc`.
3. Restart the client (or `/reload`) and run `/asuite`.

## Development

```sh
sh scripts/check.sh
sh scripts/build-dist.sh
sh scripts/release.sh 0.2.0
```

Roll starters (`RollAbilities`, `StartRapidRolling`, …) are allowed **only** in `integration/AscensionAPI.lua`; `scripts/check.sh` enforces this.

## License

All Rights Reserved.
