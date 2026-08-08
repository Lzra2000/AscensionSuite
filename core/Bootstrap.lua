-- AscensionSuite: core/Bootstrap.lua
-- Load-safe namespace bootstrap and slash command registration.

local addonName = select(1, ...) or "AscensionSuite"

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

AscensionSuite.NAME = addonName
AscensionSuite.VERSION = "0.1.0"

local function OnAddonLoaded(name)
    if name ~= addonName then
        return
    end

    local DB = AscensionSuite.Database
    if DB and DB.Init then
        DB.Init()
    end

    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RegisterSlash then
        MainWindow.RegisterSlash()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    end
end)
