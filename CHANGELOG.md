# Changelog

All notable changes to AscensionSuite are documented here.

## [0.1.0] — 2026-08-08

### Added

- Greenfield addon shell (`AscensionSuite.toc`, Bootstrap, Database).
- `AscensionAPI` integration seam — read-only entry lookup and 1:1 icon/name/tooltip presentation; roll wrappers stubbed for step 8.
- `SpellCell` shared widget and `MainWindow` proof grid.
- `/asuite` slash command to open the proof window.
- `scripts/check.sh` (Lua compile + `C_*` seam scan), `tests/test_load.lua` smoke test.
- `docs/sketch/` copies of approved system + UI mockup.
- `README.md`, `SECURITY.md`, `.cursorrules`.

### Notes

- All assists default **off** in `AscensionSuiteDB.assists`.
- Auto-Roll / Logbook / Share / Rapid Board are roadmap-only in this release.
