-- AscensionSuite: ui/LoadoutsPanel.lua
-- Loadouts tab: saved builds, snapshot/load/apply, share strings.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local LoadoutsPanel = {}
AscensionSuite.LoadoutsPanel = LoadoutsPanel

local FRAME_NAME = "AscensionSuiteLoadoutsPanel"
local LIST_WIDTH = 220
local ROW_HEIGHT = 26
local VISIBLE_ROWS = 6
local LIST_INSET = 4
local SCROLLBAR_WIDTH = 24
local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local panel
local panelParent
local panelWidth
local listFrame
local scrollFrame
local entryListFrame
local entryScrollFrame
local listRows = {}
local entryRows = {}
local selectedId
local statusLabel
local countLabel
local notesLabel
local titleLabel
local shareBox
local filteredEntries = {}

local function GetLoadouts()
    return AscensionSuite.Loadouts
end

local function GetWishlist()
    return AscensionSuite.Wishlist
end

local function ScrollOffset(scroll)
    if scroll and type(_G.FauxScrollFrame_GetOffset) == "function" then
        return tonumber(_G.FauxScrollFrame_GetOffset(scroll)) or 0
    end
    return 0
end

local function SetStatus(text, good)
    if not statusLabel then
        return
    end
    statusLabel:SetText(text or "")
    if good == true then
        statusLabel:SetTextColor(0.43, 0.81, 0.54, 1)
    elseif good == false then
        statusLabel:SetTextColor(0.88, 0.44, 0.44, 1)
    else
        statusLabel:SetTextColor(0.65, 0.61, 0.53, 1)
    end
end

local function RefreshShareBox()
    if not shareBox then
        return
    end
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        shareBox:SetText("")
        return
    end
    local text = Loadouts.ExportString(selectedId)
    shareBox:SetText(text or "")
end

local function FillListRow(row, meta, position)
    row._id = meta.id
    row._nameLabel:SetText(meta.name or "?")
    local character = meta.character or "shared"
    row._metaLabel:SetText(string.format("%d entries \194\183 %s", meta.entryCount or 0, character))

    if meta.id == selectedId then
        row._select:Show()
    else
        row._select:Hide()
    end

    if position % 2 == 0 then
        row._stripe:Show()
    else
        row._stripe:Hide()
    end
    row:Show()
end

local function FillEntryRow(row, entry, position)
    row._nameLabel:SetText(entry.name or "?")
    row._tagLabel:SetText(entry.entryType or "")
    row._idLabel:SetText(entry.displayId or "?")
    if entry.desired then
        row._badge:Show()
    else
        row._badge:Hide()
    end
    row._icon:SetTexture(entry.icon or PLACEHOLDER_ICON)

    if position % 2 == 0 then
        row._stripe:Show()
    else
        row._stripe:Hide()
    end
    row:Show()
end

