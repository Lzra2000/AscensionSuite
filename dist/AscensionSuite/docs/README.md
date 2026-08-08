# AscensionSuite

AscensionSuite is a greenfield World of Warcraft addon for the **Ascension / Project Ebonhold** client. It helps players **log every Wildcard / Rapid / Dice / SkillCard run**, **save and share builds**, and optionally use **guarded assists** (Auto-Roll, animation skip, Wildcard popup accept) — all with spell **icon / id / tooltip painted 1:1 from client APIs**, never guessed locally.

**v0.1.0** ships the addon shell, the `AscensionAPI` integration seam, and a **SpellCell proof window** only.

## In-game

```
/asuite
```

Opens the proof window: enter a spell id, click **Add**, hover a cell for the client tooltip. **Refresh** repaints icons/names from the API.

## Assists

Every assist defaults **off** in `AscensionSuiteDB.assists`:

| Key | Default | Future job |
|-----|---------|------------|
| `autoRoll` | `false` | Opt-in Auto-Roller (step 8) |
| `instantDiceSkip` | `false` | Dice flipbook skip (step 7) |
| `instantSkillCardSkip` | `false` | SkillCard reveal skip (step 7) |
| `acceptWildcardPopups` | `false` | Allowlisted Wildcard confirms (step 7) |

## Roadmap (from approved sketch)

1. **Repo + shell + AscensionAPI seam** (read-only spell present) — **this release**
2. SpellCell 1:1 proof screen — **this release**
3. Logbook + Run capture (observe rolls; no auto-roll yet)
4. Build save from Run + Build list
5. Share export/import
6. Rapid Board lock/deselect UI
7. Animation skip + popup accept (opt-in)
8. Auto-Roller (opt-in, Stop, error halt)
9. Polish / watermarks / i18n

See `docs/sketch/` for the full system write-up and UI mockup.

## Layout

```
core/           Bootstrap, Database
integration/    AscensionAPI.lua (only C_* home)
ui/             SpellCell, MainWindow
scripts/        check.sh
tests/          sandbox load smoke test
```

## Install (release zip)

1. Download **AscensionSuite.zip** from [GitHub Releases](https://github.com/Lzra2000/AscensionSuite/releases).
2. Extract so you have `Interface/AddOns/AscensionSuite/AscensionSuite.toc`.
3. Restart the client (or `/reload`) and run `/asuite`.

## Development

```sh
sh scripts/check.sh
sh scripts/build-dist.sh          # writes dist/AscensionSuite.zip
sh scripts/release.sh 0.1.0       # tag + GitHub Release with zip (maintainers)
```

Every tagged release **must** ship `AscensionSuite.zip` on the GitHub Release (local `release.sh` and `.github/workflows/release.yml`).

## License

All Rights Reserved.
