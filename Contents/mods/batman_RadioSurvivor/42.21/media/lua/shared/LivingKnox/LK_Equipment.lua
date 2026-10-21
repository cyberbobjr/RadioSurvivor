-- Living Knox : arme visible des corps de PNJ (LK02-T06). Fiche : docs/annexes/conception/equipement.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...) ; Lua vanilla sous media/lua.
--
-- Décision du 2026-10-09 : arme ACCROCHÉE (dos, hanche ou ceinture) au repos et en marche ; mise EN MAIN par chaque
-- machine d'affichage pour les gestes aim, guard et strike (LK_Anim), afin que la variable vanilla Weapon choisisse
-- les nœuds LKActorAimRifle, LKActorGuard1H, LKActorStrike1H (tools/anim_table.json).
--
-- Autorité (serveur, solo) : LivingKnox.Equipment.setWeapon(npcId, "Module.Objet" | nil) vérifie l'objet (instanceItem,
-- HandWeapon, emplacement d'accroche connu) et l'écrit dans le registre (champ facultatif npc.weapon, LK_Identity).
-- Serveur :
--   - pose l'objet accroché sur SA copie du corps (setAttachedItem ; aucun paquet, J/characters/IsoGameCharacter.java:
--     3183-3206) puis sendAttachedItem (J/Lua/LuaManager.java:9719-9724) : seuls les clients proches présents à l'envoi
--     le reçoivent (J/network/packets/GameCharacterAttachedItemPacket.java:94-105) ; renvoyé quand l'onlineId change ;
--   - publie la table complète { rev, w = { [npcId] = { t = type, l = emplacement, h = deux mains } } } (module
--     "LivingKnox", commande "equipState") à chaque changement et au client qui entre en partie (guardHello) ; un client
--     arrivé après, ou dont la copie est recréée, accroche lui-même l'objet d'après cette table ;
--   - ne pose JAMAIS d'objet en main d'un zombie : IsoGameCharacter.preupdate enverrait un paquet Equip typé joueur
--     (base zombies-as-npc-bodies.md).
-- Affichage (solo, client MP), toutes les APPLY_EVERY images, sur les corps connus de LivingKnox.Anim.knownBodies :
--   geste aim/guard/strike : objet en main (setPrimaryHandItem, et setSecondaryHandItem avec le même objet pour une arme
--   à deux mains : WeaponType ne rend firearm / 2handed que si les deux mains tiennent le même objet,
--   J/inventory/types/WeaponType.java:75-108), emplacement d'accroche vidé (pas d'affichage en double) ;
--   autre geste : mains vides, objet accroché. Idempotent : rien n'est réécrit quand l'état est juste ; une copie
--   recréée (nouvel objet) est reprise au passage suivant.
-- OnEquipPrimary : setPrimaryHandItem le déclenche pour tout personnage (J/characters/IsoGameCharacter.java:3016).
-- L'abonné vanilla de la pêche (media/lua/client/Fishing/FishingHandler.lua:15-20) est inscrit par référence et appelle
-- Fishing.Handler.handleFishing par la table (ligne 17) ; celle-ci suppose un joueur (getPlayerNum / getUsername,
-- lignes 23-24) et échoue sur un zombie. Equipment.guardEquipEvent enveloppe handleFishing, et lui seul : un personnage
-- qui n'est pas un IsoPlayer est ignoré, un joueur passe à l'original sans changement. Abonnés des autres mods relevés
-- en LK02-T13 (fiche, « Abonnés d'autres mods ») : aucun ne suppose un joueur, aucune autre enveloppe. Les abonnés
-- sont gardés par Java (Event.callbacks) et illisibles depuis Lua : pas de garde générique possible ; un mod ajouté
-- plus tard se vérifie à son tour. La pose reste rare (une par changement de geste).
--
-- Arme remplacée par un autre mod (LK07-T08, fiche equipement.md « Arme remplacée par un autre mod ») : un mod
-- d'armes peut échanger l'objet accroché d'un zombie (même emplacement, autre type d'arme). Chaque objet créé ici
-- porte la marque Equipment.MARK dans ses ModData ; à chaque passage, l'autorité (serveur, solo) relit l'objet
-- réellement accroché à l'emplacement voulu (et, hors serveur, en main) : une arme sans la marque, d'un autre type,
-- est ADOPTÉE (Equipment.adoptForeign) : registre npc.weapon = son type, objet déplacé vers son propre emplacement,
-- munitions converties par LivingKnox.Ammo.convert (rien de perdu). Arme inutilisable ici (emplacement inconnu,
-- pas une HandWeapon) : l'arme du registre est reposée comme avant. Aucun code ni marque du mod tiers n'est lu.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_ZombieGuard"
require "LivingKnox/LK_Anim"

