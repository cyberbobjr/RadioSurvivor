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
-- Zone approximative d'une mission de reconnaissance (E11-T10, MapActions.zones, plus bas) : le serveur ne l'envoie
-- que dans l'instantané du carnet (champ mapZone { x, y, r } d'une mission active dont le joueur est participant,
-- RS_MissionScout) ; jamais la position du bâtiment. Dessin : symbole vanilla « Circle » (map_o.png, cercle tracé à la
-- main) centré sur (x, y), agrandi pour que son anneau ait un rayon de r cases : avec applyZoom (vrai par défaut), la
-- taille affichée vaut largeur x échelle x worldScale pixels, worldScale = pixels par case
-- (WorldMapBaseSymbol.getDisplayScale, WorldMapRenderer.getWorldScale : 1 / metersPerPixel) ; la largeur d'une icône
-- définie sans taille vaut 20 (MapSymbolDefinitions.addTexture) et l'anneau occupe environ 50 des 64 pixels de la
-- texture. Libellé traduit (IGUI_RS_MapZone, nom du demandeur) au-dessus de l'anneau. Sur la mini-carte, l'échelle
-- est ignorée (min(worldScale, 1)) : petit cercle seulement.
-- Reconnaissance des symboles de zone : couleur orange et alpha 0,8, que l'interface vanilla ne pose jamais (alpha 1,0
-- pour ses icônes, ISWorldMapSymbols.lua:138, 432, 469) ; l'alpha est sauvegardé sur un octet (WorldMapBaseSymbol.save),
-- d'où la tolérance. À chaque instantané, les symboles de zone qui ne correspondent plus à aucune mission active du
-- joueur sont retirés (fin, abandon, expiration, mission purgée, autre personnage), y compris quand la fin a eu lieu
-- pendant que le joueur était déconnecté ; les zones manquantes sont posées une fois par session (une zone effacée par
-- le joueur revient au chargement suivant tant que la mission dure). Persistance : celle des notes du joueur
-- (map_symbols.bin côté client, voir plus haut) ; sinon reposée au premier instantané d'une session.
if isServer() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"

local MapActions = {}

-- Icône vanilla « Target » (onglet Locations) et couleur : rouge brique, lisible sur la carte papier.
MapActions.ICON = "Target"
MapActions.COLOR = { r = 0.70, g = 0.18, b = 0.08 }
-- Échelle des notes du joueur (ISMap.SCALE, client/ISUI/Maps/ISMap.lua:16).
MapActions.SCALE = 0.666
-- Écart toléré (cases) en comparant deux positions de symbole (flottants Java).
MapActions.EPSILON = 0.01
MapActions.LABEL_MAX = 48

-- API de symboles de la partie : { item = MapItem du monde, api = WorldMapSymbolsV2 }. Chaque WorldMapSymbolsV2
-- ajoute un écouteur permanent aux symboles (WorldMapSymbolsV2.java:54-59) : une seule par MapItem. MapItem.Reset()
-- (retour au menu) remplace le singleton : une nouvelle partie recrée l'API.
local cache = { item = nil, api = nil, ui = nil }

function MapActions.resetForTests()
    cache = { item = nil, api = nil, ui = nil }
end

function MapActions.symbolsAPI()
    if MapItem == nil or UIWorldMap == nil then return nil end
    local item = MapItem.getSingleton()
    if item == nil then return nil end
    if cache.api == nil or cache.item ~= item then
        local ui = {}
        ui.javaObject = UIWorldMap.new(ui)
        local mapAPI = ui.javaObject:getAPIv3()
        mapAPI:setMapItem(item)
        cache = { item = item, api = mapAPI:getSymbolsAPIv2(), ui = ui }
    end
    return cache.api
end

local function near(symbol, x, y)
    return math.abs(symbol:getWorldX() - x) < MapActions.EPSILON and math.abs(symbol:getWorldY() - y) < MapActions.EPSILON
end

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

-- Libellé sur une ligne, sans balise, borné (la fiche le borne déjà à 48 octets UTF-8).
local function cleanLabel(label)
    local text = Const.oneLine(string.gsub(tostring(label or ""), "[%c<>%[%]]", " "))
    if string.len(text) > MapActions.LABEL_MAX then text = string.sub(text, 1, MapActions.LABEL_MAX) end
    return text
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

-- ---------------------------------------------------------------------------------- zones de mission (E11-T10)

MapActions.ZONE_ICON = "Circle"
MapActions.ZONE_COLOR = { r = 0.85, g = 0.40, b = 0.05, a = 0.8 }
-- Diamètre de l'anneau de « Circle » à l'échelle 1, en cases (20 unités, anneau sur ~50/64 de la texture).
MapActions.ZONE_RING = 20 * 50 / 64
-- Couleurs sauvegardées sur un octet : 1/255 près.
MapActions.ZONE_COLOR_TOLERANCE = 0.02

