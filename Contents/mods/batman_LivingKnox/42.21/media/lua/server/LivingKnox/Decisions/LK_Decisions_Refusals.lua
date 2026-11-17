-- Living Knox : cadre de décision des PNJ, refus d'un ordre du moteur (E10-T03).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- ================================================================ E10-T03 : refus d'un ordre du moteur
-- Fiche docs/annexes/conception/contestation.md. Un membre INCARNÉ peut refuser un ordre du moteur : le guet (poste sentry,
-- Decisions.scoreGroup), le départ en expédition (LK_Expeditions.teamOf) ou sa place de combat dans la défense du
-- foyer (rôle "post" de LK_Defense, Decisions.evaluate). Règles simples et déterministes, sans LLM, dans cet ordre :
-- chef (ne refuse jamais), blessure, moral (loyauté chancelante), attitude (défense contre un joueur que le groupe
-- apprécie), rôle (ordre que son rôle ne permet pas). Conséquence bornée : le membre n'exécute pas cet ordre (un autre
-- prend le guet, l'équipe part sans lui, il quitte sa place de combat), garde mémoire et appartenance ; aucun champ
-- persistant (refus gardés en mémoire HOLD_MINUTES pour la même instance d'ordre). Annonce une seule fois par refus :
-- entrée « refusal » au journal du groupe (anglais, faits seulement) et réplique de gabarit traduite par chaque client
-- (LivingKnox.Speech.say, clé IGUI_LK_Refuse_<ordre>_<raison>), entendue par les joueurs à portée. Un membre non
-- incarné n'est jamais jugé ici : la contestation hors écran reste l'événement « conflict » de LK_Simulation (LK09-T05).
-- Loyauté (E10-T03) : dérivée du moral du groupe et de l'ancienneté du membre (rang parmi les vivants), sans champ.
Decisions.ORDERS = { "guard", "expedition", "defend" }
Decisions.REFUSAL_REASONS = { "wound", "morale", "attitude", "role" }
Decisions.REFUSAL_KEY = "IGUI_LK_Refuse_"
Decisions.CFG.REFUSE = Decisions.CFG.REFUSE or {
    HEALTH = 0.6,         -- santé de référence / naissance sous laquelle un membre refuse un ordre
    SENIOR_BONUS = 20,    -- loyauté : points ajoutés au moral pour le plus ancien vivant (0 pour le dernier arrivé)
    LOYAL = 60,           -- loyauté >= LOYAL : "loyal"
    WAVERING = 30,        -- loyauté < WAVERING : "wavering" (moral très bas) : refuse les ordres
    HOLD_MINUTES = 240,   -- minutes de jeu : un refus vaut pour la même instance d'ordre, puis il est rejugé
}
-- Comportements de rôle exigés par un ordre (règle « rôle ») ; defend : tout rôle défend (LK06-T07).
Decisions.ORDER_NEEDS = { guard = Decisions.DUTY_NEEDS.sentry, expedition = Decisions.DUTY_NEEDS.forager }
-- Niveaux d'attitude (LK_Hostility) d'un joueur que le groupe apprécie : un membre refuse de le combattre.
Decisions.FRIENDLY_LEVELS = { trusting = true, favorable = true }

-- Rang d'ancienneté du membre mid parmi les membres vivants de g (1 = plus ancien) et nombre de vivants.
function Decisions.seniorityOf(g, mid)
    local G = LivingKnox.Groups
    local mine = G.memberNumber(mid) or 0
    local older, alive = 0, 0
    for other, m in pairs(g.members or {}) do
        if m.alive then
            alive = alive + 1
            if other ~= mid and (G.memberNumber(other) or 0) < mine then older = older + 1 end
        end
    end
    return older + 1, alive
end

-- Loyauté (pur) : moral du groupe (0..100) + SENIOR_BONUS x ancienneté (1 pour le plus ancien des count vivants, 0
-- pour le dernier arrivé). Rend "loyal" | "steady" | "wavering" et le score entier.
function Decisions.loyaltyOf(morale, rank, count)
    local c = P.cfg().REFUSE
    morale = LivingKnox.Num.finite(morale) and LivingKnox.Num.clamp(morale, 0, 100) or 50
    local seniority = 0
    if LivingKnox.Num.finite(rank) and LivingKnox.Num.finite(count)
        and count > 1 then seniority = LivingKnox.Num.clamp((count - rank) / (count - 1), 0, 1) end
    local score = math.floor(morale + c.SENIOR_BONUS * seniority + 0.5)
    if score >= c.LOYAL then return "loyal", score end
    if score < c.WAVERING then return "wavering", score end
    return "steady", score
end

-- Loyauté du membre mid du groupe g (registre).
function Decisions.loyaltyOfMember(g, mid)
    local rank, count = Decisions.seniorityOf(g, mid)
    return Decisions.loyaltyOf(g.morale, rank, count)
end

-- Refus d'un ordre (pur). r = { order (ORDERS), leader (booléen), health (0..1 ou nil), loyalty, score, role, allowed
-- (ensemble des comportements du rôle), playerLevel (attitude du groupe envers le joueur visé par la défense, ou
-- nil) }. Rend la raison (REFUSAL_REASONS) et son détail anglais, ou nil (ordre accepté).
function Decisions.refusalOf(r)
    local c = P.cfg().REFUSE
    if r.leader then return nil end
    if r.health ~= nil and r.health < c.HEALTH then
        return "wound", string.format("health %d%% < %d%%", math.floor(r.health * 100 + 0.5),
            math.floor(c.HEALTH * 100 + 0.5))
    end
    if r.loyalty == "wavering" then return "morale", "loyalty " .. tostring(r.score) .. " < " .. c.WAVERING end
    if r.order == "defend" and r.playerLevel ~= nil and Decisions.FRIENDLY_LEVELS[r.playerLevel] then
        return "attitude", "player is " .. tostring(r.playerLevel)
    end
    local need = Decisions.ORDER_NEEDS[r.order]
    if need ~= nil and not P.anyOf(r.allowed or {}, need) then
        return "role", "role " .. tostring(r.role) .. " not fit"
    end
    return nil
