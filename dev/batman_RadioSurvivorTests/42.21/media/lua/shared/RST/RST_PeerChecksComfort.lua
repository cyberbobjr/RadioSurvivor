--[[
RST_PeerChecksComfort - client steps of the social comfort suite rs.comfort (E05-T15, RS_ComfortSuite.lua), asked by
the authority through RST.Steps (E01-T16). Development mod only. Load with: require "RST/RST_PeerChecksComfort"
(shared: the suite requires it, so every machine that loads the suite registers the steps; the handlers read the
local player of THIS machine).

What a client sees of the comfort is read on the client itself:
    gauges   getPlayer():getStats():get(CharacterStat.BOREDOM / UNHAPPINESS): the client copy of the stats, changed
             by the SyncPlayerStats packet of the authority in MP (same object as the authority in solo).
    halo     HaloTextHelper.addTextWithArrow (called by RS_RadioTalk for the command "comfort") is wrapped once, at
             the first "rs.comfort.arm": the wrapper keeps the text and the arrow direction while armed, then calls
             the original with the same arguments and returns its result. The vanilla halo queue itself is private
             (HaloTextHelper.java:19-20); when the class table refuses the wrapper, the step says so (data.watched
             false, data.why) and the suite notes it instead of failing.

Steps (RST.Steps.on; solo: the local player answers in the same Lua state)
    rs.comfort.arm   { boredom?, sadness?, tolerance? }: halo recorder armed and emptied; waits until the gauges of
                     the local player match the baseline (boredom, sadness) within tolerance, or the client deadline.
                     data { boredom, sadness, synced, watched, why }.
    rs.comfort.read  { before = { boredom, sadness }, drop = { boredom, sadness }?, settleMs?, tolerance? }:
                     with drop: waits until both gauges dropped by drop (within tolerance) and every eased gauge
                     showed its halo, or the client deadline; without drop: reads after settleMs. The recorder is
                     disarmed. data { boredom, sadness, droppedBoredom, droppedSadness, haloBoredom, haloSadness,
                     halos (count), texts (first ones, " | "), watched }.
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerComfort = RST.PeerComfort or {}
local PC = RST.PeerComfort
local Steps = RST.Steps

PC.HALO_KEYS = { boredom = "IGUI_HaloNote_Boredom", sadness = "IGUI_HaloNote_Unhappiness" }
PC.TOLERANCE = 0.5
PC.SETTLE_MS = 3000
PC.MAX_HALOS = 20
PC.halos = PC.halos or {}
PC.armed = PC.armed or false

local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps end

-- Gauges of the local player, or nil.
function PC.stats()
    local p = type(getPlayer) == "function" and getPlayer() or nil
    if p == nil then return nil end
    local s = p:getStats()
    if s == nil then return nil end
    return { boredom = s:get(CharacterStat.BOREDOM), sadness = s:get(CharacterStat.UNHAPPINESS) }
end

-- addTextWithArrow(player, text, separator, arrowIsUp, color...) or (player, text, arrowIsUp, color)
-- (HaloTextHelper.java:39-67): the arrow direction is the first boolean after the text.
local function arrowOf(third, fourth)
    if type(third) == "boolean" then return third end
    return fourth == true
end

local function record(text, up)
    if not PC.armed or #PC.halos >= PC.MAX_HALOS then return end
    PC.halos[#PC.halos + 1] = { text = tostring(text), up = up }
end

-- Wraps HaloTextHelper.addTextWithArrow once (idempotent across reloads). true, or false and the reason.
function PC.watchHalo()
    if HaloTextHelper == nil then return false, "HaloTextHelper absent on this side" end
    local current = HaloTextHelper.addTextWithArrow
    if PC.wrapper ~= nil and current == PC.wrapper then return true end
    if type(current) ~= "function" then return false, "HaloTextHelper.addTextWithArrow is not a function" end
    PC.original = current
    PC.wrapper = function(player, text, third, fourth, ...)
        record(text, arrowOf(third, fourth))
        return PC.original(player, text, third, fourth, ...)
    end
    local ok = pcall(function() HaloTextHelper.addTextWithArrow = PC.wrapper end)
    if not ok or HaloTextHelper.addTextWithArrow ~= PC.wrapper then
        return false, "HaloTextHelper.addTextWithArrow cannot be wrapped (class table refused the field)"
    end
    return true
end

-- Was the down-arrow halo of this translation key shown while armed?
function PC.sawHalo(key)
    local text = getText(key)
    for _, h in ipairs(PC.halos) do
        if h.text == text and h.up == false then return true end
    end
    return false
end

local function texts()
    local out = {}
    for i = 1, math.min(#PC.halos, 4) do out[i] = PC.halos[i].text .. (PC.halos[i].up and " (up)" or " (down)") end
    return table.concat(out, " | ")
end

Steps.on("rs.comfort.arm", function(args)
    local watched, why = PC.watchHalo()
    PC.halos = {}
    PC.armed = true
    local eps = tonumber(args.tolerance) or PC.TOLERANCE
    return function(ctx)
        local s = PC.stats()
        if s == nil then
            if ctx.final then return Steps.fail("no local player") end
            return nil
        end
        local synced = (args.boredom == nil or near(s.boredom, args.boredom, eps))
            and (args.sadness == nil or near(s.sadness, args.sadness, eps))
        if synced or ctx.final then
            return Steps.pass(string.format("boredom %.2f, unhappiness %.2f, baseline %s, halo %s", s.boredom, s.sadness,
                synced and "seen" or "NOT seen", watched and "watched" or "not watched"),
                { boredom = s.boredom, sadness = s.sadness, synced = synced, watched = watched == true, why = why })
        end
        return nil
    end
end)

Steps.on("rs.comfort.read", function(args)
    local before = type(args.before) == "table" and args.before or {}
    local drop = type(args.drop) == "table" and args.drop or nil
    local eps = tonumber(args.tolerance) or PC.TOLERANCE
    local settleAt = RST.now() + (tonumber(args.settleMs) or PC.SETTLE_MS)
    local watched = PC.wrapper ~= nil and HaloTextHelper ~= nil and HaloTextHelper.addTextWithArrow == PC.wrapper
    return function(ctx)
        local s = PC.stats()
        if s == nil then
            if ctx.final then return Steps.fail("no local player") end
            return nil
        end
        local data = { boredom = s.boredom, sadness = s.sadness, watched = watched, halos = #PC.halos, texts = texts(),
            droppedBoredom = (tonumber(before.boredom) or s.boredom) - s.boredom,
            droppedSadness = (tonumber(before.sadness) or s.sadness) - s.sadness,
            haloBoredom = PC.sawHalo(PC.HALO_KEYS.boredom), haloSadness = PC.sawHalo(PC.HALO_KEYS.sadness) }
        local done
        if drop then
            local b, d = tonumber(drop.boredom) or 0, tonumber(drop.sadness) or 0
            done = data.droppedBoredom >= b - eps and data.droppedSadness >= d - eps
                and (not watched or ((b <= 0 or data.haloBoredom) and (d <= 0 or data.haloSadness)))
        else
            done = RST.now() >= settleAt
        end
        if done or ctx.final then
            PC.armed = false
            return Steps.pass(string.format("boredom -%.2f, unhappiness -%.2f, %d halo(s)%s", data.droppedBoredom,
                data.droppedSadness, data.halos, data.texts ~= "" and (": " .. data.texts) or ""), data)
        end
        return nil
    end
end)

return PC
