-- Living Knox : relais des gestes et des poses vers les clients proches, filtré et borné (LK03-T05).
-- Fiche : docs/conception/corps-et-animations.md, « Relais des gestes ». Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Serveur MP seulement. Solo : rien (la seule machine lit LivingKnox.Anim et Directives.poses directement). Un client
-- MP charge aussi media/lua/server : il s'arrête à la première ligne.
--
-- Ce qui est relayé, par PNJ : le geste voulu (LivingKnox.Anim.setGesture, lu par Anim.gestureOf) et la dernière pose
-- acceptée d'un rapport d'exécution (Directives.poses). Chaque changement « touche » le PNJ (Relay.touch) ; à chaque
-- image du serveur :
--   1. publication : au plus un état par PNJ et par Config.RELAY.WINDOW_MS ; l'état publié est l'état courant à cet
--      instant (dernier état gagnant : plusieurs changements de la fenêtre n'en font qu'un). Exception : un geste
--      ponctuel important (KEEP_GESTURES : strike) ou une pose finale (arrived, stopped, faced, failed) remplacé avant
--      d'être publié est gardé (MAX_KEPT au plus) et publié d'abord, chacun dans sa fenêtre ; un état gardé ou
--      important déjà publié n'est remplacé qu'une fois remis à tous ses destinataires (jamais sauté par un client
--      différé) ;
--   2. destinataires : ceux des consignes (Directives.targets : joueurs à NEAR_RADIUS cases du corps, et le
--      propriétaire), recalculés à chaque publication et toutes les SCAN_EVERY images. Entré dans le rayon : l'état
--      courant ; sorti : { gone } ; PNJ disparu (unknown, dead, virtual) : { gone } à tous ses détenteurs ;
--   3. envoi : UN message par client et par image, tous ses PNJ regroupés (commande "animState", module
--      "LivingKnox") : { d = { [npcId] = { r, g, fa, p = { pr, v, s, a, x, y, z, t, ts } } | { r, gone = true } } }.
--      r : numéro d'envoi croissant (le client garde le plus grand par PNJ ; livraison RELIABLE non ordonnée, base
--      multiplayer.md) ; p absent sans pose. Budget : MAX_PER_TICK messages par image au total ; les clients au-delà
--      gardent leur tour et passent en tête à l'image suivante (rien n'est perdu : chaque envoi porte l'état courant).
--   Client qui entre en partie ("guardHello") : tout ce qui est à sa portée, à l'image suivante.
-- Mesure : Relay.stats (messages, entrées, octets estimés comme la sonde du mod de dev, par client et au total ; dernière
-- seconde complète et maximum ; délai d'émission changement -> envoi, dernier, maximum, moyenne ; différés par le
-- budget) et une ligne DEBUG par seconde de trafic.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_ZombieGuard"
require "LivingKnox/LK_Anim"
require "LivingKnox/LK_Directives"

local Relay = LivingKnox.Relay or {}
LivingKnox.Relay = Relay

Relay.MODULE = "LivingKnox"
Relay.CMD = LivingKnox.Anim.CMD_STATE   -- "animState"
Relay.FINAL = { arrived = true, stopped = true, faced = true, failed = true }

Relay.items = Relay.items or {}     -- npcId -> { cur, kept = { ... }, dirty, pub, pubMs }
Relay.near = Relay.near or {}       -- npcId -> { [compte] = joueur } destinataires au dernier calcul
Relay.sent = Relay.sent or {}       -- compte -> { [npcId] = numéro de publication remis }
Relay.players = Relay.players or {} -- compte -> joueur (dernier connu)
Relay.todo = Relay.todo or {}       -- compte -> { [npcId] = true } à examiner au prochain envoi
Relay.queue = Relay.queue or {}     -- comptes en attente d'envoi, dans l'ordre
Relay.queued = Relay.queued or {}   -- compte -> vrai s'il est dans la file
Relay.state = Relay.state or { pub = 0, r = 0, ticks = 0 }
Relay.meter = Relay.meter or { startMs = nil, msgs = 0, bytes = 0, byClient = {} }

local function newStats()
    return { touched = 0, coalesced = 0, kept = 0, keptDropped = 0, keptMaxDelay = -1, published = 0, messages = 0, entries = 0,
        gone = 0, bytes = 0, deferred = 0, maxPerTick = 0, samples = 0, sumDelay = 0, lastDelay = -1, maxDelay = -1,
        second = { msgs = 0, bytes = 0, ms = 0, byClient = {} }, maxMsgsPerSec = 0, maxBytesPerSec = 0, byClient = {} }
