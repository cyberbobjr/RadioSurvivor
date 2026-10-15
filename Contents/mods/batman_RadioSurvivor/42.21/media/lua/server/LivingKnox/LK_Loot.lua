-- Living Knox : butin réel du cadavre d'un PNJ (LK07-T05). Fiche : docs/conception/sante.md, section « Butin réel du
-- cadavre (LK07-T05) ». Java 42.21.0 cité en abrégé (J = zombie/...).
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- L'inventaire d'un corps (joueur réanimé) est gardé jusqu'au cadavre : DoZombieInventory ne fait rien pour lui et le
-- cadavre prend l'inventaire du mort (J/characters/IsoZombie.java:3129-3133, J/iso/objects/IsoDeadBody.java:327-332).
-- Il n'existe que sur la copie de l'autorité ; chaque client MP reçoit le contenu du cadavre serveur avec le paquet de
-- mort (IsoDeadBody.writeInventory, J/iso/objects/IsoDeadBody.java:2345-2376 ; DeadCharacterPacket.java:150-174) :
-- butin identique pour tous les joueurs.
--
-- Construction (Loot.build, une seule fois par corps) : passage toutes les EVERY_MS sur les corps reliés dans le
-- monde, et au plus tard à la mort. Marque persistante MD_BUILT dans les ModData du corps (sauvegardées avec lui dans
-- reanimated.bin) : un corps relu ou relié de nouveau n'est jamais rempli deux fois ; un nouveau corps (incarnation
-- suivante) a des ModData neuves et reçoit son propre butin (l'ancien corps a quitté le monde avec le sien). Contenu :
--   - munitions de l'arme à feu du registre (npc.weapon, LivingKnox.Ammo) selon le niveau de munitions du groupe
--     (needs.ammo 0..100 ; sans groupe : AMMO_LEVEL) : cartouches dans l'arme (fraction de la capacité), chargeurs
--     pleins de réserve (arme à chargeur) ou cartouches libres (sinon). Un état déjà noté (Ammo.give d'une suite)
--     n'est pas réécrit ;
--   - poches selon le rôle du membre (POCKETS[rôle] : vrais objets vanilla, petite quantité) ; un PNJ hors groupe
--     n'a pas de poches ;
--   - objets de mission : point d'appel Loot.missionItems(npcId, info) (aucune API de mission ne confie d'objet à un
--     PNJ en 42.21 du mod) ; liste { { t = "Module.Objet", n = 1..MISSION_MAX }, ... }, contrôlée ici.
-- Un type d'objet inconnu du jeu est sauté (une ligne de journal par type).
--
-- Mort (Loot.onDeath, appelé par Bodies.onZombieDead pour le corps courant, une seule fois par corps, marque
-- MD_DEAD) : OnZombieDead part dans onKilled, AVANT la création du cadavre (J/characters/IsoZombie.java:4599-4609,
-- J/characters/IsoGameCharacter.java:13478-13541) : ce qui est posé ici part dans le cadavre.
--   - arme du registre gardée DANS le cadavre, accrochée à son emplacement et dans son conteneur, de la même façon
--     partout : objet accroché de la copie de l'autorité (sinon objet en main en solo, sinon objet neuf). Un objet
--     accroché qui n'est pas dans le conteneur est perdu sur un serveur : setAttachedItems ne l'ajoute au conteneur
--     qu'en solo (J/iso/objects/IsoDeadBody.java:565-585), writeInventory et la sauvegarde ne gardent que les objets
--     accrochés présents dans le conteneur (indexOf, 2360-2371 ; relecture 793). Un objet en main d'un zombie n'est
--     pas repris par le cadavre (aucune lecture des mains dans le constructeur) : en solo, mains vidées et arme
--     raccrochée ; sur un serveur, la copie du serveur ne tient jamais rien en main (LK_Equipment), donc dropHeldItems
--     ne pose rien au sol (J/characters/IsoGameCharacter.java:10351-10376) ;
--   - cartouches de l'arme rendues en objets (Ammo.unload : chargeur engagé avec ses cartouches, ou cartouches
--     libres), état noté effacé.
-- Aucune duplication : une seule construction par corps, une seule mort comptée par corps (Bodies.onZombieDead ne
-- traite que le corps courant ; cadavre traîné ou relevé ignoré), l'arme n'est jamais créée si l'objet du corps existe.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Ammo"
require "LivingKnox/LK_Equipment"

