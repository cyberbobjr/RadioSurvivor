-- Radio Survivor : actions `mark_map`, repère sur la carte de l'appelant (E07-T04), et `reveal_area`, quartier révélé
-- sur sa carte (E07-T05, plus bas).
-- La fiche de la voix liste ses lieux connus (lignes place=<id> <x>,<y>,<z> <libellé>, RS_Persona) ; le pont ne
-- montre au LLM que leurs identifiants et libellés, jamais les coordonnées ; le LLM choisit un lieu par son
-- identifiant (paramètre unique `place`). RS_Actions juge (catalogue, fiche, paramètres, budget.mark_map du jour,
-- délai), puis l'exécuteur ci-dessous envoie les coordonnées exactes et le libellé de ce seul lieu au seul appelant
-- (Const.toClient : sendServerCommand au joueur en multijoueur, appel direct du client en solo, où sendServerCommand ne
-- fait rien). Le client (client/RadioSurvivor/RS_MapActions.lua) ajoute le symbole à la carte du monde du joueur.
-- L'appelant en est averti par une ligne « mark » de son historique radio (RS_RadioLog, E07-T08), sur la fréquence de
-- la réponse (ctx.khz) et pour son seul personnage du carnet (ctx.cid) : le libellé seul, sans coordonnée ; sans
-- personnage lié (carnet jamais ouvert), le repère est posé sans ligne d'historique.
-- Rien d'autre n'est gardé côté serveur en dehors des compteurs de RS_Actions : la persistance du repère est celle des
-- symboles vanilla du joueur (map_symbols.bin de sa sauvegarde, côté client). Aucune coordonnée en ModData globale.
-- Refus : place absent, autre paramètre, identifiant absent de la fiche -> bad_params ; appelant déconnecté (aucun
-- joueur à qui envoyer) -> no_player, sans compter l'usage.
--
-- Action `reveal_area` (E07-T05), rangée ici parce qu'elle partage les lieux de la fiche, leur contrôle et le même
-- paramètre `place` : le quartier autour d'un lieu devient « connu » sur la carte du monde du seul appelant
-- (WorldMapVisited, bit « connu » par bloc de 32 x 32 cases). Le serveur calcule le rectangle (MapMarks.revealRect) :
-- nombre impair de blocs entiers qui tient dans Const.MAP_REVEAL_MAX_SIDE (160 cases = 5 blocs), centré sur le bloc
-- du lieu, rogné aux bornes de la carte (métagrille, multiples de 256 : l'alignement reste) ; jamais plus grand,
-- quel que soit le lieu. Envoi au seul appelant (Const.CMD.MAP_REVEAL), budget.reveal_area de la fiche par jour de
-- jeu, délai Const.MAP_REVEAL_COOLDOWN_MS par voix, journal de RS_Actions ; ligne « reveal » de l'historique radio
-- (« Quartier révélé : <libellé> ») comme la ligne « mark ».
-- Persistance, mécanisme vanilla (Java 42.21) : en multijoueur, la carte « connue » d'un compte est tenue par le
-- serveur (WorldMapVisitedServer : un tableau par nom de compte, sauvegardé dans map_visited_server/<compte>.zip,
-- envoyé au client à sa connexion seulement, RequestDataPacket.java:215-218, 304-306) et le client n'écrit rien
-- (WorldMapVisited.save : this.client, WorldMapVisited.java:400-403). L'exécuteur l'inscrit donc lui-même dans le
-- tableau du compte de l'appelant (comme ISReadABook:revealPrintMediaLocationsOnMap côté serveur,
-- shared/TimedActions/ISReadABook.lua:314-315) : rien d'autre à garder, et le client modifié ne choisit pas la zone.
-- Le client, lui, l'affiche aussitôt (sinon seulement à la reconnexion). En solo, le client local l'inscrit dans le
-- WorldMapVisited de la partie, écrit dans map_visited.bin (WorldMapVisited.save, SaveAll, saveToBufferMap).
-- Aucune diffusion : WorldMapVisitedServer.setKnownInSquares ne touche que le tableau de cette connexion
-- (WorldMapVisitedServer.java:69-75) et n'envoie rien. Une révélation ne se défait pas (pas d'oubli ciblé).
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Actions = require "RadioSurvivor/RS_Actions"
local Log = require "RadioSurvivor/RS_RadioLog"

local MapMarks = {}

-- Délai réel entre deux repères d'une même voix (RS_Actions : par voix, tous appelants confondus).
MapMarks.COOLDOWN_MS = Const.MAP_MARK_COOLDOWN_MS

-- Lieu `id` de la fiche, ou nil.
function MapMarks.placeOf(sheet, id)
    if type(sheet) ~= "table" or type(sheet.places) ~= "table" or type(id) ~= "string" then return nil end
    for _, place in ipairs(sheet.places) do
        if type(place) == "table" and place.id == id then return place end
    end
    return nil
end

-- Paramètre unique `place` : identifiant d'un lieu de la fiche de la voix.
local function validate(params, ctx)
    for key in pairs(params) do
        if key ~= "place" then return false end
    end
    return MapMarks.placeOf(type(ctx) == "table" and ctx.sheet or nil, params.place) ~= nil
