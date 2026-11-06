--[[
rc.notebook - notebook of the core mod (E18-T24): the real notebook window (RadioSurvivorCore/RC_Notebook) is opened
without any item, like the sidebar button, and shows one bookmark per tab of an active mod: Contacts, Missions and
Reputation always (core mod), Radio with RadioSurvivor, Team with Living Knox (E18-T20). Every page is laid out
without a Lua error. The notebook is left open on its Missions page for the final screenshot of the run.
Tags "client" and "world" (solo or MP client; nothing is changed in the world). Needs the core mod only, so it runs in
the three set-ups (autoclient.py --mods rs | lk | both). Outside the game: tests/test_core_notebook.py.
]]

require "RST/RST"

local function active(id)
    local mods = getActivatedMods and getActivatedMods() or nil
    for i = 0, (mods and mods:size() or 0) - 1 do
        if string.gsub(tostring(mods:get(i)), "^\\", "") == id then return true end
    end
    return false
end

RST.suite("rc.notebook", { tags = { "client", "world" }, testTimeoutMs = 30000 }, function(s)
    s.test("one bookmark per tab of an active mod, every page laid out", function(t)
        if type(isServer) == "function" and isServer() then t:skip("client UI (not on a server)") end
        local Notebook = require "RadioSurvivorCore/RC_Notebook"
        t:ok(type(Notebook) == "table" and type(Notebook.toggle) == "function", "core notebook not loaded")
        local rs, lk = active("batman_RadioSurvivor"), active("batman_LivingKnox")
        local expected = {}
        if rs then expected[#expected + 1] = "Radio" end
        expected[#expected + 1] = "Contacts"
        expected[#expected + 1] = "Missions"
        expected[#expected + 1] = "Reputation"
        if lk then expected[#expected + 1] = "Team" end -- E18-T20: Living Knox's tab
        local w = Notebook.window
        if not (w and w:isVisible()) then w = Notebook.toggle(0, false) end
        local names = {}
        for _, b in ipairs(w.tabs) do names[#names + 1] = b.rsTab.name end
        t:eq(table.concat(expected, ","), table.concat(names, ","), "bookmarks of the active mods")
        for _, name in ipairs(names) do
            w:changeTab(name)
            t:ok(w.tab == name, name .. ": page not shown")
            t:ok(type(w.detail.text) == "string" and w.detail.text ~= "", name .. ": empty page")
        end
        -- Kahlua has no package table: the pages of RadioSurvivor are seen through their global.
        t:eq(rs, RS_Notebook ~= nil, "pages of RadioSurvivor loaded only with it")
        w:changeTab("Missions")
        t:note("mods: RadioSurvivor " .. tostring(rs) .. ", Living Knox " .. tostring(lk) .. "; tabs " ..
            table.concat(names, ","))
    end)
end)
