-- AscensionSuite: ui/MainWindow.lua
-- The /asuite window: a Wishlist tab (the panel the player edits) and an Assists
-- tab (toggles, Auto-Roll, profiles, logbook). Native Rapid UI stays authoritative.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local MainWindow = {}
AscensionSuite.MainWindow = MainWindow

local FRAME_NAME = "AscensionSuiteMainWindow"
local FRAME_WIDTH = 680
local FRAME_HEIGHT = 524
local CONTENT_WIDTH = 640
local CONTENT_TOP = -88
local LOG_LINES = 6

local TAB_WISHLIST = 1
local TAB_ASSISTS = 2

local frame
local tabs = {}
local contents = {}
local activeTab = TAB_WISHLIST
local profileBox
local logHost
local assistChecks = {}
local autoRollStatus
local desiredStatus
local stopButton
local startButton

local function GetAssists()
    local DB = AscensionSuite.Database
    if DB and DB.GetAssists then
        return DB.GetAssists()
    end
    return {}
end

local function GetWishlistPanel()
    return AscensionSuite.WishlistPanel
end

local function Print(message)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and type(chat.AddMessage) == "function" then
        chat:AddMessage("|cff6ba8e8AscensionSuite|r " .. tostring(message))
    end
end

local function CreateCheckbox(parent, label, assistKey, yOffset)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 0, yOffset)
    check:SetWidth(24)
    check:SetHeight(24)

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)

    check:SetScript("OnClick", function(self)
        local assists = GetAssists()
        assists[assistKey] = self:GetChecked() == true

        if assistKey == "autoRoll" and not assists.autoRoll then
            local AutoRoller = AscensionSuite.AutoRoller
            if AutoRoller and AutoRoller.Stop then
                AutoRoller.Stop("assist_off")
            end
        end

        if assistKey == "instantDiceSkip" or assistKey == "instantSkillCardSkip" then
            local AnimationSkip = AscensionSuite.AnimationSkip
            if AnimationSkip and AnimationSkip.Refresh then
                AnimationSkip.Refresh()
            end
        end

        MainWindow.RefreshAutoRoll()
    end)

    assistChecks[assistKey] = check
    return check
end

local STOP_REASONS = {
    assist_off = "assist switched off",
    no_desired_targets = "nothing on the wishlist is Desired yet",
    level_out_of_range = "only runs while leveling 1-60",
    not_wildcard = "not in Wildcard mode",
    rapid_not_ready = "no roll available right now",
    roll_in_flight = "waiting on the current roll",
    session_complete = "rapid session finished",
    user_stop = "stopped by you",
    native_roll_error = "Ascension's Roll button raised an error",
    native_error = "Ascension refused the roll - see its error message",
    stalled = "rapid session stuck — Suite cleared it; press Start again",
    desired_learned = "rolled a Desired entry - start again for the next one",
    desired_list_done = "every Desired entry on the wishlist has been rolled",
    desired_repeat = "the same entry landed twice - stopped rather than reroll it",
    chain_limit = "reached the chained-session limit - press Start to keep going",
    not_wildcard_mode = "not in Wildcard mode",
    no_wildcard_api = "Ascension's Wildcard API is not loaded",
}

function MainWindow.DescribeStopReason(reason)
    if reason == nil then
        return "unknown reason"
    end
    return STOP_REASONS[reason] or tostring(reason)
end

function MainWindow.RefreshAutoRoll()
    if not frame then
        return
    end

    local assists = GetAssists()
    local AutoRoller = AscensionSuite.AutoRoller
    local running = AutoRoller and AutoRoller.IsRunning and AutoRoller.IsRunning()
    local hits = 0
    if AutoRoller and AutoRoller.GetDesiredHits then
        hits = AutoRoller.GetDesiredHits() or 0
    end

    if autoRollStatus then
        if running then
            if hits > 0 then
                autoRollStatus:SetText(string.format("Auto-Roll: running (%d Desired landed)", hits))
            else
                autoRollStatus:SetText("Auto-Roll: running")
            end
            autoRollStatus:SetTextColor(0.43, 0.81, 0.54, 1)
        elseif AutoRoller and AutoRoller.GetLastError and AutoRoller.GetLastError() then
            autoRollStatus:SetText("Auto-Roll stopped - " .. MainWindow.DescribeStopReason(AutoRoller.GetLastError()))
            autoRollStatus:SetTextColor(0.88, 0.44, 0.44, 1)
        else
            autoRollStatus:SetText("Auto-Roll: idle")
            autoRollStatus:SetTextColor(0.54, 0.60, 0.67, 1)
        end
    end

    if startButton then
        startButton:SetEnabled(assists.autoRoll == true and not running)
    end
    if stopButton then
        stopButton:SetEnabled(running == true)
    end
