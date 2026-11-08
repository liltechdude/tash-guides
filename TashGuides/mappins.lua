-- TashGuides mappins.lua: quest pins on the world map and the minimap.
--   gold "!"  quest you can pick up      blue "!"  repeatable      grey "!"  low level
--   gold "?"  quest ready to turn in      colored dots: objectives (red kill, yellow loot,
--   blue object, purple explore)          ring: the active waypoint

local TG = TashGuides
local DB, QL, AV, WP, Guide = TG.DB, TG.QuestLog, TG.Avail, TG.Way, TG.Guide
local P = {}
TG.Pins = P

local cache = {}          -- map -> merged pin list
local STYLE = {
    available = { tex = TG.TEX.available, size = 18, color = TG.C.available },
    repeatable = { tex = TG.TEX.available, size = 18, color = TG.C.repeatable },
    trivial = { tex = TG.TEX.available, size = 15, color = TG.C.trivial },
    turnin = { tex = TG.TEX.turnin, size = 18, color = TG.C.turnin },
    monster = { tex = TG.TEX.dot, size = 10, color = TG.C.monster },
    item = { tex = TG.TEX.dot, size = 10, color = TG.C.item },
    object = { tex = TG.TEX.dot, size = 10, color = TG.C.object },
    event = { tex = TG.TEX.dot, size = 12, color = TG.C.event },
    waypoint = { tex = TG.TEX.target, size = 20, color = TG.C.accent },
}
local PRIORITY = { waypoint = 9, turnin = 8, available = 7, repeatable = 6, event = 5, monster = 4, item = 4, object = 4, trivial = 1 }

function P.Invalidate() wipe(cache) end

