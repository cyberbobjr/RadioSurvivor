-- Living Knox : perception des PNJ (vue, ouïe, lumière), LK05-T01. Fiche : docs/annexes/conception/perception.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Deux moitiés dans un seul fichier partagé (media/lua/shared : chargé par le solo, le client MP et le serveur) :
--   1. Calcul, sur la machine qui SIMULE le corps (client MP propriétaire, ou le jeu en solo), appelé par
--      LivingKnox.Executor à chacun de ses passages (Senses.scan). Raison : la lumière d'une case n'est calculée que
--      par un client (éclairage par joueur local, J/iso/IsoGridSquare.java:8896-8902) et le corps n'est à jour que
--      chez son simulateur ; un serveur dédié n'a pas de joueur local. Rien n'est décidé ici : seules des mesures
--      (ce que le PNJ voit et entend) sortent.
--   2. Mémoire de l'autorité (serveur MP ou solo) : le résumé voyage dans le rapport d'état "bodyReport" existant
--      (champ facultatif sen, LK03-T02, server/LivingKnox/LK_Reports.lua), contrôlé avec lui (propriétaire, bail,
--      ordre, cadence) ; l'autorité en garde la dernière valeur par PNJ après un filtre de plausibilité
--      (Senses.accept). Lecture : Senses.perceived(npcId). Aucune référence aux modules serveur au chargement.
--
-- Modèle (chiffres dans Senses.MODEL, justification dans la fiche) : portée de vue = 20 cases x lumière x météo x
-- ligne de vue x étages x champ de vision x posture et allure de la cible x vigilance du PNJ ; cible dans cette
-- portée : attention a qui monte de GAIN_MIN + GAIN_SPAN x (1 - d / portée) par seconde, « vue » à 1 ; hors de vue,
-- a baisse de DECAY par seconde. Ouïe : rayon du bruit de la cible (allure, bruits du monde qu'elle émet) x
-- vigilance / murs ; aucune ligne de vue. Déterministe : aucun tirage ; mêmes entrées (mesures et durée dt) ->
-- même résultat. Coût borné par passage (Senses.BUDGET, compteurs Senses.stats).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local Senses = LivingKnox.Senses or {}
LivingKnox.Senses = Senses

Senses.VERSION = 1   -- champ v du résumé (jamais vide sur le réseau : une table vide arrive en nil)

Senses.MODEL = {
    SIGHT = 20,             -- cases : vue de jour, cible debout qui marche, en face (vision max d'un zombie,
                            -- J/characters/IsoZombie.java:4638-4646, bornée 10..20)
    SIGHT_MAX = 30,         -- cases : plafond de la portée de vue
    LIGHT_MIN = 0.25,       -- facteur de lumière = LIGHT_MIN + (1 - LIGHT_MIN) x niveau de lumière (0..1)
    TORCH_LIGHT = 0.9,      -- cible qui tient une lumière allumée : niveau au moins égal
    FOG = 0.35, RAIN = 0.125, WEATHER_MIN = 0.3,   -- vanilla : 7 et 2,5 cases sur 20 (IsoZombie.java:4639-4640)
    LOS = { Clear = 1, ClearThroughOpenDoor = 1, ClearThroughWindow = 0.8, ClearThroughClosedDoor = 0.8,
        Blocked = 0 },      -- résultat de LosUtil.lineClear (J/iso/LosUtil.java:648-653)
    LEVEL = 1,              -- vue : portée / (1 + LEVEL x écart d'étages)
    FOV = { { 0.5, 1 }, { 0, 0.6 }, { -0.5, 0.25 } },   -- { cosinus minimal, facteur } ; en dessous : 0 (dos)
    NEAR = 1.5, NEAR_FOV = 0.6,   -- à NEAR case ou moins, champ de vision au moins NEAR_FOV (contact)
    SNEAK = 0.5,            -- joueur accroupi (isSneaking)
    CRAWL = 0.6,            -- zombie rampant (isCrawling)
    MOTION = { still = 0.7, walk = 1, run = 1.3, sprint = 1.5 },   -- vanilla 0,8 / 1 / 1,5 / 2 (IsoZombie.java:1774-1781)
    NPC_FLOOR = 0.5,        -- PNJ au sol ou rampant : portée de vue
    VIGIL = { sleep = { see = 0, hear = 0.35 }, busy = { see = 0.75, hear = 0.8 }, rest = { see = 1, hear = 1 },
        guard = { see = 1.3, hear = 1.25 } },   -- I2.2 : endormi << occupé < repos < garde
    GAIN_MIN = 0.25, GAIN_SPAN = 2.0,   -- attention gagnée par seconde dans la portée
    DECAY = 0.25,           -- attention perdue par seconde hors de vue (souvenir de 4 s)
    MAX_DT = 1.0,           -- secondes : durée d'un pas bornée (passage manqué, pause)
    NOISE = { player = { still = 0, walk = 5, run = 10, sprint = 15 }, zombie = { still = 2, walk = 5, run = 8,
        sprint = 8 } },     -- cases : bruit propre de la cible selon son allure
    SNEAK_NOISE = 0.3,      -- joueur accroupi : bruit propre
    LEVEL_HEAR = 3,         -- ouïe : un étage compte pour 3 cases (WorldSoundManager.java:230)
    WALL = { same = 1, other = 1.2, outside = 1.68 },   -- rayon divisé : autre pièce, intérieur/extérieur
                                                        -- (WorldSoundManager.java:232-244 : x1,2 puis x1,4)
    HEAR_MS = 3000,         -- ms : une cible entendue le reste ce temps (dernière position connue)
    SOUND_MS = 2000,        -- ms : un bruit du monde compte ce temps (vanilla : 16 mises à jour)
    SPEED = { walk = 0.5, run = 3.5, sprint = 5.5 },   -- cases/s : allure déduite du déplacement mesuré
}

Senses.BUDGET = {
    NPCS = 4,               -- PNJ examinés par passage de l'exécutant (tour à tour)
    TARGETS = 24,           -- cibles examinées par PNJ et par passage (les plus proches)
    LOS = 32,               -- appels LosUtil.lineClear par passage
    ZOMBIE_SCAN = 1000,     -- zombies de la cellule parcourus par passage (curseur au-delà)
    RANGE = 30,             -- cases : rayon des cibles candidates (au plus SIGHT_MAX)
    LEVELS = 2,             -- étages d'écart au plus pour une cible candidate
    PLAYERS = 4, ZOMBIES = 6, NOISES = 3,   -- entrées au plus dans un résumé
    THUMPS = 4,             -- LK06-T11 : fenêtres frappées par les zombies simulés ici, au plus par rapport
    THUMP_RANGE = 30,       -- LK06-T11 : cases (x et y) autour d'un corps de PNJ présent ici : zombies examinés
    SOUNDS = 32,            -- bruits du monde retenus (anneau)
}

-- Autorité : bornes du contrôle des résumés reçus (Senses.validate, Senses.accept).
Senses.CHECK = {
    COUNT_MAX = 1000,       -- zombies perçus au plus (nz)
    NOISE_MAX = 300,        -- cases : rayon d'un bruit rapporté
    HEAR_MAX = 150,         -- cases : distance d'une cible entendue (bruit du monde fort) au corps
    SLACK = 6,              -- cases : écart toléré (copie du serveur, MAX_GAP de LK03-T02)
    SEEN_LEVELS = 2,        -- étages d'écart au plus pour une cible vue
    NAME_MAX = 64,
    STALE_MS = 15000,       -- résumé plus vieux : marqué stale (le corps ne rapporte plus)
    KNOWN_MS = 100,         -- serveur : liste des zombies vivants relue au plus à cet intervalle (Senses.accept)
    THUMP_REACH = 4,        -- cases : copie du serveur du zombie au plus à cette distance du milieu du bord de la
                            -- fenêtre rapportée (le propriétaire lâche sa cible au-delà de 3 cases,
                            -- J/characters/IsoZombie.java:738-746 ; + 1 case de retard de la copie du serveur)
    THUMP_MS = 5000,        -- ms : fenêtre frappée rapportée encore crue (rapport renouvelé toutes les THUMP_REFRESH_MS)
    THUMP_REFRESH_MS = 2000, -- ms : client, rapport des coups renvoyé à cet intervalle tant qu'il n'est pas vide
    THUMP_MIN_MS = 150,     -- ms : serveur, rapports des coups d'un même client plus rapprochés ignorés
    FLOOR_MS = 2500,        -- ms : zombie au sol rapporté encore cru (rapport renvoyé dès que la liste change)
    FLOOR_REACH = 3,        -- cases : copie du serveur à au plus cette distance du zombie au sol rapporté
    LEVEL_MIN = -32, LEVEL_MAX = 31,   -- niveaux de carte (base map-files.md)
}

Senses.npcs = Senses.npcs or {}         -- exécutant : npcId -> { ms, tracks = { [clé] = piste }, sen, sig }
Senses.sounds = Senses.sounds or {}     -- exécutant : bruits du monde récents { ms, x, y, z, r, src }
Senses.vigilance = Senses.vigilance or {}   -- npcId -> "sleep" | "busy" | "rest" | "guard" (autorité ou LK05-T03)
Senses.cursor = Senses.cursor or { npc = 0, zombie = 0 }
Senses.store = Senses.store or {}       -- autorité : npcId -> dernier résumé accepté
Senses.thumpStore = Senses.thumpStore or {}   -- serveur (LK06-T11) : compte -> { ms, w } dernier rapport des coups
Senses.thumpSent = Senses.thumpSent or {}     -- client (LK06-T11) : { ms, key, n } dernier rapport des coups envoyé
Senses.CMD_THUMPS = "zombieThumps"
Senses.stats = Senses.stats or { passes = 0, npcs = 0, targets = 0, los = 0, losSkipped = 0, zombies = 0,
    sounds = 0, maxNpcs = 0, maxTargets = 0, maxLos = 0, maxZombies = 0, last = {}, accepted = 0, dropped = 0,
    refused = 0 }

local function log() return LivingKnox.Log end
local function now() return getTimestampMs() end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function round(v, step) return math.floor(v / step + 0.5) * step end

-- ================================================================ modèle (pur, déterministe)
-- npc : { vigil = "rest"..., pose = "stand" | "floor" | "crawl" }
-- o (observation d'une cible) : { kind = "player" | "zombie", d (cases, à plat), dz (étages), cos (alignement avec
-- le regard du PNJ, -1..1), light (0..1), torch, fog, rain (0..1), sneak, crawl, motion ("still"..."sprint"),
-- noise (rayon des bruits du monde émis par la cible, 0 sinon), room ("same" | "other" | "outside"), los (nom du
-- résultat de lineClear, nil = non testée) }

local function vigil(npc)
    local M = Senses.MODEL
    return M.VIGIL[npc and npc.vigil or "rest"] or M.VIGIL.rest
end

-- Facteur du champ de vision selon le cosinus de l'angle regard -> cible.
function Senses.fovFactor(cos, d)
    local M = Senses.MODEL
    local f = 0
    for _, step in ipairs(M.FOV) do
        if cos >= step[1] then
            f = step[2]
            break
        end
    end
    if d <= M.NEAR and f < M.NEAR_FOV then f = M.NEAR_FOV end
    return f
end

-- Portée de vue sans la ligne de vue (borne haute : une cible plus loin n'a pas besoin de lineClear).
function Senses.openRange(npc, o)
    local M = Senses.MODEL
    local light = clamp(o.light or 0, 0, 1)
    if o.torch and light < M.TORCH_LIGHT then light = M.TORCH_LIGHT end
    local r = M.SIGHT * (M.LIGHT_MIN + (1 - M.LIGHT_MIN) * light)
    r = r * math.max(M.WEATHER_MIN, 1 - M.FOG * clamp(o.fog or 0, 0, 1) - M.RAIN * clamp(o.rain or 0, 0, 1))
    r = r / (1 + M.LEVEL * math.abs(o.dz or 0))
    r = r * Senses.fovFactor(o.cos or 1, o.d or 0)
    if o.sneak then r = r * M.SNEAK end
    if o.crawl then r = r * M.CRAWL end
    r = r * (M.MOTION[o.motion or "walk"] or 1)
    r = r * vigil(npc).see
    if npc and npc.pose ~= nil and npc.pose ~= "stand" then r = r * M.NPC_FLOOR end
    return math.min(M.SIGHT_MAX, r)
end

-- Portée de vue complète (ligne de vue comprise) ; ligne non testée ou bloquée : 0.
function Senses.visionRange(npc, o)
    local f = Senses.MODEL.LOS[o.los or "Blocked"] or 0
    if f <= 0 then return 0 end
    return math.min(Senses.MODEL.SIGHT_MAX, Senses.openRange(npc, o) * f)
end

-- Rayon effectif d'ouïe de la cible pour ce PNJ (bruit propre ou bruits du monde, le plus fort).
function Senses.hearRange(npc, o)
    local M = Senses.MODEL
    local table_ = M.NOISE[o.kind or "player"] or M.NOISE.player
    local own = table_[o.motion or "still"] or 0
    if o.sneak then own = own * M.SNEAK_NOISE end
    local noise = math.max(own, o.noise or 0)
    return noise * vigil(npc).hear / (M.WALL[o.room or "same"] or 1)
end

-- Distance d'ouïe : un étage compte pour LEVEL_HEAR cases.
function Senses.hearDistance(o)
    local dz = (o.dz or 0) * Senses.MODEL.LEVEL_HEAR
    local d = o.d or 0
    return math.sqrt(d * d + dz * dz)
end

-- Évaluation instantanée : { r = portée de vue, sight = dans la portée et la ligne, hr = rayon d'ouïe, heard }.
function Senses.evaluate(npc, o)
    local r = Senses.visionRange(npc, o)
    local hr = Senses.hearRange(npc, o)
    return { r = r, sight = r > 0 and (o.d or 0) <= r, hr = hr, heard = hr > 0 and Senses.hearDistance(o) <= hr }
end

-- Pas de la piste d'une cible : attention a (0..1), vue (a = 1 et dans la portée), entendue (jusqu'à HEAR_MS après
-- le dernier bruit), dernière position connue. ev : résultat d'evaluate ; nil = cible absente (hors de portée ou
-- hors des candidats) : l'attention baisse. dt en secondes, t en ms (horloge passée par l'appelant). Rend track.
function Senses.step(track, ev, o, dt, t)
    local M = Senses.MODEL
    dt = clamp(dt or 0, 0, M.MAX_DT)
    track.a = track.a or 0
    if ev ~= nil and ev.sight then
        track.a = math.min(1, track.a + (M.GAIN_MIN + M.GAIN_SPAN * (1 - (o.d or 0) / ev.r)) * dt)
    else
        track.a = math.max(0, track.a - M.DECAY * dt)
    end
    track.s = ev ~= nil and ev.sight and track.a >= 1 or false
    if ev ~= nil and ev.heard then track.hms = t end
    track.h = track.hms ~= nil and t - track.hms <= M.HEAR_MS or false
    if ev ~= nil and (ev.sight or ev.heard) and o.x ~= nil then
        track.x, track.y, track.z = o.x, o.y, o.z
    end
    track.d = o and o.d or track.d
    return track
