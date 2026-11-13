-- Living Knox : routine « corvées visibles » des PNJ au foyer (LK05-T04, découpée en LK15-T02, ADR D05) : petite activité
-- tirée dans la liste fermée Routines.CHORES selon le poste, les comportements du rôle et les traits du membre (I3.4),
-- parmi celles qui ont une place au foyer ; emplacements relevés en mémoire (non sauvegardés). Fiche :
-- docs/annexes/conception/routines.md. Activité du comportement « chore » (ordre 90, après les barricades (10) et
-- l'entretien (20)). Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_RoutineExec"

local Routines = LivingKnox.Routines
local E = Routines.exec
local buildingId, placeBeside = E.buildingId, E.placeBeside
local cheb, byPlace, rankOf = Routines.cheb, Routines.byPlace, Routines.rankOf

local function log() return LivingKnox.Log end
local function cfg() return Routines.CFG end
local function Decisions() return LivingKnox.Decisions end
local function now() return getTimestampMs() end
local function leash() return Decisions().CFG.HOME_RADIUS end

-- Objet de corvée de la case : "fire" (IsoFireplace : cheminée, poêle à bois, brasero ; ou conteneur de type
-- « stove »), "furniture" (autre objet à conteneur, hors NOT_FURNITURE), ou nil ; et son rang (cheminée 1, cuisinière
-- 2, meuble 3). Lecture seule : aucun conteneur ouvert ni modifié.
function Routines.choreObject(sq)
    local objs = sq ~= nil and sq:getObjects() or nil
    if objs == nil then return nil end
    local best, rank
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local k, r
        if instanceof(o, "IsoFireplace") then
            k, r = "fire", 1
        elseif o ~= nil and not instanceof(o, "IsoWorldInventoryObject") then
            local c = o:getContainer()
            local t = c ~= nil and c:getType() or nil
            if t == "stove" then
                k, r = "fire", 2
            elseif t ~= nil and not cfg().NOT_FURNITURE[t] then
                k, r = "furniture", 3
            end
        end
        if k ~= nil and (rank == nil or r < rank) then best, rank = k, r end
    end
    return best, rank
end

-- Relevé des places de corvée du foyer home (zone chargée, même bâtiment, niveau du foyer) : { fire = { place... },
-- furniture = { place... } }, cheminées d'abord, puis distance au foyer et position. Camp : listes vides. nil et une
-- raison si la zone du foyer n'est pas chargée.
function Routines.surveySpots(home)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local R = leash()
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    if hsq == nil then return nil, "home square not loaded" end
    for _, c in ipairs({ { -R, -R }, { R, -R }, { R, R }, { -R, R } }) do
        if cell:getGridSquare(home.x + c[1], home.y + c[2], home.z) == nil then return nil, "home area not loaded" end
    end
    local out = { fire = {}, furniture = {} }
    local bid = buildingId(hsq)
    if bid == nil then return out end
    local found = {}
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, home.z)
            if sq ~= nil and buildingId(sq) == bid then
                local kind, rank = Routines.choreObject(sq)
                if kind ~= nil then
                    found[#found + 1] = { x = x, y = y, kind = kind, rank = rank, d = cheb(x, y, home.x, home.y) }
                end
            end
        end
    end
    table.sort(found, byPlace)
    local max = { fire = cfg().MAX_FIRES, furniture = cfg().MAX_FURNITURE }
    local used = {}
    for _, f in ipairs(found) do
        local list = out[f.kind]
        if #list < max[f.kind] then
            local p = placeBeside(cell, f.x, f.y, home.z, bid, used)
            if p ~= nil then list[#list + 1] = p end
        end
    end
    return out
end

-- Places de corvée du foyer du groupe gid (mémoire, refaites si le foyer change ; zone non chargée : nouvel essai au
-- plus toutes les RETRY_MS). Rend la table de surveySpots, ou nil.
function Routines.ensureSpots(gid, home)
    if type(home) ~= "table" then return nil end
    local key = home.x .. "," .. home.y .. "," .. home.z
    local st = Routines.state
    st.spots = st.spots or {}
    local s = st.spots[gid]
    if s ~= nil and s.key == key then
        if s.data ~= nil then return s.data end
        if now() - s.t < cfg().RETRY_MS then return nil end
    end
    local data, why = Routines.surveySpots(home)
    st.spots[gid] = { key = key, data = data, t = now() }
    if data == nil then
        log().debug("group %s: chore places postponed: %s", gid, tostring(why))
        return nil
    end
    Routines.stats.spotSurveys = Routines.stats.spotSurveys + 1
    log().info("group %s home %s chore places: %d fire(s), %d furniture", gid, key, #data.fire, #data.furniture)
    return data
end

-- Créneau de corvée du PNJ id à la minute de jeu minute : CHORE_MINUTES minutes, décalé de 0 à CHORE_MINUTES - 1
-- minutes selon l'identité (deux membres ne changent pas de corvée à la même minute).
function Routines.choreSlot(id, minute)
    local span = cfg().CHORE_MINUTES
    local off = math.floor(Decisions().stream("chore/" .. tostring(id), 0, 3)() * span)
    return math.floor((math.floor(minute) + off) / span)
end

-- Poids des corvées (pur) : poste duty (CHORE_DUTY, "routine" par défaut), comportements du rôle allowed
-- ({ [nom] = vrai }), traits ({ [nom] = vrai }), corvées possibles avail ({ [corvée] = vrai }). Rend { [corvée] = n }.
function Routines.choreWeights(duty, allowed, traits, avail)
    local c = cfg()
    local base = c.CHORE_DUTY[duty] or c.CHORE_DUTY.routine
    local out = {}
    for _, ch in ipairs(Routines.CHORES) do out[ch] = base[ch] or 0 end
    local function bonus(tbl, set)
        local names = {}
        for n in pairs(set or {}) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            local b = tbl[n]
            if b ~= nil then
                for _, ch in ipairs(Routines.CHORES) do out[ch] = out[ch] + (b[ch] or 0) end
            end
        end
    end
    bonus(c.CHORE_ROLE, allowed)
    bonus(c.CHORE_TRAIT, traits)
    for _, ch in ipairs(Routines.CHORES) do
        if not (avail or {})[ch] then out[ch] = 0 end
    end
    return out
end

-- Corvée tirée (pur, déterministe) : graine = identité id + créneau slot ; tirage pondéré dans l'ordre de CHORES.
-- Aucun poids : "rest".
function Routines.pickChore(id, slot, weights)
    local total = 0
    for _, ch in ipairs(Routines.CHORES) do total = total + (weights[ch] or 0) end
    if total <= 0 then return "rest" end
    local r = math.floor(Decisions().stream("chore/" .. tostring(id), slot, 11)() * total)
    for _, ch in ipairs(Routines.CHORES) do
        r = r - (weights[ch] or 0)
        if r < 0 then return ch end
    end
    return "rest"
end

-- Membre présent le plus blessé (santé sous CARE_HEALTH, corps incarné au foyer), autre que mid : mid, corps ; ou nil.
function Routines.woundedFor(g, mid, home)
    local B = LivingKnox.Bodies
    if B == nil or B.find == nil then return nil end
    local best, bestH, bestBody
    for _, other in ipairs(Routines.present(g)) do
        local m = g.members[other]
        if other ~= mid and m.npc ~= nil then
            local h = Decisions().healthOf(m)
            if h < cfg().CARE_HEALTH and (bestH == nil or h < bestH) then
                local z = B.find(m.npc)
                if z ~= nil and (home == nil or (math.floor(z:getZ()) == home.z
                    and cheb(z:getX(), z:getY(), home.x + 0.5, home.y + 0.5) <= leash())) then
                    best, bestH, bestBody = other, h, z
                end
            end
        end
    end
    return best, bestBody
end

local function windowsFree(posts, g, hour)
    local out = {}
    if type(posts) ~= "table" or type(posts.posts) ~= "table" then return out end
    local taken = {}
    for _, s in ipairs(Routines.sentries(g)) do
        local p = Routines.postFor(posts, g, s, hour)
        if p ~= nil then taken[p.x .. "," .. p.y] = true end
    end
    for _, p in ipairs(posts.posts) do
        if p.k == "window" and not taken[p.x .. "," .. p.y] then out[#out + 1] = p end
    end
    return out
end

-- Plan de corvée du membre (contexte ctx du cadre de décision, groupe g du registre, relevé posts) : { kind, key,
-- chore, x, y, z, a, gesture }. kind "spot" (aller, regarder, geste) ou "sit" (rester ou rentrer, s'arrêter, geste).
function Routines.chorePlan(id, ctx, g, posts)
    local m = g.members[ctx.mid] or {}
    local hour = math.floor(ctx.minute / 60)
    local spots = Routines.ensureSpots(ctx.gid, g.home) or { fire = {}, furniture = {} }
    local windows = windowsFree(posts, g, hour)
    local doors = type(posts) == "table" and type(posts.posts) == "table" and posts.posts or {}
    local wounded, wbody = Routines.woundedFor(g, ctx.mid, g.home)
    local avail = { fire = #spots.fire > 0, warm = #spots.fire > 0, tidy = #spots.furniture > 0,
        lookout = #windows > 0, repair = #doors > 0, smoke = true, care = wounded ~= nil, rest = true }
    local traits = {}
    for _, t in ipairs(type(m.traits) == "table" and m.traits or {}) do traits[t] = true end
    local duty = Routines.CFG.CHORE_DUTY[ctx.duty] ~= nil and ctx.duty or "routine"
    local slot = Routines.choreSlot(id, ctx.minute)
    local chore = Routines.pickChore(id, slot, Routines.choreWeights(duty, ctx.allowed, traits, avail))
    local rank = rankOf(Routines.present(g), ctx.mid) or 1
    local function nth(list) return list[((slot + rank - 1) % #list) + 1] end
    local gesture = Routines.CHORE_GESTURE[chore]
    local function spot(p, a)
        return { kind = "spot", chore = chore, key = string.format("chore %s %d,%d,%d", chore, p.x, p.y, p.z),
            x = p.x, y = p.y, z = p.z, a = a or p.a, gesture = gesture }
    end
    if chore == "fire" or chore == "warm" then return spot(nth(spots.fire)) end
    if chore == "tidy" then return spot(nth(spots.furniture)) end
    if chore == "lookout" then return spot(nth(windows)) end
    if chore == "repair" then
        -- Porte ou fenêtre du relevé : regard vers elle (direction du poste).
        return spot(nth(doors))
    end
    if chore == "smoke" and #windows > 0 then return spot(nth(windows)) end
    if chore == "care" then
        local cell = getCell()
        local wx, wy, wz = math.floor(wbody:getX()), math.floor(wbody:getY()), math.floor(wbody:getZ())
        local p = cell ~= nil and placeBeside(cell, wx, wy, wz, nil, {}) or nil
        if p ~= nil then
            local out = spot(p)
            out.key = string.format("chore care %s %d,%d,%d", wounded, p.x, p.y, p.z)
            return out
        end
        chore, gesture = "rest", Routines.CHORE_GESTURE.rest
    end
    return { kind = "sit", chore = chore, key = "chore " .. chore, gesture = gesture }
end

-- Activité « chore » (ADR D04, ordre 90) : corvée visible, après les barricades (10) et l'entretien (20).
Routines.registerActivity({ id = "chore.visible", behaviour = "chore", order = 90,
    run = function(id, st, ctx, g, fresh)
        local posts = Routines.ensurePosts(ctx.gid, g)
        local plan = Routines.chorePlan(id, ctx, g, posts)
        if plan == nil then return false end
        Routines.execPlan(id, st, ctx, plan, fresh)
        return true
    end })
