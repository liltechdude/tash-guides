-- TashGuides waypoint.lua: player position, map math, and the single active waypoint.
-- Points are { map = UiMapID, x = 0..1, y = 0..1 }. Distances are yards from
-- C_Map.GetMapWorldSize; points on another map are translated through world coordinates.
-- Fires "TG_WAYPOINT" whenever the waypoint changes.

local TG = TashGuides
local WP = { current = nil }
TG.Way = WP

local sizeCache = {}

function WP.PlayerMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    return TG.Safe(C_Map.GetBestMapForUnit("player"))
end

-- map, x, y (0..1) or nil (instances, loading screens)
function WP.PlayerPos()
    local map = TG.Safe(WP.PlayerMap())
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    x, y = TG.Safe(x), TG.Safe(y)
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return map, x, y
end

function WP.MapSize(map)
    local s = sizeCache[map]
    if s == nil then
        s = false
        if C_Map and C_Map.GetMapWorldSize then
            local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
            if ok and w and h and w > 0 and h > 0 then s = { w, h } end
        end
        sizeCache[map] = s
    end
    return s or nil
end

-- Express a point from `fromMap` in `toMap` coordinates (may fall outside 0..1).
-- Every map pair is reduced to one cached affine transform, found with the first strategy
-- that works:
--   1. world frames: three corners of each map through C_Map.GetWorldPosFromMapPos (only
--      needs map -> world, which works for every outdoor map, and handles points far
--      outside the destination map - a quest giver three zones away);
--   2. the client's own C_Map.GetMapPosFromWorldPos (can refuse points outside the map);
--   3. a shared parent map (zone inside a continent) through C_Map.GetMapRectOnMap.
-- Without one the arrow can only say "travel to <zone>", so all three are tried.

-- Failed lookups are remembered for a short while only (the map API can be unavailable
-- during loading screens), successful ones for the session.
local RETRY = 30
local frameCache, failedAt = {}, {}
local function expired(key)
    local t = failedAt[key]
    return t and GetTime() - t > RETRY
end

local function worldFrame(map)
    local f = frameCache[map]
    if f ~= nil and not (f == false and expired("f" .. map)) then return f or nil end
    f = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local function probe(x, y)
            local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
            if ok and cont and pos and pos.GetXY then
                local a, b = pos:GetXY()
                if type(a) == "number" and type(b) == "number" then return cont, a, b end
            end
        end
        local c0, ox, oy = probe(0, 0)
        local c1, ux, uy = probe(1, 0)
        local c2, vx, vy = probe(0, 1)
        if c0 and c0 == c1 and c0 == c2 then
            ux, uy, vx, vy = ux - ox, uy - oy, vx - ox, vy - oy
            local det = ux * vy - uy * vx
            if det ~= 0 then f = { cont = c0, ox = ox, oy = oy, ux = ux, uy = uy, vx = vx, vy = vy, det = det } end
        end
    end
    frameCache[map] = f
    if not f then failedAt["f" .. map] = GetTime() end
    return f or nil
end

local function viaWorldFrames(fromMap, toMap)
    local a, b = worldFrame(fromMap), worldFrame(toMap)
    if not (a and b and a.cont == b.cont) then return nil end
    return function(x, y)
        local dx = a.ox + x * a.ux + y * a.vx - b.ox
        local dy = a.oy + x * a.uy + y * a.vy - b.oy
        return (dx * b.vy - dy * b.vx) / b.det, (b.ux * dy - b.uy * dx) / b.det
    end
end

local function viaClient(fromMap, toMap)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    return function(px, py)
        local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, fromMap, CreateVector2D(px, py))
        if not ok or not cont or not world then return nil end
        local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, toMap)
        if not ok2 or not pos then return nil end
        return pos:GetXY()
    end
end

