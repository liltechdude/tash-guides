-- TashGuides core: namespace, saved settings, event bus, shared helpers, slash commands.

local ADDON = ...
local TG = {}
_G.TashGuides = TG

TG.NAME = "TashGuides"
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
TG.VERSION = (GetMeta and GetMeta(ADDON or "TashGuides", "Version")) or "?"
TG.MEDIA = "Interface\\AddOns\\TashGuides\\media\\"

TG.TEX = {
    arrow = TG.MEDIA .. "arrow",
    dot = TG.MEDIA .. "dot",
    target = TG.MEDIA .. "target",
    available = TG.MEDIA .. "available",
    turnin = TG.MEDIA .. "turnin",
    white = "Interface\\Buttons\\WHITE8X8",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    talk = "Interface\\Icons\\INV_Misc_Note_01",
    level = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
}

-- Theme: jade and gold. Accent palette (r, g, b) shared by every frame; headers, rules,
-- buttons and the arrow logo are all tinted from TG.C.accent.
TG.C = {
    accent = { 0.00, 0.72, 0.47 },   -- jade #00B877
    gold = { 1.00, 0.82, 0.00 },
    good = { 0.30, 0.90, 0.35 },
    bad = { 1.00, 0.30, 0.25 },
    muted = { 0.55, 0.55, 0.60 },
    bg = { 0.03, 0.06, 0.05 },
    -- objective pin tints by objective kind
    monster = { 1.00, 0.35, 0.30 },
    item = { 1.00, 0.80, 0.20 },
    object = { 0.35, 0.70, 1.00 },
    event = { 0.80, 0.45, 1.00 },
    available = { 1.00, 0.82, 0.00 },
    repeatable = { 0.35, 0.70, 1.00 },
    trivial = { 0.60, 0.60, 0.60 },
    turnin = { 1.00, 0.82, 0.00 },
}

function TG.Hex(c) return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
function TG.Color(c, text) return "|cff" .. TG.Hex(c) .. tostring(text) .. "|r" end

function TG.Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00b877Tash|cffffd100Guides|r: " .. tostring(msg))
end

-- Errors from handlers that fire many times a second (casts, combat ticks) are reported once
-- per message per minute, so one bug cannot flood the error frame and its sound.
local reported = {}
function TG.Report(err)
    local msg = (issecretvalue and issecretvalue(err)) and "secret value error" or tostring(err)
    local now = GetTime and GetTime() or 0
    if reported[msg] and now - reported[msg] < 60 then return end
    reported[msg] = now
    local h = geterrorhandler and geterrorhandler()
    if h then h(msg) else TG.Print("|cffff4444error|r %s", msg) end
end

-- ---------------------------------------------------------------------------
-- Saved settings
-- ---------------------------------------------------------------------------

TG.DEFAULTS = {
    viewer = { shown = true, locked = false, scale = 1.0, alpha = 0.92, upcoming = 2, minimized = false },
    arrow = { shown = true, locked = false, scale = 1.0, arrival = 8, forwardBias = 2.5, area = 50 },
    tracker = { shown = true, locked = false, scale = 1.0, alpha = 0.85, max = 12, hideBlizzard = false },
    steps = { shown = false },
    pins = {
        world = true, minimap = true,
        available = true, objectives = true, turnins = true,
        trivial = false, repeatable = true, profession = false,
        scale = 1.0, minimapScale = 1.0,
    },
    tooltips = true,
    autoAdvance = true,
    includeChains = true,   -- class & race quest chains inside the main guides (opt-out)
    smartRouting = "linear", -- Smart Guide order: "linear" (fixed route) or "nearest" (live)
    autoAccept = false,
    autoTurnIn = false,
    sounds = true,
    minimap = { hide = false, angle = 215 },
    positions = {},
}

