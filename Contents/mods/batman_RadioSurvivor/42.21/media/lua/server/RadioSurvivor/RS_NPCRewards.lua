-- Server-only adapter: real household surplus before the closed reward tables.
if isClient() then return end
local P = require 'RadioSurvivor/RS_NPCProvider'
local Config = require 'RadioSurvivor/RS_Config'
local Relations = require 'RadioSurvivor/RS_Relations'
local Reputation = require 'RadioSurvivorCore/RC_Reputation'
local N = {}

-- Never infer a living member from a cached notebook fiche or a loaded body.
function N.resolve(npc)
    if type(npc) ~= 'table' or npc.dead or npc.alive == false or npc.incarnation == nil then
        return nil, 'requester unavailable'
    end
    local E = LivingKnox
    local G = E and E.Groups
    if not G or not G.findNpc or not G.get then return nil, 'unsupported provider' end
    local record = P.npc(npc.incarnation)
    if not record then return nil, 'requester unavailable' end
    local gid, mid = G.findNpc(npc.incarnation)
    local g = gid and G.get(gid)
    local member = g and g.members and g.members[mid]
    if not member or member.alive ~= true or record.group ~= gid then return nil, 'requester unavailable' end
    local living = 0
    for _, m in pairs(g.members) do if m.alive == true then living = living + 1 end end
    if living == 0 then return nil, 'group unavailable' end
    return { group = gid, member = mid, data = g, role = member.role }
end

function N.describe(npc, character)
    local r, why = N.resolve(npc)
    if not r then return nil, why end
    local cfg = Config.NPC_REWARD_TABLES
    local lessons = Config.NPC_REWARD_TEACHES or {}
    local relation = Relations.view(npc, character)
    local trusted = relation and (relation.level == 'favorable' or relation.level == 'trusting')
    local good = Reputation.level(character) ~= 'bad'
    local teaches = trusted and good and lessons[r.role] or nil
    if r.data.type == 'raiders' and teaches == 'Doctor' then teaches = nil end
    local rewards = {'cache'}
    if trusted and good then rewards[#rewards + 1] = 'frequency'; rewards[#rewards + 1] = 'stashmap' end
    if teaches then rewards[#rewards + 1] = 'lesson' end
    local home = r.data.home
    local source = {id='group:' .. r.group, group=r.group, cache_table=cfg[r.data.type] or 'food',
        teaches=teaches, rewards=rewards, shares={}, places={}}
    if home then source.places[1] = {id='home', x=home.x, y=home.y, z=home.z or 0, label='Home'} end
    source.material = function(player) return N.takeMaterial(npc, character, player) end
    return source
end

-- One item of the household surplus (Living Knox: never during rationing, only above the target reserve, fitting in the
-- inventory); the returned object retains its identity (E18-T29: same rule as the lot of Living Knox alone).
function N.takeMaterial(npc, character, player)
    local r, why = N.resolve(npc)
    if not r then return nil, why end
    local Rewards = LivingKnox.MissionRewards
    if not Rewards then return nil, 'stock unavailable' end
    return Rewards.take(r.group, character, player)
end

-- nil means the historical common-lot path still owns this provider.
function N.claim(store, m, player, character, token)
    local npc = store.data.npcs and store.data.npcs[m.npc]
    if not npc or npc.incarnation == nil then return nil end
    local source, why = N.describe(npc, character)
    if not source then
        if why == 'unsupported provider' then return nil end
        return false, 'State'
    end
    -- Existing supply contracts have already paid this exact lot from the group's reserve at completion.
    -- Preserve that escrow: taking stock again would charge the household twice.
    if m.supply and (m.rewardCount or 0) > 0 then return nil end
    if m.transaction or m.state ~= 'success' or not m.participants[character] or m.claimedBy ~= '' then
        return false, 'State'
    end
    local R = require 'RadioSurvivor/RS_Rewards'
    if R.choose and not R.choose(store.data, source, m, character, player) then return nil end
    m.transaction = {kind='reward', token=token, character=character, ids={}, stage='prepared'}
    if not store.save() then return false, 'Storage' end
    -- Persist the shared withdrawal BEFORE any physical stock removal or reward effect.
    m.claimedBy = character
    m.claimedName = store.data.characters[character].name
    m.revision = m.revision + 1
    if not store.save() then return false, 'Recovery' end
    local rec, err = R.grant(store, source, m, player, character)
    if not rec or (err ~= nil and rec.status ~= 'applied') then
        m.transaction.error = err or 'reward_failed'
        store.save()
        return false, 'Recovery'
    end
    m.transaction.stage = 'applied'
    if not store.save() then return false, 'Recovery' end
    m.transaction = nil
    if not store.save() then return false, 'Recovery' end
    return true
end
return N
