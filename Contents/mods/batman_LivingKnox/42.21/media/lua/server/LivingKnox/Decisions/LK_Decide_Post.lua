-- Living Knox : comportements de poste de la cascade (LK16-T06, chantier C2), menés hors du moteur de décision : guet
-- (« guard » : au poste, regard vers l'extérieur du foyer) et ronde (« patrol »). Fiches :
-- docs/annexes/conception/decisions.md, routines.md. La règle duty qui les propose reste dans LK_Decisions.lua ; avec
-- les routines chargées (LK_Routines, activités watch.guard et watch.patrol), la routine les mène au foyer ; sinon ce
-- fichier : retour au foyer s'il est loin, regard vers l'angle de guet tiré à la décision (visée aim).
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Decisions"

local Decisions = LivingKnox.Decisions
local Post = LivingKnox.DecidePost or {}
LivingKnox.DecidePost = Post

-- Regard vers l'extérieur du foyer (sinon direction tirée), décalé de -45, 0 ou +45 degrés.
function Post.aimGuard(ctx, out, rnd)
    local base
    if ctx.home then base = Decisions.angleTo(ctx.x - (ctx.home.x + 0.5), ctx.y - (ctx.home.y + 0.5)) end
    if base == nil then base = Decisions.pick(0, 7, rnd) * 45 end
    local a = base + (Decisions.pick(0, 2, rnd) - 1) * 45
    out.angle = a - math.floor(a / 360) * 360
end

-- Sans routine : à l'état neuf, retour au foyer s'il est loin, sinon regard vers l'angle de guet (ronde : aucun).
function Post.apply(id, st, ctx, fresh)
    if not fresh then return end
    if ctx.home ~= nil and not ctx.atHome then
        Decisions.goHome(id, ctx)
    else
        Decisions.face(id, st.angle)
    end
end

Decisions.registerExtension({ id = "guard", order = 80, overlay = true, aim = Post.aimGuard, apply = Post.apply })
Decisions.registerExtension({ id = "patrol", order = 81, overlay = true, apply = Post.apply })

return Post
