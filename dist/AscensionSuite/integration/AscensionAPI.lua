-- AscensionSuite: integration/AscensionAPI.lua
-- The only first-party file that may reference C_* globals.
-- Read-only entry/spell presentation for v0.1.0; roll starters arrive in step 8.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

AscensionSuite.AscensionAPI = {}
local API = AscensionSuite.AscensionAPI

local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

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
        return unpack(results)
    end

    local results2 = { pcall(fn, ...) }
    if results2[1] then
        return unpack(results2)
    end

    return false
end

local ENTRY_BY_INTERNAL_ID = { "GetEntryByInternalID", "GetEntryByInternalId", "GetEntry" }
local ENTRY_BY_SPELL_ID = { "GetEntryBySpellID", "GetEntryBySpellId", "GetEntryForSpell" }

local GAME_MODE_GET = { "Get", "GetGameMode", "GetActiveGameMode" }
local GAME_MODE_IS = { "Is", "IsGameMode", "IsActiveGameMode" }

local function TableOrNil(ok, value)
    if not ok or type(value) ~= "table" then
        return nil
    end
    return value
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
    local ok, value = Call(gm, GAME_MODE_GET)
    if ok then
        return value
    end
    ok, value = Call(gm, GAME_MODE_IS)
    if ok then
        return value
    end
    return nil
end

function API.IsGameModeActive(modeName)
    if modeName == nil then
        return false
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
-- Step 8 — roll / rapid wrappers (stubs; do not call RollAbilities yet)
------------------------------------------------------------------------

-- function API.RollAbilities(...)
--     -- step 8: opt-in Auto-Roll only; C_GameMode gated; player-selected targets.
-- end

-- function API.StartRapidRolling(...)
--     -- step 8
-- end

-- function API.ContinueRapidRolling(...)
--     -- step 8
-- end

-- function API.CancelRapidRolling(...)
--     -- step 8
-- end
