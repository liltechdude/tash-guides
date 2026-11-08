-- TashGuides smart.lua: the Smart Guide. Works in any zone without hand-written data by
-- building steps live from QuestieDB and the quest log: hand in finished quests, work on
-- objectives, and pick up quests from nearby givers.
--
-- Two ways to order the work (TG.db.smartRouting):
--   "linear"  (default) a fixed route, followed step by step like a written guide. The
--             route is planned nearest-first from where you stand; tasks that appear later
--             (a quest you just accepted, an objective that became a turn-in) are slotted in
--             where they add the least walking, but never ahead of the current step. The
--             current step stays put until every goal in it is done, however you wander.
--             Skip moves it to the end; Re-route plans again from your position.
--   "nearest" re-sorts every few seconds by distance, so the nearest task always leads.
--             The leader is sticky: another task has to be clearly closer to take over,
--             which stops it flipping between two tasks at about the same distance.
--
-- Class and racial quests (chains.lua) are included unless the player opts out
-- (TG.db.includeChains): every one you can take is offered wherever its giver stands, not
-- just on the current map, and in "nearest" mode they rank ahead of ordinary quests at a
-- similar distance so a trainer's quest is never crowded out by nearby busywork.

local TG = TashGuides
local DB, QL, AV, WP = TG.DB, TG.QuestLog, TG.Avail, TG.Way
local Smart = {}
TG.Smart = Smart

local MAX_STEPS = 10
local MAX_CHAIN_EXTRA = 4       -- chain tasks may extend the list past MAX_STEPS
local GROUP_YARDS = 30          -- tasks this close together become one step
local WEIGHT = { turnin = 0.6, accept = 0.85, complete = 1.0 }
local CHAIN_WEIGHT = 0.5        -- class / racial quests count as this much closer
local STICKY = 1.35             -- nearest mode: the leader keeps its place unless beaten by this factor
local FAR = 1e6
local CHAIN_LABEL = { class = "Class quest", race = "Racial quest" }

