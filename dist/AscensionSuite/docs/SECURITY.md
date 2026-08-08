# Security — AscensionSuite automation boundary

AscensionSuite treats **player-initiated** Ascension actions as sacred. The addon may observe client state and, when explicitly enabled, assist with repetitive UI — but it must never silently spend currency, claim rewards, or pick Draft / Hall of Fate / store options on the player's behalf.

## Integration seam

- **`integration/AscensionAPI.lua`** is the **only** first-party file that may reference `C_*` globals (`C_CharacterAdvancement`, `C_Wildcard`, `C_GameMode`, etc.).
- All other modules call `AscensionSuite.AscensionAPI` helpers instead of reaching for the client directly.
- `scripts/check.sh` scans for stray `C_*` usage outside the seam.

## Forbidden automation (always out of scope)

| Area | Rule |
|------|------|
| **Draft** | No auto-pick / auto-learn Draft cards |
| **Hall of Fate** | No auto-claim HoF rewards |
| **Store / merchant** | No auto-purchase or currency spend |
| **Roll starters (v0.1.0)** | `RollAbilities`, `StartRapidRolling`, etc. are **not called** until step 8 |

## Future assists (steps 7–8)

When implemented, mutating assists must:

1. Default **off** in `AscensionSuiteDB.assists` until the player opts in.
2. Route **only** through `AscensionAPI`, behind **`C_GameMode` gates**.
3. Target **player-selected / locked** entry sets only (no broad reroll loops).
4. Expose a visible **Stop** control while running.
5. **Halt** on `nil` or error API results — never swallow failures in a tight loop.
6. Limit popup accept to an **allowlist** of Wildcard confirm dialogs — never Draft/HoF/store prompts.

## Data

- SavedVariables: `AscensionSuiteDB` (account). No credentials or remote endpoints in v0.1.0.
- Share import (future) creates a **Build** record only — it must **not** start Auto-Roll.

Report issues responsibly via the repository issue tracker.
