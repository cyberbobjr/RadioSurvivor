-- Living Knox : stock du groupe, seuils, rationnement et besoins du groupe (LK08-T07)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock

-- ================================================================ seuils, rationnement, besoins (LK08-T07)

local function tenths(v) return math.floor(v * 10 + 1e-9) / 10 end

local function rationOf(s)
    local r = type(s) == "table" and s.ration or nil
    if LivingKnox.Num.isInt(r, 0, #Stock.RATIONS - 1) then return r end
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
    if type(totals) ~= "table" or not LivingKnox.Num.isInt(members, 1, 100000) then return nil end
    local S = Stock.SUPPLY
    local out = { members = members, have = {}, want = {}, levels = {}, days = {}, needs = {} }
    local rank = {}
    local autonomy
    for i, c in ipairs(Stock.CATEGORIES) do
        rank[c] = i
        local have = totals[c]
        if not LivingKnox.Num.isInt(have, 0, 1000000) then have = 0 end
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
    if not LivingKnox.Num.isInt(current, 0, #Stock.RATIONS - 1) then current = 0 end
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
    local g = LivingKnox.Groups.get(gid)
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
    LivingKnox.Groups.update(function(data)
        local changed
        level, changed = Stock.applyRation(data.groups[gid], gid, LivingKnox.Groups.today())
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
    local G = LivingKnox.Groups
    local text = string.format("ration %s (was %s): %.1f day(s) of food and water for %d (food %d, water %d)",
        Stock.RATIONS[a.next + 1], Stock.RATIONS[a.ration + 1], a.autonomy, a.members, a.have.food, a.have.water)
    g.stock.ration = a.next
    G.appendLog(g, "ration", string.sub(text, 1, G.TEXT_MAX), day or G.today())
    LivingKnox.Log.info("stock: group %s %s", gid, text)
    return a.next, true
end
