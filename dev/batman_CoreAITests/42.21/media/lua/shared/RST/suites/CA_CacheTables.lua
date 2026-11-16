--[[
ca.caches - reward tables of the caches of the core mod (E11-T06, E20-T04; CA_MissionConfig.Caches, read by
CA_Caches): every item of every closed table is a real item script of the game. E21-T11: split from rs.missionrewards
(the rewards drawn by the radio voices stay there, batman_RadioSurvivorTests). Tags "server" and "world": the
authority (solo, or RST.server from an admin client).
]]

require "RST/RST"

RST.suite("ca.caches", { tags = { "server", "world" }, testTimeoutMs = 45000 }, function(s)
    s.test('every closed reward table contains real item scripts', function(t)
        if isClient() then t:skip('authority only') end
        local config = require 'CoreAI/CA_MissionConfig'
        for _, name in ipairs(config.Caches.order) do
            for _, entry in ipairs(config.Caches.tables[name]) do
                t:ok(instanceItem(entry[1]) ~= nil, 'missing reward script: ' .. entry[1])
            end
        end
    end)
end)
