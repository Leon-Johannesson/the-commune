local _,TC=...
local observed,duplicates={},{}
-- Registering CLEU itself is protected on modern/Forever clients. pcall does
-- not suppress ADDON_ACTION_FORBIDDEN, so never probe it by registering.
local combatEventAvailable=false
local function Safe(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function Empty()
    return {revision=0,total=0,fair=0,higher=0,below3=0,below6=0,below10=0,unknown=0,diffs={}}
end
local version=Safe(GetBuildInfo)
local major=type(version)=="string" and tonumber(version:match("^(%d+)"))
local legacyCombat=major and major<12 and not issecretvalue and not C_Secrets
function TC.PvPStatus()
    if not combatEventAvailable or type(CombatLogGetCurrentEventInfo)~="function" then return "Combat tracking unavailable on this client." end
    if C_CombatLog and Safe(C_CombatLog.IsCombatLogRestricted)==true then return "Client combat data is restricted; kills cannot currently be tracked." end
    return "Tracking exposed combat events. Unknown/skull levels stay unknown; no backfill."
end
function TC.InitPvP()
    TC.db.fun.pvp=TC.db.fun.pvp or {}
    TC.db.fun.pvp[TC.owner]=TC.db.fun.pvp[TC.owner] or Empty()
    TC.store.social.pvp=TC.store.social.pvp or {}
    TC.store.social.pvp[TC.owner]=TC.db.fun.pvp[TC.owner]
    TC.RefreshHonorStats(false)
    TC.RefreshDeathStats(false)
end
function TC.RefreshHonorStats(send)
    if not TC.db or not TC.db.fun or not TC.db.fun.pvp then return end
    local value=TC.Integer(Safe(GetPVPLifetimeStats),0,999999999)
    local p=TC.db.fun.pvp[TC.owner]
    if value and p and value~=p.honorKills then
        p.honorKills=value; p.honorRevision=math.max(time(),(p.honorRevision or 0)+1)
        if send then TC.BroadcastPvP() end
        if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end
    end
end
function TC.ObservePvPUnit(unit)
    if not TC.db or not TC.db.fun or Safe(UnitIsPlayer,unit)~=true then return end
    local guid=Safe(UnitGUID,unit)
    if type(guid)~="string" or not guid:match("^Player%-") then return end
    local level=Safe(UnitLevel,unit)
    level=TC.Integer(level,1,255)
    if level or not observed[guid] then observed[guid]={level=level,when=GetTime()} end
end
function TC.RecordPvPKill(timestamp,event,sourceGUID,destGUID)
    for _,value in pairs({timestamp,event,sourceGUID,destGUID}) do if issecretvalue and issecretvalue(value) then return end end
    if event~="PARTY_KILL" or not TC.store or not TC.store.social or not TC.db.fun.pvp then return end
    if type(destGUID)~="string" or not destGUID:match("^Player%-") then return end
    local player=Safe(UnitGUID,"player"); local pet=Safe(UnitGUID,"pet")
    if not player or (sourceGUID~=player and (not pet or sourceGUID~=pet)) or destGUID==player then return end
    local now=GetTime()
    if duplicates[destGUID] and now-duplicates[destGUID]<2 then return end
    duplicates[destGUID]=now
    TC.ObservePvPUnit("target"); TC.ObservePvPUnit("mouseover")
    local enemy=observed[destGUID]; local own=TC.Integer(Safe(UnitLevel,"player"),1,255)
    local diff=enemy and now-enemy.when<=30 and own and enemy.level and enemy.level-own or nil
    local p=TC.db.fun.pvp[TC.owner]; p.total=p.total+1
    local bucket="unknown"
    if diff then
        bucket=math.abs(diff)<=2 and "fair" or diff>=3 and "higher" or diff>=-5 and "below3" or diff>=-9 and "below6" or "below10"
        p.diffs[diff]=(p.diffs[diff] or 0)+1
    end
    p[bucket]=p[bucket]+1; p.revision=math.max(time(),p.revision+1)
    TC.BroadcastPvP()
    if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end
    return true
end
function TC.BroadcastPvP()
    if not TC.guildKey or not TC.db.fun.pvp then return end
    local p=TC.db.fun.pvp[TC.owner]; if not p then return end
    TC.BroadcastDeaths(p)
    if p.honorKills~=nil then TC.QueueGuildPacket("pvp-honor",table.concat({"PH",p.honorRevision or 0,p.honorKills},"\t")) end
    TC.QueueGuildPacket("pvp-head",table.concat({"PK",p.revision,p.total,p.fair,p.higher,p.below3,p.below6,p.below10,p.unknown},"\t"))
    for diff,count in pairs(p.diffs) do TC.QueueGuildPacket("pvp-gap:"..diff,table.concat({"PL",p.revision,diff,count},"\t")) end
end
function TC.ReceivePvP(message,sender)
    if TC.ReceiveDeaths(message,sender) then return true end
    local kind=message:match("^([^\t]+)"); if kind~="PK" and kind~="PL" and kind~="PH" then return false end
    local f={}; for value in (message.."\t"):gmatch("(.-)\t") do f[#f+1]=value end
    local rev=TC.Integer(f[2],0,time()+86400); if not rev then return true end
    local all=TC.store.social.pvp
    if kind=="PH" then
        local value=TC.Integer(f[3],0,999999999)
        if #f~=3 or not value then return true end
        local p=all[sender] or Empty()
        if rev>=(p.honorRevision or 0) then p.honorKills=value; p.honorRevision=rev; all[sender]=p end
    elseif kind=="PK" then
        if #f~=9 then return true end
        local values={}; for i=3,9 do values[i]=TC.Integer(f[i],0,999999999); if not values[i] then return true end end
        local sum=0; for i=4,9 do sum=sum+values[i] end; if sum~=values[3] then return true end
        local p=all[sender] or Empty()
        if rev>=p.revision and values[3]>=p.total then
            p.revision,p.total,p.fair,p.higher,p.below3,p.below6,p.below10,p.unknown=rev,unpack(values,3,9)
            all[sender]=p
        end
    else
        local diff,count=TC.Integer(f[3],-254,254),TC.Integer(f[4],0,999999999)
        if #f~=4 or not diff or not count then return true end
        all[sender]=all[sender] or Empty()
        all[sender].diffs[diff]=math.max(all[sender].diffs[diff] or 0,count)
    end
    if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end; return true
end
function TC.PvPRows(shame)
    local rows={}
    for owner,p in pairs(TC.store.social.pvp or {}) do rows[#rows+1]={owner=owner,stats=p,label=TC.DisplayName(owner)} end
    -- Characters that share a given name read as one player while no surname is
    -- known, so name the stored key on the rows that still collide.
    local counts={}; for _,r in ipairs(rows) do counts[r.label]=(counts[r.label] or 0)+1 end
    for _,r in ipairs(rows) do if counts[r.label]>1 then r.label=r.label.." ("..(r.owner:match("%-(.+)$") or r.owner)..")" end end
    table.sort(rows,function(a,b)
        local x,y=shame and a.stats.below10 or (a.stats.honorKills or a.stats.total),shame and b.stats.below10 or (b.stats.honorKills or b.stats.total)
        if x~=y then return x>y end; return a.owner<b.owner
    end)
    return rows
end
local frame=CreateFrame("Frame")
local events={"PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","NAME_PLATE_UNIT_ADDED","PLAYER_PVP_KILLS_CHANGED","HONOR_XP_UPDATE","PLAYER_ENTERING_WORLD"}
if legacyCombat then events[#events+1]="COMBAT_LOG_EVENT_UNFILTERED" end
for _,event in ipairs(events) do
    local ok=pcall(frame.RegisterEvent,frame,event)
    if event=="COMBAT_LOG_EVENT_UNFILTERED" then combatEventAvailable=ok end
end
frame:SetScript("OnEvent",function(_,event,unit)
    if not TC.db or not TC.db.fun then return end
    if event=="COMBAT_LOG_EVENT_UNFILTERED" then
        if not combatEventAvailable then return end
        if not CombatLogGetCurrentEventInfo then return end
        if C_CombatLog and Safe(C_CombatLog.IsCombatLogRestricted)==true then return end
        local ok,stamp,subevent,_,source,_,_,_,dest=pcall(CombatLogGetCurrentEventInfo)
        if ok then
            local secret=false
            for _,v in pairs({stamp,subevent,source,dest}) do if issecretvalue and issecretvalue(v) then secret=true end end
            if not secret then TC.RecordPvPKill(stamp,subevent,source,dest) end
        end
    elseif event=="PLAYER_PVP_KILLS_CHANGED" or event=="HONOR_XP_UPDATE" or event=="PLAYER_ENTERING_WORLD" then TC.RefreshHonorStats(true)
    else TC.ObservePvPUnit(event=="PLAYER_TARGET_CHANGED" and "target" or event=="UPDATE_MOUSEOVER_UNIT" and "mouseover" or unit) end
end)
local elapsed,honorElapsed=0,0
frame:SetScript("OnUpdate",function(_,delta)
    elapsed=elapsed+delta; if elapsed<5 then return end; elapsed=0
    honorElapsed=honorElapsed+5; if honorElapsed>=30 then honorElapsed=0; TC.RefreshHonorStats(true); TC.RefreshDeathStats(true) end
    local now=GetTime()
    for guid,r in pairs(observed) do if now-r.when>30 then observed[guid]=nil end end
    for guid,stamp in pairs(duplicates) do if now-stamp>5 then duplicates[guid]=nil end end
    TC.ObservePvPUnit("target"); TC.ObservePvPUnit("mouseover")
    local plates=C_NamePlate and Safe(C_NamePlate.GetNamePlates)
    if type(plates)=="table" and not (issecrettable and issecrettable(plates)) then
        for _,plate in ipairs(plates) do
            local unit=Safe(function() return plate.namePlateUnitToken end)
            if type(unit)=="string" then TC.ObservePvPUnit(unit) end
        end
    end
end)
