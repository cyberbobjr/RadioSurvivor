--[[
RST_CarnetHelpers - helpers of the notebook suites of every test mod (RST.CarnetHelpers, E21-T11: moved from
RST_RSHelpers.lua of batman_RadioSurvivorTests): the notebook server, the character of a player, an npc of the NPC
provider with a notebook fiche, selection and speech by the notebook client, placement in a town, god mode, language.
Development mod only. Load with: require "RST/RST_CarnetHelpers". No side effect at load time (definitions only). The
helpers call RST.Fixtures (RST_Fixtures.lua) and the notebook client steps of RST_PeerChecks.lua: the suites that use
them require those files (loaded at call time, so the Living Knox helpers may require this file alone).

    local N = RST.CarnetHelpers
    N.solo(t)                        skip unless solo (the local player and the authority share the Lua state)
    N.notebook(t)                    CoreAI.notebookServer with its state loaded (skip otherwise)
    N.character(t, p)                notebook character bound to the player (asks "hello" directly when missing)
    N.npcWithFiche(t, p, dx, after)  test npc of the NPC provider near the player (N.talkSpot.square, else dx squares
                                     east; RST.Fixtures.spawnNpc), its notebook fiche, waited until the notebook maps
                                     its body; after(t, id, fiche, body). Cleanup: its pending requests dropped, the npc
                                     removed by the fixture.
    N.talkSpot                       { square = function(p, dx) -> square or nil, radius = squares }: free square in
                                     sight and hearing of the player, given by the test mod of the NPC provider
                                     (RST_LKHelpers.lua); nil: the npc stands dx squares east
    N.nearestTown(x, y)              { name, x, y } of the nearest vanilla town centre (knox-geography.md)
    N.place(t, p, test, after)       test(p) -> value or nil at the current position; if nil, the player is moved to
                                     the nearest town centre (back at the end), squares awaited, test asked again;
                                     after(t, value, moved) or skip when test still fails
    N.god(t, p)                      god mode and invisibility until the end of the test
    N.language()                     "FR" when the game is in French, else "EN" (test sentences only)
    N.select(t, c, after)            the requester client selects the npc c.id with the notebook (RST.Steps "carnet.send":
                                     the real 'select' command in MP, the same code in solo), then waits until the
                                     authority selected c.fiche for c.cid; after(t)
    N.talk(t, c, text, after)        the requester client says text with the notebook Say line (RST.Steps "carnet.talk",
                                     once its previous answer and the cooldown are over), then waits for the npc_talk
                                     request of the authority; after(t, req). No request within TALK_REQUEST_MS: FAIL
                                     with the last notebook refusal read on the client (RST.Steps "carnet.state")
    N.dropMission(S, m, cid[, donors])
                                     test mission m removed from the real notebook state S (its requester's link in
                                     S.data.npcs, or in donors, and the character's known missions), then saved
    N.at(o)                          "x,y" of a body or player
    N.sightOf(a, b)                  LosUtil.lineClear from a to b ("no square" when one has none)
]]

require "RST/RST"

RST.CarnetHelpers = RST.CarnetHelpers or {}
local N = RST.CarnetHelpers

N.MAPPED_MS = 10000
N.SETTLE_MS = 3000
-- Vanilla town centres (annotations of the world map, .claude/pz-knowledge/knox-geography.md).
N.TOWNS = {
    { name = "Muldraugh", x = 10754, y = 9926 }, { name = "West Point", x = 11654, y = 6864 },
    { name = "Riverside", x = 6450, y = 5430 }, { name = "Rosewood", x = 8159, y = 11661 },
    { name = "March Ridge", x = 10130, y = 12801 }, { name = "Louisville", x = 13077, y = 2238 },
    { name = "Brandenburg", x = 2056, y = 6070 }, { name = "Ekron", x = 634, y = 9746 },
    { name = "Echo Creek", x = 3589, y = 10952 }, { name = "Irvington", x = 2427, y = 14185 },
}

local function isServerSide() return type(isServer) == "function" and isServer() end
local function isClientSide() return type(isClient) == "function" and isClient() end

function N.solo(t)
    if isServerSide() or isClientSide() then t:skip("solo only (local player and authority in the same Lua state)") end
end

function N.notebook(t)
    local Server = CoreAI and CoreAI.notebookServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (CoreAI.notebookServer)")
    end
    return Server
end

function N.character(t, p)
    local Server = N.notebook(t)
    if Server.bound[p] == nil then
        local C = require "CoreAI/CA_NotebookConfig"
        Server.command(C.MODULE, "hello", p, {})
    end
    local cid = Server.bound[p]
    t:ok(type(cid) == "string", "no notebook character bound to the player")
    return cid
end

function N.at(o) return math.floor(o:getX()) .. "," .. math.floor(o:getY()) end

function N.sightOf(a, b)
    if a:getSquare() == nil or b:getSquare() == nil then return "no square" end
    return tostring(LosUtil.lineClear(getCell(), math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ()),
        math.floor(b:getX()), math.floor(b:getY()), math.floor(b:getZ()), false))
