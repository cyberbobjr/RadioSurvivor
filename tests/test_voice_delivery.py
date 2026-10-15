"""Hidden radio handovers, real Lua with isolated Lua 5.1 engine doubles.

These tests prove server logic, not Java API compatibility or network delivery.
"""
from pathlib import Path
import unittest

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_VoiceDelivery.lua'

WORLD = r'''
NOW, SAVES, SAVE_OK, SYNC, REMOVED = 100000, 0, true, 0, 0
function isClient() return false end
function isServer() return true end
function getTimestampMs() return NOW end
function list(t)
    return {size=function() return #t end, get=function(_, i) return t[i+1] end}
end
function container(items)
    local c = {items=items or {}}
    function c:getType() return 'crate' end
    function c:getItems() return list(self.items) end
    function c:getItemWithIDRecursiv(id)
        for _, it in ipairs(self.items) do
            if it:getID() == id then return it end
            if it.bag then local found=it.bag:getItemWithIDRecursiv(id); if found then return found end end
        end
    end
    function c:contains(it) for _,v in ipairs(self.items) do if v == it then return true end end return false end
    function c:DoRemoveItem(it)
        for i,v in ipairs(self.items) do if v==it then table.remove(self.items,i); it.owner=nil; return end end
    end
    c.Remove=c.DoRemoveItem
    for _,it in ipairs(c.items) do it.owner=c end
    return c
end
function item(id, kind, bag)
    local it={id=id,kind=kind or 'Base.Bandage',bag=bag,condition=10}
    function it:getID() return self.id end
    function it:getFullType() return self.kind end
    function it:getCondition() return self.condition end
    function it:isFavorite() return false end
    function it:isEquipped() return false end
    function it:isAttachedItem() return false end
    function it:getInventory() return self.bag end
    function it:getItemContainer() return self.bag end
    function it:getContainer() return self.owner end
    function it:getWorldItem() return self.world end
    return it
end
function instanceof(o, kind) return kind=='InventoryContainer' and o and o.bag~=nil end
SQUARES, LOADED = {}, true
function square(x,y,z)
    local key=x..','..y..','..z
    if SQUARES[key] then return SQUARES[key] end
    local sq={x=x,y=y,z=z,objects={},world={}}
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getObjects() return list(self.objects) end
    function sq:getWorldObjects() return list(self.world) end
    function sq:transmitRemoveItemFromSquare(wo)
        for i,v in ipairs(self.world) do if v==wo then table.remove(self.world,i); REMOVED=REMOVED+1; wo.it.world=nil; return 0 end end
        return -1
    end
    SQUARES[key]=sq
    return sq
end
function box(sq, inv)
    local o={inv=inv,modData={}}
    function o:getModData() return self.modData end
    function o:getSprite() return {getName=function() return 'carpentry_01_16' end} end
    function o:getContainerCount() return 1 end
    function o:getContainerByIndex(i) if i==0 then return self.inv end end
    function o:getContainer() return self.inv end
    function o:getSquare() return sq end
    inv.parent=o
    function inv:getParent() return self.parent end
    sq.objects[#sq.objects+1]=o
    return o
end
function ground(sq,it)
    local wo={it=it}
    function wo:getItem() return self.it end
    function wo:getSquare() return sq end
    it.world=wo
    sq.world[#sq.world+1]=wo
    return wo
end
function getCell() return {getGridSquare=function(_,x,y,z) if LOADED then return SQUARES[x..','..y..','..z] end end} end
function player(x,y,z)
    local p={x=x,y=y,z=z or 0,inv=container()}
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:getInventory() return self.inv end
    function p:isDead() return false end
    function p:getUsername() return 'alice' end
    return p
end
PLAYERS={player(100,100)}
function getOnlinePlayers() return list(PLAYERS) end
function getNumActivePlayers() return #PLAYERS end
function getSpecificPlayer(i) return PLAYERS[i+1] end
function sendRemoveItemFromContainer(c,it) SYNC=SYNC+1 end
STORE={save=function() SAVES=SAVES+1; return SAVE_OK end}
STATE={}
package.preload['RadioSurvivor/RS_Config']=function() return {VoiceDelivery={radius=3,unseenDistance=40,unseenMs=10000,maxItems=200}} end
package.preload['RadioSurvivor/RS_State']=function() return STORE end
'''


class VoiceDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.rt.execute(WORLD)
        self.rt.globals().D = self.rt.execute(MODULE.read_text(encoding='utf-8-sig'))

    def run_lua(self, source):
        self.rt.execute(source)

    def setup_delivery(self, mode='box'):
        self.run_lua("""
            sq=square(100,100,0); inv=container(); obj=box(sq,inv)
            m={id='mission1',donor='voice',state='active',quantity=2,delivered=0,
                accepted={['Base.Bandage']=true},participants={p={name='alice'}},
                deposit={x=100,y=100,z=0,mode='%s'}}
            D.prepare(m,STORE)
            function observe() return D.observe(m,PLAYERS[1],'alice',STATE,STORE) end
            function add_goods()
                goods={item(101),item(102)}
                if m.deposit.mode=='bag' then
                    bag=item(200,'Base.Bag_Schoolbag',container(goods)); ground(sq,bag)
                else
                    for _,it in ipairs(goods) do inv.items[#inv.items+1]=it; it.owner=inv end
                end
            end
            function depart() PLAYERS[1].x=150; observe() end
            function elapsed() NOW=NOW+10001; observe() end
        """ % mode)

    def test_box_only_collected_after_departure_and_delay(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); NOW=NOW+30000; observe()
            assert(m.delivered==0 and #inv.items==2,'present caller must block collection')
            depart(); assert(#inv.items==2,'departure is not immediate collection')
            elapsed(); assert(m.delivered==2 and #inv.items==0,'complete hidden collection required')
            assert(SYNC==2,'container removals must be synchronized')
            elapsed(); assert(m.delivered==2 and SYNC==2,'collection must be idempotent')
        """)

    def test_second_player_on_other_floor_resets_delay(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart()
            PLAYERS[2]=player(100,100,4); elapsed()
            assert(m.delivered==0 and #inv.items==2,'another floor is still a witness')
            PLAYERS[2].x=150; observe(); NOW=NOW+5000; observe()
            assert(m.delivered==0,'witness must reset the full delay')
            NOW=NOW+5001; observe(); assert(m.delivered==2)
        """)

    def test_partial_delivery_never_disappears(self):
        self.setup_delivery()
        self.run_lua("""
            it=item(101); inv.items={it}; it.owner=inv
            observe(); depart(); elapsed()
            assert(m.delivered==0 and #inv.items==1)
        """)

    def test_unloaded_square_defers_collection(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart(); LOADED=false; elapsed()
            assert(m.delivered==0 and #inv.items==2)
            LOADED=true; observe(); elapsed(); assert(m.delivered==2)
        """)

    def test_failed_save_does_not_consume(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart(); SAVE_OK=false; elapsed()
            assert(m.delivered==0 and #inv.items==2 and SYNC==0,'save must precede destruction')
        """)

    def test_goods_taken_back_before_collection_are_not_credited(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart()
            PLAYERS[1].inv.items={goods[1]}; goods[1].owner=PLAYERS[1].inv
            inv.items={goods[2]}; elapsed()
            assert(m.delivered==0 and #inv.items==1 and SYNC==0)
        """)

    def test_bag_and_contents_disappear_together(self):
        self.setup_delivery('bag')
        self.run_lua("""
            add_goods(); observe(); depart(); elapsed()
            assert(m.delivered==2 and #sq.world==0 and REMOVED==1)
            elapsed(); assert(REMOVED==1,'bag may only be removed once')
        """)

    def test_bag_in_player_inventory_is_not_a_deposit(self):
        self.setup_delivery('bag')
        self.run_lua("""
            goods={item(101),item(102)}
            bag=item(200,'Base.Bag_Schoolbag',container(goods))
            PLAYERS[1].inv.items={bag}; bag.owner=PLAYERS[1].inv
            observe(); depart(); elapsed()
            assert(m.delivered==0 and #bag.bag.items==2 and REMOVED==0)
        """)

    def test_bag_with_unrelated_goods_is_not_taken(self):
        self.setup_delivery('bag')
        self.run_lua("""
            add_goods(); bag.bag.items[3]=item(103,'Base.Hammer')
            observe(); depart(); elapsed()
            assert(m.delivered==0 and #sq.world==1 and REMOVED==0)
        """)

    def test_existing_household_stock_and_excess_goods_are_preserved(self):
        self.run_lua("""
            sq=square(100,100,0); old=item(1); inv=container({old}); obj=box(sq,inv)
            m={id='baseline',donor='voice',state='active',quantity=2,delivered=0,
                accepted={['Base.Bandage']=true},deposit={x=100,y=100,z=0,mode='box'}}
            assert(D.prepare(m,STORE))
            for id=101,103 do local it=item(id); inv.items[#inv.items+1]=it; it.owner=inv end
            PLAYERS[1].x=150
            D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            NOW=NOW+10001; D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            assert(m.delivered==2 and #inv.items==2)
            assert(inv:getItemWithIDRecursiv(1)==old,'existing stock must never be taken')
            assert(inv:getItemWithIDRecursiv(103),'excess deposited goods must remain')
        """)

    def test_process_restart_restarts_unseen_timer_and_preserves_ids(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart(); NOW=NOW+9000; observe()
            assert(m.depositCandidate and m.depositCandidate.ids[1]==101)
            D.resetForTests() -- process-local state gone, durable mission and world survive
            NOW=NOW+90000; observe()
            assert(m.delivered==0 and #inv.items==2,'offline time is not an unseen timer')
            NOW=NOW+9999; observe(); assert(m.delivered==0)
            NOW=NOW+2; observe(); assert(m.delivered==2)
        """)

    def test_replacing_goods_restarts_delay_using_stable_item_ids(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart(); NOW=NOW+9000
            replacement=item(999); inv.items[1]=replacement; replacement.owner=inv
            observe(); NOW=NOW+2000; observe()
            assert(m.delivered==0,'equal item types must not preserve an old collection timer')
            NOW=NOW+8001; observe(); assert(m.delivered==2)
        """)

    def test_prepared_save_failure_preserves_all_goods(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart()
            -- Candidate was persisted; only the later write-ahead save now fails.
            assert(m.depositCandidate); SAVE_OK=false; elapsed()
            assert(m.pickup==nil and m.delivered==0 and #inv.items==2 and SYNC==0)
        """)

    def test_prepared_transaction_missing_goods_fails_closed(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart()
            m.pickup={mode='box',ids={101,102},before=0,count=2,status='prepared'}
            inv:DoRemoveItem(goods[1]); D.resetForTests(); observe(); elapsed()
            assert(m.delivered==0 and #inv.items==1 and SYNC==0)
            assert(m.pickup.error=='missing_items')
        """)

    def test_prepared_transaction_missing_bag_fails_closed(self):
        self.setup_delivery('bag')
        self.run_lua("""
            add_goods(); depart()
            m.pickup={mode='bag',bag=200,ids={101,102},before=0,count=2,status='prepared'}
            sq.world={}; D.resetForTests(); observe(); elapsed()
            assert(m.delivered==0 and m.pickup.error=='missing_bag')
        """)

    def test_failed_engine_container_removal_is_not_credited(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart(); inv.DoRemoveItem=function() end
            elapsed(); assert(m.delivered==0 and #inv.items==2)
            assert(m.pickup.error=='item_remove_failed')
        """)

    def test_failed_engine_world_removal_is_not_credited(self):
        self.setup_delivery('bag')
        self.run_lua("""
            add_goods(); depart(); sq.transmitRemoveItemFromSquare=function() return -1 end
            elapsed(); assert(m.delivered==0 and #sq.world==1)
            assert(m.pickup.error=='bag_remove_failed')
        """)

    def test_original_box_is_found_after_object_indices_shift(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods()
            local other=box(sq,container({item(901),item(902)}))
            table.insert(sq.objects,1,table.remove(sq.objects,2))
            assert(sq.objects[1]==other and sq.objects[2]==obj)
            depart(); elapsed()
            assert(m.delivered==2 and #inv.items==0,'the original marked box must remain the target')
            assert(#other.inv.items==2,'a shifted index must never redirect collection to another box')
        """)

    def test_identical_replacement_box_preserves_its_existing_stock(self):
        self.setup_delivery()
        self.run_lua("""
            local replacement=box(sq,container({item(901),item(902)}))
            table.remove(sq.objects,1)
            assert(sq.objects[1]==replacement)
            depart(); elapsed()
            assert(m.delivered==0,'an identical replacement is not the agreed box')
            assert(#replacement.inv.items==2 and SYNC==0,'replacement household stock must remain untouched')
        """)

    def test_box_witness_distance_uses_actual_box_position(self):
        self.run_lua("""
            square(100,100,0); sq=square(103,100,0); inv=container(); box(sq,inv)
            m={id='offset-box',donor='voice',state='active',quantity=2,delivered=0,
                accepted={['Base.Bandage']=true},deposit={x=100,y=100,z=0,mode='box'}}
            assert(D.prepare(m,STORE))
            for id=101,102 do local it=item(id); inv.items[#inv.items+1]=it; it.owner=inv end
            PLAYERS[1].x=141
            D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            NOW=NOW+10001; D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            assert(m.delivered==0 and #inv.items==2,'38 tiles from the actual box is still a witness')
            PLAYERS[1].x=144; D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            NOW=NOW+10001; D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            assert(m.delivered==2,'41 tiles from the actual box permits collection')
        """)

    def test_bag_witness_distance_uses_actual_bag_position(self):
        self.setup_delivery('bag')
        self.run_lua("""
            local offset=square(103,100,0)
            goods={item(101),item(102)}
            bag=item(200,'Base.Bag_Schoolbag',container(goods)); ground(offset,bag)
            PLAYERS[1].x=141; observe(); elapsed()
            assert(m.delivered==0 and #offset.world==1,'38 tiles from the bag is still a witness')
            PLAYERS[1].x=144; observe(); elapsed()
            assert(m.delivered==2 and #offset.world==0)
        """)

    def test_ground_bag_taken_back_during_unseen_delay_is_not_credited(self):
        self.setup_delivery('bag')
        self.run_lua("""
            add_goods(); depart()
            sq.world={}; bag.world=nil
            PLAYERS[1].inv.items={bag}; bag.owner=PLAYERS[1].inv
            elapsed()
            assert(m.delivered==0 and REMOVED==0,'a taken-back bag is not a completed delivery')
            assert(#bag.bag.items==2 and PLAYERS[1].inv.items[1]==bag)
        """)


if __name__ == '__main__':
    unittest.main()

