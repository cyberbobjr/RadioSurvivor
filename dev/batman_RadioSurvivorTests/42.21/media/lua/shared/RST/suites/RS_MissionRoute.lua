-- Voice mission `route` (E20-T13, ADR D10): three places around the player crossed in order. Real start path of a
-- voice (RS_MissionVoice.start, sheet with one [mission] of type route, points=a,b,c, three places use=target), real
-- set-up of the points (RS_MissionWaypoints), real engine poll (CA_Missions.observe: the template reads the server
-- copy of the player), real radio report (RS_MissionVoice.report).
-- The server copy of the player is moved point by point (IsoMovingObject setX/setY) and read at once by the poll, in
-- the same server call: no update of the client comes in between. It is put back where it was at the end.
-- Steps: B before A refused; A crossed; C before B refused, report refused; B then C crossed; radio report accepted.
-- In-memory state (store whose save does nothing): no notebook state.
require 'RST/RST'
require 'RST/RST_Fixtures'
local F = RST.Fixtures

local KHZ = 199900
local SIDE = 30        -- tiles between two points of the square route around the player

local function run(t)
    if isClient() then t:skip('authority only') end
    local M = require 'CoreAI/CA_Missions'
    local V = require 'RadioSurvivor/RS_MissionVoice'
    local R = require 'CoreAI/CA_MissionRoute'
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local x0, y0, z0 = p:getX(), p:getY(), math.floor(p:getZ())
    t:defer(function() p:setX(x0); p:setY(y0) end, 'put the player back')
    local px, py = math.floor(x0), math.floor(y0)
    local at = {a = {px + SIDE, py}, b = {px + SIDE, py + SIDE}, c = {px, py + SIDE}}
    local places = {}
    for _, id in ipairs({'a', 'b', 'c'}) do
        places[#places + 1] = {id = id, label = 'RST point ' .. id, x = at[id][1], y = at[id][2], z = z0,
            uses = {'target'}, use = {target = true}}
    end
    local sheet = {id = 'rst-voice-route', name = 'RST Voice', actions = {'say', 'start_mission'}, budgets = {},
        missions = {{id = 'route', type = 'route', params = {points = {'a', 'b', 'c'}}}}, places = places}
    local state = {missions = {}, npcs = {}, voiceDonors = {}, characters = {}, outcomes = {}}
    state.characters.char1 = {name = 'Tester', contacts = {}, knownMissions = {}}
    local store = {data = state, save = function() return true end}
    R.resetForTests() -- no previous reading of the player
    local m, why = V.start(store, sheet, 'char1', p, KHZ, 'route')
    t:ok(m ~= nil, 'route mission not created: ' .. tostring(why))
    local function go(id)
        if id then p:setX(at[id][1] + 0.5); p:setY(at[id][2] + 0.5) end
        M.observe(state, {{player = p, character = 'char1'}}, store)
        return m.crossed
    end
    t:eq({'route', 3, 0}, {m.template, #m.points, go(nil)}, 'mission at its start')
    t:eq(0, go('b'), 'B crossed before A')
    t:eq(1, go('a'), 'A not crossed')
    t:eq(1, go('c'), 'C crossed before B')
    t:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, 'report accepted with a point left')
    t:eq(2, go('b'), 'B not crossed after A')
    t:eq(3, go('c'), 'C not crossed after B')
    t:eq(true, M.reportReady(m), 'every point crossed but the objective is not met')
    t:eq(true, V.report(store, sheet, 'char1', p, KHZ) == m, 'radio report refused after every point')
    t:eq('success', m.state)
end

RST.suite("rs.voiceroute", {tags = {"server", "world"}, testTimeoutMs = 60000}, function(s)
    s.test('three places around the player crossed in order by the server copy, skipped points refused, then the '
        .. 'report', run)
end)
