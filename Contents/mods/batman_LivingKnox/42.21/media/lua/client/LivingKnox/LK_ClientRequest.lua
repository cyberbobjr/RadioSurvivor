-- Living Knox : client de requêtes commun des vues (LK20-T06, ADR docs/architecture/decisions/
-- adr-simplification-livingknox.md, D06). Servent : LK_AdminView, LK_NpcSheet, LK_TradeView.
--
-- Envoi : LivingKnox.ClientRequest.send(route, player, args, receive) ; route = { module, request, server } :
--   - client MP : sendClientCommand(player, route.module, route.request, args), la réponse viendra par
--     OnServerCommand ;
--   - solo (autorité locale) : relais direct vers LivingKnox[route.server].request(player, args), réponse rendue à
--     receive pendant l'appel (l'attente de la vue est posée avant, base multiplayer.md) ; une autorité qui ne rend
--     rien (nil, raison) donne le refus { op, n, ok = false, err = raison }.
--   Rend faux seulement en solo quand l'autorité n'est pas chargée (rien n'est envoyé).
-- Réception (client MP seulement) : un seul abonnement OnServerCommand, aiguillé par module et commande vers les
-- fonctions inscrites par LivingKnox.ClientRequest.listen(module, command, key, fn), appelées fn(module, command, args)
-- dans l'ordre d'inscription ; une inscription de même clé remplace l'ancienne (rechargement). Une erreur d'une
-- fonction est notée au journal sans priver les suivantes de la réponse (comme des abonnés distincts de l'événement).
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local Request = LivingKnox.ClientRequest or {}
LivingKnox.ClientRequest = Request

Request.routes = Request.routes or {}   -- ["module/command"] = { { key, fn }, ... } dans l'ordre d'inscription

local function slot(module, command)
    return tostring(module) .. "/" .. tostring(command)
end

-- Réponse de l'autorité locale (solo) : sa réponse, ou le refus fabriqué quand elle ne rend rien.
local function relay(server, player, args)
    local reply, why = server.request(player, args)
    if reply == nil then reply = { op = args.op, n = args.n, ok = false, err = tostring(why) } end
    return reply
end

function Request.send(route, player, args, receive)
    if isClient() then
        sendClientCommand(player, route.module, route.request, args)
        return true
    end
    local server = LivingKnox[route.server]
    if server == nil or server.request == nil then return false end
    receive(relay(server, player, args))
    return true
end

function Request.listen(module, command, key, fn)
    local s = slot(module, command)
    local list = Request.routes[s] or {}
    Request.routes[s] = list
    for _, h in ipairs(list) do
        if h.key == key then
            h.fn = fn
            return
        end
    end
    list[#list + 1] = { key = key, fn = fn }
end

function Request.dispatch(module, command, args)
    local list = Request.routes[slot(module, command)]
    if list == nil then return end
    for _, h in ipairs(list) do
        local ok, err = pcall(h.fn, module, command, args)
        if not ok then LivingKnox.Log.error("client request: %s handler %s failed: %s", slot(module, command), h.key,
            tostring(err)) end
    end
end

if isClient() and Events ~= nil then   -- solo : réponses rendues pendant l'appel (Request.send)
    LivingKnox.subscribe("OnServerCommand", "ClientRequest.onServerCommand", function(module, command, args)
        LivingKnox.ClientRequest.dispatch(module, command, args)
    end)
end

return Request
