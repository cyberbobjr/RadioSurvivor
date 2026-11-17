-- Living Knox : expéditions, passage par minute, lectures et abandon
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ passage par minute

-- Contrôles d'une expédition en cours : équipe morte, délais des phases, dépôt en attente.
local function watch(gid, minute)
    local t, g = P.curOf(gid)
    if t == nil then return end
    if t.phase == "deliver" then
        Ex.deliver(gid)
        return
    end
    if not Ex.ACTIVE[t.phase] then return end
    local alive = 0
    for _, mid in ipairs(t.team) do
        local m = g.members[mid]
        if m ~= nil and m.alive then alive = alive + 1 end
    end
    if alive == 0 then
        local G = LivingKnox.Groups
        G.update(function(d)
            local live = d.groups[gid]
            local s = live and live.trips or nil
            if s == nil or s.cur == nil or s.cur.n ~= t.n then return false, false end
            s.cur, s.last = nil, minute
            G.appendLog(live, "return", P.cut(string.format("trip %d: no one came back from %s", t.n,
                tostring(t.target.label))), G.today())
            return true, true
        end)
        Ex.state.carried[gid .. "#" .. t.n] = nil
        LivingKnox.Log.info("expedition: group %s trip %d over: no member of the team alive", gid, t.n)
        return
    end
    if minute < t.due then return end
    if t.phase == "out" then
        P.setPhase(gid, t.n, "back", minute, "never reached the building")
    elseif t.phase == "search" then
        P.setPhase(gid, t.n, "back", minute, "search time over")
    elseif t.phase == "back" then
        P.setPhase(gid, t.n, "deliver", minute, "return time over")
        Ex.deliver(gid)
    end
end

-- Chaque minute de jeu : expéditions en cours surveillées, départs examinés. Rend le nombre de départs.
function Ex.minutePass()
    if not LivingKnox.isAuthority() or getCell() == nil then return 0 end
    local Config = LivingKnox.Config
    if Config.isEnabled ~= nil and not Config.isEnabled() then return 0 end
    local G = LivingKnox.Groups
    if not G.isReady() then return 0 end
    local minute = LivingKnox.Decisions.currentMinute()
    if minute == nil then return 0 end
    local n = 0
    for _, gid in ipairs(G.list()) do
        local g = P.liveGroup(gid)
        if g ~= nil then
            P.tripsOf(gid, g)
            local ok, err = pcall(watch, gid, minute)
            if not ok then LivingKnox.Log.error("expedition: group %s watch failed: %s", gid, tostring(err)) end
            local last = Ex.state.checked[gid]
            if g.trips == nil or g.trips.cur == nil then
                if type(last) ~= "number" or minute - last >= P.cfg().CHECK_MINUTES or minute < last then
                    Ex.state.checked[gid] = minute
                    local okD, res, why = pcall(Ex.tryDepart, gid, minute)
                    if not okD then
                        LivingKnox.Log.error("expedition: group %s departure failed: %s", gid, tostring(res))
                    elseif res ~= nil then
                        n = n + 1
                    elseif why ~= nil then
                        LivingKnox.Log.debug("expedition: group %s stays home: %s", gid, tostring(why))
                    end
                end
            end
        end
    end
    return n
end

-- Expédition en cours du groupe gid (copie), ou nil.
function Ex.get(gid)
    local t = P.curOf(gid)
    if t == nil then return nil end
    return LivingKnox.Groups.copy(t)
end

-- Mémoire d'un membre (copie), ou nil.
function Ex.memberState(id)
    local m = Ex.state.npcs[id]
    if m == nil then return nil end
    return LivingKnox.Groups.copy(m)
end

-- Objets portés en mémoire par l'expédition n du groupe gid : nombre.
function Ex.carriedCount(gid, n)
    local k = 0
    for _ in pairs(Ex.state.carried[gid .. "#" .. n] or {}) do k = k + 1 end
    return k
end

-- Expédition abandonnée (suites, administration) : registre effacé (expédition abstraite liée comprise) ; les objets
-- portés sont perdus, jamais recréés. Rend vrai si une expédition était en cours.
function Ex.cancel(gid, why)
    local t = P.curOf(gid)
    if t == nil then return false end
    LivingKnox.Groups.update(function(d)
        local live = d.groups[gid]
        if live == nil or live.trips == nil then return false, false end
        live.trips.cur = nil
        if type(live.expedition) == "table" and live.expedition.trip == t.n then live.expedition = nil end
        return true, true
    end)
    Ex.state.carried[gid .. "#" .. t.n] = nil
    LivingKnox.Log.info("expedition: group %s trip %d cancelled (%s)", gid, t.n, tostring(why))
    return true
end
