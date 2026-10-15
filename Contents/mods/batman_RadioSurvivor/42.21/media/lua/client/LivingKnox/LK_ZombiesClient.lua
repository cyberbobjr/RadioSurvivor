-- Living Knox : coup de PNJ sur un zombie vanilla, côté client MP qui simule ce zombie (LK06-T04). Fiche :
-- docs/conception/zombies.md. Un serveur dédié n'exécute pas media/lua/client ; en solo, l'autorité applique tout
-- (server/LivingKnox/LK_Zombies.lua) et ce module ne reçoit rien.
--
-- "zombieHurt" { o = onlineId, d = dégâts } : coup non mortel décidé par le serveur. Le client qui simule le zombie
-- (not isRemoteZombie()) abaisse la santé de SA copie de d : son paquet de zombie porte la santé et la remet au
-- serveur (J/popman/NetworkZombiePacker.java:215-231), qui l'a déjà abaissée de son côté (valeur absolue : aucune
-- double application). Santé bornée à HURT_FLOOR : la mort est décidée par le serveur seul (paquet de mort vanilla).
-- LK06-T09 : r = "Floor" (coup au sol) : réaction vanilla posée sur la copie simulée (setHitReaction), le zombie
-- reste à terre comme sous le coup au sol d'un joueur.
-- Un client qui ne simule plus ce zombie (changement de propriétaire en route) l'ignore : le coup peut alors être
-- perdu (base multiplayer.md « Santé d'un zombie en MP »).
if not isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local View = LivingKnox.ZombiesView or {}
LivingKnox.ZombiesView = View

View.MODULE = "LivingKnox"
View.CMD_HURT = "zombieHurt"
View.FLOOR = 0.01
View.stats = View.stats or { received = 0, applied = 0, remote = 0, missing = 0, refused = 0 }

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function count(name)
    View.stats[name] = (View.stats[name] or 0) + 1
end

-- Zombie d'identifiant réseau o dans la cellule de ce client, ou nil.
function View.zombieByOnlineId(o)
    local cell = getCell()
    if cell == nil then return nil end
    local list = cell:getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z ~= nil and z:getOnlineID() == o then return z end
    end
    return nil
end

-- Coup reçu du serveur. Rend vrai si la copie locale a été abaissée.
function View.onHurt(args)
    if type(args) ~= "table" or not finite(args.o) or not finite(args.d) or args.d < 0 then
        count("refused")
        return false
    end
    count("received")
    local z = View.zombieByOnlineId(args.o)
    if z == nil or z:isDead() then
        count("missing")
        return false
    end
    if z:isRemoteZombie() then
        count("remote")
        return false
    end
    local h = z:getHealth() - args.d
    if h < View.FLOOR then h = View.FLOOR end
    z:setHealth(h)
    if args.r == "Floor" then z:setHitReaction(args.r) end   -- LK06-T09 : coup au sol, le zombie reste à terre
    count("applied")
    return true
end

-- "bodyGone" { o, x, y, z } : corps de PNJ retiré par le serveur (LK_Bodies.tellGone). La copie locale de cet
-- identifiant réseau, à GONE_REACH cases au plus de la position donnée (un identifiant peut être réattribué), est
-- retirée du monde comme le serveur l'a fait. Rend vrai si une copie a été retirée.
View.CMD_GONE = "bodyGone"
View.GONE_REACH = 6
function View.onGone(args)
    if type(args) ~= "table" or not finite(args.o) or not finite(args.x) or not finite(args.y) or not finite(args.z) then
        count("goneRefused")
        return false
    end
    local z = View.zombieByOnlineId(args.o)
    if z == nil then
        count("goneMissing")
        return false
    end
    local dx, dy = z:getX() - args.x, z:getY() - args.y
    if math.floor(z:getZ()) ~= math.floor(args.z) or dx * dx + dy * dy > View.GONE_REACH * View.GONE_REACH then
        count("goneFar")
        return false
    end
    z:removeFromWorld()
    z:removeFromSquare()
    count("goneRemoved")
    LivingKnox.Log.info("npc body copy %d removed here (removed by the server)", args.o)
    return true
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE then return end
    if command == View.CMD_HURT then
        View.onHurt(args)
    elseif command == View.CMD_GONE then
        View.onGone(args)
    end
end

local function onServerCommand(module, command, args)
    LivingKnox.ZombiesView.onServerCommand(module, command, args)
end

LivingKnox.subscribe("OnServerCommand", "ZombiesView.onServerCommand", onServerCommand)

return View
