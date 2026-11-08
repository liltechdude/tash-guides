-- TashGuides steplist.lua: the Steps panel beside the guide window. Lists every step of the
-- active guide - the ones already done, the current one and everything still to come - so
-- you can look back and ahead without moving the guide.
--   Click a step: view it in the guide window (past steps: review, future steps: preview).
--   Right-click (or Shift-click) a step: move the guide there.
-- For the Smart Guide (which has no fixed order) it shows every task it has lined up and
-- your recent quest activity instead.

local TG = TashGuides
local Guide, DB, QL, WP, UI = TG.Guide, TG.DB, TG.QuestLog, TG.Way, TG.UI
local S = {}
TG.Steps = S

local WIDTH = 320
local MAX_H = 440
local PAD = 8
local ICON = 14

local frame, header, summary, scroll, child, thumb
local rows, rowCount = {}, 0
local labels, labelCount = {}, 0
local lastCursor, lastGuide

local VERB = { accept = "Accept", complete = "Do", turnin = "Turn in", ["goto"] = "Go to", talk = "Talk to",
    level = "Reach level", hearth = "Hearth", fly = "Fly", note = "" }
local GOAL_ICON = {
    accept = TG.TEX.available, turnin = TG.TEX.turnin, complete = TG.TEX.dot,
    ["goto"] = TG.TEX.target, talk = TG.TEX.talk, level = TG.TEX.level,
    hearth = TG.TEX.hearth, fly = TG.TEX.target, note = TG.TEX.dot,
}

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

local function goalShort(goal)
    local t = goal.type
    if goal.quest then return VERB[t] .. " " .. (DB.QuestName(goal.quest) or ("#" .. goal.quest)) end
    if t == "talk" then return "Talk to " .. (DB.NpcName(goal.npc) or "?") end
    if t == "level" then return "Reach level " .. goal.level end
    if t == "goto" then return goal.text or "Go to a spot" end
    return UI.Plain(Guide.GoalText(goal))
end

