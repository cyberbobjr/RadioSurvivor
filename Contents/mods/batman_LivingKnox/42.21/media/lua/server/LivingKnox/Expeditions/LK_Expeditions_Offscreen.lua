-- Living Knox : expéditions, bascule hors écran et retour abstrait (LK09)
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ hors écran (LK09)

-- Bascule de l'expédition en cours du groupe g (registre vivant, dans une écriture) en expédition abstraite.
local function toAbstract(gid, g, t, team, hour, why)
    local hours = P.cfg().ABSTRACT_HOURS[t.phase] or 1
    g.expedition = { place = Ex.PLACE, team = team, departed = hour, returns = hour + hours, trip = t.n }
    t.from = t.phase
    t.phase = "away"
    t.team = team
    local G = LivingKnox.Groups
    G.appendLog(g, "trip", P.cut(string.format("trip %d offscreen (%s): %s, back in %d h", t.n, t.from,
        table.concat(team, " "), hours)), G.today())
    Ex.stats.abstract = Ex.stats.abstract + 1
    LivingKnox.Log.info("expedition: group %s trip %d goes offscreen during %s (%s): %s, back at hour %d", gid, t.n, t.from,
        tostring(why), table.concat(team, " "), hour + hours)
    Ex.state.claims[gid .. "#" .. t.n] = nil
end

-- PNJ npcId d'un membre retiré du monde (Materialize.onReleased, LK03-T04) : membre de l'équipe d'une expédition en
-- cours retiré de l'équipe (de retour au foyer pour la simulation), ou toute l'équipe hors écran si plus aucun de ses
-- corps n'a de joueur à BODIES.RELEASE_RADIUS cases. Rend "abstract", "left" ou nil.
function Ex.onReleased(gid, mid)
    local t, g = P.curOf(gid)
    if t == nil or not Ex.ACTIVE[t.phase] or not P.inList(t.team, mid) then return nil end
    local B = LivingKnox.Bodies
    local players = B.livingPlayers()
    local r = LivingKnox.Config.BODIES and LivingKnox.Config.BODIES.RELEASE_RADIUS or 120
    local near = false
    for _, other in ipairs(t.team) do
        local m = g.members[other]
        if other ~= mid and m ~= nil and m.alive and m.npc ~= nil and P.isEmbodied(m) then
            local z = B.find(m.npc)
            if z ~= nil and B.playerNear(players, z:getX(), z:getY(), r) then near = true end
        end
    end
    local hour = LivingKnox.Decisions.currentHour() or 0
    local result
    LivingKnox.Groups.update(function(d)
        local live = d.groups[gid]
        local cur = live and live.trips and live.trips.cur or nil
        if cur == nil or cur.n ~= t.n then return false, false end
        local team = {}
        for _, other in ipairs(cur.team) do
            local m = live.members[other]
            if m ~= nil and m.alive and (not near or other ~= mid) then team[#team + 1] = other end
        end
        if near then
            cur.team = team
            result = "left"
            LivingKnox.Log.info("expedition: group %s trip %d: %s left the team (released, the others are still seen)", gid,
                cur.n, mid)
        elseif #team > 0 then
            toAbstract(gid, live, cur, team, hour, mid .. " released")
            result = "abstract"
        end
        return true, true
    end)
    return result
end

-- Butin abstrait d'une fouille hors écran (offscreen du genre de repli) : par manque et par membre revenu, chance
-- ABSTRACT_FIND d'un objet de ABSTRACT_ITEMS (flux erand), dans la charge. Rend le nombre d'objets trouvés.
function Ex.searchOffscreen(g, gid, t, back, erand)
    local c = P.cfg()
    local found = 0
    for _, w in ipairs(t.want) do
        local list = Ex.ABSTRACT_ITEMS[w.c] or {}
        for _ = 1, back do
            if w.m > 0 and #t.carry < t.cap and #list > 0 and erand() < c.ABSTRACT_FIND then
                local k = math.min(#list, math.floor(erand() * #list) + 1)
                t.carry[#t.carry + 1] = { t = list[k], c = w.c, a = true }
                w.m = w.m - 1
                found = found + 1
            end
        end
    end
    return found
end

-- Tirages restants d'un genre à tirages hors écran (offscreen) : même flux qu'à l'écran (tirage k), conditions du
-- moment. Rend le nombre d'objets notés.
function Ex.drawnOffscreen(g, gid, t, back, erand, kind)
    local cond = kind.conditions()
    local found = 0
    while (t.k or 0) < (t.r or 0) and #t.carry < t.cap and P.remaining(t) > 0 do
        t.k = (t.k or 0) + 1
        local before = #t.carry
        P.addFinds(t, (kind.draw(gid, t, t.k, cond)))
        found = found + #t.carry - before
    end
    return found
end

-- Retour d'une expédition abstraite (appelé par LivingKnox.Simulation.simulateHour, à l'heure returns, dans
-- l'écriture du pas) : aucun membre perdu ni blessé ; butin abstrait tiré du flux erand (reproductible) ; phase
-- deliver (dépôt dès que le foyer est lisible). Pur sur le registre : aucun accès au monde. Rend le bilan.
function Ex.resolveAbstract(g, gid, hour, erand, day)
    local e = g.expedition
    g.expedition = nil
    local G = LivingKnox.Groups
    local s = g.trips
    local t = type(s) == "table" and s.cur or nil
    local back = 0
    for _, mid in ipairs(e.team) do
        local m = g.members[mid]
        if m ~= nil and m.alive then back = back + 1 end
    end
    if t == nil or t.n ~= e.trip or t.phase ~= "away" or not Ex.validCur(t) then
        G.appendLog(g, "return", P.cut("trip " .. tostring(e.trip) .. ": record lost, " .. back .. " back"), day)
        if type(s) == "table" then s.cur = nil end
        return { back = back, found = 0 }
    end
    local kind = Ex.kindOf(t)
    local found = kind.offscreen(g, gid, t, back, erand, kind)
    t.phase = "deliver"
    t.due = math.floor(hour * 60)
    G.appendLog(g, "trip", P.cut(string.format("trip %d back offscreen: %d back, %d item(s) found", t.n, back, found)),
        day)
    Ex.stats.resolved = Ex.stats.resolved + 1
    LivingKnox.Log.info("expedition: group %s trip %d back from offscreen at hour %d: %d back, %d item(s) found", gid, t.n,
        hour, back, found)
    return { back = back, found = found }
end
