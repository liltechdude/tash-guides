-- Query helper over the real QuestieDB data.
--   luajit tests/qlookup.lua q 783 7 15          -> quest details
--   luajit tests/qlookup.lua zone 12 [maxLevel]   -> quests whose starter spawns in AreaID 12
--   luajit tests/qlookup.lua npc 823              -> npc details
dofile((debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./") .. "qdb_harness.lua")

local cmd = arg[1]

local function npcLabel(id)
    local s = NpcDB.spawns(id) or {}
    local z, p = next(s)
    local loc = z and p[1] and ("%d@%.1f,%.1f"):format(z, p[1][1], p[1][2]) or "?"
    return ("%s[%d %s %s]"):format(NpcDB.name(id) or "?", id, tostring(NpcDB.friendlyToFaction(id)), loc)
end
local function objLabel(id)
    local s = ObjectDB.spawns(id) or {}
    local z, p = next(s)
    local loc = z and p[1] and ("%d@%.1f,%.1f"):format(z, p[1][1], p[1][2]) or "?"
    return ("obj:%s[%d %s]"):format(ObjectDB.name(id) or "?", id, loc)
end
local function givers(g)
    if not g then return "-" end
    local out = {}
    for _, id in ipairs(g[1] or {}) do out[#out + 1] = npcLabel(id) end
    for _, id in ipairs(g[2] or {}) do out[#out + 1] = objLabel(id) end
    for _, id in ipairs(g[3] or {}) do out[#out + 1] = "item:" .. tostring(ItemDB.name(id)) .. "[" .. id .. "]" end
    return table.concat(out, ", ")
end
local function list(t) if not t then return "-" end local o = {} for _, v in ipairs(t) do o[#o + 1] = tostring(v) end return table.concat(o, ",") end

local function quest(id)
    if not QuestDB.Exists(id) then print(id, "MISSING") return end
    local g = QuestDB.Get
    print(("%d %q lvl %d req %d races %d classes %d zone %d"):format(id, QuestDB.name(id), g(id, "questLevel"),
        g(id, "requiredLevel"), g(id, "requiredRaces"), g(id, "requiredClasses"), g(id, "zoneOrSort")))
    print("   start: " .. givers(g(id, "startedBy")))
    print("   end:   " .. givers(g(id, "finishedBy")))
    print("   pre1: " .. list(g(id, "preQuestSingle")) .. "  preAll: " .. list(g(id, "preQuestGroup")) ..
        "  next: " .. tostring(g(id, "nextQuestInChain")) .. " excl: " .. list(g(id, "exclusiveTo")) ..
        " flags " .. g(id, "questFlags") .. "/" .. g(id, "specialFlags"))
    local o = g(id, "objectives")
    if o then
        local parts = {}
        for _, r in ipairs(o[1] or {}) do parts[#parts + 1] = "kill " .. tostring(NpcDB.name(r[1])) .. "[" .. r[1] .. "]" end
        for _, r in ipairs(o[2] or {}) do parts[#parts + 1] = "obj " .. tostring(ObjectDB.name(r[1])) .. "[" .. r[1] .. "]" end
        for _, r in ipairs(o[3] or {}) do parts[#parts + 1] = "item " .. tostring(ItemDB.name(r[1])) .. "[" .. r[1] .. "]" end
        for _, r in ipairs(o[5] or {}) do parts[#parts + 1] = "credit " .. tostring(r[3]) end
        print("   obj: " .. table.concat(parts, "; "))
    end
end

if cmd == "q" then
    for i = 2, #arg do quest(tonumber(arg[i])) end
elseif cmd == "npc" then
    for i = 2, #arg do
        local id = tonumber(arg[i])
        print(npcLabel(id), "starts", list(NpcDB.questStarts(id)), "ends", list(NpcDB.questEnds(id)))
    end
elseif cmd == "zone" then
    local area, maxLevel = tonumber(arg[2]), tonumber(arg[3] or 99)
    local rows = {}
    for _, id in ipairs(QuestDB.GetAllIds()) do
        local sb = QuestDB.Get(id, "startedBy")
        local hit
        for _, nid in ipairs(sb and sb[1] or {}) do
            local s = NpcDB.spawns(nid)
            if s and s[area] then hit = npcLabel(nid) end
        end
        for _, oid in ipairs(sb and sb[2] or {}) do
            local s = ObjectDB.spawns(oid)
            if s and s[area] then hit = objLabel(oid) end
        end
        if hit and QuestDB.Get(id, "requiredLevel") <= maxLevel then
            rows[#rows + 1] = { id = id, lvl = QuestDB.Get(id, "questLevel"), hit = hit }
        end
    end
    table.sort(rows, function(a, b) if a.lvl ~= b.lvl then return a.lvl < b.lvl end return a.id < b.id end)
    for _, r in ipairs(rows) do
        print(("%5d L%-2d %-40s %s races=%d"):format(r.id, r.lvl, QuestDB.name(r.id), r.hit, QuestDB.Get(r.id, "requiredRaces")))
    end
end
