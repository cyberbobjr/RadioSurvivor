-- Living Knox : obstacles, clés des foyers portées par les corps (LK04-T12).
-- LK20-T09 : sorti de LK_Obstacles.lua sans changement de comportement ; façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- clés (LK04-T12)
-- Fiche : deplacement.md, section « Portes », « Clés ». Java 42.21.0 :
-- - clé d'une porte : IsoDoor:checkKeyId() (celle qu'emploient ISLockDoor.lua:6, IsoDoor.ToggleDoor et saveState,
--   J/iso/objects/IsoDoor.java:805, 1326, 1979-2002) : keyId propre de la porte, sinon celui du bâtiment
--   (BuildingDef:getKeyId) quand un seul côté est dans un bâtiment (ou sprite forceLocked) ; porte intérieure sans
--   keyId : -1, aucune clé. Porte construite IsoThumpable : getKeyId(). Le keyId d'un bâtiment est tiré à sa création
--   et sauvegardé dans map_meta.bin (J/iso/BuildingDef.java:72-75, J/iso/IsoMetaGrid.java:923, 1041-1053) ;
-- - une clé est un objet de classe Key (Base.Key1, ItemType base:key, media/scripts/generated/items/key.txt:3-15),
--   keyId fixé par setKeyId (J/inventory/types/Key.java : -1 tiré au hasard ; sauvegardé avec l'objet) ;
--   ItemContainer:haveThisKeyId(keyId) la cherche dans l'inventaire et les porte-clés (J/inventory/ItemContainer.java:
--   3052-3064), comme pour un joueur (IsoDoor.java:1347-1366).
-- - inventaire du corps : un joueur réanimé garde l'inventaire du cadavre dont il sort (IsoDeadBody.reanimate,
--   IsoDeadBody.java:1850-1853) ; à sa mort, DoZombieInventory ne fait rien pour un joueur réanimé
--   (J/characters/IsoZombie.java:3129-3133) et le cadavre prend l'inventaire du mort (IsoDeadBody.java:327-332) :
--   la clé posée sur le corps se retrouve sur son cadavre. Sauvegardée avec le corps (reanimated.bin,
--   IsoGameCharacter.save, IsoGameCharacter.java:5032).
-- Règles : chaque membre d'un groupe dont le foyer est un bâtiment porte UNE clé Base.Key1 au keyId de ce bâtiment,
-- marquée KEY_TAG (ModData de l'objet : identifiant du bâtiment). Posée par l'autorité sur SA copie du corps
-- (l'inventaire d'un zombie n'est jamais envoyé aux clients ; le cadavre part avec son contenu). Le corps garde dans
-- sa ModData (KEY_GIVEN) le keyId déjà remis : la clé n'est remise qu'une fois par corps et par foyer (une clé perdue
-- par le corps courant ne revient pas ; chaque nouveau corps, à chaque incarnation, reçoit la sienne ; un corps relu
-- de reanimated.bin garde la sienne, sans doublon). Foyer changé : les clés KEY_TAG du corps sont RETIRÉES et la clé
-- du nouveau foyer posée (aucune clé d'un ancien foyer) ; plus de foyer ni de groupe : clés KEY_TAG retirées. Une
-- clé non marquée (butin futur) n'est jamais touchée.
Obstacles.KEY_ITEM = "Base.Key1"
Obstacles.KEY_TAG = "LKHomeKey"        -- ModData de la clé : identifiant du bâtiment du foyer (getIDString)
Obstacles.KEY_GIVEN = "LKKeyGiven"     -- ModData du corps : keyId de la clé déjà remise à ce corps
Obstacles.KEYS_EVERY_MS = 2000         -- relevé des clés des corps liés (foyer changé)
Obstacles.KEYHOLDER_RADIUS = 20        -- cases : membre « au foyer » (dans le bâtiment, ou à cette distance du foyer)

-- keyId, identifiant du bâtiment et groupe du foyer du PNJ npcId ; nil sans groupe, sans foyer ou foyer hors de tout
-- bâtiment (métagrille seulement : getBuildingAt(x, y, z) indexé).
function Obstacles.homeKeyOf(npcId)
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil end
    local gid = G.findNpc(npcId)
    local g = gid and G.peek(gid)   -- LK13-T08 : lecture en place, seule (passage fréquent des clés)
    local h = g and g.home
    if h == nil then return nil end
    local def = getWorld():getMetaGrid():getBuildingAt(h.x, h.y, h.z)
    if def == nil then return nil end
    return def:getKeyId(), def:getIDString(), gid
end

-- Clés posées par ce module (objets Key marqués KEY_TAG) dans l'inventaire du corps z.
function Obstacles.keysOf(z)
    local out = {}
    local items = z:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if instanceof(it, "Key") and it:hasModData() and it:getModData()[Obstacles.KEY_TAG] ~= nil then
            out[#out + 1] = it
        end
    end
    return out
end

-- Retire du corps z les clés posées par ce module. Rend leur nombre.
function Obstacles.removeKeys(z)
    local inv = z:getInventory()
    local keys = Obstacles.keysOf(z)
    for _, k in ipairs(keys) do inv:DoRemoveItem(k) end
    return #keys
end

-- Vrai si le corps z porte une clé (objet Key, porte-clés compris) de keyId.
function Obstacles.hasKey(z, keyId)
    if z == nil or keyId == nil or keyId == -1 then return false end
    return z:getInventory():haveThisKeyId(keyId) ~= nil
end

-- Clé de la porte door (voir l'en-tête de la section) ; -1 : aucune.
function Obstacles.doorKeyId(door)
    if instanceof(door, "IsoDoor") then return door:checkKeyId() end
    return door:getKeyId()
end

-- Case de l'autre côté d'une porte (bord nord : case au nord ; bord ouest : case à l'ouest), ou nil.
local function oppositeOf(door)
    local sq = door:getSquare()
    if sq == nil then return nil end
    if door:getNorth() then return getCell():getGridSquare(sq:getX(), sq:getY() - 1, sq:getZ()) end
    return getCell():getGridSquare(sq:getX() - 1, sq:getY(), sq:getZ())
end

-- Ouverture « de l'intérieur » d'une porte verrouillée, sans clé (LK04-T17), pour un personnage sur la case from.
-- Règle vanilla d'un joueur (Java 42.21.0) :
-- - IsoDoor (canBeOpenFromInside, J/iso/objects/IsoDoor.java:1266-1268) : case du personnage non extérieure
--   (IsoGameCharacter.isOutside = drapeau exterior de la case, IsoGameCharacter.java:9340-9345,
--   IsoGridSquare.java:7968-7970), dans la pièce de l'une des deux cases de la porte, sprite sans forceLocked
--   (porte blindée). couldBeOpen rend alors vrai avant tout test de clé (:1271-1291) et ToggleDoorActual déverrouille
--   puis ouvre (:1343-1346), portes de garage comprises (:1389-1403) ;
-- - IsoThumpable (porte construite) : le verrou (clé ou bouton) ne retient que sur une case extérieure
--   (IsoThumpable.java:1100-1114, 1136-1153).
-- Une porte verrouillée de l'extérieur sans keyId (-1 : porte intérieure, IsoDoor.java:1979-2002) ne s'ouvre donc que
-- de l'intérieur, et toute porte d'un bâtiment s'ouvre sans clé depuis une pièce : le verrou ne retient que celui qui
-- est dehors.
function Obstacles.opensFromInside(door, from)
    if from == nil or from:isOutside() then return false end
    if P.isThumpable(door) then return true end
    local props = door:getProperties()
    if props ~= nil and props:has("forceLocked") then return false end
    local room = from:getRoom()
    local sq, other = door:getSquare(), oppositeOf(door)
    return (sq ~= nil and room == sq:getRoom()) or (other ~= nil and room == other:getRoom())
end

-- Clé du foyer du PNJ npcId sur son corps z (règles ci-dessus). Autorité seulement. Rend le keyId porté pour le foyer
-- (nil : aucun foyer) et ce qui a été fait : "kept", "given", "changed", "removed", "none".
function Obstacles.giveKey(npcId, z)
    if z == nil or not LivingKnox.isAuthority() then return nil, "none" end
    local want, bid = Obstacles.homeKeyOf(npcId)
    local md = z:getModData()
    local given = md[Obstacles.KEY_GIVEN]
    if given == want then return want, want and "kept" or "none" end
    local removed = 0
    if given ~= nil then removed = Obstacles.removeKeys(z) end
    if want == nil then
        md[Obstacles.KEY_GIVEN] = nil
        P.count("keysRemoved")
        LivingKnox.Log.info("npc %s: %d key(s) of a former home removed (no home)", npcId, removed)
        return nil, "removed"
    end
    local key = instanceItem(Obstacles.KEY_ITEM)
    key:setKeyId(want)
    key:getModData()[Obstacles.KEY_TAG] = bid
    z:getInventory():AddItem(key)
    md[Obstacles.KEY_GIVEN] = want
    P.count("keysGiven")
    LivingKnox.Log.info("npc %s: key %s of its home building %s given%s", npcId, tostring(want), tostring(bid),
        removed > 0 and (" (" .. removed .. " key(s) of a former home removed)") or "")
    return want, given ~= nil and "changed" or "given"
end

-- Toutes les KEYS_EVERY_MS : clés des corps liés dans le monde (foyer changé, groupe quitté). La remise à la liaison
-- d'un corps se fait dans Bodies.guardNow.
function Obstacles.keyPass(t)
    local st = Obstacles.state
    if st.keysMs ~= nil and t - st.keysMs < Obstacles.KEYS_EVERY_MS then return end
    st.keysMs = t
    local B = LivingKnox.Bodies
    local ids = {}
    for id in pairs(B.bound) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local z = B.bound[id]
        if z ~= nil and B.inWorld(z) then Obstacles.giveKey(id, z) end
    end
end

-- Membre du groupe du foyer h ({ gid, id, x, y }) présent au foyer (corps dans le monde, dans le bâtiment du foyer ou
-- à KEYHOLDER_RADIUS cases au plus du point du foyer) et portant une clé de keyId : identifiant du PNJ, ou nil.
function Obstacles.keyHolderAt(h, keyId)
    if keyId == nil or keyId == -1 then return nil end
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil end
    local B = LivingKnox.Bodies
    local ids = {}
    for id in pairs(B.bound) do ids[#ids + 1] = id end
    table.sort(ids)
    local R = Obstacles.KEYHOLDER_RADIUS
    for _, id in ipairs(ids) do
        local z = B.bound[id]
        if z ~= nil and B.inWorld(z) and G.findNpc(id) == h.gid then
            Obstacles.giveKey(id, z)
            if Obstacles.hasKey(z, keyId) then
                local sq = getCell():getGridSquare(math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()))
                if P.buildingOf(sq) == h.id or (math.abs(z:getX() - h.x) <= R and math.abs(z:getY() - h.y) <= R) then
                    return id
                end
            end
        end
    end
    return nil
end

P.oppositeOf = oppositeOf
