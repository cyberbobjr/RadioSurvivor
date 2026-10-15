-- Living Knox : outils d'administration (LK13-T01). Fiche : docs/conception/administration.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
--
-- Commandes réservées aux administrateurs, toutes passées par Admin.request(player, args) sur l'autorité :
--   list   -> état de tous les groupes (vivants, objectif, tâche, foyer exact, marque « disparu » et relève) ;
--   group  -> un groupe en détail : membres (rôle, vivant, PNJ, poste, blessure, incarné), expédition, journal ;
--   relief -> force la relève d'un groupe disparu (LK09-T04) : heure due ramenée à l'heure courante, puis un pas de
--             relève (LivingKnox.Population.reliefStep, même chemin que le pas horaire) ;
--   home   -> déplace le foyer d'un groupe vers une case choisie, contrôlée (entiers, dans la carte de la métagrille,
--             hors refuge de joueur, à HOME_GAP cases au moins du foyer d'un autre groupe, groupe non disparu) ;
--   load   -> mesure de charge de l'autorité (LK13-T02, shared/LivingKnox/LK_Load.lua) : action "start" (windowMs,
--             log), "report" ou "stop" ; réponse { action, running, lines } (rapport anglais, aussi écrit au journal) ;
--   npc    -> fiche d'un PNJ (LK13-T13, client/LivingKnox/LK_NpcSheet.lua) : tout l'état connu de l'autorité (groupe,
--             membre, rôle, profil, chef, besoins, santé et blessure, comportement et règle de la cascade, tâche et
--             geste, vigilance, perception résumée, arme et munitions, position, foyer) ; réponse { npc = vue } ;
--   npcSet -> réglage d'un champ de SHEET_FIELDS (besoins 0..100, santé en % de la santé de naissance, saignement en %
--             de celle-ci par heure, blessure abstraite 0..WOUND_DEATH-1), borné ici, noté au journal du groupe
--             (« ... set by admin <compte> ») ; réponse { npc = vue, field, value = valeur retenue, old }.
--             Le moteur le lit au passage de décision suivant (LK_Decisions.needsOf / healthOf lisent le registre).
--   activity -> panneau de debug des PNJ (LK13-T14, client/LivingKnox/LK_DebugView.lua) : liste de tous les groupes
--             (lignes de list) et, pour gid s'il est donné, l'activité en direct de chaque membre, le journal sauvegardé
--             du groupe et les lignes du journal d'activité en mémoire (LK_Activity.lua) de numéro > after ;
--             réponse { groups, hour, enabled, group = vue ou absent }. Lecture seule, aucune écriture. LK13-T15 :
--             chaque ligne de groupe porte aussi le nom du chef (leaderName), l'alerte en cours (alert = { kind,
--             level }) et la phase de défense (defense) ; chaque membre son nom affiché (name) ;
--   npcRole -> rôle d'un membre changé (LK13-T15) : role pris dans la liste fermée des rôles du type du groupe
--             (Admin.rolesOf), noté au journal du groupe ; réponse { npc = vue, field = "role", value, old } ;
--   npcName -> prénom et nom d'un membre (LK13-T15) : first, last nettoyés par Admin.cleanNamePart (lettres ASCII,
--             espace, apostrophe, point, tiret ; 1..NAME_PART_MAX caractères), rangés dans le membre (firstName,
--             lastName, lus par Admin.ownName et par le carnet : enveloppe Admin.hookNames) ; réponse { npc = vue,
--             field = "name", value, old } ;
--   npcGoto -> téléportation de l'administrateur près d'un PNJ (LK13-T15) : destination choisie ici (case libre
--             voisine du corps, sinon sa case ; hors écran : dernière position connue ; LK13-T16 : sinon case libre
--             voisine du foyer de son groupe, refus « no known position » seulement sans aucune des trois) ; solo :
--             joueur déplacé ici (teleportTo) ; serveur : aucun appel Lua ne déplace un joueur (base
--             multiplayer.md), le client exécute « /teleportto x,y,z » (capacité TeleportToCoordinates revérifiée
--             par le serveur) ; réponse { dest = { x, y, z, src, last }, moved } (src = "body", "last" ou "home") ;
--   homeGoto -> téléportation de l'administrateur au foyer du groupe gid (LK13-T16) : case libre voisine du foyer
--             (sa case hors zone chargée), même chemin que npcGoto ; réponse { dest = { x, y, z, src = "home" }, moved }.
-- LK13-T16 : chaque membre vivant de la vue activity et de la fiche npc porte pos = { x, y, z, src } (Admin.positionOf :
-- corps chargé, sinon dernière position connue du registre, sinon foyer du groupe) ; un membre mort n'en a pas.
-- Carte des groupes : liste des coordonnées exactes dans la réponse list (aucun symbole sur la carte du monde, voir la
-- fiche, section « Carte des groupes »).
-- Contrôle d'accès À CHAQUE requête, côté autorité (Admin.isAllowed) : serveur MP = checkPermissions(joueur,
-- Capability.PopmanManage) (J/Lua/LuaManager.java:2913-2919 -> AntiCheatCapability.validate : rôle de la connexion ;
-- rôles moderator et admin, J/characters/Roles.java) ET getRole():hasCapability (checkPermissions rend vrai sans
-- connexion trouvée), un client MP ne décide jamais ; solo = le joueur local, maître
-- de sa partie. Refus : réponse { ok = false, err = "denied" } sans aucune donnée, ligne WARN (une par joueur et par
-- opération et par REFUSAL_LOG_MS, avec le compte des refus tus).
-- Transport : MP, commande client "adminRequest" (module "LivingKnox") { op, n, gid, x, y, z } -> réponse serveur
-- "adminReply" au seul demandeur ; solo, appel direct de Admin.request par la fenêtre (sendServerCommand ne fait rien
-- hors serveur, base quest-building-blocks.md). n = numéro de requête renvoyé tel quel (réponse périmée ignorée).
-- Écritures : une seule sauvegarde du registre par commande (Groups.update), plus celles du pas de relève ; une entrée
-- de journal « admin » dans le groupe touché (qui, quoi).
-- Constantes lues aussi par un client MP (qui charge media/lua/server mais s'arrête à la garde) : MODULE, CMD_*,
-- CAPABILITY, OPS (la fenêtre client, LK_AdminView.lua, garde ses propres copies, comparées par le banc).
require "LivingKnox/LK_Core"

local Admin = LivingKnox.Admin or {}
LivingKnox.Admin = Admin

Admin.MODULE = "LivingKnox"
Admin.CMD_REQUEST = "adminRequest"
Admin.CMD_REPLY = "adminReply"
Admin.CAPABILITY = "PopmanManage"
Admin.OPS = { list = true, group = true, relief = true, home = true, load = true, npc = true, npcSet = true,
    activity = true, npcRole = true, npcName = true, npcGoto = true, homeGoto = true }
-- LK13-T13 : fiche d'un PNJ (npc) et réglage borné d'un besoin ou de la santé (npcSet). En solo, ces deux opérations
-- exigent aussi le mode debug (isDebugEnabled) ; en MP, la même capacité que le reste de l'outil. LK13-T14 : panneau de
-- debug des PNJ (activity), mêmes droits.
-- LK13-T15 : actions de la fiche et du panneau (rôle, prénom et nom, téléportation), mêmes droits. LK13-T16 :
-- téléportation au foyer d'un groupe (homeGoto), mêmes droits.
Admin.DEBUG_OPS = { npc = true, npcSet = true, activity = true, npcRole = true, npcName = true, npcGoto = true,
    homeGoto = true }
Admin.SHEET_FIELDS = { "hunger", "thirst", "fatigue", "fear", "health", "bleed", "wound" }
Admin.NAME_PART_MAX = 24   -- caractères au plus d'un prénom ou d'un nom saisi (LK13-T15)

-- Prénom ou nom saisi, nettoyé (espaces de tête et de fin retirés, espaces répétés réduits à un) : lettres ASCII,
-- espace, apostrophe, point, tiret, commençant par une lettre, 1..NAME_PART_MAX caractères. Rend le texte, ou nil.
-- Lu aussi par la fiche cliente (contrôle avant envoi) : défini avant la garde du client MP. Le texte n'est jamais
-- interprété : rangé tel quel, affiché par drawText (aucun texte riche).
function Admin.cleanNamePart(s)
    if type(s) ~= "string" or #s > 4 * Admin.NAME_PART_MAX then return nil end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "%s+", " ")
    if #s < 1 or #s > Admin.NAME_PART_MAX then return nil end
    if string.match(s, "^[A-Za-z][A-Za-z' %.%-]*$") == nil then return nil end
    return s
end

if isClient() then return Admin end

require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Population"
require "LivingKnox/LK_Journal"
require "LivingKnox/LK_Load"
require "LivingKnox/LK_Activity"

Admin.CFG = Admin.CFG or {
    HOME_GAP = 25,             -- cases au moins entre le nouveau foyer et le foyer d'un autre groupe (2,5 x RADIUS
                               -- de l'aménagement, LK_Homes : les deux aménagements ne se chevauchent pas)
    REFUSAL_LOG_MS = 60000,    -- une ligne de refus par joueur et par opération au plus par minute réelle
    NAME_MAX = 32,             -- nom de joueur recopié dans le journal du groupe
}

Admin.refusals = Admin.refusals or {}   -- "<joueur>|<op>" -> { ms, muted }
Admin.stats = Admin.stats or { requests = 0, refused = 0, done = 0, failed = 0 }

local CELL = 256

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Population() return LivingKnox.Population end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function count(name)
    Admin.stats[name] = (Admin.stats[name] or 0) + 1
end

-- Nom de compte d'un joueur, réduit à [%w_.-] et NAME_MAX caractères ; "?" sans nom.
function Admin.nameOf(player)
    local name = nil
    if player ~= nil and player.getUsername ~= nil then name = player:getUsername() end
    if type(name) ~= "string" or name == "" then return "?" end
    name = string.gsub(name, "[^%w_%.%-]", "_")
    return string.sub(name, 1, Admin.CFG.NAME_MAX)
end

local function debugOn()
    return isDebugEnabled ~= nil and isDebugEnabled() == true
end

-- Contrôle d'accès (autorité). op facultatif : en solo, une opération de DEBUG_OPS exige le mode debug (LK13-T13).
-- Rend vrai, ou faux et la raison (anglais, journal seulement).
function Admin.isAllowed(player, op)
    if player == nil then return false, "no player" end
    if isClient() then return false, "MP client" end
    if isServer() then
        local cap = Capability ~= nil and Capability[Admin.CAPABILITY] or nil
        if cap == nil then return false, "capability " .. Admin.CAPABILITY .. " unknown" end
        if checkPermissions(player, cap) ~= true then return false, "missing capability " .. Admin.CAPABILITY end
        -- checkPermissions rend vrai si la connexion du joueur est introuvable (LuaManager.java:2916-2919) : rôle du
        -- joueur relu aussi (copié de sa connexion par le serveur, base logs-and-tools.md).
        local role = player.getRole ~= nil and player:getRole() or nil
        if role == nil or role:hasCapability(cap) ~= true then
            return false, "missing capability " .. Admin.CAPABILITY .. " (role)"
        end
        return true
    end
    if op ~= nil and Admin.DEBUG_OPS[op] and not debugOn() then return false, "debug mode off (solo)" end
    return true   -- solo : le joueur local administre sa partie
end

local function now() return getTimestampMs() end

-- Refus journalisé, borné : une ligne par (joueur, opération) et par REFUSAL_LOG_MS ; les refus tus entre-temps sont
-- comptés et rapportés sur la ligne suivante.
local function refuse(player, op, why)
    count("refused")
    local name = Admin.nameOf(player)
    local key = name .. "|" .. tostring(op)
    local r = Admin.refusals[key]
    local t = now()
    if r ~= nil and t - r.ms < Admin.CFG.REFUSAL_LOG_MS then
        r.muted = r.muted + 1
        return
    end
    local muted = r and r.muted or 0
    Admin.refusals[key] = { ms = t, muted = 0 }
    log().warn("admin: request %s refused for %s (%s)%s", tostring(op), name, tostring(why),
        muted > 0 and (", " .. muted .. " more refusal(s) not logged") or "")
end

-- Vues (copies simples, sans objet Java) ------------------------------------------------------------------------

local function embodied(m)
    local S = LivingKnox.Simulation
    return S ~= nil and S.isEmbodied ~= nil and S.isEmbodied(m) == true
end

local function sortedMembers(g)
    local ids = {}
    for mid in pairs(g.members) do ids[#ids + 1] = mid end
    table.sort(ids, function(a, b) return (Groups().memberNumber(a) or 0) < (Groups().memberNumber(b) or 0) end)
    return ids
end

local function homeOf(g)
    if type(g.home) ~= "table" then return nil end
    return { x = g.home.x, y = g.home.y, z = g.home.z }
end

-- Ligne d'état d'un groupe du registre (vivant, lecture seule). hour = heure de jeu courante ou nil.
local function row(g, hour)
    local alive, total, inBody = 0, 0, 0
    for _, m in pairs(g.members) do
        total = total + 1
        if m.alive then
            alive = alive + 1
            if embodied(m) then inBody = inBody + 1 end
        end
    end
    local r = { id = g.id, type = g.type, name = g.name, alive = alive, total = total, embodied = inBody,
        leader = g.leader, objective = g.objective, task = g.task, morale = g.morale, founded = g.founded,
        needs = { food = g.needs.food, medical = g.needs.medical, ammo = g.needs.ammo }, home = homeOf(g) }
    if type(g.gone) == "table" then
        r.gone = { cause = g.gone.cause, day = g.gone.day, hour = g.gone.hour, due = g.gone.due,
            relief = g.gone.relief }
        if hour ~= nil then r.gone.dueIn = g.gone.due - hour end
    end
    if type(g.expedition) == "table" then
        local n = type(g.expedition.team) == "table" and #g.expedition.team or 0
        r.expedition = { place = g.expedition.place, returns = g.expedition.returns, team = n }
    end
    return r
end

-- Groupe que gid a relevé (gone.relief == gid), ou nil.
local function relievedBy(data, gid)
    for id, other in pairs(data.groups) do
        if type(other.gone) == "table" and other.gone.relief == gid then return id end
    end
    return nil
end

local function detail(data, g, hour)
    local r = row(g, hour)
    r.story = g.story
    r.replaces = relievedBy(data, g.id)
    r.members = {}
    for _, mid in ipairs(sortedMembers(g)) do
        local m = g.members[mid]
        r.members[#r.members + 1] = { id = mid, role = m.role, alive = m.alive == true, npc = m.npc, duty = m.duty,
            wound = m.wound or 0, profile = m.profile, embodied = m.alive == true and embodied(m) }
    end
    r.log = {}
    for i = 1, #g.log do
        local e = g.log[i]
        r.log[i] = { day = e.day, kind = e.kind, text = e.text }
    end
    -- LK10-T02 : journal de récit (vues publiques de LK_Journal, texte composé par la fenêtre dans la langue du client).
    local J = LivingKnox.Journal
    r.journal = J ~= nil and (J.view(g)) or {}
    return r
end

-- Opérations (registre prêt, accès déjà vérifié) ------------------------------------------------------------------

local function registry()
    if not Groups().ensure() then return nil end
    return Groups().state.data
end

function Admin.list()
    local data = registry()
    if not data then return nil, "group registry not ready" end
    local hour = Population().currentHour()
    local out = {}
    for _, gid in ipairs(Groups().list()) do out[#out + 1] = row(data.groups[gid], hour) end
    return { groups = out, hour = hour, enabled = LivingKnox.Config.isEnabled() }
end

function Admin.group(gid)
    local data = registry()
    if not data then return nil, "group registry not ready" end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    return { group = detail(data, g, Population().currentHour()) }
end

-- Relève forcée d'un groupe disparu (ou sans plus aucun vivant : le pas de relève le marque d'abord). Rend
-- { relief, created }, ou nil et la raison (relève impossible : nouvel essai prévu par le pas, heure rendue).
function Admin.forceRelief(gid, who)
    local G, P = Groups(), Population()
    if not LivingKnox.Config.isEnabled() then return nil, "engine disabled" end
    local data = registry()
    if not data then return nil, "group registry not ready" end
    local hour = P.currentHour()
    if hour == nil then return nil, "no game clock" end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    if g.gone == nil then
        if G.livingCount(g) > 0 then return nil, "group is not gone (" .. G.livingCount(g) .. " living)" end
        if g.nextMember <= 1 then return nil, "group never had a member" end
        P.reliefStep(hour)   -- constat : marque gone posée (cause wiped)
        g = data.groups[gid]
        if g == nil or g.gone == nil then return nil, "group could not be marked gone" end
    end
    if g.gone.relief ~= nil then return nil, "already relieved by " .. g.gone.relief end
    local ok, err = G.update(function(reg)
        local live = reg.groups[gid]
        live.gone.due = hour
        G.appendLog(live, "admin", "relief forced by " .. who, G.today())
        return true, true
    end)
    if not ok then return nil, err end
    local created, why = P.reliefStep(hour)
    if created == nil then return nil, "relief step: " .. tostring(why) end
    local after = registry().groups[gid]
    if after == nil or after.gone == nil or after.gone.relief == nil then
        return nil, "no relief possible now (see the WARN relief line), next try at hour "
            .. tostring(after and after.gone and after.gone.due)
    end
    log().info("admin: %s forced the relief of %s: %s", who, gid, after.gone.relief)
    return { relief = after.gone.relief, created = created }
end

-- Contrôle d'une case de foyer (sans chargement : métagrille et refuges seulement). Rend vrai, ou faux et la raison.
function Admin.checkHome(gid, x, y, z, data)
    if not isInt(x, 0, Groups().COORD_MAX) or not isInt(y, 0, Groups().COORD_MAX)
        or not isInt(z, Groups().Z_MIN, Groups().Z_MAX) then
        return false, "bad square"
    end
    local world = getWorld and getWorld() or nil
    local grid = world ~= nil and world:getMetaGrid() or nil
    if grid == nil then return false, "no metagrid" end
    if not grid:isValidSquare(x, y) or grid:getCellData(math.floor(x / CELL), math.floor(y / CELL)) == nil then
        return false, "outside the map"
    end
    if SafeHouse ~= nil and SafeHouse.getSafehouseList ~= nil then
        local list = SafeHouse.getSafehouseList()
        for i = 0, (list and list:size() or 0) - 1 do
            local sh = list:get(i)
            local sx, sy = sh:getX(), sh:getY()
            if x >= sx and x < sx + sh:getW() and y >= sy and y < sy + sh:getH() then
                return false, "inside a player safehouse"
            end
        end
    end
    for id, other in pairs(data.groups) do
        if id ~= gid and type(other.home) == "table" then
            local dx, dy = other.home.x - x, other.home.y - y
            if math.sqrt(dx * dx + dy * dy) < Admin.CFG.HOME_GAP then
                return false, "too close to the home of " .. id
            end
        end
    end
    return true
end

-- Déplace le foyer de gid vers (x, y, z). Une sauvegarde ; aménagement, stock et relevé des postes suivent le nouveau
-- foyer d'eux-mêmes (marques périmées, LK_Homes / LK_Stock / LK_Routines). Rend { home, old }, ou nil et la raison.
function Admin.moveHome(gid, x, y, z, who)
    local data = registry()
    if not data then return nil, "group registry not ready" end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    if g.gone ~= nil then return nil, "group " .. gid .. " is gone" end
    local ok, why = Admin.checkHome(gid, x, y, z, data)
    if not ok then return nil, why end
    local old = homeOf(g)
    if old ~= nil and old.x == x and old.y == y and old.z == z then return nil, "home unchanged" end
    local oldText = old and (old.x .. "," .. old.y .. "," .. old.z) or "none"
    local newText = x .. "," .. y .. "," .. z
    local G = Groups()
    local done, err = G.update(function(reg)
        local live = reg.groups[gid]
        live.home = { x = x, y = y, z = z }
        G.appendLog(live, "admin", "home " .. oldText .. " -> " .. newText .. " by " .. who, G.today())
        return true, true
    end)
    if not done then return nil, err end
    log().info("admin: %s moved the home of %s from %s to %s", who, gid, oldText, newText)
    return { home = { x = x, y = y, z = z }, old = old }
end

-- Mesure de charge (LK13-T02) : départ, rapport ou arrêt d'une session LivingKnox.Load sur l'autorité. Rend
-- { action, running, lines }, ou nil et la raison. Rapport et arrêt écrits aussi au journal (lignes "load: ...").
Admin.LOAD_ACTIONS = { start = true, report = true, stop = true }
Admin.LOAD_MAX_LINES = 40

function Admin.load(args, who)
    local L = LivingKnox.Load
    local action = type(args.action) == "string" and args.action or nil
    if L == nil then return nil, "load measure not loaded" end
    if action == nil or not Admin.LOAD_ACTIONS[action] then return nil, "unknown load action" end
    local lines
    if action == "start" then
        local s, why = L.start({ windowMs = args.windowMs, log = args.log == true })
        if s == nil then return nil, why end
        lines = { "measure started on " .. s.side .. " (window " .. s.windowMs .. " ms, log " .. tostring(s.log)
            .. "), from the next tick on" }
        log().info("admin: %s started a load measure (window %s ms)", who, tostring(s.windowMs))
    else
        local sum, why
        if action == "stop" then sum, why = L.stop() else sum, why = L.summary() end
        if sum == nil then return nil, why end
        lines = L.lines(sum)
        log().info("admin: %s %s the load measure", who, action == "stop" and "stopped" or "read")
        for _, line in ipairs(lines) do log().info("load: %s", line) end
    end
    local out = {}
    for i = 1, math.min(#lines, Admin.LOAD_MAX_LINES) do out[i] = lines[i] end
    return { action = action, running = L.active ~= nil, lines = out }
end

-- Fiche d'un PNJ (LK13-T13) ---------------------------------------------------------------------------------------

Admin.SHEET = Admin.SHEET or {
    HEALTH_MIN = 1,        -- % de la santé de naissance au moins (un réglage ne tue jamais : mort par Health.kill)
    PLAYERS_MAX = 8,       -- joueurs perçus recopiés dans la fiche (les plus attentifs d'abord, ordre du résumé)
}

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end
local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Valeurs simples (chaîne, nombre, booléen) d'une table, copiées ; nil sans table.
local function scalars(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if type(k) == "string" and (tv == "string" or tv == "number" or tv == "boolean") then out[k] = v end
    end
    return out
end

local function woundMax()
    local c = LivingKnox.Config.SIMULATION
    local death = c and c.WOUND_DEATH or 100
    return math.max(0, death - 1)
end

local function bleedMaxPct()
    local c = LivingKnox.Config.BLEEDING
    return (c and c.MAX or 0.6) * 100
end

-- Membre vivant d'un PNJ : groupe, membre (tables vivantes du registre), gid, mid ; ou nil et la raison.
local function memberOfNpc(id)
    local data = registry()
    if not data then return nil, "group registry not ready" end
    if type(id) ~= "string" then return nil, "bad npc" end
    local gid, mid = Groups().findNpc(id)
    if gid == nil then return nil, "npc " .. id .. " is not in a group" end
    local g = data.groups[gid]
    local m = g and g.members[mid] or nil
    if m == nil then return nil, "npc " .. id .. " is not in a group" end
    return g, m, gid, mid
end

local function bodyOf(id)
    local B = LivingKnox.Bodies
    if B == nil or B.find == nil then return nil end
    return (B.find(id))
end

-- Position d'un membre m (vivant) du groupe g pour le panneau, la fiche et la téléportation (LK13-T16) : corps chargé
-- (src "body", dixième de case), sinon dernière position vue du registre des PNJ (src "last"), sinon foyer du groupe
-- (src "home") ; nil pour un membre mort ou sans aucune des trois. Copie de valeurs simples ; last = vrai pour la
-- dernière position connue (compatibilité des vues de LK13-T15). Rien de nouveau pour l'outil : list donne déjà les
-- foyers exacts.
function Admin.positionOf(g, m)
    if type(g) ~= "table" or type(m) ~= "table" or m.alive ~= true then return nil end
    if type(m.npc) == "string" then
        local z = bodyOf(m.npc)
        if z ~= nil then
            return { x = round1(z:getX()), y = round1(z:getY()), z = math.floor(z:getZ()), src = "body" }
        end
        local St = LivingKnox.Store
        local reg = St ~= nil and St.isReady() and LivingKnox.Identity.get(St.data(), m.npc) or nil
        local p = reg ~= nil and reg.last or nil
        if type(p) == "table" and finite(p.x) and finite(p.y) and finite(p.z) then
            return { x = p.x, y = p.y, z = p.z, src = "last", last = true }
        end
    end
    local h = g.home
    if type(h) == "table" and finite(h.x) and finite(h.y) and finite(h.z) then
        return { x = h.x, y = h.y, z = h.z, src = "home" }
    end
    return nil
end

local function sensesView(id)
    local S = LivingKnox.Senses
    local p = S ~= nil and S.perceived ~= nil and S.perceived(id) or nil
    if type(p) ~= "table" then return nil end
    local out = { nz = p.nz, seen = p.seen, heard = p.heard, age = p.age, stale = p.stale == true,
        zombies = type(p.z) == "table" and #p.z or 0, players = {} }
    for _, e in ipairs(type(p.p) == "table" and p.p or {}) do
        if #out.players >= Admin.SHEET.PLAYERS_MAX then break end
        out.players[#out.players + 1] = { u = e.u, s = e.s == true, h = e.h == true }
    end
    return out
end

local function weaponView(id, z)
    local E = LivingKnox.Equipment
    local spec = E ~= nil and E.wantedOf ~= nil and E.wantedOf(id) or nil
    if spec == nil then return nil end
    local out = { t = spec.t }
    local A = LivingKnox.Ammo
    local gun = A ~= nil and A.spec ~= nil and (A.spec(spec.t)) or nil
    if gun ~= nil then
        out.max = gun.max
        if z ~= nil then
            local loose, inMags = A.reserveOf(z, gun)
            out.loaded, out.loose, out.inMags = A.loaded(z, spec.t), loose, inMags
        end
    end
    return out
end

-- Rôles possibles pour un membre d'un groupe de type gtype : rôles du type (LK_GroupTypes, roles), dans l'ordre de
-- Config.GROUP_ROLES (liste fermée). Rend une liste neuve (vide pour un type inconnu).
function Admin.rolesOf(gtype)
    local GT = LivingKnox.GroupTypes
    local def = GT ~= nil and GT.peek ~= nil and GT.peek(gtype) or nil
    local out = {}
    if def == nil or type(def.roles) ~= "table" then return out end
    for _, role in ipairs(LivingKnox.Config.GROUP_ROLES) do
        if def.roles[role] ~= nil then out[#out + 1] = role end
    end
    return out
end

-- Nom donné à un membre m par un administrateur (LK13-T15, champs facultatifs firstName et lastName du membre,
-- registre des groupes, schéma 1 inchangé : un registre sans eux se relit tel quel) : « prénom nom », ou nil (aucun,
-- ou mal formé : ignoré).
function Admin.ownName(m)
    if type(m) ~= "table" then return nil end
    local f, l = m.firstName, m.lastName
    if type(f) ~= "string" or type(l) ~= "string" then return nil end
    if Admin.cleanNamePart(f) ~= f or Admin.cleanNamePart(l) ~= l then return nil end
    return f .. " " .. l
end

-- Nom affiché d'un membre m (table du registre) : prénom et nom donnés par un administrateur (Admin.ownName), sinon
-- celui du carnet (RS_LivingKnox.npc : nom du chef de l'histoire, ou nom tiré avec le numéro du PNJ), ou nil.
function Admin.memberDisplayName(m)
    if type(m) ~= "table" then return nil end
    local own = Admin.ownName(m)
    if own ~= nil then return own end
    local P = RS_LivingKnox
    if type(m.npc) ~= "string" or type(P) ~= "table" or type(P.npc) ~= "function" then return nil end
    local r = P.npc(m.npc)
    return r ~= nil and type(r.name) == "string" and r.name or nil
end

-- Fiche du PNJ id (copie de valeurs simples). Rend { npc = vue }, ou nil et la raison.
function Admin.npcView(id)
    local g, m, gid, mid = memberOfNpc(id)
    if g == nil then return nil, m end
    local St = LivingKnox.Store
    local reg = St ~= nil and St.isReady() and LivingKnox.Identity.get(St.data(), id) or nil
    local z = bodyOf(id)
    local v = { id = id, gid = gid, mid = mid, group = g.name, type = g.type, role = m.role, profile = m.profile,
        alive = m.alive == true, leader = g.leader == mid, leaderId = g.leader, duty = m.duty,
        objective = g.objective, task = g.task, home = homeOf(g), state = reg and reg.state or nil,
        embodied = z ~= nil, wound = m.wound or 0, woundMax = woundMax() }
    local N = LivingKnox.Needs
    v.needs = N ~= nil and N.get ~= nil and N.get(gid, mid) or nil
    local De = LivingKnox.Decisions   -- seuils de la cascade (NEED_HIGH), à défaut ceux du pas horaire (ENVY)
    if De ~= nil and De.CFG ~= nil and De.CFG.NEED_HIGH ~= nil then
        v.envy = scalars(De.CFG.NEED_HIGH)
        if De.fearHigh ~= nil then v.envy.fear = De.fearHigh() end   -- LK05-T16 : option AfraidFear
    else
        v.envy = N ~= nil and N.CFG ~= nil and scalars(N.CFG.ENVY) or nil
    end
    local H = LivingKnox.Health
    local h = H ~= nil and H.get ~= nil and H.get(id) or nil
    if h ~= nil then
        v.health = { hp = h.hp, max = h.max, wounds = type(h.wounds) == "table" and #h.wounds or 0,
            bleedPct = round1((h.bleed or 0) * 100) }
        if finite(h.hp) and finite(h.max) and h.max > 0 then v.health.pct = round1(100 * h.hp / h.max) end
        local last = type(h.wounds) == "table" and h.wounds[#h.wounds] or nil
        if last ~= nil then v.health.last = { p = tostring(last.p), d = last.d } end
    end
    v.decision = De ~= nil and De.get ~= nil and scalars(De.get(id)) or nil
    local R = LivingKnox.Routines
    local r = R ~= nil and R.get ~= nil and R.get(id) or nil
    if r ~= nil then v.routine = { key = r.key, kind = r.kind, phase = r.phase } end
    local C = LivingKnox.Combat
    local c = C ~= nil and C.get ~= nil and C.get(id) or nil
    if c ~= nil then v.combat = { k = c.k, u = c.u, phase = c.phase } end
    local An = LivingKnox.Anim
    v.gesture = An ~= nil and An.shownOf ~= nil and An.shownOf(id) or nil
    local S = LivingKnox.Senses
    v.vigilance = S ~= nil and S.vigilanceOf ~= nil and S.vigilanceOf(id) or nil
    v.senses = sensesView(id)
    v.weapon = weaponView(id, z)
    v.pos = Admin.positionOf(g, m)   -- LK13-T16 : corps, dernière position connue ou foyer, avec la source
    v.minute = De ~= nil and De.currentMinute ~= nil and De.currentMinute() or nil
    -- LK13-T15 : rôles possibles (liste fermée du type), nom affiché et ses deux parties (préremplissage de la fiche).
    v.roles = Admin.rolesOf(g.type)
    v.name = Admin.memberDisplayName(m)
    v.named = Admin.ownName(m) ~= nil
    if v.named then
        v.firstName, v.lastName = m.firstName, m.lastName
    elseif type(v.name) == "string" then
        v.firstName = string.match(v.name, "^(%S+)")
        v.lastName = string.match(v.name, "^%S+%s+(.-)%s*$")
    end
    return { npc = v }
end

-- Réglage borné d'un champ de la fiche (field de SHEET_FIELDS, value nombre fini). Rend { npc = vue, field, value,
-- old }, ou nil et la raison. Une entrée de journal « admin » dans le groupe, écrite avec la valeur (besoins,
-- blessure : une écriture du registre des groupes ; santé, saignement : registre des corps puis entrée de journal).
function Admin.npcSet(id, field, value, who)
    local g, m, gid, mid = memberOfNpc(id)
    if g == nil then return nil, m end
    if not m.alive then return nil, "member " .. mid .. " is dead" end
    if not finite(value) then return nil, "bad value" end
    local G, N = Groups(), LivingKnox.Needs
    local isNeed = false
    for _, key in ipairs(N ~= nil and N.GAUGES or {}) do
        if key == field then isNeed = true end
    end
    local old, new, apply
    if isNeed then
        new = math.max(0, math.min(100, math.floor(value + 0.5)))
        local cur = N.get(gid, mid)
        old = cur and cur[field]
        local hour = N.currentHour() or 0
        apply = function(live)
            if not N.valid(live.vitals) then live.vitals = N.fresh(hour) end
            live.vitals[field] = new
        end
    elseif field == "wound" then
        new = math.max(0, math.min(woundMax(), math.floor(value + 0.5)))
        old = m.wound or 0
        apply = function(live)
            if new > 0 then live.wound = new else live.wound = nil end
        end
    elseif field == "health" or field == "bleed" then
        local H = LivingKnox.Health
        local h = H ~= nil and H.get ~= nil and H.get(id) or nil
        if h == nil or bodyOf(id) == nil or not finite(h.max) or h.max <= 0 then return nil, "npc not embodied" end
        local ok, err
        if field == "health" then
            new = round1(math.max(Admin.SHEET.HEALTH_MIN, math.min(100, value)))
            old = round1(100 * h.hp / h.max)
            ok, err = H.setByAdmin(id, h.max * new / 100, nil)
        else
            new = round1(math.max(0, math.min(bleedMaxPct(), value)))
            old = round1((h.bleed or 0) * 100)
            ok, err = H.setByAdmin(id, nil, new / 100)
        end
        if not ok then return nil, err end
    else
        return nil, "unknown field"
    end
    local text = string.format("%s %s (%s) %s -> %s set by admin %s", field, mid, id, tostring(old), tostring(new), who)
    local done, err = G.update(function(reg)
        local live = reg.groups[gid]
        if apply ~= nil then apply(live.members[mid]) end
        G.appendLog(live, "admin", text, G.today())
        return true, true
    end)
    if not done then return nil, err end
    log().info("admin: %s set %s of %s (%s %s) from %s to %s", who, field, id, gid, mid, tostring(old), tostring(new))
    local out = Admin.npcView(id)
    if out == nil then return nil, "npc view unavailable" end
    out.field, out.value, out.old = field, new, old
    return out
end

-- Actions d'administration sur un membre (LK13-T15) ------------------------------------------------------------

-- Écriture d'un membre vivant et de l'entrée « admin » du journal du groupe (une sauvegarde). Rend vrai, ou nil et la
-- raison.
local function writeMember(gid, mid, apply, text)
    local G = Groups()
    return G.update(function(reg)
        local live = reg.groups[gid]
        if apply ~= nil then apply(live.members[mid]) end
        G.appendLog(live, "admin", text, G.today())
        return true, true
    end)
end

local function short(v)
    return string.sub(tostring(v), 1, Admin.NAME_PART_MAX)
end

-- Rôle du membre du PNJ id changé en role (un rôle de Admin.rolesOf(type du groupe)). Le profil (apparence, arme) ne
-- change pas ; le moteur lit le nouveau rôle au passage de décision suivant. Rend { npc = vue, field, value, old }, ou
-- nil et la raison.
function Admin.npcRole(id, role, who)
    local g, m, gid, mid = memberOfNpc(id)
    if g == nil then return nil, m end
    if not m.alive then return nil, "member " .. mid .. " is dead" end
    if type(role) ~= "string" then return nil, "bad role" end
    local allowed = false
    for _, r in ipairs(Admin.rolesOf(g.type)) do
        if r == role then allowed = true end
    end
    if not allowed then return nil, "role " .. short(role) .. " is not a role of type " .. tostring(g.type) end
    local old = m.role
    if old == role then return nil, "role unchanged" end
    local text = string.format("role %s (%s) %s -> %s set by admin %s", mid, id, tostring(old), role, who)
    local done, err = writeMember(gid, mid, function(live) live.role = role end, text)
    if not done then return nil, err end
    log().info("admin: %s set the role of %s (%s %s) from %s to %s", who, id, gid, mid, tostring(old), role)
    local out = Admin.npcView(id)
    if out == nil then return nil, "npc view unavailable" end
    out.field, out.value, out.old = "role", role, old
    return out
end

-- Prénom et nom du membre du PNJ id (textes saisis, nettoyés par cleanNamePart). Rangés dans le membre (firstName,
-- lastName) : le carnet (RS_LivingKnox.npc, enveloppé par Admin.hookNames) et cette fiche les lisent ; le résumé
-- d'histoire déjà composé garde le nom d'origine. Rend { npc = vue, field, value, old }, ou nil et la raison.
function Admin.npcName(id, first, last, who)
    local g, m, gid, mid = memberOfNpc(id)
    if g == nil then return nil, m end
    if not m.alive then return nil, "member " .. mid .. " is dead" end
    local f, l = Admin.cleanNamePart(first), Admin.cleanNamePart(last)
    if f == nil or l == nil then return nil, "bad name" end
    if m.firstName == f and m.lastName == l then return nil, "name unchanged" end
    local old = Admin.memberDisplayName(m) or "?"
    local new = f .. " " .. l
    local text = string.format("name %s (%s) %s -> %s set by admin %s", mid, id, old, new, who)
    local done, err = writeMember(gid, mid, function(live) live.firstName, live.lastName = f, l end, text)
    if not done then return nil, err end
    log().info("admin: %s renamed %s (%s %s) from %s to %s", who, id, gid, mid, old, new)
    local out = Admin.npcView(id)
    if out == nil then return nil, "npc view unavailable" end
    out.field, out.value, out.old = "name", new, old
    return out
end

local NEAR = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

-- Destination près de la case (x, y, lvl) : première case voisine libre (isFree(false) : sol solide sans mur ni
-- meuble plein), sinon la case elle-même (case voisine absente : hors zone chargée, getGridSquare rend nil).
local function beside(x, y, lvl)
    x, y, lvl = math.floor(x), math.floor(y), math.floor(lvl)
    local cell = getCell and getCell() or nil
    for _, d in ipairs(NEAR) do
        local sq = cell ~= nil and cell:getGridSquare(x + d[1], y + d[2], lvl) or nil
        if sq ~= nil and sq.isFree ~= nil and sq:isFree(false) then return x + d[1], y + d[2], lvl end
    end
    return x, y, lvl
end

local SRC_NOTE = { last = " (last known position)", home = " (group home)" }

-- Déplacement de player vers (x, y, z) : solo seulement, par teleportTo (sort du véhicule,
-- IsoGameCharacter.java:15069-15085). Serveur : rien (aucun appel Lua serveur ne déplace un joueur, base
-- multiplayer.md : le client demande « /teleportto »). Rend vrai si le joueur a été déplacé.
local function moveTo(player, x, y, z)
    if isServer() or player == nil or player.teleportTo == nil then return false end
    player:teleportTo(x, y, z)
    return true
end

-- Téléportation de player près du PNJ id (destination décidée ici, Admin.positionOf) : corps chargé -> case libre
-- voisine du corps ; sinon dernière position connue ; sinon case libre voisine du foyer de son groupe (LK13-T16) ;
-- refus « no known position » sans aucune. Solo : déplacé ici ; serveur : seule la destination est rendue, le client
-- la demande par « /teleportto ». Rend { dest = { x, y, z, src, last }, moved }, ou nil et la raison.
function Admin.npcGoto(id, who, player)
    local g, m, gid, mid = memberOfNpc(id)
    if g == nil then return nil, m end
    if not m.alive then return nil, "member " .. mid .. " is dead" end
    local p = Admin.positionOf(g, m)
    if p == nil then return nil, "no known position" end
    local x, y, z
    if p.src == "last" then
        x, y, z = math.floor(p.x), math.floor(p.y), math.floor(p.z)
    else
        x, y, z = beside(p.x, p.y, p.z)
    end
    local where = x .. "," .. y .. "," .. z
    local note = SRC_NOTE[p.src] or ""
    local text = string.format("teleport of admin %s to %s (%s) at %s%s", who, mid, id, where, note)
    local done, err = writeMember(gid, mid, nil, text)
    if not done then return nil, err end
    local moved = moveTo(player, x, y, z)
    log().info("admin: %s teleported to %s (%s %s) at %s%s%s", who, id, gid, mid, where, note,
        moved and "" or " (requested from the client)")
    return { dest = { x = x, y = y, z = z, src = p.src, last = p.src == "last" }, moved = moved }
end

-- Téléportation de player au foyer du groupe gid (LK13-T16, bouton du panneau) : case libre voisine du foyer, notée au
-- journal du groupe. Rend { dest = { x, y, z, src = "home" }, moved }, ou nil et la raison.
function Admin.homeGoto(gid, who, player)
    local data = registry()
    if not data then return nil, "group registry not ready" end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    local h = g.home
    if type(h) ~= "table" or not finite(h.x) or not finite(h.y) or not finite(h.z) then
        return nil, "no known position"
    end
    local x, y, z = beside(h.x, h.y, h.z)
    local where = x .. "," .. y .. "," .. z
    local G = Groups()
    local done, err = G.update(function(reg)
        G.appendLog(reg.groups[gid], "admin", "teleport of admin " .. who .. " to the group home at " .. where, G.today())
        return true, true
    end)
    if not done then return nil, err end
    local moved = moveTo(player, x, y, z)
    log().info("admin: %s teleported to the home of %s at %s%s", who, gid, where,
        moved and "" or " (requested from the client)")
    return { dest = { x = x, y = y, z = z, src = "home", last = false }, moved = moved }
end

-- Nom donné repris par le carnet (LK13-T15) : enveloppes posées une fois sur le fournisseur du carnet
-- (shared/RadioSurvivor/RS_LivingKnox.lua, chargé avant ce fichier) : RS_LivingKnox.npc rend le nom donné (carnet,
-- dernières pages, missions, nom du chef de LK.composition qui l'appelle) et RS_LivingKnox.context le nom du chef
-- donné (contexte du LLM). Le résumé d'histoire déjà composé garde le nom d'origine. Rend vrai si posées.
local function groupMemberOfNpc(id)
    local G = Groups()
    if G == nil or type(id) ~= "string" or not G.ensure() then return nil end
    local gid, mid = G.findNpc(id)
    local g = gid ~= nil and G.state.data.groups[gid] or nil
    if g == nil then return nil end
    return g, g.members[mid]
end

function Admin.hookNames()
    local P = RS_LivingKnox
    if type(P) ~= "table" or type(P.npc) ~= "function" then return false end
    if P.lkAdminNames then return true end   -- rechargement du fichier : enveloppes non empilées
    P.lkAdminNames = true
    local baseNpc, baseContext = P.npc, P.context
    P.npc = function(id)
        local r = baseNpc(id)
        if type(r) == "table" then
            local _, m = groupMemberOfNpc(id)
            local own = Admin.ownName(m)
            if own ~= nil then r.name = own end
        end
        return r
    end
    if type(baseContext) == "function" then
        P.context = function(id, character, language)
            local out = baseContext(id, character, language)
            if type(out) == "table" and out.member then
                local g = groupMemberOfNpc(id)
                local own = g ~= nil and g.leader ~= nil and Admin.ownName(g.members[g.leader]) or nil
                if own ~= nil then out.leaderName = own end
            end
            return out
        end
    end
    return true
end
Admin.hookNames()

-- Panneau de debug des PNJ (LK13-T14) ------------------------------------------------------------------------------

-- Liste de tous les groupes et, si gid est une chaîne, activité du groupe (LivingKnox.Activity.groupView, lignes du
-- journal d'activité de numéro > after). Rend { groups, hour, enabled, group }, ou nil et la raison.
function Admin.activity(gid, after)
    local out, err = Admin.list()
    if out == nil then return nil, err end
    local data = registry()
    -- LK13-T15 : nom du chef, alerte en cours et phase de défense de chaque groupe (lecture seule).
    local Ac, Al, Df = LivingKnox.Activity, LivingKnox.Alert, LivingKnox.Defense
    local minute = Ac ~= nil and Ac.minute ~= nil and Ac.minute() or nil
    for _, r in ipairs(out.groups) do
        local live = data.groups[r.id]
        if live ~= nil and r.leader ~= nil then r.leaderName = Admin.memberDisplayName(live.members[r.leader]) end
        if Al ~= nil and Al.isActive ~= nil and minute ~= nil and Al.isActive(r.id, minute) then
            local a = Al.get(r.id, minute)
            if a ~= nil then r.alert = { kind = a.kind, level = a.level } end
        end
        local plan = Df ~= nil and Df.get ~= nil and Df.get(r.id) or nil
        if plan ~= nil then r.defense = plan.phase end
    end
    if gid == nil then return out end
    local g = type(gid) == "string" and data.groups[gid] or nil
    if not g then return nil, "unknown group " .. tostring(gid) end
    if Ac == nil or Ac.groupView == nil then return nil, "activity log not loaded" end
    out.group = Ac.groupView(gid, g, isInt(after, 0, 2147483647) and after or 0)
    for _, mv in ipairs(out.group.members or {}) do
        local m = g.members[mv.id]
        mv.name = Admin.memberDisplayName(m)
        mv.pos = Admin.positionOf(g, m)   -- LK13-T16 : position et source de chaque membre vivant
    end
    return out
end

-- Requête ------------------------------------------------------------------------------------------------------

-- Traite une requête d'administration de player. args = { op, n, gid, x, y, z, action, windowMs, log, npc, field,
-- value, after, role, first, last }. Rend la réponse { n, op, ok, err, ... } (table neuve de valeurs simples, prête
-- à envoyer au seul demandeur).
function Admin.request(player, args)
    count("requests")
    if type(args) ~= "table" then args = {} end
    local op = type(args.op) == "string" and args.op or nil
    local n = isInt(args.n, 0, 2147483647) and args.n or 0
    local reply = { n = n, op = op, ok = false }
    local allowed, why = Admin.isAllowed(player, op)
    if not allowed then
        refuse(player, op, why)
        reply.err = "denied"
        return reply
    end
    if op == nil or not Admin.OPS[op] then
        reply.err = "unknown request"
        return reply
    end
    local who = Admin.nameOf(player)
    local result, err
    if op == "list" then
        result, err = Admin.list()
    elseif op == "group" then
        result, err = Admin.group(args.gid)
    elseif op == "relief" then
        result, err = Admin.forceRelief(args.gid, who)
    elseif op == "load" then
        result, err = Admin.load(args, who)
    elseif op == "npc" then
        result, err = Admin.npcView(args.npc)
    elseif op == "activity" then
        result, err = Admin.activity(args.gid, args.after)
    elseif op == "npcSet" then
        result, err = Admin.npcSet(args.npc, type(args.field) == "string" and args.field or nil, args.value, who)
    elseif op == "npcRole" then
        result, err = Admin.npcRole(args.npc, args.role, who)
    elseif op == "npcName" then
        result, err = Admin.npcName(args.npc, args.first, args.last, who)
    elseif op == "npcGoto" then
        result, err = Admin.npcGoto(args.npc, who, player)
    elseif op == "homeGoto" then
        result, err = Admin.homeGoto(args.gid, who, player)
    else
        result, err = Admin.moveHome(args.gid, args.x, args.y, args.z, who)
    end
    reply.gid = type(args.gid) == "string" and args.gid or nil
    local onNpc = op == "npc" or op == "npcSet" or op == "npcRole" or op == "npcName" or op == "npcGoto"
    if onNpc then reply.id = type(args.npc) == "string" and args.npc or nil end
    if result == nil then
        count("failed")
        reply.err = tostring(err)
        if op == "relief" or op == "home" or op == "homeGoto" or (onNpc and op ~= "npc") then
            log().info("admin: %s by %s on %s failed: %s", op, who, tostring(reply.gid or reply.id), reply.err)
        end
        return reply
    end
    count("done")
    reply.ok = true
    for k, v in pairs(result) do reply[k] = v end
    return reply
end

function Admin.onClientCommand(module, command, player, args)
    if module ~= Admin.MODULE or command ~= Admin.CMD_REQUEST or not isServer() or player == nil then return end
    local reply = Admin.request(player, args)
    sendServerCommand(player, Admin.MODULE, Admin.CMD_REPLY, reply)
end

if Events ~= nil and isServer() then
    local function onClientCommand(module, command, player, args)
        LivingKnox.Admin.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnClientCommand", "Admin.onClientCommand", onClientCommand)
end

return Admin
