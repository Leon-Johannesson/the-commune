local _, TC = ...
local observed, serial, lastFatal, lastAnnounce = {}, 0, nil, -100
local pending, sending, blocked
local environments = {DROWNING="drowning", FALLING="the ground", FATIGUE="exhaustion",
    FIRE="fire", LAVA="lava", SLIME="slime"}

local function Safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local function Field(row, key)
    return Safe(function() return row[key] end)
end

function TC.ObserveDeathCauseUnit(unit)
    local guid = Safe(UnitGUID, unit)
    if type(guid) ~= "string" then return end
    local player, controlled = Safe(UnitIsPlayer, unit), Safe(UnitPlayerControlled, unit)
    local cause
    if player == true or controlled == true then cause = "pvp"
    elseif player == false and controlled == false then cause = "pve" end
    if not cause then return end
    local count, now = 0, GetTime()
    for key, entry in pairs(observed) do
        if now - entry.when > 30 then observed[key] = nil else count = count + 1 end
    end
    -- The name is only worth keeping for the announcement; the recap itself
    -- does not always carry a readable source name on this client.
    local name = Safe(UnitName, unit)
    if type(name) ~= "string" or name == "" then name = nil end
    if count < 256 or observed[guid] then observed[guid] = {cause=cause, when=now, name=name} end
end

local function ObserveVisible()
    for _, unit in ipairs({"target", "targetpet", "mouseover", "focus"}) do TC.ObserveDeathCauseUnit(unit) end
    local plates = C_NamePlate and Safe(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" or (issecrettable and issecrettable(plates)) then return end
    for _, plate in ipairs(plates) do
        local unit = Safe(function() return plate.namePlateUnitToken end)
        if type(unit) == "string" then TC.ObserveDeathCauseUnit(unit) end
    end
end

local function SpellName(id)
    id = TC.Integer(id, 1, 2147483647)
    if not id then return end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = Safe(C_Spell.GetSpellInfo, id)
        if type(info) == "table" and not (issecrettable and issecrettable(info)) then
            local name = Field(info, "name")
            if type(name) == "string" and name ~= "" then return name end
        end
    end
    local name = Safe(GetSpellInfo, id)
    if type(name) == "string" and name ~= "" then return name end
end

local function ReadCause(deathTime)
    local events = C_DeathRecap and Safe(C_DeathRecap.GetRecapEvents)
    if type(events) ~= "table" or (issecrettable and issecrettable(events)) then return end
    local row = Safe(function() return events[1] end)
    if type(row) ~= "table" or (issecrettable and issecrettable(row)) then return end
    local stamp = Field(row, "timestamp")
    local overkill = Field(row, "overkill")
    if type(stamp) ~= "number" or math.abs(stamp - deathTime) > 3 or type(overkill) ~= "number" or overkill < 0 then return end
    local event = Field(row, "event")
    local guid = Field(row, "sourceGUID")
    local signature = tostring(guid) .. ":" .. stamp .. ":" .. tostring(event)
    if signature == lastFatal then return end
    local detail = {}
    -- A swing has no spell behind it, so naming one would invent a cause.
    if event ~= "SWING_DAMAGE" then detail.spell = SpellName(Field(row, "spellId")) end
    local named = Field(row, "sourceName")
    if type(named) == "string" and named ~= "" then detail.source = named end
    if event == "ENVIRONMENTAL_DAMAGE" then
        local kind = Field(row, "environmentalType")
        detail.environment = type(kind) == "string" and environments[kind:upper()] or "the world itself"
        return "pve", signature, detail
    end
    if type(guid) ~= "string" then return end
    if guid == Safe(UnitGUID, "player") then detail.own = true; return "pve", signature, detail end
    local source = observed[guid]
    if source and GetTime() - source.when <= 30 and not detail.source then detail.source = source.name end
    if guid:match("^Player%-") then return "pvp", signature, detail end
    if source and GetTime() - source.when <= 30 then return source.cause, signature, detail end
end

local function Describe(detail)
    if not detail then return end
    if detail.environment then return detail.environment end
    if detail.own then return detail.spell and ("my own " .. detail.spell) or "my own doing" end
    if detail.source and detail.spell then return detail.source .. " (" .. detail.spell .. ")" end
    return detail.source or detail.spell
end

local function Status(text)
    if not TC.db or not TC.owner then return end
    TC.db.deathAnnouncementStatus = TC.db.deathAnnouncementStatus or {}
    TC.db.deathAnnouncementStatus[TC.owner] = {when = time(), text = text}
end

function TC.DebugDeathAnnounce()
    local status = TC.db and TC.db.deathAnnouncementStatus and TC.db.deathAnnouncementStatus[TC.owner]
    TC.Print("Death announcements: " .. (status and status.text or "no send attempted this version"))
end

local function Try(work)
    if pending ~= work or TC.owner ~= work.owner then return end
    if GetTime() - work.started > 120 then
        pending = nil; Status("expired before chat became available"); return
    end
    local guild = Safe(GetGuildInfo, "player")
    if Safe(IsInGuild) == false or (work.guild and type(guild) == "string" and guild ~= "" and guild ~= work.guild) then
        pending = nil; Status("cancelled after guild change"); return
    end
    -- Dying leaves the client in a chat-messaging lockdown, so a single send
    -- straight off the death event is dropped without raising an error.
    if Safe(InCombatLockdown) or Safe(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) or type(guild) ~= "string" or guild == "" then
        Status("waiting for combat/chat/guild readiness")
        C_Timer.After(2, function() Try(work) end); return
    end
    work.guild = work.guild or guild
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) ~= "function" then pending = nil; Status("chat API unavailable"); return end
    work.attempts = work.attempts + 1
    sending, blocked = true, false
    local ok, result = pcall(send, work.text, "GUILD")
    sending = false
    -- This API usually returns nil, so a missing echo is not grounds to send
    -- twice. Retry only an explicit rejection, an error, or a caught block.
    if ok and result ~= false and not blocked then
        pending = nil; Status("submitted to guild chat"); return
    end
    if work.attempts >= 3 then
        pending = nil; Status("failed after 3 attempts")
        TC.Print("Could not announce that death in guild chat. /commune debug includes the send status.")
    else
        Status("send rejected; retry queued")
        C_Timer.After(work.attempts * 3, function() Try(work) end)
    end
