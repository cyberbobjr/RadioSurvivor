"""Identifiant d'équipe propre au mod et mandats de négociation (E09-T03) : RS_Factions.lua dans le vrai serveur du
carnet (lupa, Lua 5.1, `next` retiré comme dans Kahlua), commandes client -> serveur et onglet Équipe du carnet.

    python tests/test_factions.py

Doublure de `zombie.characters.Faction` (42.21) fidèle au Java : liste statique `getFactions()` (ArrayList),
`getPlayers()` sans le propriétaire, `setOwner` qui garde l'ancien propriétaire comme membre et retire le nouveau des
membres (Faction.java:267-277), `addPlayer` refusé à un joueur déjà dans une faction (212-224), `isOwner`/`isMember`
(145-155), noms en double admis ; paquets serveur reproduits : création (FactionCreatePacket.java:73-89), renommage
sur le même objet (FactionChangeTitlePacket.java:65-71), changement de propriétaire (FactionChangeOwnerPacket.java:
55-66), retrait d'un membre (FactionRemoveMemberPacket), dissolution (FactionDisbandPacket.java:33-42). Un redémarrage
recrée des objets Faction neufs (IsoMetaGrid.load, map_meta.bin). Ne prouve pas l'API Java réelle ni le réseau.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, NOTEBOOK_UI, convert
from test_protocol import lua_list

FACTION_DOUBLE = r'''
local function arrayList()
    local l = {items = {}}
    function l:size() return #self.items end
    function l:get(i) return self.items[i + 1] end
    function l:add(v) self.items[#self.items + 1] = v; return true end
    function l:contains(v) for _, x in ipairs(self.items) do if x == v then return true end end; return false end
    function l:remove(v)
        for i, x in ipairs(self.items) do if rawequal(x, v) or x == v then table.remove(self.items, i); return true end end
        return false
    end
    function l:clear() self.items = {} end
    return l
end
local Object = {}
Object.__index = Object
Faction = {factions = arrayList()}
function Faction.getFactions() return Faction.factions end
function Faction.new(name, owner)
    local f = setmetatable({players = arrayList()}, Object)
    f:setName(name); f:setOwner(owner)
    return f
end
function Faction.getPlayerFaction(username)
    for _, f in ipairs(Faction.factions.items) do
        if f:getOwner() == username or f:isMember(username) then return f end
    end
    return nil
end
function Object:getName() return self.name end
function Object:setName(name) self.name = name end
function Object:getOwner() return self.owner end
function Object:setOwner(owner)
    if self.owner == nil then self.owner = owner; return end
    if not self:isMember(self.owner) then
        self:getPlayers():add(self.owner)
        self:getPlayers():remove(owner)
    end
    self.owner = owner
end
function Object:getPlayers() return self.players end
function Object:isOwner(name) return self:getOwner() == name end
function Object:isMember(name) return self.players:contains(name) end
function Object:addPlayer(name)
    if Faction.getPlayerFaction(name) then return end
    self.players:add(name)
end
function Object:removePlayer(name) self:getPlayers():remove(name) end

-- Server side of the vanilla packets (no Lua event on the server).
function FACTION_CREATE(name, owner, members)
    if Faction.getPlayerFaction(owner) then return nil end
    local f = Faction.new(name, owner)
    Faction.factions:add(f)
    for _, m in ipairs(members or {}) do f:addPlayer(m) end
    return f
end
function FACTION_RENAME(f, title) f:setName(title) end
function FACTION_OWNER(f, username)
    if f:isOwner(username) then return end
    local member = f:getOwner()
    f:setOwner(username)
    f:addPlayer(member)
end
function FACTION_REMOVE(f, username) f:removePlayer(username) end
function FACTION_DISBAND(f) Faction.factions:remove(f) end
'''


def lua_set(t):
    return sorted(k for k in t.keys()) if t is not None else []


class FactionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-factions-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, sim=None, clients=('alice', 'bob', 'carol')):
        if sim is None:
            sim = Simulation(self.path / 'game')
            sim.server.rt.execute(FACTION_DOUBLE)
        self.names = clients
        for name in clients:
            sim.add_client(name)
        self.sim, self.g = sim, sim.server.g
        self.F = sim.server.rt.eval("require('RadioSurvivor/RS_Factions')")
        return sim

    def restart(self, rebuild):
        """Server stopped then started: new Lua runtime, state read back from the files, Faction objects recreated
        by `rebuild(g)` as IsoMetaGrid.load does from map_meta.bin (same names, owners and members, or changed)."""
        self.sim.clock.offset += 60000
        restarted = Simulation(self.sim.path, self.sim.clock, saved_players=self.sim.saved())
        restarted.server.rt.execute(FACTION_DOUBLE)
        rebuild(restarted.server.g)
        return self.world(restarted, self.names)

    def player(self, name):
        return self.g.PLAYERS[name]

    def id_of(self, name):
        return self.F.idOf(self.player(name))

    def conclude(self, name):
        return self.F.canConclude(self.player(name))

    def poll(self):
        self.sim.clock.offset += 3000
        self.sim.tick()

    def record(self, rid):
        return self.sim.state().factions.records[rid]

    def team(self, name):
        return self.sim.clients[name].g.RS_CarnetClient.snapshot.team

    def test_rename_keeps_the_id_in_session_and_after_a_restart(self):
        self.world()
        f = self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob']))
        self.poll()
        rid = self.id_of('alice')
        self.assertRegex(rid, r'^fac-\d+$')
        self.assertEqual(self.id_of('bob'), rid)
        self.g.FACTION_RENAME(f, 'Beta')
        self.poll()
        self.assertEqual(self.id_of('alice'), rid, 'rename lost the id')
        self.assertEqual(self.record(rid).name, 'Beta')
        # Private state only: RS_State file, never a global ModData.
        self.assertIsNotNone(self.sim.state().factions)
        self.sim.server.g.RS_CarnetServer.store.save()
        # Restart: new Java objects, renamed again while the server was down (only the owner identifies it).

        def rebuild(g):
            created = g.FACTION_CREATE('Gamma', 'alice', None)
            created.addPlayer(created, 'bob')
        self.restart(rebuild)
        self.assertEqual(self.id_of('bob'), rid)
        self.assertEqual(self.record(rid).name, 'Gamma')

    def test_owner_change_and_rename_across_a_restart_keep_the_id_by_majority(self):
        self.world(clients=('alice', 'bob', 'carol', 'dave'))
        f = self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob', 'carol']))
        self.poll()
        rid = self.id_of('carol')
        self.sim.server.g.RS_CarnetServer.store.save()

        def rebuild(g):
            # Owner bob, previous owner alice kept as member (Faction.setOwner), dave joined, new name.
            created = g.FACTION_CREATE('Omega', 'bob', None)
            for m in ('alice', 'carol', 'dave'):
                created.addPlayer(created, m)
        self.restart(rebuild)
        self.assertEqual(self.id_of('dave'), rid, 'owner change + rename lost the id')
        self.assertEqual(self.record(rid).owner, 'bob')
        self.assertEqual(lua_set(self.record(rid).members), ['alice', 'bob', 'carol', 'dave'])

    def test_owner_change_in_session_keeps_id_and_previous_owner_as_member(self):
        self.world()
        f = self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob', 'carol']))
        self.poll()
        rid = self.id_of('alice')
        self.g.FACTION_OWNER(f, 'carol')
        self.poll()
        self.assertEqual(self.id_of('alice'), rid)
        self.assertEqual(self.record(rid).owner, 'carol')
        self.assertTrue(f.isMember(f, 'alice'), 'Java setOwner keeps the previous owner as a member')
        self.assertFalse(f.isMember(f, 'carol'), 'Java setOwner removes the new owner from getPlayers')

    def test_same_name_twice_gives_two_ids(self):
        self.world(clients=('alice', 'bob', 'carol', 'dave'))
        self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob']))
        self.g.FACTION_CREATE('Alpha', 'carol', self.sim.server.rt.table_from(['dave']))
        self.poll()
        a, c = self.id_of('bob'), self.id_of('dave')
        self.assertNotEqual(a, c)
        self.sim.server.g.RS_CarnetServer.store.save()

        def rebuild(g):  # list order swapped after the restart: names never decide
            first = g.FACTION_CREATE('Alpha', 'carol', None)
            first.addPlayer(first, 'dave')
            second = g.FACTION_CREATE('Alpha', 'alice', None)
            second.addPlayer(second, 'bob')
        self.restart(rebuild)
        self.assertEqual((self.id_of('bob'), self.id_of('dave')), (a, c))

    def test_disbanded_then_recreated_gets_a_new_id(self):
        self.world()
        f = self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob']))
        self.poll()
        old = self.id_of('alice')
        self.g.FACTION_DISBAND(f)
        # Recreated within the same poll window, same name, owner and members: still a new faction.
        self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob']))
        self.poll()
        new = self.id_of('alice')
        self.assertNotEqual(new, old)
        self.assertEqual(self.record(old).state, 'dissolved')
        self.assertGreater(int(new.split('-')[1]), int(old.split('-')[1]), 'ids are never reused')
        listed = [convert(r) for r in lua_list(self.F.list())]
        self.assertEqual([r['state'] for r in listed if r['id'] in (old, new)], ['dissolved', 'active'])

    def test_player_without_faction_is_a_team_alone(self):
        self.world()
        personal = self.id_of('bob')
        self.assertEqual(self.record(personal).kind, 'personal')
        self.assertEqual(self.conclude('bob'), (True, 'owner', personal))
        self.assertEqual(self.id_of('bob'), personal, 'personal id not stable')
        self.assertNotEqual(self.id_of('carol'), personal)
        f = self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob']))
        self.poll()  # idOf follows the bounded poll (canConclude forces a read)
        faction = self.id_of('bob')
        self.assertNotEqual(faction, personal, 'a personal id never becomes a faction id')
        self.g.FACTION_REMOVE(f, 'bob')
        self.poll()
        self.assertEqual(self.id_of('bob'), personal, 'personal id used again after leaving')
        self.poll()
        self.sim.command('bob', 'snapshot')
        team = self.team('bob')
        self.assertEqual((team.kind, team.role, team.isOwner), ('personal', 'owner', True))
        # Nobody to designate in a team alone.
        self.sim.command('bob', 'mandate', member='carol', action='grant')
        self.assertEqual(self.sim.clients['bob'].g.RS_CarnetClient.lastError, 'MandateOwner')

    def test_solo_player_owns_a_personal_team(self):
        self.world(clients=('alice',))
        self.g.FACTION_CREATE('Alpha', 'alice', None)
        self.g.isServer = lambda: False  # solo: no faction panel, notebook key 'solo'
        rid = self.id_of('alice')
        self.assertEqual(self.record(rid).kind, 'personal')
        self.assertEqual(self.record(rid).owner, 'solo')
        self.assertEqual(self.conclude('alice'), (True, 'owner', rid))
        self.assertEqual(self.F.designate(self.player('alice'), 'bob', True), (False, 'not_owner'))

    def test_mandates_designated_by_the_current_owner_only(self):
        self.world(clients=('alice', 'bob', 'carol', 'dave'))
        f = self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob', 'carol']))
        self.poll()
        rid = self.id_of('alice')
        self.assertEqual(self.conclude('alice'), (True, 'owner', rid))
        self.assertEqual(self.conclude('bob'), (False, 'no_mandate', rid), 'member without mandate concluded')
        # A member cannot designate, even himself.
        self.sim.command('carol', 'mandate', member='bob', action='grant')
        self.assertEqual(self.sim.clients['carol'].g.RS_CarnetClient.lastError, 'MandateOwner')
        self.sim.command('bob', 'mandate', member='bob', action='grant')
        self.assertEqual(self.conclude('bob')[0], False)
        # Unknown action, non-member, the owner himself.
        self.sim.command('alice', 'mandate', member='bob', action='promote')
        self.assertEqual(self.sim.clients['alice'].g.RS_CarnetClient.lastError, 'State')
        self.sim.command('alice', 'mandate', member='dave', action='grant')
        self.assertEqual(self.sim.clients['alice'].g.RS_CarnetClient.lastError, 'MandateMember')
        self.sim.command('alice', 'mandate', member='alice', action='grant')
        self.assertEqual(self.sim.clients['alice'].g.RS_CarnetClient.lastError, 'MandateMember')
        self.sim.command('alice', 'mandate', member='bob', action='grant')
        self.assertEqual(self.conclude('bob'), (True, 'negotiator', rid))
        self.assertEqual(lua_set(self.record(rid).negotiators), ['bob'])
        # Pushed to every member: bob sees his mandate.
        self.assertEqual(self.team('bob').role, 'negotiator')
        self.assertEqual([convert(m) for m in lua_list(self.team('alice').members)],
                         [{'id': 'alice', 'name': 'alice', 'role': 'owner'},
                          {'id': 'bob', 'name': 'bob', 'role': 'negotiator'},
                          {'id': 'carol', 'name': 'carol', 'role': 'member'}])
        # Withdrawn: refused at once, without waiting for a poll.
        self.sim.command('alice', 'mandate', member='bob', action='revoke')
        self.assertEqual(self.conclude('bob'), (False, 'no_mandate', rid))
        # Left the faction: refused at once, and the mandate does not come back with him.
        self.sim.command('alice', 'mandate', member='bob', action='grant')
        self.g.FACTION_REMOVE(f, 'bob')
        ok, reason, team = self.conclude('bob')
        # Alone again: bob speaks for his own personal team only, never for the faction.
        self.assertNotEqual(team, rid)
        self.assertEqual((ok, reason, self.record(team).kind), (True, 'owner', 'personal'))
        f.addPlayer(f, 'bob')
        self.assertEqual(self.conclude('bob'), (False, 'no_mandate', rid))
        # Owner change: the mandates of the previous owner end; the new owner concludes, the old one no longer.
        self.sim.command('alice', 'mandate', member='bob', action='grant')
        self.assertEqual(self.conclude('bob')[1], 'negotiator')
        self.g.FACTION_OWNER(f, 'carol')
        self.assertEqual(self.conclude('bob'), (False, 'no_mandate', rid))
        self.assertEqual(self.conclude('alice'), (False, 'no_mandate', rid))
        self.assertEqual(self.conclude('carol'), (True, 'owner', rid))
        self.sim.command('alice', 'mandate', member='bob', action='grant')
        self.assertEqual(self.sim.clients['alice'].g.RS_CarnetClient.lastError, 'MandateOwner')
        self.sim.command('carol', 'mandate', member='alice', action='grant')
        self.assertEqual(self.conclude('alice'), (True, 'negotiator', rid))

    def test_bounded_list_and_persistence(self):
        names = ('alice',) + tuple('m%d' % i for i in range(1, 8))
        self.world(clients=names)
        f = self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(list(names[1:])))
        self.poll()
        rid = self.id_of('alice')
        limit = self.F.MAX_NEGOTIATORS
        for name in names[1:limit + 1]:
            self.sim.command('alice', 'mandate', member=name, action='grant')
        self.sim.command('alice', 'mandate', member=names[limit + 1], action='grant')
        self.assertEqual(self.sim.clients['alice'].g.RS_CarnetClient.lastError, 'MandateFull')
        self.assertEqual(len(lua_set(self.record(rid).negotiators)), limit)
        self.assertEqual((self.team('alice').negotiators, self.team('alice').maxNegotiators), (limit, limit))

        def rebuild(g):
            created = g.FACTION_CREATE('Renamed', 'alice', None)
            for name in names[1:]:
                created.addPlayer(created, name)
        self.restart(rebuild)
        self.assertEqual(self.conclude('m1'), (True, 'negotiator', rid), 'mandate lost at restart')
        self.assertEqual(self.conclude(names[limit + 1])[1], 'no_mandate')

    def test_team_tab_of_the_notebook(self):
        self.world()
        self.g.FACTION_CREATE('Alpha', 'alice', self.sim.server.rt.table_from(['bob']))
        self.poll()
        c = self.sim.clients['alice']
        c.rt.execute(NOTEBOOK_UI)
        c.load('client/RS_Carnet_Client.lua')
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        self.sim.command('alice', 'snapshot')
        window.changeTab(window, 'Team')
        self.assertEqual([i.item.id for i in window.list['items'].values()], ['alice', 'bob'])
        self.assertIn('IGUI_RS_TeamFaction', window.detail.text)
        self.assertFalse(window.grant.isVisible(window.grant), 'owner row: nothing to designate')
        window.selectedId = 'bob'
        window.showDetail(window)
        self.assertTrue(window.grant.isVisible(window.grant))
        self.assertFalse(window.revoke.isVisible(window.revoke))
        window.grant.onclick(window)
        self.assertEqual(self.conclude('bob')[1], 'negotiator')
        self.assertTrue(window.revoke.isVisible(window.revoke), 'notebook not refreshed after the mandate')
        window.revoke.onclick(window)
        self.assertEqual(self.conclude('bob')[1], 'no_mandate')
        # A member sees the tab without the owner's controls.
        b = self.sim.clients['bob']
        b.rt.execute(NOTEBOOK_UI)
        b.load('client/RS_Carnet_Client.lua')
        b.g.RS_UI_Notebook.toggle()
        bw = b.g.RS_CarnetClient.window
        bw.changeTab(bw, 'Team')
        bw.selectedId = 'alice'
        bw.showDetail(bw)
        self.assertIn('IGUI_RS_TeamYou_member', bw.detail.text)
        self.assertFalse(bw.grant.isVisible(bw.grant) or bw.revoke.isVisible(bw.revoke))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
