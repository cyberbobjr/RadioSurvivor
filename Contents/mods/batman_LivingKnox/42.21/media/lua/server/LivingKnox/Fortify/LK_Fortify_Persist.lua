-- Living Knox : fortification du foyer, relevé hors écran gardé au registre des groupes : réglages et vue de
-- travail (forme 1), forme compacte (LK13-T07 : packFort, parseFort, fortView, migrate), octet pour octet
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

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
--       (sorte : lettre inscrite par sa spec, spec.code, LK16-T02)
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
Fortify.OFF_PEND_MAX = 256    -- écarts de pose en attente au plus
Fortify.CFG.OFF_WORK_MINUTES = Fortify.CFG.OFF_WORK_MINUTES or 30   -- minutes de travail utiles par ouvrier et par
                              -- heure hors écran (trajets et pauses du travail visible : moitié de l'heure)
Fortify.CFG.SCAN_MS = Fortify.CFG.SCAN_MS or 1000   -- examen depuis LoadChunk au plus une fois par seconde
for _, k in ipairs({ "offHours", "offSteps", "applied", "placed", "already", "adopted", "dropped", "kept",
    "snapshots", "boxesOpened", "migrated" }) do
    Fortify.stats[k] = Fortify.stats[k] or 0
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
    if not LivingKnox.Num.isInt(p.n, 0, 2147483647) or type(p.ops) ~= "table"
        or #p.ops > Fortify.OFF_PEND_MAX then return false end
    for name, t in pairs(f.tiers) do
        if not TIER_SET[name] or type(t) ~= "table" or not LivingKnox.Num.isInt(t.s, 0, 100000)
            or not LivingKnox.Num.isInt(t.h, 0, t.s) then
            return false
        end
    end
    for _, e in ipairs(f.sites) do
        if type(e) ~= "table" or type(e.id) ~= "string" or not Fortify.OFF_KINDS[e.k] or not TIER_SET[e.t]
            or not LivingKnox.Num.isInt(e.x, -1e7, 1e7) or not LivingKnox.Num.isInt(e.y, -1e7, 1e7)
                or not LivingKnox.Num.isInt(e.z, -32, 31)
            or not LivingKnox.Num.isInt(e.s, 1, 4) or not LivingKnox.Num.isInt(e.h, 0, e.s) then
            return false
        end
    end
    for _, op in ipairs(p.ops) do
        if type(op) ~= "table" or not LivingKnox.Num.isInt(op.u, 1, p.n) or type(op.id) ~= "string" or not Fortify.OFF_KINDS[op.k]
            or not LivingKnox.Num.isInt(op.x, -1e7, 1e7) or not LivingKnox.Num.isInt(op.y, -1e7, 1e7)
                or not LivingKnox.Num.isInt(op.z, -32, 31)
            or not LivingKnox.Num.isInt(op.a, 0, 3) or not LivingKnox.Num.isInt(op.b, op.a + 1, 4) then
            return false
        end
    end
    for _, b in ipairs(f.boxes) do
        if type(b) ~= "table" or not LivingKnox.Num.isInt(b.i, -2147483648, 2147483647)
            or not LivingKnox.Num.isInt(b.u, 1, P.cfg().BOX_NAILS) then
            return false
        end
    end
    return true
end

-- ---------------------------------------------------------------- forme compacte (LK13-T07)
-- LK16-T02 : lettre de chaque sorte (spec.code) et motifs des chantiers et des écarts tirés du registre
-- (Fortify.kinds.byCode, sitePattern, opPattern).
local TIER_CODE = { ground = "g", upper = "u", outer = "o" }
local CODE_TIER = { g = "ground", u = "upper", o = "outer" }
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
    local K = Fortify.kinds
    local sites, ops = split(f.sites, ";"), split(f.ops, ";")
    if K.sitePattern == nil and (#sites > 0 or #ops > 0) then return nil end   -- aucune sorte gardée hors écran
    for _, txt in ipairs(sites) do
        local k, t, dx, dy, z, n, o, s, h = string.match(txt, K.sitePattern)
        if k == nil then return nil end
        local kind, x, y = K.byCode[k], hx + tonumber(dx), hy + tonumber(dy)
        view.sites[#view.sites + 1] = { id = Fortify.siteId(kind, x, y, tonumber(z), n == "N"), k = kind, t = CODE_TIER[t],
            x = x, y = y, z = tonumber(z), n = n == "N", o = o == "1", s = tonumber(s), h = tonumber(h) }
    end
    for _, txt in ipairs(ops) do
        local u, k, dx, dy, z, n, o, a, b = string.match(txt, K.opPattern)
        if u == nil then return nil end
        local kind, x, y = K.byCode[k], hx + tonumber(dx), hy + tonumber(dy)
        view.pend.ops[#view.pend.ops + 1] = { u = tonumber(u), id = Fortify.siteId(kind, x, y, tonumber(z), n == "N"), k = kind,
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
    local byId = Fortify.kinds.byId
    local sites = {}
    for i, e in ipairs(view.sites) do
        sites[i] = byId[e.k].code .. TIER_CODE[e.t] .. (e.x - hx) .. "," .. (e.y - hy) .. "," .. e.z .. face(e.n)
            .. flag(e.o) .. e.s .. e.h
    end
    local ops = {}
    for i, op in ipairs(view.pend.ops) do
        ops[i] = op.u .. ":" .. byId[op.k].code .. (op.x - hx) .. "," .. (op.y - hy) .. "," .. op.z .. face(op.n)
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
    local G = LivingKnox.Groups
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
        LivingKnox.Log.info("fortify: %d offscreen survey(s) rewritten in the compact form", n)
    end
    return n
end

-- Relevé hors écran f valide pour le foyer home (l'une ou l'autre forme).
local function validFort(f, home)
    return fortView(f, home) ~= nil
end
Fortify.validFort = validFort

-- LK20-T07 : fonctions privées partagées avec les autres fichiers de Fortify/ (table Fortify._).
P.readView = readView