local Equipment = LivingKnox.Equipment or {}
LivingKnox.Equipment = Equipment

Equipment.MODULE = "LivingKnox"
Equipment.CMD_STATE = "equipState"   -- serveur -> client(s) : { rev, w = { [npcId] = { t, l, h } } }
Equipment.APPLY_EVERY = 3            -- images entre deux passages d'affichage
Equipment.SLOW_EVERY = 15            -- images entre deux passages du serveur (accroche, envoi, publication)
Equipment.HAND_GESTURES = { aim = true, guard = true, strike = true, shoot = true, reload = true }   -- tir : LK06-T03
Equipment.MARK = "LKWeapon"          -- ModData d'un objet arme créé ici (identifiant du PNJ) : LK07-T08

-- Emplacement d'accroche selon l'AttachmentType du script de l'objet : emplacements vanilla de la barre d'accès rapide
-- (media/lua/client/Hotbar/ISHotbarAttachDefinition.lua : Back 77-94, HolsterRight 44-53, SmallBeltLeft 4-22), tous
-- déclarés dans le groupe Human (media/lua/shared/NPCs/AttachedLocations.lua:5-66). Ce fichier client n'existe pas sur
-- un serveur dédié : la table est reprise ici. Pas de variante « with Bag » : les tenues des PNJ n'ont pas de sac.
Equipment.LOCATIONS = {
    Rifle = "Rifle On Back", BigWeapon = "Big Weapon On Back", BigBlade = "Blade On Back", Sword = "Blade On Back",
    Shovel = "Shovel Back", Racket = "Racket On Back", Pan = "Pan On Back", Saucepan = "Saucepan Back",
    Guitar = "Guitar", GuitarAcoustic = "Guitar Acoustic",
    Holster = "Holster Right", HolsterSmall = "Holster Right",
    Knife = "Belt Left Upside", NotKnife = "Belt Left Upside", Hammer = "Belt Left", HammerRotated = "Belt Rotated Left",
    Nightstick = "Nightstick Left", Screwdriver = "Belt Left Screwdriver", Wrench = "Wrench Left",
    MeatCleaver = "MeatCleaver Belt Left",
}

Equipment.state = Equipment.state or { ticks = 0, slow = 0, rev = 0, signature = "" }
Equipment.remote = Equipment.remote or { rev = -1, w = {} }   -- client MP : dernière table reçue
Equipment.shown = Equipment.shown or {}   -- affichage : npcId -> { z, t, l } posé par nous sur cet objet
Equipment.sent = Equipment.sent or {}     -- serveur : npcId -> { z, o, t, l } accroché et envoyé
Equipment.specs = Equipment.specs or {}   -- type -> { t, l, h } ou { bad = raison } (instanceItem une fois par type)
Equipment.hooks = Equipment.hooks or {}
Equipment.reported = Equipment.reported or {}
Equipment.stats = Equipment.stats or { passes = 0, attached = 0, detached = 0, equipped = 0, unequipped = 0,
    sent = 0, published = 0, skipped = 0 }
Equipment.stats.adopted = Equipment.stats.adopted or 0   -- LK07-T08 : armes remplacées par un autre mod, adoptées

local function log() return LivingKnox.Log end

local function stat(name, n)
    Equipment.stats[name] = Equipment.stats[name] + (n or 1)
end

-- Une ligne de journal par clé (pas une par passage).
local function reportOnce(key, msg, ...)
    if Equipment.reported[key] then return end
    Equipment.reported[key] = true
    log().error(msg, ...)
end

-- ---------------------------------------------------------------- OnEquipPrimary

-- Enveloppe Fishing.Handler.handleFishing (client vanilla) une seule fois : un non-joueur est ignoré. Rend vrai si la
-- garde est en place. Appelée avant chaque pose en main (FishingHandler.lua est chargé après media/lua/shared).
function Equipment.guardEquipEvent()
    local F = Fishing and Fishing.Handler
    if type(F) ~= "table" or type(F.handleFishing) ~= "function" then return false end
    local hooks = Equipment.hooks
    if F.handleFishing == hooks.fishingWrapper then return true end
    local original = F.handleFishing
    local function wrapper(player, item, ...)
        if not instanceof(player, "IsoPlayer") then
            stat("skipped")
            return nil
        end
        return original(player, item, ...)
    end
    hooks.fishingOriginal, hooks.fishingWrapper = original, wrapper
    F.handleFishing = wrapper
    return true
