--[[
CoreAI: approximate areas of the missions on the player's world map (E11-T10; moved to the core mod by E21-T03), and the
world map symbols API shared with the mods that mark the map.

Symbols API: the symbols of the world map (WorldMapSymbols of MapItem.getSingleton(), the player's annotations), reached
through a hidden UIWorldMap created once per game and never added to the interface (as ISWorldMap:getStashMapBounds,
client/ISUI/Maps/ISWorldMap.lua:643-645): setMapItem(MapItem.getSingleton()) then getSymbolsAPIv2(). Each
WorldMapSymbolsV2 adds a permanent listener to the symbols (WorldMapSymbolsV2.java:54-59): one API per MapItem only.
MapItem.Reset() (back to the menu) replaces the singleton: a new game creates the API again.
Private symbols (no network share), saved in map_symbols.bin of the current save on the client, in solo as on an MP
client (WorldMapSymbols.save; MapItem.SaveWorldMap called by GameWindow.save) and read back when the world loads, before
OnGameStart (MapItem.LoadWorldMap, never on a server).

Zones: the server sends them only in the notebook snapshot (field mapZone { x, y, r } of an active mission the player
takes part in); never the position of the building. Drawing: vanilla symbol "Circle" (map_o.png, ring drawn by hand)
centred on (x, y), scaled so that its ring has a radius of r squares: with applyZoom (true by default), the size shown is
width x scale x worldScale pixels, worldScale = pixels per square (WorldMapBaseSymbol.getDisplayScale,
WorldMapRenderer.getWorldScale: 1 / metersPerPixel); an icon defined without a size is 20 wide
(MapSymbolDefinitions.addTexture) and the ring takes about 50 of the 64 pixels of the texture. Translated label
(IGUI_CA_MapZone<style>, name of the requester) above the ring. On the mini map the scale is ignored
(min(worldScale, 1)): small circle only.
Zone symbols are recognised by their orange colour and alpha 0.8, never set by the vanilla interface (alpha 1.0 for its
icons, ISWorldMapSymbols.lua:138, 432, 469); the alpha is saved on one byte (WorldMapBaseSymbol.save), hence the
tolerance. On each snapshot, the zone symbols that no longer match an active mission of the player are removed (end,
abandon, expiry, purged mission, other character), also when the end happened while the player was disconnected; the
missing zones are drawn once per session (a zone erased by the player comes back at the next load while the mission
lasts).

    symbolsAPI() -> WorldMapSymbolsV2 or nil    API of the current game (nil without a world map)
    near(symbol, x, y) -> boolean               symbol at (x, y), within EPSILON squares
    cleanLabel(label) -> text                   label on one line, without markup, at most LABEL_MAX bytes
    zones(missions) -> { added, removed } | nil, 'no_map'   the player's map matched to the snapshot missions
]]
if isServer() then return end

local TextCut = require "CoreAI/CA_TextCut"

local Zones = {}

-- Scale of the player's notes (ISMap.SCALE, client/ISUI/Maps/ISMap.lua:16).
Zones.SCALE = 0.666
-- Gap allowed (squares) when comparing two symbol positions (Java floats).
Zones.EPSILON = 0.01
Zones.LABEL_MAX = 48

Zones.ZONE_ICON = "Circle"
Zones.ZONE_COLOR = { r = 0.85, g = 0.40, b = 0.05, a = 0.8 }
-- Diameter of the ring of "Circle" at scale 1, in squares (20 units, ring over ~50/64 of the texture).
Zones.ZONE_RING = 20 * 50 / 64
-- Colours saved on one byte: within 1/255.
Zones.ZONE_COLOR_TOLERANCE = 0.02

-- { item = MapItem of the world, api = WorldMapSymbolsV2 }: one API per MapItem.
local cache = { item = nil, api = nil, ui = nil }
-- Zones already handled during this session (key mission@x,y,r): drawn once per session.
local zonesDone = {}

function Zones.resetForTests()
    cache = { item = nil, api = nil, ui = nil }
end

function Zones.resetZonesForTests()
    zonesDone = {}
end

function Zones.symbolsAPI()
    if MapItem == nil or UIWorldMap == nil then return nil end
    local item = MapItem.getSingleton()
    if item == nil then return nil end
    if cache.api == nil or cache.item ~= item then
        local ui = {}
        ui.javaObject = UIWorldMap.new(ui)
        local mapAPI = ui.javaObject:getAPIv3()
        mapAPI:setMapItem(item)
        cache = { item = item, api = mapAPI:getSymbolsAPIv2(), ui = ui }
    end
    return cache.api
end

function Zones.near(symbol, x, y)
    return math.abs(symbol:getWorldX() - x) < Zones.EPSILON and math.abs(symbol:getWorldY() - y) < Zones.EPSILON
end

-- Label on one line, without markup, bounded (the sheets already bound it to 48 UTF-8 bytes).
function Zones.cleanLabel(label)
    local text = TextCut.oneLine(string.gsub(tostring(label or ""), "[%c<>%[%]]", " "))
    if string.len(text) > Zones.LABEL_MAX then text = string.sub(text, 1, Zones.LABEL_MAX) end
    return text
end

function Zones.zoneScale(r)
    return 2 * r / Zones.ZONE_RING
end

-- Symbol drawn for a mission zone (colour and alpha signature).
local function isZoneSymbol(symbol)
    local c, tol = Zones.ZONE_COLOR, Zones.ZONE_COLOR_TOLERANCE
    return math.abs(symbol:getAlpha() - c.a) < tol and math.abs(symbol:getRed() - c.r) < tol
        and math.abs(symbol:getGreen() - c.g) < tol and math.abs(symbol:getBlue() - c.b) < tol
end

local function paintZone(symbol, anchorY, scale)
    local c = Zones.ZONE_COLOR
    symbol:setRGBA(c.r, c.g, c.b, c.a)
    symbol:setAnchor(0.5, anchorY)
    symbol:setScale(scale)
end

local function isCircle(z)
    return type(z) == "table" and type(z.x) == "number" and type(z.y) == "number" and type(z.r) == "number"
        and z.r > 0
end

local function addCircle(out, id, z, name, style)
    if isCircle(z) then out[#out + 1] = { id = id, x = z.x, y = z.y, r = z.r, name = name, style = style } end
end

-- Wanted zones: active missions of the snapshot the player takes part in that carry mapZone.
local function wantedZones(missions)
    local out = {}
    for _, p in ipairs(type(missions) == "table" and missions or {}) do
        if type(p) == "table" and p.state == "active" and p.engaged then
            local id = tostring(p.id)
            -- E20-T01: label style declared by the template (CA_Missions, mapStyle), projected by the engine.
            local style = type(p.mapStyle) == "string" and p.mapStyle or nil
            addCircle(out, id, p.mapZone, p.requester, style)
            -- E11-T06: depot circle of a recover mission, drawn next to its search area.
            addCircle(out, id .. ":depot", p.depotZone, p.requester, "Depot")
            -- E20-T05: one circle per drop point of the mission, labelled with its place label.
            for i, drop in ipairs(type(p.dropZones) == "table" and p.dropZones or {}) do
                addCircle(out, id .. ":drop" .. i, drop, type(drop) == "table" and drop.label or nil, "Depot")
            end
            -- E20-T13: several circles of the template itself (route: one per known point), each with its place
            -- label, in the template's style.
            for i, zone in ipairs(type(p.mapZones) == "table" and p.mapZones or {}) do
                addCircle(out, id .. ":zone" .. i, zone, type(zone) == "table" and zone.label or nil, style)
            end
        end
    end
    return out
end

-- Label of a zone: IGUI_CA_MapZone followed by the style the template declares (E20-T01: Search for retrieve_id,
-- Clear, Cache for recover, Signal) or Depot for the depot circle of recover and the drop points (E20-T05: with the
-- place label); none: the plain label. The symbols are matched by position only.
local function zoneLabel(z)
    local name = Zones.cleanLabel(z.name)
    local key = "IGUI_CA_MapZone" .. (z.style or "")
    if name == "" then return Zones.cleanLabel(getText(key .. "Anon")) end
    return Zones.cleanLabel(getText(key, name))
end

-- Matches the player's map to the missions of the notebook snapshot. Returns { added = n, removed = n } or nil and the
-- reason ("no_map").
function Zones.zones(missions)
    local wanted = wantedZones(missions)
    local api = Zones.symbolsAPI()
    if api == nil then return nil, "no_map" end
    local hasRing, hasText, removed = {}, {}, 0
    for i = api:getSymbolCount() - 1, 0, -1 do
        local symbol = api:getSymbolByIndex(i)
        if symbol and isZoneSymbol(symbol) then
            local kept = false
            for _, z in ipairs(wanted) do
                if symbol:isTexture() and symbol:getSymbolID() == Zones.ZONE_ICON and Zones.near(symbol, z.x, z.y) then
                    kept, hasRing[z] = true, true
                elseif symbol:isText() and Zones.near(symbol, z.x, z.y - z.r) then
                    kept, hasText[z] = true, true
                end
            end
            if not kept then
                api:removeSymbolByIndex(i)
                removed = removed + 1
            end
        end
    end
    local added = 0
    for _, z in ipairs(wanted) do
        local key = z.id .. "@" .. z.x .. "," .. z.y .. "," .. z.r
        if not zonesDone[key] then
            zonesDone[key] = true
            if not hasRing[z] then
                paintZone(api:addTexture(Zones.ZONE_ICON, z.x, z.y), 0.5, Zones.zoneScale(z.r))
                added = added + 1
            end
            local text = zoneLabel(z)
            if not hasText[z] and text ~= "" then
                paintZone(api:addTranslatedText(text, api:getDefaultTextLayerID(), z.x, z.y - z.r), 1.0, Zones.SCALE)
                added = added + 1
            end
        end
    end
    return { added = added, removed = removed }
end

return Zones
