-- TashGuides chains.lua: class and racial quest chains as their own guides.
--
-- At login every QuestieDB quest is classified for this character:
--   "class"  requiredClasses names this class and leaves out at least one other class
--            (trainer letters, class quest lines), or the quest has no class flag but only
--            trainers of this class hand it out (availability.lua, AV.InferredClass);
--   "race"   not a class quest, requiredRaces names this race and leaves out at least one
--            other race of the same faction (racial quest lines).
-- Each set becomes a guide ("Warrior quests", "Human quests") ordered by level with
-- prerequisites first. Profession quests (requiredSkill) are grouped per profession into
-- their own guides ("Alchemy quests"), ordered by the skill they need. These guides stand apart from the main guides (zone guides and the
-- Smart Guide, which are for every player). The main guides pull the same quests in while
-- "include class & race quests" is on (TG.db.includeChains, on by default):
--   * zone guides show their steps tagged chain = "class" / "race";
--   * the Smart Guide adds every class/racial quest you can take or have in your log,
--     wherever it is, ahead of ordinary quests at a similar distance.

local TG = TashGuides
local DB, AV, QL = TG.DB, TG.Avail, TG.QuestLog
local Chains = { kind = {}, lists = { class = {}, race = {} }, professions = {} }
TG.Chains = Chains

-- Profession skill lines (QuestieDB requiredSkill = { skillId, minValue }).
Chains.PROFESSIONS = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
    [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning",
    [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [356] = "Fishing",
    [755] = "Jewelcrafting", [773] = "Inscription", [762] = "Riding",
}

-- { skillId, minValue } of a profession quest, or nil.
function Chains.SkillOf(qid)
    local req = DB.Quest(qid, "requiredSkill")
    if type(req) == "table" then return tonumber(req[1]), tonumber(req[2]) or 0 end
    if type(req) == "number" then return req, 0 end
    return nil
end

-- Lowercase names of the skills this character has (empty when the client does not say).
function Chains.KnownSkills()
    local set = {}
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() or 0 do
            local name, header = GetSkillLineInfo(i)
            name, header = TG.Safe(name), TG.Safe(header)
            if type(name) == "string" and not header then set[name:lower()] = true end
        end
    end
    return set
end

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
    Chains.professions = {}
    local ids = DB.QuestIds() or {}
    for i = 1, #ids do
        local qid = ids[i]
        local cmask = DB.Quest(qid, "requiredClasses") or 0
        local rmask = DB.Quest(qid, "requiredRaces") or 0
        local kind
        if (classSpecific(cmask) or (cmask == 0 and AV.classFile and AV.InferredClass(qid) == AV.classFile))
            and AV.RaceOk(qid) then kind = "class"
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
        else
            -- profession quests the character could ever take, grouped by skill
            local skill = Chains.SkillOf(qid)
            if skill and Chains.PROFESSIONS[skill] and AV.ForPlayer(qid) and not DB.IsRepeatable(qid)
                and (DB.Quest(qid, "requiredLevel") or 0) <= 60 and DB.QuestName(qid)
                and #DB.Starters(qid) > 0 then
                local list = Chains.professions[skill]
                if not list then list = {}; Chains.professions[skill] = list end
                list[#list + 1] = qid
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Guide steps: level order, prerequisites first, one step per quest.
-- ---------------------------------------------------------------------------

local function sortLevel(q) return math.max(DB.Quest(q, "requiredLevel") or 0, 1), DB.QuestLevel(q) end

-- Profession quests sort by the skill they need first, then level.
local function profKey(q)
    local _, minSkill = Chains.SkillOf(q)
    return minSkill or 0, sortLevel(q)
end

local function levelKey(q)
    local r, l = sortLevel(q)
    return r, l, 0
end

local function ordered(list, key)
    key = key or levelKey
    local set = {}
    for _, q in ipairs(list) do set[q] = true end
    local sorted = {}
    for i, q in ipairs(list) do sorted[i] = q end
    table.sort(sorted, function(a, b)
        local a1, a2, a3 = key(a)
        local b1, b2, b3 = key(b)
        if a1 ~= b1 then return a1 < b1 end
        if a2 ~= b2 then return a2 < b2 end
        if (a3 or 0) ~= (b3 or 0) then return (a3 or 0) < (b3 or 0) end
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

-- One step per profession quest: skill requirement, level and where it starts.
function Chains.ProfSteps(skill)
    local steps = {}
    local name = Chains.PROFESSIONS[skill] or "Profession"
    for _, q in ipairs(ordered(Chains.professions[skill] or {}, profKey)) do
        local _, minSkill = Chains.SkillOf(q)
        local step = { title = DB.QuestName(q), quest = q, chain = "prof", { "accept", q } }
        if #DB.Objectives(q) > 0 then step[#step + 1] = { "complete", q } end
        step[#step + 1] = { "turnin", q }
        local where = whereText(q)
        step.note = ("%s%s - level %d%s"):format(name, minSkill > 0 and (" " .. minSkill) or "",
            DB.QuestLevel(q), where and (" - " .. where) or "")
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
    local profs = {}
    for skill, list in pairs(Chains.professions) do
        if #list >= 2 then profs[#profs + 1] = skill end
    end
    table.sort(profs)
    for _, skill in ipairs(profs) do
        local name = Chains.PROFESSIONS[skill]
        local list = Chains.professions[skill]
        local lo, hi = levelRange(list)
        TG.RegisterGuide({
            id = "PROF_" .. skill,
            title = name .. " quests",
            subtitle = function() return ("%d %s quests"):format(#list, name:lower()) end,
            learned = function() return Chains.KnownSkills()[name:lower()] == true end,
            chain = "prof", group = "prof",
            hideUnavailable = true,
            minLevel = lo, maxLevel = hi,
            steps = Chains.ProfSteps(skill),
        })
    end
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