-- Summary of a step's goals that apply to this character, plus how many are done.
local function stepSummary(si, step)
    local parts, done, total = {}, 0, 0
    for gi, goal in ipairs(step.goals) do
        local st = Guide.GoalStatus(si, gi, goal)
        if st ~= "na" and st ~= "info" then
            total = total + 1
            if st == "done" then done = done + 1 end
            parts[#parts + 1] = (st == "done") and TG.Color(TG.C.muted, goalShort(goal)) or goalShort(goal)
        end
    end
    return table.concat(parts, ", "), done, total
end

local function stepTitle(si, step)
    if step.title then return step.title end
    for gi, goal in ipairs(step.goals) do
        if Guide.GoalStatus(si, gi, goal) ~= "na" then return goalShort(goal) end
    end
    return "Step " .. si
end

local function ago(t)
    if not t or not time then return "" end
    local d = math.max(0, time() - t)
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function rowTooltip(r)
    local step = r.si and Guide.Steps()[r.si]
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if r.history then
        local h = r.history
        GameTooltip:AddLine(DB.QuestName(h.quest) or ("Quest " .. h.quest), TG.C.gold[1], TG.C.gold[2], TG.C.gold[3])
        GameTooltip:AddLine((h.kind == "turnin" and "Turned in " or "Accepted ") .. ago(h.time), 0.8, 0.8, 0.8)
        GameTooltip:Show()
        return
    end
    if not step then return end
    GameTooltip:AddLine(stepTitle(r.si, step), TG.C.gold[1], TG.C.gold[2], TG.C.gold[3])
    for gi, goal in ipairs(step.goals) do
        local st = Guide.GoalStatus(r.si, gi, goal)
        if st ~= "na" then
            local c = st == "done" and TG.C.good or (st == "info" and TG.C.muted or { 1, 1, 1 })
            GameTooltip:AddLine((st == "done" and "+ " or "- ") .. UI.Plain(Guide.GoalText(goal)), c[1], c[2], c[3], true)
        end
    end
    if step.note then GameTooltip:AddLine(step.note, 0.6, 0.6, 0.65, true) end
    if r.dynamic and Guide.Ordered() then
        GameTooltip:AddLine("Click: point the arrow here   Right-click: do this next", 0.25, 0.85, 0.6, true)
    elseif r.dynamic then
        GameTooltip:AddLine("Click: point the arrow here", 0.25, 0.85, 0.6)
    else
        GameTooltip:AddLine("Click: view this step   Right-click: move the guide here", 0.25, 0.85, 0.6, true)
    end
    GameTooltip:Show()
end

local function onRowClick(r, button)
    if r.history or not r.si then return end
    if r.dynamic then
        if (button == "RightButton" or IsShiftKeyDown()) and Guide.Ordered() then
            TG.Smart.Promote(r.si)
            return
        end
        local step = Guide.Steps()[r.si]
        for gi, goal in ipairs(step and step.goals or {}) do
            local wp = Guide.WaypointFor(r.si, gi, goal)
            if wp then wp.source = "pin" WP.Set(wp) return end
        end
        return
    end
    if button == "RightButton" or IsShiftKeyDown() then
        Guide.Goto(r.si)
    else
        Guide.View(r.si)
    end
end

local function acquireRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.edge = r:CreateTexture(nil, "BORDER")
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.edge:SetWidth(2)
    r.edge:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("TOPLEFT", 6, -3)
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(ICON + 4, ICON + 4)
    r.check:SetPoint("CENTER", r.icon, "CENTER", 1, 0)
    r.check:SetTexture(TG.TEX.check)
    r.num = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.num:SetPoint("TOPRIGHT", -4, -4)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -1)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetJustifyV("TOP")
    r.sub:SetWordWrap(true)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r:SetScript("OnEnter", rowTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", onRowClick)
    rows[i] = r
    return r
end

-- opts: state = "done" | "current" | "viewing" | "todo" | "click", icon, num, si, dynamic, history
local function addRow(y, title, sub, opts)
    rowCount = rowCount + 1
    local r = acquireRow(rowCount)
    local w = WIDTH - PAD * 2 - 10
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    r:SetWidth(w)
    r.si, r.dynamic, r.history = opts.si, opts.dynamic, opts.history
    local state = opts.state
    r.icon:SetTexture(opts.icon or TG.TEX.dot)
    local c = opts.iconColor
    if c then r.icon:SetVertexColor(c[1], c[2], c[3]) else r.icon:SetVertexColor(1, 1, 1) end
    r.icon:SetDesaturated(state == "done")
    r.icon:SetAlpha(state == "done" and 0.45 or 1)
    r.check:SetShown(state == "done")
    r.num:SetText(opts.num or "")
    r.title:SetWidth(w - ICON - 40)
    r.title:SetText(title)
    r.sub:SetWidth(w - ICON - 16)
    r.sub:SetText(sub or "")
    r.sub:SetShown(sub ~= nil and sub ~= "")
    local alpha = (state == "done") and 0.55 or 1
    r.title:SetAlpha(alpha)
    r.sub:SetAlpha(alpha)
    if state == "current" then
        r.bg:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.16)
        r.title:SetTextColor(1, 1, 1)
    elseif state == "viewing" then
        r.bg:SetColorTexture(TG.C.gold[1], TG.C.gold[2], TG.C.gold[3], 0.12)
        r.title:SetTextColor(TG.C.gold[1], TG.C.gold[2], TG.C.gold[3])
    else
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.title:SetTextColor(0.92, 0.92, 0.92)
    end
    r.edge:SetShown(state == "current")
    r.sub:SetTextColor(0.78, 0.78, 0.8)
    local h = 4 + 14 + ((sub and sub ~= "") and (r.sub:GetStringHeight() + 2) or 0) + 3
    r:SetHeight(math.max(h, ICON + 8))
    r:Show()
    return y + r:GetHeight() + 1, r
end

local function addLabel(y, text)
    labelCount = labelCount + 1
    local l = labels[labelCount]
    if not l then
        l = UI.SectionLabel(child)
        labels[labelCount] = l
    end
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -(y + 4))
    l:SetWidth(WIDTH - PAD * 2 - 14)
    l.text:SetText(text)
    l:Show()
    return y + 22
end

-- ---------------------------------------------------------------------------
-- Scrolling
-- ---------------------------------------------------------------------------

local function maxScroll() return math.max(0, (child:GetHeight() or 0) - (scroll:GetHeight() or 0)) end

local function updateThumb()
    local total, view = child:GetHeight() or 0, scroll:GetHeight() or 0
    if total <= view + 1 then thumb:Hide() return end
    local h = math.max(20, view * view / total)
    local pos = (scroll:GetVerticalScroll() or 0) / maxScroll()
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -pos * (view - h))
    thumb:Show()
end

