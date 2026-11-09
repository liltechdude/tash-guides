-- Rough level pace along each race's hand-written campaign.
--   luajit tests/pace.lua                 every race
--   RACE=Tauren luajit tests/pace.lua     one race
-- QuestieDB has no quest XP, so XP is estimated from the quest level (classic-era values,
-- reduced for quests that have gone grey or green-low), plus KILL_SHARE (default 1: as much
-- again) for the mobs killed on the way. The output shows, per guide, the level on arrival and on leaving next to the
-- guide's own range: a guide entered well below its minLevel means the guides before it do
-- not carry the player far enough.
dofile((debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./") .. "qdb_harness.lua")
setmetatable(_G, nil)
local bit = require("bit")

local ADDON = os.getenv("ADDON") or ((debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./") .. "../TashGuides")
local KILL_SHARE = tonumber(os.getenv("KILL_SHARE") or "1")

-- XP needed to go from level n to n + 1 (classic)
local TO_NEXT = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8700, 9800, 11000, 12300,
    13600, 15000, 16400, 17800, 19300, 20800, 22400, 24000, 25500, 27200, 28900, 30500, 32200, 33900,
    36300, 38800, 41600, 44600, 47800, 51000, 54500, 58200, 62000, 66000, 70200, 74300, 78500, 82800,
    87100, 91600, 95300, 101000, 105800, 110300, 115300, 120500, 126000, 131100, 136400, 142000, 148200,
    154800, 161200, 167800, 174700 }
-- typical full quest XP by quest level (piecewise linear between these points)
local QXP = { { 1, 80 }, { 5, 350 }, { 10, 800 }, { 20, 1650 }, { 30, 2800 }, { 40, 3750 }, { 50, 4850 }, { 55, 5500 }, { 60, 6600 } }
local function questXP(ql, level)
    local base = QXP[#QXP][2]
    for i = 2, #QXP do
        local a, b = QXP[i - 1], QXP[i]
        if ql <= b[1] then base = a[2] + (b[2] - a[2]) * (math.max(ql, a[1]) - a[1]) / (b[1] - a[1]) break end
    end
    local d = level - ql
    if d >= 10 then return base * 0.1 elseif d == 9 then return base * 0.2 elseif d == 8 then return base * 0.4
    elseif d == 7 then return base * 0.6 elseif d == 6 then return base * 0.8 end
    return base
end

local guides, byId = {}, {}
_G.TashGuides = { RegisterGuide = function(def) guides[#guides + 1] = def byId[def.id] = def end }
_G.UnitRace = function() return "Human", "Human" end
local p = io.popen('cd "' .. ADDON .. '" && find guides -name "*.lua" | sort')
for f in p:lines() do local c = loadfile(ADDON .. "/" .. f) if c then pcall(c) end end
p:close()

local RACE_BIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local FACTION = { Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde" }
local ORDER = { "Human", "Dwarf", "Gnome", "NightElf", "Orc", "Troll", "Scourge", "Tauren" }

local function run(race)
    local start
    for _, g in ipairs(guides) do
        if g.faction == FACTION[race] and g.races and (g.minLevel or 1) <= 1 then
            for _, r in ipairs(g.races) do if r == race then start = g end end
        end
    end
    if not start then print(race .. ": no starting guide") return end
    print(("%s (quest XP + %d%% for kills)"):format(race, KILL_SHARE * 100))
    local level, xp, done = 1, 0, {}
    local function gain(amount)
        xp = xp + amount
        while level < 60 and xp >= TO_NEXT[level] do xp = xp - TO_NEXT[level] level = level + 1 end
    end
    local g, seen = start, {}
    while g and not seen[g.id] do
        seen[g.id] = true
        local arrive = level >= 60 and 60 or level + xp / TO_NEXT[level]
        local n = 0
        for _, step in ipairs(g.steps or {}) do
            if step.chain ~= "class" then
                for _, goal in ipairs(step) do
                    local q = goal[2]
                    if goal[1] == "turnin" and type(q) == "number" and not done[q] and QuestDB.Exists(q) then
                        local m = bit.band(QuestDB.Get(q, "requiredRaces") or 0, 255)
                        if m == 0 or bit.band(m, RACE_BIT[race]) ~= 0 then
                            done[q] = true
                            n = n + 1
                            gain(questXP(QuestDB.Get(q, "questLevel") or level, level) * (1 + KILL_SHARE))
                        end
                    end
                end
            end
        end
        local leave = level >= 60 and 60 or level + xp / TO_NEXT[level]
        local flag = ""
        if arrive < (g.minLevel or 1) - 2 then flag = "  << arrives under-levelled" end
        if leave < (g.maxLevel or 60) - 3 then flag = flag .. "  << leaves short of its range" end
        print(("  %-26s %2d-%-2d  arrive %5.1f  leave %5.1f  (%d quests)%s"):format(g.id, g.minLevel or 0, g.maxLevel or 0, arrive, leave, n, flag))
        g = g.next and byId[g.next]
    end
end

if os.getenv("RACE") then run(os.getenv("RACE")) else for _, r in ipairs(ORDER) do run(r) end end
