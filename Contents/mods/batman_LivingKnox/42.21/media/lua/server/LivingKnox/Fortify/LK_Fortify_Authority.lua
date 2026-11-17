-- Living Knox : fortification du foyer, stock et faisabilité (matériaux, outils, réservation), puis autorité :
-- plan gardé, niveau, besoins de réparation, chantier d'un ouvrier (Fortify.plan, feasible, siteFor)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

-- ================================================================ stock et faisabilité

-- Matériaux disponibles d'après l'inventaire de référence du stock : { [type complet] = nombre } (boîte de clous =
-- BOX_NAILS clous), ou nil et une raison.
function Fortify.available(gid)
    local St = P.Stock()
    if St == nil or St.reference == nil then return nil, "no stock module" end
    local ref, why = St.reference(gid)
    if ref == nil then return nil, why end
    local out = {}
    for _, e in ipairs(ref.items or {}) do
        local t = e.t
        if t == Fortify.NAILS_BOX then
            out[Fortify.NAILS] = (out[Fortify.NAILS] or 0) + P.cfg().BOX_NAILS
        elseif type(t) == "string" then
            out[t] = (out[t] or 0) + 1
        end
    end
    return out
end

-- Vrai si un objet du tag ItemTag[name] est dans les conteneurs du foyer (outil gardé, non consommé).
function Fortify.hasTool(gid, name)
    local St = P.Stock()
    if St == nil or St.findItem == nil or ItemTag == nil or ItemTag[name] == nil then return false end
    local tag = ItemTag[name]
    local found = St.findItem(gid, function(it) return it:hasTag(tag) end)
    return found ~= nil
end

-- Prend le besoin r ({ types, n }) dans avail en plus de taken ; rend vrai (taken complété) ou faux (taken inchangé).
local function reserveReq(r, avail, taken)
    local left, add = r.n, {}
    for _, t in ipairs(r.types) do
        local have = (avail[t] or 0) - (taken[t] or 0)
        if have > 0 and left > 0 then
            local q = math.min(have, left)
            add[t] = q
            left = left - q
        end
    end
    if left > 0 then return false end
    for t, q in pairs(add) do taken[t] = (taken[t] or 0) + q end
    return true
end

