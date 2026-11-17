-- Living Knox : fortification du foyer, plan pur (chantiers d'un relevé, ordre, niveau : Fortify.build), sans
-- aucun appel au jeu
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

-- ================================================================ plan (pur)

local function req(types, n) return { types = types, n = n } end
Fortify.req = req   -- LK16-T02 : besoin { types, n } des fichiers de sorte

local function siteId(kind, x, y, z, north) return kind .. ":" .. x .. "," .. y .. "," .. z .. (north and "N" or "W") end
Fortify.siteId = siteId

-- Chantier de barricade d'une ouverture e jusqu'à target planches.
local function barricadeSite(e, tier, target)
    local have = e.metal and target or math.min(e.planks, target)
    local need = target - have
    local site = { id = siteId("barricade", e.x, e.y, e.z, e.north), kind = "barricade", tier = tier,
        opening = e.kind, x = e.x, y = e.y, z = e.z, north = e.north, opp = e.opp,
        inside = { x = e.inX, y = e.inY }, outside = { x = e.outX, y = e.outY },
        have = have, steps = target, done = need <= 0, entity = "BarricadePlanks",
        tools = {}, materials = {}, time = 0 }
    if need > 0 then
        site.materials = { req({ Fortify.PLANK }, need), req({ Fortify.NAILS }, need) }
        site.tools = { "HAMMER" }
        site.time = need * P.cfg().TIME.plank
    end
    return site
end

-- Chantier d'un segment de pourtour de la sorte kind (ouvrage déjà sur le bord : sa sorte), tiré des étapes inscrites
-- (spec.stages, LK16-T02) : étapes visées et faites, entité (liste si plusieurs étapes), matériaux des étapes restantes
-- (même type additionné, ordre de première apparition), outils (sans doublon), durée (CFG.TIME de chaque étape).
local function ringSite(e, kind)
    if e.built ~= nil then kind = e.built end
    -- LK14-T04 : case intérieure (dans le pourtour) et extérieure du bord. Côtés N et W : le bord est porté par la
    -- case intérieure (x, y) ; côtés E et S : par la case extérieure.
    local inside, outside = { x = e.x, y = e.y }, { x = e.ox, y = e.oy }
    if e.side == "E" or e.side == "S" then inside, outside = outside, inside end
    local site = { id = siteId(kind, e.x, e.y, e.z, e.north), kind = kind, tier = "outer", x = e.x, y = e.y, z = e.z,
        north = e.north, side = e.side, pos = e.pos, inside = inside, outside = outside }
    local T = P.cfg().TIME
    local stages = Fortify.STAGES[kind]
    site.steps, site.have = #stages, e.steps or 0
    if #stages == 1 then
        site.entity = stages[1].entity
    else
        site.entity = {}
        for i, st in ipairs(stages) do site.entity[i] = st.entity end
    end
    local materials, byTypes, tools, seen, time = {}, {}, {}, {}, 0
    for n = site.have + 1, #stages do
        local st = stages[n]
        for _, r in ipairs(st.materials) do
            local key = table.concat(r.types, ",")
            local m = byTypes[key]
            if m == nil then
                m = req(r.types, 0)
                byTypes[key] = m
                materials[#materials + 1] = m
            end
            m.n = m.n + r.n
        end
        if st.tool ~= nil and not seen[st.tool] then
            seen[st.tool] = true
            tools[#tools + 1] = st.tool
        end
        time = time + (T[st.time] or 0)
    end
    site.materials, site.tools, site.time = materials, tools, time
    site.done = site.have >= site.steps
    return site
end

-- Quantité d'une pièce de réparation selon les dégâts (0..1) : floor(max(n x dégâts, 1)), comme
-- ISMoveableSpriteProps:getRepairPartsForMaterial (ISMoveableSpriteProps.lua:840-869).
function Fortify.repairAmount(n, damage)
    return math.floor(math.max(n * damage, 1))
end

-- Pièces de la réparation d'un ouvrage target ("wall", "palisade") à l'état health (0..1) : requises, facultatives.
function Fortify.repairParts(target, health)
    local r = Fortify.REPAIRS[target]
    local damage = math.max(0, math.min(1, 1 - (health or 1)))
    local options = {}
    for _, o in ipairs(r.options) do options[#options + 1] = req({ o[1] }, Fortify.repairAmount(o[2], damage)) end
    return { req({ r.part[1] }, Fortify.repairAmount(r.part[2], damage)) }, options
end

-- Chantier de réparation de la barricade complète d'une ouverture e (planche extérieure abîmée) : une planche saine
-- et un clou, marteau ; retrait puis pose d'une planche.
local function barricadeRepairSite(e, tier)
    local T = P.cfg().TIME
    return { id = siteId("repair", e.x, e.y, e.z, e.north), kind = "repair", target = "barricade", tier = tier,
        opening = e.kind, x = e.x, y = e.y, z = e.z, north = e.north, opp = e.opp,
        inside = { x = e.inX, y = e.inY }, outside = { x = e.outX, y = e.outY }, cond = e.cond,
        have = 0, steps = 1, done = false, tools = { "HAMMER" },
        materials = { req({ Fortify.PLANK }, 1), req({ Fortify.NAILS }, 1) }, time = 2 * T.plank }
end

-- Chantier de réparation d'un ouvrage achevé du pourtour (mur, palissade) sous REPAIR_BELOW.
local function ringRepairSite(e)
    local base = ringSite(e, e.built)
    local materials, options = Fortify.repairParts(e.built, e.health)
    return { id = siteId("repair", e.x, e.y, e.z, e.north), kind = "repair", target = e.built, tier = "outer",
        x = e.x, y = e.y, z = e.z, north = e.north, side = e.side, pos = e.pos, inside = base.inside,
        outside = base.outside, cond = e.health, have = 0, steps = 1, done = false,
        tools = Fortify.REPAIRS[e.built].tools, materials = materials, options = options,
        time = P.cfg().TIME.repair or 1000 }
end

local function needsRepair(v)
    return v ~= nil and v < P.cfg().REPAIR_BELOW
end

local function openingOrder(a, b)
    local ra, rb = Fortify.OPENING_RANK[a.opening], Fortify.OPENING_RANK[b.opening]
    if ra ~= rb then return ra < rb end
    if a.d ~= b.d then return a.d > b.d end
    if a.z ~= b.z then return a.z < b.z end
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return (a.north and 1 or 0) < (b.north and 1 or 0)
end

local SIDE_RANK = { N = 1, E = 2, S = 3, W = 4 }
local GAP_SIDE_RANK = { S = 1, E = 2, N = 3, W = 4 }   -- départage de la brèche (camp : sud d'abord)

-- Entrée du foyer : porte extérieure barricadable du rez-de-chaussée la plus proche de la case du foyer, ou nil.
function Fortify.entryOf(survey)
    local best
    local h = survey.home
    for _, e in ipairs(survey.openings or {}) do
        if e.kind == "door" and e.z == 0 and e.allowed then
            local d = LivingKnox.Geo.cheb(e.inX, e.inY, h.x, h.y)
            local better = best == nil or d < best.d
                or (d == best.d and (e.y < best.e.y or (e.y == best.e.y and (e.x < best.e.x
                or (e.x == best.e.x and e.north and not best.e.north)))))
            if better then best = { e = e, d = d } end
        end
    end
    return best and best.e or nil
end

-- Avancement pondéré (0..100) de chantiers : étapes faites / étapes visées par tier, pondérées par WEIGHTS ; aucun
-- chantier : 100.
function Fortify.levelOfSites(sites)
    local per = {}
    for _, t in ipairs(Fortify.TIERS) do per[t] = { have = 0, steps = 0 } end
    for _, s in ipairs(sites) do
        local p = per[s.tier]
        p.have, p.steps = p.have + math.min(s.have, s.steps), p.steps + s.steps
    end
    local num, den = 0, 0
    for _, t in ipairs(Fortify.TIERS) do
        local p, w = per[t], P.cfg().WEIGHTS[t] or 0
        if p.steps > 0 and w > 0 then
            num, den = num + w * p.have / p.steps, den + w
        end
    end
    if den == 0 then return 100 end
    return math.floor(100 * num / den + 0.5)
end

-- LK20-T07 (D09) : Fortify.build découpé en étapes nommées, sans changement de comportement (mêmes listes, même ordre
-- des chantiers, des écarts notés et des appels aux sortes).

-- Chantiers des ouvertures (barricades et leurs réparations) par tier, triés ; ouvertures non barricadables notées
-- dans plan.skipped. L'entrée reste libre.
local function openingSites(survey, plan, entry, c)
    local h = survey.home
    local ground, upper, repGround, repUpper = {}, {}, {}, {}
    for _, e in ipairs(survey.openings or {}) do
        if e ~= entry and not e.allowed then   -- l'entrée reste libre
            plan.skipped[#plan.skipped + 1] = { x = e.x, y = e.y, z = e.z, north = e.north, why = "not barricadable" }
        elseif e ~= entry then
            local tier = e.z == 0 and "ground" or "upper"
            local site = barricadeSite(e, tier, c.PLANKS[tier])
            site.d = LivingKnox.Geo.cheb(e.inX, e.inY, h.x, h.y)
            if tier == "ground" then ground[#ground + 1] = site else upper[#upper + 1] = site end
            -- LK14-T06 : barricade complète dont la planche extérieure est abîmée (une barricade incomplète reçoit
            -- d'abord ses planches : la nouvelle devient la planche extérieure).
            if site.done and not e.metal and needsRepair(e.cond) then
                local rep = barricadeRepairSite(e, tier)
                rep.d = site.d
                if tier == "ground" then repGround[#repGround + 1] = rep else repUpper[#repUpper + 1] = rep end
            end
        end
    end
    table.sort(ground, openingOrder)
    table.sort(upper, openingOrder)
    table.sort(repGround, openingOrder)
    table.sort(repUpper, openingOrder)
    return ground, upper, repGround, repUpper
end

-- Segment du pourtour au milieu de la brèche : en face de l'entrée (camp ou bâtiment sans porte : en face du foyer,
-- sud d'abord), ou nil.
local function gapCenter(ring, plan, h)
    local tx, ty = h.x, h.y
    if plan.entry ~= nil then tx, ty = plan.entry.outside.x, plan.entry.outside.y end
    local gap0
    for _, e in ipairs(ring) do
        -- Distance du milieu du bord (face nord : (x + 1/2, y) ; ouest : (x, y + 1/2)) au centre de la case visée.
        local mx, my = e.x + 0.5, e.y
        if not e.north then mx, my = e.x, e.y + 0.5 end
        local d = (mx - tx - 0.5) * (mx - tx - 0.5) + (my - ty - 0.5) * (my - ty - 0.5)
        local better = gap0 == nil or d < gap0.d or (d == gap0.d and GAP_SIDE_RANK[e.side] < GAP_SIDE_RANK[gap0.e.side])
            or (d == gap0.d and e.side == gap0.e.side and e.pos < gap0.e.pos)
        if better then gap0 = { e = e, d = d } end
    end
    return gap0
end

local function ringOrder(a, b)
    if SIDE_RANK[a.side] ~= SIDE_RANK[b.side] then return SIDE_RANK[a.side] < SIDE_RANK[b.side] end
    return a.pos < b.pos
end

-- Chantiers du pourtour et réparations de ses ouvrages, triés ; brèche dans plan.gaps, segments écartés dans
-- plan.skipped.
local function ringSites(survey, plan, c)
    local ring = survey.ring or {}
    local gap0 = gapCenter(ring, plan, survey.home)
    local outer, repOuter = {}, {}
    for _, e in ipairs(ring) do
        if gap0 ~= nil and e.side == gap0.e.side and math.abs(e.pos - gap0.e.pos) <= c.GAP and e.built == nil then
            plan.gaps[#plan.gaps + 1] = { x = e.x, y = e.y, z = e.z, north = e.north }
        elseif e.blocked ~= nil then
            plan.skipped[#plan.skipped + 1] = { x = e.x, y = e.y, z = e.z, north = e.north, why = e.blocked }
        else
            outer[#outer + 1] = ringSite(e, survey.ringKind)
            if e.built ~= nil and e.health ~= nil and needsRepair(e.health) then   -- LK14-T06
                repOuter[#repOuter + 1] = ringRepairSite(e)
            end
        end
    end
    table.sort(outer, ringOrder)
    table.sort(repOuter, ringOrder)
    return outer, repOuter
end

-- LK16-T02 : chantiers relevés par les sortes elles-mêmes (spec.plan), dans l'ordre du registre, après le pourtour.
local function kindSites(survey, urgent)
    local extra = {}
    for _, spec in ipairs(Fortify.kinds.list) do
        if spec.plan ~= nil then
            for _, s in ipairs(spec.plan(survey, { urgent = urgent }) or {}) do extra[#extra + 1] = s end
        end
    end
    return extra
end

-- LK14-T06 : ordre des listes. Après une attaque : réparations (rez-de-chaussée, étages, pourtour), puis barricades
-- entamées (planche retirée ou chantier en cours), puis le reste ; sinon le plan de LK14-T02, réparations en dernier.
local function orderedLists(urgent, ground, upper, outer, extra, repairs)
    if urgent then
        local started, rest = {}, {}
        for _, list in ipairs({ ground, upper }) do
            for _, s in ipairs(list) do
                if not s.done and s.have > 0 then started[#started + 1] = s else rest[#rest + 1] = s end
            end
        end
        return { repairs, started, rest, outer, extra }
    end
    return { ground, upper, outer, extra, repairs }
end

-- Chantiers des listes mis dans plan.sites (rang 1..n), puis nombre de réparations, niveau, chantiers restants et
-- clé du plan.
local function finishPlan(plan, lists, urgent, repairs)
    for _, list in ipairs(lists) do
        for _, s in ipairs(list) do
            s.d = nil
            plan.sites[#plan.sites + 1] = s
            s.rank = #plan.sites
        end
    end
    plan.repairs = repairs
    plan.level = Fortify.levelOfSites(plan.sites)
    local todo, ids = 0, {}
    for _, s in ipairs(plan.sites) do
        if not s.done then todo = todo + 1 end
        ids[#ids + 1] = s.id .. "=" .. s.have
    end
    plan.todo = todo
    plan.key = (urgent and "urgent;" or "") .. table.concat(ids, ";")
end

-- Plan d'un relevé (pur) : { gid, style, home, entry, sites (ordre de priorité, rank 1..n), gaps, skipped, bounds,
-- level, todo (chantiers restants), key (texte stable du plan), urgent, repairs (LK14-T06) }. opts.urgent (après
-- une attaque) : réparations puis barricades entamées en tête ; sinon réparations en dernier.
function Fortify.build(survey, opts)
    local c = P.cfg()
    local urgent = opts ~= nil and opts.urgent == true
    local plan = { gid = survey.gid, style = survey.style, home = survey.home, bounds = survey.bounds, sites = {},
        gaps = {}, skipped = {}, outerSkipped = survey.outerSkipped, urgent = urgent }
    local entry = Fortify.entryOf(survey)
    if entry ~= nil then
        plan.entry = { x = entry.x, y = entry.y, z = entry.z, north = entry.north,
            outside = { x = entry.outX, y = entry.outY } }
    end
    local ground, upper, repGround, repUpper = openingSites(survey, plan, entry, c)
    local outer, repOuter = ringSites(survey, plan, c)
    local extra = kindSites(survey, urgent)
    local repairs = {}
    for _, list in ipairs({ repGround, repUpper, repOuter }) do
        for _, s in ipairs(list) do repairs[#repairs + 1] = s end
    end
    finishPlan(plan, orderedLists(urgent, ground, upper, outer, extra, repairs), urgent, #repairs)
    return plan
end

-- LK20-T07 : fonctions privées partagées avec les autres fichiers de Fortify/ (table Fortify._).
P.needsRepair = needsRepair
