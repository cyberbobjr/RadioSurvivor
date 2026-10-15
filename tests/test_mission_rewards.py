"""Closed mission rewards, private delivery, rotation and write-ahead boundaries."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
MODULE=ROOT/'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_Rewards.lua'

class RewardsTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        function isClient() return false end
        function isServer() return true end
        cfg={Rewards={order={'cache','frequency','stashmap','lesson'},lessonXP=25,dailyXP=100,vanillaStashes={A=true}},
          Caches={tables={medical={}}}}
        day=1; xp=0; added=0; placed=0; logged={}; capacity=20; saveOK=true; saves=0
        Perks={Doctor=1}; SandboxVars={RadioSurvivor={LessonMultiplier=1}}
        function addXp(p,perk,n) xp=xp+n end
        function sendAddItemToContainer() added=added+1 end
        map={getActualWeight=function() return 1 end}
        function instanceItem() return map end
        inv={getCapacityWeight=function() return 0 end,getEffectiveCapacity=function() return capacity end,
          AddItem=function(_,it) return it end}
        player={getInventory=function() return inv end}
        stash={getName=function() return 'A' end,getItem=function() return 'Base.Map' end,
          getBuildingX=function() return 1 end,getBuildingY=function() return 2 end}
        visited=false; stashed=0
        StashSystem={getPossibleStashes=function() return {size=function() return 1 end,get=function() return stash end} end,
          getStash=function() return stash end,doStashItem=function() stashed=stashed+1 end}
        function getWorld() return {getMetaGrid=function() return {getRoomAt=function() return {
          getBuilding=function() return {isHasBeenVisited=function() return visited end} end} end} end} end
        voices={silent={state='silent'},dead={state='dead'},cody={state='active',name='Cody'}}
        modules={['RadioSurvivor/RS_Config']=cfg,['RadioSurvivor/RS_Reputation']={today=function() return day end},
          ['RadioSurvivor/RS_Personas']={get=function(id) return voices[id] end,served=function(id) return {88000} end,
            ids=function() return {'silent','cody'} end},
          ['RadioSurvivor/RS_GroupRadio']={voiceId=function() return 'grp_1' end},
          ['RadioSurvivor/RS_RadioLog']={add=function(cid,khz,kind,text)
             logged[#logged+1]={cid=cid,khz=khz,kind=kind,text=text};return true end},
          ['RadioSurvivor/RS_MapMarks']={give=function() end},
          ['RadioSurvivor/RS_Caches']={attach=function(m,t,p,b) m.cache={table=t,spot=p};return m.cache end,
             place=function() placed=placed+1;return true end}}
        function require(n) assert(modules[n],n);return modules[n] end
        store={data={},save=function() saves=saves+1;return saveOK end}
        source={id='darlene',rewards={'cache','frequency','stashmap','lesson'},cache_table='medical',teaches='Doctor',
          shares={'silent','dead','cody'},places={{id='p',x=1,y=2,label='Clinic'}}}
        m={id='m',state='success',participants={p=true}}
        ''')
        self.r=self.lua.execute(MODULE.read_text(encoding='utf-8-sig'))
        self.g=self.lua.globals()
    def grant(self): return self.r.grant(self.g.store,self.g.source,self.g.m,self.g.player,'p',77000)
    def test_rotation_and_duplicate_guard(self):
        self.grant();self.grant()
        self.assertEqual(self.g.placed,1)
        self.lua.execute("m={id='m2',state='success',participants={p=true}}")
        self.grant()
        self.assertEqual(self.g.m.extendedReward.kind,'frequency')
        line=self.g.logged[len(self.g.logged)-1]
        self.assertEqual(line.cid,'p');self.assertEqual(line.khz,88000)
        self.assertIn('88.0 MHz',line.text)
        self.assertNotIn('88.0',self.r.context(self.g.m.extendedReward))
    def test_no_effect_before_success_or_failed_reservation(self):
        self.lua.execute("m.state='active'");self.grant();self.assertEqual(self.g.placed,0)
        self.lua.execute("m.state='success';saveOK=false");self.grant()
        self.assertEqual(self.g.placed,0);self.assertIsNone(self.g.m.extendedReward)
    def test_stash_once_and_unvisited(self):
        self.lua.execute("source.rewards={'stashmap'}")
        self.grant();self.assertEqual(self.g.stashed,1);self.assertEqual(self.g.added,1)
        self.lua.execute("m={state='success',participants={p=true}}")
        self.assertIsNone(self.r.choose(self.g.store.data,self.g.source,self.g.m,'p'))
        self.lua.execute('store.data={};visited=true')
        self.assertIsNone(self.r.stash())
    def test_full_inventory_does_not_reserve_stash(self):
        self.lua.execute("source.rewards={'stashmap'};capacity=0")
        self.grant();self.assertIsNone(self.g.m.extendedReward);self.assertEqual(self.g.stashed,0)
    def test_xp_daily_limit_disable_and_day_reset(self):
        self.lua.execute("source.rewards={'lesson'}")
        for _ in range(6):
            self.lua.execute("m={state='success',participants={p=true}}")
            self.grant()
        self.assertEqual(self.g.xp,100)
        self.lua.execute("day=2;m={state='success',participants={p=true}}")
        self.grant();self.assertEqual(self.g.xp,125)
        self.lua.execute("SandboxVars.RadioSurvivor.LessonMultiplier=0;m={state='success',participants={p=true}}")
        self.grant();self.assertEqual(self.g.xp,125)
    def test_group_falls_back_to_active_voice(self):
        self.lua.execute("source.group='grp-1';source.shares={}")
        self.assertEqual(self.r.frequency(self.g.source).voice,'cody')

if __name__=='__main__':unittest.main()
