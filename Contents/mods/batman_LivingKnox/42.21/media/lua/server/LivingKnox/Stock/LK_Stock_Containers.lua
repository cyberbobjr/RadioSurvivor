-- Living Knox : stock du groupe, conteneurs du foyer, lecture de leurs objets et remplissage initial du kit
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock

-- ================================================================ conteneurs du foyer

local function tagged(o, gid)
    return o ~= nil and o:hasModData() and o:getModData()[LivingKnox.Homes.TAG] == gid
end

-- Conteneurs du foyer : liste triée { { key, container, owned, object, x, y, z } } (owned = objet posé par LK_Homes
-- pour le groupe ; x, y, z = case de l'objet), ou nil et la raison si une case de la zone n'est pas lisible.
function Stock.containers(gid, home, style, bid)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local R, z = LivingKnox.Homes.CFG.RADIUS, home.z
    local out = {}
    for x, y in LivingKnox.Geo.squaresAround(home.x, home.y, R) do
        local sq = cell:getGridSquare(x, y, z)
        if sq == nil then return nil, "home area not loaded" end
        local inBuilding = style == "building" and LivingKnox.Homes.buildingId(sq) == bid
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
                LivingKnox.Log.warn("stock: group %s: %s not created: %s", gid, tostring(entry[1]), tostring(ok and why or item))
            end
        end
    end
    return made, failed
end
