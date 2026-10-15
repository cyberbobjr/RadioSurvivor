--[[
rs.outside_news - outside news sheet brought by the smuggler (E13-T05, shared/RadioSurvivor/RS_OutsideNews.lua,
server/RadioSurvivor/RS_OutsideNewsServer.lua): item script loaded, an edition created by the passage entry point
(OutsideNewsServer.create, called by the future exchange E13-T04) holds keys and numbers only, two passages give two
different texts, the sheet is worth 0 when given back to the smuggler, and it opens in the vanilla document window
with the composed text (solo only: a dedicated server does not load the translations of the mods, and has no UI).
Tag "world": the authority only (solo or dedicated server), on a save named rstest*. Solo:
RST.run({ suite = "rs.outside_news", tags = "world" }); dedicated server, from an admin client:
RST.server({ suite = "rs.outside_news", tags = "world" }) (composition and window tests skipped there).

Changes to the world: the last test puts ONE edition (passage 2) in the main inventory of the target player, so
that the tester can also read it by hand ("Inspect"); nothing else is kept (the other editions are created in
memory by instanceItem and never added to a container). The document window opened by the reading test is closed
by the test.
]]

require "RST/RST"

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("editions are created on the authority (server files not loaded on an MP client)")
    end
    local ok, NewsServer = pcall(require, "RadioSurvivor/RS_OutsideNewsServer")
    t:ok(ok and type(NewsServer) == "table", "RadioSurvivor/RS_OutsideNewsServer is not loaded on this side")
    return NewsServer, require "RadioSurvivor/RS_OutsideNews"
end

local function soloOnly(t)
    if type(isServer) == "function" and isServer() then
        t:skip("a dedicated server does not load the translations of the mods: composed on the client")
    end
end

local function edition(t, NewsServer, passage)
    local item = NewsServer.create(passage)
    t:ok(item ~= nil, "OutsideNewsServer.create(" .. tostring(passage) .. ") returned nil")
    return item
end

RST.suite("rs.outside_news", { tags = { "world" } }, function(s)
    s.test("item script loaded", function(t)
        local _, News = authority(t)
        t:ok(getScriptManager():FindItem(News.FULL_TYPE) ~= nil, "no item script " .. News.FULL_TYPE)
    end)

    s.test("edition of a passage holds keys and numbers", function(t)
        local NewsServer, News = authority(t)
        local item = edition(t, NewsServer, 4)
        t:eq(News.FULL_TYPE, item:getFullType(), "item type")
        local modData = item:getModData()
        local pm = modData.printMedia
        t:ok(pm ~= nil, "no printMedia in the ModData")
        t:eq(News.ID_PREFIX .. "4", pm.id, "printMedia id")
        t:eq(pm.id, pm.title, "title = id (read mark of the edition)")
        t:eq(News.INFO_KEY, pm.info, "info is a key, not a composed text")
        t:eq(News.TEXT_KEY, pm.text, "text is a key, not a composed text")
        local n = modData[News.MODDATA_KEY]
        t:ok(n ~= nil, "no " .. News.MODDATA_KEY .. " in the ModData")
        t:eq(4, n.edition, "edition number")
        local gt = getGameTime()
        t:eq(gt:getYear(), n.y, "year of the edition")
        t:eq(gt:getMonth() + 1, n.m, "month of the edition")
        t:eq(gt:getDay() + 1, n.d, "day of the edition")
        t:note("edition 4: lead " .. tostring(n.lead) .. ", briefs " .. tostring(n.briefs[1]) .. ","
            .. tostring(n.briefs[2]) .. "," .. tostring(n.briefs[3]) .. ", dated " .. tostring(n.y) .. "-"
            .. tostring(n.m) .. "-" .. tostring(n.d))
        t:eq(nil, NewsServer.create(0), "passage 0 accepted")
    end)

    s.test("never bought back by the smuggler", function(t)
        local _, News = authority(t)
        local TV = require "RadioSurvivor/RS_TradeValues"
        t:eq(0, (TV.value(News.FULL_TYPE)), "the sheet has a buying value")
        t:eq(2, TV.sellValue(News.FULL_TYPE), "selling value of the sheet")
    end)

    s.test("text composed and changing from one passage to the next (solo)", function(t)
        local NewsServer, News = authority(t)
        soloOnly(t)
        local a = edition(t, NewsServer, 7)
        local b = edition(t, NewsServer, 8)
        local infoA, textA, titleA = News.compose(a:getModData())
        local infoB, textB, titleB = News.compose(b:getModData())
        t:ok(infoA ~= nil and infoB ~= nil, "compose returned nil")
        t:ok(string.find(textA, News.KEY, 1, true) == nil, "untranslated key in the transcript")
        t:ok(string.find(infoA, News.KEY, 1, true) == nil, "untranslated key in the layout")
        t:ok(string.find(infoA .. textA .. titleA, "%", 1, true) == nil, "placeholder left")
        t:ok(textA ~= textB, "two passages, same transcript")
        t:ok(infoA ~= infoB, "two passages, same layout")
        t:ok(titleA ~= titleB, "two passages, same title")
        t:note(titleA .. " / " .. titleB)
    end)

    s.test("opens in the vanilla document window (solo)", function(t)
        local NewsServer, News = authority(t)
        soloOnly(t)
        local player = (t.ctx and t.ctx.player) or (getPlayer and getPlayer())
        if not player then t:skip("no target player") end
        t:ok(PZAPI and PZAPI.UI and PZAPI.UI.PrintMedia ~= nil, "PZAPI.UI.PrintMedia missing")
        require "TimedActions/ISReadABook"
        local item = edition(t, NewsServer, 5)
        local info, text, title = News.compose(item:getModData())
        -- Temporary capture of the window built by ISReadABook:displayPrintMedia, restored before any check.
        local original = PZAPI.UI.PrintMedia
        local captured = nil
        PZAPI.UI.PrintMedia = setmetatable({}, { __call = function(_, args)
            local win = original(args)
            captured = win
            return win
        end, __index = original })
        local action = setmetatable({ item = item, character = player, playerNum = player:getPlayerNum() },
            { __index = ISReadABook })
        local ok, err = pcall(ISReadABook.displayPrintMedia, action)
        PZAPI.UI.PrintMedia = original
        t:ok(ok, "displayPrintMedia raised: " .. tostring(err))
        t:ok(captured ~= nil, "no document window created")
        t:eq(info, captured.data, "layout shown")
        t:eq(title, captured.textTitle, "title shown")
        t:ok(captured.textData ~= nil and #captured.textData > 0, "empty transcript")
        t:ok(string.find(text, "\\n", 1, true) ~= nil, "transcript without line breaks")
        local pm = item:getModData().printMedia
        t:eq(News.INFO_KEY, pm.info, "info key not restored")
        t:eq(News.ID_PREFIX .. "5", pm.title, "title not restored")
        if captured.javaObj then UIManager.RemoveElement(captured.javaObj) end
    end)

    s.test("one edition given to the target player for a manual reading", function(t)
        local NewsServer, News = authority(t)
        local player = (t.ctx and t.ctx.player) or (getPlayer and getPlayer())
        if not player then t:skip("no target player") end
        local before = player:getInventory():getCountTypeRecurse(News.FULL_TYPE)
        local item = NewsServer.give(2, player)
        t:ok(item ~= nil, "give returned nil")
        t:eq(before + 1, player:getInventory():getCountTypeRecurse(News.FULL_TYPE), "edition not in the inventory")
        t:note("edition 2 left in the inventory of " .. tostring(player:getUsername()) .. ": Inspect it by hand")
    end)
end)
