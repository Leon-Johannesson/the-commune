local _,TC=...
local function Place(widget,x,y,width,height)
    widget:ClearAllPoints(); widget:SetPoint("TOPLEFT",x,-y)
    if width then widget:SetWidth(width) end; if height then widget:SetHeight(height) end
end
local function Field(box,x,y,width)
    Place(box.label,x,y,width,18); Place(box,x,y+22,width,28)
end
function TC.PositionWordInput(p)
    local active=math.min(#TC.DailyState().guesses,5)
    Place(p.entry,p.gridX,p.gridY+active*44,216,40)
end
function TC.LayoutSocialPages(window,main,pages)
    if not pages then return end
    local width,height=window:GetWidth(),window:GetHeight()
    Place(window.balance,12,4,width-24,18); window.balance:SetJustifyH("CENTER")
    local count=#window.tabs
    local tabWidth=math.min(116,math.floor((width-40-(count-1)*8)/count))
    local tabX=(width-(tabWidth*count+(count-1)*8))/2
    for i,b in ipairs(window.tabs) do Place(b,tabX+(i-1)*(tabWidth+8),30,tabWidth,26) end
    local content=math.min(720,width-48); local left=(width-content)/2
    TC.LayoutAim(pages.aim,width,height)
    local q=pages.quiz; local top=68+math.max(0,math.floor((height-68-374)/2))
    Place(q.header,left,top,content,18); q.header:SetJustifyH("CENTER")
    Place(q.question,left,top+30,content,64); q.question:SetJustifyH("CENTER")
    for i,b in ipairs(q.buttons) do Place(b,left,top+106+(i-1)*40,content,32) end
    Place(q.message,left,top+270,content,64); q.message:SetJustifyH("CENTER")
    Place(q.previous,width/2-128,top+346,120,28); Place(q.next,width/2+8,top+346,120,28)
    local w=pages.wordle; top=68+math.max(0,math.floor((height-68-400)/2))
    Place(w.header,12,top,width-24,18); Place(w.message,12,top+18,width-24,18)
    w.gridX=(width-216)/2; w.gridY=top+36
    if w.miniArea then Place(w.miniArea,width-184,w.gridY,172,260) end
    for row=1,6 do for col=1,5 do Place(w.cells[row][col],w.gridX+(col-1)*44,w.gridY+(row-1)*44,40,40) end end
    for row,letters in ipairs({"QWERTYUIOP","ASDFGHJKL","ZXCVBNM"}) do
        local keys={}; if row==3 then keys[#keys+1]="ENTER" end
        for key in letters:gmatch(".") do keys[#keys+1]=key end
        if row==3 then keys[#keys+1]="DEL" end
        local total=0; for _,key in ipairs(keys) do total=total+(#key>1 and 62 or 40)+4 end
        local x=(width-total+4)/2
        for _,key in ipairs(keys) do local size=#key>1 and 62 or 40
            Place(w.keys[key],x,w.gridY+272+(row-1)*32,size,28); x=x+size+4
        end
    end
    TC.PositionWordInput(w)
    local c=pages.credits; local half=(content-24)/2
    Place(c.info,left,80,content,32)
    c.visible=math.min(8,math.max(1,math.floor((height-290)/32)))
    for i,b in ipairs(c.rows) do Place(b,left,126+(i-1)*32,half,28) end
    Field(c.amount,left+half+24,104,half)
    Place(c.transfer,left+half+24,170,(half-8)/2,28)
    Place(c.award,left+half+32+(half-8)/2,170,(half-8)/2,28)
    Place(c.message,left,height-164,content,36); Place(c.history,left,height-116,content,100)
    local s=pages.scores
    Place(s.body,left,84,content,height-150); s.body:SetJustifyH("CENTER")
    Place(s.sync,width/2-70,height-48,140,28)
    local v=pages.pvp
    Place(v.mode,width/2-90,80,180,28)
    v.visible=math.min(7,math.max(1,math.floor((height-248)/32)))
    for i,b in ipairs(v.rows) do Place(b,left,122+(i-1)*32,content,28) end
    Place(v.detail,left,height-112,content,68); Place(v.tracking,left,height-40,content,32)
end
