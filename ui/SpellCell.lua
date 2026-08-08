-- AscensionSuite: ui/SpellCell.lua
-- Shared spell present: icon + id label, tooltip 1:1 from AscensionAPI.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local SpellCell = {}
AscensionSuite.SpellCell = SpellCell

local CELL_SIZE = 64

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function GetWishlist()
    return AscensionSuite.Wishlist
end

function SpellCell.Create(parent, name)
    local frame = CreateFrame("Button", name, parent)
    frame:SetSize(CELL_SIZE, CELL_SIZE)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.08, 0.12, 0.16, 0.95)

    local border = frame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetTexture(0.42, 0.54, 0.66, 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 16)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local tagLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tagLabel:SetPoint("TOPRIGHT", -2, -2)
    tagLabel:SetTextColor(0.29, 0.66, 0.91, 1)
    tagLabel:Hide()

    local idLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    idLabel:SetPoint("BOTTOMLEFT", 2, 2)
    idLabel:SetPoint("BOTTOMRIGHT", -2, 2)
    idLabel:SetJustifyH("CENTER")
    idLabel:SetTextColor(0.8, 0.88, 0.95, 1)

    frame._icon = icon
    frame._idLabel = idLabel
    frame._border = border
    frame._tagLabel = tagLabel
    frame._spellId = nil
    frame._onChanged = nil

    frame:SetScript("OnEnter", function(self)
        local api = GetAPI()
        if not api then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        local lines = api.GetEntryTooltipLines(self._spellId)
        for index = 1, #lines do
            if index == 1 then
                GameTooltip:SetText(lines[index], 1, 0.82, 0.3)
            else
                GameTooltip:AddLine(lines[index], 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)

    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:SetScript("OnClick", function(self)
        local wishlist = GetWishlist()
        if not wishlist or not self._spellId then
            return
        end

        if wishlist.IsDesired(self._spellId) then
            wishlist.RemoveFromDesired(self._spellId)
        else
            wishlist.AddToDesired(self._spellId)
        end
        self:RefreshDesired()

        if type(self._onChanged) == "function" then
            self._onChanged(self)
        end
    end)

    function frame:RefreshDesired()
        local wishlist = GetWishlist()
        if not wishlist or not self._spellId then
            return
        end

        local desired = wishlist.IsDesired(self._spellId)
        if desired then
            self._border:SetTexture(74 / 255, 168 / 255, 232 / 255, 1)
            self._tagLabel:SetText("D")
            self._tagLabel:Show()
        else
            self._border:SetTexture(106 / 255, 138 / 255, 168 / 255, 1)
            self._tagLabel:Hide()
        end
    end

    function frame:SetOnChanged(callback)
        self._onChanged = callback
    end

    function frame:SetSpell(spellId)
        local id = tonumber(spellId)
        self._spellId = id

        local api = GetAPI()
        if not api or not id then
            self._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            self._idLabel:SetText(id and tostring(id) or "?")
            self:RefreshDesired()
            return
        end

        self._icon:SetTexture(api.GetEntryIcon(id))
        self._idLabel:SetText(tostring(id))
        self:RefreshDesired()
    end

    function frame:GetSpellId()
        return self._spellId
    end

    return frame
end
