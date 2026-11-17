"""Tests hors jeu du contexte de décision d'un membre (LK16-T05, chantier C3) : Decisions.context de
server/LivingKnox/LK_Decisions.lua et les fournisseurs de contexte inscrits par les modules
(Decisions.registerContext).

    python tests/livingknox/test_lk_decision_context.py

Bancs :
- gel : sur une grille de situations (rôles, foyer, perception, cible, coup reçu, reddition, trahison, demande d'aide,
  alerte, expédition, traque, défense, sommation, besoins, nuit et jour, repli débordé), le contexte rendu, la décision
  de Decisions.decide et la suite des appels faits aux modules (arguments compris, contexte au moment de l'appel) ont
  une empreinte sha256 relevée sur le code d'avant le registre ; une grille avec tous les modules chargés, une autre
  avec les seuls modules de LK_Server (les autres absents : leurs champs manquent) ;
- acceptation : un fournisseur inscrit par le banc seul pose un champ lu par la règle d'une extension, sans toucher au
  moteur ;
- ordre : liste des fournisseurs (ordre explicite) et dépendances entre champs ;
- LK16-T06 (chantier C2) : gel de l'application (Decisions.evaluate et Decisions.apply : consignes, gestes, vigilance,
  appels aux modules qui mènent un comportement) sur des séquences de trois passages, relevé avant la migration des
  comportements vers leurs extensions propriétaires ; acceptation : un comportement inscrit par le banc seul est
  décidé, visé, appliqué, garde son geste et est quitté.
Les fonctions des modules sont remplacées par des doublures qui notent leurs appels : elles NE PROUVENT PAS la logique
des modules (prouvée par leurs bancs), seulement ce que le contexte leur demande, dans quel ordre, et ce qu'il en fait.
"""
from __future__ import annotations

import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from harness import routine_files  # noqa: E402
from test_lk_decisions import DECIDERS, PureBase  # noqa: E402

D = 'LivingKnox.Decisions'
# Empreintes (sha256) relevées sur le code d'avant le registre des fournisseurs (LK16-T05). Rebasées le 2026-11-17
# (LK21-T03) : seule différence, le champ de membre wound = n devient health = 1 - n / 100 dans les tables relevées ;
# contextes, décisions et appels identiques (relevés d'avant et d'après comparés champ renommé ôté).
FROZEN_FULL = '2cc44535712eb744a00d8e0965668fe3e1b54c2b495da4f32d0ac8452a65697b'
FROZEN_SERVER = '714f7332cfcc167f84865c3e9724cf813999096ddd4af06927751d6aee383077'
FROZEN_BARE = '7a1d99f6bae8bf9c6c8bb1f6a9dd9a743bfef051ae134fc0161e1c419c777155'
# Modules qui ne sont pas chargés par LK_Server : la grille « full » les charge (ordre du jeu : tri des noms).
EXTRA = ('LK_Health', 'LK_Combat', 'LK_Zombies', 'LK_Defense', 'LK_Encounters', 'LK_Expeditions', 'LK_Relations')

