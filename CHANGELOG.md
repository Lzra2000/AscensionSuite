# Changelog

All notable changes to AscensionSuite are documented here.
Each shipped version is a `### <version> (<date>) -- <summary>` block, newest first.

### 0.4.6 (2026-08-09) -- Loadouts polish: Stop, selection memory, scope toggle, Clear Desired

#### Added
- **Stop Auto-Roll** on the Loadouts automate strip (next to Start); refreshes status and
  filtered Desired counts after stopping.
- **Remember last selected loadout** across `/reload` via `AscensionSuiteDB.prefs.loadoutsSelectedId`.
- **Shared ↔ character scope toggle** on the build header (click Scope chip); uses existing
  `character = "shared"` vs player name on Create/meta.
- **Clear Desired (filtered)** — removes Ascension Desired marks for the currently filtered
  Spells list only (Wildcard); status summary; does not delete loadout rows.
- **Empty state** when there are no saved builds — short hint plus **New build** affordance.
- **Tag cycling** on spell rows — Alt+left-click or click the tag label cycles
  Core → Optimal → Empowering → Synergistic → Utility so filters match import intent.

### 0.4.5 (2026-08-09) -- Loadouts polish: remove, duplicate, search, Known badge, ASUITE2

#### Added
- **Remove spell from loadout** — `x` on Spells rows (like Wishlist) via
  `Loadouts.RemoveEntry`; removes from the saved build only (Ascension Desired
  untouched until you toggle or Apply).
- **Duplicate build** — clones the selected loadout (entries, sections, equipment
  stubs, tags, meta, known snapshot) with a distinct `… (copy)` name.
- **Search** on Spells and Talents — filters the visible list by name or id text
  in addition to Core/Optimal/… tag filters.
- **Known badge** on spell rows when the entry appears in the loadout's
  `knownSnapshot` (from Capture Known).
- **ASUITE2** share format — export includes section texts, meta, and equipment
  stubs; import accepts ASUITE2 and legacy ASUITE1 strings.

#### Changed
- Share export defaults to **ASUITE2**; **Copy share** button label replaces
  Copy ASUITE1. Use `ExportString(id, "ASUITE1")` for the legacy format.

### 0.4.4 (2026-08-09) -- Loadouts polish: tooltips, Desired toggle, add-by-id, rename, pros/cons

#### Added
- **Spell row tooltips** on the Loadouts Spells list via `AscensionAPI.ShowEntryTooltip`
  (same safe talent rank handling as Wishlist 0.4.1).
- **Right-click** on a Spells row toggles Desired in Wildcard (mirrors Wishlist); left-click
  selects/highlights the row. Automate strip **Desired: X of N** refreshes live.
- **+ Add Spell** id box — type a spell or advancement entry id and **Add** (resolved via
  AscensionAPI, appended to the selected loadout).
- **Rename** control on the build header wires `Loadouts.Rename` for the selected build.
- **Pros and Cons** section shows colorized `+` / `-` lines (light `FormatProsAndCons`
  reimplementation) above the raw edit box; saving stores unformatted text.

#### Changed
- Spell rows are interactive buttons (hover tooltip, click handlers) instead of static frames.

### 0.4.3 (2026-08-09) -- Loadouts polish: live Desired count, equipment icons, Capture Known

#### Added
- **Automate strip** shows live **Desired: X of N** for the filtered Spells list (refreshes
  after Apply, Sync, Auto-Roll, and tab show) so players see counts instead of a blank
  “nothing Desired” state.
- **Equipment section** renders imported armor/weapon stubs as icon rows (like native
  Archetypes) with optional notes underneath.
- **Capture Known** on the automate strip snapshots Known entries into the selected
  loadout via the existing AscensionAPI path.
- **Category / Complexity** meta chips cycle on click (author stays character name unless
  imported from an archetype).

#### Changed
- **Import Archetype…** prefers editor pending → drafted → active build; clearer status
  when none is available; equipment stubs preserve type keys and tags/class grouping on
  spell import.

### 0.4.2 (2026-08-08) -- Loadouts Apply/Desired + share string + section UI

#### Fixed
- **Apply → Desired** resolves each loadout row spell-first (matching native Rapid
  Rolling) instead of trusting a stale `(entryId, entryType)` cached from import.
  Push now runs from the loadout's Spells list (respecting active tag filters) and
  stops blanket "N refused" when talents were mis-typed as Ability.
