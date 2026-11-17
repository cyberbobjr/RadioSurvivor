-- Living Knox : cadre de décision des PNJ, évaluation des membres incarnés, passages étalés (LK13-T11) et
-- lecture des évaluations pour les accords (E09-T05).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- Évalue un membre incarné : décision, état gardé ou remplacé, application. Rend vrai si une décision a été prise.
function Decisions.evaluate(gid, g, mid, m, body, players, minute)
    local id = m.npc
    Decisions.stats.evaluated = Decisions.stats.evaluated + 1
    Decisions.markEvaluated(id)   -- E09-T05 : passage de décision constaté par Decisions.aims
    if P.externalDirective(id) ~= nil then
        Decisions.stats.external = Decisions.stats.external + 1
        return false
    end
    local ctx = Decisions.context(gid, g, mid, m, body, players, minute)
    Decisions.judgeDefense(gid, g, mid, m, ctx, players, minute)   -- E10-T03 : poste de défense refusé
    local out = Decisions.decide(ctx)
    if out == nil then return false end
    if out.rule == "threat" and out.b ~= "alert" and out.b ~= "defend" then
        P.noteThreat(gid, out.key, math.floor(minute / 60))
    end
    local st = Decisions.state.members[id]
    local prev = st
    -- LK04-T05 : notre consigne close en échec "stuck" (LK_Movement) : échéance avancée, la cascade choisit une autre
    -- consigne (la case du blocage est refusée à ce PNJ par Directives.moveTo pendant Movement.AVOID_MS).
    local Mv = LivingKnox.Movement
    if st ~= nil and Mv ~= nil and Mv.takeStuck ~= nil and Mv.takeStuck(id, Decisions.state.issued[id]) then
        st.untilMin = minute
        LivingKnox.Log.info("npc %s: %s directive stuck, decision taken again", id, tostring(st.b))
    end
    local fresh, why = Decisions.replaces(st, out, minute)
    if fresh and st ~= nil and st.b == "sleep" and out.rule == "threat" and ctx.alert ~= nil then
        local A = LivingKnox.Alert   -- LK05-T08 : dormeur réveillé par l'alerte
        if A ~= nil and A.noteWoken ~= nil then A.noteWoken(gid, id) end
    end
    if fresh then
        out.gid, out.mid = gid, mid
        Decisions.state.members[id] = out
        st = out
        Decisions.stats.decided = Decisions.stats.decided + 1
        LivingKnox.Log.debug("npc %s (%s %s %s): %s -> %s until minute %d (%s)", id, gid, mid, tostring(m.role), out.rule, out.b,
            out.untilMin, out.why .. ", " .. why)
        local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement, aucune décision changée)
        if Ac ~= nil then Ac.behaviour(gid, mid, id, prev, out, why) end
    else
        Decisions.stats.kept = Decisions.stats.kept + 1
    end
    P.afterDecision(gid, g, mid, m, body, st, prev, ctx, fresh, minute)   -- LK06-T05
    Decisions.apply(id, st, ctx, fresh)
    local N = LivingKnox.Needs   -- LK05-T06 : activité de l'heure pour le pas horaire des besoins
    if N ~= nil and N.observe ~= nil then N.observe(gid, mid, st.b, ctx.home == nil or ctx.atHome, minute) end
    for _, x in ipairs(Decisions.extensions) do   -- LK05-T20 : suites des extensions (registre)
        if x.observe ~= nil then x.observe(ctx, st, body, minute) end
    end
    return fresh
end

