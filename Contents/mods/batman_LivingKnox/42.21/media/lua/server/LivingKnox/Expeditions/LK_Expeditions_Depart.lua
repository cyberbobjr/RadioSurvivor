-- Living Knox : expéditions, départ : équipe, manques, genre et lieu (Expeditions.tryDepart)
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ départ

local function hourOfDay(minute) return (math.floor(minute / 60) + 7) % 24 end

-- Vrai si l'heure du jour hod est une heure de jour (DEPART_FROM..DEPART_TO : bâtiment, cueillette).
function Ex.dayHour(hod) return hod >= P.cfg().DEPART_FROM and hod < P.cfg().DEPART_TO end

local function isEmbodied(m)
    local Si = LivingKnox.Simulation
    return Si ~= nil and Si.isEmbodied ~= nil and Si.isEmbodied(m)
end

local function bodyAtHome(m, home)
    local z = LivingKnox.Bodies.find(m.npc)
    if z == nil then return false end
    return math.floor(z:getZ()) == home.z and LivingKnox.Geo.cheb(z:getX(), z:getY(), home.x + 0.5, home.y + 0.5)
        <= LivingKnox.Decisions.CFG.HOME_RADIUS
end

-- Besoins qui retiennent un membre au foyer (LK05-T15) : rend la raison, ou nil s'il peut partir. want = manques de
-- l'expédition ({ { c, m } }) : faim élevée admise si la nourriture est cherchée, soif élevée si l'eau l'est.
local NEED_ANSWERED_BY = { hunger = "food", thirst = "water" }
function Ex.needBlocker(needs, want)
    local sought = {}
    for _, w in ipairs(want or {}) do sought[w.c] = true end
    for _, key in ipairs({ "fear", "fatigue", "hunger", "thirst" }) do
        local v, lim = needs and needs[key] or 0, LivingKnox.Decisions.needHigh(key)   -- LK05-T16 : peur = AfraidFear
        if lim ~= nil and v >= lim then
            local cat = NEED_ANSWERED_BY[key]
            if cat == nil or not sought[cat] then return key .. " " .. v end
        end
    end
    return nil
end

