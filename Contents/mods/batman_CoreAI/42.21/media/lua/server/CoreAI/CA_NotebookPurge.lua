if isClient() then return end
--[[
CoreAI: purge of dead notebook characters (C17; E21-T04: with the notebook store of the core mod). Authority
only. A dead character (record.retired, notebook server characterDeath) is never read again by the notebook; its
record kept its contacts (up to MAX_HISTORY lines per NPC), its known missions and the fiches they cite, for ever.

    local Purge = require 'CoreAI/CA_NotebookPurge'
    Purge.run(data, today, force, keepers)  -- one bounded pass; true when the state changed

Called by CA_NotebookStore: once per game day from its save, and forced over the codec bounds.

- First pass that sees a retired record without a date: retiredDay = today (deaths before this code included).
- STRIP_DAYS game days after the death: contacts, known missions and radio history emptied (record kept: id, owner,
  name, retired, retiredDay), so the uncontacted fiches are dropped by the notebook prune.
- DROP_DAYS game days after the death, when nothing refers to it any more: the record itself is removed. Still in
  use: a mission it takes part in, is invited to, claimed or has a transaction on; a reputation entry (dropped by
  Rep.prune, E04-T12); a keeper of a mod that uses the notebook (keepers: list of fn(cid) -> true while that mod still
  needs the record, registered by CA_NotebookStore.onPurge).
- At most BATCH records per pass (first save of each game day); force (the state is over the codec bounds): every
  retired record stripped at once, dropped if not in use, no batch limit.
Living characters are never touched.
]]
local Purge = {}
Purge.STRIP_DAYS = 7
Purge.DROP_DAYS = 30
Purge.BATCH = 50

local function inUse(data, cid, keepers)
    for _, m in pairs(type(data.missions) == 'table' and data.missions or {}) do
        if type(m) == 'table' then
            if (type(m.participants) == 'table' and m.participants[cid]) or (type(m.invited) == 'table' and m.invited[cid])
                or m.claimedBy == cid or (type(m.transaction) == 'table' and m.transaction.character == cid) then
                return true
            end
        end
    end
    -- E18-T22: reputation kept by the core mod.
    local okRep, Rep = pcall(require, 'CoreAI/CA_Reputation')
    local rep = okRep and type(Rep) == 'table' and type(Rep.data) == 'table' and Rep.data.reputation or nil
    if type(rep) == 'table' and rep[cid] ~= nil then return true end
    for _, keep in ipairs(type(keepers) == 'table' and keepers or {}) do
        if keep(cid) == true then return true end
    end
    return false
end
Purge.inUse = inUse

function Purge.today()
    local okR, Rep = pcall(require, 'CoreAI/CA_Reputation')
    return okR and type(Rep) == 'table' and Rep.today and Rep.today() or nil
end

function Purge.run(data, day, force, keepers)
    if type(data) ~= 'table' or type(data.characters) ~= 'table' then return false end
    day = day or Purge.today()
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
            and not inUse(data, cid, keepers) then
            data.characters[cid] = nil
            changed, done = true, done + 1
        end
    end
    return changed
end

return Purge
