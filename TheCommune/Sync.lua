local _, TC = ...
local PREFIX = "TheCommune1"
local function NewQueue()
    return {head = 1, tail = 0}
end

local queue, craftQueue, pending = NewQueue(), NewQueue(), {}

local function QueueLength()
    return queue.tail - queue.head + craftQueue.tail - craftQueue.head + 2
end
local lastQuery, lastReply = -100, -100
local peerSeen=false
local sendInterval,lastThrottle,lastWarning=1,-1000,-1000
TC.syncStatus = "Not connected"
local stats = { sent = 0, received = 0, applied = 0, rejected = 0, lastSend = "not attempted", registered = "not attempted" }
local retryAt, retryDelay = 0, 2
stats.throttled=0
TC.HasGuildPeer=function() return peerSeen end

local function ResultName(enumName, result)
    local values = Enum and Enum[enumName]
    if values then
        for name, value in pairs(values) do if value == result then return name .. " (" .. tostring(result) .. ")" end end
    end
    return tostring(result)
end

local function SetStatus(text)
    TC.syncStatus = text
    if TC.RefreshSyncStatus then TC.RefreshSyncStatus() end
end

function TC.DebugSync()
    if TC.DebugProtection then TC.DebugProtection() end
    local restricted = "unavailable"
    if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
        local ok, result = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
        restricted = ok and tostring(result) or "API error"
    end
    TC.Print("v" .. TC.version .. " | " .. tostring(TC.owner) .. " | Guild: " .. tostring(TC.guildKey or "none"))
    TC.Print("Prefix: " .. stats.registered .. " | restriction flag: " .. restricted .. " | queued: " .. QueueLength())
    TC.Print("Sent: " .. stats.sent .. " | received: " .. stats.received .. " | applied: " .. stats.applied .. " | rejected: " .. stats.rejected)
    TC.Print("Last send: " .. stats.lastSend .. " | last peer: " .. (stats.peer or "none"))
    TC.Print("Send spacing: "..string.format("%.1f",sendInterval).."s | throttles: "..stats.throttled.." | guild addon peer: "..tostring(peerSeen))
    TC.Print(TC.syncStatus)
    if TC.DebugTracking then TC.DebugTracking() end
    if TC.DebugHits then TC.DebugHits() end
    if TC.DebugCredits then TC.DebugCredits() end
end

function TC.Encode(slot, r, legacy)
    if r.deleted then return table.concat({"D", slot, r.revision}, "\t") end
    local body = table.concat({"R", slot, r.revision, r.item, r.quantity, r.received, r.expires,
        r.ongoing and "1" or "0", r.purpose, r.craft, r.delivery}, "\t")
    return not legacy and r.created and (body.."\t"..r.created) or body
end