local Loot = LivingKnox.Loot or {}
LivingKnox.Loot = Loot

Loot.MD_BUILT = "LKLoot"        -- ModData du corps : version du butin construit (une seule fois par corps)
Loot.MD_DEAD = "LKLootDead"     -- ModData du corps : butin de mort posé (arme, cartouches de l'arme)
Loot.VERSION = 1

-- Réglages (lus à chaque appel ; valeurs et raisons : docs/conception/sante.md, « Butin réel du cadavre »).
-- POCKETS : objets de poche par rôle (Config.GROUP_ROLES), types vanilla 42.21 relevés dans
-- media/scripts/generated/items (literature.txt Notepad ; weapon.txt Pencil, Screwdriver ; drainable.txt Lighter,
-- AlcoholWipes, HandTorch, DuctTape, Matches ; normal.txt Bandage, Tweezers, Nails ; food.txt GranolaBar, Chocolate ;
-- map.txt Map).
LivingKnox.Config.LOOT = LivingKnox.Config.LOOT or {
    EVERY_MS = 1000,          -- passage de construction sur les corps reliés
    AMMO_LEVEL = 50,          -- niveau de munitions d'un PNJ sans groupe (0..100)
    RESERVE_MAGS = 2,         -- chargeurs pleins de réserve au niveau 100 (arme à chargeur)
    RESERVE_ROUNDS = 12,      -- cartouches libres de réserve au niveau 100 (arme sans chargeur)
    MISSION_MAX = 5,          -- objets d'un même type au plus par entrée de mission
    POCKETS = {
        deputy = { { t = "Base.Notepad", n = 1 }, { t = "Base.Pencil", n = 1 }, { t = "Base.Lighter", n = 1 } },
        fighter = { { t = "Base.Bandage", n = 1 }, { t = "Base.Chocolate", n = 1 } },
        scout = { { t = "Base.Map", n = 1 }, { t = "Base.HandTorch", n = 1 }, { t = "Base.GranolaBar", n = 1 } },
        medic = { { t = "Base.Bandage", n = 2 }, { t = "Base.AlcoholWipes", n = 1 }, { t = "Base.Tweezers", n = 1 } },
        worker = { { t = "Base.Nails", n = 5 }, { t = "Base.Screwdriver", n = 1 } },
        breaker = { { t = "Base.DuctTape", n = 1 }, { t = "Base.Matches", n = 1 } },
    },
}

-- Point d'appel des objets de mission (LK12) : function(npcId, info) -> { { t, n }, ... } ou nil ; info = { npc =
-- entrée du registre, group, member, role }. Absent par défaut (champ Loot.missionItems).

Loot.state = Loot.state or { ms = nil }
Loot.reported = Loot.reported or {}
Loot.stats = Loot.stats or { built = 0, items = 0, rounds = 0, deaths = 0, weaponsKept = 0, weaponsCreated = 0,
    unloaded = 0, skipped = 0, missions = 0 }

local function cfg() return LivingKnox.Config.LOOT end
local function log() return LivingKnox.Log end
local function Ammo() return LivingKnox.Ammo end
local function Equipment() return LivingKnox.Equipment end

local function count(name, n)
    Loot.stats[name] = (Loot.stats[name] or 0) + (n or 1)
end

local function reportOnce(key, msg, ...)
    if Loot.reported[key] then return end
    Loot.reported[key] = true
    log().warn(msg, ...)
end

local function isType(item, fullType)
    return item ~= nil and item:getFullType() == fullType
end

-- Vrai si le conteneur inv contient l'objet item (premier niveau).
local function holds(inv, item)
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        if rawequal(items:get(i), item) then return true end
    end
    return false
end

-- Groupe, membre et rôle du PNJ id, et niveau de munitions (0..100) qui s'applique à lui.
function Loot.contextOf(id)
    local level = cfg().AMMO_LEVEL
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return { level = level } end
    local gid, mid = G.findNpc(id)
    local g = gid and G.get(gid)
    if g == nil then return { level = level } end
    local m = g.members and g.members[mid]
    local needs = g.needs
    if needs ~= nil and type(needs.ammo) == "number" then level = needs.ammo end
    return { group = gid, member = mid, role = m and m.role or nil, level = level }