function LoadoutsPanel.Refresh(note, good)
    if not panel then
        return
    end

    local Loadouts = GetLoadouts()
    if not Loadouts then
        return
    end

    local list = Loadouts.List()
    if not selectedId and #list > 0 then
        selectedId = list[1].id
    elseif selectedId and not Loadouts.Get(selectedId) then
        selectedId = #list > 0 and list[1].id or nil
    end

    if type(_G.FauxScrollFrame_Update) == "function" and scrollFrame then
        _G.FauxScrollFrame_Update(scrollFrame, #list, VISIBLE_ROWS, ROW_HEIGHT)
    end

    local offset = ScrollOffset(scrollFrame)
    for index = 1, VISIBLE_ROWS do
        local row = listRows[index]
        local meta = list[index + offset]
        if meta then
            FillListRow(row, meta, index)
        else
            row:Hide()
        end
    end

    local loadout = selectedId and Loadouts.Get(selectedId)
    if titleLabel then
        titleLabel:SetText(loadout and loadout.name or "No build selected")
    end
    if notesLabel then
        notesLabel:SetText(loadout and (loadout.notes or "") or "")
    end

    filteredEntries = {}
    if loadout and type(loadout.entries) == "table" then
        for index = 1, #loadout.entries do
            local described = Loadouts.DescribeEntry(loadout.entries[index])
            if described then
                filteredEntries[#filteredEntries + 1] = described
            end
        end
    end

    local desiredCount = Loadouts.CountDesiredInLoadout(loadout)
    if countLabel then
        countLabel:SetText(string.format("%d / 25 \194\183 %d Desired",
            #filteredEntries, desiredCount))
    end

    if type(_G.FauxScrollFrame_Update) == "function" and entryScrollFrame then
        _G.FauxScrollFrame_Update(entryScrollFrame, #filteredEntries, VISIBLE_ROWS, ROW_HEIGHT)
    end

    local entryOffset = ScrollOffset(entryScrollFrame)
    for index = 1, VISIBLE_ROWS do
        local row = entryRows[index]
        local entry = filteredEntries[index + entryOffset]
        if entry then
            FillEntryRow(row, entry, index)
        else
            row:Hide()
        end
    end

    RefreshShareBox()

    if note then
        SetStatus(note, good)
    elseif not loadout then
        SetStatus("Create a build or import a share string to get started.", nil)
    end
end

local function SelectLoadout(id)
    selectedId = id
    LoadoutsPanel.Refresh()
end

local function OnSaveBuild()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select or create a build first.", false)
        return
    end
    local ok, count = Loadouts.SaveFromWishlist(selectedId, false, true)
    if not ok then
        SetStatus("Could not save build — " .. tostring(count or "error") .. ".", false)
        return
    end
    LoadoutsPanel.Refresh(string.format("Saved %d entries from your wishlist.", count or 0), true)
end

local function OnLoadWishlist()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select a build first.", false)
        return
    end
    local ok, count = Loadouts.LoadToWishlist(selectedId)
    if not ok then
        SetStatus("Could not load — " .. tostring(count or "error") .. ".", false)
        return
    end
    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshWishlist then
        MainWindow.RefreshWishlist()
    end
    LoadoutsPanel.Refresh(string.format("Loaded %d entries into the wishlist.", count or 0), true)
end

local function OnApplyDesired()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select a build first.", false)
        return
    end
    local ok, result = Loadouts.Apply(selectedId)
    if not ok then
        SetStatus("Apply failed — " .. tostring(result or "error") .. ".", false)
        return
    end

    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshWishlist then
        MainWindow.RefreshWishlist()
    end

    if result.gate == "not_wildcard" then
        LoadoutsPanel.Refresh(string.format(
            "Loaded %d entries into the wishlist. Push to Desired needs Wildcard mode.",
            result.loaded or 0), nil)
        return
    end

    local note = string.format("Applied: %d pushed, %d already Desired",
        result.pushed or 0, result.already or 0)
    local good = true
    if (result.failed or 0) > 0 then
        note = note .. string.format(", %d refused", result.failed)
        local detail = Loadouts.FormatRefuseSummary(result.refuses)
        if detail then
            note = note .. ": " .. detail
        end
        good = false
    end
    LoadoutsPanel.Refresh(note .. ".", good)
end

local function OnCaptureKnown()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select a build first.", false)
        return
    end
    local ok, reason = Loadouts.CaptureKnown(selectedId)
    if not ok then
        SetStatus("Capture Known failed — " .. tostring(reason or "error") .. ".", false)
        return
    end
    LoadoutsPanel.Refresh("Known snapshot captured for this build.", true)
end

local function OnNewBuild()
    local Loadouts = GetLoadouts()
    if not Loadouts then
        return
    end
    local loadout, id = Loadouts.Create("New build", "", false)
    if not loadout then
        SetStatus("Could not create build — " .. tostring(id or "error") .. ".", false)
        return
    end
    selectedId = id
    LoadoutsPanel.Refresh("Created a new build — Save Build to snapshot your wishlist.", true)
end

local function OnDeleteBuild()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Nothing selected to delete.", false)
        return
    end
    local name = Loadouts.Get(selectedId) and Loadouts.Get(selectedId).name or selectedId
    local ok, reason = Loadouts.Delete(selectedId)
    if not ok then
        SetStatus("Delete failed — " .. tostring(reason or "error") .. ".", false)
        return
    end
    selectedId = nil
    LoadoutsPanel.Refresh(string.format("Deleted \"%s\".", name or "build"), true)
end

local function OnCopyShare()
    if not shareBox then
        return
    end
    local text = shareBox:GetText()
    if text == "" then
        SetStatus("Nothing to copy — select a saved build.", false)
        return
    end
    if type(_G.SetClipboardText) == "function" then
        _G.SetClipboardText(text)
        SetStatus("Share string copied.", true)
    else
        SetStatus("Copy the share string from the box below (clipboard unavailable).", nil)
    end
end

local function OnImportShare()
    local Loadouts = GetLoadouts()
    if not Loadouts then
        return
    end
    local text = shareBox and shareBox:GetText() or ""
    if text == "" then
        SetStatus("Paste a share string into the box, then Import.", false)
        return
    end
    local loadout, id = Loadouts.ImportString(text, false)
    if not loadout then
        SetStatus("Import failed — " .. tostring(id or "error") .. ".", false)
        return
    end
    selectedId = id
    LoadoutsPanel.Refresh(string.format("Imported \"%s\" (%d entries).", loadout.name, #(loadout.entries or {})), true)
end

local function NeutralizeScrollChrome(scroll)
    if type(scroll) ~= "table" then
        return
    end
    if scroll.EnableMouse then
        scroll:EnableMouse(false)
    end
    local name = scroll.GetName and scroll:GetName()
    if type(name) ~= "string" or name == "" then
        return
    end
    local extras = { "ScrollChildFrame", "Track", "Top", "Bottom", "Middle" }
    for index = 1, #extras do
        local piece = _G[name .. extras[index]]
        if type(piece) == "table" then
            if piece.Hide then piece:Hide() end
            if piece.EnableMouse then piece:EnableMouse(false) end
        end
    end
end

local function CreateListRow(parent, index, onClick)
    local row = CreateFrame("Button", FRAME_NAME .. "ListRow" .. index, parent)
    row:SetHeight(ROW_HEIGHT)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetTexture(1, 1, 1, 0.03)
    row._stripe = stripe

    local select = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    select:SetAllPoints()
    select:SetTexture(1, 0.82, 0.2, 0.16)
    select:Hide()
    row._select = select

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", 6, -4)
    nameLabel:SetJustifyH("LEFT")
    row._nameLabel = nameLabel

    local metaLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -1)
    metaLabel:SetJustifyH("LEFT")
    row._metaLabel = metaLabel

    row:SetScript("OnClick", function()
        if row._id and onClick then
            onClick(row._id)
        end
    end)
    return row
end

local function CreateEntryRow(parent, index)
    local row = CreateFrame("Frame", FRAME_NAME .. "EntryRow" .. index, parent)
    row:SetHeight(ROW_HEIGHT)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetTexture(1, 1, 1, 0.03)
    row._stripe = stripe

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(18)
    icon:SetHeight(18)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local badge = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    badge:SetPoint("RIGHT", -6, 0)
    badge:SetWidth(48)
    badge:SetJustifyH("RIGHT")
    badge:SetTextColor(0.35, 0.71, 1, 1)
    badge:SetText("Desired")
    row._badge = badge

    local idLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    idLabel:SetPoint("RIGHT", badge, "LEFT", -6, 0)
    idLabel:SetWidth(58)
    idLabel:SetJustifyH("RIGHT")
    row._idLabel = idLabel

    local tagLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tagLabel:SetPoint("RIGHT", idLabel, "LEFT", -6, 0)
    tagLabel:SetWidth(52)
    tagLabel:SetJustifyH("RIGHT")
    row._tagLabel = tagLabel

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameLabel:SetPoint("RIGHT", tagLabel, "LEFT", -8, 0)
    nameLabel:SetJustifyH("LEFT")
    row._nameLabel = nameLabel

    return row
end

local function BuildScrollList(parent, width, height, rowMaker, rowStore, onScroll)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.035, 0.025, 0.92)
    frame:SetBackdropBorderColor(0.45, 0.38, 0.20, 1)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -LIST_INSET, -LIST_INSET)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LIST_INSET, LIST_INSET)
    scroll:SetWidth(SCROLLBAR_WIDTH)
    NeutralizeScrollChrome(scroll)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        if type(_G.FauxScrollFrame_OnVerticalScroll) == "function" then
            _G.FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
                if onScroll then onScroll() end
            end)
        end
    end)

    local rowWidth = width - LIST_INSET - SCROLLBAR_WIDTH
    for index = 1, VISIBLE_ROWS do
        local row = rowMaker(frame, index)
        row:SetWidth(rowWidth)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_INSET, -(LIST_INSET + (index - 1) * ROW_HEIGHT))
        row:SetFrameLevel((scroll:GetFrameLevel() or 0) + 2)
        row:Hide()
        rowStore[index] = row
    end

    return frame, scroll
