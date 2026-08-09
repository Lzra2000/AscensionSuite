-- AscensionSuite: ui/WishlistPanel.lua
-- The Wishlist tab of /asuite: search, scroll, add, remove, push to Desired.
--
-- Everything here works in any game mode. Only "Push to Desired" is gated on
-- Wildcard, because Desired is a Wildcard-only concept in the client -- the list
-- itself is the player's and persists across modes and sessions.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local WishlistPanel = {}
AscensionSuite.WishlistPanel = WishlistPanel

local FRAME_NAME = "AscensionSuiteWishlistPanel"
local ROW_HEIGHT = 28
local VISIBLE_ROWS = 8
local LIST_INSET = 4
local SCROLLBAR_WIDTH = 24
local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- How long a row stays lit after it was just added or toggled. Long enough to
-- catch the eye when the click happened in another window (Alt + right-click in
-- the Character Advancement book), short enough not to look like state.
local TOUCH_SECONDS = 4

local panel
local panelParent
local panelWidth
local searchBox
local addBox
local listFrame
local scrollFrame
local pushButton
local clearButton
local countLabel
local statusLabel
local emptyLabel
local hint
local touchTicker
local rows = {}
local filtered = {}
local touchedKey
local touchedUntil
local selectedKey

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function GetWishlist()
    return AscensionSuite.Wishlist
end

local function Chrome()
    return AscensionSuite.NativeChrome
end

local function IsWildcard()
    local api = GetAPI()
    return api ~= nil and api.IsWildcardModeActive() == true
end

local function Now()
    if type(_G.GetTime) == "function" then
        return _G.GetTime()
    end
    return nil
end

local function ScrollOffset()
    if scrollFrame and type(_G.FauxScrollFrame_GetOffset) == "function" then
        return tonumber(_G.FauxScrollFrame_GetOffset(scrollFrame)) or 0
    end
    return 0
end

------------------------------------------------------------------------
-- "That click landed" feedback
--
-- A wishlist edit can come from three places and only one of them is this panel,
-- so the row itself is where the confirmation belongs: Alt + right-click in the
-- book has no chat line to spare per spell, and nothing may be drawn on
-- Ascension's own widgets.
------------------------------------------------------------------------

local function RowKey(entryId, entryType, spellId)
    local id = tonumber(entryId)
    if id and type(entryType) == "string" and entryType ~= "" then
        return entryType .. ":" .. tostring(id)
    end
    local spell = tonumber(spellId)
    if spell then
        return "spell:" .. tostring(spell)
    end
    return nil
end

local function ItemKey(item)
    if type(item) ~= "table" then
        return nil
    end
    return RowKey(item.entryId, item.entryType, item.spellId)
end

-- No clock means no way to put the highlight out again, so it is never lit: a row
-- stuck lit forever would read as state rather than as feedback.
local function TouchExpired()
    if not touchedKey or not touchedUntil then
        return true
    end
    local now = Now()
    return now == nil or now >= touchedUntil
end

