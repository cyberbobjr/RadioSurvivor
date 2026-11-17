-- Living Knox : expéditions, registre des genres d'expédition (LK16-T08)
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ genres (LK16-T08)

-- Genre d'expédition (Expeditions.registerKind, un fichier par genre dans Expeditions/) :
--   id        : identifiant, écrit dans trips.cur.kind (sauf pour le genre de repli) ; order : priorité au départ
--   fallback  : vrai pour le genre de repli (un seul) : essayé selon son order, lu pour une expédition sans kind ; ses
--               heures sont celles où un départ sans autre genre est permis
--   hours(hod) -> vrai si un départ de ce genre est permis à l'heure du jour hod
--   wanted(want) -> vrai si ce genre répond aux manques (facultatif : toujours)
--   pickTarget(gid, g, want, data) -> lieu { x, y, z, b, room, label, d, score, ... }, ou nil et une raison
--   wants(want) -> manques de l'expédition (facultatif : tous)
--   start(cur, target, team) : champs propres au genre dans l'expédition qui part (facultatif)
--   valid(t) -> vrai, ou faux et une raison : champs propres au genre (facultatif)
--   spot(t, rank) -> case de la place du rank-ième membre et angle de son regard (facultatif : point visé)
--   round(id, ctx, t, m, e, kind) : pas d'un membre arrivé, phase search (Ex.searchRound, Ex.drawnRound)
--   offscreen(g, gid, t, back, erand, kind) -> objets trouvés au retour abstrait (Ex.searchOffscreen,
--               Ex.drawnOffscreen)
--   gesture   : geste de la fouille (remis debout en la quittant) ; seen : vrai si le lieu (b) entre dans les derniers
--               fouillés au retour ; make(type) -> objets, nombre jetés : création au dépôt des objets notés (a, f)
--   Genres à tirages (Ex.drawnRound, Ex.drawnOffscreen) : draw(gid, t, k, cond) -> entrées { t, c, a, f } et texte ;
--               conditions() -> conditions des tirages ; minutes() -> minutes de jeu par tirage ; verb et
--               detail(cond) : journal du serveur.
Ex.kinds = Ex.kinds or { list = {}, byId = {} }
local KIND_FUNCTIONS = { "hours", "pickTarget", "round", "offscreen" }

local function validKind(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then return false, "spec needs an id" end
    for _, f in ipairs(KIND_FUNCTIONS) do
        if type(spec[f]) ~= "function" then return false, "kind " .. spec.id .. " needs " .. f end
    end
    if spec.fallback then
        for _, other in ipairs(Ex.kinds.list) do
            if other.fallback and other.id ~= spec.id then return false, "fallback kind already: " .. other.id end
        end
    end
    return true
end

local kindRegistry = LivingKnox.Registry.new("LivingKnox.Expeditions.registerKind",
    { validate = validKind, items = Ex.kinds.list, byKey = Ex.kinds.byId })

function Ex.registerKind(spec)
    return kindRegistry:register(spec, 2)
end

local function fallbackKind()
    for _, spec in ipairs(kindRegistry:list()) do
        if spec.fallback then return spec end
    end
    return nil
end

-- Genre de l'expédition t : genre inscrit de son kind, genre de repli sans kind ; nil si inconnu.
function Ex.kindOf(t)
    if t.kind == nil then return fallbackKind() end
    local spec = kindRegistry:get(t.kind)
    if spec == nil or spec.fallback then return nil end
    return spec
end

-- Vrai si un genre inscrit permet un départ à l'heure du jour hod.
local function kindHour(hod)
    for _, spec in ipairs(kindRegistry:list()) do
        if spec.hours(hod) then return true end
    end
    return false
end

P.kindRegistry, P.fallbackKind, P.kindHour = kindRegistry, fallbackKind, kindHour
