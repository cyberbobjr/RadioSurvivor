--[[
rs.env — environment of batman_RadioSurvivor: game version 42.21, mod active, Java globals, exposed classes and
methods the mod really uses (inventory of Contents/mods/batman_RadioSurvivor/42.21/media/lua, RS_Bandits.lua left out:
the Bandits! adapter is being removed, E17-T01). Tag "shared": runs in solo and on a client (RST.run("rs.env")) and
on the server (RST.server("rs.env"), dedicated server autorun); outside the game: tests/test_rs_suites.py.

Sides: a dependency belongs to the side of the files that use it.
    any     shared files, or used by both client and server files: checked everywhere.
    server  server files (authority: dedicated server or solo, where server files also load): checked when
            isClient() is false; SKIP with the reason on an MP client.
    client  client files (MP client or solo): checked when isServer() is false; SKIP with the reason on a server.
A missing global gives FAIL "missing Java global X (used by file:line)"; every missing name of a group is listed in
the same message. Java methods are checked on a real object: the inventory of the player of the run (t.ctx.player,
else getPlayer() off a server) or, without a player, a new empty ItemContainer (ItemContainer.new(), memory only,
never added to the world); SKIP when neither exists.
getActivatedMods(): Java List<String> of the loaded IDs; Mods= (GameServer.java:675) and mods.txt
(ActiveModsFile.java:99) are read with "\" removed; a leading "\" is still removed here before comparing.
]]

require "RST/RST"

local MOD_ID = "batman_RadioSurvivor"
local PREFIX = "media/lua/"

-- { name, side, first use in the mod (relative to media/lua) }. A dotted name is a field of an exposed class.
local GLOBALS = {
    { "isClient", "any", "server/RadioSurvivor/RS_Missions.lua:1" },
    { "isServer", "any", "client/RS_Carnet_Client.lua:1" },
    { "getTimestampMs", "any", "server/RadioSurvivor/RS_Missions.lua:89" },
    { "getSandboxOptions", "any", "shared/RadioSurvivor/RadioSurvivor_Const.lua:144" },
    -- Lua global of the required mod batman_BeltRadio (shared file, loaded everywhere): transmit predicate.
    { "BatmanRadioSupport.canTransmitWith", "any", "shared/RadioSurvivor/RadioSurvivor_Const.lua:264" },
    { "getPlayer", "any", "server/RadioSurvivor_Server.lua:60" },
    { "sendServerCommand", "server", "server/RS_Carnet_Server.lua:26" },
    { "getOnlinePlayers", "server", "server/RadioSurvivor_Server.lua:61" },
    { "getServerOptions", "server", "server/RS_Carnet_Server.lua:269" },
    { "detectBadWords", "server", "server/RS_Carnet_Server.lua:274" },
    { "addSound", "server", "server/RS_Carnet_Server.lua:803" },
    { "getFileReader", "server", "server/RadioSurvivor/RS_State.lua:13" },
    { "getFileWriter", "server", "server/RadioSurvivor/RS_State.lua:59" },
    { "getWorld", "server", "server/RadioSurvivor/RS_State.lua:27" },
    { "ZombRand", "server", "server/RadioSurvivor/RS_State.lua:9" },
    { "getGameTime", "server", "server/RadioSurvivor_Server.lua:81" },
    { "getClimateManager", "server", "server/RadioSurvivor/RS_ObservationTriggers.lua:243" },
    { "getZomboidRadio", "server", "server/RadioSurvivor/RS_Personas.lua:720" },
    { "sendRemoveItemFromContainer", "server", "server/RadioSurvivor/RS_Missions.lua:505" },
    { "sendAddItemToContainer", "server", "server/RadioSurvivor/RS_Missions.lua:324" },
    { "DynamicRadioChannel.new", "server", "server/RadioSurvivor/RS_Personas.lua:676" },
    { "ChannelCategory.Amateur", "server", "server/RadioSurvivor/RS_Personas.lua:676" },
    { "RadioBroadCast.new", "server", "server/RadioSurvivor_Server.lua:112" },
    { "RadioLine.new", "server", "server/RadioSurvivor_Server.lua:116" },
    { "getCell", "server", "server/RadioSurvivor_Server.lua:251" },
    { "listFilesInModDirectory", "server", "server/RadioSurvivor/RS_Personas.lua:265" },
    { "getModFileReader", "server", "server/RadioSurvivor/RS_Personas.lua:281" },
    { "listFilesInZomboidLuaDirectory", "server", "server/RadioSurvivor/RS_Personas.lua:369" },
    { "instanceItem", "server", "server/RadioSurvivor/RS_Missions.lua:308" },
    { "ItemPickerJava.Parse", "server", "server/RadioSurvivor/RS_NotesServer.lua:114" },
    { "getSpecificPlayer", "client", "client/RadioSurvivor/RS_Client.lua:11" },
    { "sendClientCommand", "client", "client/RadioSurvivor/RS_Client.lua:15" },
    { "processSayMessage", "client", "client/RadioSurvivor/RS_Client.lua:130" },
    { "checkPlayerCanUseChat", "client", "client/RadioSurvivor/RS_Client.lua:141" },
    { "getText", "any", "client/RadioSurvivor/RS_Client.lua:176" },
    { "getTextOrNull", "server", "server/RadioSurvivor_Server.lua:519" },
    { "Translator.loadFiles", "server", "server/RadioSurvivor_Server.lua:521" },
    { "getCore", "client", "client/RadioSurvivor/RS_Notebook.lua:408" },
    { "getTextManager", "client", "client/RadioSurvivor/RS_Notebook.lua:210" },
    { "getTexture", "client", "client/RadioSurvivor/RS_Notebook.lua:31" },
    { "getScriptManager", "client", "client/RadioSurvivor/RS_Notebook.lua:69" },
    { "instanceof", "client", "client/RadioSurvivor/RS_Notebook.lua:1206" },
    { "Translator.getLanguage", "any", "client/RadioSurvivor/RS_Client.lua:35" },
    { "UIFont.Medium", "client", "shared/RadioSurvivor/RS_NPCProvider.lua:271" },
    { "Keyboard.KEY_G", "client", "client/RadioSurvivor/RS_Notebook.lua:1326" },
    { "ISTimedActionQueue.add", "client", "client/RadioSurvivor/RS_RadioHistory.lua:237" },
    { "ISRadioAction.new", "client", "client/RadioSurvivor/RS_RadioHistory.lua:237" },
    -- Map marks of a voice (E07-T04): hidden UIWorldMap on the world map symbols.
    { "MapItem.getSingleton", "client", "client/RadioSurvivor/RS_MapActions.lua:79" },
    { "UIWorldMap.new", "client", "client/RadioSurvivor/RS_MapActions.lua:83" },
    -- Area revealed by a voice (E07-T05): known squares of the world map, client and server (MP account) sides.
    { "WorldMapVisited.getInstance", "client", "client/RadioSurvivor/RS_MapActions.lua:155" },
    { "WorldMapVisitedServer.getInstance", "server", "server/RadioSurvivor/RS_MapMarks.lua:129" },
    -- Comfort from talk (E05-T15): stats eased by the authority, synced to the client, vanilla arrow halo.
    { "CharacterStat.BOREDOM", "server", "server/RadioSurvivor/RS_Comfort.lua:62" },
    { "SyncPlayerStatsPacket.getBitMaskForStat", "server", "server/RadioSurvivor/RS_Comfort.lua:29" },
    { "syncPlayerStats", "server", "server/RadioSurvivor/RS_Comfort.lua:74" },
    { "HaloTextHelper.addTextWithArrow", "client", "client/RadioSurvivor/RS_RadioTalk.lua:179" },
    { "HaloTextHelper.getGoodColor", "client", "client/RadioSurvivor/RS_RadioTalk.lua:180" },
}

