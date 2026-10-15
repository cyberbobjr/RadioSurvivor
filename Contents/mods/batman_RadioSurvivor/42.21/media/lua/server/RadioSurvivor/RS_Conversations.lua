-- Radio Survivor : conversation entre deux PNJ proches (E08-T04, ADR B11 « Conversations et transmissions entre PNJ »).
-- Autorité seulement (serveur MP ou solo). Fiche : docs/conception/conversations.md ; contrat : docs/protocole-carnet-v2.md
-- « Conversation entre deux PNJ (E08-T04) ».
--
-- Ouverture (un passage toutes les EVERY_MS, une conversation ouverte au plus par passage) : un PNJ « conteur » dont la
-- fiche est vivante et le corps chargé, non occupé (Provider.engaged), sans demande en file ni conversation en cours, a
-- dans son journal (RS_Observations) une observation que son voisin ne connaît pas et peut apprendre (absent de la
-- chaîne, chaîne non pleine). Le voisin est un corps du fournisseur à RANGE cases au plus (Provider.near : même étage,
-- distance, CanSee), non occupé, sans demande en file ; sa fiche existe, ou il est d'un groupe déjà contacté (une fiche
-- de ce groupe figure dans les contacts d'un personnage) et le carnet compte moins de MAX_FICHES fiches : sa fiche est
-- alors créée (aucune autre fiche n'est jamais créée ici). Délai PAIR_HOURS (heures de jeu, état privé) avant une
-- nouvelle conversation entre les mêmes fiches.
-- Personne n'entend (aucun joueur lié au carnet n'entend le corps du conteur, Provider.hears) : transmission
-- silencieuse, Obs.transmit sans texte, une par paire et par délai, aucun appel LLM.
-- Sinon conversation identifiée (mémoire du serveur, perdue au redémarrage) : participants, sujet = clé d'observation,
-- MAX_TURNS tours au plus (conteur, voisin, conteur, voisin), durée bornée MAX_MS, TURN_GAP_MS entre deux répliques.
-- À chaque tour : les deux corps chargés, vivants, proches (RANGE) et non occupés, sinon fin (interruption : le récit
-- non encore reçu n'est pas transmis) ; auditeurs recalculés depuis le corps du locuteur ; personne n'entend : fin, avec
-- transmission silencieuse si le récit n'est pas encore passé. Un tour = une demande npc_converse (même file ordonnée par
-- PNJ que les sollicitations, plafond commun C.MAX_PER_HOUR, plafond propre du niveau de l'option
-- RadioSurvivor.InitiativeFrequency) ; la réplique est dite par Provider.say (canal de LK11-T04, auditeurs de cet
-- instant) et ajoutée à l'historique des contacts EXISTANTS des auditeurs.
-- Réception : le voisin n'apprend le récit qu'une fois la première réplique du conteur dite alors qu'il est encore à
-- portée (Obs.transmit : provenance heard_from, pas de boucle, chaîne de 4) ; jamais à la préparation de la demande.
-- Sans réponse possible du LLM (pont réputé arrêté I.bridge.down, hors budget, option « Désactivées ») : aucune
-- conversation entendue ne s'ouvre et une conversation en cours se termine au tour suivant, sans réplique de gabarit
-- (E08-T09, décision de l'utilisateur du 2026-10-14 : sans l'IA, deux PNJ ne discutent pas) ; aucun récit n'est alors
-- transmis par elle. Rien n'est consommé (ni délai de paire ni fiche créée) : la paire peut parler au retour du pont.
-- La transmission silencieuse (personne n'entend, aucun appel LLM) est inchangée.
-- Fin sans boucle : un récit reçu ne retourne jamais à celui qui l'a raconté (chaîne), une paire attend PAIR_HOURS.
--
-- Intervention d'un joueur (E08-T05, ADR B11 « Intervention du joueur », ADR B04 « Ordre ») : un joueur qui a
-- sélectionné l'un des deux PNJ et lui parle (commande talk du carnet, chat local ou ligne « Dire ») s'insère dans la
-- liste canonique des répliques de la conversation, dans l'ordre d'admission du serveur. Sa phrase reste une demande
-- npc_talk ordinaire (file du PNJ, quotas, droits du personnage inchangés : aucun mandat de faction conféré) ; son
-- contexte porte l'interlocuteur et les répliques que le PNJ a entendues (le modèle choisit : répondre, ignorer,
-- poursuivre). Tant qu'une intervention attend sa réponse, la conversation ne demande aucune réplique (aucun double
-- engagement) ; une réplique de conversation déjà demandée est revalidée à sa réception : si une ligne a été ajoutée
-- depuis (révision de la conversation), elle est refusée sans être dite et redemandée avec les nouveaux tours. La
-- réponse admise au joueur devient une réplique de la conversation ; une intervention sans réponse admise met fin à
-- la conversation. Chaque ligne garde les PNJ qui l'ont entendue : un locuteur ne reçoit que celles-là.
if isClient() then return end

