-- AscensionSuite: integration/AscensionAPI.lua
-- The only first-party file that may reference C_* globals.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

AscensionSuite.AscensionAPI = {}
local API = AscensionSuite.AscensionAPI

local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local RAPID_CONTINUE_PHASES = {
    AwaitingContinue = true,
}

local RAPID_IN_FLIGHT_PHASES = {
    WaitingForUnlearn = true,
    WaitingForRoll = true,
    WaitingForLearn = true,
    Revealing = true,
}

local RAPID_TERMINAL_PHASES = {
    Completed = true,
    Failed = true,
    Cancelled = true,
}

------------------------------------------------------------------------
-- Namespace helpers
------------------------------------------------------------------------

local function Namespace(globalName)
    local namespace = _G[globalName]
    if type(namespace) == "table" then
        return namespace
    end
    return nil
end

local function CA()
    return Namespace("C_CharacterAdvancement")
end

local function WC()
    return Namespace("C_Wildcard")
end

local function GM()
    return Namespace("C_GameMode")
end

local function Method(namespace, names)
    if not namespace then
        return nil
    end
    for index = 1, #names do
        local fn = namespace[names[index]]
        if type(fn) == "function" then
            return fn, names[index]
        end
    end
    return nil
end

local function Call(namespace, names, ...)
    local fn = Method(namespace, names)
    if not fn then
        return false
    end

    local results = { pcall(fn, namespace, ...) }
    if results[1] then
        return unpack(results, 2)
    end

    local results2 = { pcall(fn, ...) }
    if results2[1] then
        return unpack(results2, 2)
    end

    return false
end

local ENTRY_BY_INTERNAL_ID = { "GetEntryByInternalID", "GetEntryByInternalId", "GetEntry" }
local ENTRY_BY_SPELL_ID = { "GetEntryBySpellID", "GetEntryBySpellId", "GetEntryForSpell" }

local GAME_MODE_GET = { "Get", "GetGameMode", "GetActiveGameMode" }
local GAME_MODE_IS = { "Is", "IsGameMode", "IsActiveGameMode" }

