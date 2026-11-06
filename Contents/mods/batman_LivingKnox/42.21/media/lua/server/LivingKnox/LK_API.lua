-- Living Knox : API publique en lecture, versionnée (LK12-T01). Documentation :
-- docs/specifications-techniques/api-living-knox.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici
-- (LivingKnox.API n'existe donc pas chez un client MP).
--
-- Version : API.VERSION (entier). Règle de compatibilité : dans une même version, on n'AJOUTE que des fonctions ou
-- des champs ; tout retrait, renommage ou changement de sens (unité, maille, bornes, signification d'une valeur)
-- impose une nouvelle version. Un consommateur vérifie API.version() >= la version qu'il connaît.
--
-- Toutes les fonctions rendent des COPIES neuves (tables Lua simples : chaînes, nombres, booléens), sans référence
-- au registre ni objet Java ; modifier un résultat ne change rien au moteur.
-- Aucune donnée secrète : ni secrets d'histoire (le champ story du registre ne contient que le résumé public,
-- docs/annexes/conception/recits.md), ni coordonnées exactes du foyer (maille de API.AREA_SIZE cases), ni journal technique du
-- groupe (g.log) ; le journal de récit public (LK_Journal, LK10-T02) se lit par API.journal.
-- Serveur seulement : tout envoi à un client passe par une projection explicite (API.publicGroup, ou une projection
-- propre au consommateur qui ne rajoute rien de privé).
--
-- Écritures (LK12-T03, ajout compatible de la version 1) : API.missionOffers ouvre ou ferme paresseusement les offres
-- de ressources d'un groupe, API.deliver remonte une réserve ; les deux passent par LivingKnox.Groups.update (une
-- seule sauvegarde, réserve et reçu écrits ensemble). Champ facultatif du groupe (schéma 1 inchangé, voir
-- LK_Groups.lua) : supply = { next = <numéro de la prochaine offre>, offers = { [need] = offre ouverte },
-- receipts = { reçu, ... } (SUPPLY.RECEIPTS_MAX derniers) }. Aucune fonction ne touche un inventaire.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Hostility"
require "LivingKnox/LK_Journal"

local API = LivingKnox.API or {}
LivingKnox.API = API

API.VERSION = 1
API.AREA_SIZE = 100       -- maille du foyer approximatif (cases) : centre de la maille, jamais la case exacte
API.NEAR_DEFAULT = 20     -- rayon par défaut de npcsNear (cases)
API.NEAR_MAX = 50         -- rayon plafonné de npcsNear (cases)
API.NEEDS = { "food", "medical", "ammo" }

local NOT_READY = "group registry not ready"
local BODIES_NOT_READY = "npc registry not ready"

function API.version()
    return API.VERSION
end

local function Groups() return LivingKnox.Groups end
local function Store() return LivingKnox.Store end
local function Identity() return LivingKnox.Identity end

-- Vrai si le registre des groupes est lisible (relu, non bloqué).
function API.isReady()
    return Groups().ensure() == true
end

-- Registre vivant des groupes (lecture seule ici), ou nil.
local function groupData()
    if not Groups().ensure() then return nil end
    return Groups().state.data
end

-- Registre vivant des PNJ (lecture seule ici), ou nil. Rattrapage paresseux comme LK_Bodies.canAct.
local function npcData()
    local S = Store()
    if not S.isReady() and not S.isBlocked() then S.ensure() end
    return S.data()
end

local function isNumber(v) return type(v) == "number" and v == v end
local function isText(v) return type(v) == "string" end

local function inList(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Centre de la maille AREA_SIZE contenant (x, y) : { x, y, size }. Étage non rendu.
function API.area(x, y)
    if not isNumber(x) or not isNumber(y) then return nil end
    local s = API.AREA_SIZE
    return { x = math.floor(x / s) * s + math.floor(s / 2), y = math.floor(y / s) * s + math.floor(s / 2), size = s }
end

-- Membres triés par numéro (ancienneté).
local function sortedMembers(members)
    local ids = {}
    for mid in pairs(members) do ids[#ids + 1] = mid end
    table.sort(ids, function(a, b)
        local na, nb = Groups().memberNumber(a), Groups().memberNumber(b)
        if na and nb then return na < nb end
        return tostring(a) < tostring(b)
    end)
    return ids
end

local function typeNameKey(t)
    local def = LivingKnox.GroupTypes.get(t)
    return def and def.nameKey or nil
end

-- Vue publique d'un groupe du registre (table vivante) : champs listés ici seulement.
-- withMembers = vrai : liste des membres en plus.
local function view(g, withMembers, playerKey)
    local alive, total = 0, 0
    for _, m in pairs(g.members) do
        total = total + 1
        if m.alive then alive = alive + 1 end
    end
    local out = { id = g.id, type = g.type, typeNameKey = typeNameKey(g.type), name = g.name, summary = g.story,
        founded = g.founded, alive = alive, total = total, morale = g.morale, task = g.task,
        needs = { food = g.needs.food, medical = g.needs.medical, ammo = g.needs.ammo },
        attitude = nil }
    -- Attitude du groupe envers UN joueur (LK11-T03) : seulement dans une vue demandée pour ce joueur ; jamais la
    -- valeur interne, seulement { level, trend }. nil sans joueur, avec une clé invalide ou un registre non prêt.
    if playerKey ~= nil then out.attitude = API.attitude(g.id, playerKey) end
    if g.leader ~= nil and g.members[g.leader] then
        -- Nom du chef : aucun nom de membre n'est tenu par le registre en version 1 (name toujours nil).
        out.leader = { id = g.leader, npc = g.members[g.leader].npc, name = nil }
    end
    if g.home ~= nil then out.area = API.area(g.home.x, g.home.y) end
    if withMembers then
        local list = {}
        for _, mid in ipairs(sortedMembers(g.members)) do
            local m = g.members[mid]
            list[#list + 1] = { id = mid, role = m.role, alive = m.alive == true, npc = m.npc }
        end
        out.members = list
    end
    return out
end

-- Attitude d'un groupe envers un joueur (LK11-T03) : { level, trend } (niveaux LivingKnox.Hostility.LEVELS,
-- tendance up / down / stable), ou nil et une raison. playerKey = identité de personnage du carnet
-- (LivingKnox.Hostility.keyOf(player)). Aucune valeur numérique.
function API.attitude(gid, playerKey)
    local a, why = LivingKnox.Hostility.get(gid, playerKey)
    if not a then return nil, why end
    return { level = a.level, trend = a.trend }
end

-- Derniers faits de relation d'un groupe envers un joueur (E09-T04, ajout compatible de la version 1) :
-- { { n, fact, sign, day }, ... }, le plus ancien d'abord (les trois derniers au plus : ceux de la tendance), chacun
-- vu par un membre ou attribuable ; n = numéro du fait dans la paire (identifiant stable). Liste vide sans fait connu,
-- nil et une raison si la clé ou le groupe sont invalides. Jamais la valeur interne. Lecture seule, autorité.
function API.attitudeFacts(gid, playerKey)
    local H = LivingKnox.Hostility
    local a, why = H.get(gid, playerKey)
    if not a then return nil, why end
    return H.facts(gid, playerKey)
end

-- Liste des groupes, triée par numéro : { { id, type, typeNameKey, name, summary, founded, alive, total, leader,
-- area, needs, morale, task, attitude }, ... }. Table vide si le registre n'est pas prêt (voir API.isReady).
-- playerKey facultatif : attitude de chaque groupe envers ce joueur (sinon attitude = nil).
function API.listGroups(playerKey)
    local data = groupData()
    local out = {}
    if not data then return out end
    for _, gid in ipairs(Groups().list()) do
        out[#out + 1] = view(data.groups[gid], false, playerKey)
    end
    return out
end

-- Un groupe avec ses membres { id, role, alive, npc }, ou nil et une raison. playerKey facultatif : comme listGroups.
function API.getGroup(gid, playerKey)
    local data = groupData()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    return view(g, true, playerKey)
end

-- Composition d'un groupe (E10-T02, ajout compatible de la version 1) : { group, leader = "m-<k>" ou nil (chef
-- vivant), leaderNpc = "lk-<n>" ou nil, alive = membres vivants, members = { "m-<k>", ... } (vivants, triés par
-- numéro), key = empreinte "<chef ou ->|<m-a>,<m-b>,..." }, ou nil et une raison. Empreinte CALCULÉE à chaque appel
-- (aucun champ stocké, schéma inchangé) : deux appels rendent la même clé tant que ni le chef ni l'ensemble des
-- membres vivants n'ont changé ; une mort, un départ, une arrivée ou une succession la changent. Un consommateur la
-- garde avec une décision collective et la compare au moment de l'appliquer (réponse fondée sur une ancienne
-- composition : rejetée).
function API.composition(gid)
    local data = groupData()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    local living = {}
    for _, mid in ipairs(sortedMembers(g.members)) do
        if g.members[mid].alive then living[#living + 1] = mid end
    end
    local chief = g.leader ~= nil and g.members[g.leader] or nil
    local leader = chief and chief.alive and g.leader or nil
    return { group = g.id, leader = leader, leaderNpc = leader and chief.npc or nil, alive = #living,
        members = living, key = (leader or "-") .. "|" .. table.concat(living, ",") }
end

-- Journal de récit d'un groupe (LK10-T02, ajout compatible de la version 1 ; LK_Journal,
-- docs/specifications-techniques/api-living-knox.md) :
-- { group, next, entries = { { n, day, hour, kind, key, args = { { text, key }, ... }, member, npc, text }, ... } },
-- entrées de numéro > since (défaut 0), la plus ancienne d'abord ; next = numéro de la prochaine entrée (passer
-- next - 1 en since pour ne lire que les nouvelles). text = texte composé sur cette machine, ou nil quand les
-- traductions du mod n'y sont pas chargées (serveur dédié) : key et args font foi. Aucun secret ni coordonnée.
-- Ou nil et une raison.
function API.journal(gid, since)
    local data = groupData()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    local J = LivingKnox.Journal
    if J == nil then return { group = gid, next = 1, entries = {} } end
    local entries, nextN = J.view(g, since)
    for _, e in ipairs(entries) do e.text = J.text(e) end
    return { group = gid, next = nextN, entries = entries }
