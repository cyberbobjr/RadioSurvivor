if isClient() then return end
--[[
Survivants à secourir (E12-T01) : choix du bâtiment par la métagrille, sans charger aucune case, et indices
descriptifs sans coordonnées. Autorité seulement (serveur dédié ou solo). Détails : docs/specifications-techniques/rescue.md.

    local Rescue = require "RadioSurvivor/RS_Rescue"
    local site, reason = Rescue.pick({ seed = 42, minDistance = 600, avoid = { { x = 100, y = 200 } } })
    -- site = { x, y, z, buildingId, key, kind, label, bounds = { x1, y1, x2, y2 }, attempts, clues = { ... } }

Tirage : un index au hasard dans getWorld():getMetaGrid():getBuildings() (tous les BuildingDef de la carte après
fusion des dossiers), au plus CONFIG.MAX_ATTEMPTS fois ; chaque essai lit seulement le BuildingDef et ses RoomDef
(noms, niveaux, rectangles), la zone de la métagrille au point choisi et les bases connues : aucun getGridSquare,
LoadChunk, getChunk ni getBuildingAt(x, y) (qui parcourt toute la liste). Graine (opts.seed, nombre ou chaîne) :
tirage Park-Miller reproductible pour une même carte et les mêmes mods ; sans graine, ZombRand.

Habitable : premier type de Rescue.KINDS dont les pièces correspondent (église, école, poste de police, caserne,
hôpital, clinique, motel, ferme, immeuble, maison avec garage, maison) ; ni bâtiment de joueur (isUserDefined), ni
sous-sol seul, ni surface sous CONFIG.MIN_AREA.
Base connue : refuges vanilla (SafeHouse.getSafehouseList), position des joueurs connectés (serveur) ou locaux
(solo), points ou rectangles donnés par l'appelant (opts.avoid). Ne couvre pas : joueurs hors ligne, constructions
sans refuge déclaré, véhicules garés, cachettes. Distance = écart entre le rectangle du bâtiment et la base.
Terre ferme : un bâtiment de carte est posé sur des cases de sol ; le point retenu est le centre d'un rectangle de
pièce, et une zone « Water » de la métagrille à ce point (cellules déjà approchées seulement) écarte le bâtiment.

Indices (Rescue.clues) : en anglais, destinés au prompt du pont, sans aucun chiffre : type, taille et étages du
bâtiment, repères voisins tirés des bâtiments proches de la métagrille (IsoMetaCell:getBuildingsIntersecting des
seules cellules utiles) avec une direction et une distance en mots, ville la plus proche si la carte vanilla est
chargée (getLotDirectories, centres des annotations vanilla). Rien n'est envoyé au pont ici, rien n'est écrit en
ModData. Le site rendu ne contient que des valeurs simples (sérialisables), jamais d'objet Java.
Seul l'ASCII est utilisé dans les chaînes (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).

Secours en cours (E12-T02) : réserves, délai et équipe, dans l'état privé (RS_State : S.data.rescues, fichier
serveur, jamais en ModData globale). Le délai annoncé en jours de jeu EST la réserve : reserves (heures de jeu,
flottant) = jours x 24 au départ (jours : opts.days, sinon l'option sandbox RescueDays, E12-T06) ; une livraison
(E12-T03, Rescue.addReserves) la fait remonter ; à zéro, l'issue est « missed » (trop tard). Décompte : à chaque
sondage (POLL_MS réelles, OnTickEvenPaused, et chaque EveryHours),
l'écart de getWorldAgeHours depuis le sondage précédent est retiré des réserves actives seulement si au moins un
joueur est connecté (getOnlinePlayers sur un serveur, joueurs locaux en solo) ; sinon le temps passe sans rien
retirer et n'est jamais rattrapé (serveur vide sans PauseEmpty). Le premier sondage d'une session ne retire rien.
Équipe : RS_Factions.idOf (faction vanilla ou joueur seul, E09-T03) ; un seul secours actif par équipe (refus
« team_busy »), bâtiments distincts entre les secours actifs ou dont la scène reste à poser.
    local id, why = Rescue.start(player, { days = 3, requester = "Darlene" })   -- ou startForTeam(teamId, opts)
    Rescue.activeFor(teamId) / Rescue.get(id) / Rescue.list()  -> copies (daysLeft, hoursLeft)
    Rescue.addReserves(id, hours)                 -- E12-T03 : dépôt réel constaté par l'appelant
    Rescue.noteApproach(id, info)                 -- E12-T03 : approche d'un membre de l'équipe (RS_RescueVisit)
Livraison sur place et approche (E12-T03) : RS_RescueVisit.lua (lectures de cases, hors de ce fichier qui n'en fait
aucune) ; opts.site de startForTeam impose un site déjà examiné (suites en jeu).
    Rescue.finish(id, "saved" | "missed" | "abandoned", { participants = { noms } })   -- E12-T04 / T05
    Rescue.onOutcome = function(rescue, result) end                -- écouteur unique facultatif (copie)
    Rescue.pendingScenes() / Rescue.scenePlaced(id)                 -- scènes « à temps » / « trop tard »
Fait du jour (RS_Facts, global RS_Facts s'il est chargé) : 'rescue' { result, requester, participants, place
arrondie à la ville } à l'issue saved ou missed.
Issue « à temps » (E12-T04) : RS_RescueVisit note les aidants après un dépôt réel (Rescue.noteHelpers : rec.helped,
rec.helpers = { name, caller, cid }) et clôt « saved » quand plus aucun membre n'est près du bâtiment ; les noms des
aidants deviennent les participants par défaut. Rescue.sceneHook(rec, result) (RS_RescueScene, enregistrement
interne : le secours réel, pas une copie) prépare la scène à l'issue saved ou missed. Rescue.isWorkStore() : magasin
de travail actif (suites en jeu).
Issue « trop tard » (E12-T05) : au départ, rec.survivors (Rescue.drawSurvivors : 2 ou 3 tenues vanilla distinctes de
Rescue.OUTFITS, le premier est le demandeur) et rec.looks (Rescue.looks : phrases anglaises que la voix dira) ; à
l'issue missed, RS_RescueLost (enveloppe de Rescue.sceneHook) en fait des zombies en tenue (E12-T07), le
demandeur porte les dernières pages.
]]
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local S = require "RadioSurvivor/RS_State"
local Factions = require "RadioSurvivor/RS_Factions"

