local _,TC=...
local enemies,serial={},0
local prompt
local lastRecap
local function Safe(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b=pcall(fn,...)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return end
    return a,b
end
local function Field(row,key) return Safe(function() return row[key] end) end
function TC.ObserveDeathEnemy(unit)
    if not TC.guildKey or Safe(UnitIsPlayer,unit)~=true then return end
    local faction=Safe(UnitFactionGroup,unit); local own=Safe(UnitFactionGroup,"player")
    local guid=Safe(UnitGUID,unit)
    if type(guid)~="string" then return end
    if own and faction==own then enemies[guid]=nil; return end
    if not own or (faction~="Horde" and faction~="Alliance") or own==faction then return end
    local first,last=Safe(UnitFullName,unit)
    if type(guid)~="string" or not guid:match("^Player%-") or type(first)~="string" then return end
    if last and last:match("^CAMWOW") and not first:find(" ",1,true) then return end
    local canonical=TC.NormalizeName(first..(last and last~="" and ("-"..last) or ""))
    local name=canonical and canonical:gsub("%-"," ")
    if not TC.PlayerKey(name) then return end
    for key,r in pairs(enemies) do if GetTime()-r.when>300 then enemies[key]=nil end end
    local count=0; for _ in pairs(enemies) do count=count+1 end
    if count<256 or enemies[guid] then enemies[guid]={name=TC.Clean(name,90),faction=faction,when=GetTime()} end
end
function TC.HideDeathPrompt()
    serial=serial+1
    if prompt then prompt:Hide() end
end
local function OnHitlist(name)
    local target=TC.PlayerKey(name)
    for _,entry in ipairs(TC.HitRows()) do if entry.hit.target==target then return true end end
end
function TC.ShowDeathPrompt(name)
    if not TC.guildKey or OnHitlist(name) then return end
    if not prompt then
        prompt=CreateFrame("Frame","TheCommuneDeathPrompt",UIParent,"BackdropTemplate")
        prompt:SetSize(360,126); prompt:SetPoint("CENTER",UIParent,"CENTER",0,140); prompt:SetFrameStrata("DIALOG")
        prompt:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
        TC.StyleWindow(prompt); TC.RememberWindow(prompt,"deathPrompt",nil,true)
        table.insert(UISpecialFrames,"TheCommuneDeathPrompt")
        prompt.text=prompt:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        prompt.text:SetPoint("TOPLEFT",16,-20); prompt.text:SetSize(320,48); prompt.text:SetJustifyH("CENTER"); prompt.text:SetWordWrap(true)
        local close=CreateFrame("Button",nil,prompt,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT"); close:SetScript("OnClick",TC.HideDeathPrompt)
        prompt.add=CreateFrame("Button",nil,prompt,"BackdropTemplate"); TC.StyleButton(prompt.add)
        prompt.add:SetSize(150,28); prompt.add:SetPoint("BOTTOMLEFT",18,16); prompt.add:SetText("Add to hitlist")
        prompt.add:SetScript("OnClick",function()
            if prompt.store~=TC.store or not TC.guildKey then TC.HideDeathPrompt(); return end
            if OnHitlist(prompt.killer) then TC.HideDeathPrompt(); return end
            local slot,err=TC.SaveHit(nil,prompt.killer,"Killed me")
            if slot then TC.HideDeathPrompt() else prompt.text:SetText(err) end
        end)
        prompt.cancel=CreateFrame("Button",nil,prompt,"BackdropTemplate"); TC.StyleButton(prompt.cancel)
        prompt.cancel:SetSize(150,28); prompt.cancel:SetPoint("BOTTOMRIGHT",-18,16); prompt.cancel:SetText("Dismiss"); prompt.cancel:SetScript("OnClick",TC.HideDeathPrompt)
    end
    prompt.killer=name; prompt.store=TC.store
    prompt.text:SetText(name.." killed you.\nAdd them to the guild hitlist?"); prompt:Show()
end
local function ReadKiller(deathTime)
    local events=C_DeathRecap and Safe(C_DeathRecap.GetRecapEvents)
    if type(events)~="table" or (issecrettable and issecrettable(events)) then return end
    local row=Field(events,1)
    if type(row)~="table" or (issecrettable and issecrettable(row)) then return end
    local guid=Field(row,"sourceGUID"); local overkill=Field(row,"overkill"); local stamp=Field(row,"timestamp")
    if type(guid)~="string" or not guid:match("^Player%-") or type(overkill)~="number" or overkill<0 or type(stamp)~="number" or math.abs(stamp-deathTime)>3 then return end
    local signature=guid..":"..stamp
    if signature==lastRecap then return end
    local enemy=enemies[guid]
    local own=Safe(UnitFactionGroup,"player")
    if own and enemy and GetTime()-enemy.when<=300 and enemy.faction~=own then lastRecap=signature; return enemy.name end
end
local frame=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_DEAD","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","NAME_PLATE_UNIT_ADDED","PLAYER_GUILD_UPDATE"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,unit)
    if not TC.store then return end
    if event=="PLAYER_GUILD_UPDATE" then
        if not TC.guildKey then TC.HideDeathPrompt() end; return
    end
    if not TC.guildKey then return end
    if event=="PLAYER_DEAD" then
        TC.HideDeathPrompt(); local token=serial; local owner,store=TC.owner,TC.store
        local deathTime=Safe(GetServerTime) or time()
        TC.ObserveDeathEnemy("target"); TC.ObserveDeathEnemy("mouseover")
        local tries=0
        local function Check()
            if token~=serial or store~=TC.store or owner~=TC.owner or not TC.guildKey then return end
            tries=tries+1
            local name=ReadKiller(deathTime)
            if name then TC.ShowDeathPrompt(name); return end
            if tries<16 then C_Timer.After(0.5,Check) end
        end
        C_Timer.After(0.5,Check)
    elseif event=="PLAYER_TARGET_CHANGED" then TC.ObserveDeathEnemy("target")
    elseif event=="UPDATE_MOUSEOVER_UNIT" then TC.ObserveDeathEnemy("mouseover")
    elseif event=="NAME_PLATE_UNIT_ADDED" then TC.ObserveDeathEnemy(unit) end
end)
