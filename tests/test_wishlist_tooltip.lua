-- AscensionSuite: tests/test_wishlist_tooltip.lua
-- Native tooltip fetch via AscensionAPI.ShowEntryTooltip.

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

local function Noop() end

local tooltipOwner = {}
local tooltipSpellId
local tooltipHyperlink
local tooltipLines = {}

GameTooltip = {
    SetOwner = Noop,
    SetText = function(_, text)
        tooltipLines = { text }
    end,
    AddLine = function(_, text)
        tooltipLines[#tooltipLines + 1] = text
    end,
    SetSpellByID = function(_, spellId)
        tooltipSpellId = spellId
        tooltipHyperlink = nil
        tooltipLines = {}
    end,
    SetHyperlink = function(_, link)
        tooltipHyperlink = link
        tooltipSpellId = nil
        tooltipLines = {}
    end,
    Show = Noop,
    Hide = Noop,
}

LinkUtil = {
    GetSpellLink = function(_, spellId)
        return "|Hspell:" .. tostring(spellId) .. "|h[Spell]|h"
    end,
    GetTalentLinkByID = function(_, internalId, rank)
        return "|Hspell:" .. tostring(internalId + rank) .. "|h[Talent]|h"
    end,
    GetSpellLinkInternalID = function(_, internalId)
        return "|Hspell:" .. tostring(internalId + 50000) .. "|h[Internal]|h"
    end,
}

function GetSpellInfo(spellId)
    return "Spell " .. tostring(spellId), "Rank 1"
end

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, spellId)
        if spellId == 133 then
            return {
                ID = 1133,
                Type = "Ability",
                Spells = { 133 },
                Name = "Fireball",
            }
        end
        return nil
    end,
    GetEntryByInternalID = function(_, internalId)
        if internalId == 2001 then
            return {
                ID = 2001,
                Type = "Talent",
                Spells = { 2101, 2102, 2103 },
                Name = "Improved Fireball",
            }
        end
        if internalId == 3001 then
            return {
                ID = 3001,
                Type = "Tag",
                Name = "Fire Tag",
            }
        end
        return nil
    end,
    IsTalentID = function(_, internalId)
        return internalId == 2001
    end,
    GetTalentRankByID = function(_, internalId)
        if internalId == 2001 then
            return 2, 3
        end
        return 0, 0
    end,
}

dofile(ROOT .. "/integration/AscensionAPI.lua")

local API = AscensionSuite.AscensionAPI
assert(API, "AscensionAPI missing")

assert(API.GetEntryTooltipSpellID(133) == 133, "ability tooltip spell id")
assert(API.GetEntryTooltipSpellID(nil, 2001) == 2102,
    "talent tooltip uses current rank spell id")

tooltipSpellId = nil
tooltipHyperlink = nil
assert(API.ShowEntryTooltip(tooltipOwner, 133, "ANCHOR_RIGHT") == true,
    "ability shows native spell tooltip")
assert(tooltipSpellId == 133, "SetSpellByID used for ability, got " .. tostring(tooltipSpellId))

tooltipSpellId = nil
tooltipHyperlink = nil
assert(API.ShowEntryTooltip(tooltipOwner, nil, "ANCHOR_RIGHT", 2001) == true,
    "talent shows native tooltip by internal id")
assert(tooltipSpellId == 2102, "talent rank spell id in tooltip, got " .. tostring(tooltipSpellId))

tooltipSpellId = nil
tooltipHyperlink = nil
tooltipLines = {}
assert(API.ShowEntryTooltip(tooltipOwner, nil, "ANCHOR_RIGHT", 3001) == true,
    "tag entry shows text tooltip")
assert(tooltipLines[1] == "Fire Tag", "tag tooltip name")

-- Fallback path when SetSpellByID is absent.
GameTooltip.SetSpellByID = nil
tooltipHyperlink = nil
assert(API.ShowEntryTooltip(tooltipOwner, 133) == true, "hyperlink fallback")
assert(tooltipHyperlink and tooltipHyperlink:find("133"), "spell hyperlink fallback")

print("OK: wishlist tooltip tests passed")
