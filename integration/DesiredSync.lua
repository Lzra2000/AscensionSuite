-- AscensionSuite: integration/DesiredSync.lua
-- Keep the Suite wishlist in step with the Desired marks the player makes in
-- Ascension's own windows, and offer one way to make a mark from the
-- Character Advancement book.
--
-- Everything the client exposes about Desired is a per-entry IsDesiredID probe:
-- there is no count and no listing of selections. So the addon has to learn each
-- (id, type) pair as it goes. Three sources feed the tracked registry:
--
--   1. WildCardRapidRollingFrame:SaveDesiredEntry / :RemoveDesiredEntry -- the
--      funnel every Desired toggle in the native Rapid window goes through,
--      including the "desire all build spells" bulk actions.
--   2. WILDCARD_DESIRED_ENTRIES_CHANGED -- rescans the Rapid window's filtered
--      candidate list and keeps the rows IsDesiredID confirms, which recovers
--      marks made before the addon was watching.
--   3. Alt + right-click on a Character Advancement spell button.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local DesiredSync = {}
AscensionSuite.DesiredSync = DesiredSync

-- A rescan walks the whole filtered candidate list, so it is coalesced to one
-- run per frame and then rate limited: Ascension fires the change event once per
-- entry during a bulk desire.
local RESCAN_INTERVAL = 1.0

local hookedRapid = false
local hookedBook = false
local watcher
local scanner
local pendingScan = false
local lastScan = 0

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function GetWishlist()
    return AscensionSuite.Wishlist
end

-- nil outside the client, which turns the rate limit off rather than latching it
-- on: without a clock every elapsed time would read as zero.
local function Now()
    if type(_G.GetTime) == "function" then
        return _G.GetTime()
    end
    return nil
end

local function Print(message)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and type(chat.AddMessage) == "function" then
        chat:AddMessage("|cff6ba8e8AscensionSuite|r " .. tostring(message))
    end
end

local function RefreshOverlay()
    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshWishlist then
        MainWindow.RefreshWishlist()
    end
end

------------------------------------------------------------------------
-- Tracking
------------------------------------------------------------------------

function DesiredSync.Track(entryId, entryType, spellId, name)
    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.TrackEntry then
        return false
    end

    local ok, isNew = Wishlist.TrackEntry(entryId, entryType, spellId, name)
    if ok and isNew then
        RefreshOverlay()
    end
    return ok, isNew
end

function DesiredSync.Untrack(entryId, entryType)
    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.UntrackEntry then
        return false
    end

    local removed = Wishlist.UntrackEntry(entryId, entryType)
    if removed then
        RefreshOverlay()
    end
    return removed
end

-- Full rescan of the Rapid window's Desired candidate list. Returns how many
-- entries this run newly tracked and how many candidates it looked at, so the
-- caller can tell "nothing was marked" apart from "nothing was scanned" -- an
-- empty scan usually means the Rapid search box is narrowing the candidates.
function DesiredSync.Sync()
    -- Cleared before the guard: a scan that cannot run must still leave the
    -- queue empty, or the scanner frame retries it every frame.
    lastScan = Now()
    pendingScan = false

    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.SyncFromNative then
        return 0, 0
    end

    local added, scanned = Wishlist.SyncFromNative()
    if added > 0 then
        RefreshOverlay()
    end
    return added, scanned
end

local function FlushScan()
    if not pendingScan then
        return
    end

    local now = Now()
    if now and lastScan and (now - lastScan) < RESCAN_INTERVAL then
        return
    end
    DesiredSync.Sync()
end

local function QueueScan()
    pendingScan = true
    if not scanner then
        return
    end
    scanner:Show()
end

------------------------------------------------------------------------
-- Marking from the Character Advancement book
------------------------------------------------------------------------

-- Toggles one advancement entry's Desired state and mirrors the result into the
-- tracked registry. Returns the new state so callers can phrase their feedback.
function DesiredSync.ToggleDesired(entryId, entryType, spellId, name)
    local api = GetAPI()
    local id = tonumber(entryId)
    if not api or not id or type(entryType) ~= "string" or entryType == "" then
        return false, "invalid_entry"
    end

    if not api.IsWildcardModeActive() then
        return false, "not_wildcard"
    end

    -- Name lookups go through the spell id when there is one: GetEntryName
    -- resolves spell-first, so handing it an internal id can name the wrong entry.
    local label = name
    if not label and spellId then
        label = api.GetEntryName(spellId)
    end
    label = label or ("entry " .. tostring(id))

    if api.IsDesiredID(id, entryType) then
        api.RemoveDesiredID(id, entryType)
        DesiredSync.Untrack(id, entryType)
        return true, "removed", label
    end

    if not api.CanAddDesiredID(id, entryType) then
        return false, "cannot_add", label
    end

    local ok, reason = api.AddDesiredID(id, entryType)
    if not ok then
        return false, reason or "add_failed", label
    end

    DesiredSync.Track(id, entryType, spellId, name)
    return true, "added", label
