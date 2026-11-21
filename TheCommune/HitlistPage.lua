local _,TC=...
-- GetCursorPosition reports in raw screen units; divide by the effective scale
-- to compare against frame edges, the same way Resize.lua does.
local function CursorY(frame)
    if not GetCursorPosition then return end
    local _,y=GetCursorPosition()
    return y/(frame:GetEffectiveScale() or 1)
end

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

    -- Built from plain textures rather than a scroll-bar template: the rows are
    -- a manual offset list, not a ScrollFrame, and the client's templates have
    -- changed name more than once.
    local bar=CreateFrame("Frame",nil,h)
    bar.track=bar:CreateTexture(nil,"BACKGROUND"); bar.track:SetAllPoints()
    bar.track:SetColorTexture(0.07,0.07,0.06,0.85)
    bar.thumb=CreateFrame("Button",nil,bar)
    bar.thumb.texture=bar.thumb:CreateTexture(nil,"ARTWORK"); bar.thumb.texture:SetAllPoints()
    bar.thumb.texture:SetColorTexture(0.55,0.48,0.34,1)
    bar.thumb:SetWidth(10)
    bar:EnableMouse(true); bar:Hide()
    h.scrollBar=bar
    local function MaxOffset() return math.max(0,(bar.total or 0)-(bar.visible or 7)) end
    local function SetOffset(value)
        value=math.max(0,math.min(MaxOffset(),value))
        if value~=h.offset then h.offset=value; h.Update() end
    end
    bar.thumb:SetScript("OnMouseDown",function(self)
        local y=CursorY(self); local top=self:GetTop()
        if not y or not top then return end
        self.grab=top-y; self.dragging=true
    end)
    bar.thumb:SetScript("OnMouseUp",function(self) self.dragging=false end)
    bar:SetScript("OnUpdate",function()
        if not bar.thumb.dragging then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then bar.thumb.dragging=false; return end
        local y=CursorY(bar); local top=bar:GetTop()
        local travel=bar:GetHeight()-bar.thumb:GetHeight()
        if not y or not top or travel<=0 then return end
        local ratio=math.max(0,math.min(1,(top-(y+(bar.thumb.grab or 0)))/travel))
        SetOffset(math.floor(ratio*MaxOffset()+0.5))
    end)
    bar:SetScript("OnMouseDown",function(self)
        local y=CursorY(self)
        local thumbTop,thumbBottom=bar.thumb:GetTop(),bar.thumb:GetBottom()
        if not y or not thumbTop or not thumbBottom then return end
        -- A click on the track pages toward the click, like a standard bar.
        if y>thumbTop then SetOffset(h.offset-(bar.visible or 7))
        elseif y<thumbBottom then SetOffset(h.offset+(bar.visible or 7)) end
    end)
    function bar.Refresh(total,visible)
        bar.total,bar.visible=total,visible
        if total<=visible then bar:Hide(); return end
        bar:Show()
        local height=bar:GetHeight()
        local thumb=math.max(24,math.floor(height*visible/total))
        local travel=height-thumb
        local ratio=MaxOffset()>0 and (h.offset/MaxOffset()) or 0
        bar.thumb:SetHeight(thumb)
        bar.thumb:ClearAllPoints()
        bar.thumb:SetPoint("TOPLEFT",bar,"TOPLEFT",1,-math.floor(travel*ratio))
    end
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
    h.scrollHint=Label(h,"",0,0)
    h.scrollHint:SetFontObject("GameFontDisableSmall")
    h.message=Label(h,"",0,0)
    h.message:SetWordWrap(true); h.message:SetJustifyV("TOP")

    function h.Update()
        local p=h; local rows=TC.HitRows(); p.offset=math.min(p.offset,math.max(0,#rows-(p.visible or 7)))
        for i,b in ipairs(p.rows) do
            local entry=i<=(p.visible or 7) and rows[p.offset+i]; b.entry=entry
            if entry then b:SetText((entry.hit.name or entry.hit.target).."  |  "..entry.hit.reason.."  ("..TC.DisplayName(entry.owner)..")"); b:Show() else b:Hide() end
        end
        h.scrollBar.Refresh(#rows,p.visible or 7)
        local shown=math.min(#rows,p.visible or 7)
        -- Nothing else says the list continues past the last visible row.
        p.scrollHint:SetText(#rows>shown and ("Showing "..(p.offset+1).."-"..(p.offset+shown).." of "..#rows.."  -  scroll for more") or "")
        p.sound:SetChecked(TC.db.fun.sound)
        p.remove:SetEnabled(p.selected~=nil and (p.selected.owner==TC.owner or TC.IsProjectOfficer(TC.owner)==true))
    end
    function h.Layout()
        local width,height=window:GetWidth(),window:GetHeight()
        local content=math.min(720,width-48)
        local left,half=(width-content)/2,(content-24)/2
        h.visible=math.min(7,math.max(1,math.floor((height-322)/32)))
        Place(h.sync,left,106,140,28)
        -- Reserve the bar's gutter even when it is hidden, so rows keep their
        -- width instead of reflowing as entries cross the visible count.
        local rowWidth=content-18
        for i,b in ipairs(h.rows) do Place(b,left,144+(i-1)*32,rowWidth,28) end
        Place(h.scrollBar,left+rowWidth+6,144,12,h.visible*32-4)
        Place(h.scrollHint,left,144+h.visible*32+4,content,16)
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
