if isClient() then return end
--[[
Delivery on site and approach of a rescue (E12-T03). Authority only (dedicated server or solo). Reads squares and
inventories, which RS_Rescue.lua never does (its choice of building must load nothing). Design choices:
docs/annexes/conception/secours-livraison.md.

Poll (Visit.CONFIG.POLL_MS real time, OnTickEvenPaused): every connected player (getOnlinePlayers on a server, local
players in solo), alive, whose team (RS_Factions.idOf, faction or lone player) has an active rescue
(RS_Rescue.activeFor) and who stands within CONFIG.APPROACH tiles of the building bounds (RS_Rescue.gap, exclusive
ends) is "near" that rescue.

Real deposit only: a near member standing OUTSIDE the building bounds has the ids of the food, clean water and
medical items of his inventory remembered (bags included, CONFIG.DEPTH levels; memory only, per team, at most
CONFIG.MAX_CARRIED ids). A near member standing INSIDE the bounds makes the server search the containers of the
objects (IsoObject:getContainerCount / getContainerByIndex, bags inside them included) of the loaded squares of the
building within CONFIG.SCAN_RADIUS tiles around him, on his floor. An item counts when its id was remembered (it
came in from outside in a member's inventory: item ids are kept by MP transfers) and it is usable as is (food neither
rotten, frozen nor dangerous raw; non empty clean water; medical). Building loot never seen in a member's inventory
outside never counts, nor an item on the floor or in a vehicle. Each counted item is taken by the survivors
(DoRemoveItem + sendRemoveItemFromContainer) and adds Visit.HOURS[category] game hours of reserves
(RS_Rescue.addReserves, capped by RS_Rescue.RUN.MAX_RESERVE_DAYS).

Approach: when a member is near and none was near at the previous poll, at most once per CONFIG.COOLDOWN_HOURS game
hours per rescue (last approach kept in the rescue by RS_Rescue.noteApproach, saved): a smoke of CONFIG.SMOKE_COLOR
is lit with the required mod Signal Smoke (require 'SignalSmoke/SignalSmoke', start and COLORS; a module without them
is a broken install, logged as an error) for CONFIG.SMOKE_MINUTES game minutes outside the building, on the side of
the closest member (SignalSmoke.start, id "rs:rescue:<id>", source "script": no player, so the signal missions ignore
it), and the voice says so; when start fails (logged) the voice describes what it sees instead: the side where the
members stand (direction words of the clues), one or several people, a vehicle. The line is composed here in the
language of the authority (translations IGUI_RS_RescueSee*, IGUI_RS_RescueSmoke_<colour>, IGUI_RS_Dir_<code>;
English text when the mod translations cannot be read) and aired on the first served frequency of the rescue voice (rec.voice,
RS_RadioServer.frequency / air) when it has one. Visit.onApproach(rescue, info, text) and Visit.onDelivery(id, hours,
counts) are optional single listeners.

Outcome "saved" (E12-T04, docs/annexes/conception/secours-issue.md): once a real delivery was counted, the near members of
the team (at that poll and at every later poll while they stay near) are noted as helpers in the rescue
(RS_Rescue.noteHelpers: character name, radio caller key = account name on a server or "solo", notebook character
of RS_RadioLog.characterOf or nil). At the first poll where no living connected member of the team is near the
building any more, the survivors leave: RS_Rescue.finish(id, "saved") (helpers as participants); the scene (cache,
note, new place of the voice, memory) is prepared by RS_RescueScene. A visit without a real delivery saves nobody.
]]
local Rescue = require "RadioSurvivor/RS_Rescue"
local Factions = require "RadioSurvivor/RS_Factions"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local RadioLog = require "RadioSurvivor/RS_RadioLog"

local Visit = {}

