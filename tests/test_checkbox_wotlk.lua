-- AscensionSuite: tests/test_checkbox_wotlk.lua
-- WotLK CheckButton:GetChecked() returns 1 / nil. Writing == true left every
-- assist permanently off while the box stayed visually checked.

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
CreateFrame = function()
    return {
        RegisterEvent = Noop,
        SetScript = Noop,
        EnableMouse = Noop,
        RegisterForDrag = Noop,
        SetMovable = Noop,
        SetClampedToScreen = Noop,
        SetFrameStrata = Noop,
        SetSize = Noop,
        SetPoint = Noop,
        SetBackdrop = Noop,
        SetBackdropColor = Noop,
        SetBackdropBorderColor = Noop,
        CreateFontString = function()
            return {
                SetPoint = Noop, SetText = Noop, SetTextColor = Noop,
                SetWidth = Noop, SetJustifyH = Noop,
            }
        end,
        CreateTexture = function()
            return { SetAllPoints = Noop, SetTexture = Noop, SetVertexColor = Noop }
        end,
    }
end

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/ui/NativeChrome.lua")
dofile(ROOT .. "/ui/MainWindow.lua")

AscensionSuite.Database.Init()
local MainWindow = AscensionSuite.MainWindow
assert(MainWindow.CheckButtonIsOn, "CheckButtonIsOn helper missing")

assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return 1 end }) == true,
    "GetChecked() == 1 must read as on")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return true end }) == true,
    "boolean true still counts")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return nil end }) == false,
    "nil is off")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return false end }) == false,
    "false is off")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return 0 end }) == false,
    "0 is off")

-- The old bug: == true writes false when the client returns 1.
local fake = { GetChecked = function() return 1 end }
local broken = (fake:GetChecked() == true)
assert(broken == false, "sanity: 1 == true is false in Lua 5.1")
assert(MainWindow.CheckButtonIsOn(fake) == true,
    "helper must treat WotLK checked state as on")

-- Persisting the helper result enables the assist the visual already showed.
local assists = AscensionSuite.Database.GetAssists()
assists.autoRoll = MainWindow.CheckButtonIsOn(fake)
assert(AscensionSuiteDB.assists.autoRoll == true,
    "storing GetChecked()==1 must enable autoRoll in SavedVariables")

-- ClearLastError drops a sticky assist_off after the box is turned back on.
dofile(ROOT .. "/automation/AutoRoller.lua")
local AutoRoller = AscensionSuite.AutoRoller
AutoRoller.Stop("assist_off")
assert(AutoRoller.GetLastError() == "assist_off")
AutoRoller.ClearLastError()
assert(AutoRoller.GetLastError() == nil, "ClearLastError drops the sticky reason")

print("OK: AscensionSuite WotLK checkbox test passed")
