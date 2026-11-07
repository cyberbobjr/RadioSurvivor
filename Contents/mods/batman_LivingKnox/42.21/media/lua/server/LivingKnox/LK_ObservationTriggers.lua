-- Living Knox : déclencheurs des observations des PNJ (E08-T07, E08-T08 ; dans Living Knox depuis E18-T27).
-- Autorité seulement. Chaque déclencheur enregistre un fait de la liste fermée d'E08-T01 par LK_Observations.record,
-- chez les seuls témoins admissibles, et seulement pour des fiches existantes et vivantes de l'hôte de la parole
-- (Talk.host : carnet de RadioSurvivor ou Living Knox seul ; record refuse une fiche inconnue : aucun déclencheur ne
-- crée de fiche). Lieu = maille Obs.area (jamais de coordonnée exacte) ; jour = jour de jeu (1 = premier jour). La clé
-- fait|sujet|jour|lieu de LK_Observations évite tout doublon par témoin.
--
--   player_return  sondage de LK_Talk.turns (une fois par seconde) : un personnage déjà connu d'une fiche (contact de
--                  l'hôte, host.knows) revient à portée d'audition de son corps (Provider.hears, le PNJ écoute) après
--                  au moins returnHours heures de jeu hors de portée. Témoin : cette fiche. Sujet : le personnage.
--                  Dernière heure de jeu à portée gardée dans l'état privé de la parole (Talk.data.nearHours) ; le
--                  premier passage à portée n'est pas un retour.
--   mission_done   écouteur de résultat du moteur des missions (RC_Missions.addResultListener), mission réussie :
--                  chez le PNJ demandeur (fiche de l'hôte ; une voix radio n'en a pas, rien n'est enregistré). Un fait
--                  par participant (sujet = personnage) ; lieu = corps du demandeur s'il est chargé.
--   group_death    fait "memberDied" de Living Knox (LK_Core.publish). Corps présent (offscreen = false) : fiches des
--                  membres du même groupe (Provider.npc(...).group) dont le corps chargé voit le mort (même règle que
--                  Provider.near, qui refuse une cible morte : même étage, witnessRange cases, CanSee). Mort hors écran
--                  (offscreen = true, simulation abstraite) : fiches des membres présents au foyer (info.witnesses),
--                  lieu = maille du foyer. Sujet : fiche du mort, sinon <groupe>-<membre>.
--   assault_seen   fait "assaultSeen" de Living Knox (LK_Hostility.record avec witnessed = true, faits hit, shot,
--                  kill) : fiches des témoins nommés (info.witnesses). Sujet : personnage du carnet (clé de joueur).
-- Living Knox publie, ce fichier s'abonne (link).
--
-- Déclencheurs du monde (E08-T08), sans dépendance au moteur de PNJ autre que Provider.presence (facultatif) :
--   weather        sondage EveryHours (rien sur un serveur vide en pause : l'heure n'avance pas) : période météo en
--                  cours d'orage (ClimateManager.getIsThunderStorming ; sujet tropical_storm si tempête tropicale,
--                  sinon storm) ou de blizzard (sujet blizzard). Un épisode = jour de son début, gardé dans l'état
--                  privé (Talk.data.worldEvents) : une seule observation par fiche même s'il passe minuit. Pas de
--                  brouillard (matinal presque chaque jour, intensité qui dépend du réglage graphique fogQuality,
--                  ClimateManager.java:1307).
--   power_cut      sondage EveryHours : passage du réseau électrique global de présent à absent
--                  (SandboxOptions.doesPowerGridExist, sans case chargée), une seule fois par monde ; aucun passage
--                  vu (monde déjà sans courant au premier sondage) : rien. Sujet power.
--   helicopter     OnWorldSound sur l'autorité : signature du son de monde de l'hélicoptère vanilla (source nil,
--                  z 0, rayon et volume 500, Helicopter.java:218, environ toutes les 10 s pendant un passage ; seul
--                  appel de ce genre dans le Java 42.21). Le champ IsoWorld.helicopter n'est pas lisible depuis Lua
--                  (Kahlua n'expose que les méthodes d'une instance). Épisode = jour et maille du premier son, fini
--                  après helicopterGapHours sans son. Sujet helicopter.
--   Témoins (au plus maxNpcs fiches, les plus récemment vues d'abord) : fiches vivantes de l'hôte dont le PNJ n'est
--   pas en expédition (Provider.presence ; corps chargé = présent) ; pour l'hélicoptère, en plus, corps chargé ou
--   foyer à moins de helicopterRange cases d'un son. Lieu : worldPlace pour un événement global (même clé pour
--   tous les témoins), maille du premier son pour l'hélicoptère.
if isClient() then return end

