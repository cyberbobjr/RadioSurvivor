-- Living Knox : matériel des soins (LK21-T05, ADR adr-blessures-soins.md D05, D08) : sources de matériel et usage réel
-- des objets. Les soins (Care.registerTreatment, LK_CareTreatments.lua) déclarent leur matériel par fonction ou étiquette
-- vanilla ; ce module le cherche dans les sources inscrites, dans leur ordre, et le prend.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Source de matériel (Care.registerSupplySource, un fichier par source : server/LivingKnox/Care/LK_CareSource_<Id>.lua) :
--   { id, order (plus petit d'abord), find(sctx, match, skip) -> objet, place | nil ; take(sctx, objet, place) -> objet
--     dans l'inventaire du soignant, ou nil et une raison }
--   place : case où le soignant va prendre l'objet ({ key, x, y, z }), nil pour un objet déjà porté.
--   sctx = { gid, carer = { id, mid, body }, patient = { id, mid, body }, use (texte du journal) } ; skip[id] : objets
--   déjà choisis pour ce soin. Ordre actuel : soignant, blessé, stock du foyer ; la trousse (LK21-T06) s'inscrit avant.
-- Usage d'un objet (consume d'un matériel, objet dans l'inventaire inv du soignant), comme l'action vanilla :
--   Care.WHOLE : objet retiré (ISApplyBandage.lua:120, ISSplint.lua:96-101) ;
--   Care.USE   : une utilisation (InventoryItem.Use, J/inventory/InventoryItem.java:1153-1200 : retiré à 0 ; sans envoi
--                réseau, l'inventaire d'un corps n'existe que chez l'autorité, LK_Provisions.lua) (ISStitch.lua:100-101) ;
--   Care.TOOL  : outil gardé (pince, aiguille à coudre : ISRemoveBullet.lua, ISStitch.lua).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"

local Care = LivingKnox.Care or {}
LivingKnox.Care = Care

Care.supplySources = Care.supplySources or {}

local function validSource(spec)
    if type(spec) == "table" and type(spec.id) == "string" and type(spec.find) == "function"
        and type(spec.take) == "function" then
        return true
    end
    return false, "source needs id, order, find and take"
end

local sources = LivingKnox.Registry.new("LivingKnox.Care.registerSupplySource",
    { validate = validSource, items = Care.supplySources })

function Care.registerSupplySource(spec)
    return sources:register(spec, 2)
end

-- ================================================================ usage des objets

local function info(item)
    return { item = item, type = item:getFullType() }
end

function Care.WHOLE(item, inv)
    inv:DoRemoveItem(item)
    return info(item)
end

function Care.USE(item)
    local out = info(item)
    item:Use()
    return out
end

function Care.TOOL(item)
    return info(item)
end

-- ================================================================ recherche et prise

-- Premier objet des sources (dans leur ordre) tel que match(objet), hors de skip : choix { source, item, place }, ou nil.
local function pick(sctx, match, skip)
    for _, src in ipairs(Care.supplySources) do
        local item, place = src.find(sctx, match, skip)
        if item ~= nil then return { source = src.id, item = item, place = place } end
    end
    return nil
end

-- Matériel complet de l'option o : { [id du matériel] = choix }, ou nil et l'id du premier matériel manquant.
function Care.findMaterials(o, sctx)
    local picks, skip = {}, {}
    for _, m in ipairs(o.materials) do
        local p = pick(sctx, m.match, skip)
        if p == nil then return nil, m.id end
        skip[p.item:getID()] = true
        picks[m.id] = p
    end
    return picks
end

-- Première case où aller chercher du matériel des choix picks (objets non portés), ou nil.
function Care.placeOf(picks)
    for _, p in pairs(picks) do
        if p.place ~= nil then return p.place end
    end
    return nil
end

-- Prend dans l'inventaire du soignant chaque objet des choix picks (source.take) ; rend vrai, ou nil et la raison
-- (objet parti entre le repérage et la prise). Les objets déjà pris restent au soignant.
function Care.takeMaterials(picks, sctx)
    for id, p in pairs(picks) do
        local src
        for _, s in ipairs(Care.supplySources) do
            if s.id == p.source then src = s end
        end
        local got, why = nil, "no source " .. tostring(p.source)
        if src ~= nil then got, why = src.take(sctx, p.item, p.place) end
        if got == nil then return nil, id .. ": " .. tostring(why) end
        p.item = got
    end
    return true
end

return Care
