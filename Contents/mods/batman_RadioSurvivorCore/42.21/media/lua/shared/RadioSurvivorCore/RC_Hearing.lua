--[[
RadioSurvivorCore: who can talk to whom, for every mod that makes characters speak (E18-T18, moved from RS_NPCProvider,
same rules), and the personality derived from an identity. Plain functions on game objects, any side.

    Hearing.near(a, b, range) -> boolean       same floor, within range, seen
    Hearing.hears(source, listener, baseRange) -> boolean
    Hearing.personality(signature) -> table    fixed by the identity, nothing stored
]]
local Hearing = {}

function Hearing.near(a, b, range)
    if not a or not b or a:isDead() or b:isDead() or not a:getSquare() or not b:getSquare() then return false end
    if math.floor(a:getZ()) ~= math.floor(b:getZ()) then return false end
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    if dx * dx + dy * dy > range * range then return false end
    -- Prevent an exchange through an opaque wall; verified IsoGameCharacter.CanSee.
    return a:CanSee(b)
end

-- Conservative intelligible-speech policy based on ChatUtility.getScrambleValue.
-- No scrambled text is disclosed to a listener. Deaf/asleep/dead listeners get nothing.
function Hearing.hears(source, listener, baseRange)
    if not source or not listener or listener:isDead() or listener:isAsleep()
        or listener:hasTrait(CharacterTrait.DEAF) then return false end
    local sq, dest = source:getSquare(), listener:getSquare()
    if not sq or not dest then return false end
    local mod, force, display = 1, false, false
    local sb, db = sq:getBuilding(), dest:getBuilding()
    if db and sb and db == sb then
        if sq:getRoom() == dest:getRoom() then mod, display = 2, true
        elseif math.abs(listener:getZ() - source:getZ()) < 1 then mod = 2 end
    elseif db or sb then mod, force = 0.5, true end
    local dz = math.abs(listener:getZ() - source:getZ())
    if dz >= 1 then mod, force = mod - mod * dz * 0.25, true end
    local dx, dy = listener:getX() - source:getX(), listener:getY() - source:getY()
    local distance, range = math.sqrt(dx * dx + dy * dy), baseRange * mod
    return mod > 0 and distance < range and (display or (not force and distance < range * 0.6))
end

-- Personality fixed by the NPC identity, without storing anything: the same values are derived whenever the NPC is
-- first met. Park-Miller over a hash of the signature; Kahlua has no bitwise operators.
local STYLES = { "Prudent", "Direct", "Reserved", "Helpful" }
function Hearing.personality(signature)
    local m = 2147483647
    local x = 1
    for i = 1, #signature do x = (x * 31 + string.byte(signature, i)) % m end
    if x == 0 then x = 1 end
    local function draw(n)
        x = (x * 48271) % m
        return 1 + math.floor(x / m * n)
    end
    return { style = STYLES[draw(#STYLES)], courage = draw(5), sociability = draw(5), generosity = draw(5),
        values = "survival", motivation = "safety", fear = "isolation", loyalty = "current_group", schema = 1 }
end

return Hearing
