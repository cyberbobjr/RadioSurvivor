-- Living Knox : stock du groupe, joueurs, vols constatés, différence et relecture (Stock.check)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

local function homeKey(home) return home.x .. "," .. home.y .. "," .. home.z end

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
        LivingKnox.Log.warn("stock: group %s: %d item(s) taken by %s, not reported: %s", gid, n, name, tostring(why))
        return "no key"
    end
    local slot = gid .. "|" .. key
    local h = hourNow()
    local last = Stock.state.lastTheft[slot]
    if last ~= nil and h - last < P.cfg().THEFT_COOLDOWN_HOURS and h >= last then
        LivingKnox.Log.info("stock: group %s: %d more item(s) taken by %s (theft already reported this hour)", gid, n, name)
        return "cooldown"
    end
    local res, err = H.record(gid, key, "theft", { attributable = true, day = LivingKnox.Groups.today() })
    if res == nil then
        LivingKnox.Log.warn("stock: group %s: theft by %s not recorded: %s", gid, name, tostring(err))
        return "no key"
    end
    Stock.state.lastTheft[slot] = h
    Stock.stats.thefts = Stock.stats.thefts + 1
    LivingKnox.Log.info("stock: group %s: %d item(s) taken by %s, theft reported (attitude %s)", gid, n, name,
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

-- Relecture, étape 1 : contrôles d'entrée et conteneurs lisibles du foyer. Rend la liste de Stock.containers, ou nil
-- et la raison.
local function readableContainers(gid, opts)
    -- LK13-T08 : contrôles d'entrée sur la lecture en place (seule, sans copie : appelé à chaque minute de jeu) ;
    -- copie du groupe seulement pour une relecture effective (zone chargée, conteneurs trouvés).
    local view = LivingKnox.Groups.peek(gid)
    if view == nil or type(view.home) ~= "table" then return nil, "no group or no home" end
    if not LivingKnox.Homes.validMark(view.furnish, view.home) then return nil, "home not furnished yet" end
    local t = P.now()
    local st = Stock.state
    if not opts.force and st.checked[gid] ~= nil and t - st.checked[gid] < P.cfg().CHECK_MS then
        return nil, "checked recently"
    end
    st.checked[gid] = t
    local style, def = LivingKnox.Homes.ready(view.home)
    if style == nil then return nil, def end
    local bid = def ~= nil and def:getIDString() or nil
    return Stock.containers(gid, view.home, style, bid)
end

-- Relecture, étape 2 : référence absente ou invalide (première relecture, foyer déplacé) : rétablie d'après les
-- objets marqués du groupe déjà présents, sinon kit créé (marque écrite avant le monde). Rend le rapport, ou nil et la
-- raison.
local function newReference(gid, g, ref, containers, real, report, hk)
    local home = g.home
    if ref ~= nil then LivingKnox.Log.warn("stock: group %s stock reference replaced (home moved or bad reference)", gid) end
    local mark = { v = Stock.FORMAT, hx = home.x, hy = home.y, hz = home.z, fill = "filling",
                   day = LivingKnox.Groups.today(), items = {} }
    if anyTagged(real, gid) then
        mark.fill = "done"
        report.action = "restored"
        LivingKnox.Log.warn("stock: group %s home %s already holds the group's stock but no reference: reference restored,"
            .. " nothing created", gid, hk)
    else
        if not P.writeRef(gid, mark) or not LivingKnox.Groups.flush() then   -- LK13-T06 : marque écrite avant le monde
            LivingKnox.Log.warn("stock: group %s home %s: stock mark not written, nothing created", gid, hk)
            return nil, "mark not written"
        end
        local made, failed = Stock.fill(gid, g.type, containers)
        mark.fill = "done"
        report.action = "filled"
        Stock.stats.filled = Stock.stats.filled + 1
        Stock.stats.created = Stock.stats.created + made
        real = Stock.read(containers)
        LivingKnox.Log.info("stock: group %s home %s: %d item(s) stored (%s kit)%s", gid, hk, made,
            Stock.KITS[g.type] and g.type or Stock.DEFAULT_KIT, failed > 0 and (", " .. failed .. " failed") or "")
    end
    local items, over = bounded(real, {})
    mark.items = items
    if over > 0 then LivingKnox.Log.info("stock: group %s: %d item(s) beyond the tracked limit", gid, over) end
    P.writeRef(gid, mark)
    report.items, report.totals = items, Stock.count(items)
    report.ration = Stock.updateRation(gid)
    return report
end

-- Relecture, étape 3 (LK09-T06) : écarts de la vie hors écran appliqués aux conteneurs réels avant la différence.
-- Rend la référence et le contenu réel relus, ou nil, nil et la raison.
local function applyOffscreen(gid, g, home, containers, report)
    report.applied = Stock.applyPending(gid, containers, g)
    g = LivingKnox.Groups.get(gid)
    local ref = g ~= nil and g.stock or nil
    if g == nil or not Stock.validRef(ref, home) then return nil, nil, "reference lost while applying" end
    return ref, Stock.read(containers)
end

-- Relecture, étape 4 : objets disparus cherchés chez les joueurs connectés ; vol rapporté par joueur, perte sans
-- coupable comptée.
local function reportMissing(gid, missing, report)
    local list = players()
    local byPlayer, order = {}, {}
    for _, e in ipairs(missing) do
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
        LivingKnox.Log.info("stock: group %s: %d item(s) gone without a known taker", gid, report.lost)
    end
end

-- Relecture, étape 5 : la référence devient le contenu réel (écrite seulement si elle change), rationnement relu.
-- Rend le rapport.
local function storeChecked(gid, home, ref, real, d, report)
    local oldIds = {}
    for _, e in ipairs(ref.items) do oldIds[e.i] = true end
    local items = bounded(real, oldIds)
    report.action = "checked"
    report.items, report.totals = items, Stock.count(items, ref.pend)
    if not sameItems(items, ref.items) or ref.fill ~= "done" then
        P.writeRef(gid, { v = Stock.FORMAT, hx = home.x, hy = home.y, hz = home.z, fill = "done", day = LivingKnox.Groups.today(),
                        items = items, ration = ref.ration, pend = ref.pend })
        if d.added > 0 or d.moved > 0 then
            LivingKnox.Log.debug("stock: group %s: %d item(s) added, %d moved", gid, d.added, d.moved)
        end
    end
    report.ration = Stock.updateRation(gid)   -- LK08-T07 : membres ou stock changés
    return report
end

-- Relit le stock d'un groupe (remplissage initial la première fois). opts.force : sans attendre CHECK_MS.
-- Rend un rapport { action = "filled" | "restored" | "checked", items, totals, missing, added, moved,
-- thefts = { { player, items, result } }, lost, ration (niveau après relecture, LK08-T07, ou nil) }, ou nil et la
-- raison. LK20-T08 : étapes nommées ci-dessus, même ordre qu'avant.
function Stock.check(gid, opts)
    opts = opts or {}
    local containers, why = readableContainers(gid, opts)
    if containers == nil then return nil, why end
    local g = LivingKnox.Groups.get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no group or no home" end
    local home = g.home
    Stock.stats.checks = Stock.stats.checks + 1
    local real = Stock.read(containers)
    local ref = g.stock
    local hk = homeKey(home)
    local report = { missing = 0, added = 0, moved = 0, thefts = {}, lost = 0 }

    if not Stock.validRef(ref, home) then return newReference(gid, g, ref, containers, real, report, hk) end

    if ref.fill == "filling" then
        LivingKnox.Log.warn("stock: group %s home %s was left half filled (interrupted); not filled again", gid, hk)
    end
    if Stock.pendingCount(ref) > 0 then
        local lostWhy
        ref, real, lostWhy = applyOffscreen(gid, g, home, containers, report)
        if ref == nil then return nil, lostWhy end
    end
    local d = Stock.diff(ref.items, real)
    report.missing, report.added, report.moved = #d.missing, d.added, d.moved
    if #d.missing > 0 then reportMissing(gid, d.missing, report) end
    return storeChecked(gid, home, ref, real, d, report)
end

P.hourNow = hourNow