require 'LivingKnox/LK_Core'
local Talk = require 'LivingKnox/LK_TalkHost'
local Speech = require 'RadioSurvivorCore/RC_SpeechConfig'
local M = require 'RadioSurvivorCore/RC_Missions'
local World = require 'RadioSurvivorCore/RC_WorldFacts'
require 'LivingKnox/LK_Observations'
local Obs = LivingKnox.Observations
local P = Talk.provider

local Triggers = LivingKnox.ObservationTriggers or {linked = false}
LivingKnox.ObservationTriggers = Triggers
Talk.observationTriggers = Triggers
local B = Obs.CFG
local UNKNOWN_PLACE = 'unknown place'

-- Heure de jeu (âge du monde, entier), ou nil sans horloge ; météo et réseau (lectures du mod commun).
Triggers.worldHour = World.hour
Triggers.weatherNow = World.weatherNow
Triggers.gridPower = World.gridPower

local function ready() return Talk.host ~= nil and Talk.data ~= nil end
local function dirty() Talk.dirty = true end
local function objects() return Talk.host.objects() or {} end

local function dayOf(hour) return math.floor(hour / 24) + 1 end

local function validDay(day)
    return type(day) == 'number' and day == day and day >= 0 and day == math.floor(day) and day <= 1000000
end

local function placeOf(object)
    if not object then return nil end
    return Obs.area(object:getX(), object:getY())
end

-- Fiche existante de l'identifiant fournisseur id (incarnation courante ou dernière connue), sans en créer.
local function ficheOf(id)
    if id == nil or not ready() then return nil end
    local fiche = Talk.host.find(id)
    if fiche then return fiche end
    for _, candidate in pairs(Talk.host.fiches()) do
        if candidate.incarnation == id then return candidate end
    end
    return nil
end

-- Le corps a voit la scène du corps b (b peut être mort) : règle de Provider.near sans le test isDead de la cible.
local function sees(a, b, range)
    if not a or not b or a:isDead() or not a:getSquare() or not b:getSquare() then return false end
    if math.floor(a:getZ()) ~= math.floor(b:getZ()) then return false end
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    if dx * dx + dy * dy > range * range then return false end
    return a:CanSee(b)
end

local function record(ficheId, fact, subject, day, place)
    return Obs.record(ficheId, {fact = fact, subject = subject, day = day, place = place or UNKNOWN_PLACE})
end

-- Dernières heures à portée : { [personnage] = { [fiche] = heure } } (état privé de la parole).
local function nearHours(character)
    local all = Talk.data.nearHours
    if type(all) ~= 'table' then all = {}; Talk.data.nearHours = all end
    local mine = all[character]
    if type(mine) ~= 'table' then mine = {}; all[character] = mine end
    return mine
end

-- player_return : sondage sur les joueurs liés et les corps chargés des fiches (host.bound, host.objects).
-- Rend vrai si l'état a changé.
function Triggers.returns()
    if not ready() or not Talk.host.knows then return false end
    local hour = Triggers.worldHour()
    if not hour then return false end
    local changed = false
    local bodies = objects()
    for player, character in pairs(Talk.host.bound()) do
        if not player:isDead() then
            for fid, object in pairs(bodies) do
                if Talk.host.knows(character, fid) and P.hears(player, object, Speech.HEARING_RANGE) then
                    local hours = nearHours(character)
                    local last = hours[fid]
                    if type(last) == 'number' and hour - last >= B.returnHours then
                        local _, status = record(fid, 'player_return', character, dayOf(hour), placeOf(object))
                        if status == 'ok' or status == 'upgraded' then changed = true end
                    end
                    if last ~= hour then
                        hours[fid] = hour
                        dirty()
                    end
                end
            end
        end
    end
    return changed
end

