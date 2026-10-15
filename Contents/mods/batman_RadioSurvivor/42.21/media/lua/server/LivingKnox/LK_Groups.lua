-- Living Knox : registre serveur des groupes (LK08-T01). Fiche : docs/conception/groupes.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Registre (schéma 1), privé, jamais en ModData globale :
--   { schema = 1, nextId = <prochain numéro>, groups = { ["grp-<n>"] = group } }
--   group = { id = "grp-<n>", type = <LivingKnox.GroupTypes>, name = <1..NAME_MAX>, story = <0..STORY_MAX>,
--             founded = <jour>, leader = "m-<k>" ou absent (membre vivant), nextMember = <prochain numéro de membre>,
--             members = { ["m-<k>"] = { id = "m-<k>", role = <Config.GROUP_ROLES>, alive = booléen,
--                                       npc = "lk-<n>" (PNJ du registre des corps, LK_Identity) ou absent } },
--             home = { x, y, z } entiers ou absent (aucun chargement), needs = { food, medical, ammo } (0..100),
--             morale = 0..100, log = { { day, kind, text }, ... } (LOG_SIZE dernières entrées, la plus ancienne d'abord) }
-- Champs facultatifs ajoutés par la simulation hors écran (LK09-T01, LK_Simulation.lua ; schéma 1 inchangé : un
-- registre sans ces champs se relit tel quel, une version antérieure du mod les ignore et les conserve) :
--   registre : simHour = dernière heure de jeu simulée (entier >= 0 ; invalide : oublié, la simulation repart de
--              l'heure courante) ;
--   group    : rest = 0..100 (repos), task = dernière tâche hors écran choisie (même forme qu'un kind de journal) ;
--   member   : wound = 0..100 (blessure abstraite ; absent = 0).
-- Champ facultatif des expéditions abstraites (LK09-T02, LK_Simulation.lua ; schéma 1 inchangé) :
--   group    : expedition = { place = <forme d'un kind>, team = { "m-<k>", ... } (1 à MAX_MEMBERS identifiants de
--              membre bien formés, numéros < nextMember, sans doublon ; un membre retiré ou mort entre-temps est
--              seulement ignoré au retour), departed = heure de départ, returns = heure de retour (>= departed) }.
-- Expéditions physiques (LK05-T05, LK_Expeditions.lua ; schéma 1 inchangé, non contrôlé ici : LK_Expeditions le
-- contrôle et l'oublie s'il est malformé) : group.trips = { v, n, last, seen, cur } ; une expédition physique passée
-- hors écran porte en plus expedition.trip = numéro (champ supplémentaire accepté par validExpedition).
-- Événements de groupe (LK09-T05, LK_Simulation.lua) : aucun champ ajouté, seulement des entrées de journal
-- (departure, recruit, conflict, illness, clash, remains) et les entrées structurelles left, joined, died, leader.
-- Champs facultatifs de la population initiale (LK08-T05, LK_Population.lua ; schéma 1 inchangé) :
--   registre : populated = vrai (population initiale faite ou registre déjà peuplé : jamais refaite ; une valeur
--              non booléenne relue vaut vrai, par prudence) ;
--   group    : storySeed = graine de l'histoire (0..2^31-1) : LivingKnox.Stories.compose(type, storySeed) recompose
--              l'histoire complète, secrets compris, côté autorité ; story = son résumé anglais ;
--   member   : profile = identifiant du profil du type tiré, female = booléen, traits = { <trait>, ... } (1 à 16
--              noms ; forme seulement contrôlée ici : un trait ou un profil retiré des données ne fait rien écarter).
-- Champ facultatif des offres de ressources (LK12-T03, LK_API.lua ; schéma 1 inchangé, non contrôlé ici : LK_API le
-- contrôle et le remet à neuf s'il est malformé) :
--   group    : supply = { next, offers = { [need] = offre ouverte }, receipts = { reçu, ... } } (docs/api.md).
-- Champ facultatif des histoires enrichies (LK10-T03, LK_API.lua ; schéma 1 inchangé, non contrôlé ici : LK_API le
-- contrôle, ignore une entrée invalide ou périmée et la retire à l'écriture suivante) :
--   group    : enrich = { ["<group|m-<k>>:<en|fr>"] = { text, mode, version, day } } (docs/api.md).
-- Champs facultatifs du cadre de décision (LK05-T02, LK_Decisions.lua ; schéma 1 inchangé, forme d'un kind seulement
-- contrôlée ici : une valeur hors des listes fermées de LK_Decisions est ignorée par lui et remplacée à la notation) :
--   group    : objective = dernier objectif choisi (LivingKnox.Decisions.OBJECTIVES) ;
--   member   : duty = dernier poste attribué (LivingKnox.Decisions.DUTIES).
-- Champ facultatif des routines (LK05-T03, LK_Routines.lua ; schéma 1 inchangé, non contrôlé ici : LK_Routines le
-- contrôle et refait le relevé s'il est malformé ou si le foyer a changé) :
--   group    : posts = { v, hx, hy, hz, day, camp, posts = { { x, y, z, a, k } }, round = { { x, y, z } },
--              beds = { { x, y, z, bx, by, a, q } } } (relevé du foyer : postes de guet, ronde, couchages).
-- Champ facultatif des besoins individuels (LK05-T06, LK_Needs.lua ; schéma 1 inchangé, non contrôlé ici : LK_Needs
-- le contrôle et le remet à neuf s'il est malformé) :
--   member   : vitals = { hunger, thirst, fatigue, fear (entiers 0..100), hour (heure de jeu du dernier pas) }.
-- Champ facultatif de l'aménagement du foyer (LK08-T04, LK_Homes.lua ; schéma 1 inchangé, non contrôlé ici : LK_Homes le
-- contrôle et le refait si le foyer a changé) :
--   group    : furnish = { v, hx, hy, hz, style, day, state, placed = { { k, x, y, z } } } (marque « aménagé »).
-- Champ facultatif du stock réel (LK08-T06, LK_Stock.lua ; schéma 1 inchangé, non contrôlé ici : LK_Stock le contrôle
-- et le refait si le foyer a changé) :
--   group    : stock = { v, hx, hy, hz, fill, day, items = { { i, t, c, k } } } (inventaire de référence du foyer).
-- Champ facultatif de la décimation et de la relève (LK09-T04, LK_Population.lua ; schéma 1 inchangé, contrôlé ici) :
--   group    : gone = { cause = "wiped" | "dispersed", day = jour, hour = heure de jeu du constat, due = heure de
--              relève prévue (>= hour), relief = "grp-<n>" (groupe de relève, numéro < nextId) ou absent }.
--              Groupe disparu : aucun membre vivant (contrôlé), gardé au registre (foyer abandonné, aménagement et
--              stock laissés en place), aucun membre ajouté (addMember refuse). Une seule relève (relief posé une fois).
-- Identifiants jamais réutilisés : nextId (groupes) et nextMember (membres d'un groupe) ne reculent jamais.
-- Ancienneté d'un membre = son numéro (plus petit = plus ancien).
-- Jour = jours depuis le début du monde (getWorldAgeHours / 24, arrondi en dessous), 1 = premier jour.
--
-- Fichiers (mécanisme de LK_Store) : Zomboid/Lua/batman_RadioSurvivor/livingknox/groups-<partie>-<0|1>.txt, entête
-- LKGRP1, deux emplacements en alternance.
-- Relecture : schéma inconnu ou plus récent, structure générale fausse ou deux fichiers illisibles -> registre BLOQUÉ
-- (aucune écriture, fichiers conservés) ; un groupe invalide est écarté et journalisé, les autres gardés.
-- Écriture regroupée (LK13-T06, fiche groupes.md « Persistance ») : un changement marque le registre « à écrire »
-- (state.dirty) ; une seule écriture par image, à la fin de l'image (abonné OnTick placé en fin de liste), ou à
-- l'OnTickEvenPaused suivant si aucun OnTick n'a écrit (pause, PauseEmpty) ; à OnSave (solo : GameWindow.save) ; avant
-- une relecture (init). Groups.flush() écrit tout de suite (marques idempotentes qui exigent un registre écrit avant
-- ou après le monde : LK_Stock, LK_Fortify, LK_Homes, LK_Traces, LK_Trade). Relecture de contrôle : à la première
-- écriture de la session et sur demande (Groups.flush({ verify = true }), Groups.verifyFile()), plus à chaque écriture.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Store"

local Groups = LivingKnox.Groups or {}
LivingKnox.Groups = Groups

Groups.SCHEMA = 1
Groups.HEADER = "LKGRP1"
Groups.FILE = "groups"
Groups.ID_PREFIX = "grp-"
Groups.MEMBER_PREFIX = "m-"

-- Bornes (choix du 2026-10-10, fiche groupes.md) : quelques groupes de 4 à 8 membres prévus (LK08-T05), large marge.
Groups.MAX_GROUPS = 64
Groups.MAX_MEMBERS = 32
Groups.LOG_SIZE = 32
Groups.NAME_MAX = 64
Groups.STORY_MAX = 600
Groups.TEXT_MAX = 200
Groups.KIND_MAX = 24
Groups.TRAITS_MAX = 16
Groups.LEVEL_MAX = 100
Groups.DEFAULT_LEVEL = 50
Groups.NEEDS = { "food", "medical", "ammo" }
Groups.Z_MIN, Groups.Z_MAX = -32, 31
Groups.COORD_MAX = 2147483647

Groups.state = Groups.state or { data = nil, seq = 0, blocked = false, reason = nil, path = nil, dropped = 0 }
-- LK13-T06 : dirty = changements pas encore écrits (pending = le registre qui les porte, gardé même si data est remis
-- à nil) ; age = OnTickEvenPaused passés depuis, sans écriture ; verified = une écriture de la session relue.
Groups.stats = Groups.stats or { marks = 0, writes = 0, verified = 0 }

local function log() return LivingKnox.Log end
local function Store() return LivingKnox.Store end
local function Config() return LivingKnox.Config end

-- Type de groupe enregistré (LK08-T02 : registre LivingKnox.GroupTypes, rempli par les fichiers de données).
local function typeKnown(t) return LivingKnox.GroupTypes.isKnown(t) end

-- Contrôles de base ------------------------------------------------------------------------------------------------

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function isText(v, minLen, maxLen)
    return type(v) == "string" and #v >= minLen and #v <= maxLen
end

local function inList(list, value)
    if type(list) ~= "table" or type(value) ~= "string" then return false end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Rang d'un rôle dans l'ordre de succession (nil si inconnu).
local function roleRank(role)
    for i, v in ipairs(Config().GROUP_ROLES) do
        if v == role then return i end
    end
    return nil
end

local function numbered(prefix, id)
    if type(id) ~= "string" then return nil end
    local digits = string.match(id, "^" .. prefix .. "(%d+)$")
    if not digits or #digits > 9 then return nil end
    local n = tonumber(digits)
    if n < 1 then return nil end
    return n
end

-- Numéro d'un identifiant de groupe "grp-<n>" ou de membre "m-<k>" (nil si le format est faux).
function Groups.idNumber(id) return numbered("grp%-", id) end
function Groups.memberNumber(id) return numbered("m%-", id) end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end
Groups.copy = copy

local function clampLevel(v)
    v = math.floor(v + 0.5)
    if v < 0 then return 0 end
    if v > Groups.LEVEL_MAX then return Groups.LEVEL_MAX end
    return v
end

local function validHome(h)
    if type(h) ~= "table" then return false end
    return isInt(h.x, 0, Groups.COORD_MAX) and isInt(h.y, 0, Groups.COORD_MAX) and isInt(h.z, Groups.Z_MIN, Groups.Z_MAX)
end

local function validKind(kind)
    return isText(kind, 1, Groups.KIND_MAX) and string.match(kind, "^%a[%w_]*$") ~= nil
end

-- Profil de membre (même forme qu'un identifiant de type ou de profil de LK_GroupTypes).
local function validProfileId(v)
    return isText(v, 1, Groups.KIND_MAX) and string.match(v, "^%l[%l%d_]*$") ~= nil
end

-- Traits d'un membre : liste de 1 à TRAITS_MAX noms (forme d'un kind), sans trou.
local function validTraits(list)
    if type(list) ~= "table" then return false end
    local n = 0
    for key, v in pairs(list) do
        if not isInt(key, 1, Groups.TRAITS_MAX) or not validKind(v) then return false end
        n = n + 1
    end
    return n >= 1 and list[n] ~= nil
end

-- Champs facultatifs d'un membre (LK08-T05). Rend vrai, ou faux et une raison.
local function validMemberExtras(m)
    if m.profile ~= nil and not validProfileId(m.profile) then return false, "bad profile" end
    if m.female ~= nil and type(m.female) ~= "boolean" then return false, "bad female flag" end
    if m.traits ~= nil and not validTraits(m.traits) then return false, "bad traits" end
    return true
end

-- Expédition en cours d'un groupe (LK09-T02). Rend vrai, ou faux et une raison.
local function validExpedition(e, nextMember)
    if type(e) ~= "table" then return false, "expedition is not a table" end
    if not validKind(e.place) then return false, "bad expedition place" end
    if not isInt(e.departed, 0, Groups.COORD_MAX) or not isInt(e.returns, e.departed or 0, Groups.COORD_MAX) then
        return false, "bad expedition hours"
    end
    if type(e.team) ~= "table" then return false, "bad expedition team" end
    local n, seen = 0, {}
    for key, mid in pairs(e.team) do
        local k = Groups.memberNumber(mid)
        if not isInt(key, 1, Groups.MAX_MEMBERS) or not k or k >= nextMember or seen[mid] then
            return false, "bad expedition team"
        end
        seen[mid] = true
        n = n + 1
    end
    if n < 1 or e.team[n] == nil then return false, "bad expedition team" end
    return true
end

-- Causes d'une disparition (LK09-T04) : plus aucun vivant, ou dernier(s) survivant(s) partis (dispersion).
Groups.GONE_CAUSES = { "wiped", "dispersed" }

-- Marque de groupe disparu (LK09-T04). Rend vrai, ou faux et une raison.
local function validGone(gone, nextId)
    if type(gone) ~= "table" then return false, "gone is not a table" end
    if not inList(Groups.GONE_CAUSES, gone.cause) then return false, "bad gone cause" end
    if not isInt(gone.day, 0, Groups.COORD_MAX) or not isInt(gone.hour, 0, Groups.COORD_MAX)
        or not isInt(gone.due, gone.hour or 0, Groups.COORD_MAX) then
        return false, "bad gone hours"
    end
    if gone.relief ~= nil then
        local n = Groups.idNumber(gone.relief)
        if not n or n >= nextId then return false, "bad relief group" end
    end
    return true
end

-- Jour de jeu courant (1 = premier jour), 1 si l'horloge manque.
function Groups.today()
    local gt = getGameTime and getGameTime()
    if not gt then return 1 end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= "number" or hours ~= hours or hours < 0 then return 1 end
    return math.floor(hours / 24) + 1
end

-- Logique pure (registre passé en argument) -------------------------------------------------------------------------

function Groups.newRegistry()
    return { schema = Groups.SCHEMA, nextId = 1, groups = {} }
end

-- Contrôle d'un groupe relu, sous la clé id. Rend vrai, ou faux et une raison.
function Groups.validGroup(g, id, nextId)
    local n = Groups.idNumber(id)
    if not n or n >= nextId then return false, "bad group identifier" end
    if type(g) ~= "table" or g.id ~= id then return false, "id mismatch" end
    if not typeKnown(g.type) then return false, "unknown type " .. tostring(g.type) end
    if not isText(g.name, 1, Groups.NAME_MAX) then return false, "bad name" end
    if not isText(g.story, 0, Groups.STORY_MAX) then return false, "bad story" end
    if g.storySeed ~= nil and not isInt(g.storySeed, 0, Groups.COORD_MAX) then return false, "bad story seed" end
    if not isInt(g.founded, 0, Groups.COORD_MAX) then return false, "bad founding day" end
    if not isInt(g.nextMember, 1, Groups.COORD_MAX) then return false, "bad nextMember" end
    if type(g.members) ~= "table" then return false, "members is not a table" end
    local count, npcs = 0, {}
    for mid, m in pairs(g.members) do
        local k = Groups.memberNumber(mid)
        if not k or k >= g.nextMember then return false, "bad member identifier " .. tostring(mid) end
        if type(m) ~= "table" or m.id ~= mid then return false, "member " .. mid .. ": id mismatch" end
        if not roleRank(m.role) then return false, "member " .. mid .. ": unknown role " .. tostring(m.role) end
        if type(m.alive) ~= "boolean" then return false, "member " .. mid .. ": bad alive flag" end
        if m.wound ~= nil and not isInt(m.wound, 0, Groups.LEVEL_MAX) then
            return false, "member " .. mid .. ": bad wound"
        end
        local extrasOk, extrasWhy = validMemberExtras(m)
        if not extrasOk then return false, "member " .. mid .. ": " .. extrasWhy end
        if m.duty ~= nil and not validKind(m.duty) then return false, "member " .. mid .. ": bad duty" end
        if m.npc ~= nil then
            if not LivingKnox.Identity.isId(m.npc) then return false, "member " .. mid .. ": bad npc reference" end
            if npcs[m.npc] then return false, "npc " .. m.npc .. " referenced twice" end
            npcs[m.npc] = true
        end
        count = count + 1
    end
    if count > Groups.MAX_MEMBERS then return false, "too many members" end
    if g.gone ~= nil then
        local goneOk, goneWhy = validGone(g.gone, nextId)
        if not goneOk then return false, goneWhy end
        for mid, m in pairs(g.members) do
            if m.alive then return false, "gone group has a living member " .. mid end
        end
    end
    if g.leader ~= nil then
        local leader = type(g.leader) == "string" and g.members[g.leader] or nil
        if not leader then return false, "leader is not a member" end
        if not leader.alive then return false, "leader is dead" end
    end
    if g.home ~= nil and not validHome(g.home) then return false, "bad home" end
    if type(g.needs) ~= "table" then return false, "needs is not a table" end
    for _, key in ipairs(Groups.NEEDS) do
        if not isInt(g.needs[key], 0, Groups.LEVEL_MAX) then return false, "bad need " .. key end
    end
    if not isInt(g.morale, 0, Groups.LEVEL_MAX) then return false, "bad morale" end
    if g.rest ~= nil and not isInt(g.rest, 0, Groups.LEVEL_MAX) then return false, "bad rest" end
    if g.task ~= nil and not validKind(g.task) then return false, "bad task" end
    if g.objective ~= nil and not validKind(g.objective) then return false, "bad objective" end
    if g.expedition ~= nil then
        local expOk, expWhy = validExpedition(g.expedition, g.nextMember)
        if not expOk then return false, expWhy end
    end
    if type(g.log) ~= "table" then return false, "log is not a table" end
    local entries = 0
    for _ in pairs(g.log) do entries = entries + 1 end
    if entries > Groups.LOG_SIZE or #g.log ~= entries then return false, "bad log size" end
    for i = 1, entries do
        local e = g.log[i]
        if type(e) ~= "table" or not isInt(e.day, 0, Groups.COORD_MAX) or not validKind(e.kind)
            or not isText(e.text, 0, Groups.TEXT_MAX) then
            return false, "bad log entry " .. i
        end
    end
    return true
end

-- Identifiants des groupes triés par numéro (clés malformées en dernier, par ordre alphabétique).
local function sortedKeys(groups)
    local ids = {}
    for id in pairs(groups) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local na, nb = Groups.idNumber(a), Groups.idNumber(b)
        if na and nb then return na < nb end
        if na or nb then return na ~= nil end
        return tostring(a) < tostring(b)
    end)
    return ids
end

-- Contrôle d'un registre relu. Rend le registre (groupes invalides retirés) et la liste { { id, why } } des groupes
-- écartés ; ou nil, une raison et "schema" (schéma inconnu ou plus récent : refus) ou "invalid" (structure fausse).
-- Un même PNJ référencé par deux groupes : le groupe de plus grand numéro est écarté.
function Groups.validate(data)
    if type(data) ~= "table" then return nil, "group registry is not a table", "invalid" end
    if data.schema ~= Groups.SCHEMA then
        return nil, "unknown group registry schema " .. tostring(data.schema) .. " (this version reads "
            .. Groups.SCHEMA .. ")", "schema"
    end
    if not isInt(data.nextId, 1, Groups.COORD_MAX) then return nil, "bad nextId", "invalid" end
    if type(data.groups) ~= "table" then return nil, "groups is not a table", "invalid" end
    -- Heure simulée (LK09-T01) : facultative ; invalide, elle est oubliée (aucun rattrapage), le registre reste lisible.
    if data.simHour ~= nil and not isInt(data.simHour, 0, Groups.COORD_MAX) then data.simHour = nil end
    -- Population faite (LK08-T05) : facultative ; une valeur non booléenne vaut vrai (jamais de seconde population).
    if data.populated ~= nil and type(data.populated) ~= "boolean" then data.populated = true end
    local dropped, npcs = {}, {}
    for _, id in ipairs(sortedKeys(data.groups)) do
        local g = data.groups[id]
        local ok, why = Groups.validGroup(g, id, data.nextId)
        if ok then
            for _, m in pairs(g.members) do
                if m.npc ~= nil and npcs[m.npc] then
                    ok, why = false, "npc " .. m.npc .. " already in group " .. npcs[m.npc]
                end
            end
        end
        if ok then
            for _, m in pairs(g.members) do
                if m.npc ~= nil then npcs[m.npc] = id end
            end
        else
            dropped[#dropped + 1] = { id = tostring(id), why = why }
            data.groups[id] = nil
        end
    end
    return data, dropped
end

-- Successeur d'un chef (I6.6, API seulement) : parmi les membres vivants autres que le chef actuel, le rôle le plus
-- prioritaire (ordre de Config.GROUP_ROLES), puis le plus ancien (plus petit numéro). nil si personne.
function Groups.pickSuccessor(g)
    local best, bestRank, bestNum
    for mid, m in pairs(g.members) do
        if m.alive and mid ~= g.leader then
            local rank, num = roleRank(m.role) or 1000, Groups.memberNumber(mid)
            if not best or rank < bestRank or (rank == bestRank and num < bestNum) then
                best, bestRank, bestNum = mid, rank, num
            end
        end
    end
    return best
end

-- LK10-T02 : chaque entrée technique passe aussi par Groups.onLog(g, kind, text, day) (LK_Journal : journal de récit
-- tiré de la même écriture, donc sauvegardé avec elle), sans effet si absent ; son erreur est journalisée et
-- n'interrompt pas l'écriture en cours. Groups.hourContext : heure de jeu simulée en cours (posée par
-- LK_Simulation.advance pendant chaque heure simulée, nil sinon), lue par le journal pour dater ses entrées.
Groups.hourContext = nil

local function appendLog(g, kind, text, day)
    local entries = g.log
    entries[#entries + 1] = { day = day, kind = kind, text = text }
    while #entries > Groups.LOG_SIZE do table.remove(entries, 1) end
    local tap = Groups.onLog
    if tap ~= nil then
        local ok, err = pcall(tap, g, kind, text, day)
        if not ok then log().error("journal: %s entry of %s failed: %s", tostring(kind), tostring(g.id), tostring(err)) end
    end
end
Groups.appendLog = appendLog

-- Mort d'un membre vivant sur un groupe passé en argument (logique pure, sans sauvegarde ; partagée par markDead et
-- la simulation hors écran) : alive = faux, chef effacé s'il l'était, entrée « died ». Rend vrai si c'était le chef.
-- quiet = vrai : aucun fait « memberDied » publié (mort d'un membre incarné, LK09-T03 : LK_Bodies.onZombieDead l'a
-- déjà publié avec le corps ; une seule publication par mort).
function Groups.applyDeath(g, mid, day, quiet)
    local m = g.members[mid]
    m.alive = false
    local wasLeader = g.leader == mid
    if wasLeader then g.leader = nil end
    appendLog(g, "died", mid, day)
    if quiet then return wasLeader end
    -- E08-T07 : fait "memberDied" hors écran (LK_Core.publish). La simulation abstraite n'a pas de perception plus
    -- fine : témoins = PNJ (npc) des membres vivants présents au foyer (hors équipe d'une expédition en route).
    local away, witnesses = {}, {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, k in ipairs(g.expedition.team) do away[k] = true end
    end
    for k, other in pairs(g.members) do
        if k ~= mid and other.alive and not away[k] and other.npc ~= nil then witnesses[#witnesses + 1] = other.npc end
    end
    table.sort(witnesses)
    local home = type(g.home) == "table" and g.home or nil
    LivingKnox.publish("memberDied", { group = g.id, member = mid, npc = m.npc, day = day, offscreen = true,
        witnesses = witnesses, x = home and home.x or nil, y = home and home.y or nil })
    return wasLeader
end

-- Vivants d'un groupe (membres alive, expédition comprise).
function Groups.livingCount(g)
    local n = 0
    for _, m in pairs(g.members) do
        if m.alive then n = n + 1 end
    end
    return n
end

-- Groupe disparu (LK09-T04) : marque gone posée.
function Groups.isGone(g)
    return type(g) == "table" and g.gone ~= nil
end

-- Groupe disparu (LK09-T04) sur un groupe passé en argument (logique pure, sans contrôle ni sauvegarde ; l'appelant a
-- vérifié qu'aucun membre n'est vivant) : marque gone (cause, jour, heure du constat, heure de relève prévue),
-- entrée « gone » (cause). Le groupe reste au registre : foyer, aménagement et stock ne sont pas touchés.
function Groups.applyGone(g, cause, day, hour, due)
    g.gone = { cause = cause, day = day, hour = hour, due = due }
    appendLog(g, "gone", cause, day)
    log().info("group %s gone (%s) at hour %s, relief due at hour %s", g.id, cause, tostring(hour), tostring(due))
end

-- Nouveau chef (membre vivant ou nil) sur un groupe passé en argument (logique pure, sans contrôle ni sauvegarde).
function Groups.applyLeader(g, mid, day)
    g.leader = mid
    appendLog(g, "leader", mid or "", day)
end

-- Persistance ------------------------------------------------------------------------------------------------------

local function slotPath(slot)
    return Groups.state.path .. "-" .. slot .. ".txt"
end
Groups.slotPath = slotPath

local function block(reason)
    local st = Groups.state
    st.blocked, st.reason = true, reason
    log().error("group registry BLOCKED: %s; files kept for recovery (%s-0.txt, -1.txt)", reason, tostring(st.path))
    return false
end

-- Charge (ou crée) le registre des groupes de la partie courante. newWorld = vrai : registre vide. Rend vrai si prêt.
-- Des changements pas encore écrits (state.pending) sont d'abord écrits dans les fichiers qu'ils concernent : une
-- relecture ne perd jamais une écriture différée.
function Groups.init(newWorld)
    local st = Groups.state
    if st.dirty and st.pending ~= nil and not st.blocked and st.path ~= nil then Groups.flush() end
    st.data, st.seq, st.blocked, st.reason, st.dropped = nil, 0, false, nil, 0
    st.dirty, st.pending, st.age, st.verified = false, nil, 0, false
    if Groups.peekState ~= nil then Groups.peekState.byGid = {} end   -- LK13-T08 : vues du registre précédent oubliées
    st.path = Store().worldFileBase(Groups.FILE)
    local a, existsA = Store().readSlotFile(slotPath(0), Groups.HEADER)
    local b, existsB = Store().readSlotFile(slotPath(1), Groups.HEADER)
    local best = a
    if b and (not a or b.seq > a.seq) then best = b end
    local lastSeq = 0
    if a then lastSeq = a.seq end
    if b and b.seq > lastSeq then lastSeq = b.seq end
    if newWorld then
        st.data, st.seq = Groups.newRegistry(), lastSeq
        log().info("groups: new world, empty group registry")
        return Groups.save()
    end
    if not best then
        if existsA or existsB then return block("both group registry files are unreadable") end
        st.data, st.seq = Groups.newRegistry(), 0
        log().info("groups: no file yet, empty group registry")
        return true
    end
    local data, why, kind = Groups.validate(best.data)
    if not data then
        if kind == "schema" then return block(why) end
        return block("group registry file #" .. best.seq .. " is invalid: " .. why)
    end
    for _, d in ipairs(why) do
        log().error("group %s dropped at load (file #%s): %s", d.id, tostring(best.seq), d.why)
    end
    st.data, st.seq, st.dropped = data, best.seq, #why
    local count = 0
    for _ in pairs(data.groups) do count = count + 1 end
    log().info("groups loaded: %s group(s), %s dropped, file #%s", tostring(count), tostring(#why),
        tostring(best.seq))
    return true
end

function Groups.isReady()
    return Groups.state.data ~= nil and not Groups.state.blocked
end

function Groups.isBlocked()
    return Groups.state.blocked == true, Groups.state.reason
end

-- Charge le registre s'il ne l'est pas encore (rechargement Lua, événement manqué). Rend vrai si prêt.
function Groups.ensure()
    if Groups.state.data or Groups.state.blocked then return Groups.isReady() end
    return Groups.init(false)
end

-- Écrit data (défaut : le registre courant) dans l'emplacement suivant, tout de suite. Relu pour vérification si
-- verify, ou si aucune écriture de la session ne l'a encore été. Rend vrai si écrit (changements en attente compris).
local function write(data, verify)
    local st = Groups.state
    if st.blocked or not data then return false end
    verify = verify == true or not st.verified
    local seq = st.seq + 1
    local ok, why = Store().writeSlotFile(slotPath(seq % 2), Groups.HEADER, seq, data, not verify)
    if not ok then return block("group registry " .. why) end
    st.seq, st.dirty, st.pending, st.age = seq, false, nil, 0
    Groups.stats.writes = Groups.stats.writes + 1
    if verify then
        st.verified = true
        Groups.stats.verified = Groups.stats.verified + 1
    end
    return true
end

-- Écrit le registre courant tout de suite (verify : relu pour vérification). Rend vrai si écrit.
function Groups.save(verify)
    return write(Groups.state.data, verify)
end

-- Changement fait : écriture différée (fin de l'image, voir l'en-tête).
function Groups.markDirty()
    local st = Groups.state
    if st.data == nil or st.blocked then return false end
    st.dirty, st.pending, st.age = true, st.data, 0
    Groups.stats.marks = Groups.stats.marks + 1
    return true
end

function Groups.isDirty()
    return Groups.state.dirty == true
end

-- Écrit maintenant les changements en attente. opts.verify : relecture de contrôle. Rend vrai si le registre est à
-- jour dans les fichiers (rien en attente, ou écrit), faux si non prêt, bloqué ou écriture refusée (registre bloqué).
function Groups.flush(opts)
    local st = Groups.state
    if st.blocked then return false end
    if not st.dirty then return st.data ~= nil end
    return write(st.pending or st.data, type(opts) == "table" and opts.verify == true)
end

-- Relecture de contrôle sur demande : l'emplacement de la dernière écriture doit porter son numéro et se décoder.
-- Rend vrai, ou faux et une raison (fichier différent : registre bloqué, comme une écriture qui échoue à la relecture).
function Groups.verifyFile()
    local st = Groups.state
    if st.blocked or not st.data then return false, "group registry not ready" end
    if st.seq == 0 then return true end   -- rien écrit encore (aucun fichier attendu)
    local check = Store().readSlotFile(slotPath(st.seq % 2), Groups.HEADER)
    if not check or check.seq ~= st.seq then
        block("group registry write verification failed (" .. slotPath(st.seq % 2) .. ")")
        return false, "write verification failed"
    end
    Groups.stats.verified = Groups.stats.verified + 1
    return true
end

-- Écriture retenue (LK13-T09, fiche groupes.md « Écriture retenue ») : un travail étalé sur quelques images (pas
-- horaire de LK_Simulation, relecture du stock de LK_Stock : une étape par image) retient l'écriture de fin d'image
-- pour n'écrire qu'une fois, à sa fin (Groups.release(key) puis Groups.flush). Une retenue par clé (travaux
-- indépendants) ; chacune bornée : au plus frames débuts d'image (OnTickEvenPaused), puis l'écriture normale reprend
-- même sans release. Groups.flush() explicite (marques idempotentes, OnSave) écrit toujours tout de suite.
function Groups.hold(key, frames)
    local st = Groups.state
    st.holds = st.holds or {}
    local n = math.floor(tonumber(frames) or 0)
    if n > (st.holds[key] or 0) then st.holds[key] = n end
end

function Groups.release(key)
    local holds = Groups.state.holds
    if holds ~= nil then holds[key] = nil end
end

function Groups.isHeld()
    for _, n in pairs(Groups.state.holds or {}) do
        if n > 0 then return true end
    end
    return false
end

-- Début d'image : chaque retenue perd une image ; rend vrai si une retenue reste.
local function ageHolds(st)
    if st.holds == nil then return false end
    local held, done = false, {}
    for key, n in pairs(st.holds) do
        if n > 1 then
            st.holds[key] = n - 1
            held = true
        else
            done[#done + 1] = key
        end
    end
    for _, key in ipairs(done) do st.holds[key] = nil end
    return held
end

-- Fin de l'image (OnTick, placé en fin de liste) : une seule écriture pour tous les changements de l'image.
function Groups.onTick()
    if Groups.PEEK_CHECK then Groups.checkPeeks() end   -- LK13-T08 : écritures par une vue (contrôle facultatif)
    if Groups.state.dirty and not Groups.isHeld() then Groups.flush() end
end

local function onTickHandler() LivingKnox.Groups.onTick() end

-- Début de l'image (OnTickEvenPaused) : changements restés sans écriture une image entière (aucun OnTick : pause,
-- PauseEmpty) écrits ici ; sinon l'OnTick de cette image les écrit. Au premier passage, l'abonné OnTick (inscrit au
-- chargement) passe en fin de liste : même fonction retirée puis rajoutée depuis un autre événement de l'image (pas
-- de double appel, base kahlua-lua.md) ; enveloppe de mesure LK_Load déplacée de même (LK13-T12), un abonné
-- remplacé par un rechargement laissé en place.
function Groups.onTickEvenPaused()
    local st = Groups.state
    if Groups.PEEK_CHECK then Groups.checkPeeks() end
    if not st.tickHooked then
        st.tickHooked = true
        LivingKnox.requeue("OnTick", "Groups.flush", onTickHandler)   -- LK13-T12 : enveloppe de mesure comprise
    end
    if ageHolds(st) then return end   -- LK13-T09 : écriture retenue, bornée en images
    if not st.dirty then return end
    if (st.age or 0) >= 1 then
        Groups.flush()
    else
        st.age = (st.age or 0) + 1
    end
end

-- API (registre courant, écriture différée à chaque changement) ----------------------------------------------------
-- Chaque fonction rend son résultat, ou nil et une raison (anglais). Les lectures rendent des copies, sauf
-- Groups.peek (lecture en place, lecture seule, LK13-T08).

local NOT_READY = "group registry not ready"

local function registry()
    if not Groups.ensure() then return nil end
    return Groups.state.data
end

local function group(gid)
    local data = registry()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    return g
end

local function member(gid, mid)
    local g, why = group(gid)
    if not g then return nil, why end
    local m = type(mid) == "string" and g.members[mid] or nil
    if not m then return nil, "unknown member " .. tostring(mid) .. " in " .. gid end
    return m, g
end

-- LK13-T06 : le changement est écrit à la fin de l'image (Groups.flush pour une écriture immédiate). Une écriture
-- refusée plus tard bloque le registre (journal ERROR) : les appels suivants rendent "group registry not ready".
local function commit(result)
    if not Groups.markDirty() then return nil, "group registry write failed" end
    return result
end

local function dayOf(day)
    if day == nil then return Groups.today() end
    if not isInt(day, 0, Groups.COORD_MAX) then return nil end
    return day
end

local function npcOwner(data, npc)
    for gid, g in pairs(data.groups) do
        for mid, m in pairs(g.members) do
            if m.npc == npc then return gid, mid end
        end
    end
    return nil
end

-- Création d'un groupe dans un registre passé en argument (logique pure, sans sauvegarde ; partagée par create et
-- la population initiale). spec = { type, name, story, home, day (obligatoire ici), storySeed, needs = { food,
-- medical, ammo }, morale } (storySeed, needs, morale facultatifs : défauts DEFAULT_LEVEL). Rend le groupe vivant
-- (pas une copie), ou nil et une raison ; rien n'est modifié en cas de refus.
function Groups.applyCreate(data, spec)
    if type(spec) ~= "table" then return nil, "spec is not a table" end
    if not typeKnown(spec.type) then return nil, "unknown type " .. tostring(spec.type) end
    if not isText(spec.name, 1, Groups.NAME_MAX) then return nil, "bad name" end
    local story = spec.story or ""
    if not isText(story, 0, Groups.STORY_MAX) then return nil, "bad story" end
    if spec.storySeed ~= nil and not isInt(spec.storySeed, 0, Groups.COORD_MAX) then return nil, "bad story seed" end
    if spec.home ~= nil and not validHome(spec.home) then return nil, "bad home" end
    local day = spec.day
    if not isInt(day, 0, Groups.COORD_MAX) then return nil, "bad day" end
    local needs = {}
    for _, key in ipairs(Groups.NEEDS) do
        local v = Groups.DEFAULT_LEVEL
        if spec.needs ~= nil then
            if type(spec.needs) ~= "table" or not isInt(spec.needs[key], 0, Groups.LEVEL_MAX) then
                return nil, "bad need " .. key
            end
            v = spec.needs[key]
        end
        needs[key] = v
    end
    local morale = spec.morale
    if morale == nil then morale = Groups.DEFAULT_LEVEL end
    if not isInt(morale, 0, Groups.LEVEL_MAX) then return nil, "bad morale" end
    local count = 0
    for _ in pairs(data.groups) do count = count + 1 end
    if count >= Groups.MAX_GROUPS then return nil, "too many groups" end
    local id = Groups.ID_PREFIX .. tostring(data.nextId)
    if data.groups[id] ~= nil then return nil, "identifier " .. id .. " already used (registry corrupted)" end
    data.nextId = data.nextId + 1
    local g = { id = id, type = spec.type, name = spec.name, story = story, founded = day, nextMember = 1,
        members = {}, needs = needs, morale = morale, log = {}, storySeed = spec.storySeed }
    if spec.home then g.home = { x = spec.home.x, y = spec.home.y, z = spec.home.z } end
    data.groups[id] = g
    appendLog(g, "founded", "", day)
    log().info("group %s created (%s)", id, spec.type)
    -- LK12-T02 : fait "groupCreated" (LK_Core.publish) ; l'événement public part après la transaction (LK_API).
    LivingKnox.publish("groupCreated", { group = id, type = spec.type, day = day })
    return g
end

-- Nouveau groupe. spec = { type, name, story (facultatif), home = { x, y, z } (facultatif), day (facultatif),
-- storySeed, needs, morale (facultatifs, voir applyCreate) }. Par défaut besoins et moral à DEFAULT_LEVEL ; aucun
-- membre, aucun chef. Rend une copie du groupe.
function Groups.create(spec)
    local data = registry()
    if not data then return nil, NOT_READY end
    if type(spec) ~= "table" then return nil, "spec is not a table" end
    local full = copy(spec)
    full.day = dayOf(spec.day) or -1   -- invalide : refusé par applyCreate, dans l'ordre de ses contrôles
    local g, why = Groups.applyCreate(data, full)
    if not g then return nil, why end
    return commit(copy(g))
end

-- Modification groupée du registre courant (simulation hors écran, LK09-T01) : fn(data) reçoit le registre vivant
-- (pas une copie) et rend changed, result ; une seule sauvegarde si changed (différée à la fin de l'image, LK13-T06 :
-- Groups.flush() juste après pour une écriture immédiate). Rend result (vrai par défaut), ou nil et une raison
-- (registre non prêt). fn ne doit laisser que des valeurs valides (voir validGroup).
function Groups.update(fn)
    local data = registry()
    if not data then return nil, NOT_READY end
    local changed, result = fn(data)
    if result == nil then result = true end
    if changed then return commit(result) end
    return result
end

-- Copie d'un groupe, ou nil.
function Groups.get(gid)
    local g, why = group(gid)
    if not g then return nil, why end
    return copy(g)
end

-- Lecture en place (LK13-T08, fiche groupes.md « Lecture en place ») ----------------------------------------------
-- Groups.peek(gid) rend le groupe VIVANT du registre (aucune copie), ou nil et une raison. LECTURE SEULE :
--   - ne rien écrire dans la table rendue ni dans ses sous-tables (champ, table.insert/remove/sort, passage à une
--     fonction qui écrit) : toute écriture passe par l'API de ce fichier ou Groups.update ;
--   - ne pas la garder au-delà de l'appel en cours (elle suit les changements suivants, peut sortir du registre) ni la
--     rendre à un appelant qui ne connaît pas la règle ; recopier les valeurs simples utiles (nombres, chaînes).
-- Pour les passages fréquents (chaque image) qui lisent quelques champs ; une table à garder ou à modifier :
-- Groups.get (copie). Banc : tests/test_lk_groups.py vérifie qu'aucun appelant n'écrit dans la vue (lecture du code).
-- Contrôle à l'exécution (tests, console debug) : Groups.PEEK_CHECK = true. Chaque peek garde alors une copie du
-- groupe lu (une par groupe et par génération de changements : Groups.stats.marks) ; à la fin de l'image
-- (Groups.onTick), au début de la suivante (onTickEvenPaused) et sur demande (Groups.checkPeeks()), un groupe qui a
-- changé sans aucun changement enregistré depuis la lecture (marks inchangé) est une écriture par la vue : journal
-- ERROR, Groups.stats.peekViolations. Limite : une écriture par la vue suivie dans la même image d'un changement
-- enregistré n'est pas vue (la lecture du code la couvre). Coupé par défaut (le contrôle copie le groupe).
Groups.PEEK_CHECK = Groups.PEEK_CHECK or false
Groups.peekState = Groups.peekState or { byGid = {} }

-- Premier chemin où a et b diffèrent ("" pour la racine), ou nil s'ils sont égaux.
local function differs(a, b, path)
    if type(a) ~= "table" or type(b) ~= "table" then
        if a == b then return nil end
        return path
    end
    for k, v in pairs(a) do
        local d = differs(v, b[k], path .. "." .. tostring(k))
        if d ~= nil then return d end
    end
    for k in pairs(b) do
        if a[k] == nil then return path .. "." .. tostring(k) end
    end
    return nil
end

function Groups.peek(gid)
    local g, why = group(gid)
    if not g then return nil, why end
    local stats = Groups.stats
    stats.peeks = (stats.peeks or 0) + 1
    if Groups.PEEK_CHECK then
        local seen = Groups.peekState.byGid
        local e = seen[gid]
        if e == nil or e.marks ~= stats.marks or e.live ~= g then
            seen[gid] = { live = g, snap = copy(g), marks = stats.marks }
        end
    end
    return g
end

-- Changement fait en place, volontairement sans écriture (écrit avec le changement enregistré suivant, par exemple
-- la peur montée par LK_Needs.perceive, fiche besoins.md) : le contrôle des vues reprend sa copie du groupe gid (sans
-- cela, ce changement serait signalé comme une écriture par une vue). Sans effet hors contrôle.
function Groups.touched(gid)
    if not Groups.PEEK_CHECK then return end
    local e = Groups.peekState.byGid[gid]
    if e ~= nil then e.snap = copy(e.live) end
end

-- Contrôle des vues (Groups.PEEK_CHECK) : rend le nombre de groupes changés par une vue depuis le dernier contrôle.
function Groups.checkPeeks()
    local ps, stats = Groups.peekState, Groups.stats
    local data = Groups.state.data
    local found = 0
    local kept = {}
    for gid, e in pairs(ps.byGid) do
        if e.marks == stats.marks then
            local live = data ~= nil and data.groups[gid] or nil
            local where = live ~= e.live and "" or differs(live, e.snap, "")
            if where ~= nil then
                found = found + 1
                log().error("groups: group %s changed through Groups.peek without a recorded change (read-only view)"
                    .. " at %s", tostring(gid), where == "" and "<group>" or where)
            else
                kept[gid] = e
            end
        end
    end
    ps.byGid = kept
    stats.peekViolations = (stats.peekViolations or 0) + found
    return found
end

-- Identifiants des groupes triés par numéro (table vide si le registre n'est pas prêt).
function Groups.list()
    local data = registry()
    if not data then return {} end
    return sortedKeys(data.groups)
end

-- Supprime un groupe ; son numéro n'est jamais réattribué.
function Groups.remove(gid)
    local g, why = group(gid)
    if not g then return nil, why end
    local alive = 0
    for _, m in pairs(g.members) do
        if m.alive then alive = alive + 1 end
    end
    Groups.state.data.groups[gid] = nil
    log().info("group %s removed", gid)
    -- LK12-T02 : fait "groupRemoved" (vivants au moment du retrait) ; LK_API en tire l'événement « groupe disparu ».
    LivingKnox.publish("groupRemoved", { group = gid, alive = alive, day = Groups.today() })
    return commit(true)
end

-- Nouveau membre vivant d'un groupe passé en argument (logique pure, sans sauvegarde ; partagée par addMember et la
-- population initiale). spec = { role, npc (déjà contrôlé contre le registre par l'appelant), profile, female,
-- traits (facultatifs, LK08-T05) }, day = jour valide. Rend l'identifiant du membre, ou nil et une raison.
function Groups.applyMember(g, spec, day)
    if type(spec) ~= "table" then return nil, "spec is not a table" end
    if not roleRank(spec.role) then return nil, "unknown role " .. tostring(spec.role) end
    if spec.npc ~= nil and not LivingKnox.Identity.isId(spec.npc) then return nil, "bad npc reference" end
    local extrasOk, extrasWhy = validMemberExtras(spec)
    if not extrasOk then return nil, extrasWhy end
    if not isInt(day, 0, Groups.COORD_MAX) then return nil, "bad day" end
    local count = 0
    for _ in pairs(g.members) do count = count + 1 end
    if count >= Groups.MAX_MEMBERS then return nil, "too many members" end
    local mid = Groups.MEMBER_PREFIX .. tostring(g.nextMember)
    g.nextMember = g.nextMember + 1
    g.members[mid] = { id = mid, role = spec.role, alive = true, npc = spec.npc, profile = spec.profile,
        female = spec.female, traits = copy(spec.traits) }
    appendLog(g, "joined", mid, day)
    return mid
end

-- Nouveau membre vivant. spec = { role, npc = "lk-<n>" (facultatif, un seul membre par PNJ), day (facultatif),
-- profile, female, traits (facultatifs, voir l'en-tête) }. Rend l'identifiant du membre.
function Groups.addMember(gid, spec)
    local g, why = group(gid)
    if not g then return nil, why end
    if g.gone ~= nil then return nil, "group " .. gid .. " is gone" end
    if type(spec) ~= "table" then return nil, "spec is not a table" end
    if not roleRank(spec.role) then return nil, "unknown role " .. tostring(spec.role) end
    if spec.npc ~= nil then
        if not LivingKnox.Identity.isId(spec.npc) then return nil, "bad npc reference" end
        local owner = npcOwner(Groups.state.data, spec.npc)
        if owner then return nil, "npc " .. spec.npc .. " already in group " .. owner end
    end
    local day = dayOf(spec.day)
    if not day then return nil, "bad day" end
    local mid, err = Groups.applyMember(g, spec, day)
    if not mid then return nil, err end
    return commit(mid)
end

-- Départ d'un membre sur un groupe passé en argument (logique pure, sans sauvegarde ; partagée par removeMember et
-- les événements hors écran, LK09-T05) : membre retiré, chef effacé s'il l'était, entrée « left ». Rend vrai si
-- c'était le chef. reason (facultatif, LK12-T02) : raison publique du départ (chaîne courte, par exemple
-- "leave_group" pour E10-T04) ; nil = non précisée (départ hors écran de LK09-T05). Point d'appel unique du fait
-- "memberLeft" (LK_Core.publish), relayé par l'événement public « membre parti » (LK_API).
function Groups.applyLeave(g, mid, day, reason)
    local m = g.members[mid]
    g.members[mid] = nil
    local wasLeader = g.leader == mid
    if wasLeader then g.leader = nil end
    appendLog(g, "left", mid, day)
    LivingKnox.publish("memberLeft", { group = g.id, member = mid, npc = m and m.npc or nil,
        role = m and m.role or nil, alive = m ~= nil and m.alive == true, day = day, reason = reason })
    return wasLeader
end

-- Retire un membre (départ) ; s'il était chef, le groupe n'a plus de chef (voir succeed). reason : voir applyLeave.
function Groups.removeMember(gid, mid, day, reason)
    local m, g = member(gid, mid)
    if not m then return nil, g end
    day = dayOf(day)
    if not day then return nil, "bad day" end
    Groups.applyLeave(g, mid, day, reason)
    return commit(true)
end

-- Mort d'un membre (définitive) ; s'il était chef, le groupe n'a plus de chef (voir succeed).
function Groups.markDead(gid, mid, day)
    local m, g = member(gid, mid)
    if not m then return nil, g end
    if not m.alive then return true end
    day = dayOf(day)
    if not day then return nil, "bad day" end
    Groups.applyDeath(g, mid, day)
    return commit(true)
end

function Groups.setRole(gid, mid, role)
    local m, g = member(gid, mid)
    if not m then return nil, g end
    if not roleRank(role) then return nil, "unknown role " .. tostring(role) end
    m.role = role
    return commit(true)
end

-- Lien d'un membre avec un PNJ du registre des corps ("lk-<n>"), ou nil pour l'effacer.
function Groups.setNpc(gid, mid, npc)
    local m, g = member(gid, mid)
    if not m then return nil, g end
    if npc ~= nil then
        if not LivingKnox.Identity.isId(npc) then return nil, "bad npc reference" end
        local ownerGroup, ownerMember = npcOwner(Groups.state.data, npc)
        if ownerGroup and (ownerGroup ~= gid or ownerMember ~= mid) then
            return nil, "npc " .. npc .. " already in group " .. ownerGroup
        end
    end
    m.npc = npc
    return commit(true)
end

-- Groupe et membre d'un PNJ ("lk-<n>"), ou nil.
function Groups.findNpc(npc)
    local data = registry()
    if not data or type(npc) ~= "string" then return nil end
    return npcOwner(data, npc)
end

-- Nouveau chef : membre vivant, ou nil (aucun chef).
function Groups.setLeader(gid, mid, day)
    local g, why = group(gid)
    if not g then return nil, why end
    if mid ~= nil then
        local m = type(mid) == "string" and g.members[mid] or nil
        if not m then return nil, "unknown member " .. tostring(mid) .. " in " .. gid end
        if not m.alive then return nil, "member " .. mid .. " is dead" end
    end
    day = dayOf(day)
    if not day then return nil, "bad day" end
    Groups.applyLeader(g, mid, day)
    return commit(true)
end

-- Successeur que désignerait la règle de succession (sans rien changer), ou nil.
function Groups.successor(gid)
    local g, why = group(gid)
    if not g then return nil, why end
    return Groups.pickSuccessor(g)
end

-- Succession (I6.6, API seulement : aucun délai ni comportement) : le successeur devient chef. Rend son identifiant,
-- ou nil et une raison s'il n'y a aucun membre vivant (le groupe reste sans chef).
function Groups.succeed(gid, day)
    local g, why = group(gid)
    if not g then return nil, why end
    local mid = Groups.pickSuccessor(g)
    if not mid then return nil, "no living member" end
    local ok, err = Groups.setLeader(gid, mid, day)
    if not ok then return nil, err end
    return mid
end

-- Besoin (food, medical, ammo) fixé à value, arrondi et borné à 0..100. Rend la valeur retenue.
function Groups.setNeed(gid, key, value)
    local g, why = group(gid)
    if not g then return nil, why end
    if not inList(Groups.NEEDS, key) then return nil, "unknown need " .. tostring(key) end
    if type(value) ~= "number" or value ~= value then return nil, "value must be a number" end
    g.needs[key] = clampLevel(value)
    return commit(g.needs[key])
end

function Groups.addNeed(gid, key, delta)
    local g, why = group(gid)
    if not g then return nil, why end
    if not inList(Groups.NEEDS, key) then return nil, "unknown need " .. tostring(key) end
    if type(delta) ~= "number" or delta ~= delta then return nil, "delta must be a number" end
    return Groups.setNeed(gid, key, g.needs[key] + delta)
end

-- Moral fixé à value, arrondi et borné à 0..100. Rend la valeur retenue.
function Groups.setMorale(gid, value)
    local g, why = group(gid)
    if not g then return nil, why end
    if type(value) ~= "number" or value ~= value then return nil, "value must be a number" end
    g.morale = clampLevel(value)
    return commit(g.morale)
end

function Groups.addMorale(gid, delta)
    local g, why = group(gid)
    if not g then return nil, why end
    if type(delta) ~= "number" or delta ~= delta then return nil, "delta must be a number" end
    return Groups.setMorale(gid, g.morale + delta)
end

-- Foyer : trois entiers (x, y >= 0, z dans -32..31), ou nil pour l'effacer. Aucun chargement de la zone.
function Groups.setHome(gid, x, y, z)
    local g, why = group(gid)
    if not g then return nil, why end
    if x == nil and y == nil and z == nil then
        g.home = nil
        return commit(true)
    end
    local home = { x = x, y = y, z = z }
    if not validHome(home) then return nil, "bad home" end
    g.home = home
    return commit(true)
end

-- Entrée de journal : kind court (lettre puis lettres, chiffres, soulignés ; KIND_MAX au plus), text tronqué à
-- TEXT_MAX, day = jour de jeu (défaut : aujourd'hui). Les plus anciennes au-delà de LOG_SIZE sont oubliées.
function Groups.addLog(gid, kind, text, day)
    local g, why = group(gid)
    if not g then return nil, why end
    if not validKind(kind) then return nil, "bad log kind" end
    if text == nil then text = "" end
    if type(text) ~= "string" then return nil, "text must be a string" end
    if #text > Groups.TEXT_MAX then text = string.sub(text, 1, Groups.TEXT_MAX) end
    day = dayOf(day)
    if not day then return nil, "bad day" end
    appendLog(g, kind, text, day)
    return commit(true)
end

-- Écriture regroupée (LK13-T06) : début et fin de l'image, sauvegarde du monde. OnSave n'est déclenché que par
-- GameWindow.save (solo, client MP), jamais par la sauvegarde d'un serveur dédié (ServerMap.QueuedSaveAll) : sur un
-- serveur, l'écriture de fin d'image suffit (fiche groupes.md « Persistance »).
if Events ~= nil then   -- absent seulement hors du jeu (banc Kahlua sans événements)
    LivingKnox.subscribe("OnTick", "Groups.flush", onTickHandler)
    LivingKnox.subscribe("OnTickEvenPaused", "Groups.flushPaused", function() LivingKnox.Groups.onTickEvenPaused() end)
    LivingKnox.subscribe("OnSave", "Groups.onSave", function() LivingKnox.Groups.flush() end)
end

return Groups
