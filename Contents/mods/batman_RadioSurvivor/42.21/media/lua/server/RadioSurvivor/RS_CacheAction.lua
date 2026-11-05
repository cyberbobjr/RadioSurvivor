if isClient() then return end
--[[
Voice action place_cache (E11-T06; the caches themselves live in the core mod since E18-T05: RC_Caches). Authority
only. Required by RadioSurvivor_Server (executor of place_cache). Returns the core module RC_Caches, completed by
Caches.voiceMission and Caches.register.

Voice action place_cache { table } is a compatibility retry only: the mission must already have succeeded and
RS_Rewards must have selected and reserved its cache. The parameter must match that server-selected table; it never
selects contents, creates an active-mission reward, or replaces the reward rotation. New reward sites come from the
voice's allowed places. Refusals include not_done, no_reward and bad_table.
]]
local Caches = require 'RadioSurvivorCore/RC_Caches'
local S = require 'RadioSurvivor/RS_State'
local Actions = require 'RadioSurvivor/RS_Actions'
local V = require 'RadioSurvivor/RS_MissionVoice'

-- Last mission given by this voice to this character: the open one, else its latest success. nil without any.
function Caches.voiceMission(state, voice, cid)
    local open = V.open(state, voice, cid)
    if open then return open end
    local d = V.donor(state, voice, cid, false)
    if not d then return nil end
    local best
    for _, m in pairs(state.missions) do
        if m.npc == d.id and m.state == 'success' and (not best or (m.closedAt or 0) > (best.closedAt or 0)) then
            best = m
        end
    end
    return best
end

local function validate(params)
    for key in pairs(params) do
        if key ~= 'table' then return false end
    end
    return Caches.isTable(params.table)
end

local function execute(params, ctx)
    local state = S.data
    if type(state) ~= 'table' or S.blocked then return false, 'storage' end
    local cid = type(ctx) == 'table' and ctx.cid or nil
    local record = type(cid) == 'string' and state.characters[cid] or nil
    if not record or record.retired then return false, 'no_character' end
    local m = Caches.voiceMission(state, ctx.voice, cid)
    if not m then return false, 'no_mission' end
    if m.state ~= 'success' then return false, 'not_done' end
    -- Legacy action is only a retry for the server-selected mission reward, never an item selector.
    if not m.extendedReward or m.extendedReward.kind ~= 'cache' or not m.cache then
        return false, 'no_reward'
    end
    if params.table ~= m.cache.table then return false, 'bad_table' end
    Caches.place(S, m.cache)
    return true
end

function Caches.register()
    return Actions.register('place_cache', {validate = validate, cooldownMs = Caches.COOLDOWN_MS, execute = execute})
end

Caches.register()

return Caches
