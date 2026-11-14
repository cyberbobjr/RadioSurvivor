--[[
rs.memorial.animals - memorial of the evening bulletin (E14-T04, server/RadioSurvivor/RS_Facts.lua):
    animal    a real B42 animal (addAnimal, LuaManager.java:3013; vanilla hen "rhodeisland" of ISHutchUI.lua:175) is
              spawned two squares east of the target player and killed by IsoGameCharacter:Kill(player), the solo
              weapon path (IsoGameCharacter.java:5867, 13697 -> IsoPlayer.onKilled 7771 -> DoDeath 1839 ->
              IsoAnimal.OnDeath 1068 raises OnCharacterDeath). OnCharacterDeath is seen for the animal, the fact log
              gains nothing and no "None None" reaches the memorial. Counter-proof: the same handler, called directly
              on the target player (no real death), records that player for the memorial.
    bulletin  two test deaths in the fact log, then the real Facts.bulletin(true) with the radio submit caught (nothing
              reaches the bridge nor the air): the death sentence for the bridge is Facts.deathsText of the deaths,
              tells the voice that the names follow, never "do not name them", and carries no name; the memorial of
              the same facts reads both names.
Tags "server" and "world": authority only (solo or dedicated server), save named rstest*, target player t.ctx.player.
Cleanup: fact log put back as it was (RST.FactsBook), animal removed, death listener and radio submit restored, no
bulletin left in flight. Solo: RST.run({ suite = "rs.memorial.animals", tags = { "server", "world" } }); dedicated
server, from an admin client: RST.server({ suite = "rs.memorial.animals", tags = "world" }). Outside the game:
tests/test_rs_e14_e16_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_FactsBook"

local ANIMAL, BREED = "hen", "rhodeisland"
local TEST_NAMES = { "Rst Alpha", "Rst Bravo" }

local function factsOf(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Facts is not loaded on an MP client (authority only)")
    end
    local F = RST.FactsBook.keep(t)
    if F == nil then t:skip("RS_Facts or its private state is not loaded here") end
    return F
end

local function targetPlayer(t)
    local p = RST.Fixtures.player(t)
    if p == nil then t:skip("no target player (t.ctx.player)") end
    return p
end

local function nameOf(character)
    local d = character:getDescriptor()
    return tostring(d and d:getForename()) .. " " .. tostring(d and d:getSurname())
end

local function contains(text, part)
    return string.find(text, part, 1, true) ~= nil
end

RST.suite("rs.memorial.animals", { tags = { "server", "world" } }, function(s)
    s.test("a killed animal adds no death and no memorial name (E14-T04)", function(t)
        local F = factsOf(t)
        local p = targetPlayer(t)
        local def = AnimalDefinitions.getDef(ANIMAL)
        t:ok(def ~= nil, "no animal definition " .. ANIMAL)
        local breed = def:getBreedByName(BREED)
        t:ok(breed ~= nil, "no breed " .. BREED .. " for " .. ANIMAL)

        local seen = {}
        local function onDeath(c)
            if instanceof(c, "IsoAnimal") then seen[#seen + 1] = c end
        end
        Events.OnCharacterDeath.Add(onDeath)
        t:defer(function() Events.OnCharacterDeath.Remove(onDeath) end, "death listener removed")

        local animal = addAnimal(getCell(), math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ()),
            ANIMAL, breed)
        t:ok(animal ~= nil, "addAnimal returned nothing")
        local removed = false
        local function removeAnimal()
            if not removed then
                removed = true
                animal:remove()
            end
        end
        animal:addToWorld()
        t:defer(removeAnimal, "animal removed")
        t:ok(instanceof(animal, "IsoPlayer") and animal:isAnimal(), "an animal is an IsoPlayer answering isAnimal")
        t:note("animal descriptor: " .. nameOf(animal))

        local before = F.list()
        animal:Kill(p)
        removeAnimal()
        t:eq(1, #seen, "OnCharacterDeath raised for the animal")
        t:ok(seen[1] == animal, "OnCharacterDeath raised for another animal")
        local after = F.list()
        t:eq(before.next, after.next, "the death of the animal added a fact")
        for _, line in ipairs(F.memorialLines(after.facts)) do
            t:ok(not contains(line, nameOf(animal)), "animal name in the memorial: " .. line)
        end

        -- Counter-proof: the handler does record a player character (direct call, the player stays alive).
        F.characterDeath(p)
        local memorial = table.concat(F.memorialLines(F.list().facts), " ")
        t:ok(contains(memorial, nameOf(p)), "the handler records no player either: " .. memorial)
    end)

    s.test("bulletin announces the memorial names without refusing them (E14-T04)", function(t)
        local F = factsOf(t)
        local radio = type(RS_RadioServer) == "table" and RS_RadioServer or nil
        if radio == nil then t:skip("RS_RadioServer is not loaded here") end
        if F.flight then t:skip("a bulletin is already waiting for the bridge") end
        if not radio.frequency(F.CHRONICLER) then
            t:skip("the chronicler (" .. F.CHRONICLER .. ") is not on the air")
        end
        local stamp = tostring(RST.now())
        for _, name in ipairs(TEST_NAMES) do
            local n, why = F.record("death", { name = name }, "rst-memorial|" .. name .. "|" .. stamp)
            t:ok(n ~= nil, "death of " .. name .. " not recorded: " .. tostring(why))
        end

        local submit, sent = radio.submit, nil
        radio.submit = function(req)
            sent = req
            return true
        end
        t:defer(function()
            radio.submit = submit
            F.flight = nil
        end, "radio submit restored, test bulletin dropped")
        local ok, why = F.bulletin(true)
        radio.submit = submit
        local flight = F.flight
        F.flight = nil
        t:ok(ok, "bulletin not built: " .. tostring(why))
        t:ok(sent ~= nil and flight ~= nil, "no request for the bridge")

        local Codec = require "RadioSurvivorCore/RC_Codec"
        local texts = Codec.decodeBytes(Codec.unhexBytes(sent.facts))
        local _, deaths = F.split(flight.facts)
        local sentence = texts[1]
        t:eq(F.deathsText(#deaths), sentence, "first fact for the bridge: the sentence of the deaths")
        local lower = string.lower(sentence)
        t:ok(contains(lower, "names follow"), "the voice is not told that the names follow: " .. sentence)
        t:ok(not contains(lower, "do not name them"), "the voice is told to refuse the names: " .. sentence)
        for _, text in ipairs(texts) do
            for _, name in ipairs(TEST_NAMES) do
                t:ok(not contains(text, name), "name given to the bridge: " .. text)
            end
        end
        local memorial = table.concat(F.memorialLines(flight.facts), " ")
        for _, name in ipairs(TEST_NAMES) do
            t:ok(contains(memorial, name), name .. " not read by the memorial: " .. memorial)
        end
        t:note(sentence)
    end)
end)
