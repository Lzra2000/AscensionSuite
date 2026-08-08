-- AscensionSuite: tests/test_wishlist.lua
-- Desired profile save/load (sandbox, no WoW frames).

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

local desired = {}

C_GameMode = {
    IsGameModeActive = function(_, mode)
        return mode == "WildCard"
    end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        return {
            ID = id + 1000,
            Type = id % 2 == 0 and "Talent" or "Ability",
            Spell = id,
            Name = "Entry " .. tostring(id),
        }
    end,
    GetKnownSpellEntries = function()
        return { { ID = 5001, Type = "Ability", Spell = 133, Name = "Fireball" } }
    end,
    GetKnownTalentEntries = function()
        return {}
    end,
}

C_Wildcard = {
    CanAddDesiredID = function() return true end,
    AddDesiredID = function(_, entryId, entryType)
        desired[entryId] = entryType
        return true
    end,
    RemoveDesiredID = function(_, entryId)
        desired[entryId] = nil
        return true
    end,
    IsDesiredID = function(_, entryId)
        return desired[entryId] ~= nil
    end,
    ClearDesiredSpells = function()
        for key in pairs(desired) do
            desired[key] = nil
        end
        return true
    end,
    GetNumFilteredDesiredEntries = function()
        local count = 0
        for _ in pairs(desired) do
            count = count + 1
        end
        return count
    end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Wishlist.lua")

AscensionSuite.Database.Init()

local Wishlist = AscensionSuite.Wishlist
assert(Wishlist, "Wishlist module missing")

assert(Wishlist.CountDesired() == 0, "nothing desired yet")

assert(Wishlist.AddToDesired(133), "add fireball")
assert(Wishlist.IsDesired(133), "fireball desired")
assert(Wishlist.CountDesired() == 1, "one tracked entry is desired")

-- Tracking an id alone does not mark it Desired in Ascension.
assert(Wishlist.TrackSpellId(1680), "track id")
assert(Wishlist.CountDesired() == 1, "tracking is not desiring")

assert(Wishlist.SaveProfile("test-hero", true), "save profile")
local profile = AscensionSuiteDB.desiredProfiles["test-hero"]
assert(type(profile.entries) == "table" and #profile.entries >= 1, "profile has entries")
assert(type(profile.knownSnapshot) == "table", "known snapshot saved")

local API = AscensionSuite.AscensionAPI
assert(API.ClearDesiredSpells(), "clear desired via seam")
assert(not Wishlist.IsDesired(133), "cleared desired state")

assert(Wishlist.CountDesired() == 0, "clear removes desired state")

assert(Wishlist.LoadProfile("test-hero", true), "load profile")
assert(Wishlist.IsDesired(133), "fireball desired after load")
assert(Wishlist.CountDesired() == 1, "load restores desired state")
assert(#Wishlist.GetSpellIds() >= 1, "spell ids restored")

print("OK: AscensionSuite wishlist test passed")
