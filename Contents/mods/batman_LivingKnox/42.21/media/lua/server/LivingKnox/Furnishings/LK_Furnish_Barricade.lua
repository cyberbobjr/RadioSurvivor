-- Living Knox : aménagement « barricade » d'un foyer de bâtiment (LK08-T04, inscrit en LK16-T10) : planches sur
-- CFG.WINDOWS fenêtres fermées et non barricadées du bâtiment, côté extérieur, les plus éloignées du foyer d'abord
-- (CFG.PLANKS planches chacune), comme IsoWindow.addRandomBarricades (J/iso/objects/IsoWindow.java:1324-1343 : côté
-- sans pièce, addPlank(nil, nil), transmitCompleteItemToClients). Marque sur la fenêtre (ModData[TAG_SIDE] = côté de
-- la barricade) : la ModData d'une IsoBarricade n'est jamais sauvegardée (IsoBarricade.java:621-632). Retrait : la
-- barricade du groupe, la fenêtre reste. Moteur : LK_Homes.lua.
if isClient() then return end

require "LivingKnox/LK_Homes"

local Homes = LivingKnox.Homes

-- Barricade posée par le groupe sur la fenêtre marquée w (côté noté à la pose), ou nil.
function Homes.barricadeOf(w)
    if not instanceof(w, "IsoWindow") or not w:hasModData() then return nil end
    local side = w:getModData()[Homes.TAG_SIDE]
    if side == "opposite" then return w:getBarricadeOnOppositeSquare() end
    if side == "same" then return w:getBarricadeOnSameSquare() end
    return nil
end

-- Fenêtres : les plus éloignées du foyer d'abord (arrière de la maison).
local function plan(ctx, out)
    local windows = ctx.windows
    table.sort(windows, function(a, b)
        if a.d ~= b.d then return a.d > b.d end
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        if a.ny ~= b.ny then return a.ny < b.ny end
        return a.nx < b.nx
    end)
    for i = 1, math.min(ctx.cfg.WINDOWS, #windows) do
        local w = windows[i]
        out[#out + 1] = { k = "barricade", x = w.x, y = w.y, z = ctx.z, nx = w.nx, ny = w.ny }
    end
end

-- Barricade de planches côté extérieur de la fenêtre du bord (x, y) - (nx, ny).
local function place(gid, a, sq)
    local nb = getCell():getGridSquare(a.nx, a.ny, a.z)
    if nb == nil then return nil, "square not loaded" end
    local w = sq:getWindowTo(nb)
    if w == nil or not instanceof(w, "IsoWindow") then return nil, "no window" end
    if w:IsOpen() or w:isBarricaded() then return nil, "window open or barricaded" end
    local wsq = w:getSquare()
    local outside = wsq:getRoom() == nil and wsq or w:getOppositeSquare()
    if outside == nil or outside:getRoom() ~= nil then return nil, "no outside square" end
    local b = IsoBarricade.AddBarricadeToObject(w, outside ~= wsq)
    if b == nil then return nil, "barricade refused" end
    if b:getNumPlanks() > 0 or b:isMetal() or b:isMetalBar() then return nil, "already barricaded" end
    for _ = 1, Homes.CFG.PLANKS do b:addPlank(nil, nil) end
    -- Marque sur la fenêtre, pas sur la barricade : IsoBarricade.save n'écrit pas la ModData (perdue au redémarrage,
    -- J/iso/objects/IsoBarricade.java:621-632), IsoWindow.save si (IsoWindow.java:547-548). Côté de la barricade noté.
    Homes.tagObject(w, gid, "barricade")
    w:getModData()[Homes.TAG_SIDE] = outside ~= wsq and "opposite" or "same"
    if isServer() then b:transmitCompleteItemToClients() end
    return true
end

-- Retrait : fenêtre barricadée gardée pour finish (sa barricade retirée, la fenêtre reste).
local function collect(o)
    if instanceof(o, "IsoWindow") then return o end
    return nil
end

local function finish(windows)
    local removed = 0
    for _, w in ipairs(windows) do
        local b = Homes.barricadeOf(w)
        local bsq = b and b:getSquare()
        if bsq ~= nil then
            bsq:transmitRemoveItemFromSquare(b)
            removed = removed + 1
        end
        local md = w:getModData()
        md[Homes.TAG], md[Homes.TAG_KIND], md[Homes.TAG_SIDE] = nil, nil, nil
    end
    return removed
end

Homes.registerFurnishing("barricade", { style = "building", order = 10, plan = plan, place = place,
    clear = { collect = collect, finish = finish } })
