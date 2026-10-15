-- Living Knox : journal de récit des groupes (LK10-T02). Fiche : docs/conception/journal.md ; API : docs/api.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Deux journaux par groupe :
--   g.log     (LK_Groups) : journal TECHNIQUE, privé (coordonnées, comptes de joueurs, détails de calcul) ; tout module
--             y écrit ; jamais rendu par LK_API.
--   g.journal (ce module) : journal de RÉCIT, public : faits marquants datés, données publiques seulement, texte
--             composable en EN/FR par des clés de traduction. Il est TIRÉ du journal technique : chaque entrée
--             technique passe par Groups.onLog (LK_Groups.appendLog) dans la même écriture du registre ; une entrée
--             de récit au plus par fait, sauvegardée avec lui (une transaction non écrite n'en laisse aucune).
--             Deux faits internes complètent ce qui n'est pas au journal technique : encounterStarted (rencontres,
--             mises en file puis écrites au pas suivant) et memberDied d'un corps tué par un joueur (variante
--             « killed » de la mort qui suit). memberLeft complète le rôle d'un départ.
--
-- Champ facultatif du groupe (schéma 1 du registre inchangé, non contrôlé par LK_Groups ; contrôlé ici et remis à neuf
-- s'il est malformé) :
--   journal = { v = FORMAT, n = <numéro de la prochaine entrée>, e = { entry, ... } (SIZE dernières, la plus ancienne
--             d'abord) }
--   entry   = { n = numéro (croissant, jamais réutilisé dans le groupe), day = jour de jeu (celui du fait technique),
--               hour = heure du jour 0..23 du début de l'heure de jeu du fait (nil sans horloge), kind = KINDS,
--               args = { valeur, ... } (ARGS_MAX au plus : chaînes <= ARG_MAX octets ou entiers),
--               member = "m-<k>" ou nil, npc = "lk-<n>" ou nil }
-- Heure : heure simulée en cours (Groups.hourContext, posée par LK_Simulation.advance) ou, hors simulation, l'heure de
-- jeu courante ; heure simulée k = intervalle d'âge du monde [k-1, k[, début à (k + 6) % 24 h (LK_Simulation).
-- Aucune coordonnée, aucun compte de joueur, aucun secret d'histoire dans une entrée : tout le contenu est public.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"

local Journal = LivingKnox.Journal or {}
LivingKnox.Journal = Journal

Journal.FORMAT = 1
Journal.SIZE = 40              -- entrées gardées par groupe (les plus anciennes oubliées)
Journal.ARGS_MAX = 4
Journal.ARG_MAX = 64           -- octets d'un argument texte (nom de groupe <= Groups.NAME_MAX = 64)
Journal.QUEUE_MAX = 64         -- faits en attente au plus (rencontres)
Journal.KEY_PREFIX = "IGUI_LK_Journal_"
Journal.ROLE_PREFIX = "IGUI_LK_Journal_Role_"
Journal.PLACE_PREFIX = "IGUI_LK_Journal_Place_"
Journal.UNKNOWN_ROLE = "member"

-- Sortes d'entrée (liste fermée) et type de leurs arguments : role (rôle d'un membre, traduit par ROLE_PREFIX), place
-- (lieu d'une expédition abstraite, traduit par PLACE_PREFIX), group (nom d'un groupe, tel quel), count (entier).
Journal.KINDS = {
    founded = {}, settled = {}, moved = {},
    leader = { "role" }, leaderless = {},
    died = { "role" }, killed = { "role" },
    left = { "role" }, deserted = { "role" }, recruit = { "role" },
    expedition = { "count", "place" }, trip = { "count" }, returned = { "count" }, noneBack = {},
    encounter = { "count" },
    attackWon = { "group" }, attackLost = { "group" }, defenseWon = { "group" }, defenseLost = { "group" },
    wiped = {}, dispersed = {}, relief = { "group" }, relieved = { "group" },
}

Journal.state = Journal.state or { killed = {}, queue = {}, reset = {} }
Journal.stats = Journal.stats or { added = 0, merged = 0, skipped = 0, reset = 0, queued = 0, dropped = 0 }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function isMember(v) return type(v) == "string" and string.match(v, "^m%-%d+$") ~= nil end
local function isNpc(v) return type(v) == "string" and string.match(v, "^lk%-%d+$") ~= nil end

-- Format ------------------------------------------------------------------------------------------------------------

local function validEntry(e)
    if type(e) ~= "table" or not isInt(e.n, 1, 2147483647) or not isInt(e.day, 0, 2147483647) then return false end
    if e.hour ~= nil and not isInt(e.hour, 0, 23) then return false end
    if type(e.kind) ~= "string" or Journal.KINDS[e.kind] == nil then return false end
    if type(e.args) ~= "table" or #e.args > Journal.ARGS_MAX then return false end
    local count = 0
    for _ in pairs(e.args) do count = count + 1 end
    if count ~= #e.args then return false end
    for _, a in ipairs(e.args) do
        local t = type(a)
        if t == "string" then
            if #a > Journal.ARG_MAX then return false end
        elseif not isInt(a, -2147483647, 2147483647) then
            return false
        end
    end
    if e.member ~= nil and not isMember(e.member) then return false end
    if e.npc ~= nil and not isNpc(e.npc) then return false end
    return true
end

-- Vrai si j est un journal bien formé (numéros croissants, inférieurs à n).
function Journal.valid(j)
    if type(j) ~= "table" or j.v ~= Journal.FORMAT or not isInt(j.n, 1, 2147483647) or type(j.e) ~= "table" then
        return false
    end
    local count = 0
    for _ in pairs(j.e) do count = count + 1 end
    if count ~= #j.e or count > Journal.SIZE then return false end
    local last = 0
    for _, e in ipairs(j.e) do
        if not validEntry(e) or e.n <= last or e.n >= j.n then return false end
        last = e.n
    end
    return true
end

-- Journal vivant du groupe g (créé s'il manque ; remis à neuf, une ligne au journal, s'il est malformé).
local function journalOf(g)
    local j = g.journal
    if j == nil then
        j = { v = Journal.FORMAT, n = 1, e = {} }
        g.journal = j
    elseif not Journal.valid(j) then
        local n = type(j) == "table" and isInt(j.n, 1, 2147483647) and j.n or 1
        j = { v = Journal.FORMAT, n = n, e = {} }
        g.journal = j
        Journal.stats.reset = Journal.stats.reset + 1
        if not Journal.state.reset[g.id] then
            Journal.state.reset[g.id] = true
            log().warn("journal: malformed story journal of %s reset", tostring(g.id))
        end
    end
    return j
end

-- Heure de jeu (convention de LK_Simulation : k = [k-1, k[) : heure simulée en cours, sinon l'heure en cours de
-- l'horloge ; nil sans horloge.
function Journal.worldHour()
    local k = Groups().hourContext
    if isInt(k, 0, 2147483647) then return k end
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= "number" or hours ~= hours or hours < 0 then return nil end
    return math.floor(hours) + 1
end

-- Heure du jour (0..23) du début de l'heure de jeu k.
function Journal.hourOfDay(k)
    if not isInt(k, 0, 2147483647) then return nil end
    return (k + 6) % 24
end

local function cleanArg(a)
    if type(a) == "number" and a == a then
        a = math.floor(a)
        if a > 2147483647 then a = 2147483647 elseif a < -2147483647 then a = -2147483647 end
        return a
    end
    a = tostring(a)
    if #a > Journal.ARG_MAX then a = string.sub(a, 1, Journal.ARG_MAX) end
    return a
end

-- Ajoute une entrée au journal du groupe vivant g (logique pure, sans sauvegarde : l'écriture en cours la porte).
-- opts = { member, npc, at = heure de jeu (défaut : worldHour) }. Rend l'entrée vivante, ou nil (sorte inconnue).
function Journal.add(g, kind, args, day, opts)
    if Journal.KINDS[kind] == nil or type(g) ~= "table" then return nil end
    opts = opts or {}
    local j = journalOf(g)
    local list = {}
    for i, a in ipairs(args or {}) do
        if i > Journal.ARGS_MAX then break end
        list[i] = cleanArg(a)
    end
    if not isInt(day, 0, 2147483647) then day = Groups().today() end
    local at = opts.at
    if not isInt(at, 0, 2147483647) then at = Journal.worldHour() end
    local e = { n = j.n, day = day, hour = Journal.hourOfDay(at), kind = kind, args = list }
    if isMember(opts.member) then e.member = opts.member end
    if isNpc(opts.npc) then e.npc = opts.npc end
    j.n = j.n + 1
    j.e[#j.e + 1] = e
    while #j.e > Journal.SIZE do table.remove(j.e, 1) end
    Journal.stats.added = Journal.stats.added + 1
    return e
end

-- Dernière entrée de sorte kind (et du membre mid si donné) écrite le jour day, ou nil.
local function lastOf(g, kind, mid, day)
    local j = type(g.journal) == "table" and g.journal or nil
    if j == nil or type(j.e) ~= "table" then return nil, nil end
    for i = #j.e, 1, -1 do
        local e = j.e[i]
        if day ~= nil and e.day ~= day then return nil, nil end
        if e.kind == kind and (mid == nil or e.member == mid) then return e, i end
    end
    return nil, nil
end

local function memberOf(g, mid)
    return type(mid) == "string" and type(g.members) == "table" and g.members[mid] or nil
end

local function groupName(gid)
    local data = Groups().state.data
    local other = data and type(gid) == "string" and data.groups[gid] or nil
    if other ~= nil and type(other.name) == "string" then return other.name end
    return tostring(gid)
end

-- Entrées techniques -> entrées de récit -----------------------------------------------------------------------------
-- Une fonction par sorte technique retenue ; les autres sortes (objective, task, ration, alert, supply, admin hors
-- foyer, trip, loss, wounded, joined, remains, conflict, illness, raid, revenge, aid, trade, care, defense...) restent
-- au seul journal technique. Le texte technique n'est lu que pour des formes stables, écrites par le moteur et
-- vérifiées par le banc (tests/test_lk_journal.py).

local TECH = {}

TECH.founded = function(g, text, day)
    Journal.add(g, type(g.home) == "table" and "settled" or "founded", {}, day)
end

TECH.admin = function(g, text, day)
    if string.sub(text, 1, 5) == "home " then Journal.add(g, "moved", {}, day) end
end

TECH.leader = function(g, mid, day)
    local m = memberOf(g, mid)
    if m == nil then
        Journal.add(g, "leaderless", {}, day)
    else
        Journal.add(g, "leader", { m.role }, day, { member = mid, npc = m.npc })
    end
end

TECH.died = function(g, mid, day)
    local m = memberOf(g, mid)
    local slot = tostring(g.id) .. "|" .. tostring(mid)
    local killed = Journal.state.killed[slot] == true
    Journal.state.killed[slot] = nil
    Journal.add(g, killed and "killed" or "died", { m and m.role or Journal.UNKNOWN_ROLE }, day,
        { member = mid, npc = m and m.npc or nil })
end

-- Départ : rôle complété par le fait memberLeft qui suit (le membre est déjà retiré) ; un départ hors écran
-- (« departure », juste avant) en tient lieu.
TECH.left = function(g, mid, day)
    if lastOf(g, "deserted", mid, day) ~= nil then return end
    Journal.add(g, "left", { Journal.UNKNOWN_ROLE }, day, { member = mid })
end

TECH.departure = function(g, text, day)
    local mid, role = string.match(text, "^(m%-%d+) ([%w_]+)")
    if mid == nil then return end
    local m = memberOf(g, mid)
    Journal.add(g, "deserted", { role }, day, { member = mid, npc = m and m.npc or nil })
end

TECH.recruit = function(g, text, day)
    local mid, role = string.match(text, "(m%-%d+) ([%w_]+)$")
    if mid == nil then return end
    local m = memberOf(g, mid)
    Journal.add(g, "recruit", { role }, day, { member = mid, npc = m and m.npc or nil })
end

-- Départ en expédition : physique (« trip <n> to ... », LK_Expeditions : équipe de trips.cur) ou abstraite
-- (LK_Simulation : g.expedition, lieu de Config.SIMULATION.EXPEDITIONS.PLACES, heure de départ exacte).
TECH.expedition = function(g, text, day)
    if string.match(text, "^trip %d+ to ") then
        local cur = type(g.trips) == "table" and g.trips.cur or nil
        local team = type(cur) == "table" and type(cur.team) == "table" and #cur.team or 0
        Journal.add(g, "trip", { team }, day)
        return
    end
    local e = g.expedition
    if type(e) ~= "table" or type(e.team) ~= "table" then return end
    Journal.add(g, "expedition", { #e.team, e.place }, day, { at = e.departed })
end

-- Retour (abstrait, physique, équipe perdue) : « : <n> back » ou « , <n> back » (pas « trip <n> back from ») ;
-- « no one came back » = personne. Les morts de l'expédition ont chacune leur entrée (died).
TECH["return"] = function(g, text, day)
    local back = tonumber(string.match(text, "[:,] (%d+) back") or "")
    if string.find(text, "no one came back", 1, true) or back == 0 then
        Journal.add(g, "noneBack", {}, day)
    elseif back ~= nil then
        Journal.add(g, "returned", { back }, day)
    end
end

TECH.clash = function(g, text, day)
    local side, other, outcome = string.match(text, "^(%a+) (grp%-%d+) (%a+):")
    if side == nil then return end
    local kind = (side == "attack" and "attack" or "defense") .. (outcome == "won" and "Won" or "Lost")
    Journal.add(g, kind, { groupName(other) }, day)
end

TECH.gone = function(g, cause, day)
    if cause == "wiped" or cause == "dispersed" then Journal.add(g, cause, {}, day) end
end

TECH.relief = function(g, gid, day) Journal.add(g, "relief", { groupName(gid) }, day) end
TECH.relieved = function(g, gid, day) Journal.add(g, "relieved", { groupName(gid) }, day) end

-- Abonné de LK_Groups.appendLog (groupe vivant, dans l'écriture en cours).
function Journal.onLog(g, kind, text, day)
    local fn = TECH[kind]
    if fn == nil or type(g) ~= "table" then return end
    if type(text) ~= "string" then text = "" end
    fn(g, text, day)
end

Groups().onLog = function(g, kind, text, day) Journal.onLog(g, kind, text, day) end

-- Faits internes (LK_Core.listen) -----------------------------------------------------------------------------------

-- Mort d'un corps présent tué par un joueur (publiée par LK_Bodies avant la mort au registre, dans le même appel) :
-- la mort qui suit devient « killed ». Le compte du joueur n'est pas gardé.
LivingKnox.listen("memberDied", "Journal.killed", function(info)
    if info.offscreen == true or info.killer == nil or info.group == nil or info.member == nil then return end
    Journal.state.killed[tostring(info.group) .. "|" .. tostring(info.member)] = true
end)

-- Départ (publié par LK_Groups.applyLeave juste après l'entrée « left », avant l'écriture) : rôle du membre ; un
-- départ par dispersion n'a pas d'entrée propre (l'entrée « dispersed » le dit).
LivingKnox.listen("memberLeft", "Journal.left", function(info)
    local data = Groups().state.data
    local g = data and type(info.group) == "string" and data.groups[info.group] or nil
    if g == nil then return end
    local e, i = lastOf(g, "left", info.member, info.day)
    if e == nil then return end
    if info.reason == "dispersed" then
        table.remove(g.journal.e, i)
    elseif type(info.role) == "string" then
        e.args[1] = cleanArg(info.role)
    end
end)

-- Rencontre (sommation commencée, LK_Encounters) : mise en file, écrite au pas suivant hors de toute écriture du
-- registre ; une entrée par groupe et par jour, son compte augmenté par les suivantes. Ni joueur ni position gardés.
LivingKnox.listen("encounterStarted", "Journal.encounter", function(info)
    if type(info.group) ~= "string" then return end
    local q = Journal.state.queue
    q[#q + 1] = { group = info.group, day = Groups().today(), at = Journal.worldHour() }
    Journal.stats.queued = Journal.stats.queued + 1
    if #q > Journal.QUEUE_MAX then
        table.remove(q, 1)
        Journal.stats.dropped = Journal.stats.dropped + 1
        log().warn("journal: queue full, oldest encounter dropped")
    end
end)

-- Écrit les rencontres en attente (une sauvegarde). Rend le nombre de faits traités.
function Journal.flush()
    local q = Journal.state.queue
    if #q == 0 then return 0 end
    if not Groups().ensure() then return 0 end   -- registre non prêt : file gardée (bornée)
    Journal.state.queue = {}
    Groups().update(function(data)
        local changed = false
        for _, f in ipairs(q) do
            local g = data.groups[f.group]
            if g ~= nil then
                local e = lastOf(g, "encounter", nil, f.day)
                if e ~= nil and type(e.args[1]) == "number" then
                    e.args[1] = e.args[1] + 1
                    Journal.stats.merged = Journal.stats.merged + 1
                else
                    Journal.add(g, "encounter", { 1 }, f.day, { at = f.at })
                end
                changed = true
            end
        end
        return changed, true
    end)
    return #q
end

-- Lecture --------------------------------------------------------------------------------------------------------

-- Clé de traduction d'une entrée.
function Journal.keyOf(kind)
    return Journal.KEY_PREFIX .. tostring(kind)
end

-- Vue publique (copie neuve) d'une entrée : { n, day, hour, kind, key, args = { { text, key }, ... }, member, npc }.
-- key d'un argument : clé de traduction du rôle ou du lieu (le consommateur la résout, repli sur text), sinon nil.
function Journal.entryView(e)
    local spec = Journal.KINDS[e.kind] or {}
    local args = {}
    for i, a in ipairs(e.args) do
        local t, key = spec[i], nil
        if t == "role" then key = Journal.ROLE_PREFIX .. tostring(a) elseif t == "place" then
            key = Journal.PLACE_PREFIX .. tostring(a)
        end
        args[i] = { text = tostring(a), key = key }
    end
    return { n = e.n, day = e.day, hour = e.hour, kind = e.kind, key = Journal.keyOf(e.kind), args = args,
        member = e.member, npc = e.npc }
end

-- Texte d'une vue d'entrée : resolve(key, a1, ...) rend le texte d'une clé composé avec ses arguments, ou nil
-- (getTextOrNull). Arguments à clé (rôle, lieu) résolus d'abord, repli sur leur texte. La clé de l'entrée est
-- toujours résolue AVEC ses arguments (un getTextOrNull sans argument sur un texte à %1 écrit « Missing arguments »,
-- base load-warnings.md). Rend le texte, ou nil si la clé ne se résout pas.
function Journal.compose(view, resolve)
    local args = {}
    for i, a in ipairs(view.args) do
        local text = a.key and resolve(a.key) or nil
        args[i] = text or a.text
    end
    return resolve(view.key, args[1], args[2], args[3], args[4])
end

-- Texte de la vue sur cette machine (langue du processus), ou nil quand les traductions du mod n'y sont pas chargées
-- (serveur dédié : getTextOrNull rend nil, base api-42-21.md) : key et args font alors foi.
function Journal.text(view)
    if getTextOrNull == nil then return nil end
    return Journal.compose(view, getTextOrNull)
end

-- Entrées publiques du groupe vivant g de numéro > since (défaut 0), la plus ancienne d'abord, et le prochain numéro.
function Journal.view(g, since)
    local out = {}
    local j = type(g) == "table" and g.journal or nil
    if not Journal.valid(j) then return out, 1 end
    if not isInt(since, 0, 2147483647) then since = 0 end
    for _, e in ipairs(j.e) do
        if e.n > since then out[#out + 1] = Journal.entryView(e) end
    end
    return out, j.n
end

if Events ~= nil then
    LivingKnox.subscribe("OnTickEvenPaused", "Journal.flush", function() Journal.flush() end)
end

return Journal