-- Methods of an ItemContainer used by the server files (missions, radio carried on the belt).
local CONTAINER_METHODS = {
    { "getItemWithIDRecursiv", "server/RadioSurvivor/RS_Missions.lua:445" },
    { "getItemWithID", "server/RadioSurvivor_Server.lua:232" },
    { "getCapacityWeight", "server/RadioSurvivor/RS_Missions.lua:314" },
    { "getEffectiveCapacity", "server/RadioSurvivor/RS_Missions.lua:314" },
    { "AddItem", "server/RadioSurvivor/RS_Missions.lua:323" },
    { "Remove", "server/RadioSurvivor/RS_Missions.lua:504" },
}

local function side()
    if type(isServer) == "function" and isServer() then return "server" end
    if type(isClient) == "function" and isClient() then return "client" end
    return "solo"
end

-- Side of the run -> does it load the files of side s?
local function covers(runSide, depSide)
    if depSide == "any" then return true end
    if depSide == "server" then return runSide ~= "client" end
    return runSide ~= "server"
end

-- Value of a global or of a dotted field of an exposed class, without raising.
local function lookup(name)
    local ok, value = pcall(function()
        local v = _G
        for part in string.gmatch(name, "[^.]+") do
            if v == nil then return nil end
            v = v[part]
        end
        return v
    end)
    if ok then return value end
    return nil
end

local function present(name)
    local v = lookup(name)
    if v == nil then return false end
    -- A dotted name ending with a lower case word is a function (new, CreateItem, getLanguage).
    local last = string.match(name, "%.([^.]+)$") or name
    if string.match(last, "^%l") then return type(v) == "function" end
    return true
end

