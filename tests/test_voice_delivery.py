"""Dead drops of the radio voices (E20-T05, E20-T06, ADR D06; unit RS_DeadDrops), real Lua with isolated Lua 5.1 engine doubles.

A voice `deliver` mission carries all its drops; deposits at several drops add up, each item credited once. A drop is
collected only out of everyone's view (RS_OutOfSight: 100 tiles, or square not loaded) and after a delay in game hours
(CA_GameClock, real modules). These tests prove server logic, not Java API compatibility or network delivery; the
doubles only define methods that exist in the game (GameTime.getWorldAgeHours, getMinutesPerDay, ItemContainer...).
"""
from pathlib import Path
import unittest

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server'
MODULE = SERVER / 'RadioSurvivor/RS_DeadDrops.lua'
CORE = ROOT / 'Contents/mods/batman_CoreAI/42.21/media/lua'

WORLD = r'''
NOW, HOURS, SAVES, SAVE_OK, SYNC, REMOVED = 100000, 50, 0, true, 0, 0
function isClient() return false end
function isServer() return true end
function getTimestampMs() return NOW end
-- GameTime.java: getWorldAgeHours (world age, game hours), getMinutesPerDay (DayLength).
GAMETIME = {getWorldAgeHours=function() return HOURS end, getMinutesPerDay=function() return 90 end}
function getGameTime() return GAMETIME end
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
    function c:DoRemoveItem(it)
        for i,v in ipairs(self.items) do if v==it then table.remove(self.items,i); it.owner=nil; return end end
    end
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
    function o:getSquare() return sq end
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
    return p
end
PLAYERS={player(100,100)}
function getOnlinePlayers() return list(PLAYERS) end
function getNumActivePlayers() return #PLAYERS end
function getSpecificPlayer(i) return PLAYERS[i+1] end
function sendRemoveItemFromContainer(c,it) SYNC=SYNC+1 end
STORE={save=function() SAVES=SAVES+1; return SAVE_OK end}
STATE={}
CONFIG={DeadDrops={radius=3,collectDelayHours=6,maxItems=200}}
package.preload['RadioSurvivor/RS_Config']=function() return CONFIG end
package.preload['RadioSurvivor/RS_State']=function() return STORE end
SETUPS={}
package.preload['RadioSurvivor/RS_MissionVoice']=function()
    return {registerDeclaredSetup=function(field, setup) SETUPS[field]=setup; return setup end}
end
'''


class DropBench(unittest.TestCase):
    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.rt.execute(WORLD)
        paths = [SERVER, SERVER.parent / 'shared', CORE / 'server', CORE / 'shared']
        self.rt.execute('package.path = [[' + ';'.join(p.as_posix() + '/?.lua' for p in paths)
                        + ';]] .. package.path')
        self.load_module()

    def load_module(self):
        """Fresh module (a restart): only the saved mission and the world remain."""
        self.rt.globals().D = self.rt.execute(MODULE.read_text(encoding='utf-8-sig'))

    def run_lua(self, source):
        self.rt.execute(source)

    def setup_delivery(self, mode='box', quantity=2):
        self.run_lua("""
            sq=square(100,100,0); inv=container(); obj=box(sq,inv)
            m={id='mission1',donor='voice',state='active',quantity=%d,delivered=0,
                accepted={['Base.Bandage']=true},participants={p={name='alice'}},
                drops={{id='a',label='Drop A',x=100,y=100,z=0,mode='%s'}}}
            assert(D.prepare(m,m.drops[1],STORE))
            function observe() return D.observe(m,PLAYERS[1],'alice',STATE,STORE) end
            function add_goods(n)
                goods={}
                for i=1,(n or 2) do goods[i]=item(100+i) end
                if m.drops[1].mode=='bag' then
                    bag=item(200,'Base.Bag_Schoolbag',container(goods)); ground(sq,bag)
                else
                    for _,it in ipairs(goods) do inv.items[#inv.items+1]=it; it.owner=inv end
                end
            end
            function depart() PLAYERS[1].x=250; observe() end
            function elapsed() HOURS=HOURS+6.01; observe() end
        """ % (quantity, mode))


