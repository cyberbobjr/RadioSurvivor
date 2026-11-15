-- Living Knox : routine « corvées visibles » des PNJ au foyer (LK05-T04, découpée en LK15-T02, ADR D05) : petite activité
-- tirée parmi les corvées inscrites (Routines.registerChore, LK16-T07 : une corvée par fichier dans
-- media/lua/server/LivingKnox/Chores/) selon le poste, les comportements du rôle et les traits du membre (I3.4), parmi
-- celles qui ont une place au foyer ; emplacements relevés en mémoire (non sauvegardés). Fiche :
-- docs/annexes/conception/routines.md. Activité du comportement « chore » (ordre 90, après les barricades (10) et
-- l'entretien (20)). Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_RoutineExec"
require "LivingKnox/LK_Passage"   -- LK18-T01 : priorité de passage déclarée plus bas

local Routines = LivingKnox.Routines
local E = Routines.exec
local buildingId, placeBeside = E.buildingId, E.placeBeside
local cheb, byPlace, rankOf = Routines.cheb, Routines.byPlace, Routines.rankOf

local function log() return LivingKnox.Log end
local function cfg() return Routines.CFG end
local function Decisions() return LivingKnox.Decisions end
local function now() return getTimestampMs() end
local function leash() return Decisions().CFG.HOME_RADIUS end

-- ================================================================ registre des corvées (LK16-T07, ADR D02)

-- Corvée : { id (unique), order (ordre du tirage : plus petit d'abord, à égalité par id), gesture (geste final, nil :
-- debout, regard seul), duty = { [poste] = poids } (« routine » : sans poste à corvées), role = { [comportement du
-- rôle] = bonus }, trait = { [trait] = bonus }, avail(c) -> vrai si la corvée a une place au foyer (absent : toujours),
-- plan(c) -> plan, ou nil pour rester ou rentrer et faire le geste sur place (c : voir Routines.chorePlan) }.
-- Vues tenues à l'inscription : Routines.CHORES (identifiants dans l'ordre du tirage), Routines.CHORE_GESTURE.
Routines.choreSpecs = Routines.choreSpecs or {}
Routines.CHORES = Routines.CHORES or {}
Routines.CHORE_GESTURE = Routines.CHORE_GESTURE or {}
Routines.CHORE_FALLBACK = "rest"          -- aucun poids, ou corvée impossible sur place : se reposer
Routines.CHORE_DEFAULT_DUTY = "routine"   -- poste sans poids de corvée

local function optional(v, kind) return v == nil or type(v) == kind end

local function validChore(spec)
    if type(spec) == "table" and type(spec.id) == "string" and type(spec.order) == "number"
        and optional(spec.gesture, "string") and optional(spec.duty, "table") and optional(spec.role, "table")
        and optional(spec.trait, "table") and optional(spec.avail, "function") and optional(spec.plan, "function") then
        return true
    end
    return false, "spec needs id and order; gesture string; duty, role, trait tables; avail, plan functions"
end

local chores = LivingKnox.Registry.new("LivingKnox.Routines.registerChore",
    { validate = validChore, items = Routines.choreSpecs })

