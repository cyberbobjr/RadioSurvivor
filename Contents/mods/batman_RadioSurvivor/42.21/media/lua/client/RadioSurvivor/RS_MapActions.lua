-- Radio Survivor : repère d'une voix sur la carte du monde du joueur (action mark_map, E07-T04) et quartier révélé
-- (action reveal_area, E07-T05, voir plus bas).
-- Le serveur n'envoie la commande map_mark { x, y, z, label } qu'à l'appelant dont la voix a accepté mark_map
-- (server/RadioSurvivor/RS_MapMarks.lua ; OnServerCommand en multijoueur, appel direct en solo, par RS_RadioTalk.handle).
-- Ajout : symboles de la carte du monde (WorldMapSymbols de MapItem.getSingleton(), les annotations du joueur), par
-- une UIWorldMap cachée créée une seule fois par partie, jamais ajoutée à l'interface (comme ISWorldMap:
-- getStashMapBounds, client/ISUI/Maps/ISWorldMap.lua:643-645) : setMapItem(MapItem.getSingleton()) puis
-- getSymbolsAPIv2(). Deux symboles, comme une note posée par le joueur (ISWorldMapSymbols.lua:137-140, 263-269) :
--   - une icône vanilla (MapActions.ICON, définie par shared/Definitions/MapSymbolDefinitions.lua), centrée au-dessus
--     du point ; jamais masquée pour un personnage illettré ;
--   - le libellé du lieu (texte déjà composé, addTranslatedText), centré sous le point ; affiché en « ? » pour un
--     illettré (WorldMapTextSymbol.getTranslatedText, comportement vanilla).
-- Sans doublon : chaque symbole n'est ajouté que si aucun symbole du même genre n'est déjà au même point (icône : même
-- identifiant de texture ; texte : repéré par sa position seule, getUntranslatedText rendant le texte masqué pour un
-- illettré). Un repère effacé par le joueur est ainsi reposé au prochain mark_map du même lieu.
-- Persistance : celle des annotations vanilla du joueur, sans rien de plus. Symboles privés (sans partage réseau),
-- écrits dans map_symbols.bin de la sauvegarde courante côté client, en solo comme sur un client MP
-- (WorldMapSymbols.save : userDefined et sans NetworkInfo, WorldMapSymbols.java:240-259 ; MapItem.SaveWorldMap,
-- MapItem.java:47-66, appelé par GameWindow.save, GameWindow.java:1033-1035 sur un client MP et 1102 en solo) et relus
-- au chargement du monde avant OnGameStart (MapItem.LoadWorldMap, IsoWorld.java:2075-2078, jamais sur un serveur).
-- Le serveur ne garde rien : un repère perdu (sauvegarde client effacée) n'est reposé que par un nouveau mark_map.
-- Aucun texte flottant : le joueur en est averti par la ligne « Repère reçu » de l'onglet Radio du carnet, inscrite par
-- le serveur dans son historique radio (RS_MapMarks, E07-T08).
--
-- Quartier révélé (action reveal_area, E07-T05) : commande map_reveal { x1, y1, x2, y2 } du serveur, au seul appelant
-- (rectangle de cases, x2 et y2 exclus, bords multiples de 32, côté d'au plus Const.MAP_REVEAL_MAX_SIDE ; contrôlé de
-- nouveau ici). Appliquée à la carte du seul joueur local : WorldMapVisited.getInstance():setKnownInSquares, l'API
-- vanilla d'une carte lue (ISMapDefinitions.lua:383, PrintMedia.lua:299), effet immédiat, carte ouverte ou non.
-- WorldMapVisited est une instance par processus client (WorldMapVisited.java:792-816) : aucun autre joueur n'est
-- touché. Bord haut passé inclus (dernière case) : WorldMapVisited.coordToUnit rend le bloc de la case de bord haut,
-- et un bord exclu multiple de 32 révélerait un bloc de plus (bytecode de coordToUnit : (c / 32), moins 1 seulement
-- si cet index de bloc est multiple de 32). Persistance : en solo, map_visited.bin de la sauvegarde ; sur un client
-- MP, rien n'est écrit ici (WorldMapVisited.save ignore le client) : le serveur a inscrit la zone dans la carte du
-- compte (RS_MapMarks, WorldMapVisitedServer), renvoyée à la connexion. Aucune commande vanilla
-- « map setKnownInSquares » n'est envoyée : le serveur n'a pas à croire le client.
--
-- Zones des missions sur la carte (E11-T10) : mod commun depuis E21-T03 (client/CoreAI/CA_MapZones.lua), qui
-- possède aussi l'API des symboles de la carte (une seule par MapItem) utilisée ici.
if isServer() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Zones = require "CoreAI/CA_MapZones"

