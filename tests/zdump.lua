-- Dump every quest a faction can pick up in a zone, for writing curated guides by hand.
--   luajit tests/zdump.lua Alliance 40            -> Westfall (AreaID 40), all levels
--   luajit tests/zdump.lua Horde 17 10 25         -> The Barrens, quests needing level 10-25
-- Lists id, name, quest level / required level, race and class limits, giver and hand-in
-- (name [id] @x,y in AreaID), prerequisites, chain links and where the objectives are.
-- Repeatable and profession quests are marked, not hidden; "item" givers start from loot.
dofile((debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./") .. "qdb_harness.lua")

local faction, area = arg[1], tonumber(arg[2])
local minL, maxL = tonumber(arg[3] or 0), tonumber(arg[4] or 60)
assert(faction and area, "usage: zdump.lua Alliance|Horde AreaID [minReqLevel maxReqLevel]")
local FMASK = faction == "Horde" and 178 or 77
local FKEY = faction == "Horde" and "H" or "A"
local RACE = { [1] = "Hu", [2] = "Or", [4] = "Dw", [8] = "NE", [16] = "UD", [32] = "Ta", [64] = "Gn", [128] = "Tr" }
local CLASS = { [1] = "War", [2] = "Pal", [4] = "Hun", [8] = "Rog", [16] = "Pri", [64] = "Sha", [128] = "Mag", [256] = "Lck", [1024] = "Dru" }
local bit = require("bit")

local function bits(mask, names)
    if mask == 0 then return nil end
    local o = {}
    for b, n in pairs(names) do if bit.band(mask, b) ~= 0 then o[#o + 1] = n end end
    table.sort(o)
    return table.concat(o, "/")
end

local function centroid(spawns, wantArea)
    -- { [area] = {{x,y},...} } -> "x,y@area (n)" for the area with most points (prefer wantArea)
    if type(spawns) ~= "table" then return nil end
    local bestA, bestN
    for a, pts in pairs(spawns) do
        local n = #pts
        if a == wantArea then n = n + 100000 end
        if not bestN or n > bestN then bestA, bestN = a, n end
    end
    if not bestA then return nil end
    local pts = spawns[bestA]
    local sx, sy, n = 0, 0, 0
    for _, p in ipairs(pts) do if p[1] and p[1] > 0 then sx, sy, n = sx + p[1], sy + p[2], n + 1 end end
    if n == 0 then return ("@%d"):format(bestA) end
    return ("%.0f,%.0f@%d"):format(sx / n, sy / n, bestA) .. (n > 1 and ("x" .. n) or "")
end

local function npcAt(id)
    local s = NpcDB.spawns(id) or {}
    local p, a = nil, nil
    if s[area] and s[area][1] then a, p = area, s[area][1] else a, p = next(s) if p then p = p[1] end end
    return ("%s[%d%s]%s"):format(NpcDB.name(id) or "?", id, NpcDB.friendlyToFaction(id) and (" " .. NpcDB.friendlyToFaction(id)) or "",
        p and ("@%.1f,%.1f/%d"):format(p[1], p[2], a) or "")
end
local function objAt(id)
    local s = ObjectDB.spawns(id) or {}
    local p, a = nil, nil
    if s[area] and s[area][1] then a, p = area, s[area][1] else a, p = next(s) if p then p = p[1] end end
    return ("obj:%s[%d]%s"):format(ObjectDB.name(id) or "?", id, p and ("@%.1f,%.1f/%d"):format(p[1], p[2], a) or "")
end
local function who(g)
    if not g then return "-" end
    local o = {}
    for _, id in ipairs(g[1] or {}) do o[#o + 1] = npcAt(id) end
    for _, id in ipairs(g[2] or {}) do o[#o + 1] = objAt(id) end
    for _, id in ipairs(g[3] or {}) do o[#o + 1] = "item:" .. tostring(ItemDB.name(id)) .. "[" .. id .. "]" end
    return table.concat(o, " | ")
end
local function inArea(g)
    for _, id in ipairs(g and g[1] or {}) do local s = NpcDB.spawns(id) if s and s[area] then return true end end
    for _, id in ipairs(g and g[2] or {}) do local s = ObjectDB.spawns(id) if s and s[area] then return true end end
    return false
end
local function friendly(g)
    local any, ok = false, false
    for _, id in ipairs(g and g[1] or {}) do
        any = true
        local f = NpcDB.friendlyToFaction(id)
        if not f or f:find(FKEY) then ok = true end
    end
    return ok or not any
end

local function objectives(id)
    local o = QuestDB.Get(id, "objectives")
    local parts = {}
    if type(o) == "table" then
        for _, r in ipairs(o[1] or {}) do parts[#parts + 1] = ("kill %s %s"):format(NpcDB.name(r[1]) or "?", centroid(NpcDB.spawns(r[1]), area) or "?") end
        for _, r in ipairs(o[2] or {}) do parts[#parts + 1] = ("use %s %s"):format(ObjectDB.name(r[1]) or r[2] or "?", centroid(ObjectDB.spawns(r[1]), area) or "?") end
        for _, r in ipairs(o[3] or {}) do
            local where
            for _, nid in ipairs(ItemDB.Get and (ItemDB.Get(r[1], "npcDrops") or {}) or {}) do where = where or (tostring(NpcDB.name(nid)) .. " " .. (centroid(NpcDB.spawns(nid), area) or "?")) end
            for _, oid in ipairs(ItemDB.Get and (ItemDB.Get(r[1], "objectDrops") or {}) or {}) do where = where or (tostring(ObjectDB.name(oid)) .. " " .. (centroid(ObjectDB.spawns(oid), area) or "?")) end
            parts[#parts + 1] = ("loot %s (%s)"):format(ItemDB.name(r[1]) or "?", where or "?")
        end
        for _, r in ipairs(o[5] or {}) do parts[#parts + 1] = "credit " .. tostring(r[3]) end
    end
    local te = QuestDB.Get(id, "triggerEnd")
    if type(te) == "table" then parts[#parts + 1] = ("explore %s %s"):format(tostring(te[1]), centroid(te[2], area) or "?") end
    return table.concat(parts, "; ")
end

local function list(t) if not t or #t == 0 then return nil end local o = {} for _, v in ipairs(t) do o[#o + 1] = tostring(v) end return table.concat(o, ",") end

local rows = {}
for _, id in ipairs(QuestDB.GetAllIds()) do
    local sb = QuestDB.Get(id, "startedBy")
    local rl = QuestDB.Get(id, "requiredLevel") or 0
    local races = QuestDB.Get(id, "requiredRaces") or 0
    if inArea(sb) and rl >= minL and rl <= maxL and (races == 0 or bit.band(races, FMASK) ~= 0) and friendly(sb) then
        rows[#rows + 1] = { id = id, rl = rl, ql = QuestDB.Get(id, "questLevel") or 0 }
    end
end
table.sort(rows, function(a, b)
    if a.rl ~= b.rl then return a.rl < b.rl end
    if a.ql ~= b.ql then return a.ql < b.ql end
    return a.id < b.id
end)

for _, r in ipairs(rows) do
    local id, g = r.id, QuestDB.Get
    local tags = {}
    local races = g(id, "requiredRaces") or 0
    if races ~= 0 and bit.band(races, FMASK) ~= FMASK then tags[#tags + 1] = "races=" .. bits(bit.band(races, FMASK), RACE) end
    local cl = bits(g(id, "requiredClasses") or 0, CLASS)
    if cl then tags[#tags + 1] = "class=" .. cl end
    if bit.band(g(id, "specialFlags") or 0, 1) ~= 0 then tags[#tags + 1] = "REPEATABLE" end
    local sk = g(id, "requiredSkill")
    if type(sk) == "table" and sk[1] then tags[#tags + 1] = "skill=" .. sk[1] .. ":" .. tostring(sk[2]) end
    if (g(id, "parentQuest") or 0) > 0 then tags[#tags + 1] = "child" end
    local sort = g(id, "zoneOrSort")
    if sort and sort < 0 then tags[#tags + 1] = "sort=" .. sort end
    print(("%d %q L%d/r%d %s"):format(id, QuestDB.name(id), r.ql, r.rl, table.concat(tags, " ")))
    print("   from: " .. who(g(id, "startedBy")))
    print("   to:   " .. who(g(id, "finishedBy")))
    local links = {}
    if list(g(id, "preQuestSingle")) then links[#links + 1] = "pre1=" .. list(g(id, "preQuestSingle")) end
    if list(g(id, "preQuestGroup")) then links[#links + 1] = "preAll=" .. list(g(id, "preQuestGroup")) end
    if (g(id, "nextQuestInChain") or 0) > 0 then links[#links + 1] = "next=" .. g(id, "nextQuestInChain") end
    if list(g(id, "exclusiveTo")) then links[#links + 1] = "excl=" .. list(g(id, "exclusiveTo")) end
    if (g(id, "breadcrumbForQuestId") or 0) ~= 0 then links[#links + 1] = "breadcrumbFor=" .. g(id, "breadcrumbForQuestId") end
    if #links > 0 then print("   " .. table.concat(links, " ")) end
    local ob = objectives(id)
    if ob ~= "" then print("   obj:  " .. ob) end
end
print(("-- %d quests"):format(#rows))
