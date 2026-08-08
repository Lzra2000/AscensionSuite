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

## Opt-in assists (v0.2.0)

Mutating assists default **off** and must:

1. Route **only** through `AscensionAPI`, behind **`C_GameMode` / Wildcard gates**.
2. Target **Ascension Desired** (player-selected) entry sets only — no broad reroll loops.
3. Expose a visible **Stop** control while Auto-Roll is running.
4. **Halt** on `nil` or error API results — never swallow failures in a tight loop.
5. Limit popup accept to an **allowlist**: `CONFIRM_WILDCARD_MASS_ROLL`, `CONFIRM_WILDCARD_LEVELING`, `CONFIRM_UNLEARN_S`.
6. Animation skip may **force-finish / hide** flipbooks only — it must **never** start a roll by skipping alone.

## Data

- SavedVariables: `AscensionSuiteDB` (account). Wishlist profiles and logbook are local only.
- Share import (future) creates a **Build** record only — it must **not** start Auto-Roll.

Report issues responsibly via the repository issue tracker.
