-- AscensionSuite: core/Bootstrap.lua
-- Load-safe namespace bootstrap and slash command registration.

local addonName = select(1, ...) or "AscensionSuite"

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

AscensionSuite.NAME = addonName
AscensionSuite.VERSION = "0.4.1"

local function OnAddonLoaded(name)
    if name ~= addonName then
        return
    end

    local DB = AscensionSuite.Database
    if DB and DB.Init then
        DB.Init()
    end

    local Logbook = AscensionSuite.Logbook
    if Logbook and Logbook.Init then
        Logbook.Init()
    end

    local DesiredSync = AscensionSuite.DesiredSync
    if DesiredSync and DesiredSync.Init then
        DesiredSync.Init()
    end

    local AnimationSkip = AscensionSuite.AnimationSkip
    if AnimationSkip and AnimationSkip.Init then
        AnimationSkip.Init()
    end

    local PopupAssist = AscensionSuite.PopupAssist
    if PopupAssist and PopupAssist.Init then
        PopupAssist.Init()
    end

    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.Init then
        AutoRoller.Init()
    end

    local AutoUnstick = AscensionSuite.AutoUnstick
    if AutoUnstick and AutoUnstick.Init then
        AutoUnstick.Init()
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