local Sites = require "RadioSurvivorCore/RC_Sites"

-- E18-T05 : tirage des bâtiments et indices dans le mod commun (RC_Sites), partagés avec les gabarits de missions ;
-- mêmes tables et mêmes fonctions sous les noms historiques (Rescue.pick, Rescue.check, Rescue.KINDS...).
local Rescue = {}
for k, v in pairs(Sites) do Rescue[k] = v end
local drawer, townData = Sites.drawer, Sites.town

local function log(msg)
    Const.log("rescue: " .. msg)
end

-- Secours en cours : réserves, délai et équipe (E12-T02) ---------------------------------------------------------

Rescue.RUN = {
    -- délai par défaut (jours de jeu de réserves au départ) : option sandbox RadioSurvivor.RescueDays (E12-T06,
    -- Const.rescueDays, défaut 3), lue au lancement de chaque secours ; opts.days l'emporte (bancs, suites en jeu).
    MIN_DAYS = 1,
    MAX_DAYS = 10,
    MAX_RESERVE_DAYS = 10, -- plafond des réserves après livraisons
    POLL_MS = 1000,        -- sondage du décompte (temps réel)
    MAX_CLOSED = 16,       -- secours clos gardés (scènes à poser d'abord)
    MAX_NAME = 48,
    MAX_HELPERS = 8,       -- aidants gardés par secours (E12-T04)
}
Rescue.RESULTS = { saved = true, missed = true, abandoned = true }

local session = { age = nil, pollAt = 0 }
local storeOverride = nil

-- Suites en jeu et bancs : un magasin de secours de travail à la place de l'état privé (nil : retour à l'état).
function Rescue.useStore(d)
    storeOverride = d
    session.age = nil
end

function Rescue.newStore()
    return { seq = 0, active = {}, rescues = {} }
end

-- Magasin de travail actif (suites en jeu) : les effets durables hors du secours (faits, relevés de vie) sont omis.
function Rescue.isWorkStore()
    return storeOverride ~= nil