end
Relay.stats = Relay.stats or newStats()

local function cfg() return LivingKnox.Config.RELAY end
local function log() return LivingKnox.Log end
local function D() return LivingKnox.Directives end
local function now() return getTimestampMs() end

-- Taille approximative d'arguments réseau (même règle que la sonde du mod de dev : chaînes et clés par leur longueur,
-- nombres 8, booléens 1, tables 2 plus leur contenu).
function Relay.sizeOf(v, depth)
    local t = type(v)
    if t == "string" then return string.len(v) end
    if t == "number" then return 8 end
    if t == "boolean" then return 1 end
    if t ~= "table" then return 0 end
    depth = depth or 0
    if depth > 8 then return 0 end
    local n = 2
    for k, x in pairs(v) do n = n + Relay.sizeOf(k, depth + 1) + Relay.sizeOf(x, depth + 1) end
    return n
end

-- État courant d'un PNJ : geste affiché (geste ponctuel en cours et son angle fa, LK04-T13, sinon geste voulu) et
-- dernière pose acceptée (copie sûre pour le réseau).
local function snapshot(id)
    local A = LivingKnox.Anim
    local s = { g = A.shownOf(id), ms = now() }
    local act, fa = A.actOf(id)
    if act ~= nil and type(fa) == "number" then s.fa = fa end
    local pose = D().poses[id]
    if pose ~= nil then
        s.p = { pr = pose.pr, v = pose.v, s = pose.s, a = pose.a, x = pose.x, y = pose.y, z = pose.z, t = pose.t,
            ts = pose.ts }
    end
    return s
end

local function important(s)
    return cfg().KEEP_GESTURES[s.g] == true or (s.p ~= nil and Relay.FINAL[s.p.s] == true)
end

-- Vrai si remplacer prev par new ferait perdre un geste ponctuel important ou une pose finale.
local function wouldLose(prev, new)
    if prev == nil then return false end
    if cfg().KEEP_GESTURES[prev.g] and new.g ~= prev.g then return true end
    return prev.p ~= nil and Relay.FINAL[prev.p.s] == true and (new.p == nil or new.p.pr ~= prev.p.pr)
end