Visit.CONFIG = {
    APPROACH = 40,        -- tiles between the building bounds and a team member
    SCAN_RADIUS = 8,      -- tiles searched around a member inside the building (his floor)
    POLL_MS = 1000,
    COOLDOWN_HOURS = 12,  -- game hours between two approaches of the same rescue
    DEPTH = 2,            -- bags inside bags
    MAX_CARRIED = 400,    -- remembered item ids per team
    SMOKE_COLOR = "green",
    SMOKE_MINUTES = 30,
    SMOKE_OFFSET = 2,     -- tiles outside the building bounds
}
-- Game hours of reserves brought by one usable item of each category.
Visit.HOURS = { food = 8, water = 4, medical = 6 }
-- Script DisplayCategory -> category (water is recognised by its fluid, food also by its class).
Visit.DISPLAY = { Food = "food", FirstAid = "medical", Bandage = "medical" }

-- English texts when the translations of the mod cannot be read on this machine.
local ENGLISH = {
    IGUI_RS_RescueSee = "I can see you from the window! You are %1. Come on, quickly!",
    IGUI_RS_RescueSeeGroup = "I can see several of you from the window, %1. Come on, quickly!",
    IGUI_RS_RescueSeeVehicle = "I can see a vehicle out there, %1. Is that you?",
    IGUI_RS_RescueSmoke_green = "I can hear you out there! I am lighting a green smoke outside, follow it.",
    IGUI_RS_RescueSmoke_red = "I can hear you out there! I am lighting a red smoke outside, follow it.",
    IGUI_RS_RescueSmoke_yellow = "I can hear you out there! I am lighting a yellow smoke outside, follow it.",
    IGUI_RS_RescueSmoke_purple = "I can hear you out there! I am lighting a purple smoke outside, follow it.",
}

local carried = {}          -- team -> { ids = { [item id] = true }, n = count }
local near = {}             -- rescue id -> true when a member was near at the previous poll
local nextPoll = 0
local lib = nil             -- Signal Smoke module; false: unusable (broken install)
local translationsReloaded = false

local function log(msg)
    Const.log("rescue: " .. msg)
end

local function worldAge()
    local gt = getGameTime and getGameTime()
    local age = gt and gt:getWorldAgeHours() or nil
    if type(age) ~= "number" or age ~= age then return nil end
    return age
end

