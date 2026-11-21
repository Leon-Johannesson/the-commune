local _,TC=...
function TC.ApplyGuildAvailability(window)
    local available=TC.guildKey~=nil
    window.noGuild:SetShown(not available)
    window.sync:SetEnabled(available); window.funButton:SetEnabled(available)
    for name,tab in pairs(window.pageTabs) do tab:SetEnabled(available and window.activePage~=name) end
    if not available then
        window.hadNoGuild=true
        window.requestPage:Hide(); window.socialHost:Hide(); window.back:Hide(); window.new:Hide()
        window.sync:Show(); window.funButton:Show()
        for _,tab in pairs(window.pageTabs) do tab:Show() end
        for _,page in pairs(window.guildPages) do page:Hide() end
        window.save:SetEnabled(false); window.delete:SetEnabled(false)
        window.status:SetText("No guild")
        return false
    end
    if window.hadNoGuild then
        window.hadNoGuild=false; window.guildStateChanged=true; window.activePage="requests"
        window.requestPage:Show(); window.socialHost:Hide(); window.back:Hide(); window.new:Show()
        window.sync:Show(); window.funButton:Show()
        for name,tab in pairs(window.pageTabs) do tab:Show(); tab:SetEnabled(name~="requests") end
        for _,page in pairs(window.guildPages) do page:Hide() end
    end
    return true
end
