local _, TC = ...
local bankOpen, guildBankOpen, mailOpen, vendorOpen = false, false, false, false
local suppressUntil = 0
local pendingMail
local patterns, seenLines = {}, {}
local tracking = { loot = 0, mail = 0, last = "No automatic acquisitions this session" }

function TC.RegisterCharacter()
    TC.db.characters = TC.db.characters or {}
    TC.db.characters[TC.owner] = true
end

local function OwnSender(sender)
    if type(sender) ~= "string" or sender == "" then return true end
    local canonical = TC.NormalizeName(sender)
    if canonical == TC.owner or TC.db.characters[canonical] then return true end
    -- A sender without a realm is ambiguous; err on the side of not counting
    -- our own character/known alts, even if another realm has the same name.
    if not sender:find("-", 1, true) and not sender:find(" ", 1, true) then
        for owner in pairs(TC.db.characters) do
            if (owner:match("^([^%-]+)") or owner):lower() == sender:lower() then return true end
        end
    end
    return false
end

local function Targets(item)
    local targets = {}
    if TC.store then
        for slot, r in pairs(TC.store.owners[TC.owner]) do
            if r.item == item and TC.IsActive(r) then targets[slot] = r end
        end
    end
    return targets
end

local function RecordGain(item, quantity, source, targets)
    if not TC.store or not TC.Integer(quantity, 1, 999999) then return end
    local remaining, credited = quantity, 0
    -- Allocate each unit once, in request-slot order, even when several of our
    -- own projects request the same item. Never change somebody else's request.
    for slot = 1, TC.limit do
        local r = TC.store.owners[TC.owner][slot]
        if r and (not targets or targets[slot] == r) and r.item == item and TC.IsActive(r) then
            local amount = math.min(remaining, r.quantity - r.received)
            r.received = r.received + amount
            r.revision = math.max(time(), r.revision + 1)
            remaining, credited = remaining - amount, credited + amount
            TC.BroadcastSlot(slot)
            if remaining == 0 then break end
        end
    end
    if credited > 0 then
        tracking[source == "loot" and "loot" or "mail"] = tracking[source == "loot" and "loot" or "mail"] + credited
        tracking.last = credited .. " x " .. TC.ItemName(item) .. " from " .. source
        if TC.Refresh then TC.Refresh() end
    end
end