local function missing(list)
    local out = {}
    for _, dep in ipairs(list) do
        if not present(dep[1]) then
            out[#out + 1] = "missing Java global " .. dep[1] .. " (used by " .. PREFIX .. dep[3] .. ")"
        end
    end
    return out
end

local function checkSide(t, depSide)
    local runSide = side()
    if not covers(runSide, depSide) then
        t:skip(depSide .. " dependencies are not loaded on the " .. runSide .. " side")
    end
    local list = {}
    for _, dep in ipairs(GLOBALS) do
        if dep[2] == depSide then list[#list + 1] = dep end
    end
    local out = missing(list)
    if #out > 0 then t:fail(table.concat(out, "; ")) end
    t:ok(#list > 0, "no " .. depSide .. " dependency listed")
end

-- Real container: inventory of the player of the run, else a new empty ItemContainer (memory only).
local function container(t)
    local player = t.ctx and t.ctx.player
    if player == nil and side() ~= "server" and type(getPlayer) == "function" then
        local ok, p = pcall(getPlayer)
        if ok then player = p end
    end
    if player ~= nil then
        local ok, inv = pcall(function() return player:getInventory() end)
        if ok and inv ~= nil then return inv, player, "player inventory" end
    end
    local cls = lookup("ItemContainer.new")
    if type(cls) == "function" then
        local ok, inv = pcall(cls)
        if ok and inv ~= nil then return inv, nil, "new ItemContainer" end
    end
    t:skip("no player inventory and no ItemContainer.new to check the methods on")
end

RST.suite("rs.env", { tags = { "shared" } }, function(s)
    s.test("game version is 42.21", function(t)
        t:ok(type(getCore) == "function", "missing Java global getCore")
        local version = tostring(getCore():getVersion())
        t:eq("42.21", string.sub(version, 1, 5), "version " .. version)
        local nextChar = string.sub(version, 6, 6)
        t:ok(not string.match(nextChar, "%d"), "version " .. version .. " is not 42.21")
    end)

    s.test("batman_RadioSurvivor is active", function(t)
        t:ok(type(getActivatedMods) == "function", "missing Java global getActivatedMods")
        local mods = getActivatedMods()
        t:ok(mods ~= nil, "getActivatedMods() returned nil")
        local ids = {}
        local found = false
        for i = 0, mods:size() - 1 do
            local id = tostring(mods:get(i))
            if string.sub(id, 1, 1) == "\\" then id = string.sub(id, 2) end
            ids[#ids + 1] = id
            if id == MOD_ID then found = true end
        end
        t:ok(found, MOD_ID .. " not in getActivatedMods(): " .. table.concat(ids, ";"))
    end)

    s.test("Java globals used everywhere", function(t) checkSide(t, "any") end)
    s.test("Java globals of the server files", function(t) checkSide(t, "server") end)
    s.test("Java globals of the client files", function(t) checkSide(t, "client") end)

    s.test("ItemContainer methods used by the missions", function(t)
        local runSide = side()
        if not covers(runSide, "server") then
            t:skip("server dependencies are not loaded on the " .. runSide .. " side")
        end
        local inv, player, what = container(t)
        local out = {}
        for _, m in ipairs(CONTAINER_METHODS) do
            local ok, fn = pcall(function() return inv[m[1]] end)
            if not ok or type(fn) ~= "function" then
                out[#out + 1] = "missing method ItemContainer:" .. m[1] .. " (used by " .. PREFIX .. m[2] .. ")"
            end
        end
        if #out > 0 then t:fail(what .. ": " .. table.concat(out, "; ")) end
        t:eq(nil, inv:getItemWithIDRecursiv(-1), what .. ": getItemWithIDRecursiv(-1)")
        t:eq("number", type(inv:getCapacityWeight()), what .. ": getCapacityWeight()")
        t:eq("number", type(inv:getEffectiveCapacity(player)), what .. ": getEffectiveCapacity()")
    end)

    s.test("world and server option methods used by the server files", function(t)
        local runSide = side()
        if not covers(runSide, "server") then
            t:skip("server dependencies are not loaded on the " .. runSide .. " side")
        end
        local world = getWorld()
        t:ok(world ~= nil, "getWorld() returned nil")
        -- server/RadioSurvivor/RS_State.lua:28 builds the state path from these two strings.
        t:eq("string", type(world:getGameMode()), "IsoWorld:getGameMode() (used by " .. PREFIX
            .. "server/RadioSurvivor/RS_State.lua:28)")
        t:eq("string", type(world:getWorld()), "IsoWorld:getWorld() (used by " .. PREFIX
            .. "server/RadioSurvivor/RS_State.lua:28)")
        if runSide == "server" then
            -- server/RS_Carnet_Server.lua:257 and :344 only read the options on a server.
            local options = getServerOptions()
            t:eq("string", type(options:getOption("ChatStreams")), "ServerOptions:getOption (used by " .. PREFIX
                .. "server/RS_Carnet_Server.lua:257)")
            t:eq("number", type(options:getInteger("ChatMessageSlowModeTime")), "ServerOptions:getInteger (used by "
                .. PREFIX .. "server/RS_Carnet_Server.lua:347)")
        end
        if type(detectBadWords) == "function" then
            t:eq("boolean", type(detectBadWords("hello")), "detectBadWords returns a boolean")
        end
    end)
end)
