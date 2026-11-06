--[[
RadioSurvivorCore: rules of the reputation kept by the core mod (E18-T22, moved from RadioSurvivor's RS_Config,
values unchanged: docs/annexes/conception/reputation-interne.md section 9, confirmed by default 2026-10-15). Read by
server/RadioSurvivorCore/RC_Reputation.lua; RadioSurvivor's RS_Config.Reputation is this table (one copy).
]]
return {
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
}
