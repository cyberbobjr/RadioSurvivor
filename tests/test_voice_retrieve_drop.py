"""ID card of a voice `retrieve` mission left at a dead drop (E20-T06, ADR D06), real Lua with Lua 5.1 doubles.

For a mission given by a radio voice, the card taken from the body is deposited at one of the mission's drops and
collected by the same rule as the goods of `deliver` (out of everyone's view, after a delay in game hours), recognised
only by its item id (m.cardId). The objective is met once that card is collected; the radio report then succeeds and
never removes anything from the inventory. Real modules: CA_Missions (engine poll, report), CA_MissionRetrieve
(template and its "what counts" strategy), the dead-drop unit of RadioSurvivor, RS_OutOfSight, CA_GameClock. The giver
double wires the drop hooks as RS_MissionHooks does. Server logic only: no proof of the Java API nor of the network.
"""
import unittest

from test_voice_delivery import DropBench

RETRIEVE = r'''
RandomizedWorldBase = {}
-- LuaEventManager: Events.<name>.Add, read at load by the reputation of the core mod (success of the report).
Events = setmetatable({}, {__index = function(t, k) t[k] = {Add = function() end}; return t[k] end})
M = require 'CoreAI/CA_Missions'
R = require 'CoreAI/CA_MissionRetrieve'
-- Voice giver as RS_MissionHooks registers it: dead drops polled and projected by the dead-drop unit (global D).
M.registerDonor('voice', {
    find = function(state, id) return state.voiceDonors and state.voiceDonors[id] end,
    observeDrops = function(...) return D.observe(...) end,
    projectDrops = function(...) return D.project(...) end,
    dropsWhere = function(m) return D.where(m) end,
    dropsRule = function(m) return D.rule(m) end,
})
STATE.missions, STATE.outcomes, STATE.voiceDonors = {}, {}, {}
STORE.data = STATE
sq = square(100, 100, 0); inv = container(); obj = box(sq, inv)
m = {id = 'voice:v:c1-retrieve1', template = 'retrieve_id', donor = 'voice', npc = 'voice:v:c1', voice = 'v',
    state = 'active', revision = 0, remainingMs = 7200000, durationMs = 7200000, rewardType = '', rewardCount = 0,
    titleKey = 'IGUI_CA_Mission_Retrieve', report = 'radio', place = 'Drop A', placeKind = 'house',
    quantity = 1, delivered = 0, accepted = {['Base.IDcard'] = true}, cardId = 777, placed = true, found = false,
    participants = {c1 = {name = 'alice'}}, invited = {}, receipts = {}, collectHours = 6, credited = {},
    drops = {{id = 'a', label = 'Drop A', x = 100, y = 100, z = 0, mode = 'box'}}}
STATE.missions[m.id] = m
assert(D.prepare(m, m.drops[1], STORE))
ALICE = PLAYERS[1]
card = item(777, 'Base.IDcard'); ALICE.inv.items = {card}; card.owner = ALICE.inv
function poll() return M.observe(STATE, {{player = ALICE, character = 'c1'}}, STORE) end
function deposit(it)
    if it.owner then it.owner:DoRemoveItem(it) end
    inv.items[#inv.items + 1] = it; it.owner = inv
end
function leave_and_wait() ALICE.x = 250; poll(); HOURS = HOURS + 6.01; poll() end
function report() return M.spoken(STORE, m, ALICE, 'c1') end
function inBox(id) return inv:getItemWithIDRecursiv(id) ~= nil end
function held(id) return ALICE.inv:getItemWithIDRecursiv(id) ~= nil end
'''


class VoiceRetrieveDropTests(DropBench):
    def setUp(self):
        super().setUp()
        self.run_lua(RETRIEVE)

    def test_radio_report_without_deposit_is_refused_and_the_card_stays(self):
        self.run_lua("""
            poll()
            assert(m.found == true, 'the card in the inventory is observed')
            assert(not M.reportReady(m), 'holding the card is not the objective of a voice mission')
            local ok = report()
            assert(not ok and m.state == 'active', 'report refused before the card is collected')
            assert(held(777), 'the radio report never removes the card from the inventory')
        """)

    def test_card_deposited_then_collected_out_of_sight_meets_the_objective_then_report_accepted(self):
        self.run_lua("""
            poll(); deposit(card); poll()
            assert(m.delivered == 0 and inBox(777), 'never collected in front of the player')
            assert(not M.reportReady(m))
            leave_and_wait()
            assert(m.delivered == 1 and not inBox(777), 'the card is collected out of sight after the delay')
            assert(m.credited['777'] == true)
            assert(M.reportReady(m), 'objective met once the card is collected')
            local p = M.projection(m, 'c1')
            assert(p.toReport == true and p.depositCollected == true)
            local ok = report()
            assert(ok and m.state == 'success', 'radio report accepted after the collection')
        """)

    def test_another_id_card_is_never_taken(self):
        self.run_lua("""
            local other = item(778, 'Base.IDcard'); deposit(other)
            leave_and_wait()
            assert(m.delivered == 0 and inBox(778), 'another ID card is never collected')
            assert(not M.reportReady(m))
            ALICE.x = 100; poll(); deposit(card); leave_and_wait()
            assert(m.delivered == 1 and not inBox(777) and inBox(778), 'only the card of the mission is taken')
        """)

    def test_restart_never_credits_the_card_twice(self):
        self.run_lua("deposit(card); leave_and_wait(); assert(m.delivered == 1)")
        self.load_module()
        self.run_lua("""
            -- The world was not saved after the pickup: the same card is back in the box.
            deposit(card); m.delivered = 0
            ALICE.x = 100; poll(); leave_and_wait()
            assert(m.delivered == 0 and inBox(777), 'a credited card id is never counted again')
        """)

    def test_notebook_and_map_show_every_drop(self):
        self.run_lua("P = M.projection(m, 'c1')")
        self.assertEqual(self.rt.eval('P.report'), 'radio')
        self.assertEqual(self.rt.eval('#P.drops'), 1)
        self.assertEqual(self.rt.eval('P.drops[1].label'), 'Drop A')
        self.assertEqual(self.rt.eval('#P.dropZones'), 1)
        self.assertEqual(self.rt.eval('P.collectHours'), 6)
        self.assertFalse(self.rt.eval('P.depositCollected'))

    def test_voice_is_told_to_leave_the_card_at_a_drop(self):
        self.run_lua("BRIEF = R.voiceBrief(m); FACTS = table.concat(BRIEF.facts, ' ')")
        job = self.rt.eval('BRIEF.job')
        self.assertIn('drop points (Drop A)', job)
        self.assertNotIn('777', job)
        facts = self.rt.eval('FACTS')
        self.assertIn('out of sight of everyone', facts)
        self.assertIn('about 6 game hours', facts)
        self.assertIn('Card collected at a drop point: no.', facts)

    def test_card_held_by_a_non_voice_mission_still_uses_the_hand_over(self):
        """An NPC requester: the card of the mission in the inventory is handed over in person (unchanged)."""
        self.run_lua("""
            m.donor, m.drops = nil, nil
            local e = R.check(m, ALICE, {777})
            assert(e and e.item == card, 'the hand-over in person still takes the card from the inventory')
        """)


if __name__ == '__main__':
    unittest.main()
