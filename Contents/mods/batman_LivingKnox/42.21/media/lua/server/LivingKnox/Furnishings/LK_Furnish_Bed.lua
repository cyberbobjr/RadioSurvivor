-- Living Knox : aménagement « bed » d'un foyer de bâtiment (LK08-T04, inscrit en LK16-T10) : des sacs de couchage
-- jusqu'à un couchage par membre vivant (CFG.MAX_BEDS au plus, lits existants comptés), au plus près du foyer. Sac de
-- couchage vert camping_02_16 + _17 (newtiledefinitions.tiles.txt 42.21 : bed, BedType badBed, nord ; deux cases en
-- x). Pose par défaut du moteur (meuble vanilla). Moteur : LK_Homes.lua.
if isClient() then return end

require "LivingKnox/LK_Homes"

local Homes = LivingKnox.Homes

local BAG = { sprite = "camping_02_16", w = 2, h = 1 }

local function plan(ctx, out)
    local need = math.min(ctx.cfg.MAX_BEDS, ctx.members) - ctx.beds
    for _, s in ipairs(ctx.inside) do
        if need <= 0 then break end
        if ctx.fits(s.x, s.y, BAG.w, BAG.h) then
            out[#out + 1] = { k = "bed", x = s.x, y = s.y, z = ctx.z, v = "bed" }
            ctx.reserve(s.x, s.y, BAG.w, BAG.h)
            need = need - 1
        end
    end
end

Homes.registerFurnishing("bed", { style = "building", order = 30, plan = plan, furniture = { bed = BAG } })
