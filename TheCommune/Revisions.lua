local _, TC = ...

local function Clock()
    if not TC.db or not TC.owner then return end
    TC.db.syncClocks = TC.db.syncClocks or {}
    local key = TC.guildKey or "personal"
    TC.db.syncClocks[key] = TC.db.syncClocks[key] or {}
    return TC.db.syncClocks[key]
end

function TC.ObserveOwnRevision(revision)
    revision = TC.Integer(revision, 0, time() + 86400)
    local clock = revision and Clock()
    if clock then clock[TC.owner] = math.max(clock[TC.owner] or 0, revision) end
end

function TC.NextRevision(previous)
    local clock = Clock()
    local revision = math.max(time(), (tonumber(previous) or 0) + 1, (clock and clock[TC.owner] or 0) + 1)
    if clock then clock[TC.owner] = revision end
    return revision
end

function TC.StampSnapshot(record, relayed)
    record.syncSource = relayed and "cache" or "owner"
    record.receivedAt = time()
    return record
end

function TC.SnapshotNewer(old, incoming, relayed, oldKey, newKey)
    if not old or incoming.revision > old.revision then return true end
    if incoming.revision < old.revision then return false end
    -- Deletion is a final fact at this revision, even when the live owner and
    -- a relay arrive in the opposite order. Receipt time never makes data new.
    if (not not incoming.deleted) ~= (not not old.deleted) then return not not incoming.deleted end
    if oldKey == newKey then
        if not relayed then TC.StampSnapshot(old, false) end
        return false
    end
    if relayed and old.syncSource == "owner" then return false end
    if not relayed and old.syncSource ~= "owner" then return true end
    -- Conflicting caches with equal revisions converge without arrival order
    -- deciding the winner. A subsequent direct owner snapshot can resolve it.
    return (newKey or "") > (oldKey or "")
end
