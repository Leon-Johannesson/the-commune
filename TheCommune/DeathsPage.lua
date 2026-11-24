local _, TC = ...
local panel, page, mainWindow
local panelStore, panelZone, dismissedZone
local panelOffset, pageOffset = 0, 0
local panelLimit = 5

local function Label(parent, text, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetText(text); label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    label:SetTextColor(0.82, 0.77, 0.66)
    return label
end

local function Summary(rows, total)
    return #rows .. " guildmate" .. (#rows == 1 and "" or "s") .. "  |  " .. total .. " recorded death" .. (total == 1 and "" or "s")
end

local function PlayerLabel(row)
    return row.name .. (row.owner == TC.owner and " (you)" or "")
end

local function RowTooltip(self)
    if not self.entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(PlayerLabel(self.entry))
    GameTooltip:AddLine(self.entry.count .. " recorded deaths in " .. self.zone, 0.82, 0.77, 0.66, true)
    GameTooltip:AddLine("PvE: " .. self.entry.pve .. "  |  PvP: " .. self.entry.pvp, 0.82, 0.77, 0.66)
    GameTooltip:AddLine("Unknown: " .. self.entry.unknown .. " (older or unreadable causes)", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function Row(parent, index, onScroll)
    local row = CreateFrame("Frame", nil, parent)
    local background = row:CreateTexture(nil, "BACKGROUND"); background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.035 or 0)
    row.name = Label(row, "")
    row.count = Label(row, "")
    row.count:SetJustifyH("RIGHT")
    for _, key in ipairs({"pve", "pvp", "unknown"}) do
        row[key] = Label(row, ""); row[key]:SetJustifyH("RIGHT")
    end
    row.pve:SetTextColor(0.58, 0.76, 0.86)
    row.pvp:SetTextColor(0.88, 0.62, 0.58)
    row.unknown:SetTextColor(0.6, 0.6, 0.6)
    row:EnableMouse(true); row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", onScroll)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Fill(rows, widgets, visible, offset, zone)
    offset = math.max(0, math.min(offset, math.max(0, #rows - visible)))
    for i, widget in ipairs(widgets) do
        local entry = i <= visible and rows[offset + i] or nil
        widget.entry, widget.zone = entry, zone
        widget:SetShown(entry ~= nil)
        if entry then
            widget.name:SetText(PlayerLabel(entry))
            widget.count:SetText(entry.count)
            for _,key in ipairs({"pve","pvp","unknown"}) do
                local value=entry[key]
                local text=widget.compact and value>=1000000 and (math.floor(value/1000000).."m") or
                    widget.compact and value>=10000 and (math.floor(value/1000).."k") or value
                widget[key]:SetText(text)
            end
        end
    end
    return offset
end

local function BuildPanel()
    panel = CreateFrame("Frame", "TheCommuneZoneDeaths", UIParent, "BackdropTemplate")
    panel:SetSize(282, 110)
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -300)
    panel:SetFrameStrata("MEDIUM")
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12})
    TC.StyleWindow(panel)
    TC.RememberWindow(panel, "zoneDeaths", nil, true)
    panel.title = Label(panel, "")
    panel.title:SetPoint("TOPLEFT", 12, -12); panel.title:SetWidth(236)
    panel.title:SetTextColor(0.65, 0.72, 0.67)
    panel.hint = Label(panel, "", "GameFontDisableSmall")
    panel.hint:SetPoint("BOTTOMLEFT", 12, 10); panel.hint:SetWidth(258)
    for i, title in ipairs({"PvE", "PvP", "?"}) do
        local header=Label(panel,title,"GameFontDisableSmall")
        header:SetPoint("TOPLEFT",150+(i-1)*40,-32); header:SetWidth(36); header:SetJustifyH("RIGHT")
    end
    panel.rows = {}
    local function Scroll(_, delta)
        panelOffset = panelOffset - delta
        TC.RefreshZoneDeaths()
    end
    panel:EnableMouseWheel(true); panel:SetScript("OnMouseWheel", Scroll)
    for i = 1, panelLimit do
        local row = Row(panel, i, Scroll)
        row.compact=true
        row:SetPoint("TOPLEFT", 12, -49 - (i - 1) * 20); row:SetSize(258, 20)
        row.name:SetPoint("TOPLEFT", 3, -3); row.name:SetWidth(130)
        row.count:Hide()
        for column,key in ipairs({"pve","pvp","unknown"}) do
            row[key]:SetPoint("TOPLEFT",138+(column-1)*40,-3); row[key]:SetWidth(36)
        end
        panel.rows[i] = row
    end
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        dismissedZone = panelZone
        panel:Hide(); GameTooltip:Hide()
    end)
    close:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hide until you change zones")
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.close = close
end