TG.CHAR_DEFAULTS = {
    guide = nil,        -- active guide id ("SMART" for the dynamic guide)
    guideChosen = nil,  -- true once the player picked a guide (until then zone guides are suggested)
    cursor = {},        -- guide id -> step index
    manual = {},        -- "guide:step:goal" -> true for goals the player ticked / reached
    skipped = {},       -- "guide:step" -> true
    done = {},          -- quest id -> true (turn-ins seen this character, backup for the API)
    untracked = {},     -- quest id -> true (hidden from the tracker)
    history = {},       -- recent { kind = "accept"|"turnin", quest, time } for the steps panel
    smartRoute = { keys = {}, anchors = {} }, -- Smart Guide route in linear mode
    notOffered = {},    -- quest id -> level: an NPC did not offer it although QuestieDB says it should
}

local function fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            fill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function TG.LoadSettings()
    if type(TashGuidesDB) ~= "table" then TashGuidesDB = {} end
    if type(TashGuidesCharDB) ~= "table" then TashGuidesCharDB = {} end
    -- 0.1.x stored flat flags at the top level; start the new layout clean but keep completions.
    if TashGuidesDB.showPanel ~= nil and not TashGuidesDB.viewer then
        TashGuidesDB = {}
    end
    local oldDone = type(TashGuidesCharDB.done) == "table" and TashGuidesCharDB.done or nil
    if TashGuidesCharDB.step ~= nil then TashGuidesCharDB = { done = oldDone } end
    TG.db = fill(TashGuidesDB, TG.DEFAULTS)
    TG.char = fill(TashGuidesCharDB, TG.CHAR_DEFAULTS)
end

-- ---------------------------------------------------------------------------
-- Event bus: game events and internal "TG_*" messages share one dispatcher.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function TG.On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if not event:find("^TG_") then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
    end
    list[#list + 1] = fn
end

function TG.Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then TG.Report(err) end
    end
end

-- In combat the Forever client passes "secret" event payloads (unit tokens, spell IDs) that
-- throw on comparison. Handlers only ever see plain values: secrets arrive as nil.
local function scrub(n, ...)
    if n == 0 or not issecretvalue then return ... end
    local args = { ... }
    for i = 1, n do
        if issecretvalue(args[i]) then args[i] = nil end
    end
    return unpack(args, 1, n)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    TG.Fire(event, scrub(select("#", ...), ...))
end)

