-- AscensionSuite: tests/test_load.lua
-- Minimal stub environment; loads every shipped Lua file in TOC order.

unpack = unpack or table.unpack

local ADDON_NAME = "AscensionSuite"

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

AscensionSuite = AscensionSuite or {}
AscensionSuiteDB = AscensionSuiteDB or {}

local function Noop() end

local function NewFrame()
    local frame = {
        _scripts = {},
        _shown = false,
        _width = 64,
        _height = 64,
        _points = {},
    }

    local function Index(_, key)
        if key == "RegisterEvent" or key == "UnregisterEvent" or key == "UnregisterAllEvents" then
            return Noop
        elseif key == "SetScript" then
            return function(self, event, fn)
                self._scripts[event] = fn
            end
        elseif key == "GetScript" then
            return function(self, event)
                return self._scripts[event]
            end
        elseif key == "Show" then
            return function(self) self._shown = true end
        elseif key == "Hide" then
            return function(self) self._shown = false end
        elseif key == "IsShown" then
            return function(self) return self._shown end
        elseif key == "SetSize" or key == "SetWidth" or key == "SetHeight" then
            return function(self, w, h)
                if h then
                    self._width, self._height = w, h
                else
                    self._width = w
                end
            end
        elseif key == "GetWidth" then
            return function(self) return self._width end
        elseif key == "GetHeight" then
            return function(self) return self._height end
        elseif key == "EnableMouse" or key == "RegisterForDrag" or key == "SetMovable"
            or key == "StartMoving" or key == "StopMovingOrSizing" or key == "ClearAllPoints"
            or key == "SetPoint" or key == "SetAutoFocus" or key == "ClearFocus"
            or key == "SetNumeric" or key == "SetMaxLetters" or key == "SetTexCoord"
            or key == "SetJustifyH" or key == "SetTextColor" or key == "SetEnabled" then
            return Noop
        elseif key == "SetBackdrop" then
            return Noop
        elseif key == "CreateTexture" then
            return function()
                return {
                    SetAllPoints = Noop,
                    SetPoint = Noop,
                    SetTexture = Noop,
                    SetTexCoord = Noop,
                    SetWidth = Noop,
                    SetHeight = Noop,
                    Show = Noop,
                    Hide = Noop,
                }
            end
        elseif key == "CreateFontString" then
            return function()
                local text = ""
                local shown = true
                return {
                    SetPoint = Noop,
                    SetText = function(_, value) text = value or "" end,
                    GetText = function() return text end,
                    SetJustifyH = Noop,
                    SetTextColor = Noop,
                    SetWidth = Noop,
                    Show = function() shown = true end,
                    Hide = function() shown = false end,
                }
            end
        elseif key == "CreateFrame" then
            return function(_, childName, parent, template)
                local child = NewFrame()
                child._name = childName
                child._parent = parent
                child._template = template
                return child
            end
        elseif key == "SetText" then
            return function(self, value) self._text = value end
        elseif key == "GetText" then
            return function(self) return self._text or "" end
        elseif key == "SetOwner" or key == "ClearLines" or key == "AddLine" then
            return Noop
        elseif key == "SetSpellByID" then
            return function(self, spellId) self._spellId = spellId end
        elseif key == "SetHyperlink" then
            return function(self, link) self._hyperlink = link end
        elseif key == "GetChecked" or key == "SetChecked" then
            return Noop
        end
        return Noop
    end

    return setmetatable(frame, { __index = Index })
end

CreateFrame = function(kind, name, parent, template)
    local frame = NewFrame()
    frame._kind = kind
    frame._name = name
    frame._parent = parent
    frame._template = template
    return frame
end

UIParent = NewFrame()
GameTooltip = NewFrame()
hooksecurefunc = function() end
StaticPopup_Show = function() end

SLASH_ASUITE1 = nil
SlashCmdList = SlashCmdList or {}

function GetSpellInfo(spellId)
    return "Test Spell " .. tostring(spellId), "Rank 1", nil, "10 Mana", nil, nil, 1500, 0, 30
end

C_GameMode = {
    IsGameModeActive = function(_, mode)
        return mode == "WildCard"
    end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        return {
            ID = id + 1000,
            Name = "CA Entry " .. tostring(id),
            Icon = "Interface\\Icons\\Spell_Nature_Lightning",
            Description = "From C_CharacterAdvancement",
            Type = "Ability",
            Spell = id,
        }
    end,
    GetKnownSpellEntries = function()
        return {}
    end,
    GetKnownTalentEntries = function()
        return {}
    end,
}