end

-- ---------------------------------------------------------------- objets

-- Description d'une arme : { t = type, l = emplacement, h = deux mains }, ou nil et une raison. Instancie l'objet une
-- fois par type (moteur requis), résultat gardé.
function Equipment.spec(fullType)
    if not LivingKnox.Identity.isItemType(fullType) then return nil, "bad item type " .. tostring(fullType) end
    local known = Equipment.specs[fullType]
    if known then
        if known.bad then return nil, known.bad end
        return known
    end
    local item = instanceItem(fullType)
    local why
    if item == nil then
        why = "unknown item " .. fullType
    elseif not instanceof(item, "HandWeapon") then
        why = fullType .. " is not a weapon"
    else
        local kind = item:getAttachmentType()
        local loc = kind and Equipment.LOCATIONS[kind]
        if loc == nil then
            why = fullType .. " has no known attachment slot (AttachmentType " .. tostring(kind) .. ")"
        else
            known = { t = item:getFullType(), l = loc,
                h = item:isTwoHandWeapon() == true or item:isRequiresEquippedBothHands() == true }
        end
    end
    if why then known = { bad = why } end
    Equipment.specs[fullType] = known
    if why then return nil, why end
    return known
end

local function newItem(fullType)
    local item = instanceItem(fullType)
    if item == nil then
        reportOnce("item:" .. fullType, "cannot create item %s for an npc weapon", fullType)
    else
        item:getModData()[Equipment.MARK] = true   -- LK07-T08 : objet de ce module, jamais adopté
    end
    return item
end

local function isType(item, fullType)
    return item ~= nil and item:getFullType() == fullType
end

-- ---------------------------------------------------------------- arme voulue

local function Store() return LivingKnox.Store end

-- Arme voulue d'un PNJ sur cette machine (autorité : registre ; client : dernière table reçue), ou nil.
function Equipment.wantedOf(npcId)
    if not LivingKnox.isAuthority() then return Equipment.remote.w[npcId] end
    local S = Store()
    local registry = S and S.isReady() and S.data()
    local npc = registry and registry.npcs[npcId]
    if npc == nil or npc.weapon == nil then return nil end
    local spec, why = Equipment.spec(npc.weapon)
    if spec == nil then reportOnce("spec:" .. npcId .. ":" .. npc.weapon, "npc %s weapon ignored: %s", npcId, why) end
    return spec
end

-- Autorité : arme d'un PNJ (nil ou "none" : aucune). Rend vrai, ou faux et une raison.
function Equipment.setWeapon(npcId, fullType)
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    local S = Store()
    if S == nil or not S.isReady() then return false, "registry unavailable" end
    local npc = LivingKnox.Identity.get(S.data(), npcId)
    if npc == nil then return false, "unknown npc " .. tostring(npcId) end
    if fullType == "none" then fullType = nil end
    if fullType ~= nil then
        local spec, why = Equipment.spec(fullType)
        if spec == nil then return false, why end
        fullType = spec.t
    end
    if npc.weapon == fullType then return true end
    npc.weapon = fullType
    S.markChanged()   -- LK13-T10 : écrit à la fin de l'image (arme posée à la création d'un membre, même image)
    log().info("npc %s weapon %s", npcId, tostring(fullType or "none"))
    if isServer() then
        Equipment.serverPass()
        Equipment.publish(false)
    end
    return true
end

-- ---------------------------------------------------------------- arme remplacée par un autre mod (LK07-T08)

-- Serveur : objet accroché envoyé aux clients proches du corps z ; rend l'onlineId, ou nil.
local function send(z, loc, item)
    local o = z:getOnlineID()
    if type(o) ~= "number" or o < 0 then return nil end   -- les clients ne connaissent pas encore ce zombie
    sendAttachedItem(z, loc, item)
    stat("sent")
    return o
end

