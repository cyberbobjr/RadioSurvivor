-- Living Knox : fortification du foyer, lecture du monde (ouvertures barricadables, pourtour, relevé
-- Fortify.survey)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

-- ================================================================ lecture du monde

local function buildingId(sq)
    if sq == nil then return nil end
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()
end

-- Sorte d'ouverture barricadable d'un objet ("door", "window", "frame"), ou nil.
function Fortify.openingKind(o)
    if instanceof(o, "IsoDoor") then return "door" end
    if instanceof(o, "IsoWindow") then return "window" end
    if instanceof(o, "IsoWindowFrame") then return "frame" end
    if instanceof(o, "IsoThumpable") and o:isBarricadeAllowed() then
        return o:isDoor() and "door" or "window"
    end
    return nil
end

-- Planches d'une barricade (métal : complète), et vrai si elle est en métal.
local function planksOf(b)
    if b == nil then return 0, false end
    if b:isMetal() or b:isMetalBar() then return 4, true end
    return b:getNumPlanks(), false
end

-- LK14-T06 : état (0..1) de la planche extérieure d'une barricade de bois, la seule que les coups usent
-- (IsoBarricade.getThumpCondition, J/iso/objects/IsoBarricade.java:536-549 ; Damage :459-497), ou nil.
function Fortify.outerCondition(b)
    if b == nil or b:isMetal() or b:isMetalBar() or b:getNumPlanks() <= 0 then return nil end
    return b:getThumpCondition()
end

-- LK14-T06 : santé relative (0..1) d'un ouvrage IsoThumpable, ou nil.
function Fortify.healthRatio(o)
    local mx = o ~= nil and o:getMaxHealth() or 0
    if mx == nil or mx <= 0 then return nil end
    return o:getHealth() / mx
end

-- Ouvertures extérieures du bâtiment bid au niveau z : liste { kind, x, y, z, north, inX, inY, outX, outY, opp,
-- planks, metal, allowed }. Objet sur le bord nord ou ouest de sa case (x, y) ; l'autre côté est (x, y - 1) ou
-- (x - 1, y). Cases du rectangle du bâtiment, fin comprise (les bords sud et est sont portés par les cases
-- X2 / Y2, hors du rectangle).
function Fortify.openingsAt(cell, def, bid, z)
    local out = {}
    for y = def:getY(), def:getY2() do
        for x = def:getX(), def:getX2() do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local kind = o ~= nil and Fortify.openingKind(o) or nil
                    -- Cadre qui porte une fenêtre : la fenêtre seule compte (IsoWindowFrame.java:104-106).
                    if kind == "frame" and not o:isBarricadeAllowed() then kind = nil end
                    if kind ~= nil then
                        local north = o:getNorth() == true
                        local ox, oy = x, y - 1
                        if not north then ox, oy = x - 1, y end
                        local inA = buildingId(sq) == bid
                        local inB = buildingId(cell:getGridSquare(ox, oy, z)) == bid
                        if inA ~= inB then
                            local b1, b2 = o:getBarricadeOnSameSquare(), o:getBarricadeOnOppositeSquare()
                            local p1, metal1 = planksOf(b1)
                            local p2, metal2 = planksOf(b2)
                            local e = { kind = kind, x = x, y = y, z = z, north = north,
                                planks = math.max(p1, p2), metal = metal1 or metal2,
                                allowed = o:isBarricadeAllowed() == true, opp = inA }
                            -- LK14-T06 : état de la planche extérieure de la barricade la plus garnie (bois).
                            if not e.metal and e.planks > 0 then
                                e.cond = Fortify.outerCondition((p1 > 0 and p1 >= p2) and b1 or b2)
                            end
                            if inA then
                                e.inX, e.inY, e.outX, e.outY = x, y, ox, oy
                            else
                                e.inX, e.inY, e.outX, e.outY = ox, oy, x, y
                            end
                            out[#out + 1] = e
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Étapes faites sur le bord d'un segment (case porteuse sq, face north) : sorte de l'ouvrage reconnu (noms inscrits,
-- spec.names) et ses étapes faites ; ou nil ; puis l'ouvrage (LK14-T06).
local function builtOn(sq, north)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) == north then
            local name = o:getName()
            local b = name ~= nil and Fortify.BUILT_NAMES[name] or nil   -- LK16-T02 : noms des sortes inscrites
            if b ~= nil then return b.kind, b.steps, o end
        end
    end
    return nil
end

-- Case où un segment peut se poser : chargée, hors bâtiment, ni eau, ni escalier, praticable.
local function groundOk(sq)
    if sq == nil or sq:getBuildingDef() ~= nil then return false end
    if sq:isWaterSquare() or sq:HasStairs() then return false end
    return sq:isFree(false)
end