end

function MainWindow.RefreshLogbook()
    if not logHost then
        return
    end

    local Logbook = AscensionSuite.Logbook
    if not Logbook or not Logbook.GetEntries then
        return
    end

    local entries = Logbook.GetEntries()
    local lines = {}
    local start = math.max(1, #entries - LOG_LINES + 1)
    for index = start, #entries do
        local row = entries[index]
        if row then
            local rank = ""
            if row.rank and row.maxRank and row.maxRank > 1 then
                rank = string.format(" rank %d/%d", row.rank, row.maxRank)
            elseif row.rank and row.rank > 1 then
                rank = string.format(" rank %d", row.rank)
            end

            lines[#lines + 1] = string.format("[%s] %s%s (%s)",
                row.entryType or "?",
                row.name or "?",
                rank,
                tostring(row.spellId or row.entryId or "?"))
        end
    end

    if #lines == 0 then
        logHost:SetText("Logbook empty (enable capture assist)")
    else
        logHost:SetText(table.concat(lines, "\n"))
    end
end

-- "Desired" is what the client confirms right now; the wishlist is the whole
-- list. They differ on purpose: outside Wildcard nothing is Desired at all, and
-- Auto-Roll gates on the confirmed subset.
function MainWindow.RefreshDesiredStatus(note)
    if not desiredStatus then
        return
    end

    local Wishlist = AscensionSuite.Wishlist
    if not Wishlist or not Wishlist.Count then
        return
    end

    local text = string.format("Desired: %d of %d on the wishlist",
        Wishlist.CountDesired(), Wishlist.Count())
    if note then
        text = text .. "  |  " .. note
    end
    desiredStatus:SetText(text)
end

-- Everything that changes when a Desired mark lands, from any source. Skipped
-- while the window is closed so a bulk desire in the Rapid window does not
-- rebuild a list nobody is looking at.
function MainWindow.RefreshWishlist()
    if not frame or not frame:IsShown() then
        return
    end

    local panel = GetWishlistPanel()
    if panel and panel.Refresh then
        panel.Refresh()
    end
    MainWindow.RefreshDesiredStatus()
end

local function RefreshAssistToggles()
    local assists = GetAssists()
    for key, check in pairs(assistChecks) do
        check:SetChecked(assists[key] == true)
    end
    MainWindow.RefreshAutoRoll()
end

local function SyncDesiredFromNative()
    local DesiredSync = AscensionSuite.DesiredSync
    if not DesiredSync or not DesiredSync.Sync then
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

    local panel = GetWishlistPanel()
    if panel and panel.Refresh then
        panel.Refresh()
    end
    MainWindow.RefreshDesiredStatus(note)
end

local function SaveProfile()
    if not profileBox then
        return
    end
    local Wishlist = AscensionSuite.Wishlist
    if Wishlist and Wishlist.SaveProfile then
        Wishlist.SaveProfile(profileBox:GetText(), true)
    end
end

local function LoadProfile()
    if not profileBox then
        return
    end
    local Wishlist = AscensionSuite.Wishlist
    if Wishlist and Wishlist.LoadProfile then
        Wishlist.LoadProfile(profileBox:GetText(), true)
    end

    local panel = GetWishlistPanel()
    if panel and panel.Refresh then
        panel.Refresh()
    end
    MainWindow.RefreshDesiredStatus()
end

local function StartAutoRoll()
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.Start then
        -- A refused Start used to leave the status line reading "idle", which is
        -- indistinguishable from the button not having been pressed.
        local ok, reason = AutoRoller.Start()
        if not ok and autoRollStatus then
            autoRollStatus:SetText("Auto-Roll did not start - " .. MainWindow.DescribeStopReason(reason))
            autoRollStatus:SetTextColor(0.88, 0.44, 0.44, 1)
            MainWindow.RefreshDesiredStatus()
            return
        end
    end
    MainWindow.RefreshAutoRoll()
    MainWindow.RefreshDesiredStatus()
end

local function StopAutoRoll()
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.Stop then
        AutoRoller.Stop("user_stop")
    end
    MainWindow.RefreshAutoRoll()
end

-- Manual recovery when Ascension's Continue button is stuck gray (die on "?",
-- Scrolls Used visible, button disabled). Same path Auto-Roll uses after a stall.
--
-- The result goes to chat as well as the status line: the player pressing Unstick
-- is looking at the Rapid window, not at the Suite window behind it, so a line
-- they will actually see is the difference between "it worked" and "nothing
-- happened, press it again".
local function UnstickRapid()
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.IsRunning and AutoRoller.IsRunning() and AutoRoller.Stop then
        AutoRoller.Stop("user_stop")
    end

    local api = AscensionSuite.AscensionAPI
    if not api or not api.RecoverStuckRapidSession then
        return
    end

    local ok, reason = api.RecoverStuckRapidSession()
    if ok then
        Print("Rapid session cleared. Ascension's Roll button should work again.")
    else
        Print("Unstick did nothing - " .. MainWindow.DescribeStopReason(reason) .. ".")
    end

    if autoRollStatus then
        if ok then
            autoRollStatus:SetText("Rapid session cleared — try Roll again")
            autoRollStatus:SetTextColor(0.43, 0.81, 0.54, 1)
        else
            autoRollStatus:SetText("Unstick failed — " .. MainWindow.DescribeStopReason(reason))
            autoRollStatus:SetTextColor(0.88, 0.44, 0.44, 1)
        end
    end
    MainWindow.RefreshAutoRoll()
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------