local C = require 'RadioSurvivor/RS_Config'
local P = require 'RadioSurvivor/RS_NPCProvider'
local S = require 'RadioSurvivor/RS_State'
local Obs = require 'RadioSurvivor/RS_Observations'
local I = require 'RadioSurvivor/RS_Initiatives'
local T = require 'RadioSurvivor/RS_Transport'
local Codec = require 'RadioSurvivor/RS_Codec'
local TextCut = require 'RadioSurvivor/RS_TextCut'

local V = {}
V.KIND = 'npc_converse'
V.CFG = {
    RANGE = 4,             -- cases entre les deux corps (Provider.near)
    EVERY_MS = 5000,       -- recherche d'une nouvelle conversation au plus toutes les 5 s réelles
    MAX_TURNS = 4,         -- répliques d'une conversation LLM
    MAX_MS = 180000,       -- durée bornée d'une conversation (temps réel)
    TURN_GAP_MS = 6000,    -- entre deux répliques (lecture de la bulle ; LK_Speech.GAP_MS)
    PAIR_HOURS = 6,        -- heures de jeu avant une nouvelle conversation entre les mêmes fiches
    MAX_REPLY = 200,       -- octets d'une réplique (LivingKnox.Speech.MAX_TEXT ; CONVERSE_REPLY_BYTES du pont)
    MAX_FICHES = 64,       -- borne des fiches du carnet pour créer celle du voisin (RS_Config.Observations.maxNpcs)
    MAX_PENDING_ACKS = 16,
    MAX_NAME = 48,         -- octets d'un nom dans une réplique (CONVERSE_NAME_BYTES du pont)
    MAX_TALK_LINES = 6,    -- répliques de la conversation jointes à une intervention (npc_talk)
}

V.active = {}   -- conversations en cours : [id] = conversation
V.times = {}    -- demandes LLM de conversation de l'heure réelle écoulée (ms)
V.interventions = {} -- E08-T05 : [id de la demande npc_talk] = id de la conversation (réponse attendue)
V.stats = {opened = 0, silent = 0, llm = 0, said = 0, learned = 0, ended = 0, stale = 0, joined = 0}
local seq, nextPass = 0, 0

local function count(name) V.stats[name] = (V.stats[name] or 0) + 1 end

-- État privé : { pairs = { ['fiche-a|fiche-b'] = heure de jeu de la dernière conversation } }.
local function store()
    if not S.data or S.blocked then return nil end
    local st = S.data.conversations
    if type(st) ~= 'table' then st = {}; S.data.conversations = st end
    if type(st.pairs) ~= 'table' then st.pairs = {} end
    return st
end

local function pairKey(a, b)
    if a < b then return a .. '|' .. b end
    return b .. '|' .. a
end

local function prune(st, hour)
    local keep = {}
    for key, at in pairs(st.pairs) do
        if type(at) == 'number' and hour - at < V.CFG.PAIR_HOURS then keep[key] = at end
    end
    st.pairs = keep
end

-- Fiche engagée dans une conversation en cours (aucune initiative ni autre conversation pendant ce temps).
function V.busy(ficheId)
    for _, conv in pairs(V.active) do
        if conv.a == ficheId or conv.b == ficheId then return true end
    end
    return false
end

