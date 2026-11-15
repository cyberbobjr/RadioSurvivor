-- Living Knox : signalement d'un blocage par un autre PNJ, cote executant (LK18-T02). ADR :
-- docs/architecture/decisions/adr-ceder-le-passage.md (D01, D06). Fiche : docs/annexes/conception/passage.md.
--
-- Machine qui simule le corps (client MP proprietaire, solo ; appele par LK_Executor quand un "move" ne progresse
-- plus depuis STILL_MS, et avant le traitement du blocage de LK_Movement) :
--   1. un autre corps de PNJ (corps connus ici, Executor.loadedBodies) se tient juste devant : a RANGE case au plus,
--      meme niveau, du cote de l'etape visee (produit scalaire positif avec la direction de l'etape) ;
--   2. signal "bloque par un PNJ" remis a l'autorite (solo : appel direct de LivingKnox.PassageAuthority.onSignal ;
--      client MP : commande Passage.CMD_BLOCKED), une fois par etape du trajet ;
--   3. attente bornee (WAIT_MS) au lieu d'un echec : chemin relance des que le PNJ a quitte le couloir devant
--      (LANE_COS), sinon, l'attente passee, traitement habituel du blocage (nouvelle requete, deblocage, "stuck").
-- En solo, un refus de l'autorite (aucun passage) rend aussitot le traitement habituel ; un client MP n'a pas de
-- reponse et attend WAIT_MS au plus. L'autorite seule arbitre et ordonne (LK_PassageAuthority).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Passage"

local Signal = LivingKnox.PassageSignal or {}
LivingKnox.PassageSignal = Signal

Signal.RANGE = 1.5       -- cases entre les deux corps
Signal.LANE_COS = 0.75   -- PNJ encore dans le couloir devant : cosinus de l'ecart avec la direction de l'etape
Signal.WAIT_MS = 6000    -- attente bornee du passage apres le signal
Signal.STILL_MS = 1500   -- sans progres depuis ce temps, un PNJ devant est cherche (sans attendre Movement.STUCK_MS)

-- Distance et cosinus de l'ecart entre (dx, dy) et la direction (hx, hy) ; cosinus nil si une direction est nulle.
local function aim(dx, dy, hx, hy)
    local d = math.sqrt(dx * dx + dy * dy)
    local h = math.sqrt(hx * hx + hy * hy)
    if d == 0 or h == 0 then return d, nil end
    return d, (dx * hx + dy * hy) / (d * h)
end

-- Corps de PNJ juste devant z vers la case (tx, ty) : a RANGE case au plus, meme niveau, cosinus > minCos (0 par
-- defaut : tout ce qui n'est pas derriere). known = { [npcId] = corps }. Rend l'identifiant et le corps du plus
-- proche (a egalite, le plus petit identifiant), ou nil.
function Signal.blockerAhead(z, known, selfId, tx, ty, minCos)
    minCos = minCos or 0
    local x, y, lv = z:getX(), z:getY(), math.floor(z:getZ())
    local hx, hy = tx + 0.5 - x, ty + 0.5 - y
    local bestId, best, bestD = nil, nil, nil
    for id, b in pairs(known) do
        if id ~= selfId and b ~= z and not b:isDead() and math.floor(b:getZ()) == lv then
            local d, cos = aim(b:getX() - x, b:getY() - y, hx, hy)
            if d <= Signal.RANGE and cos ~= nil and cos > minCos
                and (bestD == nil or d < bestD or (d == bestD and id < bestId)) then
                bestId, best, bestD = id, b, d
            end
        end
    end
    return bestId, best
end

-- Arguments du signal : demandeur id (consigne run.v, bail run.l), bloqueur bid, positions, etape visee.
function Signal.args(id, run, z, bid, b, tx, ty)
    return { id = id, v = run.v, l = run.l, b = bid, x = z:getX(), y = z:getY(), z = z:getZ(), bx = b:getX(),
        by = b:getY(), bz = b:getZ(), tx = tx, ty = ty }
end

-- Remet le signal a l'autorite. Solo : vrai si un passage est accorde, faux sinon ; client MP : nil (envoye, sans
-- reponse) ou faux (aucun joueur local).
function Signal.send(args)
    local P = LivingKnox.Passage
    if LivingKnox.isAuthority() then
        local A = LivingKnox.PassageAuthority
        if A == nil or A.onSignal == nil then return false end
        return A.onSignal(getPlayer(), args) ~= nil
    end
    local player = getPlayer()
    if player == nil then return false end
    sendClientCommand(player, P.MODULE, P.CMD_BLOCKED, args)
    return nil
end

-- Attente d'un passage pour l'execution run (corps z, etape (tx, ty), corps connus known, instant t). Rend :
--   "signal" : PNJ devant, signal remis, attente commencee ;
--   "wait"   : attente en cours (le PNJ est encore dans le couloir devant) ;
--   "clear"  : le PNJ a quitte le couloir devant, chemin a relancer ;
--   nil      : rien a attendre (aucun PNJ devant, refus en solo, attente deja faite pour cette etape).
-- Etat garde dans run.passage = { k, ms, by, over }.
function Signal.step(id, run, z, known, tx, ty, t)
    local w = run.passage
    if w ~= nil and w.k == run.k then
        if w.over then return nil end
        if Signal.blockerAhead(z, known, id, tx, ty, Signal.LANE_COS) == nil then
            w.over = true
            return "clear"
        end
        if t - w.ms < Signal.WAIT_MS then return "wait" end
        w.over = true
        return nil
    end
    local bid, b = Signal.blockerAhead(z, known, id, tx, ty)
    if bid == nil then return nil end
    local sent = Signal.send(Signal.args(id, run, z, bid, b, tx, ty))
    run.passage = { k = run.k, ms = t, by = bid, over = sent == false }
    if sent == false then return nil end
    return "signal"
end

-- Vrai si une attente de passage est en cours pour l'execution run (etape courante).
function Signal.waiting(run)
    local w = run.passage
    return w ~= nil and w.k == run.k and not w.over
end

return Signal
