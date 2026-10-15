-- Living Knox : journal d'activité fin des groupes et activité en direct de leurs PNJ (LK13-T14), côté autorité.
-- Fiche : docs/conception/administration.md, section « Panneau de debug des PNJ ».
--
-- Journal d'activité : EN MÉMOIRE seulement (jamais sauvegardé, aucune écriture de registre), MAX lignes par groupe
-- (anneau : la plus ancienne est remplacée), effacé au redémarrage. Chaque ligne : { s = numéro croissant (toutes
-- groupes confondus), m = minute de jeu (âge du monde en minutes), k = sorte (KINDS), mid, npc, t = texte anglais court
-- (au plus TEXT_MAX caractères) }. Points d'écoute (appels gardés par « LivingKnox.Activity ~= nil », aucune décision
-- changée) :
--   behaviour : LK_Decisions.evaluate, décision renouvelée dont le comportement, la règle ou la cible change
--               (« home -> meal (rule hunger: hunger 95) ») ;
--   objective : LK_Decisions.scoreGroup, objectif ou postes du groupe changés (relève de quart comprise) ;
--   alert     : LK_Alert, écouteurs « raised » (déclenchée, aggravée) et « calm » (Alert.subscribe) ;
--   meal      : LK_Stock.takeMeal (objet mangé ou bu dans le stock du foyer) ;
--   care      : LK_Care.finish (soin appliqué) ;
--   combat    : LK_Combat.engage / disengage (mêlée ou tir), LK_Decisions.noteHit (coup reçu accepté).
-- Activité en direct d'un groupe : Activity.groupView (lue par l'opération "activity" de LK_Admin.lua, droits de
-- LK13-T13), copie de valeurs simples : membres (comportement, règle, raison, cible, échéance, routine, geste,
-- engagement, position, besoins, santé, blessure, incarné ou hors écran, expédition), journal sauvegardé du groupe et
-- lignes du journal d'activité postérieures au numéro « after » du demandeur (envoi incrémental).
-- Un client MP charge aussi media/lua/server : il s'arrête à la garde.
if isClient() then return end

require "LivingKnox/LK_Core"

local Activity = LivingKnox.Activity or {}
LivingKnox.Activity = Activity

Activity.MAX = 200          -- lignes gardées par groupe (décision du 2026-10-12)
Activity.TEXT_MAX = 160     -- caractères au plus par ligne
Activity.KINDS = { behaviour = true, objective = true, alert = true, meal = true, care = true, combat = true }

Activity.state = Activity.state or { seq = 0, groups = {} }   -- groups[gid] = { n = lignes écrites, items = anneau }
Activity.stats = Activity.stats or { notes = 0, replaced = 0, ignored = 0 }

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end
local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Minute de jeu courante (âge du monde en minutes), ou nil sans horloge.
function Activity.minute()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if not finite(hours) or hours < 0 then return nil end
    return math.floor(hours * 60 + 0.5)
end

-- Ajoute une ligne au journal d'activité du groupe gid. mid, npc facultatifs. Rend le numéro de la ligne, ou nil.
function Activity.note(gid, mid, kind, text, npc)
    if type(gid) ~= "string" or not Activity.KINDS[kind] then
        Activity.stats.ignored = Activity.stats.ignored + 1
        return nil
    end
    local st = Activity.state
    local buf = st.groups[gid]
    if buf == nil then
        buf = { n = 0, items = {} }
        st.groups[gid] = buf
    end
    text = tostring(text or "")
    if #text > Activity.TEXT_MAX then text = string.sub(text, 1, Activity.TEXT_MAX) end
    st.seq = st.seq + 1
    local slot = (buf.n % Activity.MAX) + 1
    if buf.items[slot] ~= nil then Activity.stats.replaced = Activity.stats.replaced + 1 end
    buf.items[slot] = { s = st.seq, m = Activity.minute(), k = kind, mid = type(mid) == "string" and mid or nil,
        npc = type(npc) == "string" and npc or nil, t = text }
    buf.n = buf.n + 1
    Activity.stats.notes = Activity.stats.notes + 1
    return st.seq
