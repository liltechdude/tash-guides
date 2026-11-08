-- TashGuides arrow.lua: the waypoint arrow (direction, distance, ETA, arrival).

local TG = TashGuides
local WP = TG.Way
local A = {}
TG.Arrow = A

local frame, arrow, check, titleText, distText, hintText
local lastPos, lastTime, speed = nil, nil, 0

-- Green when on course, through yellow, to red when facing away.
local function headingColor(rel)
    local f = math.abs(rel) / math.pi -- 0 ahead .. 1 behind
    if f < 0.5 then
        return f * 2, 1, 0.1 + 0.2 * (1 - f * 2)
    end
    return 1, 1 - (f - 0.5) * 2, 0.1
end

local function update()
    local wp = WP.current
    if not wp or not TG.db.arrow.shown then frame:Hide() return end
    frame:Show()
    titleText:SetText(wp.title or "Waypoint")

    local yards, bearing = WP.VectorTo(wp.map, wp.x, wp.y)
    if not yards then
        arrow:Hide()
        check:Hide()
        distText:SetText("")
        local pmap = WP.PlayerMap()
        if not pmap then hintText:SetText("No position here (instance)")
        else hintText:SetText("Travel to " .. TG.Color(TG.C.gold, TG.MapName(wp.map))) end
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
        distText:SetText(TG.Color(TG.C.good, "Arrived"))
        hintText:SetText(wp.subtitle or "")
        return
    end
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
    TG.On("TG_SETTINGS", A.Refresh)
    A.Refresh()
end
