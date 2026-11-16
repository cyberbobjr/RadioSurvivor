"""Goods asked by a radio voice `deliver` mission (E20-T16, ADR D04): `items=<category>` and `quantity=` of its section.

    python RadioSurvivor/tests/test_deliver_goods.py

A voice `deliver` mission whose section names a category accepts exactly the item types of that category (a
[category] section of the sheet first, else the shared catalogue personas/_categories.txt, through the one resolver
RS_Categories shared with the cache reward); `quantity=` (number or range) is drawn when the mission starts
(RS_MissionGoods.setRandom, injected generator) and kept on the mission. Without those keys the mission keeps the list
and the quantity of CA_MissionConfig (Bandage, RippedSheets; 6).
Integration: real RadioSurvivor_Server and CA_NotebookServer (bench of tests/test_carnet.py, VoiceMissionTests), real
sheet reader, real catalogue. Dead drops: the world doubles of tests/test_voice_delivery.py (real RS_DeadDrops, real
deliver template). Proof of the Lua logic, not of the Java API nor the network.
"""
from __future__ import annotations

import shutil
import unittest
from pathlib import Path

import test_carnet as carnet_helpers
from test_darlene_chain import CLINIC_WORLD
from test_voice_delivery import DropBench

ROOT = Path(__file__).resolve().parents[1]
PERSONAS = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'personas'
KHZ = 160000

SHEET = """format=1
id=scouter
name=Scout Voice
frequency=160.0
actions=say,start_mission
budget.start_mission=20
[place depot]
at=10600,9300,0
label=Fuel depot
use=drop
[mission snacks]
type=deliver
items=snacks
quantity=2-4
[mission meds]
type=deliver
items=medical
quantity=3
[mission plain]
type=deliver
[category snacks]
item=Base.Crisps:1
item=Base.Chocolate:2-3
[prompt]
You are Scout Voice, a voice of the offline test bench.
"""

MEDICAL = ['Base.Bandage', 'Base.Disinfectant', 'Base.Pills']


def keys(table):
    return sorted(k for k, v in table.items() if v is True)


class VoiceGoodsTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def world(self, name):
        sim = self.voice_sim(name, sheet=SHEET)
        shutil.copyfile(PERSONAS / '_categories.txt', sim.path / 'personas' / '_categories.txt')
        rt = sim.server.rt
        rt.execute(CLINIC_WORLD)  # squares of the drop not loaded: the drop waits for its first reading
        self.voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        self.store = rt.eval("require('CoreAI/CA_NotebookStore')")
        self.engine = rt.eval("require('CoreAI/CA_Missions')")
        self.goods = rt.eval("require('RadioSurvivor/RS_MissionGoods')")
        self.addCleanup(self.goods.setRandom, None)
        return sim

    def draw(self, value):
        """Generator random(n) -> 0..n-1 that always returns `value` (bounded to n - 1)."""
        self.goods.setRandom(lambda n: min(value, n - 1))

    def start(self, sim, section):
        sim.clock.offset += 1800001  # delay between two missions of the same voice (play time)
        sheet = sim.server.rt.eval("require('RadioSurvivor/RS_Personas').get('scouter')")
        m = self.voice.start(self.store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, KHZ, section)
        self.assertFalse(isinstance(m, tuple), f'{section}: {m}')
        return m

    def finish(self, sim, m):
        self.assertTrue(self.engine.finish(sim.state(), m, 'failed'))
        self.assertTrue(self.store.save())

    def test_sheet_category_and_range_are_applied_at_the_start(self):
        sim = self.world('goods-sheet')
        self.draw(0)
        low = self.start(sim, 'snacks')
        self.assertEqual(keys(low.accepted), ['Base.Chocolate', 'Base.Crisps'])
        self.assertEqual((low.quantity, low.delivered), (2, 0))
        self.finish(sim, low)
        self.draw(99)
        high = self.start(sim, 'snacks')
        self.assertEqual(high.quantity, 4, 'highest value of the range')
        saved = sim.state().missions[high.id]
        self.assertEqual((saved.quantity, keys(saved.accepted)), (4, ['Base.Chocolate', 'Base.Crisps']))

    def test_catalogue_category_and_fixed_quantity(self):
        sim = self.world('goods-catalogue')
        m = self.start(sim, 'meds')
        self.assertEqual(keys(m.accepted), MEDICAL)
        self.assertEqual(m.quantity, 3)

    def test_section_without_keys_keeps_the_configured_goods(self):
        sim = self.world('goods-plain')
        m = self.start(sim, 'plain')
        self.assertEqual(keys(m.accepted), ['Base.Bandage', 'Base.RippedSheets'])
        self.assertEqual(m.quantity, 6)

    def test_item_outside_the_category_is_refused_by_the_drop_strategy(self):
        sim = self.world('goods-refused')
        m = self.start(sim, 'meds')
        deliver, g = self.engine.template(m), sim.server.g
        self.assertTrue(deliver.dropAccepts(m, g.item('Base.Pills')))
        self.assertFalse(deliver.dropAccepts(m, g.item('Base.Hammer')), 'tools are not medical')
        self.assertFalse(deliver.dropAccepts(m, g.item('Base.RippedSheets')), 'configured list replaced')

    def test_voice_brief_and_notebook_show_the_real_goods(self):
        sim = self.world('goods-told')
        self.draw(1)
        m = self.start(sim, 'snacks')
        brief = self.engine.voiceBrief(m)
        self.assertIn('Leave 3 requested items', brief.job)
        self.assertIn('Accepted item types (closed server list): Base.Chocolate, Base.Crisps.', list(brief.facts.values()))
        self.assertIn('Collected by the server: 0 of 3', brief.facts[3])
        p = self.engine.projection(m, sim.character('alice'))
        self.assertEqual((p.quantity, keys(p.accepted)), (3, ['Base.Chocolate', 'Base.Crisps']))

    def test_cache_reward_and_goods_resolve_categories_in_one_place(self):
        sim = self.world('goods-resolver')
        rt = sim.server.rt
        sheet = rt.eval("require('RadioSurvivor/RS_Personas').get('scouter')")
        categories = rt.eval("require('RadioSurvivor/RS_Categories')")
        self.assertTrue(rt.eval("require('RadioSurvivor/Rewards/RS_Reward_Cache').category"
                                " == require('RadioSurvivor/RS_Categories').of"), 'the cache reward uses the shared resolver')
        self.assertEqual(categories.of(sheet, 'snacks').id, 'snacks', 'own section of the sheet first')
        self.assertEqual(categories.of(sheet, 'medical').id, 'medical', 'then the shared catalogue')
        self.assertIsNone(categories.of(sheet, 'weapons'))


