-- Living Knox : expéditions, forme de l'historique au registre des groupes et expédition en cours d'un membre
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

local M = 2147483647

-- ================================================================ registre (forme)

local function validStrList(list, max, pred)
    if type(list) ~= "table" then return false end
    local n = 0
    for k in pairs(list) do
        if not LivingKnox.Num.isInt(k, 1, max) then return false end
        n = n + 1
    end
    if n > 0 and list[n] == nil then return false end
    for i = 1, n do
        if not pred(list[i]) then return false end
    end
    return true
end

local function shortText(v) return type(v) == "string" and #v > 0 and #v <= 96 end

-- Expédition en cours bien formée. Rend vrai, ou faux et une raison.
function Ex.validCur(t)
    if type(t) ~= "table" then return false, "trip is not a table" end
    if not LivingKnox.Num.isInt(t.n, 1, M) or not Ex.PHASES[t.phase] then return false, "bad trip number or phase" end
    if not validStrList(t.team, LivingKnox.Groups.MAX_MEMBERS,
        function(v) return LivingKnox.Groups.memberNumber(v) ~= nil end) then
        return false, "bad team"
    end
    if not validStrList(t.want, #LivingKnox.Stock.CATEGORIES, function(w)
        return type(w) == "table" and P.CATS[w.c] == true and LivingKnox.Num.isInt(w.m, 0, 1000)
    end) then
        return false, "bad wants"
    end
    local tg = t.target
    if type(tg) ~= "table" or not LivingKnox.Num.isInt(tg.x, 0, M) or not LivingKnox.Num.isInt(tg.y, 0, M)
        or not LivingKnox.Num.isInt(tg.z, -32, 31)
        or not shortText(tg.b) then
        return false, "bad target"
    end
    if not LivingKnox.Num.isInt(t.start, 0, M) or not LivingKnox.Num.isInt(t.due, 0, M)
        or not LivingKnox.Num.isInt(t.cap, 0, 1000) then
        return false, "bad times or load"
    end
    if not validStrList(t.carry, 1000, function(e)
        return type(e) == "table" and type(e.t) == "string" and #e.t > 0 and #e.t <= 128 and P.CATS[e.c] == true
            and (e.i == nil or LivingKnox.Num.isInt(e.i, -2147483648, 2147483647)) and (e.a == nil or e.a == true)
            and (e.f == nil or e.f == true)
    end) then
        return false, "bad load"
    end
    if not validStrList(t.searched, 1000, shortText) then return false, "bad searched list" end
    local kind = Ex.kindOf(t)
    if kind == nil then return false, "unknown kind" end
    if kind.valid ~= nil then return kind.valid(t) end
    return true
end

-- Champs d'un genre à tirages (valid d'un genre) : tirages faits k et prévus r, zone ou rive visée (room).
function Ex.drawnValid(t)
    if not LivingKnox.Num.isInt(t.k, 0, 1000) or not LivingKnox.Num.isInt(t.r, 0, 1000) or not shortText(t.target.room) then
        return false, "bad foraging rounds"
    end
    return true
end

-- Historique des expéditions bien formé. Rend vrai, ou faux et une raison.
function Ex.validTrips(s)
    if type(s) ~= "table" or s.v ~= Ex.FORMAT then return false, "unknown format" end
    if not LivingKnox.Num.isInt(s.n, 0, M) or (s.last ~= nil and not LivingKnox.Num.isInt(s.last, 0, M)) then
        return false, "bad counters"
    end
    if not validStrList(s.seen, P.cfg().SEEN_MAX, shortText) then return false, "bad seen list" end
    if s.cur ~= nil then return Ex.validCur(s.cur) end
    return true
end

-- Historique du groupe g (registre vivant) ; malformé : oublié (avertissement), expédition en cours abandonnée.
local function tripsOf(gid, g)
    local s = g.trips
    if s == nil then return nil end
    local ok, why = Ex.validTrips(s)
    if ok then return s end
    LivingKnox.Log.warn("expedition: group %s trip record dropped (%s)", gid, tostring(why))
    g.trips = nil
    return nil
end

local function liveGroup(gid)
    local G = LivingKnox.Groups
    local data = G.isReady() and G.state.data or nil
    return data and data.groups[gid] or nil
end

-- Expédition en cours (registre vivant) du groupe gid, ou nil.
local function curOf(gid)
    local g = liveGroup(gid)
    local s = g and g.trips or nil
    if type(s) ~= "table" or type(s.cur) ~= "table" then return nil end
    return s.cur, g
end

-- Expédition du membre mid (contexte du cadre de décision, LK_Decisions) : { n, phase } si une expédition en cours
-- le compte dans son équipe et le mène (out, search, back), sinon nil.
function Ex.memberTrip(gid, mid)
    local t = curOf(gid)
    if t == nil or not Ex.ACTIVE[t.phase] or not P.inList(t.team, mid) then return nil end
    return { n = t.n, phase = t.phase }
end

P.tripsOf, P.liveGroup, P.curOf = tripsOf, liveGroup, curOf
