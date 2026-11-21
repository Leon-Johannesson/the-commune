local _,TC=...
local frames={}
local points={CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
local function Valid(saved)
    return type(saved)=="table" and points[saved.point] and points[saved.relativePoint] and
        type(saved.x)=="number" and type(saved.y)=="number" and saved.x==saved.x and saved.y==saved.y and
        math.abs(saved.x)<100000 and math.abs(saved.y)<100000
end
function TC.SaveWindowPosition(frame,key)
    if not TC.db then return end
    local point,_,relativePoint,x,y=frame:GetPoint(1)
    local saved={point=point,relativePoint=relativePoint,x=x,y=y}
    if not Valid(saved) then return end
    TC.db.windowPositions=TC.db.windowPositions or {}; TC.db.windowPositions[key]=saved
    if key=="main" and TC.db.ui then
        for field,value in pairs(saved) do TC.db.ui[field]=value end
        TC.db.ui.width=frame:GetWidth(); TC.db.ui.height=frame:GetHeight()
    end
end
function TC.RememberWindow(frame,key,legacy,movable)
    frames[key]=frame
    TC.db.windowPositions=TC.db.windowPositions or {}
    local saved=TC.db.windowPositions[key] or legacy
    if Valid(saved) then
        frame:ClearAllPoints(); frame:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y)
    end
    frame:SetClampedToScreen(true)
    if movable then
        frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart",frame.StartMoving)
        frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing(); TC.SaveWindowPosition(self,key) end)
    else
        frame:HookScript("OnDragStop",function() TC.SaveWindowPosition(frame,key) end)
    end
    frame:HookScript("OnHide",function() frame:StopMovingOrSizing(); TC.SaveWindowPosition(frame,key) end)
end
local events=CreateFrame("Frame"); events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent",function(_,event)
    if event~="PLAYER_LOGOUT" then return end
    for key,frame in pairs(frames) do frame:StopMovingOrSizing(); TC.SaveWindowPosition(frame,key) end
end)
