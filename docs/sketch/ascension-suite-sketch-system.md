# Ascension Suite — System & UI Sketch (greenfield)

Scope for v0 (what you listed). No legacy AscensionBuilds assumptions.

## Product pillars

| Pillar | Player-facing job |
|--------|-------------------|
| **Run Logbook** | Every Wildcard / Rapid / Dice / SkillCard run is saved as a dated run with outcomes |
| **Build Save** | Pin a run (or selection) into a named Build that can be reopened |
| **Build Share** | Export / import a short share string (clipboard) for a Build |
| **Live CA Chrome** | Spell icon / id / tooltip **1:1 from Ascension client APIs** — never guess |
| **Auto-Roller** | Opt-in; rolls only player-selected / locked targets |
| **Instant skip** | Dice + SkillCard flipbook / reveal animation skip |
| **Accept popups** | Opt-in auto-accept of Ascension Wildcard confirm dialogs only |
| **Rapid Rolling board** | Lock / unlock / deselect entries on the Rapid board while rolling |

## Hard rails (keep even in greenfield)

- Default **off** for every actuator (Auto-Roll, popup accept, animation skip).
- All `C_Wildcard` / `C_CharacterAdvancement` / `C_SkillCard` calls behind one **AscensionAPI** seam + `C_GameMode` gate.
- Roll starters only via that seam; Draft pick / HoF claim / store purchase stay out of scope.
- Auto-Roll / Rapid loops: visible **Stop**; halt on nil/error API result (release blocker if swallowed).
- No currency budget fiction — Stop + selection exhaustion are the brakes.

## Data model (minimal)

```
Run
  id, startedAt, endedAt, mode (wildcard|rapid|dice|skillcard)
  events[]   -- ordered logbook lines (roll result, lock, unlock, accept, skip…)
  selection[] -- spellIds / entryIds touched this run
  outcomeSummary

Build
  id, name, createdAt, updatedAt
  sourceRunId?          -- optional link to a Run
  lockedEntryIds[]      -- Rapid lock set
  undesiredEntryIds[]   -- explicitly deselected
  desiredEntryIds[]     -- wishlist / prefer
  primaryStat?          -- Hero Path when relevant
  notes

SharePayload
  version, buildName, locked[], undesired[], desired[], primaryStat?
  -- clipboard string; import = create Build (no auto-roll)
```

SavedVariables: `AscensionSuiteDB` (account) + optional char DB for last UI tab only.

## Fetch layer (1:1 display)

```
UI widget  →  SpellPresenter.Resolve(spellId|entryId)
           →  AscensionAPI
                GetEntryBySpellID / GetEntryByInternalID
                icon fields (Icon/icon/texture) then GetSpellInfo
                name / description / tooltip lines from client
           →  paint Texture + FontString + GameTooltip 1:1
```

Never invent names/icons. If client returns empty → show id + neutral placeholder, log once.

## Module map (suggested)

```
core/          Bootstrap, DB, Scheduler, ErrorLog, Debug
integration/   AscensionAPI.lua          -- only C_* home
data/          Builds.lua, Runs.lua, ShareCodec.lua
ui/            MainWindow, LogbookView, BuildListView,
               RapidBoardView, SettingsView, SpellCell (shared)
automation/    AutoRoller.lua, PopupAssist.lua, AnimationSkip.lua
```

## UI map (screens)

1. **Home / Builds** — list Builds; New from last Run; Import share; Open
2. **Logbook** — chronological Runs; open Run detail; “Save as Build”
3. **Rapid Board** — grid of current Rapid candidates; Lock / Unlock / Deselect; Auto-Roll Start/Stop
4. **Settings → Assists** — toggles: Auto-Roll mode, Instant Dice skip, Instant SkillCard skip, Accept Wildcard popups (all default off)
5. **Share sheet** — copy/export string; paste/import

Mockups: `ascension-suite-sketch-ui.html` (same folder).

## Event flow (Auto-Roll + Rapid)

```
Player locks targets on Rapid Board
  → AutoRoller.Start(selectedLockedIds)   -- only if assist enabled
  → AscensionAPI.StartRapidRolling / RollAbilities / Continue…
  → each result → Runs.AppendEvent + refresh SpellCell 1:1
  → Stop if: target done | selection empty | API nil/error | Stop clicked
AnimationSkip: on Dice/SkillCard frames appear → force-finish / hide wait (opt-in)
PopupAssist: allowlisted CONFIRM_WILDCARD_* only (opt-in)
```

## Step-by-step build order (after you approve sketch)

1. Repo + empty addon shell + AscensionAPI seam (read-only spell present)
2. SpellCell 1:1 (icon/id/tooltip) proof screen
3. Logbook + Run capture (observe rolls; no auto-roll yet)
4. Build save from Run + Build list
5. Share export/import
6. Rapid Board lock/deselect UI
7. Animation skip + popup accept (opt-in)
8. Auto-Roller (opt-in, Stop, error halt)
9. Polish / watermarks / i18n

## Out of scope for v0

- Community cohort / “No local sample” recommendation engine
- Preference sync Desired/Undesired curator complexity
- Full CA taxonomy browser with tiers
- Draft / Hall of Fate / store automation