end

local function Announce(zone, detail)
    if not TC.db or not TC.guildKey then return end
    local now = GetTime()
    -- A corpse run back into the same hazard should not spam the guild.
    if now - lastAnnounce < 15 then return end
    local guild = Safe(GetGuildInfo, "player")
    if (type(guild) ~= "string" or guild == "") and Safe(IsInGuild) ~= true then
        Status("not in a guild at death"); return
    end
    local how = Describe(detail)
    local where = type(zone) == "string" and zone ~= "" and (" in " .. zone) or ""
    local text = how and ("[The Commune] I died" .. where .. " to " .. how .. ".")
        or ("[The Commune] I died" .. where .. ". No idea what hit me.")
    lastAnnounce = now
    pending = {owner = TC.owner, text = TC.Clean(text, 230), started = GetTime(), attempts = 0,
        guild = type(guild) == "string" and guild ~= "" and guild or nil}
    Try(pending)
end

function TC.ClassifyZoneDeath(profile, key, zone)
    -- Keep the zone captured at PLAYER_DEAD even if release moves the player.
    -- Never turn missing/secret recap data into an assumed PvE death.
    serial = serial + 1
    local token, store, owner = serial, TC.store, TC.owner
    local deathTime, attempts, finished = Safe(GetServerTime) or time(), 0, false
    ObserveVisible()
    local function Check()
        if finished or token ~= serial or not TC.db or not TC.db.fun or TC.db.fun.pvp[owner] ~= profile then return end
        attempts = attempts + 1
        local cause, signature, detail = ReadCause(deathTime)
        if cause then
            finished = true
            lastFatal = signature
            TC.RecordZoneDeathCause(profile, key, cause, store)
            Announce(zone, detail)
            return
        end
        if attempts < 16 then C_Timer.After(0.5, Check); return end
        -- The recap never became readable. Say the death happened rather than
        -- guessing at a cause the client would not show.
        finished = true
        Announce(zone)
    end
    C_Timer.After(0.5, Check)
end

local events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN"}) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if sending and unit == "TheCommune" then blocked = true end
        return
    end
    if not TC.db or not TC.db.fun then return end
    TC.ObserveDeathCauseUnit(event == "PLAYER_TARGET_CHANGED" and "target" or event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or unit)
end)
