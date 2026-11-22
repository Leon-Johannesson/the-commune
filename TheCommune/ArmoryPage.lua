local _,TC=...
local leftColumn={1,2,3,15,5,4,19,9,10}
local rightColumn={6,7,8,11,12,13,14,16,17}

-- Dim neutral frame for an empty slot or an item the client has not cached yet.
local emptyR,emptyG,emptyB=0.28,0.27,0.25

local function QualityColor(quality)
    if type(quality)~="number" or quality<0 then return emptyR,emptyG,emptyB end
    local fn=GetItemQualityColor or (C_Item and C_Item.GetItemQualityColor)
    if type(fn)~="function" then return emptyR,emptyG,emptyB end
    local ok,r,g,b=pcall(fn,quality)
    if not ok or type(r)~="number" or type(g)~="number" or type(b)~="number" then return emptyR,emptyG,emptyB end
    return r,g,b
end

local function Ago(when)
    if type(when)~="number" then return "unknown" end
    local seconds=math.max(0,time()-when)
    if seconds<90 then return "just now" end
    if seconds<5400 then return math.floor(seconds/60).." min ago" end
    if seconds<172800 then return math.floor(seconds/3600).." h ago" end
    return math.floor(seconds/86400).." days ago"
end

function TC.BuildArmoryPage(window,H)
    local Button,Label=H.Button,H.Label
    local function Place(widget,x,y,width,height) H.Place(widget,x,-y,width,height) end
    local a=CreateFrame("Frame",nil,window); a:SetAllPoints(window); a:Hide(); a.offset=0

    a.sync=Button(a,"Sync armory",function()
        if not TC.Query(true) then TC.BroadcastGear(true) end
        a.message:SetText("Armory sync queued. Guildmates answer over the next few seconds.")
    end)
    a.rows={}
    for i=1,9 do a.rows[i]=Button(a,"",function(self) a.selected=self.owner; a.Update() end) end
    a:EnableMouseWheel(true)
    a:SetScript("OnMouseWheel",function(_,delta) a.offset=math.max(0,a.offset-delta); a.Update() end)

    a.title=Label(a,"",0,0,400)
    a.title:SetFontObject("GameFontHighlightLarge")
    a.subtitle=Label(a,"",0,0,400)
    a.subtitle:SetFontObject("GameFontHighlightSmall")
    a.message=Label(a,"",0,0,400)
    a.message:SetFontObject("GameFontDisableSmall")

    a.slots={}
    for index,slot in ipairs(leftColumn) do a.slots[index]={slot=slot} end
    for index,slot in ipairs(rightColumn) do a.slots[#leftColumn+index]={slot=slot} end
    for _,entry in ipairs(a.slots) do
        local b=CreateFrame("Button",nil,a,"BackdropTemplate")
        b:SetSize(32,32)
        -- The icon covers the button, so the rarity colour reads as a frame
        -- around it rather than a backdrop behind it.
        b.quality=b:CreateTexture(nil,"BACKGROUND")
        b.quality:SetPoint("TOPLEFT",-3,3); b.quality:SetPoint("BOTTOMRIGHT",3,-3)
        b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetAllPoints()
        b:SetScript("OnEnter",function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            if self.link then GameTooltip:SetHyperlink(self.link)
            else GameTooltip:SetText(TC.GearSlotName(self.slotID),1,0.82,0); GameTooltip:AddLine("Nothing equipped",0.6,0.6,0.6) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        entry.button=b
        entry.label=Label(a,"",0,0,200)
        entry.label:SetFontObject("GameFontHighlightSmall")
    end

    function a.Update()
        local rows=TC.GearRows()
        local store=TC.GearStore() or {}
        local visible=a.visible or 9
        a.offset=math.min(a.offset,math.max(0,#rows-visible))
        local roster, own=TC.GearRoster()
        if a.selected and not store[a.selected] then a.selected=nil end
        if not a.selected and rows[1] then a.selected=rows[1].owner end
        for i,b in ipairs(a.rows) do
            local entry=i<=visible and rows[a.offset+i]; b.owner=entry and entry.owner
            if entry then
                local who=entry.owner==TC.owner and own or roster[entry.owner] or {}
                b:SetText((entry.owner==a.selected and "> " or "")..entry.label.."  -  "..(who.level and ("Lv "..who.level) or "?").."  -  ilvl "..(entry.gear.ilvl or 0))
                b:Show()
            else b:Hide() end
        end
        local snapshot=a.selected and store[a.selected]
        for _,entry in ipairs(a.slots) do
            local id=snapshot and snapshot.items[entry.slot]
            entry.button.slotID=entry.slot
            entry.button:SetShown(snapshot~=nil)
            entry.label:SetShown(snapshot~=nil)
            if snapshot then
                if id then
                    local name,link,texture,quality=TC.ItemName(id)
                    entry.button.link=link
                    entry.button.icon:SetTexture(texture)
                    entry.button.quality:SetColorTexture(QualityColor(quality))
                    entry.label:SetText(name); entry.label:SetTextColor(0.82,0.77,0.66)
                else
                    entry.button.link=nil
                    entry.button.icon:SetColorTexture(0.12,0.12,0.11,1)
                    entry.button.quality:SetColorTexture(emptyR,emptyG,emptyB)
                    entry.label:SetText(TC.GearSlotName(entry.slot)); entry.label:SetTextColor(0.45,0.44,0.42)
                end
            end
        end
        if snapshot then
            local who=a.selected==TC.owner and own or roster[a.selected] or {}
            a.title:SetText(TC.DisplayName(a.selected))
            a.subtitle:SetText((who.class or "Unknown class").."  |  Level "..(who.level or "?").."  |  Equipped item level "..(snapshot.ilvl or 0).."  |  Updated "..Ago(snapshot.when))
        else
            a.title:SetText("No gear shared yet")
            a.subtitle:SetText("Guildmates running this version publish their equipment automatically. Press Sync armory to ask for it now.")
        end
        a.message:SetText(#rows>visible and "Scroll the list for more characters." or "")
    end

    function a.Layout()
        local width,height=window:GetWidth(),window:GetHeight()
        local content=math.min(720,width-48)
        local left=(width-content)/2
        local listWidth=math.min(260,math.floor(content*0.36))
        local paperX=left+listWidth+16
        local paperWidth=content-listWidth-16
        local column=math.floor((paperWidth-16)/2)
        a.visible=math.min(9,math.max(1,math.floor((height-300)/30)))
        Place(a.sync,left,106,listWidth,28)
        for i,b in ipairs(a.rows) do
            Place(b,left,146+(i-1)*30,listWidth,26)
            b:SetShown(i<=a.visible)
        end
        Place(a.message,left,146+a.visible*30+6,listWidth,18)
        Place(a.title,paperX,100,paperWidth,24)
        Place(a.subtitle,paperX,128,paperWidth,18)
        for index,entry in ipairs(a.slots) do
            local inRight=index>#leftColumn
            local row=inRight and index-#leftColumn or index
            local x=paperX+(inRight and (column+16) or 0)
            local y=156+(row-1)*36
            Place(entry.button,x,y,32,32)
            Place(entry.label,x+38,y+9,column-42,16)
        end
    end

    window.guildPages.armory=a
    TC.RefreshArmory=function()
        if window.activePage=="armory" and window:IsShown() and TC.guildKey then a.Update() end
    end
end