end

local function BuildPanel(parent, width)
    local contentWidth = width or 640
    panel = CreateFrame("Frame", FRAME_NAME, parent)
    panel:SetAllPoints()
    panelParent = parent
    panelWidth = contentWidth

    local detailWidth = contentWidth - LIST_WIDTH - 12

    local listLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", 0, 0)
    listLabel:SetText("Saved builds")

    listFrame, scrollFrame = BuildScrollList(panel, LIST_WIDTH, VISIBLE_ROWS * ROW_HEIGHT + LIST_INSET * 2,
        function(frame, index)
            return CreateListRow(frame, index, SelectLoadout)
        end, listRows, function() LoadoutsPanel.Refresh() end)
    listFrame:SetPoint("TOPLEFT", 0, -16)

    local newButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newButton:SetWidth(64)
    newButton:SetHeight(22)
    newButton:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -6)
    newButton:SetText("New")
    newButton:SetScript("OnClick", OnNewBuild)

    local deleteButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    deleteButton:SetWidth(64)
    deleteButton:SetHeight(22)
    deleteButton:SetPoint("LEFT", newButton, "RIGHT", 8, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", OnDeleteBuild)

    titleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 12, 0)
    titleLabel:SetText("No build selected")

    countLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetPoint("TOPRIGHT", 0, -4)
    countLabel:SetJustifyH("RIGHT")

    notesLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notesLabel:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -6)
    notesLabel:SetWidth(detailWidth)
    notesLabel:SetJustifyH("LEFT")

    local entriesLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    entriesLabel:SetPoint("TOPLEFT", notesLabel, "BOTTOMLEFT", 0, -10)
    entriesLabel:SetText("Entries in this build")

    entryListFrame, entryScrollFrame = BuildScrollList(panel, detailWidth,
        VISIBLE_ROWS * ROW_HEIGHT + LIST_INSET * 2,
        CreateEntryRow, entryRows, function() LoadoutsPanel.Refresh() end)
    entryListFrame:SetPoint("TOPLEFT", entriesLabel, "BOTTOMLEFT", 0, -4)

    local saveButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    saveButton:SetWidth(100)
    saveButton:SetHeight(22)
    saveButton:SetPoint("TOPLEFT", entryListFrame, "BOTTOMLEFT", 0, -8)
    saveButton:SetText("Save Build")
    saveButton:SetScript("OnClick", OnSaveBuild)

    local loadButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    loadButton:SetWidth(110)
    loadButton:SetHeight(22)
    loadButton:SetPoint("LEFT", saveButton, "RIGHT", 6, 0)
    loadButton:SetText("Load \226\134\146 Wishlist")
    loadButton:SetScript("OnClick", OnLoadWishlist)

    local applyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    applyButton:SetWidth(120)
    applyButton:SetHeight(22)
    applyButton:SetPoint("LEFT", loadButton, "RIGHT", 6, 0)
    applyButton:SetText("Apply \226\134\146 Desired")
    applyButton:SetScript("OnClick", OnApplyDesired)

    local knownButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    knownButton:SetWidth(100)
    knownButton:SetHeight(22)
    knownButton:SetPoint("LEFT", applyButton, "RIGHT", 6, 0)
    knownButton:SetText("Capture Known")
    knownButton:SetScript("OnClick", OnCaptureKnown)

    statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetPoint("TOPLEFT", saveButton, "BOTTOMLEFT", 0, -8)
    statusLabel:SetWidth(detailWidth)
    statusLabel:SetJustifyH("LEFT")

    local exportLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportLabel:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -10)
    exportLabel:SetText("Share string (copy / paste)")

    shareBox = CreateFrame("EditBox", FRAME_NAME .. "Share", panel, "InputBoxTemplate")
    shareBox:SetPoint("TOPLEFT", exportLabel, "BOTTOMLEFT", 0, -4)
    shareBox:SetWidth(detailWidth)
    shareBox:SetHeight(22)
    shareBox:SetAutoFocus(false)
    shareBox:SetMultiLine(true)
    shareBox:SetMaxLetters(4000)

    local copyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    copyButton:SetWidth(64)
    copyButton:SetHeight(22)
    copyButton:SetPoint("TOPLEFT", shareBox, "BOTTOMLEFT", 0, -6)
    copyButton:SetText("Copy")
    copyButton:SetScript("OnClick", OnCopyShare)

    local importButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importButton:SetWidth(72)
    importButton:SetHeight(22)
    importButton:SetPoint("LEFT", copyButton, "RIGHT", 8, 0)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", OnImportShare)

    LoadoutsPanel.Refresh()
    return panel