# Grille : doublures des modules (appels notés), situation i, contexte, décision.
GRID = r'''
local function S(v, seen)
    local t = type(v)
    if t == "table" then
        seen = seen or {}
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. S(v[k], seen) end
        seen[v] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "function" then return "fn"
    elseif t == "number" then return string.format("%.10g", v)
    end
    return tostring(v)
end
CTXS = S

LOG = {}
SIT = {}
local function note(name, ...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = S((select(i, ...))) end
    LOG[#LOG + 1] = name .. "(" .. table.concat(parts, ";") .. ")"
end
-- Doublure notée de LivingKnox.<mod>.<fn> (module chargé seulement) ; ret(...) rend la valeur de la situation.
local function fake(mod, fn, ret, quiet)
    local M = LivingKnox[mod]
    if M == nil then return end
    M[fn] = function(...)
        if not quiet then note(mod .. "." .. fn, ...) end
        return ret(...)
    end
end

local function point(x, y, z) return { x = x, y = y, z = z or 0 } end
local function body(x, y, z)
    return { kind = "body", x = x, y = y, z = z, getX = function() return x end, getY = function() return y end,
        getZ = function() return z end, isDead = function() return false end }
end
local function player(name, x, y)
    return { name = name, getUsername = function() return name end, getX = function() return x end,
        getY = function() return y end, getZ = function() return 0 end, isDead = function() return false end }
end
local function zombie(o, x, y)
    return { o = o, getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
        getOnlineID = function() return o end }
end

LivingKnox.Senses = LivingKnox.Senses or {}
fake("Senses", "perceived", function() return SIT.per end)
fake("Routines", "sentryKind", function() return SIT.sentry end)
fake("Routines", "ensurePosts", function() return { posts = SIT.sentry } end)
fake("Routines", "handles", function(b) return SIT.handles[b] end)
fake("Routines", "unfed", function() return SIT.unfed end)
fake("Expeditions", "memberTrip", function() return SIT.trip end)
fake("Relations", "memberHunt", function() return SIT.hunt end)
fake("Hostility", "keyOf", function(p) return SIT.keys and ("k-" .. p.name) or nil end)
fake("Hostility", "get", function(gid, key) local l = SIT.att[key] return l and { level = l } or nil end)
fake("Hostility", "startFor", function() return "start" end)
fake("Hostility", "levelOf", function(s) return SIT.startLevel end)
fake("Hostility", "firstStrike", function() return SIT.firstStrike end)
fake("Hostility", "isCovered", function() return SIT.covered end)
fake("Combat", "targetFor", function() return SIT.ctarget and SIT.ctarget() or nil end)
fake("Zombies", "targetFor", function() return SIT.ztarget and SIT.ztarget() or nil end)
fake("Zombies", "isVanilla", function() return true end)
fake("Zombies", "inWorld", function() return SIT.inWorld end)
fake("Alert", "observe", function() return nil end)
fake("Alert", "forMember", function() return SIT.alert and SIT.alert() or nil end)
fake("Defense", "contextFor", function() return SIT.defense and SIT.defense() or nil end)
fake("Encounters", "contextFor", function() return SIT.warn and SIT.warn() or nil end)
fake("Needs", "perceive", function() return 0 end)
fake("Needs", "fearSource", function() return SIT.fearFrom end)
fake("Needs", "get", function(gid, mid) return SIT.needs[mid] or SIT.needs.all end, true)
fake("Health", "get", function(id) return SIT.hp[id] end, true)
fake("Health", "reference", function(id) return SIT.hp[id] and SIT.hp[id].hp end, true)   -- LK21-T03
fake("Bodies", "find", function(id) return SIT.bodies[id] end, true)

local ROLES = { "fighter", "worker", "medic", "scout" }
DANGERS = { "calm", "calm", "calm", "calm", "calm", "calm", "calm", "calm", "zseen", "zheard", "far", "alice", "bob",
    "both", "horde", "stale", "calice", "czombie", "ztarget", "hit", "oldhit", "surrender", "spared", "betrayed",
    "hzombie", "hplayer", "alert", "defense", "warn", "overwhelmed" }
-- Choix mêlé (carré modulo un premier, trois tours) de l'axe de sel p pour la situation i (q : décalage) : axes non
-- corrélés entre eux.
local function pick(i, p, q, list)
    local h = (i * 31 + q) % 65521
    for r = 1, 3 do h = (h * h + p * 97 + r) % 65521 end
    return list[h % #list + 1]
end

-- Situation i : groupe, membre, corps, joueurs et retours des doublures ; état de Decisions semé.
function SITUATION(i)
    local home = pick(i, 7, 1, { "in", "away", "none", "floor" })
    local g = { type = "deciders", morale = pick(i, 5, 2, { 60, 20, 45 }), objective = pick(i, 3, 0,
        { "settle", "guard", "rest" }), members = {} }
    if home ~= "none" then g.home = { x = 100, y = 100, z = 0 } end
    for k, role in ipairs(ROLES) do
        g.members["m-" .. k] = { role = role, npc = "lk-" .. k, alive = true, health = 1 - ((k * 13 + i) % 40) / 100,
            duty = pick(i + k, 11, 3, k == 1 and { "sentry", "sentry", "keeper" } or { "sentry", "keeper", "rest", "forager", "carer" }) }
    end
    local mi = pick(i, 1, 0, { 1, 2, 3, 4 })
    local mid, m = "m-" .. mi, g.members["m-" .. mi]
    local x, y, z = 100.5, 101.5, 0
    if home == "away" then x, y = 140.5, 128.5 elseif home == "floor" then z = 1 end
    local b = body(x, y, z)
    local players = { player("alice", x + 2, y), player("bob", x + 5, y + 1) }
    local minute = pick(i, 13, 5, { 600, 1380, 1500, 2950 })
    -- Dangers : un premier tiré (calme le plus souvent), parfois un second ; les autres axes sont indépendants.
    local D1 = pick(i, 17, 3, DANGERS)
    local D2 = pick(i, 139, 1, { "calm", "calm", "calm" }) == "calm" and pick(i, 149, 2, DANGERS) or "calm"
    if pick(i, 151, 0, { true, false }) then D2 = "calm" end
    local on = { [D1] = true, [D2] = true }
    local P = nil
    if on.stale then
        P = { stale = true, z = { { o = 901, x = x + 3, y = y, z = z, s = true, d = 3 } }, p = {}, n = {} }
    elseif on.zseen or on.zheard or on.alice or on.bob or on.both or on.horde or on.far then
        P = { stale = false, z = {}, p = {}, n = {} }
        if on.zseen or on.both then P.z[#P.z + 1] = { o = 901, x = x + 3, y = y, z = z, s = true, h = false, d = 3 } end
        if on.zheard then P.z[#P.z + 1] = { o = 902, x = x + 10, y = y, z = z, s = false, h = true, d = 10 } end
        if on.far then P.z[#P.z + 1] = { o = 906, x = x + 40, y = y, z = z, s = true, h = false, d = 40 } end
        if on.alice or on.both then P.p[#P.p + 1] = { u = "alice", x = x + 2, y = y, z = z, s = true, d = 2 } end
        if on.bob then P.p[#P.p + 1] = { u = "bob", x = x + 5, y = y + 1, z = z, s = false, h = true, d = 5.1 } end
        if on.horde then
            for k = 1, 5 do P.z[#P.z + 1] = { o = 910 + k, x = x + k, y = y, z = z, s = true, h = false, d = k } end
        end
    end
    SIT = { per = P, sentry = pick(i, 19, 1, { "guard", "patrol" }),
        handles = { chore = pick(i, 23, 0, { true, false }), meal = pick(i, 29, 1, { true, false }) },
        unfed = pick(i, 31, 0, { false, true }) and { hunger = true } or nil,
        trip = pick(i, 37, 2, { false, false, false, false, true }) and { n = 3, phase = "out" } or nil,
        hunt = pick(i, 41, 1, { false, false, false, true }) and { n = 4, phase = "hunt", kind = "revenge" } or nil,
        keys = pick(i, 43, 0, { true, true, false }), att = pick(i, 47, 1, { { ["k-alice"] = "hostile", ["k-bob"] = "wary" },
            {} }), startLevel = pick(i, 53, 2, { "neutral", "hostile", "wary" }),
        firstStrike = pick(i, 59, 0, { true, true, false }), covered = pick(i, 61, 3, { false, false, true }),
        inWorld = pick(i, 67, 0, { true, false }),
        alert = on.alert and function() return { id = "a-1", kind = "zombie", label = "901", key = "a-1", x = 120, y = 100, z = 0, d = 19.5, level = 2 } end or nil,
        defense = on.defense and function() return { id = "d-1", role = "post", key = "def:post", why = "home defense d-1" } end or nil,
        warn = on.warn and function() return { u = "bob", stage = 1, key = "pbob", why = "warning bob" } end or nil,
        fearFrom = pick(i, 83, 0, { false, true }) and point(110, 100) or nil,
        needs = { all = pick(i, 89, 1, { { hunger = 0, thirst = 0, fatigue = 0, fear = 0 }, { fear = 90 },
            { hunger = 80, thirst = 75, fatigue = 10, fear = 5 }, { fatigue = 95, fear = 40.6 } }) },
        hp = { [m.npc] = pick(i, 97, 0, { false, false, { hp = 40, max = 100 }, { hp = 15, max = 100 }, { hp = 100, max = 100 } }) or nil },
        bodies = {} }
    local ct = on.calice and "alice" or (on.czombie and "zombie" or "none")
    if ct == "alice" then SIT.ctarget = function() return { u = "alice", reason = "hostile", d = 2 } end end
    if ct == "zombie" then SIT.ctarget = function() return { kind = "zombie", u = "z903", d = 1.4, zombie = zombie(903, x + 1, y) } end end
    if on.ztarget then
        SIT.ztarget = function() return { kind = "zombie", u = "z904", d = 1.2, zombie = zombie(904, x + 1, y) } end
    end
    local nb = pick(i, 107, 2, { 0, 1, 4 })
    for k = 1, nb do SIT.bodies["lk-" .. k] = body(x + k, y, z) end
    -- État de Decisions : coups reçus, demande d'aide, redditions, trahisons, état précédent du membre.
    local st = LivingKnox.Decisions.state
    st.hits, st.help, st.surrenders, st.betrayed, st.members = {}, {}, {}, {}, {}
    local hit = on.hit and "recent" or (on.oldhit and "old" or "none")
    if hit == "recent" then st.hits[m.npc] = { u = "alice", minute = minute - 1 } end
    if hit == "old" then st.hits[m.npc] = { u = "alice", minute = minute - 30 } end
    local sur = on.surrender and "mine" or (on.spared and "spared" or "none")
    if sur == "mine" then
        st.members[m.npc] = { b = "surrender", u = "alice", p = 1, key = "palice", untilMin = minute + 1, gid = "grp-9", mid = mid }
        st.surrenders["grp-9"] = { alice = { npc = m.npc, since = minute - 3, last = minute - 1, seen = minute - 1 } }
    elseif sur == "spared" then
        st.surrenders["grp-9"] = { alice = { npc = "lk-77", since = minute - 3, last = minute - 1, seen = minute - 1 } }
    end
    if on.betrayed then st.betrayed["grp-9"] = { alice = minute - 5 } end
    local help = on.hzombie and "zombie" or (on.hplayer and "player" or "none")
    if help == "zombie" then
        st.help["grp-9"] = { npc = "lk-2", kind = "zombie", key = "z905", zombie = zombie(905, x + 4, y), x = math.floor(x + 4),
            y = math.floor(y), z = 0, ox = math.floor(x), oy = math.floor(y), oz = z, minute = minute - 1 }
    elseif help == "player" then
        st.help["grp-9"] = { npc = "lk-2", kind = "player", u = "alice", x = math.floor(x + 2), y = math.floor(y), z = 0,
            ox = math.floor(x), oy = math.floor(y), oz = z, minute = minute - 1 }
    end
    if on.overwhelmed and st.members[m.npc] == nil then
        st.members[m.npc] = { b = "retreat", key = "overwhelmed", p = 1, untilMin = minute + 1 }
    end
    return g, mid, m, b, players, minute
end

-- Contexte, décision et appels notés de la situation i.
function RENDER(i)
    LOG = {}
    local g, mid, m, b, players, minute = SITUATION(i)
    local ctx = LivingKnox.Decisions.context("grp-9", g, mid, m, b, players, minute)
    local out = LivingKnox.Decisions.decide(ctx)
    return "#" .. i .. "\nctx " .. S(ctx) .. "\nout " .. S(out) .. "\ncalls " .. table.concat(LOG, " | ")
end

function RENDER_ALL(n)
    local parts = {}
    for i = 1, n do parts[i] = RENDER(i) end
    return table.concat(parts, "\n")
end
'''

