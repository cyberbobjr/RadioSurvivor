-- Living Knox : traces lisibles en jeu (LK10-T04) : carnet du foyer d'un groupe disparu, notes sur le chef mort.
-- Fiche : docs/annexes/conception/traces.md. Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Deux documents vanilla en lecture seule (objet literature CanBeWrite, pages écrites par addPage puis verrouillées
-- par setLockedBy : un lecteur d'un autre nom n'a que « Lire », J/inventory/types/Literature.java:446-482,
-- M/client/ISUI/ISInventoryPaneContextMenu.lua:566-585, ISUIWriteJournal.lua:318-325) :
--   carnet du foyer (CFG.HOME_ITEM, Base.Notebook, 10 pages) : déposé UNE fois, quand le groupe a disparu (marque
--     gone de LK09-T04 : décimé ou dispersé) et que son foyer est chargé (même règle que LK_Homes.ready) ; rangé dans
--     la caisse ou la tente posée par l'aménagement (ModData LKHome), sinon dans le conteneur le plus proche du foyer
--     (même bâtiment, ou hors bâtiment pour un camp), sinon au sol sur la case du foyer. Contenu : titre, résumé
--     public de l'histoire (LK_Stories, jamais les secrets), puis le journal de récit (LK_Journal), le plus ancien
--     d'abord ; s'il dépasse les pages, les entrées les plus anciennes sont omises ;
--   notes sur le chef (CFG.CHIEF_ITEM, Base.SheetPaper2, 1 page) : posées dans l'inventaire du corps du chef à sa mort
--     (fait memberDied de LK_Bodies, corps présent, publié dans OnZombieDead AVANT la création du cadavre, donc parti
--     avec le cadavre comme le butin de LK_Loot) : titre, motivation du groupe, entrées les plus récentes qui tiennent.
--     Un chef mort hors écran (simulation abstraite) n'a pas de corps : aucune note.
-- Langue : texte composé par l'autorité au moment du dépôt (getTextOrNull des clés IGUI_LK_Traces_* et
--   IGUI_LK_Journal_*), donc dans la langue du joueur en solo et dans celle du processus serveur en MP ; un serveur MP
--   n'a pas les traductions des mods (base api-42-21.md) : Translator.loadFiles() une fois s'il les faut. Le texte
--   d'une page est figé dans l'objet : il ne suit pas la langue du lecteur.
-- Une seule fois, sans doublon : marque persistante dans le registre privé des groupes (champ facultatif traces,
--   schéma 1 inchangé, contrôlé ici et remis à neuf s'il est malformé) :
--     traces = { v = FORMAT, home = { hx, hy, hz, day, state = "placing" | "done", where = WHERE } ou absent,
--                chiefs = { "m-<k>", ... } (CHIEFS_MAX au plus : chefs dont la note est posée) }
--   écrite AVANT le dépôt (une erreur ou un arrêt en plein dépôt ne fait jamais déposer deux fois) ; en plus, chaque
--   document porte ModData LKTrace = groupe et LKTraceKind = "home" | "chief" (sans marque, un carnet du groupe trouvé
--   autour du foyer rétablit la marque sans rien déposer : registre plus ancien que le monde), et le corps du chef
--   ModData LKTraceChief.
-- Aucun secret : ni coordonnée (le journal de récit n'en a aucune, la marque reste dans le registre privé), ni compte
--   de joueur, ni secret d'histoire (seuls le résumé et la motivation publics sont lus).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Journal"
require "LivingKnox/LK_Stories"
require "LivingKnox/LK_Homes"

local Traces = LivingKnox.Traces or {}
LivingKnox.Traces = Traces

Traces.FORMAT = 1
Traces.TAG = "LKTrace"
Traces.TAG_KIND = "LKTraceKind"
Traces.MD_BODY = "LKTraceChief"
Traces.LOCK = "Living Knox"          -- nom du verrou (setLockedBy) : aucun joueur ne le porte
Traces.KEY = "IGUI_LK_Traces_"
Traces.CHIEFS_MAX = 16
Traces.WHERE = { container = true, floor = true, found = true }

Traces.CFG = Traces.CFG or {
    HOME_ITEM = "Base.Notebook",      -- literature.txt : CanBeWrite, PageToWrite = 10
    HOME_PAGES = 10,
    CHIEF_ITEM = "Base.SheetPaper2",  -- literature.txt : CanBeWrite, PageToWrite = 1
    CHIEF_PAGES = 1,
    LINES = 15,                       -- lignes d'une page (ISUIWriteJournal : setMaxLines(15))
    WIDTH = 40,                       -- caractères par ligne au plus (fenêtre de 350 px, police Small) : à vérifier
    PAGE_MAX = 1200,                  -- caractères d'une page au plus (15 x 80, ISUIWriteJournal.lua:310)
    SCAN_MS = 1000,                   -- examen depuis LoadChunk au plus une fois par seconde
    RETRY_MS = 10000,                 -- foyer non prêt : nouvel essai au plus toutes les 10 s
}

Traces.state = Traces.state or { done = {}, tried = {}, lastScan = nil, reloaded = false, noText = false }
Traces.stats = Traces.stats or { homes = 0, chiefs = 0, restored = 0, notReady = 0, failed = 0 }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Journal() return LivingKnox.Journal end
local function Homes() return LivingKnox.Homes end
local function cfg() return Traces.CFG end
local function now() return getTimestampMs() end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function isMember(v) return type(v) == "string" and string.match(v, "^m%-%d+$") ~= nil end

local function homeKey(home) return home.x .. "," .. home.y .. "," .. home.z end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

-- ================================================================ texte

-- Langue de l'autorité pour les histoires (données EN/FR) : "fr" ou "en".
function Traces.language()
    local language = Translator and Translator.getLanguage and Translator.getLanguage()
    local name = language and tostring(language:name()) or "EN"
    return string.lower(name) == "fr" and "fr" or "en"
end

local function hasText()
    return getTextOrNull ~= nil and getTextOrNull(Traces.KEY .. "EntryDay", "1", "-") ~= nil
end

-- Résolveur des clés du mod sur cette machine (getTextOrNull), ou nil. Serveur MP : traductions des mods rechargées
-- une fois (Translator.loadFiles, base api-42-21.md), dans la langue du processus serveur.
function Traces.resolver()
    if getTextOrNull == nil then return nil end
    if not hasText() and isServer() and not Traces.state.reloaded and Translator ~= nil
        and Translator.loadFiles ~= nil then
        Traces.state.reloaded = true
        Translator.loadFiles()
        log().info("traces: mod translations reloaded on the server")
    end
    if not hasText() then
        if not Traces.state.noText then
            Traces.state.noText = true
            log().warn("traces: no translation for %sEntryDay here: no document written", Traces.KEY)
        end
        return nil
    end
    return getTextOrNull
end

-- Lignes affichées d'un texte (retour à la ligne aux espaces, width caractères au plus ; un mot plus long garde sa
-- ligne ; « \n » commence une ligne, ligne vide comprise).
function Traces.wrap(text, width)
    local out = {}
    for para in string.gmatch(tostring(text) .. "\n", "([^\n]*)\n") do
        local line = ""
        for word in string.gmatch(para, "%S+") do
            if line == "" then
                line = word
            elseif #line + 1 + #word <= width then
                line = line .. " " .. word
            else
                out[#out + 1] = line
                line = word
            end
        end
        out[#out + 1] = line
    end
    return out
end

-- Mise en pages : head (paragraphes) puis entries (paragraphes, le plus ancien d'abord), pagesMax pages de LINES
-- lignes. Une entrée qui tient dans une page n'est jamais coupée ; si tout ne tient pas, les entrées les plus anciennes
-- sont omises. Rend la liste des pages (texte) et le nombre d'entrées omises.
function Traces.layout(head, entries, pagesMax)
    local c = cfg()
    local function blocks(list)
        local out = {}
        for _, p in ipairs(list) do out[#out + 1] = Traces.wrap(p, c.WIDTH) end
        return out
    end
    local headBlocks, entryBlocks = blocks(head), blocks(entries)
    local function build(first)
        local pages, cur = {}, {}
        local function flush()
            if #cur > 0 then pages[#pages + 1] = cur end
            cur = {}
        end
        local function put(lines, keep)
            if keep and #lines <= c.LINES and #cur + #lines > c.LINES then flush() end
            for _, l in ipairs(lines) do
                if #cur >= c.LINES then flush() end
                cur[#cur + 1] = l
            end
        end
        for _, b in ipairs(headBlocks) do put(b, false) end
        for i = first, #entryBlocks do put(entryBlocks[i], true) end
        flush()
        return pages
    end
    local first, pages = 1
    while true do
        pages = build(first)
        if #pages <= pagesMax or first > #entryBlocks then break end
        first = first + 1
    end
    local out = {}
    for i = 1, math.min(#pages, pagesMax) do
        local text = table.concat(pages[i], "\n")
        if #text > c.PAGE_MAX then text = string.sub(text, 1, c.PAGE_MAX) end
        out[i] = text
    end
    return out, first - 1
end

-- Histoire publique du groupe g (copie du registre) : { summary, motivation } dans la langue lang, ou nil. Les secrets
-- ne sont jamais lus ; sans graine, le résumé anglais du registre.
function Traces.story(g, lang)
    local S = LivingKnox.Stories
    if S ~= nil and isInt(g.storySeed, 0, 2147483647) then
        local story = S.compose(g.type, g.storySeed)
        if type(story) == "table" then
            local pub = S.publicView(story)
            return { summary = S.text(pub, lang), motivation = pub.motivation and pub.motivation[lang] or nil }
        end
    end
    if type(g.story) == "string" and g.story ~= "" then return { summary = g.story } end
    return nil
end

-- Lignes du journal de récit du groupe g, la plus ancienne d'abord (entrées dont la clé ne se résout pas omises).
function Traces.entries(g, resolve)
    local out = {}
    local views = Journal().view(g, 0)
    for _, v in ipairs(views) do
        local text = Journal().compose(v, resolve)
        if text ~= nil then
            local line
            if isInt(v.hour, 0, 23) then
                line = resolve(Traces.KEY .. "Entry", tostring(v.day), string.format("%02d", v.hour), text)
            else
                line = resolve(Traces.KEY .. "EntryDay", tostring(v.day), text)
            end
            out[#out + 1] = line or text
        end
    end
    return out
end

-- Pages du carnet du foyer (rend aussi le nombre d'entrées omises), ou nil sans traductions.
function Traces.homePages(g, resolve, lang)
    resolve = resolve or Traces.resolver()
    if resolve == nil then return nil, "no translations" end
    local head = { resolve(Traces.KEY .. "HomeTitle", tostring(g.name)) or tostring(g.name) }
    local story = Traces.story(g, lang or Traces.language())
    if story ~= nil and story.summary ~= nil then head[#head + 1] = story.summary end
    head[#head + 1] = ""
    local entries = Traces.entries(g, resolve)
    if #entries == 0 then entries = { resolve(Traces.KEY .. "Empty", "") or "" } end
    return Traces.layout(head, entries, cfg().HOME_PAGES)
end

-- Page des notes sur le chef (entrées les plus récentes qui tiennent), ou nil sans traductions.
function Traces.chiefPages(g, resolve, lang)
    resolve = resolve or Traces.resolver()
    if resolve == nil then return nil, "no translations" end
    local head = { resolve(Traces.KEY .. "ChiefTitle", tostring(g.name)) or tostring(g.name) }
    local story = Traces.story(g, lang or Traces.language())
    if story ~= nil and story.motivation ~= nil then head[#head + 1] = story.motivation end
    head[#head + 1] = ""
    local entries = Traces.entries(g, resolve)
    if #entries == 0 then entries = { resolve(Traces.KEY .. "Empty", "") or "" } end
    return Traces.layout(head, entries, cfg().CHIEF_PAGES)
end

-- Document vanilla en lecture seule : objet fullType, pages écrites puis verrouillé, marqué (groupe, sorte).
function Traces.newDocument(fullType, pages, gid, kind)
    local item = instanceItem(fullType)
    if item == nil or not instanceof(item, "Literature") then return nil, "no writable item " .. fullType end
    for i, text in ipairs(pages) do item:addPage(i, text) end
    item:setLockedBy(Traces.LOCK)
    local md = item:getModData()
    md[Traces.TAG] = gid
    md[Traces.TAG_KIND] = kind
    return item
end

-- ================================================================ marque (registre des groupes)

local function validHomeMark(h)
    return type(h) == "table" and isInt(h.hx, 0, 2147483647) and isInt(h.hy, 0, 2147483647)
        and isInt(h.hz, -32, 31) and isInt(h.day, 0, 2147483647) and (h.state == "placing" or h.state == "done")
        and (h.where == nil or Traces.WHERE[h.where] == true)
end

-- Vrai si t est une marque bien formée.
function Traces.valid(t)
    if type(t) ~= "table" or t.v ~= Traces.FORMAT then return false end
    if t.home ~= nil and not validHomeMark(t.home) then return false end
    if t.chiefs ~= nil then
        if type(t.chiefs) ~= "table" or #t.chiefs > Traces.CHIEFS_MAX then return false end
        local n = 0
        for _ in pairs(t.chiefs) do n = n + 1 end
        if n ~= #t.chiefs then return false end
        for _, mid in ipairs(t.chiefs) do
            if not isMember(mid) then return false end
        end
    end
    return true
end

-- Marque du carnet posée pour ce foyer ?
function Traces.homeDone(g)
    local t = g and g.traces
    local home = g and g.home
    if not Traces.valid(t) or t.home == nil or type(home) ~= "table" then return false end
    return t.home.hx == home.x and t.home.hy == home.y and t.home.hz == home.z
end

local function chiefDone(g, mid)
    local t = g and g.traces
    if not Traces.valid(t) or t.chiefs == nil then return false end
    for _, k in ipairs(t.chiefs) do
        if k == mid then return true end
    end
    return false
end

-- Modifie la marque du groupe vivant gid (remise à neuf si malformée) : fn(t) ; une sauvegarde. Rend vrai si écrite.
local function writeTraces(gid, fn)
    local ok = Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil then return false, false end
        local t = live.traces
        if not Traces.valid(t) then
            if t ~= nil then log().warn("traces: malformed trace mark of %s reset", tostring(gid)) end
            t = { v = Traces.FORMAT }
        end
        fn(t)
        live.traces = t
        return true, true
    end)
    return ok == true
end

-- ================================================================ carnet du foyer

local function objectsAround(home, R, fn)
    local cell = getCell()
    if cell == nil then return end
    for dy = -R, R do
        for dx = -R, R do
            local sq = cell:getGridSquare(home.x + dx, home.y + dy, home.z)
            if sq ~= nil then fn(sq) end
        end
    end
end

local function isTrace(item, gid, kind)
    if item == nil or not item:hasModData() then return false end
    local md = item:getModData()
    return md[Traces.TAG] == gid and (kind == nil or md[Traces.TAG_KIND] == kind)
end

-- Documents du groupe autour du foyer (conteneurs et sol, zone chargée) : { { item, container, square } }.
function Traces.findDocuments(gid, home, kind)
    local out = {}
    objectsAround(home, Homes().CFG.RADIUS + 2, function(sq)
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local c = objs:get(i):getContainer()
            if c ~= nil then
                local items = c:getItems()
                for k = 0, items:size() - 1 do
                    local it = items:get(k)
                    if isTrace(it, gid, kind) then out[#out + 1] = { item = it, container = c, square = sq } end
                end
            end
        end
        local wobjs = sq:getWorldObjects()
        for i = 0, (wobjs and wobjs:size() or 0) - 1 do
            local w = wobjs:get(i)
            local it = w and w:getItem()
            if isTrace(it, gid, kind) then out[#out + 1] = { item = it, world = w, square = sq } end
        end
    end)
    return out
end

-- Conteneur où ranger le carnet : caisse ou tente de l'aménagement (ModData LKHome du groupe), sinon le conteneur
-- le plus proche du foyer dans le même bâtiment (hors de tout bâtiment pour un camp). Rend le conteneur, ou nil.
function Traces.pickContainer(gid, home)
    local H = Homes()
    local cell = getCell()
    local hsq = cell and cell:getGridSquare(home.x, home.y, home.z)
    if hsq == nil then return nil end
    local bid = H.buildingId(hsq)
    local best, bestScore
    objectsAround(home, H.CFG.RADIUS, function(sq)
        if H.buildingId(sq) ~= bid then return end
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local c = o:getContainer()
            if c ~= nil then
                local score = cheb(sq:getX(), sq:getY(), home.x, home.y)
                if o:hasModData() and o:getModData()[H.TAG] == gid then score = score - 1000 end
                if bestScore == nil or score < bestScore then best, bestScore = c, score end
            end
        end
    end)
    return best
end

-- Range le document : conteneur (transmis aux clients sur un serveur) ou sol de la case du foyer. Rend WHERE.
local function deposit(item, container, home)
    if container ~= nil then
        container:AddItem(item)
        if isServer() then sendAddItemToContainer(container, item) end
        return "container"
    end
    local sq = getCell():getGridSquare(home.x, home.y, home.z)
    sq:AddWorldInventoryItem(item, 0.5, 0.5, 0)   -- transmis aux clients (IsoGridSquare.java:5159-5178)
    return "floor"
end

-- Groupes disparus dont le carnet reste à déposer : { { gid, home } } triés par identifiant.
function Traces.pending()
    local out = Groups().update(function(data)
        local list = {}
        for gid, g in pairs(data.groups) do
            if g.gone ~= nil and type(g.home) == "table" and not Traces.homeDone(g) then
                list[#list + 1] = { gid = gid, home = { x = g.home.x, y = g.home.y, z = g.home.z } }
            end
        end
        return false, list
    end)
    if type(out) ~= "table" then return {} end
    table.sort(out, function(a, b) return a.gid < b.gid end)
    return out
end

-- Dépose le carnet du foyer du groupe gid s'il a disparu, si le foyer est prêt et si ce n'est pas déjà fait.
-- opts.force : sans attendre RETRY_MS. Rend "done" (déjà fait), la marque du carnet (déposé ou marque rétablie), ou
-- nil et la raison.
function Traces.checkHome(gid, opts)
    opts = opts or {}
    local st = Traces.state
    local g = Groups().get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no group or no home" end
    if g.gone == nil then return nil, "group not gone" end
    local home = g.home
    local hk = homeKey(home)
    if st.done[gid] == hk then return "done" end
    if Traces.homeDone(g) then
        if g.traces.home.state == "placing" then
            log().warn("traces: group %s home %s journal deposit was interrupted; not deposited again", gid, hk)
        end
        st.done[gid] = hk
        return "done"
    end
    local t = now()
    if not opts.force and st.tried[gid] ~= nil and t - st.tried[gid] < cfg().RETRY_MS then return nil, "retry later" end
    st.tried[gid] = t
    local style, why = Homes().ready(home)
    if style == nil then
        Traces.stats.notReady = Traces.stats.notReady + 1
        return nil, why
    end
    local mark = { hx = home.x, hy = home.y, hz = home.z, day = Groups().today(), state = "done" }
    if #Traces.findDocuments(gid, home, "home") > 0 then
        mark.where = "found"
        writeTraces(gid, function(tr) tr.home = mark end)
        st.done[gid] = hk
        Traces.stats.restored = Traces.stats.restored + 1
        log().warn("traces: group %s home %s already has its journal but no mark: mark restored, nothing deposited",
            gid, hk)
        return mark
    end
    local pages, omitted = Traces.homePages(g)
    if pages == nil then return nil, omitted end
    mark.state = "placing"
    if not writeTraces(gid, function(tr) tr.home = mark end) or not Groups().flush() then   -- LK13-T06 : avant le monde
        log().warn("traces: group %s home %s: mark not written, nothing deposited", gid, hk)
        return nil, "mark not written"
    end
    st.done[gid] = hk
    local ok, res, err = pcall(function()
        local item, whyItem = Traces.newDocument(cfg().HOME_ITEM, pages, gid, "home")
        if item == nil then return nil, whyItem end
        return deposit(item, Traces.pickContainer(gid, home), home)
    end)
    if not ok or res == nil then
        Traces.stats.failed = Traces.stats.failed + 1
        log().warn("traces: group %s journal not deposited: %s", gid, tostring(ok and err or res))
        return nil, "deposit failed"
    end
    mark.state, mark.where = "done", res
    writeTraces(gid, function(tr) tr.home = mark end)
    Traces.stats.homes = Traces.stats.homes + 1
    log().info("traces: group %s journal deposited at its home (%s, %d page(s), %d entr(ies) omitted)", gid, res,
        #pages, omitted)
    return mark
end

-- Examine les groupes disparus dont le foyer est chargé. reason = "chunk" (au plus une fois par SCAN_MS) ou
-- "minute". Rend le nombre de carnets déposés.
function Traces.scan(reason)
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    local st = Traces.state
    local t = now()
    if reason == "chunk" and st.lastScan ~= nil and t - st.lastScan < cfg().SCAN_MS then return 0 end
    st.lastScan = t
    local cell = getCell()
    if cell == nil or not Groups().isReady() then return 0 end
    local n = 0
    for _, p in ipairs(Traces.pending()) do
        if cell:getGridSquare(p.home.x, p.home.y, p.home.z) ~= nil then
            local res = Traces.checkHome(p.gid)
            if type(res) == "table" and res.where ~= "found" then n = n + 1 end
        end
    end
    return n
end

-- ================================================================ notes sur le chef

-- Pose les notes dans l'inventaire inv du chef mid du groupe gid (corps présent, avant le cadavre). body (facultatif)
-- reçoit la marque LKTraceChief. Rend vrai si posées, sinon faux et la raison.
function Traces.giveChiefNote(gid, mid, inv, body)
    if inv == nil then return false, "no inventory" end
    local g = Groups().get(gid)
    if g == nil then return false, "no group" end
    if g.leader ~= mid then return false, "not the leader" end
    if chiefDone(g, mid) then return false, "already given" end
    if body ~= nil then
        local md = body:getModData()
        if md[Traces.MD_BODY] ~= nil then return false, "body already has its note" end
        md[Traces.MD_BODY] = true
    end
    local pages, why = Traces.chiefPages(g)
    if pages == nil then return false, why end
    if not writeTraces(gid, function(tr)
        local list = tr.chiefs or {}
        list[#list + 1] = mid
        while #list > Traces.CHIEFS_MAX do table.remove(list, 1) end
        tr.chiefs = list
    end) or not Groups().flush() then   -- LK13-T06 : marque écrite avant les notes
        return false, "mark not written"
    end
    local item, whyItem = Traces.newDocument(cfg().CHIEF_ITEM, pages, gid, "chief")
    if item == nil then return false, whyItem end
    inv:AddItem(item)
    Traces.stats.chiefs = Traces.stats.chiefs + 1
    log().info("traces: notes put on the body of the leader %s of %s", mid, gid)
    return true
end

-- Mort d'un membre au corps présent (LK_Bodies.onZombieDead, avant le registre et avant le cadavre).
LivingKnox.listen("memberDied", "Traces.chief", function(info)
    if info.offscreen == true or info.body == nil or type(info.group) ~= "string" or not isMember(info.member) then
        return
    end
    local body = info.body
    local ok, why = Traces.giveChiefNote(info.group, info.member, body:getInventory(), body)
    if not ok and why ~= "not the leader" then
        log().debug("traces: no note on %s of %s: %s", info.member, info.group, tostring(why))
    end
end)

-- ================================================================ nettoyage (suites, administration)

-- Retire les documents du groupe trouvés autour de son foyer (zone chargée) et efface la marque. Rend le nombre retiré.
function Traces.clear(gid)
    local g = Groups().get(gid)
    local removed = 0
    if g ~= nil and type(g.home) == "table" then
        for _, d in ipairs(Traces.findDocuments(gid, g.home, nil)) do
            if d.container ~= nil then
                d.container:DoRemoveItem(d.item)
                if isServer() then sendRemoveItemFromContainer(d.container, d.item) end
            else
                d.square:transmitRemoveItemFromSquare(d.world)
            end
            removed = removed + 1
        end
    end
    if g ~= nil and g.traces ~= nil then
        Groups().update(function(data)
            local live = data.groups[gid]
            if live == nil then return false, false end
            live.traces = nil
            return true, true
        end)
    end
    Traces.state.done[gid], Traces.state.tried[gid] = nil, nil
    log().info("traces: group %s documents cleared, %d removed", tostring(gid), removed)
    return removed
end

function Traces.reset()
    Traces.state = { done = {}, tried = {}, lastScan = nil, reloaded = Traces.state.reloaded, noText = false }
end

LivingKnox.subscribe("LoadChunk", "Traces.onLoadChunk", function() Traces.scan("chunk") end)
LivingKnox.subscribe("EveryOneMinute", "Traces.onEveryOneMinute", function() Traces.scan("minute") end)

return Traces
