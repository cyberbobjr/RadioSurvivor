-- Living Knox : relations d'un groupe avec les joueurs, au-delà de l'attitude (LK11-T06 : demandes d'aide).
-- Fiche : docs/annexes/conception/aide.md. Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Demande d'aide (Relations.requestAid(gid, playerKey, kind, opts)) : un joueur demande de la nourriture ("food"), de
-- l'eau ("water") ou des soins ("care") à un groupe. Aucune lecture du texte du joueur : le point d'entrée est une
-- action explicite (menu contextuel « Demander de l'aide » sur un PNJ, LK_RelationsView.lua, commande "aidRequest"
-- contrôlée ici par Relations.ask) ou, plus tard, une intention fermée du LLM du carnet vérifiée par le serveur (voir
-- la fiche : le pont n'admet pas encore d'intention d'aide).
-- Décision, dans l'ordre :
--   1. une demande au plus par groupe et par période (AID.PERIOD_HOURS heures de jeu, tous joueurs confondus ; champ
--      facultatif aid = { h = heure de jeu de la dernière décision, k = genre } du groupe dans le registre privé des
--      groupes, contrôlé ici, ignoré par LK_Groups) : refus "again", rien n'est écrit ;
--   2. attitude du groupe envers le joueur (LivingKnox.Hostility.get) dans AID.LEVELS (favorable, confiant), sinon
--      refus "attitude" ;
--   3. stock réel (LK_Stock, seuils de LK08-T07) : le groupe ne donne que si, après le don, la catégorie reste à sa
--      réserve visée (have - 1 >= want), sinon refus "short" ; un objet consommable de la catégorie doit exister dans
--      les conteneurs du foyer (relus maintenant). Zone du foyer illisible ou référence absente : refus "away"
--      (rien n'est écrit, la période n'est pas consommée).
-- Les refus 2 et 3 et l'acceptation sont des décisions : marque de période et entrée « aid » au journal du groupe
-- (connue de tous les membres), fait "aidDecided" publié (LivingKnox.publish) ; un don est retiré du stock par
-- Stock.takeItem, une seule fois, dans la même écriture du registre que la marque et l'entrée du journal.
-- L'objet retiré (le même objet, même identifiant) arrive dans l'inventaire du joueur comme le vanilla le fait pour un
-- objet créé par une recette (M/shared/ActionManager.lua:4-24, Actions.addOrDropItem : AddItem, puis
-- sendAddItemToContainer sur un serveur) ; joueur trop chargé : posé au sol au pied du PNJ (sinon du joueur),
-- IsoGridSquare.AddWorldInventoryItem(objet, x, y, h, true) qui l'envoie aux clients sur un serveur
-- (J/iso/IsoGridSquare.java:5200-5266, transmitCompleteItemToClients).
-- Réplique : le PNJ qui a reçu la demande (opts.npc) répond par LivingKnox.Speech.say avec une clé traduite par chaque
-- client (IGUI_LK_Aid_Given_<genre>, IGUI_LK_Aid_Refuse_<raison>).
--
-- Vengeance différée (LK11-T05, fiche docs/annexes/conception/vengeance.md), fin du fichier : fait "npcDied" d'un membre tué
-- par un joueur identifié par le serveur -> fait d'attitude "kill" (attribuable) ; serment si l'attitude qui en
-- résulte est dans REVENGE.LEVELS (hostile), si le groupe n'a aucune vengeance en cours et compte assez de
-- combattants ; champ facultatif revenge du groupe (registre privé, persistant) ; délai, départ d'une équipe réelle
-- (expédition abstraite place "revenge" : absente du foyer pour la simulation et la matérialisation), trajet abstrait
-- (LK_Simulation : Relations.offscreenHour avant chaque heure simulée, Relations.revengeReturn au retour), traque à la
-- dernière zone connue : corps créés seulement à distance des joueurs (Relations.huntPass, chaque minute de jeu, par
-- LivingKnox.Materialize.embodyMember), comportement "revenge" du cadre de décision (Relations.memberHunt,
-- Relations.applyHunt), engagement par Hostility.chooseTarget (raison "revenge") ; fin : cible morte, rancune éteinte
-- (attitude sortie de REVENGE.LEVELS par le déclin ou des actes), ou MAX_FAILS traques manquées.
-- Raids (LK11-T07, LK_Raids.lua, fiche docs/annexes/conception/raids.md) : même trajet abstrait, mêmes corps à distance et même
-- marche, par les fonctions partagées travelHours, livingTeam, turnBack, delayReturn, embodyTeam, say et le repli de
-- memberHunt vers LivingKnox.Raids.memberHunt.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Hostility"
require "LivingKnox/LK_Stock"

local Relations = LivingKnox.Relations or {}
LivingKnox.Relations = Relations

Relations.MODULE = "LivingKnox"
Relations.CMD_AID = "aidRequest"
Relations.KINDS = { "food", "water", "care" }
Relations.CATEGORY = { food = "food", water = "water", care = "medical" }   -- genre -> catégorie du stock
-- Réglages (valeurs de départ propres au mod, à recalibrer en jeu ; fiche aide.md).
Relations.AID = Relations.AID or {
    PERIOD_HOURS = 24,                                  -- une demande par groupe et par période (heures de jeu)
    LEVELS = { favorable = true, trusting = true },     -- attitudes (LK_Hostility.LEVELS) qui donnent
    RANGE = 4,                                          -- distance joueur-PNJ au plus pour une demande par le menu
}
Relations.REASONS = { "attitude", "short", "again", "away", "stranger" }
Relations.stats = Relations.stats or { asked = 0, given = 0, refused = 0, inventory = 0, ground = 0 }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Stock() return LivingKnox.Stock end
local function Hostility() return LivingKnox.Hostility end

local function isNumber(v) return type(v) == "number" and v == v and v > -1e12 and v < 1e12 end

local function hourNow()
    local gt = getGameTime and getGameTime()
    local h = gt and gt:getWorldAgeHours() or 0
    if not isNumber(h) then return 0 end
    return h
end

local function isKind(kind)
    return type(kind) == "string" and Relations.CATEGORY[kind] ~= nil
end

-- Marque de période valide (champ aid du groupe) : { h = heure, k = genre }.
function Relations.validMark(m)
    return type(m) == "table" and isNumber(m.h) and m.h >= 0 and isKind(m.k)
end

-- Heures de jeu avant qu'une nouvelle demande soit admise par le groupe g (0 = admise). Une marque invalide ou venue
-- du futur (horloge reculée) ne bloque pas.
function Relations.waitHours(g, hour)
    local m = type(g) == "table" and g.aid or nil
    if not Relations.validMark(m) then return 0 end
    hour = hour or hourNow()
    if hour < m.h then return 0 end
    local left = Relations.AID.PERIOD_HOURS - (hour - m.h)
    if left <= 0 then return 0 end
    return left
end

-- Objet que le groupe peut donner pour le genre kind (consommable : nourriture mangeable, eau propre ; soins : tout
-- objet de la catégorie « medical »).
function Relations.giftable(item, kind)
    local S = Stock()
    local cat = Relations.CATEGORY[kind]
    if item == nil or cat == nil or S.categoryOf(item) ~= cat then return false end
    if cat == "food" or cat == "water" then return S.consumable(item, cat) end
    return true
end

-- Joueur en ligne (ou local en solo) dont la clé de joueur (identité du carnet) est key, ou nil.
function Relations.playerOf(key)
    local H = Hostility()
    local list = getOnlinePlayers and getOnlinePlayers() or nil
    if list ~= nil then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil and H.keyOf(p) == key then return p end
        end
    end
    for i = 0, 3 do
        local p = getSpecificPlayer and getSpecificPlayer(i) or nil
        if p ~= nil and H.keyOf(p) == key then return p end
    end
    return nil
end

-- Remet l'objet au joueur : inventaire (comme Actions.addOrDropItem), ou au sol au pied du PNJ (body) si le joueur
-- est trop chargé ou absent. Rend "inventory", "ground" ou nil.
function Relations.deliver(item, player, body)
    if player ~= nil and not player:isDead() then
        local inv = player:getInventory()
        inv:AddItem(item)
        if inv:getCapacityWeight() <= inv:getEffectiveCapacity(player) then
            if isServer() then sendAddItemToContainer(inv, item) end
            return "inventory"
        end
        inv:Remove(item)
    end
    local holder = body or player
    local sq = holder ~= nil and holder:getCurrentSquare() or nil
    if sq == nil then return nil end
    sq:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
    return "ground"
end

-- Réplique du PNJ (facultative) : clé traduite par chaque client. Rend vrai si quelqu'un l'a entendue.
local function reply(npc, key, player, band)
    local Sp = LivingKnox.Speech
    if npc == nil or Sp == nil or Sp.say == nil then return false end
    local ok, out, why = pcall(Sp.say, npc, { key = key }, { player = player, band = band, chat = false })
    if not ok then
        log().warn("aid: reply %s of %s failed: %s", key, tostring(npc), tostring(out))
        return false
    end
    if out == nil then log().debug("aid: reply %s of %s not said: %s", key, tostring(npc), tostring(why)) end
    return out ~= nil
end

-- Réplique traduite (clé) d'un PNJ, pour les autres modules d'autorité (LK11-T07 : éclaireurs d'un raid). Rend vrai
-- si quelqu'un l'a entendue.
function Relations.say(npc, key, player, band)
    return reply(npc, key, player, band)
end

local function bandOf(level)
    local Sp = LivingKnox.Speech
    if Sp ~= nil and Sp.bandOf ~= nil then return Sp.bandOf(level) end
    return nil
end

-- Écrit une décision (refus motivé) : marque de période et entrée au journal du groupe, en une écriture.
local function markRefusal(gid, kind, text, hour)
    local G = Groups()
    return G.update(function(data)
        local g = data.groups[gid]
        if g == nil then return false, false end
        g.aid = { h = hour, k = kind }
        G.appendLog(g, "aid", string.sub(text, 1, G.TEXT_MAX), G.today())
        return true, true
    end)
end

-- Fin commune : fait publié, réplique, compte rendu. out = { accepted, reason, kind, ... }.
local function finish(gid, key, kind, out, opts, level)
    local G = Groups()
    if out.decided then
        LivingKnox.publish("aidDecided", { group = gid, player = key, kind = kind, accepted = out.accepted,
            reason = out.reason, item = out.item and out.item.t or nil, where = out.where, npc = opts.npc,
            day = G.today() })
    end
    if out.accepted then
        out.line = "IGUI_LK_Aid_Given_" .. kind
        Relations.stats.given = Relations.stats.given + 1
    else
        out.line = "IGUI_LK_Aid_Refuse_" .. out.reason
        Relations.stats.refused = Relations.stats.refused + 1
    end
    out.said = reply(opts.npc, out.line, opts.player, out.accepted and "friendly" or bandOf(level))
    log().info("aid: group %s %s %s to %s%s", gid, out.accepted and "gave" or "refused", kind, key,
        out.accepted and (": " .. out.item.t .. " (" .. tostring(out.item.i) .. ") into " .. tostring(out.where))
            or (": " .. out.reason .. (out.detail and (" (" .. out.detail .. ")") or "")))
    return out
end

-- Demande d'aide du joueur de clé playerKey (identité du carnet) au groupe gid, pour le genre kind ("food", "water",
-- "care"). opts = { player = IsoPlayer destinataire (sinon retrouvé par sa clé), npc = "lk-<n>" membre qui répond
-- (facultatif : réplique, objet posé à ses pieds si le joueur est trop chargé) }.
-- Rend { accepted, reason ("given" | REASONS), decided (période consommée), kind, item = { i, t, k } (don), where
-- ("inventory" | "ground"), line (clé de la réplique), said, wait (heures, refus "again") }, ou nil et une raison
-- (entrée invalide : rien n'est décidé ni dit).
function Relations.requestAid(gid, playerKey, kind, opts)
    opts = type(opts) == "table" and opts or {}
    if not LivingKnox.isAuthority() then return nil, "not the authority" end
    if not isKind(kind) then return nil, "bad kind" end
    local H = Hostility()
    if not H.validPlayerKey(playerKey) then return nil, "bad player key" end
    local G = Groups()
    local g = G.get(gid)
    if g == nil then return nil, "unknown group" end
    if opts.npc ~= nil and G.findNpc(opts.npc) ~= gid then return nil, "npc not in group" end
    opts.player = opts.player or Relations.playerOf(playerKey)
    local body
    if opts.npc ~= nil and LivingKnox.Bodies ~= nil and LivingKnox.Bodies.find ~= nil then
        body = LivingKnox.Bodies.find(opts.npc)
    end
    if opts.player == nil and body == nil then return nil, "no recipient (player offline, npc not embodied)" end
    Relations.stats.asked = Relations.stats.asked + 1
    local out = { kind = kind, accepted = false, decided = false }
    local hour = hourNow()

    local att, why = H.get(gid, playerKey)   -- lu d'abord (sans effet) : couleur de la réplique de chaque refus
    if att == nil then return nil, why end

    local wait = Relations.waitHours(g, hour)
    if wait > 0 then
        out.reason, out.wait = "again", wait
        out.detail = string.format("%.1f h left", wait)
        return finish(gid, playerKey, kind, out, opts, att.level)
    end

    if not Relations.AID.LEVELS[att.level] then
        out.reason, out.decided, out.detail = "attitude", true, att.level
        markRefusal(gid, kind, string.format("aid %s refused to %s: attitude %s", kind, playerKey, att.level), hour)
        return finish(gid, playerKey, kind, out, opts, att.level)
    end

    local S = Stock()
    local cat = Relations.CATEGORY[kind]
    local a, stockWhy = S.needs(gid)
    if a == nil then
        out.reason, out.detail = "away", tostring(stockWhy)
        return finish(gid, playerKey, kind, out, opts, att.level)
    end
    local have, want = a.have[cat] or 0, a.want[cat] or 0
    local short = string.format("have %d, keep %d", have, want)
    if have - 1 < want then
        out.reason, out.decided, out.detail = "short", true, short
        markRefusal(gid, kind, string.format("aid %s refused to %s: short (%s)", kind, playerKey, short), hour)
        return finish(gid, playerKey, kind, out, opts, att.level)
    end

    local logged, picked
    local function record(live, t)
        live.aid = { h = hour, k = kind }
        G.appendLog(live, "aid", string.sub(string.format("aid %s given to %s: %s", kind, playerKey, tostring(t)), 1,
            G.TEXT_MAX), G.today())
        logged = true
    end
    local got, item = S.takeItem(gid, function(it)
        if Relations.giftable(it, kind) then
            picked = it
            return true
        end
        return false
    end, "aid to " .. playerKey, "aid " .. kind, function(live) record(live, picked:getFullType()) end)
    if got == nil then
        if item == "none" then
            out.reason, out.decided, out.detail = "short", true, "nothing usable"
            markRefusal(gid, kind, string.format("aid %s refused to %s: short (nothing usable)", kind, playerKey),
                hour)
        else
            out.reason, out.detail = "away", tostring(item)
        end
        return finish(gid, playerKey, kind, out, opts, att.level)
    end
    local ok, where = pcall(Relations.deliver, item, opts.player, body)
    if not ok then
        log().error("aid: group %s: %s (%s) taken but not delivered: %s", gid, got.t, tostring(got.i), tostring(where))
        where = nil
    end
    if where ~= nil then Relations.stats[where] = Relations.stats[where] + 1 end
    if not logged then   -- référence illisible pendant le retrait : marque et journal écrits quand même
        G.update(function(data)
            local live = data.groups[gid]
            if live == nil then return false, false end
            record(live, got.t)
            return true, true
        end)
    end
    if cat == "food" or cat == "water" then S.updateRation(gid) end
    out.accepted, out.reason, out.decided, out.item, out.where = true, "given", true, got, where
    return finish(gid, playerKey, kind, out, opts, att.level)
end

-- Demande venue du menu d'un joueur (commande "aidRequest" en MP, appel direct en solo) : args = { npc = "lk-<n>",
-- kind }. Contrôles : genre connu, PNJ d'un groupe, corps présent, joueur vivant à AID.RANGE cases au plus au même
-- niveau. Sans identité du carnet : refus « stranger » dit par le PNJ (rien n'est décidé). Rend le résultat de
-- requestAid, ou nil et une raison.
function Relations.ask(player, args)
    if type(args) ~= "table" or player == nil or player:isDead() then return nil, "bad request" end
    local npc, kind = args.npc, args.kind
    if type(npc) ~= "string" or not isKind(kind) then return nil, "bad request" end
    local gid = Groups().findNpc(npc)
    if gid == nil then return nil, "npc not in a group" end
    local B = LivingKnox.Bodies
    local body = B ~= nil and B.find ~= nil and B.find(npc) or nil
    if body == nil then return nil, "npc not embodied" end
    local dx, dy = body:getX() - player:getX(), body:getY() - player:getY()
    if math.floor(body:getZ()) ~= math.floor(player:getZ())
        or dx * dx + dy * dy > Relations.AID.RANGE * Relations.AID.RANGE then
        return nil, "too far"
    end
    local key = Hostility().keyOf(player)
    if key == nil then
        local out = { kind = kind, accepted = false, decided = false, reason = "stranger",
            line = "IGUI_LK_Aid_Refuse_stranger" }
        out.said = reply(npc, out.line, player, nil)
        Relations.stats.refused = Relations.stats.refused + 1
        log().info("aid: %s asked %s of %s without a notebook character: refused", tostring(player:getUsername()),
            kind, gid)
        return out
    end
    return Relations.requestAid(gid, key, kind, { player = player, npc = npc })
end

function Relations.onClientCommand(module, command, player, args)
    if module ~= Relations.MODULE or command ~= Relations.CMD_AID or not isServer() or player == nil then return end
    local out, why = Relations.ask(player, args)
    if out == nil then
        log().info("aid: request of %s refused: %s", tostring(player:getUsername()), tostring(why))
    end
end

if Events ~= nil and isServer() then
    local function onClientCommand(module, command, player, args)
        LivingKnox.Relations.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnClientCommand", "Relations.onClientCommand", onClientCommand)
end

-- =================================================================================================== vengeance
-- LK11-T05. Champ facultatif revenge du groupe (registre privé des groupes, schéma 1 inchangé, ignoré par LK_Groups,
-- contrôlé ici : malformé -> oublié avec un avertissement) :
--   revenge = { v = 1, key = clé de joueur (identité du carnet), u = compte du tueur, victim = "m-<k>",
--               sworn = heure du serment, phase = "sworn" | "out" | "hunt" | "back", due = heure du départ (sworn),
--               n = tentatives parties, fails = traques manquées, zone = { x, y, z, src = "kill" | "safehouse" },
--               team = { "m-<k>" } (out, hunt, back), dep, arrive, leave = heures de départ, d'arrivée à la zone et
--               de fin de traque, travel = heures de trajet, ending = raison de fin en attente du retour (facultatif) }
-- Une vengeance au plus par groupe (donc par groupe et par joueur). Pendant out, hunt et back, l'équipe est une
-- expédition abstraite { place = "revenge", team, departed, returns } (LK09-T02) : absente du foyer pour la
-- simulation horaire, jamais matérialisée au foyer (Materialize.presentMembers), jamais candidate d'une autre
-- expédition ; LK_Simulation appelle Relations.revengeReturn à l'heure returns au lieu de son propre retour.
Relations.REVENGE = Relations.REVENGE or {
    ENABLED = true,
    LEVELS = { hostile = true },   -- attitude (après le meurtre) qui fait jurer ; la rancune vit tant qu'elle y reste
    -- Heures de jeu entre le serment et le premier départ : option sandbox LivingKnox.RevengeDelayHours (LK11-T10,
    -- Relations.revengeDelayHours, défaut 72, de 12 à 336), lue au serment. DELAY_HOURS (nombre) la remplace :
    -- forçage des bancs et des suites en jeu seulement (0 admis) ; nil = l'option.
    DELAY_HOURS = nil,
    RETRY_HOURS = 24,              -- heures de jeu entre le retour d'une traque manquée et le départ suivant
    HUNT_HOURS = 12,               -- heures passées à la zone avant de renoncer à cette tentative
    MAX_FAILS = 3,                 -- traques manquées avant l'abandon
    SPEED = 300,                   -- cases par heure de jeu (trajet abstrait, pauses comprises)
    TEAM_MIN = 2,                  -- combattants (rôle qui permet fight ou defend), hors chef, valides, au foyer
    TEAM_MAX = 3,
    MIN_HOME = 1,                  -- vivants qui restent au foyer
    WOUND_MAX = 20,                -- blessure abstraite au plus d'un partant (Config.SIMULATION.WOUND_MINOR)
    MAT_RADIUS = 80,               -- un joueur vivant à cet écart de la zone : l'équipe en traque reçoit ses corps
    SPAWN_MIN = 40,                -- cases : jamais un corps créé plus près d'un joueur vivant
    SPAWN_MAX = 75,                -- cases : recherche de la case d'apparition autour de la zone
    PER_PASS = 2,                  -- corps créés au plus par passage
    STEP = 40,                     -- cases : longueur d'une étape de marche (Directives.MAX_TRIP = 60)
    PATROL = 8,                    -- cases : rayon de la ronde autour de la zone pendant la traque
    SPEAK_RANGE = 30,              -- cases : membre incarné qui annonce le serment, autour du lieu de la mort
    AVENGED_RANGE = 30,            -- cases : cible morte avec un corps de l'équipe à cet écart -> « vengé »
}
Relations.REVENGE_PHASES = { "sworn", "out", "hunt", "back" }
Relations.REVENGE_ENDINGS = { "avenged", "target_dead", "faded", "given_up", "wiped" }
Relations.revengeStats = Relations.revengeStats or { kills = 0, sworn = 0, declined = 0, departed = 0, hunts = 0,
    failed = 0, ended = 0, spawned = 0, spawnWaits = 0 }
Relations.huntState = Relations.huntState or { npcs = {}, warned = {} }

local function H() return Hostility() end

local function isInt(v, lo, hi) return isNumber(v) and math.floor(v) == v and v >= lo and v <= hi end

local function inList(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function cut(s) return string.sub(s, 1, Groups().TEXT_MAX or 200) end

local function revCfg() return Relations.REVENGE end

local function hourInt() return math.floor(hourNow()) end

-- Délai du serment au premier départ (heures de jeu entières, LK11-T10) : forçage revCfg().DELAY_HOURS s'il est un
-- nombre, sinon option LivingKnox.RevengeDelayHours (Config.readInt : absente, non entière ou hors bornes -> 72).
-- Lu au serment seulement : une vengeance jurée garde son heure de départ (due) quand l'option change.
function Relations.revengeDelayHours()
    local forced = revCfg().DELAY_HOURS
    if isNumber(forced) then return math.max(0, math.floor(forced)) end
    return LivingKnox.Config.readInt("RevengeDelayHours")
end

local function validZone(z)
    return type(z) == "table" and isInt(z.x, -1e7, 1e7) and isInt(z.y, -1e7, 1e7) and isInt(z.z, -32, 31)
        and (z.src == "kill" or z.src == "safehouse")
end

local function validTeam(list)
    if type(list) ~= "table" then return false end
    local n = 0
    for k, mid in pairs(list) do
        if not isInt(k, 1, 32) or not Groups().memberNumber(mid) then return false end
        n = n + 1
    end
    return n >= 1 and n == #list
end

-- Vengeance relue valide (champ revenge d'un groupe). Rend vrai, ou faux et une raison.
function Relations.validRevenge(r)
    if type(r) ~= "table" or r.v ~= 1 then return false, "not a revenge record" end
    if not H().validPlayerKey(r.key) then return false, "bad player key" end
    if r.u ~= nil and (type(r.u) ~= "string" or #r.u < 1 or #r.u > 64) then return false, "bad account" end
    if not Groups().memberNumber(r.victim) then return false, "bad victim" end
    if not isInt(r.sworn, 0, 1e9) or not isInt(r.n, 0, 1e6) or not isInt(r.fails, 0, 1e6) then
        return false, "bad counters"
    end
    if not inList(Relations.REVENGE_PHASES, r.phase) then return false, "bad phase" end
    if not validZone(r.zone) then return false, "bad zone" end
    if r.ending ~= nil and not inList(Relations.REVENGE_ENDINGS, r.ending) then return false, "bad ending" end
    if r.phase == "sworn" then
        if not isInt(r.due, 0, 1e9) then return false, "bad due hour" end
    else
        if not validTeam(r.team) then return false, "bad team" end
        if not isInt(r.dep, 0, 1e9) or not isInt(r.arrive, r.dep or 0, 1e9) or not isInt(r.leave, r.arrive or 0, 1e9)
            or not isInt(r.travel, 1, 1e6) then
            return false, "bad hours"
        end
    end
    return true
end

-- Vengeance valide du groupe g (registre vivant), ou nil ; une vengeance malformée est oubliée (avertissement).
local function revengeOf(g, gid)
    local r = type(g) == "table" and g.revenge or nil
    if r == nil then return nil end
    local ok, why = Relations.validRevenge(r)
    if ok then return r end
    log().warn("revenge: group %s record dropped: %s", tostring(gid), tostring(why))
    g.revenge = nil
    return nil
end

local function liveGroups()
    local G = Groups()
    if not G.isReady() then return nil end
    return G.state.data
end

-- Vengeance en cours du groupe gid contre la clé de joueur key (toute phase) : lecture seule, sans contrôle de
-- forme (Hostility.chooseTarget, à chaque décision).
function Relations.revengeAgainst(gid, key)
    local data = liveGroups()
    local g = data and data.groups[gid] or nil
    local r = g and g.revenge or nil
    return type(r) == "table" and r.key == key and r.v == 1
end

-- Rôle combattant : le type du groupe permet fight ou defend à ce rôle.
function Relations.combatant(groupType, role)
    local def = LivingKnox.GroupTypes.get(groupType)
    local r = def and def.roles and def.roles[role] or nil
    for _, b in ipairs(r and r.behaviours or {}) do
        if b == "fight" or b == "defend" then return true end
    end
    return false
end

local function memberEmbodied(m)
    local Si = LivingKnox.Simulation
    return Si ~= nil and Si.isEmbodied ~= nil and Si.isEmbodied(m)
end

-- Combattants vivants hors chef (serment : le groupe a-t-il de quoi se venger ?).
local function fighterCount(g)
    local n = 0
    for mid, m in pairs(g.members) do
        if m.alive and mid ~= g.leader and Relations.combatant(g.type, m.role) then n = n + 1 end
    end
    return n
end

-- Règle du serment (pure) : c = { enabled, level, active (vengeance déjà en cours dans le groupe), same (contre ce
-- joueur), fighters }. Rend true, "sworn", ou false et la raison du refus.
function Relations.oathRule(c)
    local cfg = revCfg()
    if c.enabled ~= true then return false, "disabled" end
    if c.same == true then return false, "already sworn" end
    if c.active == true then return false, "busy" end
    if not cfg.LEVELS[c.level] then return false, "attitude " .. tostring(c.level) end
    if (c.fighters or 0) < cfg.TEAM_MIN then return false, "too weak" end
    return true, "sworn"
end

local function publishRevenge(name, gid, r, extra)
    local info = { group = gid, player = r.key, victim = r.victim, n = r.n, fails = r.fails, day = Groups().today() }
    for k, v in pairs(extra or {}) do info[k] = v end
    LivingKnox.publish(name, info)
end

-- Membre incarné du groupe le plus proche de (x, y), à range cases au plus, ou nil.
local function speakerNear(g, x, y, range)
    local B = LivingKnox.Bodies
    if B == nil or B.find == nil or x == nil or y == nil then return nil end
    local best, bestD
    local mids = {}
    for mid in pairs(g.members) do mids[#mids + 1] = mid end
    table.sort(mids, function(a, b) return (Groups().memberNumber(a) or 0) < (Groups().memberNumber(b) or 0) end)
    for _, mid in ipairs(mids) do
        local m = g.members[mid]
        local z = m.alive and m.npc and B.find(m.npc) or nil
        if z ~= nil then
            local d = cheb(z:getX(), z:getY(), x, y)
            if d <= range and (bestD == nil or d < bestD) then best, bestD = m.npc, d end
        end
    end
    return best
end

-- Membre mid du groupe gid tué par le joueur de clé key (identité du carnet) : fait d'attitude "kill" attribuable,
-- puis serment éventuel (Relations.oathRule). opts = { u = compte, x, y, z = lieu de la mort, hour }. Rend
-- { sworn, reason, level }, ou nil et une raison.
function Relations.memberKilled(gid, mid, key, opts)
    opts = type(opts) == "table" and opts or {}
    if not LivingKnox.isAuthority() then return nil, "not the authority" end
    if not H().validPlayerKey(key) then return nil, "bad player key" end
    local G = Groups()
    if not G.ensure() then return nil, "group registry not ready" end
    local g = G.state.data.groups[gid]
    if g == nil then return nil, "unknown group" end
    Relations.revengeStats.kills = Relations.revengeStats.kills + 1
    local att, why = H().record(gid, key, "kill", { attributable = true })
    if att == nil then
        log().warn("revenge: kill of %s/%s by %s not recorded: %s", gid, tostring(mid), key, tostring(why))
        return nil, why
    end
    local r = revengeOf(g, gid)
    local ok, reason = Relations.oathRule({ enabled = revCfg().ENABLED == true, level = att.level, active = r ~= nil,
        same = r ~= nil and r.key == key, fighters = fighterCount(g) })
    local out = { sworn = ok, reason = reason, level = att.level }
    if not ok then
        Relations.revengeStats.declined = Relations.revengeStats.declined + 1
        log().info("revenge: group %s does not swear revenge on %s for %s: %s", gid, key, tostring(mid), reason)
        return out
    end
    local hour = isNumber(opts.hour) and math.floor(opts.hour) or hourInt()
    local zone = { x = math.floor(opts.x or (g.home and g.home.x) or 0), y = math.floor(opts.y or (g.home and g.home.y)
        or 0), z = math.floor(opts.z or 0), src = "kill" }
    if zone.z < -32 or zone.z > 31 then zone.z = 0 end
    local rec = { v = 1, key = key, u = type(opts.u) == "string" and string.sub(opts.u, 1, 64) or nil,
        victim = Groups().memberNumber(mid) and mid or "m-0", sworn = hour, phase = "sworn",
        due = hour + Relations.revengeDelayHours(), n = 0, fails = 0, zone = zone }
    G.update(function(data)
        local live = data.groups[gid]
        if live == nil then return false, false end
        live.revenge = rec
        G.appendLog(live, "revenge", cut(string.format("%s killed by %s: revenge sworn, leaving in %d h",
            rec.victim, key, rec.due - hour)), G.today())
        return true, true
    end)
    Relations.revengeStats.sworn = Relations.revengeStats.sworn + 1
    log().info("revenge: group %s swore revenge on %s (%s) for %s, departure at hour %d, zone %d,%d,%d", gid, key,
        tostring(rec.u), rec.victim, rec.due, zone.x, zone.y, zone.z)
    -- Annonce perceptible : réplique d'un membre présent près de la mort (bulle et ligne de chat, clé traduite par
    -- chaque client), fait publié (point d'appel de la radio du carnet et des événements publics).
    local npc = speakerNear(g, opts.x, opts.y, revCfg().SPEAK_RANGE)
    if npc ~= nil then out.said = reply(npc, "IGUI_LK_Revenge_Sworn", nil, "hostile") end
    publishRevenge("revengeSworn", gid, rec, { due = rec.due, x = zone.x, y = zone.y })
    return out
end

-- Joueur vivant de compte name (connectés en MP, locaux en solo), ou nil.
function Relations.playerByName(name)
    local B = LivingKnox.Bodies
    if type(name) ~= "string" or B == nil or B.livingPlayers == nil then return nil end
    for _, p in ipairs(B.livingPlayers()) do
        if p:getUsername() == name then return p end
    end
    return nil
end

-- Fait "npcDied" (LK_Bodies, LK07-T04) : membre d'un groupe tué par un joueur identifié par le serveur.
function Relations.onNpcDied(info)
    if type(info) ~= "table" or info.group == nil or info.member == nil or type(info.killer) ~= "string" then return end
    local p = Relations.playerByName(info.killer)
    local key = p ~= nil and H().keyOf(p) or nil
    if key == nil then
        log().info("revenge: %s of %s killed by %s (no notebook character): no attitude fact, no oath",
            tostring(info.member), tostring(info.group), info.killer)
        return
    end
    return Relations.memberKilled(info.group, info.member, key, { u = info.killer, x = info.x, y = info.y,
        z = info.z })
end

-- ------------------------------------------------------------------ hors écran (dans le pas de LK_Simulation)

-- Partants possibles (pur, registre vivant) : vivants au foyer (hors expédition), hors chef, combattants, blessure
-- abstraite au plus WOUND_MAX, sans corps (un corps au foyer veut dire un joueur proche : on attend) ; triés par
-- numéro. Rend la liste et le nombre de vivants au foyer.
function Relations.revengeCandidates(g)
    local cfg = revCfg()
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local out, present = {}, 0
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then
            present = present + 1
            if mid ~= g.leader and Relations.combatant(g.type, m.role) and (m.wound or 0) <= cfg.WOUND_MAX
                and not memberEmbodied(m) then
                out[#out + 1] = mid
            end
        end
    end
    table.sort(out, function(a, b) return (Groups().memberNumber(a) or 0) < (Groups().memberNumber(b) or 0) end)
    return out, present
end

-- Dernière zone connue du joueur : refuge vanilla dont il est propriétaire ou membre (SafeHouse.hasSafehouse), sinon
-- le lieu de la mort. Rend une zone.
function Relations.zoneOf(r)
    if r.u ~= nil and SafeHouse ~= nil and SafeHouse.hasSafehouse ~= nil then
        local ok, sh = pcall(SafeHouse.hasSafehouse, r.u)
        if ok and sh ~= nil then
            return { x = math.floor(sh:getX() + sh:getW() / 2), y = math.floor(sh:getY() + sh:getH() / 2), z = 0,
                src = "safehouse" }
        end
    end
    return { x = r.zone.x, y = r.zone.y, z = r.zone.z, src = r.zone.src }
end

-- Heures de trajet abstrait du foyer à la zone, à speed cases par heure (défaut : REVENGE.SPEED), une au moins.
-- Partagé avec les raids (LK11-T07).
function Relations.travelHours(home, zone, speed)
    local d = cheb(home.x, home.y, zone.x, zone.y)
    return math.max(1, math.ceil(d / math.max(1, speed or revCfg().SPEED)))
end
local function travelHours(home, zone) return Relations.travelHours(home, zone) end

local function teamText(team) return table.concat(team, " ") end

-- Membres vivants d'une équipe (liste de "m-<k>"), dans l'ordre. Partagé avec les raids (LK11-T07).
function Relations.livingTeam(g, team)
    local out = {}
    for _, mid in ipairs(team or {}) do
        local m = g.members[mid]
        if m ~= nil and m.alive then out[#out + 1] = mid end
    end
    return out
end
local livingTeam = Relations.livingTeam

-- Fin de la vengeance (registre vivant) : champ effacé, journal, fait publié.
local function endRevenge(g, gid, r, ending, day)
    g.revenge = nil
    Groups().appendLog(g, "revenge", cut(string.format("revenge on %s ended: %s (%d attempt(s), %d failed)", r.key,
        ending, r.n, r.fails)), day)
    Relations.revengeStats.ended = Relations.revengeStats.ended + 1
    log().info("revenge: group %s revenge on %s ended: %s", gid, r.key, ending)
    publishRevenge("revengeEnded", gid, r, { ending = ending })
end

-- Tentative close avant le retour : l'équipe rentre (phase back, retour dans travel heures, ou tout de suite si elle
-- n'a pas encore quitté le foyer). r porte dep, arrive, leave, travel (heures) ; place = lieu de l'expédition
-- abstraite (défaut "revenge" ; "raid" pour LK11-T07). field = champ de phase de r (défaut "phase").
function Relations.turnBack(g, r, hour, place, field)
    r[field or "phase"] = "back"
    if hour < r.leave then r.leave = math.max(r.arrive, hour) end
    if r.leave < r.arrive then r.leave = r.arrive end
    local back = math.max(1, math.min(r.travel, hour - r.dep))
    if type(g.expedition) == "table" and g.expedition.place == (place or "revenge") then
        g.expedition.returns = math.max(g.expedition.departed, hour + back)
    end
end
local function turnBack(g, r, hour) Relations.turnBack(g, r, hour) end

local function tryDepart(g, gid, r, hour, day)
    local cfg = revCfg()
    if type(g.home) ~= "table" then return nil, "no home" end
    if g.expedition ~= nil then return nil, "expedition under way" end
    if type(g.trips) == "table" and g.trips.cur ~= nil then return nil, "physical expedition under way" end
    local cands, present = Relations.revengeCandidates(g)
    local size = math.min(cfg.TEAM_MAX, #cands, present - cfg.MIN_HOME)
    if size < cfg.TEAM_MIN then return nil, "team too small" end
    local team = {}
    for i = 1, size do team[i] = cands[i] end
    local zone = Relations.zoneOf(r)
    local travel = travelHours(g.home, zone)
    r.phase, r.team, r.zone, r.travel = "out", team, zone, travel
    r.n = r.n + 1
    r.dep, r.arrive = hour, hour + travel
    r.leave = r.arrive + math.max(1, math.floor(cfg.HUNT_HOURS))
    r.due, r.ending = nil, nil
    local copy = {}
    for i, mid in ipairs(team) do copy[i] = mid end
    g.expedition = { place = "revenge", team = copy, departed = hour, returns = r.leave + travel }
    Groups().appendLog(g, "revenge", cut(string.format("attempt %d on %s: %s left for %d,%d (%s), %d h away", r.n,
        r.key, teamText(team), zone.x, zone.y, zone.src, travel)), day)
    Relations.revengeStats.departed = Relations.revengeStats.departed + 1
    log().info("revenge: group %s attempt %d on %s: %s left at hour %d for %d,%d,%d (%s), arrival hour %d", gid, r.n,
        r.key, teamText(team), hour, zone.x, zone.y, zone.z, zone.src, r.arrive)
    publishRevenge("revengeStarted", gid, r, { team = copy, x = zone.x, y = zone.y, src = zone.src })
    return true
end

-- Rancune encore vive : attitude du groupe envers la cible dans REVENGE.LEVELS. Registre illisible : vive (on ne
-- renonce pas sur une erreur de lecture).
function Relations.grudgeAlive(gid, key)
    local att = H().get(gid, key)
    if att == nil then return true end
    return revCfg().LEVELS[att.level] == true
end

-- Une heure de jeu pour la vengeance du groupe g (registre vivant, sans sauvegarde : appelé par Simulation.advance
-- avant chaque heure simulée du groupe, dans la même écriture). Aucun accès aux cases ; lit l'attitude et le refuge
-- du joueur. Rend la phase après l'heure, ou nil.
function Relations.offscreenHour(g, gid, hour)
    local r = revengeOf(g, gid)
    if r == nil then return nil end
    local day = math.floor(hour / 24) + 1
    if r.phase ~= "sworn" and (type(g.expedition) ~= "table" or g.expedition.place ~= "revenge") then
        -- Expédition effacée par ailleurs (administration) : la tentative est close comme un retour.
        log().warn("revenge: group %s attempt %d lost its expedition: closed", gid, r.n)
        r.phase, r.team, r.due = "sworn", nil, hour + revCfg().RETRY_HOURS
        r.dep, r.arrive, r.leave, r.travel = nil, nil, nil, nil
    end
    if r.ending == nil and not Relations.grudgeAlive(gid, r.key) then
        if r.phase == "sworn" then
            endRevenge(g, gid, r, "faded", day)
            return nil
        end
        r.ending = "faded"
        if r.phase ~= "back" then turnBack(g, r, hour) end
        log().info("revenge: group %s grudge against %s faded: team turns back", gid, r.key)
    end
    if r.phase ~= "sworn" and #livingTeam(g, r.team) == 0 then
        -- Équipe entière morte : rien ne revient ; tentative manquée.
        g.expedition = nil
        r.fails = r.fails + (r.ending == nil and 1 or 0)
        Relations.revengeStats.failed = Relations.revengeStats.failed + 1
        Groups().appendLog(g, "revenge", cut(string.format("attempt %d on %s: no one came back (%d/%d)", r.n, r.key,
            r.fails, revCfg().MAX_FAILS)), day)
        return Relations.afterAttempt(g, gid, r, hour, day, "wiped")
    end
    if r.phase == "sworn" then
        if hour >= r.due then
            local ok, why = tryDepart(g, gid, r, hour, day)
            if not ok and Relations.huntState.warned[gid] ~= why then
                Relations.huntState.warned[gid] = why
                log().info("revenge: group %s cannot leave yet: %s", gid, tostring(why))
            end
        end
        return r.phase
    end
    if r.phase == "out" and hour >= r.arrive then
        r.phase = "hunt"
        Relations.revengeStats.hunts = Relations.revengeStats.hunts + 1
        log().info("revenge: group %s attempt %d reached %d,%d (%s) at hour %d, hunting until hour %d", gid, r.n,
            r.zone.x, r.zone.y, r.zone.src, hour, r.leave)
    end
    if r.phase == "hunt" and hour >= r.leave then
        r.fails = r.fails + 1
        Relations.revengeStats.failed = Relations.revengeStats.failed + 1
        Groups().appendLog(g, "revenge", cut(string.format("attempt %d on %s failed (%d/%d): heading home", r.n,
            r.key, r.fails, revCfg().MAX_FAILS)), day)
        log().info("revenge: group %s attempt %d on %s failed (%d/%d)", gid, r.n, r.key, r.fails, revCfg().MAX_FAILS)
        turnBack(g, r, hour)
    end
    return r.phase
end

-- Suite d'une tentative close (équipe rentrée ou perdue) : fin en attente, abandon après MAX_FAILS, sinon nouveau
-- départ dans RETRY_HOURS. Rend la phase, ou nil (fin).
function Relations.afterAttempt(g, gid, r, hour, day, lost)
    if r.ending ~= nil then
        endRevenge(g, gid, r, r.ending, day)
        return nil
    end
    if r.fails >= revCfg().MAX_FAILS then
        endRevenge(g, gid, r, lost == "wiped" and "wiped" or "given_up", day)
        return nil
    end
    r.phase, r.team, r.due = "sworn", nil, hour + math.max(0, math.floor(revCfg().RETRY_HOURS))
    r.dep, r.arrive, r.leave, r.travel = nil, nil, nil, nil
    return "sworn"
end

-- Retour de l'équipe (LK_Simulation.simulateHour, heure returns de l'expédition "revenge", registre vivant). Un
-- membre encore incarné loin du foyer (joueur qui le suit) retarde le retour d'une heure. Rend vrai si l'expédition
-- est close.
-- Retour retardé d'une heure (registre vivant) si un membre vivant de team est encore incarné à plus de 10 cases
-- du foyer (joueur qui le suit). Rend vrai si le retour est retardé. Partagé avec les raids (LK11-T07).
function Relations.delayReturn(g, team, hour)
    local e = g.expedition
    if type(e) ~= "table" then return false end
    local B = LivingKnox.Bodies
    for _, mid in ipairs(livingTeam(g, team)) do
        local m = g.members[mid]
        local z = memberEmbodied(m) and B ~= nil and B.find ~= nil and B.find(m.npc) or nil
        if z ~= nil and g.home ~= nil and cheb(z:getX(), z:getY(), g.home.x + 0.5, g.home.y + 0.5) > 10 then
            e.returns = hour + 1
            return true
        end
    end
    return false
end

function Relations.revengeReturn(g, gid, hour, day)
    local r = revengeOf(g, gid)
    if r ~= nil and r.phase ~= "sworn" and Relations.delayReturn(g, r.team, hour) then return false end
    g.expedition = nil
    if r == nil then return true end
    local back = livingTeam(g, r.team)
    Groups().appendLog(g, "revenge", cut(string.format("attempt %d on %s: %d back home", r.n, r.key, #back)), day)
    log().info("revenge: group %s attempt %d back home at hour %d (%d back)", gid, r.n, hour, #back)
    Relations.afterAttempt(g, gid, r, hour, day)
    return true
end

-- Mort d'un personnage (OnCharacterDeath, autorité) : la cible d'une vengeance meurt -> fin « avenged » si un corps
-- de l'équipe était à AVENGED_RANGE cases, sinon « target_dead » ; l'équipe dehors rentre.
function Relations.onCharacterDeath(chr)
    if chr == nil or not instanceof(chr, "IsoPlayer") then return end
    local data = liveGroups()
    if data == nil then return end
    local name = chr:getUsername()
    local key = H().keyOf(chr)
    local B = LivingKnox.Bodies
    for _, gid in ipairs(Groups().list()) do
        local g = data.groups[gid]
        local r = g and g.revenge or nil
        if type(r) == "table" and r.v == 1 and r.ending == nil and ((key ~= nil and r.key == key)
            or (r.u ~= nil and r.u == name)) then
            local ending = "target_dead"
            for _, mid in ipairs(type(r.team) == "table" and r.team or {}) do
                local m = g.members[mid]
                local z = m and m.alive and m.npc and B ~= nil and B.find(m.npc) or nil
                if z ~= nil and cheb(z:getX(), z:getY(), chr:getX(), chr:getY()) <= revCfg().AVENGED_RANGE then
                    ending = "avenged"
                end
            end
            local hour, day = hourInt(), Groups().today()
            Groups().update(function(d)
                local live = d.groups[gid]
                local lr = live and revengeOf(live, gid) or nil
                if lr == nil then return false, false end
                if lr.phase == "sworn" then
                    endRevenge(live, gid, lr, ending, day)
                else
                    lr.ending = ending
                    if lr.phase ~= "back" then turnBack(live, lr, hour) end
                end
                return true, true
            end)
            log().info("revenge: target %s of group %s died: %s", r.key, gid, ending)
        end
    end
end

-- ------------------------------------------------------------------ traque à l'écran

-- Phase de traque du membre mid (contexte du cadre de décision) : { n, phase = "hunt" | "back", zone, rank } si une
-- vengeance en cours le compte dans son équipe, en traque ou au retour ; sinon nil.
-- LK11-T07 : sinon, membre d'un raid à la base ou au retour (LivingKnox.Raids.memberHunt : même forme, plus kind =
-- "raid" et patrol = rayon de la ronde).
function Relations.memberHunt(gid, mid)
    local data = liveGroups()
    local g = data and data.groups[gid] or nil
    local r = g and g.revenge or nil
    if type(r) == "table" and (r.phase == "hunt" or r.phase == "back") and type(r.team) == "table" then
        for i, x in ipairs(r.team) do
            if x == mid then return { n = r.n, phase = r.phase, zone = r.zone, rank = i } end
        end
    end
    local Ra = LivingKnox.Raids
    if Ra ~= nil and Ra.memberHunt ~= nil then return Ra.memberHunt(gid, mid) end
    return nil
end

local function farFrom(players, x, y, d)
    for _, p in ipairs(players) do
        if cheb(p:getX(), p:getY(), x, y) < d then return false end
    end
    return true
end

local ANGLES = { 0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }

-- Case d'apparition d'un membre en traque : au niveau 0, du côté du foyer, de SPAWN_MAX cases de la zone vers elle
-- (pas de 5), à SPAWN_MIN cases au moins de tout joueur vivant, chargée, libre (Bodies.freeSquare), sans escalier,
-- hors des cases déjà prises (used). Rend la case, ou nil.
function Relations.spawnSquare(zone, home, players, used)
    local cfg = revCfg()
    local cell = getCell()
    local B = LivingKnox.Bodies
    if cell == nil or B == nil then return nil end
    local dx, dy = 1, 0
    if home ~= nil then
        local hx, hy = home.x - zone.x, home.y - zone.y
        local len = math.sqrt(hx * hx + hy * hy)
        if len >= 1 then dx, dy = hx / len, hy / len end
    end
    local d = cfg.SPAWN_MAX
    while d >= 0 do
        for _, a in ipairs(ANGLES) do
            local ra = math.rad(a)
            local ux, uy = dx * math.cos(ra) - dy * math.sin(ra), dx * math.sin(ra) + dy * math.cos(ra)
            local x, y = math.floor(zone.x + ux * d + 0.5), math.floor(zone.y + uy * d + 0.5)
            local key = x .. "," .. y
            if not used[key] and farFrom(players, x + 0.5, y + 0.5, cfg.SPAWN_MIN) then
                local sq = cell:getGridSquare(x, y, 0)
                if sq ~= nil and not sq:HasStairs() and B.freeSquare(sq) then
                    used[key] = true
                    return sq
                end
            end
        end
        d = d - 5
    end
    return nil
end

-- Passage (autorité, chaque minute de jeu) : pour chaque vengeance en traque dont la zone a un joueur vivant à
-- MAT_RADIUS cases, les membres de l'équipe vivants sans corps en reçoivent un (Materialize.embodyMember), à
-- distance des joueurs ; PER_PASS au plus. Rend le nombre de corps créés.
-- Corps des membres vivants sans corps de l'équipe team (groupe gid, registre vivant), à distance des joueurs : case
-- de Relations.spawnSquare autour de zone, côté foyer, par Materialize.embodyMember ; budget corps au plus. tag =
-- préfixe du journal ("revenge", "raid") ; stats = table de compteurs { spawned, spawnWaits } ; warned = table des
-- raisons déjà journalisées (clé gid). Rend le nombre de corps créés. Partagé avec les raids (LK11-T07).
function Relations.embodyTeam(gid, g, team, zone, players, budget, tag, stats, warned)
    local Mat, I = LivingKnox.Materialize, LivingKnox.Identity
    local cfg = revCfg()
    local created, s, used = 0, Mat.settings(), {}
    for _, mid in ipairs(livingTeam(g, team)) do
        if created >= budget then return created end
        local m = g.members[mid]
        local state = Mat.npcState(m, LivingKnox.Store.data())
        if state ~= I.STATE_EMBODIED and state ~= I.STATE_DEAD then
            local sq = Relations.spawnSquare(zone, g.home, players, used)
            if sq == nil then
                stats.spawnWaits = stats.spawnWaits + 1
                if warned[gid] ~= "spawn" then
                    warned[gid] = "spawn"
                    log().info("%s: group %s: no loaded free square %d+ squares from every player near %d,%d: waiting",
                        tag, gid, cfg.SPAWN_MIN, zone.x, zone.y)
                end
                break
            end
            local npcId, why = Mat.embodyMember(gid, g, mid, m, sq, s)
            if npcId == nil then
                log().warn("%s: group %s member %s not materialized: %s", tag, gid, mid, tostring(why))
                break
            end
            created = created + 1
            stats.spawned = stats.spawned + 1
            warned[gid] = nil
            log().info("%s: group %s member %s (npc %s) near %d,%d, materialized at %d,%d", tag, gid, mid, npcId,
                zone.x, zone.y, sq:getX(), sq:getY())
        end
    end
    return created
end

function Relations.huntPass()
    local B, Mat = LivingKnox.Bodies, LivingKnox.Materialize
    if B == nil or Mat == nil or Mat.embodyMember == nil or not B.canAct(true) then return 0 end
    local data = liveGroups()
    if data == nil then return 0 end
    local cfg = revCfg()
    local players = B.livingPlayers()
    if #players == 0 then return 0 end
    local created = 0
    for _, gid in ipairs(Groups().list()) do
        local g = data.groups[gid]
        local r = g and g.revenge or nil
        if type(r) == "table" and r.phase == "hunt" and type(g.expedition) == "table"
            and g.expedition.place == "revenge" and Relations.validRevenge(r)
            and B.playerNear(players, r.zone.x + 0.5, r.zone.y + 0.5, cfg.MAT_RADIUS) then
            created = created + Relations.embodyTeam(gid, g, r.team, r.zone, players, cfg.PER_PASS - created,
                "revenge", Relations.revengeStats, Relations.huntState.warned)
            if created >= cfg.PER_PASS then return created end
        end
    end
    return created
end

local function X() return LivingKnox.Routines.exec end

local function huntMem(id, gid, n, kind)
    local mem = Relations.huntState.npcs
    local m = mem[id]
    if m == nil or m.gid ~= gid or m.n ~= n or m.kind ~= kind then
        m = { gid = gid, n = n, kind = kind, fails = 0, k = 0 }
        mem[id] = m
    end
    return m
end

local function resetSteps(m)
    m.lastV, m.moveV, m.fails, m.wp = nil, nil, 0, nil
end

-- But du membre : traque = ronde de 4 points à PATROL cases autour de la zone (hu.patrol pour un raid, LK11-T07 ;
-- départ selon son rang) ; retour = le foyer.
local PATROL = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local function goalOf(hu, ctx, m)
    if hu.phase == "back" then
        if ctx.home == nil then return nil end
        return ctx.home.x, ctx.home.y, ctx.home.z
    end
    local p = PATROL[((hu.rank + m.k) % #PATROL) + 1]
    local r = hu.patrol or revCfg().PATROL
    return hu.zone.x + p[1] * r, hu.zone.y + p[2] * r, hu.zone.z
end

-- Applique la traque au membre (comportement « revenge » du cadre de décision), à chaque passage : marche par étapes
-- de STEP cases vers la ronde de la zone (traque) ou vers le foyer (retour). La cible vue est engagée par la règle
-- threat (Hostility.chooseTarget, raison "revenge"), avant ce comportement.
function Relations.applyHunt(id, st, ctx, fresh)
    local hu = ctx.hunt
    if hu == nil or LivingKnox.Routines == nil then return end
    local m = huntMem(id, ctx.gid, hu.n, hu.kind or "revenge")
    local e = X().entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) then resetSteps(m) end   -- autre consigne passée entre-temps
    if m.phase ~= hu.phase then
        resetSteps(m)
        m.phase = hu.phase
    end
    local gx, gy, gz = goalOf(hu, ctx, m)
    if gx == nil then return end
    local tx, ty, tz = gx, gy, gz
    local far = cheb(ctx.x, ctx.y, gx + 0.5, gy + 0.5)
    if far > revCfg().STEP or ctx.z ~= gz then
        if m.wp == nil then
            local ratio = math.min(1, revCfg().STEP / math.max(far, 1))
            local wx = math.floor(ctx.x + (gx + 0.5 - ctx.x) * ratio)
            local wy = math.floor(ctx.y + (gy + 0.5 - ctx.y) * ratio)
            local sq = LivingKnox.Bodies.findFreeSquare(wx, wy, ctx.z)
            if sq == nil then
                m.k = m.k + 1
                return
            end
            m.wp = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        end
        tx, ty, tz = m.wp.x, m.wp.y, m.wp.z
    else
        m.wp = nil
    end
    local res = X().goTo(id, ctx, tx, ty, tz, m, e)
    if res == "here" or res == "failed" then
        local final = m.wp == nil
        resetSteps(m)
        if final and hu.phase == "hunt" then m.k = m.k + 1 end   -- point de ronde atteint (ou manqué) : suivant
        if res == "failed" and not final then m.k = m.k + 1 end
    end
end

-- État de traque d'un PNJ (tests, diagnostic), ou nil.
function Relations.huntMemory(id)
    return Relations.huntState.npcs[id]
end

LivingKnox.listen("npcDied", "Relations.revenge", function(info) LivingKnox.Relations.onNpcDied(info) end)
if Events ~= nil then
    LivingKnox.subscribe("OnCharacterDeath", "Relations.onCharacterDeath",
        function(chr) LivingKnox.Relations.onCharacterDeath(chr) end)
    LivingKnox.subscribe("EveryOneMinute", "Relations.huntPass", function() LivingKnox.Relations.huntPass() end)
end

return Relations
