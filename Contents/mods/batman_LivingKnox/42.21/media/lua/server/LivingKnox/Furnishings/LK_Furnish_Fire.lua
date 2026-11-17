-- Living Knox : aménagement « fire » d'un camp (LK08-T04, inscrit en LK16-T10) : un feu de camp allumé à au plus
-- CFG.FIRE_RADIUS cases du foyer, au plus près ; il devient le centre du camp (ctx.cx, ctx.cy) pour les aménagements
-- suivants (tentes). Pose par SCampfireSystem.instance:addCampfire(case), addFuel(CFG.FIRE_FUEL minutes), lightFire()
-- (M/server/Camping/SCampfireSystem.lua). Retrait par son système (flammes, contenu, objet global), aussi pour le feu
-- noté dans la marque (feu resté sans marque d'objet). Moteur : LK_Homes.lua.
if isClient() then return end

require "LivingKnox/LK_Homes"

local Homes = LivingKnox.Homes

local function campfires()
    return SCampfireSystem ~= nil and SCampfireSystem.instance or nil
end

local function plan(ctx, out)
    local R, spots = ctx.cfg.FIRE_RADIUS, {}
    for x, y in LivingKnox.Geo.squaresAround(ctx.home.x, ctx.home.y, R) do
        spots[#spots + 1] = { x = x, y = y, d = LivingKnox.Geo.cheb(x, y, ctx.home.x, ctx.home.y) }
    end
    table.sort(spots, Homes.byPlace)
    for _, s in ipairs(spots) do
        if ctx.fits(s.x, s.y, 1, 1) then
            out[#out + 1] = { k = "fire", x = s.x, y = s.y, z = ctx.z }
            ctx.reserve(s.x, s.y, 1, 1)
            ctx.cx, ctx.cy = s.x, s.y
            return
        end
    end
end

local function place(gid, _, sq)
    local sys = campfires()
    if sys == nil then return nil, "no campfire system" end
    if not Homes.clearSquare(sq) then return nil, "square no longer free" end
    local fire = sys:addCampfire(sq)
    if fire == nil then return nil, "campfire refused" end
    fire:addFuel(Homes.CFG.FIRE_FUEL)
    fire:lightFire()
    -- Marque du groupe sur l'objet du feu : le système vanilla n'écrit que ses propres clés dans cette ModData
    -- (SCampfireGlobalObject:toModData), la marque reste et permet de retrouver le feu sans la marque du foyer.
    local iso = fire.getIsoObject and fire:getIsoObject() or nil
    if iso ~= nil then Homes.tagObject(iso, gid, "fire") end
    return true
end

-- Retrait : case du feu marqué gardée pour finish.
local function collect(_, sq)
    return { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
end

local function finish(fires, cell, mark)
    for _, p in ipairs(type(mark.placed) == "table" and mark.placed or {}) do
        if p.k == "fire" then fires[#fires + 1] = p end
    end
    local sys, removed = campfires(), 0
    for _, p in ipairs(fires) do
        if sys ~= nil then
            local sq = cell:getGridSquare(p.x, p.y, p.z)
            local fire = sq and sys:getLuaObjectOnSquare(sq)
            if fire then
                sys:removeCampfire(fire)
                removed = removed + 1
            end
        end
    end
    return removed
end

Homes.registerFurnishing("fire", { style = "camp", order = 50, plan = plan, place = place,
    clear = { collect = collect, finish = finish } })