local function refreshViews()
    local list, gestures = Routines.CHORES, Routines.CHORE_GESTURE
    for i = #list, 1, -1 do list[i] = nil end
    local old = {}
    for k in pairs(gestures) do old[#old + 1] = k end
    for _, k in ipairs(old) do gestures[k] = nil end
    for _, s in ipairs(chores:list()) do
        list[#list + 1] = s.id
        gestures[s.id] = s.gesture
        if s.gesture ~= nil then Routines.GESTURES[s.gesture] = true end
    end
end

-- Inscrit une corvée (spec, voir ci-dessus) ; même id : remplacée (rechargement). Spec refusée : erreur.
function Routines.registerChore(spec)
    local s = chores:register(spec, 2)
    refreshViews()
    return s
end

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

-- Poste duty s'il a un poids de corvée, sinon CHORE_DEFAULT_DUTY.
function Routines.choreDuty(duty)
    for _, s in ipairs(chores:list()) do
        if s.duty ~= nil and s.duty[duty] ~= nil then return duty end
    end
    return Routines.CHORE_DEFAULT_DUTY
end

local function sortedNames(set)
    local names = {}
    for n in pairs(set or {}) do names[#names + 1] = n end
    table.sort(names)
    return names
end

-- Poids des corvées (pur) : poste duty (Routines.choreDuty), comportements du rôle allowed ({ [nom] = vrai }), traits
-- ({ [nom] = vrai }), corvées possibles avail ({ [corvée] = vrai }). Rend { [corvée] = n } : poids du poste, puis
-- bonus des comportements puis des traits (noms triés).
function Routines.choreWeights(duty, allowed, traits, avail)
    local d = Routines.choreDuty(duty)
    local roles, traitNames = sortedNames(allowed), sortedNames(traits)
    local out = {}
    for _, s in ipairs(chores:list()) do
        local w = s.duty ~= nil and s.duty[d] or 0
        for _, n in ipairs(roles) do w = w + (s.role ~= nil and s.role[n] or 0) end
        for _, n in ipairs(traitNames) do w = w + (s.trait ~= nil and s.trait[n] or 0) end
        if not (avail or {})[s.id] then w = 0 end
        out[s.id] = w
    end
    return out
end

-- Corvée tirée (pur, déterministe) : graine = identité id + créneau slot ; tirage pondéré dans l'ordre de CHORES.
-- Aucun poids : CHORE_FALLBACK.
function Routines.pickChore(id, slot, weights)
    local total = 0
    for _, ch in ipairs(Routines.CHORES) do total = total + (weights[ch] or 0) end
    if total <= 0 then return Routines.CHORE_FALLBACK end
    local r = math.floor(Decisions().stream("chore/" .. tostring(id), slot, 11)() * total)
    for _, ch in ipairs(Routines.CHORES) do
        r = r - (weights[ch] or 0)
        if r < 0 then return ch end
    end
    return Routines.CHORE_FALLBACK
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

-- Contexte c d'une corvée (avail, plan) : { id, ctx, g, posts, hour, spots = { fire, furniture } (places relevées),
-- windows (fenêtres du relevé sans guetteur), doors (postes du relevé) } ; après le tirage : slot, rank, chore,
-- nth(list) (place de la liste pour ce créneau et ce membre), place(p, a, key) (plan « spot » : aller en p, regarder
-- a ou p.a, geste), sit(chore) (plan « sit » de la corvée, celle tirée par défaut). Une corvée peut y garder ce que
-- son avail a trouvé pour son plan (champ à son nom).
local function choreContext(id, ctx, g, posts)
    local hour = math.floor(ctx.minute / 60)
    return { id = id, ctx = ctx, g = g, posts = posts, hour = hour,
        spots = Routines.ensureSpots(ctx.gid, g.home) or { fire = {}, furniture = {} },
        windows = windowsFree(posts, g, hour),
        doors = type(posts) == "table" and type(posts.posts) == "table" and posts.posts or {} }
end

local function drawn(c, slot, rank, chore)
    c.slot, c.rank, c.chore = slot, rank, chore
    function c.nth(list) return list[((slot + rank - 1) % #list) + 1] end
    function c.place(p, a, key)
        return { kind = "spot", chore = chore, key = key or string.format("chore %s %d,%d,%d", chore, p.x, p.y, p.z),
            x = p.x, y = p.y, z = p.z, a = a or p.a, gesture = Routines.CHORE_GESTURE[chore] }
    end
    function c.sit(other)
        local ch = other or chore
        return { kind = "sit", chore = ch, key = "chore " .. ch, gesture = Routines.CHORE_GESTURE[ch] }
    end
    return c
end

-- Plan de corvée du membre (contexte ctx du cadre de décision, groupe g du registre, relevé posts) : { kind, key,
-- chore, x, y, z, a, gesture }. kind "spot" (aller, regarder, geste) ou "sit" (rester ou rentrer, s'arrêter, geste).
-- Corvées possibles (avail de chacune), tirage pondéré, puis plan de la corvée tirée (sans plan : « sit »).
function Routines.chorePlan(id, ctx, g, posts)
    local m = g.members[ctx.mid] or {}
    local c = choreContext(id, ctx, g, posts)
    local avail = {}
    for _, s in ipairs(chores:list()) do
        if s.avail == nil or s.avail(c) then avail[s.id] = true end
    end
    local traits = {}
    for _, t in ipairs(type(m.traits) == "table" and m.traits or {}) do traits[t] = true end
    local slot = Routines.choreSlot(id, ctx.minute)
    local chore = Routines.pickChore(id, slot, Routines.choreWeights(ctx.duty, ctx.allowed, traits, avail))
    drawn(c, slot, rankOf(Routines.present(g), ctx.mid) or 1, chore)
    local spec = chores:get(chore)
    local plan = spec ~= nil and spec.plan ~= nil and spec.plan(c) or nil
    return plan or c.sit()
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

-- LK18-T01 (ADR adr-ceder-le-passage.md D02, fiche passage.md) : priorité de passage du comportement, déclarée ici.
LivingKnox.Passage.priority("chore", 50)
