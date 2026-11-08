-- TashGuides viewer.lua: the step-by-step guide window and the guide picker.

local TG = TashGuides
local Guide, QL, DB, WP = TG.Guide, TG.QuestLog, TG.DB, TG.Way
local V = {}
TG.Viewer = V

local WIDTH = 360
local PAD = 8
local ICON = 14

local frame, header, stepBar, stepLabel, body, footer, bar, barText, chainBtn
local rows, rowCount = {}, 0
local picker

-- ---------------------------------------------------------------------------
-- Small widgets
-- ---------------------------------------------------------------------------

local iconButton, textButton = TG.UI.IconButton, TG.UI.TextButton
V.IconButton, V.TextButton = iconButton, textButton

-- ---------------------------------------------------------------------------
-- Goal rows (pooled)
-- ---------------------------------------------------------------------------

local GOAL_ICON = {
    accept = TG.TEX.available, turnin = TG.TEX.turnin, complete = TG.TEX.dot,
    ["goto"] = TG.TEX.target, talk = TG.TEX.talk, level = TG.TEX.level,
    hearth = TG.TEX.hearth, fly = TG.TEX.target, note = TG.TEX.dot,
}

local function goalTooltip(row)
    local goal = row.goal
    if not goal then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if goal.quest then
        local q = goal.quest
        GameTooltip:AddLine(DB.QuestName(q) or ("Quest " .. q), TG.C.gold[1], TG.C.gold[2], TG.C.gold[3])
        GameTooltip:AddLine(("Level %d  (requires %d)"):format(DB.QuestLevel(q), DB.Quest(q, "requiredLevel") or 1), 0.8, 0.8, 0.8)
        local texts = DB.Quest(q, "objectivesText")
        if type(texts) == "table" then
            for _, line in ipairs(texts) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        local s, f = DB.GiverName(DB.Starters(q)), DB.GiverName(DB.Finishers(q))
        if s then GameTooltip:AddDoubleLine("Starts", s, 0.6, 0.6, 0.6, 1, 1, 1) end
        if f then GameTooltip:AddDoubleLine("Ends", f, 0.6, 0.6, 0.6, 1, 1, 1) end
    else
        GameTooltip:AddLine((Guide.GoalText(goal):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), 1, 1, 1, true)
    end
    if row.hasLocation then GameTooltip:AddLine("Click: point the arrow here", 0.25, 0.85, 0.6) end
    if row.manual then GameTooltip:AddLine("Right-click: mark done / not done", 0.25, 0.85, 0.6) end
    GameTooltip:Show()
end

local function acquireRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, body)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("TOPLEFT", 0, -1)
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(ICON + 4, ICON + 4)
    r.check:SetPoint("CENTER", r.icon, "CENTER", 1, 0)
    r.check:SetTexture(TG.TEX.check)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetJustifyV("TOP")
    r.text:SetWordWrap(true)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r:SetScript("OnEnter", goalTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self, button)
        if not self.goal then return end
        if button == "RightButton" then
            if self.manual then Guide.ToggleGoal(self.si, self.gi) end
            return
        end
        local wp = Guide.WaypointFor(self.si, self.gi, self.goal)
        if wp then
            wp.source = "pin"
            WP.Set(wp)
        end
    end)
    rows[i] = r
    return r
end

-- kind: "goal" | "detail" | "note" | "upcoming" | "message"
local function addRow(y, kind, text, opts)
    rowCount = rowCount + 1
    local r = acquireRow(rowCount)
    opts = opts or {}
    local indent = (kind == "detail" and 20) or 0
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", body, "TOPLEFT", indent, -y)
    r:SetWidth(WIDTH - PAD * 2 - indent)
    r.goal, r.si, r.gi, r.manual, r.hasLocation = opts.goal, opts.si, opts.gi, opts.manual, opts.hasLocation
    r:EnableMouse(opts.goal ~= nil)

    local font = (kind == "goal") and "GameFontHighlight" or "GameFontHighlightSmall"
    r.text:SetFontObject(font)
    r.text:SetWidth(WIDTH - PAD * 2 - indent - ICON - 6)
    r.text:SetText(text)

    if opts.icon then
        r.icon:SetTexture(opts.icon)
        local c = opts.iconColor
        if c then r.icon:SetVertexColor(c[1], c[2], c[3]) else r.icon:SetVertexColor(1, 1, 1) end
        r.icon:SetDesaturated(opts.done or false)
        r.icon:SetAlpha(opts.done and 0.5 or 1)
        r.icon:Show()
    else
        r.icon:Hide()
    end
    r.check:SetShown(opts.done == true)

    local alpha = 1
    if opts.done or kind == "upcoming" then alpha = 0.55 end
    r.text:SetAlpha(alpha)
    if kind == "note" then r.text:SetTextColor(TG.C.muted[1] + 0.15, TG.C.muted[2] + 0.15, TG.C.muted[3] + 0.1)
    elseif kind == "detail" then r.text:SetTextColor(0.85, 0.85, 0.85)
    else r.text:SetTextColor(1, 1, 1) end

    local h = math.max(ICON + 2, r.text:GetStringHeight() + 2)
    r:SetHeight(h)
    r:Show()
    return y + h + 3
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local objectiveColor = TG.UI.ProgressColor
local CHAIN_TAG = { class = "class", race = "racial" }

