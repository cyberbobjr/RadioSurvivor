--[[
rs.missions.solo - missions of the notebook played in a real solo game, without the bridge:
    E00-T10  a reward lot claimed by RS_Missions.claim (the real function, on an in-memory mission) is created by
             instanceItem and lands in the player's inventory; a second claim is refused.
    E00-T03  an offer of a real notebook fiche (Living Knox test npc) left unanswered expires (RS_Missions.advance on
             that mission only) and the notebook shows the translated "expired" state on its Missions page.
    E11-T11  a scout offer of a npc: no zone on the world map while it is an offer; "Accept" (the same 'accept'
             command as the notebook button) draws the circle named after the npc; "Abandon" removes it.
Tags "server" and "world" (test saves rstest* only), solo only (the notebook window and the map live on the client).
The npc tests place themselves: when no building fits around the player for a scout offer, the player is moved to the
nearest town centre and brought back at the end. Asynchronous run:
RST.run({ suite = "rs.missions.solo", tags = { "server", "world" } }).
Cleanup: reward items removed, test missions removed from the notebook state, npcs removed (RST.Fixtures).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_RSHelpers"

local F, R = RST.Fixtures, RST.RSHelpers
local REWARD, COUNT = "Base.Antibiotics", 2

local function ids(inv, fullType)
    local out = {}
    local list = inv:getItemsFromFullType(fullType)
    for i = 0, list:size() - 1 do out[list:get(i):getID()] = list:get(i) end
    return out
end

local function modules()
    return require "RadioSurvivor/RS_Missions", require "RadioSurvivor/RS_Config", require "RadioSurvivor/RS_MissionScout"
end

-- Projection of mission id in the client snapshot, or nil.
local function shown(id)
    for _, row in ipairs(RS_CarnetClient and RS_CarnetClient.snapshot.missions or {}) do
        if row.id == id then return row end
    end
    return nil
end

-- Zone symbols (colour signature of RS_MapActions) at the centre of the circle and over it.
local function zoneSymbols(z)
    local MapActions = require "RadioSurvivor/RS_MapActions"
    local api = MapActions.symbolsAPI()
    if api == nil then return nil end
    local c, tol, eps = MapActions.ZONE_COLOR, MapActions.ZONE_COLOR_TOLERANCE, 0.01
    local ring, text, label = 0, 0, nil
    for i = 0, api:getSymbolCount() - 1 do
        local sym = api:getSymbolByIndex(i)
        if sym and math.abs(sym:getAlpha() - c.a) < tol and math.abs(sym:getRed() - c.r) < tol then
            if sym:isTexture() and math.abs(sym:getWorldX() - z.x) < eps and math.abs(sym:getWorldY() - z.y) < eps then
                ring = ring + 1
            elseif sym:isText() and math.abs(sym:getWorldX() - z.x) < eps and math.abs(sym:getWorldY() - (z.y - z.r)) < eps then
                text = text + 1
                local ok, s = pcall(function() return sym:getTranslatedText() end)
                if ok then label = s end
            end
        end
    end
    return ring, text, label
end

-- npc next to the player (in a town if needed) with a scout offer made to the player's character; after(t, ctx).
local function scoutOffer(t, after)
    R.solo(t)
    local M, Config, Scout = modules()
    local Server = R.notebook(t)
    local p = F.player(t)
    t:ok(p ~= nil, "no target player")
    local cid = R.character(t, p)
    local c = Config.Missions.scout
    local function fits(pl)
        local x, y = pl:getX(), pl:getY()
        Scout.resetForTests()
        local probe = { id = "rst-scout-probe" }
        local body = { getX = function() return x end, getY = function() return y end }
        return Scout.offer(c, probe, nil, body)
    end
    R.place(t, p, fits, function(t2)
        R.god(t2, p)
        R.npcWithFiche(t2, p, 2, function(t3, id, fiche, body)
            Scout.resetForTests()
            local terms = Scout.offer(c, fiche, nil, body)
            t3:ok(terms ~= nil, "no scout offer for " .. id)
            local m = M.create(Server.store.data, fiche, cid, c.id, terms)
            t3:ok(m ~= nil and m.state == "offer", "scout offer not created")
            t3:defer(function()
                local data = Server.store.data
                data.missions[m.id] = nil
                data.outcomes[m.id .. "-" .. cid .. "-result"] = nil
                for _, record in pairs(data.characters) do record.knownMissions[m.id] = nil end
                if fiche.mission == m.id then fiche.mission = nil end
                Server.publish()
            end, "remove mission " .. m.id)
            Server.publish()
            return after(t3, { M = M, Config = Config, Server = Server, p = p, cid = cid, fiche = fiche, m = m })
        end)
    end)
end

RST.suite("rs.missions.solo", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 300000 }, function(s)
    s.test("reward lot claimed into the real inventory (instanceItem, E00-T10)", function(t)
        R.solo(t)
        local M = modules()
        local p = F.player(t)
        t:ok(p ~= nil, "no target player")
        local inv = p:getInventory()
        local before = ids(inv, REWARD)
        t:defer(function()
            for id, item in pairs(ids(inv, REWARD)) do
                if not before[id] then inv:Remove(item) end
            end
        end, "remove the reward items")
        local state = { missions = {}, npcs = {}, characters = { rst = { name = "RST" } }, outcomes = {} }
        local m = { id = "rst-reward-1", state = "success", revision = 3, participants = { rst = { name = "RST" } },
            claimedBy = "", rewardType = REWARD, rewardCount = COUNT, receipts = {} }
        state.missions[m.id] = m
        local store = { data = state, save = function() return true end }
        local ok, reason = M.claim(store, m, p, "rst", "rst-claim-1")
        t:eq(true, ok, "claim refused: " .. tostring(reason))
        local added = 0
        for id in pairs(ids(inv, REWARD)) do if not before[id] then added = added + 1 end end
        t:eq(COUNT, added, REWARD .. " items added to the inventory")
        t:eq("rst", m.claimedBy, "lot reserved")
        t:eq(nil, m.transaction, "transaction marker left")
        t:eq({ false, "State" }, { M.claim(store, m, p, "rst", "rst-claim-2") }, "second claim")
        t:note(added .. " x " .. REWARD .. " created by instanceItem")
    end)

    s.test("unanswered offer expires and the notebook shows it expired (E00-T03)", function(t)
        scoutOffer(t, function(t2, c)
            local m = c.m
            -- Only this mission ages: the other missions of the save keep their clocks.
            local only = { missions = { [m.id] = m }, npcs = c.Server.store.data.npcs,
                characters = c.Server.store.data.characters, outcomes = c.Server.store.data.outcomes }
            t2:eq(false, c.M.advance(only, c.Config.OFFER_TTL_MS - 1000), "offer expired too early")
            t2:eq(true, c.M.advance(only, 1000), "offer not expired after OFFER_TTL_MS")
            t2:eq("expired", m.state)
            t2:eq(nil, c.fiche.mission, "npc not released by the expiry")
            t2:ok(c.fiche.nextOfferAt ~= nil, "no delay before the next offer")
            c.Server.store.data.characters[c.cid].knownMissions[m.id] = true
            c.Server.publish()
            local row = shown(m.id)
            t2:ok(row ~= nil and row.state == "expired", "expired mission not in the notebook snapshot")
            local Notebook = require "RadioSurvivor/RS_Notebook"
            local Client = RS_CarnetClient
            local wasOpen = Client.window ~= nil and Client.window:isVisible()
            if not wasOpen then Notebook.toggle() end
            t2:defer(function()
                if not wasOpen and Client.window and Client.window:isVisible() then Notebook.toggle() end
            end, "close the notebook")
            local w = Client.window
            w:changeTab("Missions")
            w.selectedId = m.id
            w:refresh()
            local expected = getText("IGUI_RS_State_expired")
            t2:ne("IGUI_RS_State_expired", expected, "state not translated")
            t2:ok(string.find(w.detail.text or "", expected, 1, true) ~= nil,
                "Missions page without the expired state '" .. expected .. "'")
            t2:note("Missions page shows: " .. expected)
            -- Shown for the eye of the tester during the campaign (see the report).
            t2:sleep(3000, function(t3) t3:note("notebook left open 3 s on the expired offer") end)
        end)
    end)

    s.test("npc scout mission: zone only after Accept, removed after Abandon (E11-T11)", function(t)
        scoutOffer(t, function(t2, c)
            local m, Client = c.m, RS_CarnetClient
            local z = m.mapZone
            t2:ok(type(z) == "table", "no mapZone on the scout mission")
            local row = shown(m.id)
            t2:ok(row ~= nil and row.state == "offer", "offer not in the notebook snapshot")
            t2:eq(nil, row.mapZone, "zone sent with an offer")
            local ring = zoneSymbols(z)
            t2:ok(ring ~= nil, "no world map symbols API")
            t2:eq(0, ring, "zone drawn before the acceptance")
            Client.send("accept", { mission = m.id, revision = m.revision })
            t2:waitUntil(function()
                local r = shown(m.id)
                return r ~= nil and r.state == "active" and r.engaged
            end, 5000, function(t3)
                local ring2, text2, label = zoneSymbols(z)
                t3:eq(1, ring2, "zone circle after the acceptance")
                t3:eq(1, text2, "zone label after the acceptance")
                if label then
                    t3:ok(string.find(label, c.fiche.name, 1, true) ~= nil, "label without the npc name: " .. label)
                end
                t3:note("circle " .. z.x .. "," .. z.y .. " r " .. z.r .. ", label: " .. tostring(label))
                Client.send("abandon", { mission = m.id, revision = shown(m.id).revision })
                t3:waitUntil(function()
                    local r = shown(m.id)
                    return r ~= nil and r.state == "abandoned"
                end, 5000, function(t4)
                    local ring3, text3 = zoneSymbols(z)
                    t4:eq(0, ring3, "zone circle left after the abandon")
                    t4:eq(0, text3, "zone label left after the abandon")
                end, "mission not abandoned through the notebook command")
            end, "mission not accepted through the notebook command")
        end)
    end)
end)
