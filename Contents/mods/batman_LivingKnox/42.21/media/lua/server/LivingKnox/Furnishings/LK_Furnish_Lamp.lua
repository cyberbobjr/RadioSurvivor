-- Living Knox : aménagement « lamp » d'un foyer de bâtiment (LK08-T04, inscrit en LK16-T10) : une lampe sur pile
-- allumée (lumière visible de l'extérieur sans courant) sur la case libre la plus proche du foyer. Lampe
-- lighting_indoor_03_4 « Grey Lamp » (newtiledefinitions.tiles.txt 42.21 : lightswitch, LightRadius 12, une case) :
-- objet Moveable réglé sur pile (setLightUseBattery, setLightHasBattery, setLightPower) relu par
-- IsoLightSwitch.getCustomSettingsFromItem (J/iso/objects/IsoLightSwitch.java:531-543), puis switchLight(true) (la
-- source de lumière créée avant la pile reste éteinte, :104-116, 457-476). Moteur : LK_Homes.lua.
if isClient() then return end

require "LivingKnox/LK_Homes"

local Homes = LivingKnox.Homes

local function plan(ctx, out)
    for _, s in ipairs(ctx.inside) do
        if ctx.fits(s.x, s.y, 1, 1) then
            out[#out + 1] = { k = "lamp", x = s.x, y = s.y, z = ctx.z, v = "lamp" }
            ctx.reserve(s.x, s.y, 1, 1)
            return
        end
    end
end

local function lampItem(item)
    if not instanceof(item, "Moveable") then return end
    item:setLightUseBattery(true)
    item:setLightHasBattery(true)
    item:setLightPower(Homes.CFG.LAMP_POWER)
end

local function lightLamp(gid, sq)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoLightSwitch") and Homes.isTagged(o, gid) then
            o:switchLight(true)
            return true
        end
    end
    return false
end

local function place(gid, a, sq)
    local ok, why = Homes.placeFurniture(gid, a, sq, lampItem)
    if not ok then return nil, why end
    if not lightLamp(gid, sq) then return nil, "lamp not found after placement" end
    return true
end

Homes.registerFurnishing("lamp", { style = "building", order = 20, plan = plan, place = place,
    furniture = { lamp = { sprite = "lighting_indoor_03_4", w = 1, h = 1 } } })
