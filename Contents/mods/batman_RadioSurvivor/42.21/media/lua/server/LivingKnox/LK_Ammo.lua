-- Living Knox : munitions des PNJ armés d'une arme à feu, côté autorité (LK06-T03). Fiche : docs/conception/combat.md,
-- section « Tir ». Java 42.21.0 cité en abrégé (J = zombie/...).
-- Autorité seulement (serveur, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Modèle (le plus simple qui garde « aucun tir sans munition ») :
--   - l'arme du PNJ est un type du registre (LK_Equipment), jamais un objet réel : l'arme et son chargeur engagé sont
--     donc virtuels. Les cartouches qu'elle contient sont notées dans les ModData du corps (Ammo.MD_KEY = { t = type
--     de l'arme, n = cartouches }) : un joueur réanimé est sauvegardé avec ses ModData (base zombies-as-npc-bodies.md),
--     jamais envoyées aux clients ;
--   - les munitions de réserve sont des OBJETS RÉELS de l'inventaire du corps (z:getInventory(), premier niveau) :
--     cartouches du type de l'arme (HandWeapon:getAmmoType():getItemKey(), par exemple Base.Bullets9mm ;
--     J/scripting/objects/AmmoType.java:47-49) et chargeurs (getMagazineType(), par exemple Base.9mmClip, cartouches
--     = getCurrentAmmoCount()). Le corps devenu cadavre garde ces objets (inventaire du joueur réanimé).
--     Les boîtes (Bullets9mmBox) ne sont pas ouvertes ; les sacs ne sont pas fouillés.
-- Rechargement (Ammo.reload, à la fin du geste animé minuté par LK_Combat) :
--   - arme à chargeur avec un chargeur de réserve non vide : ÉCHANGE des contenus (le chargeur le plus plein entre
--     dans l'arme, l'objet garde les cartouches qui restaient dans l'arme ; aucun objet créé ni détruit) ;
--   - sinon cartouches libres : l'arme est remplie jusqu'à getMaxAmmo() (objets retirés un à un) ;
--   - sinon rien (Ammo.plan rend nil) : plus aucune munition.
-- Tir (Ammo.consume) : getAmmoPerShoot() cartouches retirées de l'arme, ou refus si elle en contient moins.
-- Aucun envoi réseau : l'inventaire d'un zombie n'est pas affiché aux clients ; seul le serveur le lit.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local Ammo = LivingKnox.Ammo or {}
LivingKnox.Ammo = Ammo

Ammo.MD_KEY = "LKAmmo"
Ammo.PLAN_MAGAZINE = "magazine"
Ammo.PLAN_ROUNDS = "rounds"

Ammo.specs = Ammo.specs or {}   -- type d'arme -> description (ci-dessous) ou { bad = raison } ; instanceItem une fois
Ammo.stats = Ammo.stats or { reloads = 0, swapped = 0, loadedRounds = 0, consumed = 0, empty = 0, given = 0 }
Ammo.stats.unloaded = Ammo.stats.unloaded or 0   -- LK07-T05 : cartouches de l'arme rendues en objets à la mort

local function log() return LivingKnox.Log end

local function count(name, n)
    Ammo.stats[name] = (Ammo.stats[name] or 0) + (n or 1)
end

local function posInt(v, default)
    if type(v) ~= "number" or v ~= v or v < 1 then return default end
    return math.floor(v)
end

-- Arme à feu gunType : { t, round = type des cartouches, mag = type du chargeur ou nil, max = capacité, per =
-- cartouches par tir, h = deux mains }, ou nil et une raison.
function Ammo.spec(gunType)
    if type(gunType) ~= "string" then return nil, "bad weapon type " .. tostring(gunType) end
    local known = Ammo.specs[gunType]
    if known ~= nil then
        if known.bad then return nil, known.bad end
        return known
    end
    local w = instanceItem(gunType)
    local why
    if w == nil then
        why = "unknown item " .. gunType
    elseif not instanceof(w, "HandWeapon") or not w:isRanged() then
        why = gunType .. " is not a firearm"
    else
        local at = w:getAmmoType()
        local round = at ~= nil and at:getItemKey() or nil
        if type(round) ~= "string" or round == "" then
            why = gunType .. " has no ammo type"
        else
            local mag = w:getMagazineType()
            if mag == "" then mag = nil end
            known = { t = gunType, round = round, mag = mag, max = posInt(w:getMaxAmmo(), 1),
                per = posInt(w:getAmmoPerShoot(), 1),
                h = w:isTwoHandWeapon() == true or w:isRequiresEquippedBothHands() == true }
        end
    end
    if why then known = { bad = why } end
    Ammo.specs[gunType] = known
    if why then return nil, why end
    return known
end

local function state(z)
    local md = z:getModData()
    local s = md[Ammo.MD_KEY]
    if type(s) ~= "table" then return nil end
    return s
end

-- Cartouches dans l'arme gunType du corps z (0 si l'état noté concerne une autre arme).
function Ammo.loaded(z, gunType)
    local s = state(z)
    if s == nil or s.t ~= gunType or type(s.n) ~= "number" or s.n < 0 then return 0 end
    return math.floor(s.n)
