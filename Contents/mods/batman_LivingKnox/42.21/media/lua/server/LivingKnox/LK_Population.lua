-- Living Knox : population initiale de 3 à 5 groupes, une seule fois par monde (LK08-T05) ; relève (LK09-T04). Fiche :
-- docs/annexes/conception/groupes.md, section « Population ».
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Condition : registre des groupes prêt, jamais peuplé (populated ~= true) et dans lequel aucun groupe n'a jamais
-- été créé (nextId == 1 : les numéros ne reculent jamais). Un registre d'une version antérieure qui contient ou a
-- contenu des groupes n'est donc jamais repeuplé, et la population ne se refait pas après un redémarrage.
-- Moment (LK_Server.lua) : OnServerStarted (serveur) ou OnGameStart (solo), après OnInitGlobalModData (relecture du
-- registre), la métagrille et la liste des refuges ; sinon au premier EveryHours qui suit le démarrage (registre
-- relu paresseusement, moteur activé en cours de partie). Jamais ailleurs : aucun autre code ne crée de groupe, sauf
-- la relève d'un groupe disparu (LK09-T04, fin de ce fichier), qui suit le même chemin (planGroup, Sites.pick, insert).
--
-- Pour chacun des N groupes (option GroupCount) : type tiré selon les poids des options (types enregistrés, ordre
-- trié), taille tirée dans l'intersection des bornes des options et de size du type, membres tirés (rôle selon le
-- poids des rôles du type parmi ceux qui ont encore un profil disponible, puis profil selon son poids et son max,
-- sexe imposé par le profil ou tiré, traits tirés à leur chance), chef désigné par la règle de succession
-- (Groups.pickSuccessor), histoire Stories.compose(type, storySeed) (sexe du chef = celui de l'histoire ; profil
-- au sexe imposé : graine retirée jusqu'à STORY_TRIES fois), foyer Sites.pick (foyers déjà choisis évités ; échec :
-- groupe sans foyer, journalisé). Tout est préparé avant d'écrire, puis inséré en une seule sauvegarde.
-- Registre : name = nom du chef de l'histoire, story = résumé anglais (summary.en, 600 au plus), storySeed = graine
-- qui recompose toute l'histoire (secrets compris) côté autorité ; les secrets ne sont jamais stockés.
-- Tirages reproductibles : Park-Miller (aucun opérateur binaire, quotients sous 2^31 en Kahlua) sur une graine
-- dérivée du mode et du nom de la partie (LK_Store.worldKey) : même partie, mêmes options et même métagrille ->
-- même population.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Stories"
require "LivingKnox/LK_Sites"

local Population = LivingKnox.Population or {}
LivingKnox.Population = Population

Population.STORY_TRIES = 8
Population.state = Population.state or { started = false, done = false }

local M = 2147483647

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Config() return LivingKnox.Config end

-- Tirages ------------------------------------------------------------------------------------------------------------

local function hashText(s, h)
    for i = 1, #s do
        h = (h * 31 + string.byte(s, i)) % M
    end
    return h
end

-- Graine de la partie : hachage du mode et du nom de la partie ("" sans monde).
function Population.baseSeed()
    local key = ""
    if getWorld and getWorld() then key = LivingKnox.Store.worldKey() end
    return hashText("population/" .. key, 17)
end

-- Flux reproductible : draw(n) -> entier de 1 à n.
function Population.stream(seed)
    local x = ((math.floor(math.abs(seed)) % M) * 7919 + 104729) % M
    if x == 0 then x = 1 end
    local function draw(n)
        x = (x * 48271) % M
        x = (x + (x % 65521) * 31337) % M
        if x == 0 then x = 1 end
        return 1 + math.floor(x / M * n)
    end
    for _ = 1, 4 do draw(2) end
    return draw
end

