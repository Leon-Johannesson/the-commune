local _, TC = ...

local function Account(id)
    return type(id) == "string" and #id <= 40 and id:match("^[a-zA-Z0-9%-]+$")
end

local function Scores()
    local social = TC.store and TC.store.social
    if not social then return end
    social.dailyScores = social.dailyScores or {}
    return social.dailyScores
end

function TC.DailyScorePacket(account, day, score)
    return table.concat({"FQ", account, day, score.revision, score.total, score.colors, score.wordleResult}, "\t")
end

function TC.DecodeDailyScore(message)
    if type(message) ~= "string" or #message > 254 then return end
    local account, day, revision, total, colors, wordle = message:match("^FQ\t([^\t]+)\t(%d+)\t(%d+)\t([45])\t([012]+)\t([0-7])$")
    day = TC.Integer(day, 0, TC.DayID())
    revision = TC.Integer(revision, 0, time() + 86400)
    total, wordle = tonumber(total), tonumber(wordle)
    if not Account(account) or not day or not revision or not total or #colors ~= total then return end
    local answered, correct = 0, 0
    for value in colors:gmatch(".") do
        if value ~= "0" then answered = answered + 1 end
        if value == "2" then correct = correct + 1 end
    end
    return account, {day=day, revision=revision, total=total, colors=colors, answered=answered, correct=correct, wordleResult=wordle}
end

function TC.DailyScoreAdvances(old,score)
    if old then
        if score.revision < old.revision or score.total ~= old.total then return false end
        -- Answers and completed Wordle results are final. A delayed or relayed
        -- snapshot cannot erase them, including a wrong answer worth zero points.
        for i = 1, old.total do
            local previous = old.colors:sub(i, i)
            if previous ~= "0" and previous ~= score.colors:sub(i, i) then return false end
        end
        if old.wordleResult ~= 0 and score.wordleResult ~= old.wordleResult then return false end
        if score.revision == old.revision and score.colors == old.colors and score.wordleResult == old.wordleResult then return false end
    end
    return true
end

function TC.RecordDailyScore(account, score, relayed)
    local all = Scores()
    if not all then return end
    local days = all[account] or {}
    local old = days[score.day]
    if not TC.DailyScoreAdvances(old,score) then return end
    local profile = TC.store.social.accounts[account]
    score.name = TC.Clean(profile and profile.name or (old and old.name) or "Unknown", 32)
    days[score.day], all[account] = TC.StampSnapshot(score,relayed), days
    return true
end

function TC.RecordOwnDailyScore(day, count, state, revision)
    if not TC.guildKey then return end
    local colors = {}
    for i = 1, count do
        local answer = state.answers[i]
        colors[i] = answer and (answer.correct and "2" or "1") or "0"
    end
    local account = TC.db.fun.account
    local packet = TC.DailyScorePacket(account, day, {
        revision=revision, total=count, colors=table.concat(colors), wordleResult=state.wordleResult or 0
    })
    local _, score = TC.DecodeDailyScore(packet)
    if score then TC.RecordDailyScore(account, score) end
end

function TC.BroadcastDailyScore()
    local all = Scores()
    local account, day = TC.db.fun.account, TC.DayID()
    local score = all and all[account] and all[account][day]
    if score then TC.QueueGuildPacket("daily-score", TC.DailyScorePacket(account, day, score)) end
end

function TC.QuizBoards()
    local rows = {}
    local day, all = TC.DayID(), Scores()
    for account, days in pairs(all or {}) do
        local score = days[day]
        if score and (score.answered > 0 or account == TC.db.fun.account) then
            local profile = TC.store.social.accounts[account]
            rows[#rows + 1] = {account=account, own=account == TC.db.fun.account, name=profile and profile.name or score.name, score=score}
        end
    end
    table.sort(rows, function(a, b)
        if a.own ~= b.own then return a.own end
        if a.name ~= b.name then return a.name < b.name end
        return a.account < b.account
    end)
    return rows
end
