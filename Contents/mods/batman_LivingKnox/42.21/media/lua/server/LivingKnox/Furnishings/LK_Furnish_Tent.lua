-- Living Knox : aménagement « tent » d'un camp (LK08-T04, inscrit en LK16-T10) : une tente pour CFG.PER_TENT membres
-- vivants (au moins une, CFG.MAX_TENTS au plus) autour du centre du camp (feu, sinon le foyer), aux écarts
-- CFG.TENT_RINGS. Petite tente camping_01_1 + _0 (est) ou camping_01_2 + _3 (sud) (newtiledefinitions.tiles.txt 42.21 :
-- bed, badBed, container tent 30). Pose par défaut du moteur (meuble vanilla). Moteur : LK_Homes.lua.
if isClient() then return end

require "LivingKnox/LK_Homes"

local Homes = LivingKnox.Homes

local TENTS = {
    tentE = { sprite = "camping_01_1", w = 1, h = 2 },
    tentS = { sprite = "camping_01_2", w = 2, h = 1 },
}

-- Ouest, est, nord, sud, puis les diagonales ; tente « est » (verticale) sur les côtés ouest et est.
local AROUND = { { -1, 0, "tentE" }, { 1, 0, "tentE" }, { 0, -1, "tentS" }, { 0, 1, "tentS" },
    { -1, -1, "tentS" }, { 1, -1, "tentS" }, { -1, 1, "tentS" }, { 1, 1, "tentS" } }

local function plan(ctx, out)
    local c = ctx.cfg
    local tents = math.max(1, math.min(c.MAX_TENTS, math.ceil(ctx.members / c.PER_TENT)))
    ctx.info.tents = tents
    local placed = 0
    for _, r in ipairs(c.TENT_RINGS) do
        for _, a in ipairs(AROUND) do
            if placed >= tents then break end
            local f = TENTS[a[3]]
            local x, y = ctx.cx + a[1] * r, ctx.cy + a[2] * r
            if ctx.fits(x, y, f.w, f.h) then
                out[#out + 1] = { k = "tent", x = x, y = y, z = ctx.z, v = a[3] }
                ctx.reserve(x, y, f.w, f.h)
                placed = placed + 1
            end
        end
    end
end

Homes.registerFurnishing("tent", { style = "camp", order = 60, plan = plan, furniture = TENTS })
