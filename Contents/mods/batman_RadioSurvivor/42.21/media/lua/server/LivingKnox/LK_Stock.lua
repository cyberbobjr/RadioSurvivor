-- Living Knox : stock réel du groupe dans les conteneurs de son foyer (LK08-T06). Fiche : docs/conception/stock.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Catégories (CATEGORIES) tirées des données de script des objets, jamais de leur nom affiché : eau = récipient
-- (FluidContainer) non vide dont le fluide principal est Fluid.Water ou Fluid.TaintedWater ; sinon d'après
-- DisplayCategory du script (InventoryItem.getDisplayCategory, J/inventory/InventoryItem.java:2873) : Food ->
-- nourriture, FirstAid et Bandage -> soins, Ammo -> munitions, Material et MaterialWeapon (planches) -> matériaux.
-- Tout autre objet est ignoré (ni compté, ni surveillé).
-- Conteneurs du foyer (zone de LK_Homes : RADIUS cases autour du foyer, niveau du foyer) : bâtiment = tous les
--   conteneurs des objets des cases du bâtiment du foyer (frigo, placards, caisse posée...) ; camp = conteneurs des
--   objets posés par LK_Homes pour le groupe (tentes, ModData LKHome). Seuls les objets au premier niveau d'un
--   conteneur comptent (pas le contenu d'un sac rangé dedans).
-- Inventaire de référence privé (registre des groupes, champ facultatif stock, schéma 1 inchangé, contrôlé ici) :
--   stock = { v = FORMAT, hx, hy, hz, fill = "filling" | "done", day, items = { { i = id, t = type complet,
--             c = catégorie, k = clé du conteneur }, ... } } (MAX_ITEMS au plus).
--   Identité d'un objet = InventoryItem.getID(), tirée au hasard à la création et sauvegardée avec l'objet
--   (J/inventory/InventoryItemFactory.java:126, InventoryItem.java:1521, 1740) ; un transfert MP déplace le même
--   objet (J/core/Transaction.java:258-262 : Remove puis addItem). Clé d'un conteneur = "x,y,z,type,n" (n = rang
--   parmi les conteneurs du même type sur la case).
-- Remplissage initial, une seule fois par foyer : après l'aménagement (marque LK_Homes valide), les objets du kit du
--   type de groupe (KITS, objets vanilla, quantités modestes, sans périssable) sont créés (instanceItem), marqués
--   (ModData LKStock = groupe), bouteilles d'eau vidées puis remplies d'eau (FluidContainer.Empty puis addFluid,
--   base api-42-21.md), rangés tour à tour dans les conteneurs posés par LK_Homes (caisse ou tentes), marqués
--   explorés avant (un conteneur non exploré recevrait le butin vanilla en plus : base world-placement.md) et
--   envoyés aux clients par sendAddItemToContainer sur un serveur. Sans conteneur posé (foyer « skip » des suites) :
--   rien n'est créé. Marque écrite AVANT la création (fill = "filling") : un arrêt en plein remplissage ou une
--   marque « filling » relue au redémarrage ne fait jamais recréer. Garde si le registre recule (fichier plus ancien
--   que le monde) : un objet marqué LKStock du groupe déjà présent dans un conteneur du foyer rétablit la référence
--   sans rien créer.
-- Relecture (Stock.check) : chaque fois que la zone du foyer est chargée (LoadChunk au plus une fois par SCAN_MS,
--   chaque minute de jeu ; au plus une relecture par groupe toutes les CHECK_MS) et seulement si toutes les cases de
--   la zone sont lisibles (LK_Homes.ready, puis chaque case : un conteneur d'une case non chargée paraîtrait vidé).
--   La référence devient le contenu réel. Différence avec l'ancienne référence :
--   - objet ajouté (joueur qui dépose, butin vanilla d'un conteneur ouvert plus tard) : accepté ;
--   - objet déplacé d'un conteneur du foyer à un autre : accepté ;
--   - objet disparu : cherché par son identifiant dans l'inventaire de chaque joueur connecté (sacs compris,
--     ItemContainer.getItemWithIDRecursiv, J/inventory/ItemContainer.java:2909) : trouvé = vol attribuable à ce
--     joueur, rapporté à LK_Hostility (fait "theft", attributable) une fois par joueur et par relecture, et au plus
--     une fois par THEFT_COOLDOWN_HOURS par groupe et par joueur ; introuvable (objet mangé, posé au sol, donné) :
--     perte journalisée sans coupable.
--   Choix documenté : aucun événement serveur fiable ne signale un transfert d'objet (en MP, transaction Java sans
--   Lua côté serveur : base combat-and-xp.md, « Transferts d'objets en MP ») ; la différence à la relecture, avec
--   l'identifiant de l'objet retrouvé dans l'inventaire du joueur, est la seule preuve côté serveur.
-- Les prélèvements du groupe lui-même (repas, dons, troc : LK05-T07, LK11-T06, LK11-T08) passent par ce module pour
-- mettre la référence à jour dans le même pas ; la mise à jour des conteneurs réels d'après la référence (simulation
-- hors écran) est LK09-T06.
-- Repas réels (LK05-T07, fiche docs/conception/besoins.md, « Repas réels ») : Stock.findMeal cherche le premier objet
--   consommable (Stock.consumable : nourriture ni pourrie, ni gelée, ni crue dangereuse ; eau = récipient dont le fluide
--   principal est Fluid.Water, eau croupie écartée) dans l'ordre des conteneurs du foyer ; Stock.takeMeal retire UN
--   objet d'un conteneur relu au moment de la prise (DoRemoveItem, une seule surcharge ; sendRemoveItemFromContainer
--   sur un serveur : clients proches, J/network/GameServer.java:2269-2277) et l'ôte de la référence dans la même
--   écriture du registre : la relecture suivante ne le voit ni perdu ni volé. Rien n'est jamais créé. Aucun objet
--   consommable : Stock.reportShortage écrit au journal du groupe (kind « shortage », au plus une fois par
--   SHORTAGE_HOURS et par catégorie) ; le rationnement et les besoins du groupe suivent la référence (LK08-T07).
--
-- Seuils, rationnement et besoins du groupe (LK08-T07, fiche docs/conception/stock.md, section « Seuils ») :
--   - réserve visée par catégorie selon le nombre de membres vivants n (SUPPLY) : nourriture et eau = DAILY x n x
--     TARGET_DAYS (portions abstraites : un objet = une portion de la journée d'un membre), soins, munitions,
--     matériaux = PER_MEMBER x n (arrondi au-dessus) ; niveau 0..100 = réserve / visée ;
--   - jours d'autonomie = objets / (DAILY x n) pour la nourriture et l'eau, au dixième inférieur ; autonomie du
--     groupe = la plus basse des deux ;
--   - rationnement (champ facultatif stock.ration 0..3, jamais une raison d'écarter la référence) : normal, réduit
--     (autonomie < RATION_DAYS[1]), strict (< RATION_DAYS[2]), épuisé (nourriture ou eau à zéro) ; on durcit
--     aussitôt, on ne revient à un niveau plus doux qu'avec RATION_MARGIN jour(s) d'avance ; changement relu à
--     chaque Stock.check, écrit au journal du groupe (kind « ration ») et au journal du moteur ;
--   - besoins = catégories sous leur visée, ordre fixe et reproductible : épuisé, critique (niveau < CRITICAL), bas,
--     puis niveau croissant, puis ordre de CATEGORIES. Stock.needs(gid) (copie) ; Stock.assessGroup(g) pour le
--     cadre de décision (LK_Decisions.groupInput lit les niveaux à chaque notation horaire).
--   Points d'appel des consommateurs à venir : expéditions (LK05-T05) et missions RadioSurvivor = Stock.needs(gid)
--   .needs (premier = ce qui manque le plus) ; fortification (LK14) = entrée « materials » ; repas réels (LK05-T07) et
--   stock hors écran (LK09-T06) = Stock.portion(gid) (part d'une ration normale).
--
-- Stock hors écran (LK09-T06, fiche docs/conception/stock.md, section « Hors écran ») :
--   - pendant la simulation (LK_Simulation.advance, dans son écriture du registre, logique pure sans accès au monde) :
--     repas abstrait quotidien à l'heure du jour OFFSCREEN.MEAL_HOUR (Stock.offscreenHour : membres vivants au foyer,
--     hors expédition et hors membres incarnés, DAILY x part de ration Stock.portion, arrondi au plus proche) et
--     butin d'une expédition abstraite LK09-T02 (Stock.offscreenLoot : un objet par OFFSCREEN.LEVEL_PER_ITEM points
--     de réserve gagnés, types vanilla OFFSCREEN.ITEMS) modifient l'inventaire de référence ; l'écart avec les
--     conteneurs réels est gardé dans le journal d'écarts en attente stock.pend = { n = dernier numéro d'écart,
--     ops = { { u = numéro, o = "take", i, t, c, k } | { u = numéro, o = "add", t, c } } } (borné : PEND_MAX ; un
--     objet pris quitte items, un objet ajouté n'a pas encore d'identifiant). Une prise annule d'abord un ajout en
--     attente de la même catégorie. Les totaux (Stock.count, besoins, rationnement) comptent les ajouts en attente.
--   - à l'arrivée d'un joueur (Stock.check, dès que toute la zone du foyer est lisible, avant la différence ; et avant
--     toute prise du groupe dans les conteneurs) : Stock.applyPending retire les objets pris (DoRemoveItem,
--     sendRemoveItemFromContainer) et crée les objets ajoutés (instanceItem, objets « Base. » seulement, dans le
--     conteneur posé par LK_Homes sinon le premier, sendAddItemToContainer), puis ôte du journal les seuls écarts
--     traités (par numéro) et ajoute les objets créés à la référence, en une écriture. Marque d'application
--     idempotente : chaque objet créé porte ModData LKStockOp = "<groupe>:<numéro>" jusqu'à cette écriture ; si elle
--     n'a pas eu lieu (erreur, arrêt), l'objet marqué est repris au lieu d'être recréé ; un objet pris déjà absent
--     n'est pas recherché ailleurs. Un écart ajouté pendant l'application reste en attente.
--   - fortification hors écran (LK14-T05, LK_Fortify) : Stock.offscreenCount / Stock.offscreenTake prennent des
--     matériaux par type complet dans la référence (écarts « take » du même journal, appliqués de la même façon).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"
require "LivingKnox/LK_Hostility"

