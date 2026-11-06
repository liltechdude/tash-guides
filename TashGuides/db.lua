-- TashGuides db.lua: QuestieDB access layer.
-- Uses only QuestieDB's public surface (contract 4): the QuestDB/NpcDB/ObjectDB/ItemDB entity
-- tables (Get, named getters, Exists, GetAllIds) and LibQuestieDB.Support zone tables.
-- Spawn coordinates in QuestieDB are 0-100 percentages keyed by AreaID; everything this file
-- hands out is converted to { map = UiMapID, x = 0..1, y = 0..1 } points the client can draw.

local TG = TashGuides
local DB = {}
TG.DB = DB

local Q, N, O, I
local areaToUi, uiToArea, subToParent = {}, {}, {}
local dungeonByArea = {}   -- dungeon AreaID (and its alternative ids) -> entrance points
local playerFactionLetter

local function loadMap(src)
    if type(src) == "string" then
        local f = loadstring(src)
        if not f then return nil end
        local ok, t = pcall(f)
        if ok and type(t) == "table" then return t end
        return nil
    end
    return type(src) == "table" and src or nil
end

local function merged(base, over)
    local t = {}
    if base then for k, v in pairs(base) do t[k] = v end end
    if over then for k, v in pairs(over) do t[k] = v end end
    return t
end