end

-- Enrichissement des histoires (LK10-T03, ajout compatible de la version 1 ; docs/specifications-techniques/api-living-knox.md,
-- conception recits.md) ------
-- Un autre mod (le carnet de RadioSurvivor, par son LLM) remplace ou complète le résumé public composé par LK_Stories,
-- pour un groupe ou pour un membre, dans une langue (en, fr). Le texte est contrôlé ici (longueur, lignes,
-- caractères), gardé au registre privé des groupes avec la VERSION du gabarit qu'il remplace (empreinte du type, de
-- la graine et des résumés composés) : un gabarit changé (graine, type, données mises à jour) rend le texte périmé,
-- et la lecture revient au gabarit. Les secrets de l'histoire ne sont jamais lus ni remplacés : seul le résumé public
-- l'est. Le moteur n'appelle jamais l'autre mod : sans lui, rien n'est écrit et la lecture rend le gabarit.
-- Champ facultatif du groupe (schéma 1 inchangé, non contrôlé par LK_Groups ; contrôlé ici, entrée invalide ignorée
-- à la lecture et retirée à l'écriture suivante) :
--   enrich = { ["<cible>:<langue>"] = { text, mode = "replace" | "append", version, day } }, cible = "group" ou
--   "m-<k>" (membre du groupe), au plus (MAX_MEMBERS + 1) x 2 entrées.

API.STORY = {
    TEXT_MAX = 600,       -- longueur du texte fourni (octets sous Lua 5.1, unités UTF-16 en Kahlua) = STORY_MAX
    LINES_MAX = 8,        -- lignes au plus (séparées par "\n")
    LANGS = { "en", "fr" },
    MODES = { "replace", "append" },
    GROUP = "group",      -- cible du groupe entier
}

local MOD = 2147483647

local function hashText(s, h)
    for i = 1, #s do
        h = (h * 31 + string.byte(s, i)) % MOD
    end
    return h
end

-- Histoire composée d'un groupe à graine (mémoire du serveur, contient les secrets : jamais rendue), par type et
-- graine. Les données ne changent qu'au rechargement du fichier, qui vide ce cache.
local composed = {}

local function composedStory(g)
    local S = LivingKnox.Stories
    if S == nil or type(g.storySeed) ~= "number" then return nil end
    local key = tostring(g.type) .. ":" .. tostring(g.storySeed)
    if composed[key] == nil then composed[key] = S.compose(g.type, g.storySeed) or false end
    return composed[key] or nil
end

-- Gabarit d'un groupe : résumés { en, fr } et version (chaîne ASCII). Sans graine (ou sans LK_Stories) : le résumé du
-- registre (anglais) pour les deux langues.
local function template(g)
    local story = composedStory(g)
    local en, fr
    if story then
        en, fr = story.summary.en, story.summary.fr
    else
        en = type(g.story) == "string" and g.story or ""
        fr = en
    end
    local h = hashText(tostring(g.type), 7)
    h = hashText("|" .. en .. "|" .. fr, h)
    local seed = type(g.storySeed) == "number" and tostring(g.storySeed) or "x"
    return { en = en, fr = fr }, "t1-" .. seed .. "-" .. tostring(h)
end

local function langOf(lang)
    if type(lang) ~= "string" then return nil end
    lang = string.lower(lang)
    if inList(API.STORY.LANGS, lang) then return lang end
    return nil
end

local function trim(s)
    return (string.gsub(string.gsub(s, "^[%s]+", ""), "[%s]+$", ""))
end

-- Contrôle d'un texte fourni : rend le texte (blancs de tête et de fin retirés), ou nil et une raison. Interdits :
-- caractères de contrôle autres que "\n", "<" et ">" (balises des panneaux de texte riche du jeu).
local function checkText(text)
    if type(text) ~= "string" then return nil, "bad text" end
    text = trim(text)
    if text == "" then return nil, "empty text" end
    if #text > API.STORY.TEXT_MAX then return nil, "text too long" end
    local lines = 1
    for i = 1, #text do
        local c = string.byte(text, i)
        if c == 10 then
            lines = lines + 1
        elseif c < 32 or c == 127 or c == 60 or c == 62 then
            return nil, "bad character in text"
        end
    end
    if lines > API.STORY.LINES_MAX then return nil, "too many lines" end
    return text
end

local function validTarget(g, target)
    return target == API.STORY.GROUP or (type(target) == "string" and g.members[target] ~= nil)
end

-- Entrée enregistrée encore valable pour ce gabarit (forme, cible, version), ou nil.
local function liveEntry(g, target, lang, version)
    local e = type(g.enrich) == "table" and g.enrich[target .. ":" .. lang] or nil
    if type(e) ~= "table" or e.version ~= version or not inList(API.STORY.MODES, e.mode) then return nil end
    if not validTarget(g, target) or checkText(e.text) ~= e.text then return nil end
    return e
end

local function render(base, e)
    if e.mode == "append" and base ~= "" then return base .. "\n" .. e.text end
    return e.text
end

-- Histoire publique d'un groupe ou d'un membre : story(groupId[, lang[, memberId]]) ->
-- { group, member, lang, text, source, mode, version, template }, ou nil et une raison.
--   lang : "en" ou "fr" (casse indifférente) ; toute autre valeur ou nil = anglais (comme LK_Stories.text).
--   text : texte à afficher ou à donner au LLM ; source = "member" (texte du membre), "group" (texte du groupe) ou
--          "template" (gabarit seul : aucun texte fourni, ou texte invalide ou périmé) ; mode du texte retenu ou nil.
--   Membre : son texte s'il en a un, sinon celui du groupe (texte fourni, sinon gabarit) ; un texte « append » d'un
--   membre complète celui du groupe.
--   version : version du gabarit, à rendre telle quelle à enrichStory (refus « stale version » s'il a changé).
--   template : résumé composé dans cette langue. Jamais de secret d'histoire.
function API.story(gid, lang, memberId)
    local data = groupData()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    lang = langOf(lang) or "en"
    if memberId ~= nil and (type(memberId) ~= "string" or g.members[memberId] == nil) then
        return nil, "unknown member " .. tostring(memberId)
    end
    local base, version = template(g)
    local out = { group = gid, member = memberId, lang = lang, template = base[lang], version = version,
        text = base[lang], source = "template" }
    local ge = liveEntry(g, API.STORY.GROUP, lang, version)
    if ge then out.text, out.source, out.mode = render(base[lang], ge), "group", ge.mode end
    if memberId ~= nil then
        local me = liveEntry(g, memberId, lang, version)
        if me then out.text, out.source, out.mode = render(out.text, me), "member", me.mode end
    end
    return out
end

-- Remplace ou complète l'histoire publique : enrichStory(groupId, lang, text[, opts]) -> result, ou nil et une raison.
--   lang : "en" ou "fr" (obligatoire) ; text : texte borné (voir checkText et API.STORY), nil = retirer le texte ;
--   opts = { member = "m-<k>" (sinon le groupe), mode = "replace" (défaut) | "append", version = version lue par
--            API.story (facultative : refus « stale version » si le gabarit a changé depuis) }.
-- result = { group, member, lang, mode, version, cleared }. Une seule écriture du registre (LivingKnox.Groups.update),
-- qui retire aussi les entrées invalides ou périmées du groupe. Le texte n'est jamais journalisé.
function API.enrichStory(gid, lang, text, opts)
    if opts ~= nil and type(opts) ~= "table" then return nil, "bad options" end
    opts = opts or {}
    local l = langOf(lang)
    if not l then return nil, "bad language" end
    local mode = opts.mode or "replace"
    if not inList(API.STORY.MODES, mode) then return nil, "bad mode" end
    if opts.version ~= nil and not isText(opts.version) then return nil, "bad version" end
    local clean
    if text ~= nil then
        local why
        clean, why = checkText(text)
        if not clean then return nil, why end
    end
    local data = groupData()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    local target = opts.member or API.STORY.GROUP
    if target == API.STORY.GROUP and opts.member ~= nil then return nil, "unknown member " .. tostring(target) end
    if not validTarget(g, target) then return nil, "unknown member " .. tostring(target) end
    local _, version = template(g)
    if opts.version ~= nil and opts.version ~= version then return nil, "stale version" end
    local result, err = Groups().update(function(reg)
        local live = reg.groups[gid]
        local kept = {}
        if type(live.enrich) == "table" then
            for key, e in pairs(live.enrich) do
                local t, el = string.match(tostring(key), "^(.+):(%a%a)$")
                if t and langOf(el) == el and liveEntry(live, t, el, version) == e then kept[key] = e end
            end
        end
        local key = target .. ":" .. l
        if clean ~= nil then
            kept[key] = { text = clean, mode = mode, version = version, day = Groups().today() }
        else
            kept[key] = nil
        end
        local any = false
        for _ in pairs(kept) do any = true end
        live.enrich = any and kept or nil
        return true, { group = gid, member = opts.member, lang = l, mode = clean and mode or nil, version = version,
            cleared = clean == nil }
    end)
    if not result then return nil, err end
    LivingKnox.Log.info("stories: %s text of %s %s (%s)", l, gid,
        clean and ("set for " .. target) or ("cleared for " .. target), clean and mode or "template")
    return result
end

-- Position d'un joueur ou d'un personnage (getX/getY/getZ), ou nil.
local function positionOf(o)
    local t = type(o)
    if (t ~= "table" and t ~= "userdata") or o.getX == nil then return nil end
    local x, y, z = o:getX(), o:getY(), o:getZ()
    if not isNumber(x) or not isNumber(y) or not isNumber(z) then return nil end
    return x, y, z
end

-- PNJ incarnés à portée : npcsNear(player, radius) ou npcsNear(x, y, z, radius). radius facultatif (NEAR_DEFAULT),
-- plafonné à NEAR_MAX. Position = corps lié s'il est dans le monde, sinon dernière position vue du registre des
-- corps ; distance horizontale. Rend { { id, group, member, role, distance, floor, inWorld }, ... } trié par distance
-- puis par numéro, ou nil et une raison. Coût : registre des PNJ et registre des groupes, aucun parcours de carte.
function API.npcsNear(a, b, c, d)
    local x, y, z, radius
    if type(a) == "number" then
        x, y, z, radius = a, b, c, d
    else
        x, y, z = positionOf(a)
        radius = b
    end
    if not isNumber(x) or not isNumber(y) or not isNumber(z) then return nil, "bad position" end
    if radius == nil then radius = API.NEAR_DEFAULT end
    if not isNumber(radius) or radius < 0 then return nil, "bad radius" end
    if radius > API.NEAR_MAX then radius = API.NEAR_MAX end
    local registry = npcData()
    if not registry then return nil, BODIES_NOT_READY end

    -- PNJ -> groupe, membre, rôle (un seul passage sur le registre des groupes ; vide s'il n'est pas prêt).
    local owners = {}
    local gdata = groupData()
    if gdata then
        for gid, g in pairs(gdata.groups) do
            for mid, m in pairs(g.members) do
                if m.npc ~= nil then owners[m.npc] = { group = gid, member = mid, role = m.role } end
            end
        end
    end

    local Bodies = LivingKnox.Bodies
    local cellReady = getCell ~= nil and getCell() ~= nil
    local out = {}
    for id, npc in pairs(registry.npcs) do
        if npc.state == Identity().STATE_EMBODIED then
            local px, py, pz, inWorld
            local body = Bodies and Bodies.bound[id] or nil
            if cellReady and body ~= nil and Bodies.inWorld(body) then
                px, py, pz, inWorld = body:getX(), body:getY(), body:getZ(), true
            elseif Identity().isPosition(npc.last) then
                px, py, pz, inWorld = npc.last.x, npc.last.y, npc.last.z, false
            end
            if px ~= nil then
                local dx, dy = px - x, py - y
                if math.abs(dx) <= radius and math.abs(dy) <= radius then
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= radius then
                        local o = owners[id]
                        out[#out + 1] = { id = id, group = o and o.group or nil, member = o and o.member or nil,
                            role = o and o.role or nil, distance = math.floor(dist + 0.5),
                            floor = math.floor(pz) - math.floor(z), inWorld = inWorld }
                    end
                end
            end
        end
    end
    table.sort(out, function(p, q)
        if p.distance ~= q.distance then return p.distance < q.distance end
        return (Identity().idNumber(p.id) or 0) < (Identity().idNumber(q.id) or 0)
    end)
    return out
end

-- Projection sûre pour un client : liste blanche des champs de la vue publique, valeurs simples seulement.
-- Accepte une vue de listGroups/getGroup ou un groupe brut du registre (alors converti : foyer en maille, journal et
-- histoire privée jamais repris). Rend une table neuve, ou nil.
function API.publicGroup(g)
    if type(g) ~= "table" then return nil end
    if g.nextMember ~= nil or g.home ~= nil or g.log ~= nil then
        if type(g.members) ~= "table" or type(g.needs) ~= "table" then return nil end
        g = view(g, true)
    end
    local out = {}
    for _, k in ipairs({ "id", "type", "typeNameKey", "name", "summary", "task" }) do
        if isText(g[k]) then out[k] = g[k] end
    end
    for _, k in ipairs({ "founded", "alive", "total", "morale" }) do
        if isNumber(g[k]) then out[k] = g[k] end
    end
    if type(g.needs) == "table" then
        out.needs = {}
        for _, k in ipairs(API.NEEDS) do
            if isNumber(g.needs[k]) then out.needs[k] = g.needs[k] end
        end
    end
    if type(g.leader) == "table" and isText(g.leader.id) then
        out.leader = { id = g.leader.id, npc = isText(g.leader.npc) and g.leader.npc or nil,
            name = isText(g.leader.name) and g.leader.name or nil }
    end
    if type(g.area) == "table" then
        out.area = API.area(g.area.x, g.area.y) -- remis sur la maille, même si l'entrée était exacte
    end
    -- Attitude envers le joueur destinataire (vue demandée pour lui) : niveau et tendance connus seulement.
    if type(g.attitude) == "table" then
        local H = LivingKnox.Hostility
        local level, trend = g.attitude.level, g.attitude.trend
        if isText(level) and isText(trend) and inList(H.LEVELS, level) and inList(H.TRENDS, trend) then
            out.attitude = { level = level, trend = trend }
        end
    end
    if type(g.members) == "table" then
        out.members = {}
        for _, m in ipairs(g.members) do
            if type(m) == "table" and isText(m.id) then
                out.members[#out.members + 1] = { id = m.id, role = isText(m.role) and m.role or nil,
                    alive = m.alive == true, npc = isText(m.npc) and m.npc or nil }
            end
        end
    end
    return out
end

-- Offres de ressources pour les missions (LK12-T03) -----------------------------------------------------------------
-- Barème : docs/specifications-techniques/passeur-table.md, section 5 (même valeur V que le passeur ; 1 point de réserve = 4 V,
-- arrondi au plus proche ; un groupe ne cède pas ce qui lui manque). Seuils des réserves : LivingKnox.Config.SIMULATION
-- (NEED_LOW, NEED_OK, NEED_TARGET), repli sur les valeurs ci-dessous. Heures = heures de jeu entières (âge du monde).

API.SUPPLY = {
    V_PER_POINT = 4,         -- 1 point de réserve = 4 points V (barème, section 5)
    VALUE_MAX = 40,          -- V demandée par une offre (10 points de réserve)
    VALUE_LOW = 60,          -- V demandée quand la réserve est sous NEED_LOW (15 points)
    VALUE_MIN = 8,           -- plancher (réserve juste sous le seuil, si NEED_TARGET est proche)
    HOURS = 48,              -- durée d'une offre ouverte (heures de jeu : 2 h réelles au réglage par défaut)
    COUNT_MAX = 60,          -- exemplaires d'un même objet dans une livraison
    RECEIPTS_MAX = 16,       -- reçus gardés par groupe (rejeu reconnu sur ces derniers)
    RECEIPT_KEY_MAX = 64,
    MARGIN = 0.30,           -- marge de vente d'un groupe neutre (barème, section 5)
    REWARD_SHARE = 0.5,      -- prix de vente de l'objet de récompense <= cette part de la valeur demandée
    ATTITUDE_FACT = "delivery", -- fait d'attitude (LivingKnox.Hostility.FACTS) que l'appelant enregistre
    NEED_LOW = 25, NEED_OK = 40, NEED_TARGET = 60, -- repli si Config.SIMULATION manque
}

-- Objets acceptés par réserve (liste fermée, module Base, valeurs V du barème). Vérifiés dans les scripts vanilla
-- 42.21 (media/scripts/generated/items) : food.txt:4381 TinnedBeans, 4433 TinnedSoup, 3727 CannedChili,
-- 3778 CannedCornedBeef, 3828 CannedCorn, 4077 CannedPeas, 4176 CannedPotato2, 4278 CannedTomato2,
-- 3624 CannedBolognese, 3884 CannedFruitCocktail, 5006 Rice, 4959 Pasta, 4786 DriedBlackBeans, 13359 PeanutButter,
-- 15211 Antibiotics ; normal.txt:8071 Bandage, 8283 Disinfectant, 8156 SutureNeedle, 13722 ShotgunShellsBox,
-- 13487 308Box, 13547 3030Box, 13517 556Box, 13693 Bullets9mmBox ; drainable.txt:1506 AlcoholWipes, 1414 Pills.
-- AntibioticsBox (90 V) est écartée : plus grosse qu'une offre entière.
API.SUPPLY_ITEMS = {
    food = {
        { type = "Base.TinnedBeans", value = 2 }, { type = "Base.TinnedSoup", value = 2 },
        { type = "Base.CannedChili", value = 2 }, { type = "Base.CannedCornedBeef", value = 2 },
        { type = "Base.CannedCorn", value = 2 }, { type = "Base.CannedPeas", value = 2 },
        { type = "Base.CannedPotato2", value = 2 }, { type = "Base.CannedTomato2", value = 2 },
        { type = "Base.CannedBolognese", value = 2 }, { type = "Base.CannedFruitCocktail", value = 2 },
        { type = "Base.Rice", value = 2 }, { type = "Base.Pasta", value = 2 },
        { type = "Base.DriedBlackBeans", value = 2 }, { type = "Base.PeanutButter", value = 2 },
    },
    medical = {
        { type = "Base.Antibiotics", value = 8 }, { type = "Base.Bandage", value = 1 },
        { type = "Base.AlcoholWipes", value = 1 }, { type = "Base.Disinfectant", value = 3 },
        { type = "Base.Pills", value = 3 }, { type = "Base.SutureNeedle", value = 3 },
    },
    ammo = {
        { type = "Base.ShotgunShellsBox", value = 12 }, { type = "Base.308Box", value = 14 },
        { type = "Base.3030Box", value = 12 }, { type = "Base.556Box", value = 8 },
        { type = "Base.Bullets9mmBox", value = 10 },
    },
}

-- Objet de récompense tiré d'une réserve NON manquante (au moins NEED_TARGET à l'ouverture, au moins NEED_OK après
-- la cession) : un seul type par réserve, pris dans la liste ci-dessus.
API.REWARD_ITEMS = { food = "Base.TinnedBeans", medical = "Base.Antibiotics", ammo = "Base.ShotgunShellsBox" }

local function simCfg(key)
    local sim = LivingKnox.Config and LivingKnox.Config.SIMULATION
    local v = type(sim) == "table" and sim[key] or nil
    if isNumber(v) and v >= 0 and v <= 100 then return v end
    return API.SUPPLY[key]
end

local function roundHalf(x) return math.floor(x + 0.5) end

local function itemValue(need, fullType)
    local list = API.SUPPLY_ITEMS[need]
    if type(list) ~= "table" or type(fullType) ~= "string" then return nil end
    for _, it in ipairs(list) do
        if it.type == fullType then return it.value end
    end
    return nil
end

-- Heure de jeu courante (entier, âge du monde), ou nil si l'horloge manque.
function API.currentHour()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if not isNumber(hours) or hours < 0 then return nil end
    return math.floor(hours)
end

local function isCount(v, hi)
    return isNumber(v) and math.floor(v) == v and v >= 0 and v <= hi
end

local function validOffer(rec, need, gid)
    return type(rec) == "table" and isText(rec.id) and rec.need == need
        and string.sub(rec.id, 1, #gid + #need + 2) == gid .. "-" .. need .. "-"
        and isCount(rec.opened, 2147483647) and isCount(rec.expires, 2147483647) and rec.expires >= rec.opened
        and isCount(rec.value, 1000) and rec.value >= 1 and isCount(rec.delivered, 1000)
        and (rec.rewardType == nil or (isText(rec.rewardType) and isCount(rec.rewardCount, 1000)
            and inList(API.NEEDS, rec.rewardNeed)))
end

local function validReceipt(r)
    return type(r) == "table" and isText(r.key) and isText(r.offer) and inList(API.NEEDS, r.need)
        and isCount(r.value, 1000) and isNumber(r.points) and isCount(r.level, 100) and type(r.completed) == "boolean"
end

-- État des offres d'un groupe vivant du registre (créé ou remis à neuf s'il est absent ou malformé). Rend supply et
-- vrai s'il a été créé ou réparé.
local function supplyOf(g)
    local s = g.supply
    local ok = type(s) == "table" and isCount(s.next, 2147483647) and s.next >= 1 and type(s.offers) == "table"
        and type(s.receipts) == "table"
    if ok then
        for key, rec in pairs(s.offers) do
            if not inList(API.NEEDS, key) or not validOffer(rec, key, g.id) then ok = false end
        end
        local n = 0
        for _ in pairs(s.receipts) do n = n + 1 end
        if n ~= #s.receipts or n > API.SUPPLY.RECEIPTS_MAX then ok = false end
        for i = 1, #s.receipts do
            if not validReceipt(s.receipts[i]) then ok = false end
        end
    end
    if ok then return s, false end
    if s ~= nil then LivingKnox.Log.error("supply state of %s is invalid: reset (open offers and receipts lost)", g.id) end
    local nextId = 1
    if type(s) == "table" and isCount(s.next, 2147483647) and s.next >= 1 then nextId = s.next end
    s = { next = nextId, offers = {}, receipts = {} }
    g.supply = s
    return s, true
end

local function aliveCount(g)
    local n = 0
    for _, m in pairs(g.members) do
        if m.alive then n = n + 1 end
    end
    return n
end

-- Récompense proposée à l'ouverture : objet de la réserve la plus haute (autre que need) à NEED_TARGET au moins, au
-- prix de vente ceil(V x q x (1 + MARGIN)) <= REWARD_SHARE x value, et cession qui laisse la réserve >= NEED_OK.
local function pickReward(g, need, value)
    local S = API.SUPPLY
    local best
    for _, key in ipairs(API.NEEDS) do
        if key ~= need and g.needs[key] >= simCfg("NEED_TARGET") and (best == nil or g.needs[key] > g.needs[best]) then
            best = key
        end
    end
    if not best then return nil end
    local rtype = API.REWARD_ITEMS[best]
    local v = itemValue(best, rtype)
    if not v then return nil end
    local budget = value * S.REWARD_SHARE
    local count = 0
    while math.ceil(v * (count + 1) * (1 + S.MARGIN) - 1e-9) <= budget and count < S.COUNT_MAX do
        count = count + 1
    end
    if count < 1 then return nil end
    if g.needs[best] - roundHalf(v * count / S.V_PER_POINT) < simCfg("NEED_OK") then return nil end
    return rtype, count, best
end

-- Ferme les offres expirées ou remplies, ouvre une offre par réserve sous NEED_OK (groupe avec un vivant). Logique
-- sur le groupe vivant ; rend vrai si quelque chose a changé.
local function refreshOffers(g, hour)
    local S = API.SUPPLY
    local s, changed = supplyOf(g)
    local alive = aliveCount(g) > 0
    for _, need in ipairs(API.NEEDS) do
        local rec = s.offers[need]
        if rec and (hour >= rec.expires or rec.delivered >= rec.value or not alive) then
            s.offers[need] = nil
            rec = nil
            changed = true
        end
        local level = g.needs[need]
        if not rec and alive and level < simCfg("NEED_OK") then
            local value = (simCfg("NEED_TARGET") - level) * S.V_PER_POINT
            local cap = S.VALUE_MAX
            if level < simCfg("NEED_LOW") then cap = S.VALUE_LOW end
            if value > cap then value = cap end
            if value < S.VALUE_MIN then value = S.VALUE_MIN end
            rec = { id = g.id .. "-" .. need .. "-" .. s.next, need = need, opened = hour, expires = hour + S.HOURS,
                value = value, delivered = 0 }
            rec.rewardType, rec.rewardCount, rec.rewardNeed = pickReward(g, need, value)
            s.next = s.next + 1
            s.offers[need] = rec
            changed = true
        end
    end
    return changed
end

-- Vue publique d'une offre ouverte (copie).
local function offerView(g, rec, hour)
    local items = {}
    local remaining = rec.value - rec.delivered
    for _, it in ipairs(API.SUPPLY_ITEMS[rec.need]) do
        if it.value <= rec.value then
            items[#items + 1] = { type = it.type, value = it.value, count = math.ceil(remaining / it.value) }
        end
    end
    local reward = { attitudeFact = API.SUPPLY.ATTITUDE_FACT }
    if rec.rewardType then reward.item = { type = rec.rewardType, count = rec.rewardCount } end
    return { id = rec.id, group = g.id, need = rec.need, level = g.needs[rec.need], items = items, value = rec.value,
        delivered = rec.delivered, remaining = remaining, points = roundHalf(remaining / API.SUPPLY.V_PER_POINT),
        opened = rec.opened, expires = rec.expires, hours = rec.expires - hour, reward = reward }
end

-- Refus d'un joueur hostile : vrai si playerKey est fourni et que le groupe lui est hostile ; nil et une raison si
-- la clé est invalide ou l'attitude illisible.
local function hostileTo(gid, playerKey)
    if playerKey == nil then return false end
    local a, why = API.attitude(gid, playerKey)
    if not a then return nil, why end
    return a.level == "hostile"
end

-- Offres admissibles d'un groupe : missionOffers(groupId[, playerKey]) -> { offer, ... } (ordre de API.NEEDS), ou
-- nil et une raison. Une offre par réserve sous NEED_OK, ouverte paresseusement ici (écriture du registre seulement si
-- une offre s'ouvre ou se ferme), identifiant stable "<groupe>-<réserve>-<n>" jusqu'à son expiration ou sa
-- complétion ; aucune offre si le groupe n'a aucun besoin, aucun vivant, ou s'il est hostile au joueur fourni.
function API.missionOffers(gid, playerKey)
    local data = groupData()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    local hostile, why = hostileTo(gid, playerKey)
    if hostile == nil then return nil, why end
    if hostile then return {} end
    local hour = API.currentHour()
    if hour == nil then return nil, "no game clock" end
    return Groups().update(function(reg)
        local live = reg.groups[gid]
        local changed = refreshOffers(live, hour)
        local out = {}
        for _, need in ipairs(API.NEEDS) do
            local rec = live.supply.offers[need]
            if rec then out[#out + 1] = offerView(live, rec, hour) end
        end
        return changed, out
    end)
end

local function receiptView(r, duplicate)
    local out = { applied = not duplicate, duplicate = duplicate, receipt = r.key, offer = r.offer, need = r.need,
        value = r.value, points = r.points, level = r.level, completed = r.completed }
    if r.completed then
        out.reward = { attitudeFact = API.SUPPLY.ATTITUDE_FACT }
        if r.rewardType then out.reward.item = { type = r.rewardType, count = r.rewardCount } end
    end
    return out
end

-- Contrôle d'une livraison { ["Base.X"] = nombre, ... } pour une offre : rend la valeur V totale et la plus petite
-- valeur unitaire, ou nil et une raison.
local function deliveryValue(rec, delivered)
    if type(delivered) ~= "table" then return nil, "bad delivery" end
    local total, smallest, kinds = 0, nil, 0
    for fullType, count in pairs(delivered) do
        local v = itemValue(rec.need, fullType)
        if not v or v > rec.value then return nil, "item not accepted: " .. tostring(fullType) end
        if not isCount(count, API.SUPPLY.COUNT_MAX) or count < 1 then return nil, "bad count for " .. fullType end
        total = total + v * count
        if smallest == nil or v < smallest then smallest = v end
        kinds = kinds + 1
    end
    if kinds == 0 then return nil, "nothing delivered" end
    return total, smallest
end

-- Livraison validée : deliver(groupId, offerId, delivered, receiptKey[, playerKey]) -> result, ou nil et une raison.
-- delivered = { ["Base.X"] = nombre } (objets déjà contrôlés et retirés par l'appelant, ou à retirer seulement après
-- un résultat applied). Idempotent par receiptKey : un reçu déjà connu rend son résultat d'origine (duplicate = vrai,
-- applied = faux) sans rien changer. Réserve remontée de round(cumul / 4) - round(cumul précédent / 4), bornée à 100 ;
-- à la complétion, la réserve de la récompense baisse du prix de l'objet (ou l'objet est retiré si elle passerait
-- sous NEED_OK) et l'offre se ferme. Une entrée de journal « supply » par livraison.
function API.deliver(gid, offerId, delivered, receiptKey, playerKey)
    local S = API.SUPPLY
    if not isText(receiptKey) or #receiptKey < 1 or #receiptKey > S.RECEIPT_KEY_MAX
        or string.match(receiptKey, "^[%w_.:-]+$") == nil then
        return nil, "bad receipt key"
    end
    local data = groupData()
    if not data then return nil, NOT_READY end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    if not isText(offerId) then return nil, "unknown offer " .. tostring(offerId) end
    local hour = API.currentHour()
    if hour == nil then return nil, "no game clock" end
    local result, err = Groups().update(function(reg)
        local live = reg.groups[gid]
        local s, repaired = supplyOf(live)
        for _, r in ipairs(s.receipts) do
            if r.key == receiptKey then
                if r.offer ~= offerId then return repaired, { err = "receipt key already used" } end
                return repaired, { ok = receiptView(r, true) }
            end
        end
        local hostile, why = hostileTo(gid, playerKey)
        if hostile == nil then return repaired, { err = why } end
        if hostile then return repaired, { err = "group is hostile" } end
        local ogid, need = string.match(offerId, "^(grp%-%d+)%-(%a+)%-%d+$")
        if ogid ~= gid or not inList(API.NEEDS, need) then return repaired, { err = "unknown offer " .. offerId } end
        local rec = s.offers[need]
        if not rec or rec.id ~= offerId then return repaired, { err = "offer closed" } end
        if hour >= rec.expires then return repaired, { err = "offer expired" } end
        if aliveCount(live) == 0 then return repaired, { err = "offer closed" } end
        local total, smallest = deliveryValue(rec, delivered)
        if not total then return repaired, { err = smallest } end
        local remaining = rec.value - rec.delivered
        -- Au-delà du reste, seul le dernier objet peut dépasser : un objet de plus que nécessaire est refusé.
        if total > remaining and total - smallest >= remaining then return repaired, { err = "too many items" } end
        local counted = total
        if counted > remaining then counted = remaining end
        local before = rec.delivered
        rec.delivered = before + counted
        local gain = roundHalf(rec.delivered / S.V_PER_POINT) - roundHalf(before / S.V_PER_POINT)
        local old = live.needs[need]
        local level = old + gain
        if level > Groups().LEVEL_MAX then level = Groups().LEVEL_MAX end
        live.needs[need] = level
        local r = { key = receiptKey, offer = offerId, need = need, value = counted, points = level - old,
            level = level, completed = rec.delivered >= rec.value, day = Groups().today() }
        local text = need .. " +" .. tostring(level - old) .. " (" .. offerId .. ", " .. tostring(counted) .. " V)"
        if r.completed then
            if rec.rewardType then
                local cost = roundHalf(itemValue(rec.rewardNeed, rec.rewardType) * rec.rewardCount / S.V_PER_POINT)
                if live.needs[rec.rewardNeed] - cost >= simCfg("NEED_OK") then
                    live.needs[rec.rewardNeed] = live.needs[rec.rewardNeed] - cost
                    r.rewardType, r.rewardCount = rec.rewardType, rec.rewardCount
                    text = text .. ", gives " .. tostring(rec.rewardCount) .. " " .. rec.rewardType
                else
                    text = text .. ", reward withdrawn"
                end
            end
            text = text .. ", done"
            s.offers[need] = nil
        end
        s.receipts[#s.receipts + 1] = r
        while #s.receipts > S.RECEIPTS_MAX do table.remove(s.receipts, 1) end
        Groups().appendLog(live, "supply", string.sub(text, 1, Groups().TEXT_MAX), r.day)
        return true, { ok = receiptView(r, false) }
    end)
    if not result then return nil, err end
    if result.err then return nil, result.err end
    return result.ok
end

-- Événements publics (LK12-T02) ----------------------------------------------------------------------------------
-- Événements Lua déclarés par LuaEventManager.AddEvent (idempotent : rend l'événement existant, LuaEventManager.java
-- 615-631, 42.21) sur l'autorité seulement. Un mod tiers s'abonne sans dépendance dure : il déclare lui-même le nom
-- (LuaEventManager.AddEvent, sans effet si déjà fait) puis Events[nom].Add(fn), dans n'importe quel ordre de
-- chargement ; sans Living Knox, l'événement ne part jamais. Aucun envoi aux clients : un client MP ne les reçoit pas.
-- Source : faits internes du moteur (LivingKnox.listen) mis en file, puis déclenchés au pas suivant
-- (OnTickEvenPaused), une fois la transaction du registre terminée : la charge utile est relue dans le registre
-- (membres d'un groupe tout juste peuplé, membre bien marqué mort) et un fait d'une transaction non écrite (registre
-- bloqué) est abandonné. Une seule fois par fait (clé de fait gardée pour la session). Besoin critique : sondage
-- EveryTenMinutes. Charge utile = table neuve de valeurs simples, jamais de foyer exact, de journal ni de secret ; elle
-- est partagée par les abonnés d'un même déclenchement (ne pas la modifier). Documentation :
-- docs/specifications-techniques/api-living-knox.md.

API.EVENTS = {
    groupCreated = "OnLivingKnoxGroupCreated",
    memberDied = "OnLivingKnoxMemberDied",
    groupGone = "OnLivingKnoxGroupGone",
    needCritical = "OnLivingKnoxNeedCritical",
    encounter = "OnLivingKnoxEncounter",
    memberLeft = "OnLivingKnoxMemberLeft",
}
API.EVENT_QUEUE_MAX = 256   -- faits en attente au plus (le plus ancien abandonné au-delà)

API.events = API.events or { queue = {}, fired = {}, critical = {}, seeded = false, stats = {} }

for _, name in pairs(API.EVENTS) do
    if LuaEventManager ~= nil and LuaEventManager.AddEvent ~= nil then LuaEventManager.AddEvent(name) end
end

local function countEvent(name)
    local s = API.events.stats
    s[name] = (s[name] or 0) + 1
end

-- Déclenche l'événement public kind (clé de API.EVENTS) une seule fois pour la clé de fait key. Rend vrai si parti.
local function fire(kind, key, payload)
    local st = API.events
    if st.fired[key] then return false end
    st.fired[key] = true
    countEvent(kind)
    if triggerEvent ~= nil then triggerEvent(API.EVENTS[kind], payload) end
    return true
end

local function counts(g)
    local alive, total = 0, 0
    for _, m in pairs(g.members) do
        total = total + 1
        if m.alive then alive = alive + 1 end
    end
    return alive, total
end

local function homeArea(g)
    if type(g.home) ~= "table" then return nil end
    return API.area(g.home.x, g.home.y)
end

local function textOrNil(v)
    if isText(v) then return v end
    return nil
end

-- Groupe sans vivant après une mort ou un départ (et qui a eu au moins un membre) : « groupe disparu », une fois.
-- total = membres encore connus du registre (morts ; les partis en sont retirés).
local function checkGone(g, reason, day)
    local alive, total = counts(g)
    if alive > 0 or not isNumber(g.nextMember) or g.nextMember <= 1 then return end
    fire("groupGone", "gone|" .. g.id, { group = g.id, reason = reason, total = total, day = day })
end

-- Traitement d'un fait en file (registre prêt). data = registre vivant (lecture seule).
local function handle(data, f, touch)
    local g = isText(f.group) and data.groups[f.group] or nil
    if f.kind == "created" then
        if not g then return end
        local alive = counts(g)
        fire("groupCreated", "created|" .. g.id, { group = g.id, type = g.type, typeNameKey = typeNameKey(g.type),
            name = g.name, day = g.founded, alive = alive, area = homeArea(g) })
    elseif f.kind == "died" then
        local m = g and isText(f.member) and g.members[f.member] or nil
        if not m then return end
        local area = API.area(f.x, f.y) or homeArea(g)
        local alive = counts(g)
        local key = "died|" .. g.id .. "|" .. f.member
        fire("memberDied", key, { group = g.id, member = f.member, npc = textOrNil(m.npc) or textOrNil(f.npc),
            role = m.role, offscreen = f.offscreen == true, cause = textOrNil(f.cause), byPlayer = f.byPlayer == true,
            area = area, groupAlive = alive, day = f.day })
        touch(g, "dead", f.day)
    elseif f.kind == "left" then
        if not isText(f.member) or f.alive ~= true then return end
        if g and g.members[f.member] ~= nil then return end   -- membre revenu : transaction annulée
        local key = "left|" .. f.group .. "|" .. f.member
        fire("memberLeft", key, { group = f.group, member = f.member, npc = textOrNil(f.npc), role = textOrNil(f.role),
            reason = textOrNil(f.reason), groupAlive = g and counts(g) or 0, day = f.day })
        if g then touch(g, "left", f.day) end
    elseif f.kind == "removed" then
        if g or not isNumber(f.alive) or f.alive < 1 then return end   -- encore là, ou déjà sans vivant (annoncé)
        fire("groupGone", "gone|" .. f.group, { group = f.group, reason = "removed", day = f.day })
    elseif f.kind == "encounter" then
        if not g or not isText(f.player) then return end
        local key = "enc|" .. g.id .. "|" .. f.player .. "|" .. tostring(f.n)
        fire("encounter", key, { group = g.id, npc = textOrNil(f.npc), player = f.player,
            level = textOrNil(f.level), day = f.day })
    end
end

-- Déclenche les événements des faits en attente (appelé à chaque pas ; sans fait, rien). Les faits produits par un
-- abonné pendant ce passage partent au passage suivant. Rend le nombre de faits traités.
function API.flushEvents()
    local st = API.events
    if #st.queue == 0 then return 0 end
    local list = st.queue
    st.queue = {}
    local data = groupData()
    if not data then
        LivingKnox.Log.error("events: group registry not ready, %d fact(s) dropped", #list)
        return 0
    end
    -- Groupes touchés par une mort ou un départ : disparition jugée après tous les faits du passage, avec la raison du
    -- dernier fait du groupe (celui qui l'a vidé).
    local order, last = {}, {}
    local function touch(g, reason, day)
        if last[g.id] == nil then order[#order + 1] = g.id end
        last[g.id] = { reason = reason, day = day }
    end
    for _, f in ipairs(list) do
        local ok, err = pcall(handle, data, f, touch)
        if not ok then LivingKnox.Log.error("events: fact %s failed: %s", tostring(f.kind), tostring(err)) end
    end
    for _, gid in ipairs(order) do
        local g = data.groups[gid]
        if g then
            local ok, err = pcall(checkGone, g, last[gid].reason, last[gid].day)
            if not ok then LivingKnox.Log.error("events: group %s gone check failed: %s", gid, tostring(err)) end
        end
    end
    return #list
end

local function enqueue(f)
    local q = API.events.queue
    q[#q + 1] = f
    if #q > API.EVENT_QUEUE_MAX then
        table.remove(q, 1)
        LivingKnox.Log.warn("events: queue full, oldest fact dropped")
    end
end

local function today() return Groups().today() end

-- Abonnés aux faits internes (LK_Core.listen, idempotents par clé). Les champs privés du fait (corps, tueur, arme,
-- case exacte, témoins) ne sont jamais recopiés tels quels dans la charge utile.
LivingKnox.listen("groupCreated", "API.events", function(info)
    enqueue({ kind = "created", group = info.group })
end)
-- Mort d'un corps de PNJ (LK_Bodies, après le registre des groupes) : membre d'un groupe seulement.
LivingKnox.listen("npcDied", "API.events", function(info)
    if info.group == nil then return end
    enqueue({ kind = "died", group = info.group, member = info.member, npc = info.npc, offscreen = false,
        cause = info.cause, byPlayer = info.killer ~= nil, x = info.x, y = info.y, day = today() })
end)
-- Mort hors écran (LK_Groups.applyDeath) ; la mort d'un corps présent (offscreen = faux) vient de npcDied.
LivingKnox.listen("memberDied", "API.events", function(info)
    if info.offscreen ~= true then return end
    enqueue({ kind = "died", group = info.group, member = info.member, npc = info.npc, offscreen = true,
        day = info.day })
end)
LivingKnox.listen("memberLeft", "API.events", function(info)
    enqueue({ kind = "left", group = info.group, member = info.member, npc = info.npc, role = info.role,
        alive = info.alive, reason = info.reason, day = info.day })
end)
LivingKnox.listen("groupRemoved", "API.events", function(info)
    enqueue({ kind = "removed", group = info.group, alive = info.alive, day = info.day })
end)
LivingKnox.listen("encounterStarted", "API.events", function(info)
    enqueue({ kind = "encounter", group = info.group, npc = info.npc, player = info.player, level = info.level,
        n = info.n, day = today() })
end)

-- Besoin critique : réserve publique (needs) sous NEED_LOW, groupe avec un vivant ; sortie de l'état critique à
-- NEED_OK ou plus (hystérésis : une oscillation autour du seuil ne répète pas l'événement). Mémoire de session : les
-- groupes présents au premier sondage sont relevés sans événement (un redémarrage ne répète rien) ; un groupe apparu
-- ensuite est jugé normalement. Rend le nombre d'événements partis.
function API.checkNeeds()
    local st = API.events
    local data = groupData()
    if not data then return 0 end
    local low, ok = simCfg("NEED_LOW"), simCfg("NEED_OK")
    local sent = 0
    local seeding = not st.seeded
    for _, gid in ipairs(Groups().list()) do
        local g = data.groups[gid]
        local alive = counts(g)
        for _, need in ipairs(API.NEEDS) do
            local slot = gid .. "|" .. need
            local level = g.needs[need]
            if st.critical[slot] then
                if level >= ok then st.critical[slot] = nil end
            elseif level < low and alive > 0 then
                st.critical[slot] = true
                if not seeding then
                    countEvent("needCritical")
                    if triggerEvent ~= nil then
                        triggerEvent(API.EVENTS.needCritical, { group = gid, need = need, level = level,
                            threshold = low, alive = alive, day = today() })
                    end
                    sent = sent + 1
                end
            end
        end
    end
    st.seeded = true
    return sent
end

-- E08-T03 (ajout compatible de la version 1) : vrai si le PNJ npcId est OCCUPÉ à l'instant (prédicat provisoire
-- jusqu'à LK05-T08 et LK06-T01, docs/specifications-techniques/api-living-knox.md « API.engaged ») ; rend true et la raison, ou
-- false. Raisons, dans cet ordre : "hit" (coup d'un joueur reçu depuis moins de ENGAGED_MS : Bodies.lastHits), "combat"
-- (ordre de combat de LK_Combat en cours : couvre les coups portés pendant l'engagement ; un ordre clos est oublié), "warning"
-- (sommation de LK11-T02 en cours menée par ce PNJ : rencontre à une étape >= 1), "alert" (alerte de LK05-T08
-- active pour son groupe). Modules absents (suites isolées) : la raison correspondante ne compte pas. Mémoire
-- seulement : rien n'est lu dans une sauvegarde.
API.ENGAGED_MS = 30000

function API.engaged(npcId)
    if npcId == nil then return false end
    local t = getTimestampMs()
    local B = LivingKnox.Bodies
    local hit = B ~= nil and B.lastHits ~= nil and B.lastHits[npcId] or nil
    if hit ~= nil and isNumber(hit.ms) and t - hit.ms < API.ENGAGED_MS then return true, "hit" end
    local Co = LivingKnox.Combat
    local order = Co ~= nil and Co.orders ~= nil and Co.orders[npcId] or nil
    if order ~= nil then return true, "combat" end
    local En = LivingKnox.Encounters
    if En ~= nil and En.state ~= nil and En.state.list ~= nil then
        for _, enc in pairs(En.state.list) do
            if enc.npc == npcId and isNumber(enc.stage) and enc.stage > 0 then return true, "warning" end
        end
    end
    local Al, D = LivingKnox.Alert, LivingKnox.Decisions
    if Al ~= nil and Al.isActive ~= nil and D ~= nil and D.currentMinute ~= nil and Groups().ensure() then
        local gid = Groups().findNpc(npcId)
        local minute = D.currentMinute()
        if gid ~= nil and minute ~= nil and Al.isActive(gid, minute) then return true, "alert" end
    end
    return false
end

-- Table Events absente seulement hors du jeu (VM de test sans boucle d'événements).
if Events ~= nil then
    LivingKnox.subscribe("OnTickEvenPaused", "API.flushEvents", function() API.flushEvents() end)
    LivingKnox.subscribe("EveryTenMinutes", "API.checkNeeds", function() API.checkNeeds() end)
end

return API