local function scrollTo(v)
    scroll:SetVerticalScroll(math.max(0, math.min(maxScroll(), v)))
    updateThumb()
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- Long generated guides (hundreds of steps) list the recent steps and the next stretch only.
local PAST_CAP, FUTURE_CAP = 12, 60

local function renderFixed(g, steps)
    local y, currentY = 0, nil
    local done, total = Guide.Progress()
    local cursor, view = Guide.cursor, Guide.view
    local section
    local status, pastCount, futureCount = {}, 0, 0
    for si = 1, #steps do
        local st = Guide.StepStatus(si)
        status[si] = st
        if st ~= "na" then
            if si < cursor then pastCount = pastCount + 1 elseif si > cursor then futureCount = futureCount + 1 end
        end
    end
    local pastSeen, futureSeen = 0, 0
    for si = 1, #steps do
        local st = status[si]
        local skip = false
        if st ~= "na" then
            if si < cursor then
                pastSeen = pastSeen + 1
                skip = pastSeen <= pastCount - PAST_CAP
            elseif si > cursor then
                futureSeen = futureSeen + 1
                skip = futureSeen > FUTURE_CAP
            end
        end
        if st ~= "na" and not skip then
            local want = (si < cursor and "past") or (si == cursor and "now") or "next"
            if want ~= section then
                section = want
                y = addLabel(y, want == "past" and "EARLIER STEPS" or (want == "now" and "CURRENT STEP") or "COMING UP")
                if want == "past" and pastCount > PAST_CAP then
                    y = addRow(y, TG.Color(TG.C.muted, ("%d earlier steps"):format(pastCount - PAST_CAP)), nil, { state = "done" })
                end
            end
            local step = steps[si]
            local sub, gd, gt = stepSummary(si, step)
            local state = st == "done" and "done" or "todo"
            if si == cursor and st ~= "done" then state = "current" end
            if si == view then state = "viewing" end
            local icon, color = TG.TEX.dot, TG.C.muted
            for gi, goal in ipairs(step.goals) do
                if Guide.GoalStatus(si, gi, goal) == "todo" then
                    icon = GOAL_ICON[goal.type] or icon
                    color = goal.type == "complete" and TG.C.monster or nil
                    break
                end
            end
            if st == "click" then icon, color = TG.TEX.dot, TG.C.accent end
            local title = stepTitle(si, step)
            if step.chain and not g.chain then title = title .. " " .. TG.Color(TG.C.repeatable, "[" .. step.chain .. "]") end
            local rowY = y
            y = addRow(y, title, sub, { state = state, icon = icon, iconColor = color, si = si,
                num = gt > 0 and (gd .. "/" .. gt) or tostring(si) })
            if si == cursor then currentY = rowY end
            if si > cursor and futureSeen == FUTURE_CAP and futureCount > FUTURE_CAP then
                y = addRow(y, TG.Color(TG.C.muted, ("%d more steps"):format(futureCount - FUTURE_CAP)), nil, { state = "todo" })
            end
        end
    end
    if #steps == 0 then y = addRow(y, "This guide has no steps.", nil, { state = "todo" }) end
    if Guide.Finished() then
        y = addLabel(y, "FINISHED")
        local nextId = Guide.NextOf(g)
        y = addRow(y, TG.Color(TG.C.good, "Guide complete"), nextId
            and ("Next up: " .. Guide.registry[nextId].title) or nil, { state = "todo", icon = TG.TEX.check })
        currentY = y
    end
    summary:SetText(("%s  %d of %d steps done"):format(TG.Color(TG.C.gold, g.title), done, total)
        .. TG.Color(TG.C.muted, "   click: view  -  right-click: go to step"))
    return y, currentY
end

local function renderDynamic(g, steps)
    local linear = Guide.Ordered()
    local y = addLabel(0, linear and "ROUTE (IN ORDER)" or "LINED UP (NEAREST FIRST)")
    for si, step in ipairs(steps) do
        local sub = stepSummary(si, step)
        local first = step.goals[1]
        y = addRow(y, step.title or (si == 1 and "Nearest" or ("Task " .. si)), sub, {
            state = si == 1 and "current" or "todo", si = si, dynamic = true, num = tostring(si),
            icon = first and GOAL_ICON[first.type], iconColor = first and first.type == "complete" and TG.C.monster or nil })
    end
    local more = TG.Smart and TG.Smart.more or 0
    if linear and more > 0 then
        y = addRow(y, TG.Color(TG.C.muted, ("+%d more stop%s later in the route"):format(more, more == 1 and "" or "s")), nil, { state = "todo" })
    end
    local h = TG.char.history or {}
    if #h > 0 then
        y = addLabel(y, "RECENTLY DONE")
        for i = #h, math.max(1, #h - 19), -1 do
            local e = h[i]
            local name = DB.QuestName(e.quest) or ("Quest " .. e.quest)
            y = addRow(y, name, (e.kind == "turnin" and "Turned in" or "Accepted") .. TG.Color(TG.C.muted, "  " .. ago(e.time)),
                { state = "done", history = e, icon = e.kind == "turnin" and TG.TEX.turnin or TG.TEX.available })
        end
    end
    summary:SetText(TG.Color(TG.C.gold, g.title) .. TG.Color(TG.C.muted, linear
        and "   fixed route  -  click: arrow  -  right-click: do next"
        or "   re-sorted as you move  -  click: arrow"))
    return y, 0
