-- Living Knox : obstacles, portes : bords, état d'une porte, bâtiments des foyers (LK04-T02, LK04-T10),
-- décision devant une porte et effet (LK04-T12, LK04-T17, LK04-T20).
-- LK20-T09 : sorti de LK_Obstacles.lua sans changement de comportement ; façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- portes

-- Bord entre la case (x, y) et sa voisine est (kind "W" : bord ouest de x + 1) ou sud (kind "N" : bord nord de y + 1).
-- Rend { key, kind, ex, ey, mx, my, ax, ay, bx, by, z } (a = case ouest ou nord, b = case est ou sud).
local function edge(x, y, z, kind)
    local e = { kind = kind, z = z, ax = x, ay = y }
    if kind == "W" then
        e.ex, e.ey, e.bx, e.by, e.mx, e.my = x + 1, y, x + 1, y, x + 1, y + 0.5
    else
        e.ex, e.ey, e.bx, e.by, e.mx, e.my = x, y + 1, x, y + 1, x + 0.5, y + 1
    end
    e.key = e.ex .. "," .. e.ey .. "," .. z .. "," .. kind
    return e
end
Obstacles.edge = edge

-- Côté du point (px, py) : "a" (ouest ou nord du bord) ou "b".
local function sideOf(e, px, py)
    if e.kind == "W" then return px >= e.ex and "b" or "a" end
    return py >= e.ey and "b" or "a"
end
Obstacles.sideOf = sideOf

function Obstacles.isOpen(door) return door:IsOpen() == true end

local function isThumpable(door) return instanceof(door, "IsoThumpable") end

-- Vrai si la porte est verrouillée pour un joueur sans clé (verrou, clé, cadenas, verrou de mod CustomLock).
function Obstacles.isLocked(door)
    if door:isLocked() or door:isLockedByKey() then return true end
    if isThumpable(door) then return door:isLockedByPadlock() == true end
    return door:hasModData() and door:getModData().CustomLock == true
end

-- Porte simple, ou "double" (quatre objets qui changent de case en s'ouvrant : non gérée ici) / "garage" (panneaux
-- alignés, gérés ensemble, LK04-T17 : voir panelsOf).
function Obstacles.kindOf(door)
    if IsoDoor.getDoubleDoorIndex(door) ~= -1 then return "double" end
    if IsoDoor.getGarageDoorIndex(door) ~= -1 then return "garage" end
    return "single"
end