local Stock = LivingKnox.Stock or {}
LivingKnox.Stock = Stock

Stock.FORMAT = 1
Stock.TAG = "LKStock"
Stock.CATEGORIES = { "food", "water", "medical", "ammo", "materials" }
Stock.MAX_ITEMS = 128
Stock.TYPE_MAX = 128
Stock.KEY_MAX = 96
Stock.OP_TAG = "LKStockOp"              -- LK09-T06 : marque d'application d'un objet créé d'après le journal d'écarts
Stock.PEND_MAX = 2 * Stock.MAX_ITEMS    -- LK09-T06 : écarts en attente au plus (prises <= MAX_ITEMS, ajouts aussi)

-- LK09-T06 : stock hors écran (valeurs de départ propres au mod, à recalibrer en jeu).
Stock.OFFSCREEN = Stock.OFFSCREEN or {
    MEAL_HOUR = 18,         -- heure du jour du repas abstrait quotidien (une fois par jour simulé)
    LEVEL_PER_ITEM = 5,     -- points de réserve abstraite gagnés (LK09-T02) par objet rapporté
    -- Objets vanilla 42.21 du butin abstrait (pris tour à tour d'après le numéro d'écart), sans périssable.
    ITEMS = {
        food = { "Base.TinnedBeans", "Base.CannedCorn", "Base.TinnedSoup" },
        water = { "Base.WaterBottle" },
        medical = { "Base.Bandage", "Base.Pills" },
        ammo = { "Base.Bullets9mmBox", "Base.ShotgunShellsBox" },
        materials = { "Base.NailsBox", "Base.DuctTape" },
    },
}

-- DisplayCategory du script -> catégorie (l'eau se reconnaît à son fluide, avant).
Stock.DISPLAY = {
    Food = "food",
    FirstAid = "medical",
    Bandage = "medical",
    Ammo = "ammo",
    Material = "materials",
    MaterialWeapon = "materials",
}

-- Kits du remplissage initial par type de groupe (objets vanilla 42.21, media/scripts/generated/items : conserves
-- et biscuits sans DaysFresh, bouteilles d'eau remplies, soins, munitions, matériaux) ; un type sans kit reçoit
-- DEFAULT_KIT. Entrée : { type complet, nombre, fill = nom du fluide facultatif }.
Stock.DEFAULT_KIT = "settlers"
Stock.KITS = Stock.KITS or {
    settlers = {
        { "Base.TinnedBeans", 2 }, { "Base.CannedCorn", 2 }, { "Base.TinnedSoup", 2 },
        { "Base.WaterBottle", 3, fill = "Water" },
        { "Base.Bandage", 3 }, { "Base.Pills", 1 }, { "Base.Disinfectant", 1 },
        { "Base.Bullets9mmBox", 1 },
        { "Base.NailsBox", 1 }, { "Base.Rope", 1 }, { "Base.DuctTape", 1 },
    },
    raiders = {
        { "Base.TinnedBeans", 2 }, { "Base.CannedChili", 2 },
        { "Base.WaterBottle", 2, fill = "Water" },
        { "Base.Bandage", 2 }, { "Base.AlcoholWipes", 1 },
        { "Base.Bullets9mmBox", 1 }, { "Base.ShotgunShellsBox", 2 },
        { "Base.ScrapMetal", 2 }, { "Base.DuctTape", 1 },
    },
    neutrals = {
        { "Base.CannedPeas", 2 }, { "Base.TinnedSoup", 2 }, { "Base.Crackers", 1 },
        { "Base.WaterBottle", 3, fill = "Water" },
        { "Base.Bandage", 2 }, { "Base.Pills", 1 },
        { "Base.ShotgunShellsBox", 1 },
        { "Base.NailsBox", 1 }, { "Base.Rope", 1 },
    },
}

Stock.CFG = Stock.CFG or {
    SCAN_MS = 1000,               -- examen depuis LoadChunk au plus une fois par seconde
    CHECK_MS = 2000,              -- relecture d'un même groupe au plus toutes les 2 s (temps réel)
    THEFT_COOLDOWN_HOURS = 1,     -- un vol rapporté au plus une fois par heure de jeu, par groupe et par joueur
    SHORTAGE_HOURS = 6,           -- LK05-T07 : pénurie au journal au plus une fois par 6 h de jeu, groupe, catégorie
}

-- LK08-T07 : seuils, autonomie et rationnement (valeurs de départ propres au mod, à recalibrer en jeu).
Stock.SUPPLY = Stock.SUPPLY or {
    DAILY = { food = 1, water = 1 },                       -- portions par membre vivant et par jour
    TARGET_DAYS = 3,                                       -- réserve visée des consommables, en jours
    PER_MEMBER = { medical = 1, ammo = 0.5, materials = 1 }, -- réserve visée des autres catégories, par membre vivant
    CRITICAL = 25,                                         -- niveau (0..100) sous lequel un besoin est critique
    RATION_DAYS = { 2, 1 },                                -- autonomie sous laquelle : réduit, strict
    RATION_MARGIN = 0.5,                                   -- jours d'avance pour revenir à un niveau plus doux
}
-- Niveaux de rationnement (indice = niveau + 1) et part d'une ration normale.
Stock.RATIONS = { "normal", "reduced", "strict", "out" }
Stock.PORTIONS = { 1, 0.75, 0.5, 0 }
-- Ordre des besoins : statut d'abord.
Stock.STATUS_ORDER = { empty = 1, critical = 2, low = 3 }

Stock.state = Stock.state or { checked = {}, lastScan = nil, lastTheft = {} }
Stock.stats = Stock.stats or { filled = 0, created = 0, checks = 0, thefts = 0, lost = 0 }
Stock.stats.meals = Stock.stats.meals or 0          -- LK05-T07 : objets pris par un membre pour manger ou boire
Stock.stats.shortages = Stock.stats.shortages or 0  -- LK05-T07 : pénuries écrites au journal du groupe
for _, k in ipairs({ "offMeals", "offEaten", "offShort", "offLoot", "applied", "removed", "gone", "made", "adopted" }) do
    Stock.stats[k] = Stock.stats[k] or 0            -- LK09-T06 : stock hors écran et application des écarts
end

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Homes() return LivingKnox.Homes end
local function cfg() return Stock.CFG end
local function now() return getTimestampMs() end

local CATEGORY_SET = {}
for _, c in ipairs(Stock.CATEGORIES) do CATEGORY_SET[c] = true end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function homeKey(home) return home.x .. "," .. home.y .. "," .. home.z end

-- ================================================================ catégories

local function waterFluid(f)
    if f == nil or Fluid == nil then return false end
    return f == Fluid.Water or (Fluid.TaintedWater ~= nil and f == Fluid.TaintedWater)
end

-- Catégorie d'un objet d'inventaire (Stock.CATEGORIES) ou nil.
function Stock.categoryOf(item)
    if item == nil then return nil end
    local fc = item:getFluidContainer()
    if fc ~= nil and not fc:isEmpty() and waterFluid(fc:getPrimaryFluid()) then return "water" end
    local dc = item:getDisplayCategory()
    if dc == nil then return nil end
    return Stock.DISPLAY[dc]
end

-- ================================================================ référence (registre des groupes)

local function validItem(e)
    return type(e) == "table" and isInt(e.i, -2147483648, 2147483647) and type(e.t) == "string" and #e.t > 0
        and #e.t <= Stock.TYPE_MAX and CATEGORY_SET[e.c] == true and type(e.k) == "string" and #e.k > 0
        and #e.k <= Stock.KEY_MAX
end

-- Forme de la référence pour le foyer home. Rend vrai, ou faux et une raison.
function Stock.validRef(s, home)
    if type(s) ~= "table" or s.v ~= Stock.FORMAT then return false, "unknown format" end
    if type(home) ~= "table" or s.hx ~= home.x or s.hy ~= home.y or s.hz ~= home.z then return false, "home moved" end
    if s.fill ~= "filling" and s.fill ~= "done" then return false, "bad fill state" end
    if type(s.items) ~= "table" or #s.items > Stock.MAX_ITEMS then return false, "bad item list" end
    for _, e in ipairs(s.items) do
        if not validItem(e) then return false, "bad item entry" end
    end
    return true
end

local function writeRef(gid, ref)
    return Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil then return false, false end
        live.stock = ref
        return true, true
    end)
end

-- LK09-T06 : journal d'écarts en attente (champ facultatif stock.pend). Invalide = ignoré (jamais une raison
-- d'écarter la référence : le kit serait recréé).
local function validOp(op, n)
    if type(op) ~= "table" or not isInt(op.u, 1, n) then return false end
    if op.o == "take" then return validItem(op) end
    if op.o == "add" then
        return type(op.t) == "string" and #op.t > 0 and #op.t <= Stock.TYPE_MAX and CATEGORY_SET[op.c] == true
    end
    return false
end

function Stock.validPend(p)
    if type(p) ~= "table" or not isInt(p.n, 0, 2147483647) or type(p.ops) ~= "table" or #p.ops > Stock.PEND_MAX then
        return false
    end
    local seen = {}
    for _, op in ipairs(p.ops) do
        if not validOp(op, p.n) or seen[op.u] then return false end
        seen[op.u] = true
    end
    return true
end

-- Journal valide de la référence s (table vivante), ou nil ; create : journal neuf (non attaché) s'il manque ou
-- s'il est invalide (avertissement).
local function pendOf(s, create, gid)
    local p = type(s) == "table" and s.pend or nil
    if p ~= nil and Stock.validPend(p) then return p end
    if p ~= nil and create then
        log().warn("stock: group %s pending stock changes malformed, dropped", tostring(gid))
    end
    if create then return { n = 0, ops = {} } end
    return nil
end

-- Nombre d'écarts en attente de la référence s (0 sans journal valide).
function Stock.pendingCount(s)
    local p = pendOf(s, false)
    return p ~= nil and #p.ops or 0
end

-- Totaux par catégorie d'une liste d'entrées : { food = n, water = n, medical = n, ammo = n, materials = n } ;
-- pend (facultatif, LK09-T06) : les ajouts en attente d'un journal valide comptent aussi.
function Stock.count(items, pend)
    local out = {}
    for _, c in ipairs(Stock.CATEGORIES) do out[c] = 0 end
    for _, e in ipairs(items or {}) do
        if out[e.c] ~= nil then out[e.c] = out[e.c] + 1 end
    end
    if pend ~= nil and Stock.validPend(pend) then
        for _, op in ipairs(pend.ops) do
            if op.o == "add" and out[op.c] ~= nil then out[op.c] = out[op.c] + 1 end
        end
    end
    return out
end

-- Inventaire de référence d'un groupe : copie de { items, totals, day, fill, pending }, ou nil et une raison (totals
-- compte les ajouts en attente, pending = nombre d'écarts en attente, LK09-T06). Serveur seulement (les identifiants
-- d'objets et la composition du stock ne s'envoient pas à un client).
function Stock.reference(gid)
    local g = Groups().get(gid)
    if g == nil then return nil, "unknown group" end
    if type(g.home) ~= "table" or not Stock.validRef(g.stock, g.home) then return nil, "no stock reference" end
    return { items = g.stock.items, totals = Stock.count(g.stock.items, g.stock.pend), day = g.stock.day,
             fill = g.stock.fill, pending = Stock.pendingCount(g.stock) }