end

-- Même chose pour un PNJ dont on ne connaît que l'identifiant (groupe et membre retrouvés dans le registre).
function Activity.noteNpc(npc, kind, text)
    local G = LivingKnox.Groups
    if G == nil or G.findNpc == nil or type(npc) ~= "string" then return nil end
    local gid, mid = G.findNpc(npc)
    if gid == nil then return nil end
    return Activity.note(gid, mid, kind, text, npc)
end

-- Lignes du groupe gid de numéro > after (défaut 0), de la plus ancienne à la plus récente (copies), MAX au plus.
function Activity.entries(gid, after)
    local buf = Activity.state.groups[gid]
    local out = {}
    if buf == nil then return out end
    after = finite(after) and after or 0
    local count = math.min(buf.n, Activity.MAX)
    local first = buf.n - count            -- index (0..) de la plus ancienne ligne gardée
    for i = first, buf.n - 1 do
        local e = buf.items[(i % Activity.MAX) + 1]
        if e ~= nil and e.s > after then
            out[#out + 1] = { s = e.s, m = e.m, k = e.k, mid = e.mid, npc = e.npc, t = e.t }
        end
    end
    return out
end

-- Nombre de lignes gardées pour gid (0..MAX).
function Activity.count(gid)
    local buf = Activity.state.groups[gid]
    return buf and math.min(buf.n, Activity.MAX) or 0
end

-- Oubli du journal d'un groupe (groupe retiré) ou de tous (gid nil : nouvelle partie, tests).
function Activity.forget(gid)
    if gid == nil then
        Activity.state = { seq = Activity.state.seq, groups = {} }
    else
        Activity.state.groups[gid] = nil
    end
end

-- Points d'écoute ------------------------------------------------------------------------------------------------

-- Décision renouvelée (LK_Decisions.evaluate, fresh) : ligne seulement si le comportement, la règle ou la cible change.
function Activity.behaviour(gid, mid, npc, prev, out, why)
    if out == nil then return nil end
    if prev ~= nil and prev.b == out.b and prev.rule == out.rule and prev.key == out.key then return nil end
    local text = string.format("%s -> %s (rule %s: %s%s)%s", prev and tostring(prev.b) or "none", tostring(out.b),
        tostring(out.rule), tostring(out.why), out.key ~= nil and (", target " .. tostring(out.key)) or "",
        why == "interrupted" and " interrupted" or "")
    return Activity.note(gid, mid, "behaviour", text, npc)
end

local function alertText(info, event)
    if type(info) ~= "table" then return tostring(event) end
    local where = (info.x ~= nil) and (" at " .. tostring(info.x) .. "," .. tostring(info.y) .. "," .. tostring(info.z)) or ""
    return string.format("alert %s: %s %s, level %s%s%s", tostring(event), tostring(info.kind), tostring(info.label),
        tostring(info.level), where, info.spotter ~= nil and (", seen by " .. tostring(info.spotter)) or "")
end

-- Écouteurs de l'alerte (LK_Alert chargé après ce fichier dans l'ordre du jeu : inscription au chargement si possible,
-- sinon au démarrage de la partie ou du serveur ; même nom = même écouteur remplacé).
function Activity.hookAlert()
    local A = LivingKnox.Alert
    if A == nil or A.subscribe == nil then return false end
    return A.subscribe("Activity", {
        raised = function(gid, info, event)
            LivingKnox.Activity.note(gid, nil, "alert", alertText(info, event), info and info.spotter)
        end,
        calm = function(gid, info)
            LivingKnox.Activity.note(gid, nil, "alert", alertText(info, "calm"))
        end,
    })
end

Activity.hookAlert()
if Events ~= nil then
    LivingKnox.subscribe("OnGameStart", "Activity.hookAlert", function() LivingKnox.Activity.hookAlert() end)
    LivingKnox.subscribe("OnServerStarted", "Activity.hookAlertServer", function() LivingKnox.Activity.hookAlert() end)