end

function N.npcWithFiche(t, p, dx, after)
    local Server = N.notebook(t)
    local ready, why = RST.Fixtures.npcReady()
    if not ready then t:skip("no Living Knox test npc: " .. tostring(why)) end
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()), math.floor(p:getZ())
    local dy = 0
    local finder = N.talkSpot -- registered by the test mod of the NPC provider, loaded with it
    local spot = finder.square(p, dx)
    if spot ~= nil then
        dx, dy = spot:getX() - math.floor(p:getX()), spot:getY() - math.floor(p:getY())
        x, y = spot:getX(), spot:getY()
    else
        t:note("no free square in sight of the player within " .. finder.radius .. ": npc " .. dx .. " squares east")
    end
    local saved, savedDy = RST.Fixtures.NPC_OFFSET, RST.Fixtures.NPC_DY
    RST.Fixtures.NPC_OFFSET, RST.Fixtures.NPC_DY = dx, dy
    local ok, err = pcall(function()
        RST.Fixtures.spawnNpc(t, p, function(t2, id, body)
            local fiche = Server.ensure(id)
            t2:ok(fiche ~= nil, "no notebook fiche for " .. tostring(id))
            t2:defer(function()
                local kept = {}
                for _, r in ipairs(Server.talk.pending) do if r.npc ~= fiche.id then kept[#kept + 1] = r end end
                Server.talk.pending = kept
            end, "drop the pending requests of " .. id)
            t2:waitQuiet(function() return Server.objects[fiche.id] ~= nil end, N.MAPPED_MS,
                function(t3) return after(t3, id, fiche, body) end,
                "body of " .. id .. " never mapped by the notebook (near " .. x .. "," .. y .. "," .. z .. ")")
        end)
    end)
    RST.Fixtures.NPC_OFFSET, RST.Fixtures.NPC_DY = saved, savedDy
    if not ok then error(err, 0) end
end

function N.nearestTown(x, y)
    local best, bestD
    for _, town in ipairs(N.TOWNS) do
        local d = (town.x - x) * (town.x - x) + (town.y - y) * (town.y - y)
        if bestD == nil or d < bestD then best, bestD = town, d end
    end
    return best
end

function N.place(t, p, test, after)
    local value = test(p)
    if value ~= nil then return after(t, value, false) end
    local town = N.nearestTown(p:getX(), p:getY())
    t:note("nothing fits around " .. math.floor(p:getX()) .. "," .. math.floor(p:getY()) .. ": moved to " .. town.name)
    RST.Fixtures.movePlayer(t, p, town.x + 0.5, town.y + 0.5, 0, function(t2)
        RST.Fixtures.waitSquare(t2, town.x, town.y, 0, nil, function(t3)
            t3:sleep(N.SETTLE_MS, function(t4)
                local again = test(p)
                if again == nil then t4:skip("nothing fits around the player nor in " .. town.name) end
                return after(t4, again, true)
            end)
        end)
    end)
end

function N.god(t, p)
    local wasGod = p:isGodMod()
    p:setGodMod(true)
    t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the player")
    if p.setInvisible ~= nil and p.isInvisible ~= nil then
        local wasInvisible = p:isInvisible()
        p:setInvisible(true)
        t:defer(function() p:setInvisible(wasInvisible) end, "restore the visibility of the player")
    end
end

N.TALK_REQUEST_MS = 10000
N.TALK_WAIT_MS = 120000

function N.select(t, c, after)
    RST.Steps.ask(t, "carnet.send", { command = "select", args = { incarnation = c.id } },
        { target = "requester", none = "skip", timeoutMs = 10000 }, function(t2)
            t2:waitUntil(function() return c.Server.selected[c.cid] == c.fiche.id end, 5000, after, function()
                -- Why the server refused (select needs Provider.near: same floor, SELECT_RANGE, CanSee).
                local body = c.Server.objects[c.fiche.id]
                if body == nil or c.p == nil then return "npc not selected by the notebook (body not mapped)" end
                local P = require "CoreAI/CA_NPCProvider"
                local C = require "CoreAI/CA_SpeechConfig"
                return "npc not selected by the notebook (body at " .. N.at(body) .. ", player at " .. N.at(c.p)
                    .. ", near " .. tostring(P.near(c.p, body, C.SELECT_RANGE)) .. ", sight " .. N.sightOf(c.p, body)
                    .. ")"
            end)
        end)
end

-- The pending list is watched from before the step is asked (OnTick): the talk command and the answer of the step
-- are two client commands, delivered unordered (MP campaign of 2026-11-05, lk.npctalk: the request was queued, sent
-- to the bridge and answered before the step answer reached the server; "no npc_talk request").
function N.watchRequest(t, c, text)
    local seen = {}
    local function watch()
        if seen.req ~= nil then return end
        for _, r in ipairs(c.Server.talk.pending) do
            if r.npc == c.fiche.id and r.kind == "npc_talk" and r.text == text and not seen.before[r.id] then
                seen.req = r
                return
            end
        end
    end
    seen.before = {}
    for _, r in ipairs(c.Server.talk.pending) do seen.before[r.id] = true end
    Events.OnTick.Add(watch)
    t:defer(function() Events.OnTick.Remove(watch) end, "stop watching the npc_talk requests")
    -- The request is saved right after it joins the pending list (CA_NotebookServer enqueue: S.save()): seen there
    -- even when the bridge answers before the next tick.
    local store = c.Server.store
    local save = store and store.save
    if type(save) == "function" then
        store.save = function(...)
            watch()
            return save(...)
        end
        t:defer(function() if store.save ~= save then store.save = save end end, "restore the notebook state save")
    end
    return seen, watch
end

function N.talk(t, c, text, after)
    local seen, watch = N.watchRequest(t, c, text)
    local Speech = require "CoreAI/CA_SpeechConfig"
    RST.Steps.ask(t, "carnet.talk", { text = text, cooldownMs = Speech.COOLDOWN_MS + 500 },
        { target = "requester", none = "skip", timeoutMs = N.TALK_WAIT_MS }, function(t1)
            local deadline = RST.now() + N.TALK_REQUEST_MS
            t1:waitQuiet(function()
                watch()
                if seen.req ~= nil then return seen.req end
                if RST.now() >= deadline then return { missing = true } end
                return nil
            end, nil, function(t2, req)
                if not req.missing then return after(t2, req) end
                RST.Steps.ask(t2, "carnet.state", {}, { target = "requester", timeoutMs = 5000 }, function(t3, res)
                    local e = res.list[1]
                    local why = e and e.data and e.data.lastError or nil
                    t3:ok(false, "no npc_talk request for '" .. text .. "'"
                        .. (why and (" (notebook refusal " .. why .. ")") or ""))
                end)
            end)
        end)
end

-- Removes a test mission from the real notebook state (and its requester's link: an npc of the notebook, else an entry
-- of donors, the donor records of another mod).
function N.dropMission(S, m, cid, donors)
    if not (S.data and m) then return end
    S.data.missions[m.id] = nil
    local donor = S.data.npcs[m.npc] or (donors and donors[m.npc])
    if donor and donor.mission == m.id then donor.mission = nil end
    local record = S.data.characters[cid]
    if record and type(record.knownMissions) == "table" then record.knownMissions[m.id] = nil end
    S.save()
end

function N.language()
    local lang = Translator and Translator.getLanguage and Translator.getLanguage()
    if lang ~= nil and tostring(lang:name()) == "FR" then return "FR" end
    return "EN"
end

return N