N = 1500


class GridBase(PureBase):
    full = True

    def setUp(self):
        super().setUp()
        if self.full:
            for rel in routine_files():
                self.h.load(self.srv, rel)
            for name in EXTRA:
                self.h.load(self.srv, f'server/LivingKnox/{name}.lua')
        self.h.load(self.srv, DECIDERS)   # type de groupe « deciders » (rôles fighter, worker, medic, scout)
        self.h.load(self.srv, GRID)

    def render(self):
        return self.run_lua(f'return RENDER_ALL({N})')


class FrozenContextTests(GridBase):
    def test_context_decision_and_calls_are_frozen_with_all_modules(self):
        out = self.render()
        for field in ('sentryKind=', 'chores=', 'meals=', 'unfed=', 'trip=', 'hunt=', 'atHome=', 'threat=',
                      'target=', 'morale=', 'hit=', 'surrendered=', 'help=', 'alert=', 'defense=', 'warn=',
                      'fearFrom=', 'overwhelmed='):
            self.assertIn(field, out, field)                                   # la grille couvre chaque champ
        self.assertEqual(hashlib.sha256(out.encode('utf-8')).hexdigest(), FROZEN_FULL)


class FrozenServerContextTests(GridBase):
    """Serveur dédié : la perception transmise à l'alerte porte la cible zombie du serveur (Decisions.withTarget)."""
    mode = 'mp'

    def test_context_on_a_dedicated_server_is_frozen(self):
        out = self.render()
        self.assertIn('Alert.observe(', out)
        self.assertEqual(hashlib.sha256(out.encode('utf-8')).hexdigest(), FROZEN_SERVER)


