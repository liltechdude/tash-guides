-- TashGuides tracker.lua: quest tracker with objective progress, distances and waypoints.
-- Built from the same pieces as the guide window (branded header, goal icons, progress
-- colors) and grouped by how each quest relates to the guide:
--   GUIDE STEP   quests the guide's current step is working on (accent edge)
--   THIS ZONE    other quests with something to do on your map, nearest first
--   ELSEWHERE    the rest
-- Click: waypoint. Shift: link. Ctrl: quest log. Right-click: hide.

local TG = TashGuides
local QL, DB, WP, Guide, UI = TG.QuestLog, TG.DB, TG.Way, TG.Guide, TG.UI
local T = {}
TG.Tracker = T

local WIDTH = 270
local PAD = 8
local ICON = 14
local frame, header, content, toggle
local rows, rowCount = {}, 0
local labels, labelCount = {}, 0
local collapsed = false

local function questTarget(id)
    local q = QL.Get(id)
    if not q then return nil end
    local pts
    if q.complete then
        pts = {}
        for _, g in ipairs(DB.Finishers(id)) do for _, p in ipairs(g.points) do pts[#pts + 1] = p end end
    else
        return WP.PickSpawn(Guide.ObjectivePoints(id))
    end
    return WP.Nearest(pts)
end

local function onRowClick(self, button)
    local id = self.quest
    if not id then return end
    if button == "RightButton" then
        TG.char.untracked[id] = true
        TG.Print("hid %s from the tracker (show it again from the options)", QL.Get(id) and QL.Get(id).title or id)
        T.Refresh()
        return
    end
    if IsShiftKeyDown() and ChatEdit_InsertLink and GetQuestLink then
        local ok, link = pcall(GetQuestLink, id)
        if ok and type(link) == "string" and ChatEdit_InsertLink(link) then return end
    end
    if IsControlKeyDown() then
        local q = QL.Get(id)
        if QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(id)
        elseif q and q.index and QuestLogFrame and SelectQuestLogEntry then
            ShowUIPanel(QuestLogFrame)
            SelectQuestLogEntry(q.index)
            if QuestLog_Update then QuestLog_Update() end
        end
        return
    end
    local p = questTarget(id)
    local q = QL.Get(id)
    if p then
        WP.Set({ map = p.map, x = p.x, y = p.y, source = "tracker", quest = id, objective = not (q and q.complete) or nil,
            title = (q and q.title or "Quest") .. (q and q.complete and " (turn in)" or ""),
            subtitle = p.dungeon and (p.dungeon .. " entrance") or nil })
    else
        TG.Print("no known location for that quest")
    end
end

local function rowTooltip(self)
    if not self.quest then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local q = QL.Get(self.quest)
    GameTooltip:AddLine(q and q.title or "?", TG.C.gold[1], TG.C.gold[2], TG.C.gold[3])
    if self.guide then GameTooltip:AddLine("Part of the current guide step", TG.C.accent[1], TG.C.accent[2], TG.C.accent[3]) end
    local chain = TG.Chains.Kind(self.quest)
    if chain then GameTooltip:AddLine(chain == "class" and "Class quest" or "Racial quest", TG.C.repeatable[1], TG.C.repeatable[2], TG.C.repeatable[3]) end
    local texts = DB.Quest(self.quest, "objectivesText")
    if type(texts) == "table" then for _, s in ipairs(texts) do GameTooltip:AddLine(s, 1, 1, 1, true) end end
    local f = DB.GiverName(DB.Finishers(self.quest))
    if f then GameTooltip:AddDoubleLine("Turn in to", f, 0.6, 0.6, 0.6, 1, 1, 1) end
    GameTooltip:AddLine("Click: waypoint   Shift: link   Ctrl: quest log   Right-click: hide", 0.25, 0.85, 0.6, true)
    GameTooltip:Show()
end

local function acquire(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.edge = r:CreateTexture(nil, "BORDER")
    r.edge:SetPoint("TOPLEFT", -PAD + 2, 0)
    r.edge:SetPoint("BOTTOMLEFT", -PAD + 2, 0)
    r.edge:SetWidth(2)
    r.edge:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("TOPLEFT", 0, -1)
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(ICON + 2, ICON + 2)
    r.check:SetPoint("CENTER", r.icon, "CENTER", 1, 0)
    r.check:SetTexture(TG.TEX.check)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetJustifyV("TOP")
    r.text:SetWordWrap(true)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.right:SetPoint("TOPRIGHT", 0, -1)
    r.right:SetJustifyH("RIGHT")
    r.barBg = r:CreateTexture(nil, "BACKGROUND")
    r.barBg:SetHeight(2)
    r.barBg:SetPoint("BOTTOMLEFT", ICON + 5, 0)
    r.barBg:SetPoint("BOTTOMRIGHT", 0, 0)
    r.barBg:SetColorTexture(1, 1, 1, 0.08)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetHeight(2)
    r.bar:SetPoint("BOTTOMLEFT", r.barBg, "BOTTOMLEFT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r:SetScript("OnClick", onRowClick)
    r:SetScript("OnEnter", rowTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

-- kind: "quest" | "objective" | "note"
local function addRow(y, kind, text, opts)
    rowCount = rowCount + 1
    local r = acquire(rowCount)
    opts = opts or {}
    local indent = kind == "objective" and 18 or 0
    local w = WIDTH - PAD * 2 - indent
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
    r:SetWidth(w)
    r.quest, r.guide = opts.quest, opts.guide
    r:EnableMouse(opts.quest ~= nil)
    r.text:SetFontObject(kind == "quest" and "GameFontHighlight" or "GameFontHighlightSmall")
    r.text:SetWidth(w - ICON - 6 - (opts.right and 46 or 0))
    r.text:SetText(text)
    r.right:SetText(opts.right or "")
    r.edge:SetShown(kind == "quest" and opts.guide == true)
    if opts.icon then
        r.icon:SetTexture(opts.icon)
        local c = opts.iconColor
        if c then r.icon:SetVertexColor(c[1], c[2], c[3]) else r.icon:SetVertexColor(1, 1, 1) end
        r.icon:SetSize(opts.iconSize or ICON, opts.iconSize or ICON)
        r.icon:SetDesaturated(opts.done or false)
        r.icon:SetAlpha(opts.done and 0.5 or 1)
        r.icon:Show()
    else
        r.icon:Hide()
    end
    r.check:SetShown(opts.done == true)
    r.text:SetAlpha(opts.done and kind == "objective" and 0.6 or 1)
    local barH = 0
    if opts.fraction then
        local bw = w - ICON - 5
        r.bar:SetWidth(math.max(1, bw * opts.fraction))
        local c = opts.fraction >= 1 and TG.C.good or TG.C.accent
        r.bar:SetColorTexture(c[1], c[2], c[3], 0.8)
        r.bar:Show()
        r.barBg:Show()
        barH = 4
    else
        r.bar:Hide()
        r.barBg:Hide()
    end
    local h = math.max(ICON + 2, r.text:GetStringHeight() + 2) + barH
    r:SetHeight(h)
    r:Show()
    return y + h + 2
end

local function addLabel(y, text)
    labelCount = labelCount + 1
    local l = labels[labelCount]
    if not l then
        l = UI.SectionLabel(content)
        labels[labelCount] = l
    end
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 2))
    l:SetWidth(WIDTH - PAD * 2)
    l.text:SetText(text)
    l:Show()
    return y + 19
end

local function renderQuest(y, q, guideKind)
    local status = ""
    if q.failed then status = " " .. TG.Color(TG.C.bad, "(failed)")
    elseif q.complete then status = " " .. TG.Color(TG.C.good, "(ready)") end
    local chain = TG.Chains.Kind(q.id)
    local tag = chain and (" " .. TG.Color(TG.C.repeatable, chain == "class" and "[class]" or "[racial]")) or ""
    local icon, color = TG.TEX.dot, TG.QuestColor(q.level)
    if q.complete then icon, color = TG.TEX.turnin, TG.C.turnin end
    y = addRow(y, "quest", TG.Color(TG.QuestColor(q.level), ("[%d] %s"):format(q.level or 0, q.title)) .. tag .. status, {
        quest = q.id, guide = guideKind ~= nil, icon = icon, iconColor = color,
        right = q.dist and TG.FormatDistance(q.dist) or nil,
        fraction = (not q.complete and #(q.objectives or {}) > 0) and UI.QuestFraction(q) or nil,
    })
    if q.complete then
        local f = DB.GiverName(DB.Finishers(q.id))
        y = addRow(y, "objective", TG.Color(TG.C.gold, "Turn in" .. (f and (" to " .. f) or "")), { quest = q.id })
    else
        for _, o in ipairs(q.objectives or {}) do
            y = addRow(y, "objective", TG.Color(UI.ProgressColor(o), o.text ~= "" and o.text or "objective"),
                { quest = q.id, done = o.finished })
        end
    end
    return y + 4
end

function T.Refresh()
    if not frame then return end
    local db = TG.db.tracker
    if not db.shown then frame:Hide() return end
    frame:SetScale(db.scale)
    frame:SetBackdropColor(TG.C.bg[1], TG.C.bg[2], TG.C.bg[3], db.alpha or 0.85)

    for i = 1, rowCount do rows[i]:Hide() end
    for i = 1, labelCount do labels[i]:Hide() end
    rowCount, labelCount = 0, 0

    local pmap = WP.PlayerMap()
    local inGuide = Guide.active and Guide.CurrentQuests() or {}
    local groups = { guide = {}, here = {}, away = {} }
    local total = 0
    for id, q in pairs(QL.quests) do
        if not TG.char.untracked[id] then
            local p, d = questTarget(id)
            q.dist = d
            q.onMap = (pmap and p and p.map == pmap) and true or false
            local g = inGuide[id] and "guide" or (q.onMap and "here" or "away")
            local list = groups[g]
            list[#list + 1] = q
            total = total + 1
        end
    end
    local function byDistance(a, b)
        if (a.dist or 1e9) ~= (b.dist or 1e9) then return (a.dist or 1e9) < (b.dist or 1e9) end
        return a.title < b.title
    end
    for _, list in pairs(groups) do table.sort(list, byDistance) end

    local maxQ = 0
    if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then maxQ = C_QuestLog.GetMaxNumQuestsCanAccept() end
    if (not maxQ or maxQ == 0) and MAX_QUESTLOG_QUESTS then maxQ = MAX_QUESTLOG_QUESTS end
    header:SetLabel(TG.Color(TG.C.gold, "Quests") .. "  " .. TG.Color(TG.C.muted,
        (QL.count or total) .. ((maxQ and maxQ > 0) and ("/" .. maxQ) or "")))
    toggle.icon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")

    local y = 0
    if not collapsed then
        local shown = 0
        local sections = {
            { key = "guide", label = "GUIDE STEP" },
            { key = "here", label = "THIS ZONE" },
            { key = "away", label = "ELSEWHERE" },
        }
        for _, sec in ipairs(sections) do
            local list = groups[sec.key]
            if #list > 0 and shown < db.max then
                y = addLabel(y, sec.label)
                for _, q in ipairs(list) do
                    if shown >= db.max then break end
                    shown = shown + 1
                    y = renderQuest(y, q, sec.key == "guide" and inGuide[q.id] or nil)
                end
            end
        end
        local hidden = 0
        for id in pairs(TG.char.untracked) do if QL.InLog(id) then hidden = hidden + 1 end end
        local more = total - shown
        local notes = {}
        if more > 0 then notes[#notes + 1] = more .. " more" end
        if hidden > 0 then notes[#notes + 1] = hidden .. " hidden" end
        if #notes > 0 then y = addRow(y, "note", TG.Color(TG.C.muted, table.concat(notes, "  -  "))) end
        if total == 0 and hidden == 0 then y = addRow(y, "note", TG.Color(TG.C.muted, "Your quest log is empty.")) end
    end
    content:SetShown(not collapsed)
    content:SetHeight(math.max(y, 1))
    frame:SetHeight(UI.HEADER_H + 2 + (collapsed and 0 or y + 8))
    frame:Show()
end

-- Blizzard's tracker (ObjectiveTrackerFrame on this client) holds secure quest-item buttons,
-- so it is only shown/hidden out of combat.
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function wantBlizzardHidden() return TG.db.tracker.hideBlizzard and TG.db.tracker.shown end

local function applyBlizzard()
    local watch = _G.ObjectiveTrackerFrame or _G.QuestWatchFrame
    if not watch then return end
    if inCombat() then
        T.pendingBlizzard = true
        return
    end
    T.pendingBlizzard = false
    if wantBlizzardHidden() then
        if not watch.tgHooked then
            watch.tgHooked = true
            watch:HookScript("OnShow", function(self)
                if not wantBlizzardHidden() then return end
                -- Blizzard re-shows it whenever objectives update, which mostly happens mid-fight.
                -- Hiding it then is blocked, so finish the job as soon as combat ends.
                if inCombat() then T.pendingBlizzard = true else self:Hide() end
            end)
        end
        T.blizzardHidden = true
        if watch:IsShown() then watch:Hide() end
    elseif T.blizzardHidden then
        -- only undo our own hide; Blizzard hides its tracker itself when it is empty
        T.blizzardHidden = false
        if not watch:IsShown() then watch:Show() end
    end
end
TG.On("PLAYER_REGEN_ENABLED", function()
    if T.pendingBlizzard then applyBlizzard() end
end)

function T.Init()
    frame = CreateFrame("Frame", "TashGuidesTracker", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(WIDTH, 60)
    frame:SetFrameStrata("LOW")
    TG.Skin(frame, TG.db.tracker.alpha)
    TG.RestorePosition(frame, "tracker", "TOPRIGHT", "TOPRIGHT", -40, -240)
    TG.MakeMovable(frame, "tracker", function() return TG.db.tracker.locked end)

    header = UI.Header(frame)
    header:AddButton("Interface\\Buttons\\UI-StopButton", 14, "Hide (/tg tracker to show)", function()
        TG.db.tracker.shown = false
        TG.Fire("TG_SETTINGS")
    end)
    toggle = header:AddButton("Interface\\Buttons\\UI-MinusButton-Up", 14, "Collapse", function()
        collapsed = not collapsed
        T.Refresh()
    end)

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD, -4)
    content:SetWidth(WIDTH - PAD * 2)
    content:SetHeight(1)

    TG.On("TG_QUESTLOG", function() TG.Schedule("tracker", 0.1, T.Refresh) end)
    TG.On("TG_GUIDE", function() TG.Schedule("tracker", 0.2, T.Refresh) end)
    TG.On("TG_SETTINGS", function() applyBlizzard() T.Refresh() end)
    TG.On("ZONE_CHANGED_NEW_AREA", function() TG.Schedule("tracker", 0.5, T.Refresh) end)
    -- distances drift as you move
    C_Timer.NewTicker(2, function() if frame:IsShown() and not collapsed then T.Refresh() end end)
    applyBlizzard()
    T.Refresh()
end
