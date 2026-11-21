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
