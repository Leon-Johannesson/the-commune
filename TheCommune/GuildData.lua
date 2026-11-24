local _, TC = ...
local craftStages, projectStages, deferred = {}, {}, {}
local scanScheduled = false
TC.craftStatus = "Open each profession once to scan recipes."

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function Parts(text)
    local result = {}
    for part in (text .. "\t"):gmatch("(.-)\t") do result[#result + 1] = part end
    return result
end

local function Revision(old)
    return math.max(time(), (old or 0) + 1)
end

local function ValidRevision(value)
    local n = TC.Integer(value, 1, 9999999999)
    return n and n <= time() + 86400 and n or nil
end

-- Building the recipe list walks the whole catalog, asking the client for a
-- spell name and a profession name per entry. TC.Refresh runs on every synced
-- packet, every item-info event and once per frame while the window resizes,
-- so the list is built once per data change and filtered from the cache after.
local entryCache, rowCache, filterOptions
function TC.InvalidateRecipes() entryCache, rowCache, filterOptions = nil, nil, nil end
function TC.InvalidateRecipeSearch() rowCache = nil end

local function RefreshRecipes()
    TC.InvalidateRecipes()
    if TC.QueueRefresh then TC.QueueRefresh() end
end

local function RefreshProjects()
    if TC.UpdateSummary then TC.UpdateSummary() end
    if TC.Refresh then TC.Refresh() end
end

function TC.InitGuildData()
    TC.store.crafts = TC.store.crafts or {}
    TC.store.catalog = TC.store.catalog or {}
    TC.store.professionNames = TC.store.professionNames or {}
    TC.store.projects = TC.store.projects or {}
    TC.store.crafts[TC.owner] = TC.store.crafts[TC.owner] or { professions = {}, revision = 0 }
end

local officerRanks = {generation = -1}

-- Officer privileges are a guild permission, not a specific rank number/name.
-- The Blizzard guild rank editor's OfficerCheckbox uses permission flag 22.
function TC.IsProjectOfficer(owner)
    if not TC.guildKey then return false end
    local rank
    if owner == TC.owner then
        local _, _, ownRank = GetGuildInfo("player")
        rank = ownRank
    else
        local member = TC.GuildRoster()[owner]
        rank = member and member.rank
    end
    if rank == nil then return nil end -- Wait for a usable roster; never trust the packet's claim.
    if rank == 0 then return true end
    -- Rank flags are a per-rank property, so query them once per roster change
    -- rather than on every permission check the UI makes while refreshing.
    if officerRanks.generation ~= TC.rosterGeneration then officerRanks = {generation = TC.rosterGeneration} end
    local known = officerRanks[rank]
    if known == nil then
        local flags = C_GuildInfo and Call(C_GuildInfo.GuildControlGetRankFlags, rank + 1)
        if type(flags) ~= "table" then return nil end
        known = flags[22] == true
        officerRanks[rank] = known
    end
    return known
end

local function ProfessionName(id)
    local api = C_TradeSkillUI
    local info = api and Call(api.GetProfessionInfoBySkillLineID, id)
    return (type(info) == "table" and (info.professionName or info.parentProfessionName or info.name)) or
        (TC.store and TC.store.professionNames[id])
end

local pendingSpells = {}

local function RecipeName(id)
    local info = C_Spell and Call(C_Spell.GetSpellInfo, id)
    if type(info) == "table" and info.name then return info.name, info.iconID or 134400 end
    local name = C_Spell and Call(C_Spell.GetSpellName, id)
    if name then return name, 134400 end
    if not pendingSpells[id] and C_Spell and C_Spell.RequestLoadSpellData then
        pendingSpells[id] = pcall(C_Spell.RequestLoadSpellData, id) or nil
    end
    return "Recipe #" .. id, 134400
end

local function AddCatalog(profession, recipes)
    for id in pairs(recipes) do
        if not TC.store.catalog[id] then
            TC.store.catalog[id] = {profession = profession}
            TC.InvalidateRecipes()
        end
    end
end

local function EncodeRecipes(recipes)
    local ids = {}
    for id in pairs(recipes) do ids[#ids + 1] = id end
    table.sort(ids)
    local chunks, current = {}, ""
    for _, id in ipairs(ids) do
        local token = id .. ":" .. (recipes[id] and "1" or "0")
        if #current + #token + 1 > 190 then chunks[#chunks + 1] = current; current = "" end
        current = current == "" and token or (current .. "," .. token)
    end
    if current ~= "" or #chunks == 0 then chunks[#chunks + 1] = current end
    return chunks
end

function TC.ProfessionPackets(id, profession)
    local packets={}
    local chunks = EncodeRecipes(profession.recipes)
    packets[1]=table.concat({"CB", id, profession.revision, #chunks,
        TC.Clean(profession.name, 48), profession.rank, profession.maxRank}, "\t")
    for index, chunk in ipairs(chunks) do
        packets[#packets+1]=table.concat({"CC", id, profession.revision, index, chunk}, "\t")
    end
    return packets
end
local function BroadcastProfession(id,profession)
    for index,packet in ipairs(TC.ProfessionPackets(id,profession)) do
        local key=index==1 and ("craft-head:"..id) or ("craft:"..id..":"..(index-1))
        TC.QueueGuildPacket(key,packet)
    end
end

local scanDiagnostics = {}
local function ScanCall(name, ...)
    local fn=C_TradeSkillUI and C_TradeSkillUI[name]
    if type(fn)~="function" then scanDiagnostics[name]="unavailable"; return nil end
    local ok,value=pcall(fn,...)
    if not ok then scanDiagnostics[name]="error: "..TC.Clean(value,100); return nil end
    if type(value)=="table" then
        local count=0; for _ in pairs(value) do count=count+1 end
        scanDiagnostics[name]="table ("..count.." entries)"
    else scanDiagnostics[name]=tostring(value) end
    return value
end

local function MatchesProfession(info,line,name)
    return type(info)=="table" and (info.professionID==line or info.parentProfessionID==line or
        info.skillLineID==line or info.parentProfessionSkillLineID==line or
        info.professionName==name or info.parentProfessionName==name or info.name==name)
end

local function RecipeBelongs(id,line,name)
    local fn=C_TradeSkillUI.GetTradeSkillLineForRecipe
    if type(fn)~="function" then return true end
    local ok,child,recipeName,parent=pcall(fn,id)
    if not ok or not child then return true end
    return child==line or parent==line or recipeName==name
end

function TC.DebugCrafts()
    TC.Print("Craft scan v"..TC.version..": "..TC.craftStatus)
    for _,name in ipairs({"GetBaseProfessionInfo","GetChildProfessionInfo","GetProfessionSpells","GetAllRecipeIDs","GetFilteredRecipeIDs","IsDataSourceChanging"}) do
        local available=C_TradeSkillUI and type(C_TradeSkillUI[name])=="function"
        TC.Print(name..": "..(scanDiagnostics[name] or (available and "available; not read this scan" or "unavailable")))
    end
    TC.Print("Open profession: "..(scanDiagnostics.open or "unknown").." | matched roster entries: "..(scanDiagnostics.matched or 0))
end

function TC.ScanProfessions(manual)
    if not TC.store then return end
    scanDiagnostics={}
    local api=C_TradeSkillUI
    if not api or not GetProfessions or not GetProfessionInfo then
        TC.craftStatus="Profession API unavailable on this client."
        if manual then TC.Print(TC.craftStatus) end
        return
    end
    local changing=ScanCall("IsDataSourceChanging")
    local foreign=Call(api.IsTradeSkillLinked) or Call(api.IsTradeSkillGuild) or Call(api.IsTradeSkillGuildMember) or Call(api.IsNPCCrafting)
    if changing or foreign then
        TC.craftStatus=changing and "Profession data is changing; waiting for its recipe list." or "Linked/NPC profession view ignored. Open your own profession."
        if manual then TC.Print(TC.craftStatus) end
        return
    end
    local mine=TC.store.crafts[TC.owner]
    local indices={GetProfessions()}
    local base=ScanCall("GetBaseProfessionInfo")
    local child=ScanCall("GetChildProfessionInfo")
    local display=Call(api.GetTradeSkillDisplayName)
    scanDiagnostics.open=type(base)=="table" and ((base.professionName or base.name or "unnamed").." #"..tostring(base.professionID)) or "none"
    if type(child)=="table" then scanDiagnostics.open=scanDiagnostics.open.." / child #"..tostring(child.professionID) end
    local seen,changed,observed,partial={},false,0,false
    for slot=1,6 do
        local index=indices[slot]
        if index then
            local name,_,rank,maxRank,_,_,line=GetProfessionInfo(index)
            if TC.Integer(line,1,2147483647) then
                seen[line]=true
                local previous=mine.professions[line]
                local info=Call(api.GetProfessionInfoBySkillLineID,line)
                local isOpen=MatchesProfession(base,line,name) or MatchesProfession(child,line,name) or (type(display)=="string" and display==name)
                if isOpen then scanDiagnostics.matched=(scanDiagnostics.matched or 0)+1 end
                if type(info)~="table" then
                    if MatchesProfession(child,line,name) then info=child
                    elseif MatchesProfession(base,line,name) then info=base end
                end
                local known=type(info)=="table" and info.profession and ScanCall("GetProfessionSpells",info.profession,info.professionID or line)
                local knownSet,knownCount={},0
                if type(known)=="table" then
                    for _,id in pairs(known) do
                        if TC.Integer(id,1,2147483647) and RecipeBelongs(id,line,name) then knownSet[id]=true; knownCount=knownCount+1 end
                    end
                end
                local ids,complete
                if isOpen then
                    ids=ScanCall("GetAllRecipeIDs")
                    complete=type(ids)=="table" and next(ids)~=nil
                    if not complete then
                        ids=ScanCall("GetFilteredRecipeIDs")
                        complete=false
                        if type(ids)=="table" and next(ids) then partial=true end
                    end
                end
                -- An empty GetProfessionSpells result is not an authoritative
                -- empty profession in Forever. The open window's recipe info is
                -- the primary source; filtered lists are always merged partially.
                local recipes={}
                local authoritative=knownCount>0 or complete
                if previous then
                    for id,learned in pairs(previous.recipes) do recipes[id]=not authoritative and learned or false end
                end
                for id in pairs(knownSet) do recipes[id]=true end
                local read=0
                if type(ids)=="table" then
                    for _,id in pairs(ids) do
                        if TC.Integer(id,1,2147483647) and RecipeBelongs(id,line,name) then
                            local raw=Call(api.GetRecipeInfo,id)
                            local infos=type(raw)=="table" and ((raw.recipeID or raw.learned~=nil or raw.name) and {raw} or raw) or {}
                            for _,recipe in pairs(infos) do
                                if type(recipe)=="table" then
                                    local recipeID=TC.Integer(recipe.recipeID or id,1,2147483647)
                                    if recipeID and RecipeBelongs(recipeID,line,name) then
                                        if TC.CaptureRecipeRequirements and TC.CaptureRecipeRequirements(recipeID,line,recipe,name) then changed=true end
                                        if type(recipe.learned)=="boolean" then recipes[recipeID]=recipe.learned
                                        elseif knownSet[recipeID] then recipes[recipeID]=true
                                        elseif recipes[recipeID]==nil then recipes[recipeID]=false end
                                        read=read+1
                                    end
                                end
                            end
                        end
                    end
                end
                observed=observed+read+knownCount
                -- Never replace a populated cache with an empty/not-ready API
                -- response. Explicit visible learned=false entries still update.
                if read>0 or knownCount>0 then
                    local signature=table.concat(EncodeRecipes(recipes),";")..":"..(rank or 0)..":"..(maxRank or 0)
                    if not previous or previous.signature~=signature then
                        local profile={name=TC.Clean(name or ProfessionName(line) or ("Profession #"..line),48),
                            rank=rank or 0,maxRank=maxRank or 0,recipes=recipes,revision=Revision(previous and previous.revision),signature=signature}
                        mine.professions[line]=profile; TC.store.professionNames[line]=profile.name; changed=true
                    end
                    AddCatalog(line,recipes)
                end
            end
        end
    end
    if next(seen) then
        for id in pairs(mine.professions) do if not seen[id] then mine.professions[id]=nil; changed=true end end
        if changed then mine.revision=Revision(mine.revision) end
    end
    local count=0
    for _,profile in pairs(mine.professions) do for _,learned in pairs(profile.recipes) do if learned then count=count+1 end end end
    if observed==0 then
        TC.craftStatus=count>0 and (count.." learned recipes cached. Open a profession to refresh; /commune craftsdebug") or
            "No recipes read. Keep a profession open, clear its filters, then Scan. /commune craftsdebug"
    else
        TC.craftStatus=count.." learned recipes cached. "..(partial and "Visible recipes merged; clear profession filters to scan more." or "Own profession recipes scanned.")
    end
    if manual then TC.Print(TC.craftStatus) end
    if changed then
        TC.BroadcastCrafts()
        RefreshRecipes()
    else
        -- Opening a profession can expose output data for an existing recipe.
        TC.InvalidateRecipeSearch()
        if TC.QueueRefresh then TC.QueueRefresh() end
    end
end

function TC.BroadcastCrafts()
    if TC.HasGuildPeer and not TC.HasGuildPeer() then return end
    local mine = TC.store.crafts[TC.owner]
    if mine.revision<1 then return end
    local lines = {}
    for line, profile in pairs(mine.professions) do
        lines[#lines + 1] = line
    end
    table.sort(lines)
    TC.QueueGuildPacket("craft-roster", "CL\t" .. mine.revision .. "\t" .. table.concat(lines, ","))
    for _,line in ipairs(lines) do BroadcastProfession(line,mine.professions[line]) end
    if TC.BroadcastRecipeMetadata then
        for _,line in ipairs(lines) do
            for id in pairs(mine.professions[line].recipes) do
                local entry=TC.store.catalog[id]
                if entry then TC.BroadcastRecipeMetadata(id,entry) end
            end
        end
    end
end

local function SortFilterOptions(options)
    table.sort(options, function(a,b)
        if a.order == b.order then return a.value < b.value end
        return a.order < b.order
    end)
end

local function BuildEntries()
    if entryCache then return entryCache end
    local crafters = {}
    for owner, profile in pairs(TC.store.crafts) do
        for _, profession in pairs(profile.professions) do
            for id, learned in pairs(profession.recipes) do
                local meta=TC.store.catalog[id]
                if learned and (not meta or not meta.requiredSkill or profession.rank>=meta.requiredSkill) then
                    crafters[id] = crafters[id] or {}; crafters[id][owner] = true
                end
            end
        end
    end
    entryCache = {}
    local professionNames, crafterNames, nameCounts = {}, {}, {}
    for id, entry in pairs(TC.store.catalog) do
        local names, knownBy = {}, crafters[id]
        if knownBy then
            for owner in pairs(knownBy) do
                local display = crafterNames[owner]
                if not display then
                    display = TC.DisplayName(owner)
                    crafterNames[owner] = display
                    nameCounts[display] = (nameCounts[display] or 0) + 1
                end
                names[#names + 1] = display
            end
        end
        table.sort(names)
        local name, icon = RecipeName(id)
        local profession = professionNames[entry.profession] or ProfessionName(entry.profession)
        if not profession then
            for _, profile in pairs(TC.store.crafts) do
                if profile.professions[entry.profession] then profession = profile.professions[entry.profession].name; break end
            end
        end
        profession = profession or ("Profession #" .. entry.profession)
        professionNames[entry.profession] = profession
        entryCache[#entryCache + 1] = {id=id, name=name, icon=icon, profession=profession, crafters=names,
            craftable=#names > 0, knownBy=knownBy, meta=entry, requiredSkill=entry.requiredSkill,
            sourceKind=entry.sourceKind, source=entry.source,
            text=(name .. " " .. profession .. " " .. table.concat(names, " ")):lower()}
    end
    table.sort(entryCache, function(a,b) if a.craftable ~= b.craftable then return a.craftable end
        if a.name == b.name then return a.id < b.id end return a.name < b.name end)
    local professions, owners = {}, {}
    for id, name in pairs(professionNames) do
        -- Skinning is primarily gathering. Its entries remain searchable in Crafts.
        if id~=393 then professions[#professions + 1] = {value=id, label=name, order=name:lower()} end
    end
    for owner, name in pairs(crafterNames) do
        local label = nameCounts[name] > 1 and (name .. " (" .. owner .. ")") or name
        owners[#owners + 1] = {value=owner, label=label, order=label:lower()}
    end
    SortFilterOptions(professions)
    SortFilterOptions(owners)
    filterOptions = {profession=professions, crafter=owners}
    return entryCache
end

function TC.RecipeFilterOptions()
    BuildEntries()
    return filterOptions
end

-- Availability is a pass over every crafter, so it waits until a row is shown
-- or hovered. The result rides on the entry and dies with the cache.
function TC.RecipeAvailabilityFor(entry)
    if not entry.availability then
        entry.availability = (TC.RecipeAvailability and TC.RecipeAvailability(entry.id, entry.meta)) or {}
    end
    return entry.availability
end

function TC.RecipeRows(query, onlyCraftable, professions, crafter)
    query = (query or ""):match("^%s*(.-)%s*$"):lower()
    onlyCraftable = onlyCraftable and true or false
    professions = professions and next(professions) and professions or nil
    if rowCache and rowCache.query == query and rowCache.only == onlyCraftable and
        rowCache.professions == professions and rowCache.crafter == crafter then return rowCache.result end
    local result = {}
    -- Entries are already in display order, so the filter keeps it.
    for _, entry in ipairs(BuildEntries()) do
        if (not professions or professions[entry.meta.profession]) and
            (not onlyCraftable or entry.craftable) and (not crafter or (entry.knownBy and entry.knownBy[crafter])) and
            TC.RecipeMatches(query, entry.text, entry.name, entry.id) then
            result[#result + 1] = entry
        end
    end
    rowCache = {query=query, only=onlyCraftable, professions=professions, crafter=crafter, result=result}
    return result
end

function TC.SaveProject(id, data)
    if TC.IsProjectOfficer(TC.owner) ~= true then return nil, "Project editing requires guild officer privileges (or guild leader)." end
    local title = TC.Clean(data.title,48)
    local item = (data.item == nil or data.item == "") and 0 or tonumber(data.item)
    local quantity = TC.Integer(data.quantity,1,999999)
    local received = TC.Integer(data.received,0,999999)
    if title == "" or not quantity or not received or received > quantity or not TC.Integer(item,0,2147483647) then
        return nil, "Enter a title, target 1-999999, progress 0-target, and an optional valid item ID."
    end
    if not id then
        local active = 0
        for _, p in pairs(TC.store.projects) do if not p.deleted and p.received < p.quantity then active = active + 1 end end
        if active >= 50 then return nil, "There are already 50 active guild projects." end
        TC.store.projectSequence = (TC.store.projectSequence or 0) + 1
        local guid = UnitGUID and UnitGUID("player")
        if not guid then
            local hash = 5381
            for i=1,#TC.owner do hash=(hash*33+TC.owner:byte(i))%2147483647 end
            guid = "local-" .. hash
        end
        id = guid .. "-" .. time() .. "-" .. TC.store.projectSequence
    end
    local previous = TC.store.projects[id]
    if previous and data.expectedRevision and previous.revision~=data.expectedRevision then
        return nil,"This project changed since you opened it. Select it again before saving."
    end
    TC.store.projects[id] = {revision=Revision(previous and previous.revision), writer=TC.owner,
        title=title, description=TC.Clean(data.description,240), item=item, quantity=quantity, received=received}
    TC.BroadcastProject(id, TC.store.projects[id]); RefreshProjects()
    return id
end

function TC.DeleteProject(id)
    if TC.IsProjectOfficer(TC.owner) ~= true or not TC.store.projects[id] then return nil, "Only guild officers can close projects." end
    local old = TC.store.projects[id]
    TC.store.projects[id] = {deleted=true,revision=Revision(old.revision),writer=TC.owner}
    TC.BroadcastProject(id,TC.store.projects[id]); RefreshProjects(); return true
end

function TC.ProjectRows(query, includeClosed)
    local result = {}
    query = (query or ""):match("^%s*(.-)%s*$"):lower()
    for id,p in pairs(TC.store.projects) do
        if not p.deleted and (includeClosed or p.received < p.quantity) and
            (query == "" or (p.title .. " " .. p.description .. " " .. TC.DisplayName(p.writer)):lower():find(query,1,true)) then
            result[#result+1] = {id=id, project=p}
        end
    end
    table.sort(result,function(a,b)
        local ac,bc = a.project.received < a.project.quantity,b.project.received < b.project.quantity
        if ac ~= bc then return ac end
        if a.project.title == b.project.title then return a.id < b.id end
        return a.project.title < b.project.title
    end)
    return result
end

function TC.BroadcastProject(id,p)
    if TC.IsProjectOfficer(TC.owner) ~= true then return end
    local body = table.concat({"1",p.revision,p.writer,p.deleted and "1" or "0",p.title or "",p.item or 0,
        p.quantity or 1,p.received or 0,p.description or ""},"\t")
    local chunks={}
    while #body>0 do
        local cut=math.min(140,#body)+1
        while cut>1 and (body:byte(cut) or 0)>=128 and (body:byte(cut) or 0)<192 do cut=cut-1 end
        chunks[#chunks+1]=body:sub(1,cut-1); body=body:sub(cut)
    end
    for part,chunk in ipairs(chunks) do
        TC.QueueGuildPacket("project:"..id..":"..part,table.concat({"PX",id,p.revision,part,#chunks,chunk},"\t"))
    end
end

function TC.BroadcastProjects()
    if TC.IsProjectOfficer(TC.owner) == true then
        for id,p in pairs(TC.store.projects) do TC.BroadcastProject(id,p) end
    end
end

function TC.BroadcastGuildData()
    if TC.HasGuildPeer and not TC.HasGuildPeer() then return end
    TC.BroadcastCrafts()
    if TC.BroadcastSocial then TC.BroadcastSocial() end
    TC.BroadcastProjects()
end

local function ApplyProject(id,body,sender)
    local f = Parts(body)
    local revision = ValidRevision(f[2])
    if #f ~= 9 or f[1] ~= "1" or not revision or not f[3] or #f[3]>100 or TC.NormalizeName(f[3])~=f[3] or
        (f[4] ~= "0" and f[4] ~= "1") then return end
    local permission = TC.IsProjectOfficer(sender)
    if permission == nil then
        local count=0; for _ in pairs(deferred) do count=count+1 end
        if count<50 then deferred[id] = {body=body,sender=sender,store=TC.store,when=GetTime()} end
        return
    elseif not permission then return end
    local p = {revision=revision,writer=f[3],deleted=f[4]=="1",title=TC.Clean(f[5],48),
        item=TC.Integer(f[6],0,2147483647),quantity=TC.Integer(f[7],1,999999),received=TC.Integer(f[8],0,999999),description=TC.Clean(f[9],240)}
    if not p.item or not p.quantity or not p.received or p.received>p.quantity or (not p.deleted and p.title=="") then return end
    local old=TC.store.projects[id]
    if not old or revision>old.revision or (revision==old.revision and p.writer>old.writer) or
        (revision==old.revision and p.writer==old.writer and p.deleted and not old.deleted) then
        TC.store.projects[id]=p; RefreshProjects()
    end
end

local function PruneStages(stages)
    local count=0
    for key,stage in pairs(stages) do
        if stage.store~=TC.store or GetTime()-stage.when>180 then stages[key]=nil else count=count+1 end
    end
    return count
end

function TC.ReceiveGuildData(message,sender)
    if TC.ReceiveSocial and TC.ReceiveSocial(message,sender) then return true end
    if type(message)~="string" or #message>254 then return true end
    local kind=message:match("^([^\t]+)")
    if kind=="CM" then if TC.ReceiveRecipeMetadata then TC.ReceiveRecipeMetadata(message,sender) end; return true end
    if kind=="CL" then
        local f=Parts(message); local revision=ValidRevision(f[2])
        if #f~=3 or not revision then return true end
        local roster={}; local count=0
        for token in f[3]:gmatch("[^,]+") do
            local id=TC.Integer(token,1,2147483647); count=count+1
            if not id or count>12 then return true end
            roster[id]=true
        end
        local profile=TC.store.crafts[sender] or {professions={},revision=0}
        TC.store.crafts[sender]=profile
        if revision>profile.revision then
            profile.revision=revision; profile.roster=roster
            for id in pairs(profile.professions) do if not roster[id] then profile.professions[id]=nil end end
            RefreshRecipes()
        end
        return true
    elseif kind=="CB" or kind=="CC" then
        local f=Parts(message)
        local line=TC.Integer(f[2],1,2147483647); local revision=ValidRevision(f[3])
        if not line or not revision then return true end
        local profile=TC.store.crafts[sender] or {professions={},revision=0}
        TC.store.crafts[sender]=profile
        if profile.roster and not profile.roster[line] and revision<=profile.revision then return true end
        local old=profile.professions[line]
        if old and revision<=old.revision then return true end
        local key=sender..":"..line
        PruneStages(craftStages)
        local stage=craftStages[key]
        if kind=="CB" then
            local total=TC.Integer(f[4],1,256); local rank=TC.Integer(f[6],0,10000); local maxRank=TC.Integer(f[7],0,10000)
            if #f~=7 or not total or not rank or not maxRank or #f[5]>48 or (not stage and PruneStages(craftStages)>=120) then return true end
            if not stage or revision>stage.revision then
                stage={revision=revision,chunks={},store=TC.store,when=GetTime()}
                craftStages[key]=stage
            end
            if stage.revision==revision then
                stage.total=total; stage.name=TC.Clean(f[5],48); stage.rank=rank; stage.maxRank=maxRank; stage.when=GetTime()
            end
        else
            local index=TC.Integer(f[4],1,256)
            if #f~=5 or not index then return true end
            if not stage or revision>stage.revision then
                if not stage and PruneStages(craftStages)>=120 then return true end
                stage={revision=revision,chunks={},store=TC.store,when=GetTime()}; craftStages[key]=stage
            end
            if stage.revision~=revision or (stage.total and index>stage.total) then return true end
            stage.chunks[index]=f[5]
            stage.when=GetTime()
        end
        if stage and stage.total then
            local recipes={}; local complete=true; local count=0
            for i=1,stage.total do
                if stage.chunks[i]==nil then complete=false; break end
                for token in stage.chunks[i]:gmatch("[^,]+") do
                    local recipe,learned=token:match("^(%d+):([01])$")
                    recipe=TC.Integer(recipe,1,2147483647); count=count+1
                    if not recipe or count>4096 then craftStages[key]=nil; return true end
                    recipes[recipe]=learned=="1"
                end
            end
            if complete then
                profile.professions[line]={revision=stage.revision,name=stage.name,rank=stage.rank,maxRank=stage.maxRank,recipes=recipes}
                TC.store.professionNames[line]=stage.name
                AddCatalog(line,recipes); craftStages[key]=nil; RefreshRecipes()
            end
        end
        return true
    elseif kind=="PX" then
        local id,rev,part,total,chunk=message:match("^PX\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
        local revision=ValidRevision(rev); part=TC.Integer(part,1,8); total=TC.Integer(total,1,8)
        if not id or #id>64 or not id:match("^[%w%-:]+$") or not revision or not part or not total or part>total or #chunk>140 then return true end
        if TC.IsProjectOfficer(sender)==false then return true end
        local key=sender..":"..id
        PruneStages(projectStages)
        local stage=projectStages[key]
        if not stage or revision>stage.revision then
            if not stage and PruneStages(projectStages)>=100 then return true end
            stage={revision=revision,total=total,chunks={},store=TC.store,when=GetTime()}; projectStages[key]=stage
        end
        if stage.revision~=revision or stage.total~=total then return true end
        stage.chunks[part]=chunk
        stage.when=GetTime()
        for i=1,total do if stage.chunks[i]==nil then return true end end
        local body=table.concat(stage.chunks)
        if Parts(body)[2]~=tostring(revision) then projectStages[key]=nil; return true end
        ApplyProject(id,body,sender); projectStages[key]=nil
        return true
    end
    return false
end

function TC.StartGuildData()
    if C_GuildInfo and C_GuildInfo.GuildRoster and TC.guildKey then pcall(C_GuildInfo.GuildRoster) end
    C_Timer.After(2,function() TC.ScanProfessions() end)
end

local frame=CreateFrame("Frame")
for _,event in ipairs({"TRADE_SKILL_SHOW","TRADE_SKILL_LIST_UPDATE","TRADE_SKILL_DATA_SOURCE_CHANGED","NEW_RECIPE_LEARNED","SKILL_LINES_CHANGED","SPELLS_CHANGED","SPELL_DATA_LOAD_RESULT"}) do
    pcall(frame.RegisterEvent,frame,event)
end
function TC.RetryDeferredProjects()
    for id,p in pairs(deferred) do
        if p.store~=TC.store or GetTime()-p.when>=180 then
            deferred[id]=nil
        elseif TC.IsProjectOfficer(p.sender)~=nil then
            deferred[id]=nil
            ApplyProject(id,p.body,p.sender)
        end
    end
end

frame:SetScript("OnEvent",function(_,event,id,success)
    if not TC.store then return end
    if event=="SPELL_DATA_LOAD_RESULT" then
        if id and pendingSpells[id] then
            pendingSpells[id]=nil
            if success~=false then RefreshRecipes() end
        end
    elseif not scanScheduled then
        scanScheduled=true
        C_Timer.After(0.4,function() scanScheduled=false; TC.ScanProfessions() end)
    end
end)
