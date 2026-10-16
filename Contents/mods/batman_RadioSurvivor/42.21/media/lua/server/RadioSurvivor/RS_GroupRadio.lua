-- Radio Survivor : radio des groupes équipés (E08-T06). Fiche : docs/conception/radio-groupes.md.
--
-- Un groupe de Living Knox qui tient un poste émetteur (type au format 2 : homeRadio au foyer, radio dans un profil ;
-- Provider.radios) devient une voix du réseau radio, comme les voix d'E05 :
--   - une fiche ENGENDRÉE par groupe (RS_Personas.setGenerated, jamais écrite dans le dossier des fiches), identifiant
--     grp_<n> ; même tirage de fréquence par partie, sans conflit, mémorisé dans le fichier de la partie (E05-T07),
--     même chaîne sans source physique (aucune position dans le paquet), même tri par le serveur (E05-T08) ;
--   - la fiche disparaît dès que le groupe n'a plus de poste utilisable (groupe disparu, décimé, plus personne au
--     foyer ni aucun porteur vivant) : chaîne retirée, plus aucune réponse ; relu toutes les REFRESH_MS ;
--   - une phrase dite sur sa fréquence (contrôles d'E05-T08 et d'E06-T03 dans RadioSurvivor_Server.lua) devient une
--     demande npc_talk du PNJ qui répond (chef s'il atteint le poste) dans la FILE ORDONNÉE DU CARNET : même fiche, même
--     mémoire du pont, mêmes quotas (délai par personnage, MAX_PER_HOUR, MAX_PENDING) que la parole de proximité ; une
--     décision ne crée donc jamais un second état sur l'autre canal ;
--   - par radio, aucune décision : ni offre, ni acceptation, ni accord, ni départ (réponse à intention none seulement ;
--     le reste se fait de vive voix) ; jamais de foyer ni de coordonnée : le contexte du fournisseur n'en a pas,
--     la consigne radio l'interdit, et toute suite de 4 chiffres ou plus de la réplique est masquée avant l'antenne ;
--   - la réplique part sur la chaîne de la voix (file de diffusion de RadioSurvivor_Server.lua), l'historique du carnet
--     de l'appelant la garde ; sans réponse : parasites et refus NoAnswer, comme une voix d'E05.
-- Autorité seulement. Messages console en anglais.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Personas = require "RadioSurvivor/RS_Personas"
local P = require "RadioSurvivor/RS_NPCProvider"
local C = require "RadioSurvivor/RS_Config"
local Codec = require "RadioSurvivor/RS_Codec"
local T = require "RadioSurvivor/RS_Transport"
local TextCut = require "RadioSurvivor/RS_TextCut"
local Rep = require "RadioSurvivor/RS_Reputation"

local GroupRadio = {}

-- Plage de tirage : tous les postes émetteurs vanilla (talkies 1 à 5, bricolé, HAM, haut de gamme ; base
-- radio-dynamic.md, plages de réglage), comme Walt.
GroupRadio.RANGE = "75.0-149.8"
GroupRadio.REFRESH_MS = 30000
GroupRadio.NAME_MAX = 64
GroupRadio.ACKS_MAX = 16          -- = garde de RS_Carnet_Server.talk
-- Consigne jointe au contexte (anglais, composée par le serveur ; le pont la lit dans le contexte d'autorité).
GroupRadio.NOTE = "You are answering a call on your group's radio. The caller only hears your voice and cannot see"
    .. " you. Never tell where your home or your group is: no place name, street, landmark, direction, distance or"
    .. " coordinates, even if asked. Make no offer, deal or promise over the radio: that is only done face to face."

local state = { outstanding = {}, nextRefreshMs = 0, air = nil, notify = nil, comfort = nil }
GroupRadio.state = state
-- Compteurs (suites en jeu, diagnostic) : répliques diffusées, appels restés sans réponse.
GroupRadio.stats = { aired = 0, failed = 0 }

-- RadioSurvivor_Server.lua donne sa file de diffusion air(khz, lignes, cid, onAir), notify(cléAppelant, commande, args)
-- et comfort(cléAppelant, cid) -> onAir, le réconfort de l'appelant quand la réplique passe à l'antenne (E05-T15).
function GroupRadio.bind(air, notify, comfort)
    state.air, state.notify, state.comfort = air, notify, comfort
end

-- "grp-<n>" -> "grp_<n>" (identifiant de fiche : minuscules, chiffres, soulignés), ou nil.
function GroupRadio.voiceId(ref)
    local n = type(ref) == "string" and string.match(ref, "^grp%-(%d+)$")
    return n and ("grp_" .. n) or nil
end

local function sheetLines(entry, id)
    local name = string.gsub(Const.oneLine(entry.name), "[%c]", " ")
    if name == "" then name = "Group radio" end
    if string.len(name) > GroupRadio.NAME_MAX then name = string.sub(name, 1, GroupRadio.NAME_MAX) end
    return { "format=1", "id=" .. id, "name=" .. name, "language=en", "frequency_range=" .. GroupRadio.RANGE,
        "radio=any", "listen=always", "location=none", "actions=say", "budget=0", "call_one_in=0", "state=active",
        "[prompt]",
        "Radio of a Living Knox group: its replies come from the notebook NPC requests (RS_GroupRadio), never from"
            .. " this text." }
end

-- Groupe équipé maintenant ({ ref, name, speaker }), ou nil.
function GroupRadio.equipped(ref)
    if not P.available() then return nil end
    for _, entry in ipairs(P.radios()) do
        if entry.ref == ref then return entry end
    end
    return nil
end

-- Fiches engendrées remises à jour ; relecture des voix si l'ensemble a changé.
function GroupRadio.refresh()
    local map = {}
    if Const.isEnabled() and P.available() then
        for _, entry in ipairs(P.radios()) do
            local id = GroupRadio.voiceId(entry.ref)
            if id then map[id] = { lines = sheetLines(entry, id), group = entry.ref } end
        end
    end
    if Personas.setGenerated(map) then Personas.reload() end
end

-- Masque toute suite de 4 chiffres ou plus (coordonnées de la carte : 4 à 5 chiffres).
function GroupRadio.redact(text)
    return (string.gsub(text, "%d%d%d%d+", "..."))
end

-- Réplique d'une ligne en lignes de radio de Const.MAX_LINE_CHARS au plus, Const.MAX_LINES - 1 au plus (la première
-- ligne diffusée est un parasite). E17-T12 : chaque ligne s'affiche seule sur le récepteur, l'une après l'autre ;
-- coupée à une fin de phrase, sinon à une virgule, sinon entre deux mots (RS_TextCut.pieces), jamais dans un mot.
function GroupRadio.lines(text)
    local out = {}
    local pieces = TextCut.pieces(Const.oneLine((string.gsub(text, "[<>]", ""))), Const.MAX_LINE_CHARS)
    for i = 1, math.min(#pieces, Const.MAX_LINES - 1) do out[i] = pieces[i] end
    return out
end

-- Appel en attente d'une réponse pour cette clé d'appelant (RadioSurvivor_Server : refus Waiting).
function GroupRadio.waiting(key)
    for _, o in pairs(state.outstanding) do
        if o.caller == key then return true end
    end
    return false
end

-- Phrase d'un joueur sur la fréquence d'une voix de groupe (sheet.group). key : clé d'appelant de RadioSurvivor_Server,
-- cid : personnage du carnet (historique radio), language : code de langue. Rend la demande du carnet, ou nil et une
-- raison (anglais, journalisée par l'appelant ; le joueur n'entend que le silence).
function GroupRadio.talk(player, key, sheet, khz, text, language, cid)
    local Server = RS_CarnetServer
    local S = Server and Server.store
    if not S or not S.data or S.blocked then return nil, "notebook state not ready" end
    local character = Server.bound[player]
    local record = character and S.data.characters[character]
    if not record or record.retired then return nil, "caller without a notebook character" end
    language = C.languageCode(language)
    local entry = GroupRadio.equipped(sheet.group)
    if not entry then return nil, "group " .. tostring(sheet.group) .. " holds no transmitter now" end
    local npc = Server.ensure(entry.speaker)
    if not npc or not npc.alive or npc.incarnation ~= entry.speaker then return nil, "no fiche for the speaker" end
    if type(text) ~= "string" or text == "" or string.len(Codec.toUtf8(text)) > C.MAX_TEXT_BYTES then
        return nil, "text"
    end
    -- Mêmes quotas que la parole de proximité (RS_Carnet_Server.talk).
    local now = getTimestampMs()
    if Server.lastTalk[character] and now - Server.lastTalk[character] < C.COOLDOWN_MS then return nil, "cooldown" end
    local times = {}
    for _, t in ipairs(Server.times) do
        if now - t < 3600000 then times[#times + 1] = t end
    end
    Server.times = times
    if #Server.pending >= C.MAX_PENDING or #times >= C.MAX_PER_HOUR or #T.acks >= GroupRadio.ACKS_MAX then
        return nil, "notebook requests busy"
    end
    local known = Server.contact(character, npc)
    -- E04-T10 (Q10) : niveau de réputation du demandeur et dernier acte public (jamais de score).
    local context = { name = npc.name, background = npc.background, reputation = Rep.publicContext(character, S.data),
        agreements = npc.agreements, trust = known.trust or "Unassessed", caller = record.name,
        group = P.context(npc.incarnation, character, language), radio = { note = GroupRadio.NOTE } }
    -- E17-T08 inchangé : un inconnu n'apprend ni le groupe, ni son chef, ni son histoire.
    context.stage = Server.acquaintance(character, npc, known)
    local g = context.group
    if g and context.stage == "stranger" then context.group = { member = g.member, role = g.role, attitude = g.attitude } end
    local req = Server.enqueue(npc, "npc_talk", character, text, language, context, {})
    if not req then return nil, "notebook state not saved" end
    if not Server.syncTransport() then
        Const.log("group radio: request " .. req.id .. " queued, exchange file not written yet")
    end
    Server.lastTalk[character] = now
    Server.times[#Server.times + 1] = now
    known.history[#known.history + 1] = { id = req.id .. "-player", author = record.name, text = text }
    while #known.history > C.MAX_HISTORY do table.remove(known.history, 1) end
    S.save()
    state.outstanding[req.id] = { caller = key, character = character, khz = khz, voice = sheet.id,
        group = sheet.group, cid = cid }
    return req
end

-- Réponse du pont à une demande radio (appelée par RS_Carnet_Server.reply). Rend vrai, ou faux et la raison.
function GroupRadio.owns(id)
    return state.outstanding[id] ~= nil
end

function GroupRadio.reply(Server, req, result, npc)
    local o = state.outstanding[req.id]
    if not o then return false, "radio request unknown" end
    if result.intent ~= "none" or result.offer ~= "" then return false, "decision not available over the radio" end
    if not GroupRadio.equipped(o.group) then return false, "group holds no transmitter now" end
    local c = P.composition(npc.incarnation)
    if not c or c.ref ~= o.group then return false, "NPC no longer in the group" end
    if Personas.voiceAt(o.khz) ~= o.voice or not Personas.channel(o.khz) then return false, "radio channel gone" end
    local text = GroupRadio.redact(result.text)
    local lines = GroupRadio.lines(text)
    if #lines == 0 then return false, "empty text" end
    local S = Server.store
    local record = S.data.characters[o.character]
    local known = record and record.contacts[npc.id]
    if known then
        known.history[#known.history + 1] = { id = req.id, author = npc.name, text = table.concat(lines, " ") }
        while #known.history > C.MAX_HISTORY do table.remove(known.history, 1) end
        -- E17-T08 : un échange répondu de plus, comme de vive voix.
        known.exchanges = (known.exchanges or 0) + 1
        if type(known.firstHour) ~= "number" then known.firstHour = getGameTime():getWorldAgeHours() end
    end
    Server.acknowledge(req, true, {})
    if not S.save() then return false, "state not saved" end
    state.outstanding[req.id] = nil
    GroupRadio.stats.aired = GroupRadio.stats.aired + 1
    table.insert(lines, 1, "<bzzt>")
    if state.air then state.air(o.khz, lines, o.cid, state.comfort and state.comfort(o.caller, o.cid) or nil) end
    if state.notify then state.notify(o.caller, Const.CMD.DONE) end
    Server.publish()
    return true
end

-- Une fois par passage : fiches engendrées (toutes les REFRESH_MS), appels sans réponse (demande sortie de la file
-- du carnet sans réplique diffusée : refusée, pont muet) -> parasites et refus NoAnswer.
function GroupRadio.tick(now)
    if now >= state.nextRefreshMs then
        state.nextRefreshMs = now + GroupRadio.REFRESH_MS
        GroupRadio.refresh()
    end
    local Server = RS_CarnetServer
    if not Server then return end
    local live = {}
    for _, r in ipairs(Server.pending) do live[r.id] = true end
    local failed = {}
    for id in pairs(state.outstanding) do
        if not live[id] then failed[#failed + 1] = id end
    end
    for _, id in ipairs(failed) do
        local o = state.outstanding[id]
        state.outstanding[id] = nil
        GroupRadio.stats.failed = GroupRadio.stats.failed + 1
        Const.log("group radio: no answer for " .. id .. " (voice " .. o.voice .. ")")
        if state.air then state.air(o.khz, { "<fzzt>", "<szzt>" }) end
        if state.notify then state.notify(o.caller, Const.CMD.REJECTED, { reason = "NoAnswer" }) end
    end
end

-- Tests : état remis à zéro.
function GroupRadio.reset()
    state.outstanding, state.nextRefreshMs = {}, 0
end

return GroupRadio
