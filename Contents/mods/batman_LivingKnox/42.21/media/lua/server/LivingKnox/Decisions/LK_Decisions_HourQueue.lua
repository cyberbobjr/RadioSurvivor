-- Living Knox : cadre de décision des PNJ, notation horaire étalée sur les images (LK13-T11, file
-- LivingKnox.FrameQueue de LK20-T05).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions

-- hour : heure de jeu lue à l'EveryHours (LK13-T09, file du pas horaire de LK_Simulation) ; nil = heure courante.
-- LK13-T11 : notation étalée : les groupes (ordre trié, comme scorePass) sont notés un par image à partir de l'image
-- suivante (Decisions.tick), chacun avec cette heure ; un groupe non matérialisé est passé sans coût dans la même
-- image. Écriture du registre retenue jusqu'à la fin (Groups.hold("decisions")). Une heure nouvelle, OnSave et
-- Simulation.finishHour font d'abord les notations restantes (Decisions.finishHourQueue). File : LivingKnox.FrameQueue
-- (LK20-T05), écriture faite dans l'image de la dernière notation (hourStep).
Decisions.HOUR_HOLD_MARGIN = 3

-- Une notation de la file (au plus un groupe matérialisé noté ; all : toutes) ; la file finie, retenue levée et
-- registre écrit (sauf all : la fin du vidage s'en charge sans écrire).
local function hourStep(q, all)
    while q.head <= #q.list do
        local gid = q.list[q.head]
        q.head = q.head + 1
        if Decisions.scorePass(q.hour, gid) > 0 and not all then break end
    end
    if q.head > #q.list then q:close(not all) end
    return true
end

Decisions.hourQueue = LivingKnox.FrameQueue.new({ hold = "decisions", margin = Decisions.HOUR_HOLD_MARGIN,
    step = hourStep }, Decisions.hourQueue)

function Decisions.onEveryHours(hour)
    if not LivingKnox.Config.isEnabled() then return end
    Decisions.finishHourQueue()
    hour = hour or Decisions.currentHour()
    local G = LivingKnox.Groups
    if hour == nil or not G.ensure() then return end
    local ids = {}
    for gid in pairs(G.state.data.groups) do ids[#ids + 1] = gid end
    table.sort(ids)
    local q = Decisions.hourQueue
    q.hour = hour
    for _, gid in ipairs(ids) do q:push(gid) end
    q:start()
end

-- Vrai si le groupe gid sera noté pour l'heure hour par la notation horaire encore en attente : passe différée de
-- LK_Simulation pas encore faite (même heure), ou groupe encore dans la file de notation de cette heure.
function Decisions.hourScoringPending(gid, hour)
    local q = Decisions.hourQueue
    if q ~= nil and q.hour == hour and q.head <= #q.list then
        for i = q.head, #q.list do
            if q.list[i] == gid then return true end
        end
    end
    local S = LivingKnox.Simulation
    local h = S ~= nil and S.hourly or nil
    if h ~= nil and h.hour == hour and h.head <= #h.jobs then
        for i = h.head, #h.jobs do
            if h.jobs[i].name == "Decisions" then return true end
        end
    end
    return false
end

-- Notations restantes tout de suite (heure nouvelle, OnSave, Simulation.finishHour, bancs).
function Decisions.finishHourQueue()
    local q = Decisions.hourQueue
    if q:pending() then q:finish() end
end

-- LK13-T11 : file de notation de l'heure (une notation par image, à partir de l'image qui suit l'EveryHours).
function Decisions.onFrameStart()
    Decisions.hourQueue:frameStart()
end

function Decisions.hourTick()
    if not LivingKnox.isAuthority() then return end
    local q = Decisions.hourQueue
    if q.fresh or not q:pending() then return end
    if not LivingKnox.Groups.isReady() then return end
    q:frame()
end
