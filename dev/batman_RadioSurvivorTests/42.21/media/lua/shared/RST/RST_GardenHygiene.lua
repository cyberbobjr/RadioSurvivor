--[[
RST.GardenHygiene - furrows dug by the test groups are removed with their group (test mod only, never published).

Every test group runs the real garden of Living Knox (LK15: LivingKnox.Garden.dig through the dig job), and a furrow
is a farming global object kept in the world after the test. The campaigns of 2026-11-13 showed the next suites
playing in a polluted home: lk.forage watered another thirsty plant than its fixture, lk.upkeep had a place shifted off
a plant and out of the home, lk.garden was skipped ("an empty furrow already waits in the home area").

install() (authority only, once): LivingKnox.Garden.dig is wrapped to note each square dug while an RST run is in
progress (RST.running()); on the "groupRemoved" event of Living Knox (every test removes its groups), the noted furrows
and the plants grown on them are removed (SFarmingSystem:removePlant, as the suites do for their own fixtures). Out
of a run nothing is noted: a save played with the test mod keeps its gardens. Installed at game start (OnGameStart in
solo, OnServerStarted on a dedicated server), once Living Knox is loaded.
]]

require "RST/RST"

local H = RST.GardenHygiene or {}
RST.GardenHygiene = H

H.dug = H.dug or {}
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
    return n
end

-- Wraps LivingKnox.Garden.dig once. Returns true when installed by this call.
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
    LivingKnox.listen("groupRemoved", H.LISTENER, function() H.clear() end)
    return true
end

if Events ~= nil then
    local function onStart() H.install() end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onStart) end
    if Events.OnServerStarted ~= nil then Events.OnServerStarted.Add(onStart) end
end

return H
