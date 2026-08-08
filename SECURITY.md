# Security — AscensionSuite automation boundary

AscensionSuite treats **player-initiated** Ascension actions as sacred. The addon may observe client state and, when explicitly enabled, assist with repetitive UI — but it must never silently spend currency, claim rewards, or pick Draft / Hall of Fate / store options on the player's behalf.

## Integration seam

- **`integration/AscensionAPI.lua`** is the **only** first-party file that may reference `C_*` globals (`C_CharacterAdvancement`, `C_Wildcard`, `C_GameMode`, etc.).
- All other modules call `AscensionSuite.AscensionAPI` helpers instead of reaching for the client directly.
- `scripts/check.sh` scans for stray `C_*` usage and confines roll starters to the seam.

## Forbidden automation (always out of scope)

| Area | Rule |
|------|------|
| **Draft** | No auto-pick / auto-learn Draft cards |
| **Hall of Fate** | No auto-claim HoF rewards |
| **Store / merchant** | No auto-purchase or currency spend |

## Opt-in assists (v0.2.5)

Mutating assists default **off** and must:

1. Route **only** through `AscensionAPI`, behind **`C_GameMode` / Wildcard gates**.
2. Target **Ascension Desired** (player-selected) entry sets only — no broad reroll loops. Auto-Roll refuses to start until at least one wishlist entry is verified Desired via `IsDesiredID`, because rolling with nothing Desired is a reroll loop until scrolls run out.
3. Expose a visible **Stop** control while Auto-Roll is running.
4. **Halt** on `nil` or error API results — never swallow failures in a tight loop. Ascension's own Roll button reports failures by showing `RollingFrame.ErrorFrame` and returning nothing, so Auto-Roll also stops when that frame is up, and stops on a rapid session whose phase has not moved for 15s. A refused roll must never be retried on a timer.
5. Limit popup accept to an **allowlist** of roll confirmations: `CONFIRM_WILDCARD_MASS_ROLL`, `CONFIRM_WILDCARD_LEVELING`. Accept **button 1 only**.
6. Animation skip may only change Ascension's own **playback speed** and finish an already-playing animation group. It must not call the client's `OnFinished*` handlers itself (they drive the dice state machine and would run transitions twice), and must **never** start a roll by skipping alone.
7. Anything that opens a *second* rapid session without the player pressing a button must be **separately** opt-in and **bounded from more than one direction** — see below.

### Chained sessions (`autoRollContinue`, v0.2.5)

Auto-Roll's default is still to stop the moment a Desired entry lands. The
`autoRollContinue` assist is the only thing in the Suite that will open a rapid
session the player did not ask for one at a time, so it carries its own limits:

1. It ships **off**, and turning `autoRoll` on does not turn it on.
2. Every session is opened and closed through **Ascension's own Roll button**
   (`AdvanceRapidRoll` → `WildCardRapidRollingMixin:Roll`), never by calling a roll
   starter directly. The COMPLETE / Lock / Unlearn buttons a finished session offers
   are still never pressed.
3. It stops when the wishlist has **nothing Desired left** — the ordinary ending.
4. It stops if the **same entry lands twice** (`state.LearnedEntryID`). A client that
   keeps reporting a learned entry as Desired would otherwise reroll it forever.
5. It stops after **25 chained sessions**, whatever else is true.
6. Every stop condition that applies to a single session — native error frame, 15s
   stall, leaving Wildcard, level out of range — applies unchanged to each link.

### Reading Ascension's saved Desired table

`Sync from Rapid` reads `RapidRollDesired`, Ascension_WildCard's own
per-character record of Desired toggles, because the filtered candidate list
cannot show every selection. That read is **bookkeeping only** and is treated as a
hint, never an authority: every `(id, type)` pair it yields is confirmed with
`IsDesiredID` before it counts, the table is never written to, and the scan is
capped at 1000 probes so a corrupt SavedVariable cannot turn one click into an
unbounded run of client calls.

The same sync temporarily clears the Rapid window's Desired **search text** via
Ascension's own `DesiredSearch("")` so the scan can see the whole candidate list.
It restores the player's search immediately afterwards and never writes to the
search box itself, so Ascension's saved filter state is what the player left.

### Never auto-accepted

