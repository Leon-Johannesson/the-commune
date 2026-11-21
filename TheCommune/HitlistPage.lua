local _,TC=...
function TC.BuildHitlistPage(window,H)
    local Button=H.Button
    local Label=H.Label
    local function Place(widget,x,y,width,height) H.Place(widget,x,-y,width,height) end
    local function Field(box,x,y,width) H.PlaceEdit(box,x,-y,width) end
    local h=CreateFrame("Frame",nil,window); h:SetAllPoints(window); h:Hide(); h.offset=0

    h.sync=Button(h,"Sync hitlist",function() TC.Query(true); TC.BroadcastHitCache(); h.message:SetText("Hitlist sync queued.") end)
    h.rows={}
    for i=1,7 do h.rows[i]=Button(h,"",function(self)
        h.selected=self.entry; h.name:SetText(self.entry.hit.name or self.entry.hit.target:gsub("%-"," ")); h.reason:SetText(self.entry.hit.reason)
        h.Update()
    end) end
    h:EnableMouseWheel(true); h:SetScript("OnMouseWheel",function(_,delta) h.offset=math.max(0,h.offset-delta*3); h.Update() end)
    h.name=H.Edit(h,"Enemy's full name",90)
    h.reason=H.Edit(h,"Reason / note",80)
    h.target=Button(h,"Use enemy target",function()
        local name=TC.EnemyTarget()
        if name then h.selected=nil; h.name:SetText(name); h.Update()
        else h.message:SetText("Target an opposing-faction player first.") end
    end)
    h.new=Button(h,"New entry",function() h.selected=nil; h.name:SetText(""); h.reason:SetText(""); h.Update() end)
    h.save=Button(h,"Save",function()
        if h.selected and h.selected.owner~=TC.owner then h.message:SetText("Create your own entry to change this player note."); return end
        local slot,err=TC.SaveHit(h.selected and h.selected.slot,h.name:GetText(),h.reason:GetText())
        h.message:SetText(slot and "Hitlist entry queued for guild sync." or err)
    end)
    h.remove=Button(h,"Remove",function()
        if not h.selected then h.message:SetText("Select an entry first."); return end
        local ok,err=TC.DeleteHit(h.selected.owner,h.selected.slot); if ok then h.selected=nil end
        h.message:SetText(ok and "Entry removed." or err); h.Update()
    end)
    h.sound=CreateFrame("CheckButton",nil,h,"UICheckButtonTemplate"); h.sound:SetPoint("TOPLEFT",24,-508)
    h.soundLabel=Label(h,"Sound alerts",56,-516,200)
    h.sound:SetScript("OnClick",function(self) TC.db.fun.sound=not not self:GetChecked() end)
    h.message=Label(h,"",0,0)
    h.message:SetWordWrap(true); h.message:SetJustifyV("TOP")

    function h.Update()
        local p=h; local rows=TC.HitRows(); p.offset=math.min(p.offset,math.max(0,#rows-(p.visible or 7)))
        for i,b in ipairs(p.rows) do
            local entry=i<=(p.visible or 7) and rows[p.offset+i]; b.entry=entry
            if entry then b:SetText((entry.hit.name or entry.hit.target).."  |  "..entry.hit.reason.."  ("..TC.DisplayName(entry.owner)..")"); b:Show() else b:Hide() end
        end
        p.sound:SetChecked(TC.db.fun.sound)
        p.remove:SetEnabled(p.selected~=nil and (p.selected.owner==TC.owner or TC.IsProjectOfficer(TC.owner)==true))
    end
    function h.Layout()
        local width,height=window:GetWidth(),window:GetHeight()
        local content=math.min(720,width-48)
        local left,half=(width-content)/2,(content-24)/2
        h.visible=math.min(7,math.max(1,math.floor((height-322)/32)))
        Place(h.sync,left,106,140,28)
        for i,b in ipairs(h.rows) do Place(b,left,144+(i-1)*32,content,28) end
        local formY=height-170
        Field(h.name,left,formY,half); Field(h.reason,left+half+24,formY,half)
        local buttonWidth=(content-3*8)/4
        for i,b in ipairs({h.target,h.new,h.save,h.remove}) do Place(b,left+(i-1)*(buttonWidth+8),formY+64,buttonWidth,28) end
        Place(h.sound,left,formY+102,26,26); Place(h.soundLabel,left+32,formY+108,150,18)
        Place(h.message,left+188,formY+103,content-188,48)
        h.Update()
    end
    window.guildPages.hitlist=h
    TC.RefreshHitlist=function()
        if window.activePage=="hitlist" and window:IsShown() and TC.guildKey then h.Update() end
    end
end
