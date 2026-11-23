local _,TC=...
local pendingCounters={}
local socialStore
TC.Shop={custodian={name="Copper Custodian",cost=2},snacks={name="Chief Snack Officer",cost=3},navigator={name="Questionable Navigator",cost=2}}
TC.WordSolutions={}
for word in ("aggro armor altar arrow ashen bears beast black blade blast bless blind blood boots brain bread brick broad charm chest chill cloth cobra coins coral craft crash creek crown crypt curse daily demon doubt draft drake dream druid dwarf eagle earth ember enemy fairy feast field fight flame flesh float forge frost giant ghost ghoul glory glove gnome gnoll grain grass grave green grove guard guild heart herbs honor horse horde human ivory jewel kings knife light lions magic marsh medal metal might mines money moose mount mouse night north ocean olive order peace pearl phase plain plate power pride priest quest quick quiet raids raven realm relic ridge river rogue roots round royal runes saber saint scale scout shade shard shark sheep shield shine shock shore siege skill skull slash sleep slime small smith snake soul spells spear speed spider spite staff stage stair stake steel stone store storm sword table taunt teeth thank thief three tiger titan tombs torch trade trail train tribe troll truce trust truth uncle valor venom visit voice waste water wheat wheel white whole whelp witch woods world wrath wrong yield young"):gmatch("%a+") do
    if #word==5 then TC.WordSolutions[#TC.WordSolutions+1]=word; TC.WordDictionary[word]=true end
end

local function Rev(n) return math.max(time(),(n or 0)+1) end
local function Log(text)
    local f=TC.db.fun; f.history=f.history or {}; table.insert(f.history,1,{when=time(),text=text})
    while #f.history>50 do table.remove(f.history) end
end
function TC.DayID() return math.floor(((GetServerTime and GetServerTime()) or time())/86400) end
function TC.InitSocial()
    if socialStore~=TC.store then pendingCounters={}; socialStore=TC.store end
    local hash=0; for i=1,#TC.owner do hash=(hash*31+TC.owner:byte(i))%2147483647 end
    TC.db.fun=TC.db.fun or {account="a"..time().."-"..hash.."-"..math.random(10000,99999),days={},wallets={},stats={qa=0,qc=0,qd=0,wp=0,ww=0,wg=0},sound=true}
    local f=TC.db.fun
    f.display=TC.Clean(TC.DisplayName(TC.owner),32); f.wallets=f.wallets or {}; f.days=f.days or {}
    TC.store.social=TC.store.social or {accounts={},characters={},hits={}}
    TC.InitHitlist()
    local key=TC.guildKey or "personal"
    f.wallets[key]=f.wallets[key] or {earned=0,spent=0,transfers={},grants={},purchases={},revision=0}
    TC.wallet=f.wallets[key]
    TC.wallet.deductions=TC.wallet.deductions or {}
    TC.wallet.earned=tonumber(TC.wallet.earned) or 0; TC.wallet.spent=tonumber(TC.wallet.spent) or 0
    TC.wallet.transfers=TC.wallet.transfers or {}; TC.wallet.grants=TC.wallet.grants or {}; TC.wallet.purchases=TC.wallet.purchases or {}
    local cached=TC.store.social.accounts[f.account]
    if cached then
        local repaired=cached.earned and cached.earned>TC.wallet.earned or cached.spent and cached.spent>TC.wallet.spent
        TC.wallet.earned=math.max(TC.wallet.earned,cached.earned or 0)
        TC.wallet.spent=math.max(TC.wallet.spent,cached.spent or 0)
        for _,field in ipairs({"transfers","grants","deductions"}) do
            for account,value in pairs(cached[field] or {}) do
                if value>(TC.wallet[field][account] or 0) then TC.wallet[field][account]=value; repaired=true end
            end
        end
        if repaired then TC.wallet.revision=math.max(time(),TC.wallet.revision or 0,cached.revision or 0)+1 end
    end
    TC.RepairRecordedRewards()
    if TC.InitPvP then TC.InitPvP() end
    TC.PublishSocial(false)
