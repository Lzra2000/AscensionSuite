-- AscensionSuite: ui/LoadoutsPanel.lua
-- Archetype-style loadouts: section sidebar, spell automation, ASUITE1 share.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local LoadoutsPanel = {}
AscensionSuite.LoadoutsPanel = LoadoutsPanel

local FRAME_NAME = "AscensionSuiteLoadoutsPanel"
local LIST_WIDTH = 132
local SIDEBAR_WIDTH = 148
local ROW_HEIGHT = 26
local GROUP_HEIGHT = 22
local VISIBLE_LIST_ROWS = 5
local VISIBLE_SPELL_ROWS = 8
local LIST_INSET = 4
local SCROLLBAR_WIDTH = 24
local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local panel
local panelParent
local panelWidth
local listFrame
local scrollFrame
local listRows = {}
local buildShell
local sectionSidebar
local navButtons = {}
local mainColumn
local sectionContent
local nameLabel
local authorChip
local categoryChip
local complexityChip
local autoStatusLabel
local sectionTitle
local sectionCount
local filterBar
local spellScrollFrame
local spellListFrame
local spellRows = {}
local notesEdit
local equipmentLabel
local statusLabel
local shareBox
local selectedId
local activeSection = "SPELLS_AND_TALENTS"
local displayRows = {}
local spellFilters = { core = true, optimal = true, empowering = true, synergistic = true }
local savedSnapshot

local function GetLoadouts()
    return AscensionSuite.Loadouts
end

local function GetWishlist()
    return AscensionSuite.Wishlist
end

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function ScrollOffset(scroll)
    if scroll and type(_G.FauxScrollFrame_GetOffset) == "function" then
        return tonumber(_G.FauxScrollFrame_GetOffset(scroll)) or 0
    end
    return 0
end

local function CheckButtonIsOn(check)
    if type(check) ~= "table" or type(check.GetChecked) ~= "function" then
        return false
    end
    local value = check:GetChecked()
    return value == 1 or value == true
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

local function SetAutoStatus(text, good)
    if not autoStatusLabel then
        return
    end
    autoStatusLabel:SetText(text or "")
    if good == true then
        autoStatusLabel:SetTextColor(0.43, 0.81, 0.54, 1)
    elseif good == false then
        autoStatusLabel:SetTextColor(0.88, 0.44, 0.44, 1)
    else
        autoStatusLabel:SetTextColor(0.65, 0.61, 0.53, 1)
    end
end

local function PersistActiveSection()
    if not selectedId or not notesEdit then
        return
    end
    local Loadouts = GetLoadouts()
    if not Loadouts or activeSection == "SPELLS_AND_TALENTS" or activeSection == "EQUIPMENT" then
        if activeSection == "EQUIPMENT" and notesEdit.GetText then
            Loadouts.SetSectionText(selectedId, activeSection, notesEdit:GetText())
        end
        return
    end
    if notesEdit.GetText then
        Loadouts.SetSectionText(selectedId, activeSection, notesEdit:GetText())
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
    local text = Loadouts.ExportString(selectedId) or ""
    shareBox:SetText(text)
    if shareBox.SetCursorPosition then
        shareBox:SetCursorPosition(0)
    end
    if shareBox.HighlightText then
        shareBox:HighlightText(0, 0)
    end
end

