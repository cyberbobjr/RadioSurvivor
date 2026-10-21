-- Living Knox : santé des PNJ côté client MP (LK07-T02). Fiche : docs/annexes/conception/sante.md, « Santé de référence
-- (LK07-T02) ». Serveur dédié : rien (garde). Solo : seule la lecture HealthView.get existe (elle lit l'autorité).
--
-- Client MP :
--   - invulnérabilité posée sur chaque copie locale d'un corps de PNJ (Guard.cache : copies reconnues par la liste du
--     serveur, onlineId + isReanimatedPlayer) toutes les Config.HEALTH.APPLY_EVERY images. Le drapeau est local
--     (absent des drapeaux transmis, J/characters/NetworkZombieVariables.java:10-64) : sans lui, un client
--     propriétaire appliquerait les dégâts vanilla à sa copie (J/characters/IsoZombie.java:3449) et les renverrait
--     au serveur dans sa santé (J/popman/NetworkZombiePacker.java:97-101, 231) ;
--   - santé de référence reçue du serveur (commande "npcHealth", { d = { [npcId] = { r, hp, mx, w } } }), gardée par
--     PNJ selon la plus grande révision r (livraison non ordonnée). Lecture : LivingKnox.HealthView.get(id).
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local View = LivingKnox.HealthView or {}
LivingKnox.HealthView = View

View.MODULE = "LivingKnox"
View.CMD = "npcHealth"
View.APPLY_EVERY = 3
View.view = View.view or {}            -- npcId -> { r, hp, mx, w }
View.state = View.state or { ticks = 0 }
View.stats = View.stats or { received = 0, kept = 0, older = 0, protected = 0 }

-- Santé connue du PNJ id : { hp, max, wounds = nombre } (copie), ou nil. Solo : lue sur l'autorité.
function View.get(id)
    if not isClient() then
        local H = LivingKnox.Health
        local s = H and H.get and H.get(id)
        if s == nil then return nil end
        return { hp = s.hp, max = s.max, wounds = #s.wounds }
    end
    local e = View.view[id]
    if e == nil then return nil end
    return { hp = e.hp, max = e.mx, wounds = e.w }
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE or command ~= View.CMD or not isClient() then return end
    if type(args) ~= "table" or type(args.d) ~= "table" then return end
    for id, e in pairs(args.d) do
        if type(id) == "string" and type(e) == "table" and type(e.r) == "number" and type(e.hp) == "number" then
            View.stats.received = View.stats.received + 1
            local old = View.view[id]
            if old == nil or e.r > old.r then
                View.view[id] = { r = e.r, hp = e.hp, mx = type(e.mx) == "number" and e.mx or nil,
                    w = type(e.w) == "number" and e.w or 0 }
                View.stats.kept = View.stats.kept + 1
            else
                View.stats.older = View.stats.older + 1
            end
        end
    end
end

-- Client MP : copies locales des corps rendues invulnérables. Rend le nombre de drapeaux posés.
function View.protectPass()
    local G = LivingKnox.ZombieGuard
    if G == nil or G.cache == nil then return 0 end
    local n = 0
    for _, z in pairs(G.cache) do
        if z ~= nil and not z:isDead() and not z:isInvulnerable() then
            z:setInvulnerable(true)
            n = n + 1
        end
    end
    View.stats.protected = View.stats.protected + n
    return n
end

function View.tick()
    local st = View.state
    st.ticks = st.ticks + 1
    if st.ticks < View.APPLY_EVERY then return end
    st.ticks = 0
    if getCell() ~= nil then View.protectPass() end
end

if isClient() then
    local function onTick()
        LivingKnox.HealthView.tick()
    end
    local function onServerCommand(module, command, args)
        LivingKnox.HealthView.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnTick", "HealthView.tick", onTick)
    LivingKnox.subscribe("OnServerCommand", "HealthView.onServerCommand", onServerCommand)
end

return View
