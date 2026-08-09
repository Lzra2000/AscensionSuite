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

local W = {
    listRows = {},
    spellRows = {},
    navButtons = {},
    equipmentRows = {},
}
local H = {}

local EQUIPMENT_ROW_HEIGHT = 28
local MAX_EQUIPMENT_ROWS = 8
local selectedId
local activeSection = "SPELLS_AND_TALENTS"
local displayRows = {}
local spellFilters = { core = true, optimal = true, empowering = true, synergistic = true }
local spellSearchText = ""
local selectedSpellKey

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
    if not W.statusLabel then
        return
    end
    W.statusLabel:SetText(text or "")
    if good == true then
        W.statusLabel:SetTextColor(0.43, 0.81, 0.54, 1)
    elseif good == false then
        W.statusLabel:SetTextColor(0.88, 0.44, 0.44, 1)
    else
        W.statusLabel:SetTextColor(0.65, 0.61, 0.53, 1)
    end
end

local function SetAutoStatus(text, good)
    if not W.autoStatusLabel then
        return
    end
    W.autoStatusLabel:SetText(text or "")
    if good == true then
        W.autoStatusLabel:SetTextColor(0.43, 0.81, 0.54, 1)
    elseif good == false then
        W.autoStatusLabel:SetTextColor(0.88, 0.44, 0.44, 1)
    else
        W.autoStatusLabel:SetTextColor(0.65, 0.61, 0.53, 1)
    end
end

local function IsWildcard()
    local api = GetAPI()
    return api ~= nil and api.IsWildcardModeActive() == true
end

local function SpellRowKey(rawRow, described)
    if type(rawRow) == "table" then
        local entryId = rawRow.entryId
        local entryType = rawRow.entryType
        if entryId and type(entryType) == "string" and entryType ~= "" then
            return entryType .. ":" .. tostring(entryId)
        end
        if rawRow.spellId then
            return "spell:" .. tostring(rawRow.spellId)
        end
    end
    if type(described) == "table" then
        if described.entryId and described.entryType then
            return described.entryType .. ":" .. tostring(described.entryId)
        end
        if described.spellId then
            return "spell:" .. tostring(described.spellId)
        end
    end
    return nil
end

local function PersistActiveSection()
    if not selectedId or not W.notesEdit then
        return
    end
    local Loadouts = GetLoadouts()
    if not Loadouts or activeSection == "SPELLS_AND_TALENTS" or activeSection == "EQUIPMENT" then
        if activeSection == "EQUIPMENT" and W.notesEdit.GetText then
            Loadouts.SetSectionText(selectedId, activeSection, W.notesEdit:GetText())
        end
        return
    end
    if W.notesEdit.GetText then
        Loadouts.SetSectionText(selectedId, activeSection, W.notesEdit:GetText())
    end
end

local function RefreshShareBox()
    if not W.shareBox then
        return
    end
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        W.shareBox:SetText("")
        return
    end
    local text = Loadouts.ExportString(selectedId) or ""
    W.shareBox:SetText(text)
    if W.shareBox.SetCursorPosition then
        W.shareBox:SetCursorPosition(0)
    end
    if W.shareBox.HighlightText then
        W.shareBox:HighlightText(0, 0)
    end
end

local function BuildSpellDisplayRows(loadout)
    displayRows = {}
    if not loadout or type(loadout.entries) ~= "table" then
        return 0
    end

    local Loadouts = GetLoadouts()
    local groups, order, total = Loadouts.GroupEntries(loadout.entries, spellFilters, spellSearchText, loadout)
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
        row._raw = nil
        row._described = nil
        row._select:Hide()
        row:Show()
        return
    end

    row._group:Hide()
    row._spell:Show()
    row:SetHeight(ROW_HEIGHT)
    local entry = data.entry or {}
    local raw = entry.raw or entry
    row._raw = raw
    row._described = entry
    row._displayId = entry.displayId or entry.spellId or entry.entryId
    row._internalId = entry.entryId
    row._name = entry.name

    row._nameLabel:SetText(entry.name or "?")
    row._tagLabel:SetText(entry.tagLabel or "")
    if entry.known then
        row._knownBadge:Show()
    else
        row._knownBadge:Hide()
    end
    if entry.desired then
        row._badge:Show()
    else
        row._badge:Hide()
    end
    row._icon:SetTexture(entry.icon or PLACEHOLDER_ICON)

    local key = SpellRowKey(raw, entry)
    if selectedSpellKey and key and key == selectedSpellKey then
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

