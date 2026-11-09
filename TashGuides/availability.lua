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
    local _, classFile = UnitClass("player")
    AV.classFile = classFile and classFile:upper() or nil
end

function AV.RaceOk(qid)
    local mask = DB.Quest(qid, "requiredRaces") or 0
    if mask == 0 or not raceBit then return true end
    return TG.HasBit(mask, raceBit)
end

-- Class from a trainer title: "Hunter Trainer" -> "HUNTER". Profession trainers give nil.
local CLASS_TOKENS = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
    MAGE = true, WARLOCK = true, DRUID = true, DEATHKNIGHT = true, MONK = true, DEMONHUNTER = true, EVOKER = true }
local function trainerClass(npcId)
    local sub = DB.Npc(npcId, "subName")
    if type(sub) ~= "string" then return nil end
    local name = sub:match("^%s*(.-)%s+Trainer%s*$")
    local token = name and name:upper():gsub("[%s%-]", "")
    return token and CLASS_TOKENS[token] and token or nil
end

-- The class of the trainer(s) who start a quest, when every NPC that starts it is a trainer
-- of that one class and nothing else (no object or item) starts it.
local function starterClass(qid)
    local c = false
    local g = DB.Quest(qid, "startedBy")
    local npcs = type(g) == "table" and g[1] or nil
    local objects, items = type(g) == "table" and g[2] or nil, type(g) == "table" and g[3] or nil
    if npcs and #npcs > 0 and not (objects and #objects > 0) and not (items and #items > 0) then
        for _, id in ipairs(npcs) do
            local t = trainerClass(id)
            if not t or (c and c ~= t) then return false end
            c = t
        end
    end
    return c
end

-- Does the quest follow an ordinary quest (no class flag, not from a class trainer)? Then it
-- is part of a chain everyone can do, even when a trainer happens to hand out this step.
local function followsOrdinaryQuest(qid)
    for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
        for _, p in ipairs(DB.Quest(qid, key) or {}) do
            if p > 0 and DB.QuestExists(p) and (DB.Quest(p, "requiredClasses") or 0) == 0 and not starterClass(p) then
                return true
            end
        end
    end
    return false
end

-- Some quests (often ones added for Forever) carry no class flag in QuestieDB although the
-- game only offers them to one class. When every NPC that starts a quest is a trainer of
-- the same class, treat the quest as that class's, unless it continues an ordinary quest
-- chain. Returns a class token or nil.
local inferredCache = {}
function AV.InferredClass(qid)
    local c = inferredCache[qid]
    if c == nil then
        c = starterClass(qid)
        if c and followsOrdinaryQuest(qid) then c = false end
        inferredCache[qid] = c
    end
    return c or nil
end

function AV.ClassOk(qid)
    local mask = DB.Quest(qid, "requiredClasses") or 0
    if mask == 0 or not classBit then
        local inferred = AV.InferredClass(qid)
        if inferred and AV.classFile and inferred ~= AV.classFile then return false end
        return true
    end
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

-- Quests the server did not offer although the database says it should: quest id -> the
-- character level when that was seen. They count as unavailable until the next level, when
-- whatever held them back (an unknown requirement) may have changed.
local function notOffered(qid, level)
    local seen = TG.char.notOffered and TG.char.notOffered[qid]
    return seen ~= nil and seen >= level
end

function AV.NotOffered(qid) return notOffered(qid, UnitLevel("player") or 1) end

-- Reasons a quest can no longer be picked up at all (not just not yet): an exclusive quest
-- was taken, a breadcrumb is moot, an offer expired, or the character is too high a level.
local GONE = { exclusive = true, breadcrumb = true, expired = true, ["too high"] = true }
local goneCache = {}
function AV.Gone(qid)
    local c = goneCache[qid]
    if c == nil then
        local ok, why = AV.IsEligible(qid)
        c = (not ok and GONE[why]) and true or false
        goneCache[qid] = c
    end
    return c
end
function AV.ForgetGone() wipe(goneCache) end

