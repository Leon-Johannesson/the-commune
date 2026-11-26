local _, TC = ...
local seenNews = {}

local function Safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function Status(level, text)
    TC.db.levelAnnouncementStatus=TC.db.levelAnnouncementStatus or {}
    TC.db.levelAnnouncementStatus[TC.owner]={level=level,when=time(),text=text}
end
function TC.DebugLevels()
    local status=TC.db and TC.db.levelAnnouncementStatus and TC.db.levelAnnouncementStatus[TC.owner]
    TC.Print("Level announcements: seen "..tostring(TC.db and TC.db.levelAnnouncements and TC.db.levelAnnouncements[TC.owner] or "none")..
        " | "..(status and ("level "..status.level..": "..status.text) or "no send attempted this version"))
end

-- This client blocks SendChatMessage for addons, so a level-up cannot reach
-- real guild chat at all. Carry it over the addon channel instead and let each
-- guildmate's copy print it, the way death news already travels.
local function Show(owner, level)
    TC.Print(TC.DisplayName(owner) .. " reached level " .. level .. "!")
end

local function Announce(level)
    if not TC.db or not TC.guildKey then Status(level, "no guild store to broadcast to"); return end
    -- The level is the only claim on the wire. Every receiver names the sender
    -- the transport proved, so a packet cannot level somebody else up.
    TC.QueueGuildPacket("level-news:" .. level, table.concat({"LA", time(), level}, "\t"))
    Status(level, "broadcast to the guild")
    Show(TC.owner, level)
end

function TC.ReceiveLevelNews(message, sender)
    if type(message) ~= "string" or #message > 254 or message:sub(1, 3) ~= "LA\t" then return false end
    local when, level = message:match("^LA\t(%d+)\t(%d+)$")
    when = TC.Integer(when, 1, time() + 86400)
    level = TC.Integer(level, 1, 255)
    if not when or not level or sender == TC.owner then return true end
    -- A level-up is live news, not a record: never replay a stale one from a
    -- late relay, and never print the same one twice.
    if math.abs(time() - when) > 120 or (seenNews[sender] or 0) >= when then return true end
    seenNews[sender] = when
    Show(sender, level)
    return true
end

local events = CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_LEVEL_UP","PLAYER_LEVEL_CHANGED"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent", function(_, event, level, newLevel, real)
    if not TC.db or not TC.owner then return end
    TC.db.levelAnnouncements = TC.db.levelAnnouncements or {}
    local seen = TC.db.levelAnnouncements
    local previous = TC.Integer(seen[TC.owner], 1, 255) or 0
    if event == "PLAYER_LOGIN" then
        -- Installing or reloading is not a level-up, and old milestones are
        -- never replayed into a guild joined later.
        local current = TC.Integer(Safe(UnitLevel, "player"), 1, 255)
        if current then seen[TC.owner] = current end
        return
    end
    if event=="PLAYER_LEVEL_CHANGED" then
        if (issecretvalue and issecretvalue(real)) or real~=true then return end
        local old=TC.Integer(Safe(function() return level end),1,255)
        newLevel=TC.Integer(Safe(function() return newLevel end),1,255)
        if not old or not newLevel or newLevel<=old then return end
        level=newLevel
    end
    level=TC.Integer(Safe(function() return level end),1,255)
    if not level or level<=previous then return end
    seen[TC.owner]=level
    if level%2~=0 then return end
    local guild=Safe(GetGuildInfo,"player")
    if (type(guild)~="string" or guild=="") and Safe(IsInGuild)~=true then
        Status(level,"not in a guild at level-up"); return
    end
    Announce(level)
end)
