-- AscensionSuite: ui/MainWindow.lua
-- The /asuite window: Wishlist, Loadouts, and Assists (native WotLK settings
-- chrome with Categories sidebar). Native Rapid UI stays authoritative.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local MainWindow = {}
AscensionSuite.MainWindow = MainWindow

local FRAME_NAME = "AscensionSuiteMainWindow"
local FRAME_WIDTH = 740
local FRAME_HEIGHT = 580
local CONTENT_INSET = 16
local CONTENT_TOP = -78
local SIDEBAR_WIDTH = 156
local LOG_LINES = 8
local LOG_LINES_FULL = 18

local TAB_WISHLIST = 1
local TAB_LOADOUTS = 2
local TAB_ASSISTS = 3

local CAT_GENERAL = "general"
local CAT_AUTOMATION = "automation"
local CAT_LOGBOOK = "logbook"
local CAT_WINDOWS = "windows"
local CAT_SYNC = "sync"

local frame
local tabs = {}
local contents = {}
local activeTab = TAB_WISHLIST
local activeCategory = CAT_WINDOWS
local titleLabel
local subheadLabel
local versionLabel

-- Assists chrome
local assistShell
local categoryButtons = {}
local categoryPages = {}
local assistChecks = {}
local prefChecks = {}
local draftAssists = {}
local draftPrefs = {}
local assistsDirty = false
local footerStatus
local cancelButton
local saveButton
local startButton
local stopButton
local unstickButton
local autoRollStatus
local desiredStatus
local syncStatus
local countWishlist
local countDesired
local countUndesired
local logHost
local logHostFull
local categoryHeadTitle
local categoryHeadSub

local CATEGORIES = {
    { id = CAT_GENERAL, label = "General" },
    { id = CAT_AUTOMATION, label = "Automation" },
    { id = CAT_LOGBOOK, label = "Logbook" },
    { id = CAT_WINDOWS, label = "Windows & Tools" },
    { id = CAT_SYNC, label = "Wishlist sync" },
}

local ASSIST_KEYS = {
    "autoRoll",
    "autoRollContinue",
    "instantDiceSkip",
    "instantSkillCardSkip",
    "acceptWildcardPopups",
    "captureRolls",
    "autoUnstick",
}

local PREF_KEYS = {
    "showWishlistBadges",
    "clickTrace",
}

local function ContentWidth()
    return FRAME_WIDTH - (CONTENT_INSET * 2)
end

local function GetAssists()
    local DB = AscensionSuite.Database
    if DB and DB.GetAssists then
        return DB.GetAssists()
    end
    return {}
end

local function GetPrefs()
    local DB = AscensionSuite.Database
    if DB and DB.GetPrefs then
        return DB.GetPrefs()
    end
    return {}
end

local function GetWishlistPanel()
    return AscensionSuite.WishlistPanel
end

local function GetLoadoutsPanel()
    return AscensionSuite.LoadoutsPanel
end

local function Chrome()
    return AscensionSuite.NativeChrome
end

local function Print(message)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and type(chat.AddMessage) == "function" then
        chat:AddMessage("|cff6ba8e8AscensionSuite|r " .. tostring(message))
    end
end

-- WotLK 3.3.5a CheckButton:GetChecked() returns 1 / nil, not true / false.
local function CheckButtonIsOn(check)
    if type(check) ~= "table" or type(check.GetChecked) ~= "function" then
        return false
    end
    local value = check:GetChecked()
    return value == 1 or value == true
end

local function CopyAssistDraft()
    local assists = GetAssists()
    draftAssists = {}
    for index = 1, #ASSIST_KEYS do
        local key = ASSIST_KEYS[index]
        draftAssists[key] = assists[key] == true
    end
    local prefs = GetPrefs()
    draftPrefs = {}
    for index = 1, #PREF_KEYS do
        local key = PREF_KEYS[index]
        draftPrefs[key] = prefs[key] == true
    end
    -- Badges default on when missing.
    if prefs.showWishlistBadges == nil then
        draftPrefs.showWishlistBadges = true
    end
    assistsDirty = false
end

local function MarkDirty()
    assistsDirty = true
    if footerStatus then
        footerStatus:SetText("Unsaved changes.")
        footerStatus:SetTextColor(0.82, 0.62, 0.22, 1)
    end
end

local function SyncCheckGroup(group, on)
    if type(group) ~= "table" then
        return
    end
    for index = 1, #group do
        local check = group[index]
        if check and check.SetChecked then
            check:SetChecked(on)
        end
    end
end

local function RefreshFooterClean()
    if not footerStatus then
        return
    end
    if assistsDirty then
        footerStatus:SetText("Unsaved changes.")
        footerStatus:SetTextColor(0.82, 0.62, 0.22, 1)
        return
    end
    local Wishlist = AscensionSuite.Wishlist
    local desired, total = 0, 0
    if Wishlist and Wishlist.CountDesired and Wishlist.Count then
        desired = Wishlist.CountDesired() or 0
        total = Wishlist.Count() or 0
    end
    if activeCategory == CAT_AUTOMATION then
        footerStatus:SetText(string.format("No unsaved changes \194\183 Desired %d of %d", desired, total))
    else
        footerStatus:SetText("No unsaved changes.")
    end
    footerStatus:SetTextColor(0.35, 0.28, 0.18, 1)
end