end

function LoadoutsPanel.EnsureBuilt(parent, width)
    if panel then
        return panel
    end
    if type(parent) ~= "table" then
        return nil
    end
    return BuildPanel(parent, width)
end

function LoadoutsPanel.Create(parent, width)
    return LoadoutsPanel.EnsureBuilt(parent, width)
end

-- Re-anchor after the /asuite window becomes visible. Widgets built while the tab
-- content was hidden can layout at 0x0 on 3.3.5a until the parent chain shows.
function LoadoutsPanel.InvalidateLayout()
    if not panel or not panelParent then
        return
    end

    panel:ClearAllPoints()
    panel:SetAllPoints(panelParent)

    if not panelWidth then
        return
    end

    local detailWidth = panelWidth - LIST_WIDTH - 12

    if listFrame then
        listFrame:SetWidth(LIST_WIDTH)
        local rowWidth = LIST_WIDTH - LIST_INSET - SCROLLBAR_WIDTH
        for index = 1, VISIBLE_ROWS do
            local row = listRows[index]
            if row then
                row:SetWidth(rowWidth)
            end
        end
    end

    if entryListFrame then
        entryListFrame:SetWidth(detailWidth)
        local rowWidth = detailWidth - LIST_INSET - SCROLLBAR_WIDTH
        for index = 1, VISIBLE_ROWS do
            local row = entryRows[index]
            if row then
                row:SetWidth(rowWidth)
            end
        end
    end

    if notesLabel and notesLabel.SetWidth then
        notesLabel:SetWidth(detailWidth)
    end
    if statusLabel and statusLabel.SetWidth then
        statusLabel:SetWidth(detailWidth)
    end
    if shareBox and shareBox.SetWidth then
        shareBox:SetWidth(detailWidth)
    end
end

function LoadoutsPanel.GetFrame()
    return panel
end

function LoadoutsPanel.GetSelectedId()
    return selectedId
end

function LoadoutsPanel.GetFilteredEntries()
    return filteredEntries
end
