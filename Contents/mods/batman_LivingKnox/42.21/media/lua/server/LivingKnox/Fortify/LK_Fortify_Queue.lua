-- Living Knox : fortification du foyer, relevé de la minute étalé sur plusieurs images (LK13-T11 : file
-- Fortify.minuteJobs, LivingKnox.FrameQueue) et examen des foyers chargés (Fortify.scan, appelé par les
-- événements de la façade)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

-- Relevé de la minute étalé (LK13-T11, fiche fortification.md « Relevé de la minute étalé ») : le relevé d'un plan
-- expiré (Fortify.feasible : relevé du monde, plan, faisabilité, relevé hors écran) coûte quelques ms par groupe ;
-- tous les plans relevés dans la même image expirent ensemble (PLAN_MS), d'où des pointes de 10 à 23 ms lupa à
-- des minutes isolées (5 groupes). À la minute, les groupes dont le plan a expiré rejoignent une file, sans doublon,
-- avec l'heure de la minute ; un groupe relevé à la fois (OnTick), à partir de l'image qui suit la minute (marque
-- « fresh » effacée au début de l'image suivante, comme la relecture du stock). Même résultat que le relevé dans
-- l'image de la minute :
--   - le relevé est fait avec l'heure de la minute (Fortify.clockAt) : plan.ms et l'expiration suivante inchangés ;
--   - tout ce qui lit ou change le plan, le relevé hors écran ou l'ouvrage d'un groupe encore en file (Fortify.plan,
--     donc feasible, siteFor, levelOf, hasWork, pose d'une planche ou d'un ouvrage ; invalidate ; applyPending ;
--     offscreenHour quand l'heure hors écran peut travailler) fait d'abord son relevé (settle) ;
--   - abonné OnTick inscrit avant celui de la relecture du stock (ordre des fichiers, et ordre des clés pendant une
--     mesure) ; la relecture du stock d'un groupe encore en file attend la fin de son relevé (Fortify.isQueued,
--     LK_Stock) : un groupe est relevé avant que son stock soit relu.
-- Suite (2026-10-15) : chaque relevé en trois images (runJob plus bas), une étape par image.
-- Écriture du registre des groupes retenue pendant la file (Groups.hold("fortify")) puis faite dans une image à elle ;
-- file vidée avant la sauvegarde du monde (OnSave). File : LivingKnox.FrameQueue (LK20-T05), créée après runJob.
Fortify.QUEUE_HOLD_MARGIN = 3   -- images de retenue en plus de celles des relevés en file
Fortify.JOB_FRAMES = 3          -- images d'un relevé en file (une étape chacune)
Fortify.stats.queued = Fortify.stats.queued or 0
Fortify.stats.settled = Fortify.stats.settled or 0   -- relevés en file faits avant leur image (lecture du plan)

-- LK13-T11 (suite) : un relevé en file coûte trois images au plus, une étape chacune (relevé du monde, plan,
-- faisabilité et relevé hors écran : 1,2-1,4 / 2,1 / 1,0-1,5 ms lupa au banc au lieu de 4,4-5 ms dans une image) ;
-- toutes avec l'heure de sa minute. L'entrée reste en file (queued) jusqu'à sa dernière étape : toute lecture du plan
-- d'ici là fait les étapes restantes d'un coup (settle), comme avant.
-- Une étape du relevé en file e ({ gid, ms, ctx }), avec l'heure de sa minute ; all : toutes les étapes restantes.
-- Rend vrai si l'entrée était encore en file.
local function runJob(e, all)
    local q = Fortify.minuteJobs
    if q.queued[e.gid] ~= e then return false end
    local prev = Fortify.clockAt
    Fortify.clockAt = e.ms
    local ok, err = pcall(function()
        if e.ctx == nil then
            local done, ctx = P.planNeed(e.gid)
            if not done then
                e.ctx = ctx
                P.planSurvey(ctx)                  -- étape 1 : relevé du monde
                if not all then return end
            end
        end
        if e.ctx ~= nil and not e.ctx.built then
            e.ctx.built = true
            e.ctx.plan, e.ctx.planWhy = P.planFinish(e.ctx)   -- étape 2 : plan (pur), gardé avec l'heure de la minute
            if not all then return end
        end
        q.queued[e.gid] = nil                    -- étape 3 : faisabilité, relevé hors écran
        if e.ctx ~= nil then   -- plan de l'étape 2 rendu au premier Fortify.plan de feasible (comme un relevé fait là)
            Fortify.givenPlan = { gid = e.gid, plan = e.ctx.plan, why = e.ctx.planWhy }
        end
        Fortify.feasible(e.gid)
    end)
    Fortify.givenPlan = nil
    Fortify.clockAt = prev
    if not ok then
        q.queued[e.gid] = nil
        LivingKnox.Log.error("fortify: group %s survey failed: %s", e.gid, tostring(err))
    end
    return true
end

P.settle = function(gid)
    local e = Fortify.minuteJobs.queued[gid]
    if e ~= nil and runJob(e, true) then Fortify.stats.settled = Fortify.stats.settled + 1 end
end

-- Relevé en file du groupe gid fait tout de suite (toutes ses étapes) ; sans effet s'il n'est pas en file
-- (LK_Stock.finishQueue, avant de relire le stock du groupe).
function Fortify.settleQueued(gid)
    P.settle(gid)
end

-- Vrai si le relevé de la minute du groupe gid est encore en file (LK_Stock : relecture du stock après lui).
function Fortify.isQueued(gid)
    return Fortify.minuteJobs.queued[gid] ~= nil
end

local function enqueue(gid, t)
    if not Fortify.minuteJobs:push({ gid = gid, ms = t }, gid) then return false end
    Fortify.stats.queued = Fortify.stats.queued + 1
    return true
end

-- Une étape d'un relevé de la file (LivingKnox.FrameQueue) ; un relevé déjà fait par settle est passé dans la même
-- image. all : toutes les étapes du relevé (Fortify.finishQueue). Rend vrai, vrai si une étape a été faite.
local function queueStep(q, all)
    while q.head <= #q.list do
        local e = q.list[q.head]
        if runJob(e, all) then
            if q.queued[e.gid] ~= e then q.head = q.head + 1 end   -- dernière étape faite
            return true, true
        end
        q.head = q.head + 1
    end
    return false, false
end

Fortify.minuteJobs = LivingKnox.FrameQueue.new({ hold = "fortify", frames = Fortify.JOB_FRAMES,
    margin = Fortify.QUEUE_HOLD_MARGIN, step = queueStep }, Fortify.minuteJobs)

function Fortify.onFrameStart()
    Fortify.minuteJobs:frameStart()
end

-- Une étape d'un relevé de la file (OnTick) ; la file vide, une image pour l'écriture seule. Rend vrai si une étape
-- a été faite.
function Fortify.onFrame()
    return Fortify.minuteJobs:frame()
end

-- File vidée tout de suite (bancs, OnSave). Rend le nombre de relevés faits.
function Fortify.finishQueue()
    return Fortify.minuteJobs:finish()
end

-- Examine les foyers chargés : travail hors écran posé dès que la zone est chargée ; relevé hors écran tenu à jour
-- (plan expiré ou invalidé : Fortify.feasible le relève et l'écrit ; LK13-T11 : à la minute, mis en file et fait dans
-- les images suivantes). reason = "chunk" (au plus une fois par SCAN_MS) ou "minute". Rend le nombre de groupes dont
-- le travail a été posé.
function Fortify.scan(reason)
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return 0 end
    local st = Fortify.state
    if st.migratedFor ~= G.state.data then   -- LK13-T07 : une fois par registre chargé
        st.migratedFor = G.state.data
        Fortify.migrate()
    end
    local t = P.now()
    if reason == "chunk" and st.lastScan ~= nil and t - st.lastScan < P.cfg().SCAN_MS then return 0 end
    st.lastScan = t
    local cell = getCell()
    if cell == nil then return 0 end
    local ids = G.update(function(data)
        local list = {}
        for gid, g in pairs(data.groups) do
            local home = g.home
            if type(home) == "table" and LivingKnox.Homes.validMark(g.furnish, home)
                and cell:getGridSquare(home.x, home.y, home.z) ~= nil then
                list[#list + 1] = gid
            end
        end
        return false, list
    end)
    if type(ids) ~= "table" then return 0 end
    table.sort(ids)
    local n = 0
    for _, gid in ipairs(ids) do
        if Fortify.hasPending(gid) then
            local ok, res, why = pcall(Fortify.applyPending, gid)
            if not ok then
                LivingKnox.Log.error("fortify: group %s offscreen work not placed: %s", gid, tostring(res))
            elseif type(res) == "table" then
                n = n + 1
            else
                LivingKnox.Log.debug("fortify: group %s offscreen work waits: %s", gid, tostring(why))
            end
        elseif reason == "minute" and Fortify.minuteJobs.queued[gid] == nil then
            local plan = st.plans[gid]
            if plan == nil or t - plan.ms >= P.cfg().PLAN_MS then enqueue(gid, t) end   -- LK13-T11
        end
    end
    if reason == "minute" then Fortify.minuteJobs:start() end
    return n
end
