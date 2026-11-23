local _,TC=...
local observed,duplicates={},{}
-- Registering CLEU itself is protected on modern/Forever clients. pcall does
-- not suppress ADDON_ACTION_FORBIDDEN, so never probe it by registering.
local combatEventAvailable, partyKillAvailable=false,false
local function Safe(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function Empty()
    return {revision=0,total=0,fair=0,higher=0,below3=0,below6=0,below10=0,unknown=0,diffs={}}
end
local version=Safe(GetBuildInfo)
local major,minor
if type(version)=="string" then major,minor=version:match("^(%d+)%.(%d+)") end
-- Forever reports 1.60.x but uses the modern event API.
local legacyCombat=major and tonumber(major)<12 and
    not (major=="1" and tonumber(minor)>=60) and not issecretvalue and not C_Secrets
function TC.PvPStatus()
    if partyKillAvailable then return "Level gaps count killing blows when the client reveals both players and their levels." end
    if not combatEventAvailable or type(CombatLogGetCurrentEventInfo)~="function" then return "Level-gap tracking unavailable on this client." end
    if C_CombatLog and Safe(C_CombatLog.IsCombatLogRestricted)==true then return "Level-gap tracking is restricted here." end
    return "Level gaps count killing blows with readable levels."
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
    if not TC.guildKey or Safe(UnitIsPlayer,unit)~=true then return end
    local guid=Safe(UnitGUID,unit)
    if type(guid)~="string" or not guid:match("^Player%-") then return end
    local level=Safe(UnitLevel,unit)
    level=TC.Integer(level,1,255)
    if level then
        local entry=observed[guid] or {}
        entry.level,entry.when=level,GetTime()
        observed[guid]=entry
    end
end

local function VictimLevel(guid,now)
    local enemy=observed[guid]
    if enemy and now-enemy.when<=30 then return enemy.level end
    if type(GetPlayerInfoByGUID)=="function" then
        local ok,_,_,_,_,_,_,_,level=pcall(GetPlayerInfoByGUID,guid)
        if ok and not (issecretvalue and issecretvalue(level)) then return TC.Integer(level,1,255) end
    end
end

function TC.RecordPvPKill(timestamp,event,sourceGUID,destGUID)
    if issecretvalue and (issecretvalue(event) or issecretvalue(sourceGUID) or issecretvalue(destGUID)) then return end
    if event~="PARTY_KILL" or not TC.guildKey or not TC.store or not TC.store.social or not TC.db.fun.pvp then return end
    if type(destGUID)~="string" or not destGUID:match("^Player%-") then return end
    local player=Safe(UnitGUID,"player"); local pet=Safe(UnitGUID,"pet")
    if not player or (sourceGUID~=player and (not pet or sourceGUID~=pet)) or destGUID==player then return end
    local now=GetTime()
    if duplicates[destGUID] and now-duplicates[destGUID]<2 then return end
    duplicates[destGUID]=now
    TC.ObservePvPUnit("target"); TC.ObservePvPUnit("mouseover")
    local enemy=VictimLevel(destGUID,now)
    local own=TC.Integer(Safe(UnitLevel,"player"),1,255)
    local diff=enemy and own and enemy-own or nil
    local p=TC.db.fun.pvp[TC.owner]; p.total=p.total+1
    local bucket="unknown"
    if diff then
        bucket=math.abs(diff)<=2 and "fair" or diff>=3 and "higher" or diff>=-5 and "below3" or diff>=-9 and "below6" or "below10"
        p.diffs[diff]=(p.diffs[diff] or 0)+1
    end
    p[bucket]=p[bucket]+1; p.revision=math.max(time(),p.revision+1)
    TC.BroadcastPvP(diff or false)
    if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end
    return true
end
local function BroadcastGap(p,diff,count)
    TC.QueueGuildPacket("pvp-gap:"..diff,table.concat({"PL",p.revision,diff,count},"\t"))
end

function TC.BroadcastPvP(changedGap)
    if not TC.guildKey or not TC.db.fun.pvp then return end
    local p=TC.db.fun.pvp[TC.owner]; if not p then return end
    if changedGap==nil then
        TC.BroadcastDeaths(p)
        if p.honorKills~=nil then TC.QueueGuildPacket("pvp-honor",table.concat({"PH",p.honorRevision or 0,p.honorKills},"\t")) end
    end
    TC.QueueGuildPacket("pvp-head",table.concat({"PK",p.revision,p.total,p.fair,p.higher,p.below3,p.below6,p.below10,p.unknown},"\t"))
    if changedGap==nil then
        for diff,count in pairs(p.diffs) do BroadcastGap(p,diff,count) end
    elseif changedGap then
        BroadcastGap(p,changedGap,p.diffs[changedGap])
    end
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
function TC.PvPRows(mode)
    local rows={}
    for owner,p in pairs(TC.store.social.pvp or {}) do
        -- The existing -3 to -5 bucket is ambiguous. Only the exact -5
        -- histogram entry belongs with the two lower-level buckets.
        local shame=p.below6+p.below10+math.min(p.below3,p.diffs[-5] or 0)
        rows[#rows+1]={owner=owner,stats=p,label=TC.DisplayName(owner),hero=p.higher,shame=shame}
    end
    -- Characters that share a given name read as one player while no surname is
    -- known, so name the stored key on the rows that still collide.
    local counts={}; for _,r in ipairs(rows) do counts[r.label]=(counts[r.label] or 0)+1 end
    for _,r in ipairs(rows) do if counts[r.label]>1 then r.label=r.label.." ("..(r.owner:match("%-(.+)$") or r.owner)..")" end end
    local function Score(row)
        if mode=="hero" or mode=="shame" then return row[mode] end
        return row.stats.honorKills or row.stats.total
    end
    table.sort(rows,function(a,b)
        local x,y=Score(a),Score(b)
        if x~=y then return x>y end; return a.owner<b.owner
    end)
    return rows
end
local frame=CreateFrame("Frame")
local events={"PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","NAME_PLATE_UNIT_ADDED","PLAYER_PVP_KILLS_CHANGED","HONOR_XP_UPDATE","PLAYER_ENTERING_WORLD"}
if legacyCombat then events[#events+1]="COMBAT_LOG_EVENT_UNFILTERED"
else events[#events+1]="PARTY_KILL" end
for _,event in ipairs(events) do
    local ok=pcall(frame.RegisterEvent,frame,event)
    if event=="COMBAT_LOG_EVENT_UNFILTERED" then combatEventAvailable=ok
    elseif event=="PARTY_KILL" then partyKillAvailable=ok end
end
frame:SetScript("OnEvent",function(_,event,unit,targetGUID)
    if not TC.db or not TC.db.fun then return end
    if event=="PARTY_KILL" then
        if partyKillAvailable then TC.RecordPvPKill(nil,event,unit,targetGUID) end
    elseif event=="COMBAT_LOG_EVENT_UNFILTERED" then
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

end)
