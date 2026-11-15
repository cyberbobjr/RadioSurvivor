-- Radio Survivor: where a trader looks for the payment and puts the goods at the landing (E20-T11, ADR D07/D08).
-- An arrival mode names its finder in its `holds` field (RS_TradeArrivals; bags when left out). A finder is
-- function(cx, cy, z, r) -> list of holds { inv = ItemContainer, id = number or text (log, detail of the run) } in
-- the square of side 2r + 1 centred on (cx, cy, z), or nil when the centre square is not loaded. Registered here:
--   bags        bags put on the floor (IsoWorldInventoryObject holding an InventoryContainer item), id = item id
--   containers  containers of the objects of the squares (IsoObject.getContainerCount / getContainerByIndex, 42.22
--               IsoObject.java:4845-4851): a dumpster, a mailbox, a crate...; id = "x,y,z:object:index"
-- Another finder is added by Holds.register without touching the exchange (RS_TradeExchange).
-- Authority only. ASCII only (Kahlua lexer).
if isClient() then return end

local Holds = {}

local registry = {}

-- Registers a finder; returns false when the name or the function is bad.
function Holds.register(name, finder)
    if type(name) ~= "string" or not string.match(name, "^[a-z][a-z0-9_]*$") or type(finder) ~= "function" then
        print("[RadioSurvivor] ERROR trade hold finder refused: bad name or function")
        return false
    end
    registry[name] = finder
    return true
end

-- Finder registered under this name, or nil.
function Holds.get(name)
    return registry[name]
end

-- Calls each(sq, x, y) on every loaded square of the area; false when the centre square is not loaded.
local function eachSquare(cx, cy, z, r, each)
    local cell = getCell and getCell() or nil
    if cell == nil or cell:getGridSquare(cx, cy, z) == nil then return false end
    for x = cx - r, cx + r do
        for y = cy - r, cy + r do
            local sq = cell:getGridSquare(x, y, z)
            if sq then each(sq, x, y) end
        end
    end
    return true
end

local function bags(cx, cy, z, r)
    local out = {}
    local function each(sq)
        local wos = sq:getWorldObjects()
        for i = 0, (wos and wos:size() or 0) - 1 do
            local wo = wos:get(i)
            local item = wo and wo:getItem() or nil
            if item and instanceof(item, "InventoryContainer") then
                out[#out + 1] = { inv = item:getInventory(), id = item:getID() }
            end
        end
    end
    if not eachSquare(cx, cy, z, r, each) then return nil end
    return out
end

local function containers(cx, cy, z, r)
    local out = {}
    local function each(sq, x, y)
        local objects = sq:getObjects()
        for i = 0, (objects and objects:size() or 0) - 1 do
            local o = objects:get(i)
            for n = 0, (o and o:getContainerCount() or 0) - 1 do
                local c = o:getContainerByIndex(n)
                if c then out[#out + 1] = { inv = c, id = x .. "," .. y .. "," .. z .. ":" .. i .. ":" .. n } end
            end
        end
    end
    if not eachSquare(cx, cy, z, r, each) then return nil end
    return out
end

Holds.register("bags", bags)
Holds.register("containers", containers)

return Holds
