-- Living Knox : simulation abstraite des groupes hors écran, par heure de jeu (LK09-T01).
-- Fiche : docs/conception/simulation.md. Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge
-- aussi media/lua/server, il s'arrête ici.
--
-- Pour chaque heure de jeu écoulée et chaque groupe du registre (LK_Groups) ayant au moins un membre vivant :
--   1. choix de la tâche hors écran par priorités (I1.6) : soigner (blessé grave et soins en réserve), se reposer
--      (nuit ou fatigue), fouiller (une réserve sous NEED_TARGET), sinon se reposer ; journalisée quand elle change ;
--   2. consommation de nourriture et de munitions selon l'effectif vivant ;
--   3. fouille : petit gain borné (0..SCAVENGE_MAX) sur la réserve la plus basse ;
--   4. blessures abstraites par membre (wound 0..100) : nouvelles blessures au hasard, guérison avec les soins
--      (medical consommé), aggravation sans, faim ; mort à WOUND_DEATH (Groups.applyDeath, comme markDead), le chef
--      mort est remplacé aussitôt par le successeur de la règle de succession (Groups.pickSuccessor) ;
--   5. repos (rest 0..100) selon la tâche et le rythme jour/nuit ;
--   6. moral : baisse si réserves basses, fatigue, faim ou mort ; remonte avec le repos et des réserves correctes.
-- Expéditions abstraites (LK09-T02) : une fouille de jour devient une expédition quand la réserve la plus basse est
-- sous EXPEDITIONS.NEED_TRIGGER et que l'effectif le permet : équipe (TEAM_MIN..TEAM_MAX membres sains, hors chef,
-- MIN_HOME restant au foyer) vers un type de lieu de la liste fermée EXPEDITIONS.PLACES (durée, risque, rendement,
-- recrue), absente du foyer jusqu'au retour (ni consommation, ni repos, ni blessure au foyer). Au retour : pertes
-- (Groups.applyDeath), blessés (wound), gains de réserves, recrue éventuelle (Groups.applyMember, profil tiré du
-- type, bornée par size.max et MAX_MEMBERS), moral ; journal du groupe (kinds expedition, return, loss, recruit).
-- Tirages des expéditions : flux séparé (EXPEDITION_SALT) de la même heure, le flux principal reste inchangé.
-- Événements de groupe (LK09-T05) : liste fermée Simulation.EVENTS (departure, recruit, conflict, illness, clash),
-- un tirage par groupe et par jour à l'heure du jour EVENTS.HOUR, après les règles horaires de tous les groupes ;
-- au plus un événement par groupe et par jour (la cible d'un combat compte). Chances par jour et effets bornés en
-- données (Config.SIMULATION.EVENTS) ; flux séparé (EVENT_SALT). Combat abstrait (I9.1) entre un groupe d'un type
-- ATTACKERS et un groupe d'un autre type, foyers connus proches l'un de l'autre et loin des bases connues des
-- joueurs (RS_Rescue.knownBases, lue une fois par pas) ; morts consignés avec un lieu approximatif (entrée remains),
-- aucun cadavre posé dans le monde.
-- Membres incarnés (LK09-T03 : PNJ lié à l'état "embodied" au registre des corps, LK_Materialize) : présents au foyer
-- et comptés dans la consommation, mais leur santé est celle de leur corps : ni blessure, ni guérison, ni mort
-- horaire, jamais envoyés en expédition ; un groupe qui a un membre incarné ne tire aucun événement et n'est la cible
-- d'aucun combat. Le retrait du corps (LK03-T04) rend au membre sa blessure (LK_Materialize.onReleased).
-- Stock réel hors écran (LK09-T06, LK_Stock) : après chaque heure de chaque groupe, Stock.offscreenHour (repas
-- abstrait quotidien pris dans l'inventaire de référence) ; au retour d'une expédition abstraite, Stock.offscreenLoot
-- (butin ajouté). Écarts gardés en attente dans la référence, appliqués aux conteneurs quand le foyer est lisible.
-- Aucun déplacement de PNJ, aucun accès au monde (cases, chunks) : travail proportionnel au nombre de groupes et de
-- membres du registre (bornés : 64 groupes, 32 membres), multiplié par les heures simulées (bornées).
--
-- Heures : heure simulée k = intervalle d'âge du monde [k-1, k[ (getWorldAgeHours, 0 à 7 h le premier jour), donc
-- heure du jour de son début = (k + 6) % 24. La dernière heure simulée est gardée dans le registre (simHour, privé,
-- persistant, sauvegardé avec les groupes). Chaque pas simule les heures de simHour + 1 à l'heure courante, au plus
-- MAX_CATCHUP_HOURS (les plus récentes ; le reste est ignoré et journalisé). Registre sans simHour : la simulation
-- démarre à l'heure courante, sans rattrapage. Horloge en retard sur simHour (monde rechargé d'une sauvegarde plus
-- ancienne que le fichier des groupes) : rien n'est simulé tant que l'horloge ne l'a pas dépassée.
--
-- Tirages reproductibles : Park-Miller (aucun opérateur binaire, quotients sous 2^31 en Kahlua) suivi d'un mélange,
-- graine dérivée de (graine de partie ou Config.SIMULATION.SEED, numéro du groupe, heure) : le même état et les mêmes
-- heures donnent le même résultat, que les heures soient simulées une par une ou en un rattrapage. Les quantités par
-- heure sont fractionnaires : arrondi aléatoire reproductible (partie entière + 1 avec la probabilité de la fraction).
--
-- Accroche (LK_Server.lua) : EveryHours (GameTime.update, à chaque changement d'heure) et démarrage de la partie
-- (rattrapage). Serveur dédié vide en pause (PauseEmpty) : GameTime.update n'est pas appelé, l'heure n'avance pas,
-- aucun EveryHours, rien n'est simulé (IngameState.java:1528-1530, 1574 ; GameTime.java:553-554).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"

local Simulation = LivingKnox.Simulation or {}
LivingKnox.Simulation = Simulation

Simulation.TASKS = { "heal", "rest", "scavenge", "expedition" }
Simulation.state = Simulation.state or { waiting = false }

local M = 2147483647

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function cfg() return LivingKnox.Config.SIMULATION end

-- Niveau entier 0..100 (le registre n'admet que des entiers, même si un taux configuré est fractionnaire).
local function clampLevel(v)
    v = math.floor(v + 0.5)
    if v < 0 then return 0 end
    if v > 100 then return 100 end
    return v
end

-- Tirages ------------------------------------------------------------------------------------------------------------

local function hashText(s, h)
    for i = 1, #s do
        h = (h * 31 + string.byte(s, i)) % M
    end
    return h
end

-- Graine de base : Config.SIMULATION.SEED (entier) si fixée, sinon hachage du mode et du nom de la partie.
function Simulation.baseSeed()
    local fixed = cfg().SEED
    if type(fixed) == "number" and fixed == fixed then return math.floor(math.abs(fixed)) % M end
    local key = ""
    if getWorld and getWorld() then key = LivingKnox.Store.worldKey() end
    return hashText(key, 17)
end

-- Flux de tirages d'un groupe pour une heure : rnd() -> nombre dans ]0, 1[. salt (facultatif, entier) sépare des
-- flux indépendants pour la même heure (expéditions : EXPEDITION_SALT), sans changer le flux principal (salt absent).
function Simulation.stream(base, groupNumber, hour, salt)
    local x = ((base % M) * 7919 + (groupNumber % M) * 104729 + (hour % M) * 31 + ((salt or 0) % M) + 1) % M
    if x == 0 then x = 1 end
    local function rnd()
        x = (x * 48271) % M
        x = (x + (x % 65521) * 31337) % M
        if x == 0 then x = 1 end
        return x / M
    end
    for _ = 1, 4 do rnd() end
    return rnd
end

-- Arrondi aléatoire reproductible d'une quantité fractionnaire (signe conservé).
local function amount(v, rnd)
    local a = math.abs(v)
    local n = math.floor(a)
    if rnd() < a - n then n = n + 1 end
    if v < 0 then return -n end
    return n
end
Simulation.amount = amount

-- Règles ---------------------------------------------------------------------------------------------------------

-- Membres vivants triés par numéro (ancienneté).
local function livingMembers(g)
    local ids = {}
    for mid, m in pairs(g.members) do
        if m.alive then ids[#ids + 1] = mid end
    end
    table.sort(ids, function(a, b) return Groups().memberNumber(a) < Groups().memberNumber(b) end)
    return ids
end

-- Réserve la plus basse (égalité : ordre de Groups.NEEDS).
local function lowestNeed(g)
    local best
    for _, key in ipairs(Groups().NEEDS) do
        if not best or g.needs[key] < g.needs[best] then best = key end
    end
    return best
end

function Simulation.isNight(hourOfDay)
    local c = cfg()
    return hourOfDay >= c.NIGHT_START or hourOfDay < c.NIGHT_END
end

-- Tâche hors écran (I1.6) par priorités : rend la tâche et sa raison (anglais).
function Simulation.chooseTask(g, living, night)
    local c = cfg()
    if g.needs.medical > 0 then
        for _, mid in ipairs(living) do
            if (g.members[mid].wound or 0) >= c.WOUND_SERIOUS then return "heal", "wounded" end
        end
    end
    if night then return "rest", "night" end
    if (g.rest or Groups().DEFAULT_LEVEL) < c.REST_LOW then return "rest", "tired" end
    local key = lowestNeed(g)
    if g.needs[key] < c.NEED_TARGET then return "scavenge", key end
    return "rest", "idle"
end

-- Expéditions (LK09-T02) ---------------------------------------------------------------------------------------------

Simulation.EXPEDITION_SALT = 15485863
Simulation.EXPEDITION_HOURS_MAX = 72

-- Nombre borné ; valeur non numérique (ou NaN) : borne basse.
local function num(v, lo, hi)
    if type(v) ~= "number" or v ~= v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function int(v, lo, hi) return math.floor(num(v, lo, hi)) end

local function field(t, key)
    if type(t) ~= "table" then return nil end
    return t[key]
end

local function cut(text)
    local max = Groups().TEXT_MAX
    if #text > max then return string.sub(text, 1, max) end
    return text
end

local function warnPlaceOnce(key, why)
    local st = Simulation.state
    st.badPlaces = st.badPlaces or {}
    if st.badPlaces[key] then return end
    st.badPlaces[key] = true
    log().warn("simulation: expedition place %s ignored: %s", key, why)
end

-- Lieu de Config.SIMULATION.EXPEDITIONS.PLACES normalisé, ou nil (malformé : ignoré, avertissement unique).
local function readPlace(i, p, seen)
    if type(p) ~= "table" then
        warnPlaceOnce("#" .. i, "not a table")
        return nil
    end
    local id = p.id
    if type(id) ~= "string" or #id < 1 or #id > Groups().KIND_MAX or string.match(id, "^%l[%l%d_]*$") == nil then
        warnPlaceOnce("#" .. i, "bad id")
        return nil
    end
    if seen[id] then
        warnPlaceOnce(id, "duplicate id")
        return nil
    end
    seen[id] = true
    local out = { id = id, risk = num(p.risk, 0, 1), recruit = num(p.recruit, 0, 1), yield = {} }
    out.hoursMin = int(p.hoursMin, 1, Simulation.EXPEDITION_HOURS_MAX)
    out.hoursMax = int(p.hoursMax, out.hoursMin, Simulation.EXPEDITION_HOURS_MAX)
    for _, key in ipairs(Groups().NEEDS) do out.yield[key] = num(field(p.yield, key), 0, 100) end
    return out
end

-- Réglages des expéditions lus et bornés (à chaque pas) : toujours une table ; EXPEDITIONS absent ou sans lieu
-- valide : aucune expédition ne part (une expédition déjà en route revient quand même).
function Simulation.expeditionSettings()
    local raw = cfg().EXPEDITIONS
    if type(raw) ~= "table" then raw = {} end
    local G = Groups()
    local s = {
        needTrigger = num(raw.NEED_TRIGGER, 0, 100),
        departChance = num(raw.DEPART_CHANCE, 0, 1),
        teamMin = int(raw.TEAM_MIN, 1, G.MAX_MEMBERS),
        teamMax = int(raw.TEAM_MAX, 1, G.MAX_MEMBERS),
        minHome = int(raw.MIN_HOME, 1, G.MAX_MEMBERS),
        safetyMax = num(raw.SAFETY_MAX, 0, 1),
        yieldBonusMax = num(raw.YIELD_BONUS_MAX, 0, 10),
        deathShare = num(raw.DEATH_SHARE, 0, 1),
        woundMin = int(raw.WOUND_MIN, 0, 99),
        woundMax = int(raw.WOUND_MAX, 0, 99),
        moraleReturn = num(raw.MORALE_RETURN, 0, 100),
        roleSafety = {}, roleYield = {}, roleRank = {}, places = {},
    }
    if s.teamMax < s.teamMin then s.teamMax = s.teamMin end
    if s.woundMax < s.woundMin then s.woundMax = s.woundMin end
    for _, role in ipairs(LivingKnox.Config.GROUP_ROLES) do
        s.roleSafety[role] = num(field(raw.ROLE_SAFETY, role) or 0, 0, 1)
        s.roleYield[role] = num(field(raw.ROLE_YIELD, role) or 0, 0, 10)
    end
    if type(raw.TEAM_ROLES) == "table" then
        for i, role in ipairs(raw.TEAM_ROLES) do
            if type(role) == "string" and s.roleRank[role] == nil then s.roleRank[role] = i end
        end
    end
    local seen = {}
    if type(raw.PLACES) == "table" then
        for i, p in ipairs(raw.PLACES) do
            local place = readPlace(i, p, seen)
            if place then s.places[#s.places + 1] = place end
        end
    end
    return s
end

local function placeById(s, id)
    for _, p in ipairs(s.places) do
        if p.id == id then return p end
    end
    return nil
end

-- Élément de items tiré selon weightOf(item) (nombres >= 0), ou nil si le total est nul.
local function weighted(items, weightOf, rnd)
    local total, last = 0, nil
    for _, item in ipairs(items) do
        local w = weightOf(item)
        if w > 0 then
            total = total + w
            last = item
        end
    end
    if total <= 0 then return nil end
    local r = rnd() * total
    for _, item in ipairs(items) do
        local w = weightOf(item)
        if w > 0 then
            r = r - w
            if r <= 0 then return item end
        end
    end
    return last
end

-- Membre incarné (LK09-T03) : lien npc vers un PNJ "embodied" du registre des corps. Registre des corps absent ou
-- non prêt (banc de la simulation seule) : aucun membre incarné.
function Simulation.isEmbodied(m)
    if m == nil or m.npc == nil then return false end
    local S = LivingKnox.Store
    if S == nil or S.isReady == nil or not S.isReady() then return false end
    local npc = S.data().npcs[m.npc]
    return npc ~= nil and npc.state == "embodied"
end

-- Groupe matérialisé : au moins un membre vivant incarné.
function Simulation.materialized(g)
    for _, m in pairs(g.members) do
        if m.alive and Simulation.isEmbodied(m) then return true end
    end
    return false
end

-- Membres vivants au foyer : vivants moins l'équipe d'une expédition en route (ordre conservé).
local function homeMembers(g, living)
    if not g.expedition then return living end
    local away = {}
    for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    local out = {}
    for _, mid in ipairs(living) do
        if not away[mid] then out[#out + 1] = mid end
    end
    return out
end
Simulation.homeMembers = homeMembers

-- Candidats d'une équipe : au foyer, hors chef et membres incarnés (LK09-T03), blessure sous WOUND_MINOR ; triés
-- par TEAM_ROLES puis ancienneté.
function Simulation.teamCandidates(g, home, s)
    local c, G = cfg(), Groups()
    local out = {}
    for _, mid in ipairs(home) do
        if mid ~= g.leader and (g.members[mid].wound or 0) < c.WOUND_MINOR
            and not Simulation.isEmbodied(g.members[mid]) then
            out[#out + 1] = mid
        end
    end
    table.sort(out, function(a, b)
        local ra, rb = s.roleRank[g.members[a].role] or 1000, s.roleRank[g.members[b].role] or 1000
        if ra ~= rb then return ra < rb end
        return G.memberNumber(a) < G.memberNumber(b)
    end)
    return out
end

-- Départ éventuel (tâche « scavenge » pour la réserve need, aucune expédition en route) : réserve sous NEED_TRIGGER,
-- équipe de TEAM_MIN..TEAM_MAX en gardant MIN_HOME au foyer, un lieu qui rapporte cette réserve, tirage
-- DEPART_CHANCE ; lieu tiré selon son rendement sur need, durée tirée dans hoursMin..hoursMax. Rend le texte de
-- l'entrée de journal « expedition », ou nil (pas de départ). erand : flux des expéditions de l'heure.
function Simulation.tryDepart(g, hour, home, need, s, erand)
    if g.expedition or g.needs[need] >= s.needTrigger then return nil end
    local candidates = Simulation.teamCandidates(g, home, s)
    local size = math.min(s.teamMax, #candidates, #home - s.minHome)
    if size < s.teamMin then return nil end
    local function yieldOf(p) return p.yield[need] end
    local any = false
    for _, p in ipairs(s.places) do
        if yieldOf(p) > 0 then any = true end
    end
    if not any or erand() >= s.departChance then return nil end
    local place = weighted(s.places, yieldOf, erand)
    local hours = place.hoursMin + math.floor(erand() * (place.hoursMax - place.hoursMin + 1))
    local team = {}
    for i = 1, size do team[i] = candidates[i] end
    g.expedition = { place = place.id, team = team, departed = hour, returns = hour + hours }
    return cut(place.id .. ": " .. table.concat(team, " ") .. ", " .. tostring(hours) .. " h")
end

-- Profil d'une recrue tiré du type du groupe (même forme que LK_Population : rôle selon le poids des rôles parmi
-- ceux qui ont encore un profil disponible, profil selon son poids et son max compté sur les membres vivants, sexe
-- imposé ou tiré, traits à leur chance). nil : type inconnu, groupe plein (size.max du type en vivants,
-- MAX_MEMBERS du registre en membres) ou aucun profil disponible.
function Simulation.drawRecruit(g, rnd)
    local def = LivingKnox.GroupTypes.get(g.type)
    if not def then return nil end
    local living, total, used = 0, 0, {}
    for _, m in pairs(g.members) do
        total = total + 1
        if m.alive then
            living = living + 1
            if m.profile then used[m.profile] = (used[m.profile] or 0) + 1 end
        end
    end
    if living >= def.size.max or total >= Groups().MAX_MEMBERS then return nil end
    local function available(p) return p.max == nil or (used[p.id] or 0) < p.max end
    local roles = {}
    for _, role in ipairs(LivingKnox.Config.GROUP_ROLES) do
        if def.roles[role] then
            for _, p in ipairs(def.profiles) do
                if p.role == role and available(p) then
                    roles[#roles + 1] = role
                    break
                end
            end
        end
    end
    local role = weighted(roles, function(r) return def.roles[r].weight end, rnd)
    if role == nil then return nil end
    local candidates = {}
    for _, p in ipairs(def.profiles) do
        if p.role == role and available(p) then candidates[#candidates + 1] = p end
    end
    local p = weighted(candidates, function(x) return x.weight end, rnd)
    local female = p.female
    if female == nil then female = rnd() < 0.5 end
    local traits = nil
    for _, t in ipairs(p.traits or {}) do
        if rnd() * 100 < t.chance then
            traits = traits or {}
            traits[#traits + 1] = t.id
        end
    end
    return { role = role, profile = p.id, female = female, traits = traits }
end

-- Entrée « recruit » (<origine>: <membre> <rôle>) d'un membre que applyMember vient d'ajouter : applyMember a déjà
-- inscrit « joined », remis après « recruit » (ordre de lecture). Partagée par les expéditions et les événements.
local function logRecruit(g, origin, mid, role, day)
    Groups().appendLog(g, "recruit", cut(origin .. ": " .. mid .. " " .. role), day)
    local entries = g.log
    local n = #entries
    if n >= 2 and entries[n - 1].kind == "joined" then
        entries[n - 1], entries[n] = entries[n], entries[n - 1]
    end
end

-- Retour d'une expédition (heure >= returns) : par membre de l'équipe encore vivant, un tirage d'incident (chance =
-- risque effectif) dont la part DEATH_SHARE est mortelle (Groups.applyDeath, succession si c'était le chef) et le
-- reste une blessure WOUND_MIN..WOUND_MAX ; gains par réserve (moyenne yield x survivants x (1 + bonus), tirage
-- uniforme de 0 au double de la moyenne, arrondi reproductible) ; une recrue au plus (chance recruit, s'il reste un
-- survivant) ; moral. Journal dans l'ordre : return, loss, died..., recruit, joined. Rend le bilan
-- { place, team, back, lost, wounded, gains, recruit }.
function Simulation.resolveExpedition(g, gid, hour, s, erand, day)
    local c, G = cfg(), Groups()
    local e = g.expedition
    g.expedition = nil
    local present = {}
    for _, mid in ipairs(e.team) do
        local m = g.members[mid]
        if m and m.alive then present[#present + 1] = mid end
    end
    local result = { place = e.place, team = #e.team, back = #present, lost = {}, wounded = {}, gains = {} }
    for _, key in ipairs(G.NEEDS) do result.gains[key] = 0 end
    local place = placeById(s, e.place)
    if not place then
        G.appendLog(g, "return", cut(e.place .. ": unknown place, " .. #present .. " back"), day)
        return result
    end
    local safety, bonus = 0, 0
    for _, mid in ipairs(present) do
        local role = g.members[mid].role
        safety = safety + (s.roleSafety[role] or 0)
        bonus = bonus + (s.roleYield[role] or 0)
    end
    safety, bonus = math.min(safety, s.safetyMax), math.min(bonus, s.yieldBonusMax)
    local risk = place.risk * (1 - safety)
    local survivors = 0
    for _, mid in ipairs(present) do
        local r = erand()
        if r < risk * s.deathShare then
            result.lost[#result.lost + 1] = mid
        else
            survivors = survivors + 1
            if r < risk then
                local m = g.members[mid]
                local w = (m.wound or 0) + s.woundMin + math.floor(erand() * (s.woundMax - s.woundMin + 1))
                m.wound = clampLevel(math.min(w, c.WOUND_DEATH - 1))
                if m.wound <= 0 then m.wound = nil end
                result.wounded[#result.wounded + 1] = mid
            end
        end
    end
    result.back = survivors
    local gained, parts = 0, {}
    for _, key in ipairs(G.NEEDS) do
        local mean = place.yield[key] * survivors * (1 + bonus)
        local gain = amount(mean * 2 * erand(), erand)
        local before = g.needs[key]
        g.needs[key] = clampLevel(before + gain)
        result.gains[key] = g.needs[key] - before
        gained = gained + result.gains[key]
        parts[#parts + 1] = key .. " +" .. tostring(result.gains[key])
    end
    G.appendLog(g, "return", cut(place.id .. ": " .. survivors .. " back, " .. #result.lost .. " lost, "
        .. #result.wounded .. " wounded, " .. table.concat(parts, " ")), day)
    local morale = g.morale
    if #result.lost > 0 then
        G.appendLog(g, "loss", cut(place.id .. ": " .. table.concat(result.lost, " ")), day)
        for _, mid in ipairs(result.lost) do
            morale = morale + c.MORALE_DEATH
            local wasLeader = G.applyDeath(g, mid, day)
            log().info("simulation: group %s member %s lost on an expedition to %s (hour %s)", gid, mid, place.id,
                tostring(hour))
            if wasLeader then
                local successor = G.pickSuccessor(g)
                if successor then G.applyLeader(g, successor, day) end
            end
        end
    elseif gained > 0 then
        morale = morale + s.moraleReturn
    end
    g.morale = clampLevel(morale)
    if survivors > 0 and erand() < place.recruit then
        local spec = Simulation.drawRecruit(g, erand)
        if spec then
            local mid = G.applyMember(g, spec, day)
            if mid then
                result.recruit = mid
                logRecruit(g, place.id, mid, spec.role, day)
            end
        end
    end
    log().debug("simulation: group %s back from %s at hour %s: %s back, %s lost", gid, place.id, tostring(hour),
        tostring(survivors), tostring(#result.lost))
    return result
end

-- Une heure de jeu pour un groupe (registre vivant, sans sauvegarde). Rend la tâche choisie, ou nil (aucun vivant).
-- exp : réglages des expéditions (Simulation.expeditionSettings, lus une fois par pas ; défaut : relus ici).
function Simulation.simulateHour(g, gid, hour, base, exp)
    local living = livingMembers(g)
    if #living == 0 then return nil end
    local c, G = cfg(), Groups()
    exp = exp or Simulation.expeditionSettings()
    local rnd = Simulation.stream(base, G.idNumber(gid) or 0, hour)
    local erandFn
    local function erand()
        erandFn = erandFn or Simulation.stream(base, G.idNumber(gid) or 0, hour, Simulation.EXPEDITION_SALT)
        return erandFn()
    end
    local hourOfDay = (hour + 6) % 24
    local night = Simulation.isNight(hourOfDay)
    local day = math.floor(hour / 24) + 1
    local needs = g.needs
    if g.rest == nil then g.rest = G.DEFAULT_LEVEL end

    -- 0. Retour d'expédition (au début de l'heure de retour, ou de la première heure simulée après elle).
    if g.expedition and hour >= g.expedition.returns then
        local Ex = LivingKnox.Expeditions   -- LK05-T05 : expédition physique passée hors écran (aucune perte)
        local Rl = LivingKnox.Relations   -- LK11-T05 : équipe d'une vengeance (traque manquée, cible morte, rancune)
        if g.expedition.trip ~= nil and Ex ~= nil and Ex.resolveAbstract ~= nil then
            Ex.resolveAbstract(g, gid, hour, erand, day)
        elseif g.expedition.place == "revenge" and Rl ~= nil and Rl.revengeReturn ~= nil then
            Rl.revengeReturn(g, gid, hour, day)
        elseif g.expedition.place == "raid" and LivingKnox.Raids ~= nil and LivingKnox.Raids.raidReturn ~= nil then
            LivingKnox.Raids.raidReturn(g, gid, hour, day)   -- LK11-T07 : éclaireurs ou attaque d'un raid
        else
            local res = Simulation.resolveExpedition(g, gid, hour, exp, erand, day)
            local S = LivingKnox.Stock   -- LK09-T06 : butin abstrait ajouté au stock de référence (écarts en attente)
            if S ~= nil and S.offscreenLoot ~= nil then S.offscreenLoot(g, gid, res.gains, day) end
        end
        living = livingMembers(g)
        if #living == 0 then return nil end
    end
    -- Membres en expédition : absents du foyer (ni consommation, ni repos, ni blessure au foyer ; leurs vivres sont
    -- comptés dans le rendement net de l'expédition). Personne au foyer : rien d'autre cette heure.
    local home = homeMembers(g, living)
    if #home == 0 then return "expedition" end

    -- 1. Tâche ; une fouille devient une expédition (en route, ou départ tiré maintenant).
    local task, why = Simulation.chooseTask(g, home, night)
    local departure
    if task == "scavenge" then
        if g.expedition then
            task = "expedition"
        else
            departure = Simulation.tryDepart(g, hour, home, why, exp, erand)
            if departure then
                task = "expedition"
                home = homeMembers(g, living)
            end
        end
    end
    if task ~= g.task then
        g.task = task
        G.appendLog(g, "task", task .. ": " .. why, day)
        log().debug("simulation: group %s now %s (%s) at hour %s", gid, task, why, tostring(hour))
    end
    if departure then
        G.appendLog(g, "expedition", departure, day)
        log().debug("simulation: group %s expedition %s at hour %s", gid, departure, tostring(hour))
    end

    -- 2. Consommation (membres au foyer).
    local n = #home
    needs.food = clampLevel(needs.food - amount(c.FOOD_PER_MEMBER * n, rnd))
    needs.ammo = clampLevel(needs.ammo - amount(c.AMMO_PER_MEMBER * n, rnd))

    -- 3. Fouille.
    if task == "scavenge" then
        local key = lowestNeed(g)
        needs[key] = clampLevel(needs[key] + math.floor(rnd() * (c.SCAVENGE_MAX + 1)))
    end

    -- 4. Blessures.
    local starving = needs.food <= 0
    local healing = needs.medical > 0
    local medicalUse, deaths = 0, {}
    local chance = c.WOUND_CHANCE
    if task == "scavenge" then chance = c.WOUND_CHANCE_SCAVENGE end
    for _, mid in ipairs(home) do
        local m = g.members[mid]
        if not Simulation.isEmbodied(m) then   -- membre incarné : santé de son corps (LK09-T03)
            local w = m.wound or 0
            if rnd() < chance then
                w = w + c.WOUND_MIN + math.floor(rnd() * (c.WOUND_MAX - c.WOUND_MIN + 1))
                G.appendLog(g, "wounded", mid, day)
            end
            local delta = 0
            if w >= c.WOUND_MINOR then
                if healing then
                    delta = c.WOUND_HEAL
                    if task == "heal" then delta = delta * 2 end
                    medicalUse = medicalUse + c.MEDICAL_PER_HEAL
                else
                    delta = c.WOUND_WORSEN
                end
            elseif w > 0 then
                delta = c.WOUND_SELF_HEAL
            end
            if starving then delta = delta + c.WOUND_STARVING end
            if delta ~= 0 then w = w + amount(delta, rnd) end
            if w >= c.WOUND_DEATH then
                w = 100
                deaths[#deaths + 1] = mid
            end
            w = clampLevel(w)
            if w > 0 then m.wound = w else m.wound = nil end
        end
    end
    if medicalUse > 0 then needs.medical = clampLevel(needs.medical - amount(medicalUse, rnd)) end

    -- 5. Repos.
    local rest = g.rest
    if task == "rest" then
        rest = rest + c.REST_GAIN
    elseif task == "scavenge" then
        rest = rest + c.REST_SCAVENGE_LOSS
    elseif not night then
        rest = rest + c.REST_DAY_LOSS
    end
    g.rest = clampLevel(rest)

    -- 6. Moral.
    local mood, allOk = 0, g.rest >= c.REST_OK
    for _, key in ipairs(G.NEEDS) do
        if needs[key] < c.NEED_LOW then mood = mood + c.MORALE_LOW_NEED end
        if needs[key] < c.NEED_OK then allOk = false end
    end
    if g.rest < c.REST_LOW then mood = mood + c.MORALE_TIRED end
    if starving then mood = mood + c.MORALE_STARVING end
    if allOk then mood = mood + c.MORALE_GOOD end
    local morale = g.morale + amount(mood, rnd)

    -- Morts (après tous les tirages de l'heure).
    for _, mid in ipairs(deaths) do
        morale = morale + c.MORALE_DEATH
        local wasLeader = G.applyDeath(g, mid, day)
        log().info("simulation: group %s member %s died of wounds (hour %s)", gid, mid, tostring(hour))
        if wasLeader then
            local successor = G.pickSuccessor(g)
            if successor then G.applyLeader(g, successor, day) end
        end
    end
    g.morale = clampLevel(morale)
    return task
end

-- Événements de groupe (LK09-T05) ------------------------------------------------------------------------------------

-- Liste fermée, dans l'ordre du tirage ; chaque identifiant est aussi le kind de son entrée de journal.
Simulation.EVENTS = { "departure", "recruit", "conflict", "illness", "clash" }
Simulation.EVENT_SALT = 32452843

local EVENT_KEYS = { departure = "DEPARTURE", recruit = "RECRUIT", conflict = "CONFLICT", illness = "ILLNESS",
    clash = "CLASH" }

-- Bornes des réglages de chaque événement : { min, max, entier }. Valeur non numérique : 0 ramené dans ses bornes.
local EVENT_BOUNDS = {
    departure = { CHANCE = { 0, 1 }, MORALE_MAX = { 0, 100, true }, MIN_LEFT = { 1, 32, true },
        MORALE = { -100, 100 } },
    recruit = { CHANCE = { 0, 1 }, FOOD_MIN = { 0, 100, true }, MORALE_MIN = { 0, 100, true },
        MORALE = { -100, 100 } },
    conflict = { CHANCE = { 0, 1 }, CHANCE_LOW_NEED = { 0, 1 }, MORALE_MAX = { 0, 100, true },
        MIN_MEMBERS = { 2, 32, true }, MORALE = { -100, 100 }, WOUND_CHANCE = { 0, 1 }, WOUND_MIN = { 0, 99, true },
        WOUND_MAX = { 0, 99, true }, CONTEST_CHANCE = { 0, 1 } },
    illness = { CHANCE = { 0, 1 }, CHANCE_HUNGRY = { 0, 1 }, SPREAD = { 0, 1 }, MAX_SICK = { 1, 32, true },
        WOUND_MIN = { 0, 99, true }, WOUND_MAX = { 0, 99, true }, MEDICAL_PER_SICK = { 0, 100, true },
        MORALE = { -100, 100 } },
    clash = { CHANCE = { 0, 1 }, CHANCE_NEEDY = { 0, 1 }, MAX_DISTANCE = { 0, 100000, true },
        PLAYER_DISTANCE = { 80, 100000, true }, MIN_FORCE = { 1, 32, true }, DEFENSE_BONUS = { 0.1, 10 },
        LOSS_WIN = { 0, 1 }, LOSS_LOSE = { 0, 1 }, WOUND_WIN = { 0, 1 }, WOUND_LOSE = { 0, 1 },
        MAX_DEATHS = { 0, 32, true }, WOUND_MIN = { 0, 99, true }, WOUND_MAX = { 0, 99, true },
        LOOT_SHARE = { 0, 1 }, LOOT_MAX = { 0, 100, true }, AMMO_COST = { 0, 100, true },
        MORALE_WIN = { -100, 100 }, MORALE_LOSE = { -100, 100 }, PLACE_ROUND = { 1, 1000, true } },
}

local function bounded(v, range)
    if type(v) ~= "number" or v ~= v then v = 0 end
    if v < range[1] then v = range[1] end
    if v > range[2] then v = range[2] end
    if range[3] then v = math.floor(v) end
    return v
end

-- Réglages des événements lus et bornés (à chaque pas), ou nil si Config.SIMULATION.EVENTS est absent (aucun
-- événement). s[<événement>] = ses réglages (mêmes noms que la configuration), absent si sa sous-table manque.
function Simulation.eventSettings()
    local raw = cfg().EVENTS
    if type(raw) ~= "table" then return nil end
    local s = { hour = bounded(raw.HOUR, { 0, 23, true }), maxDaily = bounded(raw.MAX_DAILY, { 0, 1 }) }
    for id, bounds in pairs(EVENT_BOUNDS) do
        local t = raw[EVENT_KEYS[id]]
        if type(t) == "table" then
            local e = {}
            for name, range in pairs(bounds) do e[name] = bounded(t[name], range) end
            if e.WOUND_MAX and e.WOUND_MAX < e.WOUND_MIN then e.WOUND_MAX = e.WOUND_MIN end
            s[id] = e
        end
    end
    if s.clash then
        local attackers = {}
        if type(raw.CLASH.ATTACKERS) == "table" then
            for _, t in ipairs(raw.CLASH.ATTACKERS) do
                if type(t) == "string" then attackers[t] = true end
            end
        end
        s.clash.ATTACKERS = attackers
    end
    return s
end

-- Élément de list tiré uniformément (list non vide).
local function pick(list, rnd)
    local i = math.floor(rnd() * #list) + 1
    if i > #list then i = #list end
    return list[i]
end

-- Blessure abstraite ajoutée (lo..hi), bornée à WOUND_DEATH - 1 : un événement ne tue que par un tirage de perte.
local function hurt(m, lo, hi, rnd)
    local w = (m.wound or 0) + lo + math.floor(rnd() * (hi - lo + 1))
    m.wound = clampLevel(math.min(w, cfg().WOUND_DEATH - 1))
    if m.wound <= 0 then m.wound = nil end
end

local function lowNeedCount(g)
    local n, low = 0, cfg().NEED_LOW
    for _, key in ipairs(Groups().NEEDS) do
        if g.needs[key] < low then n = n + 1 end
    end
    return n
end

local function signed(v)
    if v >= 0 then return "+" .. tostring(v) end
    return tostring(v)
end

-- Membres qui peuvent partir : au foyer, hors chef, sans PNJ lié (le registre des corps garde sa référence).
local function departureCandidates(g, home)
    local out = {}
    for _, mid in ipairs(home) do
        if mid ~= g.leader and g.members[mid].npc == nil then out[#out + 1] = mid end
    end
    return out
end

-- Place pour une recrue : type enregistré, moins de size.max vivants et de MAX_MEMBERS membres (morts compris).
function Simulation.recruitRoom(g)
    local def = LivingKnox.GroupTypes.get(g.type)
    if not def then return false end
    local living, total = 0, 0
    for _, m in pairs(g.members) do
        total = total + 1
        if m.alive then living = living + 1 end
    end
    return living < def.size.max and total < Groups().MAX_MEMBERS
end

-- Écart entre le foyer (case) et une base (rectangle à fin exclusive), même mesure que RS_Rescue.gap.
local function baseGap(home, b)
    local gx = math.max(0, b.x1 - (home.x + 1), home.x - b.x2)
    local gy = math.max(0, b.y1 - (home.y + 1), home.y - b.y2)
    return math.sqrt(gx * gx + gy * gy)
end

-- Foyer à minDist cases au moins de chaque base connue (entrée sans x1, y1, x2, y2 numériques : ignorée).
function Simulation.farFromBases(home, bases, minDist)
    for _, b in ipairs(bases) do
        if type(b) == "table" and type(b.x1) == "number" and type(b.y1) == "number" and type(b.x2) == "number"
            and type(b.y2) == "number" and baseGap(home, b) < minDist then
            return false
        end
    end
    return true
end

-- Cibles possibles d'un combat lancé par le groupe gid (identifiants triés) : attaquant d'un type ATTACKERS, foyer
-- connu loin des bases, au moins MIN_FORCE membres au foyer ; cible d'un autre type (hors ATTACKERS), sans
-- événement ce jour, foyer connu à MAX_DISTANCE au plus et loin des bases, au moins un membre au foyer.
-- bases = nil (inconnues) : aucun combat.
function Simulation.clashTargets(data, ids, gid, s, bases, done)
    local e, g = s.clash, data.groups[gid]
    if not e or bases == nil or not e.ATTACKERS[g.type] or not g.home then return {} end
    if #homeMembers(g, livingMembers(g)) < e.MIN_FORCE then return {} end
    if not Simulation.farFromBases(g.home, bases, e.PLAYER_DISTANCE) then return {} end
    local out = {}
    for _, tid in ipairs(ids) do
        local t = data.groups[tid]
        if tid ~= gid and not done[tid] and t and not e.ATTACKERS[t.type] and t.home
            and not Simulation.materialized(t) then
            local dx, dy = t.home.x - g.home.x, t.home.y - g.home.y
            if math.sqrt(dx * dx + dy * dy) <= e.MAX_DISTANCE and Simulation.farFromBases(t.home, bases,
                e.PLAYER_DISTANCE) and #homeMembers(t, livingMembers(t)) > 0 then
                out[#out + 1] = tid
            end
        end
    end
    return out
end

-- Chances du jour de chaque événement pour le groupe gid (0..1 chacune), et cibles d'un combat. Voir l'en-tête.
function Simulation.eventChances(data, ids, gid, s, bases, done)
    local c, g = cfg(), data.groups[gid]
    local out, targets = {}, {}
    for _, id in ipairs(Simulation.EVENTS) do out[id] = 0 end
    local living = livingMembers(g)
    local home = homeMembers(g, living)
    if #home == 0 then return out, targets end
    local low = lowNeedCount(g)
    local e = s.departure
    if e and g.morale < e.MORALE_MAX and #living - 1 >= e.MIN_LEFT and #departureCandidates(g, home) > 0 then
        out.departure = e.CHANCE * (e.MORALE_MAX - g.morale) / e.MORALE_MAX
    end
    e = s.recruit
    if e and g.needs.food >= e.FOOD_MIN and g.morale >= e.MORALE_MIN and Simulation.recruitRoom(g) then
        out.recruit = e.CHANCE
    end
    e = s.conflict
    if e and #home >= e.MIN_MEMBERS and (g.morale < e.MORALE_MAX or low > 0) then
        out.conflict = e.CHANCE + e.CHANCE_LOW_NEED * low
    end
    e = s.illness
    if e then
        out.illness = e.CHANCE
        if g.needs.food < c.NEED_LOW then out.illness = out.illness + e.CHANCE_HUNGRY end
    end
    e = s.clash
    if e then
        targets = Simulation.clashTargets(data, ids, gid, s, bases, done)
        if #targets > 0 then
            out.clash = e.CHANCE
            if low > 0 then out.clash = out.clash + e.CHANCE_NEEDY end
        end
    end
    for _, id in ipairs(Simulation.EVENTS) do out[id] = math.min(out[id], 1) end
    return out, targets
end

-- Un seul tirage : événement choisi selon ses chances (somme plafonnée à maxDaily, proportions conservées), ou nil.
function Simulation.drawEvent(chances, maxDaily, rnd)
    local total = 0
    for _, id in ipairs(Simulation.EVENTS) do total = total + chances[id] end
    if total <= 0 then return nil end
    local scale = 1
    if total > maxDaily then scale = maxDaily / total end
    local r = rnd()
    for _, id in ipairs(Simulation.EVENTS) do
        local p = chances[id] * scale
        if p > 0 then
            if r < p then return id end
            r = r - p
        end
    end
    return nil
end

-- departure : un membre part (journal departure puis left), moral.
local function eventDeparture(g, gid, e, rnd, day)
    local candidates = departureCandidates(g, homeMembers(g, livingMembers(g)))
    if #candidates == 0 then return nil end
    local mid = pick(candidates, rnd)
    Groups().appendLog(g, "departure", cut(mid .. " " .. g.members[mid].role .. ": low morale"), day)
    Groups().applyLeave(g, mid, day)
    g.morale = clampLevel(g.morale + e.MORALE)
    log().info("simulation: member %s left group %s (low morale)", mid, gid)
    return { member = mid }
end

-- recruit : un survivant rejoint le groupe (journal recruit « wanderer: <membre> <rôle> » puis joined), moral.
local function eventRecruit(g, gid, e, rnd, day)
    local spec = Simulation.drawRecruit(g, rnd)
    if not spec then return nil end
    local mid = Groups().applyMember(g, spec, day)
    if not mid then return nil end
    logRecruit(g, "wanderer", mid, spec.role, day)
    g.morale = clampLevel(g.morale + e.MORALE)
    log().debug("simulation: wanderer %s joined group %s", mid, gid)
    return { member = mid, role = spec.role }
end

-- conflict : deux membres au foyer s'opposent (le premier hors chef ; le second est le chef si contesté), blessure
-- légère possible de l'un d'eux, moral. Aucun changement de chef (journal seulement).
local function eventConflict(g, e, rnd, day)
    local home = homeMembers(g, livingMembers(g))
    if #home < 2 then return nil end
    local others, leaderHome = {}, false
    for _, mid in ipairs(home) do
        if mid == g.leader then leaderHome = true else others[#others + 1] = mid end
    end
    local a = pick(others, rnd)
    local b, contested
    if leaderHome and rnd() < e.CONTEST_CHANCE then
        b, contested = g.leader, true
    else
        contested = false
        local rest = {}
        for _, mid in ipairs(home) do
            if mid ~= a then rest[#rest + 1] = mid end
        end
        b = pick(rest, rnd)
    end
    local parts, wounded = { a .. " vs " .. b }, nil
    if contested then parts[#parts + 1] = "leader contested" end
    if rnd() < e.WOUND_CHANCE then
        wounded = a
        if rnd() < 0.5 then wounded = b end
        hurt(g.members[wounded], e.WOUND_MIN, e.WOUND_MAX, rnd)
        parts[#parts + 1] = wounded .. " wounded"
    end
    g.morale = clampLevel(g.morale + e.MORALE)
    Groups().appendLog(g, "conflict", cut(table.concat(parts, ", ")), day)
    return { a = a, b = b, contested = contested, wounded = wounded }
end

-- illness : un malade au foyer, contagion à chaque autre (SPREAD, MAX_SICK au plus) ; un malade soigné (réserve
-- medical >= MEDICAL_PER_SICK et non vide) consomme MEDICAL_PER_SICK et prend la moitié de la blessure ; moral.
local function eventIllness(g, e, rnd, day)
    local home = homeMembers(g, livingMembers(g))
    if #home == 0 then return nil end
    local first = pick(home, rnd)
    local sick = { first }
    for _, mid in ipairs(home) do
        if mid ~= first and #sick < e.MAX_SICK and rnd() < e.SPREAD then sick[#sick + 1] = mid end
    end
    local treated, used = 0, 0
    for _, mid in ipairs(sick) do
        local lo, hi = e.WOUND_MIN, e.WOUND_MAX
        if g.needs.medical > 0 and g.needs.medical >= e.MEDICAL_PER_SICK then
            g.needs.medical = g.needs.medical - e.MEDICAL_PER_SICK
            used = used + e.MEDICAL_PER_SICK
            treated = treated + 1
            lo, hi = math.floor(lo / 2), math.floor(hi / 2)
        end
        hurt(g.members[mid], lo, hi, rnd)
    end
    g.morale = clampLevel(g.morale + e.MORALE)
    Groups().appendLog(g, "illness", cut(table.concat(sick, " ") .. " sick, " .. treated .. " treated, medical -"
        .. used), day)
    return { sick = sick, treated = treated, medical = used }
end

-- Force au foyer : 1 par membre, 0.5 par blessé grave (WOUND_SERIOUS).
local function strength(g, home)
    local serious, s = cfg().WOUND_SERIOUS, 0
    for _, mid in ipairs(home) do
        if (g.members[mid].wound or 0) >= serious then s = s + 0.5 else s = s + 1 end
    end
    return s
end

-- Un tirage par membre au foyer : perte (lossRate, MAX_DEATHS au plus, au-delà : blessure), sinon blessure.
local function casualties(g, home, lossRate, woundRate, e, rnd)
    local dead, wounded = {}, {}
    for _, mid in ipairs(home) do
        local r = rnd()
        if r < lossRate and #dead < e.MAX_DEATHS then
            dead[#dead + 1] = mid
        elseif r < lossRate + woundRate then
            hurt(g.members[mid], e.WOUND_MIN, e.WOUND_MAX, rnd)
            wounded[#wounded + 1] = mid
        end
    end
    return dead, wounded
end

local function roundedPlace(home, step)
    local function r(v) return math.floor(v / step + 0.5) * step end
    return r(home.x) .. "," .. r(home.y) .. "," .. home.z
end

-- clash (I9.1) : combat abstrait entre l'attaquant gid et la cible tid, au foyer de la cible. Victoire de
-- l'attaquant avec la chance force A / (force A + force D x DEFENSE_BONUS) ; pertes et blessés des deux côtés
-- (taux du vainqueur ou du vaincu) ; AMMO_COST munitions dépensées de chaque côté ; attaquant vainqueur : butin
-- borné (LOOT_SHARE de chaque réserve de la cible, LOOT_MAX au plus, sans dépasser 100) ; moral. Journal des deux
-- groupes : clash, died..., (leader), remains « <morts> at x,y,z » (foyer de la cible arrondi à PLACE_ROUND).
local function eventClash(data, gid, g, tid, e, rnd, day)
    local G, t = Groups(), data.groups[tid]
    local homeA, homeD = homeMembers(g, livingMembers(g)), homeMembers(t, livingMembers(t))
    local sa, sd = strength(g, homeA), strength(t, homeD) * e.DEFENSE_BONUS
    local won = rnd() * (sa + sd) < sa
    local deadA, woundedA, deadD, woundedD
    if won then
        deadA, woundedA = casualties(g, homeA, e.LOSS_WIN, e.WOUND_WIN, e, rnd)
        deadD, woundedD = casualties(t, homeD, e.LOSS_LOSE, e.WOUND_LOSE, e, rnd)
    else
        deadA, woundedA = casualties(g, homeA, e.LOSS_LOSE, e.WOUND_LOSE, e, rnd)
        deadD, woundedD = casualties(t, homeD, e.LOSS_WIN, e.WOUND_WIN, e, rnd)
    end
    local deltaA, deltaD = {}, {}
    for _, key in ipairs(G.NEEDS) do deltaA[key], deltaD[key] = 0, 0 end
    local beforeA, beforeD = g.needs.ammo, t.needs.ammo
    g.needs.ammo, t.needs.ammo = clampLevel(beforeA - e.AMMO_COST), clampLevel(beforeD - e.AMMO_COST)
    deltaA.ammo, deltaD.ammo = g.needs.ammo - beforeA, t.needs.ammo - beforeD
    if won then
        for _, key in ipairs(G.NEEDS) do
            local take = math.min(math.floor(t.needs[key] * e.LOOT_SHARE), e.LOOT_MAX, G.LEVEL_MAX - g.needs[key])
            if take > 0 then
                t.needs[key], g.needs[key] = t.needs[key] - take, g.needs[key] + take
                deltaA[key], deltaD[key] = deltaA[key] + take, deltaD[key] - take
            end
        end
    end
    local function needsText(delta)
        local parts = {}
        for _, key in ipairs(G.NEEDS) do parts[#parts + 1] = key .. " " .. signed(delta[key]) end
        return table.concat(parts, " ")
    end
    local outcomeA, outcomeD = "lost", "won"
    if won then outcomeA, outcomeD = "won", "lost" end
    G.appendLog(g, "clash", cut("attack " .. tid .. " " .. outcomeA .. ": " .. #deadA .. " lost, " .. #woundedA
        .. " wounded, " .. needsText(deltaA)), day)
    G.appendLog(t, "clash", cut("defend " .. gid .. " " .. outcomeD .. ": " .. #deadD .. " lost, " .. #woundedD
        .. " wounded, " .. needsText(deltaD)), day)
    local place = roundedPlace(t.home, e.PLACE_ROUND)
    local moraleA, moraleD = g.morale + e.MORALE_LOSE, t.morale + e.MORALE_WIN
    if won then moraleA, moraleD = g.morale + e.MORALE_WIN, t.morale + e.MORALE_LOSE end
    -- Morts d'un côté : toutes appliquées, puis une seule succession si le chef en était (jamais un mort du combat).
    local function bury(grp, dead, morale)
        local leaderDied = false
        for _, mid in ipairs(dead) do
            morale = morale + cfg().MORALE_DEATH
            if G.applyDeath(grp, mid, day) then leaderDied = true end
        end
        if leaderDied then
            local successor = G.pickSuccessor(grp)
            if successor then G.applyLeader(grp, successor, day) end
        end
        if #dead > 0 then G.appendLog(grp, "remains", cut(table.concat(dead, " ") .. " at " .. place), day) end
        return clampLevel(morale)
    end
    g.morale = bury(g, deadA, moraleA)
    t.morale = bury(t, deadD, moraleD)
    log().info("simulation: clash %s attacks %s, attacker %s, losses %s/%s", gid, tid, outcomeA,
        tostring(#deadA), tostring(#deadD))
    return { target = tid, won = won, deadA = deadA, deadD = deadD, woundedA = woundedA, woundedD = woundedD,
        deltaA = deltaA, deltaD = deltaD, place = place }
end

-- Applique l'événement kind au groupe gid (tirages rnd). Rend son bilan, ou nil (rien n'est arrivé : aucun membre
-- possible, aucune recrue tirée, aucune cible). targets : cibles d'un combat (Simulation.clashTargets).
function Simulation.applyEvent(data, gid, kind, s, rnd, day, targets)
    local g = data.groups[gid]
    local e = s[kind]
    if not g or not e then return nil end
    if kind == "departure" then return eventDeparture(g, gid, e, rnd, day) end
    if kind == "recruit" then return eventRecruit(g, gid, e, rnd, day) end
    if kind == "conflict" then return eventConflict(g, e, rnd, day) end
    if kind == "illness" then return eventIllness(g, e, rnd, day) end
    if kind == "clash" and targets and #targets > 0 then
        return eventClash(data, gid, g, pick(targets, rnd), e, rnd, day)
    end
    return nil
end

-- Tirage quotidien des événements (heure hour, dont l'heure du jour vaut s.hour) : groupes dans l'ordre ids, un flux
-- par groupe (EVENT_SALT) ; un groupe qui a eu un événement ce jour (y compris comme cible d'un combat) n'en tire
-- plus. Un groupe matérialisé (LK09-T03 : membre incarné) ne tire rien et n'est la cible d'aucun combat. Rend la
-- liste { { group, kind } } des événements arrivés.
function Simulation.runEvents(data, ids, hour, base, s, bases)
    local day = math.floor(hour / 24) + 1
    local done, out = {}, {}
    for _, gid in ipairs(ids) do
        if not done[gid] and data.groups[gid] and not Simulation.materialized(data.groups[gid]) then
            local chances, targets = Simulation.eventChances(data, ids, gid, s, bases, done)
            local rnd = Simulation.stream(base, Groups().idNumber(gid) or 0, hour, Simulation.EVENT_SALT)
            local kind = Simulation.drawEvent(chances, s.maxDaily, rnd)
            local result = kind and Simulation.applyEvent(data, gid, kind, s, rnd, day, targets)
            if result then
                done[gid] = true
                if result.target then done[result.target] = true end
                out[#out + 1] = { group = gid, kind = kind }
                log().debug("simulation: group %s event %s at hour %s", gid, kind, tostring(hour))
            end
        end
    end
    return out
end

-- Bases connues pour les combats (RS_Rescue.knownBases : refuges, joueurs connectés ou locaux), lues une fois par pas.
function Simulation.knownBases()
    local Rescue = require "RadioSurvivor/RS_Rescue"
    if type(Rescue) ~= "table" or not Rescue.knownBases then return nil end
    return Rescue.knownBases({})
end

-- Avance un registre (logique pure, sans sauvegarde) jusqu'à l'heure now. Rend changed, nombre d'heures simulées.
-- bases : bases connues des joueurs (rectangles { x1, y1, x2, y2 }) pour les combats ; nil = inconnues, aucun combat.
-- afterHour(g, gid, hour) (facultatif) : appelé après chaque heure simulée de chaque groupe (LK05-T06 : besoins
-- individuels avancés avec la tâche et l'expédition de cette heure, que les heures passent une par une ou en
-- rattrapage).
function Simulation.advance(data, now, bases, afterHour)
    local st = Simulation.state
    local last = data.simHour
    if last == nil then
        data.simHour = now
        log().info("simulation: starts at world hour %s (no catch-up)", tostring(now))
        return true, 0
    end
    if now < last then
        if not st.waiting then
            st.waiting = true
            log().warn("simulation: game clock (hour %s) is behind the last simulated hour %s (world older than "
                .. "the group file): waiting", tostring(now), tostring(last))
        end
        return false, 0
    end
    st.waiting = false
    local missing = now - last
    if missing == 0 then return false, 0 end
    local cap = cfg().MAX_CATCHUP_HOURS
    if type(cap) ~= "number" or cap ~= cap or cap < 0 then cap = 0 end
    cap = math.floor(cap)
    local from = last + 1
    if missing > cap then
        from = now - cap + 1
        log().warn("simulation: %s hour(s) missed, %s simulated, %s skipped", tostring(missing), tostring(cap),
            tostring(missing - cap))
    end
    local base = Simulation.baseSeed()
    local exp = Simulation.expeditionSettings()
    local events = Simulation.eventSettings()
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids, function(a, b) return (Groups().idNumber(a) or 0) < (Groups().idNumber(b) or 0) end)
    local Stock = LivingKnox.Stock   -- LK09-T06 : repas abstrait pris dans le stock de référence (écarts en attente)
    local Relations = LivingKnox.Relations   -- LK11-T05 : vengeance (serment, départ, traque) avant l'heure du groupe
    for hour = from, now do
        Groups().hourContext = hour   -- LK10-T02 : heure simulée des entrées du journal de récit (LK_Journal)
        for _, gid in ipairs(ids) do
            if Relations ~= nil and Relations.offscreenHour ~= nil then
                Relations.offscreenHour(data.groups[gid], gid, hour)
            end
            local Raids = LivingKnox.Raids   -- LK11-T07 : raid (éclaireurs, annonce, attaque), après la vengeance
            if Raids ~= nil and Raids.offscreenHour ~= nil then Raids.offscreenHour(data, data.groups[gid], gid, hour) end
            Simulation.simulateHour(data.groups[gid], gid, hour, base, exp)
            if afterHour ~= nil then afterHour(data.groups[gid], gid, hour) end
            if Stock ~= nil and Stock.offscreenHour ~= nil then
                Stock.offscreenHour(data.groups[gid], gid, hour, math.floor(hour / 24) + 1)
            end
            local Fortify = LivingKnox.Fortify   -- LK14-T05 : chantiers avancés hors écran (matériaux du stock)
            if Fortify ~= nil and Fortify.offscreenHour ~= nil then Fortify.offscreenHour(data.groups[gid], gid, hour) end
        end
        -- Événements du jour (LK09-T05), après les règles horaires de tous les groupes, à l'heure EVENTS.HOUR.
        if events and (hour + 6) % 24 == events.hour then
            Simulation.runEvents(data, ids, hour, base, events, bases)
        end
    end
    Groups().hourContext = nil
    data.simHour = now
    local count = now - from + 1
    if count > 1 then
        log().info("simulation: caught up %s hour(s) for %s group(s), now at hour %s", tostring(count),
            tostring(#ids), tostring(now))
    end
    return true, count
end

-- Heure de jeu courante (entier, âge du monde), ou nil si l'horloge manque.
function Simulation.currentHour()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= "number" or hours ~= hours or hours < 0 then return nil end
    return math.floor(hours)
end

-- Pas de simulation jusqu'à l'heure now (défaut : heure courante), une seule sauvegarde. Rend le nombre d'heures
-- simulées, ou nil et une raison. Moteur désactivé (option LivingKnox.Enabled) : rien, les heures s'accumulent et
-- seront rattrapées (bornées) à la réactivation.
function Simulation.step(now)
    if not LivingKnox.Config.isEnabled() then return 0 end
    now = now or Simulation.currentHour()
    if now == nil then return nil, "no game clock" end
    local bases = Simulation.knownBases()
    local Needs = LivingKnox.Needs
    local afterHour = Needs ~= nil and Needs.advanceGroup or nil
    return Groups().update(function(data) return Simulation.advance(data, now, bases, afterHour) end)
end

-- hour : heure de jeu lue à l'EveryHours (LK13-T09, file du pas horaire) ; nil = heure courante.
function Simulation.onEveryHours(hour)
    Simulation.step(hour)
end

-- Démarrage : rattrapage si le registre a été relu (OnInitGlobalModData part avant OnServerStarted / OnGameStart) ;
-- sinon rien ici, le prochain EveryHours le chargera (Groups.ensure) et rattrapera.
function Simulation.onStart()
    if not Groups().isReady() then return end
    Simulation.step()
end

-- ================================================================ pas horaire étalé (LK13-T09)
-- Fiche : docs/conception/charge.md, « Pas horaire étalé ». Abonnés EveryHours de LK_Server, dans l'ordre de
-- l'événement :
--   - population, simulation, besoins : dans l'image de l'EveryHours (Simulation.runNow). Ils avancent les jauges des
--     membres (LK_Needs) que les comportements des membres incarnés modifient en place à chaque image (peur montée,
--     repas réels) avec des bornes 0..100 : les décaler d'une image changerait l'ordre de ces écritures, donc les
--     jauges (mesuré au banc de charge : un groupe incarné diverge en trois heures). Peu coûteux (logique pure) ;
--   - notation des objectifs (LK_Decisions) et déclin des attitudes : rangés dans une file (Simulation.defer) avec
--     l'heure de jeu lue à ce moment ; une passe par image à partir de l'image SUIVANTE (OnTick ; l'EveryHours du jeu
--     part dans GameTime.update, avant l'OnTick de la même image : marque « fresh » effacée au début de l'image
--     suivante, OnTickEvenPaused), puis une image pour l'écriture seule.
-- L'écriture du registre des groupes est retenue de l'EveryHours à la fin de la file (Groups.hold, bornée à
-- HOLD_FRAMES débuts d'image) : une seule écriture pour tout le pas, comme avant, dans une image à elle.
-- Mêmes passes, même ordre, même heure : même registre et même journal (banc tests/test_lk_spread.py, banc léger et
-- banc de charge complet sur une journée). Une heure nouvelle alors que la file n'est pas vide (accéléré du temps en
-- solo, banc qui déclenche EveryHours sans image) : les passes restantes de l'heure précédente partent aussitôt, dans
-- l'ordre, avant celles de la nouvelle heure (seul Raids.survey, abonné avant, passe alors devant). Une erreur dans
-- une passe de la file est journalisée et n'arrête pas les suivantes (comme des abonnés distincts d'un même
-- événement). Simulation.finishHour() vide la file tout de suite (bancs, OnSave).
Simulation.SPREAD = Simulation.SPREAD or { HOLD_FRAMES = 12 }
Simulation.hourly = Simulation.hourly or { jobs = {}, head = 1, hour = nil, fresh = false, write = false }
Simulation.spreadStats = Simulation.spreadStats or { chains = 0, jobs = 0, flushedEarly = 0, errors = 0 }

local function pendingJobs(q) return q.head <= #q.jobs end

local function runJob(job)
    local ok, err = pcall(job.fn, job.hour)
    Simulation.spreadStats.jobs = Simulation.spreadStats.jobs + 1
    if not ok then
        Simulation.spreadStats.errors = Simulation.spreadStats.errors + 1
        log().error("simulation: hourly pass %s failed: %s", tostring(job.name), tostring(err))
    end
end

-- Range une passe horaire fn(hour) dans la file (abonné EveryHours de LK_Server). name : nom pour le journal.
function Simulation.defer(name, fn)
    local q = Simulation.hourly
    local hour = Simulation.currentHour()
    if pendingJobs(q) and q.hour ~= hour then
        Simulation.spreadStats.flushedEarly = Simulation.spreadStats.flushedEarly + 1
        Simulation.finishHour()
    end
    if not pendingJobs(q) then
        q.jobs, q.head, q.hour = {}, 1, hour
        Simulation.spreadStats.chains = Simulation.spreadStats.chains + 1
    end
    q.jobs[#q.jobs + 1] = { name = name, fn = fn, hour = hour }
    q.fresh, q.write = true, true
    Groups().hold("hour", Simulation.SPREAD.HOLD_FRAMES)
end

-- Passe horaire fn(hour) tout de suite, dans l'image de l'EveryHours (abonné de LK_Server), après les passes restées
-- en file d'une heure précédente ; écriture retenue jusqu'à la fin de la file de cette heure.
function Simulation.runNow(name, fn)
    local q = Simulation.hourly
    local hour = Simulation.currentHour()
    if pendingJobs(q) and q.hour ~= hour then
        Simulation.spreadStats.flushedEarly = Simulation.spreadStats.flushedEarly + 1
        Simulation.finishHour()
    end
    q.fresh, q.write = true, true
    Groups().hold("hour", Simulation.SPREAD.HOLD_FRAMES)
    return fn(hour)
end

-- Vrai si des passes horaires attendent leur image.
function Simulation.hourPending()
    local q = Simulation.hourly
    return pendingJobs(q) or q.write
end

-- Passes restantes tout de suite, dans l'ordre ; écriture rendue à la fin de l'image (Groups.release).
function Simulation.finishHour()
    local q = Simulation.hourly
    while pendingJobs(q) do
        local job = q.jobs[q.head]
        q.head = q.head + 1
        runJob(job)
    end
    q.jobs, q.head, q.write, q.fresh = {}, 1, false, false
    Groups().release("hour")
    local D = LivingKnox.Decisions   -- LK13-T11 : notations de l'heure étalées par LK_Decisions, faites aussi
    if D ~= nil and D.finishHourQueue ~= nil then D.finishHourQueue() end
end

-- Début de l'image (OnTickEvenPaused) : les passes rangées pendant l'image précédente peuvent partir.
function Simulation.onFrameStart()
    Simulation.hourly.fresh = false
end

-- Image (OnTick) : une passe ; la file vide, une image de plus pour l'écriture seule.
function Simulation.onFrame()
    local q = Simulation.hourly
    if q.fresh then return end
    if pendingJobs(q) then
        local job = q.jobs[q.head]
        q.head = q.head + 1
        runJob(job)
        return
    end
    if q.write then
        q.write = false
        q.jobs, q.head = {}, 1
        local G = Groups()
        G.release("hour")
        if G.isDirty() and not G.isHeld() then G.flush() end   -- une autre retenue (LK_Stock) écrira à sa fin
    end
end

return Simulation
