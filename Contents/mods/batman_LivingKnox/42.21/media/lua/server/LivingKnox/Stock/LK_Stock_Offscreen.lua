-- Living Knox : stock du groupe, stock hors écran, logique pure sur le registre (LK09-T06, LK14-T05)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

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
    local p = P.pendOf(s, true, gid)
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
    LivingKnox.Log.debug("stock: group %s offscreen meal (hour %s, %d eater(s), ration %s): food %d/%d, water %d/%d", gid,
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
    local p = P.pendOf(s, true, gid)
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
    LivingKnox.Log.debug("stock: group %s offscreen expedition loot pending: %s", gid, table.concat(parts, " "))
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
    local p = P.pendOf(s, false)
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
    if not LivingKnox.Num.isInt(n, 1, Stock.MAX_ITEMS) or Stock.offscreenCount(g.stock, types) < n then return 0 end
    local s = g.stock
    local p = P.pendOf(s, true, gid)
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
