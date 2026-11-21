local _,TC=...
local function Stats()
    TC.db.fun.aim=TC.db.fun.aim or {hits=0,misses=0,lifetimeHits=0,lifetimeMisses=0,dots={}}
    return TC.db.fun.aim
end
local function PlaceDot(page,index)
    local point=Stats().dots[index]
    local width,height=page.arena:GetWidth(),page.arena:GetHeight()
    local dot=page.dots[index]
    dot:ClearAllPoints(); dot:SetPoint("CENTER",page.arena,"TOPLEFT",22+point.x*math.max(0,width-44),-(22+point.y*math.max(0,height-44)))
end
local function NewDot(page,index)
    local saved=Stats(); local width,height=page.arena:GetWidth()-44,page.arena:GetHeight()-44
    local candidate
    for _=1,80 do
        candidate={x=math.random(),y=math.random()}; local clear=true
        for _,other in pairs(saved.dots) do
            local dx,dy=(candidate.x-other.x)*width,(candidate.y-other.y)*height
            if dx*dx+dy*dy<52*52 then clear=false; break end
        end
        if clear then break end
    end
    saved.dots[index]=candidate; PlaceDot(page,index)
end
function TC.RefreshAim(page)
    local saved=Stats(); local total=saved.hits+saved.misses
    page.stats:SetText("Hits: "..saved.hits.."  |  Misses: "..saved.misses.."  |  Accuracy: "..(total>0 and math.floor(100*saved.hits/total+0.5) or 0).."%")
end
function TC.BuildAim(page,H)
    page.stats=H.Label(page,"",24,-80,560)
    page.reset=H.Button(page,"New round",600,-76,120,function()
        local saved=Stats(); saved.hits=0; saved.misses=0; saved.dots={}
        for i=1,7 do NewDot(page,i) end; TC.RefreshAim(page)
    end)
    page.arena=CreateFrame("Frame",nil,page,"BackdropTemplate"); page.arena:EnableMouse(true)
    page.arena:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    page.arena:SetBackdropColor(0.055,0.06,0.055,1); page.arena:SetBackdropBorderColor(0.32,0.31,0.26,1)
    local function Miss()
        local saved=Stats(); saved.misses=saved.misses+1; saved.lifetimeMisses=saved.lifetimeMisses+1; TC.RefreshAim(page)
    end
    page.arena:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" then Miss() end end)
    page.dots={}
    for i=1,7 do
        local dot=CreateFrame("Button",nil,page.arena); dot:SetSize(28,28)
        dot.texture=dot:CreateTexture(nil,"ARTWORK"); dot.texture:SetAllPoints(); dot.texture:SetColorTexture(0.93,0.40,0.28,1)
        local mask=dot:CreateMaskTexture(nil,"ARTWORK")
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE"); mask:SetAllPoints()
        dot.texture:AddMaskTexture(mask)
        dot:SetScript("OnClick",function()
            if GetCursorPosition then
                local x,y=GetCursorPosition(); local scale=dot:GetEffectiveScale() or 1
                local left,top=dot:GetLeft(),dot:GetTop()
                if type(left)=="number" and type(top)=="number" then
                    local dx,dy=x/scale-(left+14),y/scale-(top-14)
                    if dx*dx+dy*dy>14*14 then Miss(); return end
                end
            end
            local saved=Stats(); saved.hits=saved.hits+1; saved.lifetimeHits=saved.lifetimeHits+1
            NewDot(page,i); TC.RefreshAim(page)
        end)
        page.dots[i]=dot
    end
end
function TC.LayoutAim(page,width,height)
    page.stats:SetWidth(width-220)
    page.reset:ClearAllPoints(); page.reset:SetPoint("TOPLEFT",width-144,-76)
    page.arena:ClearAllPoints(); page.arena:SetPoint("TOPLEFT",24,-112); page.arena:SetSize(width-48,height-128)
    local saved=Stats()
    for i=1,7 do
        local point=saved.dots[i]
        if not point or type(point.x)~="number" or type(point.y)~="number" or point.x<0 or point.x>1 or point.y<0 or point.y>1 then NewDot(page,i) else PlaceDot(page,i) end
    end
    TC.RefreshAim(page)
end