-- Réserve les matériaux de site dans avail (modifié) ; rend vrai si tout y est, sinon avail est inchangé. LK14-T06 :
-- site.options (pièces facultatives d'une réparation) : une seule, la première qui tient, est exigée.
function Fortify.reserve(site, avail)
    local taken = {}
    for _, r in ipairs(site.materials) do
        if not reserveReq(r, avail, taken) then return false end
    end
    if site.options ~= nil and #site.options > 0 then
        local ok = false
        for _, r in ipairs(site.options) do
            if not ok and reserveReq(r, avail, taken) then ok = true end
        end
        if not ok then return false end
    end
    for t, q in pairs(taken) do avail[t] = avail[t] - q end
    return true
end

-- Chantiers faisables d'un plan (pur) : restants, dans l'ordre du plan, dont les outils sont présents (tools[nom]
-- vrai) et dont les matériaux tiennent dans avail après ceux des précédents. Rend la liste (copies des chantiers).
function Fortify.feasibleSites(plan, avail, tools)
    local left = {}
    for t, n in pairs(avail or {}) do left[t] = n end
    local out = {}
    for _, s in ipairs(plan.sites) do
        if not s.done then
            local ok = true
            for _, name in ipairs(s.tools) do
                if not tools[name] then ok = false end
            end
            if ok and Fortify.reserve(s, left) then out[#out + 1] = s end
        end
    end
    return out
end

-- ================================================================ autorité : plan, niveau, ouvriers

-- Plan du foyer du groupe gid, relevé de nouveau au plus toutes les PLAN_MS (opts.force : maintenant). Zone non
-- chargée : dernier plan connu (champ stale vrai), sinon nil et la raison.
-- LK13-T11 (suite) : trois étapes, enchaînées ici, séparables par la file de la minute (une étape par image) :
-- planNeed (plan gardé, ou contexte d'un nouveau relevé), planSurvey (relevé du monde), planFinish (plan pur, journal,
-- plan gardé). Le contexte porte l'heure (now) et l'urgence de la première étape.
local function planNeed(gid, opts)
    local st = Fortify.state.plans[gid]
    local t = P.now()
    local urgent = Fortify.urgent(gid)
    if st ~= nil and not (opts and opts.force) and t - st.ms < P.cfg().PLAN_MS and st.plan.urgent == urgent then
        return true, st.plan
    end
    return false, { gid = gid, t = t, urgent = urgent }
end

local function planSurvey(ctx)
    ctx.survey, ctx.why = Fortify.survey(ctx.gid)
    ctx.surveyed = true
end

local function planFinish(ctx)
    local gid, survey = ctx.gid, ctx.survey
    local st = Fortify.state.plans[gid]
    if survey == nil then
        Fortify.stats.notReady = Fortify.stats.notReady + 1
        if st ~= nil then
            st.plan.stale = true
            return st.plan
        end
        return nil, ctx.why
    end
    local plan = Fortify.build(survey, { urgent = ctx.urgent })
    if st == nil or st.plan.key ~= plan.key then
        Fortify.stats.changed = Fortify.stats.changed + 1
        local counts = { ground = 0, upper = 0, outer = 0 }
        for _, s in ipairs(plan.sites) do
            if not s.done then counts[s.tier] = counts[s.tier] + 1 end
        end
        LivingKnox.Log.info("fortify: group %s plan (%s): %d site(s), %d to do (ground %d, upper %d, outer %d), %d gap(s), "
            .. "%d skipped, level %d, %d repair(s)%s", gid, plan.style, #plan.sites, plan.todo, counts.ground,
            counts.upper, counts.outer, #plan.gaps, #plan.skipped, plan.level, plan.repairs,
            plan.urgent and " first (after an attack)" or "")
        if plan.outerSkipped then LivingKnox.Log.info("fortify: group %s: no outer defence (%s)", gid, plan.outerSkipped) end
    end
    Fortify.state.plans[gid] = { plan = plan, ms = ctx.t }
    return plan
end

function Fortify.plan(gid, opts)
    P.settle(gid)   -- LK13-T11 : relevé de la minute encore en file fait d'abord (même résultat qu'avant la file)
    local given = Fortify.givenPlan   -- dernière étape d'un relevé en file : plan de ses deux premières étapes
    if given ~= nil and given.gid == gid and not (opts and opts.force) then
        Fortify.givenPlan = nil
        if given.plan ~= nil then return given.plan end
        return nil, given.why
    end
    local done, plan = planNeed(gid, opts)
    if done then return plan end
    planSurvey(plan)
    return planFinish(plan)
end

-- Niveau de fortification du foyer (0..100), ou nil si aucun plan n'est connu. LK14-T05 : foyer hors de la zone
-- chargée (plan absent ou ancien) : niveau du relevé gardé au registre, avancé par la simulation hors écran.
function Fortify.levelOf(gid)
    local plan = Fortify.plan(gid)
    if plan == nil or plan.stale then
        local level = Fortify.offscreenLevel(gid)
        if level ~= nil then return level end
    end
    if plan == nil then return nil end
    return plan.level
end

-- LK14-T06 : vrai si une attaque contre le foyer a été repoussée il y a moins de REPAIR_URGENT_MINUTES minutes de jeu
-- (marque LivingKnox.Defense.after, LK05-T09) : les réparations passent alors en tête du plan.
function Fortify.urgent(gid)
    local mark = Fortify.ports.attackMark(gid)
    if mark == nil or type(mark.minute) ~= "number" then return false end
    local minute = Fortify.ports.currentMinute()
    if minute == nil then return false end
    return minute - mark.minute <= P.cfg().REPAIR_URGENT_MINUTES
end

-- LK14-T06 : besoin de réparation (pur) : réparations du plan non faisables avec avail (après les chantiers faisables
-- qui les précèdent) et outils absents. Rend { materials = { [type] = manquant }, tools = { nom... }, sites = n } ou nil.
function Fortify.repairShortage(plan, avail, tools, feasible)
    local ok = {}
    local left = {}
    for t, n in pairs(avail or {}) do left[t] = n end
    for _, s in ipairs(feasible) do
        ok[s.id] = true
        Fortify.reserve(s, left)   -- matériaux des chantiers faisables : déjà promis
    end
    local need, missingTools, toolSeen, blocked = {}, {}, {}, 0
    for _, s in ipairs(plan.sites) do
        local spec = Fortify.kinds.byId[s.kind]
        if spec ~= nil and spec.need == true and not s.done and not ok[s.id] then   -- LK16-T02 : sortes à besoin
            blocked = blocked + 1
            for _, name in ipairs(s.tools) do
                if not tools[name] and not toolSeen[name] then
                    toolSeen[name] = true
                    missingTools[#missingTools + 1] = name
                end
            end
            local reqs = {}
            for _, r in ipairs(s.materials) do reqs[#reqs + 1] = r end
            if s.options ~= nil and #s.options > 0 then
                local opt = s.options[1]   -- aucune pièce facultative en quantité : la première est demandée
                for i = #s.options, 1, -1 do
                    if reserveReq(s.options[i], left, {}) then opt = s.options[i] end
                end
                reqs[#reqs + 1] = opt
            end
            for _, r in ipairs(reqs) do
                -- ce qui existe est compté pour cette réparation (la suivante ne le reprend pas), le reste manque
                local rest = r.n
                for _, t in ipairs(r.types) do
                    local q = math.min(rest, left[t] or 0)
                    if q > 0 then
                        left[t] = left[t] - q
                        rest = rest - q
                    end
                end
                if rest > 0 then need[r.types[1]] = (need[r.types[1]] or 0) + rest end
            end
        end
    end
    if blocked == 0 then return nil end
    table.sort(missingTools)
    return { materials = need, tools = missingTools, sites = blocked }
end

-- Texte stable d'un besoin : "2 Base.Plank, 4 Base.Nails; tools: SAW".
local function needText(n)
    local types = {}
    for t in pairs(n.materials) do types[#types + 1] = t end
    table.sort(types)
    local parts = {}
    for _, t in ipairs(types) do parts[#parts + 1] = n.materials[t] .. " " .. t end
    local text = #parts > 0 and table.concat(parts, ", ") or "no material"
    if #n.tools > 0 then text = text .. "; tools: " .. table.concat(n.tools, ", ") end
    return text
end

-- LK14-T06 : note le besoin de réparation du groupe (Fortify.needOf) et l'écrit au journal du groupe (kind
-- « shortage ») : une fois par attaque repoussée (marque Defense.after) et au plus toutes les NEED_HOURS pour un même
-- besoin. Aucun besoin : la note est effacée.
local function noteNeed(gid, plan, shortage)
    local needs = Fortify.state.needs
    if shortage == nil then
        needs[gid] = nil
        return
    end
    local mark = Fortify.ports.attackMark(gid)
    local minute = Fortify.ports.currentMinute() or 0
    local text = needText(shortage)
    local attack = plan.urgent and mark ~= nil and mark.id or nil
    local prev = needs[gid]
    shortage.text, shortage.attack, shortage.minute = text, attack, minute
    local fresh = prev == nil or prev.text ~= text or prev.attack ~= attack
        or minute - (prev.logged or -1e18) >= P.cfg().NEED_HOURS * 60
    shortage.logged = prev ~= nil and prev.logged or nil
    needs[gid] = shortage
    if not fresh then return end
    shortage.logged = minute
    Fortify.stats.needs = Fortify.stats.needs + 1
    local line = string.format("materials to repair %d defence(s): %s%s", shortage.sites, text,
        attack ~= nil and (" (after " .. attack .. ")") or "")
    LivingKnox.Log.info("fortify: group %s %s", gid, line)
    local G = LivingKnox.Groups
    if G ~= nil and G.addLog ~= nil then G.addLog(gid, "shortage", line) end
end

-- LK14-T06 : besoin de réparation en cours du groupe gid (copie), ou nil : { materials = { [type] = n }, tools,
-- sites, text, attack, minute }. Point d'appel des consommateurs (expéditions, missions) : matériaux à rapporter.
function Fortify.needOf(gid)
    local n = Fortify.state.needs[gid]
    if n == nil then return nil end
    local materials, tools = {}, {}
    for t, q in pairs(n.materials) do materials[t] = q end
    for i, name in ipairs(n.tools) do tools[i] = name end
    return { materials = materials, tools = tools, sites = n.sites, text = n.text, attack = n.attack,
        minute = n.minute }
end

-- Chantiers faisables du foyer maintenant (stock et outils du foyer), ou nil et une raison. LK14-T06 : réparations non
-- faisables notées comme besoin du groupe (noteNeed).
function Fortify.feasible(gid)
    local plan, why = Fortify.plan(gid)
    -- LK14-T05 : travail fait hors écran posé d'abord (zone du foyer chargée), puis plan relevé de nouveau.
    if plan ~= nil and not plan.stale and Fortify.hasPending(gid) then
        Fortify.applyPending(gid)
        plan, why = Fortify.plan(gid, { force = true })
    end
    if plan == nil or plan.stale then
        -- LK14-T05 : foyer hors de la zone chargée : chantiers faisables d'après le relevé gardé au registre.
        local off = Fortify.offscreenFeasible(gid)
        if off ~= nil then return off end
    end
    if plan == nil then return nil, why end
    local avail, w2 = Fortify.available(gid)
    if avail == nil then return nil, w2 end
    local tools = {}
    for _, s in ipairs(plan.sites) do
        if not s.done then
            for _, name in ipairs(s.tools) do
                if tools[name] == nil then tools[name] = Fortify.hasTool(gid, name) end
            end
        end
    end
    local list = Fortify.feasibleSites(plan, avail, tools)
    if (plan.repairs or 0) > 0 or Fortify.state.needs[gid] ~= nil then
        noteNeed(gid, plan, (plan.repairs or 0) > 0 and Fortify.repairShortage(plan, avail, tools, list) or nil)
    end
    if not plan.stale then Fortify.snapshot(gid, plan, tools) end   -- LK14-T05 : relevé gardé pour le hors écran
    return list
end

-- Vrai si au moins un chantier est faisable, faux sinon, nil si on ne sait pas (plan ou stock inconnu).
function Fortify.hasWork(gid)
    local list = Fortify.feasible(gid)
    if list == nil then return nil end
    return #list > 0
end

-- Chantier proposé au membre mid de poste « builder » (point d'appel de LK14-T03) : le k-ième faisable pour le
-- k-ième ouvrier vivant (numéro de membre croissant). Rend le chantier, ou nil et la raison.
function Fortify.siteFor(gid, mid)
    local G = LivingKnox.Groups
    local g = G ~= nil and G.isReady() and G.get(gid) or nil
    if g == nil then return nil, "unknown group" end
    local m = g.members and g.members[mid]
    if m == nil or not m.alive then return nil, "not a living member" end
    if m.duty ~= "builder" then return nil, "not a builder" end
    local builders = {}
    for id, b in pairs(g.members) do
        if b.alive and b.duty == "builder" then builders[#builders + 1] = { id = id, n = G.memberNumber(id) or 0 } end
    end
    table.sort(builders, function(a, b)
        if a.n ~= b.n then return a.n < b.n end
        return a.id < b.id
    end)
    local k = 0
    for i, b in ipairs(builders) do
        if b.id == mid then k = i end
    end
    local list, why = Fortify.feasible(gid)
    if list == nil then return nil, why end
    local site = list[k]
    if site == nil then return nil, "nothing feasible" end
    return site
end

-- Plan du groupe à relever de nouveau au prochain appel (le dernier reste connu si la zone se décharge).
function Fortify.invalidate(gid)
    P.settle(gid)   -- LK13-T11 : relevé de la minute encore en file fait avant d'oublier le plan
    local st = Fortify.state.plans[gid]
    if st ~= nil then st.ms = -1e18 end
end

-- LK20-T07 : fonctions privées partagées avec les autres fichiers de Fortify/ (table Fortify._).
P.planNeed, P.planSurvey, P.planFinish = planNeed, planSurvey, planFinish
