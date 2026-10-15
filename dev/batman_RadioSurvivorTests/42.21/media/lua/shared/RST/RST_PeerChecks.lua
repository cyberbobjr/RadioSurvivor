--[[
RST_PeerChecks - client checks and player actions asked by the authority through RST.Steps (E01-T16). Development mod
only. Load with: require "RST/RST_PeerChecks" (shared: the describers run on both sides, so that the server builds the
expected value with the same code as the client that checks it).

Client handlers (RST.Steps.on)
    world.keys        { squares = { { x, y, z }, ... }, kinds, expect = { { key, ... }, ... } }: the keys of each square
                      (PC.squareKeys) equal the expected ones; polled until equal (replication delay) or the deadline.
    lk.present        { bodies = { { o, p }, ... } }: a local copy of each body exists (zombieOf), polled.
    lk.look           { bodies = { { o = onlineId, sig = signature }, ... } }: the local copy of each zombie body
                      (found by its online id) has the same signature (PC.look: skin, hair, beard, colour, clothes);
                      a copy not drawn yet (culled: never dressed) is dressed first as the renderer does (LK02-T15).
    lk.speech.seen    { lines = { { id, names = { account, ... } }, ... } }: every line heard by this account (its name
                      in names) reached its speech view (LivingKnox.SpeechView.seen); SKIP when it heard none.
    lk.speech.pieces  { answer }: the bubble pieces of the answer (View.lastPieces) and the order in which they were
                      shown (View.pieceLog), returned in data once all were shown (E17-T13).
    rst.access        { user, level }: the requester (admin) sends "/setaccesslevel <user> <level>" (SendCommandToServer,
                      ChangeAccessLevel); test accounts rs_mp<N> of the launcher only, user or admin only, never itself.
    rst.request       { module, command, reply, args }: this client sends the command of a tool (LivingKnox
                      adminRequest, RadioSurvivorDebug freqRequest) and returns the reply of the same request number.
    carnet.send       { command, args }: RS_CarnetClient.send for select, deselect and accept only.
    carnet.talk       { text, cooldownMs }: the notebook Say line (RS_CarnetClient.talk(text, true)) once the client no
                      longer waits for an answer and the cooldown is over.
    carnet.state      { mission }: notebook client state: lastError, waiting, offer shown, snapshot row of the mission.
Authority helpers (suite code, through RST.Steps.ask)
    PC.checkSquares(t, squares, kinds, after)  expected keys built here, asked to the other clients ("others").
    PC.checkLooks(t, bodies, after)            signatures of the zombie bodies built here, asked to the others.
    PC.waitCopies(t, bodies, after)            the others hold a local copy of each body (lk.present) before a
                                               death is checked: a zombie killed before its copy reached a client
                                               leaves no corpse there (vanilla, DeadZombiePacket dropped).
    PC.recordSpeech(t) -> list                 lines said by LivingKnox.Speech.say until the end of the test
                                               ({ id, npc, key, names }); PC.checkSpeech(t, lines, after) asks the
                                               others to have shown the lines they heard (fails when another client
                                               is not among the listeners).
    PC.asUser(t, after)                        the first other client gets the access level "user" (asked to the
                                               requester, role read back on the server), "admin" again at the end
                                               (t:defer); after(t, account). SKIP without a dedicated server or
                                               without a second client.
    PC.request(t, user, spec, after)           rst.request asked to that account; after(t, reply or nil).
    PC.assertRefused(t, reply, n, label)       { ok = false, err = "denied", n } and no other field.
Kinds of PC.squareKeys: { corpse = true, barricade = true, thumpable = true | { name, ... },
container = true | { sprite name, ... }, floor = true (items on the floor: "floor <full type>"),
sprite = { sprite name, ... } (objects drawn with one of these sprites: "sprite <name>"),
light = true (IsoLightSwitch: "light <sprite> on=<activated>") }.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerChecks = RST.PeerChecks or {}
local PC = RST.PeerChecks
local Steps = RST.Steps

PC.SQUARE_MS = 20000
PC.LOOK_MS = 20000
PC.SPEECH_MS = 10000
PC.REQUEST_MS = 10000
PC.ACCESS_MS = 15000
PC.MODULES = { LivingKnox = { adminRequest = "adminReply" }, RadioSurvivorDebug = { freqRequest = "freqReply" } }
PC.CARNET_COMMANDS = { select = true, deselect = true, accept = true }

local function safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- ---------------------------------------------------------------- describers (both sides)

-- "type*n" of the items of a container, sorted, comma separated ("" when empty).
function PC.itemsKey(container)
    local counts, names = {}, {}
    local items = container and safe(function() return container:getItems() end)
    for i = 0, (items and items:size() or 0) - 1 do
        local ft = tostring(items:get(i):getFullType())
        if counts[ft] == nil then
            counts[ft] = 0
            names[#names + 1] = ft
        end
        counts[ft] = counts[ft] + 1
    end
    table.sort(names)
    local out = {}
    for i, ft in ipairs(names) do out[i] = counts[ft] > 1 and (ft .. "*" .. counts[ft]) or ft end
    return table.concat(out, ",")
end

function PC.corpseKey(body)
    local worn = {}
    local list = safe(function() return body:getWornItems() end)
    for i = 0, (list and list:size() or 0) - 1 do
        local it = safe(function() return list:get(i):getItem():getFullType() end)
        if it then worn[#worn + 1] = tostring(it) end
    end
    table.sort(worn)
    return "corpse worn=" .. table.concat(worn, ",") .. " items=" .. PC.itemsKey(safe(function() return body:getContainer() end))
end

local function listed(filter, value)
    if filter == true then return true end
    if type(filter) ~= "table" then return false end
    for _, v in ipairs(filter) do if v == value then return true end end
    return false
end

local function spriteName(o)
    return safe(function() return o:getSprite():getName() end) or "?"
end

-- Sorted keys of what a square holds for the given kinds, or nil when the square is not loaded here.
function PC.squareKeys(x, y, z, kinds)
    local sq = getCell() and getCell():getGridSquare(x, y, z)
    if sq == nil then return nil end
    kinds = kinds or {}
    local out = {}
    if kinds.corpse then
        local list = sq:getStaticMovingObjects()
        for i = 0, (list and list:size() or 0) - 1 do
            local o = list:get(i)
            if instanceof(o, "IsoDeadBody") then out[#out + 1] = PC.corpseKey(o) end
        end
    end
    local objects = sq:getObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        local o = objects:get(i)
        if kinds.barricade and instanceof(o, "IsoBarricade") then
            out[#out + 1] = "barricade planks=" .. tostring(safe(function() return o:getNumPlanks() end))
                .. " metal=" .. tostring(safe(function() return o:isMetal() end) and true or false)
        elseif kinds.thumpable and instanceof(o, "IsoThumpable") then
            local name = tostring(safe(function() return o:getName() end))
            if listed(kinds.thumpable, name) then
                out[#out + 1] = "thumpable " .. name .. " north=" .. tostring(safe(function() return o:getNorth() end)
                    and true or false)
            end
        end
        if kinds.sprite and type(kinds.sprite) == "table" and listed(kinds.sprite, spriteName(o)) then
            out[#out + 1] = "sprite " .. spriteName(o)
        end
        if kinds.light and instanceof(o, "IsoLightSwitch") then
            out[#out + 1] = "light " .. spriteName(o) .. " on=" .. tostring(safe(function() return o:isActivated() end)
                and true or false)
        end
        if kinds.container then
            local sprite = spriteName(o)
            local n = safe(function() return o:getContainerCount() end) or 0
            if n > 0 and listed(kinds.container, sprite) then
                for j = 0, n - 1 do
                    out[#out + 1] = "container " .. sprite .. " items=" .. PC.itemsKey(o:getContainerByIndex(j))
                end
            end
        end
    end
    if kinds.floor then
        local floor = sq:getWorldObjects()
        for i = 0, (floor and floor:size() or 0) - 1 do
            local ft = safe(function() return floor:get(i):getItem():getFullType() end)
            if ft then out[#out + 1] = "floor " .. tostring(ft) end
        end
    end
    table.sort(out)
    return out
end

-- Expected keys of the squares (authority); a square not loaded gives an empty list.
function PC.expectSquares(squares, kinds)
    local out = {}
    for i, s in ipairs(squares) do out[i] = PC.squareKeys(s.x, s.y, s.z, kinds) or {} end
    return out
end

-- Short difference of two texts by tokens (separated by spaces, commas, semicolons, "=" and "*"): what the server
-- has and this client lacks, and the reverse (multisets).
function PC.diff(expected, got)
    local function count(text)
        local c = {}
        for tok in string.gmatch(tostring(text or ""), "[^%s,;=]+") do c[tok] = (c[tok] or 0) + 1 end
        return c
    end
    local a, b = count(expected), count(got)
    local missing, extra = {}, {}
    for k, n in pairs(a) do if (b[k] or 0) < n then missing[#missing + 1] = k end end
    for k, n in pairs(b) do if (a[k] or 0) < n then extra[#extra + 1] = k end end
    table.sort(missing)
    table.sort(extra)
    return "missing here [" .. table.concat(missing, " ") .. "], extra here [" .. table.concat(extra, " ") .. "]"
end

local function same(a, b)
    return table.concat(a or {}, "\n") == table.concat(b or {}, "\n")
end

-- Signature of what a body draws: skin, haircut, beard, hair colour, sorted clothes keys (LivingKnox.Appearance).
function PC.look(body)
    local hv = body:getHumanVisual()
    local c = hv:getHairColor()
    local parts = { tostring(hv:getSkinTexture()), tostring(hv:getHairModel()), tostring(hv:getBeardModel()),
        c:getRedInt() .. "," .. c:getGreenInt() .. "," .. c:getBlueInt() }
    local A = LivingKnox and LivingKnox.Appearance
    local keys = A and A.clothesKeys(A.describe(body)) or {}
    table.sort(keys)
    return table.concat(parts, " ") .. " " .. table.concat(keys, ";")
end

-- Local copy of a body: by its persistent outfit id (the shared descriptor id of a reanimated player, the same on the
-- server and every client from the creation of the copy), else by its online id.
-- Local copy of the server body b ({ o = online id, p = persistent outfit id }). The persistent outfit id is not
-- unique: bodies dressed in the same outfit variant share it (campaign MP 2026-10-15, lk.appearance: the copy of
-- another body with outfit id 39911425, online id 29938 instead of 29951, was compared). Among the copies with that
-- outfit id, the one with the same online id wins; otherwise the first one (the online id of a reanimated player's
-- copy may differ from the server's). Without an outfit id, the online id alone.
local function zombieOf(b)
    local list = getCell() and getCell():getZombieList()
    local byOnline, byOutfit = nil, nil
    local outfit = b.p ~= nil and b.p ~= 0
    for i = 0, (list and list:size() or 0) - 1 do
        local z = list:get(i)
        if z ~= nil and not z:isDead() then
            local sameOnline = z:getOnlineID() == b.o
            if outfit and z:getPersistentOutfitID() == b.p then
                if sameOnline then return z end
                if byOutfit == nil then byOutfit = z end
            end
            if byOnline == nil and sameOnline then byOnline = z end
        end
    end
    if outfit then return byOutfit end
    return byOnline
end

-- Other live copies with the outfit id of b and another online id than z (copies of other bodies dressed alike).
local function sameOutfit(b, z)
    local out = {}
    if b.p == nil or b.p == 0 then return out end
    local list = getCell() and getCell():getZombieList()
    for i = 0, (list and list:size() or 0) - 1 do
        local o = list:get(i)
        if o ~= nil and o ~= z and not o:isDead() and o:getPersistentOutfitID() == b.p then out[#out + 1] = o end
    end
    return out
end

-- Plain copy of a reply table (strings, numbers, booleans, nested tables up to depth 4).
local function plain(v, depth)
    if type(v) ~= "table" then
        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return v end
        return nil
    end
    if depth > 4 then return nil end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then out[k] = plain(x, depth + 1) end
    end
    return out
end

-- ---------------------------------------------------------------- client handlers

-- Diagnostic: corpses of this client within r squares of (x, y, z): "x,y(worn n)" list.
local function corpsesNear(x, y, z, r)
    local out = {}
    for dy = -r, r do
        for dx = -r, r do
            local sq = getCell() and getCell():getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            for i = 0, (list and list:size() or 0) - 1 do
                local o = list:get(i)
                if instanceof(o, "IsoDeadBody") then
                    out[#out + 1] = (x + dx) .. "," .. (y + dy) .. "(worn " .. tostring(safe(function()
                        return o:getWornItems():size() end)) .. ")"
                end
            end
        end
    end
    return #out .. " corpse(s) within " .. r .. ": " .. table.concat(out, " ")
end

-- Number of static moving objects (corpses...) of a square, or -1 when it is not loaded here.
function PC.staticCount(x, y, z)
    local sq = getCell() and getCell():getGridSquare(x, y, z)
    if sq == nil then return -1 end
    local list = sq:getStaticMovingObjects()
    return list and list:size() or 0
end

-- Diagnostic (LK07-T09): zombies of this client within r squares, "onlineId@x,y(dead, reanimated player)", and the
-- squares whose number of static moving objects differs from the server's (args.counts).
local function corpseDiag(args, c, r)
    local out = {}
    local list = getCell() and getCell():getZombieList()
    for i = 0, (list and list:size() or 0) - 1 do
        local zb = list:get(i)
        if zb ~= nil and math.abs(zb:getX() - c.x) <= r and math.abs(zb:getY() - c.y) <= r then
            out[#out + 1] = tostring(zb:getOnlineID()) .. "@" .. math.floor(zb:getX()) .. "," .. math.floor(zb:getY())
                .. "(" .. (zb:isDead() and "dead" or "alive") .. (zb:isReanimatedPlayer() and ",rp" or "") .. ")"
        end
    end
    local diffs = {}
    for i, s in ipairs(args.squares or {}) do
        local want = (args.counts or {})[i]
        local here = PC.staticCount(s.x, s.y, s.z)
        if want ~= nil and want ~= here then
            diffs[#diffs + 1] = s.x .. "," .. s.y .. " server " .. want .. " here " .. here
        end
    end
    return "zombies within " .. r .. ": [" .. table.concat(out, " ") .. "]; static objects differ: ["
        .. table.concat(diffs, "; ") .. "]"
end

-- args.union: compare the keys of all the squares together (a corpse of a client copy may lie on a neighbour square).
local function unionCheck(args, ctx, state)
    local all, want, missing = {}, {}, 0
    for i, s in ipairs(args.squares or {}) do
        local got = PC.squareKeys(s.x, s.y, s.z, args.kinds)
        if got == nil then missing = missing + 1 else for _, k in ipairs(got) do all[#all + 1] = k end end
        for _, k in ipairs((args.expect or {})[i] or {}) do want[#want + 1] = k end
    end
    table.sort(all)
    table.sort(want)
    if missing == 0 and same(all, want) then return Steps.pass(#want .. " key(s) on " .. #(args.squares or {})
        .. " square(s) as on the server") end
    state.last = missing > 0 and (missing .. " square(s) not loaded on this client")
        or (#want .. " key(s) expected, " .. #all .. " here; " .. PC.diff(table.concat(want, " "), table.concat(all, " ")))
    if args.kinds and args.kinds.corpse and ctx.final and #(args.squares or {}) > 0 then
        local c = args.squares[math.floor((#args.squares + 1) / 2)]
        state.last = state.last .. "; " .. corpsesNear(c.x, c.y, c.z, 10) .. "; " .. corpseDiag(args, c, 10)
    end
    if ctx.final then
        if missing > 0 then return Steps.skip(state.last) end
        return Steps.fail(state.last)
    end
    return nil
end

Steps.on("world.keys", function(args)
    local squares, expect = args.squares or {}, args.expect or {}
    local last = "nothing read"
    if args.union then
        local state = {}
        return function(ctx) return unionCheck(args, ctx, state) end
    end
    return function(ctx)
        local allSame = true
        for i, s in ipairs(squares) do
            local got = PC.squareKeys(s.x, s.y, s.z, args.kinds)
            if got == nil then
                allSame = false
                last = "square " .. s.x .. "," .. s.y .. "," .. s.z .. " not loaded on this client"
                break
            end
            if not same(got, expect[i]) then
                allSame = false
                last = "square " .. s.x .. "," .. s.y .. "," .. s.z .. ": " .. #(expect[i] or {}) .. " key(s) expected, "
                    .. #got .. " here; " .. PC.diff(table.concat(expect[i] or {}, " "), table.concat(got, " "))
                break
            end
        end
        if allSame then return Steps.pass(#squares .. " square(s) as on the server") end
        if ctx.final then
            if string.find(last, "not loaded", 1, true) then return Steps.skip(last) end
            return Steps.fail(last)
        end
        return nil
    end
end)

Steps.on("lk.look", function(args)
    local bodies = args.bodies or {}
    local last = "nothing read"
    local undrawn = 0
    return function(ctx)
        local done = true
        for _, b in ipairs(bodies) do
            local z = zombieOf(b)
            if z == nil then
                done = false
                last = "no zombie with persistent outfit id " .. tostring(b.p) .. " (online id " .. tostring(b.o)
                    .. ") on this client"
                break
            end
            -- A copy is dressed only when it is first drawn (ModelManager.Add -> dressInRandomOutfit, client: a
            -- reanimated player not yet dressed gets dressInPersistentOutfitID, whose outfitter applies the shared
            -- descriptor). A copy out of view (behind a wall, culled) keeps the random look of a new IsoZombie: dress
            -- it here exactly as the renderer will, so that what is compared is what the player will see.
            if not z:isPersistentOutfitInit() and z:getPersistentOutfitID() ~= 0 then
                z:dressInPersistentOutfitID(z:getPersistentOutfitID())
                undrawn = undrawn + 1
            end
            local sig = PC.look(z)
            if sig ~= b.sig and z:getOnlineID() ~= b.o then
                -- No copy with the server's online id: the body is one of the copies dressed in this outfit variant.
                for _, o in ipairs(sameOutfit(b, z)) do
                    if o:isPersistentOutfitInit() and PC.look(o) == b.sig then
                        z, sig = o, b.sig
                        break
                    end
                end
            end
            if sig ~= b.sig then
                done = false
                last = "body " .. tostring(b.p) .. " (online id here " .. tostring(z:getOnlineID()) .. ", server "
                    .. tostring(b.o) .. ", reanimated player " .. tostring(z:isReanimatedPlayer()) .. ", descriptor "
                    .. tostring(safe(function() return z:getSharedDescriptor() end) ~= nil) .. "): " .. PC.diff(b.sig, sig)
                break
            end
        end
        if done then
            return Steps.pass(#bodies .. " body(ies) drawn as on the server" .. (undrawn > 0 and (" (" .. undrawn
                .. " not drawn yet here: dressed as the renderer does)") or ""))
        end
        if ctx.final then
            print("[RST-PC] lk.look " .. last)
            return Steps.fail(last)
        end
        return nil
    end
end)

-- The local copy of each body exists (alive): a zombie killed before a client received it never leaves a corpse
-- there (DeadZombiePacket is dropped when the client has no copy, DeadCharacterPacket.isConsistent).
Steps.on("lk.present", function(args)
    local bodies = args.bodies or {}
    return function(ctx)
        for _, b in ipairs(bodies) do
            if zombieOf(b) == nil then
                if ctx.final then
                    return Steps.fail("no local copy of body " .. tostring(b.p) .. " (online id " .. tostring(b.o) .. ")")
                end
                return nil
            end
        end
        return Steps.pass(#bodies .. " body(ies) present after " .. math.floor(RST.now() - ctx.startedMs) .. " ms")
    end
end)

Steps.on("lk.speech.seen", function(args, ctx)
    local V = LivingKnox and LivingKnox.SpeechView
    if V == nil then return Steps.fail("LivingKnox.SpeechView is not loaded on this client") end
    -- Solo: one local player, named by the authority otherwise than getUsername (LK_Directives.senderName): every
    -- line said was heard by it (Speech.say sends nothing when nobody hears).
    local solo = not (type(isClient) == "function" and isClient())
    local wanted = {}
    for _, line in ipairs(args.lines or {}) do
        local heard = solo
        for _, n in ipairs(line.names or {}) do
            if n == ctx.user then heard = true end
        end
        if heard then wanted[#wanted + 1] = line.id end
    end
    if #wanted == 0 then return Steps.skip("this account heard none of the " .. #(args.lines or {}) .. " line(s)") end
    return function(c)
        local missing = {}
        for _, id in ipairs(wanted) do
            if not V.seen[id] then missing[#missing + 1] = id end
        end
        if #missing == 0 then
            local last = V.last and V.last.text or nil
            return Steps.pass(#wanted .. " line(s) received" .. (last and (", last shown: '" .. last .. "'") or ""))
        end
        if c.final then return Steps.fail("line(s) never received here: " .. table.concat(missing, ", ")) end
        return nil
    end
end)

Steps.on("lk.speech.pieces", function(args)
    local V = LivingKnox and LivingKnox.SpeechView
    if V == nil or V.pieceLog == nil then return Steps.fail("speech view (LK_SpeechView) not loaded on this client") end
    local answer = args.answer
    return function(ctx)
        local last = V.lastPieces
        if last == nil or last.text ~= answer then
            if ctx.final then return Steps.fail("the answer was not shown in a bubble") end
            return nil
        end
        local pieces = last.pieces
        local shown, started = {}, false
        for _, e in ipairs(V.pieceLog) do
            if e.npc == last.npc then
                if e.text == pieces[1] then
                    shown, started = {}, true
                end
                if started then shown[#shown + 1] = { text = e.text, at = e.at, ms = e.ms } end
            end
        end
        local data = { pieces = pieces, shown = shown, npc = last.npc, PIECE = V.PIECE, MAX_SHOW_MS = V.MAX_SHOW_MS }
        if #pieces < 2 or #shown >= #pieces then return Steps.pass(#pieces .. " piece(s)", data) end
        if ctx.final then
            return Steps.fail("the pieces of the bubble were not all shown (" .. #shown .. "/" .. #pieces .. ")", data)
        end
        return nil
    end
end)

Steps.on("rst.access", function(args, ctx)
    if not (type(isClient) == "function" and isClient()) then return Steps.skip("access levels exist on a server only") end
    local user, level = tostring(args.user or ""), tostring(args.level or "")
    if not string.match(user, "^rs_mp%d+$") then
        return Steps.fail("refused: '" .. user .. "' is not a test account of the launcher (rs_mp<N>)")
    end
    if level ~= "user" and level ~= "admin" then return Steps.fail("refused: level '" .. level .. "'") end
    if user == ctx.user then return Steps.fail("refused: the requester never changes its own level") end
    SendCommandToServer("/setaccesslevel " .. user .. " " .. level)
    return Steps.pass("/setaccesslevel " .. user .. " " .. level .. " sent")
end)

PC.replies = PC.replies or {}

local function onReply(module, command, args)
    local spec = PC.MODULES[module]
    if spec == nil or type(args) ~= "table" or args.n == nil then return end
    for _, reply in pairs(spec) do
        if reply == command then PC.replies[module .. "/" .. command .. "/" .. tostring(args.n)] = args end
    end
end

Steps.on("rst.request", function(args)
    local spec = PC.MODULES[tostring(args.module)]
    local reply = spec and spec[tostring(args.command)]
    if reply == nil then return Steps.fail("refused: " .. tostring(args.module) .. "/" .. tostring(args.command)) end
    local a = type(args.args) == "table" and args.args or {}
    if a.n == nil then return Steps.fail("refused: request without a number n") end
    local key = args.module .. "/" .. reply .. "/" .. tostring(a.n)
    PC.replies[key] = nil
    sendClientCommand(getPlayer(), args.module, args.command, a)
    return function(ctx)
        local r = PC.replies[key]
        if r ~= nil then
            PC.replies[key] = nil
            return Steps.pass(args.command .. " " .. tostring(a.op) .. ": reply ok=" .. tostring(r.ok) .. " err="
                .. tostring(r.err), plain(r, 1))
        end
        if ctx.final then return Steps.fail("no " .. reply .. " for request " .. tostring(a.n)) end
        return nil
    end
end)

local function carnet()
    return RS_CarnetClient
end

Steps.on("carnet.send", function(args)
    local C = carnet()
    if C == nil then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    local command = tostring(args.command)
    if not PC.CARNET_COMMANDS[command] then return Steps.fail("refused: notebook command " .. command) end
    C.send(command, type(args.args) == "table" and args.args or {})
    return Steps.pass(command .. " sent")
end)

Steps.on("carnet.talk", function(args)
    local C = carnet()
    if C == nil then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    local cooldown = tonumber(args.cooldownMs) or 0
    return function(ctx)
        local last = C.lastTalkAt
        if not C.isWaiting() and (last == nil or getTimestampMs() - last >= cooldown) then
            C.lastError = nil
            if not C.talk(args.text, true) then return Steps.fail("sentence not sent: " .. tostring(args.text)) end
            return Steps.pass("said: " .. tostring(args.text))
        end
        if ctx.final then return Steps.fail("the notebook still waits for a previous answer") end
        return nil
    end
end)

local function carnetState(C, mission)
    local data = { lastError = C.lastError ~= nil and tostring(C.lastError) or nil, waiting = C.isWaiting() }
    if mission ~= nil then
        data.offerShown = C.offersShown ~= nil and C.offersShown[mission] == true
        for _, row in ipairs(C.snapshot and C.snapshot.missions or {}) do
            if row.id == mission then
                data.row = { engaged = row.engaged and true or false, mapZone = row.mapZone ~= nil, state = row.state }
            end
        end
    end
    return data
end

-- args.wait: nil (read now), "offer" (until the offer message of args.mission was shown) or "engaged" (until the
-- snapshot row of args.mission is engaged); the state is returned in data either way (the server asserts).
Steps.on("carnet.state", function(args)
    local C = carnet()
    if C == nil then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    return function(ctx)
        local data = carnetState(C, args.mission)
        local reached = args.wait == nil or (args.wait == "offer" and data.offerShown)
            or (args.wait == "engaged" and data.row ~= nil and data.row.engaged)
        if reached or ctx.final then
            return Steps.pass("state read" .. (reached and "" or (" (" .. tostring(args.wait) .. " not reached)")), data)
        end
        return nil
    end
end)

-- ---------------------------------------------------------------- authority helpers

-- Both clients are asked (target "all"): the requester is a client too in MP, and a difference seen by both is not
-- a matter of distance. In solo the local player answers (same Lua state as the authority).
function PC.checkSquares(t, squares, kinds, after, union)
    local expect = PC.expectSquares(squares, kinds)
    local counts = nil
    if kinds and kinds.corpse then
        counts = {}
        for i, s in ipairs(squares) do counts[i] = PC.staticCount(s.x, s.y, s.z) end
    end
    Steps.ask(t, "world.keys", { squares = squares, kinds = kinds, expect = expect, union = union, counts = counts },
        { target = "all", timeoutMs = PC.SQUARE_MS }, after)
end

-- Squares of the rectangle x-r..x+r, y-r..y+r on level z (a corpse of a client copy may lie a square away).
function PC.around(x, y, z, r)
    local out = {}
    for dy = -r, r do
        for dx = -r, r do out[#out + 1] = { x = x + dx, y = y + dy, z = z } end
    end
    return out
end

function PC.checkLooks(t, bodies, after)
    local list = {}
    for _, z in ipairs(bodies) do
        list[#list + 1] = { o = z:getOnlineID(), p = z:getPersistentOutfitID(), sig = PC.look(z) }
    end
    -- solo: one body only, online ids unused (-1): nothing to compare, nobody asked
    local target = (type(isServer) == "function" and isServer()) and "all" or "others"
    Steps.ask(t, "lk.look", { bodies = list }, { target = target, timeoutMs = PC.LOOK_MS }, after)
end

-- Waits until the other clients hold a local copy of each body (zombie objects of the authority), then after(t).
function PC.waitCopies(t, bodies, after)
    if #Steps.others(t) == 0 then return after(t) end -- solo or no other client: nothing to wait for
    local list = {}
    for _, z in ipairs(bodies) do list[#list + 1] = { o = z:getOnlineID(), p = z:getPersistentOutfitID() } end
    Steps.ask(t, "lk.present", { bodies = list }, { timeoutMs = PC.LOOK_MS }, after)
end

function PC.recordSpeech(t)
    local lines = {}
    local Sp = LivingKnox and LivingKnox.Speech
    if Sp == nil or type(Sp.say) ~= "function" then return lines end
    local say = Sp.say
    Sp.say = function(npcId, what, opts)
        local out, why = say(npcId, what, opts)
        if type(out) == "table" then
            local names = {}
            for i, n in ipairs(out.names or {}) do names[i] = tostring(n) end
            lines[#lines + 1] = { id = out.id, npc = npcId, key = type(what) == "table" and what.key or nil,
                names = names }
        end
        return out, why
    end
    t:defer(function() Sp.say = say end, "LivingKnox.Speech.say restored")
    return lines
end

function PC.checkSpeech(t, lines, after)
    local others = Steps.others(t)
    for _, user in ipairs(others) do
        local heard = false
        for _, line in ipairs(lines) do
            for _, n in ipairs(line.names) do if n == user then heard = true end end
        end
        local keys = {}
        for _, line in ipairs(lines) do keys[#keys + 1] = tostring(line.key or line.id) end
        t:ok(heard, "client " .. user .. " is not among the listeners of " .. #lines .. " line(s) ("
            .. table.concat(keys, ", ") .. ")")
    end
    local sent = {}
    for i, line in ipairs(lines) do sent[i] = { id = line.id, names = line.names } end
    Steps.ask(t, "lk.speech.seen", { lines = sent }, { timeoutMs = PC.SPEECH_MS }, after)
end

local function roleName(p)
    return safe(function() return p:getRole():getName() end)
end

local function setLevel(t, user, level, after)
    Steps.ask(t, "rst.access", { user = user, level = level }, { target = "requester", timeoutMs = PC.REQUEST_MS },
        function(t2)
            t2:waitUntil(function()
                local p = Steps.playerOf(user)
                return p ~= nil and roleName(p) == level
            end, PC.ACCESS_MS, function(t3)
                if after then return after(t3) end
            end, "role of " .. user .. " still not " .. level)
        end)
end

function PC.asUser(t, after)
    if not (type(isServer) == "function" and isServer()) then
        t:skip("needs a dedicated server and a second client (MP campaign, autoclient.py --mp --clients 2)")
    end
    local others = Steps.others(t)
    if #others == 0 then t:skip("no second client online (MP campaign, autoclient.py --mp --clients 2)") end
    local user = others[1]
    setLevel(t, user, "user", function(t2)
        t2:defer(function(tc) setLevel(tc, user, "admin") end, "access level of " .. user .. " back to admin")
        t2:note("client " .. user .. " has the access level user")
        return after(t2, user)
    end)
end

function PC.request(t, user, spec, after)
    Steps.ask(t, "rst.request", spec, { target = { user }, timeoutMs = PC.REQUEST_MS }, function(t2, res)
        local e = res.by[user]
        return after(t2, e and e.data or nil)
    end)
end

function PC.assertRefused(t, reply, n, label)
    t:ok(type(reply) == "table", label .. ": no reply")
    t:eq(false, reply.ok, label .. " accepted")
    t:eq("denied", reply.err, label .. " error")
    t:eq(n, reply.n, label .. " request number")
    for k in pairs(reply) do
        t:ok(k == "n" or k == "op" or k == "ok" or k == "err", label .. ": refusal carries the field " .. tostring(k))
    end
end

-- Several refused requests of one account in a row: specs = { { label, spec }, ... }; after(t) at the end.
function PC.requestsRefused(t, user, specs, after, i)
    i = i or 1
    local e = specs[i]
    if e == nil then
        if after then return after(t) end
        return
    end
    PC.request(t, user, e.spec, function(t2, reply)
        PC.assertRefused(t2, reply, e.spec.args.n, e.label)
        return PC.requestsRefused(t2, user, specs, after, i + 1)
    end)
end

-- Requests of the Living Knox administration tools (LK_Admin, module "LivingKnox", adminRequest), one per operation,
-- numbered from n0, with every argument any of them reads (a refusal must carry none of them back).
function PC.adminSpecs(ops, n0)
    local out = {}
    for i, op in ipairs(ops) do
        out[i] = { label = op, spec = { module = "LivingKnox", command = "adminRequest", args = { op = op, n = n0 + i,
            gid = "grp-1", npc = "lk-1", x = 1, y = 1, z = 0, field = "hunger", value = 90, role = "fighter",
            first = "Jane", last = "Doe", after = 0 } } }
    end
    return out
end

-- Test body shared by the rights suites (E01-T16): a REAL client with the access level "user" sends the requests of
-- specs; each one is refused without data; refused(delta) checks the counter of the authority afterwards.
function PC.refusedForUser(t, specs, counter)
    PC.asUser(t, function(t2, user)
        local before = counter and counter() or nil
        PC.requestsRefused(t2, user, specs, function(t3)
            if counter then t3:eq(before + #specs, counter(), "refusals counted by the authority") end
            t3:note(#specs .. " request(s) of " .. user .. " (user) refused without data")
        end)
    end)
end

-- ---------------------------------------------------------------- subscription (clients and solo, once)

if not PC._subscribed and type(Events) == "table" and Events.OnServerCommand
        and not (type(isServer) == "function" and isServer()) then
    Events.OnServerCommand.Add(function(module, command, args) RST.PeerChecks.onReply(module, command, args) end)
    PC._subscribed = true
end
PC.onReply = onReply

return PC
