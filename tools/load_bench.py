"""Mesure de charge hors jeu du moteur Living Knox (LK13-T02) : 5 groupes, 4 joueurs, serveur dédié + 4 clients.

    python RadioSurvivor/tools/load_bench.py [--minutes 60] [--seed 7] [--json out.json] [--quiet] [--lenient]
    python RadioSurvivor/tools/load_bench.py --kahlua      rapport de vitesse Kahlua / lupa (voir kahlua_factor)
    python RadioSurvivor/tools/load_bench.py --minutes 1440 --dump-groups groups.hex     registre des groupes du banc
    python RadioSurvivor/tools/load_bench.py --kahlua --registry groups.hex    écriture de CE registre, Kahlua / lupa

Banc tests/harness.py (Lua 5.1 lupa, une VM par machine) avec la pile complète des corps des bancs existants
(test_lk_materialize.MatBase : corps, consignes, rapports, santé, équipement ; doublures de santé, perception,
combat, tir, zombies, butin et mort), puis TOUS les fichiers Lua de Living Knox (shared, server, client), chargés par
require comme le jeu les exécute. Doublures ajoutées ici (BENCH) : cases sans eau, buisson, clôture basse ni
bâtiment (getBuilding, getBuildingAt nil), ZombRand reproductible,
getText / getTextOrNull qui rendent la clé. Les clients C et D reçoivent les mêmes doublures que A (chargement recopié).

Scénario : Population.run crée 5 groupes (option GroupCount = 5, types tirés par les poids par défaut, foyers fixés
par le banc : Sites.pick remplacé). Joueurs : A (propriétaire) et B (observateur) près du foyer 1, C près du foyer 2,
D loin de tout ; les foyers 3 à 5 restent hors écran. Serveur à 10 images par seconde (100 ms, base
multiplayer.md), une minute de jeu toutes les 25 images (journée de 1 h réelle), EveryHours à chaque heure de jeu.
Réseau : file du banc livrée à chaque image. Corps : copie chez chaque client à 64 cases ou moins de son joueur
(portée réseau), propriétaire = client le plus proche à 48 cases ou moins (sinon le serveur), position du
propriétaire recopiée sur les autres machines, marche STEP du banc chez le propriétaire.

Mesure : LivingKnox.Load (shared/LivingKnox/LK_Load.lua) démarré sur chaque machine après une minute de jeu de mise en
route, horloge fine (time.perf_counter, en ms) passée à Load.clock. Coûts = temps lupa (Lua 5.1 en C), PAS Kahlua
(interprète Java, plus lent) ni le jeu (API Java réelles, rendu) : l'ordre de grandeur relatif entre modules et les
volumes réseau sont les résultats utiles, les ms absolues un minorant. Sortie : un rapport texte par machine et, avec
--json, les résumés complets.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests'
sys.path.insert(0, str(TESTS))

from harness import Harness, LUA  # noqa: E402
from test_lk_materialize import MatBase  # noqa: E402
from test_lk_health import HEALTH_DOUBLES  # noqa: E402
from test_lk_senses import SENSES_DOUBLES  # noqa: E402
from test_lk_combat import COMBAT_DOUBLES, RANGED_DOUBLES  # noqa: E402
from test_lk_zombies import ZOMBIE_DOUBLES  # noqa: E402
from test_lk_loot import LOOT_DOUBLES  # noqa: E402
from test_lk_death import DEATH_DOUBLES  # noqa: E402

CLIENTS = ('A', 'B', 'C', 'D')
EXTRA = ('C', 'D')
TICK_MS = 100
TICKS_PER_MINUTE = 25
NET_RANGE = 64
OWNER_RANGE = 48
STEP_SPEED = 0.08
SYNC_EVERY = 5          # images entre deux synchronisations des corps (500 ms)
HOMES = [(110, 110, 0), (330, 110, 0), (700, 110, 0), (110, 700, 0), (700, 700, 0)]
PLAYERS = {'A': (100, 100), 'B': (106, 102), 'C': (320, 100), 'D': (1200, 1200)}

BENCH = r'''
local H = HARNESS
-- ZombRand(n) : entier dans [0, n[ ; ZombRand(a, b) : dans [a, b[ (Rand.java). Tirage reproductible du banc.
if ZombRand == nil then
    math.randomseed(7)
    ZombRand = function(a, b)
        if b == nil then a, b = 0, a end
        a, b = math.floor(a), math.floor(b)
        if b <= a then return a end
        return math.random(a, b - 1)
    end
end
local Sq = H.classes.IsoGridSquare
if rawget(Sq, 'isWaterSquare') == nil then function Sq:isWaterSquare() return false end end
if rawget(Sq, 'hasBush') == nil then function Sq:hasBush() return false end end
if rawget(Sq, 'isHoppableTo') == nil then function Sq:isHoppableTo() return false end end
if rawget(Sq, 'getBuilding') == nil then function Sq:getBuilding() return nil end end
if getText == nil then getText = function(key) return tostring(key) end end
if getTextOrNull == nil then getTextOrNull = function(key) return tostring(key) end end
local GRID = { getBuildingAt = function() return nil end, isValidSquare = function() return true end,
    getCellData = function() return {} end }
local baseWorld = getWorld
getWorld = function()
    local w = baseWorld()
    if w.getMetaGrid == nil then w.getMetaGrid = function() return GRID end end
    return w
end
-- Corps chargés sur cette machine : liste { id, x, y, z, owner, goal }.
function BENCH_BODIES()
    local out = {}
    for id, zb in pairs(H.zombies) do
        if not zb.dead then
            out[#out + 1] = { id = id, x = zb.x, y = zb.y, z = zb.z, owner = zb.owner, goal = zb.goal ~= nil }
        end
    end
    return out
end
function BENCH_PLACE(id, x, y, z)
    local zb = H.zombies[id]
    if zb then H.place(zb, x, y, z) end
end
function BENCH_OWNER(id, owner)
    local zb = H.zombies[id]
    if zb then zb.owner = owner end
end
function BENCH_DROP(id)
    if H.zombies[id] then H.removeZombie(id) end
end
'''

HOMES_LUA = 'BENCH_HOMES = {' + ', '.join(f'{{ x = {x}, y = {y}, z = {z} }}' for x, y, z in HOMES) + '}\n' + r'''
BENCH_HOME_N = 0
LivingKnox.Sites.pick = function(groupType, opts)
    BENCH_HOME_N = BENCH_HOME_N + 1
    local h = BENCH_HOMES[BENCH_HOME_N]
    if h == nil then return nil, "bench: no more homes" end
    return { x = h.x, y = h.y, z = h.z, key = "bench-" .. BENCH_HOME_N }
end
'''


class _Stack(MatBase):
    """Pile MatBase à quatre clients ; les chargements faits sur A sont recopiés sur C et D."""
    clients = CLIENTS

    def make(self, root=None):
        orig = Harness.load

        def load(h, machine, code):
            result = orig(h, machine, code)
            if machine == 'A':
                for extra in EXTRA:
                    if extra in h.machines:
                        orig(h, extra, code)
            return result

        Harness.load = load
        try:
            h = super().make(root)
        finally:
            Harness.load = orig
        h.tick_ms = TICK_MS
        return h

    def setUp(self):  # pas d'init ici : le banc pose d'abord les doublures et les fichiers
        self.h = self.make()

    def runTest(self):  # requis par unittest.TestCase
        pass


def lua_modules():
    out = []
    for side in ('shared', 'server', 'client'):
        for p in sorted((LUA / side / 'LivingKnox').rglob('*.lua'), key=lambda p: p.as_posix().lower()):
            out.append((side, p.relative_to(LUA / side).with_suffix('').as_posix()))
    return out


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class LoadBench:
    def __init__(self, seed: int = 7, strict: bool = True):
        self.stack = _Stack()
        self.stack.setUp()
        self.h = self.stack.h
        self.h.strict = strict
        self.seed = seed
        self.minute = 0
        for m in self.h.machines:
            for name, doubles in (('health', HEALTH_DOUBLES), ('senses', SENSES_DOUBLES), ('combat', COMBAT_DOUBLES),
                                  ('ranged', RANGED_DOUBLES), ('zombies', ZOMBIE_DOUBLES), ('loot', LOOT_DOUBLES),
                                  ('death', DEATH_DOUBLES), ('bench', BENCH)):
                self.h.load(m, doubles)
            for side, name in lua_modules():
                if m == 'server' and side == 'client':
                    continue
                self.h.load(m, f'require "{name}"')
        self.h.load('server', 'SandboxVars = { LivingKnox = { GroupCount = 5 } }')
        self.h.load('server', HOMES_LUA)
        self.stack.init(new_world=True)
        for p, (x, y) in PLAYERS.items():
            self.h.move_player(p, x, y)
        ids, why = self.h.load('server', f'local r, why = LivingKnox.Population.run({{ seed = {seed} }}) '
                                         'return r, why')
        if ids is None:
            raise RuntimeError(f'population failed: {why}')
        self.groups = lua_list(ids)
        self.h.fire('server', 'OnServerStarted')
        self.mirrored = {c: set() for c in CLIENTS}
        self.ticks = 0
        self.wall = 0.0

    # Monde ------------------------------------------------------------------------------------------------------
    def players(self):
        return {c: (self.h.player('server', c).x, self.h.player('server', c).y) for c in CLIENTS}

    def sync_bodies(self):
        """Copies réseau des corps du serveur : portée, propriétaire le plus proche, position du propriétaire."""
        h = self.h
        pos = self.players()
        bodies = lua_list(h.eval('server', 'BENCH_BODIES()'))
        alive = set()
        for b in bodies:
            alive.add(b.id)
            dists = {c: math.hypot(b.x - px, b.y - py) for c, (px, py) in pos.items()}
            near = min(dists, key=dists.get)
            owner = near if dists[near] <= OWNER_RANGE else 'server'
            x, y, z = b.x, b.y, b.z
            if b.owner != 'server' and b.owner in self.mirrored and b.id in self.mirrored[b.owner]:
                zb = h.zombie(b.owner, b.id)
                x, y, z = zb.x, zb.y, zb.z                              # le propriétaire fait foi
            for c in CLIENTS:
                if dists[c] <= NET_RANGE:
                    if b.id not in self.mirrored[c]:
                        h.eval(c, f'MIRROR({b.id}, {x}, {y}, {z}, "{owner}")')
                        self.mirrored[c].add(b.id)
                elif b.id in self.mirrored[c]:
                    h.load(c, f'BENCH_DROP({b.id})')
                    self.mirrored[c].discard(b.id)
            for m in ['server'] + [c for c in CLIENTS if b.id in self.mirrored[c]]:
                h.load(m, f'BENCH_OWNER({b.id}, "{owner}") BENCH_PLACE({b.id}, {x}, {y}, {z})')
        for c in CLIENTS:
            for zid in list(self.mirrored[c] - alive):
                h.load(c, f'BENCH_DROP({zid})')
                self.mirrored[c].discard(zid)

    def frame(self):
        h = self.h
        h.tick(1)
        self.ticks += 1
        for c in CLIENTS:
            h.load(c, f'for id, zb in pairs(HARNESS.zombies) do if zb.owner == "{c}" and zb.goal then '
                      f'STEP(id, {STEP_SPEED}) end end')
        h.load('server', f'for id, zb in pairs(HARNESS.zombies) do if zb.owner == "server" and zb.goal then '
                         f'STEP(id, {STEP_SPEED}) end end')
        h.pump()
        if self.ticks % SYNC_EVERY == 0:
            self.sync_bodies()
        if self.ticks % TICKS_PER_MINUTE == 0:
            h.advance(1)
            self.minute += 1
            if self.minute % 60 == 0:
                for m in h.machines:
                    h.fire(m, 'EveryHours')

    def run_minutes(self, minutes: int):
        t0 = time.perf_counter()
        for _ in range(minutes * TICKS_PER_MINUTE):
            self.frame()
        self.wall += time.perf_counter() - t0

    # Mesure -----------------------------------------------------------------------------------------------------
    def start(self, window_ms: int = 60000, heavy_ms: float | None = None):
        for m in self.h.machines.values():
            m.g.LivingKnox.Load.clock = lambda: time.perf_counter() * 1000.0
            self.h.load(m.name, f'assert(LivingKnox.Load.start({{ windowMs = {window_ms} }}))')
        self.h.load('server', NET_MAX)
        if heavy_ms is not None:
            self.h.load('server', HEAVY.replace('THRESHOLD', repr(float(heavy_ms)))
                        .replace('OFFSET', str(self.ticks)))

    def stop(self):
        out = {}
        for name in self.h.machines:
            self.h.load(name, 'BENCH_SUM = LivingKnox.Load.stop()')
            lines = lua_list(self.h.eval(name, 'LivingKnox.Load.lines(BENCH_SUM)'))
            out[name] = {'lines': lines, 'summary': to_py(self.h.eval(name, 'BENCH_SUM'))}
        return out

    def errors(self):
        return {m: self.h.errors(m) for m in self.h.machines}

    def close(self):
        self.h.close()


# LK13-T09 : plus gros message envoyé par commande (taille approchée LK_Load.size), serveur.
NET_MAX = r'''
BENCH_NETMAX = {}
local send = sendServerCommand
sendServerCommand = function(...)
    local a, b, c, d = ...
    local command, args
    if type(a) == "string" then command, args = b, c else command, args = c, d end
    if command ~= nil then
        local n = LivingKnox.Load.size(args)
        local k = tostring(command)
        if n > (BENCH_NETMAX[k] or 0) then BENCH_NETMAX[k] = n end
    end
    return send(...)
end
'''

# LK13-T09 : images du serveur au-dessus d'un seuil (--heavy) : composition par module, les plus lourdes gardées.
HEAVY = r'''
BENCH_HEAVY = { threshold = THRESHOLD, n = 0, frames = {}, byTop = {}, tick = 0, all = {}, offset = OFFSET,
    hourMax = {}, minuteMax = {} }
local L = LivingKnox.Load
local counter = L.counter
L.counter = function(...)
    local s = L.active
    local hv = BENCH_HEAVY
    if s ~= nil and s.measuring then
        hv.tick = hv.tick + 1
        local f = s.frame
        -- Plus lourde image selon sa place après l'heure (0..10) et après la minute (0..24) du banc.
        local hp = (hv.tick + hv.offset - 1) % (25 * 60)
        if hp <= 10 and f.ms > (hv.hourMax[hp + 1] or 0) then hv.hourMax[hp + 1] = f.ms end
        local mp = (hv.tick + hv.offset - 1) % 25
        if hp > 10 and f.ms > (hv.minuteMax[mp + 1] or 0) then hv.minuteMax[mp + 1] = f.ms end
        if f.ms >= hv.threshold then
            hv.n = hv.n + 1
            local mods = {}
            for m, ms in pairs(f.modules) do mods[#mods + 1] = { m = m, ms = ms } end
            table.sort(mods, function(a, b) return a.ms > b.ms end)
            local top = mods[1] and mods[1].m or "?"
            local e = hv.byTop[top] or { n = 0, max = 0 }
            e.n = e.n + 1
            if f.ms > e.max then e.max = f.ms end
            hv.byTop[top] = e
            local parts = {}
            for i = 1, math.min(4, #mods) do parts[i] = string.format("%s %.1f", mods[i].m, mods[i].ms) end
            if #hv.all < 4000 then hv.all[#hv.all + 1] = { tick = hv.tick, top = top } end
            hv.frames[#hv.frames + 1] = { ms = f.ms, tick = hv.tick, text = table.concat(parts, " + ") }
            table.sort(hv.frames, function(a, b) return a.ms > b.ms end)
            if #hv.frames > 12 then hv.frames[13] = nil end
        end
    end
    return counter(...)
end
'''


def to_py(v):
    from lupa import lua51
    if lua51.lua_type(v) == 'table':
        keys = list(v.keys())
        if keys and all(isinstance(k, (int, float)) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(v[i]) for i in range(1, len(keys) + 1)]
        return {str(k): to_py(v[k]) for k in keys}
    return v


# Charge de référence du rapport Kahlua / lupa : un registre de 5 groupes (7 membres, 120 chantiers chacun, ~64 Ko
# RSV2) encodé, passé en hex, contrôlé, relu et décodé (le chemin d'une écriture de registre, LK_Store.writeSlotFile).
FACTOR_BUILD = (
    'local t = {} for g = 1, 5 do local grp = { id = "grp-" .. g, members = {}, fort = {} } '
    'for m = 1, 7 do grp.members["m-" .. m] = { role = "worker", alive = true, wound = 0, duty = "guard", '
    'npc = "lk-" .. m } end '
    'for f = 1, 120 do grp.fort[f] = { x = 1000 + f, y = 2000 + f, z = 0, kind = "wall", tier = 2, have = 3, '
    'steps = { "a", "b" } } end t[#t + 1] = grp end DATA = { groups = t } return "built"')
FACTOR_LOOP = ('local C = require "RadioSurvivor/RS_Codec" for i = 1, {n} do local b = C.encodeBytes(DATA) '
               'local x = C.hexBytes(b) local c = C.checksumBytes(b) local d = C.decodeBytes(C.unhexBytes(x)) end '
               'return "KF done"')
# LK13-T06 : chemin d'écriture du registre des groupes après regroupement : encodage, hex par table de remplacement
# (LK_Store.hexOfBytes), somme de contrôle par blocs (LK_Store.checksumOfBytes), sans relecture.
FACTOR_LOOP_T06 = ('local C = require "RadioSurvivor/RS_Codec" local HX = {{}} for i = 0, 255 do '
                   'HX[string.char(i)] = string.format("%02x", i) end local function ck(s) local a, b, n, i = 1, 0, '
                   '#s, 1 while i <= n do local j = i + 3999 if j > n then j = n end for k = i, j do '
                   'a = a + string.byte(s, k) b = b + a end a, b = a % 65521, b % 65521 i = j + 1 end '
                   'return string.format("%.0f", b * 65536 + a) end for i = 1, {n} do local b = C.encodeBytes(DATA) '
                   'local x = string.gsub(b, ".", HX) local c = ck(b) end return "KF done"')


# LK13-T07 : registre réel du banc (--dump-groups : RSV2 en hex) décodé avant la mesure, à la place de FACTOR_BUILD.
REGISTRY_BUILD = ('local C = require "RadioSurvivor/RS_Codec" DATA = assert(C.decodeBytes(C.unhexBytes(REGISTRY_HEX))) '
                  'return "built"')


def kahlua_factor(rounds: int = 40, loop: str = FACTOR_LOOP, registry: Path | None = None):
    """Temps d'une écriture de registre type dans la VM Kahlua réelle (projectzomboid.jar, banc tests/kahlua) et sous
    lupa ; rend (ms Kahlua, ms lupa, rapport) ou None et la raison si les prérequis de tests/test_kahlua.py manquent.
    Kahlua : différence de durée entre deux JVM (1 et 1 + rounds tours), JIT compris ; ordre de grandeur seulement.
    registry : fichier hex d'un registre (--dump-groups) mesuré à la place du registre type (LK13-T07)."""
    import os
    import shutil
    import subprocess
    import tempfile
    import lupa.lua51 as lupa
    import test_kahlua as tk
    why = tk.missing_prerequisites()
    if why:
        return None, why
    work = Path(tempfile.mkdtemp(prefix='lk_kfactor_'))
    try:
        shutil.copyfile(tk.STDLIB, work / 'stdlib.lua')
        build, pre = FACTOR_BUILD, []
        if registry is not None:
            hexa = registry.read_text(encoding='ascii').strip()
            (work / 'registry.lua').write_text('REGISTRY_HEX = "' + hexa + '"' + chr(10), encoding='ascii')
            build, pre = REGISTRY_BUILD, ['load:bench/registry=' + str(work / 'registry.lua')]
        comp = subprocess.run([str(tk.JAVA), '-jar', str(tk.ECJ), '-21', '-nowarn', '-cp', str(tk.JAR), '-d', str(work),
                               str(tk.BENCH / 'KRun.java')], capture_output=True, text=True, timeout=300)
        if comp.returncode != 0:
            return None, 'KRun.java does not compile: ' + comp.stdout[-300:] + comp.stderr[-300:]

        def jvm(n):
            args = [str(tk.JAVA), '-cp', os.pathsep.join([str(tk.JAR), str(work)]), 'KRun',
                    'load:driver=' + str(tk.BENCH / 'driver.lua'),
                    'load:RadioSurvivor/RS_Codec=' + str(tk.MOD_LUA / 'shared' / 'RadioSurvivor' / 'RS_Codec.lua'),
                    *pre, 'eval:' + build, 'eval:' + loop.format(n=n)]
            t = time.perf_counter()
            p = subprocess.run(args, cwd=work, capture_output=True, text=True, timeout=600)
            if 'KF done' not in p.stdout:
                raise RuntimeError('Kahlua run failed: ' + p.stdout[-300:] + p.stderr[-300:])
            return time.perf_counter() - t

        base = jvm(1)
        full = jvm(1 + rounds)
        k_ms = (full - base) / rounds * 1000
        rt = lupa.LuaRuntime()
        rt.execute('package.path = [[' + (tk.MOD_LUA / 'shared').as_posix() + '/?.lua;]] .. package.path')
        if registry is not None:
            rt.execute((work / 'registry.lua').read_text(encoding='ascii'))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    rt.execute(build)
    t = time.perf_counter()
    rt.execute(loop.format(n=rounds))
    l_ms = (time.perf_counter() - t) / rounds * 1000
    return (round(k_ms, 1), round(l_ms, 1), round(k_ms / l_ms, 2)), None


