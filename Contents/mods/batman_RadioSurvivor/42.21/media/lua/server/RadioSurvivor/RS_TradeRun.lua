-- Radio Survivor : suivi du passage réservé du passeur (E13-T03). Fiche : docs/conception/passeur-rendezvous.md.
-- La réservation et le rendez-vous sont tenus par RS_Trade (S.data.trade.run) ; ce fichier applique les règles du
-- serveur pendant la semaine et la nuit du rendez-vous. Autorité seulement (serveur MP, jeu local en solo).
--
-- - Réservation (Trade.onBooked, appelé par l'exécuteur de propose_trade) : repère du ponton envoyé à l'appelant
--   (RS_MapMarks.give, libellé traduit dans la langue de l'autorité) ; sans joueur en ligne, rien.
-- - Hélicoptère vanilla : signature OnWorldSound (source nil, étage 0, rayon et volume 500, base staging-effects.md)
--   -> Trade.noteHelicopter (cordon monté d'un cran la première fois dans le passage).
-- - Règles, à chaque EveryTenMinutes, pour le passage attendu (state booked), à partir de WARN_HOURS avant la
--   fenêtre : patrouille (Trade.patrolRoll < PATROL_CHANCE du cordon, reproductible), hélicoptère entendu depuis
--   HELI_HOURS avant la fenêtre, orage en cours (ClimateManager.getIsThunderStorming, base api-42-21.md) : annulation.
--   Fenêtre finie sans signal : annulation « late » (le passeur est reparti).
-- - Annulation : Trade.cancelRun (offre du passage close « cancelled ») puis annonce à la radio sur la fréquence de la
--   voix qui a pris la réservation (RS_RadioServer.air, texte traduit dans la langue de l'autorité, comme le texte
--   fixe des appels spontanés) ; voix absente ou hors antenne : journal seulement. Un retard découvert plus de
--   ANNOUNCE_LATE_HOURS après la fin de la fenêtre (serveur arrêté) n'est pas annoncé.
-- - Signal pendant la fenêtre, avec un membre de l'équipe à moins de RADIUS cases du ponton : fusée rouge de Signal
--   Smoke (événement « started » de couleur red à moins de RADIUS cases, mod requis) ou lampe allumée tenue en
--   main (InventoryItem.isEmittingLight ; état allumé reçu par le serveur, SyncItemActivatedPacket.processServer)
--   -> Trade.arrive : la barque est au ponton ; l'échange sans contact est dans RS_TradeExchange.lua (E13-T04), qui
--   dit son issue par Run.say.
-- Messages de journal en anglais ; aucun secret ni coordonnée dans les textes diffusés. Code ASCII seulement.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Trade = require "RadioSurvivor/RS_Trade"
local MapMarks = require "RadioSurvivor/RS_MapMarks"
local Factions = require "RadioSurvivor/RS_Factions"

local Run = {}

Run.RADIUS = 15                  -- cases autour du ponton (Trade.PIER)
Run.WARN_HOURS = 1               -- règles appliquées dès 00:00 : l'annonce précède le départ des joueurs
Run.HELI_HOURS = 3               -- hélicoptère entendu depuis 22:00 : rendez-vous annulé
Run.ANNOUNCE_LATE_HOURS = 2
Run.PATROL_CHANCE = { 5, 15, 30 }  -- pour cent, par cordon (Trade.CORDONS : calme, patrouilles, serré)
Run.SIGNAL_COLOR = "red"
Run.COLOR_TOLERANCE = 0.02
Run.REASONS = { "patrol", "helicopter", "storm", "late" }
Run.KEY = "IGUI_RS_TradeRun_"
-- Textes anglais si les traductions du mod manquent sur cette machine (getTextOrNull nil après rechargement).
Run.FALLBACK = {
    Pier = "Smuggler's landing",
    Cancel_patrol = "No run tonight. A patrol boat is working the river. Stay off the bank. Over.",
    Cancel_helicopter = "No run tonight. A helicopter is sweeping the river. Keep your heads down. Over.",
    Cancel_storm = "No run tonight. There is a storm on the river, no boat crosses in that. Over.",
    Cancel_late = "I waited at the landing and nobody showed the signal. I am gone. Over.",
    -- E13-T04 : issue de l'échange sur la berge (RS_TradeExchange.lua).
    Done = "Your goods are in the bag on the landing. Pleasure doing business. Over.",
    Cheated = "You tried to short me. Your bag stays where it is, no deal, and I will remember it. Over.",
    Cancel_nodrop = "Nobody left me a bag at the landing. I am gone. Over.",
}

local function log(msg) Const.log("trade run: " .. msg) end

-- ================================================================ textes

local reloaded = false

-- Texte de la clé Run.KEY .. name dans la langue de cette machine ; serveur MP : traductions des mods rechargées une
-- fois (Translator.loadFiles, base api-42-21.md) ; repli anglais Run.FALLBACK.
function Run.text(name)
    local key = Run.KEY .. name
    local value = getTextOrNull and getTextOrNull(key) or nil
    if value == nil and isServer() and not reloaded and Translator and Translator.loadFiles then
        reloaded = true
        Translator.loadFiles()
        log("mod translations reloaded on the server")
        value = getTextOrNull(key)
    end
    return value or Run.FALLBACK[name] or key
end

-- ================================================================ joueurs et équipe

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

local function near(x, y)
    local p = Trade.PIER
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) <= Run.RADIUS * Run.RADIUS
end

-- Le joueur est-il un membre vivant de l'équipe du passage, au ponton ?
local function memberAtPier(player, run)
    if player == nil or (player.isDead and player:isDead()) then return false end
    if not near(player:getX(), player:getY()) then return false end
    return Trade.teamOf(Factions.keyOf(player), player) == run.team
end

local function anyMemberAtPier(run)
    for _, p in ipairs(players()) do
        if memberAtPier(p, run) then return true end
    end
    return false
end

-- Lampe allumée tenue en main par un membre de l'équipe au ponton.
local function lampAtPier(run)
    for _, p in ipairs(players()) do
        if memberAtPier(p, run) then
            local hands = { p:getPrimaryHandItem(), p:getSecondaryHandItem() }
            for i = 1, 2 do
                local item = hands[i]
                if item and item.isEmittingLight and item:isEmittingLight() then return true end
            end
        end
    end
    return false
end

-- ================================================================ annonces et règles

-- Texte Run.KEY .. name dit sur la fréquence de la voix du passage ; what : objet du message de journal. Rend true si
-- mis en file.
function Run.say(run, name, what)
    what = what or name
    local radio = RS_RadioServer
    local khz = type(radio) == "table" and type(radio.frequency) == "function" and run.voice
        and radio.frequency(run.voice) or nil
    if not khz then
        log(what .. " of run " .. tostring(run.passage) .. " not aired: voice '" .. tostring(run.voice)
            .. "' is off the air")
        return false
    end
    radio.air(khz, { "<fzzt>", Run.text(name), "<szzt>" })
    log(what .. " of run " .. tostring(run.passage) .. " aired (" .. name .. ")")
    return true
end

-- Annonce d'une annulation sur la fréquence de la voix du passage. Rend true si mise en file.
function Run.announce(run, reason)
    return Run.say(run, "Cancel_" .. reason, "cancellation")
end

-- Annule le passage attendu et l'annonce (sauf announce == false). Rend la copie du passage annulé, ou nil.
function Run.cancel(reason, announce)
    local run = Trade.cancelRun(reason)
    if run and announce ~= false then Run.announce(run, reason) end
    return run
end

local function stormy()
    local cm = getClimateManager and getClimateManager()
    return cm ~= nil and cm:getIsThunderStorming() == true
end

local function patrolChance(cordon)
    for i, level in ipairs(Trade.CORDONS) do
        if level == cordon then return Run.PATROL_CHANCE[i] or 0 end
    end
    return 0
end

-- Règles du passage attendu à l'heure du monde `hours`. Rend la raison d'une annulation, "arrived", ou nil.
function Run.update(hours)
    hours = hours or Trade.worldHours()
    local run = Trade.lastRun()
    if run == nil or run.state ~= "booked" or type(run.start) ~= "number" then return nil end
    local stop = run.start + Trade.WINDOW_HOURS
    if hours >= stop then
        Run.cancel("late", hours < stop + Run.ANNOUNCE_LATE_HOURS)
        return "late"
    end
    if hours < run.start - Run.WARN_HOURS then return nil end
    if Trade.patrolRoll(run.passage) < patrolChance(Trade.cordon(run.passage)) then
        Run.cancel("patrol")
        return "patrol"
    end
    if Trade.helicopterSince(run.start - Run.HELI_HOURS) then
        Run.cancel("helicopter")
        return "helicopter"
    end
    if stormy() then
        Run.cancel("storm")
        return "storm"
    end
    if hours >= run.start and lampAtPier(run) and Trade.arrive("lamp") then return "arrived" end
    return nil
end

local function onEveryTenMinutes()
    Run.update()
end

-- ================================================================ hélicoptère

function Run.onWorldSound(x, y, z, radius, volume, source)
    if source ~= nil or z ~= 0 or radius ~= 500 or volume ~= 500 then return end
    Trade.noteHelicopter(Trade.worldHours())
end

-- ================================================================ Signal Smoke (mod requis)

local lib, subscribed = nil, nil

-- Module public de Signal Smoke (mod requis), ou nil s'il est inutilisable (installation cassée : erreur au
-- journal). Cherché une fois.
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

-- Événement de Signal Smoke : une fusée ou fumée rouge allumée près du ponton pendant la fenêtre, un membre de
-- l'équipe au ponton -> la barque arrive.
function Run.onSignal(event)
    if type(event) ~= "table" or event.type ~= "started" or type(event.entry) ~= "table" then return end
    local run = Trade.lastRun()
    if run == nil or run.state ~= "booked" or type(run.start) ~= "number" then return end
    local hours = Trade.worldHours()
    if hours < run.start or hours >= run.start + Trade.WINDOW_HOURS then return end
    local e = event.entry
    if not isColor(e.color, Run.SIGNAL_COLOR) or not near(e.x, e.y) then return end
    if anyMemberAtPier(run) then Trade.arrive("flare") end
end

-- ================================================================ réservation

-- Trade.onBooked : repère du ponton sur la carte de l'appelant qui a réservé.
function Run.onBooked(run, ctx)
    local player = type(ctx) == "table" and ctx.player or nil
    if player == nil or type(run) ~= "table" then return end
    local p = Trade.PIER
    MapMarks.give(player, ctx.cid, ctx.khz, { x = p.x, y = p.y, z = p.z, label = Run.text("Pier") })
end

-- Abonnements (une fois) : rappel de réservation, horloge, hélicoptère, Signal Smoke.
local installed = false
function Run.install()
    Trade.onBooked = Run.onBooked
    local mod = Run.library()
    if mod and subscribed ~= mod then
        mod.onSignal(Run.onSignal)
        subscribed = mod
    end
    if installed then return end
    installed = true
    if Events.EveryTenMinutes then Events.EveryTenMinutes.Add(onEveryTenMinutes) end
    if Events.OnWorldSound then Events.OnWorldSound.Add(Run.onWorldSound) end
end

-- Bancs : oublie le module Signal Smoke retenu (l'abonnement à un module précédent reste).
function Run.resetForTests()
    lib, subscribed = nil, nil
end

Run.install()

return Run
