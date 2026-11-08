-- TashGuides guide.lua: step-by-step guide engine.
--
-- A guide is registered with TG.RegisterGuide{ id, title, faction?, races?, minLevel, maxLevel,
-- area (default AreaID for "goto"), next?, steps = { step, ... } }.
-- A step is a table whose array part lists goals, plus optional title/note/class/race keys:
--   { {"turnin", 783}, {"accept", 7}, note = "Inside the abbey" , class = "WARRIOR" }
-- Goal types:
--   {"accept", questId}      done once the quest is in the log (or already turned in)
--   {"complete", questId}    done once every objective is finished
--   {"turnin", questId}      done once the quest is turned in
--   {"goto", x, y, text?, area = AreaID?}   done on arrival (0-100 coordinates)
--   {"talk", npcId, text?}   done when you open the NPC's gossip/quest window
--   {"level", n}             done at character level n
--   {"hearth", "Goldshire"}  done when you cast your Hearthstone
--   {"fly", "Stormwind"}     done when you board a flight
--   {"note", text}           information only
-- Quest goals this character can never do (other class/race) are hidden automatically; steps
-- left with nothing to do are skipped.
--
-- Steps tagged chain = "class" | "race" belong to a class or racial quest chain. Main guides
-- show them only while "include class & race quests" is on (TG.db.includeChains, opt-out);
-- the chains also exist as their own guides (chains.lua), which always show them.

local TG = TashGuides
local DB, QL, AV, WP = TG.DB, TG.QuestLog, TG.Avail, TG.Way
local Guide = { registry = {}, order = {}, active = nil, cursor = 1, view = nil }
TG.Guide = Guide

local QUEST_GOALS = { accept = true, complete = true, turnin = true }