GOODS_PATHS = "package.preload['RadioSurvivor/RS_Personas'] = function() return {rules = function() return {categories = {}} end} end"


class DropGoodsTests(DropBench):
    """Real dead drop of a mission set up from a section with items= and quantity= (RS_MissionGoods)."""

    def test_category_items_counted_up_to_the_drawn_quantity(self):
        self.run_lua(GOODS_PATHS)
        self.run_lua("""
            G = require('RadioSurvivor/RS_MissionGoods')
            G.setRandom(function(n) return 1 end)
            sheet = {id='v', categories={snacks={id='snacks', items={{type='Base.Crisps', min=1, max=1},
                {type='Base.Chocolate', min=1, max=2}}}}}
            sq=square(100,100,0); inv=container(); box(sq,inv)
            m={id='goods',template='deliver',donor='voice',state='active',quantity=6,delivered=0,
                accepted={['Base.Bandage']=true},drops={{id='a',label='A',x=100,y=100,z=0,mode='box'}}}
            SETUPS.askFor.apply(m, sheet, {missionCount=1}, {type='deliver', params={items='snacks',
                quantity={min=2, max=4}}})
            assert(m.quantity==3, 'drawn quantity '..tostring(m.quantity))
            assert(D.prepare(m,m.drops[1],STORE))
            for i, kind in ipairs({'Base.Hammer', 'Base.Crisps', 'Base.Bandage', 'Base.Chocolate', 'Base.Crisps',
                    'Base.Chocolate'}) do
                local it=item(100+i, kind); inv.items[#inv.items+1]=it; it.owner=inv
            end
            local function observe() D.observe(m,PLAYERS[1],'alice',STATE,STORE) end
            observe(); PLAYERS[1].x=300; observe(); HOURS=HOURS+6.01; observe()
        """)
        self.assertEqual(self.rt.eval('m.delivered'), 3)
        left = self.rt.eval('(function() local t={} for _,it in ipairs(inv.items) do t[#t+1]=it:getFullType() end '
                            'return table.concat(t, ",") end)()')
        self.assertEqual(left, 'Base.Hammer,Base.Bandage,Base.Chocolate', 'outside the category or beyond the quantity')

    def test_section_without_keys_changes_nothing(self):
        self.run_lua(GOODS_PATHS)
        self.run_lua("""
            G = require('RadioSurvivor/RS_MissionGoods')
            m={id='plain',template='deliver',donor='voice',state='active',quantity=6,delivered=0,
                accepted={['Base.Bandage']=true}}
            assert(SETUPS.askFor.check({id='v'}, {type='deliver', params={}}))
            SETUPS.askFor.apply(m, {id='v'}, {missionCount=1}, {type='deliver', params={}})
            SETUPS.askFor.apply(m, {id='v'}, {missionCount=1}, nil)
        """)
        self.assertEqual(self.rt.eval('m.quantity'), 6)
        self.assertEqual(self.rt.eval('m.accepted["Base.Bandage"]'), True)


if __name__ == '__main__':
    unittest.main(verbosity=1)
