local _,TC=...
function TC.FoldPlayerName(name)
    -- byte-wise string.lower is locale-dependent on Windows and can turn
    -- UTF-8 lead bytes into different bytes. Only lowercase ASCII byte ranges.
    name=name:gsub("[A-Z]",function(letter) return letter:lower() end)
    for upper,lower in pairs({["À"]="à",["Á"]="á",["Â"]="â",["Ã"]="ã",["Ä"]="ä",["Å"]="å",["Æ"]="æ",["Ç"]="ç",["È"]="è",["É"]="é",["Ê"]="ê",["Ë"]="ë",["Ì"]="ì",["Í"]="í",["Î"]="î",["Ï"]="ï",["Ð"]="ð",["Ñ"]="ñ",["Ò"]="ò",["Ó"]="ó",["Ô"]="ô",["Õ"]="õ",["Ö"]="ö",["Ø"]="ø",["Ù"]="ù",["Ú"]="ú",["Û"]="û",["Ü"]="ü",["Ý"]="ý",["Þ"]="þ",["ẞ"]="ß"}) do name=name:gsub(upper,lower) end
    return name
end
function TC.IsGuildMaster(owner)
    if not TC.guildKey then return false end
    if owner==TC.owner then local _,_,rank=GetGuildInfo("player"); return rank~=nil and rank==0 end
    local member=TC.GuildRoster()[owner]
    if member then return member.rank==0 end
    return nil
end
function TC.WordReward(guesses) return ({5,3,2,1,1,1})[guesses] or 0 end
function TC.WordBoards()
    local rows={}
    for account,p in pairs(TC.store.social.accounts) do
        local board=p.wordBoard
        if account~=TC.db.fun.account and board and board.day==TC.DayID() then rows[#rows+1]={name=p.name,board=board} end
    end
    table.sort(rows,function(a,b) return a.name<b.name end); return rows
end
function TC.BroadcastWordBoard()
    local d,day=TC.DailyState()
    if not d.wordleResult or d.wordleResult>6 then return end
    local colors={}
    for _,word in ipairs(d.guesses) do
        for _,value in ipairs(TC.WordFeedback(word,TC.WordAnswer())) do colors[#colors+1]=tostring(value) end
    end
    TC.QueueGuildPacket("wordle-board",table.concat({"FW",TC.db.fun.account,day,d.wordleResult,table.concat(colors)},"\t"))
end