-- Marks the row for an entry as just-touched. Safe to call before the panel has
-- been built: the next Refresh picks it up, and an expired touch is dropped.
function WishlistPanel.NoteTouched(entryId, entryType, spellId)
    local key = RowKey(entryId, entryType, spellId)
    if not key then
        return false
    end

    touchedKey = key
    local now = Now()
    touchedUntil = now and (now + TOUCH_SECONDS) or nil

    if touchTicker then
        touchTicker:Show()
    end
    return true
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function ShowRowTooltip(row)
    local api = GetAPI()
    if not api or not row._displayId or not GameTooltip then
        return
    end

    local item = row._item
    local internalId = item and item.entryId
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

    if row._desired then
        GameTooltip:AddLine("Marked Desired in Ascension", 0.35, 0.71, 1)
    elseif row._undesired then
        GameTooltip:AddLine("Marked Undesired in Ascension Rapid", 0.72, 0.45, 0.18)
    elseif IsWildcard() then
        GameTooltip:AddLine("Right-click to toggle Desired", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Desired sync happens in Wildcard mode", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Left-click selects this row", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function SelectRow(row, note)
    local key = ItemKey(row._item)
    if not key then
        return false
    end
    selectedKey = key
    WishlistPanel.Refresh(note)
    return true
end

local function OnRowToggleDesired(row)
    local Wishlist = GetWishlist()
    local item = row._item
    if not Wishlist or not item then
        return
    end

    if not IsWildcard() then
        SelectRow(row, "Selected " .. (row._name or "entry")
            .. ". Desired is Wildcard-only — Push marks every row when you enter Wildcard.")
        return
    end

    local api = GetAPI()
    local entryId, entryType = Wishlist.GetItemPair(item)
    if not api or not entryId then
        SelectRow(row, "Selected " .. (row._name or "entry")
            .. ". This client cannot resolve that id to an advancement entry yet.")
        return
    end

    if api.IsDesiredID(entryId, entryType) then
        api.RemoveDesiredID(entryId, entryType)
        WishlistPanel.NoteTouched(entryId, entryType, item.spellId)
        SelectRow(row)
        return
    end

    if not api.CanAddDesiredID(entryId, entryType) then
        SelectRow(row, "Selected " .. (row._name or "entry")
            .. ". Ascension will not accept that entry as Desired right now.")
        return
    end

    api.AddDesiredID(entryId, entryType)
    WishlistPanel.NoteTouched(entryId, entryType, item.spellId)
    SelectRow(row)
end

local function OnRowClick(row, button)
    if button == "RightButton" then
        OnRowToggleDesired(row)
        return
    end
    local name = row._name or "entry"
    SelectRow(row, "Selected " .. name .. ".")
end

local function OnRowRemove(row)
    local Wishlist = GetWishlist()
    if not Wishlist or not row._item then
        return
    end

    local name = row._name or "entry"
    Wishlist.RemoveItem(row._item)
    if GameTooltip then
        GameTooltip:Hide()
    end
    WishlistPanel.Refresh("Removed " .. name .. " from the wishlist.")
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", FRAME_NAME .. "Row" .. index, parent)
    row:SetHeight(ROW_HEIGHT)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetTexture(0.55, 0.42, 0.18, 0.12)
    row._stripe = stripe

    local select = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    select:SetAllPoints()
    select:SetTexture(0.85, 0.70, 0.28, 0.28)
    select:Hide()
    row._select = select

    local touch = row:CreateTexture(nil, "BORDER")
    touch:SetAllPoints()
    touch:SetTexture(0.85, 0.70, 0.28, 0.35)
    touch:Hide()
    row._touch = touch

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(0.85, 0.70, 0.28, 0.18)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local remove = CreateFrame("Button", FRAME_NAME .. "Row" .. index .. "Remove", row, "UIPanelButtonTemplate")
    remove:SetWidth(20)
    remove:SetHeight(18)
    remove:SetPoint("RIGHT", -4, 0)
    remove:SetText("x")
    remove:SetScript("OnClick", function()
        OnRowRemove(row)
    end)
    row._remove = remove

    local badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("RIGHT", remove, "LEFT", -6, 0)
    badge:SetWidth(56)
    badge:SetJustifyH("RIGHT")
    badge:SetTextColor(0.12, 0.29, 0.44, 1)
    badge:SetText("Desired")
    row._badge = badge

    local idLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    idLabel:SetPoint("RIGHT", badge, "LEFT", -8, 0)
    idLabel:SetWidth(60)
    idLabel:SetJustifyH("RIGHT")
    idLabel:SetTextColor(0.35, 0.28, 0.18, 1)
    row._idLabel = idLabel

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameLabel:SetPoint("RIGHT", idLabel, "LEFT", -8, 0)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetTextColor(0.12, 0.08, 0.02, 1)
    row._nameLabel = nameLabel

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnClick", OnRowClick)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    return row
end

local function BadgesEnabled()
    local DB = AscensionSuite.Database
    if DB and DB.GetPrefs then
        local prefs = DB.GetPrefs()
        if type(prefs) == "table" and prefs.showWishlistBadges == false then
            return false
        end
    end
    return true
end

local function FillRow(row, entry, position)
    row._item = entry.item
    row._displayId = entry.displayId
    row._desired = entry.desired
    row._undesired = entry.undesired
    row._name = entry.name

    row._icon:SetTexture(entry.icon or PLACEHOLDER_ICON)
    row._nameLabel:SetText(entry.name)
    if entry.resolved then
        row._nameLabel:SetTextColor(0.12, 0.08, 0.02, 1)
    else
        row._nameLabel:SetTextColor(0.42, 0.36, 0.26, 1)
    end

    row._idLabel:SetText(tostring(entry.displayId or "?"))

    if BadgesEnabled() and entry.desired then
        row._badge:SetText("Desired")
        row._badge:SetTextColor(0.12, 0.29, 0.44, 1)
        row._badge:Show()
    elseif BadgesEnabled() and entry.undesired then
        row._badge:SetText("Undes.")
        row._badge:SetTextColor(0.42, 0.24, 0.06, 1)
        row._badge:Show()
    else
        row._badge:Hide()
    end

    if position % 2 == 0 then
        row._stripe:Show()
    else
        row._stripe:Hide()
    end

    if touchedKey and not TouchExpired() and ItemKey(entry.item) == touchedKey then
        row._touch:Show()
    else
        row._touch:Hide()
    end

    if selectedKey and ItemKey(entry.item) == selectedKey then
        row._select:Show()
    else
        row._select:Hide()
    end

    row:Show()
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------

local function AddFromInput()
    local Wishlist = GetWishlist()
    if not addBox or not Wishlist then
        return
    end

    local text = addBox:GetText()
    local id = tonumber(text)
    if not id then
        WishlistPanel.Refresh("Type a spell id or an advancement entry id.")
        return
    end

    local ok, result = Wishlist.Add(id)
    addBox:SetText("")

    if not ok then
        WishlistPanel.Refresh("Could not add " .. tostring(id) .. ".")
        return
    end

    -- A search box still holding an unrelated word would hide the row that was
    -- just added, which reads as "Add did nothing".
    if searchBox and searchBox:GetText() ~= "" then
        searchBox:SetText("")
    end

    local api = GetAPI()
    WishlistPanel.NoteTouched(api and api.GetEntryInternalID and api.GetEntryInternalID(id) or nil,
        api and api.GetEntryType and api.GetEntryType(id) or nil, id)

    if result == "exists" then
        WishlistPanel.Refresh("Already on the wishlist.")
        return
    end
    WishlistPanel.Refresh()
end

local function ClearList()
    local Wishlist = GetWishlist()
    if not Wishlist then
        return
    end
    local removed = Wishlist.Clear()
    WishlistPanel.Refresh(string.format("Cleared %d wishlist entries. Ascension Desired is untouched.", removed))
end

local function PushToDesired()
    local Wishlist = GetWishlist()
    if not Wishlist then
        return
    end

    local pushed, already, failed, reason, refuses, skipped = Wishlist.PushToDesired()
    if reason == "not_wildcard" then
        WishlistPanel.Refresh("Desired sync needs Wildcard mode. Your wishlist is saved and waiting.")
        return
    end
    if reason then
        WishlistPanel.Refresh("Ascension's Wildcard API is not available right now.")
        return
    end

    local Loadouts = AscensionSuite.Loadouts
    local note
    if Loadouts and Loadouts.FormatPushSummary then
        note = Loadouts.FormatPushSummary(pushed, already, failed, skipped, refuses)
    else
        note = string.format("Pushed %d to Desired (%d already there).", pushed, already)
    end
    if skipped and skipped > 0 and pushed == 0 and failed == 0 and Wishlist.RemoveIneligibleEntries then
        note = note .. " Use Clear tags to remove Tag rows from the wishlist."
    end
    WishlistPanel.Refresh(note)
end

local function ClearTags()
    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.RemoveIneligibleEntries then
        return
    end
    local removed = Wishlist.RemoveIneligibleEntries()
    if removed > 0 then
        WishlistPanel.Refresh(string.format("Removed %d Tag/meta rows from the wishlist.", removed))
    else
        WishlistPanel.Refresh("No Tag or meta rows to remove.")
    end
end

local function SyncFromRapid()
    local DesiredSync = AscensionSuite.DesiredSync
    if not DesiredSync or not DesiredSync.Sync then
        WishlistPanel.Refresh("Desired sync is not available right now.")
        return
    end

    local added, scanned, widened = DesiredSync.Sync()
    local note
    if scanned == 0 then
        note = "no Desired candidates to scan - open Rapid Rolling first"
    elseif added == 0 then
        note = string.format("scanned %d, nothing new", scanned)
    else
        note = string.format("+%d from Rapid", added)
    end
    if widened then
        note = note .. " (searched past your Rapid filter, then put it back)"
    end
    WishlistPanel.Refresh(note)

    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshDesiredStatus then
        MainWindow.RefreshDesiredStatus(note)
    end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

local function DefaultStatus(total, desired)
    if not IsWildcard() then
        return "Not in Wildcard - the wishlist is saved. Desired sync happens when you enter Wildcard mode.", false
    end
    if total == 0 then
        return "Wildcard active - add entries above, then push them to Desired.", true
    end
    if desired >= total then
        return string.format("Wildcard active - all %d entries are Desired. Auto-Roll has targets.", total), true
    end
    return string.format(
        "Wildcard active - %d of %d already Desired. Push marks the rest for Auto-Roll.", desired, total), true
end

-- Why Push is greyed out, in the same words the button's tooltip uses. Returning
-- nil means it is live.
function WishlistPanel.GetPushBlockReason()
    local Wishlist = GetWishlist()
    if not Wishlist then
        return "The wishlist is not loaded yet."
    end
    if Wishlist.Count() == 0 then
        return "There is nothing on the wishlist to push."
    end
    if not IsWildcard() then
        return "Desired only exists in Wildcard mode. Your list is saved until you get there."
    end
    return nil
end

-- note is optional. It is typed rather than trusted because FrameXML hands the
-- update callback its own frame -- FauxScrollFrame_OnVerticalScroll calls
-- updateFunction(self) -- and a frame reaching SetText raises a Lua error, which
-- is what used to happen the moment a wishlist grew past eight rows and the
-- player scrolled it.
function WishlistPanel.HideTooltips()
    if GameTooltip then
        GameTooltip:Hide()
    end
    for index = 1, #rows do
        local row = rows[index]
        if type(row) == "table" and type(row.GetScript) == "function" then
            local onLeave = row:GetScript("OnLeave")
            if type(onLeave) == "function" then
                onLeave(row)
            end
        end
    end
end

function WishlistPanel.Refresh(note)
    if type(note) ~= "string" then
        note = nil
    end

    if not panel then
        return
    end

    local Wishlist = GetWishlist()
    if not Wishlist then
        return
    end

    if TouchExpired() then
        touchedKey = nil
        touchedUntil = nil
    end

    if GameTooltip then
        GameTooltip:Hide()
    end

    local total = Wishlist.Count()
    local desired = Wishlist.CountDesired()
    local undesired = 0
    if Wishlist.CountUndesired then
        undesired = Wishlist.CountUndesired() or 0
    end
    filtered = Wishlist.Search(searchBox and searchBox:GetText() or nil)

    if countLabel then
        countLabel:SetText(string.format("%d entries \194\183 Desired %d \194\183 Undesired %d",
            total, desired, undesired))
    end

    if type(_G.FauxScrollFrame_Update) == "function" and scrollFrame then
        _G.FauxScrollFrame_Update(scrollFrame, #filtered, VISIBLE_ROWS, ROW_HEIGHT)
    end

    -- Typing into the search box shortens the list without moving the scroll
    -- offset, so an offset left over from a longer list would render eight empty
    -- rows over matches that are right there.
    local offset = ScrollOffset()
    local maxOffset = #filtered - VISIBLE_ROWS
    if maxOffset < 0 then
        maxOffset = 0
    end
    if offset > maxOffset then
        offset = maxOffset
        if scrollFrame and type(_G.FauxScrollFrame_SetOffset) == "function" then
            _G.FauxScrollFrame_SetOffset(scrollFrame, offset)
        end
    end

    for index = 1, VISIBLE_ROWS do
        local row = rows[index]
        local entry = filtered[index + offset]
        if entry then
            FillRow(row, entry, index)
        else
            row._item = nil
            row:Hide()
        end
    end

    if emptyLabel then
        if #filtered > 0 then
            emptyLabel:Hide()
        else
            if total == 0 then
                emptyLabel:SetText("Your wishlist is empty. Add a spell id below, or Alt + right-click a spell\nin the Character Advancement book.")
            else
                emptyLabel:SetText("No wishlist entry matches that search.")
            end
            emptyLabel:Show()
        end
    end

    if pushButton then
        pushButton:SetEnabled(total > 0)
    end
    if clearButton then
        clearButton:SetEnabled(total > 0)
    end

    if statusLabel then
        local text, good = DefaultStatus(total, desired)
        if note then
            statusLabel:SetText(note)
            statusLabel:SetTextColor(0.82, 0.62, 0.22, 1)
        else
            statusLabel:SetText(text)
            if good then
                statusLabel:SetTextColor(0.15, 0.45, 0.22, 1)
            else
                statusLabel:SetTextColor(0.35, 0.28, 0.18, 1)
            end
        end
    end
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

-- Ascension's FauxScrollFrameTemplate also spawns track/middle chrome and a
-- scroll child that can sit above manually positioned row buttons. The list only
-- needs the scrollbar strip for offset math, so strip the overlay pieces.
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

    local extras = {
        "ScrollChildFrame",
        "Track",
        "Top",
        "Bottom",
        "Middle",
    }
    for index = 1, #extras do
        local piece = _G[name .. extras[index]]
        if type(piece) == "table" then
            if piece.Hide then
                piece:Hide()
            end
            if piece.EnableMouse then
                piece:EnableMouse(false)
            end
        end
    end
end

local function BuildPanel(parent, width)
    local contentWidth = width or 640

    panel = CreateFrame("Frame", FRAME_NAME, parent)
    panel:SetAllPoints()
    panelParent = parent
    panelWidth = contentWidth

    local NC = Chrome()
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Wishlist")
    title:SetTextColor(0.30, 0.20, 0.04, 1)

    countLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetPoint("TOPRIGHT", -8, -10)
    countLabel:SetJustifyH("RIGHT")
    countLabel:SetTextColor(0.28, 0.22, 0.12, 1)

    local searchLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 8, -34)
    searchLabel:SetText("Search")
    searchLabel:SetTextColor(0.30, 0.20, 0.04, 1)

    searchBox = CreateFrame("EditBox", FRAME_NAME .. "Search", panel, "InputBoxTemplate")
    searchBox:SetHeight(22)
    searchBox:SetWidth(contentWidth - 186)
    searchBox:SetPoint("TOPLEFT", 68, -30)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetScript("OnTextChanged", function()
        WishlistPanel.Refresh()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    local clearSearch = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearSearch:SetWidth(80)
    clearSearch:SetHeight(22)
    clearSearch:SetPoint("TOPRIGHT", -8, -30)
    clearSearch:SetText("Clear")
    clearSearch:SetScript("OnClick", function()
        if searchBox then
            searchBox:SetText("")
            searchBox:ClearFocus()
        end
        WishlistPanel.Refresh()
    end)

    listFrame = CreateFrame("Frame", FRAME_NAME .. "List", panel)
    listFrame:SetPoint("TOPLEFT", 8, -60)
    listFrame:SetWidth(contentWidth - 16)
    listFrame:SetHeight(VISIBLE_ROWS * ROW_HEIGHT + LIST_INSET * 2)
    if NC and NC.ApplyInsetList then
        NC.ApplyInsetList(listFrame)
    end

    -- Only the scrollbar strip is mouse-active. A full-width FauxScrollFrame sits
    -- above row buttons in 3.3.5a and eats clicks even when the thumb is narrow.
    scrollFrame = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -LIST_INSET, -LIST_INSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -LIST_INSET, LIST_INSET)
    scrollFrame:SetWidth(SCROLLBAR_WIDTH)
    NeutralizeScrollChrome(scrollFrame)
    -- The updater is wrapped rather than passed straight through: FrameXML calls
    -- it as updateFunction(self), and Refresh's first argument is the status note.
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        if type(_G.FauxScrollFrame_OnVerticalScroll) == "function" then
            _G.FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
                WishlistPanel.Refresh()
            end)
        end
    end)

    local listWidth = contentWidth - 16
    local rowWidth = listWidth - LIST_INSET - SCROLLBAR_WIDTH
    for index = 1, VISIBLE_ROWS do
        local row = CreateRow(listFrame, index)
        row:SetWidth(rowWidth)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", LIST_INSET, -(LIST_INSET + (index - 1) * ROW_HEIGHT))
        row:SetFrameLevel((scrollFrame:GetFrameLevel() or 0) + 2)
        row:Hide()
        rows[index] = row
    end

    emptyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLabel:SetPoint("TOPLEFT", 16, -16)
    emptyLabel:SetWidth(rowWidth - 24)
    emptyLabel:SetJustifyH("LEFT")
    emptyLabel:SetTextColor(0.35, 0.28, 0.18, 1)
    emptyLabel:Hide()

    local addLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -12)
    addLabel:SetText("Spell / entry id")
    addLabel:SetTextColor(0.30, 0.20, 0.04, 1)

    addBox = CreateFrame("EditBox", FRAME_NAME .. "Add", panel, "InputBoxTemplate")
    addBox:SetHeight(22)
    addBox:SetWidth(90)
    addBox:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 104, -8)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)
    addBox:SetMaxLetters(9)
    addBox:SetScript("OnEnterPressed", function(self)
        AddFromInput()
        self:ClearFocus()
    end)

    local addButton = CreateFrame("Button", FRAME_NAME .. "AddButton", panel, "UIPanelButtonTemplate")
    addButton:SetWidth(64)
    addButton:SetHeight(22)
    addButton:SetPoint("LEFT", addBox, "RIGHT", 12, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", AddFromInput)

    clearButton = CreateFrame("Button", FRAME_NAME .. "ClearButton", panel, "UIPanelButtonTemplate")
    clearButton:SetWidth(90)
    clearButton:SetHeight(22)
    clearButton:SetPoint("TOPRIGHT", listFrame, "BOTTOMRIGHT", 0, -8)
    clearButton:SetText("Clear list")
    clearButton:SetScript("OnClick", ClearList)

    -- Contained footer: Push / Sync / Clear tags stay inside the parchment body.
    local footer = CreateFrame("Frame", FRAME_NAME .. "Footer", panel)
    footer:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -40)
    footer:SetPoint("TOPRIGHT", listFrame, "BOTTOMRIGHT", 0, -40)
    footer:SetHeight(52)

    pushButton = CreateFrame("Button", FRAME_NAME .. "PushButton", footer, "UIPanelButtonTemplate")
    pushButton:SetWidth(130)
    pushButton:SetHeight(22)
    pushButton:SetPoint("TOPLEFT", 0, 0)
    pushButton:SetText("Push to Desired")
    pushButton:SetScript("OnClick", PushToDesired)
    -- A disabled button with no explanation is the most common "the addon is
    -- broken" report, and a disabled button still gets OnEnter.
    pushButton:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText("Push to Desired", 1, 0.82, 0.3)
        local blocked = WishlistPanel.GetPushBlockReason()
        if blocked then
            GameTooltip:AddLine(blocked, 0.88, 0.44, 0.44, true)
        else
            GameTooltip:AddLine("Marks every wishlist entry Desired in Ascension. "
                .. "Marks you already made are left alone.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    pushButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local syncButton = CreateFrame("Button", FRAME_NAME .. "SyncButton", footer, "UIPanelButtonTemplate")
    syncButton:SetWidth(120)
    syncButton:SetHeight(22)
    syncButton:SetPoint("LEFT", pushButton, "RIGHT", 8, 0)
    syncButton:SetText("Sync from Rapid")
    syncButton:SetScript("OnClick", SyncFromRapid)

    local clearTagsFooter = CreateFrame("Button", FRAME_NAME .. "ClearTagsFooter", footer, "UIPanelButtonTemplate")
    clearTagsFooter:SetWidth(90)
    clearTagsFooter:SetHeight(22)
    clearTagsFooter:SetPoint("LEFT", syncButton, "RIGHT", 8, 0)
    clearTagsFooter:SetText("Clear tags")
    clearTagsFooter:SetScript("OnClick", ClearTags)

    statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetPoint("LEFT", clearTagsFooter, "RIGHT", 10, 0)
    statusLabel:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    statusLabel:SetJustifyH("LEFT")

    hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", footer, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(contentWidth - 16)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.35, 0.28, 0.18, 1)
    hint:SetText("Left-click selects a row \194\183 right-click toggles Desired in Wildcard \194\183 Alt + right-click a spell "
        .. "in the Character Advancement book to add or remove it here (the row lights up) \194\183 x removes it from "
        .. "the Suite wishlist only.")

    -- Only runs while a row is lit, and its whole job is to put the highlight out
    -- again once nobody is looking at a fresh edit any more.
    touchTicker = CreateFrame("Frame", nil, panel)
    touchTicker:Hide()
    touchTicker:SetScript("OnUpdate", function(self)
        if not TouchExpired() then
            return
        end
        self:Hide()
        if touchedKey then
            touchedKey = nil
            touchedUntil = nil
            WishlistPanel.Refresh()
        end
    end)

    WishlistPanel.Refresh()
    return panel
end

function WishlistPanel.EnsureBuilt(parent, width)
    if panel then
        return panel
    end
    if type(parent) ~= "table" then
        return nil
    end
    return BuildPanel(parent, width)
end

function WishlistPanel.Create(parent, width)
    return WishlistPanel.EnsureBuilt(parent, width)
end

-- Re-anchor after the /asuite window becomes visible. Rows built while the tab
-- content was hidden can layout at 0x0 on 3.3.5a until the parent chain shows.
function WishlistPanel.InvalidateLayout()
    if not panel or not panelParent then
        return
    end

    panel:ClearAllPoints()
    panel:SetAllPoints(panelParent)

    if panelWidth and listFrame then
        local listWidth = panelWidth - 16
        listFrame:SetWidth(listWidth)
        local rowWidth = listWidth - LIST_INSET - SCROLLBAR_WIDTH
        for index = 1, VISIBLE_ROWS do
            local row = rows[index]
            if row then
                row:SetWidth(rowWidth)
            end
        end
        if emptyLabel and emptyLabel.SetWidth then
            emptyLabel:SetWidth(rowWidth - 24)
        end
        if searchBox and searchBox.SetWidth then
            searchBox:SetWidth(panelWidth - 186)
        end
        if statusLabel and statusLabel.SetWidth then
            statusLabel:SetWidth(panelWidth - 180)
        end
        if hint and hint.SetWidth then
            hint:SetWidth(panelWidth - 16)
        end
    end
end

function WishlistPanel.GetFrame()
    return panel
end

-- Rows visible right now, after the search filter. Test seam and the reason the
-- panel can be asserted on without a real client.
function WishlistPanel.GetFilteredRows()
    return filtered
end

function WishlistPanel.GetSelectedKey()
    return selectedKey
end
