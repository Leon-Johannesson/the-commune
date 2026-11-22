local _,TC=...
local deferred={}
function TC.ReconcileCreditReceipts()
    local wallet=TC.wallet; wallet.receipts=wallet.receipts or {}
    for issuer,p in pairs(TC.store.social.accounts) do
        local receipt=wallet.receipts[issuer] or {}; wallet.receipts[issuer]=receipt
        receipt.transfer=math.max(receipt.transfer or 0,(p.transfers or {})[TC.db.fun.account] or 0)
        receipt.grant=math.max(receipt.grant or 0,(p.grants or {})[TC.db.fun.account] or 0)
        receipt.deduction=math.max(receipt.deduction or 0,(p.deductions or {})[TC.db.fun.account] or 0)
    end
    local value=(wallet.earned or 0)-(wallet.spent or 0)
    for _,amount in pairs(wallet.transfers or {}) do value=value-amount end
    for _,receipt in pairs(wallet.receipts) do value=value+(receipt.transfer or 0)+(receipt.grant or 0)-(receipt.deduction or 0) end
    return value
end
function TC.RepairRecordedRewards()
    local total,expected,guilds=0,0,0
    for key,wallet in pairs(TC.db.fun.wallets) do total=total+(wallet.earned or 0); if key~="personal" then guilds=guilds+1 end end
    for _,day in pairs(TC.db.fun.days) do
        for _,answer in pairs(day.answers or {}) do if answer.correct then expected=expected+1 end end
        if day.wordleResult and day.wordleResult<=6 then expected=expected+(day.wordleCredits or 2) end
    end
    if TC.guildKey and guilds==1 and expected>total then
        TC.db.creditRepair=TC.db.creditRepair or {}; TC.db.creditRepair[#TC.db.creditRepair+1]={when=time(),amount=expected-total,guild=TC.guildKey,previous=TC.wallet.earned}
        TC.wallet.earned=TC.wallet.earned+(expected-total); TC.wallet.revision=math.max(time(),TC.wallet.revision or 0)+1
    end
end
function TC.DeferCreditPacket(message,sender)
    local key=sender..":"..message; local n=0;for _ in pairs(deferred) do n=n+1 end
    if n<100 then deferred[key]={message=message,sender=sender,store=TC.store,when=GetTime()} end
end
function TC.DebugCredits()
    if not TC.wallet then return end
    TC.Print("Credits wallet: "..(TC.guildKey or "personal").." | earned: "..TC.wallet.earned.." | spent: "..TC.wallet.spent.." | balance: "..TC.ReconcileCreditReceipts())
    if TC.db.creditRepair then TC.Print("Recorded-reward recoveries: "..#TC.db.creditRepair) end
    for old,recovery in pairs(TC.db.guildRecovery or {}) do TC.Print("Recovered guild record: "..old.." -> "..recovery.destination) end
end
function TC.RetryDeferredCredits()
    for key,p in pairs(deferred) do
        if p.store~=TC.store or GetTime()-p.when>180 then deferred[key]=nil
        elseif TC.IsGuildMaster(p.sender)~=nil then deferred[key]=nil; TC.ReceiveSocial(p.message,p.sender) end
    end
end
