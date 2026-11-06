-- Offline loader for the installed QuestieDB (baked mode) so TashGuides data can be
-- checked against the real WoW Forever database without launching the game.
--   luajit tests/qdb_harness.lua            -> loads and prints a summary
-- Other test scripts `dofile` this and then use QuestDB / NpcDB / ... globals.

local QDB = os.getenv("QDB") or "/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestieDB"
local TOC = QDB .. "/QuestieDB_Forever.toc"

-- ---- parse TOC: metadata + file list ------------------------------------
local meta, files = {}, {}
for line in io.lines(TOC) do
    line = line:gsub("\r$", "")
    local k, v = line:match("^##%s*([^:]+):%s?(.*)$")
    if k then
        meta[k] = v
    elseif line ~= "" and not line:match("^#") then
        files[#files + 1] = line:gsub("\\", "/")
    end
end

-- ---- minimal client stand-ins -------------------------------------------
local function noop() end
_G.C_AddOns = { GetAddOnMetadata = function(_, key) return meta[key] end }
_G.GetAddOnMetadata = _G.C_AddOns.GetAddOnMetadata
_G.UnitFactionGroup = function() return os.getenv("FACTION") or "Alliance" end
_G.GetLocale = function() return "enUS" end
_G.GetBuildInfo = function() return "1.60.1", "70291", "Nov 1 2026", 16001 end
_G.CreateFrame = function()
    return setmetatable({}, { __index = function() return noop end })
end
_G.UIParent = CreateFrame()
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) io.stderr:write(tostring(m), "\n") end }
_G.print = _G.print
_G.geterrorhandler = function() return function(e) io.stderr:write("ERR ", tostring(e), "\n") end end
_G.C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
_G.hooksecurefunc = noop
_G.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert, _G.tremove = table.insert, table.remove
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.format = string.format
_G.UnitClassBase = function() return os.getenv("CLASS") or "WARRIOR", 1 end
_G.UnitClass = function() return "Warrior", os.getenv("CLASS") or "WARRIOR", 1 end
_G.UnitRace = function() return "Human", os.getenv("RACE") or "Human", 1 end
_G.UnitLevel = function() return 1 end
-- Any other Unit*/Get*/Is* client call reads as "unknown" (nil) offline.
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" and (k:match("^Unit") or k:match("^Get") or k:match("^Is")) then
        return noop
    end
end })

dofile((debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./") .. "encoding_shim.lua")
local ns = {}
for _, rel in ipairs(files) do
    local chunk, err = loadfile(QDB .. "/" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err)) end
    local ok, e = pcall(chunk, "QuestieDB", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(e)) end
end

if arg and arg[0] and arg[0]:match("qdb_harness%.lua$") then
    local n = #QuestDB.GetAllIds()
    print(("QuestieDB loaded: mode=%s quests=%d npcs=%d"):format(
        tostring(LibQuestieDB.readMode), n, #NpcDB.GetAllIds()))
    print("783:", QuestDB.name(783), "starter npc", (QuestDB.Get(783, "startedBy") or {})[1] and QuestDB.Get(783, "startedBy")[1][1])
end

return ns
