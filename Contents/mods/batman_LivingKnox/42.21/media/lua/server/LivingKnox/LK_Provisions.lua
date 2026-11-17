-- Living Knox : provisions portées sur soi par les PNJ incarnés (LK05-T20). Fiche : docs/annexes/conception/besoins.md,
-- section « Provisions sur soi et gourde inépuisable ». Java 42.22 cité en abrégé (J = zombie/...).
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Décision de l'utilisateur du 2026-11-04 (plan LK05) : chaque PNJ porte CFG.COUNT vrais aliments non périssables et une
-- gourde d'eau qui ne se vide jamais, dans l'inventaire de son corps (gardé par le cadavre : LK_Loot.lua, en-tête).
-- Ce fichier tient les objets et leurs effets ; la décision de manger ou de boire est LK_ProvisionMeal.lua.
--   - Provision : aliment (Food) mangeable tel quel (LivingKnox.Stock.consumable) qui ne pourrit jamais : offAgeMax au
--     moins MAX_FOOD_AGE (J/inventory/InventoryItem.java:165, 2453 ; Item.daysTotallyRotten par défaut 1000000000,
--     J/scripting/objects/Item.java:111, 1563). Les poches du rôle (LK_Loot.lua) en comptent déjà, s'il y en a.
--   - Don initial : contenu « provisions » du butin (Loot.registerContent), une seule fois par corps comme le reste du
--     butin : complète jusqu'à CFG.COUNT avec CFG.FOODS (choix reproductible par PNJ) et ajoute la gourde CFG.CANTEEN
--     si le corps n'en porte pas.
--   - Remplacement : Provisions.refill, au foyer, prend dans le stock du groupe (LivingKnox.Stock.takeItem : objet
--     retiré du conteneur et des clients, ôté de la référence) et le met dans l'inventaire du corps ; jamais d'objet
--     créé ; au plus un essai toutes les CFG.REFILL_MINUTES minutes de jeu par membre ; jamais avant le don initial
--     (marque Loot.MD_BUILT du corps).
--   - Repas : Provisions.eat retire UNE provision de l'inventaire (ItemContainer.DoRemoveItem,
--     J/inventory/ItemContainer.java:2004) et baisse la faim de Needs.CFG.MEAL, une fois.
--   - Boisson : Provisions.drink baisse la soif de Needs.CFG.DRINK ; la gourde n'est jamais touchée (choix assumé de
--     l'utilisateur).
-- L'inventaire d'un corps n'existe que sur la copie de l'autorité : aucun envoi aux clients (ils reçoivent le contenu du
-- cadavre à la mort, LK_Loot.lua).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Needs"
require "LivingKnox/LK_Stock"
require "LivingKnox/LK_Loot"

local Provisions = LivingKnox.Provisions or {}
LivingKnox.Provisions = Provisions