end
function TC.DailyState()
    local f=TC.db.fun; local day=TC.DayID()
    f.days[day]=f.days[day] or {answers={},guesses={}}
    return f.days[day],day
end
local function QuizCount(day, state)
    -- Someone upgrading after answering on an older version can finish that
    -- day's original quiz with their saved answers and completion intact.
    if day<TC.MixedQuizStartDay or (state and not state.mixedQuiz and next(state.answers)) then return 4 end
    return 5
end

function TC.DailyQuizCount()
    local day=TC.DayID()
    return QuizCount(day, TC.db and TC.db.fun and TC.db.fun.days[day])
end

local function ShuffledCopy(entries, seed)
    local result={}
    for i,entry in ipairs(entries) do result[i]=entry end
    seed=seed%2147483647
    for i=#result,2,-1 do
        seed=(seed*48271)%2147483647
        local j=seed%i+1
        result[i],result[j]=result[j],result[i]
    end
    return result
end

local wowDeck, gamesDeck, generalDeck
local function MixedQuiz(day)
    -- Walk shuffled decks so a category covers its whole pool before repeating.
    -- Use the same deterministic order for every guildmate, regardless of relogs.
    if not wowDeck then
        wowDeck=ShuffledCopy(TC.QuizBank,773)
        gamesDeck=ShuffledCopy(TC.QuizOtherGames,2137)
        generalDeck=ShuffledCopy(TC.QuizGeneral,3527)
    end
    local offset=day-TC.MixedQuizStartDay
    local questions={}
    for i=1,3 do questions[i]=wowDeck[(offset*3+i-1)%#wowDeck+1] end
    questions[4]=gamesDeck[offset%#gamesDeck+1]
    questions[5]=generalDeck[offset%#generalDeck+1]
    return ShuffledCopy(questions, day*104729)
end

function TC.DailyQuiz()
    local state,day=TC.DailyState()
    local count=QuizCount(day,state)
    local questions=count==5 and MixedQuiz(day)
    local rollout=day==TC.QuizRolloutDay and TC.QuizRolloutQuestions
    local result={}
    for slot=1,count do
        local index=(day*4+slot-1)%#TC.QuizBank+1
        local q=questions and questions[slot] or (rollout and rollout[index]) or TC.QuizBank[index]
        local options=ShuffledCopy(q.choices, day*7919+q.id*104729)
        result[slot]={id=q.id,question=q.question,options=options,answer=q.answer,explanation=q.explanation,source=q.source,difficulty=q.difficulty}
    end
    return result
end

function TC.DailyProgress()
    if not TC.db or not TC.db.fun then return 0,false,TC.DailyQuizCount() end
    local d,day=TC.DailyState()
    local count=QuizCount(day,d)
    local n=0
    for i=1,count do if d.answers[i] then n=n+1 end end
    return n,d.wordleResult~=nil,count
end
function TC.CreditBalance(account)
    account=account or TC.db.fun.account
    if account==TC.db.fun.account then return TC.ReconcileCreditReceipts() end
    local p=TC.store.social.accounts[account]; if not p then return 0 end
    local value=(p.earned or 0)-(p.spent or 0)
    for _,amount in pairs(p.transfers or {}) do value=value-amount end
    for _,other in pairs(TC.store.social.accounts) do
        value=value+((other.transfers or {})[account] or 0)+((other.grants or {})[account] or 0)-((other.deductions or {})[account] or 0)
    end
    return value
end
function TC.PublishSocial(send)
    if not TC.wallet then return end
    local f,w=TC.db.fun,TC.wallet
    -- The guild roster can supply our surname well after login, so take the
    -- label as it reads now instead of the one cached when the guild loaded.
    f.display=TC.Clean(TC.DisplayName(TC.owner),32)
    local d,day=TC.DailyState(); local answered,correct=0,0
    for i=1,QuizCount(day,d) do if d.answers[i] then answered=answered+1; if d.answers[i].correct then correct=correct+1 end end end
    local s=f.stats
    local p={revision=w.revision,name=f.display,qa=s.qa,qc=s.qc,qd=s.qd,wp=s.wp,ww=s.ww,wg=s.wg,day=day,answered=answered,correct=correct,
        fifthAnswered=d.answers[5]~=nil,fifthCorrect=d.answers[5] and d.answers[5].correct,result=d.wordleResult or 0,earned=w.earned,spent=w.spent,title=f.title or "",transfers=w.transfers,grants=w.grants,deductions=w.deductions}
    TC.store.social.accounts[f.account]=p; TC.store.social.characters[TC.owner]=f.account
    if send and TC.guildKey and TC.QueueGuildPacket then TC.BroadcastSocial() end
end
local function Changed()
    TC.wallet.revision=Rev(TC.wallet.revision); TC.PublishSocial(true)
    if TC.UpdateSummaryDaily then TC.UpdateSummaryDaily() end
    if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end
end
function TC.AnswerQuiz(slot,choice)
    local d,day=TC.DailyState()
    local count=QuizCount(day,d)
    if not TC.Integer(slot,1,count) or not TC.Integer(choice,1,4) then return nil,"Choose an answer." end
    if d.answers[slot] then return nil,"That question is already answered today." end
    local q=TC.DailyQuiz()[slot]; local correct=q.options[choice]==q.answer
    if count==5 then d.mixedQuiz=true end
    d.answers[slot]={choice=choice,correct=correct,id=q.id}
    local s=TC.db.fun.stats; s.qa=s.qa+1
    if correct then s.qc=s.qc+1; TC.wallet.earned=TC.wallet.earned+1; Log("+1 Social Credit: daily quiz") end
    local n=TC.DailyProgress(); if n==count then s.qd=s.qd+1 end
    Changed(); return true,correct
end
function TC.WordAnswer(day) return TC.WordSolutions[((day or TC.DayID())*37)%#TC.WordSolutions+1] end
function TC.WordFeedback(guess,answer)
    local result,remaining={},{}
    for i=1,5 do
        local g,a=guess:sub(i,i),answer:sub(i,i)
        if g==a then result[i]=2 else remaining[a]=(remaining[a] or 0)+1 end
    end
    for i=1,5 do if result[i]~=2 then
        local g=guess:sub(i,i)
        if (remaining[g] or 0)>0 then result[i]=1; remaining[g]=remaining[g]-1 else result[i]=0 end
    end end
    return result
end
function TC.GuessWord(word)
    local d=TC.DailyState(); word=(word or ""):lower():match("^%s*(.-)%s*$")
    if d.wordleResult then return nil,"Today's Wordle is finished." end
    if #word~=5 or not word:match("^[a-z]+$") or not TC.WordDictionary[word] then return nil,"Enter a five-letter word from the dictionary." end
    d.guesses[#d.guesses+1]=word
    local won=word==TC.WordAnswer()
    if won or #d.guesses==6 then
        d.wordleResult=won and #d.guesses or 7
        local s=TC.db.fun.stats; s.wp=s.wp+1; s.wg=s.wg+#d.guesses
        if won then
            local reward=TC.WordReward(#d.guesses); d.wordleCredits=reward
            s.ww=s.ww+1; TC.wallet.earned=TC.wallet.earned+reward; Log("+"..reward.." Social Credits: daily Wordle")
        end
    end
    Changed(); return true
end
function TC.TransferCredits(account,amount,award)
    if TC.IsGuildMaster(TC.owner)~=true then return nil,"Only the guild master can manually change Social Credits." end
    amount=TC.Integer(amount,1,5)
    if not amount or not account or account==TC.db.fun.account or not TC.store.social.accounts[account] then return nil,"Select another guild account and enter 1-5 credits." end
    if award then
        if TC.IsGuildMaster(TC.owner)~=true then return nil,"Only the guild master can award credits." end
        TC.wallet.grants[account]=(TC.wallet.grants[account] or 0)+amount; Log("Awarded "..amount.." Social Credits to "..TC.store.social.accounts[account].name)
    else
        if TC.CreditBalance()<amount then return nil,"Not enough Social Credits." end
        TC.wallet.transfers[account]=(TC.wallet.transfers[account] or 0)+amount; Log("Sent "..amount.." Social Credits to "..TC.store.social.accounts[account].name)
    end
    Changed(); return true
end
function TC.AdjustCredits(account,amount,remove)
    if TC.IsGuildMaster(TC.owner)~=true then return nil,"Only the guild master can manually change Social Credits." end
    amount=TC.Integer(amount,1,99999)
    if not amount or not account or not TC.store.social.accounts[account] then return nil,"Select a guild account and enter an amount from 1 to 99999." end
    if remove and amount>TC.CreditBalance(account) then return nil,"That account does not have enough Social Credits." end
    local counters=remove and TC.wallet.deductions or TC.wallet.grants
    counters[account]=(counters[account] or 0)+amount
    Log((remove and "Removed " or "Added ")..amount.." Social Credits "..(remove and "from " or "to ")..TC.store.social.accounts[account].name)
    Changed(); return true
end
function TC.BuyTitle(key)
    if TC.IsGuildMaster(TC.owner)~=true then return nil,"Only the guild master can manually change Social Credits." end
    local item=TC.Shop[key]; if not item then return nil,"Unknown title." end
    if not TC.wallet.purchases[key] then
        if TC.CreditBalance()<item.cost then return nil,"Not enough Social Credits." end
        TC.wallet.spent=TC.wallet.spent+item.cost; TC.wallet.purchases[key]=true; Log("Bought "..item.name.." for "..item.cost.." Social Credits")
    end
    TC.db.fun.title=key; Changed(); return true
end
function TC.ScoreRows()
    local rows={}
    for account,p in pairs(TC.store.social.accounts) do rows[#rows+1]={account=account,profile=p,balance=TC.CreditBalance(account)} end
    table.sort(rows,function(a,b) if a.profile.qc~=b.profile.qc then return a.profile.qc>b.profile.qc end
        if a.profile.ww~=b.profile.ww then return a.profile.ww>b.profile.ww end return a.profile.name<b.profile.name end)
    return rows
end
function TC.BroadcastSocial()
    if TC.BroadcastPvP then TC.BroadcastPvP() end
    TC.BroadcastWordBoard()
    if not TC.store or not TC.store.social then return end
    local f,w=TC.db.fun,TC.wallet; local p=TC.store.social.accounts[f.account]
    -- Older clients reject the whole profile if the daily field exceeds four.
    -- Lifetime scores and earned credits include the fifth question.
    local answered=math.min(p.answered-(p.fifthAnswered and 1 or 0),4)
    local correct=p.correct-(p.fifthCorrect and 1 or 0)
    TC.QueueGuildPacket("social-head",table.concat({"FA",f.account,p.revision,p.name,p.qa,p.qc,p.qd,p.wp,p.ww,p.wg,p.day,answered,correct,p.result,p.earned,p.spent,p.title},"\t"))
    for to,amount in pairs(w.transfers) do TC.QueueGuildPacket("social-transfer:"..to,table.concat({"FB",f.account,to,p.revision,amount},"\t")) end
    if TC.IsGuildMaster(TC.owner)==true then
        for to,amount in pairs(w.deductions) do TC.QueueGuildPacket("social-deduction:"..to,table.concat({"FD",f.account,to,p.revision,amount},"\t")) end
        for to,amount in pairs(w.grants) do TC.QueueGuildPacket("social-grant:"..to,table.concat({"FG",f.account,to,p.revision,amount},"\t")) end
    end
    for owner,slots in pairs(TC.store.social.hits) do
        for slot,r in pairs(slots) do
            if owner==TC.owner then TC.BroadcastHit(slot,r)
            elseif r.deleted and r.officer==TC.owner then TC.BroadcastHitDelete(owner,slot,r.revision) end
        end
    end
    TC.BroadcastHitCache()
end
local function Fields(message)
    local f={}; for value in (message.."\t"):gmatch("(.-)\t") do f[#f+1]=value end; return f
end
local function Account(id) return type(id)=="string" and #id<=40 and id:match("^[a-zA-Z0-9%-]+$") end
function TC.ReceiveSocial(message,sender)
    if TC.ReceiveHitCache(message,sender) then return true end
    if TC.ReceivePvP and TC.ReceivePvP(message,sender) then return true end
    if TC.ReceiveGear and TC.ReceiveGear(message,sender) then return true end
    local f=Fields(message); local kind=f[1]
    if kind=="HL" or kind=="HD" then return TC.ReceiveHit(message,sender) end
    if kind~="FA" and kind~="FB" and kind~="FG" and kind~="FD" and kind~="FW" then return false end
    if kind=="FW" then
        local day,result=TC.Integer(f[3],0,TC.DayID()),TC.Integer(f[4],1,6)
        if #f~=5 or not Account(f[2]) or not day or day~=TC.DayID() or not result or #f[5]~=result*5 or f[5]:find("[^012]") or f[5]:sub(-5)~="22222" then return true end
        if TC.store.social.characters[sender]~=f[2] then
            pendingCounters[sender]=pendingCounters[sender] or {}; if #pendingCounters[sender]<50 then table.insert(pendingCounters[sender],message) end
            return true
        end
        TC.store.social.accounts[f[2]].wordBoard={day=day,result=result,colors=f[5]}
        if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end; return true
    end
    if kind=="FA" then
        if #f~=17 or not Account(f[2]) then return true end
        local values={}; for i=3,16 do if i~=4 then values[i]=TC.Integer(f[i],0,9999999999); if not values[i] then return true end end end
        if values[3]>time()+86400 or values[12]>4 or values[13]>values[12] or values[14]>7 or #f[4]>32 or (f[17]~="" and not TC.Shop[f[17]]) then return true end
        if f[2]==TC.db.fun.account then return true end
        local old=TC.store.social.accounts[f[2]]
        TC.store.social.characters[sender]=f[2]
        if not old or values[3]>=old.revision then
            TC.store.social.accounts[f[2]]={revision=values[3],name=TC.Clean(f[4],32),qa=values[5],qc=values[6],qd=values[7],wp=values[8],ww=values[9],wg=values[10],day=values[11],
                answered=values[12],correct=values[13],result=values[14],earned=math.max(values[15],old and old.earned or 0),spent=math.max(values[16],old and old.spent or 0),title=f[17],transfers=old and old.transfers or {},grants=old and old.grants or {},counterVersions=old and old.counterVersions or {},deductions=old and old.deductions or {},wordBoard=old and old.wordBoard}
        end
        local waiting=pendingCounters[sender]; pendingCounters[sender]=nil
        for _,packet in ipairs(waiting or {}) do TC.ReceiveSocial(packet,sender) end
    else
        local revision=TC.Integer(f[4],0,time()+86400); local amount=TC.Integer(f[5],0,9999999999)
        if #f~=5 or not Account(f[2]) or not Account(f[3]) or not revision or not amount or (kind=="FB" and f[2]==f[3]) then return true end
        if TC.store.social.characters[sender]~=f[2] then
            pendingCounters[sender]=pendingCounters[sender] or {}; if #pendingCounters[sender]<50 then pendingCounters[sender][#pendingCounters[sender]+1]=message end
            return true
        end
        local permission=TC.IsGuildMaster(sender)
        if permission==nil then TC.DeferCreditPacket(message,sender); return true end
        if not permission then return true end
        local p=TC.store.social.accounts[f[2]]; p.counterVersions=p.counterVersions or {}; p.deductions=p.deductions or {}
        local key=kind..":"..f[3]; local target=kind=="FB" and p.transfers or kind=="FD" and p.deductions or p.grants
        if revision>=(p.counterVersions[key] or 0) and amount>=(target[f[3]] or 0) then
            local delta=amount-(target[f[3]] or 0); target[f[3]]=amount; p.counterVersions[key]=revision
            if delta>0 and f[3]==TC.db.fun.account then Log((kind=="FD" and "Removed " or "Received ")..delta.." Social Credits "..(kind=="FD" and "by " or "from ")..p.name) end
        end
    end
    TC.ReconcileCreditReceipts()
    if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end
    if TC.Refresh then TC.Refresh() end
    return true
end

local function Safe(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b=pcall(fn,...)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return end
    return a,b
end
function TC.PlayerKey(name)
    if type(name)~="string" then return end
    name=TC.Clean(name,90)
    if not name:find("[%s%-]") then return end
    return TC.FoldPlayerName(TC.NormalizeName(name))
end
function TC.SaveHit(slot,name,reason)
    local faction=Safe(UnitFactionGroup,"player"); if faction~="Alliance" and faction~="Horde" then return nil,"Faction information is not ready." end
    local target=TC.PlayerKey(name); if not target then return nil,"Enter the player's full first and last name, or use your enemy target." end
    local hits=TC.store.social.hits; hits[TC.owner]=hits[TC.owner] or {}; local slots=hits[TC.owner]
    if not slot then for i=1,20 do if not slots[i] or slots[i].deleted then slot=i; break end end end
    if not slot then return nil,"You already have 20 active hitlist entries." end
    slots[slot]={target=target,name=TC.Clean(name,90),reason=TC.Clean(reason,80),faction=faction=="Alliance" and "Horde" or "Alliance",revision=Rev(slots[slot] and slots[slot].revision)}
    TC.BroadcastHit(slot,slots[slot]); TC.BroadcastHitCache(); if TC.RefreshHitlist then TC.RefreshHitlist() end; return slot
end
function TC.BroadcastHit(slot,r)
    TC.QueueGuildPacket("hit:"..slot,table.concat({"HL",slot,r.revision,r.deleted and 1 or 0,r.target or "",r.faction or "",r.reason or ""},"\t"))
end
function TC.BroadcastHitDelete(owner,slot,revision)
    TC.QueueGuildPacket("hit-delete:"..owner..":"..slot,table.concat({"HD",owner,slot,revision},"\t"))
end
function TC.DeleteHit(owner,slot)
    if owner~=TC.owner and TC.IsProjectOfficer(TC.owner)~=true then return nil,"You can remove your own entries; officers can remove any." end
    local r=TC.store.social.hits[owner] and TC.store.social.hits[owner][slot]; if not r then return end
    r.deleted=true; r.revision=Rev(r.revision)
    if owner==TC.owner then TC.BroadcastHit(slot,r) else r.officer=TC.owner; TC.BroadcastHitDelete(owner,slot,r.revision) end
    TC.BroadcastHitCache()
    if TC.RefreshHitlist then TC.RefreshHitlist() end; return true
end
function TC.HitRows()
    local rows={}
    for owner,slots in pairs(TC.store.social.hits) do for slot,r in pairs(slots) do if not r.deleted then rows[#rows+1]={owner=owner,slot=slot,hit=r} end end end
    table.sort(rows,function(a,b) return a.hit.target<b.hit.target end); return rows
end
function TC.ReceiveHit(message,sender)
    local f=Fields(message); local owner=sender; local slot,revision,r
    if f[1]=="HD" then
        if #f~=4 or TC.IsProjectOfficer(sender)~=true or #f[2]>100 then return true end
        owner=TC.NormalizeName(f[2]); slot=TC.Integer(f[3],1,20); revision=TC.Integer(f[4],1,time()+86400)
        r={deleted=true,revision=revision,officer=sender}
    elseif f[1]=="HL" then
        if #f~=7 or (f[4]~="0" and f[4]~="1") or #f[5]>90 or #f[7]>80 then return true end
        slot=TC.Integer(f[2],1,20); revision=TC.Integer(f[3],1,time()+86400)
        if f[4]=="0" and (not TC.PlayerKey(f[5]) or (f[6]~="Alliance" and f[6]~="Horde")) then return true end
        r={target=f[5],name=f[5]:gsub("%-"," "),faction=f[6],reason=TC.Clean(f[7],80),deleted=f[4]=="1",revision=revision}
    else return false end
    if not slot or not revision then return true end
    if not r.deleted then r.target=TC.PlayerKey(r.target) end
    local hits=TC.store.social.hits; hits[owner]=hits[owner] or {}; local old=hits[owner][slot]
    if not old or revision>old.revision or (revision==old.revision and r.deleted) then hits[owner][slot]=r end
    if TC.RefreshHitlist then TC.RefreshHitlist() end; return true
end
local seenAlerts,lastAlert={},-100
function TC.CheckHitUnit(unit)
    if not TC.guildKey then return end
    TC.ObserveDeathEnemy(unit)
    local entry,key,name=TC.HitUnitMatch(unit)
    if not entry then return end
    TC.ShowHitAlert(name,entry.reason,unit,key)
    local now=GetTime()
    if now-(seenAlerts[key] or -100)<60 or now-lastAlert<5 then return end
    seenAlerts[key]=now; lastAlert=now
    if TC.db.fun.sound and PlaySound then pcall(PlaySound,SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,"Master") end
    return true
end
function TC.EnemyTarget()
    if not Safe(UnitIsPlayer,"target") then return end
    local f=Safe(UnitFactionGroup,"target"); local own=Safe(UnitFactionGroup,"player")
    if not f or f==own then return end
    local name,last=Safe(UnitFullName,"target"); return name and (name..(last and (" "..last) or ""))
end
function TC.StartSocial()
    TC.PublishSocial(false)
end
local frame=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","NAME_PLATE_UNIT_ADDED","PLAYER_CONTROL_LOST","PLAYER_CONTROL_GAINED"}) do pcall(frame.RegisterEvent,frame,event) end
frame:SetScript("OnEvent",function(_,event,unit)
    if not TC.db or not TC.db.fun then return end
    if event=="PLAYER_TARGET_CHANGED" then TC.CheckHitUnit("target")
    elseif event=="UPDATE_MOUSEOVER_UNIT" then TC.CheckHitUnit("mouseover")
    elseif event=="NAME_PLATE_UNIT_ADDED" then TC.CheckHitUnit(unit) end
end)
local elapsed,onFlight,lastDay=0,false,nil
frame:SetScript("OnUpdate",function(_,delta)
    if not TC.db or not TC.db.fun then return end
    elapsed=elapsed+delta; if elapsed<2 then return end; elapsed=0
    local day=TC.DayID()
    if day~=lastDay then
        lastDay=day; TC.PublishSocial(false)
        if TC.UpdateSummaryDaily then TC.UpdateSummaryDaily() end
        if TC.RefreshSocialWindow then TC.RefreshSocialWindow() end
    end
    local flying=TC.guildKey~=nil and Safe(UnitOnTaxi,"player")==true
    if flying and not onFlight and TC.ShowFlightPanel then TC.ShowFlightPanel() end
    if not flying and onFlight and TC.HideFlightPanel then TC.HideFlightPanel() end
    onFlight=flying
    TC.CheckHitUnit("target"); TC.CheckHitUnit("mouseover")
    local plates=C_NamePlate and Safe(C_NamePlate.GetNamePlates)
    if type(plates)=="table" and not (issecrettable and issecrettable(plates)) then
        for _,plate in ipairs(plates) do
            local token=Safe(function() return plate.namePlateUnitToken end)
            if not (issecretvalue and issecretvalue(token)) and type(token)=="string" then TC.CheckHitUnit(token) end
        end
    end
    TC.RefreshHitAlert()
end)
