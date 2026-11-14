"""Reward of a mission given by a Living Knox NPC (LK_MissionRewards, E18-T29; E11-T21, decision D09).

Each mod pays its missions: the lot of a Living Knox NPC is Living Knox's (household surplus, else the announced lot,
else the created lot), alone or with RadioSurvivor. With both mods the "npc" giver of RadioSurvivor (RS_MissionHooks)
delegates the claim of an engine NPC fiche to the reward source Living Knox registers in the core engine
(RC_Missions.registerNpcReward).
"""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents/mods'
LK_REWARDS = MODS / 'batman_LivingKnox/42.21/media/lua/server/LivingKnox/LK_MissionRewards.lua'

class AloneRewardTests(unittest.TestCase):
    """Lot of an NPC of Living Knox alone (E18-T29): a household surplus item in hand, else the common lot."""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        function isClient() return false end
        function isServer() return false end
        config={NPC_REWARD_TABLES={settlers='tools'},Caches={tables={tools={{'Base.Hammer',1},{'Base.Nails',3}},
          food={{'Base.TinnedBeans',2}}}}}
        registered=nil
        missions={registerNpcReward=function(source) registered=source end}
        function require(name)
          if name=='RadioSurvivorCore/RC_MissionConfig' then return config end
          if name=='RadioSurvivorCore/RC_Missions' then return missions end
          return nil
        end
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


# Real core engine, real Living Knox lot and real RadioSurvivor givers; Living Knox groups and stock are doubles
# (one living member 'm' of 'grp-1', engine id 'lk-1', the incarnation of the notebook fiche 'n').
BOTH_MODS = r"""
function isClient() return false end
function isServer() return false end
nextId = 100
function instanceItem(t) nextId = nextId + 1; local id = nextId
  return {getActualWeight=function() return 1 end, getID=function() return id end, getFullType=function() return t end} end
item = {getActualWeight=function() return 1 end, getID=function() return 77 end,
        getFullType=function() return 'Base.Bandage' end}
g = {type='settlers', home={x=1,y=2,z=0}, members={m={alive=true, role='medic'}}}
assessment = {ration=0, next=0, have={medical=3}, want={medical=2}}
taken = 0
LivingKnox = {Groups={findNpc=function(id) if id == 'lk-1' then return 'grp-1', 'm' end return nil end,
                      get=function(gid) if gid == 'grp-1' then return g end return nil end},
  Stock={needs=function() return assessment end, categoryOf=function() return 'medical' end,
    takeItem=function(_, pred) if not pred(item) then return nil, 'none' end
      assert(m.transaction and m.transaction.stage == 'prepared', 'stock taken before the write-ahead marker')
      taken = taken + 1; return {i=1}, item end}}
function makePlayer() local added = {}
  return {added=added, getInventory=function() return {getCapacityWeight=function() return 0 end,
    getEffectiveCapacity=function() return 50 end, AddItem=function(_, it) added[#added+1] = it; return it end} end} end
alice, bob = makePlayer(), makePlayer()
modules = {['RadioSurvivor/RS_NPCProvider'] = {available=function() return true end}}
local roots = {}
for _, mod in ipairs({'batman_RadioSurvivorCore', 'batman_RadioSurvivor', 'batman_LivingKnox'}) do
  for _, side in ipairs({'shared', 'server'}) do roots[#roots+1] = MODS .. '/' .. mod .. '/42.21/media/lua/' .. side .. '/' end
end
function require(name)
  if modules[name] ~= nil then return modules[name] end
  for _, root in ipairs(roots) do
    local f = io.open(root .. name .. '.lua', 'r')
    if f then f:close(); modules[name] = dofile(root .. name .. '.lua') or true; return modules[name] end
  end
  error('module not found: ' .. name)
end
M = require 'RadioSurvivorCore/RC_Missions'
require 'LivingKnox/LK_MissionRewards'
store = {data={npcs={n={id='n', incarnation='lk-1'}}, characters={a={name='Ann'}, b={name='Bob'}}},
         save=function() return true end}
require('RadioSurvivor/RS_MissionHooks').attach(store)
m = {id='n-d1', npc='n', state='success', participants={a={name='Ann'}, b={name='Bob'}}, invited={},
     claimedBy='', revision=1, rewardCount=0, rewardType='', receipts={}, quantity=1, delivered=1, accepted={}}
"""


