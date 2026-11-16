"""Closed mission rewards, private delivery and write-ahead boundaries (E11), drawn at random since E20-T04.

Real RS_Rewards (draw engine), real reward kinds of server/RadioSurvivor/Rewards/ (one file per kind, loaded as the
game loads them), real RS_Persona and real CA_Caches; game doubles for the rest.
"""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
SERVER=ROOT/'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor'
CORE_SERVER=ROOT/'Contents/mods/batman_CoreAI/42.21/media/lua/server/CoreAI'
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
    g.LEVELS_LUA=str(SERVER.parents[1]/'shared'/'RadioSurvivor'/'RS_RadioLevels.lua')  # E24-T01, read by RS_Persona
    g.CACHES_LUA=str(CORE_SERVER/'CA_Caches.lua')
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
    steps={}  -- order of the inventory and stash effects (E23-T05)
    function sendAddItemToContainer() added=added+1;steps[#steps+1]='send' end
    map={getActualWeight=function() return 1 end}
    function instanceItem() return map end
    inv={getCapacityWeight=function() return 0 end,getEffectiveCapacity=function() return capacity end,
      AddItem=function(_,it) steps[#steps+1]='add';return it end}
    player={getInventory=function() return inv end}
    stash={getName=function() return 'A' end,getItem=function() return 'Base.Map' end,
      getBuildingX=function() return 1 end,getBuildingY=function() return 2 end}
    visited=false; stashed=0; possible=true
    -- StashSystem.java: doStashItem annotates the map and removes the stash from the possible ones.
    StashSystem={getPossibleStashes=function() return {size=function() return possible and 1 or 0 end,
        get=function() return stash end} end,
      getStash=function() return stash end,
      doStashItem=function() stashed=stashed+1;possible=false;steps[#steps+1]='stash' end}
    function getWorld() return {getMetaGrid=function() return {getRoomAt=function() return {
      getBuilding=function() return {isHasBeenVisited=function() return visited end} end} end} end} end
    voices={silent={state='silent'},dead={state='dead'},cody={state='active',name='Cody'}}
    modules={['RadioSurvivor/RS_Config']=cfg,['CoreAI/CA_Reputation']={today=function() return day end},
      ['CoreAI/CA_MissionConfig']=missionCfg,['CoreAI/CA_Missions']={},
      ['RadioSurvivor/RS_Personas']={get=function(id) return voices[id] end,served=function(id) return {88000} end,
        ids=function() return {'silent','cody'} end,rules=function() return {categories=catalogue} end},
      ['RadioSurvivor/RS_GroupRadio']={voiceId=function() return 'grp_1' end},
      ['RadioSurvivor/RS_RadioLog']={add=function(cid,khz,kind,text)
         logged[#logged+1]={cid=cid,khz=khz,kind=kind,text=text};return true end},
      ['RadioSurvivor/RS_MapMarks']={give=function() end}}
    function require(n) assert(modules[n],n);return modules[n] end
    modules['RadioSurvivor/RS_PersonaParams']=dofile(PARAMS_LUA)
    modules['RadioSurvivor/RS_RadioLevels']=dofile(LEVELS_LUA)
    modules['RadioSurvivor/RS_Persona']=dofile(PERSONA_LUA)
    modules['RadioSurvivor/RS_Categories']=dofile(CATEGORIES_LUA)  -- E20-T16: real resolver of the categories
    -- Real caches of the core mod; placement in the world is the double (counted).
    modules['CoreAI/CA_Caches']=dofile(CACHES_LUA)
    modules['CoreAI/CA_Caches'].place=function() placed=placed+1;return true end
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
    def test_map_enters_the_inventory_before_the_stash_is_reserved(self):
        """E23-T05 (ADR D10): the map is in the inventory before the vanilla stash is reserved; the client gets the
        annotated map after."""
        self.lua.execute("source.rewards={{kind='stashmap',weight=1}}")
        self.assertEqual(self.grant().status,'applied')
        self.assertEqual(list(self.g.steps.values()),['add','stash','send'])
    def test_full_inventory_consumes_nothing_and_the_map_stays_to_claim(self):
        """E23-T05 (ADR D10): inventory full, nothing consumed, the reward stays reserved and the map is handed
        once there is room."""
        self.lua.execute("source.rewards={{kind='stashmap',weight=1}};capacity=0")
        rec,why=self.grant()
        self.assertEqual((rec.status,why),('reserved','recovery'))
        self.assertEqual((self.g.stashed,self.g.added,len(self.g.steps)),(0,0,0))
        self.assertTrue(self.g.possible,'the stash was consumed')
        # A second success of the same voice never draws the same stash again meanwhile.
        self.lua.execute("m2={id='m2',state='success',participants={p=true}}")
        self.assertIsNone(self.r.choose(self.g.store.data,self.g.source,self.g.m2,'p',self.g.player)[0])
        retry=lambda: self.r.retry(self.g.store,self.g.source,self.g.m,self.g.player,'p',77000)
        self.assertEqual(retry()[1],'not_now')
        self.assertEqual((rec.status,self.g.stashed),('reserved',0))
        self.lua.execute('capacity=20')
        self.assertEqual(retry().status,'applied')
        self.assertEqual((self.g.stashed,self.g.added),(1,1))
        self.assertEqual(list(self.g.steps.values()),['add','stash','send'])
        self.assertEqual(self.g.logged[len(self.g.logged)].kind,'reward')
        self.assertIsNone(retry()[0]);self.assertEqual(self.g.stashed,1)
    def test_notebook_poll_hands_the_map_to_its_connected_recipient(self):
        """E23-T05: RS_RewardRetry, poll of the notebook server, retries the reserved reward of a connected recipient."""
        self.lua.execute("source.rewards={{kind='stashmap',weight=1}};capacity=0;voices.darlene=source;"
                         "modules['RadioSurvivor/RS_State']=store;m.donor='voice';m.khz=77000;m.revision=1")
        rec,_=self.grant()
        poll=self.lua.execute((SERVER/'RS_RewardRetry.lua').read_text(encoding='utf-8-sig')).poll
        state=self.lua.eval('{missions={m=m}}')
        watched=self.lua.eval("{{player=player,character='p'}}")
        self.assertFalse(poll(state,self.g.store,watched))
        self.lua.execute('capacity=20')
        self.assertFalse(poll(state,self.g.store,self.lua.eval("{{player=player,character='other'}}")))
        self.assertEqual(self.g.stashed,0,'handed to a character who is not the recipient')
        self.assertTrue(poll(state,self.g.store,watched))
        self.assertEqual((rec.status,self.g.stashed,self.g.m.revision),('applied',1,2))
        self.assertIn('stash',self.g.m.rewardLabel)
        self.assertFalse(poll(state,self.g.store,watched))
    def test_reserved_map_whose_stash_is_gone_is_never_handed(self):
        self.lua.execute("source.rewards={{kind='stashmap',weight=1}};capacity=0")
        rec,_=self.grant()
        self.lua.execute('possible=false;capacity=20')
        self.assertIsNone(self.r.retry(self.g.store,self.g.source,self.g.m,self.g.player,'p',77000)[0])
        self.assertEqual((rec.status,self.g.added,self.g.stashed),('reserved',0,0))
    def test_kind_without_resume_is_never_reissued(self):
        self.lua.execute("source.rewards={{kind='frequency',weight=1}}")
        rec=self.grant();rec.status='reserved'
        self.assertEqual(self.r.retry(self.g.store,self.g.source,self.g.m,self.g.player,'p',77000)[1],'not_resumable')
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
