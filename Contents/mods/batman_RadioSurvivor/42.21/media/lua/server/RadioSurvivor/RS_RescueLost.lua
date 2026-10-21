if isClient() then return end
--[[
Outcome "too late" of a rescue (E12-T05, zombies since E12-T07; "saved" is RS_RescueScene, E12-T04).
Authority only (dedicated server or solo). Design choices: docs/annexes/conception/secours-trop-tard.md.

Survivors: RS_Rescue draws them at the start (rec.survivors = { { outfit, look, requester } }, 2 or 3 distinct vanilla
outfits of RS_Rescue.OUTFITS, the first one is the requester, the voice) and keeps the English descriptions the voice
gives (rec.looks). A record started before E12-T05 gets them drawn here, with the same draw (rescue id and site).

Outcome "missed" (reserves at zero, RS_Rescue.consume): RS_Rescue.finish calls Rescue.sceneHook, wrapped here for the
result "missed" (the "saved" branch stays RS_RescueScene.prepare), on the real record of the rescue:
  - rec.lost = { placing, placed, bodies (count), pages = { name, text } or nil }: the last pages are composed now
    in the language of the authority (IGUI_RS_RescueLast_*, English text when the mod translations cannot be read)
    from the facts of the rescue only: game days waited (reserves consumed), number of survivors, an approach of the
    team without delivery, a delivery that was not enough, signature of the requester. No coordinate, no frequency.
    No document when the sandbox option RadioSurvivor.LastPages is off (Const.lastPages, E15-T04), at the outcome
    or at the placement;
  - life log: RS_LifeLog.rescue(cid, 'missed', label) for each helper bound to a notebook character (helpers exist
    only when a delivery was made), not in a work store.
Placement (Lost.poll every CONFIG.POLL_MS real time, OnTickEvenPaused; an attempt at most every CONFIG.RETRY_MS per
rescue), once the site square itself is loaded (getCell():getGridSquare of the point, never a neighbour chunk) and its
building has passed its vanilla stories (BuildingDef:isFullyStreamedIn, or one of its rooms explored):
  - one ZOMBIE per survivor (E12-T07, decision of 2026-10-14), dressed in the outfit the voice described, on
    distinct free squares of the building around the site point (no stairs, isFree; squares reused when there are
    fewer). Made as a "reanimated player" in ONE Lua call (base zombies-as-npc-bodies.md): addZombiesInOutfit(x, y,
    z, 1, outfit, 50) (dressInPersistentOutfit: the game knows the outfit by its name, getOutfitName), ModData
    RS_RescueBody = "<rescue id>#<index>", DoZombieInventory (worn clothes become items), square:createCorpse(zombie)
    (the corpse copies visual, items and ModData), body:reanimate() (zombie isReanimatedPlayer: never virtualized,
    saved whole with its inventory and ModData in reanimated.bin, its look sent to every client as a shared
    descriptor; the temporary zombie never reaches a client). It is born lying and gets up by itself;
  - the last pages: a vanilla Base.Notebook (RS_LastPages.ITEM) written by addPage (RS_LastPages.layout) then locked
    by setLockedBy (every reader only gets "Read"), custom name, ModData RS_RescuePages = rescue id, in the
    INVENTORY of the requester's zombie (getInventory():AddItem on the authority): DoZombieInventory does nothing for
    a reanimated player at its death, the corpse takes the inventory and goes to the MP clients with it (an item only
    attached would be lost on a server). Requester's zombie missing: in the container of its marked corpse
    (sendAddItemToContainer on a server), else on the floor of the first square.
Once only, even after a restart: rec.lost.placing is saved (store.save) before anything is created; a record found
again with placing but not placed first adopts what carries its marks - zombies of the zombie list (anywhere: they
walk) and corpses of the site bounds at the site floor (killed meanwhile) - with their notebook, and creates only the
missing survivors. Then rec.lost.placed, RS_Rescue.scenePlaced, save.
Lost.onPlaced(rescue id, lost record) is an optional single listener. The voice of the dead survivors is not
changed here. ASCII only in the code (Kahlua lexer).
]]
local Rescue = require "RadioSurvivor/RS_Rescue"
require "RadioSurvivor/RS_RescueScene" -- sets Rescue.sceneHook first (saved branch), wrapped at the end of this file
local LastPages = require "RadioSurvivor/RS_LastPages"
local LifeLog = require "RadioSurvivor/RS_LifeLog"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local S = require "RadioSurvivor/RS_State"

