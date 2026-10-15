--[[
rs.notes - frequency notes (E05-T09): item scripts loaded, frequency of the game written by the authority on a new
note (OnCreate), notes present in the vanilla loot lists according to the NoteRarity option, text composed with the
frequency in the language of the game (solo only: a dedicated server does not load the translations of the mods).
Tags "world" and "server": the authority only (dedicated server or solo), on a save named rstest*. Solo:
RST.run({ suite = "rs.notes", tags = { "world", "server" } }); dedicated server:
RST.server({ suite = "rs.notes", tags = { "world", "server" } }) from an admin client. A plain string filter
runs 0 test: the default exclusions drop "world" (and "server" on the client side).

The notes are created in memory by instanceItem and never added to a container or to the world, except by the search
test: real containers of the rooms around the player (in the nearest town when too few are around: the player is
moved there and back) are rolled again by the vanilla loot code and every item added is removed at once.
The document test opens each note in the real document window (solo, 3 s each, closed after).
]]

require "RST/RST"

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("notes get their frequency on the authority (server files not loaded on an MP client)")
    end
    local ok, NotesServer = pcall(require, "RadioSurvivor/RS_NotesServer")
    t:ok(ok and type(NotesServer) == "table", "RadioSurvivor/RS_NotesServer is not loaded on this side")
    return NotesServer, require "RadioSurvivor/RS_Notes"
end