end

-- Ascension routes every right-click on a CA spell button -- book grid, talent
-- grid, compact buttons and the browser list all share CASpellButtonBaseMixin --
-- through CharacterAdvancement:ShowSpellDropDownMenu. That single funnel is the
-- hook point; the modifier has to be Alt + *right*-click because plain Alt-click
-- is Ascension's unlearn and Shift-click is its learn, neither of which may
-- change meaning.
function DesiredSync.OnSpellDropDown(spellButton)
    if type(spellButton) ~= "table" then
        return false
    end

    local isAlt = _G.IsAltKeyDown
    if type(isAlt) ~= "function" or not isAlt() then
        return false
    end

    local entry = spellButton.entry
    if type(entry) ~= "table" then
        return false
    end

    local entryId = tonumber(entry.ID or entry.Id or entry.id)
    local entryType = entry.Type or entry.type
    if not entryId or type(entryType) ~= "string" then
        return false
    end

    -- The dropdown was already opened by the native handler; close it again so
    -- Alt + right-click reads as a mark rather than a menu.
    if type(_G.CloseDropDownMenus) == "function" then
        _G.CloseDropDownMenus()
    end

    local ok, result, label = DesiredSync.ToggleDesired(entryId, entryType, spellButton.spellID, entry.Name)
    label = label or entry.Name or ("entry " .. tostring(entryId))

    if ok and result == "added" then
        Print("Desired: " .. label)
    elseif ok and result == "removed" then
        Print("No longer Desired: " .. label)
    elseif result == "not_wildcard" then
        Print("Desired marks only exist in Wildcard mode.")
    else
        Print("Cannot mark " .. label .. " Desired (" .. tostring(result) .. ").")
    end

    return ok
end

------------------------------------------------------------------------
-- Hook installation
------------------------------------------------------------------------

local function HookMethod(host, methodName, handler)
    if type(host) ~= "table" or type(host[methodName]) ~= "function" then
        return false
    end
    if type(_G.hooksecurefunc) ~= "function" then
        return false
    end
    return pcall(_G.hooksecurefunc, host, methodName, handler)
end

-- Mixins are copied onto the frame (SharedXML/Util/Mixin.lua), so the live
-- WildCardRapidRollingFrame carries its own copy of these methods and hooking
-- WildCardRapidRollingMixin after the fact would miss every call.
local function AttachRapid()
    local frame = _G.WildCardRapidRollingFrame
    if hookedRapid or type(frame) ~= "table" then
        return false
    end

    local saved = HookMethod(frame, "SaveDesiredEntry", function(_, entryId, entryType)
        DesiredSync.Track(entryId, entryType)
    end)

    local removed = HookMethod(frame, "RemoveDesiredEntry", function(_, entryId, entryType)
        DesiredSync.Untrack(entryId, entryType)
    end)

    hookedRapid = saved or removed
    return hookedRapid
end

local function AttachBook()
    local book = _G.CharacterAdvancement
    if hookedBook or type(book) ~= "table" then
        return false
    end

    hookedBook = HookMethod(book, "ShowSpellDropDownMenu", function(_, spellButton)
        DesiredSync.OnSpellDropDown(spellButton)
    end)
    return hookedBook
end

-- Ascension_WildCard and Ascension_CharacterAdvancement are load-on-demand, so
-- the frames these hooks need usually do not exist yet at our own ADDON_LOADED.
function DesiredSync.Attach()
    local rapid = AttachRapid()
    local book = AttachBook()
    return rapid or book
end

function DesiredSync.IsAttached()
    return hookedRapid, hookedBook
end

function DesiredSync.Init()
    DesiredSync.Attach()

    if watcher or type(CreateFrame) ~= "function" then
        return
    end

    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:RegisterEvent("WILDCARD_DESIRED_ENTRIES_CHANGED")
    watcher:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
            if name == "Ascension_WildCard" or name == "Ascension_CharacterAdvancement" then
                DesiredSync.Attach()
            end
            return
        end
        if event == "WILDCARD_DESIRED_ENTRIES_CHANGED" then
            DesiredSync.Attach()
            QueueScan()
        end
    end)

    scanner = CreateFrame("Frame")
    scanner:Hide()
    scanner:SetScript("OnUpdate", function(self)
        FlushScan()
        if not pendingScan then
            self:Hide()
        end
    end)
end