end

-- Jugement de l'ordre order (instance key) donné au membre incarné mid à la minute minute (autorité). extra =
-- { playerLevel } pour la défense. Rend la raison et le détail d'un refus, ou nil. Un refus encore valable (même
-- instance, HOLD_MINUTES) est rendu sans nouvelle annonce ; un nouveau refus est mis en file (flushRefusals).
function Decisions.judgeOrder(gid, g, mid, m, order, key, minute, extra)
    local id = m and m.npc or nil
    if id == nil or not LivingKnox.Num.finite(minute) then return nil end
    local all = P.bucket("refusals")
    local mine = all[id]
    local rec = mine ~= nil and mine[order] or nil
    -- Refus encore valable : à moins de HOLD_MINUTES de son jugement, dans un sens ou dans l'autre. Le guet est jugé à
    -- l'heure pleine (refuseDuties : heure x 60), les autres appelants à la minute près : un jugement à 23 h 25 puis
    -- un autre à « 23 h 00 » est le même refus (essai en jeu du 2026-10-13, lk.contest : refus annoncé deux fois).
    if rec ~= nil and rec.key == key and math.abs(minute - rec.since) < rec.untilMin - rec.since then
        return rec.reason, rec.why
    end
    local level, score = Decisions.loyaltyOfMember(g, mid)
    local reason, why = Decisions.refusalOf({ order = order, leader = g.leader == mid, health = Decisions.healthOf(m),
        loyalty = level, score = score, role = m.role, allowed = Decisions.allowedOf(g.type, m.role),
        playerLevel = extra and extra.playerLevel or nil })
    if reason == nil then
        if mine ~= nil then mine[order] = nil end
        return nil
    end
    all[id] = mine or {}
    all[id][order] = { key = key, reason = reason, why = why, since = minute,
        untilMin = minute + P.cfg().REFUSE.HOLD_MINUTES }
    local q = P.bucket("refusalQueue")
    q[#q + 1] = { gid = gid, mid = mid, npc = id, order = order, reason = reason, why = why }
    Decisions.stats.orderRefusals = (Decisions.stats.orderRefusals or 0) + 1
    LivingKnox.Log.info("npc %s (%s %s) refuses the %s order: %s (%s)", id, gid, mid, order, reason, why)
    return reason, why
end

-- Refus actif (copie) du PNJ id pour l'ordre order, ou nil : { key, reason, why, since, untilMin }.
function Decisions.refusalFor(id, order)
    local mine = P.bucket("refusals")[id]
    local rec = mine ~= nil and mine[order] or nil
    if rec == nil then return nil end
    local out = {}
    for k, v in pairs(rec) do out[k] = v end
    return out
end

-- Guet (appelé par scoreGroup dans l'écriture du registre) : chaque membre incarné à qui le guet échoit est jugé ;
-- un refus le rend inapte au poste sentry (members[i].refuses). Rend vrai si un nouveau membre refuse (postes à refaire).
function Decisions.refuseDuties(gid, g, members, duties, hour)
    local registry = P.registryOfBodies()
    local any = false
    for _, gm in ipairs(members) do
        local m = g.members[gm.mid]
        if duties[gm.mid] == "sentry" and m ~= nil and P.isEmbodied(m, registry)
            and not (gm.refuses ~= nil and gm.refuses.sentry)
            and Decisions.judgeOrder(gid, g, gm.mid, m, "guard", "sentry", hour * 60) ~= nil then
            gm.refuses = gm.refuses or {}
            gm.refuses.sentry = true
            any = true
        end
    end
    return any
end

-- Défense (appelée par evaluate) : place de combat (rôle "post") refusée -> le membre quitte la défense (ctx.defense
-- effacé) et ne combat aucun joueur (cible joueur effacée ; un zombie à portée reste combattu, LK06-T07).
function Decisions.judgeDefense(gid, g, mid, m, ctx, players, minute)
    local dv = ctx.defense
    if dv == nil or dv.role ~= "post" then return nil end
    local level
    local tg = dv.target or ctx.target
    if tg ~= nil and tg.kind ~= "zombie" and tg.u ~= nil then level = P.attitudesFor(gid, g, players)[tg.u] end
    local reason = Decisions.judgeOrder(gid, g, mid, m, "defend", "defense " .. tostring(dv.id), minute,
        { playerLevel = level })
    if reason == nil then return nil end
    ctx.defense = nil
    if ctx.target ~= nil and ctx.target.kind ~= "zombie" then ctx.target = nil end
    ctx.refused = reason
    return reason
end

-- Annonce des refus en file : journal du groupe (Groups.addLog, kind "refusal") et réplique de gabarit entendue par
-- les joueurs à portée (LivingKnox.Speech.say ; module absent ou personne à portée : journal seul). Rend le nombre.
function Decisions.flushRefusals()
    local q = Decisions.state.refusalQueue
    if q == nil or #q == 0 then return 0 end
    Decisions.state.refusalQueue = {}
    local G, Sp = LivingKnox.Groups, LivingKnox.Speech
    for _, r in ipairs(q) do
        local text = string.sub(string.format("%s refused the %s order: %s (%s)", r.mid, r.order, r.reason, r.why), 1,
            G.TEXT_MAX)
        local ok, err = G.addLog(r.gid, "refusal", text)
        if not ok then LivingKnox.Log.warn("group %s: refusal of %s not logged: %s", r.gid, r.mid, tostring(err)) end
        if Sp ~= nil and Sp.say ~= nil then
            local out, why = Sp.say(r.npc, { key = Decisions.REFUSAL_KEY .. r.order .. "_" .. r.reason })
            if out == nil then LivingKnox.Log.debug("npc %s: refusal line not heard: %s", r.npc, tostring(why)) end
        end
    end
    return #q
end