local function ShowSpellRowTooltip(row)
    local api = GetAPI()
    if not api or not row._displayId or not GameTooltip then
        return
    end

    local internalId = row._internalId
    local usedNative = api.ShowEntryTooltip(row, row._displayId, "ANCHOR_RIGHT", internalId)

    if not usedNative then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if type(GameTooltip.ClearLines) == "function" then
            GameTooltip:ClearLines()
        end

        local lines = api.GetEntryTooltipLines(row._displayId)
        for index = 1, #lines do
            if index == 1 then
                GameTooltip:SetText(lines[index], 1, 0.82, 0.3)
            else
                GameTooltip:AddLine(lines[index], 1, 1, 1, true)
            end
        end
    end

    local described = row._described
    if described and described.desired then
        GameTooltip:AddLine("Marked Desired in Ascension", 0.35, 0.71, 1)
    elseif IsWildcard() then
        GameTooltip:AddLine("Right-click to toggle Desired", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Desired sync happens in Wildcard mode", 0.6, 0.6, 0.6)
    end
    if described and described.known then
        GameTooltip:AddLine("Known when this build was captured", 0.38, 0.82, 0.53)
    end
    GameTooltip:AddLine("x removes from this build (Ascension Desired untouched)", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Left-click selects this row", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function SelectSpellRow(row, note)
    local key = SpellRowKey(row._raw, row._described)
    if not key then
        return false
    end
    selectedSpellKey = key
    LoadoutsPanel.Refresh(note)
    return true
end

local function OnSpellRowRemove(row)
    local Loadouts = GetLoadouts()
    local raw = row._raw
    if not Loadouts or not selectedId or not raw then
        return
    end

    local name = row._name or "entry"
    local ok, reason = Loadouts.RemoveEntry(selectedId, raw)
    if not ok then
        SetStatus("Could not remove " .. name .. " — " .. tostring(reason or "error") .. ".", false)
        return
    end

    if selectedSpellKey and SpellRowKey(raw, row._described) == selectedSpellKey then
        selectedSpellKey = nil
    end
    if GameTooltip then
        GameTooltip:Hide()
    end
    LoadoutsPanel.Refresh("Removed " .. name .. " from this build.", true)
end

local function OnSpellRowToggleDesired(row)
    local Loadouts = GetLoadouts()
    local raw = row._raw
    if not Loadouts or not selectedId or not raw then
        return
    end

    if not IsWildcard() then
        SelectSpellRow(row, "Selected " .. (row._name or "entry")
            .. ". Desired is Wildcard-only — Apply marks rows when you enter Wildcard.")
        return
    end

    local ok, result, label = Loadouts.ToggleEntryDesired(selectedId, raw)
    if not ok then
        SelectSpellRow(row, "Selected " .. (label or row._name or "entry")
            .. ". Ascension will not accept that entry as Desired right now.")
        return
    end

    SelectSpellRow(row)
end

local function OnSpellRowClick(row, button)
    if button == "RightButton" then
        OnSpellRowToggleDesired(row)
        return
    end
    SelectSpellRow(row, "Selected " .. (row._name or "entry") .. ".")
end

local function UpdateHeader(loadout)
    if not loadout then
        if W.nameLabel then W.nameLabel:SetText("No build selected") end
        if W.authorChip then W.authorChip:SetText("") end
        if W.categoryChip then W.categoryChip:Hide() end
        if W.complexityChip then W.complexityChip:Hide() end
        return
    end

    if W.nameLabel then
        W.nameLabel:SetText(loadout.name or "Untitled build")
        W.nameLabel:Show()
    end
    if W.nameEdit then
        W.nameEdit:Hide()
    end
    if W.authorChip then
        W.authorChip:SetText(string.format("Author %s", loadout.author or "?"))
    end
    if W.categoryChip then
        if loadout.category and loadout.category ~= "" then
            W.categoryChip:SetText(loadout.category)
            W.categoryChip:Show()
        else
            W.categoryChip:SetText("Category —")
            W.categoryChip:Show()
        end
    end
    if W.complexityChip then
        if loadout.complexity and loadout.complexity ~= "" then
            W.complexityChip:SetText(string.format("Complexity %s", loadout.complexity))
            W.complexityChip:Show()
        else
            W.complexityChip:SetText("Complexity —")
            W.complexityChip:Show()
        end
    end
end

local function UpdateAutoStatus(loadout)
    if not loadout then
        SetAutoStatus("Select or create a build to automate.", nil)
        return
    end

    local Loadouts = GetLoadouts()
    local desired, total = 0, 0
    if Loadouts and Loadouts.CountFilteredDesired then
        desired, total = Loadouts.CountFilteredDesired(loadout, spellFilters)
    else
        total = type(loadout.entries) == "table" and #loadout.entries or 0
        desired = Loadouts and Loadouts.CountDesiredInLoadout(loadout) or 0
    end
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

local function FillEquipmentRow(row, described)
    if not row or not described then
        row:Hide()
        return
    end
    row._nameLabel:SetText(described.name or "?")
    row._icon:SetTexture(described.icon or PLACEHOLDER_ICON)
    row:Show()
end

local function RefreshEquipmentRows(loadout)
    if not W.equipmentFrame then
        return 0
    end

    local Loadouts = GetLoadouts()
    local stubs = {}
    if loadout and type(loadout.equipment) == "table" then
        local armor = loadout.equipment.armorTypes or {}
        local weapons = loadout.equipment.weaponTypes or {}
        for index = 1, #armor do
            stubs[#stubs + 1] = Loadouts and Loadouts.DescribeEquipmentStub(armor[index])
        end
        for index = 1, #weapons do
            stubs[#stubs + 1] = Loadouts and Loadouts.DescribeEquipmentStub(weapons[index])
        end
    end

    for index = 1, MAX_EQUIPMENT_ROWS do
        local row = W.equipmentRows[index]
        if row then
            FillEquipmentRow(row, stubs[index])
            if not stubs[index] then
                row:Hide()
            end
        end
    end

    return #stubs
end

local function RefreshSectionContent(loadout)
    if not W.sectionTitle or not W.sectionCount then
        return
    end

    local Loadouts = GetLoadouts()
    local label = Loadouts and Loadouts.GetSectionLabel(activeSection) or activeSection
    W.sectionTitle:SetText(label)

    if activeSection == "SPELLS_AND_TALENTS" then
        if W.prosPreview then W.prosPreview:Hide() end
        if W.filterBar then W.filterBar:Show() end
        if W.notesEdit then W.notesEdit:Hide() end
        if W.equipmentFrame then W.equipmentFrame:Hide() end
        if W.spellListFrame then W.spellListFrame:Show() end

        local total = BuildSpellDisplayRows(loadout)
        W.sectionCount:SetText(string.format("%d entries \194\183 grouped by class like Archetypes", total))

        if type(_G.FauxScrollFrame_Update) == "function" and W.spellScrollFrame then
            _G.FauxScrollFrame_Update(W.spellScrollFrame, #displayRows, VISIBLE_SPELL_ROWS, ROW_HEIGHT)
        end

        local offset = ScrollOffset(W.spellScrollFrame)
        local maxOffset = #displayRows - VISIBLE_SPELL_ROWS
        if maxOffset < 0 then
            maxOffset = 0
        end
        if offset > maxOffset then
            offset = maxOffset
            if W.spellScrollFrame and type(_G.FauxScrollFrame_SetOffset) == "function" then
                _G.FauxScrollFrame_SetOffset(W.spellScrollFrame, offset)
            end
        end

        for index = 1, VISIBLE_SPELL_ROWS do
            local row = W.spellRows[index]
            local data = displayRows[index + offset]
            if data then
                FillSpellRow(row, data, index)
            else
                row:Hide()
            end
        end
        return
    end

    if W.spellListFrame then W.spellListFrame:Hide() end
    if W.filterBar then W.filterBar:Hide() end
    if W.notesEdit then W.notesEdit:Show() end

    if activeSection == "EQUIPMENT" and W.equipmentFrame and loadout then
        W.equipmentFrame:Show()
        local stubCount = RefreshEquipmentRows(loadout)
        W.sectionCount:SetText(string.format("%d equipment stubs from archetype import", stubCount))

        if W.notesEdit then
            W.notesEdit:Show()
            if W.notesEdit.SetText then
                local sections = Loadouts and Loadouts.GetSections(loadout) or {}
                W.notesEdit:SetText(sections.EQUIPMENT or "")
            end
            if W.notesEdit.ClearAllPoints then
                W.notesEdit:ClearAllPoints()
                if stubCount > 0 then
                    W.notesEdit:SetPoint("TOPLEFT", W.equipmentFrame, "BOTTOMLEFT", 0, -8)
                else
                    W.notesEdit:SetPoint("TOPLEFT", W.sectionTitle, "BOTTOMLEFT", 0, -8)
                end
                W.notesEdit:SetPoint("BOTTOMRIGHT", W.sectionContent, "BOTTOMRIGHT", -4, 0)
            end
        end
        return
    end

    if W.equipmentFrame then W.equipmentFrame:Hide() end
    if W.prosPreview then W.prosPreview:Hide() end
    W.sectionCount:SetText("local notes (SavedVariables)")
    if W.notesEdit and W.notesEdit.SetText and loadout then
        local sections = Loadouts and Loadouts.GetSections(loadout) or {}
        local raw = sections[activeSection] or ""
        if activeSection == "PROS_AND_CONS" and Loadouts and Loadouts.FormatProsAndCons then
            if W.prosPreview then
                W.prosPreview:Show()
                W.prosPreview:SetText(Loadouts.FormatProsAndCons(raw))
            end
            if W.notesEdit.ClearAllPoints then
                W.notesEdit:ClearAllPoints()
                W.notesEdit:SetPoint("TOPLEFT", W.prosPreview, "BOTTOMLEFT", 0, -6)
                W.notesEdit:SetPoint("BOTTOMRIGHT", W.sectionContent, "BOTTOMRIGHT", -4, 0)
            end
        else
            if W.notesEdit.ClearAllPoints then
                W.notesEdit:ClearAllPoints()
                W.notesEdit:SetPoint("TOPLEFT", W.sectionTitle, "BOTTOMLEFT", 0, -8)
                W.notesEdit:SetPoint("BOTTOMRIGHT", W.sectionContent, "BOTTOMRIGHT", -4, 0)
            end
        end
        W.notesEdit:SetText(raw)
    end
end

local function RefreshNav()
    local Loadouts = GetLoadouts()
    if not Loadouts then
        return
    end
    for index = 1, #W.navButtons do
        local button = W.navButtons[index]
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
    if not W.panel then
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

    if type(_G.FauxScrollFrame_Update) == "function" and W.scrollFrame then
        _G.FauxScrollFrame_Update(W.scrollFrame, #list, VISIBLE_LIST_ROWS, ROW_HEIGHT)
    end

    local offset = ScrollOffset(W.scrollFrame)
    for index = 1, VISIBLE_LIST_ROWS do
        local row = W.listRows[index]
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

H.SelectLoadout = function(id)
    PersistActiveSection()
    selectedId = id
    selectedSpellKey = nil
    LoadoutsPanel.Refresh()
end

H.SelectSection = function(key)
    PersistActiveSection()
    activeSection = key
    LoadoutsPanel.Refresh()
end

H.OnSaveBuild = function()
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

H.OnResetBuild = function()
    PersistActiveSection()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Nothing selected to reset.", false)
        return
    end
    Loadouts.ResetToSaved(selectedId)
    LoadoutsPanel.Refresh("Discarded unsaved section edits.", true)
end

H.OnImportArchetype = function()
    PersistActiveSection()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select or create a build first.", false)
        return
    end
    local ok, count, source = Loadouts.ImportFromArchetype(selectedId)
    if not ok then
        local detail = Loadouts.DescribeImportError and Loadouts.DescribeImportError(count) or tostring(count or "error")
        SetStatus("Import failed — " .. detail .. ".", false)
        return
    end
    local note = string.format("Imported %d spells from %s build.", count or 0, source or "native")
    LoadoutsPanel.Refresh(note, true)
end

H.OnLoadWishlist = function()
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

H.OnApplyDesired = function()
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

H.OnSyncRapid = function()
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

H.OnCaptureKnown = function()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select a build first.", false)
        return
    end
    local ok, count = Loadouts.CaptureKnown(selectedId)
    if not ok then
        local detail = Loadouts.DescribeImportError and Loadouts.DescribeImportError(count) or tostring(count or "error")
        SetStatus("Capture Known failed — " .. detail .. ".", false)
        return
    end
    LoadoutsPanel.Refresh(string.format("Captured %d Known entries into this build.", count or 0), true)
end

H.OnCycleCategory = function()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        return
    end
    local loadout = Loadouts.Get(selectedId)
    if not loadout then
        return
    end
    local nextCategory = Loadouts.CycleCategory(loadout.category)
    Loadouts.UpdateMeta(selectedId, { category = nextCategory })
    LoadoutsPanel.Refresh()
end

H.OnCycleComplexity = function()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        return
    end
    local loadout = Loadouts.Get(selectedId)
    if not loadout then
        return
    end
    local nextComplexity = Loadouts.CycleComplexity(loadout.complexity)
    Loadouts.UpdateMeta(selectedId, { complexity = nextComplexity })
    LoadoutsPanel.Refresh()
end

H.OnStartAutoRoll = function()
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

H.OnAddSpellFromInput = function()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select a build first.", false)
        return
    end
    if not W.addSpellBox then
        return
    end

    local text = W.addSpellBox:GetText()
    local id = tonumber(text)
    if not id then
        SetStatus("Type a spell id or an advancement entry id.", false)
        return
    end

    local ok, result = Loadouts.AddById(selectedId, id)
    W.addSpellBox:SetText("")

    if not ok then
        if result == "duplicate" then
            SetStatus("That entry is already on this build.", false)
        elseif result == "entry_limit" then
            SetStatus("This build already has the maximum number of entries.", false)
        else
            SetStatus("Could not add " .. tostring(id) .. ".", false)
        end
        return
    end

    LoadoutsPanel.Refresh(string.format("Added entry %d to this build.", id), true)
end

H.OnRenameBuild = function()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId or not W.nameEdit then
        SetStatus("Select a build first.", false)
        return
    end

    local loadout = Loadouts.Get(selectedId)
    if not loadout then
        return
    end

    if W.nameEdit.IsShown and W.nameEdit:IsShown() then
        local newName = W.nameEdit:GetText()
        Loadouts.Rename(selectedId, newName)
        if W.nameLabel then
            W.nameLabel:Show()
        end
        W.nameEdit:Hide()
        LoadoutsPanel.Refresh(string.format("Renamed build to \"%s\".", newName or "Untitled"), true)
        return
    end

    if W.nameLabel then
        W.nameLabel:Hide()
    end
    W.nameEdit:SetText(loadout.name or "")
    W.nameEdit:Show()
    if W.nameEdit.SetFocus then
        W.nameEdit:SetFocus()
    end
end

H.OnNewBuild = function()
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

H.OnDuplicateBuild = function()
    local Loadouts = GetLoadouts()
    if not Loadouts or not selectedId then
        SetStatus("Select a build to duplicate.", false)
        return
    end
    local sourceName = Loadouts.Get(selectedId) and Loadouts.Get(selectedId).name or "build"
    local clone, newId = Loadouts.Duplicate(selectedId)
    if not clone then
        SetStatus("Could not duplicate — " .. tostring(newId or "error") .. ".", false)
        return
    end
    selectedId = newId
    selectedSpellKey = nil
    LoadoutsPanel.Refresh(string.format("Duplicated \"%s\" as \"%s\".", sourceName, clone.name or "copy"), true)
end

H.OnDeleteBuild = function()
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

H.OnCopyShare = function()
    if not W.shareBox then
        return
    end
    local text = W.shareBox:GetText()
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

H.OnImportShare = function()
    local Loadouts = GetLoadouts()
    if not Loadouts then
        return
    end
    local text = W.shareBox and W.shareBox:GetText() or ""
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

local function CreateListRow(parent, index)
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
        if row._id then
            H.SelectLoadout(row._id)
        end
    end)
    return row
end

local function CreateSpellRow(parent, index)
    local row = CreateFrame("Button", FRAME_NAME .. "SpellRow" .. index, parent)
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

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(1, 0.82, 0.2, 0.12)

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
    badge:SetPoint("RIGHT", -30, 0)
    badge:SetWidth(48)
    badge:SetJustifyH("RIGHT")
    badge:SetTextColor(0.35, 0.71, 1, 1)
    badge:SetText("Desired")
    row._badge = badge

    local knownBadge = spell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    knownBadge:SetPoint("RIGHT", badge, "LEFT", -6, 0)
    knownBadge:SetWidth(44)
    knownBadge:SetJustifyH("RIGHT")
    knownBadge:SetTextColor(0.38, 0.82, 0.53, 1)
    knownBadge:SetText("Known")
    row._knownBadge = knownBadge

    local tagLabel = spell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tagLabel:SetPoint("RIGHT", knownBadge, "LEFT", -6, 0)
    tagLabel:SetWidth(64)
    tagLabel:SetJustifyH("RIGHT")
    row._tagLabel = tagLabel

    local nameLabel = spell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameLabel:SetPoint("RIGHT", tagLabel, "LEFT", -8, 0)
    nameLabel:SetJustifyH("LEFT")
    row._nameLabel = nameLabel

    local remove = CreateFrame("Button", FRAME_NAME .. "SpellRow" .. index .. "Remove", row, "UIPanelButtonTemplate")
    remove:SetWidth(20)
    remove:SetHeight(18)
    remove:SetPoint("RIGHT", -4, 0)
    remove:SetText("x")
    remove:SetScript("OnClick", function()
        OnSpellRowRemove(row)
    end)
    row._remove = remove

    row:SetScript("OnEnter", function()
        if row._raw then
            ShowSpellRowTooltip(row)
        end
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnClick", function(_, button)
        if row._raw then
            OnSpellRowClick(row, button)
        end
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

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
        H.SelectSection(key)
    end)
    return button
end

local function BuildPanel(parent, width)
    local contentWidth = width or 640
    W.panel = CreateFrame("Frame", FRAME_NAME, parent)
    W.panel:SetAllPoints()
    W.panelParent = parent
    W.panelWidth = contentWidth

    local shellWidth = contentWidth - LIST_WIDTH - 8

    local listLabel = W.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", 0, 0)
    listLabel:SetText("Saved builds")

    W.listFrame, W.scrollFrame = BuildScrollList(W.panel, LIST_WIDTH, VISIBLE_LIST_ROWS * ROW_HEIGHT + LIST_INSET * 2,
        CreateListRow, W.listRows, VISIBLE_LIST_ROWS, function() LoadoutsPanel.Refresh() end)
    W.listFrame:SetPoint("TOPLEFT", 0, -16)

    local newButton = CreateFrame("Button", nil, W.panel, "UIPanelButtonTemplate")
    newButton:SetWidth(58)
    newButton:SetHeight(22)
    newButton:SetPoint("TOPLEFT", W.listFrame, "BOTTOMLEFT", 0, -6)
    newButton:SetText("New")
    newButton:SetScript("OnClick", function() H.OnNewBuild() end)

    local deleteButton = CreateFrame("Button", nil, W.panel, "UIPanelButtonTemplate")
    deleteButton:SetWidth(58)
    deleteButton:SetHeight(22)
    deleteButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", function() H.OnDeleteBuild() end)

    local duplicateButton = CreateFrame("Button", nil, W.panel, "UIPanelButtonTemplate")
    duplicateButton:SetWidth(68)
    duplicateButton:SetHeight(22)
    duplicateButton:SetPoint("LEFT", deleteButton, "RIGHT", 6, 0)
    duplicateButton:SetText("Duplicate")
    duplicateButton:SetScript("OnClick", function() H.OnDuplicateBuild() end)

    W.buildShell = CreateFrame("Frame", nil, W.panel)
    W.buildShell:SetPoint("TOPLEFT", W.listFrame, "TOPRIGHT", 8, 0)
    W.buildShell:SetWidth(shellWidth)
    W.buildShell:SetHeight(430)
    W.buildShell:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    W.buildShell:SetBackdropColor(0.035, 0.03, 0.02, 0.95)
    W.buildShell:SetBackdropBorderColor(0.45, 0.38, 0.20, 1)

    W.sectionSidebar = CreateFrame("Frame", nil, W.buildShell)
    W.sectionSidebar:SetWidth(SIDEBAR_WIDTH)
    W.sectionSidebar:SetPoint("TOPLEFT", 4, -4)
    W.sectionSidebar:SetPoint("BOTTOMLEFT", 4, 4)
    W.sectionSidebar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    W.sectionSidebar:SetBackdropColor(0.10, 0.09, 0.06, 1)
    W.sectionSidebar:SetBackdropBorderColor(0.35, 0.30, 0.18, 1)

    local Loadouts = GetLoadouts()
    local y = -4
    for index = 1, #(Loadouts and Loadouts.SECTION_ORDER or {}) do
        local key = Loadouts.SECTION_ORDER[index]
        W.navButtons[index] = CreateNavButton(W.sectionSidebar, key, y)
        y = y - 34
    end

    W.mainColumn = CreateFrame("Frame", nil, W.buildShell)
    W.mainColumn:SetPoint("TOPLEFT", W.sectionSidebar, "TOPRIGHT", 4, 0)
    W.mainColumn:SetPoint("BOTTOMRIGHT", W.buildShell, "BOTTOMRIGHT", -4, 4)

    local meta = CreateFrame("Frame", nil, W.mainColumn)
    meta:SetPoint("TOPLEFT", 0, 0)
    meta:SetPoint("TOPRIGHT", 0, 0)
    meta:SetHeight(34)

    W.nameLabel = meta:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    W.nameLabel:SetPoint("LEFT", 8, 0)
    W.nameLabel:SetTextColor(1, 0.82, 0.2, 1)
    W.nameLabel:SetText("No build selected")

    W.nameEdit = CreateFrame("EditBox", FRAME_NAME .. "NameEdit", meta, "InputBoxTemplate")
    W.nameEdit:SetPoint("LEFT", 8, 0)
    W.nameEdit:SetWidth(140)
    W.nameEdit:SetHeight(22)
    W.nameEdit:SetAutoFocus(false)
    W.nameEdit:SetMaxLetters(64)
    W.nameEdit:Hide()
    W.nameEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        H.OnRenameBuild()
    end)
    W.nameEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:Hide()
        if W.nameLabel then
            W.nameLabel:Show()
        end
    end)

    local renameButton = CreateFrame("Button", nil, meta, "UIPanelButtonTemplate")
    renameButton:SetWidth(54)
    renameButton:SetHeight(22)
    renameButton:SetPoint("LEFT", W.nameLabel, "RIGHT", 4, 0)
    renameButton:SetText("Rename")
    renameButton:SetScript("OnClick", function() H.OnRenameBuild() end)

    W.authorChip = meta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    W.authorChip:SetPoint("LEFT", renameButton, "RIGHT", 8, 0)

    W.categoryChip = meta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    W.categoryChip:SetPoint("LEFT", W.authorChip, "RIGHT", 8, 0)

    local categoryButton = CreateFrame("Button", nil, meta)
    categoryButton:SetPoint("LEFT", W.categoryChip, "LEFT", -4, 0)
    categoryButton:SetPoint("RIGHT", W.categoryChip, "RIGHT", 4, 0)
    categoryButton:SetHeight(22)
    categoryButton:SetScript("OnClick", function() H.OnCycleCategory() end)

    W.complexityChip = meta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    W.complexityChip:SetPoint("LEFT", W.categoryChip, "RIGHT", 8, 0)

    local complexityButton = CreateFrame("Button", nil, meta)
    complexityButton:SetPoint("LEFT", W.complexityChip, "LEFT", -4, 0)
    complexityButton:SetPoint("RIGHT", W.complexityChip, "RIGHT", 4, 0)
    complexityButton:SetHeight(22)
    complexityButton:SetScript("OnClick", function() H.OnCycleComplexity() end)

    local resetButton = CreateFrame("Button", nil, meta, "UIPanelButtonTemplate")
    resetButton:SetWidth(54)
    resetButton:SetHeight(22)
    resetButton:SetPoint("RIGHT", -4, 0)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function() H.OnResetBuild() end)

    local saveButton = CreateFrame("Button", nil, meta, "UIPanelButtonTemplate")
    saveButton:SetWidth(72)
    saveButton:SetHeight(22)
    saveButton:SetPoint("RIGHT", resetButton, "LEFT", -6, 0)
    saveButton:SetText("Save Build")
    saveButton:SetScript("OnClick", function() H.OnSaveBuild() end)

    local importButton = CreateFrame("Button", nil, meta, "UIPanelButtonTemplate")
    importButton:SetWidth(108)
    importButton:SetHeight(22)
    importButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
    importButton:SetText("Import Archetype…")
    importButton:SetScript("OnClick", function() H.OnImportArchetype() end)

    local autoBar = CreateFrame("Frame", nil, W.mainColumn)
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
    applyButton:SetScript("OnClick", function() H.OnApplyDesired() end)

    local rollButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    rollButton:SetWidth(100)
    rollButton:SetHeight(22)
    rollButton:SetPoint("LEFT", applyButton, "RIGHT", 6, 0)
    rollButton:SetText("Start Auto-Roll")
    rollButton:SetScript("OnClick", function() H.OnStartAutoRoll() end)

    local syncButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    syncButton:SetWidth(108)
    syncButton:SetHeight(22)
    syncButton:SetPoint("LEFT", rollButton, "RIGHT", 6, 0)
    syncButton:SetText("Sync from Rapid")
    syncButton:SetScript("OnClick", function() H.OnSyncRapid() end)

    local wishButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    wishButton:SetWidth(88)
    wishButton:SetHeight(22)
    wishButton:SetPoint("LEFT", syncButton, "RIGHT", 6, 0)
    wishButton:SetText("\226\134\222 Wishlist")
    wishButton:SetScript("OnClick", function() H.OnLoadWishlist() end)

    local captureButton = CreateFrame("Button", nil, autoBar, "UIPanelButtonTemplate")
    captureButton:SetWidth(100)
    captureButton:SetHeight(22)
    captureButton:SetPoint("LEFT", wishButton, "RIGHT", 6, 0)
    captureButton:SetText("Capture Known")
    captureButton:SetScript("OnClick", function() H.OnCaptureKnown() end)

    W.autoStatusLabel = autoBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.autoStatusLabel:SetPoint("TOPLEFT", applyButton, "BOTTOMLEFT", 0, -4)
    W.autoStatusLabel:SetPoint("RIGHT", autoBar, "RIGHT", -8, 0)
    W.autoStatusLabel:SetJustifyH("LEFT")

    local content = CreateFrame("Frame", nil, W.mainColumn)
    W.sectionContent = content
    content:SetPoint("TOPLEFT", autoBar, "BOTTOMLEFT", 0, -6)
    content:SetPoint("BOTTOMRIGHT", W.mainColumn, "BOTTOMRIGHT", 0, 58)

    W.sectionTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    W.sectionTitle:SetPoint("TOPLEFT", 4, -2)
    W.sectionTitle:SetTextColor(1, 0.82, 0.2, 1)

    W.sectionCount = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    W.sectionCount:SetPoint("TOPRIGHT", -4, -4)
    W.sectionCount:SetJustifyH("RIGHT")

    W.filterBar = CreateFrame("Frame", nil, content)
    W.filterBar:SetPoint("TOPLEFT", W.sectionTitle, "BOTTOMLEFT", 0, -8)
    W.filterBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -24)
    W.filterBar:SetHeight(24)

    local searchLabel = W.filterBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchLabel:SetPoint("TOPLEFT", 0, 2)
    searchLabel:SetText("Search")

    W.spellSearchBox = CreateFrame("EditBox", FRAME_NAME .. "SpellSearch", W.filterBar, "InputBoxTemplate")
    W.spellSearchBox:SetHeight(22)
    W.spellSearchBox:SetWidth(88)
    W.spellSearchBox:SetPoint("LEFT", searchLabel, "RIGHT", 4, 0)
    W.spellSearchBox:SetAutoFocus(false)
    W.spellSearchBox:SetMaxLetters(40)
    W.spellSearchBox:SetScript("OnTextChanged", function(self)
        spellSearchText = self:GetText() or ""
        LoadoutsPanel.Refresh()
    end)
    W.spellSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    local filterDefs = {
        { key = "core", label = "Core" },
        { key = "optimal", label = "Optimal" },
        { key = "empowering", label = "Empowering" },
        { key = "synergistic", label = "Synergistic" },
    }
    local lastCheck
    for index = 1, #filterDefs do
        local def = filterDefs[index]
        local check = CreateFrame("CheckButton", nil, W.filterBar, "UICheckButtonTemplate")
        check:SetWidth(20)
        check:SetHeight(20)
        if lastCheck then
            check:SetPoint("LEFT", lastCheck, "RIGHT", 52, 0)
        else
            check:SetPoint("LEFT", W.spellSearchBox, "RIGHT", 10, 0)
        end
        check:SetChecked(true)
        local text = W.filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
        text:SetText(def.label)
        check:SetScript("OnClick", function()
            spellFilters[def.key] = CheckButtonIsOn(check)
            LoadoutsPanel.Refresh()
        end)
        lastCheck = check
    end

    local addSpellButton = CreateFrame("Button", nil, W.filterBar, "UIPanelButtonTemplate")
    addSpellButton:SetWidth(44)
    addSpellButton:SetHeight(22)
    addSpellButton:SetPoint("RIGHT", 0, 0)
    addSpellButton:SetText("Add")
    addSpellButton:SetScript("OnClick", function() H.OnAddSpellFromInput() end)

    W.addSpellBox = CreateFrame("EditBox", FRAME_NAME .. "AddSpell", W.filterBar, "InputBoxTemplate")
    W.addSpellBox:SetHeight(22)
    W.addSpellBox:SetWidth(72)
    W.addSpellBox:SetPoint("RIGHT", addSpellButton, "LEFT", -6, 0)
    W.addSpellBox:SetAutoFocus(false)
    W.addSpellBox:SetNumeric(true)
    W.addSpellBox:SetMaxLetters(9)
    W.addSpellBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        H.OnAddSpellFromInput()
    end)

    W.prosPreview = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.prosPreview:SetPoint("TOPLEFT", W.sectionTitle, "BOTTOMLEFT", 0, -8)
    W.prosPreview:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -32)
    W.prosPreview:SetJustifyH("LEFT")
    W.prosPreview:Hide()

    local spellHeight = VISIBLE_SPELL_ROWS * ROW_HEIGHT + LIST_INSET * 2
    W.spellListFrame, W.spellScrollFrame = BuildScrollList(content, shellWidth - SIDEBAR_WIDTH - 16, spellHeight,
        CreateSpellRow, W.spellRows, VISIBLE_SPELL_ROWS, function() LoadoutsPanel.Refresh() end)
    W.spellListFrame:SetPoint("TOPLEFT", W.filterBar, "BOTTOMLEFT", 0, -6)

    W.equipmentFrame = CreateFrame("Frame", nil, content)
    W.equipmentFrame:SetPoint("TOPLEFT", W.filterBar, "BOTTOMLEFT", 0, -6)
    W.equipmentFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -40)
    W.equipmentFrame:SetHeight(MAX_EQUIPMENT_ROWS * EQUIPMENT_ROW_HEIGHT)
    W.equipmentFrame:Hide()

    local function CreateEquipmentRow(parent, index)
        local row = CreateFrame("Frame", FRAME_NAME .. "EquipRow" .. index, parent)
        row:SetHeight(EQUIPMENT_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * EQUIPMENT_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -(index - 1) * EQUIPMENT_ROW_HEIGHT)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(22)
        icon:SetHeight(22)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row._icon = icon

        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        nameLabel:SetJustifyH("LEFT")
        row._nameLabel = nameLabel

        return row
    end

    for index = 1, MAX_EQUIPMENT_ROWS do
        W.equipmentRows[index] = CreateEquipmentRow(W.equipmentFrame, index)
        W.equipmentRows[index]:Hide()
    end

    W.notesEdit = CreateFrame("EditBox", FRAME_NAME .. "Notes", content, "InputBoxTemplate")
    W.notesEdit:SetPoint("TOPLEFT", W.filterBar, "BOTTOMLEFT", 0, -6)
    W.notesEdit:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 0)
    W.notesEdit:SetMultiLine(true)
    W.notesEdit:SetAutoFocus(false)
    W.notesEdit:SetMaxLetters(8000)
    W.notesEdit:Hide()

    local foot = CreateFrame("Frame", nil, W.mainColumn)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(54)

    local copyButton = CreateFrame("Button", nil, foot, "UIPanelButtonTemplate")
    copyButton:SetWidth(88)
    copyButton:SetHeight(22)
    copyButton:SetPoint("BOTTOMLEFT", 0, 28)
    copyButton:SetText("Copy share")
    copyButton:SetScript("OnClick", function() H.OnCopyShare() end)

    local importShareButton = CreateFrame("Button", nil, foot, "UIPanelButtonTemplate")
    importShareButton:SetWidth(96)
    importShareButton:SetHeight(22)
    importShareButton:SetPoint("LEFT", copyButton, "RIGHT", 8, 0)
    importShareButton:SetText("Import string…")
    importShareButton:SetScript("OnClick", function() H.OnImportShare() end)

    W.shareBox = CreateFrame("EditBox", FRAME_NAME .. "Share", foot, "InputBoxTemplate")
    W.shareBox:SetPoint("BOTTOMLEFT", copyButton, "TOPLEFT", 0, 4)
    W.shareBox:SetPoint("BOTTOMRIGHT", foot, "BOTTOMRIGHT", 0, 28)
    W.shareBox:SetHeight(44)
    W.shareBox:SetMultiLine(true)
    W.shareBox:SetAutoFocus(false)
    W.shareBox:SetMaxLetters(8000)

    W.statusLabel = foot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.statusLabel:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, -2)
    W.statusLabel:SetPoint("LEFT", importShareButton, "RIGHT", 12, 0)
    W.statusLabel:SetJustifyH("RIGHT")

    LoadoutsPanel.Refresh()
    return W.panel
