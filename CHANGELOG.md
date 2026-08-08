# Changelog

All notable changes to AscensionSuite are documented here.
Each shipped version is a `### <version> (<date>) -- <summary>` block, newest first.

### 0.2.0 (2026-08-08) -- Native Rapid assists, wishlist Desired sync, logbook

#### Added
- **AscensionAPI** live wrappers (GameMode-gated): Desired add/remove/is/clear, Known probes, `RollAbilities` / `StartRapidRolling` / `ContinueRapidRolling` / `CancelRapidRolling`, `AdvanceRapidRoll`.
- **Wishlist** (`core/Wishlist.lua`): add by spell/entry id → client chrome 1:1 → `AddDesiredID`; Save/Load named Desired profiles (+ optional Known snapshot).
- **Logbook** (`core/Logbook.lua`): capture rolls on `WILDCARD_RAPID_ROLL_LEARNED` / `WILDCARD_ENTRY_LEARNED` when assist enabled.
- **Assists** (all default off): Auto-Roll with visible Stop + error halt; dice/skillcard animation skip; allowlisted Wildcard popup accept.
- Thin `/asuite` overlay — toggles, wishlist grid, profiles, logbook (no parallel Rapid UI).
- `automation/` modules: `AutoRoller`, `AnimationSkip`, `PopupAssist`.
- Tests: `test_wishlist.lua`, `test_assists.lua`; `check.sh` allows roll starters only in `AscensionAPI.lua`.
- `docs/sketch/ascension-suite-rapid-native-mockup.html`.

#### Changed
- Product direction: native Rapid Rolling is the board; Suite is overlay assists + wishlist sync + logbook.
- Replaced v0.2 marks cycle (`Marks.lua`) with Ascension Desired sync.

#### Notes
- Draft / HoF / store automation remain out of scope.
- Auto-Roll targets **player-selected Ascension Desired** only; no currency cap fiction.

### 0.1.0 (2026-08-08) -- Shell, AscensionAPI seam, SpellCell proof

#### Added
- Greenfield addon shell (`AscensionSuite.toc`, Bootstrap, Database).
- `AscensionAPI` integration seam — read-only entry lookup and 1:1 icon/name/tooltip presentation.
- `SpellCell` shared widget and `MainWindow` proof grid.
- `/asuite` slash command.
- `scripts/check.sh`, `scripts/build-dist.sh` + `scripts/release.sh`.
- `docs/sketch/` system + UI mockups.

#### Notes
- All assists default **off** in `AscensionSuiteDB.assists`.
