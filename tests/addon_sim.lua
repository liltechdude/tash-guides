-- Headless simulation: real QuestieDB + TashGuides under a mocked WoW API.
--   luajit tests/addon_sim.lua            (Human in Northshire)
--   FACTION=Horde RACE=Orc luajit tests/addon_sim.lua
-- Exits non-zero on the first failed check.

local HERE = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local ADDON = os.getenv("ADDON") or (HERE .. "../TashGuides")
local HORDE = os.getenv("FACTION") == "Horde"

dofile(HERE .. "qdb_harness.lua")
setmetatable(_G, nil)

local failures = 0
local function check(cond, msg)
    if cond then print("  ok   " .. msg) else print("  FAIL " .. msg) failures = failures + 1 end
end

-- ---------------------------------------------------------------------------
-- Mock frames
-- ---------------------------------------------------------------------------
local frames, events, timers = {}, {}, {}
local function noop() end

local function newRegion(kind)
    local r = { _kind = kind, _shown = true, _w = 100, _h = 20, _scripts = {}, _text = "" }
    local mt = {}
    mt.__index = function(t, k)
        local f = rawget(mt, k)
        if f then return f end
        -- WoW widget methods are capitalized; unknown fields read nil like real frames
        if type(k) == "string" and k:match("^%u") then return noop end
        return nil
    end
    function mt.SetScript(self, k, fn) self._scripts[k] = fn end
    function mt.GetScript(self, k) return self._scripts[k] end
    function mt.HookScript(self, k, fn)
        local old = self._scripts[k]
        self._scripts[k] = function(...) if old then old(...) end fn(...) end
    end
    function mt.RegisterEvent(self, e) events[e] = events[e] or {} ; events[e][self] = true end
    function mt.Show(self) self._shown = true if self._scripts.OnShow then self._scripts.OnShow(self) end end
    function mt.Hide(self) self._shown = false end
    function mt.SetShown(self, v) if v then self:Show() else self:Hide() end end
    function mt.IsShown(self) return self._shown end
    function mt.IsVisible(self) return self._shown end
    function mt.SetSize(self, w, h) self._w, self._h = w, h end
    function mt.SetWidth(self, w) self._w = w end
    function mt.SetHeight(self, h) self._h = h end
    function mt.GetWidth(self) return self._w end
    function mt.GetHeight(self) return self._h end
    function mt.GetSize(self) return self._w, self._h end
    function mt.GetRight(self) return 400 end
    function mt.GetCenter(self) return 500, 400 end
    function mt.GetEffectiveScale() return 1 end
    function mt.GetFrameLevel() return 1 end
    function mt.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function mt.SetText(self, t) self._text = t or "" end
    function mt.GetText(self) return self._text end
    function mt.GetStringHeight(self) return 12 end
    function mt.GetChecked(self) return self._checked end
    function mt.SetChecked(self, v) self._checked = v end
    function mt.CreateTexture() return newRegion("Texture") end
    function mt.CreateFontString() return newRegion("FontString") end
    function mt.CreateMaskTexture() return newRegion("MaskTexture") end
    function mt.GetUnit() return nil end
    function mt.GetMapID() return 1429 end
    return setmetatable(r, mt)
end

_G.CreateFrame = function(kind, name, parent, template)
    local f = newRegion(kind)
    f._name = name
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
_G.UIParent = CreateFrame("Frame", "UIParent")
_G.UIParent._w = 1920
_G.Minimap = CreateFrame("Frame", "Minimap")
_G.Minimap._w = 140
_G.Minimap.GetZoom = function() return 0 end
_G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
_G.GameTooltipTextLeft1 = newRegion("FontString")
_G.GameTooltip_Hide = noop
_G.WorldMapFrame = CreateFrame("Frame", "WorldMapFrame")
_G.WorldMapFrame.ScrollContainer = CreateFrame("Frame")
_G.WorldMapFrame.ScrollContainer.Child = CreateFrame("Frame")
_G.WorldMapFrame.ScrollContainer.Child._w, _G.WorldMapFrame.ScrollContainer.Child._h = 1000, 667
_G.WorldMapFrame.ScrollContainer.GetCanvasScale = function() return 1 end
_G.WorldMapFrame.OnMapChanged = noop
_G.UISpecialFrames = {}
_G.BackdropTemplateMixin = {}
_G.Mixin = function(t, m) for k, v in pairs(m) do t[k] = v end return t end
_G.hooksecurefunc = function(t, name, fn)
    if type(t) == "string" then return end
    local old = t[name]
    t[name] = function(...) local r = { old(...) } fn(...) return unpack(r) end
