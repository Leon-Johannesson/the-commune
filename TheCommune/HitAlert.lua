local _, TC = ...
local alert, targets
local sightings, dismissed = {}, {}
local store
local offset, dragging = 0, false
local rowLimit, rowHeight, width = 7, 25, 370

local function Safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if ok and not (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return a, b end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

function TC.HitUnitMatch(unit)
    if not TC.guildKey or not TC.store or not TC.store.social or not unit or Safe(UnitIsPlayer, unit) ~= true then return end
    local faction, own = Safe(UnitFactionGroup, unit), Safe(UnitFactionGroup, "player")
    if (faction ~= "Horde" and faction ~= "Alliance") or (own ~= "Horde" and own ~= "Alliance") or faction == own then return end
    local first, last = Safe(UnitFullName, unit)
    if type(first) ~= "string" then return end
    local full = first .. (last and last ~= "" and "-" .. last or "")
    local key = TC.PlayerKey(full)
    if not key then return end
    for _, slots in pairs(TC.store.social.hits) do
        for _, entry in pairs(slots) do
            if not entry.deleted and entry.target == key and entry.faction == faction then
                return entry, key, TC.NormalizeName(full):gsub("-", " ")
            end
        end
    end
end

-- Several guildmates can list the same enemy, each with their own note.
function TC.HitNotes(key)
    local notes = {}
    if not key or not TC.store or not TC.store.social then return notes end
    for owner, slots in pairs(TC.store.social.hits) do
        for _, entry in pairs(slots) do
            if not entry.deleted and entry.target == key then
                local reason = entry.reason
                if type(reason) ~= "string" or reason == "" then reason = "No reason given" end
                notes[#notes + 1] = reason .. " - " .. TC.DisplayName(owner)
            end
        end
    end
    table.sort(notes)
    return notes
end

function TC.AddHitTooltip(tooltip, data)
    if tooltip ~= GameTooltip then return end
    local _, unit = Safe(tooltip.GetUnit, tooltip)
    if not unit and data then
        local guid = Safe(function() return data.guid end)
        if guid and guid == Safe(UnitGUID, "mouseover") then unit = "mouseover" end
    end
    local entry, key = TC.HitUnitMatch(unit)
    if entry then
        tooltip:AddLine("On your guild's Hitlist", 1, 0.36, 0.33)
        for _, note in ipairs(TC.HitNotes(key)) do tooltip:AddLine(note, 1, 0.82, 0, true) end
    end
end

local function SetClassIcon(icon, token)
    local coords = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if coords then
        icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        -- The client does not always expose a class for a passing nameplate.
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
end

local function RowTooltip(row)
    local sighting = row.sighting
    if not sighting or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(sighting.name, 1, 0.82, 0)
    GameTooltip:AddLine(sighting.class .. "  |  Level " .. sighting.level, 1, 1, 1)
    for _, note in ipairs(TC.HitNotes(sighting.key)) do GameTooltip:AddLine(note, 1, 0.36, 0.33, true) end
    GameTooltip:AddLine(InCombat() and "Targeting resumes after combat" or "Click to target", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function FindUnit(sighting)
    if not sighting or store ~= TC.store then return end
    local function Matches(unit)
        local _, key = TC.HitUnitMatch(unit)
        return key == sighting.key and (not sighting.guid or Safe(UnitGUID, unit) == sighting.guid)
    end
    for _, unit in ipairs({"target", "focus", "mouseover", sighting.unit or "target"}) do
        if Matches(unit) then return unit end
    end
    local plates = C_NamePlate and Safe(C_NamePlate.GetNamePlates)
    if type(plates) == "table" and not (issecrettable and issecrettable(plates)) then
        for _, plate in ipairs(plates) do
            local unit = Safe(function() return plate.namePlateUnitToken end)
            if unit and Matches(unit) then return unit end
        end
    end
end

local function PositionTargets()
    if not targets or InCombat() then return end
    local left, top = alert:GetLeft(), alert:GetTop()
    if not alert:IsShown() or dragging or not left or not top then targets:Hide(); return end
    targets:SetFrameLevel(alert:GetFrameLevel() + 5)
    targets:ClearAllPoints()
    targets:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + 12, top - 32)
    targets:Show()
end

local function BuildTargets()
    if targets or InCombat() or not RegisterStateDriver then return end
    -- Keep secure buttons independent of the alert so combat cannot lock its geometry.
    targets = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    targets:SetFrameStrata("HIGH"); targets:SetFrameLevel(alert:GetFrameLevel() + 5)
    targets:SetSize(width - 24, rowLimit * rowHeight)
    targets:EnableMouseWheel(true)
    targets:SetScript("OnMouseWheel", alert:GetScript("OnMouseWheel"))
    targets:SetAttribute("_onstate-combat", [[
        if newstate == "locked" then self:Hide() end
    ]])
    RegisterStateDriver(targets, "combat", "[combat] locked; open")
    targets.rows = {}
    for i = 1, rowLimit do
        local row = CreateFrame("Button", nil, targets, "SecureActionButtonTemplate")
        row:SetSize(width - 24, rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        -- SecureActionButton otherwise follows ActionButtonUseKeyDown, which
        -- can ignore the only release edge the old button registered.
        row:SetAttribute("useOnKeyDown", false)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", alert:GetScript("OnMouseWheel"))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row:SetScript("OnEnter", RowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("PreClick", function(self)
            if InCombat() then return end
            local sighting = self.sighting
            local unit, name
            if sighting and store == TC.store and GetTime() - sighting.seen <= 6 and
                not Safe(SpellIsTargeting) and not Safe(CursorHasItem) then
                unit = FindUnit(sighting)
                -- Hovering this button removes the original world mouseover.
                -- An exact-name action can still select that recently seen
                -- player without a live nameplate token. Never insert commands.
                if not unit and type(sighting.name) == "string" and not sighting.name:find("[%c|]") then
                    name = TC.Clean(sighting.name, 100)
                    if name == "" then name = nil end
                end
            end
            self:SetAttribute("type", nil)
            self:SetAttribute("unit", nil)
            self:SetAttribute("macrotext", nil)
            self:SetAttribute("unit1", unit)
            self:SetAttribute("macrotext1", name and ("/targetexact [nocombat] " .. name) or nil)
            self:SetAttribute("type1", unit and "target" or name and "macro" or nil)
        end)
        targets.rows[i] = row
    end
end

local function Build()
    alert = CreateFrame("Frame", "TheCommuneHitAlert", UIParent, "BackdropTemplate")
    alert:SetSize(width, 70); alert:SetPoint("TOP", UIParent, "TOP", 0, -100)
    alert:SetFrameStrata("HIGH")
    alert:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12})
    TC.StyleWindow(alert)
    TC.RememberWindow(alert, "hitAlert", nil, true)
    alert:HookScript("OnMouseDown", PositionTargets)
    alert:HookScript("OnDragStart", function() dragging=true; PositionTargets() end)
    alert:HookScript("OnDragStop", function() dragging=false; PositionTargets() end)
    alert:HookScript("OnHide", function() dragging=false; PositionTargets() end)
    local title = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 12, -12); title:SetText("Hitlist nearby")
    local close = CreateFrame("Button", nil, alert, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function()
        for key in pairs(sightings) do dismissed[key] = true end
        alert:Hide()
    end)
    alert:EnableMouseWheel(true)
    alert:SetScript("OnMouseWheel", function(_, delta) offset=math.max(0,offset-delta); TC.RefreshHitAlert() end)
    alert.rows, alert.icons = {}, {}
    for i = 1, rowLimit do
        local icon = alert:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 14, -36 - (i - 1) * rowHeight)
        alert.icons[i] = icon
        local line = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", 37, -38 - (i - 1) * rowHeight)
        line:SetWidth(width - 52); line:SetJustifyH("LEFT"); line:SetWordWrap(false)
        alert.rows[i] = line
    end
    alert.status = alert:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    alert.status:SetPoint("BOTTOMLEFT", 15, 9)
