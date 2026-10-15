-- Real server containers and world bags; all online witnesses leave before pickup.
require 'RST/RST'
require 'RST/RST_Fixtures'
require 'RST/RST_RSHelpers'
local F = RST.Fixtures

local function run(t, mode)
    if isClient() then t:skip('authority only') end
    local D = require 'RadioSurvivor/RS_VoiceDelivery'
    local p = F.player(t)
    local sq = p:getSquare()
    t:ok(sq ~= nil, 'requester square unavailable')
    local m = {id='rst-drop-'..mode..'-'..tostring(RST.now()), donor='voice',state='active',
        quantity=2,delivered=0,accepted={['Base.Bandage']=true},
        deposit={x=sq:getX(),y=sq:getY(),z=sq:getZ(),mode=mode}}
    local store = {save=function() return true end}
    local crate, wo, inv, bag
    local ids={}
    if mode=='box' then
        crate=IsoObject.new(getCell(),sq,'location_military_generic_01_0')
        crate:createContainersFromSpriteProperties()
        sq:transmitAddObjectToSquare(crate,-1)
    end
    t:defer(function()
        if inv then
            for _,id in ipairs(ids) do
                local it=inv:getItemWithIDRecursiv(id)
                if it then
                    inv:DoRemoveItem(it)
                    if isServer() and mode=='box' then sendRemoveItemFromContainer(inv,it) end
                end
            end
        end
        if wo and wo:getSquare() then wo:getSquare():transmitRemoveItemFromSquare(wo) end
        if crate and crate:getSquare() then crate:getSquare():transmitRemoveItemFromSquare(crate) end
        D.resetForTests()
    end,'remove deposit fixture')
    t:eq(true,D.prepare(m,store),'prepare actual deposit')
    if mode=='bag' then
        bag=instanceItem('Base.Bag_Schoolbag')
        t:ok(bag~=nil,'bag script unavailable')
        inv=bag:getItemContainer()
        sq:AddWorldInventoryItem(bag,0.5,0.5,0,true)
        wo=bag:getWorldItem()
    else
        t:eq('box',m.deposit.mode,'real crate not selected')
        local b=m.deposit.box
        local at=getCell():getGridSquare(b.x,b.y,m.deposit.z)
        inv=at:getObjects():get(b.object):getContainerByIndex(b.container)
    end
    for i=1,2 do
        local it=inv:AddItem('Base.Bandage')
        ids[i]=it:getID()
        if isServer() then sendAddItemToContainer(inv,it) end
    end
    local function observe() D.observe(m,p,'Tester',{},store) end
    observe()
    t:eq(0,m.delivered,'caller still watches deposit')
    t:eq(true,D.witness(m,p),'caller witness not detected')
    F.movePlayers(t,p,p:getX()+65,p:getY(),p:getZ(),function(t2)
        t2:eq(false,D.witness(m,p),'some online player still witnesses deposit')
        observe()
        t2:eq(0,m.delivered,'departure collected instantly')
        t2:waitUntil(function()
            observe()
            return m.delivered==2
        end,20000,function(t3)
            t3:eq(2,m.delivered,'hidden pickup not credited')
            if mode=='bag' then
                local objects=sq:getWorldObjects()
                for i=0,objects:size()-1 do
                    t3:ok(objects:get(i):getItem():getID()~=bag:getID(),'bag still exists in world')
                end
            else
                for _,id in ipairs(ids) do
                    t3:eq(nil,inv:getItemWithIDRecursiv(id),'delivered object still in box')
                end
            end
            observe()
            t3:eq(2,m.delivered,'duplicate pickup credited')
        end)
    end)
end

RST.suite("rs.voicedelivery",{tags={"server","world"},testTimeoutMs=45000},function(s)
    s.test('agreed box loses only delivered objects after every witness leaves',function(t) run(t,'box') end)
    s.test('hidden bag disappears with its complete contents after departure',function(t) run(t,'bag') end)
end)
