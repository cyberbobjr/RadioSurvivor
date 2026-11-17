-- Living Knox : passage demande par un PNJ bloque par un autre, cote autorite (LK18-T02). ADR :
-- docs/architecture/decisions/adr-ceder-le-passage.md (D01, D03, D06). Fiche : docs/annexes/conception/passage.md.
--
-- Recoit le signal de l'executant (LK_PassageSignal : appel direct en solo, commande Passage.CMD_BLOCKED d'un client
-- MP) et, seule, arbitre et ordonne :
--   1. controles : demandeur et bloqueur incarnes ; expediteur proprietaire du corps du demandeur
--      (Directives.isOwner) ; consigne "move" ouverte du demandeur, du numero signale ; corps VOISINS vus par
--      l'autorite (meme niveau, NEIGHBOUR case au plus, distance de Tchebychev) ; au plus un signal par demandeur et
--      par SIGNAL_MS ;
--   2. genre de passage de chaque PNJ (kindOf : son comportement au cadre de decision, "care" quand le soin le mene)
--      ; bloqueur en marche (moving : consigne "move" ouverte ; immobile, il cede toujours, mise a jour du
--      2026-11-15 soir, D07) et capable de bouger (canMove : vivant, hors combat, ni soigne ni soignant, pas deja a
--      l'ecart) ;
--   3. cases libres autour du bloqueur (freeAround, relevees ici, D06, D08) : joignables a pied en FREE_RADIUS pas au
--      plus (pas entre voisines par un cote : case praticable, aucun personnage debout, bord libre au sens de
--      Edges.closed), sans danger (Bodies.hazardOn) ; cases de passage comprises (l'ecart dure quelques
--      secondes, ce n'est pas une place d'arret) ;
--   4. LivingKnox.Passage.arbitrate ; decision stepAside ou backOff : ordre au bloqueur (LivingKnox.StepAside.order),
--      marche visant la case libre juste au-dela de la case decidee, dans le meme sens (walkTarget : un corps
--      "arrive" a Directives.ARRIVE case du centre vise, soit une case : sans ce depassement, il resterait sur le
--      bord du couloir), sinon la case decidee ;
--      et consigne du demandeur excusee (Movement.excuse : un echec "stuck" ne la note pas) ; decision nil : rien,
--      le demandeur garde le traitement habituel du blocage.
-- Le module ne nomme aucun comportement : priorites au registre (LK_Passage), comportements de combat lus dans
-- Decisions.COMBAT_BEHAVIOURS. Autorite seulement : un client MP charge aussi media/lua/server, il s'arrete ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Movement"
require "LivingKnox/Edges/LK_Edges"
require "LivingKnox/LK_Passage"

local Authority = LivingKnox.PassageAuthority or {}
LivingKnox.PassageAuthority = Authority

Authority.NEIGHBOUR = 2      -- cases (Tchebychev, meme niveau) entre les corps du demandeur et du bloqueur
Authority.FREE_RADIUS = 3    -- pas au plus du bloqueur aux cases relevees pour l'arbitrage (D08)
Authority.PATH_SQUARES = 4   -- cases du trajet du demandeur (ligne vers l'etape) tenues hors de la case de retrait
Authority.SIGNAL_MS = 1000   -- au plus un signal traite par demandeur dans ce delai
Authority.LINE_STEP = 0.25   -- cases : echantillonnage de la ligne du demandeur vers l'etape

Authority.last = Authority.last or {}   -- demandeur -> heure du dernier signal traite
Authority.stats = Authority.stats or { signals = 0, refused = 0, none = 0, granted = 0 }

local function now() return getTimestampMs() end

local function sign(v)
    if v > 0 then return 1 elseif v < 0 then return -1 end
    return 0
end

local function senderName(player)
    if player ~= nil and player.getUsername ~= nil then return tostring(player:getUsername()) end
    return "?"
end

local function refuse(player, args, why)
    Authority.stats.refused = Authority.stats.refused + 1
    local id = type(args) == "table" and args.id or nil
    LivingKnox.Log.info("npc %s: passage signal from %s refused: %s", tostring(id), senderName(player), why)
    return nil, why
end

local function validArgs(a)
    if type(a) ~= "table" or type(a.id) ~= "string" or type(a.b) ~= "string" or a.id == a.b then return false end
    for _, k in ipairs({ "v", "x", "y", "z" }) do
        if not LivingKnox.Num.finite(a[k]) then return false end
    end
    return true
end

-- Genre de passage du PNJ id : "care" quand le soin le mene (LivingKnox.Care), sinon son comportement au cadre de
-- decision, sinon nil (priorite par defaut).
function Authority.kindOf(id)
    local Ca = LivingKnox.Care
    if Ca ~= nil and Ca.get ~= nil and Ca.get(id) ~= nil then return "care" end
    local Dec = LivingKnox.Decisions
    local st = Dec ~= nil and Dec.get ~= nil and Dec.get(id) or nil
    return st ~= nil and st.b or nil
end

-- Vrai si le PNJ id est en marche : consigne "move" ouverte (D07 : sinon il est immobile et cede toujours).
function Authority.movingOf(id)
    local e = LivingKnox.Directives.get(id)
    return e ~= nil and not e.done and e.op == LivingKnox.Directives.OP_MOVE
end

-- Vrai si le PNJ id (corps body) peut s'ecarter ; sinon faux et la raison.
function Authority.canMove(id, body)
    if body == nil or body:isDead() then return false, "dead" end
    local Dec = LivingKnox.Decisions
    if Dec ~= nil then
        local st = Dec.get(id)
        if st ~= nil then
            for _, b in ipairs(Dec.COMBAT_BEHAVIOURS) do
                if st.b == b then return false, "in combat" end
            end
        end
    end
    local C = LivingKnox.Combat
    if C ~= nil and C.get ~= nil and C.get(id) ~= nil then return false, "in combat" end
    local Ca = LivingKnox.Care
    if Ca ~= nil then
        if Ca.caredFor ~= nil and Ca.caredFor(id) then return false, "cared for" end
        if (Ca.get ~= nil and Ca.get(id) ~= nil) or (Ca.taskOf ~= nil and Ca.taskOf(id) ~= nil) then
            return false, "caring"
        end
    end
    local S = LivingKnox.StepAside
    if S ~= nil and S.active ~= nil and S.active(id) then return false, "already stepping aside" end
    return true
end

local SIDES = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

-- Cases libres ou le bloqueur de (bx, by, lv) peut se tenir et qu'il peut joindre a pied en FREE_RADIUS pas au plus
-- (voir l'en-tete), dans l'ordre du parcours en largeur (pas, puis nord, est, sud, ouest).
function Authority.freeAround(bx, by, lv)
    local cell = getCell()
    local Bo, Edges = LivingKnox.Bodies, LivingKnox.Edges
    local out, seen = {}, { [bx .. "," .. by] = true }
    local front = { cell:getGridSquare(bx, by, lv) }
    if front[1] == nil then return out end
    for _ = 1, Authority.FREE_RADIUS do
        local nextFront = {}
        for _, sq in ipairs(front) do
            for _, d in ipairs(SIDES) do
                local x, y = sq:getX() + d[1], sq:getY() + d[2]
                local k = x .. "," .. y
                local nb = not seen[k] and cell:getGridSquare(x, y, lv) or nil
                if nb ~= nil and nb:isFree(false) and not Bo.standingOn(x, y, lv) and not Edges.closed(sq, nb) then
                    seen[k] = true
                    nextFront[#nextFront + 1] = nb
                    if Bo.hazardOn(nb) == nil then out[#out + 1] = { x = x, y = y, z = lv } end
                end
            end
        end
        front = nextFront
    end
    return out
end

-- Prochaines cases du trajet du demandeur (case (mx, my) vers l'etape (tx, ty)) : la case du bloqueur, celle juste
-- au-dela (meme direction), puis PATH_SQUARES cases de la ligne vers l'etape.
function Authority.pathAhead(mx, my, bx, by, tx, ty)
    local out, seen = {}, {}
    local function add(x, y)
        local k = x .. "," .. y
        if seen[k] or (x == mx and y == my) then return end
        seen[k] = true
        out[#out + 1] = { x = x, y = y }
    end
    add(bx, by)
    add(bx + sign(bx - mx), by + sign(by - my))
    local x0, y0, x1, y1 = mx + 0.5, my + 0.5, tx + 0.5, ty + 0.5
    local n = math.max(1, math.ceil(math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / Authority.LINE_STEP))
    local taken = 0
    for i = 1, n do
        local cx = math.floor(x0 + (x1 - x0) * i / n)
        local cy = math.floor(y0 + (y1 - y0) * i / n)
        local k = cx .. "," .. cy
        if not (cx == mx and cy == my) and not seen[k] then
            add(cx, cy)
            taken = taken + 1
            if taken >= Authority.PATH_SQUARES then break end
        end
    end
    return out
end

-- Case visee par la marche du bloqueur de (bx, by) vers la case decidee to : la case libre (liste free) juste au-dela
-- dans le meme sens, sinon to.
function Authority.walkTarget(bx, by, to, free)
    local ax, ay = to.x + sign(to.x - bx), to.y + sign(to.y - by)
    for _, c in ipairs(free) do
        if c.x == ax and c.y == ay then return { x = ax, y = ay, z = to.z } end
    end
    return to
end

-- Raison d'une decision nil de l'arbitrage (journal).
local function noneReason(mover, blocker, cant)
    if blocker.canMove == false then return "blocker cannot move (" .. tostring(cant) .. ")" end
    if not LivingKnox.PassageArbiter.moverPasses(mover, blocker, LivingKnox.Passage.priorityOf) then
        return "blocker has priority"
    end
    return "no free square for the blocker"
end

-- Signal "bloque par un PNJ" (args = LivingKnox.PassageSignal.args) de l'expediteur player. Rend la decision
-- ({ action, to }) si le bloqueur a recu l'ordre de s'ecarter, sinon nil et la raison.
function Authority.onSignal(player, args)
    if not LivingKnox.isAuthority() then return nil, "not the authority" end
    Authority.stats.signals = Authority.stats.signals + 1
    if not validArgs(args) then return refuse(player, args, "bad signal") end
    local id, bid = args.id, args.b
    local mz = LivingKnox.Bodies.find(id)
    if mz == nil then return refuse(player, args, "mover has no body") end
    local bz = LivingKnox.Bodies.find(bid)
    if bz == nil then return refuse(player, args, "blocker " .. bid .. " has no body") end
    if not LivingKnox.Directives.isOwner(mz, player) then return refuse(player, args, "not the owner of " .. id) end
    local e = LivingKnox.Directives.get(id)
    if e == nil or e.done or e.op ~= LivingKnox.Directives.OP_MOVE or e.v ~= args.v then
        return refuse(player, args, "no open move")
    end
    local mx, my, lv = math.floor(mz:getX()), math.floor(mz:getY()), math.floor(mz:getZ())
    local bx, by, bl = math.floor(bz:getX()), math.floor(bz:getY()), math.floor(bz:getZ())
    if bl ~= lv or LivingKnox.Geo.cheb(mx, my, bx, by) > Authority.NEIGHBOUR then
        return refuse(player, args, string.format("not neighbours (%d,%d,%d and %d,%d,%d)", mx, my, lv, bx, by, bl))
    end
    local t = now()
    local last = Authority.last[id]
    if last ~= nil and t - last < Authority.SIGNAL_MS then return refuse(player, args, "too soon") end
    Authority.last[id] = t
    local can, cant = Authority.canMove(bid, bz)
    local mover = { id = id, kind = Authority.kindOf(id), x = mx, y = my, z = lv }
    local blocker = { id = bid, kind = Authority.kindOf(bid), x = bx, y = by, z = bl, canMove = can,
        moving = Authority.movingOf(bid) }
    local tx, ty = LivingKnox.Directives.stepTarget(e, e.k)
    local path = Authority.pathAhead(mx, my, bx, by, tx, ty)
    local free = Authority.freeAround(bx, by, bl)
    local decision = LivingKnox.Passage.arbitrate(mover, blocker, free, path)
    if decision == nil then
        Authority.stats.none = Authority.stats.none + 1
        local why = noneReason(mover, blocker, cant)
        LivingKnox.Log.info("npc %s: blocked by npc %s at %d,%d, no passage: %s (%s vs %s, blocker %s)", id, bid, bx, by, why,
            tostring(mover.kind), tostring(blocker.kind), blocker.moving and "moving" or "still")
        return nil, why
    end
    decision.aim = Authority.walkTarget(bx, by, decision.to, free)
    local ok, why = LivingKnox.StepAside.order(bid, decision, id)
    if not ok then return refuse(player, args, "order not given: " .. tostring(why)) end
    LivingKnox.Movement.excuse(id, e.v)
    Authority.stats.granted = Authority.stats.granted + 1
    LivingKnox.Log.info("npc %s: blocked by npc %s at %d,%d, %s to %d,%d granted (%s vs %s)", id, bid, bx, by,
        decision.action, decision.to.x, decision.to.y, tostring(mover.kind), tostring(blocker.kind))
    return decision
end

-- Oubli (suites de test, PNJ oublie).
function Authority.reset()
    Authority.last = {}
    Authority.stats = { signals = 0, refused = 0, none = 0, granted = 0 }
end

if isServer() and Events ~= nil then
    local function onClientCommand(module, command, player, args)
        local P = LivingKnox.Passage
        if module == P.MODULE and command == P.CMD_BLOCKED then LivingKnox.PassageAuthority.onSignal(player, args) end
    end
    LivingKnox.subscribe("OnClientCommand", "PassageAuthority.onClientCommand", onClientCommand)
end

return Authority