function TC.Decode(message)
    if type(message) ~= "string" or #message > 254 then return end
    local fields = {}
    for part in (message .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = part end
    local kind = fields[1]
    if kind ~= "D" and kind ~= "R" then return end
    local slot = TC.Integer(fields[2], 1, TC.limit)
    local revision = TC.Integer(fields[3], 1, 9999999999)
    if not slot or not revision or revision > time() + 86400 then return end
    if kind == "D" then if #fields == 3 then return slot, {deleted = true, revision = revision} end return end
    if #fields ~= 11 and #fields ~= 12 then return end
    local r = { revision = revision, item = TC.Integer(fields[4], 1, 2147483647),
        quantity = TC.Integer(fields[5], 1, 999999), received = TC.Integer(fields[6], 0, 999999),
        expires = TC.Integer(fields[7], 0, 9999999999), ongoing = fields[8] == "1",
        purpose = TC.Clean(fields[9], 64), craft = TC.Clean(fields[10], 40), delivery = TC.Clean(fields[11], 40) }
    if not r.item or not r.quantity or not r.received or not r.expires or (fields[8] ~= "0" and fields[8] ~= "1") then return end
    if fields[12] then
        r.created=TC.Integer(fields[12],1,revision)
        if not r.created then return end
        r.createdKnown=true
    end
    return slot, r
end

local function Enqueue(key, message)
    if not TC.guildKey then return end
    if not pending[key] then
        local target = key:sub(1,5)=="craft" and craftQueue or queue
        target.tail = target.tail + 1
        target[target.tail] = key
    end
    pending[key] = message
end
TC.QueueGuildPacket = Enqueue

function TC.BroadcastSlot(slot)
    local r=TC.store.owners[TC.owner][slot]
    if r.created and not r.deleted then Enqueue("request-new:"..slot,TC.Encode(slot,r)) end
    if r.deleted and pending["request-new:"..slot] then Enqueue("request-new:"..slot,TC.Encode(slot,r)) end
    Enqueue(tostring(slot),TC.Encode(slot,r,true))
end

local function BroadcastRequests()
    for slot in pairs(TC.store.owners[TC.owner]) do TC.BroadcastSlot(slot) end
end

function TC.BroadcastAll()
    if not TC.store then return end
    BroadcastRequests()
    if TC.BroadcastGuildData then TC.BroadcastGuildData() end
    if TC.BroadcastGear then TC.BroadcastGear(true) end
    if TC.BroadcastDeathZones then TC.BroadcastDeathZones() end
end

function TC.Query(manual, lightweight)
    if TC.CheckMailProgress then TC.CheckMailProgress() end
    if not TC.guildKey then TC.Print("Join a guild to share requests. Your personal board still works."); return end
    if GetTime() - lastQuery < 30 then
        if manual then TC.Print("Sync cooldown: " .. math.ceil(30 - (GetTime() - lastQuery)) .. " seconds. Saving still queues requests automatically.") end
        return
    end
    lastQuery = GetTime()
    Enqueue("query", "Q\t1")
    if lightweight then
        -- Keep the legacy query so older peers can still answer. Our full
        -- snapshot is sent at login, on a peer's query, or on manual sync.
        BroadcastRequests()
        if TC.BroadcastProjects then TC.BroadcastProjects() end
    else
        TC.BroadcastAll()
    end
    SetStatus("Guild sync queued; waiting for responses")
    if manual then TC.Print("Guild sync queued. Allow a few seconds; /commune debug shows delivery details.") end
    return true
end

function TC.ResetSync()
    queue, craftQueue, pending = NewQueue(), NewQueue(), {}
    lastQuery, lastReply = -100, -100
    retryAt, retryDelay = 0, 2
    peerSeen=false; sendInterval=1; lastThrottle=-1000; lastWarning=-1000
    TC.syncStatus = TC.guildKey and "Guild sharing ready" or "Personal board (no guild)"
    C_Timer.After(3, TC.Query)
end

function TC.Receive(prefix, message, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" or not TC.guildKey then return end
    sender = TC.NormalizeName(sender)
    if not sender or sender == TC.owner then return end
    local firstPeer=not peerSeen
    peerSeen=true
    stats.received = stats.received + 1
    stats.peer = sender
    if message == "Q\t1" then
        SetStatus("Sync query received from " .. TC.DisplayName(sender))
        if GetTime() - lastReply > 30 then
            lastReply = GetTime()
            -- Spread responses across the guild to avoid a login burst.
            local guild = TC.guildKey
            C_Timer.After(math.random() * 3, function()
                if TC.guildKey == guild then TC.BroadcastAll() end
            end)
        end
        return
    end
    if firstPeer then
        local guild=TC.guildKey
        C_Timer.After(0.5+math.random()*2,function() if TC.guildKey==guild then TC.BroadcastAll() end end)
    end
    if TC.ReceiveGuildData and TC.ReceiveGuildData(message, sender) then return end
    local slot, r = TC.Decode(message)
    if not slot then stats.rejected = stats.rejected + 1; return end
    TC.store.owners[sender] = TC.store.owners[sender] or {}
    local previous = TC.store.owners[sender][slot]
    if not previous or r.revision > previous.revision or (r.revision==previous.revision and r.createdKnown and
        (not previous.createdKnown or r.created~=previous.created)) then
        if not r.created and not r.deleted then
            r.created=previous and not previous.deleted and previous.item==r.item and
                (previous.created or previous.revision) or r.revision
            r.createdKnown=previous and previous.createdKnown or false
        end
        TC.store.owners[sender][slot] = r
        stats.applied = stats.applied + 1
        TC.RequestsChanged()
        if not r.deleted and TC.LearnItem and not (TC.db.itemIndex and TC.db.itemIndex[r.item]) then TC.LearnItem(r.item) end
        if TC.QueueRefresh then TC.QueueRefresh() end
        SetStatus("Received requests from " .. TC.DisplayName(sender))
    end
end

function TC.StartSync()
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        TC.syncStatus = "Guild messaging API unavailable"; return
    end
    local registered, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    stats.registered = registered and ResultName("RegisterAddonMessagePrefixResult", result) or tostring(result)
    if not registered or result == false then
        SetStatus("Cannot register guild messages: " .. stats.registered)
        TC.Print(TC.syncStatus)
        return
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, ...) TC.Receive(...) end)
    -- Conservative pacing, coalescing and adaptive backoff for Forever's limits.
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < sendInterval then return end
        elapsed = 0
        if QueueLength() == 0 or not TC.guildKey or GetTime() < retryAt then return end
        -- The general restriction flag is advisory: let the GUILD API's actual
        -- result decide whether this message is permitted. Do not change channels.
        -- Requests/projects should not wait behind a large recipe scan.
        local target = queue.head <= queue.tail and queue or craftQueue
        local key = target[target.head]
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, pending[key], "GUILD")
        -- Modern clients return an enum; older builds may return nil or boolean.
        local success = ok and result ~= false
        if Enum and Enum.SendAddonMessageResult and type(result) == "number" then
            success = ok and result == Enum.SendAddonMessageResult.Success
        end
        stats.lastSend = ok and ResultName("SendAddonMessageResult", result) or TC.Clean(result, 160)
        if success then
            local recovering=retryAt>0
            target[target.head], pending[key] = nil, nil
            if target.head == target.tail then
                target.head, target.tail = 1, 0
            else
                target.head = target.head + 1
            end
            stats.sent = stats.sent + 1
            retryAt, retryDelay = 0, 2
            if GetTime()-lastThrottle>60 then sendInterval=math.max(1,sendInterval-0.1) end
            if recovering then SetStatus(QueueLength()>0 and "Sharing queued guild updates" or "Guild updates sent")
            elseif QueueLength() == 0 and stats.received == 0 then SetStatus("Sent to guild; no peer response yet") end
        else
            local values=Enum and Enum.SendAddonMessageResult or {}
            local throttled=ok and (result==3 or result==8 or
                (values.AddonMessageThrottle~=nil and result==values.AddonMessageThrottle) or
                (values.ChannelThrottle~=nil and result==values.ChannelThrottle))
            if throttled then
                stats.throttled=stats.throttled+1; lastThrottle=GetTime()
                sendInterval=math.min(8,math.max(2,sendInterval*1.5))
                retryDelay=math.max(5,retryDelay)
                SetStatus("Guild sync paused by WoW's rate limit; retry queued")
            else
                SetStatus("Guild send failed: "..stats.lastSend.."; retry queued")
                if GetTime()-lastWarning>=60 then TC.Print(TC.syncStatus..". /commune debug for details."); lastWarning=GetTime() end
            end
            retryAt=GetTime()+retryDelay
            retryDelay=math.min(retryDelay*2,60)
        end
    end)
    TC.ResetSync()
end
