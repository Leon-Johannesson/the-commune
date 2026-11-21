local _,TC=...
local seeds={[2770]="Copper Ore",[2771]="Tin Ore",[2772]="Iron Ore",[2775]="Silver Ore",[2776]="Gold Ore",[3858]="Mithril Ore",[10620]="Thorium Ore", [2840]="Copper Bar",[3576]="Tin Bar",[2841]="Bronze Bar",[3575]="Iron Bar",[2589]="Linen Cloth",[2592]="Wool Cloth",[4306]="Silk Cloth",[4338]="Mageweave Cloth",[14047]="Runecloth"}
local seedIDs={2318,2319,4234,4304,8170,2447,765,2449,785,2450,2452,2453,3355,3356,3357,3818,3821,3358,8838,8839,8845,8846,13463,13465,13466,13467,13468,2672,2673,5956,3860,12359,2842,3577,6037}
local function Normalize(text) return (text or ""):match("^%s*(.-)%s*$"):gsub("%s+"," "):lower() end
function TC.LearnItem(id)
    if not TC.db or not TC.Integer(id,1,2147483647) then return end
    TC.db.itemIndex=TC.db.itemIndex or {}
    local name=C_Item.GetItemInfo(id)
    if name then TC.db.itemIndex[id]=name
    elseif C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end
function TC.InitItemSearch()
    TC.db.itemIndex=TC.db.itemIndex or {}
    for id,name in pairs(seeds) do
        if not TC.db.itemIndex[id] then TC.db.itemIndex[id]=name end
        TC.LearnItem(id)
    end
    for _,id in ipairs(seedIDs) do TC.LearnItem(id) end
    TC.ScanBagItems()
end
function TC.ScanBagItems()
    if not TC.db then return end
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bag=0,(NUM_BAG_SLOTS or 4) do
            for slot=1,C_Container.GetContainerNumSlots(bag) do
                local info=C_Container.GetContainerItemInfo(bag,slot)
                if info and info.itemID then TC.LearnItem(info.itemID) end
            end
        end
    end
    if TC.store then
        for _,slots in pairs(TC.store.owners) do for _,r in pairs(slots) do if not r.deleted then TC.LearnItem(r.item) end end end
    end
end
function TC.SearchItems(query,limit)
    local results={}; query=Normalize(query)
    if query=="" or not TC.db then return results end
    for id,name in pairs(TC.db.itemIndex or {}) do
        local normalized=Normalize(name)
        if normalized:find(query,1,true) then
            results[#results+1]={id=id,name=name,score=normalized==query and 0 or (normalized:sub(1,#query)==query and 1 or 2)}
        end
    end
    table.sort(results,function(a,b) if a.score~=b.score then return a.score<b.score end
        if a.name==b.name then return a.id<b.id end; return a.name<b.name end)
    while #results>(limit or 6) do table.remove(results) end
    return results
end
function TC.ResolveItem(text)
    text=(text or ""):match("^%s*(.-)%s*$")
    local id=tonumber(text:match("item[:=](%d+)")) or TC.Integer(text,1,2147483647)
    if id then TC.LearnItem(id); return id end
    local normalized=Normalize(text)
    if normalized=="" then return end
    local matches={}
    for item,name in pairs(TC.db and TC.db.itemIndex or {}) do if Normalize(name)==normalized then matches[#matches+1]=item end end
    if #matches==1 then return matches[1] elseif #matches>1 then return end
    local name,link=C_Item.GetItemInfo(text)
    if name and Normalize(name)==normalized and type(link)=="string" then
        id=tonumber(link:match("item:(%d+)")); if id then TC.LearnItem(id); return id end
    end
end
function TC.AttachItemSearch(box,parent,onChange)
    local popup=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetSize(330,160)
    popup:SetPoint("TOPLEFT",box,"BOTTOMLEFT",-5,-3)
    popup:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10})
    popup:SetBackdropColor(0.035,0.06,0.055,0.94); popup:Hide()
    local buttons={}
    for i=1,6 do
        local b=CreateFrame("Button",nil,popup); b:SetSize(314,24); b:SetPoint("TOPLEFT",8,-8-(i-1)*24)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetSize(20,20); b.icon:SetPoint("LEFT",2,0)
        b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); b.text:SetPoint("LEFT",28,0); b.text:SetWidth(280); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick",function(self)
            box:SetText(self.entry.name); onChange(self.entry.id); popup:Hide(); box:ClearFocus()
        end); buttons[i]=b
    end
    local function Changed()
        onChange(TC.ResolveItem(box:GetText()))
        local data=TC.SearchItems(box:GetText(),6)
        if not box:HasFocus() or not box:IsEnabled() or tonumber(box:GetText()) or box:GetText():find("item[:=]%d+") or #data==0 then popup:Hide(); return end
        popup:SetWidth(math.max(260,math.min(420,box:GetWidth()+5))); popup:SetHeight(#data*24+16)
        for i,b in ipairs(buttons) do
            local entry=data[i]; b.entry=entry
            if entry then
                local _,_,icon=TC.ItemName(entry.id); b.icon:SetTexture(icon or 134400)
                b:SetWidth(popup:GetWidth()-16); b.text:SetWidth(popup:GetWidth()-52)
                b.text:SetText(entry.name.."  ["..entry.id.."]"); b:Show()
            else b:Hide() end
        end
        popup:Show()
    end
    box:SetScript("OnTextChanged",Changed); box:SetScript("OnEditFocusGained",Changed)
    box:SetScript("OnEditFocusLost",function() C_Timer.After(0.2,function() popup:Hide() end) end)
    box:SetScript("OnHide",function() popup:Hide() end)
    return popup
end
local frame=CreateFrame("Frame")
frame:RegisterEvent("BAG_UPDATE_DELAYED"); frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent",function(_,event,id,success)
    if not TC.db then return end
    if event=="BAG_UPDATE_DELAYED" then TC.ScanBagItems()
    elseif success then
        local name=C_Item.GetItemInfo(id); if name then TC.db.itemIndex=TC.db.itemIndex or {}; TC.db.itemIndex[id]=name end
    end
end)