-- Panneaux d'une porte de garage (LK04-T17), du premier au dernier ; { door } pour toute autre porte. Un joueur bascule
-- tous les panneaux d'un coup (IsoDoor.toggleGarageDoor depuis ToggleDoorActual : chaque panneau ouvert ou fermé et
-- déverrouillé, J/iso/objects/IsoDoor.java:1389-1403, 2880-2932) ; les panneaux restent sur leur case et leur bord
-- (getGarageDoorPrev / Next : case voisine le long du mur, index 1 à 3, :2770-2878).
function Obstacles.panelsOf(door)
    if Obstacles.kindOf(door) ~= "garage" then return { door } end
    local out = {}
    local p = IsoDoor.getGarageDoorFirst(door)
    while p ~= nil and #out < 8 do
        out[#out + 1] = p
        p = IsoDoor.getGarageDoorNext(p)
    end
    if #out == 0 then out[1] = door end
    return out
end

-- Vrai si un panneau de la porte est barricadé.
local function anyBarricaded(door)
    for _, p in ipairs(Obstacles.panelsOf(door)) do
        if p:isBarricaded() then return true end
    end
    return false
end

-- Identifiant stable du bâtiment de la case (BuildingDef:getIDString), ou nil.
local function buildingOf(sq)
    if sq == nil then return nil end
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()
end
Obstacles.buildingOf = buildingOf

-- ---------------------------------------------------------------- foyers

-- Relevé (au plus toutes les HOMES_MS) des bâtiments de foyer : byBuilding[idString] = gid ; list = { { gid, id, def,
-- x, y, z } }. Foyer en clairière ou hors bâtiment : ignoré. Métagrille seulement (getBuildingAt(x, y, z) indexé).
function Obstacles.refreshHomes(force)
    local H = Obstacles.homes
    local t = P.now()
    if not force and H.ms ~= nil and t - H.ms < Obstacles.HOMES_MS then return H end
    H.ms, H.byBuilding, H.list = t, {}, {}
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return H end
    local grid = getWorld():getMetaGrid()
    for _, gid in ipairs(G.list()) do
        local g = G.peek(gid)   -- LK13-T08 : lecture en place, seule (coordonnées recopiées)
        local h = g and g.home
        if h ~= nil then
            local def = grid:getBuildingAt(h.x, h.y, h.z)
            if def ~= nil then
                local id = def:getIDString()
                if H.byBuilding[id] == nil then   -- deux groupes dans un même bâtiment : le premier (Groups.list trié)
                    H.byBuilding[id] = gid
                    H.list[#H.list + 1] = { gid = gid, id = id, def = def, x = h.x, y = h.y, z = h.z }
                end
            end
        end
    end
    return H
end

-- Groupe dont le foyer est le bâtiment d'un des deux côtés de la porte, et vrai si la porte est extérieure (l'autre
-- côté hors de ce bâtiment). Rend nil hors de tout foyer.
function Obstacles.homeOf(sqA, sqB)
    local H = Obstacles.refreshHomes(false)
    local ia, ib = buildingOf(sqA), buildingOf(sqB)
    local ga = ia and H.byBuilding[ia]
    if ga ~= nil then return ga, ib ~= ia end
    local gb = ib and H.byBuilding[ib]
    if gb ~= nil then return gb, true end
    return nil
end

-- Groupe du PNJ (LivingKnox.Groups.findNpc), ou nil.
function Obstacles.groupOf(npcId)
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil end
    return (G.findNpc(npcId))
end

-- ---------------------------------------------------------------- décision et effet

-- Décision pour le PNJ npcId (corps body, ou son corps courant) devant la porte fermée door (cases sqA, sqB). Rend
-- "open", lockAfter, gid, keyId (clé de la porte) ; ou nil et la raison du refus (anglais, journal).
-- LK04-T12 : une porte verrouillée n'est ouverte que si le corps porte une clé de la porte (Obstacles.hasKey) ; elle
-- est alors reverrouillée derrière lui, comme une porte extérieure de son foyer. Sans clé, une porte non verrouillée
-- s'ouvre mais n'est jamais verrouillée ensuite.
-- LK04-T17 (essai solo du 2026-10-12, lk-73 enfermé dans son foyer : porte intérieure verrouillée, keyId -1, refusée
-- malgré la clé du bâtiment) : sans clé, une porte verrouillée s'ouvre aussi de l'intérieur, comme pour un joueur
-- (opensFromInside), depuis la case from (côté d'où le PNJ l'aborde ; nil : case courante du corps) ; elle n'est pas
-- reverrouillée ensuite sans clé, sauf porte de son foyer sans clé propre et clé du foyer portée (LK04-T19). Rend en
-- cinquième valeur vrai si la porte verrouillée est ouverte de l'intérieur sans sa clé. Porte de garage : tous ses
-- panneaux (panelsOf), sans test d'obstruction à l'ouverture (le moteur n'en fait pas : IsoDoor.java:1389-1398,
-- isGarageDoorObstructed faux pour une porte fermée, :2934-2944).
-- LK04-T20 (campagne MP du 2026-10-15, lk-7 sans groupe apparu dans le foyer de grp-5) : trapped (consigne de dernier
-- recours, e.lr) : la porte du foyer d'un autre groupe abordée depuis l'intérieur de ce foyer (inHomeOf) n'est plus
-- refusée ; elle suit alors les règles d'une porte ordinaire (verrou ouvert de l'intérieur), jamais reverrouillée.
function Obstacles.decide(npcId, door, sqA, sqB, body, from, trapped)
    if anyBarricaded(door) then return nil, "barricaded door" end
    local kind = Obstacles.kindOf(door)
    if kind == "double" then return nil, "double door not handled" end
    if kind == "single" and door:isObstructed() then return nil, "obstructed door" end
    if isThumpable(door) and door:isLockedByPadlock() then return nil, "padlocked door" end
    local home, exterior = Obstacles.homeOf(sqA, sqB)
    local mine = Obstacles.groupOf(npcId)
    local foreign = home ~= nil and home ~= mine
    local z = body
    if foreign then
        if trapped and from == nil and z == nil then z = LivingKnox.Bodies.find(npcId) end
        if trapped and from == nil and z ~= nil then from = z:getCurrentSquare() end
        if not (trapped and Obstacles.inHomeOf(from, home)) then
            return nil, "door of the home of " .. home .. " (not a member)"
        end
    end
    local locked = Obstacles.isLocked(door)
    local keyId, key = nil, false
    if locked or home ~= nil then   -- sinon la clé ne sert à rien : ni corps ni inventaire lus
        keyId = Obstacles.doorKeyId(door)
        if z == nil then z = LivingKnox.Bodies.find(npcId) end
        if z ~= nil then Obstacles.giveKey(npcId, z) end   -- clé du foyer (une fois par corps et par foyer)
        key = Obstacles.hasKey(z, keyId)
    end
    if locked and not key then
        if from == nil and z ~= nil then from = z:getCurrentSquare() end
        if not Obstacles.opensFromInside(door, from) then return nil, "locked door (no key)" end
        -- LK04-T19 (décision de l'utilisateur du 2026-10-14) : ouverte de l'intérieur sans la clé de la porte, une
        -- porte verrouillée de SON foyer (home : décision déjà refusée pour le foyer d'un autre groupe) est
        -- reverrouillée derrière lui s'il porte la clé de son foyer et que la porte n'a pas d'autre clé : keyId -1
        -- (porte intérieure du bâtiment, IsoDoor.checkKeyId, IsoDoor.java:1979-2002 ; cas de lk-73). Une porte à
        -- keyId propre différent de celui du foyer reste déverrouillée (la clé du foyer ne la ferme pas) ; une porte
        -- au keyId du foyer s'ouvre déjà avec la clé (branche key ci-dessus). keyId rendu : clé du foyer, revérifiée
        -- à la refermeture (closePass) ; inside : ouverte sans la clé de la porte (journal).
        if home ~= nil and not foreign and (keyId == nil or keyId == -1) then
            local homeKey = Obstacles.homeKeyOf(npcId)
            if homeKey ~= nil and homeKey ~= -1 and Obstacles.hasKey(z, homeKey) then
                return "open", true, home, homeKey, true
            end
        end
        return "open", false, home, keyId, true
    end
    return "open", key and (locked or (home ~= nil and not foreign and exterior)), home, keyId, false
end

-- Vrai si la case sq est dans le bâtiment du foyer du groupe gid (LK04-T20 : passage abordé depuis l'intérieur).
function Obstacles.inHomeOf(sq, gid)
    local id = buildingOf(sq)
    if id == nil or gid == nil then return false end
    return Obstacles.refreshHomes(false).byBuilding[id] == gid
end

-- Case du bord e du côté du point (px, py) : sqA (ouest ou nord) ou sqB.
local function nearSquare(e, px, py, sqA, sqB)
    if sideOf(e, px, py) == "a" then return sqA end
    return sqB
end

-- Fixe l'état de la porte : ouverte (déverrouillée) ou fermée (verrouillée si lock). Bascule seulement si l'état
-- diffère (jamais deux fois) ; recalcul des cases et envoi de l'état absolu (sync) si quelque chose a changé. Rend
-- vrai si la porte a changé. Porte de garage (LK04-T17) : chaque panneau (panelsOf), comme toggleGarageDoor ; un
-- verrou ou un déverrouillage compté une fois pour la porte.
local function setPanel(door, open, lock)
    local changed, unlocked, locked = false, false, false
    if open then
        if door:isLocked() or door:isLockedByKey() then
            door:setLockedByKey(false, false)
            door:setIsLocked(false)
            unlocked, changed = true, true
        end
        if not Obstacles.isOpen(door) then
            door:ToggleDoorSilent()
            changed = true
        end
    else
        if Obstacles.isOpen(door) then
            door:ToggleDoorSilent()
            changed = true
        end
        if lock and not (door:isLocked() or door:isLockedByKey()) and not Obstacles.isOpen(door) then
            if instanceof(door, "IsoDoor") then door:checkKeyId() end
            door:setLockedByKey(true, false)
            locked, changed = true, true
        end
    end
    return changed, unlocked, locked
end

-- Recalcul et envoi d'état après que TOUS les panneaux ont pris leur état : un SyncIsoObject de panneau de garage
-- applique son état à tous les panneaux chez le destinataire (IsoDoor.java:1487-1503, 1601-1622).
function Obstacles.setDoor(door, open, lock)
    local changed, unlocked, locked = false, false, false
    local done = {}
    for _, p in ipairs(Obstacles.panelsOf(door)) do
        local c, u, l = setPanel(p, open, lock)
        if c then done[#done + 1] = p end
        changed, unlocked, locked = changed or c, unlocked or u, locked or l
    end
    for _, p in ipairs(done) do
        local sq = p:getSquare()
        sq:RecalcAllWithNeighbours(true)
        sq:setSquareChanged()
        p:sync()
        P.count("syncs")
    end
    if unlocked then P.count("unlocked") end
    if locked then P.count("locked") end
    return changed
end

P.anyBarricaded = anyBarricaded
P.buildingOf = buildingOf
P.edge = edge
P.isThumpable = isThumpable
P.nearSquare = nearSquare
P.sideOf = sideOf