Provisions.MAX_FOOD_AGE = 1000000000   -- J/inventory/InventoryItem.java:165 (offAgeMax d'un aliment qui ne pourrit pas)

-- Réglages (valeurs et raisons : fiche besoins.md).
-- FOODS : aliments vanilla 42.22 prêts à manger, sans DaysFresh ni DaysTotallyRotten
-- (media/scripts/generated/items/food.txt:12842 GranolaBar, :12691 BeefJerky, :8721 DriedApricots).
-- CANTEEN : gourde militaire pleine (normal.txt:14015-14040 : 0,9 l d'eau à la création, sans InitialPercent :
-- J/scripting/entity/components/fluids/FluidContainerScript.java:330-333).
Provisions.CFG = Provisions.CFG or {
    COUNT = 2,                  -- provisions portées
    FOODS = { "Base.GranolaBar", "Base.BeefJerky", "Base.DriedApricots" },
    CANTEEN = "Base.CanteenMilitaryFull",
    REFILL_MINUTES = 10,        -- minutes de jeu entre deux essais de remplacement d'un même membre
}

Provisions.state = Provisions.state or { tried = {} }
Provisions.stats = Provisions.stats or { given = 0, refilled = 0, refillTries = 0, eaten = 0, drunk = 0 }

local function cfg() return Provisions.CFG end

-- ================================================================ objets portés

-- Vrai si l'objet est une provision : aliment mangeable tel quel qui ne pourrit jamais.
function Provisions.isProvision(item)
    if item == nil or not instanceof(item, "Food") then return false end
    local S = LivingKnox.Stock
    if S.categoryOf(item) ~= "food" or not S.consumable(item, "food") then return false end
    return item:getOffAgeMax() >= Provisions.MAX_FOOD_AGE
end

-- Provisions du corps z : nombre, première provision (ou nil), gourde (ou nil).
function Provisions.carried(z)
    local items = z:getInventory():getItems()
    local n, first, canteen = 0, nil, nil
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if Provisions.isProvision(it) then
            n = n + 1
            if first == nil then first = it end
        elseif canteen == nil and it ~= nil and it:getFullType() == cfg().CANTEEN then
            canteen = it
        end
    end
    return n, first, canteen
end

-- Aliments du don initial du PNJ id (n types de CFG.FOODS, tour à tour depuis un rang tiré de l'identité).
function Provisions.kitFor(id, n)
    local foods = cfg().FOODS
    local h = 0
    local s = tostring(id)
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 1000003 end
    local out = {}
    for i = 1, n do out[i] = foods[(h + i - 1) % #foods + 1] end
    return out
end

-- Contenu « provisions » du butin (une seule fois par corps, LK_Loot.lua).
LivingKnox.Loot.registerContent({ id = "provisions", order = 30, add = function(id, z, inv)
    local L = LivingKnox.Loot
    local have, _, canteen = Provisions.carried(z)
    local n = 0
    for _, t in ipairs(Provisions.kitFor(id, math.max(0, cfg().COUNT - have))) do
        n = n + L.addItems(inv, t, 1, "provisions")
    end
    local c = canteen ~= nil and 0 or L.addItems(inv, cfg().CANTEEN, 1, "provisions")
    Provisions.stats.given = Provisions.stats.given + n + c
    return { items = n + c, rounds = 0, part = string.format("%d provision(s)%s", have + n,
        (canteen ~= nil or c > 0) and " and a canteen" or ", no canteen") }
end })

-- ================================================================ effets (autorité)

-- Baisse la jauge gauge du membre mid du groupe gid de amount (LivingKnox.Needs.relieve, registre écrit). Rend la
-- nouvelle valeur ou nil.
local function relieve(gid, mid, gauge, amount)
    local N, G = LivingKnox.Needs, LivingKnox.Groups
    local value
    G.update(function(data)
        local g = data.groups[gid]
        if g == nil then return false, false end
        value = N.relieve(g, mid, gauge, amount)
        return value ~= nil, true
    end)
    return value
end

local function note(gid, mid, text)
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil and Ac.note ~= nil then Ac.note(gid, mid, "meal", text) end
end

-- Mange UNE provision du corps z (membre mid du groupe gid) : objet retiré, faim baissée de Needs.CFG.MEAL. Rend le type
-- mangé, ou nil et une raison.
function Provisions.eat(gid, mid, z)
    if z == nil then return nil, "no body" end
    local n, item = Provisions.carried(z)
    if item == nil then return nil, "no provision" end
    local t, id = item:getFullType(), item:getID()
    z:getInventory():DoRemoveItem(item)
    local amount = LivingKnox.Needs.CFG.MEAL
    local value = relieve(gid, mid, "hunger", amount)
    Provisions.stats.eaten = Provisions.stats.eaten + 1
    LivingKnox.Log.info("group %s %s: ate provision %s (%s), hunger -%d -> %s, %d left", tostring(gid), tostring(mid), t,
        tostring(id), amount, tostring(value), n - 1)
    note(gid, mid, "ate provision " .. t)
    return t
end

-- Boit à la gourde du corps z : soif baissée de Needs.CFG.DRINK, gourde intacte. Rend vrai, ou nil et une raison.
function Provisions.drink(gid, mid, z)
    if z == nil then return nil, "no body" end
    local _, _, canteen = Provisions.carried(z)
    if canteen == nil then return nil, "no canteen" end
    local amount = LivingKnox.Needs.CFG.DRINK
    local value = relieve(gid, mid, "thirst", amount)
    Provisions.stats.drunk = Provisions.stats.drunk + 1
    LivingKnox.Log.info("group %s %s: drank from the canteen, thirst -%d -> %s (canteen never emptied)", tostring(gid),
        tostring(mid), amount, tostring(value))
    note(gid, mid, "drank from the canteen")
    return true
end

-- Provisions manquantes du corps z (membre mid du PNJ id, groupe gid) remplacées sur le stock du foyer, au plus un essai
-- par CFG.REFILL_MINUTES et par PNJ (minute : minute de jeu). Rend le nombre d'objets pris, ou 0 et une raison.
function Provisions.refill(gid, mid, id, z, minute)
    if z == nil then return 0, "no body" end
    -- Butin du corps pas encore construit : le don initial passe d'abord (sinon le stock paierait ce qu'il donne).
    if z:getModData()[LivingKnox.Loot.MD_BUILT] == nil then return 0, "loot not built yet" end
    local have = Provisions.carried(z)
    if have >= cfg().COUNT then return 0, "full" end
    local tried = Provisions.state.tried
    local last = tried[id]
    if last ~= nil and minute ~= nil and minute >= last and minute - last < cfg().REFILL_MINUTES then
        return 0, "tried recently"
    end
    tried[id] = minute
    Provisions.stats.refillTries = Provisions.stats.refillTries + 1
    local S = LivingKnox.Stock
    local inv = z:getInventory()
    local n, why = 0, nil
    while have + n < cfg().COUNT do
        local got, item = S.takeItem(gid, Provisions.isProvision, mid, "provisions")
        if got == nil then
            why = item
            break
        end
        inv:AddItem(item)
        n = n + 1
        note(gid, mid, "took " .. got.t .. " from " .. got.k .. " for provisions")
    end
    Provisions.stats.refilled = Provisions.stats.refilled + n
    if n > 0 then
        LivingKnox.Log.info("group %s %s: %d provision(s) replaced from the home stock, %d carried", tostring(gid),
            tostring(mid), n, have + n)
    else
        LivingKnox.Log.debug("group %s %s: no provision replaced: %s", tostring(gid), tostring(mid), tostring(why))
    end
    return n, why
end

function Provisions.reset()
    Provisions.state = { tried = {} }
end

return Provisions