- **Start Auto-Roll** on the Loadouts tab runs Apply first (load wishlist + push
  filtered spells to Desired) when a build is selected, so one click works after
  assists are on.
- **ASUITE1** export resolves rows before encoding (`Type:entryId:name`), escapes
  colons in names, scrolls the share box to the start, and imports legacy
  `spellId:name` tokens.
- **Overview / Notes sections** hide the Spells filter bar and + Add Spell chrome;
  notes edit anchors under the section title instead of the hidden filter row.

### 0.4.1 (2026-08-08) -- Tooltip tonumber crash fix

#### Fixed
- **Wishlist tooltip crash** when hovering talents at rank 0: `GetEntryTooltipSpellID`
  no longer passes `GetTalentRank`'s second return value into `tonumber` as an
  invalid radix (`tonumber("0", 1)` on Lua 5.1). Added `TonumberFirst` helper
  and regression test for unlearned talents.
- **ShowEntryTooltip** talent-link fallback uses the same safe rank coercion.

### 0.4.0 (2026-08-08) -- Archetype-style Loadouts + automate strip

#### Added
- **Loadouts tab redesign** mirroring native Ascension BuildCreator / Archetypes
  sections: sidebar nav (Overview → Notes), header chips (author, category,
  complexity), and an always-visible automation strip.
- **Import Archetype…** — reads spells (+ tags) and description sections from
  the editor pending build, drafted build, or active archetype via
  `C_BuildCreator` / `C_BuildEditor` / `C_BuildDraft` in
  `integration/AscensionAPI.lua` only (no Publish / Draft purchase).
- **Spells and Talents** section with Core / Optimal / Empowering / Synergistic
  filters, class grouping, Desired badges, and + Add Spell from the wishlist.
- Local editable notes per non-spell section and equipment stubs on each loadout
  (`AscensionSuiteDB.loadouts` schema v7 migration).
- Loadouts **Start Auto-Roll** respects the Assists toggle (does not force-enable).

#### Changed
- Automation actions (Apply, Auto-Roll, Sync, Wishlist) live on the Loadouts tab
  instead of only on Assists; Assists tab keeps the master toggles.

#### Fixed
- Loadouts panel `InvalidateLayout` re-sizes the new archetype shell widgets after
  tab round-trips (same 0×0 class as 0.3.1).

### 0.3.1 (2026-08-08) -- Loadouts layout fix and auto-unstick assist

#### Added
- **Auto-unstick gray Rapid Continue** — opt-in checkbox on the Assists tab
  (`autoUnstick`, default off). When enabled, detects the same stranded-die /
  gray-Continue state as the manual **Unstick** button and calls
  `RecoverStuckRapidSession` after a short stuck window, with a cooldown so it
  cannot loop forever. Auto-Roll's own stall recovery still owns recovery while a
  run is active.
- `automation/AutoUnstick.lua`, `AscensionAPI.IsRapidRollingContinueStuck`.
- `tests/test_loadouts_panel.lua`, `tests/test_auto_unstick.lua`.

#### Fixed
- **Loadouts tab could stay empty/transparent** when the panel was built while
  its parent tab was hidden (same 0×0 layout class as the Wishlist fix in
  0.2.8). `LoadoutsPanel.InvalidateLayout` now re-sizes list/entry rows and
  detail widgets; `/asuite` ensures and refreshes Loadouts on show when that tab
  is active.

### 0.3.0 (2026-08-08) -- Loadouts tab and Push refuse fixes

#### Added
- **Loadouts tab** (third `/asuite` tab): named builds with Save Build, Load →
  Wishlist, Apply → Desired, Capture Known, and **ASUITE1** share-string
  Copy/Import.
- `core/Loadouts.lua` + `ui/LoadoutsPanel.lua` — bounded `AscensionSuiteDB.loadouts`
  store (name, notes, resolved entries, optional Known snapshot, character meta).
- `tests/test_loadouts.lua` — save/load/apply/import/export and refuse-resolve.

#### Changed
- **Push to Desired** resolves and caches `(entryId, entryType)` on every row
  before calling Ascension, including spell-only wishlist rows, and surfaces
  per-entry refuse reasons in status text.
- Assists tab **Desired profile Save/Load** removed — use Loadouts instead;
  legacy `desiredProfiles` migrate into loadouts on first load (schema v6).

