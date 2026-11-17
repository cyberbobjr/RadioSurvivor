-- Living Knox : plaies et santé d'un membre de groupe hors écran (LK21-T03, ADR docs/architecture/decisions/
-- adr-blessures-soins.md, D01). Remplace la blessure abstraite wound 0..100 de la simulation (non reprise : mod non
-- publié). Un membre hors écran porte la même liste de plaies que le corps incarné (LK_Health) :
--   member.wounds : forme sauvegardée des plaies (texte de Wounds.pack, LK_WoundsForm.lua ; absent = aucune plaie ;
--                   même validation que le registre des corps, LK_Groups.validGroup) ;
--   member.health : santé, fraction de la santé de naissance ]0, 1[ (absent = pleine santé), gardée au millionième.
-- Les plaies d'un membre incarné sont celles de son corps (LK_Health) : ce module les lit là (Mh.state) et ne change
-- jamais un membre incarné. Passage incarné <-> hors écran : LK_Materialize (plaies passées telles quelles).
--
-- Mêmes règles que le corps : coups par le registre des sources (Wounds.fromHit, LK_WoundSources.lua), évolution et
-- santé par la formule commune (Wounds.healthStep, LK_WoundsHealth.lua), premier soin par Wounds.bandageBleeding.
-- Hasard : celui de la simulation (flux reproductible passé par l'appelant, Mh.context) ; options du jeu (durée d'une
-- journée, InjurySeverity) : LivingKnox.WoundContext.
-- Autorité seulement (un client MP charge aussi media/lua/server, il s'arrête ici).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_WoundsForm"
require "LivingKnox/LK_WoundsHealth"
require "LivingKnox/LK_WoundSources"
require "LivingKnox/LK_WoundContext"

local Wounds = LivingKnox.Wounds

local Mh = LivingKnox.MemberHealth or {}
LivingKnox.MemberHealth = Mh

Mh.FLOOR = 0.01   -- santé laissée au plus bas par un coup hors écran : un coup ne tue jamais sur le coup

local function round6(v) return math.floor(v * 1e6 + 0.5) / 1e6 end

-- Contexte du modèle des plaies pour la simulation : options du jeu, hasard rnd (flux de la simulation).
function Mh.context(rnd)
    local ctx = LivingKnox.WoundContext.current()
    ctx.rnd = rnd
    return ctx
end

-- ---------------------------------------------------------------- lecture

-- Plaies hors écran du membre m (liste neuve du modèle, relue de m.wounds ; forme refusée : aucune plaie).
function Mh.wounds(m)
    if m.wounds == nil then return {} end
    return Wounds.unpack(m.wounds) or {}
end

-- Santé hors écran du membre m (fraction).
function Mh.health(m)
    if LivingKnox.Num.finite(m.health) then return m.health end
    return 1
end

-- Corps incarné du membre m : santé (fraction) et plaies vivantes de LK_Health, ou nil (membre hors écran, ou santé du
-- corps inconnue).
local function bodyState(m)
    local H = LivingKnox.Health
    if m.npc == nil or H == nil or H.reference == nil then return nil end
    local hp = H.reference(m.npc)
    local h = hp ~= nil and H.get(m.npc) or nil
    if h == nil or not LivingKnox.Num.finite(h.max) or h.max <= 0 then return nil end
    return LivingKnox.Num.clamp(hp / h.max, 0, 1), H.wounds(m.npc) or {}
end

-- Santé (fraction) et plaies du membre m : celles de son corps s'il est incarné, sinon celles de la simulation.
function Mh.state(m)
    local health, list = bodyState(m)
    if health ~= nil then return health, list end
    return Mh.health(m), Mh.wounds(m)
end

-- Gravement blessé (seul critère du moteur : tâche « heal », équipes, raids, vengeance, force au combat) : santé sous
-- l'option WoundedHealth (Config.woundedRatio), ou une plaie qui saigne à nu.
function Mh.seriouslyWounded(m)
    local health, list = Mh.state(m)
    return health < LivingKnox.Config.woundedRatio() or Wounds.bleeding(list) > 0
end

-- ---------------------------------------------------------------- écriture (membre hors écran)

local function save(m, list, health)
    if #list > 0 then m.wounds = Wounds.pack(list) else m.wounds = nil end
    health = round6(health)
    if health >= 1 then m.health = nil else m.health = health end
end

-- Coup hors écran sur le membre m : plaies de la source du coup hit (Wounds.fromHit ; hit nil ou sans source connue :
-- aucune plaie) et santé baissée de loss (fraction), jamais sous FLOOR. Rend les plaies ajoutées.
function Mh.hurt(m, hit, loss, ctx)
    local list = Mh.wounds(m)
    local added = hit ~= nil and Wounds.fromHit(list, hit, ctx) or {}
    local before = Mh.health(m)
    local health = before - math.max(0, loss or 0)
    if health < Mh.FLOOR then health = math.min(before, Mh.FLOOR) end
    save(m, list, health)
    return added
end

-- Premier soin hors écran (réserve de soins au foyer) : bandage sur chaque plaie qui saigne (Wounds.bandageBleeding,
-- Config.BLEEDING.BANDAGE_LIFE). Rend le nombre de bandages posés.
function Mh.care(m, ctx)
    local list = Mh.wounds(m)
    local _, count = Wounds.bandageBleeding(list, ctx, LivingKnox.Config.BLEEDING.BANDAGE_LIFE)
    if count > 0 then save(m, list, Mh.health(m)) end
    return count
end

-- minutes de jeu hors écran pour le membre m : plaies et santé par la formule du corps (Wounds.healthStep) ; loss
-- (fraction, facultative) retirée d'abord sans régénération (faim). Rend vrai si le membre est encore en vie (santé
-- > 0 ; sinon ses plaies sont effacées et la mort reste à appliquer par l'appelant).
function Mh.pass(m, minutes, ctx, loss)
    if m.wounds == nil and m.health == nil and (loss or 0) <= 0 then return true end
    local list = Mh.wounds(m)
    local health = Mh.health(m) - math.max(0, loss or 0)
    health = Wounds.healthStep(list, health, minutes, ctx, (loss or 0) <= 0)
    if health <= 0 then
        m.wounds, m.health = nil, nil
        return false
    end
    save(m, list, math.max(1e-6, health))
    return true
end

-- Santé et plaies du membre m en valeurs simples pour les vues (LK_Admin, LK_Activity) : { pct (0..100, un décimal),
-- wounds (nombre) }.
function Mh.summary(m)
    local health, list = Mh.state(m)
    return { pct = math.floor(health * 1000 + 0.5) / 10, wounds = #list }
end

return Mh