class CollectionRuleTests(DropBench):
    def test_box_only_collected_out_of_view_after_six_game_hours(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); HOURS=HOURS+30; observe()
            assert(m.delivered==0 and #inv.items==2,'a player in view blocks collection')
            depart(); HOURS=HOURS+5.9; observe()
            assert(m.delivered==0 and #inv.items==2,'collected before the delay')
            HOURS=HOURS+0.2; observe()
            assert(m.delivered==2 and #inv.items==0,'complete hidden collection required')
            assert(SYNC==2,'container removals must be synchronized')
            elapsed(); assert(m.delivered==2 and SYNC==2,'collection must be idempotent')
        """)

    def test_player_within_one_hundred_tiles_is_a_witness_on_any_level(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart()
            PLAYERS[2]=player(199,1,4); elapsed()
            assert(m.delivered==0 and #inv.items==2,'99 tiles away on another floor still sees the drop')
            PLAYERS[2].x=201; observe(); elapsed()
            assert(m.delivered==2,'101 tiles away is out of view')
        """)

    def test_paused_game_stops_the_delay(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart(); NOW=NOW+48*3600*1000; observe()
            assert(m.delivered==0,'real time alone never collects')
            elapsed(); assert(m.delivered==2)
        """)

    def test_faster_game_shortens_the_real_wait(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart()
            -- x3: 6 game hours pass in 7.5 real minutes (90 min per day).
            NOW=NOW+450000; HOURS=HOURS+6.01; observe()
            assert(m.delivered==2,'game hours count, whatever the real time')
        """)

    def test_return_in_view_before_the_delay_resets_it(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart(); HOURS=HOURS+5
            PLAYERS[1].x=150; observe()
            assert(m.delivered==0 and #inv.items==2,'never collected in front of a player')
            depart(); HOURS=HOURS+5; observe()
            assert(m.delivered==0,'the full delay restarts after a witness')
            HOURS=HOURS+1.01; observe(); assert(m.delivered==2)
        """)

    def test_mission_delay_overrides_the_default(self):
        self.setup_delivery()
        self.run_lua("""
            m.collectHours=1; add_goods(); depart(); HOURS=HOURS+1.01; observe()
            assert(m.delivered==2,'collect_hours of the mission section')
        """)

    def test_unloaded_drop_is_collected_at_the_first_loaded_pass_once_due(self):
        """Solo: the drop square unloads far from the player; the delay elapses out of view, the pickup is applied
        when the square is loaded again (the player then stands at the edge of the loaded area)."""
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe()
            PLAYERS[1].x=400; LOADED=false; observe(); elapsed()
            assert(m.delivered==0 and #inv.items==2,'nothing removed from an unloaded square')
            assert(m.drops[1].due==true,'pickup due while nobody can watch')
            LOADED=true; PLAYERS[1].x=170; observe()
            assert(m.delivered==2 and #inv.items==0,'collected at the first pass once loaded')
            assert(m.drops[1].due==nil)
        """)

    def test_unloaded_drop_before_the_delay_is_not_due(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); PLAYERS[1].x=400; LOADED=false; observe(); HOURS=HOURS+3; observe()
            LOADED=true; PLAYERS[1].x=170; observe()
            assert(m.delivered==0 and not m.drops[1].due,'back in view before the delay: nothing collected')
        """)

    def test_restart_keeps_the_wait_saved_with_the_mission(self):
        self.setup_delivery()
        self.run_lua("add_goods(); depart(); HOURS=HOURS+4; observe()")
        self.load_module()
        self.run_lua("""
            HOURS=HOURS+2.01; observe()
            assert(m.delivered==2,'the wait started before the restart counts')
        """)


class DepositTests(DropBench):
    def test_two_drops_partial_deposits_add_up_and_are_credited_once(self):
        self.run_lua("""
            sqa=square(100,100,0); inv=container(); box(sqa,inv)
            sqb=square(130,100,0)
            m={id='two',donor='voice',state='active',quantity=2,delivered=0,accepted={['Base.Bandage']=true},
                drops={{id='a',label='Drop A',x=100,y=100,z=0,mode='box'},
                       {id='b',label='Drop B',x=130,y=100,z=0,mode='bag'}}}
            assert(D.prepare(m,m.drops[1],STORE) and D.prepare(m,m.drops[2],STORE))
            assert(m.drops[1].mode=='box' and m.drops[2].mode=='bag')
            a=item(101); inv.items={a}; a.owner=inv
            bag=item(200,'Base.Bag_Schoolbag',container({item(102)})); ground(sqb,bag)
            local function observe() D.observe(m,PLAYERS[1],'alice',STATE,STORE) end
            observe(); PLAYERS[1].x=300; observe(); HOURS=HOURS+6.01; observe()
            assert(m.delivered==2,'one item at each drop adds up to the quantity')
            assert(#inv.items==0 and #sqb.world==0 and REMOVED==1)
            assert(m.credited['101'] and m.credited['102'])
            HOURS=HOURS+7; observe(); assert(m.delivered==2,'credited once')
        """)

    def test_partial_deposits_add_up_over_time(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(1); depart(); elapsed()
            assert(m.delivered==1 and #inv.items==0,'a partial deposit is collected and counted')
            PLAYERS[1].x=100; observe()
            local it=item(150); inv.items={it}; it.owner=inv
            depart(); elapsed(); assert(m.delivered==2)
        """)

    def test_existing_household_stock_and_excess_goods_are_preserved(self):
        self.run_lua("""
            sq=square(100,100,0); old=item(1); inv=container({old}); box(sq,inv)
            m={id='baseline',donor='voice',state='active',quantity=2,delivered=0,
                accepted={['Base.Bandage']=true},drops={{id='a',label='A',x=100,y=100,z=0,mode='box'}}}
            assert(D.prepare(m,m.drops[1],STORE))
            for id=101,103 do local it=item(id); inv.items[#inv.items+1]=it; it.owner=inv end
            PLAYERS[1].x=250
            D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            HOURS=HOURS+6.01; D.observe(m,PLAYERS[1],'alice',STATE,STORE)
            assert(m.delivered==2 and #inv.items==2)
            assert(inv:getItemWithIDRecursiv(1)==old,'existing stock must never be taken')
            assert(inv:getItemWithIDRecursiv(103),'excess deposited goods must remain')
        """)

    def test_restored_world_after_a_restart_is_never_credited_twice(self):
        self.setup_delivery()
        self.run_lua("add_goods(); depart(); elapsed(); assert(m.delivered==2)")
        self.load_module()
        self.run_lua("""
            -- The world was not saved after the pickup: the same items are back in the box.
            for _,it in ipairs(goods) do inv.items[#inv.items+1]=it; it.owner=inv end
            m.delivered=1   -- and the mission had a second deposit to collect
            PLAYERS[1].x=100; observe(); depart(); elapsed()
            assert(m.delivered==1 and #inv.items==2,'credited item ids are never counted again')
        """)

    def test_failed_save_does_not_consume(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart(); SAVE_OK=false; elapsed()
            assert(m.delivered==0 and #inv.items==2 and SYNC==0,'save must precede destruction')
        """)

    def test_goods_taken_back_before_collection_are_not_credited(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); observe(); depart()
            PLAYERS[1].inv.items={goods[1]}; goods[1].owner=PLAYERS[1].inv
            inv.items={goods[2]}; elapsed()
            assert(m.delivered==1 and #inv.items==0 and SYNC==1,'only the item left at the drop counts')
        """)

    def test_interrupted_pickup_credits_the_items_gone_from_the_box(self):
        """E23-T04 (ADR D09): a stop between the removal and the record; at the restart, the items of the journal
        that disappeared are counted as delivered, the others stay at the drop for a later pickup."""
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart()
            m.drops[1].pickup={ids={101,102}}
            inv:DoRemoveItem(goods[1])
        """)
        self.load_module()
        self.run_lua("""
            observe()
            assert(m.drops[1].pickup==nil,'journal settled at the first loaded pass')
            assert(m.delivered==1 and m.credited['101'] and not m.credited['102'],'the vanished item is delivered')
            HOURS=HOURS+6.01; observe(); assert(m.delivered==2,'the goods still there are collected later')
            HOURS=HOURS+7; observe(); assert(m.delivered==2,'never credited twice')
        """)

    def test_interrupted_pickup_credits_a_bag_gone_from_the_floor(self):
        self.setup_delivery(mode='bag')
        self.run_lua("""
            add_goods(); depart()
            m.drops[1].pickup={ids={101,102}}
            sq:transmitRemoveItemFromSquare(bag.world)
        """)
        self.load_module()
        self.run_lua("""
            observe()
            assert(m.drops[1].pickup==nil and m.delivered==2,'the whole bag vanished: both items delivered')
        """)

    def test_interrupted_pickup_with_everything_still_there_credits_nothing(self):
        self.setup_delivery(mode='bag')
        self.run_lua("add_goods(); depart(); m.drops[1].pickup={ids={101,102}}")
        self.load_module()
        self.run_lua("""
            observe()
            assert(m.drops[1].pickup==nil and m.delivered==0,'world saved before the removal: nothing delivered')
            HOURS=HOURS+6.01; observe(); assert(m.delivered==2 and #sq.world==0,'collected again later')
        """)

    def test_interrupted_pickup_waits_for_its_square(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart()
            m.drops[1].pickup={ids={101,102}}
            inv:DoRemoveItem(goods[1]); inv:DoRemoveItem(goods[2])
            LOADED=false
        """)
        self.load_module()
        self.run_lua("""
            observe()
            assert(m.drops[1].pickup~=nil and m.delivered==0,'nothing decided while the square is not loaded')
            LOADED=true; observe()
            assert(m.drops[1].pickup==nil and m.delivered==2)
        """)

    def test_failed_engine_container_removal_is_not_credited(self):
        self.setup_delivery()
        self.run_lua("""
            add_goods(); depart(); inv.DoRemoveItem=function() end
            elapsed(); assert(m.delivered==0 and #inv.items==2 and not m.credited['101'])
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
            depart(); elapsed()
            assert(m.delivered==0,'an identical replacement is not the agreed box')
            assert(#replacement.inv.items==2 and SYNC==0,'replacement household stock must remain untouched')
        """)


class BagTests(DropBench):
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

    def test_bag_with_more_than_the_rest_is_not_taken(self):
        self.setup_delivery('bag')
        self.run_lua("""
            add_goods(3); observe(); depart(); elapsed()
            assert(m.delivered==0 and #sq.world==1,'excess goods would vanish with the bag')
        """)

    def test_failed_engine_world_removal_is_not_credited(self):
        self.setup_delivery('bag')
        self.run_lua("""
            add_goods(); depart(); sq.transmitRemoveItemFromSquare=function() return -1 end
            elapsed(); assert(m.delivered==0 and #sq.world==1)
        """)


class SetUpTests(DropBench):
    """Set-up registered for the templates declaring dropAccepts (RS_MissionVoice.registerDeclaredSetup), here a
    voice `deliver`: all the drops of the section."""

    SHEET = """
        local function place(id, x) return {id=id, label='Label '..id, x=x, y=100, z=0} end
        -- E25-T01: shared places of the sheet (id -> place); the section names its drops.
        sheet={id='v', places={a=place('a',100), m=place('m',300), b=place('b',130), c=place('c',160)}}
        ALL={type='deliver', drops={'a','b','c'}, params={}}
        square(100,100,0); square(130,100,0); square(160,100,0)
        donor={missionCount=1}
        function setUp(section)
            local mission={id='new',donor='voice',quantity=2,delivered=0,accepted={['Base.Bandage']=true}}
            SETUPS.dropAccepts.apply(mission, sheet, donor, section)
            return mission
        end
    """

    def ids(self, expr):
        drops = self.rt.eval(expr)
        return [drops[i].id for i in range(1, len(drops) + 1)]

    def test_section_list_gives_those_drops(self):
        self.run_lua(self.SHEET + "M = setUp({type='deliver', drops={'c','a'}, params={}})")
        self.assertEqual(self.ids('M.drops'), ['c', 'a'])
        self.assertEqual(self.rt.eval('M.drops[1].label'), 'Label c')
        self.assertTrue(self.rt.eval('M.drops[1].ready and M.drops[2].ready'))

    def test_collect_hours_of_the_section_or_the_default(self):
        self.run_lua(self.SHEET + "M = setUp({type='deliver', drops={}, params={collect_hours=2}}); N = setUp(nil)")
        self.assertEqual(self.rt.eval('M.collectHours'), 2)
        self.assertEqual(self.rt.eval('N.collectHours'), 6)

    def test_sheet_without_drop_place_is_refused(self):
        self.run_lua("R = {SETUPS.dropAccepts.check({id='v', places={}}, {type='deliver', drops={'a'}})}")
        self.assertEqual(self.rt.eval('R[2]'), 'no_place')

    def test_notebook_projection_lists_every_drop_and_its_map_zone(self):
        self.run_lua(self.SHEET + """
            M = setUp(ALL)
            P = {engaged=true}; D.project(M, P)
            Q = {engaged=false}; D.project(M, Q)
        """)
        self.assertEqual(self.rt.eval('#P.drops'), 3)
        self.assertEqual(self.rt.eval('P.drops[2].label'), 'Label b')
        self.assertEqual(self.rt.eval('#P.dropZones'), 3)
        self.assertEqual(self.rt.eval('P.dropZones[3].label'), 'Label c')
        self.assertEqual(self.rt.eval('P.collectHours'), 6)
        self.assertIsNone(self.rt.eval('Q.dropZones'), 'map zones only for a participant')

    def test_rule_told_to_the_voice(self):
        self.run_lua(self.SHEET + "M = setUp(ALL); RULE = D.rule(M); WHERE = D.where(M)")
        rule = self.rt.eval('RULE')
        self.assertIn('out of sight of everyone', rule)
        self.assertIn('about 6 game hours', rule)
        self.assertEqual(self.rt.eval('WHERE'), 'Label a, Label b, Label c')


if __name__ == '__main__':
    unittest.main()