local function collect(map)
    local out, index = {}, {}
    local pins = TG.db.pins
    local function add(style, x, y, line, quest)
        local group = (style == "trivial" or style == "repeatable") and "available" or style
        local key = group .. math.floor(x * 300) .. ":" .. math.floor(y * 300)
        local p = index[key]
        if not p then
            p = { style = style, map = map, x = x, y = y, lines = {}, quests = {} }
            index[key] = p
            out[#out + 1] = p
        elseif PRIORITY[style] > PRIORITY[p.style] then
            p.style = style
        end
        if quest and p.quests[quest] then return end
        if quest then p.quests[quest] = true end
        p.lines[#p.lines + 1] = line
    end

    if pins.available then
        for _, e in ipairs(AV.ForMap(map) or {}) do
            local info = e.info
            if AV.ShowOnMap(info) then
                local style = (info.trivial and "trivial") or (info.repeatable and "repeatable") or "available"
                add(style, e.x, e.y, { quest = e.quest, kind = "available", who = e.giver }, e.quest)
            end
        end
    end

    for id, q in pairs(QL.quests) do
        if q.complete then
            if pins.turnins then
                for _, g in ipairs(DB.Finishers(id)) do
                    for _, pt in ipairs(g.points) do
                        if pt.map == map then add("turnin", pt.x, pt.y, { quest = id, kind = "turnin", who = g.name }, id) end
                    end
                end
            end
        elseif pins.objectives and not q.failed then
            local matched, sources = DB.MatchObjectives(id, q.objectives)
            local function addSource(s, o)
                for _, pt in ipairs(s.points) do
                    if pt.map == map then
                        add(s.kind, pt.x, pt.y, { quest = id, kind = "objective", text = o and o.text or s.name, who = s.name }, nil)
                    end
                end
            end
            if #q.objectives == 0 then
                for _, s in ipairs(sources) do addSource(s, nil) end
            else
                for i, o in ipairs(q.objectives) do
                    local s = matched[i]
                    if s and not o.finished then addSource(s, o) end
                end
            end
        end
    end
    -- draw low-priority pins first so important ones end up on top
    table.sort(out, function(a, b) return PRIORITY[a.style] < PRIORITY[b.style] end)
    return out
end

function P.ForMap(map)
    if not map then return {} end
    local c = cache[map]
    if not c then c = collect(map); cache[map] = c end
    return c
end

-- ---------------------------------------------------------------------------
-- Pin frames
-- ---------------------------------------------------------------------------

local function pinTooltip(pin)
    local data = pin.data
    if not data then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    if data.style == "waypoint" then
        local cur = WP.current
        GameTooltip:AddLine(cur and cur.title or "Waypoint", TG.C.accent[1], TG.C.accent[2], TG.C.accent[3])
        GameTooltip:Show()
        return
    end
    local lastQuest
    for i, line in ipairs(data.lines) do
        if i > 12 then GameTooltip:AddLine(("...and %d more"):format(#data.lines - 12), 0.6, 0.6, 0.6) break end
        local q = line.quest
        local name = DB.QuestName(q) or (QL.Get(q) and QL.Get(q).title) or ("Quest " .. tostring(q))
        local lvl = DB.QuestLevel(q)
        local c = TG.QuestColor(lvl)
        if line.kind == "available" then
            GameTooltip:AddDoubleLine("! " .. name .. (lvl > 0 and (" (" .. lvl .. ")") or ""), line.who or "", c[1], c[2], c[3], 0.8, 0.8, 0.8)
        elseif line.kind == "turnin" then
            GameTooltip:AddDoubleLine("? " .. name, "turn in to " .. (line.who or "?"), TG.C.gold[1], TG.C.gold[2], TG.C.gold[3], 0.8, 0.8, 0.8)
        else
            if lastQuest ~= q then GameTooltip:AddLine(name, c[1], c[2], c[3]) end
            GameTooltip:AddLine("   " .. (line.text or ""), 1, 1, 1)
        end
        lastQuest = q
    end
    GameTooltip:AddLine("Click: set waypoint", 0.25, 0.85, 0.6)
    GameTooltip:Show()
end

local function pinClick(pin)
    local data = pin.data
    if not data or data.style == "waypoint" then return end
    local line = data.lines[1]
    local name = line and (DB.QuestName(line.quest) or "Quest") or "Quest"
    local verb = line and (line.kind == "available" and "Pick up " or line.kind == "turnin" and "Turn in " or "") or ""
    WP.Set({ map = data.map, x = data.x, y = data.y, source = "pin", title = verb .. name, subtitle = line and line.who })
end

local function newPin(parent, pool)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(16, 16)
    pin.tex = pin:CreateTexture(nil, "ARTWORK")
    pin.tex:SetAllPoints()
    pin:SetScript("OnEnter", pinTooltip)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:SetScript("OnClick", pinClick)
    pool[#pool + 1] = pin
    return pin
end

local function stylePin(pin, data, scale)
    local s = STYLE[data.style] or STYLE.monster
    pin.data = data
    pin.tex:SetTexture(s.tex)
    pin.tex:SetVertexColor(s.color[1], s.color[2], s.color[3])
    local size = s.size * scale
    pin:SetSize(size, size)
end

-- ---------------------------------------------------------------------------
-- World map
-- ---------------------------------------------------------------------------

local worldPool, worldUsed = {}, 0

local function worldCanvas()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    return sc and sc.Child, sc
end

function P.RefreshWorld()
    local child, sc = worldCanvas()
    if not child then return end
    for i = 1, worldUsed do worldPool[i]:Hide() end
    worldUsed = 0
    if not (TG.db.pins.world and WorldMapFrame:IsShown()) then return end
    local map = WorldMapFrame:GetMapID()
    if not map then return end
    local w, h = child:GetSize()
    local canvasScale = (sc.GetCanvasScale and sc:GetCanvasScale()) or 1
    local scale = TG.db.pins.scale / canvasScale
    local level = child:GetFrameLevel() + 300
    local list = P.ForMap(map)
    local wpPin
    local cur = WP.current
    if cur then
        local tx, ty = cur.x, cur.y
        if cur.map ~= map then tx, ty = WP.Translate(cur.map, cur.x, cur.y, map) end
        if tx and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then
            wpPin = { style = "waypoint", map = map, x = tx, y = ty, lines = {} }
        end
    end
    local n = #list + (wpPin and 1 or 0)
    for i = 1, n do
        local data = list[i] or wpPin
        worldUsed = worldUsed + 1
        local pin = worldPool[worldUsed] or newPin(child, worldPool)
        stylePin(pin, data, scale)
        pin:SetFrameLevel(level + (PRIORITY[data.style] or 0))
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", child, "TOPLEFT", data.x * w, -data.y * h)
        pin:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------

local miniPool, miniUsed = {}, 0
local MINIMAP_DIAMETER = { 466.67, 400, 333.33, 266.67, 200, 133.33 } -- yards per zoom level, outdoors

local function minimapRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local r = TG.Safe(C_Minimap.GetViewRadius())
        if type(r) == "number" and r > 0 then return r end
    end
    local zoom = TG.Safe(Minimap:GetZoom()) or 0
    return (MINIMAP_DIAMETER[zoom + 1] or 466.67) / 2
end

local function minimapRotates()
    local v = GetCVar and GetCVar("rotateMinimap")
    return v == "1"
end

local function placeOnMinimap(pin, east, south, radiusYards, rotate, facing, clamp)
    local half = Minimap:GetWidth() / 2
    local k = half / radiusYards
    local north = -south
    local sx, sy = east, north
    if rotate and facing then
        local c, s = math.cos(facing), math.sin(facing)
        sx, sy = east * c + north * s, -east * s + north * c
    end
    local dist = math.sqrt(sx * sx + sy * sy)
    if dist > radiusYards then
        if not clamp then return false end
        sx, sy = sx / dist * radiusYards * 0.93, sy / dist * radiusYards * 0.93
    end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", sx * k, sy * k)
    return true
end

function P.UpdateMinimap()
    for i = 1, miniUsed do miniPool[i]:Hide() end
    miniUsed = 0
    if not TG.db.pins.minimap then return end
    local map, px, py = WP.PlayerPos()
    if not map then return end
    local size = WP.MapSize(map)
    if not size then return end
    local radius = minimapRadius()
    local rotate = minimapRotates()
    local facing = rotate and TG.Facing() or nil
    local scale = TG.db.pins.minimapScale * 0.85
    local level = Minimap:GetFrameLevel() + 5
    local reach = radius * 1.05

    local function draw(data, x, y, clamp)
        local east, south = (x - px) * size[1], (y - py) * size[2]
        if not clamp and (math.abs(east) > reach or math.abs(south) > reach) then return end
        miniUsed = miniUsed + 1
        local pin = miniPool[miniUsed] or newPin(Minimap, miniPool)
        stylePin(pin, data, scale)
        pin:SetFrameLevel(level + (PRIORITY[data.style] or 0))
        if placeOnMinimap(pin, east, south, radius, rotate, facing, clamp) then
            pin:Show()
        else
            pin:Hide()
            miniUsed = miniUsed - 1
        end
    end

    for _, data in ipairs(P.ForMap(map)) do
        if miniUsed >= 120 then break end
        draw(data, data.x, data.y, false)
    end
    local cur = WP.current
    if cur then
        local tx, ty = WP.Translate(cur.map, cur.x, cur.y, map)
        if tx then draw({ style = "waypoint", map = map, x = tx, y = ty, lines = {} }, tx, ty, true) end
    end
end

-- ---------------------------------------------------------------------------

function P.Init()
    local function dirty()
        P.Invalidate()
        TG.Schedule("pins", 0.1, P.RefreshWorld)
    end
    TG.On("TG_QUESTLOG", dirty)
    TG.On("TG_AVAILABLE", dirty)
    TG.On("TG_SETTINGS", dirty)
    TG.On("TG_WAYPOINT", function() TG.Schedule("pins", 0.05, P.RefreshWorld) end)

    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function() TG.Schedule("pins", 0.05, P.RefreshWorld) end)
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function() TG.Schedule("pins", 0.01, P.RefreshWorld) end)
        end
        if WorldMapFrame.OnCanvasScaleChanged then
            hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function() TG.Schedule("pinscale", 0.01, P.RefreshWorld) end)
        end
    end

    local acc = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        P.UpdateMinimap()
    end)
end
