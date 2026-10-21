-- Radio Survivor : journal du dehors côté autorité (E13-T05) : création d'une édition et commande de test.
-- Serveur MP ou solo. Fiche : docs/annexes/conception/journal-du-dehors.md ; module partagé : RS_OutsideNews.lua.
--
-- Point d'appel de l'échange sur la berge (E13-T04, à venir) :
--     local NewsServer = require "RadioSurvivor/RS_OutsideNewsServer"
--     local item = NewsServer.create(passage)   -- numéro du passage du passeur (entier >= 1), ou nil
-- rend un objet neuf, hors de tout conteneur, avec l'édition du passage datée du jour de jeu ; l'appelant le pose
-- avec la contrepartie (sol ou conteneur, envoi aux clients compris). Deux passages différents donnent deux
-- éditions différentes (une, brèves, prix, titre et marque « lu »). Sans numéro : édition de la semaine en cours.
-- Le journal ne se revend pas : hors module Base, il vaut 0 dans le barème (RS_TradeValues.value) ; sa valeur de
-- vente est RS_TradeValues.sellValue("RadioSurvivor.OutsideNews").
--
-- Commande de test (console Lua de debug, solo) :
--     RadioSurvivorOutsideNews.give()          -- édition de la semaine en cours, dans l'inventaire du joueur
--     RadioSurvivorOutsideNews.give(3)         -- édition du passage 3
--     RadioSurvivorOutsideNews.give(3, player) -- à un autre joueur (serveur : objet envoyé à son client)
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local News = require "RadioSurvivor/RS_OutsideNews"

local NewsServer = {}

local function log(msg)
    Const.log("outside news: " .. msg)
end

-- Objet neuf portant l'édition du passage (ou de la semaine en cours), ou nil.
function NewsServer.create(passage)
    local edition = passage
    if edition == nil then edition = News.currentEdition() end
    if type(edition) ~= "number" or edition ~= math.floor(edition) or edition < 1 or edition > News.EDITION_MAX then
        log("WARNING: invalid passage number " .. tostring(passage) .. ", no edition created")
        return nil
    end
    local item = instanceItem(News.FULL_TYPE)
    if not item then
        log("WARNING: instanceItem(" .. News.FULL_TYPE .. ") returned nil")
        return nil
    end
    News.apply(item, edition)
    return item
end

-- Commande de test : une édition dans l'inventaire principal du joueur (solo : le joueur local par défaut).
function NewsServer.give(passage, player)
    player = player or (getPlayer and getPlayer()) or nil
    if not player then
        log("WARNING: give without a player")
        return nil
    end
    local item = NewsServer.create(passage)
    if not item then return nil end
    local inv = player:getInventory()
    inv:AddItem(item)
    if isServer() then sendAddItemToContainer(inv, item) end
    log("edition " .. tostring(item:getModData()[News.MODDATA_KEY].edition) .. " given to "
        .. tostring(player:getUsername()))
    return item
end

RadioSurvivorOutsideNews = RadioSurvivorOutsideNews or {}
RadioSurvivorOutsideNews.give = function(passage, player) return NewsServer.give(passage, player) end

return NewsServer
