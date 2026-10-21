"""Conteneur du cadavre d'un joueur (E15-T02) : banc hors jeu de la suite en jeu rs.lastpages.corpse.

    python RadioSurvivor/tests/test_lastpages_corpse.py

Charge le vrai moteur RST (`RST.lua`, `RST_Fixtures.lua`) et la vraie suite
`dev/.../shared/RST/suites/RS_LastPagesCorpse.lua` sous lupa (Lua 5.1, `next` retiré comme dans Kahlua), avec des
doublures minimales de l'API Java qui reproduisent l'ordre établi dans le Java 42.21.0 (docs/annexes/recherches/derniers-pages-cadavre.md) :
`OnCharacterDeath` d'abord, puis le cadavre qui reprend le conteneur du mort (`IsoDeadBody` : `setContainer(died
.getInventory())`, puis un inventaire neuf pour le mort).

- SuiteTests : rs.lastpages.corpse passe (cadavre créé, papier marqué dans son conteneur et envoyé, repli au sol) ;
  les suites manuelles sont hors de la sélection par défaut.
- DeathWitnessTests : arm, mort simulée, check : le papier ajouté pendant OnCharacterDeath se retrouve dans le cadavre ;
  check sans mort = FAIL ; un autre joueur qui meurt n'est pas touché ; un seul tir par armement.
Simulation, PAS validation en jeu.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_LastPagesCorpse.lua'

DOUBLES = r"""
next = nil
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
CLOCK = 7000000
getTimestampMs = function() return CLOCK end
SIDE = "server"
isServer = function() return SIDE == "server" end
isClient = function() return SIDE == "client" end
getWorld = function() return { getWorld = function() return "rstest-bench" end } end
SENT = { add = 0, remove = 0, world = 0 }
sendAddItemToContainer = function() SENT.add = SENT.add + 1 end
sendRemoveItemFromContainer = function() SENT.remove = SENT.remove + 1 end

