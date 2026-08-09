-- AscensionSuite: tests/test_desired_skip_tags.lua
-- Tag / Suggestion rows must not block Push to Desired or Auto-Roll.

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

local wildcard = true

local ENTRIES = {
    [2] = { ID = 2, Type = "Tag", Name = "Word of Mass Recall (OLD)" },
    [3] = { ID = 3, Type = "Tag", Name = "Root Master" },
    [1133] = { ID = 1133, Type = "Ability", Spell = 133, Name = "Fireball" },
    [1116] = { ID = 1116, Type = "Talent", Spell = 116, Name = "Ice Block" },
}

local BY_SPELL = {
    [133] = ENTRIES[1133],
    [116] = ENTRIES[1116],
}

local desired = {}

local function Key(entryId, entryType)
    return tostring(entryId) .. "/" .. tostring(entryType)
end

C_GameMode = {
    IsGameModeActive = function(_, mode)
        return wildcard and mode == "WildCard"
    end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id) return BY_SPELL[id] end,
    GetEntryByInternalID = function(_, id) return ENTRIES[id] end,
    GetKnownSpellEntries = function() return {} end,
    GetKnownTalentEntries = function() return {} end,
}

C_Wildcard = {
    CanAddDesiredID = function(_, entryId, entryType)
        return entryType == "Ability" or entryType == "Talent"
    end,
    AddDesiredID = function(_, entryId, entryType)
        desired[Key(entryId, entryType)] = true
        return true
    end,
    RemoveDesiredID = function(_, entryId, entryType)
        desired[Key(entryId, entryType)] = nil
        return true
    end,
    IsDesiredID = function(_, entryId, entryType)
        return desired[Key(entryId, entryType)] == true
    end,
    ClearDesiredSpells = function()
        for key in pairs(desired) do
            desired[key] = nil
        end
        return true
    end,
    GetNumFilteredDesiredEntries = function() return 0 end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/core/Loadouts.lua")

AscensionSuite.Database.Init()

local API = AscensionSuite.AscensionAPI
local Wishlist = AscensionSuite.Wishlist
local Loadouts = AscensionSuite.Loadouts

assert(API.IsMetaEntryType("Tag"), "Tag is meta")
assert(API.IsDesiredEligibleType("Ability"), "Ability is eligible")
assert(not API.IsDesiredEligibleType("Tag"), "Tag is not eligible")

local ok, reason = Wishlist.AddEntry(2, "Tag", nil, "Word of Mass Recall (OLD)")
assert(not ok and reason == "meta_entry", "AddEntry rejects Tag rows")

Wishlist.AddEntry(1133, "Ability", 133, "Fireball")
Wishlist.AddEntry(1116, "Talent", 116, "Ice Block")

local loadout, id = Loadouts.Create("Tag pollution", "", false)
loadout.entries = {
    { entryId = 2, entryType = "Tag", name = "Word of Mass Recall (OLD)" },
    { entryId = 3, entryType = "Tag", name = "Root Master" },
    { entryId = 1133, entryType = "Ability", spellId = 133, name = "Fireball" },
}

local loadedOk, loadedCount, loadSkipped = Loadouts.LoadToWishlist(id)
assert(loadedOk and loadedCount == 1, "LoadToWishlist keeps only Ability/Talent (got " .. tostring(loadedCount) .. ")")
assert(loadSkipped == 2, "LoadToWishlist reports skipped tags (got " .. tostring(loadSkipped) .. ")")

Wishlist.Clear()
local items = Wishlist.GetItems()
items[#items + 1] = { entryId = 2, entryType = "Tag", name = "Word of Mass Recall (OLD)" }
items[#items + 1] = { entryId = 3, entryType = "Tag", name = "Root Master" }
Wishlist.AddEntry(1133, "Ability", 133, "Fireball")

local pushed, already, failed, gate, refuses, skipped = Wishlist.PushToDesired()
assert(skipped == 2, "Push skips Tag rows (got " .. tostring(skipped) .. ")")
assert(pushed == 1, "Push marks the Ability (got " .. tostring(pushed) .. ")")
assert(failed == 0, "Tags are not counted as refused (got " .. tostring(failed) .. ")")

local summary = Wishlist.GetDesiredEligibilitySummary()
assert(summary.meta == 2 and summary.eligible == 1, "eligibility summary counts meta vs eligible")

local removed = Wishlist.RemoveIneligibleEntries()
assert(removed == 2, "cleanup removes Tag rows (got " .. tostring(removed) .. ")")
assert(Wishlist.Count() == 1, "one Ability row remains")

local imported, importId = Loadouts.ImportString(
    "ASUITE2|tag build|3|Tag:2:Word of Mass Recall (OLD);Tag:3:Root Master;Ability:1133:Fireball|||||",
    true)
assert(imported and #imported.entries == 1, "ASUITE2 import drops Tag tokens")
assert(imported.entries[1].entryType == "Ability", "only Ability kept from share string")

local note = Loadouts.FormatPushSummary(0, 0, 1, 5, {
    { name = "Mystery", reason = "can_add_false" },
})
assert(note:find("skipped 5 Tag"), "push summary mentions skipped tags")
assert(note:find("cannot mark Desired"), "refuse summary uses can_add_false label")

print("OK: AscensionSuite desired skip tags test passed")
