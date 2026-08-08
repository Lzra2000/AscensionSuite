# AscensionSuite

AscensionSuite is a World of Warcraft addon for the **Ascension / Project Ebonhold** client. It layers **opt-in assists** on top of Ascension’s **native Rapid Rolling UI** (Desired · Roll · Known) — it does **not** rebuild that three-column board.

**v0.2.2** ships: Rapid Rolling **Continue unstick** (dice-skip no longer strands gray Continue), plus **wishlist from native Desired marks**, **roll logbook**, and guarded assists (Auto-Roll, animation skip, popup accept) — all default **off**.

## Marking a wishlist entry

Three ways, all of which end up in the same place — Ascension's Desired set, mirrored into the Suite wishlist so Auto-Roll can verify it:

| Where | How |
|-------|-----|
| **Rapid Rolling → Desired list** | Click a row, exactly as before. The Suite picks the toggle up automatically. |
| **Character Advancement book / browser** | **Alt + right-click** a spell. Click again to un-desire. |
| **`/asuite` overlay** | Type a spell or entry id → **Add**, or click a grid cell to toggle. |

Alt + **right**-click is deliberate: plain Alt-click is Ascension's unlearn and Shift-click is its learn, so neither may change meaning. The padlock, learn and unlearn paths are untouched.

If you marked things Desired before installing the addon — or with the Rapid search box narrowed — press **Sync from Rapid** in the overlay. It rescans the Rapid window's filtered Desired candidate list and keeps whatever the client confirms is selected.

## In-game

```
/asuite
```

Opens the **assist overlay**:

- **Assists** (checkboxes, all default off): Auto-Roll, dice/skillcard animation skip, Wildcard popup accept, logbook capture.
- **Start / Stop** for Auto-Roll (Stop is mandatory while running).
- **Unstick** clears a stranded Rapid session when Continue is stuck gray (die on "?").
- **`Desired: N of M tracked`** — N is what the client confirms Desired right now, M is every entry the addon holds an id/type pair for.
- **Sync from Rapid** — rescan for marks made before the addon was watching.
- **Spell / entry id → Add** resolves icon/name/tooltip 1:1 via `AscensionAPI`, then calls `C_Wildcard.AddDesiredID`.
- **Save / Load** named Desired profiles (+ optional Known snapshot) in `AscensionSuiteDB`.
- **Wishlist grid** — click toggles Ascension Desired; native Rapid board stays authoritative. Two rows are drawn and the rest is counted.
- **Logbook** — recent rolls captured while the capture assist is on.

## Native Rapid Rolling

Ascension’s `WildCardRapidRollingFrame` owns Desired / Roll / Known. Suite hooks:

| Hook | Purpose |
|------|---------|
| `WildCardRapidRollingFrame:SaveDesiredEntry` / `:RemoveDesiredEntry` | Track every Desired toggle made in the native Rapid list |
| `WILDCARD_DESIRED_ENTRIES_CHANGED` | Rescan the filtered Desired candidate list and keep what `IsDesiredID` confirms |
| `CharacterAdvancement:ShowSpellDropDownMenu` | Alt + right-click marks Desired from the book, talent grid and browser |
| `WILDCARD_RAPID_ROLL_LEARNED` / `WILDCARD_ENTRY_LEARNED` | Logbook capture (both carry `internalID, newRank, preRollRank`) |
| `WildCardRapidRollingFrame:Roll` | Auto-Roll drives the native Roll button when the Rapid window is open |
| `AscensionAPI.AdvanceRapidRoll` | Fallback when it is closed (`StartRapidRolling` / `ContinueRapidRolling` / `RollAbilities`) |
| `hooksecurefunc(WildCardDice, …)` | Opt-in dice animation speed-up + icon reel finish |
| `hooksecurefunc(SkillCardUnlockCoverMixin, …)` | Opt-in card reveal speed-up |
| `hooksecurefunc(StaticPopup_Show, …)` | Allowlisted Wildcard roll confirms only |

Every hook is a post-hook. The Rapid mixin is copied onto `WildCardRapidRollingFrame` at
creation (`SharedXML/Util/Mixin.lua`), so the hooks go on the live frame, not on
`WildCardRapidRollingMixin`, which nothing would still be reading.

See `docs/sketch/ascension-suite-rapid-native-mockup.html` and
`docs/sketch/ascension-suite-0.2.1-desired-sync-mockup.html`.

## Assists (`AscensionSuiteDB.assists`)

| Key | Default | Job |
|-----|---------|-----|
| `autoRoll` | `false` | Auto-Roll while leveling (1–60), only while a tracked wishlist entry is **Desired** |
| `instantDiceSkip` | `false` | Speed up `WildCardDice` flipbooks and finish the icon reel (never starts a roll alone) |
| `instantSkillCardSkip` | `false` | Speed up SkillCard reveal flipbooks |
| `acceptWildcardPopups` | `false` | Auto-accept `CONFIRM_WILDCARD_MASS_ROLL` and `CONFIRM_WILDCARD_LEVELING` only |
| `captureRolls` | `false` | Append roll results to logbook |

Animation skip only changes how fast Ascension's own animations play; the client's
own completion callbacks still run, and the addon restores the native speeds when
you switch the assist back off. Unlearn, unlock and Draft confirmations are never
auto-accepted.

Auto-Roll needs at least one tracked entry marked Desired. The client offers no
way to count or list Desired *selections* — only `IsDesiredID` per entry — so the
addon has to learn each id/type pair as it is marked. That is what the sync hooks
above are for; **Sync from Rapid** covers anything they missed.

It stops on its own and tells you why: rolling the Desired entry you asked for,
the Desired set going empty, leaving Wildcard mode, Ascension refusing a roll (its
own error frame, e.g. out of scrolls), or a rapid session whose phase stops moving
for 15s. It never retries a roll the client has already refused, and a Desired hit
ends the run rather than spending the next scroll — press Start again to chase the
next entry on the list.

## Layout

```
core/           Bootstrap, Database, Wishlist, Logbook
integration/    AscensionAPI.lua (only C_* home), DesiredSync.lua
automation/     AutoRoller, AnimationSkip, PopupAssist
ui/             SpellCell, MainWindow
scripts/        check.sh, release.sh
tests/          sandbox load, wishlist, desired sync, assists, animation skip, popups, logbook
```

## Install (release zip)

1. Download **AscensionSuite.zip** from [GitHub Releases](https://github.com/Lzra2000/AscensionSuite/releases).
2. Extract so you have `Interface/AddOns/AscensionSuite/AscensionSuite.toc`.
3. Restart the client (or `/reload`) and run `/asuite`.

## Development

```sh
sh scripts/check.sh
sh scripts/build-dist.sh
sh scripts/release.sh 0.2.1
```

`build-dist.sh` cross-checks every TOC-listed Lua file against the built archive,
so a payload directory missing from the zip fails the build.

Roll starters (`RollAbilities`, `StartRapidRolling`, …) are allowed **only** in `integration/AscensionAPI.lua`; `scripts/check.sh` enforces this.

## License

All Rights Reserved.
