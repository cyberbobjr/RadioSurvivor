-- Living Knox : cadre de décision des PNJ, objectifs du groupe et postes des membres (logique pure, LK05-T02,
-- LK05-T03).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- ================================================================ groupe : objectifs et postes (pur)

local function jitter(gidNumber, day, i)
    local j = P.cfg().JITTER
    if j <= 0 then return 0 end
    local rnd = Decisions.stream("group" .. tostring(gidNumber), day, 1000 + i)
    return P.pick(-j, j, rnd)
end

-- Notation des objectifs (pur). gin = { gidNumber, day, night, needs = { food, water (facultatif : stock réel,
-- LK08-T07), medical, ammo } (réserves 0..100 : LivingKnox.Stock.assessGroup, sinon besoins abstraits), rest (0..100),
-- worstWound (0..100), threats (nombre de menaces connues), fortification (0..100 ou nil), fortWork (chantier de
-- fortification faisable : vrai, faux, ou nil inconnu, LK14-T02), hostility (0..100),
-- traits = { [trait] = vrai } (chef) }. Rend { objective, score, scores = { [objectif] = entier }, why }.
function Decisions.scoreObjectives(gin)
    local c = P.cfg()
    local raw, factors = {}, {}
    for _, o in ipairs(Decisions.OBJECTIVES) do
        raw[o], factors[o] = 0, {}
    end
    local function add(o, v, what)
        if v == 0 then return end
        raw[o] = raw[o] + v
        if what then factors[o][#factors[o] + 1] = what end
    end
    add("settle", c.SETTLE)
    local rest = gin.rest or 50
    if gin.night then
        add("rest", c.NIGHT_REST, "night")
    elseif rest < c.REST_OK then
        add("rest", (c.REST_OK - rest) * 1.5, "rest " .. rest)
    end
    if (gin.threats or 0) > 0 then add("guard", math.min(80, gin.threats * 20), "threats " .. gin.threats) end
    local hostility = gin.hostility or 0
    if hostility > 0 then add("guard", math.floor(hostility * 0.1 + 0.5), "hostility " .. hostility) end
    local needs = gin.needs or {}
    if (needs.medical or 0) > 0 and (gin.worstWound or 0) >= c.HEAL_MIN then
        add("heal", math.floor(gin.worstWound * 0.9 + 0.5), "wound " .. gin.worstWound)
    end
    local lowest, lowKey = 100, nil
    for _, key in ipairs({ "food", "water", "medical", "ammo" }) do
        local v = needs[key]   -- water : seulement d'après le stock réel (LK08-T07), sinon ignorée
        if v == nil and key ~= "water" then v = 50 end
        if v ~= nil and v < lowest then lowest, lowKey = v, key end
    end
    if lowest < c.NEED_OK then add("supply", (c.NEED_OK - lowest) * 1.5, (lowKey or "?") .. " " .. lowest) end
    -- LK14-T02 : fortWork (LivingKnox.Fortification.hasWork) faux = aucun chantier faisable avec le stock du foyer :
    -- pas de score de fortification ; vrai : les menaces connues pressent le chantier ; nil (inconnu) : comme avant.
    if lowest >= 50 and gin.fortWork ~= false then
        local fort = gin.fortification
        local known = fort ~= nil
        if not known then fort = c.FORT_NEUTRAL end
        add("fortify", math.floor((100 - fort) * 0.5 + 0.5), (known and "fortification " or "fortification unknown ")
            .. fort)
        if gin.fortWork == true and (gin.threats or 0) > 0 and fort < 100 then
            add("fortify", math.min(c.FORT_THREAT_MAX, gin.threats * c.FORT_THREAT), "threats " .. gin.threats)
        end
    end
    local traits = gin.traits or {}
    local names = {}
    for t in pairs(traits) do names[#names + 1] = t end
    table.sort(names)
    for _, t in ipairs(names) do
        local bonus = c.TRAITS[t]
        if bonus then
            for _, o in ipairs(Decisions.OBJECTIVES) do
                if bonus[o] then add(o, bonus[o], "leader " .. t) end
            end
        end
    end
    local scores = {}
    local best, bestScore
    for i, o in ipairs(Decisions.OBJECTIVES) do
        local s = LivingKnox.Num.clamp(math.floor(raw[o] + 0.5) + jitter(gin.gidNumber or 0, gin.day or 0, i), 0, 100)
        scores[o] = s
        if best == nil or s > bestScore then best, bestScore = o, s end
    end
    local second, secondScore
    for _, o in ipairs(Decisions.OBJECTIVES) do
        if o ~= best and (second == nil or scores[o] > secondScore) then second, secondScore = o, scores[o] end
    end
    local why = best .. " " .. bestScore
    if #factors[best] > 0 then why = why .. " (" .. table.concat(factors[best], ", ") .. ")" end
    if second then why = why .. " > " .. second .. " " .. secondScore end
    return { objective = best, score = bestScore, scores = scores, why = why }
end

local function eligible(member, duty)
    if member.refuses ~= nil and member.refuses[duty] then return false end   -- E10-T03 : poste refusé
    local need = Decisions.DUTY_NEEDS[duty]
    return need == nil or P.anyOf(member.allowed or {}, need)
end

-- Postes (pur). members = { { mid, number, allowed = { [comportement] = vrai }, wound (0..100) }, ... } (ordre
-- quelconque), objective, night, rotation = entier >= 0. Rend { [mid] = poste }.
function Decisions.assignDuties(members, objective, night, rotation)
    local c = P.cfg()
    local list = {}
    for _, m in ipairs(members) do list[#list + 1] = m end
    table.sort(list, function(a, b) return a.number < b.number end)
    local n = #list
    local out = {}
    local able = {}
    for _, m in ipairs(list) do
        if (m.wound or 0) >= c.WOUND_DUTY then out[m.mid] = "rest" else able[#able + 1] = m end
    end
    -- Rotation : la liste des valides commence au rang rotation % nombre (relève de jour en jour).
    local k = #able
    local rotated = {}
    for i = 1, k do rotated[i] = able[((i - 1 + (rotation or 0)) % k) + 1] end
    local function take(duty, count)
        local got = 0
        for _, m in ipairs(rotated) do
            if got >= count then return end
            if out[m.mid] == nil and eligible(m, duty) then
                out[m.mid] = duty
                got = got + 1
            end
        end
    end
    local sentries = 1
    if objective == "guard" then sentries = math.floor((n + 1) / 2) end
    take("sentry", sentries)
    if objective == "heal" then take("carer", k) end
    if objective == "supply" then take("forager", math.max(1, math.floor(n / 2))) end
    if objective == "fortify" then take("builder", math.max(1, math.floor(n / 2))) end
    local rest = objective == "rest" or (night and objective ~= "guard")
    for _, m in ipairs(rotated) do
        if out[m.mid] == nil then out[m.mid] = rest and "rest" or "keeper" end
    end
    return out
end