Accepting these destroys or unprotects spells rather than confirming a roll, so
they are excluded from the allowlist by design and covered by `tests/test_popups.lua`:

`CONFIRM_UNLEARN_S`, `CONFIRM_UNLEARN_ALL_S`, `UNLOCK_SPELL_CONFIRM`,
`UNLOCK_SPEC_CONFIRM`, `DRAFT_UNLEARN_CONFIRM`, `UNLEARN_SKILL`, `UNLEARN_SKILLID`,
`RECOVER_WILDCARD_ROLL_CONFIRM`.

## The wishlist and Ascension Desired are two different things

Since v0.2.3 the wishlist (`AscensionSuiteDB.wishlist`) is a list the player owns
and can edit in any game mode. Ascension **Desired** is a Wildcard-only concept in
the client, and the two are kept deliberately apart:

- Editing the wishlist — adding, removing, clearing, loading a profile — never
  touches Desired outside Wildcard, and says so rather than failing silently.
- **Push to Desired** and Auto-Roll's Start only ever **add**. Neither clears the
  Desired set, and both skip whatever is Desired already, so marks the player made
  by hand in the Rapid window survive.
- Removing a row from the wishlist (`x`) leaves Ascension's Desired mark alone. The
  Suite's store is the Suite's.
- `ClearDesiredSpells` is called from exactly one place: loading a named profile
  with `reapplyDesired`, which is the player explicitly asking for that profile's
  Desired set to replace the current one.

## Marking Desired from Ascension's own UI

`integration/DesiredSync.lua` hooks the client so a mark the player makes in the
native windows reaches the wishlist. It stays inside the same boundary:

1. Every hook is a **post-hook** (`hooksecurefunc`) — the client's own handler
   always runs first and is never replaced.
2. Tracking is **bookkeeping only**. Learning that an entry is Desired writes to
   `AscensionSuiteDB` and takes no game action.
3. The one hook that acts, **Alt + right-click** on a Character Advancement spell
   button, only adds or removes a Desired mark and only when the player holds the
   modifier. It never learns, unlearns, locks or unlocks; `tests/test_desired_sync.lua`
   asserts an unmodified right-click still just opens Ascension's dropdown.
4. Alt + **right**-click specifically, because `CASpellButtonBaseMixin:OnClick`
   already spends plain Alt-click on unlearn and Shift-click on learn. Reusing
   either would change what an existing input does.

### Known client limitation

The client exposes no API to count or enumerate Desired **selections** — only
`IsDesiredID(id, type)` per entry, and `GetNumFilteredDesiredEntries()`, which is
the size of the filtered *candidate* list and must never be used as a
"player has targets" gate. Auto-Roll can therefore only verify entries the addon
holds an (id, type) pair for.

Since v0.2.1 those pairs are collected from the native windows too. Up to v0.2.4
the scan universe was the Rapid window's **filtered** candidate list, so a narrowed
search box hid selections from it; v0.2.5 widens that list for the length of the
scan and adds Ascension's saved Desired table as a second source (see above). Two
gaps remain by design: a Desired mark for an entry that is in neither the candidate
list nor `RapidRollDesired` is still invisible, and the Rapid window's *filter
checkboxes* are left exactly as the player set them — only the search text is
temporarily widened.

## Recovering a stranded session

`RecoverStuckRapidSession` (the **Unstick** button, Auto-Roll's stall path, and
the opt-in **auto-unstick** assist when Auto-Roll is not running)
cancels the session and puts the window back together. It only ever undoes what
Ascension's own `Roll()` did on the way in — re-register `TOKEN_UPDATED`, clear
`pendingReveal`, hide the die, clear the error frame, ask the frame to recompute
its Roll button — and it re-enables that button only when `CanStartRapidRolling`
agrees a roll can start, so a client with its own reason to keep Roll disabled is
never overridden. It raises `completingSession` before the cancel exactly as
Ascension's terminal path does, and Ascension clears that flag itself on the next
Roll. It learns, unlearns and locks nothing.

## Data

- SavedVariables: `AscensionSuiteDB` (account). Wishlist, profiles and logbook are local only.
- Ascension's own SavedVariables (`RapidRollDesired`) are **read** during Sync and never written.
- Share import (future) creates a **Build** record only — it must **not** start Auto-Roll.

Report issues responsibly via the repository issue tracker.
