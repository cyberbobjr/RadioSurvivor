--[[
rs.lastpages - last pages of a dead notebook character (E15-T03, server/RadioSurvivor/RS_LastPages.lua): the real
Java pieces of the document (Base.Notebook written by addPage, locked by setLockedBy, custom name), the profession
display name read at the death, and the placement pass of the module on a frozen life log made by the suite:
    document    a document built from a made-up frozen log: Literature, locked, at most PAGES pages, title first;
    profession  CharacterProfessionDefinition gives the display name of the target player's profession;
    corpse      a corpse (RandomizedWorldBase.createRandomDeadBody, gap: a zombie corpse, not a player death) marked
                with the token, a made-up frozen log whose text is ready: one poll puts the document in the corpse,
                the log is released, a second poll adds nothing;
    fire        same log noted "on fire": the document goes on the ground of the death square, not in the corpse;
    option      (E15-T04) sandbox option RadioSurvivor.LastPages registered by the game (sandbox-options.txt), boolean,
                on by default, and read as on by RadioSurvivor_Const. The other tests are skipped when it is off.
Tags "world" and "server": authority only (solo or server), save named rstest*, target player t.ctx.player. Every
object made by the suite is removed at the end. Solo: RST.run({ suite = "rs.lastpages", tags = "world" });
dedicated server, from an admin client: RST.server({ suite = "rs.lastpages", tags = "world" }). Outside the game:
tests/test_last_pages.py. A real death (request to the bridge, fallback journal) follows the manual protocol of
docs/annexes/conception/dernieres-pages.md.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("authority only (solo or server), not an MP client")
    end
end

local function modules(t)
    authority(t)
    local P = require "RadioSurvivor/RS_LastPages"
    local L = require "RadioSurvivor/RS_LifeLog"
    local S = require "RadioSurvivor/RS_State"
    if type(P) ~= "table" or type(L) ~= "table" then t:skip("RS_LastPages or RS_LifeLog not loaded here") end
    if type(S) ~= "table" or not S.data or S.blocked then t:skip("private state of the notebook not ready") end
    local Const = require "RadioSurvivor/RadioSurvivor_Const"
    if not Const.lastPages() then t:skip("sandbox option RadioSurvivor.LastPages is off") end
    return P, L, S
end

local function target(t)
    local p = RST.Fixtures.player(t)
    if p == nil then t:skip("no target player (t.ctx.player)") end
    return p
end

local seq = 0

-- Made-up frozen life log (cid rst-lastpages-<n>) whose text is ready, death square (x, y, z).
local function fakeLog(t, S, x, y, z, fire)
    seq = seq + 1
    local cid = "rst-lastpages-" .. seq .. "-" .. string.format("%.0f", getTimestampMs())
    S.data.lifelogs = S.data.lifelogs or { seq = 0, logs = {} }
    local log = { cid = cid, name = "RST Tester", dead = true, deathSeq = 0, deathWhen = "07/12 21:05", kills = 3,
        hours = 30, profession = "unemployed", towns = { { name = "Muldraugh" } }, phrases = { { text = "Anyone?" } },
        missions = {}, open = {}, rescues = {}, noted = {},
        totals = { success = 0, failed = 0, cancelled = 0, saved = 0, missed = 0 } }
    log.pages = { state = "ready", token = "rst-" .. cid, x = x, y = y, z = z, fire = fire and true or false,
        dead = getTimestampMs() - 60000, asked = getTimestampMs() - 60000, source = "fallback",
        text = "First line of the suite.\n\nSecond paragraph." }
    S.data.lifelogs.logs[cid] = log
    t:defer(function() S.data.lifelogs.logs[cid] = nil end, "drop the made-up log")
    return cid, log
end

local function docIn(container, token)
    if container == nil then return nil end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:hasModData() and it:getModData().RS_LastPagesToken == token then return it end
    end
    return nil
end

local function docOnGround(sq, token)
    local list = sq:getWorldObjects()
    for i = 0, list:size() - 1 do
        local it = list:get(i):getItem()
        if it ~= nil and it:hasModData() and it:getModData().RS_LastPagesToken == token then return list:get(i) end
    end
    return nil
end

local function makeCorpse(t, sq)
    local body = RandomizedWorldBase.createRandomDeadBody(sq, IsoDirections.S, 0, 0, nil)
    t:ok(body ~= nil, "createRandomDeadBody returned nil")
    body:setFakeDead(false)
    t:defer(function()
        local s = body:getSquare()
        if s ~= nil then s:removeCorpse(body, false) end
    end, "remove the test corpse")
    return body
end

RST.suite("rs.lastpages", { tags = { "world", "server" } }, function(s)
    s.test("document: written, locked, bounded", function(t)
        local P, _, S = modules(t)
        local _, log = fakeLog(t, S, 0, 0, 0, false)
        local item = P.newDocument(log)
        t:ok(item ~= nil, "no document")
        t:ok(instanceof(item, "Literature"), "not a Literature")
        t:eq(P.ITEM, item:getFullType())
        t:eq(P.LOCK, item:getLockedBy(), "lock")
        local pages = item:getCustomPages()
        t:ok(pages ~= nil and pages:size() >= 1 and pages:size() <= P.PAGES, "page count")
        t:ok(string.find(item:seePage(1), "RST Tester", 1, true) ~= nil, "name not on the first page")
        t:note("name '" .. tostring(item:getName()) .. "', " .. pages:size() .. " page(s)")
    end)

    s.test("profession display name", function(t)
        modules(t)
        local p = target(t)
        local prof = p:getDescriptor():getCharacterProfession()
        t:ok(CharacterProfessionDefinition ~= nil, "CharacterProfessionDefinition not exposed")
        local def = CharacterProfessionDefinition.getCharacterProfessionDefinition(prof)
        t:ok(def ~= nil, "no definition for " .. tostring(prof))
        t:ok(type(def:getUIName()) == "string" and def:getUIName() ~= "", "empty UI name")
        t:note(tostring(prof:getName()) .. " -> " .. tostring(def:getUIName()))
    end)

    s.test("placement in the marked corpse, once", function(t)
        local P, L, S = modules(t)
        local p = target(t)
        local x, y, z = math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ())
        local sq = getCell():getGridSquare(x, y, z)
        t:ok(sq ~= nil, "square not loaded")
        local body = makeCorpse(t, sq)
        local cid, log = fakeLog(t, S, x, y, z, false)
        body:getModData()[P.TOKEN_KEY] = log.pages.token
        P.poll()
        local container = body:getContainer()
        local doc = docIn(container, log.pages.token)
        t:defer(function()
            if doc ~= nil and doc:getContainer() ~= nil then
                doc:getContainer():Remove(doc)
                if type(isServer) == "function" and isServer() then sendRemoveItemFromContainer(container, doc) end
            end
        end, "take the document back")
        t:ok(doc ~= nil, "document not in the corpse")
        t:ok(L.get(cid) == nil, "frozen log not released")
        P.poll()
        local n = 0
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it:hasModData() and it:getModData().RS_LastPagesToken == log.pages.token then n = n + 1 end
        end
        t:eq(1, n, "documents of this death")
    end)

    s.test("on fire: on the ground of the death square", function(t)
        local P, _, S = modules(t)
        local p = target(t)
        local x, y, z = math.floor(p:getX()) + 2, math.floor(p:getY()) + 1, math.floor(p:getZ())
        local sq = getCell():getGridSquare(x, y, z)
        t:ok(sq ~= nil, "square not loaded")
        local body = makeCorpse(t, sq)
        local _, log = fakeLog(t, S, x, y, z, true)
        body:getModData()[P.TOKEN_KEY] = log.pages.token
        P.poll()
        local wo = docOnGround(sq, log.pages.token)
        t:defer(function()
            if wo ~= nil and wo:getSquare() ~= nil then wo:getSquare():transmitRemoveItemFromSquare(wo) end
        end, "remove the document from the ground")
        t:ok(wo ~= nil, "document not on the ground")
        t:ok(docIn(body:getContainer(), log.pages.token) == nil, "document in the corpse of a death on fire")
    end)

    s.test("option RadioSurvivor.LastPages registered, on by default", function(t)
        authority(t)
        local options = type(getSandboxOptions) == "function" and getSandboxOptions() or nil
        t:ok(options ~= nil, "getSandboxOptions() is nil")
        local option = options:getOptionByName("RadioSurvivor.LastPages")
        t:ok(option ~= nil, "option RadioSurvivor.LastPages not registered (sandbox-options.txt)")
        local value = option:getValue()
        t:ok(type(value) == "boolean", "value is not a boolean: " .. tostring(value))
        t:eq(true, option:getDefaultValue(), "default value (BooleanConfigOption.getDefaultValue)")
        local Const = require "RadioSurvivor/RadioSurvivor_Const"
        t:eq(value, Const.lastPages(), "Const.lastPages() differs from the registered option")
        t:note("RadioSurvivor.LastPages = " .. tostring(value) .. (value and "" or " (off: other tests skipped)"))
    end)
end)