#### Fixed
- Wishlist Push no longer reports blanket “N refused” for rows that only had a
  spell id — pairs are resolved first and failures name the entry + reason.

### 0.2.9 (2026-08-08) -- Wishlist rows show native spell tooltips

#### Added
- **`AscensionAPI.ShowEntryTooltip`** paints the real client spell tooltip on a
  widget via `GameTooltip:SetSpellByID` (or spell hyperlink fallback), matching
  Character Advancement and Rapid Rolling hover behavior.
- **Rank-aware talent tooltips** — `GetEntryTooltipSpellID` resolves the current
  talent rank (or rank 1 when unknown) before fetching.
- Tag / Suggestion advancement entries show name + tag description text instead
  of a spell tooltip (no spell id on those types).
- `tests/test_wishlist_tooltip.lua` — tooltip spell-id resolution and native
  fetch path.

#### Changed
- Wishlist panel row hover uses `ShowEntryTooltip` first; the old
  `GetEntryTooltipLines` text stack remains as fallback when the client cannot
  resolve a spell.

### 0.2.8 (2026-08-08) -- Wishlist panel shows stored rows again

#### Fixed
- **Wishlist tab could stay blank while chat confirmed adds.** The panel was
  built while its parent tab was still hidden, which on 3.3.5a can leave the
  layout at 0×0 until the window is shown. The panel now builds on first open,
  re-anchors when `/asuite` becomes visible, and refreshes after every
  Character Advancement Alt + right-click add — even when the window is closed.
- **Sparse SavedVariables wishlists read as empty.** If `AscensionSuiteDB.wishlist`
  round-tripped with gaps so `#wishlist` was 0, Count/Search reported nothing
  while rows still existed. Count and Search now walk every stored row.
- **FauxScrollFrame chrome could cover the list.** Track/middle/scroll-child
  pieces from the template are hidden and mouse-disabled; only the scrollbar
  strip drives offset math.
- **Chat could claim a wishlist add before the store accepted it.** Toggle now
  checks the Track result and only prints success when the row is actually saved.
- **Describe resolves names/icons from advancement internal ids**, not only spell
  ids, so Wildcard book marks name correctly once CA data is loaded.

#### Added
- Save / Load profile buttons now confirm in chat (row count, or the failure reason).
- `tests/test_wishlist_render.lua` — sparse store + CA add + panel render path.

### 0.2.7 (2026-08-08) -- Wishlist rows click and select again

#### Fixed
- **Wishlist rows could not be clicked.** The faux scroll frame covered the full list
  area and sat above the row buttons in 3.3.5a, swallowing mouse input. The scroll
  frame is now only the scrollbar strip; rows are raised, mouse-enabled, and
  register left/right clicks.
- **Left-click felt broken outside Wildcard.** It used to try toggling Desired and
  only print a status note. Left-click now always selects/highlights the row;
  right-click toggles Desired when Wildcard is active.
- **Wildcard mode was never detected in-game.** `C_GameMode:IsGameModeActive`
  expects `Enum.GameMode` flags, not the string `"WildCard"`, so Push to Desired
  stayed greyed out and Desired counts stayed at 0 even in Wildcard. The API seam
  now resolves enum values and falls back through `GetActiveGameModes` /
  `GetCustomGameMode`.
- **Push to Desired** is clickable whenever the list has entries; it explains in
  status text (and tooltip) when Wildcard is required instead of staying dead grey.

#### Added
- `WishlistPanel.GetSelectedKey`, `tests/test_gamemode_enum.lua`.

### 0.2.6 (2026-08-08) -- WotLK checkboxes actually turn assists on

#### Fixed
- **Assist toggles were a lie on 3.3.5a.** `CheckButton:GetChecked()` returns `1`
  (or nil), not `true`. The Assists tab compared with `== true`, so every click
  wrote `false` into SavedVariables while the box stayed visually checked —
  Auto-Roll looked on, Start stayed dead, and the status line said
  `assist switched off`. Checkboxes now treat `1` and `true` as on.
- Stale **`assist_off`** no longer sticks after you tick Auto-Roll back on.
- Logbook empty copy no longer says "enable capture" when Capture is already on.
- Assists tab hints **Push to Desired** when the wishlist has rows but Desired is
  still 0 (the "25 on wishlist, 0 Desired" case).

