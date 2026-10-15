--[[
RST_RSHelpers - helpers of the RadioSurvivor solo suites of the development mod (RST.RSHelpers): placement in a town,
Living Knox npc with a notebook fiche, radio held in hand and lines heard, god mode, files. Development mod only.
Load with: require "RST/RST_RSHelpers". No side effect at load time (definitions only).

    local R = RST.RSHelpers
    R.solo(t)                        skip unless solo (the local player and the authority share the Lua state)
    R.notebook(t)                    RS_CarnetServer with its state loaded (skip otherwise)
    R.character(t, p)                notebook character bound to the player (asks "hello" directly when missing)
    R.npcWithFiche(t, p, dx, after)  Living Knox test npc dx squares east of the player (RST.Fixtures.spawnNpc), its
                                     notebook fiche, waited until the notebook maps its body; after(t, id, fiche, body).
                                     Cleanup: its pending requests dropped, the npc removed by the fixture.
    R.nearestTown(x, y)              { name, x, y } of the nearest vanilla town centre (knox-geography.md)
    R.place(t, p, test, after)       test(p) -> value or nil at the current position; if nil, the player is moved to
                                     the nearest town centre (back at the end), squares awaited, test asked again;
                                     after(t, value, moved) or skip when test still fails
    R.heardSquares(p, r)             E08-T11: free squares (LivingKnox.Bodies.freeSquare) at most r (SPOT_RADIUS)
                                     squares from the player, never next to it, where the player hears a body
                                     (Provider.hears), nearest first
    R.pairSquares(p, range, max, r)  up to max (SPOT_PAIRS) pairs { a, b }: a heard square, b free, 2 to range squares
                                     from a, each in sight of the other (LosUtil.lineClear both ways), nearest a first
    R.at(o) R.sightOf(a, b)          "x,y" of an object; LosUtil.lineClear of two bodies ("no square" when unplaced)
    R.radioInHand(t, p, fullType, khz)
                                     radio given (RST.Fixtures.giveItem) and held in the main hand, battery full, on,
                                     microphone open, tuned to khz; the former main hand item is held again at the end
    R.hear(t)                        list of lines heard by any device (OnDeviceText), { khz, text, at }; listener
                                     removed at the end
    R.god(t, p)                      god mode and invisibility until the end of the test
    R.readLines(path) R.writeLines(t, path, lines)
                                     Zomboid/Lua files (getFileReader / getFileWriter)
    R.language()                     "FR" when the game is in French, else "EN" (test sentences only)
    R.select(t, c, after)            the requester client selects the npc c.id with the notebook (RST.Steps "carnet.send":
                                     the real 'select' command in MP, the same code in solo), then waits until the
                                     authority selected c.fiche for c.cid; after(t)
    R.talk(t, c, text, after)        the requester client says text with the notebook Say line (RST.Steps "carnet.talk",
                                     once its previous answer and the cooldown are over), then waits for the npc_talk
                                     request of the authority; after(t, req). No request within TALK_REQUEST_MS: FAIL
                                     with the last notebook refusal read on the client (RST.Steps "carnet.state")
    R.label(khz)                     "145.0"
    R.bridgeCause(Server, since)     E17-T15: failure message of a wait for a bridge answer: the latest request refused
                                     by the notebook server since `since` (getTimestampMs) with its cause (bridge error
                                     `timeout`, `http_503`..., no reply), else "no request refused: is the bridge
                                     program running?". Pass it as a function: function() return R.bridgeCause(...) end
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_PeerChecks"

RST.RSHelpers = RST.RSHelpers or {}
local R = RST.RSHelpers

R.MAPPED_MS = 10000
R.SETTLE_MS = 3000
-- Vanilla town centres (annotations of the world map, .claude/pz-knowledge/knox-geography.md).
R.TOWNS = {
    { name = "Muldraugh", x = 10754, y = 9926 }, { name = "West Point", x = 11654, y = 6864 },
    { name = "Riverside", x = 6450, y = 5430 }, { name = "Rosewood", x = 8159, y = 11661 },
    { name = "March Ridge", x = 10130, y = 12801 }, { name = "Louisville", x = 13077, y = 2238 },
    { name = "Brandenburg", x = 2056, y = 6070 }, { name = "Ekron", x = 634, y = 9746 },
    { name = "Echo Creek", x = 3589, y = 10952 }, { name = "Irvington", x = 2427, y = 14185 },
}

local function isServerSide() return type(isServer) == "function" and isServer() end
local function isClientSide() return type(isClient) == "function" and isClient() end

function R.solo(t)
    if isServerSide() or isClientSide() then t:skip("solo only (local player and authority in the same Lua state)") end
end

function R.notebook(t)
    local Server = RS_CarnetServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (RS_CarnetServer)")
    end
    return Server
end

function R.character(t, p)
    local Server = R.notebook(t)
    if Server.bound[p] == nil then
        local C = require "RadioSurvivor/RS_Config"
        Server.command(C.MODULE, "hello", p, {})
    end
    local cid = Server.bound[p]
    t:ok(type(cid) == "string", "no notebook character bound to the player")
    return cid
end

function R.npcWithFiche(t, p, dx, after)
    local Server = R.notebook(t)
    local ready, why = RST.Fixtures.npcReady()
    if not ready then t:skip("no Living Knox test npc: " .. tostring(why)) end
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()), math.floor(p:getZ())
    local saved = RST.Fixtures.NPC_OFFSET
    RST.Fixtures.NPC_OFFSET = dx
    local ok, err = pcall(function()
        RST.Fixtures.spawnNpc(t, p, function(t2, id, body)
            local fiche = Server.ensure(id)
            t2:ok(fiche ~= nil, "no notebook fiche for " .. tostring(id))
            t2:defer(function()
                local kept = {}
                for _, r in ipairs(Server.pending) do if r.npc ~= fiche.id then kept[#kept + 1] = r end end
                Server.pending = kept
            end, "drop the pending requests of " .. id)
            t2:waitQuiet(function() return Server.objects[fiche.id] ~= nil end, R.MAPPED_MS,
                function(t3) return after(t3, id, fiche, body) end,
                "body of " .. id .. " never mapped by the notebook (near " .. x .. "," .. y .. "," .. z .. ")")
        end)
    end)
    RST.Fixtures.NPC_OFFSET = saved
    if not ok then error(err, 0) end
end

function R.nearestTown(x, y)
    local best, bestD
    for _, town in ipairs(R.TOWNS) do
        local d = (town.x - x) * (town.x - x) + (town.y - y) * (town.y - y)
        if bestD == nil or d < bestD then best, bestD = town, d end
    end
    return best
end

function R.place(t, p, test, after)
    local value = test(p)
    if value ~= nil then return after(t, value, false) end
    local town = R.nearestTown(p:getX(), p:getY())
    t:note("nothing fits around " .. math.floor(p:getX()) .. "," .. math.floor(p:getY()) .. ": moved to " .. town.name)
    RST.Fixtures.movePlayer(t, p, town.x + 0.5, town.y + 0.5, 0, function(t2)
        RST.Fixtures.waitSquare(t2, town.x, town.y, 0, nil, function(t3)
            t3:sleep(R.SETTLE_MS, function(t4)
                local again = test(p)
                if again == nil then t4:skip("nothing fits around the player nor in " .. town.name) end
                return after(t4, again, true)
            end)
        end)
    end)
end

-- E08-T11: bounded search of npc spots around the player (no fixed offsets: the start house of the MP test server put
-- them behind walls or out of earshot). Same rules as the mod: a body stands on a LivingKnox.Bodies.freeSquare, the
-- player hears it by Provider.hears (C.HEARING_RANGE), two bodies see each other by Provider.near (CanSee =
-- LosUtil.lineClear not Blocked; not symmetric, so both ways are required).
R.SPOT_RADIUS = 6
R.SPOT_PAIRS = 4

-- Stand-in of a body on sq for Provider.hears (reads getSquare, getX, getY, getZ only).
local function standIn(sq)
    return {
        getSquare = function() return sq end,
        getX = function() return sq:getX() + 0.5 end,
        getY = function() return sq:getY() + 0.5 end,
        getZ = function() return sq:getZ() end,
    }
end

local function blocked(a, b)
    return tostring(LosUtil.lineClear(getCell(), a:getX(), a:getY(), a:getZ(), b:getX(), b:getY(), b:getZ(), false))
        == "Blocked"
end

-- Squares (same level, at most r squares away, never next to the player) where a new body may stand and be heard by
-- the player p, nearest first.
function R.heardSquares(p, r)
    local P = require "RadioSurvivor/RS_NPCProvider"
    local C = require "RadioSurvivor/RS_Config"
    local Bodies = LivingKnox and LivingKnox.Bodies
    local cell = getCell()
    local out = {}
    if Bodies == nil or cell == nil then return out end
    r = r or R.SPOT_RADIUS
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for dy = -r, r do
        for dx = -r, r do
            if math.max(math.abs(dx), math.abs(dy)) >= 2 then
                local sq = cell:getGridSquare(px + dx, py + dy, pz)
                if sq ~= nil and Bodies.freeSquare(sq) and P.hears(standIn(sq), p, C.HEARING_RANGE) then
                    out[#out + 1] = { sq = sq, d = dx * dx + dy * dy, dx = dx, dy = dy }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        if a.dy ~= b.dy then return a.dy < b.dy end
        return a.dx < b.dx
    end)
    local squares = {}
    for i, e in ipairs(out) do squares[i] = e.sq end
    return squares
end

-- Up to max pairs { a, b } of squares: a heard by the player (R.heardSquares), b free, 2 to range squares from a
-- (never next to it: Bodies.clearAround would move the second body), each in sight of the other; one pair per a,
-- nearest a first. Bounded: (2r + 1)^2 squares a, (2 range + 1)^2 squares b each.
function R.pairSquares(p, range, max, r)
    local Bodies = LivingKnox and LivingKnox.Bodies
    local cell = getCell()
    local out = {}
    if Bodies == nil or cell == nil then return out end
    max = max or R.SPOT_PAIRS
    local reach = math.floor(range)
    for _, a in ipairs(R.heardSquares(p, r)) do
        local best, bestD
        for dy = -reach, reach do
            for dx = -reach, reach do
                local d = dx * dx + dy * dy
                if math.max(math.abs(dx), math.abs(dy)) >= 2 and d <= range * range and (bestD == nil or d < bestD) then
                    local b = cell:getGridSquare(a:getX() + dx, a:getY() + dy, a:getZ())
                    if b ~= nil and Bodies.freeSquare(b) and not blocked(a, b) and not blocked(b, a) then
                        best, bestD = b, d
                    end
                end
            end
        end
        if best ~= nil then
            out[#out + 1] = { a = a, b = best }
            if #out >= max then break end
        end
    end
    return out
end

-- "x,y" of a square or a body, and why two bodies (or a body and the player) fail the rules above, for the reports.
function R.at(o) return math.floor(o:getX()) .. "," .. math.floor(o:getY()) end
function R.sightOf(a, b)
    if a:getSquare() == nil or b:getSquare() == nil then return "no square" end
    return tostring(LosUtil.lineClear(getCell(), math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ()),
        math.floor(b:getX()), math.floor(b:getY()), math.floor(b:getZ()), false))
end

function R.radioInHand(t, p, fullType, khz)
    local item = RST.Fixtures.giveItem(t, p, fullType)[1]
    local previous = p:getPrimaryHandItem()
    p:setPrimaryHandItem(item)
    t:defer(function()
        if p:getPrimaryHandItem() == item then p:setPrimaryHandItem(previous) end
    end, "hold the former main hand item again")
    local data = item:getDeviceData()
    t:ok(data ~= nil, fullType .. " has no DeviceData")
    t:ok(khz >= data:getMinChannelRange() and khz <= data:getMaxChannelRange(),
        fullType .. " cannot tune " .. R.label(khz) .. " MHz")
    data:setHasBattery(true)
    data:setPower(1.0)
    data:setTurnedOnRaw(true)
    data:setChannel(khz)
    data:setMicIsMuted(false)
    p:updateEquippedRadioFreq()
    return item, data
end

function R.hear(t)
    local heard = {}
    local function listener(_guid, _codes, _x, _y, _z, line, device)
        if type(line) ~= "string" then
            if line ~= nil and instanceof(line, "ChatMessage") then line = line:getText() else return end
        end
        local khz = nil
        local ok, data = pcall(function() return device:getDeviceData() end)
        if ok and data ~= nil then khz = data:getChannel() end
        heard[#heard + 1] = { khz = khz, text = line, at = getTimestampMs() }
    end
    Events.OnDeviceText.Add(listener)
    t:defer(function() Events.OnDeviceText.Remove(listener) end, "remove the OnDeviceText listener")
    return heard
end

-- Lines of heard on khz since the given time, words only (static "<fzzt>" lines left out).
function R.words(heard, khz, since)
    local out = {}
    for _, h in ipairs(heard) do
        if h.khz == khz and h.at >= (since or 0) and not string.match(h.text, "^%s*<%a+>%s*$") then
            out[#out + 1] = h.text
        end
    end
    return out
end

function R.god(t, p)
    local wasGod = p:isGodMod()
    p:setGodMod(true)
    t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the player")
    if p.setInvisible ~= nil and p.isInvisible ~= nil then
        local wasInvisible = p:isInvisible()
        p:setInvisible(true)
        t:defer(function() p:setInvisible(wasInvisible) end, "restore the visibility of the player")
    end
end

function R.readLines(path)
    local reader = getFileReader(path, false)
    if not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

function R.writeLines(t, path, lines)
    local writer = getFileWriter(path, true, false)
    t:ok(writer ~= nil, "cannot write Zomboid/Lua/" .. path)
    for _, line in ipairs(lines) do writer:write(line .. "\n") end
    writer:close()
end

R.TALK_REQUEST_MS = 10000
R.TALK_WAIT_MS = 120000

function R.select(t, c, after)
    RST.Steps.ask(t, "carnet.send", { command = "select", args = { incarnation = c.id } },
        { target = "requester", none = "skip", timeoutMs = 10000 }, function(t2)
            t2:waitUntil(function() return c.Server.selected[c.cid] == c.fiche.id end, 5000, after, function()
                -- Why the server refused (select needs Provider.near: same floor, SELECT_RANGE, CanSee).
                local body = c.Server.objects[c.fiche.id]
                if body == nil or c.p == nil then return "npc not selected by the notebook (body not mapped)" end
                local P = require "RadioSurvivor/RS_NPCProvider"
                local C = require "RadioSurvivor/RS_Config"
                return "npc not selected by the notebook (body at " .. R.at(body) .. ", player at " .. R.at(c.p)
                    .. ", near " .. tostring(P.near(c.p, body, C.SELECT_RANGE)) .. ", sight " .. R.sightOf(c.p, body)
                    .. ")"
            end)
        end)
end

function R.talk(t, c, text, after)
    RST.Steps.ask(t, "carnet.talk", { text = text, cooldownMs = c.C.COOLDOWN_MS + 500 },
        { target = "requester", none = "skip", timeoutMs = R.TALK_WAIT_MS }, function(t1)
            local deadline = RST.now() + R.TALK_REQUEST_MS
            t1:waitQuiet(function()
                for _, r in ipairs(c.Server.pending) do
                    if r.npc == c.fiche.id and r.kind == "npc_talk" and r.text == text then return r end
                end
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

function R.language()
    local lang = Translator and Translator.getLanguage and Translator.getLanguage()
    if lang ~= nil and tostring(lang:name()) == "FR" then return "FR" end
    return "EN"
end

function R.bridgeCause(Server, since)
    local refusals = Server and Server.refusals or {}
    for i = #refusals, 1, -1 do
        local r = refusals[i]
        if (r.at or 0) >= (since or 0) then
            return "request " .. tostring(r.kind) .. " " .. tostring(r.id) .. " refused by the server: " .. tostring(r.reason)
        end
    end
    return "no request refused by the server meanwhile: is the bridge program running?"
end

function R.label(khz)
    return string.format("%.1f", khz / 1000)
end

return R
