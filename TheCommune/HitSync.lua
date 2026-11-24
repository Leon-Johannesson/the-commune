local _,TC=...
local stages={}
local hitStore
local stats={sent=0,received=0,applied=0,rejected=0}
function TC.HitKey(r)
    return table.concat({r.target or "",r.faction or "",r.reason or "",r.officer or ""},"\t")
end
local function Fields(message)
    local result={}; for value in (message.."\t"):gmatch("(.-)\t") do result[#result+1]=value end; return result
end
function TC.InitHitlist()
    if hitStore~=TC.store then stages={}; hitStore=TC.store end
    local rebuilt={}
    for owner,slots in pairs(TC.store.social.hits) do
        owner=TC.NormalizeName(owner)
        if owner then
            rebuilt[owner]=rebuilt[owner] or {}
            for slot,r in pairs(slots) do
                if not r.deleted then r.target=TC.PlayerKey(r.name or r.target) end
                local old=rebuilt[owner][slot]
                if TC.SnapshotNewer(old,r,r.syncSource~="owner",old and TC.HitKey(old),TC.HitKey(r)) then rebuilt[owner][slot]=r end
            end
        end
    end
    TC.store.social.hits=rebuilt
end
function TC.BroadcastHitCache()
    if not TC.guildKey then return end
    for owner,slots in pairs(TC.store.social.hits) do for slot,r in pairs(slots) do
        local body=table.concat({r.deleted and 1 or 0,TC.Clean(r.name or r.target or "",90),r.faction or "",TC.Clean(r.reason,80),r.officer or owner},"\t")
        local chunks={}; local first=1
        while first<=#body do
            local last=math.min(first+89,#body)
            while last>first and (body:byte(last+1) or 0)>=128 and (body:byte(last+1) or 0)<192 do last=last-1 end
            chunks[#chunks+1]=body:sub(first,last); first=last+1
        end
        for part,chunk in ipairs(chunks) do
            TC.QueueGuildPacket("hit-cache:"..owner..":"..slot..":"..part,table.concat({"HT",owner,slot,r.revision,part,#chunks,chunk},"\t"))
            stats.sent=stats.sent+1
        end
    end end
end
function TC.ReceiveHitCache(message,sender)
    if message:sub(1,3)~="HT\t" then return false end
    stats.received=stats.received+1; stats.peer=sender
    local owner,slot,revision,part,total,chunk=message:match("^HT\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
    if not owner or #owner>100 or TC.NormalizeName(owner)~=owner then stats.rejected=stats.rejected+1; return true end
    slot=TC.Integer(slot,1,20); revision=TC.Integer(revision,1,time()+86400); part=TC.Integer(part,1,4); total=TC.Integer(total,1,4)
    if not slot or not revision or not part or not total or part>total or #chunk>90 then stats.rejected=stats.rejected+1; return true end
    local stageCount=0
    for key,stage in pairs(stages) do
        if stage.store~=TC.store or GetTime()-stage.when>180 then stages[key]=nil else stageCount=stageCount+1 end
    end
    local key=sender..":"..owner..":"..slot..":"..revision
    if not stages[key] and stageCount>=200 then return true end
    local stage=stages[key] or {store=TC.store,total=total,parts={}}; stages[key]=stage
    if stage.total~=total then stages[key]=nil; return true end
    stage.when=GetTime(); stage.parts[part]=chunk
    for index=1,total do if not stage.parts[index] then return true end end
    stages[key]=nil
    local f=Fields(table.concat(stage.parts))
    if #f~=5 or (f[1]~="0" and f[1]~="1") or #f[2]>90 or #f[4]>80 or #f[5]>100 then stats.rejected=stats.rejected+1; return true end
    local deleted=f[1]=="1"; local target=TC.PlayerKey(f[2]); local actor=TC.NormalizeName(f[5])
    if not actor or (actor~=owner and TC.IsProjectOfficer(actor)~=true) or (not deleted and (not target or actor~=owner or (f[3]~="Alliance" and f[3]~="Horde"))) then stats.rejected=stats.rejected+1; return true end
    if owner==TC.owner then
        TC.ObserveOwnRevision(revision)
        if not deleted or actor==owner then return true end
    end
    local slots=TC.store.social.hits[owner] or {}; TC.store.social.hits[owner]=slots
    local old=slots[slot]
    local incoming={revision=revision,deleted=deleted,target=target,name=TC.Clean(f[2],90),faction=f[3],reason=TC.Clean(f[4],80),officer=actor~=owner and actor or nil,fullNameKnown=true}
    local relayed=sender~=actor
    if TC.SnapshotNewer(old,incoming,relayed,old and TC.HitKey(old),TC.HitKey(incoming)) then
        slots[slot]=TC.StampSnapshot(incoming,relayed)
        stats.applied=stats.applied+1
    elseif old and not old.fullNameKnown and old.revision==revision and TC.HitKey(old)==TC.HitKey(incoming) then
        old.name,old.fullNameKnown=incoming.name,true
    end
    if TC.RefreshHitlist then TC.RefreshHitlist() end
    return true
end
function TC.DebugHits()
    local counts={}; for owner,slots in pairs(TC.store.social.hits) do
        local count=0; for _,r in pairs(slots) do if not r.deleted then count=count+1 end end
        counts[#counts+1]=TC.DisplayName(owner)..": "..count
    end
    TC.Print("Hitlist active entries: "..(#counts>0 and table.concat(counts,", ") or "none"))
    TC.Print("Hitlist cache packets queued: "..stats.sent.." | received: "..stats.received.." | applied: "..stats.applied.." | rejected: "..stats.rejected.." | peer: "..(stats.peer or "none"))
end