end

-- Allure déduite d'une vitesse mesurée (cases/s).
function Senses.motionOfSpeed(speed)
    local S = Senses.MODEL.SPEED
    if speed >= S.sprint then return "sprint" end
    if speed >= S.run then return "run" end
    if speed >= S.walk then return "walk" end
    return "still"
end

local MOTION_RANK = { still = 0, walk = 1, run = 2, sprint = 3 }

-- La plus vive des deux allures.
function Senses.maxMotion(a, b)
    if (MOTION_RANK[b] or 0) > (MOTION_RANK[a] or 0) then return b end
    return a
end

-- ================================================================ mesures du moteur (exécutant)

-- Bruit du monde (OnWorldSound, déclenché par WorldSound.init, J/WorldSoundManager.java:480, sur toute machine qui
-- l'ajoute, client MP compris pour les bruits relayés, J/network/packets/sound/WorldSoundPacket.java:109-121).
function Senses.onWorldSound(x, y, z, radius, volume, source)
    if not finite(x) or not finite(y) or not finite(z) or not finite(radius) or radius <= 0 then return end
    local list = Senses.sounds
    list[#list + 1] = { ms = now(), x = x, y = y, z = z, r = radius, src = source }
    while #list > Senses.BUDGET.SOUNDS do table.remove(list, 1) end
    Senses.stats.sounds = Senses.stats.sounds + 1
end

-- Bruits encore valables (SOUND_MS), anneau purgé.
local function liveSounds(t)
    local keep = {}
    for _, s in ipairs(Senses.sounds) do
        if t - s.ms <= Senses.MODEL.SOUND_MS then keep[#keep + 1] = s end
    end
    Senses.sounds = keep
    return keep
end

-- Ligne de vue (J/iso/LosUtil.java:28-30, portes fermées et rideaux bloquants, verre transparent ; même appel que
-- IsoGameCharacter.CanSee, J/characters/IsoGameCharacter.java:4733-4735). Rend le nom du résultat.
function Senses.lineOfSight(x0, y0, z0, x1, y1, z1)
    if LosUtil == nil or LosUtil.lineClear == nil then return "Blocked" end
    local res = LosUtil.lineClear(getCell(), math.floor(x0), math.floor(y0), math.floor(z0), math.floor(x1),
        math.floor(y1), math.floor(z1), false)
    return tostring(res)
end

-- Lumière de la case de la cible pour le joueur local d'index idx (J/iso/IsoGridSquare.java:8896-8902 : maximum de
-- r, g, b de l'éclairage calculé pour ce joueur) ; case absente : lumière ambiante.
local function lightAt(sq, idx, ambient)
    if sq == nil then return ambient end
    local l = sq:getLightLevel(idx)
    if not finite(l) then return ambient end
    return clamp(l, 0, 1)
end

-- Relation de pièces entre deux cases : "same" (même pièce ou dehors tous deux), "outside" (l'une dehors),
-- "other" (deux pièces) ; WorldSoundManager.java:232-244.
local function roomRelation(a, b)
    local ra = a and a:getRoom() or nil
    local rb = b and b:getRoom() or nil
    if ra == rb then return "same" end
    if ra == nil or rb == nil then return "outside" end
    return "other"
end

-- Contexte d'un passage : météo, lumière ambiante, index de lumière du joueur local.
local function passContext(t)
    local ctx = { t = t, fog = 0, rain = 0, ambient = 1, idx = 0 }
    local cm = getClimateManager and getClimateManager() or nil
    if cm ~= nil then
        ctx.fog = clamp(cm:getFogIntensity() or 0, 0, 1)
        ctx.rain = clamp(cm:getRainIntensity() or 0, 0, 1)
        ctx.ambient = clamp(math.min(cm:getDayLightStrength() or 1, cm:getAmbient() or 1), 0, 1)
    end
    local p = getSpecificPlayer and getSpecificPlayer(0) or nil
    if p ~= nil then ctx.idx = p:getPlayerNum() end
    if ctx.idx == nil or ctx.idx < 0 then ctx.idx = 0 end
    return ctx
end

-- Joueurs vivants visibles du moteur : connectés (client MP) et locaux, sans double, ni fantôme ni invisible
-- (le moteur les ignore aussi, IsoZombie.java:1714-1717).
local function livePlayers()
    local out, seen = {}, {}
    local function add(p)
        if p == nil or p:isDead() then return end
        local name = p:getUsername()
        if name == nil or seen[name] then return end
        if p:isGhostMode() or p:isInvisible() then return end
        seen[name] = true
        out[#out + 1] = p
    end
    local list = getOnlinePlayers and getOnlinePlayers() or nil
    if list ~= nil then
        for i = 0, list:size() - 1 do add(list:get(i)) end
    end
    if getNumActivePlayers ~= nil then
        for i = 0, getNumActivePlayers() - 1 do add(getSpecificPlayer(i)) end
    end
    return out
end

-- Vigilance du PNJ : valeur posée par l'autorité (Senses.setVigilance ; solo et serveur) ; sur un client MP, celle que
-- l'autorité a décidée et que porte la consigne courante reçue (champ vg, LK05-T03 : LivingKnox.Directives.setVigil) ;
-- sinon déduite de l'exécution en cours (marche : occupé ; sinon : repos).
function Senses.vigilanceOf(id)
    local v = Senses.vigilance[id]
    if v ~= nil and Senses.MODEL.VIGIL[v] then return v end
    local E = LivingKnox.Executor
    if isClient() and E ~= nil and type(E.remote) == "table" and type(E.remote.d) == "table" then
        local e = E.remote.d[id]
        if type(e) == "table" and type(e.vg) == "string" and Senses.MODEL.VIGIL[e.vg] then return e.vg end
    end
    if E ~= nil and E.activityOf ~= nil and E.activityOf(id) == "moving" then return "busy" end
    return "rest"
end

-- Autorité : vigilance d'un PNJ (sleep, busy, rest, guard), nil pour revenir à la valeur déduite. Rend vrai.
function Senses.setVigilance(id, kind)
    if type(id) ~= "string" or (kind ~= nil and not Senses.MODEL.VIGIL[kind]) then return false end
    Senses.vigilance[id] = kind
    return true
end

local function poseOf(z)
    local E = LivingKnox.Executor
    if E ~= nil and E.poseOf ~= nil then return E.poseOf(z) end
    return "stand"
end

-- Clé stable d'une cible : compte d'un joueur, identifiant réseau d'un zombie (solo : -1, objet Java à défaut).
local function zombieKey(z)
    local o = z:getOnlineID()
    if o ~= nil and o >= 0 then return "z:" .. tostring(o), o end
    return "z@" .. tostring(z), -1
end

-- Zombies de la cellule proches d'au moins un des PNJ choisis (borné par ZOMBIE_SCAN, curseur au-delà), hors corps
-- de PNJ. Rend { [npcId] = { zombie, ... } }.
local function nearZombies(chosen, bodies)
    local B = Senses.BUDGET
    local out = {}
    for _, c in ipairs(chosen) do out[c.id] = {} end
    local cell = getCell()
    local list = cell and cell:getZombieList() or nil
    if list == nil then return out, 0 end
    local n = list:size()
    local count = math.min(n, B.ZOMBIE_SCAN)
    local start = n > B.ZOMBIE_SCAN and Senses.cursor.zombie % n or 0
    for k = 0, count - 1 do
        local z = list:get((start + k) % n)
        if z ~= nil and not z:isDead() and bodies[z] == nil then
            local x, y, lz = z:getX(), z:getY(), z:getZ()
            for _, c in ipairs(chosen) do
                if math.abs(x - c.x) <= B.RANGE and math.abs(y - c.y) <= B.RANGE
                    and math.abs(math.floor(lz) - math.floor(c.z)) <= B.LEVELS then
                    local t = out[c.id]
                    t[#t + 1] = z
                end
            end
        end
    end
    if n > B.ZOMBIE_SCAN then Senses.cursor.zombie = (start + count) % n end
    return out, count
end

-- Observation d'une cible par le PNJ c (sans ligne de vue). Rend o.
local function observe(c, target, kind, key, ctx, bySource, track)
    local tx, ty, tz = target:getX(), target:getY(), target:getZ()
    local dx, dy = tx - c.x, ty - c.y
    local d = math.sqrt(dx * dx + dy * dy)
    local cos = 1
    if d > 0.01 then cos = (dx * c.fx + dy * c.fy) / d end
    local sq = target:getCurrentSquare()
    local o = { kind = kind, key = key, d = d, dz = math.floor(tz) - math.floor(c.z), cos = cos,
        light = lightAt(sq, ctx.idx, ctx.ambient), fog = ctx.fog, rain = ctx.rain,
        room = roomRelation(c.sq, sq), noise = bySource[target] or 0,
        x = math.floor(tx), y = math.floor(ty), z = math.floor(tz), fx = tx, fy = ty }
    local motion = "still"
    if kind == "player" then
        o.torch = target:getTorchStrength() > 0
        o.sneak = target:isSneaking()
        if target:isSprinting() then motion = "sprint"
        elseif target:isRunning() then motion = "run"
        elseif target:isPlayerMoving() then motion = "walk" end
    else
        o.crawl = target:isCrawling()
    end
    -- Allure mesurée depuis le passage précédent de ce PNJ (zombies, joueurs distants dont les drapeaux manquent).
    if track ~= nil and track.px ~= nil and track.pms ~= nil and ctx.t > track.pms then
        local mx, my = tx - track.px, ty - track.py
        local speed = math.sqrt(mx * mx + my * my) / ((ctx.t - track.pms) / 1000)
        motion = Senses.maxMotion(motion, Senses.motionOfSpeed(speed))
    end
    o.motion = motion
    return o
end

-- Bruits du monde émis par une source (objet Java) : rayon le plus grand.
local function soundsBySource(sounds)
    local out = {}
    for _, s in ipairs(sounds) do
        if s.src ~= nil and (out[s.src] or 0) < s.r then out[s.src] = s.r end
    end
    return out
end

-- Bruits entendus par le PNJ c (hors bruits des corps de PNJ), les plus forts d'abord, au plus NOISES.
local function heardNoises(c, sounds, bodies, npc)
    local M = Senses.MODEL
    local cell = getCell()
    local out = {}
    for _, s in ipairs(sounds) do
        if s.src == nil or bodies[s.src] == nil then
            local dx, dy = math.floor(s.x) + 0.5 - c.x, math.floor(s.y) + 0.5 - c.y   -- centre de la case du bruit
            local dz = (math.floor(s.z) - math.floor(c.z)) * M.LEVEL_HEAR
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            local sq = cell and cell:getGridSquare(math.floor(s.x), math.floor(s.y), math.floor(s.z)) or nil
            local r = s.r * vigil(npc).hear / (M.WALL[roomRelation(c.sq, sq)] or 1)
            if dist <= r then
                out[#out + 1] = { x = math.floor(s.x), y = math.floor(s.y), z = math.floor(s.z), r = s.r, ms = s.ms }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.r ~= b.r then return a.r > b.r end
        if a.ms ~= b.ms then return a.ms > b.ms end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local res = {}
    for i = 1, math.min(#out, Senses.BUDGET.NOISES) do
        -- Rayon borné à celui que l'autorité accepte (Senses.validate) : un bruit du monde plus large (hélicoptère
        -- vanilla, rayon 500) faisait refuser tout le rapport d'état ("bad report", essai MP du 2026-10-14).
        res[i] = { x = out[i].x, y = out[i].y, z = out[i].z, r = math.min(out[i].r, Senses.CHECK.NOISE_MAX) }
    end
    return res
end

local function byDistance(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.key < b.key
end

-- LK06-T11 : fenêtres (IsoWindow) que frappent, parmi zombies, ceux SIMULÉS ICI (getThumpTarget du propriétaire, état
-- ThumpState). Sur un serveur, la copie d'un zombie simulé par un client n'a jamais de cible de coups : le paquet Thump
-- est seulement relayé aux autres clients (J/network/packets/character/ThumpPacket.java:54-63) ; la copie distante d'un
-- autre client la reçoit sans paquet de fin de coups : seule celle du propriétaire est rapportée. Identifiant stable :
-- onlineId du zombie, case de la fenêtre (x, y, z) et bord (k = "N" ou "W" : fenêtre posée sur sa case, bord nord ou
-- ouest). Triées par onlineId, au plus BUDGET.THUMPS. Solo (onlineId -1) : rien, l'autorité simule.
local function thumpsOf(zombies)
    local G = LivingKnox.ZombieGuard
    local out = {}
    for _, z in ipairs(zombies or {}) do
        local o = z:getOnlineID()
        if type(o) == "number" and o >= 0 and (G == nil or G.simulatedHere(z)) then
            local t = z:getThumpTarget()
            local sq = t ~= nil and instanceof(t, "IsoWindow") and t:getSquare() or nil
            if sq ~= nil then
                out[#out + 1] = { o = o, x = sq:getX(), y = sq:getY(), z = sq:getZ(), k = t:getNorth() and "N" or "W" }
            end
        end
    end
    table.sort(out, function(a, b) return a.o < b.o end)
    while #out > Senses.BUDGET.THUMPS do table.remove(out) end
    return out
end
Senses.thumpsOf = thumpsOf

-- LK06-T11 (MP) : zombies SIMULÉS ICI, parmi zombies, au sol (isOnFloor, non rampants) : la copie du serveur ne suit
-- que les paquets du propriétaire (base multiplayer.md) et ne voit pas les 2 s à terre après l'enjambée d'une fenêtre
-- (campagne MP du 2026-10-15 : zombie « entré debout » pour le serveur, aucun coup au sol). { o, x, y, z } triés par
-- onlineId, au plus BUDGET.THUMPS.
local function floorOf(zombies)
    local G = LivingKnox.ZombieGuard
    local out = {}
    for _, z in ipairs(zombies or {}) do
        local o = z:getOnlineID()
        if type(o) == "number" and o >= 0 and (G == nil or G.simulatedHere(z)) and z:isOnFloor()
            and not z:isCrawling() then
            out[#out + 1] = { o = o, x = math.floor(z:getX()), y = math.floor(z:getY()), z = math.floor(z:getZ()) }
        end
    end
    table.sort(out, function(a, b) return a.o < b.o end)
    while #out > Senses.BUDGET.THUMPS do table.remove(out) end
    return out
end
Senses.floorOf = floorOf

-- Résumé d'un PNJ depuis ses pistes : joueurs et zombies perçus (vus, entendus ou encore en attention), triés (vus,
-- attention, distance, clé), bornés ; nz = zombies perçus en tout. Rend sen et sa signature (change quand une cible
-- apparaît, disparaît, est vue ou entendue, ou se déplace de 2 cases).
local function summarize(entry)
    local B = Senses.BUDGET
    local players, zombies = {}, {}
    local nz = 0
    for key, tr in pairs(entry.tracks) do
        if tr.x ~= nil and (tr.a > 0 or tr.s or tr.h) then
            local row = { key = key, kind = tr.kind, u = tr.u, o = tr.o, x = tr.x, y = tr.y, z = tr.z,
                a = round(tr.a, 0.01), s = tr.s == true, h = tr.h == true, d = tr.d or 0 }
            if tr.kind == "player" then players[#players + 1] = row else
                zombies[#zombies + 1] = row
                nz = nz + 1
            end
        end
    end
    local function order(a, b)
        if a.s ~= b.s then return a.s end
        if a.a ~= b.a then return a.a > b.a end
        return byDistance(a, b)
    end
    table.sort(players, order)
    table.sort(zombies, order)
    local sen = { v = Senses.VERSION, nz = nz, p = {}, z = {}, n = entry.noises or {} }
    local sig = {}
    for i = 1, math.min(#players, B.PLAYERS) do
        local r = players[i]
        sen.p[i] = { u = r.u, x = r.x, y = r.y, z = r.z, a = r.a, s = r.s, h = r.h }
        sig[#sig + 1] = string.format("%s:%s%s%d,%d", r.key, r.s and "S" or "-", r.h and "H" or "-",
            math.floor(r.x / 2), math.floor(r.y / 2))
    end
    for i = 1, math.min(#zombies, B.ZOMBIES) do
        local r = zombies[i]
        sen.z[i] = { o = r.o, x = r.x, y = r.y, z = r.z, a = r.a, s = r.s, h = r.h }
        sig[#sig + 1] = string.format("%s:%s%s%d,%d", r.key, r.s and "S" or "-", r.h and "H" or "-",
            math.floor(r.x / 2), math.floor(r.y / 2))
    end
    sig[#sig + 1] = "nz" .. nz .. "n" .. #sen.n
    return sen, table.concat(sig, ";")
end

-- Perception d'un PNJ c pour ce passage. Rend le nombre de cibles et d'appels lineClear.
local function perceive(c, entry, players, zombies, ctx, bySource, sounds, bodies, losLeft)
    local B = Senses.BUDGET
    local npc = { vigil = Senses.vigilanceOf(c.id), pose = poseOf(c.body) }
    local dt = entry.ms ~= nil and (ctx.t - entry.ms) / 1000 or 0
    entry.ms = ctx.t
    local cands = {}
    for _, p in ipairs(players) do
        local dx, dy = p:getX() - c.x, p:getY() - c.y
        if math.abs(dx) <= B.RANGE and math.abs(dy) <= B.RANGE
            and math.abs(math.floor(p:getZ()) - math.floor(c.z)) <= B.LEVELS then
            cands[#cands + 1] = { obj = p, kind = "player", key = "p:" .. p:getUsername(), u = p:getUsername(),
                d = math.sqrt(dx * dx + dy * dy) }
        end
    end
    for _, z in ipairs(zombies) do
        local dx, dy = z:getX() - c.x, z:getY() - c.y
        local key, o = zombieKey(z)
        cands[#cands + 1] = { obj = z, kind = "zombie", key = key, o = o, d = math.sqrt(dx * dx + dy * dy) }
    end
    table.sort(cands, byDistance)
    local done, skipped = {}, {}
    local targets, los = 0, 0
    for i = 1, #cands do
        local cd = cands[i]
        if i > B.TARGETS then
            skipped[cd.key] = true
        else
            local tr = entry.tracks[cd.key]
            local o = observe(c, cd.obj, cd.kind, cd.key, ctx, bySource, tr)
            local open = Senses.openRange(npc, o)
            local skip = false
            if open > 0 and o.d <= open then
                if los < losLeft then
                    o.los = Senses.lineOfSight(c.x, c.y, c.z, o.fx, o.fy, o.z)
                    los = los + 1
                else
                    skip = true
                    Senses.stats.losSkipped = Senses.stats.losSkipped + 1
                end
            end
            if skip then
                skipped[cd.key] = true
            else
                targets = targets + 1
                if tr == nil then
                    tr = { kind = cd.kind, u = cd.u, o = cd.o, a = 0 }
                    entry.tracks[cd.key] = tr
                end
                Senses.step(tr, Senses.evaluate(npc, o), o, dt, ctx.t)
                tr.px, tr.py, tr.pms = o.fx, o.fy, ctx.t
                done[cd.key] = true
            end
        end
    end
    -- Cibles hors des candidats : l'attention baisse ; pistes éteintes oubliées (table modifiée hors de pairs).
    local drop = {}
    for key, tr in pairs(entry.tracks) do
        if not done[key] and not skipped[key] then
            Senses.step(tr, nil, nil, dt, ctx.t)
            tr.px, tr.pms = nil, nil
            if tr.a <= 0 and not tr.h then drop[#drop + 1] = key end
        end
    end
    for _, key in ipairs(drop) do entry.tracks[key] = nil end
    entry.noises = heardNoises(c, sounds, bodies, npc)
    entry.sen, entry.sig = summarize(entry)
    entry.vigil = npc.vigil
    return targets, los
end

-- Passage de perception de l'exécutant : known = { [npcId] = corps présent dans le monde de cette machine } ;
-- seuls les corps simulés ici sont examinés, NPCS au plus par passage, tour à tour. Rend le nombre de PNJ examinés.
function Senses.scan(known, t)
    t = t or now()
    local B = Senses.BUDGET
    local G = LivingKnox.ZombieGuard
    local ids, bodies = {}, {}
    for id, z in pairs(known) do
        bodies[z] = id
        if G == nil or G.simulatedHere(z) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    -- PNJ disparus de cette machine : pistes oubliées (table modifiée hors de pairs).
    local gone = {}
    for id in pairs(Senses.npcs) do
        if known[id] == nil or bodies[known[id]] == nil then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do Senses.npcs[id] = nil end
    local st = Senses.stats
    st.passes = st.passes + 1
    local chosen = {}
    local n = #ids
    if n > 0 then
        local first = Senses.cursor.npc % n
        for k = 0, math.min(n, B.NPCS) - 1 do
            local id = ids[(first + k) % n + 1]
            local z = known[id]
            -- Regard : (cos a, sin a), a en degrés (J/characters/IsoGameCharacter.java:2626-2635).
            local a = z:getDirectionAngle() * math.pi / 180
            chosen[#chosen + 1] = { id = id, body = z, x = z:getX(), y = z:getY(), z = z:getZ(),
                sq = z:getCurrentSquare(), fx = math.cos(a), fy = math.sin(a) }
        end
        Senses.cursor.npc = (first + #chosen) % n
    end
    local ctx = passContext(t)
    local sounds = liveSounds(t)
    local bySource = soundsBySource(sounds)
    local players = livePlayers()
    local near, scanned = nearZombies(chosen, bodies)
    local targets, los = 0, 0
    for _, c in ipairs(chosen) do
        local entry = Senses.npcs[c.id]
        if entry == nil then
            entry = { tracks = {} }
            Senses.npcs[c.id] = entry
        end
        local nt, nl = perceive(c, entry, players, near[c.id], ctx, bySource, sounds, bodies, B.LOS - los)
        targets, los = targets + nt, los + nl
    end
    st.npcs = st.npcs + #chosen
    st.targets = st.targets + targets
    st.los = st.los + los
    st.zombies = st.zombies + scanned
    st.maxNpcs = math.max(st.maxNpcs, #chosen)
    st.maxTargets = math.max(st.maxTargets, targets)
    st.maxLos = math.max(st.maxLos, los)
    st.maxZombies = math.max(st.maxZombies, scanned)
    st.last = { npcs = #chosen, targets = targets, los = los, zombies = scanned, players = #players }
    return #chosen
end

-- Dernier résumé calculé ici pour un PNJ (pour le rapport d'état), et sa signature ; nil si jamais examiné.
function Senses.summary(id)
    local e = Senses.npcs[id]
    if e == nil or e.sen == nil then return nil, nil end
    return e.sen, e.sig
end

-- ================================================================ autorité : contrôle et mémoire

local function validEntry(e, idField)
    if type(e) ~= "table" then return false end
    if not finite(e.x) or not finite(e.y) or not finite(e.z) then return false end
    if type(e.a) ~= "number" or e.a < 0 or e.a > 1 then return false end
    if type(e.s) ~= "boolean" or type(e.h) ~= "boolean" then return false end
    if idField == "u" then
        return type(e.u) == "string" and #e.u > 0 and #e.u <= Senses.CHECK.NAME_MAX
    end
    return finite(e.o)
end

-- Forme et bornes d'un résumé reçu. Rend nil, ou la raison (raisons de LK_Reports) et un détail.
function Senses.validate(sen)
    local B, C = Senses.BUDGET, Senses.CHECK
    if type(sen) ~= "table" or sen.v ~= Senses.VERSION or type(sen.nz) ~= "number" then return "bad report", "senses" end
    if sen.nz < 0 or sen.nz > C.COUNT_MAX or sen.nz ~= math.floor(sen.nz) then
        return "out of bounds", "senses count " .. tostring(sen.nz)
    end
    for _, part in ipairs({ { "p", "u", B.PLAYERS }, { "z", "o", B.ZOMBIES } }) do
        local list = sen[part[1]]
        if list ~= nil then
            if type(list) ~= "table" or #list > part[3] then return "out of bounds", "senses " .. part[1] end
            for i = 1, #list do
                if not validEntry(list[i], part[2]) then return "bad report", "senses " .. part[1] .. " " .. i end
            end
        end
    end
    if sen.n ~= nil then
        if type(sen.n) ~= "table" or #sen.n > B.NOISES then return "out of bounds", "senses noises" end
        for i = 1, #sen.n do
            local s = sen.n[i]
            if type(s) ~= "table" or not finite(s.x) or not finite(s.y) or not finite(s.z) or not finite(s.r)
                or s.r <= 0 or s.r > C.NOISE_MAX then
                return "bad report", "senses noise " .. i
            end
        end
    end
    return nil
end

-- LK06-T11 : forme et bornes d'une liste de fenêtres frappées reçue. Rend nil, ou la raison et un détail.
function Senses.validateThumps(list)
    local C = Senses.CHECK
    if type(list) ~= "table" or #list > Senses.BUDGET.THUMPS then return "out of bounds", "thumps" end
    for i = 1, #list do
        local w = list[i]
        if type(w) ~= "table" or not finite(w.o) or not finite(w.x) or not finite(w.y) or not finite(w.z)
            or (w.k ~= "N" and w.k ~= "W") then
            return "bad report", "thump " .. i
        end
        if w.o < 0 or w.o ~= math.floor(w.o) or w.x ~= math.floor(w.x) or w.y ~= math.floor(w.y)
            or w.z ~= math.floor(w.z) or w.x < 0 or w.y < 0 or w.z < C.LEVEL_MIN or w.z > C.LEVEL_MAX then
            return "out of bounds", "thump " .. i
        end
    end
    return nil
end

-- LK06-T11 : forme et bornes d'une liste de zombies au sol reçue ({ o, x, y, z }). Rend nil, ou la raison.
function Senses.validateFloor(list)
    local C = Senses.CHECK
    if type(list) ~= "table" or #list > Senses.BUDGET.THUMPS then return "out of bounds", "floor" end
    for i = 1, #list do
        local f = list[i]
        if type(f) ~= "table" or not finite(f.o) or not finite(f.x) or not finite(f.y) or not finite(f.z) then
            return "bad report", "floor " .. i
        end
        if f.o < 0 or f.o ~= math.floor(f.o) or f.z < C.LEVEL_MIN or f.z > C.LEVEL_MAX then
            return "out of bounds", "floor " .. i
        end
    end
    return nil
end

-- LK06-T11 : fenêtre (IsoWindow) posée sur la case x, y, z, sur son bord k ("N" : entre y - 1 et y ; "W" : entre
-- x - 1 et x), ou nil. IsoGridSquare.getWindowTo rend la fenêtre du bord commun de deux cases voisines
-- (J/iso/IsoGridSquare.java:3131-3137).
function Senses.windowAt(x, y, z, k)
    local cell = getCell()
    if cell == nil then return nil end
    local sq = cell:getGridSquare(x, y, z)
    local nb
    if k == "N" then nb = cell:getGridSquare(x, y - 1, z) else nb = cell:getGridSquare(x - 1, y, z) end
    if sq == nil or nb == nil then return nil end
    local w = sq:getWindowTo(nb)
    if w == nil or not instanceof(w, "IsoWindow") then return nil end
    local ws = w:getSquare()
    if ws == nil or ws:getX() ~= x or ws:getY() ~= y or ws:getZ() ~= z or (w:getNorth() == true) ~= (k == "N") then
        return nil
    end
    return w
end

-- Distance (cases, à plat) du point (px, py) au milieu du bord k de la case x, y.
function Senses.edgeDist(px, py, x, y, k)
    local mx, my = x + 0.5, y
    if k == "W" then mx, my = x, y + 0.5 end
    local dx, dy = px - mx, py - my
    return math.sqrt(dx * dx + dy * dy)
end

-- Comptes des joueurs vivants connus de l'autorité (serveur : connectés ; solo : locaux).
local function knownNames()
    local out = {}
    for _, p in ipairs(livePlayers()) do out[p:getUsername()] = true end
    return out
end

-- Serveur : onlineId -> zombie vivant de sa cellule (relu au plus toutes les CHECK.KNOWN_MS), ou nil ailleurs.
-- Un zombie que le serveur a retiré reste chez le client qui le simulait jusqu'à ~5 s (aucun paquet de retrait sans
-- NetworkZombiePacker.deleteZombie, non exposé ; copie retirée par J/characters/IsoZombie.java:2718 après 5 s sans
-- paquet) : le corps d'un PNJ retiré y devient un zombie ordinaire, vu par les PNJ voisins (campagne MP du
-- 2026-10-14 : alerte levée contre deux « zombies » fantômes dans la maison, constructeur jamais au travail).
local function serverZombies()
    if not isServer() then return nil end
    local k = Senses.known
    local t = now()
    if k ~= nil and t - k.ms < Senses.CHECK.KNOWN_MS then return k.set end
    local set = {}
    local cell = getCell()
    local list = cell and cell:getZombieList() or nil
    if list ~= nil then
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and not z:isDead() then
                local o = z:getOnlineID()
                if type(o) == "number" and o >= 0 then set[o] = z end   -- LK06-T11 : objet gardé
            end
        end
    end
    Senses.known = { ms = t, set = set }
    return set
end

local function plausible(e, body, seenMax)
    local C = Senses.CHECK
    local dx, dy = e.x + 0.5 - body:getX(), e.y + 0.5 - body:getY()   -- centre de la case rapportée
    local d = math.sqrt(dx * dx + dy * dy)
    local limit = (e.s and seenMax or C.HEAR_MAX) + C.SLACK
    if d > limit then return false, d end
    if e.s and math.abs(e.z - math.floor(body:getZ())) > C.SEEN_LEVELS then return false, d end
    return true, d
end

-- Résumé d'un rapport d'état ACCEPTÉ (LK_Reports.onReport, après tous ses contrôles) : entrées implausibles (vue
-- au-delà de la portée maximale, cible entendue trop loin, joueur inconnu, zombie inconnu du serveur) retirées et
-- comptées (stats.dropped ; zombies inconnus aussi dans stats.ghosts) ; distance recalculée
-- depuis la copie du serveur ; mémoire = dernière valeur. Rend le nombre d'entrées retirées.
function Senses.accept(id, sen, by, body)
    if not LivingKnox.isAuthority() or type(id) ~= "string" or body == nil then return 0 end
    local st0 = Senses.stats
    local names = knownNames()
    local known = serverZombies()
    local seenMax = Senses.MODEL.SIGHT_MAX
    local out = { ms = now(), by = by, nz = sen.nz, p = {}, z = {}, n = {} }
    local dropped = 0
    for _, e in ipairs(sen.p or {}) do
        local ok, d = plausible(e, body, seenMax)
        if ok and names[e.u] then
            out.p[#out.p + 1] = { u = e.u, x = e.x, y = e.y, z = e.z, a = e.a, s = e.s, h = e.h, d = round(d, 0.1) }
        else
            dropped = dropped + 1
        end
    end
    for _, e in ipairs(sen.z or {}) do
        local ok, d = plausible(e, body, seenMax)
        if ok and known ~= nil and e.o >= 0 and not known[e.o] then
            ok = false
            st0.ghosts = (st0.ghosts or 0) + 1   -- zombie inconnu du serveur (copie fantôme du client)
        end
        if ok then
            out.z[#out.z + 1] = { o = e.o, x = e.x, y = e.y, z = e.z, a = e.a, s = e.s, h = e.h, d = round(d, 0.1) }
        else
            dropped = dropped + 1
        end
    end
    for _, s in ipairs(sen.n or {}) do
        local dx, dy = s.x + 0.5 - body:getX(), s.y + 0.5 - body:getY()
        if math.sqrt(dx * dx + dy * dy) <= s.r * Senses.MODEL.VIGIL.guard.hear + Senses.CHECK.SLACK then
            out.n[#out.n + 1] = { x = s.x, y = s.y, z = s.z, r = s.r }
        else
            dropped = dropped + 1
        end
    end
    local st = Senses.stats
    st.accepted = st.accepted + 1
    if dropped > 0 then
        st.dropped = st.dropped + dropped
        log().debug("npc %s: %d implausible perception entries from %s dropped", id, dropped, tostring(by))
    end
    Senses.store[id] = out
    return dropped
end

local function copyRows(list)
    local out = {}
    for i, e in ipairs(list) do
        local r = {}
        for k, v in pairs(e) do r[k] = v end
        out[i] = r
    end
    return out
end

-- Ce que perçoit un PNJ selon le dernier rapport accepté (copie), ou nil : { ms, age, stale, by, nz, seen, heard,
-- p = { { u, x, y, z, a, s, h, d } }, z = { { o, x, y, z, a, s, h, d } }, n = { { x, y, z, r } } }. seen / heard :
-- nombre de cibles vues / entendues. PNJ dont l'état n'est plus suivi (LK_Reports.get nil) : oublié.
function Senses.perceived(id)
    local s = Senses.store[id]
    if s == nil then return nil end
    local R = LivingKnox.Reports
    if R ~= nil and R.get ~= nil and R.get(id) == nil then
        Senses.forget(id)
        return nil
    end
    local out = { ms = s.ms, age = now() - s.ms, by = s.by, nz = s.nz, p = copyRows(s.p), z = copyRows(s.z),
        n = copyRows(s.n), seen = 0, heard = 0 }
    out.stale = out.age > Senses.CHECK.STALE_MS
    for _, list in ipairs({ out.p, out.z }) do
        for _, e in ipairs(list) do
            if e.s then out.seen = out.seen + 1 end
            if e.h then out.heard = out.heard + 1 end
        end
    end
    return out
end

-- ================================================================ LK06-T11 : rapport des coups du propriétaire

-- Client MP (appelé par LivingKnox.Executor à chacun de ses passages) : fenêtres frappées par les zombies que CE
-- client simule, à THUMP_RANGE cases d'un corps de PNJ présent ici (known : { [npcId] = corps }, simulé ici ou non :
-- le propriétaire d'un zombie n'est pas toujours celui des corps voisins, campagne MP du 2026-10-15). Rend les
-- arguments { n, w } de la commande zombieThumps (envoyée par l'exécutant : aucune commande réseau ici) quand la liste
-- change, puis toutes les THUMP_REFRESH_MS tant qu'elle n'est pas vide ; liste vidée : { n } seul (une table vide
-- arrive en nil). Sinon nil.
function Senses.thumpReport(known, t)
    if not isClient() or isServer() then return nil end
    t = t or now()
    local B = Senses.BUDGET
    local spots = {}
    for _, z in pairs(known or {}) do spots[#spots + 1] = { x = z:getX(), y = z:getY(), z = math.floor(z:getZ()) } end
    local list = {}
    if #spots > 0 then
        local bodies = {}
        for _, z in pairs(known) do bodies[z] = true end
        local cell = getCell()
        local zl = cell and cell:getZombieList() or nil
        for i = 0, math.min(zl ~= nil and zl:size() or 0, B.ZOMBIE_SCAN) - 1 do
            local z = zl:get(i)
            if z ~= nil and bodies[z] == nil and not z:isDead() then
                local zx, zy, zz = z:getX(), z:getY(), math.floor(z:getZ())
                for _, sp in ipairs(spots) do
                    if math.abs(zx - sp.x) <= B.THUMP_RANGE and math.abs(zy - sp.y) <= B.THUMP_RANGE
                        and math.abs(zz - sp.z) <= B.LEVELS then
                        list[#list + 1] = z
                        break
                    end
                end
            end
        end
    end
    local w = thumpsOf(list)
    local fl = floorOf(list)
    local keys = {}
    for _, e in ipairs(w) do keys[#keys + 1] = string.format("z%d %d,%d,%d,%s", e.o, e.x, e.y, e.z, e.k) end
    for _, e in ipairs(fl) do keys[#keys + 1] = string.format("z%d floor", e.o) end
    local key = table.concat(keys, "; ")
    local last = Senses.thumpSent
    local due = key ~= (last.key or "")
        or ((#w > 0 or #fl > 0) and t - (last.ms or 0) >= Senses.CHECK.THUMP_REFRESH_MS)
    if not due then return nil end
    last.n = (last.n or 0) + 1
    if key ~= (last.key or "") then
        log().info("thumped windows reported: %s", key ~= "" and key or "none")
    end
    last.key, last.ms = key, t
    Senses.stats.thumpsSent = (Senses.stats.thumpsSent or 0) + 1
    return { n = last.n, w = #w > 0 and w or nil, f = #fl > 0 and fl or nil }
end

-- Serveur : rapport des coups du client player (args { n, w }). Gardé (dernier rapport par compte) après contrôle :
-- forme (validateThumps, sinon rapport entier refusé), rapports plus rapprochés que THUMP_MIN_MS ignorés ; par
-- entrée : zombie vivant connu du serveur, SIMULÉ PAR CE CLIENT (getOwnerPlayer, le seul qui voit ses coups),
-- fenêtre réelle à la case et au bord indiqués, copie du serveur au même niveau et à THUMP_REACH cases au plus du
-- milieu du bord ; sinon entrée retirée (stats.thumpsDropped). Le foyer et la fraîcheur sont contrôlés à l'usage
-- (Senses.thumpOf, LivingKnox.Defense.thumpTargetOf). Rend le nombre d'entrées gardées, ou nil si refusé.
function Senses.onThumps(player, args)
    if not isServer() or player == nil then return nil end
    local name = player:getUsername()
    local st = Senses.stats
    if type(name) ~= "string" or type(args) ~= "table" or not finite(args.n) then
        st.thumpsRefused = (st.thumpsRefused or 0) + 1
        return nil
    end
    local why, detail = nil, nil
    if args.w ~= nil then why, detail = Senses.validateThumps(args.w) end
    if why == nil and args.f ~= nil then why, detail = Senses.validateFloor(args.f) end
    local t = now()
    local prev = Senses.thumpStore[name]
    if why == nil and prev ~= nil and (args.n <= prev.n or t - prev.ms < Senses.CHECK.THUMP_MIN_MS) then
        why, detail = "replayed or too frequent", tostring(args.n)
    end
    if why ~= nil then
        st.thumpsRefused = (st.thumpsRefused or 0) + 1
        log().debug("thump report from %s refused: %s (%s)", name, why, tostring(detail))
        return nil
    end
    local known = serverZombies()
    local out = {}
    for _, w in ipairs(args.w or {}) do
        local z = known ~= nil and known[w.o] or nil
        local owner = z ~= nil and z.getOwnerPlayer ~= nil and z:getOwnerPlayer() or nil
        local ok = z ~= nil and owner ~= nil and owner:getUsername() == name
            and Senses.windowAt(w.x, w.y, w.z, w.k) ~= nil and math.floor(z:getZ()) == w.z
            and Senses.edgeDist(z:getX(), z:getY(), w.x, w.y, w.k) <= Senses.CHECK.THUMP_REACH
        if ok then
            out[#out + 1] = { o = w.o, x = w.x, y = w.y, z = w.z, k = w.k }
            st.thumps = (st.thumps or 0) + 1
        else
            st.thumpsDropped = (st.thumpsDropped or 0) + 1
            log().debug("thump report from %s: zombie %s at window %d,%d,%d,%s dropped", name, tostring(w.o), w.x, w.y,
                w.z, w.k)
        end
    end
    -- Zombies au sol : même contrôle de propriétaire, copie du serveur au même niveau et à FLOOR_REACH cases au plus.
    local floor = {}
    for _, f in ipairs(args.f or {}) do
        local z = known ~= nil and known[f.o] or nil
        local owner = z ~= nil and z.getOwnerPlayer ~= nil and z:getOwnerPlayer() or nil
        if z ~= nil and owner ~= nil and owner:getUsername() == name and math.floor(z:getZ()) == f.z
            and math.abs(z:getX() - (f.x + 0.5)) <= Senses.CHECK.FLOOR_REACH
            and math.abs(z:getY() - (f.y + 0.5)) <= Senses.CHECK.FLOOR_REACH then
            floor[f.o] = true
            st.floorReported = (st.floorReported or 0) + 1
        else
            st.floorDropped = (st.floorDropped or 0) + 1
        end
    end
    Senses.thumpStore[name] = { ms = t, n = args.n, w = out, f = floor }
    return #out
end

-- LK06-T11 : dernière fenêtre frappée rapportée pour le zombie d'onlineId o, encore crue (THUMP_MS), ou nil :
-- { x, y, z, k, ms, by } (copie). Un rapport suivant du même client sans elle l'efface.
function Senses.thumpOf(o)
    if type(o) ~= "number" or o < 0 then return nil end
    local t = now()
    local best = nil
    for name, r in pairs(Senses.thumpStore) do
        if t - r.ms <= Senses.CHECK.THUMP_MS and (best == nil or r.ms > best.ms or (r.ms == best.ms and name < best.by)) then
            for _, w in ipairs(r.w) do
                if w.o == o then best = { x = w.x, y = w.y, z = w.z, k = w.k, ms = r.ms, by = name } end
            end
        end
    end
    return best
end

-- LK06-T11 : vrai si le zombie z est au sol (isOnFloor, non rampant) ; sur un serveur MP, aussi d'après le dernier
-- rapport encore cru (FLOOR_MS) du client qui le simule (la copie du serveur ne voit pas la chute). Seul le rapport
-- du propriétaire actuel compte.
function Senses.onFloor(z)
    if z == nil then return false end
    if z:isOnFloor() then return not z:isCrawling() end
    if not isServer() or z:isCrawling() then return false end
    local o = z:getOnlineID()
    local owner = z.getOwnerPlayer ~= nil and z:getOwnerPlayer() or nil
    local r = owner ~= nil and Senses.thumpStore[owner:getUsername()] or nil
    return r ~= nil and r.f ~= nil and r.f[o] == true and now() - r.ms <= Senses.CHECK.FLOOR_MS
end

-- Entrée d'un joueur dans ce que perçoit un PNJ (copie), ou nil.
function Senses.perceivedPlayer(id, username)
    local p = Senses.perceived(id)
    if p == nil then return nil end
    for _, e in ipairs(p.p) do
        if e.u == username then return e end
    end
    return nil
end

function Senses.forget(id)
    Senses.store[id] = nil
    Senses.vigilance[id] = nil
end

-- ================================================================ abonnements
if isServer() and Events ~= nil then   -- LK06-T11 : rapport des coups du propriétaire d'un zombie
    local function onClientCommand(module, command, player, args)
        if module == "LivingKnox" and command == LivingKnox.Senses.CMD_THUMPS then
            LivingKnox.Senses.onThumps(player, args)
        end
    end
    LivingKnox.subscribe("OnClientCommand", "Senses.onThumps", onClientCommand)
end
if not isServer() and Events ~= nil then   -- Events absent : VM de test sans moteur (tests/test_kahlua.py)
    local function onWorldSound(x, y, z, radius, volume, source)
        LivingKnox.Senses.onWorldSound(x, y, z, radius, volume, source)
    end
    LivingKnox.subscribe("OnWorldSound", "Senses.onWorldSound", onWorldSound)
end

return Senses
