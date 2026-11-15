"""Closed mission rewards, private delivery and write-ahead boundaries (E11), drawn at random since E20-T04.

Real RS_Rewards (draw engine), real reward kinds of server/RadioSurvivor/Rewards/ (one file per kind, loaded as the
game loads them), real RS_Persona and real RC_Caches; game doubles for the rest.
"""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
SERVER=ROOT/'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor'
CORE_SERVER=ROOT/'Contents/mods/batman_RadioSurvivorCore/42.21/media/lua/server/RadioSurvivorCore'
MODULE=SERVER/'RS_Rewards.lua'
KINDS_DIR=SERVER/'Rewards'


def reward_kind_files():
    """Reward kind files (E20-T04) as the game loads them: every file of server/RadioSurvivor/Rewards/, by name."""
    return sorted(KINDS_DIR.glob('*.lua'), key=lambda p: p.name.lower())


# Seeded generator of the draws (Park-Miller): random(n) -> 0..n-1, like ZombRand(n).
SEEDED = '''
function seeded(seed)
    local s = seed
    return function(n) s = (s * 16807) % 2147483647; return s % n end
end
'''


def runtime():
    """Lua state with the real engine, the real kinds and the doubles; returns (lua, engine module)."""
    lua=LuaRuntime(unpack_returned_tuples=True)
    g=lua.globals()
    g.PARAMS_LUA=str(SERVER/'RS_PersonaParams.lua')
    g.PERSONA_LUA=str(SERVER/'RS_Persona.lua')
    g.CACHES_LUA=str(CORE_SERVER/'RC_Caches.lua')
    g.CATEGORIES_LUA=str(SERVER/'RS_Categories.lua')
    g.next=None  # absent from Kahlua
    lua.execute(SEEDED)
    lua.execute('''
    function isClient() return false end
    function isServer() return true end
    cfg={Rewards={lessonXP=25,dailyXP=100,vanillaStashes={A=true}}}
    missionCfg={Caches={bagType='Base.Bag',order={'medical'},tables={medical={{'Base.Bandage',4}}}}}
    -- Shared catalogue (personas/_categories.txt) as RS_Personas.rules() gives it.
    catalogue={medical={id='medical',items={{type='Base.Bandage',min=4,max=4},{type='Base.Pills',min=1,max=3}}},
      food={id='food',items={{type='Base.TinnedBeans',min=2,max=2}}}}
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
    modules={['RadioSurvivor/RS_Config']=cfg,['RadioSurvivorCore/RC_Reputation']={today=function() return day end},
      ['RadioSurvivorCore/RC_MissionConfig']=missionCfg,['RadioSurvivorCore/RC_Missions']={},
      ['RadioSurvivor/RS_Personas']={get=function(id) return voices[id] end,served=function(id) return {88000} end,
        ids=function() return {'silent','cody'} end,rules=function() return {categories=catalogue} end},
      ['RadioSurvivor/RS_GroupRadio']={voiceId=function() return 'grp_1' end},
      ['RadioSurvivor/RS_RadioLog']={add=function(cid,khz,kind,text)
         logged[#logged+1]={cid=cid,khz=khz,kind=kind,text=text};return true end},
      ['RadioSurvivor/RS_MapMarks']={give=function() end}}
    function require(n) assert(modules[n],n);return modules[n] end
    modules['RadioSurvivor/RS_PersonaParams']=dofile(PARAMS_LUA)
    modules['RadioSurvivor/RS_Persona']=dofile(PERSONA_LUA)
    modules['RadioSurvivor/RS_Categories']=dofile(CATEGORIES_LUA)  -- E20-T16: real resolver of the categories
    -- Real caches of the core mod; placement in the world is the double (counted).
    modules['RadioSurvivorCore/RC_Caches']=dofile(CACHES_LUA)
    modules['RadioSurvivorCore/RC_Caches'].place=function() placed=placed+1;return true end
    store={data={},save=function() saves=saves+1;return saveOK end}
    source={id='darlene',rewards={{kind='cache',param='medical',weight=1},{kind='frequency',weight=1},
        {kind='stashmap',weight=1},{kind='lesson',param='Doctor',weight=1}},
      shares={'silent','dead','cody'},places={{id='p',x=1,y=2,label='Clinic',uses={'drop'},use={drop=true}}}}
    m={id='m',state='success',participants={p=true}}
    ''')
    engine=lua.execute(MODULE.read_text(encoding='utf-8-sig'))
    g.modules['RadioSurvivor/RS_Rewards']=engine
    for path in reward_kind_files():
        g.modules[f'RadioSurvivor/Rewards/{path.stem}']=lua.execute(path.read_text(encoding='utf-8-sig'))
    return lua, engine


