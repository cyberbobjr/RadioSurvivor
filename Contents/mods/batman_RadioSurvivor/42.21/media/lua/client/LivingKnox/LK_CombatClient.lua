-- Living Knox : mêlée des PNJ, côté machine qui simule le corps (LK06-T02). Fiche : docs/conception/combat.md.
-- Tourne sur un client MP et en solo (un serveur dédié n'exécute pas media/lua/client).
--
-- Ordres lus : solo = LivingKnox.Combat.orders (même machine) ; client MP = "combatState" reçus du serveur, PNJ par PNJ
-- (numéro d'envoi r croissant : un envoi plus ancien ou un doublon est ignoré ; { gone } retire l'ordre).
-- Pour chaque corps simulé ici (LivingKnox.ZombieGuard.simulatedHere) dont le geste affiché est "strike" (ou,
-- LK06-T09, le coup au sol "strikefloor" / "stomp" ; posé par l'autorité, LivingKnox.Anim) : premier impact IMPACT_MS
-- après l'apparition du geste (AttackCollisionCheck à 25 % du clip ; 33 % pour "stomp", View.IMPACT_MS), puis
-- un impact par boucle du clip (iv). À chaque impact, la cible (joueur de l'ordre) est cherchée ici :
-- (ou zombie de l'ordre, LK06-T04, retrouvé par son identifiant réseau zo) vivante, même niveau, à la portée de
-- l'ordre (rc) -> touche rapportée à l'autorité ("combatHit" { id, c, n, u, x, y,
-- z }, appel direct de Combat.onHit en solo) ; sinon coup manqué, rien n'est envoyé (LK05-T18, client MP : zombie
-- introuvable ici car simulé par un autre client = touche rapportée quand même, champ nf, jugée par l'autorité sur ses
-- copies ; coups manqués journalisés au plus une fois par DIAG_MS et par raison). n croît sur cette machine pour
-- chaque ordre c. L'autorité contrôle tout de nouveau et applique les dommages une seule fois : ce module ne fait
-- que minuter le geste.
-- Tir (LK06-T03) : un ordre de tir (m = "ranged") est minuté de la même façon sur le geste "shoot" (un coup de feu
-- par boucle du clip de tir) ; le rapport est le même message. Le serveur retire la cartouche, décide de la touche
-- et renvoie à chaque client proche l'entrée du coup de feu ("combatShot" { s = { k, npc, o, x, y, z, snd } }, appel
-- direct de View.onShot en solo). View.onShot JOUE alors, une seule fois par clé k (livraison répétée ignorée) :
--   - le son vanilla de l'arme (SwingSound, par exemple M9Shoot) sur l'émetteur de la copie locale du corps
--     (CharacterSoundEmitter.playSoundImpl(String, IsoObject), seule surcharge à deux arguments, aucun paquet), sinon
--     sur un émetteur libre à la position du tir (playSoundImpl(String, boolean, IsoObject)) ; comme le cri d'alerte
--     (LK_AlertView.lua) ;
--   - l'éclair : lumière temporaire comme celle du tir vanilla (EffectsManager.startMuzzleFlash,
--     J/EffectsManager.java:45-58 : IsoLightSource(x, y, z, 0,8 i, 0,8 i, 0,6 i, rayon 18, vie 6), i = max(nuit x 0,8,
--     0,2)), posée par getCell():addLamppost ; une lumière à durée de vie est passée au moteur d'éclairage puis
--     retirée de la liste (J/iso/LightingJNI.java:275-280). La flamme 3D au bout du canon (modèle de l'arme) n'est pas
--     accessible depuis Lua (EffectsManager non exposé).
-- Sons de la mêlée (LK06-T11, fiche combat.md, section « Sons de la mêlée ») :
--   - élan : chaque machine qui connaît l'ordre de mêlée (client proche ou solo) et voit un geste de frappe sur une
--     copie du corps joue l'élan au début de chaque boucle du clip (apparition du geste, puis toutes les iv ms), comme
--     l'événement PlaySwingSound au début des nœuds de frappe vanilla : nom sw de l'ordre (SwingSound de l'arme,
--     "AttackShove" à mains nues), "AttackStomp" pour le geste "stomp" ; aucun message, coup manqué compris ;
--   - impact : entrée "combatMelee" { m = { k, npc, o, x, y, z, sw, hit } } envoyée par l'autorité pour chaque touche
--     acceptée (appel direct de View.onMelee en solo), jouée une seule fois par clé k : l'élan en cours est arrêté
--     (stopSoundByName, comme J/CombatManager.java:782) puis l'impact est joué sur l'émetteur de la copie locale du
--     corps (playSoundImpl(String, IsoObject)), sinon sur un émetteur libre (playSoundImpl(String, boolean,
--     IsoObject)). Aucun bruit pour les zombies.
-- Sons et mort du corps (LK06-T13, fiche combat.md, section « Sons et mort du corps ») : le moteur n'arrête ni ne
-- fait plus avancer l'émetteur d'un zombie qui meurt ou quitte le monde (J/iso/objects/IsoDeadBody.java:358-361 : un
-- seul tick ; IsoZombie.removeFromWorld, J/characters/IsoZombie.java:3554-3580, n'arrête que BurningFlesh ; l'arrêt
-- différé de 5 s n'existe que pour un joueur ou un animal, J/characters/IsoPlayer.java:1525-1540). Donc :
--   - élan et impact ne sont joués que sur un corps vivant, debout et connu ici (View.bodyAlive) ; un impact reçu
--     pour un corps mort, à terre, retiré ou absent n'est joué nulle part (aucun émetteur libre) ;
--   - chaque son lancé sur l'émetteur d'un corps (élan, impact, coup de feu) est noté par PNJ (View.bodySounds) ;
--     à la mort du corps (OnZombieDead sur cette machine), ou au premier passage où il n'est plus le corps vivant
--     et debout connu du PNJ, ces sons sont arrêtés par leur nom (stopSoundByName, local, J/fmod/fmod/
--     FMODSoundEmitter.java:166-186 : arrêt FMOD immédiat, sans tick de l'émetteur), comme le vanilla arrête l'élan
--     à l'impact. Un coup normal ne change pas : la note est oubliée SOUND_HOLD_MS après le dernier son.
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_ZombieGuard"
require "LivingKnox/LK_Anim"

local View = LivingKnox.CombatView or {}
LivingKnox.CombatView = View

View.MODULE = "LivingKnox"
View.CMD_STATE = "combatState"
View.CMD_HIT = "combatHit"
View.CMD_SHOT = "combatShot"
View.CMD_MELEE = "combatMelee"   -- LK06-T11
View.STOMP_SOUND = "AttackStomp"   -- élan du piétinement (J/ai/states/SwipeStatePlayer.java:219-220)
View.MAX_SEEN = 64           -- clés de coups de feu retenues (livraison répétée)
View.FLASH_RADIUS = 18       -- EffectsManager.startMuzzleFlash
View.FLASH_LIFE = 6
-- Gestes minutés selon le mode de l'ordre : tir "shoot" ; mêlée "strike", et coup au sol "strikefloor" ou "stomp"
-- (LK06-T09, même boucle de 1,25 s).
View.TIMED_GESTURES = { ranged = { shoot = true }, melee = { strike = true, strikefloor = true, stomp = true } }
-- Impact dans la boucle propre à un geste (sinon im de l'ordre) : piétinement, AttackCollisionCheck à 33 % du clip
-- Bob_AttackFloorStamp (StompDefault.xml) joué en 1,25 s par nos nœuds (LK06-T09).
View.IMPACT_MS = { stomp = 412 }
View.PASS_EVERY = 2          -- images entre deux passages (impact à une image près à 30 i/s)
View.remote = View.remote or { r = {}, d = {} }   -- client MP : npcId -> dernier r reçu, ordre reçu
View.swings = View.swings or {}                   -- npcId -> { c, next } frappe en cours sur cette machine
View.swingSounds = View.swingSounds or {}         -- npcId -> { c, g, next } élan joué ici (LK06-T11)
View.bodySounds = View.bodySounds or {}           -- npcId -> { z, names, t } sons lancés sur le corps (LK06-T13)
View.SOUND_HOLD_MS = 5000    -- au-delà, les sons notés sont finis : note oubliée sans arrêt (LK06-T13)
View.counters = View.counters or {}               -- npcId -> { c, n } numéro du dernier rapport de l'ordre c
View.state = View.state or { ticks = 0 }
View.stats = View.stats or { received = 0, older = 0, swings = 0, reported = 0, missed = 0 }
for _, k in ipairs({ "shotsReceived", "shotsPlayed", "shotsDuplicate", "shotsRefused", "onBody", "free", "flashes" }) do
    View.stats[k] = View.stats[k] or 0   -- LK06-T03
end
for _, k in ipairs({ "meleeSwings", "meleeReceived", "meleeImpacts", "meleeDuplicate", "meleeRefused" }) do
    View.stats[k] = View.stats[k] or 0   -- LK06-T11
end
for _, k in ipairs({ "meleeNoBody", "bodySoundsStopped", "bodySoundStops" }) do
    View.stats[k] = View.stats[k] or 0   -- LK06-T13
end
View.lastMelee = View.lastMelee or {}   -- derniers noms joués { sw, hit } (suites en jeu)
View.seen = View.seen or {}     -- clé de coup de feu -> vrai
View.order = View.order or {}   -- clés dans l'ordre d'arrivée (MAX_SEEN au plus)

local function now() return getTimestampMs() end

local function count(name)
    View.stats[name] = (View.stats[name] or 0) + 1
end

-- LK06-T13 : vrai si le corps z peut faire entendre un geste de combat : vivant et debout (un mort, ou un corps au
-- sol, ne frappe ni ne tire).
function View.bodyAlive(z)
    return z ~= nil and not z:isDead() and not z:isOnFloor()
end

-- LK06-T13 : arrête par leur nom les sons notés pour le PNJ id sur l'émetteur de son corps, puis oublie la note.
-- Rend le nombre de noms arrêtés.
function View.stopBodySounds(id)
    local rec = View.bodySounds[id]
    if rec == nil then return 0 end
    View.bodySounds[id] = nil
    local em = rec.z:getEmitter()
    if em == nil then return 0 end
    local n = 0
    for name in pairs(rec.names) do
        em:stopSoundByName(name)
        n = n + 1
    end
    count("bodySoundsStopped")
    View.stats.bodySoundStops = View.stats.bodySoundStops + n
    return n
end

-- LK06-T13 : joue name sur l'émetteur du corps z du PNJ id (CharacterSoundEmitter.playSoundImpl(String, IsoObject),
-- seule surcharge à deux arguments, local) et note le nom. Rend l'identifiant du son.
local function playOnBody(id, z, name)
    local rec = View.bodySounds[id]
    if rec ~= nil and not rawequal(rec.z, z) then
        View.stopBodySounds(id)   -- autre corps pour le même PNJ : l'ancien ne garde rien de nous
        rec = nil
    end
    if rec == nil then
        rec = { z = z, names = {} }
        View.bodySounds[id] = rec
    end
    rec.names[name] = true
    rec.t = now()
    return z:getEmitter():playSoundImpl(name, nil)
end

-- LK06-T13 : passage sur les notes : corps qui n'est plus le corps vivant et debout connu du PNJ -> sons arrêtés ;
-- note plus ancienne que SOUND_HOLD_MS -> oubliée. Rend le nombre de PNJ dont les sons ont été arrêtés.
function View.sweepBodySounds(known, t)
    local stop, forget = {}, {}
    for id, rec in pairs(View.bodySounds) do   -- relevé d'abord : la table n'est pas modifiée pendant pairs
        if not rawequal(known[id], rec.z) or not View.bodyAlive(rec.z) then
            stop[#stop + 1] = id
        elseif t - rec.t > View.SOUND_HOLD_MS then
            forget[#forget + 1] = id
        end
    end
    for _, id in ipairs(stop) do View.stopBodySounds(id) end
    for _, id in ipairs(forget) do View.bodySounds[id] = nil end
    return #stop
end

-- LK06-T13 : OnZombieDead sur cette machine (solo : Kill ou die du corps ; client MP : mort reçue du serveur) : les
-- sons notés pour ce corps sont arrêtés à l'instant de la mort. Rend le nombre de PNJ concernés.
function View.onZombieDead(zb)
    if zb == nil then return 0 end
    local ids = {}
    for id, rec in pairs(View.bodySounds) do
        if rawequal(rec.z, zb) then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do View.stopBodySounds(id) end
    return #ids
end

-- Ordres connus ici : { [npcId] = { c, u, k, m, rc, iv, im, zo, sw } } (zo : identifiant réseau d'une cible zombie,
-- LK06-T04 ; zt : l'objet zombie, en solo seulement ; sw : élan d'un ordre de mêlée, LK06-T11).
function View.orders()
    if LivingKnox.isAuthority() then
        local C = LivingKnox.Combat
        if C == nil or C.orders == nil then return {} end
        local out = {}
        for id, o in pairs(C.orders) do
            out[id] = { c = o.c, u = o.u, k = o.k, m = o.m, rc = o.reach, iv = o.iv, im = o.im, zo = o.zo, zt = o.zt,
                sw = o.sw }
        end
        return out
    end
    return View.remote.d
end

local function validOrder(e)
    return type(e) == "table" and type(e.c) == "number" and type(e.u) == "string" and type(e.rc) == "number"
        and type(e.iv) == "number" and e.iv > 0 and type(e.im) == "number"
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE or not isClient() then return end
    if command == View.CMD_SHOT then
        if type(args) == "table" then View.onShot(args.s) end
        return
    end
    if command == View.CMD_MELEE then
        if type(args) == "table" then View.onMelee(args.m) end
        return
    end
    if command ~= View.CMD_STATE then return end
    if type(args) ~= "table" or type(args.d) ~= "table" then return end
    local rem = View.remote
    for id, e in pairs(args.d) do
        if type(id) == "string" and type(e) == "table" and type(e.r) == "number" then
            count("received")
            local last = rem.r[id]
            if last ~= nil and e.r <= last then
                count("older")
            else
                rem.r[id] = e.r
                if e.gone then
                    rem.d[id] = nil
                elseif validOrder(e) then
                    rem.d[id] = e
                end
            end
        end
    end
end

-- Joueur de compte name connu de cette machine (client MP : joueurs connectés ; solo : joueurs locaux), ou nil.
function View.playerByName(name)
    local list = getOnlinePlayers()
    if list ~= nil then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil and p:getUsername() == name then return p end
        end
    end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p ~= nil and p:getUsername() == name then return p end
    end
    return nil
end

local function nextNumber(id, c)
    local k = View.counters[id]
    if k == nil or k.c ~= c then
        k = { c = c, n = 0 }
        View.counters[id] = k
    end
    k.n = k.n + 1
    return k.n
end

-- Zombie d'identifiant réseau o dans la cellule de cette machine, ou nil (LK06-T04).
function View.zombieByOnlineId(o)
    if type(o) ~= "number" or o < 0 then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local list = cell:getZombieList()
    for i = 0, list:size() - 1 do
        local zb = list:get(i)
        if zb ~= nil and zb:getOnlineID() == o then return zb end
    end
    return nil
end

-- Cible de l'ordre o sur cette machine : joueur de compte o.u, ou zombie (LK06-T04 : objet de l'autorité en solo,
-- sinon copie locale retrouvée par son identifiant réseau zo). Rend l'objet ou nil.
function View.targetOf(o)
    if o.k == "zombie" then
        if o.zt ~= nil then return o.zt end
        return View.zombieByOnlineId(o.zo)
    end
    return View.playerByName(o.u)
end

-- Coup manqué ici, journalisé au plus une fois par DIAG_MS et par (PNJ, raison) : sans cela, un ordre dont aucun coup
-- n'est jamais rapporté (cible introuvable sur cette machine, copie éloignée) ne laisse aucune trace.
View.DIAG_MS = 15000
View.diagAt = View.diagAt or {}
local function missed(id, o, reason, detail)
    count("missed")
    local key = tostring(id) .. "|" .. reason
    local t = now()
    local last = View.diagAt[key]
    if last ~= nil and t - last < View.DIAG_MS then return false end
    View.diagAt[key] = t
    LivingKnox.Log.info("npc %s: %s #%d against %s missed here: %s%s", tostring(id), tostring(o.m), o.c, tostring(o.u),
        reason, detail and (" (" .. detail .. ")") or "")
    return false
end

-- Impact d'une frappe du PNJ id (corps z, ordre o) : touche rapportée si la cible est à portée. Rend vrai si envoyée.
function View.impact(id, z, o)
    local p = View.targetOf(o)
    local blind = false
    if p == nil and o.k == "zombie" and isClient() then
        -- LK05-T18 (campagne MP du 2026-10-15, camp) : zombie simulé par un AUTRE client et absent de cette cellule
        -- (une copie distante sans paquet depuis 5 s est retirée, J/characters/IsoZombie.java:2718-2722 ; le serveur
        -- ne relaie un zombie qu'à la réception d'un paquet de son propriétaire, J/popman/NetworkZombiePacker.java:
        -- 182-189). Ses attaques sur le PNJ sont décidées par l'autorité sur SES copies (LK_Zombies) : la touche est
        -- rapportée quand même (nf), l'autorité la juge sur ses copies (portée, ligne de coup, cadence), comme les
        -- attaques du zombie. Avant : aucun coup jamais rapporté, PNJ tués sans riposte.
        blind = true
        missed(id, o, "target not found, reported to the authority", "zo " .. tostring(o.zo))
        View.stats.missed = View.stats.missed - 1
        count("blind")
    elseif p == nil then
        return missed(id, o, "target not found", o.k == "zombie" and ("zo " .. tostring(o.zo)) or nil)
    else
        if p:isDead() then return missed(id, o, "target dead") end
        if math.floor(p:getZ()) ~= math.floor(z:getZ()) then return missed(id, o, "other level") end
        local dx, dy = p:getX() - z:getX(), p:getY() - z:getY()
        if dx * dx + dy * dy > o.rc * o.rc then
            return missed(id, o, "out of reach", string.format("%.1f squares, body %.1f,%.1f, target %.1f,%.1f",
                math.sqrt(dx * dx + dy * dy), z:getX(), z:getY(), p:getX(), p:getY()))
        end
    end
    local args = { id = id, c = o.c, n = nextNumber(id, o.c), u = o.u, x = z:getX(), y = z:getY(), z = z:getZ(),
        nf = blind or nil }
    count("reported")
    if LivingKnox.isAuthority() then
        local C = LivingKnox.Combat
        if C == nil then return false end
        C.onHit(getPlayer(), args)
        return true
    end
    local player = getPlayer()
    if player == nil then return false end
    sendClientCommand(player, View.MODULE, View.CMD_HIT, args)
    return true
end

-- LK06-T11 : nom de l'élan de l'ordre de mêlée o pour le geste affiché g ("AttackStomp" pour le piétinement, sinon
-- sw de l'ordre), ou nil.
function View.swingNameOf(o, g)
    if g == "stomp" then return View.STOMP_SOUND end
    if type(o.sw) == "string" and o.sw:match("^[%w_]+$") then return o.sw end
    return nil
end

-- LK06-T11 : élan du PNJ id (corps z, ordre de mêlée o, geste affiché g) au début de chaque boucle du clip : à
-- l'apparition du geste (ou à un changement d'ordre ou de geste), puis toutes les iv ms. Rend vrai si joué.
local function playSwing(id, z, o, g, t)
    local s = View.swingSounds[id]
    if s ~= nil and s.c == o.c and s.g == g then
        if t < s.next then return false end
        s.next = s.next + o.iv
        if s.next <= t then s.next = t + o.iv end   -- passage en retard : pas de rafale de rattrapage
    else
        View.swingSounds[id] = { c = o.c, g = g, next = t + o.iv }
    end
    local name = View.swingNameOf(o, g)
    if name == nil then return false end
    playOnBody(id, z, name)   -- CharacterSoundEmitter : seule surcharge à deux arguments, local
    count("meleeSwings")
    View.lastMelee.sw = name
    return true
end

-- Passage : frappes minutées sur les corps simulés ici ; élan des frappes vues ici (LK06-T11). Rend le nombre
-- d'impacts traités.
function View.pass()
    local A = LivingKnox.Anim
    local G = LivingKnox.ZombieGuard
    local known = A.knownBodies()
    local orders = View.orders()
    local t = now()
    local n = 0
    View.sweepBodySounds(known, t)   -- LK06-T13
    for id in pairs(View.swings) do
        if orders[id] == nil then View.swings[id] = nil end
    end
    for id in pairs(View.swingSounds) do
        if orders[id] == nil then View.swingSounds[id] = nil end
    end
    for id, o in pairs(orders) do
        local z = known[id]
        local shown = z ~= nil and A.shownOf(id) or nil
        local timed = View.TIMED_GESTURES[o.m] or View.TIMED_GESTURES.melee
        if View.bodyAlive(z) and o.m ~= "ranged" and View.TIMED_GESTURES.melee[shown] then
            playSwing(id, z, o, shown, t)
        else
            View.swingSounds[id] = nil
        end
        if z == nil or z:isDead() or not G.simulatedHere(z) or not timed[shown] then
            View.swings[id] = nil
        else
            local sw = View.swings[id]
            if sw == nil or sw.c ~= o.c then
                sw = { c = o.c, next = t + (View.IMPACT_MS[shown] or o.im) }
                View.swings[id] = sw
                count("swings")
            end
            if t >= sw.next then
                sw.next = sw.next + o.iv
                if sw.next <= t then sw.next = t + o.iv end   -- passage en retard : pas de rafale de rattrapage
                View.impact(id, z, o)
                n = n + 1
            end
        end
    end
    return n
end

-- ---------------------------------------------------------------- coups de feu (LK06-T03)

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function remember(k)
    View.seen[k] = true
    View.order[#View.order + 1] = k
    if #View.order > View.MAX_SEEN then View.seen[table.remove(View.order, 1)] = nil end
end

-- Éclair d'un coup de feu à (x, y, z) : lumière temporaire (voir l'en-tête). Rend vrai si posée.
function View.flash(x, y, z)
    local cell = getCell()
    if cell == nil or IsoLightSource == nil then return false end
    local night = 0
    local gt = getGameTime()
    if gt ~= nil then night = gt:getNight() or 0 end
    local i = math.max(night * 0.8, 0.2)
    local light = IsoLightSource.new(math.floor(x), math.floor(y), math.floor(z), 0.8 * i, 0.8 * i, 0.6 * i,
        View.FLASH_RADIUS, View.FLASH_LIFE)
    if light == nil then return false end
    cell:addLamppost(light)
    count("flashes")
    return true
end

-- Coup de feu reçu de l'autorité (table e = { k, npc, o, x, y, z, snd }) : son de l'arme et éclair, une seule fois par
-- clé. Rend vrai s'il a été joué.
function View.onShot(e)
    if type(e) ~= "table" or type(e.k) ~= "string" or type(e.snd) ~= "string" or not e.snd:match("^[%w_]+$")
        or not finite(e.x) or not finite(e.y) or not finite(e.z) then
        count("shotsRefused")
        return false
    end
    count("shotsReceived")
    if View.seen[e.k] then
        count("shotsDuplicate")
        return false
    end
    remember(e.k)
    local A = LivingKnox.Anim
    local z = (A ~= nil and type(e.npc) == "string") and A.knownBodies()[e.npc] or nil
    if View.bodyAlive(z) then
        playOnBody(e.npc, z, e.snd)   -- LK06-T13 : arrêté si le tireur meurt
        count("onBody")
    else
        local w = getWorld and getWorld() or nil
        local em = w ~= nil and w:getFreeEmitter(e.x, e.y, e.z) or nil
        if em ~= nil then
            em:playSoundImpl(e.snd, false, nil)
            count("free")
        end
    end
    View.flash(e.x, e.y, e.z)
    count("shotsPlayed")
    return true
end

-- LK06-T11 : touche de mêlée acceptée par l'autorité (table e = { k, npc, o, x, y, z, sw, hit }) : élan en cours arrêté
-- puis impact joué, une seule fois par clé. Rend vrai s'il a été joué.
function View.onMelee(e)
    if type(e) ~= "table" or type(e.k) ~= "string" or type(e.hit) ~= "string" or not e.hit:match("^[%w_]+$")
        or (e.sw ~= nil and (type(e.sw) ~= "string" or not e.sw:match("^[%w_]+$")))
        or not finite(e.x) or not finite(e.y) or not finite(e.z) then
        count("meleeRefused")
        return false
    end
    count("meleeReceived")
    if View.seen[e.k] then
        count("meleeDuplicate")
        return false
    end
    remember(e.k)
    local A = LivingKnox.Anim
    local z = (A ~= nil and type(e.npc) == "string") and A.knownBodies()[e.npc] or nil
    if not View.bodyAlive(z) then
        count("meleeNoBody")   -- LK06-T13 : corps mort, à terre, retiré ou absent ici : aucun impact, nulle part
        return false
    end
    if e.sw ~= nil then z:getEmitter():stopSoundByName(e.sw) end
    playOnBody(e.npc, z, e.hit)
    count("onBody")
    count("meleeImpacts")
    View.lastMelee.hit = e.hit
    return true
end

function View.tick()
    local st = View.state
    st.ticks = st.ticks + 1
    if st.ticks < View.PASS_EVERY then return end
    st.ticks = 0
    if getCell() == nil or LivingKnox.Anim == nil then return end
    View.pass()
end

-- Réinitialisation (tests).
function View.reset()
    View.remote = { r = {}, d = {} }
    View.swings, View.counters, View.swingSounds, View.bodySounds = {}, {}, {}, {}
    View.seen, View.order = {}, {}
    View.state = { ticks = 0 }
end

local function onTick()
    LivingKnox.CombatView.tick()
end

LivingKnox.subscribe("OnTick", "CombatView.tick", onTick)

local function onZombieDead(zb)   -- LK06-T13
    LivingKnox.CombatView.onZombieDead(zb)
end

LivingKnox.subscribe("OnZombieDead", "CombatView.onZombieDead", onZombieDead)

if isClient() then
    local function onServerCommand(module, command, args)
        LivingKnox.CombatView.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "CombatView.onServerCommand", onServerCommand)
end

return View
