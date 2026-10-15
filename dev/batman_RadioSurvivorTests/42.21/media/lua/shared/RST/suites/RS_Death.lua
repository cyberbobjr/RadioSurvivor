--[[
rs.death - REAL death of the second client on a dedicated server, then its new character (E00-T02, E03-T04,
E15-T02; E01-T16 second client). Tags "server" and "world": the authority, from RST.server of the admin client of the
MP campaign (autoclient.py --mp --clients 2), save rstest*. Client steps: RST_PeerChecksDeath.lua (death.prepare,
death.corpse, death.after) and RST_PeerChecks2.lua (carnet.claim).

    1. death        the second client B leaves god mode the vanilla way (its client: setGodMod(false) +
                    sendPlayerExtraInfo); a zombie carrying the requester's identity in its ModData dies through the
                    notebook death handler: nothing retired (a zombie retires nothing); B gets a marked "known
                    mission" on its notebook record; a one-shot OnCharacterDeath witness is armed for B; the server
                    kills B with player:die() (the server path of a lethal hit, IsoGameCharacter.hitConsequences:
                    GameServer.server -> die(); OnCharacterDeath, then the corpse that takes the inventory, then the
                    PlayerDeath packet to the clients, IsoPlayer.onDied). Checked on the server: OnCharacterDeath
                    seen for B, B's identity retired, unbound and gone from the server ModData (E00-T02), the
                    requester's identity untouched (another account retires nothing), the witness paper added at
                    OnCharacterDeath is in the container of B's corpse (E15-T02, method retained in
                    docs/derniers-pages-cadavre.md); the requester's client claims B's old identity and gets its own
                    (carnet.claim) and finds the paper in the corpse as ITS client received it (death.corpse).
    2. new character  B's driver (RST_AutoClient.lua) presses Respawn on the post-death screen and NEXT twice on the
                    in-game character creation; the server then sees a living character of account B bound to a NEW
                    identity of the same account, the old one retired and bound to nobody, without the old marked
                    mission nor any mission the old identity was engaged in or invited to (E03-T04); the real hello
                    handler, asked by the server for the new character with the OLD identity, gives a fresh one,
                    never the old (E00-T02: a dead character cannot be claimed again; the extra record is removed and
                    the binding restored); B's client holds the new identity in its notebook and gets its god mode back
                    (death.after).
    E00-T02 (shared mission): before the kill, a real Living Knox test NPC (RST.Fixtures.spawnNpc) requests an ACTIVE
                    mission where the requester and B are engaged (RST.Fixtures.engagedMission); after B's death and
                    again after its new character, the mission is still active with the requester engaged (the
                    death of a participant closes nothing for the others). Removed at the end (or at once when B did
                    not die). Without the Living Knox test API: FAIL.
Solo: SKIP (the only player would die and end the run). Dedicated server with one client: SKIP (no second client).
With two clients, every check that cannot be made FAILS. Cleanup: B's corpse removed (RemoveCorpseFromMap sent to
the clients), marked mission removed, witness disarmed. Server console lines: "[RST] death ...".
Outside the game: tests/test_death_suites.py.
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_PeerChecks2"
require "RST/RST_PeerChecksDeath"
require "RST/RST_Fixtures"

RST.DeathSuite = RST.DeathSuite or {}
local D = RST.DeathSuite
local PD = RST.PeerDeath
local Steps = RST.Steps

D.KEY = "RS_CarnetCharacter"     -- RS_Carnet_Server.lua IDENTITY_KEY
D.BOUND_MS = 20000                -- identity of a connected client (hello at game start)
D.GOD_MS = 10000                  -- ExtraInfo packet of the client applied on the server
D.DEATH_MS = 15000                -- OnCharacterDeath, then the corpse
D.RESPAWN_MS = 150000             -- post-death screen (3 s), driver delay (5 s), creation, hello
D.RADIUS = 3

local function log(msg) print("[RST] death " .. msg) end

local function userOf(p)
    local ok, name = pcall(function() return p:getUsername() end)
    return ok and name ~= nil and tostring(name) or nil
end

-- Authority on a dedicated server with a ready notebook; solo and MP clients skip.
local function authority(t)
    if type(isClient) == "function" and isClient() then t:skip("authority only (dedicated server), not an MP client") end
    if not (type(isServer) == "function" and isServer()) then
        t:skip("solo: the only player would die and end the run; the real death runs on a dedicated server with a "
            .. "second client (autoclient.py --mp --clients 2, RST.server)")
    end
    local Server = RS_CarnetServer
    t:ok(type(Server) == "table" and type(Server.store) == "table" and type(Server.store.data) == "table",
        "notebook server state not ready (RS_CarnetServer)")
    t:ok(not Server.store.blocked, "notebook storage is blocked")
    return Server, Server.store.data
