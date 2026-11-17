--[[
ca.notebook - notebook of the core mod (E18-T24): the real notebook window (CoreAI/CA_Notebook) is opened
without any item, like the sidebar button, and shows one bookmark per tab of an active mod: Contacts, Missions and
Reputation always (core mod), plus the tabs each test mod registers for its mod in RST.NotebookTabs (E21-T07: name ->
order of the bookmark; RST_ModLivingKnox.lua, RST_ModRadioSurvivor.lua). Every page is laid out without a Lua
error. The notebook is left open on its Missions page for the final screenshot of the run.
Tags "client" and "world" (solo or MP client; nothing is changed in the world). Needs the core mod only, so it runs in
the three set-ups (autoclient.py --mods rs | lk | both). Outside the game: tests/coreai/test_core_notebook.py.
]]

require "RST/RST"

-- Bookmarks expected in the window, by order: the core tabs here, the others registered by the test mods.
RST.NotebookTabs = RST.NotebookTabs or {}
RST.NotebookTabs.Contacts = 20
RST.NotebookTabs.Missions = 30
RST.NotebookTabs.Reputation = 40

local function expectedTabs()
    local names = {}
    for name in pairs(RST.NotebookTabs) do names[#names + 1] = name end
    table.sort(names, function(a, b) return RST.NotebookTabs[a] < RST.NotebookTabs[b] end)
    return names
end

RST.suite("ca.notebook", { tags = { "client", "world" }, testTimeoutMs = 30000 }, function(s)
    s.test("one bookmark per tab of an active mod, every page laid out", function(t)
        if type(isServer) == "function" and isServer() then t:skip("client UI (not on a server)") end
        local Notebook = require "CoreAI/CA_Notebook"
        t:ok(type(Notebook) == "table" and type(Notebook.toggle) == "function", "core notebook not loaded")
        local expected = expectedTabs()
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
        w:changeTab("Missions")
        t:note("tabs " .. table.concat(names, ","))
    end)
end)