class RewardsTests(unittest.TestCase):
    def setUp(self):
        self.lua,self.r=runtime()
        self.g=self.lua.globals()
        self.r.setRandom(self.lua.eval('seeded(7)'))
    def kind(self,name): return self.g.modules[f'RadioSurvivor/Rewards/{name}']
    def grant(self): return self.r.grant(self.g.store,self.g.source,self.g.m,self.g.player,'p',77000)
    def test_duplicate_guard(self):
        self.lua.execute("source.rewards={{kind='cache',param='medical',weight=1}}")
        first=self.grant();self.grant()
        self.assertEqual(self.g.placed,1)
        self.assertTrue(self.lua.eval('rawequal')(self.g.m.extendedReward,first))
    def test_frequency_logged_privately(self):
        self.lua.execute("source.rewards={{kind='frequency',weight=1}}")
        self.grant()
        self.assertEqual(self.g.m.extendedReward.kind,'frequency')
        line=self.g.logged[len(self.g.logged)]
        self.assertEqual(line.cid,'p');self.assertEqual(line.khz,77000);self.assertEqual(line.kind,'reward')
        line=self.g.logged[1]
        self.assertEqual(line.khz,88000);self.assertIn('88.0 MHz',line.text)
        self.assertNotIn('88.0',self.r.context(self.g.m.extendedReward))
    def test_no_effect_before_success_or_failed_reservation(self):
        self.lua.execute("m.state='active'");self.grant();self.assertEqual(self.g.placed,0)
        self.lua.execute("m.state='success';saveOK=false;source.rewards={{kind='cache',param='medical',weight=1}}")
        self.grant()
        self.assertEqual(self.g.placed,0);self.assertIsNone(self.g.m.extendedReward);self.assertIsNone(self.g.m.cache)
    def test_stash_once_and_unvisited(self):
        self.lua.execute("source.rewards={{kind='stashmap',weight=1}}")
        self.grant();self.assertEqual(self.g.stashed,1);self.assertEqual(self.g.added,1)
        self.lua.execute("m={state='success',participants={p=true}}")
        self.assertIsNone(self.r.choose(self.g.store.data,self.g.source,self.g.m,'p')[0])
        self.lua.execute('store.data={};visited=true')
        self.assertIsNone(self.kind('RS_Reward_Stashmap').find())
    def test_full_inventory_does_not_reserve_stash(self):
        self.lua.execute("source.rewards={{kind='stashmap',weight=1}};capacity=0")
        self.grant();self.assertIsNone(self.g.m.extendedReward);self.assertEqual(self.g.stashed,0)
    def test_xp_daily_limit_disable_and_day_reset(self):
        self.lua.execute("source.rewards={{kind='lesson',param='Doctor',weight=1}}")
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
        self.assertEqual(self.kind('RS_Reward_Frequency').find(self.g.source).voice,'cody')
    def test_every_pool_kind_is_granted_by_the_draw(self):
        seen=set()
        for i in range(40):
            self.lua.execute(f"m={{id='m{i}',state='success',participants={{p=true}}}};day={i};store.data.lessonDays=nil;"
                             "store.data.missionRewards=nil")
            rec=self.grant()
            self.assertEqual(rec.status,'applied')
            seen.add(rec.kind)
        self.assertEqual(seen,{'cache','frequency','stashmap','lesson'})


if __name__=='__main__':unittest.main()
