-- Validate every hand-written guide against the real QuestieDB Forever data.
--   luajit tests/check_guides.lua            errors fail the run, warnings are listed
--   QUIET=1 luajit tests/check_guides.lua    errors and the summary only
--   ONLY=A_WESTFALL,H_BARRENS luajit tests/check_guides.lua   problems in these guides only (id
--       prefixes); each is also checked on its own, so it can be tested before its neighbours exist
--
-- Per guide:
--   * every quest exists, suits the guide's faction (race mask, a friendly giver) and is not
--     repeatable or a profession quest; class quests sit in steps tagged chain = "class"
--   * givers and hand-ins stand on the guide's map (def.area) or one listed in def.areas
--   * talk NPCs exist; goto goals have coordinates; next points at a registered guide
-- Per race, along the whole campaign (the starting guide for that race, then each `next`):
--   * a quest is accepted once, before it is completed or turned in
--   * prerequisites are turned in before the quest is accepted, and are part of the path
--   * exclusive quests and breadcrumbs are not taken after the quest that rules them out
--   * the quest log never holds more than 20 quests
--   * quests accepted but never turned in are listed as warnings

local HERE = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local ADDON = os.getenv("ADDON") or (HERE .. "../TashGuides")
local QUIET = os.getenv("QUIET")
local ONLY = os.getenv("ONLY")
dofile(HERE .. "qdb_harness.lua")
setmetatable(_G, nil)
local bit = require("bit")

