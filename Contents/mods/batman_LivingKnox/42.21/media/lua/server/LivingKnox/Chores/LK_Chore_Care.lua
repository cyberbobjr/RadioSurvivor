-- Living Knox : corvée « care » (LK05-T04, inscrite en LK16-T07) : s'agenouiller à côté du membre présent le plus blessé
-- (santé sous CFG.CARE_HEALTH, corps incarné au foyer) ; sans place à côté de lui : se reposer. Moteur :
-- Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

local Routines = LivingKnox.Routines

local function Decisions() return LivingKnox.Decisions end

-- Membre présent le plus blessé (santé sous CARE_HEALTH, corps incarné au foyer), autre que mid : mid, corps ; ou nil.
function Routines.woundedFor(g, mid, home)
    local B = LivingKnox.Bodies
    if B == nil or B.find == nil then return nil end
    local leash = Decisions().CFG.HOME_RADIUS
    local best, bestH, bestBody
    for _, other in ipairs(Routines.present(g)) do
        local m = g.members[other]
        if other ~= mid and m.npc ~= nil then
            local h = Decisions().healthOf(m)
            if h < Routines.CFG.CARE_HEALTH and (bestH == nil or h < bestH) then
                local z = B.find(m.npc)
                if z ~= nil and (home == nil or (math.floor(z:getZ()) == home.z
                    and Routines.cheb(z:getX(), z:getY(), home.x + 0.5, home.y + 0.5) <= leash)) then
                    best, bestH, bestBody = other, h, z
                end
            end
        end
    end
    return best, bestBody
end

Routines.registerChore({ id = "care", order = 70, gesture = "kneel",
    duty = { keeper = 1, carer = 6 },
    role = { heal = 3 },
    avail = function(c)
        local mid, body = Routines.woundedFor(c.g, c.ctx.mid, c.g.home)
        c.care = { mid = mid, body = body }
        return mid ~= nil
    end,
    plan = function(c)
        local mid, body = c.care.mid, c.care.body
        local cell = getCell()
        local wx, wy, wz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
        local p = cell ~= nil and Routines.exec.placeBeside(cell, wx, wy, wz, nil, {}) or nil
        if p == nil then return c.sit(Routines.CHORE_FALLBACK) end
        return c.place(p, nil, string.format("chore care %s %d,%d,%d", mid, p.x, p.y, p.z))
    end })
