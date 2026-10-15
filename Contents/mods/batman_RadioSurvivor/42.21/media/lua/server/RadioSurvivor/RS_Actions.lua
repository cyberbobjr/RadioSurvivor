-- Radio Survivor : actions en liste fermée des voix radio (E07-T01, note de travail §02).
-- Le pont propose (réponse radio structurée, docs/protocole-carnet-v2.md « Réponse radio structurée »), le serveur
-- décide : chaque action est contrôlée contre le catalogue, la fiche de la voix, son exécuteur, ses paramètres, la
-- distance, le budget du jour de jeu et le délai propre à l'action, puis exécutée ou refusée avec une raison courte.
-- `say` n'y passe jamais : le texte est diffusé par RadioSurvivor_Server (airQueue).
-- Aucun exécuteur réel n'est enregistré ici : les tâches E07-T03..T06, E11, E12 et E13 branchent les leurs par
-- Actions.register. Sans exécuteur, une action du catalogue est refusée `not_available`. place_cache (E11-T06) :
-- exécuteur dans RS_Caches.lua (cache de la dernière mission de la voix pour l'appelant, une par mission).
--
-- Compteurs (budget du jour, dernier usage) : état privé du serveur, jamais en ModData globale. Rangés dans l'état
-- privé RS_State (S.data.actionCounters, fichier state-<partie>-<0|1>.txt, sauvegardé par la boucle du carnet quand
-- S.dirty) dès que cet état est chargé ; sinon (état pas encore initialisé ou bloqué) dans une table en mémoire,
-- perdue au redémarrage du serveur : un budget ou un délai repart alors de zéro.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Persona = require "RadioSurvivor/RS_Persona"
local S = require "RadioSurvivor/RS_State"
local ActionLog = require "RadioSurvivor/RS_ActionLog"

local Actions = {}

Actions.MAX_PER_REPLY = 3
Actions.MAX_PARAMS = 8
Actions.MAX_PARAM_CHARS = 64

-- Catalogue fermé : copie de RS_Persona.ACTIONS (même liste que bridge/persona_store.ACTIONS).
local CATALOGUE = {}
for _, name in ipairs(Persona.ACTIONS) do CATALOGUE[name] = true end

local executors = {}
-- Compteurs de secours quand RS_State n'est pas chargé (voir l'en-tête).
local memoryCounters = {}

function Actions.isKnown(name)
    return type(name) == "string" and CATALOGUE[name] == true
end

-- spec = { validate = function(params, ctx) -> ok (refus : bad_params) ; cooldownMs = n ; maxDistance = n ou nil ;
--          execute = function(params, ctx) -> ok, reason (refus : reason en [a-z_], sinon failed) }.
-- ctx : { caller, voice, sheet, player, khz, cid, day } (sheet : fiche de la voix, lue par un exécuteur qui en
-- dépend, comme les lieux de mark_map). Rend true si l'exécuteur est enregistré.
function Actions.register(name, spec)
    if name == "say" or not Actions.isKnown(name) or type(spec) ~= "table" or type(spec.execute) ~= "function" then
        Const.log("executor for '" .. tostring(name) .. "' refused (unknown action, say, or no execute function)")
        return false
    end
    executors[name] = spec
    return true
end

function Actions.unregister(name)
    executors[name] = nil
end

-- Banc : retire les exécuteurs et les compteurs en mémoire.
function Actions.resetForTests()
    executors, memoryCounters = {}, {}
end

local function counters()
    if S.data and not S.blocked then
        if type(S.data.actionCounters) ~= "table" then S.data.actionCounters = {} end
        return S.data.actionCounters, true
    end
    return memoryCounters, false
end

local function counterOf(voice, name)
    local all, persistent = counters()
    local byVoice = all[voice]
    if type(byVoice) ~= "table" then
        byVoice = {}
        all[voice] = byVoice
    end
    local c = byVoice[name]
    if type(c) ~= "table" then
        c = { day = "", used = 0, lastMs = nil }
        byVoice[name] = c
    end
    return c, persistent
end

-- Jour de jeu courant (AAAA-MM-JJ), clé du budget quotidien.
local function gameDay()
    local gt = getGameTime()
    return string.format("%04d-%02d-%02d", gt:getYear(), gt:getMonth() + 1, gt:getDay() + 1)
end

-- Actions allowed with another one of the sheet (E11-T13: a voice that gives missions takes their report on the
-- radio, report_mission, without listing it; same rule in the bridge, radio_bridge.IMPLIED_ACTIONS).
Actions.IMPLIED = { report_mission = "start_mission" }

local function allowedBy(sheet, name)
    if type(sheet) ~= "table" or type(sheet.actions) ~= "table" then return false end
    for _, a in ipairs(sheet.actions) do
        if a == name or a == Actions.IMPLIED[name] then return true end
    end
    return false
end

