--[[
rs.lastpages.corpse - where the "last pages" document of a dead character can go (E15-T02, investigation; written
conclusion: docs/derniers-pages-cadavre.md). Tags "world" and "server": the authority only (solo or server), on a
save named rstest*, with a target player (t.ctx.player).

Method retained (Java 42.21.0): on the authority, OnCharacterDeath fires BEFORE the corpse exists, while the dead
player still holds his inventory; the corpse then takes that very container (IsoDeadBody constructor) and the
PlayerDeath packet carries it to every client in range. An item added to player:getInventory() in OnCharacterDeath
therefore ends in the corpse for everyone, with no other network call. Once the corpse exists, an item is added to
body:getContainer() then sent by sendAddItemToContainer (server). Fallback: on the ground next to the corpse
(square:AddWorldInventoryItem(item, x, y, z, true)), e.g. when the dying player is on fire (the corpse burns).

Automated suite (the target player is not killed here; the REAL death of a second client, with the same witness
paper added at OnCharacterDeath and found in its corpse by the server and by the requester's client, is the suite
rs.death, RS_Death.lua, MP campaign with two clients):
    corpse      a corpse made by RandomizedWorldBase.createRandomDeadBody next to the player (gap: a zombie corpse,
                isPlayer() false, created already; it proves the "corpse exists" path, not the death-time path),
                a marked Base.SheetPaper2 added to its container + sendAddItemToContainer: found in the container;
    ground      fallback: the marked paper laid on the ground next to the corpse (transmitted);
    listener    the Java pieces of the death-time path exist here (Events.OnCharacterDeath, instanceItem).
    Solo: RST.run({ suite = "rs.lastpages.corpse", tags = "world" }); dedicated server, from an admin client:
    RST.server({ suite = "rs.lastpages.corpse", tags = "world" }).

Manual protocol on a real death (opt-in suites, tag "manual", named exactly):
    1. RST.server({ suite = "rs.lastpages.corpse.arm", tags = "manual" })   (solo: RST.run with the same filter)
       arms a one-shot OnCharacterDeath witness for the target player on the authority;
    2. the target player dies (zombies, fall, /godmod off and damage...), not on fire;
    3. a client opens the corpse: a "RST corpse witness <token>" sheet of paper is in it; a second client sees it
       too; reconnect and look again (saved with the corpse);
    4. after respawn, RST.server({ suite = "rs.lastpages.corpse.check", tags = "manual" }) finds the corpse at the
       recorded square with the marked paper inside (server copy).
    Server console lines: "[RST] lastpages ...".
]]

require "RST/RST"
require "RST/RST_Fixtures"

local MARK = "rsLastPagesWitness"
local PAPER = "Base.SheetPaper2"
local RADIUS = 2

-- Shared across reloads of this file: armed tokens by user name, deaths seen by token.
RST_LastPagesCorpse = RST_LastPagesCorpse or { armed = {}, seen = {}, seq = 0, listening = false }
local W = RST_LastPagesCorpse

local function log(msg) print("[RST] lastpages " .. msg) end

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("authority only (solo or server), not an MP client")
    end
end

local function target(t)
    local p = RST.Fixtures.player(t)
    if p == nil then t:skip("no target player (t.ctx.player)") end
    return p
end

local function userOf(p)
    local ok, name = pcall(function() return p:getUsername() end)
    return tostring(ok and name or "?")
end

local function newWitness(token)
    local item = instanceItem(PAPER)
    item:setName("RST corpse witness " .. token)
    item:setCustomName(true)
    item:getModData()[MARK] = token
    return item
end

local function isWitness(item, token)
    return item ~= nil and item:hasModData() and item:getModData()[MARK] == token
end

-- Marked item in a container (first level), or nil.
local function witnessIn(container, token)
    if container == nil then return nil end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if isWitness(it, token) then return it end
    end
    return nil
end

