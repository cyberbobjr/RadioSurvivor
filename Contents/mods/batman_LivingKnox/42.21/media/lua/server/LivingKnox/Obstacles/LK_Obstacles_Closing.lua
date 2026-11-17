-- Living Knox : obstacles, refermeture des portes et des fenêtres ouvertes ici (LK04-T02, LK04-T13,
-- LK04-T18).
-- LK20-T09 : sorti de LK_Obstacles.lua sans changement de comportement ; façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- refermeture

-- Vrai si un objet mobile occupe les cases de la porte ou de la fenêtre notée rec. except : le corps qui la referme
-- (LK04-T18 : arrêté sur la case d'arrivée d'une fenêtre, il n'empêche pas sa propre fermeture).
local function occupied(rec, except)
    local cell = getCell()
    for _, p in ipairs({ { rec.e.ax, rec.e.ay }, { rec.e.bx, rec.e.by } }) do
        local sq = cell:getGridSquare(p[1], p[2], rec.e.z)
        local list = sq ~= nil and sq:getMovingObjects() or nil
        for i = 0, (list ~= nil and list:size() or 0) - 1 do
            if list:get(i) ~= except then return true end
        end
    end
    -- Porte de garage (LK04-T17) : cases des deux côtés de chaque panneau, et véhicule sous un panneau (approche de
    -- isGarageDoorObstructed, privé : IsoDoor.isDoorObstructed de chaque panneau, IsoDoor.java:2288-2324).
    if rec.door ~= nil and Obstacles.kindOf(rec.door) == "garage" then
        for _, pn in ipairs(Obstacles.panelsOf(rec.door)) do
            if pn:isObstructed() then return true end
            for _, sq in ipairs({ pn:getSquare(), P.oppositeOf(pn) }) do
                if sq ~= nil and sq:getMovingObjects():size() > 0 then return true end
            end
        end
    end
    return false
end

-- Vrai si le dernier passant de la porte ou de la fenêtre notée rec (corps z) est passé de l'autre côté, n'a plus de
-- "move" en cours, ou ne l'a plus sur son trajet depuis CLOSE_AFTER_MS.
local function passedOrStale(rec, z, t)
    local passed = P.sideOf(rec.e, z:getX(), z:getY()) ~= rec.from
    local d = LivingKnox.Directives.entries[rec.id]
    local going = d ~= nil and d.op == LivingKnox.Directives.OP_MOVE and not d.done
    return passed or not going or t - rec.seenMs >= Obstacles.CLOSE_AFTER_MS
end

-- Vrai si la porte notée rec peut être refermée maintenant (voir l'en-tête).
local function closeDue(rec, t)
    local z = LivingKnox.Bodies.find(rec.id)
    if z == nil then return true end
    local away = P.dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) >= Obstacles.CLOSE_DIST
    if not away then return false end
    return passedOrStale(rec, z, t)
end

-- Portes ouvertes ici : refermées (et reverrouillées) quand c'est dû. seen : bords encore sur un trajet.
function Obstacles.closePass(seen, t)
    local drop, shut = {}, {}
    for key, rec in pairs(Obstacles.opened) do
        local door = rec.door
        if P.gone(door) then
            drop[#drop + 1] = key
        elseif not Obstacles.isOpen(door) then
            drop[#drop + 1] = key   -- refermée par quelqu'un d'autre : plus à nous
        elseif select(2, LivingKnox.Bodies.find(rec.id)) == "unknown" then
            drop[#drop + 1] = key   -- PNJ retiré du registre (lk.traversal MP du 2026-11-16) : plus à nous
        elseif not seen[key] and closeDue(rec, t) then
            if occupied(rec) then
                P.count("busy")
                if t - rec.ms >= Obstacles.GIVE_UP_MS then
                    P.count("givenUp")
                    LivingKnox.Log.warn("door %s left open: its squares stay occupied", key)
                    drop[#drop + 1] = key
                end
            else
                shut[#shut + 1] = key
            end
        end
    end
    for _, key in ipairs(shut) do   -- table modifiée hors de pairs
        local rec = Obstacles.opened[key]
        -- LK04-T12 : reverrouillée seulement si le PNJ porte toujours la clé (corps disparu : clé gardée par le PNJ).
        local lock = rec.lock
        local z = lock and LivingKnox.Bodies.find(rec.id) or nil
        if z ~= nil and not Obstacles.hasKey(z, rec.keyId) then
            lock = false
            LivingKnox.Log.info("door %s: npc %s lost its key, left unlocked", key, rec.id)
        end
        Obstacles.setDoor(rec.door, false, lock)
        P.count("closed")
        LivingKnox.Log.info("door %s closed behind npc %s%s", key, rec.id, lock and " and locked" or "")
        Obstacles.opened[key] = nil
    end
    for _, key in ipairs(drop) do Obstacles.opened[key] = nil end
end

-- Consigne "move" ouverte et non suspendue du PNJ id (moving), ou close à l'arrivée (arrived).
local function moveState(id)
    local d = LivingKnox.Directives.entries[id]
    if d == nil or d.op ~= LivingKnox.Directives.OP_MOVE then return nil end
    if not d.done then return d.suspended == nil and "moving" or nil end
    return d.s == "arrived" and "arrived" or nil
end

-- Vrai si la fenêtre notée rec peut être refermée maintenant par le corps z de son dernier passant (LK04-T18, voir
-- l'en-tête) : corps dans le monde, au niveau de la fenêtre, hors escalade, à ACT_REACH case au plus du milieu du
-- bord, et passé de l'autre côté (ou consigne changée, ou CLOSE_AFTER_MS sans passage). Jamais de loin.
local function windowCloseDue(rec, z, t)
    if z == nil or not LivingKnox.Bodies.inWorld(z) or P.climbing(z) or math.floor(z:getZ()) ~= rec.e.z then return false end
    if P.dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) > Obstacles.ACT_REACH then return false end
    return passedOrStale(rec, z, t)
end

-- Fenêtre notée rec à refermer (LK04-T13) par le corps z (windowCloseDue vrai) : geste de fermeture si la consigne
-- est un "move" en marche ou arrivé (une autre consigne, regard ou arrêt, n'est pas détournée). Rend vrai si le geste
-- est posé (fenêtre fermée plus tard par windowActPass, l'exécutant arrête le corps).
local function closeWithGesture(rec, z, t)
    if not Obstacles.WINDOW_GESTURE or moveState(rec.id) == nil then return false end
    return Obstacles.startWindowAct(rec.id, z, rec.win, rec.e, "close", t)
end

-- Geste de fermeture r (corps z) : la fenêtre ne bascule que corps arrêté (moins de STILL case depuis le passage
-- précédent), à ACT_REACH case au plus et tourné vers elle (LK04-T18). Rend ce constat et la distance du corps au
-- milieu du bord ; met à jour la position de référence.
function Obstacles.closeReady(r, z)
    local x, y = z:getX(), z:getY()
    local still = P.dist(x, y, r.lx or x, r.ly or y) < Obstacles.STILL
    r.lx, r.ly = x, y
    local d = P.dist(x, y, r.e.mx, r.e.my)
    return still and d <= Obstacles.ACT_REACH and Obstacles.facing(z, r.e), d
end

-- Fenêtre key refermée par le PNJ id, corps à d case de son milieu (gesture : avec le geste) : constat gardé pour les
-- essais en jeu (Obstacles.lastClose, lk.traversal) et garde contre une réouverture par le même PNJ (closedBy).
local function noteClosed(key, e, id, z, d, gesture, t)
    P.count("windowsClosed")
    Obstacles.closedBy[key] = { id = id, ms = t }
    Obstacles.lastClose = { key = key, id = id, d = d, gesture = gesture, ms = t,
        facing = z ~= nil and Obstacles.facing(z, e) or false }
    LivingKnox.Log.info("window %s closed behind npc %s (body %.2f square(s) away%s)", key, id, d,
        gesture and ", gesture" or "")
end

-- Gestes en cours devant une fenêtre (LK04-T13), à chaque passage : bascule à l'instant du clip (toggleMs), geste
-- oublié à sa fin (endMs). Ouverture : fenêtre ouverte avec le corps (openWindow) puis notée pour être refermée, comme
-- sans geste ; fermeture : fenêtre fermée si ses deux cases sont libres, sinon nouvel essai à chaque passage jusqu'à la
-- fin du geste, puis closeWindowsPass reprend (nouveau geste, abandon après GIVE_UP_MS). Geste interrompu (fin
-- anticipée de l'animation) si la fenêtre a disparu, est brisée, barricadée ou déjà dans l'état voulu (quelqu'un
-- d'autre), si le corps n'est plus dans le monde ou, pour une ouverture, si la consigne "move" n'est plus en cours.
function Obstacles.windowActPass(t)
    local keys = {}
    for key in pairs(Obstacles.winActs) do keys[#keys + 1] = key end
    table.sort(keys)   -- ordre déterministe ; table modifiée hors de pairs
    for _, key in ipairs(keys) do
        local r = Obstacles.winActs[key]
        local w = r.win
        local open = r.kind == "open"
        local z = LivingKnox.Bodies.find(r.id)
        local why = nil
        if r.done then
            if t >= r.endMs then Obstacles.winActs[key] = nil end
        else
            local ready, d = false, nil
            if not open and z ~= nil then ready, d = Obstacles.closeReady(r, z) end   -- LK04-T18
            if P.gone(w) then
                why = "window removed"
            elseif w:isDestroyed() or w:isBarricaded() then
                why = "window broken or barricaded"
            elseif (w:IsOpen() == true) == open then
                why = open and "window already open" or "window already closed"
            elseif z == nil or not LivingKnox.Bodies.inWorld(z) then
                why = "body gone"
            elseif open and moveState(r.id) ~= "moving" then
                why = "move no longer running"
            elseif t >= r.toggleMs then
                if open then
                    if Obstacles.openWindow(w, z) then
                        r.done = true
                        P.count("windowsOpened")
                        Obstacles.openWins[key] = { win = w, e = r.e, id = r.id, ms = t, seenMs = t, from = r.from }
                        LivingKnox.Log.info("npc %s: window %s opened (group %s)", r.id, key, tostring(Obstacles.groupOf(r.id)))
                    else
                        why = "window did not open"
                    end
                else
                    local rec = Obstacles.openWins[key]
                    if rec == nil then
                        why = "window no longer followed"
                    elseif not ready then
                        -- LK04-T18 : corps pas encore arrêté devant elle (relais, exécutant) : attente jusqu'à la fin
                        -- du geste, puis nouvel essai par closeWindowsPass s'il est toujours à ACT_REACH.
                        P.count("windowCloseWaits")
                        if t >= r.endMs then Obstacles.winActs[key] = nil end
                    elseif occupied(rec, z) then
                        P.count("windowsBusy")
                        if t >= r.endMs then Obstacles.winActs[key] = nil end   -- nouvel essai par closeWindowsPass
                    elseif Obstacles.setWindow(w, false, z) then
                        r.done = true
                        noteClosed(key, r.e, r.id, z, d, true, t)
                        Obstacles.openWins[key] = nil
                    else
                        LivingKnox.Log.warn("window %s could not be closed behind npc %s", key, r.id)
                        Obstacles.openWins[key] = nil
                        why = "window did not close"
                    end
                end
            end
            if why ~= nil then
                Obstacles.winActs[key] = nil
                P.count("windowGesturesStopped")
                local A = LivingKnox.Anim
                if A ~= nil and A.endAct ~= nil then A.endAct(r.id, r.g) end
                LivingKnox.Log.info("npc %s: %s gesture at the window %s stopped: %s", r.id, r.g, key, why)
            end
        end
    end
end

-- Fenêtres ouvertes ici : refermées quand c'est dû (voir l'en-tête). seen : bords encore sur un trajet.
function Obstacles.closeWindowsPass(seen, t)
    local drop, shut = {}, {}
    for key, rec in pairs(Obstacles.openWins) do
        local w = rec.win
        if P.gone(w) then
            drop[#drop + 1] = key
        elseif not w:IsOpen() or w:isDestroyed() or w:isBarricaded() then
            drop[#drop + 1] = key   -- fermée, brisée ou barricadée par quelqu'un d'autre : plus à nous
        elseif Obstacles.winActs[key] == nil then   -- geste en cours devant elle : windowActPass (LK04-T13)
            local z = LivingKnox.Bodies.find(rec.id)
            -- LK04-T18 : escalade de cette fenêtre en cours, fin guettée à chaque image (Obstacles.landed).
            rec.climbing = (z ~= nil and P.climbing(z) and math.floor(z:getZ()) == rec.e.z
                and P.dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) <= Obstacles.DETECT) or nil
            local due = not seen[key] and windowCloseDue(rec, z, t)
            local busy = due and occupied(rec, z)
            if due and not busy then
                if not closeWithGesture(rec, z, t) then shut[#shut + 1] = key end
            else
                if busy then P.count("windowsBusy") end
                if t - rec.ms >= Obstacles.GIVE_UP_MS then
                    P.count("windowsGivenUp")
                    LivingKnox.Log.warn("window %s left open: npc %s not next to it in time or its squares stay occupied",
                        key, rec.id)
                    drop[#drop + 1] = key
                end
            end
        end
    end
    for _, key in ipairs(shut) do   -- table modifiée hors de pairs (corps à ACT_REACH au plus : windowCloseDue)
        local rec = Obstacles.openWins[key]
        local z = LivingKnox.Bodies.find(rec.id)
        if Obstacles.setWindow(rec.win, false, z) then
            noteClosed(key, rec.e, rec.id, z, z ~= nil and P.dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) or -1, false, t)
        else
            LivingKnox.Log.warn("window %s could not be closed behind npc %s", key, rec.id)
        end
        Obstacles.openWins[key] = nil
    end
    for _, key in ipairs(drop) do Obstacles.openWins[key] = nil end
    local old = {}
    for key, cb in pairs(Obstacles.closedBy) do
        if t - cb.ms >= Obstacles.CLOSE_GUARD_MS then old[#old + 1] = key end
    end
    for _, key in ipairs(old) do Obstacles.closedBy[key] = nil end
end

-- Vrai si le dernier passant d'une fenêtre à refermer vient de finir son escalade (LK04-T18) : passage avancé à
-- l'image suivante, pour arrêter le corps sur la case d'arrivée avant qu'il ne s'éloigne.
function Obstacles.landed()
    for _, rec in pairs(Obstacles.openWins) do
        if rec.climbing then
            local z = LivingKnox.Bodies.find(rec.id)
            if z == nil or not P.climbing(z) then return true end
        end
    end
    return false
end

P.occupied = occupied
P.moveState = moveState   -- LK21-T12 : retrait du verre (LK_Obstacles_Glass)
