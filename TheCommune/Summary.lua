local _, TC = ...
local bubble, state, currentStore
local function NumberOf(t)
    local count=0; for _ in pairs(t) do count=count+1 end; return count
end

local function StateForStore()
    TC.store.summaries=TC.store.summaries or {}
    local saved=TC.store.summaries[TC.owner]
    local first=not saved
    if not saved then
        saved={requests={},projects={},unreadRequests={},unreadProjects={}}
        TC.store.summaries[TC.owner]=saved
    end
    currentStore,state=TC.store,saved
    return first
end

function TC.UpdateSummary()
    if not TC.guildKey then if bubble then bubble:Hide() end; return end
    if not TC.store then return end
    local first=false
    if currentStore~=TC.store or not state then first=StateForStore() end
    local requests,projects,newArrival=0,0,false
    local activeRequests,activeProjects={},{}
    for owner,slots in pairs(TC.store.owners) do
        for slot,r in pairs(slots) do
            local key=owner..":"..slot
            local known=state.requests[key]
            local active=not not TC.IsActive(r)
            if active then
                requests=requests+1; activeRequests[key]=true
                local created=r.created or (known and known.created) or r.revision
                local createdKnown=r.created~=nil and r.createdKnown~=false
                local isNew=not known or not known.active or known.item~=r.item or (createdKnown and known.createdKnown and created>known.created)
                if isNew and not first and owner~=TC.owner then state.unreadRequests[key]=true; newArrival=true end
                state.requests[key]={created=math.max(created,known and known.created or 0),createdKnown=createdKnown,item=r.item,active=true}
            elseif known then known.active=false end
        end
    end
    for key,known in pairs(state.requests) do if not activeRequests[key] then known.active=false end end
    for id,p in pairs(TC.store.projects or {}) do
        if not p.deleted and p.received<p.quantity then
            projects=projects+1; activeProjects[id]=true
            if not state.projects[id] and not first and p.writer~=TC.owner then state.unreadProjects[id]=true; newArrival=true end
            state.projects[id]=true
        end
    end
    for key in pairs(state.unreadRequests) do if not activeRequests[key] then state.unreadRequests[key]=nil end end
    for id in pairs(state.unreadProjects) do if not activeProjects[id] then state.unreadProjects[id]=nil end end
    TC.summaryCounts={requests=requests,projects=projects,newRequests=NumberOf(state.unreadRequests),newProjects=NumberOf(state.unreadProjects)}
    if bubble then
        bubble.requests:SetText("Requests: "..requests); bubble.projects:SetText("Projects: "..projects)
        local parts={}
        local nr,np=TC.summaryCounts.newRequests,TC.summaryCounts.newProjects
        if nr>0 then parts[#parts+1]=nr.." new request"..(nr==1 and "" or "s") end
        if np>0 then parts[#parts+1]=np.." new project"..(np==1 and "" or "s") end
        bubble.news:SetText(table.concat(parts,"\n"))
        bubble.news:SetShown(#parts>0)
        local textHeight=#parts>1 and 30 or 16
        bubble.news:SetHeight(textHeight); bubble:SetSize(264,#parts>0 and 106+textHeight or 98)
        TC.UpdateSummaryDaily()
        if newArrival then bubble:Show() end
    end
end

function TC.UpdateSummaryDaily()
    if not bubble or not TC.guildKey then return end
    local answered,done=TC.DailyProgress()
    bubble.quiz:SetText("Quiz: "..answered.."/4")
    bubble.wordle:SetText("Wordle: "..(done and "Done" or "To do"))
end

function TC.DismissSummary()
    if state then state.unreadRequests={}; state.unreadProjects={} end
    if bubble then bubble:Hide() end
    TC.UpdateSummary()
end

local function Build()
    bubble=CreateFrame("Frame","TheCommuneSummary",UIParent,"BackdropTemplate")
    bubble:SetSize(264,98)
    local saved=TC.db.summaryPosition or {}
    local points={CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
    if points[saved.point] and points[saved.relativePoint] and tonumber(saved.x) and tonumber(saved.y) then
        bubble:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y)
    else bubble:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-38,-150) end
    bubble:SetFrameStrata("MEDIUM"); bubble:SetClampedToScreen(true); bubble:EnableMouse(true)
    bubble:SetMovable(true); bubble:RegisterForDrag("LeftButton")
    bubble:SetScript("OnDragStart",bubble.StartMoving)
    bubble:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local point,_,relativePoint,x,y=self:GetPoint(1)
        TC.db.summaryPosition={point=point,relativePoint=relativePoint,x=x,y=y}
    end)
    bubble:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3}})
    TC.RememberWindow(bubble,"summary",TC.db.summaryPosition,false)
    TC.StyleWindow(bubble)
    local title=bubble:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOPLEFT",14,-14); title:SetText("THE COMMUNE"); title:SetTextColor(0.47,0.84,0.68)
    local close=CreateFrame("Button",nil,bubble,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",0,0)
    close:SetScript("OnClick",TC.DismissSummary); bubble.close=close
    for i,page in ipairs({"requests","projects"}) do
        local button=CreateFrame("Button",nil,bubble,"BackdropTemplate")
        TC.StyleButton(button)
        button:SetSize(112,24); button:SetPoint("TOPLEFT",14+(i-1)*124,-36)
        button:SetScript("OnClick",function()
            SlashCmdList.THECOMMUNE(page)
            TC.DismissSummary()
        end); bubble[page]=button
    end
    for i,page in ipairs({"quiz","wordle"}) do
        local button=CreateFrame("Button",nil,bubble,"BackdropTemplate")
        TC.StyleButton(button)
        button:SetSize(112,24); button:SetPoint("TOPLEFT",14+(i-1)*124,-66)
        button:SetScript("OnClick",function() TC.OpenSocial(page); TC.DismissSummary() end); bubble[page]=button
    end
    bubble.news=bubble:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    bubble.news:SetPoint("TOPLEFT",14,-98); bubble.news:SetWidth(236); bubble.news:SetHeight(16)
    bubble.news:SetJustifyH("LEFT"); bubble.news:SetJustifyV("TOP"); bubble.news:SetWordWrap(true)
end

function TC.ShowSummary()
    if not TC.store or not TC.guildKey then return end
    if not bubble then Build() end
    TC.UpdateSummary(); bubble:Show()
end

function TC.StartSummary()
    TC.ShowSummary()
end
