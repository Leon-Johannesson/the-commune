local _,TC=...
local active=false

local function Readable(value)
    if not (issecretvalue and issecretvalue(value)) then return value end
end

local function Safe(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok then return Readable(value) end
end

local function ZoneName(value)
    value=Readable(value)
    if type(value)~="string" then return "" end
    return TC.Clean(value,80)
end

local function DeathZone()
    if type(GetInstanceInfo)=="function" then
        local ok,name,kind,_,_,_,_,_,id=pcall(GetInstanceInfo)
        kind,id=Readable(kind),TC.Integer(Readable(id),1,2147483647)
        if ok and type(kind)=="string" and kind~="" and kind~="none" and id then
            name=ZoneName(name)
            return "instance:"..id,name~="" and name or ("Instance #"..id)
        end
    end
    if C_Map then
        local id=TC.Integer(Safe(C_Map.GetBestMapForUnit,"player"),1,2147483647)
        local zoneType=Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
        -- An outdoor subzone can have its own map. Record the parent zone.
        for _=1,8 do
            if not id then break end
            local info=Safe(C_Map.GetMapInfo,id)
            if type(info)~="table" or (issecrettable and issecrettable(info)) then break end
            if Readable(info.mapType)==zoneType then
                local name=ZoneName(info.name)
                return "map:"..id,name~="" and name or ("Zone #"..id)
            end
            local parent=TC.Integer(Readable(info.parentMapID),1,2147483647)
            if parent==id then break end
            id=parent
        end
    end
    local name=ZoneName(Safe(GetZoneText))
    if name=="" then name=ZoneName(Safe(GetRealZoneText)) end
    if name~="" then return "name:"..name,name end
    return "unknown","Unknown zone"
end
TC.CurrentDeathZone=DeathZone

function TC.ZoneDeathRows()
    local key,name=DeathZone()
    local rows,total={},0
    local profiles=TC.store and TC.store.social and TC.store.social.pvp or {}
    for owner,profile in pairs(profiles) do
        local count,pve,pvp=0,0,0
        for zone,entry in pairs(profile.deathZones or {}) do
            -- A client without map data records the zone's name instead. Keep
            -- those observations visible without merging distinct map/instance IDs.
            if zone==key or (key~="unknown" and entry.name==name and
                (zone:sub(1,5)=="name:" or key:sub(1,5)=="name:")) then
                count=count+(TC.Integer(entry.count,1,999999999) or 0)
                pve=pve+(entry.pve or 0); pvp=pvp+(entry.pvp or 0)
            end
        end
        if count>0 then
            rows[#rows+1]={owner=owner,name=TC.DisplayName(owner),count=count,pve=pve,pvp=pvp,unknown=math.max(0,count-pve-pvp)}
            total=total+count
        end
    end
    table.sort(rows,function(a,b)
        if a.count~=b.count then return a.count>b.count end
        if a.name~=b.name then return a.name<b.name end
        return a.owner<b.owner
    end)
    return rows,total,key,name
end

local function SaveZone(profile,key,entry)
    profile.deathZones=profile.deathZones or {}
    local previous=profile.deathZones[key]
    local newer=not previous or (entry.revision>=previous.revision and entry.count>=previous.count and
        (entry.revision>previous.revision or entry.count>previous.count))
    local typed=entry.typeRevision and (not previous or entry.typeRevision>(previous.typeRevision or 0)) and
        entry.typeCount<=(newer and entry.count or previous.count) and
        entry.pve>=(previous and previous.pve or 0) and entry.pvp>=(previous and previous.pvp or 0)
    if not newer and not typed then return end
    local merged={name=newer and entry.name or previous.name,count=newer and entry.count or previous.count,
        revision=newer and entry.revision or previous.revision}
    local types=typed and entry or previous
    if types and types.typeRevision then
        merged.pve,merged.pvp=types.pve,types.pvp
        merged.typeRevision,merged.typeCount=types.typeRevision,types.typeCount
    end
    profile.deathZones[key]=merged
    return true
end

function TC.MergeDeathZones(profile,zones)
    for key,entry in pairs(zones or {}) do SaveZone(profile,key,entry) end
end

local function BroadcastZone(key,entry)
    TC.QueueGuildPacket("death-zone:"..key,table.concat({"PZ",key,entry.revision,entry.count,entry.name},"\t"))
    local typed=TC.DeathZoneTypePacket(key,entry)
    if typed then TC.QueueGuildPacket("death-zone-type:"..key,typed) end
end

function TC.DeathZoneTypePacket(key,entry)
    if entry.typeRevision then
        return table.concat({"PY",key,entry.typeRevision,entry.typeCount,entry.pve,entry.pvp,entry.name},"\t")
    end
end

function TC.BroadcastDeathZones()
    if not TC.guildKey or not TC.HasGuildPeer() then return end
    local profiles=TC.db.fun and TC.db.fun.pvp
    local p=profiles and profiles[TC.owner]
    for key,entry in pairs(p and p.deathZones or {}) do BroadcastZone(key,entry) end
end

local function RecordDeathZone(profile)
    -- Snapshot immediately, before releasing can move the player to a graveyard.
    local key,name=DeathZone()
    profile.deathZones=profile.deathZones or {}
    local old=profile.deathZones[key]
    local entry={name=name,count=(old and old.count or 0)+1,revision=math.max(time(),(old and old.revision or 0)+1)}
    entry.pve,entry.pvp=old and old.pve or 0,old and old.pvp or 0
    entry.typeRevision,entry.typeCount=entry.revision,entry.count
    profile.deathZones[key]=entry
    if TC.guildKey then BroadcastZone(key,entry) end
    if TC.RefreshZoneDeaths then TC.RefreshZoneDeaths() end
    if TC.ClassifyZoneDeath then TC.ClassifyZoneDeath(profile,key) end
end

function TC.RecordZoneDeathCause(profile,key,cause,store)
    local entry=profile.deathZones and profile.deathZones[key]
    if not entry or (cause~="pve" and cause~="pvp") or (entry.pve or 0)+(entry.pvp or 0)>=entry.count then return end
    entry[cause]=(entry[cause] or 0)+1
    entry.revision=math.max(time(),entry.revision+1)
    entry.typeRevision,entry.typeCount=entry.revision,entry.count
    if TC.guildKey and TC.store==store then BroadcastZone(key,entry) end
    if TC.RefreshZoneDeaths then TC.RefreshZoneDeaths() end
end

local function DeathProfile(sender)
    local all=TC.store.social.pvp
    all[sender]=all[sender] or {revision=0,total=0,fair=0,higher=0,below3=0,below6=0,below10=0,unknown=0,diffs={}}
    return all[sender]
end

local function ReceiveZone(message,sender)
    if #message>254 then return end
    local key,revision,count,name=message:match("^PZ\t([^\t]+)\t(%d+)\t(%d+)\t([^\t]+)$")
    local pve,pvp
    local typed=message:sub(1,3)=="PY\t"
    if typed then
        key,revision,count,pve,pvp,name=message:match("^PY\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([^\t]+)$")
        pve,pvp=TC.Integer(pve,0,999999999),TC.Integer(pvp,0,999999999)
    end
    revision=TC.Integer(revision,1,time()+86400)
    count=TC.Integer(count,1,999999999)
    name=ZoneName(name)
    if not revision or not count or name=="" or not key or #key>85 then return end
    if typed and (not pve or not pvp or pve+pvp>count) then return end
    if key=="unknown" then
        name="Unknown zone"
    elseif key~="name:"..name then
        local kind,id=key:match("^(%l+):([1-9]%d*)$")
        if (kind~="map" and kind~="instance") or not TC.Integer(id,1,2147483647) then return end
    end
    local entry={name=name,count=count,revision=revision}
    if typed then entry.pve,entry.pvp,entry.typeRevision,entry.typeCount=pve,pvp,revision,count end
    SaveZone(DeathProfile(sender),key,entry)
    if TC.RefreshZoneDeaths then TC.RefreshZoneDeaths() end
end

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
    local kind=message:sub(1,3)
    if kind=="PZ\t" or kind=="PY\t" then ReceiveZone(message,sender); return true end
    if kind~="PT\t" then return false end
    local revision,count,source=message:match("^PT\t(%d+)\t(%d+)\t([01])$")
    revision=TC.Integer(revision,0,time()+86400); count=TC.Integer(count,0,999999999)
    if not revision or not count then return true end
    local p=DeathProfile(sender)
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
        RecordDeathZone(p)
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