#### Added
- `AutoRoller.ClearLastError`, `MainWindow.CheckButtonIsOn`.
- `tests/test_checkbox_wotlk.lua`.

### 0.2.5 (2026-08-08) -- Sync stops missing marks, Auto-Roll stops asking

A polish pass over the three places the Suite quietly did less than it looked
like it was doing: syncing from Rapid only saw what the search box allowed,
Start only pushed the wishlist into an empty Desired set, and scrolling a
wishlist past eight rows raised a Lua error.

#### Fixed
- **Sync from Rapid sees every Desired mark.** The scan universe was the Rapid
  window's *filtered* candidate list, so anything typed in the Desired search box
  hid selections from it -- syncing with `fire` in the box found only the Desired
  marks whose names contain "fire", and reported the rest as "nothing new". The
  scan now widens that list for its own duration through Ascension's own
  `DesiredSearch` funnel and restores the player's search afterwards; the search
  box itself is never written to, so Ascension's saved filter state is untouched.
  It also sweeps `RapidRollDesired`, Ascension's own record of every Desired
  toggle, which finds marks the candidate list cannot show at all. Every pair from
  either source is still confirmed with `IsDesiredID` before it counts. The status
  line says when the search had to be widened.
- **Auto-Roll Start merges the wishlist into Desired.** It used to push only when
  Desired was *completely* empty, so a single mark made by hand in the Rapid
  window was enough for Start to ignore the entire wishlist and report having no
  targets. `PushToDesired` only ever adds -- it never clears and it skips whatever
  is Desired already -- so the push is now unconditional and hand-made marks are
  left exactly as they were.
- **Scrolling a wishlist past eight rows no longer raises.** FrameXML calls a faux
  scroll frame's update function as `updateFunction(self)`, and the panel passed
  `WishlistPanel.Refresh` straight in, so the scroll frame arrived where the status
  note goes and `FontString:SetText` was handed a table.
- **Searching after scrolling shows the matches.** A scroll offset left over from a
  longer list is clamped, instead of rendering eight empty rows over results that
  are right there.
- **Unstick puts the Rapid window back the way it found it.** `Roll()` disables the
  Roll button and unregisters `TOKEN_UPDATED` on its way into a session; recovery
  restored neither, so a session that stranded left the button dead and the scroll
  counters frozen until the window was reopened. It now re-registers the event,
  clears the stale error frame, re-enables the button when the client agrees a roll
  can start, and raises `completingSession` before the cancel exactly as Ascension's
  own terminal path does -- so cancelling no longer surfaces `ROLL_ABILITIES_NO_ROLL`
  as a red error. It confirms in chat, where a player looking at the Rapid window
  will actually see it.
- **A refused Start says so.** Pressing Start when Auto-Roll cannot run left the
  status line reading "idle", which is indistinguishable from the button not having
  been pressed.

#### Added
- **`autoRollContinue`** (default **off**, like every assist): after a Desired entry
  lands, close the session through Ascension's own Roll button and open the next one
  rather than handing control back. It ends when the wishlist has nothing Desired
  left, when the player stops it, on any error -- and on two ceilings that exist so a
  client which keeps calling a learned entry Desired cannot turn this into a reroll
  loop: the same entry landing twice, and 25 chained sessions. Leaving it off keeps
  0.2.1's stop-per-hit behaviour, which is still the default.
- **Row highlight** on the Wishlist panel for whatever was just added, removed or
  toggled -- including from **Alt + right-click** in the Character Advancement book,
  which happens with the Suite window behind it. Nothing is drawn on Ascension's own
  widgets.
- **Push to Desired explains itself** when it is greyed out, on hover.
- The wishlist redraws when `Ascension_CharacterAdvancement` or `Ascension_WildCard`
  loads, so a row added by id while the book was unloaded fills in its name and icon
  rather than sitting on a placeholder until something else happens to refresh it.
- `AscensionAPI.WidenDesiredCandidates`, `CollectSavedRapidSelections`,
  `CollectAllDesiredSelections`, `GetRapidRollingLearnedEntryID`.
- `AutoRoller.GetDesiredHits`, `WishlistPanel.NoteTouched`,
  `WishlistPanel.GetPushBlockReason`.
- `tests/test_sync_filter.lua`, `tests/test_autoroll_continue.lua`. `test_load.lua`
  now fails a release that bumps the TOC, `Bootstrap.VERSION`, the CHANGELOG heading
  and the README out of step with each other.

