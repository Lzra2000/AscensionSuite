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

local panel
local searchBox
local addBox
local listFrame
local scrollFrame
local pushButton
local clearButton
local countLabel
local statusLabel
local emptyLabel
local rows = {}
local filtered = {}

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function GetWishlist()
    return AscensionSuite.Wishlist
end

local function IsWildcard()
    local api = GetAPI()
    return api ~= nil and api.IsWildcardModeActive() == true
end

local function ScrollOffset()
    if scrollFrame and type(_G.FauxScrollFrame_GetOffset) == "function" then
        return tonumber(_G.FauxScrollFrame_GetOffset(scrollFrame)) or 0
    end
    return 0
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function ShowRowTooltip(row)
    local api = GetAPI()
    if not api or not row._displayId or not GameTooltip then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local lines = api.GetEntryTooltipLines(row._displayId)
    for index = 1, #lines do
        if index == 1 then
            GameTooltip:SetText(lines[index], 1, 0.82, 0.3)
        else
            GameTooltip:AddLine(lines[index], 1, 1, 1, true)
        end
    end

    if row._desired then
        GameTooltip:AddLine("Marked Desired in Ascension", 0.35, 0.71, 1)
    elseif IsWildcard() then
        GameTooltip:AddLine("Click to mark Desired", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Desired sync happens in Wildcard mode", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Clicking a row is the Desired toggle. Outside Wildcard there is nothing to
-- toggle, so it says so in the status line instead of doing nothing silently.
local function OnRowClick(row)
    local Wishlist = GetWishlist()
    local item = row._item
    if not Wishlist or not item then
        return
    end

    if not IsWildcard() then
        WishlistPanel.Refresh("Desired is Wildcard-only. The entry stays on your wishlist either way.")
        return
    end

    local api = GetAPI()
    local entryId, entryType = Wishlist.GetItemPair(item)
    if not api or not entryId then
        WishlistPanel.Refresh("This client cannot resolve that id to an advancement entry yet.")
        return
    end

    if api.IsDesiredID(entryId, entryType) then
        api.RemoveDesiredID(entryId, entryType)
        WishlistPanel.Refresh()
        return
    end

    if not api.CanAddDesiredID(entryId, entryType) then
        WishlistPanel.Refresh("Ascension will not accept that entry as Desired right now.")
        return
    end

    api.AddDesiredID(entryId, entryType)
    WishlistPanel.Refresh()
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
    stripe:SetTexture(1, 1, 1, 0.03)
    row._stripe = stripe

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(1, 0.82, 0.2, 0.12)

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
    badge:SetTextColor(0.35, 0.71, 1, 1)
    badge:SetText("Desired")
    row._badge = badge

    local idLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    idLabel:SetPoint("RIGHT", badge, "LEFT", -8, 0)
    idLabel:SetWidth(60)
    idLabel:SetJustifyH("RIGHT")
    row._idLabel = idLabel

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameLabel:SetPoint("RIGHT", idLabel, "LEFT", -8, 0)
    nameLabel:SetJustifyH("LEFT")
    row._nameLabel = nameLabel

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnClick", OnRowClick)

    return row
end

local function FillRow(row, entry, position)
    row._item = entry.item
    row._displayId = entry.displayId
    row._desired = entry.desired
    row._name = entry.name

    row._icon:SetTexture(entry.icon or PLACEHOLDER_ICON)
    row._nameLabel:SetText(entry.name)
    if entry.resolved then
        row._nameLabel:SetTextColor(1, 0.92, 0.78, 1)
    else
        row._nameLabel:SetTextColor(0.61, 0.57, 0.50, 1)
    end

    row._idLabel:SetText(tostring(entry.displayId or "?"))

    if entry.desired then
        row._badge:Show()
    else
        row._badge:Hide()
    end

    if position % 2 == 0 then
        row._stripe:Show()
    else
        row._stripe:Hide()
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

    local pushed, already, failed, reason = Wishlist.PushToDesired()
    if reason == "not_wildcard" then
        WishlistPanel.Refresh("Desired sync needs Wildcard mode. Your wishlist is saved and waiting.")
        return
    end
    if reason then
        WishlistPanel.Refresh("Ascension's Wildcard API is not available right now.")
        return
    end

    local note = string.format("Pushed %d to Desired (%d already there", pushed, already)
    if failed > 0 then
        note = note .. string.format(", %d refused by Ascension", failed)
    end
    WishlistPanel.Refresh(note .. ").")
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
    return string.format(
        "Wildcard active - %d of %d already Desired. Push marks the rest for Auto-Roll.", desired, total), true
end

function WishlistPanel.Refresh(note)
    if not panel then
        return
    end

    local Wishlist = GetWishlist()
    if not Wishlist then
        return
    end

    local total = Wishlist.Count()
    local desired = Wishlist.CountDesired()
    filtered = Wishlist.Search(searchBox and searchBox:GetText() or nil)

    if countLabel then
        countLabel:SetText(string.format("%d entries \194\183 %d Desired", total, desired))
    end

    if type(_G.FauxScrollFrame_Update) == "function" and scrollFrame then
        _G.FauxScrollFrame_Update(scrollFrame, #filtered, VISIBLE_ROWS, ROW_HEIGHT)
    end

    local offset = ScrollOffset()
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

    local wildcard = IsWildcard()
    if pushButton then
        pushButton:SetEnabled(wildcard and total > 0)
    end
    if clearButton then
        clearButton:SetEnabled(total > 0)
    end

    if statusLabel then
        local text, good = DefaultStatus(total, desired)
        if note then
            statusLabel:SetText(note)
            statusLabel:SetTextColor(1, 0.82, 0.3, 1)
        else
            statusLabel:SetText(text)
            if good then
                statusLabel:SetTextColor(0.43, 0.81, 0.54, 1)
            else
                statusLabel:SetTextColor(0.65, 0.61, 0.53, 1)
            end
        end
    end
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

function WishlistPanel.Create(parent, width)
    if panel then
        return panel
    end

    local contentWidth = width or 640

    panel = CreateFrame("Frame", FRAME_NAME, parent)
    panel:SetAllPoints()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Wishlist")

    countLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetPoint("TOPRIGHT", 0, -4)
    countLabel:SetJustifyH("RIGHT")

    local searchLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 0, -28)
    searchLabel:SetText("Search")

    searchBox = CreateFrame("EditBox", FRAME_NAME .. "Search", panel, "InputBoxTemplate")
    searchBox:SetHeight(22)
    searchBox:SetWidth(contentWidth - 170)
    searchBox:SetPoint("TOPLEFT", 60, -24)
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
    clearSearch:SetPoint("TOPRIGHT", 0, -24)
    clearSearch:SetText("Clear")
    clearSearch:SetScript("OnClick", function()
        if searchBox then
            searchBox:SetText("")
            searchBox:ClearFocus()
        end
        WishlistPanel.Refresh()
    end)

    listFrame = CreateFrame("Frame", FRAME_NAME .. "List", panel)
    listFrame:SetPoint("TOPLEFT", 0, -54)
    listFrame:SetWidth(contentWidth)
    listFrame:SetHeight(VISIBLE_ROWS * ROW_HEIGHT + LIST_INSET * 2)
    listFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listFrame:SetBackdropColor(0.04, 0.035, 0.025, 0.92)
    listFrame:SetBackdropBorderColor(0.45, 0.38, 0.20, 1)

    scrollFrame = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", LIST_INSET, -LIST_INSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, LIST_INSET)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        if type(_G.FauxScrollFrame_OnVerticalScroll) == "function" then
            _G.FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, WishlistPanel.Refresh)
        end
    end)

    local rowWidth = contentWidth - LIST_INSET - SCROLLBAR_WIDTH
    for index = 1, VISIBLE_ROWS do
        local row = CreateRow(listFrame, index)
        row:SetWidth(rowWidth)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", LIST_INSET, -(LIST_INSET + (index - 1) * ROW_HEIGHT))
        row:Hide()
        rows[index] = row
    end

    emptyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLabel:SetPoint("TOPLEFT", 16, -16)
    emptyLabel:SetWidth(rowWidth - 24)
    emptyLabel:SetJustifyH("LEFT")
    emptyLabel:Hide()

    local addLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -12)
    addLabel:SetText("Spell / entry id")

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

    pushButton = CreateFrame("Button", FRAME_NAME .. "PushButton", panel, "UIPanelButtonTemplate")
    pushButton:SetWidth(140)
    pushButton:SetHeight(24)
    pushButton:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -44)
    pushButton:SetText("Push to Desired")
    pushButton:SetScript("OnClick", PushToDesired)

    statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetPoint("LEFT", pushButton, "RIGHT", 12, 0)
    statusLabel:SetWidth(contentWidth - 164)
    statusLabel:SetJustifyH("LEFT")

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", pushButton, "BOTTOMLEFT", 0, -14)
    hint:SetWidth(contentWidth)
    hint:SetJustifyH("LEFT")
    hint:SetText("Click a row to toggle Desired \194\183 Alt + right-click a spell in the Character Advancement "
        .. "book to add or remove it here \194\183 x removes it from the Suite wishlist only.")

    WishlistPanel.Refresh()
    return panel
end

function WishlistPanel.GetFrame()
    return panel
end

-- Rows visible right now, after the search filter. Test seam and the reason the
-- panel can be asserted on without a real client.
function WishlistPanel.GetFilteredRows()
    return filtered
end