-- Returns true when the quest can be accepted now. `reason` explains a false.
function AV.IsEligible(qid, level)
    local QL = TG.QuestLog
    if QL.IsCompleted(qid) and not DB.IsRepeatable(qid) then return false, "done" end
    if QL.InLog(qid) then return false, "in log" end
    level = level or UnitLevel("player") or 1
    if notOffered(qid, level) then return false, "not offered" end
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
    -- a child quest is offered only while its parent quest is in the log
    if parent > 0 and not QL.InLog(parent) then return false, "child" end
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
    local byMap, set, count, byGiver = {}, {}, 0, {}
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
                if giver.kind == "npc" then
                    local list = byGiver[giver.id]
                    if not list then list = {}; byGiver[giver.id] = list end
                    list[#list + 1] = qid
                end
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
    AV.byMap, AV.set, AV.count, AV.byGiver = byMap, set, count, byGiver
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

-- ---------------------------------------------------------------------------
-- Check the database against what NPCs actually offer.
-- When a quest window opens, every quest that NPC should have for you (by the index) but does
-- not list is marked "not offered" and drops out of the guide, the pins and the Smart Guide.
-- ---------------------------------------------------------------------------

-- Titles and ids the open window lists as available, or nil when it cannot be read.
local function offeredNow(event)
    local ids, titles = {}, {}
    if event == "GOSSIP_SHOW" then
        local G = C_GossipInfo
        if G and G.GetAvailableQuests then
            for _, q in ipairs(G.GetAvailableQuests() or {}) do
                local id, title = TG.Safe(q.questID), TG.Safe(q.title)
                if id then ids[id] = true end
                if type(title) == "string" then titles[title] = true end
            end
            return ids, titles
        elseif GetGossipAvailableQuests then
            local info = { GetGossipAvailableQuests() }
            local stride = 7
            for i = 1, math.floor(#info / stride) do
                local title = TG.Safe(info[(i - 1) * stride + 1])
                if type(title) == "string" then titles[title] = true end
            end
            return ids, titles
        end
    elseif event == "QUEST_GREETING" and GetNumAvailableQuests and GetAvailableTitle then
        for i = 1, GetNumAvailableQuests() or 0 do
            local title = TG.Safe(GetAvailableTitle(i))
            if type(title) == "string" then titles[title] = true end
        end
        return ids, titles
    end
    return nil
end

function AV.CheckOffers(event, npcId)
    if not npcId or not AV.byGiver then return end
    local expected = AV.byGiver[npcId]
    if not expected then return end
    local ids, titles = offeredNow(event)
    if not ids then return end
    local level = UnitLevel("player") or 1
    local trivialBelow = AV.TrivialLevel(level)
    local missed = {}
    for _, qid in ipairs(expected) do
        local e = AV.set[qid]
        local qlevel = DB.QuestLevel(qid)
        -- Low-level quests can be hidden by the client's own filter: never judge those.
        if e and not (qlevel > 0 and qlevel < trivialBelow) and AV.IsEligible(qid, level)
            and not ids[qid] and not titles[DB.QuestName(qid) or ""] then
            missed[#missed + 1] = qid
        end
    end
    if #missed == 0 then return end
    TG.char.notOffered = TG.char.notOffered or {}
    local names = {}
    for _, qid in ipairs(missed) do
        TG.char.notOffered[qid] = level
        names[#names + 1] = TG.Color(TG.C.gold, DB.QuestName(qid) or ("#" .. qid))
    end
    TG.Print("%s does not offer %s to you - hidden from the guide until your next level.",
        DB.NpcName(npcId) or "This NPC", table.concat(names, ", "))
    AV.Rebuild()
    TG.Schedule("guide", 0.3, function() if TG.Guide.active then TG.Guide.Evaluate() end end)
end

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
    TG.On("TG_QUESTLOG", function(membership) if membership then AV.ForgetGone() end end)
    TG.On("TG_QUEST_DONE", AV.ForgetGone)
    TG.On("PLAYER_LEVEL_UP", AV.ForgetGone)
    for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING" }) do
        TG.On(e, function()
            local npc = TG.NpcIdFromGuid(UnitGUID("npc"))
            -- the window's lists fill in on the same frame; read them a moment later
            C_Timer.After(0.1, function()
                local ok, err = pcall(AV.CheckOffers, e, npc)
                if not ok then TG.Report(err) end
            end)
        end)
    end
end
