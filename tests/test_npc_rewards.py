"""NPC reward adapter: real surplus, living authority and shared withdrawal (Lua doubles).

RadioSurvivor's adapter (RS_NPCRewards) and the lot of Living Knox alone (LK_MissionRewards, E18-T29): both take the
same household surplus (LivingKnox.MissionRewards.take).
"""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_NPCRewards.lua'
LK_REWARDS = ROOT / 'Contents/mods/batman_LivingKnox/42.21/media/lua/server/LivingKnox/LK_MissionRewards.lua'

class NPCRewardsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        function isClient() return false end
        cfg={NPC_REWARD_TEACHES={medic='Doctor',fighter='Aiming'},NPC_REWARD_TABLES={settlers='tools',neutrals='food',raiders='ammo'}}
        relation='trusting'; reputation='good'; item={getActualWeight=function() return 1 end}
        g={type='settlers',home={x=1,y=2,z=0},members={m={alive=true,role='medic'}}}
        npc={id='n',incarnation='npc-1'}
        assessment={ration=0,next=0,have={medical=3},want={medical=2}}
        taken=0; granted=0
        LivingKnox={Groups={findNpc=function() return 'grp-1','m' end,get=function() return g end},Stock={
          needs=function() return assessment end,categoryOf=function() return 'medical' end,
          takeItem=function(_,pred) if not pred(item) then return nil,'none' end
            taken=taken+1;return {i=1},item end}}
        modules={['RadioSurvivor/RS_NPCProvider']={npc=function() return {group='grp-1'} end},
          ['RadioSurvivor/RS_Config']=cfg,
          ['RadioSurvivor/RS_Relations']={view=function() return {level=relation} end},
          ['RadioSurvivorCore/RC_Reputation']={level=function() return reputation end},
          ['RadioSurvivor/RS_Rewards']={grant=function() granted=granted+1;return {kind='lesson'} end}}
        function require(n) return modules[n] end
        function isServer() return false end
        store={data={npcs={n=npc},characters={p={name='Player'}}},save=function() return true end}
        m={npc='n',state='success',participants={p=true,q=true},claimedBy='',revision=1}
        ''')
        self.lk = self.lua.execute(LK_REWARDS.read_text(encoding='utf-8-sig'))
        self.n = self.lua.execute(MODULE.read_text(encoding='utf-8-sig'))

    def test_surplus_is_same_real_item(self):
        item, _ = self.n.takeMaterial(self.lua.globals().npc, 'p')
        self.assertEqual(self.lua.globals().taken, 1)
        self.assertTrue(self.lua.eval('function(x) return x == item end')(item))

    def test_rations_and_target_reserves_are_protected(self):
        for change in ('assessment.ration=1', 'assessment.ration=0;assessment.next=1',
                       'assessment.next=0;assessment.have.medical=2'):
            self.lua.execute(change)
            self.n.takeMaterial(self.lua.globals().npc, 'p')
        self.assertEqual(self.lua.globals().taken, 0)

    def test_dead_requester_and_capacity_are_protected(self):
        self.lua.execute('g.members.m.alive=false')
        self.assertIsNone(self.n.resolve(self.lua.globals().npc)[0])
        self.lua.execute('''g.members.m.alive=true; player={getInventory=function() return {
          getCapacityWeight=function() return 5 end,getEffectiveCapacity=function() return 5 end} end}''')
        self.n.takeMaterial(self.lua.globals().npc, 'p', self.lua.globals().player)
        self.assertEqual(self.lua.globals().taken, 0)

    def test_relation_reputation_and_raider_lesson_filter(self):
        source = self.n.describe(self.lua.globals().npc, 'p')
        self.assertEqual(source.teaches, 'Doctor')
        self.lua.execute("g.type='raiders'")
        self.assertIsNone(self.n.describe(self.lua.globals().npc, 'p').teaches)
        self.lua.execute("relation='wary'")
        self.assertEqual(len(self.n.describe(self.lua.globals().npc, 'p').rewards), 1)

    def test_shared_lot_reserved_before_effect(self):
        self.lua.execute('''modules['RadioSurvivor/RS_Rewards'].grant=function()
          assert(m.claimedBy=='p' and m.transaction.stage=='prepared');granted=granted+1;return {} end''')
        self.assertTrue(self.n.claim(self.lua.globals().store, self.lua.globals().m, None, 'p', 't'))
        ok, _ = self.n.claim(self.lua.globals().store, self.lua.globals().m, None, 'q', 'u')
        self.assertFalse(ok)
        self.assertEqual(self.lua.globals().granted, 1)

    def test_save_failure_prevents_reward(self):
        self.lua.execute('store.save=function() return false end')
        ok, why = self.n.claim(self.lua.globals().store, self.lua.globals().m, None, 'p', 't')
        self.assertFalse(ok)
        self.assertEqual(why, 'Storage')
        self.assertEqual(self.lua.globals().granted, 0)

class AloneRewardTests(unittest.TestCase):
    """Lot of an NPC of Living Knox alone (E18-T29): a household surplus item in hand, else the common lot."""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        function isClient() return false end
        function isServer() return false end
        config={NPC_REWARD_TABLES={settlers='tools'},Caches={tables={tools={{'Base.Hammer',1},{'Base.Nails',3}},
          food={{'Base.TinnedBeans',2}}}}}
        function require(name) if name=='RadioSurvivorCore/RC_MissionConfig' then return config end return nil end
        nextId=100
        function instanceItem(t) nextId=nextId+1; local id=nextId
          return {getActualWeight=function() return 1 end,getID=function() return id end,
                  getFullType=function() return t end} end
        added = {}
        item={getActualWeight=function() return 1 end,getID=function() return 77 end,
              getFullType=function() return 'Base.Bandage' end}
        g={type='settlers',home={x=1,y=2,z=0},members={m={alive=true,role='medic'}}}
        assessment={ration=0,next=0,have={medical=3},want={medical=2}}
        taken=0
        LivingKnox={Groups={findNpc=function() return 'grp-1','m' end,get=function() return g end},Stock={
          needs=function() return assessment end,categoryOf=function() return 'medical' end,
          takeItem=function(_,pred) if not pred(item) then return nil,'none' end
            assert(m.transaction and m.transaction.stage=='prepared')
            taken=taken+1;return {i=1},item end}}
        player={getInventory=function() return {getCapacityWeight=function() return 0 end,
          getEffectiveCapacity=function() return 50 end,AddItem=function(_, it) added[#added+1]=it; return it end} end}
        saves=0
        store={data={},save=function() saves=saves+1 return true end}
        m={npc='lk-1',state='success',participants={p={name='Ann'},q={name='Bob'}},claimedBy='',revision=1,
           rewardCount=0,rewardType=''}
        ''')
        self.r = self.lua.execute(LK_REWARDS.read_text(encoding='utf-8-sig'))
        self.g = self.lua.globals()

    def claim(self, who='p', token='t'):
        return self.r.claim(self.g.store, self.g.m, self.g.player, who, token)

    def test_household_item_given_once_to_the_group(self):
        ok = self.claim()
        self.assertEqual(ok, True)
        self.assertEqual(self.g.taken, 1)
        self.assertEqual(len(self.g.added), 1)
        self.assertEqual(self.g.m.claimedBy, 'p')
        self.assertEqual(self.g.m.claimedName, 'Ann')
        self.assertEqual(self.g.m.householdItem, 'Base.Bandage')
        self.assertIsNone(self.g.m.transaction)
        ok, why = self.claim('q', 'u')
        self.assertEqual((ok, why), (False, 'State'))
        self.assertEqual(self.g.taken, 1)

    def test_no_surplus_falls_back_to_the_announced_lot(self):
        self.lua.execute("assessment.ration=1; m.rewardCount=2; m.rewardType='Base.Pills'")
        self.assertIsNone(self.r.lot(self.g.m))
        self.assertIsNone(self.claim())
        self.assertIsNone(self.g.m.transaction)
        self.assertEqual(self.g.m.claimedBy, '')

    def test_no_surplus_nor_announced_lot_creates_the_lot_of_the_group_type(self):
        """E18-T33: settlers -> tools, every item of the table in the inventory, once for the group."""
        self.lua.execute('assessment.ration=1')
        self.assertEqual(self.r.lot(self.g.m), 'tools')
        self.assertEqual(self.claim(), True)
        got = [it.getFullType() for it in self.g.added.values()]
        self.assertEqual(sorted(got), ['Base.Hammer'] + ['Base.Nails'] * 3)
        self.assertEqual((self.g.m.claimedBy, self.g.m.createdLot), ('p', 'tools'))
        self.assertIsNone(self.g.m.transaction)
        self.assertEqual(self.claim('q', 'u'), (False, 'State'))
        self.assertEqual(len(self.g.added), 4)

    def test_created_lot_unknown_type_is_food_and_too_heavy_is_refused(self):
        self.lua.execute("assessment.ration=1; g.type='traders'")
        self.assertEqual(self.r.lot(self.g.m), 'food')
        self.lua.execute('player.getInventory=function() return {getCapacityWeight=function() return 49 end,'
                         'getEffectiveCapacity=function() return 50 end,AddItem=function(_, it) added[#added+1]=it; return it end} end')
        self.assertEqual(self.claim(), (False, 'Capacity'))
        self.assertEqual(len(self.g.added), 0)
        self.assertEqual(self.g.m.claimedBy, '')

    def test_dead_requester_has_no_created_lot(self):
        self.lua.execute('g.members.m.alive=false')
        self.assertIsNone(self.r.lot(self.g.m))
        self.assertIsNone(self.claim())

    def test_supply_lot_paid_at_completion_is_the_common_lot(self):
        self.lua.execute("m.supply={ref='grp-1'}; m.rewardCount=2")
        self.assertIsNone(self.claim())
        self.assertEqual(self.g.taken, 0)

    def test_dead_requester_falls_back_and_storage_failure_takes_nothing(self):
        self.lua.execute('g.members.m.alive=false')
        self.assertIsNone(self.claim())
        self.lua.execute('g.members.m.alive=true; store.save=function() return false end')
        ok, why = self.claim()
        self.assertEqual((ok, why), (False, 'Storage'))
        self.assertEqual(self.g.taken, 0)


if __name__ == '__main__':
    unittest.main()