#### Changed
- Adding an id while the search box is narrowed clears the search, so the row that
  was just added is visible rather than filtered out of its own confirmation.

### 0.2.4 (2026-08-08) -- First-click removal, and the install steps back in the README

#### Fixed
- **Alt + right-click removes on the first click** for a spell that reached the
  wishlist without an advancement pair -- a row added by typing its spell id
  while the Character Advancement book was not loaded. Membership is now matched
  on the spell id as well as the `(entryId, entryType)` pair, so that row is the
  one removed rather than being upserted and needing a second click.
- README: the **Install (release zip)** steps and the licence notice were lost in
  the 0.2.3 rewrite. Both are back.

### 0.2.3 (2026-08-08) -- A real Wishlist panel, editable outside Wildcard

The wishlist stops being a side effect of Ascension's Desired set and becomes a
list the player owns: build it whenever you like, in any game mode, and push it
into Desired when you are in Wildcard and want Auto-Roll to chase it.

#### Fixed
- **Alt + right-click no longer reports an error for a mark that worked.**
  Outside Wildcard it used to print `Desired marks only exist in Wildcard mode.`
  and do nothing. It now adds the spell to the Suite wishlist -- clicking again
  removes it -- and only touches `AddDesiredID` when Wildcard is actually active.
  The line that explains the Desired sync is shown **once per session**, not once
  per spell, so building a list is not a wall of warnings.

#### Added
- **Wishlist panel** (`ui/WishlistPanel.lua`) on a new **Wishlist** tab in
  `/asuite`: search by name or id, a scrollable list of every entry with its
  icon, name, id and a live **Desired** badge, add by spell or entry id, remove
  per row, clear the list, and **Push to Desired** with a status line that says
  what happened. Icon, name and tooltip come from `AscensionAPI` 1:1.
- **Assists tab** keeps everything that was in the old overlay -- toggles,
  Start / Stop / Unstick, Desired profiles, Sync from Rapid, logbook.
- `Wishlist.PushToDesired`, `Search`, `Describe`, `Add`, `Remove`, `Clear`,
  `Contains`, `Count`.
- `tests/test_wishlist_panel.lua`.

#### Changed
- **One wishlist store.** `AscensionSuiteDB.wishlistSpellIds` and
  `wishlistEntries` were two views of the same list, and neither alone could
  describe a row: the spell id draws it, the `(entryId, entryType)` pair is what
  every Desired call needs. They are folded into `AscensionSuiteDB.wishlist`
  (db v5, migrated on load), whose rows carry both and resolve the missing half
  lazily -- so an id the client cannot resolve in one game mode is kept rather
  than dropped, and can resolve later.
- **Auto-Roll Start pushes the wishlist to Desired first** when the Desired set
  is empty, so a list built outside Wildcard works on the first Start. If you
  have already narrowed Desired by hand, that choice is left alone.
- The 8x2 icon grid and its `+N more` counter are gone, replaced by the panel's
  scrollable list. `ui/SpellCell.lua` went with it.

### 0.2.2 (2026-08-08) -- Unstick gray Continue on Rapid Rolling

Hotfix for the hang where Rapid Rolling shows **Continue** grayed out with the
die on "?" and Scrolls Used visible — usually after Instant Dice Skip during a
rapid session.

#### Fixed
- **Animation skip** no longer `Finish()`es the icon reel while
  `WildCardDice.isRapidRolling`. That early finish could leave `pendingReveal`
  set without ever reaching `AwaitingContinue`, so Ascension kept Continue
  disabled. Leveling dice still skip the reel; rapid sessions only get the
  flipbook speed-up.
- **`AdvanceRapidRoll`** mirrors Ascension's own Roll early-out: if the session
  is in-flight or the die is active without Continue/terminal, it returns
  `roll_in_flight` instead of calling `Roll()` and reporting success on a silent
  no-op (which made Auto-Roll look busy while the UI was dead).
- Auto-Roll **stall recovery** calls `RecoverStuckRapidSession` (cancel + clear
  `pendingReveal` + hide die + refresh Roll button) before stopping.
- Overlay **Unstick** button for the same recovery when you hit the hang by hand.

#### Added
- `AscensionAPI.IsRapidRollingDiceActive`, `IsRapidRollingAdvanceBlocked`,
  `RecoverStuckRapidSession`.
- `tests/test_continue_stuck.lua`.

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
