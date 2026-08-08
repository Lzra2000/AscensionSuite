# Ascension Suite — System & UI Sketch (greenfield)

Scope for v0. **Native Rapid Rolling is the board**; Suite is overlay assists + wishlist sync + logbook.

## Product pillars

| Pillar | Player-facing job |
|--------|-------------------|
| **Native Rapid board** | Ascension `WildCardRapidRollingFrame` — Desired · Roll · Known (do not clone) |
| **Wishlist → Desired** | Add by id in Suite; sync to `C_Wildcard.AddDesiredID`; Save/Load profiles |
| **Run Logbook** | Capture rolled abilities/talents while leveling (opt-in assist) |
| **Live CA Chrome** | Spell icon / id / tooltip **1:1 from Ascension client APIs** |
| **Auto-Roller** | Opt-in; rolls only current Ascension **Desired** targets |
| **Instant skip** | Dice + SkillCard flipbook force-finish (never starts rolls alone) |
| **Accept popups** | Opt-in auto-accept of allowlisted Wildcard confirm dialogs |

## Hard rails

- Default **off** for every actuator.
- All `C_Wildcard` / `C_CharacterAdvancement` calls behind **AscensionAPI** + GameMode gate.
- Roll starters only in `integration/AscensionAPI.lua`; Draft / HoF / store stay out of scope.
- Auto-Roll: visible **Stop**; halt on nil/error API result.
- No currency budget fiction.

## Data model (v0.2)

```
AscensionSuiteDB
  assists { autoRoll, instantDiceSkip, instantSkillCardSkip, acceptWildcardPopups, captureRolls }
  wishlistSpellIds[]          -- UI grid ids
  desiredProfiles[name] = { entries[], spellIds[], knownSnapshot? }
  logbook[] = { spellId, entryId, name, icon, entryType, timestamp }
```

Ascension Desired/Known state lives in **client APIs** — Suite does not mirror lock columns.

## Module map

```
core/          Bootstrap, Database, Wishlist, Logbook
integration/   AscensionAPI.lua
automation/    AutoRoller, AnimationSkip, PopupAssist
ui/            MainWindow (overlay), SpellCell
```

## Event flow

```
Player adds id in Suite → AscensionAPI.AddDesiredID
Native Rapid board shows Desired / Roll / Known

Auto-Roll (opt-in):
  AutoRoller → AscensionAPI.AdvanceRapidRoll
  → StartRapidRolling | ContinueRapidRolling | RollAbilities
  → Stop on error | user Stop | assist off

Logbook (opt-in captureRolls):
  WILDCARD_RAPID_ROLL_LEARNED / WILDCARD_ENTRY_LEARNED → Logbook.Append

Animation skip: hook WildCardDice flipbooks → HideFlipBooks / OnFinished*
Popup assist: hook StaticPopup_Show → allowlisted CONFIRM_WILDCARD_* only
```

Mockups: `ascension-suite-rapid-native-mockup.html`, `ascension-suite-sketch-ui.html`.

## Out of scope

- Parallel Desired/Known three-column UI
- Draft / Hall of Fate / store automation
- Community recommendation engine
