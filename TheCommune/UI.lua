local _, TC = ...
local window, fields, rows, selected, editingSlot, editingOwner
local filter, offset, itemID = "all", 0, nil
local list, filterButtons = {}, {}
local visibleRows, resizeEnabled = 7, true
local loadedReceived
local Layout

local function Place(widget, x, y, width, height)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", x, y)
    if width then widget:SetWidth(width) end
    if height then widget:SetHeight(height) end
end

local function Label(parent, text, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Place(label, x, y, width)
    label:SetText(text); label:SetJustifyH("LEFT"); label:SetWordWrap(false); label:SetTextColor(0.82,0.77,0.66)
    return label
end

local function Button(parent, text, callback)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    TC.StyleButton(b)
    b:SetSize(140, 26); b:SetText(text); b:SetScript("OnClick", callback)
    return b
end

local function Edit(parent, title, max)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    TC.StyleEdit(box)
    box.label = Label(parent, title, 0, 0)
    box:SetAutoFocus(false); box:SetMaxLetters(max or 120)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function PlaceEdit(box, x, y, width)
    Place(box.label, x, y, width)
    Place(box, x, y - 20, width, 26)
end

local function SaveGeometry()
    if not window or not TC.db then return end
    local point, _, relativePoint, x, y = window:GetPoint(1)
    TC.db.ui = { width = window:GetWidth(), height = window:GetHeight(),
        point = point, relativePoint = relativePoint, x = x, y = y, compactLayout=1, resizeEnabled=resizeEnabled }
end

local function StopSizing()
    local wasResizing=window.resizing
    window:StopMovingOrSizing()
    window.resizing=false; window.layoutPending=false; window.resizeStart=nil
    if wasResizing and window.ready then Layout() end
    SaveGeometry()
end

-- One button, two stages: an open request closes, a closed one can then be
-- deleted for good. Keeps the editor's button row as it is.
local function UpdateCloseButton()
    local slots = TC.store and TC.store.owners[editingOwner or TC.owner]
    local r = editingSlot and slots and slots[editingSlot]
    window.deleteClosed = (r and not r.deleted and not TC.IsActive(r)) and true or false
    window.delete:SetText(window.deleteClosed and "Delete request" or "Close request")
end

local function SetEditable(editable)
    for _, field in pairs(fields) do field:SetEnabled(editable) end
    window.save:SetEnabled(editable)
    window.delete:SetEnabled(editable and editingSlot ~= nil)
    window.itemSlot:SetEnabled(editable)
    UpdateCloseButton()
end

local function UpdateItem()
    local name, _, texture = TC.ItemName(itemID)
    window.itemSlot.icon:SetTexture(texture or 134400)
    window.itemLabel:SetText(name)
end

local function LoadSelection(entry)
    selected = entry and (entry.owner .. ":" .. entry.slot) or nil
    editingOwner = entry and TC.CanEditRequest(entry.owner) and entry.owner or nil
    editingSlot = editingOwner and entry.slot or nil
    local r = entry and entry.request
    itemID = r and r.item or nil
    fields.item:SetText(itemID and (itemID == TC.GOLD and "gold" or tostring(itemID)) or "")
    fields.quantity:SetText(tostring(r and r.quantity or 1))
    fields.received:SetText(tostring(r and r.received or 0))
    loadedReceived = fields.received:GetText()
    fields.purpose:SetText(r and r.purpose or "")
    fields.delivery:SetText(r and r.delivery or "Mail or trade to me")
    window.editorTitle:SetText(entry and ("Request by " .. TC.DisplayName(entry.owner)) or "New request")
    window.feedback:SetText(entry and not TC.CanEditRequest(entry.owner) and "Only your account characters can edit this request." or "")
    SetEditable(not entry or TC.CanEditRequest(entry.owner))
    UpdateItem(); TC.Refresh()
end

local function ReceiveItem()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return end
    itemID = id; fields.item:SetText(tostring(id)); UpdateItem(); ClearCursor()
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, window.requestPage)
    local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.045 or 0.015)
    row.highlight = row:CreateTexture(nil, "ARTWORK"); row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.3, 0.7, 0.5, 0.2)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.owner = Label(row, "", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.item = Label(row, "", 0, 0)
    row.need = Label(row, "", 0, 0)
    row.purpose = Label(row, "", 0, 0)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; TC.Refresh() end)
    row:SetScript("OnClick", function(self) LoadSelection(self.entry) end)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        local r = self.entry.request
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. r.item)
        GameTooltip:AddLine("Received: " .. r.received .. " / " .. r.quantity, 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function TC.RefreshSyncStatus()
    if window and window:IsShown() and window.activePage~="social" then
        window.status:SetText(TC.syncStatus)
    end
end

function TC.Refresh()
    if not window or not window:IsShown() or not TC.store or not window.ready then return end
    if not TC.ApplyGuildAvailability(window) then editingSlot=nil; editingOwner=nil; selected=nil; return end
    if window.guildStateChanged then window.guildStateChanged=false; LoadSelection(nil); Layout(); return end
    if window.activePage=="social" then TC.RefreshSocialWindow(); return end
    if window.activePage~="requests" then
        local page = window.guildPages[window.activePage]
        if page then page.Update() end
        window.status:SetText(TC.syncStatus)
        return
    end
    if editingSlot then
        local r = TC.store.owners[editingOwner or TC.owner][editingSlot]
        -- Keep an open editor current without replacing a manual correction.
        if r and not r.deleted and fields.received:GetText() == loadedReceived then
            local received = tostring(r.received)
            if received ~= loadedReceived then
                fields.received:SetText(received)
                loadedReceived = received
            end
        end
    end
    rows = TC.Rows(filter, window.search:GetText(), window.closed:GetChecked())
    offset = math.max(0, math.min(offset, math.max(0, #rows - visibleRows)))
    local items = {}
    for i, row in ipairs(list) do
        local entry = i <= visibleRows and rows[offset + i] or nil
        if entry then
            row.entry = entry
            local r = entry.request
            local item = entry.item or items[r.item]
            if not item then
                local name, _, icon = TC.ItemName(r.item)
                item = {name = name, icon = icon}
                items[r.item] = item
            end
            row.owner:SetText(entry.displayName)
            row.icon:SetTexture(item.icon or 134400)
            row.item:SetText(item.name)
            row.need:SetText(not TC.IsActive(r) and "Closed" or
                (math.max(0, r.quantity - r.received) .. (r.item == TC.GOLD and "g" or "")))
            row.purpose:SetText(r.purpose)
            row.highlight:SetShown(selected == entry.owner .. ":" .. entry.slot)
            row:Show()
        else row.entry = nil; row:Hide() end
    end
    window.count:SetText(#rows .. " requests" .. (#rows > visibleRows and "  |  Scroll for more" or ""))
    window.status:SetText(TC.syncStatus)
    for name, button in pairs(filterButtons) do button:SetEnabled(filter ~= name) end
end

local refreshQueued
function TC.QueueRefresh()
    if refreshQueued or not window or not window:IsShown() then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        TC.Refresh()
        if window:IsShown() and window.activePage == "requests" then UpdateItem() end
    end)
end

Layout = function()
    if not window.ready then return end
    local width, height = window:GetWidth(), window:GetHeight()
    local content = width - 48
    if window.pageTabs then
        local tabWidth = math.min(112, math.floor((content - 6 * 8) / 7))
        for i, key in ipairs({"requests", "crafts", "projects", "hitlist", "armory", "deaths"}) do
            Place(window.pageTabs[key], 24 + (i - 1) * (tabWidth + 8), -70, tabWidth, 26)
        end
        Place(window.funButton, 24 + 6 * (tabWidth + 8), -70, tabWidth, 26)
    end
    if window.noGuildText then window.noGuildText:SetWidth(width-96) end
    local column = (content - 24) / 2
    local numberWidth = (column - 24) / 2
    local editorY = -(height - 252)
    Place(window.new, width - 276, -28, 116, 26)
    Place(window.sync, width - 148, -28, 124, 26)
    window.status:SetWidth(width - 324)
    if window.activePage=="social" then
        if TC.LayoutSocial then TC.LayoutSocial() end
        TC.Refresh(); return
    end
    local page = window.guildPages[window.activePage]
    if page then
        page.Layout()
        TC.Refresh()
        return
    end
    PlaceEdit(window.search, 292, -104, width - 492)
    Place(window.closed, width - 180, -120, 26, 26)
    Place(window.closedLabel, width - 148, -127, 124)
    local ownerWidth, itemWidth = math.floor(content * 0.20), math.floor(content * 0.32)
    local itemX, needX = ownerWidth, ownerWidth + itemWidth
    local purposeX = needX + 82
    Place(window.headers[1], 28, -160, ownerWidth - 12)
    Place(window.headers[2], 24 + itemX, -160, itemWidth - 12)
    Place(window.headers[3], 24 + needX, -160, 74)
    Place(window.headers[4], 24 + purposeX, -160, content - purposeX - 8)
    visibleRows = math.max(1, math.floor((height - 252 - 28 - 182) / 30))
    for i = 1, visibleRows do
        if not list[i] then list[i] = CreateRow(i) end
        local row = list[i]
        Place(row, 24, -182 - (i - 1) * 30, content, 30)
        Place(row.owner, 4, -9, ownerWidth - 12)
        Place(row.icon, itemX, -4, 22, 22)
        Place(row.item, itemX + 30, -9, itemWidth - 38)
        Place(row.need, needX, -9, 74)
        Place(row.purpose, purposeX, -9, content - purposeX - 8)
    end
    Place(window.count, 28, editorY + 25, content)
    Place(window.editor, 24, editorY, content, 232)
    Place(window.editorTitle, 0, -8, content)
    Place(window.itemSlot, 0, -48, 40, 40)
    PlaceEdit(fields.item, 52, -32, column - 52)
    Place(window.itemLabel, 52, -82, column - 52)
    PlaceEdit(fields.quantity, column + 24, -32, numberWidth)
    PlaceEdit(fields.received, column + 48 + numberWidth, -32, numberWidth)
    PlaceEdit(fields.purpose, 0, -108, column)
    PlaceEdit(fields.delivery, column + 24, -108, column)
    Place(window.feedback, 0, -179, content - 324, 32)
    Place(window.save, content - 296, -172, 140, 26)
    Place(window.delete, content - 140, -172, 140, 26)
    TC.Refresh()
end

local function Build()
    window = CreateFrame("Frame", "TheCommuneWindow", UIParent, "BackdropTemplate")
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local maxWidth, maxHeight = math.min(1500, screenWidth - 24), math.min(1100, screenHeight - 24)
    local minWidth, minHeight = math.min(760, maxWidth), math.min(550, maxHeight)
    local saved = TC.db.ui or {}
    resizeEnabled=saved.resizeEnabled~=false
    local previousWidth,previousHeight=tonumber(saved.width),tonumber(saved.height)
    if not saved.compactLayout then
        if previousWidth then previousWidth=previousWidth*0.92 end
        if previousHeight then previousHeight=previousHeight*0.92 end
    end
    local width = math.max(minWidth, math.min(maxWidth, previousWidth or 820))
    local height = math.max(minHeight, math.min(maxHeight, previousHeight or 600))
    window:SetSize(width, height)
    local points = {CENTER=true, TOP=true, BOTTOM=true, LEFT=true, RIGHT=true, TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true}
    if points[saved.point] and points[saved.relativePoint] and tonumber(saved.x) and tonumber(saved.y) then
        window:SetPoint(saved.point, UIParent, saved.relativePoint, tonumber(saved.x), tonumber(saved.y))
    else window:SetPoint("CENTER") end
    window:SetFrameStrata("DIALOG"); window:SetClampedToScreen(true)
    window:EnableMouse(true); window:SetMovable(true); window:RegisterForDrag("LeftButton")
    window:SetResizable(resizeEnabled); window:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    window.resizeBoundsBase={minWidth,minHeight,maxWidth,maxHeight}
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", StopSizing)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, insets = {left=4, right=4, top=4, bottom=4} })
    TC.StyleWindow(window)
    window.requestPage=CreateFrame("Frame",nil,window); window.requestPage:SetAllPoints(window)
    window.activePage="requests"
    table.insert(UISpecialFrames, "TheCommuneWindow")
    Label(window,"THE COMMUNE",24,-20):SetTextColor(0.47,0.84,0.68)
    window.status = Label(window, "", 24, -44)
    window.status:SetFontObject("GameFontDisableSmall")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetFrameLevel((window:GetFrameLevel() or 0)+50)
    close:SetScript("OnClick",function() window:Hide() end); window.close=close
    window.new = Button(window, "New request", function() LoadSelection(nil) end)
    window.sync = Button(window, "Sync guild", TC.Query)
    for i, entry in ipairs({{"all", "All requests"}, {"mine", "My requests"}}) do
        local key = entry[1]
        filterButtons[key] = Button(window.requestPage, entry[2], function() filter = key; offset = 0; TC.Refresh() end)
        Place(filterButtons[key], 24 + (i - 1) * 120, -124, 112, 26)
    end
    window.search = Edit(window.requestPage, "Search people, items, or purpose", 80)
    window.search:SetScript("OnTextChanged", function() offset = 0; TC.Refresh() end)
    window.closed = CreateFrame("CheckButton", nil, window.requestPage, "UICheckButtonTemplate")
    window.closedLabel = Label(window.requestPage, "Include closed", 0, 0)
    window.closed:SetScript("OnClick", function() offset = 0; TC.Refresh() end)
    window.headers = {}
    for i, title in ipairs({"GUILD MEMBER", "REQUESTED ITEM", "NEEDED", "PURPOSE"}) do
        window.headers[i] = Label(window.requestPage, title, 0, 0)
    end
    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; TC.Refresh() end)
    window.count = Label(window.requestPage, "", 0, 0)
    window.editor = CreateFrame("Frame", nil, window.requestPage)
    local separator = window.editor:CreateTexture(nil, "BACKGROUND")
    separator:SetColorTexture(0.47, 0.84, 0.68, 0.25)
    separator:SetPoint("BOTTOMLEFT", window.editor, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", window.editor, "TOPRIGHT", 0, 0); separator:SetHeight(1)
    window.editorTitle = Label(window.editor, "New request", 0, 0)
    fields = {}
    window.itemSlot = CreateFrame("Button", nil, window.editor)
    window.itemSlot.icon = window.itemSlot:CreateTexture(nil, "ARTWORK"); window.itemSlot.icon:SetAllPoints()
    window.itemSlot:SetScript("OnReceiveDrag", ReceiveItem); window.itemSlot:SetScript("OnClick", ReceiveItem)
    window.itemLabel = Label(window.editor, "Drop an item", 0, 0)
    window.itemLabel:SetFontObject("GameFontHighlightSmall")
    fields.item = Edit(window.editor, "Item name, link, ID - or type gold", 255)
    TC.AttachItemSearch(fields.item,window.editor,function(id)
        itemID=id; UpdateItem()
    end)
    fields.item:SetScript("OnReceiveDrag", ReceiveItem)
    fields.quantity = Edit(window.editor, "Target", 6)
    fields.received = Edit(window.editor, "Received", 6)
    fields.purpose = Edit(window.editor, "Purpose", 64)
    fields.delivery = Edit(window.editor, "Delivery instructions", 40)
    window.save = Button(window.editor, "Save request", function()
        local slot, err = TC.Save(editingSlot, { item = itemID, quantity = fields.quantity:GetText(), received = fields.received:GetText(),
            purpose = fields.purpose:GetText(), delivery = fields.delivery:GetText() }, editingOwner)
        if slot then
            editingOwner = editingOwner or TC.owner
            editingSlot = slot; selected = editingOwner .. ":" .. slot
            loadedReceived = fields.received:GetText()
            window.delete:Enable(); UpdateCloseButton()
            window.editorTitle:SetText("Request by " .. TC.DisplayName(editingOwner))
            window.feedback:SetText("Saved. " .. (TC.guildKey and "Queued for guild sharing." or "Personal request."))
            TC.Refresh()
        else window.feedback:SetText(err) end
    end)
    window.delete = Button(window.editor, "Close request", function()
        if not editingSlot then return end
        local removing = window.deleteClosed
        if removing then TC.Delete(editingSlot, editingOwner) else TC.Close(editingSlot, editingOwner) end
        LoadSelection(nil)
        window.feedback:SetText(removing and "Request deleted." or
            "Request closed. Tick Include closed to see it, then delete it for good.")
    end)
    window.feedback = Label(window.editor, "", 0, 0)
    window.feedback:SetWordWrap(true); window.feedback:SetJustifyV("TOP"); window.feedback:SetFontObject("GameFontHighlightSmall")
    window.feedback:SetTextColor(0.9, 0.8, 0.5)
    TC.BuildGuildPages(window,{Place=Place,Label=Label,Button=Button,Edit=Edit,PlaceEdit=PlaceEdit})
    TC.BuildHitlistPage(window,{Place=Place,Label=Label,Button=Button,Edit=Edit,PlaceEdit=PlaceEdit})
    TC.BuildArmoryPage(window,{Place=Place,Label=Label,Button=Button,Edit=Edit,PlaceEdit=PlaceEdit})
    TC.BuildDeathsPage(window,{Place=Place,Label=Label,Button=Button,Edit=Edit,PlaceEdit=PlaceEdit})
    window.pageTabs={}
    TC.ShowPage=function(name)
        if name~="requests" and not window.guildPages[name] then return end
        local changed=window.activePage~=name
        window.activePage=name
        window.socialHost:Hide(); window.back:Hide(); window.sync:Show(); window.funButton:Show()
        for _,tab in pairs(window.pageTabs) do tab:Show() end
        window.requestPage:SetShown(name=="requests"); window.new:SetShown(name=="requests")
        for key,page in pairs(window.guildPages) do page:SetShown(name==key) end
        for key,tab in pairs(window.pageTabs) do tab:SetEnabled(name~=key) end
        GameTooltip:Hide(); Layout()
        if TC.guildKey and changed and name=="hitlist" then TC.Query(false, true); TC.BroadcastHitCache() end
        if TC.guildKey and changed and name=="armory" then TC.Query(false, true); TC.BroadcastGear(true) end
    end
    for i,entry in ipairs({{"requests","Requests"},{"crafts","Crafts"},{"projects","Projects"},{"hitlist","Hitlist"},{"armory","Armory"},{"deaths","Deaths"}}) do
        local key=entry[1]
        local tab=Button(window,entry[2],function() TC.ShowPage(key) end)
        Place(tab,24+(i-1)*120,-70,112,26); window.pageTabs[key]=tab
        tab:SetEnabled(key~="requests")
    end
    window.funButton=Button(window,"Guild fun",function() TC.OpenSocial("scores") end)
    Place(window.funButton,624,-70,112,26)
    window.socialHost=CreateFrame("Frame",nil,window)
    window.socialHost:SetPoint("TOPLEFT",12,-64); window.socialHost:SetPoint("BOTTOMRIGHT",-12,12); window.socialHost:Hide()
    window.back=Button(window,"Back to guild",function() TC.ShowPage(window.previousPage or "requests") end)
    window.back:SetPoint("TOPRIGHT",-44,-28); window.back:Hide()
    window.noGuild=CreateFrame("Frame",nil,window)
    window.noGuild:SetPoint("TOPLEFT",24,-104); window.noGuild:SetPoint("BOTTOMRIGHT",-24,24); window.noGuild:Hide()
    window.noGuildText=window.noGuild:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
    window.noGuildText:SetPoint("CENTER"); window.noGuildText:SetJustifyH("CENTER"); window.noGuildText:SetWordWrap(true)
    window.noGuildText:SetText("You're not in a guild.\nJoin one to use The Commune.")
    window.grip = CreateFrame("Button", nil, window)
    window.grip:SetSize(22, 22); window.grip:SetPoint("BOTTOMRIGHT", -6, 6)
    window.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    window.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    window.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    window.grip:SetScript("OnMouseDown", function(_, button)
        if resizeEnabled and button == "LeftButton" then
            TC.BeginWindowResize(window)
        end
    end)
    window.grip:SetScript("OnMouseUp", StopSizing); window.grip:SetShown(resizeEnabled)
    window:SetScript("OnSizeChanged", function()
        if not window.ready then return end
        if window.resizing then window.layoutPending=true else Layout() end
    end)
    window:SetScript("OnHide", function() StopSizing(); GameTooltip:Hide() end)
    window:SetScript("OnShow", function()
        TC.Refresh()
        if window.ready and window.activePage == "requests" then UpdateItem() end
    end)
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if window:IsShown() and window.save:IsEnabled() and fields.item:HasFocus() then fields.item:SetText(link) end
        end)
    end
    window:SetScript("OnUpdate", function()
        TC.StepWindowResize(window,StopSizing)
        if window.layoutPending then window.layoutPending=false; Layout() end
    end)
    TC.RememberWindow(window,"main",TC.db.ui,false)
    window.ready = true
    Layout(); LoadSelection(nil); SaveGeometry()
end

function TC.GetMainWindow()
    if not window then Build() end
    return window
end
function TC.EnterSocial()
    TC.GetMainWindow()
    if window.activePage~="social" then window.previousPage=window.activePage end
    window.activePage="social"
    window.requestPage:Hide(); window.new:Hide(); window.sync:Hide(); window.funButton:Hide()
    for _,page in pairs(window.guildPages) do page:Hide() end
    for _,tab in pairs(window.pageTabs) do tab:Hide() end
    window.status:SetText("")
    window.socialHost:Show(); window.back:Show(); window:Show()
    if TC.LayoutSocial then TC.LayoutSocial() end
end

function TC.StartMinimapButton()
    if not Minimap then return end

    local button = CreateFrame("Button", nil, Minimap)
    button:SetSize(31, 31)
    button:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 19, 19)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(22, 22)
    background:SetPoint("CENTER")

    local mark = button:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    mark:SetPoint("CENTER")
    mark:SetText("C")
    mark:SetTextColor(0.47, 0.84, 0.68)

    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        GameTooltip:Hide()
        SlashCmdList.THECOMMUNE("")
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("The Commune")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

SLASH_THECOMMUNE1 = "/commune"
SLASH_THECOMMUNE2 = "/thecommune"
SlashCmdList.THECOMMUNE = function(command)
    if not TC.store then TC.Print("Please wait until your character has finished logging in."); return end
    TC.RefreshGuildMembership()
    command = (command or ""):match("^%s*(.-)%s*$"):lower()
    if not TC.guildKey and command~="" and command~="resize" and command~="debug" then TC.GetMainWindow():Show(); TC.Refresh(); return end
    if command=="quiz" or command=="wordle" or command=="credits" or command=="hitlist" or command=="scores" or command=="pvp" or command=="aim" then TC.OpenSocial(command); return end
    if command == "sync" then TC.Query(true); return end
    if command == "debug" then
        if TC.ShowReport then TC.ShowReport("The Commune - sync debug",TC.DebugSync) else TC.DebugSync() end
        return
    end
    if command == "craftsdebug" then
        TC.ScanProfessions()
        if TC.ShowReport then TC.ShowReport("The Commune - crafts debug",TC.DebugCrafts) else TC.DebugCrafts() end
        return
    end
    if command == "summary" then TC.ShowSummary(); return end
    if command=="crafts" or command=="projects" or command=="requests" or command=="deaths" then
        if not window then Build() end
        window:Show(); TC.ShowPage(command); return
    end
    if command == "resize" then
        if not window then Build() end
        resizeEnabled = not resizeEnabled
        StopSizing(); window:SetResizable(resizeEnabled); window.grip:SetShown(resizeEnabled); window:Show()
        TC.Print(resizeEnabled and "Resizing unlocked. Drag the bottom-right corner; /commune resize locks it again." or "Window size locked and saved.")
        return
    end
    if not window then Build(); window:Show() else window:SetShown(not window:IsShown()) end
end
