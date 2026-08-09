-- AscensionSuite: tests/test_can_add_refuse.lua
-- DescribeCanAddRefuse surfaces real Push refusal reasons.

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

Enum = {
    GameMode = {
        WildCard = 0x40,
    },
}

function GetCustomGameMode()
    return 0x40
end

bit = {
    band = function(a, b)
        local result = 0
        local bitval = 1
        while a > 0 or b > 0 do
            if (a % 2 == 1) and (b % 2 == 1) then
                result = result + bitval
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bitval = bitval * 2
        end
        return result
    end,
    contains = function(mask, flag)
        return bit.band(mask, flag) == flag
    end,
}

local known = {}
local desired = {}
local canAdd = {}
local desiredList = {}
local wildcardActive = true

C_GameMode = {
    IsGameModeActive = function(_, mode)
        if not wildcardActive then
            return false
        end
        return mode == Enum.GameMode.WildCard
    end,
}

C_CharacterAdvancement = {
    GetEntryByInternalID = function(_, id)
        if id == 1133 then
            return { ID = 1133, Type = "Ability", Spells = { 133 } }
        end
        if id == 1116 then
            return { ID = 1116, Type = "Talent", Spells = { 116 } }
        end
        if id == 9999 then
            return { ID = 9999, Type = "Ability", Spells = { 9999 } }
        end
        return nil
    end,
    GetEntryBySpellID = function(_, spellId)
        if spellId == 133 then
            return { ID = 1133, Type = "Ability", Spells = { 133 } }
        end
        return nil
    end,
    IsKnownID = function(_, id)
        return known[id] == true
    end,
}

C_Wildcard = {
    CanAddDesiredID = function(_, entryId, entryType)
        return canAdd[entryType .. ":" .. tostring(entryId)] == true
    end,
    IsDesiredID = function(_, entryId, entryType)
        return desired[entryType .. ":" .. tostring(entryId)] == true
    end,
    GetNumFilteredDesiredEntries = function()
        return #desiredList
    end,
    GetFilteredDesiredEntryAtIndex = function(_, index)
        return desiredList[index]
    end,
    GetMaxDesiredCount = function()
        return 6
    end,
}

dofile(ROOT .. "/integration/AscensionAPI.lua")

local API = AscensionSuite.AscensionAPI
assert(API, "AscensionAPI missing")

canAdd["Ability:1133"] = true
assert(API.DescribeCanAddRefuse(1133, "Ability") == nil, "eligible Ability can add")

known[1133] = true
assert(API.DescribeCanAddRefuse(1133, "Ability") == "already_known", "known entry refused")
known[1133] = nil

assert(API.DescribeCanAddRefuse(1133, "Talent") == "bad_pair", "wrong type is bad_pair")
assert(API.DescribeCanAddRefuse(1133, "Tag") == "tag_not_desired", "Tag refused")

desired["Ability:1133"] = true
assert(API.DescribeCanAddRefuse(1133, "Ability") == "already_desired", "already Desired")
desired["Ability:1133"] = nil

for index = 1, 6 do
    local id = 2000 + index
    desired["Ability:" .. tostring(id)] = true
    desiredList[#desiredList + 1] = { ID = id, Type = "Ability", Spells = { id } }
end
canAdd["Ability:1133"] = false
assert(API.DescribeCanAddRefuse(1133, "Ability") == "desired_cap", "cap reached")
desired = {}
desiredList = {}
canAdd["Ability:1133"] = true

GetCustomGameMode = function()
    if not wildcardActive then
        return 0x00
    end
    return 0x40
end
wildcardActive = false
assert(API.DescribeCanAddRefuse(1133, "Ability") == "not_wildcard_mode", "outside Wildcard")

print("OK: AscensionSuite can_add refuse test passed")