-- Vrai si item est une arme posée par un autre que ce module à la place de l'arme de type t.
local function foreign(item, t)
    if item == nil or not instanceof(item, "HandWeapon") or item:getFullType() == t then return false end
    return not (item:hasModData() and item:getModData()[Equipment.MARK] ~= nil)
end

-- Arme d'un autre type posée par un tiers sur le corps z à la place de l'arme voulue w : à l'emplacement w.l, ou en
-- main (jamais sur un serveur, où rien n'est en main). Rend l'objet et son emplacement (nil : en main), ou nil.
function Equipment.foreignWeapon(z, w)
    local a = z:getAttachedItem(w.l)
    if foreign(a, w.t) then return a, w.l end
    if not isServer() then
        local p = z:getPrimaryHandItem()
        if foreign(p, w.t) then return p, nil end
    end
    return nil
end

local function ammoText(r, why)
    if r == nil then return "ammo unchanged" .. (why and (": " .. tostring(why)) or "") end
    return string.format("%d round(s) in the weapon, %d loose round(s) and %d magazine(s) converted", r.loaded or 0,
        r.rounds or 0, r.mags or 0)
end

-- Autorité : l'arme réellement portée par le corps z du PNJ id, posée par un autre mod à la place de celle du
-- registre, devient l'arme du PNJ (registre, emplacement, munitions). Rend vrai si une arme a été adoptée.
function Equipment.adoptForeign(id, z)
    if not LivingKnox.isAuthority() or z == nil then return false end
    local S = Store()
    local registry = S and S.isReady() and S.data()
    local npc = registry and registry.npcs[id]
    if npc == nil or npc.weapon == nil then return false end
    local w = Equipment.spec(npc.weapon)
    if w == nil then return false end
    local item, loc = Equipment.foreignWeapon(z, w)
    if item == nil then return false end
    local newType = item:getFullType()
    local spec, why = Equipment.spec(newType)
    if spec == nil then
        reportOnce("foreign:" .. id .. ":" .. tostring(newType), "npc %s weapon %s replaced by %s, not usable by an "
            .. "npc (%s): %s put back", id, w.t, tostring(newType), tostring(why), w.t)
        return false
    end
    if loc ~= nil and loc ~= spec.l then   -- vers son propre emplacement (geste et affichage de son type)
        z:setAttachedItem(loc, nil)
        z:setAttachedItem(spec.l, item)
        if isServer() then send(z, loc, nil) end
    end
    item:getModData()[Equipment.MARK] = id
    local old = npc.weapon
    npc.weapon = spec.t
    S.markChanged()
    local A = LivingKnox.Ammo
    local r, rwhy
    if A ~= nil and A.convert ~= nil then r, rwhy = A.convert(z, old, spec.t) end
    stat("adopted")
    if isServer() then
        Equipment.sent[id] = nil   -- renvoyé par serverPass à son emplacement
    else
        local s = Equipment.shown[id]
        if s ~= nil and s.z == z then s.t, s.l = spec.t, spec.l end   -- objet désormais le nôtre
    end
    log().info("npc %s weapon %s replaced by %s by another mod, adopted (%s): %s", id, old, spec.t,
        loc ~= nil and ("attached, " .. spec.l) or "in hand", ammoText(r, rwhy))
    return true
end

-- adoptForeign protégé : une erreur est journalisée une fois et n'arrête pas le passage (LK_Loot.onDeath aussi).
local function safeAdopt(id, z)
    local ok, err = pcall(Equipment.adoptForeign, id, z)
    if ok then return err end
    reportOnce("adopt:" .. id .. ":" .. tostring(err), "npc %s replaced weapon not adopted: %s", id, tostring(err))
    return false
end
Equipment.adoptSafe = safeAdopt

-- ---------------------------------------------------------------- serveur

local function bound()
    local B = LivingKnox.Bodies
    return B and B.bound or nil
end

-- Table publiée : PNJ du registre qui ont une arme valide ; rend la table et sa signature.
function Equipment.buildTable()
    local w, parts = {}, {}
    local S = Store()
    local registry = S and S.isReady() and S.data()
    if not registry then return w, "" end
    for _, id in ipairs(LivingKnox.Identity.sortedIds(registry)) do
        local spec = Equipment.wantedOf(id)
        if spec then
            w[id] = { t = spec.t, l = spec.l, h = spec.h }
            parts[#parts + 1] = id .. "=" .. spec.t .. "@" .. spec.l
        end
    end
    return w, table.concat(parts, ";")
end

function Equipment.stateArgs(w)
    return { rev = Equipment.state.rev, w = w }
end

-- Serveur : envoie la table à tous les clients quand elle change (force : même inchangée).
function Equipment.publish(force)
    if not isServer() then return false end
    local w, signature = Equipment.buildTable()
    local st = Equipment.state
    if signature == st.signature and not force then return false end
    st.signature = signature
    st.rev = st.rev + 1
    sendServerCommand(Equipment.MODULE, Equipment.CMD_STATE, Equipment.stateArgs(w))
    stat("published")
    return true
end

-- Serveur : objet accroché sur la copie du serveur et envoyé aux clients proches (nouveau corps, arme changée,
-- nouvel onlineId après un retour de chunk).
function Equipment.serverPass()
    local b = bound()
    if b == nil or getCell() == nil then return end
    local sent = Equipment.sent
    local stale = {}
    for id, s in pairs(sent) do
        local z = b[id]
        if z ~= s.z or z == nil or z:isDead() then stale[#stale + 1] = id end
    end
    for _, id in ipairs(stale) do sent[id] = nil end   -- table modifiée hors de pairs
    for id, z in pairs(b) do
        -- Corps dans le monde seulement : un corps mis de côté (chunk déchargé) n'a plus d'onlineId valable.
        if z ~= nil and LivingKnox.Bodies.inWorld(z) then
            safeAdopt(id, z)   -- LK07-T08 : arme remplacée par un autre mod
            local w = Equipment.wantedOf(id)
            local s = sent[id]
            if s ~= nil and (w == nil or s.t ~= w.t or s.l ~= w.l) then
                if isType(z:getAttachedItem(s.l), s.t) then
                    z:setAttachedItem(s.l, nil)
                    stat("detached")
                end
                send(z, s.l, nil)
                sent[id] = nil
                s = nil
            end
            if w ~= nil then
                local item = z:getAttachedItem(w.l)
                local changed = false
                if not isType(item, w.t) then
                    item = newItem(w.t)
                    if item ~= nil then
                        z:setAttachedItem(w.l, item)
                        stat("attached")
                        changed = true
                    end
                end
                if item ~= nil and (changed or s == nil or s.o ~= z:getOnlineID()) then
                    local o = send(z, w.l, item)
                    if o ~= nil then sent[id] = { z = z, o = o, t = w.t, l = w.l } end
                end
            end
        end
    end
end

-- Serveur : un client entré en partie demande la liste des corps (guardHello) : il reçoit aussi les armes.
function Equipment.onClientCommand(module, command, player, args)
    local G = LivingKnox.ZombieGuard
    if module ~= Equipment.MODULE or command ~= G.CMD_HELLO or not isServer() or player == nil then return end
    local w = Equipment.buildTable()
    sendServerCommand(player, Equipment.MODULE, Equipment.CMD_STATE, Equipment.stateArgs(w))
end

-- ---------------------------------------------------------------- client MP

function Equipment.onServerCommand(module, command, args)
    if module ~= Equipment.MODULE or command ~= Equipment.CMD_STATE or not isClient() then return end
    if type(args) ~= "table" or type(args.rev) ~= "number" then return end
    if args.rev < Equipment.remote.rev then return end
    local w = {}
    if type(args.w) == "table" then   -- table vide envoyée = nil reçu
        for id, e in pairs(args.w) do
            if type(id) == "string" and type(e) == "table" and LivingKnox.Identity.isItemType(e.t)
                and type(e.l) == "string" then
                w[id] = { t = e.t, l = e.l, h = e.h == true }
            end
        end
    end
    Equipment.remote.rev, Equipment.remote.w = args.rev, w
end

-- ---------------------------------------------------------------- affichage (solo, client MP)

local function equip(z, item, twoHands)
    Equipment.guardEquipEvent()
    z:setPrimaryHandItem(item)
    if twoHands then
        z:setSecondaryHandItem(item)
    elseif z:getSecondaryHandItem() ~= nil then
        z:setSecondaryHandItem(nil)
    end
    stat("equipped")
end

local function unequip(z)
    Equipment.guardEquipEvent()
    if z:getSecondaryHandItem() ~= nil then z:setSecondaryHandItem(nil) end
    z:setPrimaryHandItem(nil)
    stat("unequipped")
end

-- Pose l'état voulu sur la copie locale z. w = arme voulue ou nil ; hand = geste qui tient l'arme ; prev = ce que nous
-- avons posé sur ce même objet (ou nil). Rend le nombre de changements (0 : déjà juste).
function Equipment.applyTo(z, w, hand, prev)
    local n = 0
    local primary = z:getPrimaryHandItem()
    if prev ~= nil and (w == nil or prev.t ~= w.t or prev.l ~= w.l) then
        if primary ~= nil and isType(primary, prev.t) then
            unequip(z)
            primary = nil
            n = n + 1
        end
        if isType(z:getAttachedItem(prev.l), prev.t) then
            z:setAttachedItem(prev.l, nil)
            stat("detached")
            n = n + 1
        end
    end
    if w == nil then return n end
    local attached = z:getAttachedItem(w.l)
    local attachedOk = isType(attached, w.t)
    if hand then
        if not isType(primary, w.t) then
            local item = attachedOk and attached or newItem(w.t)
            if item == nil then return n end
            if attachedOk then
                z:setAttachedItem(w.l, nil)   -- passe du dos (ou de la hanche) à la main
                stat("detached")
            end
            equip(z, item, w.h)
            return n + 1
        end
        if attachedOk then   -- renvoi du serveur reçu pendant le geste : pas d'affichage en double
            z:setAttachedItem(w.l, nil)
            stat("detached")
            n = n + 1
        end
        local second = nil
        if w.h then second = primary end
        if z:getSecondaryHandItem() ~= second then
            Equipment.guardEquipEvent()
            z:setSecondaryHandItem(second)
            n = n + 1
        end
        return n
    end
    if primary ~= nil then
        unequip(z)
        n = n + 1
    end
    if not attachedOk then
        local item = isType(primary, w.t) and primary or newItem(w.t)
        if item == nil then return n end
        z:setAttachedItem(w.l, item)
        stat("attached")
        n = n + 1
    end
    return n
end

local function safeApply(id, z, w, hand, prev)
    local ok, err = pcall(Equipment.applyTo, z, w, hand, prev)
    if ok then return true end
    reportOnce("apply:" .. id .. ":" .. tostring(err), "npc %s weapon display failed: %s", id, tostring(err))
    return false
end

-- Passage d'affichage : corps connus de LK_Anim (solo : corps reliés ; client : copies retrouvées par la garde).
function Equipment.displayPass()
    local known = LivingKnox.Anim.knownBodies()
    local shown = Equipment.shown
    local stale = {}
    for id, s in pairs(shown) do
        if known[id] ~= s.z then stale[#stale + 1] = id end
    end
    for _, id in ipairs(stale) do   -- table modifiée hors de pairs
        local s = shown[id]
        shown[id] = nil
        if s.z ~= nil and not s.z:isDead() then safeApply(id, s.z, nil, false, s) end
    end
    local auth = LivingKnox.isAuthority()
    for id, z in pairs(known) do
        if auth then safeAdopt(id, z) end   -- LK07-T08 (solo) : arme remplacée par un autre mod
        local w = Equipment.wantedOf(id)
        local hand = Equipment.HAND_GESTURES[LivingKnox.Anim.gestureOf(id)] == true
        if safeApply(id, z, w, hand, shown[id]) then
            if w ~= nil then shown[id] = { z = z, t = w.t, l = w.l } else shown[id] = nil end
        end
    end
    stat("passes")
end

-- ---------------------------------------------------------------- abonnements

function Equipment.tick()
    local st = Equipment.state
    st.ticks = st.ticks + 1
    if st.ticks < Equipment.APPLY_EVERY then return end
    st.ticks = 0
    st.slow = st.slow + Equipment.APPLY_EVERY
    local slow = st.slow >= Equipment.SLOW_EVERY
    if slow then st.slow = 0 end
    if getCell() == nil then return end
    if isServer() then
        if slow then
            Equipment.serverPass()
            Equipment.publish(false)
        end
        return
    end
    Equipment.displayPass()
end

local function onTick()
    LivingKnox.Equipment.tick()
end

LivingKnox.subscribe("OnTick", "Equipment.tick", onTick)

if isServer() then
    local function onClientCommand(module, command, player, args)
        LivingKnox.Equipment.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnClientCommand", "Equipment.onClientCommand", onClientCommand)
elseif isClient() then
    local function onServerCommand(module, command, args)
        LivingKnox.Equipment.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "Equipment.onServerCommand", onServerCommand)
end

return Equipment