local function giverPoints(list)
    local pts = {}
    for _, g in ipairs(list or {}) do for _, p in ipairs(g.points) do pts[#pts + 1] = p end end
    return pts
end

local function keyOf(kind, quest) return kind .. ":" .. quest end

function Smart.Mode() return TG.db.smartRouting == "nearest" and "nearest" or "linear" end

local function route()
    local r = TG.char.smartRoute
    if type(r) ~= "table" or type(r.keys) ~= "table" then
        r = { keys = {}, anchors = {} }
        TG.char.smartRoute = r
    end
    r.anchors = r.anchors or {}
    return r
end

-- ---------------------------------------------------------------------------
-- Tasks: everything worth doing right now, keyed "kind:quest".
-- ---------------------------------------------------------------------------

local function collect()
    local tasks, byKey = {}, {}
    local level = UnitLevel("player") or 1
    local Chains = TG.Chains
    local include = TG.Guide.ChainsIncluded()
    local cur = WP.current

    local function add(t)
        t.key = keyOf(t.kind, t.quest)
        if byKey[t.key] then return byKey[t.key] end
        byKey[t.key] = t
        tasks[#tasks + 1] = t
        return t
    end

    for id, q in pairs(QL.quests) do
        if not q.failed and Chains.Allowed(id) then
            local kind, pts, p, d
            if q.complete then
                kind, pts = "turnin", giverPoints(DB.Finishers(id))
                p, d = WP.Nearest(pts)
            else
                kind, pts = "complete", TG.Guide.ObjectivePoints(id)
                p, d = WP.PickSpawn(pts, cur and cur.source == "guide" and cur or nil)
            end
            add({ kind = kind, quest = id, point = p, dist = d or FAR, chain = Chains.Kind(id), points = pts })
        end
    end

    local map, px, py = WP.PlayerPos()
    local size = map and WP.MapSize(map)
    for _, e in ipairs(size and AV.ForMap(map) or {}) do
        local info = e.info
        local chain = Chains.Kind(e.quest)
        if (chain and include) or (not chain and AV.ShowOnMap(info) and (info.level or 0) <= level + 3) then
            local dx, dy = (e.x - px) * size[1], (e.y - py) * size[2]
            local d = math.sqrt(dx * dx + dy * dy)
            local key = keyOf("accept", e.quest)
            local prev = byKey[key]
            if not prev then
                add({ kind = "accept", quest = e.quest, point = e, dist = d, chain = chain })
            elseif d < prev.dist then
                prev.point, prev.dist = e, d
            end
        end
    end

    -- Class / racial quests you can pick up anywhere (trainers in a city, a racial quest giver
    -- in another zone): measured through the map transforms, so they still get an arrow.
    if include then
        for kind, list in pairs(Chains.lists) do
            for _, qid in ipairs(list) do
                if not byKey[keyOf("accept", qid)] and AV.IsAvailable(qid) then
                    local p, d = WP.Nearest(giverPoints(DB.Starters(qid)))
                    add({ kind = "accept", quest = qid, point = p, dist = d or FAR, chain = kind })
                end
            end
        end
    end
    return tasks, byKey
end

-- ---------------------------------------------------------------------------
-- Ordering
-- ---------------------------------------------------------------------------

local function score(t)
    if t.dist >= FAR then return t.chain and FAR * 0.5 or FAR end
    return t.dist * (WEIGHT[t.kind] or 1) * (t.chain and CHAIN_WEIGHT or 1)
end

local function orderNearest(tasks)
    for _, t in ipairs(tasks) do t.score = score(t) end
    table.sort(tasks, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.quest < b.quest
    end)
    -- Sticky leader: keep the previous first task while it is still about as close as the best.
    local r = route()
    local lead = r.lead
    if lead and tasks[1] and tasks[1].key ~= lead then
        for i, t in ipairs(tasks) do
            if t.key == lead then
                if t.score <= tasks[1].score * STICKY then
                    table.remove(tasks, i)
                    table.insert(tasks, 1, t)
                end
                break
            end
        end
    end
    r.lead = tasks[1] and tasks[1].key or nil
    return tasks
end

-- Walking cost between two route stops; unknown (other continent, no location) is expensive
-- but finite, so such tasks drift to the end of the route instead of breaking it.
local UNKNOWN = 20000
local function cost(a, b)
    if not (a and b) then return UNKNOWN end
    return WP.Between(a, b) or UNKNOWN
end

local function playerPoint()
    local map, x, y = WP.PlayerPos()
    return map and { map = map, x = x, y = y } or nil
end

-- Plan a fresh route: greedy nearest-next from the player, so the order reads like a guide.
local function planFresh(tasks, r)
    local left = {}
    for _, t in ipairs(tasks) do left[#left + 1] = t end
    local at = playerPoint()
    wipe(r.keys)
    while #left > 0 do
        local bi, bc
        for i, t in ipairs(left) do
            local c = cost(at, t.point) * (WEIGHT[t.kind] or 1) * (t.chain and CHAIN_WEIGHT or 1)
            if not bc or c < bc then bi, bc = i, c end
        end
        local t = table.remove(left, bi)
        r.keys[#r.keys + 1] = t.key
        if t.point then at = t.point end
    end
end

-- Cheapest place for a new task, never before the current step (index 1).
local function insertCheapest(r, t, pointOf)
    local keys = r.keys
    if #keys == 0 then keys[1] = t.key return end
    local bestI, bestC
    for i = 2, #keys + 1 do
        local prev, nxt = pointOf(keys[i - 1]), keys[i] and pointOf(keys[i]) or nil
        local c = cost(prev, t.point) + (nxt and (cost(t.point, nxt) - cost(prev, nxt)) or 0)
        if not bestC or c < bestC then bestI, bestC = i, c end
    end
    table.insert(keys, bestI, t.key)
end

local function orderLinear(tasks, byKey)
    local r = route()
    -- Accept tasks fall out of the live list when you leave the giver's map; keep them in the
    -- route while the quest is still available, at the spot remembered when they joined.
    for i = #r.keys, 1, -1 do
        local k = r.keys[i]
        if not byKey[k] then
            local kind, q = k:match("^(%a+):(%d+)$")
            q = tonumber(q)
            local a = r.anchors[k]
            if kind == "accept" and q and a and AV.IsAvailable(q) and TG.Chains.Allowed(q) then
                local t = { kind = "accept", quest = q, key = k, point = a, dist = WP.DistanceTo(a) or FAR,
                    chain = TG.Chains.Kind(q) }
                byKey[k] = t
                tasks[#tasks + 1] = t
            else
                table.remove(r.keys, i)
                r.anchors[k] = nil
            end
        end
    end

    local inRoute = {}
    for _, k in ipairs(r.keys) do inRoute[k] = true end
    local fresh = {}
    for _, t in ipairs(tasks) do if not inRoute[t.key] then fresh[#fresh + 1] = t end end

    if #r.keys == 0 then
        planFresh(tasks, r)
    else
        -- Insert nearer newcomers first so later ones can chain off them.
        for _, t in ipairs(fresh) do t.score = score(t) end
        table.sort(fresh, function(a, b) return a.score < b.score end)
        local function pointOf(k)
            return r.anchors[k] or (byKey[k] and byKey[k].point)
        end
        for _, t in ipairs(fresh) do insertCheapest(r, t, pointOf) end
    end
    -- Remember where each stop is, so the order does not drift as spawns are re-picked.
    for _, k in ipairs(r.keys) do
        local t = byKey[k]
        if t and t.point and not r.anchors[k] then
            r.anchors[k] = { map = t.point.map, x = t.point.x, y = t.point.y }
        end
    end
    local out = {}
    for _, k in ipairs(r.keys) do out[#out + 1] = byKey[k] end
    return out
end

-- ---------------------------------------------------------------------------
-- Steps
-- ---------------------------------------------------------------------------

local function near(a, b)
    if not (a and b) then return false end
    local d = WP.Between(a, b)
    return d ~= nil and d <= GROUP_YARDS
end

local function stepTitle(t, linear, n)
    local where = t.dist < FAR and TG.FormatDistance(t.dist) .. " away" or (t.point and ("in " .. TG.MapName(t.point.map))) or nil
    if t.chain then where = CHAIN_LABEL[t.chain] .. (where and (" - " .. where) or "") end
    if linear then where = ("Route %d"):format(n) .. (where and (" - " .. where) or "") end
    return where
end

-- Linear: only consecutive route stops at the same spot share a step, so the order holds.
-- Nearest: any task near an existing step joins it (one NPC, several quests).
local function buildSteps(ordered, linear)
    local steps = {}
    local extra = 0
    for _, t in ipairs(ordered) do
        local host
        if linear then
            local last = steps[#steps]
            if last and near(last.anchor, t.point) then host = last end
        else
            for _, s in ipairs(steps) do
                if near(s.anchor, t.point) then host = s break end
            end
        end
        if host then
            host.goals[#host.goals + 1] = { type = t.kind, quest = t.quest }
            host.keys[#host.keys + 1] = t.key
        elseif linear or #steps < MAX_STEPS or (t.chain and #steps < MAX_STEPS + MAX_CHAIN_EXTRA) then
            if linear and #steps >= MAX_STEPS + MAX_CHAIN_EXTRA then
                extra = extra + 1
            else
                steps[#steps + 1] = { index = #steps + 1, anchor = t.point, chain = t.chain, keys = { t.key },
                    goals = { { type = t.kind, quest = t.quest } }, title = stepTitle(t, linear, #steps + 1) }
            end
        end
    end
    -- Within a step: hand in first, then complete, then pick up.
    local order = { turnin = 1, complete = 2, accept = 3 }
    for _, s in ipairs(steps) do
        table.sort(s.goals, function(a, b) return order[a.type] < order[b.type] end)
    end
    Smart.more = extra
    return steps
end

local function generate()
    local tasks, byKey = collect()
    local linear = Smart.Mode() == "linear"
    local ordered = linear and orderLinear(tasks, byKey) or orderNearest(tasks)
    Smart.count = #ordered
    local steps = buildSteps(ordered, linear)
    if #steps == 0 then
        steps[1] = { index = 1, keys = {}, goals = { { type = "note",
            text = "Nothing nearby. Explore toward a town, or open /tg guides to pick a zone guide." } } }
    end
    return steps
end

-- ---------------------------------------------------------------------------
-- Route controls (linear mode)
-- ---------------------------------------------------------------------------

local function refresh() if TG.Guide.active and TG.Guide.active.id == "SMART" then TG.Guide.Evaluate() end end

-- Move the current step to the end of the route.
function Smart.Skip()
    local r = route()
    local steps = TG.Guide.active and TG.Guide.active.id == "SMART" and TG.Guide.Steps() or {}
    local first = steps[1] and steps[1].keys or { r.keys[1] }
    local drop = {}
    for _, k in ipairs(first) do drop[k] = true end
    local kept, moved = {}, {}
    for _, k in ipairs(r.keys) do
        if drop[k] then moved[#moved + 1] = k else kept[#kept + 1] = k end
    end
    for _, k in ipairs(moved) do kept[#kept + 1] = k end
    r.keys = kept
    refresh()
end

-- Do a given step next (from the steps panel).
function Smart.Promote(si)
    local r = route()
    local step = TG.Guide.Steps()[si]
    if not step or not step.keys then return end
    local set = {}
    for _, k in ipairs(step.keys) do set[k] = true end
    local front, rest = {}, {}
    for _, k in ipairs(r.keys) do
        if set[k] then front[#front + 1] = k else rest[#rest + 1] = k end
    end
    for _, k in ipairs(rest) do front[#front + 1] = k end
    r.keys = front
    refresh()
end

-- Throw the route away and plan again from where you stand.
function Smart.Reroute()
    local r = route()
    wipe(r.keys)
    wipe(r.anchors)
    r.lead = nil
    refresh()
end

function Smart.SetMode(mode)
    TG.db.smartRouting = (mode == "nearest") and "nearest" or "linear"
    route().lead = nil
    TG.Fire("TG_SETTINGS")
    refresh()
end

TG.RegisterGuide({
    id = "SMART",
    title = "Smart Guide",
    subtitle = "your quests, routed",
    dynamic = true,
    generate = generate,
})
