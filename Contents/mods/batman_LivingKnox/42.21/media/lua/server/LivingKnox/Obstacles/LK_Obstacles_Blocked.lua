-- Living Knox : obstacles, passage bloqué : attendre ou forcer (LK04-T04).
-- LK20-T09 : sorti de LK_Obstacles.lua sans changement de comportement ; façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- passage bloqué (LK04-T04)
-- Fiche : deplacement.md, section « Passage bloqué : attendre ou forcer ». Un passage est bloqué quand le corps reste
-- au contact d'une porte ou d'une fenêtre refusée (REFUSE_MS). Comportement selon l'hostilité du type de groupe du PNJ
-- (blockedPolicy), avant le refus (qui donne un détour par une porte s'il y en a une, LK_Detour.lua, LK17-T01) :
--   - "detour" (colons, PNJ sans groupe) : refus aussitôt (détour, ou consigne close en échec : le cadre de décision
--     choisit autre chose) ;
--   - "wait" (neutres) : le corps attend WAIT_MS devant l'obstacle (geste ponctuel "wait", clip de repos : l'exécutant
--     le garde arrêté et tourné vers l'obstacle), passage repris dès que l'obstacle cède (porte ouverte ou
--     déverrouillée par quelqu'un, barricade retirée) ; refus à la fin de l'attente ;
--   - "force" (pillards) : le corps frappe l'obstacle (geste ponctuel "force", clip "strike" du combat en boucle) et
--     l'autorité applique un coup par boucle du clip (STRIKE_MS, premier à IMPACT_MS) avec le chemin vanilla d'un coup
--     d'arme sur un objet : IsoBarricade:WeaponHit (barricade du côté du corps, puis celle d'en face ; dégâts
--     DoorDamage x 5 sur la planche extérieure ou le métal, synchronisés par sync() sur le serveur, barricade retirée
--     pour tous à la dernière planche : J/iso/objects/IsoBarricade.java:416-457, 459-501) puis IsoDoor:WeaponHit pour
--     une porte verrouillée sans clé (dégâts DoorDamage x 2 x 0,5 : force 0 d'un zombie, plus un coup fort 1 fois sur
--     10 ; porte cassée à 0 : destroy(), planches, poignée et charnières au sol, porte retirée pour tous :
--     J/iso/objects/IsoDoor.java:1056-1176, 1178-1210). Planche retirée : sendObjectChange(STATE) en plus (comme
--     IsoBarricade.Thump, :375-379 : sync() ne redessine pas la barricade chez les clients, loadChange le fait :
--     :646-656). Porte d'un autre foyer non verrouillée : ouverte (setDoor) et refermée derrière comme les autres.
--     Arme : celle du PNJ (LivingKnox.Equipment.wantedOf), de mêlée, DoorDamage >= FORCE_MIN_DOOR_DAMAGE ; sans arme
--     capable (mains nues : DoorDamage 0, arme à feu), pas de forçage. Abandon (refus) après FORCE_GIVE_UP_MS.
-- Jamais forcé : le foyer d'un groupe AMI DES JOUEURS (hostilité du type < FRIENDLY_HOSTILITY : colons, neutres) sans
-- consigne explicite (Obstacles.orderForce, valable pour un "move" donné) ; porte double, de garage, construite
-- (IsoThumpable), cadenassée ou obstruée ; fenêtre seulement barricadée (jamais brisée, LK04-T03 : après la barricade,
-- règles des fenêtres). Pendant une attente ou un forçage : aucune autre décision d'obstacle pour ce PNJ ; une autre
-- consigne (cadre de décision, combat) l'interrompt. Interrupteur BLOCKED_RULES (coupé : refus aussitôt pour tous).
Obstacles.BLOCKED_RULES = true
Obstacles.FORCE_HOSTILITY = 75      -- hostilité du type au moins : force (pillards 90 ; même seuil que « tire le premier »)
Obstacles.WAIT_HOSTILITY = 30       -- au moins : attend (neutres 45) ; en deçà : refus aussitôt (colons 10)
Obstacles.FRIENDLY_HOSTILITY = 50   -- foyer d'un groupe dont le type est en deçà : ami des joueurs, jamais forcé
Obstacles.WAIT_MS = 15000           -- attente devant un passage bloqué
Obstacles.FORCE_GIVE_UP_MS = 240000 -- forçage abandonné après ce temps (refus ; une porte à la batte demande environ 2 min)
Obstacles.STRIKE_MS = 1250          -- boucle du clip de frappe (LivingKnox.Config.COMBAT.STRIKE_MS : 1,0 s à 0,80)
Obstacles.IMPACT_MS = 312           -- impact dans la boucle (AttackCollisionCheck à 25 % du clip)
Obstacles.FORCE_MIN_DOOR_DAMAGE = 1 -- DoorDamage minimal de l'arme (Sledgehammer 40, Axe 35, Crowbar 8, BaseballBat 5)
Obstacles.ACT_RENEW_MS = 3000       -- geste ponctuel renouvelé quand il lui reste moins que ce temps (Anim.ACT_MAX_MS)

-- Hostilité du type du groupe gid (LivingKnox.GroupTypes), ou nil.
function Obstacles.typeHostility(gid)
    local G, T = LivingKnox.Groups, LivingKnox.GroupTypes
    if gid == nil or G == nil or T == nil or not G.isReady() then return nil end
    local g = G.peek(gid)   -- LK13-T08 : lecture en place, seule
    local def = g and T.get(g.type) or nil
    return def and def.hostility or nil
end

-- Comportement du PNJ npcId devant un passage bloqué : "force", "wait" ou "detour" (voir l'en-tête de la section).
function Obstacles.blockedPolicy(npcId)
    if not Obstacles.BLOCKED_RULES then return "detour" end
    local h = Obstacles.typeHostility(Obstacles.groupOf(npcId))
    if type(h) ~= "number" then return "detour" end
    if h >= Obstacles.FORCE_HOSTILITY then return Obstacles.breachPolicy(npcId) end
    if h >= Obstacles.WAIT_HOSTILITY then return "wait" end
    return "detour"
end

-- Comportement "breach" (rôle casseur des pillards, décision du 2026-11-13) : un membre dont le rôle le permet force ;
-- les autres attendent (WAIT_MS) qu'un casseur du groupe, incarné à BREACH_RANGE cases au plus, ouvre le passage ;
-- sans casseur sur place (resté au foyer, mort, sans corps) : chacun force comme avant.
Obstacles.BREACH_RANGE = 20
function Obstacles.breachPolicy(npcId)
    local G, D = LivingKnox.Groups, LivingKnox.Decisions
    local gid, mid = nil, nil
    if G ~= nil and G.isReady() then gid, mid = G.findNpc(npcId) end
    local g = gid and G.peek(gid) or nil
    if g == nil or D == nil or D.allowedOf == nil then return "force" end
    local function breaks(m) return m ~= nil and m.role ~= nil and (D.allowedOf(g.type, m.role) or {}).breach == true end
    if breaks(g.members[mid]) then return "force" end
    local B = LivingKnox.Bodies
    local me = B and B.find(npcId) or nil
    if me == nil then return "force" end
    for omid, m in pairs(g.members) do
        local other = omid ~= mid and m.npc ~= nil and breaks(m) and B.find(m.npc) or nil
        if other ~= nil and math.abs(other:getX() - me:getX()) <= Obstacles.BREACH_RANGE
            and math.abs(other:getY() - me:getY()) <= Obstacles.BREACH_RANGE then
            return "wait"
        end
    end
    return "force"
end

-- Consigne explicite (autorité) : le PNJ npcId peut forcer le foyer d'un groupe ami des joueurs pendant le "move" v
-- (défaut : sa consigne "move" ouverte). Rend vrai, ou faux et une raison.
function Obstacles.orderForce(npcId, v)
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    local e = LivingKnox.Directives.entries[npcId]
    if v == nil and e ~= nil and e.op == LivingKnox.Directives.OP_MOVE and not e.done then v = e.v end
    if type(v) ~= "number" then return false, "no open move for npc " .. tostring(npcId) end
    Obstacles.forceOrders[npcId] = { v = v }
    LivingKnox.Log.info("npc %s: may force the home of a friendly group during move #%d (explicit order)", npcId, v)
    return true
end

local function ordered(id, e)
    local o = Obstacles.forceOrders[id]
    return o ~= nil and e ~= nil and o.v == e.v
end

-- Arme de forçage du PNJ npcId : son arme de mêlée (Equipment.wantedOf) si elle abîme une porte, sinon nil.
function Obstacles.forceWeapon(npcId)
    local E = LivingKnox.Equipment
    local spec = E ~= nil and E.wantedOf ~= nil and E.wantedOf(npcId) or nil
    local t = spec and spec.t
    if type(t) ~= "string" then return nil end
    local w = Obstacles.weapons[t]
    if w == nil then
        w = instanceItem(t)
        if w == nil or not instanceof(w, "HandWeapon") then w = false end
        Obstacles.weapons[t] = w
    end
    if w == false or w:isRanged() then return nil end
    local dd = w:getDoorDamage()
    if type(dd) ~= "number" or dd < Obstacles.FORCE_MIN_DOOR_DAMAGE then return nil end
    return w
end

-- Arme du forçage en cours rec (objet), ou nil.
local function weaponOf(rec)
    local w = Obstacles.weapons[rec.weapon]
    if w == nil or w == false then return nil end
    return w
end

-- Le PNJ npcId (consigne e) peut-il forcer l'obstacle c (what "door" ou "window", refusé pour why) ? Rend l'arme, ou
-- nil et la raison.
function Obstacles.canForce(npcId, e, c, what, why)
    local home
    if what == "window" then
        if not c.win:isBarricaded() then return nil, tostring(why) .. ": only a barricade is forced" end
        home = Obstacles.homeOf(c.sqA, c.sqB)
    else
        local d = c.door
        if P.isThumpable(d) then return nil, "built door never forced" end
        local kind = Obstacles.kindOf(d)
        if kind ~= "single" then return nil, kind .. " door not forced" end
        if d:isObstructed() then return nil, "obstructed door" end
        home = Obstacles.homeOf(c.sqA, c.sqB)
        local other = home ~= nil and home ~= Obstacles.groupOf(npcId)
        if not (d:isBarricaded() or Obstacles.isLocked(d) or other) then return nil, tostring(why) end
    end
    if home ~= nil and home ~= Obstacles.groupOf(npcId) and not ordered(npcId, e) then
        local h = Obstacles.typeHostility(home)
        if type(h) == "number" and h < Obstacles.FRIENDLY_HOSTILITY then
            return nil, "home of " .. home .. ", a group friendly to the players (no order to force it)"
        end
    end
    local w = Obstacles.forceWeapon(npcId)
    if w == nil then return nil, "no weapon able to damage a door" end
    return w
end

-- Geste ponctuel g ("force" ou "wait") du corps z du PNJ id tourné vers le bord de rec, posé ou renouvelé avant son
-- échéance (Anim.ACT_MAX_MS au plus ; until : fin voulue, facultative).
local function holdAct(id, z, rec, g, t, untilMs)
    local A = LivingKnox.Anim
    if A == nil or A.startAct == nil then return false end
    local act = A.actOf(id)
    if act == g and rec.actUntil ~= nil and rec.actUntil - t >= Obstacles.ACT_RENEW_MS then return true end
    local ms = A.ACT_MAX_MS or 10000
    if untilMs ~= nil then ms = math.max(1, math.min(ms, untilMs - t)) end
    local ok = A.startAct(id, g, ms, Obstacles.faceAngle(rec.e, z:getX(), z:getY()))
    if ok then rec.actUntil = t + ms end
    return ok == true
end

local function endHold(id, g)
    local A = LivingKnox.Anim
    if A ~= nil and A.endAct ~= nil then A.endAct(id, g) end
end

-- Passage bloqué du PNJ id (consigne e, corps z) au contact de l'obstacle c (what "door" ou "window", refusé pour why).
-- Rend vrai si le PNJ attend ou force (aucun refus maintenant), faux si l'appelant doit refuser la consigne.
function Obstacles.onBlocked(id, e, z, c, why, what, t)
    t = t or P.now()
    local f, w = Obstacles.forcing[id], Obstacles.waiting[id]
    if (f ~= nil and f.v == e.v) or (w ~= nil and w.v == e.v) then return true end   -- un obstacle à la fois
    local policy = Obstacles.blockedPolicy(id)
    local rec = { v = e.v, key = c.e.key, e = c.e, what = what, door = c.door, win = c.win, wk = c.wk, sqA = c.sqA,
        sqB = c.sqB, why = why, ms = t, from = P.sideOf(c.e, z:getX(), z:getY()) }
    if policy == "force" then
        local weapon, cause = Obstacles.canForce(id, e, c, what, why)
        if weapon == nil then
            P.count("forceRefused")
            LivingKnox.Log.info("npc %s: %s %s not forced: %s", id, what, c.e.key, tostring(cause))
            return false
        end
        rec.weapon, rec.nextMs, rec.hits, rec.planks = weapon:getFullType(), t + Obstacles.IMPACT_MS, 0, 0
        Obstacles.forcing[id] = rec
        holdAct(id, z, rec, "force", t)
        P.count("forcings")
        LivingKnox.Log.info("npc %s: forcing the %s %s (%s) with %s%s", id, what, c.e.key, tostring(why), rec.weapon,
            ordered(id, e) and " (explicit order)" or "")
        return true
    elseif policy == "wait" then
        rec.untilMs = t + Obstacles.WAIT_MS
        Obstacles.waiting[id] = rec
        holdAct(id, z, rec, "wait", t, rec.untilMs)
        P.count("waits")
        LivingKnox.Log.info("npc %s: waiting %d ms at the %s %s (%s)", id, Obstacles.WAIT_MS, what, c.e.key, tostring(why))
        return true
    end
    return false
end

-- Vrai si l'objet o (porte, fenêtre) n'est plus dans le monde.
local function gone(o)
    return o == nil or o:getSquare() == nil or o:getObjectIndex() == -1
end

-- Vrai si l'obstacle de rec ne bloque plus le PNJ id : porte retirée, ouverte et sans barricade, ou décision "open" ;
-- fenêtre retirée, ou qui ne l'arrête plus, ou décision "open".
local function passable(id, rec, z)
    local de = LivingKnox.Directives.entries[id]
    local trapped = de ~= nil and de.v == rec.v and de.lr == true   -- LK04-T20 : dernier recours de cette consigne
    local near = P.nearSquare(rec.e, z:getX(), z:getY(), rec.sqA, rec.sqB)
    if rec.what == "door" then
        local d = rec.door
        if gone(d) or d:isDestroyed() then return true end
        if d:isBarricaded() then return false end
        if Obstacles.isOpen(d) then return true end
        return Obstacles.decide(id, d, rec.sqA, rec.sqB, z, near, trapped) == "open"
    end
    local w = rec.win
    if gone(w) then return true end
    if w:isBarricaded() then return false end
    if not Obstacles.windowBlocks(w, rec.wk or "window") then return true end
    local px, py = z:getX(), z:getY()
    return Obstacles.decideWindow(id, w, "window", rec.sqA, rec.sqB, P.farSquare(rec.e, px, py), trapped, near)
        == "open"
end

-- Barricade à frapper sur l'objet o pour le corps z : celle de son côté, sinon celle d'en face (ordre de
-- IsoDoor.getThumpableFor, J/iso/objects/IsoDoor.java:1032-1046).
local function barricadeFor(o, z)
    local b = o:getBarricadeForCharacter(z)
    if b == nil then b = o:getBarricadeOppositeCharacter(z) end
    return b
end

-- Un coup du corps z (PNJ id) sur l'obstacle de rec, avec l'arme w. Rend "hit" ou "done" (porte non verrouillée
-- d'un autre foyer ouverte ici) ; nil et raison si l'obstacle ne se force plus.
local function strikeOnce(id, rec, z, w, t)
    local o = rec.what == "door" and rec.door or rec.win
    local b = barricadeFor(o, z)
    if b ~= nil then
        local n0 = b:getNumPlanks()
        b:WeaponHit(z, w)
        rec.hits = rec.hits + 1
        P.count("forceHits")
        local destroyed = b:isDestroyed()
        local n1 = destroyed and 0 or b:getNumPlanks()
        if n1 < n0 then
            rec.planks = rec.planks + (n0 - n1)
            local st = Obstacles.stats
            st.planksBroken = (st.planksBroken or 0) + (n0 - n1)
            LivingKnox.Log.info("npc %s: plank of the barricade on the %s %s broken (%d left)", id, rec.what, rec.key, n1)
            -- sync() de Damage ne redessine pas la barricade chez les clients : STATE comme IsoBarricade.Thump.
            if not destroyed and isServer() then b:sendObjectChange(IsoObjectChange.STATE) end
        end
        if destroyed then
            P.count("barricadesBroken")
            LivingKnox.Log.info("npc %s: barricade on the %s %s broken", id, rec.what, rec.key)
        end
        return "hit"
    end
    if rec.what ~= "door" then return nil, "window no longer barricaded" end
    local d = rec.door
    if Obstacles.isLocked(d) then
        d:WeaponHit(z, w)
        rec.hits = rec.hits + 1
        P.count("forceHits")
        if gone(d) or d:isDestroyed() then
            P.count("doorsBroken")
            LivingKnox.Log.info("npc %s: door %s broken", id, rec.key)
        end
        return "hit"
    end
    -- Porte non verrouillée et sans barricade d'un autre foyer : ouverte (refermée derrière lui, jamais verrouillée).
    local home = Obstacles.homeOf(rec.sqA, rec.sqB)
    if home ~= nil and home ~= Obstacles.groupOf(id) and not Obstacles.isOpen(d) then
        Obstacles.setDoor(d, true)
        P.count("opened")
        Obstacles.opened[rec.key] = { door = d, e = rec.e, id = id, ms = t, seenMs = t, from = rec.from, lock = false }
        LivingKnox.Log.info("npc %s: door %s of the home of %s opened by force", id, rec.key, home)
        return "done"
    end
    return nil, tostring(rec.why)
end

-- Fin d'une attente ou d'un forçage : geste ponctuel retiré ; refus de la consigne si why est donné.
local function release(id, rec, list, g, outcome, refuseWhy)
    list[id] = nil
    endHold(id, g)
    LivingKnox.Log.info("npc %s: %s at the %s %s ended after %d ms: %s", id, g == "force" and "forcing" or "waiting", rec.what,
        rec.key, P.now() - rec.ms, outcome)
    if refuseWhy ~= nil then
        local e = LivingKnox.Directives.entries[id]
        if e ~= nil and not e.done and e.v == rec.v then P.refuse(id, e, rec, refuseWhy, rec.what) end
    end
end

-- Raison d'arrêter une attente ou un forçage sans refus (consigne changée, corps parti), ou nil.
local function interrupted(id, rec, z)
    local e = LivingKnox.Directives.entries[id]
    if e == nil or e.done or e.v ~= rec.v or e.op ~= LivingKnox.Directives.OP_MOVE or e.suspended ~= nil then
        return "move no longer running"
    end
    if z == nil or not LivingKnox.Bodies.inWorld(z) then return "body gone" end
    return nil
end

-- À chaque passage : attentes et forçages en cours (voir l'en-tête de la section).
function Obstacles.blockedPass(t)
    for _, list in ipairs({ Obstacles.waiting, Obstacles.forcing }) do
        local ids = {}
        for id in pairs(list) do ids[#ids + 1] = id end
        table.sort(ids)   -- ordre déterministe ; table modifiée hors de pairs
        local forcing = list == Obstacles.forcing
        local g = forcing and "force" or "wait"
        for _, id in ipairs(ids) do
            local rec = list[id]
            local z = LivingKnox.Bodies.find(id)
            local stop = interrupted(id, rec, z)
            if stop ~= nil then
                release(id, rec, list, g, stop)
            elseif passable(id, rec, z) then
                P.count(forcing and "forced" or "waitResumed")
                release(id, rec, list, g, forcing and string.format("way open (%d hit(s), %d plank(s) broken)",
                    rec.hits, rec.planks) or "way open")
            elseif not forcing then
                if t >= rec.untilMs then
                    P.count("waitedOut")
                    release(id, rec, list, g, "nobody opened", rec.why .. " (waited " .. Obstacles.WAIT_MS .. " ms)")
                else
                    holdAct(id, z, rec, "wait", t, rec.untilMs)
                end
            elseif t - rec.ms >= Obstacles.FORCE_GIVE_UP_MS then
                P.count("forceGivenUp")
                release(id, rec, list, g, "given up", rec.why .. " (forcing given up after " .. rec.hits .. " hit(s))")
            else
                holdAct(id, z, rec, "force", t)
                local w = weaponOf(rec)
                if w == nil then
                    release(id, rec, list, g, "no weapon", rec.why)
                elseif t >= rec.nextMs then
                    rec.nextMs = math.max(rec.nextMs + Obstacles.STRIKE_MS, t + 1)
                    local res, why = strikeOnce(id, rec, z, w, t)
                    if res == nil then
                        release(id, rec, list, g, "cannot be forced", why)
                    elseif res == "done" then
                        P.count("forced")
                        release(id, rec, list, g, "door opened")
                    end
                end
            end
        end
    end
    local drop = {}
    for id, o in pairs(Obstacles.forceOrders) do
        local e = LivingKnox.Directives.entries[id]
        if e == nil or e.v ~= o.v or e.done then drop[#drop + 1] = id end
    end
    for _, id in ipairs(drop) do Obstacles.forceOrders[id] = nil end
end

P.gone = gone