local function BuildSpellDisplayRows(loadout)
    displayRows = {}
    if not loadout or type(loadout.entries) ~= "table" then
        return 0
    end

    local Loadouts = GetLoadouts()
    local groups, order, total = Loadouts.GroupEntries(loadout.entries, spellFilters)
    for groupIndex = 1, #order do
        local label = order[groupIndex]
        displayRows[#displayRows + 1] = { kind = "group", label = label }
        local rows = groups[label] or {}
        for rowIndex = 1, #rows do
            displayRows[#displayRows + 1] = { kind = "spell", entry = rows[rowIndex] }
        end
    end
    return total
end

local function RowHeightForIndex(index)
    local row = displayRows[index]
    if row and row.kind == "group" then
        return GROUP_HEIGHT
    end
    return ROW_HEIGHT
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

local function FillSpellRow(row, data, position)
    if data.kind == "group" then
        row._group:Show()
        row._spell:Hide()
        row._groupLabel:SetText(data.label or "?")
        row:SetHeight(GROUP_HEIGHT)
        row:Show()
        return
    end

    row._group:Hide()
    row._spell:Show()
    row:SetHeight(ROW_HEIGHT)
    local entry = data.entry or {}
    row._nameLabel:SetText(entry.name or "?")
    row._tagLabel:SetText(entry.tagLabel or "")
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

local function UpdateHeader(loadout)
    if not loadout then
        if nameLabel then nameLabel:SetText("No build selected") end
        if authorChip then authorChip:SetText("") end
        if categoryChip then categoryChip:Hide() end
        if complexityChip then complexityChip:Hide() end
        return
    end

    if nameLabel then
        nameLabel:SetText(loadout.name or "Untitled build")
    end
    if authorChip then
        authorChip:SetText(string.format("Author %s", loadout.author or "?"))
    end
    if categoryChip then
        if loadout.category and loadout.category ~= "" then
            categoryChip:SetText(loadout.category)
            categoryChip:Show()
        else
            categoryChip:Hide()
        end
    end
    if complexityChip then
        if loadout.complexity and loadout.complexity ~= "" then
            complexityChip:SetText(string.format("Complexity %s", loadout.complexity))
            complexityChip:Show()
        else
            complexityChip:Hide()
        end
    end
end

local function UpdateAutoStatus(loadout)
    if not loadout then
        SetAutoStatus("Select or create a build to automate.", nil)
        return
    end

    local Loadouts = GetLoadouts()
    local total = type(loadout.entries) == "table" and #loadout.entries or 0
    local desired = Loadouts and Loadouts.CountDesiredInLoadout(loadout) or 0
    local assists = AscensionSuite.Database and AscensionSuite.Database.GetAssists and AscensionSuite.Database.GetAssists() or {}
    local tail = ""
    if assists.autoRoll == true then
        tail = "missing will be rolled (Wildcard + assists on)"
    else
        tail = "enable Auto-Roll on Assists to roll missing entries"
    end
    SetAutoStatus(string.format("%d spells ready \194\183 Desired %d of %d \194\183 %s",
        total, desired, total, tail), total > 0)
end

local function RefreshSectionContent(loadout)
    if not sectionTitle or not sectionCount then
        return
    end

    local Loadouts = GetLoadouts()
    local label = Loadouts and Loadouts.GetSectionLabel(activeSection) or activeSection
    sectionTitle:SetText(label)

    if activeSection == "SPELLS_AND_TALENTS" then
        if filterBar then filterBar:Show() end
        if notesEdit then notesEdit:Hide() end
        if equipmentLabel then equipmentLabel:Hide() end
        if spellListFrame then spellListFrame:Show() end

        local total = BuildSpellDisplayRows(loadout)
        sectionCount:SetText(string.format("%d entries \194\183 grouped by class like Archetypes", total))

        if type(_G.FauxScrollFrame_Update) == "function" and spellScrollFrame then
            _G.FauxScrollFrame_Update(spellScrollFrame, #displayRows, VISIBLE_SPELL_ROWS, ROW_HEIGHT)
        end

        local offset = ScrollOffset(spellScrollFrame)
        for index = 1, VISIBLE_SPELL_ROWS do
            local row = spellRows[index]
            local data = displayRows[index + offset]
            if data then
                FillSpellRow(row, data, index)
            else
                row:Hide()
            end
        end
        return
    end

    if spellListFrame then spellListFrame:Hide() end
    if filterBar then filterBar:Hide() end
    if notesEdit then notesEdit:Show() end

    if activeSection == "EQUIPMENT" and equipmentLabel and loadout and loadout.equipment then
        equipmentLabel:Show()
        local lines = {}
        local armor = loadout.equipment.armorTypes or {}
        local weapons = loadout.equipment.weaponTypes or {}
        if #armor > 0 then
            lines[#lines + 1] = "Armor: " .. table.concat(armor, ", ")
        end
        if #weapons > 0 then
            lines[#lines + 1] = "Weapons: " .. table.concat(weapons, ", ")
        end
        if #lines == 0 then
            lines[1] = "No equipment types imported yet."
        end
        equipmentLabel:SetText(table.concat(lines, "\n"))
        sectionCount:SetText("equipment stubs from archetype import")
        if notesEdit.SetText then
            local sections = Loadouts and Loadouts.GetSections(loadout) or {}
            notesEdit:SetText(sections.EQUIPMENT or "")
        end
        if notesEdit.ClearAllPoints then
            notesEdit:ClearAllPoints()
            notesEdit:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -8)
            notesEdit:SetPoint("BOTTOMRIGHT", sectionContent, "BOTTOMRIGHT", -4, 0)
        end
        return
    end

    if equipmentLabel then equipmentLabel:Hide() end
    sectionCount:SetText("local notes (SavedVariables)")
    if notesEdit and notesEdit.SetText and loadout then
        local sections = Loadouts and Loadouts.GetSections(loadout) or {}
        notesEdit:SetText(sections[activeSection] or "")
    end
    if notesEdit and notesEdit.ClearAllPoints then
        notesEdit:ClearAllPoints()
        notesEdit:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -8)
        notesEdit:SetPoint("BOTTOMRIGHT", sectionContent, "BOTTOMRIGHT", -4, 0)
    end
end

local function RefreshNav()
    local Loadouts = GetLoadouts()
    if not Loadouts then
        return
    end
    for index = 1, #navButtons do
        local button = navButtons[index]
        local key = Loadouts.SECTION_ORDER[index]
        if button and key then
            if key == activeSection then
                button._select:Show()
                button._label:SetTextColor(1, 0.82, 0.2, 1)
            else
                button._select:Hide()
                button._label:SetTextColor(0.78, 0.72, 0.59, 1)
            end
        end
    end
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
        _G.FauxScrollFrame_Update(scrollFrame, #list, VISIBLE_LIST_ROWS, ROW_HEIGHT)
    end

    local offset = ScrollOffset(scrollFrame)
    for index = 1, VISIBLE_LIST_ROWS do
        local row = listRows[index]
        local meta = list[index + offset]
        if meta then
            FillListRow(row, meta, index)
        else
            row:Hide()
        end
    end

    local loadout = selectedId and Loadouts.Get(selectedId)
    UpdateHeader(loadout)
    UpdateAutoStatus(loadout)
    RefreshNav()
    RefreshSectionContent(loadout)
    RefreshShareBox()

    if note then
        SetStatus(note, good)
    elseif not loadout then
        SetStatus("Create a build or import an archetype to get started.", nil)
    end
end

local function SelectLoadout(id)
    PersistActiveSection()
    selectedId = id
    savedSnapshot = nil
    LoadoutsPanel.Refresh()
end

local function SelectSection(key)
    PersistActiveSection()
    activeSection = key
    LoadoutsPanel.Refresh()
end

local function OnSaveBuild()
    PersistActiveSection()
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

local function OnResetBuild()
    PersistActiveSection()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Nothing selected to reset.", false)
        return
    end
    Loadouts.ResetToSaved(selectedId)
    LoadoutsPanel.Refresh("Discarded unsaved section edits.", true)
end

local function OnImportArchetype()
    PersistActiveSection()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select or create a build first.", false)
        return
    end
    local ok, count, source = Loadouts.ImportFromArchetype(selectedId)
    if not ok then
        SetStatus("Import failed — " .. tostring(count or "error") .. ".", false)
        return
    end
    local note = string.format("Imported %d spells from %s build.", count or 0, source or "native")
    LoadoutsPanel.Refresh(note, true)
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
    local ok, result = Loadouts.Apply(selectedId, spellFilters)
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

local function OnSyncRapid()
    local DesiredSync = AscensionSuite.DesiredSync
    if not DesiredSync or not DesiredSync.Sync then
        SetStatus("Desired sync is not available.", false)
        return
    end
    local added, scanned, widened = DesiredSync.Sync()
    local note
    if scanned == 0 then
        note = "no Desired candidates to scan"
    elseif added == 0 then
        note = string.format("scanned %d, nothing new", scanned)
    else
        note = string.format("+%d from Rapid", added)
    end
    if widened then
        note = note .. " (widened Rapid search)"
    end
    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshWishlist then
        MainWindow.RefreshWishlist()
    end
    LoadoutsPanel.Refresh(note, added > 0)
end

local function OnStartAutoRoll()
    local DB = AscensionSuite.Database
    local assists = DB and DB.GetAssists and DB.GetAssists() or {}
    if assists.autoRoll ~= true then
        SetAutoStatus("Auto-Roll is off — enable it on the Assists tab first.", false)
        return
    end

    local Loadouts = GetLoadouts()
    if Loadouts and selectedId then
        local ok, result = Loadouts.Apply(selectedId, spellFilters)
        if ok and result and result.gate == "not_wildcard" then
            SetAutoStatus("Apply needs Wildcard mode before Auto-Roll can run.", false)
            return
        end
        local MainWindow = AscensionSuite.MainWindow
        if MainWindow and MainWindow.RefreshWishlist then
            MainWindow.RefreshWishlist()
        end
    end

    local AutoRoller = AscensionSuite.AutoRoller
    if not AutoRoller or not AutoRoller.Start then
        SetAutoStatus("Auto-Roll is not available.", false)
        return
    end
    local ok, reason = AutoRoller.Start()
    if not ok then
        local detail = reason or "unknown"
        if AscensionSuite.MainWindow and AscensionSuite.MainWindow.DescribeStopReason then
            detail = AscensionSuite.MainWindow.DescribeStopReason(reason)
        end
        SetAutoStatus("Auto-Roll did not start — " .. detail, false)
        return
    end
    SetAutoStatus("Auto-Roll running…", true)
end

local function OnAddSpell()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select a build first.", false)
        return
    end
    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.GetItems then
        SetStatus("Wishlist is not available.", false)
        return
    end
    local items = Wishlist.GetItems()
    local added = 0
    for index = 1, #items do
        local item = items[index]
        local ok = Loadouts.AddEntry(selectedId, {
            entryId = item.entryId,
            entryType = item.entryType,
            spellId = item.spellId,
            name = item.name,
            desired = Wishlist.IsItemDesired and Wishlist.IsItemDesired(item) or false,
        })
        if ok then
            added = added + 1
        end
    end
    if added == 0 then
        SetStatus("No new spells added — put rows on the Wishlist first.", false)
        return
    end
    LoadoutsPanel.Refresh(string.format("Added %d spell(s) from the wishlist.", added), true)
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
    activeSection = "SPELLS_AND_TALENTS"
    LoadoutsPanel.Refresh("Created a new build.", true)
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

local function CreateSpellRow(parent, index)
    local row = CreateFrame("Frame", FRAME_NAME .. "SpellRow" .. index, parent)
    row:SetHeight(ROW_HEIGHT)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetTexture(1, 1, 1, 0.03)
    row._stripe = stripe

    local group = CreateFrame("Frame", nil, row)
    group:SetAllPoints()
    group:Hide()
    row._group = group

    local groupLabel = group:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupLabel:SetPoint("LEFT", 8, 0)
    groupLabel:SetTextColor(0.49, 0.77, 0.35, 1)
    row._groupLabel = groupLabel

    local spell = CreateFrame("Frame", nil, row)
    spell:SetAllPoints()
    row._spell = spell

    local icon = spell:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(18)
    icon:SetHeight(18)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local badge = spell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    badge:SetPoint("RIGHT", -6, 0)
    badge:SetWidth(48)
    badge:SetJustifyH("RIGHT")
    badge:SetTextColor(0.35, 0.71, 1, 1)
    badge:SetText("Desired")
    row._badge = badge

    local tagLabel = spell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tagLabel:SetPoint("RIGHT", badge, "LEFT", -6, 0)
    tagLabel:SetWidth(64)
    tagLabel:SetJustifyH("RIGHT")
    row._tagLabel = tagLabel

    local nameLabel = spell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameLabel:SetPoint("RIGHT", tagLabel, "LEFT", -8, 0)
    nameLabel:SetJustifyH("LEFT")
    row._nameLabel = nameLabel

    return row
end

local function BuildScrollList(parent, width, height, rowMaker, rowStore, visibleRows, onScroll)
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
    for index = 1, visibleRows do
        local row = rowMaker(frame, index)
        row:SetWidth(rowWidth)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_INSET, -(LIST_INSET + (index - 1) * ROW_HEIGHT))
        row:SetFrameLevel((scroll:GetFrameLevel() or 0) + 2)
        row:Hide()
        rowStore[index] = row
    end

    return frame, scroll
end

local function CreateNavButton(parent, key, yOffset)
    local Loadouts = GetLoadouts()
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", 0, yOffset)
    button:SetPoint("TOPRIGHT", 0, yOffset)
    button:SetHeight(34)

    local select = button:CreateTexture(nil, "BACKGROUND")
    select:SetPoint("TOPLEFT", 0, 0)
    select:SetPoint("BOTTOMRIGHT", 0, 0)
    select:SetTexture(0.16, 0.14, 0.09, 0.9)
    select:Hide()
    button._select = select

    local accent = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetTexture(1, 0.82, 0.2, 1)
    accent:Hide()
    button._accent = accent

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 10, -6)
    label:SetJustifyH("LEFT")
    label:SetText(Loadouts and Loadouts.GetSectionLabel(key) or key)
    button._label = label

    local hint = Loadouts and Loadouts.SECTION_HINTS and Loadouts.SECTION_HINTS[key]
    if hint then
        local hintLabel = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hintLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        hintLabel:SetText(hint)
        hintLabel:SetTextColor(0.44, 0.42, 0.33, 1)
        button._hint = hintLabel
    end

    button:SetScript("OnClick", function()
        SelectSection(key)
    end)
    return button
end

local function BuildPanel(parent, width)
    local contentWidth = width or 640
    panel = CreateFrame("Frame", FRAME_NAME, parent)
    panel:SetAllPoints()
    panelParent = parent
    panelWidth = contentWidth

    local shellWidth = contentWidth - LIST_WIDTH - 8

    local listLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", 0, 0)
    listLabel:SetText("Saved builds")

    listFrame, scrollFrame = BuildScrollList(panel, LIST_WIDTH, VISIBLE_LIST_ROWS * ROW_HEIGHT + LIST_INSET * 2,
        CreateListRow, listRows, VISIBLE_LIST_ROWS, function() LoadoutsPanel.Refresh() end)
    listFrame:SetPoint("TOPLEFT", 0, -16)

    local newButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newButton:SetWidth(58)
    newButton:SetHeight(22)
    newButton:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -6)
    newButton:SetText("New")
    newButton:SetScript("OnClick", OnNewBuild)

    local deleteButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    deleteButton:SetWidth(58)
    deleteButton:SetHeight(22)
    deleteButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", OnDeleteBuild)

    buildShell = CreateFrame("Frame", nil, panel)
    buildShell:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 8, 0)
    buildShell:SetWidth(shellWidth)
    buildShell:SetHeight(430)
    buildShell:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    buildShell:SetBackdropColor(0.035, 0.03, 0.02, 0.95)
    buildShell:SetBackdropBorderColor(0.45, 0.38, 0.20, 1)

    sectionSidebar = CreateFrame("Frame", nil, buildShell)
    sectionSidebar:SetWidth(SIDEBAR_WIDTH)
    sectionSidebar:SetPoint("TOPLEFT", 4, -4)
    sectionSidebar:SetPoint("BOTTOMLEFT", 4, 4)
    sectionSidebar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sectionSidebar:SetBackdropColor(0.10, 0.09, 0.06, 1)
    sectionSidebar:SetBackdropBorderColor(0.35, 0.30, 0.18, 1)

    local Loadouts = GetLoadouts()
    local y = -4
    for index = 1, #(Loadouts and Loadouts.SECTION_ORDER or {}) do
        local key = Loadouts.SECTION_ORDER[index]
        navButtons[index] = CreateNavButton(sectionSidebar, key, y)
        y = y - 34
    end

    mainColumn = CreateFrame("Frame", nil, buildShell)
    mainColumn:SetPoint("TOPLEFT", sectionSidebar, "TOPRIGHT", 4, 0)
    mainColumn:SetPoint("BOTTOMRIGHT", buildShell, "BOTTOMRIGHT", -4, 4)

    local meta = CreateFrame("Frame", nil, mainColumn)
    meta:SetPoint("TOPLEFT", 0, 0)
    meta:SetPoint("TOPRIGHT", 0, 0)
    meta:SetHeight(34)

    nameLabel = meta:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("LEFT", 8, 0)
    nameLabel:SetTextColor(1, 0.82, 0.2, 1)
    nameLabel:SetText("No build selected")

    authorChip = meta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    authorChip:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)

    categoryChip = meta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    categoryChip:SetPoint("LEFT", authorChip, "RIGHT", 8, 0)

    complexityChip = meta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    complexityChip:SetPoint("LEFT", categoryChip, "RIGHT", 8, 0)

    local resetButton = CreateFrame("Button", nil, meta, "UIPanelButtonTemplate")
    resetButton:SetWidth(54)
    resetButton:SetHeight(22)
    resetButton:SetPoint("RIGHT", -4, 0)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", OnResetBuild)

    local saveButton = CreateFrame("Button", nil, meta, "UIPanelButtonTemplate")
    saveButton:SetWidth(72)
    saveButton:SetHeight(22)
    saveButton:SetPoint("RIGHT", resetButton, "LEFT", -6, 0)
    saveButton:SetText("Save Build")
    saveButton:SetScript("OnClick", OnSaveBuild)

    local importButton = CreateFrame("Button", nil, meta, "UIPanelButtonTemplate")
    importButton:SetWidth(108)
    importButton:SetHeight(22)
    importButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
    importButton:SetText("Import Archetype…")
    importButton:SetScript("OnClick", OnImportArchetype)

    local autoBar = CreateFrame("Frame", nil, mainColumn)
    autoBar:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", 0, -4)
    autoBar:SetPoint("TOPRIGHT", meta, "BOTTOMRIGHT", 0, -4)
    autoBar:SetHeight(52)
    autoBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    autoBar:SetBackdropColor(0.04, 0.08, 0.06, 1)
    autoBar:SetBackdropBorderColor(0.12, 0.23, 0.16, 1)

    local autoLabel = autoBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    autoLabel:SetPoint("TOPLEFT", 8, -6)
    autoLabel:SetText("AUTOMATE")
    autoLabel:SetTextColor(0.42, 0.67, 0.48, 1)

    local applyButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    applyButton:SetWidth(108)
    applyButton:SetHeight(22)
    applyButton:SetPoint("TOPLEFT", autoLabel, "BOTTOMLEFT", 0, -4)
    applyButton:SetText("Apply \226\134\146 Desired")
    applyButton:SetScript("OnClick", OnApplyDesired)

    local rollButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    rollButton:SetWidth(100)
    rollButton:SetHeight(22)
    rollButton:SetPoint("LEFT", applyButton, "RIGHT", 6, 0)
    rollButton:SetText("Start Auto-Roll")
    rollButton:SetScript("OnClick", OnStartAutoRoll)

    local syncButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    syncButton:SetWidth(108)
    syncButton:SetHeight(22)
    syncButton:SetPoint("LEFT", rollButton, "RIGHT", 6, 0)
    syncButton:SetText("Sync from Rapid")
    syncButton:SetScript("OnClick", OnSyncRapid)

    local wishButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    wishButton:SetWidth(88)
    wishButton:SetHeight(22)
    wishButton:SetPoint("LEFT", syncButton, "RIGHT", 6, 0)
    wishButton:SetText("\226\134\222 Wishlist")
    wishButton:SetScript("OnClick", OnLoadWishlist)

    autoStatusLabel = autoBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoStatusLabel:SetPoint("TOPLEFT", applyButton, "BOTTOMLEFT", 0, -4)
    autoStatusLabel:SetPoint("RIGHT", autoBar, "RIGHT", -8, 0)
    autoStatusLabel:SetJustifyH("LEFT")

    local content = CreateFrame("Frame", nil, mainColumn)
    sectionContent = content
    content:SetPoint("TOPLEFT", autoBar, "BOTTOMLEFT", 0, -6)
    content:SetPoint("BOTTOMRIGHT", mainColumn, "BOTTOMRIGHT", 0, 58)

    sectionTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionTitle:SetPoint("TOPLEFT", 4, -2)
    sectionTitle:SetTextColor(1, 0.82, 0.2, 1)

    sectionCount = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sectionCount:SetPoint("TOPRIGHT", -4, -4)
    sectionCount:SetJustifyH("RIGHT")

    filterBar = CreateFrame("Frame", nil, content)
    filterBar:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -8)
    filterBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -24)
    filterBar:SetHeight(24)

    local filterDefs = {
        { key = "core", label = "Core" },
        { key = "optimal", label = "Optimal" },
        { key = "empowering", label = "Empowering" },
        { key = "synergistic", label = "Synergistic" },
    }
    local lastCheck
    for index = 1, #filterDefs do
        local def = filterDefs[index]
        local check = CreateFrame("CheckButton", nil, filterBar, "UICheckButtonTemplate")
        check:SetWidth(20)
        check:SetHeight(20)
        if lastCheck then
            check:SetPoint("LEFT", lastCheck, "RIGHT", 52, 0)
        else
            check:SetPoint("LEFT", 0, 0)
        end
        check:SetChecked(true)
        local text = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
        text:SetText(def.label)
        check:SetScript("OnClick", function()
            spellFilters[def.key] = CheckButtonIsOn(check)
            LoadoutsPanel.Refresh()
        end)
        lastCheck = check
    end

    local addSpellButton = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    addSpellButton:SetWidth(84)
    addSpellButton:SetHeight(22)
    addSpellButton:SetPoint("RIGHT", 0, 0)
    addSpellButton:SetText("+ Add Spell")
    addSpellButton:SetScript("OnClick", OnAddSpell)

    local spellHeight = VISIBLE_SPELL_ROWS * ROW_HEIGHT + LIST_INSET * 2
    spellListFrame, spellScrollFrame = BuildScrollList(content, shellWidth - SIDEBAR_WIDTH - 16, spellHeight,
        CreateSpellRow, spellRows, VISIBLE_SPELL_ROWS, function() LoadoutsPanel.Refresh() end)
    spellListFrame:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)

    equipmentLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    equipmentLabel:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 4, -6)
    equipmentLabel:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -40)
    equipmentLabel:SetJustifyH("LEFT")
    equipmentLabel:Hide()

    notesEdit = CreateFrame("EditBox", FRAME_NAME .. "Notes", content, "InputBoxTemplate")
    notesEdit:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    notesEdit:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 0)
    notesEdit:SetMultiLine(true)
    notesEdit:SetAutoFocus(false)
    notesEdit:SetMaxLetters(8000)
    notesEdit:Hide()

    local foot = CreateFrame("Frame", nil, mainColumn)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(54)

    local copyButton = CreateFrame("Button", nil, foot, "UIPanelButtonTemplate")
    copyButton:SetWidth(88)
    copyButton:SetHeight(22)
    copyButton:SetPoint("BOTTOMLEFT", 0, 28)
    copyButton:SetText("Copy ASUITE1")
    copyButton:SetScript("OnClick", OnCopyShare)

    local importShareButton = CreateFrame("Button", nil, foot, "UIPanelButtonTemplate")
    importShareButton:SetWidth(96)
    importShareButton:SetHeight(22)
    importShareButton:SetPoint("LEFT", copyButton, "RIGHT", 8, 0)
    importShareButton:SetText("Import string…")
    importShareButton:SetScript("OnClick", OnImportShare)

    shareBox = CreateFrame("EditBox", FRAME_NAME .. "Share", foot, "InputBoxTemplate")
    shareBox:SetPoint("BOTTOMLEFT", copyButton, "TOPLEFT", 0, 4)
    shareBox:SetPoint("BOTTOMRIGHT", foot, "BOTTOMRIGHT", 0, 28)
    shareBox:SetHeight(44)
    shareBox:SetMultiLine(true)
    shareBox:SetAutoFocus(false)
    shareBox:SetMaxLetters(8000)

    statusLabel = foot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, -2)
    statusLabel:SetPoint("LEFT", importShareButton, "RIGHT", 12, 0)
    statusLabel:SetJustifyH("RIGHT")

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