end

local function store()
    if storeOverride then return storeOverride end
    if not S.data or S.blocked then return nil end
    local d = S.data.rescues
    if type(d) ~= "table" or type(d.active) ~= "table" or type(d.rescues) ~= "table" then
        d = Rescue.newStore()
        S.data.rescues = d
    end
    return d
end
Rescue.store = store

local function dirty()
    if not storeOverride then S.dirty = true end
end

local function worldAge()
    local gt = getGameTime and getGameTime()
    if not gt or not gt.getWorldAgeHours then return nil end
    local age = gt:getWorldAgeHours()
    if type(age) ~= "number" or age ~= age or age < 0 then return nil end
    return age
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function view(rec)
    local out = copy(rec)
    out.hoursLeft = math.floor(rec.reserves or 0)
    out.daysLeft = math.ceil((rec.reserves or 0) / 24)
    return out
end

local function activeRec(d, team)
    local id = d.active[team]
    local rec = id and d.rescues[id]
    if rec and rec.state == "active" then return rec end
    if id then d.active[team] = nil end
    return nil
end

local function cleanName(value)
    if type(value) ~= "string" then return nil end
    local text = Const.oneLine(string.gsub(value, "%c", " "))
    if text == "" then return nil end
    return string.sub(text, 1, Rescue.RUN.MAX_NAME)
end

-- Au moins un joueur connecté : liste du serveur, joueurs locaux en solo.
function Rescue.connected()
    if isServer() then
        local list = getOnlinePlayers and getOnlinePlayers()
        return list ~= nil and list:size() > 0
    end
    return getNumActivePlayers ~= nil and getNumActivePlayers() > 0
end

-- Survivants du groupe (E12-T05) : tenues vanilla qu'ils décrivent à la radio, portées par leurs zombies si
-- l'aide arrive trop tard (RS_RescueLost). Liste fermée de tenues présentes pour les deux sexes dans
-- media/clothing/clothing.xml 42.21 (PersistentOutfits.pickOutfit rend 0 pour un sexe absent), hors Bandit et
-- Survivalist* (remplacées par ZombiesStageDefinitions.getAdvancedOutfitName) ; look = pièce toujours portée
-- (probabilité 1 dans la tenue), en anglais, sans chiffre (donnée du prompt comme les indices).
Rescue.SURVIVORS = { MIN = 2, MAX = 3 }
Rescue.OUTFITS = {
    { outfit = "Doctor", look = "a long white doctor's coat" },
    { outfit = "Nurse", look = "hospital scrubs" },
    { outfit = "HospitalPatient", look = "a hospital gown" },
    { outfit = "Fireman", look = "firefighter's trousers" },
    { outfit = "Police", look = "a police uniform" },
    { outfit = "Ranger", look = "a park ranger's uniform" },
    { outfit = "Chef", look = "chef's checked trousers" },
    { outfit = "Fossoil", look = "a Fossoil gas station T-shirt" },
    { outfit = "Sanitation", look = "a blue and red boiler suit" },
    { outfit = "Ski", look = "padded ski trousers" },
}