end

-- Totaux par catégorie de la référence d'un groupe (LK08-T07), ou nil et une raison.
function Stock.totals(gid)
    local r, why = Stock.reference(gid)
    if r == nil then return nil, why end
    return r.totals
end

-- ================================================================ conteneurs du foyer

local function tagged(o, gid)
    return o ~= nil and o:hasModData() and o:getModData()[Homes().TAG] == gid
end

-- Conteneurs du foyer : liste triée { { key, container, owned, object, x, y, z } } (owned = objet posé par LK_Homes
-- pour le groupe ; x, y, z = case de l'objet), ou nil et la raison si une case de la zone n'est pas lisible.
function Stock.containers(gid, home, style, bid)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local R, z = Homes().CFG.RADIUS, home.z
    local out = {}
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, z)
            if sq == nil then return nil, "home area not loaded" end
            local inBuilding = style == "building" and Homes().buildingId(sq) == bid
            local objs = sq:getObjects()
            local seen = {}
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                local owned = tagged(o, gid)
                if owned or inBuilding then
                    for ci = 0, o:getContainerCount() - 1 do
                        local c = o:getContainerByIndex(ci)
                        if c ~= nil then
                            local ctype = tostring(c:getType())
                            local n = (seen[ctype] or 0) + 1
                            seen[ctype] = n
                            out[#out + 1] = { key = x .. "," .. y .. "," .. z .. "," .. ctype .. "," .. n,
                                              container = c, owned = owned, object = o, x = x, y = y, z = z }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- Objets classés des conteneurs (premier niveau) : liste { { i, t, c, k, item, container } } dans l'ordre des
-- conteneurs puis des objets.
function Stock.read(containers)
    local out = {}
    for _, ct in ipairs(containers) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            local cat = Stock.categoryOf(it)
            if cat ~= nil then
                out[#out + 1] = { i = it:getID(), t = it:getFullType(), c = cat, k = ct.key, item = it,
                                  container = ct.container }
            end
        end
    end
    return out
end

-- ================================================================ remplissage initial

local function kitOf(gtype)
    return Stock.KITS[gtype] or Stock.KITS[Stock.DEFAULT_KIT] or {}
end

local function makeItem(gid, entry)
    local item = instanceItem(entry[1])
    if item == nil then return nil, "unknown item " .. tostring(entry[1]) end
    if entry.fill ~= nil then
        local fc = item:getFluidContainer()
        local fluid = Fluid ~= nil and Fluid[entry.fill] or nil
        if fc == nil or fluid == nil then return nil, "cannot fill " .. tostring(entry[1]) end
        fc:Empty()
        fc:addFluid(fluid, fc:getCapacity())
    end
    item:getModData()[Stock.TAG] = gid
    return item
end

