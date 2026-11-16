-- Radio Survivor : suivi des passages reserves des marchands (E13-T03 ; E20-T07 : un passage par marchand, causes et
-- signal donnes par le mode d'arrivee de la fiche, registre RS_TradeArrivals). Fiche :
-- docs/annexes/conception/passeur-rendezvous.md. La reservation et le rendez-vous sont tenus par RS_Trade ; ce fichier
-- applique les regles du serveur pendant la periode et la nuit du rendez-vous. Autorite seulement (serveur MP, jeu
-- local en solo). Racine de composition du troc : install branche les voix chargees (RS_Personas) dans RS_Trade.
--
-- - Reservation (Trade.onBooked, appele par l'executeur de propose_trade) : repere du lieu du rendez-vous envoye a
--   l'appelant (RS_MapMarks.give, libelle traduit dans la langue de l'autorite) ; sans joueur en ligne, rien.
-- - Accord fige (Trade.onAgreed, E23-T06) : ligne « trade » de l'historique radio du personnage de l'appelant
--   (RS_RadioLog.add, texte Trade.agreedText : les deux listes, jamais de points), sur la frequence de la reponse.
-- - Regles, a chaque EveryTenMinutes et pour chaque marchand dont le passage est attendu (state booked) : fenetre
--   finie sans signal -> annulation « late » ; a partir de WARN_HOURS avant la fenetre, chaque cause du mode
--   d'arrivee dans son ordre (check(world), RS_TradeCauses : patrouille 1 sur 75, helicoptere 1 sur 100, orage reel)
--   -> annulation de ce nom.
-- - Annulation : Trade.cancelRun puis annonce a la radio sur la frequence de la voix du marchand (RS_RadioServer.air,
--   texte IGUI_RS_TradeRun_Cancel_<cause> traduit dans la langue de l'autorite, repli anglais de la cause) ; voix hors
--   antenne : journal seulement. Un retard decouvert plus de ANNOUNCE_LATE_HOURS apres la fin de la fenetre n'est pas
--   annonce. Annulation par une cause du mode (ADR D05) : annonce repetee chaque heure de jeu jusqu'au debut de la
--   fenetre (Trade.noteAnnounced garde l'heure de la derniere) ; aucun depot touche, aucune penalite.
-- - Signal pendant la fenetre, si le mode l'attend (registre des detecteurs, Run.registerSignal ; E20-T11) : lamp
--   (lampe allumee tenue en main par un membre de l'equipe a moins de RADIUS cases du lieu,
--   InventoryItem.isEmittingLight), flare (evenement « started » rouge de Signal Smoke, mod requis, a moins de RADIUS
--   cases, un membre present), hour (aucun signal : le marchand vient au debut de la fenetre) -> Trade.arrive et son
--   d'approche du mode joue au lieu (port useSound, RS_TradeSound par defaut). L'echange sans contact est dans
--   RS_TradeExchange.lua, qui dit son issue par Run.say et joue le son de depart par Run.playSound.
-- - Textes dits : variante du mode d'arrivee (cle IGUI_RS_TradeRun_<nom>_<mode>, puis lines du mode) avant le texte
--   commun du nom (Run.textFor).
-- Messages de journal en anglais ; aucun secret ni coordonnee dans les textes diffuses. Code ASCII seulement.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Trade = require "RadioSurvivor/RS_Trade"
local Arrivals = require "RadioSurvivor/RS_TradeArrivals"
local MapMarks = require "RadioSurvivor/RS_MapMarks"
local Factions = require "CoreAI/CA_Teams" -- E18-T20: team ids kept by the core mod
local Sound = require "RadioSurvivor/RS_TradeSound"

local Run = {}

Run.RADIUS = 15                  -- cases autour du lieu du rendez-vous
Run.WARN_HOURS = 3               -- causes appliquees trois heures avant la fenetre : annonce, puis rappels
Run.REPEAT_HOURS = 1             -- rappel d'une annulation par cause, chaque heure de jeu jusqu'au rendez-vous
Run.ANNOUNCE_LATE_HOURS = 2
Run.SIGNAL_COLOR = "red"
Run.COLOR_TOLERANCE = 0.02
-- Signaux reconnus par ce suivi (champ signals d'un mode d'arrivee) : nom -> true, tenu par Run.registerSignal.
Run.SIGNALS = {}
Run.KEY = "IGUI_RS_TradeRun_"
-- Textes anglais si les traductions du mod manquent sur cette machine (getTextOrNull nil apres rechargement). Les
-- annonces des causes ont leur repli dans le mode d'arrivee.
Run.FALLBACK = {
    Pier = "Smuggler's landing",
    Cancel_late = "I waited at the landing and nobody showed the signal. I am gone. Over.",
    -- E13-T04 : issue de l'echange au lieu du rendez-vous (RS_TradeExchange.lua).
    Done = "Your goods are in the bag on the landing. Pleasure doing business. Over.",
    Cheated = "You did not leave all we agreed. I keep what you left, no goods, and I will remember it. Over.",
    Cancel_nodrop = "Nobody left me the payment at the landing. I am gone. Over.",
    -- E23-T07 : jamais tranquille au lieu (RS_TradeExchange.WAIT_HOURS) : il repart sans rien toucher.
    Cancel_watched = "Someone stayed in sight of the landing the whole time. I could not come close. I am gone. Over.",
}

local function log(msg) Const.log("trade run: " .. msg) end

-- ================================================================ ports

local play = Sound.playAt

-- Son joue a un lieu : function(name, { x, y, z }). Bancs : doublure ; jeu : RS_TradeSound.playAt.
function Run.useSound(fn)
    play = fn or Sound.playAt
end

local function modeOf(id)
    local spec = Trade.specOf(id)
    return spec and Arrivals.get(spec.arrival) or nil
end

-- Son `which` (approach, leave) du mode d'arrivee du marchand du passage, joue au lieu du rendez-vous.
function Run.playSound(run, which)
    local mode = type(run) == "table" and modeOf(run.voice) or nil
    local name = mode and mode.sounds[which]
    if type(name) ~= "string" or type(run.landing) ~= "table" then return false end
    play(name, run.landing)
    return true
end

-- ================================================================ textes

local reloaded = false

-- Traduction de la cle Run.KEY .. name dans la langue de cette machine, ou nil ; serveur MP : traductions des mods
-- rechargees une fois (Translator.loadFiles, base api-42-21.md).
local function translated(name)
    local key = Run.KEY .. name
    local value = getTextOrNull and getTextOrNull(key) or nil
    if value == nil and isServer() and not reloaded and Translator and Translator.loadFiles then
        reloaded = true
        Translator.loadFiles()
        log("mod translations reloaded on the server")
        value = getTextOrNull(key)
    end
    return value
end

-- Texte de la cle Run.KEY .. name ; repli anglais fallback, puis Run.FALLBACK.
function Run.text(name, fallback)
    return translated(name) or fallback or Run.FALLBACK[name] or (Run.KEY .. name)
end

-- Texte `name` dit pour le passage run : variante de son mode d'arrivee (traduction name_<mode>, puis lines du mode),
-- sinon Run.text(name, fallback).
function Run.textFor(run, name, fallback)
    local spec = type(run) == "table" and Trade.specOf(run.voice) or nil
    local mode = spec and Arrivals.get(spec.arrival) or nil
    if mode then
        local own = translated(name .. "_" .. spec.arrival) or (type(mode.lines) == "table" and mode.lines[name])
        if type(own) == "string" then return own end
    end
    return Run.text(name, fallback)
end

-- ================================================================ joueurs et equipe

local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers and getOnlinePlayers()
        if list then
            for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        end
    else
        local p = getPlayer and getPlayer()
        if p then out[1] = p end
    end
    return out
end

local function near(run, x, y)
    local p = run.landing
    if type(p) ~= "table" or type(x) ~= "number" or type(y) ~= "number" then return false end
    return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) <= Run.RADIUS * Run.RADIUS
end

-- Le joueur est-il un membre vivant de l'equipe du passage, au lieu du rendez-vous ?
local function memberAtLanding(player, run)
    if player == nil or (player.isDead and player:isDead()) then return false end
    if not near(run, player:getX(), player:getY()) then return false end
    return Trade.teamOf(Factions.keyOf(player), player) == run.team
end

local function anyMemberAtLanding(run)
    for _, p in ipairs(players()) do
        if memberAtLanding(p, run) then return true end
    end
    return false
end

-- Lampe allumee tenue en main par un membre de l'equipe au lieu du rendez-vous.
local function lampAtLanding(run)
    for _, p in ipairs(players()) do
        if memberAtLanding(p, run) then
            local hands = { p:getPrimaryHandItem(), p:getSecondaryHandItem() }
            for i = 1, 2 do
                local item = hands[i]
                if item and item.isEmittingLight and item:isEmittingLight() then return true end
            end
        end
    end
    return false
end

-- Aucun signal attendu : le marchand vient des que la fenetre est ouverte.
local function windowOpen()
    return true
end

-- ================================================================ detecteurs de signal

-- Detecteurs sondes a chaque EveryTenMinutes pendant la fenetre, dans l'ordre d'inscription : { name, poll }.
local polled = {}

-- Inscrit le signal name (nom d'un champ signals des modes d'arrivee). poll(run) -> true quand le signal est donne,
-- sonde pendant la fenetre ; false : signal recu par un evenement (flare, Run.onSignal). Rend false si deja inscrit.
function Run.registerSignal(name, poll)
    if type(name) ~= "string" or Run.SIGNALS[name] or (poll ~= false and type(poll) ~= "function") then
        log("ERROR signal detector '" .. tostring(name) .. "' refused")
        return false
    end
    Run.SIGNALS[name] = true
    if poll then polled[#polled + 1] = { name = name, poll = poll } end
    return true
end

Run.registerSignal("lamp", lampAtLanding)
Run.registerSignal("flare", false)
Run.registerSignal("hour", windowOpen)

-- ================================================================ annonces et regles

-- Texte Run.KEY .. name dit sur la frequence de la voix du passage ; what : objet du message de journal ; fallback :
-- repli anglais. Rend true si mis en file.
function Run.say(run, name, what, fallback)
    what = what or name
    local radio = RS_RadioServer
    local khz = type(radio) == "table" and type(radio.frequency) == "function" and run.voice
        and radio.frequency(run.voice) or nil
    if not khz then
        log(what .. " of run " .. tostring(run.passage) .. " not aired: voice '" .. tostring(run.voice)
            .. "' is off the air")
        return false
    end
    radio.air(khz, { "<fzzt>", Run.textFor(run, name, fallback), "<szzt>" })
    log(what .. " of run " .. tostring(run.passage) .. " of " .. tostring(run.voice) .. " aired (" .. name .. ")")
    return true
end

local function causeOf(id, reason)
    local mode = modeOf(id)
    for _, cause in ipairs(mode and mode.causes or {}) do
        if cause.name == reason then return cause end
    end
    return nil
end

-- Annonce d'une annulation sur la frequence de la voix du passage. Rend true si mise en file.
function Run.announce(run, reason)
    local cause = causeOf(run.voice, reason)
    return Run.say(run, "Cancel_" .. reason, "cancellation", cause and cause.fallback or nil)
end

-- Annule le passage attendu du marchand id et l'annonce (sauf announce == false) ; heure de l'annonce notee. Rend la
-- copie annulee, ou nil.
function Run.cancel(id, reason, announce, hours)
    local run = Trade.cancelRun(id, reason)
    if run and announce ~= false then
        Run.announce(run, reason)
        Trade.noteAnnounced(id, hours or Trade.worldHours())
    end
    return run
end

-- Rappel de l'annulation d'un passage par une cause du mode (ADR D05) : chaque REPEAT_HOURS jusqu'au debut de la
-- fenetre. Rend true si le rappel est dit.
function Run.remind(id, hours)
    hours = hours or Trade.worldHours()
    local run = Trade.lastRun(id)
    if run == nil or run.state ~= "cancelled" or type(run.start) ~= "number" or hours >= run.start
            or type(run.announcedAt) ~= "number" or hours < run.announcedAt + Run.REPEAT_HOURS - 1e-9
            or causeOf(id, run.reason) == nil then
        return false
    end
    Run.announce(run, run.reason)
    Trade.noteAnnounced(id, hours)
    return true
end

-- Arrivee du marchand au lieu (signal how) : etat arrived et son d'approche. Rend true si le passage etait attendu.
function Run.arrive(id, how)
    if not Trade.arrive(id, how) then return false end
    Run.playSound(Trade.lastRun(id), "approach")
    return true
end

local function stormy()
    local cm = getClimateManager and getClimateManager()
    return cm ~= nil and cm:getIsThunderStorming() == true
end

-- Monde vu par les causes d'un mode d'arrivee (contrat : RS_TradeArrivals).
local function worldOf(id, run, hours)
    local function roll(salt, n) return Trade.runRoll(id, run.passage, salt, n) end
    return { id = id, run = run, hours = hours, roll = roll, stormy = stormy }
end

-- Regles du passage attendu du marchand id a l'heure `hours`. Rend la raison d'une annulation, "arrived", ou nil.
function Run.updateTrader(id, hours)
    hours = hours or Trade.worldHours()
    local run = Trade.lastRun(id)
    local spec, mode = Trade.specOf(id), modeOf(id)
    if run == nil or run.state ~= "booked" or type(run.start) ~= "number" or not spec or not mode then return nil end
    local stop = run.start + spec.hours
    if hours >= stop then
        Run.cancel(id, "late", hours < stop + Run.ANNOUNCE_LATE_HOURS)
        return "late"
    end
    if hours < run.start - Run.WARN_HOURS then return nil end
    local world = worldOf(id, run, hours)
    for _, cause in ipairs(mode.causes) do
        if cause.check(world) then
            Run.cancel(id, cause.name, true, hours)
            return cause.name
        end
    end
    if hours < run.start then return nil end
    for _, d in ipairs(polled) do
        if mode.signals[d.name] and d.poll(run) and Run.arrive(id, d.name) then return "arrived" end
    end
    return nil
end

-- Regles de tous les marchands, puis rappels des annulations.
function Run.update(hours)
    for _, id in ipairs(Trade.traderIds()) do
        Run.updateTrader(id, hours)
        Run.remind(id, hours)
    end
end

local function onEveryTenMinutes()
    Run.update()
end

-- ================================================================ Signal Smoke (mod requis)

local lib, subscribed = nil, nil

-- Module public de Signal Smoke (mod requis), ou nil s'il est inutilisable (erreur au journal). Cherche une fois.
function Run.library()
    if lib == nil then
        local mod = require "SignalSmoke/SignalSmoke"
        if type(mod) == "table" and type(mod.onSignal) == "function" and type(mod.COLORS) == "table" then
            lib = mod
        else
            lib = false
            log("ERROR required mod batman_SignalSmoke is broken: module SignalSmoke/SignalSmoke "
                .. "has no onSignal or COLORS")
        end
    end
    return lib or nil
end

local function isColor(color, name)
    local mod = Run.library()
    local ref = mod and mod.COLORS[name]
    if type(ref) ~= "table" or type(color) ~= "table" then return false end
    for _, k in ipairs({ "r", "g", "b" }) do
        if type(color[k]) ~= "number" or math.abs(color[k] - ref[k]) > Run.COLOR_TOLERANCE then return false end
    end
    return true
end

-- Fusee rouge pour le marchand id : passage attendu, fenetre ouverte, mode qui l'attend, pres du lieu, membre present.
local function flareFor(id, entry, hours)
    local run, spec, mode = Trade.lastRun(id), Trade.specOf(id), modeOf(id)
    if run == nil or run.state ~= "booked" or type(run.start) ~= "number" or not spec or not mode then return end
    if not mode.signals.flare or hours < run.start or hours >= run.start + spec.hours then return end
    if not near(run, entry.x, entry.y) or not anyMemberAtLanding(run) then return end
    Run.arrive(id, "flare")
end

-- Evenement de Signal Smoke : une fusee ou fumee rouge allumee.
function Run.onSignal(event)
    if type(event) ~= "table" or event.type ~= "started" or type(event.entry) ~= "table" then return end
    if not isColor(event.entry.color, Run.SIGNAL_COLOR) then return end
    local hours = Trade.worldHours()
    for _, id in ipairs(Trade.traderIds()) do flareFor(id, event.entry, hours) end
end

-- ================================================================ reservation

-- Trade.onBooked : repere du lieu du rendez-vous sur la carte de l'appelant qui a reserve.
function Run.onBooked(run, ctx)
    local player = type(ctx) == "table" and ctx.player or nil
    if player == nil or type(run) ~= "table" or type(run.landing) ~= "table" then return end
    local p = run.landing
    MapMarks.give(player, ctx.cid, ctx.khz, { x = p.x, y = p.y, z = p.z, label = Run.textFor(run, "Pier") })
end

-- Trade.onAgreed : accord fige inscrit dans le carnet du personnage de l'appelant (ligne « trade » de son historique
-- radio, sur la frequence de la reponse) ; sans personnage lie, rien. RS_RadioLog charge a l'appel (bancs sans
-- carnet).
function Run.onAgreed(offer, ctx)
    if type(offer) ~= "table" or type(ctx) ~= "table" or type(ctx.cid) ~= "string" or type(ctx.khz) ~= "number" then
        return false
    end
    local Log = require "RadioSurvivor/RS_RadioLog"
    return Log.add(ctx.cid, ctx.khz, "trade", Trade.agreedText(offer)) ~= nil
end

-- Racine de composition du troc et abonnements (une fois) : voix chargees, rappels de reservation et d'accord,
-- horloge, Signal Smoke.
local installed = false
function Run.install()
    Trade.useVoices(require "RadioSurvivor/RS_Personas")
    Trade.onBooked = Run.onBooked
    Trade.onAgreed = Run.onAgreed
    local mod = Run.library()
    if mod and subscribed ~= mod then
        mod.onSignal(Run.onSignal)
        subscribed = mod
    end
    if installed then return end
    installed = true
    if Events.EveryTenMinutes then Events.EveryTenMinutes.Add(onEveryTenMinutes) end
end

-- Bancs : oublie le module Signal Smoke retenu (l'abonnement a un module precedent reste).
function Run.resetForTests()
    lib, subscribed = nil, nil
end

Run.install()

return Run
