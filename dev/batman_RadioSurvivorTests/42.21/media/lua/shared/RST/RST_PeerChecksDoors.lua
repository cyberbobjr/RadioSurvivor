--[[
RST_PeerChecksDoors - client checks of the door suite lk.doors (LK04-T02), asked by the authority through RST.Steps.
Development mod only. Shared file: the game runs it on the server, on each client and in solo; it only registers step
handlers and, while a door is watched, one OnTick sampler (clients and solo). Load with:
require "RST/RST_PeerChecksDoors".

A door is named by the key of its edge, as LivingKnox.Obstacles and lk.traversal write it: "x,y,z,W" (edge west of the
square x, y: between x - 1 and x) or "x,y,z,N" (edge north of x, y: between y - 1 and y). The door is read on the
square west (north) of the edge: IsoGridSquare:getDoorTo of the neighbour.

Client handlers (RST.Steps.on)
    lk.door.state  { key, open, locked }: polled until the local door has that state (replication delay) or the
                   deadline; data { open, locked } as read here. FAIL with the state read; SKIP when the square of the
                   door is not loaded here.
    lk.door.watch  { key }: arms a watcher of that door: at each tick the open state is read and every change counted
                   (opens, closes). PASS "armed" with the state read. SKIP when the square is not loaded here.
    lk.door.seen   { key, opens, closes, settleMs }: once the watcher counted at least opens and closes, waits
                   settleMs more, then compares: exactly opens openings and closes closings seen here (a second toggle
                   of the authority, or a client that bounced the door, shows as an extra change). The watcher is
                   removed. data { opens, closes }.
Kahlua: no next(), no goto; nothing suspends. Every handler is pcall-protected by RST.Steps.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerChecksDoors = RST.PeerChecksDoors or {}
local PD = RST.PeerChecksDoors
local Steps = RST.Steps

PD.watchers = PD.watchers or {}   -- key -> { key, open, opens, closes }

local function now() return RST.now() end

-- Door of the edge key, or nil and why.
function PD.doorOf(key)
    local x, y, z, kind = string.match(tostring(key), "^(%-?%d+),(%-?%d+),(%-?%d+),([WN])$")
    if x == nil then return nil, "bad door key " .. tostring(key) end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    local cell = getCell()
    local b = cell and cell:getGridSquare(x, y, z)
    local a
    if kind == "W" then a = cell and cell:getGridSquare(x - 1, y, z) else a = cell and cell:getGridSquare(x, y - 1, z) end
    if a == nil or b == nil then return nil, "square of the door " .. key .. " not loaded here" end
    local door = a:getDoorTo(b)
    if door == nil then return nil, "no door on the edge " .. key .. " here" end
    return door
end

local function locked(door)
    return (door:isLocked() or door:isLockedByKey()) and true or false
end

local function opened(door)
    return door:IsOpen() == true
end

function PD.stateText(door)
    return "open " .. tostring(opened(door)) .. ", locked " .. tostring(locked(door))
end

-- ---------------------------------------------------------------- sampler (one per Lua state)

local function sample()
    local any = false
    for _, w in pairs(PD.watchers) do
        any = true
        local door = PD.doorOf(w.key)
        if door ~= nil then
            local o = opened(door)
            if w.open ~= nil and o ~= w.open then
                if o then w.opens = w.opens + 1 else w.closes = w.closes + 1 end
            end
            w.open = o
        end
    end
    if not any and PD._ticking then
        Events.OnTick.Remove(PD._ticking)
        PD._ticking = nil
    end
end

local function onTick() RST.PeerChecksDoors.sample() end
PD.sample = sample

local function attach()
    if PD._ticking or type(Events) ~= "table" or Events.OnTick == nil then return end
    Events.OnTick.Add(onTick)
    PD._ticking = onTick
end

-- ---------------------------------------------------------------- handlers

Steps.on("lk.door.state", function(args)
    if type(args.key) ~= "string" then return Steps.fail("lk.door.state { key, open, locked }") end
    return function(ctx)
        local door, why = PD.doorOf(args.key)
        if door == nil then
            if ctx.final then return Steps.skip(why) end
            return nil
        end
        local o, l = opened(door), locked(door)
        local data = { open = o, locked = l }
        if (args.open == nil or o == args.open) and (args.locked == nil or l == args.locked) then
            return Steps.pass("door " .. args.key .. ": " .. PD.stateText(door), data)
        end
        if ctx.final then
            return Steps.fail("door " .. args.key .. ": " .. PD.stateText(door) .. ", expected open "
                .. tostring(args.open) .. ", locked " .. tostring(args.locked), data)
        end
        return nil
    end
end)

Steps.on("lk.door.watch", function(args)
    if type(args.key) ~= "string" then return Steps.fail("lk.door.watch { key }") end
    local door, why = PD.doorOf(args.key)
    if door == nil then return Steps.skip(why) end
    PD.watchers[args.key] = { key = args.key, open = opened(door), opens = 0, closes = 0 }
    attach()
    return Steps.pass("armed: " .. PD.stateText(door))
end)

Steps.on("lk.door.seen", function(args)
    local w = type(args.key) == "string" and PD.watchers[args.key] or nil
    if w == nil then return Steps.skip("door " .. tostring(args.key) .. " not watched here") end
    local opens, closes = tonumber(args.opens) or 0, tonumber(args.closes) or 0
    local settle = tonumber(args.settleMs) or 2000
    local reached
    return function(ctx)
        if reached == nil and w.opens >= opens and w.closes >= closes then reached = now() end
        if reached ~= nil and now() - reached < settle and not ctx.final then return nil end
        if reached == nil and not ctx.final then return nil end
        PD.watchers[args.key] = nil
        local data = { opens = w.opens, closes = w.closes }
        local text = "door " .. args.key .. ": " .. w.opens .. " opening(s), " .. w.closes .. " closing(s) seen here"
        if w.opens == opens and w.closes == closes then return Steps.pass(text, data) end
        return Steps.fail(text .. ", expected " .. opens .. " and " .. closes, data)
    end
end)

return PD