-- Liste des membres incarnés dont le corps est relié : { { gid, mid, npc }, ... } triée (groupe, numéro de membre).
function Decisions.buildRoster()
    local out = {}
    local G = LivingKnox.Groups
    local registry = P.registryOfBodies()
    local data = G.isReady() and G.state.data or nil
    if data == nil or registry == nil then return out end
    local B = LivingKnox.Bodies
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids)
    for _, gid in ipairs(ids) do
        local g = data.groups[gid]
        local mids = {}
        for mid, m in pairs(g.members) do
            if m.alive and P.isEmbodied(m, registry) and B ~= nil and B.find(m.npc) ~= nil then mids[#mids + 1] = mid end
        end
        table.sort(mids, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
        for _, mid in ipairs(mids) do out[#out + 1] = { gid = gid, mid = mid, npc = g.members[mid].npc } end
    end
    local keep = {}
    for _, r in ipairs(out) do keep[r.npc] = true end
    local gone = {}
    for id in pairs(Decisions.state.members) do
        if not keep[id] then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do Decisions.forget(id) end
    return out
end

function Decisions.forget(id)
    Decisions.state.members[id] = nil
    Decisions.evals.at[id] = nil   -- E09-T05
    P.bucket("refusals")[id] = nil   -- E10-T03
    Decisions.state.issued[id] = nil
    Decisions.setAlertGesture(id, nil)   -- LK06-T12 : geste d'alerte ou de reddition retiré (mort, corps parti)
    P.bucket("hits")[id] = nil   -- LK06-T05 : coup reçu, reddition de ce PNJ
    for _, per in pairs(P.bucket("surrenders")) do
        local gone = {}
        for u, s in pairs(per) do
            if s.npc == id then gone[#gone + 1] = u end
        end
        for _, u in ipairs(gone) do per[u] = nil end
    end
    local R = LivingKnox.Routines
    if R ~= nil then R.forget(id) end
    for _, x in ipairs(Decisions.extensions) do   -- LK05-T20, LK16-T06 : oubli (forget), sinon sortie (leave)
        if x.forget ~= nil then x.forget(id) elseif x.leave ~= nil then x.leave(id) end
    end
end

-- Passage des membres : au plus MEMBERS_PER_PASS choisis, tour à tour. Liste refaite toutes les ROSTER_MS, ou à
-- chaque passage tant qu'elle est vide (un membre incarné entre-temps attend au plus ROSTER_MS). LK13-T11 : les
-- membres choisis sont évalués MEMBERS_PER_FRAME par image (Decisions.memberStep), le premier dans l'image du
-- passage, les suivants aux images qui suivent (300 ms au plus sur un serveur dédié) : même fréquence par membre,
-- coût d'une image borné à un membre. Chaque membre est relu (groupe, membre, corps) et évalué avec l'heure et les
-- joueurs de son image. Un passage suivant remplace ce qui reste du précédent. Rend le nombre évalué dans l'image.
function Decisions.memberPass(t)
    local st = Decisions.state
    t = t or P.now()
    if st.rosterMs == nil or t - st.rosterMs >= P.cfg().ROSTER_MS or #st.roster == 0 then
        st.roster = Decisions.buildRoster()
        st.rosterMs = t
    end
    local roster = st.roster
    local n = #roster
    st.batch, st.batchHead = nil, 1
    if n == 0 then return 0 end
    local minute = Decisions.currentMinute()
    if minute == nil then return 0 end
    local A = LivingKnox.Alert   -- LK05-T08 : alertes retombées closes (écouteurs « calm »)
    if A ~= nil and A.update ~= nil then A.update(minute) end
    local batch = {}
    for _ = 1, math.min(n, P.cfg().MEMBERS_PER_PASS) do
        st.cursor = (st.cursor % n) + 1
        batch[#batch + 1] = roster[st.cursor]
    end
    st.batch = batch
    Decisions.stats.passes = Decisions.stats.passes + 1
    return Decisions.memberStep()
end

-- Membres du passage en cours évalués dans cette image (au plus MEMBERS_PER_FRAME ; un membre sans corps est passé
-- sans compter). Rend le nombre évalué.
function Decisions.memberStep()
    local st = Decisions.state
    local batch = st.batch
    if batch == nil then return 0 end
    local minute = Decisions.currentMinute()
    if minute == nil then return 0 end
    local hour = math.floor(minute / 60)
    local G = LivingKnox.Groups
    local data = G.state.data
    local B = LivingKnox.Bodies
    local players = B ~= nil and B.livingPlayers ~= nil and B.livingPlayers() or {}
    local done, budget = 0, math.max(1, P.cfg().MEMBERS_PER_FRAME or 1)
    while done < budget and st.batchHead <= #batch do
        local r = batch[st.batchHead]
        st.batchHead = st.batchHead + 1
        local g = data and data.groups[r.gid] or nil
        local m = g and g.members[r.mid] or nil
        local body = m and m.alive and m.npc == r.npc and B.find(r.npc) or nil
        if body ~= nil then
            -- Groupe noté à son arrivée ; LK13-T11 : pas s'il le sera par la notation de l'heure encore en attente
            -- (passe différée de LK_Simulation ou file de notation) : ses membres gardent d'ici là l'objectif et les
            -- postes de l'heure précédente (quelques images).
            if st.scored[r.gid] ~= hour and not Decisions.hourScoringPending(r.gid, hour) then
                Decisions.scorePass(hour, r.gid)
            end
            Decisions.evaluate(r.gid, g, r.mid, m, body, players, minute)
            done = done + 1
        end
    end
    if st.batchHead > #batch then st.batch = nil end
    Decisions.flushRefusals()   -- E10-T03 : refus de la défense et des expéditions (LK_Expeditions.teamOf)
    local stats = Decisions.stats
    if done > stats.maxPerPass then stats.maxPerPass = done end   -- LK13-T11 : membres évalués dans une image
    return done
end

function Decisions.tick()
    if not LivingKnox.isAuthority() or getCell() == nil then return end
    if not LivingKnox.Config.isEnabled() then return end
    local t = P.now()
    local st = Decisions.state
    if st.lastPass ~= nil and t - st.lastPass < P.cfg().PASS_MS then
        if st.batch ~= nil and LivingKnox.Groups.isReady() then Decisions.memberStep() end   -- LK13-T11 : suite du passage
        return
    end
    st.lastPass = t
    if not LivingKnox.Groups.isReady() then return end
    Decisions.memberPass(t)
end

-- Note l'évaluation du membre id ; rend son numéro.
function Decisions.markEvaluated(id)
    local e = Decisions.evals
    e.seq = e.seq + 1
    e.at[id] = e.seq
    return e.seq
end

-- Joueur visé par le membre id : engagement de LK_Combat contre un joueur (mêlée, tir, défense du foyer), sinon
-- comportement « fight » ou « warn » de la cascade (clé "p<compte>"). Compte ou nil.
local function aimedAccount(id)
    local C = LivingKnox.Combat
    local o = C ~= nil and C.get ~= nil and C.get(id) or nil
    if o ~= nil and o.k ~= "zombie" and type(o.u) == "string" then return o.u end
    local st = Decisions.state.members[id]
    if st ~= nil and (st.b == "fight" or st.b == "warn") and type(st.key) == "string"
            and string.sub(st.key, 1, 1) == "p" then
        return string.sub(st.key, 2)
    end
    return nil
end

-- Lecture seule, pour l'application d'un accord : { seq = dernier numéro d'évaluation, members = { { npc, eval =
-- numéro de sa dernière évaluation ou nil, active = vrai s'il a un état de décision ou un engagement, u = compte du
-- joueur visé ou nil }, ... } } pour chaque membre vivant du groupe gid (ordre des numéros de membre), ou nil.
function Decisions.aims(gid)
    local G = LivingKnox.Groups
    local g = G.isReady() and G.state.data.groups[gid] or nil
    if g == nil then return nil end
    local mids = {}
    for mid, m in pairs(g.members) do
        if m.alive and type(m.npc) == "string" then mids[#mids + 1] = mid end
    end
    table.sort(mids, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
    local out = {}
    local C = LivingKnox.Combat
    for _, mid in ipairs(mids) do
        local id = g.members[mid].npc
        local engaged = C ~= nil and C.get ~= nil and C.get(id) ~= nil
        out[#out + 1] = { npc = id, eval = Decisions.evals.at[id],
            active = Decisions.state.members[id] ~= nil or engaged, u = aimedAccount(id) }
    end
    return { seq = Decisions.evals.seq, members = out }
end
