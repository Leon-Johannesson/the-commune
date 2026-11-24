local _, TC = ...
local observed, serial, lastFatal = {}, 0

local function Safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
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
    if count < 256 or observed[guid] then observed[guid] = {cause=cause, when=now} end
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

local function ReadCause(deathTime)
    local events = C_DeathRecap and Safe(C_DeathRecap.GetRecapEvents)
    if type(events) ~= "table" or (issecrettable and issecrettable(events)) then return end
    local row = Safe(function() return events[1] end)
    if type(row) ~= "table" or (issecrettable and issecrettable(row)) then return end
    local stamp = Safe(function() return row.timestamp end)
    local overkill = Safe(function() return row.overkill end)
    if type(stamp) ~= "number" or math.abs(stamp - deathTime) > 3 or type(overkill) ~= "number" or overkill < 0 then return end
    local event = Safe(function() return row.event end)
    local guid = Safe(function() return row.sourceGUID end)
    local signature = tostring(guid) .. ":" .. stamp .. ":" .. tostring(event)
    if signature == lastFatal then return end
    if event == "ENVIRONMENTAL_DAMAGE" then return "pve", signature end
    if type(guid) ~= "string" then return end
    if guid == Safe(UnitGUID, "player") then return "pve", signature end
    if guid:match("^Player%-") then return "pvp", signature end
    local source = observed[guid]
    if source and GetTime() - source.when <= 30 then return source.cause, signature end
end

function TC.ClassifyZoneDeath(profile, key)
    -- Keep the zone captured at PLAYER_DEAD even if release moves the player.
    -- Never turn missing/secret recap data into an assumed PvE death.
    serial = serial + 1
    local token, store, owner = serial, TC.store, TC.owner
    local deathTime, attempts, finished = Safe(GetServerTime) or time(), 0, false
    ObserveVisible()
    local function Check()
        if finished or token ~= serial or not TC.db or not TC.db.fun or TC.db.fun.pvp[owner] ~= profile then return end
        attempts = attempts + 1
        local cause, signature = ReadCause(deathTime)
        if cause then
            finished = true
            lastFatal = signature
            TC.RecordZoneDeathCause(profile, key, cause, store)
            return
        end
        if attempts < 16 then C_Timer.After(0.5, Check) end
    end
    C_Timer.After(0.5, Check)
end

local events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, unit)
    if not TC.db or not TC.db.fun then return end
    TC.ObserveDeathCauseUnit(event == "PLAYER_TARGET_CHANGED" and "target" or event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or unit)
end)
