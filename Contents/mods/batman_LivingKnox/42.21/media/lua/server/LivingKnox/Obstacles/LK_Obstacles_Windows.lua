-- Living Knox : obstacles, fenêtres (LK04-T03, LK04-T13, LK04-T18, LK19-T01) : décision, gestes, fenêtres
-- au contact, fenêtres notées sur un trajet et passant qui escalade.
-- LK20-T09 : sorti de LK_Obstacles.lua sans changement de comportement ; façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- fenêtres (LK04-T03)

-- Fenêtre d'un bord : LivingKnox.Edges.windowOf (ADR adr-bords-des-cases.md).

-- Vrai si la fenêtre arrête un corps : barricadée, ou IsoWindow fermée et intacte. Fenêtre ouverte, cassée ou
-- détruite, cadre vide et fenêtre construite non barricadés : franchis par le moteur (IsoWindow.java:1220-1238,
-- IsoWindowFrame.java:348-372, IsoThumpable.java:2175-2186).
function Obstacles.windowBlocks(w, kind)
    return LivingKnox.EdgeRules.windowStops(LivingKnox.Edges.windowFacts(w, kind))
end

-- Vrai si la case sq n'offre aucun sol où se poser : franchir serait une chute (issue "fall" quand la case opposée
-- n'est pas un sol, ClimbThroughWindowState.java:81-83, 576). Case absente (non chargée) : vrai, par prudence.
function Obstacles.isDrop(sq)
    if sq == nil then return true end
    return not sq:TreatAsSolidFloor()
end

-- Vrai si la case sq, de l'autre côté d'une fenêtre, porte un meuble bas (drapeau solidtrans : comptoir, table,
-- cuisinière...) : l'escalade prend l'issue "obstacle" (zombie : case suivante libre) ou finit sur le meuble
-- (ClimbThroughWindowState.java:574-588), jouée par les nœuds zombie qui mettent le corps au sol (LK04-T11 ne remplace
-- que l'issue "success"). Essai solo du 2026-10-11 23:08 : fenêtre 10747,9532,0,W au-dessus de la table
-- furniture_tables_high_01_15, « on the floor after a crossing true ».
function Obstacles.isFurnitureLanding(sq)
    return sq ~= nil and sq:isSolidTrans() == true
end

-- Case de l'autre côté du bord e, vue du point (px, py).
local function farSquare(e, px, py)
    if P.sideOf(e, px, py) == "a" then return getCell():getGridSquare(e.bx, e.by, e.z) end
    return getCell():getGridSquare(e.ax, e.ay, e.z)
end

-- Vrai si le corps z est tourné vers l'autre côté du bord e (produit scalaire de son orientation avec la normale du
-- bord au moins FACING ; orientation en degrés, vecteur (cos, sin), IsoGameCharacter.java:2626-2635).
function Obstacles.facing(z, e)
    local a = z:getDirectionAngle() * math.pi / 180
    local s = P.sideOf(e, z:getX(), z:getY()) == "a" and 1 or -1
    local f = e.kind == "W" and math.cos(a) or math.sin(a)
    return f * s >= Obstacles.FACING
end

-- Vrai si ouvrir la fenêtre w avec un zombie armerait l'alarme : option ZombieLore.TriggerHouseAlarm et bâtiment
-- du côté intérieur à alarme (IsoWindow.java:164-173, 328-340, 716-718 ; option lue à chaque appel).
function Obstacles.alarmArmed(w)
    local on
    local opt = getSandboxOptions ~= nil and getSandboxOptions():getOptionByName("ZombieLore.TriggerHouseAlarm") or nil
    if opt ~= nil then
        on = opt:getValue() == true
    else
        on = SandboxVars ~= nil and SandboxVars.ZombieLore ~= nil and SandboxVars.ZombieLore.TriggerHouseAlarm == true
    end
    if not on then return false end
    local sq = w:getIndoorSquare()
    local def = sq ~= nil and sq:getBuildingDef() or nil
    return def ~= nil and def:isAlarmed() == true
end