local MapActions = {}

-- Icône vanilla « Target » (onglet Locations) et couleur : rouge brique, lisible sur la carte papier.
MapActions.ICON = "Target"
MapActions.COLOR = { r = 0.70, g = 0.18, b = 0.08 }
-- Échelle des notes du joueur, écart toléré entre deux positions, longueur des libellés et API des symboles : ceux
-- du mod commun (E21-T03).
MapActions.SCALE, MapActions.EPSILON, MapActions.LABEL_MAX = Zones.SCALE, Zones.EPSILON, Zones.LABEL_MAX
MapActions.symbolsAPI, MapActions.resetForTests = Zones.symbolsAPI, Zones.resetForTests
local near, cleanLabel = Zones.near, Zones.cleanLabel

-- Symboles déjà présents au point (x, y) : icône MapActions.ICON, texte (tout texte).
local function existing(api, x, y)
    local icon, text = false, false
    for i = 0, api:getSymbolCount() - 1 do
        local symbol = api:getSymbolByIndex(i)
        if symbol and near(symbol, x, y) then
            if symbol:isTexture() and symbol:getSymbolID() == MapActions.ICON then icon = true end
            if symbol:isText() then text = true end
        end
    end
    return icon, text
end

local function paint(symbol, anchorY)
    local c = MapActions.COLOR
    symbol:setRGBA(c.r, c.g, c.b, 1.0)
    symbol:setAnchor(0.5, anchorY)
    symbol:setScale(MapActions.SCALE)
end


-- Pose le repère du point de case (x, y) (centre de la case). Rend "added" (au moins un symbole ajouté), "present"
-- (déjà marqué) ou nil et la raison ("bad_args", "no_map").
function MapActions.mark(x, y, label)
    if type(x) ~= "number" or type(y) ~= "number" or x < 0 or y < 0 then return nil, "bad_args" end
    local api = MapActions.symbolsAPI()
    if api == nil then return nil, "no_map" end
    local wx, wy = math.floor(x) + 0.5, math.floor(y) + 0.5
    local hasIcon, hasText = existing(api, wx, wy)
    local text = cleanLabel(label)
    local added = false
    if not hasIcon then
        paint(api:addTexture(MapActions.ICON, wx, wy), 1.0)
        added = true
    end
    if not hasText and text ~= "" then
        paint(api:addTranslatedText(text, api:getDefaultTextLayerID(), wx, wy), 0.0)
        added = true
    end
    return added and "added" or "present"
end

local function aligned(n)
    return type(n) == "number" and n == math.floor(n) and n % Const.MAP_REVEAL_BLOCK == 0
end

-- Rend connu sur la carte du monde du joueur local le rectangle de cases [x1, x2[ x [y1, y2[. Rend "revealed" ou nil
-- et la raison ("bad_args" : bord non entier ou non multiple de 32, rectangle vide ou plus grand que le plafond ;
-- "no_map" : WorldMapVisited absent).
function MapActions.reveal(x1, y1, x2, y2)
    if not (aligned(x1) and aligned(y1) and aligned(x2) and aligned(y2)) then return nil, "bad_args" end
    local max = Const.MAP_REVEAL_MAX_SIDE
    if x1 < 0 or y1 < 0 or x2 <= x1 or y2 <= y1 or x2 - x1 > max or y2 - y1 > max then return nil, "bad_args" end
    if WorldMapVisited == nil then return nil, "no_map" end
    local visited = WorldMapVisited.getInstance()
    if visited == nil then return nil, "no_map" end
    visited:setKnownInSquares(x1, y1, x2 - 1, y2 - 1)
    return "revealed"
end


-- Commande du serveur (RS_RadioTalk.handle). Rend true si elle est traitée ici.
function MapActions.receive(command, args)
    if command == Const.CMD.MAP_REVEAL then
        args = args or {}
        local result, why = MapActions.reveal(tonumber(args.x1), tonumber(args.y1), tonumber(args.x2),
            tonumber(args.y2))
        if result == nil then Const.log("map area not revealed: " .. tostring(why)) end
        return true
    end
    if command ~= Const.CMD.MAP_MARK then return false end
    args = args or {}
    local result, why = MapActions.mark(tonumber(args.x), tonumber(args.y), args.label)
    if result == nil then Const.log("map mark not added: " .. tostring(why)) end
    return true
end

return MapActions
