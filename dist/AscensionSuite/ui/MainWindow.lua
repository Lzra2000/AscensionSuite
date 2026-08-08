-- AscensionSuite: ui/MainWindow.lua
-- Minimal proof window: spell id input, Add/Refresh, SpellCell grid.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local MainWindow = {}
AscensionSuite.MainWindow = MainWindow

local FRAME_NAME = "AscensionSuiteMainWindow"
local GRID_COLUMNS = 8
local CELL_GAP = 10

local frame
local inputBox
local gridHost
local cells = {}

local function GetDB()
    local DB = AscensionSuite.Database
    if DB and DB.GetProofSpellIds then
        return DB.GetProofSpellIds()
    end
    return {}
end

local function SaveSpellIds(spellIds)
    local DB = AscensionSuite.Database
    if DB and DB.SetProofSpellIds then
        DB.SetProofSpellIds(spellIds)
    end
end

local function ParseInput(text)
    local id = tonumber(text)
    if not id then
        return nil
    end
    return math.floor(id)
end

local function UniqueAppend(spellIds, spellId)
    for index = 1, #spellIds do
        if spellIds[index] == spellId then
            return false
        end
    end
    spellIds[#spellIds + 1] = spellId
    return true
end

local function LayoutGrid()
    if not gridHost then
        return
    end

    local SpellCell = AscensionSuite.SpellCell
    if not SpellCell or not SpellCell.Create then
        return
    end

    local spellIds = GetDB()
    local needed = #spellIds

    while #cells < needed do
        local index = #cells + 1
        local cell = SpellCell.Create(gridHost, FRAME_NAME .. "Cell" .. index)
        cells[index] = cell
    end

    local x, y = 0, 0
    for index = 1, needed do
        local cell = cells[index]
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", gridHost, "TOPLEFT", x, -y)
        cell:SetSpell(spellIds[index])
        cell:Show()

        x = x + cell:GetWidth() + CELL_GAP
        if index % GRID_COLUMNS == 0 then
            x = 0
            y = y + cell:GetHeight() + CELL_GAP
        end
    end

    for index = needed + 1, #cells do
        cells[index]:Hide()
    end
end

local function RefreshAll()
    for index = 1, #cells do
        local spellId = cells[index]:GetSpellId()
        if spellId then
            cells[index]:SetSpell(spellId)
        end
    end
end

local function AddSpellFromInput()
    if not inputBox then
        return
    end

    local spellId = ParseInput(inputBox:GetText())
    if not spellId then
        return
    end

    local spellIds = GetDB()
    if UniqueAppend(spellIds, spellId) then
        SaveSpellIds(spellIds)
    end

    inputBox:SetText("")
    LayoutGrid()
end

local function EnsureFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(560, 420)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    local backdrop = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }
    frame:SetBackdrop(backdrop)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("AscensionSuite")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("SpellCell proof — icon / id / tooltip from client APIs")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    inputBox = CreateFrame("EditBox", FRAME_NAME .. "Input", frame, "InputBoxTemplate")
    inputBox:SetSize(120, 24)
    inputBox:SetPoint("TOPLEFT", 24, -64)
    inputBox:SetAutoFocus(false)
    inputBox:SetNumeric(true)
    inputBox:SetMaxLetters(8)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputLabel:SetPoint("BOTTOMLEFT", inputBox, "TOPLEFT", 0, 2)
    inputLabel:SetText("Spell ID")

    local addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addButton:SetSize(72, 22)
    addButton:SetPoint("LEFT", inputBox, "RIGHT", 12, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", AddSpellFromInput)

    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshButton:SetSize(72, 22)
    refreshButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", RefreshAll)

    inputBox:SetScript("OnEnterPressed", function(self)
        AddSpellFromInput()
        self:ClearFocus()
    end)

    gridHost = CreateFrame("Frame", nil, frame)
    gridHost:SetPoint("TOPLEFT", 24, -110)
    gridHost:SetPoint("BOTTOMRIGHT", -24, 24)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 12)
    hint:SetText("/asuite to toggle · assists default off")

    frame._layoutGrid = LayoutGrid
    return frame
end

function MainWindow.Toggle()
    local win = EnsureFrame()
    if win:IsShown() then
        win:Hide()
    else
        LayoutGrid()
        win:Show()
    end
end

function MainWindow.Show()
    local win = EnsureFrame()
    LayoutGrid()
    win:Show()
end

function MainWindow.Hide()
    if frame then
        frame:Hide()
    end
end

function MainWindow.RegisterSlash()
    SLASH_ASUITE1 = "/asuite"
    SlashCmdList.ASUITE = function()
        MainWindow.Toggle()
    end
end
