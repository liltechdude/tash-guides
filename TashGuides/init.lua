-- TashGuides init.lua: start-up order. Everything waits for PLAYER_LOGIN so saved variables,
-- QuestieDB and the player's quest state are all available.

local TG = TashGuides

local MODULES = {
    { "QuestLog", "QuestLog" },
    { "Avail", "Availability" },
    { "Chains", "Class & race chains" },
    { "Zones", "Zone guides" },
    { "Viewer", "Guide window" },
    { "Steps", "Steps panel" },
    { "Arrow", "Arrow" },
    { "Tracker", "Quest tracker" },
    { "Pins", "Map pins" },
    { "Tooltip", "Tooltips" },
    { "Automate", "Automation" },
    { "Options", "Options" },
}

local function boot()
    TG.LoadSettings()
    local ok, err = TG.DB.Init()
    if not ok then
        TG.initError = err
        TG.Print("|cffff4444could not start|r - %s", tostring(err))
        return
    end
    for _, m in ipairs(MODULES) do
        local mod = TG[m[1]]
        local good, e = pcall(mod.Init)
        if not good then
            TG.Report(("TashGuides %s failed to start: %s"):format(m[2], tostring(e)))
        end
    end
    TG.ready = true
    -- The guide engine needs the quest log and availability in place, so it starts last.
    local good, e = pcall(TG.Guide.Init)
    if not good then TG.Report("TashGuides guide engine failed to start: " .. tostring(e)) end
    TG.Fire("TG_SETTINGS")
    TG.Print("v%s ready - %s. Type %s for commands.", TG.VERSION,
        TG.Guide.active and TG.Color(TG.C.gold, TG.Guide.active.title) or "no guide",
        TG.Color(TG.C.accent, "/tg help"))
end

TG.On("PLAYER_LOGIN", function()
    local ok, err = pcall(boot)
    if not ok then
        TG.initError = tostring(err)
        TG.Report(err)
    end
end)
