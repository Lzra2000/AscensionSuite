-- AscensionSuite: tests/test_wishlist.lua
-- The player-owned wishlist store: editable in any game mode, Desired only in
-- Wildcard (sandbox, no WoW frames).

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

-- Flipped mid-test: the point of 0.2.2+ is that everything except the Desired
-- push behaves the same on both sides of this flag.
local wildcard = false

local ENTRIES = {
    [1133] = { ID = 1133, Type = "Ability", Spell = 133, Name = "Fireball" },
    [1116] = { ID = 1116, Type = "Talent", Spell = 116, Name = "Ice Block" },
    [1780] = { ID = 1780, Type = "Ability", Spell = 780, Name = "Living Bomb" },
}

local BY_SPELL = {}
for _, entry in pairs(ENTRIES) do
    BY_SPELL[entry.Spell] = entry
end

-- No GetSpellInfo on purpose: 999999 must stay unresolvable so the "keep an id
-- the client cannot name" path is exercised rather than papered over.
local UNRESOLVABLE = 999999

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
    GetKnownSpellEntries = function()
        return { { ID = 1133, Type = "Ability", Spell = 133, Name = "Fireball" } }
    end,
    GetKnownTalentEntries = function() return {} end,
}

C_Wildcard = {
    CanAddDesiredID = function() return true end,
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

AscensionSuite.Database.Init()

local API = AscensionSuite.AscensionAPI
local Wishlist = AscensionSuite.Wishlist
assert(Wishlist, "Wishlist module missing")

------------------------------------------------------------------------
-- Editing works outside Wildcard, which is the whole point
------------------------------------------------------------------------

assert(not API.IsWildcardModeActive(), "this half of the test runs outside Wildcard")
assert(Wishlist.Count() == 0, "the wishlist starts empty")

local ok, result = Wishlist.Add(133)
assert(ok and result == "added", "adding a spell id outside Wildcard succeeds")
assert(Wishlist.Count() == 1, "and the row is stored")
assert(Wishlist.Contains(133), "and is findable by spell id")

ok, result = Wishlist.Add(133)
assert(ok and result == "exists", "adding the same spell twice is a no-op, not a duplicate")
assert(Wishlist.Count() == 1, "still one row")

-- The advancement internal id is the other id space the player might type.
assert(Wishlist.Contains(1133), "a row is findable by its entry id too")

-- An id nothing can resolve is kept rather than rejected: Character Advancement
-- data is not always loaded, and an id that fails here can resolve in Wildcard.
assert(Wishlist.Add(UNRESOLVABLE), "an unresolvable id is still accepted")
assert(Wishlist.Count() == 2, "and stored")

local rows = Wishlist.Search(nil)
assert(#rows == 2, "an empty filter returns everything")
assert(rows[1].name == "Fireball", "names come from the advancement entry")
assert(rows[1].resolved, "a resolved row says so")
assert(not rows[2].resolved, "and an unresolved one does not")
assert(rows[2].name:find(tostring(UNRESOLVABLE)), "an unresolved row still names its id")

assert(#Wishlist.Search("fire") == 1, "search matches the name, case-insensitively")
assert(#Wishlist.Search("133") == 1, "search matches the id")
assert(#Wishlist.Search("nothing here") == 0, "and misses cleanly")

------------------------------------------------------------------------
-- Desired is the only Wildcard-gated half
------------------------------------------------------------------------

local pushed, already, failed, reason = Wishlist.PushToDesired()
assert(reason == "not_wildcard", "pushing outside Wildcard reports why")
assert(pushed == 0 and already == 0 and failed == 0, "and changes nothing")
assert(Wishlist.CountDesired() == 0, "nothing is Desired outside Wildcard")
assert(Wishlist.Count() == 2, "and the wishlist is untouched by the refusal")

wildcard = true

pushed, already, failed, reason = Wishlist.PushToDesired()
assert(reason == nil, "in Wildcard the push runs")
assert(pushed == 1, "the resolvable row is marked Desired (got " .. tostring(pushed) .. ")")
assert(already == 0, "nothing was Desired beforehand")
assert(failed == 1, "the unresolvable row cannot be pushed and is counted, not silently dropped")
assert(desired[Key(1133, "Ability")] == true, "the client holds the mark")
assert(Wishlist.CountDesired() == 1, "and the panel count agrees")

-- The badge is a live probe, not stored state: editing Desired in Ascension's
-- own window has to move the count without the addon being told.
API.RemoveDesiredID(1133, "Ability")
assert(Wishlist.CountDesired() == 0, "un-desiring outside the addon is reflected immediately")
assert(Wishlist.Count() == 2, "and does not remove the row from the wishlist")

------------------------------------------------------------------------
-- Adding from an advancement entry the caller already holds a pair for
------------------------------------------------------------------------

local added, isNew = Wishlist.AddEntry(1116, "Talent", nil, "Ice Block")
assert(added and isNew, "the book hook path adds a row")
assert(Wishlist.HasEntry(1116, "Talent"), "keyed on the (id, type) pair Desired needs")
assert(Wishlist.Count() == 3, "three rows now")

local iceRow
for _, row in ipairs(Wishlist.Search("ice")) do
    iceRow = row
end
assert(iceRow and iceRow.spellId == 116,
    "the spell behind an internal id is resolved in the internal id space")

pushed, already, failed = Wishlist.PushToDesired()
assert(pushed == 2, "both resolvable rows push (got " .. tostring(pushed) .. ")")
assert(failed == 1, "the unresolvable one still cannot")
assert(Wishlist.CountDesired() == 2, "and two are Desired")

------------------------------------------------------------------------
-- Removal never touches more than it was asked to
------------------------------------------------------------------------

assert(Wishlist.RemoveEntry(1116, "Talent"), "removing by pair works")
assert(not Wishlist.HasEntry(1116, "Talent"), "the row is gone")
assert(Wishlist.Count() == 2, "one row lighter")
assert(desired[Key(1116, "Talent")] == true,
    "removing from the wishlist leaves Ascension's own Desired set alone")

assert(Wishlist.Remove(133), "removing by spell id works")
assert(not Wishlist.Contains(133), "the row is gone")
assert(not Wishlist.Remove(133), "removing it again reports nothing to do")

------------------------------------------------------------------------
-- Profiles carry the whole list plus the Desired subset
------------------------------------------------------------------------

Wishlist.Add(133)
Wishlist.Add(780)
API.AddDesiredID(1133, "Ability")

assert(Wishlist.SaveProfile("test-hero", true), "save profile")
local profile = AscensionSuiteDB.desiredProfiles["test-hero"]
assert(#profile.wishlist == Wishlist.Count(), "the profile carries the whole wishlist")
assert(#profile.entries == 1 and profile.entries[1].id == 1133,
    "and separately the subset Ascension confirms is Desired")
assert(type(profile.knownSnapshot) == "table", "known snapshot saved")

local before = Wishlist.Count()
assert(Wishlist.Clear() == before, "Clear reports how many rows it removed")
assert(Wishlist.Count() == 0, "and empties the list")
assert(API.ClearDesiredSpells(), "clear desired via seam")
assert(Wishlist.CountDesired() == 0, "nothing Desired after the clear")

assert(Wishlist.LoadProfile("test-hero", true), "load profile")
assert(Wishlist.Count() == 3, "the whole list comes back")
assert(Wishlist.CountDesired() == 1,
    "and only the Desired subset is re-marked, not everything on the list")

print("OK: AscensionSuite wishlist test passed")
