-- TashGuides options.lua: settings window, Settings-panel entry and minimap button.

local TG = TashGuides
local O = {}
TG.Options = O

local window
local controls = {}

local function changed()
    TG.Fire("TG_SETTINGS")
    if TG.Pins then TG.Pins.Invalidate() end
end

-- path "pins.world" -> table, key
local function resolve(path)
    local t, key = TG.db, path
    for part, rest in path:gmatch("([^%.]+)%.(.+)") do
        t, key = t[part], rest
    end
    return t, key
end

local function checkbox(parent, x, y, label, path, tip, onSet)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    fs:SetText(label)
    cb.label = fs
    for _, key in ipairs({ "text", "Text" }) do
        local fs = rawget(cb, key)
        if type(fs) == "table" and fs.SetText then fs:SetText("") end
    end
    cb:SetScript("OnClick", function(self)
        local t, k = resolve(path)
        t[k] = self:GetChecked() and true or false
        if onSet then onSet(t[k]) end
        changed()
    end)
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
    end
    cb.Sync = function(self) local t, k = resolve(path) self:SetChecked(t[k] and true or false) end
    controls[#controls + 1] = cb
    return cb
end

local function slider(parent, x, y, label, path, minV, maxV, step, fmt)
    local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(150, 14)
    s:SetPoint("TOPLEFT", x + 4, y - 16)
    if s.SetBackdrop then
        s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local fs = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("BOTTOMLEFT", s, "TOPLEFT", -2, 2)
    s.label = fs
    local function show(v) fs:SetText(label .. ": " .. TG.Color(TG.C.gold, (fmt or "%.2f"):format(v))) end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        local t, k = resolve(path)
        show(v)
        if t[k] ~= v then
            t[k] = v
            changed()
        end
    end)
    s.Sync = function(self) local t, k = resolve(path) self:SetValue(t[k]) show(t[k]) end
    controls[#controls + 1] = s
    return s
end

local function heading(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    line:SetSize(210, 1)
    line:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.5)
    return fs
end

local function build()
    window = CreateFrame("Frame", "TashGuidesOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    window:SetSize(500, 620)
    window:SetFrameStrata("DIALOG")
    window:SetPoint("CENTER")
    TG.Skin(window, 0.97)
    window:SetBackdropBorderColor(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.8)
    TG.MakeMovable(window, "options")
    window:Hide()
    tinsert(UISpecialFrames, "TashGuidesOptions")

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(TG.UI.BRAND .. "  " .. TG.Color(TG.C.muted, "v" .. TG.VERSION))
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local L, R = 14, 262
    local y = -44
    heading(window, L, y, "Guide window")
    checkbox(window, L, y - 18, "Show guide window", "viewer.shown")
    checkbox(window, L, y - 40, "Lock position", "viewer.locked")
    checkbox(window, L, y - 62, "Advance steps automatically", "autoAdvance", "Move to the next step as soon as every goal of the current one is done.")
    local chains = checkbox(window, L, y - 84, "Include class & race quests", "includeChains",
        "Class trainer and racial quest chains inside the main guides (zone guides and the Smart Guide). They are also available as their own guides from the guide picker.")
    chains:SetScript("OnClick", function(self) TG.Guide.SetChainsIncluded(self:GetChecked() and true or false) end)
    checkbox(window, L, y - 106, "Sounds", "sounds")
    slider(window, L, y - 130, "Upcoming steps shown", "viewer.upcoming", 0, 5, 1, "%d")
    slider(window, L, y - 168, "Scale", "viewer.scale", 0.6, 1.6, 0.05)
    slider(window, L, y - 206, "Opacity", "viewer.alpha", 0.2, 1, 0.05)

    heading(window, R, y, "Arrow")
    checkbox(window, R, y - 18, "Show waypoint arrow", "arrow.shown")
    checkbox(window, R, y - 40, "Lock position", "arrow.locked")
    slider(window, R, y - 64, "Scale", "arrow.scale", 0.5, 2, 0.05)
    slider(window, R, y - 102, "Arrival distance (yd)", "arrow.arrival", 3, 30, 1, "%d")
    slider(window, R, y - 140, "Prefer spawns ahead of you", "arrow.forwardBias", 0, 5, 0.5, "%.1f")

    heading(window, R, y - 184, "Quest tracker")
    checkbox(window, R, y - 202, "Show quest tracker", "tracker.shown")
    checkbox(window, R, y - 224, "Lock position", "tracker.locked")
    checkbox(window, R, y - 246, "Hide Blizzard's quest tracker", "tracker.hideBlizzard")
    slider(window, R, y - 270, "Quests shown", "tracker.max", 3, 25, 1, "%d")
    slider(window, R, y - 308, "Scale", "tracker.scale", 0.6, 1.6, 0.05)
    slider(window, R, y - 346, "Opacity", "tracker.alpha", 0.2, 1, 0.05)

    y = -300
    heading(window, L, y, "Map pins")
    checkbox(window, L, y - 18, "World map", "pins.world")
    checkbox(window, L + 110, y - 18, "Minimap", "pins.minimap")
    checkbox(window, L, y - 40, "Quests to pick up (!)", "pins.available")
    checkbox(window, L, y - 62, "Objectives (dots)", "pins.objectives")
    checkbox(window, L, y - 84, "Turn-ins (?)", "pins.turnins")
    checkbox(window, L, y - 106, "Low-level quests", "pins.trivial", "Grey quests that give little experience.")
    checkbox(window, L, y - 128, "Repeatable quests", "pins.repeatable")
    checkbox(window, L, y - 150, "Profession quests", "pins.profession")
    slider(window, L, y - 174, "World map pin size", "pins.scale", 0.5, 2, 0.05)
    slider(window, L, y - 212, "Minimap pin size", "pins.minimapScale", 0.5, 2, 0.05)

    local qy = y - 132
    heading(window, R, qy, "Quests")
    checkbox(window, R, qy - 18, "Quest info on tooltips", "tooltips", "Show your objectives and available quests when you hover NPCs and objects.")
    checkbox(window, R, qy - 40, "Auto-accept quests", "autoAccept", "Accept quests as soon as an NPC offers them. Hold Shift to skip.")
    checkbox(window, R, qy - 62, "Auto turn-in quests", "autoTurnIn", "Hand in finished quests automatically. Quests with a reward choice wait for you. Hold Shift to skip.")
    checkbox(window, R, qy - 84, "Minimap button", "minimap.hide", nil, function() O.UpdateMinimapButton() end)
    -- minimap.hide is stored inverted; the box shows "visible"
    local mm = controls[#controls]
    mm:SetScript("OnClick", function(self)
        TG.db.minimap.hide = not self:GetChecked()
        O.UpdateMinimapButton()
    end)
    mm.Sync = function(self) self:SetChecked(not TG.db.minimap.hide) end

    local unhide = TG.UI.TextButton(window, "Show hidden tracker quests", 210, function()
        wipe(TG.char.untracked)
        changed()
    end)
    unhide:SetPoint("TOPLEFT", R, qy - 114)
    local pick = TG.UI.TextButton(window, "Choose guide...", 210, function() window:Hide() TG.Viewer.ShowPicker() end)
    pick:SetPoint("TOPLEFT", R, qy - 140)

    local help = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("BOTTOMLEFT", 14, 12)
    help:SetPoint("BOTTOMRIGHT", -14, 12)
    help:SetJustifyH("LEFT")
    help:SetText("/tg toggles the guide  -  /tg way 45 60 sets a waypoint  -  /tg help for all commands")

    window:SetScript("OnShow", function() for _, c in ipairs(controls) do c:Sync() end end)
end

function O.Toggle()
    if not window then build() end
    window:SetShown(not window:IsShown())
end

-- Settings panel stub that opens the window.
local function registerSettings()
    local panel = CreateFrame("Frame")
    panel.name = "TashGuides"
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("TashGuides")
    local b = TG.UI.TextButton(panel, "Open TashGuides options", 200, function()
        if SettingsPanel and SettingsPanel:IsShown() and SettingsPanel.Close then SettingsPanel:Close(true) end
        O.Toggle()
    end)
    b:SetPoint("TOPLEFT", 16, -50)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "TashGuides")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------

local mmButton

local function positionButton()
    local angle = math.rad(TG.db.minimap.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 8
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

function O.UpdateMinimapButton()
    if not mmButton then return end
    mmButton:SetShown(not TG.db.minimap.hide)
    positionButton()
end

local function buildMinimapButton()
    mmButton = CreateFrame("Button", "TashGuidesMinimapButton", Minimap)
    mmButton:SetSize(31, 31)
    mmButton:SetFrameStrata("MEDIUM")
    mmButton:SetFrameLevel(8)
    mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mmButton:RegisterForDrag("LeftButton")
    mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = mmButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture(TG.TEX.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = mmButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    mmButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then O.Toggle()
        elseif IsShiftKeyDown() then
            TG.db.tracker.shown = not TG.db.tracker.shown
            TG.Fire("TG_SETTINGS")
        else
            TG.db.viewer.shown = not TG.db.viewer.shown
            TG.Fire("TG_SETTINGS")
        end
    end)
    mmButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            TG.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            positionButton()
        end)
    end)
    mmButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff33b8ffTash|cffffd100Guides|r")
        GameTooltip:AddLine("Click: guide window", 1, 1, 1)
        GameTooltip:AddLine("Shift-click: quest tracker", 1, 1, 1)
        GameTooltip:AddLine("Right-click: options", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    mmButton:SetScript("OnLeave", GameTooltip_Hide)
    O.UpdateMinimapButton()
end

function O.Init()
    registerSettings()
    buildMinimapButton()
end