-- Zones déjà traitées pendant cette session (clé mission@x,y,r) : posées une seule fois par session.
local zonesDone = {}

function MapActions.resetZonesForTests()
    zonesDone = {}
end

function MapActions.zoneScale(r)
    return 2 * r / MapActions.ZONE_RING
end

-- Symbole posé pour une zone de mission (signature de couleur et d'alpha).
local function isZoneSymbol(symbol)
    local c, tol = MapActions.ZONE_COLOR, MapActions.ZONE_COLOR_TOLERANCE
    return math.abs(symbol:getAlpha() - c.a) < tol and math.abs(symbol:getRed() - c.r) < tol
        and math.abs(symbol:getGreen() - c.g) < tol and math.abs(symbol:getBlue() - c.b) < tol
end

local function paintZone(symbol, anchorY, scale)
    local c = MapActions.ZONE_COLOR
    symbol:setRGBA(c.r, c.g, c.b, c.a)
    symbol:setAnchor(0.5, anchorY)
    symbol:setScale(scale)
end

-- Zones voulues : missions actives de l'instantané dont le joueur est participant et qui portent mapZone.
local function wantedZones(missions)
    local out = {}
    for _, p in ipairs(type(missions) == "table" and missions or {}) do
        local z = type(p) == "table" and p.mapZone or nil
        if type(z) == "table" and p.state == "active" and p.engaged and type(z.x) == "number"
                and type(z.y) == "number" and type(z.r) == "number" and z.r > 0 then
            out[#out + 1] = { id = tostring(p.id), x = z.x, y = z.y, r = z.r, requester = p.requester,
                search = p.template == "retrieve_id", clear = p.template == "clear", cache = p.template == "recover",
                signal = p.template == "signal" }
        end
        -- E11-T06: depot circle of a recover mission (same conditions), drawn next to its search area.
        local d = type(p) == "table" and p.depotZone or nil
        if type(d) == "table" and p.state == "active" and p.engaged and type(d.x) == "number"
                and type(d.y) == "number" and type(d.r) == "number" and d.r > 0 then
            out[#out + 1] = { id = tostring(p.id) .. ":depot", x = d.x, y = d.y, r = d.r, requester = p.requester,
                depot = true }
        end
    end
    return out
end

-- E11-T05: a retrieve_id mission (search for a body) has its own label, E11-T04 a clear mission (counting circle) too,
-- E11-T06 a recover mission (cache area and depot circle), E11-T07 a signal mission; the symbols are matched by position
-- only.
local function zoneLabel(z)
    local name = cleanLabel(z.requester)
    local key = z.search and "IGUI_RS_MapZoneSearch" or (z.clear and "IGUI_RS_MapZoneClear")
        or (z.cache and "IGUI_RS_MapZoneCache") or (z.depot and "IGUI_RS_MapZoneDepot")
        or (z.signal and "IGUI_RS_MapZoneSignal") or "IGUI_RS_MapZone"
    if name == "" then return cleanLabel(getText(key .. "Anon")) end
    return cleanLabel(getText(key, name))
end

-- Accorde la carte du joueur aux missions de l'instantané du carnet. Rend { added = n, removed = n } ou nil et la
-- raison ("no_map").
function MapActions.zones(missions)
    local wanted = wantedZones(missions)
    local api = MapActions.symbolsAPI()
    if api == nil then return nil, "no_map" end
    local hasRing, hasText, removed = {}, {}, 0
    for i = api:getSymbolCount() - 1, 0, -1 do
        local symbol = api:getSymbolByIndex(i)
        if symbol and isZoneSymbol(symbol) then
            local kept = false
            for _, z in ipairs(wanted) do
                if symbol:isTexture() and symbol:getSymbolID() == MapActions.ZONE_ICON and near(symbol, z.x, z.y) then
                    kept, hasRing[z] = true, true
                elseif symbol:isText() and near(symbol, z.x, z.y - z.r) then
                    kept, hasText[z] = true, true
                end
            end
            if not kept then
                api:removeSymbolByIndex(i)
                removed = removed + 1
            end
        end
    end
    local added = 0
    for _, z in ipairs(wanted) do
        local key = z.id .. "@" .. z.x .. "," .. z.y .. "," .. z.r
        if not zonesDone[key] then
            zonesDone[key] = true
            if not hasRing[z] then
                paintZone(api:addTexture(MapActions.ZONE_ICON, z.x, z.y), 0.5, MapActions.zoneScale(z.r))
                added = added + 1
            end
            local text = zoneLabel(z)
            if not hasText[z] and text ~= "" then
                paintZone(api:addTranslatedText(text, api:getDefaultTextLayerID(), z.x, z.y - z.r), 1.0,
                    MapActions.SCALE)
                added = added + 1
            end
        end
    end
    return { added = added, removed = removed }
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
