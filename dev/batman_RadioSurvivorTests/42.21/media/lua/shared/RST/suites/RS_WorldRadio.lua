--[[
rs.worldradio - a sentence sent from a placed radio or a car radio is judged by the authority (E06-T03,
server/RadioSurvivor_Server.lua: findRadio, Const.inMicRange, Const.inVehicle). The clients send the REAL radio command
"talk" (RST.Steps "rs.talk", RST_PeerChecksRadio.lua): the requester client, and in MP the second client too.
    placed radio  a two-way radio without sprite (IsoRadio, as the 3D placement of an inventory radio adds one) is
                  placed 1 square from the requester and another one FAR_DX squares away, both on, tuned to a
                  frequency where no voice listens (silence path: nothing reaches the bridge). The requester is
                  accepted at the near radio and refused "TooFar" at the far one; every other client gets what the
                  server's own range rule gives for its position (noted); the near radio turned off gives "Off".
    car radio     a car (Base.CarNormal) is spawned on a free outdoor square near the requester, its radio part made a
                  HAM transmitter (item Base.HamRadio1 installed, then Vehicles.Create.Radio_HAM), on, tuned to a free
                  frequency; the requester client enters the passenger seat (RST.Steps "rs.vehicle": BaseVehicle:enter
                  as ISEnterVehicle does, VehicleEnter packet in MP) and is accepted; a client outside the car is
                  refused "NotInVehicle" (MP; nobody else in solo).
Tags "server" and "world": the authority (solo, or RST.server from an admin client of a dedicated server), on a save
rstest*. MP: autoclient.py --mp --clients 2 --server-suite rs.worldradio --server-tags world.
Cleanup: radios removed (transmitRemoveItemFromSquare), the requester leaves the car, the car is removed
(permanentlyRemove), the history lines of the test sentences are removed from the notebook state.
Outside the game: tests/test_rs_mp_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_PeerChecksRadio"

local PR = RST.PeerRadio
local Steps = RST.Steps
local MARK = "RST worldradio "
local MIC = 5
local FAR_DX = { 10, 9, 11, 8, 12 }
local CAR = "Base.CarNormal"
local SEAT = 1

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the radio checks live on the authority (solo or dedicated server), not on an MP client")
    end
    local okC, Const = pcall(require, "RadioSurvivor/RadioSurvivor_Const")
    t:ok(okC and type(Const) == "table" and type(Const.SOURCE) == "table", "RadioSurvivor_Const (E06-T03) not loaded")
    local okP, Personas = pcall(require, "RadioSurvivor/RS_Personas")
    t:ok(okP and type(Personas) == "table", "RadioSurvivor/RS_Personas not loaded on this side")
    t:ok(type(RS_RadioServer) == "table", "RadioSurvivor_Server.lua (talk command) not loaded on this side")
    if not Const.isEnabled() then t:skip("sandbox option RadioSurvivor.Enabled is off") end
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    t:defer(function() PR.stripHistory(MARK) end, "test sentences removed from the radio histories")
    return { Const = Const, P = Personas, p = p }
end

-- First frequency of [low, high] where no voice listens (no channel of RS_Personas), other than except.
local function freeKhz(P, low, high, except)
    local start = math.max(low or 200, 90000)
    local k = start - (start % 200) + 200
    while k <= (high or 1000000) do
        if k ~= except and P.voiceAt(k) == nil and P.channel(k) == nil then return k end
        k = k + 200
    end
    return nil
end

local n = 0
local function sentence()
    n = n + 1
    return MARK .. tostring(ZombRand(1000, 9999)) .. "-" .. n
end

local function square(p, dx, dy)
    return getCell():getGridSquare(math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ()))
end

-- Two-way radio placed on the square (dx, dy) from the player, on, battery full, microphone range MIC.
local function placeRadio(t, p, dx, dy)
    local sq = square(p, dx, dy)
    if sq == nil then t:skip("square at " .. dx .. "," .. dy .. " from the player is not loaded") end
    local radio = IsoRadio.new(getCell(), sq, nil)
    local data = radio:getDeviceData()
    data:setIsTwoWay(true)
    data:setMicRange(MIC)
    data:setIsBatteryPowered(true)
    data:setHasBattery(true)
    data:setPower(1.0)
    data:setTurnedOnRaw(true)
    sq:transmitAddObjectToSquare(radio, -1)
    t:defer(function()
        local at = radio:getSquare()
        if at ~= nil and radio:getObjectIndex() ~= -1 then at:transmitRemoveItemFromSquare(radio) end
    end, "remove the placed radio at " .. sq:getX() .. "," .. sq:getY())
    return radio
end

local function worldArgs(radio, khz, text)
    local sq = radio:getSquare()
    return { text = text, channel = khz, source = "world", x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        index = radio:getObjectIndex() }
end

-- Answer expected from the server rule for a player at its current position: "accepted", "rejected TooFar" or
-- "rejected Off" (order of RadioSurvivor_Server.findRadio: range, then on).
local function expectedAt(Const, player, radio)
    local sq, data = radio:getSquare(), radio:getDeviceData()
    if not Const.inMicRange(player, data, sq:getX(), sq:getY(), sq:getZ()) then return "rejected TooFar" end
    if not data:getIsTurnedOn() then return "rejected Off" end
    return "accepted"
end

local function answerOf(e)
    local d = e and e.data or nil
    if d == nil then return "none" end
    if d.reason ~= nil then return tostring(d.command) .. " " .. tostring(d.reason) end
    return tostring(d.command)
end

local function distance(player, radio)
    local sq = radio:getSquare()
    local dx, dy = math.floor(player:getX()) - sq:getX(), math.floor(player:getY()) - sq:getY()
    return math.floor(math.sqrt(dx * dx + dy * dy))
end

-- Every client sends the talk command for this radio; the requester must get want, the others what the server rule
-- gives at their position. after(t) next.
local function talkAll(t, c, radio, khz, want, label, after)
    Steps.ask(t, "rs.talk", { args = worldArgs(radio, khz, sentence()) }, { target = "all", timeoutMs = PR.TALK_MS },
        function(t2, res)
            for _, e in ipairs(res.list) do
                local player = PR.player(t2, e.user)
                if player == c.p then
                    t2:eq(want, answerOf(e), label .. ": requester")
                elseif player ~= nil then
                    local exp = expectedAt(c.Const, player, radio)
                    t2:eq(exp, answerOf(e), label .. ": client " .. e.user .. " at " .. distance(player, radio)
                        .. " square(s)")
                    t2:note(label .. ": client " .. e.user .. " at " .. distance(player, radio) .. " square(s): " .. exp)
                end
            end
            return after(t2)
        end)
end

local function farRadio(t, p)
    for _, dx in ipairs(FAR_DX) do
        if square(p, dx, 0) ~= nil then return placeRadio(t, p, dx, 0) end
    end
    t:skip("no loaded square " .. FAR_DX[1] .. " squares east of the player")
end

-- Free outdoor square for a car (2 to 10 squares around the player), then the car, or skip.
local function spawnCar(t, p)
    for r = 3, 10 do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local sq = square(p, dx, dy)
                    if sq ~= nil and sq:isOutside() and sq:isFree(false) and sq:getBuilding() == nil then
                        local v = addVehicleDebug(CAR, IsoDirections.E, nil, sq)
                        if v ~= nil and v:getSqlId() ~= -1 then
                            t:defer(function() v:permanentlyRemove() end, "remove the test car " .. tostring(v:getId()))
                            return v
                        end
                    end
                end
            end
        end
    end
    t:skip("no free outdoor square for a car within 10 squares of the player")
end

RST.suite("rs.worldradio", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 240000 }, function(s)
    s.test("placed radio: accepted in microphone range, refused out of range or off (E06-T03)", function(t)
        local c = authority(t)
        local near = placeRadio(t, c.p, 1, 0)
        local far = farRadio(t, c.p)
        local khz = freeKhz(c.P, 200, 1000000)
        t:ok(khz ~= nil, "no free frequency")
        near:getDeviceData():setChannelRaw(khz)
        far:getDeviceData():setChannelRaw(khz)
        t:note("radios on " .. khz .. " kHz at 1 and " .. distance(c.p, far) .. " square(s) from the requester")
        talkAll(t, c, near, khz, "accepted", "near radio", function(t2)
            talkAll(t2, c, far, khz, "rejected TooFar", "far radio", function(t3)
                near:getDeviceData():setTurnedOnRaw(false)
                talkAll(t3, c, near, khz, "rejected Off", "near radio off", function() end)
            end)
        end)
    end)

    s.test("car radio: a seated passenger transmits, a player outside is refused (E06-T03)", function(t)
        local c = authority(t)
        local v = spawnCar(t, c.p)
        local part = v:getPartById("Radio")
        if part == nil then t:skip(CAR .. " has no radio part") end
        if Vehicles ~= nil and Vehicles.Create ~= nil and Vehicles.Create.Radio_HAM ~= nil then
            -- Vehicles.Create.Radio_HAM copies the device data of the part's item and creates a HAM item only when
            -- the part has none (VehicleUtils.createPartInventoryItem_HAMRadio, from the part's itemType list): the
            -- radio part of a car spawned with its parts already holds a car radio (Base.RadioBlack/RadioRed, not two
            -- way). Install the vanilla car HAM item first (Base.HamRadio1, the itemType of template_radio_HAM).
            local ham = instanceItem("Base.HamRadio1")
            t:ok(ham ~= nil, "Base.HamRadio1 could not be created")
            part:setInventoryItem(ham)
            Vehicles.Create.Radio_HAM(v, part)
        end
        local data = part:getDeviceData()
        t:ok(data ~= nil and data:getIsTwoWay(), "the car radio is not a HAM transmitter (Vehicles.Create.Radio_HAM)")
        local khz = freeKhz(c.P, data:getMinChannelRange(), data:getMaxChannelRange())
        t:ok(khz ~= nil, "no free frequency for the car radio")
        -- Powered by a battery of its own: the car battery may be flat, and DeviceData.update turns off a device
        -- that cannot be powered (DeviceData.java:789-796).
        data:setIsBatteryPowered(true)
        data:setHasBattery(true)
        data:setPower(1.0)
        data:setTurnedOnRaw(true)
        data:setChannelRaw(khz)
        local vid = v:getId()
        Steps.ask(t, "rs.vehicle", { op = "enter", vehicleId = vid, seat = SEAT },
            { target = "requester", timeoutMs = PR.VEHICLE_MS }, function(t2)
            t2:defer(function(tc)
                if c.p:getVehicle() == v then
                    Steps.ask(tc, "rs.vehicle", { op = "exit", vehicleId = vid },
                        { target = "requester", timeoutMs = PR.VEHICLE_MS })
                end
            end, "requester out of the test car")
            t2:waitUntil(function() return c.p:getVehicle() == v end, PR.VEHICLE_MS, function(t3)
                t3:note("requester on seat " .. tostring(v:getSeat(c.p)) .. " of car " .. tostring(vid) .. ", radio "
                    .. khz .. " kHz")
                local args = { text = sentence(), channel = khz, source = "vehicle", vehicleId = vid, part = "Radio" }
                Steps.ask(t3, "rs.talk", { args = args }, { target = "all", timeoutMs = PR.TALK_MS }, function(t4, res)
                    for _, e in ipairs(res.list) do
                        local player = PR.player(t4, e.user)
                        if player == c.p then
                            t4:eq("accepted", answerOf(e), "passenger of the car")
                        elseif player ~= nil then
                            local inside = c.Const.inVehicle(player, v)
                            t4:eq(inside and "accepted" or "rejected NotInVehicle", answerOf(e),
                                "client " .. e.user .. (inside and " inside" or " outside") .. " the car")
                        end
                    end
                end)
            end, "the server never saw the requester in the car (VehicleEnter)")
        end)
    end)
end)
