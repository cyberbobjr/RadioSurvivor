--[[
RadioSurvivorCore: identity of the player characters (E18-T03), shared by RadioSurvivor and Living Knox.

A character has one identity "character-<ms>-<n>-<rand>", decided by the authority (dedicated server, or the solo
game) and kept by both mods: the notebook keys its records on it, Living Knox its attitudes and facts.
Rules (E00-T01, E00-T02, moved here unchanged):
- the authority writes the identity into ITS copy of the player modData (key KEY): in MP only the server IsoPlayer is
  saved, a value written by a client into its own modData is lost at reconnection;
- the value sent by the client is only a fallback for states created before this rule: accepted for the same owner
  (account in MP, "solo" in solo) and the same slot, never for a retired identity;
- a new character gets a new identity; OnCharacterDeath (IsoPlayer only, owner checked) retires it for good and
  clears the modData key. Identity.idOf still gives the retired identity of that dead player object to the other
  death subscribers of the same event, whatever their order.

Registry (schema 1), private file of the authority (RC_SlotFile, header RCID1), never a global ModData:
  Zomboid/Lua/batman_RadioSurvivorCore/identity-<hex of "game mode/world">-<0|1>.txt
  { schema = 1, counter = n, characters = { [id] = { owner, slot, retired = true|nil } } }
New world (RC_WorldStart): empty registry, even if an old file has the same name.

An unknown CLIENT claim is never accepted.

Network (module MODULE): the client sends "hello" { character = its modData value } when the game starts and when
its player is created; the authority binds and answers "identity" { character }, which the client stores in its
modData. RadioSurvivor binds through Identity.bind from its own hello too: both give the same answer.
]]
local SlotFile = require "RadioSurvivorCore/RC_SlotFile"
local WorldStart = require "RadioSurvivorCore/RC_WorldStart"
local RateLimit = require "RadioSurvivorCore/RC_RateLimit"

local Identity = RC_Identity or {}
RC_Identity = Identity

Identity.KEY = "RS_CarnetCharacter"   -- modData key, kept from the notebook (saved games read as they are)
Identity.MODULE = "RadioSurvivorCore"
Identity.DIR = "batman_RadioSurvivorCore/"
Identity.HEADER = "RCID1"
Identity.SCHEMA = 1
Identity.HELLO_LIMIT = { 4, 0.5 }    -- per-account token bucket of "hello" (RC_RateLimit, MP server only)
Identity.MAX_ID = 64

Identity.bound = Identity.bound or {}           -- [IsoPlayer of the authority] = identity
Identity.retiredBy = Identity.retiredBy or {}   -- [dead IsoPlayer] = identity retired at its death (this session)
Identity.state = Identity.state or { data = nil, seq = 0, base = nil, blocked = false }
Identity.listeners = Identity.listeners or { bind = {}, retire = {} }

local function log(text) print("[RadioSurvivorCore] identity: " .. text) end

local function authority() return not isClient() end

function Identity.ownerOf(player)
    return isServer() and player:getUsername() or "solo"
end

local function validId(id)
    return type(id) == "string" and #id > 0 and #id <= Identity.MAX_ID and not string.find(id, "[^%w_.:-]")
end

local function emptyData() return { schema = Identity.SCHEMA, counter = 0, characters = {} } end

-- Loads the registry of this world (once). newWorld: OnInitGlobalModData argument, read through RC_WorldStart.
function Identity.init(newWorld)
    if not authority() then return false end
    local st = Identity.state
    if st.data ~= nil or st.blocked then return st.data ~= nil end
    st.base = SlotFile.worldBase(Identity.DIR, "identity")
    if WorldStart.isNewWorld(newWorld == true) then
        st.data, st.seq = emptyData(), 0
        log("new world, empty registry")
        return Identity.save()
    end
    local best, broken = SlotFile.read(st.base, Identity.HEADER)
    if best == nil then
        if broken then
            st.blocked = true
            log("ERROR registry unreadable, kept as is; identities are not saved this session")
            return false
        end
        st.data, st.seq = emptyData(), 0
        log("no registry yet, empty registry")
        return true
    end
    local data = best.data
    if data.schema ~= Identity.SCHEMA or type(data.characters) ~= "table" then
        st.blocked = true
        log("ERROR registry of an unknown schema " .. tostring(data.schema) .. ", kept as is")
        return false
    end
    data.counter = tonumber(data.counter) or 0
    st.data, st.seq = data, best.seq
    local n = 0
    for _ in pairs(data.characters) do n = n + 1 end
    log("registry read, " .. n .. " character(s)")
    return true
end

-- True when the registry is loaded (loaded now if the world exists and OnInitGlobalModData was missed).
function Identity.ensure()
    if Identity.state.data ~= nil then return true end
    if Identity.state.blocked or not authority() or getWorld == nil or getWorld() == nil then return false end
    return Identity.init(false)
end

function Identity.save()
    local st = Identity.state
    if st.data == nil or st.blocked then return false end
    local ok, why = SlotFile.write(st.base, Identity.HEADER, st.seq + 1, st.data)
    if not ok then
        log("ERROR registry not saved: " .. tostring(why))
        return false
    end
    st.seq = st.seq + 1
    return true
end

-- Record of an identity (read only), or nil.
function Identity.record(id)
    if not Identity.ensure() or not validId(id) then return nil end
    return Identity.state.data.characters[id]
end