-- Équipe (pur sur le registre vivant) : fourrageurs vivants, incarnés, au foyer, hors chef, assez valides, sans
-- besoin élevé que l'expédition ne comble pas (gid et want donnés : Ex.needBlocker). Rend la liste triée par numéro
-- et le nombre de vivants présents au foyer.
function Ex.teamOf(g, gid, want)
    local G, c = LivingKnox.Groups, P.cfg()
    local mids, present = {}, 0
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then
            present = present + 1
            if m.duty == "forager" and mid ~= g.leader and m.npc ~= nil and isEmbodied(m)
                and LivingKnox.Decisions.healthOf(m) >= c.TEAM_HEALTH and bodyAtHome(m, g.home)
                and (gid == nil or Ex.needBlocker(LivingKnox.Decisions.needsOf(gid, mid), want) == nil) then
                mids[#mids + 1] = mid
            end
        end
    end
    table.sort(mids, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
    local n = math.min(c.TEAM_MAX, #mids, present - c.MIN_HOME)
    local team = {}
    -- E10-T03 : gid donné, chaque partant est jugé (Decisions.judgeOrder) : un refus le laisse au foyer, le suivant part.
    local D = LivingKnox.Decisions
    local minute = gid ~= nil and D.judgeOrder ~= nil and D.currentMinute() or nil
    for _, mid in ipairs(mids) do
        if #team >= n then break end
        if minute == nil or D.judgeOrder(gid, g, mid, g.members[mid], "expedition", "expedition", minute) == nil then
            team[#team + 1] = mid
        end
    end
    return team, present
end

-- Raison pour laquelle le groupe ne part pas (ou nil : il peut partir), sans lire le monde.
function Ex.departBlocker(g, minute)
    local c = P.cfg()
    if type(g.home) ~= "table" then return "no home" end
    if g.objective ~= "supply" then return "objective " .. tostring(g.objective) end
    if g.expedition ~= nil then return "offscreen expedition under way" end
    local s = g.trips
    if type(s) == "table" and s.cur ~= nil then return "expedition under way" end
    if type(s) == "table" and s.last ~= nil and minute - s.last < c.COOLDOWN_MINUTES and minute >= s.last then
        return "rested less than " .. c.COOLDOWN_MINUTES .. " minutes"
    end
    local hod = hourOfDay(minute)
    if not P.kindHour(hod) then return "hour of day " .. hod end
    return nil
end

-- Manques du stock (Stock.needs) : { { c, m } } dans l'ordre du manque, ou nil et une raison.
function Ex.wantOf(gid)
    local a, why = LivingKnox.Stock.needs(gid)
    if a == nil then return nil, why end
    local want = {}
    for _, nd in ipairs(a.needs) do
        if P.CATS[nd.c] and nd.missing > 0 then want[#want + 1] = { c = nd.c, m = nd.missing } end
    end
    if #want == 0 then return nil, "nothing missing" end
    return want
end

local function wantText(want)
    local parts = {}
    for _, w in ipairs(want) do parts[#parts + 1] = w.c .. " " .. w.m end
    return table.concat(parts, ", ")
end

-- Départ éventuel du groupe gid à la minute minute. Rend le numéro de l'expédition partie, ou nil et une raison.
function Ex.tryDepart(gid, minute)
    local g = P.liveGroup(gid)
    if g == nil then return nil, "unknown group" end
    P.tripsOf(gid, g)
    local why = Ex.departBlocker(g, minute)
    if why ~= nil then return nil, why end
    if not LivingKnox.Decisions.materialized(g, LivingKnox.Store.isReady() and LivingKnox.Store.data() or nil) then
        return nil, "not materialized"
    end
    local want, wwhy = Ex.wantOf(gid)
    if want == nil then return nil, wwhy end
    local team = Ex.teamOf(g, gid, want)
    if #team < P.cfg().TEAM_MIN then return nil, "no forager free to leave" end
    local data = LivingKnox.Groups.state.data
    -- LK16-T08 : genres par priorité ; le premier permis à cette heure, qui répond aux manques et trouve un lieu, part.
    local hod = hourOfDay(minute)
    local target, twhy, kind
    for _, spec in ipairs(P.kindRegistry:list()) do
        if spec.hours(hod) and (spec.wanted == nil or spec.wanted(want)) then
            local tg, kwhy = spec.pickTarget(gid, g, want, data)
            if tg ~= nil then
                target, kind = tg, spec
                break
            end
            if kwhy ~= nil then twhy = kwhy end
        end
    end
    if target == nil then
        -- Heure où le genre de repli ne part pas : rien d'autre (raison du dernier genre essayé entre parenthèses).
        local fb = P.fallbackKind()
        if fb == nil or not fb.hours(hod) then
            return nil, "hour of day " .. hod .. (twhy ~= nil and (" (" .. twhy .. ")") or "")
        end
        Ex.stats.refused = Ex.stats.refused + 1
        return nil, twhy
    end
    if kind.wants ~= nil then want = kind.wants(want) end
    local c = P.cfg()
    local missing = 0
    for _, w in ipairs(want) do missing = missing + w.m end
    local cap = math.min(c.CARRY_PER_MEMBER * #team, c.CARRY_MAX, missing)
    local n
    local G = LivingKnox.Groups
    G.update(function(d)
        local live = d.groups[gid]
        if live == nil then return false, false end
        local s = live.trips
        if type(s) ~= "table" then s = { v = Ex.FORMAT, n = 0, seen = {} } end
        s.n = s.n + 1
        n = s.n
        s.cur = { n = n, phase = "out", team = team, want = want,
            target = { x = target.x, y = target.y, z = target.z, b = target.b, room = target.room,
                label = target.label }, start = minute, due = minute + c.OUT_MINUTES, cap = cap, carry = {},
            searched = {} }
        if not kind.fallback then s.cur.kind = kind.id end
        if kind.start ~= nil then kind.start(s.cur, target, team) end
        live.trips = s
        G.appendLog(live, "expedition", P.cut(string.format("trip %d to %s (%d squares): %s for %s", n, target.label,
            target.d, table.concat(team, " "), wantText(want))), G.today())
        return true, true
    end)
    Ex.stats.departed = Ex.stats.departed + 1
    LivingKnox.Log.info("expedition: group %s trip %d leaves for building %s %s at %d,%d,%d (%d squares, score %.1f): %s, "
        .. "wants %s, load %d", gid, n, target.b, target.label, target.x, target.y, target.z, target.d, target.score,
        table.concat(team, " "), wantText(want), cap)
    return n
end

P.isEmbodied = isEmbodied
