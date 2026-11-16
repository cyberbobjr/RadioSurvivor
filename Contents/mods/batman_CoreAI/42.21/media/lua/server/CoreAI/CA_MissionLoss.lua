if isClient() then return end
--[[
CoreAI: missions lost with a dead character (E23-T02, ADR D07). Authority only. Called by the notebook server when a
notebook character dies (CA_NotebookServer.characterDeath).

    Loss.died(state, character, record) -> number of missions left
        every active mission (of a present giver) the dead character took part in: his participation ends
        (CA_Missions.participantDied: the mission is lost when he was alone, it goes on for the other participants);
        a notice is kept for the next character of the same account and slot (record.owner, record.slot)
    Loss.notices(state, record) -> list of { name, titleKey, requester, team }
        notices of the account of this living character, newest first, for LOST_NOTICE_HOURS game hours (all of them
        without game time); never a mission id nor a place. team = true: the mission goes on for the others

State: state.lostNotices = { ['<owner>|<slot>'] = { { name, titleKey, requester, team, hour }, ... } }, at most
LOST_NOTICE_MAX per account (the oldest dropped first). ASCII only (Kahlua lexer).
]]
local Config = require 'CoreAI/CA_MissionConfig'
local Clock = require 'CoreAI/CA_GameClock'
local M = require 'CoreAI/CA_Missions'

local Loss = {}

local function accountKey(record)
    return tostring(record.owner) .. '|' .. tostring(record.slot)
end

local function fresh(notice, h)
    return h == nil or type(notice.hour) ~= 'number' or h - notice.hour <= Config.LOST_NOTICE_HOURS
end

local function remember(state, record, notice)
    if type(state.lostNotices) ~= 'table' then state.lostNotices = {} end
    local key = accountKey(record)
    local list = state.lostNotices[key] or {}
    local h = Clock.hours()
    local kept = {notice}
    for _, old in ipairs(list) do
        if #kept < Config.LOST_NOTICE_MAX and fresh(old, h) then kept[#kept + 1] = old end
    end
    state.lostNotices[key] = kept
end

function Loss.died(state, character, record)
    if type(state) ~= 'table' or type(state.missions) ~= 'table' or type(record) ~= 'table' then return 0 end
    local count = 0
    for _, m in pairs(state.missions) do
        local outcome = M.present(m) and M.participantDied(state, m, character) or nil
        if outcome then
            remember(state, record, {name = tostring(record.name or ''), titleKey = m.titleKey,
                requester = tostring(M.requester(state, m) or ''), team = outcome == 'continues',
                hour = Clock.hours()})
            count = count + 1
        end
    end
    return count
end

function Loss.notices(state, record)
    local out = {}
    local list = type(state) == 'table' and type(state.lostNotices) == 'table' and type(record) == 'table'
        and state.lostNotices[accountKey(record)] or nil
    if type(list) ~= 'table' then return out end
    local h = Clock.hours()
    for _, n in ipairs(list) do
        if fresh(n, h) then
            out[#out + 1] = {name = n.name, titleKey = n.titleKey, requester = n.requester, team = n.team == true}
        end
    end
    return out
end

return Loss
