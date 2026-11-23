local _,TC=...
local function Copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=Copy(item) end; return result
end
local function Merge(target,source)
    for key,value in pairs(source) do
        local old=target[key]
        if old==nil then target[key]=Copy(value)
        elseif type(old)=="table" and type(value)=="table" then
            if type(old.revision)=="number" and type(value.revision)=="number" then
                if value.revision>old.revision or (value.revision==old.revision and value.deleted and not old.deleted) then target[key]=Copy(value) end
            else Merge(old,value) end
        end
    end
end
local function MaxMap(target,source)
    for key,value in pairs(source or {}) do if type(value)=="number" then target[key]=math.max(target[key] or 0,value) end end
end
function TC.GuildStorageKey(guild,realm)
    if type(guild)~="string" or guild=="" then return end
    local _,surname=UnitFullName("player")
    if type(realm)=="string" and realm~="" and realm~=surname then return realm..":"..guild end
    local match
    for key in pairs(TC.db.guilds) do
        local savedRealm,savedGuild=key:match("^([^:]+):(.+)$")
        if savedGuild==guild and savedRealm~="unguilded" then
            if match then match=nil; break end
            match=key
        end
    end
    if match then return match end
    if type(realm)=="string" and realm~="" then return realm..":"..guild end
    realm=GetNormalizedRealmName()
    if type(realm)~="string" or realm=="" then realm=GetRealmName() end
    if type(realm)~="string" then realm="" end
    return realm..":"..guild
end
function TC.MergeEmptyRealmGuild(guild,key)
    local oldKey=":"..guild
    if oldKey==key then return end
    local old=TC.db.guilds[oldKey]
    local fun=TC.db.fun
    local oldWallet=fun and fun.wallets and fun.wallets[oldKey]
    if not old and not oldWallet then return end
    TC.db.guildRecovery=TC.db.guildRecovery or {}
    TC.db.guildRecovery[oldKey]=TC.db.guildRecovery[oldKey] or {when=time(),destination=key,store=Copy(old),wallet=Copy(oldWallet)}
    local target=TC.db.guilds[key] or {owners={}}; TC.db.guilds[key]=target
    local profiles={}
    for _,store in ipairs({target,old or {}}) do
        for account,p in pairs(store.social and store.social.accounts or {}) do
            local merged=profiles[account]
            if not merged then merged=Copy(p); profiles[account]=merged
            else
                local grants,transfers,deductions=merged.grants or {},merged.transfers or {},merged.deductions or {}
                MaxMap(grants,p.grants); MaxMap(transfers,p.transfers); MaxMap(deductions,p.deductions)
                local earned,spent=math.max(merged.earned or 0,p.earned or 0),math.max(merged.spent or 0,p.spent or 0)
                if (p.revision or 0)>(merged.revision or 0) then merged=Copy(p); profiles[account]=merged end
                merged.grants,merged.transfers,merged.deductions=grants,transfers,deductions; merged.earned,merged.spent=earned,spent
            end
        end
    end
    if old then Merge(target,old) end
    if next(profiles) then target.social=target.social or {}; target.social.accounts=profiles end
    for owner,p in pairs(old and old.social and old.social.pvp or {}) do
        target.social=target.social or {}; target.social.pvp=target.social.pvp or {}
        local current=target.social.pvp[owner] or Copy(p); target.social.pvp[owner]=current
        if TC.MergeDeathZones then TC.MergeDeathZones(current,p.deathZones) end
        if p.honorKills~=nil then current.honorKills=math.max(current.honorKills or 0,p.honorKills); current.honorRevision=math.max(current.honorRevision or 0,p.honorRevision or 0) end
        if p.deaths~=nil and (not current.deathsLifetime or p.deathsLifetime) then
            current.deaths=math.max(current.deaths or 0,p.deaths); current.deathsLifetime=current.deathsLifetime or p.deathsLifetime
            current.deathRevision=math.max(current.deathRevision or 0,p.deathRevision or 0)
        end
    end
    if oldWallet then
        local wallet=fun.wallets[key]
        if not wallet then wallet=Copy(oldWallet); fun.wallets[key]=wallet
        else
            wallet.earned=(wallet.earned or 0)+(oldWallet.earned or 0); wallet.spent=(wallet.spent or 0)+(oldWallet.spent or 0)
            for _,field in ipairs({"transfers","grants","deductions"}) do
                wallet[field]=wallet[field] or {}
                for account,value in pairs(oldWallet[field] or {}) do wallet[field][account]=(wallet[field][account] or 0)+value end
            end
            wallet.purchases=wallet.purchases or {}; for id,value in pairs(oldWallet.purchases or {}) do if value then wallet.purchases[id]=true end end
            wallet.receipts=wallet.receipts or {}
            for account,receipt in pairs(oldWallet.receipts or {}) do wallet.receipts[account]=wallet.receipts[account] or {}; MaxMap(wallet.receipts[account],receipt) end
        end
        wallet.revision=math.max(time(),wallet.revision or 0,oldWallet.revision or 0)+1
        fun.wallets[oldKey]=nil
    end
    TC.db.guilds[oldKey]=nil
end
