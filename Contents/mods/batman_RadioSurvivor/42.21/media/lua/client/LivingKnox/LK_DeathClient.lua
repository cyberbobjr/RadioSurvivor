-- Living Knox : contrôle du cadavre d'un PNJ demandé par le serveur MP (LK07-T10). Client MP seulement.
-- Fiche : docs/conception/sante.md, « Cadavre renvoyé à un client sans copie (LK07-T10) » ; autorité :
-- server/LivingKnox/LK_Death.lua.
-- Commande "corpseCheck" { id, o = identifiant d'objet "DeadBody-<n>" ou nil, n = objets statiques de la case sur le
-- serveur, x, y, z } : case non chargée ici -> rien (le cadavre viendra avec le chunk) ; cadavre de même identifiant
-- d'objet sur la case ou une voisine -> rien ; sinon (sans identifiant : moins d'objets statiques que le serveur)
-- réponse "corpseMissing" { id }, et le serveur renvoie le cadavre.
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local View = LivingKnox.DeathView or {}
LivingKnox.DeathView = View

View.MODULE = "LivingKnox"
View.CMD_CHECK = "corpseCheck"
View.CMD_MISSING = "corpseMissing"
View.stats = View.stats or { checks = 0, present = 0, missing = 0, unloaded = 0 }

local function objectKey(body)
    local ok, key = pcall(function() return tostring(body:getObjectID()) end)
    if ok then return key end
    return nil
end

-- Vrai si un cadavre d'identifiant d'objet key est sur la case (x, y, z) ou une voisine.
function View.hasCorpse(key, x, y, z)
    local cell = getCell()
    for dy = -1, 1 do
        for dx = -1, 1 do
            local sq = cell and cell:getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            for i = 0, (list and list:size() or 0) - 1 do
                local o = list:get(i)
                if instanceof(o, "IsoDeadBody") and objectKey(o) == key then return true end
            end
        end
    end
    return false
end

-- Rend "unloaded", "present" ou "missing" (réponse envoyée).
function View.check(args)
    if type(args) ~= "table" or type(args.id) ~= "string" or type(args.x) ~= "number" or type(args.y) ~= "number"
        or type(args.z) ~= "number" then return nil end
    View.stats.checks = View.stats.checks + 1
    local sq = getCell() and getCell():getGridSquare(args.x, args.y, args.z)
    if sq == nil then
        View.stats.unloaded = View.stats.unloaded + 1
        return "unloaded"
    end
    local present
    if type(args.o) == "string" then
        present = View.hasCorpse(args.o, args.x, args.y, args.z)
    else
        local list = sq:getStaticMovingObjects()
        present = type(args.n) ~= "number" or (list and list:size() or 0) >= args.n
    end
    if present then
        View.stats.present = View.stats.present + 1
        return "present"
    end
    View.stats.missing = View.stats.missing + 1
    LivingKnox.Log.info("corpse of npc %s missing here at %s,%s,%s: resend asked", args.id, tostring(args.x),
        tostring(args.y), tostring(args.z))
    sendClientCommand(View.MODULE, View.CMD_MISSING, { id = args.id })
    return "missing"
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE or command ~= View.CMD_CHECK or not isClient() then return end
    View.check(args)
end

if isClient() then
    local function onServerCommand(module, command, args)
        LivingKnox.DeathView.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "DeathView.onServerCommand", onServerCommand)
end

return View
