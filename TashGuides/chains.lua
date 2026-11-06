-- TashGuides chains.lua: class and racial quest chains as their own guides.
--
-- At login every QuestieDB quest is classified for this character:
--   "class"  requiredClasses names this class and leaves out at least one other class
--            (trainer letters, class quest lines);
--   "race"   not a class quest, requiredRaces names this race and leaves out at least one
--            other race of the same faction (racial quest lines).
-- Each set becomes a guide ("Warrior quests", "Human quests") ordered by level with
-- prerequisites first. These guides stand apart from the main guides (zone guides and the
-- Smart Guide, which are for every player). The main guides pull the same quests in while
-- "include class & race quests" is on (TG.db.includeChains, on by default):
--   * zone guides show their steps tagged chain = "class" / "race";
--   * the Smart Guide adds every class/racial quest you can take or have in your log,
--     wherever it is, ahead of ordinary quests at a similar distance.

local TG = TashGuides
local DB, AV, QL = TG.DB, TG.Avail, TG.QuestLog
local Chains = { kind = {}, lists = { class = {}, race = {} } }
TG.Chains = Chains

-- Playable classes (class id -> bit) and the original races of each faction. Newer races
-- are not listed on purpose: a quest open to every original race of the faction is a
-- faction quest, not a racial one, whatever newer bits its mask carries.
local CLASS_IDS = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }
local FACTION_RACES = { Alliance = { 1, 3, 4, 7 }, Horde = { 2, 5, 6, 8 } }

local function bitOf(id) return 2 ^ (id - 1) end

local function classSpecific(mask)
    if mask == 0 or not AV.classBit or not TG.HasBit(mask, AV.classBit) then return false end
    for _, id in ipairs(CLASS_IDS) do
        if not TG.HasBit(mask, bitOf(id)) then return true end
    end
    return false
end

local function raceSpecific(mask)
    if mask == 0 or not AV.raceBit or not TG.HasBit(mask, AV.raceBit) then return false end
    local races = FACTION_RACES[UnitFactionGroup("player") or ""]
    if not races then return false end
    for _, id in ipairs(races) do
        if not TG.HasBit(mask, bitOf(id)) then return true end
    end
    return false
end

function Chains.Kind(qid) return qid and Chains.kind[qid] or nil end
function Chains.Count(kind) return #(Chains.lists[kind] or {}) end

-- Is this quest part of the main guides right now? (chain quests only with the toggle on)
function Chains.Allowed(qid)
    return not Chains.kind[qid] or TG.Guide.ChainsIncluded()
end

function Chains.Scan()
    wipe(Chains.kind)
    Chains.lists = { class = {}, race = {} }
    local ids = DB.QuestIds() or {}
    for i = 1, #ids do
        local qid = ids[i]
        local cmask = DB.Quest(qid, "requiredClasses") or 0
        local rmask = DB.Quest(qid, "requiredRaces") or 0
        local kind
        if classSpecific(cmask) and AV.RaceOk(qid) then kind = "class"
        elseif rmask ~= 0 and raceSpecific(rmask) and AV.ClassOk(qid) then kind = "race" end
        -- Leave out repeatables, profession quests, and quests nobody friendly hands out.
        if kind and (DB.IsRepeatable(qid) or DB.Quest(qid, "requiredSkill") ~= nil or #DB.Starters(qid) == 0
            or not DB.QuestName(qid)) then
            kind = nil
        end
        if kind then
            Chains.kind[qid] = kind
            local list = Chains.lists[kind]
            list[#list + 1] = qid
        end
    end
end

-- ---------------------------------------------------------------------------
-- Guide steps: level order, prerequisites first, one step per quest.
-- ---------------------------------------------------------------------------

local function sortLevel(q) return math.max(DB.Quest(q, "requiredLevel") or 0, 1), DB.QuestLevel(q) end

local function ordered(list)
    local set = {}
    for _, q in ipairs(list) do set[q] = true end
    local sorted = { unpack(list) }
    table.sort(sorted, function(a, b)
        local ra, la = sortLevel(a)
        local rb, lb = sortLevel(b)
        if ra ~= rb then return ra < rb end
        if la ~= lb then return la < lb end
        return a < b
    end)
    local state, out = {}, {}
    local function place(q)
        if state[q] then return end
        state[q] = true
        for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
            for _, p in ipairs(DB.Quest(q, key) or {}) do
                if set[p] then place(p) end
            end
        end
        out[#out + 1] = q
    end
    for _, q in ipairs(sorted) do place(q) end
    return out
end

local function whereText(q)
    local s = DB.Starters(q)[1]
    if not s then return nil end
    if s.kind == "item" then return "Starts from " .. s.name end
    local p = s.points[1]
    return s.name .. (p and (" in " .. TG.MapName(p.map)) or "")
end

function Chains.Steps(kind)
    local steps = {}
    for _, q in ipairs(ordered(Chains.lists[kind] or {})) do
        local lvl = DB.QuestLevel(q)
        local step = { title = DB.QuestName(q), quest = q, chain = kind,
            { "accept", q } }
        if #DB.Objectives(q) > 0 then step[#step + 1] = { "complete", q } end
        step[#step + 1] = { "turnin", q }
        local where = whereText(q)
        step.note = ("Level %d%s"):format(lvl, where and (" - " .. where) or "")
        steps[#steps + 1] = step
    end
    return steps
end

local function levelRange(list)
    local lo, hi
    for _, q in ipairs(list) do
        local l = sortLevel(q)
        lo = (not lo or l < lo) and l or lo
        hi = (not hi or l > hi) and l or hi
    end
    return lo or 1, hi or 60
end

function Chains.Init()
    Chains.Scan()
    local className = UnitClass("player")
    local raceName = UnitRace("player")
    for _, kind in ipairs({ "class", "race" }) do
        local list = Chains.lists[kind]
        if #list > 0 then
            local lo, hi = levelRange(list)
            TG.RegisterGuide({
                id = kind == "class" and "CHAIN_CLASS" or "CHAIN_RACE",
                title = ((kind == "class" and className or raceName) or (kind == "class" and "Class" or "Racial")) .. " quests",
                subtitle = kind == "class" and "your class quest chain" or "your racial quest chain",
                chain = kind,
                hideUnavailable = true,
                minLevel = lo, maxLevel = hi,
                steps = Chains.Steps(kind),
            })
        end
    end
end