def error_kinds(errors):
    """Erreurs d'abonnés distinctes (chiffres masqués), avec leur nombre, toutes machines."""
    import re
    kinds = {}
    for machine, lines in errors.items():
        for line in lines:
            key = machine + ': ' + re.sub(r'\d+', 'N', line)[:240]
            kinds[key] = kinds.get(key, 0) + 1
    return dict(sorted(kinds.items(), key=lambda kv: -kv[1]))


def run(minutes: int, seed: int = 7, warmup: int = 1, window_ms: int = 60000, strict: bool = True,
        dump: Path | None = None, heavy_ms: float | None = None):
    bench = LoadBench(seed=seed, strict=strict)
    try:
        bench.run_minutes(warmup)
        bench.start(window_ms, heavy_ms)
        bench.run_minutes(minutes)
        result = bench.stop()
        netmax = to_py(bench.h.eval('server', 'BENCH_NETMAX')) or {}
        heavy = to_py(bench.h.eval('server', 'BENCH_HEAVY')) if heavy_ms is not None else None
        state = to_py(bench.h.eval('server', 'LivingKnox.Load.stateSize()'))
        if dump is not None:   # LK13-T07 : registre des groupes tel qu'écrit (RSV2 en hex), pour --kahlua --registry
            # LK13-T09 : passes de la dernière heure et relectures encore en file faites avant (comparaison avant/après)
            bench.h.load('server', 'local S, St = LivingKnox.Simulation, LivingKnox.Stock '
                                   'if S.finishHour then S.finishHour() end if St.finishQueue then St.finishQueue() end')
            dump.write_text(bench.h.eval('server', '(function() local C = require "RadioSurvivor/RS_Codec" '
                                         'return C.hexBytes(C.encodeBytes(LivingKnox.Groups.state.data)) end)()'),
                            encoding='ascii')
        info = {'minutes': minutes, 'warmup': warmup, 'seed': seed, 'ticks': bench.ticks,
                'wall_s': round(bench.wall, 2), 'groups': bench.groups,
                'bodies': len(lua_list(bench.h.eval('server', 'BENCH_BODIES()'))), 'state': state,
                'errors': {k: len(v) for k, v in bench.errors().items()},
                'error_kinds': error_kinds(bench.errors()), 'net_max': netmax, 'heavy': heavy}
        return info, result
    finally:
        bench.close()


