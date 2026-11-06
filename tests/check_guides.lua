-- Validate every bundled guide against the real QuestieDB Forever data.
--   luajit tests/check_guides.lua
-- Checks: quest exists, race mask fits the guide, givers have spawns on the guide's map,
-- accept -> complete -> turn-in order, and prerequisites turned in earlier in the guide.

local HERE = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local ADDON = os.getenv("ADDON") or (HERE .. "../TashGuides")
dofile(HERE .. "qdb_harness.lua")
setmetatable(_G, nil)

local guides = {}
_G.TashGuides = { RegisterGuide = function(def) guides[#guides + 1] = def end }
for _, f in ipairs({ "guides/northshire.lua", "guides/valley_of_trials.lua" }) do
    assert(loadfile(ADDON .. "/" .. f))()
end

local RACE_ID = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }
local function hasBit(mask, b) return mask == 0 or (mask % (b * 2)) >= b end

local problems = 0
local function bad(g, i, msg)
    problems = problems + 1
    print(("  [%s step %d] %s"):format(g.id, i, msg))
end

for _, g in ipairs(guides) do
    print(("%s: %d steps"):format(g.id, #g.steps))
    local accepted, turnedIn = {}, {}
    for i, step in ipairs(g.steps) do
        for _, goal in ipairs(step) do
            local kind, q = goal[1], goal[2]
            if kind == "accept" or kind == "complete" or kind == "turnin" then
                if not QuestDB.Exists(q) then
                    bad(g, i, ("quest %s does not exist"):format(tostring(q)))
                else
                    local mask = QuestDB.Get(q, "requiredRaces") or 0
                    local fits = false
                    for _, r in ipairs(g.races or {}) do
                        if hasBit(mask, 2 ^ (RACE_ID[r] - 1)) then fits = true end
                    end
                    if not fits and mask ~= 0 then
                        -- class letters for other races are harmless only if no guide race can take them
                        bad(g, i, ("%d %q is not available to %s"):format(q, QuestDB.name(q), table.concat(g.races, "/")))
                    end
                    if kind == "accept" then
                        accepted[q] = i
                        for _, p in ipairs(QuestDB.Get(q, "preQuestSingle") or {}) do
                            -- satisfied if any listed prerequisite is turned in earlier (or not in this guide at all)
                            local any = false
                            for _, p2 in ipairs(QuestDB.Get(q, "preQuestSingle")) do if turnedIn[p2] then any = true end end
                            local inGuide = false
                            for _, s2 in ipairs(g.steps) do for _, g2 in ipairs(s2) do if g2[2] == p and g2[1] == "turnin" then inGuide = true end end end
                            if inGuide and not any then bad(g, i, ("accept %d before its prerequisite %d is turned in"):format(q, p)) end
                            break
                        end
                    elseif kind == "complete" then
                        if not accepted[q] then bad(g, i, ("complete %d before accepting it"):format(q)) end
                    elseif kind == "turnin" then
                        if not accepted[q] and (QuestDB.Get(q, "requiredClasses") or 0) == 0 then
                            bad(g, i, ("turn in %d before accepting it"):format(q))
                        end
                        turnedIn[q] = i
                    end
                    -- givers must be on the guide's map (or a dungeon / item start)
                    local givers = QuestDB.Get(q, kind == "turnin" and "finishedBy" or "startedBy")
                    if (kind == "accept" or kind == "turnin") and givers then
                        local onMap = false
                        for _, id in ipairs(givers[1] or {}) do
                            local sp = NpcDB.spawns(id)
                            if sp and sp[g.area] then onMap = true end
                        end
                        for _, id in ipairs(givers[2] or {}) do
                            local sp = ObjectDB.spawns(id)
                            if sp and sp[g.area] then onMap = true end
                        end
                        if givers[3] and #givers[3] > 0 then onMap = true end
                        if not onMap then bad(g, i, ("%s %d %q: giver not on area %d"):format(kind, q, QuestDB.name(q), g.area)) end
                    end
                end
            elseif kind == "talk" then
                if not NpcDB.Exists(q) then bad(g, i, "talk npc " .. tostring(q) .. " missing") end
            end
        end
    end
    for q, i in pairs(accepted) do
        if not turnedIn[q] and q ~= 805 then
            print(("  note: %d %q accepted at step %d but never turned in by this guide"):format(q, QuestDB.name(q), i))
        end
    end
end

print(problems == 0 and "GUIDES OK" or (problems .. " PROBLEM(S)"))
os.exit(problems == 0 and 0 or 1)
