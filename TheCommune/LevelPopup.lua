local _, TC = ...
local popup, baseline, pending, ready, shownToken
local fields={{"health","Max health"},{"mana","Max mana"},{"strength","Strength"},{"agility","Agility"},
    {"stamina","Stamina"},{"intellect","Intellect"},{"spirit","Spirit"}}

local function Read(fn, index, ...)
    if type(fn)~="function" then return end
    local values={pcall(fn,...)}
    if not values[1] then return end
    local value=values[index+1]
    if issecretvalue and issecretvalue(value) then return end
    if type(value)=="number" and value==value and value>=0 and value<1000000000 then return math.floor(value) end
end
local function Snapshot()
    local s={level=Read(UnitLevel,1,"player"),health=Read(UnitHealthMax,1,"player"),mana=Read(UnitPowerMax,1,"player",0)}
    for i,key in ipairs({"strength","agility","stamina","intellect","spirit"}) do
        s[key]=Read(UnitStat,2,"player",i)
    end
    return s
end
local function Label(parent,text,font)
    local f=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    f:SetText(text); f:SetJustifyH("LEFT"); f:SetWordWrap(false)
    f:SetTextColor(0.82,0.77,0.66)
    return f
end
local function Portrait()
    if not popup then return end
    popup.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    if type(SetPortraitTexture)=="function" then pcall(SetPortraitTexture,popup.portrait,"player") end
end
local function Build()
    popup=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    popup:SetSize(314,330); popup:SetPoint("CENTER",UIParent,"CENTER",0,90)
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
    TC.StyleWindow(popup); TC.RememberWindow(popup,"levelPopup",nil,true)
    local portraitFrame=CreateFrame("Frame",nil,popup,"BackdropTemplate")
    portraitFrame:SetSize(76,76); portraitFrame:SetPoint("TOP",popup,"TOP",0,37)
    local ring=portraitFrame:CreateTexture(nil,"BACKGROUND")
    ring:SetAllPoints(); ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    ring:SetVertexColor(0.60,0.53,0.36,1)
    local face=portraitFrame:CreateTexture(nil,"ARTWORK")
    face:SetSize(68,68); face:SetPoint("CENTER")
    if face.AddMaskTexture and portraitFrame.CreateMaskTexture then
        local mask=portraitFrame:CreateMaskTexture()
        if mask then
            mask:SetAllPoints(face); mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
            face:AddMaskTexture(mask)
        end
    end
    popup.portrait=face
    local close=CreateFrame("Button",nil,popup,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",0,0); close:SetScript("OnClick",function() popup:Hide() end)
    popup.kicker=Label(popup,"THE COMMUNE"); popup.kicker:SetPoint("TOP",0,-47)
    popup.kicker:SetTextColor(0.47,0.84,0.68)
    popup.title=Label(popup,"", "GameFontHighlightLarge"); popup.title:SetPoint("TOP",0,-67)
    popup.subtitle=Label(popup,""); popup.subtitle:SetPoint("TOP",0,-92)
    popup.rows={}
    for i=1,#fields do
        local row=CreateFrame("Frame",nil,popup); row:SetSize(274,23)
        local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1,1,1,i%2==0 and 0.035 or 0)
        row.label=Label(row,""); row.label:SetPoint("LEFT",7,0); row.label:SetWidth(98)
        row.values=Label(row,""); row.values:SetPoint("RIGHT",-57,0); row.values:SetWidth(111); row.values:SetJustifyH("RIGHT")
        row.gain=Label(row,""); row.gain:SetPoint("RIGHT",-7,0); row.gain:SetWidth(46); row.gain:SetJustifyH("RIGHT")
        popup.rows[i]=row
    end
    popup.note=Label(popup,""); popup.note:SetPoint("BOTTOMLEFT",20,27); popup.note:SetWidth(274)
    popup.note:SetWordWrap(true); popup.note:SetHeight(30); popup.note:SetTextColor(0.57,0.60,0.56)
    popup.hint=Label(popup,""); popup.hint:SetPoint("BOTTOM",0,12); popup.hint:SetTextColor(0.57,0.60,0.56)
    popup:HookScript("OnShow",Portrait)
    popup:Hide()