-- Compile the client's localized loot formats, including positional placeholders.
-- Match only SELF loot; pushed/created/party-member messages are not accepted.
local function LootPattern(format)
    if type(format) ~= "string" then return end
    local pattern, captures, cursor, argument = "^", {}, 1, 0
    while cursor <= #format do
        local first, last, position, kind = format:find("%%(%d+)%$([sd])", cursor)
        local plainFirst, plainLast, plainKind = format:find("%%([sd])", cursor)
        if plainFirst and (not first or plainFirst < first) then
            first, last, position, kind = plainFirst, plainLast, nil, plainKind
        end
        local literal = format:sub(cursor, first and first - 1 or #format)
        literal = literal:gsub("%%%%", "%%"):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        pattern = pattern .. literal
        if not first then break end
        argument = argument + 1
        captures[#captures + 1] = tonumber(position) or argument
        pattern = pattern .. (kind == "d" and "(%d+)" or "(.+)")
        cursor = last + 1
    end
    return { pattern = pattern .. "$", captures = captures }
end

local function LootItemID(text)
    local id = tonumber(text:match("item:(%d+)"))
    if id then return id end
    -- Forever sometimes emits [Item name] instead of a hyperlink.
    local plain = TC.Clean(text, 200):match("^%[(.-)%]$") or TC.Clean(text, 200)
    if TC.store then
        for _, r in pairs(TC.store.owners[TC.owner]) do
            if TC.IsActive(r) then
                local name = C_Item.GetItemInfo(r.item)
                if name and name == plain then return r.item end
            end
        end
    end
end

local function OnLoot(message, lineID)
    if not TC.store or type(message) ~= "string" then return end
    if issecretvalue and issecretvalue(message) then return end
    if bankOpen or guildBankOpen or vendorOpen or mailOpen or GetTime() < suppressUntil then return end
    if issecretvalue and issecretvalue(lineID) then lineID = nil end
    if type(lineID) == "number" and lineID > 0 then
        if seenLines[lineID] then return end
        seenLines[lineID] = GetTime()
        for id, when in pairs(seenLines) do if GetTime() - when > 60 then seenLines[id] = nil end end
    end
    for _, spec in ipairs(patterns) do
        local captures = { message:match(spec.pattern) }
        if #captures > 0 then
            local values = {}
            for i, value in ipairs(captures) do values[spec.captures[i]] = value end
            local item = values[1] and LootItemID(values[1])
            local quantity = TC.Integer(values[2] or 1, 1, 999999)
            if item and quantity then RecordGain(item, quantity, "loot") end
            return
        end
    end
end

local function MailSource(index)
    local _, _, sender, _, _, _, _, _, _, returned, _, canReply, isGM = GetInboxHeaderInfo(index)
    if not sender or returned or isGM then return end
    local invoice = GetInboxInvoiceInfo(index)
    if invoice == "buyer" then return "auction purchase" end
    if invoice and invoice ~= "" then return end
    -- Player mail must be replyable. System, expired/cancelled auctions,
    -- restorations and unknown mail are deliberately excluded.
    if canReply and not OwnSender(sender) then return "player mail" end
end

local function InboxTotals()
    local totals = {}
    for index = 1, GetInboxNumItems() do
        if MailSource(index) then
            for attachment = 1, (ATTACHMENTS_MAX_RECEIVE or ATTACHMENTS_MAX or 16) do
                local _, id, _, count, _, _, currency = GetInboxItem(index, attachment)
                if id and count and not currency then totals[id] = (totals[id] or 0) + count end
            end
        end
    end
    return totals
end

local function BagCount(item)
    -- Never use bank contents as an acquisition baseline.
    return C_Item.GetItemCount(item, false, false, false, false)
end

function TC.CheckMailProgress()
    local pending = pendingMail
    if not pending then return end
    if not mailOpen or pending.store ~= TC.store or pending.owner ~= TC.owner or
        GetTime() - pending.when > 15 or bankOpen or guildBankOpen then pendingMail = nil; return end
    local totals = InboxTotals()
    local complete = true
    for item, entry in pairs(pending.entries) do
        -- Require BOTH removal from eligible inbox attachments and an actual
        -- increase in carried items. A click, failed pickup, or deleted mail
        -- alone is never progress. Absolute totals prevent event double-counts.
        local delivered = math.max(0, math.min(entry.limit,
            entry.beforeInbox - (totals[item] or 0), BagCount(item) - entry.beforeBag))
        if delivered > entry.credited then
            RecordGain(item, delivered - entry.credited, entry.source, entry.targets)
            entry.credited = delivered
        end
        if entry.credited < entry.limit then complete = false end
    end
    if complete then pendingMail = nil end
end

local function CapturePickup(index, attachment)
    if not TC.store or not mailOpen or bankOpen or guildBankOpen then return end
    TC.CheckMailProgress()
    local source = MailSource(index)
    -- Do not let a failed eligible pickup consume a later self-mail pickup.
    if not source then pendingMail = nil; return end
    local totals = InboxTotals()
    if not pendingMail then pendingMail = { store = TC.store, owner = TC.owner, when = GetTime(), entries = {} } end
    pendingMail.when = GetTime()
    local first, last = attachment or 1, attachment or (ATTACHMENTS_MAX_RECEIVE or ATTACHMENTS_MAX or 16)
    for slot = first, last do
        local _, id, _, count, _, _, currency = GetInboxItem(index, slot)
        if id and count and count > 0 and not currency then
            local targets = Targets(id)
            if next(targets) then
                local entry = pendingMail.entries[id]
                if not entry then
                    entry = { limit = 0, beforeInbox = totals[id] or 0, beforeBag = BagCount(id),
                        credited = 0, source = source, targets = targets }
                    pendingMail.entries[id] = entry
                end
                entry.limit = entry.limit + count
            end
        end
    end
    if not next(pendingMail.entries) then pendingMail = nil end
end

local function CancelMailProgress()
    TC.CheckMailProgress()
    pendingMail = nil
end

function TC.DebugTracking()
    TC.Print("Auto progress this session: loot " .. tracking.loot .. ", mail/AH " .. tracking.mail .. ". " .. tracking.last)
    TC.Print("Self-mail excludes characters seen by this installation. Log each of your alts in once to recognize it.")
end

function TC.StartProgress()
    TC.RegisterCharacter()
    for _, key in ipairs({"LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF"}) do
        local pattern = LootPattern(_G[key])
        if pattern then patterns[#patterns + 1] = pattern end
    end
    if TakeInboxItem and AutoLootMailItem and GetInboxInvoiceInfo and GetInboxHeaderInfo and GetInboxItem and GetInboxNumItems then
        hooksecurefunc("TakeInboxItem", CapturePickup)
        hooksecurefunc("AutoLootMailItem", function(index) CapturePickup(index) end)
        for _, name in ipairs({"ReturnInboxItem", "DeleteInboxItem", "SendMail"}) do
            if _G[name] then hooksecurefunc(name, CancelMailProgress) end
        end
    else TC.Print("Mail acquisition tracking unavailable on this client; Received can still be corrected manually.") end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({"CHAT_MSG_LOOT", "BAG_UPDATE_DELAYED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_FAILED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED"}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_LOOT" then OnLoot((...), select(11, ...))
    elseif event == "MAIL_SHOW" then mailOpen = true; pendingMail = nil
    elseif event == "MAIL_CLOSED" then CancelMailProgress(); mailOpen = false; suppressUntil = GetTime() + 1
    elseif event == "MAIL_FAILED" then pendingMail = nil
    elseif event == "MAIL_INBOX_UPDATE" or event == "MAIL_SUCCESS" or event == "BAG_UPDATE_DELAYED" then
        if TC.store then TC.CheckMailProgress() end
    elseif event == "BANKFRAME_OPENED" then bankOpen = true; pendingMail = nil
    elseif event == "GUILDBANKFRAME_OPENED" then guildBankOpen = true; pendingMail = nil
    elseif event == "BANKFRAME_CLOSED" then bankOpen = false; suppressUntil = GetTime() + 1
    elseif event == "GUILDBANKFRAME_CLOSED" then guildBankOpen = false; suppressUntil = GetTime() + 1
    elseif event == "MERCHANT_SHOW" then vendorOpen = true
    elseif event == "MERCHANT_CLOSED" then vendorOpen = false; suppressUntil = GetTime() + 1 end
end)