end

local function save(Server)
    Server.store.dirty = true
    if type(Server.store.save) == "function" then pcall(Server.store.save) end
end

-- Missions where character is engaged or invited: list of ids.
local function missionsOf(data, character)
    local out = {}
    for id, m in pairs(data.missions or {}) do
        if (m.participants and m.participants[character]) or (m.invited and m.invited[character]) then
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

function D.removeMark(Server, data)
    if D.mark == nil then return end
    for _, r in pairs(data.characters) do
        if r.knownMissions then r.knownMissions[D.mark] = nil end
    end
    D.mark = nil
    save(Server)
end

local function boundTo(Server, id)
    for p, cid in pairs(Server.bound) do
        if cid == id then return userOf(p) or "?" end
    end
    return nil
end

-- A zombie carrying the requester's identity in its ModData dies through the notebook handler: nothing retired.
local function zombieRetiresNothing(t, Server, data, p, requesterId)
    if type(addZombiesInOutfit) ~= "function" or type(Server.characterDeath) ~= "function" then
        t:ok(false, "addZombiesInOutfit or RS_CarnetServer.characterDeath missing")
    end
    -- Created and removed in the same call: never sent to the clients.
    local list = addZombiesInOutfit(math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), 1, nil, 0)
    local z = list and list:size() > 0 and list:get(0) or nil
    t:ok(z ~= nil, "no zombie created on the requester's square")
    z:getModData()[D.KEY] = requesterId
    local ok, err = pcall(Server.characterDeath, z)
    z:getModData()[D.KEY] = nil
    pcall(function() z:removeFromWorld() end)
    pcall(function() z:removeFromSquare() end)
    t:ok(ok, "notebook death handler raised on a zombie: " .. tostring(err))
    local r = data.characters[requesterId]
    t:ok(r ~= nil and not r.retired, "a zombie carrying the requester's identity retired it")
end

D.MISSION_TAG = "rs.death"

-- Shared mission (E00-T02) removed: kept from the death to the new character check.
function D.removeShared(Server)
    if D.shared ~= nil then RST.Fixtures.removeTestMission(Server.store, D.shared) end
    D.shared = nil
end

-- A test NPC of Living Knox near the requester (removed after the test), its notebook fiche and an ACTIVE mission
-- it requests with every character of members engaged (D.shared, kept for the next test); then after(t).
local function sharedMission(t, Server, requester, members, after)
    local ready, why = RST.Fixtures.npcReady()
    t:ok(ready, "no test NPC for the shared mission (E00-T02): " .. tostring(why))
    RST.Fixtures.spawnNpc(t, requester, function(t2, id)
        local npc = Server.ensure(id)
        t2:ok(npc ~= nil, "no notebook fiche for the test npc " .. tostring(id))
        D.removeShared(Server)
        D.shared = RST.Fixtures.engagedMission(t2, Server.store, npc, members, { tag = D.MISSION_TAG, keep = true })
        return after(t2)
    end)
end

-- The death of a participant closes nothing: the shared mission is still active with the other participant engaged.
local function sharedGoesOn(t, data, requesterId, when)
    local m = D.shared
    t:ok(m ~= nil, "no shared mission (E00-T02)")
    t:ok(data.missions[m.id] == m, "shared mission " .. m.id .. " gone " .. when)
    t:eq("active", m.state, "state of the shared mission " .. m.id .. " " .. when)
    t:ok(m.participants[requesterId] ~= nil, "the requester is no longer engaged in " .. m.id .. " " .. when)
    t:note("shared mission " .. m.id .. " " .. when .. ": " .. m.state .. ", " .. string.format("%.0f", m.remainingMs)
        .. " ms left")
end