end
_G.C_Timer = {
    After = function(d, fn) timers[#timers + 1] = fn end,
    NewTicker = function(d, fn) return { Cancel = noop } end,
}
_G.GetTime = function() return os.clock() end
_G.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
_G.IsShiftKeyDown = function() return false end
_G.IsControlKeyDown = function() return false end
_G.GetCVar = function() return "0" end
_G.PlaySound = noop
_G.SOUNDKIT = {}
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("  chat: " .. (tostring(m):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end }
_G.SlashCmdList = {}
_G.GetAddOnMetadata = function(_, k) if k == "Version" then return "0.2.0-sim" end end
_G.C_AddOns = { GetAddOnMetadata = _G.GetAddOnMetadata }
_G.geterrorhandler = function() return function(e) print("  ERROR " .. tostring(e)) failures = failures + 1 end end
_G.GetQuestGreenRange = function() return 8 end
_G.GetQuestDifficultyColor = function(l) return { r = 1, g = 1, b = 0 } end

-- ---------------------------------------------------------------------------
-- Player and world
-- ---------------------------------------------------------------------------
local player = HORDE and { race = "Orc", raceID = 2, class = "WARRIOR", classID = 1, map = 1411, x = 0.433, y = 0.685 }
    or { race = "Human", raceID = 1, class = "WARRIOR", classID = 1, map = 1429, x = 0.482, y = 0.429 }
local RACES = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }
local CLASSES = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
if os.getenv("RACE") then player.race = os.getenv("RACE") player.raceID = RACES[player.race] end
if os.getenv("CLASS") then player.class = os.getenv("CLASS") player.classID = CLASSES[player.class] end
print(("player: %s %s"):format(player.race, player.class))
local level = 1
_G.UnitFactionGroup = function() return HORDE and "Horde" or "Alliance" end
_G.UnitRace = function() return player.race, player.race, player.raceID end
_G.UnitClass = function() return "Warrior", player.class, player.classID end
_G.UnitLevel = function() return level end
_G.UnitGUID = function(u) if u == "npc" and player.npc then return "Creature-0-1-1-1-" .. player.npc .. "-0" end end
_G.UnitOnTaxi = function() return false end
_G.GetPlayerFacing = function() return player.facing or 0 end
_G.GetUnitSpeed = function() return 7 end

_G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
_G.C_Map = {
    GetBestMapForUnit = function() return player.map end,
    GetPlayerMapPosition = function() return CreateVector2D(player.x, player.y) end,
    GetMapWorldSize = function() return 4000, 2700 end,
    GetMapInfo = function(m) return { name = "Map" .. m } end,
}
_G.C_Minimap = { GetViewRadius = function() return 233 end }

-- quest log
local log, completed = {}, {}
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #log end,
    GetQuestObjectives = function(id)
        for _, q in ipairs(log) do if q.id == id then return q.objectives end end
        return {}
    end,
    IsQuestFlaggedCompleted = function(id) return completed[id] == true end,
    GetAllCompletedQuestIDs = function() local t = {} for id in pairs(completed) do t[#t + 1] = id end return t end,
}
_G.GetQuestLogTitle = function(i)
    local q = log[i]
    if not q then return nil end
    return q.title, q.level, nil, false, false, q.complete and 1 or nil, 0, q.id
end

local function fire(event, ...)
    for f in pairs(events[event] or {}) do
        if f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end
local function pump(n)
    for _ = 1, n or 400 do
        local t = timers
        timers = {}
        for _, fn in ipairs(t) do fn() end
        for _, f in ipairs(frames) do
            local u = f._scripts.OnUpdate
            if u and f._shown then u(f, 0.2) end
        end
    end
end

local function accept(id, objectives)
    log[#log + 1] = { id = id, title = QuestDB.name(id), level = QuestDB.Get(id, "questLevel"),
        objectives = objectives or {}, complete = objectives == nil or #objectives == 0 }
    fire("QUEST_ACCEPTED", #log, id)
    fire("QUEST_LOG_UPDATE")
    pump(30)
end
local function finishObjectives(id)
    for _, q in ipairs(log) do
        if q.id == id then
            for _, o in ipairs(q.objectives) do o.finished = true o.numFulfilled = o.numRequired end
            q.complete = true
        end
    end
    fire("QUEST_LOG_UPDATE")
    pump(30)
end
local function turnin(id)
    for i, q in ipairs(log) do if q.id == id then table.remove(log, i) break end end
    completed[id] = true
    fire("QUEST_REMOVED", id)
    fire("QUEST_TURNED_IN", id, 100, 0)
    fire("QUEST_LOG_UPDATE")
    pump(80)
end

-- ---------------------------------------------------------------------------
-- Load the addon in TOC order
-- ---------------------------------------------------------------------------
local files = {}
for line in io.lines(ADDON .. "/TashGuides.toc") do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
end
print("loading " .. #files .. " files")
for _, f in ipairs(files) do
    local chunk, err = loadfile(ADDON .. "/" .. f)
    if not chunk then print("LOAD ERROR " .. err) os.exit(1) end
    local ok, e = pcall(chunk, "TashGuides", {})
    if not ok then print("RUN ERROR " .. f .. ": " .. tostring(e)) os.exit(1) end
end

local TG = TashGuides
print("login")
fire("PLAYER_LOGIN")
pump(200)

check(TG.ready, "addon reports ready")
check(TG.DB.UiMap(HORDE and 14 or 12) == player.map, "area -> UiMap conversion (" .. tostring(TG.DB.UiMap(HORDE and 14 or 12)) .. ")")
check((TG.Avail.count or 0) > 0, "available quests indexed: " .. tostring(TG.Avail.count))
local expectGuide = HORDE and "HORDE_VALLEY_OF_TRIALS" or "ALLIANCE_NORTHSHIRE"
check(TG.Guide.active and TG.Guide.active.id == expectGuide, "auto-picked guide " .. tostring(TG.Guide.active and TG.Guide.active.id))
check(TG.Guide.cursor == 1, "starts at step 1")
local first = HORDE and 4641 or 783
check(TG.Avail.IsAvailable(first), "first quest " .. first .. " is available")
local wp = TG.Way.current
check(wp and wp.source == "guide", "guide set a waypoint: " .. tostring(wp and wp.title))
if wp then
    local d = TG.Way.DistanceTo(wp)
    check(d and d < 200, ("waypoint distance %.0f yd"):format(d or -1))
end
local pins = TG.Pins.ForMap(player.map)
local avail = 0
for _, p in ipairs(pins) do if p.style == "available" then avail = avail + 1 end end
check(avail > 0, "world map has " .. avail .. " available-quest pins on the start map")
TG.Pins.UpdateMinimap()
TG.Pins.RefreshWorld()

-- viewer content
local function viewerText()
    local out = {}
    for _, f in ipairs(frames) do
        local t = rawget(f, "text") if f._kind == "Button" and type(t) == "table" and f._shown and t._text ~= "" then out[#out + 1] = t._text end
    end
    return table.concat(out, "\n")
end
check(viewerText():find(QuestDB.name(first), 1, true) ~= nil, "viewer shows the first quest")

print("accept first quest")
accept(first)
check(TG.Guide.cursor == 2, "advanced to step 2 after accepting (cursor " .. TG.Guide.cursor .. ")")
wp = TG.Way.current
check(wp and wp.title:find("Turn in", 1, true), "waypoint now points at the turn-in: " .. tostring(wp and wp.title))

print("turn in first quest")
turnin(first)
local second = HORDE and 788 or 7
check(TG.Avail.IsAvailable(second), "follow-up quest " .. second .. " became available")
print("accept the follow-up kill quest")
accept(second, { { text = (HORDE and "Mottled Boar" or "Kobold Vermin") .. " slain: 0/10", type = "monster", finished = false, numFulfilled = 0, numRequired = 10 } })
check(TG.Guide.cursor >= 2, "guide still on track (cursor " .. TG.Guide.cursor .. ")")

-- objectives -> pins and tooltip index
pins = TG.Pins.ForMap(player.map)
local obj = 0
for _, p in ipairs(pins) do if p.style == "monster" then obj = obj + 1 end end
check(obj > 0, "objective pins for the kill quest: " .. obj)
local pts = TG.Guide.ObjectivePoints(second)
check(#pts > 0, "objective locations resolved: " .. #pts)

print("finish objectives")
finishObjectives(second)
check(TG.QuestLog.IsReady(second), "quest marked ready to turn in")
local turninPins = 0
for _, p in ipairs(TG.Pins.ForMap(player.map)) do if p.style == "turnin" then turninPins = turninPins + 1 end end
check(turninPins > 0, "turn-in pin shown")

print("smart guide")
TG.Guide.Load("SMART")
local smart = TG.Guide.Steps()
check(#smart > 0, "smart guide generated " .. #smart .. " steps")
local hasTurnin, kinds = false, {}
for _, s in ipairs(smart) do
    for _, g in ipairs(s.goals) do
        kinds[#kinds + 1] = g.type .. ":" .. tostring(g.quest)
        if g.type == "turnin" and g.quest == second then hasTurnin = true end
    end
end
print("    smart steps: " .. table.concat(kinds, ", "))
check(hasTurnin, "smart guide includes the ready turn-in")
check(TG.Way.current ~= nil, "smart guide set a waypoint: " .. tostring(TG.Way.current and TG.Way.current.title))
TG.Guide.Load(expectGuide)


-- ---------------------------------------------------------------------------
-- Autoplay: do whatever each step asks until the guide ends.
-- ---------------------------------------------------------------------------
local function objectivesFor(q)
    local list = {}
    local function add(name) list[#list + 1] = { text = name .. ": 0/1", finished = false, numFulfilled = 0, numRequired = 1 } end
    local o = QuestDB.Get(q, "objectives")
    if o then
        for _, r in ipairs(o[1] or {}) do add((NpcDB.name(r[1]) or "?") .. " slain") end
        for _, r in ipairs(o[2] or {}) do add(r[2] or ObjectDB.name(r[1]) or "?") end
        for _, r in ipairs(o[3] or {}) do add(ItemDB.name(r[1]) or "?") end
        for _, r in ipairs(o[5] or {}) do add(r[3] or "?") end
    end
    local t = QuestDB.Get(q, "triggerEnd")
    if t then add(t[1] or "Explore") end
    return list
end

print("autoplay " .. expectGuide)
local noWaypoint, actions = {}, 0
for _ = 1, 600 do
    if TG.Guide.Finished() then break end
    local si = TG.Guide.cursor
    local step = TG.Guide.Steps()[si]
    local acted = false
    for gi, g in ipairs(step.goals) do
        if TG.Guide.GoalStatus(si, gi, g) == "todo" then
            if TG.Guide.GoalLocation(g) and not TG.Way.current then noWaypoint[#noWaypoint + 1] = si .. ":" .. g.type end
            actions = actions + 1
            if g.type == "accept" then
                local ok, why = TG.Avail.IsEligible(g.quest)
                if not ok and why == "level" then
                    level = QuestDB.Get(g.quest, "requiredLevel")
                    fire("PLAYER_LEVEL_UP", level)
                    pump(80)
                    ok, why = TG.Avail.IsEligible(g.quest)
                end
                if ok then
                    accept(g.quest, objectivesFor(g.quest))
                else
                    check(false, ("step %d: quest %d not available yet (%s)"):format(si, g.quest, tostring(why)))
                    TG.Guide.Skip()
                end
            elseif g.type == "complete" then
                finishObjectives(g.quest)
            elseif g.type == "turnin" then
                turnin(g.quest)
            elseif g.type == "talk" then
                player.npc = g.npc
                fire("GOSSIP_SHOW")
                pump(5)
                player.npc = nil
            elseif g.type == "level" then
                level = g.level
                fire("PLAYER_LEVEL_UP", level)
                pump(10)
            else
                TG.Guide.ToggleGoal(si, gi)
            end
            acted = true
            break
        end
    end
    if not acted then TG.Guide.Next() end
    pump(5)
end
check(TG.Guide.Finished(), ("autoplay finished the guide (%d actions, cursor %d/%d)"):format(actions, TG.Guide.cursor, #TG.Guide.Steps()))
check(#noWaypoint == 0, "every located goal had a waypoint" .. (#noWaypoint > 0 and (": missing " .. table.concat(noWaypoint, " ")) or ""))
local done, total = TG.Guide.Progress()
check(done == total, ("progress %d/%d"):format(done, total))

print("slash commands")
SlashCmdList.TASHGUIDES("status")
SlashCmdList.TASHGUIDES("way 50 50 test point")
check(TG.Way.current and TG.Way.current.source == "manual", "manual waypoint via /tg way")
SlashCmdList.TASHGUIDES("clear")
check((TG.Guide.Finished() and TG.Way.current == nil) or (TG.Way.current and TG.Way.current.source == "guide"), "/tg clear hands the arrow back to the guide")
SlashCmdList.TASHGUIDES("options")
SlashCmdList.TASHGUIDES("guides")
SlashCmdList.TASHGUIDES("next")
SlashCmdList.TASHGUIDES("prev")
pump(20)

print("arrow across maps and past empty steps")
do
    local WP = TG.Way
    -- Two maps side by side in world space: a point on the far map must still get a distance.
    local FAR_MAP = 99999
    local rect = { [player.map] = { 0, 0 }, [FAR_MAP] = { 4000, 0 } }
    _G.C_Map.GetWorldPosFromMapPos = function(map, v)
        local r = rect[map]
        if not r then return nil end
        return 0, CreateVector2D(r[1] + v.x * 4000, r[2] + v.y * 2700)
    end
    local sx, sy = player.x, player.y
    player.x, player.y = 0.5, 0.5
    WP.ForgetMaps()
    local tx, ty = WP.Translate(FAR_MAP, 0.5, 0.5, player.map)
    check(tx and math.abs(tx - 1.5) < 1e-6 and math.abs(ty - 0.5) < 1e-6, ("point on a neighbouring map translates (%s, %s)"):format(tostring(tx), tostring(ty)))
    local d = WP.DistanceTo({ map = FAR_MAP, x = 0.5, y = 0.5 })
    check(d and math.abs(d - 4000) < 1, "distance to a point on another map: " .. tostring(d))
    local p = WP.Nearest({ { map = FAR_MAP, x = 0.9, y = 0.5 }, { map = FAR_MAP, x = 0.1, y = 0.5 } })
    check(p and p.x == 0.1, "nearest point on another map is measured, not just the first one")
    _G.C_Map.GetWorldPosFromMapPos = nil
    WP.ForgetMaps()
    player.x, player.y = sx, sy

    -- A step with nothing to point at (a note) lends the arrow to the next located step.
    TG.RegisterGuide({ id = "TEST_LOOKAHEAD", title = "Lookahead", area = HORDE and 14 or 12, steps = {
        { { "note", "Read this first" } },
        { title = "The spot", { "goto", 60, 60, "Spot" } },
    } })
    TG.Guide.Load("TEST_LOOKAHEAD")
    local wp = WP.current
    check(wp and wp.ahead and wp.title:find("Spot", 1, true), "arrow points at the next step when the current one has no location: " .. tostring(wp and wp.title))
    TG.Guide.View(2)
    check(TG.Guide.view == 2 and TG.Guide.cursor == 1, "a future step can be previewed without moving the guide")
    TG.Guide.Prev()
    check(TG.Guide.view == nil, "stepping back from a preview returns to the current step")
    TG.Guide.registry.TEST_LOOKAHEAD = nil
    for i, id in ipairs(TG.Guide.order) do if id == "TEST_LOOKAHEAD" then table.remove(TG.Guide.order, i) break end end
    TG.Guide.Load(expectGuide)
end

print("class & race chains")
do
    local C, G = TG.Chains, TG.Guide
    print(("    class quests %d, racial quests %d"):format(C.Count("class"), C.Count("race")))
    check(C.Count("class") > 0, "class quests found for this character")
    check(G.registry.CHAIN_CLASS ~= nil, "class quest chain registered as its own guide")
    -- every class quest a zone guide tags for this character is in the class chain
    local tagged, missing, chainStep = 0, {}, nil
    for si, step in ipairs(G.Steps()) do
        if step.chain then
            chainStep = chainStep or si
            for _, goal in ipairs(step.goals) do
                if goal.quest and TG.Avail.ForPlayer(goal.quest) then
                    tagged = tagged + 1
                    if C.Kind(goal.quest) ~= "class" then missing[#missing + 1] = goal.quest end
                end
            end
        end
    end
    check(tagged > 0 and #missing == 0, ("tagged class quests are in the class chain (%d, missing: %s)"):format(tagged, table.concat(missing, " ")))
    if chainStep then
        G.SetChainsIncluded(false)
        check(G.StepStatus(chainStep) == "na", "turning class & race quests off hides the tagged steps")
        G.Load("SMART")
        local leaked = 0
        for _, s in ipairs(G.Steps()) do
            for _, goal in ipairs(s.goals) do if goal.quest and C.Kind(goal.quest) then leaked = leaked + 1 end end
        end
        check(leaked == 0, "the Smart Guide leaves chain quests out while they are off")
        G.SetChainsIncluded(true)
        G.Load(expectGuide)
        check(G.StepStatus(chainStep) ~= "na", "turning them back on shows the tagged steps")
    end
    G.Load("CHAIN_CLASS")
    check(#G.Steps() > 0, "class chain guide has " .. #G.Steps() .. " steps")
    check(#(TG.char.history or {}) > 0, "quest history recorded: " .. #(TG.char.history or {}))

    TG.db.steps.shown = false
    TG.Steps.Toggle()
    local ok, err = pcall(TG.Steps.Refresh)
    check(ok, "steps panel renders a chain guide " .. tostring(err or ""))
    G.Load("SMART")
    ok, err = pcall(TG.Steps.Refresh)
    check(ok, "steps panel renders the Smart Guide " .. tostring(err or ""))
    ok, err = pcall(TG.Tracker.Refresh)
    check(ok, "tracker renders " .. tostring(err or ""))
    TG.Steps.Toggle()
    G.Load(expectGuide)
end

print("smart guide routing")
do
    local G, Smart, QLm = TG.Guide, TG.Smart, TG.QuestLog
    local M = player.map
    local saved = { quests = QLm.quests, op = G.ObjectivePoints, forMap = TG.Avail.ForMap,
        chains = TG.db.includeChains, mode = TG.db.smartRouting, x = player.x, y = player.y }
    local spots = { [900001] = { 0.30, 0.50 }, [900002] = { 0.60, 0.50 }, [900003] = { 0.63, 0.53 }, [900004] = { 0.33, 0.52 } }
    local function quest(id) return { id = id, title = "Q" .. id, level = 1, complete = false,
        objectives = { { text = "Thing slain: 0/5", finished = false, have = 0, need = 5 } } } end
    QLm.quests = { [900001] = quest(900001), [900002] = quest(900002), [900003] = quest(900003) }
    G.ObjectivePoints = function(q) local s = spots[q] return s and { { map = M, x = s[1], y = s[2] } } or {} end
    TG.Avail.ForMap = function() return {} end
    TG.db.includeChains = false
    local function head() local s = G.Steps()[1] return s and s.goals[1] and s.goals[1].quest end

    TG.db.smartRouting = "linear"
    player.x, player.y = 0.32, 0.50
    G.Load("SMART")
    Smart.Reroute()
    check(head() == 900001, "linear: the route starts at the nearest task (" .. tostring(head()) .. ")")
    player.x, player.y = 0.61, 0.50          -- wander over to another quest's spawns
    G.Evaluate()
    check(head() == 900001, "linear: the current step holds while you wander off (" .. tostring(head()) .. ")")
    QLm.quests[900004] = quest(900004)       -- pick up a new quest right next to the first one
    G.Evaluate()
    check(head() == 900001, "linear: a new quest is slotted in behind the current step")
    local order = {}
    for i, k in ipairs(TG.char.smartRoute.keys) do order[i] = k end
    print("    route: " .. table.concat(order, ", "))
    check(order[2] == "complete:900004", "linear: the new quest goes where it adds the least walking")
    QLm.quests[900001].complete = true       -- finish the current step's objectives
    G.Evaluate()
    check(head() == 900004, "linear: finishing the step moves on to the next stop in the route (" .. tostring(head()) .. ")")
    G.Next()
    check(head() ~= 900004 and TG.char.smartRoute.keys[#TG.char.smartRoute.keys] == "complete:900004", "linear: > skips the step to the end of the route")

    Smart.SetMode("nearest")
    QLm.quests[900001].complete = false
    G.Evaluate()
    check(head() == 900002, "nearest: the nearest task leads (" .. tostring(head()) .. ")")
    player.x, player.y = 0.616, 0.515        -- now a little closer to 900003 than to 900002
    G.Evaluate()
    check(head() == 900002, "nearest: the leader is sticky between two tasks at about the same distance")
    player.x, player.y = 0.30, 0.50
    G.Evaluate()
    check(head() == 900001, "nearest: a clearly closer task takes over (" .. tostring(head()) .. ")")

    QLm.quests, G.ObjectivePoints, TG.Avail.ForMap = saved.quests, saved.op, saved.forMap
    TG.db.includeChains, TG.db.smartRouting = saved.chains, saved.mode
    player.x, player.y = saved.x, saved.y
    Smart.Reroute()
    G.Load(expectGuide)
end

print("quests the game does not offer")
do
    local DBm, AV = TG.DB, TG.Avail
    local FAKE, TRAINER, GIVER = 990001, 990101, 990102
    local fake = {
        [FAKE] = { name = "Chakuyak", questLevel = level, requiredLevel = 1, requiredClasses = 0, requiredRaces = 0,
            startedBy = { { TRAINER } }, finishedBy = { { TRAINER } } },
    }
    local npcs = { [TRAINER] = { name = "Yaw Sharpmane", subName = "Hunter Trainer" },
        [GIVER] = { name = "Some Giver", subName = "Fishing Trainer" } }
    local realQuest, realNpc, realExists = DBm.Quest, DBm.Npc, DBm.QuestExists
    DBm.Quest = function(id, key) if fake[id] then return fake[id][key] end return realQuest(id, key) end
    DBm.QuestExists = function(id) return fake[id] ~= nil or realExists(id) end
    DBm.Npc = function(id, key) if npcs[id] then return npcs[id][key] end return realNpc(id, key) end
    local realFile = AV.classFile

    -- 1. A quest with no class flag that only a Hunter trainer hands out is a hunter quest.
    AV.classFile = "WARRIOR"
    check(AV.InferredClass(FAKE) == "HUNTER", "a quest only a Hunter trainer gives is treated as a hunter quest")
    check(not AV.ClassOk(FAKE), "a warrior is not offered a Hunter trainer's quest")
    AV.classFile = "HUNTER"
    check(AV.ClassOk(FAKE), "a hunter still is")
    AV.classFile = "WARRIOR"

    -- 2. An NPC that does not list a quest the database expects: the guide stops asking for it.
    local Q2 = FAKE + 1
    fake[Q2] = { name = "Unlisted Errand", questLevel = level, requiredLevel = 1, requiredClasses = 0, requiredRaces = 0,
        startedBy = { { GIVER } }, finishedBy = { { GIVER } } }
    check(AV.InferredClass(Q2) == nil and AV.ClassOk(Q2), "profession trainers do not imply a class")
    check(TG.Guide.GoalStatus(1, 1, { type = "accept", quest = Q2 }) == "todo", "before talking to the NPC the guide asks for it")
    AV.byGiver = AV.byGiver or {}
    AV.byGiver[GIVER] = { Q2 }
    AV.set[Q2] = { quest = Q2, level = level }
    local realGossip = _G.C_GossipInfo
    local offered = { { questID = Q2, title = "Unlisted Errand" } }
    _G.C_GossipInfo = { GetAvailableQuests = function() return offered end }
    AV.CheckOffers("GOSSIP_SHOW", GIVER)
    check(not AV.NotOffered(Q2), "a quest the NPC lists stays available")
    offered = {}
    AV.CheckOffers("GOSSIP_SHOW", GIVER)
    check(AV.NotOffered(Q2) and not AV.IsEligible(Q2), "a quest the NPC does not list is marked not offered")
    check(TG.Guide.GoalStatus(1, 1, { type = "accept", quest = Q2 }) == "na", "the guide stops asking you to accept it")
    level = level + 1
    check(not AV.NotOffered(Q2), "it gets another look after you level up")
    level = level - 1

    _G.C_GossipInfo = realGossip
    AV.set[Q2], AV.byGiver[GIVER] = nil, nil
    TG.char.notOffered[Q2] = nil
    DBm.Quest, DBm.Npc, DBm.QuestExists = realQuest, realNpc, realExists
    AV.classFile = realFile
    pump(40)
end

print("objective area on the arrow")
do
    local WP, QLm, DBm, A = TG.Way, TG.QuestLog, TG.DB, TG.Arrow
    local M, FAKE = player.map, 990201
    local saved = { quests = QLm.quests, obj = DBm.Objectives, x = player.x, y = player.y }
    QLm.quests = { [FAKE] = { id = FAKE, title = "Kobold Trouble", level = 1, complete = false,
        objectives = { { text = "Kobold Vermin slain: 3/10", finished = false, have = 3, need = 10 } } } }
    DBm.Objectives = function(q)
        if q == FAKE then return { { kind = "monster", name = "Kobold Vermin", npcs = {}, objects = {},
            points = { { map = M, x = 0.50, y = 0.45 }, { map = M, x = 0.52, y = 0.45 } } } } end
        return saved.obj(q)
    end
    local function arrowState() pump(2) return A.state end

    player.x, player.y = 0.50, 0.50                         -- 135 yd south of the camp
    WP.Set({ map = M, x = 0.50, y = 0.45, source = "tracker", quest = FAKE, objective = true, title = "Kobold Trouble" })
    check(arrowState() == "arrow", "far from the objective the arrow points the way (" .. tostring(A.state) .. ")")
    player.x, player.y = 0.50, 0.465                        -- ~40 yd out: among the spawns
    check(arrowState() == "area", "inside the objective area the arrow shows the area display (" .. tostring(A.state) .. ")")
    player.x, player.y = 0.50, 0.471                        -- ~57 yd: just past the edge, still inside the margin
    check(arrowState() == "area", "the area display does not flicker at the edge")
    player.x, player.y = 0.50, 0.45                         -- standing on a spawn
    WP.CheckArrival(0)
    check(WP.current and WP.current.source == "tracker", "reaching one spawn does not clear an objective waypoint")
    check(arrowState() == "area", "standing on a spawn still shows the objective area, not a check mark")
    player.x, player.y = 0.50, 0.55                         -- walk well away
    check(arrowState() == "arrow", "leaving the area brings the arrow back")
    QLm.quests[FAKE].complete = true
    TG.Fire("TG_QUESTLOG", false)
    check(WP.current == nil or WP.current.source ~= "tracker", "the objective waypoint clears once the quest is ready")

    WP.Set({ map = M, x = 0.50, y = 0.55, source = "manual", title = "spot" })
    check(arrowState() == "arrived", "a plain waypoint still shows the arrival check")
    WP.Clear("manual")

    QLm.quests, DBm.Objectives = saved.quests, saved.obj
    player.x, player.y = saved.x, saved.y
    pump(10)
end

print("spawn picking")
do
    local WP = TG.Way
    local saved = { player.map, player.x, player.y, player.facing }
    local realTime, clock = _G.GetTime, 1000
    _G.GetTime = function() return clock end
    local M = player.map
    local function pt(x, y) return { map = M, x = x, y = y } end
    local function at(x, y, facing) player.x, player.y, player.facing = x, y, facing end
    local N, E, S = 0, -math.pi / 2, math.pi -- WoW facing: counter-clockwise from north
    WP.ForgetVisited()

    -- map is 4000 x 2700 yd: 0.01 x = 40 yd, 0.01 y = 27 yd
    local ahead, behind = pt(0.5, 0.48), pt(0.5, 0.515)       -- 54 yd ahead, 40 yd behind
    at(0.5, 0.5, N)
    check(WP.Nearest({ ahead, behind }) == behind, "plain nearest picks the closer spawn behind")
    check(WP.PickSpawn({ ahead, behind }) == ahead, "a spawn ahead beats a slightly closer one behind")
    at(0.5, 0.5, S)
    check(WP.PickSpawn({ ahead, behind }) == behind, "turning around flips the preference")
    at(0.5, 0.5, N)
    local farAhead, nearBehind = pt(0.5, 0.40), pt(0.5, 0.52)  -- 270 yd ahead, 54 yd behind
    check(WP.PickSpawn({ farAhead, nearBehind }) == nearBehind, "a much closer spawn behind still wins")

    -- arrive at a node, clear it, walk on: the arrow must not point back at it
    WP.ForgetVisited()
    local node, nextNode = pt(0.5, 0.5), pt(0.53, 0.5)          -- next node 120 yd east
    at(0.5, 0.5, E)
    check(WP.PickSpawn({ node, nextNode }) == node, "standing on a node keeps it as the target")
    clock = clock + 20
    at(0.505, 0.5, E)                                            -- 20 yd past it
    local p, d = WP.PickSpawn({ node, nextNode }, node)
    check(p == nextNode, "a cleared node behind you is not pulled back as the target")
    check(d and math.abs(d - 100) < 1, "the reported distance is the real distance (" .. tostring(d) .. ")")
    clock = clock + WP.VISIT_TTL + 1
    at(0.505, 0.5, math.pi / 2)                                  -- face west, back at the node
    check(WP.PickSpawn({ node, nextNode }) == node, "a cleared node counts again after a few minutes")

    -- sticky: a marginally better spawn does not steal the target
    WP.ForgetVisited()
    at(0.5, 0.5, N)
    local a1, a2 = pt(0.5, 0.48), pt(0.5, 0.477)                -- 54 yd and 62 yd ahead
    check(WP.PickSpawn({ a1, a2 }, a2) == a2, "the current target is kept against a slightly better one")
    check(WP.PickSpawn({ a1, pt(0.5, 0.46) }, pt(0.5, 0.46)) == a1, "a clearly better spawn replaces the target")

    TG.db.arrow.forwardBias = 0
    WP.ForgetVisited()
    check(WP.PickSpawn({ ahead, behind }) == behind, "forward bias 0 is plain nearest")
    TG.db.arrow.forwardBias = 2.5

    _G.GetTime = realTime
    player.map, player.x, player.y, player.facing = saved[1], saved[2], saved[3], saved[4]
    WP.ForgetVisited()
end

print("combat secret values")
-- The Forever client hands secret payloads to events while in combat (e.g. every cast fires
-- UNIT_SPELLCAST_SUCCEEDED for player/target/nameplates). Handlers must never see them.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
_G.issecretvalue = function(v) return v == SECRET end
local leaked = 0
TG.On("UNIT_SPELLCAST_SUCCEEDED", function(...)
    for i = 1, select("#", ...) do if select(i, ...) == SECRET then leaked = leaked + 1 end end
end)
for _ = 1, 50 do
    fire("UNIT_SPELLCAST_SUCCEEDED", SECRET, SECRET, SECRET)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", SECRET, SECRET)
    fire("UNIT_QUEST_LOG_CHANGED", SECRET)
end
check(leaked == 0, "secret event payloads are scrubbed before handlers run")
local seen, realHandler = 0, _G.geterrorhandler
_G.geterrorhandler = function() return function() seen = seen + 1 end end
for _ = 1, 20 do TG.Report("same error") end
_G.geterrorhandler = realHandler
check(seen == 1, "a repeating error is reported once, not every time")
_G.issecretvalue = nil
pump(20)

print("hide Blizzard's tracker")
do
    -- Blizzard's tracker holds secure quest-item buttons: hiding it in combat is blocked.
    local combat, blocked = false, 0
    _G.InCombatLockdown = function() return combat end
    local blizz = CreateFrame("Frame", "ObjectiveTrackerFrame")
    local realHide = blizz.Hide
    blizz.Hide = function(self) if combat then blocked = blocked + 1 return end realHide(self) end

    TG.db.tracker.shown, TG.db.tracker.hideBlizzard = true, true
    TG.Fire("TG_SETTINGS")
    check(not blizz:IsShown(), "turning the option on hides Blizzard's tracker")
    blizz:Show()
    check(not blizz:IsShown(), "it stays hidden when Blizzard shows it again")

    combat = true
    blizz:Show() -- objectives update mid-fight
    check(blocked == 0, "no hide is attempted in combat")
    combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(not blizz:IsShown(), "a re-show during combat is hidden once combat ends")

    combat = true
    TG.Fire("TG_SETTINGS")
    combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(not blizz:IsShown(), "settings applied in combat still hide it after combat")

    TG.db.tracker.hideBlizzard = false
    TG.Fire("TG_SETTINGS")
    check(blizz:IsShown(), "turning the option off shows it again")
    blizz:Hide() -- Blizzard empties its tracker
    fire("PLAYER_REGEN_ENABLED")
    check(not blizz:IsShown(), "with the option off, combat ending does not force it back on")

    TG.db.tracker.hideBlizzard = true
    TG.Fire("TG_SETTINGS")
    TG.db.tracker.shown = false
    TG.Fire("TG_SETTINGS")
    check(blizz:IsShown(), "hiding our tracker brings Blizzard's back")
    TG.db.tracker.shown, TG.db.tracker.hideBlizzard = true, false
    TG.Fire("TG_SETTINGS")
    check(blocked == 0, "never tried to hide it in combat")
    _G.InCombatLockdown, _G.ObjectiveTrackerFrame = nil, nil
end

print(failures == 0 and "ALL CHECKS PASSED" or (failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
