local _,TC=...
local white="Interface\\Buttons\\WHITE8X8"
function TC.StyleButton(button)
    button:SetBackdrop({bgFile=white,edgeFile=white,edgeSize=1})
    button:SetBackdropColor(0.27,0.26,0.23,1); button:SetBackdropBorderColor(0.52,0.47,0.37,1)
    local stone=button:CreateTexture(nil,"ARTWORK"); stone:SetPoint("TOPLEFT",1,-1); stone:SetPoint("BOTTOMRIGHT",-1,1)
    stone:SetColorTexture(1,1,1,1)
    if stone.SetGradient and CreateColor then
        stone:SetGradient("VERTICAL",CreateColor(0.21,0.21,0.19,1),CreateColor(0.34,0.32,0.27,1))
    else stone:SetColorTexture(0.27,0.26,0.23,1) end
    local text=button:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    text:SetPoint("CENTER"); text:SetTextColor(0.94,0.89,0.78); button:SetFontString(text)
    button:SetNormalFontObject("GameFontHighlight"); button:SetHighlightFontObject("GameFontHighlight")
    button:SetDisabledFontObject("GameFontDisable"); button:SetPushedTextOffset(0,-1)
    local shine=button:CreateTexture(nil,"HIGHLIGHT"); shine:SetAllPoints(); shine:SetColorTexture(1,1,1,0.09)
    button:SetHighlightTexture(shine)
    local bevel=button:CreateTexture(nil,"BORDER"); bevel:SetPoint("TOPLEFT",1,-1); bevel:SetPoint("TOPRIGHT",-1,-1)
    bevel:SetHeight(1); bevel:SetColorTexture(0.8,0.76,0.64,0.22)
    button.communeTheme="stone"
end
function TC.StyleEdit(box)
    box:SetBackdrop({bgFile=white,edgeFile=white,edgeSize=1})
    box:SetBackdropColor(0.86,0.80,0.69,1); box:SetBackdropBorderColor(0.62,0.53,0.38,1)
    box:SetFontObject("GameFontHighlight"); box:SetTextColor(0.20,0.16,0.11,1)
    box:SetTextInsets(8,8,4,4); box.communeTheme="ledger"
end
local windows={}
local function FrontWindow(frame)
    for i,window in ipairs(windows) do
        if window==frame then table.remove(windows,i); break end
    end
    windows[#windows+1]=frame
    -- Separate root frames by more than their child controls' offsets, so a
    -- lower window's labels cannot draw over the upper window's background.
    for i,window in ipairs(windows) do window:SetFrameLevel(i*100) end
end
function TC.StyleWindow(frame)
    frame:SetBackdropColor(0.12,0.11,0.09,1)
    frame:SetBackdropBorderColor(0.45,0.40,0.31,1)
    if frame:GetParent()==UIParent and not frame.communeWindowStacked then
        frame.communeWindowStacked=true
        FrontWindow(frame)
        frame:HookScript("OnShow",FrontWindow)
        frame:HookScript("OnMouseDown",FrontWindow)
    end
end