-- True when id belongs to this owner and slot and is not retired.
function Identity.usable(id, owner, slot)
    local r = Identity.record(id)
    return r ~= nil and r.owner == owner and r.slot == slot and not r.retired
end

local function newId()
    local data = Identity.state.data
    data.counter = data.counter + 1
    return "character-" .. string.format("%.0f", getTimestampMs()) .. "-" .. data.counter .. "-"
        .. ZombRand(100000, 999999)
end

local function notify(kind, ...)
    for _, fn in ipairs(Identity.listeners[kind]) do
        local ok, err = pcall(fn, ...)
        if not ok then log("ERROR " .. kind .. " listener: " .. tostring(err)) end
    end
end

-- fn(player, id, created) after each new binding; fn(player, id) after a retirement (death).
function Identity.onBind(fn) table.insert(Identity.listeners.bind, fn) end
function Identity.onRetire(fn) table.insert(Identity.listeners.retire, fn) end

-- Binds the player of the authority to its identity: the server modData value, else the client claim when usable,
-- else a new one. Returns the
-- identity and true when it was created, or nil (registry unreadable, save failed, dead player).
function Identity.bind(player, claimed)
    if player == nil or not Identity.ensure() then return nil end
    local known = Identity.bound[player]
    if known ~= nil then return known, false end
    if player:isDead() then return nil end
    local owner, slot = Identity.ownerOf(player), player:getPlayerNum()
    local md = player:getModData()
    local stored = md[Identity.KEY]
    local chars = Identity.state.data.characters
    local id
    local created, changed = false, false
    if Identity.usable(stored, owner, slot) then
        id = stored
    elseif Identity.usable(claimed, owner, slot) then
        id = claimed
    else
        id = newId()
        chars[id] = { owner = owner, slot = slot }
        created, changed = true, true
    end
    if changed and not Identity.save() then
        chars[id] = nil
        return nil
    end
    md[Identity.KEY] = id
    Identity.bound[player] = id
    notify("bind", player, id, created)
    return id, created
end

-- Identity bound to this player (nil before its hello, after its death or for another machine's player).
function Identity.of(player)
    if player == nil then return nil end
    return Identity.bound[player]
end

-- Bound identity, or the identity retired at the death of this player object (death subscribers).
function Identity.idOf(player)
    if player == nil then return nil end
    return Identity.bound[player] or Identity.retiredBy[player]
end

-- OnCharacterDeath: retires the identity of a dead player of the authority (zombies and NPC bodies ignored).
function Identity.characterDeath(character)
    if not authority() or not instanceof(character, "IsoPlayer") or not Identity.ensure() then return end
    local md = character:getModData()
    local id = Identity.bound[character] or md[Identity.KEY]
    local r = Identity.record(id)
    if r == nil or r.retired or r.owner ~= Identity.ownerOf(character) then return end
    r.retired = true
    md[Identity.KEY] = nil
    Identity.bound[character] = nil
    Identity.retiredBy[character] = id
    Identity.save()
    log("retired " .. id .. " (death)")
    notify("retire", character, id)
end

local function reply(player, id)
    local args = { character = id }
    if isServer() then
        sendServerCommand(player, Identity.MODULE, "identity", args)
    else
        Identity.receive("identity", args)   -- solo: same Lua, no server command
    end
end

function Identity.onClientCommand(module, command, player, args)
    if module ~= Identity.MODULE or command ~= "hello" or player == nil or not authority() then return end
    if not RateLimit.allow(player, "core.hello", Identity.HELLO_LIMIT[1], Identity.HELLO_LIMIT[2]) then return end
    local claimed = type(args) == "table" and args.character or nil
    local id = Identity.bind(player, claimed)
    if id ~= nil then reply(player, id) end
end

-- Forgets the bindings of players gone from the game (reconnection: a new IsoPlayer). Called once a second.
local nextSweep = 0
function Identity.sweep()
    local now = getTimestampMs()
    if now < nextSweep then return end
    nextSweep = now + 1000
    if not isServer() then return end
    local present = {}
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do present[list:get(i)] = true end
    for p in pairs(Identity.bound) do
        if not present[p] then Identity.bound[p] = nil end
    end
    for p in pairs(Identity.retiredBy) do
        if not present[p] then Identity.retiredBy[p] = nil end
    end
end

-- Client ---------------------------------------------------------------------------------------------------------
function Identity.hello()
    local p = getSpecificPlayer(0)
    if p == nil then return end
    sendClientCommand(p, Identity.MODULE, "hello", { character = p:getModData()[Identity.KEY] })
end

function Identity.receive(command, args)
    if command ~= "identity" or type(args) ~= "table" or not validId(args.character) then return end
    local p = getSpecificPlayer(0)
    if p ~= nil then p:getModData()[Identity.KEY] = args.character end
    Identity.mine = args.character
end

function Identity.onServerCommand(module, command, args)
    if module == Identity.MODULE then Identity.receive(command, args) end
end

if not Identity.subscribed then
    Identity.subscribed = true
    Events.OnInitGlobalModData.Add(Identity.init)
    Events.OnClientCommand.Add(Identity.onClientCommand)
    Events.OnCharacterDeath.Add(Identity.characterDeath)
    Events.OnTickEvenPaused.Add(Identity.sweep)
    if isClient() or not isServer() then
        Events.OnServerCommand.Add(Identity.onServerCommand)
        Events.OnGameStart.Add(Identity.hello)
        Events.OnCreatePlayer.Add(function(num) if num == 0 then Identity.hello() end end)
    end
end

return Identity
