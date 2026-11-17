-- Living Knox : cadre de décision des PNJ, contexte d'un membre (perception, cible, membres valides proches ;
-- LK16-T05, LK06-T07).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- Perception per du membre, plus le zombie qu'il combat (cible du serveur, Zombies.targetFor) quand elle ne le porte
-- pas encore. Sur un serveur, la perception vient du rapport du propriétaire, en retard d'une seconde ou plus ; le
-- membre pouvait tuer un zombie à 3 cases avant que l'alerte du groupe ne soit levée (campagne MP du 2026-10-14). En
-- solo la perception le porte déjà : rien n'est ajouté. Rend per, ou une copie complétée.
function Decisions.withTarget(per, tg)
    if not isServer() or tg == nil or tg.zombie == nil then return per end
    local z = tg.zombie
    local o = z:getOnlineID()
    if type(o) ~= "number" or o == -1 then return per end
    local known
    for i, e in ipairs(per and per.z or {}) do
        -- Connu du propriétaire sans être vu ni entendu (dans son dos) : la ligne dégagée du serveur fait foi
        -- (campagne MP du 2026-11-13 : garde qui tire, aucune alerte). Résumé périmé : reconstruit plus bas.
        if e.o == o and not per.stale then
            if e.s or e.h then return per end
            known = i
        end
    end
    local fresh = per ~= nil and not per.stale   -- résumé périmé : seul le fait du serveur compte
    local out = { z = {}, p = fresh and per.p or {}, n = fresh and per.n or {}, stale = false }
    if fresh then
        for k, v in pairs(per) do
            if out[k] == nil then out[k] = v end
        end
        for i, e in ipairs(per.z or {}) do
            if i ~= known then out.z[#out.z + 1] = e end
        end
    end
    out.z[#out.z + 1] = { o = o, x = z:getX(), y = z:getY(), z = z:getZ(), a = 1, s = true, h = false, d = tg.d or 0 }
    return out
end

-- Contexte d'un membre incarné (corps body) pour Decisions.decide : champs propres au membre, puis ceux des
-- fournisseurs inscrits (Decisions.registerContext, dans leur ordre), puis les entrées des extensions (input).
function Decisions.context(gid, g, mid, m, body, players, minute)
    local allowed = Decisions.allowedOf(g.type, m.role)
    local x, y, z = body:getX(), body:getY(), body:getZ()
    local ctx = { id = m.npc, gid = gid, mid = mid, role = m.role, allowed = allowed,
        combatant = P.anyOf(allowed, Decisions.COMBAT_BEHAVIOURS), x = x, y = y, z = math.floor(z), home = g.home,
        health = Decisions.healthOf(m), duty = m.duty, objective = g.objective,
        night = Decisions.isNight(math.floor(minute / 60)), minute = minute }
    local src = { gid = gid, g = g, mid = mid, m = m, body = body, players = players, minute = minute }
    for _, p in ipairs(Decisions.contextProviders) do p.fill(ctx, src) end
    for _, ext in ipairs(Decisions.extensions) do   -- LK05-T20 : entrées des extensions (registre)
        if ext.input ~= nil then ext.input(ctx, body, minute) end
    end
    return ctx
end

-- Perception du membre id (LivingKnox.Senses.perceived, module partagé chargé avant ce registre : lu ici), ou nil.
function Decisions.perceptionOf(id)
    local S = LivingKnox.Senses
    if S == nil or S.perceived == nil then return nil end
    return S.perceived(id)
end

-- Cible d'attaque d'un membre : un combattant prend la cible de LivingKnox.Combat (joueurs vus, Hostility.chooseTarget,
-- LK06-T02) ; LK06-T07 : tout autre rôle se bat contre un zombie à portée (Zombies.targetFor, jamais contre un joueur).
function Decisions.targetOf(ctx, src)
    if ctx.combatant then
        local C = LivingKnox.Combat
        if C ~= nil and C.targetFor ~= nil then return C.targetFor(src.gid, ctx.id, src.per, src.players) end
        return nil
    end
    local Zm = LivingKnox.Zombies
    if Zm ~= nil and Zm.targetFor ~= nil then return Zm.targetFor(ctx.id) end
    return nil
end

-- LK06-T07 : membres valides (Decisions.unfitOf : santé et peur) du groupe gid, incarnés, au même niveau et à
-- OVERWHELM.RADIUS cases au plus de (x, y), le membre évalué compris.
function Decisions.ableNear(gid, g, x, y, z)
    local B = LivingKnox.Bodies
    if B == nil or B.find == nil then return 0 end
    local n = 0
    local radius = P.cfg().OVERWHELM.RADIUS
    for mid, m in pairs(g.members or {}) do
        local body = m.alive and m.npc ~= nil and B.find(m.npc) or nil
        if body ~= nil and not body:isDead() and math.floor(body:getZ()) == z
            and LivingKnox.Geo.cheb(body:getX(), body:getY(), x, y) <= radius
            and Decisions.unfitOf({ health = Decisions.healthOf(m), needs = Decisions.needsOf(gid, mid) }) == nil then
            n = n + 1
        end
    end
    return n
end