local Lost = {}

Lost.CONFIG = {
    POLL_MS = 2000,
    RETRY_MS = 10000,     -- placement attempts of one rescue
    FEMALE_CHANCE = 50,   -- addZombiesInOutfit: percent of women (every outfit of the list exists for both)
    BODY_MARK = "RS_RescueBody",
    PAGES_MARK = "RS_RescuePages",
}

-- English texts when the translations of the mod cannot be read on this machine.
local ENGLISH = {
    IGUI_RS_RescueLast_Item = "Last pages of %1",
    IGUI_RS_RescueLast_Waited = "We called for help on the radio. We waited %1 days.",
    IGUI_RS_RescueLast_WaitedOne = "We called for help on the radio. We waited a whole day.",
    IGUI_RS_RescueLast_Group = "There were %1 of us in here.",
    IGUI_RS_RescueLast_Approach = "Once we saw someone come close. They did not stay.",
    IGUI_RS_RescueLast_Delivered = "Someone left us food. It kept us going a little longer, but it was not enough.",
    IGUI_RS_RescueLast_End = "The food is gone and we are too weak to leave. If you find this, we waited as long as "
        .. "we could.",
    IGUI_RS_RescueLast_Signer = "the people who waited",
}

local nextPoll = 0
local tried = {}
local reloaded = false

local function log(msg)
    Const.log("rescue: " .. msg)
end

-- Mod translations on this machine (an MP server does not load them: Translator.loadFiles once, base api-42-21.md).
local function hasText()
    return getTextOrNull ~= nil and getTextOrNull("IGUI_RS_RescueLast_Item", "x") ~= nil
end

local function translated()
    if hasText() then return true end
    if not reloaded and isServer() and Translator ~= nil and Translator.loadFiles ~= nil then
        reloaded = true
        Translator.loadFiles()
        log("mod translations reloaded on the server (last pages of a rescue)")
    end
    return hasText()
end

local function tr(key, a)
    local t = nil
    if translated() then
        if a == nil then t = getTextOrNull(key) else t = getTextOrNull(key, a) end -- no nil to the Java overloads
    end
    if t ~= nil then return t end
    return (string.gsub(ENGLISH[key] or key, "%%1", function() return tostring(a or "") end))
end

-- Bench and suites: next poll at once, retries and translations checked again.
function Lost.resetForTests()
    nextPoll, tried, reloaded = 0, {}, false
end

-- ---------------------------------------------------------------- last pages

-- Survivors of a rescue (drawn at the start; drawn now for an older record, same draw).
function Lost.survivors(rec)
    if type(rec.survivors) ~= "table" or #rec.survivors == 0 then
        rec.survivors = Rescue.drawSurvivors(rec)
        rec.looks = Rescue.looks(rec.survivors)
    end
    return rec.survivors
end

