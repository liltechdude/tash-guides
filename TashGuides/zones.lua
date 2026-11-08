-- TashGuides zones.lua: zone guides for levels 1-60, generated from QuestieDB.
--
-- At login every quest is checked for this character (faction, race, class, level 60 or below,
-- not repeatable / profession / holiday / child, given by someone who stands somewhere) and
-- filed under the zone its giver is in. Every zone with enough quests becomes a guide
-- ("ZONE_<uiMapId>"); its steps are built the first time it is loaded:
--
--   * a short simulation of playing the zone: quests whose in-zone prerequisites are done
--     come available, a level counter rises as quests are handed in (so higher-level quests
--     unlock in a believable order), and the log never holds more than LOG_CAP quests;
--   * each move goes to the cheapest task (hand in 0.6x, pick up 0.85x, objectives 1.0x of the
--     walking distance; a pick-up also counts half the walk from its giver to its objectives),
--     then everything that can be done within reach of that spot joins the same step: hand-ins and pick-ups at one NPC, objectives in one area;
--   * class and racial quests get steps of their own (step.chain) so the "include class &
--     race quests" opt-out hides them without touching the rest of the route.
--
-- The result depends only on the data and the character's faction / race / class, never on
-- quest progress, so step numbers (and the saved place in the guide) stay put between
-- sessions. Quests that can never be taken at runtime (an exclusive quest was done, a
-- breadcrumb is moot) are hidden by the guide engine (def.hideUnavailable).
--
-- Left out on purpose: dungeon / group quests (every objective inside an instance), quests
-- that start from an item or inside an instance, holiday quests, and profession quests
-- (those have their own guides, see chains.lua).

local TG = TashGuides
local DB, AV, WP = TG.DB, TG.Avail, TG.Way
local Z = { byMap = {}, defs = {}, ready = false, count = 0 }
TG.Zones = Z

local MAX_LEVEL = 60
local MIN_QUESTS = 8            -- fewer quests than this and a zone gets no guide
local NPC_YARDS = 35            -- hand-ins and pick-ups this close share a step
local AREA_YARDS = 140          -- objectives this close share a step
local LOG_CAP = 10              -- quests the simulation carries at once
local MAX_GOALS = 12            -- goals per step
local UNKNOWN = 15000           -- yards between spots with no known route between them
local DEFAULT_SIZE = { 3000, 2000 }
local WEIGHT = { T = 0.6, A = 0.85, C = 1.0 }
local KIND_ORDER = { T = 1, A = 2, C = 3 }
local GOAL = { A = "accept", C = "complete", T = "turnin" }

-- QuestieDB zoneOrSort values of holiday / event quests (negative numbers are quest sorts,
-- positive ones are zones). Best effort: add an id here if an event quest slips into a guide.
local HOLIDAY_SORT = { [-22] = true, [-284] = true, [-364] = true, [-365] = true, [-366] = true,
    [-369] = true, [-370] = true, [-374] = true, [-375] = true, [-376] = true }

-- ---------------------------------------------------------------------------
-- Which quests belong in a zone guide
-- ---------------------------------------------------------------------------

function Z.Static(qid)
    if not DB.QuestExists(qid) or not DB.QuestName(qid) then return false end
    if not AV.ForPlayer(qid) then return false end
    if DB.IsRepeatable(qid) then return false end
    if (DB.Quest(qid, "requiredLevel") or 0) > MAX_LEVEL then return false end
    if TG.Chains.SkillOf(qid) then return false end
    if (DB.Quest(qid, "parentQuest") or 0) > 0 then return false end
    local sort = DB.Quest(qid, "zoneOrSort")
    if type(sort) == "number" and HOLIDAY_SORT[sort] then return false end
    return true
end

local function pointLess(a, b)
    if a.map ~= b.map then return a.map < b.map end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