end

-- Activité en direct d'un groupe -------------------------------------------------------------------------------------

local function onExpedition(g, mid)
    local e = g.expedition
    if type(e) ~= "table" or type(e.team) ~= "table" then return false end
    for _, id in ipairs(e.team) do
        if id == mid then return true end
    end
    return false
end

-- Activité d'un membre (valeurs simples). reg : registre des PNJ (Store.data()) ou nil.
local function memberView(gid, g, mid, m, reg)
    local v = { id = mid, npc = m.npc, role = m.role, profile = m.profile, alive = m.alive == true,
        leader = g.leader == mid, duty = m.duty, wound = m.wound or 0 }
    if not v.alive then return v end
    v.away = onExpedition(g, mid) or nil
    local id = m.npc
    local npc = reg ~= nil and type(id) == "string" and reg.npcs[id] or nil
    v.state = npc and npc.state or nil
    local N = LivingKnox.Needs
    local n = N ~= nil and N.get ~= nil and N.get(gid, mid) or nil
    if n ~= nil then v.needs = { hunger = n.hunger, thirst = n.thirst, fatigue = n.fatigue, fear = n.fear } end
    if type(id) ~= "string" then return v end
    local B = LivingKnox.Bodies
    local z = B ~= nil and B.find ~= nil and (B.find(id)) or nil
    v.embodied = z ~= nil
    if z ~= nil then
        v.pos = { x = round1(z:getX()), y = round1(z:getY()), z = math.floor(z:getZ()) }
    elseif npc ~= nil and type(npc.last) == "table" then
        v.pos = { x = npc.last.x, y = npc.last.y, z = npc.last.z, last = true }
    end
    local De = LivingKnox.Decisions
    local d = De ~= nil and De.state ~= nil and De.state.members[id] or nil
    if d ~= nil then
        v.b, v.rule, v.why, v.key, v.untilMin = d.b, d.rule, d.why, d.key, d.untilMin
    end
    local R = LivingKnox.Routines
    local r = R ~= nil and R.state ~= nil and R.state.npcs[id] or nil
    if r ~= nil then v.routine = { key = r.key, kind = r.kind, phase = r.phase } end
    local C = LivingKnox.Combat
    local c = C ~= nil and C.orders ~= nil and C.orders[id] or nil
    if c ~= nil then v.combat = { k = c.k, u = c.u, phase = c.phase } end
    local An = LivingKnox.Anim
    v.gesture = An ~= nil and An.shownOf ~= nil and An.shownOf(id) or nil
    local H = LivingKnox.Health
    local h = H ~= nil and H.get ~= nil and H.get(id) or nil
    if h ~= nil and finite(h.hp) and finite(h.max) and h.max > 0 then v.hp = round1(100 * h.hp / h.max) end
    return v
end

local function sortedMids(g)
    local G = LivingKnox.Groups
    local ids = {}
    for mid in pairs(g.members) do ids[#ids + 1] = mid end
    table.sort(ids, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
    return ids
end

-- Vue du groupe g (table vivante du registre, lecture seule) pour le panneau : membres, journal sauvegardé, lignes
-- d'activité postérieures à after. Rend une table neuve.
function Activity.groupView(gid, g, after)
    local St = LivingKnox.Store
    local reg = St ~= nil and St.isReady ~= nil and St.isReady() and St.data() or nil
    local out = { id = gid, name = g.name, type = g.type, objective = g.objective, task = g.task, leader = g.leader,
        members = {}, log = {}, seq = Activity.state.seq, kept = Activity.count(gid), minute = Activity.minute() }
    for _, mid in ipairs(sortedMids(g)) do out.members[#out.members + 1] = memberView(gid, g, mid, g.members[mid], reg) end
    for i = 1, #(g.log or {}) do
        local e = g.log[i]
        out.log[i] = { day = e.day, kind = e.kind, text = e.text }
    end
    out.activity = Activity.entries(gid, after)
    return out
end

return Activity