-- Paramètres d'une action proposée : tout champ sauf `type`, clés en chaînes courtes, valeurs scalaires (chaîne
-- d'au plus MAX_PARAM_CHARS, nombre fini, booléen), au plus MAX_PARAMS. Rend la copie, ou nil.
local function paramsOf(action)
    local params, count = {}, 0
    for k, v in pairs(action) do
        if k ~= "type" then
            count = count + 1
            if count > Actions.MAX_PARAMS or type(k) ~= "string" or not string.match(k, "^[a-z][a-z0-9_]*$")
                    or string.len(k) > 32 then
                return nil
            end
            local t = type(v)
            if t == "string" then
                if string.len(v) > Actions.MAX_PARAM_CHARS then return nil end
            elseif t == "number" then
                if v ~= v or v == math.huge or v == -math.huge then return nil end
            elseif t ~= "boolean" then
                return nil
            end
            params[k] = v
        end
    end
    return params
end

-- Distance au sol (cases) entre le lieu de la voix (sheet.coords) et l'appelant ; nil si l'un manque (voix sans lieu
-- fixe, appelant déconnecté) : le contrôle too_far est alors ignoré.
local function distance(sheet, player)
    local c = type(sheet) == "table" and sheet.coords or nil
    if type(c) ~= "table" or type(c.x) ~= "number" or type(c.y) ~= "number" or not player then return nil end
    local x, y = player:getX(), player:getY()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local dx, dy = x - c.x, y - c.y
    return math.sqrt(dx * dx + dy * dy)
end

local function logName(value)
    if type(value) == "string" and string.match(value, "^[a-z_]+$") and string.len(value) <= 32 then return value end
    return "?"
end

local function logDecision(decision, voice, caller)
    Const.log("action " .. logName(decision.type) .. " voice=" .. tostring(voice) .. " caller=" .. tostring(caller)
        .. " " .. (decision.accepted and "accepted" or "refused") .. " reason=" .. decision.reason)
end

-- Juge une action. Rend accepted, reason.
local function judge(sheet, name, params, now, ctx)
    if not Actions.isKnown(name) then return false, "unknown_action" end
    if not allowedBy(sheet, name) then return false, "not_allowed" end
    local spec = executors[name]
    if not spec then return false, "not_available" end
    if params == nil then return false, "bad_params" end
    if spec.validate then
        if not spec.validate(params, ctx) then return false, "bad_params" end
    end
    if type(spec.maxDistance) == "number" then
        local d = distance(sheet, ctx.player)
        if d ~= nil and d > spec.maxDistance then return false, "too_far" end
    end
    local counter, persistent = counterOf(sheet.id, name)
    local day = ctx.day or gameDay()
    if counter.day ~= day then counter.day, counter.used = day, 0 end
    local cap = type(sheet.budgets) == "table" and sheet.budgets[name] or nil
    if type(cap) == "number" and cap > 0 and counter.used >= cap then return false, "budget" end
    local cooldown = spec.cooldownMs
    if type(cooldown) == "number" and cooldown > 0 and type(counter.lastMs) == "number"
            and now - counter.lastMs < cooldown then
        return false, "cooldown"
    end
    local ok, why = spec.execute(params, ctx)
    if not ok then return false, (logName(why) ~= "?" and why or "failed") end
    counter.used = counter.used + 1
    counter.lastMs = now
    if persistent then S.dirty = true end
    return true, "ok"
end

-- sheet : fiche de la voix (RS_Personas.get), nil si elle a disparu (tout est alors refusé not_allowed après le
-- catalogue) ; caller : clé de l'appelant ; actions : liste reçue du pont ; now : horloge réelle (ms) ;
-- ctx : { player, khz, cid, day } (day : jour de jeu AAAA-MM-JJ, calculé si absent). Rend la liste des décisions
-- { type, params, accepted, reason }, dans l'ordre reçu ; une ligne console et une ligne du journal admin
-- (RS_ActionLog, E07-T02) par décision, too_many compris.
function Actions.decide(sheet, caller, actions, now, ctx)
    ctx = ctx or {}
    ctx.caller = caller
    ctx.voice = type(sheet) == "table" and sheet.id or nil
    ctx.sheet = type(sheet) == "table" and sheet or nil
    local decisions, logLines = {}, {}
    if type(actions) ~= "table" then return decisions end
    for i, action in ipairs(actions) do
        local name = type(action) == "table" and action.type or nil
        local params = type(action) == "table" and paramsOf(action) or nil
        local accepted, reason
        if i > Actions.MAX_PER_REPLY then
            accepted, reason = false, "too_many"
        elseif type(sheet) ~= "table" and Actions.isKnown(name) then
            accepted, reason = false, "not_allowed"
        else
            accepted, reason = judge(sheet, name, params, now, ctx)
        end
        local decision = { type = name, params = params, accepted = accepted, reason = reason }
        decisions[#decisions + 1] = decision
        logDecision(decision, ctx.voice, caller)
        logLines[#logLines + 1] = ActionLog.format(decision, ctx.voice, caller, logName(name))
    end
    ActionLog.append(logLines)
    return decisions
end

return Actions