RST.suite("rs.notes", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 240000 }, function(s)
    s.test("item scripts of the five notes loaded", function(t)
        local _, Notes = authority(t)
        for _, def in ipairs(Notes.VOICES) do
            t:ok(getScriptManager():FindItem(def.fullType) ~= nil, "no item script " .. def.fullType)
        end
        t:ok(Notes.forVoice("whitaker") == nil, "whitaker (silent until E12) must not have a note")
    end)

    s.test("new note carries the frequency of its voice for this game", function(t)
        local NotesServer, Notes = authority(t)
        local Personas = require "RadioSurvivor/RS_Personas"
        local written = 0
        for _, def in ipairs(Notes.VOICES) do
            local item = instanceItem(def.fullType)
            t:ok(item ~= nil, "instanceItem(" .. def.fullType .. ") returned nil")
            local modData = item:getModData()
            t:eq(def.id, modData.printMedia and modData.printMedia.id, "printMedia id of " .. def.fullType)
            t:eq(def.infoKey, modData.printMedia.info, "info of " .. def.fullType .. " (keys, not a composed text)")
            local note = modData[Notes.MODDATA_KEY]
            t:ok(note ~= nil, "no " .. Notes.MODDATA_KEY .. " in the ModData of " .. def.fullType)
            t:eq(def.voice, note.voice, "voice of " .. def.fullType)
            t:eq(NotesServer.frequencyOf(def.voice), note.khz, "frequency of " .. def.fullType)
            local sheet = Personas.get(def.voice)
            if sheet and sheet.state == "active" and #Personas.served(def.voice) > 0 then
                t:eq(Personas.served(def.voice)[1], note.khz, "served frequency of voice " .. def.voice)
                written = written + 1
            end
            t:note(def.voice .. " -> " .. Notes.frequencyLabel(note))
        end
        t:ok(written > 0, "no note got a frequency (no active voice served?)")
    end)

    s.test("notes in the loot lists according to NoteRarity", function(t)
        local NotesServer, Notes = authority(t)
        local Const = require "RadioSurvivor/RadioSurvivor_Const"
        local factor = Const.noteRarityFactor()
        local expected = Const.isEnabled() and factor > 0
        for _, entry in ipairs(NotesServer.ENTRIES) do
            local list
            if entry.vehicle then
                list = VehicleDistributions[entry.list]
            else
                list = ProceduralDistributions.list[entry.list]
            end
            t:ok(list ~= nil and list.items ~= nil, "loot list " .. entry.list .. " missing")
            local weight = nil
            local items = list.items
            for i = 1, #items - 1 do
                if items[i] == Notes.forVoice(entry.voice).fullType then weight = items[i + 1] end
            end
            if expected then
                t:ok(weight ~= nil, "note of " .. entry.voice .. " missing from " .. entry.list)
                t:ok(math.abs(weight - entry.weight * factor) < 0.0001, "weight in " .. entry.list)
            else
                t:ok(weight == nil, "note of " .. entry.voice .. " in " .. entry.list .. " although disabled")
            end
        end
        t:note(tostring(#NotesServer.ENTRIES) .. " entries, rarity factor " .. tostring(factor))
    end)

    s.test("text composed with the frequency (solo)", function(t)
        local _, Notes = authority(t)
        if type(isServer) == "function" and isServer() then
            t:skip("a dedicated server does not load the translations of the mods: composed on the client")
        end
        local def = Notes.forVoice("walt")
        local item = instanceItem(def.fullType)
        local modData = item:getModData()
        local info, text = Notes.compose(modData)
        local label = Notes.frequencyLabel(modData[Notes.MODDATA_KEY])
        t:ok(info ~= def.infoKey, "translation " .. def.infoKey .. " missing")
        t:ok(string.find(info, label, 1, true) ~= nil, "frequency " .. label .. " absent from the layout")
        t:ok(string.find(text, label, 1, true) ~= nil, "frequency " .. label .. " absent from the transcript")
        t:ok(string.find(info, "%1", 1, true) == nil, "placeholder left in the layout")
        t:eq(def.infoKey, modData.printMedia.info, "keys kept on the item")
    end)

    -- E05-T09 in game: each note opened through the vanilla reader (ISReadABook:displayPrintMedia, the function the
    -- "Read" action calls), window captured, text checked, left 3 s on screen for the eye of the tester, then closed.
    s.test("each note opens in the document window with its frequency (solo)", function(t)
        local NotesServer, Notes = authority(t)
        if type(isServer) == "function" and isServer() then t:skip("document window: client UI (solo only)") end
        require "TimedActions/ISReadABook"
        local original = PZAPI.UI.PrintMedia
        local opened = {}
        PZAPI.UI.PrintMedia = function(args)
            local win = original(args)
            opened[#opened + 1] = win
            return win
        end
        t:defer(function()
            PZAPI.UI.PrintMedia = original
            for _, win in ipairs(opened) do
                if win.javaObj then UIManager.RemoveElement(win.javaObj) end
            end
        end, "restore PZAPI.UI.PrintMedia and close the documents")
        local function step(t2, i)
            local def = Notes.VOICES[i]
            if def == nil then return t2:ok(#opened == #Notes.VOICES, "documents opened") end
            local item = instanceItem(def.fullType)
            local note = item:getModData()[Notes.MODDATA_KEY]
            local label = Notes.frequencyLabel(note)
            local before = #opened
            ISReadABook:new(getPlayer(), item):displayPrintMedia()
            t2:eq(before + 1, #opened, def.fullType .. ": no document window")
            local win = opened[#opened]
            for _, field in ipairs({ "data", "textData", "textTitle" }) do
                local v = tostring(win[field] or "")
                t2:ok(v ~= "" and string.find(v, "%1", 1, true) == nil and string.find(v, "Print_", 1, true) == nil,
                    def.fullType .. ": " .. field .. " not composed: " .. string.sub(v, 1, 80))
            end
            if NotesServer.frequencyOf(def.voice) ~= nil then
                t2:ok(string.find(win.data, label, 1, true) ~= nil, def.fullType .. ": frequency absent from the page")
                t2:ok(string.find(win.textData, label, 1, true) ~= nil, def.fullType .. ": frequency absent from the text")
            end
            t2:note(def.voice .. ": '" .. tostring(win.textTitle) .. "' " .. label)
            t2:sleep(3000, function(t3)
                if win.javaObj then UIManager.RemoveElement(win.javaObj) end
                return step(t3, i + 1)
            end)
        end
        step(t, 1)
    end)

    -- E05-T09 in game: real search. The containers in rooms around the player (in a town: the player is moved to the
    -- nearest town centre when fewer than MIN_CONTAINERS are found) are filled again and again by the vanilla loot
    -- roll (ItemPickerJava.fillContainer, as at the first opening of a container); every item added by a roll is
    -- removed at once. The notes found, their container and their frequency are measured.
    s.test("searching town containers finds notes with the frequency of the game", function(t)
        local NotesServer, Notes = authority(t)
        local Const = require "RadioSurvivor/RadioSurvivor_Const"
        if not Const.isEnabled() or Const.noteRarityFactor() <= 0 then t:skip("NoteRarity = none: no note in the loot") end
        require "RST/RST_RSHelpers"
        local R, F = RST.RSHelpers, RST.Fixtures
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local RADIUS, MIN_CONTAINERS, MAX_ROUNDS, ENOUGH = 40, 30, 60, 5
        local function containers(pl)
            local cell, out = getCell(), {}
            local px, py, pz = math.floor(pl:getX()), math.floor(pl:getY()), math.floor(pl:getZ())
            for x = px - RADIUS, px + RADIUS do
                for y = py - RADIUS, py + RADIUS do
                    local sq = cell:getGridSquare(x, y, pz)
                    if sq ~= nil and sq:getRoom() ~= nil then
                        local objects = sq:getObjects()
                        for i = 0, objects:size() - 1 do
                            local o = objects:get(i)
                            for k = 0, o:getContainerCount() - 1 do
                                local c = o:getContainerByIndex(k)
                                if c ~= nil then out[#out + 1] = { c = c, room = sq:getRoom():getName() } end
                            end
                        end
                    end
                end
            end
            if #out < MIN_CONTAINERS then return nil end
            return out
        end
        local types = {}
        for _, def in ipairs(Notes.VOICES) do types[def.fullType] = def end
        R.place(t, p, containers, function(t2, list)
            R.god(t2, p)
            local found, byVoice, where, rounds = {}, {}, {}, 0
            local function round()
                rounds = rounds + 1
                for _, entry in ipairs(list) do
                    local c = entry.c
                    local before, items = {}, c:getItems()
                    for i = 0, items:size() - 1 do before[items:get(i):getID()] = true end
                    ItemPickerJava.fillContainer(c, p)
                    local added = {}
                    items = c:getItems()
                    for i = 0, items:size() - 1 do
                        local item = items:get(i)
                        if not before[item:getID()] then added[#added + 1] = item end
                    end
                    for _, item in ipairs(added) do
                        local def = types[item:getFullType()]
                        if def then
                            local note = item:getModData()[Notes.MODDATA_KEY]
                            found[#found + 1] = { voice = def.voice, khz = note and note.khz }
                            byVoice[def.voice] = (byVoice[def.voice] or 0) + 1
                            where[entry.room .. "/" .. c:getType()] = true
                        end
                        c:Remove(item)
                    end
                end
            end
            local function step(t3)
                local started = getTimestampMs()
                while rounds < MAX_ROUNDS and #found < ENOUGH and getTimestampMs() - started < 40 do round() end
                if rounds < MAX_ROUNDS and #found < ENOUGH then return t3:sleep(1, step) end
                local parts, places = {}, {}
                for voice, n in pairs(byVoice) do parts[#parts + 1] = voice .. " " .. n end
                for k in pairs(where) do places[#places + 1] = k end
                table.sort(parts)
                table.sort(places)
                t3:note(#list .. " containers x " .. rounds .. " rolls: " .. #found .. " note(s) ("
                    .. table.concat(parts, ", ") .. ") in " .. table.concat(places, ", "))
                t3:ok(#found > 0, "no note in " .. (#list * rounds) .. " container rolls")
                for _, f in ipairs(found) do
                    t3:eq(NotesServer.frequencyOf(f.voice), f.khz, "frequency written on a note of " .. f.voice)
                end
            end
            return step(t2)
        end)
    end)
end)
