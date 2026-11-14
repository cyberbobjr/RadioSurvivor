--[[
RST.GardenHygiene - furrows dug and seed packets received by the test groups are removed with their group (test mod
only, never published).

Every test group runs the real garden of Living Knox (LK15: LivingKnox.Garden.dig through the dig job), and a furrow
is a farming global object kept in the world after the test. The campaigns of 2026-11-13 showed the next suites
playing in a polluted home: lk.forage watered another thirsty plant than its fixture, lk.upkeep had a place shifted off
a plant and out of the home, lk.garden was skipped ("an empty furrow already waits in the home area").

The campaigns of 2026-11-14 showed the same with the seed packets (LK15-T06, LivingKnox.Garden.receiveSeeds): the
packet received by a test group stayed in the depot of the shared home, and lk.garden was skipped ("the home already
holds 5 sowable seed(s)").

install() (authority only, once): LivingKnox.Garden.dig and LivingKnox.Garden.receiveSeeds are wrapped to note, while
an RST run is in progress (RST.running()), each square dug and each seed of a packet put in a depot container; on the
"groupRemoved" event of Living Knox (every test removes its groups), the noted furrows and the plants grown on them are
removed (SFarmingSystem:removePlant, as the suites do for their own fixtures), and the noted seeds still in their
container (a seed sown is gone already). Out of a run nothing is noted: a save played with the test mod keeps its
gardens and its seeds. Installed at game start (OnGameStart in
solo, OnServerStarted on a dedicated server), once Living Knox is loaded.
]]

require "RST/RST"

local H = RST.GardenHygiene or {}
RST.GardenHygiene = H

H.dug = H.dug or {}
H.seeds = H.seeds or {}   -- { { ct = container, id = item id } }
H.LISTENER = "RST.gardenHygiene"

local function authority()
    local LK = LivingKnox
    return LK ~= nil and LK.isAuthority ~= nil and LK.isAuthority()
end

-- Removes every noted furrow (and the plant on it). Returns the number of plants removed.
function H.clear()
    local Gd = LivingKnox and LivingKnox.Garden
    local sys = Gd ~= nil and Gd.farming ~= nil and Gd.farming() or nil
    local n = 0
    if sys ~= nil then
        for _, q in ipairs(H.dug) do
            local plant = sys:getLuaObjectAt(q.x, q.y, q.z)
            if plant ~= nil then
                sys:removePlant(plant)
                n = n + 1
            end
        end
    end
    H.dug = {}
    if n > 0 then print("[RST] garden hygiene: " .. n .. " furrow(s) of test groups removed") end
    local byCt, k = {}, 0
    for _, e in ipairs(H.seeds) do
        byCt[e.ct] = byCt[e.ct] or {}
        byCt[e.ct][e.id] = true
    end
    for ct, ids in pairs(byCt) do
        local items = ct:getItems()
        for i = items:size() - 1, 0, -1 do
            local it = items:get(i)
            if it ~= nil and ids[it:getID()] then
                ct:DoRemoveItem(it)
                if isServer() then sendRemoveItemFromContainer(ct, it) end
                k = k + 1
            end
        end
    end
    H.seeds = {}
    if k > 0 then print("[RST] garden hygiene: " .. k .. " seed(s) of test groups removed") end
    return n
end

-- Item ids of a container: set.
local function idsOf(ct)
    local out = {}
    local items = ct:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it ~= nil then out[it:getID()] = true end
    end
    return out
end

-- Wraps LivingKnox.Garden.dig and LivingKnox.Garden.receiveSeeds once. Returns true when installed by this call.
function H.install()
    if H.installed then return false end
    local Gd = LivingKnox and LivingKnox.Garden
    if Gd == nil or type(Gd.dig) ~= "function" or not authority() then return false end
    H.installed = true
    local dig = Gd.dig
    Gd.dig = function(sq, ...)
        if sq ~= nil and RST.running() then
            H.dug[#H.dug + 1] = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        end
        return dig(sq, ...)
    end
    local receive = Gd.receiveSeeds
    if type(receive) == "function" then
        Gd.receiveSeeds = function(gid, depot, offer, ...)
            local ct = type(depot) == "table" and depot.container or nil
            if ct == nil or not RST.running() then return receive(gid, depot, offer, ...) end
            local before = idsOf(ct)
            local count = receive(gid, depot, offer, ...)
            local items = ct:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it ~= nil and not before[it:getID()] then H.seeds[#H.seeds + 1] = { ct = ct, id = it:getID() } end
            end
            return count
        end
    end
    LivingKnox.listen("groupRemoved", H.LISTENER, function() H.clear() end)
    return true
end

if Events ~= nil then
    local function onStart() H.install() end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onStart) end
    if Events.OnServerStarted ~= nil then Events.OnServerStarted.Add(onStart) end
end

return H
