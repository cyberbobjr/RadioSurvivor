-- Living Knox : cadre de décision des PNJ, registres des extensions de la cascade (LK05-T20) et des
-- fournisseurs de contexte (LK16-T05).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- ================================================================ extensions de la cascade (registre, LK05-T20)

-- Extension : { id (unique ; nom du comportement ajouté quand behaviour est donné), order (plus petit d'abord, à
-- égalité par id), rules (facultatif) = { { name, before (règle de PRIORITIES), rule(ctx) -> b, why, key }, ... } :
-- règle essayée juste avant la règle before, au même rang ; behaviour (facultatif) = { vigil, minutes = { lo, hi },
-- needs } : comportement id ajouté à BEHAVIOURS, mené par apply(id, st, ctx, fresh) ; leave(id) : membre sorti du
-- comportement id (ou oublié) ; input(ctx, body, minute) (facultatif) : complète le contexte lu par ses règles ;
-- observe(ctx, st, body, minute) (facultatif) : après la décision appliquée }. Ce registre ne nomme aucune extension :
-- chacune s'inscrit depuis son propre fichier (Decisions.registerExtension). Liste triée à l'inscription (sans next).
-- LK16-T06 : l'extension qui porte l'id d'un comportement (et apply) le MÈNE, qu'il soit déclaré par elle (behaviour)
-- ou par la liste fermée du moteur (sans behaviour : la déclaration reste celle des règles du moteur ; un id est unique,
-- donc un seul propriétaire). Champs du meneur, tous facultatifs :
--   aim(ctx, out, rnd) : visée de la décision out (angle, away, side, u...) ; rnd : flux de la décision, après la durée ;
--   gesture : vrai, ou function(ctx, st) -> vrai, quand le comportement pose et garde lui-même son geste
--     (Decisions.setAlertGesture) ; sinon le moteur retire, avant d'appliquer, le geste posé par un comportement
--     précédent ;
--   overlay : vrai si l'application passe après le soin (LK_Care) et la routine du comportement (LK_Routines) ; sans
--     lui, l'extension mène seule, avant eux ;
--   keeps = { id, ... } : extensions dont l'état du membre est gardé pendant ce comportement (leur leave n'est pas
--     appelé) ;
--   forget(id) : membre oublié (mort, corps parti) ; sans forget, leave.
Decisions.extensions = Decisions.extensions or {}

local function validRules(rules)
    if rules == nil then return true end
    if type(rules) ~= "table" then return false end
    for _, r in ipairs(rules) do
        if type(r) ~= "table" or type(r.name) ~= "string" or type(r.rule) ~= "function" or P.RULES[r.before] == nil then
            return false
        end
    end
    return true
end

local function wellFormed(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.order) ~= "number" then return false end
    if not validRules(spec.rules) then return false end
    for _, f in ipairs({ "apply", "leave", "input", "observe", "aim", "forget" }) do
        if spec[f] ~= nil and type(spec[f]) ~= "function" then return false end
    end
    if spec.gesture ~= nil and spec.gesture ~= true and type(spec.gesture) ~= "function" then return false end
    if spec.overlay ~= nil and type(spec.overlay) ~= "boolean" then return false end
    if spec.keeps ~= nil and type(spec.keeps) ~= "table" then return false end
    local b = spec.behaviour
    if b ~= nil then
        if type(b) ~= "table" or type(b.vigil) ~= "string" or spec.apply == nil then return false end
        -- Règle propre à ce registre : un comportement de la liste fermée ne peut pas être repris par une extension.
        if Decisions.BEHAVIOURS[spec.id] ~= nil and Decisions.BEHAVIOURS[spec.id].ext ~= spec.id then return false end
    end
    return true
end

local function validExtension(spec)
    if wellFormed(spec) then return true end
    return false, "spec needs id, order, rules { name, before, rule } and, for a behaviour { vigil }, apply"
end

-- LK16-T01 : socle commun (LivingKnox.Registry) ; Decisions.extensions en est la liste.
local extensions = LivingKnox.Registry.new("LivingKnox.Decisions.registerExtension",
    { validate = validExtension, items = Decisions.extensions })

-- Inscrit une extension (spec, voir ci-dessus). Une extension déjà inscrite sous le même id est remplacée
-- (rechargement). Un comportement de la liste fermée ne peut pas être repris par une extension.
function Decisions.registerExtension(spec)
    extensions:register(spec, 2)
    local b = spec.behaviour
    if b ~= nil then
        Decisions.BEHAVIOURS[spec.id] = { vigil = b.vigil, needs = b.needs, ext = spec.id }
        if type(b.minutes) == "table" then P.cfg().MINUTES[spec.id] = { b.minutes[1], b.minutes[2] } end
    end
    return spec
end

-- ================================================================ fournisseurs de contexte (registre, LK16-T05)

-- Fournisseur : { id (unique), order (plus petit d'abord, à égalité par id), fill(ctx, src) } : pose ses champs dans
-- le contexte ctx d'un membre (Decisions.context) ; src = { gid, g, mid, m, body, players, minute, per } : entrées de
-- l'évaluation (per : perception du membre, posée par le fournisseur « perception »). Un fournisseur lit seulement les
-- champs posés avant lui (ordre explicite, figé par tests/livingknox/test_lk_decision_context.py) ; module absent = fournisseur
-- absent = champ absent. Chaque module pose son champ depuis son propre fichier (Decisions.registerContext) ; ce
-- registre n'en nomme aucun. Les entrées des extensions (input) passent après tous les fournisseurs.
-- Bandes d'ordre (fiche docs/annexes/conception/decisions.md, « Contexte d'un membre ») : 10 routines, 20 expédition,
-- 30 traque, 40 foyer, 50 perception, 60 menaces, 70 cible, 80 défense personnelle, 90 alerte, 100 défense du foyer,
-- 110 sommation, 120 peur, 130 besoins, 140 débordement.
Decisions.contextProviders = Decisions.contextProviders or {}

local function validProvider(spec)
    if type(spec) == "table" and type(spec.id) == "string" and type(spec.fill) == "function" then return true end
    return false, "spec needs id, order and fill(ctx, src)"
end

local providers = LivingKnox.Registry.new("LivingKnox.Decisions.registerContext",
    { validate = validProvider, items = Decisions.contextProviders })

-- Inscrit un fournisseur de contexte (spec, voir ci-dessus) ; un fournisseur déjà inscrit sous le même id est remplacé
-- (rechargement). Rend spec ; spec mal formée : erreur.
function Decisions.registerContext(spec)
    return providers:register(spec, 2)
end