local function giverPoints(list, out)
    out = out or {}
    for _, g in ipairs(list or {}) do
        for _, p in ipairs(g.points) do out[#out + 1] = p end
    end
    return out
end

-- The map most of the points are on (ties: the lowest map id).
local function dominantMap(pts)
    local count = {}
    for _, p in ipairs(pts) do count[p.map] = (count[p.map] or 0) + 1 end
    local best, bestCount
    for map, c in pairs(count) do
        if not bestCount or c > bestCount or (c == bestCount and map < best) then best, bestCount = map, c end
    end
    return best
end

-- The point nearest the middle of a spread of spawns (on preferredMap when it has any).
local function anchor(pts, preferredMap)
    local use = {}
    for _, p in ipairs(pts) do if p.map == preferredMap then use[#use + 1] = p end end
    if #use == 0 then
        local m = dominantMap(pts)
        for _, p in ipairs(pts) do if p.map == m then use[#use + 1] = p end end
    end
    local sx, sy = 0, 0
    for _, p in ipairs(use) do sx, sy = sx + p.x, sy + p.y end
    local cx, cy = sx / #use, sy / #use
    local best, bestD
    for _, p in ipairs(use) do
        local d = (p.x - cx) ^ 2 + (p.y - cy) ^ 2
        if not bestD or d < bestD or (d == bestD and pointLess(p, best)) then best, bestD = p, d end
    end
    return { map = best.map, x = best.x, y = best.y }
end

-- Everything the simulation needs about one quest, or nil when it has nowhere to be done.
local function buildInfo(qid)
    local pts = {}
    for _, p in ipairs(giverPoints(DB.Starters(qid))) do
        if not p.dungeon then pts[#pts + 1] = p end     -- givers inside instances are out
    end
    if #pts == 0 then return nil end
    local map = dominantMap(pts)
    local here = {}
    for _, p in ipairs(pts) do if p.map == map then here[#here + 1] = p end end
    table.sort(here, pointLess)
    local a = { map = map, x = here[1].x, y = here[1].y }

    local rl = math.max(DB.Quest(qid, "requiredLevel") or 0, 1)
    local ql = DB.QuestLevel(qid)
    local info = { id = qid, map = map, a = a, rl = rl, ql = ql,
        lv = math.min(MAX_LEVEL, math.max(rl, ql - 5, 1)), chain = TG.Chains.Kind(qid) }

    -- hand-in: the finisher spot nearest the pick-up (same NPC for most quests)
    local fpts = giverPoints(DB.Finishers(qid))
    local bestD
    for _, p in ipairs(fpts) do
        local d = p.map == a.map and ((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2) or 1e9
        if not bestD or d < bestD or (d == bestD and pointLess(p, info.t)) then
            bestD, info.t = d, { map = p.map, x = p.x, y = p.y }
        end
    end
    info.t = info.t or a

    local objs = DB.Objectives(qid)
    info.hasC = #objs > 0
    if info.hasC then
        local opts, allInside = {}, true
        for _, s in ipairs(objs) do
            for _, p in ipairs(s.points) do
                opts[#opts + 1] = p
                if not p.dungeon then allInside = false end
            end
        end
        if #opts > 0 then
            if allInside then return nil end            -- an instance quest: not for a leveling route
            info.c = anchor(opts, map)
        end
    end
    return info
end

-- ---------------------------------------------------------------------------
-- Indexing (in slices across frames, like the availability index)
-- ---------------------------------------------------------------------------

local worker
local runner = CreateFrame("Frame")
runner:Hide()

local function percentile(sorted, p)
    if #sorted == 0 then return 1 end
    return sorted[math.max(1, math.min(#sorted, math.ceil(#sorted * p)))]
end

local function register()
    local maps = {}
    for map, list in pairs(Z.byMap) do
        if #list >= MIN_QUESTS then maps[#maps + 1] = map end
    end
    table.sort(maps)
    Z.maps = maps
    for _, map in ipairs(maps) do
        local list = Z.byMap[map]
        table.sort(list, function(a, b)
            if a.lv ~= b.lv then return a.lv < b.lv end
            return a.id < b.id
        end)
        local lows, highs = {}, {}
        for _, q in ipairs(list) do lows[#lows + 1], highs[#highs + 1] = q.lv, math.max(q.ql, q.lv) end
        table.sort(lows)
        table.sort(highs)
        local lo = percentile(lows, 0.1)
        local hi = math.max(lo, math.min(MAX_LEVEL, percentile(highs, 0.9)))
        local name = TG.MapName(map)
        local def = {
            id = "ZONE_" .. map, title = name, group = "zone", map = map,
            subtitle = ("%d quests"):format(#list), questCount = #list,
            hideUnavailable = true,
            minLevel = lo, maxLevel = hi,
            hub = list[1].a,
            build = function() return Z.Steps(map) end,
        }
        def.nextFn = function() return Z.NextFor(map) end
        Z.defs[map] = def
        TG.RegisterGuide(def)
    end
    Z.ready = true
    TG.Fire("TG_ZONES")
end

local function index()
    local ids = {}
    local all = DB.QuestIds() or {}
    for i = 1, #all do ids[i] = all[i] end
    table.sort(ids)
    local byMap, count = {}, 0
    for i = 1, #ids do
        local qid = ids[i]
        if Z.Static(qid) then
            local info = buildInfo(qid)
            if info then
                local list = byMap[info.map]
                if not list then list = {}; byMap[info.map] = list end
                list[#list + 1] = info
                count = count + 1
            end
        end
        if i % 60 == 0 then coroutine.yield() end
    end
    Z.byMap, Z.count = byMap, count
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
        self:Hide()
        local good, e = pcall(register)
        if not good then TG.Report(e) end
    end
end)

function Z.Rebuild()
    if worker then return end
    Z.ready = false
    worker = coroutine.create(index)
    runner:Show()
end

function Z.Init()
    Z.Rebuild()
end

-- The zone guide to suggest after this one: a step up in level, preferably on the same
-- continent and close by.
function Z.NextFor(map)
    local me = Z.defs[map]
    if not me then return nil end
    local best, bestScore
    for other, def in pairs(Z.defs) do
        if other ~= map and def.maxLevel > me.maxLevel then
            local d = WP.Between(me.hub, def.hub)
            local score = math.abs(def.minLevel - (me.maxLevel - 2)) + (d and (d / 2000) or 100)
            if not bestScore or score < bestScore or (score == bestScore and other < best) then
                best, bestScore = other, score
            end
        end
    end
    return best and ("ZONE_" .. best) or nil
end

-- ---------------------------------------------------------------------------
-- Route simulation
-- ---------------------------------------------------------------------------

local function dist(a, b)
    if not (a and b) then return 0 end
    if a.map == b.map then
        local s = WP.MapSize(a.map) or DEFAULT_SIZE
        local dx, dy = (a.x - b.x) * s[1], (a.y - b.y) * s[2]
        return math.sqrt(dx * dx + dy * dy)
    end
    return WP.Between(a, b) or UNKNOWN
end

local function levelsNeeded(level) return math.max(3, math.floor(3 + 0.2 * level)) end

local function shorten(s)
    if #s > 40 then return s:sub(1, 38) .. ".." end
    return s
end

local function titleFor(goals, list)
    for _, g in ipairs(goals) do
        if g.kind ~= "C" then
            local who = DB.GiverName(g.kind == "T" and DB.Finishers(list[g.i].id) or DB.Starters(list[g.i].id))
            if who and who ~= "?" then return shorten(who) end
        end
    end
    local first, more = nil, -1
    for _, g in ipairs(goals) do
        if g.kind == "C" then
            first = first or DB.QuestName(list[g.i].id)
            more = more + 1
        end
    end
    if not first then return nil end
    return shorten(first) .. (more > 0 and (" +" .. more) or "")
end

function Z.Steps(map)
    local list = Z.byMap[map] or {}
    local n = #list
    if n == 0 then return {} end
    local idx = {}
    for i, q in ipairs(list) do idx[q.id] = i end

    -- gates: in-zone prerequisites (a prerequisite outside the zone is assumed done elsewhere)
    local gSingle, gGroup, excl, state = {}, {}, {}, {}
    local alive, maxLv, minLv = 0, 1, MAX_LEVEL
    for i, q in ipairs(list) do
        state[i] = 0
        alive = alive + 1
        maxLv, minLv = math.max(maxLv, q.lv), math.min(minLv, q.lv)
        local singles = DB.Quest(q.id, "preQuestSingle")
        if type(singles) == "table" and #singles > 0 then
            local gated = true
            for _, p in ipairs(singles) do if p < 0 or not idx[p] then gated = false break end end
            if gated then
                local t = {}
                for _, p in ipairs(singles) do t[#t + 1] = idx[p] end
                gSingle[i] = t
            end
        end
        local gg = {}
        for _, p in ipairs(DB.Quest(q.id, "preQuestGroup") or {}) do
            if p > 0 and idx[p] then gg[#gg + 1] = idx[p] end
        end
        gGroup[i] = gg
        for _, e in ipairs(DB.Quest(q.id, "exclusiveTo") or {}) do
            local j = idx[e]
            if j and j ~= i then
                excl[i] = excl[i] or {}
                excl[i][j] = true
                excl[j] = excl[j] or {}
                excl[j][i] = true
            end
        end
    end
    -- a breadcrumb whose target is in this zone is a detour: leave it out
    for i, q in ipairs(list) do
        local bc = DB.Quest(q.id, "breadcrumbForQuestId") or 0
        if bc > 0 and idx[bc] then state[i] = -1; alive = alive - 1 end
    end

    local function gateOk(i)
        local gs = gSingle[i]
        if gs then
            local any = false
            for _, j in ipairs(gs) do if state[j] == 3 then any = true break end end
            if not any then return false end
        end
        for _, j in ipairs(gGroup[i]) do if state[j] ~= 3 then return false end end
        return true
    end

    local steps, pos = {}, nil
    local simLevel, counter, inLog = minLv, 0, 0
    local guard, maxIter = 0, n * 3 + 20

    while alive > 0 and guard < maxIter do
        guard = guard + 1

        -- 1. the cheapest next task
        local bI, bKind, bLoc, bScore
        local function consider(i, kind, loc)
            local d = (pos and loc) and dist(pos, loc) or 0
            -- a pick-up whose objectives are far from its giver is a detour: count half that walk
            if kind == "A" and list[i].c then d = d + 0.5 * dist(loc, list[i].c) end
            local lag = math.max(0, simLevel - list[i].lv)
            local score = d * WEIGHT[kind] / (1 + 0.05 * lag)
            local better = not bI or score < bScore - 1e-9
            if not better and math.abs(score - bScore) <= 1e-9 then
                local ko, kb = KIND_ORDER[kind], KIND_ORDER[bKind]
                better = ko < kb or (ko == kb and list[i].id < list[bI].id)
            end
            if better then bI, bKind, bLoc, bScore = i, kind, loc, score end
        end
        for i = 1, n do
            local s, q = state[i], list[i]
            if s == 1 then consider(i, "C", q.c or q.a)
            elseif s == 2 then consider(i, "T", q.t)
            elseif s == 0 and inLog < LOG_CAP and q.lv <= simLevel and gateOk(i) then consider(i, "A", q.a) end
        end
        if not bI then
            if simLevel < maxLv then
                simLevel = simLevel + 1                 -- nothing left at this level: level up
                counter = 0
            else
                for i = 1, n do                         -- gates that can never open: take them anyway
                    if state[i] == 0 then consider(i, "A", list[i].a) end
                end
            end
        end

        if bI then
            -- 2. build the step around it
            local ck = list[bI].chain
            local loc0 = bLoc
            local goals, inStep, turned, depth = {}, {}, 0, {}
            local function add(kind, i)
                goals[#goals + 1] = { kind = kind, i = i }
                inStep[i] = inStep[i] or {}
                inStep[i][kind] = true
            end
            local function accept(i)
                add("A", i)
                -- a follow-up accepted in the same step has to be listed after the hand-in it needs
                local d = 0
                for _, j in ipairs(gSingle[i] or {}) do
                    if inStep[j] and inStep[j].T then d = math.max(d, (depth[j] or 0) + 1) end
                end
                for _, j in ipairs(gGroup[i]) do
                    if inStep[j] and inStep[j].T then d = math.max(d, (depth[j] or 0) + 1) end
                end
                depth[i] = d
                state[i] = 1
                inLog = inLog + 1
                for j in pairs(excl[i] or {}) do
                    if state[j] == 0 then state[j] = -1; alive = alive - 1 end
                end
                local q = list[i]
                if not q.hasC then state[i] = 2
                elseif not q.c then add("C", i); state[i] = 2 end    -- no known spot: do it on the spot
            end
            local function complete(i) add("C", i); state[i] = 2 end
            local function turnin(i)
                add("T", i)
                state[i] = 3
                inLog = inLog - 1
                alive = alive - 1
                turned = turned + 1
            end
            if bKind == "A" then accept(bI) elseif bKind == "C" then complete(bI) else turnin(bI) end

            for _ = 1, 4 do
                local cands = {}
                for i = 1, n do
                    local s, q = state[i], list[i]
                    if q.chain == ck then
                        if s == 0 and inLog < LOG_CAP and q.lv <= simLevel and gateOk(i) then
                            local d = dist(loc0, q.a)
                            if d <= NPC_YARDS then cands[#cands + 1] = { d, i, "A" } end
                        elseif s == 1 then
                            local d = dist(loc0, q.c)
                            if d <= AREA_YARDS then cands[#cands + 1] = { d, i, "C" } end
                        elseif s == 2 then
                            local d = dist(loc0, q.t)
                            if d <= NPC_YARDS then cands[#cands + 1] = { d, i, "T" } end
                        end
                    end
                end
                if #cands == 0 or #goals >= MAX_GOALS then break end
                table.sort(cands, function(a, b)
                    if a[1] ~= b[1] then return a[1] < b[1] end
                    if list[a[2]].id ~= list[b[2]].id then return list[a[2]].id < list[b[2]].id end
                    return KIND_ORDER[a[3]] < KIND_ORDER[b[3]]
                end)
                local progressed = false
                for _, c in ipairs(cands) do
                    if #goals >= MAX_GOALS then break end
                    local i, kind = c[2], c[3]
                    if kind == "A" and state[i] == 0 and inLog < LOG_CAP and gateOk(i) then accept(i); progressed = true
                    elseif kind == "C" and state[i] == 1 then complete(i); progressed = true
                    elseif kind == "T" and state[i] == 2 then turnin(i); progressed = true end
                end
                if not progressed then break end
            end

            -- 3. write the step: hand in, pick up, then objectives
            local function key(g)
                local base
                if g.kind == "T" then base = (inStep[g.i].A or inStep[g.i].C) and 4 or 1
                else base = g.kind == "A" and 2 or 3 end
                return (depth[g.i] or 0) * 10 + base
            end
            table.sort(goals, function(a, b)
                local ka, kb = key(a), key(b)
                if ka ~= kb then return ka < kb end
                return list[a.i].id < list[b.i].id
            end)
            local step = { chain = ck, title = titleFor(goals, list) }
            local lo, hi, onlyC = MAX_LEVEL, 1, true
            for _, g in ipairs(goals) do
                step[#step + 1] = { GOAL[g.kind], list[g.i].id }
                lo, hi = math.min(lo, list[g.i].rl), math.max(hi, list[g.i].ql)
                if g.kind ~= "C" then onlyC = false end
            end
            if onlyC then step.note = ("Level %d-%d objectives"):format(lo, math.max(lo, hi)) end
            steps[#steps + 1] = step

            pos = loc0
            counter = counter + turned
            while counter >= levelsNeeded(simLevel) and simLevel < maxLv do
                counter = counter - levelsNeeded(simLevel)
                simLevel = simLevel + 1
            end
        end
    end

    -- anything the loop could not place (it should not happen): one step per quest
    for i = 1, n do
        if state[i] == 0 or state[i] == 1 or state[i] == 2 then
            local q = list[i]
            local step = { chain = q.chain, title = shorten(DB.QuestName(q.id) or "Quest") }
            if state[i] == 0 then step[#step + 1] = { "accept", q.id } end
            if q.hasC and state[i] < 2 then step[#step + 1] = { "complete", q.id } end
            step[#step + 1] = { "turnin", q.id }
            steps[#steps + 1] = step
        end
    end
    return steps
end
