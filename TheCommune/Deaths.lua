local _,TC=...
local active=false
local function NativeDeaths()
    if type(GetStatistic)~="function" then return end
    local ok,value=pcall(GetStatistic,60)
    if not ok or (issecretvalue and issecretvalue(value)) then return end
    if type(value)=="string" then
        if value:match("^%s*%-") then return end
        value=tonumber((value:gsub("[^0-9]","")))
    end
    return TC.Integer(value,0,999999999)
end
function TC.RefreshDeathStats(send)
    if not TC.db or not TC.db.fun or not TC.db.fun.pvp then return end
    local p=TC.db.fun.pvp[TC.owner]; if not p then return end
    local value=NativeDeaths(); local lifetime=value~=nil or p.deathsLifetime==true
    if value==nil then value=p.deaths or p.deathsObserved or 0 end
    if lifetime and p.deathsLifetime then value=math.max(value,p.deaths or 0) end
    if value~=p.deaths or lifetime~=p.deathsLifetime then
        p.deaths=value; p.deathsLifetime=lifetime; p.deathRevision=math.max(time(),(p.deathRevision or 0)+1)
        if send then TC.BroadcastPvP() end
        if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end
    end
end
function TC.BroadcastDeaths(p)
    if p.deaths~=nil then TC.QueueGuildPacket("pvp-deaths",table.concat({"PT",p.deathRevision or 0,p.deaths,p.deathsLifetime and 1 or 0},"\t")) end
end
function TC.ReceiveDeaths(message,sender)
    if message:sub(1,3)~="PT\t" then return false end
    local revision,count,source=message:match("^PT\t(%d+)\t(%d+)\t([01])$")
    revision=TC.Integer(revision,0,time()+86400); count=TC.Integer(count,0,999999999)
    if not revision or not count then return true end
    local all=TC.store.social.pvp
    all[sender]=all[sender] or {revision=0,total=0,fair=0,higher=0,below3=0,below6=0,below10=0,unknown=0,diffs={}}
    local p=all[sender]
    if revision>=(p.deathRevision or 0) then p.deaths=count; p.deathRevision=revision; p.deathsLifetime=source=="1" end
    if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end; return true
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST","PLAYER_ENTERING_WORLD","ACHIEVEMENT_EARNED","CRITERIA_UPDATE"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event)
    if not TC.db or not TC.db.fun or not TC.db.fun.pvp then return end
    local p=TC.db.fun.pvp[TC.owner]; if not p then return end
    if event=="PLAYER_DEAD" then
        if active then return end; active=true
        p.deathsObserved=(p.deathsObserved or 0)+1
        if not p.deathsLifetime and NativeDeaths()==nil then p.deaths=nil end
        local owner,store=TC.owner,TC.store
        C_Timer.After(1,function() if TC.owner==owner and TC.store==store then TC.RefreshDeathStats(true) end end)
    elseif event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST" then
        local dead=false
        if UnitIsDeadOrGhost then local ok,value=pcall(UnitIsDeadOrGhost,"player"); dead=ok and not (issecretvalue and issecretvalue(value)) and value end
        if not dead then active=false end
    elseif event=="PLAYER_ENTERING_WORLD" and UnitIsDeadOrGhost then
        local ok,value=pcall(UnitIsDeadOrGhost,"player")
        if ok and not (issecretvalue and issecretvalue(value)) then active=not not value end
    end
    TC.RefreshDeathStats(true)
end)
