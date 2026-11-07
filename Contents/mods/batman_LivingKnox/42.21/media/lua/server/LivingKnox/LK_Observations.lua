-- Living Knox : observations personnelles des PNJ (E08-T02, ADR B11 ; dans Living Knox depuis E18-T27).
-- Journal borné par interlocuteur de la parole des PNJ (fiche de l'hôte de LK_Talk : fiche du carnet de RadioSurvivor,
-- ou interlocuteur de Living Knox seul, LK_TalkAlone ; créée au contact seulement) : ce que le PNJ a vu lui-même ou
-- entendu d'un autre PNJ. Une observation n'est jamais une preuve d'action : elle est jointe aux demandes PNJ (champ
-- observations=, docs/specifications-techniques/protocole-carnet-v2.md « Observations des PNJ ») et le pont la présente
-- comme un souvenir non vérifié, comme les propos des joueurs. Aucun système de rumeurs.
--
-- Entrée : { fact = <type de Obs.CFG.facts>, subject = <identifiant court [A-Za-z0-9_-]>, day = <jour de jeu,
-- entier >= 0>, place = <libellé court ou maille Observations.area, sans coordonnée exacte>, source = 'seen' |
-- 'heard_from:<npc>' }. Clé d'observation : fait|sujet|jour|lieu (lieu en minuscules) ; une même observation n'est
-- stockée qu'une fois par PNJ, avec sa chaîne de provenance (sources successives depuis la première : 'seen',
-- 'heard_from:<npc-1>', 'heard_from:<npc-2>'...).
--
-- Bornes (Obs.CFG) : maxPerNpc observations par PNJ (la plus ancienne évincée), maxChain éléments de chaîne (une
-- observation à chaîne pleine n'est plus retransmise), maxNpcs PNJ suivis (le moins récemment mis à jour évincé). Pas de
-- boucle : un PNJ déjà présent dans la chaîne (ou l'émetteur lui-même) ne la réapprend pas.
-- Stockage : état privé de la parole des PNJ (LK_Talk, Talk.data.observations, fichier talk-* de Living Knox, jamais en
-- ModData globale), Talk.dirty à chaque changement. Sans état chargé, sans hôte ou état bloqué, rien n'est enregistré.
-- Purge : fiches mortes ou retirées par l'hôte (prune, appelé par LK_Talk.turns).
-- Les déclencheurs (LK_ObservationTriggers) appellent record ; transmit sert aux conversations (E08-T04).
if isClient() then return end

require 'LivingKnox/LK_Core'
local Talk = require 'LivingKnox/LK_TalkHost'
local World = require 'RadioSurvivorCore/RC_WorldFacts'

local Obs = LivingKnox.Observations or {}
LivingKnox.Observations = Obs
Talk.observationLog = Obs

-- Personal observations (E08-T02). `facts` is the closed list of the E08-T01 triggers (same list as OBS_FACTS in
-- bridge/npc_protocol.py).
Obs.CFG = {
    facts = {'player_return', 'mission_done', 'group_death', 'assault_seen', 'weather', 'power_cut', 'helicopter'},
    maxPerNpc = 12,   -- oldest evicted
    maxChain = 4,     -- provenance entries ('seen', 'heard_from:<npc>'...); a full chain is not retold
    maxNpcs = 64,     -- tracked fiches, least recently updated evicted
    subjectChars = 48,
    placeChars = 32,
    areaTiles = 256,  -- coarse area of Obs.area (one map cell)
    -- E08-T07 triggers (LK_ObservationTriggers)
    returnHours = 24,     -- player_return: game hours out of hearing range before a comeback counts
    witnessRange = 20,    -- group_death: tiles between a witness body and the dead body (same floor, CanSee)
    -- E08-T08 world triggers (same file): weather and power cut polled at EveryHours, vanilla helicopter heard
    -- through its world sound (OnWorldSound, Helicopter.java:218).
    worldPlace = 'everywhere',  -- place of a global event (storm, power cut): one shared key for every witness
    helicopterSound = 500,      -- radius and volume of the vanilla helicopter world sound (source nil, z 0)
    helicopterRange = 500,      -- tiles between a witness (loaded body, else home) and a helicopter sound
    helicopterGapHours = 2,     -- game hours without a helicopter sound before the next sound is a new passage
    helicopterEveryMs = 5000,   -- helicopter sounds handled at most once per this real time (ms)
}
local B = Obs.CFG

local FACTS = {}
for _, name in ipairs(B.facts) do FACTS[name] = true end

local function dirty() Talk.dirty = true end

local function store()
    if not Talk.host or not Talk.data then return nil end
    if type(Talk.data.observations) ~= 'table' then Talk.data.observations = {seq = 0, npcs = {}} end
    local all = Talk.data.observations
    if type(all.npcs) ~= 'table' then all.npcs = {} end
    if type(all.seq) ~= 'number' then all.seq = 0 end
    return all
end

-- Fiche suivie : fiche existante et vivante de l'hôte.
local function tracked(npcId)
    if type(npcId) ~= 'string' or not Talk.host then return false end
    local npc = Talk.host.fiche(npcId)
    return type(npc) == 'table' and npc.alive ~= false
end
Obs.tracked = tracked

local function validId(value)
    return type(value) == 'string' and string.len(value) >= 1 and string.len(value) <= B.subjectChars
        and string.find(value, '^[%w_%-]+$') ~= nil
end

-- Lieu sur une ligne : contrôles et balises retirés, espaces réduits, coupé à placeChars ; nil si vide ou s'il
-- contient trois chiffres de suite (coordonnée exacte refusée : utiliser Obs.area).
Obs.MAX_CHAIN = B.maxChain -- read by the conversations (LK_Conversations)

function Obs.cleanPlace(text)
    if type(text) ~= 'string' then return nil end
    text = string.gsub(text, '[%c<>%[%]]', ' ')
    text = Talk.oneLine((string.gsub(text, '%s+', ' ')))
    if string.len(text) > B.placeChars then text = Talk.oneLine(string.sub(text, 1, B.placeChars)) end
    if text == '' or string.find(text, '%d%d%d') then return nil end
    return text
end

-- Maille approximative d'une position (areaTiles cases de côté) : 'area-<x>-<y>'.
function Obs.area(x, y)
    if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
    return 'area-' .. math.floor(x / B.areaTiles) .. '-' .. math.floor(y / B.areaTiles)
end

-- E08-T03 : heure de jeu (âge du monde en heures) à laquelle une observation a été rangée chez ce PNJ (champ `hour` de
-- l'entrée, absent du champ observations= des demandes) ; nil sans horloge.
function Obs.hour()
    local gt = getGameTime and getGameTime()
    local hours = gt and gt:getWorldAgeHours()
    if type(hours) ~= 'number' or hours ~= hours or hours < 0 then return nil end
    return hours
end

-- Jour de jeu courant (1 = premier jour), 1 sans horloge.
Obs.today = World.today

local function sourceNpc(source)
    if type(source) ~= 'string' then return nil end
    local _, _, id = string.find(source, '^heard_from:(.+)$')
    return id
end

-- Observation validée et normalisée (copie), ou nil, motif.
local function normalize(npcId, obs)
    if type(obs) ~= 'table' then return nil, 'bad_obs' end
    for key in pairs(obs) do
        if key ~= 'fact' and key ~= 'subject' and key ~= 'day' and key ~= 'place' and key ~= 'source' then
            return nil, 'bad_obs'
        end
    end
    if not FACTS[obs.fact] then return nil, 'fact' end
    if not validId(obs.subject) then return nil, 'subject' end
    local day = obs.day
    if type(day) ~= 'number' or day ~= day or day < 0 or day ~= math.floor(day) or day > 1000000 then
        return nil, 'day'
    end
    local place = Obs.cleanPlace(obs.place)
    if not place then return nil, 'place' end
    local source = obs.source or 'seen'
    local from = sourceNpc(source)
    if source ~= 'seen' and not (validId(from) and from ~= npcId) then return nil, 'source' end
    return {fact = obs.fact, subject = obs.subject, day = day, place = place, source = source}
end

function Obs.keyOf(obs)
    return obs.fact .. '|' .. obs.subject .. '|' .. string.format('%.0f', obs.day) .. '|' .. string.lower(obs.place)
end

local function bucket(all, npcId, create)
    local b = all.npcs[npcId]
    if type(b) ~= 'table' or type(b.items) ~= 'table' then
        if not create then return nil end
        b = {items = {}, touched = 0}
        all.npcs[npcId] = b
    end
    return b
end

local function find(b, key)
    for i, item in ipairs(b.items) do
        if type(item) == 'table' and item.key == key then return item, i end
    end
    return nil
end

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

-- Retire le PNJ suivi le moins récemment mis à jour tant qu'il y en a plus que maxNpcs.
local function evictNpcs(all)
    while true do
        local count, oldest, oldestAt = 0, nil, nil
        for id, b in pairs(all.npcs) do
            count = count + 1
            local at = type(b) == 'table' and tonumber(b.touched) or -1
            if oldestAt == nil or at < oldestAt then oldest, oldestAt = id, at end
        end
        if count <= B.maxNpcs or oldest == nil then return end
        all.npcs[oldest] = nil
    end
end

-- Range une entrée déjà validée chez npcId ; rend la clé et 'ok' | 'duplicate' | 'upgraded'.
local function put(all, npcId, entry, chain)
    local b = bucket(all, npcId, true)
    all.seq = all.seq + 1
    local existing = find(b, entry.key)
    if existing then
        -- Déjà connue : stockée une seule fois. Seule une observation directe remplace un ouï-dire.
        if entry.source == 'seen' and existing.source ~= 'seen' then
            existing.source, existing.chain, existing.hour = 'seen', {'seen'}, Obs.hour()
            b.touched = all.seq
            dirty()
            return entry.key, 'upgraded'
        end
        return entry.key, 'duplicate'
    end
    entry.chain, entry.hour = chain, Obs.hour()
    b.items[#b.items + 1] = entry
    while #b.items > B.maxPerNpc do table.remove(b.items, 1) end
    b.touched = all.seq
    evictNpcs(all)
    dirty()
    return entry.key, 'ok'
end

-- Observation du PNJ npcId (fiche du carnet) ; source 'seen' par défaut. Rend la clé et 'ok' | 'duplicate' |
-- 'upgraded', ou nil et le motif du refus ('storage', 'fiche', 'bad_obs', 'fact', 'subject', 'day', 'place',
-- 'source').
function Obs.record(npcId, obs)
    local all = store()
    if not all then return nil, 'storage' end
    if not tracked(npcId) then return nil, 'fiche' end
    local entry, reason = normalize(npcId, obs)
    if not entry then return nil, reason end
    entry.key = Obs.keyOf(entry)
    return put(all, npcId, entry, {entry.source})
end

-- Observations du PNJ, de la plus ancienne à la plus récente (copies : key, fact, subject, day, place, source,
-- chain, hour) ; liste vide sans fiche suivie.
function Obs.list(npcId)
    local out = {}
    local all = store()
    local b = all and tracked(npcId) and bucket(all, npcId, false)
    if not b then return out end
    for _, item in ipairs(b.items) do
        if type(item) == 'table' and type(item.key) == 'string' then
            out[#out + 1] = {key = item.key, fact = item.fact, subject = item.subject, day = item.day,
                place = item.place, source = item.source, chain = copyList(item.chain), hour = item.hour}
        end
    end
    return out
end

-- Le PNJ fromNpc raconte son observation obsKey à toNpc (réception admissible déjà vérifiée par l'appelant) : le
-- destinataire la range en 'heard_from:<fromNpc>' avec la chaîne de l'émetteur prolongée. Rend la clé et 'ok' |
-- 'duplicate', ou nil et 'storage' | 'fiche' | 'self' | 'unknown' | 'loop' | 'chain'.
function Obs.transmit(fromNpc, toNpc, obsKey)
    local all = store()
    if not all then return nil, 'storage' end
    if not tracked(fromNpc) or not tracked(toNpc) then return nil, 'fiche' end
    if fromNpc == toNpc then return nil, 'self' end
    local b = bucket(all, fromNpc, false)
    local item = b and type(obsKey) == 'string' and find(b, obsKey)
    if not item then return nil, 'unknown' end
    local chain = copyList(item.chain)
    for _, step in ipairs(chain) do
        if sourceNpc(step) == toNpc then return nil, 'loop' end
    end
    local target = bucket(all, toNpc, false)
    if target and find(target, obsKey) then return obsKey, 'duplicate' end
    if #chain >= B.maxChain then return nil, 'chain' end
    local source = 'heard_from:' .. fromNpc
    chain[#chain + 1] = source
    return put(all, toNpc, {key = obsKey, fact = item.fact, subject = item.subject, day = item.day,
        place = item.place, source = source}, chain)
end

-- Fiche morte ou retirée : son journal est oublié (ce qu'elle a raconté reste chez les autres).
function Obs.forget(npcId)
    local all = store()
    if all and npcId ~= nil and all.npcs[npcId] ~= nil then
        all.npcs[npcId] = nil
        dirty()
    end
end

-- Journaux des fiches disparues ou mortes retirés. Rend true si quelque chose a été retiré.
function Obs.prune()
    local all = store()
    if not all then return false end
    local doomed = {}
    for id in pairs(all.npcs) do
        if not tracked(id) then doomed[#doomed + 1] = id end
    end
    for _, id in ipairs(doomed) do all.npcs[id] = nil end
    if #doomed > 0 then dirty() end
    return #doomed > 0
end

-- Nom d'une fiche de l'hôte ou d'un personnage, nil s'il est inconnu.
local function nameOf(id)
    if type(id) ~= 'string' or not Talk.host then return nil end
    local npc = Talk.host.fiche(id)
    if type(npc) == 'table' and type(npc.name) == 'string' and npc.name ~= '' then return npc.name end
    local name = Talk.host.characterName(id)
    if type(name) == 'string' and name ~= '' then return name end
    return nil
end

-- Champ observations= d'une demande PNJ : liste (de la plus ancienne à la plus récente) de cartes { fact, subject,
-- day, place, source = 'seen' | 'heard', hops = nombre de récits ('heard_from') de la chaîne, who = nom connu du
-- sujet (facultatif), teller = nom du PNJ qui l'a racontée (facultatif) } ; nil sans observation (champ absent). Ni
-- coordonnée exacte ni identifiant de PNJ : les noms seulement.
function Obs.field(npcId)
    local items = Obs.list(npcId)
    if #items == 0 then return nil end
    local out = {}
    for _, item in ipairs(items) do
        local entry = {fact = item.fact, subject = item.subject, day = item.day, place = item.place,
            source = item.source == 'seen' and 'seen' or 'heard', hops = 0}
        for _, step in ipairs(item.chain) do
            if sourceNpc(step) then entry.hops = entry.hops + 1 end
        end
        entry.who = nameOf(item.subject)
        local teller = sourceNpc(item.source)
        if teller then entry.teller = nameOf(teller) or 'someone' end
        out[#out + 1] = entry
    end
    return out
end

return Obs
