--[[
RST_FactsBook - keeps the live fact log of RadioSurvivor (RS_Facts, private state RS_State, E14-T01) as it was before a
test (development mod only). Load with: require "RST/RST_FactsBook". No side effect at load time (definitions only).

    local Facts = RST.FactsBook.keep(t)
        RS_Facts when it is loaded here (authority of a game with RadioSurvivor active) and its book exists, else nil.
        The book is copied now; a cleanup (t:defer) puts that copy back and saves the private state, whatever the
        test recorded meanwhile (deaths, a mission closed through CA_Missions.finish...).
]]

require "RST/RST"

RST.FactsBook = RST.FactsBook or {}
local FB = RST.FactsBook

function FB.keep(t)
    local Facts = type(RS_Facts) == "table" and RS_Facts or nil
    local book = Facts and Facts.book() or nil
    if book == nil then return nil end
    local saved = RST.deepCopy(book)
    local S = require "RadioSurvivor/RS_State"
    t:defer(function()
        if S.data == nil then return end
        S.data.facts = saved
        S.dirty = true
        S.save()
    end, "fact log restored")
    return Facts
end

return FB