-- Heures à portée des fiches qui ne sont plus suivies retirées (avec Obs.prune, LK_Talk.turns).
function Triggers.prune()
    if not ready() or type(Talk.data.nearHours) ~= 'table' then return end
    for _, hours in pairs(Talk.data.nearHours) do
        local doomed = {}
        for fid in pairs(hours) do if not Obs.tracked(fid) then doomed[#doomed + 1] = fid end end
        for _, fid in ipairs(doomed) do hours[fid] = nil; dirty() end
    end
end

-- mission_done : écouteur de résultat du moteur des missions (une fois par participant d'une mission close).
function Triggers.missionResult(_, mission, result, character)
    if result ~= 'success' or not ready() or (mission.donor or 'npc') ~= 'npc' then return end
    local fiche = Talk.host.fiche(mission.npc)
    if not fiche or type(character) ~= 'string' then return end
    local hour = Triggers.worldHour()
    if not hour then return end
    record(fiche.id, 'mission_done', character, dayOf(hour), placeOf(objects()[mission.npc]))
end

local function memberSubject(info, dead)
    if dead then return dead.id end
    local subject = tostring(info.group) .. '-' .. tostring(info.member)
    if string.find(subject, '^[%w_%-]+$') and string.len(subject) <= B.subjectChars then return subject end
    return nil
end

-- group_death : fait "memberDied" de Living Knox.
function Triggers.memberDied(info)
    if type(info) ~= 'table' or not ready() or type(info.group) ~= 'string' then return end
    local day = validDay(info.day) and info.day or nil
    if not day then
        local hour = Triggers.worldHour()
        if not hour then return end
        day = dayOf(hour)
    end
    local dead = ficheOf(info.npc)
    local subject = memberSubject(info, dead)
    if not subject then return end
    if info.offscreen then
        local place = Obs.area(info.x, info.y) or UNKNOWN_PLACE
        for _, npcId in ipairs(type(info.witnesses) == 'table' and info.witnesses or {}) do
            local fiche = ficheOf(npcId)
            if fiche and fiche ~= dead then record(fiche.id, 'group_death', subject, day, place) end
        end
        return
    end
    local body = info.body
    if not body then return end
    local place = placeOf(body)
    for fid, object in pairs(objects()) do
        local fiche = Talk.host.fiche(fid)
        local data = fiche and fiche ~= dead and fiche.incarnation ~= info.npc and not rawequal(object, body)
            and P.npc(fiche.incarnation)
        if data and tostring(data.group or '') == info.group and sees(object, body, B.witnessRange) then
            record(fid, 'group_death', subject, day, place)
        end
    end
end

local ASSAULTS = {hit = true, shot = true, kill = true}

-- assault_seen : fait "assaultSeen" de Living Knox.
function Triggers.assaultSeen(info)
    if type(info) ~= 'table' or not ready() or not ASSAULTS[info.fact] then return end
    if type(info.player) ~= 'string' or type(info.witnesses) ~= 'table' then return end
    local day = validDay(info.day) and info.day or nil
    if not day then
        local hour = Triggers.worldHour()
        if not hour then return end
        day = dayOf(hour)
    end
    local fiches = {}
    for _, npcId in ipairs(info.witnesses) do
        local fiche = ficheOf(npcId)
        if fiche then fiches[#fiches + 1] = fiche end
    end
    -- Un seul lieu pour tous les témoins (même clé) : la scène, sinon le premier témoin dont le corps est chargé.
    local place = Obs.area(info.x, info.y)
    if not place then
        local bodies = objects()
        for _, fiche in ipairs(fiches) do
            place = placeOf(bodies[fiche.id])
            if place then break end
        end
    end
    for _, fiche in ipairs(fiches) do record(fiche.id, 'assault_seen', info.player, day, place) end
end

-- ---------------------------------------------------------------- déclencheurs du monde (E08-T08)

local function worldEvents()
    if type(Talk.data.worldEvents) ~= 'table' then Talk.data.worldEvents = {} end
    return Talk.data.worldEvents
end

-- Témoins d'un événement du monde : fiches vivantes dont le PNJ est présent (corps chargé, ou pas en expédition
-- d'après Provider.presence) et qu'admet filter(fiche, body, presence) s'il est donné ; au plus maxNpcs, les plus
-- récemment vues d'abord. Travail proportionnel aux fiches du carnet, jamais à la population.
function Triggers.witnesses(filter)
    local list = {}
    if not ready() then return list end
    local bodies = objects()
    for fid, fiche in pairs(Talk.host.fiches()) do
        if type(fiche) == 'table' and fiche.alive ~= false then
            local body = bodies[fid]
            local presence = P.presence(fiche.incarnation)
            if (body or not (presence and presence.away == true)) and (not filter or filter(fiche, body, presence)) then
                list[#list + 1] = fiche
            end
        end
    end
    table.sort(list, function(a, b)
        local sa, sb = tonumber(a.seenAt) or 0, tonumber(b.seenAt) or 0
        if sa ~= sb then return sa > sb end
        return tostring(a.id) < tostring(b.id)
    end)
    while #list > B.maxNpcs do table.remove(list) end
    return list
end

local function recordAll(fiches, fact, subject, day, place)
    for _, fiche in ipairs(fiches) do record(fiche.id, fact, subject, day, place) end
end

-- Sondage EveryHours : météo et coupure du réseau.
function Triggers.hourly()
    if not ready() then return end
    local hour = Triggers.worldHour()
    if not hour then return end
    local ev = worldEvents()
    local kind = Triggers.weatherNow()
    if kind then
        if ev.weather ~= kind or not validDay(ev.weatherDay) then
            ev.weather, ev.weatherDay = kind, dayOf(hour)
            dirty()
        end
        -- Chaque heure de l'épisode, même clé : une fiche revenue d'expédition ou créée pendant l'orage l'apprend,
        -- les autres n'ont qu'un doublon refusé.
        recordAll(Triggers.witnesses(), 'weather', kind, ev.weatherDay, B.worldPlace)
    elseif ev.weather ~= nil then
        ev.weather, ev.weatherDay = nil, nil
        dirty()
    end
    local grid = Triggers.gridPower()
    if grid == true and ev.grid ~= true then
        ev.grid = true
        dirty()
    elseif grid == false and ev.grid ~= false then
        local cut = ev.grid == true and ev.powerCut == nil
        ev.grid = false
        dirty()
        if cut then
            ev.powerCut = dayOf(hour)
            recordAll(Triggers.witnesses(), 'power_cut', 'power', ev.powerCut, B.worldPlace)
        end
    end
end

-- OnWorldSound (x, y, z, radius, volume, source) : passage de l'hélicoptère vanilla.
function Triggers.worldSound(x, y, z, radius, volume, source)
    if source ~= nil or z ~= 0 or radius ~= B.helicopterSound or volume ~= B.helicopterSound then return end
    if not ready() or type(x) ~= 'number' or type(y) ~= 'number' then return end
    local hour = Triggers.worldHour()
    if not hour then return end
    local ev = worldEvents()
    local heli = ev.helicopter
    if type(heli) ~= 'table' or type(heli.hour) ~= 'number' or not validDay(heli.day) or type(heli.place) ~= 'string'
        or hour < heli.hour or hour - heli.hour > B.helicopterGapHours then
        heli = {day = dayOf(hour), place = Obs.area(x, y), hour = hour}
        ev.helicopter = heli
        Triggers.helicopterAt = nil
        dirty()
    elseif heli.hour ~= hour then
        heli.hour = hour
        dirty()
    end
    local now = getTimestampMs()
    if Triggers.helicopterAt and now - Triggers.helicopterAt < B.helicopterEveryMs then return end
    Triggers.helicopterAt = now
    local range2 = B.helicopterRange * B.helicopterRange
    local function hears(fiche, body, presence)
        local px, py
        if body then
            px, py = body:getX(), body:getY()
        elseif presence and type(presence.x) == 'number' and type(presence.y) == 'number' then
            px, py = presence.x, presence.y
        else
            return false
        end
        local dx, dy = px - x, py - y
        return dx * dx + dy * dy <= range2
    end
    recordAll(Triggers.witnesses(hears), 'helicopter', 'helicopter', heli.day, heli.place)
end

-- Abonnement aux faits de Living Knox (idempotent). Rend vrai si abonné.
function Triggers.link()
    if Triggers.linked then return true end
    LivingKnox.listen('memberDied', 'Observations.groupDeath', Triggers.memberDied)
    LivingKnox.listen('assaultSeen', 'Observations.assaultSeen', Triggers.assaultSeen)
    Triggers.linked = true
    return true
end

if not Triggers.subscribed then
    Triggers.subscribed = true
    Triggers.link()
    M.addResultListener(Triggers.missionResult)
    LivingKnox.subscribe('EveryHours', 'Observations.hourly', function() Triggers.hourly() end)
    LivingKnox.subscribe('OnWorldSound', 'Observations.worldSound', function(...) Triggers.worldSound(...) end)
end

return Triggers
