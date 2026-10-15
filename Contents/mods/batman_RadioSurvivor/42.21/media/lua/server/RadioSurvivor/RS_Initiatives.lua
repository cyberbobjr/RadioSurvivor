-- Radio Survivor : initiative de parole d'un PNJ à proximité (E08-T03, ADR B04 « Initiative acceptée »).
-- Autorité seulement (serveur MP ou solo). Fiche : docs/conception/initiatives.md ; contrat : docs/protocole-carnet-v2.md
-- « Initiative d'un PNJ (E08-T03) ».
--
-- Un PNJ du carnet prend la parole de lui-même quand, à un passage (toutes les EVERY_MS) :
--   - sa fiche est vivante et son corps chargé (Server.objects), aucune demande de ce PNJ n'attend le pont ;
--   - il a une observation récente (RS_Observations, rangée chez lui depuis moins de RECENT_HOURS heure de jeu) qui
--     n'a jamais ouvert d'initiative chez lui (événement = fiche | clé d'observation, gardé dans l'état privé) ;
--   - au moins un joueur lié au carnet l'entend (Provider.hears, depuis la position de son corps) ;
--   - il n'est pas occupé (Provider.engaged : coup reçu ou combat, sommation, alerte ; LivingKnox.API.engaged) ;
--   - le niveau de l'option sandbox RadioSurvivor.InitiativeFrequency le permet : délai par PNJ en heures de jeu
--     depuis sa dernière initiative (gardé dans l'état privé : un redémarrage ou une reconnexion ne le remet pas à
--     zéro) ; plafond serveur en demandes LLM par heure réelle (mémoire, comme les autres budgets du carnet).
-- Au plus une initiative ouverte par passage. L'événement est marqué consommé dès l'ouverture : une même observation
-- n'ouvre jamais deux initiatives (regroupement des répétitions), même après une sortie puis un retour dans la portée,
-- une reconnexion ou un redémarrage.
-- Demande : kind npc_initiative, dans la MÊME file ordonnée par PNJ que les sollicitations (Server.pending, ordre du
-- PNJ, un seul tour en cours par PNJ chez le pont) ; sans texte de joueur ; event = carte de l'observation ;
-- toutes les demandes comptent dans le plafond commun C.MAX_PER_HOUR (Server.times). Réponse (I.reply) : caduque si la
-- situation a changé (corps absent ou mort, PNJ occupé, observation sortie de son journal, plus personne n'entend) ;
-- sinon dite par le canal de parole de LK11-T04 (Provider.say : bulle et ligne de chat aux auditeurs de cet instant),
-- et ajoutée à l'historique des contacts EXISTANTS des auditeurs (aucun contact ni fiche créé).
-- Sans réponse possible du LLM (pont réputé arrêté, budget épuisé) : silence, aucune réplique de gabarit (E08-T09,
-- décision de l'utilisateur du 2026-10-14 : sans l'IA, le PNJ ne dit rien de lui-même) ; l'événement reste consommé.
-- Option « Désactivées » : aucune initiative.
-- Pont réputé arrêté après une demande restée sans réponse (C.REQUEST_TIMEOUT_MS) ; réputé revenu dès qu'une réponse
-- arrive (une sollicitation de joueur suffit) ; pendant l'arrêt, une seule demande d'essai au plus toutes les
-- PROBE_MS.
if isClient() then return end

local C = require 'RadioSurvivor/RS_Config'
local P = require 'RadioSurvivor/RS_NPCProvider'
local S = require 'RadioSurvivor/RS_State'
local Obs = require 'RadioSurvivor/RS_Observations'
local Radio = require 'RadioSurvivor/RadioSurvivor_Const'
local T = require 'RadioSurvivor/RS_Transport'

local I = {}
I.KIND = 'npc_initiative'
I.OPTION = 'RadioSurvivor.InitiativeFrequency'
-- Niveaux de l'option enum (index 1..4) : délai par PNJ (heures de jeu) et demandes LLM par heure réelle (serveur).
I.LEVELS = {
    [1] = nil,                                  -- désactivées
    [2] = {npcHours = 24, perHour = 2},         -- rares
    [3] = {npcHours = 1, perHour = 6},          -- normales
    [4] = {npcHours = 0.5, perHour = 12},       -- fréquentes
}
I.DEFAULT_LEVEL = 3
I.CFG = {
    RECENT_HOURS = 1,      -- observation rangée depuis moins d'une heure de jeu
    EVERY_MS = 5000,       -- un passage au plus toutes les 5 s réelles
    MAX_REPLY = 200,       -- octets d'une réplique (LivingKnox.Speech.MAX_TEXT ; INITIATIVE_REPLY_BYTES du pont)
    PROBE_MS = 600000,     -- pont réputé arrêté : une demande d'essai au plus toutes les 10 min
    MAX_PENDING_ACKS = 16, -- même seuil que talk (acquittements non soldés)
}
I.times = {}                                  -- demandes LLM d'initiative de l'heure réelle écoulée (ms)
I.bridge = {down = false, probeAt = 0}
I.stats = {opened = 0, llm = 0, silent = 0, said = 0, stale = 0}
local nextPass = 0

local function count(name) I.stats[name] = (I.stats[name] or 0) + 1 end

-- Niveau de l'option (1..4) : option enregistrée (Java) d'abord, puis SandboxVars, puis la valeur par défaut.
function I.level()
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options.getOptionByName and options:getOptionByName(I.OPTION)
    local value = option and option:getValue() or nil
    if value == nil then
        local vars = SandboxVars and SandboxVars.RadioSurvivor
        value = vars and vars.InitiativeFrequency
    end
    value = math.floor(tonumber(value) or I.DEFAULT_LEVEL)
    if value < 1 or value > 4 then value = I.DEFAULT_LEVEL end
    return value
end

-- État privé : { done = { [fiche|clé] = heure de jeu }, last = { [fiche] = heure de la dernière initiative } }.
local function store()
    if not S.data or S.blocked then return nil end
    local st = S.data.initiatives
    if type(st) ~= 'table' then st = {}; S.data.initiatives = st end
    if type(st.done) ~= 'table' then st.done = {} end
    if type(st.last) ~= 'table' then st.last = {} end
    return st
end

-- Événements et délais périmés retirés (borne naturelle : seuls les événements de l'heure écoulée comptent).
local function prune(st, hour, rule)
    local keep = {}
    for key, at in pairs(st.done) do
        if type(at) == 'number' and hour - at <= I.CFG.RECENT_HOURS + 1 then keep[key] = at end
    end
    st.done = keep
    local last = {}
    for id, at in pairs(st.last) do
        if type(at) == 'number' and S.data.npcs[id] and hour - at < rule.npcHours + 1 then last[id] = at end
    end
    st.last = last
end

local function eventKey(npcId, obsKey) return npcId .. '|' .. obsKey end

local function language()
    local forced = Radio.callLanguage and Radio.callLanguage()
    if forced then return forced end
    local current = Translator and Translator.getLanguage and Translator.getLanguage()
    return C.languageCode(current and tostring(current:name()) or 'EN')
end

local function hasPending(server, npcId)
    for _, r in ipairs(server.pending) do
        if r.npc == npcId then return true end
    end
    return false
end

-- Joueurs liés au carnet qui entendent le corps (triés par personnage : ordre stable).
local function listeners(server, object)
    local out = {}
    for player, cid in pairs(server.bound) do
        if P.hears(object, player, C.HEARING_RANGE) then out[#out + 1] = {player = player, character = cid} end
    end
    table.sort(out, function(a, b) return a.character < b.character end)
    return out
end

-- Observation la plus récente de la fiche, rangée depuis moins de RECENT_HOURS et jamais utilisée ; nil sinon.
local function freshObservation(st, npcId, hour)
    local items = Obs.list(npcId)
    for i = #items, 1, -1 do
        local item = items[i]
        local age = type(item.hour) == 'number' and hour - item.hour or nil
        if age and age >= 0 and age < I.CFG.RECENT_HOURS and not st.done[eventKey(npcId, item.key)] then return item end
    end
    return nil
end

-- Carte d'observation de la demande (même forme qu'une entrée du champ observations=).
local function card(npcId, item)
    for _, entry in ipairs(Obs.field(npcId) or {}) do
        if entry.fact == item.fact and entry.subject == item.subject and entry.day == item.day
                and entry.place == item.place then return entry end
    end
    return nil
end

local function recentCalls(now)
    local kept = {}
    for _, t in ipairs(I.times) do if now - t < 3600000 then kept[#kept + 1] = t end end
    I.times = kept
    return #kept
end

local function serverCalls(server, now)
    local n = 0
    for _, t in ipairs(server.times) do if now - t < 3600000 then n = n + 1 end end
    return n
end

-- Le pont peut recevoir une demande d'initiative maintenant (pont réputé présent, ou essai dû).
local function bridgeReady(now)
    if not I.bridge.down then return true end
    return now >= I.bridge.probeAt
end

-- Sans demande au LLM (pont arrêté, hors budget, demande impossible) : silence (E08-T09), jamais de gabarit.
local function silent()
    count('silent')
    return 'silent'
end

local function open(server, st, npc, item, heard, rule, hour, now)
    st.done[eventKey(npc.id, item.key)] = hour
    st.last[npc.id] = hour
    S.dirty = true
    count('opened')
    local busy = #server.pending >= C.MAX_PENDING or serverCalls(server, now) >= C.MAX_PER_HOUR
        or #T.acks >= I.CFG.MAX_PENDING_ACKS
    if not bridgeReady(now) or busy or recentCalls(now) >= rule.perHour then return silent() end
    local event = card(npc.id, item)
    if not event then return silent() end
    local lang = language()
    local g = P.context(npc.incarnation, nil, lang)
    -- Plusieurs auditeurs, connus ou non : règle de l'inconnu (E17-T08) pour tous, jamais le groupe ni le foyer.
    local context = {name = npc.name, background = npc.background, audience = #heard,
        group = g and {member = g.member, role = g.role} or nil}
    local req = server.enqueue(npc, I.KIND, 'system', nil, lang, context, {})
    if not req then return silent() end
    req.event = event
    req.observations = Obs.field(npc.id)
    if I.bridge.down then I.bridge.probeAt = now + I.CFG.PROBE_MS end
    I.times[#I.times + 1] = now
    server.times[#server.times + 1] = now
    server.syncTransport()
    count('llm')
    print('[RS_Initiatives] initiative ' .. req.id .. ' of ' .. tostring(npc.id) .. ' about ' .. item.fact
        .. ' (' .. #heard .. ' listener(s))')
    return 'llm', req
end

-- Passage (appelé une fois par seconde par le carnet ; cadence propre EVERY_MS). Rend le résultat de l'initiative
-- ouverte ('llm', 'silent') ou nil.
function I.tick(server, now)
    now = now or getTimestampMs()
    if now < nextPass then return nil end
    nextPass = now + I.CFG.EVERY_MS
    local rule = I.LEVELS[I.level()]
    local st = store()
    local hour = Obs.hour()
    if not rule or not st or not hour or not P.available() then return nil end
    prune(st, hour, rule)
    local ids = {}
    for id in pairs(server.objects) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local npc, object = S.data.npcs[id], server.objects[id]
        local last = st.last[id]
        if npc and npc.alive and object and not object:isDead() and not hasPending(server, id)
                and not (server.conversations and server.conversations.busy(id)) -- E08-T04: not while talking
                and not (last and hour - last < rule.npcHours) then
            local item = freshObservation(st, id, hour)
            if item and not P.engaged(npc.incarnation) then
                local heard = listeners(server, object)
                if #heard > 0 then return open(server, st, npc, item, heard, rule, hour, now) end
            end
        end
    end
    return nil
end

-- Une demande quitte la file : réponse reçue (le pont est là) ou délai écoulé sans réponse (pont réputé arrêté).
function I.observe(req, answered, now)
    if answered then
        I.bridge.down = false
    elseif req and (req.kind == 'npc_talk' or req.kind == I.KIND or req.kind == 'npc_converse') -- E08-T04
            and not I.bridge.down then
        I.bridge.down = true
        I.bridge.probeAt = (now or getTimestampMs()) + I.CFG.PROBE_MS
        print('[RS_Initiatives] bridge considered stopped: no reply to ' .. tostring(req.id)
            .. ', initiatives and conversations stay silent')
    end
end

-- Réponse du pont à une initiative (contrôles communs déjà faits par le carnet). Rend true, ou false et la raison.
function I.reply(server, req, result, npc)
    if result.intent ~= 'none' or result.offer ~= '' then return false, 'initiative with an intent' end
    if #result.text > I.CFG.MAX_REPLY then return false, 'initiative text too long (' .. #result.text .. ')' end
    local object = server.objects[npc.id]
    if not object or object:isDead() then count('stale'); return false, 'initiative stale: body not loaded or dead' end
    local busy, why = P.engaged(npc.incarnation)
    if busy then count('stale'); return false, 'initiative stale: NPC busy (' .. tostring(why) .. ')' end
    local event = type(req.event) == 'table' and req.event or nil
    local key = event and Obs.keyOf(event) or nil
    local kept = false
    for _, item in ipairs(Obs.list(npc.id)) do
        if item.key == key then kept = true end
    end
    if not kept then count('stale'); return false, 'initiative stale: observation gone' end
    local out, reason = P.say(npc.incarnation, result.text, {name = npc.name, chat = true, range = C.HEARING_RANGE})
    if not out then count('stale'); return false, 'initiative stale: ' .. tostring(reason) end
    for _, p in ipairs(out.heard or {}) do
        local cid = server.bound[p]
        local record = cid and S.data.characters[cid]
        local known = record and record.contacts[npc.id]
        if known then
            known.history[#known.history + 1] = {id = req.id, author = npc.name, text = result.text}
            while #known.history > C.MAX_HISTORY do table.remove(known.history, 1) end
        end
    end
    count('said')
    return true
end

-- Mémoire remise à zéro (bancs de test). Une fiche morte ou retirée perd son délai au prochain passage (prune).
function I.reset()
    I.times, I.bridge, nextPass = {}, {down = false, probeAt = 0}, 0
    I.stats = {opened = 0, llm = 0, silent = 0, said = 0, stale = 0}
end

-- E08-T04: helpers shared with the NPC conversations (RS_Conversations).
I.listeners, I.language, I.card, I.hasPending = listeners, language, card, hasPending

return I