-- Run `fn` once after `delay` seconds, coalescing repeated requests with the same key.
local pending = {}
function TG.Schedule(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        local ok, err = pcall(fn)
        if not ok then TG.Report(err) end
    end)
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- The Forever client can hand out "secret" values (e.g. unit identity in combat) that error
-- when compared or used; treat them as unknown.
function TG.Safe(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- GUID -> creature id, or nil for players/objects/secret GUIDs.
function TG.NpcIdFromGuid(guid)
    guid = TG.Safe(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    return nil
end

function TG.Facing()
    local f = GetPlayerFacing and TG.Safe(GetPlayerFacing())
    return type(f) == "number" and f or nil
end

-- Bit test without the 32-bit `bit` library (race masks exceed 2^32 on Forever).
function TG.HasBit(mask, bitValue)
    if not mask or not bitValue or bitValue <= 0 then return false end
    return (mask % (bitValue * 2)) >= bitValue
end

function TG.WrapAngle(a)
    local tau = math.pi * 2
    a = a % tau
    if a > math.pi then a = a - tau end
    return a
end

function TG.FormatDistance(yards)
    if not yards then return "" end
    if yards >= 1000 then return ("%.1fk yd"):format(yards / 1000) end
    return ("%d yd"):format(math.floor(yards + 0.5))
end

function TG.FormatTime(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge then return "" end
    seconds = math.floor(seconds + 0.5)
    if seconds >= 3600 then return ("%d:%02d:%02d"):format(seconds / 3600, (seconds % 3600) / 60, seconds % 60) end
    return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

-- Quest title colored by difficulty relative to the player.
function TG.QuestColor(level)
    if GetQuestDifficultyColor and level and level > 0 then
        local c = GetQuestDifficultyColor(level)
        if c then return { c.r, c.g, c.b } end
    end
    return TG.C.gold
end

function TG.MapName(map)
    if map and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(map)
        if info and info.name then return info.name end
    end
    return map and ("Map " .. map) or "?"
end

-- Flat, modern-looking panel background used by every TashGuides frame.
function TG.Skin(frame, alpha)
    if not frame.SetBackdrop then
        if BackdropTemplateMixin then Mixin(frame, BackdropTemplateMixin) else return end
    end
    frame:SetBackdrop({
        bgFile = TG.TEX.white, edgeFile = TG.TEX.white, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local bg = TG.C.bg
    frame:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 0.88)
    frame:SetBackdropBorderColor(0.15, 0.24, 0.20, 1)
end

-- Pin a frame by its top-left corner where it stands now, so a height change (collapsing the
-- tracker, minimizing the guide) moves the bottom edge and the header stays put. WoW may
-- re-anchor a dragged frame by its bottom or center, which would make it shrink downward.
function TG.AnchorTop(frame, key)
    local left, top = frame:GetLeft(), frame:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    if key then TG.db.positions[key] = { "TOPLEFT", "BOTTOMLEFT", left, top } end
end

-- Remember where the player dragged a frame.
function TG.MakeMovable(frame, key, lockedFn)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if lockedFn and lockedFn() then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        TG.db.positions[key] = { point, relPoint, x, y }
        TG.AnchorTop(self, key)
    end)
end

function TG.RestorePosition(frame, key, point, relPoint, x, y)
    local p = TG.db.positions[key]
    frame:ClearAllPoints()
    if p and p[1] then
        frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
        -- positions saved before this fix may be pinned by the bottom or center: convert
        if not tostring(p[1]):find("^TOP") then TG.AnchorTop(frame, key) end
    else
        frame:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local HELP = {
    "/tg                 toggle the guide window",
    "/tg guides          pick a guide (or the Smart Guide)",
    "/tg next | prev | skip   move through guide steps",
    "/tg steps          past and upcoming steps",
    "/tg class | race    open your class / racial quest chain",
    "/tg zone            open the guide for the zone you are in",
    "/tg prof <name>     open a profession quest guide (e.g. /tg prof alchemy)",
    "/tg chains          include or hide class & race quests in the main guides",
    "/tg route linear | nearest   Smart Guide: fixed route or nearest-first",
    "/tg route reset | skip       plan the route again / skip the current step",
    "/tg arrow | tracker toggle the arrow / quest tracker",
    "/tg way 45.2 61.8 [note]  set a waypoint on your current map",
    "/tg clear           clear the waypoint",
    "/tg options         settings",
    "/tg reset           restart the current guide",
    "/tg status          database and guide status",
}

SLASH_TASHGUIDES1 = "/tg"
SLASH_TASHGUIDES2 = "/tashguides"
SlashCmdList["TASHGUIDES"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if not TG.ready then
        TG.Print("not ready: %s", TG.initError or "still loading")
        return
    end
    if cmd == "" or cmd == "toggle" or cmd == "show" or cmd == "hide" then
        if cmd == "" or cmd == "toggle" then TG.db.viewer.shown = not TG.db.viewer.shown
        else TG.db.viewer.shown = (cmd == "show") end
        TG.Fire("TG_SETTINGS")
    elseif cmd == "guides" or cmd == "guide" or cmd == "pick" then
        TG.Viewer.ShowPicker()
    elseif cmd == "next" then TG.Guide.Next()
    elseif cmd == "prev" or cmd == "back" then TG.Guide.Prev()
    elseif cmd == "skip" then TG.Guide.Skip()
    elseif cmd == "smart" then TG.Guide.Load("SMART")
    elseif cmd == "steps" or cmd == "history" then TG.Steps.Toggle()
    elseif cmd == "class" or cmd == "race" then
        local id = cmd == "class" and "CHAIN_CLASS" or "CHAIN_RACE"
        if TG.Guide.registry[id] then TG.Guide.Load(id) else TG.Print("no %s quests found for this character", cmd) end
    elseif cmd == "route" then
        local arg = (rest or ""):lower()
        if arg == "linear" or arg == "nearest" then
            TG.Smart.SetMode(arg)
            TG.Print("Smart Guide routing: %s", arg == "linear" and "fixed route, step by step" or "nearest task first")
        elseif arg == "reset" or arg == "reroute" then
            TG.Smart.Reroute()
            TG.Print("Smart Guide route planned again from here")
        elseif arg == "skip" then
            TG.Smart.Skip()
        else
            TG.Print("Smart Guide routing is %s. Usage: /tg route linear | nearest | reset | skip", TG.Smart.Mode())
        end
    elseif cmd == "zone" then
        local map = TG.Way.PlayerMap()
        local id = map and ("ZONE_" .. map)
        if id and TG.Guide.registry[id] then TG.Guide.Load(id)
        elseif not TG.Zones.ready then TG.Print("zone guides are still being built - try again in a moment")
        else TG.Print("no zone guide for %s", map and TG.MapName(map) or "here") end
    elseif cmd == "prof" or cmd == "profession" then
        local want = (rest or ""):lower()
        local found
        for skill, name in pairs(TG.Chains.PROFESSIONS) do
            local id = "PROF_" .. skill
            if want ~= "" and name:lower():find(want, 1, true) == 1 and TG.Guide.registry[id] then found = id end
        end
        if found then TG.Guide.Load(found)
        else
            local names = {}
            for skill, name in pairs(TG.Chains.PROFESSIONS) do
                if TG.Guide.registry["PROF_" .. skill] then names[#names + 1] = name:lower() end
            end
            table.sort(names)
            TG.Print("usage: /tg prof <name> - %s", #names > 0 and table.concat(names, ", ") or "no profession quests found")
        end
    elseif cmd == "chains" then
        local on = not TG.Guide.ChainsIncluded()
        TG.Guide.SetChainsIncluded(on)
        TG.Print("class & race quests %s the main guides", on and "included in" or "hidden from")
    elseif cmd == "arrow" then
        TG.db.arrow.shown = not TG.db.arrow.shown
        TG.Fire("TG_SETTINGS")
    elseif cmd == "tracker" then
        TG.db.tracker.shown = not TG.db.tracker.shown
        TG.Fire("TG_SETTINGS")
    elseif cmd == "way" then
        local x, y, note = rest:match("^([%d%.]+)[%s,]+([%d%.]+)%s*(.-)$")
        x, y = tonumber(x), tonumber(y)
        local map = TG.Way.PlayerMap()
        if x and y and map then
            TG.Way.Set({ map = map, x = x / 100, y = y / 100, title = note ~= "" and note or ("%.1f, %.1f"):format(x, y), source = "manual" })
        else
            TG.Print("usage: /tg way 45.2 61.8 [note]")
        end
    elseif cmd == "clear" then
        TG.Way.Clear("manual")
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        TG.Options.Toggle()
    elseif cmd == "reset" then
        TG.Guide.Reset()
    elseif cmd == "status" then
        local g = TG.Guide.active
        TG.Print("v%s  QuestieDB contract %s (%s)  available quests indexed: %d",
            TG.VERSION, tostring(LibQuestieDB and LibQuestieDB.contractVersion),
            tostring(LibQuestieDB and LibQuestieDB.readMode), TG.Avail.count or 0)
        if g then TG.Print("guide: %s  step %d/%d", g.title, TG.Guide.cursor or 0, #TG.Guide.Steps()) end
        TG.Print("class quests: %d  racial quests: %d  (%s)", TG.Chains.Count("class"), TG.Chains.Count("race"),
            TG.Guide.ChainsIncluded() and "included in main guides" or "hidden from main guides")
        local profs = 0
        for _ in pairs(TG.Chains.professions) do profs = profs + 1 end
        TG.Print("zone guides: %d (%d quests)  profession guides: %d", #(TG.Zones.maps or {}), TG.Zones.count or 0, profs)
    else
        TG.Print("commands:")
        for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
    end
end

-- Addon compartment (minimap addon menu) entry declared in the TOC.
function TashGuides_OnAddonCompartmentClick(_, button)
    if not TG.ready then return end
    if button == "RightButton" then TG.Options.Toggle()
    else
        TG.db.viewer.shown = not TG.db.viewer.shown
        TG.Fire("TG_SETTINGS")
    end
end
