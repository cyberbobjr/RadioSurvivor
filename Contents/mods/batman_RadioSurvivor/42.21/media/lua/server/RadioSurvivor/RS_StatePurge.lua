if isClient() then return end
--[[
Purge of dead notebook characters (C17). Authority only. A dead character (record.retired, RS_Carnet_Server
characterDeath) is never read again by the notebook; its record kept its contacts (up to MAX_HISTORY lines per NPC),
its known missions and the fiches they cite, for ever.

    local Purge = require 'RadioSurvivor/RS_StatePurge'
    Purge.run(data, today, force)  -- one bounded pass; true when the state changed
    Purge.attach(S)                -- done by RS_State: reducer over the codec bounds, pass every game hour

- First pass that sees a retired record without a date: retiredDay = today (deaths before this code included).
- STRIP_DAYS game days after the death: contacts, known missions and radio history emptied (record kept: id, owner,
  name, retired, retiredDay), so the uncontacted fiches are dropped by the notebook prune.
- DROP_DAYS game days after the death, when nothing refers to it any more: the record itself is removed. Still in
  use: a mission it takes part in, is invited to, claimed or has a transaction on; a frozen life log (last pages,
  E15); a reputation entry (dropped by Rep.prune, E04-T12). The memorial (E14) keeps its own names in the facts.
- At most BATCH records per pass (EveryHours); force (the state is over the codec bounds, RS_State reducers): every
  retired record stripped at once, dropped if not in use, no batch limit.
Living characters are never touched.
]]
local Purge = {}
Purge.STRIP_DAYS = 7
Purge.DROP_DAYS = 30
Purge.BATCH = 50

local function inUse(data, cid)
    for _, m in pairs(type(data.missions) == 'table' and data.missions or {}) do
        if type(m) == 'table' then
            if (type(m.participants) == 'table' and m.participants[cid]) or (type(m.invited) == 'table' and m.invited[cid])
                or m.claimedBy == cid or (type(m.transaction) == 'table' and m.transaction.character == cid) then
                return true
            end
        end
    end
    if type(data.reputation) == 'table' and data.reputation[cid] ~= nil then return true end
    local okL, LifeLog = pcall(require, 'RadioSurvivor/RS_LifeLog')
    if okL and type(LifeLog) == 'table' and LifeLog.get then
        local log = LifeLog.get(cid)
        if log ~= nil then return true end
    end
    return false
end
Purge.inUse = inUse

local function today()
    local okR, Rep = pcall(require, 'RadioSurvivor/RS_Reputation')
    return okR and type(Rep) == 'table' and Rep.today and Rep.today() or nil
end

function Purge.run(data, day, force)
    if type(data) ~= 'table' or type(data.characters) ~= 'table' then return false end
    day = day or today()
    if type(day) ~= 'number' and not force then return false end
    local retired = {}
    for cid, record in pairs(data.characters) do
        if type(record) == 'table' and record.retired == true then retired[#retired + 1] = cid end
    end
    table.sort(retired)
    local changed, done = false, 0
    for _, cid in ipairs(retired) do
        if not force and done >= Purge.BATCH then break end
        local record = data.characters[cid]
        if type(record.retiredDay) ~= 'number' and day then record.retiredDay, changed = day, true end
        -- Unknown game day (forced pass only): strip, never drop.
        local age = (day and type(record.retiredDay) == 'number') and day - record.retiredDay or -1
        if (force or age >= Purge.STRIP_DAYS) and not record.stripped then
            record.contacts, record.knownMissions, record.radio, record.stripped = {}, {}, nil, true
            changed, done = true, done + 1
        end
        if record.stripped and (age >= Purge.DROP_DAYS or (force and age >= Purge.STRIP_DAYS))
            and not inUse(data, cid) then
            data.characters[cid] = nil
            changed, done = true, done + 1
        end
    end
    return changed
end

-- Called once by RS_State (no require cycle).
function Purge.attach(S)
    S.reducers[#S.reducers + 1] = function(data, force) return Purge.run(data, nil, force) end
    if Events and Events.EveryHours then
        Events.EveryHours.Add(function()
            if S.data and not S.blocked and Purge.run(S.data) then S.dirty = true end
        end)
    end
end

return Purge
