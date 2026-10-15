-- Living Knox : menu « Demander de l'aide » sur un PNJ (LK11-T06), côté joueur local (client MP, solo).
-- Fiche : docs/conception/aide.md. M = media/lua vanilla.
--
-- OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test) (M/client/ISUI/ISWorldObjectContextMenu.lua:213) :
-- si un corps de PNJ connu ici (LivingKnox.Anim.knownBodies) se tient à CLICK case(s) au plus d'une case cliquée et
-- à RANGE cases au plus du joueur, au même niveau, l'option « Demander de l'aide » ouvre un sous-menu (nourriture,
-- eau, soins). Sondage manette (test vrai) : ISWorldObjectContextMenu.setTest() sans rien ajouter (base
-- quest-building-blocks.md). Le client ne connaît pas l'attitude du groupe : l'option est offerte sur tout PNJ et le
-- serveur décide (refus motivé dit par le PNJ). Envoi : commande "aidRequest" { npc, kind } en MP ; appel direct de
-- LivingKnox.Relations.ask en solo (même machine, comme LK_AdminView). Aucun texte du joueur n'est lu.
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Anim"

local View = LivingKnox.RelationsView or {}
LivingKnox.RelationsView = View

View.MODULE = "LivingKnox"
View.CMD_AID = "aidRequest"
View.KINDS = { "food", "water", "care" }
View.RANGE = 4      -- = LivingKnox.Relations.AID.RANGE (contrôlé de nouveau par le serveur)
View.CLICK = 1.5    -- distance au plus entre le corps et une case cliquée
View.stats = View.stats or { offered = 0, sent = 0 }

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

-- Identifiant du PNJ dont le corps est près d'une case cliquée et du joueur, ou nil (le plus proche du clic).
function View.bodyNear(player, worldObjects)
    local A = LivingKnox.Anim
    if A == nil or A.knownBodies == nil or type(worldObjects) ~= "table" then return nil end
    local squares = {}
    for _, o in ipairs(worldObjects) do
        local sq = o ~= nil and o.getSquare ~= nil and o:getSquare() or nil
        if sq ~= nil then squares[#squares + 1] = sq end
    end
    if #squares == 0 then return nil end
    local pz = math.floor(player:getZ())
    local best, bestD
    for id, z in pairs(A.knownBodies()) do
        if math.floor(z:getZ()) == pz and dist2(z:getX(), z:getY(), player:getX(), player:getY())
            <= View.RANGE * View.RANGE then
            for _, sq in ipairs(squares) do
                local d = dist2(z:getX(), z:getY(), sq:getX() + 0.5, sq:getY() + 0.5)
                if sq:getZ() == pz and d <= View.CLICK * View.CLICK and (bestD == nil or d < bestD) then
                    best, bestD = id, d
                end
            end
        end
    end
    return best
end

-- Envoie la demande au serveur (MP) ou à l'autorité locale (solo).
function View.send(player, npc, kind)
    local args = { npc = npc, kind = kind }
    View.stats.sent = View.stats.sent + 1
    if LivingKnox.isAuthority() then
        local R = LivingKnox.Relations
        if R == nil then return nil, "relations not loaded" end
        return R.ask(player, args)
    end
    sendClientCommand(player, View.MODULE, View.CMD_AID, args)
    return true
end

function View.onChoose(player, npc, kind)
    View.send(player, npc, kind)
end

function View.fill(playerNum, context, worldObjects, test)
    if not LivingKnox.Config.isEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then return end
    local npc = View.bodyNear(player, worldObjects)
    if npc == nil then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    local option = context:addOption(getText("IGUI_LK_Aid_Menu"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    for _, kind in ipairs(View.KINDS) do
        sub:addOption(getText("IGUI_LK_Aid_Menu_" .. kind), player, View.onChoose, npc, kind)
    end
    View.stats.offered = View.stats.offered + 1
end

if Events ~= nil then
    local function onFill(playerNum, context, worldObjects, test)
        return LivingKnox.RelationsView.fill(playerNum, context, worldObjects, test)
    end
    LivingKnox.subscribe("OnFillWorldObjectContextMenu", "RelationsView.fill", onFill)
end

return View
