-- Living Knox : routine « repas » des PNJ au foyer (LK05-T07, découpée en LK15-T02, ADR D05) : prise réelle dans le
-- stock du foyer, consommation assise, repas appliqué une fois, besoin mis de côté (unfed). Fiche :
-- docs/annexes/conception/routines.md. Activité du comportement « meal » (ordre 10) ; Routines.runMeal la mène.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_RoutineExec"

local Routines = LivingKnox.Routines
local E = Routines.exec
local buildingId, placeBeside = E.buildingId, E.placeBeside
local goTo, faceTo, sitDown, entryOf = E.goTo, E.faceTo, E.sitDown, E.entryOf

local function log() return LivingKnox.Log end
local function cfg() return Routines.CFG end
local function Groups() return LivingKnox.Groups end

local function unfedKey(gid, mid) return tostring(gid) .. "/" .. tostring(mid) end

-- Met de côté le besoin need ("hunger" ou "thirst") du membre jusqu'à la minute de jeu untilMin.
function Routines.fast(gid, mid, need, untilMin)
    local st = Routines.state
    st.unfed = st.unfed or {}
    local key = unfedKey(gid, mid)
    local f = st.unfed[key] or {}
    st.unfed[key] = f
    if f[need] == nil or untilMin > f[need] then f[need] = untilMin end
end

-- Besoins mis de côté du membre à la minute minute (lu par la cascade, LivingKnox.Decisions.context) :
-- { hunger = vrai, thirst = vrai } (clés présentes seulement), ou nil.
function Routines.unfed(gid, mid, minute)
    local f = (Routines.state.unfed or {})[unfedKey(gid, mid)]
    if f == nil or minute == nil then return nil end
    local out, any = {}, false
    for _, need in ipairs({ "hunger", "thirst" }) do
        if f[need] ~= nil and minute < f[need] then
            out[need], any = true, true
        end
    end
    if not any then return nil end
    return out
end

-- Repas pris (m.pending) appliqué une seule fois : jauge du membre baissée de m.relief, registre sauvegardé.
function Routines.finishMeal(id, m)
    if m == nil or not m.pending then return false end
    m.pending = false
    local N, G = LivingKnox.Needs, Groups()
    local value
    if N ~= nil and N.relieve ~= nil and G ~= nil then
        G.update(function(data)
            local g = data.groups[m.gid]
            if g == nil then return false, false end
            value = N.relieve(g, m.mid, m.need, m.relief)
            return value ~= nil, true
        end)
    end
    log().info("npc %s (%s %s): %s of %s done, %s -%d -> %s", tostring(id), tostring(m.gid), tostring(m.mid),
        m.need == "thirst" and "drink" or "meal", m.took and m.took.t or "?", m.need, m.relief or 0, tostring(value))
    return true
end

-- Part de ration d'un repas : Stock.portion, au moins celle du rationnement strict (un objet a bien été trouvé même
-- quand l'autre catégorie est épuisée).
local function mealPortion(gid)
    local S = LivingKnox.Stock
    if S == nil or S.portion == nil then return 1 end
    local p = S.portion(gid)
    local least = S.PORTIONS ~= nil and S.PORTIONS[3] or 0.5
    if type(p) ~= "number" or p < least then p = least end
    return p
end

local function mealOff(id, m, ctx, why, minutes)
    Routines.fast(ctx.gid, ctx.mid, m.need, ctx.minute + minutes)
    Routines.stats.fasts = Routines.stats.fasts + 1
    m.phase = "done"
    log().debug("npc %s: %s set aside for %d minute(s): %s", tostring(id), m.need, minutes, tostring(why))
end

local function mealRestart(m)
    m.phase, m.spot, m.place = "find", nil, nil
    m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
end

