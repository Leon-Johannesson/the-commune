local _,TC=...
local window,pages,current,flight
local function Label(parent,text,x,y,width,height)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    f:SetPoint("TOPLEFT",x,y); f:SetText(text); f:SetJustifyH("LEFT")
    if width then f:SetWidth(width) end; if height then f:SetHeight(height); f:SetJustifyV("TOP"); f:SetWordWrap(true) else f:SetWordWrap(false) end
    return f
end
local function Button(parent,text,x,y,width,callback)
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
    TC.StyleButton(b)
    b:SetSize(width,26); b:SetPoint("TOPLEFT",x,y); b:SetText(text); b:SetScript("OnClick",callback); return b
end
local function Edit(parent,label,x,y,width,max)
    local title=Label(parent,label,x,y)
    local b=CreateFrame("EditBox",nil,parent,"BackdropTemplate"); b.label=title; TC.StyleEdit(b)
    b:SetSize(width-5,26); b:SetPoint("TOPLEFT",x+5,y-22); b:SetAutoFocus(false); b:SetMaxLetters(max)
    b:SetScript("OnEscapePressed",function(self) self:ClearFocus() end); return b
end
local function Backdrop(frame)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    TC.StyleWindow(frame)
end
local function ScoreText(limit)
    local lines={}
    for i,row in ipairs(TC.ScoreRows()) do
        if i>(limit or 10) then break end
        local p=row.profile
        lines[#lines+1]=p.name.."  |  Quiz "..p.qc.."/"..p.qa.."  |  Wordle "..p.ww.."/"..p.wp.."  |  "..row.balance.." SC"
    end
    return table.concat(lines,"\n")
end
local function Build()
    local main=TC.GetMainWindow()
    window=CreateFrame("Frame","TheCommuneSocialWindow",main.socialHost)
    window:SetPoint("TOPLEFT",0,0)
    TC.LayoutSocial=function()
        window:SetScale(1); window:SetSize(main:GetWidth()-24,main:GetHeight()-76)
        TC.LayoutSocialPages(window,main,pages)
    end
    TC.LayoutSocial()
    window.tabs={}
    window.balance=Label(window,"",20,-42,700)
    pages={}
    for i,name in ipairs({"quiz","wordle","credits","scores","pvp","aim"}) do
        local page=CreateFrame("Frame",nil,window); page:SetAllPoints(window); page:Hide(); pages[name]=page
        local title=({quiz="Daily Quiz",wordle="Daily Wordle",credits="Social Credits",scores="Guild Scores",pvp="PvP Stats",aim="Aim trainer"})[name]
        window.tabs[i]=Button(window,title,20+(i-1)*122,-68,116,function() TC.OpenSocial(name) end)
    end
    local q=pages.quiz; q.slot=1
    q.header=Label(q,"",24,-112,700)
    q.question=Label(q,"",24,-144,700,72)
    q.buttons={}
    for i=1,4 do
        q.buttons[i]=Button(q,"",24,-228-(i-1)*42,700,function()
            local ok,err=TC.AnswerQuiz(q.slot,i); if not ok then q.message:SetText(err) end; TC.RefreshSocialWindow()
        end)
        q.buttons[i]:SetHeight(34)
    end
    q.message=Label(q,"",24,-412,700,104)
    q.previous=Button(q,"Previous",24,-550,120,function() q.slot=q.slot==1 and 4 or q.slot-1; TC.RefreshSocialWindow() end)
    q.next=Button(q,"Next",158,-550,120,function() q.slot=q.slot==4 and 1 or q.slot+1; TC.RefreshSocialWindow() end)


    local w=pages.wordle
    w.header=Label(w,"",24,-110,732); w.header:SetJustifyH("CENTER")
    w.message=Label(w,"",24,-138,732,22)
    w.message:SetJustifyH("CENTER"); w.message:SetFontObject("GameFontHighlightSmall")
    w.cells={}; w.keys={}
    for row=1,6 do
        w.cells[row]={}
        for col=1,5 do
            local cell=CreateFrame("Button",nil,w,"BackdropTemplate"); cell:SetSize(48,48)
            cell:SetPoint("TOPLEFT",258+(col-1)*54,-166-(row-1)*54)
            cell:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
            cell:SetBackdropColor(0.07,0.08,0.08,1); cell:SetBackdropBorderColor(0.23,0.24,0.25,1)
            cell.letter=cell:CreateFontString(nil,"OVERLAY","GameFontNormalHuge"); cell.letter:SetPoint("CENTER")
            cell.letter:SetTextColor(1,1,1,1)
            cell:SetScript("OnClick",function()
                local d=TC.DailyState(); if not d.wordleResult and row==#d.guesses+1 then w.entry:SetFocus() end
            end)
            w.cells[row][col]=cell
        end
    end
    -- A real EditBox receives native typing/backspace, but only the tile
    -- letters are drawn. It moves onto the unsubmitted row after each guess.
    w.entry=CreateFrame("EditBox",nil,w)
    w.entry:SetSize(264,48); w.entry:SetAutoFocus(false); w.entry:SetMaxLetters(5)
    w.entry:SetFontObject("GameFontNormalLarge"); w.entry:SetTextColor(1,1,1,0)
    w.entry:SetScript("OnTextChanged",function(self)
        if w.changing then return end
        local text=self:GetText():upper():gsub("[^A-Z]", ""):sub(1,5)
        if text~=self:GetText() then w.changing=true; self:SetText(text); w.changing=false end
        TC.RefreshSocialWindow()
    end)
    w.entry:SetScript("OnEditFocusGained",function() TC.RefreshSocialWindow() end)
    w.entry:SetScript("OnEditFocusLost",function() TC.RefreshSocialWindow() end)
    w.entry:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    w:SetScript("OnHide",function() w.entry:ClearFocus() end)
    local function Guess()
        local ok,err=TC.GuessWord(w.entry:GetText())
        if ok then w.entry:SetText(""); w.message:SetText("") else w.message:SetText(err) end
        TC.RefreshSocialWindow()
        local _,finished=TC.DailyProgress(); if not finished then w.entry:SetFocus() end
    end
    w.entry:SetScript("OnEnterPressed",Guess)
    local function Key(key)
        local _,finished=TC.DailyProgress(); if finished then return end
        if key=="ENTER" then Guess()
        elseif key=="DEL" then w.entry:SetText(w.entry:GetText():sub(1,-2))
        elseif #w.entry:GetText()<5 then w.entry:SetText(w.entry:GetText()..key) end
        if not select(2,TC.DailyProgress()) then w.entry:SetFocus() end
    end
    for row,letters in ipairs({"QWERTYUIOP","ASDFGHJKL","ZXCVBNM"}) do
        local keys={}; if row==3 then keys[#keys+1]="ENTER" end
        for ch in letters:gmatch(".") do keys[#keys+1]=ch end
        if row==3 then keys[#keys+1]="DEL" end
        local width=0; for _,key in ipairs(keys) do width=width+(#key>1 and 70 or 44)+4 end
        local x=(780-width+4)/2
        for _,key in ipairs(keys) do
            local size=#key>1 and 70 or 44
            local b=CreateFrame("Button",nil,w,"BackdropTemplate"); b:SetSize(size,32)
            b:SetPoint("TOPLEFT",x,-500-(row-1)*38)
            b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); b:SetBackdropColor(0.44,0.46,0.48,1)
            b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlight"); b.text:SetPoint("CENTER"); b.text:SetText(key)
            b:SetScript("OnClick",function() Key(key) end); w.keys[key]=b; x=x+size+4
        end
    end


    w.miniArea=CreateFrame("Frame",nil,w); w.miniArea:SetSize(172,260)
    w.miniHeading=Label(w.miniArea,"Guild solves",0,16,172,16)
    w.miniBoards={}; w.boardOffset=0
    for i=1,6 do
        local mini=CreateFrame("Frame",nil,w.miniArea); mini:SetSize(82,74)
        mini:SetPoint("TOPLEFT",((i-1)%2)*86,-math.floor((i-1)/2)*80)
        mini.name=Label(mini,"",0,0,82,14); mini.name:SetFontObject("GameFontHighlightSmall")
        mini.cells={}
        for row=1,6 do for col=1,5 do
            local tile=mini:CreateTexture(nil,"ARTWORK"); tile:SetSize(7,7); tile:SetPoint("TOPLEFT",(col-1)*9,-16-(row-1)*9)
            mini.cells[(row-1)*5+col]=tile
        end end
        w.miniBoards[i]=mini
    end
    w.miniArea:EnableMouseWheel(true)
    w.miniArea:SetScript("OnMouseWheel",function(_,delta) w.boardOffset=math.max(0,w.boardOffset-delta*2); TC.RefreshSocialWindow() end)

    local c=pages.credits
    c.info=Label(c,"",24,-112,720,40)
    c.rows={}; c.offset=0
    for i=1,8 do
        c.rows[i]=Button(c,"",24,-162-(i-1)*30,360,function(self) c.selected=self.account; TC.RefreshSocialWindow() end)
    end
    c:EnableMouseWheel(true); c:SetScript("OnMouseWheel",function(_,delta) c.offset=math.max(0,c.offset-delta*3); TC.RefreshSocialWindow() end)
    c.amount=Edit(c,"Amount",420,-164,180,5); c.amount:SetText("1")
    c.transfer=Button(c,"Remove credits",420,-224,125,function()
        local ok,err=TC.AdjustCredits(c.selected,c.amount:GetText(),true); c.message:SetText(ok and "Credits removed." or err)
    end)
    c.award=Button(c,"Add credits",556,-224,150,function()
        local ok,err=TC.AdjustCredits(c.selected,c.amount:GetText(),false); c.message:SetText(ok and "Credits added." or err)
    end)
    c.message=Label(c,"",24,-432,700,45)
    c.history=Label(c,"",24,-488,700,104); c.history:SetFontObject("GameFontHighlightSmall")

    local s=pages.scores

    s.body=Label(s,"",24,-160,700,380)
    s.body:SetFontObject("GameFontHighlight")
    s.sync=Button(s,"Sync guild",24,-554,140,function() TC.Query(true) end)

    local v=pages.pvp; v.offset=0; v.shame=false
    v.mode=Button(v,"Show shame list",24,-180,180,function() v.shame=not v.shame; v.offset=0; TC.RefreshSocialWindow() end)
    v.rows={}
    for i=1,7 do
        v.rows[i]=Button(v,"",24,-222-(i-1)*32,720,function(self) v.selected=self.owner; TC.RefreshSocialWindow() end)
    end
    v:EnableMouseWheel(true); v:SetScript("OnMouseWheel",function(_,delta) v.offset=math.max(0,v.offset-delta*3); TC.RefreshSocialWindow() end)
    v.detail=Label(v,"Select a player for the level-gap breakdown.",24,-464,720,112)
    v.detail:SetFontObject("GameFontHighlightSmall")
    v.tracking=Label(v,"",24,-592,720,38); v.tracking:SetFontObject("GameFontDisableSmall")
    TC.BuildAim(pages.aim,{Label=Label,Button=Button})
    window.pages=pages
    TC.LayoutSocial()
end

local colours={[0]={0.23,0.24,0.25},[1]={0.71,0.62,0.23},[2]={0.33,0.55,0.31}}
function TC.RefreshSocialWindow()
    if flight and flight:IsShown() then TC.UpdateFlightPanel() end
    if not window or not window:IsShown() or not current then return end
    local d=TC.DailyState(); local _,finished=TC.DailyProgress()
    window.balance:SetText(TC.db.fun.display.."  |  "..TC.CreditBalance().." Social Credits")
    if current=="quiz" then
        local p=pages.quiz; local question=TC.DailyQuiz()[p.slot]; local a=d.answers[p.slot]
        p.header:SetText("Question "..p.slot.."/4")
        p.question:SetText(question.question)
        for i,b in ipairs(p.buttons) do b:SetText(question.options[i]); b:SetEnabled(a==nil) end
        p.message:SetText(a and ((a.correct and "Correct! +1 Social Credit.\n" or "Not quite.\n").."Answer: "..question.answer.."\n"..question.explanation) or "")
    elseif current=="wordle" then
        local p=pages.wordle; local letters={}; local active=#d.guesses+1
        local _,day=TC.DailyState()
        if p.day~=day then
            p.day=day; p.changing=true; p.entry:SetText(""); p.changing=false
            p.message:SetText("")
        end
        local draft=p.entry:GetText()
        for row=1,6 do
            local word=d.guesses[row]; local feedback=word and TC.WordFeedback(word,TC.WordAnswer())
            for col=1,5 do
                local cell=p.cells[row][col]; local value=word and feedback[col]
                local colour=word and colours[value] or {0.07,0.08,0.08}
                local pending=not finished and row==active
                cell:SetBackdropColor(colour[1],colour[2],colour[3],1)
                local border=pending and (p.entry:HasFocus() and 0.72 or 0.45) or 0.23
                if word then cell:SetBackdropBorderColor(colour[1],colour[2],colour[3],1)
                else cell:SetBackdropBorderColor(border,border,border,1) end
                cell.letter:SetText(word and word:sub(col,col):upper() or pending and draft:sub(col,col) or "")
                if word then local ch=word:sub(col,col):upper(); letters[ch]=math.max(letters[ch] or 0,value) end
            end
        end
        for key,b in pairs(p.keys) do
            local value=letters[key]; local c=value~=nil and colours[value] or {0.44,0.46,0.48}
            b:SetBackdropColor(c[1],c[2],c[3],1); b:SetEnabled(not finished)
        end
        local boards=TC.WordBoards(); p.boardOffset=math.min(p.boardOffset,math.max(0,#boards-6))
        p.miniHeading:SetShown(#boards>0)
        for i,mini in ipairs(p.miniBoards) do
            local entry=boards[p.boardOffset+i]; mini:SetShown(entry~=nil)
            if entry then
                mini.name:SetText(entry.name.." "..entry.board.result.."/6")
                for index,tile in ipairs(mini.cells) do
                    local value=tonumber(entry.board.colors:sub(index,index)); local color=value and colours[value] or {0.12,0.12,0.11}
                    tile:SetColorTexture(color[1],color[2],color[3],value and 1 or 0.35)
                end
            end
        end
        TC.PositionWordInput(p)
        p.entry:SetEnabled(not finished); p.entry:SetShown(not finished)
        p.header:SetText(d.wordleResult and (d.wordleResult<=6 and ("Solved in "..d.wordleResult.."! +"..(d.wordleCredits or 2).." Social Credits") or "Finished for today") or ("Guess "..active.." of 6"))
        if finished then p.entry:ClearFocus(); p.message:SetText("Today's word: "..TC.WordAnswer():upper()) end
    elseif current=="credits" then
        local p=pages.credits; local rows=TC.ScoreRows(); p.offset=math.min(p.offset,math.max(0,#rows-(p.visible or 8)))
        local isGM=TC.IsGuildMaster(TC.owner)==true
        p.info:SetText(isGM and "" or "Only the guild master can adjust credits.")
        for i,b in ipairs(p.rows) do
            local entry=i<=(p.visible or 8) and rows[p.offset+i]; b.account=entry and entry.account
            if entry then b:SetText((entry.account==p.selected and "> " or "")..entry.profile.name.."  -  "..entry.balance.." SC"); b:Show() else b:Hide() end
        end
        p.award:SetEnabled(isGM)
        p.transfer:SetEnabled(isGM)
        p.amount:SetEnabled(isGM)
        local lines={}; for i,event in ipairs(TC.db.fun.history or {}) do if i>6 then break end; lines[#lines+1]=event.text end
        p.history:SetText(table.concat(lines,"\n"))
    elseif current=="aim" then TC.RefreshAim(pages.aim)
    elseif current=="scores" then pages.scores.body:SetText(ScoreText(20))
    elseif current=="pvp" then
        local p=pages.pvp; local rows=TC.PvPRows(p.shame); p.offset=math.min(p.offset,math.max(0,#rows-(p.visible or 7)))
        local labels={}; for _,r in ipairs(rows) do labels[r.owner]=r.label end
        p.tracking:SetText(TC.PvPStatus())
        p.mode:SetText(p.shame and "Show most kills" or "Show shame list")
        for i,b in ipairs(p.rows) do
            local r=i<=(p.visible or 7) and rows[p.offset+i]; b.owner=r and r.owner
            if r then
                local s=r.stats
                b:SetText(r.label.." | Honorable kills: "..(s.honorKills~=nil and s.honorKills or "?").." | Deaths: "..(s.deaths~=nil and (s.deaths..(s.deathsLifetime and "" or "*")) or "?").." | Observed: "..s.total.." | ±2: "..s.fair.." | 10+ below: "..s.below10)
                b:Show()
            else b:Hide() end
        end
        local selected=p.selected and TC.store.social.pvp[p.selected]
        if selected then
            local gaps={}; for diff,count in pairs(selected.diffs) do gaps[#gaps+1]={diff=diff,count=count} end
            table.sort(gaps,function(a,b) return a.diff<b.diff end)
            local parts={}; for _,g in ipairs(gaps) do parts[#parts+1]=(g.diff>0 and "+" or "")..g.diff..": "..g.count end
            p.detail:SetText((labels[p.selected] or TC.DisplayName(p.selected)).." - victim level minus killer level (negative = lower)\n"..table.concat(parts," | ").."\nUnknown level: "..selected.unknown.." | Deaths: "..(selected.deaths or "?")..(selected.deathsLifetime and " (lifetime, all causes)" or " (tracked since addon, all causes)"))
        else p.detail:SetText("Select a player for the level-gap breakdown. Shame list ranks kills against players 10+ levels lower.") end
    end
end
function TC.OpenSocial(page)
    if not TC.store or not TC.db.fun then TC.Print("Please wait until login finishes."); return end
    if not TC.guildKey then TC.GetMainWindow():Show(); TC.Refresh(); return end
    if page=="hitlist" then TC.GetMainWindow():Show(); TC.ShowPage("hitlist"); return end
    page=pages and pages[page] and page or ((page=="quiz" or page=="wordle" or page=="credits" or page=="pvp" or page=="aim") and page or "scores")
    if not window then Build() end
    TC.EnterSocial()
    current=page; for name,p in pairs(pages) do p:SetShown(name==page) end
    window:Show(); TC.RefreshSocialWindow()
    if page=="wordle" and not select(2,TC.DailyProgress()) then pages.wordle.entry:SetFocus() end
end
function TC.UpdateFlightPanel()
    if not flight then return end
    local answered,wordle=TC.DailyProgress()
    flight.reminder:SetText((answered<4 and ("Quiz: "..(4-answered).." questions left") or "Quiz complete").."  |  "..(wordle and "Wordle complete" or "Wordle to do"))
    flight.scores:SetText(ScoreText(6))
    local measured=flight.scores:GetStringHeight()
    local height=type(measured)=="number" and measured>0 and measured or math.min(6,math.max(1,#TC.ScoreRows()))*14
    height=math.max(14,height); flight.scores:SetHeight(height); flight:SetHeight(90+height+8)
end
function TC.ShowFlightPanel()
    if not TC.guildKey then return end
    if not flight then
        flight=CreateFrame("Frame","TheCommuneFlightPanel",UIParent,"BackdropTemplate"); flight:SetSize(352,112); flight:SetPoint("TOPLEFT",UIParent,"TOPLEFT",24,-150)
        flight:SetFrameStrata("MEDIUM"); flight:SetClampedToScreen(true); Backdrop(flight)
        TC.RememberWindow(flight,"flight",nil,true)
        Label(flight,"The Commune - Flight Time Entertainment",12,-12,308):SetFontObject("GameFontHighlightSmall")
        local close=CreateFrame("Button",nil,flight,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT"); close:SetScript("OnClick",function() flight:Hide() end)
        flight.reminder=Label(flight,"",12,-34,328,18)
        Button(flight,"Daily Quiz",12,-58,104,function() TC.OpenSocial("quiz") end):SetHeight(24)
        Button(flight,"Daily Wordle",124,-58,104,function() TC.OpenSocial("wordle") end):SetHeight(24)
        Button(flight,"Aim trainer",236,-58,104,function() TC.OpenSocial("aim") end):SetHeight(24)
        flight.scores=Label(flight,"",12,-90,328,14); flight.scores:SetFontObject("GameFontHighlightSmall")
    end
    TC.UpdateFlightPanel(); flight:Show()
end
function TC.HideFlightPanel() if flight then flight:Hide() end end
