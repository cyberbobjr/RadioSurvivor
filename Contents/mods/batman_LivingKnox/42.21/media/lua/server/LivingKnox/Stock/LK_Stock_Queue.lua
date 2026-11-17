-- Living Knox : stock du groupe, examen des foyers chargés et relecture de la minute étalée (LK13-T09)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

-- Groupes à relire : foyer aménagé dont la case est chargée, triés par identifiant.
local function candidates(cell)
    local out = LivingKnox.Groups.update(function(data)
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
    if type(out) ~= "table" then return {} end
    table.sort(out)
    return out
end

-- Relit les stocks des foyers chargés. reason = "chunk" (au plus une fois par SCAN_MS) ou "minute". Rend le nombre
-- de groupes relus.
function Stock.scan(reason)
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local st = Stock.state
    local t = P.now()
    if reason == "chunk" and st.lastScan ~= nil and t - st.lastScan < P.cfg().SCAN_MS then return 0 end
    st.lastScan = t
    local cell = getCell()
    if cell == nil then return 0 end
    local n = 0
    for _, gid in ipairs(candidates(cell)) do
        if Stock.checkOne(gid) then n = n + 1 end
    end
    return n
end

-- Relecture d'un groupe par Stock.scan ou la file de la minute : rend vrai si relu. Erreur journalisée.
function Stock.checkOne(gid)
    local ok, res, why = pcall(Stock.check, gid)
    if not ok then
        LivingKnox.Log.error("stock: group %s check failed: %s", gid, tostring(res))
    elseif type(res) == "table" then
        return true
    elseif why ~= "checked recently" then
        LivingKnox.Log.debug("stock: group %s not checked: %s", gid, tostring(why))
    end
    return false
end

-- Relecture de la minute étalée (LK13-T09, fiche stock.md « Relecture étalée ») : à chaque minute de jeu, les groupes
-- candidats (foyer aménagé dont la case est chargée, triés) rejoignent une file, sans doublon ; un groupe relu par
-- image (OnTick), à partir de l'image qui suit la minute (marque « fresh » effacée au début de l'image suivante,
-- comme la file du pas horaire de LK_Simulation). Même relecture (Stock.check) et même ordre que Stock.scan("minute"),
-- décalée de quelques images (100 ms chacune sur un serveur dédié). Écriture du registre des groupes retenue pendant
-- la file (Groups.hold("stock")) puis faite dans une image à elle : une seule écriture, comme quand tous les groupes
-- étaient relus dans la même image. Rend le nombre de groupes rangés. File : LivingKnox.FrameQueue (LK20-T05).
Stock.QUEUE_HOLD_MARGIN = 3   -- images de retenue en plus du nombre de groupes en file

-- Un groupe de la file, relu ; la file vide, une image pour l'écriture seule (LivingKnox.FrameQueue). LK13-T11 : un
-- groupe dont le relevé de fortification de la minute est encore en file (trois images, LK_Fortify) attend la fin de
-- ce relevé (file arrêtée, écriture retenue d'autant) : son stock est relu après lui, comme quand le relevé tenait
-- dans une image, sans faire ses étapes restantes dans l'image de la relecture. all : relevé fini tout de suite
-- (Stock.finishQueue).
local function queueStep(q, all)
    local gid = q.list[q.head]
    local F = LivingKnox.Fortify
    if F ~= nil and F.isQueued ~= nil and F.isQueued(gid) then
        if not all then
            q:hold()
            return true, false
        end
        F.settleQueued(gid)
    end
    q.head = q.head + 1
    q.queued[gid] = nil
    return true, Stock.checkOne(gid)
end

Stock.queue = LivingKnox.FrameQueue.new({ hold = "stock", margin = Stock.QUEUE_HOLD_MARGIN, step = queueStep },
    Stock.queue)

function Stock.queueScan()
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local cell = getCell()
    if cell == nil then return 0 end
    local q, n = Stock.queue, 0
    for _, gid in ipairs(candidates(cell)) do
        if q:push(gid, gid) then n = n + 1 end
    end
    q:start()
    return n
end

function Stock.onFrameStart()
    Stock.queue:frameStart()
end

-- Une image de la file (OnTick). Rend vrai si un groupe a été relu.
function Stock.onFrame()
    return Stock.queue:frame()
end

-- File vidée tout de suite (bancs). Rend le nombre de groupes relus.
function Stock.finishQueue()
    return Stock.queue:finish()
end