function LoadoutsPanel.InvalidateLayout()
    if not panel or not panelParent then
        return
    end

    panel:ClearAllPoints()
    panel:SetAllPoints(panelParent)

    if not panelWidth then
        return
    end

    local shellWidth = panelWidth - LIST_WIDTH - 8
    local detailWidth = shellWidth - SIDEBAR_WIDTH - 16

    if listFrame then
        listFrame:SetWidth(LIST_WIDTH)
        local rowWidth = LIST_WIDTH - LIST_INSET - SCROLLBAR_WIDTH
        for index = 1, VISIBLE_LIST_ROWS do
            local row = listRows[index]
            if row then
                row:SetWidth(rowWidth)
            end
        end
    end

    if buildShell then
        buildShell:SetWidth(shellWidth)
    end

    if spellListFrame then
        spellListFrame:SetWidth(detailWidth)
        local rowWidth = detailWidth - LIST_INSET - SCROLLBAR_WIDTH
        for index = 1, VISIBLE_SPELL_ROWS do
            local row = spellRows[index]
            if row then
                row:SetWidth(rowWidth)
            end
        end
    end

    if shareBox and shareBox.SetWidth then
        shareBox:SetWidth(detailWidth)
    end
    if statusLabel and statusLabel.SetWidth then
        statusLabel:SetWidth(detailWidth * 0.55)
    end
end

function LoadoutsPanel.GetFrame()
    return panel
end

function LoadoutsPanel.GetSelectedId()
    return selectedId
end

function LoadoutsPanel.GetFilteredEntries()
    local rows = {}
    for index = 1, #displayRows do
        if displayRows[index].kind == "spell" then
            rows[#rows + 1] = displayRows[index].entry
        end
    end
    return rows
end

function LoadoutsPanel.GetActiveSection()
    return activeSection
end
