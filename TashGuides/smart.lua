-- TashGuides smart.lua: the Smart Guide. Works in any zone without hand-written data by
-- building steps live from QuestieDB and the quest log: hand in finished quests, work on
-- the nearest objectives, and pick up quests from nearby givers, ordered by distance.
--
-- Class and racial quests (chains.lua) are included unless the player opts out
-- (TG.db.includeChains): every one you can take is offered wherever its giver stands, not
-- just on the current map, and they rank ahead of ordinary quests at a similar distance so
-- a trainer's quest is never crowded out by nearby busywork.

local TG = TashGuides
local DB, QL, AV, WP = TG.DB, TG.QuestLog, TG.Avail, TG.Way

local MAX_STEPS = 10
local MAX_CHAIN_EXTRA = 4       -- chain tasks may extend the list past MAX_STEPS
local GROUP_YARDS = 30          -- tasks this close together become one step
local WEIGHT = { turnin = 0.6, accept = 0.85, complete = 1.0 }
local CHAIN_WEIGHT = 0.5        -- class / racial quests count as this much closer
local FAR = 1e6
local CHAIN_LABEL = { class = "Class quest", race = "Racial quest" }

local function giverPoints(list)
    local pts = {}
    for _, g in ipairs(list or {}) do for _, p in ipairs(g.points) do pts[#pts + 1] = p end end
    return pts
end

local function generate()
    local tasks = {}
    local level = UnitLevel("player") or 1

    local Chains = TG.Chains
    local include = TG.Guide.ChainsIncluded()
    for id, q in pairs(QL.quests) do
        if not q.failed and Chains.Allowed(id) then
            local kind, pts
            if q.complete then
                kind, pts = "turnin", giverPoints(DB.Finishers(id))
            else
                kind, pts = "complete", TG.Guide.ObjectivePoints(id)
            end
            local p, d
            if kind == "complete" then
                local cur = WP.current
                p, d = WP.PickSpawn(pts, cur and cur.source == "guide" and cur or nil)
            else
                p, d = WP.Nearest(pts)
            end
            tasks[#tasks + 1] = { kind = kind, quest = id, point = p, dist = d or FAR, chain = Chains.Kind(id) }
        end
    end

    local map, px, py = WP.PlayerPos()
    local size = map and WP.MapSize(map)
    local seenQuest = {}
    for _, e in ipairs(size and AV.ForMap(map) or {}) do
        local info = e.info
        local chain = Chains.Kind(e.quest)
        if (chain and include) or (not chain and AV.ShowOnMap(info) and (info.level or 0) <= level + 3) then
            local dx, dy = (e.x - px) * size[1], (e.y - py) * size[2]
            local d = math.sqrt(dx * dx + dy * dy)
            local prev = seenQuest[e.quest]
            if d and (not prev or d < prev.dist) then
                local t = { kind = "accept", quest = e.quest, point = e, dist = d, chain = chain }
                if prev then
                    for k, v in pairs(t) do prev[k] = v end
                else
                    seenQuest[e.quest] = t
                    tasks[#tasks + 1] = t
                end
            end
        end
    end

    -- Class / racial quests you can pick up anywhere (trainers in a city, a racial quest giver
    -- in another zone): measured through the map transforms, so they still get an arrow.
    if include then
        for kind, list in pairs(Chains.lists) do
            for _, qid in ipairs(list) do
                if not seenQuest[qid] and AV.IsAvailable(qid) then
                    local p, d = WP.Nearest(giverPoints(DB.Starters(qid)))
                    local t = { kind = "accept", quest = qid, point = p, dist = d or FAR, chain = kind }
                    seenQuest[qid] = t
                    tasks[#tasks + 1] = t
                end
            end
        end
    end

    for _, t in ipairs(tasks) do
        t.score = t.dist * (WEIGHT[t.kind] or 1) * (t.chain and CHAIN_WEIGHT or 1)
        -- unknown distance: keep chain tasks ahead of other unlocated ones
        if t.dist >= FAR and t.chain then t.score = FAR * 0.5 end
    end
    table.sort(tasks, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.quest < b.quest
    end)

    -- Group tasks that share a spot (one NPC handing out and taking several quests).
    local steps = {}
    for _, t in ipairs(tasks) do
        local placed = false
        if t.point then
            for _, s in ipairs(steps) do
                local a = s.anchor
                if a and a.map == t.point.map then
                    local size = WP.MapSize(a.map)
                    if size then
                        local dx, dy = (a.x - t.point.x) * size[1], (a.y - t.point.y) * size[2]
                        if dx * dx + dy * dy <= GROUP_YARDS * GROUP_YARDS then
                            s.goals[#s.goals + 1] = { type = t.kind, quest = t.quest }
                            placed = true
                            break
                        end
                    end
                end
            end
        end
        if not placed and (#steps < MAX_STEPS or (t.chain and #steps < MAX_STEPS + MAX_CHAIN_EXTRA)) then
            local where = t.dist < FAR and TG.FormatDistance(t.dist) .. " away" or (t.point and ("in " .. TG.MapName(t.point.map))) or nil
            if t.chain then where = CHAIN_LABEL[t.chain] .. (where and (" - " .. where) or "") end
            steps[#steps + 1] = { index = #steps + 1, anchor = t.point, chain = t.chain,
                goals = { { type = t.kind, quest = t.quest } }, title = where }
        end
    end
    -- Within a step: hand in first, then complete, then pick up.
    local order = { turnin = 1, complete = 2, accept = 3 }
    for _, s in ipairs(steps) do
        table.sort(s.goals, function(a, b) return order[a.type] < order[b.type] end)
    end
    if #steps == 0 then
        steps[1] = { index = 1, goals = { { type = "note",
            text = "Nothing nearby. Explore toward a town, or open /tg guides to pick a zone guide." } } }
    end
    return steps
end

TG.RegisterGuide({
    id = "SMART",
    title = "Smart Guide",
    subtitle = "nearest quests, live",
    dynamic = true,
    generate = generate,
})