-- Survivants d'un secours : MIN à MAX, tenues distinctes tirées par l'identifiant et le site (même tirage après un
-- redémarrage) ; le premier est le demandeur (la voix). Liste de { outfit, look, requester }.
function Rescue.drawSurvivors(rec)
    local draw = drawer(tostring(rec.id) .. "|" .. tostring(rec.site and rec.site.key) .. "|survivors")
    local n = Rescue.SURVIVORS.MIN + draw(Rescue.SURVIVORS.MAX - Rescue.SURVIVORS.MIN + 1)
    local pool = {}
    for i, o in ipairs(Rescue.OUTFITS) do pool[i] = o end
    local out = {}
    for i = 1, math.min(n, #pool) do
        local o = table.remove(pool, draw(#pool) + 1)
        out[i] = { outfit = o.outfit, look = o.look, requester = i == 1 or nil }
    end
    return out
end

-- Description des tenues pour la voix (phrases anglaises sans chiffre, données du prompt comme les indices).
function Rescue.looks(survivors)
    local out = {}
    for _, s in ipairs(type(survivors) == "table" and survivors or {}) do
        if s.requester then out[#out + 1] = "I am wearing " .. s.look .. "."
        else out[#out + 1] = "One of the others is wearing " .. s.look .. "." end
    end
    return out
end

-- Démarre le secours d'une équipe (identifiant 'fac-<n>' de RS_Factions). opts (facultatifs) : days, requester
-- (nom de la voix), voice (identifiant), seed, minDistance, avoid, maxAttempts. Rend id et la copie du secours, ou
-- nil, la raison ('state', 'bad_team', 'team_busy' + id du secours actif, 'no_site' + raison du tirage).
function Rescue.startForTeam(team, opts)
    opts = opts or {}
    if type(team) ~= "string" or team == "" then return nil, "bad_team" end
    local d = store()
    if not d then return nil, "state" end
    local current = activeRec(d, team)
    if current then
        log("refused a second rescue for team " .. team .. ": " .. current.id .. " is still running")
        return nil, "team_busy", current.id
    end
    local days = math.floor(tonumber(opts.days) or Const.rescueDays())
    days = math.max(Rescue.RUN.MIN_DAYS, math.min(Rescue.RUN.MAX_DAYS, days))
    local exclude = {}
    for k, v in pairs(opts.exclude or {}) do exclude[k] = v end
    for _, rec in pairs(d.rescues) do
        if rec.state == "active" or rec.scene == "pending" then exclude[rec.site.key] = true end
    end
    local site, why = opts.site, nil
    if type(site) == "table" then -- E12-T03 : site imposé (suites en jeu : bâtiment du joueur de test)
        if type(site.bounds) ~= "table" or type(site.key) ~= "string" then return nil, "no_site", "bad site" end
        if exclude[site.key] then return nil, "no_site", "excluded" end
    else
        site, why = Rescue.pick({ seed = opts.seed, minDistance = opts.minDistance, avoid = opts.avoid,
            maxAttempts = opts.maxAttempts, exclude = exclude })
    end
    if not site then return nil, "no_site", why end
    d.seq = (d.seq or 0) + 1
    local id = "rsc-" .. string.format("%.0f", d.seq)
    local rec = {
        id = id, team = team, state = "active", days = days, reserves = days * 24, consumed = 0, delivered = 0,
        startedAt = worldAge(), requester = cleanName(opts.requester), voice = cleanName(opts.voice),
        site = { x = site.x, y = site.y, z = site.z, key = site.key, buildingId = site.buildingId, kind = site.kind,
                 label = site.label, bounds = copy(site.bounds) },
        clues = copy(site.clues or {}), clueData = copy(site.clueData or {}),
    }
    rec.survivors = Rescue.drawSurvivors(rec)
    rec.looks = Rescue.looks(rec.survivors)
    d.rescues[id], d.active[team] = rec, id
    dirty()
    log(id .. " started for team " .. team .. ": a " .. site.kind .. " (" .. site.key .. "), " .. days .. " day(s)")
    return id, view(rec)
end

-- Secours de l'équipe du joueur (faction vanilla ou joueur seul).
function Rescue.start(player, opts)
    local team = player and Factions.idOf(player)
    if not team then return nil, "state" end
    return Rescue.startForTeam(team, opts)
end

-- Identifiant d'équipe d'un joueur (RS_Factions), pour les appelants.
function Rescue.teamOf(player)
    return player and Factions.idOf(player) or nil
end

function Rescue.get(id)
    local d = store()
    local rec = d and d.rescues[id]
    return rec and view(rec) or nil
end

function Rescue.activeFor(team)
    local d = store()
    local rec = d and type(team) == "string" and activeRec(d, team)
    return rec and view(rec) or nil
end

-- Copies de tous les secours (actifs et clos), par numéro.
function Rescue.list()
    local d = store()
    local out = {}
    if not d then return out end
    for _, rec in pairs(d.rescues) do out[#out + 1] = view(rec) end
    table.sort(out, function(a, b) return (tonumber(string.sub(a.id, 5)) or 0) < (tonumber(string.sub(b.id, 5)) or 0) end)
    return out
end

local function seqOf(rec)
    return tonumber(string.sub(rec.id, 5)) or 0
end

local function pruneClosed(d)
    local closed = {}
    for _, rec in pairs(d.rescues) do
        if rec.state ~= "active" then closed[#closed + 1] = rec end
    end
    if #closed <= Rescue.RUN.MAX_CLOSED then return end
    -- Les scènes à poser partent en dernier, puis le plus ancien d'abord.
    table.sort(closed, function(a, b)
        local pa, pb = a.scene == "pending" and 1 or 0, b.scene == "pending" and 1 or 0
        if pa ~= pb then return pa < pb end
        return seqOf(a) < seqOf(b)
    end)
    for i = 1, #closed - Rescue.RUN.MAX_CLOSED do d.rescues[closed[i].id] = nil end
end

-- Noms des aidants notés (E12-T04), ou nil s'il n'y en a pas.
local function helperNames(rec)
    if type(rec.helpers) ~= "table" or #rec.helpers == 0 then return nil end
    local out = {}
    for _, h in ipairs(rec.helpers) do out[#out + 1] = h.name end
    return out
end

-- Issue d'un secours actif (E12-T04 « saved », E12-T05 « missed » ou décompte à zéro, « abandoned »). fields
-- (facultatif) : participants = liste de noms de personnages (par défaut : les aidants notés). Rend la copie du
-- secours clos, ou nil et la raison.
function Rescue.finish(id, result, fields)
    if not Rescue.RESULTS[result] then return nil, "bad_result" end
    local d = store()
    if not d then return nil, "state" end
    local rec = d.rescues[id]
    if not rec or rec.state ~= "active" then return nil, "not_active" end
    rec.state, rec.closedAt = result, worldAge()
    if result ~= "abandoned" then rec.scene = "pending" end
    if d.active[rec.team] == id then d.active[rec.team] = nil end
    dirty()
    log(id .. " of team " .. rec.team .. " closed: " .. result)
    local participants = type(fields) == "table" and fields.participants or helperNames(rec)
    if result ~= "abandoned" and not storeOverride and type(RS_Facts) == "table" and RS_Facts.record then
        local _, key, town = townData(rec.site.x, rec.site.y)
        RS_Facts.record("rescue", { result = result, requester = rec.requester, participants = participants,
            place = key and { key = key, town = town } or nil }, "rescue|" .. id)
    end
    if result ~= "abandoned" and Rescue.sceneHook then Rescue.sceneHook(rec, result) end
    local out = view(rec)
    pruneClosed(d)
    if Rescue.onOutcome then Rescue.onOutcome(copy(out), result) end
    return out
end

-- Dépôt constaté (E12-T03) : ajoute des heures de réserves, plafonnées. Rend les réserves, ou nil et la raison.
function Rescue.addReserves(id, hours)
    if type(hours) ~= "number" or hours ~= hours or hours <= 0 then return nil, "bad_amount" end
    local d = store()
    if not d then return nil, "state" end
    local rec = d.rescues[id]
    if not rec or rec.state ~= "active" then return nil, "not_active" end
    rec.reserves = math.min(Rescue.RUN.MAX_RESERVE_DAYS * 24, rec.reserves + hours)
    rec.delivered = (rec.delivered or 0) + hours
    dirty()
    return rec.reserves
end

-- Approche constatée (E12-T03, RS_RescueVisit) : info = { at (âge du monde), dir (code de direction), count,
-- vehicle, smoke (nom de couleur ou nil), aired } ; gardée dans le secours (rec.approach, rec.approaches). Rend true.
function Rescue.noteApproach(id, info)
    local d = store()
    local rec = d and d.rescues[id]
    if not rec or rec.state ~= "active" or type(info) ~= "table" then return false end
    rec.approach = { at = tonumber(info.at) or worldAge(), dir = info.dir, count = tonumber(info.count) or 1,
        vehicle = info.vehicle == true, smoke = info.smoke, aired = info.aired == true }
    rec.approaches = (rec.approaches or 0) + 1
    dirty()
    return true
end

-- Aidants (E12-T04, RS_RescueVisit) : membres près du bâtiment une fois un dépôt réel fait. helpers = liste de
-- { name, caller, cid } (nom du personnage, clé d'appelant de la radio, personnage du carnet ou nil) ; gardés dans le
-- secours (rec.helpers, au plus RUN.MAX_HELPERS, une fois par appelant, personnage et nom), rec.helped = true. Rend le
-- nombre d'aidants nouveaux, ou nil si le secours n'est pas actif.
function Rescue.noteHelpers(id, helpers)
    local d = store()
    local rec = d and d.rescues[id]
    if not rec or rec.state ~= "active" then return nil end
    if type(rec.helpers) ~= "table" then rec.helpers = {} end
    local changed, added = not rec.helped, 0
    rec.helped = true
    for _, h in ipairs(type(helpers) == "table" and helpers or {}) do
        local name = type(h) == "table" and cleanName(h.name) or nil
        local caller = type(h) == "table" and cleanName(h.caller) or nil
        local cid = type(h) == "table" and type(h.cid) == "string" and h.cid or nil
        if name and caller and #rec.helpers < Rescue.RUN.MAX_HELPERS then
            local known = false
            for _, k in ipairs(rec.helpers) do
                if k.caller == caller and k.cid == cid and k.name == name then known = true break end
            end
            if not known then
                rec.helpers[#rec.helpers + 1] = { name = name, caller = caller, cid = cid }
                added = added + 1
            end
        end
    end
    if changed or added > 0 then dirty() end
    return added
end

-- Identifiants des secours actifs déjà aidés (dépôt réel fait), triés.
function Rescue.helpedActive()
    local out = {}
    local d = store()
    for id, rec in pairs(d and d.rescues or {}) do
        if rec.state == "active" and rec.helped then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- Retire des heures aux secours actifs (cœur du décompte) ; un secours à zéro est clos « missed ». Rend true si
-- l'état a changé (heure entière de réserves franchie ou issue).
function Rescue.consume(hours)
    local d = store()
    if not d or type(hours) ~= "number" or hours <= 0 then return false end
    local changed, expired = false, {}
    for id, rec in pairs(d.rescues) do
        if rec.state == "active" then
            local before = math.floor(rec.reserves)
            rec.reserves = math.max(0, rec.reserves - hours)
            rec.consumed = (rec.consumed or 0) + hours
            if math.floor(rec.reserves) ~= before then changed = true end
            if rec.reserves <= 0 then expired[#expired + 1] = id end
        end
    end
    if changed then dirty() end
    table.sort(expired)
    for _, id in ipairs(expired) do Rescue.finish(id, "missed") end
    return changed or #expired > 0
end

-- Sondage du décompte (voir l'en-tête). force : ignore l'espacement POLL_MS (EveryHours).
function Rescue.poll(force)
    local now = getTimestampMs()
    if not force and now < session.pollAt then return false end
    session.pollAt = now + Rescue.RUN.POLL_MS
    if not store() then return false end
    local age = worldAge()
    if not age then return false end
    local last = session.age
    session.age = age
    if last == nil or age <= last then return false end
    if not Rescue.connected() then return false end -- serveur vide : réserves figées, aucun rattrapage
    return Rescue.consume(age - last)
end

-- Secours clos dont la scène reste à poser (E12-T04 / T05), par numéro.
function Rescue.pendingScenes()
    local out = {}
    for _, rec in ipairs(Rescue.list()) do
        if rec.scene == "pending" then out[#out + 1] = rec end
    end
    return out
end

function Rescue.scenePlaced(id)
    local d = store()
    local rec = d and d.rescues[id]
    if not rec or rec.scene ~= "pending" then return false end
    rec.scene = "placed"
    dirty()
    return true
end

-- Bancs : oublie l'âge du monde vu en dernier (nouvelle session).
function Rescue.resetSession()
    session = { age = nil, pollAt = 0 }
end

-- Abonnements une seule fois ; le module est relu dans le global RS_Rescue à chaque appel (rechargement Lua).
RS_Rescue = Rescue
if not RS_RescueHooked and Events then
    RS_RescueHooked = true
    if Events.OnTickEvenPaused then Events.OnTickEvenPaused.Add(function() RS_Rescue.poll(false) end) end
    if Events.EveryHours then Events.EveryHours.Add(function() RS_Rescue.poll(true) end) end
end

return Rescue
