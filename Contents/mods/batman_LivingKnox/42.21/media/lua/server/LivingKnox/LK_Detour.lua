-- Living Knox : détour après un refus au contact (LK17-T01). ADR : docs/architecture/decisions/adr-chemin-vanilla.md ;
-- fiche : docs/annexes/conception/deplacement.md, section « Détour après un refus ». Autorité seulement, comme
-- LK_Obstacles.lua (un client MP charge aussi media/lua/server : il s'arrête ici).
--
-- Le jeu calcule le chemin de chaque "move" (D01 : aucun point de passage posé d'avance pour une porte ou une
-- fenêtre). Quand les règles de contact de LK_Obstacles (decide, decideWindow) refusent au PNJ la porte ou la fenêtre
-- où son chemin l'a mené (refus de LK_Obstacles, gestionnaire Obstacles.onRefusal posé ici), ce module cherche la
-- porte, le portail ou la clôture basse utilisable la plus proche du corps (bords à RADIUS cases au plus, même niveau,
-- cases chargées) qui mène du côté du corps vers le côté visé :
--   - lieu d'une case : son bâtiment (Obstacles.buildingOf) ou dehors (OUTSIDE) ;
--   - case avant l'ouverture dans le lieu du corps ; case après de préférence dans le lieu de l'autre côté de
--     l'ouverture refusée (rang 1), sinon dans celui de la destination (rang 2), sinon, corps dans un bâtiment, hors de
--     ce bâtiment (rang 3 : sortie quelconque) ; ouverture entre deux cases du même lieu (portail entre deux cours,
--     porte intérieure) : case avant la plus proche du corps ;
--   - utilisable, règles de contact réutilisées : porte ouverte et non barricadée, portail bas (enjambé par le moteur,
--     LK04-T08), décision "open" de Obstacles.decide abordée depuis la case avant (doorRefusal) ; clôture basse
--     (Edges.fenceTo : enjambée par le moteur, jamais refusée) ; cases avant et après praticables ;
--   - jamais une ouverture déjà refusée pendant ce "move" (memory : par PNJ et numéro de consigne) ;
--   - couloirs (LK_DetourCorridor, correctifs du 2026-11-15, campagnes 20261115-193703 et 20261115-202338) : case
--     avant accessible depuis le corps (cases du lieu du corps) ET destination accessible depuis la case après (cases
--     des lieux de la case après et de la destination ; destination à plus de RADIUS cases de la case après ou sur un
--     autre niveau : voir Limites), sans franchir mur, fenêtre ni clôture basse ; une porte n'est franchie que si les
--     règles de contact la laissent passer (doorRefusal, hors des clés déjà refusées) ; cases praticables (la
--     destination exceptée) ; boîtes bornées à RADIUS cases ; sinon l'ouverture est écartée et la suivante essayée.
-- La consigne garde son numéro (les modules qui l'ont émise la suivent toujours) et reçoit (Directives.reroute) les
-- coins du premier couloir (chaque segment droit entre deux points libre de fenêtre, mur et clôture : pour un corps de
-- zombie une fenêtre ne coûte rien au chemin natif, base pz-knowledge pathfinding-and-obstacles.md, le plus court
-- chemin entre deux points n'a ainsi aucune raison de repasser par la fenêtre refusée), les points { case avant, case
-- après }, les coins du second couloir, tous serrés (t : Directives.STEP_TIGHT, le corps passe vraiment l'ouverture
-- et ne coupe pas un coin), puis le contournement des plantes et feux de camp (Directives.planDetour, LK04-T06) depuis
-- le dernier de ces points jusqu'à la destination ; nouveau bail :
-- l'exécutant repart aussitôt de la position du corps. Aucune case n'est écartée (pas de Movement.AVOID_MS).
-- Dernier recours (D03, LK04-T20) : aucune ouverture utilisable et corps dans un bâtiment : l'ouverture la plus
-- proche permise par les règles de dernier recours (porte ou fenêtre abordée de l'intérieur : decide et decideWindow
-- avec trapped), l'ouverture refusée comprise (alors sans point de passage) ; consigne marquée lr (décisions au
-- contact de dernier recours, LK_Obstacles). Rien de tout cela, la même ouverture refusée une seconde fois, ou plus de
-- MAX_PER_MOVE détours : refus inchangé (consigne close en échec par LK_Obstacles).
-- Limites : le lieu ignore les pièces (deux pièces d'un même bâtiment sont un seul lieu) ; entre deux points du
-- couloir, le chemin reste celui du jeu (supposé proche de la ligne droite libre) ; destination à plus de RADIUS cases
-- de la case après : le second couloir s'arrête à la case accessible de sa boîte la plus proche de la destination
-- (DetourCorridor.toward), le chemin du jeu reprend de là ; destination sur un autre niveau : aucun second couloir.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Directives"
require "LivingKnox/LK_Obstacles"
require "LivingKnox/Detour/LK_DetourCorridor"
require "LivingKnox/Edges/LK_Edges"

local Detour = LivingKnox.Detour or {}
LivingKnox.Detour = Detour

Detour.RADIUS = 15          -- cases : ouvertures cherchées autour du corps (boîte carrée)
Detour.MAX_PER_MOVE = 3     -- détours au plus pour un même "move"
Detour.OUTSIDE = "outside"  -- lieu d'une case hors de tout bâtiment

Detour.memory = Detour.memory or {}   -- npcId -> { v, keys = { [clé de bord] = vrai }, n } du "move" courant
Detour.stats = Detour.stats or { detours = 0, lastResorts = 0, none = 0 }

local function count(name)
    local st = Detour.stats
    st[name] = (st[name] or 0) + 1
end

-- Lieu de la case sq : identifiant de son bâtiment, ou OUTSIDE.
function Detour.placeOf(sq)
    return LivingKnox.Obstacles.buildingOf(sq) or Detour.OUTSIDE
end

-- Raison (anglais) pour laquelle le PNJ npcId ne passera pas la porte d (cases sqA, sqB) abordée depuis la case from,
-- ou nil s'il la passe : ouverte et non barricadée, portail bas fermé (enjambé), ou décision "open" de
-- Obstacles.decide (trapped : règles de dernier recours, LK04-T20).
function Detour.doorRefusal(npcId, d, sqA, sqB, from, trapped)
    local Ob = LivingKnox.Obstacles
    if d:isBarricaded() then return "barricaded door" end
    if Ob.isOpen(d) or Ob.isLowGate(d) then return nil end
    local act, why = Ob.decide(npcId, d, sqA, sqB, nil, from, trapped)
    if act == "open" then return nil end
    return why or "door refused"
end

-- Raison pour laquelle le PNJ npcId ne passera pas la fenêtre w (sorte wk) de la case from vers la case far en dernier
-- recours, ou nil : fenêtre qui n'arrête pas le corps (ouverte, cassée, cadre ; franchie par le moteur), ou décision
-- "open" de Obstacles.decideWindow avec trapped.
function Detour.windowRefusal(npcId, w, wk, sqA, sqB, from, far)
    local Ob = LivingKnox.Obstacles
    if w:isBarricaded() then return "barricaded window" end
    if not Ob.windowBlocks(w, wk) then return nil end
    local act, why = Ob.decideWindow(npcId, w, wk, sqA, sqB, far, true, from)
    if act == "open" then return nil end
    return why or "window refused"
end

-- Mémoire du "move" courant e du PNJ id (oubliée quand le numéro de consigne change).
local function memoryOf(id, e)
    local m = Detour.memory[id]
    if m == nil or m.v ~= e.v then
        m = { v = e.v, keys = {}, n = 0 }
        Detour.memory[id] = m
    end
    return m
end

-- Ouvertures des bords à RADIUS cases au plus de la case (fx, fy) au niveau z, cases chargées : portes et clôtures
-- basses ; avec windows (dernier recours), fenêtres aussi. Chaque élément : { e (Obstacles.edge), sqA, sqB, kind
-- ("door", "fence", "window"), obj, wk }.
local function openingsNear(fx, fy, z, windows)
    local Ob, cell = LivingKnox.Obstacles, getCell()
    local out = {}
    local R = Detour.RADIUS
    for x = fx - R, fx + R do
        for y = fy - R, fy + R do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                for _, side in ipairs({ "W", "N" }) do
                    local e = Ob.edge(x, y, z, side)
                    local nb = cell:getGridSquare(e.bx, e.by, z)
                    if nb ~= nil then
                        local f = LivingKnox.Edges.read(sq, nb)
                        if f.door then
                            out[#out + 1] = { e = e, sqA = sq, sqB = nb, kind = "door", obj = f.door.obj }
                        elseif windows and f.window then
                            out[#out + 1] = { e = e, sqA = sq, sqB = nb, kind = "window", obj = f.window.obj,
                                wk = f.window.kind }
                        elseif f.fence then
                            out[#out + 1] = { e = e, sqA = sq, sqB = nb, kind = "fence" }
                        end
                    end
                end
            end
        end
    end
    return out
end

local function centerDist(px, py, sq)
    return LivingKnox.Obstacles.dist(px, py, sq:getX() + 0.5, sq:getY() + 0.5)
end

-- Cases avant et après de l'ouverture c pour aller du lieu near vers le lieu far (destination dans le lieu goal),
-- corps au point (px, py), et rang (voir l'en-tête) ; nil si elle ne sert pas.
local function sidesOf(c, near, far, goal, px, py)
    local pa, pb = Detour.placeOf(c.sqA), Detour.placeOf(c.sqB)
    local before, after, pafter
    if pa == near and pb == near then
        if centerDist(px, py, c.sqA) <= centerDist(px, py, c.sqB) then before, after = c.sqA, c.sqB
        else before, after = c.sqB, c.sqA end
        pafter = near
    elseif pa == near then
        before, after, pafter = c.sqA, c.sqB, pb
    elseif pb == near then
        before, after, pafter = c.sqB, c.sqA, pa
    else
        return nil
    end
    if pafter == far then return before, after, 1 end
    if pafter == goal then return before, after, 2 end
    if near ~= Detour.OUTSIDE and pafter ~= near then return before, after, 3 end
    return nil
end

-- Clé (Obstacles.edge) du bord commun des cases voisines orthogonales a et b.
local function edgeKeyOf(a, b)
    local x, y, side = a:getX(), a:getY(), "W"
    if b:getX() > x then x = b:getX()
    elseif b:getY() > y then y, side = b:getY(), "N"
    elseif b:getY() < y then side = "N" end
    return LivingKnox.Obstacles.edge(x, y, a:getZ(), side).key
end

-- Règles d'un tronçon de couloir du PNJ id : lieux permis (places : lieu -> vrai), portes jugées avec trapped (dernier
-- recours) et jamais par une clé de skip (déjà refusée), case free (destination) dispensée d'être praticable.
local function laneOf(id, trapped, skip, places, free)
    return { id = id, trapped = trapped, skip = skip, places = places, free = free }
end

-- Vrai si le corps passe de la case a à sa voisine orthogonale b dans le couloir lane : b dans un lieu permis et
-- praticable (sauf lane.free) ; bord classé dans l'ordre de la base pz-knowledge (pathfinding-and-obstacles.md,
-- « Classer le bord commun de deux cases ») : porte (passée si doorRefusal ne la refuse pas, abordée depuis a ;
-- isBlockedTo est vrai pour toute porte fermée, IsoDoor.isBlocked), fenêtre de tout état et
-- clôture basse refusées, puis mur ou escalier (isBlockedTo) ; règle pure LivingKnox.EdgeRules.corridorStep.
function Detour.corridorStep(lane, a, b)
    if not lane.places[Detour.placeOf(b)] then return false end
    if b ~= lane.free and not b:isFree(false) then return false end
    local f = LivingKnox.Edges.read(a, b)
    return LivingKnox.EdgeRules.corridorStep(f, function()
        return not lane.skip[edgeKeyOf(a, b)] and Detour.doorRefusal(lane.id, f.door.obj, a, b, a, lane.trapped) == nil
    end)
end

-- Accès aux cases d'un couloir (LK_DetourCorridor) : cases chargées du niveau z, pas de corridorStep selon lane.
local function corridorGrid(z, lane)
    local cell = getCell()
    return {
        square = function(x, y) return cell:getGridSquare(x, y, z) end,
        open = function(a, b) return Detour.corridorStep(lane, a, b) end,
    }
end

-- Coins des deux couloirs de l'ouverture (cases before et after) pour le trajet t (voir pick) : way (corps -> case
-- avant) et tail (case après -> destination ; vide si la destination est sur un autre niveau), ou nil si l'un manque.
local function corridorsOf(t, before, after, trapped)
    local C = LivingKnox.DetourCorridor
    local near = corridorGrid(t.z, laneOf(t.id, trapped, t.skip, { [t.near] = true }))
    local way = C.plan(near, t.px, t.py, before:getX(), before:getY(), Detour.RADIUS)
    if way == nil then return nil end
    if t.dest == nil then return way, {} end
    local places = { [Detour.placeOf(after)] = true, [t.goal] = true }
    local far = corridorGrid(t.z, laneOf(t.id, trapped, t.skip, places, t.dest))
    local tail = C.toward(far, after:getX() + 0.5, after:getY() + 0.5, t.dest:getX(), t.dest:getY(), Detour.RADIUS)
    if tail == nil then return nil end
    return way, tail
end

-- Vrai si le PNJ id passe l'ouverture c de la case before vers la case after (trapped : dernier recours).
local function usable(id, c, before, after, trapped)
    if c.kind == "fence" then return true end
    if c.kind == "door" then return Detour.doorRefusal(id, c.obj, c.sqA, c.sqB, before, trapped) == nil end
    return trapped and Detour.windowRefusal(id, c.obj, c.wk, c.sqA, c.sqB, before, after) == nil
end

-- Ouverture choisie pour le trajet t = { id, px, py, z, near, far, goal, dest, skip } (PNJ id, corps au point
-- (px, py) du niveau z, lieux du corps, de l'autre côté de l'ouverture refusée et de la destination, case de
-- destination au niveau z ou nil, clés à écarter) : la plus proche du meilleur rang, utilisable (trapped : dernier
-- recours), avec ses deux couloirs. Rend { c, before, after, rank, d, way, tail } ou nil.
local function pick(t, trapped)
    local best = nil
    for _, c in ipairs(openingsNear(math.floor(t.px), math.floor(t.py), t.z, trapped)) do
        if not t.skip[c.e.key] then
            local before, after, rank = sidesOf(c, t.near, t.far, t.goal, t.px, t.py)
            if before ~= nil and before:isFree(false) and after:isFree(false) then
                local d = LivingKnox.Obstacles.dist(t.px, t.py, c.e.mx, c.e.my)
                local better = best == nil or rank < best.rank or (rank == best.rank and (d < best.d - 1e-9
                    or (math.abs(d - best.d) <= 1e-9 and c.e.key < best.c.e.key)))
                if better and usable(t.id, c, before, after, trapped) then
                    local way, tail = corridorsOf(t, before, after, trapped)
                    if way ~= nil then
                        best = { c = c, before = before, after = after, rank = rank, d = d, way = way, tail = tail }
                    end
                end
            end
        end
    end
    return best
end

-- Points de passage : coins du premier couloir, { case avant, case après }, coins du second couloir, tous serrés
-- (best nil : aucun), puis contournement des plantes et feux de camp jusqu'à la destination de e
-- (Directives.planDetour, depuis le dernier de ces points ou le point (px, py)).
local function pointsOf(e, best, px, py)
    local w = {}
    local sx, sy = px, py
    if best ~= nil then
        for _, p in ipairs(best.way) do w[#w + 1] = { x = p.x, y = p.y, t = true } end
        w[#w + 1] = { x = best.before:getX(), y = best.before:getY(), t = true }
        w[#w + 1] = { x = best.after:getX(), y = best.after:getY(), t = true }
        for _, p in ipairs(best.tail) do w[#w + 1] = { x = p.x, y = p.y, t = true } end
        local last = w[#w]
        sx, sy = last.x + 0.5, last.y + 0.5
    end
    local around = LivingKnox.Directives.planDetour(sx, sy, e.x, e.y, e.z)
    if around ~= nil then
        for _, p in ipairs(around) do w[#w + 1] = { x = p.x, y = p.y } end
    end
    return w
end

-- Nombre de points du détour par l'ouverture de best (coins du premier couloir, cases avant et après : dk de
-- Directives.reroute, Directives.detouring ; après l'ouverture, les règles de contact ordinaires reprennent).
local function detourPoints(best)
    return #best.way + 2
end

-- Détour du PNJ id (corps z, consigne e) après le refus de l'ouverture c (clés déjà refusées : skip). Rend
-- { w, dk, lr, via, kind } ou nil et la raison (anglais).
function Detour.plan(id, e, c, z, skip)
    local Ob = LivingKnox.Obstacles
    local px, py, pz = z:getX(), z:getY(), math.floor(z:getZ())
    local nearSq, farSq = c.sqA, c.sqB
    if Ob.sideOf(c.e, px, py) ~= "a" then nearSq, farSq = c.sqB, c.sqA end
    local near, far = Detour.placeOf(nearSq), Detour.placeOf(farSq)
    local destSq = getCell():getGridSquare(e.x, e.y, e.z)
    local goal = Detour.placeOf(destSq)
    local t = { id = id, px = px, py = py, z = pz, near = near, far = far, goal = goal, skip = skip,
        dest = e.z == pz and destSq or nil }
    local best = pick(t, false)
    if best ~= nil then
        return { w = pointsOf(e, best, px, py), dk = detourPoints(best), via = best.c.e.key, kind = best.c.kind }
    end
    local why = "no usable door, gate or low fence within " .. Detour.RADIUS .. " squares"
    if near == Detour.OUTSIDE then return nil, why end
    if e.lr == true then return nil, why .. ", last resort already given" end
    -- Dernier recours (LK04-T20) : règles de dernier recours, l'ouverture refusée comprise.
    t.skip = {}
    local last = pick(t, true)
    if last == nil then return nil, why .. " and no way out of building " .. near .. " even as a last resort" end
    if last.c.e.key == c.e.key then
        return { w = pointsOf(e, nil, px, py), lr = true, via = last.c.e.key, kind = last.c.kind }
    end
    return { w = pointsOf(e, last, px, py), dk = detourPoints(last), lr = true, via = last.c.e.key, kind = last.c.kind }
end

-- Gestionnaire des refus au contact (Obstacles.onRefusal) : ouverture c (bord c.e, cases c.sqA et c.sqB) refusée au
-- PNJ id pendant la consigne e (what "door" ou "window", raison why). Rend vrai si la consigne a reçu un détour
-- (LK_Obstacles ne la close pas), faux sinon (refus inchangé).
function Detour.afterRefusal(id, e, c, why, what)
    if e == nil or e.done or e.op ~= LivingKnox.Directives.OP_MOVE then return false end
    local z = LivingKnox.Bodies.find(id)
    if z == nil or math.floor(z:getZ()) ~= c.e.z then return false end
    local mem = memoryOf(id, e)
    local key = c.e.key
    if mem.keys[key] then
        LivingKnox.Log.info("npc %s: move #%d refused again at the %s %s: no second detour", id, e.v, tostring(what), key)
        return false
    end
    mem.keys[key] = true
    if mem.n >= Detour.MAX_PER_MOVE then
        LivingKnox.Log.warn("npc %s: move #%d no detour after the refused %s %s: %d detours already", id, e.v, tostring(what),
            key, mem.n)
        return false
    end
    local p, none = Detour.plan(id, e, c, z, mem.keys)
    if p == nil then
        count("none")
        LivingKnox.Log.warn("npc %s: move #%d no detour after the refused %s %s (%s): %s", id, e.v, tostring(what), key,
            tostring(why), tostring(none))
        return false
    end
    mem.n = mem.n + 1
    local text
    if p.lr and p.via == key then
        text = "last resort through the refused " .. tostring(what) .. " " .. key
    elseif p.lr then
        text = "last resort detour through the " .. p.kind .. " " .. p.via
    else
        text = "detour through the " .. p.kind .. " " .. p.via
    end
    if not LivingKnox.Directives.reroute(id, { w = p.w, dk = p.dk, lr = p.lr },
        text .. " after the refused " .. tostring(what) .. " " .. key .. " (" .. tostring(why) .. ")") then
        return false
    end
    count(p.lr and "lastResorts" or "detours")
    return true
end

LivingKnox.Obstacles.onRefusal = Detour.afterRefusal
