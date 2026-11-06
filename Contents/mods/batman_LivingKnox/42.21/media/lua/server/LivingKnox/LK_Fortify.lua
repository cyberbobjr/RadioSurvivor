-- Living Knox : plan de fortification du foyer d'un groupe (LK14-T02). Fiches : docs/annexes/conception/fortification.md
-- (règles vanilla 42.21, LK14-T01 ; section « Plan de fortification » pour ce module). Java 42.21.0 cité en abrégé
-- (J = zombie/...) ; M = media/scripts/generated vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Ce module ne pose rien : il lit le monde chargé et dresse la liste des chantiers du foyer, par priorité, avec les
-- matériaux vanilla qui restent à fournir et la durée ; LK14-T03 (barricades), LK14-T04 (murs, palissade) et LK14-T05
-- (rattrapage hors écran) feront le travail.
--   1. Rez-de-chaussée (niveau 0, tier "ground") : portes et fenêtres extérieures du bâtiment du foyer (objets
--      BarricadeAble dont un côté est dans le bâtiment et l'autre dehors : IsoDoor simple, IsoWindow, IsoWindowFrame
--      sans fenêtre, IsoThumpable barricadable ; isBarricadeAllowed écarte portes doubles et de garage,
--      J/iso/objects/IsoDoor.java:1699-1701), jusqu'à PLANKS.ground planches. Cadres vides d'abord (trou ouvert), puis
--      fenêtres, puis portes ; à rang égal, les plus éloignées du foyer d'abord (arrière de la maison, comme
--      LK_Homes). L'entrée du foyer (porte extérieure simple du rez-de-chaussée la plus proche de la case du foyer)
--      n'est jamais barricadée : une barricade, d'un côté ou de l'autre, bloque la porte pour tous (IsoDoor.java
--      :1320-1325, fortification.md §5.3).
--   2. Étages (niveaux 1 .. BuildingDef:getMaxLevel(), tier "upper") : mêmes ouvertures, jusqu'à PLANKS.upper planches.
--   3. Défenses extérieures (tier "outer", décision LK14-T04 du 2026-10-08) : bâtiment = murs en bois vanilla
--      (WoodenWallFrame puis WoodenWallLvl1) sur le pourtour d'un rectangle à OUTER_MARGIN cases du bâtiment ; camp =
--      palissade de rondins (LogWall) sur le pourtour d'un carré de CAMP_RING cases autour du foyer. Seuls ces deux
--      ouvrages arrêtent un zombie (fortification.md §2.2). Une brèche de 2 × GAP + 1 segments reste ouverte en face de
--      l'entrée (camp : côté sud) : le portail en bois vanilla est enjambé. Segment écarté : case hors zone chargée,
--      dans un bâtiment, eau, escalier, case impraticable, bord déjà fermé (isBlockedTo) ; pourtour de plus de
--      MAX_OUTER segments : aucune défense extérieure (bâtiment trop grand).
-- Matériaux (scripts vanilla) : barricade = 1 Base.Plank + 1 Base.Nails par planche, marteau (tag Hammer), durée 200
--   par planche (M/entities/barricades/entity_barricade_planks.txt:46-60) ; mur = cadre (2 planches, 2 clous) + mur
--   (2 planches, 4 clous), marteau, 200 + 200 (walls/entity_woodenwallframe.txt:33-43, entity_wood_walllvl1.txt
--   :37-47) ; palissade = 4 Base.Log + 4 liens (draps déchirés, ficelle, corde, corde de draps), sans outil, 200
--   (walls/entity_logwall.txt:33-41). Durées en unités des actions vanilla (environ 48 par seconde réelle à vitesse 1 :
--   base api-42-21.md « unités de durée »). Compétences requises (Menuiserie 2 pour un mur) non vérifiées : les PNJ
--   n'ont pas de niveaux.
-- Reproductible : même foyer et même monde = même plan (cases parcourues dans un ordre fixe, tri total des
--   chantiers, identifiants de chantier tirés des coordonnées). Aucun chantier hors du foyer : ouvertures du seul
--   bâtiment du foyer, segments dans le rectangle plan.bounds (bâtiment + marge, ou carré du camp, plus une case).
-- Niveau 0..100 (Fortify.levelOf(gid), interface LivingKnox.Fortification lue par LK_Decisions.fortificationOf) :
--   avancement pondéré des trois tiers (WEIGHTS), étapes faites / étapes visées (planches, cadre + mur, palissade) ;
--   foyer sans aucun chantier possible = 100. Plan gardé en mémoire PLAN_MS ; zone non chargée : dernier plan connu,
--   sinon nil (le cadre de décision prend alors sa valeur neutre).
-- Faisable : matériaux comptés dans l'inventaire de référence du stock (LivingKnox.Stock.reference ; une boîte de
--   clous vaut BOX_NAILS clous, recette OpenBox100, M/recipes/recipes_packing.txt:220-241) et outil cherché dans
--   les conteneurs du foyer (LivingKnox.Stock.findItem, hasTag(ItemTag.HAMMER)). Les chantiers faisables sont pris
--   dans l'ordre du plan, les matériaux réservés de l'un au suivant (deux ouvriers ne comptent jamais les mêmes planches).
-- Point d'appel de LK14-T03 : Fortify.siteFor(gid, mid) rend au k-ième membre de poste « builder » (numéro croissant)
--   le k-ième chantier faisable. Cadre de décision : Fortify.hasWork(gid) (LK_Decisions.groupInput, champ fortWork).
-- Barricades posées (LK14-T03, section « pose des barricades » plus bas) : un membre de poste « builder » dont la
--   cascade choisit « chore » (de jour, au foyer) reçoit son chantier de siteFor (Fortify.run, appelé par
--   LK_Routines.apply avant l'entretien et les corvées) ; il va à la case intérieure de l'ouverture, se tourne vers elle,
--   travaille avec le geste existant CFG.GESTURE pendant CFG.PLANK_MINUTES minutes de jeu par planche, puis l'autorité
--   cloue UNE planche (Fortify.nailPlank : état relu, une planche et un clou retirés du stock par LivingKnox.Stock
--   .takeItem, boîte de clous ouverte au besoin, IsoBarricade.AddBarricadeToObject + addPlank + transmission comme
--   BuildRecipeCode.barricade.OnCreate) ; il recommence jusqu'au nombre de planches visé.
-- Murs et palissade (LK14-T04, section « murs et palissade du pourtour » plus bas) : même ouvrier, même parcours ; un
--   chantier du pourtour se fait depuis sa case intérieure, geste CFG.RING_GESTURES, CFG.STAGE_MINUTES minutes avant
--   chaque étape (cadre puis mur ; palissade), posée par Fortify.buildStep (matériaux du stock retirés une seule fois,
--   ouvrage vanilla posé comme ISBuildIsoEntity:setInfo, transmis aux clients). La brèche n'est jamais construite.
-- Entretien et réparation (LK14-T06, section « réparations » plus bas, fiche §9) : le relevé note l'état de la planche
--   extérieure des barricades complètes (getThumpCondition : seule la planche extérieure s'use, IsoBarricade.java
--   :459-497) et la santé des murs et palissades achevés ; sous CFG.REPAIR_BELOW, un chantier « repair » s'ajoute au
--   plan (tier de l'ouvrage). Une planche retirée (barricade sous sa visée) reste un chantier de barricade ordinaire.
--   Après une attaque repoussée (marque LivingKnox.Defense.after de moins de CFG.REPAIR_URGENT_MINUTES), réparations
--   puis barricades entamées passent en tête du plan ; sinon les réparations viennent en dernier. Le même ouvrier
--   répare (Fortify.repair) : barricade = planche extérieure abîmée retirée (rendue au conteneur, comme
--   ISUnbarricadeAction) et planche saine clouée (1 planche + 1 clou) ; mur ou palissade = recette vanilla de
--   réparation « Wood » / « Log » (ISMoveableDefinitions.lua:656-668 : marteau, scie, planches ou rondins selon les
--   dégâts, une pièce facultative), santé remise au maximum (setHealth, synchronisé par le Java). Matériaux ou outils
--   absents : besoin noté (Fortify.needOf) et écrit au journal du groupe (kind « shortage »).
-- Rattrapage hors écran (LK14-T05, section « rattrapage hors écran » plus bas, fiche §10) : relevé du plan gardé au
--   registre privé des groupes (champ fort), avancé par la simulation (Fortify.offscreenHour, appelé par
--   LK_Simulation.advance : ouvriers, temps, outils, matériaux pris une fois dans la référence du stock par son journal
--   d'écarts), posé par Fortify.addPlanks / Fortify.placeStructure quand la zone du foyer est chargée
--   (Fortify.applyPending, marque d'application idempotente LKFortOp).
-- Persistance : plan recalculé d'après le monde ; les objets posés par LK14-T03/T04 sont sauvegardés par le jeu avec
--   leur case ; besoins de réparation en mémoire seulement ; relevé hors écran (LK14-T05) dans le registre des groupes.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"

local Fortify = LivingKnox.Fortify or {}
LivingKnox.Fortify = Fortify
LivingKnox.Fortification = Fortify   -- interface lue par LK_Decisions (levelOf)

Fortify.TIERS = { "ground", "upper", "outer" }
Fortify.KINDS = { barricade = true, wall = true, palisade = true, repair = true }
-- Rang des ouvertures dans un tier : cadre vide (trou), fenêtre, porte.
Fortify.OPENING_RANK = { frame = 1, window = 2, door = 3 }
Fortify.PLANK = "Base.Plank"
Fortify.NAILS = "Base.Nails"
Fortify.NAILS_BOX = "Base.NailsBox"
Fortify.LOG = "Base.Log"
Fortify.TIES = { "Base.RippedSheets", "Base.RippedSheetsDirty", "Base.Twine", "Base.Rope", "Base.SheetRope" }
-- Noms d'objet (getName) des ouvrages vanilla reconnus sur un bord : étapes faites.
Fortify.WALL_NAMES = { WoodenWallFrame = 1, WoodenWallLvl1 = 2, WoodenWallLvl2 = 2, WoodenWallLvl3 = 2 }
Fortify.PALISADE_NAME = "LogWall"

Fortify.CFG = Fortify.CFG or {
    PLANKS = { ground = 4, upper = 2 },   -- planches visées par ouverture (4 = maximum vanilla, IsoBarricade.java:62-67)
    OUTER_MARGIN = 2,     -- cases entre le bâtiment et le pourtour des murs
    CAMP_RING = 7,        -- demi-côté du carré de la palissade d'un camp (tentes jusqu'à 6 cases du foyer, LK_Homes)
    GAP = 1,              -- segments laissés ouverts de part et d'autre du segment en face de l'entrée
    MAX_OUTER = 96,       -- segments au plus sur le pourtour
    MAX_OPENINGS = 64,    -- ouvertures relevées au plus
    WEIGHTS = { ground = 3, upper = 1, outer = 2 },
    TIME = { plank = 200, frame = 200, wall = 200, palisade = 200, repair = 1000 },   -- unités des actions vanilla
                          -- (repair : réparation d'un ouvrage, ISMoveableDefinitions.lua:656-662, LK14-T06)
    BOX_NAILS = 100,      -- clous d'une boîte (recette OpenBox100)
    PLAN_MS = 60000,      -- plan gardé en mémoire au plus une minute réelle
    -- LK14-T03 : pose des barricades.
    GESTURE = "hammer",   -- geste existant (nœud lkactor_hammer, clip vanilla Bob_IdleHammering de l'action Build)
    PLANK_MINUTES = 2,    -- minutes de jeu de travail avant chaque planche
    REST_MINUTES = 2,     -- chantier fini ou abandonné : pas de nouveau chantier avant
    IDLE_MINUTES = 10,    -- aucun chantier pour ce membre : nouvel essai après
    -- LK14-T04 : murs et palissade du pourtour.
    STAGE_MINUTES = 2,    -- minutes de jeu de travail avant chaque étape (cadre, mur, palissade : 200 unités chacune)
    RING_GESTURES = { wall = "hammer", palisade = "rummage" },   -- gestes existants (actions vanilla BuildWallHammer :
                          -- Build ; BuildWallNoTool : Loot, M/scripts/generated/timedactions.txt:828-858)
}
-- LK14-T06 : entretien et réparation (valeurs de départ propres au mod, à recalibrer en jeu).
Fortify.CFG.REPAIR_BELOW = Fortify.CFG.REPAIR_BELOW or 0.75   -- état (0..1) sous lequel planche ou ouvrage est réparé
Fortify.CFG.REPAIR_URGENT_MINUTES = Fortify.CFG.REPAIR_URGENT_MINUTES or 1440   -- après une attaque : réparations en tête
Fortify.CFG.REPAIR_MINUTES = Fortify.CFG.REPAIR_MINUTES or { barricade = 4, wall = 10, palisade = 10 }   -- minutes de
                          -- jeu de travail : retrait + pose d'une planche (200 + 200 unités) ; réparation vanilla 1000
Fortify.CFG.NEED_HOURS = Fortify.CFG.NEED_HOURS or 6   -- même besoin de matériaux au journal au plus toutes les 6 h

Fortify.state = Fortify.state or { plans = {} }
Fortify.state.rest = Fortify.state.rest or {}       -- LK14-T03 : npcId -> minute de jeu avant un nouveau chantier
Fortify.state.claims = Fortify.state.claims or {}   -- LK14-T03 : "gid|chantier" -> npcId qui y travaille
Fortify.stats = Fortify.stats or { surveys = 0, notReady = 0, changed = 0 }
for _, k in ipairs({ "started", "planks", "finished", "skipped", "boxes", "stages", "corners", "repairs", "needs" }) do
    Fortify.stats[k] = Fortify.stats[k] or 0   -- LK14-T03/T04/T06
end
Fortify.state.needs = Fortify.state.needs or {}   -- LK14-T06 : gid -> besoin de réparation { materials, tools, ... }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Homes() return LivingKnox.Homes end
local function cfg() return Fortify.CFG end
-- LK13-T11 : relevé de la minute fait dans une image suivante avec l'heure de la minute (Fortify.clockAt, file
-- Fortify.minuteJobs plus bas) : PLAN_MS compté comme si le relevé avait été fait dans l'image de la minute.
local function now() return Fortify.clockAt or getTimestampMs() end
local settle   -- LK13-T11 : relevé en file du groupe gid fait tout de suite (défini avec la file, plus bas)

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function buildingId(sq)
    if sq == nil then return nil end
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()
end

-- ================================================================ lecture du monde

-- Sorte d'ouverture barricadable d'un objet ("door", "window", "frame"), ou nil.
function Fortify.openingKind(o)
    if instanceof(o, "IsoDoor") then return "door" end
    if instanceof(o, "IsoWindow") then return "window" end
    if instanceof(o, "IsoWindowFrame") then return "frame" end
    if instanceof(o, "IsoThumpable") and o:isBarricadeAllowed() then
        return o:isDoor() and "door" or "window"
    end
    return nil
end

-- Planches d'une barricade (métal : complète), et vrai si elle est en métal.
local function planksOf(b)
    if b == nil then return 0, false end
    if b:isMetal() or b:isMetalBar() then return 4, true end
    return b:getNumPlanks(), false
end

-- LK14-T06 : état (0..1) de la planche extérieure d'une barricade de bois, la seule que les coups usent
-- (IsoBarricade.getThumpCondition, J/iso/objects/IsoBarricade.java:536-549 ; Damage :459-497), ou nil.
function Fortify.outerCondition(b)
    if b == nil or b:isMetal() or b:isMetalBar() or b:getNumPlanks() <= 0 then return nil end
    return b:getThumpCondition()
end

-- LK14-T06 : santé relative (0..1) d'un ouvrage IsoThumpable, ou nil.
function Fortify.healthRatio(o)
    local mx = o ~= nil and o:getMaxHealth() or 0
    if mx == nil or mx <= 0 then return nil end
    return o:getHealth() / mx
end

-- Ouvertures extérieures du bâtiment bid au niveau z : liste { kind, x, y, z, north, inX, inY, outX, outY, opp,
-- planks, metal, allowed }. Objet sur le bord nord ou ouest de sa case (x, y) ; l'autre côté est (x, y - 1) ou
-- (x - 1, y). Cases du rectangle du bâtiment, fin comprise (les bords sud et est sont portés par les cases
-- X2 / Y2, hors du rectangle).
function Fortify.openingsAt(cell, def, bid, z)
    local out = {}
    for y = def:getY(), def:getY2() do
        for x = def:getX(), def:getX2() do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local kind = o ~= nil and Fortify.openingKind(o) or nil
                    -- Cadre qui porte une fenêtre : la fenêtre seule compte (IsoWindowFrame.java:104-106).
                    if kind == "frame" and not o:isBarricadeAllowed() then kind = nil end
                    if kind ~= nil then
                        local north = o:getNorth() == true
                        local ox, oy = x, y - 1
                        if not north then ox, oy = x - 1, y end
                        local inA = buildingId(sq) == bid
                        local inB = buildingId(cell:getGridSquare(ox, oy, z)) == bid
                        if inA ~= inB then
                            local b1, b2 = o:getBarricadeOnSameSquare(), o:getBarricadeOnOppositeSquare()
                            local p1, metal1 = planksOf(b1)
                            local p2, metal2 = planksOf(b2)
                            local e = { kind = kind, x = x, y = y, z = z, north = north,
                                planks = math.max(p1, p2), metal = metal1 or metal2,
                                allowed = o:isBarricadeAllowed() == true, opp = inA }
                            -- LK14-T06 : état de la planche extérieure de la barricade la plus garnie (bois).
                            if not e.metal and e.planks > 0 then
                                e.cond = Fortify.outerCondition((p1 > 0 and p1 >= p2) and b1 or b2)
                            end
                            if inA then
                                e.inX, e.inY, e.outX, e.outY = x, y, ox, oy
                            else
                                e.inX, e.inY, e.outX, e.outY = ox, oy, x, y
                            end
                            out[#out + 1] = e
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Étapes faites sur le bord d'un segment (case porteuse sq, face north) : "wall", 1 ou 2 ; "palisade", 1 ; ou nil ;
-- puis l'ouvrage (LK14-T06).
local function builtOn(sq, north)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) == north then
            local name = o:getName()
            if name == Fortify.PALISADE_NAME then return "palisade", 1, o end
            local steps = name ~= nil and Fortify.WALL_NAMES[name] or nil
            if steps ~= nil then return "wall", steps, o end
        end
    end
    return nil
end

-- Case où un segment peut se poser : chargée, hors bâtiment, ni eau, ni escalier, praticable.
local function groundOk(sq)
    if sq == nil or sq:getBuildingDef() ~= nil then return false end
    if sq:isWaterSquare() or sq:HasStairs() then return false end
    return sq:isFree(false)
end

-- Segments du pourtour du rectangle intérieur r = { x1, y1, x2, y2 } au niveau z (côté, position, case porteuse,
-- face). Côtés dans l'ordre N, E, S, W ; position croissante.
function Fortify.ringSegments(r, z)
    local out = {}
    for x = r.x1, r.x2 do out[#out + 1] = { side = "N", pos = x, x = x, y = r.y1, north = true, ox = x, oy = r.y1 - 1 } end
    for y = r.y1, r.y2 do
        out[#out + 1] = { side = "E", pos = y, x = r.x2 + 1, y = y, north = false, ox = r.x2, oy = y }
    end
    for x = r.x1, r.x2 do
        out[#out + 1] = { side = "S", pos = x, x = x, y = r.y2 + 1, north = true, ox = x, oy = r.y2 }
    end
    for y = r.y1, r.y2 do out[#out + 1] = { side = "W", pos = y, x = r.x1, y = y, north = false, ox = r.x1 - 1, oy = y } end
    for _, s in ipairs(out) do s.z = z end
    return out
end

-- Relevé du foyer d'un groupe : { gid, style, bid, home, levels, openings, ring, ringKind, bounds, outerSkipped },
-- ou nil et la raison (zone non chargée...). Lecture seule.
function Fortify.survey(gid)
    local G = Groups()
    if G == nil or not G.isReady() then return nil, "registry not ready" end
    local g = G.get(gid)
    if g == nil then return nil, "unknown group" end
    local home = g.home
    if type(home) ~= "table" then return nil, "no home" end
    local style, def = Homes().ready(home)
    if style == nil then return nil, def end
    local cell = getCell()
    local c = cfg()
    local s = { gid = gid, style = style, home = { x = home.x, y = home.y, z = home.z }, openings = {} }
    local rect
    if style == "building" then
        s.bid = def:getIDString()
        local M = c.OUTER_MARGIN
        rect = { x1 = def:getX() - M, y1 = def:getY() - M, x2 = def:getX2() - 1 + M, y2 = def:getY2() - 1 + M }
        s.ringKind, s.ringZ = "wall", 0
        s.levels = math.max(0, def:getMaxLevel())
    else
        local R = c.CAMP_RING
        rect = { x1 = home.x - R, y1 = home.y - R, x2 = home.x + R, y2 = home.y + R }
        s.ringKind, s.ringZ = "palisade", home.z
        s.levels = 0
    end
    s.rect = rect
    s.bounds = { x1 = rect.x1 - 1, y1 = rect.y1 - 1, x2 = rect.x2 + 1, y2 = rect.y2 + 1 }
    for _, p in ipairs({ { s.bounds.x1, s.bounds.y1 }, { s.bounds.x2, s.bounds.y1 }, { s.bounds.x2, s.bounds.y2 },
        { s.bounds.x1, s.bounds.y2 } }) do
        if cell:getGridSquare(p[1], p[2], s.ringZ) == nil then return nil, "home area not loaded" end
    end
    if style == "building" then
        for z = 0, s.levels do
            for _, e in ipairs(Fortify.openingsAt(cell, def, s.bid, z)) do
                if #s.openings < c.MAX_OPENINGS then s.openings[#s.openings + 1] = e end
            end
        end
    end
    local segs = Fortify.ringSegments(rect, s.ringZ)
    s.ring = {}
    if #segs > c.MAX_OUTER then
        s.outerSkipped = "ring of " .. #segs .. " segment(s) over " .. c.MAX_OUTER
    else
        for _, seg in ipairs(segs) do
            local sq = cell:getGridSquare(seg.x, seg.y, seg.z)
            local other = cell:getGridSquare(seg.ox, seg.oy, seg.z)
            local e = { side = seg.side, pos = seg.pos, x = seg.x, y = seg.y, z = seg.z, north = seg.north,
                ox = seg.ox, oy = seg.oy }
            if sq == nil or other == nil then
                e.blocked = "not loaded"
            else
                local kind, steps, obj = builtOn(sq, seg.north)
                if kind ~= nil then
                    e.built, e.steps = kind, steps
                    -- LK14-T06 : santé d'un ouvrage achevé (mur sur son cadre, palissade) ; un cadre seul n'est pas
                    -- réparé (l'étape du mur le remplace).
                    if kind == "palisade" or steps >= 2 then e.health = Fortify.healthRatio(obj) end
                elseif not groundOk(sq) or other:getBuildingDef() ~= nil or other:isWaterSquare() then
                    e.blocked = "ground"
                elseif sq:isBlockedTo(other) then
                    e.blocked = "edge closed"
                end
            end
            s.ring[#s.ring + 1] = e
        end
    end
    Fortify.stats.surveys = Fortify.stats.surveys + 1
    return s
end

-- ================================================================ plan (pur)

local function req(types, n) return { types = types, n = n } end

local function siteId(kind, x, y, z, north) return kind .. ":" .. x .. "," .. y .. "," .. z .. (north and "N" or "W") end

-- Chantier de barricade d'une ouverture e jusqu'à target planches.
local function barricadeSite(e, tier, target)
    local have = e.metal and target or math.min(e.planks, target)
    local need = target - have
    local site = { id = siteId("barricade", e.x, e.y, e.z, e.north), kind = "barricade", tier = tier,
        opening = e.kind, x = e.x, y = e.y, z = e.z, north = e.north, opp = e.opp,
        inside = { x = e.inX, y = e.inY }, outside = { x = e.outX, y = e.outY },
        have = have, steps = target, done = need <= 0, entity = "BarricadePlanks",
        tools = {}, materials = {}, time = 0 }
    if need > 0 then
        site.materials = { req({ Fortify.PLANK }, need), req({ Fortify.NAILS }, need) }
        site.tools = { "HAMMER" }
        site.time = need * cfg().TIME.plank
    end
    return site
end

-- Chantier d'un segment de pourtour (kind "wall" ou "palisade").
local function ringSite(e, kind)
    if e.built == "wall" then kind = "wall" elseif e.built == "palisade" then kind = "palisade" end
    -- LK14-T04 : case intérieure (dans le pourtour) et extérieure du bord. Côtés N et W : le bord est porté par la
    -- case intérieure (x, y) ; côtés E et S : par la case extérieure.
    local inside, outside = { x = e.x, y = e.y }, { x = e.ox, y = e.oy }
    if e.side == "E" or e.side == "S" then inside, outside = outside, inside end
    local site = { id = siteId(kind, e.x, e.y, e.z, e.north), kind = kind, tier = "outer", x = e.x, y = e.y, z = e.z,
        north = e.north, side = e.side, pos = e.pos, inside = inside, outside = outside, tools = {}, materials = {},
        time = 0 }
    local T = cfg().TIME
    if kind == "wall" then
        site.steps, site.have = 2, e.steps or 0
        site.entity = { "WoodenWallFrame", "WoodenWallLvl1" }
        if site.have == 0 then
            site.materials = { req({ Fortify.PLANK }, 4), req({ Fortify.NAILS }, 6) }
            site.time = T.frame + T.wall
        elseif site.have == 1 then
            site.materials = { req({ Fortify.PLANK }, 2), req({ Fortify.NAILS }, 4) }
            site.time = T.wall
        end
        if site.have < 2 then site.tools = { "HAMMER" } end
    else
        site.steps, site.have = 1, e.steps or 0
        site.entity = "LogWall"
        if site.have == 0 then
            site.materials = { req({ Fortify.LOG }, 4), req(Fortify.TIES, 4) }
            site.time = T.palisade
        end
    end
    site.done = site.have >= site.steps
    return site
end

-- LK14-T06 : recettes de réparation vanilla des ouvrages du pourtour (M/lua/shared/Moveables/ISMoveableDefinitions.lua
-- :656-668 : définition « Wood » des murs en bois, Material = Wood ; « Log » de la palissade, Material = Log) : outils
-- (marteau et scie), pièce requise, pièces facultatives (une seule sorte utilisée : la première présente en quantité,
-- ISMoveableSpriteProps:repairObjectInternal, M/lua/shared/Moveables/ISMoveableSpriteProps.lua:3574-3599). « Tag.Rope »
-- réduit ici à Base.Rope.
Fortify.REPAIRS = {
    wall = { tools = { "HAMMER", "SAW" }, part = { Fortify.PLANK, 2 },
        options = { { Fortify.NAILS, 4 }, { "Base.Screws", 4 } } },
    palisade = { tools = { "HAMMER", "SAW" }, part = { Fortify.LOG, 2 },
        options = { { Fortify.NAILS, 4 }, { "Base.Screws", 2 }, { "Base.RippedSheets", 4 }, { "Base.Sheet", 2 },
            { "Base.Rope", 2 } } },
}

-- Quantité d'une pièce de réparation selon les dégâts (0..1) : floor(max(n x dégâts, 1)), comme
-- ISMoveableSpriteProps:getRepairPartsForMaterial (ISMoveableSpriteProps.lua:840-869).
function Fortify.repairAmount(n, damage)
    return math.floor(math.max(n * damage, 1))
end

-- Pièces de la réparation d'un ouvrage target ("wall", "palisade") à l'état health (0..1) : requises, facultatives.
function Fortify.repairParts(target, health)
    local r = Fortify.REPAIRS[target]
    local damage = math.max(0, math.min(1, 1 - (health or 1)))
    local options = {}
    for _, o in ipairs(r.options) do options[#options + 1] = req({ o[1] }, Fortify.repairAmount(o[2], damage)) end
    return { req({ r.part[1] }, Fortify.repairAmount(r.part[2], damage)) }, options
end

-- Chantier de réparation de la barricade complète d'une ouverture e (planche extérieure abîmée) : une planche saine
-- et un clou, marteau ; retrait puis pose d'une planche.
local function barricadeRepairSite(e, tier)
    local T = cfg().TIME
    return { id = siteId("repair", e.x, e.y, e.z, e.north), kind = "repair", target = "barricade", tier = tier,
        opening = e.kind, x = e.x, y = e.y, z = e.z, north = e.north, opp = e.opp,
        inside = { x = e.inX, y = e.inY }, outside = { x = e.outX, y = e.outY }, cond = e.cond,
        have = 0, steps = 1, done = false, tools = { "HAMMER" },
        materials = { req({ Fortify.PLANK }, 1), req({ Fortify.NAILS }, 1) }, time = 2 * T.plank }
end

-- Chantier de réparation d'un ouvrage achevé du pourtour (mur, palissade) sous REPAIR_BELOW.
local function ringRepairSite(e)
    local base = ringSite(e, e.built)
    local materials, options = Fortify.repairParts(e.built, e.health)
    return { id = siteId("repair", e.x, e.y, e.z, e.north), kind = "repair", target = e.built, tier = "outer",
        x = e.x, y = e.y, z = e.z, north = e.north, side = e.side, pos = e.pos, inside = base.inside,
        outside = base.outside, cond = e.health, have = 0, steps = 1, done = false,
        tools = Fortify.REPAIRS[e.built].tools, materials = materials, options = options,
        time = cfg().TIME.repair or 1000 }
end

local function needsRepair(v)
    return v ~= nil and v < cfg().REPAIR_BELOW
end

local function openingOrder(a, b)
    local ra, rb = Fortify.OPENING_RANK[a.opening], Fortify.OPENING_RANK[b.opening]
    if ra ~= rb then return ra < rb end
    if a.d ~= b.d then return a.d > b.d end
    if a.z ~= b.z then return a.z < b.z end
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return (a.north and 1 or 0) < (b.north and 1 or 0)
end

local SIDE_RANK = { N = 1, E = 2, S = 3, W = 4 }
local GAP_SIDE_RANK = { S = 1, E = 2, N = 3, W = 4 }   -- départage de la brèche (camp : sud d'abord)

-- Entrée du foyer : porte extérieure barricadable du rez-de-chaussée la plus proche de la case du foyer, ou nil.
function Fortify.entryOf(survey)
    local best
    local h = survey.home
    for _, e in ipairs(survey.openings or {}) do
        if e.kind == "door" and e.z == 0 and e.allowed then
            local d = cheb(e.inX, e.inY, h.x, h.y)
            local better = best == nil or d < best.d
                or (d == best.d and (e.y < best.e.y or (e.y == best.e.y and (e.x < best.e.x
                or (e.x == best.e.x and e.north and not best.e.north)))))
            if better then best = { e = e, d = d } end
        end
    end
    return best and best.e or nil
end

-- Avancement pondéré (0..100) de chantiers : étapes faites / étapes visées par tier, pondérées par WEIGHTS ; aucun
-- chantier : 100.
function Fortify.levelOfSites(sites)
    local per = {}
    for _, t in ipairs(Fortify.TIERS) do per[t] = { have = 0, steps = 0 } end
    for _, s in ipairs(sites) do
        local p = per[s.tier]
        p.have, p.steps = p.have + math.min(s.have, s.steps), p.steps + s.steps
    end
    local num, den = 0, 0
    for _, t in ipairs(Fortify.TIERS) do
        local p, w = per[t], cfg().WEIGHTS[t] or 0
        if p.steps > 0 and w > 0 then
            num, den = num + w * p.have / p.steps, den + w
        end
    end
    if den == 0 then return 100 end
    return math.floor(100 * num / den + 0.5)
end

-- Plan d'un relevé (pur) : { gid, style, home, entry, sites (ordre de priorité, rank 1..n), gaps, skipped, bounds,
-- level, todo (chantiers restants), key (texte stable du plan), urgent, repairs (LK14-T06) }. opts.urgent (après
-- une attaque) : réparations puis barricades entamées en tête ; sinon réparations en dernier.
function Fortify.build(survey, opts)
    local c = cfg()
    local h = survey.home
    local urgent = opts ~= nil and opts.urgent == true
    local plan = { gid = survey.gid, style = survey.style, home = h, bounds = survey.bounds, sites = {}, gaps = {},
        skipped = {}, outerSkipped = survey.outerSkipped, urgent = urgent }
    local repGround, repUpper, repOuter = {}, {}, {}
    local entry = Fortify.entryOf(survey)
    if entry ~= nil then
        plan.entry = { x = entry.x, y = entry.y, z = entry.z, north = entry.north,
            outside = { x = entry.outX, y = entry.outY } }
    end
    local ground, upper = {}, {}
    for _, e in ipairs(survey.openings or {}) do
        if e ~= entry and not e.allowed then   -- l'entrée reste libre
            plan.skipped[#plan.skipped + 1] = { x = e.x, y = e.y, z = e.z, north = e.north, why = "not barricadable" }
        elseif e ~= entry then
            local tier = e.z == 0 and "ground" or "upper"
            local site = barricadeSite(e, tier, c.PLANKS[tier])
            site.d = cheb(e.inX, e.inY, h.x, h.y)
            if tier == "ground" then ground[#ground + 1] = site else upper[#upper + 1] = site end
            -- LK14-T06 : barricade complète dont la planche extérieure est abîmée (une barricade incomplète reçoit
            -- d'abord ses planches : la nouvelle devient la planche extérieure).
            if site.done and not e.metal and needsRepair(e.cond) then
                local rep = barricadeRepairSite(e, tier)
                rep.d = site.d
                if tier == "ground" then repGround[#repGround + 1] = rep else repUpper[#repUpper + 1] = rep end
            end
        end
    end
    table.sort(ground, openingOrder)
    table.sort(upper, openingOrder)
    table.sort(repGround, openingOrder)
    table.sort(repUpper, openingOrder)
    -- Pourtour : brèche en face de l'entrée (camp ou bâtiment sans porte : en face du foyer, sud d'abord).
    local ring = survey.ring or {}
    local tx, ty = h.x, h.y
    if plan.entry ~= nil then tx, ty = plan.entry.outside.x, plan.entry.outside.y end
    local gap0
    for _, e in ipairs(ring) do
        -- Distance du milieu du bord (face nord : (x + 1/2, y) ; ouest : (x, y + 1/2)) au centre de la case visée.
        local mx, my = e.x + 0.5, e.y
        if not e.north then mx, my = e.x, e.y + 0.5 end
        local d = (mx - tx - 0.5) * (mx - tx - 0.5) + (my - ty - 0.5) * (my - ty - 0.5)
        local better = gap0 == nil or d < gap0.d or (d == gap0.d and GAP_SIDE_RANK[e.side] < GAP_SIDE_RANK[gap0.e.side])
            or (d == gap0.d and e.side == gap0.e.side and e.pos < gap0.e.pos)
        if better then gap0 = { e = e, d = d } end
    end
    local outer = {}
    for _, e in ipairs(ring) do
        if gap0 ~= nil and e.side == gap0.e.side and math.abs(e.pos - gap0.e.pos) <= c.GAP and e.built == nil then
            plan.gaps[#plan.gaps + 1] = { x = e.x, y = e.y, z = e.z, north = e.north }
        elseif e.blocked ~= nil then
            plan.skipped[#plan.skipped + 1] = { x = e.x, y = e.y, z = e.z, north = e.north, why = e.blocked }
        else
            outer[#outer + 1] = ringSite(e, survey.ringKind)
            if e.built ~= nil and e.health ~= nil and needsRepair(e.health) then   -- LK14-T06
                repOuter[#repOuter + 1] = ringRepairSite(e)
            end
        end
    end
    local function ringOrder(a, b)
        if SIDE_RANK[a.side] ~= SIDE_RANK[b.side] then return SIDE_RANK[a.side] < SIDE_RANK[b.side] end
        return a.pos < b.pos
    end
    table.sort(outer, ringOrder)
    table.sort(repOuter, ringOrder)
    -- LK14-T06 : ordre des listes. Après une attaque : réparations (rez-de-chaussée, étages, pourtour), puis barricades
    -- entamées (planche retirée ou chantier en cours), puis le reste ; sinon le plan de LK14-T02, réparations en dernier.
    local lists
    local repairs = {}
    for _, list in ipairs({ repGround, repUpper, repOuter }) do
        for _, s in ipairs(list) do repairs[#repairs + 1] = s end
    end
    if urgent then
        local started, rest = {}, {}
        for _, list in ipairs({ ground, upper }) do
            for _, s in ipairs(list) do
                if not s.done and s.have > 0 then started[#started + 1] = s else rest[#rest + 1] = s end
            end
        end
        lists = { repairs, started, rest, outer }
    else
        lists = { ground, upper, outer, repairs }
    end
    for _, list in ipairs(lists) do
        for _, s in ipairs(list) do
            s.d = nil
            plan.sites[#plan.sites + 1] = s
            s.rank = #plan.sites
        end
    end
    plan.repairs = #repairs
    plan.level = Fortify.levelOfSites(plan.sites)
    local todo, ids = 0, {}
    for _, s in ipairs(plan.sites) do
        if not s.done then todo = todo + 1 end
        ids[#ids + 1] = s.id .. "=" .. s.have
    end
    plan.todo = todo
    plan.key = (urgent and "urgent;" or "") .. table.concat(ids, ";")
    return plan
end

-- ================================================================ stock et faisabilité

-- Matériaux disponibles d'après l'inventaire de référence du stock : { [type complet] = nombre } (boîte de clous =
-- BOX_NAILS clous), ou nil et une raison.
function Fortify.available(gid)
    local St = LivingKnox.Stock
    if St == nil or St.reference == nil then return nil, "no stock module" end
    local ref, why = St.reference(gid)
    if ref == nil then return nil, why end
    local out = {}
    for _, e in ipairs(ref.items or {}) do
        local t = e.t
        if t == Fortify.NAILS_BOX then
            out[Fortify.NAILS] = (out[Fortify.NAILS] or 0) + cfg().BOX_NAILS
        elseif type(t) == "string" then
            out[t] = (out[t] or 0) + 1
        end
    end
    return out
end

-- Vrai si un objet du tag ItemTag[name] est dans les conteneurs du foyer (outil gardé, non consommé).
function Fortify.hasTool(gid, name)
    local St = LivingKnox.Stock
    if St == nil or St.findItem == nil or ItemTag == nil or ItemTag[name] == nil then return false end
    local tag = ItemTag[name]
    local found = St.findItem(gid, function(it) return it:hasTag(tag) end)
    return found ~= nil
end

-- Prend le besoin r ({ types, n }) dans avail en plus de taken ; rend vrai (taken complété) ou faux (taken inchangé).
local function reserveReq(r, avail, taken)
    local left, add = r.n, {}
    for _, t in ipairs(r.types) do
        local have = (avail[t] or 0) - (taken[t] or 0)
        if have > 0 and left > 0 then
            local q = math.min(have, left)
            add[t] = q
            left = left - q
        end
    end
    if left > 0 then return false end
    for t, q in pairs(add) do taken[t] = (taken[t] or 0) + q end
    return true
end

-- Réserve les matériaux de site dans avail (modifié) ; rend vrai si tout y est, sinon avail est inchangé. LK14-T06 :
-- site.options (pièces facultatives d'une réparation) : une seule, la première qui tient, est exigée.
function Fortify.reserve(site, avail)
    local taken = {}
    for _, r in ipairs(site.materials) do
        if not reserveReq(r, avail, taken) then return false end
    end
    if site.options ~= nil and #site.options > 0 then
        local ok = false
        for _, r in ipairs(site.options) do
            if not ok and reserveReq(r, avail, taken) then ok = true end
        end
        if not ok then return false end
    end
    for t, q in pairs(taken) do avail[t] = avail[t] - q end
    return true
end

-- Chantiers faisables d'un plan (pur) : restants, dans l'ordre du plan, dont les outils sont présents (tools[nom]
-- vrai) et dont les matériaux tiennent dans avail après ceux des précédents. Rend la liste (copies des chantiers).
function Fortify.feasibleSites(plan, avail, tools)
    local left = {}
    for t, n in pairs(avail or {}) do left[t] = n end
    local out = {}
    for _, s in ipairs(plan.sites) do
        if not s.done then
            local ok = true
            for _, name in ipairs(s.tools) do
                if not tools[name] then ok = false end
            end
            if ok and Fortify.reserve(s, left) then out[#out + 1] = s end
        end
    end
    return out
end

-- ================================================================ autorité : plan, niveau, ouvriers

-- Plan du foyer du groupe gid, relevé de nouveau au plus toutes les PLAN_MS (opts.force : maintenant). Zone non
-- chargée : dernier plan connu (champ stale vrai), sinon nil et la raison.
-- LK13-T11 (suite) : trois étapes, enchaînées ici, séparables par la file de la minute (une étape par image) :
-- planNeed (plan gardé, ou contexte d'un nouveau relevé), planSurvey (relevé du monde), planFinish (plan pur, journal,
-- plan gardé). Le contexte porte l'heure (now) et l'urgence de la première étape.
local function planNeed(gid, opts)
    local st = Fortify.state.plans[gid]
    local t = now()
    local urgent = Fortify.urgent(gid)
    if st ~= nil and not (opts and opts.force) and t - st.ms < cfg().PLAN_MS and st.plan.urgent == urgent then
        return true, st.plan
    end
    return false, { gid = gid, t = t, urgent = urgent }
end

local function planSurvey(ctx)
    ctx.survey, ctx.why = Fortify.survey(ctx.gid)
    ctx.surveyed = true
end

local function planFinish(ctx)
    local gid, survey = ctx.gid, ctx.survey
    local st = Fortify.state.plans[gid]
    if survey == nil then
        Fortify.stats.notReady = Fortify.stats.notReady + 1
        if st ~= nil then
            st.plan.stale = true
            return st.plan
        end
        return nil, ctx.why
    end
    local plan = Fortify.build(survey, { urgent = ctx.urgent })
    if st == nil or st.plan.key ~= plan.key then
        Fortify.stats.changed = Fortify.stats.changed + 1
        local counts = { ground = 0, upper = 0, outer = 0 }
        for _, s in ipairs(plan.sites) do
            if not s.done then counts[s.tier] = counts[s.tier] + 1 end
        end
        log().info("fortify: group %s plan (%s): %d site(s), %d to do (ground %d, upper %d, outer %d), %d gap(s), "
            .. "%d skipped, level %d, %d repair(s)%s", gid, plan.style, #plan.sites, plan.todo, counts.ground,
            counts.upper, counts.outer, #plan.gaps, #plan.skipped, plan.level, plan.repairs,
            plan.urgent and " first (after an attack)" or "")
        if plan.outerSkipped then log().info("fortify: group %s: no outer defence (%s)", gid, plan.outerSkipped) end
    end
    Fortify.state.plans[gid] = { plan = plan, ms = ctx.t }
    return plan
end

function Fortify.plan(gid, opts)
    settle(gid)   -- LK13-T11 : relevé de la minute encore en file fait d'abord (même résultat qu'avant la file)
    local given = Fortify.givenPlan   -- dernière étape d'un relevé en file : plan de ses deux premières étapes
    if given ~= nil and given.gid == gid and not (opts and opts.force) then
        Fortify.givenPlan = nil
        if given.plan ~= nil then return given.plan end
        return nil, given.why
    end
    local done, plan = planNeed(gid, opts)
    if done then return plan end
    planSurvey(plan)
    return planFinish(plan)
end

-- Niveau de fortification du foyer (0..100), ou nil si aucun plan n'est connu. LK14-T05 : foyer hors de la zone
-- chargée (plan absent ou ancien) : niveau du relevé gardé au registre, avancé par la simulation hors écran.
function Fortify.levelOf(gid)
    local plan = Fortify.plan(gid)
    if plan == nil or plan.stale then
        local level = Fortify.offscreenLevel(gid)
        if level ~= nil then return level end
    end
    if plan == nil then return nil end
    return plan.level
end

-- LK14-T06 : vrai si une attaque contre le foyer a été repoussée il y a moins de REPAIR_URGENT_MINUTES minutes de jeu
-- (marque LivingKnox.Defense.after, LK05-T09) : les réparations passent alors en tête du plan.
function Fortify.urgent(gid)
    local D = LivingKnox.Defense
    local mark = D ~= nil and D.after ~= nil and D.after(gid) or nil
    if mark == nil or type(mark.minute) ~= "number" then return false end
    local Dc = LivingKnox.Decisions
    local minute = Dc ~= nil and Dc.currentMinute ~= nil and Dc.currentMinute() or nil
    if minute == nil then return false end
    return minute - mark.minute <= cfg().REPAIR_URGENT_MINUTES
end

-- LK14-T06 : besoin de réparation (pur) : réparations du plan non faisables avec avail (après les chantiers faisables
-- qui les précèdent) et outils absents. Rend { materials = { [type] = manquant }, tools = { nom... }, sites = n } ou nil.
function Fortify.repairShortage(plan, avail, tools, feasible)
    local ok = {}
    local left = {}
    for t, n in pairs(avail or {}) do left[t] = n end
    for _, s in ipairs(feasible) do
        ok[s.id] = true
        Fortify.reserve(s, left)   -- matériaux des chantiers faisables : déjà promis
    end
    local need, missingTools, toolSeen, blocked = {}, {}, {}, 0
    for _, s in ipairs(plan.sites) do
        if s.kind == "repair" and not s.done and not ok[s.id] then
            blocked = blocked + 1
            for _, name in ipairs(s.tools) do
                if not tools[name] and not toolSeen[name] then
                    toolSeen[name] = true
                    missingTools[#missingTools + 1] = name
                end
            end
            local reqs = {}
            for _, r in ipairs(s.materials) do reqs[#reqs + 1] = r end
            if s.options ~= nil and #s.options > 0 then
                local opt = s.options[1]   -- aucune pièce facultative en quantité : la première est demandée
                for i = #s.options, 1, -1 do
                    if reserveReq(s.options[i], left, {}) then opt = s.options[i] end
                end
                reqs[#reqs + 1] = opt
            end
            for _, r in ipairs(reqs) do
                -- ce qui existe est compté pour cette réparation (la suivante ne le reprend pas), le reste manque
                local rest = r.n
                for _, t in ipairs(r.types) do
                    local q = math.min(rest, left[t] or 0)
                    if q > 0 then
                        left[t] = left[t] - q
                        rest = rest - q
                    end
                end
                if rest > 0 then need[r.types[1]] = (need[r.types[1]] or 0) + rest end
            end
        end
    end
    if blocked == 0 then return nil end
    table.sort(missingTools)
    return { materials = need, tools = missingTools, sites = blocked }
end

-- Texte stable d'un besoin : "2 Base.Plank, 4 Base.Nails; tools: SAW".
local function needText(n)
    local types = {}
    for t in pairs(n.materials) do types[#types + 1] = t end
    table.sort(types)
    local parts = {}
    for _, t in ipairs(types) do parts[#parts + 1] = n.materials[t] .. " " .. t end
    local text = #parts > 0 and table.concat(parts, ", ") or "no material"
    if #n.tools > 0 then text = text .. "; tools: " .. table.concat(n.tools, ", ") end
    return text
end

-- LK14-T06 : note le besoin de réparation du groupe (Fortify.needOf) et l'écrit au journal du groupe (kind
-- « shortage ») : une fois par attaque repoussée (marque Defense.after) et au plus toutes les NEED_HOURS pour un même
-- besoin. Aucun besoin : la note est effacée.
local function noteNeed(gid, plan, shortage)
    local needs = Fortify.state.needs
    if shortage == nil then
        needs[gid] = nil
        return
    end
    local D = LivingKnox.Defense
    local mark = D ~= nil and D.after ~= nil and D.after(gid) or nil
    local Dc = LivingKnox.Decisions
    local minute = Dc ~= nil and Dc.currentMinute ~= nil and Dc.currentMinute() or 0
    local text = needText(shortage)
    local attack = plan.urgent and mark ~= nil and mark.id or nil
    local prev = needs[gid]
    shortage.text, shortage.attack, shortage.minute = text, attack, minute
    local fresh = prev == nil or prev.text ~= text or prev.attack ~= attack
        or minute - (prev.logged or -1e18) >= cfg().NEED_HOURS * 60
    shortage.logged = prev ~= nil and prev.logged or nil
    needs[gid] = shortage
    if not fresh then return end
    shortage.logged = minute
    Fortify.stats.needs = Fortify.stats.needs + 1
    local line = string.format("materials to repair %d defence(s): %s%s", shortage.sites, text,
        attack ~= nil and (" (after " .. attack .. ")") or "")
    log().info("fortify: group %s %s", gid, line)
    local G = Groups()
    if G ~= nil and G.addLog ~= nil then G.addLog(gid, "shortage", line) end
end

-- LK14-T06 : besoin de réparation en cours du groupe gid (copie), ou nil : { materials = { [type] = n }, tools,
-- sites, text, attack, minute }. Point d'appel des consommateurs (expéditions, missions) : matériaux à rapporter.
function Fortify.needOf(gid)
    local n = Fortify.state.needs[gid]
    if n == nil then return nil end
    local materials, tools = {}, {}
    for t, q in pairs(n.materials) do materials[t] = q end
    for i, name in ipairs(n.tools) do tools[i] = name end
    return { materials = materials, tools = tools, sites = n.sites, text = n.text, attack = n.attack,
        minute = n.minute }
end

-- Chantiers faisables du foyer maintenant (stock et outils du foyer), ou nil et une raison. LK14-T06 : réparations non
-- faisables notées comme besoin du groupe (noteNeed).
function Fortify.feasible(gid)
    local plan, why = Fortify.plan(gid)
    -- LK14-T05 : travail fait hors écran posé d'abord (zone du foyer chargée), puis plan relevé de nouveau.
    if plan ~= nil and not plan.stale and Fortify.hasPending(gid) then
        Fortify.applyPending(gid)
        plan, why = Fortify.plan(gid, { force = true })
    end
    if plan == nil or plan.stale then
        -- LK14-T05 : foyer hors de la zone chargée : chantiers faisables d'après le relevé gardé au registre.
        local off = Fortify.offscreenFeasible(gid)
        if off ~= nil then return off end
    end
    if plan == nil then return nil, why end
    local avail, w2 = Fortify.available(gid)
    if avail == nil then return nil, w2 end
    local tools = {}
    for _, s in ipairs(plan.sites) do
        if not s.done then
            for _, name in ipairs(s.tools) do
                if tools[name] == nil then tools[name] = Fortify.hasTool(gid, name) end
            end
        end
    end
    local list = Fortify.feasibleSites(plan, avail, tools)
    if (plan.repairs or 0) > 0 or Fortify.state.needs[gid] ~= nil then
        noteNeed(gid, plan, (plan.repairs or 0) > 0 and Fortify.repairShortage(plan, avail, tools, list) or nil)
    end
    if not plan.stale then Fortify.snapshot(gid, plan, tools) end   -- LK14-T05 : relevé gardé pour le hors écran
    return list
end

-- Vrai si au moins un chantier est faisable, faux sinon, nil si on ne sait pas (plan ou stock inconnu).
function Fortify.hasWork(gid)
    local list = Fortify.feasible(gid)
    if list == nil then return nil end
    return #list > 0
end

-- Chantier proposé au membre mid de poste « builder » (point d'appel de LK14-T03) : le k-ième faisable pour le
-- k-ième ouvrier vivant (numéro de membre croissant). Rend le chantier, ou nil et la raison.
function Fortify.siteFor(gid, mid)
    local G = Groups()
    local g = G ~= nil and G.isReady() and G.get(gid) or nil
    if g == nil then return nil, "unknown group" end
    local m = g.members and g.members[mid]
    if m == nil or not m.alive then return nil, "not a living member" end
    if m.duty ~= "builder" then return nil, "not a builder" end
    local builders = {}
    for id, b in pairs(g.members) do
        if b.alive and b.duty == "builder" then builders[#builders + 1] = { id = id, n = G.memberNumber(id) or 0 } end
    end
    table.sort(builders, function(a, b)
        if a.n ~= b.n then return a.n < b.n end
        return a.id < b.id
    end)
    local k = 0
    for i, b in ipairs(builders) do
        if b.id == mid then k = i end
    end
    local list, why = Fortify.feasible(gid)
    if list == nil then return nil, why end
    local site = list[k]
    if site == nil then return nil, "nothing feasible" end
    return site
end

-- Plan du groupe à relever de nouveau au prochain appel (le dernier reste connu si la zone se décharge).
function Fortify.invalidate(gid)
    settle(gid)   -- LK13-T11 : relevé de la minute encore en file fait avant d'oublier le plan
    local st = Fortify.state.plans[gid]
    if st ~= nil then st.ms = -1e18 end
end

-- ================================================================ pose des barricades (LK14-T03)
-- Fiche docs/annexes/conception/fortification.md §7. Autorité seulement (module absent d'un client MP).

local function R() return LivingKnox.Routines end
local function Stock() return LivingKnox.Stock end

local function ofType(t)
    return function(it) return it:getFullType() == t end
end

-- Ouverture barricadable du chantier site (même case, même face), et sa case ; nil si elle n'y est plus.
function Fortify.openingOf(site)
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(site.x, site.y, site.z) or nil
    if sq == nil then return nil, nil end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o ~= nil and Fortify.openingKind(o) ~= nil and (o:getNorth() == true) == (site.north == true)
            and o:isBarricadeAllowed() then
            return o, sq
        end
    end
    return nil, sq
end

-- Côté où clouer la planche : celui de la barricade déjà commencée (la plus garnie), sinon le côté visé par le plan
-- (site.opp : dehors, comme IsoWindow.addRandomBarricades, fortification.md §5.3) s'il a une case, sinon l'autre.
-- Rend addOpposite et les planches déjà posées, ou nil et une raison.
local function sideFor(o, site)
    local ps, ms = planksOf(o:getBarricadeOnSameSquare())
    local po, mo = planksOf(o:getBarricadeOnOppositeSquare())
    if ms or mo then return nil, "metal barricade" end
    local have = math.max(ps, po)
    if ps > 0 and ps >= po then return false, have end
    if po > 0 then return true, have end
    local opp = site.opp == true
    local target = opp and o:getOppositeSquare() or o:getSquare()
    if target == nil then opp = not opp end
    return opp, have
end

-- Ouvre une boîte de clous du foyer comme la recette vanilla OpenBox100 (M/recipes/recipes_packing.txt:220-241) : la
-- boîte retirée par Stock.takeItem, BOX_NAILS Base.Nails ajoutés au même conteneur (envoyés aux clients proches sur un
-- serveur), puis relecture du stock (objets ajoutés acceptés : référence à jour). Rend vrai, ou faux et une raison.
local function openBox(gid, box, ctr, who, use)
    local id = box:getID()
    local got, why = Stock().takeItem(gid, function(it) return it:getID() == id end, who, use)
    if got == nil then return false, why end
    local list = ctr:AddItems(Fortify.NAILS, cfg().BOX_NAILS)
    if isServer() and list ~= nil then sendAddItemsToContainer(ctr, list) end
    Fortify.stats.boxes = Fortify.stats.boxes + 1
    log().info("fortify: group %s: %s opened a box of nails (%d nail(s))", gid, tostring(who or "member"),
        list ~= nil and list:size() or 0)
    Stock().check(gid, { force = true })
    return true
end

-- Pose des planches sur l'ouverture o, côté addOpp, comme BuildRecipeCode.barricade.OnCreate (M/lua/server/
-- BuildRecipeCode/buildRecipeCode.lua:91-161) : barricade ajoutée ou reprise (IsoBarricade.AddBarricadeToObject,
-- J/iso/objects/IsoBarricade.java:739-764), planches ajoutées (addPlank, :90-108 ; planks = liste d'objets Base.Plank
-- réels, état repris, ou nombre de planches neuves), UNE transmission sur un serveur (barricade neuve :
-- transmitCompleteItemToClients ; planches ajoutées : sendObjectChange(STATE), J/iso/IsoObject.java:4265-4272,
-- 4314-4322), drapeau de construction de la case. Matériaux déjà retirés par l'appelant. Rend la barricade, ou nil.
function Fortify.addPlanks(o, addOpp, planks)
    local b = IsoBarricade.AddBarricadeToObject(o, addOpp)
    if b == nil then return nil end
    local isNew = b:getNumPlanks() == 0 and not b:isMetal() and not b:isMetalBar()
    if type(planks) == "number" then
        for _ = 1, planks do b:addPlank(nil, nil) end   -- planche neuve (1000 PV)
    else
        for _, plank in ipairs(planks) do b:addPlank(nil, plank) end
    end
    if isServer() then
        if isNew then b:transmitCompleteItemToClients() else b:sendObjectChange(IsoObjectChange.STATE) end
    end
    if type(buildUtil) == "table" and buildUtil.setHaveConstruction ~= nil then
        buildUtil.setHaveConstruction(b:getSquare(), true)   -- drapeau de zone de toutes les constructions vanilla
    end
    return b
end

-- Cloue UNE planche sur l'ouverture du chantier site du groupe gid (who : texte du journal), comme
-- BuildRecipeCode.barricade.OnCreate (M/lua/server/BuildRecipeCode/buildRecipeCode.lua:91-161) sans personnage :
-- tout est relu maintenant (ouverture présente, pas l'entrée du foyer, porte fermée, pas de métal, planches sous la
-- visée, marteau, planche et clou au foyer) AVANT toute prise ; puis une planche et un clou retirés du stock (une
-- seule fois, référence à jour), barricade ajoutée (IsoBarricade.AddBarricadeToObject, J/iso/objects/IsoBarricade.java
-- :739-764), planche réelle passée à addPlank (état repris, :90-108), transmission sur un serveur (barricade neuve :
-- transmitCompleteItemToClients ; planche ajoutée : sendObjectChange(STATE)). Rend un texte et le nombre de planches
-- posées, ou nil et une raison (rien fait).
function Fortify.nailPlank(site, gid, who)
    local St = Stock()
    if St == nil or St.findItem == nil or St.takeItem == nil then return nil, "no stock module" end
    local o, sq = Fortify.openingOf(site)
    if o == nil then return nil, sq == nil and "square not loaded" or "opening gone" end
    local plan = Fortify.plan(gid)
    local e = plan ~= nil and plan.entry or nil
    if e ~= nil and e.x == site.x and e.y == site.y and e.z == site.z and e.north == site.north then
        return nil, "home entry"   -- l'entrée reste praticable (une barricade bloque la porte pour tous)
    end
    if Fortify.openingKind(o) == "door" and o:IsOpen() then return nil, "door open" end
    local addOpp, have = sideFor(o, site)
    if addOpp == nil then return nil, have end
    if have >= site.steps then return nil, "already done" end
    if not Fortify.hasTool(gid, "HAMMER") then return nil, "no hammer" end
    local pf, plank, pctr = St.findItem(gid, ofType(Fortify.PLANK))
    if pf == nil then return nil, "no plank" end
    local boxF, box, bctr
    if St.findItem(gid, ofType(Fortify.NAILS)) == nil then
        boxF, box, bctr = St.findItem(gid, ofType(Fortify.NAILS_BOX))
        if boxF == nil then return nil, "no nails" end
    end
    local use = "barricade " .. site.id
    if boxF ~= nil then
        local ok, why = openBox(gid, box, bctr, who, use)
        if not ok then return nil, "box of nails not opened: " .. tostring(why) end
    end
    local plankId = plank:getID()
    local gotPlank, w1 = St.takeItem(gid, function(it) return it:getID() == plankId end, who, use)
    if gotPlank == nil then return nil, "plank not taken: " .. tostring(w1) end
    local gotNail, w2 = St.takeItem(gid, ofType(Fortify.NAILS), who, use)
    if gotNail == nil then
        pctr:AddItem(plank)   -- planche remise (relue comme ajoutée) : rien n'est perdu
        if isServer() then sendAddItemToContainer(pctr, plank) end
        return nil, "nail not taken: " .. tostring(w2)
    end
    local b = Fortify.addPlanks(o, addOpp, { plank })
    if b == nil then return nil, "barricade not added" end
    Fortify.invalidate(gid)
    Fortify.stats.planks = Fortify.stats.planks + 1
    local n = b:getNumPlanks()
    return string.format("plank %d/%d nailed on %s %s (%s side)", n, site.steps, tostring(site.opening), site.id,
        addOpp and "opposite" or "same"), n
end

-- ================================================================ murs et palissade du pourtour (LK14-T04)
-- Fiche docs/annexes/conception/fortification.md §8. Une étape par appel (cadre, mur sur le cadre, palissade), posée par
-- l'autorité comme ISBuildIsoEntity:setInfo (M/lua/server/BuildingObjects/ISBuildIsoEntity.lua:595-763) sans
-- personnage : IsoThumpable aux drapeaux tirés du sprite, buildUtil.setInfo, santé du script, composants de l'entité,
-- étape précédente retirée (transmitRemoveItemFromSquare), AddSpecialObject, poteau d'angle, setExplored,
-- RecalcAllWithNeighbours, transmitCompleteItemToClients.

-- Sprites vanilla (faces W, N) des ouvrages du pourtour (M/scripts/generated/entities/walls/entity_woodenwallframe.txt,
-- entity_wood_walllvl1.txt, entity_logwall.txt).
Fortify.STRUCTURES = {
    WoodenWallFrame = { W = "carpentry_02_100", N = "carpentry_02_101" },
    WoodenWallLvl1 = { W = "walls_exterior_wooden_01_44", N = "walls_exterior_wooden_01_45" },
    LogWall = { W = "carpentry_02_80", N = "carpentry_02_81" },
}
-- Étapes d'un chantier du pourtour (recettes vanilla) : entité posée, étape remplacée, matériaux, outil gardé.
Fortify.STAGES = {
    wall = {
        { entity = "WoodenWallFrame", materials = { req({ Fortify.PLANK }, 2), req({ Fortify.NAILS }, 2) },
            tool = "HAMMER" },
        { entity = "WoodenWallLvl1", prev = "WoodenWallFrame",
            materials = { req({ Fortify.PLANK }, 2), req({ Fortify.NAILS }, 4) }, tool = "HAMMER" },
    },
    palisade = { { entity = "LogWall", materials = { req({ Fortify.LOG }, 4), req(Fortify.TIES, 4) } } },
}
-- Multiplicateur de la santé bonus selon l'option sandbox ConstructionBonusPoints (ISBuildIsoEntity.lua:655-660).
local BONUS_MULT = { [1] = 0.5, [2] = 0.7, [4] = 1.3, [5] = 1.5 }

-- Fiche de l'entité vanilla posée par le sprite de la face voulue (comme le menu de construction) : info, sprite ;
-- ou nil et une raison. Le nom de l'entité doit être celui attendu (sprite repris par un autre mod : refus).
function Fortify.entityInfo(entity, north)
    local sprites = Fortify.STRUCTURES[entity]
    if sprites == nil then return nil, "unknown structure " .. tostring(entity) end
    local sprite = north and sprites.N or sprites.W
    if SpriteConfigManager == nil then return nil, "no SpriteConfigManager" end
    local info = SpriteConfigManager.getObjectInfoFromSprite(sprite)
    if info == nil or info:getScript() == nil then return nil, "no entity for sprite " .. sprite end
    if info:getName() ~= entity then return nil, "sprite " .. sprite .. " is " .. tostring(info:getName()) end
    return info, sprite
end

-- Santé d'un ouvrage posé sans personnage (ISBuildIsoEntity.lua:637-668) : santé du script + bonus × multiplicateur
-- sandbox + niveau × skillBaseHealth, le niveau étant le plus haut niveau requis par la recette (Menuiserie 2 pour
-- un mur, 0 pour la palissade : les PNJ n'ont pas de compétences ; même plancher que le mode triche vanilla).
function Fortify.healthOf(info)
    local script = info:getScript()
    local level = 0
    local recipe = info:getRecipe() ~= nil and info:getRecipe():getCraftRecipe() or nil
    if recipe ~= nil then
        for i = 0, recipe:getRequiredSkillCount() - 1 do
            local rs = recipe:getRequiredSkill(i)
            if rs ~= nil and rs:getPerk() ~= nil and rs:getLevel() > level then level = rs:getLevel() end
        end
    end
    local bonus = script:getBonusHealth() or 0
    local opt = getSandboxOptions ~= nil and getSandboxOptions():getOptionByName("ConstructionBonusPoints") or nil
    local mult = opt ~= nil and BONUS_MULT[opt:getValue()] or 1
    return math.max(script:getHealth(), 0) + bonus * mult + level * script:getSkillBaseHealth()
end

-- Drapeaux de l'objet tirés des propriétés de son sprite, comme ISBuildIsoEntity:setInfo (:614-631) ; murs, cadres et
-- palissade ne sont ni portes ni fenêtres (canBarricade, isDoor, isDoorFrame faux).
local function propsInfo(t, info)
    local p = t:getProperties()
    local function has(f) return p ~= nil and f ~= nil and p:has(f) end
    local F = IsoFlagType
    local script = info:getScript()
    return {
        canPassThrough = p ~= nil and not (has(F.solid) or has(F.solidtrans) or has(F.doorN) or has(F.doorW)
            or has(F.WallN) or has(F.WallNTrans) or has(F.WallW) or has(F.WallWTrans) or has(F.WallNW)),
        hoppable = has(F.HoppableN) or has(F.HoppableW) or has(F.TallHoppableN) or has(F.TallHoppableW),
        blockAllTheSquare = IsoPropertyType ~= nil and has(IsoPropertyType.BLOCKS_PLACEMENT),
        isFloor = has(F.solidfloor),
        canBarricade = false, thumpDmg = 8, isContainer = false, isDoor = false, isDoorFrame = false, crossSpeed = 1.0,
        name = info:getName(), dismantable = true, canBePlastered = false, modData = {}, isStairs = false,
        isThumpable = script:getIsThumpable() or false, corner = script:getCornerSprite(),
    }
end

-- Ouvrage du pourtour nommé name sur le bord (sq, north), ou nil.
local function structureOn(sq, north, name)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) == north and o:getName() == name then return o end
    end
    return nil
end

-- Poteau d'angle comme buildUtil.checkCorner (M/lua/server/BuildingObjects/ISBuildUtil.lua:57-99) : mur
-- perpendiculaire sur la case diagonale et aucun mur sur la case du coin ; poteau déjà là (étape suivante du même
-- bord) : aucun second poteau (vanilla en ajoute un à chaque étape). Rend vrai si un poteau est posé.
local function cornerPost(sq, north, t, sprite)
    if sprite == nil or type(buildUtil) ~= "table" or buildUtil.addCorner == nil then return false end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local nx, ny, cx, cy = x + 1, y - 1, x + 1, y
    if not north then nx, ny, cx, cy = x - 1, y + 1, x, y + 1 end
    local cell = getCell()
    local sq2 = cell:getGridSquare(nx, ny, z)
    if sq2 == nil then return false end
    local found = false
    local sp = sq2:getSpecialObjects()
    for i = 0, sp:size() - 1 do
        local o = sp:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) ~= north then found = true end
    end
    if not found then return false end
    local csq = cell:getGridSquare(cx, cy, z)
    if csq == nil or csq:getWallFull() then return false end
    local sp2 = csq:getSpecialObjects()
    for i = 0, sp2:size() - 1 do
        local o = sp2:get(i)
        if instanceof(o, "IsoThumpable") and o:isCorner() then return false end
    end
    buildUtil.addCorner(cx, cy, z, t, { corner = sprite })   -- pose, recalcul et envoi aux clients (vanilla)
    Fortify.stats.corners = Fortify.stats.corners + 1
    return true
end

-- Pose l'ouvrage de fiche info (sprite) sur le bord (sq, north) à la place de prev (étape précédente, ou nil), comme
-- ISBuildIsoEntity:setInfo sans personnage. Autorité seulement ; matériaux déjà retirés par l'appelant. Rend l'objet.
function Fortify.placeStructure(sq, north, info, sprite, prev)
    local t = IsoThumpable.new(getCell(), sq, sprite, north, {})   -- table sauvegardée avec l'objet : vide
    local item = propsInfo(t, info)
    buildUtil.setInfo(t, item)
    local health = Fortify.healthOf(info)
    t:setMaxHealth(health)
    t:setHealth(t:getMaxHealth())   -- avant la pose : setHealth enverrait sync() d'un objet posé
    local breakSound = info:getScript():getBreakSound()
    if breakSound ~= nil then t:setBreakSound(breakSound) end
    local entity = info:getScript():getParent()
    if entity ~= nil then GameEntityFactory.CreateIsoObjectEntity(t, entity, true) end
    local index = -1
    if prev ~= nil and prev:getSquare() == sq then index = sq:transmitRemoveItemFromSquare(prev) end
    sq:AddSpecialObject(t, index)
    cornerPost(sq, north, t, item.corner)
    t:setExplored(true)
    sq:RecalcAllWithNeighbours(true)
    if isServer() then t:transmitCompleteItemToClients() end
    if buildUtil.setHaveConstruction ~= nil then buildUtil.setHaveConstruction(sq, true) end
    return t
end

local function typeIn(types)
    return function(it)
        local t = it:getFullType()
        for _, w in ipairs(types) do
            if t == w then return true end
        end
        return false
    end
end

-- Objets du foyer pour les besoins reqs ({ types, n }), sans rien prendre (objets distincts) : liste { it, ctr }, ou
-- nil et le type manquant.
local function gather(gid, reqs, picked)
    local out = {}
    picked = picked or {}
    for _, r in ipairs(reqs) do
        local match = typeIn(r.types)
        for _ = 1, r.n do
            local f, it, ctr = Stock().findItem(gid, function(i) return not picked[i:getID()] and match(i) end)
            if f == nil then return nil, r.types[1] end
            picked[it:getID()] = true
            out[#out + 1] = { it = it, ctr = ctr }
        end
    end
    return out
end

-- Chantier du pourtour du plan courant (même identifiant), ou nil et une raison (brèche, hors du plan).
local function ringSiteNow(gid, site)
    local plan = Fortify.plan(gid)
    if plan == nil then return nil, "no plan" end
    for _, g in ipairs(plan.gaps) do
        if g.x == site.x and g.y == site.y and g.z == site.z and g.north == site.north then return nil, "gap" end
    end
    local b = plan.bounds
    if b == nil or site.x < b.x1 or site.x > b.x2 or site.y < b.y1 or site.y > b.y2 then return nil, "outside the home" end
    for _, s in ipairs(plan.sites) do
        if s.id == site.id then return s end
    end
    return nil, "not in the plan"
end

-- Pose UNE étape (cadre, mur, palissade) du chantier de pourtour site du groupe gid (who : texte du journal) : tout est
-- relu AVANT toute prise (chantier encore au plan et hors brèche, bord chargé, étape suivante d'après les ouvrages du
-- bord, sol praticable et bord libre pour une première étape, fiche de l'entité, marteau, tous les matériaux) ; boîte
-- de clous ouverte au besoin ; matériaux retirés une seule fois par Stock.takeItem (remis si une prise échoue) ;
-- ouvrage posé par Fortify.placeStructure. Rend un texte et le nombre d'étapes faites, ou nil et une raison.
function Fortify.buildStep(site, gid, who)
    local St = Stock()
    if St == nil or St.findItem == nil or St.takeItem == nil then return nil, "no stock module" end
    local stages = Fortify.STAGES[site.kind]
    if stages == nil then return nil, "not a ring site" end
    if type(buildUtil) ~= "table" or buildUtil.setInfo == nil or IsoThumpable == nil or GameEntityFactory == nil then
        return nil, "no vanilla build helpers"
    end
    local cur, why = ringSiteNow(gid, site)
    if cur == nil then return nil, why end
    local cell = getCell()
    local north = site.north == true
    local sq = cell ~= nil and cell:getGridSquare(site.x, site.y, site.z) or nil
    local ox, oy = site.x, site.y - 1
    if not north then ox, oy = site.x - 1, site.y end
    local other = sq ~= nil and cell:getGridSquare(ox, oy, site.z) or nil
    if sq == nil or other == nil then return nil, "square not loaded" end
    local kind, done = builtOn(sq, north)
    done = done or 0
    if kind ~= nil and kind ~= site.kind then return nil, "other structure (" .. kind .. ")" end
    if done >= #stages then return nil, "already done" end
    local stage = stages[done + 1]
    local prev
    if stage.prev ~= nil then
        prev = structureOn(sq, north, stage.prev)
        if prev == nil then return nil, "no " .. stage.prev end
    elseif not groundOk(sq) or other:getBuildingDef() ~= nil or other:isWaterSquare() then
        return nil, "ground"
    elseif sq:isBlockedTo(other) then
        return nil, "edge closed"
    end
    local info, sprite = Fortify.entityInfo(stage.entity, north)
    if info == nil then return nil, sprite end
    if stage.tool ~= nil and not Fortify.hasTool(gid, stage.tool) then return nil, "no " .. string.lower(stage.tool) end
    local nails, others = 0, {}
    for _, r in ipairs(stage.materials) do
        if #r.types == 1 and r.types[1] == Fortify.NAILS then nails = r.n else others[#others + 1] = r end
    end
    local picked = {}
    local items, miss = gather(gid, others, picked)
    if items == nil then return nil, "no " .. tostring(miss) end
    local use = site.kind .. " " .. site.id
    if nails > 0 then
        local trial = {}
        for k, v in pairs(picked) do trial[k] = v end
        local loose = gather(gid, { req({ Fortify.NAILS }, nails) }, trial)
        if loose == nil then
            local boxF, box, bctr = St.findItem(gid, ofType(Fortify.NAILS_BOX))
            if boxF == nil then return nil, "no nails" end
            local ok, w = openBox(gid, box, bctr, who, use)
            if not ok then return nil, "box of nails not opened: " .. tostring(w) end
            loose = gather(gid, { req({ Fortify.NAILS }, nails) }, picked)
            if loose == nil then return nil, "no nails" end
        end
        for _, e in ipairs(loose) do items[#items + 1] = e end
    end
    local taken = {}
    for _, e in ipairs(items) do
        local id = e.it:getID()
        local got, w = St.takeItem(gid, function(it) return it:getID() == id end, who, use)
        if got == nil then
            for _, b in ipairs(taken) do   -- objets remis (relus comme ajoutés) : rien n'est perdu
                b.ctr:AddItem(b.it)
                if isServer() then sendAddItemToContainer(b.ctr, b.it) end
            end
            return nil, e.it:getFullType() .. " not taken: " .. tostring(w)
        end
        taken[#taken + 1] = e
    end
    Fortify.placeStructure(sq, north, info, sprite, prev)
    Fortify.invalidate(gid)
    Fortify.stats.stages = Fortify.stats.stages + 1
    return string.format("%s %d/%d built on %s (%d item(s) used)", stage.entity, done + 1, #stages, site.id, #taken),
        done + 1
end

-- ================================================================ réparations (LK14-T06)
-- Fiche docs/annexes/conception/fortification.md §9. Autorité seulement ; une réparation par appel ; tout est relu AVANT toute
-- prise ; matériaux retirés une seule fois par Stock.takeItem (remis si une prise échoue).

-- Objets pris un à un dans le stock (items : { it, ctr }) ; une prise qui échoue remet les objets déjà pris. Rend vrai,
-- ou faux et une raison.
local function takeAll(gid, items, who, use)
    local St = Stock()
    local taken = {}
    for _, e in ipairs(items) do
        local id = e.it:getID()
        local got, w = St.takeItem(gid, function(it) return it:getID() == id end, who, use)
        if got == nil then
            for _, b in ipairs(taken) do   -- objets remis (relus comme ajoutés) : rien n'est perdu
                b.ctr:AddItem(b.it)
                if isServer() then sendAddItemToContainer(b.ctr, b.it) end
            end
            return false, e.it:getFullType() .. " not taken: " .. tostring(w)
        end
        taken[#taken + 1] = e
    end
    return true
end

-- Planche saine : état relatif au moins REPAIR_BELOW (une planche plus abîmée serait aussitôt à réparer).
local function soundPlank(it)
    if it:getFullType() ~= Fortify.PLANK then return false end
    local mx = it:getConditionMax()
    return mx ~= nil and mx > 0 and it:getCondition() / mx >= cfg().REPAIR_BELOW
end

-- Clous libres pour n clous, en ouvrant une boîte au besoin (comme buildStep) : liste { it, ctr }, ou nil et une raison.
local function nailsFor(gid, n, picked, who, use)
    local trial = {}
    for k, v in pairs(picked) do trial[k] = v end
    local loose = gather(gid, { req({ Fortify.NAILS }, n) }, trial)
    if loose ~= nil then
        for k, v in pairs(trial) do picked[k] = v end
        return loose
    end
    local boxF, box, bctr = Stock().findItem(gid, ofType(Fortify.NAILS_BOX))
    if boxF == nil then return nil, "no nails" end
    local ok, w = openBox(gid, box, bctr, who, use)
    if not ok then return nil, "box of nails not opened: " .. tostring(w) end
    loose = gather(gid, { req({ Fortify.NAILS }, n) }, picked)
    if loose == nil then return nil, "no nails" end
    return loose
end

-- Barricade de bois la plus garnie de l'ouverture o (celle dont la planche extérieure reçoit les coups) : barricade,
-- addOpposite ; ou nil et une raison.
local function plankedSide(o)
    local same, opp = o:getBarricadeOnSameSquare(), o:getBarricadeOnOppositeSquare()
    local ps, ms = planksOf(same)
    local po, mo = planksOf(opp)
    if ms or mo then return nil, "metal barricade" end
    if ps > 0 and ps >= po then return same, false end
    if po > 0 then return opp, true end
    return nil, "no barricade"
end

-- Répare la barricade du chantier site (target "barricade") : planche extérieure abîmée retirée (removePlank,
-- IsoBarricade.java:110-136 : planche d'état proportionnel rendue au conteneur de la planche neuve, comme
-- ISUnbarricadeAction:complete la rend au joueur, M/lua/shared/TimedActions/ISUnbarricadeAction.lua:97-152), planche
-- saine clouée à sa place (addPlank, :90-108), transmission : état de la barricade (sendObjectChange(STATE)) ; si la
-- planche retirée était la dernière, barricade effacée par le Java (transmitRemoveItemFromSquare sur un serveur) puis
-- recréée et envoyée complète. Rend un texte et 1, ou nil et une raison.
local function repairPlank(site, gid, who)
    local St = Stock()
    local o, sq = Fortify.openingOf(site)
    if o == nil then return nil, sq == nil and "square not loaded" or "opening gone" end
    local b, addOpp = plankedSide(o)
    if b == nil then return nil, addOpp end
    local cond = b:getThumpCondition()
    if not needsRepair(cond) then return nil, "already repaired" end
    if not Fortify.hasTool(gid, "HAMMER") then return nil, "no hammer" end
    local pf, plank, pctr = St.findItem(gid, soundPlank)
    if pf == nil then return nil, "no sound plank" end
    local use = "repair " .. site.id
    local items = { { it = plank, ctr = pctr } }
    local nails, why = nailsFor(gid, 1, { [plank:getID()] = true }, who, use)
    if nails == nil then return nil, why end
    items[#items + 1] = nails[1]
    local ok, w = takeAll(gid, items, who, use)
    if not ok then return nil, w end
    local before = b:getNumPlanks()
    local old = b:removePlank(nil)
    local isNew = false
    if before <= 1 then   -- dernière planche : la barricade a été retirée de sa case
        b = IsoBarricade.AddBarricadeToObject(o, addOpp)
        if b == nil then return nil, "barricade not re-added" end
        isNew = true
    end
    b:addPlank(nil, plank)
    if isServer() then
        if isNew then b:transmitCompleteItemToClients() else b:sendObjectChange(IsoObjectChange.STATE) end
    end
    if old ~= nil then   -- planche abîmée rendue (vanilla : à l'inventaire de celui qui la retire)
        pctr:AddItem(old)
        if isServer() then sendAddItemToContainer(pctr, old) end
    end
    if type(buildUtil) == "table" and buildUtil.setHaveConstruction ~= nil then
        buildUtil.setHaveConstruction(b:getSquare(), true)
    end
    Fortify.invalidate(gid)
    Fortify.stats.repairs = Fortify.stats.repairs + 1
    return string.format("outer plank of %s %s replaced (%d%% -> %d%%, %d plank(s))", tostring(site.opening), site.id,
        math.floor(cond * 100 + 0.5), math.floor(b:getThumpCondition() * 100 + 0.5), b:getNumPlanks()), 1
end

-- Ouvrage achevé du pourtour (mur sur son cadre, palissade) sur le bord (sq, north), ou nil.
local function finishedStructure(sq, north, target)
    local kind, steps, o = builtOn(sq, north)
    if kind ~= target then return nil end
    if kind == "wall" and steps < 2 then return nil end
    return o
end

-- Répare un mur ou une palissade du chantier site (target "wall" ou "palisade") comme la réparation vanilla
-- (ISMoveableSpriteProps:repairObject, M/lua/shared/Moveables/ISMoveableSpriteProps.lua:3538-3599) sans hasard ni
-- compétence : marteau et scie, pièce requise et une pièce facultative selon les dégâts (Fortify.repairParts),
-- matériaux retirés, santé remise au maximum (IsoThumpable.setHealth envoie sync() sur un serveur,
-- J/iso/objects/IsoThumpable.java:288-297). Rend un texte et 1, ou nil et une raison.
local function repairStructure(site, gid, who)
    local plan = Fortify.plan(gid)
    local bd = plan ~= nil and plan.bounds or nil
    if bd == nil or site.x < bd.x1 or site.x > bd.x2 or site.y < bd.y1 or site.y > bd.y2 then
        return nil, "outside the home"
    end
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(site.x, site.y, site.z) or nil
    if sq == nil then return nil, "square not loaded" end
    local o = finishedStructure(sq, site.north == true, site.target)
    if o == nil then return nil, "no " .. tostring(site.target) end
    local health = Fortify.healthRatio(o)
    if not needsRepair(health) then return nil, "already repaired" end
    local r = Fortify.REPAIRS[site.target]
    for _, name in ipairs(r.tools) do
        if not Fortify.hasTool(gid, name) then return nil, "no " .. string.lower(name) end
    end
    local required, options = Fortify.repairParts(site.target, health)
    local picked = {}
    local items, miss = gather(gid, required, picked)
    if items == nil then return nil, "no " .. tostring(miss) end
    local use = "repair " .. site.id
    local extra
    for _, opt in ipairs(options) do   -- première pièce facultative présente en quantité
        if extra == nil then
            local trial = {}
            for k, v in pairs(picked) do trial[k] = v end
            extra = gather(gid, { opt }, trial)
            if extra ~= nil then picked = trial end
        end
    end
    if extra == nil and options[1] ~= nil and options[1].types[1] == Fortify.NAILS then   -- clous en boîte
        local w
        extra, w = nailsFor(gid, options[1].n, picked, who, use)
        if extra == nil then return nil, w end
    end
    if extra == nil then return nil, "no " .. tostring(options[1] and options[1].types[1]) end
    for _, e in ipairs(extra) do items[#items + 1] = e end
    local ok, w = takeAll(gid, items, who, use)
    if not ok then return nil, w end
    local h0 = o:getHealth()
    o:setHealth(o:getMaxHealth())
    Fortify.invalidate(gid)
    Fortify.stats.repairs = Fortify.stats.repairs + 1
    return string.format("%s %s repaired (%d -> %d / %d, %d item(s) used)", tostring(o:getName()), site.id, h0,
        o:getHealth(), o:getMaxHealth(), #items), 1
end

-- Répare l'ouvrage du chantier site (kind "repair") du groupe gid : barricade, mur ou palissade.
function Fortify.repair(site, gid, who)
    local St = Stock()
    if St == nil or St.findItem == nil or St.takeItem == nil then return nil, "no stock module" end
    if site.target == "barricade" then return repairPlank(site, gid, who) end
    if site.target == "wall" or site.target == "palisade" then return repairStructure(site, gid, who) end
    return nil, "unknown repair target " .. tostring(site.target)
end

local function claimKey(gid, sid) return tostring(gid) .. "|" .. sid end

-- Chantier du membre libéré (fin, abandon, interruption : Routines.leave et forget).
function Fortify.release(id, m)
    if type(m) ~= "table" or type(m.site) ~= "table" then return end
    local k = claimKey(m.gid, m.site.id)
    if Fortify.state.claims[k] == id then Fortify.state.claims[k] = nil end
end

local function finishSite(id, m, minute, why)
    m.phase = "done"
    Fortify.release(id, m)
    Fortify.state.rest[id] = minute + cfg().REST_MINUTES
    local unit = m.site.kind == "barricade" and "plank(s)" or m.site.kind == "repair" and "repair(s)" or "stage(s)"
    if why == nil then
        Fortify.stats.finished = Fortify.stats.finished + 1
        log().info("npc %s (%s %s): %s %s done, %d %s", tostring(id), tostring(m.gid), tostring(m.mid), m.site.kind,
            m.site.id, m.placed, unit)
    else
        Fortify.stats.skipped = Fortify.stats.skipped + 1
        log().info("npc %s (%s %s): %s %s stopped after %d %s: %s", tostring(id), tostring(m.gid), tostring(m.mid),
            m.site.kind, m.site.id, m.placed, unit, tostring(why))
    end
end

-- Geste, minutes de travail avant chaque pose et effet (une planche, une étape) selon la sorte de chantier.
local function workOf(site)
    local c = cfg()
    if site.kind == "barricade" then return c.GESTURE, c.PLANK_MINUTES, Fortify.nailPlank end
    if site.kind == "repair" then   -- LK14-T06 : marteau (son vanilla « Hammering » des deux réparations)
        return c.GESTURE, (c.REPAIR_MINUTES or {})[site.target] or c.PLANK_MINUTES, Fortify.repair
    end
    return c.RING_GESTURES[site.kind] or c.GESTURE, c.STAGE_MINUTES, Fortify.buildStep
end

-- Place de travail : la case intérieure de l'ouverture, tournée vers l'extérieur ; sinon une case libre voisine du
-- même bâtiment (règle des corvées, Routines.exec.placeBeside).
local function placeFor(site)
    local cell = getCell()
    if cell == nil then return nil end
    local X = R().exec
    local sq = cell:getGridSquare(site.inside.x, site.inside.y, site.z)
    if X.standable(sq) then
        local D = LivingKnox.Decisions
        return { x = site.inside.x, y = site.inside.y, z = site.z,
            a = D.angleTo(site.outside.x - site.inside.x, site.outside.y - site.inside.y) }
    end
    local bid = sq ~= nil and X.buildingId(sq) or nil
    return X.placeBeside(cell, site.inside.x, site.inside.y, site.z, bid, {})
end

local function step(id, ctx, m)
    local X = R().exec
    local e = X.entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) and (m.phase == "go" or m.phase == "face") then
        -- Une autre consigne est passée (suite de test, autre module) : retour à la place.
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
        m.phase = "go"
    end
    if m.phase == "place" then
        local p = placeFor(m.site)
        if p == nil then return finishSite(id, m, ctx.minute, "no place inside " .. m.site.id) end
        m.place, m.phase = p, "go"
    end
    if m.phase == "go" then
        local res = X.goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
        if res == "moving" then return end
        if res == "failed" then return finishSite(id, m, ctx.minute, "cannot reach " .. m.site.id) end
        m.phase = "face"
    end
    if m.phase == "face" then
        if m.place.a ~= nil then
            if m.faceV == nil then
                X.faceTo(id, m, m.place.a)
                return
            end
            e = X.entryOf(id)
            if e == nil or e.v ~= m.faceV or not e.done then return end
        end
        X.sitDown(id, m, (workOf(m.site)))
        m.since, m.phase = ctx.minute, "work"
        return
    end
    if m.phase == "work" then
        local gesture, minutes, effect = workOf(m.site)
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) ~= gesture then X.sitDown(id, m, gesture) end
        if ctx.minute - m.since < minutes then return end
        m.phase = "nail"   -- avant l'effet : jamais deux fois la même pose, même si le Java lève une erreur
        local ok, text, n = pcall(effect, m.site, m.gid, m.mid)
        if not ok then
            log().error("npc %s: %s %s failed: %s", tostring(id), m.site.kind, m.site.id, tostring(text))
            return finishSite(id, m, ctx.minute, "error")
        end
        if text == nil then return finishSite(id, m, ctx.minute, n) end
        m.placed = m.placed + 1
        log().info("npc %s (%s %s): %s", tostring(id), tostring(m.gid), tostring(m.mid), text)
        if n >= m.site.steps then return finishSite(id, m, ctx.minute, nil) end
        m.since, m.phase = ctx.minute, "work"
    end
end

-- Membre de poste « builder » en corvée (comportement « chore », LK_Routines.apply) : poursuit son chantier de
-- fortification (barricade, mur, palissade) ou en prend un (Fortify.siteFor, chantier qu'aucun autre membre ne
-- tient). Rend vrai si le membre est occupé par la fortification (corvée et entretien attendent), faux sinon.
function Fortify.run(id, st, ctx, g)
    if ctx.gid == nil or ctx.duty ~= "builder" or type(g) ~= "table" or type(g.home) ~= "table" then return false end
    local mem = R().state.npcs
    local m = mem[id]
    if m ~= nil and m.kind == "fortify" then
        if m.phase == "done" then return false end
        step(id, ctx, m)
        return true
    end
    local wait = Fortify.state.rest[id]
    if wait ~= nil and ctx.minute < wait then return false end
    local site, why = Fortify.siteFor(ctx.gid, ctx.mid)
    local k = site ~= nil and claimKey(ctx.gid, site.id) or nil
    if site == nil or not Fortify.KINDS[site.kind] or site.inside == nil
        or (Fortify.state.claims[k] ~= nil and Fortify.state.claims[k] ~= id) then
        Fortify.state.rest[id] = ctx.minute + cfg().IDLE_MINUTES
        log().debug("npc %s: no fortification site: %s", tostring(id), tostring(site ~= nil and site.id or why))
        return false
    end
    -- Place du chantier évitée par ce PNJ (échec "stuck" récent, LivingKnox.Movement.avoided) : il le reprend après
    -- l'évitement au lieu d'enchaîner les arrêts "cannot reach" (campagne MP du 2026-10-15, réparation urgente).
    local Mv = LivingKnox.Movement
    if Mv ~= nil and Mv.avoided ~= nil and Mv.avoided(id, site.inside.x, site.inside.y, site.z) ~= nil then
        Fortify.state.rest[id] = ctx.minute + cfg().REST_MINUTES
        log().debug("npc %s: site %s avoided for now (recent stuck move)", tostring(id), site.id)
        return false
    end
    if m ~= nil then R().leave(id) end   -- corvée visible en cours : debout d'abord
    Fortify.state.claims[k] = id
    m = { key = "fortify " .. site.id, kind = "fortify", site = site, gid = ctx.gid, mid = ctx.mid, phase = "place",
        fails = 0, placed = 0 }
    mem[id] = m
    Fortify.stats.started = Fortify.stats.started + 1
    log().info("npc %s (%s %s): %s %s (%s, %d/%d step(s), %s)", tostring(id), tostring(ctx.gid), tostring(ctx.mid),
        site.kind, site.id, tostring(site.opening or site.side), site.have, site.steps, tostring(st.why or st.b))
    step(id, ctx, m)
    return true
end

-- ================================================================ rattrapage hors écran (LK14-T05)
-- Fiche docs/annexes/conception/fortification.md §10. Autorité seulement. Le monde n'existe pas hors de la zone chargée
-- (aucune case, aucun objet : fortification.md §3) : la simulation avance un relevé gardé au registre privé des
-- groupes, puis le résultat est posé par les fonctions de pose existantes quand la zone du foyer est chargée.
--   Relevé (champ facultatif fort du groupe, schéma 1 des groupes inchangé, contrôlé ici et ignoré par LK_Groups).
--     Vue de travail (Fortify.fortView, forme 1 d'avant LK13-T07) :
--     { v, hx, hy, hz, key, day, tools = { [outil] = vrai }, tiers = { [tier] = { h, s } },
--       sites = { { id, k, t, x, y, z, n, o, s, h } }, work, boxes = { { i, u } },
--       pend = { n, ops = { { u, id, k, x, y, z, n, o, a, b } } } }
--     Forme gardée au registre (LK13-T07, forme 2, compacte : chaînes courtes au lieu de tables, coordonnées
--     relatives au foyer, identifiants recalculés, clé du plan réduite à une empreinte) :
--     fort = { v = 2, hx, hy, hz, key = empreinte, day, tools = "HAMMER,SAW" (outils présents), tiers = "h/s,h/s,h/s"
--       (ordre de TIERS), sites = "<chantier>;<chantier>", work, boxes = "<i>:<u>,<i>:<u>", pn, ops = "<écart>;..." }
--       chantier = <sorte b|w|p><tier g|u|o><dx>,<dy>,<z><face N|W><côté opposé 0|1><visées s><faites h>
--       écart    = <u>:<sorte><dx>,<dy>,<z><face><côté><avant a><après b>
--     L'ancienne forme 1 est lue telle quelle et réécrite en forme 2 (Fortify.migrate au premier examen, ou à la
--     première écriture du relevé), écarts en attente et numéros compris : aucune perte ni double pose.
--     écrit par Fortify.feasible (plan relevé dans le monde, aucun écart en attente) : chantiers restants du plan
--     (barricades, murs, palissades ; réparations et portes ouvertes écartées), dans l'ordre du plan ; étapes faites
--     et visées par tier (niveau) ; outils présents au foyer (un outil ne disparaît pas hors écran : personne n'y est).
--   Simulation (Fortify.offscreenHour, appelé par LK_Simulation.advance après chaque heure de chaque groupe, dans
--     son écriture du registre ; logique pure, sans hasard ni accès au monde) : de jour (Simulation.isNight),
--     groupe sans membre incarné (sinon les vrais ouvriers travaillent), chaque membre vivant de poste « builder »
--     au foyer (hors expédition) donne CFG.OFF_WORK_MINUTES minutes de travail par heure (reste gardé dans work
--     tant qu'un chantier attend) ; une étape coûte PLANK_MINUTES (planche) ou STAGE_MINUTES (cadre, mur,
--     palissade), comme le travail visible. Chantiers pris dans l'ordre du plan ; un chantier dont l'étape suivante
--     manque d'outil ou de matériaux est passé. Matériaux pris dans la référence du stock, une seule fois, par son
--     journal d'écarts (Stock.offscreenTake : écarts « take » appliqués aux conteneurs à l'arrivée) ; clous : libres
--     d'abord, puis boîtes suivies (BOX_NAILS clous chacune, clous utilisés notés dans boxes : la boîte reste dans
--     la référence jusqu'à son ouverture réelle). Étape faite : h du chantier et du tier avancés, écart de pose
--     { a = étapes avant, b = étapes après } ajouté au journal de pose pend (un par chantier et par heure).
--   Application (Fortify.applyPending, à l'arrivée d'un joueur : LoadChunk et chaque minute de jeu, dès que la zone
--     du foyer est chargée, et avant tout chantier en jeu) : chaque écart est posé par Fortify.addPlanks (planches
--     neuves) ou Fortify.placeStructure (cadre, mur, palissade), jusqu'à b étapes en partant de l'état réel, jamais
--     plus que b - a ; boîtes utilisées ouvertes comme OpenBox100 (BOX_NAILS - u clous ajoutés, boîte retirée par
--     Stock.takeItem). Marque d'application idempotente : l'objet posé (ouverture barricadée, dernier ouvrage) et les clous
--     créés portent ModData LKFortOp = "<groupe>:<numéro>" (clous : "<groupe>:box:<id>") jusqu'à l'écriture du
--     registre qui ôte les écarts traités ; un écart dont l'objet porte sa marque, ou dont l'état réel atteint déjà
--     b, n'est pas reposé (ni double, ni second achat). État posé = état simulé. Barricade : marque sur l'ouverture
--     (la ModData d'une IsoBarricade n'est pas sauvegardée, IsoBarricade.java:621-632).
Fortify.FORT_FORMAT = 2      -- forme compacte gardée au registre (LK13-T07)
Fortify.FORT_FORMAT_OLD = 1  -- ancienne forme (tables), lue et convertie
Fortify.OP_TAG = "LKFortOp"
Fortify.OFF_KINDS = { barricade = true, wall = true, palisade = true }
Fortify.OFF_PEND_MAX = 256    -- écarts de pose en attente au plus
Fortify.CFG.OFF_WORK_MINUTES = Fortify.CFG.OFF_WORK_MINUTES or 30   -- minutes de travail utiles par ouvrier et par
                              -- heure hors écran (trajets et pauses du travail visible : moitié de l'heure)
Fortify.CFG.SCAN_MS = Fortify.CFG.SCAN_MS or 1000   -- examen depuis LoadChunk au plus une fois par seconde
for _, k in ipairs({ "offHours", "offSteps", "applied", "placed", "already", "adopted", "dropped", "kept",
    "snapshots", "boxesOpened", "migrated" }) do
    Fortify.stats[k] = Fortify.stats[k] or 0
end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local TIER_SET = { ground = true, upper = true, outer = true }

-- Vue de travail f (forme 1) valide pour le foyer home.
local function validView(f, home)
    if type(f) ~= "table" or type(home) ~= "table" then return false end
    if f.hx ~= home.x or f.hy ~= home.y or f.hz ~= home.z then return false end
    if type(f.key) ~= "string" or type(f.tools) ~= "table" or type(f.tiers) ~= "table" then return false end
    if type(f.sites) ~= "table" or type(f.boxes) ~= "table" or type(f.pend) ~= "table" then return false end
    if type(f.work) ~= "number" or f.work ~= f.work or f.work < 0 then return false end
    local p = f.pend
    if not isInt(p.n, 0, 2147483647) or type(p.ops) ~= "table" or #p.ops > Fortify.OFF_PEND_MAX then return false end
    for name, t in pairs(f.tiers) do
        if not TIER_SET[name] or type(t) ~= "table" or not isInt(t.s, 0, 100000) or not isInt(t.h, 0, t.s) then
            return false
        end
    end
    for _, e in ipairs(f.sites) do
        if type(e) ~= "table" or type(e.id) ~= "string" or not Fortify.OFF_KINDS[e.k] or not TIER_SET[e.t]
            or not isInt(e.x, -1e7, 1e7) or not isInt(e.y, -1e7, 1e7) or not isInt(e.z, -32, 31)
            or not isInt(e.s, 1, 4) or not isInt(e.h, 0, e.s) then
            return false
        end
    end
    for _, op in ipairs(p.ops) do
        if type(op) ~= "table" or not isInt(op.u, 1, p.n) or type(op.id) ~= "string" or not Fortify.OFF_KINDS[op.k]
            or not isInt(op.x, -1e7, 1e7) or not isInt(op.y, -1e7, 1e7) or not isInt(op.z, -32, 31)
            or not isInt(op.a, 0, 3) or not isInt(op.b, op.a + 1, 4) then
            return false
        end
    end
    for _, b in ipairs(f.boxes) do
        if type(b) ~= "table" or not isInt(b.i, -2147483648, 2147483647) or not isInt(b.u, 1, cfg().BOX_NAILS) then
            return false
        end
    end
    return true
end

-- ---------------------------------------------------------------- forme compacte (LK13-T07)
local KIND_CODE = { barricade = "b", wall = "w", palisade = "p" }
local CODE_KIND = { b = "barricade", w = "wall", p = "palisade" }
local TIER_CODE = { ground = "g", upper = "u", outer = "o" }
local CODE_TIER = { g = "ground", u = "upper", o = "outer" }
local SITE_PATTERN = "^([bwp])([guo])(%-?%d+),(%-?%d+),(%-?%d+)([NW])([01])(%d)(%d)$"
local OP_PATTERN = "^(%d+):([bwp])(%-?%d+),(%-?%d+),(%-?%d+)([NW])([01])(%d)(%d)$"
local BOX_PATTERN = "^(%-?%d+):(%d+)$"
local TIER_PATTERN = "^(%d+)/(%d+)$"

-- Morceaux de s séparés par sep (caractère simple, recherche littérale ; chaîne vide : aucun morceau).
local function split(s, sep)
    local out = {}
    if s == "" then return out end
    local i = 1
    while true do
        local j = string.find(s, sep, i, true)
        if j == nil then
            out[#out + 1] = string.sub(s, i)
            return out
        end
        out[#out + 1] = string.sub(s, i, j - 1)
        i = j + 1
    end
end

-- Empreinte courte et stable d'un texte (longueur, somme d'Adler-32 et polynôme modulo 2^31 - 1, sans opérateur
-- binaire) : clé du relevé gardée au registre à la place du texte complet du plan.
function Fortify.digest(text)
    local a, b, c = 1, 0, 0
    for i = 1, #text do
        local x = string.byte(text, i)
        a = (a + x) % 65521
        b = (b + a) % 65521
        c = (c * 31 + x) % 2147483647
    end
    return string.format("%.0f:%.0f:%.0f", #text, b * 65536 + a, c)
end

-- Vue de travail d'un relevé en forme 2 (nil si une chaîne est mal formée).
local function parseFort(f)
    if type(f.sites) ~= "string" or type(f.ops) ~= "string" or type(f.boxes) ~= "string"
        or type(f.tools) ~= "string" or type(f.tiers) ~= "string" or type(f.hx) ~= "number"
        or type(f.hy) ~= "number" then
        return nil
    end
    local hx, hy = f.hx, f.hy
    local view = { v = f.v, hx = hx, hy = hy, hz = f.hz, key = f.key, day = f.day, work = f.work, tools = {},
        tiers = {}, sites = {}, boxes = {}, pend = { n = f.pn, ops = {} } }
    for _, name in ipairs(split(f.tools, ",")) do view.tools[name] = true end
    local parts = split(f.tiers, ",")
    if #parts ~= #Fortify.TIERS then return nil end
    for i, t in ipairs(Fortify.TIERS) do
        local h, s = string.match(parts[i], TIER_PATTERN)
        if h == nil then return nil end
        view.tiers[t] = { h = tonumber(h), s = tonumber(s) }
    end
    for _, txt in ipairs(split(f.sites, ";")) do
        local k, t, dx, dy, z, n, o, s, h = string.match(txt, SITE_PATTERN)
        if k == nil then return nil end
        local kind, x, y = CODE_KIND[k], hx + tonumber(dx), hy + tonumber(dy)
        view.sites[#view.sites + 1] = { id = siteId(kind, x, y, tonumber(z), n == "N"), k = kind, t = CODE_TIER[t],
            x = x, y = y, z = tonumber(z), n = n == "N", o = o == "1", s = tonumber(s), h = tonumber(h) }
    end
    for _, txt in ipairs(split(f.ops, ";")) do
        local u, k, dx, dy, z, n, o, a, b = string.match(txt, OP_PATTERN)
        if u == nil then return nil end
        local kind, x, y = CODE_KIND[k], hx + tonumber(dx), hy + tonumber(dy)
        view.pend.ops[#view.pend.ops + 1] = { u = tonumber(u), id = siteId(kind, x, y, tonumber(z), n == "N"), k = kind,
            x = x, y = y, z = tonumber(z), n = n == "N", o = o == "1", a = tonumber(a), b = tonumber(b) }
    end
    for _, txt in ipairs(split(f.boxes, ",")) do
        local i, u = string.match(txt, BOX_PATTERN)
        if i == nil then return nil end
        view.boxes[#view.boxes + 1] = { i = tonumber(i), u = tonumber(u) }
    end
    return view
end

local function flag(v) return v == true and "1" or "0" end
local function face(v) return v == true and "N" or "W" end

-- Forme 2 (gardée au registre) d'une vue de travail valide.
local function packFort(view)
    local hx, hy = view.hx, view.hy
    local tools = {}
    for name, v in pairs(view.tools) do
        if v == true then tools[#tools + 1] = name end
    end
    table.sort(tools)
    local tiers = {}
    for i, t in ipairs(Fortify.TIERS) do
        local p = view.tiers[t] or { h = 0, s = 0 }
        tiers[i] = p.h .. "/" .. p.s
    end
    local sites = {}
    for i, e in ipairs(view.sites) do
        sites[i] = KIND_CODE[e.k] .. TIER_CODE[e.t] .. (e.x - hx) .. "," .. (e.y - hy) .. "," .. e.z .. face(e.n)
            .. flag(e.o) .. e.s .. e.h
    end
    local ops = {}
    for i, op in ipairs(view.pend.ops) do
        ops[i] = op.u .. ":" .. KIND_CODE[op.k] .. (op.x - hx) .. "," .. (op.y - hy) .. "," .. op.z .. face(op.n)
            .. flag(op.o) .. op.a .. op.b
    end
    local boxes = {}
    for i, b in ipairs(view.boxes) do boxes[i] = string.format("%.0f", b.i) .. ":" .. b.u end
    local key = view.key
    if view.v == Fortify.FORT_FORMAT_OLD then key = Fortify.digest(key) end   -- ancienne forme : texte complet du plan
    return { v = Fortify.FORT_FORMAT, hx = hx, hy = hy, hz = view.hz, key = key, day = view.day,
        tools = table.concat(tools, ","), tiers = table.concat(tiers, ","), sites = table.concat(sites, ";"),
        work = view.work, boxes = table.concat(boxes, ","), pn = view.pend.n, ops = table.concat(ops, ";") }
end
Fortify.packFort = packFort

-- Vue de travail (forme 1, tables) du relevé f gardé au registre pour le foyer home, ou nil s'il est invalide ou
-- d'un autre foyer. Forme 2 : vue neuve à chaque appel (modifiable). Ancienne forme 1 : f lui-même (à réécrire par
-- packFort avant de le garder).
local function fortView(f, home)
    if type(f) ~= "table" then return nil end
    local view
    if f.v == Fortify.FORT_FORMAT then
        view = parseFort(f)
    elseif f.v == Fortify.FORT_FORMAT_OLD then
        view = f
    end
    if view == nil or not validView(view, home) then return nil end
    return view
end
Fortify.fortView = fortView

-- Vue en lecture seule du relevé du groupe gid (mémoire : relevé inchangé depuis le dernier appel = même vue, à ne
-- pas modifier), ou nil.
local function readView(gid, f, home)
    if type(f) ~= "table" or f.v ~= Fortify.FORT_FORMAT then return fortView(f, home) end
    local views = Fortify.state.views
    if views == nil then
        views = {}
        Fortify.state.views = views
    end
    local c = views[gid]
    if c ~= nil and c.sites == f.sites and c.ops == f.ops and c.boxes == f.boxes and c.tools == f.tools
        and c.tiers == f.tiers and c.work == f.work and c.pn == f.pn and c.key == f.key and c.hx == f.hx
        and c.hy == f.hy and c.hz == f.hz and c.day == f.day and type(home) == "table" and c.homeX == home.x
        and c.homeY == home.y and c.homeZ == home.z then
        return c.view
    end
    local view = fortView(f, home)
    views[gid] = { sites = f.sites, ops = f.ops, boxes = f.boxes, tools = f.tools, tiers = f.tiers, work = f.work,
        pn = f.pn, key = f.key, hx = f.hx, hy = f.hy, hz = f.hz, day = f.day, homeX = type(home) == "table" and home.x,
        homeY = type(home) == "table" and home.y, homeZ = type(home) == "table" and home.z, view = view }
    return view
end

-- LK13-T07 : relevés gardés dans l'ancienne forme réécrits en forme compacte, écarts en attente (mêmes numéros, donc
-- mêmes marques d'application) et boîtes entamées compris, en une écriture du registre ; relevé invalide laissé tel
-- quel (remplacé au prochain relevé, comme avant). Rend le nombre de relevés convertis.
function Fortify.migrate()
    local G = Groups()
    if G == nil or not G.isReady() then return 0 end
    local n = G.update(function(data)
        local count = 0
        for _, g in pairs(data.groups) do
            local f = type(g) == "table" and g.fort or nil
            if type(f) == "table" and f.v == Fortify.FORT_FORMAT_OLD then
                local view = fortView(f, g.home)
                if view ~= nil then
                    g.fort = packFort(view)
                    count = count + 1
                end
            end
        end
        return count > 0, count
    end)
    if type(n) ~= "number" then return 0 end
    if n > 0 then
        Fortify.stats.migrated = Fortify.stats.migrated + n
        log().info("fortify: %d offscreen survey(s) rewritten in the compact form", n)
    end
    return n
end

-- Relevé hors écran f valide pour le foyer home (l'une ou l'autre forme).
local function validFort(f, home)
    return fortView(f, home) ~= nil
end
Fortify.validFort = validFort

-- Groupe vivant du registre (lecture seule, sans copie), ou nil.
local function liveGroup(gid)
    local G = Groups()
    if G == nil or not G.isReady() then return nil end
    local g = G.update(function(data) return false, data.groups[gid] end)
    if type(g) ~= "table" then return nil end
    return g
end

-- Vrai si le travail fait hors écran du groupe gid attend d'être posé (écarts de pose ou boîtes de clous entamées).
function Fortify.hasPending(gid)
    local g = liveGroup(gid)
    local f = g ~= nil and readView(gid, g.fort, g.home) or nil
    if f == nil then return false end
    return #f.pend.ops > 0 or #f.boxes > 0
end

-- Étape suivante d'un chantier du relevé e : besoins { types, n }, outil (ou nil), minutes de travail ; nil si fini.
local function nextStage(e)
    local c = cfg()
    if e.h >= e.s then return nil end
    if e.k == "barricade" then
        return { req({ Fortify.PLANK }, 1), req({ Fortify.NAILS }, 1) }, "HAMMER", c.PLANK_MINUTES
    end
    local stages = Fortify.STAGES[e.k]
    local st = stages ~= nil and stages[e.h + 1] or nil
    if st == nil then return nil end
    return st.materials, st.tool, c.STAGE_MINUTES
end

-- Matériaux de toutes les étapes restantes d'un chantier du relevé e (comme site.materials du plan : un chantier
-- n'est commencé que si tout ce qui lui reste tient dans le stock, Fortify.feasibleSites).
local function remainingReqs(e)
    if e.k == "barricade" then
        local n = e.s - e.h
        return { req({ Fortify.PLANK }, n), req({ Fortify.NAILS }, n) }
    end
    local out = {}
    local stages = Fortify.STAGES[e.k] or {}
    for n = e.h + 1, e.s do
        for _, r in ipairs(stages[n] ~= nil and stages[n].materials or {}) do out[#out + 1] = r end
    end
    return out
end

local function boxUsed(f, id)
    for _, b in ipairs(f.boxes) do
        if b.i == id then return b end
    end
    return nil
end

-- Matériaux disponibles hors écran (pur) : { [type] = n } d'après la référence du stock (objets suivis et ajouts en
-- attente) ; clous = clous libres + clous restants des boîtes suivies (BOX_NAILS moins ceux déjà utilisés).
local function offAvail(g, f)
    local St = Stock()
    local s = g.stock
    local out = {}
    local types = { Fortify.PLANK, Fortify.NAILS, Fortify.LOG }
    for _, t in ipairs(Fortify.TIES) do types[#types + 1] = t end
    for _, t in ipairs(types) do out[t] = St.offscreenCount(s, { t }) end
    for _, e in ipairs(s.items) do
        if e.t == Fortify.NAILS_BOX then
            local b = boxUsed(f, e.i)
            out[Fortify.NAILS] = out[Fortify.NAILS] + cfg().BOX_NAILS - (b ~= nil and b.u or 0)
        end
    end
    return out
end

local function copyMap(m)
    local out = {}
    for k, v in pairs(m) do out[k] = v end
    return out
end

-- Prend n clous hors écran : libres d'abord (écarts du stock), puis dans les boîtes suivies (ordre de la référence).
local function takeNails(g, gid, f, n)
    local St = Stock()
    local loose = math.min(n, St.offscreenCount(g.stock, { Fortify.NAILS }))
    if loose > 0 then St.offscreenTake(g, gid, { Fortify.NAILS }, loose) end
    local rest = n - loose
    for _, e in ipairs(g.stock.items) do
        if rest > 0 and e.t == Fortify.NAILS_BOX then
            local b = boxUsed(f, e.i)
            local used = b ~= nil and b.u or 0
            local d = math.min(rest, cfg().BOX_NAILS - used)
            if d > 0 then
                if b == nil then
                    b = { i = e.i, u = 0 }
                    f.boxes[#f.boxes + 1] = b
                end
                b.u = used + d
                rest = rest - d
            end
        end
    end
end

-- Prend les besoins reqs (déjà réservés dans avail par Fortify.reserve) dans la référence du groupe g.
local function takeStage(g, gid, f, reqs)
    local St = Stock()
    for _, r in ipairs(reqs) do
        if #r.types == 1 and r.types[1] == Fortify.NAILS then
            takeNails(g, gid, f, r.n)
        else
            local left = r.n
            for _, t in ipairs(r.types) do
                if left > 0 then
                    local q = math.min(left, St.offscreenCount(g.stock, { t }))
                    if q > 0 then left = left - St.offscreenTake(g, gid, { t }, q) end
                end
            end
        end
    end
end

local function nightAt(hour)
    local S = LivingKnox.Simulation
    if S == nil or S.isNight == nil then return false end
    return S.isNight((hour + 6) % 24)   -- heure simulée k = intervalle [k - 1, k[ : heure du jour de son début
end

-- Ouvriers du groupe vivant g qui travaillent hors écran : vivants, poste « builder », au foyer (hors expédition),
-- non incarnés.
local function offBuilders(g)
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local S = LivingKnox.Simulation
    local n = 0
    for mid, m in pairs(g.members) do
        if type(m) == "table" and m.alive and m.duty == "builder" and not away[mid]
            and not (S ~= nil and S.isEmbodied ~= nil and S.isEmbodied(m)) then
            n = n + 1
        end
    end
    return n
end

-- Heure simulée hour du groupe vivant g (registre, dans l'écriture du pas de LK_Simulation) : chantiers du relevé
-- avancés selon les ouvriers, les outils et les matériaux du stock (fiche §10). Rend { builders, steps, sites, left }
-- ou nil (rien à faire, nuit, groupe incarné, pas de relevé).
local offscreenHour

function Fortify.offscreenHour(g, gid, hour)
    if type(g) ~= "table" or type(g.home) ~= "table" or type(g.members) ~= "table" then return nil end
    -- LK13-T11 : relevé de la minute encore en file (heure et minute dans la même image) fait d'abord quand l'heure
    -- hors écran peut travailler (mêmes conditions que le début de son corps, indépendantes du relevé) : le relevé
    -- qu'elle lit est celui qu'aurait écrit l'image de la minute. Sinon il reste en file (heure sans effet).
    if Fortify.minuteJobs.queued[gid] ~= nil then
        local St, S = Stock(), LivingKnox.Simulation
        if St ~= nil and St.offscreenTake ~= nil and St.validRef(g.stock, g.home) and type(hour) == "number"
            and not nightAt(hour) and not (S ~= nil and S.materialized ~= nil and S.materialized(g)) then
            settle(gid)
        end
    end
    local f = fortView(g.fort, g.home)
    if f == nil or #f.sites == 0 then return nil end
    local out, changed = offscreenHour(g, gid, hour, f)
    if changed or g.fort.v ~= Fortify.FORT_FORMAT then g.fort = packFort(f) end   -- LK13-T07 : forme compacte
    return out
end

-- Corps de Fortify.offscreenHour sur la vue de travail f ; rend le résultat et vrai si f a changé.
offscreenHour = function(g, gid, hour, f)
    local St = Stock()
    if St == nil or St.offscreenTake == nil or not St.validRef(g.stock, g.home) then return nil, false end
    if type(hour) ~= "number" or nightAt(hour) then return nil, false end
    local S = LivingKnox.Simulation
    if S ~= nil and S.materialized ~= nil and S.materialized(g) then return nil, false end   -- vrais ouvriers au travail
    local builders = offBuilders(g)
    if builders == 0 then
        local changed = f.work ~= 0
        f.work = 0
        return nil, changed
    end
    local minutes = f.work + builders * cfg().OFF_WORK_MINUTES
    local avail = offAvail(g, f)
    local ops, steps, touched, waiting = {}, 0, 0, false
    local i = 1
    while i <= #f.sites do
        local e = f.sites[i]
        local reqs, tool, cost = nextStage(e)
        if reqs == nil or (tool ~= nil and f.tools[tool] ~= true) then
            i = i + 1
        elseif not Fortify.reserve({ materials = remainingReqs(e) }, copyMap(avail)) then
            i = i + 1   -- tout ce qui reste au chantier ne tient pas dans le stock : chantier passé
        elseif minutes < cost then
            waiting = true
            break
        elseif (#f.pend.ops >= Fortify.OFF_PEND_MAX and ops[e.id] == nil)
            or not Fortify.reserve({ materials = reqs }, avail) then
            break
        else
            takeStage(g, gid, f, reqs)
            minutes = minutes - cost
            local op = ops[e.id]
            if op == nil then
                f.pend.n = f.pend.n + 1
                op = { u = f.pend.n, id = e.id, k = e.k, x = e.x, y = e.y, z = e.z, n = e.n, o = e.o, a = e.h,
                    b = e.h }
                f.pend.ops[#f.pend.ops + 1] = op
                ops[e.id] = op
                touched = touched + 1
            end
            e.h = e.h + 1
            op.b = e.h
            local tier = f.tiers[e.t]
            if tier ~= nil then tier.h = math.min(tier.s, tier.h + 1) end
            steps = steps + 1
            if e.h >= e.s then table.remove(f.sites, i) end
        end
    end
    local work = waiting and minutes or 0
    local changed = work ~= f.work or steps > 0
    f.work = work
    Fortify.stats.offHours = Fortify.stats.offHours + 1
    if steps == 0 then return { builders = builders, steps = 0, sites = 0, left = #f.sites }, changed end
    Fortify.stats.offSteps = Fortify.stats.offSteps + steps
    Fortify.invalidate(gid)   -- plan en mémoire relevé de nouveau (zone non chargée : relevé hors écran)
    log().info("fortify: group %s offscreen hour %s: %d builder(s), %d step(s) on %d site(s), %d site(s) left, "
        .. "%d change(s) to place", gid, tostring(hour), builders, steps, touched, #f.sites, #f.pend.ops)
    return { builders = builders, steps = steps, sites = touched, left = #f.sites }, changed
end

-- Niveau (0..100) du relevé hors écran du groupe gid (étapes faites / visées par tier, pondéré comme levelOfSites),
-- ou nil sans relevé valide.
function Fortify.offscreenLevel(gid)
    local g = liveGroup(gid)
    local f = g ~= nil and readView(gid, g.fort, g.home) or nil
    if f == nil then return nil end
    local num, den = 0, 0
    for _, t in ipairs(Fortify.TIERS) do
        local p, w = f.tiers[t], cfg().WEIGHTS[t] or 0
        if p ~= nil and p.s > 0 and w > 0 then num, den = num + w * p.h / p.s, den + w end
    end
    if den == 0 then return 100 end
    return math.floor(100 * num / den + 0.5)
end

-- Chantiers faisables hors écran d'après le relevé (pur, rien de pris) : chantiers dont l'outil est présent et dont
-- les matériaux restants tiennent après ceux des précédents (comme Fortify.feasibleSites). Liste de copies { id, kind, tier, x,
-- y, z, north, have, steps, offscreen = vrai } (sans case de travail : Fortify.run ne les prend pas), ou nil sans
-- relevé valide.
function Fortify.offscreenFeasible(gid)
    local g = liveGroup(gid)
    local f = g ~= nil and readView(gid, g.fort, g.home) or nil
    if f == nil then return nil end
    local St = Stock()
    if St == nil or St.offscreenCount == nil or not St.validRef(g.stock, g.home) then return nil end
    local avail = offAvail(g, f)
    local out = {}
    for _, e in ipairs(f.sites) do
        local reqs, tool = nextStage(e)
        if reqs ~= nil and (tool == nil or f.tools[tool] == true)
            and Fortify.reserve({ materials = remainingReqs(e) }, avail) then
            out[#out + 1] = { id = e.id, kind = e.k, tier = e.t, x = e.x, y = e.y, z = e.z, north = e.n, have = e.h,
                steps = e.s, offscreen = true }
        end
    end
    return out
end

-- Relevé hors écran du plan relevé dans le monde (tools : outils présents, Fortify.feasible), écrit au registre s'il
-- a changé et si rien n'attend d'être posé. Rend vrai si écrit.
function Fortify.snapshot(gid, plan, tools)
    if plan == nil or plan.stale then return false end
    local G = Groups()
    if G == nil or not G.isReady() then return false end
    local sites, skipped = {}, {}
    local tiers = {}
    for _, t in ipairs(Fortify.TIERS) do tiers[t] = { h = 0, s = 0 } end
    for _, s in ipairs(plan.sites) do
        local tier = tiers[s.tier]
        if tier ~= nil then tier.h, tier.s = tier.h + math.min(s.have, s.steps), tier.s + s.steps end
        if not s.done and Fortify.OFF_KINDS[s.kind] then
            local open = false
            if s.kind == "barricade" and s.opening == "door" then   -- porte ouverte : refusée en jeu (« door open »)
                local o = Fortify.openingOf(s)
                open = o ~= nil and o:IsOpen() == true
            end
            if open then
                skipped[#skipped + 1] = s.id
            else
                sites[#sites + 1] = { id = s.id, k = s.kind, t = s.tier, x = s.x, y = s.y, z = s.z, n = s.north == true,
                    o = s.opp == true, s = s.steps, h = s.have }
            end
        end
    end
    local names = {}
    for name in pairs(tools or {}) do names[#names + 1] = name end
    table.sort(names)
    local toolSet, toolText = {}, {}
    for _, name in ipairs(names) do
        toolSet[name] = tools[name] == true
        toolText[#toolText + 1] = name .. "=" .. tostring(tools[name] == true)
    end
    -- LK13-T07 : clé gardée au registre = empreinte du texte (mémoire : empreinte recalculée seulement s'il change).
    local text = plan.key .. "|" .. table.concat(toolText, ",") .. "|" .. table.concat(skipped, ",")
    local keys = Fortify.state.keys
    if keys == nil then
        keys = {}
        Fortify.state.keys = keys
    end
    local memo = keys[gid]
    if memo == nil or memo.text ~= text then
        memo = { text = text, key = Fortify.digest(text) }
        keys[gid] = memo
    end
    local key = memo.key
    local written = G.update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" then return false, false end
        local f = readView(gid, live.fort, live.home)   -- LK13-T11 : lecture seule ici (relevé inchangé : même vue)
        local n = 0
        if f ~= nil then
            if #f.pend.ops > 0 or #f.boxes > 0 then return false, false end   -- application d'abord
            if f.key == key and live.fort.v == Fortify.FORT_FORMAT then return false, false end
            n = f.pend.n
        elseif live.fort ~= nil then
            log().warn("fortify: group %s offscreen survey malformed or for another home: replaced", gid)
        end
        local h = live.home
        live.fort = packFort({ hx = h.x, hy = h.y, hz = h.z, key = key, day = G.today(), tools = toolSet,
            tiers = tiers, sites = sites, work = 0, boxes = {}, pend = { n = n, ops = {} } })
        return true, true
    end)
    if written == true then
        Fortify.stats.snapshots = Fortify.stats.snapshots + 1
        log().debug("fortify: group %s offscreen survey kept: %d site(s) to do, level %d", gid, #sites, plan.level)
        return true
    end
    return false
end

local function markOf(o)
    if o == nil or not o:hasModData() then return nil end
    return o:getModData()[Fortify.OP_TAG]
end

-- Pose un écart de barricade op (marque mark) : rend l'issue ("placed", "already", "adopted", "dropped", "kept"),
-- l'objet marqué et le nombre de planches posées.
local function applyBarricade(gid, op, mark)
    local site = { id = op.id, x = op.x, y = op.y, z = op.z, north = op.n, opp = op.o, steps = op.b }
    local o, sq = Fortify.openingOf(site)
    if sq == nil then return "kept" end
    if o == nil then return "dropped", nil, 0, "opening gone" end
    -- Marque sur l'ouverture, pas sur la barricade : IsoBarricade.save n'écrit pas la ModData (J/iso/objects/
    -- IsoBarricade.java:621-632, sans IsoObject.save) ; IsoWindow, IsoDoor et IsoThumpable la sauvegardent.
    if markOf(o) == mark then return "adopted", o, 0 end
    local plan = Fortify.plan(gid)
    local e = plan ~= nil and plan.entry or nil
    if e ~= nil and e.x == op.x and e.y == op.y and e.z == op.z and e.north == op.n then
        return "dropped", nil, 0, "home entry"
    end
    if Fortify.openingKind(o) == "door" and o:IsOpen() then return "dropped", nil, 0, "door open" end
    local addOpp, have = sideFor(o, site)
    if addOpp == nil then return "dropped", nil, 0, have end
    if have >= op.b then return "already" end
    local k = math.min(op.b - have, op.b - op.a)
    local b = Fortify.addPlanks(o, addOpp, k)
    if b == nil then return "dropped", nil, 0, "barricade not added" end
    o:getModData()[Fortify.OP_TAG] = mark
    return "placed", o, k
end

-- Pose un écart de mur ou de palissade op (marque mark), étape par étape par Fortify.placeStructure, comme
-- Fortify.buildStep sans prise de matériaux. Mêmes issues qu'applyBarricade.
local function applyRing(op, mark)
    local cell = getCell()
    local north = op.n == true
    local sq = cell ~= nil and cell:getGridSquare(op.x, op.y, op.z) or nil
    local ox, oy = op.x, op.y - 1
    if not north then ox, oy = op.x - 1, op.y end
    local other = sq ~= nil and cell:getGridSquare(ox, oy, op.z) or nil
    if sq == nil or other == nil then return "kept" end
    local kind, cur, obj = builtOn(sq, north)
    cur = cur or 0
    if kind ~= nil and kind ~= op.k then return "dropped", nil, 0, "other structure (" .. kind .. ")" end
    if markOf(obj) == mark then return "adopted", obj, 0 end
    if cur >= op.b then return "already" end
    if cur < op.a then return "dropped", nil, 0, "earlier stage missing" end
    local stages = Fortify.STAGES[op.k]
    local placed, last = 0, nil
    for n = cur + 1, op.b do
        local stage = stages[n]
        local prev
        if stage.prev ~= nil then
            prev = structureOn(sq, north, stage.prev)
            if prev == nil then return placed > 0 and "placed" or "dropped", last, placed, "no " .. stage.prev end
        elseif not groundOk(sq) or other:getBuildingDef() ~= nil or other:isWaterSquare() then
            return "dropped", nil, 0, "ground"
        elseif sq:isBlockedTo(other) then
            return "dropped", nil, 0, "edge closed"
        end
        local info, sprite = Fortify.entityInfo(stage.entity, north)
        if info == nil then return placed > 0 and "placed" or "dropped", last, placed, sprite end
        last = Fortify.placeStructure(sq, north, info, sprite, prev)
        placed = placed + 1
    end
    if last ~= nil then last:getModData()[Fortify.OP_TAG] = mark end
    return "placed", last, placed
end

-- Ouvre une boîte de clous entamée hors écran (entrée b = { i, u }) comme OpenBox100 : BOX_NAILS - u clous marqués
-- ajoutés au conteneur de la boîte (envoyés aux clients proches sur un serveur), boîte retirée par Stock.takeItem.
-- Boîte absente : clous déjà créés (marque) = repris, sinon boîte partie (rien). Rend l'issue.
local function openUsedBox(gid, b)
    local St = Stock()
    local mark = gid .. ":box:" .. tostring(b.i)
    if St.homeContainers == nil or St.homeContainers(gid) == nil then return "kept" end   -- conteneurs illisibles
    local f, box, ctr = St.findItem(gid, function(it) return it:getID() == b.i end)
    if f == nil then
        if St.findItem(gid, function(it) return markOf(it) == mark end) ~= nil then return "adopted" end
        log().warn("fortify: group %s: used box of nails %s gone before it was opened", gid, tostring(b.i))
        return "dropped"
    end
    local n = cfg().BOX_NAILS - b.u
    if n > 0 then
        local list = ctr:AddItems(Fortify.NAILS, n)
        if list ~= nil then
            for j = 0, list:size() - 1 do list:get(j):getModData()[Fortify.OP_TAG] = mark end
            if isServer() then sendAddItemsToContainer(ctr, list) end
        end
    end
    local id = box:getID()
    local got, why = St.takeItem(gid, function(it) return it:getID() == id end, "offscreen", "fortify box")
    if got == nil then log().warn("fortify: group %s: used box of nails %s not removed: %s", gid, tostring(id), tostring(why)) end
    Fortify.stats.boxesOpened = Fortify.stats.boxesOpened + 1
    return "placed"
end

-- Efface les marques d'application des clous créés pour le groupe gid (conteneurs du foyer).
local function clearNailMarks(gid)
    local St = Stock()
    local list = St.homeContainers ~= nil and St.homeContainers(gid) or nil
    if list == nil then return end
    local prefix = gid .. ":box:"
    for _, ct in ipairs(list) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            local mk = markOf(it)
            if type(mk) == "string" and string.sub(mk, 1, #prefix) == prefix then it:getModData()[Fortify.OP_TAG] = nil end
        end
    end
end

-- Pose le travail fait hors écran du groupe gid (zone du foyer chargée) : écarts de pose puis boîtes entamées, en
-- une écriture du registre (écarts traités ôtés), marques effacées après elle. Rend { placed, already, adopted,
-- dropped, kept, steps, boxes }, ou nil et une raison.
function Fortify.applyPending(gid)
    settle(gid)   -- LK13-T11
    local g = liveGroup(gid)
    local f = g ~= nil and readView(gid, g.fort, g.home) or nil
    if f == nil then return nil, "no offscreen survey" end
    if #f.pend.ops == 0 and #f.boxes == 0 then return nil, "nothing pending" end
    local survey, why = Fortify.survey(gid)   -- toute la zone du pourtour chargée
    if survey == nil then return nil, why end
    local rep = { placed = 0, already = 0, adopted = 0, dropped = 0, kept = 0, steps = 0, boxes = 0 }
    local ops, boxes = {}, {}
    for _, op in ipairs(f.pend.ops) do ops[#ops + 1] = op end
    for _, b in ipairs(f.boxes) do boxes[#boxes + 1] = { i = b.i, u = b.u } end
    local done, marked, doneBox = {}, {}, {}
    for _, op in ipairs(ops) do
        local mark = gid .. ":" .. op.u
        local ok, res, obj, n, reason
        if op.k == "barricade" then
            ok, res, obj, n, reason = pcall(applyBarricade, gid, op, mark)
        else
            ok, res, obj, n, reason = pcall(applyRing, op, mark)
        end
        if not ok then
            rep.kept = rep.kept + 1
            log().error("fortify: group %s offscreen change %s (%s) not placed: %s (kept)", gid, tostring(op.u), op.id,
                tostring(res))
        elseif res == "kept" then
            rep.kept = rep.kept + 1
        else
            done[op.u] = true
            rep[res] = rep[res] + 1
            rep.steps = rep.steps + (n or 0)
            if obj ~= nil then marked[#marked + 1] = obj end
            if res == "dropped" then
                log().warn("fortify: group %s offscreen change %s (%s, %d -> %d) dropped: %s", gid, tostring(op.u),
                    op.id, op.a, op.b, tostring(reason))
            end
        end
    end
    for _, b in ipairs(boxes) do
        local ok, res = pcall(openUsedBox, gid, b)
        if not ok then
            rep.kept = rep.kept + 1
            log().error("fortify: group %s used box of nails %s not opened: %s (kept)", gid, tostring(b.i), tostring(res))
        elseif res == "kept" then
            rep.kept = rep.kept + 1
        else
            doneBox[b.i] = true
            if res == "placed" then rep.boxes = rep.boxes + 1 end
        end
    end
    local written = Groups().update(function(data)
        local live = data.groups[gid]
        local lf = live ~= nil and fortView(live.fort, live.home) or nil
        if lf == nil then return false, false end
        local kept = {}
        for _, op in ipairs(lf.pend.ops) do
            if not done[op.u] then kept[#kept + 1] = op end
        end
        lf.pend.ops = kept
        local keptBoxes = {}
        for _, b in ipairs(lf.boxes) do
            if not doneBox[b.i] then keptBoxes[#keptBoxes + 1] = b end
        end
        lf.boxes = keptBoxes
        live.fort = packFort(lf)   -- LK13-T07 : forme compacte (ancienne forme réécrite)
        return true, true
    end)
    if written == true and not Groups().flush() then written = false end   -- LK13-T06 : écrit avant d'ôter les marques
    if written == true then
        for _, o in ipairs(marked) do o:getModData()[Fortify.OP_TAG] = nil end
        if rep.boxes > 0 or #boxes > 0 then clearNailMarks(gid) end
    else
        log().warn("fortify: group %s offscreen work placed but the registry was not written (marks kept)", gid)
    end
    if rep.boxes > 0 then Stock().check(gid, { force = true }) end   -- clous ajoutés acceptés dans la référence
    Fortify.invalidate(gid)
    Fortify.stats.applied = Fortify.stats.applied + 1
    for _, k in ipairs({ "placed", "already", "adopted", "dropped", "kept" }) do
        Fortify.stats[k] = Fortify.stats[k] + rep[k]
    end
    log().info("fortify: group %s offscreen work placed: %d change(s) placed (%d step(s)), %d already there, "
        .. "%d resumed, %d dropped, %d kept, %d box(es) of nails opened", gid, rep.placed, rep.steps, rep.already,
        rep.adopted, rep.dropped, rep.kept, rep.boxes)
    return rep
end

-- Relevé de la minute étalé (LK13-T11, fiche fortification.md « Relevé de la minute étalé ») : le relevé d'un plan
-- expiré (Fortify.feasible : relevé du monde, plan, faisabilité, relevé hors écran) coûte quelques ms par groupe ;
-- tous les plans relevés dans la même image expirent ensemble (PLAN_MS), d'où des pointes de 10 à 23 ms lupa à
-- des minutes isolées (5 groupes). À la minute, les groupes dont le plan a expiré rejoignent une file, sans doublon,
-- avec l'heure de la minute ; un groupe relevé à la fois (OnTick), à partir de l'image qui suit la minute (marque
-- « fresh » effacée au début de l'image suivante, comme la relecture du stock). Même résultat que le relevé dans
-- l'image de la minute :
--   - le relevé est fait avec l'heure de la minute (Fortify.clockAt) : plan.ms et l'expiration suivante inchangés ;
--   - tout ce qui lit ou change le plan, le relevé hors écran ou l'ouvrage d'un groupe encore en file (Fortify.plan,
--     donc feasible, siteFor, levelOf, hasWork, pose d'une planche ou d'un ouvrage ; invalidate ; applyPending ;
--     offscreenHour quand l'heure hors écran peut travailler) fait d'abord son relevé (settle) ;
--   - abonné OnTick inscrit avant celui de la relecture du stock (ordre des fichiers, et ordre des clés pendant une
--     mesure) ; la relecture du stock d'un groupe encore en file attend la fin de son relevé (Fortify.isQueued,
--     LK_Stock) : un groupe est relevé avant que son stock soit relu.
-- Suite (2026-10-15) : chaque relevé en trois images (runJob plus bas), une étape par image.
-- Écriture du registre des groupes retenue pendant la file (Groups.hold("fortify")) puis faite dans une image à elle ;
-- file vidée avant la sauvegarde du monde (OnSave).
Fortify.minuteJobs = Fortify.minuteJobs or { list = {}, head = 1, queued = {}, fresh = false, write = false }
Fortify.QUEUE_HOLD_MARGIN = 3   -- images de retenue en plus de celles des relevés en file
Fortify.JOB_FRAMES = 3          -- images d'un relevé en file (une étape chacune)
Fortify.stats.queued = Fortify.stats.queued or 0
Fortify.stats.settled = Fortify.stats.settled or 0   -- relevés en file faits avant leur image (lecture du plan)

-- LK13-T11 (suite) : un relevé en file coûte trois images au plus, une étape chacune (relevé du monde, plan,
-- faisabilité et relevé hors écran : 1,2-1,4 / 2,1 / 1,0-1,5 ms lupa au banc au lieu de 4,4-5 ms dans une image) ;
-- toutes avec l'heure de sa minute. L'entrée reste en file (queued) jusqu'à sa dernière étape : toute lecture du plan
-- d'ici là fait les étapes restantes d'un coup (settle), comme avant.
-- Une étape du relevé en file e ({ gid, ms, ctx }), avec l'heure de sa minute ; all : toutes les étapes restantes.
-- Rend vrai si l'entrée était encore en file.
local function runJob(e, all)
    local q = Fortify.minuteJobs
    if q.queued[e.gid] ~= e then return false end
    local prev = Fortify.clockAt
    Fortify.clockAt = e.ms
    local ok, err = pcall(function()
        if e.ctx == nil then
            local done, ctx = planNeed(e.gid)
            if not done then
                e.ctx = ctx
                planSurvey(ctx)                  -- étape 1 : relevé du monde
                if not all then return end
            end
        end
        if e.ctx ~= nil and not e.ctx.built then
            e.ctx.built = true
            e.ctx.plan, e.ctx.planWhy = planFinish(e.ctx)   -- étape 2 : plan (pur), gardé avec l'heure de la minute
            if not all then return end
        end
        q.queued[e.gid] = nil                    -- étape 3 : faisabilité, relevé hors écran
        if e.ctx ~= nil then   -- plan de l'étape 2 rendu au premier Fortify.plan de feasible (comme un relevé fait là)
            Fortify.givenPlan = { gid = e.gid, plan = e.ctx.plan, why = e.ctx.planWhy }
        end
        Fortify.feasible(e.gid)
    end)
    Fortify.givenPlan = nil
    Fortify.clockAt = prev
    if not ok then
        q.queued[e.gid] = nil
        log().error("fortify: group %s survey failed: %s", e.gid, tostring(err))
    end
    return true
end

settle = function(gid)
    local e = Fortify.minuteJobs.queued[gid]
    if e ~= nil and runJob(e, true) then Fortify.stats.settled = Fortify.stats.settled + 1 end
end

-- Relevé en file du groupe gid fait tout de suite (toutes ses étapes) ; sans effet s'il n'est pas en file
-- (LK_Stock.finishQueue, avant de relire le stock du groupe).
function Fortify.settleQueued(gid)
    settle(gid)
end

-- Vrai si le relevé de la minute du groupe gid est encore en file (LK_Stock : relecture du stock après lui).
function Fortify.isQueued(gid)
    return Fortify.minuteJobs.queued[gid] ~= nil
end

local function enqueue(gid, t)
    local q = Fortify.minuteJobs
    if q.queued[gid] ~= nil then return false end
    if q.head > #q.list then q.list, q.head = {}, 1 end
    local e = { gid = gid, ms = t }
    q.queued[gid] = e
    q.list[#q.list + 1] = e
    Fortify.stats.queued = Fortify.stats.queued + 1
    return true
end

function Fortify.onFrameStart()
    Fortify.minuteJobs.fresh = false
end

-- Une étape d'un relevé de la file (OnTick) ; la file vide, une image pour l'écriture seule. Rend vrai si une étape
-- a été faite.
function Fortify.onFrame()
    local q = Fortify.minuteJobs
    if q.fresh then return false end
    while q.head <= #q.list do
        local e = q.list[q.head]
        if runJob(e, false) then
            if q.queued[e.gid] ~= e then q.head = q.head + 1 end   -- dernière étape faite
            return true
        end
        q.head = q.head + 1   -- relevé déjà fait par settle : suivant dans la même image
    end
    if q.write then
        q.write = false
        q.list, q.head = {}, 1
        local G = Groups()
        G.release("fortify")
        if G.isDirty() and not G.isHeld() then G.flush() end   -- une autre retenue écrira à sa fin
    end
    return false
end

-- File vidée tout de suite (bancs, OnSave). Rend le nombre de relevés faits.
function Fortify.finishQueue()
    local q, n = Fortify.minuteJobs, 0
    q.fresh = false
    while q.head <= #q.list do
        local e = q.list[q.head]
        q.head = q.head + 1
        if runJob(e, true) then n = n + 1 end
    end
    q.list, q.head, q.write = {}, 1, false
    local G = Groups()
    if G ~= nil and G.release ~= nil then G.release("fortify") end
    return n
end

-- Examine les foyers chargés : travail hors écran posé dès que la zone est chargée ; relevé hors écran tenu à jour
-- (plan expiré ou invalidé : Fortify.feasible le relève et l'écrit ; LK13-T11 : à la minute, mis en file et fait dans
-- les images suivantes). reason = "chunk" (au plus une fois par SCAN_MS) ou "minute". Rend le nombre de groupes dont
-- le travail a été posé.
function Fortify.scan(reason)
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local G = Groups()
    if G == nil or not G.isReady() then return 0 end
    local st = Fortify.state
    if st.migratedFor ~= G.state.data then   -- LK13-T07 : une fois par registre chargé
        st.migratedFor = G.state.data
        Fortify.migrate()
    end
    local t = now()
    if reason == "chunk" and st.lastScan ~= nil and t - st.lastScan < cfg().SCAN_MS then return 0 end
    st.lastScan = t
    local cell = getCell()
    if cell == nil then return 0 end
    local ids = G.update(function(data)
        local list = {}
        for gid, g in pairs(data.groups) do
            local home = g.home
            if type(home) == "table" and Homes().validMark(g.furnish, home)
                and cell:getGridSquare(home.x, home.y, home.z) ~= nil then
                list[#list + 1] = gid
            end
        end
        return false, list
    end)
    if type(ids) ~= "table" then return 0 end
    table.sort(ids)
    local n = 0
    for _, gid in ipairs(ids) do
        if Fortify.hasPending(gid) then
            local ok, res, why = pcall(Fortify.applyPending, gid)
            if not ok then
                log().error("fortify: group %s offscreen work not placed: %s", gid, tostring(res))
            elseif type(res) == "table" then
                n = n + 1
            else
                log().debug("fortify: group %s offscreen work waits: %s", gid, tostring(why))
            end
        elseif reason == "minute" and Fortify.minuteJobs.queued[gid] == nil then
            local plan = st.plans[gid]
            if plan == nil or t - plan.ms >= cfg().PLAN_MS then enqueue(gid, t) end   -- LK13-T11
        end
    end
    local q = Fortify.minuteJobs
    if reason == "minute" and q.head <= #q.list then
        q.fresh, q.write = true, true
        G.hold("fortify", Fortify.JOB_FRAMES * (#q.list - q.head + 1) + Fortify.QUEUE_HOLD_MARGIN)
    end
    return n
end

local function onLoadChunk()
    Fortify.scan("chunk")
end

local function onEveryOneMinute()
    Fortify.scan("minute")
end

LivingKnox.subscribe("LoadChunk", "Fortify.onLoadChunk", onLoadChunk)
LivingKnox.subscribe("EveryOneMinute", "Fortify.onEveryOneMinute", onEveryOneMinute)
-- LK13-T11 : file des relevés de la minute (une image chacun), vidée avant la sauvegarde du monde.
LivingKnox.subscribe("OnTickEvenPaused", "Fortify.frameStart", function() Fortify.onFrameStart() end)
LivingKnox.subscribe("OnTick", "Fortify.minuteQueue", function() Fortify.onFrame() end)
LivingKnox.subscribe("OnSave", "Fortify.minuteSave", function() Fortify.finishQueue() end)

-- Oublie les plans en mémoire (suites en jeu, administration).
function Fortify.reset()
    Fortify.state = { plans = {}, rest = {}, claims = {}, needs = {} }
    Fortify.minuteJobs = { list = {}, head = 1, queued = {}, fresh = false, write = false }   -- LK13-T11
    if Groups() ~= nil and Groups().release ~= nil then Groups().release("fortify") end
end
