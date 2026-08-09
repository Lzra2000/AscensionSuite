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

-- Ascension_WildCard's saved Desired table is per character and per spec, so it is
-- small in practice; the cap only exists so a corrupt SavedVariable cannot turn one
-- Sync click into an unbounded run of IsDesiredID probes.
local MAX_SAVED_SELECTION_PROBES = 1000

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

-- Ascension CA entries store the blp name only; native widgets prefix
-- Interface\Icons\ before SetTexture (SpellIconTemplateMixin:SetCharacterAdvancementEntry).
local ICON_TEXTURE_ROOT = "Interface\\Icons\\"

local function NormalizeIconTexture(texture)
    if type(texture) ~= "string" or texture == "" then
        return nil
    end
    if texture:find("\\") or texture:find("/") then
        return texture
    end
    local lower = texture:lower()
    if lower:sub(1, 9) == "interface" then
        return texture
    end
    return ICON_TEXTURE_ROOT .. texture
end

local function EntryIconFromFields(entry)
    if type(entry) ~= "table" then
        return nil
    end
    return NormalizeIconTexture(FirstTexture(
        entry.Icon, entry.icon, entry.texture, entry.Texture, entry.spellIcon))
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

-- Lua 5.1 tonumber(e, base) treats a second argument as radix; never pass a
-- multi-return call straight into tonumber (e.g. GetTalentRank returns rank, maxRank).
-- Assign through a local: tonumber(select(1, ...)) still leaks the second value.
local function TonumberFirst(...)
    local value = select(1, ...)
    return tonumber(value)
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

-- Ascension's C_GameMode:IsGameModeActive takes Enum.GameMode flags, not strings.
-- Sandbox tests still pass string mode names into a stub; the live client needs the
-- enum value (or GetActiveGameModes / GetCustomGameMode fallbacks).
local function GameModeEnum(modeName)
    if type(modeName) ~= "string" or modeName == "" then
        return nil
    end
    local enums = _G.Enum and _G.Enum.GameMode
    if type(enums) ~= "table" then
        return nil
    end
    local value = enums[modeName]
    if value ~= nil then
        return value
    end
    if modeName == "Wildcard" then
        return enums.WildCard
    end
    return nil
end

local function BitContains(mask, flag)
    if mask == nil or flag == nil then
        return false
    end
    local bitLib = _G.bit
    if type(bitLib) == "table" and type(bitLib.contains) == "function" then
        return bitLib.contains(mask, flag) == true
    end
    if type(mask) == "number" and type(flag) == "number" then
        return bitLib and type(bitLib.band) == "function" and bitLib.band(mask, flag) == flag
    end
    return false
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

    local enumValue = GameModeEnum(modeName)
    local gm = GM()
    if gm then
        if enumValue ~= nil and Call(gm, { "IsGameModeActive" }, enumValue) == true then
            return true
        end
        if Call(gm, { "IsGameModeActive" }, modeName) == true then
            return true
        end
        if Call(gm, { "IsActiveGameMode" }, modeName) == true then
            return true
        end
        if enumValue ~= nil and Call(gm, { "IsActiveGameMode" }, enumValue) == true then
            return true
        end

        local modes = Call(gm, { "GetActiveGameModes" })
        if type(modes) == "table" then
            if modes[modeName] == true then
                return true
            end
            if enumValue ~= nil and type(_G.Enum) == "table" and type(_G.Enum.GameMode) == "table" then
                for name, active in pairs(modes) do
                    if active == true and _G.Enum.GameMode[name] == enumValue then
                        return true
                    end
                end
            end
        end
    end

    local getCustom = _G.GetCustomGameMode
    if enumValue ~= nil and type(getCustom) == "function" then
        local ok, activeModes = pcall(getCustom)
        if ok and BitContains(activeModes, enumValue) then
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
    if type(current) == "number" and enumValue ~= nil then
        if current == enumValue or BitContains(current, enumValue) then
            return true
        end
    end
    if type(current) == "number" and type(_G.Enum) == "table" and type(_G.Enum.GameMode) == "table" then
        local resolved = _G.Enum.GameMode[modeName]
        if resolved ~= nil then
            if current == resolved or BitContains(current, resolved) then
                return true
            end
        end
    end
    return tostring(current) == tostring(modeName)
end

function API.IsWildcardModeActive()
    local wildCard = GameModeEnum("WildCard")
    if wildCard ~= nil then
        if API.IsGameModeActive("WildCard") or API.IsGameModeActive("Wildcard") then
            return true
        end
        local current = API.GetGameMode()
        if type(current) == "number" and BitContains(current, wildCard) then
            return true
        end
        local getCustom = _G.GetCustomGameMode
        if type(getCustom) == "function" then
            local ok, activeModes = pcall(getCustom)
            if ok and BitContains(activeModes, wildCard) then
                return true
            end
        end
        return false
    end
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

function API.GetEntryIcon(spellOrEntryId, internalId)
    local entry = nil
    if internalId ~= nil then
        entry = API.ResolveEntryByInternalID(internalId)
    end
    if not entry then
        entry = API.ResolveEntry(spellOrEntryId)
    end

    if entry then
        local icon = EntryIconFromFields(entry)
        if icon then
            return icon
        end

        local spellId = API.GetEntryTooltipSpellID(spellOrEntryId, internalId)
        if spellId and GetSpellInfo then
            local _, _, texture = GetSpellInfo(spellId)
            icon = NormalizeIconTexture(texture)
            if icon then
                return icon
            end
        end
    end

    local id = tonumber(spellOrEntryId)
    if id and GetSpellInfo then
        local _, _, texture = GetSpellInfo(id)
        local icon = NormalizeIconTexture(texture)
        if icon then
            return icon
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

-- Spell id the client should use for a hover tooltip. Talents resolve to the
-- current rank (or rank 1 when unknown), matching Rapid Rolling list items.
function API.GetEntryTooltipSpellID(spellOrEntryId, internalId)
    local entry = nil
    local knownInternal = tonumber(internalId)
    if knownInternal then
        entry = API.ResolveEntryByInternalID(knownInternal)
    end
    if not entry then
        entry = API.ResolveEntry(spellOrEntryId)
    end
    if not entry then
        return tonumber(spellOrEntryId)
    end

    local entryId = FirstNumber(entry.ID, entry.Id, entry.id, entry.internalID, entry.InternalID)
    local ca = CA()
    local isTalent = false
    if entryId and ca then
        isTalent = Call(ca, { "IsTalentID" }, entryId) == true
    end

    if isTalent and entryId then
        local rank = TonumberFirst(API.GetTalentRank(entryId)) or 0
        if rank < 1 then
            rank = 1
        end
        local spells = entry.Spells or entry.spells
        if type(spells) == "table" then
            local spellId = tonumber(spells[rank])
            if spellId then
                return spellId
            end
            return tonumber(spells[1])
        end
        local byRank = API.GetTalentRankSpellID(entryId, rank)
        if byRank then
            return byRank
        end
    end

    local spellId = EntrySpellID(entry)
    if spellId then
        return spellId
    end
    return tonumber(spellOrEntryId)
end

local function TooltipSetHyperlink(tooltip, link)
    if not link or link == "" or type(tooltip.SetHyperlink) ~= "function" then
        return false
    end
    tooltip:SetHyperlink(link)
    return true
end

