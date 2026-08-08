# Changelog

All notable changes to AscensionSuite are documented here.
Each shipped version is a `### <version> (<date>) -- <summary>` block, newest first.

### 0.2.0 (2026-08-08) -- Native Rapid assists, wishlist Desired sync, logbook

Assists ride on Ascension's own Rapid Rolling rather than rebuilding it: the Suite
drives the native Roll button, speeds up the client's own animations, and syncs its
wishlist into native Desired. All assists ship **off**.

#### Added
- **AscensionAPI** live wrappers, GameMode-gated and confined to the seam: Desired
  add/remove/is/clear, Known probes, `RollAbilities` / `StartRapidRolling` /
  `ContinueRapidRolling` / `CancelRapidRolling`, and `AdvanceRapidRoll`, which
  delegates to `WildCardRapidRollingMixin:Roll` whenever the Rapid window is open
  instead of re-deriving the phase sequence.
- **Wishlist** (`core/Wishlist.lua`): add by spell/entry id → client chrome 1:1 →
  `AddDesiredID`; Save/Load named Desired profiles (+ optional Known snapshot).
  Profiles record only entries that are actually Desired, so loading one does not
  desire spells that were merely being watched in the grid.
- **Logbook** (`core/Logbook.lua`): captures rolls on `WILDCARD_RAPID_ROLL_LEARNED`
  / `WILDCARD_ENTRY_LEARNED`, resolving each rolled talent to the spell for the
  rank that was rolled and recording `rank`/`maxRank`.
- **Assists** (all default off): Auto-Roll with a visible Stop; dice / SkillCard
  animation skip; allowlisted Wildcard popup accept.
- Thin `/asuite` overlay — toggles, wishlist grid, profiles, logbook, and readable
  Auto-Roll stop reasons. No parallel Rapid board.
- `automation/` modules: `AutoRoller`, `AnimationSkip`, `PopupAssist`.
- Tests: `test_wishlist.lua`, `test_assists.lua`, `test_animation_skip.lua`,
  `test_popups.lua`, `test_logbook.lua`. `check.sh` keeps `C_*` and roll starters
  inside `AscensionAPI.lua` and discovers `tests/test_*.lua` itself;
  `build-dist.sh` fails if a TOC-listed file is missing from the zip.
- `docs/sketch/ascension-suite-rapid-native-mockup.html`.

#### Changed
- Product direction: native Rapid Rolling is the board; the Suite is overlay
  assists + wishlist sync + logbook.
- Replaced the v0.2 marks cycle (`Marks.lua`) with Ascension Desired sync.

#### Assist behaviour worth knowing
- **Animation skip** raises the playback speed of Ascension's own flipbooks and
  finishes the icon reel's `AnimationGroup`. It never calls the dice `OnFinished*`
  handlers itself — those drive the dice state machine, and invoking one mid-flight
  runs the transition twice. Native speeds are restored when it is switched off.
- **Popup accept** covers only `CONFIRM_WILDCARD_MASS_ROLL` and
  `CONFIRM_WILDCARD_LEVELING`, and clicks the plain accept button rather than
  "start and don't ask again", which would rewrite Ascension's own preference.
  Unlearn, unlock and Draft dialogs are never accepted.
- **Auto-Roll** stops on anything it cannot resolve: the client refusing a roll
  (Ascension's error frame), a rapid session whose phase stops moving, the Desired
  set going empty, or leaving Wildcard mode. It never runs without a verified
  Desired target, since rolling with none is just a reroll loop until scrolls
  run out.

#### Notes
- Draft / Hall of Fame / store automation remain out of scope.
- The client exposes no way to count or enumerate Desired *selections* (only
  `IsDesiredID` per entry), so Auto-Roll can only verify targets the addon
  tracks. Entries marked Desired directly in the native Rapid window are not
  visible to it — add them through the overlay to use Auto-Roll.
- `GetNumFilteredDesiredEntries()` is the size of the Desired *candidate* list
  after the Rapid window's search/filter, not a count of selections. It is not a
  "player has targets" gate.
- The v0.2.0 asset first uploaded on release day omitted `automation/` and could
  not load its own assists; it was replaced with the build described here.

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