local STOP_REASONS = {
    assist_off = "assist switched off",
    no_desired_targets = "nothing on the wishlist is Desired yet",
    wishlist_tags_only = "wishlist has only Tag/meta rows — Clear tags or re-import Archetype",
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
    unlearn_decision = "keep-or-unlearn decision is up - Cancel/Unlearn is yours; Suite never spends Scroll of Fortune",
}

function MainWindow.DescribeStopReason(reason)
    if reason == nil then
        return "unknown reason"
    end
    return STOP_REASONS[reason] or tostring(reason)
end

function MainWindow.CheckButtonIsOn(check)
    return CheckButtonIsOn(check)
end

function MainWindow.GetActiveCategory()
    return activeCategory
end

local function ApplyAssistSideEffects(key, on)
    if key == "autoRoll" then
        local AutoRoller = AscensionSuite.AutoRoller
        if not on then
            if AutoRoller and AutoRoller.Stop then
                AutoRoller.Stop("assist_off")
            end
        elseif AutoRoller and AutoRoller.ClearLastError then
            AutoRoller.ClearLastError()
        end
    end

    if key == "instantDiceSkip" or key == "instantSkillCardSkip" then
        local AnimationSkip = AscensionSuite.AnimationSkip
        if AnimationSkip and AnimationSkip.Refresh then
            AnimationSkip.Refresh()
        end
    end

    if key == "autoUnstick" then
        local AutoUnstick = AscensionSuite.AutoUnstick
        if AutoUnstick and AutoUnstick.Refresh then
            AutoUnstick.Refresh()
        end
    end
end

local function SaveDraft()
    local assists = GetAssists()
    for index = 1, #ASSIST_KEYS do
        local key = ASSIST_KEYS[index]
        local on = draftAssists[key] == true
        assists[key] = on
        ApplyAssistSideEffects(key, on)
    end

    local prefs = GetPrefs()
    for index = 1, #PREF_KEYS do
        local key = PREF_KEYS[index]
        prefs[key] = draftPrefs[key] == true
    end

    assistsDirty = false
    MainWindow.RefreshAutoRoll()
    MainWindow.RefreshLogbook()
    MainWindow.RefreshWishlist()
    RefreshFooterClean()
    Print("Settings saved.")
end

local function CancelDraft()
    CopyAssistDraft()
    for key, group in pairs(assistChecks) do
        SyncCheckGroup(group, draftAssists[key] == true)
    end
    for key, group in pairs(prefChecks) do
        SyncCheckGroup(group, draftPrefs[key] == true)
    end
    RefreshFooterClean()
end

function MainWindow.RefreshAutoRoll()
    if not frame then
        return
    end

    local assists = GetAssists()
    local autoRollOn = assists.autoRoll == true
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
            autoRollStatus:SetTextColor(0.15, 0.45, 0.22, 1)
        elseif not autoRollOn then
            autoRollStatus:SetText("Auto-Roll: off (enable, Save, then Start)")
            autoRollStatus:SetTextColor(0.35, 0.28, 0.18, 1)
        elseif AutoRoller and AutoRoller.GetLastError and AutoRoller.GetLastError() then
            local err = AutoRoller.GetLastError()
            if err == "assist_off" then
                if AutoRoller.ClearLastError then
                    AutoRoller.ClearLastError()
                end
                autoRollStatus:SetText("Auto-Roll: ready — press Start")
                autoRollStatus:SetTextColor(0.35, 0.28, 0.18, 1)
            else
                autoRollStatus:SetText("Auto-Roll stopped - " .. MainWindow.DescribeStopReason(err))
                autoRollStatus:SetTextColor(0.72, 0.22, 0.18, 1)
            end
        else
            autoRollStatus:SetText("Auto-Roll: ready — press Start")
            autoRollStatus:SetTextColor(0.35, 0.28, 0.18, 1)
        end
    end

    if startButton then
        startButton:SetEnabled(autoRollOn and not running)
    end
    if stopButton then
        stopButton:SetEnabled(running == true)
    end
end