end

function S.Refresh()
    if not frame then return end
    if not TG.db.steps.shown then frame:Hide() return end
    if not TG.db.viewer.shown then
        if frame:IsShown() then frame.autoHide = true frame:Hide() end
        return
    end
    for i = 1, rowCount do rows[i]:Hide() end
    for i = 1, labelCount do labels[i]:Hide() end
    rowCount, labelCount = 0, 0

    frame:SetScale(TG.db.viewer.scale)
    frame:SetBackdropColor(TG.C.bg[1], TG.C.bg[2], TG.C.bg[3], TG.db.viewer.alpha)
    if TG.Viewer.frame then UI.Beside(frame, TG.Viewer.frame, WIDTH) end

    local g = Guide.active
    local y, currentY = 0, nil
    if not g then
        header:SetLabel(TG.Color(TG.C.muted, "Steps"))
        summary:SetText("")
        y = addRow(0, "No guide loaded.", nil, { state = "todo" })
    else
        header:SetLabel(TG.Color(TG.C.gold, "Steps") .. "  " .. TG.Color(TG.C.muted, g.title))
        if g.dynamic then y, currentY = renderDynamic(g, Guide.Steps())
        else y, currentY = renderFixed(g, Guide.Steps()) end
    end

    child:SetHeight(math.max(y, 1))
    local top = UI.HEADER_H + 4 + (summary:GetStringHeight() or 12) + 6
    local h = math.min(MAX_H, top + y + PAD)
    frame:SetHeight(h)
    scroll:SetHeight(h - top - PAD)

    -- Follow the guide: when the cursor or guide changes, bring the current step into view.
    local key = g and g.id
    if currentY and (key ~= lastGuide or Guide.cursor ~= lastCursor) then
        scrollTo(currentY - 60)
    else
        scrollTo(scroll:GetVerticalScroll() or 0)
    end
    lastGuide, lastCursor = key, Guide.cursor
    frame:Show()
end

function S.Toggle()
    TG.db.steps.shown = not TG.db.steps.shown
    lastCursor = nil
    S.Refresh()
end

function S.Init()
    frame = CreateFrame("Frame", "TashGuidesSteps", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(WIDTH, 200)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    TG.Skin(frame, TG.db.viewer.alpha)
    frame:Hide()

    header = UI.Header(frame)
    header:AddButton("Interface\\Buttons\\UI-StopButton", 14, "Close", function()
        TG.db.steps.shown = false
        S.Refresh()
    end)

    summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD, -4)
    summary:SetWidth(WIDTH - PAD * 2)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(true)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -6)
    scroll:SetWidth(WIDTH - PAD * 2 - 6)
    scroll:SetHeight(100)
    child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(WIDTH - PAD * 2 - 6)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        scrollTo((self:GetVerticalScroll() or 0) - delta * 48)
    end)
    thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(TG.C.accent[1], TG.C.accent[2], TG.C.accent[3], 0.6)
    thumb:Hide()

    tinsert(UISpecialFrames, "TashGuidesSteps")
    frame:SetScript("OnHide", function()
        -- Escape closes the panel; hiding it along with the guide window does not.
        if frame.autoHide then frame.autoHide = nil return end
        TG.db.steps.shown = false
    end)

    TG.On("TG_GUIDE", function() if TG.db.steps.shown then TG.Schedule("steps", 0.1, S.Refresh) end end)
    TG.On("TG_QUESTLOG", function() if TG.db.steps.shown then TG.Schedule("steps", 0.3, S.Refresh) end end)
    TG.On("TG_SETTINGS", function() TG.Schedule("steps", 0.1, S.Refresh) end)
    S.Refresh()
end
