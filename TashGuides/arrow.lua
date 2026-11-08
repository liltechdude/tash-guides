-- TashGuides arrow.lua: the waypoint arrow (direction, distance, ETA, arrival).
-- For a quest objective the arrow turns into an objective-area display once you are among
-- the spawns you still need (TG.db.arrow.area yards of the nearest one): a ring in the
-- objective's pin color (red kill, yellow loot, blue object, purple explore) around the
-- matching icon, "IN OBJECTIVE AREA", and your live progress for that objective.

local TG = TashGuides
local WP = TG.Way
local A = {}
TG.Arrow = A

local frame, arrow, check, titleText, distText, hintText, area
local QL = TG.QuestLog
local lastPos, lastTime, speed = nil, nil, 0

local AREA_ICON = {
    monster = "Interface\\Icons\\Ability_SteelMelee",
    item = "Interface\\Icons\\INV_Misc_Bag_10",
    object = "Interface\\Icons\\INV_Misc_Gear_01",
    event = "Interface\\Icons\\INV_Misc_Map_01",
}
local AREA_HINT = { monster = "Kill", item = "Loot", object = "Use / collect", event = "Explore" }

-- Objective-area lookup, recomputed when you move or every half second (it walks spawn lists).
local areaCache = { at = 0 }
local function objectiveArea(wp)
    if not (wp.objective and wp.quest) then return nil end
    local map, px, py = WP.PlayerPos()
    local now = GetTime()
    local c = areaCache
    if c.wp == wp and c.map == map and c.x == px and c.y == py and now - c.at < 0.5 then return c.info end
    c.wp, c.map, c.x, c.y, c.at = wp, map, px, py, now
    c.info = TG.Guide.ObjectiveArea(wp.quest)
    return c.info
end

-- Green when on course, through yellow, to red when facing away.
local function headingColor(rel)
    local f = math.abs(rel) / math.pi -- 0 ahead .. 1 behind
    if f < 0.5 then
        return f * 2, 1, 0.1 + 0.2 * (1 - f * 2)
    end
    return 1, 1 - (f - 0.5) * 2, 0.1
end

-- Enter the area at the configured size; leave only a little further out, so standing on
-- the edge does not flicker between the two displays.
local function inArea(info)
    if not info then return false end
    local r = TG.db.arrow.area or 50
    return info.dist <= r or (A.state == "area" and info.dist <= r * 1.25)
end

local function showArea(wp, info)
    arrow:Hide()
    check:Hide()
    local color = TG.C[info.kind] or TG.C.monster
    area.ring:SetVertexColor(color[1], color[2], color[3])
    area.icon:SetTexture(AREA_ICON[info.kind] or AREA_ICON.monster)
    -- slow pulse so the state is visible at a glance
    local pulse = 0.65 + 0.35 * math.sin(GetTime() * 3)
    area.ring:SetAlpha(pulse)
    area.glow:SetVertexColor(color[1], color[2], color[3])
    area.glow:SetAlpha(0.25 * pulse)
    area:Show()
    titleText:SetText(info.title or wp.title or "Objective")
    distText:SetText(TG.Color(color, "IN OBJECTIVE AREA"))
    local o = info.objective
    local what
    if o and o.text and o.text ~= "" then
        what = TG.Color(TG.UI.ProgressColor(o), o.text)
    else
        what = AREA_HINT[info.kind] or "Objective"
    end
    local near = info.dist > (TG.db.arrow.arrival or 8)
        and TG.Color(TG.C.muted, "  -  nearest " .. TG.FormatDistance(info.dist)) or ""
    hintText:SetText(what .. near)
    if A.state ~= "area" and TG.db.sounds and PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then
        PlaySound(SOUNDKIT.MAP_PING)
    end
    A.state = "area"
end

