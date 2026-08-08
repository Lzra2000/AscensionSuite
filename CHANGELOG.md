# Changelog

All notable changes to AscensionSuite are documented here.
Each shipped version is a `### <version> (<date>) -- <summary>` block, newest first.

### 0.2.1 (2026-08-08) -- Build the wishlist where you already mark Desired

Marking Desired in Ascension's own windows now builds the Suite wishlist, which
closes the v0.2.0 limitation where Auto-Roll could only see targets added through
the overlay. Nothing about the native board changed and no assist was switched on.

#### Added
- **Desired sync** (`integration/DesiredSync.lua`) tracks every Desired mark from
  three sources: `WildCardRapidRollingFrame:SaveDesiredEntry` /
  `:RemoveDesiredEntry` (the funnel every toggle in the native Rapid list goes
  through, bulk "desire all build spells" included), a rescan of the filtered
  Desired candidate list on `WILDCARD_DESIRED_ENTRIES_CHANGED`, and
  **Alt + right-click** on a Character Advancement spell button.
- **Alt + right-click marks Desired** anywhere `CASpellButtonBaseMixin` is used —
  the book grid, the talent grid, compact buttons and the browser list all route
  right-click through `CharacterAdvancement:ShowSpellDropDownMenu`. Alt + right
  is the only free modifier there: plain Alt-click is Ascension's unlearn and
  Shift-click is its learn. Clicking again un-desires; the padlock, learn and
  unlearn paths are untouched.
- **Tracked entry registry** in `AscensionSuiteDB.wishlistEntries` — (id, type)
  pairs, which is what `IsDesiredID` needs and what a spell id alone cannot always
  give. Bounded at 300 entries, pruned when a mark is removed.
- Overlay: a **`Desired: N of M tracked`** line, a **Sync from Rapid** button for
  marks made before the addon was watching, and a `+N more` counter now that the
  grid can fill from the native windows faster than by typing ids.
- `AscensionAPI.CollectDesiredSelections`, `GetFilteredDesiredEntryAtIndex`,
  `GetRapidRollingStopCode`, `IsRapidRollingDesiredHit`.
- `tests/test_desired_sync.lua`.

#### Fixed
- **Auto-Roll sees native Desired marks.** `Wishlist.CountDesired` now counts the
  tracked registry as well as the grid, and `AutoRoller.Start` runs a sync first,
  so pressing Start no longer reports "no Desired targets" while the Rapid window
  visibly has some.
- `GetEntrySpellID` reads `entry.Spells[1]`. Advancement entries carry spells as a
  per-rank array, so entries without a scalar `Spell` field previously resolved to
  no icon and no grid cell.
- Auto-Roll **stops when a Desired entry lands** instead of starting a fresh
  session. The rolled entry is already learned and the session's own buttons are
  now COMPLETE / Lock / Unlearn, none of which an assist may press; it closes the
  session out through Ascension's Roll button and reports `desired_learned`.

#### Notes
- The rescan's universe is the Rapid window's **filtered** candidate list, so a
  search box narrowed to one word hides other selections from it. Clear the search
  before using Sync from Rapid if a mark seems to be missing.
- Un-desiring an entry drops it from the tracked registry but leaves its cell in
  the grid, so a cell toggled off is still there to toggle back on.

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
