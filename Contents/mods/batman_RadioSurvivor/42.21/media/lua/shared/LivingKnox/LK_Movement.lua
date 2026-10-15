-- Living Knox : détection de blocage et déblocage d'un "move" (LK04-T05). Fiche : docs/conception/deplacement.md,
-- section « Blocage et déblocage (LK04-T05) ». Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Deux moitiés, chargées partout (media/lua/shared) :
--   exécutant (machine qui simule le corps : client MP propriétaire, solo ; appelé par LK_Executor.follow) :
--     progrès d'un "move" = distance au centre de l'étape courante qui baisse d'IMPROVE case, ou case jamais visitée
--     pendant ce trajet (un détour du chemin vanilla, illisible depuis Lua, éloigne parfois de l'étape) ; aucun
--     progrès pendant STUCK_MS, hors pauses (geste ponctuel : ouvrir une fenêtre, attendre, forcer, LK04-T04/T13 ;
--     escalade climbwindow/climbfence ; attente devant une porte ou une fenêtre fermée) -> déblocage local :
--       1. nouvelle requête de chemin (pathToLocation vers l'étape) ;
--       2. point intermédiaire de déblocage : case praticable à UNBLOCK_MIN..UNBLOCK_MAX cases du corps, joignable
--          en ligne dégagée (cases isFree(false), bords sans mur, porte, fenêtre, cadre ni clôture), sans plante
--          cultivée à 1 case, au plus à la distance actuelle + UNBLOCK_SLACK de l'étape ; la plus proche de l'étape
--          (ordre de parcours fixe à égalité) ; détour de UNBLOCK_MS au plus, puis chemin relancé vers l'étape ;
--       3. échec rapporté à l'autorité, raison REASON ("stuck") et détail (cause, position, distance).
--     Les nouveaux essais de l'exécutant (chemin terminé sans arrivée, immobile STALL_MS) mènent au point 2 quand ils
--     sont épuisés, au lieu d'un échec immédiat. Une étape atteinte remet tout à zéro.
--   autorité (serveur MP, solo ; appelé par LK_Directives) : une consigne close en échec "stuck" est notée par PNJ
--     (case visée, AVOID_MS) ; Directives.moveTo refuse au même PNJ une case à AVOID_RADIUS de celle-ci pendant ce
--     délai, et le cadre de décision (LK_Decisions) avance l'échéance du comportement dont la consigne a échoué
--     (Movement.takeStuck) : la cascade existante choisit alors une autre consigne.
-- Chemin d'un zombie : nœuds illisibles en Lua ; PathFindState efface bPathfind en échec comme en succès
-- (J/ai/states/PathFindState.java:51-71) ; piétinement : échec après walkingOnTheSpot
-- (J/pathfind/PathFindBehavior2.java:750-752) ; base pz-knowledge pathfinding-and-obstacles.md.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local Movement = LivingKnox.Movement or {}
LivingKnox.Movement = Movement

Movement.STUCK_MS = 6000       -- sans progrès pendant ce temps (pauses exclues) : déblocage, puis échec
Movement.IMPROVE = 0.5         -- cases : baisse de la distance à l'étape qui compte comme progrès
Movement.SEEN_MAX = 400        -- cases visitées gardées par trajet (au-delà, la mémoire repart de zéro)
Movement.UNBLOCK_MIN = 2       -- cases (Tchebychev) : anneaux des points de déblocage candidats
Movement.UNBLOCK_MAX = 3
Movement.UNBLOCK_SLACK = 2     -- cases : point au plus à la distance actuelle de l'étape + ce surplus
Movement.UNBLOCK_MS = 5000     -- durée maximale du détour vers le point de déblocage
Movement.LINE_STEP = 0.1       -- cases : échantillonnage de la ligne dégagée
Movement.REASON = "stuck"      -- raison d'échec rapportée à l'autorité (consigne close, LK_Directives)
Movement.AVOID_STUCK = true    -- autorité : case d'un échec "stuck" refusée au même PNJ pendant AVOID_MS
Movement.AVOID_MS = 60000
Movement.AVOID_RADIUS = 1      -- cases (Tchebychev, même niveau)
Movement.AVOID_KEEP = 4        -- cases d'échec gardées par PNJ
Movement.WHY_MAX = 40          -- caractères d'une raison reçue d'un client
Movement.DETAIL_MAX = 160      -- caractères du détail reçu d'un client

Movement.stuckAt = Movement.stuckAt or {}   -- autorité : npcId -> { { x, y, z, ms, v, taken }, ... }
Movement.stats = Movement.stats or { detected = 0, repaths = 0, unblocks = 0, unblockReached = 0, unblockTimeout = 0,
    noPoint = 0, stuck = 0, noted = 0, avoided = 0, taken = 0 }

local function log() return LivingKnox.Log end
local function now() return getTimestampMs() end

local function count(name)
    local st = Movement.stats
    st[name] = (st[name] or 0) + 1
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- ================================================================ exécutant

-- Remet à zéro le suivi de progrès d'une exécution (départ, reprise, étape atteinte). Rend l'état de suivi.
function Movement.begin(run, t)
    run.mv = { seen = {}, nSeen = 0, ref = nil, refMs = t or now(), repathed = false, unblocked = false,
        since = t or now() }
    run.unblock = nil
    return run.mv
end

-- Pause (geste ponctuel, escalade, attente devant une porte, chemin relancé) : le temps sans progrès repart de t.
function Movement.pause(run, t)
    local m = run.mv
    if m == nil then return end
    m.ref = nil
    m.refMs = t or now()
end

-- Note la position du corps z à l'instant t, d = distance au centre de l'étape courante (nil sur un autre niveau).
-- Rend vrai si aucun progrès n'a été vu depuis STUCK_MS.
function Movement.progress(run, z, d, t)
    local m = run.mv or Movement.begin(run, t)
    local key = math.floor(z:getX()) .. "," .. math.floor(z:getY()) .. "," .. math.floor(z:getZ())
    local moved = false
    if not m.seen[key] then
        if m.nSeen >= Movement.SEEN_MAX then m.seen, m.nSeen = {}, 0 end
        moved = m.nSeen > 0   -- la première case vue n'est pas un progrès
        m.seen[key] = true
        m.nSeen = m.nSeen + 1
    end
    if d ~= nil and (m.ref == nil or d <= m.ref - Movement.IMPROVE) then
        m.ref = d
        m.refMs = t
        return false
    end
    if moved then
        m.refMs = t
        if d ~= nil and d < m.ref then m.ref = d end
        return false
    end
    return t - m.refMs >= Movement.STUCK_MS
end

-- Durée sans progrès (ms) à l'instant t.
function Movement.stillMs(run, t)
    local m = run.mv
    if m == nil then return 0 end
    return t - m.refMs
end

-- Vrai si le bord commun des cases voisines a et b porte un mur, une porte, une fenêtre, un cadre ou une clôture
-- (IsoGridSquare.isBlockedTo, getDoorTo, getWindowTo, getWindowThumpableTo, getWindowFrameTo, isHoppableTo :
-- J/iso/IsoGridSquare.java:935-941, 1043-1049, 3065-3111, 3131-3172, 3228-3236). Le point de déblocage ne franchit rien.
function Movement.edgeBlocked(a, b)
    if a:isBlockedTo(b) then return true end
    if a:getDoorTo(b) ~= nil then return true end
    if a:getWindowTo(b) ~= nil or a:getWindowThumpableTo(b) ~= nil or a:getWindowFrameTo(b) ~= nil then return true end
    if a.isHoppableTo ~= nil and a:isHoppableTo(b) then return true end
    return false
end

local function walkable(sq)
    return sq ~= nil and sq:isFree(false)
end

-- Vrai si le segment (x0, y0) -> (x1, y1) du niveau lv ne passe que par des cases praticables chargées, sans franchir
-- de bord bloqué ; un coin n'est franchi que si ses deux cases et ses quatre bords sont libres.
function Movement.clearLine(x0, y0, x1, y1, lv)
    local cell = getCell()
    if cell == nil then return false end
    local px, py = math.floor(x0), math.floor(y0)
    local prev = cell:getGridSquare(px, py, lv)
    if prev == nil then return false end
    local n = math.max(1, math.ceil(dist(x0, y0, x1, y1) / Movement.LINE_STEP))
    for i = 1, n do
        local cx = math.floor(x0 + (x1 - x0) * i / n)
        local cy = math.floor(y0 + (y1 - y0) * i / n)
        if cx ~= px or cy ~= py then
            local sq = cell:getGridSquare(cx, cy, lv)
            if not walkable(sq) then return false end
            if cx ~= px and cy ~= py then
                local a = cell:getGridSquare(cx, py, lv)
                local b = cell:getGridSquare(px, cy, lv)
                if not walkable(a) or not walkable(b) then return false end
                if Movement.edgeBlocked(prev, a) or Movement.edgeBlocked(a, sq) or Movement.edgeBlocked(prev, b)
                    or Movement.edgeBlocked(b, sq) then
                    return false
                end
            elseif Movement.edgeBlocked(prev, sq) then
                return false
            end
            prev, px, py = sq, cx, cy
        end
    end
    return true
end

-- Vrai si une plante cultivée est sur sq ou à 1 case (LK04-T06 : un corps ne s'arrête pas près d'une plante ;
-- hasFarmingPlant est lisible sur un client MP, J/iso/IsoGridSquare.java:9713-9765).
local function nearPlant(cell, x, y, lv)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(x + dx, y + dy, lv)
            if sq ~= nil and sq.hasFarmingPlant ~= nil and sq:hasFarmingPlant() then return true end
        end
    end
    return false
end

-- Point de déblocage du corps z vers la case (tx, ty) : { x, y }, ou nil et la raison. Ordre fixe (anneau, puis x,
-- puis y croissants) : même choix sur toute machine pour les mêmes cases.
function Movement.unblockPoint(z, tx, ty)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local zx, zy = z:getX(), z:getY()
    local x0, y0, lv = math.floor(zx), math.floor(zy), math.floor(z:getZ())
    local d0 = dist(zx, zy, tx + 0.5, ty + 0.5)
    local best, bestD = nil, nil
    local seen = 0
    for r = Movement.UNBLOCK_MIN, Movement.UNBLOCK_MAX do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = x0 + dx, y0 + dy
                    local sq = cell:getGridSquare(x, y, lv)
                    if walkable(sq) then
                        seen = seen + 1
                        local dd = dist(x + 0.5, y + 0.5, tx + 0.5, ty + 0.5)
                        if dd <= d0 + Movement.UNBLOCK_SLACK and (bestD == nil or dd < bestD - 1e-9)
                            and not nearPlant(cell, x, y, lv) and Movement.clearLine(zx, zy, x + 0.5, y + 0.5, lv) then
                            best, bestD = { x = x, y = y }, dd
                        end
                    end
                end
            end
        end
    end
    if best == nil then
        return nil, string.format("no free square in a clear line %d to %d squares around %.1f,%.1f (%d walkable)",
            Movement.UNBLOCK_MIN, Movement.UNBLOCK_MAX, zx, zy, seen)
    end
    return best
end

-- Prochaine réponse à un blocage de l'exécution run : "repath" (nouvelle requête, seulement pour une absence de
-- progrès, les nouveaux essais de l'exécutant en ayant déjà fait), "unblock" (et le point), ou "fail" (et le
-- détail). cause : "no approach" (aucun progrès), "no progress" (immobile, essais épuisés), "no path" (recherche
-- terminée sans arrivée, essais épuisés). Note la réponse dans l'état de suivi.
function Movement.respond(run, z, tx, ty, cause, t)
    local m = run.mv or Movement.begin(run, t)
    if cause == "no approach" and not m.repathed then
        m.repathed = true
        count("repaths")
        return "repath"
    end
    if not m.unblocked then
        m.unblocked = true
        local p, why = Movement.unblockPoint(z, tx, ty)
        if p ~= nil then
            count("unblocks")
            run.unblock = { x = p.x, y = p.y, ms = t, from = { x = z:getX(), y = z:getY() } }
            return "unblock", p
        end
        count("noPoint")
        return "fail", string.format("%s at %.1f,%.1f, %d ms without progress, %s", cause, z:getX(), z:getY(),
            t - m.since, why)
    end
    return "fail", string.format("%s at %.1f,%.1f after a new path request and an unblocking point", cause, z:getX(),
        z:getY())
end

-- Détour vers le point de déblocage en cours : rend nil tant qu'il dure, sinon "reached" (point atteint à arrive
-- case), "ended" (recherche finie sans arrivée) ou "timeout" (UNBLOCK_MS).
function Movement.legEnd(run, z, searching, arrive, t)
    local leg = run.unblock
    if leg == nil then return nil end
    if dist(z:getX(), z:getY(), leg.x + 0.5, leg.y + 0.5) <= arrive then return "reached" end
    if t - leg.ms >= Movement.UNBLOCK_MS then return "timeout" end
    if not searching then return "ended" end
    return nil
