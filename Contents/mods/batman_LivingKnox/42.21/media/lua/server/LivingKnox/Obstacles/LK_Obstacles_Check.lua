-- Living Knox : obstacles, détection des portes sur le trajet, immobilité, refus d'une consigne et contrôle
-- d'un PNJ à chaque passage (LK04-T02, LK04-T09, LK17-T01).
-- LK20-T09 : sorti de LK_Obstacles.lua sans changement de comportement ; façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- détection

-- Portes des bords à DETECT cases au plus du point (px, py) au niveau z, triées par distance. Chaque élément :
-- { door, e (bord), d (distance au milieu du bord), sqA, sqB }.
function Obstacles.doorsNear(px, py, z)
    local cell = getCell()
    local out = {}
    local r = math.ceil(Obstacles.DETECT)
    local fx, fy = math.floor(px), math.floor(py)
    for x = fx - r, fx + r do
        for y = fy - r, fy + r do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                for _, kind in ipairs({ "W", "N" }) do
                    local e = P.edge(x, y, z, kind)
                    local nb = cell:getGridSquare(e.bx, e.by, z)
                    local door = nb and sq:getDoorTo(nb)
                    if door ~= nil then
                        local d = P.dist(px, py, e.mx, e.my)
                        if d <= Obstacles.DETECT then
                            out[#out + 1] = { door = door, e = e, d = d, sqA = sq, sqB = nb }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.e.key < b.e.key
    end)
    return out
end

-- Vrai si franchir le bord e rapproche le point (px, py) de la case visée (tx, ty) (centres des cases).
function Obstacles.onRoute(e, px, py, tx, ty)
    local nx, ny, fx, fy
    if P.sideOf(e, px, py) == "a" then
        nx, ny, fx, fy = e.ax, e.ay, e.bx, e.by
    else
        nx, ny, fx, fy = e.bx, e.by, e.ax, e.ay
    end
    return P.dist(fx + 0.5, fy + 0.5, tx + 0.5, ty + 0.5) < P.dist(nx + 0.5, ny + 0.5, tx + 0.5, ty + 0.5) - 0.01
end

-- Temps (ms) depuis lequel le corps du PNJ id est immobile (STILL case).
-- E18-T35 : un corps simulé par un client n'est vu du serveur qu'aux rapports de l'exécutant (copie recalée par
-- Directives.syncServerCopy, au moins tous les REPORT_MS) ou aux paquets du moteur (200 ms à 4 s) : entre deux, sa copie
-- paraît immobile alors qu'il marche. Cette attente est retranchée (campagne MP à un client du 2026-11-12 : porte
-- refusée longée, prise « au contact » après 800 ms et ouverte de l'intérieur).
local function stillFor(id, z, t)
    local tr = Obstacles.track[id]
    if tr == nil or P.dist(tr.x, tr.y, z:getX(), z:getY()) >= Obstacles.STILL then
        Obstacles.track[id] = { x = z:getX(), y = z:getY(), ms = t }
        return 0
    end
    local blind = (isServer() and z:getOwner() ~= nil) and LivingKnox.Directives.REPORT_MS or 0
    return math.max(0, t - tr.ms - blind)
end

-- Vrai si le corps z est en train d'escalader (fenêtre ou clôture : nom de l'état d'action, en minuscules).
local function climbing(z)
    local st = z ~= nil and z:getActionStateName() or nil
    return st == "climbwindow" or st == "climbfence"
end

-- Refus d'une consigne bloquée par une porte (what = "door") ou une fenêtre ("window"). LK17-T01 : le gestionnaire
-- Obstacles.onRefusal (LK_Detour.lua : function(id, e, c, why, what), vrai si la consigne a reçu un détour) est
-- consulté d'abord ; détour donné : consigne gardée, immobilité du corps remise à zéro (aucun second refus avant
-- REFUSE_MS). Sinon close en échec par l'autorité.
local function refuse(id, e, c, why, what)
    what = what or "door"
    P.count("refused")
    Obstacles.lastRefused = { id = id, what = what, key = c.e.key, why = why, ms = P.now() }
    if Obstacles.onRefusal ~= nil and Obstacles.onRefusal(id, e, c, why, what) then
        P.count("detoured")
        Obstacles.track[id] = nil
        LivingKnox.Log.info("npc %s: move #%d refused at the %s %s: %s; detour given", id, e.v, what, c.e.key, why)
        return
    end
    LivingKnox.Log.warn("npc %s: move #%d refused at the %s %s: %s", id, e.v, what, c.e.key, why)
    -- E18-T38 : sans détour, case visée derrière une fenêtre refusée écartée comme après un échec "stuck"
    -- (Movement.AVOID_MS) : le même trajet revenait sur la même fenêtre verrouillée à chaque consigne (campagne solo du
    -- 2026-11-13 : 37 refus de suite).
    local Mv = LivingKnox.Movement
    if what == "window" and Mv ~= nil and Mv.noteStuck ~= nil then Mv.noteStuck(id, e) end
    LivingKnox.Directives.abort(id, what .. " " .. c.e.key .. ": " .. why)
end

-- Vrai si la porte fermée door est basse (portail de clôture) : le corps l'enjambe, verrouillée ou non, et ne s'y
-- arrête jamais (IsoZombie.java:3051-3058 tryThump, 1075 collideWith exclut IsoDoor enjambable ; IsoThumpable :
-- 3065-3071 ; IsoDoor.java:1244-1253). LK04-T08.
function Obstacles.isLowGate(door)
    return LivingKnox.Edges.isLowGate(door)