C_Wildcard = {
    CanAddDesiredID = function() return true end,
    AddDesiredID = function() return true end,
    RemoveDesiredID = function() return true end,
    IsDesiredID = function() return false end,
    ClearDesiredSpells = function() return true end,
    GetNumFilteredDesiredEntries = function() return 0 end,
    CanRollAbilities = function() return false end,
}

-- Load exactly what the TOC loads, in TOC order, so this test cannot drift from
-- the shipped addon.
local files = {}
local toc = assert(io.open(ROOT .. "/AscensionSuite.toc", "r"), "AscensionSuite.toc missing")
for line in toc:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():match("%.lua$") then
        files[#files + 1] = line:gsub("\\", "/")
    end
end
toc:close()

assert(#files > 0, "AscensionSuite.toc lists no Lua files")

------------------------------------------------------------------------
-- One version, in every place that states one
--
-- The TOC is what the client reads, Bootstrap is what the /asuite title bar
-- shows, and the CHANGELOG heading is what release.sh looks for. A release that
-- bumps two of the three ships a window claiming the wrong version.
------------------------------------------------------------------------

local function ReadFile(path)
    local handle = assert(io.open(path, "r"), path .. " missing")
    local text = handle:read("*a")
    handle:close()
    return text
end

local tocVersion = ReadFile(ROOT .. "/AscensionSuite.toc"):match("##%s*Version:%s*([%d%.]+)")
assert(tocVersion, "AscensionSuite.toc has no ## Version:")

local changelogVersion = ReadFile(ROOT .. "/CHANGELOG.md"):match("###%s+([%d%.]+)%s")
assert(changelogVersion == tocVersion,
    "CHANGELOG.md's newest entry is " .. tostring(changelogVersion) .. ", the TOC says " .. tocVersion)

assert(ReadFile(ROOT .. "/README.md"):find("v" .. tocVersion, 1, true),
    "README.md does not mention v" .. tocVersion)

for index = 1, #files do
    local path = ROOT .. "/" .. files[index]
    local chunk, err = loadfile(path)
    assert(chunk, files[index] .. ": " .. tostring(err))
    chunk(ADDON_NAME)
end

assert(AscensionSuite.VERSION == tocVersion,
    "Bootstrap says v" .. tostring(AscensionSuite.VERSION) .. ", the TOC says v" .. tocVersion)

local API = AscensionSuite.AscensionAPI
assert(API, "AscensionAPI missing")
assert(API.GetEntryIcon(133):find("Icons"), "GetEntryIcon failed")
assert(API.GetEntryName(133):find("CA Entry"), "GetEntryName failed")
assert(#API.GetEntryTooltipLines(133) > 0, "GetEntryTooltipLines failed")
assert(API.ShowEntryTooltip(GameTooltip, 133) == true, "ShowEntryTooltip failed")
assert(GameTooltip._spellId == 133, "ShowEntryTooltip uses SetSpellByID")

AscensionSuite.Database.Init()
assert(AscensionSuiteDB.assists.autoRoll == false, "autoRoll must default false")
assert(AscensionSuiteDB.assists.captureRolls == false, "captureRolls must default false")

-- The window builds both tabs on first open, so this also smoke-tests every
-- widget the Wishlist panel creates.
local MainWindow = AscensionSuite.MainWindow
local Wishlist = AscensionSuite.Wishlist
assert(Wishlist.Add(133), "seed one wishlist row")

local window = MainWindow.Show()
assert(window:IsShown(), "/asuite opens")
assert(MainWindow.GetActiveTab() == 1, "the Wishlist tab is the one you land on")

local panel = AscensionSuite.WishlistPanel
assert(panel and panel.GetFrame(), "the Wishlist panel is built with the window")
assert(#panel.GetFilteredRows() == 1, "and lists the wishlist")

MainWindow.SelectTab(2)
assert(MainWindow.GetActiveTab() == 2, "the Assists tab switches")
MainWindow.SelectTab(1)

MainWindow.RegisterSlash()
assert(type(SlashCmdList.ASUITE) == "function", "slash handler missing")

print("OK: AscensionSuite load smoke test passed")
