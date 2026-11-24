local _,TC=...

local function Call(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...); if ok then return value end
end
local function CleanSource(text)
    return TC.Clean(type(text)=="string" and text:gsub("|n"," "):gsub("<br%s*/?>"," "):gsub("<[^>]+>","") or "",136)
end
local function Escape(text) return text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1") end

local function SkillFromText(text,profession)
    if type(text)~="string" or type(profession)~="string" then return end
    -- Match the client's explicit localized 'Requires Profession (N)' format.
    -- Difficulty colours and triviality thresholds are NOT learning requirements.
    local format=_G.ITEM_MIN_SKILL
    if type(format)=="string" then
        local pattern=Escape(format):gsub("%%%%s","(.+)"):gsub("%%%%d","(%%d+)")
        local name,number=text:match(pattern)
        if name==profession then return TC.Integer(number,1,10000) end
    end
    local number=text:match("[Rr]equires%s+"..Escape(profession).."%s*%((%d+)%)")
    return TC.Integer(number,1,10000)
end

local function SourceKind(source,label)
    local trainerLabels={_G.TRAINER,_G.PROFESSION_TRAINER,"Trainer","Profession Trainer"}
    local lower=source:lower():gsub("^source:%s*","")
    for _,text in pairs(trainerLabels) do
        if type(text)=="string" and text~="" and
            (label==text or lower:match("^"..Escape(text:lower()).."%f[%W]")) then return 1 end
    end
    -- Known non-trainer sources. An unexplained skill requirement alone does
    -- not prove that a separate pattern item is needed.
    for _,text in pairs({_G.BATTLE_PET_SOURCE_1,_G.BATTLE_PET_SOURCE_2,_G.BATTLE_PET_SOURCE_3,
        "Vendor","Drop","Quest","Discovery","Reputation","World Drop","Dungeon","Raid"}) do
        if type(text)=="string" and text~="" and (label==text or lower:match("^"..Escape(text:lower()).."%f[%W]")) then return 2 end
    end
    return 0
end

function TC.SetRecipeMetadata(id,line,required,kind,source)
    if not TC.store then return end
    local entry=TC.store.catalog[id]
    if entry and entry.profession~=line then return end
    local newEntry = not entry
    entry=entry or {profession=line}
    required=TC.Integer(required,1,10000) or entry.requiredSkill
    kind=kind and kind>0 and kind or entry.sourceKind or 0
    if entry.sourceKind==1 then kind=1 end -- A confirmed trainer is an available alternative to a pattern.
    source=source and source~="" and CleanSource(source) or entry.source or ""
    if not required and kind==0 and source=="" then return end
    if newEntry then TC.store.catalog[id]=entry end
    if entry.requiredSkill~=required or entry.sourceKind~=kind or entry.source~=source then
        entry.requiredSkill,entry.sourceKind,entry.source=required,kind,source
        entry.metaRevision=TC.NextRevision(entry.metaRevision)
        entry.metaWriter=TC.owner
        if TC.InvalidateRecipes then TC.InvalidateRecipes() end
        return true
    end
end

function TC.CaptureRecipeRequirements(id,line,recipe,profession)
    local api=C_TradeSkillUI or {}
    local required=TC.Integer(recipe.requiredSkillRank or recipe.requiredSkillLevel or recipe.requiredSkill,1,10000)
    local source=CleanSource(Call(api.GetRecipeSourceText,id))
    if not required then required=SkillFromText(source,profession) end
    if not required and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tooltip=Call(C_TooltipInfo.GetHyperlink,"enchant:"..id)
        for _,row in ipairs(type(tooltip)=="table" and tooltip.lines or {}) do
            required=SkillFromText(CleanSource(row.leftText),profession)
            if required then break end
        end
    end
    local label=recipe.sourceType and _G["BATTLE_PET_SOURCE_"..recipe.sourceType]
    return TC.SetRecipeMetadata(id,line,required,SourceKind(source,label),source~="" and source or label)
end

function TC.BroadcastRecipeMetadata(id,entry)
    if not entry.metaRevision then return end
    TC.QueueGuildPacket("craft-meta:"..id,table.concat({"CM",id,entry.profession,entry.metaRevision,
        entry.requiredSkill or 0,entry.sourceKind or 0,CleanSource(entry.source)},"\t"))
end

function TC.ReceiveRecipeMetadata(message,sender)
    local id,line,revision,required,kind,source=message:match("^CM\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([012])\t([^\t]*)$")
    id=TC.Integer(id,1,2147483647); line=TC.Integer(line,1,2147483647)
    revision=TC.Integer(revision,1,time()+86400); required=TC.Integer(required,0,10000); kind=tonumber(kind)
    if not id or not line or not revision or not required or not kind or #source>136 then return end
    local entry=TC.store.catalog[id]
    if entry and entry.profession~=line then return end
    if not entry or revision>(entry.metaRevision or 0) or
        (revision==(entry.metaRevision or 0) and sender>(entry.metaWriter or "")) then
        entry=entry or {profession=line}; TC.store.catalog[id]=entry
        entry.requiredSkill=required>0 and required or nil
        entry.sourceKind,entry.source,entry.metaRevision,entry.metaWriter=kind,CleanSource(source),revision,sender
        -- This writes the catalog without going through GuildData's Refresh,
        -- so the cached recipe list has to be dropped explicitly.
        if TC.InvalidateRecipes then TC.InvalidateRecipes() end
        if TC.QueueRefresh then TC.QueueRefresh() end
    end