-- Autorité MP : le geste ou la pose du PNJ id vient de changer. Rend vrai si noté.
function Relay.touch(id)
    if not isServer() or type(id) ~= "string" then return false end
    local st = Relay.stats
    local it = Relay.items[id]
    if it == nil then
        it = { kept = {} }
        Relay.items[id] = it
    end
    local new = snapshot(id)
    st.touched = st.touched + 1
    if it.dirty then
        st.coalesced = st.coalesced + 1
        if wouldLose(it.cur, new) then
            if #it.kept < cfg().MAX_KEPT then
                it.kept[#it.kept + 1] = it.cur
                st.kept = st.kept + 1
            else
                st.keptDropped = st.keptDropped + 1
                log().warn("npc %s: gesture relay keeps %d states already, %s dropped", id, #it.kept,
                    tostring(it.cur.g))
            end
        end
    end
    it.cur, it.dirty = new, true
    return true
end

local function want(name, id)
    local t = Relay.todo[name]
    if t == nil then
        t = {}
        Relay.todo[name] = t
    end
    t[id] = true
    if not Relay.queued[name] then
        Relay.queued[name] = true
        Relay.queue[#Relay.queue + 1] = name
    end
end

-- PNJ disparu : { gone } à chaque client qui en a un état, puis oubli.
function Relay.drop(id)
    for name, s in pairs(Relay.sent) do
        if s[id] ~= nil then want(name, id) end
    end
    Relay.items[id], Relay.near[id] = nil, nil
end

-- Destinataires du PNJ id recalculés ; clients à servir notés (état publié non remis, ou sortis du rayon). Corps
-- absent de la zone chargée, ou liste des joueurs vide (reconnexion) : destinataires gardés.
function Relay.refresh(id)
    local it = Relay.items[id]
    if it == nil then return end
    local B = LivingKnox.Bodies
    if B == nil then return end
    local z, where = B.find(id)
    if z == nil then
        if where == "unknown" or where == "dead" or where == "virtual" then Relay.drop(id) end
        return
    end
    local targets, any = D().targets(z)
    if not any then return end
    Relay.near[id] = targets
    local n = it.pub and it.pub.n
    for name, p in pairs(targets) do
        Relay.players[name] = p
        local s = Relay.sent[name]
        if n ~= nil and (s == nil or s[id] ~= n) then want(name, id) end
    end
    for name, s in pairs(Relay.sent) do
        if s[id] ~= nil and targets[name] == nil then want(name, id) end
    end
end

-- Vrai si le PNJ peut publier un nouvel état à l'instant t.
local function mayPublish(id, it, t)
    if not it.dirty and #it.kept == 0 then return false end
    if it.pubMs ~= nil and t - it.pubMs < cfg().WINDOW_MS then return false end
    local pub = it.pub
    if pub ~= nil and pub.keep then   -- état important : remis à tous ses destinataires avant d'être remplacé
        for name in pairs(Relay.near[id] or {}) do
            local s = Relay.sent[name]
            if s == nil or s[id] ~= pub.n then return false end
        end
    end
    return true
end

local function publish(id, it, t)
    local snap
    if #it.kept > 0 then
        snap = table.remove(it.kept, 1)
        snap.keep, snap.held = true, true
    else
        snap = it.cur
        snap.keep = important(snap)
        it.dirty = false
    end
    local st = Relay.state
    st.pub = st.pub + 1
    snap.n = st.pub
    it.pub, it.pubMs = snap, t
    Relay.stats.published = Relay.stats.published + 1
    Relay.refresh(id)
end

local function nextR()
    local st = Relay.state
    st.r = st.r + 1
    return st.r
end

local function wire(s, r)
    local out = { r = r, g = s.g, fa = s.fa }
    if s.p ~= nil then
        local p = s.p
        out.p = { pr = p.pr, v = p.v, s = p.s, a = p.a, x = p.x, y = p.y, z = p.z, t = p.t, ts = p.ts }
    end
    return out
end

local function sample(delay)
    local st = Relay.stats
    st.samples = st.samples + 1
    st.sumDelay = st.sumDelay + delay
    st.lastDelay = delay
    if delay > st.maxDelay then st.maxDelay = delay end
end

local function meterAdd(name, bytes)
    local m = Relay.meter
    m.msgs = m.msgs + 1
    m.bytes = m.bytes + bytes
    local c = m.byClient[name]
    if c == nil then
        c = { msgs = 0, bytes = 0 }
        m.byClient[name] = c
    end
    c.msgs = c.msgs + 1
    c.bytes = c.bytes + bytes
    local st = Relay.stats
    st.messages = st.messages + 1
    st.bytes = st.bytes + bytes
    local total = st.byClient[name]
    if total == nil then
        total = { msgs = 0, bytes = 0 }
        st.byClient[name] = total
    end
    total.msgs = total.msgs + 1
    total.bytes = total.bytes + bytes
end

-- Message du client name : états publiés non remis des PNJ notés, { gone } de ceux qu'il ne doit plus avoir. Rend
-- vrai si un message est parti.
local function sendTo(name, t)
    local todo = Relay.todo[name]
    if todo == nil then return false end
    local s = Relay.sent[name]
    if s == nil then
        s = {}
        Relay.sent[name] = s
    end
    local d, n = {}, 0
    for id in pairs(todo) do
        local it = Relay.items[id]
        local near = Relay.near[id]
        if it ~= nil and it.pub ~= nil and near ~= nil and near[name] ~= nil then
            if s[id] ~= it.pub.n then
                if s[id] ~= nil then   -- client déjà servi : délai changement -> envoi
                    local delay = t - it.pub.ms
                    if it.pub.held then   -- état gardé : publié après la fenêtre suivante, compté à part
                        if delay > Relay.stats.keptMaxDelay then Relay.stats.keptMaxDelay = delay end
                    else
                        sample(delay)
                    end
                end
                d[id] = wire(it.pub, nextR())
                s[id] = it.pub.n
                n = n + 1
            end
        elseif s[id] ~= nil then
            d[id] = { r = nextR(), gone = true }
            s[id] = nil
            n = n + 1
            Relay.stats.gone = Relay.stats.gone + 1
        end
    end
    local player = Relay.players[name]
    if n == 0 or player == nil then return false end
    local args = { d = d }
    sendServerCommand(player, Relay.MODULE, Relay.CMD, args)
    Relay.stats.entries = Relay.stats.entries + n
    meterAdd(name, Relay.sizeOf(args))
    return true
end

-- Envoi de l'image : un message par client en attente, MAX_PER_TICK au plus ; les autres gardent leur rang.
function Relay.flush(t)
    local budget = cfg().MAX_PER_TICK
    local queue = Relay.queue
    local rest, sent = {}, 0
    for i = 1, #queue do
        local name = queue[i]
        if sent < budget then
            if sendTo(name, t) then sent = sent + 1 end
            Relay.todo[name], Relay.queued[name] = nil, nil
        else
            rest[#rest + 1] = name
        end
    end
    Relay.queue = rest
    local st = Relay.stats
    st.deferred = st.deferred + #rest
    if sent > st.maxPerTick then st.maxPerTick = sent end
    return sent
end

local function clientLine(byClient)
    local names = {}
    for name in pairs(byClient) do names[#names + 1] = name end
    table.sort(names)
    local parts = {}
    for i, name in ipairs(names) do
        local c = byClient[name]
        parts[i] = string.format("%s %d/%dB", name, c.msgs, c.bytes)
    end
    return table.concat(parts, ", ")
end
Relay.clientLine = clientLine

-- Compteurs par seconde : seconde écoulée gardée dans stats.second, maximums, ligne DEBUG si du trafic.
local function meterRoll(t)
    local m = Relay.meter
    if m.startMs == nil then
        m.startMs = t
        return
    end
    local ms = t - m.startMs
    if ms < 1000 then return end
    local st = Relay.stats
    st.second = { msgs = m.msgs, bytes = m.bytes, ms = ms, byClient = m.byClient }
    if m.msgs > st.maxMsgsPerSec then st.maxMsgsPerSec = m.msgs end
    if m.bytes > st.maxBytesPerSec then st.maxBytesPerSec = m.bytes end
    if m.msgs > 0 then
        log().debug("gesture relay: %d msg, %d B in %d ms (%s), %d deferred so far", m.msgs, m.bytes, ms,
            clientLine(m.byClient), st.deferred)
    end
    m.startMs, m.msgs, m.bytes, m.byClient = t, 0, 0, {}
end

-- Délai moyen d'émission (ms), ou -1 sans échantillon.
function Relay.meanDelay()
    local st = Relay.stats
    if st.samples == 0 then return -1 end
    return st.sumDelay / st.samples
end

-- Remise à zéro des compteurs (tests, suites en jeu).
function Relay.resetStats()
    Relay.stats = newStats()
    Relay.meter = { startMs = nil, msgs = 0, bytes = 0, byClient = {} }
end

-- Image du serveur : publications, destinataires (toutes les SCAN_EVERY images), envoi borné, compteurs.
function Relay.tick()
    if not isServer() then return end
    local st = Relay.state
    st.ticks = st.ticks + 1
    local scan = st.ticks >= cfg().SCAN_EVERY
    if scan then st.ticks = 0 end
    local t = now()
    if getCell() ~= nil then
        local ids = {}
        for id in pairs(Relay.items) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do   -- Relay.items modifiée (drop) hors de pairs
            local it = Relay.items[id]
            if it ~= nil then
                if mayPublish(id, it, t) then
                    publish(id, it, t)
                elseif scan then
                    Relay.refresh(id)
                end
            end
        end
    end
    Relay.flush(t)
    meterRoll(t)
end

-- Client entré en partie ("guardHello", première connexion ou reconnexion) : son état Lua est neuf ; tout état publié
-- d'un PNJ à sa portée (ou dont il est propriétaire) lui est envoyé à l'image suivante.
function Relay.onHello(player)
    local name = D().senderName(player)
    Relay.sent[name] = {}
    Relay.players[name] = player
    local B = LivingKnox.Bodies
    if B == nil then return 0 end
    local n = 0
    for id, it in pairs(Relay.items) do
        local z = B.find(id)
        if it.pub ~= nil and z ~= nil and (D().isNear(player, z) or D().isOwner(z, player)) then
            local near = Relay.near[id]
            if near == nil then
                near = {}
                Relay.near[id] = near
            end
            near[name] = player
            want(name, id)
            n = n + 1
        end
    end
    return n
end

function Relay.onClientCommand(module, command, player, args)
    if module ~= Relay.MODULE or command ~= LivingKnox.ZombieGuard.CMD_HELLO or not isServer() or player == nil then
        return
    end
    Relay.onHello(player)
end

if isServer() then
    local function onTick()
        LivingKnox.Relay.tick()
    end
    local function onClientCommand(module, command, player, args)
        LivingKnox.Relay.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnTick", "Relay.tick", onTick)
    LivingKnox.subscribe("OnClientCommand", "Relay.onClientCommand", onClientCommand)
end

return Relay
