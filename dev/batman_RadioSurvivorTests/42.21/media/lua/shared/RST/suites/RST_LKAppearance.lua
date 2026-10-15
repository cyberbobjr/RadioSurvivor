--[[
lk.appearance - Living Knox npc appearance (LK02-T03): human skin, haircut, beard and hair colour from the profile;
clothes worn without holes, blood, dirt or patches; no wound and no attached item; the registry keeps the resolved
profile and a new incarnation looks the same, even when the outfit list changed (LK02-T12: the clothes recorded
on the first body are replayed instead of the outfit variant). Tags "world" and "server": the authority only, on a save named
rstest*, with a target player (t.ctx.player); the Living Knox option Enabled must be on.
Solo: RST.run({ suite = "lk.appearance", tags = "world" }); dedicated server: RST.server({ suite = "lk.appearance",
tags = "world" }) from an admin client. The checks read the authority's objects (the source of the shared
descriptor sent to MP clients); E01-T16: the first test also asks the other clients (MP campaign) for the signature
of their local copy of each body (skin, hair, beard, colour, clothes keys: RST.PeerChecks.checkLooks).
Every test forgets its npcs with t:defer, even when it fails. "[LKA] measure ..." lines are printed for the report.
Restart test (LK02-T12, two runs on the same save): the launcher runs the suite a first time with the usual mods
(phase 1 records the npc and writes Lua/batman_RadioSurvivor/tests/lk-appearance-restart.txt), then restarts the game
(and in MP the dedicated server and both clients) on the SAME save and Lua folder with the clothes mod of the
development folder added (dev/batman_RadioSurvivorTestClothes, id batman_RadioSurvivorTestClothes: two clothing items
of their own module), and runs the suite again: phase 2 embodies the same npc and compares its clothes.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

-- Profiles under test: a bearded man, a woman, two skin tones of each sex.
local LOOKS = { "manFairBeard", "womanFairBun", "manDarkGoatee", "womanDarkPonytail" }

local function B() return LivingKnox and LivingKnox.Bodies end
local function A() return LivingKnox and LivingKnox.Appearance end
local function R() return LivingKnox and LivingKnox.Store and LivingKnox.Store.data() end

-- dx: distinct offsets 2 apart, so that no new body lies next to another one (Bodies.findFreeSquare would move it).
local function spawnLook(t, look, dx)
    t:ok(B() ~= nil and A() ~= nil, "LivingKnox.Bodies / Appearance not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + 2, math.floor(p:getZ())
    local id, body = B().spawn({ look = look }, x, y, z)
    if id then t:defer(function() B().despawn(id, true) end, "forget " .. id) end
    t:ok(id ~= nil, "spawn " .. look .. " refused: " .. tostring(body))
    return id, body
end

-- Holes, blood, dirt and patches of the clothes; dirt of the body (RST_LKHelpers.lua).
local clothesDamage = RST.LKHelpers.clothesDamage
local bodyDirt = RST.LKHelpers.bodyDirt

-- Skin, hair, beard and hair colour of a body.
local function bodyLook(body)
    local hv = body:getHumanVisual()
    local c = hv:getHairColor()
    return table.concat({ hv:getSkinTexture(), tostring(hv:getHairModel()), tostring(hv:getBeardModel()),
        c:getRedInt() .. "," .. c:getGreenInt() .. "," .. c:getBlueInt() }, " ")
end

-- Clothes keys of a body (type, clothing item, tint bytes, hue, textures and decal, LivingKnox.Appearance.describe),
-- sorted: the order of the visuals follows the body locations, which a mod may reorder without changing a garment.
local function clothesKeys(body)
    local keys = A().clothesKeys(A().describe(body))
    table.sort(keys)
    return keys
end

-- Comparable description of what is drawn: body look and sorted clothes keys.
local function signature(body)
    return bodyLook(body) .. " " .. table.concat(clothesKeys(body), ";")
end

-- ---------------------------------------------------------------- record across a restart (LK02-T12)

local RECORD = (RST.FILE_DIR or "batman_RadioSurvivor/tests/") .. "lk-appearance-restart.txt"

-- Active mod ids, sorted.
local function modList()
    local out = {}
    local mods = getActivatedMods and getActivatedMods() or nil
    for i = 0, (mods and mods:size() or 0) - 1 do out[#out + 1] = tostring(mods:get(i)) end
    table.sort(out)
    return out
end

-- Items of list a missing from list b.
local function diff(a, b)
    local set, out = {}, {}
    for _, v in ipairs(b or {}) do set[v] = true end
    for _, v in ipairs(a or {}) do
        if not set[v] then out[#out + 1] = v end
    end
    return out
end

-- Record of run 1: lines "save=", "npc=", "body=" (bodyLook), one "item=" per recorded clothes entry
-- (Appearance.entryKey) and one "mod=" per active mod. Returns { save, npc, body, items, mods }, or nil and why.
local function readRecord()
    local reader = getFileReader(RECORD, false)
    if reader == nil then return nil, "no record file " .. RECORD end
    local rec = { mods = {}, items = {} }
    local line = reader:readLine()
    while line do
        local k, v = string.match(line, "^(%w+)=(.*)$")
        if k == "mod" then
            rec.mods[#rec.mods + 1] = v
        elseif k == "item" then
            rec.items[#rec.items + 1] = v
        elseif k ~= nil then
            rec[k] = v
        end
        line = reader:readLine()
    end
    reader:close()
    if rec.npc == nil then return nil, "record file " .. RECORD .. " is empty" end
    if rec.body == nil or #rec.items == 0 then
        return nil, "record file " .. RECORD .. " has an old format (no body= and item= lines)"
    end
    return rec
end

local function writeRecord(t, rec)
    local lines = {}
    for _, k in ipairs({ "save", "npc", "body" }) do
        if rec[k] ~= nil then lines[#lines + 1] = k .. "=" .. tostring(rec[k]) end
    end
    for _, item in ipairs(rec.items or {}) do lines[#lines + 1] = "item=" .. item end
    for _, m in ipairs(rec.mods or {}) do lines[#lines + 1] = "mod=" .. m end
    local ok, why = RST.writeLines(RECORD, lines)
    t:ok(ok, "record not written: " .. tostring(why))
end

-- Prints and notes one report line (notes are never truncated in the report file).
local function measure(t, text)
    print("[LKA] measure " .. text)
    t:note(text)
end

RST.suite("lk.appearance", { tags = { "world", "server" }, testTimeoutMs = 60000, timeoutMs = 300000 }, function(s)
    s.test("each profile gives a human body: skin, haircut, beard and hair colour as in the registry", function(t)
        local bodies = {}
        for i, look in ipairs(LOOKS) do
            local id, body = spawnLook(t, look, 2 * i)
            bodies[#bodies + 1] = body
            local p = R().npcs[id].profile
            t:eq(look, p.look, "registry look")
            t:eq(true, body:isReanimatedPlayer(), look .. " reanimated player")
            local hv = body:getHumanVisual()
            local skin = hv:getSkinTexture()
            t:eq(p.skin, skin, look .. " skin")
            t:ok(string.find(skin, p.female and "^FemaleBody0[1-5]$" or "^MaleBody0[1-5]$") ~= nil,
                look .. ": not a human skin: " .. tostring(skin))
            t:eq(p.hair, hv:getHairModel(), look .. " haircut")
            if p.female then
                t:ok(hv:getBeardModel() == nil or hv:getBeardModel() == "", look .. ": a woman with a beard")
            else
                t:eq(p.beard, hv:getBeardModel(), look .. " beard")
            end
            local c = hv:getHairColor()
            t:eq(p.hairColor.r .. "," .. p.hairColor.g .. "," .. p.hairColor.b,
                c:getRedInt() .. "," .. c:getGreenInt() .. "," .. c:getBlueInt(), look .. " hair colour")
            print("[LKA] measure " .. id .. " " .. look .. " skin=" .. skin .. " hair=" .. tostring(hv:getHairModel())
                .. " beard=" .. tostring(hv:getBeardModel()) .. " colour=" .. c:getRedInt() .. "," .. c:getGreenInt()
                .. "," .. c:getBlueInt() .. " outfit=" .. p.outfit .. "#" .. p.variant)
        end
        -- E01-T16: the other clients draw the same bodies (signature of their local copy, found by online id).
        RST.PeerChecks.checkLooks(t, bodies)
    end)

    s.test("clothes worn without holes, blood, dirt or patches; no wound, no attached item", function(t)
        for i, look in ipairs(LOOKS) do
            local _, body = spawnLook(t, look, 2 * i)
            local n, holes, blood, dirt, patches = clothesDamage(body)
            t:ok(n > 0, look .. ": no clothes")
            t:eq(0, holes, look .. " holes")
            t:eq(0, blood, look .. " blood on clothes")
            t:eq(0, dirt, look .. " dirt on clothes")
            t:eq(0, patches, look .. " patches")
            local hv = body:getHumanVisual()
            t:eq(0, hv:getTotalBlood(), look .. " blood on the body")
            t:eq(0, bodyDirt(hv), look .. " dirt on the body")
            t:eq(0, hv:getBodyVisuals():size(), look .. " wounds and bandages")
            t:eq(0, body:getAttachedItems():size(), look .. " attached items")
            local worn = body:getWornItems()
            t:eq(n, worn:size(), look .. " worn items")
            local damaged = 0
            for j = 0, worn:size() - 1 do
                local item = worn:get(j):getItem()
                if item:getCondition() < item:getConditionMax() then damaged = damaged + 1 end
            end
            t:eq(0, damaged, look .. " worn items below their maximum condition")
            print("[LKA] measure " .. look .. " clothes=" .. n .. " holes=" .. holes .. " blood=" .. blood
                .. " dirt=" .. dirt .. " patches=" .. patches)
        end
    end)

    s.test("a new incarnation keeps the same appearance", function(t)
        local id, body = spawnLook(t, "manOliveChops", 2)
        local before = signature(body)
        local profile = R().npcs[id].profile
        local x, y, z = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
        t:ok(B().despawn(id), "despawn")
        local body2, why = B().embody(id, x, y, z)
        t:ok(body2 ~= nil, "embody: " .. tostring(why))
        t:eq(2, R().npcs[id].generation, "second incarnation")
        t:ok(A().same(profile, R().npcs[id].profile), "registry profile changed")
        local after = signature(body2)
        t:eq(before, after, "appearance of the second incarnation")
        print("[LKA] measure reincarnation same=" .. tostring(before == after) .. " " .. after)
    end)

    -- The outfit list cannot be changed in a running game; the change is simulated by another variant and another
    -- outfit name in the registry profile: replaying the variant would now dress the npc otherwise.
    s.test("a new incarnation keeps the same clothes when the outfit variant would give others", function(t)
        local id, body = spawnLook(t, "womanTanBob", 2)
        local npc = R().npcs[id]
        t:ok(npc.clothes ~= nil, "clothes not recorded on the first body")
        local recorded = A().clothesKey(npc.clothes)
        t:eq(recorded, A().clothesKey(A().describe(body)), "recorded clothes = clothes of the first body")
        local before = signature(body)
        npc.profile.variant = npc.profile.variant % A().VARIANTS + 1
        npc.profile.outfit = npc.profile.outfit == "Generic01" and "Generic02" or "Generic01"
        local x, y, z = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
        t:ok(B().despawn(id), "despawn")
        local body2, why = B().embody(id, x, y, z)
        t:ok(body2 ~= nil, "embody: " .. tostring(why))
        local after = signature(body2)
        t:eq(before, after, "appearance of the second incarnation")
        t:eq(recorded, A().clothesKey(R().npcs[id].clothes), "recorded clothes unchanged")
        local n, holes = clothesDamage(body2)
        t:eq(0, holes, "holes after the replay")
        t:eq(0, body2:getAttachedItems():size(), "attached items after the replay")
        print("[LKA] measure replay same=" .. tostring(before == after) .. " clothes=" .. n .. " " .. recorded)
    end)

    -- LK02-T12 across a restart: run 1 records an npc left virtual (no body) with its appearance and the active mods,
    -- then SKIP with the instruction; the user adds or removes a clothes mod and restarts the game; run 2 embodies the
    -- same npc and compares garment by garment, in any order (the order of the visuals follows the body locations,
    -- which a clothes mod may reorder). The record file is Zomboid/Lua/batman_RadioSurvivor/tests/
    -- lk-appearance-restart.txt: cleared (and the npc forgotten) only when run 2 passes; after a failure the npc goes
    -- back to virtual and the record is kept, so run 2 can be repeated. A missing, empty, old or foreign record makes
    -- run 2 a new run 1, with the reason.
    s.test("an npc embodied again after a restart with another mod list keeps its clothes (two runs)", function(t)
        t:ok(B() ~= nil and A() ~= nil, "LivingKnox.Bodies / Appearance not loaded on this side")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local px, py, pz = math.floor(p:getX()), math.floor(p:getY()) + 2, math.floor(p:getZ())
        local rec, missing = readRecord()
        local save = RST.saveName and RST.saveName() or "?"
        if rec ~= nil and rec.save ~= save then
            rec, missing = nil, "record made on save " .. tostring(rec.save) .. ", not on " .. save
        elseif rec ~= nil and R().npcs[rec.npc] == nil then
            rec, missing = nil, "npc " .. rec.npc .. " of the record is no longer in the registry"
        end
        if rec == nil then
            measure(t, "restart phase 1 (" .. tostring(missing) .. ")")
            local id, body = B().spawn({ look = "womanTanBob" }, px, py, pz)
            t:ok(id ~= nil, "spawn refused: " .. tostring(body))
            local items = A().clothesKeys(R().npcs[id].clothes)
            t:ok(#items > 0, "clothes not recorded on the first body")
            t:ok(A().sameClothes(R().npcs[id].clothes, A().describe(body)), "recorded clothes = clothes of the body")
            local look = bodyLook(body)
            t:ok(B().despawn(id), "despawn (npc kept virtual)")
            if LivingKnox.Store.flush then LivingKnox.Store.flush() end
            writeRecord(t, { save = save, npc = id, body = look, items = items, mods = modList() })
            measure(t, "restart phase 1: npc " .. id .. " recorded, " .. look .. ", " .. #items .. " item(s)")
            for i, item in ipairs(items) do measure(t, "restart phase 1 item " .. i .. ": " .. item) end
            t:skip("phase 1 done (npc " .. id .. " recorded, virtual; " .. tostring(missing) .. "): add or remove a "
                .. "clothes mod, restart the game, load this save and run the suite again")
        end
        local passed = false
        t:defer(function()
            if passed then
                B().despawn(rec.npc, true)
                writeRecord(t, {})
            else
                B().despawn(rec.npc)   -- back to virtual, kept with the record for another run 2
            end
        end, "forget " .. rec.npc .. " and clear the record when run 2 passes")
        if R().npcs[rec.npc].state == "embodied" then B().despawn(rec.npc) end
        local body2, why = B().embody(rec.npc, px, py, pz)
        t:ok(body2 ~= nil, "embody " .. rec.npc .. ": " .. tostring(why))
        local now = modList()
        local added, removed = diff(now, rec.mods), diff(rec.mods, now)
        local look = bodyLook(body2)
        local d = A().diffKeys(rec.items, A().clothesKeys(A().describe(body2)))
        local gone, wrong = 0, 0
        for _, k in ipairs(d.removed) do
            local ty = string.match(k, "^([^|]*)")
            if A().itemExists(ty) then
                wrong = wrong + 1
                measure(t, "restart phase 2 missing: " .. k)
            else
                gone = gone + 1
                measure(t, "restart phase 2 left out (item type no longer exists): " .. k)
            end
        end
        for _, k in ipairs(d.added) do measure(t, "restart phase 2 added: " .. k) end
        for _, c in ipairs(d.changed) do measure(t, "restart phase 2 changed: " .. c.from .. " -> " .. c.to) end
        wrong = wrong + #d.added + #d.changed
        measure(t, "restart phase 2: npc " .. rec.npc .. " body " .. (look == rec.body and "same" or
            ("changed: " .. rec.body .. " -> " .. look)) .. ", clothes " .. #rec.items .. " recorded, " .. wrong
            .. " difference(s), " .. gone .. " left out, mods added {" .. table.concat(added, " ") .. "} removed {"
            .. table.concat(removed, " ") .. "}")
        t:eq(rec.body, look, "skin, hair, beard and colour after the restart")
        t:eq(0, wrong, "clothes differences after the restart (see the notes)")
        passed = true
        if #added + #removed == 0 then
            t:skip("same appearance, but the mod list did not change between both runs: change a clothes mod to prove "
                .. "LK02-T12")
        end
    end, { timeoutMs = 30000 })

    s.test("drawn profile is deterministic for an npc number", function(t)
        t:ok(A() ~= nil, "LivingKnox.Appearance not loaded")
        for seed = 1, 20 do
            local a, b = A().normalize({}, seed), A().normalize({}, seed)
            t:ok(a ~= nil and A().same(a, b), "seed " .. seed)
            local w = A().normalize({ female = true }, seed)
            t:eq(true, w.female, "female filter, seed " .. seed)
        end
    end)
end)
