-- Actual Java inventory/XP effects. Authority grants, each client reads its OWN player only.
-- E20-T04: rewards drawn at random in the [rewards] pool (RS_Rewards, kinds in server/RadioSurvivor/Rewards/); a voice
-- reward cache holds contents drawn in its category (catalogue personas/_categories.txt or a section of the sheet).
-- E21-T11: the reward tables of the caches of the core mod are ca.caches (CA_CacheTables.lua, batman_CoreAITests).
require 'RST/RST'
require "RST/RST_ModRadioSurvivor"
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

-- Contents of the reward bag with this item id on the floor around (x, y, z), as THIS client sees it:
-- full type -> count.
local function bagContents(args)
    local cell = getCell()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell and cell:getGridSquare(args.x + dx, args.y + dy, args.z)
            local floor = sq and sq:getWorldObjects()
            for i = 0, (floor and floor:size() or 0) - 1 do
                local item = floor:get(i):getItem()
                if item and item:getID() == args.id then
                    local out, inside = {}, item:getItemContainer():getItems()
                    for j = 0, inside:size() - 1 do
                        local fullType = inside:get(j):getFullType()
                        out[fullType] = (out[fullType] or 0) + 1
                    end
                    return out
                end
            end
        end
    end
    return nil
end

Steps.on('rewards.cachebag', function(args)
    return function(ctx)
        local items = bagContents(args)
        if items then return Steps.pass('reward bag seen on the floor', {items=items}) end
        if ctx.final then return Steps.fail('reward bag ' .. tostring(args.id) .. ' not seen around '
            .. args.x .. ',' .. args.y .. ',' .. args.z) end
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

-- Item line of this full type in the category, or nil.
local function lineOf(category, fullType)
    for _, item in ipairs(category.items) do
        if item.type == fullType then return item end
    end
    return nil
end

-- Every item of the bag belongs to the category, each count within its range and equal to the drawn contents.
local function checkContents(t, category, drawn, items, who)
    local expected = {}
    for _, line in ipairs(drawn) do expected[line[1]] = line[2] end
    for fullType, count in pairs(items) do
        local line = lineOf(category, fullType)
        t:ok(line ~= nil, who .. ': ' .. fullType .. ' is not in category ' .. category.id)
        if line then
            t:ok(count >= line.min and count <= line.max, who .. ': ' .. fullType .. ' x' .. count .. ' outside '
                .. line.min .. '-' .. line.max)
        end
        t:eq(expected[fullType], count, who .. ': count of ' .. fullType .. ' differs from the drawn contents')
    end
    for fullType, count in pairs(expected) do
        t:eq(count, items[fullType], who .. ': drawn ' .. fullType .. ' missing from the bag')
    end
end

local function setup(t, kind)
    if isClient() then t:skip('authority only') end
    local Server = Helpers.notebook(t)
    local Notebook = Server.store
    -- E21-T04: the ledgers of the rewards live in the state of the voices, saved with the missions (S.save).
    local S = require "RadioSurvivor/RS_State"
    local p = RST.Fixtures.player(t)
    local cid = Helpers.character(t, p)
    local id = 'rst-reward-' .. kind .. '-' .. tostring(RST.now())
    local m = {id=id, state='success', participants={[cid]=true}}
    Notebook.data.missions[id] = m
    -- E20-T03: [rewards] pool of the sheet (one entry of this kind); E25-T01: cache_place= a shared point for the cache.
    local params = {cache='medical', lesson='Doctor'}
    local point = {id='reward',label='Test reward',x=math.floor(p:getX()),y=math.floor(p:getY()),z=math.floor(p:getZ())}
    local source = {id=id, rewards={{kind=kind, param=params[kind], weight=1}}, shares={'cody','darlene'},
        places={reward=point}, cachePlace=point}
    t:defer(function()
        Notebook.data.missions[id] = nil
        if S.data.missionRewards then S.data.missionRewards[cid .. ':' .. id] = nil end
        S.dirty = true
    end, 'reward fixture removed')
    return require('RadioSurvivor/RS_Rewards'), S, p, cid, m, source
end

RST.suite("rs.missionrewards", {tags={"server","world"},testTimeoutMs=45000}, function(s)
    s.test('every catalogue category contains real item scripts', function(t)
        if isClient() then t:skip('authority only') end
        local categories = require('RadioSurvivor/RS_Personas').rules().categories
        local count = 0
        for id, category in pairs(categories) do
            count = count + 1
            for _, item in ipairs(category.items) do
                t:ok(instanceItem(item.type) ~= nil, 'missing script ' .. item.type .. ' in category ' .. id)
            end
        end
        t:ok(count > 0, 'shared category catalogue not loaded')
    end)

    s.test('voice mission cache holds contents of the drawn category, seen alike by the client', function(t)
        local _,S,p,cid,m,source=setup(t,'cache')
        -- Pool of two catalogue categories and one of the sheet (E20-T03 [category] section).
        source.categories={rst_snacks={id='rst_snacks',items={{type='Base.Crisps',min=1,max=3},
            {type='Base.Pop',min=2,max=2}}}}
        source.rewards={{kind='cache',param='medical',weight=1},{kind='cache',param='food',weight=1},
            {kind='cache',param='rst_snacks',weight=1}}
        local V=require 'RadioSurvivor/RS_MissionVoice'
        local rec=V.reward(S,source,m,p,cid,nil)
        t:ok(rec and rec.status=='applied','voice mission reward not applied')
        t:eq('cache',rec.kind,'reward kind')
        local Cache=require 'RadioSurvivor/Rewards/RS_Reward_Cache'
        local category=Cache.category(source,rec.category)
        t:ok(category~=nil,'drawn category unknown: '..tostring(rec.category))
        t:eq(rec.category,m.cache.table,'cache record category')
        local C=require 'RadioSurvivor/RS_CacheAction'
        C.place(S,m.cache)
        t:eq(true,m.cache.placed,'reward cache was not placed')
        local at=m.cache.at
        local server=bagContents({id=m.cache.itemId,x=at.x,y=at.y,z=at.z})
        t:ok(server~=nil,'reward bag absent from the floor on the authority')
        checkContents(t,category,m.cache.items,server or {},'authority')
        t:note('drawn category '..rec.category..', '..#m.cache.items..' item lines')
        Steps.ask(t,'rewards.cachebag',{id=m.cache.itemId,x=at.x,y=at.y,z=at.z},
            {target='requester',timeoutMs=15000},function(t2,res)
                for _,row in ipairs(res.list) do
                    if row.status=='PASS' then checkContents(t2,category,m.cache.items,row.data.items,row.user) end
                end
            end)
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
            -- Vanilla AddXP multipliers apply (IsoGameCharacter.java:15616-15643: x0.25 without a profession or trait boost):
            -- the recipient gains XP, at most 1.66 times the lesson.
            Steps.ask(t2,'rewards.xp',{skill='Doctor',minimum=before+rec.xp*0.25},
                {target='requester',timeoutMs=15000},function(t3,res)
                    local d=res.list[1].data
                    t3:ok(d.xp>=before+rec.xp*0.25-0.001 and d.xp<=before+rec.xp*1.66+0.001,
                        'recipient did not receive server XP: ' .. tostring(d.xp - before)
                        .. ' for a lesson of ' .. tostring(rec.xp))
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
        local C=require 'RadioSurvivor/RS_CacheAction'
        C.place(S,m.cache)
        t:eq(true,m.cache.placed,'real cache was not placed')
        local itemId=m.cache.itemId
        t:eq(rec,R.grant(S,source,m,p,cid),'cache reward duplicated')
        t:eq(itemId,m.cache.itemId,'cache bag identity changed')
        t:note('cache status='..tostring(m.cache.status)..', placed='..tostring(m.cache.placed))
    end)

    s.test('stash map is a real annotated map and cannot repeat for source',function(t)
        local R,S,p,cid,m,source=setup(t,'stashmap')
        t:ok(require('RadioSurvivor/Rewards/RS_Reward_Stashmap').find()~=nil,
            'no undiscovered vanilla stash in fresh test world')
        local count=p:getInventory():getItems():size()
        local rec,why=R.grant(S,source,m,p,cid)
        t:ok(rec and rec.status=='applied','stash grant failed: '..tostring(why))
        t:eq(count+1,p:getInventory():getItems():size(),'stash map not in real inventory')
        local nextMission={id=m.id..'-next',state='success',participants={[cid]=true}}
        t:eq(nil,(R.choose(S.data,source,nextMission,cid)),'same source gave a second stash map')
    end)

    s.test('frequency reward changes recipient private radio log only',function(t)
        local R,S,p,cid,m,source=setup(t,'frequency')
        t:ok(require('RadioSurvivor/Rewards/RS_Reward_Frequency').find(source)~=nil,
            'no active delivered voice frequency')
        local other=Steps.others(t)[1]
        local mate=other and Steps.playerOf(other)
        local mid=mate and Helpers.character(t,mate)
        local radio=mid and RST.radioOf(mid)
        local sequence=radio and radio.seq
        local rec,why=R.grant(S,source,m,p,cid)
        t:ok(rec and rec.status=='applied','frequency grant failed: '..tostring(why))
        t:ok(RST.radioOf(cid)~=nil,'recipient radio log absent')
        if mid then
            local after=RST.radioOf(mid)
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
