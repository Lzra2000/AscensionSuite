# Changelog

All notable changes to AscensionSuite are documented here.
Each shipped version is a `### <version> (<date>) -- <summary>` block, newest first.

### 0.2.1 (2026-08-08) -- Assists that actually load and behave

v0.2.0's release zip omitted the whole `automation/` directory that its own TOC
loads, so Auto-Roll, animation skip and popup accept could not load in-game.
This is the first build where the 0.2 assists work. Install this instead of 0.2.0.

#### Fixed
- **Release zip** now contains `automation/`, and `build-dist.sh` fails the build
  if any TOC-listed Lua file is missing from the archive.
- **Animation skip** no longer calls the dice `OnFinished*` handlers while a
  flipbook is still playing. Those handlers drive the dice state machine, so
  each skip ran a transition twice and could consume `pendingReveal` early and
  leave the dice stranded. Skip now raises the playback speed of Ascension's own
  flipbooks and finishes the icon reel's `AnimationGroup`, letting the client's
  completion callbacks fire once. Native speeds are restored when switched off.
- **SkillCard skip** hooked `SkillCardUnlockCoverMixin.PlayReveal`, which does not
  exist on this client — the reveal runs through `OnMouseUp`. Card skipping was
  dead code and now works.
- **Popup accept** no longer allowlists `CONFIRM_UNLEARN_S`: accepting it unlearns
  a spell rather than confirming a roll. Only the two Wildcard roll confirmations
  remain, and it clicks the plain accept button rather than
  "start and don't ask again", which rewrote Ascension's own preference.
- **Auto-Roll target gate** used `GetNumFilteredDesiredEntries()` as a stand-in for
  "the player has Desired targets". That is the size of the Desired *candidate*
  list after the Rapid window's search/filter, so it allowed rolling with nothing
  desired and blocked rolling while a search was typed in. Auto-Roll now verifies
  Desired state per entry over the wishlist it tracks.
- **Leveling dice** could never be advanced: two contradictory gates left the
  `RollAbilities` branch unreachable.
- **Rolled talents** were logged with rank 1's spell, so an upgraded talent showed
  the wrong icon and name. The logbook now resolves the spell for the rolled rank
  and records `rank`/`maxRank`.
- **Internal IDs** were resolved spell-ID-first, which could label a roll with an
  unrelated entry on an id collision.
- **Desired profiles** recorded every tracked wishlist entry, so loading a profile
  desired spells the player had only added to the grid to watch.
- `check.sh` no longer fails on its own `dist/` output, and discovers
  `tests/test_*.lua` instead of listing each test.

#### Added
- `AscensionAPI`: `ResolveEntryByInternalID`, `GetTalentRankSpellID`,
  `GetTalentRank`, `DescribeRolledEntry`, `CanUseRapidRolling`.
- `Wishlist.CountDesired()`.
- Tests: `test_animation_skip.lua`, `test_popups.lua`, `test_logbook.lua`.
- Readable Auto-Roll stop reasons in the overlay.

#### Notes
- The client exposes no way to count or enumerate Desired *selections* (only
  `IsDesiredID` per entry), so Auto-Roll can only verify targets the addon
  tracks. Entries marked Desired directly in the native Rapid window are not
  visible to it — add them through the overlay to use Auto-Roll.

### 0.2.0 (2026-08-08) -- Native Rapid assists, wishlist Desired sync, logbook

> Superseded by 0.2.1: this release's zip is missing `automation/` and cannot
> load the assists it advertises.

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