-- Repas réel du membre (comportement « meal », règle hunger ou thirst de la cascade), à chaque passage.
function Routines.runMeal(id, st, ctx, g)
    local need = st.rule == "thirst" and "thirst" or "hunger"
    local key = "meal " .. need
    local mem = Routines.state.npcs
    local m = mem[id]
    if m == nil or m.key ~= key then
        if m ~= nil then Routines.leave(id) end
        m = { key = key, kind = "meal", need = need, cat = Routines.MEAL[need], gid = ctx.gid, mid = ctx.mid,
            phase = "find", tries = 0, fails = 0 }
        mem[id] = m
        log().debug("npc %s: routine %s (%s)", id, key, tostring(st.why))
    end
    local e = entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) and (m.phase == "go" or m.phase == "face"
        or m.phase == "take") then
        -- Une autre consigne est passée avant la prise (suite de test, autre module) : retour à la place du repas.
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
        m.phase = "go"
    end
    local S = LivingKnox.Stock
    if m.phase == "find" then
        if S == nil or S.findMeal == nil then return mealOff(id, m, ctx, "no stock module", cfg().UNFED_MINUTES) end
        local spot, why = S.findMeal(ctx.gid, m.cat)
        if spot == nil then
            if why == "none" then S.reportShortage(ctx.gid, m.cat, ctx.mid) end
            return mealOff(id, m, ctx, why, cfg().UNFED_MINUTES)
        end
        local cell = getCell()
        local home = g.home
        local hsq = cell ~= nil and type(home) == "table" and cell:getGridSquare(home.x, home.y, home.z) or nil
        local bid = hsq ~= nil and buildingId(hsq) or nil
        local place = cell ~= nil and placeBeside(cell, spot.x, spot.y, spot.z, bid, {}) or nil
        if place == nil then
            return mealOff(id, m, ctx, "no free square beside " .. spot.key, cfg().UNFED_MINUTES)
        end
        m.spot, m.place, m.phase = spot, place, "go"
    end
    if m.phase == "go" then
        local res = goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
        if res == "moving" then return end
        if res == "failed" then return mealOff(id, m, ctx, "cannot reach " .. m.spot.key, cfg().UNFED_MINUTES) end
        m.phase = "face"
    end
    if m.phase == "face" then
        if m.faceV == nil then
            faceTo(id, m, m.place.a)
            return
        end
        e = entryOf(id)
        if e == nil or e.v ~= m.faceV or not e.done then return end
        sitDown(id, m, Routines.MEAL_TAKE_GESTURE)
        m.since, m.phase = ctx.minute, "take"
        return
    end
    if m.phase == "take" then
        if ctx.minute - m.since < cfg().MEAL_TAKE_MINUTES then return end
        local portion = mealPortion(ctx.gid)
        local got, why = S.takeMeal(ctx.gid, m.cat, m.spot.key, nil, ctx.mid)
        if got == nil then
            m.tries = m.tries + 1
            log().debug("npc %s: %s at %s not taken: %s", id, m.cat, m.spot.key, tostring(why))
            if m.tries >= cfg().MEAL_TRIES then return mealOff(id, m, ctx, why, cfg().UNFED_MINUTES) end
            mealRestart(m)
            return
        end
        local N = LivingKnox.Needs
        local full = 60
        if N ~= nil and N.CFG ~= nil then full = need == "thirst" and N.CFG.DRINK or N.CFG.MEAL end
        m.took, m.relief, m.pending = got, math.floor(full * portion + 0.5), true
        Routines.stats.meals = Routines.stats.meals + 1
        sitDown(id, m, Routines.MEAL_EAT_GESTURE)
        m.since, m.phase = ctx.minute, "eat"
        return
    end
    if m.phase == "eat" then
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) ~= Routines.MEAL_EAT_GESTURE then sitDown(id, m, Routines.MEAL_EAT_GESTURE) end
        if ctx.minute - m.since < cfg().MEAL_EAT_MINUTES then return end
        Routines.finishMeal(id, m)
        Routines.fast(ctx.gid, ctx.mid, need, ctx.minute + cfg().MEAL_GAP_MINUTES)
        m.phase = "done"
    end
end

Routines.registerActivity({ id = "meal", behaviour = "meal", order = 10,
    run = function(id, st, ctx, g)
        Routines.runMeal(id, st, ctx, g)
        return true
    end })
