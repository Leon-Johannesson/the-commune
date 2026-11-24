local _, TC = ...

local function Safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event, level)
    if not TC.db or not TC.owner then return end
    TC.db.levelAnnouncements = TC.db.levelAnnouncements or {}
    local seen = TC.db.levelAnnouncements
    local previous = TC.Integer(seen[TC.owner], 1, 255) or 0
    if event == "PLAYER_LOGIN" then
        -- Establish a quiet baseline; installing or reloading is not a level-up.
        local current = TC.Integer(Safe(UnitLevel, "player"), 1, 255)
        if current then seen[TC.owner] = math.max(previous, current) end
        return
    end
    if issecretvalue and issecretvalue(level) then return end
    level = TC.Integer(level, 1, 255)
    if not level or level <= previous then return end
    -- Record the event before sending, so duplicate events or a chat error
    -- cannot cause repeated attempts. Unguilded milestones are not replayed.
    seen[TC.owner] = level
    if level % 2 ~= 0 or not TC.guildKey then return end
    local guild = Safe(GetGuildInfo, "player")
    if type(guild) ~= "string" or guild == "" then return end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) ~= "function" then return end
    local ok, result = pcall(send, "[The Commune] Ding! I just reached level " .. level .. "!", "GUILD")
    if not ok or result == false then TC.Print("Could not announce level " .. level .. " in guild chat.") end
end)