-- Corpses around (x, y, z), as a list.
local function corpsesNear(x, y, z, radius)
    local out = {}
    for dy = -radius, radius do
        for dx = -radius, radius do
            local sq = getCell():getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            if list ~= nil then
                for i = 0, list:size() - 1 do
                    local o = list:get(i)
                    if instanceof(o, "IsoDeadBody") then out[#out + 1] = o end
                end
            end
        end
    end
    return out
end

local function newToken()
    W.seq = W.seq + 1
    return "w" .. tostring(W.seq) .. "-" .. tostring(math.floor(getTimestampMs() / 1000))
end

-- Death-time witness: runs on the authority inside OnCharacterDeath, before becomeCorpse.
function W.handle(chr)
    if not instanceof(chr, "IsoPlayer") then return end
    local user = userOf(chr)
    local token = W.armed[user]
    if token == nil then return end
    W.armed[user] = nil
    local inv = chr:getInventory()
    local seen = { user = user, x = math.floor(chr:getX()), y = math.floor(chr:getY()), z = math.floor(chr:getZ()),
        onFire = chr:isOnFire() and true or false, inventory = inv ~= nil,
        corpsesBefore = #corpsesNear(math.floor(chr:getX()), math.floor(chr:getY()), math.floor(chr:getZ()), 0) }
    if inv ~= nil then
        local item = newWitness(token)
        inv:AddItem(item)
        seen.added = inv:contains(item)
    end
    W.seen[token] = seen
    log("witness " .. token .. " for " .. user .. " at " .. seen.x .. "," .. seen.y .. "," .. seen.z
        .. ": inventory " .. tostring(seen.inventory) .. ", added " .. tostring(seen.added)
        .. ", on fire " .. tostring(seen.onFire) .. ", corpses already on the square " .. seen.corpsesBefore)
end

local function listen()
    if W.listening then return end
    W.listening = true
    Events.OnCharacterDeath.Add(function(chr) RST_LastPagesCorpse.handle(chr) end)
end

-- New corpse 2 squares east of the player, removed at the end of the test.
local function makeCorpse(t, p)
    local x, y, z = math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ())
    local sq = getCell():getGridSquare(x, y, z)
    t:ok(sq ~= nil, "square " .. x .. "," .. y .. "," .. z .. " not loaded")
    local body = RandomizedWorldBase.createRandomDeadBody(sq, IsoDirections.S, 0, 0, nil)
    t:ok(body ~= nil, "createRandomDeadBody returned nil")
    body:setFakeDead(false)
    t:defer(function()
        local s = body:getSquare()
        if s ~= nil then s:removeCorpse(body, false) end
    end, "remove the test corpse")
    return body, sq
end

RST.suite("rs.lastpages.corpse", { tags = { "world", "server" } }, function(s)
    s.test("corpse container: marked paper added and sent", function(t)
        authority(t)
        local p = target(t)
        local body = makeCorpse(t, p)
        local container = body:getContainer()
        t:ok(container ~= nil, "corpse without container")
        t:ok(container:getParent() == body, "container parent is not the corpse")
        local token = newToken()
        local item = newWitness(token)
        container:AddItem(item)
        if type(isServer) == "function" and isServer() then sendAddItemToContainer(container, item) end
        t:defer(function()
            container:Remove(item)
            if type(isServer) == "function" and isServer() then sendRemoveItemFromContainer(container, item) end
        end, "take the paper back")
        t:ok(witnessIn(container, token) == item, "marked paper not in the corpse container")
        t:ok(item:getContainer() == container, "item container is not the corpse container")
        t:note("corpse at " .. math.floor(body:getX()) .. "," .. math.floor(body:getY()) .. " isPlayer "
            .. tostring(body:isPlayer()) .. " (gap: a zombie corpse, not a player death), "
            .. container:getItems():size() .. " item(s), token " .. token)
    end)

    s.test("fallback: marked paper on the ground next to the corpse", function(t)
        authority(t)
        local p = target(t)
        local _, sq = makeCorpse(t, p)
        local token = newToken()
        local item = newWitness(token)
        sq:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
        local wo = item:getWorldItem()
        t:defer(function()
            local w = item:getWorldItem()
            if w ~= nil and w:getSquare() ~= nil then w:getSquare():transmitRemoveItemFromSquare(w) end
        end, "remove the paper from the ground")
        t:ok(wo ~= nil, "no world item for the paper")
        t:ok(wo:getSquare() == sq, "paper not on the corpse square")
        t:ok(isWitness(wo:getItem(), token), "world item lost its mark")
    end)

    s.test("death-time path: Java pieces present", function(t)
        authority(t)
        t:ok(Events ~= nil and Events.OnCharacterDeath ~= nil, "Events.OnCharacterDeath missing")
        t:eq("function", type(instanceItem), "instanceItem")
        local item = newWitness("probe")
        t:eq(PAPER, item:getFullType())
        t:ok(isWitness(item, "probe"), "mark not kept in the item ModData")
    end)
end)

RST.suite("rs.lastpages.corpse.arm", { tags = { "world", "server", "manual" } }, function(s)
    s.test("arm the death witness of the target player", function(t)
        authority(t)
        local p = target(t)
        listen()
        local token = newToken()
        local user = userOf(p)
        W.armed[user] = token
        W.last = token
        t:ok(W.listening, "listener not registered")
        log("armed " .. token .. " for " .. user)
        t:note("armed " .. token .. " for " .. user .. ": die now (not on fire), then run rs.lastpages.corpse.check")
    end)
end)

RST.suite("rs.lastpages.corpse.check", { tags = { "world", "server", "manual" } }, function(s)
    s.test("corpse of the armed death holds the marked paper", function(t)
        authority(t)
        local token = W.last
        if token == nil then t:skip("nothing armed in this session (run rs.lastpages.corpse.arm first)") end
        local seen = W.seen[token]
        t:ok(seen ~= nil, "no death of the armed player seen yet (token " .. token .. ")")
        t:ok(seen.inventory, "no inventory at OnCharacterDeath")
        t:ok(seen.added, "paper not added to the inventory at OnCharacterDeath")
        local found, body
        for _, b in ipairs(corpsesNear(seen.x, seen.y, seen.z, RADIUS)) do
            local it = witnessIn(b:getContainer(), token)
            if it ~= nil then found, body = it, b end
        end
        if found == nil and getCell():getGridSquare(seen.x, seen.y, seen.z) == nil then
            t:skip("death square " .. seen.x .. "," .. seen.y .. "," .. seen.z .. " not loaded here")
        end
        t:ok(found ~= nil, "no corpse near " .. seen.x .. "," .. seen.y .. " holds the paper " .. token)
        t:note("corpse of " .. seen.user .. " isPlayer " .. tostring(body:isPlayer()) .. ", "
            .. body:getContainer():getItems():size() .. " item(s), corpses on the square before the death "
            .. tostring(seen.corpsesBefore) .. ", on fire " .. tostring(seen.onFire))
    end)
end)