end

-- Portes du PNJ id (consigne e, corps z) : ouverture ou refus. seen : clés des bords sur un trajet à ce passage.
-- Jamais de refus pendant une escalade, ni devant une porte basse (enjambée par le moteur).
-- Une porte qui rapproche de l'étape SUIVANTE compte aussi (LK04-T09, détour LK17-T01) : le point de passage « case
-- avant la porte » est atteint à ARRIVE case près, souvent à moins d'une case de la porte ; elle est ainsi ouverte
-- avant (en course, moins d'une demi-seconde sépare l'arrivée sur ce point du contact).
function Obstacles.check(id, e, z, seen, t)
    local px, py, pz = z:getX(), z:getY(), math.floor(z:getZ())
    local tx, ty = LivingKnox.Directives.stepTarget(e, e.k)
    local k = (type(e.k) == "number" and e.k >= 1) and e.k or 1
    local nx, ny
    if type(e.w) == "table" and k <= #e.w then nx, ny = LivingKnox.Directives.stepTarget(e, k + 1) end
    -- LK04-T17 (lk.traversal du 2026-10-12, « refused door next to a low fence ») : l'immobilité ne court pas pendant
    -- une escalade (corps figé par l'animation) ; sinon, à la fin de l'escalade, une porte refusée LONGEANT le trajet
    -- était « au contact » depuis plus de REFUSE_MS et la consigne échouait.
    if climbing(z) then Obstacles.track[id] = { x = px, y = py, ms = t } end
    local still = stillFor(id, z, t)
    local near = Obstacles.doorsNear(px, py, pz)
    local function onWay(c)
        return Obstacles.onRoute(c.e, px, py, tx, ty) or (nx ~= nil and Obstacles.onRoute(c.e, px, py, nx, ny))
    end
    -- E18-T31 (campagne MP du 2026-11-08, runs/20261108-101002-mp-0569ec9c26f8, lk.traversal) : une porte du même mur
    -- une case à côté rapproche aussi de l'étape ; tant que la porte ouverte par ce PNJ n'est pas franchie, une autre
    -- porte fermée n'est ouverte qu'au contact.
    local pending = false
    for _, c in ipairs(near) do
        local rec = Obstacles.opened[c.e.key]
        if rec ~= nil and rec.door == c.door and rec.id == id and Obstacles.isOpen(c.door) and onWay(c) then
            pending = true
        end
    end
    for _, c in ipairs(near) do
        local contact = still >= Obstacles.STUCK_MS and c.d <= Obstacles.REACH
        local route = onWay(c)
        if pending and route and not contact and not Obstacles.isOpen(c.door) then route = false end
        if contact or route then
            seen[c.e.key] = true
            local rec = Obstacles.opened[c.e.key]
            if rec ~= nil and rec.door == c.door then   -- dernier PNJ qui l'a sur son trajet, et son côté
                rec.id, rec.seenMs, rec.from = id, t, P.sideOf(c.e, px, py)
            end
            if not Obstacles.isOpen(c.door) or c.door:isBarricaded() then
                local act, lockAfter, home, keyId, inside = Obstacles.decide(id, c.door, c.sqA, c.sqB, z,
                    P.nearSquare(c.e, px, py, c.sqA, c.sqB), e.lr == true)   -- refus : lockAfter = raison
                if act == "open" then
                    local wasLocked = Obstacles.isLocked(c.door)
                    Obstacles.setDoor(c.door, true)
                    P.count("opened")
                    Obstacles.opened[c.e.key] = { door = c.door, e = c.e, id = id, ms = t, seenMs = t,
                        from = P.sideOf(c.e, px, py), lock = lockAfter == true, home = home, keyId = keyId }
                    -- LK04-T17 : sans clé portée, ouverte de l'intérieur (opensFromInside) ; LK04-T19 : reverrouillée
                    -- derrière lui avec la clé de son foyer.
                    local how = inside and " from inside" or (" with its key " .. tostring(keyId))
                    if inside and lockAfter then how = how .. " (to be relocked with its home key " .. tostring(keyId)
                        .. ")" end
                    LivingKnox.Log.info("npc %s: door %s opened%s", id, c.e.key, wasLocked and (" and unlocked"
                        .. (home and (" (member of " .. tostring(home) .. ")") or "") .. how) or "")
                elseif contact and still >= Obstacles.REFUSE_MS and not climbing(z)
                    and not Obstacles.isLowGate(c.door) and (route or Obstacles.facing(z, c.e)) then
                    -- LK04-T17 : porte au contact refusée seulement sur le trajet ou en face du corps (pas celle qu'il
                    -- longe), comme une fenêtre (checkWindows).
                    -- LK04-T04 : attendre ou forcer selon le type de groupe, sinon refus (voir « passage bloqué »).
                    if not Obstacles.onBlocked(id, e, z, c, lockAfter, "door", t) then refuse(id, e, c, lockAfter) end
                    return
                end
            end
        end
    end
    Obstacles.climbedWindows(id, z, t)
    Obstacles.climbedGlass(id, z)   -- LK21-T12 : risque du verre brisé à l'enjambée
    Obstacles.noteWindows(z, tx, ty, seen)
    if Obstacles.checkGlass(id, z, onWay, t) then return end   -- LK21-T12 : verre retiré avant l'enjambée
    Obstacles.checkWindows(id, e, z, still, t)
end

P.climbing = climbing
P.refuse = refuse