class FrozenBareContextTests(GridBase):
    full = False

    def test_context_without_the_optional_modules_is_frozen(self):
        out = self.render()
        self.assertNotIn('trip=', out)                                         # modules absents : champs absents
        self.assertNotIn('defense=', out)
        self.assertEqual(hashlib.sha256(out.encode('utf-8')).hexdigest(), FROZEN_BARE)


# LK16-T06 (chantier C2) : gel de l'APPLICATION d'une décision (Decisions.evaluate puis Decisions.apply) sur des
# séquences de trois passages par situation : état neuf, même situation une minute plus tard (état en cours, consigne
# parfois close, consigne bloquée), puis l'état transporté chez le membre d'une autre situation (changement de
# comportement : sorties, gestes retirés), parfois suivi de l'oubli du membre (Decisions.forget). Sont notés : consignes
# (Directives.moveTo, face, stop, setVigil avec arguments), gestes posés (Anim.setGesture), vigilance
# (Senses.setVigilance), appels aux modules qui mènent un comportement (apply, leave, forget, applyHunt) et aux suites
# (Needs.observe, Alert.noteWoken, Alert.raise, Speech.say, Activity.behaviour), état gardé et geste du moteur.
# Empreintes relevées sur le code d'avant la migration des comportements (LK16-T06). Rebasées le 2026-11-16 (LK17-T03,
# lk.windowsally MP) : seule différence, watch et alert ne posent ni regard ni geste tant qu'une course du moteur est
# ouverte (Decisions.runningOwnMove) ; une marche ordinaire est coupée comme avant. Rebasées le 2026-11-17 (LK21-T03) :
# seul le champ de membre renommé (wound -> health) change, application identique (même comparaison).
FROZEN_APPLY_FULL = '0d3cf5f04112a9dc98e861896882a0af41d89d2061bf3fd07760da9cb5090745'
FROZEN_APPLY_BARE = 'af90157d76df94d8ca0bb45cc38d2aecf20ce9ea323bf20f4a571d6982bcd687'
APPLY = r'''
DIR, ANIM, VSEQ, CARE, STUCK = {}, {}, 0, false, false
local function noteApply(mod, fn, ret)
    local M = LivingKnox[mod]
    if M == nil then return end
    M[fn] = function(id, st, ctx, fresh)
        LOG[#LOG + 1] = mod .. "." .. fn .. "(" .. tostring(id) .. ";" .. CTXS(st) .. ";" .. tostring(fresh) .. ")"
        if ret ~= nil then return ret() end
    end
end
local function noteCall(mod, fn, ret)
    local M = LivingKnox[mod]
    if M == nil then return end
    M[fn] = function(...)
        local n = select("#", ...)
        local parts = {}
        for k = 1, n do
            local v = (select(k, ...))
            parts[k] = type(v) == "table" and v.getX ~= nil and "obj" or CTXS(v)
        end
        LOG[#LOG + 1] = mod .. "." .. fn .. "(" .. table.concat(parts, ";") .. ")"
        if ret ~= nil then return ret(...) end
    end
end
local Dr = LivingKnox.Directives
local function issue(id, e)
    if VSEQ % 11 == 5 then VSEQ = VSEQ + 1 return nil end   -- consigne refusée de temps en temps
    VSEQ = VSEQ + 1
    e.v = VSEQ
    DIR[id] = e
    return VSEQ
end
Dr.get = function(id) return DIR[id] end
noteCall("Directives", "moveTo", function(id, x, y, z, g) return issue(id, { op = Dr.OP_MOVE, x = x, y = y, z = z, g = g }) end)
noteCall("Directives", "face", function(id, a) return issue(id, { op = Dr.OP_FACE, a = a }) end)
noteCall("Directives", "stop", function(id) return issue(id, { op = Dr.OP_STOP }) end)
noteCall("Directives", "setVigil", function() return true end)
noteCall("Senses", "setVigilance", function() return true end)
local An = LivingKnox.Anim
if An ~= nil then
    An.gestureOf = function(id) return ANIM[id] or An.DEFAULT end
    noteCall("Anim", "setGesture", function(id, g) ANIM[id] = g return true end)
end
noteApply("Combat", "apply")
noteCall("Combat", "leave")
noteCall("Combat", "forget")
noteCall("Combat", "playerByName", function(u) if u == "alice" then return { getX = function() return 103 end,
    getY = function() return 100 end, getZ = function() return 0 end } end return nil end)
noteApply("Defense", "apply")
noteCall("Defense", "forget")
noteApply("Expeditions", "apply")
noteApply("Relations", "applyHunt")
noteApply("Encounters", "apply")
noteCall("Encounters", "forget")
noteApply("Care", "apply", function() return CARE end)
noteApply("Routines", "apply")
noteCall("Routines", "leave")
noteCall("Routines", "forget")
noteCall("Routines", "handles", function(b)
    if b == "guard" or b == "patrol" then return SIT.post == true end
    return SIT.handles[b] == true
end)
noteCall("Needs", "observe")
noteCall("Alert", "noteWoken")
noteCall("Alert", "raise")
LivingKnox.Speech = LivingKnox.Speech or {}
noteCall("Speech", "say", function(id, what) return { id = "line-" .. tostring(what.key) } end)
LivingKnox.Movement = LivingKnox.Movement or {}
noteCall("Movement", "takeStuck", function() return STUCK end)
noteCall("Activity", "behaviour")
local Ma = LivingKnox.Materialize
if Ma ~= nil then
    noteCall("Materialize", "homeSquare", function(home) return { kind = "sq" }, "b-1" end)
    noteCall("Materialize", "placeFor", function(home)
        if VSEQ % 3 == 0 then return nil end
        return { getX = function() return home.x + 1 end, getY = function() return home.y end,
            getZ = function() return home.z end }
    end)
end
local CELL = { getGridSquare = function(self, x, y, z)
    return { isFree = function() return (x * 3 + y) % 4 ~= 0 end }
end }
getCell = function() return CELL end

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- Séquence de la situation i (voir le commentaire du banc) : rend les trois passages notés.
function SEQUENCE(i, n)
    local De = LivingKnox.Decisions
    local st = De.state
    DIR, ANIM, VSEQ = {}, {}, i % 7
    st.issued, st.gestures = {}, {}
    local g, mid, m, b, players, minute = SITUATION(i)
    SIT.post = i % 3 == 0
    CARE, STUCK = i % 4 == 0, false
    if i % 13 == 0 then DIR[m.npc] = { op = Dr.OP_MOVE, v = -1 } end   -- consigne d'un autre module
    local parts = {}
    local function pass(tag, gg, mmid, mm, bb, pl, mn)
        LOG = {}
        local fresh = De.evaluate("grp-9", gg, mmid, mm, bb, pl, mn)
        parts[#parts + 1] = tag .. " " .. tostring(fresh) .. " st " .. CTXS(st.members[mm.npc]) .. " gesture "
            .. tostring(st.gestures[mm.npc]) .. " anim " .. tostring(ANIM[mm.npc]) .. " calls " .. table.concat(LOG, " | ")
    end
    pass("1", g, mid, m, b, players, minute)
    if i % 5 == 1 and DIR[m.npc] ~= nil then DIR[m.npc].done = true end   -- consigne close entre deux passages
    CARE, STUCK = i % 6 == 1, i % 9 == 4
    pass("2", g, mid, m, b, players, minute + 1)
    local keep = { member = copy(st.members[m.npc]), issued = st.issued[m.npc], gesture = st.gestures[m.npc],
        dir = DIR[m.npc], anim = ANIM[m.npc] }
    local j = (i * 7) % n + 1
    local g2, mid2, m2, b2, players2, minute2 = SITUATION(j)
    SIT.post = j % 3 == 0
    CARE, STUCK = j % 4 == 1, false
    if keep.member ~= nil and st.members[m2.npc] == nil then
        keep.member.gid, keep.member.mid = "grp-9", mid2
        st.members[m2.npc] = keep.member
    end
    st.issued[m2.npc], st.gestures[m2.npc], DIR[m2.npc], ANIM[m2.npc] = keep.issued, keep.gesture, keep.dir, keep.anim
    pass("3", g2, mid2, m2, b2, players2, minute2 + 2)
    if i % 7 == 0 then
        LOG = {}
        De.forget(m2.npc)
        parts[#parts + 1] = "forget calls " .. table.concat(LOG, " | ")
    end
    return "#" .. i .. "\n" .. table.concat(parts, "\n")
end

function SEQUENCE_ALL(n)
    local parts = {}
    for i = 1, n do parts[i] = SEQUENCE(i, n) end
    parts[#parts + 1] = "stats " .. CTXS(LivingKnox.Decisions.stats)
    return table.concat(parts, "\n")
end
'''


