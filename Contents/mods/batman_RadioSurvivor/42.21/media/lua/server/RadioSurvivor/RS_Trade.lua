-- Radio Survivor : livre des marchands radio (E13-T02, E13-T03 ; E20-T07, ADR D07 : troc declare dans la fiche, un
-- etat par marchand). Barème : docs/specifications-techniques/passeur-table.md (sections 1 et 3), code
-- shared/CoreAI/CA_TradeValues.lua (valeur V de chaque objet). Format de la section [trade] :
-- docs/specifications-techniques/persona-format.md.
--
-- Marchand = voix dont la fiche a une section [trade] (RS_Persona : sheet.trade = spec) : lieux de rendez-vous
-- (use=landing), mode d'arrivee (registre RS_TradeArrivals), cadence (every_days), fenetre du rendez-vous (from,
-- hours), delai hors de vue (delayHours), marges (marginMin, marginMax), stock (items { n, t, w, min, max, gr } et
-- groups { id, min, max, kinds }). Les voix chargees viennent d'un port injecte (Trade.useVoices : get(id) -> fiche,
-- ids() -> identifiants ; RS_TradeRun.install branche RS_Personas). Aucune voix ni aucun lieu dans ce code.
--
-- Le LLM du marchand negocie a la radio et propose un accord par l'action `propose_trade` (E23-T06, ADR D01) :
--     { type = "propose_trade", gives = "Antibiotics:2,Battery:4", wants = "MoneyBundle:3,GoldCoin:1" }
--   gives : texte, au plus MAX_PARAM_CHARS (64) caracteres : ce que le marchand laisse, tire de son stock,
--           « Nom:quantite » separes par des virgules (quantite 1 si omise ; nom du stock, module facultatif, casse
--           indifferente) ;
--   wants : meme forme : ce que l'appelant doit deposer, parmi ce que la fiche accepte en paiement (accept= de la
--           section [trade], resolu par RS_Persona en spec.accepts : objets a valeur de vente ; module facultatif).
-- Le joueur ne voit jamais de points : il convient de deux listes a la radio, et la liste convenue s'inscrit dans son
-- carnet (Trade.onAgreed). Le serveur garde le bareme pour refuser un accord inequitable (Trade.propose, voix de la
-- demande) : chaque objet de gives au stock du passage et disponible (stock tire moins les offres en cours ou conclues
-- des autres appelants), charge au plus CAP_KG, prix au plus CAP_POINTS ; chaque objet de wants accepte par la fiche
-- (refus not_taken), au plus son plafond par passage (cap du bareme, over_count), au plus CAP_PAY_KG au total
-- (pay_weight) ;
-- valeur de wants au moins le prix de gives (unfair). Prix : par ligne, ceil(V x quantite x (1 + marge) x M), marge =
-- la plus basse permise a cet appelant, M = cordon x rarete borne a M_MAX, rarete RARITY si le stock tire de l'objet
-- est d'un seul exemplaire. Valeur de wants : somme de V x quantite (billets : V par lot entier de e.lot). Accepte :
-- accord fige (revision rev, unique pour tout le serveur), qui remplace l'accord precedent du meme appelant chez ce
-- marchand ; ses quantites sont reservees. Accord fige a l'arrivee (ADR D04) : passage arrive, nouvelle offre refusee
-- (frozen).
-- Memoire des affaires : par marchand et par appelant, les MAX_DEALS derniers accords. Avec la reputation de
-- l'appelant (RS_Config.TradeMargin), elle fixe la marge (base moins MARGIN_STEP par affaire conclue, bornee aux marges
-- de la fiche ; la plus haute apres une tricherie).
--
-- Passage reserve (E13-T03) : un passage par periode de every_days jours de jeu et par marchand ; le premier accord
-- fige d'un passage le reserve pour l'equipe de l'appelant (CA_Teams.idOf ; sans joueur « caller:<compte> »). Une
-- autre equipe est refusee (booked) ; annule, fait ou trop tard dans la periode : run_over. Rendez-vous : un lieu
-- landing de la fiche (tire par passage s'il y en a plusieurs), la premiere fenetre au moins LEAD_HOURS apres la
-- reservation, dans la periode. Cordon (multiplicateur de prix cache) : tire par passage. Deux marchands ne partagent
-- rien : stock, livres, passage, cordon.
-- Suivi du rendez-vous : RS_TradeRun.lua ; echange sans contact : RS_TradeExchange.lua (Trade.finishRun) ; contenu
-- du lieu note a la premiere vue apres la reservation (Trade.noteDeposit, E23-T07).
-- Etat prive du serveur S.data.trade = { rev, traders = { [voix] = { books, cordons, sold, seed, run } } }
-- (RS_State), jamais en ModData ; sans etat charge, table en memoire. Pas de reprise d'un ancien etat (ADR D11).
-- Contexte du LLM : RadioSurvivor_Server joint Trade.field a chaque demande d'une voix qui autorise propose_trade
-- (champ trade=, hexadecimal RSV2). Le lieu n'est donne qu'a l'equipe qui a reserve ; jamais de coordonnee.
-- Code ASCII seulement (litteraux non ASCII changes en U+FFFD par le lexeur Kahlua).
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Codec = require "CoreAI/CA_Codec"
local S = require "RadioSurvivor/RS_State"
local Actions = require "RadioSurvivor/RS_Actions"
local TV = require "CoreAI/CA_TradeValues"
-- E21-T06: sale value of the outside news (section 3, one issue per visit: E13-T05, RS_OutsideNewsServer.lua).
TV.registerSellOnly("RadioSurvivor.OutsideNews", { v = 2, k = "supply", cap = 1 })
local Factions = require "CoreAI/CA_Teams" -- E18-T20: team ids kept by the core mod
local Rep = require "CoreAI/CA_Reputation"
local Config = require "RadioSurvivor/RS_Config"
local Arrivals = require "RadioSurvivor/RS_TradeArrivals"
local ItemWeights = require "RadioSurvivor/RS_ItemWeights"

local Trade = {}

Trade.ACTION = "propose_trade"
Trade.COOLDOWN_MS = 0          -- budget.propose_trade de la fiche et 3 actions par reponse suffisent
Trade.MARGIN_DEFAULT = 0.25
Trade.MARGIN_STEP = 0.05       -- baisse de la marge la plus basse par affaire conclue
Trade.M_MAX = 1.75
Trade.RARITY = 1.25
Trade.CORDONS = { 1.0, 1.25, 1.5 }
Trade.CAP_POINTS = 120         -- prix au plus de ce que le marchand laisse par passage (section 1)
Trade.CAP_KG = 10              -- poids au plus de ce que le marchand laisse
Trade.MAX_LINES = 8            -- objets distincts au plus par liste
Trade.MAX_QTY = 99
Trade.MAX_DEALS = 8            -- affaires gardees par appelant
Trade.DEALS_SENT = 5           -- affaires envoyees au LLM
Trade.MAX_BOOKS = 50           -- appelants gardes par marchand, le moins recent evince
Trade.CAP_PAY_KG = 20          -- poids au plus de ce que l'appelant depose (place dans la barque, section 1)
Trade.REASONS = { "bad_params", "not_in_stock", "over_stock", "over_weight", "over_cap", "not_taken", "over_count",
    "pay_weight", "unfair", "failed", "booked", "run_over", "frozen" }
Trade.LEAD_HOURS = 6           -- au moins 6 heures de jeu entre la reservation et le rendez-vous
Trade.CORDON_ODDS = { 60, 30, 10 }   -- pour cent : calme, patrouilles, cordon serre (Trade.CORDONS)
-- Fin d'un passage pour le LLM (status over), hors causes du mode d'arrivee : texte anglais sans chiffre.
Trade.REASON_TEXTS = {
    late = "nobody showed the signal in time", done = "the trade is done", recovered = "the trade is done",
    cheated = "they did not bring everything agreed", short = "they did not bring everything agreed",
    cancelled = "it was called off", no_offer = "it was called off",
    no_drop = "nobody left the payment at the landing", watched = "someone stayed in sight of the landing",
    closed = "it is too late in this period for a run",
}
-- Ordre des classes du bareme (CA_TradeValues) dans ce que le marchand accepte, pour le contexte du LLM ; papers :
-- papiers a un nom seulement (RS_TradeExchange). Une classe absente de cette liste suit, par nom.
Trade.TAKES = { "valuables", "images", "papers", "military", "ammo", "medical", "food", "supply" }

local function log(msg) Const.log("trade: " .. msg) end

-- ================================================================ voix (port injecte)

local voices = nil

-- Port des voix chargees : { get = function(id) -> fiche, ids = function() -> liste d'identifiants }.
function Trade.useVoices(port)
    voices = port
end

-- Spec [trade] de la voix (sheet.trade), ou nil.
function Trade.specOf(id)
    local sheet = voices and type(id) == "string" and voices.get(id) or nil
    return type(sheet) == "table" and type(sheet.trade) == "table" and sheet.trade or nil
end

-- Identifiants des voix chargees qui ont une section [trade], dans l'ordre du port.
function Trade.traderIds()
    local out = {}
    for _, id in ipairs(voices and voices.ids() or {}) do
        if Trade.specOf(id) then out[#out + 1] = id end
    end
    return out
end

-- ================================================================ etat

local volatile = {}

function Trade.resetForTests()
    volatile = {}
end

local function rootOf()
    local root, persistent
    if S.data and not S.blocked then
        if type(S.data.trade) ~= "table" then S.data.trade = {} end
        root, persistent = S.data.trade, true
    else
        root, persistent = volatile, false
    end
    if type(root.traders) ~= "table" then root.traders = {} end
    if type(root.rev) ~= "number" then root.rev = 0 end
    return root, persistent
end

-- Etat du marchand id (cree au besoin), persistance, racine.
local function store(id)
    local root, persistent = rootOf()
    local t = root.traders[id]
    if type(t) ~= "table" then
        t = {}
        root.traders[id] = t
    end
    if type(t.books) ~= "table" then t.books = {} end
    if type(t.cordons) ~= "table" then t.cordons = {} end
    if type(t.sold) ~= "table" or type(t.sold.items) ~= "table" then t.sold = { passage = 0, items = {} } end
    if type(t.seed) ~= "number" or t.seed < 1 or t.seed > 2147483646 then
        -- Graine tiree une fois par marchand (base kahlua-lua.md, Park-Miller) : stock reproductible par passage.
        t.seed = ZombRand(46340) * 46340 + ZombRand(46340) + 1
        if persistent then S.dirty = true end
    end
    return t, persistent, root
end

local function touched(persistent)
    if persistent then S.dirty = true end
end

-- Cle d'un appelant : compte, plus le personnage du carnet s'il est connu (meme regle que RS_Memory).
local function bookKey(caller, cid)
    if type(caller) ~= "string" or caller == "" then return nil end
    if type(cid) == "string" and cid ~= "" then return caller .. "|" .. cid end
    return caller
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

-- ================================================================ calendrier

-- Age du monde en heures de jeu (0 = 1er jour a 07:00).
function Trade.worldHours()
    local gt = getGameTime and getGameTime()
    local h = gt and tonumber(gt:getWorldAgeHours()) or 0
    if h == nil or h < 0 then h = 0 end
    return h
end

local function periodHours(spec)
    return 24 * spec.everyDays
end

local function passageAt(spec, hours)
    return math.floor(hours / periodHours(spec)) + 1
end

-- Passage en cours du marchand : periode de every_days jours de jeu (7 : la semaine du journal du dehors).
function Trade.passage(id)
    local spec = Trade.specOf(id)
    return spec and passageAt(spec, Trade.worldHours()) or nil
end

local function passageEnd(spec, passage)
    return passage * periodHours(spec)
end

function Trade.passageEnd(id, passage)
    local spec = Trade.specOf(id)
    return spec and passageEnd(spec, passage) or nil
end

-- Debut (age du monde) de la fenetre du rendez-vous pour une reservation faite a `hours` dans `passage` : la premiere
-- heure spec.from du jeu au moins LEAD_HOURS plus tard ; nil si la fenetre finit apres la periode du passage.
local function rendezvous(spec, hours, passage)
    local start = 24 * math.ceil((hours + Trade.LEAD_HOURS + 7 - spec.from) / 24) - 7 + spec.from
    if start + spec.hours > passageEnd(spec, passage) then return nil end
    return start
end

function Trade.rendezvous(id, hours, passage)
    local spec = Trade.specOf(id)
    return spec and rendezvous(spec, hours, passage) or nil
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

-- Un groupe tire : total, puis (kinds) sortes tirees sans remise, un exemplaire chacune puis le reste parmi elles ;
-- sans kinds, chaque exemplaire d'une sorte tiree parmi toutes.
local function drawGroup(out, group, names, roll)
    local total = group.min + roll(group.max - group.min + 1)
    if not group.kinds then
        for _ = 1, total do
            local name = names[1 + roll(#names)]
            out[name] = out[name] + 1
        end
        return
    end
    local kinds = math.min(math.min(group.kinds, total), 1 + roll(group.kinds))
    local pool = {}
    for i, name in ipairs(names) do pool[i] = name end
    local chosen = {}
    for _ = 1, kinds do
        chosen[#chosen + 1] = table.remove(pool, 1 + roll(#pool))
    end
    for _, name in ipairs(chosen) do out[name] = 1 end
    for _ = 1, total - kinds do
        local name = chosen[1 + roll(#chosen)]
        out[name] = out[name] + 1
    end
end

-- Stock tire d'un passage : { [nom] = quantite } (0 compris), meme resultat pour la meme graine et le meme passage.
-- Objets hors groupe dans l'ordre de la fiche, puis les groupes dans leur ordre.
function Trade.drawStock(spec, seed, passage)
    local roll = rng(seed, passage)
    local out, members = {}, {}
    for _, e in ipairs(spec.items) do
        if e.gr then
            out[e.n] = 0
            members[e.gr] = members[e.gr] or {}
            local list = members[e.gr]
            list[#list + 1] = e.n
        else
            out[e.n] = e.min + roll(e.max - e.min + 1)
        end
    end
    for _, group in ipairs(spec.groups) do
        drawGroup(out, group, members[group.id] or {}, roll)
    end
    return out
end

function Trade.stock(id, passage)
    local spec = Trade.specOf(id)
    if not spec then return nil end
    local t = store(id)
    return Trade.drawStock(spec, t.seed, passage or passageAt(spec, Trade.worldHours()))
end

-- Cordon tire d'un passage : CORDON_ODDS pour cent calme, patrouilles, cordon serre ; reproductible.
function Trade.drawCordon(seed, passage)
    local n = rng(seed + 104729, passage)(100)
    local acc = 0
    for i, odds in ipairs(Trade.CORDON_ODDS) do
        acc = acc + odds
        if n < acc then return Trade.CORDONS[i] end
    end
    return Trade.CORDONS[#Trade.CORDONS]
end

local function cordonOf(t, passage)
    local c = t.cordons[tostring(passage)]
    if type(c) == "number" then return c end
    return Trade.drawCordon(t.seed, passage)
end

-- Cordon du passage du marchand (1, 1.25 ou 1.5) : fixe par setCordon (bancs), sinon tire.
function Trade.cordon(id, passage)
    local t = store(id)
    return cordonOf(t, passage or Trade.passage(id) or 1)
end

-- Rang du cordon dans Trade.CORDONS (1 : calme).
function Trade.cordonLevel(cordon)
    for i, level in ipairs(Trade.CORDONS) do
        if level == cordon then return i end
    end
    return 1
end

function Trade.setCordon(id, passage, level)
    local ok = false
    for _, c in ipairs(Trade.CORDONS) do
        if c == level then ok = true end
    end
    if not ok or type(passage) ~= "number" then return false end
    local t, persistent = store(id)
    t.cordons = { [tostring(passage)] = level }   -- seul le passage en cours compte
    touched(persistent)
    return true
end

-- Multiplicateur M d'un objet : cordon x rarete (stock tire d'un exemplaire), borne a M_MAX.
local function multiplier(drawnQty, cordon)
    local m = cordon
    if drawnQty == 1 then m = m * Trade.RARITY end
    if m > Trade.M_MAX then m = Trade.M_MAX end
    return m
end

-- Une offre ouverte d'un passage passe devient « expired » (lecture paresseuse) et ne reserve plus rien.
local function expire(t, passage, persistent)
    for _, book in pairs(t.books) do
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

-- Quantites prises dans le passage : echanges faits plus offres ouvertes du passage, sauf celles des cles except et
-- except2 (offre du passage d'un autre membre de l'equipe).
local function reserved(t, passage, except, except2)
    local out = {}
    if t.sold.passage == passage then
        for name, q in pairs(t.sold.items) do out[name] = q end
    end
    for key, book in pairs(t.books) do
        local o = book.offer
        if key ~= except and key ~= except2 and type(o) == "table" and o.passage == passage and o.state == "open" then
            for _, l in ipairs(o.lines or {}) do
                out[l.n] = (out[l.n] or 0) + l.q
            end
        end
    end
    return out
end

-- Stock disponible pour la cle key : stock tire moins ce qui est pris. Jamais negatif.
local function available(spec, t, passage, key, key2)
    local drawn = Trade.drawStock(spec, t.seed, passage)
    local taken = reserved(t, passage, key, key2)
    local out = {}
    for _, e in ipairs(spec.items) do
        local left = (drawn[e.n] or 0) - (taken[e.n] or 0)
        if left < 0 then left = 0 end
        out[e.n] = left
    end
    return out, drawn
end

function Trade.available(id, caller, cid, passage)
    local spec = Trade.specOf(id)
    if not spec then return {} end
    local t, persistent = store(id)
    passage = passage or passageAt(spec, Trade.worldHours())
    expire(t, passage, persistent)
    return (available(spec, t, passage, bookKey(caller, cid)))
end

-- ================================================================ marge et memoire

local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

-- Niveau de reputation du personnage appelant ; neutre sans personnage du carnet ou sans etat charge.
function Trade.levelOf(cid)
    if type(cid) ~= "string" or cid == "" or not S.data or S.blocked then return "neutral" end
    return Rep.level(cid) or "neutral"
end

-- Marge la plus basse permise : tricherie = marge haute de la fiche ; sinon base du niveau de reputation
-- (RS_Config.TradeMargin) moins MARGIN_STEP par affaire conclue, bornee aux marges de la fiche.
local function marginFloor(spec, book, cid)
    local done = 0
    for _, d in ipairs(type(book) == "table" and book.deals or {}) do
        if d.state == "cheated" then return spec.marginMax end
        if d.state == "done" then done = done + 1 end
    end
    local margins = type(Config.TradeMargin) == "table" and Config.TradeMargin or {}
    local base = margins[Trade.levelOf(cid)] or margins.neutral or Trade.MARGIN_DEFAULT
    local m = round2(base - Trade.MARGIN_STEP * done)
    if m < spec.marginMin then m = spec.marginMin end
    if m > spec.marginMax then m = spec.marginMax end
    return m
end

function Trade.marginRange(id, caller, cid)
    local spec = Trade.specOf(id)
    if not spec then return nil end
    local t = store(id)
    local key = bookKey(caller, cid)
    return marginFloor(spec, key and t.books[key], cid), spec.marginMax
end

-- Texte « Nom:quantite » d'une liste, separe par des virgules.
local function listText(lines)
    local parts = {}
    for _, l in ipairs(lines or {}) do parts[#parts + 1] = l.n .. ":" .. l.q end
    return table.concat(parts, ",")
end

local function bookOf(t, key, create)
    local book = t.books[key]
    if type(book) ~= "table" then
        if not create then return nil end
        -- Au plus MAX_BOOKS appelants : le moins recent (derniere revision) evince, jamais une offre en cours.
        local count, oldestKey, oldestRev = 0, nil, nil
        for k, b in pairs(t.books) do
            count = count + 1
            local busy = type(b.offer) == "table" and b.offer.state == "open"
            if not busy and (oldestRev == nil or (b.lastRev or 0) < oldestRev) then oldestKey, oldestRev = k, b.lastRev or 0 end
        end
        if count >= Trade.MAX_BOOKS and oldestKey ~= nil then t.books[oldestKey] = nil end
        book = { deals = {}, lastRev = 0 }
        t.books[key] = book
    end
    if type(book.deals) ~= "table" then book.deals = {} end
    return book
end

-- ================================================================ passage reserve

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

-- Equipe d'un appelant : identifiant CA_Teams de son joueur ; sans joueur ni etat, « caller:<compte> ».
function Trade.teamOf(caller, player)
    if type(caller) ~= "string" or caller == "" then return nil end
    player = player or playerOf(caller)
    local id = player and Factions.idOf(player) or nil
    if type(id) == "string" and id ~= "" then return id end
    return "caller:" .. caller
end

local function currentRun(t, passage)
    local r = t.run
    if type(r) == "table" and r.passage == passage then return r end
    return nil
end

-- Etat du passage pour une equipe : "free", "yours", "taken", "over" ; et le passage reserve s'il existe.
local function runStatus(spec, t, passage, team, hours)
    local r = currentRun(t, passage)
    if r == nil then
        if rendezvous(spec, hours, passage) == nil then return "over", nil end
        return "free", nil
    end
    if r.state ~= "booked" and r.state ~= "arrived" then return "over", r end
    if team ~= nil and r.team == team then return "yours", r end
    return "taken", r
end

-- Lieu du rendez-vous d'un passage : le seul lieu landing, ou un tire par passage (reproductible).
local function landingOf(spec, t, passage)
    local list = spec.landings
    local p = list[1]
    if #list > 1 then p = list[1 + rng(t.seed + 31, passage)(#list)] end
    return { id = p.id, x = p.x, y = p.y, z = p.z, label = p.label }
end

-- ================================================================ offre

local function replaceOpen(book)
    local old = type(book) == "table" and book.offer or nil
    if type(old) == "table" and old.state == "open" then
        old.state = "replaced"
        for _, d in ipairs(book.deals or {}) do
            if d.rev == old.rev and d.state == "open" then d.state = "replaced" end
        end
    end
end

-- Liste « Nom:quantite » separes par des virgules : { { name, low (nom sans module, minuscules), module (minuscules
-- ou nil), q } }, ou nil (forme invalide : texte trop long, jeton mal ecrit, quantite hors 1..MAX_QTY, doublon, plus
-- de MAX_LINES lignes, liste vide).
function Trade.parseList(text)
    if type(text) ~= "string" or string.len(text) > Actions.MAX_PARAM_CHARS then return nil end
    local lines, seen = {}, {}
    for token in string.gmatch(text .. ",", "([^,]*),") do
        local tok = string.gsub(token, "^%s+", "")
        tok = string.gsub(tok, "%s+$", "")
        local name, qty = string.match(tok, "^([%w_%.]+)%s*:%s*(%d+)$")
        if name == nil then
            name = string.match(tok, "^([%w_%.]+)$")
            qty = name and "1" or nil
        end
        if name == nil then return nil end
        local q = tonumber(qty)
        if q == nil or q < 1 or q > Trade.MAX_QTY or math.floor(q) ~= q then return nil end
        local lower = string.lower(name)
        local module, low = string.match(lower, "^([%w_]+)%.([%w_]+)$")
        if low == nil then low = lower end
        if seen[low] or string.find(low, ".", 1, true) then return nil end
        seen[low] = true
        lines[#lines + 1] = { name = name, low = low, module = module, q = q }
        if #lines > Trade.MAX_LINES then return nil end
    end
    if #lines == 0 then return nil end
    return lines
end

local function byLower(spec)
    local out = {}
    for _, e in ipairs(spec.items) do out[string.lower(e.n)] = e end
    return out
end

-- Lignes de gives depuis le texte : { { e = entree du stock, q, name } }, ou nil (forme invalide). Un nom inconnu du
-- stock est garde (e = nil) : refus not_in_stock, pas bad_params.
function Trade.parseItems(text, spec)
    local parsed = Trade.parseList(text)
    if parsed == nil then return nil end
    local known = spec and byLower(spec) or {}
    local lines = {}
    for _, p in ipairs(parsed) do lines[#lines + 1] = { e = known[p.low], q = p.q, name = p.name } end
    return lines
end

-- Entree du bareme d'un type (prix, puis objets vendus seulement, CA_TradeValues), ou nil.
local function valueEntry(fullType)
    return TV.entry(fullType) or TV.SELL_ONLY[fullType]
end

-- Index minuscule de ce que la fiche accepte : nom sans module -> type complet, et module.nom -> type complet.
local function acceptIndex(spec)
    local out = {}
    for _, full in ipairs(spec and spec.accepts or {}) do
        local lower = string.lower(full)
        out[lower] = full
        local short = string.match(lower, "^[%w_]+%.([%w_]+)$")
        if short and out[short] == nil then out[short] = full end
    end
    return out
end

-- Lignes de wants depuis le texte : { { t = type complet accepte par la fiche ou nil, n = nom du script, q } }, ou nil
-- (forme invalide). Module facultatif, casse indifferente.
function Trade.parseWants(text, spec)
    local parsed = Trade.parseList(text)
    if parsed == nil then return nil end
    local index = acceptIndex(spec)
    local lines = {}
    for _, p in ipairs(parsed) do
        local full = index[p.module and (p.module .. "." .. p.low) or p.low]
        lines[#lines + 1] = { t = full, n = full and string.match(full, "%.(.+)$") or p.name, q = p.q }
    end
    return lines
end

-- Valeur d'une ligne de wants au bareme : V x quantite, billets V par lot entier.
local function wantValue(e, q)
    if e.lot then return math.floor(q / e.lot) * e.v end
    return e.v * q
end

-- Ce que l'appelant doit deposer : { lines = { { n, t, q, v } }, value, weight } ou nil et la raison.
local function evaluateWants(text, spec)
    local parsed = Trade.parseWants(text, spec)
    if parsed == nil then return nil, "bad_params" end
    local out = { lines = {}, value = 0, weight = 0 }
    for _, p in ipairs(parsed) do
        local e = p.t and valueEntry(p.t) or nil
        if e == nil then return nil, "not_taken" end
        if e.cap and p.q > e.cap then return nil, "over_count" end
        local value = wantValue(e, p.q)
        out.lines[#out.lines + 1] = { n = p.n, t = p.t, q = p.q, v = value }
        out.value = out.value + value
        out.weight = out.weight + (ItemWeights.of(p.t) or 0) * p.q
    end
    out.weight = math.floor(out.weight * 10 + 0.5) / 10
    if out.weight > Trade.CAP_PAY_KG + 1e-9 then return nil, "pay_weight" end
    return out
end

local function evaluate(id, spec, caller, cid, gives, wants, alsoKey)
    local key = bookKey(caller, cid)
    if key == nil then return nil, "failed" end
    local parsed = Trade.parseItems(gives, spec)
    if parsed == nil then return nil, "bad_params" end
    local pay, payWhy = evaluateWants(wants, spec)
    if pay == nil then return nil, payWhy end
    local t, persistent = store(id)
    local passage = passageAt(spec, Trade.worldHours())
    expire(t, passage, persistent)
    local margin = marginFloor(spec, t.books[key], cid)
    local avail, drawn = available(spec, t, passage, key, alsoKey)
    local cordon = cordonOf(t, passage)
    local offer = { passage = passage, lines = {}, margin = margin, price = 0, weight = 0, cordon = cordon,
        wants = pay.lines, value = pay.value, payWeight = pay.weight }
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
    if offer.value < offer.price then return nil, "unfair" end
    return offer
end

-- Evalue un accord chez le marchand id sans rien ecrire. Rend l'accord ou nil et la raison. alsoKey : livre dont
-- l'accord ouvert ne compte pas comme pris (accord du passage d'un autre membre de l'equipe).
function Trade.evaluate(id, caller, cid, gives, wants, alsoKey)
    local spec = Trade.specOf(id)
    if not spec then return nil, "failed" end
    return evaluate(id, spec, caller, cid, gives, wants, alsoKey)
end

-- Texte de l'accord pour le carnet (ligne « trade » de l'historique radio) : « wants|gives », chaque cote
-- « Type:quantite » separes par des virgules, types sans le module Base (RS_NotebookRadio les nomme).
function Trade.agreedText(offer)
    local function side(lines)
        local parts = {}
        for _, l in ipairs(lines or {}) do
            parts[#parts + 1] = string.gsub(l.t or l.n, "^Base%.", "") .. ":" .. l.q
        end
        return table.concat(parts, ",")
    end
    return side(offer.wants) .. "|" .. side(offer.lines)
end

-- Fige un accord chez le marchand id pour l'appelant. team (Trade.teamOf) : passage reserve par une autre equipe ->
-- booked ; annule, fait ou trop tard -> run_over ; marchand deja arrive pour cette equipe -> frozen (ADR D04) ; libre
-- -> l'accord fige le reserve (troisieme valeur : true). via : { voice, khz } de la demande (voix qui annoncera une
-- annulation). Sans team : aucune reservation.
function Trade.propose(id, caller, cid, gives, wants, team, via)
    local spec = Trade.specOf(id)
    if not spec then return nil, "failed" end
    local key = bookKey(caller, cid)
    local t, persistent, root = store(id)
    local hours = Trade.worldHours()
    local passage = passageAt(spec, hours)
    local status, run, offer, why = nil, nil, nil, nil
    if team ~= nil and key ~= nil then
        expire(t, passage, persistent)
        status, run = runStatus(spec, t, passage, team, hours)
        if status == "taken" then
            why = "booked"
        elseif status == "over" then
            why = "run_over"
        elseif status == "yours" and run.state ~= "booked" then
            why = "frozen"
        end
    end
    if why == nil then
        local other = run and run.key ~= key and run.key or nil
        offer, why = evaluate(id, spec, caller, cid, gives, wants, other)
    end
    if offer == nil then
        if key ~= nil then
            local book = bookOf(t, key, true)
            book.refused = { reason = why }
            touched(persistent)
        end
        log("offer refused by " .. tostring(id) .. " (" .. tostring(why) .. ") caller=" .. tostring(caller))
        return nil, why
    end
    local book = bookOf(t, key, true)
    replaceOpen(book)
    if run ~= nil and run.key ~= key then replaceOpen(t.books[run.key]) end
    root.rev = root.rev + 1
    offer.rev = root.rev
    offer.state = "open"
    book.offer = offer
    book.lastRev = offer.rev
    book.refused = nil
    local deals = book.deals
    deals[#deals + 1] = { rev = offer.rev, passage = offer.passage, items = listText(offer.lines),
        wants = listText(offer.wants), state = "open" }
    while #deals > Trade.MAX_DEALS do table.remove(deals, 1) end
    local booked = false
    if status == "free" then
        via = type(via) == "table" and via or {}
        run = { passage = offer.passage, team = team, state = "booked", bookedAt = hours, voice = id, khz = via.khz,
            start = rendezvous(spec, hours, offer.passage), landing = landingOf(spec, t, offer.passage) }
        t.run = run
        booked = true
    end
    if run ~= nil then
        run.key, run.caller, run.cid, run.rev = key, caller, cid, offer.rev
    end
    touched(persistent)
    log("offer " .. offer.rev .. " of " .. tostring(id) .. " frozen for " .. tostring(caller) .. ": "
        .. listText(offer.lines) .. " for " .. listText(offer.wants) .. " (price " .. offer.price .. ", value "
        .. offer.value .. ", passage " .. offer.passage .. ")")
    if booked then
        log("run " .. run.passage .. " of " .. tostring(id) .. " booked by team " .. tostring(team) .. " ("
            .. tostring(caller) .. "), meeting at world hour " .. run.start)
    end
    return Trade.offerOf(id, caller, cid), nil, booked
end

-- Offre courante de l'appelant chez le marchand id (copie), ou nil.
function Trade.offerOf(id, caller, cid)
    local spec = Trade.specOf(id)
    local key = bookKey(caller, cid)
    if key == nil or not spec then return nil end
    local t, persistent = store(id)
    expire(t, passageAt(spec, Trade.worldHours()), persistent)
    local book = t.books[key]
    if type(book) ~= "table" or type(book.offer) ~= "table" then return nil end
    return copy(book.offer)
end

-- Affaires passees de l'appelant chez le marchand id (copie, de la plus ancienne a la plus recente).
function Trade.deals(id, caller, cid)
    local key = bookKey(caller, cid)
    local t = store(id)
    local book = key and t.books[key]
    return copy(type(book) == "table" and book.deals or {})
end

-- Issue d'une offre ouverte : "done" (quantites prises pour le passage), "cheated" ou "cancelled" (reserve rendue).
-- Rend true si l'offre rev de l'appelant etait ouverte.
local OUTCOMES = { done = true, cheated = true, cancelled = true }
function Trade.close(id, caller, cid, rev, outcome)
    local spec = Trade.specOf(id)
    local key = bookKey(caller, cid)
    if key == nil or not spec or not OUTCOMES[outcome] then return false end
    local t, persistent = store(id)
    expire(t, passageAt(spec, Trade.worldHours()), persistent)
    local book = t.books[key]
    local o = type(book) == "table" and book.offer or nil
    if type(o) ~= "table" or o.rev ~= rev or o.state ~= "open" then return false end
    o.state = outcome
    if outcome == "done" then
        if t.sold.passage ~= o.passage then t.sold = { passage = o.passage, items = {} } end
        for _, l in ipairs(o.lines) do
            t.sold.items[l.n] = (t.sold.items[l.n] or 0) + l.q
        end
    end
    for _, d in ipairs(book.deals) do
        if d.rev == rev then d.state = outcome end
    end
    -- L'offre du passage reserve close : le passage est fini.
    local r = t.run
    if type(r) == "table" and r.key == key and r.rev == rev and (r.state == "booked" or r.state == "arrived") then
        r.state, r.endedAt = outcome, Trade.worldHours()
        if outcome == "cancelled" and r.reason == nil then r.reason = "cancelled" end
    end
    touched(persistent)
    log("offer " .. tostring(rev) .. " of " .. tostring(caller) .. " at " .. tostring(id) .. " closed: " .. outcome)
    return true
end

-- ================================================================ suivi du passage (RS_TradeRun, RS_TradeExchange)

-- Passage reserve le plus recent du marchand (copie, quel que soit son passage), ou nil.
function Trade.lastRun(id)
    local t = store(id)
    if type(t.run) ~= "table" then return nil end
    return copy(t.run)
end

-- Passage reserve du passage en cours (copie), ou nil.
function Trade.runOf(id, passage)
    local t = store(id)
    local r = currentRun(t, passage or Trade.passage(id))
    return r and copy(r) or nil
end

-- Etat du passage du marchand pour une equipe (voir runStatus) et copie du passage reserve.
function Trade.runStatus(id, team, passage, hours)
    local spec = Trade.specOf(id)
    if not spec then return "over", nil end
    local t = store(id)
    hours = hours or Trade.worldHours()
    local status, r = runStatus(spec, t, passage or passageAt(spec, hours), team, hours)
    return status, r and copy(r) or nil
end

-- Passage clos avec la meme issue que son offre (si elle etait encore ouverte), sinon clos directement.
local function endRun(id, t, r, outcome)
    local o = r.key and type(t.books[r.key]) == "table" and t.books[r.key].offer or nil
    if not (type(o) == "table" and o.rev == r.rev and o.state == "open" and Trade.close(id, r.caller, r.cid, r.rev, outcome))
    then
        r.state, r.endedAt = outcome, Trade.worldHours()
    end
end

-- Annule le passage reserve encore attendu (state booked) : raison notee, offre close « cancelled ». Rend la copie du
-- passage annule, ou nil s'il n'y avait rien a annuler.
function Trade.cancelRun(id, reason)
    local t, persistent = store(id)
    local r = t.run
    if type(r) ~= "table" or r.state ~= "booked" then return nil end
    r.reason = reason
    endRun(id, t, r, "cancelled")
    touched(persistent)
    log("run " .. tostring(r.passage) .. " of " .. tostring(id) .. " for team " .. tostring(r.team) .. " cancelled: "
        .. tostring(reason))
    return copy(r)
end

-- Le marchand est au lieu du rendez-vous (signal vu) : state arrived. Rend true si le passage etait attendu.
function Trade.arrive(id, how)
    local t, persistent = store(id)
    local r = t.run
    if type(r) ~= "table" or r.state ~= "booked" then return false end
    r.state, r.arrivedAt, r.signal = "arrived", Trade.worldHours(), how
    touched(persistent)
    log("run " .. tostring(r.passage) .. " of " .. tostring(id) .. ": trader at the landing for team "
        .. tostring(r.team) .. " (" .. tostring(how) .. ")")
    return true
end

-- Issue de l'echange d'un passage arrive : outcome done, cheated ou cancelled, raison notee, detail facultatif ;
-- l'offre du passage est close avec la meme issue. Rend la copie du passage clos, ou nil.
function Trade.finishRun(id, outcome, reason, detail)
    if not OUTCOMES[outcome] then return nil end
    local t, persistent = store(id)
    local r = t.run
    if type(r) ~= "table" or r.state ~= "arrived" then return nil end
    r.reason = reason
    if type(detail) == "table" then r.exchange = detail end
    endRun(id, t, r, outcome)
    touched(persistent)
    log("run " .. tostring(r.passage) .. " of " .. tostring(id) .. " for team " .. tostring(r.team) .. " finished: "
        .. outcome .. " (" .. tostring(reason) .. ")")
    return copy(r)
end

-- Regle hors de vue (RS_OutOfSight) appliquee au lieu du passage arrive : watcher.watch sur l'enregistrement du
-- passage (sauvegarde avec lui). Rend true quand l'echange est du (delai ecoule hors de vue ; reste du ensuite).
function Trade.watchLanding(id, watcher, delayHours)
    local t, persistent = store(id)
    local r = t.run
    if type(r) ~= "table" or r.state ~= "arrived" or type(r.landing) ~= "table" then return false end
    if r.due then return true end
    if type(r.sight) ~= "table" then r.sight = {} end
    local ready, moved = watcher.watch(r.sight, r.landing, delayHours)
    if ready then r.due = true end
    if ready or moved then touched(persistent) end
    return r.due == true
end

-- Tirage reproductible 0..n-1 d'un passage du marchand pour une cause d'annulation (salt : un nombre par cause ; meme
-- graine, meme passage, meme sel : meme tirage, ADR D05).
function Trade.runRoll(id, passage, salt, n)
    local t = store(id)
    return rng(t.seed + salt, passage)(n)
end

-- Annonce d'une annulation dite a l'heure `hours` (RS_TradeRun, repetee chaque heure jusqu'au rendez-vous, ADR
-- D05) : heure notee sur le passage annule. Rend true si le passage est annule.
function Trade.noteAnnounced(id, hours)
    local t, persistent = store(id)
    local r = t.run
    if type(r) ~= "table" or r.state ~= "cancelled" then return false end
    r.announcedAt = hours
    touched(persistent)
    return true
end

-- Contenu du lieu note la premiere fois que le serveur le voit charge apres la reservation (RS_TradeExchange, ADR
-- D02) : seen = { [identifiant d'objet en texte] = true }. Ecrit une seule fois par passage attendu ou arrive.
-- Rend true si la note est ecrite.
function Trade.noteDeposit(id, seen)
    local t, persistent = store(id)
    local r = t.run
    if type(r) ~= "table" or (r.state ~= "booked" and r.state ~= "arrived") or r.seen ~= nil
            or type(seen) ~= "table" then
        return false
    end
    r.seen = seen
    touched(persistent)
    log("run " .. tostring(r.passage) .. " of " .. tostring(id) .. ": landing content noted before the drop")
    return true
end

-- ================================================================ contexte du LLM

local function allowsTrade(sheet)
    if type(sheet) ~= "table" or type(sheet.actions) ~= "table" or type(sheet.trade) ~= "table" then return false end
    for _, a in ipairs(sheet.actions) do
        if a == Trade.ACTION then return true end
    end
    return false
end

-- Ce que la fiche accepte en paiement, par classe du bareme (ordre Trade.TAKES, puis les autres) : { k, items = texte
-- « Nom V, Nom V » trie par nom ; billets « per <lot> », plafond par passage « (max n) », etat minimal
-- « (condition n%+) » }. Garde par fiche (spec.accepts ne change qu'avec une nouvelle lecture de la fiche).
local takesCache = setmetatable({}, { __mode = "k" })
local function takes(spec)
    local cached = takesCache[spec]
    if cached then return cached end
    local byClass, order = {}, {}
    for _, full in ipairs(spec.accepts or {}) do
        local e = valueEntry(full)
        if e then
            local k = e.k or "supply"
            if not byClass[k] then
                byClass[k] = {}
                order[#order + 1] = k
            end
            local text = string.match(full, "%.(.+)$") .. " " .. e.v
            if e.lot then text = text .. " per " .. e.lot end
            if e.cap then text = text .. " (max " .. e.cap .. ")" end
            if e.cond then text = text .. " (condition " .. math.floor(e.cond * 100 + 0.5) .. "%+)" end
            local list = byClass[k]
            list[#list + 1] = text
        end
    end
    local rank = {}
    for i, k in ipairs(Trade.TAKES) do rank[k] = i end
    table.sort(order, function(a, b)
        local ra, rb = rank[a] or 100, rank[b] or 100
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    cached = {}
    for _, k in ipairs(order) do
        table.sort(byClass[k])
        cached[#cached + 1] = { k = k, items = table.concat(byClass[k], ", ") }
    end
    takesCache[spec] = cached
    return cached
end

-- Texte d'une fin de passage pour le LLM : cause du mode d'arrivee, sinon REASON_TEXTS.
local function reasonText(spec, reason)
    local mode = Arrivals.get(spec.arrival)
    for _, cause in ipairs(mode and mode.causes or {}) do
        if cause.name == reason then return cause.text end
    end
    return Trade.REASON_TEXTS[reason] or Trade.REASON_TEXTS.cancelled
end

-- Passage vu par l'equipe de l'appelant, pour le LLM : status (free, yours, taken, over), heures de la fenetre (from,
-- to : heure du jeu, decimales pour les minutes), days et inHours jusqu'a son debut ; yours : state, place (libelle
-- du lieu), signal (ce que l'equipe doit faire), drop (ou deposer le paiement), arrived (texte du mode une fois
-- arrive) ; over : reason (texte).
local function runContext(id, spec, team, passage, hours)
    local t = store(id)
    local status, r = runStatus(spec, t, passage, team, hours)
    local out = { status = status, from = spec.from, to = (spec.from + spec.hours) % 24 }
    local start = nil
    if status == "free" then
        start = rendezvous(spec, hours, passage)
    elseif status == "yours" then
        local mode = Arrivals.get(spec.arrival)
        start = r.start
        out.state, out.place = r.state, r.landing and r.landing.label or nil
        out.signal = mode and mode.texts.signal or nil
        out.drop = mode and mode.texts.drop or nil
        if r.state == "arrived" then out.arrived = mode and mode.texts.arrived or nil end
    elseif status == "over" then
        out.reason = reasonText(spec, r and (r.reason or r.state) or "closed")
    end
    if start ~= nil then
        local hourOfDay = (hours + 7) % 24
        out.days = math.max(0, math.floor((hourOfDay + start - hours) / 24))
        out.inHours = math.floor((start - hours) * 10 + 0.5) / 10
    end
    return out
end

function Trade.runContext(id, team, passage, hours)
    local spec = Trade.specOf(id)
    if not spec then return nil end
    hours = hours or Trade.worldHours()
    return runContext(id, spec, team, passage or passageAt(spec, hours), hours)
end

-- Contexte du marchand (fiche sheet) pour une demande de l'appelant (table), ou nil si la fiche ne troque pas :
-- passage, cap (prix au plus de ce qu'il laisse), kg (poids au plus de ce qu'il laisse), payKg (poids au plus du
-- depot), stock { n, q, w, unit = prix d'un exemplaire a la marge de l'appelant }, takes { k, items }, offer { rev,
-- items, wants, state }, deals { passage, items, wants, state }, refused (raison), run (runContext). Le LLM compte en
-- points pour juger ; il ne les dit jamais (consignes du pont).
function Trade.context(sheet, caller, cid)
    if not allowsTrade(sheet) then return nil end
    local id, spec = sheet.id, sheet.trade
    local key = bookKey(caller, cid)
    local t, persistent = store(id)
    local hours = Trade.worldHours()
    local passage = passageAt(spec, hours)
    expire(t, passage, persistent)
    local book = key and t.books[key] or nil
    local low = marginFloor(spec, book, cid)
    local avail, drawn = available(spec, t, passage, key)
    local cordon = cordonOf(t, passage)
    local ctx = { passage = passage, cap = Trade.CAP_POINTS, kg = Trade.CAP_KG, payKg = Trade.CAP_PAY_KG, stock = {},
        takes = takes(spec), deals = {} }
    for _, e in ipairs(spec.items) do
        local n = avail[e.n]
        if n > 0 then
            local v = TV.sellValue(e.t)
            ctx.stock[#ctx.stock + 1] = { n = e.n, q = n, w = e.w,
                unit = TV.linePrice(v, 1, (1 + low) * multiplier(drawn[e.n], cordon)) }
        end
    end
    if type(book) == "table" then
        local o = book.offer
        if type(o) == "table" and o.passage == passage then
            ctx.offer = { rev = o.rev, items = listText(o.lines), wants = listText(o.wants), state = o.state }
        end
        local deals = book.deals or {}
        for i = math.max(1, #deals - Trade.DEALS_SENT + 1), #deals do
            local d = deals[i]
            ctx.deals[#ctx.deals + 1] = { passage = d.passage, items = d.items, wants = d.wants, state = d.state }
        end
        if type(book.refused) == "table" then ctx.refused = book.refused.reason end
    end
    ctx.run = runContext(id, spec, Trade.teamOf(caller), passage, hours)
    return ctx
end

-- Champ trade= d'une demande radio : hexadecimal RSV2 du contexte, ou nil.
function Trade.field(sheet, caller, cid)
    local ctx = Trade.context(sheet, caller, cid)
    if ctx == nil then return nil end
    return Codec.hexBytes(Codec.encodeBytes(ctx))
end

-- ================================================================ action

local PARAMS = { gives = true, wants = true }

local function validate(params)
    for k in pairs(params) do
        if not PARAMS[k] then return false end
    end
    return Trade.parseList(params.gives) ~= nil and Trade.parseList(params.wants) ~= nil
end

local function execute(params, ctx)
    if type(ctx) ~= "table" or type(ctx.caller) ~= "string" or type(ctx.voice) ~= "string" then
        return false, "failed"
    end
    -- Le premier accord fige reserve le passage du marchand pour l'equipe de l'appelant ; RS_TradeRun en est averti,
    -- et l'accord s'inscrit dans le carnet de l'appelant (Trade.onAgreed, composition RS_TradeRun.install).
    local team = Trade.teamOf(ctx.caller, ctx.player)
    local offer, why, booked = Trade.propose(ctx.voice, ctx.caller, ctx.cid, params.gives, params.wants, team,
        { khz = ctx.khz })
    if offer == nil then return false, why end
    if booked and type(Trade.onBooked) == "function" then Trade.onBooked(Trade.lastRun(ctx.voice), ctx) end
    if type(Trade.onAgreed) == "function" then Trade.onAgreed(offer, ctx) end
    return true
end

function Trade.register()
    return Actions.register(Trade.ACTION, { validate = validate, cooldownMs = Trade.COOLDOWN_MS, execute = execute })
end

Trade.register()

return Trade
