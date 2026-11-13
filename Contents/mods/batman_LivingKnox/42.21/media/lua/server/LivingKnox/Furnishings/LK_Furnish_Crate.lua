-- Living Knox : aménagement « crate » d'un foyer de bâtiment (LK08-T04, inscrit en LK16-T10) : CFG.CRATES caisses
-- vides (réserve du stock, LK_Stock la remplit), au fond (cases les plus éloignées du foyer). Caisse carpentry_01_16
-- (newtiledefinitions.tiles.txt 42.21 : container crate, 60). Pose par défaut du moteur (meuble vanilla). Une sorte
-- inconnue relue sur un objet marqué vaut « crate » (Homes.findTagged). Moteur : LK_Homes.lua.
if isClient() then return end

require "LivingKnox/LK_Homes"

local Homes = LivingKnox.Homes

local function plan(ctx, out)
    local inside, crates = ctx.inside, 0
    for i = #inside, 1, -1 do
        if crates >= ctx.cfg.CRATES then break end
        local s = inside[i]
        if ctx.fits(s.x, s.y, 1, 1) then
            out[#out + 1] = { k = "crate", x = s.x, y = s.y, z = ctx.z, v = "crate" }
            ctx.reserve(s.x, s.y, 1, 1)
            crates = crates + 1
        end
    end
end

Homes.registerFurnishing("crate", { style = "building", order = 40, plan = plan,
    furniture = { crate = { sprite = "carpentry_01_16", w = 1, h = 1 } } })