end

function TC.RefreshHitAlert()
    if store ~= TC.store or not TC.guildKey then
        sightings, dismissed, offset, store = {}, {}, 0, TC.store
    end
    local rows, now = {}, GetTime()
    for key, sighting in pairs(sightings) do
        if now - sighting.seen > 6 then sightings[key], dismissed[key] = nil, nil
        elseif not dismissed[key] then rows[#rows+1] = sighting end
    end
    if #rows == 0 then if alert then alert:Hide(); PositionTargets() end; return end
    if not alert then Build() end
    BuildTargets()
    table.sort(rows, function(a,b) return a.key < b.key end)
    offset = math.min(offset, math.max(0, #rows - rowLimit))
    for i,line in ipairs(alert.rows) do
        local sighting = rows[offset+i]
        line:SetShown(sighting ~= nil)
        alert.icons[i]:SetShown(sighting ~= nil)
        if sighting then
            line:SetText(sighting.name .. "  |  " .. sighting.class .. "  |  Lv " .. sighting.level)
            SetClassIcon(alert.icons[i], sighting.token)
        end
        if targets and not InCombat() then
            targets.rows[i].sighting = sighting
            -- A scrolled/reused row must not retain a different enemy's action.
            targets.rows[i]:SetAttribute("type1", nil)
            targets.rows[i]:SetAttribute("unit1", nil)
            targets.rows[i]:SetAttribute("macrotext1", nil)
            targets.rows[i]:SetShown(sighting ~= nil)
        end
    end
    local status = InCombat() and "Targeting resumes after combat" or
        (targets and "Click a visible player to target" or "Click targeting unavailable")
    alert.status:SetText(status .. (#rows > rowLimit and "  ·  Scroll for more" or ""))
    alert:SetHeight(57 + math.min(#rows, rowLimit) * rowHeight)
    alert:Show(); PositionTargets()
end

function TC.ShowHitAlert(name, _, unit, key)
    if not TC.guildKey then return end
    if store ~= TC.store then sightings, dismissed, offset, store = {}, {}, 0, TC.store end
    key = key or TC.PlayerKey(name)
    if not key then return end
    local class, token, level, guid
    -- UnitClass returns the localized name and the class file token; the token
    -- is what indexes the class icon atlas, so keep both.
    if unit then
        class, token = Safe(UnitClass, unit)
        level, guid = Safe(UnitLevel, unit), Safe(UnitGUID, unit)
    end
    sightings[key] = {key=key, name=name, unit=unit, guid=guid, seen=GetTime(),
        token=type(token)=="string" and token or nil,
        class=class or "Unknown class", level=type(level)=="number" and level>0 and tostring(level) or "?"}
    TC.RefreshHitAlert()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_,event)
    if alert and (event=="PLAYER_REGEN_DISABLED" or event=="PLAYER_REGEN_ENABLED") then TC.RefreshHitAlert() end
end)
