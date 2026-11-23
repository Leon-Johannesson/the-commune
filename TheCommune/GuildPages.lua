local _, TC = ...

local function CrafterMenu(page, H, onChoose)
    local shield=CreateFrame("Button",nil,page)
    shield:SetAllPoints(page)
    shield:SetFrameStrata("FULLSCREEN_DIALOG")
    shield:SetScript("OnClick",function(self) self:Hide() end)
    shield:Hide()
    page:HookScript("OnHide",function() shield:Hide() end)

    local menu=CreateFrame("Frame",nil,shield,"BackdropTemplate")
    menu:SetFrameLevel(shield:GetFrameLevel()+1)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    TC.StyleWindow(menu)
    menu:SetBackdropColor(0.12,0.11,0.09,1)
    local rows, options, offset, activeChoices = {}, {}, 0, nil
    local rowHeight, maxRows = 26, 7
    local Render
    local bar=TC.AttachScrollBar(menu,function(value) offset=value; Render() end)
    bar:SetWidth(10)
    bar:SetPoint("TOPRIGHT",menu,"TOPRIGHT",-4,-4)
    bar:SetPoint("BOTTOMRIGHT",menu,"BOTTOMRIGHT",-4,4)

    local function Scroll(_,delta)
        offset=offset-delta
        Render()
    end
    menu:SetScript("OnMouseWheel",Scroll)
    for i=1,maxRows do
        local row=H.Button(menu,"",function(self)
            shield:Hide()
            onChoose(self.option.value)
        end)
        row:SetHeight(rowHeight)
        row.label=H.Label(row,"",0,0)
        row.label:SetPoint("TOPLEFT",row,"TOPLEFT",8,-6)
        row.label:SetPoint("TOPRIGHT",row,"TOPRIGHT",-6,-6)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel",Scroll)
        rows[i]=row
    end

    Render=function()
        local visible=math.min(maxRows,#options)
        offset=math.max(0,math.min(offset,#options-visible))
        menu:SetHeight(visible*rowHeight+8)
        for i,row in ipairs(rows) do
            local option=i<=visible and options[offset+i] or nil
            row.option=option
            row:SetShown(option~=nil)
            if option then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",menu,"TOPLEFT",4,-4-(i-1)*rowHeight)
                row:SetPoint("TOPRIGHT",menu,"TOPRIGHT",#options>visible and -18 or -4,-4-(i-1)*rowHeight)
                local selected=option.value==page.crafter
                row.label:SetText(option.label)
                if selected then row.label:SetTextColor(0.47,0.84,0.68) else row.label:SetTextColor(0.94,0.89,0.78) end
            end
        end
        bar.Refresh(#options,visible,offset)
    end

    function menu.Open(anchor)
        page.search:ClearFocus()
        offset, activeChoices=0,nil
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-3)
        menu:SetPoint("TOPRIGHT",anchor,"BOTTOMRIGHT",0,-3)
        shield:Show()
    end

    function menu.Update(available)
        if not shield:IsShown() or available==activeChoices then return end
        activeChoices=available
        options={{label="All crafters"},{value=true,label="Craftable by guild"}}
        for _,option in ipairs(available) do options[#options+1]=option end
        Render()
    end

    return menu
end

function TC.BuildGuildPages(window,H)
    local Place,Label,Button,Edit,PlaceEdit=H.Place,H.Label,H.Button,H.Edit,H.PlaceEdit
    local pages={}
    window.guildPages=pages
    local function Page()
        local page=CreateFrame("Frame",nil,window); page:SetAllPoints(window); page:Hide()
        page.rows={}; page.offset=0
        page.search=Edit(page,"Search",80)
        page.search:SetScript("OnTextChanged",function() page.offset=0; if page.Update then page.Update() end end)
        page:EnableMouseWheel(true)
        page:SetScript("OnMouseWheel",function(_,delta) page.offset=page.offset-delta*3; page.Update() end)
        page.count=Label(page,"",0,0)
        page.scrollBar=TC.AttachScrollBar(page,function(value) page.offset=value; page.Update() end)
        return page
    end
    local function Row(page,i)
        local row=CreateFrame("Button",nil,page)
        local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1,1,1,i%2==0 and 0.045 or 0.015)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetTexCoord(0.07,0.93,0.07,0.93)
        row.a=Label(row,"",0,0); row.b=Label(row,"",0,0); row.c=Label(row,"",0,0)
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel",function(_,delta) page.offset=page.offset-delta*3; page.Update() end)
        row:SetScript("OnClick",function(self) if self.data then page.Select(self.data) end end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        return row
    end
    local function Fill(page,data,render)
        page.offset=math.max(0,math.min(page.offset,math.max(0,#data-page.visible)))
        for i,row in ipairs(page.rows) do
            local entry=i<=page.visible and data[page.offset+i] or nil
            row.data=entry
            if entry then render(row,entry); row:Show() else row:Hide() end
        end
        page.scrollBar.Refresh(#data,page.visible,page.offset)
    end

    local crafts=Page(); pages.crafts=crafts
    crafts.search.label:SetText("Search recipes, categories, or crafters")
    crafts.scan=Button(crafts,"Scan professions",function() TC.ScanProfessions(true) end)
    local function ResetCraftsList()
        crafts.offset,crafts.selected=0,nil
        crafts.Update()
    end
    crafts.search:SetScript("OnTextChanged",ResetCraftsList)
    local menu=CrafterMenu(crafts,H,function(value)
        crafts.crafter=value
        ResetCraftsList()
    end)
    local crafter=Button(crafts,"",function(self)
        menu.Open(self)
        menu.Update(TC.RecipeFilterOptions().crafter)
    end)
    crafter.label=Label(crafts,"Crafter",0,0)
    crafter.caption=Label(crafter,"",0,0)
    crafter.caption:SetPoint("TOPLEFT",crafter,"TOPLEFT",8,-6)
    crafter.caption:SetPoint("TOPRIGHT",crafter,"TOPRIGHT",-24,-6)
    local arrow=crafter:CreateTexture(nil,"ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetSize(18,18)
    arrow:SetPoint("RIGHT",crafter,"RIGHT",-3,0)
    crafts.crafterButton=crafter

    crafts.professionChecks={}
    local professionOptions
    local function UpdateProfessionChecks(options)
        if options==professionOptions then return end
        local previousCount=professionOptions and #professionOptions or 0
        professionOptions=options
        local selection={}
        for i,option in ipairs(options) do
            local check=crafts.professionChecks[i]
            if not check then
                check=CreateFrame("CheckButton",nil,crafts,"UICheckButtonTemplate")
                check.label=Label(check,"",0,0)
                check:SetScript("OnClick",function(self)
                    -- The row cache uses the selection table as a key.
                    local selection={}
                    for id in pairs(crafts.professions or {}) do selection[id]=true end
                    selection[self.professionID]=self:GetChecked() and true or nil
                    crafts.professions=next(selection) and selection or nil
                    ResetCraftsList()
                end)
                crafts.professionChecks[i]=check
            end
            check.professionID=option.value
            check.label:SetText(option.label)
            selection[option.value]=crafts.professions and crafts.professions[option.value] or nil
            check:SetChecked(selection[option.value] or false)
            check:Show()
        end
        crafts.professions=next(selection) and selection or nil
        for i=#options+1,#crafts.professionChecks do crafts.professionChecks[i]:Hide() end
        if #options~=previousCount then crafts.Layout() end
    end
    local function FilterLabel(options,value,default)
        for _,option in ipairs(options) do if option.value==value then return option.label end end
        return default
    end
    crafts.headers={Label(crafts,"RECIPE",0,0),Label(crafts,"PROFESSION",0,0),Label(crafts,"GUILD CRAFTERS",0,0)}
    crafts.details=Label(crafts,"",0,0)
    crafts.details:SetWordWrap(true); crafts.details:SetJustifyV("TOP")
    crafts.Select=function(entry)
        crafts.selected=entry.id
        local lines={entry.name.."  |  "..entry.profession..(entry.requiredSkill and ("  |  Required skill: "..entry.requiredSkill) or "  |  Required skill unknown")}
        local availability=TC.RecipeAvailabilityFor(entry)
        for i=1,math.min(8,#availability) do lines[#lines+1]=availability[i].text end
        if #availability>8 then lines[#lines+1]="More members listed in the recipe tooltip." end
        if #availability==0 then lines[#lines+1]="No guild profession data for this recipe yet." end
        if entry.source and entry.source~="" then lines[#lines+1]="Source: "..entry.source end
        crafts.details:SetText(table.concat(lines,"\n"))
    end
    crafts.Update=function()
        if window.activePage~="crafts" then return end
        if crafts.store~=TC.store then
            crafts.store=TC.store
            crafts.professions,crafts.crafter,crafts.offset,crafts.selected=nil,nil,0,nil
        end
        local choices=TC.RecipeFilterOptions()
        UpdateProfessionChecks(choices.profession)
        local owner=type(crafts.crafter)=="string" and crafts.crafter or nil
        crafts.crafterButton.caption:SetText(FilterLabel(choices.crafter,owner,
            owner and TC.DisplayName(owner) or (crafts.crafter and "Craftable by guild" or "All crafters")))
        menu.Update(choices.crafter)
        local query=crafts.search:GetText()
        local data=TC.RecipeRows(query,crafts.crafter==true,crafts.professions,owner)
        Fill(crafts,data,function(row,entry)
            row.icon:SetTexture(entry.icon); row.a:SetText(entry.name); row.b:SetText(entry.profession)
            local availability=not entry.craftable and TC.RecipeAvailabilityFor(entry) or nil
            row.c:SetText(entry.craftable and table.concat(entry.crafters,", ") or
                (availability[1] and availability[1].short or "No confirmed crafter"))
            row.c:SetTextColor(entry.craftable and 0.47 or 0.6,entry.craftable and 0.84 or 0.6,entry.craftable and 0.68 or 0.6)
            if crafts.selected==entry.id then crafts.Select(entry) end
        end)
        crafts.count:SetText(#data.." recipes")
        if #data==0 then
            crafts.details:SetText((query~="" or crafts.professions or crafts.crafter) and
                "No matching recipes." or "Open your profession and click Scan professions.")
        elseif not crafts.selected then crafts.details:SetText("") end
    end
    crafts.Layout=function()
        local w,h=window:GetWidth(),window:GetHeight(); local content=w-48
        Place(crafts.scan,w-290,-28,130,26)
        local searchW=math.floor(content*0.64)
        PlaceEdit(crafts.search,24,-106,searchW)
        PlaceEdit(crafts.crafterButton,24+searchW+12,-106,content-searchW-12)
        local columns=math.max(1,math.floor(content/140))
        local cellWidth=content/columns
        local optionCount=professionOptions and #professionOptions or 0
        for i=1,optionCount do
            local check=crafts.professionChecks[i]
            local column=(i-1)%columns
            local row=math.floor((i-1)/columns)
            Place(check,24+column*cellWidth,-156-row*22,22,22)
            Place(check.label,24,-5,cellWidth-30)
            check:SetHitRectInsets(0,22-cellWidth,0,0)
        end
        local gridHeight=optionCount>0 and math.ceil(optionCount/columns)*22+6 or 0
        local rowTop=182+gridHeight
        local recipeW,professionW=math.floor(content*0.42),math.floor(content*0.23)
        -- Reserve the bar's gutter even when it is hidden, so rows keep their
        -- width instead of reflowing as the result count crosses the page size.
        local rowW=content-18
        Place(crafts.headers[1],54,-160-gridHeight,recipeW-36); Place(crafts.headers[2],24+recipeW,-160-gridHeight,professionW-10)
        Place(crafts.headers[3],24+recipeW+professionW,-160-gridHeight,rowW-recipeW-professionW)
        crafts.visible=math.max(1,math.floor((h-225-rowTop)/30))
        for i=1,crafts.visible do
            if not crafts.rows[i] then crafts.rows[i]=Row(crafts,i) end
            local row=crafts.rows[i]; Place(row,24,-rowTop-(i-1)*30,rowW,30)
            Place(row.icon,0,-4,22,22); Place(row.a,30,-9,recipeW-38)
            Place(row.b,recipeW,-9,professionW-10); Place(row.c,recipeW+professionW,-9,rowW-recipeW-professionW)
            row:SetScript("OnEnter",function(self)
                if self.data then
                    GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetHyperlink("spell:"..self.data.id)
                    for _,member in ipairs(TC.RecipeAvailabilityFor(self.data)) do GameTooltip:AddLine(member.text,0.85,0.85,0.85,true) end
                    if self.data.source and self.data.source~="" then GameTooltip:AddLine("Source: "..self.data.source,0.85,0.85,0.85,true) end
                    GameTooltip:Show()
                end
            end)
        end
        Place(crafts.scrollBar,24+rowW+6,-rowTop,12,crafts.visible*30-4)
        Place(crafts.count,24,-h+213,content)
        Place(crafts.details,24,-h+186,content,148)
        crafts.details:SetFontObject("GameFontHighlightSmall")
    end

    local projects=Page(); pages.projects=projects
    projects.search.label:SetText("Search projects or descriptions")
    projects.new=Button(projects,"New project",function() projects.Select(nil) end)
    projects.closed=CreateFrame("CheckButton",nil,projects,"UICheckButtonTemplate")
    projects.closedLabel=Label(projects,"Include completed",0,0)
    projects.closed:SetScript("OnClick",function() projects.offset=0; projects.Update() end)
    projects.headers={Label(projects,"PROJECT",0,0),Label(projects,"PROGRESS",0,0),Label(projects,"LAST UPDATED BY",0,0)}
    projects.editor=CreateFrame("Frame",nil,projects)
    projects.title=Label(projects.editor,"New guild project",0,-8)
    local f={}; projects.fields=f
    f.title=Edit(projects.editor,"Project title",48)
    f.quantity=Edit(projects.editor,"Target",6); f.received=Edit(projects.editor,"Completed / received",6)
    f.item=Edit(projects.editor,"Optional item: link or ID (drag here)",255)
    f.item:SetScript("OnReceiveDrag",function()
        if TC.IsProjectOfficer(TC.owner)~=true then return end
        local kind,id=GetCursorInfo(); if kind=="item" then f.item:SetText(tostring(id)); ClearCursor() end
    end)
    f.description=CreateFrame("EditBox",nil,projects.editor,"BackdropTemplate")
    f.description.label=Label(projects.editor,"Description",0,0)
    f.description:SetMultiLine(true); f.description:SetAutoFocus(false); f.description:SetMaxLetters(240)
    f.description:SetFontObject("GameFontHighlight"); f.description:SetTextInsets(6,6,5,5)
    f.description:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8})
    TC.StyleEdit(f.description)
    f.description:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    projects.feedback=Label(projects.editor,"",0,0); projects.feedback:SetWordWrap(true); projects.feedback:SetJustifyV("TOP")
    projects.feedback:SetFontObject("GameFontHighlightSmall")
    local function Editable()
        local allowed=TC.IsProjectOfficer(TC.owner)==true
        for _,field in pairs(f) do field:SetEnabled(allowed) end
        projects.save:SetEnabled(allowed); projects.close:SetEnabled(allowed and projects.selected~=nil)
        projects.new:SetEnabled(allowed)
        return allowed
    end
    projects.Select=function(entry)
        projects.selected=entry and entry.id or nil
        local p=entry and entry.project
        projects.selectedRevision=p and p.revision or nil
        projects.title:SetText(p and p.title or "New guild project")
        f.title:SetText(p and p.title or ""); f.quantity:SetText(tostring(p and p.quantity or 1))
        f.received:SetText(tostring(p and p.received or 0)); f.item:SetText(p and p.item>0 and tostring(p.item) or "")
        f.description:SetText(p and p.description or "")
        projects.feedback:SetText(Editable() and "" or "View only. Creation and editing require guild officer privileges.")
    end
    projects.save=Button(projects.editor,"Save project",function()
        local text=f.item:GetText()
        local item=text=="" and 0 or (tonumber(text:match("item:(%d+)")) or tonumber(text))
        if item==nil then projects.feedback:SetText("Enter a valid optional item link or numeric ID."); return end
        local id,err=TC.SaveProject(projects.selected,{title=f.title:GetText(),quantity=f.quantity:GetText(),received=f.received:GetText(),
            description=f.description:GetText(),item=item,expectedRevision=projects.selectedRevision})
        if id then
            projects.Select({id=id,project=TC.store.projects[id]}); projects.feedback:SetText("Project saved and queued for guild sharing.")
        else projects.feedback:SetText(err) end
    end)
    projects.close=Button(projects.editor,"Close project",function()
        if projects.selected then
            local ok,err=TC.DeleteProject(projects.selected)
            if ok then projects.Select(nil); projects.feedback:SetText("Project closed.") else projects.feedback:SetText(err) end
        end
    end)
    projects.Update=function()
        if window.activePage~="projects" then return end
        local data=TC.ProjectRows(projects.search:GetText(),projects.closed:GetChecked())
        Fill(projects,data,function(row,entry)
            local p=entry.project
            local texture=p.item>0 and select(3,TC.ItemName(p.item)) or 134400
            row.icon:SetTexture(texture); row.a:SetText(p.title)
            row.b:SetText(p.received.." / "..p.quantity..(p.received>=p.quantity and " (complete)" or ""))
            row.c:SetText(TC.DisplayName(p.writer))
        end)
        projects.count:SetText(#data.." projects")
        Editable()
    end
    projects.Layout=function()
        local w,h=window:GetWidth(),window:GetHeight(); local content=w-48; local column=(content-24)/2; local numberW=(column-24)/2
        Place(projects.new,w-276,-28,116,26)
        PlaceEdit(projects.search,24,-106,content-250)
        Place(projects.closed,w-224,-122,26,26); Place(projects.closedLabel,w-192,-129,168)
        local titleW,progressW=math.floor(content*0.48),math.floor(content*0.24)
        local rowW=content-18
        Place(projects.headers[1],54,-160,titleW-36); Place(projects.headers[2],24+titleW,-160,progressW-10)
        Place(projects.headers[3],24+titleW+progressW,-160,rowW-titleW-progressW)
        local editorY=-h+290
        projects.visible=math.max(1,math.floor((h-290-28-182)/30))
        for i=1,projects.visible do
            if not projects.rows[i] then projects.rows[i]=Row(projects,i) end
            local row=projects.rows[i]; Place(row,24,-182-(i-1)*30,rowW,30)
            Place(row.icon,0,-4,22,22); Place(row.a,30,-9,titleW-38)
            Place(row.b,titleW,-9,progressW-10); Place(row.c,titleW+progressW,-9,rowW-titleW-progressW)
        end
        Place(projects.scrollBar,24+rowW+6,-182,12,projects.visible*30-4)
        Place(projects.count,24,editorY+25,content)
        Place(projects.editor,24,editorY,content,270)
        PlaceEdit(f.title,0,-32,column); PlaceEdit(f.quantity,column+24,-32,numberW)
        PlaceEdit(f.received,column+48+numberW,-32,numberW)
        PlaceEdit(f.item,0,-108,column)
        Place(f.description.label,column+24,-108,column)
        -- A multi-line EditBox resizes its own height to fit the text whenever
        -- its width changes, so SetHeight loses that fight once per frame while
        -- the window is being dragged. Opposing anchors pin the box instead.
        f.description:ClearAllPoints()
        f.description:SetPoint("TOPLEFT",column+24,-128)
        f.description:SetPoint("BOTTOMRIGHT",projects.editor,"TOPLEFT",column+24+column,-202)
        Place(projects.feedback,0,-210,column,34)
        Place(projects.save,content-296,-210,140,26); Place(projects.close,content-140,-210,140,26)
    end
    projects.Select(nil)

end