local function parents(map)
    local out, seen = {}, {}
    while map and map > 0 and not seen[map] and C_Map and C_Map.GetMapInfo do
        seen[map] = true
        out[#out + 1] = map
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
    return out
end

-- Rectangle of `map` inside its ancestor `top` (0..1 of top), identity when they match.
local function rectOn(map, top)
    if map == top then return 0, 1, 0, 1 end
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local ok, x0, x1, y0, y1 = pcall(C_Map.GetMapRectOnMap, map, top)
    if ok and type(x0) == "number" and type(x1) == "number" and type(y0) == "number" and type(y1) == "number"
        and x1 ~= x0 and y1 ~= y0 then
        return x0, x1, y0, y1
    end
end

local function viaParent(fromMap, toMap)
    local up = {}
    for _, m in ipairs(parents(toMap)) do up[m] = true end
    for _, top in ipairs(parents(fromMap)) do
        if up[top] then
            local fx0, fx1, fy0, fy1 = rectOn(fromMap, top)
            local tx0, tx1, ty0, ty1 = rectOn(toMap, top)
            if not (fx0 and tx0) then return nil end
            return function(x, y)
                local ax, ay = fx0 + x * (fx1 - fx0), fy0 + y * (fy1 - fy0)
                return (ax - tx0) / (tx1 - tx0), (ay - ty0) / (ty1 - ty0)
            end
        end
    end
end

local transCache = {}
function WP.Translate(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    if not (fromMap and toMap) then return nil end
    local key = fromMap * 100000 + toMap
    local t = transCache[key]
    if t == nil or (t == false and expired(key)) then
        t = false
        for _, strategy in ipairs({ viaWorldFrames, viaClient, viaParent }) do
            local fn = strategy(fromMap, toMap)
            if fn then
                local ax, ay = fn(0, 0)
                local bx, by = fn(1, 0)
                local cx, cy = fn(0, 1)
                if ax and bx and cx then
                    local ux, uy, vx, vy = bx - ax, by - ay, cx - ax, cy - ay
                    if ux * vy - uy * vx ~= 0 then
                        t = { ax, ay, ux, uy, vx, vy }
                        break
                    end
                end
            end
        end
        transCache[key] = t
        if not t then failedAt[key] = GetTime() end
    end
    if not t then return nil end
    return t[1] + x * t[3] + y * t[5], t[2] + x * t[4] + y * t[6]
end

-- Drop every cached map transform (tests, or after the client's map data changes).
function WP.ForgetMaps() wipe(frameCache) wipe(transCache) wipe(failedAt) end

-- Yards and bearing (radians clockwise from north) from the player to a point, or nil.
function WP.VectorTo(map, x, y)
    local pmap, px, py = WP.PlayerPos()
    if not pmap then return nil end
    local tx, ty = WP.Translate(map, x, y, pmap)
    if not tx then return nil end
    local size = WP.MapSize(pmap)
    if not size then return nil end
    local east = (tx - px) * size[1]
    local south = (ty - py) * size[2]
    return math.sqrt(east * east + south * south), math.atan2(east, -south)
end

-- Yards between two points (any maps on the same continent), or nil.
function WP.Between(a, b)
    if not (a and b) then return nil end
    local bx, by = WP.Translate(b.map, b.x, b.y, a.map)
    local size = bx and WP.MapSize(a.map)
    if not size then return nil end
    local dx, dy = (bx - a.x) * size[1], (by - a.y) * size[2]
    return math.sqrt(dx * dx + dy * dy)
end

function WP.DistanceTo(p)
    if not p then return nil end
    return (WP.VectorTo(p.map, p.x, p.y))
end

-- Pick the closest point in a list (points on the player's map are preferred; other maps are
-- only measured when nothing is local). Returns point, yards.
function WP.Nearest(points)
    if not points or #points == 0 then return nil end
    local pmap, px, py = WP.PlayerPos()
    if not pmap then return points[1], nil end
    local size = WP.MapSize(pmap)
    local best, bestD
    for _, p in ipairs(points) do
        if p.map == pmap and size then
            local dx, dy = (p.x - px) * size[1], (p.y - py) * size[2]
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    if best then return best, math.sqrt(bestD) end
    -- Nothing on this map: measure every point through the (cached) map transform, so a
    -- turn-in two zones away still gets a direction instead of an arbitrary first entry.
    for _, p in ipairs(points) do
        local d = WP.DistanceTo(p)
        if d and (not bestD or d < bestD) then best, bestD = p, d end
    end
    if best then return best, bestD end
    return points[1], nil
end

-- ---------------------------------------------------------------------------
-- Spawn picking: for objectives with many spawn points (mobs, nodes, objects), the target is
-- the spawn with the lowest weighted distance rather than the plain nearest one:
--   * direction: a spawn straight ahead costs its distance; one directly behind costs
--     distance x (1 + forwardBias). Behind spawns still win when they are much closer.
--   * cleared: a spawn you have stood at recently is assumed done (killed, looted) and costs
--     extra for a few minutes, so the arrow moves on instead of pointing back at it.
--   * sticky: the current target is kept unless another spawn is clearly better, so turning
--     the camera or circling a mob does not make the arrow flicker between spawns.
-- ---------------------------------------------------------------------------

WP.VISIT_RADIUS = 15       -- yards: standing this close to a spawn counts as visiting it
WP.VISIT_TTL = 180         -- seconds a visited spawn stays discounted
WP.VISIT_PENALTY = 3       -- extra cost multiplier for a visited spawn once you walk away
WP.STICKY = 1.25           -- a new spawn must score this much better to replace the target

local visited = {}

local function pointKey(p) return ("%d:%.4f:%.4f"):format(p.map, p.x, p.y) end

-- Direction the player is heading, radians clockwise from north (same frame as VectorTo).
-- GetPlayerFacing is the character's facing, which follows the camera while steering with
-- the mouse and matches the direction of travel otherwise.
function WP.Heading()
    local f = TG.Facing()
    if not f then return nil end
    -- WoW facing is counter-clockwise from north; bearings here are clockwise.
    return (-f) % (math.pi * 2)
end

function WP.ForgetVisited() wipe(visited) end

-- Returns point, yards (true distance, not the weighted score).
function WP.PickSpawn(points, current)
    if not points or #points == 0 then return nil end
    local pmap, px, py = WP.PlayerPos()
    local size = pmap and WP.MapSize(pmap)
    if not size then return WP.Nearest(points) end

    local bias = TG.db.arrow.forwardBias or 2.5
    local heading = WP.Heading()
    local now = GetTime()
    local best, bestScore, bestD, curScore, curD
    local curKey = current and current.map == pmap and pointKey(current)

    for _, p in ipairs(points) do
        if p.map == pmap then
            local east, south = (p.x - px) * size[1], (p.y - py) * size[2]
            local d = math.sqrt(east * east + south * south)
            local key = pointKey(p)
            local score = d
            if d <= WP.VISIT_RADIUS then
                visited[key] = now
            else
                if heading and bias > 0 then
                    local off = TG.WrapAngle(math.atan2(east, -south) - heading)
                    -- 0 straight ahead .. 1 directly behind
                    score = score * (1 + bias * (1 - math.cos(off)) / 2)
                end
                local t = visited[key]
                if t then
                    if now - t < WP.VISIT_TTL then score = score * WP.VISIT_PENALTY else visited[key] = nil end
                end
            end
            if not bestScore or score < bestScore then best, bestScore, bestD = p, score, d end
            if key == curKey then curScore, curD = score, d end
        end
    end
    if not best then return WP.Nearest(points) end
    if curScore and curScore <= bestScore * WP.STICKY then
        for _, p in ipairs(points) do
            if p.map == pmap and pointKey(p) == curKey then return p, curD end
        end
    end
    return best, bestD
end

-- ---------------------------------------------------------------------------
-- Active waypoint
-- wp = { map, x, y, title, subtitle?, source = "guide"|"manual"|"tracker"|"pin", key?, onArrive?,
--        quest?, objective? (true: a quest objective - the arrow shows the objective area) }
-- A manual/tracker/pin waypoint wins over the guide's until it is reached or cleared.
-- ---------------------------------------------------------------------------

function WP.Set(wp)
    if not wp or not wp.map then return end
    local cur = WP.current
    if wp.source == "guide" and cur and cur.source ~= "guide" then
        WP.guidePending = wp
        return
    end
    if cur and cur.map == wp.map and cur.x == wp.x and cur.y == wp.y and cur.title == wp.title and cur.source == wp.source then
        return
    end
    -- A manual/pin waypoint parks the guide's target so it comes back afterwards.
    if cur and cur.source == "guide" and wp.source ~= "guide" then WP.guidePending = cur end
    WP.current = wp
    WP.arrived = false
    TG.Fire("TG_WAYPOINT", wp)
end

function WP.Clear(source)
    local cur = WP.current
    if source == "guide" then WP.guidePending = nil end
    if not cur then return end
    if source and cur.source ~= source and source ~= "any" then return end
    WP.current = nil
    WP.arrived = false
    if cur.source ~= "guide" and WP.guidePending then
        local g = WP.guidePending
        WP.guidePending = nil
        WP.Set(g)
    end
    TG.Fire("TG_WAYPOINT", nil)
end

-- Arrival is checked here, independent of the arrow, so hiding the arrow never stalls a guide.
C_Timer.NewTicker(0.2, function()
    local cur = WP.current
    if cur and TG.ready then WP.CheckArrival((WP.VectorTo(cur.map, cur.x, cur.y))) end
end)

-- Called with the measured distance to the active waypoint.
function WP.CheckArrival(yards)
    local cur = WP.current
    if not cur or not yards or WP.arrived then return end
    if yards <= (cur.radius or TG.db.arrow.arrival) then
        WP.arrived = true
        if cur.onArrive then
            local ok, err = pcall(cur.onArrive, cur)
            if not ok then TG.Report(err) end
        end
        -- A spot you picked is done once reached. An objective is not: the mobs or nodes are
        -- spread around, so it stays (as the objective area) until the quest is ready.
        if cur.source ~= "guide" and not cur.objective then
            if TG.db.sounds and PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then PlaySound(SOUNDKIT.MAP_PING) end
            WP.Clear(cur.source)
        end
        TG.Fire("TG_ARRIVED", cur)
    end
end
