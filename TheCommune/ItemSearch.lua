local _,TC=...
local seeds={[2770]="Copper Ore",[2771]="Tin Ore",[2772]="Iron Ore",[2775]="Silver Ore",[2776]="Gold Ore",[3858]="Mithril Ore",[10620]="Thorium Ore", [2840]="Copper Bar",[3576]="Tin Bar",[2841]="Bronze Bar",[3575]="Iron Bar",[2589]="Linen Cloth",[2592]="Wool Cloth",[4306]="Silk Cloth",[4338]="Mageweave Cloth",[14047]="Runecloth"}
local seedIDs={2318,2319,4234,4304,8170,2447,765,2449,785,2450,2452,2453,3355,3356,3357,3818,3821,3358,8838,8839,8845,8846,13463,13465,13466,13467,13468,2672,2673,5956,3860,12359,2842,3577,6037}
local function Normalize(text) return (text or ""):match("^%s*(.-)%s*$"):gsub("%s+"," "):lower() end

local normalized, exactNames = {}, {}

local function IndexName(id, name)
    local previous = normalized[id]
    local key = Normalize(name)
    if key == previous then return end
    if previous then
        local old = exactNames[previous]
        old[id] = nil
        if not next(old) then exactNames[previous] = nil end
    end
    local matches = exactNames[key] or {}
    matches[id] = true
    exactNames[key], normalized[id] = matches, key
end

local function StoreName(id, name)
    local index = TC.db.itemIndex
    if index[id] ~= name then
        index[id] = name
        IndexName(id, name)
    end
end
function TC.LearnItem(id)
    if not TC.db or id==TC.GOLD or not TC.Integer(id,1,2147483647) then return end
    TC.db.itemIndex=TC.db.itemIndex or {}
    local name=C_Item.GetItemInfo(id)
    if name then StoreName(id,name)
    elseif C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end
function TC.InitItemSearch()
    TC.db.itemIndex=TC.db.itemIndex or {}
    normalized, exactNames = {}, {}
    for id,name in pairs(TC.db.itemIndex) do IndexName(id,name) end
    for id,name in pairs(seeds) do
        if not TC.db.itemIndex[id] then StoreName(id,name) end
        TC.LearnItem(id)
    end
    for _,id in ipairs(seedIDs) do TC.LearnItem(id) end
    TC.ScanBagItems()
    if TC.store then
        for _,slots in pairs(TC.store.owners) do
            for _,r in pairs(slots) do
                if not r.deleted and not TC.db.itemIndex[r.item] then TC.LearnItem(r.item) end
            end
        end
    end
end

function TC.ScanBagItems()
    if not TC.db then return end
    local index = TC.db.itemIndex
    local seen = {}
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bag=0,(NUM_BAG_SLOTS or 4) do
            for slot=1,C_Container.GetContainerNumSlots(bag) do
                local info=C_Container.GetContainerItemInfo(bag,slot)
                local id = info and info.itemID
                if id and not index[id] and not seen[id] then
                    seen[id] = true
                    TC.LearnItem(id)
                end
            end
        end
    end
end

local function Safe(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
function TC.ScanAuctionItems()
    if not TC.db then return end
    local api=C_AuctionHouse
    local results=api and Safe(api.GetBrowseResults)
    if type(results)=="table" and not (issecrettable and issecrettable(results)) then
        for i=1,math.min(#results,500) do
            local key=Safe(function() return results[i].itemKey end)
            local id=type(key)=="table" and Safe(function() return key.itemID end)
            id=TC.Integer(id,1,2147483647)
            if id then
                local info=Safe(api.GetItemKeyInfo,key)
                local name=type(info)=="table" and Safe(function() return info.itemName end)
                if type(name)=="string" and name~="" then
                    TC.db.itemIndex=TC.db.itemIndex or {}; StoreName(id,name)
                end
                TC.LearnItem(id)
            end
        end
    end
    local count=Safe(GetNumAuctionItems,"list")
    if type(count)=="number" then
        for i=1,math.min(count,500) do
            local link=Safe(GetAuctionItemLink,"list",i)
            local id=type(link)=="string" and TC.Integer(link:match("item:(%d+)"),1,2147483647)
            if id then TC.LearnItem(id) end
        end
    end
end

local function ComesBefore(score, name, id, other)
    if score~=other.score then return score<other.score end
    if name~=other.name then return name<other.name end
    return id<other.id
end

function TC.SearchItems(query,limit)
    local results={}; query=Normalize(query); limit=math.floor(limit or 6)
    if query=="" or not TC.db or limit<1 then return results end
    for id,value in pairs(normalized) do
        local start=value:find(query,1,true)
        if start then
            local name=TC.db.itemIndex[id]
            local score=value==query and 0 or (start==1 and 1 or 2)
            if #results<limit or ComesBefore(score,name,id,results[limit]) then
                local position=math.min(#results+1,limit)
                while position>1 and ComesBefore(score,name,id,results[position-1]) do
                    results[position]=results[position-1]
                    position=position-1
                end
                results[position]={id=id,name=name,score=score}
            end
        end
    end
    return results
end
function TC.ResolveItem(text)
    text=(text or ""):match("^%s*(.-)%s*$")
    -- "gold" names the sentinel so a money request needs no second input.
    if text:lower()=="gold" or text:lower()=="g" then return TC.GOLD end
    local id=tonumber(text:match("item[:=](%d+)")) or TC.Integer(text,1,2147483647)
    if id then TC.LearnItem(id); return id end
    local normalized=Normalize(text)
    if normalized=="" then return end
    local matches=exactNames[normalized]
    if matches then
        local id=next(matches)
        if not next(matches,id) then return id end
        return
    end
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
        local text=box:GetText()
        local item=TC.ResolveItem(text)
        onChange(item)
        if not box:HasFocus() or not box:IsEnabled() or item==TC.GOLD or tonumber(text) or text:find("item[:=]%d+") then
            popup:Hide(); return
        end
        local data=TC.SearchItems(text,6)
        if #data==0 then popup:Hide(); return end
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
    TC.RefreshItemSearch=Changed
    box:SetScript("OnTextChanged",Changed)
    box:SetScript("OnEditFocusGained",function() TC.ScanAuctionItems(); Changed() end)
    box:SetScript("OnEditFocusLost",function() C_Timer.After(0.2,function() popup:Hide() end) end)
    box:SetScript("OnHide",function() popup:Hide() end)
    return popup
end
local frame=CreateFrame("Frame")
frame:RegisterEvent("BAG_UPDATE_DELAYED"); frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
for _,event in ipairs({"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED","AUCTION_HOUSE_BROWSE_RESULTS_ADDED","AUCTION_HOUSE_ITEM_SEARCH_RESULTS_UPDATED","AUCTION_ITEM_LIST_UPDATE"}) do
    pcall(frame.RegisterEvent,frame,event)
end
frame:SetScript("OnEvent",function(_,event,id,success)
    if not TC.db then return end
    if event=="BAG_UPDATE_DELAYED" then TC.ScanBagItems()
    elseif event=="GET_ITEM_INFO_RECEIVED" and success then
        local name=C_Item.GetItemInfo(id)
        if name then TC.db.itemIndex=TC.db.itemIndex or {}; StoreName(id,name) end
    elseif event~="GET_ITEM_INFO_RECEIVED" then TC.ScanAuctionItems() end
    if TC.RefreshItemSearch then TC.RefreshItemSearch() end
end)