local function renderStep(si, y, isCurrent)
    local step = Guide.Steps()[si]
    if not step then return y end
    for gi, goal in ipairs(step.goals) do
        local status = Guide.GoalStatus(si, gi, goal)
        if status ~= "na" then
            local done = status == "done"
            local text = Guide.GoalText(goal)
            local blocked = not done and Guide.GoalBlocked(goal)
            if blocked then text = text .. " " .. TG.Color(TG.C.bad, "(" .. blocked .. ")") end
            if goal.optional and not done then text = text .. TG.Color(TG.C.muted, " (optional)") end
            local chain = goal.quest and TG.Chains.Kind(goal.quest)
            if chain and not (Guide.active and Guide.active.chain) then
                text = text .. " " .. TG.Color(TG.C.repeatable, "[" .. CHAIN_TAG[chain] .. "]")
            end
            local color = goal.type == "complete" and TG.C.monster or nil
            if goal.type == "accept" and goal.quest and DB.IsRepeatable(goal.quest) then color = TG.C.repeatable end
            local manual = not goal.quest and goal.type ~= "level" and goal.type ~= "note"
            y = addRow(y, status == "info" and "note" or "goal", text, {
                icon = GOAL_ICON[goal.type], iconColor = color, done = done,
                goal = goal, si = si, gi = gi, manual = manual,
                hasLocation = not done and Guide.GoalLocation(goal) ~= nil,
            })
            if isCurrent and not done then
                local details = Guide.GoalDetails(goal)
                if details then
                    for _, o in ipairs(details) do
                        y = addRow(y, "detail", TG.Color(objectiveColor(o), o.text ~= "" and o.text or "objective"), {})
                    end
                end
            end
        end
    end
    if step.note then y = addRow(y, "note", step.note, {}) end
    return y
end

