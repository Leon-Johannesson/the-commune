local _,TC=...
-- Real inspection needs the player in range on a loaded unit, which rules out
-- offline guildmates and anyone across the map. Every client publishes its own
-- equipment instead, and the armory renders whatever the guild has cached.
local slots={1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,19}
local slotNames={[1]="Head",[2]="Neck",[3]="Shoulder",[4]="Shirt",[5]="Chest",[6]="Waist",[7]="Legs",[8]="Feet",
    [9]="Wrist",[10]="Hands",[11]="Finger 1",[12]="Finger 2",[13]="Trinket 1",[14]="Trinket 2",[15]="Back",
    [16]="Main hand",[17]="Off hand",[19]="Tabard"}
local allowed={}; for _,slot in ipairs(slots) do allowed[slot]=true end
local stages,gearStore,pendingSend,lastSignature={}
TC.GearSlots=slots
function TC.GearSlotName(slot) return slotNames[slot] or ("Slot "..slot) end

local function Safe(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b=pcall(fn,...)
    if ok and not (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return a,b end
end

-- Saves written before the armory existed have no gear table; add it rather
-- than assuming it, and drop half-assembled packets when the guild changes.
local function Store()
    if not TC.store or not TC.store.social then return end
    TC.store.social.gear=TC.store.social.gear or {}
    if gearStore~=TC.store then stages={}; lastSignature=nil; gearStore=TC.store end
    return TC.store.social.gear
end
TC.GearStore=Store

function TC.OwnGear()
    local items={}
    for _,slot in ipairs(slots) do
        local id=TC.Integer(Safe(GetInventoryItemID,"player",slot),1,9999999)
        if id then items[slot]=id end
    end
    local overall,equipped=Safe(GetAverageItemLevel)
    local level=TC.Integer(math.floor(tonumber(equipped) or tonumber(overall) or 0),0,9999) or 0
    return {items=items,ilvl=level}
end

function TC.BroadcastGear(force)
    local store=Store()
    if not store or not TC.guildKey then return end
    local snapshot=TC.OwnGear()
    local entries={}
    for _,slot in ipairs(slots) do
        if snapshot.items[slot] then entries[#entries+1]=slot..":"..snapshot.items[slot] end
    end
    local signature=snapshot.ilvl.."|"..table.concat(entries,",")
    local changed=signature~=lastSignature
    if not changed and not force then return end
    lastSignature=signature
    local own=store[TC.owner]
    -- A forced resend answers a sync query with the snapshot guildmates may
    -- have missed; only real equipment changes earn a new revision.
    if changed or not own or not own.revision then
        snapshot.revision=math.max(time(),((own and own.revision) or 0)+1)
        snapshot.when=time()
        store[TC.owner]=snapshot
    else
        snapshot=own
    end
    -- Keep every packet inside the 254-byte addon-message limit.
    local chunks,current={},""
    for _,entry in ipairs(entries) do
        local candidate=current=="" and entry or (current..","..entry)
        if #candidate>160 then chunks[#chunks+1]=current; current=entry else current=candidate end
    end
    chunks[#chunks+1]=current
    local total=math.min(#chunks,3)
    for part=1,total do
        TC.QueueGuildPacket("gear:"..part,table.concat({"GG",snapshot.revision,part,total,snapshot.ilvl,chunks[part]},"\t"))
    end
    if TC.RefreshArmory then TC.RefreshArmory() end
end

function TC.ReceiveGear(message,sender)
    if type(message)~="string" or message:sub(1,3)~="GG\t" then return false end
    local store=Store(); if not store then return true end
    local rev,part,total,ilvl,payload=message:match("^GG\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
    rev=TC.Integer(rev,1,time()+86400); part=TC.Integer(part,1,3); total=TC.Integer(total,1,3)
    ilvl=TC.Integer(ilvl,0,9999)
    if not rev or not part or not total or part>total or not ilvl or #payload>170 then return true end
    local count=0
    for key,stage in pairs(stages) do
        if stage.store~=TC.store or GetTime()-stage.when>120 then stages[key]=nil else count=count+1 end
    end
    local key=sender..":"..rev
    if not stages[key] and count>=60 then return true end
    local stage=stages[key] or {store=TC.store,total=total,parts={}}
    if stage.total~=total then stages[key]=nil; return true end
    stages[key]=stage; stage.when=GetTime(); stage.parts[part]=payload
    for index=1,total do if stage.parts[index]==nil then return true end end
    stages[key]=nil
    local items,seen={},0
    for index=1,total do
        for token in stage.parts[index]:gmatch("[^,]+") do
            local slot,id=token:match("^(%d+):(%d+)$")
            slot=TC.Integer(slot,1,19); id=TC.Integer(id,1,9999999)
            seen=seen+1
            if not slot or not id or not allowed[slot] or seen>#slots then return true end
            items[slot]=id
        end
    end
    local old=store[sender]
    -- Gear is a snapshot, not a record set: a newer revision replaces it whole.
    if not old or rev>old.revision then
        store[sender]={revision=rev,ilvl=ilvl,items=items,when=time()}
        if TC.RefreshArmory then TC.RefreshArmory() end
    end
    return true
end

-- Class and level are already on the guild roster, so they never go on the wire.
function TC.GearRoster()
    local roster=TC.GuildRoster()
    local own=roster[TC.owner] or {}
    if own.class and own.level then return roster, own end
    -- Only the current character needs a fallback. Keep it outside the roster.
    local class, token=own.class, own.token
    if not class then class,token=Safe(UnitClass,"player") end
    local level=own.level or TC.Integer(Safe(UnitLevel,"player"),1,255)
    return roster, {class=class,token=token,level=level}
end

function TC.GearRows()
    local store=Store(); local rows={}
    if not store then return rows end
    for owner,snapshot in pairs(store) do rows[#rows+1]={owner=owner,gear=snapshot,label=TC.DisplayName(owner)} end
    table.sort(rows,function(a,b) if a.label~=b.label then return a.label<b.label end; return a.owner<b.owner end)
    return rows
end

local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent",function()
    if not TC.store or not TC.guildKey or pendingSend then return end
    pendingSend=true
    -- Swapping a set fires once per slot; collapse the burst into one send.
    C_Timer.After(5,function() pendingSend=false; TC.BroadcastGear() end)
end)