function MainWindow.SelectTab(index)
    if index ~= TAB_WISHLIST and index ~= TAB_ASSISTS then
        return
    end
    activeTab = index

    -- PanelTemplates draws the selected/deselected tab art. It is guarded rather
    -- than assumed: if the client's FrameXML disagrees about the signature the
    -- window must still open, so the content swap below is done by hand either way.
    if frame and type(_G.PanelTemplates_SetTab) == "function" then
        pcall(_G.PanelTemplates_SetTab, frame, index)
    end

    for tabIndex = 1, #contents do
        local content = contents[tabIndex]
        if content then
            if tabIndex == index then
                content:Show()
            else
                content:Hide()
            end
        end
    end

    if index == TAB_WISHLIST then
        local panel = GetWishlistPanel()
        if panel and panel.Refresh then
            panel.Refresh()
        end
    else
        MainWindow.RefreshDesiredStatus()
        MainWindow.RefreshLogbook()
        MainWindow.RefreshAutoRoll()
    end
end

function MainWindow.GetActiveTab()
    return activeTab
end

local function CreateTab(parent, index, label)
    local tab = CreateFrame("Button", FRAME_NAME .. "Tab" .. index, parent, "CharacterFrameTabButtonTemplate")
    tab:SetID(index)
    tab:SetText(label)
    tab:SetScript("OnClick", function(self)
        MainWindow.SelectTab(self:GetID())
    end)

    if type(_G.PanelTemplates_TabResize) == "function" then
        pcall(_G.PanelTemplates_TabResize, tab, 0)
    end

    tabs[index] = tab
    return tab
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