end

-- ================================================================ autorité

local function cheb(ax, ay, bx, by)
    return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- Raison reçue d'un rapport : chaîne courte, sinon nil.
function Movement.cleanWhy(why, max)
    if type(why) ~= "string" or why == "" then return nil end
    max = max or Movement.WHY_MAX
    if #why > max then return string.sub(why, 1, max) end
    return why
end

-- Consigne e du PNJ id close en échec "stuck" (autorité) : case visée notée pour AVOID_MS. Rend vrai.
function Movement.noteStuck(id, e)
    if not LivingKnox.isAuthority() or type(id) ~= "string" or type(e) ~= "table" then return false end
    if type(e.x) ~= "number" or type(e.y) ~= "number" or type(e.z) ~= "number" then return false end
    local list = Movement.stuckAt[id] or {}
    local t = now()
    local keep = {}
    for _, s in ipairs(list) do
        if t - s.ms < Movement.AVOID_MS then keep[#keep + 1] = s end
    end
    keep[#keep + 1] = { x = e.x, y = e.y, z = e.z, ms = t, v = e.v, taken = false }
    while #keep > Movement.AVOID_KEEP do table.remove(keep, 1) end
    Movement.stuckAt[id] = keep
    count("noted")
    log().info("npc %s: %s #%s stuck, target %d,%d,%d avoided by this npc for %d s", id, tostring(e.op),
        tostring(e.v), e.x, e.y, e.z, math.floor(Movement.AVOID_MS / 1000))
    return true
end

-- Raison de refuser au PNJ id la case (x, y, z) (échec "stuck" récent à AVOID_RADIUS), ou nil.
function Movement.avoided(id, x, y, z)
    if not Movement.AVOID_STUCK then return nil end
    local list = Movement.stuckAt[id]
    if list == nil then return nil end
    local t = now()
    for _, s in ipairs(list) do
        local age = t - s.ms
        if age < Movement.AVOID_MS and s.z == z and cheb(s.x, s.y, x, y) <= Movement.AVOID_RADIUS then
            count("avoided")
            return string.format("target %d,%d,%d avoided: this npc got stuck going to %d,%d,%d %d s ago", x, y, z,
                s.x, s.y, s.z, math.floor(age / 1000))
        end
    end
    return nil
end

-- Vrai une seule fois si la consigne v du PNJ id a été close en échec "stuck" (cadre de décision : échéance
-- avancée, la cascade choisit une autre consigne).
function Movement.takeStuck(id, v)
    if v == nil then return false end
    local list = Movement.stuckAt[id]
    if list == nil then return false end
    for _, s in ipairs(list) do
        if s.v == v and not s.taken then
            s.taken = true
            count("taken")
            return true
        end
    end
    return false
end

-- Oublie les échecs notés d'un PNJ (tous si id est nil) : suites de test, PNJ oublié.
function Movement.forgetStuck(id)
    if id == nil then
        Movement.stuckAt = {}
    else
        Movement.stuckAt[id] = nil
    end
end

return Movement