end

function TC.RecipeAvailability(id,entry)
    local result={}
    for owner,profile in pairs(TC.store.crafts) do
        local profession=profile.professions[entry.profession]
        if profession then
            local known=profession.recipes[id]
            local rank,maxRank=profession.rank,profession.maxRank
            local required=entry.requiredSkill
            local reasons,short={},{}
            local canCraft=known==true and (not required or rank>=required)
            if canCraft then reasons[1]="Can craft (recipe learned)"; short[1]="Can craft"
            else
                if required and rank<required then
                    reasons[#reasons+1]="Skill "..rank.."/"..required.." (needs +"..(required-rank)..")"
                    short[#short+1]="skill "..rank.."/"..required
                    if maxRank<required then reasons[#reasons+1]="Raise profession cap from "..maxRank.." to at least "..required end
                elseif not required then reasons[#reasons+1]="Skill requirement unknown" end
                if known==true then
                    -- Recipe is learned; only its skill requirement is unmet.
                elseif known==nil then
                    reasons[#reasons+1]="Recipe knowledge not yet confirmed"; short[#short+1]="knowledge unconfirmed"
                elseif entry.sourceKind==1 then
                    if not required or rank>=required then reasons[#reasons+1]="Train recipe at a profession trainer"; short[#short+1]="train recipe" end
                elseif entry.sourceKind==2 then
                    reasons[#reasons+1]="Recipe missing (non-trainer source)"; short[#short+1]="recipe missing"
                else
                    reasons[#reasons+1]="Recipe not learned"; short[#short+1]="recipe missing"
                end
                if #short==0 then short[1]="Requirements unknown" end
            end
            result[#result+1]={owner=owner,name=TC.DisplayName(owner),known=known,canCraft=canCraft,rank=rank,maxRank=maxRank,
                deficit=required and math.max(0,required-rank) or 10001,
                text=TC.DisplayName(owner)..": "..table.concat(reasons,"; "),short=TC.DisplayName(owner)..": "..table.concat(short," + ")}
        end
    end
    table.sort(result,function(a,b)
        if a.canCraft~=b.canCraft then return a.canCraft end
        if a.deficit~=b.deficit then return a.deficit<b.deficit end
        if a.rank~=b.rank then return a.rank>b.rank end
        return a.owner<b.owner
    end)
    return result
end

function TC.ScanTrainerRequirements()
    if not TC.store or not GetNumTrainerServices or not GetTrainerServiceInfo or not GetTrainerServiceSkillReq then return end
    local mine=TC.store.crafts[TC.owner]
    local changed=false
    for index=1,GetNumTrainerServices() do
        local name,second,third=GetTrainerServiceInfo(index)
        local service=(second=="available" or second=="unavailable" or second=="used") and second or third
        local step=Call(_G.IsTrainerServiceSkillStep,index)
        if name and not step and (service=="available" or service=="unavailable" or service=="used") then
            local skillName,required=GetTrainerServiceSkillReq(index)
            required=TC.Integer(required,1,10000)
            for line,profession in pairs(mine.professions) do
                if profession.name==skillName and required then
                    local link=Call(_G.GetTrainerServiceItemLink,index)
                    local id=type(link)=="string" and tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
                    if not id then
                        local found
                        for candidate,entry in pairs(TC.store.catalog) do
                            if entry.profession==line and C_Spell and Call(C_Spell.GetSpellName,candidate)==name then
                                if found then found=false; break end; found=candidate
                            end
                        end
                        id=found
                    end
                    if not id and C_Spell and C_Spell.GetSpellInfo then
                        local spell=Call(C_Spell.GetSpellInfo,name)
                        local candidate=type(spell)=="table" and TC.Integer(spell.spellID,1,2147483647)
                        if candidate and spell.name==name and C_TradeSkillUI then
                            local matches=Call(C_TradeSkillUI.IsRecipeInSkillLine,candidate,line)
                            if matches==nil and C_TradeSkillUI.GetTradeSkillLineForRecipe then
                                local ok,child,_,parent=pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe,candidate)
                                matches=ok and (child==line or parent==line)
                            end
                            if matches then id=candidate end
                        end
                    end
                    if id then
                        if TC.SetRecipeMetadata(id,line,required,1,"Profession trainer") then changed=true end
                        local learned=service=="used"
                        if profession.recipes[id]~=learned then
                            profession.recipes[id]=learned; profession.signature=nil
                            profession.revision=TC.NextRevision(profession.revision)
                            mine.revision=TC.NextRevision(mine.revision); changed=true
                        end
                    end
                end
            end
        end
    end
    if changed then
        if TC.InvalidateRecipes then TC.InvalidateRecipes() end
        TC.BroadcastCrafts()
        if TC.QueueRefresh then TC.QueueRefresh() end
    end
end

local events=CreateFrame("Frame")
for _,event in ipairs({"TRAINER_SHOW","TRAINER_UPDATE"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function() TC.ScanTrainerRequirements() end)