class BothModsRewardTests(unittest.TestCase):
    """RadioSurvivor and Living Knox active: a Living Knox NPC mission is paid by Living Knox, as without
    RadioSurvivor (E11-T21)."""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f'MODS = [[{MODS.as_posix()}]]')
        self.lua.execute(BOTH_MODS)
        self.g = self.lua.globals()

    def claim(self, player, who, token):
        return self.g.M.claim(self.g.store, self.g.m, player, who, token)

    def test_one_household_item_for_the_recipient_only(self):
        self.assertEqual(self.claim(self.g.alice, 'a', 't'), (True, None))
        self.assertEqual(self.g.taken, 1)
        self.assertEqual([it.getFullType() for it in self.g.alice.added.values()], ['Base.Bandage'])
        self.assertEqual((self.g.m.claimedBy, self.g.m.claimedName, self.g.m.householdItem), ('a', 'Ann', 'Base.Bandage'))
        self.assertIsNone(self.g.m.transaction)
        self.assertEqual(self.claim(self.g.bob, 'b', 'u'), (False, 'State'))
        self.assertEqual(self.g.taken, 1)
        self.assertEqual(len(self.g.bob.added), 0)

    def test_dead_npc_pays_nothing_from_the_household(self):
        self.lua.execute('g.members.m.alive = false')
        self.assertEqual(self.claim(self.g.alice, 'a', 't'), (False, 'State'))
        self.assertEqual(self.g.taken, 0)
        self.assertEqual(len(self.g.alice.added), 0)
        self.assertEqual(self.g.m.claimedBy, '')

    def test_no_surplus_gives_the_lot_created_by_the_group_type(self):
        self.lua.execute('assessment.ration = 1')
        self.assertEqual(self.g.M.projection(self.g.m, 'a').rewardTable, 'tools')
        self.assertEqual(self.claim(self.g.alice, 'a', 't'), (True, None))
        table = self.lua.eval("require('RadioSurvivorCore/RC_MissionConfig').Caches.tables.tools")
        expected = sorted(e[1] for e in table.values() for _ in range(e[2]))
        self.assertEqual(sorted(it.getFullType() for it in self.g.alice.added.values()), expected)
        self.assertEqual(self.g.m.createdLot, 'tools')

    def test_npc_of_no_group_gets_the_announced_lot_as_living_knox_alone(self):
        self.lua.execute("store.data.npcs.n.incarnation = 'lk-9'; m.rewardCount = 2; m.rewardType = 'Base.Pills'")
        self.lua.execute('sendAddItemToContainer = function() end')
        self.assertIsNone(self.g.M.projection(self.g.m, 'a').rewardTable)
        self.assertEqual(self.claim(self.g.alice, 'a', 't'), True)
        self.assertEqual(self.g.taken, 0)
        self.assertEqual([it.getFullType() for it in self.g.alice.added.values()], ['Base.Pills', 'Base.Pills'])

    def test_fiche_of_no_engine_keeps_the_common_lot(self):
        self.lua.execute("store.data.npcs.n.incarnation = nil; m.rewardCount = 1; m.rewardType = 'Base.Pills'")
        self.lua.execute('sendAddItemToContainer = function() end')
        self.assertEqual(self.claim(self.g.alice, 'a', 't'), True)
        self.assertEqual(self.g.taken, 0)
        self.assertEqual([it.getFullType() for it in self.g.alice.added.values()], ['Base.Pills'])


if __name__ == '__main__':
    unittest.main()
