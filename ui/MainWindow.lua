-- AscensionSuite: ui/MainWindow.lua
-- Thin assist overlay: toggles, wishlist sync, profiles, logbook. Native Rapid UI stays authoritative.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local MainWindow = {}
AscensionSuite.MainWindow = MainWindow

local FRAME_NAME = "AscensionSuiteMainWindow"
local GRID_COLUMNS = 8
-- The grid is a fixed two rows. Marking Desired in Ascension's own windows can
-- fill it far faster than typing ids ever did, so the rest is counted instead.
local GRID_ROWS = 2
local CELL_GAP = 10
local LOG_LINES = 6

local frame
local inputBox
local profileBox
local gridHost
local gridOverflow
local logHost
local cells = {}
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

local function ParseInput(text)
    local id = tonumber(text)
    if not id then
        return nil
    end
    return math.floor(id)
end

local function CreateCheckbox(parent, label, assistKey, yOffset)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 20, yOffset)
    check:SetSize(24, 24)

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
    no_desired_targets = "mark a wishlist spell Desired first",
    level_out_of_range = "only runs while leveling 1-60",
    not_wildcard = "not in Wildcard mode",
    rapid_not_ready = "no roll available right now",
    roll_in_flight = "waiting on the current roll",
    session_complete = "rapid session finished",
    user_stop = "stopped by you",
    native_roll_error = "Ascension's Roll button raised an error",
    native_error = "Ascension refused the roll - see its error message",
    stalled = "rapid session stopped making progress",
    desired_learned = "rolled a Desired entry - start again for the next one",
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

    if autoRollStatus then
        if running then
            autoRollStatus:SetText("Auto-Roll: running")
            autoRollStatus:SetTextColor(0.43, 0.81, 0.54, 1)
        elseif AutoRoller and AutoRoller.GetLastError and AutoRoller.GetLastError() then
            autoRollStatus:SetText("Auto-Roll stopped — " .. MainWindow.DescribeStopReason(AutoRoller.GetLastError()))
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

