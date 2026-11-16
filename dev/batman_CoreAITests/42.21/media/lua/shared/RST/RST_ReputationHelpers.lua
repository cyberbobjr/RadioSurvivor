--[[
RST_ReputationHelpers - authority helpers of the reputation suites (E04-T14; E21-T11: split from the rs.reputation suite
of batman_RadioSurvivorTests): ca.reputation (CA_Reputation.lua, this mod), lk.reputation (RST_LKReputation.lua of
batman_LivingKnoxTests) and rs.reputation (batman_RadioSurvivorTests). Development mod only.
Load with: require "RST/RST_ReputationHelpers". No side effect at load time (definitions only).

    local RP = RST.ReputationSuite
    RP.setup(t)                      { Server, S (notebook store), Rep (CA_Reputation), p, cid, M (CA_Missions) };
                                     skip on an MP client or when the notebook storage is blocked
    RP.guard(t, c, cid)              reputation entry of cid restored at the end, outcomes created meanwhile dropped
    RP.baseline(t, c, cid, level)    test baseline of the level (CA_Reputation.testSetLevel), skip when refused
    RP.mute(t, c)                    listeners of closed missions muted during the test
    RP.second(t)                     second online player, its account and character (MP), or nil
    RP.testMission(t, c, npcId, participants)
                                     active test mission of npcId with participants { [cid] = name } (removed at the end)
    RP.revisions(c, except)          { [cid] = revision } of every reputation entry but except
    RP.readBy(t, target, args, after) step "rep.read" (RST_PeerChecksRep.lua) asked to target
    RP.firstData(res)                data of the first answer of a step, or {}
    RP.outcomes()                    facts of the missions in the reputation of the core mod (CA_Reputation, E18-T22)
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_CarnetHelpers"
require "RST/RST_PeerChecksRep"

RST.ReputationSuite = RST.ReputationSuite or {}
local RP = RST.ReputationSuite
RP.FILE = "reputation-persist.txt"
RP.HEADER = "RSREPUTATION1"
RP.REQUESTER = "RST Requester"
RP.READ_MS = 10000
RP.DEATH_MS = 8000

local Steps = RST.Steps
local N = RST.CarnetHelpers

local function isServerSide() return type(isServer) == "function" and isServer() end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Notebook server, its state, the reputation module, the requester and its character.
function RP.setup(t)
    if type(isClient) == "function" and isClient() then t:skip("the reputation lives on the authority") end
    local Server = N.notebook(t)
    local S = Server.store
    if S.blocked then t:skip("notebook storage blocked") end
    local Rep = require "CoreAI/CA_Reputation"
    t:ok(type(Rep) == "table" and type(Rep.testSetLevel) == "function", "CA_Reputation (E04, core mod) not loaded")
    t:ok(Rep.ensure(), "reputation state of the core mod not loaded")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local cid = N.character(t, p)
    return { Server = Server, S = S, Rep = Rep, p = p, cid = cid, M = require "CoreAI/CA_Missions" }
end

-- The reputation entry of cid is restored at the end; outcomes created during the test are dropped.
function RP.guard(t, c, cid)
    local data = c.Rep.data -- E18-T22: reputation kept by the core mod
    local saved = copy(type(data.reputation) == "table" and data.reputation[cid] or nil)
    local known = {}
    for id in pairs(data.outcomes or {}) do known[id] = true end
    t:defer(function()
        if type(data.reputation) ~= "table" then data.reputation = {} end
        data.reputation[cid] = saved
        local drop = {}
        for id in pairs(data.outcomes or {}) do if not known[id] then drop[#drop + 1] = id end end
        for _, id in ipairs(drop) do data.outcomes[id] = nil end
        c.Rep.save()
        c.Server.publish()
    end, "reputation of " .. cid .. " restored")
end

function RP.baseline(t, c, cid, level)
    local ok, why = c.Rep.testSetLevel(nil, cid, level)
    if not ok then t:skip("test baseline refused: " .. tostring(why)) end
end

-- Listeners of closed missions (chronicle, observations) muted during the test: a test mission is no event.
function RP.mute(t, c)
    local previous = c.M.onFinished
    c.M.onFinished = nil
    t:defer(function() c.M.onFinished = previous end, "listeners of closed missions restored")
end

-- Second online player and its character (MP), or nil.
function RP.second(t)
    if not isServerSide() then return nil end
    local name = Steps.others(t)[1]
    local p = name and Steps.playerOf(name) or nil
    if p == nil then return nil end
    return p, name, N.character(t, p)
end

-- Active test mission of `npcId` with participants { [cid] = name }, inserted in the state (removed at the end).
function RP.testMission(t, c, npcId, participants)
    local id = "rst-rep-" .. string.format("%.0f", RST.now())
    local m = { id = id, npc = npcId, template = "deliver", offer = "first_aid_v1", titleKey = "IGUI_CA_Mission_FirstAid",
        state = "active", revision = 1, durationMs = 3600000, remainingMs = 3600000, participants = {}, invited = {},
        rewardType = "", rewardCount = 0, claimedBy = "", receipts = {}, quantity = 1, delivered = 0, accepted = {},
        requesterName = RP.REQUESTER }
    for cid, name in pairs(participants) do m.participants[cid] = { name = name } end
    c.S.data.missions[id] = m
    t:defer(function() c.S.data.missions[id] = nil; c.S.dirty = true end, "test mission " .. id .. " removed")
    return m
end

function RP.revisions(c, except)
    local out = {}
    for cid, e in pairs(c.Rep.data.reputation or {}) do
        if cid ~= except then out[cid] = e.revision end
    end
    return out
end

function RP.readBy(t, target, args, after)
    Steps.ask(t, "rep.read", args, { target = target, timeoutMs = RP.READ_MS }, after)
end

function RP.outcomes()
    local Rep = require "CoreAI/CA_Reputation"
    Rep.ensure()
    return Rep.data and Rep.data.outcomes or {}
end

function RP.firstData(res)
    local e = res and res.list and res.list[1]
    return e and e.data or {}
end

return RP