-- ---- load the guides listed in the TOC, plus any guides/ file not listed yet -----------
local guides, byId, files, seen = {}, {}, {}, {}
for line in io.lines(ADDON .. "/TashGuides.toc") do
    local f = line:gsub("\r$", ""):gsub("\\", "/")
    if f:match("^guides/.*%.lua$") then files[#files + 1] = f seen[f] = true end
end
local unlisted = {}
local p = io.popen('cd "' .. ADDON .. '" && find guides -name "*.lua" | sort')
for f in p:lines() do if not seen[f] then files[#files + 1] = f unlisted[#unlisted + 1] = f end end
p:close()

local currentFile
local loadErrors = {}
_G.TashGuides = { RegisterGuide = function(def)
    def._file = currentFile
    if byId[def.id] then loadErrors[#loadErrors + 1] = { file = currentFile, id = def.id, msg = "duplicate guide id " .. def.id } return end
    guides[#guides + 1] = def
    byId[def.id] = def
end }
_G.UnitRace = function() return "Human", "Human" end
for _, f in ipairs(files) do
    currentFile = f
    local chunk, err = loadfile(ADDON .. "/" .. f)
    local ok = chunk ~= nil
    if chunk then ok, err = pcall(chunk) end
    if not ok then loadErrors[#loadErrors + 1] = { file = f, msg = tostring(err) } end
end

local RACE_BIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local FACTION_RACES = {
    Alliance = { "Human", "Dwarf", "NightElf", "Gnome" },
    Horde = { "Orc", "Scourge", "Tauren", "Troll" },
}
local FACTION_MASK = { Alliance = 77, Horde = 178 }
local FKEY = { Alliance = "A", Horde = "H" }

local errors, warnings = 0, 0
local function selected(g)
    if not ONLY then return true end
    if not g then return false end
    for pat in ONLY:gmatch("[^,]+") do if g.id:find("^" .. pat) then return true end end
    return false
end
-- with ONLY set, problems in other guides (and race-wide ones) are not reported or counted
local function report(level, g, where, msg)
    if not selected(g) then return end
    if level == "ERR" then errors = errors + 1 else warnings = warnings + 1 end
    if level == "warn" and QUIET then return end
    print(("  %s [%s%s] %s"):format(level, g and g.id or "?", where and (" step " .. where) or "", msg))
end

for _, e in ipairs(loadErrors) do
    -- with ONLY set, a broken file still counts when it is one of the selected guides' files
    local mine = not ONLY
    if ONLY then
        local text = io.open(ADDON .. "/" .. e.file):read("*a")
        for pat in ONLY:gmatch("[^,]+") do if text:find('id%s*=%s*"' .. pat) then mine = true end end
    end
    if mine then errors = errors + 1 print("  ERR [" .. e.file .. "] " .. e.msg)
    else print("  note: skipped " .. e.file .. " (" .. e.msg .. ")") end
end

local function qname(q) return ("%d %q"):format(q, tostring(QuestDB.name(q))) end
local function raceOk(q, race)
    local m = QuestDB.Get(q, "requiredRaces") or 0
    m = bit.band(m, 255)
    return m == 0 or bit.band(m, RACE_BIT[race]) ~= 0
end
local trainerCache = {}
local function trainerClass(npc)
    if trainerCache[npc] == nil then
        local sub = NpcDB.subName and NpcDB.subName(npc)
        trainerCache[npc] = type(sub) == "string" and sub:match("^(%a+) Trainer$") or false
    end
    return trainerCache[npc]
end
local CLASS_NAMES = { Warrior = 1, Paladin = 1, Hunter = 1, Rogue = 1, Priest = 1, Shaman = 1, Mage = 1, Warlock = 1, Druid = 1 }
-- same rule as AV.InferredClass: every starter is a class trainer, and the quest does not
-- continue an ordinary quest chain
local function fromTrainer(q)
    local sb = QuestDB.Get(q, "startedBy")
    local npcs = sb and sb[1]
    if not npcs or #npcs == 0 or (sb[2] and #sb[2] > 0) or (sb[3] and #sb[3] > 0) then return false end
    for _, id in ipairs(npcs) do
        local c = trainerClass(id)
        if not c or not CLASS_NAMES[c] then return false end
    end
    return true
end
local function isClassQuest(q)
    if (QuestDB.Get(q, "requiredClasses") or 0) ~= 0 then return true end
    if not fromTrainer(q) then return false end
    for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
        for _, p in ipairs(QuestDB.Get(q, key) or {}) do
            if p > 0 and QuestDB.Exists(p) and (QuestDB.Get(p, "requiredClasses") or 0) == 0 and not fromTrainer(p) then return false end
        end
    end
    return true
end
local function giverAreas(list)
    local areas, any = {}, false
    for _, id in ipairs(list and list[1] or {}) do
        for a in pairs(NpcDB.spawns(id) or {}) do areas[a] = true any = true end
    end
    for _, id in ipairs(list and list[2] or {}) do
        for a in pairs(ObjectDB.spawns(id) or {}) do areas[a] = true any = true end
    end
    return areas, any, list and list[3] and #list[3] > 0
end
local function friendlyGiver(list, faction)
    local any = false
    for _, id in ipairs(list and list[1] or {}) do
        any = true
        local f = NpcDB.friendlyToFaction(id)
        if not f or f:find(FKEY[faction]) then return true end
    end
    if list and ((list[2] and #list[2] > 0) or (list[3] and #list[3] > 0)) then return true end
    return not any
end

-- ---- per-guide static checks ---------------------------------------------------------
local QUEST_GOALS = { accept = true, complete = true, turnin = true }
for _, g in ipairs(guides) do
    local faction = g.faction
    if not FACTION_MASK[faction] then report("ERR", g, nil, "faction must be Alliance or Horde") faction = "Alliance" end
    if not g.area then report("ERR", g, nil, "no area") end
    if g.next and not byId[g.next] and not g.next:match("^ZONE_") then report("ERR", g, nil, "next guide " .. g.next .. " is not registered") end
    if not g.minLevel or not g.maxLevel then report("ERR", g, nil, "minLevel / maxLevel missing") end
    local allowed = { [g.area or -1] = true }
    for _, a in ipairs(g.areas or {}) do allowed[a] = true end
    if #(g.steps or {}) == 0 then report("ERR", g, nil, "no steps") end
    for i, step in ipairs(g.steps or {}) do
        local n = 0
        for _, goal in ipairs(step) do
            n = n + 1
            local kind, q = goal[1], goal[2]
            if QUEST_GOALS[kind] then
                if type(q) ~= "number" or not QuestDB.Exists(q) then
                    report("ERR", g, i, ("quest %s does not exist"):format(tostring(q)))
                else
                    local mask = bit.band(QuestDB.Get(q, "requiredRaces") or 0, 255)
                    local fits = mask == 0 or bit.band(mask, FACTION_MASK[faction]) ~= 0
                    if fits and g.races then
                        fits = false
                        for _, r in ipairs(g.races) do if raceOk(q, r) then fits = true end end
                    end
                    if not fits then report("ERR", g, i, qname(q) .. " is not available to this guide's races / faction") end
                    if bit.band(QuestDB.Get(q, "specialFlags") or 0, 1) ~= 0 then report("ERR", g, i, qname(q) .. " is repeatable") end
                    if QuestDB.Get(q, "requiredSkill") then report("ERR", g, i, qname(q) .. " is a profession quest") end
                    if isClassQuest(q) and step.chain ~= "class" then report("warn", g, i, qname(q) .. " is a class quest: tag its step chain = \"class\"") end
                    if kind == "accept" or kind == "turnin" then
                        local list = QuestDB.Get(q, kind == "accept" and "startedBy" or "finishedBy")
                        local areas, any, item = giverAreas(list)
                        if kind == "accept" and not friendlyGiver(list, faction) then
                            report("ERR", g, i, qname(q) .. ": its giver is not friendly to " .. faction)
                        end
                        if any then
                            local ok = false
                            for a in pairs(areas) do if allowed[a] then ok = true end end
                            if not ok then
                                local names = {}
                                for a in pairs(areas) do names[#names + 1] = tostring(a) end
                                table.sort(names)
                                report("ERR", g, i, ("%s %s: giver is in area %s, add it to areas"):format(kind, qname(q), table.concat(names, "/")))
                            end
                        elseif not item then
                            report("ERR", g, i, ("%s %s: nobody gives / takes it"):format(kind, qname(q)))
                        end
                    end
                    if (QuestDB.Get(q, "requiredLevel") or 0) > (g.maxLevel or 60) + 1 and kind == "accept" then
                        report("warn", g, i, ("%s needs level %d, above the guide's range"):format(qname(q), QuestDB.Get(q, "requiredLevel")))
                    end
                end
            elseif kind == "talk" then
                if not NpcDB.Exists(q) then report("ERR", g, i, "talk npc " .. tostring(q) .. " missing") end
            elseif kind == "goto" then
                if type(goal[2]) ~= "number" or type(goal[3]) ~= "number" then report("ERR", g, i, "goto needs x, y") end
                if goal.area and not goal.area then end
            elseif kind == "level" then
                if type(q) ~= "number" then report("ERR", g, i, "level goal needs a number") end
            elseif kind ~= "note" and kind ~= "hearth" and kind ~= "fly" then
                report("ERR", g, i, "unknown goal type " .. tostring(kind))
            end
        end
        if n == 0 and not step.note then report("ERR", g, i, "empty step") end
        if n > 14 then report("warn", g, i, n .. " goals in one step") end
    end
end

-- ---- campaign walk per race ----------------------------------------------------------
local reached = {}
-- every turn-in in any guide of a faction, so a standalone check can tell "done elsewhere"
local anywhere = { Alliance = {}, Horde = {} }
local acceptedAnywhere = { Alliance = {}, Horde = {} }
for _, g in ipairs(guides) do
    for _, step in ipairs(g.steps or {}) do
        for _, goal in ipairs(step) do
            if goal[1] == "turnin" and type(goal[2]) == "number" and anywhere[g.faction] then anywhere[g.faction][goal[2]] = g.id end
            if goal[1] == "accept" and type(goal[2]) == "number" and acceptedAnywhere[g.faction] then acceptedAnywhere[g.faction][goal[2]] = g.id end
        end
    end
end

local function campaignPath(faction, race)
    -- the starting guide: a guide restricted to races that include this one, minLevel 1
    local start
    for _, g in ipairs(guides) do
        if g.faction == faction and g.races and (g.minLevel or 1) <= 1 then
            for _, r in ipairs(g.races) do if r == race then start = g end end
        end
    end
    if not start then report("ERR", nil, nil, race .. ": no starting guide") return nil end
    local path, seenG = {}, {}
    local g = start
    while g and not seenG[g.id] do
        seenG[g.id] = true
        path[#path + 1] = g
        g = g.next and byId[g.next]
    end
    if g then report("ERR", g, nil, race .. ": the next chain loops back here") end
    return path
end

-- standalone: one guide on its own; prerequisites outside it count as done elsewhere
-- (a warning when no guide of the faction turns them in at all)
local function walk(faction, race, path, standalone)
    -- every quest on the path (this race, not class quests), to tell "missing prerequisite"
    -- from "prerequisite later in the path"
    local onPath = {}
    for _, pg in ipairs(path) do
        if not standalone then reached[pg.id] = true end
        for i, step in ipairs(pg.steps or {}) do
            if step.chain ~= "class" then
                for _, goal in ipairs(step) do
                    if goal[1] == "turnin" and type(goal[2]) == "number" then onPath[goal[2]] = onPath[goal[2]] or (pg.id .. ":" .. i) end
                end
            end
        end
    end

    local state, log, logSize, maxLog, maxAt = {}, {}, 0, 0, nil
    local acceptedAt = {}
    for _, pg in ipairs(path) do
        for i, step in ipairs(pg.steps or {}) do
            if step.chain ~= "class" and not (step.race and not (step.race == race or (type(step.race) == "table" and table.concat(step.race, ","):find(race)))) then
                for _, goal in ipairs(step) do
                    local kind, q = goal[1], goal[2]
                    if QUEST_GOALS[kind] and type(q) == "number" and QuestDB.Exists(q) and raceOk(q, race) and not isClassQuest(q) then
                        local where = i
                        if kind == "accept" then
                            if state[q] then
                                report("ERR", pg, where, ("%s: %s accepted again (first at %s)"):format(race, qname(q), acceptedAt[q]))
                            else
                                -- prerequisites
                                local group = QuestDB.Get(q, "preQuestGroup") or {}
                                for _, pq in ipairs(group) do
                                    if pq > 0 and raceOk(pq, race) and not isClassQuest(pq) and state[pq] ~= "T" then
                                        if standalone and not onPath[pq] then
                                            if not anywhere[faction][pq] then report("warn", pg, where, ("%s: %s needs %s, which no guide turns in"):format(race, qname(q), qname(pq))) end
                                        elseif onPath[pq] then
                                            report("ERR", pg, where, ("%s: %s accepted before its prerequisite %s is turned in (at %s)"):format(race, qname(q), qname(pq), onPath[pq]))
                                        else
                                            report("ERR", pg, where, ("%s: %s needs %s, which the campaign never turns in"):format(race, qname(q), qname(pq)))
                                        end
                                    end
                                end
                                local single = QuestDB.Get(q, "preQuestSingle") or {}
                                if #single > 0 then
                                    local any, possible, later = false, false, nil
                                    for _, pq in ipairs(single) do
                                        if pq < 0 or state[pq] == "T" then any = true end
                                        if pq > 0 and raceOk(pq, race) and not isClassQuest(pq) then possible = true later = later or (onPath[pq] and pq) end
                                    end
                                    if not any and possible and standalone and not later then
                                        local elsewhere = false
                                        for _, pq in ipairs(single) do if anywhere[faction][pq] then elsewhere = true end end
                                        if not elsewhere then report("warn", pg, where, ("%s: %s needs one of %s, which no guide turns in"):format(race, qname(q), table.concat(single, ","))) end
                                    elseif not any and possible then
                                        if later then
                                            report("ERR", pg, where, ("%s: %s accepted before its prerequisite %s is turned in (at %s)"):format(race, qname(q), qname(later), onPath[later]))
                                        else
                                            report("ERR", pg, where, ("%s: %s needs one of %s, which the campaign never turns in"):format(race, qname(q), table.concat(single, ",")))
                                        end
                                    end
                                end
                                for _, x in ipairs(QuestDB.Get(q, "exclusiveTo") or {}) do
                                    if state[x] then report("ERR", pg, where, ("%s: %s is exclusive with %s, taken earlier"):format(race, qname(q), qname(x))) end
                                end
                                local parent = QuestDB.Get(q, "parentQuest") or 0
                                if parent > 0 and state[parent] ~= "A" and not (standalone and not state[parent]) then
                                    report("ERR", pg, where, ("%s: %s is only offered while %s is in the log"):format(race, qname(q), qname(parent)))
                                end
                                local bc = QuestDB.Get(q, "breadcrumbForQuestId") or 0
                                if bc > 0 and state[bc] then report("ERR", pg, where, ("%s: breadcrumb %s comes after %s"):format(race, qname(q), qname(bc))) end
                                state[q] = "A"
                                acceptedAt[q] = pg.id .. ":" .. i
                                log[q] = true
                                logSize = logSize + 1
                                if logSize > maxLog then maxLog, maxAt = logSize, pg.id .. ":" .. i end
                                if logSize > 20 then report("ERR", pg, where, ("%s: quest log holds %d quests"):format(race, logSize)) end
                            end
                        elseif kind == "complete" then
                            if state[q] ~= "A" and not (standalone and not state[q] and acceptedAnywhere[faction][q]) then report("ERR", pg, where, ("%s: complete %s which is not in the log"):format(race, qname(q))) end
                        elseif kind == "turnin" then
                            if state[q] ~= "A" and not (standalone and not state[q] and acceptedAnywhere[faction][q]) then
                                report("ERR", pg, where, ("%s: turn in %s which is not in the log"):format(race, qname(q)))
                            end
                            if log[q] then log[q] = nil logSize = logSize - 1 end
                            state[q] = "T"
                        end
                    end
                end
            end
        end
    end
    for q in pairs(log) do
        local at = acceptedAt[q]
        local gid = at:match("^(.-):")
        report("warn", byId[gid], at:match(":(%d+)$"), ("%s: %s accepted but never turned in"):format(race, qname(q)))
    end
    local ids = {}
    for _, pg in ipairs(path) do ids[#ids + 1] = pg.id end
    if standalone then return end
    if not QUIET then print(("%s %s: %d guides, largest quest log %d (%s)"):format(faction, race, #path, maxLog, tostring(maxAt))) end
    if not QUIET then print("    " .. table.concat(ids, " > ")) end
end

if ONLY then
    -- each selected guide on its own, for every race of its faction it suits
    for _, g in ipairs(guides) do
        if selected(g) and FACTION_RACES[g.faction] then
            for _, race in ipairs(FACTION_RACES[g.faction]) do
                local fits = not g.races
                for _, r in ipairs(g.races or {}) do if r == race then fits = true end end
                if fits then walk(g.faction, race, { g }, true) end
            end
        end
    end
end
for faction, races in pairs(FACTION_RACES) do
    for _, race in ipairs(races) do
        local path = campaignPath(faction, race)
        if path then walk(faction, race, path, false) end
    end
end
for _, g in ipairs(guides) do
    if not reached[g.id] then report("warn", g, nil, "no race reaches this guide through next links") end
end
for _, f in ipairs(unlisted) do print("  note: " .. f .. " is not listed in TashGuides.toc") end

local steps = 0
for _, g in ipairs(guides) do steps = steps + #(g.steps or {}) end
print(("%d guides, %d steps, %d error(s), %d warning(s)"):format(#guides, steps, errors, warnings))
print(errors == 0 and "GUIDES OK" or "GUIDES HAVE ERRORS")
os.exit(errors == 0 and 0 or 1)
