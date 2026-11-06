-- TashGuides ui.lua: widgets shared by every TashGuides window (guide, steps, tracker,
-- options) so they all look and behave the same: branded header, icon/text buttons,
-- section labels and progress colors.

local TG = TashGuides
local UI = {}
TG.UI = UI

UI.BRAND = "|cff33b8ffTash|r|cffffd100Guides|r"
UI.HEADER_H = 24

function UI.IconButton(parent, texture, size, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(texture)
    if texture:find("Icons") then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b.icon = t
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local text = type(tip) == "function" and tip(self) or tip
            if type(text) == "table" then
                GameTooltip:AddLine(text[1], 1, 1, 1)
                for i = 2, #text do GameTooltip:AddLine(text[i], 0.8, 0.8, 0.8, true) end
            else
                GameTooltip:SetText(text, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    return b
end

function UI.TextButton(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    b:SetSize(width, 20)
    TG.Skin(b, 0.9)
    b:SetBackdropBorderColor(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.6)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(label)
    b.text = fs
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.2)
    b:SetScript("OnClick", onClick)
    return b
end

-- The header strip every window starts with: arrow logo, "TashGuides", a muted context
-- label (guide name, "Quests 5/20", ...) and room for icon buttons on the right.
-- Buttons added with header:AddButton are laid out right to left.
function UI.Header(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(UI.HEADER_H)
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(TG.C.accent[1] * 0.25, TG.C.accent[2] * 0.25, TG.C.accent[3] * 0.25, 0.9)
    local line = header:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.8)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 5, 0)
    logo:SetTexture(TG.TEX.arrow)
    logo:SetVertexColor(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3])
    header.logo = logo

    local brand = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    brand:SetPoint("LEFT", logo, "RIGHT", 4, 0)
    brand:SetText(UI.BRAND)
    header.brand = brand

    local sep = header:CreateTexture(nil, "ARTWORK")
    sep:SetSize(1, 12)
    sep:SetPoint("LEFT", brand, "RIGHT", 6, 0)
    sep:SetColorTexture(TG.C.muted[1], TG.C.muted[2], TG.C.muted[3], 0.6)

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", sep, "RIGHT", 6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    header.label = label

    header.buttons = {}
    function header:AddButton(texture, size, tip, onClick)
        local b = UI.IconButton(self, texture, size, tip, onClick)
        local prev = self.buttons[#self.buttons]
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", -5, 0) end
        self.buttons[#self.buttons + 1] = b
        label:SetPoint("RIGHT", b, "LEFT", -6, 0)
        return b
    end
    function header:SetLabel(text) label:SetText(text or "") end
    return header
end

-- Small uppercase section label with an accent rule, used inside lists.
function UI.SectionLabel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(14)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("LEFT", 0, 0)
    f.text:SetTextColor(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3])
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetHeight(1)
    f.rule:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
    f.rule:SetPoint("RIGHT", 0, 0)
    f.rule:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.3)
    return f
end

-- Objective color by progress: red -> yellow while counting, green when finished.
function UI.ProgressColor(o)
    if o.finished then return TG.C.good end
    if o.have and o.need and o.need > 0 then
        local f = o.have / o.need
        return { 1, 0.35 + 0.55 * f, 0.3 }
    end
    return { 0.9, 0.9, 0.9 }
end

-- Fraction of a quest's objectives done (0..1).
function UI.QuestFraction(q)
    if not q then return 0 end
    if q.complete then return 1 end
    local objs = q.objectives or {}
    if #objs == 0 then return 0 end
    local sum = 0
    for _, o in ipairs(objs) do
        if o.finished then sum = sum + 1
        elseif o.have and o.need and o.need > 0 then sum = sum + math.min(1, o.have / o.need) end
    end
    return sum / #objs
end

-- Strip color codes for tooltips and waypoint titles.
function UI.Plain(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Place `panel` beside `anchor`, on whichever side has room.
function UI.Beside(panel, anchor, width)
    panel:ClearAllPoints()
    local x = anchor:GetRight() or 0
    if x + width + 10 > (UIParent:GetWidth() or 0) then
        panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
    else
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    end
end
