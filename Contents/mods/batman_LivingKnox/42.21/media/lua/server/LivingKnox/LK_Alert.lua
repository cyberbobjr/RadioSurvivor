-- Living Knox : alerte de proximité d'un groupe (zombies et intrus), côté autorité (LK05-T08).
-- Fiche : docs/annexes/conception/alerte.md. Java 42.21.0 cité en abrégé (J = zombie/...).
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
-- Le client ne fait que jouer le cri reçu (client/LivingKnox/LK_AlertView.lua) : aucune décision côté client.
--
-- 1. Entrée (Alert.observe, appelé par LivingKnox.Decisions.context pour chaque membre incarné évalué) : ce que perçoit
--    le membre (LivingKnox.Senses.perceived : zombies et joueurs vus ou entendus). Menace d'alerte (Alert.threatsOf) :
--      - zombie : clé "z:<onlineId>" ; sans identifiant réseau (solo : -1), clé commune "z?" ;
--      - joueur hostile : niveau d'attitude du groupe "hostile" (LivingKnox.Hostility ; sans paire : niveau de
--        départ du type) ;
--      - intrus : joueur INCONNU du groupe (aucune paire d'attitude : aucun fait vu ni attribuable, ou aucune
--        identité de personnage) ou envers qui le groupe est méfiant ("wary"). Un joueur connu prudent, favorable ou
--        confiant ne donne pas l'alerte.
--    Seulement si elle est près du membre (distance de la perception <= NEAR_MEMBER[genre]) ou près du foyer (écart
--    en x et en y <= NEAR_HOME[genre], au plus un étage d'écart). LK05-T14 : un zombie perçu à plus de
--    Config.zombieAlertDistance() cases du membre (option sandbox ZombieAlertDistance) ne compte jamais ; REACH et
--    SHOUT.zombie sont aussi réglables (AlertReach, AlertShoutZombie : Alert.reach, Alert.shoutRadius).
-- 2. Niveau (0..100, par groupe) : une menace porte le niveau à LEVEL[genre] au moins, chaque menace nouvelle de la
--    même alerte ajoute EXTRA ; il retombe de DECAY par minute de jeu depuis la dernière observation ; à CALM ou
--    moins, l'alerte retombe (Alert.update, à chaque passage du cadre de décision).
-- 3. Une seule fois par menace : chaque clé est gardée FORGET_MIN minutes de jeu après sa dernière observation. Une
--    alerte n'est DÉCLENCHÉE (cri, journal du groupe, écouteurs onRaised) que par une menace nouvelle quand le groupe
--    est calme, ou par une menace plus grave que celle de l'alerte en cours (zombie < intrus < hostile). Une menace
--    déjà connue revue après le calme rallume l'alerte sans cri ni écouteur ; une autre menace pendant l'alerte la
--    rejoint (niveau, dernière position connue) sans cri.
-- 4. Effets, portés par la cascade de LK_Decisions : membres à REACH cases au plus de l'origine ou de la dernière
--    position connue, ou au foyer : comportement "alert" (règle threat, rang 1) : tâches et corvées interrompues,
--    dormeurs réveillés (geste assis remis debout), vigilance "guard", regard vers la DERNIÈRE POSITION CONNUE de la
--    menace (partagée par tout le groupe, I2.4), geste de garde (combattant) ou accroupi (non-combattant ; loin du
--    foyer, il y court d'abord). Alerte retombée : la cascade reprend la routine.
-- 5. Cri (Alert.cry, au déclenchement) par le membre qui a vu la menace : réplique "alert" de LivingKnox.Speech
--    (bulle aux auditeurs, s'il y en a), bruit du monde addSound(nil, x, y, z, rayon, volume) qui attire les zombies
--    (rayon SHOUT[genre] ; cri vanilla d'un personnage : 30, J/characters/IsoGameCharacter.java:4821-4888 ; bruit
--    relayé aux clients par le serveur, J/WorldSoundManager.java:107-150) et voix vanilla VoiceMaleShoutHey ou
--    VoiceFemaleShoutHey (scripts sounds_player_voice_*.txt) jouée localement par chaque client proche : commande
--    serveur "alertCry" aux destinataires du relais des consignes (Directives.targets : joueurs à 100 cases et
--    propriétaire), appel direct de LivingKnox.AlertView.receive en solo. Même entrée (même identifiant) pour tous.
-- 6. Portes et autres sous-systèmes : Alert.subscribe(nom, { raised = fn(gid, info, event), calm = fn(gid, info) })
--    ; Alert.onRaised(gid, a, event) et Alert.onCalm(gid, a) appellent les écouteurs (erreur isolée et journalisée).
-- Mémoire seulement (non sauvegardé) : alertes en cours, menaces connues. Coût : une évaluation lit au plus les
-- entrées de la perception (4 joueurs, 6 zombies) ; Alert.update parcourt les groupes en alerte.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"

local Alert = LivingKnox.Alert or {}
LivingKnox.Alert = Alert

Alert.MODULE = "LivingKnox"
Alert.CMD = "alertCry"
Alert.KINDS = { "zombie", "intruder", "hostile" }   -- ordre = gravité croissante
Alert.SEVERITY = { zombie = 1, intruder = 2, hostile = 3 }
Alert.VOICES = { male = "VoiceMaleShoutHey", female = "VoiceFemaleShoutHey" }   -- sounds_player_voice_*.txt

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche ; à recalibrer en jeu).
Alert.CFG = Alert.CFG or {
    NEAR_MEMBER = { zombie = 10, intruder = 8, hostile = 20 },   -- cases : menace près du membre qui la perçoit
    NEAR_HOME = { zombie = 15, intruder = 12, hostile = 25 },    -- cases : menace près du foyer (x et y)
    LEVEL = { zombie = 45, intruder = 50, hostile = 80 },        -- niveau porté par une menace
    EXTRA = 10,              -- niveau ajouté par menace nouvelle d'une alerte en cours
    MAX = 100,
    DECAY = 5,               -- niveau perdu par minute de jeu sans observation
    CALM = 10,               -- niveau à partir duquel (et en dessous) l'alerte retombe
    FORGET_MIN = 60,         -- minutes de jeu : une menace revue dans ce délai ne redéclenche rien
    REACH = 30,              -- cases (un étage = 3 cases) : membres alertés autour de l'origine ou de la menace
    SHOUT = { zombie = 15, intruder = 20, hostile = 30 },        -- rayon et volume du bruit du cri (vanilla : 30)
    MAX_KNOWN = 32,          -- menaces gardées au plus par groupe (les plus anciennes oubliées)
    SPEECH_RANGE = 30,       -- cases : portée de la bulle du cri (Speech.bark)
}

Alert.state = Alert.state or { groups = {}, n = 0 }
Alert.listeners = Alert.listeners or {}
Alert.stats = Alert.stats or { observed = 0, raised = 0, escalated = 0, joined = 0, resumed = 0, repeated = 0,
    calmed = 0, cries = 0, barks = 0, sent = 0, noises = 0, woken = 0, listenerErrors = 0 }

local function log() return LivingKnox.Log end
local function cfg() return Alert.CFG end

-- LK05-T14 : seuils réglables (options sandbox, LivingKnox.Config.danger) ; repli : valeurs de CFG.
-- Portée de l'alerte (cases, un étage = 3 cases).
function Alert.reach() return LivingKnox.Config.danger("AlertReach", cfg().REACH) end
-- Rayon (et volume) du bruit du cri pour une alerte de genre kind ; zombie : option AlertShoutZombie.
function Alert.shoutRadius(kind)
    local c = cfg()
    if kind == "zombie" or c.SHOUT[kind] == nil then return LivingKnox.Config.danger("AlertShoutZombie", c.SHOUT.zombie) end
    return c.SHOUT[kind]
end

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function count(name)
    Alert.stats[name] = (Alert.stats[name] or 0) + 1
end

-- ================================================================ menaces (pur)

-- Genre d'alerte d'un joueur pour le groupe gid de type gtype : "hostile", "intruder" (inconnu ou méfiant) ou nil.
-- Hostility absent : inconnu.
function Alert.playerKind(gid, gtype, player)
    local Ho = LivingKnox.Hostility
    if Ho == nil or Ho.get == nil then return "intruder" end
    local key = Ho.keyOf ~= nil and player ~= nil and Ho.keyOf(player) or nil
    local known = key ~= nil and Ho.isKnown ~= nil and Ho.isKnown(gid, key) == true
    local view = known and Ho.get(gid, key) or nil
    local level
    if view ~= nil then level = view.level else level = Ho.levelOf(Ho.startFor(gtype)) end
    if level == "hostile" then return "hostile" end
    if not known or level == "wary" then return "intruder" end
    return nil
end

-- Vrai si la menace t ({ kind, x, y, z, d }) est près du membre (t.d) ou du foyer home ({ x, y, z } ou nil).
function Alert.isNear(t, home)
    local c = cfg()
    if (t.d or 1e9) <= c.NEAR_MEMBER[t.kind] then return true end
    if home == nil then return false end
    return math.abs((t.z or 0) - home.z) <= 1 and cheb(t.x, t.y, home.x, home.y) <= c.NEAR_HOME[t.kind]
end

-- Menaces d'alerte d'une perception (Senses.perceived) : { { kind, key, label, x, y, z, d, seen }, ... } triées par
-- gravité décroissante, distance, clé. kinds : { [compte] = genre } des joueurs perçus (Alert.playerKind). Perception
-- absente ou périmée : aucune. LK05-T14 : zombie perçu au-delà de Config.zombieAlertDistance() du membre : ignoré
-- (même près du foyer).
function Alert.threatsOf(per, kinds, home)
    local out = {}
    if per == nil or per.stale then return out end
    local zmax = LivingKnox.Config.zombieAlertDistance()
    for _, e in ipairs(per.z or {}) do
        if (e.s or e.h) and finite(e.x) and finite(e.y) and (zmax == nil or (e.d or 0) <= zmax) then
            local o = e.o
            local key = (finite(o) and o >= 0) and ("z:" .. string.format("%d", math.floor(o))) or "z?"
            local t = { kind = "zombie", key = key, label = key, x = math.floor(e.x), y = math.floor(e.y),
                z = math.floor(e.z or 0), d = e.d or 0, seen = e.s == true }
            if Alert.isNear(t, home) then out[#out + 1] = t end
        end
    end
    for _, e in ipairs(per.p or {}) do
        local kind = kinds[e.u]
        if (e.s or e.h) and kind ~= nil and finite(e.x) and finite(e.y) then
            local t = { kind = kind, key = "p:" .. tostring(e.u), label = tostring(e.u), x = math.floor(e.x),
                y = math.floor(e.y), z = math.floor(e.z or 0), d = e.d or 0, seen = e.s == true }
            if Alert.isNear(t, home) then out[#out + 1] = t end
        end
    end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return Alert.SEVERITY[a.kind] > Alert.SEVERITY[b.kind] end
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    return out
end

-- Niveau de l'alerte a à la minute de jeu minute (baisse de DECAY par minute depuis a.at).
function Alert.levelAt(a, minute)
    if a == nil then return 0 end
    local gone = math.max(0, (minute or a.at) - a.at)
    return math.max(0, a.level - cfg().DECAY * gone)
end

-- ================================================================ état (autorité)

local function groupState(gid)
    local st = Alert.state.groups[gid]
    if st == nil then
        st = { known = {}, alert = nil }
        Alert.state.groups[gid] = st
    end
    return st
end

local function forgetOld(st, minute)
    local old, n = {}, 0
    for key, k in pairs(st.known) do
        if minute - k.last > cfg().FORGET_MIN then old[#old + 1] = key else n = n + 1 end
    end
    for _, key in ipairs(old) do st.known[key] = nil end
    if n <= cfg().MAX_KNOWN then return end
    local list = {}
    for key, k in pairs(st.known) do list[#list + 1] = { key = key, last = k.last } end
    table.sort(list, function(a, b)
        if a.last ~= b.last then return a.last < b.last end
        return a.key < b.key
    end)
    for i = 1, n - cfg().MAX_KNOWN do st.known[list[i].key] = nil end
end

-- Vue publique d'une alerte (copie) : { id, gid, kind, key, label, x, y, z (dernière position connue), level, since,
-- threats, spotter, origin = { x, y, z }, home }.
local function view(gid, a, minute)
    if a == nil then return nil end
    return { id = a.id, gid = gid, kind = a.kind, key = a.key, label = a.label, x = a.x, y = a.y, z = a.z,
        level = math.floor(Alert.levelAt(a, minute) + 0.5), since = a.since, threats = a.n, spotter = a.spotter,
        origin = { x = a.ox, y = a.oy, z = a.oz }, home = a.home and { x = a.home.x, y = a.home.y, z = a.home.z } or nil }
end

local function isActive(a, minute)
    return a ~= nil and Alert.levelAt(a, minute) > cfg().CALM
end

-- Note une menace t perçue par le membre spot = { npc, mid, x, y, z, female } du groupe gid (foyer home) à la minute
-- minute. Rend l'événement : "raised" (nouvelle alerte), "escalated" (menace plus grave), "joined" (autre menace
-- nouvelle de l'alerte en cours), "seen" (menace de l'alerte revue), "resumed" (menace connue revue après le calme,
-- sans cri), et l'alerte (table interne).
function Alert.note(gid, t, spot, minute, home)
    local c = cfg()
    local st = groupState(gid)
    forgetOld(st, minute)
    local k = st.known[t.key]
    local fresh = k == nil
    st.known[t.key] = { first = fresh and minute or k.first, last = minute, kind = t.kind }
    local a = st.alert
    if a ~= nil and not isActive(a, minute) then
        Alert.calm(gid, minute)
        a = nil
    end
    local base = c.LEVEL[t.kind]
    if a == nil then
        Alert.state.n = Alert.state.n + 1
        a = { id = "al-" .. Alert.state.n, kind = t.kind, key = t.key, label = t.label, x = t.x, y = t.y, z = t.z,
            level = base, at = minute, since = minute, n = 1, keys = { [t.key] = true }, spotter = spot.npc,
            mid = spot.mid, ox = math.floor(spot.x), oy = math.floor(spot.y), oz = spot.z, home = home }
        st.alert = a
        if fresh then return "raised", a end
        return "resumed", a
    end
    a.level = math.min(c.MAX, math.max(Alert.levelAt(a, minute), base))
    a.at = minute
    local event = "seen"
    if not a.keys[t.key] then
        a.keys[t.key] = true
        a.n = a.n + 1
        a.level = math.min(c.MAX, a.level + c.EXTRA)
        event = "joined"
        if fresh and Alert.SEVERITY[t.kind] > Alert.SEVERITY[a.kind] then
            event = "escalated"
            a.spotter, a.mid = spot.npc, spot.mid
            a.ox, a.oy, a.oz = math.floor(spot.x), math.floor(spot.y), spot.z
        end
    end
    -- Dernière position connue (I2.4) : celle de la menace la plus grave observée en dernier.
    if Alert.SEVERITY[t.kind] >= Alert.SEVERITY[a.kind] then
        a.kind, a.key, a.label, a.x, a.y, a.z = t.kind, t.key, t.label, t.x, t.y, t.z
    end
    return event, a
end

-- ================================================================ écouteurs (portes : LK_Obstacles)

-- Écouteur nommé : handlers = { raised = function(gid, info, event), calm = function(gid, info) } (l'un ou l'autre).
-- Rend vrai. Un même nom remplace l'écouteur précédent (rechargement sans doublon).
function Alert.subscribe(name, handlers)
    if type(name) ~= "string" or type(handlers) ~= "table" then return false end
    for i, l in ipairs(Alert.listeners) do
        if l.name == name then
            Alert.listeners[i] = { name = name, h = handlers }
            return true
        end
    end
    Alert.listeners[#Alert.listeners + 1] = { name = name, h = handlers }
    return true
end

function Alert.unsubscribe(name)
    for i, l in ipairs(Alert.listeners) do
        if l.name == name then
            table.remove(Alert.listeners, i)
            return true
        end
    end
    return false
end

local function dispatch(what, gid, info, event)
    for _, l in ipairs(Alert.listeners) do
        local fn = l.h[what]
        if type(fn) == "function" then
            local ok, err = pcall(fn, gid, info, event)
            if not ok then
                count("listenerErrors")
                log().warn("alert listener %s (%s) failed for group %s: %s", l.name, what, tostring(gid), tostring(err))
            end
        end
    end
end

-- Alerte déclenchée (event "raised") ou aggravée ("escalated") : écouteurs « raised ». Point d'entrée des portes.
function Alert.onRaised(gid, a, event, minute)
    dispatch("raised", gid, view(gid, a, minute), event or "raised")
end

-- Alerte retombée : écouteurs « calm ».
function Alert.onCalm(gid, a, minute)
    dispatch("calm", gid, view(gid, a, minute), "calm")
end

-- ================================================================ cri (autorité)

-- Voix du cri d'un membre (femme : VoiceFemaleShoutHey).
function Alert.voiceOf(female)
    if female then return Alert.VOICES.female end
    return Alert.VOICES.male
end

-- Cri du membre spot (corps body) pour l'alerte a du groupe gid : réplique, bruit, voix aux clients proches. Rend
-- l'entrée envoyée.
function Alert.cry(gid, a, spot, body)
    local c = cfg()
    local x, y, z = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
    local entry = { id = a.id .. "-" .. a.n, gid = gid, npc = spot.npc, o = body:getOnlineID(), x = x, y = y, z = z,
        s = Alert.voiceOf(spot.female), k = a.kind }
    count("cries")
    local Sp = LivingKnox.Speech
    if Sp ~= nil and Sp.bark ~= nil then
        local out, why = Sp.bark(spot.npc, "alert", { range = c.SPEECH_RANGE })
        if out ~= nil then
            count("barks")
        else
            log().debug("npc %s: alert line not said: %s", spot.npc, tostring(why))
        end
    end
    local r = Alert.shoutRadius(a.kind)
    if addSound ~= nil then
        addSound(nil, x, y, z, r, r)
        count("noises")
    end
    if isServer() then
        local D = LivingKnox.Directives
        local targets = D ~= nil and D.targets ~= nil and D.targets(body) or {}
        local names = {}
        for name in pairs(targets) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            sendServerCommand(targets[name], Alert.MODULE, Alert.CMD, { c = entry })
            count("sent")
        end
    else
        local V = LivingKnox.AlertView
        if V ~= nil and V.receive ~= nil then V.receive(entry) end
    end
    return entry
end

-- ================================================================ points d'entrée (LK_Decisions)

-- Membre incarné évalué : menaces de sa perception per notées pour son groupe. m = membre du registre (npc,
-- female), body = corps, players = joueurs vivants (pour l'attitude). Rend le nombre de menaces notées.
function Alert.observe(gid, g, mid, m, body, per, players, minute)
    if not LivingKnox.isAuthority() or per == nil or minute == nil then return 0 end
    local kinds = {}
    if #(per.p or {}) > 0 then
        local byName = {}
        for _, p in ipairs(players or {}) do byName[p:getUsername()] = p end
        for _, e in ipairs(per.p) do
            if kinds[e.u] == nil and byName[e.u] ~= nil then kinds[e.u] = Alert.playerKind(gid, g.type, byName[e.u]) end
        end
    end
    local list = Alert.threatsOf(per, kinds, g.home)
    if #list == 0 then return 0 end
    local female = m.female
    if female == nil and body.isFemale ~= nil then female = body:isFemale() end
    local spot = { npc = m.npc, mid = mid, x = body:getX(), y = body:getY(), z = math.floor(body:getZ()),
        female = female == true }
    for _, t in ipairs(list) do
        count("observed")
        Alert.raise(gid, t, spot, body, minute, g.home)
    end
    return #list
end

-- Menace t notée pour le groupe gid par le membre spot (corps body), foyer home : journal, cri et écouteurs si
-- l'alerte est nouvelle ou plus grave. how : mot du journal du groupe (« seen by » par défaut ; LK06-T05 : « called
-- by » pour un appel à l'aide après un coup reçu). Rend l'événement de Alert.note et l'alerte.
function Alert.raise(gid, t, spot, body, minute, home, how)
    local event, a = Alert.note(gid, t, spot, minute, home)
    count(event == "seen" and "repeated" or event)
    if event == "raised" or event == "escalated" then
        log().info("group %s alert %s %s by %s (%s): %s %s at %d,%d,%d, level %d", gid, a.id, event, spot.npc,
            spot.mid, t.kind, t.label, t.x, t.y, t.z, math.floor(Alert.levelAt(a, minute) + 0.5))
        local G = LivingKnox.Groups
        if G ~= nil and G.addLog ~= nil then
            G.addLog(gid, "alert", string.format("%s %s near %d,%d,%d (%s %s)", t.kind, t.label, t.x, t.y, t.z,
                how or "seen by", spot.mid))
        end
        Alert.cry(gid, a, spot, body)
        Alert.onRaised(gid, a, event, minute)
    elseif event == "joined" or event == "resumed" then
        log().info("group %s alert %s %s: %s %s at %d,%d,%d, level %d", gid, a.id, event, t.kind, t.label, t.x,
            t.y, t.z, math.floor(Alert.levelAt(a, minute) + 0.5))
    end
    return event, a
end

-- Alerte qui concerne un membre du groupe gid en (x, y, z), au foyer ou non, à la minute minute ; ou nil :
-- { id, key = "alert:<id>", kind, label, x, y, z (dernière position connue), d (distance du membre), level }.
function Alert.forMember(gid, x, y, z, atHome, minute)
    local st = Alert.state.groups[gid]
    local a = st and st.alert or nil
    if not isActive(a, minute) then return nil end
    local reach = Alert.reach()
    local function within(px, py, pz)
        return cheb(x, y, px + 0.5, py + 0.5) + 3 * math.abs(z - pz) <= reach
    end
    if not atHome and not within(a.ox, a.oy, a.oz) and not within(a.x, a.y, a.z) then return nil end
    local dx, dy = a.x + 0.5 - x, a.y + 0.5 - y
    return { id = a.id, key = "alert:" .. a.id, kind = a.kind, label = a.label, x = a.x, y = a.y, z = a.z,
        d = math.floor(math.sqrt(dx * dx + dy * dy) * 10 + 0.5) / 10,
        level = math.floor(Alert.levelAt(a, minute) + 0.5) }
end

-- Fin d'une alerte du groupe gid (niveau retombé) : journal, écouteurs « calm ».
function Alert.calm(gid, minute)
    local st = Alert.state.groups[gid]
    local a = st and st.alert or nil
    if a == nil then return false end
    st.alert = nil
    count("calmed")
    log().info("group %s alert %s calm after %d min (%d threat(s), last %s %s at %d,%d,%d)", gid, a.id,
        math.max(0, (minute or a.at) - a.since), a.n, a.kind, a.label, a.x, a.y, a.z)
    Alert.onCalm(gid, a, minute)
    return true
end

-- Passage du cadre de décision : alertes retombées closes. Rend le nombre d'alertes closes.
function Alert.update(minute)
    if minute == nil then return 0 end
    local ids = {}
    for gid, st in pairs(Alert.state.groups) do
        if st.alert ~= nil and not isActive(st.alert, minute) then ids[#ids + 1] = gid end
    end
    table.sort(ids)
    for _, gid in ipairs(ids) do Alert.calm(gid, minute) end
    return #ids
end

-- Dormeur réveillé par l'alerte (compteur, journal du moteur).
function Alert.noteWoken(gid, npc)
    count("woken")
    log().debug("npc %s (%s): woken by the alert", tostring(npc), tostring(gid))
end

-- Alerte en cours du groupe gid (vue publique), ou nil.
function Alert.get(gid, minute)
    local st = Alert.state.groups[gid]
    local a = st and st.alert or nil
    if a == nil then return nil end
    return view(gid, a, minute or a.at)
end

-- Vrai si le groupe gid est en alerte à la minute minute.
function Alert.isActive(gid, minute)
    local st = Alert.state.groups[gid]
    return st ~= nil and isActive(st.alert, minute)
end

-- Groupe dissous ou retiré : mémoire oubliée.
function Alert.forget(gid)
    Alert.state.groups[gid] = nil
end

function Alert.reset()
    Alert.state = { groups = {}, n = 0 }
end

return Alert