local function list(items)
    return { items = items, size = function(self) return #self.items end,
        get = function(self, i) return self.items[i + 1] end,
        add = function(self, v) self.items[#self.items + 1] = v end,
        remove = function(self, v)
            for i = #self.items, 1, -1 do if self.items[i] == v then table.remove(self.items, i) end end
        end,
        contains = function(self, v) for _, x in ipairs(self.items) do if x == v then return true end end return false end }
end

instanceof = function(o, cls) return type(o) == "table" and o._class == cls end

function newContainer(parent)
    local c = { _class = "ItemContainer", parent = parent, items = list({}) }
    function c:getItems() return self.items end
    function c:getParent() return self.parent end
    function c:AddItem(it) self.items:add(it); it.container = self; return it end
    function c:Remove(it) self.items:remove(it); it.container = nil end
    function c:contains(it) return self.items:contains(it) end
    return c
end

instanceItem = function(fullType)
    local it = { _class = "InventoryItem", fullType = fullType, md = nil }
    function it:getFullType() return self.fullType end
    function it:setName(n) self.name = n end
    function it:setCustomName(v) self.custom = v end
    function it:getModData() self.md = self.md or {}; return self.md end
    function it:hasModData() return self.md ~= nil end
    function it:getContainer() return self.container end
    function it:getWorldItem() return self.worldItem end
    return it
end

SQUARES = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
function square(x, y, z)
    local k = key(x, y, z)
    if SQUARES[k] then return SQUARES[k] end
    local sq = { x = x, y = y, z = z, statics = list({}), objects = list({}) }
    function sq:getStaticMovingObjects() return self.statics end
    function sq:removeCorpse(body) self.statics:remove(body); body.square = nil end
    function sq:AddWorldInventoryItem(item, ox, oy, oz, transmit)
        local wo = { _class = "IsoWorldInventoryObject", item = item, square = self }
        function wo:getSquare() return self.square end
        function wo:getItem() return self.item end
        self.objects:add(wo); item.worldItem = wo
        if transmit then SENT.world = SENT.world + 1 end
        return item
    end
    function sq:transmitRemoveItemFromSquare(wo) self.objects:remove(wo); wo.item.worldItem = nil; wo.square = nil end
    SQUARES[k] = sq
    return sq
end
UNLOADED = {}
getCell = function() return { getGridSquare = function(_, x, y, z)
    if UNLOADED[key(x, y, z)] then return nil end
    return square(x, y, z) end } end

-- IsoDeadBody: takes the container of the dead (IsoDeadBody.java:327-333).
function newBody(sq, x, y, container, isPlayer)
    local b = { _class = "IsoDeadBody", square = sq, x = x + 0.5, y = y + 0.5, z = sq.z, player = isPlayer }
    function b:getSquare() return self.square end
    function b:getX() return self.x end
    function b:getY() return self.y end
    function b:getContainer() return self.container end
    function b:isPlayer() return self.player and true or false end
    function b:setFakeDead(v) self.fakeDead = v end
    b.container = container or newContainer(nil)
    b.container.parent = b
    sq.statics:add(b)
    return b
end
IsoDirections = { S = "S" }
RandomizedWorldBase = { createRandomDeadBody = function(sq) return newBody(sq, sq.x, sq.y, nil, false) end }

LISTENERS = {}
Events = { OnCharacterDeath = { Add = function(f) LISTENERS[#LISTENERS + 1] = f end } }

function newPlayer(name, x, y, z)
    local p = { _class = "IsoPlayer", name = name, x = x + 0.5, y = y + 0.5, z = z, fire = false }
    p.inv = newContainer(p)
    function p:getUsername() return self.name end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:getInventory() return self.inv end
    function p:isOnFire() return self.fire end
    return p
end

-- die() on the authority: Kill -> onKilled -> DoDeath -> OnCharacterDeath, then becomeCorpse (IsoGameCharacter.java
-- 13480-13542): the corpse takes the inventory, the dead gets an empty one.
function die(p)
    for _, f in ipairs(LISTENERS) do f(p) end
    local sq = square(math.floor(p.x), math.floor(p.y), p.z)
    local body = newBody(sq, math.floor(p.x), math.floor(p.y), p.inv, true)
    p.inv = newContainer(p)
    return body
end

function results(report)
    local out = {}
    for _, r in pairs(report.results) do out[#out + 1] = r.suite .. " | " .. r.test .. " | " .. r.status .. " | "
        .. tostring(r.message) end
    table.sort(out)
    return out
end
"""


class Bench(unittest.TestCase):
    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.rt.execute(DOUBLES)
        self.rt.execute(f'package.path = [[{(TESTS_LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('require "RST/RST"; require "RST/RST_Fixtures"')
        self.rt.execute(SUITE.read_text(encoding='utf-8'))
        self.rt.execute('ALICE = newPlayer("alice", 100, 200, 0); BOB = newPlayer("bob", 110, 200, 0)')

    def run_filter(self, flt: str, player: str = 'ALICE') -> list[str]:
        return list(self.rt.eval(f'results(RST.runSync({flt}, {{ player = {player} }}))').values())

    def status(self, lines: list[str]) -> list[str]:
        return [line.split(' | ')[2] for line in lines]


class SuiteTests(Bench):
    def test_suite_passes(self):
        lines = self.run_filter('{ suite = "rs.lastpages.corpse", tags = "world" }')
        self.assertEqual(len(lines), 3, lines)
        self.assertEqual(self.status(lines), ['PASS'] * 3, lines)
        self.assertEqual(self.rt.eval('SENT.add'), 1)
        self.assertEqual(self.rt.eval('SENT.remove'), 1)
        self.assertEqual(self.rt.eval('SENT.world'), 1)
        # Cleanups: no corpse, no paper left on the ground.
        self.assertEqual(self.rt.eval('square(102, 200, 0).statics:size()'), 0)
        self.assertEqual(self.rt.eval('square(102, 200, 0).objects:size()'), 0)

    def test_manual_suites_not_selected_by_default(self):
        lines = self.run_filter('{ suite = "rs.lastpages.corpse", tags = "world" }')
        self.assertFalse(any('.arm' in line or '.check' in line for line in lines), lines)

    def test_mp_client_skips(self):
        self.rt.execute('SIDE = "client"')
        lines = self.run_filter('{ suite = "rs.lastpages.corpse", tags = "world" }')
        self.assertEqual(self.status(lines), ['SKIP'] * 3, lines)


class DeathWitnessTests(Bench):
    ARM = '{ suite = "rs.lastpages.corpse.arm", tags = "manual" }'
    CHECK = '{ suite = "rs.lastpages.corpse.check", tags = "manual" }'

    def test_paper_added_at_death_ends_in_the_corpse(self):
        self.assertEqual(self.status(self.run_filter(self.ARM)), ['PASS'])
        self.rt.execute('BODY = die(ALICE)')
        token = self.rt.eval('RST_LastPagesCorpse.last')
        self.assertTrue(self.rt.eval(f'RST_LastPagesCorpse.seen["{token}"].added'))
        self.assertEqual(self.rt.eval(f'RST_LastPagesCorpse.seen["{token}"].corpsesBefore'), 0)
        self.assertEqual(self.rt.eval('BODY.container:getItems():size()'), 1)
        self.assertEqual(self.rt.eval('ALICE.inv:getItems():size()'), 0)
        lines = self.run_filter(self.CHECK, player='nil')
        self.assertEqual(self.status(lines), ['PASS'], lines)

    def test_check_without_death_fails(self):
        self.run_filter(self.ARM)
        self.assertEqual(self.status(self.run_filter(self.CHECK)), ['FAIL'])

    def test_check_without_arm_skips(self):
        self.assertEqual(self.status(self.run_filter(self.CHECK)), ['SKIP'])

    def test_other_player_and_second_death_untouched(self):
        self.run_filter(self.ARM)
        self.rt.execute('BOB_BODY = die(BOB)')
        self.assertEqual(self.rt.eval('BOB_BODY.container:getItems():size()'), 0)
        self.rt.execute('BODY1 = die(ALICE); BODY2 = die(ALICE)')
        self.assertEqual(self.rt.eval('BODY1.container:getItems():size()'), 1)
        self.assertEqual(self.rt.eval('BODY2.container:getItems():size()'), 0)
        self.assertEqual(self.rt.eval('#LISTENERS'), 1)

    def test_listener_registered_once(self):
        self.run_filter(self.ARM)
        self.run_filter(self.ARM)
        self.assertEqual(self.rt.eval('#LISTENERS'), 1)

    def test_unloaded_death_square_skips(self):
        self.run_filter(self.ARM)
        self.rt.execute('die(ALICE); for _, s in pairs(SQUARES) do UNLOADED[s.x .. "," .. s.y .. "," .. s.z] = true end;'
                        'for k in pairs(UNLOADED) do SQUARES[k] = nil end')
        self.assertEqual(self.status(self.run_filter(self.CHECK)), ['SKIP'])


if __name__ == '__main__':
    sys.exit(0 if unittest.main(exit=False, verbosity=1).result.wasSuccessful() else 1)