local function TableOrNil(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" then
            return value
        end
    end
    return nil
end

local function FirstString(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

local function FirstTexture(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

local function FirstNumber(...)
    for index = 1, select("#", ...) do
        local value = tonumber(select(index, ...))
        if value then
            return value
        end
    end
    return nil
end

-- Advancement entries carry Spells as a per-rank array (entry.Spells[rank]);
-- Ascension's own list items read Spells[1] as the representative spell, so a
-- lookup that only knows about a scalar Spell field misses most entries.
local function EntrySpellID(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local spellId = FirstNumber(entry.Spell, entry.spell, entry.SpellID, entry.spellID, entry.SpellId)
    if spellId then
        return spellId
    end

    local spells = entry.Spells or entry.spells
    if type(spells) == "table" then
        return FirstNumber(spells[1])
    end
    return nil
end

local function EntryPair(entry)
    if type(entry) ~= "table" then
        return nil, nil
    end
    local entryId = FirstNumber(entry.ID, entry.Id, entry.id, entry.internalID, entry.InternalID)
    local entryType = FirstString(entry.Type, entry.type, entry.entryType, entry.EntryType)
    if not entryId or not entryType then
        return nil, nil
    end
    return entryId, entryType
end

local function RequireWildcard()
    if not API.IsWildcardModeActive() then
        return false, "not_wildcard_mode"
    end
    return true
end

local function RapidRollingFrame()
    return _G.WildCardRapidRollingFrame
end

------------------------------------------------------------------------
-- Availability + GameMode gates
------------------------------------------------------------------------

function API.IsAvailable()
    return CA() ~= nil or WC() ~= nil
end

function API.GetGameMode()
    local gm = GM()
    if not gm then
        return nil
    end
    local value = Call(gm, GAME_MODE_GET)
    if value ~= false and value ~= nil then
        return value
    end
    value = Call(gm, GAME_MODE_IS)
    if value ~= false and value ~= nil then
        return value
    end
    return nil
end

function API.IsGameModeActive(modeName)
    if modeName == nil then
        return false
    end

    local gm = GM()
    if gm then
        if Call(gm, { "IsGameModeActive" }, modeName) == true then
            return true
        end
        if Call(gm, { "IsActiveGameMode" }, modeName) == true then
            return true
        end
    end

    local current = API.GetGameMode()
    if current == nil then
        return false
    end
    if type(current) == "string" then
        return current == modeName
    end
    if type(current) == "number" and type(_G.Enum) == "table" and type(_G.Enum.GameMode) == "table" then
        local enumValue = _G.Enum.GameMode[modeName]
        if enumValue ~= nil then
            return current == enumValue
        end
    end
    return tostring(current) == tostring(modeName)
end

function API.IsWildcardModeActive()
    return API.IsGameModeActive("WildCard") or API.IsGameModeActive("Wildcard")
end

------------------------------------------------------------------------
-- Entry lookup (read-only)
------------------------------------------------------------------------

function API.GetEntryByInternalID(internalId)
    local id = tonumber(internalId)
    if not id then
        return nil
    end
    local ca = CA()
    if not ca then
        return nil
    end
    return TableOrNil(Call(ca, ENTRY_BY_INTERNAL_ID, id))
end

function API.GetEntryBySpellID(spellId)
    local id = tonumber(spellId)
    if not id then
        return nil
    end
    local ca = CA()
    if not ca then
        return nil
    end
    return TableOrNil(Call(ca, ENTRY_BY_SPELL_ID, id))
end

function API.ResolveEntry(spellOrEntryId)
    local id = tonumber(spellOrEntryId)
    if not id then
        return nil
    end

    local entry = API.GetEntryBySpellID(id)
    if entry then
        return entry
    end
    return API.GetEntryByInternalID(id)
end

-- Advancement internal IDs and spell IDs are separate id spaces, so anything
-- that already knows it holds an internal ID (the WILDCARD_*_LEARNED events do)
-- must look that up first or it can land on an unrelated entry whose spell ID
-- happens to collide.
function API.ResolveEntryByInternalID(internalId)
    local id = tonumber(internalId)
    if not id then
        return nil
    end

    local entry = API.GetEntryByInternalID(id)
    if entry then
        return entry
    end
    return API.GetEntryBySpellID(id)
end

function API.GetEntryInternalID(spellOrEntryId)
    local entry = API.ResolveEntry(spellOrEntryId)
    if entry then
        return FirstNumber(entry.ID, entry.Id, entry.id, entry.internalID, entry.InternalID)
    end
    return tonumber(spellOrEntryId)
end

function API.GetEntryType(spellOrEntryId)
    local entry = API.ResolveEntry(spellOrEntryId)
    if not entry then
        return nil
    end
    return FirstString(entry.Type, entry.type, entry.entryType, entry.EntryType)
end

------------------------------------------------------------------------
-- Presentation (dual-read fields, GetSpellInfo fallback)
------------------------------------------------------------------------

function API.GetEntryIcon(spellOrEntryId)
    local entry = API.ResolveEntry(spellOrEntryId)
    if entry then
        local icon = FirstTexture(entry.Icon, entry.icon, entry.texture, entry.Texture, entry.spellIcon)
        if icon then
            return icon
        end
    end

    local id = tonumber(spellOrEntryId)
    if id and GetSpellInfo then
        local _, _, texture = GetSpellInfo(id)
        if texture and texture ~= "" then
            return texture
        end
    end

    return PLACEHOLDER_ICON
end

function API.GetEntryName(spellOrEntryId)
    local entry = API.ResolveEntry(spellOrEntryId)
    if entry then
        local name = FirstString(entry.Name, entry.name, entry.spellName, entry.displayName)
        if name then
            return name
        end
    end

    local id = tonumber(spellOrEntryId)
    if id and GetSpellInfo then
        local name = GetSpellInfo(id)
        if name and name ~= "" then
            return name
        end
    end

    if id then
        return "Spell " .. tostring(id)
    end
    return "Unknown"
end

function API.GetEntrySpellID(spellOrEntryId)
    local spellId = EntrySpellID(API.ResolveEntry(spellOrEntryId))
    if spellId then
        return spellId
    end
    return tonumber(spellOrEntryId)
end

-- Same lookup for a caller that already knows it holds an internal ID. Spell IDs
-- and internal IDs are separate id spaces, so resolving one as the other can land
-- on an unrelated entry whose id happens to collide.
function API.GetEntrySpellIDByInternalID(internalId)
    return EntrySpellID(API.ResolveEntryByInternalID(internalId))
end

function API.GetEntryTooltipLines(spellOrEntryId)
    local lines = {}
    local id = tonumber(spellOrEntryId)
    local entry = API.ResolveEntry(spellOrEntryId)

    if entry then
        local name = FirstString(entry.Name, entry.name, entry.spellName, entry.displayName)
        if name then
            lines[#lines + 1] = name
        end

        local description = FirstString(entry.Description, entry.description, entry.tooltip, entry.Tooltip)
        if description then
            lines[#lines + 1] = description
        end

        local entryType = FirstString(entry.Type, entry.type, entry.entryType, entry.EntryType)
        if entryType then
            lines[#lines + 1] = entryType
        end
    end

    if #lines == 0 and id and GetSpellInfo then
        local name, rank, _, cost, _, _, castTime, minRange, maxRange = GetSpellInfo(id)
        if name then
            lines[#lines + 1] = name
        end
        if rank and rank ~= "" then
            lines[#lines + 1] = rank
        end
        if cost and cost ~= "" then
            lines[#lines + 1] = cost
        end
        if castTime and castTime > 0 then
            local seconds = castTime / 1000
            lines[#lines + 1] = string.format("Cast: %.1f sec", seconds)
        end
        if minRange and maxRange and (minRange > 0 or maxRange > 0) then
            lines[#lines + 1] = string.format("Range: %s yd", tostring(maxRange))
        end
    end

    if id then
        lines[#lines + 1] = "spell=" .. tostring(id)
    end

    if #lines == 0 then
        lines[1] = "No client data"
        if id then
            lines[2] = "spell=" .. tostring(id)
        end
    end

    return lines
end

------------------------------------------------------------------------
-- Desired (player-selected targets only; synced with Ascension Rapid board)
------------------------------------------------------------------------

function API.CanAddDesiredID(entryId, entryType)
    local ok = RequireWildcard()
    if not ok then
        return false
    end
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "CanAddDesiredID" }, entryId, entryType)
end

function API.AddDesiredID(entryId, entryType)
    local ok = RequireWildcard()
    if not ok then
        return false, ok
    end
    local wc = WC()
    if not wc then
        return false, "no_wildcard_api"
    end
    local result = Call(wc, { "AddDesiredID" }, entryId, entryType)
    if result == false then
        return false, "add_failed"
    end
    return true
end

function API.RemoveDesiredID(entryId, entryType)
    local ok = RequireWildcard()
    if not ok then
        return false
    end
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "RemoveDesiredID" }, entryId, entryType)
end

function API.IsDesiredID(entryId, entryType)
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "IsDesiredID" }, entryId, entryType) == true
end

function API.ClearDesiredSpells()
    local ok = RequireWildcard()
    if not ok then
        return false
    end
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "ClearDesiredSpells" })
end

-- Size of the Desired *candidate* list after the Rapid window's search/filter,
-- not the number of entries the player marked Desired. The client exposes no
-- count or enumeration of actual Desired selections, only IsDesiredID per entry,
-- so never use this as a "player has targets" gate. It is still useful as the
-- scan universe for CollectDesiredSelections.
function API.GetNumFilteredDesiredEntries()
    local wc = WC()
    if not wc then
        return 0
    end
    local count = Call(wc, { "GetNumFilteredDesiredEntries" })
    if type(count) == "number" then
        return count
    end
    return 0
end

-- One candidate row of the Rapid window's Desired list, in filter order. This is
-- the same call Ascension's own RapidRollDesiredSpellListItemMixin:GetEntry uses.
function API.GetFilteredDesiredEntryAtIndex(index)
    local position = tonumber(index)
    if not position then
        return nil
    end
    local wc = WC()
    if not wc then
        return nil
    end
    return TableOrNil(Call(wc, { "GetFilteredDesiredEntryAtIndex" }, position))
end

-- Walk the candidate list and keep the rows IsDesiredID confirms are actually
-- selected. This is the closest thing to enumerating Desired selections the
-- client allows, and it only sees what the current Rapid search/filter admits:
-- a narrowed filter hides selections rather than deselecting them.
function API.CollectDesiredSelections(maxScan)
    local selections = {}
    local total = API.GetNumFilteredDesiredEntries()
    if total <= 0 then
        return selections, 0
    end

    local limit = tonumber(maxScan)
    if limit and limit < total then
        total = limit
    end

    for index = 1, total do
        local entry = API.GetFilteredDesiredEntryAtIndex(index)
        local entryId, entryType = EntryPair(entry)
        if entryId and entryType and API.IsDesiredID(entryId, entryType) then
            selections[#selections + 1] = {
                id = entryId,
                type = entryType,
                spellId = EntrySpellID(entry),
                name = FirstString(entry.Name, entry.name),
            }
        end
    end

    return selections, total
end

-- Whether Rapid Rolling is usable at all for the active spec / game mode.
function API.CanUseRapidRolling()
    if not API.IsWildcardModeActive() then
        return false
    end
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "CanUseRapidRolling" }) == true
end

------------------------------------------------------------------------
-- Known probes (read-only)
------------------------------------------------------------------------

function API.IsKnownID(entryId)
    local ca = CA()
    if not ca then
        return false
    end
    return Call(ca, { "IsKnownID" }, entryId) == true
end

function API.GetKnownSpellEntries()
    local ca = CA()
    if not ca then
        return {}
    end
    local entries = Call(ca, { "GetKnownSpellEntries" })
    if type(entries) == "table" then
        return entries
    end
    return {}
end

function API.GetKnownTalentEntries()
    local ca = CA()
    if not ca then
        return {}
    end
    local entries = Call(ca, { "GetKnownTalentEntries" })
    if type(entries) == "table" then
        return entries
    end
    return {}
end

function API.CaptureKnownSnapshot()
    local snapshot = {}
    local spells = API.GetKnownSpellEntries()
    for index = 1, #spells do
        local entry = spells[index]
        if type(entry) == "table" then
            snapshot[#snapshot + 1] = {
                id = FirstNumber(entry.ID, entry.Id, entry.id),
                type = FirstString(entry.Type, entry.type) or "Ability",
                spellId = FirstNumber(entry.Spell, entry.spell, entry.SpellID, entry.spellID),
                name = FirstString(entry.Name, entry.name),
            }
        end
    end
    local talents = API.GetKnownTalentEntries()
    for index = 1, #talents do
        local entry = talents[index]
        if type(entry) == "table" then
            snapshot[#snapshot + 1] = {
                id = FirstNumber(entry.ID, entry.Id, entry.id),
                type = FirstString(entry.Type, entry.type) or "Talent",
                spellId = FirstNumber(entry.Spell, entry.spell, entry.SpellID, entry.spellID),
                name = FirstString(entry.Name, entry.name),
            }
        end
    end
    return snapshot
end

------------------------------------------------------------------------
-- Rolled-entry description (mirrors the native Rapid result display)
------------------------------------------------------------------------

local function CAUtil()
    return Namespace("CharacterAdvancementUtil")
end

-- A talent's icon and name belong to the spell for a specific rank, so a rank-1
-- lookup mislabels an upgraded talent. Ascension's own Rapid Rolling result
-- display resolves it this way (RapidRollingRender.CachePreviousUpgradeResultDisplay).
function API.GetTalentRankSpellID(internalId, rank)
    local id = tonumber(internalId)
    if not id then
        return nil
    end

    local util = CAUtil()
    if util then
        local byRank = Method(util, { "GetTalentRankSpellByID" })
        if byRank and rank then
            local ok, spellId = pcall(byRank, id, rank)
            if ok then
                spellId = tonumber(spellId)
                if spellId and spellId ~= 0 then
                    return spellId
                end
            end
        end

        local bySpell = Method(util, { "GetSpellByID" })
        if bySpell then
            local ok, spellId = pcall(bySpell, id)
            if ok then
                spellId = tonumber(spellId)
                if spellId and spellId ~= 0 then
                    return spellId
                end
            end
        end
    end

    return nil
end

function API.GetTalentRank(internalId)
    local id = tonumber(internalId)
    if not id then
        return nil
    end
    local ca = CA()
    if not ca then
        return nil
    end
    local rank, maxRank = Call(ca, { "GetTalentRankByID" }, id)
    return tonumber(rank), tonumber(maxRank)
end

-- Single description used by the logbook. newRank / preRollRank come straight
-- from WILDCARD_RAPID_ROLL_LEARNED / WILDCARD_ENTRY_LEARNED.
function API.DescribeRolledEntry(internalId, newRank, preRollRank)
    local id = tonumber(internalId)
    if not id or id == 0 then
        return nil
    end

    local entry = API.ResolveEntryByInternalID(id)
    local entryType = nil
    if entry then
        entryType = FirstString(entry.Type, entry.type, entry.entryType, entry.EntryType)
    end

    local rank = tonumber(newRank) or tonumber(preRollRank)
    local currentRank, maxRank = API.GetTalentRank(id)
    rank = rank or currentRank

    local spellId = API.GetTalentRankSpellID(id, rank)
    if not spellId and entry then
        spellId = FirstNumber(entry.Spell, entry.spell, entry.SpellID, entry.spellID, entry.SpellId)
    end

    local name, icon
    if spellId and GetSpellInfo then
        local spellName, _, spellIcon = GetSpellInfo(spellId)
        name = FirstString(spellName)
        icon = FirstTexture(spellIcon)
    end

    if entry then
        name = name or FirstString(entry.Name, entry.name, entry.spellName, entry.displayName)
        icon = icon or FirstTexture(entry.Icon, entry.icon, entry.texture, entry.Texture, entry.spellIcon)
    end

    return {
        entryId = id,
        spellId = spellId,
        name = name or ("Entry " .. tostring(id)),
        icon = icon or PLACEHOLDER_ICON,
        entryType = entryType,
        rank = rank,
        maxRank = maxRank,
    }
end

------------------------------------------------------------------------
-- Roll starters (opt-in assists only; GameMode gated)
------------------------------------------------------------------------

function API.CanRollAbilities()
    local ok = RequireWildcard()
    if not ok then
        return false
    end
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "CanRollAbilities" }) == true
end

function API.RollAbilities()
    local ok = RequireWildcard()
    if not ok then
        return false, ok
    end
    local wc = WC()
    if not wc then
        return false, "no_wildcard_api"
    end
    local result = Call(wc, { "RollAbilities" })
    if result == false then
        return false, "roll_failed"
    end
    return true
end

function API.CanStartRapidRolling()
    local ok = RequireWildcard()
    if not ok then
        return false, ok
    end
    local wc = WC()
    if not wc then
        return false, "no_wildcard_api"
    end
    return Call(wc, { "CanStartRapidRolling" })
end

function API.StartRapidRolling()
    local ok = RequireWildcard()
    if not ok then
        return false, ok
    end
    local wc = WC()
    if not wc then
        return false, "no_wildcard_api"
    end
    local result, reason = Call(wc, { "StartRapidRolling" })
    if result == false then
        return false, reason or "start_failed"
    end
    return true, reason
end

function API.ContinueRapidRolling()
    local ok = RequireWildcard()
    if not ok then
        return false, ok
    end
    local wc = WC()
    if not wc then
        return false, "no_wildcard_api"
    end
    local result, reason = Call(wc, { "ContinueRapidRolling" })
    if result == false then
        return false, reason or "continue_failed"
    end
    return true, reason
end

function API.CancelRapidRolling()
    local ok = RequireWildcard()
    if not ok then
        return false
    end
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "CancelRapidRolling" })
end

