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
4. **Halt** on `nil` or error API results — never swallow failures in a tight loop.
5. Limit popup accept to an **allowlist** of roll confirmations: `CONFIRM_WILDCARD_MASS_ROLL`, `CONFIRM_WILDCARD_LEVELING`. Accept **button 1 only**.
6. Animation skip may only change Ascension's own **playback speed** and finish an already-playing animation group. It must not call the client's `OnFinished*` handlers itself (they drive the dice state machine and would run transitions twice), and must **never** start a roll by skipping alone.

### Never auto-accepted

Accepting these destroys or unprotects spells rather than confirming a roll, so
they are excluded from the allowlist by design and covered by `tests/test_popups.lua`:

`CONFIRM_UNLEARN_S`, `CONFIRM_UNLEARN_ALL_S`, `UNLOCK_SPELL_CONFIRM`,
`UNLOCK_SPEC_CONFIRM`, `DRAFT_UNLEARN_CONFIRM`, `UNLEARN_SKILL`, `UNLEARN_SKILLID`,
`RECOVER_WILDCARD_ROLL_CONFIRM`.

### Known client limitation

The client exposes no API to count or enumerate Desired **selections** — only
`IsDesiredID(id, type)` per entry, and `GetNumFilteredDesiredEntries()`, which is
the size of the filtered *candidate* list and must never be used as a
"player has targets" gate. Auto-Roll can therefore only verify the entries the
addon itself tracks; Desired marks made directly in the native Rapid window are
invisible to it and are treated as "no targets".

## Data

- SavedVariables: `AscensionSuiteDB` (account). Wishlist profiles and logbook are local only.
- Share import (future) creates a **Build** record only — it must **not** start Auto-Roll.

Report issues responsibly via the repository issue tracker.
