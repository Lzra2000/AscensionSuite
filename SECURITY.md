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

## Opt-in assists (v0.2.1)

Mutating assists default **off** and must:

1. Route **only** through `AscensionAPI`, behind **`C_GameMode` / Wildcard gates**.
2. Target **Ascension Desired** (player-selected) entry sets only — no broad reroll loops. Auto-Roll refuses to start until at least one tracked wishlist entry is verified Desired via `IsDesiredID`, because rolling with nothing Desired is a reroll loop until scrolls run out.
3. Expose a visible **Stop** control while Auto-Roll is running.
4. **Halt** on `nil` or error API results — never swallow failures in a tight loop. Ascension's own Roll button reports failures by showing `RollingFrame.ErrorFrame` and returning nothing, so Auto-Roll also stops when that frame is up, and stops on a rapid session whose phase has not moved for 15s. A refused roll must never be retried on a timer.
5. Limit popup accept to an **allowlist** of roll confirmations: `CONFIRM_WILDCARD_MASS_ROLL`, `CONFIRM_WILDCARD_LEVELING`. Accept **button 1 only**.
6. Animation skip may only change Ascension's own **playback speed** and finish an already-playing animation group. It must not call the client's `OnFinished*` handlers itself (they drive the dice state machine and would run transitions twice), and must **never** start a roll by skipping alone.

### Never auto-accepted

Accepting these destroys or unprotects spells rather than confirming a roll, so
they are excluded from the allowlist by design and covered by `tests/test_popups.lua`:

`CONFIRM_UNLEARN_S`, `CONFIRM_UNLEARN_ALL_S`, `UNLOCK_SPELL_CONFIRM`,
`UNLOCK_SPEC_CONFIRM`, `DRAFT_UNLEARN_CONFIRM`, `UNLEARN_SKILL`, `UNLEARN_SKILLID`,
`RECOVER_WILDCARD_ROLL_CONFIRM`.

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
holds an (id, type) pair for. Since v0.2.1 those pairs are collected from the
native windows too, but the rescan's universe is the Rapid window's **filtered**
candidate list, so a narrowed search box can still hide a selection from it.

## Data

- SavedVariables: `AscensionSuiteDB` (account). Wishlist profiles and logbook are local only.
- Share import (future) creates a **Build** record only — it must **not** start Auto-Roll.

Report issues responsibly via the repository issue tracker.
