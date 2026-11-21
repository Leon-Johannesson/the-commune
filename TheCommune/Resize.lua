local _,TC=...
function TC.BeginWindowResize(window)
    local width,height=window:GetWidth(),window:GetHeight()
    local x,y
    if GetCursorPosition then x,y=GetCursorPosition() end
    local scale=window:GetEffectiveScale() or 1
    local bounds=window.resizeBoundsBase
    local left,top=window:GetLeft(),window:GetTop()
    window.resizing=true
    window.resizeStart={width=width,height=height,x=x,y=y,scale=scale,minWidth=bounds[1],minHeight=bounds[2],maxWidth=bounds[3],maxHeight=bounds[4]}
    if type(left)=="number" and type(top)=="number" then
        window:ClearAllPoints(); window:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
        window:SetSize(width,height)
        window.resizeStart.maxWidth=math.max(width,math.min(bounds[3],UIParent:GetWidth()-left))
        window.resizeStart.maxHeight=math.max(height,math.min(bounds[4],top))
    end
end
function TC.StepWindowResize(window,stop)
    local start=window.resizeStart
    if not window.resizing or not start then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then stop(); return end
    if not start.x or not GetCursorPosition then return end
    local x,y=GetCursorPosition()
    local width=math.max(start.minWidth,math.min(start.maxWidth,start.width+(x-start.x)/start.scale))
    local height=math.max(start.minHeight,math.min(start.maxHeight,start.height+(start.y-y)/start.scale))
    if math.abs(width-window:GetWidth())>=0.5 or math.abs(height-window:GetHeight())>=0.5 then window:SetSize(width,height) end
end
