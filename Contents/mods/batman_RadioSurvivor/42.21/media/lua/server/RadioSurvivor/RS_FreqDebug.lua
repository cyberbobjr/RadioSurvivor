-- Radio Survivor : fréquences de la partie pour le panneau de debug (E05-T14). Doc :
-- docs/specifications-techniques/persona-format.md, section
-- « Panneau de debug des fréquences (E05-T14) ». Fenêtre : client/RadioSurvivor/RS_FreqDebugView.lua.
--
-- Les fréquences des voix sont tirées au hasard par partie (E05-T07, RS_Personas.lua) et restent un secret de partie :
-- aucune commande ne les envoie aux clients (E05-T08). Seule exception : la réponse de ce module, envoyée au SEUL
-- demandeur, et seulement s'il a le droit (FreqDebug.isAllowed, revérifié À CHAQUE requête sur l'autorité).
--
-- Droits : la règle des outils de debug Living Knox (LK13-T13, server/LivingKnox/LK_Admin.lua, Admin.isAllowed avec une
-- opération de DEBUG_OPS), recopiée ici pour garder un canal propre à RadioSurvivor (aucun appel à LK_Admin.lua, qui
-- peut évoluer pour ses propres opérations ; tests/test_rs_freqdebug.py compare les deux règles) :
--   - serveur MP : checkPermissions(joueur, Capability.PopmanManage) (rôle de la connexion, LuaManager.java:2913-2919 ;
--     rôles moderator et admin) ET getRole():hasCapability (checkPermissions rend vrai sans connexion trouvée) ;
--   - solo : mode debug exigé (isDebugEnabled) ;
--   - client MP : jamais (un client ne décide pas).
-- Refus : réponse { n, op, ok = false, err = "denied" } sans aucune donnée, une ligne WARNING par joueur et par
-- REFUSAL_LOG_MS au plus (refus tus comptés).
--
-- Contenu (lecture seule, copie de valeurs simples, kHz) : FreqDebug.view()
--   { enabled, voices = { { id, name, state, holds, fixed, frequencies, served, ranges = { { low, high } }, radio,
--     listen = { { from, to } } (minutes du jour ; vide = toujours), language, chronicler } } dans l'ordre de
--     chargement des fiches (RS_Personas.ids),
--     others = { { kind = "bulletin", voice, khz (nil : chroniqueur pas à l'antenne), hour } } : autres fréquences
--     du mod (bulletin du soir du chroniqueur, E14-T02 ; le mod n'a aucune chaîne hors des chaînes des voix) }.
-- frequencies = fréquences de la voix pour cette partie (fixes ou tirées) ; served = celles qu'une chaîne du module
-- sert réellement (une fréquence non servie : conflit avec une autre voix ou une chaîne étrangère, voix gone/dead).
--
-- Transport : MP, commande client "freqRequest" (module "RadioSurvivorDebug") { op = "frequencies", n } -> réponse
-- serveur "freqReply" au seul demandeur ; solo, appel direct de FreqDebug.request par la fenêtre (sendServerCommand
-- ne fait rien hors serveur). n = numéro de requête renvoyé tel quel (réponse périmée ignorée par la fenêtre).
-- Aucun envoi spontané : le serveur ne répond qu'à une requête, la fenêtre n'en envoie qu'ouverte.
-- Constantes avant la garde du client MP (lues par le banc ; la fenêtre garde ses copies, comparées par le banc).
-- Seul l'ASCII est utilisé dans le code (Kahlua). Messages de journal en anglais.

local FreqDebug = RS_FreqDebug or {}
RS_FreqDebug = FreqDebug

FreqDebug.MODULE = "RadioSurvivorDebug"
FreqDebug.CMD_REQUEST = "freqRequest"
FreqDebug.CMD_REPLY = "freqReply"
FreqDebug.CAPABILITY = "PopmanManage"
FreqDebug.OP = "frequencies"
FreqDebug.REFUSAL_LOG_MS = 60000
FreqDebug.NAME_MAX = 32

if isClient() then return FreqDebug end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Personas = require "RadioSurvivor/RS_Personas"

FreqDebug.refusals = FreqDebug.refusals or {}   -- nom du joueur -> { ms, muted }
FreqDebug.stats = FreqDebug.stats or { requests = 0, refused = 0, done = 0 }

local function log(msg)
    Const.log("frequency debug: " .. msg)
end

local function count(name)
    FreqDebug.stats[name] = (FreqDebug.stats[name] or 0) + 1
end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

-- Nom de compte d'un joueur, réduit à [%w_.-] et NAME_MAX caractères ; "?" sans nom.
function FreqDebug.nameOf(player)
    local name = nil
    if player ~= nil and player.getUsername ~= nil then name = player:getUsername() end
    if type(name) ~= "string" or name == "" then return "?" end
    name = string.gsub(name, "[^%w_%.%-]", "_")
    return string.sub(name, 1, FreqDebug.NAME_MAX)
end

-- Contrôle d'accès (autorité) : règle des opérations de debug de LK_Admin.isAllowed (voir l'en-tête). Rend vrai, ou
-- faux et la raison (anglais, journal seulement).
function FreqDebug.isAllowed(player)
    if player == nil then return false, "no player" end
    if isClient() then return false, "MP client" end
    if isServer() then
        local cap = Capability ~= nil and Capability[FreqDebug.CAPABILITY] or nil
        if cap == nil then return false, "capability " .. FreqDebug.CAPABILITY .. " unknown" end
        if checkPermissions(player, cap) ~= true then return false, "missing capability " .. FreqDebug.CAPABILITY end
        local role = player.getRole ~= nil and player:getRole() or nil
        if role == nil or role:hasCapability(cap) ~= true then
            return false, "missing capability " .. FreqDebug.CAPABILITY .. " (role)"
        end
        return true
    end
    if isDebugEnabled == nil or isDebugEnabled() ~= true then return false, "debug mode off (solo)" end
    return true
end

local function refuse(player, why)
    count("refused")
    local name = FreqDebug.nameOf(player)
    local r = FreqDebug.refusals[name]
    local t = getTimestampMs()
    if r ~= nil and t - r.ms < FreqDebug.REFUSAL_LOG_MS then
        r.muted = r.muted + 1
        return
    end
    local muted = r and r.muted or 0
    FreqDebug.refusals[name] = { ms = t, muted = 0 }
    log("WARNING: request refused for " .. name .. " (" .. tostring(why) .. ")"
        .. (muted > 0 and (", " .. muted .. " more refusal(s) not logged") or ""))
end

-- Vue (copies simples, sans objet Java) ------------------------------------------------------------------------

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

local function chronicler()
    local F = RS_Facts
    return type(F) == "table" and type(F.CHRONICLER) == "string" and F.CHRONICLER or nil
end

local function voiceView(id, chron)
    local sheet = Personas.get(id)
    if sheet == nil then return nil end
    local ranges, listen = {}, {}
    for i, r in ipairs(sheet.frequency_ranges or {}) do ranges[i] = { low = r.low, high = r.high } end
    for i, r in ipairs(sheet.listen or {}) do listen[i] = { from = r.from, to = r.to } end
    return { id = id, name = sheet.name, state = sheet.state, holds = Personas.holdsFrequencies(sheet) == true,
        fixed = #ranges == 0, frequencies = copyList(Personas.frequencies(id)), served = copyList(Personas.served(id)),
        ranges = ranges, radio = sheet.radio, listen = listen, language = sheet.language, chronicler = id == chron }
end

-- Toutes les fréquences de la partie (voir l'en-tête). Lecture seule : rien n'est relu ni écrit.
function FreqDebug.view()
    local chron = chronicler()
    local voices = {}
    for _, id in ipairs(Personas.ids()) do
        local v = voiceView(id, chron)
        if v ~= nil then voices[#voices + 1] = v end
    end
    local others = {}
    if chron ~= nil then
        local radio = RS_RadioServer
        local khz = type(radio) == "table" and type(radio.frequency) == "function" and radio.frequency(chron) or nil
        local F = RS_Facts
        local hour = type(F.chronicleHour) == "function" and F.chronicleHour() or nil
        others[#others + 1] = { kind = "bulletin", voice = chron, khz = khz, hour = hour }
    end
    return { enabled = Const.isEnabled() == true, voices = voices, others = others }
end

-- Requête ------------------------------------------------------------------------------------------------------

-- Traite une requête de player. args = { op, n }. Rend la réponse { n, op, ok, err } ou { n, op, ok = true, enabled,
-- voices, others } (table neuve de valeurs simples, prête à envoyer au seul demandeur).
function FreqDebug.request(player, args)
    count("requests")
    if type(args) ~= "table" then args = {} end
    local op = type(args.op) == "string" and args.op or nil
    local reply = { n = isInt(args.n, 0, 2147483647) and args.n or 0, op = op, ok = false }
    local allowed, why = FreqDebug.isAllowed(player)
    if not allowed then
        refuse(player, why)
        reply.err = "denied"
        return reply
    end
    if op ~= FreqDebug.OP then
        reply.err = "unknown request"
        return reply
    end
    count("done")
    reply.ok = true
    for k, v in pairs(FreqDebug.view()) do reply[k] = v end
    return reply
end

function FreqDebug.onClientCommand(module, command, player, args)
    if module ~= FreqDebug.MODULE or command ~= FreqDebug.CMD_REQUEST or not isServer() or player == nil then return end
    sendServerCommand(player, FreqDebug.MODULE, FreqDebug.CMD_REPLY, FreqDebug.request(player, args))
end

-- Une seule inscription, même si le fichier est relu (la fonction appelée est toujours la dernière version).
if Events ~= nil and Events.OnClientCommand ~= nil and isServer() and not FreqDebug.subscribed then
    FreqDebug.subscribed = true
    Events.OnClientCommand.Add(function(module, command, player, args)
        RS_FreqDebug.onClientCommand(module, command, player, args)
    end)
end

return FreqDebug
