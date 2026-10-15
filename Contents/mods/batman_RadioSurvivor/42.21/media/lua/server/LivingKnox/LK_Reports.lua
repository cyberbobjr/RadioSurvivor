-- Living Knox : rapports d'état des corps de PNJ, reçus et contrôlés par l'autorité (LK03-T02).
-- Fiche : docs/conception/rapports.md. Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Le propriétaire réel d'un corps (le client qui le simule ; en solo, la seule machine) rapporte son état : position,
-- orientation, activité (phase de l'exécution en cours), santé du zombie et pose (debout, au sol, rampant). Envoi
-- par LivingKnox.Executor (client/LivingKnox/LK_Executor.lua), commande "bodyReport" en MP, appel direct en solo,
-- à cadence bornée (Config.REPORTS : STATE_MS, MIN_MS, IDLE_MS).
--
-- Le serveur ne garde un rapport qu'après ces contrôles, dans cet ordre ; tout écart refuse le rapport ENTIER (état
-- gardé inchangé), compte la raison (stats.why) et écrit une ligne par (expéditeur, raison) et par minute (WARN si
-- le rapport est suspect, INFO pour une course attendue du réseau) ; corps absent ("no body", LK03-T07) : une seule
-- ligne par PNJ, expéditeur et absence (de nouveau après un rapport qui retrouve le corps) :
--   1. forme et bornes (activité et pose de listes fermées, niveaux -32..31, santé 0..32,767, angle) ;
--   2. corps présent ; expéditeur = propriétaire du corps (Directives.isOwner, getOwnerPlayer côté serveur) ; un
--      ANCIEN propriétaire encore persuadé de simuler le corps (LK03-T03, Directives.isPreviousOwner) : rapport
--      ignoré sans être compté comme refus (stats.ignored, INFO), course attendue du transfert ;
--   3. bail (LK03-T01, Directives.entries) : rapport sous le bail courant l, et expéditeur = exécutant désigné o ;
--      bail plus ancien : ignoré (course) ; plus grand que tout bail donné : refusé. PNJ sans consigne : bail 0 ;
--   4. cadence (seau à jetons par PNJ, RATE par seconde, BURST d'avance) ;
--   5. ordre : numéro n croissant pour un même expéditeur et un même bail (rapport rejoué ou plus ancien refusé ;
--      numéros remis à zéro à l'entrée en partie de l'expéditeur, "guardHello", comme le fait LK03-T01) ;
--   6. plausibilité : à MAX_GAP cases et MAX_LEVEL_GAP niveau de la copie du serveur ; depuis le dernier rapport
--      accepté pour le même objet de corps, déplacement au plus SLACK + MAX_SPEED x durée, montée et descente de
--      niveau bornées (chute du moteur, J/characters/IsoGameCharacter.java:8679-8685) ; santé non croissante, sauf
--      soin connu de l'autorité (Reports.noteHeal, crédit consommé par la hausse).
-- Aucun contrôle ne déplace le corps : un rapport refusé ne « téléporte » rien. Solo : mêmes contrôles (le joueur
-- local est le propriétaire), sauf les contrôles de durée (déplacement, niveaux) en accéléré (getGameSpeed() > 1),
-- l'horloge réelle ne mesurant plus le temps de jeu.
--
-- État accepté (mémoire seulement, perdu au redémarrage comme les consignes) : Reports.get(id) -> { x, y, z, a, act,
-- hp, pose, ms, by, l, n, t } ; lu par l'API et le transfert d'état (LK03-T03 : santé acceptée remise au nouveau
-- propriétaire par Directives.handState, qui l'applique à sa copie avant son premier rapport).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local Reports = LivingKnox.Reports or {}
LivingKnox.Reports = Reports

-- Constantes lues aussi par l'exécutant d'un client MP (qui charge media/lua/server mais s'arrête à la garde).
Reports.MODULE = "LivingKnox"
-- exécutant -> serveur : { id, l, n, x, y, z, a, act, hp, pose, t[, sen] } ; sen : résumé de perception (LK05-T01,
-- shared/LivingKnox/LK_Senses.lua), contrôlé (Senses.validate) puis gardé (Senses.accept) avec le rapport accepté.
Reports.CMD_REPORT = "bodyReport"
Reports.ACTIVITIES = { idle = true, moving = true, arrived = true, failed = true, stopped = true, faced = true }
Reports.POSES = { stand = true, floor = true, crawl = true }

if isClient() then return Reports end

require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Directives"
require "LivingKnox/LK_ZombieGuard"

Reports.states = Reports.states or {}   -- npcId -> dernier état accepté (avec l'objet du corps, champ body)
Reports.lastN = Reports.lastN or {}     -- npcId -> { by, l, n } dernier rapport accepté
Reports.heals = Reports.heals or {}     -- npcId -> santé de soin connue, pas encore consommée
Reports.buckets = Reports.buckets or {} -- npcId -> { tokens, ms }
Reports.warned = Reports.warned or {}
Reports.absent = Reports.absent or {}   -- npcId -> { [expéditeur] = true } : refus "no body" déjà écrit (LK03-T07)
Reports.rejectedBy = Reports.rejectedBy or {}   -- npcId -> { n, suspect } refus pendant que son corps était présent
Reports.stats = Reports.stats or { received = 0, accepted = 0, rejected = 0, ignored = 0, healed = 0, fastForward = 0,
    why = {} }

Reports.GONE = { unknown = true, dead = true, virtual = true }   -- états de Bodies.find : plus de corps à suivre

local function cfg() return LivingKnox.Config.REPORTS end
local function log() return LivingKnox.Log end
local function D() return LivingKnox.Directives end
local function Bodies() return LivingKnox.Bodies end

local function now() return getTimestampMs() end

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

-- Raisons suspectes (WARN) ; les autres sont des courses attendues du réseau (INFO).
Reports.SUSPECT = { ["bad report"] = true, ["out of bounds"] = true, ["not the owner"] = true,
    ["not the designated executor"] = true, ["unknown lease"] = true, ["too many reports"] = true,
    ["far from the body"] = true, ["other level than the body"] = true, ["too fast"] = true,
    ["impossible climb"] = true, ["impossible fall"] = true, ["health rose without a known heal"] = true }

local function reject(name, id, reason, detail, absent)
    local st = Reports.stats
    st.rejected = st.rejected + 1
    st.why[reason] = (st.why[reason] or 0) + 1
    -- Par PNJ (corps présent seulement : la table reste bornée, vidée par Reports.forget) : un passage MP en compte
    -- les refus d'UN PNJ sans ceux, attendus, des rapports en vol d'un PNJ retiré juste avant (campagne 2026-10-14).
    if type(id) == "string" and not absent then
        local c = Reports.rejectedBy[id]
        if c == nil then
            c = { n = 0, suspect = 0 }
            Reports.rejectedBy[id] = c
        end
        c.n = c.n + 1
        if Reports.SUSPECT[reason] then c.suspect = c.suspect + 1 end
    end
    local key = tostring(name) .. "|" .. reason
    local last = Reports.warned[key]
    if last == nil or now() - last >= cfg().WARN_EVERY_MS then
        Reports.warned[key] = now()
        local say = Reports.SUSPECT[reason] and log().warn or log().info
        say("state report on npc %s from %s refused: %s%s", tostring(id), tostring(name), reason,
            detail and (" (" .. detail .. ")") or "")
    end
    return false, reason
end

-- Corps absent (LK03-T07) : refus compté à chaque fois, écrit une seule fois par PNJ, expéditeur et absence.
local function rejectAbsent(name, id, where)
    local seen = Reports.absent[id]
    if seen == nil then
        seen = {}
        Reports.absent[id] = seen
    end
    local key = tostring(name)
    if seen[key] then
        local st = Reports.stats
        st.rejected = st.rejected + 1
        st.why["no body"] = (st.why["no body"] or 0) + 1
        return false, "no body"
    end
    seen[key] = true
    Reports.warned[key .. "|no body"] = nil
    return reject(name, id, "no body", where, true)
end

-- Course du transfert de propriété (LK03-T03) : rapport ignoré, ni refusé ni gardé ; ligne INFO par minute.
local function ignore(name, id, reason)
    local st = Reports.stats
    st.ignored = (st.ignored or 0) + 1
    st.why[reason] = (st.why[reason] or 0) + 1
    local key = tostring(name) .. "|" .. reason
    local last = Reports.warned[key]
    if last == nil or now() - last >= cfg().WARN_EVERY_MS then
        Reports.warned[key] = now()
        log().info("state report on npc %s from %s ignored: %s", tostring(id), tostring(name), reason)
    end
    return false, reason
end

-- Vrai si l'horloge réelle ne mesure plus le temps de jeu (solo en accéléré).
local function fastForward()
    if isServer() or getGameSpeed == nil then return false end
    local ok, speed = pcall(getGameSpeed)
    return ok and type(speed) == "number" and speed > 1
end

-- Seau à jetons du PNJ id : vrai si un rapport peut encore être pris.
local function take(id)
    local c = cfg()
    local t = now()
    local b = Reports.buckets[id]
    if b == nil then
        b = { tokens = c.BURST, ms = t }
        Reports.buckets[id] = b
    end
    b.tokens = math.min(c.BURST, b.tokens + (t - b.ms) * c.RATE / 1000)
    b.ms = t
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

-- Forme et bornes d'un rapport. Rend nil, ou la raison et un détail.
local function badShape(args)
    if type(args) ~= "table" or type(args.id) ~= "string" or type(args.l) ~= "number" or args.l < 0
        or type(args.n) ~= "number" or not finite(args.x) or not finite(args.y) or not finite(args.z)
        or not finite(args.a) or not finite(args.hp) or type(args.act) ~= "string" or type(args.pose) ~= "string" then
        return "bad report"
    end
    local c = cfg()
    if not Reports.ACTIVITIES[args.act] then return "out of bounds", "activity " .. args.act end
    if not Reports.POSES[args.pose] then return "out of bounds", "pose " .. args.pose end
    if args.x < 0 or args.y < 0 or args.x > c.COORD_MAX or args.y > c.COORD_MAX then
        return "out of bounds", string.format("position %.1f,%.1f", args.x, args.y)
    end
    if args.z < c.Z_MIN or args.z >= c.Z_MAX + 1 then return "out of bounds", string.format("level %.2f", args.z) end
    if args.hp < 0 or args.hp > c.HP_MAX then return "out of bounds", string.format("health %.3f", args.hp) end
    if args.a < -360 or args.a > 360 then return "out of bounds", string.format("angle %.1f", args.a) end
    -- Résumé de perception facultatif (LK05-T01) : forme et bornes contrôlées par LivingKnox.Senses s'il est chargé.
    local S = LivingKnox.Senses
    if args.sen ~= nil and S ~= nil and S.validate ~= nil then return S.validate(args.sen) end
    return nil
end

-- Bail (LK03-T01) : rend nil si le rapport est sous le bail courant de son expéditeur, sinon la raison et un détail.
local function badLease(id, args, name)
    local Dir = D()
    local e = Dir.entries[id]
    if e == nil then
        if args.l == 0 then return nil end
        if args.l > (Dir.state.lease or 0) then return "unknown lease", "lease " .. args.l .. ", none given" end
        return "previous lease", "lease " .. args.l .. ", npc without directive"
    end
    local cur = e.l or 0
    if args.l > cur then return "unknown lease", "lease " .. args.l .. ", current " .. cur end
    if args.l < cur then return "previous lease", "lease " .. args.l .. ", current " .. cur end
    if isServer() and e.o ~= name then
        return "not the designated executor", "lease " .. cur .. " given to " .. tostring(e.o)
    end
    return nil
end

-- Plausibilité face à la copie du serveur z et au dernier état accepté s. Rend nil, ou la raison et un détail.
local function implausible(id, args, z, s)
    local c = cfg()
    local Dir = D()
    local gap = Dir.dist(args.x, args.y, z:getX(), z:getY())
    if gap > c.MAX_GAP then return "far from the body", string.format("%.1f squares", gap) end
    local lgap = math.abs(args.z - z:getZ())
    if lgap > c.MAX_LEVEL_GAP then return "other level than the body", string.format("%.2f levels", lgap) end
    if s == nil then return nil end
    if args.hp > s.hp + c.HP_EPSILON then
        local rise = args.hp - s.hp
        local credit = Reports.heals[id] or 0
        if credit + c.HP_EPSILON < rise then
            return "health rose without a known heal", string.format("%.3f to %.3f, heal %.3f", s.hp, args.hp, credit)
        end
    end
    if fastForward() then
        Reports.stats.fastForward = Reports.stats.fastForward + 1
        return nil
    end
    local dt = math.max(0, now() - s.ms) / 1000
    local moved = Dir.dist(args.x, args.y, s.x, s.y)
    if moved > c.SLACK + c.MAX_SPEED * dt then
        return "too fast", string.format("%.1f squares in %d ms", moved, math.floor(dt * 1000))
    end
    local dz = args.z - s.z
    if dz > c.CLIMB_SLACK + c.CLIMB_RATE * dt then
        return "impossible climb", string.format("%.2f levels up in %d ms", dz, math.floor(dt * 1000))
    end
    if -dz > c.FALL_SLACK + math.max(c.CLIMB_RATE * dt, c.FALL_ACCEL / 2 * dt * dt) then
        return "impossible fall", string.format("%.2f levels down in %d ms", -dz, math.floor(dt * 1000))
    end
    return nil
end

-- Rapport d'état. player : expéditeur (serveur : joueur de la connexion ; solo : joueur local). Rend vrai si
-- accepté, sinon faux et la raison.
function Reports.onReport(player, args)
    if not LivingKnox.isAuthority() then return false, "not the authority" end
    local st = Reports.stats
    st.received = st.received + 1
    local Dir = D()
    local name = Dir.senderName(player)
    local id = type(args) == "table" and args.id or nil
    local bad, detail = badShape(args)
    if bad then return reject(name, id, bad, detail) end
    local z, where = Bodies().find(id)
    if z == nil then
        if Reports.GONE[where] then Reports.forget(id) end
        return rejectAbsent(name, id, tostring(where))
    end
    Reports.absent[id] = nil   -- corps retrouvé : une prochaine absence sera de nouveau écrite
    if not Dir.isOwner(z, player) then
        if Dir.isPreviousOwner ~= nil and Dir.isPreviousOwner(id, name) then return ignore(name, id, "previous owner") end
        return reject(name, id, "not the owner", "owner " .. Dir.senderName(z:getOwnerPlayer()))
    end
    bad, detail = badLease(id, args, name)
    if bad then return reject(name, id, bad, detail) end
    if not take(id) then return reject(name, id, "too many reports") end
    local last = Reports.lastN[id]
    if last ~= nil and last.by == name and last.l == args.l and args.n <= last.n then
        return reject(name, id, "replayed or older report", "n " .. args.n .. ", last " .. last.n)
    end
    local s = Reports.states[id]
    if s ~= nil and not rawequal(s.body, z) then s = nil end   -- autre corps (nouvelle génération) : repère neuf
    bad, detail = implausible(id, args, z, s)
    if bad then return reject(name, id, bad, detail) end
    if s ~= nil and args.hp > s.hp + cfg().HP_EPSILON then
        Reports.heals[id] = math.max(0, (Reports.heals[id] or 0) - (args.hp - s.hp))
        st.healed = st.healed + 1
    end
    if s ~= nil and s.by ~= name then
        log().info("npc %s: state now reported by %s (was %s)", id, name, tostring(s.by))
    end
    Reports.lastN[id] = { by = name, l = args.l, n = args.n }
    Reports.states[id] = { x = args.x, y = args.y, z = args.z, a = args.a, act = args.act, hp = args.hp,
        pose = args.pose, ms = now(), by = name, l = args.l, n = args.n, t = type(args.t) == "number" and args.t or 0,
        body = z }
    st.accepted = st.accepted + 1
    local S = LivingKnox.Senses
    if args.sen ~= nil and S ~= nil and S.accept ~= nil then S.accept(id, args.sen, name, z) end
    return true
end

-- Soin connu de l'autorité (LK07-T03) : la santé rapportée pourra remonter d'autant. Rend vrai si noté.
function Reports.noteHeal(id, amount)
    if not LivingKnox.isAuthority() or type(id) ~= "string" or not finite(amount) or amount <= 0 then return false end
    Reports.heals[id] = (Reports.heals[id] or 0) + amount
    return true
end

-- Dernier état accepté d'un PNJ (copie, sans l'objet du corps), ou nil. PNJ oublié, mort ou redevenu virtuel :
-- état oublié (nil).
function Reports.get(id)
    local s = Reports.states[id]
    if s == nil then return nil end
    local z, where = Bodies().find(id)
    if z == nil and Reports.GONE[where] then
        Reports.forget(id)
        return nil
    end
    return { x = s.x, y = s.y, z = s.z, a = s.a, act = s.act, hp = s.hp, pose = s.pose, ms = s.ms, by = s.by,
        l = s.l, n = s.n, t = s.t }
end

-- Rapports refusés pour le PNJ id depuis que son état est suivi (corps présent) : total, puis ceux de raison suspecte
-- (Reports.SUSPECT, WARN) ; les autres sont des courses attendues du réseau (bail précédent au transfert...).
function Reports.rejectedOf(id)
    local c = Reports.rejectedBy[id]
    if c == nil then return 0, 0 end
    return c.n, c.suspect
end

-- Oublie l'état d'un PNJ (PNJ oublié, corps retiré).
function Reports.forget(id)
    Reports.states[id], Reports.lastN[id], Reports.heals[id], Reports.buckets[id] = nil, nil, nil, nil
    Reports.rejectedBy[id] = nil
    local S = LivingKnox.Senses
    if S ~= nil and S.forget ~= nil then S.forget(id) end
end

-- Entrée en partie d'un joueur (nouvel état Lua, numéros n repartis de 1) : ses derniers numéros sont oubliés.
function Reports.onHello(player)
    local name = D().senderName(player)
    for _, last in pairs(Reports.lastN) do
        if last.by == name then last.n = -1 end
    end
end

function Reports.onClientCommand(module, command, player, args)
    if module ~= Reports.MODULE or not isServer() or player == nil then return end
    if command == Reports.CMD_REPORT then
        Reports.onReport(player, args)
    elseif command == LivingKnox.ZombieGuard.CMD_HELLO then
        Reports.onHello(player)
    end
end

if isServer() then
    local function onClientCommand(module, command, player, args)
        LivingKnox.Reports.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnClientCommand", "Reports.onClientCommand", onClientCommand)
end

return Reports
