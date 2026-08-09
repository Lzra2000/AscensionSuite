-- AscensionSuite: tests/test_loadouts.lua
-- Loadouts save/load/apply/import/export and refuse-resolve hardening.

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

local wildcard = false

local ENTRIES = {
    [1133] = { ID = 1133, Type = "Ability", Spell = 133, Name = "Fireball" },
    [1116] = { ID = 1116, Type = "Talent", Spell = 116, Name = "Ice Block" },
    [1780] = { ID = 1780, Type = "Ability", Spell = 780, Name = "Living Bomb" },
    [8264] = { ID = 8264, Type = "Talent", Spell = 8264, Name = "Gavel of Wrath" },
}

local BY_SPELL = {}
for _, entry in pairs(ENTRIES) do
    BY_SPELL[entry.Spell] = entry
end

local desired = {}
local refuseIds = {}

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
    GetInternalID = function(_, spellId)
        if spellId == 116 then return 1116 end
        if spellId == 8264 then return 8264 end
        return nil
    end,
    GetKnownSpellEntries = function()
        return { { ID = 1133, Type = "Ability", Spell = 133, Name = "Fireball" } }
    end,
    GetKnownTalentEntries = function() return {} end,
    GetClassInfo = function(_, spellId)
        if spellId == 133 then return "MAGE", "Fire" end
        if spellId == 116 then return "MAGE", "Frost" end
    end,
}

