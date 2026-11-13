-- Living Knox : aménagement des foyers des groupes au premier chargement réel de leurs cases (LK08-T04).
-- Fiche : docs/annexes/conception/foyers.md. Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Quand : un groupe qui a un foyer (LivingKnox.Groups, champ home) et aucune marque d'aménagement pour ce foyer est
-- examiné à chaque LoadChunk (au plus une fois par SCAN_MS) et à chaque minute de jeu (chunk déjà chargé : LoadChunk
-- ne revient pas). Rien n'est tenté tant que la case du foyer et les quatre coins du carré de RADIUS cases ne sont pas
-- lisibles (getCell():getGridSquare, nil hors zone chargée, aussi sur un serveur) ; pour un bâtiment, tant que
-- BuildingDef:isFullyStreamedIn() est faux et qu'aucune pièce n'est explorée (l'histoire de bâtiment vanilla, qui
-- peut vider ou retirer des objets, passe avant LoadChunk et seulement sur un bâtiment complet jamais exploré : base
-- world-placement.md, « Quand poser »).
-- Quoi (objets vanilla seulement, quantités modestes, tous démontables ou ramassables par un joueur ; LK16-T10 : un
-- aménagement par fichier sous Furnishings/, inscrit par Homes.registerFurnishing, voir « aménagements » plus bas) :
--   bâtiment (case du foyer dans une pièce, même règle que LK_Routines) : planches sur WINDOWS fenêtres fermées et non
--     barricadées du bâtiment, au niveau du foyer, côté extérieur, les plus éloignées du foyer d'abord (PLANKS planches
--     chacune : au plus 2, la vue reste dégagée, J/iso/objects/IsoBarricade.java:234-236) ; une lampe sur pile
--     allumée (lumière visible de l'extérieur sans courant) ; des sacs de couchage jusqu'à un couchage par membre
--     vivant (MAX_BEDS au plus, lits existants comptés) ; une caisse vide (réserve, LK08-T06 la remplira) ;
--   camp (case du foyer hors de toute pièce) : un feu de camp allumé (système vanilla SCampfireSystem) et une tente
--     pour PER_TENT membres vivants (MAX_TENTS au plus) autour du feu.
--   Cases utilisées : praticables (isFree(false)), sans escalier, eau, buisson, meuble déplaçable ni objet au sol ;
--   dans le bâtiment du foyer (bâtiment) ou hors de tout bâtiment (camp) ; ni la case du foyer et son pourtour
--   (bâtiment), ni une case intérieure
--   contre une porte ou une fenêtre (postes de guet de LK_Routines), ni le pourtour d'un objet déjà posé.
-- Comment : pose comme le vanilla, sans personnage : meubles par ISMoveableSpriteProps:placeMoveableInternal(nil, ...)
--   avec l'objet d'inventaire du sprite (M/shared/Moveables/ISMoveableSpriteProps.lua:215-244, 2075-2560 : objet
--   créé, ajouté à la case et transmis aux clients par transmitCompleteItemToClients sur un serveur) et, pour un
--   meuble de plusieurs cases (tente, sac de couchage), une pose par case de la grille de sprites comme la pose
--   vanilla d'un objet ForceSingleItem (:2024-2044) ; lampe : objet Moveable réglé sur pile (setLightUseBattery,
--   setLightHasBattery, setLightPower) relu par IsoLightSwitch.getCustomSettingsFromItem
--   (J/iso/objects/IsoLightSwitch.java:531-543), puis switchLight(true) (la source de lumière créée avant la pile
--   reste éteinte, :104-116, 457-476) ; barricade comme IsoWindow.addRandomBarricades (J/iso/objects/IsoWindow.java
--   :1324-1343 : côté sans pièce, addPlank(nil, nil), transmitCompleteItemToClients) ; feu par
--   SCampfireSystem.instance:addCampfire(case), addFuel(FIRE_FUEL minutes), lightFire() (M/server/Camping).
--   Chaque objet posé porte ModData[TAG] = identifiant du groupe et ModData[TAG_KIND] = sorte (copiés de l'objet
--   d'inventaire avant la transmission, ISMoveableSpriteProps.lua:2423-2432) ; le feu de camp n'est pas marqué
--   (ModData gérée par son système global). Barricade : marque sur la fenêtre (ModData[TAG_SIDE] = côté de la
--   barricade), la ModData d'une IsoBarricade n'étant jamais sauvegardée (IsoBarricade.java:621-632).
-- Une seule fois, sans doublon : marque persistante côté serveur dans le registre privé des groupes (champ facultatif
--   furnish, schéma 1 inchangé, contrôlé ici) : { v = FORMAT, hx, hy, hz, style = "building" | "camp", day,
--   state = "placing" | "done", placed = { { k, x, y, z }, ... } }. Écrite AVANT la pose (une erreur Java en pleine
--   pose ou un arrêt ne fait jamais reposer) ; une marque « placing » relue au redémarrage vaut « fait » (journalisé).
--   Foyer déplacé (setHome) : marque périmée, nouvel aménagement au nouveau foyer, l'ancien reste en place. Garde si
--   le registre recule (fichier plus ancien que le monde) : sans marque, un objet marqué du groupe trouvé autour du
--   foyer rétablit la marque sans rien poser (Homes.findTagged) ; en plus, une case occupée n'est plus libre, une
--   fenêtre déjà barricadée est écartée et addCampfire refuse une case qui a déjà un feu.
-- Générateurs du groupe (LK05-T19, entretien de LK_Upkeep limité à eux) : à l'aménagement d'un foyer de bâtiment, juste
--   avant la marque, chaque IsoGenerator du bâtiment du foyer (zone du foyer, niveau du foyer) sans marque de groupe
--   reçoit ModData[GEN_TAG] = identifiant du groupe (Homes.adoptGenerators ; ModData sauvegardée avec l'objet :
--   IsoGenerator.save appelle IsoObject.save, J/iso/objects/IsoGenerator.java:382-384). Un générateur ramassé puis
--   reposé perd la marque (setInfoFromItem ne recopie que le carburant et l'état, :128-134). Aucun autre générateur
--   n'est jamais marqué : celui d'un joueur, posé après, n'est jamais entretenu.
-- Après la pose : LivingKnox.Routines.resurvey(gid) (couchages et postes relevés de nouveau).
-- Homes.clear(gid) retire ce qui a été posé (objets marqués dans la zone chargée, feu de la marque) et efface la marque
-- (suite en jeu, administration).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Groups"

local Homes = LivingKnox.Homes or {}
LivingKnox.Homes = Homes

Homes.FORMAT = 1
Homes.TAG = "LKHome"
Homes.TAG_KIND = "LKHomeKind"
Homes.TAG_SIDE = "LKHomeSide"   -- fenêtre barricadée : côté de la barricade du groupe ("same" | "opposite")
Homes.GEN_TAG = "LKGenerator"   -- LK05-T19 : générateur du groupe (ModData de l'IsoGenerator)
Homes.STYLES = { building = true, camp = true }
Homes.MAX_PLACED = 32

-- ================================================================ aménagements (LK16-T10)
-- Ce module ne décrit AUCUN aménagement : chacun s'inscrit par Homes.registerFurnishing(kind, spec) depuis son fichier
-- media/lua/server/LivingKnox/Furnishings/LK_Furnish_<Nom>.lua (chargé par le jeu, sous-dossiers compris, après ce
-- module qu'il requiert). Les tables KINDS (sortes acceptées dans la marque) et FURNITURE (meubles vanilla : sprite
-- d'ancrage et emprise w en x, h en y depuis l'ancrage) en sont DÉRIVÉES à chaque inscription. spec :
--   kind     : nom unique (premier argument ; a.k du plan, ModData[TAG_KIND], journal), minuscules, chiffres, « _ »
--   order    : rang dans le registre, plus petit d'abord ; à égalité, par kind : ordre du plan d'un style et du journal
--   style    : style de foyer aménagé (« building » ou « camp »)
--   plan(ctx, out) : ajoute ses actions { k, x, y, z, ... } à out (plan du style, déjà rempli par les aménagements
--              d'ordre plus petit). ctx : cell, home, z, members (membres vivants), cfg (Homes.CFG), taken (cases
--              réservées), fits(x, y, w, h) (emprise libre pour ce style), reserve(x, y, w, h), info (rendue par le
--              plan) ; bâtiment : bid, inside (cases du bâtiment triées par Homes.byPlace), windows (fenêtres fermées non
--              barricadées du bord), beds (lits déjà là) ; camp : cx, cy (centre du camp, case du foyer au départ)
--   furniture : facultatif, { [nom] = { sprite, w, h } } (a.v du plan, sinon a.k)
--   prep(item) : facultatif, réglage de l'objet d'inventaire avant la pose d'un meuble
--   place(gid, a, sq) : facultatif, pose de l'action a sur sq (case chargée) ; rend vrai, ou nil et la raison ; par
--              défaut le meuble FURNITURE[a.v or a.k] posé comme un joueur (Homes.placeFurniture)
--   clear    : facultatif, retrait propre : { collect(o, sq) -> entrée gardée pour finish, ou nil (objet marqué retiré
--              de sa case) ; finish(entries, cell, mark) -> objets retirés }, finish appelé dans l'ordre du registre
-- Inscrire de nouveau un kind le remplace (rechargement).
Homes.furnishings = Homes.furnishings or { list = {}, byKind = {} }

local SPEC_FIELDS = { plan = "function", place = "function", prep = "function", furniture = "table", clear = "table" }

local function furnishingProblem(spec)
    if type(spec) ~= "table" then return "spec must be a table" end
    if type(spec.kind) ~= "string" or string.match(spec.kind, "^[a-z][a-z0-9_]*$") == nil then
        return "kind must be a lowercase name"
    end
    if type(spec.order) ~= "number" or not Homes.STYLES[spec.style] or type(spec.plan) ~= "function" then
        return spec.kind .. " needs order, style (building or camp) and plan"
    end
    for field, t in pairs(SPEC_FIELDS) do
        if spec[field] ~= nil and type(spec[field]) ~= t then return spec.kind .. "." .. field .. " must be a " .. t end
    end
    if spec.clear ~= nil and (type(spec.clear.collect) ~= "function" or type(spec.clear.finish) ~= "function") then
        return spec.kind .. ".clear needs collect and finish"
    end
    return nil
end

local function validFurnishing(spec)
    local why = furnishingProblem(spec)
    return why == nil, why
end

-- LK16-T01 : socle commun (LivingKnox.Registry) ; Homes.furnishings.list et byKind en sont la liste triée et l'index.
local furnishingRegistry = LivingKnox.Registry.new("LivingKnox.Homes.registerFurnishing",
    { key = "kind", validate = validFurnishing, items = Homes.furnishings.list, byKey = Homes.furnishings.byKind })

-- Tables dérivées du registre (une seule source : les specs inscrites).
local function deriveFurnishings()
    local kinds, furniture = {}, {}
    for _, s in ipairs(Homes.furnishings.list) do
        kinds[s.kind] = true
        for name, f in pairs(s.furniture or {}) do furniture[name] = f end
    end
    Homes.KINDS, Homes.FURNITURE = kinds, furniture
end

-- Inscrit l'aménagement kind décrit par spec (voir plus haut) ; rend spec. Erreur claire si spec est invalide : rien
-- n'est inscrit.
function Homes.registerFurnishing(kind, spec)
    if type(spec) == "table" then spec.kind = kind end
    furnishingRegistry:register(spec, 2)
    deriveFurnishings()
    return spec
end

-- Spec de l'aménagement kind, ou nil.
function Homes.furnishingOf(kind)
    return furnishingRegistry:get(kind)
end

deriveFurnishings()

Homes.CFG = Homes.CFG or {
    RADIUS = 10,          -- cases autour du foyer examinées (laisse de LK_Decisions, HOME_RADIUS)
    WINDOWS = 2,          -- fenêtres barricadées au plus
    PLANKS = 2,           -- planches par fenêtre (au-delà de 2 la vue est bloquée)
    MAX_BEDS = 4,         -- couchages visés au plus (lits existants compris)
    CRATES = 1,           -- caisses vides posées
    MAX_TENTS = 3,        -- tentes au plus
    PER_TENT = 2,         -- membres vivants par tente
    FIRE_RADIUS = 2,      -- écart au foyer de la case du feu de camp
    TENT_RINGS = { 3, 4, 5 },   -- écarts des tentes au feu
    FIRE_FUEL = 120,      -- minutes de combustible du feu de camp (1 par minute allumée, SCampfireSystem)
    LAMP_POWER = 1.0,     -- charge de la pile de la lampe (0..1 ; 2,5e-4 par minute allumée : environ 2,8 jours)
    SCAN_MS = 1000,       -- examen des foyers en attente au plus une fois par seconde depuis LoadChunk
    RETRY_MS = 10000,     -- foyer non prêt : nouvel essai au plus toutes les 10 s
}

Homes.state = Homes.state or { done = {}, tried = {}, lastScan = nil }
Homes.stats = Homes.stats or { furnished = 0, notReady = 0, placed = 0, failed = 0, scans = 0 }

-- Directions orthogonales et diagonales.
local DIRS4 = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function cfg() return Homes.CFG end
local function now() return getTimestampMs() end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function key(x, y) return x .. "," .. y end

local function homeKey(home) return home.x .. "," .. home.y .. "," .. home.z end

-- ================================================================ lecture des cases

local function buildingId(sq)
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()   -- long au-delà de 2^53 : texte exact (base world-placement.md)
end
Homes.buildingId = buildingId

-- Case occupée par un meuble déplaçable (propriété de tuile IsMoveAble : meubles, lits, lampes, tentes) ou par un objet
-- au sol. En 42.21, sols, tapis, rideaux, fenêtres et appliques murales portent aussi IsMoveAble (on peut les
-- ramasser) : seul un objet de MoveType "Object" (valeur par défaut, MoveType absent) occupe la case, comme le classe
-- le vanilla (media/lua/shared/Moveables/ISMoveableSpriteProps.lua:143 ; FloorTile, FloorRug, WallObject,
-- WindowObject... ne gênent pas une pose au sol).
local function occupied(sq)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local props = o ~= nil and o:getSprite() ~= nil and o:getProperties() or nil
        if props ~= nil and props:has("IsMoveAble") then
            local moveType = props:has("MoveType") and props:get("MoveType") or "Object"
            if moveType == "Object" then return true end
        end
    end
    local items = sq:getWorldObjects()
    return items ~= nil and items:size() > 0
end

-- Case où poser : praticable (sol solide, ni mur plein, ni meuble plein, ni arbre : J/iso/IsoGridSquare.java
-- :2894-2915), pas un escalier (isFree y est vrai), ni eau, ni buisson, ni occupée.
function Homes.clearSquare(sq)
    if sq == nil or not sq:isFree(false) or sq:HasStairs() then return false end
    if sq:isWaterSquare() or sq:hasBush() then return false end
    return not occupied(sq)
end

local function isBed(sq)
    if IsoFlagType == nil or IsoFlagType.bed == nil then return false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local props = o ~= nil and o:getSprite() ~= nil and o:getProperties() or nil
        if props ~= nil and props:has(IsoFlagType.bed) then return true end
    end
    return false
end

-- Style du foyer d'après la case chargée : "building" (case dans une pièce) ou "camp". Rend aussi le bâtiment.
local function styleOf(hsq)
    local def = hsq:getBuildingDef()
    if def == nil then return "camp", nil end
    return "building", def
end

local function anyExplored(def)
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        if rooms:get(i):isExplored() then return true end
    end
    return false
end

-- Foyer prêt à aménager ? Rend le style et le BuildingDef (ou nil), ou nil et la raison.
function Homes.ready(home)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    if hsq == nil then return nil, "home square not loaded" end
    local R = cfg().RADIUS
    for _, c in ipairs({ { -R, -R }, { R, -R }, { R, R }, { -R, R } }) do
        if cell:getGridSquare(home.x + c[1], home.y + c[2], home.z) == nil then return nil, "home area not loaded" end
    end
    local style, def = styleOf(hsq)
    if def ~= nil and not def:isFullyStreamedIn() and not anyExplored(def) then
        return nil, "building not fully streamed in"
    end
    return style, def
end

-- ================================================================ plan (lecture seule)

-- Ordre des cases d'un plan : écart au foyer, puis y, puis x.
local function byPlace(a, b)
    if a.d ~= b.d then return a.d < b.d end
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
end
Homes.byPlace = byPlace
Homes.cheb = cheb

-- Pourtour réservé : l'emprise et ses cases voisines (y compris en diagonale) ne reçoivent plus rien.
local function reserve(taken, x, y, w, h)
    for yy = y - 1, y + h do
        for xx = x - 1, x + w do taken[key(xx, yy)] = true end
    end
end

-- Emprise (x, y, w, h) entièrement libre : chaque case passe test(sq) et n'est pas réservée.
local function footprintFree(cell, x, y, z, w, h, taken, test)
    for yy = y, y + h - 1 do
        for xx = x, x + w - 1 do
            if taken[key(xx, yy)] then return false end
            if not test(cell:getGridSquare(xx, yy, z)) then return false end
        end
    end
    return true
end

-- Plan du style style : chaque aménagement de ce style, dans l'ordre du registre, ajoute ses actions.
local function planStyle(style, ctx)
    ctx.reserve = function(x, y, w, h) reserve(ctx.taken, x, y, w, h) end
    local plan = {}
    for _, s in ipairs(Homes.furnishings.list) do
        if s.style == style then s.plan(ctx, plan) end
    end
    return plan
end

-- Plan d'un foyer de bâtiment : { { k, x, y, z, ... } } dans l'ordre de pose. members = membres vivants.
function Homes.planBuilding(cell, home, bid, members)
    local c, R, z = cfg(), cfg().RADIUS, home.z
    local inside, windows, edge = {}, {}, {}
    local beds, bedSeen = 0, {}
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil and buildingId(sq) == bid then
                inside[#inside + 1] = { x = x, y = y, d = cheb(x, y, home.x, home.y) }
                if isBed(sq) then
                    -- Une case de lit voisine d'une case de lit déjà comptée = le même lit (lit double).
                    local same = false
                    for _, b in ipairs(bedSeen) do
                        if cheb(x, y, b.x, b.y) <= 1 then same = true end
                    end
                    bedSeen[#bedSeen + 1] = { x = x, y = y }
                    if not same then beds = beds + 1 end
                end
                for _, d in ipairs(DIRS4) do
                    local nb = cell:getGridSquare(x + d[1], y + d[2], z)
                    if nb ~= nil and buildingId(nb) ~= bid then
                        if sq:getDoorTo(nb) ~= nil or sq:getWindowThumpableTo(nb) ~= nil then
                            edge[key(x, y)] = true
                        end
                        local w = sq:getWindowTo(nb)
                        if w ~= nil then
                            edge[key(x, y)] = true
                            if instanceof(w, "IsoWindow") and not w:IsOpen() and not w:isBarricaded() then
                                windows[#windows + 1] = { x = x, y = y, z = z, nx = x + d[1], ny = y + d[2],
                                    d = cheb(x, y, home.x, home.y) }
                            end
                        end
                    end
                end
            end
        end
    end
    local taken = {}
    reserve(taken, home.x, home.y, 1, 1)   -- case du foyer et son pourtour : lieu de rassemblement
    for k in pairs(edge) do taken[k] = true end
    local function inBuilding(sq) return Homes.clearSquare(sq) and buildingId(sq) == bid end
    table.sort(inside, byPlace)
    local ctx = { cell = cell, home = home, z = z, members = members, cfg = c, taken = taken, bid = bid,
                  inside = inside, windows = windows, beds = beds,
                  info = { beds = beds, windows = #windows, squares = #inside } }
    ctx.fits = function(x, y, w, h) return footprintFree(cell, x, y, z, w, h, taken, inBuilding) end
    return planStyle("building", ctx), ctx.info
end

-- Plan d'un camp (feu près du foyer, tentes autour du feu, selon les aménagements inscrits).
function Homes.planCamp(cell, home, members)
    local c, z = cfg(), home.z
    local function outdoor(sq) return Homes.clearSquare(sq) and buildingId(sq) == nil end
    local taken = {}
    local ctx = { cell = cell, home = home, z = z, members = members, cfg = c, taken = taken, cx = home.x,
                  cy = home.y, info = {} }
    ctx.fits = function(x, y, w, h) return footprintFree(cell, x, y, z, w, h, taken, outdoor) end
    return planStyle("camp", ctx), ctx.info
end

-- ================================================================ pose (autorité)

-- Marque l'objet o (objet posé ou objet d'inventaire) comme aménagement kind du groupe gid.
local function tagObject(o, gid, kind)
    local md = o:getModData()
    md[Homes.TAG] = gid
    md[Homes.TAG_KIND] = kind
end
Homes.tagObject = tagObject

-- Vrai si l'objet o porte la marque du groupe gid.
local function tagged(o, gid)
    return o ~= nil and o:hasModData() and o:getModData()[Homes.TAG] == gid
end
Homes.isTagged = tagged

-- ================================================================ générateurs du groupe (LK05-T19)

-- Vrai si l'objet o est un générateur marqué comme celui du groupe gid.
function Homes.groupGenerator(o, gid)
    return gid ~= nil and instanceof(o, "IsoGenerator") and o:hasModData() and o:getModData()[Homes.GEN_TAG] == gid
end

-- Marque le générateur gen comme celui du groupe gid (autorité ; suites de test, aménagement).
function Homes.markGenerator(gen, gid)
    gen:getModData()[Homes.GEN_TAG] = gid
end

-- Marque les générateurs sans marque du bâtiment bid autour du foyer home (zone du foyer, niveau du foyer) comme ceux
-- du groupe gid. Rend le nombre de générateurs marqués.
function Homes.adoptGenerators(gid, home, bid)
    local cell = getCell()
    if cell == nil or bid == nil then return 0 end
    local R, n = cfg().RADIUS, 0
    for dy = -R, R do
        for dx = -R, R do
            local sq = cell:getGridSquare(home.x + dx, home.y + dy, home.z)
            if sq ~= nil and buildingId(sq) == bid then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if instanceof(o, "IsoGenerator") and (not o:hasModData() or o:getModData()[Homes.GEN_TAG] == nil) then
                        Homes.markGenerator(o, gid)
                        n = n + 1
                    end
                end
            end
        end
    end
    return n
end

-- Cases d'un meuble (grille de sprites vanilla pour un meuble de plusieurs cases) : { { square, sprite } }.
local function gridOf(props, sq)
    if not props.isMultiSprite then return { { square = sq, sprite = props.sprite } } end
    local info = props:getSpriteGridInfo(sq, false)
    if info == nil then return nil end
    local out = {}
    for _, m in ipairs(info) do out[#out + 1] = { square = m.square, sprite = m.sprite } end
    return out
end

-- Pose un meuble vanilla d'ancrage spriteName sur sq, comme un joueur (sans personnage). prep(item) règle l'objet
-- d'inventaire avant la pose. Rend le nombre de cases posées, ou nil et la raison.
local function placeSprite(gid, kind, sq, spriteName, prep)
    local sprite = getSprite(spriteName)
    if sprite == nil then return nil, "unknown sprite " .. spriteName end
    local props = ISMoveableSpriteProps.new(sprite)
    if not props.isMoveable then return nil, "sprite not movable " .. spriteName end
    local grid = gridOf(props, sq)
    if grid == nil then return nil, "no sprite grid" end
    for _, m in ipairs(grid) do
        if m.square == nil or m.sprite == nil or not Homes.clearSquare(m.square) then
            return nil, "square no longer free"
        end
    end
    for _, m in ipairs(grid) do
        local name = m.sprite:getName()
        local item = props:instanceItem(name)
        if item == nil then return nil, "no item for " .. name end
        tagObject(item, gid, kind)
        if prep then prep(item) end
        props:placeMoveableInternal(nil, m.square, item, name)
    end
    return #grid
end

-- Pose par défaut d'une action a du plan sur sq : le meuble FURNITURE[a.v or a.k], marqué de la sorte a.k ; prep(item)
-- facultatif règle l'objet d'inventaire avant la pose. Rend vrai, ou nil et la raison.
function Homes.placeFurniture(gid, a, sq, prep)
    local f = Homes.FURNITURE[a.v or a.k]
    if f == nil then return nil, "unknown furniture " .. tostring(a.v) end
    local n, why = placeSprite(gid, a.k, sq, f.sprite, prep)
    if n == nil then return nil, why end
    return true
end

-- Pose une action du plan par son aménagement (spec.place, sinon le meuble). Rend vrai, ou nil et la raison.
function Homes.applyAction(gid, a)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local sq = cell:getGridSquare(a.x, a.y, a.z)
    if sq == nil then return nil, "square not loaded" end
    local spec = furnishingRegistry:get(a.k)
    if spec == nil then return nil, "unknown furniture " .. tostring(a.v) end
    if spec.place ~= nil then return spec.place(gid, a, sq) end
    return Homes.placeFurniture(gid, a, sq, spec.prep)
end

-- ================================================================ marque (registre des groupes)

-- Forme de la marque pour le foyer home. Rend vrai, ou faux et une raison.
function Homes.validMark(m, home)
    if type(m) ~= "table" or m.v ~= Homes.FORMAT then return false, "unknown format" end
    if type(home) ~= "table" or m.hx ~= home.x or m.hy ~= home.y or m.hz ~= home.z then return false, "home moved" end
    if not Homes.STYLES[m.style] then return false, "bad style" end
    if m.state ~= "placing" and m.state ~= "done" then return false, "bad state" end
    if m.placed ~= nil then
        if type(m.placed) ~= "table" or #m.placed > Homes.MAX_PLACED then return false, "bad placed list" end
        for _, p in ipairs(m.placed) do
            if type(p) ~= "table" or not Homes.KINDS[p.k] or not isInt(p.x, 0, 2147483647)
                or not isInt(p.y, 0, 2147483647) or not isInt(p.z, -32, 31) then
                return false, "bad placed entry"
            end
        end
    end
    return true
end

-- Objets déjà posés pour ce groupe autour du foyer (marque TAG, zone chargée) : { { k, x, y, z } } (une entrée par
-- case marquée, MAX_PLACED au plus). Sert de garde si la marque manque alors que la pose a eu lieu (registre relu
-- d'une sauvegarde plus ancienne que le monde).
function Homes.findTagged(gid, home)
    local cell = getCell()
    local out = {}
    if cell == nil then return out end
    local R = cfg().RADIUS + 2
    for dy = -R, R do
        for dx = -R, R do
            local sq = cell:getGridSquare(home.x + dx, home.y + dy, home.z)
            if sq ~= nil then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if tagged(o, gid) and #out < Homes.MAX_PLACED then
                        local kind = o:getModData()[Homes.TAG_KIND]
                        out[#out + 1] = { k = Homes.KINDS[kind] and kind or "crate", x = sq:getX(), y = sq:getY(),
                                          z = sq:getZ() }
                    end
                end
            end
        end
    end
    return out
end

local function writeMark(gid, mark)
    return Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil then return false, false end
        live.furnish = mark
        return true, true
    end)
end

-- Marque le foyer actuel d'un groupe comme aménagé sans rien poser (groupes des suites de test, qui ne doivent pas
-- barricader ni meubler le site de leurs essais). Rend vrai si la marque est écrite.
function Homes.skip(gid)
    local g = Groups().get(gid)
    if g == nil or type(g.home) ~= "table" then return false end
    local home = g.home
    local ok = writeMark(gid, { v = Homes.FORMAT, hx = home.x, hy = home.y, hz = home.z, style = "building",
                                day = Groups().today(), state = "done", placed = {} })
    if ok then Homes.state.done[gid] = homeKey(home) end
    return ok == true
end

-- Foyers en attente d'aménagement : { { gid, home, members } } triés par identifiant (lecture du registre sans copie).
function Homes.pending()
    local out = Groups().update(function(data)
        local list = {}
        for gid, g in pairs(data.groups) do
            local home = g.home
            -- Groupe disparu (LK09-T04) : foyer abandonné, jamais aménagé après coup.
            if type(home) == "table" and g.gone == nil and not Homes.validMark(g.furnish, home) then
                local alive = 0
                for _, m in pairs(g.members) do
                    if m.alive then alive = alive + 1 end
                end
                list[#list + 1] = { gid = gid, home = { x = home.x, y = home.y, z = home.z }, members = alive }
            end
        end
        return false, list
    end)
    if type(out) ~= "table" then return {} end
    table.sort(out, function(a, b) return a.gid < b.gid end)
    return out
end

-- ================================================================ aménagement

-- Aménage le foyer d'un groupe s'il est prêt et pas encore aménagé. opts.force : sans attendre RETRY_MS.
-- Rend "done" (déjà fait), la marque écrite (aménagé maintenant), ou nil et la raison.
function Homes.check(gid, opts)
    opts = opts or {}
    local st = Homes.state
    local g = Groups().get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no group or no home" end
    local home = g.home
    local hk = homeKey(home)
    if st.done[gid] == hk then return "done" end
    local ok = Homes.validMark(g.furnish, home)
    if ok then
        if g.furnish.state == "placing" then
            log().warn("homes: group %s home %s was left half furnished (interrupted); not furnished again", gid, hk)
        end
        st.done[gid] = hk
        return "done"
    end
    local t = now()
    if not opts.force and st.tried[gid] ~= nil and t - st.tried[gid] < cfg().RETRY_MS then return nil, "retry later" end
    st.tried[gid] = t
    local style, def = Homes.ready(home)
    if style == nil then
        Homes.stats.notReady = Homes.stats.notReady + 1
        log().debug("homes: group %s home %s not ready: %s", gid, hk, tostring(def))
        return nil, def
    end
    local found = Homes.findTagged(gid, home)
    if #found > 0 then
        local restored = { v = Homes.FORMAT, hx = home.x, hy = home.y, hz = home.z, style = style,
                           day = Groups().today(), state = "done", placed = found }
        writeMark(gid, restored)
        st.done[gid] = hk
        log().warn("homes: group %s home %s already has %d furnishing object(s) but no mark: mark restored, nothing"
            .. " placed", gid, hk, #found)
        return restored
    end
    local alive = 0
    for _, m in pairs(g.members) do
        if m.alive then alive = alive + 1 end
    end
    local cell = getCell()
    local plan
    if style == "building" then
        plan = Homes.planBuilding(cell, home, def:getIDString(), alive)
    else
        plan = Homes.planCamp(cell, home, alive)
    end
    if style == "building" then
        -- LK05-T19 : générateurs déjà là quand le bâtiment devient le foyer = ceux du groupe. Avant la marque : un arrêt
        -- entre les deux refait seulement ce marquage (sans effet sur un générateur déjà marqué).
        local adopted = Homes.adoptGenerators(gid, home, def:getIDString())
        if adopted > 0 then log().info("homes: group %s home %s: %d generator(s) of the building marked as the group's",
            gid, hk, adopted) end
    end
    local mark = { v = Homes.FORMAT, hx = home.x, hy = home.y, hz = home.z, style = style, day = Groups().today(),
                   state = "placing", placed = {} }
    if g.furnish ~= nil then log().warn("homes: group %s furnish mark replaced (home moved or bad mark)", gid) end
    if not writeMark(gid, mark) or not Groups().flush() then   -- LK13-T06 : marque écrite avant le monde
        log().warn("homes: group %s home %s: mark not written, nothing placed", gid, hk)
        return nil, "mark not written"
    end
    local counts, failed = {}, 0
    for _, a in ipairs(plan) do
        -- Une erreur Java pendant une pose n'empêche pas les suivantes ni la marque « done » (marque déjà écrite).
        local done, res, why = pcall(Homes.applyAction, gid, a)
        if done and res == true then
            mark.placed[#mark.placed + 1] = { k = a.k, x = a.x, y = a.y, z = a.z }
            counts[a.k] = (counts[a.k] or 0) + 1
        else
            failed = failed + 1
            log().warn("homes: group %s: %s at %d,%d,%d not placed: %s", gid, a.k, a.x, a.y, a.z,
                tostring(done and why or res))
        end
    end
    mark.state = "done"
    writeMark(gid, mark)
    st.done[gid] = hk
    Homes.stats.furnished = Homes.stats.furnished + 1
    Homes.stats.placed = Homes.stats.placed + #mark.placed
    Homes.stats.failed = Homes.stats.failed + failed
    local parts = {}
    for _, s in ipairs(Homes.furnishings.list) do
        if counts[s.kind] then parts[#parts + 1] = counts[s.kind] .. " " .. s.kind end
    end
    log().info("homes: group %s home %s furnished (%s, %d member(s)): %s%s", gid, hk, style, alive,
        #parts > 0 and table.concat(parts, ", ") or "nothing", failed > 0 and (", " .. failed .. " failed") or "")
    local R = LivingKnox.Routines
    if R and R.resurvey then R.resurvey(gid) end
    return mark
end

-- Examine les foyers en attente dont la case est chargée. reason = "chunk" (au plus une fois par SCAN_MS) ou
-- "minute". Rend le nombre de foyers aménagés.
function Homes.scan(reason)
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local st = Homes.state
    local t = now()
    if reason == "chunk" and st.lastScan ~= nil and t - st.lastScan < cfg().SCAN_MS then return 0 end
    st.lastScan = t
    local cell = getCell()
    if cell == nil then return 0 end
    Homes.stats.scans = Homes.stats.scans + 1
    local n = 0
    for _, p in ipairs(Homes.pending()) do
        if cell:getGridSquare(p.home.x, p.home.y, p.home.z) ~= nil then
            local res = Homes.check(p.gid)
            if type(res) == "table" then n = n + 1 end
        end
    end
    return n
end

-- Retire ce qui a été posé pour un groupe (objets marqués dans la zone chargée autour du foyer de la marque ; retrait
-- propre à un aménagement par son clear, par exemple barricade d'une fenêtre ou feu de camp de la marque) et efface la
-- marque. Rend le nombre d'objets retirés.
function Homes.clear(gid)
    local g = Groups().get(gid)
    local m = g and g.furnish
    local removed, kept = 0, {}
    local cell = getCell()
    if cell ~= nil and type(m) == "table" and isInt(m.hx, 0, 2147483647) and isInt(m.hy, 0, 2147483647)
        and isInt(m.hz, -32, 31) then
        local R = cfg().RADIUS + 8
        for dy = -R, R do
            for dx = -R, R do
                local sq = cell:getGridSquare(m.hx + dx, m.hy + dy, m.hz)
                if sq ~= nil then
                    local objs = sq:getObjects()
                    for i = objs:size() - 1, 0, -1 do
                        local o = objs:get(i)
                        if tagged(o, gid) then
                            local kind = o:getModData()[Homes.TAG_KIND]
                            local spec = furnishingRegistry:get(kind)
                            local entry = spec ~= nil and spec.clear ~= nil and spec.clear.collect(o, sq) or nil
                            if entry ~= nil then
                                kept[kind] = kept[kind] or {}
                                kept[kind][#kept[kind] + 1] = entry
                            else
                                sq:transmitRemoveItemFromSquare(o)
                                removed = removed + 1
                            end
                        end
                    end
                end
            end
        end
        for _, s in ipairs(Homes.furnishings.list) do
            if s.clear ~= nil then removed = removed + s.clear.finish(kept[s.kind] or {}, cell, m) end
        end
    end
    if g ~= nil and g.furnish ~= nil then writeMark(gid, nil) end
    Homes.state.done[gid], Homes.state.tried[gid] = nil, nil
    log().info("homes: group %s furnishing cleared, %d object(s) removed", tostring(gid), removed)
    return removed
end

function Homes.reset()
    Homes.state = { done = {}, tried = {}, lastScan = nil }
end

-- Événements : LoadChunk (fin du chargement d'un chunk, après les histoires de bâtiment et le butin :
-- J/iso/IsoChunk.java:3612) et EveryOneMinute (chunk déjà chargé).
local function onLoadChunk()
    Homes.scan("chunk")
end

local function onEveryOneMinute()
    Homes.scan("minute")
end

LivingKnox.subscribe("LoadChunk", "Homes.onLoadChunk", onLoadChunk)
LivingKnox.subscribe("EveryOneMinute", "Homes.onEveryOneMinute", onEveryOneMinute)

return Homes