local function BuildAssistContent(content)
    CreateCheckbox(content, "Auto-Roll while leveling (Desired targets only)", "autoRoll", -4)
    CreateCheckbox(content, "  ...and keep going after a Desired entry lands", "autoRollContinue", -28)
    CreateCheckbox(content, "Instant skip WildCardDice animation", "instantDiceSkip", -52)
    CreateCheckbox(content, "Instant skip SkillCard flipbook", "instantSkillCardSkip", -76)
    CreateCheckbox(content, "Accept Wildcard confirm popups", "acceptWildcardPopups", -100)
    CreateCheckbox(content, "Capture rolls into Logbook", "captureRolls", -124)

    startButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    startButton:SetWidth(90)
    startButton:SetHeight(22)
    startButton:SetPoint("TOPRIGHT", -90, -4)
    startButton:SetText("Start")
    startButton:SetScript("OnClick", StartAutoRoll)

    stopButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    stopButton:SetWidth(90)
    stopButton:SetHeight(22)
    stopButton:SetPoint("LEFT", startButton, "RIGHT", 8, 0)
    stopButton:SetText("Stop")
    stopButton:SetScript("OnClick", StopAutoRoll)

    local unstickButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    unstickButton:SetWidth(90)
    unstickButton:SetHeight(22)
    unstickButton:SetPoint("TOPRIGHT", stopButton, "BOTTOMRIGHT", 0, -28)
    unstickButton:SetText("Unstick")
    unstickButton:SetScript("OnClick", UnstickRapid)

    autoRollStatus = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoRollStatus:SetPoint("TOPRIGHT", unstickButton, "BOTTOMRIGHT", 0, -8)
    autoRollStatus:SetWidth(240)
    autoRollStatus:SetJustifyH("RIGHT")

    local profileLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileLabel:SetPoint("TOPLEFT", 0, -164)
    profileLabel:SetText("Desired profile")

    profileBox = CreateFrame("EditBox", FRAME_NAME .. "Profile", content, "InputBoxTemplate")
    profileBox:SetWidth(140)
    profileBox:SetHeight(22)
    profileBox:SetPoint("TOPLEFT", 8, -182)
    profileBox:SetAutoFocus(false)
    profileBox:SetMaxLetters(32)
    profileBox:SetText("my-hero")

    local saveButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    saveButton:SetWidth(64)
    saveButton:SetHeight(22)
    saveButton:SetPoint("LEFT", profileBox, "RIGHT", 12, 0)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", SaveProfile)

    local loadButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    loadButton:SetWidth(64)
    loadButton:SetHeight(22)
    loadButton:SetPoint("LEFT", saveButton, "RIGHT", 8, 0)
    loadButton:SetText("Load")
    loadButton:SetScript("OnClick", LoadProfile)

    local syncButton = CreateFrame("Button", FRAME_NAME .. "SyncButton", content, "UIPanelButtonTemplate")
    syncButton:SetWidth(140)
    syncButton:SetHeight(22)
    syncButton:SetPoint("TOPRIGHT", 0, -182)
    syncButton:SetText("Sync from Rapid")
    syncButton:SetScript("OnClick", SyncDesiredFromNative)

    desiredStatus = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desiredStatus:SetPoint("TOPLEFT", 0, -216)
    desiredStatus:SetWidth(CONTENT_WIDTH)
    desiredStatus:SetJustifyH("LEFT")

    local logLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logLabel:SetPoint("TOPLEFT", 0, -246)
    logLabel:SetText("Logbook (recent)")

    logHost = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logHost:SetPoint("TOPLEFT", 0, -264)
    logHost:SetWidth(CONTENT_WIDTH)
    logHost:SetJustifyH("LEFT")
end

local function EnsureFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(FRAME_HEIGHT)
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

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("AscensionSuite")

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    version:SetText("v" .. tostring(AscensionSuite.VERSION or "?"))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local wishlistTab = CreateTab(frame, TAB_WISHLIST, "Wishlist")
    wishlistTab:SetPoint("TOPLEFT", 14, -46)

    local assistTab = CreateTab(frame, TAB_ASSISTS, "Assists")
    assistTab:SetPoint("LEFT", wishlistTab, "RIGHT", -14, 0)

    if type(_G.PanelTemplates_SetNumTabs) == "function" then
        pcall(_G.PanelTemplates_SetNumTabs, frame, 2)
    end

    for index = 1, 2 do
        local content = CreateFrame("Frame", FRAME_NAME .. "Content" .. index, frame)
        content:SetPoint("TOPLEFT", 20, CONTENT_TOP)
        content:SetWidth(CONTENT_WIDTH)
        content:SetHeight(FRAME_HEIGHT + CONTENT_TOP - 20)
        content:Hide()
        contents[index] = content
    end

    local panel = GetWishlistPanel()
    if panel and panel.Create then
        panel.Create(contents[TAB_WISHLIST], CONTENT_WIDTH)
    end

    BuildAssistContent(contents[TAB_ASSISTS])

    RefreshAssistToggles()
    MainWindow.SelectTab(activeTab)
    return frame
end

function MainWindow.Toggle()
    local win = EnsureFrame()
    if win:IsShown() then
        win:Hide()
    else
        MainWindow.Show()
    end
end

function MainWindow.Show()
    local win = EnsureFrame()
    win:Show()

    local panel = GetWishlistPanel()
    if panel and panel.Refresh then
        panel.Refresh()
    end
    MainWindow.RefreshDesiredStatus()
    MainWindow.RefreshLogbook()
    MainWindow.RefreshAutoRoll()
    return win
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
