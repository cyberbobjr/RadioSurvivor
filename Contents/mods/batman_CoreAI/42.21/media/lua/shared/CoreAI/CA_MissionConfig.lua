--[[
CoreAI: mission catalogue, caches and mission delays of the common mission engine (E18-T05, moved from a
mod's configuration; values unchanged). Read by CA_Missions, its templates and CA_Caches; a mod's
configuration may point at the same tables (one copy). Loaded on every machine (media/lua/shared).
]]
local MC = {
    -- E11-T20: OFFER_TTL_MS, OFFER_COOLDOWN_MS and the durationMs of the missions are play ms (CA_GameClock: real ms
    -- at normal speed, stopped while the game is paused, faster at x2/x3); the retentions below stay real time.
    OFFER_TTL_MS = 3600000,            -- play time before an unaccepted offer expires
    OFFER_COOLDOWN_MS = 1800000,       -- play time before the same NPC or voice can offer again
    -- E11-T06: offers sent to the bridge in one npc_talk request, at most (CA_Missions.offers keeps the first ones in
    -- template registration order and does not ask the templates after the cap: no place drawn for an offer that is
    -- not sent). Same value as MAX_OFFERS in bridge/npc_protocol.py, which rejects a larger catalog.
    MAX_OFFERS = 6,
    -- Squares between a player and the requester's body for a hand-over or a claim (deliver, claim: notebook and
    -- journal of the core mod, E18-T29).
    DELIVERY_RANGE = 3,
    MISSION_RETENTION_MS = 86400000,   -- closed missions kept 24 h for the notebook
    -- Successful but unclaimed lot kept 7 game days (168 game hours of world age, stopped while paused: user decision
    -- of 2026-10-21). UNCLAIMED_RETENTION_MS (7 real days) only converts a lot saved before that decision.
    UNCLAIMED_RETENTION_HOURS = 168,
    UNCLAIMED_RETENTION_MS = 604800000,
    -- E23-T02: notice of a mission lost with a dead character, shown to the account's next character for 7 game days
    -- (game hours of world age); at most LOST_NOTICE_MAX notices kept per account.
    LOST_NOTICE_HOURS = 168,
    LOST_NOTICE_MAX = 8,
    -- Mission catalogue, one entry per template of CA_Missions (E11-T02). `id` is the offer id seen by the bridge;
    -- durationMs (play ms, E11-T20), rewardType and rewardCount are read by the engine, the other fields by the
    -- template.
    Missions = {
        -- M01: first-aid delivery.
        deliver = {
            id = 'first_aid_v1',
            titleKey = 'IGUI_CA_Mission_FirstAid',
            quantity = 6,
            durationMs = 7200000,
            accepted = {['Base.Bandage'] = true, ['Base.RippedSheets'] = true},
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
        },
        -- E11-T03: reach a building drawn by the server, then report to the requester in person
        -- (server/CoreAI/CA_MissionScout.lua). Delay and reward of M01 (decisions E11-T01).
        scout = {
            id = 'scout_v1',
            titleKey = 'IGUI_CA_Mission_Scout',
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
        -- (server/CoreAI/CA_MissionRetrieve.lua). Place, area, delay and reward as `scout`.
        retrieve_id = {
            id = 'retrieve_id_v1',
            titleKey = 'IGUI_CA_Mission_Retrieve',
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
        -- (server/CoreAI/CA_MissionClear.lua). Place, delay and reward as `scout`; N from the zone density.
        clear = {
            id = 'clear_v1',
            titleKey = 'IGUI_CA_Mission_Clear',
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
        -- the requester's group (server/CoreAI/CA_MissionRecover.lua). Place, area, delay and reward as `scout`.
        recover = {
            id = 'recover_v1',
            titleKey = 'IGUI_CA_Mission_Recover',
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
        -- a window of game hours (server/CoreAI/CA_MissionSignal.lua), with the required mod Signal Smoke.
        -- Place, delay and reward as `scout`.
        signal = {
            id = 'signal_v1',
            titleKey = 'IGUI_CA_Mission_Signal',
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
        -- E20-T09: barricade `count` outside windows and doors of the building at a place of the voice sheet
        -- (server/CoreAI/CA_MissionBarricade.lua). Given by a radio voice only (no reward lot: the voice
        -- pays); count from the sheet section (parameter count), else the default below.
        barricade = {
            id = 'barricade_v1',
            titleKey = 'IGUI_CA_Mission_Barricade',
            durationMs = 14400000, -- barricading takes longer than a visit: twice the delay of `scout`
            rewardType = '',
            rewardCount = 0,
            count = 4,             -- openings to barricade when the section sets no count
            zoneRadius = 8,        -- tiles: smallest circle drawn on the map around the building
            zoneMargin = 3,        -- tiles kept between the building corners and the circle
            scanMs = 3000,         -- real ms between two server reads of the building's openings
        },
        -- E20-T12: a powered two-way radio turned on high at a place of the voice sheet
        -- (server/CoreAI/CA_MissionRelay.lua). Given by a radio voice only (no reward lot: the voice pays).
        relay = {
            id = 'relay_v1',
            titleKey = 'IGUI_CA_Mission_Relay',
            durationMs = 14400000, -- a radio and a way up to find: the delay of `barricade`
            rewardType = '',
            rewardCount = 0,
            minZ = 1,              -- lowest level of the radio (0 = ground), raised to the level of a high place
            zoneHalf = 6,          -- tiles around a place outside any building (square zone of 13 x 13 tiles)
            zoneLevels = 4,        -- levels of that zone, from the lowest one allowed
            zoneRadius = 8,        -- tiles: smallest circle drawn on the map around the spot
            zoneMargin = 3,        -- tiles kept between the spot corners and the circle
            scanMs = 3000,         -- real ms between two server reads of the spot
        },
        -- E20-T14: keep watch at a place of the voice sheet for a duration in game hours, then report what was seen
        -- (server/CoreAI/CA_MissionWatch.lua). Given by a radio voice only (no reward lot: the voice pays).
        watch = {
            id = 'watch_v1',
            titleKey = 'IGUI_CA_Mission_Watch',
            durationMs = 14400000, -- 64 game hours at the default day length: room for a watch of maxHours
            rewardType = '',
            rewardCount = 0,
            hours = 2,             -- game hours of the watch when the section sets no hours
            maxHours = 24,         -- longest watch a section may ask
            radius = 6,            -- tiles (on the ground plane, any level) around the place where a participant watches
            absenceMinutes = 10,   -- game minutes a watch tolerates nobody at the spot; longer: it starts from zero
            gapHours = 1,          -- game hours between two readings (fast forward) still counted; longer: from zero
            zoneRadius = 8,        -- tiles: circle drawn on the map around the place
            scanMs = 3000,         -- real ms between two samplings of the facts of the spot (horde)
        },
        -- E20-T13: several places of the voice sheet crossed in order, on foot or by vehicle
        -- (server/CoreAI/CA_MissionRoute.lua). Given by a radio voice only (no reward lot: the voice pays).
        route = {
            id = 'route_v1',
            titleKey = 'IGUI_CA_Mission_Route',
            durationMs = 14400000, -- several places to reach, maybe far apart: the delay of `relay`
            rewardType = '',
            rewardCount = 0,
            radius = 8,            -- tiles: a point is crossed within this distance of the participant (or vehicle)
            maxStep = 60,          -- tiles between two server readings still driven (above: a jump, only its end counts)
        },
        -- E20-T15: a personal vanilla item placed by the server at a place of the voice sheet, to find and leave at
        -- one of the mission's dead drops (server/CoreAI/CA_MissionItem.lua). Given by a radio voice only
        -- (no reward lot: the voice pays).
        item = {
            id = 'item_v1',
            titleKey = 'IGUI_CA_Mission_Item',
            durationMs = 14400000, -- a place to search and a drop to reach: the delay of `relay`
            rewardType = '',
            rewardCount = 0,
            zoneHalf = 4,          -- tiles around a place outside any building: square of 9 x 9 tiles where it lies
            zoneRadius = 8,        -- tiles: smallest circle drawn on the map around the place
            zoneMargin = 3,        -- tiles kept between the place corners and the circle
        },
    },
    -- E11-T06: caches (server/CoreAI/CA_Caches.lua): a marked bag filled from one closed table of the server,
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
    -- E18-T33: lot of a mission given by an NPC, by type of its group: a table of Caches.tables. Read by an NPC engine
    -- (its mission rewards: lot created when the household has no surplus and the mission announces none, with or
    -- without the voices, E11-T21). Unknown type: food.
    NPC_REWARD_TABLES = {settlers = 'tools', neutrals = 'food', raiders = 'ammo'},
}

return MC