class ApplyGridBase(GridBase):
    """Consignes et gestes chargés dans les deux grilles (le jeu les charge toujours) ; soin dans la grille complète."""

    def setUp(self):
        super().setUp()
        for rel in ('shared/LivingKnox/LK_Anim.lua', 'server/LivingKnox/LK_Directives.lua') + (
                ('server/LivingKnox/LK_Care.lua',) if self.full else ()):
            self.h.load(self.srv, rel)
        self.h.load(self.srv, APPLY)

    def sequences(self):
        return self.run_lua(f'return SEQUENCE_ALL({N})')


class FrozenApplyTests(ApplyGridBase):
    def test_application_with_all_modules_is_frozen(self):
        out = self.sequences()
        for call in ('Directives.moveTo(', 'Directives.face(', 'Directives.stop(', 'Directives.setVigil(',
                     'Anim.setGesture(', 'Senses.setVigilance(', 'Combat.apply(', 'Combat.leave(', 'Combat.forget(',
                     'Defense.apply(', 'Defense.forget(', 'Expeditions.apply(', 'Relations.applyHunt(',
                     'Encounters.apply(', 'Encounters.forget(', 'Care.apply(', 'Routines.apply(', 'Routines.leave(',
                     'Routines.forget(', 'Needs.observe(', 'Speech.say('):
            self.assertIn(call, out, call)                                     # la grille couvre chaque appel
        for b in ('fight', 'defend', 'expedition', 'revenge', 'warn', 'surrender', 'retreat', 'watch', 'alert',
                  'flee', 'guard', 'patrol', 'home', 'rest', 'sleep', 'chore'):
            self.assertIn(f'b={b},', out, b)                                   # et chaque comportement
        self.assertEqual(self.h.errors(self.srv), [])
        self.assertEqual(hashlib.sha256(out.encode('utf-8')).hexdigest(), FROZEN_APPLY_FULL)


