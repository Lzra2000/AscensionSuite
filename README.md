# AscensionSuite

AscensionSuite is a World of Warcraft addon for the **Ascension / Project Ebonhold** client. It layers **opt-in assists** on top of Ascension’s **native Rapid Rolling UI** (Desired · Roll · Known) — it does **not** rebuild that three-column board.

**v0.2.1** ships: **AscensionAPI** wrappers, **wishlist → Desired sync**, **roll logbook**, and guarded assists (Auto-Roll, animation skip, popup accept) — all default **off**.

> Install **0.2.1 or later**. The v0.2.0 zip was missing the `automation/` directory its TOC loads, so its assists could not load in-game.

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
| `WILDCARD_RAPID_ROLL_LEARNED` / `WILDCARD_ENTRY_LEARNED` | Logbook capture (both carry `internalID, newRank, preRollRank`) |
| `WildCardRapidRollingFrame:Roll` | Auto-Roll drives the native Roll button when the Rapid window is open |
| `AscensionAPI.AdvanceRapidRoll` | Fallback when it is closed (`StartRapidRolling` / `ContinueRapidRolling` / `RollAbilities`) |
| `hooksecurefunc(WildCardDice, …)` | Opt-in dice animation speed-up + icon reel finish |
| `hooksecurefunc(SkillCardUnlockCoverMixin, …)` | Opt-in card reveal speed-up |
| `hooksecurefunc(StaticPopup_Show, …)` | Allowlisted Wildcard roll confirms only |

See `docs/sketch/ascension-suite-rapid-native-mockup.html`.

## Assists (`AscensionSuiteDB.assists`)

| Key | Default | Job |
|-----|---------|-----|
| `autoRoll` | `false` | Auto-Roll while leveling (1–60), only while a tracked wishlist entry is **Desired** |
| `instantDiceSkip` | `false` | Speed up `WildCardDice` flipbooks and finish the icon reel (never starts a roll alone) |
| `instantSkillCardSkip` | `false` | Speed up SkillCard reveal flipbooks |
| `acceptWildcardPopups` | `false` | Auto-accept `CONFIRM_WILDCARD_MASS_ROLL` and `CONFIRM_WILDCARD_LEVELING` only |
| `captureRolls` | `false` | Append roll results to logbook |

Animation skip only changes how fast Ascension's own animations play; the client's
own completion callbacks still run, and the addon restores the native speeds when
you switch the assist back off. Unlearn, unlock and Draft confirmations are never
auto-accepted.

Auto-Roll needs at least one wishlist entry marked Desired. The client offers no
way to count Desired *selections* (only `IsDesiredID` per entry), so entries you
marked directly in Ascension's Rapid window are invisible to the addon — add them
through the overlay if you want Auto-Roll to run.

## Layout

```
core/           Bootstrap, Database, Wishlist, Logbook
integration/    AscensionAPI.lua (only C_* home)
automation/     AutoRoller, AnimationSkip, PopupAssist
ui/             SpellCell, MainWindow
scripts/        check.sh, release.sh
tests/          sandbox load, wishlist, assists, animation skip, popups, logbook
```

## Install (release zip)

1. Download **AscensionSuite.zip** from [GitHub Releases](https://github.com/Lzra2000/AscensionSuite/releases).
2. Extract so you have `Interface/AddOns/AscensionSuite/AscensionSuite.toc`.
3. Restart the client (or `/reload`) and run `/asuite`.

## Development

```sh
sh scripts/check.sh
sh scripts/build-dist.sh
sh scripts/release.sh 0.2.1
```

`build-dist.sh` cross-checks every TOC-listed Lua file against the built archive,
so a payload directory missing from the zip fails the build.

Roll starters (`RollAbilities`, `StartRapidRolling`, …) are allowed **only** in `integration/AscensionAPI.lua`; `scripts/check.sh` enforces this.

## License

All Rights Reserved.