-- Last pages left by the survivors: { name, text } in the language of the authority, facts of the rescue only.
function Lost.pages(rec)
    local signer = rec.requester or tr("IGUI_RS_RescueLast_Signer")
    -- Hours waited: reserves consumed, at most the reserves they ever had (the last poll may overshoot zero).
    local hours = math.min(tonumber(rec.consumed) or 0, (tonumber(rec.days) or 0) * 24 + (tonumber(rec.delivered) or 0))
    local days = math.floor((hours + 12) / 24)
    local paras = {}
    paras[#paras + 1] = days > 1 and tr("IGUI_RS_RescueLast_Waited", tostring(days)) or tr("IGUI_RS_RescueLast_WaitedOne")
    paras[#paras + 1] = tr("IGUI_RS_RescueLast_Group", tostring(#Lost.survivors(rec)))
    if (tonumber(rec.approaches) or 0) > 0 and not rec.helped then paras[#paras + 1] = tr("IGUI_RS_RescueLast_Approach") end
    if (tonumber(rec.delivered) or 0) > 0 then paras[#paras + 1] = tr("IGUI_RS_RescueLast_Delivered") end
    paras[#paras + 1] = tr("IGUI_RS_RescueLast_End")
    paras[#paras + 1] = "- " .. signer
    return { name = tr("IGUI_RS_RescueLast_Item", signer), text = table.concat(paras, "\n\n") }
end

-- The notebook of the last pages (vanilla, written then locked), or nil when it cannot be made.
function Lost.document(rec)
    local pages = rec.lost and rec.lost.pages
    if type(pages) ~= "table" or type(pages.text) ~= "string" then return nil end
    local item = instanceItem(LastPages.ITEM)
    if item == nil or not instanceof(item, "Literature") then return nil end
    for i, page in ipairs(LastPages.layout(pages.text)) do item:addPage(i, page) end
    item:setLockedBy(LastPages.LOCK)
    item:setName(pages.name)
    item:setCustomName(true)
    item:getModData()[Lost.CONFIG.PAGES_MARK] = rec.id
    return item
end

-- ---------------------------------------------------------------- outcome

-- Rescue.sceneHook for "missed": prepares the scene on the real record of the rescue (see the header).
function Lost.prepare(rec)
    if type(rec) ~= "table" or type(rec.site) ~= "table" then return false end
    local survivors = Lost.survivors(rec)
    rec.lost = { placing = false, placed = false, bodies = #survivors,
        pages = Const.lastPages() and Lost.pages(rec) or nil }
    if not Rescue.isWorkStore() then
        local label = rec.requester or rec.site.label
        for _, h in ipairs(type(rec.helpers) == "table" and rec.helpers or {}) do
            if h.cid then LifeLog.rescue(h.cid, "missed", label) end
        end
    end
    log(rec.id .. ": too late, " .. #survivors .. " survivor(s) to place"
        .. (rec.lost.pages and " with their last pages" or " (option LastPages off: no pages)"))
    return true
end

-- ---------------------------------------------------------------- placement

-- Building of the site has passed its vanilla stories: fully loaded, or one of its rooms explored.
local function buildingReady(square)
    local building = square:getBuilding()
    local def = building and building:getDef()
    if not def then return true end
    if def:isFullyStreamedIn() then return true end
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        if rooms:get(i):isExplored() then return true end
    end
    return false
end

local function freeSquare(square)
    return square ~= nil and square:isFree(false) and not square:HasStairs()
end

-- Up to n distinct free squares of the site's building around the point (rings up to the bounds), squares of the
-- bounds outside the building after them.
local function squares(cell, rec, centre, n)
    local building = centre:getBuilding()
    local p, b = rec.site, rec.site.bounds
    local z = p.z or 0
    local reach = math.max(p.x - b.x1, b.x2 - 1 - p.x, p.y - b.y1, b.y2 - 1 - p.y, 0)
    local inside, outside = {}, {}
    for ring = 0, reach do
        for dx = -ring, ring do
            for dy = -ring, ring do
                local x, y = p.x + dx, p.y + dy
                if math.max(math.abs(dx), math.abs(dy)) == ring and x >= b.x1 and x < b.x2 and y >= b.y1 and y < b.y2 then
                    local sq = cell:getGridSquare(x, y, z)
                    if freeSquare(sq) then
                        if building == nil or sq:getBuilding() == building then
                            inside[#inside + 1] = sq
                            if #inside >= n then return inside end
                        else
                            outside[#outside + 1] = sq
                        end
                    end
                end
            end
        end
    end
    for _, sq in ipairs(outside) do
        if #inside >= n then break end
        inside[#inside + 1] = sq
    end
    return inside
end

-- Index of the survivor marked on object o for this rescue (ModData RS_RescueBody), or nil.
local function markIndex(o, prefix)
    if not o:hasModData() then return nil end
    local mark = o:getModData()[Lost.CONFIG.BODY_MARK]
    if type(mark) ~= "string" or string.sub(mark, 1, #prefix) ~= prefix then return nil end
    return tonumber(string.sub(mark, #prefix + 1))
end

-- Survivors already in the world for this rescue: index -> { o = zombie or corpse, zombie = bool }. Living zombies of
-- the zombie list first (they walk), then corpses of the site bounds at the site floor (killed meanwhile).
local function markedSurvivors(cell, rec)
    local found = {}
    local prefix = rec.id .. "#"
    local zombies = cell:getZombieList()
    for i = 0, (zombies and zombies:size() or 0) - 1 do
        local zed = zombies:get(i)
        local index = zed ~= nil and not zed:isDead() and markIndex(zed, prefix) or nil
        if index then found[index] = { o = zed, zombie = true } end
    end
    local b, z = rec.site.bounds, rec.site.z or 0
    for x = b.x1, b.x2 - 1 do
        for y = b.y1, b.y2 - 1 do
            local sq = cell:getGridSquare(x, y, z)
            local objects = sq and sq:getStaticMovingObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local o = objects:get(i)
                local index = instanceof(o, "IsoDeadBody") and markIndex(o, prefix) or nil
                if index and found[index] == nil then found[index] = { o = o, zombie = false } end
            end
        end
    end
    return found
end

local function hasPages(container, id)
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        local it = items:get(i)
        if it:hasModData() and it:getModData()[Lost.CONFIG.PAGES_MARK] == id then return true end
    end
    return false
end

-- Zombie of one survivor on a square: a reanimated player in the outfit, marked (see the header). Everything in this
-- one call: a step put off (event, next tick) would send the temporary zombie to the MP clients. Returns the zombie,
-- or nil and a reason; the debris of a failed creation are removed.
local function makeZombie(rec, index, survivor, sq)
    local tmp, body
    local ok, result, why = pcall(function()
        local list = addZombiesInOutfit(sq:getX(), sq:getY(), sq:getZ(), 1, survivor.outfit, Lost.CONFIG.FEMALE_CHANCE)
        if list == nil or list:size() == 0 then return nil, "addZombiesInOutfit made no zombie" end
        tmp = list:get(0)
        tmp:getModData()[Lost.CONFIG.BODY_MARK] = rec.id .. "#" .. index
        tmp:DoZombieInventory()
        body = sq:createCorpse(tmp)
        if body == nil then return nil, "createCorpse made no corpse" end
        tmp = nil
        local zed = body:reanimate()
        if zed == nil then return nil, "reanimate made no zombie" end
        body = nil
        return zed
    end)
    if not ok then why = "engine error: " .. tostring(result) end
    if ok and result ~= nil then return result end
    if tmp ~= nil then pcall(function() tmp:removeFromWorld() tmp:removeFromSquare() end) end
    if body ~= nil then pcall(function() body:getSquare():removeCorpse(body, false) end) end
    return nil, why
end

-- Inventory of a survivor found or made (zombie: its inventory, corpse: its container), or nil.
local function holderOf(entry)
    if entry == nil then return nil end
    if entry.zombie then return entry.o:getInventory() end
    return entry.o:getContainer()
end

local function putPages(rec, entry, sq)
    local item = Lost.document(rec)
    if item == nil then
        log(rec.id .. ": no writable " .. tostring(LastPages.ITEM) .. " here, no last pages")
        return "none"
    end
    local container = holderOf(entry)
    if container ~= nil then
        container:AddItem(item)
        -- A living zombie's inventory is never sent (the clients get it with the corpse); a corpse's container is.
        if not entry.zombie and isServer() then sendAddItemToContainer(container, item) end
        return entry.zombie and "zombie" or "corpse"
    end
    sq:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
    return "floor"
end

-- Deferred placement of one "too late" scene (see the header). saver: RS_State or a double { save }. Returns true
-- when the scene was placed now.
function Lost.place(saver, rec)
    local lost = rec.lost
    if type(lost) ~= "table" or lost.placed then return false end
    local now = getTimestampMs()
    if tried[rec.id] and now - tried[rec.id] < Lost.CONFIG.RETRY_MS then return false end
    local cell = getCell()
    if not cell then return false end
    local z = rec.site.z or 0
    local centre = cell:getGridSquare(rec.site.x, rec.site.y, z)
    if not centre or not buildingReady(centre) then return false end
    tried[rec.id] = now
    local survivors = Lost.survivors(rec)
    local found = lost.placing and markedSurvivors(cell, rec) or {}
    local spots = squares(cell, rec, centre, #survivors)
    if #spots == 0 then
        log(rec.id .. ": no free square for the bodies of the survivors")
        return false
    end
    lost.placing = true
    if not saver.save() then
        log(rec.id .. ": state not saved, bodies not placed")
        return false
    end
    local made, adopted, outfits = 0, 0, {}
    for i, survivor in ipairs(survivors) do
        local entry = found[i]
        if entry ~= nil then
            adopted = adopted + 1
        else
            local zed, why = makeZombie(rec, i, survivor, spots[(i - 1) % #spots + 1])
            if zed ~= nil then
                made = made + 1
                entry = { o = zed, zombie = true }
            else
                log(rec.id .. ": the game made no zombie for survivor " .. i .. ": " .. tostring(why))
            end
        end
        if entry ~= nil then
            outfits[#outfits + 1] = tostring(entry.o:getOutfitName())
            found[i] = entry
        end
    end
    local where = "none"
    if lost.pages ~= nil and Const.lastPages() then
        local first = found[1]
        if first ~= nil and hasPages(holderOf(first), rec.id) then where = "kept"
        else where = putPages(rec, first, spots[1]) end
    end
    lost.placed, lost.placing, lost.outfits = true, false, outfits
    tried[rec.id] = nil
    Rescue.scenePlaced(rec.id)
    saver.save()
    log(rec.id .. ": scene of the lost survivors placed (" .. made .. " zombie(s) made, " .. adopted .. " adopted, "
        .. "outfits " .. table.concat(outfits, ", ") .. ", last pages: " .. where .. ")")
    if Lost.onPlaced then Lost.onPlaced(rec.id, lost) end
    return true
end

local WORK_SAVER = { save = function() return true end }

-- Pending scenes of missed rescues (prepared now when an older record has none). force: ignore the spacing.
-- Returns true when a scene was placed.
function Lost.poll(force)
    local now = getTimestampMs()
    if not force and now < nextPoll then return false end
    nextPoll = now + Lost.CONFIG.POLL_MS
    local d = Rescue.store()
    if not d then return false end
    local ids = {}
    for id, rec in pairs(d.rescues) do
        if rec.scene == "pending" and rec.state == "missed" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local saver = Rescue.isWorkStore() and WORK_SAVER or S
    local changed = false
    for _, id in ipairs(ids) do
        local rec = d.rescues[id]
        if type(rec.lost) ~= "table" then Lost.prepare(rec) end
        if Lost.place(saver, rec) then changed = true end
    end
    return changed
end

RS_RescueLost = Lost
local previousHook = Rescue.sceneHook
Rescue.sceneHook = function(rec, result)
    if result == "missed" then return RS_RescueLost.prepare(rec) end
    if previousHook then return previousHook(rec, result) end
    return false
end
if not RS_RescueLostHooked and Events and Events.OnTickEvenPaused then
    RS_RescueLostHooked = true
    Events.OnTickEvenPaused.Add(function() RS_RescueLost.poll(false) end)
end

return Lost
