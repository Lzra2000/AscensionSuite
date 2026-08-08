-- AscensionSuite: tests/test_gamemode_enum.lua
-- C_GameMode:IsGameModeActive expects Enum.GameMode flags, not strings.

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
        None = 0x00,
        WildCard = 0x40,
    },
}

local activeMask = 0x40

function GetCustomGameMode()
    return activeMask
end

bit = {
    contains = function(mask, flag)
        return bit.band(mask, flag) == flag
    end,
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
}

C_GameMode = {
    IsGameModeActive = function(_, mode)
        return bit.contains(activeMask, mode)
    end,
    GetActiveGameModes = function()
        if bit.contains(activeMask, Enum.GameMode.WildCard) then
            return { WildCard = true, None = nil }
        end
        return { None = true }
    end,
}

dofile(ROOT .. "/integration/AscensionAPI.lua")

local API = AscensionSuite.AscensionAPI
assert(API, "AscensionAPI missing")

assert(API.IsGameModeActive("WildCard") == true,
    "string WildCard resolves to Enum.GameMode.WildCard for IsGameModeActive")
assert(API.IsWildcardModeActive() == true, "Wildcard mode is detected through the enum seam")

activeMask = 0x00
assert(API.IsWildcardModeActive() == false, "non-Wildcard masks read as inactive")

activeMask = 0x40
assert(API.IsGameModeActive("Wildcard") == true,
    "Wildcard spelling alias still resolves to WildCard")

print("OK: AscensionSuite gamemode enum test passed")