local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers and getOnlinePlayers()
        for i = 0, (list and list:size() or 0) - 1 do out[#out + 1] = list:get(i) end
    elseif getNumActivePlayers and getSpecificPlayer then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

-- Bench and suites: forget the remembered items, the near flags and the Signal Smoke module.
function Visit.resetForTests()
    carried, near, nextPoll, lib = {}, {}, 0, nil
end

-- ---------------------------------------------------------------- items

local function waterOf(item)
    local fc = item:getFluidContainer()
    if fc == nil or fc:isEmpty() then return nil end
    return Fluid ~= nil and fc:getPrimaryFluid() == Fluid.Water
end

-- Category of an inventory item ("food", "water", "medical") or nil.
function Visit.categoryOf(item)
    if item == nil then return nil end
    local water = waterOf(item)
    if water then return "water" end
    if water == false then return nil end -- another fluid (petrol, bleach, tainted water...)
    if instanceof(item, "Food") then return "food" end
    return Visit.DISPLAY[item:getDisplayCategory() or ""]
end

-- Category of an item usable as is (Food.isRotten, isFrozen, isbDangerousUncooked, InventoryItem.isCooked), or nil.
function Visit.usable(item)
    local cat = Visit.categoryOf(item)
    if cat == "food" and instanceof(item, "Food") then
        if item:isRotten() or item:isFrozen() then return nil end
        if item:isbDangerousUncooked() and not item:isCooked() then return nil end
    end
    return cat
end

local function walk(container, depth, fn)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        fn(it, container)
        if depth < Visit.CONFIG.DEPTH and instanceof(it, "InventoryContainer") then
            walk(it:getInventory(), depth + 1, fn)
        end
    end
end

-- Remembers the supply items carried by a member of team (outside the building). Returns the number of new ids.
function Visit.remember(team, player)
    local set = carried[team]
    if not set then
        set = { ids = {}, n = 0 }
        carried[team] = set
    end
    local added = 0
    walk(player:getInventory(), 0, function(it)
        if Visit.categoryOf(it) then
            local id = it:getID()
            if not set.ids[id] then
                if set.n >= Visit.CONFIG.MAX_CARRIED then
                    set.ids, set.n = {}, 0
                end
                set.ids[id], set.n = true, set.n + 1
                added = added + 1
            end
        end
    end)
    return added
end

function Visit.isCarried(team, id)
    local set = carried[team]
    return set ~= nil and set.ids[id] == true
end

-- ---------------------------------------------------------------- deposit

local function inside(b, x, y)
    return x >= b.x1 and x < b.x2 and y >= b.y1 and y < b.y2
end

-- Distance in tiles from the building bounds to the player (0 inside or touching).
function Visit.distance(rec, player)
    local fx, fy = math.floor(player:getX()), math.floor(player:getY())
    return Rescue.gap(rec.site.bounds, { x1 = fx, y1 = fy, x2 = fx + 1, y2 = fy + 1 })
end

-- Counted deposits around the members inside the building: list of { id, item, container, cat } (each item once).
function Visit.findDeposits(rec, team, list, cell)
    local out, seen = {}, {}
    local set = carried[team]
    if not set or set.n == 0 or not cell then return out end
    local b, r = rec.site.bounds, Visit.CONFIG.SCAN_RADIUS
    local function take(it, container)
        local id = it:getID()
        if set.ids[id] and not seen[id] then
            local cat = Visit.usable(it)
            if cat then
                seen[id] = true
                out[#out + 1] = { id = id, item = it, container = container, cat = cat }
            end
        end
    end
    for _, p in ipairs(list) do
        local px, py, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        for x = math.max(b.x1, px - r), math.min(b.x2 - 1, px + r) do
            for y = math.max(b.y1, py - r), math.min(b.y2 - 1, py + r) do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local o = objects:get(i)
                        for k = 0, o:getContainerCount() - 1 do
                            walk(o:getContainerByIndex(k), 0, take)
                        end
                    end
                end
            end
        end
    end
    return out
end

local function takeOut(container, item)
    return pcall(function()
        container:DoRemoveItem(item)
        sendRemoveItemFromContainer(container, item)
    end)
end

-- Takes the counted deposits and raises the reserves. Returns the hours added.
function Visit.collect(rec, team, list)
    local found = Visit.findDeposits(rec, team, list, getCell and getCell() or nil)
    local hours, counts = 0, {}
    local set = carried[team]
    for _, f in ipairs(found) do
        if takeOut(f.container, f.item) then
            hours = hours + (Visit.HOURS[f.cat] or 0)
            counts[f.cat] = (counts[f.cat] or 0) + 1
            set.ids[f.id] = nil
        else
            log("an item left for " .. rec.id .. " could not be taken out of its container")
        end
    end
    if hours <= 0 then return 0 end
    local reserves = Rescue.addReserves(rec.id, hours)
    log(rec.id .. ": delivery of " .. (counts.food or 0) .. " food, " .. (counts.water or 0) .. " water, "
        .. (counts.medical or 0) .. " medical item(s), +" .. hours .. " h, reserves " .. tostring(reserves))
    if Visit.onDelivery then Visit.onDelivery(rec.id, hours, counts) end
    return hours
end

-- ---------------------------------------------------------------- approach

-- Signal Smoke public module (required mod), or nil when it is unusable (broken install: error logged). Checked once.
function Visit.library()
    if lib == nil then
        local mod = require "SignalSmoke/SignalSmoke"
        if type(mod) == "table" and type(mod.start) == "function" and type(mod.COLORS) == "table" then
            lib = mod
        else
            lib = false
            log("ERROR required mod batman_SignalSmoke is broken: module SignalSmoke/SignalSmoke "
                .. "has no start or COLORS")
        end
    end
    return lib or nil
end

-- Members near the building, the closest first.
local function sorted(rec, list)
    local out = {}
    for _, p in ipairs(list) do out[#out + 1] = { p = p, d = Visit.distance(rec, p) } end
    table.sort(out, function(a, b) return a.d < b.d end)
    local players2 = {}
    for i, e in ipairs(out) do players2[i] = e.p end
    return players2
end

-- What the voice sees: { dir = code, count, vehicle }.
function Visit.describe(rec, list)
    local b = rec.site.bounds
    local cx, cy = (b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2
    local first = list[1]
    local dir = Rescue.direction(cx, cy, first:getX(), first:getY())
    local vehicle = false
    for _, p in ipairs(list) do
        if p:getVehicle() ~= nil then vehicle = true end
    end
    return { dir = (string.gsub(dir, "-", "_")), count = #list, vehicle = vehicle }
end

-- Smoke point: outside the bounds, on the side of the player (south side when he is inside).
function Visit.smokePoint(rec, player)
    local b, off = rec.site.bounds, Visit.CONFIG.SMOKE_OFFSET
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local function axis(v, lo, hi)
        if v < lo then return lo - off end
        if v >= hi then return hi - 1 + off end
        return v
    end
    local x, y = axis(px, b.x1, b.x2), axis(py, b.y1, b.y2)
    if inside(b, x, y) then y = b.y2 - 1 + off end
    return x, y
end

-- Lights the smoke; returns the colour name, or nil.
function Visit.lightSmoke(mod, rec, player)
    local color = Visit.CONFIG.SMOKE_COLOR
    if type(mod.COLORS[color]) ~= "table" then return nil end
    local x, y = Visit.smokePoint(rec, player)
    local ok, id, err = pcall(mod.start, { x = x, y = y, z = 0, color = color, minutes = Visit.CONFIG.SMOKE_MINUTES,
        id = "rs:rescue:" .. rec.id, owner = "RadioSurvivor" })
    if not ok or not id then
        log(rec.id .. ": Signal Smoke refused the smoke (" .. tostring(ok and err or id) .. ")")
        return nil
    end
    return color
end

-- Translated text of the authority (mod translations reloaded once on an MP server), else the English text.
local function tr(key, arg)
    local function get(k, a)
        if not getTextOrNull then return nil end
        if a == nil then return getTextOrNull(k) end -- no nil argument to the Java overloads
        return getTextOrNull(k, a)
    end
    if get(key, arg) == nil and isServer() and not translationsReloaded and Translator and Translator.loadFiles then
        translationsReloaded = true
        Translator.loadFiles()
        log("mod translations reloaded on the server (" .. key .. " was missing)")
    end
    local text = get(key, arg)
    if text == nil and ENGLISH[key] then
        text = arg and (string.gsub(ENGLISH[key], "%%1", (string.gsub(arg, "%%", "%%%%")))) or ENGLISH[key]
    end
    return text
end

-- Line of the voice for an approach info.
function Visit.line(info)
    if info.smoke then return tr("IGUI_RS_RescueSmoke_" .. info.smoke) end
    local where = getTextOrNull and getTextOrNull("IGUI_RS_Dir_" .. info.dir) or nil
    where = where or ("to the " .. string.gsub(info.dir, "_", "-"))
    if info.vehicle then return tr("IGUI_RS_RescueSeeVehicle", where) end
    if info.count > 1 then return tr("IGUI_RS_RescueSeeGroup", where) end
    return tr("IGUI_RS_RescueSee", where)
end

-- Airs the line on the voice of the rescue; true when queued.
function Visit.air(rec, text)
    local radio = RS_RadioServer
    if type(text) ~= "string" or text == "" or type(rec.voice) ~= "string" or type(radio) ~= "table" then return false end
    local khz = radio.frequency and radio.frequency(rec.voice)
    if not khz then return false end
    radio.air(khz, { "<fzzt>", text, "<szzt>" })
    return true
end

-- Approach of the members in list (closest first after sorting). Returns true when the voice reacted.
function Visit.approach(rec, list)
    if #list == 0 then return false end
    local age = worldAge()
    local last = rec.approach and rec.approach.at
    if last and age and age >= last and age - last < Visit.CONFIG.COOLDOWN_HOURS then return false end
    list = sorted(rec, list)
    local info = Visit.describe(rec, list)
    info.at = age
    local mod = Visit.library()
    if mod then info.smoke = Visit.lightSmoke(mod, rec, list[1]) end
    local text = Visit.line(info)
    info.aired = Visit.air(rec, text)
    Rescue.noteApproach(rec.id, info)
    log(rec.id .. ": approach of " .. info.count .. " member(s) from the " .. info.dir
        .. (info.smoke and (", " .. info.smoke .. " smoke") or ", description")
        .. (info.aired and ", aired" or ", no voice frequency"))
    if Visit.onApproach then Visit.onApproach(rec, info, text) end
    return true
end

-- ---------------------------------------------------------------- poll

-- Near members by rescue: { [id] = { rec, team, near = { players }, inside = { players } } }.
function Visit.gather()
    local out = {}
    for _, p in ipairs(players()) do
        if not p:isDead() then
            local team = Factions.idOf(p)
            local rec = team and Rescue.activeFor(team)
            if rec and Visit.distance(rec, p) <= Visit.CONFIG.APPROACH then
                local e = out[rec.id]
                if not e then
                    e = { rec = rec, team = team, near = {}, inside = {} }
                    out[rec.id] = e
                end
                e.near[#e.near + 1] = p
                if inside(rec.site.bounds, math.floor(p:getX()), math.floor(p:getY())) then
                    e.inside[#e.inside + 1] = p
                else
                    Visit.remember(team, p)
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------- outcome "saved" (E12-T04)

-- Helper record of a member: { name, caller, cid } (see the header).
function Visit.helper(player)
    local desc = player:getDescriptor()
    local name = desc and (desc:getForename() .. " " .. desc:getSurname()) or nil
    local caller = isServer() and player:getUsername() or "solo"
    local cid = RadioLog.characterOf(player)
    return { name = name, caller = caller, cid = cid }
end

function Visit.helpers(list)
    local out = {}
    for _, p in ipairs(list) do out[#out + 1] = Visit.helper(p) end
    return out
end

-- The survivors leave once the helpers are gone: outcome "saved". Returns true when closed.
function Visit.leave(id)
    local out = Rescue.finish(id, "saved")
    if not out then return false end
    log(id .. ": the helpers left, the survivors leave too (saved, "
        .. (type(out.helpers) == "table" and #out.helpers or 0) .. " helper(s))")
    return true
end

-- One poll (force: ignore the spacing). Returns true when a rescue changed (approach, delivery or outcome).
function Visit.poll(force)
    local now = getTimestampMs()
    if not force and now < nextPoll then return false end
    nextPoll = now + Visit.CONFIG.POLL_MS
    local groups = Visit.gather()
    local ids = {}
    for id in pairs(groups) do ids[#ids + 1] = id end
    table.sort(ids)
    local changed, seen = false, {}
    for _, id in ipairs(ids) do
        local e = groups[id]
        seen[id] = true
        if not near[id] and Visit.approach(e.rec, e.near) then changed = true end
        local delivered = #e.inside > 0 and Visit.collect(e.rec, e.team, e.inside) > 0
        if delivered then changed = true end
        if (delivered or e.rec.helped) and (Rescue.noteHelpers(id, Visit.helpers(e.near)) or 0) > 0 then
            changed = true
        end
    end
    near = seen
    for _, id in ipairs(Rescue.helpedActive()) do
        if not seen[id] and Visit.leave(id) then changed = true end
    end
    return changed
end

RS_RescueVisit = Visit
if not RS_RescueVisitHooked and Events and Events.OnTickEvenPaused then
    RS_RescueVisitHooked = true
    Events.OnTickEvenPaused.Add(function() RS_RescueVisit.poll(false) end)
end

return Visit