class FrozenBareApplyTests(ApplyGridBase):
    """Modules de LK_Server seuls : un comportement dont le module manque retombe sur le repli du moteur."""
    full = False

    def test_application_without_the_optional_modules_is_frozen(self):
        out = self.sequences()
        self.assertNotIn('Combat.apply(', out)
        self.assertIn('b=fight,', out)                                         # mêlée décidée (renfort), sans Combat
        self.assertEqual(self.h.errors(self.srv), [])
        self.assertEqual(hashlib.sha256(out.encode('utf-8')).hexdigest(), FROZEN_APPLY_BARE)


# Acceptation LK16-T06 : un comportement nouveau inscrit par le banc seul (fournisseur de contexte, règle, visée, geste,
# application, sortie), sans rien toucher au moteur. Le membre écoute un bruit près du foyer : il le regarde (visée
# portée par le comportement), s'accroupit (geste qu'il pose et garde), puis le quitte quand le bruit cesse.
LISTEN = r'''
NOISE_ON, BENCH = true, {}
local De = LivingKnox.Decisions
De.registerContext({ id = "bench.noise", order = 45, fill = function(ctx)
    if NOISE_ON and ctx.atHome then ctx.noise = { x = ctx.home.x + 3, y = ctx.home.y } end
end })
De.registerExtension({ id = "bench.listen", order = 5,
    rules = { { name = "listen", before = "threat", rule = function(ctx)
        if ctx.noise == nil then return nil end
        return "bench.listen", "noise", "noise"
    end } },
    behaviour = { vigil = "guard", minutes = { 3, 3 } },
    aim = function(ctx, out) out.angle = De.angleTo(ctx.noise.x + 0.5 - ctx.x, ctx.noise.y + 0.5 - ctx.y) end,
    gesture = function() return true end,
    apply = function(id, st, ctx, fresh)
        BENCH[#BENCH + 1] = "apply " .. tostring(fresh)
        if fresh then De.face(id, st.angle) end   -- consigne notée comme celle du moteur
        De.setAlertGesture(id, "crouch")
    end,
    leave = function(id) BENCH[#BENCH + 1] = "leave " .. id end })
function LISTEN_PASS(i, minute)
    LOG, BENCH = {}, {}
    local st = De.state
    local g, mid, m, b, players, mn = SITUATION(i)
    st.members[m.npc] = KEPT
    local fresh = De.evaluate("grp-9", g, mid, m, b, players, minute or mn)
    KEPT = st.members[m.npc]
    return fresh, KEPT.b, KEPT.angle, table.concat(BENCH, ","), table.concat(LOG, " | "), m.npc, mn
end
'''


