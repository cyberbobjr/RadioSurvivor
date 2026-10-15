-- Radio Survivor : journal du dehors (E13-T05), document du mod apporté par le passeur de l'Ohio.
--
-- Feuille ronéotypée de la rive de l'Indiana : nouvelles du dehors datées du jour de sa création (donc après
-- l'épidémie), une édition par passage du passeur. Objet `literature` sans CanBeWrite
-- (media/scripts/RadioSurvivor_outsidenews.txt) : « Inspecter » l'ouvre dans la fenêtre vanilla des documents
-- (ISReadABook:displayPrintMedia). Fiche : docs/conception/journal-du-dehors.md.
--
-- Contenu : gabarits FR/EN fixes (Print_Text.json), aucun secret ni fréquence. Une édition choisit, de façon
-- reproductible d'après son numéro : un article de une parmi LEADS (deux éditions qui se suivent n'ont jamais la
-- même une : pas de 7 premier avec LEADS), BRIEF_COUNT brèves distinctes parmi BRIEFS et deux prix (essence, pain)
-- qui montent d'une édition à l'autre.
--
-- Transport (règle MP des traductions, base api-42-21.md et multiplayer.md) : l'autorité n'écrit que des nombres
-- et des clés dans la ModData de l'objet :
--   modData.printMedia = { id = "RadioSurvivor_OutsideNews_<n>", title = id, info = INFO_KEY, text = TEXT_KEY }
--   modData.RadioSurvivorOutsideNews = { format, edition, y, m, d, lead, briefs = { i, j, k }, gas, bread }
-- Le titre vaut l'identifiant : ISReadABook:complete marque lu l'identifiant (addReadPrintMedia(id)) et
-- l'inventaire teste le titre (isPrintMediaRead(title), ISInventoryPane.lua:2605), donc chaque édition a sa propre
-- marque « lu ». Le client compose mise en page, transcription et titre dans la langue du lecteur juste avant
-- l'ouverture (client/RadioSurvivor/RS_NotesReader.lua). INFO_KEY et TEXT_KEY ont une traduction de repli (titre
-- seul) pour une ouverture sans composition.
--
-- Point d'appel du futur échange (E13-T04) : server/RadioSurvivor/RS_OutsideNewsServer.lua, OutsideNewsServer.create
-- (numéro du passage). OnCreate (butin, objet donné par un admin) pose l'édition de la semaine en cours.
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).

local News = {}

News.FORMAT = 1
News.MODULE = "RadioSurvivor"
News.TYPE = "OutsideNews"
News.FULL_TYPE = News.MODULE .. "." .. News.TYPE
News.MODDATA_KEY = "RadioSurvivorOutsideNews"
News.ID_PREFIX = "RadioSurvivor_OutsideNews_"
News.INFO_KEY = "Print_Media_RadioSurvivor_OutsideNews_info"
News.TEXT_KEY = "Print_Text_RadioSurvivor_OutsideNews_info"
News.TITLE_KEY = "Print_Media_RadioSurvivor_OutsideNews_title"
-- Fragments de la mise en page et de la transcription (Print_Text.json, routés par leur préfixe).
News.KEY = "Print_Text_RadioSurvivor_OutsideNews_"

News.LEADS = 10           -- articles de une : <KEY>lead<i>_head, <KEY>lead<i>_body
News.BRIEFS = 12          -- brèves : <KEY>brief<i>_head, <KEY>brief<i>_body
News.BRIEF_COUNT = 3      -- brèves par édition
News.LEAD_STEP = 7        -- pas de la une d'une édition à la suivante (premier avec LEADS)
News.EDITION_MAX = 9999
News.WEEK_HOURS = 168
-- Prix en cents : base + pas x (édition - 1) + tirage 0..9, plafonnés.
News.PRICES = { gas = { base = 109, step = 14 }, bread = { base = 79, step = 8 } }
News.PRICE_MAX = 9999

local function isInt(v, lo, hi)
    return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

-- Tirage reproductible sans opérateur binaire (Park-Miller, 16807 x s reste exact en double).
local function nextSeed(s)
    return (s * 16807) % 2147483647
end

-- Numéro de l'édition de la semaine en cours (1 la première semaine du monde), ou 1 sans horloge.
function News.currentEdition()
    local gt = getGameTime and getGameTime()
    local hours = gt and tonumber(gt:getWorldAgeHours()) or 0
    if hours == nil or hours < 0 then hours = 0 end
    local n = math.floor(hours / News.WEEK_HOURS) + 1
    if n > News.EDITION_MAX then n = News.EDITION_MAX end
    return n
end

