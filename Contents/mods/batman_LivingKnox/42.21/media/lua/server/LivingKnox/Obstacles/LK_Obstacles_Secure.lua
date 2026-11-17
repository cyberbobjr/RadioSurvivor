-- Living Knox : obstacles, foyers verrouillés, fermeture à l'arrivée et portes refermées à l'alerte
-- (LK04-T10, LK05-T08).
-- LK20-T09 : sorti de LK_Obstacles.lua sans changement de comportement ; façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- foyers verrouillés

-- Portes extérieures du foyer h ({ gid, def, z }) au niveau du foyer, dans la zone chargée (bords du rectangle du
-- bâtiment compris) : fn(door, e) pour chacune.
local function eachExteriorDoor(h, fn)
    local cell = getCell()
    local def, z = h.def, h.z
    for x = def:getX() - 1, def:getX2() - 1 do
        for y = def:getY() - 1, def:getY2() - 1 do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                for _, kind in ipairs({ "W", "N" }) do
                    local e = P.edge(x, y, z, kind)
                    local nb = cell:getGridSquare(e.bx, e.by, z)
                    local door = nb and sq:getDoorTo(nb)
                    if door ~= nil then
                        local gid, exterior = Obstacles.homeOf(sq, nb)
                        if gid == h.gid and exterior then fn(door, e) end
                    end
                end
            end
        end
    end
end

-- Verrouille les portes extérieures fermées et non verrouillées du foyer h dans la zone chargée, sauf celles ouvertes
-- ici, chacune seulement si un membre porteur de sa clé est au foyer (LK04-T12, keyHolderAt). Rend le nombre de
-- portes verrouillées.
function Obstacles.secureHome(h)
    local n = 0
    local holders = {}   -- keyId -> membre porteur (false : aucun), relevé une fois par appel
    eachExteriorDoor(h, function(door, e)
        if Obstacles.opened[e.key] == nil and not Obstacles.isOpen(door)
            and Obstacles.kindOf(door) ~= "double" and not Obstacles.isLocked(door) then
            local keyId = Obstacles.doorKeyId(door)
            if holders[keyId] == nil then holders[keyId] = Obstacles.keyHolderAt(h, keyId) or false end
            if holders[keyId] == false then
                P.count("secureKeyless")
            elseif Obstacles.setDoor(door, false, true) then
                n = n + 1
            end
        end
    end)
    if n > 0 then
        P.count("secured")
        -- E18-T31 : portes verrouillees par le foyer, comptees aussi dans stats.locked (setDoor).
        Obstacles.stats.securedDoors = (Obstacles.stats.securedDoors or 0) + n
        LivingKnox.Log.info("group %s: %d exterior door(s) of its home locked", h.gid, n)
    end
    return n
end

-- Raison (anglais, journal) pour laquelle une porte extérieure ouverte du foyer n'est jamais fermée par shutHome, ou
-- nil : barricadée (ToggleDoorSilent la refuse), détruite, double (objets qui changent de case), cadenassée. Porte de
-- garage : tous ses panneaux (LK04-T17).
function Obstacles.shutRefusal(door)
    if P.anyBarricaded(door) then return "barricaded door" end
    if door:isDestroyed() then return "destroyed door" end
    local kind = Obstacles.kindOf(door)
    if kind == "double" then return "double door not handled" end
    if P.isThumpable(door) and door:isLockedByPadlock() then return "padlocked door" end
    return nil
end