local function recentCalls(now)
    local kept = {}
    for _, t in ipairs(V.times) do if now - t < 3600000 then kept[#kept + 1] = t end end
    V.times = kept
    return #kept
end

local function serverCalls(server, now)
    local n = 0
    for _, t in ipairs(server.times) do if now - t < 3600000 then n = n + 1 end end
    return n
end

-- Groupes déjà contactés : groupe de chaque fiche présente dans les contacts d'un personnage.
local function contactedGroups()
    local out = {}
    for _, record in pairs(S.data.characters or {}) do
        for id in pairs(type(record.contacts) == 'table' and record.contacts or {}) do
            local npc = S.data.npcs[id]
            if npc and type(npc.clan) == 'string' and npc.clan ~= '' then out[npc.clan] = true end
        end
    end
    return out
end

local function ficheCount()
    local n = 0
    for _ in pairs(S.data.npcs) do n = n + 1 end
    return n
end

-- Observation la plus récente du conteur que le voisin peut apprendre (absente de son journal, voisin absent de la
-- chaîne, chaîne non pleine) ; nil sinon.
local function teachable(tellerId, listenerId)
    local known = {}
    if listenerId then
        for _, item in ipairs(Obs.list(listenerId)) do known[item.key] = true end
    end
    local items = Obs.list(tellerId)
    for i = #items, 1, -1 do
        local item = items[i]
        local ok = not known[item.key] and #item.chain < C.Observations.maxChain
        if ok and listenerId then
            for _, step in ipairs(item.chain) do
                if step == 'heard_from:' .. listenerId then ok = false end
            end
        end
        if ok then return item end
    end
    return nil
end

local function free(server, npc)
    return npc and npc.alive and not I.hasPending(server, npc.id) and not V.busy(npc.id)
        and not P.engaged(npc.incarnation)
end

-- Voisin admissible du conteur (corps à portée) et son observation à apprendre : fiche (existante ou à créer), objet,
-- observation ; nil sinon.
local function partnerOf(server, npc, object, bodies, groups, st)
    local ids = {}
    for pid in pairs(bodies) do
        if pid ~= npc.incarnation then ids[#ids + 1] = pid end
    end
    table.sort(ids, function(x, y) return tostring(x) < tostring(y) end)
    for _, pid in ipairs(ids) do
        local body = bodies[pid]
        if P.near(object, body, V.CFG.RANGE) then
            local fiche = server.find(pid)
            if fiche and fiche.incarnation == pid then
                if free(server, fiche) and not st.pairs[pairKey(npc.id, fiche.id)] then
                    local item = teachable(npc.id, fiche.id)
                    if item then return {fiche = fiche, pid = pid, body = body, item = item} end
                end
            elseif not fiche and not P.engaged(pid) then
                local record = P.npc(pid)
                local group = record and tostring(record.group or '') or ''
                if group ~= '' and groups[group] and ficheCount() < V.CFG.MAX_FICHES then
                    local item = teachable(npc.id, nil)
                    if item then return {pid = pid, body = body, item = item} end
                end
            end
        end
    end
    return nil
end

local function transmit(conv, how)
    if conv.learned then return end
    conv.learned = true
    local key, why = Obs.transmit(conv.a, conv.b, conv.subject)
    if key and why == 'ok' then count('learned') end
    print('[RS_Conversations] ' .. tostring(conv.a) .. ' told ' .. tostring(conv.b) .. ' (' .. how .. '): '
        .. tostring(why))
end

local function finish(conv, reason)
    if not V.active[conv.id] then return end
    V.active[conv.id] = nil
    count('ended')
    for rid, cid in pairs(V.interventions) do
        if cid == conv.id then V.interventions[rid] = nil end
    end
    print('[RS_Conversations] conversation ' .. conv.id .. ' ended after ' .. #conv.lines .. ' line(s): ' .. reason)
end

-- Les deux participants peuvent encore se parler (corps chargés, vivants, proches, non occupés).
local function together(conv, bodies)
    local a, b = S.data.npcs[conv.a], S.data.npcs[conv.b]
    local ba, bb = bodies[conv.aInc], bodies[conv.bInc]
    if not (a and a.alive and b and b.alive and ba and bb) then return false, 'participant gone' end
    if not P.near(ba, bb, V.CFG.RANGE) then return false, 'out of range' end
    if P.engaged(conv.aInc) or P.engaged(conv.bInc) then return false, 'participant busy' end
    return true
end

-- Locuteur du tour suivant : le PNJ qui n'a pas dit la dernière réplique de PNJ (le conteur commence).
local function speakerOf(conv)
    if conv.last ~= conv.a then return conv.a, conv.aInc, conv.b end
    return conv.b, conv.bInc, conv.a
end

-- Texte borné à max octets UTF-8 (Kahlua : caractères UTF-16, Codec.toUtf8 compte les octets), coupé comme une bulle
-- (E17-T13, RS_TextCut.pieces : fin de phrase, sinon virgule, sinon entre deux mots ; jamais dans un mot quand une
-- coupe entre deux mots est possible) : une réponse au joueur (jusqu'à C.MAX_REPLY_BYTES) jointe au contexte d'un
-- tour n'arrive plus au modèle coupée au milieu d'un mot.
local function cut(text, max)
    text = tostring(text or '')
    local n = max
    while n > 0 do
        local piece = TextCut.pieces(text, n)[1] or ''
        local bytes = #Codec.toUtf8(piece)
        if bytes <= max then return piece end
        n = math.min(n - 1, #piece - (bytes - max))   -- chaque caractère compte un octet au moins
    end
    return ''
end

-- Ajoute une réplique dite à la liste canonique ; heard : fiches de PNJ qui l'ont entendue.
local function addLine(conv, who, text, heard, player)
    conv.lines[#conv.lines + 1] = {who = cut(who, V.CFG.MAX_NAME), text = cut(text, V.CFG.MAX_REPLY), heard = heard,
        player = player or nil}
    conv.rev = conv.rev + 1
end

-- Répliques entendues par une fiche, au format du contrat (who, text).
local function linesHeardBy(conv, ficheId)
    local out = {}
    for _, line in ipairs(conv.lines) do
        if line.heard[ficheId] then out[#out + 1] = {who = line.who, text = line.text} end
    end
    return out
end

-- Une intervention d'un joueur attend encore sa réponse.
local function held(conv)
    for _, cid in pairs(V.interventions) do
        if cid == conv.id then return true end
    end
    return false
end

local function llmAllowed(server, now)
    local rule = I.LEVELS[I.level()]
    if not rule or I.bridge.down then return false end
    if #server.pending >= C.MAX_PENDING or serverCalls(server, now) >= C.MAX_PER_HOUR
        or #T.acks >= V.CFG.MAX_PENDING_ACKS then return false end
    return recentCalls(now) < rule.perHour
end

local function llmTurn(server, conv, speakerId, partnerId, heard, now)
    local npc, partner = S.data.npcs[speakerId], S.data.npcs[partnerId]
    local event = I.card(speakerId, {fact = conv.item.fact, subject = conv.item.subject, day = conv.item.day,
        place = conv.item.place})
    if not event then return false end
    local lang = I.language()
    local g = P.context(npc.incarnation, nil, lang)
    local lines = linesHeardBy(conv, speakerId)
    local context = {name = npc.name, background = npc.background, audience = #heard, partner = partner.name,
        role = speakerId == conv.a and 'teller' or 'listener', turn = #lines + 1, turns = V.CFG.MAX_TURNS,
        lines = lines, group = g and {member = g.member, role = g.role} or nil}
    local req = server.enqueue(npc, V.KIND, 'system', nil, lang, context, {})
    if not req then return false end
    req.event = event
    req.observations = Obs.field(npc.id)
    V.times[#V.times + 1] = now
    server.times[#server.times + 1] = now
    server.syncTransport()
    conv.waiting, conv.waitingRev, conv.mode = req.id, conv.rev, 'llm'
    count('llm')
    print('[RS_Conversations] line ' .. (#conv.lines + 1) .. ' of ' .. conv.id .. ': request ' .. req.id)
    return true
end

local function hasRequest(server, id)
    for _, r in ipairs(server.pending) do
        if r.id == id then return true end
    end
    return false
end

-- Un tour d'une conversation en cours.
local function advance(server, conv, bodies, now)
    if conv.waiting then
        if not hasRequest(server, conv.waiting) then finish(conv, 'line refused or unanswered') end
        return
    end
    if now > conv.deadline then return finish(conv, 'time is up') end
    if held(conv) then return end -- E08-T05 : une intervention attend sa réponse (aucun double engagement)
    if now < conv.nextAt then return end
    if #conv.lines >= V.CFG.MAX_TURNS then return finish(conv, 'done') end
    local ok, why = together(conv, bodies)
    if not ok then return finish(conv, why) end
    local speakerId, speakerInc, partnerId = speakerOf(conv)
    local heard = I.listeners(server, bodies[speakerInc])
    if #heard == 0 then
        transmit(conv, 'silent')
        return finish(conv, 'nobody hears')
    end
    if llmAllowed(server, now) and llmTurn(server, conv, speakerId, partnerId, heard, now) then return end
    -- E08-T09: no line of the model possible (bridge stopped, budget, option Off): silence, the conversation ends.
    finish(conv, 'no model line (bridge stopped, budget or option off)')
end

local function open(server, st, npc, found, hour, now, bodies)
    -- E08-T09: a heard conversation needs the model for its lines; without it nothing opens and nothing is consumed.
    local heard = #I.listeners(server, bodies[npc.incarnation]) > 0
    if heard and not llmAllowed(server, now) then return nil end
    local partner = found.fiche
    if not partner then
        partner = server.ensure(found.pid)
        if not partner then return nil end
        print('[RS_Conversations] fiche ' .. partner.id .. ' created for ' .. tostring(found.pid)
            .. ' (group already contacted)')
    end
    st.pairs[pairKey(npc.id, partner.id)] = hour
    S.dirty = true
    seq = seq + 1
    local conv = {id = 'cv-' .. seq .. '-' .. npc.id, a = npc.id, aInc = npc.incarnation, b = partner.id,
        bInc = partner.incarnation, subject = found.item.key, item = found.item, turn = 0, lines = {},
        started = now, deadline = now + V.CFG.MAX_MS, nextAt = now, learned = false, rev = 0}
    if not heard then
        transmit(conv, 'silent')
        count('silent')
        return 'silent', conv
    end
    V.active[conv.id] = conv
    count('opened')
    print('[RS_Conversations] conversation ' .. conv.id .. ' between ' .. npc.id .. ' and ' .. partner.id
        .. ' about ' .. found.item.fact)
    advance(server, conv, bodies, now)
    return 'opened', conv
end

-- Passage (appelé une fois par seconde par le carnet) : tours des conversations en cours, puis au plus une ouverture
-- toutes les EVERY_MS. Rend 'opened' ou 'silent' et la conversation quand une paire a été traitée, sinon nil.
function V.tick(server, now)
    now = now or getTimestampMs()
    local st = store()
    local hour = Obs.hour()
    if not st or not hour or not P.available() then return nil end
    local bodies = P.objects()
    local ids = {}
    for id in pairs(V.active) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local conv = V.active[id]
        if conv then advance(server, conv, bodies, now) end
    end
    if now < nextPass then return nil end
    nextPass = now + V.CFG.EVERY_MS
    prune(st, hour)
    local groups = contactedGroups()
    local fiches = {}
    for id in pairs(server.objects) do fiches[#fiches + 1] = id end
    table.sort(fiches)
    for _, id in ipairs(fiches) do
        local npc, object = S.data.npcs[id], server.objects[id]
        if object and not object:isDead() and free(server, npc) and #Obs.list(id) > 0 then
            local found = partnerOf(server, npc, object, bodies, groups, st)
            local kind, conv = nil, nil
            if found then kind, conv = open(server, st, npc, found, hour, now, bodies) end
            if kind then return kind, conv end
        end
    end
    return nil
end

-- Réponse du pont à un tour (contrôles communs déjà faits par le carnet). Rend true, ou false et la raison.
function V.reply(server, req, result, npc)
    if result.intent ~= 'none' or result.offer ~= '' then return false, 'conversation line with an intent' end
    if #result.text > V.CFG.MAX_REPLY then return false, 'conversation line too long (' .. #result.text .. ')' end
    local conv
    for _, c in pairs(V.active) do
        if c.waiting == req.id then conv = c end
    end
    if not conv then count('stale'); return false, 'conversation line stale: conversation over' end
    conv.waiting = nil
    -- E08-T05 : revalidée avec les nouveaux tours : une ligne ajoutée depuis la demande (intervention d'un joueur, sa
    -- réponse) rend la réplique caduque ; elle n'est pas dite et sera redemandée avec la liste à jour.
    if conv.rev ~= conv.waitingRev then
        count('stale')
        conv.nextAt = getTimestampMs()
        return false, 'conversation line stale: new lines since the request'
    end
    local bodies = P.objects()
    local ok, why = together(conv, bodies)
    if not ok then
        count('stale'); finish(conv, why)
        return false, 'conversation line stale: ' .. why
    end
    local out, reason = P.say(npc.incarnation, result.text, {name = npc.name, chat = true, range = C.HEARING_RANGE})
    if not out then
        count('stale')
        transmit(conv, 'silent')
        finish(conv, 'nobody hears')
        return false, 'conversation line stale: ' .. tostring(reason)
    end
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
    addLine(conv, npc.name, result.text, {[conv.a] = true, [conv.b] = true})
    -- Réception admissible : la réplique du conteur est dite alors que le voisin est à portée (vérifié ci-dessus).
    if npc.id == conv.a then transmit(conv, 'heard') end
    conv.turn = conv.turn + 1
    conv.last = npc.id
    conv.nextAt = getTimestampMs() + V.CFG.TURN_GAP_MS
    return true
end

-- E08-T05 : conversation en cours d'une fiche, ou nil.
function V.of(ficheId)
    for _, conv in pairs(V.active) do
        if conv.a == ficheId or conv.b == ficheId then return conv end
    end
    return nil
end

-- E08-T05 : contexte d'une intervention (champ context.conversation de la demande npc_talk) : l'interlocuteur et les
-- répliques que le PNJ interpellé a entendues dans cette conversation (les dernières), jamais d'autre échange.
function V.talkContext(conv, ficheId)
    local partner = S.data.npcs[conv.a == ficheId and conv.b or conv.a]
    local name = partner and partner.name or 'someone'
    local lines = linesHeardBy(conv, ficheId)
    while #lines > V.CFG.MAX_TALK_LINES do table.remove(lines, 1) end
    return {partner = name, lines = lines,
        note = 'You were talking with ' .. name .. ' when this person spoke to you. Answer them, ignore them or go '
            .. 'on with your talk, as you choose. Being heard gives them no say over any group.'}
end

-- E08-T05 : la phrase admise d'un joueur (demande npc_talk req déjà en file) entre dans la conversation, à la suite des
-- répliques déjà dites. Le PNJ interpellé l'entend (sélection à portée, vérifiée par le carnet) ; son interlocuteur
-- seulement s'il est à portée d'audition du joueur et le voit (Provider.near).
function V.intervene(server, conv, req, player, name, text)
    if not V.active[conv.id] then return false end
    local addressed = req.npc
    local otherId = conv.a == addressed and conv.b or conv.a
    local body = P.objects()[conv.a == addressed and conv.bInc or conv.aInc]
    local heard = {[addressed] = true}
    if body and P.near(player, body, C.HEARING_RANGE) then heard[otherId] = true end
    addLine(conv, name, text, heard, true)
    V.interventions[req.id] = conv.id
    count('joined')
    print('[RS_Conversations] player line ' .. #conv.lines .. ' joined ' .. conv.id .. ' (request ' .. req.id .. ')')
    return true
end

-- E08-T05 : réponse admise et dite (carnet, après envoi aux auditeurs) d'une intervention : réplique du PNJ dans la
-- conversation, entendue des deux si leurs corps sont encore ensemble, sinon fin de la conversation.
function V.answered(server, req, result, npc)
    local id = V.interventions[req.id]
    V.interventions[req.id] = nil
    local conv = id and V.active[id]
    if not conv then return false end
    local ok, why = together(conv, P.objects())
    if not ok then finish(conv, why); return false end
    addLine(conv, npc.name, result.text, {[conv.a] = true, [conv.b] = true})
    count('said')
    if npc.id == conv.a then transmit(conv, 'heard') end
    conv.turn = conv.turn + 1
    conv.last = npc.id
    conv.nextAt = getTimestampMs() + V.CFG.TURN_GAP_MS
    return true
end

-- E08-T05 : une demande quitte la file (poll) : une intervention restée sans réponse admise met fin à la conversation.
function V.settle(requestId)
    local id = V.interventions[requestId]
    if not id then return end
    V.interventions[requestId] = nil
    local conv = V.active[id]
    if conv then finish(conv, 'player line unanswered') end
end

-- Mémoire remise à zéro (bancs de test) ; les délais par paire restent dans l'état privé.
function V.reset()
    V.active, V.times, V.interventions, nextPass, seq = {}, {}, {}, 0, 0
    V.stats = {opened = 0, silent = 0, llm = 0, said = 0, learned = 0, ended = 0, stale = 0, joined = 0}
end

return V
