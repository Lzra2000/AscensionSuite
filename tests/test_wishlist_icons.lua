-- AscensionSuite: tests/test_wishlist_icons.lua
-- Wishlist rows must resolve CA entry icons like native Rapid/CA (short Icon names,
-- spell-id fallback — never GetSpellInfo on an internal entry id).

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

local SPELL_TEXTURES = {
    [42650] = "Interface\\Icons\\Ability_DK_ArmyOfTheDead",
    [8232] = "Interface\\Icons\\Spell_Nature_Cyclone",
    [8024] = "Interface\\Icons\\Spell_Fire_FlameTounge",
}

function GetSpellInfo(spellId)
    local texture = SPELL_TEXTURES[spellId]
    if texture then
        return "Spell " .. tostring(spellId), "Rank 1", texture
    end
    return "Spell " .. tostring(spellId), "Rank 1", "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Internal id 5001 spells Army of the Dead; spell id 5001 is a different entry.
local ENTRIES_BY_INTERNAL = {
    [5001] = {
        ID = 5001,
        Type = "Ability",
        Spells = { 42650 },
        Name = "Army of the Dead",
        Icon = "Ability_DK_ArmyOfTheDead",
    },
    [5002] = {
        ID = 5002,
        Type = "Ability",
        Spells = { 8232 },
        Name = "Windfury Weapon",
        Icon = "Spell_Nature_Cyclone",
    },
    [5003] = {
        ID = 5003,
        Type = "Ability",
        Spells = { 8024 },
        Name = "Flametongue Weapon",
        Icon = "Spell_Fire_FlameTounge",
    },
}

local ENTRIES_BY_SPELL = {
    [5001] = {
        ID = 9001,
        Type = "Ability",
        Spells = { 5001 },
        Name = "Wrong spell collision",
        Icon = "Spell_Shadow_ShadowBolt",
    },
}

C_CharacterAdvancement = {
    GetEntryByInternalID = function(_, id)
        if id == 5010 then
            return {
                ID = 5010,
                Type = "Ability",
                Spells = { 42650 },
                Name = "Army fallback",
            }
        end
        return ENTRIES_BY_INTERNAL[id]
    end,
    GetEntryBySpellID = function(_, spellId)
        return ENTRIES_BY_SPELL[spellId]
    end,
    IsTalentID = function() return false end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")

AscensionSuite.Database.Init()

local API = AscensionSuite.AscensionAPI
local Wishlist = AscensionSuite.Wishlist

local expectedArmy = "Interface\\Icons\\Ability_DK_ArmyOfTheDead"
local expectedWindfury = "Interface\\Icons\\Spell_Nature_Cyclone"
local expectedFlame = "Interface\\Icons\\Spell_Fire_FlameTounge"

assert(API.GetEntryIcon(5001, 5001) == expectedArmy,
    "internal id uses entry.Icon with Icons prefix, got " .. tostring(API.GetEntryIcon(5001, 5001)))
assert(API.GetEntryIcon(42650) == expectedArmy,
    "spell id resolves GetSpellInfo texture")

assert(API.GetEntryIcon(5010, 5010) == expectedArmy,
    "missing entry.Icon falls back to spell texture, got " .. tostring(API.GetEntryIcon(5010, 5010)))

Wishlist.AddEntry(5001, "Ability", 42650, "Army of the Dead")
Wishlist.AddEntry(5002, "Ability", 8232, "Windfury Weapon")
Wishlist.AddEntry(5003, "Ability", 8024, "Flametongue Weapon")

local rows = Wishlist.Search(nil)
assert(#rows == 3, "three wishlist rows")

for index = 1, #rows do
    local row = rows[index]
    assert(row.icon and row.icon:find("Interface\\Icons\\", 1, true),
        row.name .. " icon is not a full texture path: " .. tostring(row.icon))
end

assert(rows[1].icon == expectedArmy, "Army of the Dead icon")
assert(rows[2].icon == expectedWindfury, "Windfury Weapon icon")
assert(rows[3].icon == expectedFlame, "Flametongue Weapon icon")

print("OK: AscensionSuite wishlist icon resolution test passed")