function API.GetRapidRollingState()
    local wc = WC()
    if not wc then
        return nil
    end
    local state = Call(wc, { "GetRapidRollingState" })
    if type(state) == "table" then
        return state
    end
    return nil
end

-- Why the current rapid session stopped, e.g.
-- STOP_RAPID_ROLLING_DESIRED_ENTRY_LEARNED or STOP_RAPID_ROLLING_COUNT_DEPLETED.
function API.GetRapidRollingStopCode()
    local state = API.GetRapidRollingState()
    if not state then
        return nil
    end
    return FirstString(state.StopCode)
end

-- The session ended because a Desired entry was rolled: the entry is already
-- learned, the native Roll button now reads COMPLETE, and the only other buttons
-- on offer are Lock and Unlearn, which no assist may press.
function API.IsRapidRollingDesiredHit()
    return API.GetRapidRollingStopCode() == "STOP_RAPID_ROLLING_DESIRED_ENTRY_LEARNED"
end

function API.IsAwaitingRapidRollingTalentUpgradeRoll()
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "IsAwaitingRapidRollingTalentUpgradeRoll" }) == true
end

function API.IsRapidRollingFrameShown()
    local frame = RapidRollingFrame()
    return frame and frame.IsShown and frame:IsShown()
end

-- The native Roll button reports failures by showing RollingFrame.ErrorFrame and
-- returns nothing, so this is the only way a caller can see that a roll was
-- rejected (out of scrolls, unspent talent essence, ...). Ascension hides the
-- frame again for reasons it considers benign, so a shown frame means a real
-- error the player has to resolve.
function API.IsRapidRollingErrorShown()
    local frame = RapidRollingFrame()
    local rolling = frame and frame.RollingFrame
    local errorFrame = rolling and rolling.ErrorFrame
    if type(errorFrame) ~= "table" or type(errorFrame.IsShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(errorFrame.IsShown, errorFrame)
    return ok and shown == true
end

local function IsAwaitingContinue(state)
    return state and RAPID_CONTINUE_PHASES[state.Phase]
end

local function IsInFlight(state)
    return state and RAPID_IN_FLIGHT_PHASES[state.Phase]
end

local function IsTerminal(state)
    return state and RAPID_TERMINAL_PHASES[state.Phase]
end

local function DiceIsShown()
    local dice = _G.WildCardDice
    return dice and dice.IsShown and dice:IsShown()
end

-- Mirrors WildCardRapidRollingMixin:IsRapidRollingDiceActive. A shown die with
-- pendingReveal (or any non-idle Core state) counts as active even when Phase is
-- Idle — that is the stuck-Continue case the assist must not treat as progress.
function API.IsRapidRollingDiceActive(state)
    state = state or API.GetRapidRollingState()
    local dice = _G.WildCardDice
    if type(dice) ~= "table" or type(dice.IsShown) ~= "function" then
        return false
    end
    local shownOk, shown = pcall(dice.IsShown, dice)
    if not shownOk or shown ~= true then
        return false
    end

    local diceCore = dice.Core
    local diceState = nil
    if type(diceCore) == "table" and type(diceCore.GetState) == "function" then
        local ok, value = pcall(diceCore.GetState, diceCore)
        if ok then
            diceState = value
        end
    end
    local idleState = type(diceCore) == "table" and diceCore.State and diceCore.State.IDLE
    if state and state.Phase == "Idle" and diceCore
        and idleState ~= nil and diceState == idleState
        and not dice.pendingReveal then
        return false
    end
    return true
end

-- Same early-out WildCardRapidRollingMixin:Roll uses before it will touch the
-- server: in-flight phases, or a live die that has not yet reached Continue /
-- a terminal result. Calling Roll in that state is a silent no-op that used to
-- look like success to Auto-Roll.
function API.IsRapidRollingAdvanceBlocked(state)
    state = state or API.GetRapidRollingState()
    if IsInFlight(state) then
        return true, "roll_in_flight"
    end
    local awaitingContinue = IsAwaitingContinue(state)
    local terminalResult = IsTerminal(state)
    if API.IsRapidRollingDiceActive(state) and not awaitingContinue and not terminalResult then
        return true, "roll_in_flight"
    end
    return false, nil
end

-- Break out of a stranded Rapid session (gray Continue / die stuck on ?).
-- Cancels the server session, clears local pendingReveal, hides the die, and
-- asks the Rapid window to refresh its Roll button.
function API.RecoverStuckRapidSession()
    local ok, reason = RequireWildcard()
    if not ok then
        return false, reason
    end

    API.CancelRapidRolling()

    local dice = _G.WildCardDice
    if type(dice) == "table" then
        dice.pendingReveal = nil
        if type(dice.Hide) == "function" then
            pcall(dice.Hide, dice)
        end
    end

    local frame = RapidRollingFrame()
    if frame then
        if type(frame.RegisterEvent) == "function" then
            pcall(frame.RegisterEvent, frame, "TOKEN_UPDATED")
        end
        if type(frame.UpdateRollButton) == "function" then
            pcall(frame.UpdateRollButton, frame)
        elseif type(frame.Refresh) == "function" then
            pcall(frame.Refresh, frame)
        end
    end
    return true
end

-- Click-equivalent advance for Rapid Rolling / leveling dice.
-- Never starts a roll from animation skip; caller must invoke this explicitly.
-- Whether the player actually has Desired targets is the caller's policy call
-- (see AutoRoller): the client exposes no way to count selected Desired entries.
function API.AdvanceRapidRoll(skipConfirm)
    local ok, reason = RequireWildcard()
    if not ok then
        return false, reason
    end

    -- The native Roll button already encodes every phase rule, so drive it when
    -- the Rapid window is open instead of re-deriving the sequence. Guard the
    -- silent no-op path first: Roll() returns nothing when blocked, which used
    -- to look like a successful advance.
    local frame = RapidRollingFrame()
    if frame and frame.IsShown and frame:IsShown() and type(frame.Roll) == "function" then
        local blocked, blockReason = API.IsRapidRollingAdvanceBlocked()
        if blocked then
            return false, blockReason or "roll_in_flight"
        end
        local rollOk = pcall(frame.Roll, frame, skipConfirm == true)
        if not rollOk then
            return false, "native_roll_error"
        end
        return true
    end

    local state = API.GetRapidRollingState()
    local awaitingContinue = IsAwaitingContinue(state)
    local terminalResult = IsTerminal(state)
    local diceIsShown = DiceIsShown()

    local blocked, blockReason = API.IsRapidRollingAdvanceBlocked(state)
    if blocked then
        return false, blockReason or "roll_in_flight"
    end

    if terminalResult and not API.IsAwaitingRapidRollingTalentUpgradeRoll() then
        API.CancelRapidRolling()
        if _G.WildCardDice and _G.WildCardDice.Hide then
            _G.WildCardDice:Hide()
        end
        return false, "session_complete"
    end

    if awaitingContinue or API.IsAwaitingRapidRollingTalentUpgradeRoll() then
        if API.IsAwaitingRapidRollingTalentUpgradeRoll() and API.CanRollAbilities() then
            local rollOk, rollReason = API.RollAbilities()
            if not rollOk then
                return false, rollReason or "roll_failed"
            end
            return true
        end
        local contOk, contReason = API.ContinueRapidRolling()
        if not contOk then
            return false, contReason or "continue_failed"
        end
        return true
    end

    -- No Rapid window and no session: this is the plain leveling dice.
    if not API.IsRapidRollingFrameShown() and API.CanRollAbilities() then
        local rollOk, rollReason = API.RollAbilities()
        if not rollOk then
            return false, rollReason or "roll_failed"
        end
        return true
    end

    -- Dice still on screen with no actionable phase: wait, do not Start again.
    if diceIsShown and not awaitingContinue and not terminalResult then
        return false, "roll_in_flight"
    end

    local startOk, startReason = API.StartRapidRolling()
    if not startOk then
        return false, startReason or "start_failed"
    end
    return true
end