# LK13-T12 : écritures des registres comptées par en-tête, sans LK_Load (enveloppe d'une fonction de module : aucun
# abonné déplacé), et état final des trois registres encodé (RSV2 en hex).
WRITES = r'''
BENCH_WRITES = {}
local Store = LivingKnox.Store
local write = Store.writeSlotFile
Store.writeSlotFile = function(path, header, ...)
    local k = tostring(header)
    BENCH_WRITES[k] = (BENCH_WRITES[k] or 0) + 1
    return write(path, header, ...)
end
'''
STATE_HEX = ('(function() local C = require "RadioSurvivor/RS_Codec" local LK = LivingKnox local out = {} '
             'for name, st in pairs({ registry = LK.Store.state, groups = LK.Groups.state, '
             'attitudes = LK.Hostility.state }) do out[name] = C.hexBytes(C.encodeBytes({ st.data })) end '
             'return out end)()')


def run_compare(minutes: int, measure: bool, seed: int = 7, warmup: int = 1):
    """LK13-T12 : même scénario que run(), mesure LK_Load démarrée ou non après la mise en route. Rend
    { writes = { en-tête: nombre }, state = { registry, groups, attitudes: hex }, errors } : avec et sans mesure,
    les registres et le nombre d'écritures doivent être identiques (la mesure ne change rien au moteur)."""
    bench = LoadBench(seed=seed)
    try:
        bench.h.load('server', WRITES)
        bench.run_minutes(warmup)
        if measure:
            bench.start()
        bench.run_minutes(minutes)
        if measure:
            bench.stop()
        return {'writes': to_py(bench.h.eval('server', 'BENCH_WRITES')) or {},
                'state': to_py(bench.h.eval('server', STATE_HEX)),
                'errors': {k: len(v) for k, v in bench.errors().items()}}
    finally:
        bench.close()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--minutes', type=int, default=60, help='minutes de jeu mesurées (défaut 60)')
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--warmup', type=int, default=1, help='minutes de jeu avant la mesure (défaut 1)')
    ap.add_argument('--window', type=int, default=60000, help='fenêtre de LK_Load en ms réelles simulées')
    ap.add_argument('--json', type=Path, help='écrit les résumés complets dans ce fichier')
    ap.add_argument('--quiet', action='store_true', help='rapport du serveur seulement')
    ap.add_argument('--lenient', action='store_true',
                    help="erreurs d'abonnés comptées sans arrêter le banc (défaut : arrêt à la première)")
    ap.add_argument('--kahlua', action='store_true', help='mesure seulement le rapport de vitesse Kahlua / lupa')
    ap.add_argument('--dump-groups', type=Path,
                    help='écrit le registre des groupes du serveur en fin de banc (RSV2 en hex) dans ce fichier')
    ap.add_argument('--registry', type=Path,
                    help='avec --kahlua : mesure une écriture de ce registre (fichier de --dump-groups)')
    ap.add_argument('--heavy', type=float,
                    help="images du serveur à ce seuil (ms lupa) ou plus : nombre, module principal, les plus lourdes")
    args = ap.parse_args(argv)
    if args.kahlua and args.registry is not None:
        res, why = kahlua_factor(loop=FACTOR_LOOP_T06, registry=args.registry)
        if res is None:
            print(f'kahlua factor: skipped ({why})')
            return 0
        size = len(args.registry.read_text(encoding='ascii').strip())
        print(f'kahlua factor: group registry write of {args.registry.name} ({size} B in hex) {res[0]} ms in Kahlua, '
              f'{res[1]} ms in lupa, ratio {res[2]}')
        return 0
    if args.kahlua:
        res, why = kahlua_factor()
        if res is None:
            print(f'kahlua factor: skipped ({why})')
            return 0
        print(f'kahlua factor: registry write path {res[0]} ms in Kahlua, {res[1]} ms in lupa, ratio {res[2]}')
        res, why = kahlua_factor(loop=FACTOR_LOOP_T06)
        if res is not None:
            print(f'kahlua factor: group registry write without read-back (LK13-T06) {res[0]} ms in Kahlua, '
                  f'{res[1]} ms in lupa, ratio {res[2]}')
        return 0
    info, result = run(args.minutes, args.seed, args.warmup, args.window, strict=not args.lenient,
                       dump=args.dump_groups, heavy_ms=args.heavy)
    for kind, n in info['error_kinds'].items():
        print(f'callback error x{n}: {kind}')
    print(f'load bench: {info["minutes"]} game minute(s) after {info["warmup"]} of warm-up, seed {info["seed"]}, '
          f'{info["ticks"]} ticks, {info["wall_s"]} s wall, groups {", ".join(info["groups"])}, '
          f'{info["bodies"]} bodies at the end, callback errors {info["errors"]}')
    for name, r in result.items():
        if args.quiet and name != 'server':
            continue
        print(f'--- {name}')
        for line in r['lines']:
            print('  ' + line)
        if name == 'server':
            nm = info['net_max']
            print('  net largest message: ' + ', '.join(f'{k} {v} B' for k, v in
                                                        sorted(nm.items(), key=lambda kv: -kv[1])[:6]))
            hv = info['heavy']
            if hv is not None:
                by = hv.get('byTop') or {}
                print(f"  heavy ticks >= {hv['threshold']} ms: {hv['n']} of {hv['tick']}; by top module: " + ', '.join(
                    f"{k} x{v['n']} (max {v['max']:.1f})" for k, v in sorted(by.items(), key=lambda kv: -kv[1]['n'])))
                # Phase dans l'heure de jeu (image 0 = celle de l'EveryHours du banc) : pointes liées au pas horaire ?
                per_hour = TICKS_PER_MINUTE * 60
                near, far = {}, {}
                for f in hv.get('all') or []:
                    phase = (f['tick'] + info['warmup'] * TICKS_PER_MINUTE - 1) % per_hour
                    bucket = near if phase <= 10 else far
                    bucket[f['top']] = bucket.get(f['top'], 0) + 1
                print('  heavy ticks within 10 ticks after the hour: ' + (', '.join(
                    f'{k} x{v}' for k, v in sorted(near.items(), key=lambda kv: -kv[1])) or 'none') +
                    '; elsewhere: ' + (', '.join(f'{k} x{v}' for k, v in sorted(far.items(), key=lambda kv: -kv[1]))
                                       or 'none'))
                def maxes(t, n):
                    t = t or {}
                    if isinstance(t, list):
                        t = {i + 1: v for i, v in enumerate(t)}
                    return ' '.join(f"{float(t.get(i + 1, t.get(str(i + 1), 0)) or 0):.1f}" for i in range(n))
                print('  heaviest tick by place after the hour (tick 0 = EveryHours tick of the bench, then 1..10): '
                      + maxes(hv.get('hourMax'), 11))
                print('  heaviest tick by place after the minute (outside the hour ticks, 0..24): '
                      + maxes(hv.get('minuteMax'), 25))
                for f in hv.get('frames') or []:
                    print(f"    tick {f['tick']}: {f['ms']:.1f} ms = {f['text']}")
    if args.json:
        args.json.write_text(json.dumps({'info': info, 'machines': result}, indent=1, ensure_ascii=False),
                             encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