function TG.RegisterGuide(def)
    if type(def) ~= "table" or not def.id then return end
    if not Guide.registry[def.id] then Guide.order[#Guide.order + 1] = def.id end
    Guide.registry[def.id] = def
end

-- ---------------------------------------------------------------------------
-- Compile raw steps into normalized goal tables (needs the database, so done on load).
-- ---------------------------------------------------------------------------

local function asSet(v)
    if not v then return nil end
    local s = {}
    if type(v) == "string" then s[v:upper()] = true
    else for _, x in ipairs(v) do s[tostring(x):upper()] = true end end
    return s
end

local function compileGoal(raw, def)
    local t = raw[1]
    local g = { type = t, optional = raw.optional }
    if QUEST_GOALS[t] then
        g.quest = tonumber(raw[2])
        g.text = raw[3]
    elseif t == "goto" then
        local area = raw.area or def.area
        g.map = raw.map or (area and DB.UiMap(area))
        g.x, g.y = (raw[2] or 0) / 100, (raw[3] or 0) / 100
        g.text = raw[4]
        g.radius = raw.radius
    elseif t == "talk" then
        g.npc = tonumber(raw[2])
        g.text = raw[3]
    elseif t == "level" then
        g.level = tonumber(raw[2]) or 1
    else
        g.text = raw[2]
    end
    return g
end

local function compile(def)
    if def.compiled then return def end
    -- Guides generated from QuestieDB (zones) build their steps the first time they are loaded.
    if def.build and not def.steps then def.steps = def.build() end
    local steps = {}
    for i, raw in ipairs(def.steps or {}) do
        local step = { index = i, title = raw.title, note = raw.note, goals = {},
            classes = asSet(raw.class), races = asSet(raw.race), chain = raw.chain, quest = raw.quest }
        for _, rg in ipairs(raw) do
            if type(rg) == "table" and rg[1] then step.goals[#step.goals + 1] = compileGoal(rg, def) end
        end
        steps[i] = step
    end
    -- where each quest is accepted: if the player walks past that step without taking the quest,
    -- its later complete / turn-in goals no longer wait on it (generated guides, see GoalStatus)
    if def.hideUnavailable then
        def.acceptStep = {}
        for si, step in ipairs(steps) do
            for _, goal in ipairs(step.goals) do
                if goal.type == "accept" and goal.quest and not def.acceptStep[goal.quest] then def.acceptStep[goal.quest] = si end
            end
        end
    end
    def.compiledSteps = steps
    def.compiled = true
    return def
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local function guideKey() return Guide.active and Guide.active.id or "?" end
local function goalKey(si, gi) return guideKey() .. ":" .. si .. ":" .. gi end
local function stepKey(si) return guideKey() .. ":" .. si end

function Guide.Steps()
    local g = Guide.active
    if not g then return {} end
    if g.dynamic then return g.steps or {} end
    return g.compiledSteps or {}
end

local function playerRaceFile() local _, r = UnitRace("player") return r and r:upper() end
local function playerClassFile() local _, c = UnitClass("player") return c and c:upper() end

-- "done" | "todo" | "na" (does not apply to this character) | "info"
function Guide.GoalStatus(si, gi, goal)
    local t = goal.type
    if goal.quest then
        local q = goal.quest
        if not AV.ForPlayer(q) then return "na" end
        if not QL.InLog(q) and not QL.IsCompleted(q) then
            -- the quest giver did not list it for this character: do not wait on it
            if AV.NotOffered(q) then return "na" end
            local g = Guide.active
            -- a quest that can no longer be taken (an exclusive one was done, it expired)
            if g and g.hideUnavailable then
                if AV.Gone(q) then return "na" end
                -- its pick-up is behind you and you never took it: nothing left to complete or hand in
                local at = t ~= "accept" and g.acceptStep and g.acceptStep[q]
                if at and at < Guide.cursor then return "na" end
            end
            -- class / racial quests left out of the main guides by the opt-out
            if g and not g.chain and not Guide.ChainsIncluded() and TG.Chains.Kind(q) then return "na" end
        end
        if t == "accept" then
            if QL.InLog(q) or QL.IsCompleted(q) then return "done" end
        elseif t == "complete" then
            if QL.IsReady(q) or QL.IsCompleted(q) then return "done" end
        elseif t == "turnin" then
            if QL.IsCompleted(q) then return "done" end
        end
        return "todo"
    elseif t == "level" then
        return (UnitLevel("player") or 1) >= goal.level and "done" or "todo"
    elseif t == "note" then
        return "info"
    end
    if goal.done or TG.char.manual[goalKey(si, gi)] then return "done" end
    return "todo"
end

-- Reasons a quest can never be picked up by this character any more.
local GONE = { exclusive = true, breadcrumb = true, expired = true, ["too high"] = true }

-- Are class/race chain steps part of the main guides right now?
function Guide.ChainsIncluded() return TG.db.includeChains ~= false end

-- "done" | "todo" | "na" | "click" (only notes left: the player confirms with Next)
function Guide.StepStatus(si)
    local step = Guide.Steps()[si]
    if not step then return "na" end
    if step.classes and not step.classes[playerClassFile() or ""] then return "na" end
    if step.races and not step.races[playerRaceFile() or ""] then return "na" end
    if step.chain and not Guide.active.chain and not Guide.ChainsIncluded() then return "na" end
    if step.quest and Guide.active.hideUnavailable and not QL.InLog(step.quest) and not QL.IsCompleted(step.quest) then
        local ok, why = AV.IsEligible(step.quest)
        if not ok and GONE[why] then return "na" end
    end
    if not Guide.active.dynamic and TG.char.skipped[stepKey(si)] then return "done" end
    local applicable, todo, info = 0, 0, 0
    for gi, goal in ipairs(step.goals) do
        local s = Guide.GoalStatus(si, gi, goal)
        if s == "info" then info = info + 1
        elseif s ~= "na" then
            applicable = applicable + 1
            if s == "todo" and not goal.optional then todo = todo + 1 end
        end
    end
    if applicable == 0 then
        if info == 0 then return "na" end
        return TG.char.manual[stepKey(si)] and "done" or "click"
    end
    return todo == 0 and "done" or "todo"
end

function Guide.Progress()
    local steps = Guide.Steps()
    local done, total = 0, 0
    for i = 1, #steps do
        local s = Guide.StepStatus(i)
        if s ~= "na" then
            total = total + 1
            if s == "done" then done = done + 1 end
        end
    end
    return done, total
end

function Guide.Finished()
    local g = Guide.active
    return g and not g.dynamic and Guide.cursor > #Guide.Steps()
end

-- ---------------------------------------------------------------------------
-- Text for the viewer
-- ---------------------------------------------------------------------------

local function questLabel(q)
    local name = DB.QuestName(q) or ("quest #" .. tostring(q))
    local lvl = DB.QuestLevel(q)
    return TG.Color(TG.QuestColor(lvl), name) .. (lvl > 0 and TG.Color(TG.C.muted, " (" .. lvl .. ")") or "")
end

function Guide.GoalText(goal)
    local t, q = goal.type, goal.quest
    if t == "accept" then
        local who = DB.GiverName(DB.Starters(q))
        return "Accept " .. questLabel(q) .. (who and TG.Color(TG.C.muted, " from " .. who) or "")
    elseif t == "complete" then
        return (goal.text or "Complete") .. " " .. questLabel(q)
    elseif t == "turnin" then
        local who = DB.GiverName(DB.Finishers(q))
        return "Turn in " .. questLabel(q) .. (who and TG.Color(TG.C.muted, " to " .. who) or "")
    elseif t == "goto" then
        local where = ("%.1f, %.1f"):format(goal.x * 100, goal.y * 100)
        return (goal.text and (goal.text .. " ") or "Go to ") .. TG.Color(TG.C.muted, where)
    elseif t == "talk" then
        return "Talk to " .. TG.Color(TG.C.gold, DB.NpcName(goal.npc) or "?") .. (goal.text and (" " .. goal.text) or "")
    elseif t == "level" then
        return ("Reach level %d %s"):format(goal.level, TG.Color(TG.C.muted, "(now " .. (UnitLevel("player") or 1) .. ")"))
    elseif t == "hearth" then
        return "Hearth to " .. TG.Color(TG.C.gold, goal.text or "your inn")
    elseif t == "fly" then
        return "Fly to " .. TG.Color(TG.C.gold, goal.text or "?")
    end
    return goal.text or ""
end

-- Objective lines (with progress) shown under a "complete" goal.
function Guide.GoalDetails(goal)
    if goal.type ~= "complete" or not goal.quest then return nil end
    local q = QL.Get(goal.quest)
    if not q then
        if QL.IsCompleted(goal.quest) then return nil end
        return { { text = "not in your quest log yet", finished = false } }
    end
    return q.objectives
end

-- Why an accept goal cannot be picked up yet ("level 4 required").
function Guide.GoalBlocked(goal)
    if goal.type ~= "accept" or not goal.quest then return nil end
    if QL.InLog(goal.quest) or QL.IsCompleted(goal.quest) then return nil end
    local ok, why = AV.IsEligible(goal.quest)
    if ok then return nil end
    if why == "level" then return "requires level " .. (DB.Quest(goal.quest, "requiredLevel") or "?") end
    if why == "prereq" then return "finish the earlier quests first" end
    if why == "not offered" then return "not offered to you yet" end
    return nil
end

-- ---------------------------------------------------------------------------
-- Locations
-- ---------------------------------------------------------------------------

local function giverPoints(list)
    local pts = {}
    for _, g in ipairs(list or {}) do for _, p in ipairs(g.points) do pts[#pts + 1] = p end end
    return pts
end

-- Points still worth visiting for an in-progress quest.
function Guide.ObjectivePoints(q)
    local entry = QL.Get(q)
    if not entry then return {} end
    local matched, sources = DB.MatchObjectives(q, entry.objectives)
    local pts = {}
    if #entry.objectives == 0 then
        for _, s in ipairs(sources) do for _, p in ipairs(s.points) do pts[#pts + 1] = p end end
        return pts
    end
    for i, lo in ipairs(entry.objectives) do
        local s = matched[i]
        if s and not lo.finished then for _, p in ipairs(s.points) do pts[#pts + 1] = p end end
    end
    return pts
end

-- The unfinished objective of an in-progress quest whose spawns are nearest to the player:
-- { quest, title, dist (yards to its nearest spawn), kind ("monster"|"item"|"object"|"event"),
--   objective (the quest log line, with text/have/need), point } or nil.
function Guide.ObjectiveArea(q)
    local entry = QL.Get(q)
    if not entry or entry.complete then return nil end
    local matched, sources = DB.MatchObjectives(q, entry.objectives)
    local best
    local function consider(points, kind, o)
        local p, d = WP.Nearest(points)
        if p and d and (not best or d < best.dist) then best = { dist = d, kind = kind, objective = o, point = p } end
    end
    if #entry.objectives == 0 then
        for _, s in ipairs(sources) do consider(s.points, s.kind, nil) end
    else
        for i, lo in ipairs(entry.objectives) do
            local s = matched[i]
            if s and not lo.finished then consider(s.points, s.kind, lo) end
        end
    end
    if best then best.quest, best.title = q, entry.title end
    return best
end

-- Where a goal sends the player: returns a point or nil.
function Guide.GoalLocation(goal)
    local t = goal.type
    if t == "goto" then
        return goal.map and { map = goal.map, x = goal.x, y = goal.y } or nil
    elseif t == "accept" then
        return (WP.Nearest(giverPoints(DB.Starters(goal.quest))))
    elseif t == "turnin" then
        return (WP.Nearest(giverPoints(DB.Finishers(goal.quest))))
    elseif t == "complete" then
        if not QL.InLog(goal.quest) or QL.IsReady(goal.quest) then return nil end
        local cur = WP.current
        return (WP.PickSpawn(Guide.ObjectivePoints(goal.quest), cur and cur.source == "guide" and cur or nil))
    elseif t == "talk" then
        return (WP.Nearest(DB.NpcPoints(goal.npc)))
    end
    return nil
end

local function plainText(s) return (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end

function Guide.WaypointFor(si, gi, goal)
    local p = Guide.GoalLocation(goal)
    if not p then return nil end
    local step = Guide.Steps()[si]
    return {
        map = p.map, x = p.x, y = p.y,
        title = plainText(Guide.GoalText(goal)),
        subtitle = p.dungeon and (p.dungeon .. " entrance") or (step and step.title),
        source = "guide",
        radius = goal.radius,
        quest = goal.quest,
        objective = goal.type == "complete" or nil,
        onArrive = goal.type == "goto" and function()
            if Guide.active and not Guide.active.dynamic then TG.char.manual[goalKey(si, gi)] = true end
            goal.done = true
            Guide.Evaluate()
        end or nil,
    }
end

-- Does the active guide follow a fixed order (written guides, the Smart Guide's linear route)?
function Guide.Ordered()
    local g = Guide.active
    if not g then return false end
    if not g.dynamic then return true end
    return g.id == "SMART" and TG.Smart and TG.Smart.Mode() == "linear"
end

-- Steps after the current one the arrow may borrow a target from.
local LOOKAHEAD = 4

-- The arrow follows the first goal of the current step that has a location. When the current
-- step has none (an item-started quest, a note to read, a quest that is not in the log yet),
-- it points at the next step that does instead of disappearing, labelled "Next: ...". The
-- Smart Guide considers every task it generated, nearest first.
function Guide.UpdateWaypoint()
    local steps = Guide.Steps()
    local si = Guide.cursor
    local dynamic = Guide.active and Guide.active.dynamic
    local last = dynamic and #steps or math.min(#steps, si + LOOKAHEAD)
    for s = si, last do
        local step = steps[s]
        local st = (s == si) and "todo" or Guide.StepStatus(s)
        if step and st == "todo" then
            for gi, goal in ipairs(step.goals) do
                if Guide.GoalStatus(s, gi, goal) == "todo" then
                    local wp = Guide.WaypointFor(s, gi, goal)
                    if wp then
                        if s ~= si and Guide.Ordered() then
                            wp.subtitle = "Next: " .. (step.title or ("step " .. s))
                            wp.ahead = true
                        end
                        WP.Set(wp)
                        return
                    end
                end
            end
        end
    end
    WP.Clear("guide")
end

-- Quest ids the current step works on (todo goals only), for the tracker.
function Guide.CurrentQuests()
    local out = {}
    local steps = Guide.Steps()
    local si = Guide.cursor
    local step = steps[si]
    if not step then return out end
    for gi, goal in ipairs(step.goals) do
        if goal.quest and Guide.GoalStatus(si, gi, goal) == "todo" then out[goal.quest] = goal.type end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Cursor
-- ---------------------------------------------------------------------------

local function save()
    local g = Guide.active
    if g and not g.dynamic then TG.char.cursor[g.id] = Guide.cursor end
end

local function skippable(si)
    local s = Guide.StepStatus(si)
    return s == "done" or s == "na"
end

function Guide.Evaluate()
    local g = Guide.active
    if not g then return end
    if g.dynamic then
        if g.generate then g.steps = g.generate() end
        Guide.cursor = 1
    elseif TG.db.autoAdvance then
        local steps = Guide.Steps()
        local before = Guide.cursor
        while Guide.cursor <= #steps and skippable(Guide.cursor) do Guide.cursor = Guide.cursor + 1 end
        if Guide.cursor ~= before then
            Guide.view = nil
            save()
            if TG.db.sounds and PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN and Guide.cursor <= #steps then
                PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
            end
        end
    end
    Guide.UpdateWaypoint()
    TG.Fire("TG_GUIDE")
end

-- system = true when the addon picks the guide (start-up, default), not the player.
-- keepSaved = true leaves the saved guide id alone (a saved zone guide that has not been
-- generated yet while a stand-in is shown).
function Guide.Load(id, system, keepSaved)
    local def = Guide.registry[id]
    if not def then TG.Print("no guide named %s", tostring(id)) return end
    if not def.dynamic then compile(def) end
    Guide.active = def
    if not keepSaved then TG.char.guide = id end
    if not system then TG.char.guideChosen = true end
    Guide.view = nil
    if def.dynamic then
        Guide.cursor = 1
    else
        Guide.cursor = TG.char.cursor[id] or 1
        -- Catch up on a fresh load: jump past steps already finished.
        local steps = Guide.Steps()
        if Guide.cursor > #steps + 1 then Guide.cursor = 1 end
    end
    WP.Clear("guide")
    Guide.Evaluate()
end

-- Browse to a step without moving the guide (past steps to review, future ones to preview).
function Guide.View(si)
    local g = Guide.active
    if not g or g.dynamic then return end
    local steps = Guide.Steps()
    if not si or si < 1 or si > #steps then return end
    Guide.view = (si ~= Guide.cursor) and si or nil
    TG.Fire("TG_GUIDE")
end

function Guide.Next()
    local g = Guide.active
    if not g then return end
    if g.dynamic then
        if g.id == "SMART" and TG.Smart.Mode() == "linear" then TG.Smart.Skip() else Guide.Evaluate() end
        return
    end
    local steps = Guide.Steps()
    if Guide.view then
        -- browsing: step forward through the guide, back to live when the cursor is reached
        local v = Guide.view + 1
        while v <= #steps and Guide.StepStatus(v) == "na" do v = v + 1 end
        if (Guide.view < Guide.cursor and v >= Guide.cursor) or v == Guide.cursor then
            Guide.view = nil
        elseif v <= #steps then
            Guide.view = v
        end
        TG.Fire("TG_GUIDE")
        return
    end
    -- Confirm a note-only step, or move ahead manually.
    TG.char.manual[stepKey(Guide.cursor)] = true
    if Guide.cursor <= #steps then Guide.cursor = Guide.cursor + 1 end
    while Guide.cursor <= #steps and Guide.StepStatus(Guide.cursor) == "na" do Guide.cursor = Guide.cursor + 1 end
    save()
    Guide.Evaluate()
end

function Guide.Prev()
    if not Guide.active or Guide.active.dynamic then return end
    local from = Guide.view or Guide.cursor
    local v = from - 1
    while v >= 1 and Guide.StepStatus(v) == "na" do v = v - 1 end
    if from > Guide.cursor and v <= Guide.cursor then
        Guide.view = nil
    elseif v >= 1 then
        Guide.view = v
    end
    TG.Fire("TG_GUIDE")
end

function Guide.Skip()
    local g = Guide.active
    if not g then return end
    if g.dynamic then
        if g.id == "SMART" then TG.Smart.Reroute() end
        return
    end
    TG.char.skipped[stepKey(Guide.cursor)] = true
    Guide.view = nil
    local steps = Guide.Steps()
    if Guide.cursor <= #steps then Guide.cursor = Guide.cursor + 1 end
    while Guide.cursor <= #steps and Guide.StepStatus(Guide.cursor) == "na" do Guide.cursor = Guide.cursor + 1 end
    save()
    Guide.Evaluate()
end

-- Jump the cursor to a step (from the viewer's step list).
function Guide.Goto(si)
    if not Guide.active or Guide.active.dynamic then return end
    local steps = Guide.Steps()
    if si < 1 or si > #steps then return end
    Guide.cursor = si
    Guide.view = nil
    save()
    Guide.UpdateWaypoint()
    TG.Fire("TG_GUIDE")
end

function Guide.Reset()
    local g = Guide.active
    if not g or g.dynamic then return end
    local prefix = g.id .. ":"
    for k in pairs(TG.char.manual) do if k:sub(1, #prefix) == prefix then TG.char.manual[k] = nil end end
    for k in pairs(TG.char.skipped) do if k:sub(1, #prefix) == prefix then TG.char.skipped[k] = nil end end
    for _, s in ipairs(Guide.Steps()) do for _, goal in ipairs(s.goals) do goal.done = nil end end
    TG.char.cursor[g.id] = 1
    Guide.cursor = 1
    Guide.view = nil
    Guide.Evaluate()
    TG.Print("restarted %s", g.title)
end

-- Toggle a manual goal (talk / hearth / fly / goto) from the viewer.
function Guide.ToggleGoal(si, gi)
    local step = Guide.Steps()[si]
    local goal = step and step.goals[gi]
    if not goal or goal.quest or goal.type == "level" or goal.type == "note" then return end
    local k = goalKey(si, gi)
    if TG.char.manual[k] or goal.done then
        TG.char.manual[k] = nil
        goal.done = nil
    else
        TG.char.manual[k] = true
    end
    Guide.Evaluate()
end

-- ---------------------------------------------------------------------------
-- Guide choice
-- ---------------------------------------------------------------------------

function Guide.Suits(def)
    if def.dynamic or def.chain then return true end
    local faction = UnitFactionGroup("player")
    if def.faction and def.faction ~= faction then return false end
    if def.races then
        local mine, ok = playerRaceFile(), false
        for _, r in ipairs(def.races) do if r:upper() == mine then ok = true end end
        if not ok then return false end
    end
    return true
end

local GROUP_ORDER = { smart = 1, curated = 2, zone = 3, class = 4, race = 5, prof = 6 }

-- "smart" | "curated" (hand-written) | "zone" (generated) | "class" | "race" | "prof"
function Guide.GroupOf(def)
    if def.group then return def.group end
    if def.chain then return def.chain end
    if def.dynamic then return "smart" end
    return "curated"
end

function Guide.List()
    local out = {}
    for _, id in ipairs(Guide.order) do
        local def = Guide.registry[id]
        if Guide.Suits(def) then out[#out + 1] = def end
    end
    table.sort(out, function(a, b)
        local ga, gb = GROUP_ORDER[Guide.GroupOf(a)], GROUP_ORDER[Guide.GroupOf(b)]
        if ga ~= gb then return ga < gb end
        if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
        return a.title < b.title
    end)
    return out
end

-- Where a guide with no explicit next one sends you when you finish it.
function Guide.NextOf(def)
    if not def then return nil end
    local n = def.next
    if n and Guide.registry[n] then return n end
    if def.nextFn then
        n = def.nextFn()
        if n and Guide.registry[n] then return n end
    end
    if not def.chain and not def.dynamic and Guide.registry.SMART then return "SMART" end
    return nil
end

function Guide.PickDefault()
    local level = UnitLevel("player") or 1
    local best
    for _, def in ipairs(Guide.List()) do
        if Guide.GroupOf(def) == "curated" and level >= (def.minLevel or 1) - 1 and level <= (def.maxLevel or 60) then
            compile(def)
            -- prefer race-specific guides, then the one with steps left
            if not best or (def.races and not best.races) then best = def end
        end
    end
    if best then return best.id end
    -- No hand-written guide fits: use the generated guide for the zone you stand in.
    local map = WP.PlayerMap()
    local zone = map and Guide.registry["ZONE_" .. map]
    if zone and level >= (zone.minLevel or 1) - 3 and level <= (zone.maxLevel or 60) + 2 then return zone.id end
    return "SMART"
end

-- Zone guides appear a moment after login (they are indexed in slices). A saved zone guide
-- is restored then; a character with no chosen guide is moved off the Smart Guide to the
-- guide for the zone it is standing in.
function Guide.OnZones()
    local pending = Guide.pending
    if pending then
        Guide.pending = nil
        if Guide.registry[pending] then Guide.Load(pending, true)
        elseif Guide.active then TG.char.guide = Guide.active.id end
        return
    end
    if not TG.char.guideChosen and Guide.active and Guide.active.id == "SMART" then
        local pick = Guide.PickDefault()
        if pick ~= "SMART" then Guide.Load(pick, true) end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local function npcIdFromUnit(unit) return TG.NpcIdFromGuid(UnitGUID(unit)) end

-- Flip "include class & race quests". Turning it back on rewinds a main guide to the first
-- chain step it passed while they were hidden, so nothing is silently skipped.
function Guide.SetChainsIncluded(on)
    TG.db.includeChains = on and true or false
    local g = Guide.active
    if on and g and not g.dynamic and not g.chain then
        for si = 1, Guide.cursor - 1 do
            local step = Guide.Steps()[si]
            if step.chain and Guide.StepStatus(si) == "todo" then
                Guide.cursor = si
                Guide.view = nil
                save()
                break
            end
        end
    end
    TG.Fire("TG_SETTINGS")
    Guide.Evaluate()
end

-- Recent quest activity (accepted / turned in), newest last, for the step history panel.
local HISTORY_MAX = 40
function Guide.Remember(kind, quest)
    local h = TG.char.history
    if not quest then return end
    local last = h[#h]
    if last and last.kind == kind and last.quest == quest then return end
    h[#h + 1] = { kind = kind, quest = quest, time = time and time() or 0,
        guide = Guide.active and Guide.active.id or nil }
    while #h > HISTORY_MAX do table.remove(h, 1) end
end

local function markCurrent(predicate)
    local steps = Guide.Steps()
    local step = steps[Guide.cursor]
    if not step then return end
    local changed = false
    for gi, goal in ipairs(step.goals) do
        if predicate(goal) and Guide.GoalStatus(Guide.cursor, gi, goal) == "todo" then
            if not Guide.active.dynamic then TG.char.manual[goalKey(Guide.cursor, gi)] = true end
            goal.done = true
            changed = true
        end
    end
    if changed then Guide.Evaluate() end
end

local function onInteract()
    local id = npcIdFromUnit("npc")
    if id then markCurrent(function(g) return g.type == "talk" and g.npc == id end) end
end

function Guide.Init()
    local id = TG.char.guide
    -- A character that already has a saved guide chose it (the flag did not exist before).
    if TG.char.guideChosen == nil then TG.char.guideChosen = id ~= nil end
    local pending
    if id and not Guide.registry[id] and id:find("^ZONE_") then pending, id = id, nil end
    if not id or not Guide.registry[id] then id = pending and "SMART" or Guide.PickDefault() end
    Guide.pending = pending
    Guide.Load(id, true, pending ~= nil)
    TG.On("TG_ZONES", Guide.OnZones)
    if TG.Zones and TG.Zones.ready then Guide.OnZones() end

    local function soon() TG.Schedule("guide", 0.1, Guide.Evaluate) end
    TG.On("TG_QUESTLOG", soon)
    TG.On("TG_QUEST_DONE", function(id) Guide.Remember("turnin", id) soon() end)
    TG.On("TG_QUEST_ACCEPTED", function(id) Guide.Remember("accept", id) end)
    TG.On("TG_AVAILABLE", function() if Guide.active and Guide.active.dynamic then soon() end end)
    TG.On("PLAYER_LEVEL_UP", function() TG.Schedule("guide", 0.5, Guide.Evaluate) end)
    TG.On("ZONE_CHANGED_NEW_AREA", soon)
    for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW" }) do
        TG.On(e, onInteract)
    end
    TG.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        unit, spellID = TG.Safe(unit), TG.Safe(spellID)
        if unit == "player" and (spellID == 8690 or spellID == 556) then
            markCurrent(function(g) return g.type == "hearth" end)
        end
    end)
    TG.On("PLAYER_CONTROL_LOST", function()
        C_Timer.After(1, function()
            if UnitOnTaxi and UnitOnTaxi("player") then markCurrent(function(g) return g.type == "fly" end) end
        end)
    end)

    -- Objective spawns are re-ranked as the player moves and turns: refresh the target every
    -- second (the Smart Guide rebuilds its whole list, so it only does that every 3 seconds).
    local acc, ticks = 0, 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        ticks = ticks + 1
        if not Guide.active then return end
        if Guide.active.dynamic then
            if ticks % 3 == 0 then Guide.Evaluate() end
        else
            local cur = WP.current
            if not cur or cur.source == "guide" then Guide.UpdateWaypoint() end
        end
    end)
end
