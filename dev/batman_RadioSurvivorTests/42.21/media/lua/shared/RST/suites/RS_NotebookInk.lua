--[[
rs.notebook.ink - the notebook text is written in dark ink on its paper (E00-T12, client/RadioSurvivor/RS_Notebook.lua):
the real notebook window is opened, every bookmark (Radio, Contacts, Missions, Reputation, Team) is shown in turn, and
the rich text of the page is laid out (ISRichTextPanel:paginate): it starts with an <RGB:...> tag and no line keeps
the vanilla white or grey colour (every colour of the page is dark: r + g + b < 1.5). Each page stays 2 s on screen
for the eye of the tester (readability itself is judged by eye, see the campaign report).
Tags "client" and "world" (solo or MP client; "world" only so that the world campaigns select it, nothing is
changed). RST.run({ suite = "rs.notebook.ink", tags = { "client", "world" } }).
Cleanup: the notebook is closed again when it was closed before, back on its former bookmark otherwise.
]]

require "RST/RST"

local TABS = { "Radio", "Contacts", "Missions", "Reputation", "Team" }
local SHOW_MS = 2000
local DARK = 1.5

local function check(t, w, tab)
    w:changeTab(tab)
    local text = w.detail.text or ""
    t:eq("<RGB:", string.sub(text, 1, 5), tab .. ": page text does not start with a colour tag")
    w.detail:paginate()
    local lines, light = 0, {}
    for line, c in pairs(w.detail.rgb or {}) do
        lines = lines + 1
        if c.r + c.g + c.b >= DARK then light[#light + 1] = tostring(line) .. "=" .. c.r .. "," .. c.g .. "," .. c.b end
    end
    t:ok(lines > 0, tab .. ": no laid out line")
    t:eq(0, #light, tab .. ": light (white or grey) lines: " .. table.concat(light, " "))
    t:note(tab .. ": " .. lines .. " coloured line(s), all dark")
end

RST.suite("rs.notebook.ink", { tags = { "client", "world" }, testTimeoutMs = 30000 }, function(s)
    s.test("every page of the real notebook is written in dark ink", function(t)
        if type(isServer) == "function" and isServer() then t:skip("client UI (not on a server)") end
        local Notebook = require "RadioSurvivor/RS_Notebook"
        local Client = RS_CarnetClient
        t:ok(Notebook ~= nil and Client ~= nil, "notebook client not loaded")
        local wasOpen = Client.window ~= nil and Client.window:isVisible()
        if not wasOpen then Notebook.toggle() end
        local w = Client.window
        local formerTab = w.tab
        t:defer(function()
            if Client.window then
                Client.window:changeTab(formerTab)
                if not wasOpen and Client.window:isVisible() then Notebook.toggle() end
            end
        end, "close the notebook")
        local function step(t2, i)
            if i > #TABS then return t2:ok(true, "all pages checked") end
            check(t2, w, TABS[i])
            t2:sleep(SHOW_MS, function(t3) return step(t3, i + 1) end)
        end
        step(t, 1)
    end)
end)