local function FormatLogLines(maxLines)
    local Logbook = AscensionSuite.Logbook
    if not Logbook or not Logbook.GetEntries then
        return nil
    end

    local entries = Logbook.GetEntries()
    local lines = {}
    local start = math.max(1, #entries - maxLines + 1)
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
    return lines
end

function MainWindow.RefreshLogbook()
    local lines = FormatLogLines(LOG_LINES)
    local full = FormatLogLines(LOG_LINES_FULL)
    local emptyText
    local assists = GetAssists()
    if assists.captureRolls == true then
        emptyText = "Logbook empty — waiting for the next roll"
    else
        emptyText = "Logbook empty — enable Capture rolls (Logbook), then Save"
    end

    if logHost then
        if not lines or #lines == 0 then
            logHost:SetText(emptyText)
        else
            logHost:SetText(table.concat(lines, "\n"))
        end
    end
    if logHostFull then
        if not full or #full == 0 then
            logHostFull:SetText(emptyText)
        else
            logHostFull:SetText(table.concat(full, "\n"))
        end
    end
end

function MainWindow.RefreshDesiredStatus(note)
    local Wishlist = AscensionSuite.Wishlist
    if not Wishlist or not Wishlist.Count then
        return
    end

    local desired = Wishlist.CountDesired()
    local total = Wishlist.Count()
    local undesired = 0
    if Wishlist.CountUndesired then
        undesired = Wishlist.CountUndesired() or 0
    end

    if countWishlist then
        countWishlist:SetText(tostring(total))
    end
    if countDesired then
        countDesired:SetText(string.format("%d / %d", desired, total))
    end
    if countUndesired then
        countUndesired:SetText(tostring(undesired))
    end

    local text = string.format("Desired: %d of %d on the wishlist \194\183 Undesired: %d",
        desired, total, undesired)
    if note then
        text = text .. "  |  " .. note
    elseif total > 0 and desired == 0 then
        text = text .. "  |  Wishlist tab → Push to Desired (Wildcard)"
    end

    if desiredStatus then
        desiredStatus:SetText(text)
    end
    if syncStatus then
        syncStatus:SetText(text)
    end

    if not assistsDirty then
        RefreshFooterClean()
    end
end

function MainWindow.RefreshWishlist()
    local panel = GetWishlistPanel()
    if panel and panel.Refresh then
        panel.Refresh()
    end

    if not frame or not frame:IsShown() then
        return
    end
    MainWindow.RefreshDesiredStatus()
end

function MainWindow.RefreshLoadouts()
    local loadoutsPanel = GetLoadoutsPanel()
    if loadoutsPanel and loadoutsPanel.Refresh then
        loadoutsPanel.Refresh()
    end
end

local function EnsureWishlistPanel()
    local content = contents[TAB_WISHLIST]
    local panel = GetWishlistPanel()
    if not content or not panel then
        return
    end

    if not panel.GetFrame() then
        if panel.EnsureBuilt then
            panel.EnsureBuilt(content, ContentWidth())
        elseif panel.Create then
            panel.Create(content, ContentWidth())
        end
    end

    if panel.InvalidateLayout then
        panel.InvalidateLayout()
    end
end

local function EnsureLoadoutsPanel()
    local content = contents[TAB_LOADOUTS]
    local loadoutsPanel = GetLoadoutsPanel()
    if not content or not loadoutsPanel then
        return
    end

    if not loadoutsPanel.GetFrame() then
        if loadoutsPanel.EnsureBuilt then
            loadoutsPanel.EnsureBuilt(content, ContentWidth())
        elseif loadoutsPanel.Create then
            loadoutsPanel.Create(content, ContentWidth())
        end
    end

    if loadoutsPanel.InvalidateLayout then
        loadoutsPanel.InvalidateLayout()
    end
end

function MainWindow.InvalidateLayout()
    if not frame then
        return
    end

    for tabIndex = 1, #tabs do
        local tab = tabs[tabIndex]
        if tab and type(_G.PanelTemplates_TabResize) == "function" then
            pcall(_G.PanelTemplates_TabResize, tab, 0)
        end
    end

    if type(_G.PanelTemplates_SetTab) == "function" and frame.selectedTab then
        pcall(_G.PanelTemplates_SetTab, frame, frame.selectedTab)
    end

    EnsureWishlistPanel()
    EnsureLoadoutsPanel()

    local wishlistPanel = GetWishlistPanel()
    if wishlistPanel and wishlistPanel.InvalidateLayout then
        wishlistPanel.InvalidateLayout()
    end

    local loadoutsPanel = GetLoadoutsPanel()
    if loadoutsPanel and loadoutsPanel.AnchorLayout then
        loadoutsPanel.AnchorLayout()
    elseif loadoutsPanel and loadoutsPanel.InvalidateLayout then
        loadoutsPanel.InvalidateLayout()
    end
end

local function RefreshAssistToggles()
    CopyAssistDraft()
    for key, group in pairs(assistChecks) do
        SyncCheckGroup(group, draftAssists[key] == true)
    end
    for key, group in pairs(prefChecks) do
        SyncCheckGroup(group, draftPrefs[key] == true)
    end
    MainWindow.RefreshAutoRoll()
    RefreshFooterClean()
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

local function StartAutoRoll()
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.Start then
        local ok, reason = AutoRoller.Start()
        if not ok and autoRollStatus then
            local detail = MainWindow.DescribeStopReason(reason)
            if reason == "no_desired_targets" then
                local Wishlist = AscensionSuite.Wishlist
                if Wishlist and Wishlist.Count and Wishlist.Count() > 0 then
                    detail = detail .. " — Wishlist tab → Push to Desired"
                end
            elseif reason == "wishlist_tags_only" then
                detail = detail .. " — Wishlist tab → Clear tags"
            end
            autoRollStatus:SetText("Auto-Roll did not start - " .. detail)
            autoRollStatus:SetTextColor(0.72, 0.22, 0.18, 1)
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

local function UnstickRapid()
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.IsRunning and AutoRoller.IsRunning() and AutoRoller.Stop then
        AutoRoller.Stop("user_stop")
    end

    local api = AscensionSuite.AscensionAPI
    if not api then
        return false
    end

    local ok, reason
    if api.RecoverDiceInteraction then
        ok, reason = api.RecoverDiceInteraction()
    elseif api.RecoverStuckRapidSession then
        ok = api.RecoverStuckRapidSession()
        reason = ok and "rapid_session_cleared" or "recover_failed"
    else
        return false
    end

    if ok then
        if reason == "mouse_restored" or reason == "mouse_forced" then
            Print("Wild Card dice should accept clicks again.")
        else
            Print("Rapid session cleared. Ascension's Roll button should work again.")
        end
    else
        Print("Unstick did nothing - " .. MainWindow.DescribeStopReason(reason) .. ".")
    end

    if autoRollStatus then
        if ok then
            if reason == "mouse_restored" or reason == "mouse_forced" then
                autoRollStatus:SetText("Dice click restored — try clicking the die")
            else
                autoRollStatus:SetText("Rapid session cleared — try Roll again")
            end
            autoRollStatus:SetTextColor(0.15, 0.45, 0.22, 1)
        else
            autoRollStatus:SetText("Unstick failed — " .. MainWindow.DescribeStopReason(reason))
            autoRollStatus:SetTextColor(0.72, 0.22, 0.18, 1)
        end
    end
    MainWindow.RefreshAutoRoll()
    return ok
end

function MainWindow.UnstickRapid()
    return UnstickRapid()
end

------------------------------------------------------------------------
-- Tabs / chrome titles
------------------------------------------------------------------------

local function UpdateChromeForTab(index)
    if not titleLabel then
        return
    end
    if index == TAB_ASSISTS then
        titleLabel:SetText("AscensionSuite Settings")
        if subheadLabel then
            subheadLabel:SetText("Timing, assists, wishlist sync, logbook, and tools for the whole suite.")
            subheadLabel:Show()
        end
    else
        titleLabel:SetText("AscensionSuite")
        if subheadLabel then
            if index == TAB_WISHLIST then
                subheadLabel:SetText("Wishlist \194\183 Desired / Undesired badges \194\183 controls stay inside the frame.")
            else
                subheadLabel:SetText("Named builds \194\183 parchment shell \194\183 Apply \226\134\146 Desired.")
            end
            subheadLabel:Show()
        end
    end
end

function MainWindow.SelectTab(index)
    if index ~= TAB_WISHLIST and index ~= TAB_LOADOUTS and index ~= TAB_ASSISTS then
        return
    end

    if index ~= TAB_WISHLIST then
        local panel = GetWishlistPanel()
        if panel and panel.HideTooltips then
            panel.HideTooltips()
        end
    end

    activeTab = index

    if frame then
        frame.selectedTab = index
        if type(_G.PanelTemplates_SetTab) == "function" then
            pcall(_G.PanelTemplates_SetTab, frame, index)
        end
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

    UpdateChromeForTab(index)

    if index == TAB_WISHLIST then
        EnsureWishlistPanel()
        local panel = GetWishlistPanel()
        if panel and panel.Refresh then
            panel.Refresh()
        end
    elseif index == TAB_LOADOUTS then
        EnsureLoadoutsPanel()
        local loadoutsPanel = GetLoadoutsPanel()
        if loadoutsPanel and loadoutsPanel.Refresh then
            loadoutsPanel.Refresh()
        end
    else
        MainWindow.SelectCategory(activeCategory)
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
-- Assists: category chrome helpers
------------------------------------------------------------------------

local function SetCategoryHighlight(id)
    local NC = Chrome()
    for catId, button in pairs(categoryButtons) do
        if button then
            local selected = (catId == id)
            if NC and NC.ApplyNavButton then
                NC.ApplyNavButton(button, selected)
            end
            if button._label then
                if selected then
                    button._label:SetTextColor(0.12, 0.08, 0.02, 1)
                else
                    button._label:SetTextColor(0.92, 0.85, 0.65, 1)
                end
            end
        end
    end
end

function MainWindow.SelectCategory(id)
    if not categoryPages[id] then
        id = CAT_WINDOWS
    end
    activeCategory = id
    SetCategoryHighlight(id)

    for catId, page in pairs(categoryPages) do
        if page then
            if catId == id then
                page:Show()
            else
                page:Hide()
            end
        end
    end

    local titles = {
        [CAT_GENERAL] = { "General", "Safety defaults and suite overview. Assists stay opt-in." },
        [CAT_AUTOMATION] = { "Automation", "Opt-in assists for Wildcard Rapid / leveling dice. Never Draft, HoF, or store." },
        [CAT_LOGBOOK] = { "Logbook", "Recent roll capture. Enable Capture rolls, then Save." },
        [CAT_WINDOWS] = { "Windows & Tools", "Open suite panels and toggle optional diagnostics. All assists stay opt-in." },
        [CAT_SYNC] = { "Wishlist sync", "Pull Ascension Rapid Desired marks into the Suite wishlist." },
    }
    local info = titles[id]
    if categoryHeadTitle and info then
        categoryHeadTitle:SetText(info[1])
    end
    if categoryHeadSub and info then
        categoryHeadSub:SetText(info[2])
    end

    -- Footer action visibility: Start/Unstick on Automation; Cancel/Save always.
    if startButton then
        if id == CAT_AUTOMATION then
            startButton:Show()
            if stopButton then stopButton:Show() end
            if unstickButton then unstickButton:Show() end
        else
            startButton:Hide()
            if stopButton then stopButton:Hide() end
            if unstickButton then unstickButton:Hide() end
        end
    end

    RefreshFooterClean()
    MainWindow.RefreshLogbook()
    MainWindow.RefreshDesiredStatus()
end

local function CreateSectionLabel(parent, text, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 4, y)
    label:SetText(string.upper(text))
    label:SetTextColor(0.42, 0.30, 0.10, 1)
    return label
end

local function CreateToggleRow(parent, y, title, description, onToggle)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(40)

    local NC = Chrome()
    if NC and NC.ApplyToggleRow then
        NC.ApplyToggleRow(row)
    end

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 4, -6)
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetScript("OnClick", function(self)
        onToggle(CheckButtonIsOn(self))
    end)

    local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", check, "TOPRIGHT", 6, -2)
    titleFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetText(title)
    titleFs:SetTextColor(0.42, 0.24, 0.04, 1)

    local descFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -2)
    descFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    descFs:SetJustifyH("LEFT")
    descFs:SetText(description)
    descFs:SetTextColor(0.35, 0.28, 0.18, 1)

    return check, -46