-- Crée le kit du type gtype dans les conteneurs posés par LK_Homes (tour à tour). Rend le nombre d'objets créés et
-- le nombre d'échecs.
function Stock.fill(gid, gtype, containers)
    local targets = {}
    for _, ct in ipairs(containers) do
        if ct.owned then targets[#targets + 1] = ct end
    end
    if #targets == 0 then return 0, 0 end
    for _, ct in ipairs(targets) do
        if not ct.container:isExplored() then ct.container:setExplored(true) end
    end
    local made, failed, slot = 0, 0, 0
    for _, entry in ipairs(kitOf(gtype)) do
        for _ = 1, entry[2] or 1 do
            local ok, item, why = pcall(makeItem, gid, entry)
            if ok and item ~= nil then
                slot = slot % #targets + 1
                local c = targets[slot].container
                c:AddItem(item)
                if isServer() then sendAddItemToContainer(c, item) end
                made = made + 1
            else
                failed = failed + 1
                log().warn("stock: group %s: %s not created: %s", gid, tostring(entry[1]), tostring(ok and why or item))
            end
        end
    end
    return made, failed
end

-- ================================================================ joueurs et vols

local function players()
    local out = {}
    local list = getOnlinePlayers and getOnlinePlayers() or nil
    if list ~= nil and list:size() > 0 then
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        return out
    end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p ~= nil then out[#out + 1] = p end
    end
    return out
end

-- Joueur qui détient l'objet id (inventaire, sacs compris), ou nil.
function Stock.holderOf(id, list)
    for _, p in ipairs(list or players()) do
        local inv = p:getInventory()
        if inv ~= nil and inv:getItemWithIDRecursiv(id) ~= nil then return p end
    end
    return nil
end

local function hourNow()
    local gt = getGameTime and getGameTime()
    local h = gt and gt:getWorldAgeHours() or 0
    if type(h) ~= "number" or h ~= h then return 0 end
    return h
end

-- Rapporte un vol constaté à LK_Hostility. Rend "reported", "cooldown" ou "no key".
local function reportTheft(gid, player, n)
    local H = LivingKnox.Hostility
    local key, why = H.keyOf(player)
    local name = tostring(player:getUsername())
    if key == nil then
        log().warn("stock: group %s: %d item(s) taken by %s, not reported: %s", gid, n, name, tostring(why))
        return "no key"
    end
    local slot = gid .. "|" .. key
    local h = hourNow()
    local last = Stock.state.lastTheft[slot]
    if last ~= nil and h - last < cfg().THEFT_COOLDOWN_HOURS and h >= last then
        log().info("stock: group %s: %d more item(s) taken by %s (theft already reported this hour)", gid, n, name)
        return "cooldown"
    end
    local res, err = H.record(gid, key, "theft", { attributable = true, day = Groups().today() })
    if res == nil then
        log().warn("stock: group %s: theft by %s not recorded: %s", gid, name, tostring(err))
        return "no key"
    end
    Stock.state.lastTheft[slot] = h
    Stock.stats.thefts = Stock.stats.thefts + 1
    log().info("stock: group %s: %d item(s) taken by %s, theft reported (attitude %s)", gid, n, name,
        tostring(res.level))
    return "reported"
end

-- ================================================================ différence et relecture

-- Nouvelle référence bornée : objets déjà suivis d'abord (dans l'ordre réel), puis les nouveaux, MAX_ITEMS au plus.
local function bounded(real, oldIds)
    local out, kept, extra = {}, {}, {}
    for _, e in ipairs(real) do
        if oldIds[e.i] then kept[#kept + 1] = e else extra[#extra + 1] = e end
    end
    local seen = {}
    for _, list in ipairs({ kept, extra }) do
        for _, e in ipairs(list) do
            if #out >= Stock.MAX_ITEMS then break end
            if not seen[e.i] then
                seen[e.i] = true
                out[#out + 1] = { i = e.i, t = e.t, c = e.c, k = e.k }
            end
        end
    end
    return out, #real - #out
end

-- Compare une référence et le contenu réel. Rend { missing = { entrée }, added = n, moved = n }.
function Stock.diff(refItems, real)
    local byId = {}
    for _, e in ipairs(real) do byId[e.i] = e end
    local refIds = {}
    local missing, moved = {}, 0
    for _, e in ipairs(refItems) do
        refIds[e.i] = true
        local r = byId[e.i]
        if r == nil then
            missing[#missing + 1] = e
        elseif r.k ~= e.k then
            moved = moved + 1
        end
    end
    local added = 0
    for _, e in ipairs(real) do
        if not refIds[e.i] then added = added + 1 end
    end
    return { missing = missing, added = added, moved = moved }
end

local function sameItems(a, b)
    if #a ~= #b then return false end
    for n = 1, #a do
        local x, y = a[n], b[n]
        if x.i ~= y.i or x.t ~= y.t or x.c ~= y.c or x.k ~= y.k then return false end
    end
    return true
end

local function anyTagged(real, gid)
    for _, e in ipairs(real) do
        local it = e.item
        if it ~= nil and it:hasModData() and it:getModData()[Stock.TAG] == gid then return true end
    end
    return false
end

-- Relit le stock d'un groupe (remplissage initial la première fois). opts.force : sans attendre CHECK_MS.
-- Rend un rapport { action = "filled" | "restored" | "checked", items, totals, missing, added, moved,
-- thefts = { { player, items, result } }, lost, ration (niveau après relecture, LK08-T07, ou nil) }, ou nil et la
-- raison.
function Stock.check(gid, opts)
    opts = opts or {}
    -- LK13-T08 : contrôles d'entrée sur la lecture en place (seule, sans copie : appelé à chaque minute de jeu) ;
    -- copie du groupe seulement pour une relecture effective (zone chargée, conteneurs trouvés).
    local view = Groups().peek(gid)
    if view == nil or type(view.home) ~= "table" then return nil, "no group or no home" end
    if not Homes().validMark(view.furnish, view.home) then return nil, "home not furnished yet" end
    local t = now()
    local st = Stock.state
    if not opts.force and st.checked[gid] ~= nil and t - st.checked[gid] < cfg().CHECK_MS then
        return nil, "checked recently"
    end
    st.checked[gid] = t
    local style, def = Homes().ready(view.home)
    if style == nil then return nil, def end
    local bid = def ~= nil and def:getIDString() or nil
    local containers, why = Stock.containers(gid, view.home, style, bid)
    if containers == nil then return nil, why end
    local g = Groups().get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no group or no home" end
    local home = g.home
    Stock.stats.checks = Stock.stats.checks + 1
    local real = Stock.read(containers)
    local ref = g.stock
    local hk = homeKey(home)
    local report = { missing = 0, added = 0, moved = 0, thefts = {}, lost = 0 }

    if not Stock.validRef(ref, home) then
        if ref ~= nil then log().warn("stock: group %s stock reference replaced (home moved or bad reference)", gid) end
        local mark = { v = Stock.FORMAT, hx = home.x, hy = home.y, hz = home.z, fill = "filling",
                       day = Groups().today(), items = {} }
        if anyTagged(real, gid) then
            mark.fill = "done"
            report.action = "restored"
            log().warn("stock: group %s home %s already holds the group's stock but no reference: reference restored,"
                .. " nothing created", gid, hk)
        else
            if not writeRef(gid, mark) or not Groups().flush() then   -- LK13-T06 : marque écrite avant le monde
                log().warn("stock: group %s home %s: stock mark not written, nothing created", gid, hk)
                return nil, "mark not written"
            end
            local made, failed = Stock.fill(gid, g.type, containers)
            mark.fill = "done"
            report.action = "filled"
            Stock.stats.filled = Stock.stats.filled + 1
            Stock.stats.created = Stock.stats.created + made
            real = Stock.read(containers)
            log().info("stock: group %s home %s: %d item(s) stored (%s kit)%s", gid, hk, made,
                Stock.KITS[g.type] and g.type or Stock.DEFAULT_KIT, failed > 0 and (", " .. failed .. " failed") or "")
        end
        local items, over = bounded(real, {})
        mark.items = items
        if over > 0 then log().info("stock: group %s: %d item(s) beyond the tracked limit", gid, over) end
        writeRef(gid, mark)
        report.items, report.totals = items, Stock.count(items)
        report.ration = Stock.updateRation(gid)
        return report
    end

    if ref.fill == "filling" then
        log().warn("stock: group %s home %s was left half filled (interrupted); not filled again", gid, hk)
    end
    -- LK09-T06 : écarts de la vie hors écran appliqués aux conteneurs réels avant la différence.
    if Stock.pendingCount(ref) > 0 then
        report.applied = Stock.applyPending(gid, containers, g)
        g = Groups().get(gid)
        ref = g ~= nil and g.stock or nil
        if g == nil or not Stock.validRef(ref, home) then return nil, "reference lost while applying" end
        real = Stock.read(containers)
    end
    local d = Stock.diff(ref.items, real)
    report.missing, report.added, report.moved = #d.missing, d.added, d.moved
    if #d.missing > 0 then
        local list = players()
        local byPlayer, order = {}, {}
        for _, e in ipairs(d.missing) do
            local p = Stock.holderOf(e.i, list)
            if p ~= nil then
                if byPlayer[p] == nil then
                    byPlayer[p] = 0
                    order[#order + 1] = p
                end
                byPlayer[p] = byPlayer[p] + 1
            else
                report.lost = report.lost + 1
            end
        end
        for _, p in ipairs(order) do
            local res = reportTheft(gid, p, byPlayer[p])
            report.thefts[#report.thefts + 1] = { player = tostring(p:getUsername()), items = byPlayer[p], result = res }
        end
        if report.lost > 0 then
            Stock.stats.lost = Stock.stats.lost + report.lost
            log().info("stock: group %s: %d item(s) gone without a known taker", gid, report.lost)
        end
    end
    local oldIds = {}
    for _, e in ipairs(ref.items) do oldIds[e.i] = true end
    local items = bounded(real, oldIds)
    report.action = "checked"
    report.items, report.totals = items, Stock.count(items, ref.pend)
    if not sameItems(items, ref.items) or ref.fill ~= "done" then
        writeRef(gid, { v = Stock.FORMAT, hx = home.x, hy = home.y, hz = home.z, fill = "done", day = Groups().today(),
                        items = items, ration = ref.ration, pend = ref.pend })
        if d.added > 0 or d.moved > 0 then
            log().debug("stock: group %s: %d item(s) added, %d moved", gid, d.added, d.moved)
        end
    end
    report.ration = Stock.updateRation(gid)   -- LK08-T07 : membres ou stock changés
    return report
end

-- ================================================================ seuils, rationnement, besoins (LK08-T07)

local function tenths(v) return math.floor(v * 10 + 1e-9) / 10 end

local function rationOf(s)
    local r = type(s) == "table" and s.ration or nil
    if isInt(r, 0, #Stock.RATIONS - 1) then return r end
    return 0
end

-- Membres vivants d'un groupe (registre).
function Stock.livingMembers(g)
    local n = 0
    for _, m in pairs(type(g) == "table" and type(g.members) == "table" and g.members or {}) do
        if type(m) == "table" and m.alive then n = n + 1 end
    end
    return n
end

-- Évaluation pure des réserves : totals = { [catégorie] = objets }, members = membres vivants (>= 1). Rend
-- { members, have, want, levels (0..100), days = { food, water }, autonomy, needs = { { c, have, want, missing,
-- level, status }, ... } } (besoins dans l'ordre de STATUS_ORDER, niveau, CATEGORIES), ou nil.
function Stock.assess(totals, members)
    if type(totals) ~= "table" or not isInt(members, 1, 100000) then return nil end
    local S = Stock.SUPPLY
    local out = { members = members, have = {}, want = {}, levels = {}, days = {}, needs = {} }
    local rank = {}
    local autonomy
    for i, c in ipairs(Stock.CATEGORIES) do
        rank[c] = i
        local have = totals[c]
        if not isInt(have, 0, 1000000) then have = 0 end
        local daily = S.DAILY[c]
        local per = daily ~= nil and daily * S.TARGET_DAYS or (S.PER_MEMBER[c] or 0)
        local want = math.ceil(per * members - 1e-9)
        local level = 100
        if want > 0 then level = math.min(100, math.floor(have * 100 / want + 0.5)) end
        out.have[c], out.want[c], out.levels[c] = have, want, level
        if daily ~= nil and daily > 0 then
            local d = tenths(have / (daily * members))
            out.days[c] = d
            if autonomy == nil or d < autonomy then autonomy = d end
        end
        if have < want then
            local status = "low"
            if have == 0 then status = "empty" elseif level < S.CRITICAL then status = "critical" end
            out.needs[#out.needs + 1] = { c = c, have = have, want = want, missing = want - have, level = level,
                                          status = status }
        end
    end
    out.autonomy = autonomy or 0
    table.sort(out.needs, function(a, b)
        local sa, sb = Stock.STATUS_ORDER[a.status], Stock.STATUS_ORDER[b.status]
        if sa ~= sb then return sa < sb end
        if a.level ~= b.level then return a.level < b.level end
        return rank[a.c] < rank[b.c]
    end)
    return out
end

-- Niveau de rationnement d'après l'autonomie (jours), sans tenir compte du niveau courant.
local function band(autonomy, out)
    local R = Stock.SUPPLY.RATION_DAYS
    if out then return 3 end
    if autonomy < R[2] then return 2 end
    if autonomy < R[1] then return 1 end
    return 0
end

-- Niveau de rationnement (pur) : a = Stock.assess(...), current = niveau en vigueur. Durcir : aussitôt ;
-- adoucir : seulement avec RATION_MARGIN jour(s) d'avance sur le seuil quitté.
function Stock.rationLevel(a, current)
    local out = (a.have.food or 0) == 0 or (a.have.water or 0) == 0
    local level = band(a.autonomy, out)
    if not isInt(current, 0, #Stock.RATIONS - 1) then current = 0 end
    if level >= current then return level end
    local eased = math.min(2, band(a.autonomy - Stock.SUPPLY.RATION_MARGIN, false))
    return math.max(level, math.min(current, eased))
end

-- Évaluation d'un groupe du registre (table vivante ou copie) d'après sa référence : Stock.assess, plus ration (en
-- vigueur), next (niveau que la relecture appliquerait), portion. nil sans référence valide ni membre vivant.
function Stock.assessGroup(g)
    if type(g) ~= "table" or type(g.home) ~= "table" or not Stock.validRef(g.stock, g.home) then return nil end
    local a = Stock.assess(Stock.count(g.stock.items, g.stock.pend), Stock.livingMembers(g))
    if a == nil then return nil end
    a.ration = rationOf(g.stock)
    a.next = Stock.rationLevel(a, a.ration)
    a.rationName = Stock.RATIONS[a.ration + 1]
    a.portion = Stock.PORTIONS[a.ration + 1]
    return a
end

-- Besoins du groupe gid (copie de Stock.assessGroup), ou nil et une raison. Serveur seulement.
function Stock.needs(gid)
    local g = Groups().get(gid)
    if g == nil then return nil, "unknown group" end
    local a = Stock.assessGroup(g)
    if a == nil then return nil, "no stock reference or no living member" end
    return a
end

-- Part d'une ration normale (1, 0,75, 0,5, 0) du groupe gid ; 1 sans référence de stock.
function Stock.portion(gid)
    local a = Stock.needs(gid)
    return a ~= nil and a.portion or 1
end

-- Applique le rationnement d'après la référence courante (après chaque relecture). Changement : stock.ration,
-- entrée « ration » au journal du groupe, ligne au journal du moteur. Rend le niveau en vigueur, ou nil.
function Stock.updateRation(gid)
    local level
    Groups().update(function(data)
        local changed
        level, changed = Stock.applyRation(data.groups[gid], gid, Groups().today())
        return changed, true
    end)
    return level
end

-- Même règle sur le groupe vivant g du registre (logique pure, dans l'écriture de l'appelant ; LK09-T06 : la
-- simulation passe le jour de l'heure simulée). Rend le niveau en vigueur (ou nil) et vrai s'il a changé.
function Stock.applyRation(g, gid, day)
    local a = Stock.assessGroup(g)
    if a == nil then return nil, false end
    if a.next == a.ration then return a.next, false end
    local G = Groups()
    local text = string.format("ration %s (was %s): %.1f day(s) of food and water for %d (food %d, water %d)",
        Stock.RATIONS[a.next + 1], Stock.RATIONS[a.ration + 1], a.autonomy, a.members, a.have.food, a.have.water)
    g.stock.ration = a.next
    G.appendLog(g, "ration", string.sub(text, 1, G.TEXT_MAX), day or G.today())
    log().info("stock: group %s %s", gid, text)
    return a.next, true
end

-- ================================================================ repas réels (LK05-T07)

-- Vrai si l'objet, de la catégorie cat ("food" ou "water"), se mange ou se boit tel quel : nourriture ni pourrie, ni
-- gelée, ni crue dangereuse (Food.isRotten, isFrozen, isbDangerousUncooked : J/inventory/types/Food.java:1653, 1671,
-- 1974 ; InventoryItem.isCooked :2413) ; eau propre seulement (fluide principal Fluid.Water).
function Stock.consumable(item, cat)
    if item == nil then return false end
    if cat == "water" then
        local fc = item:getFluidContainer()
        return fc ~= nil and not fc:isEmpty() and Fluid ~= nil and fc:getPrimaryFluid() == Fluid.Water
    end
    if cat ~= "food" or Stock.categoryOf(item) ~= "food" then return false end
    if instanceof(item, "Food") then
        if item:isRotten() or item:isFrozen() then return false end
        if item:isbDangerousUncooked() and not item:isCooked() then return false end
    end
    return true
end

-- Conteneurs lisibles du foyer du groupe gid : liste de Stock.containers, ou nil et une raison.
local function homeContainers(gid)
    local g = Groups().get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no group or no home" end
    if not Stock.validRef(g.stock, g.home) then return nil, "no stock reference" end
    local style, def = Homes().ready(g.home)
    if style == nil then return nil, def end
    local list, why = Stock.containers(gid, g.home, style, def ~= nil and def:getIDString() or nil)
    -- LK09-T06 : écarts hors écran appliqués avant toute prise du groupe dans les conteneurs.
    if list ~= nil and Stock.pendingCount(g.stock) > 0 then Stock.applyPending(gid, list, g) end
    return list, why
end
Stock.homeContainers = homeContainers   -- LK11-T08 : troc (LK_Trade.lua), mêmes conteneurs que les prises du groupe

local function firstConsumable(container, cat)
    local items = container:getItems()
    for j = 0, items:size() - 1 do
        local it = items:get(j)
        if Stock.categoryOf(it) == cat and Stock.consumable(it, cat) then return it end
    end
    return nil
end

-- Premier objet consommable de la catégorie cat ("food" ou "water") dans les conteneurs du foyer du groupe gid (ordre
-- des clés de conteneur, puis des objets : reproductible). Rend { key, x, y, z (case de l'objet qui porte le
-- conteneur), i, t, c }, ou nil et une raison ("none" : rien à manger ou à boire ; autre : stock ou zone illisible).
function Stock.findMeal(gid, cat)
    if cat ~= "food" and cat ~= "water" then return nil, "bad category" end
    local containers, why = homeContainers(gid)
    if containers == nil then return nil, why end
    for _, ct in ipairs(containers) do
        local it = firstConsumable(ct.container, cat)
        if it ~= nil then
            return { key = ct.key, x = ct.x, y = ct.y, z = ct.z, i = it:getID(), t = it:getFullType(), c = cat }
        end
    end
    return nil, "none"
end

-- Prend UN objet consommable de la catégorie cat dans le conteneur de clé key (relu maintenant : l'objet repéré a pu
-- partir entre-temps). L'objet est retiré du conteneur (et des clients sur un serveur), puis ôté de la référence dans la
-- même écriture du registre que apply(g) (facultatif, groupe vivant). who : texte du journal. Rend { i, t, c, k }, ou
-- nil et une raison ("gone" : plus rien de consommable dans ce conteneur).
function Stock.takeMeal(gid, cat, key, apply, who)
    if cat ~= "food" and cat ~= "water" then return nil, "bad category" end
    local containers, why = homeContainers(gid)
    if containers == nil then return nil, why end
    local ct
    for _, c in ipairs(containers) do
        if c.key == key then ct = c end
    end
    if ct == nil then return nil, "container gone" end
    local item = firstConsumable(ct.container, cat)
    if item == nil then return nil, "gone" end
    local id, t = item:getID(), item:getFullType()
    ct.container:DoRemoveItem(item)
    if isServer() then sendRemoveItemFromContainer(ct.container, item) end
    local written = Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil then return false, false end
        if type(live.home) == "table" and Stock.validRef(live.stock, live.home) then
            local kept = {}
            for _, e in ipairs(live.stock.items) do
                if e.i ~= id then kept[#kept + 1] = e end
            end
            live.stock.items = kept
        end
        if apply ~= nil then apply(live) end
        return true, true
    end)
    if not written then
        log().warn("stock: group %s: %s taken from %s but the registry was not written (counted as lost)", gid, t, key)
    end
    Stock.stats.meals = Stock.stats.meals + 1
    log().info("stock: group %s: %s %s %s (%s) from %s", gid, tostring(who or "member"),
        cat == "water" and "drank" or "ate", t, tostring(id), key)
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then Ac.note(gid, who, "meal", (cat == "water" and "drank " or "ate ") .. t .. " from " .. key) end
    Stock.updateRation(gid)
    return { i = id, t = t, c = cat, k = key }
end

-- Pénurie : un membre n'a rien trouvé à manger (cat "food"), à boire ("water") ou pour panser une plaie ("medical",
-- LK07-T03, LK_Care) dans le stock. Écrite au journal du
-- groupe (kind « shortage ») au plus une fois par SHORTAGE_HOURS et par catégorie ; le rationnement est relu.
-- Rend vrai si écrite.
function Stock.reportShortage(gid, cat, who)
    Stock.state.shortage = Stock.state.shortage or {}
    local slot = gid .. "|" .. tostring(cat)
    local h = hourNow()
    local last = Stock.state.shortage[slot]
    Stock.updateRation(gid)
    if last ~= nil and h - last < cfg().SHORTAGE_HOURS and h >= last then return false end
    Stock.state.shortage[slot] = h
    local a = Stock.needs(gid)
    local what = cat == "water" and "water to drink" or cat == "medical" and "bandage to treat a wound" -- LK07-T03
        or "food to eat"
    local text = string.format("no %s left for %s (ration %s)", what,
        tostring(who or "a member"), a ~= nil and a.rationName or "unknown")
    local G = Groups()
    G.update(function(data)
        local g = data.groups[gid]
        if g == nil then return false, false end
        G.appendLog(g, "shortage", string.sub(text, 1, G.TEXT_MAX), G.today())
        return true, true
    end)
    Stock.stats.shortages = Stock.stats.shortages + 1
    log().info("stock: group %s %s", gid, text)
    return true
end

-- ================================================================ matériaux d'entretien (LK05-T10)
-- Entretien du foyer (LK_Upkeep.lua, fiche docs/conception/entretien.md) : carburant, pièces et produits pris dans les
-- conteneurs du foyer, relus au moment de la prise, jamais créés. Un récipient (fluide) est vidé de la quantité exacte
-- utilisée comme le vanilla (FluidContainer.adjustAmount(quantité - prise), ISAddFuel.lua:56-61, ISCleanBlood.lua) ;
-- sur un serveur, l'objet resté dans son meuble part aux clients proches par sendItemStats (copie du fluide :
-- J/network/GameServer.java:2944-2964, J/network/packets/ItemStatsPacket.java:160-168, 520-523) ; syncItemFields ne
-- vise que l'inventaire d'un joueur ou un objet posé au sol (J/inventory/InventoryItem.java:4154-4170). Un objet pris
-- entier (pièce) est retiré comme un repas (DoRemoveItem, sendRemoveItemFromContainer) et ôté de la référence s'il y
-- était suivi.

-- Fluide principal d'un récipient non vide parmi la liste fluids ({ "Petrol" }, ...), ou nil ; quantité en litres.
local function fluidIn(item, fluids)
    local fc = item ~= nil and item:getFluidContainer() or nil
    if fc == nil or fc:isEmpty() or Fluid == nil then return nil end
    local primary = fc:getPrimaryFluid()
    for _, name in ipairs(fluids) do
        if Fluid[name] ~= nil and primary == Fluid[name] then return name, fc:getAmount(), fc end
    end
    return nil
end

-- Premier objet des conteneurs du foyer (ordre des clés, puis des objets) tel que pred(objet) : { key, x, y, z, i, t },
-- objet, conteneur ; ou nil et une raison ("none" : aucun ; autre : stock ou zone illisible).
function Stock.findItem(gid, pred)
    local containers, why = homeContainers(gid)
    if containers == nil then return nil, why end
    for _, ct in ipairs(containers) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            if it ~= nil and pred(it) then
                return { key = ct.key, x = ct.x, y = ct.y, z = ct.z, i = it:getID(), t = it:getFullType() }, it,
                    ct.container
            end
        end
    end
    return nil, "none"
end

-- Premier récipient du foyer dont le fluide principal est dans fluids et qui en contient au moins least litres :
-- { key, x, y, z, i, t, fluid, amount }, ou nil et une raison.
function Stock.findFluid(gid, fluids, least)
    local found, item = Stock.findItem(gid, function(it)
        local name, amount = fluidIn(it, fluids)
        return name ~= nil and amount >= (least or 0) and amount > 0
    end)
    if found == nil then return nil, item end
    found.fluid, found.amount = fluidIn(item, fluids)   -- LK05-T11 : champs annoncés, lus maintenant
    return found
end

-- Verse au plus want litres d'un fluide de la liste fluids, pris dans UN récipient du foyer qui en contient au moins
-- least litres (relu maintenant). Retire exactement la quantité rendue. who, use : texte du journal. Rend { i, t, k,
-- fluid, amount, left }, ou nil et une raison.
function Stock.drawFluid(gid, fluids, want, least, who, use)
    if type(want) ~= "number" or want <= 0 then return nil, "nothing wanted" end
    local found, item = Stock.findItem(gid, function(it)
        local name, amount = fluidIn(it, fluids)
        return name ~= nil and amount >= (least or 0) and amount > 0
    end)
    if found == nil then return nil, item end
    local name, amount, fc = fluidIn(item, fluids)
    local q = math.min(amount, want)
    fc:adjustAmount(amount - q)
    if isServer() then sendItemStats(item) end
    Stock.stats.fluids = (Stock.stats.fluids or 0) + 1
    log().info("stock: group %s: %s used %.3f l of %s from %s (%s) in %s for %s", gid, tostring(who or "member"), q,
        name, found.t, tostring(found.i), found.key, tostring(use or "upkeep"))
    return { i = found.i, t = found.t, k = found.key, fluid = name, amount = q, left = fc:getAmount() }
end

-- Prend UN objet du foyer tel que pred(objet) (pièce de réparation...) : retiré du conteneur (et des clients sur un
-- serveur), ôté de la référence s'il y était suivi. Rend { i, t, k } et l'objet retiré (LK11-T06 : le même objet est
-- donné au joueur), ou nil et une raison. apply(g) facultatif (LK11-T06) : appelé sur le groupe vivant dans la MÊME
-- écriture du registre que la mise à jour de la référence (le registre est alors écrit même si l'objet n'était pas
-- suivi).
function Stock.takeItem(gid, pred, who, use, apply)
    local found, item, container = Stock.findItem(gid, pred)
    if found == nil then return nil, item end
    container:DoRemoveItem(item)
    if isServer() then sendRemoveItemFromContainer(container, item) end
    local id = found.i
    local written = Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not Stock.validRef(live.stock, live.home) then
            return false, live ~= nil
        end
        local kept, gone = {}, false
        for _, e in ipairs(live.stock.items) do
            if e.i ~= id then kept[#kept + 1] = e else gone = true end
        end
        if apply ~= nil then apply(live) end
        if not gone then return apply ~= nil, true end
        live.stock.items = kept
        return true, true
    end)
    if not written then
        log().warn("stock: group %s: %s taken from %s but the registry was not read (reference unchanged)", gid,
            found.t, found.key)
    end
    Stock.stats.parts = (Stock.stats.parts or 0) + 1
    log().info("stock: group %s: %s used %s (%s) from %s for %s", gid, tostring(who or "member"), found.t,
        tostring(id), found.key, tostring(use or "upkeep"))
    return { i = id, t = found.t, k = found.key }, item
end

-- LK05-T11 : objet d'identifiant id resté au foyer mais sorti des catégories suivies (bouteille vidée pour arroser) :
-- ôté de la référence, pour que la relecture suivante ne le compte pas perdu. Rend vrai s'il y était.
function Stock.untrack(gid, id)
    local gone = false
    Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not Stock.validRef(live.stock, live.home) then
            return false, false
        end
        local kept = {}
        for _, e in ipairs(live.stock.items) do
            if e.i ~= id then kept[#kept + 1] = e else gone = true end
        end
        if not gone then return false, false end
        live.stock.items = kept
        return true, true
    end)
    return gone
end

-- ================================================================ stock hors écran (LK09-T06)
-- Logique pure sur le registre vivant (appelée par LK_Simulation dans l'écriture de son pas : aucun accès au monde,
-- aucun hasard, même résultat que les heures passent une par une ou en rattrapage), puis application aux conteneurs
-- réels quand le foyer est lisible (Stock.applyPending).

local function off() return Stock.OFFSCREEN end

-- Membres vivants au foyer qui mangent hors écran : ni en expédition (leurs vivres sont dans le rendement net du
-- lieu, LK09-T02), ni incarnés (repas réels dans les conteneurs, LK05-T07).
local function abstractEaters(g)
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local Sim = LivingKnox.Simulation
    local n = 0
    for mid, m in pairs(g.members) do
        if type(m) == "table" and m.alive and not away[mid]
            and not (Sim ~= nil and Sim.isEmbodied ~= nil and Sim.isEmbodied(m)) then
            n = n + 1
        end
    end
    return n
end

-- Retire au plus n objets de la catégorie c de la référence s (journal p) : ajouts en attente de la même catégorie
-- annulés d'abord (les plus récents), puis objets suivis dans l'ordre de la référence (écart « take »). Rend le
-- nombre pris.
local function consume(s, p, c, n)
    local taken = 0
    local k = #p.ops
    while taken < n and k >= 1 do
        local op = p.ops[k]
        if op.o == "add" and op.c == c then
            table.remove(p.ops, k)
            taken = taken + 1
        end
        k = k - 1
    end
    if taken >= n then return taken end
    local kept = {}
    for _, e in ipairs(s.items) do
        if taken < n and e.c == c and #p.ops < Stock.PEND_MAX then
            p.n = p.n + 1
            p.ops[#p.ops + 1] = { u = p.n, o = "take", i = e.i, t = e.t, c = e.c, k = e.k }
            taken = taken + 1
        else
            kept[#kept + 1] = e
        end
    end
    s.items = kept
    return taken
end

-- Heure simulée hour du groupe vivant g (registre, dans l'écriture du pas) : à l'heure du jour MEAL_HOUR, repas
-- abstrait des membres au foyer (DAILY x part de ration, arrondi au plus proche, nourriture et eau). day : jour de
-- l'heure simulée (journal). Rend { eaters, portion, food, water, wantFood, wantWater }, ou nil (aucun repas).
function Stock.offscreenHour(g, gid, hour, day)
    if type(g) ~= "table" or type(g.home) ~= "table" or not Stock.validRef(g.stock, g.home) then return nil end
    if type(hour) ~= "number" or (hour + 6) % 24 ~= off().MEAL_HOUR then return nil end
    local a = Stock.assessGroup(g)
    if a == nil then return nil end
    local eaters = abstractEaters(g)
    if eaters == 0 then return nil end
    local s = g.stock
    local p = pendOf(s, true, gid)
    local out = { eaters = eaters, portion = a.portion }
    local short = false
    for _, c in ipairs({ "food", "water" }) do
        local want = math.floor(eaters * (Stock.SUPPLY.DAILY[c] or 0) * a.portion + 0.5)
        local got = want > 0 and consume(s, p, c, want) or 0
        out[c] = got
        out["want" .. string.upper(string.sub(c, 1, 1)) .. string.sub(c, 2)] = want
        if got < want then short = true end
        Stock.stats.offEaten = Stock.stats.offEaten + got
    end
    if out.food + out.water > 0 or s.pend ~= nil then s.pend = p end
    Stock.stats.offMeals = Stock.stats.offMeals + 1
    if short then Stock.stats.offShort = Stock.stats.offShort + 1 end
    log().debug("stock: group %s offscreen meal (hour %s, %d eater(s), ration %s): food %d/%d, water %d/%d", gid,
        tostring(hour), eaters, tostring(a.rationName), out.food, out.wantFood, out.water, out.wantWater)
    Stock.applyRation(g, gid, day)
    return out
end

-- Butin d'une expédition abstraite (LK09-T02, Simulation.resolveExpedition) du groupe vivant g : gains = { [réserve]
-- = points gagnés } ; un objet par LEVEL_PER_ITEM points, types de OFFSCREEN.ITEMS, ajouts en attente tant que la
-- référence (objets suivis + ajouts) reste sous MAX_ITEMS. Rend le nombre d'objets ajoutés.
function Stock.offscreenLoot(g, gid, gains, day)
    if type(g) ~= "table" or type(g.home) ~= "table" or not Stock.validRef(g.stock, g.home) then return 0 end
    if type(gains) ~= "table" then return 0 end
    local per = off().LEVEL_PER_ITEM
    if type(per) ~= "number" or per ~= per or per < 1 then per = 1 end
    local s = g.stock
    local p = pendOf(s, true, gid)
    local adds = 0
    for _, op in ipairs(p.ops) do
        if op.o == "add" then adds = adds + 1 end
    end
    local added, parts = 0, {}
    for _, c in ipairs(Stock.CATEGORIES) do
        local gain = gains[c]
        local list = off().ITEMS[c]
        if type(gain) == "number" and gain == gain and gain > 0 and type(list) == "table" and #list > 0 then
            local n, got = math.floor(gain / per), 0
            for _ = 1, n do
                if #s.items + adds >= Stock.MAX_ITEMS or #p.ops >= Stock.PEND_MAX then break end
                p.n = p.n + 1
                p.ops[#p.ops + 1] = { u = p.n, o = "add", t = list[(p.n - 1) % #list + 1], c = c }
                adds, got = adds + 1, got + 1
            end
            if got > 0 then parts[#parts + 1] = c .. " +" .. got end
            added = added + got
        end
    end
    if added == 0 then return 0 end
    s.pend = p
    Stock.stats.offLoot = Stock.stats.offLoot + added
    log().debug("stock: group %s offscreen expedition loot pending: %s", gid, table.concat(parts, " "))
    Stock.applyRation(g, gid, day)
    return added
end

-- LK14-T05 (fortification hors écran, LK_Fortify) : objets dont le type complet est dans types (liste) dans la
-- référence s : objets suivis plus ajouts en attente d'un journal valide.
function Stock.offscreenCount(s, types)
    if type(s) ~= "table" or type(s.items) ~= "table" or type(types) ~= "table" then return 0 end
    local set = {}
    for _, t in ipairs(types) do set[t] = true end
    local n = 0
    for _, e in ipairs(s.items) do
        if set[e.t] then n = n + 1 end
    end
    local p = pendOf(s, false)
    if p ~= nil then
        for _, op in ipairs(p.ops) do
            if op.o == "add" and set[op.t] then n = n + 1 end
        end
    end
    return n
end

-- LK14-T05 : prend n objets des types types dans la référence du groupe vivant g (registre, dans l'écriture du pas
-- de simulation : logique pure), tout ou rien : ajouts en attente de ces types annulés d'abord (les plus récents),
-- puis objets suivis dans l'ordre de la référence (écarts « take », appliqués aux conteneurs à l'arrivée d'un
-- joueur comme ceux du repas abstrait). Rend n, ou 0 si la référence n'en a pas assez (rien de pris).
function Stock.offscreenTake(g, gid, types, n)
    if type(g) ~= "table" or type(g.home) ~= "table" or not Stock.validRef(g.stock, g.home) then return 0 end
    if not isInt(n, 1, Stock.MAX_ITEMS) or Stock.offscreenCount(g.stock, types) < n then return 0 end
    local s = g.stock
    local p = pendOf(s, true, gid)
    if #p.ops + n > Stock.PEND_MAX then return 0 end
    local set = {}
    for _, t in ipairs(types) do set[t] = true end
    local taken = 0
    local k = #p.ops
    while taken < n and k >= 1 do
        local op = p.ops[k]
        if op.o == "add" and set[op.t] then
            table.remove(p.ops, k)
            taken = taken + 1
        end
        k = k - 1
    end
    if taken < n then
        local kept = {}
        for _, e in ipairs(s.items) do
            if taken < n and set[e.t] then
                p.n = p.n + 1
                p.ops[#p.ops + 1] = { u = p.n, o = "take", i = e.i, t = e.t, c = e.c, k = e.k }
                taken = taken + 1
            else
                kept[#kept + 1] = e
            end
        end
        s.items = kept
    end
    s.pend = p
    Stock.stats.offTaken = (Stock.stats.offTaken or 0) + taken
    return taken
end

-- Objet vanilla d'un écart « add » : créé, eau remplie, marqué (groupe et marque d'application). Rend l'objet, ou nil
-- et une raison (type refusé : l'écart est abandonné).
local function makePending(gid, op, mark)
    if string.sub(op.t, 1, 5) ~= "Base." then return nil, "not a vanilla item" end
    local item = instanceItem(op.t)
    if item == nil then return nil, "unknown item" end
    if op.c == "water" then
        local fc = item:getFluidContainer()
        if fc == nil or Fluid == nil or Fluid.Water == nil then return nil, "cannot fill" end
        fc:Empty()
        fc:addFluid(Fluid.Water, fc:getCapacity())
    end
    local md = item:getModData()
    md[Stock.TAG] = gid
    md[Stock.OP_TAG] = mark
    return item
end

-- Applique le journal d'écarts du groupe gid aux conteneurs lisibles du foyer (containers = Stock.containers) ; g :
-- copie du groupe (facultative). Objets pris retirés s'ils sont encore là ; objets ajoutés créés (ou repris s'ils
-- portent déjà leur marque) dans le conteneur posé par LK_Homes, sinon le premier ; puis, en une écriture, écarts
-- traités ôtés du journal (par numéro : un écart ajouté entre-temps reste) et objets créés ajoutés à la référence ;
-- marques effacées après l'écriture. Rend { removed, gone, made, adopted, dropped, kept }, ou nil et une raison.
function Stock.applyPending(gid, containers, g)
    g = g or Groups().get(gid)
    if g == nil or type(g.home) ~= "table" or not Stock.validRef(g.stock, g.home) then
        return nil, "no stock reference"
    end
    local p = pendOf(g.stock, false, gid)
    if p == nil or #p.ops == 0 then return nil, "nothing pending" end
    local byId, byMark, depot = {}, {}, nil
    for _, ct in ipairs(containers) do
        if depot == nil and ct.owned then depot = ct end
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            byId[it:getID()] = { item = it, ct = ct }
            if it:hasModData() then
                local mk = it:getModData()[Stock.OP_TAG]
                if type(mk) == "string" then byMark[mk] = { item = it, ct = ct } end
            end
        end
    end
    depot = depot or containers[1]
    local rep = { removed = 0, gone = 0, made = 0, adopted = 0, dropped = 0, kept = 0 }
    local done, refs, marked = {}, {}, {}
    for _, op in ipairs(p.ops) do
        if op.o == "take" then
            local hit = byId[op.i]
            if hit ~= nil then
                hit.ct.container:DoRemoveItem(hit.item)
                if isServer() then sendRemoveItemFromContainer(hit.ct.container, hit.item) end
                byId[op.i] = nil
                rep.removed = rep.removed + 1
            else
                rep.gone = rep.gone + 1
            end
            done[op.u] = true
        else
            local mark = gid .. ":" .. op.u
            local hit = byMark[mark]
            local item, ct
            if hit ~= nil then
                item, ct = hit.item, hit.ct
                rep.adopted = rep.adopted + 1
            elseif depot ~= nil then
                local ok, made, why = pcall(makePending, gid, op, mark)
                if ok and made ~= nil then
                    item, ct = made, depot
                    depot.container:AddItem(item)
                    if isServer() then sendAddItemToContainer(depot.container, item) end
                    rep.made = rep.made + 1
                elseif ok then
                    done[op.u] = true
                    rep.dropped = rep.dropped + 1
                    log().warn("stock: group %s pending %s not created: %s (dropped)", gid, op.t, tostring(why))
                else
                    rep.kept = rep.kept + 1
                    log().error("stock: group %s pending %s not created: %s (kept)", gid, op.t, tostring(made))
                end
            else
                rep.kept = rep.kept + 1
            end
            if item ~= nil then
                done[op.u] = true
                marked[#marked + 1] = item
                local cat = Stock.categoryOf(item)
                if cat ~= nil then refs[#refs + 1] = { i = item:getID(), t = item:getFullType(), c = cat, k = ct.key } end
            end
        end
    end
    local written = Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not Stock.validRef(live.stock, live.home) then
            return false, false
        end
        local lp = pendOf(live.stock, false, gid)
        if lp ~= nil then
            local kept = {}
            for _, op in ipairs(lp.ops) do
                if not done[op.u] then kept[#kept + 1] = op end
            end
            lp.ops = kept
        end
        local have = {}
        for _, e in ipairs(live.stock.items) do have[e.i] = true end
        for _, r in ipairs(refs) do
            if not have[r.i] and #live.stock.items < Stock.MAX_ITEMS then
                live.stock.items[#live.stock.items + 1] = r
                have[r.i] = true
            end
        end
        return true, true
    end)
    -- LK13-T06 : registre écrit dans son fichier avant d'effacer les marques (sinon une sauvegarde du monde sans marque
    -- suivie d'un arrêt avant l'écriture différée ferait recréer les objets).
    if written then written = Groups().flush() end
    if written then
        for _, item in ipairs(marked) do item:getModData()[Stock.OP_TAG] = nil end
    else
        log().warn("stock: group %s pending stock changes applied but the registry was not written (marks kept)", gid)
    end
    Stock.stats.applied = Stock.stats.applied + 1
    Stock.stats.removed = Stock.stats.removed + rep.removed
    Stock.stats.gone = Stock.stats.gone + rep.gone
    Stock.stats.made = Stock.stats.made + rep.made
    Stock.stats.adopted = Stock.stats.adopted + rep.adopted
    log().info("stock: group %s offscreen changes applied into %s: %d removed, %d already gone, %d created, "
        .. "%d resumed, %d dropped, %d kept", gid, depot ~= nil and depot.key or "no container", rep.removed, rep.gone,
        rep.made, rep.adopted, rep.dropped, rep.kept)
    Stock.updateRation(gid)
    return rep
end

-- Groupes à relire : foyer aménagé dont la case est chargée, triés par identifiant.
local function candidates(cell)
    local out = Groups().update(function(data)
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
    if type(out) ~= "table" then return {} end
    table.sort(out)
    return out
end

-- Relit les stocks des foyers chargés. reason = "chunk" (au plus une fois par SCAN_MS) ou "minute". Rend le nombre
-- de groupes relus.
function Stock.scan(reason)
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local st = Stock.state
    local t = now()
    if reason == "chunk" and st.lastScan ~= nil and t - st.lastScan < cfg().SCAN_MS then return 0 end
    st.lastScan = t
    local cell = getCell()
    if cell == nil then return 0 end
    local n = 0
    for _, gid in ipairs(candidates(cell)) do
        if Stock.checkOne(gid) then n = n + 1 end
    end
    return n
end

-- Relecture d'un groupe par Stock.scan ou la file de la minute : rend vrai si relu. Erreur journalisée.
function Stock.checkOne(gid)
    local ok, res, why = pcall(Stock.check, gid)
    if not ok then
        log().error("stock: group %s check failed: %s", gid, tostring(res))
    elseif type(res) == "table" then
        return true
    elseif why ~= "checked recently" then
        log().debug("stock: group %s not checked: %s", gid, tostring(why))
    end
    return false
end

-- Relecture de la minute étalée (LK13-T09, fiche stock.md « Relecture étalée ») : à chaque minute de jeu, les groupes
-- candidats (foyer aménagé dont la case est chargée, triés) rejoignent une file, sans doublon ; un groupe relu par
-- image (OnTick), à partir de l'image qui suit la minute (marque « fresh » effacée au début de l'image suivante,
-- comme la file du pas horaire de LK_Simulation). Même relecture (Stock.check) et même ordre que Stock.scan("minute"),
-- décalée de quelques images (100 ms chacune sur un serveur dédié). Écriture du registre des groupes retenue pendant
-- la file (Groups.hold("stock")) puis faite dans une image à elle : une seule écriture, comme quand tous les groupes
-- étaient relus dans la même image. Rend le nombre de groupes rangés.
Stock.queue = Stock.queue or { list = {}, head = 1, queued = {}, fresh = false, write = false }
Stock.QUEUE_HOLD_MARGIN = 3   -- images de retenue en plus du nombre de groupes en file

function Stock.queueScan()
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local cell = getCell()
    if cell == nil then return 0 end
    local q, n = Stock.queue, 0
    if q.head > #q.list then q.list, q.head, q.queued = {}, 1, {} end
    for _, gid in ipairs(candidates(cell)) do
        if not q.queued[gid] then
            q.queued[gid] = true
            q.list[#q.list + 1] = gid
            n = n + 1
        end
    end
    if q.head <= #q.list then
        q.fresh, q.write = true, true
        Groups().hold("stock", #q.list - q.head + 1 + Stock.QUEUE_HOLD_MARGIN)
    end
    return n
end

function Stock.onFrameStart()
    Stock.queue.fresh = false
end

-- Un groupe de la file (OnTick) ; la file vide, une image pour l'écriture seule. Rend vrai si un groupe a été relu.
-- LK13-T11 : un groupe dont le relevé de fortification de la minute est encore en file (trois images, LK_Fortify)
-- attend la fin de ce relevé (file arrêtée, écriture retenue d'autant) : son stock est relu après lui, comme quand le
-- relevé tenait dans une image, sans faire ses étapes restantes dans l'image de la relecture. finish : relevé fini
-- tout de suite (Stock.finishQueue).
function Stock.onFrame(finish)
    local q = Stock.queue
    if q.fresh then return false end
    if q.head > #q.list then
        if q.write then
            q.write = false
            q.list, q.head, q.queued = {}, 1, {}
            local G = Groups()
            G.release("stock")
            if G.isDirty() and not G.isHeld() then G.flush() end   -- une autre retenue (pas horaire) écrira à sa fin
        end
        return false
    end
    local gid = q.list[q.head]
    local F = LivingKnox.Fortify
    if F ~= nil and F.isQueued ~= nil and F.isQueued(gid) then
        if finish ~= true then
            Groups().hold("stock", #q.list - q.head + 1 + Stock.QUEUE_HOLD_MARGIN)
            return false
        end
        F.settleQueued(gid)
    end
    q.head = q.head + 1
    q.queued[gid] = nil
    return Stock.checkOne(gid)
end

-- File vidée tout de suite (bancs). Rend le nombre de groupes relus.
function Stock.finishQueue()
    local q, n = Stock.queue, 0
    q.fresh = false
    while q.head <= #q.list do
        if Stock.onFrame(true) then n = n + 1 end
    end
    q.write = false
    Groups().release("stock")
    return n
end

-- Efface la référence d'un groupe (suites en jeu, administration). Les objets restent où ils sont.
function Stock.clear(gid)
    local g = Groups().get(gid)
    if g ~= nil and g.stock ~= nil then writeRef(gid, nil) end
    Stock.state.checked[gid] = nil
end

function Stock.reset()
    Stock.state = { checked = {}, lastScan = nil, lastTheft = {}, shortage = {} }
    Stock.queue = { list = {}, head = 1, queued = {}, fresh = false, write = false }
    if Groups() ~= nil and Groups().release ~= nil then Groups().release("stock") end
end

-- Événements : LoadChunk et EveryOneMinute, inscrits après ceux de LK_Homes (ordre des fichiers) : le stock d'un
-- foyer aménagé dans la même minute est relu à partir de l'image suivante (LK13-T09 : un groupe par image).
local function onLoadChunk()
    Stock.scan("chunk")
end

local function onEveryOneMinute()
    Stock.queueScan()
end

LivingKnox.subscribe("LoadChunk", "Stock.onLoadChunk", onLoadChunk)
LivingKnox.subscribe("EveryOneMinute", "Stock.onEveryOneMinute", onEveryOneMinute)
LivingKnox.subscribe("OnTickEvenPaused", "Stock.frameStart", function() Stock.onFrameStart() end)
LivingKnox.subscribe("OnTick", "Stock.minuteQueue", function() Stock.onFrame() end)

return Stock
