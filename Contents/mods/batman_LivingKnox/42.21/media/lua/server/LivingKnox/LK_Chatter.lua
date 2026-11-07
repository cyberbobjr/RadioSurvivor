-- Living Knox : bavardage entre deux membres d'un groupe à leur foyer (E18-T32, décisions de l'utilisateur du
-- 2026-11-07). Autorité seulement. Contrat : docs/specifications-techniques/protocole-carnet-v2.md « Bavardage d'un
-- groupe (E18-T32) » ; conversations : LK_Conversations.
--
-- Ouverture (un passage toutes les EVERY_MS, appelé par Talk.turns quand aucune conversation d'observation ne s'est
-- ouverte à ce passage : une observation à transmettre passe avant) : deux fiches vivantes, corps chargés, du même
-- groupe, toutes deux au foyer (HOME_RADIUS cases en x et en y de la case du foyer, même étage : règle « au foyer »
-- de LK_Decisions), à RANGE cases l'une de l'autre (sans exiger de vue : deux pièces du foyer, essai du 2026-11-07),
-- libres (aucune demande en file, aucune conversation, non occupées), et au moins un joueur lié entend la première
-- (Provider.hears). Délai par GROUPE : celui de l'option LivingKnox.InitiativeFrequency par PNJ (Rares 24 h de jeu,
-- Normales 1 h, Fréquentes 30 min), gardé dans l'état privé (Talk.data.chatter.last) ; Désactivées : aucun
-- bavardage. Les répliques comptent dans les mêmes plafonds que les conversations (LK_Conversations : plafond du
-- niveau de l'option, plafond commun du serveur).
-- Sans réponse possible du modèle (pont réputé arrêté, budget) : rien ne s'ouvre et rien n'est consommé.
--
-- Sujet tiré de l'état réel du groupe : besoin le plus pressant (LivingKnox.Stock.needs : catégorie et état ; vide
-- ou critique : ce sujet d'abord), moral (g.morale : low, steady, high), temps qu'il fait (RC_WorldFacts.weather),
-- chef (nom du chef vivant). Longueur selon le sujet (TURNS : 2 à 4 répliques). Le bavardage dure tant que les deux
-- restent au foyer (ils vaquent chez eux) ; il s'arrête si l'un en sort, meurt ou est occupé. Le reste (tours, réponse,
-- intervention d'un joueur, historique des contacts existants) est celui des conversations.
if isClient() then return end

local Talk = require 'LivingKnox/LK_TalkHost'
local World = require 'RadioSurvivorCore/RC_WorldFacts'
local I = require 'LivingKnox/LK_Initiatives'
local V = require 'LivingKnox/LK_Conversations'
local P = Talk.provider

local Ch = {}
Ch.CFG = {
    EVERY_MS = 5000,     -- recherche d'un bavardage au plus toutes les 5 s réelles
    RANGE = 8,           -- cases entre les deux membres à l'ouverture, même étage (ensuite : tous deux au foyer)
    HOME_RADIUS = 10,    -- cases : « au foyer » (LK_Decisions.CFG.HOME_RADIUS)
    MORALE_LOW = 35,     -- moral 0..100 : bas en dessous, haut à partir de MORALE_HIGH
    MORALE_HIGH = 70,
    MAX_DETAIL = 48,     -- octets du détail du sujet (CHATTER_DETAIL_BYTES du pont)
}
-- Répliques selon le sujet (décision : 2 à 4 selon le sujet).
Ch.TURNS = {needs = 4, leader = 3, morale = 3, weather = 2}
Ch.stats = {opened = 0}
local nextPass = 0

-- Tirage d'un entier 1..n (serveur ; remplaçable par les bancs).
function Ch.draw(n)
    if ZombRand then return ZombRand(n) + 1 end
    return math.random(n)
end

-- État privé : { last = { [groupe] = heure de jeu du dernier bavardage } }.
local function store()
    local data = Talk.data
    if not data then return nil end
    data.chatter = data.chatter or {last = {}}
    return data.chatter
end

local function groupOf(npc)
    local record = P.npc(npc.incarnation)
    local gid = record and tostring(record.group or '') or ''
    if gid == '' then return nil end
    local G = LivingKnox.Groups
    local g = G and G.get and G.get(gid)
    if not g or type(g.home) ~= 'table' then return nil end
    return gid, g
end

local function homeOf(g)
    return {x = g.home.x, y = g.home.y, z = g.home.z, radius = Ch.CFG.HOME_RADIUS}
end

-- Même étage, à RANGE cases au plus ; aucune vue exigée (ils se parlent d'une pièce à l'autre de leur foyer : campagne
-- MP du 2026-11-07, deux membres à 1,8 case séparés par une cloison n'ouvraient rien pendant 30 s).
local function close(ba, bb)
    if math.floor(ba:getZ()) ~= math.floor(bb:getZ()) then return false end
    local dx, dy = ba:getX() - bb:getX(), ba:getY() - bb:getY()
    return dx * dx + dy * dy <= Ch.CFG.RANGE * Ch.CFG.RANGE
end

local function free(server, npc)
    return npc and npc.alive and not I.hasPending(server, npc.id) and not V.busy(npc.id)
        and not P.engaged(npc.incarnation)
end

local function clip(text)
    text = tostring(text or '')
    if #text > Ch.CFG.MAX_DETAIL then text = string.sub(text, 1, Ch.CFG.MAX_DETAIL) end
    return text
end

-- Sujets possibles du groupe gid, g ({ subject, detail }) ; urgent : un besoin vide ou critique.
function Ch.topics(gid, g)
    local out, urgent = {}, nil
    local S = LivingKnox.Stock
    local a = S and S.needs and S.needs(gid)
    local need = a and a.needs and a.needs[1]
    if need then
        out[#out + 1] = {subject = 'needs', detail = clip(need.c .. ' ' .. need.status)}
        if need.status == 'empty' or need.status == 'critical' then urgent = out[#out] end
    end
    if type(g.morale) == 'number' then
        local word = 'steady'
        if g.morale < Ch.CFG.MORALE_LOW then word = 'low' elseif g.morale >= Ch.CFG.MORALE_HIGH then word = 'high' end
        out[#out + 1] = {subject = 'morale', detail = word}
    end
    local weather = World.weather()
    if weather then out[#out + 1] = {subject = 'weather', detail = weather} end
    local leader = g.leader and g.members and g.members[g.leader]
    if leader and leader.alive and leader.npc then
        local record = P.npc(leader.npc)
        if record and record.name then out[#out + 1] = {subject = 'leader', detail = clip(record.name)} end
    end
    return out, urgent
end

-- Sujet du bavardage : un besoin urgent d'abord, sinon un sujet tiré ; nil sans sujet.
function Ch.topic(gid, g)
    local list, urgent = Ch.topics(gid, g)
    if urgent then return urgent end
    if #list == 0 then return nil end
    return list[Ch.draw(#list)]
end

-- Deux membres libres au foyer, proches, la première entendue d'un joueur : { a, b, gid, g } ou nil.
local function pairAtHome(server, st, hour, rule)
    local objects = server.objects()
    local byGroup, ids = {}, {}
    for id in pairs(objects) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local npc, body = server.fiche(id), objects[id]
        if npc and body and not body:isDead() and free(server, npc) then
            local gid, g = groupOf(npc)
            local last = gid and st.last[gid]
            if gid and not (last and hour - last < rule.npcHours) and V.atHome(body, homeOf(g)) then
                byGroup[gid] = byGroup[gid] or {g = g, list = {}}
                local list = byGroup[gid].list
                list[#list + 1] = {npc = npc, body = body}
            end
        end
    end
    local gids = {}
    for gid in pairs(byGroup) do gids[#gids + 1] = gid end
    table.sort(gids)
    for _, gid in ipairs(gids) do
        local list = byGroup[gid].list
        for i = 1, #list do
            if #I.listeners(server, list[i].body) > 0 then
                for j = 1, #list do
                    if j ~= i and close(list[i].body, list[j].body) then
                        return {a = list[i].npc, b = list[j].npc, gid = gid, g = byGroup[gid].g}
                    end
                end
            end
        end
    end
    return nil
end

-- Passage : au plus un bavardage ouvert. Rend la conversation ouverte, ou nil.
function Ch.tick(server, now)
    now = now or getTimestampMs()
    if now < nextPass then return nil end
    nextPass = now + Ch.CFG.EVERY_MS
    local rule = I.LEVELS[I.level()]
    local st = store()
    local hour = World.hour()
    if not rule or not st or not hour or not P.available() then return nil end
    -- Rien sans le modèle : ni ouverture ni délai consommé.
    if not V.canSpeak(server, now) then return nil end
    local found = pairAtHome(server, st, hour, rule)
    if not found then return nil end
    local topic = Ch.topic(found.gid, found.g)
    if not topic then return nil end
    local conv = V.openChatter(server, found.a, found.b, topic, Ch.TURNS[topic.subject] or 2, now, homeOf(found.g))
    if not conv or not conv.waiting then return nil end
    st.last[found.gid] = hour
    Talk.dirty = true
    Ch.stats.opened = Ch.stats.opened + 1
    return conv
end

-- Délais oubliés (bancs) : les délais par groupe restent dans l'état privé.
function Ch.reset()
    nextPass = 0
    Ch.stats = {opened = 0}
end

Talk.chatter = Ch

return Ch