end

-- Munitions de départ de l'arme à feu gunType au niveau level (0..100) : cartouches dans l'arme, chargeurs pleins et
-- cartouches libres de réserve. Rend nil si ce n'est pas une arme à feu.
function Loot.ammoPlan(gunType, level)
    local spec = Ammo().spec(gunType)
    if spec == nil then return nil end
    local f = math.max(0, math.min(100, tonumber(level) or 0)) / 100
    local c = cfg()
    local plan = { loaded = math.floor(spec.max * f + 0.5), mags = 0, rounds = 0 }
    if spec.mag ~= nil then
        plan.mags = math.floor(c.RESERVE_MAGS * f + 0.5)
    else
        plan.rounds = math.floor(c.RESERVE_ROUNDS * f + 0.5)
    end
    return plan
end

-- Ajoute n objets de type t au conteneur inv. Rend le nombre ajouté (0 pour un type inconnu, signalé une fois).
local function addItems(inv, t, n, why)
    if not LivingKnox.Identity.isItemType(t) then
        reportOnce("bad:" .. tostring(t), "loot item type %s refused (%s)", tostring(t), why)
        count("skipped")
        return 0
    end
    local added = 0
    for _ = 1, n do
        local it = instanceItem(t)
        if it == nil then
            reportOnce("unknown:" .. t, "loot item %s is unknown to the game (%s): skipped", t, why)
            count("skipped")
            return added
        end
        inv:AddItem(it)
        added = added + 1
    end
    return added
end

