-- Living Knox : cadre de décision des PNJ, entrées de l'autorité et notation des groupes (LK05-T02).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"
require "LivingKnox/LK_MemberHealth"   -- LK21-T03 : santé des membres hors écran

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- ================================================================ entrées (autorité)

-- Besoins individuels (LK05-T06, LK_Needs.lua) : LivingKnox.Needs.get(gid, mid) -> { hunger, thirst, fatigue, fear }
-- (0..100). Module absent ou valeur invalide : neutre (0).
function Decisions.needsOf(gid, mid)
    local out = {}
    local N = LivingKnox.Needs
    local got = N ~= nil and N.get ~= nil and N.get(gid, mid) or nil
    for _, key in ipairs(Decisions.NEEDS) do
        local v = type(got) == "table" and got[key] or nil
        out[key] = LivingKnox.Num.finite(v) and LivingKnox.Num.clamp(math.floor(v + 0.5), 0, 100) or 0
    end
    return out
end

-- Interface de la fortification du foyer (LK14) : LivingKnox.Fortification.levelOf(gid) -> 0..100, sinon nil.
function Decisions.fortificationOf(gid)
    local F = LivingKnox.Fortification
    local v = F ~= nil and F.levelOf ~= nil and F.levelOf(gid) or nil
    if LivingKnox.Num.finite(v) then return LivingKnox.Num.clamp(v, 0, 100) end
    return nil
end

-- LK14-T02 : chantier de fortification faisable (LivingKnox.Fortification.hasWork(gid)) : vrai, faux, ou nil.
function Decisions.fortifyWorkOf(gid)
    local F = LivingKnox.Fortification
    if F == nil or F.hasWork == nil then return nil end
    local v = F.hasWork(gid)
    if v == true or v == false then return v end
    return nil
end

-- Santé d'un membre (0..1) : référence du corps (LK_Health) pour un membre incarné, sinon santé hors écran
-- (LK21-T03, LivingKnox.MemberHealth.state).
function Decisions.healthOf(m)
    return (LivingKnox.MemberHealth.state(m))
end

local function isEmbodied(m, registry)
    if m.npc == nil or registry == nil or type(registry.npcs) ~= "table" then return false end
    local npc = registry.npcs[m.npc]
    return npc ~= nil and npc.state == "embodied"
end

local function registryOfBodies()
    local S = LivingKnox.Store
    if S == nil or S.isReady == nil or not S.isReady() then return nil end
    return S.data()
end

