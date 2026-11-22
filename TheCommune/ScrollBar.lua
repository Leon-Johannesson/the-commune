local _,TC=...

-- GetCursorPosition reports in raw screen units; divide by the effective scale
-- to compare against frame edges, the same way Resize.lua does.
local function CursorY(frame)
    if not GetCursorPosition then return end
    local _,y=GetCursorPosition()
    return y/(frame:GetEffectiveScale() or 1)
end

-- The row lists in this addon are a manual offset into a table rather than a
-- ScrollFrame, and the client's scroll-bar templates have been renamed more
-- than once, so the bar is built from plain textures. Place it with the page's
-- own layout helper, then call Refresh whenever the rows are filled.
function TC.AttachScrollBar(parent,apply)
    local bar=CreateFrame("Frame",nil,parent)
    bar.track=bar:CreateTexture(nil,"BACKGROUND"); bar.track:SetAllPoints()
    bar.track:SetColorTexture(0.07,0.07,0.06,0.85)
    bar.thumb=CreateFrame("Button",nil,bar)
    bar.thumb.texture=bar.thumb:CreateTexture(nil,"ARTWORK"); bar.thumb.texture:SetAllPoints()
    bar.thumb.texture:SetColorTexture(0.55,0.48,0.34,1)
    bar.thumb:SetWidth(10)
    bar:EnableMouse(true); bar:Hide()
    bar.total,bar.visible,bar.offset=0,1,0

    local function MaxOffset() return math.max(0,bar.total-bar.visible) end
    local function Apply(value)
        value=math.max(0,math.min(MaxOffset(),value))
        if value~=bar.offset then bar.offset=value; apply(value) end
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
        -- Track the cursor's absolute position so a long drag cannot drift.
        local ratio=math.max(0,math.min(1,(top-(y+(bar.thumb.grab or 0)))/travel))
        Apply(math.floor(ratio*MaxOffset()+0.5))
    end)
    bar:SetScript("OnMouseDown",function(self)
        local y=CursorY(self)
        local thumbTop,thumbBottom=bar.thumb:GetTop(),bar.thumb:GetBottom()
        if not y or not thumbTop or not thumbBottom then return end
        -- A click on the track pages toward the click, like a standard bar.
        if y>thumbTop then Apply(bar.offset-bar.visible)
        elseif y<thumbBottom then Apply(bar.offset+bar.visible) end
    end)

    function bar.Refresh(total,visible,offset)
        bar.total,bar.visible,bar.offset=total or 0,math.max(1,visible or 1),offset or 0
        if bar.total<=bar.visible then bar:Hide(); return end
        bar:Show()
        local height=bar:GetHeight()
        local thumb=math.max(24,math.floor(height*bar.visible/bar.total))
        local travel=height-thumb
        local max=MaxOffset()
        bar.thumb:SetHeight(thumb)
        bar.thumb:ClearAllPoints()
        bar.thumb:SetPoint("TOPLEFT",bar,"TOPLEFT",1,-math.floor(travel*(max>0 and bar.offset/max or 0)))
    end

    return bar
end
