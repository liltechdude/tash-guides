-- TashGuides availability.lua: which quests this character can pick up right now, and where.
-- The index is rebuilt in small slices across frames (QuestieDB holds ~5k quests) and fires
-- "TG_AVAILABLE" when a fresh index is in place.

local TG = TashGuides
local DB = TG.DB
local AV = { byMap = {}, set = {}, count = 0 }
TG.Avail = AV

local raceBit, classBit

function AV.PlayerFacts()
    local _, _, raceID = UnitRace("player")
    local _, _, classID = UnitClass("player")
    raceBit = raceID and raceID > 0 and 2 ^ (raceID - 1) or nil
    classBit = classID and classID > 0 and 2 ^ (classID - 1) or nil
    AV.raceBit, AV.classBit = raceBit, classBit
end

function AV.RaceOk(qid)
    local mask = DB.Quest(qid, "requiredRaces") or 0
    if mask == 0 or not raceBit then return true end
    return TG.HasBit(mask, raceBit)
end

function AV.ClassOk(qid)
    local mask = DB.Quest(qid, "requiredClasses") or 0
    if mask == 0 or not classBit then return true end
    return TG.HasBit(mask, classBit)
end

-- Can this character ever do the quest (race/class), regardless of level or progress?
function AV.ForPlayer(qid)
    return DB.QuestExists(qid) and AV.RaceOk(qid) and AV.ClassOk(qid)
end

function AV.TrivialLevel(level)
    level = level or UnitLevel("player") or 1
    local range = (GetQuestGreenRange and GetQuestGreenRange()) or 8
    return level - range
end

-- Pre-requisites. preQuestSingle: any one done. preQuestGroup: all done.
-- Negative ids appear in a few Questie entries; they are treated as already satisfied.
function AV.PrereqsDone(qid)
    local QL = TG.QuestLog
    local single = DB.Quest(qid, "preQuestSingle")
    if single and #single > 0 then
        local any = false
        for _, p in ipairs(single) do
            if p < 0 or QL.IsCompleted(p) then any = true break end
        end
        if not any then return false end
    end
    local group = DB.Quest(qid, "preQuestGroup")
    if group then
        for _, p in ipairs(group) do
            if p > 0 and not QL.IsCompleted(p) then return false end
        end
    end
    return true
end

-- Returns true when the quest can be accepted now. `reason` explains a false.
function AV.IsEligible(qid, level)
    local QL = TG.QuestLog
    if QL.IsCompleted(qid) and not DB.IsRepeatable(qid) then return false, "done" end
    if QL.InLog(qid) then return false, "in log" end
    level = level or UnitLevel("player") or 1
    if (DB.Quest(qid, "requiredLevel") or 0) > level then return false, "level" end
    local maxLevel = DB.Quest(qid, "requiredMaxLevel") or 0
    if maxLevel > 0 and level > maxLevel then return false, "too high" end
    if not AV.RaceOk(qid) then return false, "race" end
    if not AV.ClassOk(qid) then return false, "class" end
    if not AV.PrereqsDone(qid) then return false, "prereq" end
    local excl = DB.Quest(qid, "exclusiveTo")
    if excl then
        for _, e in ipairs(excl) do
            if QL.IsCompleted(e) or QL.InLog(e) then return false, "exclusive" end
        end
    end
    local untilDone = DB.Quest(qid, "availableUntilCompleted") or 0
    if untilDone > 0 and QL.IsCompleted(untilDone) then return false, "expired" end
    local crumbFor = DB.Quest(qid, "breadcrumbForQuestId") or 0
    if crumbFor > 0 and (QL.IsCompleted(crumbFor) or QL.InLog(crumbFor)) then return false, "breadcrumb" end
    local parent = DB.Quest(qid, "parentQuest") or 0
    if parent > 0 then return false, "child" end
    return true
end

-- Filter for map pins (settings-dependent): trivial, repeatable and profession quests.
function AV.ShowOnMap(entry)
    local pins = TG.db.pins
    if entry.trivial and not pins.trivial then return false end
    if entry.repeatable and not pins.repeatable then return false end
    if entry.profession and not pins.profession then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Index build
-- ---------------------------------------------------------------------------

local worker, rerun
local runner = CreateFrame("Frame")
runner:Hide()

local function build()
    local byMap, set, count = {}, {}, 0
    local level = UnitLevel("player") or 1
    local trivialBelow = AV.TrivialLevel(level)
    local ids = DB.QuestIds()
    for i = 1, #ids do
        local qid = ids[i]
        if AV.IsEligible(qid, level) then
            local qlevel = DB.QuestLevel(qid)
            local entry = {
                quest = qid,
                level = qlevel,
                trivial = qlevel > 0 and qlevel < trivialBelow,
                repeatable = DB.IsRepeatable(qid),
                profession = DB.Quest(qid, "requiredSkill") ~= nil,
            }
            set[qid] = entry
            count = count + 1
            for _, giver in ipairs(DB.Starters(qid)) do
                for _, p in ipairs(giver.points) do
                    local list = byMap[p.map]
                    if not list then list = {}; byMap[p.map] = list end
                    list[#list + 1] = { quest = qid, map = p.map, x = p.x, y = p.y, giver = giver.name,
                        giverId = giver.id, giverKind = giver.kind, info = entry }
                end
            end
        end
        if i % 120 == 0 then coroutine.yield() end
    end
    AV.byMap, AV.set, AV.count = byMap, set, count
end

runner:SetScript("OnUpdate", function(self)
    if not worker then self:Hide() return end
    local ok, err = coroutine.resume(worker)
    if not ok then
        worker = nil
        self:Hide()
        TG.Report(err)
        return
    end
    if coroutine.status(worker) == "dead" then
        worker = nil
        if rerun then
            rerun = false
            worker = coroutine.create(build)
        else
            self:Hide()
            TG.Fire("TG_AVAILABLE")
        end
    end
end)

function AV.Rebuild()
    if worker then rerun = true return end
    worker = coroutine.create(build)
    runner:Show()
end

function AV.ForMap(map) return map and AV.byMap[map] or nil end
function AV.IsAvailable(qid) return AV.set[qid] ~= nil end

function AV.Init()
    AV.PlayerFacts()
    AV.Rebuild()
    -- The server's completed-quest list can arrive a little after login: refresh once.
    C_Timer.After(6, function()
        TG.QuestLog.LoadCompleted()
        AV.Rebuild()
        TG.Schedule("guide", 0.5, function() if TG.Guide.active then TG.Guide.Evaluate() end end)
    end)
    local function soon() TG.Schedule("avail", 0.6, AV.Rebuild) end
    TG.On("TG_QUESTLOG", function(membership) if membership then soon() end end)
    TG.On("PLAYER_LEVEL_UP", function() TG.Schedule("avail", 1.0, AV.Rebuild) end)
    TG.On("SKILL_LINES_CHANGED", soon)
end