RST.suite("rs.death", { tags = { "server", "world" }, testTimeoutMs = 180000, timeoutMs = 420000 }, function(s)
    s.test("client 2 dies on the server: OnCharacterDeath, identity retired, last-pages paper in its corpse seen "
        .. "by the requester (E00-T02, E15-T02)", function(t)
        D.died, D.skipped = false, nil
        local Server, data = authority(t)
        local others = Steps.others(t)
        if #others == 0 then
            D.skipped = "no second client online: run with autoclient.py --mp --clients 2"
            t:skip(D.skipped)
        end
        local requester = t.ctx and t.ctx.player
        t:ok(requester ~= nil, "no target player (t.ctx.player)")
        local me = userOf(requester)
        local user = others[1]
        local victim = PD.alivePlayerOf(user)
        t:ok(victim ~= nil, "client " .. user .. " has no living character on the server")
        D.user, D.victim = user, victim
        t:waitUntil(function() return type(Server.bound[victim]) == "string" and type(Server.bound[requester]) == "string"
        end, D.BOUND_MS, function(t0)
            D.old, D.requesterId = Server.bound[victim], Server.bound[requester]
            local record = data.characters[D.old]
            t0:ok(record ~= nil and not record.retired, "identity " .. tostring(D.old) .. " of " .. user
                .. " not usable before the death")
            zombieRetiresNothing(t0, Server, data, requester, D.requesterId)
            -- E00-T02: a mission of a real Living Knox NPC where B and the requester are engaged goes on for the
            -- requester after B's death.
            sharedMission(t0, Server, requester, { [D.requesterId] = me, [D.old] = user }, function(t1)
                local token = "d" .. tostring(math.floor(RST.now()))
                D.token = token
                D.mark = "rst-death-" .. token
                record.knownMissions = record.knownMissions or {}
                record.knownMissions[D.mark] = true
                D.engaged = missionsOf(data, D.old)
                -- Kept until the new character is checked (next test); removed now if client 2 did not die.
                t1:defer(function() if not D.died then D.removeMark(Server, data) end end, "marked known mission removed")
                t1:defer(function() if not D.died then D.removeShared(Server) end end, "shared mission removed")
                PD.arm(user, token)
                t1:defer(function() PD.disarm(user) end, "death witness disarmed")
                t1:defer(function()
                    local seen = PD.seen[token]
                    local body = seen and PD.corpseWith(seen.x, seen.y, seen.z, D.RADIUS, token) or nil
                    if body ~= nil and body:getSquare() ~= nil then body:getSquare():removeCorpse(body, false) end
                end, "corpse of client " .. user .. " removed")
                Steps.ask(t1, "death.prepare", {}, { target = { user }, timeoutMs = D.GOD_MS }, function(t2, res)
                    local e = res.by[user]
                    D.godmode = e and e.data and e.data.godmode == true or false
                    t2:waitUntil(function() return not victim:isGodMod() end, D.GOD_MS, function(t3)
                        log("killing " .. user .. " (" .. D.old .. ") at " .. math.floor(victim:getX()) .. ","
                            .. math.floor(victim:getY()) .. "," .. math.floor(victim:getZ()))
                        local ok, err = pcall(function() victim:die() end)
                        t3:ok(ok, "player:die() raised on the server: " .. tostring(err))
                        t3:waitUntil(function()
                            local seen = PD.seen[token]
                            return seen ~= nil and PD.corpseWith(seen.x, seen.y, seen.z, D.RADIUS, token) ~= nil
                        end, D.DEATH_MS, function(t4)
                            D.died = true
                            local seen = PD.seen[token]
                            local body = PD.corpseWith(seen.x, seen.y, seen.z, D.RADIUS, token)
                            t4:ok(seen.inventory and seen.added, "witness paper not added to the inventory at OnCharacterDeath")
                            t4:ok(body:isPlayer(), "the corpse holding the paper is not a player corpse")
                            local r = data.characters[D.old]
                            t4:ok(r ~= nil and r.retired == true, "old identity " .. D.old .. " not retired")
                            t4:eq(nil, Server.bound[victim], "old IsoPlayer still bound")
                            t4:eq(nil, victim:getModData()[D.KEY], "old identity still in the server ModData of the dead")
                            t4:eq(nil, boundTo(Server, D.old), "old identity bound to a player")
                            local rr = data.characters[D.requesterId]
                            sharedGoesOn(t4, data, D.requesterId, "after the death of " .. user)
                            t4:ok(rr ~= nil and not rr.retired and Server.bound[requester] == D.requesterId,
                                "the requester's identity changed with another account's death")
                            t4:note("corpse of " .. user .. " at " .. seen.x .. "," .. seen.y .. "," .. seen.z .. ": "
                                .. body:getContainer():getItems():size() .. " item(s), on fire " .. tostring(seen.onFire)
                                .. ", identity bound at OnCharacterDeath " .. tostring(seen.boundAtEvent))
                            Steps.ask(t4, "carnet.claim", { character = D.old }, { target = "requester", timeoutMs = 8000 },
                                function(t5, res5)
                                    local a = res5.by[me]
                                    local got = a and a.data and a.data.character or nil
                                    t5:eq(D.requesterId, got, "identity answered to the requester claiming " .. D.old)
                                    Steps.ask(t5, "death.corpse", { x = seen.x, y = seen.y, z = seen.z, radius = D.RADIUS,
                                        token = token }, { target = "requester", timeoutMs = D.DEATH_MS })
                                end)
                        end, function()
                            return "no corpse of " .. user .. " holding the witness paper (OnCharacterDeath seen: "
                                .. tostring(PD.seen[token] ~= nil) .. ")"
                        end)
                    end, "client " .. user .. " still in god mode on the server")
                end)
            end)
        end, "no notebook identity bound to " .. user .. " and the requester (hello not received)")
    end)

    s.test("the dead client starts a new character: new identity, old missions not resumed, old identity never "
        .. "claimed again (E00-T02, E03-T04)", function(t)
        local Server, data = authority(t)
        if D.skipped then t:skip(D.skipped) end
        t:defer(function() D.removeMark(Server, data) end, "marked known mission removed")
        t:defer(function() D.removeShared(Server) end, "shared mission removed")
        t:ok(D.died == true, "client 2 did not die in the previous test")
        local user, oldPlayer = D.user, D.victim
        local newPlayer
        t:waitUntil(function()
            newPlayer = PD.alivePlayerOf(user, oldPlayer)
            return newPlayer ~= nil and type(Server.bound[newPlayer]) == "string"
        end, D.RESPAWN_MS, function(t1)
            local newId = Server.bound[newPlayer]
            local r = data.characters[newId]
            t1:ne(D.old, newId, "the new character got the old identity back")
            t1:ok(r ~= nil, "no record for the new identity " .. tostring(newId))
            t1:eq(user, r.owner, "owner of the new identity")
            t1:ok(not r.retired, "new identity already retired")
            t1:eq(newId, newPlayer:getModData()[D.KEY], "server ModData of the new character")
            t1:ok(data.characters[D.old] and data.characters[D.old].retired, "old identity no longer retired")
            sharedGoesOn(t1, data, D.requesterId, "after the new character of " .. user)
            t1:eq(nil, boundTo(Server, D.old), "old identity bound to a player")
            t1:ok(not (r.knownMissions and D.mark and r.knownMissions[D.mark]),
                "the new character knows the old marked mission")
            for _, mid in ipairs(D.engaged or {}) do
                local m = data.missions[mid]
                t1:ok(not (m and ((m.participants and m.participants[newId]) or (m.invited and m.invited[newId]))),
                    "the new character resumed mission " .. mid)
            end
            -- The real hello handler, for the new character, claiming the old identity: a fresh one, never the old.
            local Config = require "RadioSurvivor/RS_Config"
            local md = newPlayer:getModData()
            Server.bound[newPlayer], md[D.KEY] = nil, nil
            local ok, err = pcall(Server.command, Config.MODULE, "hello", newPlayer,
                { v = Config.VERSION, character = D.old })
            local got = Server.bound[newPlayer]
            if got ~= nil and got ~= newId and got ~= D.old then data.characters[got] = nil end
            Server.bound[newPlayer], md[D.KEY] = newId, newId
            save(Server)
            pcall(Server.command, Config.MODULE, "hello", newPlayer, { v = Config.VERSION, character = newId })
            t1:ok(ok, "hello handler raised: " .. tostring(err))
            t1:ok(got ~= nil, "no identity given to the claim of the old one")
            t1:ne(D.old, got, "the dead character's identity was claimed again")
            t1:note(user .. ": " .. D.old .. " (dead) -> " .. newId .. "; claim of " .. D.old .. " answered "
                .. tostring(got) .. " (removed); " .. #(D.engaged or {}) .. " mission(s) of the old identity")
            Steps.ask(t1, "death.after", { old = D.old, godmode = D.godmode }, { target = { user },
                timeoutMs = 20000 }, function(t2, res)
                local a = res.by[user]
                t2:eq(newId, a and a.data and a.data.character, "notebook identity on the client of " .. user)
            end)
        end, "no living new character of " .. user .. " bound to an identity (post-death screen not passed? see "
            .. "the client status 'respawn' lines)")
    end)
end)
