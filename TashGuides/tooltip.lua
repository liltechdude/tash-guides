-- TashGuides tooltip.lua: quest lines on unit and object tooltips.
-- Hover a mob to see which of your quests need it (with progress), and a quest giver to see
-- what they offer or are waiting for.

local TG = TashGuides
local DB, QL, AV = TG.DB, TG.QuestLog, TG.Avail
local TT = {}
TG.Tooltip = TT

local byNpc, byObjectName = {}, {}

-- npc id / object name -> list of { quest, objective index }
local function rebuild()
    wipe(byNpc)
    wipe(byObjectName)
    for id, q in pairs(QL.quests) do
        if not q.complete then
            local matched = DB.MatchObjectives(id, q.objectives)
            for i in ipairs(q.objectives) do
                local s = matched[i]
                if s then
                    for _, npc in ipairs(s.npcs or {}) do
                        local list = byNpc[npc] or {}
                        byNpc[npc] = list
                        list[#list + 1] = { quest = id, index = i }
                    end
                    for _, obj in ipairs(s.objects or {}) do
                        local name = DB.ObjectName(obj)
                        if name then
                            local list = byObjectName[name] or {}
                            byObjectName[name] = list
                            list[#list + 1] = { quest = id, index = i }
                        end
                    end
                end
            end
        end
    end
end

local function progressColor(o)
    if o.finished then return 0.3, 0.9, 0.35 end
    if o.have and o.need and o.need > 0 then
        local f = o.have / o.need
        return 1, 0.35 + 0.55 * f, 0.3
    end
    return 0.9, 0.9, 0.9
end

local function addObjectiveLines(tt, list)
    local lastQuest
    local seen = {}
    for _, ref in ipairs(list) do
        local q = QL.Get(ref.quest)
        local o = q and q.objectives[ref.index]
        local key = ref.quest .. ":" .. ref.index
        if o and not seen[key] then
            seen[key] = true
            if lastQuest ~= ref.quest then
                local c = TG.QuestColor(q.level)
                tt:AddLine(q.title, c[1], c[2], c[3])
                lastQuest = ref.quest
            end
            tt:AddLine("   " .. o.text, progressColor(o))
        end
    end
end

local function onUnit(tt)
    if not TG.ready or not TG.db.tooltips or tt ~= GameTooltip then return end
    local _, unit = tt:GetUnit()
    unit = TG.Safe(unit)
    if not unit then return end
    local id = TG.NpcIdFromGuid(UnitGUID(unit))
    if not id then return end
    local added = false
    local list = byNpc[id]
    if list then
        addObjectiveLines(tt, list)
        added = true
    end
    for _, qid in ipairs(DB.Npc(id, "questStarts") or {}) do
        if AV.IsAvailable(qid) then
            local lvl = DB.QuestLevel(qid)
            local c = TG.QuestColor(lvl)
            tt:AddLine("! " .. (DB.QuestName(qid) or "?") .. " (" .. lvl .. ")", c[1], c[2], c[3])
            added = true
        end
    end
    for _, qid in ipairs(DB.Npc(id, "questEnds") or {}) do
        local q = QL.Get(qid)
        if q then
            if q.complete then
                tt:AddLine("? Turn in: " .. q.title, TG.C.gold[1], TG.C.gold[2], TG.C.gold[3])
            else
                tt:AddLine("? " .. q.title .. " (not finished)", 0.6, 0.6, 0.6)
            end
            added = true
        end
    end
    if added then tt:Show() end
end

-- Game objects have no unit: match the tooltip's first line against objective object names.
local function onShow(tt)
    if not TG.ready or not TG.db.tooltips or tt ~= GameTooltip then return end
    if TG.Safe((tt:GetUnit())) then return end
    local first = _G.GameTooltipTextLeft1
    local name = first and TG.Safe(first:GetText())
    if type(name) ~= "string" then return end
    local list = name and byObjectName[name]
    if list and not tt.tgObjectDone then
        tt.tgObjectDone = true
        addObjectiveLines(tt, list)
        tt:Show()
    end
end

function TT.Init()
    rebuild()
    TG.On("TG_QUESTLOG", function() TG.Schedule("tooltip", 0.2, rebuild) end)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) onUnit(tt) end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", onUnit)
    end
    GameTooltip:HookScript("OnShow", onShow)
    GameTooltip:HookScript("OnHide", function(tt) tt.tgObjectDone = nil end)
end
