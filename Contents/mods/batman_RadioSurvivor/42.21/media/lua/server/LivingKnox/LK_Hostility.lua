-- Living Knox : attitude d'un groupe envers un personnage joueur (LK11-T03). Fiche : docs/annexes/conception/attitude.md.
-- Choix de cible fondé sur l'attitude (LK06-T01, fin du fichier). Fiche : docs/annexes/conception/cibles.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Clé d'une attitude : groupe (grp-<n> du registre des groupes) + clé de joueur. La clé de joueur est l'identité de
-- personnage du carnet (RS_CarnetCharacter, RS_Carnet_Server : liée au compte en MP, nouvelle pour chaque personnage,
-- retirée à sa mort) : deux personnages d'un même compte ont deux attitudes distinctes. Hostility.keyOf(player) la
-- retrouve ; le module accepte toute clé bien formée (PLAYER_KEY_MAX caractères de [%w_.:-]).
--
-- Registre (schéma 1), privé, jamais en ModData globale :
--   { schema = 1, decayDay = dernier jour de déclin (facultatif), groups = { ["grp-<n>"] = { [playerKey] = pair } } }
--   pair = { value = -100..100 (interne, jamais rendu), start = valeur de départ (-100..100, fixée à la création
--            d'après l'hostilité du type), facts = { { fact, sign = -1|0|1, day }, ... } (les TREND_FACTS derniers,
--            le plus ancien d'abord), murder = vrai ou absent (un meurtre a eu lieu : plafond du déclin),
--            decayDay = dernier jour de déclin appliqué, seen = jour du dernier fait,
--            count = nombre de faits enregistrés (E09-T04, facultatif ; chaque fait porte n = count à son ajout) }
-- E04-T11 : départ d'une paire inconnue décalé d'un cran selon la réputation interne du personnage (crochet
-- LivingKnox.Hooks.reputation, Hostility.startForPlayer), au premier contact seulement.
-- Sortie : { level, trend } seulement (niveaux LEVELS, tendance up / down / stable = signe de la somme des sens des
-- trois derniers faits).
-- Faits : liste fermée FACTS, effet borné (Config.ATTITUDE). Un fait ne compte que s'il a été vu par un membre du
-- groupe (opts.witnessed) ou s'il lui est attribuable (opts.attributable) ; seul le joueur désigné est visé, jamais
-- son équipe. Aucune détection dans le monde ici : les points d'entrée viendront avec le combat et les interactions.
--
-- Fichiers (mécanisme de LK_Store) : Zomboid/Lua/batman_RadioSurvivor/livingknox/attitudes-<partie>-<0|1>.txt,
-- entête LKATT1, deux emplacements en alternance, relus pour vérification. Relecture : schéma inconnu, structure
-- générale fausse ou deux fichiers illisibles -> registre BLOQUÉ (aucune écriture, fichiers conservés) ; une paire
-- ou un groupe invalide est écarté et journalisé. Sauvegarde à chaque fait et à chaque déclin effectif.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"

local Hostility = LivingKnox.Hostility or {}
LivingKnox.Hostility = Hostility

Hostility.SCHEMA = 1
Hostility.HEADER = "LKATT1"
Hostility.FILE = "attitudes"

Hostility.MIN, Hostility.MAX = -100, 100
Hostility.MAX_PLAYERS = 64          -- paires gardées par groupe (au-delà : la plus ancienne sans meurtre est oubliée)
Hostility.MAX_GROUPS = 64           -- = LivingKnox.Groups.MAX_GROUPS
Hostility.TREND_FACTS = 3           -- décision E09-T01 : tendance sur les trois derniers faits
Hostility.PLAYER_KEY_MAX = 96
Hostility.DAY_MAX = 2147483647

-- Niveaux, du plus bas au plus haut (décision E09-T01 : hostile, méfiant, prudent, favorable, confiant).
Hostility.LEVELS = { "hostile", "wary", "cautious", "favorable", "trusting" }
Hostility.TRENDS = { "up", "down", "stable" }
-- Faits (liste fermée) : aide, agression, meurtre, vol constaté, mission.
Hostility.FACTS = { "gift", "heal", "delivery", "hit", "shot", "kill", "theft", "mission_success", "mission_failure" }
Hostility.MURDER_FACTS = { kill = true }
-- Agressions publiées quand un témoin les a vues (E08-T07, fait "assaultSeen").
local ASSAULT_FACTS = { hit = true, shot = true, kill = true }

-- Repli si Config.ATTITUDE manque ou porte une valeur inutilisable (mêmes valeurs que LK_Config).
local FALLBACK = {
    START_SCALE = 1.25,
    LEVEL_MIN = { wary = -44, cautious = -14, favorable = 15, trusting = 60 },
    EFFECTS = { gift = 8, heal = 12, delivery = 10, hit = -15, shot = -25, kill = -60, theft = -20,
        mission_success = 15, mission_failure = -10 },
    EFFECT_MAX = 60,
    DECAY_PER_DAY = 2,
    DECAY_MAX_DAYS = 30,
    MURDER_CAP = -15,
}

Hostility.state = Hostility.state or { data = nil, seq = 0, blocked = false, reason = nil, path = nil, dropped = 0 }

local NOT_READY = "attitude registry not ready"

local function log() return LivingKnox.Log end
local function Store() return LivingKnox.Store end
local function Groups() return LivingKnox.Groups end

local function isNumber(v) return type(v) == "number" and v == v end

local function isInt(v, lo, hi)
    return isNumber(v) and math.floor(v) == v and v >= lo and v <= hi
end

local function round(v) return math.floor(v + 0.5) end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function inList(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Réglages ----------------------------------------------------------------------------------------------------------

local function raw()
    local c = LivingKnox.Config.ATTITUDE
    if type(c) ~= "table" then return FALLBACK end
    return c
end

-- Nombre de la configuration borné à lo..hi ; valeur non numérique : repli.
local function num(name, lo, hi)
    local v = raw()[name]
    if not isNumber(v) then v = FALLBACK[name] end
    return clamp(v, lo, hi)
end

-- Seuils bas des niveaux au-dessus de hostile, dans l'ordre de LEVELS ; seuils de repli s'ils ne sont pas entiers
-- strictement croissants dans -99..100.
local function levelMins()
    local t = raw().LEVEL_MIN
    local out, previous = {}, Hostility.MIN
    if type(t) == "table" then
        for i = 2, #Hostility.LEVELS do
            local v = t[Hostility.LEVELS[i]]
            if not isInt(v, previous + 1, Hostility.MAX) then out = nil break end
            out[#out + 1] = v
            previous = v
        end
    else
        out = nil
    end
    if out then return out end
    out = {}
    for i = 2, #Hostility.LEVELS do out[#out + 1] = FALLBACK.LEVEL_MIN[Hostility.LEVELS[i]] end
    return out
end

-- Effet d'un fait de la liste fermée, borné à +-EFFECT_MAX (valeur non numérique : repli).
function Hostility.effect(fact)
    if not inList(Hostility.FACTS, fact) then return nil end
    local t = raw().EFFECTS
    local v = type(t) == "table" and t[fact] or nil
    if not isNumber(v) then v = FALLBACK.EFFECTS[fact] end
    local m = num("EFFECT_MAX", 0, 200)
    return round(clamp(v, -m, m))
end

-- Niveau d'une valeur interne.
function Hostility.levelOf(value)
    local mins = levelMins()
    local level = Hostility.LEVELS[1]
    for i, v in ipairs(mins) do
        if value >= v then level = Hostility.LEVELS[i + 1] end
    end
    return level
end

-- Tendance d'une liste de faits : signe de la somme de leurs sens.
function Hostility.trendOf(facts)
    local s = 0
    for _, f in ipairs(facts or {}) do s = s + f.sign end
    if s > 0 then return "up" end
    if s < 0 then return "down" end
    return "stable"
end

-- Valeur de départ envers tout joueur pour un type de groupe (hostilité 0..100 des données de type ; type inconnu :
-- hostilité 50, soit 0).
function Hostility.startFor(groupType)
    local def = LivingKnox.GroupTypes.peek(groupType)   -- LK13-T11 : lecture en place (un champ lu)
    local hostility = def and def.hostility or 50
    if not isNumber(hostility) then hostility = 50 end
    return clamp(round((50 - hostility) * num("START_SCALE", 0, 10)), Hostility.MIN, Hostility.MAX)
end

-- E04-T11 (Q14, confirmé par défaut le 2026-10-15) : niveau de réputation interne d'un personnage (« good », « neutral »,
-- « bad ») rendu par le crochet facultatif LivingKnox.Hooks.reputation(playerKey) (RadioSurvivor : réputation interne
-- du carnet, RS_Reputation). Crochet absent, en erreur ou valeur inconnue : nil (aucun effet).
local REPUTATION_LEVELS = { good = true, neutral = true, bad = true }

function Hostility.reputationOf(playerKey)
    local hooks = LivingKnox.Hooks
    local fn = type(hooks) == "table" and hooks.reputation or nil
    if type(fn) ~= "function" or not Hostility.validPlayerKey(playerKey) then return nil end
    local ok, level = pcall(fn, playerKey)
    if not ok then
        Hostility.hookStats.reputationErrors = (Hostility.hookStats.reputationErrors or 0) + 1
        log().error("hook reputation failed for %s: %s", tostring(playerKey), tostring(level))
        return nil
    end
    return REPUTATION_LEVELS[level] and level or nil
end

-- Valeur de départ d'une paire encore inconnue (premier contact) : celle du type (startFor), décalée d'un cran de
-- niveau selon la réputation du personnage : bonne = au moins le seuil du niveau au-dessus, mauvaise = juste sous le
-- seuil de son niveau (un cran plus bas). Neutre, inconnue ou niveau extrême déjà atteint : inchangée. Fixée à la
-- création de la paire (champ start) : ensuite seuls les faits envers ce groupe la changent (la réputation n'est plus
-- relue pour cette paire).
function Hostility.startForPlayer(groupType, playerKey)
    local base = Hostility.startFor(groupType)
    local rep = Hostility.reputationOf(playerKey)
    if rep ~= "good" and rep ~= "bad" then return base end
    local mins = levelMins()
    local index = 1
    for i, v in ipairs(mins) do
        if base >= v then index = i + 1 end
    end
    if rep == "good" and index < #Hostility.LEVELS then
        return clamp(math.max(base, mins[index]), Hostility.MIN, Hostility.MAX)
    end
    if rep == "bad" and index > 1 then
        return clamp(math.min(base, mins[index - 1] - 1), Hostility.MIN, Hostility.MAX)
    end
    return base
end

-- Contrôles ---------------------------------------------------------------------------------------------------------

function Hostility.validPlayerKey(key)
    return type(key) == "string" and #key >= 1 and #key <= Hostility.PLAYER_KEY_MAX
        and string.match(key, "^[%w_%.:%-]+$") ~= nil
end

local function validFacts(list)
    if type(list) ~= "table" then return false end
    local n = 0
    for k, f in pairs(list) do
        if not isInt(k, 1, Hostility.TREND_FACTS) or type(f) ~= "table" then return false end
        if not inList(Hostility.FACTS, f.fact) or not isInt(f.sign, -1, 1) or not isInt(f.day, 0, Hostility.DAY_MAX) then
            return false
        end
        -- E09-T04 : numéro du fait dans la paire (facultatif : faits enregistrés avant son ajout).
        if f.n ~= nil and not isInt(f.n, 1, Hostility.DAY_MAX) then return false end
        n = n + 1
    end
    return #list == n
end

-- Contrôle d'une paire relue. Rend vrai, ou faux et une raison.
function Hostility.validPair(p)
    if type(p) ~= "table" then return false, "pair is not a table" end
    if not isInt(p.value, Hostility.MIN, Hostility.MAX) then return false, "bad value" end
    if not isInt(p.start, Hostility.MIN, Hostility.MAX) then return false, "bad start" end
    if not validFacts(p.facts) then return false, "bad facts" end
    if p.murder ~= nil and p.murder ~= true then return false, "bad murder flag" end
    if not isInt(p.decayDay, 0, Hostility.DAY_MAX) then return false, "bad decay day" end
    if not isInt(p.seen, 0, Hostility.DAY_MAX) then return false, "bad seen day" end
    if p.count ~= nil and not isInt(p.count, 0, Hostility.DAY_MAX) then return false, "bad fact count" end
    return true
end

function Hostility.newRegistry()
    return { schema = Hostility.SCHEMA, groups = {} }
end

-- Contrôle d'un registre relu : rend (registre, écartés = { { id, why } }) ou (nil, raison, "schema"|"structure").
function Hostility.validate(data)
    if type(data) ~= "table" then return nil, "registry is not a table", "structure" end
    if data.schema ~= Hostility.SCHEMA then
        return nil, "unknown attitude schema " .. tostring(data.schema), "schema"
    end
    if type(data.groups) ~= "table" then return nil, "groups is not a table", "structure" end
    local out, dropped = Hostility.newRegistry(), {}
    local gids = {}
    for gid in pairs(data.groups) do gids[#gids + 1] = gid end
    if #gids > Hostility.MAX_GROUPS then return nil, "too many groups", "structure" end
    for i, gid in ipairs(gids) do gids[i] = tostring(gid) end
    table.sort(gids)
    for _, gid in ipairs(gids) do
        local pairsOf = data.groups[gid]
        if not Groups().idNumber(gid) or type(pairsOf) ~= "table" then
            dropped[#dropped + 1] = { id = gid, why = "bad group entry" }
        else
            local keep, count = {}, 0
            local keys = {}
            for key in pairs(pairsOf) do keys[#keys + 1] = tostring(key) end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local ok, why = Hostility.validPair(pairsOf[key])
                if not Hostility.validPlayerKey(key) then ok, why = false, "bad player key" end
                if ok and count >= Hostility.MAX_PLAYERS then ok, why = false, "too many players" end
                if ok then
                    keep[key] = pairsOf[key]
                    count = count + 1
                else
                    dropped[#dropped + 1] = { id = gid .. "/" .. key, why = why }
                end
            end
            out.groups[gid] = keep
        end
    end
    if data.decayDay ~= nil and isInt(data.decayDay, 0, Hostility.DAY_MAX) then out.decayDay = data.decayDay end
    return out, dropped
end

-- Persistance -------------------------------------------------------------------------------------------------------

local function slotPath(slot)
    return Hostility.state.path .. "-" .. slot .. ".txt"
end
Hostility.slotPath = slotPath

local function block(reason)
    local st = Hostility.state
    st.blocked, st.reason = true, reason
    log().error("attitude registry BLOCKED: %s; files kept for recovery (%s-0.txt, -1.txt)", reason,
        tostring(st.path))
    return false
end

-- Charge (ou crée) le registre des attitudes de la partie courante. newWorld = vrai : registre vide.
function Hostility.init(newWorld)
    local st = Hostility.state
    st.data, st.seq, st.blocked, st.reason, st.dropped = nil, 0, false, nil, 0
    st.path = Store().worldFileBase(Hostility.FILE)
    local a, existsA = Store().readSlotFile(slotPath(0), Hostility.HEADER)
    local b, existsB = Store().readSlotFile(slotPath(1), Hostility.HEADER)
    local best = a
    if b and (not a or b.seq > a.seq) then best = b end
    local lastSeq = 0
    if a then lastSeq = a.seq end
    if b and b.seq > lastSeq then lastSeq = b.seq end
    if newWorld then
        st.data, st.seq = Hostility.newRegistry(), lastSeq
        log().info("attitudes: new world, empty attitude registry")
        return Hostility.save()
    end
    if not best then
        if existsA or existsB then return block("both attitude registry files are unreadable") end
        st.data, st.seq = Hostility.newRegistry(), 0
        log().info("attitudes: no file yet, empty attitude registry")
        return true
    end
    local data, why, kind = Hostility.validate(best.data)
    if not data then
        if kind == "schema" then return block(why) end
        return block("attitude registry file #" .. best.seq .. " is invalid: " .. why)
    end
    for _, d in ipairs(why) do
        log().error("attitude %s dropped at load (file #%s): %s", d.id, tostring(best.seq), d.why)
    end
    st.data, st.seq, st.dropped = data, best.seq, #why
    log().info("attitudes loaded: %s dropped, file #%s", tostring(#why), tostring(best.seq))
    return true
end

function Hostility.isReady()
    return Hostility.state.data ~= nil and not Hostility.state.blocked
end

function Hostility.isBlocked()
    return Hostility.state.blocked == true, Hostility.state.reason
end

-- Charge le registre s'il ne l'est pas encore (rechargement Lua, événement manqué). N'écrit rien.
function Hostility.ensure()
    if Hostility.state.data or Hostility.state.blocked then return Hostility.isReady() end
    return Hostility.init(false)
end

function Hostility.save()
    local st = Hostility.state
    if st.blocked or not st.data then return false end
    local seq = st.seq + 1
    local ok, why = Store().writeSlotFile(slotPath(seq % 2), Hostility.HEADER, seq, st.data)
    if not ok then return block("attitude registry " .. why) end
    st.seq = seq
    return true
end

-- Logique -----------------------------------------------------------------------------------------------------------

local function view(p)
    return { level = Hostility.levelOf(p.value), trend = Hostility.trendOf(p.facts) }
end

-- Groupe connu du registre des groupes : rend (groupe vivant) ou (nil, raison).
local function knownGroup(gid)
    if not Groups().ensure() then return nil, "group registry not ready" end
    local g = type(gid) == "string" and Groups().state.data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    return g
end

-- Retire les entrées des groupes qui n'existent plus (registre des groupes prêt seulement). Rend le nombre retiré.
local function pruneOrphans(data)
    if not Groups().ensure() then return 0 end
    local live = Groups().state.data.groups
    local doomed = {}
    for gid in pairs(data.groups) do
        if not live[gid] then doomed[#doomed + 1] = gid end
    end
    for _, gid in ipairs(doomed) do data.groups[gid] = nil end
    return #doomed
end

-- Paire à oublier quand un groupe atteint MAX_PLAYERS : la plus ancienne (seen) sans meurtre, sinon la plus
-- ancienne ; égalité : la plus petite clé.
local function evictKey(pairsOf)
    local bestKey, bestPair
    for key, p in pairs(pairsOf) do
        local better
        if not bestKey then
            better = true
        elseif (p.murder == true) ~= (bestPair.murder == true) then
            better = bestPair.murder == true
        elseif p.seen ~= bestPair.seen then
            better = p.seen < bestPair.seen
        else
            better = key < bestKey
        end
        if better then bestKey, bestPair = key, p end
    end
    return bestKey
end

local function dayOf(day)
    if day == nil then return Groups().today() end
    if not isInt(day, 0, Hostility.DAY_MAX) then return nil end
    return day
end

-- Fait de relation entre un groupe et un joueur. opts = { witnessed = bool, attributable = bool, day = jour,
-- witnesses = { "lk-<n>", ... } et x, y facultatifs (E08-T07 : témoins et lieu d'une agression vue) }.
-- Rend { level, trend } après le fait, ou nil et une raison (anglais) : fait inconnu, ni vu ni attribuable, groupe
-- inconnu, registre non prêt, écriture impossible.
function Hostility.record(gid, playerKey, fact, opts)
    opts = type(opts) == "table" and opts or {}
    local delta = Hostility.effect(fact)
    if delta == nil then return nil, "unknown fact " .. tostring(fact) end
    if not Hostility.validPlayerKey(playerKey) then return nil, "bad player key" end
    if opts.witnessed ~= true and opts.attributable ~= true then return nil, "fact neither witnessed nor attributable" end
    local day = dayOf(opts.day)
    if not day then return nil, "bad day" end
    if not Hostility.ensure() then return nil, NOT_READY end
    local g, why = knownGroup(gid)
    if not g then return nil, why end
    local data = Hostility.state.data
    local pairsOf = data.groups[gid]
    if not pairsOf then
        local n = 0
        for _ in pairs(data.groups) do n = n + 1 end
        if n >= Hostility.MAX_GROUPS then pruneOrphans(data) end
        pairsOf = {}
        data.groups[gid] = pairsOf
    end
    local p = pairsOf[playerKey]
    if not p then
        local n = 0
        for _ in pairs(pairsOf) do n = n + 1 end
        if n >= Hostility.MAX_PLAYERS then
            local victim = evictKey(pairsOf)
            log().info("attitude %s/%s forgotten (group full)", gid, victim)
            pairsOf[victim] = nil
        end
        local start = Hostility.startForPlayer(g.type, playerKey) -- E04-T11 : premier contact selon la réputation
        p = { value = start, start = start, facts = {}, decayDay = day, seen = day }
        pairsOf[playerKey] = p
    end
    p.value = clamp(p.value + delta, Hostility.MIN, Hostility.MAX)
    local sign = 0
    if delta > 0 then sign = 1 elseif delta < 0 then sign = -1 end
    -- E09-T04 : chaque fait reçoit un numéro propre à la paire (count), qui le désigne sans ambiguïté pour les
    -- relations personnelles du carnet (un fait ne motive qu'un changement).
    p.count = (isInt(p.count, 0, Hostility.DAY_MAX) and p.count or 0) + 1
    p.facts[#p.facts + 1] = { fact = fact, sign = sign, day = day, n = p.count }
    while #p.facts > Hostility.TREND_FACTS do table.remove(p.facts, 1) end
    if Hostility.MURDER_FACTS[fact] then p.murder = true end
    if day > p.seen then p.seen = day end
    if not Hostility.save() then return nil, "attitude registry write failed" end
    -- E08-T07 : agression vue (fait "assaultSeen" de LK_Core.publish). opts.witnesses = identifiants "lk-<n>" des
    -- PNJ qui l'ont vue (fournis par l'appelant, qui seul connaît la scène) ; opts.x, opts.y = lieu de la scène,
    -- facultatif. Sans témoin nommé, aucun PNJ n'en garde le souvenir.
    if opts.witnessed == true and ASSAULT_FACTS[fact] then
        local witnesses = {}
        if type(opts.witnesses) == "table" then
            for _, w in ipairs(opts.witnesses) do
                if type(w) == "string" then witnesses[#witnesses + 1] = w end
            end
        end
        LivingKnox.publish("assaultSeen", { group = gid, player = playerKey, fact = fact, day = day,
            witnesses = witnesses, x = isNumber(opts.x) and opts.x or nil, y = isNumber(opts.y) and opts.y or nil })
    end
    return view(p)
end

-- Attitude d'un groupe envers un joueur : { level, trend }, ou nil et une raison. Sans fait connu : niveau de
-- départ du type, tendance stable (rien n'est créé). Lecture seule.
function Hostility.get(gid, playerKey)
    if not Hostility.validPlayerKey(playerKey) then return nil, "bad player key" end
    if not Hostility.ensure() then return nil, NOT_READY end
    local g, why = knownGroup(gid)
    if not g then return nil, why end
    local pairsOf = Hostility.state.data.groups[gid]
    local p = pairsOf and pairsOf[playerKey] or nil
    if p then return view(p) end
    return { level = Hostility.levelOf(Hostility.startForPlayer(g.type, playerKey)), trend = "stable" }
end

-- E09-T04 : faits gardés de la paire (les TREND_FACTS derniers, le plus ancien d'abord) qui portent un numéro :
-- { { n, fact, sign, day }, ... } (copies) ; liste vide sans paire. Jamais la valeur interne. Lecture seule.
function Hostility.facts(gid, playerKey)
    local out = {}
    local data = Hostility.state.data
    local pairsOf = data and data.groups[gid]
    local p = pairsOf and Hostility.validPlayerKey(playerKey) and pairsOf[playerKey] or nil
    if not p then return out end
    for _, f in ipairs(p.facts) do
        if isInt(f.n, 1, Hostility.DAY_MAX) then
            out[#out + 1] = { n = f.n, fact = f.fact, sign = f.sign, day = f.day }
        end
    end
    return out
end

-- Attitudes connues d'un groupe, triées par clé de joueur (MAX_PLAYERS au plus) : { { player, level, trend }, ... },
-- ou nil et une raison. Serveur seulement : les clés de joueur ne s'envoient pas à un autre client.
function Hostility.forGroup(gid)
    if not Hostility.ensure() then return nil, NOT_READY end
    local _, why = knownGroup(gid)
    if why then return nil, why end
    local pairsOf = Hostility.state.data.groups[gid] or {}
    local keys = {}
    for key in pairs(pairsOf) do keys[#keys + 1] = key end
    table.sort(keys)
    local out = {}
    for i = 1, math.min(#keys, Hostility.MAX_PLAYERS) do
        local v = view(pairsOf[keys[i]])
        out[#out + 1] = { player = keys[i], level = v.level, trend = v.trend }
    end
    return out
end

-- Retour lent vers la valeur de départ (I9.4) jusqu'au jour day (défaut : aujourd'hui) : DECAY_PER_DAY par jour
-- écoulé depuis le dernier déclin de la paire (DECAY_MAX_DAYS au plus), sans dépasser la cible ; après un meurtre,
-- cible = min(départ, MURDER_CAP). Le déclin n'est pas un fait (tendance inchangée). Retire aussi les attitudes des
-- groupes disparus. Rend le nombre de paires dont la valeur a changé, ou nil et une raison.
function Hostility.decay(day)
    day = dayOf(day)
    if not day then return nil, "bad day" end
    if not Hostility.ensure() then return nil, NOT_READY end
    local data = Hostility.state.data
    if data.decayDay == day then return 0 end
    local perDay = round(num("DECAY_PER_DAY", 0, 50))
    local maxDays = round(num("DECAY_MAX_DAYS", 1, 365))
    local cap = round(num("MURDER_CAP", Hostility.MIN, Hostility.MAX))
    local changed, touched = 0, pruneOrphans(data) > 0
    for _, pairsOf in pairs(data.groups) do
        for _, p in pairs(pairsOf) do
            if day > p.decayDay then
                local days = math.min(day - p.decayDay, maxDays)
                local target = p.start
                if p.murder and cap < target then target = cap end
                local step = days * perDay
                local before = p.value
                if p.value > target then
                    p.value = math.max(target, p.value - step)
                elseif p.value < target then
                    p.value = math.min(target, p.value + step)
                end
                p.decayDay = day
                touched = true
                if p.value ~= before then changed = changed + 1 end
            end
        end
    end
    data.decayDay = day
    if touched and not Hostility.save() then return nil, "attitude registry write failed" end
    return changed
end

-- Une fois par heure de jeu (LK_Server) : déclin quand le jour de jeu a changé.
function Hostility.onEveryHours()
    if not Hostility.ensure() then return end
    if Hostility.state.data.decayDay == Groups().today() then return end
    Hostility.decay()
end

-- Clé de joueur d'un IsoPlayer : identité de personnage du carnet liée à ce joueur (RS_Carnet_Server, commande
-- hello à l'entrée en jeu), ou nil et une raison s'il n'en a pas encore.
function Hostility.keyOf(player)
    local server = RS_CarnetServer
    local cid = server and player and server.bound and server.bound[player] or nil
    if not Hostility.validPlayerKey(cid) then return nil, "no notebook character bound" end
    return cid
end

-- Vrai si le groupe gid a une attitude propre envers ce joueur (au moins un fait vu ou attribuable) ; faux pour un
-- inconnu (alerte LK05-T08 : « joueur inconnu du groupe »). Lecture seule.
function Hostility.isKnown(gid, playerKey)
    local data = Hostility.state.data
    local pairsOf = data and data.groups[gid]
    return pairsOf ~= nil and Hostility.validPlayerKey(playerKey) and pairsOf[playerKey] ~= nil
end

-- Choix de cible (LK06-T01) -----------------------------------------------------------------------------------------
-- Décidé par l'autorité seulement, sans tirage : mêmes registres, mêmes perceptions -> même décision pour tous (le
-- client propriétaire n'exécutera qu'une consigne, LK06-T02/T03). Règle par joueur (Hostility.targetRule), dans
-- l'ordre :
--   1. auteur d'un incident ouvert avec ce groupe (crochet LivingKnox.Hooks.incident, E09-T06) : attaque ;
--   2. joueur couvert (crochet LivingKnox.Hooks.covered, trêves E09-T05 / E10-T04) : jamais une cible ;
--   2b. cible d'une vengeance jurée par le groupe (LK11-T05, LivingKnox.Relations.revengeAgainst) : attaque ;
--   3. provocation (agression hit, shot ou kill du joueur envers le groupe, vue ou attribuable, datée de
--      TARGET.PROVOKE_DAYS jours au plus) : attaque (défense) ;
--   4. niveau hostile : attaque si le type tire le premier (hostilité du type >= TARGET.FIRST_STRIKE), sinon
--      avertissement ;
--   5. niveau méfiant : avertissement ;
--   6. sinon : rien.
-- Un groupe qui ne tire pas le premier (colons, neutres) n'attaque donc jamais sans incident ni provocation : il
-- avertit (la séquence de sommation elle-même est LK11-T02). Crochets absents : personne n'est couvert, aucun incident.
Hostility.TARGET = Hostility.TARGET or {
    FIRST_STRIKE = 75,   -- hostilité de type (0..100) à partir de laquelle le groupe tire le premier (pillards : 90)
    PROVOKE_DAYS = 1,    -- jours de jeu : une agression du jour ou de la veille est une provocation
}
Hostility.ACTIONS = { "attack", "warn" }
-- Raisons, par priorité décroissante (départage des cibles).
Hostility.REASONS = { "incident", "revenge", "provoked", "hostile", "wary" }
Hostility.hookStats = Hostility.hookStats or { coveredErrors = 0, incidentErrors = 0 }

local REASON_RANK = {}
for i, r in ipairs(Hostility.REASONS) do REASON_RANK[r] = i end

-- Vrai si le type de groupe tire le premier sur un joueur hostile (type inconnu : non).
function Hostility.firstStrike(groupType)
    local def = LivingKnox.GroupTypes.peek(groupType)   -- LK13-T11 : lecture en place (un champ lu)
    local h = def and def.hostility or nil
    local limit = Hostility.TARGET.FIRST_STRIKE
    if not isNumber(limit) then limit = 75 end
    return isNumber(h) and h >= limit
end

-- Vrai si playerKey a provoqué le groupe gid : agression (hit, shot, kill) parmi les faits gardés de la paire, datée
-- du jour day (défaut : aujourd'hui) ou des PROVOKE_DAYS jours précédents. Lecture seule.
function Hostility.provoked(gid, playerKey, day)
    day = dayOf(day)
    local data = Hostility.state.data
    local pairsOf = data and data.groups[gid]
    local p = pairsOf and Hostility.validPlayerKey(playerKey) and pairsOf[playerKey] or nil
    if not p or not day then return false end
    local window = Hostility.TARGET.PROVOKE_DAYS
    if not isNumber(window) or window < 0 then window = 1 end
    for _, f in ipairs(p.facts) do
        if ASSAULT_FACTS[f.fact] and f.day <= day and day - f.day <= window then return true end
    end
    return false
end

-- Appel d'un crochet facultatif LivingKnox.Hooks[name](gid, playerKey, npcId). Rend vrai seulement si le crochet rend
-- true ; absent : faux ; erreur : onError (journalisée et comptée).
local function askHook(name, gid, playerKey, npcId, onError)
    local hooks = LivingKnox.Hooks
    local fn = type(hooks) == "table" and hooks[name] or nil
    if type(fn) ~= "function" or not Hostility.validPlayerKey(playerKey) then return false end
    local ok, res = pcall(fn, gid, playerKey, npcId)
    if not ok then
        local stat = name .. "Errors"
        Hostility.hookStats[stat] = (Hostility.hookStats[stat] or 0) + 1
        log().error("hook %s failed for %s/%s: %s", name, tostring(gid), tostring(playerKey), tostring(res))
        return onError
    end
    return res == true
end

-- Joueur couvert envers le groupe (trêve, E09-T05 ; trêve gardée par le PNJ npcId, E10-T04). Crochet en erreur :
-- couvert (prudence : on ne tire pas sur la foi d'une erreur).
function Hostility.isCovered(gid, playerKey, npcId)
    return askHook("covered", gid, playerKey, npcId, true)
end

-- Joueur auteur d'un incident ouvert avec le groupe (E09-T06). Crochet en erreur : non.
function Hostility.isIncidentAuthor(gid, playerKey, npcId)
    return askHook("incident", gid, playerKey, npcId, false)
end

-- Cible d'une vengeance jurée par le groupe gid (LK11-T05) ; module des relations absent : non.
function Hostility.isRevengeTarget(gid, playerKey)
    local R = LivingKnox.Relations
    if R == nil or R.revengeAgainst == nil or not Hostility.validPlayerKey(playerKey) then return false end
    return R.revengeAgainst(gid, playerKey) == true
end

-- Règle pure : c = { level, covered, incident, revenge, provoked, firstStrike } -> action ("attack", "warn" ou nil),
-- raison ("incident", "covered", "revenge", "provoked", "hostile", "wary" ou nil).
function Hostility.targetRule(c)
    if c.incident == true then return "attack", "incident" end
    if c.covered == true then return nil, "covered" end
    if c.revenge == true then return "attack", "revenge" end
    if c.provoked == true then return "attack", "provoked" end
    if c.level == "hostile" then
        if c.firstStrike == true then return "attack", "hostile" end
        return "warn", "hostile"
    end
    if c.level == "wary" then return "warn", "wary" end
    return nil, nil
end

local function targetOrder(a, b)
    if a.action ~= b.action then return a.action == "attack" end
    if a.reason ~= b.reason then return REASON_RANK[a.reason] < REASON_RANK[b.reason] end
    if a.d ~= b.d then return a.d < b.d end
    return a.u < b.u
end

-- Choix de cible du membre npcId du groupe gid parmi des joueurs candidats { { u = compte, key = clé de joueur ou
-- nil, d = distance }, ... } au jour day (défaut : aujourd'hui). Rend { target = première décision ou nil, list =
-- décisions { u, key, d, action, reason, level } triées (attaque avant avertissement, raison, distance, compte) },
-- ou nil et une raison. Un joueur sans clé (aucune identité de personnage) a le niveau de départ du type, n'est ni
-- couvert ni provocateur. Les décisions sans action ne sont pas rendues.
function Hostility.chooseTarget(gid, npcId, candidates, day)
    day = dayOf(day)
    if not day then return nil, "bad day" end
    if not Hostility.ensure() then return nil, NOT_READY end
    local g, why = knownGroup(gid)
    if not g then return nil, why end
    local first = Hostility.firstStrike(g.type)
    local startLevel = Hostility.levelOf(Hostility.startFor(g.type))
    local list, seen = {}, {}
    for _, c in ipairs(type(candidates) == "table" and candidates or {}) do
        local u = type(c) == "table" and c.u or nil
        if type(u) == "string" and not seen[u] then
            seen[u] = true
            local key = Hostility.validPlayerKey(c.key) and c.key or nil
            local level = startLevel
            if key then level = Hostility.get(gid, key).level end
            local action, reason = Hostility.targetRule({ level = level, firstStrike = first,
                incident = key ~= nil and Hostility.isIncidentAuthor(gid, key, npcId),
                covered = key ~= nil and Hostility.isCovered(gid, key, npcId),
                revenge = key ~= nil and Hostility.isRevengeTarget(gid, key),
                provoked = key ~= nil and Hostility.provoked(gid, key, day) })
            if action then
                list[#list + 1] = { u = u, key = key, d = isNumber(c.d) and c.d or 0, action = action, reason = reason,
                    level = level }
            end
        end
    end
    table.sort(list, targetOrder)
    return { target = list[1], list = list }
end

-- Candidats d'une perception (LivingKnox.Senses.perceived) : joueurs VUS (s), vivants, dans players (IsoPlayer du
-- serveur), avec leur clé (keyOf). Perception absente ou périmée : aucun.
function Hostility.candidatesOf(per, players)
    local out = {}
    if per == nil or per.stale then return out end
    local byName = {}
    for _, p in ipairs(players or {}) do byName[p:getUsername()] = p end
    for _, e in ipairs(per.p or {}) do
        local p = e.s and byName[e.u] or nil
        if p ~= nil and not (p.isDead ~= nil and p:isDead()) then
            out[#out + 1] = { u = e.u, key = Hostility.keyOf(p), d = e.d or 0 }
        end
    end
    return out
end

-- Copie d'une paire (tests, diagnostic serveur) : contient la valeur interne, jamais à envoyer à un client.
function Hostility.debugPair(gid, playerKey)
    local data = Hostility.state.data
    local pairsOf = data and data.groups[gid]
    return pairsOf and copy(pairsOf[playerKey]) or nil
end

return Hostility