-- Segments du pourtour du rectangle intérieur r = { x1, y1, x2, y2 } au niveau z (côté, position, case porteuse,
-- face). Côtés dans l'ordre N, E, S, W ; position croissante.
function Fortify.ringSegments(r, z)
    local out = {}
    for x = r.x1, r.x2 do out[#out + 1] = { side = "N", pos = x, x = x, y = r.y1, north = true, ox = x, oy = r.y1 - 1 } end
    for y = r.y1, r.y2 do
        out[#out + 1] = { side = "E", pos = y, x = r.x2 + 1, y = y, north = false, ox = r.x2, oy = y }
    end
    for x = r.x1, r.x2 do
        out[#out + 1] = { side = "S", pos = x, x = x, y = r.y2 + 1, north = true, ox = x, oy = r.y2 }
    end
    for y = r.y1, r.y2 do out[#out + 1] = { side = "W", pos = y, x = r.x1, y = y, north = false, ox = r.x1 - 1, oy = y } end
    for _, s in ipairs(out) do s.z = z end
    return out
end

-- Relevé du foyer d'un groupe : { gid, style, bid, home, levels, openings, ring, ringKind, bounds, outerSkipped },
-- ou nil et la raison (zone non chargée...). Lecture seule.
function Fortify.survey(gid)
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil, "registry not ready" end
    local g = G.get(gid)
    if g == nil then return nil, "unknown group" end
    local home = g.home
    if type(home) ~= "table" then return nil, "no home" end
    local style, def = LivingKnox.Homes.ready(home)
    if style == nil then return nil, def end
    local cell = getCell()
    local c = P.cfg()
    local s = { gid = gid, style = style, home = { x = home.x, y = home.y, z = home.z }, openings = {} }
    local rect
    if style == "building" then
        s.bid = def:getIDString()
        local M = c.OUTER_MARGIN
        rect = { x1 = def:getX() - M, y1 = def:getY() - M, x2 = def:getX2() - 1 + M, y2 = def:getY2() - 1 + M }
        s.ringKind, s.ringZ = Fortify.ringKindOf("building"), 0   -- LK16-T02 : sorte inscrite (spec.ring)
        s.levels = math.max(0, def:getMaxLevel())
    else
        local R = c.CAMP_RING
        rect = { x1 = home.x - R, y1 = home.y - R, x2 = home.x + R, y2 = home.y + R }
        s.ringKind, s.ringZ = Fortify.ringKindOf("camp"), home.z
        s.levels = 0
    end
    s.rect = rect
    s.bounds = { x1 = rect.x1 - 1, y1 = rect.y1 - 1, x2 = rect.x2 + 1, y2 = rect.y2 + 1 }
    for _, p in ipairs({ { s.bounds.x1, s.bounds.y1 }, { s.bounds.x2, s.bounds.y1 }, { s.bounds.x2, s.bounds.y2 },
        { s.bounds.x1, s.bounds.y2 } }) do
        if cell:getGridSquare(p[1], p[2], s.ringZ) == nil then return nil, "home area not loaded" end
    end
    if style == "building" then
        for z = 0, s.levels do
            for _, e in ipairs(Fortify.openingsAt(cell, def, s.bid, z)) do
                if #s.openings < c.MAX_OPENINGS then s.openings[#s.openings + 1] = e end
            end
        end
    end
    local segs = Fortify.ringSegments(rect, s.ringZ)
    s.ring = {}
    if s.ringKind == nil then
        s.outerSkipped = "no ring kind for " .. tostring(style)
    elseif #segs > c.MAX_OUTER then
        s.outerSkipped = "ring of " .. #segs .. " segment(s) over " .. c.MAX_OUTER
    else
        for _, seg in ipairs(segs) do
            local sq = cell:getGridSquare(seg.x, seg.y, seg.z)
            local other = cell:getGridSquare(seg.ox, seg.oy, seg.z)
            local e = { side = seg.side, pos = seg.pos, x = seg.x, y = seg.y, z = seg.z, north = seg.north,
                ox = seg.ox, oy = seg.oy }
            if sq == nil or other == nil then
                e.blocked = "not loaded"
            else
                local kind, steps, obj = builtOn(sq, seg.north)
                if kind ~= nil then
                    e.built, e.steps = kind, steps
                    -- LK14-T06 : santé d'un ouvrage achevé (mur sur son cadre, palissade) ; un cadre seul n'est pas
                    -- réparé (l'étape du mur le remplace).
                    if steps >= #(Fortify.STAGES[kind] or {}) then e.health = Fortify.healthRatio(obj) end
                elseif not groundOk(sq) or other:getBuildingDef() ~= nil or other:isWaterSquare() then
                    e.blocked = "ground"
                elseif sq:isBlockedTo(other) then
                    e.blocked = "edge closed"
                end
            end
            s.ring[#s.ring + 1] = e
        end
    end
    Fortify.stats.surveys = Fortify.stats.surveys + 1
    return s
end

-- LK20-T07 : fonctions privées partagées avec les autres fichiers de Fortify/ (table Fortify._).
P.planksOf, P.builtOn, P.groundOk = planksOf, builtOn, groundOk
