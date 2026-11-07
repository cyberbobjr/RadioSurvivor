--[[
RadioSurvivorCore: mission catalogue, caches and mission delays of the common mission engine (E18-T05, moved from the
RadioSurvivor configuration; values unchanged). Read by RC_Missions, its templates and RC_Caches; RadioSurvivor's
RS_Config points at the same tables (one copy). Loaded on every machine (media/lua/shared).
]]
local MC = {
    -- E11-T20: OFFER_TTL_MS, OFFER_COOLDOWN_MS and the durationMs of the missions are play ms (RC_GameClock: real ms
    -- at normal speed, stopped while the game is paused, faster at x2/x3); the retentions below stay real time.
    OFFER_TTL_MS = 3600000,            -- play time before an unaccepted offer expires
    OFFER_COOLDOWN_MS = 1800000,       -- play time before the same NPC or voice can offer again
    -- E11-T06: offers sent to the bridge in one npc_talk request, at most (RC_Missions.offers keeps the first ones in
    -- template registration order and does not ask the templates after the cap: no place drawn for an offer that is
    -- not sent). Same value as MAX_OFFERS in bridge/npc_protocol.py, which rejects a larger catalog.
    MAX_OFFERS = 6,
    -- Squares between a player and the requester's body for a hand-over or a claim (deliver, claim: notebook of
    -- RadioSurvivor and journal of the core mod, E18-T29).
    DELIVERY_RANGE = 3,
    MISSION_RETENTION_MS = 86400000,   -- closed missions kept 24 h for the notebook
    -- Successful but unclaimed lot kept 7 game days (168 game hours of world age, stopped while paused: user decision
    -- of 2026-10-21). UNCLAIMED_RETENTION_MS (7 real days) only converts a lot saved before that decision.
    UNCLAIMED_RETENTION_HOURS = 168,
    UNCLAIMED_RETENTION_MS = 604800000,
    -- Mission catalogue, one entry per template of RC_Missions (E11-T02). `id` is the offer id seen by the bridge;
    -- durationMs (play ms, E11-T20), rewardType and rewardCount are read by the engine, the other fields by the
    -- template.
    Missions = {
        -- M01: first-aid delivery.
        deliver = {
            id = 'first_aid_v1',
            titleKey = 'IGUI_RC_Mission_FirstAid',
            quantity = 6,
            durationMs = 7200000,
            accepted = {['Base.Bandage'] = true, ['Base.RippedSheets'] = true},
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
        },
        -- E11-T03: reach a building drawn by the server, then report to the requester in person
        -- (server/RadioSurvivorCore/RC_MissionScout.lua). Delay and reward of M01 (decisions E11-T01).
        scout = {
            id = 'scout_v1',
            titleKey = 'IGUI_RC_Mission_Scout',
            durationMs = 7200000,
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
            minDistance = 60,     -- tiles between the building and the requester, and any known base
            maxDistance = 250,    -- tiles at most between the building and the requester
            maxAttempts = 40,     -- buildings examined per draw
            margin = 2,           -- tiles around the building footprint that count as the zone
            mapZoneRadius = 30,   -- E11-T10: radius (tiles) of the approximate area drawn on the player's map
            siteTtlMs = 600000,   -- a drawn place is kept for the requester's offers during 10 min
            retryMs = 60000,      -- no place found: next draw after 1 min
        },
        -- E11-T05: find a body in a building drawn by the server and bring its ID card back to the requester
        -- (server/RadioSurvivorCore/RC_MissionRetrieve.lua). Place, area, delay and reward as `scout`.
        retrieve_id = {
            id = 'retrieve_id_v1',
            titleKey = 'IGUI_RC_Mission_Retrieve',
            durationMs = 7200000,
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
            minDistance = 60,
            maxDistance = 250,
            maxAttempts = 40,
            mapZoneRadius = 30,
            siteTtlMs = 600000,
            retryMs = 60000,
            cardType = 'Base.IDcard',  -- card put in the body, named after it (nameAfterDescriptor)
            -- identity cards listed by the delivery window; only the mission's card (by item id) is accepted
            cards = {['Base.IDcard'] = true, ['Base.IDcard_Male'] = true, ['Base.IDcard_Female'] = true,
                ['Base.IDcard_Stolen'] = true},
            blood = 2,             -- blood passes of RandomizedWorldBase.createRandomDeadBody
            placeRetryMs = 5000,   -- placement attempts of one mission at most this often (site square loaded)
        },
        -- E11-T04: kill N zombies inside a circle drawn around a building chosen by the server
        -- (server/RadioSurvivorCore/RC_MissionClear.lua). Place, delay and reward as `scout`; N from the zone density.
        clear = {
            id = 'clear_v1',
            titleKey = 'IGUI_RC_Mission_Clear',
            durationMs = 7200000,
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
            minDistance = 60,
            maxDistance = 250,
            maxAttempts = 40,
            siteTtlMs = 600000,
            retryMs = 60000,
            zoneRadius = 30,       -- tiles: radius of the counting circle drawn on the map (centred on the building)
            zoneMargin = 5,        -- tiles kept between the building corners and the circle of a big building
            minKills = 6,          -- N at the lowest admitted density
            maxKills = 25,         -- N at fullDensity and above
            fullDensity = 0.5,     -- density (mean lot header intensity / 255 x PopulationMultiplier) giving maxKills
            minDensity = 0.04,     -- below: no offer (too few zombies around the place)
        },
        -- E11-T06: pick up a cache (marked bag) placed in a building drawn by the server and carry it to the depot of
        -- the requester's group (server/RadioSurvivorCore/RC_MissionRecover.lua). Place, area, delay and reward as `scout`.
        recover = {
            id = 'recover_v1',
            titleKey = 'IGUI_RC_Mission_Recover',
            durationMs = 7200000,
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
            minDistance = 60,
            maxDistance = 250,
            maxAttempts = 40,
            mapZoneRadius = 30,
            siteTtlMs = 600000,
            retryMs = 60000,
            depotRadius = 3,       -- tiles (square of side 2r+1 around the home point, same floor): the depot area
        },
        -- E11-T07: light a signal of the asked colour inside a circle around a building chosen by the server, within
        -- a window of game hours (server/RadioSurvivorCore/RC_MissionSignal.lua), with the required mod Signal Smoke.
        -- Place, delay and reward as `scout`.
        signal = {
            id = 'signal_v1',
            titleKey = 'IGUI_RC_Mission_Signal',
            durationMs = 7200000,
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
            minDistance = 60,
            maxDistance = 250,
            maxAttempts = 40,
            siteTtlMs = 600000,
            retryMs = 60000,
            zoneRadius = 20,       -- tiles: radius of the circle where the signal must be lit (centred on the building)
            zoneMargin = 5,        -- tiles kept between the building corners and the circle of a big building
            colors = {'green', 'red', 'yellow', 'purple'},  -- names of SignalSmoke.COLORS (smoke grenade colours)
            leadHours = 2,         -- game hours at least between the draw and the start of the window
            spreadHours = 2,       -- start drawn up to this many game hours later
            windowHours = 2,       -- game hours of the window, valid on any day while the mission is active
        },
    },
    -- E11-T06: caches (server/RadioSurvivorCore/RC_Caches.lua): a marked bag filled from one closed table of the server,
    -- placed once in the world when its site is loaded. `order` is the closed list (and the draw order) of the tables.
    Caches = {
        bagType = 'Base.Bag_DuffelBag',
        placeRetryMs = 5000,   -- placement attempts of one cache at most this often (site square loaded)
        order = {'food', 'medical', 'ammo', 'tools', 'radio'},
        tables = {
            food = {{'Base.TinnedBeans', 2}, {'Base.TinnedSoup', 2}, {'Base.CannedCorn', 1}},
            medical = {{'Base.Bandage', 4}, {'Base.Disinfectant', 1}, {'Base.Pills', 1}},
            ammo = {{'Base.Bullets9mm', 20}, {'Base.ShotgunShells', 8}},
            radio = {{'Base.WalkieTalkie2', 1}, {'Base.Battery', 2}},
            tools = {{'Base.Hammer', 1}, {'Base.Screwdriver', 1}, {'Base.Nails', 10}},
        },
    },
}

return MC
