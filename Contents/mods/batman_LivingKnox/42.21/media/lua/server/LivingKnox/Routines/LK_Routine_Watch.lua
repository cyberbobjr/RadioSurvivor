-- Living Knox : routine « guet et ronde » des PNJ au foyer (LK05-T03, découpée en LK15-T02, ADR D05) : guetteur à son
-- poste, ronde autour du foyer (comportements « guard » et « patrol »). Ce fichier porte le choix guet ou ronde selon
-- l'heure (Routines.sentryKind, lu par LK_Decisions) et le plan de chaque activité (LK16-T07) ; le relevé, les
-- affectations et l'exécution sont dans LK_Routines.lua (Routines.runPlanned). Autorité seulement.
if isClient() then return end

require "LivingKnox/LK_Routines"

local Routines = LivingKnox.Routines

local function cfg() return Routines.CFG end

-- Guet ("guard") ou ronde ("patrol") du guetteur à l'heure hour, selon les postes relevés (posts, ou nil).
function Routines.sentryKind(hour, posts)
    local hasRound = type(posts) == "table" and type(posts.round) == "table" and #posts.round >= cfg().MIN_ROUND
    if not hasRound then return "guard" end
    local p = Routines.period(hour)
    if p == "night" then return "guard" end
    if p == "dawn" then return "patrol" end
    if Routines.hourInWatch(hour) == 0 then return "patrol" end
    return "guard"
end

-- Sans poste ni ronde : regard dans la direction angle.
local function face(angle) return { kind = "face", key = "face", a = angle } end

-- Guet : aller au poste du quart, regarder dehors.
local function guardPlan(posts, g, mid, hour, angle)
    local p = Routines.postFor(posts, g, mid, hour)
    if p == nil then return face(angle) end
    return { kind = "post", key = string.format("post %d,%d,%d", p.x, p.y, p.z), x = p.x, y = p.y, z = p.z, a = p.a,
        what = p.k }
end

-- Ronde : boucle relevée, départ réparti entre guetteurs.
local function patrolPlan(posts, g, mid, hour, angle)
    if type(posts) == "table" and #posts.round >= cfg().MIN_ROUND then
        return { kind = "round", key = "round", points = posts.round, start = Routines.roundStart(posts, g, mid) }
    end
    return face(angle)
end

Routines.registerActivity({ id = "watch.guard", behaviour = "guard", order = 10, plan = guardPlan })
Routines.registerActivity({ id = "watch.patrol", behaviour = "patrol", order = 10, plan = patrolPlan })