end

local function setLoaded(z, gunType, n)
    z:getModData()[Ammo.MD_KEY] = { t = gunType, n = n }
end

-- Cartouches dans l'arme gunType du corps z fixées à n (borné à 0..capacité), sans objet créé : munitions de départ
-- (LK07-T05, LK_Loot). Rend le nombre retenu, ou nil et une raison.
function Ammo.setLoaded(z, gunType, n)
    local spec, why = Ammo.spec(gunType)
    if spec == nil then return nil, why end
    n = math.max(0, math.min(spec.max, math.floor(tonumber(n) or 0)))
    setLoaded(z, gunType, n)
    return n
end

-- Vrai si l'état des cartouches dans l'arme du corps z est noté (quelle que soit l'arme).
function Ammo.hasState(z)
    return state(z) ~= nil
end

-- Réserve du corps z pour l'arme spec : cartouches libres, cartouches dans les chargeurs, chargeur le plus plein
-- (objet) et son contenu.
function Ammo.reserveOf(z, spec)
    local loose, inMags, best, bestN = 0, 0, nil, 0
    local items = z:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it ~= nil then
            local t = it:getFullType()
            if t == spec.round then
                loose = loose + 1
            elseif spec.mag ~= nil and t == spec.mag then
                local n = it:getCurrentAmmoCount()
                if type(n) == "number" and n > 0 then
                    inMags = inMags + n
                    if n > bestN then best, bestN = it, n end
                end
            end
        end
    end
    return loose, inMags, best, bestN
end

-- Munitions utilisables du corps z avec l'arme gunType : cartouches dans l'arme + réserve (0 si ce n'est pas une
-- arme à feu connue).
function Ammo.available(z, gunType)
    local spec = Ammo.spec(gunType)
    if spec == nil or z == nil then return 0 end
    local loose, inMags = Ammo.reserveOf(z, spec)
    return Ammo.loaded(z, gunType) + loose + inMags
end

-- Rechargement possible : PLAN_MAGAZINE (échange avec un chargeur de réserve plus plein que l'arme), PLAN_ROUNDS
-- (cartouches libres, arme pas pleine), ou nil.
function Ammo.plan(z, gunType)
    local spec = Ammo.spec(gunType)
    if spec == nil or z == nil then return nil end
    local n = Ammo.loaded(z, gunType)
    local loose, _, best, bestN = Ammo.reserveOf(z, spec)
    if best ~= nil and bestN > n then return Ammo.PLAN_MAGAZINE end
    if loose > 0 and n < spec.max then return Ammo.PLAN_ROUNDS end
    return nil
end

-- Rechargement de l'arme gunType du corps z (voir l'en-tête). Rend le nombre de cartouches dans l'arme et le plan
-- appliqué (nil : rien à faire).
function Ammo.reload(id, z, gunType)
    local spec = Ammo.spec(gunType)
    if spec == nil or z == nil then return 0, nil end
    local n = Ammo.loaded(z, gunType)
    local inv = z:getInventory()
    local loose, _, best, bestN = Ammo.reserveOf(z, spec)
    if best ~= nil and bestN > n then
        best:setCurrentAmmoCount(n)
        setLoaded(z, gunType, bestN)
        count("reloads")
        count("swapped")
        log().info("npc %s reloaded %s with a magazine: %d round(s) in, %d left in the magazine taken out", tostring(id),
            gunType, bestN, n)
        return bestN, Ammo.PLAN_MAGAZINE
    end
    if loose > 0 and n < spec.max then
        local want = math.min(loose, spec.max - n)
        local taken = 0
        local items = inv:getItems()
        local list = {}
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it ~= nil and it:getFullType() == spec.round then list[#list + 1] = it end
            if #list >= want then break end
        end
        for _, it in ipairs(list) do   -- liste Java modifiée hors de son parcours
            inv:DoRemoveItem(it)
            taken = taken + 1
        end
        setLoaded(z, gunType, n + taken)
        count("reloads")
        count("loadedRounds", taken)
        log().info("npc %s reloaded %s with %d loose round(s): %d in the weapon, %d loose round(s) left", tostring(id),
            gunType, taken, n + taken, loose - taken)
        return n + taken, Ammo.PLAN_ROUNDS
    end
    return n, nil
end

-- Tir : retire getAmmoPerShoot() cartouches de l'arme. Rend vrai, ou faux si elle en contient moins.
function Ammo.consume(z, gunType)
    local spec = Ammo.spec(gunType)
    if spec == nil or z == nil then return false end
    local n = Ammo.loaded(z, gunType)
    if n < spec.per then
        count("empty")
        return false
    end
    setLoaded(z, gunType, n - spec.per)
    count("consumed", spec.per)
    return true
end

-- Ajoute à l'inventaire du corps z `rounds` cartouches libres et `mags` chargeurs pleins de l'arme gunType (chargeurs
-- ignorés pour une arme sans chargeur). Rend le nombre de cartouches ajoutées, ou nil et une raison.
function Ammo.addReserve(z, gunType, rounds, mags)
    local spec, why = Ammo.spec(gunType)
    if spec == nil then return nil, why end
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    mags = spec.mag ~= nil and math.max(0, math.floor(tonumber(mags) or 0)) or 0
    local inv = z:getInventory()
    local added = 0
    for _ = 1, rounds do
        local it = instanceItem(spec.round)
        if it == nil then return nil, "unknown ammo item " .. spec.round end
        inv:AddItem(it)
        added = added + 1
    end
    for _ = 1, mags do
        local it = instanceItem(spec.mag)
        if it == nil then return nil, "unknown magazine item " .. spec.mag end
        it:setCurrentAmmoCount(spec.max)
        inv:AddItem(it)
        added = added + spec.max
    end
    count("given", added)
    return added
end

-- API et suites de test : ajoute à l'inventaire du corps du PNJ id `rounds` cartouches libres et `mags` chargeurs
-- pleins de l'arme gunType (Ammo.addReserve). Autorité seulement. Rend le nombre de cartouches ajoutées, ou nil et une
-- raison.
function Ammo.give(id, gunType, rounds, mags)
    if not LivingKnox.isAuthority() then return nil, "not the authority (MP client)" end
    local B = LivingKnox.Bodies
    local z = B ~= nil and B.find(id) or nil
    if z == nil or z:isDead() then return nil, "npc " .. tostring(id) .. " has no body in the loaded area" end
    local added, why = Ammo.addReserve(z, gunType, rounds, mags)
    if added == nil then return nil, why end
    log().info("npc %s given %d loose round(s) and %d magazine(s) for %s", tostring(id),
        math.max(0, math.floor(tonumber(rounds) or 0)), math.max(0, math.floor(tonumber(mags) or 0)), gunType)
    return added
end

-- Mort du corps z (LK07-T05, LK_Loot.onDeath, avant la création du cadavre) : les cartouches notées dans l'arme
-- gunType deviennent des OBJETS de son inventaire (arme à chargeur : le chargeur engagé, avec ses cartouches, même
-- vide ; sinon une cartouche libre par cartouche). L'état noté est effacé (quelle que soit l'arme notée). Rend le
-- nombre de cartouches rendues en objets.
function Ammo.unload(z, gunType)
    local s = state(z)
    z:getModData()[Ammo.MD_KEY] = nil
    if s == nil or s.t ~= gunType then return 0 end
    local spec = Ammo.spec(gunType)
    if spec == nil then return 0 end
    local n = type(s.n) == "number" and s.n >= 0 and math.floor(s.n) or 0
    local inv = z:getInventory()
    if spec.mag ~= nil then
        local it = instanceItem(spec.mag)
        if it == nil then return 0 end
        it:setCurrentAmmoCount(n)
        inv:AddItem(it)
        count("unloaded", n)
        return n
    end
    for _ = 1, n do
        local it = instanceItem(spec.round)
        if it == nil then return 0 end
        inv:AddItem(it)
    end
    count("unloaded", n)
    return n
end

-- Arme du corps z remplacée par un autre mod (LK07-T08, LivingKnox.Equipment.adoptForeign) : munitions de l'arme
-- fromType reportées sur l'arme toType, RIEN DE PERDU et le nombre de cartouches gardé :
--   - arme d'origine sans munitions (mêlée) : rien ;
--   - arme remplaçante sans munitions : cartouches de l'arme rendues en objets (Ammo.unload), réserve gardée telle
--     quelle ;
--   - sinon : cartouches dans l'arme reportées (au plus la capacité de la nouvelle arme, le reste en cartouches
--     libres) ; cartouches libres d'un autre type échangées une pour une ; chargeurs d'un autre type échangés contre
--     des chargeurs de la nouvelle arme avec leurs cartouches (au plus sa capacité, le reste en cartouches libres),
--     ou vidés en cartouches libres si la nouvelle arme n'a pas de chargeur (l'objet chargeur est gardé). Mêmes
--     types : objets gardés tels quels.
-- Aucun état noté avant (munitions de départ pas encore posées par LK_Loot) : aucun état créé. Rend { loaded =
-- cartouches dans la nouvelle arme, rounds = cartouches libres créées, mags = chargeurs échangés }, ou nil et une
-- raison (rien n'est changé).
function Ammo.convert(z, fromType, toType)
    local out = { loaded = 0, rounds = 0, mags = 0 }
    if z == nil or fromType == toType then return out end
    local from = Ammo.spec(fromType)
    if from == nil then return out end
    local s = state(z)
    local to = Ammo.spec(toType)
    if to == nil then
        if s ~= nil then out.loaded = Ammo.unload(z, fromType) end
        return out
    end
    local spare = instanceItem(to.round)   -- type des cartouches vérifié avant tout retrait
    if spare == nil then return nil, "unknown ammo item " .. to.round end
    local function addRound(inv)
        local it = spare or instanceItem(to.round)
        spare = nil
        inv:AddItem(it)
        out.rounds = out.rounds + 1
    end
    local inv = z:getInventory()
    local loose, mags = {}, {}
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it ~= nil then
            local t = it:getFullType()
            if t == from.round and from.round ~= to.round then
                loose[#loose + 1] = it
            elseif from.mag ~= nil and t == from.mag and from.mag ~= to.mag then
                mags[#mags + 1] = it
            end
        end
    end
    local extra = 0
    for _, it in ipairs(loose) do   -- liste Java modifiée hors de son parcours
        inv:DoRemoveItem(it)
        extra = extra + 1
    end
    for _, it in ipairs(mags) do
        local c = it:getCurrentAmmoCount()
        c = (type(c) == "number" and c > 0) and math.floor(c) or 0
        local m = to.mag ~= nil and instanceItem(to.mag) or nil
        if m ~= nil then
            local k = math.min(c, to.max)
            m:setCurrentAmmoCount(k)
            inv:AddItem(m)
            inv:DoRemoveItem(it)
            out.mags = out.mags + 1
            extra = extra + c - k
        else
            it:setCurrentAmmoCount(0)
            extra = extra + c
        end
    end
    if s ~= nil and s.t == fromType then
        local n = Ammo.loaded(z, fromType)
        local k = math.min(n, to.max)
        setLoaded(z, toType, k)
        out.loaded = k
        extra = extra + n - k
    end
    for _ = 1, extra do addRound(inv) end
    count("converted")
    return out
end

-- Réinitialisation (tests).
function Ammo.reset()
    Ammo.specs = {}
end

return Ammo