-- "Desired" is what the client confirms right now; "tracked" is every entry the
-- addon holds an (id, type) pair for. They differ on purpose: only the tracked
-- ones can be verified at all, and Auto-Roll gates on the confirmed subset.
function MainWindow.RefreshDesiredStatus(note)
    if not desiredStatus then
        return
    end

    local Wishlist = AscensionSuite.Wishlist
    if not Wishlist or not Wishlist.CollectTracked then
        return
    end

    local text = string.format("Desired: %d of %d tracked",
        Wishlist.CountDesired(), #Wishlist.CollectTracked())
    if note then
        text = text .. "  |  " .. note
    end
    desiredStatus:SetText(text)
end

function MainWindow.RefreshGrid()
    if not gridHost then
        return
    end

    local SpellCell = AscensionSuite.SpellCell
    local Wishlist = AscensionSuite.Wishlist
    if not SpellCell or not SpellCell.Create or not Wishlist then
        return
    end

    local spellIds = Wishlist.GetSpellIds()
    local hidden = math.max(0, #spellIds - GRID_COLUMNS * GRID_ROWS)
    local needed = #spellIds - hidden
    while #cells < needed do
        local index = #cells + 1
        local cell = SpellCell.Create(gridHost, FRAME_NAME .. "Cell" .. index)
        cell:SetOnChanged(function()
            MainWindow.RefreshGrid()
            MainWindow.RefreshDesiredStatus()
        end)
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

    if gridOverflow then
        if hidden > 0 then
            gridOverflow:SetText(string.format("+ %d more not shown", hidden))
            gridOverflow:Show()
        else
            gridOverflow:Hide()
        end
    end
end

-- Everything that changes when a Desired mark lands, from any source. Skipped
-- while the overlay is closed so a bulk desire in the Rapid window does not
-- rebuild a grid nobody is looking at.
function MainWindow.RefreshWishlist()
    if not frame or not frame:IsShown() then
        return
    end
    MainWindow.RefreshGrid()
    MainWindow.RefreshDesiredStatus()
end

local function RefreshAssistToggles()
    local assists = GetAssists()
    for key, check in pairs(assistChecks) do
        check:SetChecked(assists[key] == true)
    end
    MainWindow.RefreshAutoRoll()
end

local function AddSpellFromInput()
    if not inputBox then
        return
    end

    local spellId = ParseInput(inputBox:GetText())
    if not spellId then
        return
    end

    local Wishlist = AscensionSuite.Wishlist
    if Wishlist and Wishlist.AddToDesired then
        Wishlist.AddToDesired(spellId)
    end

    inputBox:SetText("")
    MainWindow.RefreshGrid()
    MainWindow.RefreshDesiredStatus()
end

local function SyncDesiredFromNative()
    local DesiredSync = AscensionSuite.DesiredSync
    if not DesiredSync or not DesiredSync.Sync then
        return
    end

    local added, scanned = DesiredSync.Sync()
    local note
    if scanned == 0 then
        note = "no candidates to scan - clear the Rapid search box"
    elseif added == 0 then
        note = string.format("scanned %d, nothing new", scanned)
    else
        note = string.format("+%d from Rapid", added)
    end

    MainWindow.RefreshGrid()
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
    MainWindow.RefreshGrid()
    MainWindow.RefreshDesiredStatus()
end

local function StartAutoRoll()
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.Start then
        AutoRoller.Start()
    end
    MainWindow.RefreshAutoRoll()
end

local function StopAutoRoll()
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.Stop then
        AutoRoller.Stop("user_stop")
    end
    MainWindow.RefreshAutoRoll()
end

local function EnsureFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(720, 568)
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
    title:SetPoint("TOPLEFT", 24, -18)
    title:SetText("AscensionSuite assists")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", 24, -42)
    subtitle:SetWidth(420)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Native Rapid Rolling is the board. Suite syncs Desired, captures rolls, and optional assists.")

    CreateCheckbox(frame, "Auto-Roll while leveling (Desired targets only)", "autoRoll", -70)
    CreateCheckbox(frame, "Instant skip WildCardDice animation", "instantDiceSkip", -94)
    CreateCheckbox(frame, "Instant skip SkillCard flipbook", "instantSkillCardSkip", -118)
    CreateCheckbox(frame, "Accept Wildcard confirm popups", "acceptWildcardPopups", -142)
    CreateCheckbox(frame, "Capture rolls into Logbook", "captureRolls", -166)

    startButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startButton:SetSize(90, 22)
    startButton:SetPoint("TOPLEFT", 280, -72)
    startButton:SetText("Start")
    startButton:SetScript("OnClick", StartAutoRoll)

    stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopButton:SetSize(90, 22)
    stopButton:SetPoint("TOPLEFT", startButton, "BOTTOMLEFT", 0, -6)
    stopButton:SetText("Stop")
    stopButton:SetScript("OnClick", StopAutoRoll)

    autoRollStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoRollStatus:SetPoint("TOPLEFT", stopButton, "BOTTOMLEFT", 0, -6)
    autoRollStatus:SetWidth(180)
    autoRollStatus:SetJustifyH("LEFT")

    profileBox = CreateFrame("EditBox", FRAME_NAME .. "Profile", frame, "InputBoxTemplate")
    profileBox:SetSize(120, 24)
    profileBox:SetPoint("TOPRIGHT", -52, -20)
    profileBox:SetAutoFocus(false)
    profileBox:SetMaxLetters(32)
    profileBox:SetText("my-hero")

    local saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveButton:SetSize(56, 22)
    saveButton:SetPoint("TOPRIGHT", profileBox, "BOTTOMRIGHT", 0, -6)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", SaveProfile)

    local loadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    loadButton:SetSize(56, 22)
    loadButton:SetPoint("RIGHT", saveButton, "LEFT", -8, 0)
    loadButton:SetText("Load")
    loadButton:SetScript("OnClick", LoadProfile)

    inputBox = CreateFrame("EditBox", FRAME_NAME .. "Input", frame, "InputBoxTemplate")
    inputBox:SetSize(120, 24)
    inputBox:SetPoint("TOPLEFT", 24, -200)
    inputBox:SetAutoFocus(false)
    inputBox:SetNumeric(true)
    inputBox:SetMaxLetters(8)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputLabel:SetPoint("BOTTOMLEFT", inputBox, "TOPLEFT", 0, 2)
    inputLabel:SetText("Spell / entry id → Ascension Desired")

    local addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addButton:SetSize(72, 22)
    addButton:SetPoint("LEFT", inputBox, "RIGHT", 12, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", AddSpellFromInput)

    inputBox:SetScript("OnEnterPressed", function(self)
        AddSpellFromInput()
        self:ClearFocus()
    end)

    desiredStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desiredStatus:SetPoint("TOPLEFT", 24, -236)
    desiredStatus:SetWidth(420)
    desiredStatus:SetJustifyH("LEFT")

    local syncButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    syncButton:SetSize(120, 22)
    syncButton:SetPoint("TOPLEFT", 452, -232)
    syncButton:SetText("Sync from Rapid")
    syncButton:SetScript("OnClick", SyncDesiredFromNative)

    gridHost = CreateFrame("Frame", nil, frame)
    gridHost:SetPoint("TOPLEFT", 24, -262)
    gridHost:SetSize(420, 148)

    gridOverflow = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    gridOverflow:SetPoint("TOPLEFT", 24, -416)
    gridOverflow:SetJustifyH("LEFT")
    gridOverflow:Hide()

    local logLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logLabel:SetPoint("TOPLEFT", 24, -436)
    logLabel:SetText("Logbook (recent)")

    logHost = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logHost:SetPoint("TOPLEFT", 24, -452)
    logHost:SetWidth(660)
    logHost:SetJustifyH("LEFT")

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 12)
    hint:SetText("Click a cell to toggle Desired · Alt + right-click a spell in the Character Advancement book · /asuite")

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
    MainWindow.RefreshGrid()
    MainWindow.RefreshDesiredStatus()
    MainWindow.RefreshLogbook()
    MainWindow.RefreshAutoRoll()
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