end
local function Show(before,after,preview)
    if not popup then Build() end
    shownToken={}; local token=shownToken
    popup.title:SetText(preview and "Level-up preview" or ("Level "..after.level.."!"))
    popup.subtitle:SetText(preview and "Radio Lysander  |  Example values" or
        (before and before.level and ("Level "..before.level.."  >  "..after.level) or "Your character has grown"))
    local count=0
    for _,row in ipairs(popup.rows) do row:Hide() end
    for _,field in ipairs(fields) do
        local key,name=field[1],field[2]
        local old,value=before and before[key],after[key]
        if value and (key~="mana" or value>0 or (old and old>0)) then
            count=count+1
            local row=popup.rows[count]
            row:SetPoint("TOPLEFT",20,-117-(count-1)*23)
            row.label:SetText(name)
            row.values:SetText((old and tostring(old) or "?").." > "..value)
            local delta=old and value-old
            row.gain:SetText(delta and (delta>0 and ("+"..delta) or tostring(delta)) or "")
            row.gain:SetTextColor(delta and delta>0 and 0.47 or 0.72,delta and delta>0 and 0.84 or 0.67,0.58)
            row:Show()
        end
    end
    if count==0 then
        popup.note:SetText("Character stats are unavailable on this client.")
    else popup.note:SetText(preview and "PREVIEW ONLY - sample gains, not a real level-up." or "Current character totals, including equipment and effects.") end
    popup:SetHeight(117+count*23+66)
    popup.hint:SetText(preview and "Drag to move  |  Close when finished" or "Drag to move  |  Closes after 20 seconds")
    Portrait(); popup:Show()
    if not preview then C_Timer.After(20,function() if shownToken==token and popup then popup:Hide() end end) end
end
local function Radio()
    return TC.owner and TC.DisplayName(TC.owner)=="Radio Lysander"
end
function TC.PreviewLevelPopup()
    if not TC.db or not Radio() then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local before={level=29,health=1000,mana=1450,strength=42,agility=36,stamina=61,intellect=78,spirit=53}
    local after={level=30,health=1050,mana=1510,strength=43,agility=37,stamina=63,intellect=80,spirit=55}
    Show(before,after,true)
    return true
end
local function DisplayReady()
    if not ready or (InCombatLockdown and InCombatLockdown()) then return end
    local result=ready; ready=nil
    Show(result.before,result.after,false)
end
local function Sample()
    if pending then return end
    local snapshot=Snapshot()
    if snapshot.level and (not baseline or not baseline.level or snapshot.level==baseline.level) then baseline=snapshot end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_LEVEL_UP","PLAYER_REGEN_ENABLED","UNIT_STATS","UNIT_MAXHEALTH","UNIT_MAXPOWER","PLAYER_EQUIPMENT_CHANGED","UNIT_PORTRAIT_UPDATE"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event,arg)
    if not TC.db or not TC.owner then return end
    if event=="PLAYER_LOGIN" then
        baseline=Snapshot()
        -- Temporary owner-requested preview, once for this release on the exact
        -- full character name. It never changes real stats or sends a message.
        local attempts=0
        local function Preview()
            attempts=attempts+1
            if TC.db and Radio() then
                TC.db.levelPopupPreview=TC.db.levelPopupPreview or {}
                if not TC.db.levelPopupPreview[TC.owner] and not shownToken then
                    if not pending and not ready and TC.PreviewLevelPopup() then TC.db.levelPopupPreview[TC.owner]=true
                    elseif attempts<20 then C_Timer.After(1,Preview) end
                end
            elseif attempts<20 then C_Timer.After(1,Preview) end
        end
        C_Timer.After(4,Preview)
    elseif event=="PLAYER_LEVEL_UP" then
        local level=Read(function() return arg end,1)
        if not level or level<1 or level>255 then return end
        local previous=pending and pending.before or ready and ready.before or baseline
        if previous and previous.level and level<=previous.level then return end
        if pending and level<=pending.level then return end
        local work={before=previous,level=level,attempts=0}; pending=work
        local function Finish()
            if pending~=work then return end
            work.attempts=work.attempts+1
            local after=Snapshot()
            if after.level~=level and work.attempts<12 then C_Timer.After(0.5,Finish); return end
            pending=nil
            if after.level~=level then return end
            baseline=after; ready={before=previous,after=after}; DisplayReady()
        end
        C_Timer.After(1,Finish)
    elseif event=="PLAYER_REGEN_ENABLED" then DisplayReady(); Sample()
    elseif event=="UNIT_PORTRAIT_UPDATE" then if arg=="player" then Portrait() end
    elseif event=="PLAYER_EQUIPMENT_CHANGED" or arg=="player" then Sample() end
end)