-- Arrivée a ({ ms, due, doors, done }) près du foyer h : ferme et verrouille ses portes extérieures ouvertes (liste
-- figée au premier essai), sauf celles occupées, sur un trajet (seen) ou obstruées, réessayées plus tard (voir
-- l'en-tête). Rend le nombre de portes fermées.
function Obstacles.shutHome(h, a, seen, t)
    seen = seen or {}
    t = t or P.now()
    if a.doors == nil then
        a.doors = {}
        eachExteriorDoor(h, function(door, e)
            if Obstacles.isOpen(door) and Obstacles.opened[e.key] == nil then
                local why = Obstacles.shutRefusal(door)
                if why == nil then
                    a.doors[e.key] = { door = door, e = e }
                else
                    P.count("shutRefused")
                    LivingKnox.Log.info("group %s: exterior door %s of its home left open: %s", h.gid, e.key, why)
                end
            end
        end)
    end
    local keys = {}
    for key in pairs(a.doors) do keys[#keys + 1] = key end
    table.sort(keys)   -- ordre déterministe ; table modifiée hors de pairs
    local shut, busy, unlocked = 0, 0, 0
    for _, key in ipairs(keys) do
        local c = a.doors[key]
        local door = c.door
        if P.gone(door) or not Obstacles.isOpen(door)
            or Obstacles.opened[key] ~= nil or Obstacles.shutRefusal(door) ~= nil then
            a.doors[key] = nil   -- retirée, fermée ou barricadée par quelqu'un, ou suivie par la refermeture
        elseif seen[key] or P.occupied(c) or door:isObstructed() then
            busy = busy + 1
        else
            -- LK04-T12 : fermer ne demande aucune clé ; verrouiller, un membre porteur de la clé au foyer (sinon
            -- securePass la verrouille plus tard, quand un porteur est là).
            local lock = Obstacles.keyHolderAt(h, Obstacles.doorKeyId(door)) ~= nil
            Obstacles.setDoor(door, false, lock)
            a.doors[key] = nil
            shut = shut + 1
            if not lock then unlocked = unlocked + 1 end
        end
    end
    local st = Obstacles.stats
    local cause = a.why and (" (" .. a.why .. ")") or ""   -- alerte (LK05-T08), sinon arrivée
    if shut > 0 then
        st.shut = (st.shut or 0) + shut
        st.shutUnlocked = (st.shutUnlocked or 0) + unlocked
        if unlocked == 0 then
            LivingKnox.Log.info("group %s: %d open exterior door(s) of its home closed and locked%s", h.gid, shut, cause)
        else
            LivingKnox.Log.info("group %s: %d open exterior door(s) of its home closed, %d left unlocked: no member with "
                .. "the key at home%s", h.gid, shut, unlocked, cause)
        end
    end
    if busy == 0 then
        a.done = true
    elseif t - a.ms >= Obstacles.SHUT_GIVE_UP_MS then
        a.done = true
        P.count("shutGivenUp")
        LivingKnox.Log.warn("group %s: %d exterior door(s) of its home left open: squares occupied or on a path%s", h.gid, busy,
            cause)
    else
        P.count("shutBusy")
        a.due = t + Obstacles.SHUT_RETRY_MS
    end
    return shut
end

-- À chaque passage : arrivées près des foyers (case du foyer chargée après ne pas l'avoir été) et fermeture de leurs
-- portes extérieures ouvertes quand elle est due. Foyer déchargé, supprimé ou déplacé : arrivée oubliée.
function Obstacles.shutPass(seen, t)
    local A = Obstacles.arrivals
    local live = {}
    local cell = getCell()
    for _, h in ipairs(Obstacles.refreshHomes(false).list) do
        local key = h.gid .. "|" .. h.id
        if cell:getGridSquare(h.x, h.y, h.z) ~= nil then
            live[key] = true
            local a = A[key]
            if a == nil then
                a = { ms = t, due = t + Obstacles.SHUT_DELAY_MS }
                A[key] = a
            end
            if not a.done and t >= a.due then Obstacles.shutHome(h, a, seen, t) end
        end
    end
    local stale = {}
    for key in pairs(A) do
        if not live[key] then stale[#stale + 1] = key end
    end
    for _, key in ipairs(stale) do A[key] = nil end   -- table modifiée hors de pairs
    Obstacles.alertShutPass(seen, t)
end

-- ---------------------------------------------------------------- alerte (complément de LK05-T08)
-- Fiche : deplacement.md, section « Portes refermées à l'alerte » ; alerte.md, « Portes refermées ». Écouteur "doors"
-- de LivingKnox.Alert (Alert.subscribe) : à une alerte déclenchée ou aggravée (raised, escalated) du groupe gid, les
-- portes extérieures OUVERTES de son foyer (bâtiment, niveau du foyer, zone chargée) sont fermées, et verrouillées si
-- un membre porteur de la clé est au foyer (LK04-T10, LK04-T12) : même code que la fermeture à l'arrivée (shutHome :
-- liste figée au premier essai, hors portes ouvertes ici pour un PNJ en route, refermées derrière lui ; cases libres,
-- pas sur le trajet d'un PNJ à ce passage, porte non obstruée ; nouvel essai toutes les SHUT_RETRY_MS, abandon (WARN)
-- après SHUT_GIVE_UP_MS ; jamais barricadée, détruite, double ni cadenassée). L'écouteur ne touche aucune
-- porte : il note la demande, traitée au passage suivant (où les trajets des PNJ sont connus). Une demande par foyer
-- en cours au plus ; une porte rouverte ensuite reste ouverte jusqu'à l'alerte suivante (pas de bataille avec un
-- joueur). Foyer hors bâtiment, déchargé ou changé : rien.

-- Écouteur "raised" : note la fermeture des portes du foyer du groupe gid. Rend le nombre de foyers notés.
function Obstacles.onAlert(gid, info, event)
    if not LivingKnox.isAuthority() then return 0 end
    local t = P.now()
    local n = 0
    local label = "alert " .. tostring(type(info) == "table" and info.id or "?") .. " " .. tostring(event or "raised")
    for _, h in ipairs(Obstacles.refreshHomes(true).list) do
        if h.gid == gid then
            local key = h.gid .. "|" .. h.id
            local a = Obstacles.alertShuts[key]
            if a == nil or a.done then
                Obstacles.alertShuts[key] = { ms = t, due = t, why = label }
                n = n + 1
            end
        end
    end
    if n > 0 then
        P.count("alertShuts")
        LivingKnox.Log.info("group %s: %s: open exterior doors of its home to be closed", tostring(gid), label)
    end
    return n
end

-- À chaque passage (depuis shutPass) : demandes de l'alerte traitées par shutHome. seen : bords sur un trajet.
function Obstacles.alertShutPass(seen, t)
    local AS = Obstacles.alertShuts
    local homes = {}
    for _, h in ipairs(Obstacles.refreshHomes(false).list) do homes[h.gid .. "|" .. h.id] = h end
    local keys = {}
    for key in pairs(AS) do keys[#keys + 1] = key end
    table.sort(keys)   -- ordre déterministe ; table modifiée hors de pairs
    local cell = getCell()
    for _, key in ipairs(keys) do
        local a, h = AS[key], homes[key]
        if h == nil or cell:getGridSquare(h.x, h.y, h.z) == nil then
            AS[key] = nil   -- foyer changé, supprimé ou déchargé
        elseif not a.done and t >= a.due then
            Obstacles.shutHome(h, a, seen, t)
        end
        if AS[key] ~= nil and AS[key].done then AS[key] = nil end
    end
end

-- Abonnement de l'écouteur "doors" à LivingKnox.Alert (chargé avant ou après ce fichier : appelé au chargement et à
-- chaque passage ; un même nom remplace l'écouteur). Rend vrai si l'alerte est branchée.
function Obstacles.hookAlert()
    local A = LivingKnox.Alert
    if A == nil or A.subscribe == nil then return false end
    if Obstacles.state.alertHook == A then return true end
    local function raised(gid, info, event) return LivingKnox.Obstacles.onAlert(gid, info, event) end
    A.subscribe("doors", { raised = raised })
    Obstacles.state.alertHook = A
    return true
end

-- Toutes les SECURE_EVERY_MS : foyers dont la case est chargée. La fermeture à l'arrivée (shutPass) a lieu à chaque
-- passage.
function Obstacles.securePass(t, seen)
    Obstacles.shutPass(seen or {}, t)
    local st = Obstacles.state
    if st.secured ~= nil and t - st.secured < Obstacles.SECURE_EVERY_MS then return 0 end
    st.secured = t
    local n = 0
    for _, h in ipairs(Obstacles.refreshHomes(false).list) do
        if getCell():getGridSquare(h.x, h.y, h.z) ~= nil then n = n + Obstacles.secureHome(h) end
    end
    return n
end