end

function LoadoutsPanel.EnsureBuilt(parent, width)
    if W.panel then
        return W.panel
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
    if not W.panel or not W.panelParent then
        return
    end

    W.panel:ClearAllPoints()
    W.panel:SetAllPoints(W.panelParent)

    if not W.panelWidth then
        return
    end

    local shellWidth = W.panelWidth - LIST_WIDTH - 8
    local detailWidth = shellWidth - SIDEBAR_WIDTH - 16

    if W.listFrame then
        W.listFrame:SetWidth(LIST_WIDTH)
        local rowWidth = LIST_WIDTH - LIST_INSET - SCROLLBAR_WIDTH
        for index = 1, VISIBLE_LIST_ROWS do
            local row = W.listRows[index]
            if row then
                row:SetWidth(rowWidth)
            end
        end
    end

    if W.buildShell then
        W.buildShell:SetWidth(shellWidth)
    end

    if W.spellListFrame then
        W.spellListFrame:SetWidth(detailWidth)
        local rowWidth = detailWidth - LIST_INSET - SCROLLBAR_WIDTH
        for index = 1, VISIBLE_SPELL_ROWS do
            local row = W.spellRows[index]
            if row then
                row:SetWidth(rowWidth)
            end
        end
    end

    if W.shareBox and W.shareBox.SetWidth then
        W.shareBox:SetWidth(detailWidth)
    end
    if W.statusLabel and W.statusLabel.SetWidth then
        W.statusLabel:SetWidth(detailWidth * 0.55)
    end
end

function LoadoutsPanel.GetFrame()
    return W.panel
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