-- Date du jour de jeu : année, mois 1..12, jour 1..31 (GameTime compte mois et jours depuis 0), ou nil.
function News.today()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    return { y = gt:getYear(), m = gt:getMonth() + 1, d = gt:getDay() + 1 }
end

-- Contenu d'une édition (nombres seulement) : une, brèves, prix. Même édition, même contenu.
function News.select(edition)
    local lead = ((edition - 1) * News.LEAD_STEP) % News.LEADS + 1
    local s = (edition * 7919 + 13) % 2147483647
    local briefs, used = {}, {}
    while #briefs < News.BRIEF_COUNT do
        s = nextSeed(s)
        local i = s % News.BRIEFS + 1
        if not used[i] then
            used[i] = true
            briefs[#briefs + 1] = i
        end
    end
    local prices = {}
    for _, name in ipairs({ "gas", "bread" }) do
        s = nextSeed(s)
        local p = News.PRICES[name]
        local cents = p.base + p.step * (edition - 1) + s % 10
        if cents > News.PRICE_MAX then cents = News.PRICE_MAX end
        prices[name] = cents
    end
    return lead, briefs, prices.gas, prices.bread
end

-- ModData d'une édition : clés du document et données de composition. Rend nil si edition est invalide.
function News.newData(edition, date)
    if not isInt(edition, 1, News.EDITION_MAX) then return nil end
    date = date or News.today() or {}
    local lead, briefs, gas, bread = News.select(edition)
    local id = News.ID_PREFIX .. tostring(edition)
    return {
        printMedia = { id = id, title = id, info = News.INFO_KEY, text = News.TEXT_KEY },
        news = { format = News.FORMAT, edition = edition, y = date.y, m = date.m, d = date.d, lead = lead,
            briefs = briefs, gas = gas, bread = bread },
    }
end

-- Écrit une édition dans la ModData de l'objet ; vrai si fait.
function News.apply(item, edition, date)
    local data = News.newData(edition, date)
    if not data or not item then return false end
    local modData = item:getModData()
    modData.printMedia = data.printMedia
    modData[News.MODDATA_KEY] = data.news
    return true
end

-- OnCreate de l'objet (script : OnCreate = RadioSurvivorOutsideNews.onCreate) : édition de la semaine en cours.
-- Sur un client MP, rejoué à la réception de l'objet puis remplacé par la ModData du serveur.
function News.onCreate(item)
    if not item or item:getType() ~= News.TYPE then return end
    News.apply(item, News.currentEdition())
end

-- Vrai si la table printMedia est celle d'un journal du dehors.
function News.isPrintMedia(printMedia)
    return type(printMedia) == "table" and type(printMedia.id) == "string"
        and string.sub(printMedia.id, 1, #News.ID_PREFIX) == News.ID_PREFIX
end

-- Données valides d'un journal (nombres dans leurs bornes), ou nil.
local function readNews(modData)
    if type(modData) ~= "table" or not News.isPrintMedia(modData.printMedia) then return nil end
    local n = modData[News.MODDATA_KEY]
    if type(n) ~= "table" or not isInt(n.edition, 1, News.EDITION_MAX) or not isInt(n.lead, 1, News.LEADS) then
        return nil
    end
    if type(n.briefs) ~= "table" then return nil end
    for i = 1, #n.briefs do
        if not isInt(n.briefs[i], 1, News.BRIEFS) then return nil end
    end
    return n
end
News.readNews = readNews

-- Mise en page (unités de la page 600 x 800). Les blocs de texte ont leur bas autorisé (bottom) : vérifié hors jeu
-- avec les métriques des polices SDF (tests/test_outside_news.py).
News.PAGE = { width = 600, height = 800 }
News.LAYOUT = {
    masthead = { font = "SdfOldBold", x = 300, y = 26, scale = 1.1, pivotX = 0.5, bottom = 88 },
    subline = { font = "SdfOldRegular", x = 300, y = 92, scale = 0.5, pivotX = 0.5, bottom = 116 },
    date = { font = "SdfOldRegular", x = 300, y = 118, scale = 0.5, pivotX = 0.5, bottom = 146 },
    leadHead = { font = "SdfOldBold", x = 40, y = 164, scale = 0.7, autoWidth = 743, bottom = 234 },
    leadBody = { font = "SdfOldRegular", x = 40, y = 238, scale = 0.6, autoWidth = 866, bottom = 416 },
    briefHead = { font = "SdfOldBold", x = 40, y = 432, scale = 0.55, autoWidth = 945, step = 96 },
    briefBody = { font = "SdfOldRegular", x = 40, y = 456, scale = 0.5, autoWidth = 1040, step = 96, bottom = 524 },
    prices = { font = "SdfOldRegular", x = 40, y = 730, scale = 0.5, autoWidth = 1040, bottom = 790 },
}
local INK = "r:0.1, g:0.09, b:0.08, a:1"

-- Les textes viennent de nos traductions ; < et > couperaient l'élément, % serait relu par getText.
local function clean(s)
    s = tostring(s or "")
    s = string.gsub(s, "[<>%%]", "")
    return s
end

local function textElement(b, y, s)
    local p = "<type:text, font:" .. b.font .. ", x:" .. b.x .. ", y:" .. y .. ", scaleX:" .. b.scale
        .. ", scaleY:" .. b.scale
    if b.pivotX then p = p .. ", pivotX:" .. b.pivotX end
    if b.autoWidth then p = p .. ", autoWidth:" .. b.autoWidth end
    return p .. ", " .. INK .. ">" .. clean(s)
end

local function rect(y, h, a)
    return "<type:texture, x:40, y:" .. y .. ", width:520, height:" .. h .. ", r:0.1, g:0.09, b:0.08, a:" .. a .. ">"
end

-- Prix en cents -> texte de la langue (gabarit price : %1 dollars, %2 cents sur deux chiffres).
function News.priceLabel(cents)
    cents = math.floor(tonumber(cents) or 0)
    local dollars = math.floor(cents / 100)
    local rest = cents - dollars * 100
    local two = (rest < 10 and "0" or "") .. tostring(rest)
    return getText(News.KEY .. "price", tostring(dollars), two)
end

-- Date de l'édition dans la langue du lecteur, ou nil (date inconnue).
function News.dateLabel(n)
    if not isInt(n.y, 1, 9999) or not isInt(n.m, 1, 12) or not isInt(n.d, 1, 31) then return nil end
    return getText(News.KEY .. "date", tostring(n.d), getText(News.KEY .. "month" .. n.m), tostring(n.y))
end

-- Mise en page, transcription et titre dans la langue courante, ou nil (autre document, données invalides).
function News.compose(modData)
    local n = readNews(modData)
    if not n then return nil end
    local K, L = News.KEY, News.LAYOUT
    local ed = tostring(n.edition)
    local masthead = getText(K .. "masthead")
    local subline = getText(K .. "subline", ed)
    local date = News.dateLabel(n) or getText(K .. "undated")
    local leadHead = getText(K .. "lead" .. n.lead .. "_head")
    local leadBody = getText(K .. "lead" .. n.lead .. "_body")
    local prices = getText(K .. "prices", News.priceLabel(n.gas), News.priceLabel(n.bread))

    local info = { "<type:parent, width:" .. News.PAGE.width .. ", height:" .. News.PAGE.height .. ">",
        "<type:texture, x:0, y:0, width:600, height:800, r:0.93, g:0.91, b:0.85, a:1>",
        textElement(L.masthead, L.masthead.y, masthead), textElement(L.subline, L.subline.y, subline),
        textElement(L.date, L.date.y, date), rect(150, 3, 0.85),
        textElement(L.leadHead, L.leadHead.y, leadHead), textElement(L.leadBody, L.leadBody.y, leadBody),
        rect(422, 1, 0.6) }
    local text = { clean(masthead), "\\n", clean(subline), "\\n", clean(date), "\\n\\n", clean(leadHead), "\\n",
        clean(leadBody) }
    for i = 1, #n.briefs do
        local head = getText(K .. "brief" .. n.briefs[i] .. "_head")
        local body = getText(K .. "brief" .. n.briefs[i] .. "_body")
        local dy = (i - 1) * L.briefHead.step
        info[#info + 1] = textElement(L.briefHead, L.briefHead.y + dy, head)
        info[#info + 1] = textElement(L.briefBody, L.briefBody.y + dy, body)
        text[#text + 1] = "\\n\\n" .. clean(head) .. "\\n" .. clean(body)
    end
    info[#info + 1] = rect(720, 1, 0.6)
    info[#info + 1] = textElement(L.prices, L.prices.y, prices)
    text[#text + 1] = "\\n\\n" .. clean(prices)
    local title = clean(getText(News.TITLE_KEY, ed))
    return table.concat(info), table.concat(text), title
end

-- Fonction globale citée par le script d'objet (résolue par son nom pointé, LuaManager.getFunctionObject). Le fichier
-- serveur y ajoute la commande de test give.
RadioSurvivorOutsideNews = RadioSurvivorOutsideNews or {}
RadioSurvivorOutsideNews.onCreate = function(item) News.onCreate(item) end

return News
