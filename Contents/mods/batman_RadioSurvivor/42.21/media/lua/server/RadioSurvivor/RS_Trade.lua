-- Radio Survivor : livre du passeur de l'Ohio (E13-T02) : stock du passage, offre figée et action `propose_trade`.
-- Fiche : docs/conception/passeur-offre.md ; barème validé : docs/passeur-table.md (sections 1 et 3), code
-- shared/RadioSurvivor/RS_TradeValues.lua (valeur V de chaque objet).
--
-- Le LLM du passeur négocie à la radio et propose une offre par l'action `propose_trade` :
--     { type = "propose_trade", items = "Antibiotics:2, Battery:4", margin = 0.25 }
--   items  : texte, au plus MAX_PARAM_CHARS (64) caractères : objets apportés par le passeur, « Nom:quantité »
--            séparés par des virgules (quantité 1 si omise ; nom du stock, sans module, casse indifférente) ;
--   margin : nombre facultatif, marge choisie dans la fourchette permise à cet appelant (sinon la plus basse).
-- Le serveur décide (Trade.propose, appelé par l'exécuteur après les contrôles de RS_Actions) : chaque objet doit être
-- au stock du passage et disponible (stock tiré moins les offres en cours ou conclues des autres appelants), la
-- marge dans la fourchette, la charge au plus CAP_KG, le prix au plus CAP_POINTS (ce que le passeur peut prendre en
-- un passage). Hors table : refus avec une raison courte, aucune offre. Accepté : l'offre est figée (numéro de
-- révision rev, prix calculé ici, jamais par le LLM) et remplace l'offre précédente du même appelant ; ses quantités
-- sont réservées. Le stock disponible n'est donc jamais négatif.
-- Prix (section 1 du barème) : par ligne, ceil(V x quantité x (1 + marge) x M), M = cordon x rareté borné à M_MAX,
-- rareté RARITY si le stock tiré de l'objet est d'un seul exemplaire. Cordon : tiré par passage, ou fixé par
-- Trade.setCordon (E13-T03).
-- Mémoire des affaires passées : par appelant, les MAX_DEALS dernières offres (passage, objets, prix, issue :
-- open, replaced, expired, done, cheated, cancelled). Avec la réputation de l'appelant (E04-T11 : base bonne 0,10,
-- neutre 0,25, mauvaise 0,40), elle fixe la marge la plus basse permise (base moins MARGIN_STEP par affaire conclue,
-- jamais sous MARGIN_MIN ; MARGIN_MAX après une tricherie) et part dans le contexte
-- du LLM. Refus possible : le LLM ne propose rien ; le serveur refuse ce qui sort de la table.
-- Contexte du LLM : RadioSurvivor_Server joint Trade.field à chaque demande radio d'une voix qui autorise
-- propose_trade (champ trade=, hexadécimal RSV2) : stock disponible avec V, poids et prix unitaire à la marge la plus
-- basse, fourchette de marge, plafonds, ce que le passeur prend (barème et plafonds par catégorie), offre en cours,
-- affaires passées, dernier refus. Rien de secret : ni lieu, ni heure, ni fréquence.
-- Points d'appel des tâches suivantes : Trade.offerOf(caller, cid) (offre en cours, copie), Trade.close(caller, cid,
-- rev, outcome) (issue de l'échange sur la berge, E13-T04), Trade.setCordon(passage, level) (E13-T03).
-- État privé du serveur (S.data.trade, fichier d'état RS_State), jamais en ModData globale ; sinon (état pas encore
-- chargé ou bloqué) table en mémoire, perdue au redémarrage, comme les compteurs de RS_Actions.
-- Code ASCII seulement (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).
--
-- E13-T03 : passage réservé et rendez-vous (fiche docs/conception/passeur-rendezvous.md). Un seul passage par semaine
-- de jeu pour tout le serveur (S.data.trade.run, le passage en cours seulement). La réservation se fait à la radio :
-- la première offre figée du passage par l'exécuteur (propose_trade jugé par RS_Actions) le réserve pour l'équipe de
-- l'appelant (RS_Factions.idOf : faction vanilla ou équipe personnelle ; sans état ni joueur : « caller:<compte> »).
-- Ensuite, une offre d'une autre équipe est refusée (booked), et une fois le passage annulé, fait ou trop tard dans la
-- semaine pour une nuit (run_over), plus aucune offre. Une nouvelle offre de la même équipe remplace celle du passage
-- (même d'un autre membre). Rendez-vous : toujours le même ponton (PIER, Riverside, base knox-geography.md), de nuit,
-- de WINDOW_START à WINDOW_START + WINDOW_HOURS heure du jeu, la première nuit au moins LEAD_HOURS après la
-- réservation et dans la semaine du passage. Cordon (multiplicateur de prix) : tiré par passage (CORDON_ODDS,
-- reproductible), monté d'un cran par un hélicoptère vanilla entendu dans la semaine (noteHelicopter). Le suivi du
-- rendez-vous (annulations, signal, annonce à la radio, repère sur la carte) est dans RS_TradeRun.lua.
-- Appel direct de Trade.propose sans équipe (bancs, outils) : aucune réservation, comme en E13-T02.
--
-- E13-T04 : l'échange sans contact sur la berge (sac déposé au ponton, contenu évalué, objets retirés, contrepartie
-- posée) est dans RS_TradeExchange.lua ; il clôt le passage arrivé par Trade.finishRun (done, cheated ou cancelled).
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Codec = require "RadioSurvivor/RS_Codec"
local S = require "RadioSurvivor/RS_State"
local Actions = require "RadioSurvivor/RS_Actions"
local TV = require "RadioSurvivor/RS_TradeValues"
local News = require "RadioSurvivor/RS_OutsideNews"
local Factions = require "RadioSurvivor/RS_Factions"
local Rep = require "RadioSurvivor/RS_Reputation"

local Trade = {}

Trade.ACTION = "propose_trade"
Trade.COOLDOWN_MS = 0          -- budget.propose_trade de la fiche et 3 actions par réponse suffisent
Trade.MARGIN_MIN = 0.10
Trade.MARGIN_DEFAULT = 0.25
Trade.MARGIN_MAX = 0.50
Trade.MARGIN_STEP = 0.05       -- baisse de la marge la plus basse par affaire conclue
Trade.M_MAX = 1.75
Trade.RARITY = 1.25
Trade.CORDONS = { 1.0, 1.25, 1.5 }
Trade.CAP_POINTS = 120         -- points au plus pris par passage (section 1)
Trade.CAP_KG = 10              -- poids au plus de la contrepartie
Trade.MAX_LINES = 8            -- objets distincts au plus par offre
Trade.MAX_QTY = 99
Trade.MAX_DEALS = 8            -- affaires gardées par appelant
Trade.DEALS_SENT = 5           -- affaires envoyées au LLM
Trade.MAX_BOOKS = 50           -- appelants gardés, le moins récent évincé
Trade.REASONS = { "bad_params", "bad_margin", "not_in_stock", "over_stock", "over_weight", "over_cap", "failed",
    "booked", "run_over" }
-- Passage réservé (E13-T03).
Trade.LEAD_HOURS = 6           -- au moins 6 heures de jeu entre la réservation et le rendez-vous
Trade.WINDOW_START = 1         -- 01:00 heure du jeu : nuit noire en juillet (base staging-effects.md)
Trade.WINDOW_HOURS = 2         -- jusqu'à 03:00, quand le passeur reprend l'écoute
Trade.CORDON_ODDS = { 60, 30, 10 }   -- pour cent : calme, patrouilles, cordon serré (Trade.CORDONS)
-- Ponton de Riverside (floors_interior_tilesandwood_01_40, x 6041-6042, y 5215-5220, eau à l'ouest ; bassin ouest de
-- l'Ohio, base knox-geography.md). desc : pour le LLM, sans chiffre.
Trade.PIER = { x = 6041, y = 5217, z = 0,
    desc = "the old wooden pier on the river at the west end of Riverside, where the boat can come alongside" }
-- Plafonds par catégorie de ce que le passeur prend (sections 2.1 à 2.4), pour le contexte du LLM ; le contrôle du
-- contenu du sac déposé est E13-T04.
Trade.TAKES = {
    { k = "valuables", cap = 60 }, { k = "images", cap = 40 }, { k = "papers", cap = 30, pieces = 10 },
    { k = "military", cap = 60 },
}

-- Ce que le passeur apporte (section 3) : nom du stock, type complet, poids en kg (Weight du script vanilla 42.21,
-- plus le contenu d'un récipient plein : InventoryItem.getContentsWeight = litres de fluide,
-- J/inventory/InventoryItem.java:3135-3147), fourchette du stock par passage. Graines (gr = "seeds") : 3 à 8 sachets
-- au total, 4 sortes au plus ; alcools (gr = "alcohol") : 1 à 4 bouteilles au total. V : RS_TradeValues.sellValue.
Trade.SUPPLY = {
    { n = "Battery", t = "Base.Battery", w = 0.1, min = 4, max = 12 },
    { n = "Antibiotics", t = "Base.Antibiotics", w = 0.1, min = 2, max = 6 },
    { n = "ShotgunShellsBox", t = "Base.ShotgunShellsBox", w = 1.5, min = 0, max = 2 },
    { n = "308Box", t = "Base.308Box", w = 0.6, min = 0, max = 2 },
    { n = "3030Box", t = "Base.3030Box", w = 0.6, min = 0, max = 1 },
    { n = "CarrotBagSeed2", t = "Base.CarrotBagSeed2", w = 0.1, gr = "seeds" },
    { n = "BroccoliBagSeed2", t = "Base.BroccoliBagSeed2", w = 0.1, gr = "seeds" },
    { n = "RedRadishBagSeed2", t = "Base.RedRadishBagSeed2", w = 0.1, gr = "seeds" },
    { n = "StrewberrieBagSeed2", t = "Base.StrewberrieBagSeed2", w = 0.1, gr = "seeds" },
    { n = "TomatoBagSeed2", t = "Base.TomatoBagSeed2", w = 0.1, gr = "seeds" },
    { n = "PotatoBagSeed2", t = "Base.PotatoBagSeed2", w = 0.1, gr = "seeds" },
    { n = "CabbageBagSeed2", t = "Base.CabbageBagSeed2", w = 0.1, gr = "seeds" },
    { n = "CornBagSeed", t = "Base.CornBagSeed", w = 0.1, gr = "seeds" },
    { n = "KaleBagSeed", t = "Base.KaleBagSeed", w = 0.1, gr = "seeds" },
    { n = "OnionBagSeed", t = "Base.OnionBagSeed", w = 0.1, gr = "seeds" },
    { n = "GarlicBagSeed", t = "Base.GarlicBagSeed", w = 0.1, gr = "seeds" },
    { n = "WheatBagSeed", t = "Base.WheatBagSeed", w = 0.1, gr = "seeds" },
    { n = "LettuceBagSeed", t = "Base.LettuceBagSeed", w = 0.1, gr = "seeds" },
    { n = "CigarettePack", t = "Base.CigarettePack", w = 0.2, min = 2, max = 8 },
    { n = "CigaretteCarton", t = "Base.CigaretteCarton", w = 2.0, min = 0, max = 1 },
    { n = "Whiskey", t = "Base.Whiskey", w = 1.7, gr = "alcohol" },
    { n = "Vodka", t = "Base.Vodka", w = 2.0, gr = "alcohol" },
    { n = "Wine", t = "Base.Wine", w = 1.3, gr = "alcohol" },
    { n = "Wine2", t = "Base.Wine2", w = 1.3, gr = "alcohol" },
    { n = "BeerPack", t = "Base.BeerPack", w = 1.8, gr = "alcohol" },
    { n = "Coffee2", t = "Base.Coffee2", w = 1.0, min = 1, max = 3 },
    { n = "RadioReceiver", t = "Base.RadioReceiver", w = 0.1, min = 0, max = 2 },
    { n = "RadioTransmitter", t = "Base.RadioTransmitter", w = 0.1, min = 0, max = 2 },
    { n = "Amplifier", t = "Base.Amplifier", w = 0.3, min = 0, max = 2 },
    { n = "ElectricWire", t = "Base.ElectricWire", w = 0.1, min = 2, max = 5 },
    { n = "ElectronicsScrap", t = "Base.ElectronicsScrap", w = 0.1, min = 2, max = 5 },
    { n = "OutsideNews", t = "RadioSurvivor.OutsideNews", w = 0.2, min = 1, max = 1 },
}
Trade.GROUPS = { seeds = { min = 3, max = 8, kinds = 4 }, alcohol = { min = 1, max = 4 } }

local BY_LOWER = {}
for _, e in ipairs(Trade.SUPPLY) do BY_LOWER[string.lower(e.n)] = e end

local function log(msg) Const.log("trade: " .. msg) end

-- ================================================================ état

local volatile = {}

function Trade.resetForTests()
    volatile = {}
end

local function store()
    local root, persistent
    if S.data and not S.blocked then
        if type(S.data.trade) ~= "table" then S.data.trade = {} end
        root, persistent = S.data.trade, true
    else
        root, persistent = volatile, false
    end
    if type(root.books) ~= "table" then root.books = {} end
    if type(root.cordons) ~= "table" then root.cordons = {} end
    if type(root.rev) ~= "number" then root.rev = 0 end
    if type(root.sold) ~= "table" or type(root.sold.items) ~= "table" then root.sold = { passage = 0, items = {} } end
    if type(root.seed) ~= "number" or root.seed < 1 or root.seed > 2147483646 then
        -- Graine tirée une fois (base kahlua-lua.md, Park-Miller) : stock reproductible pour un passage donné.
        root.seed = ZombRand(46340) * 46340 + ZombRand(46340) + 1
        if persistent then S.dirty = true end
    end
    return root, persistent
end

local function touched(persistent)
    if persistent then S.dirty = true end
end

-- Clé d'un appelant : compte, plus le personnage du carnet s'il est connu (un nouveau personnage en solo, même clé
-- « solo », n'hérite pas des affaires du précédent ; même règle que RS_Memory).
local function bookKey(caller, cid)
    if type(caller) ~= "string" or caller == "" then return nil end
    if type(cid) == "string" and cid ~= "" then return caller .. "|" .. cid end
    return caller
end

-- Passage en cours : semaine de jeu, la même que l'édition du journal du dehors (RS_OutsideNews.currentEdition).
function Trade.passage()
    return News.currentEdition()
end

-- ================================================================ stock

-- Park-Miller (multiplicateur 48271, modulo 2^31 - 1) : produit sous 2^47, quotient sous 48271, juste en Kahlua.
local MOD = 2147483647
local function rng(seed, passage)
    local x = (seed + passage * 7919 + 1) % MOD
    if x < 1 then x = 1 end
    for _ = 1, 3 do x = (x * 48271) % MOD end
    return function(n)
        x = (x * 48271) % MOD
        return math.floor(x / MOD * n)
    end
end

-- Stock tiré d'un passage : { [nom] = quantité } (0 compris), même résultat pour la même graine et le même passage.
function Trade.drawStock(seed, passage)
    local roll = rng(seed, passage)
    local out, groups = {}, {}
    for _, e in ipairs(Trade.SUPPLY) do
        if e.gr then
            out[e.n] = 0
            groups[e.gr] = groups[e.gr] or {}
            local list = groups[e.gr]
            list[#list + 1] = e.n
        else
            out[e.n] = e.min + roll(e.max - e.min + 1)
        end
    end
    -- Graines : total, nombre de sortes (au plus kinds), sortes tirées sans remise, un sachet chacune puis le reste.
    local g = Trade.GROUPS.seeds
    local total = g.min + roll(g.max - g.min + 1)
    local kinds = math.min(math.min(g.kinds, total), 1 + roll(g.kinds))
    local pool = {}
    for i, name in ipairs(groups.seeds) do pool[i] = name end
    local chosen = {}
    for _ = 1, kinds do
        local i = 1 + roll(#pool)
        chosen[#chosen + 1] = table.remove(pool, i)
    end
    for _, name in ipairs(chosen) do out[name] = 1 end
    for _ = 1, total - kinds do
        local name = chosen[1 + roll(#chosen)]
        out[name] = out[name] + 1
    end
    -- Alcools : total de bouteilles, chacune d'une sorte tirée.
    local a = Trade.GROUPS.alcohol
    local bottles = a.min + roll(a.max - a.min + 1)
    for _ = 1, bottles do
        local name = groups.alcohol[1 + roll(#groups.alcohol)]
        out[name] = out[name] + 1
    end
    return out
end

function Trade.stock(passage)
    local root = store()
    return Trade.drawStock(root.seed, passage or Trade.passage())
end

-- Cordon tiré d'un passage (E13-T03) : CORDON_ODDS pour cent calme, patrouilles, cordon serré ; reproductible.
function Trade.drawCordon(seed, passage)
    local n = rng(seed + 104729, passage)(100)
    local acc = 0
    for i, odds in ipairs(Trade.CORDON_ODDS) do
        acc = acc + odds
        if n < acc then return Trade.CORDONS[i] end
    end
    return Trade.CORDONS[#Trade.CORDONS]
end

-- Cordon militaire du passage (1, 1.25 ou 1.5) : fixé par setCordon (hélicoptère entendu), sinon tiré du passage.
function Trade.cordon(passage)
    local root = store()
    passage = passage or Trade.passage()
    local c = root.cordons[tostring(passage)]
    if type(c) == "number" then return c end
    return Trade.drawCordon(root.seed, passage)
end

function Trade.setCordon(passage, level)
    local ok = false
    for _, c in ipairs(Trade.CORDONS) do
        if c == level then ok = true end
    end
    if not ok or type(passage) ~= "number" then return false end
    local root, persistent = store()
    root.cordons = { [tostring(passage)] = level }   -- seul le passage en cours compte
    touched(persistent)
    return true
end

-- Multiplicateur M d'un objet : cordon x rareté (stock tiré d'un exemplaire), borné à M_MAX.
local function multiplier(drawnQty, cordon)
    local m = cordon
    if drawnQty == 1 then m = m * Trade.RARITY end
    if m > Trade.M_MAX then m = Trade.M_MAX end
    return m
end

-- Une offre ouverte d'un passage passé devient « expired » (lecture paresseuse) et ne réserve plus rien.
local function expire(root, passage, persistent)
    for _, book in pairs(root.books) do
        local o = book.offer
        if type(o) == "table" and o.passage ~= passage and o.state == "open" then
            o.state = "expired"
            for _, d in ipairs(book.deals or {}) do
                if d.rev == o.rev and d.state == "open" then d.state = "expired" end
            end
            touched(persistent)
        end
    end
end

-- Quantités prises dans le passage : échanges faits (root.sold, passage en cours seulement) plus offres ouvertes du
-- passage, sauf celles des clés except et except2 (E13-T03 : offre du passage d'un autre membre de l'équipe).
local function reserved(root, passage, except, except2)
    local out = {}
    if root.sold.passage == passage then
        for name, q in pairs(root.sold.items) do out[name] = q end
    end
    for key, book in pairs(root.books) do
        local o = book.offer
        if key ~= except and key ~= except2 and type(o) == "table" and o.passage == passage and o.state == "open" then
            for _, l in ipairs(o.lines or {}) do
                out[l.n] = (out[l.n] or 0) + l.q
            end
        end
    end
    return out
end

-- Stock disponible pour la clé key : stock tiré moins ce qui est pris (son offre ouverte rendue : une nouvelle offre
-- remplace la sienne). Jamais négatif.
local function available(root, passage, key, key2)
    local drawn = Trade.drawStock(root.seed, passage)
    local taken = reserved(root, passage, key, key2)
    local out = {}
    for _, e in ipairs(Trade.SUPPLY) do
        local left = drawn[e.n] - (taken[e.n] or 0)
        if left < 0 then left = 0 end
        out[e.n] = left
    end
    return out, drawn
end

function Trade.available(caller, cid, passage)
    local root, persistent = store()
    passage = passage or Trade.passage()
    expire(root, passage, persistent)
    return (available(root, passage, bookKey(caller, cid)))
end

-- ================================================================ marge et mémoire

local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

-- Niveau de réputation du personnage appelant (E04-T11, réputation interne RS_Reputation) ; neutre sans personnage du
-- carnet ou sans état chargé.
function Trade.levelOf(cid)
    if type(cid) ~= "string" or cid == "" or not S.data or S.blocked then return "neutral" end
    return Rep.level(cid, S.data) or "neutral"
end

-- Marge la plus basse permise (E04-T11, Q13) : tricherie = MARGIN_MAX ; sinon base du niveau de réputation de
-- l'appelant (RS_Reputation.margin : bonne 0,10, neutre 0,25 = MARGIN_DEFAULT, mauvaise 0,40) moins MARGIN_STEP par
-- affaire conclue (rabais d'historique), jamais sous MARGIN_MIN.
local function marginFloor(book, cid)
    local done = 0
    for _, d in ipairs(type(book) == "table" and book.deals or {}) do
        if d.state == "cheated" then return Trade.MARGIN_MAX end
        if d.state == "done" then done = done + 1 end
    end
    local base = Rep.margin(Trade.levelOf(cid))
    local m = round2(base - Trade.MARGIN_STEP * done)
    if m < Trade.MARGIN_MIN then m = Trade.MARGIN_MIN end
    if m > Trade.MARGIN_MAX then m = Trade.MARGIN_MAX end
    return m
end

function Trade.marginRange(caller, cid)
    local root = store()
    local key = bookKey(caller, cid)
    return marginFloor(key and root.books[key], cid), Trade.MARGIN_MAX
end

local function itemsText(lines)
    local parts = {}
    for _, l in ipairs(lines) do parts[#parts + 1] = l.n .. ":" .. l.q end
    return table.concat(parts, ",")
end

local function bookOf(root, key, create)
    local book = root.books[key]
    if type(book) ~= "table" then
        if not create then return nil end
        -- Au plus MAX_BOOKS appelants : le moins récent (dernière révision) évincé, jamais une offre en cours.
        local count, oldestKey, oldestRev = 0, nil, nil
        for k, b in pairs(root.books) do
            count = count + 1
            local busy = type(b.offer) == "table" and b.offer.state == "open"
            if not busy and (oldestRev == nil or (b.lastRev or 0) < oldestRev) then oldestKey, oldestRev = k, b.lastRev or 0 end
        end
        if count >= Trade.MAX_BOOKS and oldestKey ~= nil then root.books[oldestKey] = nil end
        book = { deals = {}, lastRev = 0 }
        root.books[key] = book
    end
    if type(book.deals) ~= "table" then book.deals = {} end
    return book
end

-- ================================================================ passage réservé (E13-T03)

-- Âge du monde en heures de jeu (0 = 1er jour à 07:00).
function Trade.worldHours()
    local gt = getGameTime and getGameTime()
    local h = gt and tonumber(gt:getWorldAgeHours()) or 0
    if h == nil or h < 0 then h = 0 end
    return h
end

-- Fin (exclue) d'un passage en heures de jeu : le passage n couvre [WEEK_HOURS x (n - 1), WEEK_HOURS x n).
function Trade.passageEnd(passage)
    return passage * News.WEEK_HOURS
end

-- Début (âge du monde) de la fenêtre du rendez-vous pour une réservation faite à `hours` dans `passage` : la première
-- heure WINDOW_START du jeu au moins LEAD_HOURS plus tard ; nil si la fenêtre finit après la semaine du passage.
function Trade.rendezvous(hours, passage)
    local start = 24 * math.ceil((hours + Trade.LEAD_HOURS + 7 - Trade.WINDOW_START) / 24) - 7 + Trade.WINDOW_START
    if start + Trade.WINDOW_HOURS > Trade.passageEnd(passage) then return nil end
    return start
end

-- Joueur en ligne d'un appelant (compte ; solo : le joueur local), ou nil.
local function playerOf(caller)
    if not isServer() then return getPlayer and getPlayer() or nil end
    local list = getOnlinePlayers and getOnlinePlayers()
    if not list then return nil end
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p and p:getUsername() == caller then return p end
    end
    return nil
end

-- Équipe d'un appelant : identifiant RS_Factions (faction vanilla ou équipe personnelle) de son joueur ; sans joueur
-- en ligne ni état privé, « caller:<compte> ». nil sans appelant.
function Trade.teamOf(caller, player)
    if type(caller) ~= "string" or caller == "" then return nil end
    player = player or playerOf(caller)
    local id = player and Factions.idOf(player) or nil
    if type(id) == "string" and id ~= "" then return id end
    return "caller:" .. caller
end

local function currentRun(root, passage)
    local r = root.run
    if type(r) == "table" and r.passage == passage then return r end
    return nil
end

-- État du passage pour une équipe : "free" (pas réservé, une nuit est encore possible), "yours" (réservé par cette
-- équipe, rendez-vous à venir ou barque arrivée), "taken" (une autre équipe), "over" (annulé, fait, ou trop tard dans
-- la semaine) ; et le passage réservé (table) s'il existe.
local function runStatus(root, passage, team, hours)
    local r = currentRun(root, passage)
    if r == nil then
        if Trade.rendezvous(hours, passage) == nil then return "over", nil end
        return "free", nil
    end
    if r.state ~= "booked" and r.state ~= "arrived" then return "over", r end
    if team ~= nil and r.team == team then return "yours", r end
    return "taken", r
end

-- ================================================================ offre

-- Offre ouverte d'un livre remplacée (et son affaire) : sa réserve est rendue.
local function replaceOpen(book)
    local old = type(book) == "table" and book.offer or nil
    if type(old) == "table" and old.state == "open" then
        old.state = "replaced"
        for _, d in ipairs(book.deals or {}) do
            if d.rev == old.rev and d.state == "open" then d.state = "replaced" end
        end
    end
end

-- Lignes d'une offre depuis le texte items : { { e = entrée du stock, q = quantité } }, ou nil (forme invalide :
-- nom hors des caractères admis, quantité non entière ou hors 1..MAX_QTY, doublon, trop de lignes, vide). Un nom
-- inconnu du stock est gardé (e = nil) : refus not_in_stock, pas bad_params.
function Trade.parseItems(text)
    if type(text) ~= "string" or string.len(text) > Actions.MAX_PARAM_CHARS then return nil end
    local lines, seen = {}, {}
    for token in string.gmatch(text .. ",", "([^,]*),") do
        local t = string.gsub(token, "^%s+", "")
        t = string.gsub(t, "%s+$", "")
        local name, qty = string.match(t, "^([%w_%.]+)%s*:%s*(%d+)$")
        if name == nil then
            name = string.match(t, "^([%w_%.]+)$")
            qty = name and "1" or nil
        end
        if name == nil then return nil end
        local q = tonumber(qty)
        if q == nil or q < 1 or q > Trade.MAX_QTY or math.floor(q) ~= q then return nil end
        local low = string.lower(name)
        low = string.gsub(low, "^base%.", "")
        low = string.gsub(low, "^radiosurvivor%.", "")
        if seen[low] then return nil end
        seen[low] = true
        lines[#lines + 1] = { e = BY_LOWER[low], q = q, name = name }
        if #lines > Trade.MAX_LINES then return nil end
    end
    if #lines == 0 then return nil end
    return lines
end

-- Évalue une proposition sans rien écrire. Rend l'offre { passage, lines = { { n, t, q, v, w, m, price } }, margin,
-- price, weight, cordon } ou nil et la raison. alsoKey : livre dont l'offre ouverte ne compte pas comme prise (offre
-- du passage d'un autre membre de l'équipe, remplacée si celle-ci est figée).
function Trade.evaluate(caller, cid, items, margin, alsoKey)
    local key = bookKey(caller, cid)
    if key == nil then return nil, "failed" end
    local parsed = Trade.parseItems(items)
    if parsed == nil then return nil, "bad_params" end
    local root, persistent = store()
    local passage = Trade.passage()
    expire(root, passage, persistent)
    local low = marginFloor(root.books[key], cid)
    if margin == nil then margin = low end
    if type(margin) ~= "number" or margin ~= margin then return nil, "bad_margin" end
    margin = round2(margin)
    if margin < low - 1e-9 or margin > Trade.MARGIN_MAX + 1e-9 then return nil, "bad_margin" end
    local avail, drawn = available(root, passage, key, alsoKey)
    local cordon = Trade.cordon(passage)
    local offer = { passage = passage, lines = {}, margin = margin, price = 0, weight = 0, cordon = cordon }
    for _, p in ipairs(parsed) do
        if p.e == nil or avail[p.e.n] == nil or avail[p.e.n] <= 0 then return nil, "not_in_stock" end
        if p.q > avail[p.e.n] then return nil, "over_stock" end
        local v = TV.sellValue(p.e.t)
        if v <= 0 then return nil, "not_in_stock" end
        local m = multiplier(drawn[p.e.n], cordon)
        local price = TV.linePrice(v, p.q, (1 + margin) * m)
        offer.lines[#offer.lines + 1] = { n = p.e.n, t = p.e.t, q = p.q, v = v, w = p.e.w, m = m, price = price }
        offer.price = offer.price + price
        offer.weight = offer.weight + p.e.w * p.q
    end
    offer.weight = math.floor(offer.weight * 10 + 0.5) / 10
    if offer.weight > Trade.CAP_KG + 1e-9 then return nil, "over_weight" end
    if offer.price > Trade.CAP_POINTS then return nil, "over_cap" end
    return offer
end

-- Fige une offre (évaluée ici même) pour l'appelant : révision nouvelle, ancienne offre du même appelant remplacée,
-- quantités réservées, affaire ajoutée à la mémoire. Rend l'offre figée (copie) ou nil et la raison ; un refus est
-- gardé (dernier refus, envoyé au LLM avec le contexte suivant).
-- E13-T03 : team (équipe de l'appelant, Trade.teamOf) : passage réservé par une autre équipe -> booked ; annulé, fait
-- ou trop tard dans la semaine -> run_over ; libre -> l'offre figée le réserve pour team (troisième valeur rendue :
-- true) ; déjà à team -> l'offre devient celle du passage (l'offre ouverte d'un autre membre est remplacée). via :
-- { voice, khz } de la demande (voix qui annoncera une annulation). Sans team : aucune réservation (E13-T02).
function Trade.propose(caller, cid, items, margin, team, via)
    local key = bookKey(caller, cid)
    local root, persistent = store()
    local hours, status, run, offer, why = Trade.worldHours(), nil, nil, nil, nil
    if team ~= nil and key ~= nil then
        expire(root, Trade.passage(), persistent)
        status, run = runStatus(root, Trade.passage(), team, hours)
        if status == "taken" then why = "booked" elseif status == "over" then why = "run_over" end
    end
    if why == nil then
        local other = run and run.key ~= key and run.key or nil
        offer, why = Trade.evaluate(caller, cid, items, margin, other)
    end
    if offer == nil then
        if key ~= nil then
            local book = bookOf(root, key, true)
            book.refused = { reason = why, items = type(items) == "string" and items or "" }
            touched(persistent)
        end
        log("offer refused (" .. tostring(why) .. ") caller=" .. tostring(caller))
        return nil, why
    end
    local book = bookOf(root, key, true)
    replaceOpen(book)
    if run ~= nil and run.key ~= key then replaceOpen(root.books[run.key]) end
    root.rev = root.rev + 1
    offer.rev = root.rev
    offer.state = "open"
    book.offer = offer
    book.lastRev = offer.rev
    book.refused = nil
    local deals = book.deals
    deals[#deals + 1] = { rev = offer.rev, passage = offer.passage, items = itemsText(offer.lines), price = offer.price,
        state = "open" }
    while #deals > Trade.MAX_DEALS do table.remove(deals, 1) end
    local booked = false
    if status == "free" then
        via = type(via) == "table" and via or {}
        run = { passage = offer.passage, team = team, state = "booked", bookedAt = hours,
            start = Trade.rendezvous(hours, offer.passage), voice = via.voice, khz = via.khz }
        root.run = run
        booked = true
    end
    if run ~= nil then
        run.key, run.caller, run.cid, run.rev = key, caller, cid, offer.rev
    end
    touched(persistent)
    log("offer " .. offer.rev .. " frozen for " .. tostring(caller) .. ": " .. itemsText(offer.lines) .. " for "
        .. offer.price .. " points (passage " .. offer.passage .. ")")
    if booked then
        log("run " .. run.passage .. " booked by team " .. tostring(team) .. " (" .. tostring(caller)
            .. "), meeting at world hour " .. run.start)
    end
    return Trade.offerOf(caller, cid), nil, booked
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

-- Offre courante de l'appelant (copie), ou nil.
function Trade.offerOf(caller, cid)
    local key = bookKey(caller, cid)
    if key == nil then return nil end
    local root, persistent = store()
    expire(root, Trade.passage(), persistent)
    local book = root.books[key]
    if type(book) ~= "table" or type(book.offer) ~= "table" then return nil end
    return copy(book.offer)
end

-- Affaires passées de l'appelant (copie, de la plus ancienne à la plus récente).
function Trade.deals(caller, cid)
    local key = bookKey(caller, cid)
    local root = store()
    local book = key and root.books[key]
    return copy(type(book) == "table" and book.deals or {})
end

-- Issue d'une offre ouverte (E13-T04) : "done" (échange fait : ses quantités restent prises pour le passage, même si
-- l'appelant fait ensuite une autre offre), "cheated" ou "cancelled" (réserve rendue). Rend true si l'offre rev de
-- l'appelant était ouverte.
local OUTCOMES = { done = true, cheated = true, cancelled = true }
function Trade.close(caller, cid, rev, outcome)
    local key = bookKey(caller, cid)
    if key == nil or not OUTCOMES[outcome] then return false end
    local root, persistent = store()
    expire(root, Trade.passage(), persistent)
    local book = root.books[key]
    local o = type(book) == "table" and book.offer or nil
    if type(o) ~= "table" or o.rev ~= rev or o.state ~= "open" then return false end
    o.state = outcome
    if outcome == "done" then
        if root.sold.passage ~= o.passage then root.sold = { passage = o.passage, items = {} } end
        for _, l in ipairs(o.lines) do
            root.sold.items[l.n] = (root.sold.items[l.n] or 0) + l.q
        end
    end
    for _, d in ipairs(book.deals) do
        if d.rev == rev then d.state = outcome end
    end
    -- L'offre du passage réservé close : le passage est fini (E13-T03).
    local r = root.run
    if type(r) == "table" and r.key == key and r.rev == rev and (r.state == "booked" or r.state == "arrived") then
        r.state, r.endedAt = outcome, Trade.worldHours()
        if outcome == "cancelled" and r.reason == nil then r.reason = "cancelled" end
    end
    touched(persistent)
    log("offer " .. tostring(rev) .. " of " .. tostring(caller) .. " closed: " .. outcome)
    return true
end

-- ================================================================ suivi du passage (E13-T03, appelé par RS_TradeRun)

-- Passage réservé le plus récent (copie, quel que soit son passage), ou nil.
function Trade.lastRun()
    local root = store()
    if type(root.run) ~= "table" then return nil end
    return copy(root.run)
end

-- Passage réservé du passage en cours (copie), ou nil.
function Trade.runOf(passage)
    local root = store()
    local r = currentRun(root, passage or Trade.passage())
    return r and copy(r) or nil
end

-- État du passage pour une équipe (voir runStatus) et copie du passage réservé.
function Trade.runStatus(team, passage, hours)
    local root = store()
    local status, r = runStatus(root, passage or Trade.passage(), team, hours or Trade.worldHours())
    return status, r and copy(r) or nil
end

-- Annule le passage réservé encore attendu (state booked) : raison notée, offre du passage close « cancelled »
-- (réserve rendue). Rend la copie du passage annulé, ou nil s'il n'y avait rien à annuler.
function Trade.cancelRun(reason)
    local root, persistent = store()
    local r = root.run
    if type(r) ~= "table" or r.state ~= "booked" then return nil end
    r.reason = reason
    local o = r.key and type(root.books[r.key]) == "table" and root.books[r.key].offer or nil
    if not (type(o) == "table" and o.rev == r.rev and o.state == "open"
            and Trade.close(r.caller, r.cid, r.rev, "cancelled")) then
        r.state, r.endedAt = "cancelled", Trade.worldHours()
    end
    touched(persistent)
    log("run " .. tostring(r.passage) .. " of team " .. tostring(r.team) .. " cancelled: " .. tostring(reason))
    return copy(r)
end

-- La barque est au ponton (signal vu) : state arrived. Rend true si le passage était attendu.
function Trade.arrive(how)
    local root, persistent = store()
    local r = root.run
    if type(r) ~= "table" or r.state ~= "booked" then return false end
    r.state, r.arrivedAt, r.signal = "arrived", Trade.worldHours(), how
    touched(persistent)
    log("run " .. tostring(r.passage) .. ": boat at the pier for team " .. tostring(r.team) .. " (" .. tostring(how)
        .. ")")
    return true
end

-- Issue de l'échange d'un passage dont la barque est au ponton (state arrived, E13-T04) : outcome done, cheated ou
-- cancelled, raison notée (done, recovered, cheated, no_drop, no_offer), détail facultatif (table de nombres et de
-- textes) ; l'offre du passage est close avec la même issue (done : quantités prises ; cheated : marge plancher au
-- plus haut). Rend la copie du passage clos, ou nil s'il n'y avait pas de barque au ponton.
function Trade.finishRun(outcome, reason, detail)
    if not OUTCOMES[outcome] then return nil end
    local root, persistent = store()
    local r = root.run
    if type(r) ~= "table" or r.state ~= "arrived" then return nil end
    r.reason = reason
    if type(detail) == "table" then r.exchange = detail end
    local o = r.key and type(root.books[r.key]) == "table" and root.books[r.key].offer or nil
    if not (type(o) == "table" and o.rev == r.rev and o.state == "open" and Trade.close(r.caller, r.cid, r.rev, outcome))
    then
        r.state, r.endedAt = outcome, Trade.worldHours()
    end
    touched(persistent)
    log("run " .. tostring(r.passage) .. " of team " .. tostring(r.team) .. " finished: " .. outcome .. " ("
        .. tostring(reason) .. ")")
    return copy(r)
end

-- Tirage 0..99 de la patrouille d'un passage (reproductible : même graine, même passage, même résultat).
function Trade.patrolRoll(passage)
    local root = store()
    return rng(root.seed + 7, passage)(100)
end

-- Hélicoptère vanilla entendu (RS_TradeRun, signature OnWorldSound) à `hours` : noté pour le passage en cours ; la
-- première fois dans le passage, le cordon monte d'un cran (jamais au-delà du dernier). Rend true si le cordon monte.
function Trade.noteHelicopter(hours)
    local root, persistent = store()
    local passage = Trade.passage()
    local heli = root.heli
    if type(heli) ~= "table" or heli.passage ~= passage then
        heli = { passage = passage, raised = false }
        root.heli = heli
    end
    local old = type(heli.at) == "number" and heli.at or -1
    heli.at = hours
    if hours - old >= 0.25 then touched(persistent) end
    if heli.raised then return false end
    heli.raised = true
    local c = Trade.cordon(passage)
    local up = c
    for i, level in ipairs(Trade.CORDONS) do
        if level == c and Trade.CORDONS[i + 1] then up = Trade.CORDONS[i + 1] end
    end
    if up ~= c then Trade.setCordon(passage, up) end
    touched(persistent)
    log("helicopter heard in passage " .. passage .. ": cordon " .. c .. " -> " .. up)
    return up ~= c
end

-- Vrai si un hélicoptère a été entendu dans le passage en cours à partir de l'heure `since`.
function Trade.helicopterSince(since)
    local root = store()
    local heli = root.heli
    return type(heli) == "table" and heli.passage == Trade.passage() and type(heli.at) == "number"
        and heli.at >= since
end

-- ================================================================ contexte du LLM

local function allowsTrade(sheet)
    if type(sheet) ~= "table" or type(sheet.actions) ~= "table" then return false end
    for _, a in ipairs(sheet.actions) do
        if a == Trade.ACTION then return true end
    end
    return false
end

-- Ce que le passeur prend, par classe : texte « Nom V, Nom V » trié par nom (barème RS_TradeValues).
local takesCache = nil
local function takes()
    if takesCache then return takesCache end
    local byClass = {}
    for full, e in pairs(TV.VALUES) do
        byClass[e.k] = byClass[e.k] or {}
        local list = byClass[e.k]
        local text = string.sub(full, 6) .. " " .. e.v
        if e.lot then text = text .. " per " .. e.lot end
        if e.cap then text = text .. " (max " .. e.cap .. ")" end
        if e.cond then text = text .. " (condition " .. math.floor(e.cond * 100 + 0.5) .. "%+)" end
        list[#list + 1] = text
    end
    takesCache = {}
    for _, t in ipairs(Trade.TAKES) do
        local list = byClass[t.k] or {}
        table.sort(list)
        takesCache[#takesCache + 1] = { k = t.k, cap = t.cap, pieces = t.pieces, items = table.concat(list, ", ") }
    end
    return takesCache
end

-- Contexte du passeur pour une demande de l'appelant (table), ou nil si la fiche n'autorise pas propose_trade.
function Trade.context(sheet, caller, cid)
    if not allowsTrade(sheet) then return nil end
    local key = bookKey(caller, cid)
    local root, persistent = store()
    local passage = Trade.passage()
    expire(root, passage, persistent)
    local book = key and root.books[key] or nil
    local low = marginFloor(book, cid)
    local avail, drawn = available(root, passage, key)
    local cordon = Trade.cordon(passage)
    local ctx = { passage = passage, cap = Trade.CAP_POINTS, kg = Trade.CAP_KG, marginMin = low,
        marginMax = Trade.MARGIN_MAX, cordon = cordon, stock = {}, takes = takes(), deals = {} }
    for _, e in ipairs(Trade.SUPPLY) do
        local n = avail[e.n]
        if n > 0 then
            local v = TV.sellValue(e.t)
            ctx.stock[#ctx.stock + 1] = { n = e.n, q = n, v = v, w = e.w,
                unit = TV.linePrice(v, 1, (1 + low) * multiplier(drawn[e.n], cordon)) }
        end
    end
    if type(book) == "table" then
        local o = book.offer
        if type(o) == "table" and o.passage == passage then
            ctx.offer = { rev = o.rev, items = itemsText(o.lines), price = o.price, margin = o.margin,
                weight = o.weight, state = o.state }
        end
        local deals = book.deals or {}
        for i = math.max(1, #deals - Trade.DEALS_SENT + 1), #deals do
            local d = deals[i]
            ctx.deals[#ctx.deals + 1] = { passage = d.passage, items = d.items, price = d.price, state = d.state }
        end
        if type(book.refused) == "table" then ctx.refused = book.refused.reason end
    end
    ctx.run = Trade.runContext(Trade.teamOf(caller), passage, Trade.worldHours())
    return ctx
end

-- Passage de la semaine vu par l'équipe de l'appelant (E13-T03), pour le LLM : status (free, yours, taken, over),
-- heures de la fenêtre (from, to), days = jours de calendrier jusqu'à la nuit du rendez-vous (free : si réservé
-- maintenant), inHours = heures avant son début ; yours : state (booked, arrived) et place (description du ponton) ;
-- over : reason (patrol, helicopter, storm, late, done, cheated, cancelled ; closed = trop tard dans la semaine).
-- Le lieu n'est donné qu'à l'équipe qui a réservé ; jamais de coordonnée.
function Trade.runContext(team, passage, hours)
    local root = store()
    local status, r = runStatus(root, passage, team, hours)
    local out = { status = status, from = Trade.WINDOW_START, to = Trade.WINDOW_START + Trade.WINDOW_HOURS }
    local start = nil
    if status == "free" then
        start = Trade.rendezvous(hours, passage)
    elseif status == "yours" then
        start = r.start
        out.state, out.place = r.state, Trade.PIER.desc
    elseif status == "over" then
        out.reason = r and (r.reason or r.state) or "closed"
    end
    if start ~= nil then
        local hourOfDay = (hours + 7) % 24
        out.days = math.max(0, math.floor((hourOfDay + start - hours) / 24))
        out.inHours = math.floor((start - hours) * 10 + 0.5) / 10
    end
    return out
end

-- Champ trade= d'une demande radio : hexadécimal RSV2 du contexte, ou nil.
function Trade.field(sheet, caller, cid)
    local ctx = Trade.context(sheet, caller, cid)
    if ctx == nil then return nil end
    return Codec.hexBytes(Codec.encodeBytes(ctx))
end

-- ================================================================ action

local PARAMS = { items = true, margin = true }

local function validate(params)
    if type(params.items) ~= "string" then return false end
    for k, v in pairs(params) do
        if not PARAMS[k] then return false end
        if k == "margin" and type(v) ~= "number" then return false end
    end
    return Trade.parseItems(params.items) ~= nil
end

local function execute(params, ctx)
    if type(ctx) ~= "table" or type(ctx.caller) ~= "string" then return false, "failed" end
    -- E13-T03 : l'offre figée réserve le passage pour l'équipe de l'appelant ; RS_TradeRun en est averti (repère).
    local team = Trade.teamOf(ctx.caller, ctx.player)
    local offer, why, booked = Trade.propose(ctx.caller, ctx.cid, params.items, params.margin, team,
        { voice = ctx.voice, khz = ctx.khz })
    if offer == nil then return false, why end
    if booked and type(Trade.onBooked) == "function" then Trade.onBooked(Trade.lastRun(), ctx) end
    return true
end

function Trade.register()
    return Actions.register(Trade.ACTION, { validate = validate, cooldownMs = Trade.COOLDOWN_MS, execute = execute })
end

Trade.register()

return Trade