function V.Refresh()
    if not frame then return end
    local db = TG.db.viewer
    frame:SetShown(db.shown)
    if not db.shown then return end
    frame:SetScale(db.scale)
    frame:SetBackdropColor(TG.C.bg[1], TG.C.bg[2], TG.C.bg[3], db.alpha)

    for i = 1, rowCount do rows[i]:Hide() end
    rowCount = 0

    local g = Guide.active
    local steps = Guide.Steps()
    local range = ""
    if g and not g.dynamic and g.minLevel then range = ("%d-%d"):format(g.minLevel, g.maxLevel or 60)
    elseif g and g.dynamic then range = "live" end
    header:SetLabel(g and (TG.Color(TG.C.gold, g.title) .. "  " .. TG.Color(TG.C.muted, range)) or TG.Color(TG.C.muted, "no guide"))
    V.UpdateChainButton()

    local si = Guide.view or Guide.cursor
    local finished = Guide.Finished()
    local done, total = Guide.Progress()

    local linear = g and g.dynamic and Guide.Ordered()
    if g and g.dynamic then
        local n = TG.Smart and TG.Smart.count or #steps
        if linear then
            stepLabel:SetText(TG.Color(TG.C.accent, "Route") .. TG.Color(TG.C.muted, ("  %d stop%s left"):format(n, n == 1 and "" or "s")))
        else
            stepLabel:SetText(TG.Color(TG.C.accent, "Nearest first") .. TG.Color(TG.C.muted, "  (" .. n .. ")"))
        end
    elseif finished then
        stepLabel:SetText(TG.Color(TG.C.good, "Guide complete"))
    else
        local step = steps[si]
        local label = ("Step %d/%d"):format(si, #steps)
        if Guide.view then
            label = label .. TG.Color(Guide.view < Guide.cursor and TG.C.muted or TG.C.accent,
                Guide.view < Guide.cursor and "  (done)" or "  (preview)")
        end
        if step and step.title then label = label .. "  " .. TG.Color(TG.C.gold, step.title) end
        stepLabel:SetText(label)
    end
    local smart = g and g.id == "SMART"
    stepBar.prev:SetShown(g and not g.dynamic)
    stepBar.next:SetShown(g and (not g.dynamic or linear))
    stepBar.mode:SetShown(smart and true or false)
    stepBar.mode.text:SetText(linear and "Linear" or "Nearest")
    stepLabel:ClearAllPoints()
    stepLabel:SetPoint("LEFT", smart and stepBar.mode or stepBar.prev, "RIGHT", smart and 6 or 2, 0)
    stepLabel:SetPoint("RIGHT", stepBar.next, "LEFT", -2, 0)

    local y = 0
    if db.minimized then
        body:Hide()
        stepBar:Hide()
        footer:Hide()
        frame:SetHeight(30)
        return
    end
    body:Show()
    stepBar:Show()
    footer:Show()

    if not g then
        y = addRow(y, "message", "No guide loaded. Click the book icon to choose one.", {})
    elseif finished then
        local nextDef = g.next and Guide.registry[g.next]
        y = addRow(y, "message", "You finished " .. TG.Color(TG.C.gold, g.title) .. "!" ..
            (nextDef and ("\nNext up: " .. TG.Color(TG.C.accent, nextDef.title) .. ". Press > to continue.") or ""), {})
    elseif g.dynamic then
        for i = 1, #steps do
            if i > 1 then y = y + 4 end
            local step = steps[i]
            if step.title and i > 1 then y = addRow(y, "note", step.title, {}) end
            y = renderStep(i, y, i == 1)
            if i >= 1 + (db.upcoming or 2) then break end
        end
    else
        if Guide.view then
            y = addRow(y, "note", TG.Color(TG.C.accent, ("Viewing step %d. Click the step bar to return to step %d."):format(si, Guide.cursor)), {})
        end
        y = renderStep(si, y, si == Guide.cursor)
        local shown, n = 0, si + 1
        while shown < (db.upcoming or 0) and n <= #steps do
            if Guide.StepStatus(n) ~= "na" then
                local step = steps[n]
                for gi, goal in ipairs(step.goals) do
                    if Guide.GoalStatus(n, gi, goal) ~= "na" then
                        y = addRow(y, "upcoming", Guide.GoalText(goal), { icon = GOAL_ICON[goal.type] })
                        break
                    end
                end
                shown = shown + 1
            end
            n = n + 1
        end
    end

    body:SetHeight(math.max(y, 10))
    if g and not g.dynamic and total > 0 then
        bar:SetMinMaxValues(0, total)
        bar:SetValue(done)
        barText:SetText(("%d / %d steps  -  %d%%"):format(done, total, math.floor(done / total * 100 + 0.5)))
        footer:Show()
    else
        footer:Hide()
    end
    local footerH = footer:IsShown() and 16 or 0
    frame:SetHeight(26 + 22 + y + PAD + footerH + 4)
end

-- The class crest in the header: lit while class & race quests are part of the main guides,
-- crossed out while they are hidden, absent in a chain guide (which always shows them).
function V.UpdateChainButton()
    if not chainBtn then return end
    local g = Guide.active
    chainBtn:SetShown(not (g and g.chain))
    local on = Guide.ChainsIncluded()
    chainBtn.icon:SetDesaturated(not on)
    chainBtn.icon:SetAlpha(on and 1 or 0.5)
    chainBtn.slash:SetShown(not on)
end

-- ---------------------------------------------------------------------------
-- Guide picker
-- ---------------------------------------------------------------------------

local function buildPicker()
    picker = CreateFrame("Frame", "TashGuidesPicker", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    picker:SetSize(300, 100)
    picker:SetFrameStrata("DIALOG")
    TG.Skin(picker, 0.96)
    picker:SetBackdropBorderColor(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.8)
    picker:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
    picker:EnableMouse(true)
    picker:Hide()
    local t = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 10, -8)
    t:SetText(TG.UI.BRAND .. "  " .. TG.Color(TG.C.muted, "choose a guide"))
    local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScale(0.8)
    picker.buttons = {}
    tinsert(UISpecialFrames, "TashGuidesPicker")
end

function V.ShowPicker()
    if not picker then buildPicker() end
    if picker:IsShown() then picker:Hide() return end
    local list = Guide.List()
    local y = 30
    picker.sections = picker.sections or {}
    local sectionN, lastKind = 0, nil
    for i, def in ipairs(list) do
        local kind = def.chain and "chain" or "main"
        if kind ~= lastKind then
            lastKind = kind
            sectionN = sectionN + 1
            local sec = picker.sections[sectionN]
            if not sec then
                sec = TG.UI.SectionLabel(picker)
                sec:SetWidth(280)
                picker.sections[sectionN] = sec
            end
            sec:ClearAllPoints()
            sec:SetPoint("TOPLEFT", 10, -y)
            sec.text:SetText(kind == "main" and "MAIN GUIDES" or "CLASS & RACE CHAINS")
            sec:Show()
            y = y + 18
        end
        local b = picker.buttons[i]
        if not b then
            b = textButton(picker, "", 280, nil)
            b:SetHeight(34)
            b.text:ClearAllPoints()
            b.text:SetPoint("TOPLEFT", 8, -5)
            b.text:SetJustifyH("LEFT")
            b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            b.sub:SetPoint("BOTTOMLEFT", 8, 5)
            b.lvl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.lvl:SetPoint("RIGHT", -8, 0)
            picker.buttons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 10, -y)
        local active = Guide.active and Guide.active.id == def.id
        b.text:SetText((active and TG.Color(TG.C.good, "> ") or "") .. def.title)
        b.sub:SetText(def.subtitle or "")
        b.lvl:SetText(def.dynamic and "any" or ("%d-%d"):format(def.minLevel or 1, def.maxLevel or 60))
        b:SetScript("OnClick", function()
            picker:Hide()
            Guide.Load(def.id)
            TG.Print("loaded %s", def.title)
        end)
        b:Show()
        y = y + 38
    end
    for i = #list + 1, #picker.buttons do picker.buttons[i]:Hide() end
    for i = sectionN + 1, #picker.sections do picker.sections[i]:Hide() end
    if not picker.reset then
        picker.reset = textButton(picker, "Restart current guide", 280, function()
            picker:Hide()
            Guide.Reset()
        end)
    end
    picker.reset:ClearAllPoints()
    picker.reset:SetPoint("TOPLEFT", 10, -(y + 4))
    if not picker.chains then
        picker.chains = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
        picker.chains:SetSize(22, 22)
        local fs = picker.chains:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", picker.chains, "RIGHT", 2, 1)
        fs:SetText("Include class & race quests in main guides")
        picker.chains:SetScript("OnClick", function(self) Guide.SetChainsIncluded(self:GetChecked() and true or false) end)
    end
    picker.chains:ClearAllPoints()
    picker.chains:SetPoint("TOPLEFT", 8, -(y + 28))
    picker.chains:SetChecked(Guide.ChainsIncluded())
    picker:SetHeight(y + 58)
    TG.UI.Beside(picker, frame, 300)
    picker:Show()
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function V.Init()
    frame = CreateFrame("Frame", "TashGuidesViewer", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(WIDTH, 200)
    frame:SetFrameStrata("MEDIUM")
    TG.Skin(frame, TG.db.viewer.alpha)
    TG.RestorePosition(frame, "viewer", "TOPLEFT", "TOPLEFT", 40, -180)
    TG.MakeMovable(frame, "viewer", function() return TG.db.viewer.locked end)

    header = TG.UI.Header(frame)
    header:AddButton("Interface\\Buttons\\UI-StopButton", 14, "Hide (/tg to show)", function()
        TG.db.viewer.shown = false
        V.Refresh()
    end)
    header:AddButton("Interface\\Buttons\\UI-MinusButton-Up", 14, "Minimize", function()
        TG.db.viewer.minimized = not TG.db.viewer.minimized
        V.Refresh()
    end)
    header:AddButton("Interface\\Icons\\Trade_Engineering", 16, "Options", function() TG.Options.Toggle() end)
    header:AddButton("Interface\\Icons\\INV_Misc_Book_09", 16, "Choose guide", V.ShowPicker)
    header:AddButton("Interface\\Icons\\INV_Misc_Note_05", 16,
        { "Steps", "Steps you have done and the ones still to come.", "Click a step to view it." },
        function() TG.Steps.Toggle() end)
    chainBtn = header:AddButton("Interface\\Icons\\INV_Misc_Book_11", 16, function()
        local on = Guide.ChainsIncluded()
        return { "Class & race quests: " .. (on and "|cff4de659included|r" or "|cffff4d40hidden|r"),
            "Class trainer and racial quest chains inside the main guides (zone guides and the Smart Guide).",
            "Click to " .. (on and "hide" or "include") .. " them. They are also available as their own guides from the book icon." }
    end, function()
        Guide.SetChainsIncluded(not Guide.ChainsIncluded())
        V.UpdateChainButton()
    end)
    local _, classFile = UnitClass("player")
    local coords = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
    if coords then
        chainBtn.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        chainBtn.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
    chainBtn.slash = chainBtn:CreateTexture(nil, "OVERLAY")
    chainBtn.slash:SetAllPoints()
    chainBtn.slash:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

    stepBar = CreateFrame("Frame", nil, frame)
    stepBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    stepBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    stepBar:SetHeight(22)
    stepBar.prev = iconButton(stepBar, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", 22, "Previous step", Guide.Prev)
    stepBar.prev:SetPoint("LEFT", 2, 0)
    stepBar.next = iconButton(stepBar, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 22, function()
        if Guide.active and Guide.active.dynamic then
            return { "Skip this step", "Moves it to the end of the route.", "Shift-click: plan the route again from here." }
        end
        return "Next step (Shift: skip)"
    end, function()
        if IsShiftKeyDown() then Guide.Skip()
        elseif Guide.Finished() and Guide.active.next then Guide.Load(Guide.active.next)
        else Guide.Next() end
    end)
    stepBar.next:SetPoint("RIGHT", -2, 0)
    -- Smart Guide routing: a fixed route followed step by step, or nearest task first.
    stepBar.mode = textButton(stepBar, "Linear", 58, function()
        TG.Smart.SetMode(TG.Smart.Mode() == "linear" and "nearest" or "linear")
    end)
    stepBar.mode:SetHeight(18)
    stepBar.mode:SetPoint("LEFT", 4, 0)
    stepBar.mode:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local linear = TG.Smart.Mode() == "linear"
        GameTooltip:AddLine("Routing: " .. (linear and "Linear" or "Nearest first"), 1, 1, 1)
        GameTooltip:AddLine(linear and "Follows a fixed route step by step, like a written guide. The current step stays until it is done; new quests are slotted into the route."
            or "Re-sorts by distance as you move, so the nearest task always leads.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Click to switch to " .. (linear and "nearest first." or "linear."), 0.25, 0.85, 0.6)
        GameTooltip:Show()
    end)
    stepBar.mode:SetScript("OnLeave", GameTooltip_Hide)
    stepBar.mode:Hide()

    -- Clicking the step bar returns from a viewed step to the live one.
    local back = CreateFrame("Button", nil, stepBar)
    back:SetPoint("LEFT", stepBar.prev, "RIGHT", 2, 0)
    back:SetPoint("RIGHT", stepBar.next, "LEFT", -2, 0)
    back:SetHeight(20)
    back:SetScript("OnClick", function()
        if Guide.view then Guide.View(Guide.cursor) else TG.Steps.Toggle() end
    end)
    back:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Guide.view and "Back to the current step" or "Show all steps", 1, 1, 1)
        GameTooltip:Show()
    end)
    back:SetScript("OnLeave", GameTooltip_Hide)
    stepLabel = stepBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stepLabel:SetPoint("LEFT", stepBar.prev, "RIGHT", 2, 0)
    stepLabel:SetPoint("RIGHT", stepBar.next, "LEFT", -2, 0)
    stepLabel:SetJustifyH("LEFT")
    stepLabel:SetWordWrap(false)

    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", stepBar, "BOTTOMLEFT", PAD, -2)
    body:SetWidth(WIDTH - PAD * 2)
    body:SetHeight(10)

    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(14)
    bar = CreateFrame("StatusBar", nil, footer)
    bar:SetAllPoints()
    bar:SetStatusBarTexture(TG.TEX.white)
    bar:SetStatusBarColor(TG.C.accent[1] * 0.6, TG.C.accent[2] * 0.6, TG.C.accent[3] * 0.6, 0.9)
    local bbg = bar:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0, 0, 0, 0.5)
    barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    barText:SetPoint("CENTER")

    V.frame = frame
    TG.On("TG_GUIDE", V.Refresh)
    TG.On("TG_SETTINGS", V.Refresh)
    TG.On("TG_QUESTLOG", function() TG.Schedule("viewer", 0.2, V.Refresh) end)
    V.Refresh()
end
