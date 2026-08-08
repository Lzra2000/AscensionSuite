-- AscensionSuite: tests/test_logbook.lua
-- Roll capture is opt-in and resolves talent ranks to the right rank's spell.

unpack = unpack or table.unpack

local function RepoRoot()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    local dir = src:match("^(.*)/")
    if dir and dir:match("/tests$") then
        return dir:gsub("/tests$", "")
    end
    return "."
end

local ROOT = RepoRoot()

AscensionSuite = {}
AscensionSuiteDB = {}

local lastFrame

CreateFrame = function()
    local frame = { _events = {} }
    frame.RegisterEvent = function(self, event) self._events[event] = true end
    frame.SetScript = function(self, script, fn)
        if script == "OnEvent" then
            self._onEvent = fn
        end
    end
    frame.Fire = function(self, event, ...)
        assert(self._events[event], "event not registered: " .. event)
        self._onEvent(self, event, ...)
    end
    lastFrame = frame
    return frame
end

-- Internal ID 7001 is a 5-rank talent; each rank is its own spell.
local TALENT_INTERNAL = 7001
local TALENT_RANK_SPELLS = { [1] = 501, [2] = 502, [3] = 503, [4] = 504, [5] = 505 }
local ABILITY_INTERNAL = 8002
local ABILITY_SPELL = 900

local SPELL_NAMES = {
    [501] = "Fireblast", [502] = "Fireblast", [503] = "Fireblast",
    [504] = "Fireblast", [505] = "Fireblast",
    [900] = "Spartan Kick",
}

local SPELL_ICONS = {
    [503] = "Interface\\Icons\\Rank3_Icon",
    [900] = "Interface\\Icons\\Kick_Icon",
}

function GetSpellInfo(spellId)
    return SPELL_NAMES[spellId], "Rank", SPELL_ICONS[spellId]
end

C_GameMode = {
    IsGameModeActive = function(_, mode) return mode == "WildCard" end,
}

C_CharacterAdvancement = {
    GetEntryByInternalID = function(_, id)
        if id == TALENT_INTERNAL then
            return { ID = TALENT_INTERNAL, Type = "Talent", Name = "Fireblast" }
        elseif id == ABILITY_INTERNAL then
            return { ID = ABILITY_INTERNAL, Type = "Ability", Name = "Spartan Kick", Spell = ABILITY_SPELL }
        end
        return nil
    end,
    -- Deliberately collides: spell-id space reuses the talent's internal ID.
    GetEntryBySpellID = function(_, id)
        if id == TALENT_INTERNAL then
            return { ID = 999999, Type = "Ability", Name = "WRONG ENTRY", Spell = TALENT_INTERNAL }
        end
        return nil
    end,
    GetTalentRankByID = function(_, id)
        if id == TALENT_INTERNAL then
            return 3, 5
        end
        return nil
    end,
    GetKnownSpellEntries = function() return {} end,
    GetKnownTalentEntries = function() return {} end,
}

C_Wildcard = {}

CharacterAdvancementUtil = {
    GetTalentRankSpellByID = function(internalId, rank)
        if internalId == TALENT_INTERNAL then
            return TALENT_RANK_SPELLS[rank]
        end
        return nil
    end,
    GetSpellByID = function(internalId)
        if internalId == ABILITY_INTERNAL then
            return ABILITY_SPELL
        end
        return nil
    end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Logbook.lua")

AscensionSuite.Database.Init()
local API = AscensionSuite.AscensionAPI
local Logbook = AscensionSuite.Logbook
assert(Logbook, "Logbook missing")

-- Internal IDs resolve internal-first, so the colliding spell-id entry loses.
local entry = API.ResolveEntryByInternalID(TALENT_INTERNAL)
assert(entry and entry.Name == "Fireblast",
    "internal id must resolve internal-first, got " .. tostring(entry and entry.Name))

-- Rank 3 of the talent points at rank 3's spell, not rank 1's.
assert(API.GetTalentRankSpellID(TALENT_INTERNAL, 3) == 503, "rank 3 spell id")
assert(API.GetTalentRankSpellID(TALENT_INTERNAL, 1) == 501, "rank 1 spell id")
assert(API.GetTalentRankSpellID(ABILITY_INTERNAL) == ABILITY_SPELL, "ability falls back to GetSpellByID")

local rank, maxRank = API.GetTalentRank(TALENT_INTERNAL)
assert(rank == 3 and maxRank == 5, "talent rank " .. tostring(rank) .. "/" .. tostring(maxRank))

Logbook.Init()

-- Capture defaults off.
assert(AscensionSuiteDB.assists.captureRolls == false, "captureRolls default off")
assert(Logbook.Append(TALENT_INTERNAL, 3) == false, "must not capture while assist is off")
assert(#Logbook.GetEntries() == 0, "logbook stays empty while assist is off")

AscensionSuiteDB.assists.captureRolls = true

-- Talent upgrade to rank 3 records rank 3's spell, icon and rank pair.
assert(Logbook.Append(TALENT_INTERNAL, 3, 2), "talent capture should succeed")
local entries = Logbook.GetEntries()
assert(#entries == 1, "one entry captured, got " .. #entries)

local row = entries[1]
assert(row.entryId == TALENT_INTERNAL, "entry id recorded")
assert(row.spellId == 503, "rank 3 spell recorded, got " .. tostring(row.spellId))
assert(row.icon == SPELL_ICONS[503], "rank 3 icon recorded, got " .. tostring(row.icon))
assert(row.name == "Fireblast", "name recorded")
assert(row.entryType == "talent", "talent type normalized, got " .. tostring(row.entryType))
assert(row.rank == 3 and row.maxRank == 5, "rank pair recorded")

-- Abilities record their own spell and icon.
assert(Logbook.Append(ABILITY_INTERNAL), "ability capture should succeed")
row = Logbook.GetEntries()[2]
assert(row.spellId == ABILITY_SPELL, "ability spell recorded")
assert(row.icon == SPELL_ICONS[ABILITY_SPELL], "ability icon recorded")
assert(row.entryType == "ability", "ability type normalized")

Logbook.Clear()
assert(#Logbook.GetEntries() == 0, "cleared")

-- The real event payloads reach the same path, ranks included.
local frame = lastFrame
assert(frame and frame._onEvent, "Logbook.Init should register an OnEvent handler")

frame:Fire("WILDCARD_RAPID_ROLL_LEARNED", TALENT_INTERNAL, 3, 2, "STOP_RAPID_ROLLING_DESIRED_ENTRY_LEARNED")
frame:Fire("WILDCARD_ENTRY_LEARNED", ABILITY_INTERNAL, 1, 0)

entries = Logbook.GetEntries()
assert(#entries == 2, "both learn events captured, got " .. #entries)
assert(entries[1].spellId == 503, "rapid roll event kept rank 3 spell")
assert(entries[2].spellId == ABILITY_SPELL, "leveling event captured the ability")

Logbook.Clear()

-- Unknown ids are skipped rather than logged as junk.
assert(Logbook.Append(0) == false, "internal id 0 is not a roll result")
assert(Logbook.Append(nil) == false, "nil id is not a roll result")
assert(#Logbook.GetEntries() == 0, "no junk rows")

print("OK: AscensionSuite logbook test passed")
