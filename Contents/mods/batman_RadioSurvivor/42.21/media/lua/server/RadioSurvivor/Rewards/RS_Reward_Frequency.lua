-- Reward kind `frequency` (pool entry frequency:<weight>, E20-T04): the frequency of another active voice (a voice
-- the sheet shares, or for a group radio its own voice first, then every other voice), written in the private radio
-- log of the recipient only.
if isClient() then return end
local Rewards = require 'RadioSurvivor/RS_Rewards'

local Frequency = {}

-- {voice, khz, name} of the first active voice with a served frequency, or nil.
function Frequency.find(source)
    local personas = require 'RadioSurvivor/RS_Personas'
    local ids = source.shares or {}
    if source.group then
        ids = {}
        local own = require('RadioSurvivor/RS_GroupRadio').voiceId(source.group)
        if own then ids[#ids + 1] = own end
        local others = personas.ids()
        for _, id in ipairs(others) do if id ~= own then ids[#ids + 1] = id end end
    end
    for _, id in ipairs(ids) do
        local sheet = personas.get(id)
        if id ~= source.id and sheet and sheet.state == 'active' then
            local frequencies = personas.served(id)
            if frequencies[1] then return {voice = id, khz = frequencies[1], name = sheet.name} end
        end
    end
    return nil
end

local function available(ctx)
    return Frequency.find(ctx.source)
end

local function reserve(_, rec, detail)
    rec.voice, rec.khz, rec.name = detail.voice, detail.khz, detail.name
    return true
end

local function apply(ctx, rec)
    require('RadioSurvivor/RS_RadioLog').add(ctx.cid, rec.khz, 'reply',
        (rec.name or rec.voice) .. ' (' .. string.format('%.1f MHz', rec.khz / 1000) .. ')', rec.voice)
    return true
end

local function describe()
    return 'A radio contact has been added to your private notebook.'
end

Rewards.register('frequency', {available = available, reserve = reserve, apply = apply, describe = describe})

return Frequency