function TC.RefreshZoneDeaths()
    if not TC.db or not TC.guildKey or not TC.store then
        if panel then panel:Hide() end
        return
    end
    local rows, total, key, name = TC.ZoneDeathRows()
    if panelStore ~= TC.store or panelZone ~= key then
        panelStore, panelZone, dismissedZone, panelOffset, pageOffset = TC.store, key, nil, 0, 0
    end
    if page and mainWindow:IsShown() and mainWindow.activePage == "deaths" then
        page.title:SetText(name)
        page.summary:SetText(Summary(rows, total))
        pageOffset = Fill(rows, page.rows, page.visible, pageOffset, name)
        page.scrollBar.Refresh(#rows, page.visible, pageOffset)
        page.empty:SetShown(#rows == 0)
        page.showPanel:SetChecked(TC.db.zoneDeathPanel ~= false)
    end
    if TC.db.zoneDeathPanel == false or dismissedZone == key or #rows == 0 or key == "unknown" then
        if panel then panel:Hide() end
        return
    end
    if not panel then BuildPanel() end
    panel.title:SetText("Deaths  |  " .. name)
    panelOffset = Fill(rows, panel.rows, panelLimit, panelOffset, name)
    local visible = math.min(panelLimit, #rows)
    panel:SetHeight(77 + visible * 20)
    panel.hint:SetText(#rows > panelLimit and
        ((panelOffset + 1) .. "-" .. (panelOffset + visible) .. " of " .. #rows .. " guildmates  |  Scroll") or
        (total .. " recorded death" .. (total == 1 and "" or "s")))
    panel:Show()
end

function TC.BuildDeathsPage(window, H)
    mainWindow = window
    page = CreateFrame("Frame", nil, window); page:SetAllPoints(window); page:Hide()
    page.rows = {}; page.visible = 1
    page.title = H.Label(page, "", 0, 0)
    page.title:SetFontObject("GameFontHighlightLarge")
    page.summary = H.Label(page, "", 0, 0)
    page.summary:SetFontObject("GameFontHighlightSmall")
    page.headers = {H.Label(page, "GUILD MEMBER", 0, 0)}
    for _,title in ipairs({"PvE","PvP","UNKNOWN","TOTAL"}) do
        local header=H.Label(page,title,0,0); header:SetJustifyH("RIGHT")
        page.headers[#page.headers+1]=header
    end
    page.empty = H.Label(page, "No shared deaths recorded in this zone yet.", 0, 0)
    page.empty:SetFontObject("GameFontDisableSmall")
    page.note = H.Label(page, "PvE/PvP tracked since v0.4.39. Unknown includes older or unreadable causes.", 0, 0)
    page.note:SetFontObject("GameFontDisableSmall")
    page.showPanel = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.panelLabel = H.Label(page, "Show zone panel while playing", 0, 0)
    page.showPanel:SetScript("OnClick", function(self)
        TC.db.zoneDeathPanel = not not self:GetChecked()
        dismissedZone = nil
        TC.RefreshZoneDeaths()
    end)
    page.Update = TC.RefreshZoneDeaths
    local function Scroll(_, delta)
        pageOffset = pageOffset - delta * 3
        TC.RefreshZoneDeaths()
    end
    page:EnableMouseWheel(true); page:SetScript("OnMouseWheel", Scroll)
    page.scrollBar = TC.AttachScrollBar(page, function(value)
        pageOffset = value; TC.RefreshZoneDeaths()
    end)
    function page.Layout()
        local width, height = window:GetWidth(), window:GetHeight()
        local content = width - 48
        H.Place(page.title, 24, -114, content, 24)
        H.Place(page.summary, 24, -146, content, 18)
        local rowWidth = content - 18
        local numberX = rowWidth - 320
        H.Place(page.headers[1], 32, -182, numberX - 16, 18)
        for column=1,4 do H.Place(page.headers[column+1],24+numberX+(column-1)*80,-182,72,18) end
        page.visible = math.max(1, math.floor((height - 292) / 30))
        for i = 1, page.visible do
            if not page.rows[i] then page.rows[i] = Row(page, i, Scroll) end
            local row = page.rows[i]
            H.Place(row, 24, -206 - (i - 1) * 30, rowWidth, 30)
            H.Place(row.name, 8, -8, numberX - 16, 18)
            for column,key in ipairs({"pve","pvp","unknown","count"}) do
                H.Place(row[key],numberX+(column-1)*80,-8,72,18)
            end
        end
        H.Place(page.scrollBar, width - 36, -206, 12, page.visible * 30 - 4)
        H.Place(page.empty, 32, -220, content - 16, 20)
        H.Place(page.showPanel, 24, -height + 70, 26, 26)
        H.Place(page.panelLabel, 56, -height + 77, content - 32, 18)
        H.Place(page.note, 28, -height + 34, content - 8, 18)
    end
    window.guildPages.deaths = page
end

local queued
local events = CreateFrame("Frame")
for _, event in ipairs({"ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function() queued = false; TC.RefreshZoneDeaths() end)
end)
