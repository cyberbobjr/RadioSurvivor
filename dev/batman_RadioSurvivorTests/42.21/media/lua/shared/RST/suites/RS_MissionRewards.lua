-- Actual Java inventory/XP effects. Authority grants, each client reads its OWN player only.
require 'RST/RST'
require 'RST/RST_Fixtures'
require 'RST/RST_Steps'
require 'RST/RST_RSHelpers'
local Steps = RST.Steps
local Helpers = RST.RSHelpers

Steps.on('rewards.radio', function(args)
    local H = require 'RadioSurvivor/RS_RadioHistory'
    local count = #H.frequencies
    H.request()
    return function(ctx)
        if #H.frequencies == args.count or ctx.final then return Steps.pass('own radio entries=' .. tostring(#H.frequencies),
            {count=#H.frequencies, previous=count}) end
    end
end)

Steps.on('rewards.xp', function(args)
    local p = getSpecificPlayer(0)
    if not p then return Steps.fail('no local player') end
    return function(ctx)
        local xp = p:getXp():getXP(Perks[args.skill])
        if not args.minimum or xp >= args.minimum or ctx.final then
            return Steps.pass('local XP=' .. tostring(xp), {xp=xp})
        end
    end
end)

local function setup(t, kind)
    if isClient() then t:skip('authority only') end
    local Server = Helpers.notebook(t)
    local S = Server.store
    local p = RST.Fixtures.player(t)
    local cid = Helpers.character(t, p)
    local id = 'rst-reward-' .. kind .. '-' .. tostring(RST.now())
    local m = {id=id, state='success', participants={[cid]=true}}
    S.data.missions[id] = m
    local source = {id=id, rewards={kind}, teaches='Doctor', cache_table='medical', shares={'cody','darlene'},
        places={{id='reward',label='Test reward',x=math.floor(p:getX()),y=math.floor(p:getY()),z=math.floor(p:getZ())}}}
    t:defer(function()
        S.data.missions[id] = nil
        if S.data.missionRewards then S.data.missionRewards[cid .. ':' .. id] = nil end
        S.dirty = true
    end, 'reward fixture removed')
    return require('RadioSurvivor/RS_Rewards'), S, p, cid, m, source
end

RST.suite("rs.missionrewards", {tags={"server","world"},testTimeoutMs=45000}, function(s)
    s.test('every closed reward table contains real item scripts', function(t)
        if isClient() then t:skip('authority only') end
        local config = require 'RadioSurvivor/RS_Config'
        for _, name in ipairs(config.Caches.order) do
            for _, entry in ipairs(config.Caches.tables[name]) do
                t:ok(instanceItem(entry[1]) ~= nil, 'missing reward script: ' .. entry[1])
            end
        end
    end)
    s.test('lesson is applied by server and observed by recipient client; peer unchanged', function(t)
        local R,S,p,cid,m,source = setup(t,'lesson')
        local oldDay = S.data.lessonDays and S.data.lessonDays[cid]
        S.data.lessonDays = S.data.lessonDays or {}; S.data.lessonDays[cid] = nil
        t:defer(function() S.data.lessonDays[cid] = oldDay end, 'daily lesson state restored')
        local before = p:getXp():getXP(Perks.Doctor)
        local other = Steps.others(t)[1]
        local mate = other and Steps.playerOf(other)
        local mateBefore = mate and mate:getXp():getXP(Perks.Doctor)
        local target = mate and 'others' or 'requester'
        Steps.ask(t,'rewards.xp',{skill='Doctor'}, {target=target,timeoutMs=10000}, function(t2, initial)
            local rec,why = R.grant(S,source,m,p,cid)
            t2:ok(rec and rec.status=='applied', 'lesson grant failed: ' .. tostring(why))
            t2:eq('lesson',rec.kind,'reward kind')
            Steps.ask(t2,'rewards.xp',{skill='Doctor',minimum=before+rec.xp},
                {target='requester',timeoutMs=15000},function(t3,res)
                    local d=res.list[1].data
                    t3:ok(d.xp>=before+rec.xp,'recipient did not receive server XP')
                    local same=R.grant(S,source,m,p,cid)
                    t3:eq(rec,same,'duplicate reward record')
                    if mate then
                        t3:eq(mateBefore,mate:getXp():getXP(Perks.Doctor),'peer server XP changed')
                        Steps.ask(t3,'rewards.xp',{skill='Doctor'},{target='others',timeoutMs=10000},function(t4,after)
                            for i,row in ipairs(after.list) do
                                t4:eq(initial.list[i].data.xp,row.data.xp,'unrelated client received lesson')
                            end
                        end)
                    end
                end)
        end)
    end)

    s.test('real reward cache is placed once on a loaded square',function(t)
        local R,S,p,cid,m,source=setup(t,'cache')
        local rec,why=R.grant(S,source,m,p,cid)
        t:ok(rec and rec.status=='applied','cache grant failed: '..tostring(why))
        t:ok(m.cache~=nil,'persistent cache outbox absent')
        local C=require 'RadioSurvivor/RS_Caches'
        C.place(S,m.cache)
        t:eq(true,m.cache.placed,'real cache was not placed')
        local itemId=m.cache.itemId
        t:eq(rec,R.grant(S,source,m,p,cid),'cache reward duplicated')
        t:eq(itemId,m.cache.itemId,'cache bag identity changed')
        t:note('cache status='..tostring(m.cache.status)..', placed='..tostring(m.cache.placed))
    end)

    s.test('stash map is a real annotated map and cannot repeat for source',function(t)
        local R,S,p,cid,m,source=setup(t,'stashmap')
        t:ok(R.stash()~=nil,'no undiscovered vanilla stash in fresh test world')
        local count=p:getInventory():getItems():size()
        local rec,why=R.grant(S,source,m,p,cid)
        t:ok(rec and rec.status=='applied','stash grant failed: '..tostring(why))
        t:eq(count+1,p:getInventory():getItems():size(),'stash map not in real inventory')
        local nextMission={id=m.id..'-next',state='success',participants={[cid]=true}}
        t:eq(nil,R.choose(S.data,source,nextMission,cid),'same source gave a second stash map')
    end)

    s.test('frequency reward changes recipient private radio log only',function(t)
        local R,S,p,cid,m,source=setup(t,'frequency')
        t:ok(R.frequency(source)~=nil,'no active delivered voice frequency')
        local other=Steps.others(t)[1]
        local mate=other and Steps.playerOf(other)
        local mid=mate and Helpers.character(t,mate)
        local radio=mid and S.data.characters[mid].radio
        local sequence=radio and radio.seq
        local rec,why=R.grant(S,source,m,p,cid)
        t:ok(rec and rec.status=='applied','frequency grant failed: '..tostring(why))
        t:ok(S.data.characters[cid].radio~=nil,'recipient radio log absent')
        if mid then
            local after=S.data.characters[mid].radio
            t:eq(sequence,after and after.seq,'peer private radio log sequence changed')
            local expected=after and #after.frequencies or 0
            Steps.ask(t,'rewards.radio',{count=expected}, {target={other},timeoutMs=5000},function(t2,res)
                for _,row in ipairs(res.list) do
                    t2:eq(expected,row.data.count,'unrelated client received someone else radio log')
                end
            end)
        end
    end)
end)
