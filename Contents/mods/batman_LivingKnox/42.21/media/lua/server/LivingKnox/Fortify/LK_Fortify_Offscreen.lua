-- Living Knox : fortification du foyer, rattrapage hors écran (LK14-T05) : heure simulée
-- (Fortify.offscreenHour), niveau et chantiers faisables du relevé, relevé écrit d'après le plan
-- (Fortify.snapshot)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)


-- Groupe vivant du registre (lecture seule, sans copie), ou nil.
local function liveGroup(gid)
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil end
    local g = G.update(function(data) return false, data.groups[gid] end)
    if type(g) ~= "table" then return nil end
    return g
end

-- Vrai si le travail fait hors écran du groupe gid attend d'être posé (écarts de pose ou boîtes de clous entamées).
function Fortify.hasPending(gid)
    local g = liveGroup(gid)
    local f = g ~= nil and P.readView(gid, g.fort, g.home) or nil
    if f == nil then return false end
    return #f.pend.ops > 0 or #f.boxes > 0
end

-- Étape suivante d'un chantier du relevé e : besoins { types, n }, outil (ou nil), minutes de travail ; nil si fini.
-- LK16-T02 : étape de la sorte inscrite (spec.offscreen.nextStage).
local function nextStage(e)
    if e.h >= e.s then return nil end
    return Fortify.kinds.byId[e.k].offscreen.nextStage(e, P.cfg())
end

-- Matériaux de toutes les étapes restantes d'un chantier du relevé e (comme site.materials du plan : un chantier
-- n'est commencé que si tout ce qui lui reste tient dans le stock, Fortify.feasibleSites) : spec.offscreen.remaining.
local function remainingReqs(e)
    return Fortify.kinds.byId[e.k].offscreen.remaining(e)
end

local function boxUsed(f, id)
    for _, b in ipairs(f.boxes) do
        if b.i == id then return b end
    end
    return nil
end

-- Matériaux disponibles hors écran (pur) : { [type] = n } d'après la référence du stock (objets suivis et ajouts en
-- attente), types des sortes inscrites (Fortify.OFF_TYPES, LK16-T02) ; clous = clous libres + clous restants des
-- boîtes suivies (BOX_NAILS moins ceux déjà utilisés).
local function offAvail(g, f)
    local St = P.Stock()
    local s = g.stock
    local out = {}
    for _, t in ipairs(Fortify.OFF_TYPES) do out[t] = St.offscreenCount(s, { t }) end
    for _, e in ipairs(s.items) do
        if e.t == Fortify.NAILS_BOX then
            local b = boxUsed(f, e.i)
            out[Fortify.NAILS] = (out[Fortify.NAILS] or 0) + P.cfg().BOX_NAILS - (b ~= nil and b.u or 0)
        end
    end
    return out
end

local function copyMap(m)
    local out = {}
    for k, v in pairs(m) do out[k] = v end
    return out
end