function DB.Init()
    if DB.ready then return true end
    local L = _G.LibQuestieDB
    if not L then return false, "QuestieDB is not loaded. Install/enable QuestieDB and /reload." end
    local ok, msg = L.RequireContract(4)
    if not ok then return false, msg end
    Q = L.Quest or _G.QuestDB
    N = L.Npc or _G.NpcDB
    O = L.Object or _G.ObjectDB
    I = L.Item or _G.ItemDB
    if not (Q and N and O and I) then return false, "QuestieDB entity tables are missing." end

    local zone = L.Support and L.Support.Get and L.Support.Get("ZoneDB")
    local p = zone and zone.private
    if p then
        areaToUi = merged(loadMap(p.areaIdToUiMapId), loadMap(p.areaIdToUiMapIdOverride))
        uiToArea = merged(loadMap(p.uiMapIdToAreaId), loadMap(p.uiMapIdToAreaIdOverride))
        subToParent = merged(loadMap(p.subZoneToParentZone), loadMap(p.subZoneToParentZoneOverride))
        if type(p.dungeons) == "table" then
            for areaId, entry in pairs(p.dungeons) do
                local pts = {}
                for _, loc in ipairs(entry[4] or {}) do
                    local ui = loc[1] and DB.UiMap(loc[1])
                    if ui and loc[2] and loc[3] then
                        pts[#pts + 1] = { map = ui, x = loc[2] / 100, y = loc[3] / 100, dungeon = entry[1] }
                    end
                end
                if #pts > 0 then
                    dungeonByArea[areaId] = pts
                    for _, alt in ipairs(entry[2] or {}) do dungeonByArea[alt] = pts end
                end
            end
        end
    end

    local faction = UnitFactionGroup("player")
    playerFactionLetter = faction == "Horde" and "H" or (faction == "Alliance" and "A") or nil
    DB.Q, DB.N, DB.O, DB.I = Q, N, O, I
    DB.ready = true
    return true
end

-- ---------------------------------------------------------------------------
-- Field access. Unknown ids read as nil.
-- ---------------------------------------------------------------------------

function DB.QuestExists(id) return id and Q.Exists(id) or false end
function DB.Quest(id, key) if not (id and Q.Exists(id)) then return nil end return Q.Get(id, key) end
function DB.QuestName(id) return DB.Quest(id, "name") end
function DB.QuestLevel(id) return DB.Quest(id, "questLevel") or 0 end
function DB.QuestIds() return Q.GetAllIds() end

function DB.Npc(id, key) if not (id and N.Exists(id)) then return nil end return N.Get(id, key) end
function DB.NpcName(id) return DB.Npc(id, "name") end
function DB.Object(id, key) if not (id and O.Exists(id)) then return nil end return O.Get(id, key) end
function DB.ObjectName(id) return DB.Object(id, "name") end
function DB.Item(id, key) if not (id and I.Exists(id)) then return nil end return I.Get(id, key) end
function DB.ItemName(id) return DB.Item(id, "name") end

-- Repeatable quests carry specialFlags bit 1.
function DB.IsRepeatable(id) return TG.HasBit(DB.Quest(id, "specialFlags") or 0, 1) end

-- ---------------------------------------------------------------------------
-- Zones
-- ---------------------------------------------------------------------------

function DB.ParentArea(area) return area and (subToParent[area] or area) end

function DB.UiMap(area)
    if not area then return nil end
    local ui = areaToUi[area]
    if ui == nil then ui = areaToUi[DB.ParentArea(area)] end
    if ui and ui > 0 then return ui end
    return nil
end

function DB.AreaForMap(ui) return ui and uiToArea[ui] end

-- ---------------------------------------------------------------------------
-- Points
-- ---------------------------------------------------------------------------

-- Convert a QuestieDB spawn table {[AreaID] = {{x, y}, ...}} into drawable points, appending
-- to `out`. Spawns inside a dungeon become the dungeon's entrance on the outdoor map.
function DB.SpawnPoints(spawns, out, cap)
    out = out or {}
    if type(spawns) ~= "table" then return out end
    cap = cap or 400
    for area, pts in pairs(spawns) do
        local dungeon = dungeonByArea[area]
        if dungeon then
            for _, e in ipairs(dungeon) do
                out[#out + 1] = { map = e.map, x = e.x, y = e.y, dungeon = e.dungeon }
            end
        else
            local ui = DB.UiMap(area)
            if ui and type(pts) == "table" then
                for _, pt in ipairs(pts) do
                    if #out >= cap then return out end
                    local x, y = pt[1], pt[2]
                    if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                        out[#out + 1] = { map = ui, x = x / 100, y = y / 100 }
                    end
                end
            end
        end
    end
    return out
end

local npcPointCache, objectPointCache = {}, {}

function DB.NpcPoints(id)
    local c = npcPointCache[id]
    if c == nil then
        c = DB.SpawnPoints(DB.Npc(id, "spawns"))
        npcPointCache[id] = c
    end
    return c
end

function DB.ObjectPoints(id)
    local c = objectPointCache[id]
    if c == nil then
        c = DB.SpawnPoints(DB.Object(id, "spawns"))
        objectPointCache[id] = c
    end
    return c
end

-- NPCs hostile to the player's faction cannot hand out or accept quests.
function DB.NpcFriendly(id)
    local f = DB.Npc(id, "friendlyToFaction")
    if type(f) ~= "string" or not playerFactionLetter then return true end
    return f:find(playerFactionLetter, 1, true) ~= nil
end

-- Quest givers ({{npcIds}, {objectIds}, {itemIds}}) as a list of
-- { kind = "npc"|"object"|"item", id, name, points }.
local function givers(g)
    local out = {}
    if type(g) ~= "table" then return out end
    for _, id in ipairs(g[1] or {}) do
        if DB.NpcFriendly(id) then
            out[#out + 1] = { kind = "npc", id = id, name = DB.NpcName(id) or "?", points = DB.NpcPoints(id) }
        end
    end
    for _, id in ipairs(g[2] or {}) do
        out[#out + 1] = { kind = "object", id = id, name = DB.ObjectName(id) or "?", points = DB.ObjectPoints(id) }
    end
    for _, id in ipairs(g[3] or {}) do
        out[#out + 1] = { kind = "item", id = id, name = DB.ItemName(id) or "?", points = {} }
    end
    return out
end

local starterCache, finisherCache = {}, {}

function DB.Starters(qid)
    local c = starterCache[qid]
    if not c then c = givers(DB.Quest(qid, "startedBy")); starterCache[qid] = c end
    return c
end

function DB.Finishers(qid)
    local c = finisherCache[qid]
    if not c then c = givers(DB.Quest(qid, "finishedBy")); finisherCache[qid] = c end
    return c
end

function DB.GiverName(list)
    local g = list and list[1]
    return g and g.name or nil
end

-- ---------------------------------------------------------------------------
-- Objectives
-- QuestieDB objectives: { creatures {{id, text?}}, objects {{id, text?}}, items {{id, text?}},
-- reputation {factionId, value}, killCredit {{{ids}, baseId, text}}, ... }, plus triggerEnd
-- {text, spawns} for exploration/event objectives.
-- Each source returned here: { kind, name, ids = {npc/object ids}, points, itemId? }.
-- ---------------------------------------------------------------------------

local objectiveCache = {}

local function itemSources(itemId, src)
    local drops = DB.Item(itemId, "npcDrops")
    if drops then
        for _, id in ipairs(drops) do
            src.npcs[#src.npcs + 1] = id
            DB.SpawnPoints(DB.Npc(id, "spawns"), src.points)
        end
    end
    local odrops = DB.Item(itemId, "objectDrops")
    if odrops then
        for _, id in ipairs(odrops) do
            src.objects[#src.objects + 1] = id
            DB.SpawnPoints(DB.Object(id, "spawns"), src.points)
        end
    end
    if #src.points == 0 then
        local vendors = DB.Item(itemId, "vendors")
        if vendors then
            for _, id in ipairs(vendors) do
                src.npcs[#src.npcs + 1] = id
                DB.SpawnPoints(DB.Npc(id, "spawns"), src.points)
            end
        end
    end
end

function DB.Objectives(qid)
    local c = objectiveCache[qid]
    if c then return c end
    c = {}
    local o = DB.Quest(qid, "objectives")
    if type(o) == "table" then
        for _, row in ipairs(o[1] or {}) do
            local id = row[1]
            c[#c + 1] = { kind = "monster", name = DB.NpcName(id) or row[2] or "?", npcs = { id }, objects = {},
                points = DB.SpawnPoints(DB.Npc(id, "spawns")) }
        end
        for _, row in ipairs(o[2] or {}) do
            local id = row[1]
            c[#c + 1] = { kind = "object", name = row[2] or DB.ObjectName(id) or "?", npcs = {}, objects = { id },
                points = DB.SpawnPoints(DB.Object(id, "spawns")) }
        end
        for _, row in ipairs(o[3] or {}) do
            local id = row[1]
            local src = { kind = "item", name = DB.ItemName(id) or row[2] or "?", itemId = id, npcs = {}, objects = {}, points = {} }
            itemSources(id, src)
            c[#c + 1] = src
        end
        for _, row in ipairs(o[5] or {}) do
            local ids = type(row[1]) == "table" and row[1] or {}
            local src = { kind = "monster", name = row[3] or DB.NpcName(row[2]) or "?", npcs = {}, objects = {}, points = {} }
            for _, id in ipairs(ids) do
                src.npcs[#src.npcs + 1] = id
                DB.SpawnPoints(DB.Npc(id, "spawns"), src.points)
            end
            c[#c + 1] = src
        end
    end
    local trig = DB.Quest(qid, "triggerEnd")
    if type(trig) == "table" and type(trig[2]) == "table" then
        c[#c + 1] = { kind = "event", name = trig[1] or "Explore", npcs = {}, objects = {}, points = DB.SpawnPoints(trig[2]) }
    end
    objectiveCache[qid] = c
    return c
end

-- Pair the client's objective lines (text like "Kobold Vermin slain: 3/10") with database
-- sources: by name first, then by order within the remaining sources.
function DB.MatchObjectives(qid, logObjectives)
    local sources = DB.Objectives(qid)
    local used, out = {}, {}
    logObjectives = logObjectives or {}
    for i, lo in ipairs(logObjectives) do
        local text = (lo.text or ""):lower()
        for j, s in ipairs(sources) do
            if not used[j] and s.name and s.name ~= "?" and text:find(s.name:lower(), 1, true) then
                used[j] = true
                out[i] = s
                break
            end
        end
    end
    for i in ipairs(logObjectives) do
        if not out[i] then
            for j, s in ipairs(sources) do
                if not used[j] then used[j] = true; out[i] = s; break end
            end
        end
    end
    return out, sources
end