-- Comportements permis par le rôle du membre dans son type de groupe (copie en ensemble).
function Decisions.allowedOf(groupType, role)
    local out = {}
    local def = LivingKnox.GroupTypes.peek(groupType)   -- LK13-T11 : lecture en place (rien n'est écrit ni gardé)
    local r = def and def.roles and def.roles[role] or nil
    for _, b in ipairs(r and r.behaviours or {}) do out[b] = true end
    return out
end

-- Menaces connues d'un groupe : menaces distinctes vues ces THREAT_HOURS dernières heures (mémoire).
function Decisions.knownThreats(gid, hour)
    local per = Decisions.state.threats[gid]
    if per == nil then return 0 end
    local n = 0
    for h, keys in pairs(per) do
        if h > hour - P.cfg().THREAT_HOURS and h <= hour then n = n + keys.n end
    end
    return n
end

local function noteThreat(gid, key, hour)
    local st = Decisions.state.threats
    st[gid] = st[gid] or {}
    local per = st[gid]
    local old = {}
    for h in pairs(per) do
        if h <= hour - P.cfg().THREAT_HOURS then old[#old + 1] = h end
    end
    for _, h in ipairs(old) do per[h] = nil end
    per[hour] = per[hour] or { n = 0, keys = {} }
    local slot = per[hour]
    if slot.keys[key] or slot.n >= P.cfg().THREAT_KEYS then return end
    slot.keys[key] = true
    slot.n = slot.n + 1
end

-- Entrée de notation d'un groupe vivant (registre) à l'heure hour.
function Decisions.groupInput(gid, g, hour)
    local G = LivingKnox.Groups
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local members, worst = {}, 0
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then
            local wound = math.floor((1 - Decisions.healthOf(m)) * 100 + 0.5)
            if wound > worst then worst = wound end
            members[#members + 1] = { mid = mid, number = G.memberNumber(mid) or 0, wound = wound,
                allowed = Decisions.allowedOf(g.type, m.role) }
        end
    end
    local traits = {}
    local leader = g.leader and g.members[g.leader] or nil
    if leader and type(leader.traits) == "table" then
        for _, t in ipairs(leader.traits) do traits[t] = true end
    end
    local def = LivingKnox.GroupTypes.peek(g.type)   -- LK13-T11 : lecture en place (hostilité seule)
    local needs = { food = g.needs.food, medical = g.needs.medical, ammo = g.needs.ammo }
    local St = LivingKnox.Stock   -- LK08-T07 : niveaux du stock réel du foyer quand sa référence existe
    local stock = St ~= nil and St.assessGroup ~= nil and St.assessGroup(g) or nil
    if stock ~= nil then
        needs = { food = stock.levels.food, water = stock.levels.water, medical = stock.levels.medical,
            ammo = stock.levels.ammo }
    end
    return { gidNumber = G.idNumber(gid) or 0, day = math.floor(hour / 24) + 1, night = Decisions.isNight(hour),
        needs = needs, rest = g.rest,
        worstWound = worst, threats = Decisions.knownThreats(gid, hour), fortification = Decisions.fortificationOf(gid),
        fortWork = Decisions.fortifyWorkOf(gid),
        hostility = def and def.hostility or 0, traits = traits, members = members }
end

-- Notation d'un groupe vivant (registre) : objectif, postes, journal si changement. Rend vrai si le registre change.
function Decisions.scoreGroup(gid, g, hour)
    local gin = Decisions.groupInput(gid, g, hour)
    if #gin.members == 0 then return false end
    local result = Decisions.scoreObjectives(gin)
    local duties = Decisions.assignDuties(gin.members, result.objective, gin.night,
        Decisions.rotation(gin.gidNumber, hour))
    for _ = 1, #gin.members do   -- E10-T03 : guet refusé, postes refaits ; le nouveau guetteur est jugé à son tour
        if not Decisions.refuseDuties(gid, g, gin.members, duties, hour) then break end
        duties = Decisions.assignDuties(gin.members, result.objective, gin.night, Decisions.rotation(gin.gidNumber, hour))
    end
    Decisions.state.scored[gid] = hour
    Decisions.stats.scored = Decisions.stats.scored + 1
    local changed = g.objective ~= result.objective
    for _, m in ipairs(gin.members) do
        if g.members[m.mid].duty ~= duties[m.mid] then changed = true end
    end
    if not changed then return false end
    -- Changement prévu par l'horloge seule (LK05-T03 : relève d'un quart, tombée de la nuit, aube) : même objectif et
    -- postes gardés = ceux de l'heure précédente ; journal du moteur seulement (pas de journal du groupe à chaque quart).
    local scheduled = false
    if g.objective == result.objective and hour > 0 then
        local before = Decisions.assignDuties(gin.members, result.objective, Decisions.isNight(hour - 1),
            Decisions.rotation(gin.gidNumber, hour - 1))
        scheduled = true
        for _, m in ipairs(gin.members) do
            if g.members[m.mid].duty ~= before[m.mid] then scheduled = false end
        end
    end
    g.objective = result.objective
    local byDuty, order = {}, {}
    for _, m in ipairs(gin.members) do
        local d = duties[m.mid]
        g.members[m.mid].duty = d
        if byDuty[d] == nil then
            byDuty[d] = {}
            order[#order + 1] = d
        end
        byDuty[d][#byDuty[d] + 1] = m
    end
    table.sort(order, function(a, b)
        local ia, ib = 0, 0
        for i, d in ipairs(Decisions.DUTIES) do
            if d == a then ia = i end
            if d == b then ib = i end
        end
        return ia < ib
    end)
    local parts = {}
    for _, d in ipairs(order) do
        local list = byDuty[d]
        table.sort(list, function(a, b) return a.number < b.number end)
        local ids = {}
        for i, m in ipairs(list) do ids[i] = m.mid end
        parts[#parts + 1] = d .. " " .. table.concat(ids, " ")
    end
    local G = LivingKnox.Groups
    local text = result.why .. "; " .. table.concat(parts, ", ")
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then
        Ac.note(gid, nil, "objective", (scheduled and ("watch " .. Decisions.watchOf(hour) .. ": ") or "") .. text)
    end
    if scheduled then
        Decisions.stats.watchChanges = Decisions.stats.watchChanges + 1
        LivingKnox.Log.info("group %s watch %d (hour of day %d): %s", gid, Decisions.watchOf(hour), (hour + 7) % 24,
            table.concat(parts, ", "))
        return true
    end
    G.appendLog(g, "objective", string.sub(text, 1, G.TEXT_MAX), gin.day)
    Decisions.stats.objectiveChanges = Decisions.stats.objectiveChanges + 1
    LivingKnox.Log.info("group %s objective: %s", gid, text)
    return true
end

-- Groupe matérialisé : au moins un membre vivant incarné.
function Decisions.materialized(g, registry)
    for _, m in pairs(g.members) do
        if m.alive and isEmbodied(m, registry) then return true end
    end
    return false
end

-- Notation de tous les groupes matérialisés à l'heure hour (défaut : heure courante), ou du seul groupe only.
-- Une sauvegarde si un objectif ou un poste change. Rend le nombre de groupes notés.
function Decisions.scorePass(hour, only)
    if not LivingKnox.isAuthority() then return 0 end
    hour = hour or Decisions.currentHour()
    if hour == nil then return 0 end
    local G = LivingKnox.Groups
    if not G.ensure() then return 0 end
    local registry = registryOfBodies()
    local count = 0
    G.update(function(data)
        local changed = false
        local ids = {}
        for gid in pairs(data.groups) do ids[#ids + 1] = gid end
        table.sort(ids)
        for _, gid in ipairs(ids) do
            local g = data.groups[gid]
            if (only == nil or only == gid) and Decisions.materialized(g, registry) then
                count = count + 1
                if Decisions.scoreGroup(gid, g, hour) then changed = true end
            end
        end
        return changed, true
    end)
    Decisions.flushRefusals()   -- E10-T03 : refus du guet annoncés hors de l'écriture du registre
    return count
end

P.isEmbodied = isEmbodied
P.noteThreat = noteThreat
P.registryOfBodies = registryOfBodies