local function TooltipSetSpellById(tooltip, spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return false
    end

    if type(tooltip.SetSpellByID) == "function" then
        tooltip:SetSpellByID(spellId)
        return true
    end

    local linkUtil = _G.LinkUtil
    if type(linkUtil) == "table" and type(linkUtil.GetSpellLink) == "function" then
        local link = linkUtil:GetSpellLink(spellId)
        if link and link ~= "" then
            return TooltipSetHyperlink(tooltip, link)
        end
    end

    return TooltipSetHyperlink(tooltip, "spell:" .. tostring(spellId))
end

-- Paint the native Ascension / Blizzard spell tooltip on owner. Returns true when
-- GameTooltip was populated from client APIs; false when callers should fall back
-- to GetEntryTooltipLines. Tag / Suggestion entries have no spell tooltip.
function API.ShowEntryTooltip(owner, spellOrEntryId, anchor, internalId)
    local tooltip = _G.GameTooltip
    if not tooltip or not owner then
        return false
    end

    anchor = anchor or "ANCHOR_RIGHT"
    tooltip:SetOwner(owner, anchor)

    local entry = nil
    local knownInternal = tonumber(internalId)
    if knownInternal then
        entry = API.ResolveEntryByInternalID(knownInternal)
    end
    if not entry then
        entry = API.ResolveEntry(spellOrEntryId)
    end

    local entryType = entry and FirstString(entry.Type, entry.type, entry.entryType, entry.EntryType)
    if entryType == "Tag" or entryType == "Suggestion" then
        local name = FirstString(entry.Name, entry.name, entry.spellName, entry.displayName) or "Entry"
        tooltip:SetText(name, 1, 1, 1)
        local tagFormat = _G.SPELL_TAG_TOOLTIP
        if type(tagFormat) == "string" then
            local highlight = _G.HIGHLIGHT_FONT_COLOR
            local wrapped = name
            if type(highlight) == "table" and type(highlight.WrapText) == "function" then
                wrapped = highlight:WrapText(name)
            end
            tooltip:AddLine(tagFormat:format(wrapped), 1, 0.82, 0, true)
        end
        return true
    end

    local spellId = API.GetEntryTooltipSpellID(spellOrEntryId, internalId)
    if spellId and TooltipSetSpellById(tooltip, spellId) then
        return true
    end

    local entryId = knownInternal or (entry and FirstNumber(entry.ID, entry.Id, entry.id))
    local linkUtil = _G.LinkUtil
    if entryId and type(linkUtil) == "table" then
        local rank = TonumberFirst(API.GetTalentRank(entryId)) or 1
        if rank < 1 then
            rank = 1
        end
        if type(linkUtil.GetTalentLinkByID) == "function" then
            local talentLink = linkUtil:GetTalentLinkByID(entryId, rank)
            if talentLink and TooltipSetHyperlink(tooltip, talentLink) then
                return true
            end
        end
        if type(linkUtil.GetSpellLinkInternalID) == "function" then
            local internalLink = linkUtil:GetSpellLinkInternalID(entryId)
            if internalLink and internalLink ~= "" and TooltipSetHyperlink(tooltip, internalLink) then
                return true
            end
        end
    end

    return false
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
-- Desired eligibility (Ability / Talent only; Tag / Suggestion are meta rows)
------------------------------------------------------------------------

local DESIRED_ELIGIBLE_TYPES = {
    Ability = true,
    Talent = true,
}

local META_ENTRY_TYPES = {
    Tag = true,
    Suggestion = true,
}

function API.IsDesiredEligibleType(entryType)
    if type(entryType) ~= "string" or entryType == "" then
        return false
    end
    return DESIRED_ELIGIBLE_TYPES[entryType] == true
end

function API.IsMetaEntryType(entryType)
    if type(entryType) ~= "string" or entryType == "" then
        return false
    end
    return META_ENTRY_TYPES[entryType] == true
end

function API.DescribeEntryTypeRefuse(entryType, resolveErr)
    if resolveErr == "unresolved" or resolveErr == "incomplete_entry" or resolveErr == "invalid_item" then
        return "unresolved"
    end
    if API.IsMetaEntryType(entryType) then
        return "tag_not_desired"
    end
    if entryType and not API.IsDesiredEligibleType(entryType) then
        return "type_not_desired"
    end
    return "can_add_false"
end

function API.CountDesiredSelections(maxScan)
    local selections = API.CollectAllDesiredSelections(maxScan)
    return #selections
end

local function ResolveCanAddMaxDesired()
    local wc = WC()
    if not wc then
        return nil
    end
    local maxDesired = Call(wc, { "GetMaxDesiredCount", "GetDesiredLimit", "GetMaxDesiredSelections" })
    if type(maxDesired) == "number" and maxDesired > 0 then
        return maxDesired
    end
    return nil
end

-- Why CanAddDesiredID returned false for a resolved (entryId, entryType) pair.
function API.DescribeCanAddRefuse(entryId, entryType, resolveErr)
    local typeRefuse = API.DescribeEntryTypeRefuse(entryType, resolveErr)
    if typeRefuse ~= "can_add_false" then
        return typeRefuse
    end

    if not API.IsWildcardModeActive() then
        return "not_wildcard_mode"
    end

    local wc = WC()
    if not wc then
        return "no_wildcard_api"
    end

    local id = tonumber(entryId)
    if not id or type(entryType) ~= "string" or entryType == "" then
        return "bad_pair"
    end

    if API.IsDesiredID(id, entryType) then
        return "already_desired"
    end

    if API.IsKnownID(id) then
        return "already_known"
    end

    local entry = API.GetEntryByInternalID(id)
    if type(entry) == "table" then
        local resolvedId, resolvedType = EntryPair(entry)
        if resolvedId and resolvedType then
            if resolvedId ~= id or resolvedType ~= entryType then
                return "bad_pair"
            end
        end
    else
        return "bad_pair"
    end

    local maxDesired = ResolveCanAddMaxDesired()
    if maxDesired then
        local desiredCount = API.CountDesiredSelections()
        if desiredCount >= maxDesired then
            return "desired_cap"
        end
    end

    if API.CanAddDesiredID(id, entryType) then
        return nil
    end

    return "can_add_false"
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
-- a narrowed filter hides selections rather than deselecting them. Use
-- CollectAllDesiredSelections unless you specifically want the filtered view.
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

-- Drop the Rapid window's Desired *search text* so the candidate list widens to
-- everything the filter checkboxes admit, and hand back the undo. Ascension's own
-- WildCardRapidRollingMixin:DesiredSearch(text) is the funnel -- passing "" runs
-- C_Wildcard.SetFilteredDesiredEntries("", <current filter>), and calling it with
-- no argument re-reads the search box, which this never writes to. So the player's
-- typed search survives, in the box and in Ascension's own saved filter state.
--
-- Returns nil when there is nothing to widen (no Rapid frame, or an empty box),
-- which is also the signal that a scan already saw the full candidate list.
function API.WidenDesiredCandidates()
    local frame = RapidRollingFrame()
    if type(frame) ~= "table" or type(frame.DesiredSearch) ~= "function" then
        return nil
    end

    local searchBox = frame.DesiredSearchBox
    if type(searchBox) ~= "table" or type(searchBox.GetText) ~= "function" then
        return nil
    end

    local ok, text = pcall(searchBox.GetText, searchBox)
    if not ok or type(text) ~= "string" or text:match("^%s*$") then
        return nil
    end

    if not pcall(frame.DesiredSearch, frame, "") then
        return nil
    end

    return function()
        pcall(frame.DesiredSearch, frame)
    end
end

-- Ascension_WildCard remembers every Desired toggle the player makes in the Rapid
-- window in its own per-character SavedVariable (RapidRollDesired[specID][type][id],
-- written by WildCardRapidRollingMixin:SaveDesiredEntry). Reading it finds marks the
-- filtered candidate list cannot show at all -- including ones made in a previous
-- session. It is a hint, not an authority: every pair is still confirmed with
-- IsDesiredID before it counts, so a stale row contributes nothing.
function API.CollectSavedRapidSelections()
    local selections = {}
    local saved = _G.RapidRollDesired
    if type(saved) ~= "table" then
        return selections, 0
    end

    local buckets = {}
    local specUtil = Namespace("SpecializationUtil")
    if specUtil and type(specUtil.GetActiveSpecialization) == "function" then
        local ok, specId = pcall(specUtil.GetActiveSpecialization)
        if ok and specId ~= nil and type(saved[specId]) == "table" then
            buckets[#buckets + 1] = saved[specId]
        end
    end

    -- No spec id (or no bucket for it): every spec's bucket is fair game, since
    -- IsDesiredID answers for the spec that is actually active anyway.
    if #buckets == 0 then
        for _, bucket in pairs(saved) do
            if type(bucket) == "table" then
                buckets[#buckets + 1] = bucket
            end
        end
    end

    local probed = 0
    for bucketIndex = 1, #buckets do
        for entryType, ids in pairs(buckets[bucketIndex]) do
            if type(entryType) == "string" and type(ids) == "table" then
                for entryId in pairs(ids) do
                    local id = tonumber(entryId)
                    if id and probed < MAX_SAVED_SELECTION_PROBES then
                        probed = probed + 1
                        if API.IsDesiredID(id, entryType) then
                            local entry = API.GetEntryByInternalID(id)
                            selections[#selections + 1] = {
                                id = id,
                                type = entryType,
                                spellId = EntrySpellID(entry),
                                name = entry and FirstString(entry.Name, entry.name) or nil,
                            }
                        end
                    end
                end
            end
        end
    end

    return selections, probed
end

-- Every Desired selection the client will admit to, from both sources, with the
-- Rapid search box taken out of the way for the duration of the scan. This is what
-- "Sync from Rapid" and Auto-Roll should use: the filtered scan alone silently
-- misses selections whenever the player has typed in the Desired search box.
--
-- Returns the merged selections, how many candidate rows were scanned, and whether
-- the search box had to be widened -- the caller uses the last one to say so.
function API.CollectAllDesiredSelections(maxScan)
    local restore = API.WidenDesiredCandidates()
    local widened = restore ~= nil

    local ok, selections, scanned = pcall(API.CollectDesiredSelections, maxScan)
    if restore then
        restore()
    end
    if not ok then
        return {}, 0, widened
    end

    selections = selections or {}
    scanned = scanned or 0

    local seen = {}
    for index = 1, #selections do
        local row = selections[index]
        seen[row.type .. ":" .. tostring(row.id)] = true
    end

    local saved = API.CollectSavedRapidSelections()
    for index = 1, #saved do
        local row = saved[index]
        local key = row.type .. ":" .. tostring(row.id)
        if not seen[key] then
            seen[key] = true
            selections[#selections + 1] = row
        end
    end

    return selections, scanned, widened
end

------------------------------------------------------------------------
-- Undesired (Rapid Undesired column; read for badges / counts only)
------------------------------------------------------------------------

function API.IsUndesiredID(entryId, entryType)
    local wc = WC()
    if not wc then
        return false
    end
    return Call(wc, { "IsUndesiredID" }, entryId, entryType) == true
end

function API.GetNumFilteredUndesiredEntries()
    local wc = WC()
    if not wc then
        return 0
    end
    local count = Call(wc, { "GetNumFilteredUndesiredEntries" })
    if type(count) == "number" then
        return count
    end
    return 0
end

function API.GetFilteredUndesiredEntryAtIndex(index)
    local position = tonumber(index)
    if not position then
        return nil
    end
    local wc = WC()
    if not wc then
        return nil
    end
    return TableOrNil(Call(wc, { "GetFilteredUndesiredEntryAtIndex" }, position))
end

function API.CollectUndesiredSelections(maxScan)
    local selections = {}
    local total = API.GetNumFilteredUndesiredEntries()
    if total <= 0 then
        return selections, 0
    end

    local limit = tonumber(maxScan)
    if limit and limit < total then
        total = limit
    end

    for index = 1, total do
        local entry = API.GetFilteredUndesiredEntryAtIndex(index)
        local entryId, entryType = EntryPair(entry)
        if entryId and entryType and API.IsUndesiredID(entryId, entryType) then
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

function API.WidenUndesiredCandidates()
    local frame = RapidRollingFrame()
    if type(frame) ~= "table" or type(frame.UndesiredSearch) ~= "function" then
        return nil
    end

    local searchBox = frame.UndesiredSearchBox
    if type(searchBox) ~= "table" or type(searchBox.GetText) ~= "function" then
        return nil
    end

    local ok, text = pcall(searchBox.GetText, searchBox)
    if not ok or type(text) ~= "string" or text:match("^%s*$") then
        return nil
    end

    if not pcall(frame.UndesiredSearch, frame, "") then
        return nil
    end

    return function()
        pcall(frame.UndesiredSearch, frame)
    end
end

-- Ascension_WildCard's RapidRollUndesired[spec][type][id], confirmed with IsUndesiredID.
function API.CollectSavedRapidUndesiredSelections()
    local selections = {}
    local saved = _G.RapidRollUndesired
    if type(saved) ~= "table" then
        return selections, 0
    end

    local buckets = {}
    local specUtil = Namespace("SpecializationUtil")
    if specUtil and type(specUtil.GetActiveSpecialization) == "function" then
        local ok, specId = pcall(specUtil.GetActiveSpecialization)
        if ok and specId ~= nil and type(saved[specId]) == "table" then
            buckets[#buckets + 1] = saved[specId]
        end
    end

    if #buckets == 0 then
        for _, bucket in pairs(saved) do
            if type(bucket) == "table" then
                buckets[#buckets + 1] = bucket
            end
        end
    end

    local probed = 0
    for bucketIndex = 1, #buckets do
        for entryType, ids in pairs(buckets[bucketIndex]) do
            if type(entryType) == "string" and type(ids) == "table" then
                for entryId in pairs(ids) do
                    local id = tonumber(entryId)
                    if id and probed < MAX_SAVED_SELECTION_PROBES then
                        probed = probed + 1
                        if API.IsUndesiredID(id, entryType) then
                            local entry = API.GetEntryByInternalID(id)
                            selections[#selections + 1] = {
                                id = id,
                                type = entryType,
                                spellId = EntrySpellID(entry),
                                name = entry and FirstString(entry.Name, entry.name) or nil,
                            }
                        end
                    end
                end
            end
        end
    end

    return selections, probed
end

function API.CollectAllUndesiredSelections(maxScan)
    local restore = API.WidenUndesiredCandidates()
    local widened = restore ~= nil

    local ok, selections, scanned = pcall(API.CollectUndesiredSelections, maxScan)
    if restore then
        restore()
    end
    if not ok then
        return {}, 0, widened
    end

    selections = selections or {}
    scanned = scanned or 0

    local seen = {}
    for index = 1, #selections do
        local row = selections[index]
        seen[row.type .. ":" .. tostring(row.id)] = true
    end

    local saved = API.CollectSavedRapidUndesiredSelections()
    for index = 1, #saved do
        local row = saved[index]
        local key = row.type .. ":" .. tostring(row.id)
        if not seen[key] then
            seen[key] = true
            selections[#selections + 1] = row
        end
    end

    return selections, scanned, widened
end

function API.CountUndesiredSelections(maxScan)
    local selections = API.CollectAllUndesiredSelections(maxScan)
    return #selections
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
        icon = NormalizeIconTexture(spellIcon)
    end

    if entry then
        name = name or FirstString(entry.Name, entry.name, entry.spellName, entry.displayName)
        icon = icon or EntryIconFromFields(entry)
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
    if API.IsUnlearnOrKeepDecisionPending() then
        return false, "unlearn_decision"
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

-- Which entry the session just learned. Ascension's own Roll button reads the same
-- field to decide whether to offer Lock / Unlearn for it.
function API.GetRapidRollingLearnedEntryID()
    local state = API.GetRapidRollingState()
    if not state then
        return nil
    end
    return tonumber(state.LearnedEntryID)
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

local function GetDiceCoreState(dice)
    dice = dice or _G.WildCardDice
    local core = dice and dice.Core
    if type(core) ~= "table" or type(core.GetState) ~= "function" then
        return nil, nil
    end
    local ok, state = pcall(core.GetState, core)
    if not ok then
        return nil, core.State
    end
    return state, core.State
end

-- Ascension creates WildCardDice at FULLSCREEN_DIALOG (WildCard.lua). Suite must
-- not treat that native strata as a Suite-raised click-stealer.
local DICE_DECISION_STRATA = "FULLSCREEN_DIALOG"
local DICE_DECISION_FRAME_LEVEL = 128
local DICE_NATIVE_STRATA = "FULLSCREEN_DIALOG"
local DICE_SUITE_STRATA = "DIALOG"
local SUITE_MAIN_WINDOW_NAME = "AscensionSuiteMainWindow"
local SUITE_MAIN_FRAME_LEVEL = 130

local function IsSuiteMainWindowShown()
    local win = _G[SUITE_MAIN_WINDOW_NAME]
    if type(win) ~= "table" or type(win.IsShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(win.IsShown, win)
    return ok and shown == true
end

function API.IsSuiteMainWindowShown()
    return IsSuiteMainWindowShown()
end

local function SuiteMainWindowFrameLevel()
    local win = _G[SUITE_MAIN_WINDOW_NAME]
    if type(win) == "table" and type(win.GetFrameLevel) == "function" then
        local ok, level = pcall(win.GetFrameLevel, win)
        if ok and level then
            return level
        end
    end
    return SUITE_MAIN_FRAME_LEVEL
end

local function FrameChildIsShown(frame)
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function GetDiceInternalID(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" or type(dice.GetInternalID) ~= "function" then
        return nil
    end
    local ok, id = pcall(dice.GetInternalID, dice)
    if ok and id and id ~= 0 then
        return id
    end
    return nil
end

-- Post-reveal keep-vs-unlearn: green cage + spell icon / name frame / Roll offer.
function API.IsDiceRevealedDecisionShown(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" or dice.isRapidRolling then
        return false
    end
    if dice.pendingReveal then
        return false
    end
    if not GetDiceInternalID(dice) then
        return false
    end
    if FrameChildIsShown(dice.Icon) then
        return true
    end
    if FrameChildIsShown(dice.NameFrame) then
        return true
    end
    if API.IsDiceUnlearnRollOffered(dice) then
        return true
    end
    return false
end

local function CaptureDiceNativeLayering(dice)
    if type(dice) ~= "table" then
        return
    end
    -- Once Suite has demoted/raised, do not re-sample the mutated strata as "native".
    if dice._asuiteNativeStrata then
        return
    end
    if dice._asuiteStrataRaised or dice._asuiteDemotedForSuite then
        dice._asuiteNativeStrata = DICE_NATIVE_STRATA
    elseif type(dice.GetFrameStrata) == "function" then
        local ok, strata = pcall(dice.GetFrameStrata, dice)
        if ok and type(strata) == "string" and strata ~= "" then
            dice._asuiteNativeStrata = strata
        end
    end
    if not dice._asuiteNativeStrata then
        dice._asuiteNativeStrata = DICE_NATIVE_STRATA
    end
    if not dice._asuiteNativeLevel and type(dice.GetFrameLevel) == "function" then
        local ok, level = pcall(dice.GetFrameLevel, dice)
        if ok and level then
            dice._asuiteNativeLevel = level
        end
    end
    local rollButton = dice.RollButton
    if type(rollButton) == "table" and not dice._asuiteRollButtonLevel
        and type(rollButton.GetFrameLevel) == "function" then
        local ok, level = pcall(rollButton.GetFrameLevel, rollButton)
        if ok and level then
            dice._asuiteRollButtonLevel = level
        end
    end
end

local function RestoreDiceNativeLayering(dice)
    if type(dice) ~= "table" then
        return false
    end
    -- Only undo Suite mutations; never rewrite Ascension's own FULLSCREEN_DIALOG.
    if not dice._asuiteStrataRaised and not dice._asuiteDemotedForSuite then
        return false
    end

    local restored = false
    local strata = dice._asuiteNativeStrata or DICE_NATIVE_STRATA
    if type(dice.SetFrameStrata) == "function" then
        pcall(dice.SetFrameStrata, dice, strata)
        restored = true
    end
    local level = dice._asuiteNativeLevel
    if level and type(dice.SetFrameLevel) == "function" then
        pcall(dice.SetFrameLevel, dice, level)
        restored = true
    end
    local rollButton = dice.RollButton
    if type(rollButton) == "table" and dice._asuiteRollButtonLevel
        and type(rollButton.SetFrameLevel) == "function" then
        pcall(rollButton.SetFrameLevel, rollButton, dice._asuiteRollButtonLevel)
        restored = true
    end
    dice._asuiteStrataRaised = nil
    dice._asuiteDemotedForSuite = nil
    return restored
end

local function DiceIsShown(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" or type(dice.IsShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(dice.IsShown, dice)
    return ok and shown == true
end

-- Leveling die already revealed a spell (internalID set): rolling again opens
-- ConfirmOrUnlearnID / CONFIRM_UNLEARN_* (Scroll of Fortune I or II).
function API.IsDiceKeepOrUnlearnDecisionUp(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" or dice.isRapidRolling then
        return false
    end
    if not DiceIsShown(dice) or dice.pendingReveal then
        return false
    end
    if GetDiceInternalID(dice) then
        return true
    end
    return API.IsDiceRevealedDecisionShown(dice)
end

local function DiceIsIdle(dice)
    local state, states = GetDiceCoreState(dice)
    if state and states and states.IDLE then
        return state == states.IDLE
    end
    return false
end

local DICE_RECOVERY_COOLDOWN_SECONDS = 2.0
local DICE_STUCK_VISIBLE_SECONDS = 1.0
local DICE_LEVEL_UP_SETTLE_SECONDS = 0.35
local diceRecoveryCooldownUntil = 0
local diceStuckSince = 0
local levelUpSettleUntil = 0
local lastHoverSanitizeAt = 0
local HOVER_SANITIZE_COOLDOWN_SECONDS = 0.5

local function SuiteNow()
    if type(_G.GetTime) == "function" then
        return _G.GetTime()
    end
    return 0
end

local function DiceFadeAnimationPlaying(dice)
    if type(dice) ~= "table" then
        return false
    end
    -- Sandbox / legacy stub; AscensionUI does not attach this object.
    local fade = dice.BaseFrameFadeOut
    if type(fade) == "table" and type(fade.IsPlaying) == "function" then
        local ok, playing = pcall(fade.IsPlaying, fade)
        if ok and playing == true then
            return true
        end
    end
    return false
end

-- AscensionUI BaseFrameFade sets frame.FadeMode to "IN" or "OUT". Mid alpha alone
-- is NOT fade-out — appear uses the same alpha ramp with FadeMode "IN", and Suite
-- used to clear mouse / demote strata during that ramp.
function API.IsDiceFadingOut(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end
    if dice.FadeMode == "OUT" then
        return true
    end
    if DiceFadeAnimationPlaying(dice) then
        return true
    end
    return false
end

function API.IsDiceRecoveryCooldownActive()
    local now = SuiteNow()
    if now <= 0 then
        return false
    end
    return now < diceRecoveryCooldownUntil
end

function API.NoteDiceRecoveryHide()
    local now = SuiteNow()
    if now > 0 then
        diceRecoveryCooldownUntil = now + DICE_RECOVERY_COOLDOWN_SECONDS
    end
    diceStuckSince = 0
end

function API.MarkLevelUpDiceSettle()
    local now = SuiteNow()
    if now > 0 then
        levelUpSettleUntil = now + DICE_LEVEL_UP_SETTLE_SECONDS
    end
end

local function DiceStuckCandidate(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" or dice.isRapidRolling then
        return false
    end
    if not DiceIsShown(dice) then
        return false
    end
    if API.DiceShouldAcceptClicks(dice) then
        return false
    end
    if API.IsDiceFadingOut(dice) then
        return false
    end
    if API.IsUnlearnOrKeepDecisionPending() then
        return false
    end
    return true
end

local function TrackDiceStuckVisible(dice)
    if DiceStuckCandidate(dice) then
        if diceStuckSince <= 0 then
            diceStuckSince = SuiteNow()
        end
    else
        diceStuckSince = 0
    end
end

-- Shown die with no interactive state lingering after level-up settle (Suite stall).
function API.IsDiceStuckVisibleNonInteractive(dice)
    local now = SuiteNow()
    if now <= 0 then
        return false
    end
    TrackDiceStuckVisible(dice)
    if diceStuckSince <= 0 then
        return false
    end
    if now < levelUpSettleUntil then
        return false
    end
    return (now - diceStuckSince) >= DICE_STUCK_VISIBLE_SECONDS
end

-- Ascension is hiding the die or no roll / keep-vs-unlearn is up — do not re-show.
function API.ShouldLetDiceHide(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return true
    end
    if API.IsDiceFadingOut(dice) then
        return true
    end
    if API.IsUnlearnOrKeepDecisionPending() then
        return false
    end
    if API.DiceShouldAcceptClicks(dice) then
        return false
    end
    if not DiceIsShown(dice) then
        return true
    end
    if dice.isRapidRolling then
        return false
    end
    if not API.CanRollAbilities() then
        return true
    end
    if DiceIsIdle(dice) then
        return true
    end
    return false
end

function API.HideLingeringDice(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end

    API.ClearDiceHoverArtifacts(dice)

    local hidden = false
    if DiceIsShown(dice) and not API.DiceShouldAcceptClicks(dice) then
        if type(dice.Hide) == "function" then
            pcall(dice.Hide, dice)
            hidden = true
        end
    end

    if API.ClearDiceClickStealer(dice) then
        hidden = true
    end

    if hidden then
        API.NoteDiceRecoveryHide()
    end
    return hidden
end

local function MaybeSanitizeDiceHoverAfterRecovery(dice)
    local now = SuiteNow()
    if now > 0 and (now - lastHoverSanitizeAt) < HOVER_SANITIZE_COOLDOWN_SECONDS then
        return false
    end
    if now > 0 then
        lastHoverSanitizeAt = now
    end
    return API.SanitizeDiceHover(dice)
end

local function DiceStrataWasRaised(dice)
    -- Only Suite's own raise flag — Ascension's native strata is FULLSCREEN_DIALOG.
    return type(dice) == "table" and dice._asuiteStrataRaised == true
end

local function FrameIsMouseOver(frame)
    if type(frame) ~= "table" or type(frame.IsMouseOver) ~= "function" then
        return false
    end
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and over == true
end

-- Hide Ascension's dice highlight and any lingering GameTooltip without toggling
-- mouse. Used when Suite disables mouse outside RegisterOnClick/UnregisterOnClick.
function API.ClearDiceHoverArtifacts(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end

    local cleared = false
    local tooltip = _G.GameTooltip
    if type(tooltip) == "table" and type(tooltip.Hide) == "function" then
        pcall(tooltip.Hide, tooltip)
        cleared = true
    end
    local highlight = dice.Highlight
    if type(highlight) == "table" and type(highlight.Hide) == "function" then
        pcall(highlight.Hide, highlight)
        cleared = true
    end
    return cleared
end

-- After mouse/strata recovery, mirror Ascension's RegisterOnClick hover contract:
-- OnLeave when the cursor is elsewhere; OnEnter (or RollButton hover) when over.
function API.SanitizeDiceHover(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end

    local rollButton = dice.RollButton
    local scrollCount = rollButton and rollButton.ScrollCount
    local scrollOver = FrameIsMouseOver(scrollCount)
    local rollOver = FrameIsMouseOver(rollButton)
    local diceOver = FrameIsMouseOver(dice)

    if scrollOver and type(dice.ScrollCountOnEnter) == "function" then
        pcall(dice.ScrollCountOnEnter, dice)
        return true
    end
    if rollOver and type(dice.RollButtonOnEnter) == "function" then
        pcall(dice.RollButtonOnEnter, dice)
        return true
    end
    if diceOver and type(dice.OnEnter) == "function" then
        pcall(dice.OnEnter, dice)
        return true
    end

    if type(dice.OnLeave) == "function" then
        pcall(dice.OnLeave, dice)
        return true
    end

    return API.ClearDiceHoverArtifacts(dice)
end

local function RestoreDiceRollButtonAffordances(dice)
    if type(dice) ~= "table" or not API.IsDiceUnlearnRollOffered(dice) then
        return false
    end

    local restored = false
    local rollButton = dice.RollButton
    if type(rollButton) == "table" then
        if type(rollButton.EnableMouse) == "function" then
            local needsMouse = true
            if type(rollButton.IsMouseEnabled) == "function" then
                local ok, enabled = pcall(rollButton.IsMouseEnabled, rollButton)
                needsMouse = not ok or enabled ~= true
            end
            if needsMouse then
                pcall(rollButton.EnableMouse, rollButton, true)
                restored = true
            end
        end
        local scrollCount = rollButton.ScrollCount
        if type(scrollCount) == "table" and type(scrollCount.EnableMouse) == "function" then
            pcall(scrollCount.EnableMouse, scrollCount, true)
            restored = true
        end
    end

    if type(dice.RefreshScrollOfFortuneRerollDisplay) == "function" then
        pcall(dice.RefreshScrollOfFortuneRerollDisplay, dice)
        return true
    end
    if type(dice.UpdateRollButton) == "function" then
        pcall(dice.UpdateRollButton, dice)
        restored = true
    end
    return restored
end

-- Non-interactive die with mouse on (or Suite-raised strata) steals clicks from
-- Manastorm tracker / other UI. Does not rewrite Ascension's native FULLSCREEN_DIALOG.
function API.ClearDiceClickStealer(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end
    if API.DiceShouldAcceptClicks(dice) then
        return false
    end

    local cleared = false

    API.ClearDiceHoverArtifacts(dice)

    if type(dice.IsMouseEnabled) == "function" and type(dice.EnableMouse) == "function" then
        local mouseOk, enabled = pcall(dice.IsMouseEnabled, dice)
        if mouseOk and enabled == true then
            pcall(dice.EnableMouse, dice, false)
            cleared = true
        end
    end

    if IsSuiteMainWindowShown() and not dice.isRapidRolling and DiceIsShown(dice) then
        if API.DemoteDiceBelowSuite(dice, { skipHoverClear = true }) then
            cleared = true
        end
    elseif DiceStrataWasRaised(dice) then
        if RestoreDiceNativeLayering(dice) then
            cleared = true
        end
    end

    if DiceIsShown(dice) and DiceIsIdle(dice) and not dice.pendingReveal and not dice.isRapidRolling then
        if type(dice.Hide) == "function" then
            pcall(dice.Hide, dice)
            API.NoteDiceRecoveryHide()
            cleared = true
        end
    end

    return cleared
end

-- While /asuite is open, keep the leveling die under the Suite window — never at
-- FULLSCREEN_DIALOG above MainWindow. Rapid-rolling dice stay parented to the
-- Rapid board and are left alone.
function API.DemoteDiceBelowSuite(dice, opts)
    dice = dice or _G.WildCardDice
    opts = opts or {}
    if type(dice) ~= "table" or not DiceIsShown(dice) then
        return false
    end
    if dice.isRapidRolling then
        return false
    end

    CaptureDiceNativeLayering(dice)

    local suiteLevel = SuiteMainWindowFrameLevel()
    local targetLevel = math.max(1, suiteLevel - 2)
    local already = false
    if dice._asuiteDemotedForSuite and type(dice.GetFrameStrata) == "function" then
        local ok, strata = pcall(dice.GetFrameStrata, dice)
        already = ok and strata == DICE_SUITE_STRATA
    end

    if not already then
        if not opts.skipHoverClear then
            API.ClearDiceHoverArtifacts(dice)
        end
        if type(dice.SetFrameStrata) == "function" then
            pcall(dice.SetFrameStrata, dice, DICE_SUITE_STRATA)
        end
        if type(dice.SetFrameLevel) == "function" then
            pcall(dice.SetFrameLevel, dice, targetLevel)
        end
        local rollButton = dice.RollButton
        if type(rollButton) == "table" and type(rollButton.SetFrameLevel) == "function" then
            pcall(rollButton.SetFrameLevel, rollButton, targetLevel + 1)
        end
        dice._asuiteDemotedForSuite = true
        dice._asuiteStrataRaised = nil
    end
    return true
end

function API.SyncDiceLayeringForSuite()
    if not IsSuiteMainWindowShown() then
        return false
    end
    return API.DemoteDiceBelowSuite()
end

local function RaiseDiceAboveClutter(dice)
    if type(dice) ~= "table" or not DiceIsShown(dice) or not API.DiceShouldAcceptClicks(dice) then
        return false
    end
    if dice.isRapidRolling then
        return false
    end

    if IsSuiteMainWindowShown() then
        return API.DemoteDiceBelowSuite(dice, { skipHoverClear = true })
    end

    CaptureDiceNativeLayering(dice)

    local changed = false
    if type(dice.GetFrameStrata) == "function" and type(dice.SetFrameStrata) == "function" then
        local ok, strata = pcall(dice.GetFrameStrata, dice)
        if not ok or strata ~= DICE_DECISION_STRATA then
            pcall(dice.SetFrameStrata, dice, DICE_DECISION_STRATA)
            changed = true
        end
    elseif type(dice.SetFrameStrata) == "function" then
        pcall(dice.SetFrameStrata, dice, DICE_DECISION_STRATA)
        changed = true
    end
    if type(dice.SetFrameLevel) == "function" then
        local ok, level = false, nil
        if type(dice.GetFrameLevel) == "function" then
            ok, level = pcall(dice.GetFrameLevel, dice)
        end
        if not ok or level ~= DICE_DECISION_FRAME_LEVEL then
            pcall(dice.SetFrameLevel, dice, DICE_DECISION_FRAME_LEVEL)
            changed = true
        end
    end
    local rollButton = dice.RollButton
    if type(rollButton) == "table" and type(rollButton.SetFrameLevel) == "function" then
        pcall(rollButton.SetFrameLevel, rollButton, DICE_DECISION_FRAME_LEVEL + 1)
    end
    dice._asuiteStrataRaised = true
    dice._asuiteDemotedForSuite = nil
    return changed or true
end

-- Refresh RollButton state and lift strata for a shown, clickable post-reveal die.
local function SyncDiceDecisionAffordances(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end
    if not DiceIsShown(dice) or not API.DiceShouldAcceptClicks(dice) then
        return false
    end
    if not API.IsDiceRevealedDecisionShown(dice) and not API.IsDiceDecisionPending(dice) then
        return false
    end

    local affordances = RaiseDiceAboveClutter(dice)

    if RestoreDiceRollButtonAffordances(dice) then
        affordances = true
    end

    return affordances
end

-- Character Advancement unlearn / reset confirms from patch-B StaticPopup.lua.
-- PopupAssist must never accept these; Auto-Roll must halt while any is visible.
local UNLEARN_CONFIRM_DIALOGS = {
    CONFIRM_UNLEARN_S = true,
    CONFIRM_UNLEARN_ALL_S = true,
    DRAFT_UNLEARN_CONFIRM = true,
    UNLEARN_SKILL = true,
    UNLEARN_SKILLID = true,
    CONFIRM_RESET_BUILD = true,
    CONFIRM_RESET_BUILD_NO_COST = true,
}

function API.IsUnlearnConfirmDialog(which)
    return UNLEARN_CONFIRM_DIALOGS[which] == true
end

function API.GetUnlearnConfirmDialogs()
    local names = {}
    for name in pairs(UNLEARN_CONFIRM_DIALOGS) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local function StaticPopupFrameText(dialog)
    if type(dialog) ~= "table" then
        return nil
    end
    local textFrame = dialog.text
    if type(textFrame) == "table" and type(textFrame.GetText) == "function" then
        local ok, text = pcall(textFrame.GetText, textFrame)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    return nil
end

function API.StaticPopupTextLooksLikeUnlearnTokenSpend(text)
    if type(text) ~= "string" or text == "" then
        return false
    end
    local lower = string.lower(text)
    if not string.find(lower, "unlearn", 1, true) then
        return false
    end
    if string.find(lower, "scroll of fortune", 1, true) then
        return true
    end
    return false
end

local function DialogLooksLikeUnlearnConfirm(dialog)
    if type(dialog) ~= "table" or not dialog.which then
        return false
    end
    if UNLEARN_CONFIRM_DIALOGS[dialog.which] == true then
        return true
    end
    return API.StaticPopupTextLooksLikeUnlearnTokenSpend(StaticPopupFrameText(dialog))
end

function API.IsUnlearnConfirmVisible()
    local findVisible = _G.StaticPopup_FindVisible
    if type(findVisible) == "function" then
        for name in pairs(UNLEARN_CONFIRM_DIALOGS) do
            local dialog = findVisible(name)
            if type(dialog) == "table" and dialog.which == name then
                return true, name
            end
        end
    end

    local numDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
    for index = 1, numDialogs do
        local dialog = _G["StaticPopup" .. index]
        if type(dialog) == "table" and type(dialog.IsShown) == "function" then
            local shownOk, shown = pcall(dialog.IsShown, dialog)
            if shownOk and shown == true and DialogLooksLikeUnlearnConfirm(dialog) then
                return true, dialog.which
            end
        end
    end
    return false
end

-- Cancel button only — never Accept / Unlearn (SECURITY.md).
function API.CancelVisibleUnlearnConfirm()
    local visible, which = API.IsUnlearnConfirmVisible()
    if not visible then
        return false
    end

    local dialog
    local findVisible = _G.StaticPopup_FindVisible
    if which and type(findVisible) == "function" then
        dialog = findVisible(which)
    end

    if type(dialog) ~= "table" then
        local numDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
        for index = 1, numDialogs do
            local frame = _G["StaticPopup" .. index]
            if type(frame) == "table" and type(frame.IsShown) == "function" then
                local shownOk, shown = pcall(frame.IsShown, frame)
                if shownOk and shown == true and DialogLooksLikeUnlearnConfirm(frame) then
                    dialog = frame
                    which = frame.which
                    break
                end
            end
        end
    end

    if type(dialog) ~= "table" then
        return false
    end

    local onClick = _G.StaticPopup_OnClick
    if type(onClick) == "function" then
        local ok = pcall(onClick, dialog, 2)
        if ok then
            return true, which
        end
    end

    local hide = _G.StaticPopup_Hide
    if type(hide) == "function" then
        local ok = pcall(hide, dialog)
        if ok then
            return true, which
        end
    end
    return false
end

function API.IsDiceDecisionPending(dice)
    local state, states = GetDiceCoreState(dice)
    if state and states then
        return state == states.DECISION_PENDING
    end
    return false
end

-- Leveling die RollButton (Unlearn and Roll) is only shown for keep-vs-unlearn.
function API.IsDiceUnlearnRollOffered(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" or dice.isRapidRolling then
        return false
    end
    local rollButton = dice.RollButton
    if type(rollButton) ~= "table" or type(rollButton.IsVisible) ~= "function" then
        return false
    end
    local ok, visible = pcall(rollButton.IsVisible, rollButton)
    return ok and visible == true
end

function API.IsRapidRollingWaitingForUnlearn(state)
    state = state or API.GetRapidRollingState()
    return state and state.Phase == "WaitingForUnlearn"
end

-- Keep-vs-unlearn / Scroll-of-Fortune spend is up: DECISION_PENDING die, visible
-- CONFIRM_UNLEARN_*, Rapid WaitingForUnlearn, or the leveling RollButton offer.
function API.IsUnlearnOrKeepDecisionPending()
    if API.IsUnlearnConfirmVisible() then
        return true
    end
    if API.IsDiceKeepOrUnlearnDecisionUp() then
        return true
    end
    if API.IsDiceDecisionPending() then
        return true
    end
    if API.IsRapidRollingWaitingForUnlearn() then
        return true
    end
    if API.IsDiceUnlearnRollOffered() and DiceIsShown() then
        return true
    end
    return false
end

-- READY_TO_ROLL (golden d20), DECISION_PENDING (confirm/reroll), and a visually
-- revealed decision (icon/name frame) are clickable. Animation skip can strand
-- Core in REVEALING while SetInternalID already rendered the spell icon.
function API.DiceShouldAcceptClicks(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end

    local state, states = GetDiceCoreState(dice)
    if state and states then
        if state == states.READY_TO_ROLL or state == states.DECISION_PENDING then
            return true
        end
        if state == states.REVEALING and API.IsDiceRevealedDecisionShown(dice) then
            return true
        end
        return false
    end

    if API.IsDiceRevealedDecisionShown(dice) then
        return true
    end

    if dice.RollButton and type(dice.RollButton.IsVisible) == "function" then
        local ok, visible = pcall(dice.RollButton.IsVisible, dice.RollButton)
        if ok and visible == true then
            return true
        end
    end

    if dice.DiceEmptyEnter and type(dice.DiceEmptyEnter.IsShown) == "function" then
        local ok, shown = pcall(dice.DiceEmptyEnter.IsShown, dice.DiceEmptyEnter)
        if ok and shown == true and not dice.pendingReveal then
            return true
        end
    end

    return false
end

function API.IsDiceShownUnclickable()
    local dice = _G.WildCardDice
    if type(dice) ~= "table" or type(dice.IsShown) ~= "function" then
        return false
    end
    local shownOk, shown = pcall(dice.IsShown, dice)
    if not shownOk or shown ~= true then
        return false
    end
    if not API.DiceShouldAcceptClicks(dice) then
        return false
    end
    if type(dice.IsMouseEnabled) ~= "function" then
        return false
    end
    local mouseOk, enabled = pcall(dice.IsMouseEnabled, dice)
    return mouseOk and enabled == false
end

-- Single mode resolver for DiceGuard / AnimationSkip / Unstick. Prefer this over
-- stacking independent Ensure / Clear / Demote calls every frame.
-- Modes: none | rapid | hide_linger | let_hide | demote | heal | clear_stealer | ok
function API.ResolveDiceGuardMode(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return "none"
    end
    if dice.isRapidRolling then
        if API.IsDiceShownUnclickable() then
            return "heal"
        end
        return "rapid"
    end
    if API.IsDiceStuckVisibleNonInteractive(dice) then
        return "hide_linger"
    end
    if API.ShouldLetDiceHide(dice) then
        return "let_hide"
    end
    if IsSuiteMainWindowShown() and DiceIsShown(dice) then
        if API.DiceShouldAcceptClicks(dice) and API.IsDiceShownUnclickable() then
            return "heal"
        end
        return "demote"
    end
    if API.IsDiceRecoveryCooldownActive() then
        if DiceIsShown(dice) and API.DiceShouldAcceptClicks(dice) and not API.IsDiceFadingOut(dice) then
            return "heal"
        end
        return "clear_stealer"
    end
    if DiceIsShown(dice) and API.DiceShouldAcceptClicks(dice) then
        if API.IsDiceFadingOut(dice) then
            return "let_hide"
        end
        if API.IsDiceShownUnclickable() then
            return "heal"
        end
        if API.IsDiceRevealedDecisionShown(dice) or API.IsDiceDecisionPending(dice) then
            return "heal"
        end
        return "ok"
    end
    return "clear_stealer"
end

-- Re-enable mouse / visibility on a shown die that should accept clicks but does
-- not. Never auto-presses Unlearn, Lock, or ConfirmOrUnlearnID. Refreshes native
-- RollButton enablement and raises strata when a post-reveal decision is shown.
function API.EnsureDiceClickable()
    local dice = _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end

    local mode = API.ResolveDiceGuardMode(dice)

    if mode == "none" or mode == "rapid" or mode == "ok" then
        if mode == "ok" and IsSuiteMainWindowShown() then
            return API.DemoteDiceBelowSuite(dice, { skipHoverClear = true })
        end
        return false
    end

    if mode == "hide_linger" then
        return API.HideLingeringDice(dice)
    end

    if mode == "let_hide" then
        local cleared = API.ClearDiceClickStealer(dice)
        API.ClearDiceHoverArtifacts(dice)
        if cleared then
            API.NoteDiceRecoveryHide()
        end
        return cleared
    end

    if mode == "clear_stealer" then
        return API.ClearDiceClickStealer(dice)
    end

    if mode == "demote" then
        return API.DemoteDiceBelowSuite(dice)
    end

    -- mode == "heal"
    if not API.DiceShouldAcceptClicks(dice) then
        return API.ClearDiceClickStealer(dice)
    end
    if API.IsDiceFadingOut(dice) then
        return API.ClearDiceClickStealer(dice)
    end

    local healed = false
    local shownOk, shown = false, false
    if type(dice.IsShown) == "function" then
        shownOk, shown = pcall(dice.IsShown, dice)
    end

    if shownOk and shown == true then
        local needsMouse = API.IsDiceShownUnclickable()
        if needsMouse then
            if type(dice.RegisterOnClick) == "function" then
                pcall(dice.RegisterOnClick, dice)
            elseif type(dice.EnableMouse) == "function" then
                pcall(dice.EnableMouse, dice, true)
            end

            if type(dice.GetAlpha) == "function" and type(dice.SetAlpha) == "function" then
                local alphaOk, alpha = pcall(dice.GetAlpha, dice)
                if alphaOk and (not alpha or alpha < 0.1) then
                    pcall(dice.SetAlpha, dice, 1)
                end
            end

            healed = true
        end
    end

    local affordances = SyncDiceDecisionAffordances(dice)
    if IsSuiteMainWindowShown() and not dice.isRapidRolling and DiceIsShown(dice) then
        API.DemoteDiceBelowSuite(dice, { skipHoverClear = true })
    end
    if healed or affordances then
        MaybeSanitizeDiceHoverAfterRecovery(dice)
    end
    return healed or affordances == true
end

-- After /asuite closes, put a Suite-demoted leveling die back at Ascension native
-- layering and re-heal mouse if the player still needs to click Continue / roll.
function API.RestoreDiceAfterSuite(dice)
    if IsSuiteMainWindowShown() then
        return false
    end
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" or not dice._asuiteDemotedForSuite then
        return false
    end

    API.ClearDiceHoverArtifacts(dice)
    local restored = RestoreDiceNativeLayering(dice)
    if DiceIsShown(dice) and API.DiceShouldAcceptClicks(dice) then
        if API.IsDiceShownUnclickable() then
            if type(dice.RegisterOnClick) == "function" then
                pcall(dice.RegisterOnClick, dice)
            elseif type(dice.EnableMouse) == "function" then
                pcall(dice.EnableMouse, dice, true)
            end
            restored = true
        end
        if SyncDiceDecisionAffordances(dice) then
            restored = true
        end
    end
    return restored
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
    if API.IsUnlearnOrKeepDecisionPending() then
        return true, "unlearn_decision"
    end

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

-- Gray Continue / die stuck on "?" — not a healthy in-flight reveal and not an
-- actionable Continue or terminal result. Used by the opt-in auto-unstick assist
-- and distinct from a normal Revealing phase that IsInFlight covers.
function API.IsRapidRollingContinueStuck(state)
    if not API.IsWildcardModeActive() then
        return false
    end
    if not API.IsRapidRollingFrameShown() then
        return false
    end
    state = state or API.GetRapidRollingState()
    if IsInFlight(state) then
        return false
    end
    if IsAwaitingContinue(state) or IsTerminal(state) then
        return false
    end
    return API.IsRapidRollingDiceActive(state) == true
end

-- Gray Continue or a shown leveling die that should accept clicks but does not.
function API.IsDiceInteractionStuck(state)
    if not API.IsWildcardModeActive() then
        return false
    end
    if API.IsDiceShownUnclickable() then
        return true
    end
    return API.IsRapidRollingContinueStuck(state) == true
end

-- Break out of a stranded Rapid session (gray Continue / die stuck on ?).
-- Cancels the server session, clears local pendingReveal, hides the die, and puts
-- the Rapid window back in a state where its own Roll button works again.
--
-- The order mirrors Ascension's own terminal-session teardown in
-- WildCardRapidRollingMixin:Roll: completingSession is raised *before* the cancel so
-- the ROLL_ABILITIES_NO_ROLL the server answers a cancelled session with does not
-- surface as a red error the player has to dismiss. Ascension clears the flag itself
-- on the next Roll and on OnShow, so it never outlives the recovery.
function API.RecoverStuckRapidSession()
    local ok, reason = RequireWildcard()
    if not ok then
        return false, reason
    end

    if API.IsUnlearnOrKeepDecisionPending() then
        return false, "unlearn_decision"
    end

    local frame = RapidRollingFrame()
    if type(frame) == "table" then
        frame.completingSession = true
    end

    API.CancelRapidRolling()

    local dice = _G.WildCardDice
    if type(dice) == "table" then
        dice.pendingReveal = nil
        API.ClearDiceClickStealer(dice)
        if type(dice.Hide) == "function" then
            pcall(dice.Hide, dice)
        end
    end

    if type(frame) == "table" then
        -- Roll() unregisters TOKEN_UPDATED for the duration of a roll and never
        -- re-registers it when the session strands, so the scroll counters stay
        -- frozen until the window is reopened.
        if type(frame.RegisterEvent) == "function" then
            pcall(frame.RegisterEvent, frame, "TOKEN_UPDATED")
        end

        local rolling = frame.RollingFrame
        local errorFrame = rolling and rolling.ErrorFrame
        if type(errorFrame) == "table" and type(errorFrame.Hide) == "function" then
            pcall(errorFrame.Hide, errorFrame)
        end

        if type(frame.UpdateRollButton) == "function" then
            pcall(frame.UpdateRollButton, frame)
        elseif type(frame.Refresh) == "function" then
            pcall(frame.Refresh, frame)
        end

        -- Roll() disables the button by hand. UpdateRollButton normally re-enables
        -- it, but only when it agrees a roll can start; if it left the button dead
        -- while the client says otherwise, the player is still stuck.
        local rollButton = rolling and rolling.RollButton
        if type(rollButton) == "table" and type(rollButton.IsEnabled) == "function" then
            local enabledOk, enabled = pcall(rollButton.IsEnabled, rollButton)
            if enabledOk and not enabled and API.CanStartRapidRolling() == true then
                if type(rollButton.Enable) == "function" then
                    pcall(rollButton.Enable, rollButton)
                elseif type(rollButton.SetEnabled) == "function" then
                    pcall(rollButton.SetEnabled, rollButton, true)
                end
            end
        end
    end
    return true
end

-- Shared recovery for manual Unstick, auto-unstick, and level-up guards: restore
-- mouse on a stranded leveling die first; fall back to the Rapid session reset.
function API.RecoverDiceInteraction()
    local ok, reason = RequireWildcard()
    if not ok then
        return false, reason
    end

    if API.ClearDiceClickStealer() then
        return true, "click_stealer_cleared"
    end

    if API.EnsureDiceClickable() then
        return true, "mouse_restored"
    end

    if API.IsRapidRollingContinueStuck() then
        if API.RecoverStuckRapidSession() then
            return true, "rapid_session_cleared"
        end
        return false, "recover_failed"
    end

    local dice = _G.WildCardDice
    if type(dice) == "table" and type(dice.IsShown) == "function" then
        local shownOk, shown = pcall(dice.IsShown, dice)
        if shownOk and shown == true and API.DiceShouldAcceptClicks(dice) then
            if type(dice.RegisterOnClick) == "function" then
                pcall(dice.RegisterOnClick, dice)
            elseif type(dice.EnableMouse) == "function" then
                pcall(dice.EnableMouse, dice, true)
            end
            if type(dice.SetAlpha) == "function" then
                pcall(dice.SetAlpha, dice, 1)
            end
            SyncDiceDecisionAffordances(dice)
            MaybeSanitizeDiceHoverAfterRecovery(dice)
            if type(dice.IsMouseEnabled) == "function" then
                local mouseOk, enabled = pcall(dice.IsMouseEnabled, dice)
                if mouseOk and enabled == true then
                    return true, "mouse_forced"
                end
            end
        end
    end

    return false, "nothing_to_recover"
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

    if API.IsUnlearnOrKeepDecisionPending() then
        return false, "unlearn_decision"
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

------------------------------------------------------------------------
-- BuildCreator / BuildEditor import (read-only; no Publish / Draft purchase)
------------------------------------------------------------------------

local function BC()
    return Namespace("C_BuildCreator")
end

local function BE()
    return Namespace("C_BuildEditor")
end

local function BD()
    return Namespace("C_BuildDraft")
end

function API.GetActiveBuildID()
    local bc = BC()
    if not bc then
        return nil
    end

    local specId
    local specUtil = Namespace("SpecializationUtil")
    if specUtil and type(specUtil.GetActiveSpecialization) == "function" then
        local ok, value = pcall(specUtil.GetActiveSpecialization)
        if ok then
            specId = value
        end
    end

    local buildId = Call(bc, { "GetActiveBuild" }, specId)
    if type(buildId) == "string" and buildId ~= "" then
        return buildId
    end
    return nil
end

function API.GetDraftedBuildID()
    local bd = BD()
    if not bd then
        return nil
    end
    local buildId = Call(bd, { "GetDraftedBuild" })
    if type(buildId) == "string" and buildId ~= "" then
        return buildId
    end
    return nil
end

function API.GetBuildByID(buildId)
    if type(buildId) ~= "string" or buildId == "" then
        return nil
    end
    local bc = BC()
    if not bc then
        return nil
    end
    return TableOrNil(Call(bc, { "GetBuild" }, buildId))
end

-- Prefer the editor's pending build, then drafted, then the active archetype.
function API.GetImportableBuild()
    local be = BE()
    if be then
        local pending = TableOrNil(Call(be, { "GetPendingBuild" }))
        if pending and type(pending.Spells) == "table" and #pending.Spells > 0 then
            return pending, "editor"
        end
    end

    local draftedId = API.GetDraftedBuildID()
    if draftedId then
        local build = API.GetBuildByID(draftedId)
        if build then
            return build, "draft"
        end
    end

    local activeId = API.GetActiveBuildID()
    if activeId then
        local build = API.GetBuildByID(activeId)
        if build then
            return build, "active"
        end
    end

    return nil, "no_build"
end

function API.DescribeImportableBuildFailure(reason)
    if reason == "no_build" then
        return "No importable build — open Archetypes in the editor, draft one, or activate a build first."
    end
    return "No importable build available."
end

function API.UnpackBuildDescription(description)
    local sections = {}
    if type(description) ~= "string" or description == "" then
        return sections
    end

    for section in description:gmatch("###%s*([^#]*)") do
        local header, text = section:match("^([^\n]*)\n?(.*)\n*$")
        if header and header ~= "" then
            text = (text or ""):gsub("{HT}", "#")
            text = text:match("^%s*(.-)%s*$") or text
            sections[header] = text
        end
    end
    return sections
end

local function FormatEnumLabel(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    local label = value:gsub("_", " ")
    label = label:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return label
end

function API.DescribeBuildCategory(category)
    if category == nil then
        return nil
    end
    if type(category) == "string" then
        if _G.Enum and _G.Enum.BuildCategory and _G.Enum.BuildCategory[category] ~= nil then
            category = _G.Enum.BuildCategory[category]
        end
    end
    if type(category) == "number" and _G.Enum and type(_G.Enum.BuildCategory) == "table" then
        for name, enumValue in pairs(_G.Enum.BuildCategory) do
            if enumValue == category then
                local parent = nil
                if _G.Enum.BuildSubCategory and _G.Enum.BuildSubCategory[name] then
                    parent = _G.Enum.BuildSubCategory[name]
                end
                if parent and _G.Enum.BuildSubCategory and type(_G.Enum.BuildSubCategory) == "table" then
                    for parentName, parentValue in pairs(_G.Enum.BuildSubCategory) do
                        if parentValue == parent then
                            if parentName == "PvE" or parentName == "PvP" then
                                return parentName
                            end
                        end
                    end
                end
                if name:find("PvE") then
                    return "PvE"
                end
                if name:find("PvP") then
                    return "PvP"
                end
                return FormatEnumLabel(name)
            end
        end
    end
    return FormatEnumLabel(tostring(category))
end

function API.DescribeBuildDifficulty(difficulty)
    if difficulty == nil then
        return nil
    end
    if type(difficulty) == "number" and _G.Enum and type(_G.Enum.BuildDifficulty) == "table" then
        for name, enumValue in pairs(_G.Enum.BuildDifficulty) do
            if enumValue == difficulty then
                return FormatEnumLabel(name)
            end
        end
    end
    if type(difficulty) == "string" then
        return FormatEnumLabel(difficulty)
    end
    return tostring(difficulty)
end

function API.GetBuildSpellTags(buildId, spellId)
    local id = tonumber(spellId)
    if type(buildId) ~= "string" or buildId == "" or not id then
        return {}
    end
    local bc = BC()
    if not bc then
        return {}
    end
    local spellData = TableOrNil(Call(bc, { "GetSpell" }, buildId, id))
    if type(spellData) ~= "table" then
        return {}
    end
    return {
        core = spellData.IsCoreAbility == true,
        optimal = spellData.IsOptimalAbility == true,
        empowering = spellData.IsEmpoweringAbility == true,
        synergistic = spellData.IsSynergisticAbility == true,
    }
end

local function ClassSpecLabel(classValue, specValue)
    local classLabel = classValue
    local specLabel = specValue

    local util = Namespace("CharacterAdvancementUtil")
    if util then
        local classFn = Method(util, { "GetClassFileByDBC" })
        if classFn and classValue ~= nil then
            local ok, resolved = pcall(classFn, classValue)
            if ok and type(resolved) == "string" and resolved ~= "" then
                classLabel = resolved
            end
        end
        local specFn = Method(util, { "GetSpecFileByDBC" })
        if specFn and specValue ~= nil then
            local ok, resolved = pcall(specFn, specValue)
            if ok and type(resolved) == "string" and resolved ~= "" then
                specLabel = resolved
            end
        end
    end

    if type(classLabel) == "number" and _G.Enum and type(_G.Enum.Class) == "table" then
        for name, enumValue in pairs(_G.Enum.Class) do
            if enumValue == classLabel then
                classLabel = FormatEnumLabel(name)
                break
            end
        end
    end

    if type(specLabel) == "number" and _G.Enum and type(_G.Enum.Spec) == "table" then
        for name, enumValue in pairs(_G.Enum.Spec) do
            if enumValue == specLabel then
                specLabel = FormatEnumLabel(name)
                break
            end
        end
    end

    classLabel = FormatEnumLabel(tostring(classLabel or ""))
    specLabel = FormatEnumLabel(tostring(specLabel or ""))

    if specLabel and specLabel ~= "" and classLabel and classLabel ~= "" then
        return specLabel .. " " .. classLabel
    end
    if classLabel and classLabel ~= "" then
        return classLabel
    end
    if specLabel and specLabel ~= "" then
        return specLabel
    end
    return nil
end

function API.GetSpellClassGroup(spellId)
    local id = tonumber(spellId)
    if not id then
        return nil
    end
    local ca = CA()
    if not ca then
        return nil
    end
    local classValue, specValue = Call(ca, { "GetClassInfo" }, id)
    return ClassSpecLabel(classValue, specValue)
end

local function EntryFromBuildSpell(build, spellRow)
    if type(spellRow) ~= "table" then
        return nil
    end
    local spellId = FirstNumber(spellRow.Spell, spellRow.spell, spellRow.SpellID, spellRow.spellID)
    if not spellId then
        return nil
    end

    -- Match native RapidRollingSpells: spell-first lookup yields the correct Type.
    local entry = API.GetEntryBySpellID(spellId) or API.ResolveEntry(spellId)
    local entryId, entryType = EntryPair(entry)
    if not entryId then
        local ca = CA()
        if ca then
            entryId = FirstNumber(Call(ca, { "GetInternalID" }, spellId))
            if entryId then
                local internalEntry = API.GetEntryByInternalID(entryId)
                local internalId, internalType = EntryPair(internalEntry)
                if internalId and internalType then
                    entryId = internalId
                    entryType = internalType
                else
                    entryType = entryType or "Ability"
                end
            end
        end
    end

    local tags = API.GetBuildSpellTags(build.ID, spellId)
    local name = FirstString(spellRow.Name, spellRow.name)
    if not name then
        name = API.GetEntryName(spellId)
    end

    return {
        entryId = entryId,
        entryType = entryType,
        spellId = spellId,
        name = name,
        tags = tags,
        classGroup = API.GetSpellClassGroup(spellId),
        desired = tags.core == true,
    }
end

-- Read spells from a native build table without touching Publish / purchase APIs.
function API.CollectBuildSpellEntries(build)
    if type(build) ~= "table" or type(build.Spells) ~= "table" then
        return {}
    end

    local entries = {}
    local seen = {}
    for index = 1, #build.Spells do
        local row = EntryFromBuildSpell(build, build.Spells[index])
        if row and API.IsDesiredEligibleType(row.entryType) then
            local key = (row.entryType or "?") .. ":" .. tostring(row.entryId or row.spellId)
            if not seen[key] then
                seen[key] = true
                entries[#entries + 1] = row
            end
        end
    end
    return entries
end

local EQUIPMENT_TYPE_ALIASES = {
    Plate = "ITEM_SUBCLASS_ARMOR_PLATE",
    Mail = "ITEM_SUBCLASS_ARMOR_MAIL",
    Leather = "ITEM_SUBCLASS_ARMOR_LEATHER",
    Cloth = "ITEM_SUBCLASS_ARMOR_CLOTH",
    Shield = "ITEM_SUBCLASS_ARMOR_SHIELD",
}

function API.NormalizeEquipmentTypeKey(value)
    if type(value) == "table" then
        value = value.Type or value.type
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if EQUIPMENT_TYPE_ALIASES[value] then
        return EQUIPMENT_TYPE_ALIASES[value]
    end
    if value:find("ITEM_SUBCLASS_") then
        return value
    end
    local underscored = "ITEM_SUBCLASS_" .. value:upper():gsub("%s+", "_")
    if _G.Enum and _G.Enum.ArmorSubClassSID and _G.Enum.ArmorSubClassSID[underscored] then
        return underscored
    end
    if _G.Enum and _G.Enum.WeaponSubClassSID and _G.Enum.WeaponSubClassSID[underscored] then
        return underscored
    end
    return value
end

function API.NormalizeEquipmentStub(item)
    if type(item) == "table" then
        local typeKey = API.NormalizeEquipmentTypeKey(item.Type or item.type)
        local comment = item.Comment or item.comment
        if type(comment) ~= "string" then
            comment = ""
        end
        return typeKey, comment
    end
    if type(item) == "string" then
        return API.NormalizeEquipmentTypeKey(item), ""
    end
    return nil, ""
end

function API.GetEquipmentTypeIconAndName(typeKey)
    typeKey = API.NormalizeEquipmentTypeKey(typeKey)
    if not typeKey then
        return nil, nil, false
    end

    local spellId = nil
    local isArmor = false
    if _G.Enum and type(_G.Enum.ArmorSubClassSID) == "table" then
        spellId = _G.Enum.ArmorSubClassSID[typeKey]
        if spellId then
            isArmor = true
        end
    end
    if not spellId and _G.Enum and type(_G.Enum.WeaponSubClassSID) == "table" then
        spellId = _G.Enum.WeaponSubClassSID[typeKey]
    end

    local name = FormatEnumLabel(typeKey)
    local icon = PLACEHOLDER_ICON
    if spellId and type(_G.GetSpellInfo) == "function" then
        local spellName, _, spellIcon = _G.GetSpellInfo(spellId)
        if type(spellName) == "string" and spellName ~= "" then
            name = spellName
        end
        if type(spellIcon) == "string" and spellIcon ~= "" then
            icon = spellIcon
        end
    end
    return name, icon, isArmor
end

function API.CollectBuildEquipmentStubs(build)
    if type(build) ~= "table" then
        return { armorTypes = {}, weaponTypes = {} }
    end
    local armorTypes = {}
    local weaponTypes = {}
    if type(build.ArmorTypes) == "table" then
        for index = 1, #build.ArmorTypes do
            local typeKey, comment = API.NormalizeEquipmentStub(build.ArmorTypes[index])
            if typeKey then
                armorTypes[#armorTypes + 1] = { type = typeKey, comment = comment or "" }
            end
        end
    end
    if type(build.WeaponTypes) == "table" then
        for index = 1, #build.WeaponTypes do
            local typeKey, comment = API.NormalizeEquipmentStub(build.WeaponTypes[index])
            if typeKey then
                weaponTypes[#weaponTypes + 1] = { type = typeKey, comment = comment or "" }
            end
        end
    end
    return { armorTypes = armorTypes, weaponTypes = weaponTypes }
end
