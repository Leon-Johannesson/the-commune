local _,TC=...
-- Cache packets always use GUILD and the existing paced queue. They carry an
-- explicit original owner; they never pass through the live sender dispatcher.
local incoming,outgoing,lastQuery={}, {}, -100
local serial=0
local changedQuery
local sharedSnapshot
local MAX_RECORDS,MAX_PARTS,FRAGMENT=4096,512,160
local kinds={q=true,l=true,c=true,g=true,p=true,h=true,d=true,z=true,a=true,b=true,w=true,s=true,v=true}
local function Owner(owner)
    return type(owner)=="string" and #owner<=100 and not owner:find("[%c]") and TC.NormalizeName(owner)==owner
end
local function Member(owner)
    return Owner(owner) and (owner==TC.owner or TC.GuildRoster()[owner]~=nil)
end
local function Hash(text)
    local a,b=1,7
    for i=1,#text do local n=text:byte(i); a=(a*31+n)%2147483647; b=(b*17+n)%2147483647 end
    return a..":"..b
end
local function Pack(packets)
    local result={}
    for _,packet in ipairs(packets) do
        if type(packet)~="string" or #packet>254 then return end
        result[#result+1]=#packet..":"..packet
    end
    local blob=table.concat(result)
    if #blob==0 or #blob>MAX_PARTS*FRAGMENT then return end
    return blob
end
local function Unpack(blob)
    local result,pos={},1
    while pos<=#blob do
        local first,last,n=blob:find("^(%d+):",pos)
        n=tonumber(n)
        if not first or not n or n<1 or n>254 or last+n>#blob then return end
        result[#result+1]=blob:sub(last+1,last+n); pos=last+n+1
        if #result>1024 then return end
    end
    return result
end
local function Key(owner,kind,id) return owner.."\t"..kind.."\t"..id end
local function Fragments(blob)
    local chunks,first={},1
    while first<=#blob do
        local last=math.min(first+FRAGMENT-1,#blob)
        while last>first and (blob:byte(last+1) or 0)>=128 and (blob:byte(last+1) or 0)<192 do last=last-1 end
        chunks[#chunks+1]=blob:sub(first,last); first=last+1
    end
    if #chunks>MAX_PARTS then return end
    return chunks
end
local function Record(owner,kind,id,revision,packets)
    revision=TC.Integer(revision,0,time()+86400)
    if not revision then return end
    local blob=Pack(packets); if not blob then return end
    local fragments=Fragments(blob); if not fragments then return end
    return {owner=owner,kind=kind,id=tostring(id),revision=revision,fragments=fragments,hash=Hash(blob)}
end
local function SortedKeys(t)
    local keys={}; for key in pairs(t or {}) do keys[#keys+1]=key end
    table.sort(keys); return keys
end
local function Packet(...) return table.concat({...},"\t") end

-- Serialize persisted snapshots, including those learned before this feature
-- was installed. Independent revisions stay independent (honor/deaths/zones).
local function RecordsFor(owner,emit)
    local store=TC.store
    for _,slot in ipairs(SortedKeys(store.owners[owner])) do
        local r=store.owners[owner][slot]
        emit(Record(owner,"q",slot,r.revision,{TC.Encode(slot,r)}))
    end
    local crafts=store.crafts and store.crafts[owner]
    if crafts then
        local lines=SortedKeys(crafts.roster or crafts.professions)
        if (crafts.revision or 0)>0 then emit(Record(owner,"l",0,crafts.revision,{Packet("CL",crafts.revision,table.concat(lines,","))})) end
        for _,line in ipairs(SortedKeys(crafts.professions)) do
            local p=crafts.professions[line]
            emit(Record(owner,"c",line,p.revision,TC.ProfessionPackets(line,p)))
        end
    end
    local social=store.social or {}
    local gear=social.gear and social.gear[owner]
    if gear then
        local chunks,current={},""
        for _,slot in ipairs(TC.GearSlots) do
            if gear.items[slot] then
                local token=slot..":"..gear.items[slot]
                if #current+#token+1>160 then chunks[#chunks+1]=current; current="" end
                current=current=="" and token or current..","..token
            end
        end
        chunks[#chunks+1]=current
        local packets={}
        for i,chunk in ipairs(chunks) do packets[i]=Packet("GG",gear.revision,i,#chunks,gear.ilvl,chunk) end
        emit(Record(owner,"g",0,gear.revision,packets))
    end
    local p=social.pvp and social.pvp[owner]
    if p then
        local packets={Packet("PK",p.revision,p.total,p.fair,p.higher,p.below3,p.below6,p.below10,p.unknown)}
        for _,diff in ipairs(SortedKeys(p.diffs)) do
            if not p.gapRevisions or (p.gapRevisions[diff] or 0)<=p.revision then packets[#packets+1]=Packet("PL",p.revision,diff,p.diffs[diff]) end
        end
        emit(Record(owner,"p",0,p.revision,packets))
        if p.honorKills~=nil then emit(Record(owner,"h",0,p.honorRevision or 0,{Packet("PH",p.honorRevision or 0,p.honorKills)})) end
        if p.deaths~=nil then emit(Record(owner,"d",0,p.deathRevision or 0,{Packet("PT",p.deathRevision or 0,p.deaths,p.deathsLifetime and 1 or 0)})) end
        for _,zone in ipairs(SortedKeys(p.deathZones)) do
            local entry=p.deathZones[zone]
            emit(Record(owner,"z",Hash(zone),entry.revision,{Packet("PZ",zone,entry.revision,entry.count,entry.name)}))
            local typed=TC.DeathZoneTypePacket and TC.DeathZoneTypePacket(zone,entry)
            if typed then emit(Record(owner,"v",Hash(zone),entry.typeRevision,{typed})) end
        end
    end
    local account=social.characters and social.characters[owner]
    local a=account and social.accounts and social.accounts[account]
    if a then
        -- Use the same backwards-compatible daily-score representation as FA.
        local answered=math.min(a.answered-(a.fifthAnswered and 1 or 0),4)
        local correct=a.correct-(a.fifthCorrect and 1 or 0)
        local packets={Packet("FA",account,a.revision,a.name,a.qa,a.qc,a.qd,a.wp,a.ww,a.wg,a.day,answered,correct,a.result,a.earned,a.spent,a.title)}
        emit(Record(owner,"a",account,a.revision,packets))
        for _,field in ipairs({"transfers","grants","deductions"}) do
            local kind=field=="transfers" and "FB" or field=="grants" and "FG" or "FD"
            for _,to in ipairs(SortedKeys(a[field])) do
                local rev=a.counterVersions and a.counterVersions[kind..":"..to] or a.revision
                emit(Record(owner,"b",Hash(Packet(kind,account,to)),rev,{Packet(kind,account,to,rev,a[field][to])}))
            end
        end
        local word=a.wordBoard
        if word and word.day==TC.DayID() then
            emit(Record(owner,"w",account,a.revision,{Packet("FW",account,word.day,word.result,word.colors)}))
        end
        local history=social.dailyScores and social.dailyScores[account]
        for _,day in ipairs(SortedKeys(history)) do
            local score=history[day]
            if TC.DailyScorePacket then
                emit(Record(owner,"s",account..":"..day,score.revision,{TC.DailyScorePacket(account,day,score)}))
            end
        end
    end
end
local function Build(done)
    local store,guild=TC.store,TC.guildKey
    local owners={}
    for owner in pairs(store.owners or {}) do owners[owner]=true end
    for owner in pairs(store.crafts or {}) do owners[owner]=true end
    for _,field in ipairs({"gear","pvp","characters"}) do for owner in pairs(store.social and store.social[field] or {}) do owners[owner]=true end end
    local list,index={},{}
    local names=SortedKeys(owners); local position=0
    local function Step()
        if TC.store~=store or TC.guildKey~=guild then return end
        position=position+1; local owner=names[position]
        if not owner then done(list,index); return end
        -- The guild-scoped cache can include offline characters absent from the visible roster.
        if Owner(owner) then
            RecordsFor(owner,function(r)
                if r and #list<MAX_RECORDS then
                    list[#list+1]=r; index[Key(owner,r.kind,r.id)]=r
                end
            end)
        end
        -- Work on one character per tick instead of blocking a frame for the guild.
        C_Timer.After(0.02,Step)
    end
    Step()
end
-- Several simultaneous logins can share the same immutable outgoing snapshot.
-- Keep it briefly; the requester still validates every original revision.
local function BuildOutgoing(done)
    local current=sharedSnapshot
    if current and current.store==TC.store and (not current.records or GetTime()-current.when<5) then
        if current.records then done(current.records)
        else current.waiters[#current.waiters+1]=done end
        return
    end
    current={store=TC.store,when=GetTime(),waiters={done}}; sharedSnapshot=current
    Build(function(records)
        if sharedSnapshot~=current then return end
        current.records=records; current.when=GetTime()
        local waiting=current.waiters; current.waiters=nil
        for _,callback in ipairs(waiting) do callback(records) end
    end)
end
local function Send(key,message,background)
    if #message<=254 then TC.QueueGuildPacket((background and "relay:" or "cache:")..key,message) end
end
local function Active(session) return session and session.store==TC.store and GetTime()-session.when<900 end
function TC.ResetCacheSync() incoming,outgoing={},{}; sharedSnapshot=nil; changedQuery=nil; lastQuery=-100 end
function TC.NotifyRequestCache()
    sharedSnapshot=nil
    if TC.guildKey then Send("changed", "KU\t1") end
end
function TC.QueryCache(attempt)
    if not TC.store or not TC.guildKey or GetTime()-lastQuery<30 then return end
    lastQuery=GetTime(); serial=serial+1
    local token=string.format("%d-%d-%s-%d",time(),math.random(1,999999999),Hash(TC.owner):match("^(%d+)"),serial)
    local session={token=token,store=TC.store,when=GetTime(),known={},waiting={},offers={},count=0,attempt=tonumber(attempt) or 0}
    incoming={session=session}
    Build(function(_,index)
        if incoming.session~=session then return end
        session.known=index
        Send("query",Packet("KQ",token))
    end)
end
local function Need(session,r)
    if r.owner==TC.owner then
        if TC.ObserveOwnRevision then TC.ObserveOwnRevision(r.revision) end
        return false
    end
    local old=session.known[Key(r.owner,r.kind,r.id)]
    return not old or r.revision>old.revision or (r.revision==old.revision and r.hash~=old.hash)
end
local function Request(session,r)
    r.progress=GetTime()
    Send("get:"..session.token..":"..r.peer..":"..r.index,Packet("KR",session.token,r.peer,r.index,r.hash))
end
local function Watch(session,r)
    C_Timer.After(60,function()
        if incoming.session~=session or not Active(session) or r.done or session.offers[Key(r.owner,r.kind,r.id)]~=r then return end
        if GetTime()-r.progress>=60 then
            r.retries=(r.retries or 0)+1
            if r.retries<=2 then Request(session,r)
            else
                -- Restart discovery once; records already applied compare equal,
                -- and another online cache can take over from a disconnected peer.
                r.done=true; r.parts=nil
                if session.attempt<1 then TC.QueryCache(session.attempt+1) end
                return
            end
        end
        Watch(session,r)
    end)
end
local function ScheduleRequest(session,key)
    if session.waiting[key] then return end
    session.waiting[key]=true
    C_Timer.After(2,function()
        if incoming.session~=session or not Active(session) then return end
        session.waiting[key]=nil
        local r=session.offers[key]
        if not r or r.requested or not Need(session,r) then return end
        r.requested=true; r.parts={}; r.received=0; r.started=GetTime()
        session.transfers=session.transfers or {}; session.transfers[r.peer..":"..r.index]=r
        Request(session,r); Watch(session,r)
    end)
end
local function Apply(r,packets)
    if r.owner==TC.owner or #packets==0 then return false end
    -- Strict per-record allowlist: a cache response cannot become a query,
    -- privileged project edit, hit deletion, or a packet for a different owner.
    local request,head,level
    local parts,gaps={},{}
    for _,packet in ipairs(packets) do
        local kind=packet:match("^([^\t]+)")
        local id=packet:match("^[^\t]+\t([^\t]+)")
        local allowed=(r.kind=="q" and (kind=="R" or kind=="D") and id==r.id) or
            (r.kind=="l" and kind=="CL") or (r.kind=="c" and (kind=="CB" or kind=="CC") and id==r.id) or
            (r.kind=="g" and kind=="GG") or (r.kind=="p" and (kind=="PK" or kind=="PL")) or
            (r.kind=="h" and kind=="PH") or (r.kind=="d" and kind=="PT") or (r.kind=="z" and kind=="PZ" and Hash(id or "")==r.id) or
            (r.kind=="v" and kind=="PY" and Hash(id or "")==r.id) or
            (r.kind=="a" and kind=="FA" and id==r.id) or (r.kind=="w" and kind=="FW" and id==r.id) or
            (r.kind=="s" and kind=="FQ" and r.id==(id or "")..":"..(packet:match("^FQ\t[^\t]+\t(%d+)\t") or "")) or
            (r.kind=="b" and (kind=="FB" or kind=="FG" or kind=="FD") and
                Hash(packet:match("^([^\t]+\t[^\t]+\t[^\t]+)" ) or "")==r.id)
        if not allowed then return false end
        local fields={}; for value in (packet.."\t"):gmatch("(.-)\t") do fields[#fields+1]=value end
        local index=({q=3,l=2,c=3,g=2,p=2,h=2,d=2,z=3,v=3,a=3,b=4,s=4})[r.kind]
        if index and TC.Integer(fields[index],0,time()+86400)~=r.revision then return false end
        if r.kind~="c" and r.kind~="g" and r.kind~="p" and #packets~=1 then return false end
        if r.kind=="c" then
            if kind=="CB" then
                if head then return false end
                head=TC.Integer(fields[4],1,256); if not head then return false end
            else
                local part=TC.Integer(fields[4],1,256)
                if not part or parts[part] then return false end
                parts[part]=true
            end
        elseif r.kind=="g" then
            local part,total=TC.Integer(fields[3],1,3),TC.Integer(fields[4],1,3)
            local ilvl=TC.Integer(fields[5],0,9999)
            if not part or not total or part>total or not ilvl or parts[part] or (head and (head~=total or level~=ilvl)) then return false end
            head,level,parts[part]=total,ilvl,true
        elseif r.kind=="p" then
            if kind=="PK" then
                if head then return false end
                head=TC.Integer(fields[3],0,999999999); if not head then return false end
            else
                local gap,count=TC.Integer(fields[3],-254,254),TC.Integer(fields[4],0,999999999)
                if not gap or not count or gaps[gap] then return false end
                gaps[gap]=count
            end
        end
        if r.kind=="v" then
            local revision=TC.Integer(packet:match("^PY\t[^\t]+\t(%d+)\t"),1,time()+86400)
            if revision~=r.revision or #packets~=1 then return false end
        end
        if r.kind=="s" then
            if not TC.DecodeDailyScore then return false end
            local _,score=TC.DecodeDailyScore(packet)
            if not score or score.revision~=r.revision or #packets~=1 then return false end
        end
        if r.kind=="q" then
            local slot,value=TC.Decode(packet)
            if not slot or value.revision~=r.revision or #packets~=1 then return false end
            request={slot,value}
        end
    end
    if r.kind=="c" or r.kind=="g" then
        if not head or #packets~=head+(r.kind=="c" and 1 or 0) then return false end
        for part=1,head do if not parts[part] then return false end end
    elseif r.kind=="p" then
        if not head then return false end
        local total=0; for _,count in pairs(gaps) do total=total+count end
        if total>head then return false end
    end
    if request then TC.ApplyRequest(request[1],request[2],r.owner,true)
    else for _,packet in ipairs(packets) do TC.ReceiveGuildData(packet,r.owner,true) end end
    return true
end

function TC.ReceiveCacheSync(message,sender)
    local kind=type(message)=="string" and message:match("^([^\t]+)")
    if kind~="KQ" and kind~="KI" and kind~="KR" and kind~="KD" and kind~="KU" then return false end
    if #message>254 or not Member(sender) then return true end
    if kind=="KU" then
        if message~="KU\t1" or changedQuery then return true end
        local store=TC.store
        local token={}; changedQuery=token
        local function Check()
            if changedQuery~=token then return end
            if TC.store~=store then changedQuery=nil; return end
            local wait=31-(GetTime()-lastQuery)
            if wait>0 then C_Timer.After(wait+math.random()*2,Check); return end
            changedQuery=nil
            TC.QueryCache()
        end
        C_Timer.After(math.max(1,31-(GetTime()-lastQuery))+math.random()*2,Check)
        return true
    end
    if kind=="KQ" then
        local token=message:match("^KQ\t([%d%-]+)$")
        if not token or #token>48 then return true end
        local old=outgoing[sender]
        if Active(old) and GetTime()-old.when<30 then return true end
        -- One bounded snapshot per requester. Direct packets keep queue priority.
        if old then
            TC.CancelGuildPackets("relay:offer:"..old.token..":")
            TC.CancelGuildPackets("relay:data:"..old.token..":")
        end
        for peer,session in pairs(outgoing) do if not Active(session) then outgoing[peer]=nil end end
        local session={token=token,store=TC.store,when=GetTime()}; outgoing[sender]=session
        C_Timer.After(1+math.random()*2,function()
            if outgoing[sender]~=session or not Active(session) then return end
            BuildOutgoing(function(records)
                if outgoing[sender]~=session or not Active(session) then return end
                session.records=records; session.index={}
                for index,r in ipairs(records) do
                    session.index[Key(r.owner,r.kind,r.id)]={record=r,index=index}
                    -- Owners see revision metadata too, but Need never requests
                    -- their payloads. This gives restored saves a safe clock floor.
                    Send("offer:"..token..":"..index,Packet("KI",token,index,r.owner,r.kind,r.id,r.revision,r.hash,#r.fragments),true)
                end
            end)
        end)
    elseif kind=="KI" then
        local token,index,owner,recordKind,id,rev,hash,total=message:match("^KI\t([%d%-]+)\t(%d+)\t([^\t]+)\t(%l)\t([^\t]+)\t(%d+)\t([%d:]+)\t(%d+)$")
        index=TC.Integer(index,1,MAX_RECORDS); rev=TC.Integer(rev,0,time()+86400); total=TC.Integer(total,1,MAX_PARTS)
        if not index or not rev or not total or not kinds[recordKind] or not Owner(owner) or #id>85 or not hash or #hash>24 then return true end
        local key=Key(owner,recordKind,id)
        -- Everybody hears offers on GUILD. Cancel our queued duplicate when
        -- another cache has already advertised the same (or newer) record.
        for _,out in pairs(outgoing) do
            local own=Active(out) and out.token==token and out.index and out.index[key]
            if own and (rev>own.record.revision or (rev==own.record.revision and hash==own.record.hash)) then
                TC.CancelGuildPacket("relay:offer:"..token..":"..own.index)
            end
        end
        local session=incoming.session
        if not Active(session) or token~=session.token then return true end
        session.when=GetTime()
        local r={owner=owner,kind=recordKind,id=id,revision=rev,hash=hash,total=total,peer=sender,index=index}
        if not Need(session,r) then return true end
        local previous=session.offers[key]
        if previous then
            if previous.revision>rev or (previous.revision==rev and previous.requested and GetTime()-previous.started<180) then return true end
            if previous.revision==rev and previous.hash==hash and previous.peer<sender then return true end
        elseif session.count>=MAX_RECORDS then return true
        else session.count=session.count+1 end
        session.offers[key]=r
        ScheduleRequest(session,key)
    elseif kind=="KR" then
        local token,peer,index,hash=message:match("^KR\t([%d%-]+)\t([^\t]+)\t(%d+)\t([%d:]+)$")
        if peer~=TC.owner then return true end
        local session=outgoing[sender]; index=TC.Integer(index,1,MAX_RECORDS)
        if not Active(session) or session.token~=token or not index or not session.records then return true end
        local r=session.records[index]
        if not r or hash~=r.hash then return true end
        session.when=GetTime()
        session.sent=session.sent or {}; if session.sent[index] and GetTime()-session.sent[index]<45 then return true end
        session.sent[index]=GetTime()
        local total=#r.fragments
        for part=1,total do
            Send("data:"..token..":"..index..":"..part,Packet("KD",token,index,part,total,r.fragments[part]),true)
        end
    else
        local token,index,part,total,payload=message:match("^KD\t([%d%-]+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
        local session=incoming.session
        if not Active(session) or session.token~=token then return true end
        index=TC.Integer(index,1,MAX_RECORDS); part=TC.Integer(part,1,MAX_PARTS); total=TC.Integer(total,1,MAX_PARTS)
        if not index or not part or not total or part>total or #payload>FRAGMENT then return true end
        -- Offers are indexed by logical record; find only a requested provider.
        local r=session.transfers and session.transfers[sender..":"..index]
        if not r or r.done or r.total~=total then return true end
        session.when=GetTime()
        if not r.parts[part] then r.parts[part]=payload; r.received=r.received+1; r.progress=GetTime() end
        if r.received~=total then return true end
        local blob=table.concat(r.parts)
        if Hash(blob)~=r.hash then r.parts={}; r.received=0; return true end
        local packets=Unpack(blob)
        if not packets or not Apply(r,packets) then return true end
        r.applied=true; r.done=true; r.parts=nil
        -- The session began before some live updates. Never lower its revision.
        local key=Key(r.owner,r.kind,r.id); local old=session.known[key]
        if not old or r.revision>=old.revision then session.known[key]=r end
    end
    return true
end

function TC.DebugCacheSync()
    local session=incoming.session
    if not session then TC.Print("Offline cache: no discovery this session"); return end
    local requested,complete=0,0
    for _,r in pairs(session.offers) do
        if r.requested then requested=requested+1 end
        if r.applied then complete=complete+1 end
    end
    TC.Print("Offline cache: "..session.count.." differing records offered | "..requested.." requested | "..complete.." applied")
end

function TC.CachePacketSent(key)
    local token=key:match("^relay:[^:]+:([%d%-]+):")
    if not token then return end
    for _,session in pairs(outgoing) do if session.token==token then session.when=GetTime(); break end end
end
