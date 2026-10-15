--[[
RST_PeerChecksDeath - client steps and authority helpers of the REAL death of a client (E00-T02, E03-T04, E15-T02;
suite rs.death, RS_Death.lua). Development mod only. Load with: require "RST/RST_PeerChecksDeath" (shared: the suite
requires it, so every machine that loads the suites registers the client handlers; the helpers run on the authority).

Client handlers (RST.Steps.on)
    death.prepare  {}: the local player leaves god mode the vanilla way (setGodMod(false) + sendPlayerExtraInfo: the
                   server applies it, ExtraInfoPacket.processServer) and waits until its own copy reads false.
                   PASS data { godmode = true when it was on before } (the suite gives it back to the new character).
    death.corpse   { x, y, z, radius, token }: waits until a corpse within radius squares of x, y on level z holds, in
                   ITS container as received here (PlayerDeath packet), the witness paper of token (ModData mark
                   RST_PeerDeath.MARK = token, or the custom name "RST corpse witness <token>"). PASS data { items };
                   FAIL at the deadline with the corpses and item counts seen.
    death.after    { old, godmode }: waits until the local player is a living character again (new character after
                   the post-death screen) and the notebook client (RS_CarnetClient) holds an identity other than old;
                   god mode given back when args.godmode. PASS data { character, name }.
Authority helpers
    PD.arm(user, token)       one-shot OnCharacterDeath witness for the IsoPlayer of account user: records the death
                              (square, inventory present, identity still bound at that time, on fire) in PD.seen[token]
                              and adds the marked paper to the inventory (it ends in the corpse: IsoDeadBody takes that
                              very container, IsoGameCharacter.java:13480-13542, IsoDeadBody.java:327-333).
    PD.disarm(user)           forgets an armed witness that did not fire.
    PD.corpseWith(x, y, z, radius, token) -> body, item, or nil
    PD.alivePlayerOf(name, except) -> online living IsoPlayer of the account (other than except), or nil (server)
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerDeath = RST.PeerDeath or {}
local PD = RST.PeerDeath
local Steps = RST.Steps

PD.MARK = "rsLastPagesWitness"     -- same mark as rs.lastpages.corpse (RS_LastPagesCorpse.lua)
PD.PAPER = "Base.SheetPaper2"
PD.armed = PD.armed or {}          -- user -> token
PD.seen = PD.seen or {}            -- token -> record of the death

local function log(msg) print("[RST] death " .. msg) end

local function userOf(p)
    local ok, name = pcall(function() return p:getUsername() end)
    return tostring(ok and name or "?")
end

function PD.witnessName(token) return "RST corpse witness " .. tostring(token) end

function PD.isWitness(item, token)
    if item == nil then return false end
    local okM, mark = pcall(function() return item:hasModData() and item:getModData()[PD.MARK] or nil end)
    if okM and mark == token then return true end
    local okN, name = pcall(function() return item:getName() end)
    return okN and name == PD.witnessName(token)
end

local function witnessIn(container, token)
    if container == nil then return nil end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if PD.isWitness(it, token) then return it end
    end
    return nil
end

-- Corpses within radius of (x, y) on level z, as a list.
function PD.corpsesNear(x, y, z, radius)
    local out = {}
    local cell = getCell()
    if cell == nil then return out end
    for dy = -radius, radius do
        for dx = -radius, radius do
            local sq = cell:getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            for i = 0, (list and list:size() or 0) - 1 do
                local o = list:get(i)
                if instanceof(o, "IsoDeadBody") then out[#out + 1] = o end
            end
        end
    end
    return out
end

function PD.corpseWith(x, y, z, radius, token)
    for _, b in ipairs(PD.corpsesNear(x, y, z, radius)) do
        local it = witnessIn(b:getContainer(), token)
        if it ~= nil then return b, it end
    end
    return nil
end

-- ---------------------------------------------------------------- authority: death witness

function PD.onDeath(chr)
    if not instanceof(chr, "IsoPlayer") then return end
    local user = userOf(chr)
    local token = PD.armed[user]
    if token == nil then return end
    PD.armed[user] = nil
    local Server = RS_CarnetServer
    local seen = { user = user, player = chr, x = math.floor(chr:getX()), y = math.floor(chr:getY()),
        z = math.floor(chr:getZ()), onFire = chr:isOnFire() and true or false,
        boundAtEvent = type(Server) == "table" and Server.bound and Server.bound[chr] or nil }
    local inv = chr:getInventory()
    seen.inventory = inv ~= nil
    if inv ~= nil then
        local item = instanceItem(PD.PAPER)
        item:setName(PD.witnessName(token))
        item:setCustomName(true)
        item:getModData()[PD.MARK] = token
        inv:AddItem(item)
        seen.added = inv:contains(item) and true or false
    end
    PD.seen[token] = seen
    log("OnCharacterDeath of " .. user .. " at " .. seen.x .. "," .. seen.y .. "," .. seen.z .. ": paper added "
        .. tostring(seen.added) .. ", on fire " .. tostring(seen.onFire))
end

function PD.listen()
    if PD.listening or type(Events) ~= "table" or Events.OnCharacterDeath == nil then return end
    PD.listening = true
    Events.OnCharacterDeath.Add(function(chr) RST.PeerDeath.onDeath(chr) end)
end

function PD.arm(user, token)
    PD.listen()
    PD.armed[user] = token
    PD.seen[token] = nil
end

function PD.disarm(user) PD.armed[user] = nil end

function PD.alivePlayerOf(name, except)
    if type(getOnlinePlayers) ~= "function" then return nil end
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        if p ~= nil and p ~= except and userOf(p) == name and not p:isDead() then return p end
    end
    return nil
end

-- ---------------------------------------------------------------- client steps

local function localPlayer()
    if type(getPlayer) ~= "function" then return nil end
    local ok, p = pcall(getPlayer)
    if ok then return p end
    return nil
end

local function setGod(p, on)
    p:setGodMod(on)
    if type(isClient) == "function" and isClient() and type(sendPlayerExtraInfo) == "function" then
        sendPlayerExtraInfo(p)
    end
end

Steps.on("death.prepare", function()
    local p = localPlayer()
    if p == nil then return Steps.fail("no local player") end
    if p:isDead() then return Steps.fail("the local player is already dead") end
    local was = p:isGodMod() and true or false
    if was then setGod(p, false) end
    return function(ctx)
        if not p:isGodMod() then
            return Steps.pass("god mode " .. (was and "removed" or "already off") .. " for the death test",
                { godmode = was })
        end
        if ctx.final then return Steps.fail("god mode still on here (role without ToggleGodModHimself?)") end
        return nil
    end
end)

Steps.on("death.corpse", function(args)
    local token, radius = args.token, tonumber(args.radius) or 3
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z) or 0
    if type(token) ~= "string" or x == nil or y == nil then return Steps.fail("death.corpse needs x, y and a token") end
    return function(ctx)
        local body, item = PD.corpseWith(x, y, z, radius, token)
        if body ~= nil then
            local n = body:getContainer():getItems():size()
            return Steps.pass("corpse at " .. math.floor(body:getX()) .. "," .. math.floor(body:getY()) .. " holds '"
                .. tostring(item:getName()) .. "' (" .. n .. " item(s)) here", { items = n })
        end
        if ctx.final then
            local corpses, items = PD.corpsesNear(x, y, z, radius), 0
            for _, b in ipairs(corpses) do
                local c = b:getContainer()
                items = items + (c and c:getItems():size() or 0)
            end
            local sq = getCell() and getCell():getGridSquare(x, y, z) or nil
            return Steps.fail("no corpse near " .. x .. "," .. y .. "," .. z .. " holds the paper " .. token .. " here ("
                .. #corpses .. " corpse(s), " .. items .. " item(s)" .. (sq == nil and ", square not loaded" or "")
                .. ")")
        end
        return nil
    end
end)

Steps.on("death.after", function(args)
    local restored = false
    return function(ctx)
        local p = localPlayer()
        local C = RS_CarnetClient
        local cid = type(C) == "table" and C.character or nil
        if p ~= nil and not p:isDead() and type(cid) == "string" and cid ~= args.old then
            if args.godmode and not restored then
                restored = true
                setGod(p, true)
            end
            local name = tostring(p:getDescriptor():getForename()) .. " " .. tostring(p:getDescriptor():getSurname())
            return Steps.pass("new character " .. name .. " alive here, notebook identity " .. cid
                .. (restored and ", god mode given back" or ""), { character = cid, name = name })
        end
        if ctx.final then
            return Steps.fail("no new living character with a new notebook identity here (player "
                .. (p == nil and "none" or (p:isDead() and "dead" or "alive")) .. ", identity " .. tostring(cid)
                .. ", old " .. tostring(args.old) .. ")")
        end
        return nil
    end
end)

return PD
