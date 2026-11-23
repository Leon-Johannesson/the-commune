local addonName, TC = ...
_G.TheCommune = TC
TC.version = "0.4.31"
TC.limit = 20

function TC.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff79d6adThe Commune:|r " .. message)
end

-- Keep user text safe for tooltips, the wire format, and UTF-8 truncation.
function TC.Clean(value, limit)
    local text = tostring(value or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("[%c|]", " ")
    text = text:match("^%s*(.-)%s*$")
    if #text > limit then
        local cut = limit + 1
        while cut > 1 and (text:byte(cut) or 0) >= 128 and (text:byte(cut) or 0) < 192 do cut = cut - 1 end
        text = text:sub(1, cut - 1)
    end
    return text
end

function TC.Integer(value, low, high)
    local n = tonumber(value)
    if not n or n ~= n or n % 1 ~= 0 or n < low or n > high then return nil end
    return n
end

function TC.NormalizeName(name)
    if type(name) ~= "string" or name == "" then return nil end
    -- Forever can deliver "Radio Lysander-CAMWOWEU5Realm8PvP" for the
    -- same character that UnitFullName identifies as "Radio", "Lysander".
    -- The CAMWOW suffix is a physical realm, not the character's virtual realm.
    local virtualName, physicalRealm = name:match("^([^%-]+)%-(.+)$")
    if virtualName and virtualName:find(" ", 1, true) and physicalRealm:match("^CAMWOW") then
        return (virtualName:gsub("%s+", "-"))
    end
    if not name:find("-", 1, true) and name:find(" ", 1, true) then
        return (name:gsub("%s+", "-"))
    end
    if not name:find("-", 1, true) then
        local realm=GetNormalizedRealmName()
        if not realm or realm=="" then realm=GetRealmName() end
        if realm and realm~="" then name=name.."-"..realm:gsub("%s","") end
    end
    return name
end

local roster, surnames, rosterLoaded = {}, {}, false
TC.rosterGeneration = 0

local function InvalidateRoster()
    roster, surnames, rosterLoaded = {}, {}, false
    TC.rosterGeneration = TC.rosterGeneration + 1
end

-- Rank, level, class and surname all used to be read by walking the whole
-- roster and normalising every name, from functions the UI calls on each
-- refresh. Scan once per roster change and let everyone read the result.
local function Roster()
    if not TC.guildKey or rosterLoaded or not GetNumGuildMembers or not GetGuildRosterInfo then return roster, surnames end
    local count = GetNumGuildMembers()
    if not count or count == 0 then return roster, surnames end
    roster, surnames, rosterLoaded = {}, {}, true
    for index = 1, count do
        local name, _, rank, level, class, _, _, _, _, _, token = GetGuildRosterInfo(index)
        local canonical = TC.NormalizeName(name)
        if canonical then
            roster[canonical] = {rank = rank, level = TC.Integer(level, 1, 255), class = class, token = token}
            local given, last = canonical:match("^([^-]+)%-(.+)$")
            if last and not last:match("^CAMWOW") then
                -- Two guildmates can share a given name; it then names nobody.
                if surnames[given] == nil then surnames[given] = last
                elseif surnames[given] ~= last then surnames[given] = false end
            end
        end
    end
    return roster, surnames
end

function TC.GuildRoster()
    local members = Roster()
    return members
end

local function RosterSurnames()
    local _, names = Roster()
    return names
end

function TC.Surname(canonical, given)
    local social = TC.store and TC.store.social
    local account = social and social.characters and social.characters[canonical]
    local profile = account and social.accounts and social.accounts[account]
    -- A published label is the owner's own claim, so take the surname from it
    -- only when its given name matches the key the packet already proved.
    if profile and type(profile.name) == "string" then
        local first, rest = profile.name:match("^(%S+)%s+(%S.*)$")
        if rest and first == given then return rest end
    end
    local last = RosterSurnames()[given]
    if last then return last end
end

function TC.DisplayName(owner)
    local canonical = TC.NormalizeName(owner)
    if not canonical then return "Unknown" end
    local first,last=canonical:match("^([^-]+)%-(.+)$")
    if not first then return canonical end
    if last:match("^CAMWOW") then last=TC.Surname(canonical,first) end
    return last and (first.." "..last) or first
end

function TC.MergeOwnerAliases(store)
    -- Rebuild keys instead of removing them while iterating. A slot is the same
    -- request across aliases; retain its newest revision, including deletions.
    local owners = {}
    for owner, slots in pairs(store.owners) do
        local canonical = TC.NormalizeName(owner)
        owners[canonical] = owners[canonical] or {}
        for slot, r in pairs(slots) do
            local previous = owners[canonical][slot]
            if not previous or r.revision > previous.revision or
                (r.revision == previous.revision and r.deleted and not previous.deleted) then
                owners[canonical][slot] = r
            end
        end
    end
    store.owners = owners
end

function TC.Identity()
    local name, realm = UnitFullName("player")
    return TC.NormalizeName(name .. (realm and realm ~= "" and ("-" .. realm) or ""))
end

function TC.SetGuild(onlyIfChanged)
    local guild, _, _, realm = GetGuildInfo("player")
    TC.owner = TC.Identity()
    local guildKey=TC.GuildStorageKey(guild,realm)
    TC.guildPending=not guildKey and IsInGuild and IsInGuild() or false
    if TC.guildPending and TC.guildKey then return false end
    local changed=not TC.store or TC.guildKey~=guildKey
    if onlyIfChanged and not changed then return false end
    if changed then InvalidateRoster() end
    TC.guildKey=guildKey
    if guildKey then TC.MergeEmptyRealmGuild(guild,guildKey) end
    -- Personal drafts work outside a guild and never leak into the next guild.
    local key = TC.guildKey or ("unguilded:" .. TC.owner)
    TC.db.guilds[key] = TC.db.guilds[key] or { owners = {} }
    TC.store = TC.db.guilds[key]
    TC.MergeOwnerAliases(TC.store)
    TC.store.owners[TC.owner] = TC.store.owners[TC.owner] or {}
    if TC.RegisterCharacter then TC.RegisterCharacter() end
    if TC.InitGuildData then TC.InitGuildData() end
    if TC.InvalidateRecipes then TC.InvalidateRecipes() end
    if TC.InitSocial then TC.InitSocial() end
    if not TC.guildKey and TC.HideFlightPanel then TC.HideFlightPanel() end
    if not TC.guildKey and TC.HideDeathPrompt then TC.HideDeathPrompt() end
    -- Retire the removed options on our own published requests. Revision the
    -- change so guildmates also receive the updated, non-expiring request.
    for _, r in pairs(TC.store.owners[TC.owner]) do
        if not r.deleted and (r.expires ~= 0 or r.ongoing or r.craft ~= "") then
            r.expires, r.ongoing, r.craft = 0, false, ""
            r.revision = math.max(time(), r.revision + 1)
        end
    end
    TC.RequestsChanged()
    if TC.Refresh then TC.Refresh() end
    return changed
end

function TC.IsActive(r)
    return r and not r.deleted and r.received < r.quantity
end

-- Gold is not an item, so a request for it rides the existing item field under
-- a sentinel no real item can reach. That keeps the R packet exactly as it is:
-- older clients still accept the request and merely name it as an unknown
-- item, instead of rejecting a packet whose field count they do not know.
TC.GOLD = 2147483647

local pendingItems = {}

function TC.ItemName(id)
    if not id then return "Drop an item" end
    if id == TC.GOLD then return "Gold", nil, "Interface\\Icons\\INV_Misc_Coin_01" end
    local name, link, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
    if not name and not pendingItems[id] and C_Item.RequestLoadItemDataByID then
        pendingItems[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    -- Quality is a trailing return so existing callers keep working unchanged.
    return name or ("Item #" .. id), link or ("item:" .. id), texture or 134400, quality
end

local activeRequestsByItem

function TC.RequestsChanged()
    activeRequestsByItem = nil
    if TC.UpdateSummary and TC.wallet then TC.UpdateSummary() end
end

function TC.Rows(filter, query, includeClosed)
    local rows = {}
    if not TC.store then return rows end
    query = (query or ""):lower()
    local itemNames = {}
    for owner, slots in pairs(TC.store.owners) do
        if filter ~= "mine" or owner == TC.owner then
            local displayName
            for slot, r in pairs(slots) do
                if not r.deleted and (includeClosed or TC.IsActive(r)) then
                    displayName = displayName or TC.DisplayName(owner)
                    local item
                    if query ~= "" then
                        item = itemNames[r.item]
                        if not item then
                            local name, _, icon = TC.ItemName(r.item)
                            item = {name = name, icon = icon}
                            itemNames[r.item] = item
                        end
                    end
                    if not item or (owner .. " " .. displayName .. " " .. item.name .. " " .. r.purpose):lower():find(query, 1, true) then
                        rows[#rows + 1] = {owner = owner, slot = slot, request = r, displayName = displayName, item = item}
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b) if a.owner == b.owner then return a.slot < b.slot end return a.owner < b.owner end)
    return rows
end

function TC.Save(slot, data)
    local editingExisting = slot ~= nil
    local item = TC.Integer(data.item, 1, 2147483647)
    local quantity = TC.Integer(data.quantity == nil and 1 or data.quantity, 1, 999999)
    local received = TC.Integer(data.received == nil and 0 or data.received, 0, 999999)
    if not item then return nil, "Enter an exact known item name, choose a suggestion, or drop/link an item." end
    if not quantity or not received then return nil, "Use whole numbers: quantity 1-999999, received 0-999999." end
    local slots = TC.store.owners[TC.owner]
    if not slot then
        for i = 1, TC.limit do if not slots[i] or not TC.IsActive(slots[i]) then slot = i; break end end
    end
    if not slot then return nil, "You have 20 active requests. Close one before adding another." end
    local previous = slots[slot]
    local revision = math.max(time(), (previous and previous.revision or 0) + 1)
    -- Keep the legacy wire fields empty for compatibility with older clients.
    slots[slot] = { item = item, quantity = quantity, received = received, ongoing = false,
        expires = 0, revision = revision,
        created = editingExisting and previous and TC.IsActive(previous) and previous.item==item and (previous.created or previous.revision) or revision,
        purpose = TC.Clean(data.purpose, 64), craft = "", delivery = TC.Clean(data.delivery, 40) }
    TC.BroadcastSlot(slot)
    TC.RequestsChanged()
    if TC.Refresh then TC.Refresh() end
    return slot
end

function TC.Close(slot)
    local r = TC.store.owners[TC.owner][slot]
    if not r or r.deleted then return end
    -- Closing retires the request without tombstoning it, so "Include closed"
    -- still has something to show and the purpose survives. received==quantity
    -- is the only closed state the R packet can express, which leaves the wire
    -- format untouched and reads the same on older clients.
    r.received = r.quantity
    r.revision = math.max(time(), r.revision + 1)
    TC.BroadcastSlot(slot)
    TC.RequestsChanged()
    if TC.Refresh then TC.Refresh() end
end

function TC.Delete(slot)
    local r = TC.store.owners[TC.owner][slot]
    if not r then return end
    TC.store.owners[TC.owner][slot] = { deleted = true, revision = math.max(time(), r.revision + 1) }
    TC.BroadcastSlot(slot)
    TC.RequestsChanged()
    if TC.Refresh then TC.Refresh() end
end

local function AddTooltip(tooltip, data)
    if not TC.store or not data or not data.id then return end
    if issecretvalue and issecretvalue(data.id) then return end
    if not activeRequestsByItem then
        activeRequestsByItem = {}
        for owner, slots in pairs(TC.store.owners) do
            for _, r in pairs(slots) do
                if TC.IsActive(r) then
                    local matches = activeRequestsByItem[r.item] or {}
                    matches[#matches + 1] = {owner = owner, r = r}
                    activeRequestsByItem[r.item] = matches
                end
            end
        end
        for _, matches in pairs(activeRequestsByItem) do
            table.sort(matches, function(a, b) return a.owner < b.owner end)
        end
    end
    local matches = activeRequestsByItem[data.id]
    if not matches then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("The Commune - Guild requests", 0.47, 0.84, 0.68)
    for i = 1, math.min(#matches, 8) do
        local m = matches[i]
        local need = math.max(0, m.r.quantity - m.r.received) .. " more needed"
        tooltip:AddDoubleLine(TC.DisplayName(m.owner), need, 1, 1, 1, 0.47, 0.84, 0.68)
        if m.r.purpose ~= "" then tooltip:AddLine(m.r.purpose, 0.8, 0.8, 0.8, true) end
        if m.r.delivery ~= "" then tooltip:AddLine("Delivery: " .. m.r.delivery, 0.8, 0.8, 0.8, true) end
    end
    if #matches > 8 then tooltip:AddLine((#matches - 8) .. " more requests - /commune", 0.8, 0.8, 0.8) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
pcall(events.RegisterEvent, events, "GUILD_RANKS_UPDATE")
events:RegisterEvent("MERCHANT_SHOW")
local function RefreshGuild()
    local previous=TC.guildKey
    if TC.SetGuild(true) then
        TC.ResetSync()
        if not previous and TC.guildKey then TC.ShowSummary() end
    elseif TC.Refresh then TC.Refresh() end
end
local retryScheduled
local function RetryGuild()
    if TC.guildKey or retryScheduled then return end
    retryScheduled=true
    if TC.guildPending and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    for _, seconds in ipairs({1,3,8,15}) do C_Timer.After(seconds, function()
        if seconds==15 then retryScheduled=false end
        if not TC.guildKey then RefreshGuild() end
    end) end
end
function TC.RefreshGuildMembership()
    if TC.store and not TC.guildKey then RefreshGuild(); RetryGuild() end
end
events:SetScript("OnEvent", function(_, event, arg, success)
    if event == "GUILD_ROSTER_UPDATE" or event == "GUILD_RANKS_UPDATE" then
        InvalidateRoster()
        if TC.InvalidateRecipes then TC.InvalidateRecipes() end
    end
    if event == "ADDON_LOADED" and arg == addonName then
        TheCommuneDB = TheCommuneDB or { version = 1, guilds = {} }
        TheCommuneDB.guilds = TheCommuneDB.guilds or {}
        TC.db = TheCommuneDB
    elseif event == "PLAYER_LOGIN" then
        TC.SetGuild()
        TC.InitItemSearch()
        TC.StartSocial()
        TC.StartProgress()
        TC.StartSync()
        RetryGuild()
        if TC.StartGuildData then TC.StartGuildData() end
        if TC.StartSummary then TC.StartSummary() end
        if TC.StartMinimapButton then TC.StartMinimapButton() end
        if TooltipDataProcessor and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddTooltip)
            if Enum.TooltipDataType.Unit then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, TC.AddHitTooltip) end
        else TC.Print("Item tooltip API unavailable on this client.") end
        TC.Print("v" .. TC.version .. " loaded. Type /commune to open the guild board.")
    elseif event == "MERCHANT_SHOW" and TC.store then
        if TC.guildKey then TC.Query(false, true) end
    elseif event == "PLAYER_GUILD_UPDATE" and TC.db and (arg == "player" or not arg) then
        if TC.store then RefreshGuild(); RetryGuild() end
    elseif TC.store and event == "PLAYER_ENTERING_WORLD" then
        RefreshGuild()
    elseif TC.store and (event == "GUILD_ROSTER_UPDATE" or event == "GUILD_RANKS_UPDATE") then
        if not TC.guildKey or TC.guildKey:sub(1,1)==":" then RefreshGuild() end
        if TC.RetryDeferredProjects then TC.RetryDeferredProjects() end
        if TC.RetryDeferredCredits then TC.RetryDeferredCredits() end
        if TC.Refresh then TC.Refresh() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local waiting = pendingItems[arg]
        if arg then pendingItems[arg] = nil end
        local recipeChanged = TC.RecipeOutputDataReceived and TC.RecipeOutputDataReceived(arg)
        if success ~= false and (waiting or recipeChanged) and TC.QueueRefresh then TC.QueueRefresh() end
    end
end)
