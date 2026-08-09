-- AscensionSuite: ui/NativeChrome.lua
-- Shared DialogFrame / parchment / OptionsFrame-style chrome used by Assists,
-- Wishlist, and Loadouts so every /asuite tab speaks the same WotLK language.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local NativeChrome = {}
AscensionSuite.NativeChrome = NativeChrome

NativeChrome.TOOLTIP_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

NativeChrome.TOOLTIP_BACKDROP_TIGHT = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Ink / gold palette matching docs/sketch/ascension-suite-native-wotlk-layout-mockup.html
NativeChrome.INK_TITLE = { 0.30, 0.20, 0.04, 1 }
NativeChrome.INK_BODY = { 0.20, 0.14, 0.06, 1 }
NativeChrome.INK_SOFT = { 0.28, 0.22, 0.12, 1 }
NativeChrome.INK_MUTED = { 0.35, 0.28, 0.18, 1 }
NativeChrome.INK_ROW = { 0.12, 0.08, 0.02, 1 }
NativeChrome.INK_ROW_DIM = { 0.42, 0.36, 0.26, 1 }
NativeChrome.GOLD = { 0.78, 0.62, 0.24, 1 }
NativeChrome.GOLD_BRIGHT = { 1.00, 0.82, 0.20, 1 }
NativeChrome.DESIRED = { 0.12, 0.29, 0.44, 1 }
NativeChrome.UNDESIRED = { 0.42, 0.24, 0.06, 1 }
NativeChrome.KNOWN = { 0.12, 0.42, 0.22, 1 }
NativeChrome.OK = { 0.15, 0.45, 0.22, 1 }
NativeChrome.WARN = { 0.82, 0.62, 0.22, 1 }
NativeChrome.BAD = { 0.72, 0.22, 0.18, 1 }
NativeChrome.GROUP = { 0.30, 0.42, 0.14, 1 }

local function ApplyBackdrop(frame, template, r, g, b, a, br, bg, bb, ba)
    if type(frame) ~= "table" or type(frame.SetBackdrop) ~= "function" then
        return false
    end
    frame:SetBackdrop(template)
    if frame.SetBackdropColor then
        frame:SetBackdropColor(r, g, b, a)
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(br, bg, bb, ba)
    end
    return true
end

function NativeChrome.ApplyParchment(frame)
    return ApplyBackdrop(frame, NativeChrome.TOOLTIP_BACKDROP,
        0.78, 0.70, 0.50, 0.92,
        0.45, 0.35, 0.14, 1)
end

function NativeChrome.ApplySidebar(frame)
    return ApplyBackdrop(frame, NativeChrome.TOOLTIP_BACKDROP,
        0.12, 0.09, 0.04, 0.95,
        0.45, 0.35, 0.14, 1)
end

function NativeChrome.ApplyInsetList(frame)
    return ApplyBackdrop(frame, NativeChrome.TOOLTIP_BACKDROP,
        0.95, 0.90, 0.72, 0.55,
        0.55, 0.45, 0.18, 0.9)
end

function NativeChrome.ApplyToggleRow(frame)
    return ApplyBackdrop(frame, NativeChrome.TOOLTIP_BACKDROP_TIGHT,
        0.95, 0.90, 0.72, 0.55,
        0.55, 0.45, 0.18, 0.9)
end

function NativeChrome.ApplyNavButton(frame, selected)
    ApplyBackdrop(frame, NativeChrome.TOOLTIP_BACKDROP_TIGHT,
        selected and 0.85 or 0.22,
        selected and 0.70 or 0.16,
        selected and 0.28 or 0.08,
        selected and 1 or 0.95,
        selected and 0.94 or 0.45,
        selected and 0.82 or 0.35,
        selected and 0.38 or 0.14,
        1)
    return true
end

function NativeChrome.SetFontColor(fs, rgba)
    if type(fs) ~= "table" or type(fs.SetTextColor) ~= "function" or type(rgba) ~= "table" then
        return
    end
    fs:SetTextColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
end