end

-- Commande envoyée à l'appelant : coordonnées entières et libellé du lieu, rien d'autre de la fiche.
function MapMarks.command(place)
    return { x = place.x, y = place.y, z = place.z, label = place.label }
end

-- Repère d'un lieu de fiche envoyé au seul joueur, ligne « mark » de l'historique de son personnage (cid, peut être
-- nil) sur khz. Aussi la récompense d'une mission de voix (RS_MissionVoice, E11-T08), hors budget et délai.
function MapMarks.give(player, cid, khz, place)
    Const.toClient(player, Const.CMD.MAP_MARK, MapMarks.command(place))
    if cid then Log.add(cid, khz, "mark", place.label) end
end

local function execute(params, ctx)
    if type(ctx) ~= "table" then return false, "failed" end
    local place = MapMarks.placeOf(ctx.sheet, params.place)
    if place == nil then return false, "failed" end
    if ctx.player == nil then return false, "no_player" end
    MapMarks.give(ctx.player, ctx.cid, ctx.khz, place)
    return true
end

-- ---------------------------------------------------------------------------------------------- reveal_area

MapMarks.REVEAL_COOLDOWN_MS = Const.MAP_REVEAL_COOLDOWN_MS

-- Blocs de 32 cases par côté : le plus grand nombre impair qui tient dans Const.MAP_REVEAL_MAX_SIDE (au moins 1).
function MapMarks.revealBlocks()
    local blocks = math.floor(Const.MAP_REVEAL_MAX_SIDE / Const.MAP_REVEAL_BLOCK)
    if blocks % 2 == 0 then blocks = blocks - 1 end
    if blocks < 1 then blocks = 1 end
    return blocks
end

-- Bornes de la carte en cases (x2, y2 exclus) : cellules de 256 cases de la métagrille ; nil hors partie.
function MapMarks.mapBounds()
    if type(getWorld) ~= "function" then return nil end
    local world = getWorld()
    local grid = world and world.getMetaGrid and world:getMetaGrid() or nil
    if grid == nil then return nil end
    return { x1 = grid:getMinX() * 256, y1 = grid:getMinY() * 256,
             x2 = (grid:getMaxX() + 1) * 256, y2 = (grid:getMaxY() + 1) * 256 }
end

-- Rectangle révélé autour de la case (x, y) : { x1, y1, x2, y2 } en cases, x2 et y2 exclus, chaque bord multiple de
-- 32, côté d'au plus MapMarks.revealBlocks() blocs ; rogné à bounds (sans bornes : aux coordonnées positives). nil si
-- rien ne reste (lieu hors de la carte).
function MapMarks.revealRect(x, y, bounds)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local size = Const.MAP_REVEAL_BLOCK
    local radius = (MapMarks.revealBlocks() - 1) / 2
    local bx, by = math.floor(x / size), math.floor(y / size)
    local rect = { x1 = (bx - radius) * size, y1 = (by - radius) * size,
                   x2 = (bx + radius + 1) * size, y2 = (by + radius + 1) * size }
    local b = bounds or { x1 = 0, y1 = 0 }
    if b.x1 and rect.x1 < b.x1 then rect.x1 = b.x1 end
    if b.y1 and rect.y1 < b.y1 then rect.y1 = b.y1 end
    if b.x2 and rect.x2 > b.x2 then rect.x2 = b.x2 end
    if b.y2 and rect.y2 > b.y2 then rect.y2 = b.y2 end
    if rect.x2 <= rect.x1 or rect.y2 <= rect.y1 then return nil end
    return rect
end

-- Inscription dans la carte connue du compte de l'appelant, tenue par le serveur multijoueur (voir l'en-tête). Bord
-- haut inclus pour Java (dernière case du rectangle) : WorldMapVisited.coordToUnit garde le bloc de cette case.
local function storeOnServer(player, rect)
    if not isServer() or WorldMapVisitedServer == nil then return end
    WorldMapVisitedServer.getInstance():setKnownInSquares(player, rect.x1, rect.y1, rect.x2 - 1, rect.y2 - 1)
end

local function reveal(params, ctx)
    if type(ctx) ~= "table" then return false, "failed" end
    local place = MapMarks.placeOf(ctx.sheet, params.place)
    if place == nil then return false, "failed" end
    if ctx.player == nil then return false, "no_player" end
    local rect = MapMarks.revealRect(place.x, place.y, MapMarks.mapBounds())
    if rect == nil then return false, "off_map" end
    storeOnServer(ctx.player, rect)
    Const.toClient(ctx.player, Const.CMD.MAP_REVEAL, rect)
    if ctx.cid then Log.add(ctx.cid, ctx.khz, "reveal", place.label) end
    return true
end

function MapMarks.register()
    local marked = Actions.register("mark_map", { validate = validate, cooldownMs = MapMarks.COOLDOWN_MS,
        execute = execute })
    local revealed = Actions.register("reveal_area", { validate = validate, cooldownMs = MapMarks.REVEAL_COOLDOWN_MS,
        execute = reveal })
    return marked and revealed
end

MapMarks.register()

return MapMarks
