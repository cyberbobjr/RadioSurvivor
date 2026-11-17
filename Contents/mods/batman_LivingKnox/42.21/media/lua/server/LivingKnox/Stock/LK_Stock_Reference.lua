-- Living Knox : stock du groupe, catégories des objets et inventaire de référence au registre des groupes (forme, journal
-- d'écarts en attente, totaux)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

local CATEGORY_SET = {}
for _, c in ipairs(Stock.CATEGORIES) do CATEGORY_SET[c] = true end

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
    return type(e) == "table" and LivingKnox.Num.isInt(e.i, -2147483648, 2147483647) and type(e.t) == "string" and #e.t > 0
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
    return LivingKnox.Groups.update(function(data)
        local live = data.groups[gid]
        if live == nil then return false, false end
        live.stock = ref
        return true, true
    end)
end

-- LK09-T06 : journal d'écarts en attente (champ facultatif stock.pend). Invalide = ignoré (jamais une raison
-- d'écarter la référence : le kit serait recréé).
local function validOp(op, n)
    if type(op) ~= "table" or not LivingKnox.Num.isInt(op.u, 1, n) then return false end
    if op.o == "take" then return validItem(op) end
    if op.o == "add" then
        return type(op.t) == "string" and #op.t > 0 and #op.t <= Stock.TYPE_MAX and CATEGORY_SET[op.c] == true
    end
    return false
end

function Stock.validPend(p)
    if type(p) ~= "table" or not LivingKnox.Num.isInt(p.n, 0, 2147483647) or type(p.ops) ~= "table"
        or #p.ops > Stock.PEND_MAX then
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
        LivingKnox.Log.warn("stock: group %s pending stock changes malformed, dropped", tostring(gid))
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
    local g = LivingKnox.Groups.get(gid)
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

P.writeRef, P.pendOf = writeRef, pendOf
