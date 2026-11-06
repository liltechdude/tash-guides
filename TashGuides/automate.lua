-- TashGuides automate.lua: optional auto-accept / auto turn-in (both off by default).
-- Hold Shift while talking to an NPC to handle quests yourself. A reward choice is never made
-- for you: when a quest offers several rewards the window stays open.

local TG = TashGuides
local AU = {}
TG.Automate = AU

local function suppressed() return IsShiftKeyDown() end

local function onDetail()
    if not TG.db.autoAccept or suppressed() then return end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
    elseif AcceptQuest then
        AcceptQuest()
    end
end

local function onProgress()
    if not TG.db.autoTurnIn or suppressed() then return end
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then CompleteQuest() end
end

local function onComplete()
    if not TG.db.autoTurnIn or suppressed() then return end
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if choices <= 1 and GetQuestReward then GetQuestReward(choices) end
end

-- Gossip window: hand in finished quests first, then pick up new ones (one per window update).
local function onGossip()
    if suppressed() then return end
    local G = C_GossipInfo
    if TG.db.autoTurnIn then
        if G and G.GetActiveQuests then
            for _, q in ipairs(G.GetActiveQuests() or {}) do
                if q.isComplete and q.questID then G.SelectActiveQuest(q.questID) return end
            end
        elseif GetGossipActiveQuests and SelectGossipActiveQuest then
            local info = { GetGossipActiveQuests() }
            local stride = 6
            for i = 1, #info / stride do
                if info[(i - 1) * stride + 4] then SelectGossipActiveQuest(i) return end
            end
        end
    end
    if TG.db.autoAccept then
        if G and G.GetAvailableQuests then
            for _, q in ipairs(G.GetAvailableQuests() or {}) do
                if q.questID and not q.isTrivial then G.SelectAvailableQuest(q.questID) return end
            end
        elseif GetGossipAvailableQuests and SelectGossipAvailableQuest then
            local info = { GetGossipAvailableQuests() }
            local stride = 7
            for i = 1, #info / stride do
                if not info[(i - 1) * stride + 3] then SelectGossipAvailableQuest(i) return end
            end
        end
    end
end

-- Quest greeting window (NPCs with several quests and no gossip).
local function onGreeting()
    if suppressed() then return end
    if TG.db.autoTurnIn and GetNumActiveQuests then
        for i = 1, GetNumActiveQuests() do
            local _, complete = GetActiveTitle(i)
            if complete then SelectActiveQuest(i) return end
        end
    end
    if TG.db.autoAccept and GetNumAvailableQuests then
        for i = 1, GetNumAvailableQuests() do
            local trivial = IsAvailableQuestTrivial and IsAvailableQuestTrivial(i)
            if not trivial then SelectAvailableQuest(i) return end
        end
    end
end

function AU.Init()
    TG.On("QUEST_DETAIL", onDetail)
    TG.On("QUEST_PROGRESS", onProgress)
    TG.On("QUEST_COMPLETE", onComplete)
    TG.On("GOSSIP_SHOW", onGossip)
    TG.On("QUEST_GREETING", onGreeting)
end