# Première situation de la grille d'un membre valide au foyer, sans danger ni consigne d'un autre module (avant le banc).
CALM = f'''
for i = 1, {N} do
    local g, mid, m, b, players, minute = SITUATION(i)
    local ctx = {D}.context("grp-9", g, mid, m, b, players, minute)
    local out = {D}.decide(ctx)
    if i % 13 ~= 0 and ctx.atHome and out.rule ~= "threat" and {D}.unfitOf(ctx) == nil then return i end
end
return nil
'''


class BehaviourExtensionTests(ApplyGridBase):
    def test_a_behaviour_registered_by_one_file_is_decided_applied_aimed_and_left(self):
        i = self.run_lua(CALM)
        self.assertIsNotNone(i)
        self.h.load(self.srv, LISTEN)
        self.run_lua('KEPT = nil')
        fresh, b, angle, bench, calls, npc, minute = self.run_lua(f'return LISTEN_PASS({i})')
        self.assertEqual((fresh, b, bench), (True, 'bench.listen', 'apply true'))
        self.assertEqual(angle, self.ev(f'{D}.angleTo(103.5 - 100.5, 100.5 - 101.5)'))   # visée portée par l'extension
        self.assertIn(f'Directives.face({npc};{angle:.10g})', calls)
        self.assertIn(f'Senses.setVigilance({npc};guard)', calls)                     # vigilance déclarée
        self.assertIn(f'Anim.setGesture({npc};crouch)', calls)
        # Passage suivant : état en cours, geste gardé (ni retiré ni reposé).
        fresh, b, _, bench, calls, _, _ = self.run_lua(f'return LISTEN_PASS({i}, {minute + 1})')
        self.assertEqual((fresh, b, bench), (False, 'bench.listen', 'apply false'))
        self.assertNotIn('Anim.setGesture(', calls)
        # Bruit retombé : autre comportement, sortie appelée une fois, geste retiré par le moteur.
        self.run_lua('NOISE_ON = false')
        fresh, b, _, bench, calls, _, _ = self.run_lua(f'return LISTEN_PASS({i}, {minute + 2})')
        self.assertTrue(fresh)
        self.assertNotEqual(b, 'bench.listen')
        self.assertEqual(bench, f'leave {npc}')
        self.assertIn(f'Anim.setGesture({npc};idle)', calls)
        self.assertEqual(self.h.errors(self.srv), [])

    def test_malformed_behaviour_fields_are_refused(self):
        base = 'id = "bench.bad", order = 1, apply = function() end'
        for extra in ('aim = 3', 'gesture = "crouch"', 'overlay = 1', 'keeps = "fight"', 'forget = true',
                      'behaviour = { vigil = "rest" }, id = "guard"'):   # redéclarer la liste fermée : refusé
            ok, err = self.run_lua(f'return pcall({D}.registerExtension, {{ {base}, {extra} }})')
            self.assertIs(ok, False, extra)
            self.assertIn('LivingKnox.Decisions.registerExtension', err)


# Fournisseur et règle d'extension inscrits par le banc seul : le champ « noise » (bruit entendu près du foyer) est posé
# après le foyer (ordre 45) et lu par une règle placée avant la menace ; le moteur n'en sait rien.
NOISE = r'''
SEEN_BY_NOISE = nil
LivingKnox.Decisions.registerContext({ id = "bench.noise", order = 45, fill = function(ctx, src)
    SEEN_BY_NOISE = { atHome = ctx.atHome, threats = ctx.threats ~= nil, gid = src.gid, players = #src.players,
        body = src.body ~= nil, group = src.g ~= nil, member = src.m ~= nil }
    if ctx.atHome then ctx.noise = { x = ctx.home.x + 3, y = ctx.home.y } end
end })
LivingKnox.Decisions.registerExtension({ id = "bench.listen", order = 1, rules = { { name = "listen", before = "threat",
    rule = function(ctx)
        if ctx.noise == nil then return nil end
        return "watch", string.format("noise at %d,%d", ctx.noise.x, ctx.noise.y), "noise"
    end } } })
'''

# Contexte et décision de la situation i : bruit posé, règle, raison, au foyer, menace, alerte.
DECIDE = (f'LOG = {{}} local g, mid, m, b, players, minute = SITUATION(%d) '
          f'local ctx = {D}.context("grp-9", g, mid, m, b, players, minute) local out = {D}.decide(ctx) '
          f'return ctx.noise ~= nil, out.rule, out.why, ctx.atHome == true, ctx.threat ~= nil, ctx.alert ~= nil')