local function update()
    local wp = WP.current
    if not wp or not TG.db.arrow.shown then frame:Hide() A.state = nil return end
    frame:Show()
    titleText:SetText(wp.title or "Waypoint")

    local info = objectiveArea(wp)
    if inArea(info) then showArea(wp, info) return end
    area:Hide()

    local yards, bearing = WP.VectorTo(wp.map, wp.x, wp.y)
    if not yards then
        arrow:Hide()
        check:Hide()
        distText:SetText("")
        local pmap = WP.PlayerMap()
        if not pmap then hintText:SetText("No position here (instance)")
        else hintText:SetText("Travel to " .. TG.Color(TG.C.gold, TG.MapName(wp.map))) end
        A.state = "travel"
        return
    end

    if WP.current ~= wp then return end -- cleared on arrival (checked by waypoint.lua's ticker)

    local now = GetTime()
    local map, px, py = WP.PlayerPos()
    if lastPos and lastTime and now > lastTime and map == lastPos[1] then
        local size = WP.MapSize(map)
        if size then
            local dx, dy = (px - lastPos[2]) * size[1], (py - lastPos[3]) * size[2]
            local inst = math.sqrt(dx * dx + dy * dy) / (now - lastTime)
            speed = speed * 0.8 + inst * 0.2
        end
    end
    lastPos, lastTime = { map, px, py }, now
    local unitSpeed = GetUnitSpeed and TG.Safe(GetUnitSpeed("player"))
    if type(unitSpeed) == "number" and unitSpeed > 0 then speed = unitSpeed end

    local radius = wp.radius or TG.db.arrow.arrival
    if yards <= radius then
        arrow:Hide()
        check:Show()
        distText:SetText(TG.Color(TG.C.good, wp.objective and "At the objective" or "Arrived"))
        hintText:SetText(wp.subtitle or "")
        A.state = "arrived"
        return
    end
    A.state = "arrow"
    check:Hide()
    arrow:Show()

    local facing = TG.Facing()
    if facing then
        local rel = TG.WrapAngle(bearing + facing)
        arrow:SetRotation(-rel)
        arrow:SetVertexColor(headingColor(rel))
    else
        arrow:SetRotation(0)
        arrow:SetVertexColor(0.6, 0.6, 0.6)
    end
    local eta = speed > 0.5 and (yards / speed) or nil
    distText:SetText(TG.FormatDistance(yards) .. (eta and TG.Color(TG.C.muted, "   " .. TG.FormatTime(eta)) or ""))
    hintText:SetText(wp.subtitle or "")
end

function A.Refresh()
    if not frame then return end
    frame:SetScale(TG.db.arrow.scale)
    update()
end

function A.Init()
    frame = CreateFrame("Button", "TashGuidesArrow", UIParent)
    frame:SetSize(190, 104)
    frame:SetFrameStrata("MEDIUM")
    TG.RestorePosition(frame, "arrow", "TOP", "TOP", 0, -130)
    TG.MakeMovable(frame, "arrow", function() return TG.db.arrow.locked end)
    frame:RegisterForClicks("RightButtonUp")
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local cur = WP.current
            if cur and cur.source ~= "guide" then WP.Clear(cur.source)
            elseif cur then WP.Clear("guide") end
        end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local cur = WP.current
        GameTooltip:AddLine(cur and cur.title or "Waypoint", 1, 0.82, 0)
        if cur then GameTooltip:AddLine(("%s  %.1f, %.1f"):format(TG.MapName(cur.map), cur.x * 100, cur.y * 100), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine("Drag to move. Right-click to clear.", 0.25, 0.85, 0.6)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(56, 56)
    arrow:SetPoint("TOP", 0, -2)
    arrow:SetTexture(TG.TEX.arrow)

    -- objective-area display: tinted ring, soft glow, objective icon
    area = CreateFrame("Frame", nil, frame)
    area:SetSize(56, 56)
    area:SetPoint("TOP", 0, -2)
    area.glow = area:CreateTexture(nil, "BACKGROUND")
    area.glow:SetSize(64, 64)
    area.glow:SetPoint("CENTER")
    area.glow:SetTexture(TG.TEX.dot)
    area.ring = area:CreateTexture(nil, "ARTWORK")
    area.ring:SetAllPoints()
    area.ring:SetTexture(TG.TEX.target)
    area.icon = area:CreateTexture(nil, "OVERLAY")
    area.icon:SetSize(24, 24)
    area.icon:SetPoint("CENTER")
    area.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    area:Hide()

    check = frame:CreateTexture(nil, "ARTWORK")
    check:SetSize(40, 40)
    check:SetPoint("TOP", 0, -10)
    check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    check:Hide()

    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    titleText:SetWidth(240)
    titleText:SetWordWrap(false)
    distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    distText:SetPoint("TOP", titleText, "BOTTOM", 0, -2)
    hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("TOP", distText, "BOTTOM", 0, -1)
    hintText:SetWidth(240)
    hintText:SetWordWrap(false)

    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then return end
        acc = 0
        update()
    end)

    -- The OnUpdate stops while hidden, so wake the arrow when a waypoint appears.
    TG.On("TG_WAYPOINT", A.Refresh)
    -- A tracker / map-pin objective waypoint stays while you work the area; drop it once the
    -- quest is ready to hand in (or gone), and hand the arrow back to the guide.
    TG.On("TG_QUESTLOG", function()
        local cur = WP.current
        if cur and cur.objective and cur.quest and cur.source ~= "guide"
            and (not QL.InLog(cur.quest) or QL.IsReady(cur.quest)) then
            WP.Clear(cur.source)
        end
    end)
    TG.On("TG_SETTINGS", A.Refresh)
    A.Refresh()
end