-- Prend n clous hors écran : libres d'abord (écarts du stock), puis dans les boîtes suivies (ordre de la référence).
local function takeNails(g, gid, f, n)
    local St = P.Stock()
    local loose = math.min(n, St.offscreenCount(g.stock, { Fortify.NAILS }))
    if loose > 0 then St.offscreenTake(g, gid, { Fortify.NAILS }, loose) end
    local rest = n - loose
    for _, e in ipairs(g.stock.items) do
        if rest > 0 and e.t == Fortify.NAILS_BOX then
            local b = boxUsed(f, e.i)
            local used = b ~= nil and b.u or 0
            local d = math.min(rest, P.cfg().BOX_NAILS - used)
            if d > 0 then
                if b == nil then
                    b = { i = e.i, u = 0 }
                    f.boxes[#f.boxes + 1] = b
                end
                b.u = used + d
                rest = rest - d
            end
        end
    end
end

-- Prend les besoins reqs (déjà réservés dans avail par Fortify.reserve) dans la référence du groupe g.
local function takeStage(g, gid, f, reqs)
    local St = P.Stock()
    for _, r in ipairs(reqs) do
        if #r.types == 1 and r.types[1] == Fortify.NAILS then
            takeNails(g, gid, f, r.n)
        else
            local left = r.n
            for _, t in ipairs(r.types) do
                if left > 0 then
                    local q = math.min(left, St.offscreenCount(g.stock, { t }))
                    if q > 0 then left = left - St.offscreenTake(g, gid, { t }, q) end
                end
            end
        end
    end
end

local function nightAt(hour)
    return Fortify.ports.isNight((hour + 6) % 24)   -- heure simulée k = intervalle [k - 1, k[ : heure du jour de son début
end

-- Ouvriers du groupe vivant g qui travaillent hors écran : vivants, poste « builder », au foyer (hors expédition),
-- non incarnés.
local function offBuilders(g)
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local n = 0
    for mid, m in pairs(g.members) do
        if type(m) == "table" and m.alive and m.duty == "builder" and not away[mid]
            and not Fortify.ports.isEmbodied(m) then
            n = n + 1
        end
    end
    return n
end

-- Heure simulée hour du groupe vivant g (registre, dans l'écriture du pas de LK_Simulation) : chantiers du relevé
-- avancés selon les ouvriers, les outils et les matériaux du stock (fiche §10). Rend { builders, steps, sites, left }
-- ou nil (rien à faire, nuit, groupe incarné, pas de relevé).
local offscreenHour

function Fortify.offscreenHour(g, gid, hour)
    if type(g) ~= "table" or type(g.home) ~= "table" or type(g.members) ~= "table" then return nil end
    -- LK13-T11 : relevé de la minute encore en file (heure et minute dans la même image) fait d'abord quand l'heure
    -- hors écran peut travailler (mêmes conditions que le début de son corps, indépendantes du relevé) : le relevé
    -- qu'elle lit est celui qu'aurait écrit l'image de la minute. Sinon il reste en file (heure sans effet).
    if Fortify.minuteJobs.queued[gid] ~= nil then
        local St = P.Stock()
        if St ~= nil and St.offscreenTake ~= nil and St.validRef(g.stock, g.home) and type(hour) == "number"
            and not nightAt(hour) and not Fortify.ports.materialized(g) then
            P.settle(gid)
        end
    end
    local f = Fortify.fortView(g.fort, g.home)
    if f == nil or #f.sites == 0 then return nil end
    local out, changed = offscreenHour(g, gid, hour, f)
    if changed or g.fort.v ~= Fortify.FORT_FORMAT then g.fort = Fortify.packFort(f) end   -- LK13-T07 : forme compacte
    return out
end

-- Corps de Fortify.offscreenHour sur la vue de travail f ; rend le résultat et vrai si f a changé.
offscreenHour = function(g, gid, hour, f)
    local St = P.Stock()
    if St == nil or St.offscreenTake == nil or not St.validRef(g.stock, g.home) then return nil, false end
    if type(hour) ~= "number" or nightAt(hour) then return nil, false end
    if Fortify.ports.materialized(g) then return nil, false end   -- vrais ouvriers au travail
    local builders = offBuilders(g)
    if builders == 0 then
        local changed = f.work ~= 0
        f.work = 0
        return nil, changed
    end
    local minutes = f.work + builders * P.cfg().OFF_WORK_MINUTES
    local avail = offAvail(g, f)
    local ops, steps, touched, waiting = {}, 0, 0, false
    local i = 1
    while i <= #f.sites do
        local e = f.sites[i]
        local reqs, tool, cost = nextStage(e)
        if reqs == nil or (tool ~= nil and f.tools[tool] ~= true) then
            i = i + 1
        elseif not Fortify.reserve({ materials = remainingReqs(e) }, copyMap(avail)) then
            i = i + 1   -- tout ce qui reste au chantier ne tient pas dans le stock : chantier passé
        elseif minutes < cost then
            waiting = true
            break
        elseif (#f.pend.ops >= Fortify.OFF_PEND_MAX and ops[e.id] == nil)
            or not Fortify.reserve({ materials = reqs }, avail) then
            break
        else
            takeStage(g, gid, f, reqs)
            minutes = minutes - cost
            local op = ops[e.id]
            if op == nil then
                f.pend.n = f.pend.n + 1
                op = { u = f.pend.n, id = e.id, k = e.k, x = e.x, y = e.y, z = e.z, n = e.n, o = e.o, a = e.h,
                    b = e.h }
                f.pend.ops[#f.pend.ops + 1] = op
                ops[e.id] = op
                touched = touched + 1
            end
            e.h = e.h + 1
            op.b = e.h
            local tier = f.tiers[e.t]
            if tier ~= nil then tier.h = math.min(tier.s, tier.h + 1) end
            steps = steps + 1
            if e.h >= e.s then table.remove(f.sites, i) end
        end
    end
    local work = waiting and minutes or 0
    local changed = work ~= f.work or steps > 0
    f.work = work
    Fortify.stats.offHours = Fortify.stats.offHours + 1
    if steps == 0 then return { builders = builders, steps = 0, sites = 0, left = #f.sites }, changed end
    Fortify.stats.offSteps = Fortify.stats.offSteps + steps
    Fortify.invalidate(gid)   -- plan en mémoire relevé de nouveau (zone non chargée : relevé hors écran)
    LivingKnox.Log.info("fortify: group %s offscreen hour %s: %d builder(s), %d step(s) on %d site(s), %d site(s) left, "
        .. "%d change(s) to place", gid, tostring(hour), builders, steps, touched, #f.sites, #f.pend.ops)
    return { builders = builders, steps = steps, sites = touched, left = #f.sites }, changed
end

-- Niveau (0..100) du relevé hors écran du groupe gid (étapes faites / visées par tier, pondéré comme levelOfSites),
-- ou nil sans relevé valide.
function Fortify.offscreenLevel(gid)
    local g = liveGroup(gid)
    local f = g ~= nil and P.readView(gid, g.fort, g.home) or nil
    if f == nil then return nil end
    local num, den = 0, 0
    for _, t in ipairs(Fortify.TIERS) do
        local p, w = f.tiers[t], P.cfg().WEIGHTS[t] or 0
        if p ~= nil and p.s > 0 and w > 0 then num, den = num + w * p.h / p.s, den + w end
    end
    if den == 0 then return 100 end
    return math.floor(100 * num / den + 0.5)
end

-- Chantiers faisables hors écran d'après le relevé (pur, rien de pris) : chantiers dont l'outil est présent et dont
-- les matériaux restants tiennent après ceux des précédents (comme Fortify.feasibleSites). Liste de copies { id, kind, tier, x,
-- y, z, north, have, steps, offscreen = vrai } (sans case de travail : Fortify.run ne les prend pas), ou nil sans
-- relevé valide.
function Fortify.offscreenFeasible(gid)
    local g = liveGroup(gid)
    local f = g ~= nil and P.readView(gid, g.fort, g.home) or nil
    if f == nil then return nil end
    local St = P.Stock()
    if St == nil or St.offscreenCount == nil or not St.validRef(g.stock, g.home) then return nil end
    local avail = offAvail(g, f)
    local out = {}
    for _, e in ipairs(f.sites) do
        local reqs, tool = nextStage(e)
        if reqs ~= nil and (tool == nil or f.tools[tool] == true)
            and Fortify.reserve({ materials = remainingReqs(e) }, avail) then
            out[#out + 1] = { id = e.id, kind = e.k, tier = e.t, x = e.x, y = e.y, z = e.z, north = e.n, have = e.h,
                steps = e.s, offscreen = true }
        end
    end
    return out
end

-- Relevé hors écran du plan relevé dans le monde (tools : outils présents, Fortify.feasible), écrit au registre s'il
-- a changé et si rien n'attend d'être posé. Rend vrai si écrit.
function Fortify.snapshot(gid, plan, tools)
    if plan == nil or plan.stale then return false end
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return false end
    local sites, skipped = {}, {}
    local tiers = {}
    for _, t in ipairs(Fortify.TIERS) do tiers[t] = { h = 0, s = 0 } end
    for _, s in ipairs(plan.sites) do
        local tier = tiers[s.tier]
        if tier ~= nil then tier.h, tier.s = tier.h + math.min(s.have, s.steps), tier.s + s.steps end
        if not s.done and Fortify.OFF_KINDS[s.kind] then
            local skip = Fortify.kinds.byId[s.kind].offscreen.skip   -- LK16-T02 : chantier écarté par sa sorte
            if skip ~= nil and skip(s) == true then
                skipped[#skipped + 1] = s.id
            else
                sites[#sites + 1] = { id = s.id, k = s.kind, t = s.tier, x = s.x, y = s.y, z = s.z, n = s.north == true,
                    o = s.opp == true, s = s.steps, h = s.have }
            end
        end
    end
    local names = {}
    for name in pairs(tools or {}) do names[#names + 1] = name end
    table.sort(names)
    local toolSet, toolText = {}, {}
    for _, name in ipairs(names) do
        toolSet[name] = tools[name] == true
        toolText[#toolText + 1] = name .. "=" .. tostring(tools[name] == true)
    end
    -- LK13-T07 : clé gardée au registre = empreinte du texte (mémoire : empreinte recalculée seulement s'il change).
    local text = plan.key .. "|" .. table.concat(toolText, ",") .. "|" .. table.concat(skipped, ",")
    local keys = Fortify.state.keys
    if keys == nil then
        keys = {}
        Fortify.state.keys = keys
    end
    local memo = keys[gid]
    if memo == nil or memo.text ~= text then
        memo = { text = text, key = Fortify.digest(text) }
        keys[gid] = memo
    end
    local key = memo.key
    local written = G.update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" then return false, false end
        local f = P.readView(gid, live.fort, live.home)   -- LK13-T11 : lecture seule ici (relevé inchangé : même vue)
        local n = 0
        if f ~= nil then
            if #f.pend.ops > 0 or #f.boxes > 0 then return false, false end   -- application d'abord
            if f.key == key and live.fort.v == Fortify.FORT_FORMAT then return false, false end
            n = f.pend.n
        elseif live.fort ~= nil then
            LivingKnox.Log.warn("fortify: group %s offscreen survey malformed or for another home: replaced", gid)
        end
        local h = live.home
        live.fort = Fortify.packFort({ hx = h.x, hy = h.y, hz = h.z, key = key, day = G.today(), tools = toolSet,
            tiers = tiers, sites = sites, work = 0, boxes = {}, pend = { n = n, ops = {} } })
        return true, true
    end)
    if written == true then
        Fortify.stats.snapshots = Fortify.stats.snapshots + 1
        LivingKnox.Log.debug("fortify: group %s offscreen survey kept: %d site(s) to do, level %d", gid, #sites, plan.level)
        return true
    end
    return false
end

-- LK20-T07 : fonctions privées partagées avec les autres fichiers de Fortify/ (table Fortify._).
P.liveGroup = liveGroup