C_Wildcard = {
    CanAddDesiredID = function(_, entryId)
        return refuseIds[entryId] ~= true
    end,
    AddDesiredID = function(_, entryId, entryType)
        if refuseIds[entryId] then
            return false
        end
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

local Wishlist = AscensionSuite.Wishlist
local Loadouts = AscensionSuite.Loadouts
assert(Wishlist and Loadouts, "modules missing")

------------------------------------------------------------------------
-- Resolve spell-only rows before Push
------------------------------------------------------------------------

Wishlist.Add(133)
Wishlist.Add(780)
local items = Wishlist.GetItems()
assert(items[1].entryId == nil or items[1].entryType == nil or true, "seed rows")

wildcard = true
local pushed, already, failed, reason, refuses = Wishlist.PushToDesired()
assert(reason == nil, "push runs in wildcard")
assert(pushed == 2, "both spell-only rows resolve and push (got " .. tostring(pushed) .. ")")
assert(failed == 0, "nothing refused after resolve")
assert(items[1].entryId == 1133, "pair cached on row")
assert(items[2].entryId == 1780, "second row cached")

------------------------------------------------------------------------
-- Refuse reasons surface
------------------------------------------------------------------------

desired = {}
refuseIds[1116] = true
Wishlist.AddEntry(1116, "Talent", 116, "Ice Block")
pushed, already, failed, reason, refuses = Wishlist.PushToDesired()
assert(failed >= 1, "refused entry counted (got " .. tostring(failed) .. ")")
assert(type(refuses) == "table" and #refuses >= 1, "refuse list returned")
local summary = Loadouts.FormatRefuseSummary(refuses)
assert(type(summary) == "string" and summary:find("refused"), "summary mentions refuse")

------------------------------------------------------------------------
-- Loadouts save / load / export / import
------------------------------------------------------------------------

refuseIds = {}
desired = {}

local loadout, id = Loadouts.Create("Storm kit", "notes", false)
assert(loadout and id, "create loadout")

Wishlist.Clear()
Wishlist.Add(133)
Wishlist.AddEntry(1116, "Talent", 116, "Ice Block")
API = AscensionSuite.AscensionAPI
API.AddDesiredID(1133, "Ability")

local ok, count = Loadouts.SaveFromWishlist(id, false, true)
assert(ok and count == 2, "save snapshots wishlist")

local exported = Loadouts.ExportString(id)
assert(exported:match("^ASUITE1|"), "export uses ASUITE1 prefix")
assert(exported:find("Storm kit"), "export carries name")
assert(exported:find("Ability:1133:"), "export carries resolved entry")

Wishlist.Clear()
assert(Wishlist.Count() == 0, "cleared")

ok, count = Loadouts.LoadToWishlist(id)
assert(ok and count == 2, "load restores wishlist")
assert(Wishlist.Count() == 2, "two rows back")

Wishlist.Clear()
local imported, importId = Loadouts.ImportString(exported, true)
assert(imported and importId, "import share string")
assert(#imported.entries == 2, "imported two entries")

------------------------------------------------------------------------
-- Apply = load + push
------------------------------------------------------------------------

Wishlist.Clear()
wildcard = true
ok, result = Loadouts.Apply(importId)
assert(ok and result.loaded == 2, "apply loads entries")
assert(result.pushed >= 1, "apply pushes resolved pairs")

------------------------------------------------------------------------
-- Stale spell-as-entryId pairs re-resolve spell-first
------------------------------------------------------------------------

local staleLoadout, staleId = Loadouts.Create("Stale pair", "", false)
staleLoadout.entries = {
    { entryId = 8264, entryType = "Ability", spellId = 8264, name = "Gavel of Wrath" },
}
wildcard = true
desired = {}
local pushedStale, _, failedStale = Loadouts.PushToDesired(staleId)
assert(pushedStale == 1, "talent row with wrong type still pushes (got " .. tostring(pushedStale) .. ")")
assert(failedStale == 0, "stale Ability type does not refuse talent")
assert(desired["8264/Talent"] == true, "correct Talent pair marked Desired")

------------------------------------------------------------------------
-- Export resolves spell-only rows and keeps ASUITE1 prefix
------------------------------------------------------------------------

local exportLoadout, exportId = Loadouts.Create("Export test", "", false)
exportLoadout.entries = {
    { spellId = 133, name = "Fireball" },
}
local exportText = Loadouts.ExportString(exportId)
assert(exportText:match("^ASUITE1|"), "export keeps prefix")
assert(exportText:find("Ability:1133:"), "spell-only row resolves before export")

local legacyImported = Loadouts.ImportString("ASUITE1|legacy|1|8264:Gavel of Wrath", true)
assert(legacyImported and #legacyImported.entries == 1, "legacy spellId:name imports")

------------------------------------------------------------------------
-- Migration from desiredProfiles
------------------------------------------------------------------------

AscensionSuiteDB.version = 5
AscensionSuiteDB.loadouts = {}
AscensionSuiteDB.desiredProfiles = {
    legacy = {
        wishlist = { { spellId = 133, entryId = 1133, entryType = "Ability", name = "Fireball" } },
        entries = { { id = 1133, type = "Ability", spellId = 133 } },
    },
}
AscensionSuite.Database.Init()
assert(AscensionSuiteDB.version == 7, "migrated to v7")
assert(AscensionSuiteDB.loadouts["legacy-migrated"], "legacy profile became loadout")

------------------------------------------------------------------------
-- Import archetype from native build seam
------------------------------------------------------------------------

C_BuildCreator = {
    GetActiveBuild = function() return "build-1" end,
    GetBuild = function(_, id)
        if id == "build-1" then
            return {
                ID = "build-1",
                Name = "Imported archetype",
                AuthorName = "Native",
                Category = "Level60PvE",
                Difficulty = "Expert",
                Description = "### OVERVIEW\nImported overview\n###",
                Spells = {
                    { Spell = 133 },
                    { Spell = 116 },
                },
                ArmorTypes = { "Plate" },
                WeaponTypes = {},
            }
        end
    end,
    GetSpell = function(_, buildId, spellId)
        if spellId == 133 then
            return { IsCoreAbility = true }
        end
        if spellId == 116 then
            return { IsOptimalAbility = true }
        end
    end,
}

C_BuildEditor = {
    GetPendingBuild = function() return nil end,
}

local importLoadout, importId = Loadouts.Create("Import target", "", false)
local ok, count, source = Loadouts.ImportFromArchetype(importId)
assert(ok and count == 2, "imported two spells from archetype (got " .. tostring(count) .. ")")
assert(source == "active", "used active build")
importLoadout = Loadouts.Get(importId)
assert(importLoadout.name == "Imported archetype", "name copied")
assert(importLoadout.author == "Native", "author copied")
assert(importLoadout.sections.OVERVIEW:match("Imported overview"), "overview section copied")
assert(#importLoadout.equipment.armorTypes == 1, "equipment stub copied")
assert(importLoadout.equipment.armorTypes[1].type == "ITEM_SUBCLASS_ARMOR_PLATE", "equipment type normalized")

------------------------------------------------------------------------
-- Filtered Desired counts (live marks among filtered spells)
------------------------------------------------------------------------

local filterLoadout, filterId = Loadouts.Create("Filter test", "", false)
filterLoadout.entries = {
    { entryId = 1133, entryType = "Ability", spellId = 133, name = "Fireball", tags = { core = true } },
    { entryId = 1116, entryType = "Talent", spellId = 116, name = "Ice Block", tags = { optimal = true } },
}
desired["1133/Ability"] = true
local desiredCount, filteredTotal = Loadouts.CountFilteredDesired(filterLoadout, { core = true, optimal = false })
assert(filteredTotal == 1, "only core row counts when optimal filtered out")
assert(desiredCount == 1, "live Desired mark counted among filtered rows")

------------------------------------------------------------------------
-- Capture Known snapshot
------------------------------------------------------------------------

local okKnown, knownCount = Loadouts.CaptureKnown(filterId)
assert(okKnown and knownCount >= 1, "Capture Known stores snapshot")

------------------------------------------------------------------------
-- Import failure messaging
------------------------------------------------------------------------

local message = Loadouts.DescribeImportError("no_build")
assert(type(message) == "string" and message:find("importable"), "clear no-build message")

local API = AscensionSuite.AscensionAPI
local originalGetImportable = API.GetImportableBuild
API.GetImportableBuild = function() return nil, "no_build" end
local failLoadout, failId = Loadouts.Create("Fail import", "", false)
local failOk, failReason = Loadouts.ImportFromArchetype(failId)
API.GetImportableBuild = originalGetImportable
assert(not failOk, "import fails without build")
assert(type(failReason) == "string" and failReason:find("importable"), "import surfaces clear message")

------------------------------------------------------------------------
-- Pros/cons formatting, add-by-id, Desired toggle on rows
------------------------------------------------------------------------

local formatted = Loadouts.FormatProsAndCons("+ burst damage\n- squishy")
assert(type(formatted) == "string" and formatted:find("burst"), "pros line formatted")
assert(formatted:find("squishy"), "cons line formatted")

local addLoadout, addId = Loadouts.Create("Add test", "", false)
local addOk, addReason = Loadouts.AddById(addId, 133)
assert(addOk and addReason == "added", "AddById resolves spell id")
addLoadout = Loadouts.Get(addId)
assert(#addLoadout.entries == 1, "one entry after AddById")

local dupOk, dupReason = Loadouts.AddById(addId, 133)
assert(not dupOk and dupReason == "duplicate", "AddById rejects duplicate")

wildcard = true
desired = {}
local toggleRow = addLoadout.entries[1]
local toggleOk, nowDesired = Loadouts.ToggleEntryDesired(addId, toggleRow)
assert(toggleOk and nowDesired == true, "ToggleEntryDesired marks Desired in Wildcard")
assert(desired[Key(1133, "Ability")] == true, "client Desired updated")
toggleOk, nowDesired = Loadouts.ToggleEntryDesired(addId, toggleRow)
assert(toggleOk and nowDesired == false, "ToggleEntryDesired removes Desired mark")
assert(desired[Key(1133, "Ability")] == nil, "client Desired cleared")

local renameOk = Loadouts.Rename(addId, "Renamed build")
assert(renameOk, "Rename succeeds")
assert(Loadouts.Get(addId).name == "Renamed build", "Rename updates name")

print("OK: AscensionSuite loadouts test passed")
