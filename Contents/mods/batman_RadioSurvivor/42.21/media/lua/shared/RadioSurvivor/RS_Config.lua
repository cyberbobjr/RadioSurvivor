local C = {
    MODULE = 'RS_Carnet',
    VoiceDelivery = {radius = 3, unseenDistance = 40, unseenMs = 10000, maxItems = 512},
    Rewards = {order = {'cache', 'frequency', 'stashmap', 'lesson'}, lessonXP = 25, dailyXP = 100,
        -- Vanilla 42.21 stash catalogue; mod-added stash maps are never mission rewards.
        vanillaStashes = {
            ['BBurgStashMap1'] = true,
            ['BBurgStashMap2'] = true,
            ['BBurgStashMap3'] = true,
            ['BBurgStashMap4'] = true,
            ['BBurgStashMap5'] = true,
            ['BBurgStashMap6'] = true,
            ['BBurgStashMap7'] = true,
            ['BBurgStashMap8'] = true,
            ['EkronStashMap1'] = true,
            ['EkronStashMap2'] = true,
            ['EkronStashMap3'] = true,
            ['EkronStashMap4'] = true,
            ['EkronStashMap5'] = true,
            ['EkronStashMap6'] = true,
            ['EkronStashMap7'] = true,
            ['EkronStashMap8'] = true,
            ['IrvingtonStashMap1'] = true,
            ['IrvingtonStashMap10'] = true,
            ['IrvingtonStashMap2'] = true,
            ['IrvingtonStashMap3'] = true,
            ['IrvingtonStashMap4'] = true,
            ['IrvingtonStashMap5'] = true,
            ['IrvingtonStashMap6'] = true,
            ['IrvingtonStashMap7'] = true,
            ['IrvingtonStashMap8'] = true,
            ['IrvingtonStashMap9'] = true,
            ['LouisvilleStashMap1'] = true,
            ['LouisvilleStashMap10'] = true,
            ['LouisvilleStashMap11'] = true,
            ['LouisvilleStashMap12'] = true,
            ['LouisvilleStashMap13'] = true,
            ['LouisvilleStashMap14'] = true,
            ['LouisvilleStashMap15'] = true,
            ['LouisvilleStashMap16'] = true,
            ['LouisvilleStashMap2'] = true,
            ['LouisvilleStashMap3'] = true,
            ['LouisvilleStashMap4'] = true,
            ['LouisvilleStashMap5'] = true,
            ['LouisvilleStashMap6'] = true,
            ['LouisvilleStashMap7'] = true,
            ['LouisvilleStashMap8'] = true,
            ['LouisvilleStashMap9'] = true,
            ['MarchRidgeStashMap1'] = true,
            ['MarchRidgeStashMap10'] = true,
            ['MarchRidgeStashMap2'] = true,
            ['MarchRidgeStashMap3'] = true,
            ['MarchRidgeStashMap4'] = true,
            ['MarchRidgeStashMap5'] = true,
            ['MarchRidgeStashMap6'] = true,
            ['MarchRidgeStashMap7'] = true,
            ['MarchRidgeStashMap8'] = true,
            ['MarchRidgeStashMap9'] = true,
            ['MulStashMap1'] = true,
            ['MulStashMap10'] = true,
            ['MulStashMap11'] = true,
            ['MulStashMap12'] = true,
            ['MulStashMap13'] = true,
            ['MulStashMap14'] = true,
            ['MulStashMap15'] = true,
            ['MulStashMap16'] = true,
            ['MulStashMap17'] = true,
            ['MulStashMap18'] = true,
            ['MulStashMap19'] = true,
            ['MulStashMap2'] = true,
            ['MulStashMap3'] = true,
            ['MulStashMap4'] = true,
            ['MulStashMap5'] = true,
            ['MulStashMap6'] = true,
            ['MulStashMap7'] = true,
            ['MulStashMap8'] = true,
            ['MulStashMap9'] = true,
            ['RiversideStashMap1'] = true,
            ['RiversideStashMap10'] = true,
            ['RiversideStashMap2'] = true,
            ['RiversideStashMap3'] = true,
            ['RiversideStashMap4'] = true,
            ['RiversideStashMap5'] = true,
            ['RiversideStashMap6'] = true,
            ['RiversideStashMap7'] = true,
            ['RiversideStashMap8'] = true,
            ['RiversideStashMap9'] = true,
            ['RosewoodStashMap1'] = true,
            ['RosewoodStashMap2'] = true,
            ['RosewoodStashMap3'] = true,
            ['RosewoodStashMap4'] = true,
            ['RosewoodStashMap5'] = true,
            ['WorldStashMap1'] = true,
            ['WorldStashMap10'] = true,
            ['WorldStashMap11'] = true,
            ['WorldStashMap12'] = true,
            ['WorldStashMap13'] = true,
            ['WorldStashMap14'] = true,
            ['WorldStashMap15'] = true,
            ['WorldStashMap16'] = true,
            ['WorldStashMap17'] = true,
            ['WorldStashMap18'] = true,
            ['WorldStashMap19'] = true,
            ['WorldStashMap2'] = true,
            ['WorldStashMap20'] = true,
            ['WorldStashMap21'] = true,
            ['WorldStashMap22'] = true,
            ['WorldStashMap23'] = true,
            ['WorldStashMap3'] = true,
            ['WorldStashMap4'] = true,
            ['WorldStashMap5'] = true,
            ['WorldStashMap6'] = true,
            ['WorldStashMap7'] = true,
            ['WorldStashMap8'] = true,
            ['WorldStashMap9'] = true,
            ['WpStashMap1'] = true,
            ['WpStashMap10'] = true,
            ['WpStashMap11'] = true,
            ['WpStashMap12'] = true,
            ['WpStashMap13'] = true,
            ['WpStashMap14'] = true,
            ['WpStashMap15'] = true,
            ['WpStashMap16'] = true,
            ['WpStashMap2'] = true,
            ['WpStashMap3'] = true,
            ['WpStashMap4'] = true,
            ['WpStashMap5'] = true,
            ['WpStashMap6'] = true,
            ['WpStashMap7'] = true,
            ['WpStashMap8'] = true,
            ['WpStashMap9'] = true,
        }},
    NPC_REWARD_TEACHES = {medic = 'Doctor', fighter = 'Aiming', scout = 'Aiming', worker = 'Woodwork',
        breaker = 'Maintenance', deputy = 'Aiming'},
    NPC_REWARD_TABLES = {settlers = 'tools', neutrals = 'food', raiders = 'ammo'},
    VERSION = 2,
    SELECT_RANGE = 8,
    DELIVERY_RANGE = 3,
    HEARING_RANGE = 30, -- inspected SayChat default; our policy, not a claim of exact vanilla hearing
    NOISE_RANGE = 15,
    -- E17-T15: longer than the longest answer of the bridge (bridge/radio_bridge.py: start at most MAX_AGE_S = 75 s
    -- after `sent`, then one model call of at most LLM_BUDGET_S = 60 s, attempts included: 135 s). An error of the
    -- provider comes back sooner as a reply with `error` (timeout, http_503...), refused with that cause.
    REQUEST_TIMEOUT_MS = 150000,
    COOLDOWN_MS = 10000,
    MAX_PENDING = 8,
    MAX_PER_HOUR = 60,
    ENRICH_PER_HOUR = 12,
    ENRICH_RETRY_MS = 300000,
    ENRICH_MAX_ATTEMPTS = 3,
    NARRATIVE_LANGUAGE = 'FR', -- one canonical biography, independent of listener language
    MAX_TEXT_BYTES = 800,
    MAX_REPLY_BYTES = 1600,
    SAVE_INTERVAL_MS = 5000, -- only while a mission clock runs or the state changed
    MAX_HISTORY = 40,
    -- E17-T08: acquaintance of a character with an NPC (RS_Carnet_Server, contact.stage). 'stranger' until a talk at
    -- least ACQUAINT_HOURS game hours after the first answered exchange, or after ACQUAINT_EXCHANGES answered exchanges.
    ACQUAINT_HOURS = 1,
    ACQUAINT_EXCHANGES = 4,
    -- Snapshot polling by the client: open notebook vs. closed (identity/session keep-alive).
    SNAPSHOT_OPEN_MS = 3000,
    SNAPSHOT_CLOSED_MS = 30000,
    -- Lifecycle of missions and NPC fiches; keeps the private state bounded on long servers.
    -- E11-T20: OFFER_TTL_MS, OFFER_COOLDOWN_MS and the durationMs of the missions are play ms (RS_GameClock: real ms
    -- at normal speed, stopped while the game is paused, faster at x2/x3); the retentions below stay real time.
    OFFER_TTL_MS = 3600000,            -- play time before an unaccepted offer expires
    OFFER_COOLDOWN_MS = 1800000,       -- play time before the same NPC or voice can offer again
    -- E11-T06: offers sent to the bridge in one npc_talk request, at most (RS_Missions.offers keeps the first ones in
    -- template registration order and does not ask the templates after the cap: no place drawn for an offer that is
    -- not sent). Same value as MAX_OFFERS in bridge/npc_protocol.py, which rejects a larger catalog.
    MAX_OFFERS = 6,
    MISSION_RETENTION_MS = 86400000,   -- closed missions kept 24 h for the notebook
    UNCLAIMED_RETENTION_MS = 604800000, -- successful but unclaimed lot kept 7 days
    NPC_UNSEEN_MS = 3600000,           -- uncontacted fiche dropped after 1 h without a loaded body
    PRUNE_INTERVAL_MS = 60000,
    -- Personal observations of contacted NPCs (E08-T02, server/RadioSurvivor/RS_Observations.lua). `facts` is the
    -- closed list of the E08-T01 triggers (same list as OBS_FACTS in bridge/npc_protocol.py).
    Observations = {
        facts = {'player_return', 'mission_done', 'group_death', 'assault_seen', 'weather', 'power_cut', 'helicopter'},
        maxPerNpc = 12,   -- oldest evicted
        maxChain = 4,     -- provenance entries ('seen', 'heard_from:<npc>'...); a full chain is not retold
        maxNpcs = 64,     -- tracked fiches, least recently updated evicted
        subjectChars = 48,
        placeChars = 32,
        areaTiles = 256,  -- coarse area of RS_Observations.area (one map cell)
        -- E08-T07 triggers (server/RadioSurvivor/RS_ObservationTriggers.lua)
        returnHours = 24,     -- player_return: game hours out of hearing range before a comeback counts
        witnessRange = 20,    -- group_death: tiles between a witness body and the dead body (same floor, CanSee)
        -- E08-T08 world triggers (same file): weather and power cut polled at EveryHours, vanilla helicopter heard
        -- through its world sound (OnWorldSound, Helicopter.java:218).
        worldPlace = 'everywhere',  -- place of a global event (storm, power cut): one shared key for every witness
        helicopterSound = 500,      -- radius and volume of the vanilla helicopter world sound (source nil, z 0)
        helicopterRange = 500,      -- tiles between a witness (loaded body, else home) and a helicopter sound
        helicopterGapHours = 2,     -- game hours without a helicopter sound before the next sound is a new passage
        helicopterEveryMs = 5000,   -- helicopter sounds handled at most once per this real time (ms)
    },
    -- Internal reputation (E04-T08/T09, server/RadioSurvivor/RS_Reputation.lua, docs/annexes/conception/reputation-interne.md
    -- section 9, values confirmed by default 2026-10-15). Amounts per act; the score stays on the server.
    Reputation = {
        success = 5, failure = -5,       -- mission.success; mission.failed, mission.abandoned, trade.cheated
        requesterKilled = -50,           -- npc.requesterKilled (E04-T07, Q7: back to bad)
        memberKilled = -10,              -- npc.memberKilled (Q5)
        rescue = 5,                      -- rescue.success (reserved, E12)
        min = -100, max = 100, start = 0, -- bounds and start of every new character (Q1)
        badAt = -20, goodAt = 20,        -- bad <= badAt < neutral < goodAt <= good (Q3: four successes)
        dailyGainCap = 10,               -- gains per character and game day (Q6); losses never capped; no decay (Q4)
        reasons = 5, trendFacts = 3,     -- reasons kept and shown (Q8), acts read by the trend
        keepOutcomeDays = 30,            -- game days an outcome (deduplication record) is kept
        retiredPurgeDays = 7,            -- game days before a dead character's reputation and outcomes are dropped
        -- E04-T05 (Q11, Q12): templates (and offer kinds) closed to a bad reputation; simple missions (deliver,
        -- signal, scout, clear) stay open to every level.
        sensitive = {retrieve_id = true, recover = true, supply = true},
        -- E04-T11 (Q13): lowest margin of the smuggler by level; a done deal lowers it by RS_Trade.MARGIN_STEP down to
        -- RS_Trade.MARGIN_MIN, a cheat sets RS_Trade.MARGIN_MAX.
        margin = {good = 0.10, neutral = 0.25, bad = 0.40},
    },
    -- Mission catalogue, one entry per template of RS_Missions (E11-T02). `id` is the offer id seen by the bridge;
    -- durationMs (play ms, E11-T20), rewardType and rewardCount are read by the engine, the other fields by the
    -- template.
    Missions = {
        -- M01: first-aid delivery.
        deliver = {
            id = 'first_aid_v1',
            titleKey = 'IGUI_RS_FirstAid',
            quantity = 6,
            durationMs = 7200000,
            accepted = {['Base.Bandage'] = true, ['Base.RippedSheets'] = true},
            rewardType = 'Base.Bullets9mm',
            rewardCount = 20,
        },
        -- E11-T03: reach a building drawn by the server, then report to the requester in person
        -- (server/RadioSurvivor/RS_MissionScout.lua). Delay and reward of M01 (decisions E11-T01).
        scout = {
            id = 'scout_v1',
            titleKey = 'IGUI_RS_Scout',
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
        -- (server/RadioSurvivor/RS_MissionRetrieve.lua). Place, area, delay and reward as `scout`.
        retrieve_id = {
            id = 'retrieve_id_v1',
            titleKey = 'IGUI_RS_Retrieve',
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
        -- (server/RadioSurvivor/RS_MissionClear.lua). Place, delay and reward as `scout`; N from the zone density.
        clear = {
            id = 'clear_v1',
            titleKey = 'IGUI_RS_Clear',
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
        -- the requester's group (server/RadioSurvivor/RS_MissionRecover.lua). Place, area, delay and reward as `scout`.
        recover = {
            id = 'recover_v1',
            titleKey = 'IGUI_RS_Recover',
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
        -- a window of game hours (server/RadioSurvivor/RS_MissionSignal.lua), with the required mod Signal Smoke.
        -- Place, delay and reward as `scout`.
        signal = {
            id = 'signal_v1',
            titleKey = 'IGUI_RS_Signal',
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
    -- E11-T06: caches (server/RadioSurvivor/RS_Caches.lua): a marked bag filled from one closed table of the server,
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
-- Historical name of the M01 entry (same table).
C.Delivery = C.Missions.deliver

-- E17-T11: game language code sent to the bridge as a hint (npc_talk). The game names a language after its Translate
-- folder (Language.name(), Languages.loadTranslateDirectory: EN, ES, ES_CL, PTBR, STREW, or a folder added by a mod),
-- so the code is checked by its form only, never against a list of known languages: 2 to 8 characters, ASCII letters
-- and underscores, starting with a letter, upper-cased (Languages.getByName ignores the case). Anything else -> 'EN'.
-- Same form as LANGUAGE_CODE in bridge/npc_protocol.py.
function C.languageCode(value)
    if type(value) ~= 'string' then return 'EN' end
    local code = value:upper()
    if #code < 2 or #code > 8 or not code:match('^[A-Z][A-Z_]+$') then return 'EN' end
    return code
end
return C
