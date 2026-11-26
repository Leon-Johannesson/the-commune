local _, TC = ...
local pending, sending, blocked

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
local function Try(work)
    if pending~=work or TC.owner~=work.owner then return end
    if GetTime()-work.started>120 then
        pending=nil; Status(work.level,"expired before chat became available"); return
    end
    local guild=Safe(GetGuildInfo,"player")
    if Safe(IsInGuild)==false or (work.guild and type(guild)=="string" and guild~="" and guild~=work.guild) then
        pending=nil; Status(work.level,"cancelled after guild change"); return
    end
    if Safe(InCombatLockdown) or Safe(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) or type(guild)~="string" or guild=="" then
        Status(work.level,"waiting for combat/chat/guild readiness")
        C_Timer.After(2,function() Try(work) end); return
    end
    work.guild=work.guild or guild
    local send=C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send)~="function" then pending=nil; Status(work.level,"chat API unavailable"); return end
    work.attempts=work.attempts+1
    sending,blocked=true,false
    local ok,result=pcall(send,"[The Commune] Ding! I just reached level "..work.level.."!","GUILD")
    sending=false
    -- This API usually returns nil, so lack of an echo is not grounds to send
    -- twice. Retry only explicit rejection, an error, or a synchronous block.
    if ok and result~=false and not blocked then
        pending=nil; Status(work.level,"submitted to guild chat"); return
    end
    if work.attempts>=3 then
        pending=nil; Status(work.level,"failed after 3 attempts")
        TC.Print("Could not announce level "..work.level.." in guild chat. /commune debug includes the send status.")
    else
        Status(work.level,"send rejected; retry queued")
        C_Timer.After(work.attempts*3,function() Try(work) end)
    end
end
local events = CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_LEVEL_UP","PLAYER_LEVEL_CHANGED","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent", function(_, event, level, newLevel, real)
    if event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN" then
        if sending and level=="TheCommune" then blocked=true end
        return
    end
    if not TC.db or not TC.owner then return end
    TC.db.levelAnnouncements = TC.db.levelAnnouncements or {}
    local seen = TC.db.levelAnnouncements
    local previous = TC.Integer(seen[TC.owner], 1, 255) or 0
    if event == "PLAYER_LOGIN" then
        pending=nil
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
    local work={owner=TC.owner,level=level,guild=type(guild)=="string" and guild~="" and guild or nil,started=GetTime(),attempts=0}
    pending=work; Try(work)
end)