class ProviderTests(GridBase):
    def calm_at_home(self):
        """Première situation de la grille d'un membre au foyer, sans menace ni alerte."""
        for i in range(1, N + 1):
            _, _, _, at_home, threat, alert = self.run_lua(DECIDE % i)
            if at_home and not threat and not alert:
                return i
        self.fail('no calm member at home in the grid')

    def test_a_provider_registered_by_one_file_feeds_an_extension_rule(self):
        i = self.calm_at_home()
        self.h.load(self.srv, NOISE)
        noise, rule, why, at_home, _, _ = self.run_lua(DECIDE % i)
        self.assertEqual((noise, rule, why, at_home), (True, 'listen', 'noise at 103,100', True))
        seen = self.run_lua('local s = SEEN_BY_NOISE return s.atHome, s.threats, s.gid, s.players, s.body, s.group, '
                            's.member')
        self.assertEqual(tuple(seen), (True, False, 'grp-9', 2, True, True, True))   # après le foyer, avant les menaces

    def test_a_provider_registered_again_replaces_the_previous_one(self):
        self.h.load(self.srv, NOISE)
        n = self.ev(f'#{D}.contextProviders')
        self.h.load(self.srv, NOISE)
        self.assertEqual(self.ev(f'#{D}.contextProviders'), n)

    def test_a_malformed_provider_is_refused(self):
        for spec in ('{ order = 1, fill = function() end }', '{ id = "x", fill = function() end }',
                     '{ id = "x", order = 1 }', '{ id = "x", order = 1, fill = 3 }'):
            ok, err = self.run_lua(f'return pcall({D}.registerContext, {spec})')
            self.assertIs(ok, False, spec)
            self.assertIn('LivingKnox.Decisions.registerContext', err)


# Ordre des fournisseurs (tous les modules chargés) et champs que chacun lit : un champ lu est posé avant (src.per :
# perception posée par le fournisseur « perception » ; « fear » : montée de la peur, Needs.perceive).
ORDER = ['routines', 'expedition', 'hunt', 'home', 'perception', 'threats', 'target', 'defence', 'alert', 'defense',
         'warn', 'fear', 'needs', 'overwhelmed']
WRITES = {'routines': ['sentryKind', 'chores', 'meals', 'unfed'], 'expedition': ['trip'], 'hunt': ['hunt'],
          'home': ['homeDist', 'atHome'], 'perception': ['per'], 'threats': ['threats', 'threat'],
          'target': ['target'], 'defence': ['morale', 'hit', 'seen', 'canSurrender', 'surrendered', 'betrayed', 'help'],
          'alert': ['alert'], 'defense': ['defense'], 'warn': ['warn'], 'fear': ['fear', 'fearFrom'],
          'needs': ['needs'], 'overwhelmed': ['overwhelmed']}
READS = {'hunt': ['trip'], 'threats': ['per'], 'target': ['per'], 'defence': ['target', 'per'],
         'alert': ['per', 'target', 'atHome'], 'defense': ['alert', 'threats', 'target', 'atHome'],
         'warn': ['per', 'target'], 'fear': ['threats'], 'needs': ['fear'],
         'overwhelmed': ['threats', 'needs', 'atHome']}
PROVIDER_IDS = f'local out = {{}} for i, p in ipairs({D}.contextProviders) do out[i] = p.id end return table.concat(out, ",")'


class OrderTests(GridBase):
    def test_providers_run_in_their_explicit_order(self):
        self.assertEqual(self.run_lua(PROVIDER_IDS).split(','), ORDER)
        orders = self.run_lua(f'local out = {{}} for i, p in ipairs({D}.contextProviders) do out[i] = p.order end '
                              f'return table.concat(out, ",")').split(',')
        self.assertEqual([int(o) for o in orders], sorted({int(o) for o in orders}))   # ordres distincts, croissants

    def test_every_field_is_written_before_it_is_read(self):
        rank = {pid: i for i, pid in enumerate(ORDER)}
        written = {}
        for pid in ORDER:
            for f in WRITES[pid]:
                written.setdefault(f, rank[pid])
        for pid, fields in READS.items():
            for f in fields:
                self.assertLess(written[f], rank[pid], f'{pid} reads {f}')

    def test_extension_inputs_run_after_every_provider(self):
        self.h.load(self.srv, r'''
        LATE = nil
        LivingKnox.Decisions.registerExtension({ id = "bench.late", order = 1, input = function(ctx)
            LATE = ctx.needs ~= nil and ctx.threats ~= nil and ctx.sentryKind ~= nil
        end })''')
        self.run_lua(f'local g, mid, m, b, players, minute = SITUATION(1) '
                     f'{D}.context("grp-9", g, mid, m, b, players, minute)')
        self.assertIs(self.ev('LATE'), True)


class BareOrderTests(GridBase):
    full = False

    def test_without_a_module_its_provider_is_absent(self):
        self.assertEqual(self.run_lua(PROVIDER_IDS).split(','),
                         [p for p in ORDER if p not in ('expedition', 'hunt', 'defense', 'warn')])


if __name__ == '__main__':
    unittest.main()
