-- TashGuides questlog.lua: the player's quest log, objective progress and completed quests.
-- Fires "TG_QUESTLOG" after every rescan and "TG_QUEST_DONE"(questId) on turn-in.

local TG = TashGuides
local QL = { quests = {}, completed = {}, count = 0 }
TG.QuestLog = QL

local function numEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        return (C_QuestLog.GetNumQuestLogEntries()) or 0
    end
    return GetNumQuestLogEntries and (GetNumQuestLogEntries()) or 0
end

-- title, level, isHeader, isCollapsed, questID, isComplete (1 done / -1 failed / nil)
local function entry(i)
    if GetQuestLogTitle then
        local title, level, _, isHeader, isCollapsed, isComplete, _, questID = GetQuestLogTitle(i)
        local S = TG.Safe
        title, questID = S(title), S(questID)
        if title then return title, S(level), S(isHeader), S(isCollapsed), questID, S(isComplete) end
    end
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHidden then return nil end
        if info then
            local S = TG.Safe
            local complete = S(info.isComplete)
            if complete == nil and info.questID and C_QuestLog.IsComplete then
                complete = C_QuestLog.IsComplete(info.questID) and 1 or nil
            end
            return S(info.title), S(info.level), S(info.isHeader), S(info.isCollapsed), S(info.questID), complete
        end
    end
end

local function parseCount(text)
    local have, need = (text or ""):match("(%d+)%s*/%s*(%d+)")
    return tonumber(have), tonumber(need)
end

local function readObjectives(questID, index)
    local out = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives and questID then
        local list = C_QuestLog.GetQuestObjectives(questID)
        if type(list) == "table" and #list > 0 then
            for _, o in ipairs(list) do
                local text = TG.Safe(o.text)
                if type(text) ~= "string" then text = "" end
                local have, need = TG.Safe(o.numFulfilled), TG.Safe(o.numRequired)
                if type(need) ~= "number" then have, need = parseCount(text) end
                out[#out + 1] = { text = text, type = TG.Safe(o.type), finished = TG.Safe(o.finished) == true,
                    have = have, need = need }
            end
            return out
        end
    end
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard and index then
        for j = 1, GetNumQuestLeaderBoards(index) or 0 do
            local text, kind, finished = GetQuestLogLeaderBoard(j, index)
            text, finished = TG.Safe(text), TG.Safe(finished)
            if type(text) == "string" then
                local have, need = parseCount(text)
                out[#out + 1] = { text = text, type = kind, finished = finished and true or false, have = have, need = need }
            end
        end
    end
    return out
end

function QL.LoadCompleted()
    local ids = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
    if type(ids) == "table" and #ids > 0 then
        for _, id in ipairs(ids) do QL.completed[id] = true end
    elseif GetQuestsCompleted then
        local t = GetQuestsCompleted()
        if type(t) == "table" then for id in pairs(t) do QL.completed[id] = true end end
    end
    for id in pairs(TG.char.done) do QL.completed[id] = true end
end

function QL.IsCompleted(id)
    if not id then return false end
    if QL.completed[id] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        if ok and v then QL.completed[id] = true return true end
    end
    return false
end

function QL.Get(id) return id and QL.quests[id] end
function QL.InLog(id) return id ~= nil and QL.quests[id] ~= nil end
function QL.IsReady(id) local q = id and QL.quests[id] return q ~= nil and q.complete == true end

function QL.Scan()
    local seen, anyCollapsed, header = {}, false, nil
    local before = {}
    for id, q in pairs(QL.quests) do before[id] = q.complete end
    for i = 1, numEntries() do
        local title, level, isHeader, isCollapsed, questID, isComplete = entry(i)
        if isHeader then
            header = title
            if isCollapsed then anyCollapsed = true end
        elseif title and questID and questID > 0 then
            seen[questID] = true
            local q = QL.quests[questID] or { id = questID }
            q.title, q.level, q.index, q.header = title, level or 0, i, header
            q.failed = (isComplete == -1)
            q.objectives = readObjectives(questID, i)
            local allDone = #q.objectives > 0
            for _, o in ipairs(q.objectives) do if not o.finished then allDone = false end end
            -- An empty objective list only means "done" for quests that truly have none (talk-to
            -- quests); right after accepting, the client can briefly report no objectives.
            q.complete = not q.failed and (isComplete == 1 or allDone
                or (#q.objectives == 0 and #TG.DB.Objectives(questID) == 0))
            QL.quests[questID] = q
        end
    end
    -- Quests under a collapsed header are invisible to the scan; keep what we knew about them.
    if not anyCollapsed then
        for id in pairs(QL.quests) do if not seen[id] then QL.quests[id] = nil end end
    end
    local n, membership = 0, QL.membershipChanged or false
    QL.membershipChanged = false
    for id in pairs(before) do if not QL.quests[id] then membership = true end end
    for id, q in pairs(QL.quests) do
        n = n + 1
        if before[id] == nil then
            membership = true
            if QL.scanned then TG.Fire("TG_QUEST_ACCEPTED", id) end
        end
        if q.complete and before[id] == false then
            local finisher = TG.DB.GiverName(TG.DB.Finishers(id))
            TG.Print("%s %s%s", TG.Color(TG.C.good, "Complete:"), q.title,
                finisher and (" - turn in to " .. TG.Color(TG.C.gold, finisher)) or "")
            if TG.db.sounds and PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
                PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
            end
        end
    end
    QL.count = n
    QL.scanned = true
    -- second argument: true when quests were added/removed (not just progress ticks)
    TG.Fire("TG_QUESTLOG", membership)
end

local function queueScan() TG.Schedule("questlog", 0.15, QL.Scan) end

function QL.Init()
    QL.LoadCompleted()
    QL.Scan()
    TG.On("QUEST_LOG_UPDATE", queueScan)
    TG.On("QUEST_ACCEPTED", queueScan)
    TG.On("UNIT_QUEST_LOG_CHANGED", function(unit) if unit == "player" then queueScan() end end)
    TG.On("QUEST_REMOVED", function(id)
        if id then QL.quests[id] = nil end
        QL.membershipChanged = true
        queueScan()
    end)
    TG.On("QUEST_TURNED_IN", function(id)
        if not id then return end
        QL.membershipChanged = true
        QL.completed[id] = true
        TG.char.done[id] = true
        QL.quests[id] = nil
        TG.Fire("TG_QUEST_DONE", id)
        queueScan()
    end)
end
