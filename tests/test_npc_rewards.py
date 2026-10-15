"""NPC reward adapter: real surplus, living authority and shared withdrawal (Lua doubles)."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

MODULE = Path(__file__).resolve().parents[1] / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_NPCRewards.lua'

class NPCRewardsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        function isClient() return false end
        cfg={NPC_REWARD_TEACHES={medic='Doctor',fighter='Aiming'}}
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
          ['RadioSurvivor/RS_Reputation']={level=function() return reputation end},
          ['RadioSurvivor/RS_Rewards']={grant=function() granted=granted+1;return {kind='lesson'} end}}
        function require(n) return modules[n] end
        store={data={npcs={n=npc},characters={p={name='Player'}}},save=function() return true end}
        m={npc='n',state='success',participants={p=true,q=true},claimedBy='',revision=1}
        ''')
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

if __name__ == '__main__':
    unittest.main()