end

local function BindAssistCheck(check, key)
    if type(assistChecks[key]) ~= "table" or assistChecks[key].SetChecked then
        local prior = assistChecks[key]
        assistChecks[key] = {}
        if type(prior) == "table" and prior.SetChecked then
            assistChecks[key][1] = prior
        end
    end
    assistChecks[key][#assistChecks[key] + 1] = check
    check:SetScript("OnClick", function(self)
        local on = CheckButtonIsOn(self)
        draftAssists[key] = on
        SyncCheckGroup(assistChecks[key], on)
        MarkDirty()
    end)
end

local function BindPrefCheck(check, key)
    if type(prefChecks[key]) ~= "table" or prefChecks[key].SetChecked then
        local prior = prefChecks[key]
        prefChecks[key] = {}
        if type(prior) == "table" and prior.SetChecked then
            prefChecks[key][1] = prior
        end
    end
    prefChecks[key][#prefChecks[key] + 1] = check
    check:SetScript("OnClick", function(self)
        local on = CheckButtonIsOn(self)
        draftPrefs[key] = on
        SyncCheckGroup(prefChecks[key], on)
        MarkDirty()
    end)
end

local function CreateToolButton(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetHeight(28)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function BuildCategoryPage(parent, id)
    local page = CreateFrame("Frame", FRAME_NAME .. "Cat_" .. id, parent)
    page:SetAllPoints(parent)
    page:Hide()
    categoryPages[id] = page
    return page
end

local function BuildAssistContent(content)
    assistShell = CreateFrame("Frame", FRAME_NAME .. "AssistShell", content)
    assistShell:SetAllPoints(content)

    local NC = Chrome()
    local sidebar = CreateFrame("Frame", FRAME_NAME .. "Sidebar", assistShell)
    sidebar:SetPoint("TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    if NC and NC.ApplySidebar then
        NC.ApplySidebar(sidebar)
    end

    local sideLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sideLabel:SetPoint("TOPLEFT", 10, -10)
    sideLabel:SetText("CATEGORIES")
    sideLabel:SetTextColor(0.78, 0.62, 0.24, 1)

    local y = -28
    for index = 1, #CATEGORIES do
        local cat = CATEGORIES[index]
        local btn = CreateFrame("Button", FRAME_NAME .. "Nav_" .. cat.id, sidebar)
        btn:SetHeight(28)
        btn:SetPoint("TOPLEFT", 8, y)
        btn:SetPoint("TOPRIGHT", -8, y)
        if NC and NC.ApplyNavButton then
            NC.ApplyNavButton(btn, false)
        end
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", 10, 0)
        lbl:SetText(cat.label)
        lbl:SetTextColor(0.92, 0.85, 0.65, 1)
        btn._label = lbl
        btn:SetScript("OnClick", function()
            MainWindow.SelectCategory(cat.id)
        end)
        categoryButtons[cat.id] = btn
        y = y - 32
    end

    local main = CreateFrame("Frame", FRAME_NAME .. "AssistMain", assistShell)
    main:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    main:SetPoint("BOTTOMRIGHT", assistShell, "BOTTOMRIGHT", 0, 36)

    if NC and NC.ApplyParchment then
        NC.ApplyParchment(main)
    end

    categoryHeadTitle = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoryHeadTitle:SetPoint("TOPLEFT", 12, -10)
    categoryHeadTitle:SetText("Windows & Tools")
    categoryHeadTitle:SetTextColor(0.30, 0.20, 0.04, 1)

    categoryHeadSub = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    categoryHeadSub:SetPoint("TOPLEFT", categoryHeadTitle, "BOTTOMLEFT", 0, -2)
    categoryHeadSub:SetPoint("RIGHT", main, "RIGHT", -12, 0)
    categoryHeadSub:SetJustifyH("LEFT")
    categoryHeadSub:SetTextColor(0.28, 0.22, 0.12, 1)

    local pageHost = CreateFrame("Frame", FRAME_NAME .. "PageHost", main)
    pageHost:SetPoint("TOPLEFT", 10, -48)
    pageHost:SetPoint("BOTTOMRIGHT", -10, 8)

    -- Footer bar (outside parchment main, still inside assist shell)
    local footer = CreateFrame("Frame", FRAME_NAME .. "AssistFooter", assistShell)
    footer:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -4)
    footer:SetPoint("BOTTOMRIGHT", assistShell, "BOTTOMRIGHT", 0, 0)

    footerStatus = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerStatus:SetPoint("LEFT", 4, 0)
    footerStatus:SetWidth(280)
    footerStatus:SetJustifyH("LEFT")

    saveButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    saveButton:SetWidth(110)
    saveButton:SetHeight(22)
    saveButton:SetPoint("RIGHT", 0, 0)
    saveButton:SetText("Save changes")
    saveButton:SetScript("OnClick", SaveDraft)

    cancelButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    cancelButton:SetWidth(70)
    cancelButton:SetHeight(22)
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", CancelDraft)

    unstickButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    unstickButton:SetWidth(70)
    unstickButton:SetHeight(22)
    unstickButton:SetPoint("RIGHT", cancelButton, "LEFT", -6, 0)
    unstickButton:SetText("Unstick")
    unstickButton:SetScript("OnClick", UnstickRapid)

    stopButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    stopButton:SetWidth(60)
    stopButton:SetHeight(22)
    stopButton:SetPoint("RIGHT", unstickButton, "LEFT", -6, 0)
    stopButton:SetText("Stop")
    stopButton:SetScript("OnClick", StopAutoRoll)

    startButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    startButton:SetWidth(60)
    startButton:SetHeight(22)
    startButton:SetPoint("RIGHT", stopButton, "LEFT", -6, 0)
    startButton:SetText("Start")
    startButton:SetScript("OnClick", StartAutoRoll)

    --------------------------------------------------------------------
    -- General
    --------------------------------------------------------------------
    local general = BuildCategoryPage(pageHost, CAT_GENERAL)
    local g1 = general:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    g1:SetPoint("TOPLEFT", 4, -4)
    g1:SetPoint("RIGHT", -4, 0)
    g1:SetJustifyH("LEFT")
    g1:SetText("AscensionSuite layers a player-owned Wishlist and opt-in assists on "
        .. "Ascension's native Rapid Rolling UI. It does not rebuild Desired columns.")
    g1:SetTextColor(0.20, 0.14, 0.06, 1)

    local g2 = general:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    g2:SetPoint("TOPLEFT", g1, "BOTTOMLEFT", 0, -14)
    g2:SetPoint("RIGHT", -4, 0)
    g2:SetJustifyH("LEFT")
    g2:SetText("Safety (always):\n"
        .. "\226\128\162 Assists default off until you enable them and Save\n"
        .. "\226\128\162 Suite never auto-Unlearns and never spends Scroll of Fortune\n"
        .. "\226\128\162 No Draft / Hall of Fame / store automation\n"
        .. "\226\128\162 Wild Card dice stay under this window while it is open")
    g2:SetTextColor(0.30, 0.22, 0.10, 1)

    CreateSectionLabel(general, "More assists", -130)
    local gy = -148
    local gCheck
    gCheck = select(1, CreateToggleRow(general, gy,
        "Instant skip SkillCard flipbook",
        "Speeds SkillCard reveal flipbooks only.",
        function() end))
    BindAssistCheck(gCheck, "instantSkillCardSkip")
    gy = gy - 46
    gCheck = select(1, CreateToggleRow(general, gy,
        "Auto-unstick gray Rapid Continue",
        "Recover stuck Continue or an unclickable leveling die after a short wait.",
        function() end))
    BindAssistCheck(gCheck, "autoUnstick")

    --------------------------------------------------------------------
    -- Automation
    --------------------------------------------------------------------
    local auto = BuildCategoryPage(pageHost, CAT_AUTOMATION)

    local counts = CreateFrame("Frame", nil, auto)
    counts:SetPoint("TOPLEFT", 0, 0)
    counts:SetPoint("TOPRIGHT", 0, 0)
    counts:SetHeight(44)

    local NCCounts = Chrome()
    local cardW = math.floor((ContentWidth() - SIDEBAR_WIDTH - 40) / 3)
    local c1 = CreateFrame("Frame", nil, counts)
    c1:SetWidth(cardW)
    c1:SetHeight(40)
    c1:SetPoint("TOPLEFT", 0, 0)
    if NCCounts and NCCounts.ApplyToggleRow then
        NCCounts.ApplyToggleRow(c1)
    end
    local c1l = c1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c1l:SetPoint("TOP", 0, -4)
    c1l:SetText("WISHLIST")
    c1l:SetTextColor(0.35, 0.28, 0.18, 1)
    countWishlist = c1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countWishlist:SetPoint("BOTTOM", 0, 6)
    countWishlist:SetText("0")

    local c2 = CreateFrame("Frame", nil, counts)
    c2:SetWidth(cardW)
    c2:SetHeight(40)
    c2:SetPoint("LEFT", c1, "RIGHT", 6, 0)
    if NCCounts and NCCounts.ApplyToggleRow then
        NCCounts.ApplyToggleRow(c2)
    end
    local c2l = c2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c2l:SetPoint("TOP", 0, -4)
    c2l:SetText("DESIRED")
    c2l:SetTextColor(0.35, 0.28, 0.18, 1)
    countDesired = c2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countDesired:SetPoint("BOTTOM", 0, 6)
    countDesired:SetText("0 / 0")
    countDesired:SetTextColor(0.12, 0.40, 0.18, 1)

    local c3 = CreateFrame("Frame", nil, counts)
    c3:SetWidth(cardW)
    c3:SetHeight(40)
    c3:SetPoint("LEFT", c2, "RIGHT", 6, 0)
    if NCCounts and NCCounts.ApplyToggleRow then
        NCCounts.ApplyToggleRow(c3)
    end
    local c3l = c3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c3l:SetPoint("TOP", 0, -4)
    c3l:SetText("UNDESIRED")
    c3l:SetTextColor(0.35, 0.28, 0.18, 1)
    countUndesired = c3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countUndesired:SetPoint("BOTTOM", 0, 6)
    countUndesired:SetText("0")
    countUndesired:SetTextColor(0.55, 0.30, 0.10, 1)

    CreateSectionLabel(auto, "Assists", -52)
    local ay = -70
    local check
    check = select(1, CreateToggleRow(auto, ay,
        "Auto-Roll while leveling",
        "Desired Ability/Talent targets only. Never Unlearn / Scroll of Fortune.",
        function() end))
    BindAssistCheck(check, "autoRoll")
    ay = ay - 46

    check = select(1, CreateToggleRow(auto, ay,
        "Keep going after a Desired hit",
        "Close the session and start the next one instead of handing control back.",
        function() end))
    BindAssistCheck(check, "autoRollContinue")
    ay = ay - 46

    check = select(1, CreateToggleRow(auto, ay,
        "Instant skip WildCardDice animation",
        "Speeds flipbooks only — never starts a roll alone.",
        function() end))
    BindAssistCheck(check, "instantDiceSkip")
    ay = ay - 46

    check = select(1, CreateToggleRow(auto, ay,
        "Accept Wildcard confirm popups",
        "Mass roll / leveling confirms only — never Unlearn Accept.",
        function() end))
    BindAssistCheck(check, "acceptWildcardPopups")
    ay = ay - 50

    CreateSectionLabel(auto, "Logbook", ay)
    ay = ay - 18

    local logBox = CreateFrame("Frame", nil, auto)
    logBox:SetPoint("TOPLEFT", 0, ay)
    logBox:SetPoint("TOPRIGHT", 0, ay)
    logBox:SetHeight(72)
    if logBox.SetBackdrop then
        logBox:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        logBox:SetBackdropColor(0.15, 0.11, 0.06, 0.18)
        logBox:SetBackdropBorderColor(0.55, 0.45, 0.18, 0.9)
    end
    logHost = logBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logHost:SetPoint("TOPLEFT", 8, -8)
    logHost:SetPoint("BOTTOMRIGHT", -8, 8)
    logHost:SetJustifyH("LEFT")
    logHost:SetTextColor(0.22, 0.16, 0.08, 1)

    autoRollStatus = auto:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoRollStatus:SetPoint("TOPLEFT", logBox, "BOTTOMLEFT", 0, -6)
    autoRollStatus:SetPoint("RIGHT", auto, "RIGHT", 0, 0)
    autoRollStatus:SetJustifyH("LEFT")

    --------------------------------------------------------------------
    -- Logbook category
    --------------------------------------------------------------------
    local logPage = BuildCategoryPage(pageHost, CAT_LOGBOOK)
    CreateSectionLabel(logPage, "Capture", -4)
    check = select(1, CreateToggleRow(logPage, -22,
        "Capture rolls into Logbook",
        "Write roll results (and assist decisions when detailed logging is on) into the suite logbook.",
        function() end))
    BindAssistCheck(check, "captureRolls")

    CreateSectionLabel(logPage, "Recent rolls", -86)
    local logFullBox = CreateFrame("Frame", nil, logPage)
    logFullBox:SetPoint("TOPLEFT", 0, -104)
    logFullBox:SetPoint("BOTTOMRIGHT", 0, 4)
    if logFullBox.SetBackdrop then
        logFullBox:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        logFullBox:SetBackdropColor(0.15, 0.11, 0.06, 0.18)
        logFullBox:SetBackdropBorderColor(0.55, 0.45, 0.18, 0.9)
    end
    logHostFull = logFullBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logHostFull:SetPoint("TOPLEFT", 8, -8)
    logHostFull:SetPoint("BOTTOMRIGHT", -8, 8)
    logHostFull:SetJustifyH("LEFT")
    logHostFull:SetTextColor(0.22, 0.16, 0.08, 1)

    --------------------------------------------------------------------
    -- Windows & Tools
    --------------------------------------------------------------------
    local windows = BuildCategoryPage(pageHost, CAT_WINDOWS)
    CreateSectionLabel(windows, "Open a window", -4)

    local grid = CreateFrame("Frame", nil, windows)
    grid:SetPoint("TOPLEFT", 0, -22)
    grid:SetPoint("TOPRIGHT", 0, -22)
    grid:SetHeight(100)

    local tools = {
        { "Wishlist", function() MainWindow.SelectTab(TAB_WISHLIST) end },
        { "Loadouts", function() MainWindow.SelectTab(TAB_LOADOUTS) end },
        { "Commands guide", function()
            Print("Slash: /asuite opens this window. Assists default off. Never auto-Unlearn.")
            Print("Wishlist: Push to Desired / Sync from Rapid. Loadouts: Apply → Desired.")
        end },
        { "Roll logbook", function() MainWindow.SelectCategory(CAT_LOGBOOK) end },
        { "Debug / Click Trace", function()
            MainWindow.SelectCategory(CAT_WINDOWS)
            Print("Toggle “Log every button click” below, then Save. Off by default.")
        end },
        { "Error log", function()
            Print("Lua errors appear in the default client error frame (BugGrabber / !Swatter if installed).")
        end },
    }

    local colW = math.floor(((ContentWidth() - SIDEBAR_WIDTH - 36) - 8) / 2)
    for index = 1, #tools do
        local spec = tools[index]
        local btn = CreateToolButton(grid, spec[1], spec[2])
        btn:SetWidth(colW)
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        btn:SetPoint("TOPLEFT", col * (colW + 8), -(row * 34))
    end

    CreateSectionLabel(windows, "Toggles", -130)
    local wy = -148
    check = select(1, CreateToggleRow(windows, wy,
        "Detailed automation logging",
        "Write Auto-Roll / Instant Skip decisions into the suite logbook (Capture rolls).",
        function() end))
    -- Maps to captureRolls so one Save path covers Logbook + Windows diagnostics.
    BindAssistCheck(check, "captureRolls")
    wy = wy - 46

    check = select(1, CreateToggleRow(windows, wy,
        "Log every button click",
        "Trace UI clicks for stuck-dice or overlap debugging. Off by default.",
        function() end))
    BindPrefCheck(check, "clickTrace")
    wy = wy - 46

    check = select(1, CreateToggleRow(windows, wy,
        "Show Desired / Undesired badges",
        "Mark wishlist rows from Rapid Desired vs Undesired lists.",
        function() end))
    BindPrefCheck(check, "showWishlistBadges")

    --------------------------------------------------------------------
    -- Wishlist sync
    --------------------------------------------------------------------
    local sync = BuildCategoryPage(pageHost, CAT_SYNC)
    CreateSectionLabel(sync, "Sync", -4)
    local syncBtn = CreateFrame("Button", FRAME_NAME .. "SyncButton", sync, "UIPanelButtonTemplate")
    syncBtn:SetWidth(140)
    syncBtn:SetHeight(24)
    syncBtn:SetPoint("TOPLEFT", 0, -24)
    syncBtn:SetText("Sync from Rapid")
    syncBtn:SetScript("OnClick", SyncDesiredFromNative)

    syncStatus = sync:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncStatus:SetPoint("LEFT", syncBtn, "RIGHT", 12, 0)
    syncStatus:SetPoint("RIGHT", sync, "RIGHT", 0, 0)
    syncStatus:SetJustifyH("LEFT")
    syncStatus:SetTextColor(0.28, 0.22, 0.12, 1)

    desiredStatus = syncStatus

    local syncHelp = sync:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncHelp:SetPoint("TOPLEFT", syncBtn, "BOTTOMLEFT", 0, -16)
    syncHelp:SetPoint("RIGHT", sync, "RIGHT", 0, 0)
    syncHelp:SetJustifyH("LEFT")
    syncHelp:SetText("Sync widens the Rapid Desired search temporarily, reads Ascension's "
        .. "saved Desired toggles, and merges confirmed marks into your Suite wishlist. "
        .. "It never clears Ascension Desired and never marks Undesired.")
    syncHelp:SetTextColor(0.28, 0.22, 0.12, 1)

    CopyAssistDraft()
    MainWindow.SelectCategory(CAT_WINDOWS)
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

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
        if GameTooltip then
            GameTooltip:Hide()
        end
        local panel = GetWishlistPanel()
        if panel and panel.HideTooltips then
            panel.HideTooltips()
        end
        local API = AscensionSuite.AscensionAPI
        if API then
            if API.ClearDiceHoverArtifacts then
                API.ClearDiceHoverArtifacts()
            end
            if API.RestoreDiceAfterSuite then
                API.RestoreDiceAfterSuite()
            end
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(130)

    frame.numTabs = 3
    frame.selectedTab = activeTab

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("TOPLEFT", 20, -16)
    titleLabel:SetText("AscensionSuite")

    versionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    versionLabel:SetPoint("LEFT", titleLabel, "RIGHT", 8, 0)
    versionLabel:SetText("v" .. tostring(AscensionSuite.VERSION or "?"))

    subheadLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subheadLabel:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -2)
    subheadLabel:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    subheadLabel:SetJustifyH("LEFT")
    subheadLabel:SetText("Wishlist, Loadouts, and opt-in assists.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local wishlistTab = CreateTab(frame, TAB_WISHLIST, "Wishlist")
    wishlistTab:SetPoint("TOPLEFT", 14, -52)

    local loadoutsTab = CreateTab(frame, TAB_LOADOUTS, "Loadouts")
    loadoutsTab:SetPoint("LEFT", wishlistTab, "RIGHT", -14, 0)

    local assistTab = CreateTab(frame, TAB_ASSISTS, "Assists")
    assistTab:SetPoint("LEFT", loadoutsTab, "RIGHT", -14, 0)

    if type(_G.PanelTemplates_SetNumTabs) == "function" then
        pcall(_G.PanelTemplates_SetNumTabs, frame, 3)
    end

    local bodyTop = CONTENT_TOP
    local bodyHeight = FRAME_HEIGHT + CONTENT_TOP - 18
    local NC = Chrome()
    for index = 1, 3 do
        local content = CreateFrame("Frame", FRAME_NAME .. "Content" .. index, frame)
        content:SetPoint("TOPLEFT", CONTENT_INSET, bodyTop)
        content:SetWidth(ContentWidth())
        content:SetHeight(bodyHeight)
        content:Hide()
        -- Wishlist + Loadouts sit in clipped parchment; Assists builds its own shell.
        if index ~= TAB_ASSISTS and NC and NC.ApplyParchment then
            NC.ApplyParchment(content)
        end
        contents[index] = content
    end

    BuildAssistContent(contents[TAB_ASSISTS])
    RefreshAssistToggles()
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

    local API = AscensionSuite.AscensionAPI
    if API then
        if API.ClearDiceHoverArtifacts then
            API.ClearDiceHoverArtifacts()
        end
        if API.SanitizeDiceHover then
            API.SanitizeDiceHover()
        end
        if API.SyncDiceLayeringForSuite then
            API.SyncDiceLayeringForSuite()
        end
    end
    if GameTooltip then
        GameTooltip:Hide()
    end

    MainWindow.InvalidateLayout()
    MainWindow.SelectTab(activeTab)

    if activeTab == TAB_LOADOUTS then
        EnsureLoadoutsPanel()
        MainWindow.RefreshLoadouts()
    else
        EnsureWishlistPanel()
        MainWindow.RefreshWishlist()
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
