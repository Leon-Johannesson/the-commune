local _, TC = ...
local function Marks()
    if not TC.store then return end
    TC.store.requestMarks=TC.store.requestMarks or {}
    return TC.store.requestMarks
end
local function Current(mark,owner,slot)
    if not mark or mark.deleted then return false end
    if owner and (mark.owner~=owner or mark.slot~=slot) then return false end
    local slots=TC.store.owners[mark.owner]
    local request=slots and slots[mark.slot]
    return request and TC.IsActive(request) and request.revision==mark.requestRevision and request.item==mark.item or false
end
function TC.RequestMarkPacket(slot,mark)
    if mark.deleted then return table.concat({"RM",slot,mark.revision,"D"},"\t") end
    return table.concat({"RM",slot,mark.revision,"R",mark.owner,mark.slot,mark.requestRevision,mark.item},"\t")
end
function TC.RequestMarkNames(owner,slot)
    local names={}
    for reporter,slots in pairs(Marks() or {}) do
        for _,mark in pairs(slots) do
            if Current(mark,owner,slot) then names[#names+1]=TC.DisplayName(reporter); break end
        end
    end
    table.sort(names)
    return names
end
function TC.OwnRequestMark(owner,slot)
    local all=Marks()
    for index,mark in pairs(all and all[TC.owner] or {}) do
        if Current(mark,owner,slot) then return index,mark end
    end
end
function TC.ToggleRequestMark(owner,slot)
    if not TC.guildKey then return nil,"Join a guild to share completion marks." end
    local r=TC.store.owners[owner] and TC.store.owners[owner][slot]
    if not r or not TC.IsActive(r) then return nil,"This request is no longer open." end
    local all=Marks(); all[TC.owner]=all[TC.owner] or {}
    local slots=all[TC.owner]
    local index,old=TC.OwnRequestMark(owner,slot)
    local undo=index~=nil
    if not index then
        for i=1,TC.limit do if not Current(slots[i]) then index=i; break end end
        old=index and slots[index]
    end
    if not index then return nil,"You have 20 active completion marks. Undo one before adding another." end
    local mark={revision=TC.NextRevision(old and old.revision),deleted=undo,
        owner=owner,slot=slot,requestRevision=r.revision,item=r.item}
    slots[index]=TC.StampSnapshot(mark,false)
    TC.QueueGuildPacket("request-mark:"..index,TC.RequestMarkPacket(index,mark))
    if TC.NotifyRequestCache then TC.NotifyRequestCache() end
    if TC.QueueRefresh then TC.QueueRefresh() end
    return true,undo and "Your completion mark was removed." or "Marked done. The requester must confirm completion."
end
function TC.BroadcastRequestMarks()
    local all=Marks()
    for slot,mark in pairs(all and all[TC.owner] or {}) do
        TC.QueueGuildPacket("request-mark:"..slot,TC.RequestMarkPacket(slot,mark))
    end
end
function TC.ReceiveRequestMark(message,sender,relayed)
    if type(message)~="string" or message:sub(1,3)~="RM\t" then return false end
    if #message>254 or not TC.guildKey or sender==TC.owner then return true end
    if type(sender)~="string" or TC.NormalizeName(sender)~=sender then return true end
    -- The live sender owns their mark, never the underlying request. Cache
    -- transfers use the same validated original-owner trust as other snapshots.
    if not relayed and not TC.GuildRoster()[sender] then return true end
    local f={}; for part in (message.."\t"):gmatch("(.-)\t") do f[#f+1]=part end
    local index=TC.Integer(f[2],1,TC.limit)
    local revision=TC.Integer(f[3],1,time()+86400)
    if not index or not revision then return true end
    local mark={revision=revision}
    if #f==4 and f[4]=="D" then mark.deleted=true
    elseif #f==8 and f[4]=="R" then
        local owner=f[5]
        mark.owner=type(owner)=="string" and #owner<=100 and not owner:find("[%c|]") and TC.NormalizeName(owner)==owner and owner or nil
        mark.slot=TC.Integer(f[6],1,TC.limit)
        mark.requestRevision=TC.Integer(f[7],1,time()+86400)
        mark.item=TC.Integer(f[8],1,2147483647)
        if not mark.owner or not mark.slot or not mark.requestRevision or not mark.item then return true end
    else return true end
    local all=Marks(); local slots=all[sender] or {}; local old=slots[index]
    if TC.SnapshotNewer(old,mark,relayed,old and TC.RequestMarkPacket(index,old),TC.RequestMarkPacket(index,mark)) then
        slots[index]=TC.StampSnapshot(mark,relayed); all[sender]=slots
        if TC.QueueRefresh then TC.QueueRefresh() end
    end
    return true
end
