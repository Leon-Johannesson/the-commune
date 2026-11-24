local addonName,TC=...
local pending
local frame=CreateFrame("Frame")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent",function(_,event,name,action)
    if event=="ADDON_LOADED" then
        if name==addonName and pending and TC.db then TC.db.lastBlockedAction=pending; pending=nil end
        return
    end
    if (issecretvalue and (issecretvalue(name) or issecretvalue(action))) or name~=addonName then return end
    local entry={event=event,action=TC.Clean(action or "Unknown function",160),when=time(),version=TC.version}
    if TC.db then TC.db.lastBlockedAction=entry else pending=entry end
end)
function TC.DebugProtection()
    local entry=TC.db and TC.db.lastBlockedAction
    if entry then TC.Print("Last blocked action (v"..entry.version.."): "..entry.action.." ["..entry.event.."]") end
end

-- The debug reports run to a couple of dozen lines that people paste into
-- Discord, and chat-frame text cannot be selected. Collect what the debug
-- paths send to TC.Print instead of letting it scroll past in chat.
function TC.CaptureOutput(fn)
    local lines,chat={},TC.Print
    TC.Print=function(message) lines[#lines+1]=tostring(message or "") end
    local ok,err=pcall(fn)
    TC.Print=chat
    if not ok then lines[#lines+1]="Report failed: "..tostring(err) end
    return lines
end

local report
local function BuildReport()
    local f=CreateFrame("Frame","TheCommuneDebugWindow",UIParent,"BackdropTemplate")
    f:SetSize(640,470); f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    TC.StyleWindow(f)
    table.insert(UISpecialFrames,"TheCommuneDebugWindow")

    f.title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f.title:SetPoint("TOPLEFT",20,-18); f.title:SetTextColor(0.47,0.84,0.68)
    f.hint=f:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT",20,-40)
    f.hint:SetText("Already selected - press Ctrl+C to copy, Escape to close.")

    local close=CreateFrame("Button",nil,f,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-4,-4); close:SetScript("OnClick",function() f:Hide() end)

    f.scroll=CreateFrame("ScrollFrame",nil,f)
    f.scroll:SetPoint("TOPLEFT",18,-62); f.scroll:SetPoint("BOTTOMRIGHT",-38,18)
    f.box=CreateFrame("EditBox",nil,f.scroll)
    f.box:SetMultiLine(true); f.box:SetAutoFocus(false); f.box:SetWidth(584)
    f.box:SetFontObject("GameFontHighlightSmall")
    f.scroll:SetScrollChild(f.box)

    local bar=TC.AttachScrollBar(f,function(value) f.scroll:SetVerticalScroll(value) end)
    bar:SetPoint("TOPRIGHT",-18,-62); bar:SetPoint("BOTTOMRIGHT",-18,18); bar:SetWidth(12)
    -- A multi-line edit box sizes itself to its text, so the bar works in
    -- pixels here rather than the row counts the list pages use.
    local function Sync()
        bar.Refresh(math.floor(f.box:GetHeight() or 0),math.floor(f.scroll:GetHeight() or 1),
            math.floor(f.scroll:GetVerticalScroll() or 0))
    end
    f.Sync=Sync

    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel",function(self,delta)
        local range=self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0,math.min(range,(self:GetVerticalScroll() or 0)-delta*30)))
        Sync()
    end)
    f.box:SetScript("OnEscapePressed",function(self) self:ClearFocus(); f:Hide() end)
    -- A stray keypress must not change what the player is about to paste.
    f.box:SetScript("OnTextChanged",function(self,user)
        if user and self:GetText()~=(f.content or "") then self:SetText(f.content or ""); self:HighlightText() end
    end)
    f:SetScript("OnHide",function() f.box:ClearFocus() end)
    return f
end

local function Display(title,text)
    report=report or BuildReport()
    report.content=text
    report.title:SetText(title)
    report.box:SetText(text)
    report.scroll:SetVerticalScroll(0)
    report:Show()
    report.box:SetFocus(); report.box:HighlightText()
    report.Sync()
    -- The box reports its final height a frame after the text lands.
    C_Timer.After(0.05,function() if report:IsShown() then report.Sync() end end)
end

function TC.ShowReport(title,fn)
    local lines=TC.CaptureOutput(fn)
    if #lines==0 then lines[1]="No debug output was produced." end
    local text=table.concat(lines,"\n")
    -- A debug report is wanted most when something is already broken, so fall
    -- back to chat rather than losing the output with the window.
    if not pcall(Display,title,text) then
        for _,line in ipairs(lines) do TC.Print(line) end
    end
end