-- Élément de items tiré selon weightOf(item) (entiers >= 0), ou nil si le total est nul.
local function weighted(items, weightOf, draw)
    local total = 0
    for _, item in ipairs(items) do total = total + weightOf(item) end
    if total <= 0 then return nil end
    local r = draw(total)
    for _, item in ipairs(items) do
        r = r - weightOf(item)
        if r <= 0 then return item end
    end
    return items[#items]
end

-- Réglages -----------------------------------------------------------------------------------------------------------

-- Types tirables : { { id, weight } } triés par identifiant, poids > 0, types enregistrés seulement. Tous les poids
-- des options à 0 : poids par défaut (avertissement). Rend la liste (éventuellement vide).
function Population.typeWeights(settings)
    local weights, total = settings.weights or {}, 0
    for _, w in pairs(weights) do total = total + w end
    if total <= 0 then
        log().warn("population: every group type weight is 0, default weights used")
        weights = {}
        for groupType, option in pairs(Config().TYPE_WEIGHT_OPTIONS) do weights[groupType] = Config().DEFAULTS[option] end
    end
    local out, known = {}, {}
    for _, id in ipairs(LivingKnox.GroupTypes.ids()) do
        known[id] = true
        local w = weights[id] or 0
        if w > 0 then out[#out + 1] = { id = id, weight = w } end
    end
    local missing = {}
    for id, w in pairs(weights) do
        if w > 0 and not known[id] then missing[#missing + 1] = id end
    end
    table.sort(missing)
    for _, id in ipairs(missing) do
        log().warn("population: group type %s has a weight but is not registered: never drawn", id)
    end
    return out
end

-- Bornes de taille d'un groupe : intersection de [sizeMin, sizeMax] (options) et de size du type. Intersection
-- vide : la borne du type la plus proche des options (taille fixe), avertissement. Rend lo, hi.
function Population.sizeRange(def, settings)
    local lo = math.max(settings.sizeMin, def.size.min)
    local hi = math.min(settings.sizeMax, def.size.max)
    if lo <= hi then return lo, hi end
    local n = def.size.min
    if settings.sizeMin > def.size.max then n = def.size.max end
    log().warn("population: group size options %d..%d outside the size %d..%d of type %s, %d member(s)",
        settings.sizeMin, settings.sizeMax, def.size.min, def.size.max, def.id, n)
    return n, n
end

-- Membres d'un groupe de type def : liste de { role, profile, female, traits, forced } (forced = sexe imposé par le
-- profil). Rôles parcourus dans l'ordre de Config.GROUP_ROLES (tirage indépendant de l'ordre de pairs).
function Population.drawMembers(def, size, draw)
    local used, members = {}, {}
    local function available(p) return p.max == nil or (used[p.id] or 0) < p.max end
    for _ = 1, size do
        local roles = {}
        for _, role in ipairs(Config().GROUP_ROLES) do
            if def.roles[role] then
                for _, p in ipairs(def.profiles) do
                    if p.role == role and available(p) then
                        roles[#roles + 1] = role
                        break
                    end
                end
            end
        end
        local role = weighted(roles, function(r) return def.roles[r].weight end, draw)
        if role == nil then break end
        local candidates = {}
        for _, p in ipairs(def.profiles) do
            if p.role == role and available(p) then candidates[#candidates + 1] = p end
        end
        local p = weighted(candidates, function(c) return c.weight end, draw)
        used[p.id] = (used[p.id] or 0) + 1
        local female = p.female
        local forced = female ~= nil
        if female == nil then female = draw(2) == 2 end
        local traits = nil
        for _, t in ipairs(p.traits or {}) do
            if draw(100) <= t.chance then
                traits = traits or {}
                traits[#traits + 1] = t.id
            end
        end
        members[#members + 1] = { role = role, profile = p.id, female = female, traits = traits, forced = forced }
    end
    return members
end

-- Plan d'un groupe (logique pure, sans foyer) : { type, name, story, storySeed, needs, morale, members, leader
-- (indice du chef dans members, ou nil), siteSeed }.
function Population.planGroup(def, settings, draw, index)
    local lo, hi = Population.sizeRange(def, settings)
    local size = lo + draw(hi - lo + 1) - 1
    local members = Population.drawMembers(def, size, draw)
    local tmp = {}
    for k, m in ipairs(members) do
        local mid = Groups().MEMBER_PREFIX .. tostring(k)
        tmp[mid] = { id = mid, role = m.role, alive = true }
    end
    local leaderId = Groups().pickSuccessor({ members = tmp })
    local leader = leaderId and Groups().memberNumber(leaderId) or nil
    local story, storySeed
    for _ = 1, Population.STORY_TRIES do
        storySeed = draw(M - 1)
        story = LivingKnox.Stories.compose(def.id, storySeed)
        if story == nil or leader == nil or not members[leader].forced
            or members[leader].female == story.leader.female then
            break
        end
    end
    local name, summary = "Group " .. tostring(index), ""
    if story then
        name, summary = story.leader.name, story.summary.en
        if leader then
            local m = members[leader]
            if m.forced and m.female ~= story.leader.female then
                log().warn("population: no story of type %s matches the leader profile %s", def.id, m.profile)
            else
                m.female = story.leader.female
            end
        end
    else
        storySeed = nil
        log().error("population: no story for type %s, group kept without story", def.id)
    end
    return { type = def.id, name = name, story = summary, storySeed = storySeed, needs = def.needs,
        morale = def.morale, members = members, leader = leader, siteSeed = draw(M - 1) }
end

-- Plan de la population (logique pure, sans foyer) : liste de plans de groupes, ou nil et une raison.
function Population.plan(settings, seed)
    local types = Population.typeWeights(settings)
    if #types == 0 then return nil, "no group type can be drawn" end
    local draw = Population.stream(seed)
    local plans = {}
    for i = 1, settings.count do
        local t = weighted(types, function(x) return x.weight end, draw)
        local def = LivingKnox.GroupTypes.get(t.id)
        local sub = Population.stream((seed % M) * 31 + i * 7919)
        plans[#plans + 1] = Population.planGroup(def, settings, sub, i)
    end
    return plans
end

-- Foyers : Sites.pick pour chaque plan, en évitant les foyers déjà choisis. Échec : plan sans foyer, journalisé.
function Population.placeHomes(plans)
    local homes, taken = {}, {}
    for i, p in ipairs(plans) do
        local site, why = LivingKnox.Sites.pick(p.type, { seed = p.siteSeed, homes = homes, exclude = taken })
        if site then
            p.home = { x = math.floor(site.x), y = math.floor(site.y), z = math.floor(site.z or 0) }
            p.site = site.key
            homes[#homes + 1] = { x = p.home.x, y = p.home.y, source = "population" }
            if site.key then taken[site.key] = true end
        else
            log().warn("population: group %d (%s) has no home: %s", i, p.type, tostring(why))
        end
    end
end

-- Exécution ----------------------------------------------------------------------------------------------------------

local function eligible(data)
    return data.populated ~= true and data.nextId == 1
end

-- Insère un plan de groupe (foyer compris) dans le registre passé en argument (logique pure, sans sauvegarde ;
-- partagée par la population initiale et la relève) : groupe, membres, chef. Rend le groupe vivant, ou nil et la raison.
function Population.insert(data, p, day)
    local G = Groups()
    local g, why = G.applyCreate(data, { type = p.type, name = p.name, story = p.story, storySeed = p.storySeed,
        home = p.home, needs = p.needs, morale = p.morale, day = day })
    if not g then return nil, why end
    local mids = {}
    for k, m in ipairs(p.members) do
        mids[k] = G.applyMember(g, { role = m.role, profile = m.profile, female = m.female, traits = m.traits }, day)
    end
    if p.leader and mids[p.leader] then G.applyLeader(g, mids[p.leader], day) end
    return g
end

-- Population initiale si le registre n'a jamais été peuplé. opts.seed : graine (défaut : baseSeed). Rend la liste des
-- identifiants créés (vide si rien à faire), ou nil et une raison.
function Population.run(opts)
    opts = opts or {}
    local G = Groups()
    if not G.ensure() then return nil, "group registry not ready" end
    if not eligible(G.state.data) then
        log().info("population: group registry already populated, nothing created")
        return {}
    end
    local settings = Config().population()
    local seed = opts.seed or Population.baseSeed()
    local plans, why = Population.plan(settings, seed)
    if not plans then
        log().error("population: %s; no group created", why)
        return nil, why
    end
    Population.placeHomes(plans)
    local result, err = G.update(function(data)
        if not eligible(data) then return false, {} end
        local day, ids = G.today(), {}
        for _, p in ipairs(plans) do
            local g, gwhy = Population.insert(data, p, day)
            if g then
                ids[#ids + 1] = g.id
                log().info("population: %s %s, %d member(s), leader %s, home %s", g.id, p.type, #p.members,
                    tostring(g.leader), p.home and (p.home.x .. "," .. p.home.y .. "," .. p.home.z) or "none")
            else
                log().error("population: group of type %s not created: %s", p.type, tostring(gwhy))
            end
        end
        data.populated = true
        return true, ids
    end)
    if not result then
        log().error("population: %s", tostring(err))
        return nil, err
    end
    log().info("population: %d group(s) created (requested %d, seed %s)", #result, settings.count, tostring(seed))
    return result
end

-- Tentative du démarrage ou d'une heure de jeu : une seule par session une fois le registre prêt. Moteur désactivé :
-- rien, nouvelle tentative à l'heure suivante.
function Population.ensure()
    local st = Population.state
    if st.done or not Config().isEnabled() then return nil end
    st.done = true
    if Groups().isBlocked() then return nil end
    return Population.run()
end

-- Nouvelle partie chargée (OnInitGlobalModData, avec la relecture du registre) : nouvelle tentative permise.
function Population.reset()
    Population.state.started, Population.state.done = false, false
end

-- Démarrage (OnServerStarted / OnGameStart) : registre relu à OnInitGlobalModData, sinon attente du premier
-- EveryHours (relecture paresseuse).
function Population.onStart()
    Population.state.started = true
    if not Groups().isReady() then return nil end
    return Population.ensure()
end

-- Heure de jeu : population initiale (une fois), puis décimation et relève (LK09-T04).
function Population.onEveryHours()
    if not Population.state.started then return nil end
    local result = Population.ensure()
    Population.reliefStep()
    return result
end

-- Décimation et relève (LK09-T04) ------------------------------------------------------------------------------------
-- Fiche : docs/annexes/conception/groupes.md, section « Décimation et relève ».
-- Constat à chaque heure de jeu (Population.onEveryHours), groupes dans l'ordre de leur numéro, une seule sauvegarde :
--   - plus aucun membre vivant, dans un groupe qui en a eu (nextMember > 1) -> disparu, cause "wiped" ;
--   - dispersion : au plus RELIEF.DISPERSE_AT vivant(s) dans un groupe qui en a compté davantage, hors écran (aucun
--     membre incarné, aucune expédition en cours) -> le ou les survivants partent (applyLeave, raison "dispersed"),
--     puis disparu, cause "dispersed".
-- Disparu = marque gone (LK_Groups) : le groupe reste au registre, son foyer reste un foyer connu (Sites l'évite),
-- aménagement et stock restent en place (traces), rien n'est repris ni nettoyé.
-- Délai : jours tirés dans [ReliefDaysMin, ReliefDaysMax] (options), graine (partie, groupe) : heure de relève due =
-- heure du constat + jours x 24, écrite dans la marque (survit au redémarrage).
-- Relève : à la première heure >= due, un groupe neuf est planifié par le chemin de la population (type selon les
-- poids, planGroup, Sites.pick) ; le site évite tous les foyers du registre, l'ancien compris (GROUP_DISTANCE). Une
-- seule relève : gone.relief = identifiant du nouveau groupe, posé dans la même sauvegarde que sa création. Aucun site
-- ou registre plein : nouvel essai RELIEF.RETRY_HOURS plus tard (due repoussé, nouvelle graine).
Population.RELIEF = {
    DISPERSE_AT = 1,     -- dispersion : au plus ce nombre de vivants (0 : jamais de dispersion)
    RETRY_HOURS = 24,    -- relève impossible : nouvel essai un jour de jeu plus tard
}

local function byNumber(a, b)
    return (Groups().idNumber(a) or 0) < (Groups().idNumber(b) or 0)
end

local function sortedGroups(data)
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids, byNumber)
    return ids
end

-- Graine de la relève : hachage du mode et du nom de la partie.
function Population.reliefSeed()
    local key = ""
    if getWorld and getWorld() then key = LivingKnox.Store.worldKey() end
    return hashText("relief/" .. key, 23)
end

-- Heure de jeu courante (entier, âge du monde), ou nil si l'horloge manque.
function Population.currentHour()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= "number" or hours ~= hours or hours < 0 then return nil end
    return math.floor(hours)
end

-- Délai de relève d'un groupe en heures : jours tirés dans [reliefMin, reliefMax] (reproductible par groupe).
function Population.reliefDelay(settings, gid)
    local n = Groups().idNumber(gid) or 0
    local draw = Population.stream((Population.reliefSeed() % M) * 31 + n * 7919)
    local days = settings.reliefMin + draw(settings.reliefMax - settings.reliefMin + 1) - 1
    return days * 24
end

-- Membre incarné (corps présent, LK09-T03) : même règle que la simulation ; registre des corps absent : non.
local function embodied(m)
    local S = LivingKnox.Simulation
    if S ~= nil and S.isEmbodied ~= nil then return S.isEmbodied(m) end
    return false
end

-- Constat des groupes disparus sur un registre passé en argument (logique pure, sans sauvegarde). Rend la liste des
-- identifiants marqués à l'heure now.
function Population.markGone(data, now, settings)
    local G, R = Groups(), Population.RELIEF
    local day = math.floor(now / 24) + 1
    local out = {}
    for _, gid in ipairs(sortedGroups(data)) do
        local g = data.groups[gid]
        if g.gone == nil and g.nextMember > 1 then
            local living, inBody = {}, false
            for mid, m in pairs(g.members) do
                if m.alive then
                    living[#living + 1] = mid
                    if embodied(m) then inBody = true end
                end
            end
            table.sort(living, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
            local cause
            if #living == 0 then
                cause = "wiped"
            elseif #living <= R.DISPERSE_AT and g.nextMember - 1 > R.DISPERSE_AT and g.expedition == nil
                and not inBody then
                for _, mid in ipairs(living) do G.applyLeave(g, mid, day, "dispersed") end
                cause = "dispersed"
            end
            if cause then
                G.applyGone(g, cause, day, now, now + Population.reliefDelay(settings, gid))
                out[#out + 1] = gid
            end
        end
    end
    return out
end

-- Groupes disparus dont la relève est due à l'heure now (sans relève), triés par numéro. E10-T04 : un groupe d'un
-- type que la population ne tire jamais (aucune option de poids, LK_Config.TYPE_WEIGHT_OPTIONS : solitaire parti de
-- son groupe) n'appelle aucune relève ; il reste marqué disparu.
function Population.dueReliefs(data, now)
    local out = {}
    local drawn = Config().TYPE_WEIGHT_OPTIONS
    for _, gid in ipairs(sortedGroups(data)) do
        local gone = data.groups[gid].gone
        if gone ~= nil and gone.relief == nil and now >= gone.due and drawn[data.groups[gid].type] ~= nil then
            out[#out + 1] = gid
        end
    end
    return out
end

-- Distance entre deux points { x, y } (nil si l'un manque).
local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Plan d'un groupe de relève pour le groupe disparu old (copie ou vivant, lecture seule), avec son foyer : type selon
-- les poids, planGroup, Sites.pick (tous les foyers du registre évités, l'ancien compris). index = numéro prévu (nom
-- de secours). Rend le plan, ou nil et la raison.
function Population.planRelief(old, settings, index)
    local types = Population.typeWeights(settings)
    if #types == 0 then return nil, "no group type can be drawn" end
    local seed = ((Population.reliefSeed() % M) * 31 + (Groups().idNumber(old.id) or 0) * 7919
        + (old.gone.due % 100000)) % M
    local draw = Population.stream(seed)
    local t = weighted(types, function(x) return x.weight end, draw)
    local def = LivingKnox.GroupTypes.get(t.id)
    local p = Population.planGroup(def, settings, Population.stream(seed * 3 + 1), index)
    local site, why = LivingKnox.Sites.pick(p.type, { seed = p.siteSeed })
    if not site then return nil, "no site: " .. tostring(why) end
    p.home = { x = math.floor(site.x), y = math.floor(site.y), z = math.floor(site.z or 0) }
    p.site = site.key
    local d = distance(p.home, old.home)
    if d ~= nil and d < LivingKnox.Sites.CONFIG.GROUP_DISTANCE then
        return nil, "site " .. tostring(site.key) .. " too close to the old home (" .. math.floor(d) .. ")"
    end
    p.distance = d
    return p
end

-- Pas de la relève à l'heure now (défaut : heure courante) : constat (une sauvegarde si un groupe est marqué), puis
-- relèves dues (une sauvegarde chacune). Rend la liste des groupes créés, ou nil et une raison. Moteur désactivé :
-- rien (le constat et les relèves attendent la réactivation).
function Population.reliefStep(now)
    if not Config().isEnabled() then return nil, "disabled" end
    local G = Groups()
    if not G.ensure() then return nil, "group registry not ready" end
    now = now or Population.currentHour()
    if now == nil then return nil, "no game clock" end
    local settings = Config().population()
    G.update(function(data)
        local marked = Population.markGone(data, now, settings)
        return #marked > 0, marked
    end)
    local due = G.update(function(data) return false, Population.dueReliefs(data, now) end)
    local created = {}
    if type(due) ~= "table" then return created end
    local R = Population.RELIEF
    for _, gid in ipairs(due) do
        local old = G.get(gid)
        local plan, why = Population.planRelief(old, settings, G.state.data.nextId)
        local newId = G.update(function(data)
            local o = data.groups[gid]
            if o == nil or o.gone == nil or o.gone.relief ~= nil or now < o.gone.due then return false, false end
            local day = math.floor(now / 24) + 1
            local g
            if plan then g, why = Population.insert(data, plan, day) end
            if not g then
                o.gone.due = now + R.RETRY_HOURS
                log().warn("relief: no relief for %s (%s), next try at hour %s", gid, tostring(why), tostring(o.gone.due))
                return true, false
            end
            o.gone.relief = g.id
            G.appendLog(o, "relieved", g.id, day)
            G.appendLog(g, "relief", gid, day)
            log().info("relief: %s %s, %d member(s), leader %s, home %d,%d,%d (%s), replaces %s, %s squares from"
                .. " its home", g.id, plan.type, #plan.members, tostring(g.leader), plan.home.x, plan.home.y,
                plan.home.z, tostring(plan.site), gid, plan.distance and tostring(math.floor(plan.distance)) or "?")
            return true, g.id
        end)
        if type(newId) == "string" then created[#created + 1] = newId end
    end
    return created
end

return Population
