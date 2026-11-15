-- Reward kind `lesson` (pool entry lesson:<skill>:<weight>, E20-T04): XP of a vanilla skill given by the server
-- (addXp), RS_Config.Rewards.lessonXP per lesson within RS_Config.Rewards.dailyXP per character and game day, both
-- times the sandbox option LessonMultiplier (0 disables lessons).
if isClient() then return end
local Rewards = require 'RadioSurvivor/RS_Rewards'
local Config = require 'RadioSurvivor/RS_Config'
local Rep = require 'RadioSurvivorCore/RC_Reputation'

local Lesson = {}

function Lesson.multiplier()
    local n = SandboxVars and SandboxVars.RadioSurvivor and SandboxVars.RadioSurvivor.LessonMultiplier
    if type(n) ~= 'number' or n ~= n then return 1 end
    return math.max(0, math.min(5, n))
end

local function xpAmount(state, cid)
    local day = Rep.today()
    if not day then return 0 end
    local row = state.lessonDays and state.lessonDays[cid]
    local used = row and row.day == day and row.xp or 0
    local k = Lesson.multiplier()
    return math.max(0, math.min(Config.Rewards.lessonXP * k, Config.Rewards.dailyXP * k - used))
end

local function available(ctx)
    local skill = ctx.param
    return skill and Perks and Perks[skill] and xpAmount(ctx.state, ctx.cid) > 0 or nil
end

local function reserve(ctx, rec)
    rec.skill, rec.xp = ctx.param, xpAmount(ctx.state, ctx.cid)
    return true
end

local function apply(ctx, rec)
    local state = ctx.state
    state.lessonDays = state.lessonDays or {}
    local day = Rep.today()
    local daily = state.lessonDays[ctx.cid]
    if not daily or daily.day ~= day then daily = {day = day, xp = 0}; state.lessonDays[ctx.cid] = daily end
    daily.xp = daily.xp + rec.xp
    if not ctx.store.save() then return false end
    addXp(ctx.player, Perks[rec.skill], rec.xp)
    return true
end

local function describe(rec)
    return 'A practical lesson in ' .. tostring(rec.skill) .. ' has been given.'
end

Rewards.register('lesson', {param = 'skill', available = available, reserve = reserve, apply = apply,
    describe = describe})

return Lesson
