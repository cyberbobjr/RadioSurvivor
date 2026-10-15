--[[
RST_GunSwap - a minimal "firearm overhaul" for the in-game tests (RST.GunSwap, LK07-T07). Development mod only. Load
with: require "RST/RST_GunSwap". No side effect at load time: the swap exists only between enable(t) and the end of
that test.

What a firearm overhaul does to a vanilla gun (base pz-knowledge loot-distributions.md, "Objet pose par script qui
disparait ou change de type apres coup"): it sets the OnCreate of the vanilla item script (Item.setLuaCreate), notes
every item created, and at a later tick, once the item left a living inventory, replaces it in its container by its
own type (AddItem of the new one, DoRemoveItem of the old one) and in the attachment slot it occupied. This file does
exactly that for one type, on the authority only (solo or server; MP: sendAddItemToContainer and
sendRemoveItemFromContainer):
    RST.GunSwap.enable(t[, from, to])   sets the creation hook of the script from (default FROM, Base.Pistol) to the
                                        global RSTGunSwap_OnCreate until the end of the test t (t:defer puts the former
                                        OnCreate back, the swap off, pending items forgotten); items created meanwhile
                                        are swapped for to (default TO, RSTGuns.TestPistol of RST_TestGuns.txt) when
                                        they sit in the container of a corpse (IsoDeadBody), at the next OnTick.
    RST.GunSwap.stats                   { created, swapped, attached } since the last enable.
    RST.GunSwap.active()                true while enabled.
A pending item never seen in a corpse within PENDING_MS is forgotten (it stays vanilla).
]]

require "RST/RST"

RST.GunSwap = RST.GunSwap or {}
local G = RST.GunSwap

G.FROM = "Base.Pistol"
G.TO = "RSTGuns.TestPistol"
G.HOOK = "RSTGunSwap_OnCreate"
G.PENDING_MS = 120000
G.pending = G.pending or {}
G.stats = G.stats or { created = 0, swapped = 0, attached = 0 }

local function log(msg) print("[RST] gunswap: " .. tostring(msg)) end
local function now() return getTimestampMs() end

function G.active() return G.on == true end

-- Corpse holding the container c, or nil.
local function corpseOf(c)
    local parent = c ~= nil and c:getParent() or nil
    if parent ~= nil and instanceof(parent, "IsoDeadBody") then return parent end
    return nil
end

-- "type#id" of an item (id left out where the item has none).
local function label(item)
    local okT, ty = pcall(function() return item:getFullType() end)
    local okI, id = pcall(function() return item:getID() end)
    return tostring(okT and ty or "?") .. "#" .. tostring(okI and id or "?")
end

-- Replaces item (in the container c of the corpse body) by a new G.to item: container, then attachment slot.
local function swap(item, c, body)
    local new = instanceItem(G.to or G.TO)
    if new == nil then
        log("ERROR: " .. tostring(G.to) .. " is not a known item")
        return false
    end
    c:AddItem(new)
    if isServer() then sendAddItemToContainer(c, new) end
    local ok, loc = pcall(function()
        local att = body:getAttachedItems()
        return att and att:getLocation(item) or nil
    end)
    if ok and loc ~= nil then
        local set = pcall(function() body:getAttachedItems():setItem(loc, new) end)
        if set then G.stats.attached = G.stats.attached + 1 end
    end
    c:DoRemoveItem(item)
    if isServer() then sendRemoveItemFromContainer(c, item) end
    G.stats.swapped = G.stats.swapped + 1
    log(label(item) .. " swapped for " .. label(new) .. " in a corpse"
        .. (loc ~= nil and (" (slot " .. tostring(loc) .. ")") or ""))
    return true
end

local function onTick()
    if not G.on then return end
    local keep = {}
    local t = now()
    for _, e in ipairs(G.pending) do
        local c = e.item:getContainer()
        local body = corpseOf(c)
        if body ~= nil then
            swap(e.item, c, body)
        elseif t - e.ms < G.PENDING_MS then
            keep[#keep + 1] = e
        end
    end
    G.pending = keep
end

-- OnCreate of the hooked script (called by InventoryItem.initialiseItem for every new item of that type).
function RSTGunSwap_OnCreate(item)
    if not G.on or item == nil then return end
    G.stats.created = G.stats.created + 1
    G.pending[#G.pending + 1] = { item = item, ms = now() }
end

function G.enable(t, from, to)
    if type(isClient) == "function" and isClient() then error("RST.GunSwap: authority only (solo or server)", 0) end
    from, to = from or G.FROM, to or G.TO
    local script = getScriptManager():FindItem(from)
    if script == nil then error("RST.GunSwap: unknown item " .. tostring(from), 0) end
    if getScriptManager():FindItem(to) == nil then error("RST.GunSwap: unknown item " .. tostring(to), 0) end
    local was = script:getLuaCreate()
    script:setLuaCreate(G.HOOK)
    G.on, G.to, G.pending = true, to, {}
    G.stats = { created = 0, swapped = 0, attached = 0 }
    if not G._ticking then
        Events.OnTick.Add(onTick)
        G._ticking = true
    end
    log("on: " .. from .. " -> " .. to .. " (former OnCreate " .. tostring(was) .. ")")
    t:defer(function()
        script:setLuaCreate(was)
        G.on, G.pending = false, {}
        log("off: OnCreate of " .. from .. " back to " .. tostring(was))
    end, "firearm swap of " .. from .. " off")
end

return G