-- Décision pour le PNJ npcId (tout PNJ, pillards compris) arrêté contre la fenêtre w (kind, cases sqA et sqB, case
-- de l'autre côté far) : rend "open", ou nil et la raison du refus (anglais, journal). Jamais de bris.
-- LK04-T20 : trapped (consigne de dernier recours, e.lr : aucune porte utilisable pour sortir), from = case d'où la
-- fenêtre est abordée. Une fenêtre verrouillée s'ouvre alors depuis une case non extérieure (le joueur vanilla l'ouvre
-- de l'intérieur : OpenWindowState ne lutte que dehors ; ToggleWindow ignore et lève le verrou, IsoWindow.java:701-731),
-- et une fenêtre du foyer d'un autre groupe abordée depuis ce foyer (inHomeOf) n'est plus refusée. Barricade,
-- fenêtre inamovible, chute, meuble à l'arrivée et alarme restent refusés.
function Obstacles.decideWindow(npcId, w, kind, sqA, sqB, far, trapped, from)
    if w:isBarricaded() then return nil, "barricaded window" end
    if kind ~= "window" then return nil, kind .. " window not handled" end
    if w:isPermaLocked() then return nil, "window that cannot be opened" end
    if w:isLocked() and not (trapped and from ~= nil and not from:isOutside()) then
        return nil, "locked window"   -- même au foyer du PNJ : il passe par la porte
    end
    if Obstacles.isDrop(far) then return nil, "window over a drop" end
    if Obstacles.isFurnitureLanding(far) then return nil, "window over furniture" end
    local home = Obstacles.homeOf(sqA, sqB)
    local mine = Obstacles.groupOf(npcId)
    if home ~= nil and home ~= mine and not (trapped and Obstacles.inHomeOf(from, home)) then
        return nil, "window of the home of " .. home .. " (not a member)"
    end
    -- Foyer du PNJ en alerte : fenêtres fermées, on sort et on rentre par la porte (E18-T34, lk.windowsally solo du
    -- 2026-11-16 : fenêtre menacée ouverte pour rejoindre le zombie) ; dernier recours (aucune porte) : ouverte.
    local Al = LivingKnox.Alert
    if home ~= nil and home == mine and not trapped and Al ~= nil and Al.get ~= nil and Al.get(home) ~= nil then
        return nil, "window of the home on alert (by the door)"
    end
    if Obstacles.alarmArmed(w) then return nil, "window of an alarmed house" end
    return "open"
end

-- Fixe l'état de la fenêtre w (ouverte si open) : ToggleWindow(chr) seulement si l'état diffère (c'est une
-- bascule : jamais deux fois) ; le moteur recalcule la case, met à jour la recherche de chemin et synchronise
-- (IsoWindow.java:701-731). chr : le corps (copie de l'autorité) ou nil (fermeture sans corps : aucune alarme, aucun
-- contrôle de barricade). Rend vrai si la fenêtre est maintenant dans l'état voulu par cet appel.
-- Fenêtre cassée ou inamovible : jamais touchée (ToggleWindow n'y fait rien, IsoWindow.java:705-711) ; bascule
-- comptée seulement si l'état a changé (LK04-T08).
function Obstacles.setWindow(w, open, chr)
    if (w:IsOpen() == true) == open then return false end
    if w:isDestroyed() or w:isPermaLocked() then return false end
    w:ToggleWindow(chr)
    local done = (w:IsOpen() == true) == open
    if done then P.count("windowToggles") end
    return done
end

-- Ouvre la fenêtre w avec le corps body. Rend vrai si elle est maintenant ouverte par cet appel.
function Obstacles.openWindow(w, body) return Obstacles.setWindow(w, true, body) end

-- Angle (degrés, convention de setDirectionAngle : E 0, S 90, W 180, N 270) qui tourne un corps placé au point
-- (px, py) face au bord e.
function Obstacles.faceAngle(e, px, py)
    local west = P.sideOf(e, px, py) == "a"
    if e.kind == "W" then return west and 0 or 180 end
    return west and 90 or 270
end

-- Geste ponctuel g de ms millisecondes devant la fenêtre du bord e, joué par le corps z du PNJ id tourné vers elle
-- (LivingKnox.Anim.startAct ; l'exécutant arrête le corps, le tourne, puis relance son chemin à la fin du geste).
-- Rend vrai si le geste est posé (refus journalisé). LK21-T12 : partagé avec le retrait du verre (LK_Obstacles_Glass).
local function windowGesture(id, z, e, g, ms)
    local A = LivingKnox.Anim
    if not Obstacles.WINDOW_GESTURE or A == nil or A.startAct == nil or z == nil then return false end
    local ok, why = A.startAct(id, g, ms, Obstacles.faceAngle(e, z:getX(), z:getY()))
    if not ok then
        LivingKnox.Log.warn("npc %s: %s gesture at the window %s refused: %s", id, g, e.key, tostring(why))
        return false
    end
    return true
end

-- Geste devant la fenêtre w du bord e (LK04-T13) : kind "open" (geste openwindow) ou "close" (closewindow), joué par
-- le corps z du PNJ id tourné vers la fenêtre (windowGesture). La fenêtre n'est basculée qu'à l'instant du clip
-- (windowActPass). Rend vrai si le geste est posé.
function Obstacles.startWindowAct(id, z, w, e, kind, t)
    local open = kind == "open"
    local g = open and "openwindow" or "closewindow"
    local ms = open and Obstacles.OPEN_GESTURE_MS or Obstacles.CLOSE_GESTURE_MS
    if not windowGesture(id, z, e, g, ms) then return false end
    t = t or P.now()
    Obstacles.winActs[e.key] = { win = w, e = e, id = id, kind = kind, g = g, ms = t, endMs = t + ms,
        toggleMs = t + (open and Obstacles.OPEN_TOGGLE_MS or Obstacles.CLOSE_TOGGLE_MS),
        from = P.sideOf(e, z:getX(), z:getY()), lx = z:getX(), ly = z:getY() }   -- lx, ly : closeReady (LK04-T18)
    P.count("windowGestures")
    LivingKnox.Log.info("npc %s: %s gesture at the window %s", id, g, e.key)
    return true
end

-- Fenêtres des bords à REACH case au plus du point (px, py) au niveau z, triées par distance. Chaque élément :
-- { win, wk (sorte), e (bord), d, sqA, sqB }.
function Obstacles.windowsNear(px, py, z)
    local cell = getCell()
    local out = {}
    local fx, fy = math.floor(px), math.floor(py)
    for x = fx - 1, fx + 1 do
        for y = fy - 1, fy + 1 do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                for _, kind in ipairs({ "W", "N" }) do
                    local e = P.edge(x, y, z, kind)
                    local nb = cell:getGridSquare(e.bx, e.by, z)
                    local w, wk
                    if nb ~= nil then w, wk = LivingKnox.Edges.windowOf(sq, nb) end
                    if w ~= nil then
                        local d = P.dist(px, py, e.mx, e.my)
                        if d <= Obstacles.REACH then
                            out[#out + 1] = { win = w, wk = wk, e = e, d = d, sqA = sq, sqB = nb }
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

-- Fenêtre contre laquelle le corps z du PNJ id (consigne e) est arrêté depuis still ms : ouverture (notée pour être
-- refermée) ou refus (voir l'en-tête). Une seule fenêtre par passage. Rend vrai si une fenêtre a été traitée.
function Obstacles.checkWindows(id, e, z, still, t)
    if still < Obstacles.STUCK_MS then return false end
    -- E18-T34 : corps mené vers la porte d'un détour (LK17-T01, Directives.detouring) : l'arrêt vient de la porte ou
    -- d'un pas du chemin, jamais d'une fenêtre à ouvrir (campagne MP du 2026-11-08,
    -- runs/20261108-012549-mp-a2dbaf99cf8b : fenêtre du foyer ouverte par un membre arrêté à sa porte).
    if LivingKnox.Directives.detouring(e) then return false end
    t = t or P.now()
    local px, py = z:getX(), z:getY()
    local near = Obstacles.windowsNear(px, py, math.floor(z:getZ()))
    -- LK04-T20 : fenêtre voisine ouverte par ce PNJ (ou geste en cours) : il va la franchir ; une autre fenêtre au
    -- contact (barricadée à côté) n'est pas une raison de refuser la consigne.
    local ownWay = false
    for _, c in ipairs(near) do
        local ow, wa = Obstacles.openWins[c.e.key], Obstacles.winActs[c.e.key]
        if (ow ~= nil and ow.id == id and not Obstacles.windowBlocks(c.win, c.wk)) or (wa ~= nil and wa.id == id) then
            ownWay = true
        end
    end
    for _, c in ipairs(near) do
        local cb = Obstacles.closedBy[c.e.key]
        local guarded = cb ~= nil and cb.id == id and t - cb.ms < Obstacles.CLOSE_GUARD_MS   -- refermée par lui
        if not guarded and Obstacles.windowBlocks(c.win, c.wk) and Obstacles.facing(z, c.e) then
            if Obstacles.winActs[c.e.key] ~= nil then return true end   -- geste en cours : bascule par windowActPass
            local act, why = Obstacles.decideWindow(id, c.win, c.wk, c.sqA, c.sqB, farSquare(c.e, px, py),
                e.lr == true, P.nearSquare(c.e, px, py, c.sqA, c.sqB))   -- LK04-T20 : dernier recours
            if act == "open" and Obstacles.startWindowAct(id, z, c.win, c.e, "open", t) then
                return true   -- LK04-T13 : ouverte à l'instant du geste (windowActPass)
            elseif act == "open" and Obstacles.openWindow(c.win, z) then
                P.count("windowsOpened")
                Obstacles.openWins[c.e.key] = { win = c.win, e = c.e, id = id, ms = t, seenMs = t,
                    from = P.sideOf(c.e, px, py) }
                LivingKnox.Log.info("npc %s: window %s opened (group %s)", id, c.e.key, tostring(Obstacles.groupOf(id)))
            elseif still >= Obstacles.REFUSE_MS and not P.climbing(z) and not ownWay
                and not Obstacles.onBlocked(id, e, z, c, why or "window did not open", "window", t) then
                P.count("windowsRefused")
                P.refuse(id, e, c, why or "window did not open", "window")
            end
            return true
        end
    end
    return false
end

-- Fenêtres ouvertes ici, à DETECT case du corps z, que franchir rapproche de l'étape (tx, ty) : bord noté dans seen,
-- pas de refermeture à ce passage (un PNJ arrive). Le passant ne change pas (LK19-T01 : seulement à l'enjambée,
-- climbedWindows).
function Obstacles.noteWindows(z, tx, ty, seen)
    local px, py, pz = z:getX(), z:getY(), math.floor(z:getZ())
    for key, rec in pairs(Obstacles.openWins) do
        local e = rec.e
        if e.z == pz and P.dist(px, py, e.mx, e.my) <= Obstacles.DETECT and Obstacles.onRoute(e, px, py, tx, ty) then
            seen[key] = true
        end
    end
end

-- LK19-T01 (ADR adr-fenetres-chacun-referme.md, D01) : le corps z du PNJ id escalade une fenêtre ouverte ici (état
-- climbwindow, à ALIGN case au plus du milieu de son bord, même niveau) : ce PNJ en devient le passant, côté de départ
-- noté. Seule façon de reprendre une fenêtre ouverte par un autre PNJ.
function Obstacles.climbedWindows(id, z, t)
    if z:getActionStateName() ~= "climbwindow" then return end
    local px, py, pz = z:getX(), z:getY(), math.floor(z:getZ())
    for key, rec in pairs(Obstacles.openWins) do
        local e = rec.e
        if rec.id ~= id and e.z == pz and P.dist(px, py, e.mx, e.my) <= Obstacles.ALIGN then
            LivingKnox.Log.info("npc %s: climbs the window %s opened by npc %s, closes it behind", id, key, tostring(rec.id))
            rec.id, rec.seenMs, rec.from = id, t, P.sideOf(e, px, py)
        end
    end
end

P.farSquare = farSquare
P.windowGesture = windowGesture