-- Liste { { t, n } } contrôlée (n entier 1..max) ; entrées fautives sautées.
local function entries(list, max)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if type(e) == "table" and type(e.t) == "string" and type(e.n) == "number" and e.n == e.n and e.n >= 1 then
            out[#out + 1] = { t = e.t, n = math.min(max, math.floor(e.n)) }
        end
    end
    return out
end

-- Construit l'inventaire du corps z du PNJ id, une seule fois (marque MD_BUILT). Rend vrai s'il vient d'être construit,
-- sinon faux et la raison.
function Loot.build(id, z)
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    if z == nil then return false, "no body" end
    local md = z:getModData()
    if md[Loot.MD_BUILT] ~= nil then return false, "already built" end
    md[Loot.MD_BUILT] = Loot.VERSION   -- posée d'abord : une erreur plus bas ne fait jamais construire deux fois
    local S = LivingKnox.Store
    local npc = S ~= nil and S.isReady() and S.data().npcs[id] or nil
    local ctx = Loot.contextOf(id)
    local inv = z:getInventory()
    local items, rounds, parts = 0, 0, {}
    -- Munitions de l'arme à feu du registre.
    local gun = npc and npc.weapon
    local plan = gun and Loot.ammoPlan(gun, ctx.level) or nil
    if plan ~= nil then
        local A = Ammo()
        if not A.hasState(z) then
            local n = A.setLoaded(z, gun, plan.loaded)
            rounds = rounds + (n or 0)
        end
        local added, why = A.addReserve(z, gun, plan.rounds, plan.mags)
        if added == nil then
            reportOnce("ammo:" .. gun, "npc %s reserve ammo for %s not given: %s", id, gun, tostring(why))
        else
            rounds = rounds + added
            items = items + plan.rounds + plan.mags
        end
        parts[#parts + 1] = string.format("%s: %d loaded, %d magazine(s), %d loose round(s) (ammo level %s)", gun,
            plan.loaded, plan.mags, plan.rounds, tostring(ctx.level))
    end
    -- Poches du rôle.
    local pockets = ctx.role and cfg().POCKETS[ctx.role] or nil
    if pockets ~= nil then
        local n = 0
        for _, e in ipairs(entries(pockets, 100)) do n = n + addItems(inv, e.t, e.n, "pockets of " .. ctx.role) end
        items = items + n
        parts[#parts + 1] = string.format("%d pocket item(s) of a %s", n, ctx.role)
    end
    -- Objets de mission (point d'appel).
    if type(Loot.missionItems) == "function" then
        local ok, list = pcall(Loot.missionItems, id, { npc = npc, group = ctx.group, member = ctx.member,
            role = ctx.role })
        if not ok then
            log().error("npc %s mission items failed: %s", id, tostring(list))
        else
            local n = 0
            for _, e in ipairs(entries(list, cfg().MISSION_MAX)) do n = n + addItems(inv, e.t, e.n, "mission") end
            items = items + n
            count("missions", n)
            if n > 0 then parts[#parts + 1] = string.format("%d mission item(s)", n) end
        end
    end
    count("built")
    count("items", items)
    count("rounds", rounds)
    log().info("npc %s loot built: %s", id, #parts > 0 and table.concat(parts, "; ") or "nothing")
    return true
end

-- Mort du corps courant z du PNJ id (Bodies.onZombieDead, avant la création du cadavre). Rend vrai si le butin de
-- mort vient d'être posé.
function Loot.onDeath(id, z)
    if not LivingKnox.isAuthority() or z == nil then return false end
    local md = z:getModData()
    if md[Loot.MD_DEAD] then return false end
    local E0 = Equipment()
    if E0 ~= nil and E0.adoptSafe ~= nil then
        E0.adoptSafe(id, z)   -- LK07-T08 : arme remplacée par un autre mod depuis le dernier passage
    end
    Loot.build(id, z)
    md[Loot.MD_DEAD] = true
    count("deaths")
    local inv = z:getInventory()
    local E = Equipment()
    local w = E ~= nil and E.wantedOf(id) or nil
    local kept, unloaded = "none", 0
    if w ~= nil then
        local attached = z:getAttachedItem(w.l)
        local primary, secondary = z:getPrimaryHandItem(), z:getSecondaryHandItem()
        local item
        if isType(attached, w.t) then
            item, kept = attached, "attached"
        elseif isType(primary, w.t) then
            item, kept = primary, "in hand"
        else
            item = instanceItem(w.t)
            kept = item ~= nil and "created" or "none"
        end
        -- Mains vidées (solo : un objet en main n'est pas repris par le cadavre ; jamais sur un serveur, où rien n'est
        -- en main et où setPrimaryHandItem sur un zombie enverrait un paquet Equip typé joueur).
        if not isServer() and (primary ~= nil or secondary ~= nil) then
            E.guardEquipEvent()
            if secondary ~= nil then z:setSecondaryHandItem(nil) end
            if primary ~= nil then z:setPrimaryHandItem(nil) end
        end
        if item ~= nil then
            if not rawequal(attached, item) then z:setAttachedItem(w.l, item) end
            if not holds(inv, item) then inv:AddItem(item) end
            if kept == "created" then count("weaponsCreated") else count("weaponsKept") end
        end
        unloaded = Ammo().unload(z, w.t)
    else
        Ammo().unload(z, nil)   -- état noté d'une ancienne arme : effacé
    end
    count("unloaded", unloaded)
    log().info("npc %s death loot: weapon %s (%s), %d round(s) of the weapon turned into items, %d item(s) in the "
        .. "corpse", id, w and w.t or "none", kept, unloaded, inv:getItems():size())
    return true
end

-- Passage : butin des corps reliés dans le monde qui n'en ont pas encore (incarnation, matérialisation : l'arme et le
-- lien de groupe sont posés dans le même appel Lua que la création, avant ce passage).
function Loot.pass()
    local B = LivingKnox.Bodies
    if B == nil or B.bound == nil or getCell() == nil then return 0 end
    local S = LivingKnox.Store
    if S == nil or not S.isReady() then return 0 end
    local ids = {}
    for id in pairs(B.bound) do ids[#ids + 1] = id end
    table.sort(ids)
    local n = 0
    for _, id in ipairs(ids) do
        local z = B.bound[id]
        if z ~= nil and B.inWorld(z) and z:getModData()[Loot.MD_BUILT] == nil then
            local ok, err = pcall(Loot.build, id, z)
            if not ok then
                log().error("npc %s loot not built: %s", id, tostring(err))
            else
                n = n + 1
            end
        end
    end
    return n
end

function Loot.tick()
    local t = getTimestampMs()
    local st = Loot.state
    if st.ms ~= nil and t - st.ms < cfg().EVERY_MS then return end
    st.ms = t
    Loot.pass()
end

local function onTick()
    LivingKnox.Loot.tick()
end

LivingKnox.subscribe("OnTick", "Loot.tick", onTick)

return Loot
