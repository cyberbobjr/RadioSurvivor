"""Banc Kahlua réel : le moteur RST et ses suites exécutés dans la VM Kahlua de `projectzomboid.jar`, hors du jeu.

    python RadioSurvivor/tests/test_kahlua.py

Compile `tests/kahlua/KRun.java` avec ECJ (compilateur Eclipse, un seul jar : le JRE du jeu n'a pas de `javac`),
puis lance une seule JVM qui charge les fichiers Lua comme le jeu (UTF-8 vers le lexeur Kahlua), injecte une horloge
simulée (`RST.clock`) et fait avancer les ticks depuis Java (`KahluaThread.pcall` par tick, comme un événement du
jeu). Vérifie : `rst.selftest` PASS ; `rst.failures` donne les FAIL / ERROR attendus et le passage se termine
(`onDone` appelé) ; `rs.codec` (15/15, E00-T08) et `rs.missions` exécutés ; logique d'identité Living Knox (`LK_Identity.lua`, LK02-T02) registre des groupes (`LK_Groups.lua`, LK08-T01) et types de groupes en données (`LK_GroupTypes.lua`, LK08-T02), simulation hors écran (`LK_Simulation.lua`, LK09-T01). Échanges avec le pont (E00-T09) :
une demande RSV2 accentuée encodée par la VM Kahlua est décodée par `bridge/npc_protocol.py`, et une réponse encodée
par Python est relue par la VM Kahlua, sans mojibake.
Fiches de voix (E05-T01) : `RS_Persona` lit dans la VM réelle les lignes que rendrait `getFileReader` (accents, hors BMP,
BOM, U+FFFD) et donne les mêmes fiches et les mêmes refus que `bridge/persona_store.py`.
Module « Émettre » (E06-T02) : logique de `RS_RadioTalk.lua` dans la VM réelle et suites `rs.radiomodule` déclarées.

Prérequis (sinon les tests sont sautés) :
    jeu        RS_PZ_DIR (défaut : tools/pz_paths.py, PZ_STEAM_LIBRARY ou détection Steam) : projectzomboid.jar,
               stdlib.lua, jre64\\bin\\java.exe
    ECJ        RS_ECJ_JAR, sinon tests/kahlua/ecj.jar (jamais versionné) : Maven Central
               org/eclipse/jdt/ecj/3.40.0/ecj-3.40.0.jar
Ne prouve pas l'API Java du jeu ni le chargement réel des mods : le serveur dédié de test reste nécessaire.
"""
from __future__ import annotations

import os
import shutil
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / 'tests' / 'kahlua'
TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
MOD_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
PZ_DIR = pz_paths.game_dir()
ECJ = Path(os.environ['RS_ECJ_JAR']) if os.environ.get('RS_ECJ_JAR') else BENCH / 'ecj.jar'
JAR = PZ_DIR / 'projectzomboid.jar'
JAVA = PZ_DIR / 'jre64' / 'bin' / ('java.exe' if os.name == 'nt' else 'java')
STDLIB = PZ_DIR / 'stdlib.lua'

# Fichiers chargés, dans l'ordre, sous le nom utilisé par require.
# Modules qui s'abonnent a des evenements au chargement (LivingKnox.subscribe lit Events) : charges avec une table
# Events vide (aucun abonne inscrit), comme LK_Fortify plus bas.
EVENTS_AT_LOAD = {'LivingKnox/LK_Decisions'}
LUA_FILES = [
    ('driver', BENCH / 'driver.lua'),
    ('RST/RST', TESTS_LUA / 'shared' / 'RST' / 'RST.lua'),
    ('RST/RST_LKHelpers', TESTS_LUA / 'shared' / 'RST' / 'RST_LKHelpers.lua'),
    ('RST/RST_LKProbe', TESTS_LUA / 'shared' / 'RST' / 'RST_LKProbe.lua'),
    ('RadioSurvivor/RS_Config', MOD_LUA / 'shared' / 'RadioSurvivor' / 'RS_Config.lua'),
    ('RadioSurvivor/RS_Codec', MOD_LUA / 'shared' / 'RadioSurvivor' / 'RS_Codec.lua'),
    ('RadioSurvivor/RS_Reputation', MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_Reputation.lua'),
    ('RadioSurvivor/RS_NPCProvider', MOD_LUA / 'shared' / 'RadioSurvivor' / 'RS_NPCProvider.lua'),  # RS_Missions
    ('RadioSurvivor/RS_Missions', MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_Missions.lua'),
    ('RadioSurvivor/RS_Persona', MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_Persona.lua'),
    ('RadioSurvivor/RadioSurvivor_Const', MOD_LUA / 'shared' / 'RadioSurvivor' / 'RadioSurvivor_Const.lua'),
    ('RadioSurvivor/RS_Personas', MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_Personas.lua'),
    ('RadioSurvivor/RS_RadioHistory', MOD_LUA / 'client' / 'RadioSurvivor' / 'RS_RadioHistory.lua'),
    ('RadioSurvivor/RS_MapActions', MOD_LUA / 'client' / 'RadioSurvivor' / 'RS_MapActions.lua'),
    ('RadioSurvivor/RS_RadioTalk', MOD_LUA / 'client' / 'RadioSurvivor' / 'RS_RadioTalk.lua'),
    ('LivingKnox/LK_Core', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Core.lua'),
    ('LivingKnox/LK_Config', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Config.lua'),
    ('LivingKnox/LK_Log', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Log.lua'),
    ('LivingKnox/LK_Appearance', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Appearance.lua'),
    ('LivingKnox/LK_Identity', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Identity.lua'),
    # LK08-T02 : registre des types de groupes, puis les fichiers de données comme le balayage du jeu les exécute.
    ('LivingKnox/LK_GroupTypes', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_GroupTypes.lua'),
    ('LivingKnox/Data/LK_Type_neutrals', MOD_LUA / 'shared' / 'LivingKnox' / 'Data' / 'LK_Type_neutrals.lua'),
    ('LivingKnox/Data/LK_Type_raiders', MOD_LUA / 'shared' / 'LivingKnox' / 'Data' / 'LK_Type_raiders.lua'),
    ('LivingKnox/Data/LK_Type_settlers', MOD_LUA / 'shared' / 'LivingKnox' / 'Data' / 'LK_Type_settlers.lua'),
    ('LivingKnox/LK_Store', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Store.lua'),
    ('LivingKnox/LK_Groups', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Groups.lua'),
    # LK09-T01 : simulation hors écran (logique pure sur un registre en mémoire).
    ('LivingKnox/LK_Simulation', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Simulation.lua'),
    # LK02-T14 : remise debout des corps (requis par LK_Bodies ; abonne OnZombieCreate seulement ici).
    ('LivingKnox/LK_Stand', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Stand.lua'),
    # LK07-T10 : renvoi d'un cadavre manqué par un client (requis par LK_Bodies).
    ('LivingKnox/LK_Death', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Death.lua'),
    # LK12-T01 : API publique en lecture (registres en memoire ; LK_Bodies pour les corps lies, aucun ici).
    ('LivingKnox/LK_Bodies', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Bodies.lua'),
    # LK11-T03 : attitudes des groupes envers les joueurs (registre en memoire ; requis par LK_API).
    ('LivingKnox/LK_Hostility', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Hostility.lua'),
    # LK10-T02 : journal de recit (requis par LK_API ; alimente par LK_Groups.appendLog).
    ('LivingKnox/LK_Journal', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Journal.lua'),
    ('LivingKnox/LK_API', MOD_LUA / 'server' / 'LivingKnox' / 'LK_API.lua'),
    # LK05-T01 : modele de perception (fonctions pures ; le passage sur le monde est teste sous lupa).
    ('LivingKnox/LK_Senses', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Senses.lua'),
    # LK05-T02 : cadre de decision (fonctions pures ; les passages sur les corps sont testes sous lupa). LK13-T11 :
    # file de notation horaire inscrite a OnTick au chargement (EVENTS_AT_LOAD).
    ('LivingKnox/LK_Decisions', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Decisions.lua'),
    # LK05-T08 : alerte de groupe (fonctions pures ; les passages sur les corps sont testes sous lupa).
    ('LivingKnox/LK_Alert', MOD_LUA / 'server' / 'LivingKnox' / 'LK_Alert.lua'),
    # LK13-T02 : mesure de charge (enveloppes d'abonnes et reseau ; Events absent au chargement : aucun abonne).
    ('LivingKnox/LK_Load', MOD_LUA / 'shared' / 'LivingKnox' / 'LK_Load.lua'),
    ('suite/selftest', TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RST_SelfTest.lua'),
    ('suite/failures', TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RST_Failures.lua'),
    ('suite/codec', TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_Codec.lua'),
    ('suite/missions', TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_Missions.lua'),
    # E05-T06 : déclaration seule (compilée et déclarée dans la VM réelle ; exécutée en jeu et sous lupa).
    ('suite/voices', TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_Voices.lua'),
    # E06-T02 : déclaration seule (interface du client : exécutée en jeu et sous lupa, tests/test_rs_suites.py).
    ('suite/radiomodule', TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_RadioModule.lua'),
    # E03-T02 : déclaration seule (interface du client : exécutée en jeu et sous lupa, tests/test_notebook_visual.py).
    ('suite/notebookvisual', TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_NotebookVisual.lua'),
]
RUNS = ['rst', 'rst.failures', 'rs.codec', 'rs.missions']
MAX_TICKS = 5000
sys.path.insert(0, str(ROOT / 'bridge'))
sys.path.insert(0, str(ROOT / 'tests'))
import npc_protocol as protocol  # noqa: E402
import persona_store  # noqa: E402
import test_personas  # noqa: E402

# Texte accentué, ponctuation typographique, euro, ligature et caractère hors BMP (paire de substitution en Kahlua).
ACCENTED = 'Été : l’abri coûte 5 €, œuvre 📻.'


def java_arg(arg: str) -> str:
    """Argument d'un fichier @ du lanceur java : entre guillemets, \\ et " échappés (arguments ASCII, sans saut de ligne)."""
    if not arg.isascii() or '\n' in arg or '\r' in arg:
        raise ValueError('KRun argument must be ASCII on one line: ' + arg[:60])
    return '"' + arg.replace('\\', '\\\\').replace('"', '\\"') + '"'


def lua_literal(text: str) -> str:
    """Littéral Lua ASCII : chaque caractère non ASCII en échappements décimaux de ses octets UTF-8 (lexeur Kahlua)."""
    out = []
    for ch in text:
        if ch in '"\\' or not 32 <= ord(ch) < 127:
            out.extend('\\%d' % b for b in ch.encode('utf-8'))
        else:
            out.append(ch)
    return '"' + ''.join(out) + '"'


REPLY = {'version': 2, 'kind': 'npc_reply', 'id': 'run-a-npc-a-1', 'text': ACCENTED, 'intent': 'none', 'offer': ''}
EXCHANGE_EVALS = [
    # E05-T06 : suites rs.voices déclarées sans erreur dans la VM réelle (nombre de tests, erreur de déclaration).
    'eval:local out = {} for _, e in ipairs(RST.list("rs.voices")) do out[#out + 1] = e.name .. "=" .. e.count '
    '.. "/" .. tostring(e.error) end return "KR-VOICES " .. table.concat(out, " ")',
    # E06-T02 : logique du module « Émettre » dans la VM réelle (visibilité, deux dernières lignes, coupe à 200).
    'eval:local T = require("RadioSurvivor/RS_RadioTalk"); local function d(tw, on, mu) return { getIsTwoWay = '
    'function() return tw end, getIsTurnedOn = function() return on end, getMicIsMuted = function() return mu end } '
    'end local s = tostring(T.moduleShown(d(true, true, false))) .. tostring(T.moduleShown(d(true, false, false))) '
    '.. tostring(T.moduleShown(d(true, true, true))) .. tostring(T.moduleShown(d(false, true, false))) '
    'for i = 1, 4 do CLOCK = CLOCK + 3000; T.recordLine(145000, "l" .. i) end '
    'return "KR-RADIOTALK " .. s .. " " .. table.concat(T.lastLines(145000), ",") .. " " '
    '.. string.len(T.cleanText(" " .. string.rep("ab", 150)))',
    # E06-T04 : copie client de l'historique radio dans la VM réelle (40 lignes gardées, voyant sans onglet ouvert).
    'eval:local H = require("RadioSurvivor/RS_RadioHistory"); local lines = {} for i = 1, 45 do '
    'lines[i] = { kind = "said", text = "t" .. i, when = "", seq = i } end '
    'H.receive("history_lines", { character = "c", khz = 145000, last = 45, lines = lines }) '
    'H.receive("history_add", { character = "c", khz = 146000, last = 46, line = { kind = "heard", text = "h", seq = 46 } }) '
    'local l = H.lines(145000) return "KR-HISTORY " .. #l .. " " .. l[1].text .. " " .. tostring(H.unread) '
    '.. " " .. H.sorted()[1].khz',
    # E06-T02 : suites rs.radiomodule déclarées sans erreur dans la VM réelle.
    'eval:local out = {} for _, e in ipairs(RST.list("rs.radiomodule")) do out[#out + 1] = e.name .. "=" .. e.count '
    '.. "/" .. tostring(e.error) end return "KR-RADIOMODULE " .. table.concat(out, " ")',
    # E03-T02 : suite rs.notebook.visual déclarée sans erreur dans la VM réelle.
    'eval:local out = {} for _, e in ipairs(RST.list("rs.notebook.visual")) do out[#out + 1] = e.name .. "=" .. e.count '
    '.. "/" .. tostring(e.error) end return "KR-NBVISUAL " .. table.concat(out, " ")',
    # Runtime detected by the codec, UTF-16 string length of the sample.
    r'eval:return "KR-CODEC utf16=" .. tostring(#"\195\169" == 1) .. " len=" .. #' + lua_literal(ACCENTED),
    # Lua -> Python: request payload exactly as RS_Transport writes it.
    'eval:local C = require("RadioSurvivor/RS_Codec"); return "KR-PAYLOAD " .. C.hexBytes(C.encodeBytes({version = 2, '
    'kind = "npc_talk", text = ' + lua_literal(ACCENTED) + '}))',
    # Python -> Lua: reply payload read as RS_Transport reads it.
    'eval:local C = require("RadioSurvivor/RS_Codec"); local v = C.decodeBytes(C.unhexBytes("'
    + protocol.encode(REPLY).hex() + '")); return "KR-REPLY " .. tostring(v ~= nil and v.text == '
    + lua_literal(ACCENTED) + ') .. " " .. C.hex(v and v.text or "")',
    # Old Latin-1 state (U+00E9 written as the byte e9 before E00-T08): same checksum, decoded as U+00E9.
    'eval:local C = require("RadioSurvivor/RS_Codec"); local b = C.unhexBytes("74313a73343a6e616d6573343a636166e9"); '
    'local v = C.decodeBytes(b); return "KR-LEGACY " .. C.checksumBytes(b) .. " " .. tostring(v ~= nil and v.name == '
    + lua_literal('café') + ')',
    # LK02-T02 : identité des PNJ (logique pure) dans la VM réelle : identifiants, classement, registre relu en RSV2.
    'eval:local I = LivingKnox.Identity; local C = require("RadioSurvivor/RS_Codec"); local r = I.newRegistry(); '
    'local a = I.create(r, {}, 10, 20, 0); local b = I.create(r, { female = true, outfit = "Generic02" }, 1.5, 2, 0); '
    'I.markEmbodied(a, I.nextGeneration(a)); I.markEmbodied(a, I.nextGeneration(a)); '
    'local md = {}; I.writeTag(md, a.id, 2); local id, gen = I.readTag(md); '
    'local back = I.validate(C.decodeBytes(C.encodeBytes(r))); '
    'local _, why, kind = I.validate({ schema = 3, nextId = 1, npcs = {} }); '
    'return "KR-IDENTITY " .. a.id .. " " .. b.id .. " " .. tostring(I.idNumber("lk-12")) .. " " .. id .. "#" .. gen '
    '.. " " .. I.classify(r, a.id, 2) .. " " .. I.classify(r, a.id, 1) .. " " .. I.classify(r, a.id, 3) .. " " '
    '.. I.classify(r, "lk-9", 1) .. " " .. I.classify(r, b.id, 1) .. " " .. tostring(back ~= nil and back.nextId == 3 '
    'and back.npcs["lk-2"].want.x == 1.5) .. " " .. kind',
    # LK02-T03 : tirage d'apparence (Park-Miller, modulo Kahlua), identifiant de tenue sans opérateurs binaires,
    # migration d'un registre schéma 1.
    'eval:local A = LivingKnox.Appearance; local I = LivingKnox.Identity; local out = {} '
    'for _, seed in ipairs({ 1, 2, 3, 77, 999999999 }) do local p = A.normalize({}, seed); '
    'out[#out + 1] = p.look .. "#" .. p.variant end '
    'out[#out + 1] = A.normalize({ female = true }, 7).look; '
    'out[#out + 1] = string.format("%.0f", A.outfitIdWithVariant(-2147483648 + 12 * 65536 + 500, 3)); '
    'out[#out + 1] = string.format("%.0f", A.outfitIdWithVariant(11 * 65536 + 32768 + 7, 9)); '
    'local r = { schema = 1, nextId = 3, npcs = { ["lk-2"] = { id = "lk-2", generation = 0, state = "virtual", '
    'profile = { female = true, outfit = "Generic04", preset = "clean" }, want = { x = 0, y = 0, z = 0 } } } }; '
    'local from = I.upgrade(r); local ok = I.validate(r); '
    'out[#out + 1] = tostring(from) .. ":" .. tostring(ok ~= nil) .. ":" .. r.npcs["lk-2"].profile.look .. ":" '
    '.. r.npcs["lk-2"].profile.outfit; '
    'return "KR-APPEARANCE " .. table.concat(out, " ")',
    # LK02-T12 : vêtements concrets dans le registre (champ facultatif npc.clothes) : contrôle, aller-retour RSV2 d'un
    # décalage de teinte flottant (float32 vu en double), refus d'une entrée fausse par Identity.validate.
    'eval:local A = LivingKnox.Appearance; local I = LivingKnox.Identity; local C = require("RadioSurvivor/RS_Codec"); '
    'local r = I.newRegistry(); local npc = I.create(r, { look = "womanTanBob" }, 1, 2, 0); '
    'npc.clothes = { { type = "Base.Tshirt_DefaultTEXTURE_TINT", item = "Tshirt_DefaultTEXTURE_TINT", '
    'tint = { r = 31, g = 166, b = 127 }, hue = -0.3799999952316284, base = 0, choice = 2, decal = "TShirtDecal" }, '
    '{ type = "Base.Shoes_Black" } }; '
    'local back = I.validate(C.decodeBytes(C.encodeBytes(r))); local c = back and back.npcs["lk-1"].clothes; '
    'local ok1 = A.validClothes(c); local _, why = A.validClothes({ { type = "Base.X", hue = 1.5 } }); '
    'npc.clothes[2].tint = { r = 1, g = 2 }; local _, why2 = I.validate(r); '
    'return "KR-CLOTHES " .. tostring(ok1) .. " " .. tostring(c and c[1].hue == -0.3799999952316284) .. " " '
    '.. tostring(c and #c) .. " " .. A.clothesKey(c) .. " " .. tostring(why) .. " / " .. tostring(why2)',
    # LK08-T02 : types de groupes dans la VM réelle : trois types livrés enregistrés, type supplémentaire ajouté par
    # une simple définition, refus (motifs %l / %a, liste, arme vanilla non admise), doublon refusé.
    'eval:local T = LivingKnox.GroupTypes; local ids = table.concat(T.ids(), ","); local n0 = #T.refused(); '
    'local d = { format = 1, id = "nomads", nameKey = "IGUI_X", size = { min = 3, max = 5 }, hostility = 30, '
    'home = "forest", morale = 55, needs = { food = 1, medical = 2, ammo = 3 }, roles = { scout = { weight = 2, '
    'behaviours = { "scout", "forage" } } }, profiles = { { id = "walker", role = "scout", weight = 5, '
    'female = true, looks = { "womanTanBob" }, weapons = { "Base.Machete", "Mod_X.Spear" }, '
    'traits = { { id = "keenHearing", chance = 40 } } } } }; local ok = T.register(d); '
    'local _, w1 = T.register({ format = 1, id = "Bad-Id" }); d.id = "other"; d.profiles[1].weapons = '
    '{ "Base.Spoon" }; local _, w2 = T.register(d); d.id = "nomads"; d.profiles[1].weapons = nil; '
    'local _, w3 = T.register(d); local g = T.get("raiders"); '
    'return "KR-GROUPTYPES " .. ids .. " " .. n0 .. " " .. tostring(ok) .. " " .. table.concat(T.ids(), ",") '
    '.. " " .. g.roles.breaker.behaviours[1] .. " " .. g.size.max .. " / " .. w1 .. " / " .. w2 .. " / " .. w3 '
    '.. " / " .. #T.refused()',
    # LK08-T01 : registre des groupes dans la VM réelle (API sur un registre en mémoire, écriture de fichier
    # neutralisée : getFileWriter n'existe pas hors du jeu) : succession, bornes, journal, aller-retour RSV2 validé,
    # groupe invalide écarté, schéma futur refusé.
    'eval:local G = LivingKnox.Groups; local C = require("RadioSurvivor/RS_Codec"); '
    'G.state.data, G.state.blocked = G.newRegistry(), false; G.save = function() return true end; '
    'local g = G.create({ type = "settlers", name = "Mill", home = { x = 10600, y = 9400, z = -1 }, day = 2 }); '
    'local m1 = G.addMember(g.id, { role = "worker", npc = "lk-3" }); local m2 = G.addMember(g.id, { role = "fighter" }); '
    'local m3 = G.addMember(g.id, { role = "fighter" }); G.setLeader(g.id, m1, 2); G.markDead(g.id, m1, 3); '
    'local s = G.succeed(g.id, 3); local food = G.setNeed(g.id, "food", 141.2); local mor = G.addMorale(g.id, -7.4); '
    'G.addLog(g.id, "raid", string.rep("z", 250), 4); '
    'local back, dropped = G.validate(C.decodeBytes(C.encodeBytes(G.state.data))); local bg = back.groups[g.id]; '
    'local bad = C.decodeBytes(C.encodeBytes(G.state.data)); bad.groups[g.id].leader = m1; '
    'local _, d2 = G.validate(bad); local _, why, kind = G.validate({ schema = 2, nextId = 1, groups = {} }); '
    'return "KR-GROUPS " .. g.id .. " " .. s .. " " .. tostring(food) .. " " .. tostring(mor) .. " " '
    '.. tostring(#dropped) .. " " .. bg.home.z .. " " .. #bg.log .. " " .. #bg.log[#bg.log].text .. " " '
    '.. bg.members[m1].npc .. " " .. tostring(bg.members[m1].alive) .. " " .. tostring(G.today()) .. " " '
    '.. d2[1].why .. " / " .. kind .. " " .. tostring(m3)',
    # LK09-T01 : simulation hors écran dans la VM réelle : 24 pas d'une heure = un rattrapage de 24 h (mêmes octets),
    # valeurs identiques à celles de lupa (tirages Park-Miller, arrondi aléatoire, blessures, succession) ;
    # LK09-T02 : une expédition partie et revenue pendant les 24 h (dernier nombre : entrées « return »).
    'eval:local G = LivingKnox.Groups; local S = LivingKnox.Simulation; local C = require("RadioSurvivor/RS_Codec"); '
    'LivingKnox.Config.SIMULATION.SEED = 4242; G.state.data, G.state.blocked = G.newRegistry(), false; '
    'G.save = function() return true end; local g = G.create({ type = "settlers", name = "Mill", day = 1 }); '
    'for _ = 1, 5 do G.addMember(g.id, { role = "worker" }) end; G.setLeader(g.id, "m-2", 1); local d = G.state.data; '
    'd.groups[g.id].members["m-2"].wound = 97; d.groups[g.id].members["m-3"].wound = 30; d.groups[g.id].needs.medical = 0; '
    'd.simHour = 10; local a, b = G.copy(d), G.copy(d); '
    'for h = 11, 34 do S.advance(a, h) end; S.advance(b, 34); local ga = a.groups[g.id]; local rnd = S.stream(7, 1, 1); '
    'local s = 0; for _ = 1, 1000 do s = s + S.amount(0.5, rnd) end; '
    'local rets = 0; for _, e in ipairs(ga.log) do if e.kind == "return" then rets = rets + 1 end end; '
    'return "KR-SIM " .. tostring(C.hexBytes(C.encodeBytes(a)) == C.hexBytes(C.encodeBytes(b))) .. " " .. a.simHour '
    '.. " " .. ga.needs.food .. " " .. ga.needs.medical .. " " .. ga.needs.ammo .. " " .. ga.morale .. " " .. ga.rest '
    '.. " " .. tostring(ga.leader) .. " " .. tostring(ga.members["m-2"].alive) .. " " .. tostring(ga.members["m-3"].wound) '
    '.. " " .. s .. " " .. rets',
    # LK09-T05 : événements de groupe (combat compris) dans la VM réelle : 240 pas d'une heure = rattrapages de 72 h
    # (mêmes octets), nombre d'événements et valeurs identiques à lupa (tests/test_lk_simulation.py, CrossVmTests).
    'eval:local G = LivingKnox.Groups; local S = LivingKnox.Simulation; local C = require("RadioSurvivor/RS_Codec"); '
    'local E = LivingKnox.Config.SIMULATION.EVENTS; LivingKnox.Config.SIMULATION.SEED = 777; E.MAX_DAILY = 1; '
    'E.CLASH.CHANCE = 0.8; G.state.data, G.state.blocked = G.newRegistry(), false; G.save = function() return true end; '
    'local a = G.create({ type = "settlers", name = "Mill", day = 1, home = { x = 1000, y = 1000, z = 0 } }); '
    'local b = G.create({ type = "raiders", name = "Crows", day = 1, home = { x = 1500, y = 1000, z = 0 } }); '
    'for _ = 1, 6 do G.addMember(a.id, { role = "worker" }) end; for _ = 1, 5 do G.addMember(b.id, { role = "fighter" }) end; '
    'G.setLeader(a.id, "m-1", 1); G.setLeader(b.id, "m-1", 1); local d = G.state.data; d.groups[a.id].morale = 20; '
    'd.groups[b.id].morale = 20; d.simHour = 0; local x, y = G.copy(d), G.copy(d); local n = 0; local ap = G.appendLog; '
    'local kinds = { departure = true, recruit = true, conflict = true, illness = true, clash = true }; '
    'G.appendLog = function(g, k, t, dd) if kinds[k] then n = n + 1 end ap(g, k, t, dd) end; '
    'for h = 1, 240 do S.advance(x, h, {}) end; G.appendLog = ap; for h = 72, 240, 72 do S.advance(y, h, {}) end; '
    'S.advance(y, 240, {}); local ga, gb = x.groups[a.id], x.groups[b.id]; '
    'return "KR-EVT " .. tostring(C.hexBytes(C.encodeBytes(x)) == C.hexBytes(C.encodeBytes(y))) .. " " .. n .. " " '
    '.. ga.morale .. " " .. gb.morale .. " " .. ga.needs.food .. " " .. gb.needs.ammo .. " " .. ga.nextMember .. " " '
    '.. gb.nextMember .. " " .. tostring(ga.leader) .. " " .. tostring(gb.leader)',
    # LK12-T01 : API en lecture dans la VM reelle : vue publique (foyer en maille, aucun journal), copies, PNJ a
    # portee d'apres la derniere position vue (aucun corps lie), projection publique d'un groupe brut.
    'eval:local G, A, I, S = LivingKnox.Groups, LivingKnox.API, LivingKnox.Identity, LivingKnox.Store; '
    'G.state.data, G.state.blocked = G.newRegistry(), false; G.save = function() return true end; '
    'S.state.data, S.state.blocked = I.newRegistry(), false; '
    'local g = G.create({ type = "settlers", name = "Mill", home = { x = 10637, y = 9412, z = 0 }, day = 2 }); '
    'local m1 = G.addMember(g.id, { role = "worker", npc = "lk-1" }); G.setLeader(g.id, m1, 2); '
    'G.addLog(g.id, "note", "private", 3); local n = I.create(S.state.data, { female = true }, 1, 1, 0); '
    'I.markEmbodied(n, 1); n.last = { x = 103, y = 104, z = 1 }; local v = A.getGroup(g.id); v.name = "x"; '
    'local l = A.listGroups(); local near = A.npcsNear(100, 100, 0, 999); local p = A.publicGroup(G.state.data.groups[g.id]); '
    'return "KR-API " .. A.version() .. " " .. #l .. " " .. l[1].name .. " " .. l[1].area.x .. "," .. l[1].area.y '
    '.. " " .. tostring(l[1].log) .. " " .. tostring(l[1].home) .. " " .. l[1].leader.npc .. " " .. l[1].alive '
    '.. " " .. #near .. " " .. near[1].id .. " " .. near[1].group .. " " .. near[1].distance .. " " .. near[1].floor '
    '.. " " .. tostring(near[1].inWorld) .. " " .. p.area.x .. " " .. tostring(p.home) .. " " .. p.members[1].role',
    # LK11-T03 : attitudes dans la VM reelle (ecriture neutralisee) : deux joueurs distincts, tendance, declin borne,
    # plafond apres un meurtre, aller-retour RSV2 valide ; memes valeurs que sous lupa (tests/test_lk_hostility.py).
    'eval:local G, H = LivingKnox.Groups, LivingKnox.Hostility; local C = require("RadioSurvivor/RS_Codec"); '
    'G.state.data, G.state.blocked = G.newRegistry(), false; G.save = function() return true end; '
    'H.state.data, H.state.blocked = H.newRegistry(), false; H.save = function() return true end; '
    'local g = G.create({ type = "settlers", name = "Mill", day = 1 }).id; local o = { witnessed = true, day = 1 }; '
    'for _, f in ipairs({ "shot", "theft", "hit" }) do H.record(g, "p-1", f, o) end; '
    'H.record(g, "p-2", "gift", o); local b = H.record(g, "p-2", "heal", o); local a = H.get(g, "p-1"); '
    'H.record(g, "p-3", "kill", o); local n = H.decay(200); '
    'local back, dropped = H.validate(C.decodeBytes(C.encodeBytes(H.state.data))); '
    'return "KR-ATT " .. a.level .. " " .. a.trend .. " " .. b.level .. " " .. b.trend .. " " .. tostring(a.value) '
    '.. " " .. n .. " " .. back.groups[g]["p-3"].value .. " " .. back.groups[g]["p-1"].value .. " " .. #dropped '
    '.. " " .. #H.forGroup(g)',
    # LK12-T03 : offres et livraison idempotente dans la VM reelle (ecriture et horloge neutralisees) ; memes valeurs
    # que sous lupa (tests/test_lk_api.py, SupplyTests) : food 20 -> +5 -> rejeu sans effet -> +10, recompense.
    'eval:local G, A = LivingKnox.Groups, LivingKnox.API; local C = require("RadioSurvivor/RS_Codec"); '
    'G.state.data, G.state.blocked = G.newRegistry(), false; G.save = function() return true end; '
    'A.currentHour = function() return 10 end; '
    'local g = G.create({ type = "settlers", name = "Mill", day = 1, needs = { food = 20, medical = 35, ammo = 60 } }).id; '
    'G.addMember(g, { role = "worker", day = 1 }); local o = A.missionOffers(g); '
    'local r1 = A.deliver(g, o[1].id, { ["Base.TinnedBeans"] = 6, ["Base.Rice"] = 4 }, "k1"); '
    'local r2 = A.deliver(g, o[1].id, { ["Base.TinnedBeans"] = 20 }, "k1"); '
    'local r3 = A.deliver(g, o[1].id, { ["Base.CannedChili"] = 20 }, "k2"); '
    'local _, why = A.deliver(g, o[1].id, { ["Base.TinnedBeans"] = 1 }, "k3"); local d = G.state.data.groups[g]; '
    'local back = G.validate(C.decodeBytes(C.encodeBytes(G.state.data))); '
    'return "KR-SUPPLY " .. #o .. " " .. o[1].id .. " " .. o[1].value .. " " .. o[2].value .. " " .. r1.points '
    '.. " " .. tostring(r2.duplicate) .. " " .. r2.points .. " " .. r3.points .. " " .. tostring(r3.completed) '
    '.. " " .. r3.reward.item.type .. " " .. why .. " " .. d.needs.food .. " " .. d.needs.ammo .. " " '
    '.. #back.groups[g].supply.receipts',
    # LK12-T02 : evenements publics dans la VM reelle (ecriture et jour neutralises, triggerEvent remplace) : besoin
    # critique une fois (hysteresis), file videe au pas, groupe disparu apres le dernier fait ; memes regles que lupa.
    'eval:local G, A = LivingKnox.Groups, LivingKnox.API; local got = {}; local te, td = triggerEvent, G.today; '
    'G.state.data, G.state.blocked = G.newRegistry(), false; G.save = function() return true end; '
    'G.today = function() return 3 end; triggerEvent = function(n, e) got[#got + 1] = n .. "=" .. tostring(e.reason '
    'or e.need or e.member or e.name) end; A.events = { queue = {}, fired = {}, critical = {}, seeded = false, '
    'stats = {} }; A.checkNeeds(); '
    'local g = G.create({ type = "settlers", name = "Mill", day = 1, needs = { food = 50, medical = 50, ammo = 50 } }).id; '
    'G.addMember(g, { role = "worker", day = 1 }); G.addMember(g, { role = "medic", day = 1 }); '
    'G.setNeed(g, "food", 10); local c1 = A.checkNeeds(); local c2 = A.checkNeeds(); '
    'G.removeMember(g, "m-1", 1, "leave_group"); G.markDead(g, "m-2", 2); local n = A.flushEvents(); '
    'local n2 = A.flushEvents(); triggerEvent, G.today = te, td; '
    'return "KR-EVENTS " .. c1 .. " " .. c2 .. " " .. n .. " " .. n2 .. " " .. table.concat(got, ",")',
    # LK05-T01 : modele de perception dans la VM reelle ; memes valeurs que sous lupa (tests/test_lk_senses.py).
    'eval:local S = LivingKnox.Senses; local n = { vigil = "rest", pose = "stand" }; local function o(t) '
    'local b = { kind = "player", d = 6, dz = 0, cos = 1, light = 1, motion = "walk", room = "same", los = "Clear" } '
    'for k, v in pairs(t) do b[k] = v end return b end; local a = S.evaluate(n, o({})); '
    'local b = S.evaluate(n, o({ light = 0, sneak = true })); '
    'local c = S.evaluate(n, o({ los = "Blocked", motion = "run", room = "outside", d = 4 })); local tr = {}; '
    'for i = 1, 3 do S.step(tr, a, o({}), 0.2, i * 200) end; return "KR-SENSES " .. string.format('
    '"%.3f %.3f %s %.3f %s %s %.4f %s", a.r, b.r, tostring(c.sight), c.hr, tostring(c.heard), tostring(tr.s), tr.a, '
    'S.motionOfSpeed(4.0))',
    # LK05-T02 : decisions dans la VM reelle (atan2, modulo, tirages) ; memes valeurs que sous lupa
    # (tests/test_lk_decisions.py, KahluaParityTests).
    'eval:local D = LivingKnox.Decisions; local function c(t) local b = { id = "lk-7", allowed = { chores = '
    'true }, combatant = false, x = 100.5, y = 100.5, z = 0, home = { x = 100, y = 100, z = 0 }, atHome = '
    'true, needs = { hunger = 0, thirst = 0, fatigue = 0, fear = 0 }, health = 1, duty = "keeper", '
    'objective = "settle", night = false, minute = 600 } for k, v in pairs(t) do b[k] = v end return b '
    'end; local zt = { kind = "zombie", key = "z42", label = "42", x = 103, y = 98, z = 0, d = 3.2, seen '
    '= true, flee = true }; local a = D.decide(c({ threat = zt, health = 0.4, atHome = false })); '
    'local b = D.decide(c({ duty = '
    '"sentry", allowed = { guard = true }, home = { x = 95, y = 97, z = 0 } })); local e = D.decide(c({ '
    'health = 0.3, minute = 12345 })); local s = D.scoreObjectives({ gidNumber = 3, day = 4, night = '
    'false, needs = { food = 20, medical = 50, ammo = 50 }, rest = 40, worstWound = 10, threats = 1, '
    'hostility = 90, traits = { nervous = true } }); local r = D.stream("lk-7", 600, 3); return '
    '"KR-DECIDE " .. a.b .. " " .. a.away .. " " .. a.side .. " " .. a.untilMin .. " " .. b.b .. " " .. '
    'b.angle .. " " .. b.untilMin .. " " .. e.b .. " " .. e.untilMin .. " " .. s.objective .. " " .. '
    's.scores.guard .. " " .. s.scores.supply .. " " .. string.format("%.6f", r())',
    # LK05-T08 : alerte de groupe dans la VM reelle (cles, une fois par menace, niveau, distance) ; memes valeurs que
    # sous lupa (tests/test_lk_alert.py, KahluaParityTests).
    'eval:local A = LivingKnox.Alert; A.reset(); local h = { x = 100, y = 100, z = 0 }; local sp = { npc = "lk-1", '
    'mid = "m-1", x = 100.5, y = 100.5, z = 0 }; local per = { stale = false, p = {}, z = { { o = 5, x = 106, '
    'y = 100, z = 0, s = true, h = false, d = 6 }, { o = -1, x = 104, y = 101, z = 0, s = false, h = true, d = 3.6 '
    '} } }; local t = A.threatsOf(per, {}, h); local e1 = A.note("grp-1", t[1], sp, 600, h); local e2 = '
    'A.note("grp-1", t[1], sp, 601, h); local e3 = A.note("grp-1", t[2], sp, 601, h); local v = '
    'A.forMember("grp-1", 100.5, 100.5, 0, false, 603); return "KR-ALERT " .. #t .. " " .. t[1].key .. " " .. '
    't[2].key .. " " .. e1 .. " " .. e2 .. " " .. e3 .. " " .. v.level .. " " .. v.d .. " " .. v.key .. " " .. '
    'tostring(A.isActive("grp-1", 620))',
]


# E05-T01 : fiches de voix lues par RS_Persona dans la VM réelle. Les lignes sont celles que rend getFileReader
# (UTF-8 décodé par InputStreamReader : U+FFFD pour un octet invalide, BOM conservé), passées en littéraux ASCII.
PERSONA_CASES = [
    ('walt', test_personas.WALT.read_bytes(), 'walt'),
    ('full', test_personas.FULL.encode('utf-8'), 'case'),
    ('bom', ('\ufeff' + test_personas.HEAD + test_personas.PROMPT).encode('utf-8'), 'case'),
    ('invalid', test_personas.HEAD.encode() + b'knows=caf\xe9\n' + test_personas.PROMPT.encode(), 'case'),
    ('accented-id', (test_personas.HEAD.replace('id=case', 'id=cas\u00e9') + test_personas.PROMPT).encode(), 'case'),
    ('frequency', (test_personas.HEAD.replace('145.0', '145.1') + test_personas.PROMPT).encode(), 'case'),
    ('budget', (test_personas.HEAD + 'actions=say\nbudget.signal=1\n' + test_personas.PROMPT).encode(), 'case'),
    # E07-T04 : libellé de lieu borné en octets UTF-8, comptés depuis les unités UTF-16 de Kahlua.
    ('place-48', (test_personas.HEAD + 'place=a 1,2,0 ' + 'é' * 24 + '\n' + test_personas.PROMPT).encode(),
     'case'),
    ('place-49', (test_personas.HEAD + 'place=a 1,2,0 ' + 'é' * 24 + 'x\n' + test_personas.PROMPT).encode(),
     'case'),
    ('place-cjk', (test_personas.HEAD + 'place=a 1,2,0 ' + '港' * 16 + '\n' + test_personas.PROMPT).encode(),
     'case'),
    ('place-cjk-long', (test_personas.HEAD + 'place=a 1,2,0 ' + '港' * 16 + 'x\n'
                        + test_personas.PROMPT).encode(), 'case'),
    ('place-emoji', (test_personas.HEAD + 'place=a 1,2,0 ' + '\U0001F4FB' * 12 + '\n'
                     + test_personas.PROMPT).encode(), 'case'),
    ('place-emoji-long', (test_personas.HEAD + 'place=a 1,2,0 ' + '\U0001F4FB' * 12 + 'x\n'
                          + test_personas.PROMPT).encode(), 'case'),
]


def persona_lines(raw: bytes) -> list[str]:
    return persona_store.split_lines(raw.decode('utf-8', errors='replace'))


def persona_expected(raw: bytes, expected_id: str) -> str:
    try:
        return 'OK ' + test_personas.canonical(persona_store.parse_lines(persona_lines(raw), expected_id)).encode(
            'utf-8').hex()
    except persona_store.PersonaError as exc:
        return 'ERR ' + str(exc).encode('utf-8').hex()


def persona_eval(name: str, raw: bytes, expected_id: str) -> str:
    lines = ', '.join(lua_literal(line) for line in persona_lines(raw))
    canon = ' '.join(test_personas.LUA_CANONICAL.split())
    return ('eval:local P = require("RadioSurvivor/RS_Persona"); local C = require("RadioSurvivor/RS_Codec"); '
            f'local canon = (function() {canon} end)(); local p, why = P.parseLines({{ {lines} }}, "{expected_id}"); '
            f'return "KR-PERSONA-{name} " .. (p and ("OK " .. C.hex(canon(p))) or ("ERR " .. C.hex(why)))')


EXCHANGE_EVALS += [persona_eval(name, raw, expected_id) for name, raw, expected_id in PERSONA_CASES]

# E05-T02 : RS_Personas dans la VM réelle (doublures Lua des fichiers, du dossier du mod et du gestionnaire de
# chaînes) : migration d'une valeur sandbox arrondie au pas, identifiants de chaîne (tostring d'un nombre Kahlua),
# changement de fréquence et d'état, conflit, fiche invalide gardant l'ancienne version.
PERSONAS_EVAL = (
    'eval:local P = require("RadioSurvivor/RS_Personas"); local K = require("RadioSurvivor/RadioSurvivor_Const"); '
    'local FILES = {}; local function rd(l) local i = 0; return { readLine = function() i = i + 1; return l[i] end, '
    'close = function() end } end; '
    'local function jl(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end; '
    'getFileReader = function(p) return FILES[p] and rd(FILES[p]) end; '
    'getFileWriter = function(p) local o = {}; return { write = function(_, x) o[#o + 1] = x end, close = function() '
    'local l = {}; for x in string.gmatch(table.concat(o), "([^\\n]*)\\n") do l[#l + 1] = x end; '
    'FILES[p] = l end } end; '
    'listFilesInZomboidLuaDirectory = function(d) local n = {}; for k in pairs(FILES) do '
    'if string.sub(k, 1, string.len(d) + 1) == d .. "/" then n[#n + 1] = string.sub(k, string.len(d) + 2) end end; '
    'return jl(n) end; '
    'listFilesInModDirectory = function() return jl({ "walt.txt" }) end; '
    'getModFileReader = function() return rd({ "format=1", "id=walt", "name=Walt", "frequencies=145.0", '
    '"call_one_in=3", "call_text=IGUI_X", "[prompt]", "Hi." }) end; '
    'getSandboxOptions = function() return { getOptionByName = function(_, n) '
    'if n == "RadioSurvivor.Frequency" then return { getValue = function() return 150.1 end } end; '
    'if n == "RadioSurvivor.Enabled" then return { getValue = function() return true end } end end } end; '
    'local M = { by = {} }; function M:AddChannel(c) if not self.by[c.f] then self.by[c.f] = c end end; '
    'function M:RemoveChannel(f) self.by[f] = nil end; '
    'function M:getRadioChannel(u) for _, c in pairs(self.by) do if c.u == u then return c end end end; '
    'DynamicRadioChannel = { new = function(n, f, c, u) return { f = f, u = u } end }; ChannelCategory = {}; '
    'getZomboidRadio = function() return { getScriptManager = function() return M end, '
    'removeChannelName = function() end } end; '
    'local out = {}; local function chans() local l = {}; for _, c in pairs(M.by) do l[#l + 1] = c.u end; '
    'table.sort(l); return table.concat(l, ",") end; '
    'P.onLoadRadioScripts(M); local d = "batman_RadioSurvivor/personas/"; '
    'out[#out + 1] = FILES[d .. "walt.txt"][4]; out[#out + 1] = chans(); '
    'out[#out + 1] = K.frequencyLabel(P.heldFrequencies()[1]); '
    'FILES[d .. "walt.txt"][4] = "frequencies=145.0, 146.0"; FILES[d .. "abe.txt"] = { "format=1", "id=abe", '
    '"name=Abe", "frequencies=146.0, 147.0", "state=silent", "[prompt]", "Hi." }; P.reload(); '
    'out[#out + 1] = chans(); out[#out + 1] = tostring(P.voiceAt(146000)); '
    'FILES[d .. "walt.txt"][4] = "frequencies=145.1"; P.reload(); '
    'out[#out + 1] = chans() .. "|" .. P.get("walt").frequencies[2]; '
    'FILES[d .. "abe.txt"][5] = "state=gone"; P.reload(); out[#out + 1] = chans(); '
    'out[#out + 1] = tostring(P.isListening({ listen = { { from = 1320, to = 360 } } }, 0)); '
    'return "KR-PERSONAS " .. table.concat(out, " ")'
)
EXCHANGE_EVALS.append(PERSONAS_EVAL)

# E05-T07 : tirage dans une plage dans la VM réelle. Plage 100.0-101.0 ; 100.0 tenue par une autre chaîne, 100.4 par
# l'AEBS de la ModData de GameTime ; ZombRand rend 1 : deuxième fréquence libre (100.6). Fichier de la partie
# (nom en hex de « mode/nom »), puis rechargement du même monde (non neuf) : même fréquence, aucun tirage.
DRAW_EVAL = (
    'eval:local P = require("RadioSurvivor/RS_Personas"); '
    'local FILES = {}; local function rd(l) local i = 0; return { readLine = function() i = i + 1; return l[i] end, '
    'close = function() end } end; '
    'local function jl(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end; '
    'getFileReader = function(p) return FILES[p] and rd(FILES[p]) end; '
    'getFileWriter = function(p) local o = {}; return { write = function(_, x) o[#o + 1] = x end, close = function() '
    'local l = {}; for x in string.gmatch(table.concat(o), "([^\\n]*)\\n") do l[#l + 1] = x end; '
    'FILES[p] = l end } end; '
    'listFilesInZomboidLuaDirectory = function(d) local n = {}; for k in pairs(FILES) do '
    'if string.sub(k, 1, string.len(d) + 1) == d .. "/" then n[#n + 1] = string.sub(k, string.len(d) + 2) end end; '
    'return jl(n) end; '
    'listFilesInModDirectory = function() return jl({ "abe.txt" }) end; '
    'getModFileReader = function() return rd({ "format=1", "id=abe", "name=Abe", "frequency_range=100.0-101.0", '
    '"[prompt]", "Hi." }) end; '
    'getSandboxOptions = function() return { getOptionByName = function(_, n) '
    'if n == "RadioSurvivor.Enabled" then return { getValue = function() return true end } end end } end; '
    'getWorld = function() return { getWorld = function() return "kr" end, '
    'getGameMode = function() return "Multiplayer" end } end; '
    'getGameTime = function() return { getModData = function() return { dynamicRadio = { { name = "AEBS", '
    'freq = 100400 } } } end } end; '
    'local draws = 0; ZombRand = function(n) draws = draws + 1; return 1 end; '
    'local function mgr() local M = { by = {} }; '
    'function M:AddChannel(c) if not self.by[c.f] then self.by[c.f] = c end end; '
    'function M:RemoveChannel(f) self.by[f] = nil end; '
    'function M:getRadioChannel(u) for _, c in pairs(self.by) do if c.u == u then return c end end end; '
    'function M:getChannelsList() local l = {}; for _, c in pairs(self.by) do l[#l + 1] = c end; return jl(l) end; '
    'M.by[100000] = { f = 100000, u = "other", n = "Other" }; return M end; '
    'DynamicRadioChannel = { new = function(n, f, c, u) return { f = f, u = u, n = n } end }; ChannelCategory = {}; '
    'local chanMethods = function(c) c.getGUID = function(self) return self.u end; '
    'c.GetFrequency = function(self) return self.f end; c.GetName = function(self) return self.n end; return c end; '
    'local new = DynamicRadioChannel.new; DynamicRadioChannel.new = function(...) return chanMethods(new(...)) end; '
    'local M = mgr(); chanMethods(M.by[100000]); '
    'getZomboidRadio = function() return { getScriptManager = function() return M end, '
    'removeChannelName = function() end } end; '
    'local out = {}; P.onLoadRadioScripts(M, true); out[#out + 1] = tostring(P.served("abe")[1]); '
    'local path = "batman_RadioSurvivor/frequencies-4d756c7469706c617965722f6b72.txt"; '
    'out[#out + 1] = table.concat(FILES[path] or { "none" }, "/"); out[#out + 1] = tostring(draws); '
    'M = mgr(); chanMethods(M.by[100000]); P.onLoadRadioScripts(M, false); '
    'out[#out + 1] = tostring(P.served("abe")[1]) .. "/" .. tostring(draws); '
    'return "KR-DRAW " .. table.concat(out, " ")'
)
EXCHANGE_EVALS.append(DRAW_EVAL)

# E07-T04 : RS_MapActions.mark dans la VM réelle (doublures Lua des symboles de la carte) : centre de la case,
# libellé nettoyé (un « é » = une unité), pas de doublon au second repère du même point, une seule UIWorldMap.
MAP_EVAL = (
    'eval:local A = require("RadioSurvivor/RS_MapActions"); A.resetForTests(); local syms = {}; '
    'local function sym(kind, id, text, x, y) local s = { k = kind, i = id, t = text, x = x, y = y }; '
    's.getWorldX = function() return s.x end; s.getWorldY = function() return s.y end; '
    's.isTexture = function() return s.k == "tex" end; s.isText = function() return s.k == "text" end; '
    's.getSymbolID = function() return s.i end; s.setRGBA = function() end; '
    's.setAnchor = function(_, ax, ay) s.ay = ay end; s.setScale = function() end; syms[#syms + 1] = s; return s end; '
    'local api = { addTexture = function(_, id, x, y) return sym("tex", id, nil, x, y) end, '
    'addTranslatedText = function(_, t, l, x, y) return sym("text", nil, t, x, y) end, '
    'getSymbolCount = function() return #syms end, getSymbolByIndex = function(_, i) return syms[i + 1] end, '
    'getDefaultTextLayerID = function() return "note" end }; '
    'local item = {}; MapItem = { getSingleton = function() return item end }; local made = 0; '
    'UIWorldMap = { new = function() made = made + 1; local v3 = { setMapItem = function() end, '
    'getSymbolsAPIv2 = function() return api end }; return { getAPIv3 = function() return v3 end } end }; '
    'local r1 = A.mark(10600, 9300.7, "Caf\\195\\169 <b>x</b>"); local r2 = A.mark(10600, 9300, "other"); '
    'return "KR-MAP " .. r1 .. " " .. r2 .. " " .. #syms .. " " .. made .. " " .. string.len(syms[2].t) .. " " '
    '.. tostring(syms[1].x) .. "," .. tostring(syms[1].y) .. " " .. tostring(syms[1].ay) .. "/" .. tostring(syms[2].ay)'
)
EXCHANGE_EVALS.append(MAP_EVAL)

# E07-T05 : RS_MapActions.reveal dans la VM réelle (doublure de WorldMapVisited qui garde ses appels) : rectangle
# aligné passé avec le bord haut inclus, valeurs reçues en flottants (copie réseau) acceptées, rectangle non aligné ou
# trop grand refusé sans appel, WorldMapVisited absent.
REVEAL_EVAL = (
    'eval:local A = require("RadioSurvivor/RS_MapActions"); local calls = {}; '
    'WorldMapVisited = { getInstance = function() return { setKnownInSquares = function(_, a, b, c, d) '
    'calls[#calls + 1] = a .. "," .. b .. "," .. c .. "," .. d end } end }; '
    'local r1 = A.reveal(10528, 9216, 10688, 9376); local r2 = A.reveal(10528.0, 9216.0, 10688.0, 9376.0); '
    'local r3, w3 = A.reveal(10529, 9216, 10688, 9376); local r4, w4 = A.reveal(0, 0, 192, 96); '
    'WorldMapVisited = nil; local r5, w5 = A.reveal(0, 0, 64, 64); '
    'return "KR-REVEAL " .. r1 .. " " .. r2 .. " " .. tostring(r3) .. "/" .. w3 .. " " .. tostring(r4) .. "/" .. w4 '
    '.. " " .. tostring(r5) .. "/" .. w5 .. " " .. table.concat(calls, ";")'
)
EXCHANGE_EVALS.append(REVEAL_EVAL)

# LK13-T02 : LK_Load dans la VM reelle (Events, isServer et sendServerCommand de test, remis ensuite) : valeurs rendues
# par l'enveloppe d'un abonne (nil au milieu, quatre valeurs), cout mesure sur l'horloge du banc, reseau compte par
# commande (a tous / a un joueur, autre module ignore), arguments transmis tels quels (3, 4, 3), enveloppe retiree.
LOAD_EVAL = (
    'eval:local L = LivingKnox.Load; local function ev() local e = { list = {} }; e.Add = function(f) '
    'e.list[#e.list + 1] = f end; e.Remove = function(f) for i, g in ipairs(e.list) do if g == f then '
    'table.remove(e.list, i) return end end end; return e end; local oldE, oldS, oldSend = Events, isServer, '
    'sendServerCommand; Events = { OnTick = ev(), OnTickEvenPaused = ev(), EveryOneMinute = ev() }; '
    'isServer = function() return true end; local sent = {}; local dbl = function(...) sent[#sent + 1] = '
    'select("#", ...) end; sendServerCommand = dbl; LivingKnox.subscribe("EveryOneMinute", "Bench.minute", '
    'function(a, b) CLOCK = CLOCK + 3 return a + b, "x", nil, 7 end); L.start({ windowMs = 1000 }); L.install(); '
    'local f = Events.EveryOneMinute.list[1]; local r1, r2, r3, r4 = f(2, 5); local n = select("#", f(2, 5)); '
    'sendServerCommand("LivingKnox", "a", { k = 1 }); sendServerCommand({}, "LivingKnox", "b", { "xy" }); '
    'sendServerCommand("Other", "c", {}); L.counter(); local sum = L.stop(); local restored = sendServerCommand '
    '== dbl; Events, isServer, sendServerCommand = oldE, oldS, oldSend; '
    'LivingKnox.handlers["EveryOneMinute/Bench.minute"] = nil; return "KR-LOAD " .. r1 .. " " .. r2 .. " " .. '
    'tostring(r3) .. " " .. r4 .. " " .. n .. " " .. sum.ticks .. " " .. sum.engineMs .. " " .. sum.sent.count '
    '.. " " .. sum.sent.toAll .. " " .. table.concat(sent, ",") .. " " .. tostring(restored) .. " " .. '
    'sum.modules[1].module .. " " .. L.lines(sum)[1]'
)
EXCHANGE_EVALS.append(LOAD_EVAL)

# LK13-T06 : hex rapide de LK_Store (gsub et table de remplacement) = Codec.hexBytes sur les 256 octets et un registre
# non ASCII, somme de controle par blocs (seize octets par appel) = Codec.checksumBytes (10 Ko, vide), relecture
# rapide (St.unhexOfBytes), dans la VM reelle ; ecriture differee du registre des groupes (writeSlotFile de test) : rien ecrit avant
# la fin de l'image, une ecriture pour trois changements, premiere ecriture relue, flush sans changement sans effet.
GFLUSH_EVAL = (
    'eval:local C = require("RadioSurvivor/RS_Codec"); local St = LivingKnox.Store; local G = LivingKnox.Groups; '
    'local all = {} for i = 0, 255 do all[#all + 1] = string.char(i) end local bytes = table.concat(all); '
    'local s = C.encodeBytes({ t = "\\195\\169t\\195\\169 \\226\\128\\153", n = 1.5, b = true }); '
    'local long = string.rep(bytes, 40) .. s; local same = St.hexOfBytes(bytes) == C.hexBytes(bytes) and '
    'St.hexOfBytes(s) == C.hexBytes(s) and St.checksumOfBytes(long) == C.checksumBytes(long) and '
    'St.checksumOfBytes("") == C.checksumBytes("") and St.checksumOfBytes(s) == C.checksumBytes(s) and '
    'St.unhexOfBytes(C.hexBytes(long)) == long and St.unhexOfBytes("0G") == nil; '
    'local old = St.writeSlotFile; local calls, flags = 0, {}; St.writeSlotFile = function(p, h, seq, d, nv) '
    'calls = calls + 1; flags[#flags + 1] = tostring(nv == true) return true end; local st = G.state; '
    'st.data, st.blocked, st.dirty, st.pending, st.verified, st.path, st.seq = G.newRegistry(), false, false, nil, '
    'false, "x", 0; local g = G.create({ type = "settlers", name = "Mill", day = 1 }); '
    'G.addMember(g.id, { role = "worker", day = 1 }); G.setMorale(g.id, 10); local before = calls; local d1 = G.isDirty(); '
    'G.onTick(); local d2 = G.isDirty(); G.setMorale(g.id, 20); G.flush(); G.flush(); G.setMorale(g.id, 30); '
    'G.flush({ verify = true }); St.writeSlotFile = old; return "KR-GFLUSH " .. tostring(same) .. " " .. before '
    '.. " " .. tostring(d1) .. " " .. tostring(d2) .. " " .. calls .. " " .. table.concat(flags, ",") .. " " .. st.seq'
)
EXCHANGE_EVALS.append(GFLUSH_EVAL)

# LK13-T07 : releve de fortification en forme compacte (Fortify.packFort) relu par Fortify.fortView dans la VM reelle :
# chaines, coordonnees relatives, identifiants recalcules, empreinte de la cle, chaine mal formee refusee. Modules
# charges ici, apres les autres echanges, avec une table Events vide le temps du chargement (aucun abonne inscrit).
EXCHANGE_EVALS += [
    'eval:Events = {} return nil',
    'load:LivingKnox/LK_Homes=' + str(MOD_LUA / 'server' / 'LivingKnox' / 'LK_Homes.lua'),
    'load:LivingKnox/LK_Fortify=' + str(MOD_LUA / 'server' / 'LivingKnox' / 'LK_Fortify.lua'),
    'eval:Events = nil return nil',
]
FORT_EVAL = (
    'eval:local F = LivingKnox.Fortify; local home = { x = 110, y = 110, z = 0 }; local v = { v = 1, hx = 110, '
    'hy = 110, hz = 0, key = "plan text", day = 3, work = 12.5, tools = { HAMMER = true, SAW = false }, tiers = { '
    'ground = { h = 2, s = 8 }, upper = { h = 0, s = 0 }, outer = { h = 1, s = 114 } }, sites = { { id = '
    '"barricade:112,105,0N", k = "barricade", t = "ground", x = 112, y = 105, z = 0, n = true, o = true, s = 4, '
    'h = 2 }, { id = "wall:103,117,0W", k = "wall", t = "outer", x = 103, y = 117, z = 0, n = false, o = false, '
    's = 2, h = 1 } }, boxes = { { i = -2147483000, u = 8 } }, pend = { n = 7, ops = { { u = 7, id = '
    '"barricade:112,105,0N", k = "barricade", x = 112, y = 105, z = 0, n = true, o = true, a = 0, b = 2 } } } }; '
    'local p = F.packFort(v); local b = F.fortView(p, home); local bad = F.fortView({ v = 2, hx = 110, hy = 110, '
    'hz = 0, key = "k", day = 1, work = 0, tools = "", tiers = "0/0,0/0,0/0", sites = "bg2,-5", boxes = "", pn = 0, '
    'ops = "" }, home); return "KR-FORT " .. p.sites .. " " .. p.ops .. " " .. p.boxes .. " " .. p.tools .. " " .. '
    'p.tiers .. " " .. p.key .. " " .. b.sites[1].id .. " " .. b.sites[2].id .. " " .. tostring(b.sites[1].o) .. '
    '" " .. b.pend.ops[1].id .. " " .. b.pend.n .. " " .. string.format("%.0f", b.boxes[1].i) .. " " .. b.work .. '
    '" " .. tostring(b.tools.HAMMER) .. tostring(b.tools.SAW) .. " " .. tostring(bad)'
)
EXCHANGE_EVALS.append(FORT_EVAL)

# LK13-T10 : tri des cles de RS_Codec (textes de tri calcules une fois) = comparateur historique, octet pour octet, sur
# 300 tables tirees (cles chaines, entieres, flottantes, negatives, non ASCII, tables imbriquees) dans la VM reelle
# (table.sort de stdlib.lua) ; ecriture differee du registre des PNJ (writeSlotFile de test) : rien ecrit avant la fin
# de l'image, une ecriture pour trois changements, premiere ecriture relue, flush sans changement sans effet.
RFLUSH_EVAL = (
    'eval:local C = require("RadioSurvivor/RS_Codec"); local St = LivingKnox.Store; local pack; pack = '
    'function(v) local kind = type(v) if kind == "boolean" then return v and "b1" or "b0" end if kind == "string" '
    'then local s = C.toUtf8(v) return "s" .. #s .. ":" .. s end if kind == "number" then local s = tostring(v) '
    'return "n" .. #s .. ":" .. s end local keys = {} for k in pairs(v) do keys[#keys + 1] = k end '
    'table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end) local out = '
    '{ "t" .. #keys .. ":" } for _, k in ipairs(keys) do out[#out + 1] = pack(k) out[#out + 1] = pack(v[k]) end '
    'return table.concat(out) end; local seed = 1310; local function rnd(n) seed = (seed * 16807) % 2147483647 '
    'return seed % n end; local NAMES = { "a", "b", "A", "1", "10", "2", "n1", "number1", "fort", "members", '
    '"\\195\\169t\\195\\169", "", "z" }; local NUMS = { 0.5, 1.25, -3.75, 1e15, 0.0025, 123456789012, -1 }; '
    'local function gen(d) local t = {} for _ = 1, rnd(13) do local r = rnd(10) local k if r < 4 then '
    'k = NAMES[rnd(#NAMES) + 1] .. rnd(4) elseif r < 8 then k = rnd(141) - 20 else k = NUMS[rnd(#NUMS) + 1] end '
    'if d < 3 and rnd(10) < 3 then t[k] = gen(d + 1) else local w = rnd(5) if w == 0 then t[k] = true elseif '
    'w == 1 then t[k] = "v\\226\\128\\153" elseif w == 2 then t[k] = 1.5 else t[k] = rnd(5000) end end end '
    'return t end; local same = 0; for _ = 1, 300 do local t = gen(0) if C.encodeBytes(t) == pack(t) then '
    'same = same + 1 end end; local old = St.writeSlotFile; local calls, flags = 0, {}; St.writeSlotFile = '
    'function(p, h, seq, d, nv) calls = calls + 1; flags[#flags + 1] = tostring(nv == true) return true end; '
    'local st = St.state; st.data, st.blocked, st.queued, st.dirty, st.verified, st.path, st.seq = '
    'LivingKnox.Identity.newRegistry(), false, false, false, false, "x", 0; St.markChanged(); St.markChanged(); '
    'St.markChanged(); local before = calls; local q1 = St.isQueued(); St.onTick(); local q2 = St.isQueued(); '
    'St.markChanged(); St.flush(); St.flush(); St.markChanged(); St.flush({ verify = true }); St.writeSlotFile = old; '
    'return "KR-RFLUSH " .. same .. " " .. before .. " " .. tostring(q1) .. " " .. tostring(q2) .. " " .. calls .. '
    '" " .. table.concat(flags, ",") .. " " .. st.seq'
)
EXCHANGE_EVALS.append(RFLUSH_EVAL)

# E17-T12 : découpe d'une réplique (RS_TextCut.pieces) dans la VM réelle, longueurs en unités UTF-16 : mêmes morceaux
# que radio_bridge.cut_pieces (caractères) sur un texte accentué avec points de suspension (U+2026) et un décimal.
TEXTCUT_TEXT = ("Oui, j'ai du travail pour toi. Il s'agit d'aller repérer une maison à West Point, une expédition de "
                "deux heures, avec 9.5 litres d'essence et un sac bien rempli… Le rapport se fait en personne ; "
                "la récompense : vingt cartouches de 9 mm. Est-ce que ça t'intéresse ?")
TEXTCUT_LIMITS = (20, 30, 60, 100, 140)
EXCHANGE_EVALS += [
    'load:RadioSurvivor/RS_TextCut=' + str(MOD_LUA / 'shared' / 'RadioSurvivor' / 'RS_TextCut.lua'),
    'eval:local C = require("RadioSurvivor/RS_Codec"); local T = require("RadioSurvivor/RS_TextCut"); local out = {} '
    'for _, n in ipairs({' + ', '.join(str(n) for n in TEXTCUT_LIMITS) + '}) do out[#out + 1] = '
    'table.concat(T.pieces(' + lua_literal(TEXTCUT_TEXT) + ', n), "|") end return "KR-TEXTCUT " .. '
    'C.hex(table.concat(out, "#"))',
]


def fort_digest(text: str) -> str:
    """Fortify.digest recalcule en Python (texte ASCII)."""
    a, b, c = 1, 0, 0
    for x in text.encode('ascii'):
        a = (a + x) % 65521
        b = (b + a) % 65521
        c = (c * 31 + x) % 2147483647
    return f'{len(text)}:{b * 65536 + a}:{c}'


LOOKS = ['manFairBeard', 'manDarkGoatee', 'manBlondShaven', 'manOliveChops', 'manElderMoustache',
         'womanFairBun', 'womanTanBob', 'womanDarkPonytail', 'womanBlondLong', 'womanBrownKate']


def appearance_draw(seed: int, salt: int, n: int) -> int:
    """Tirage de LK_Appearance (Park-Miller + mélange modulo 65521, six pas de chauffe) recalculé en Python."""
    m = 2147483647
    x = (seed * 7919 + salt * 104729 + 1) % m or 1
    for _ in range(7):
        x = (x * 48271) % m
        x = (x + (x % 65521) * 31337) % m or 1
    return 1 + int(x / m * n)


def expected_appearance() -> str:
    out = []
    for seed in (1, 2, 3, 77, 999999999):
        out.append(f'{LOOKS[appearance_draw(seed, 1, len(LOOKS)) - 1]}#{appearance_draw(seed, 2, 500)}')
    women = [n for n in LOOKS if n.startswith('woman')]
    out.append(women[appearance_draw(7, 1, len(women)) - 1])
    out.append(str(-2147483648 + 12 * 65536 + 3))
    out.append(str(11 * 65536 + 32768 + 9))
    out.append(f'1:true:{women[appearance_draw(2, 1, len(women)) - 1]}:Generic04')
    return ' '.join(out)


def missing_prerequisites() -> str | None:
    for what, path in (('jeu (projectzomboid.jar)', JAR), ('JRE du jeu', JAVA), ('stdlib.lua du jeu', STDLIB),
                       ('ECJ (RS_ECJ_JAR ou tests/kahlua/ecj.jar)', ECJ)):
        if not path.is_file():
            return f'{what} introuvable : {path}'
    return None


def parse(output: str) -> dict[str, dict]:
    """Blocs KR-BEGIN / KR-END -> {label: {'done': bool, 'results': [(status, suite, test, message)], 'lines': []}}."""
    runs, current = {}, None
    for line in output.splitlines():
        if line.startswith('KR-BEGIN '):
            current = {'done': False, 'results': [], 'lines': []}
            runs[line[len('KR-BEGIN '):]] = current
        elif line.startswith('KR-END '):
            current = None
        elif current is not None:
            if line.startswith('KR-DONE '):
                current['done'] = line.endswith('yes')
            elif line.startswith('KR-STATUS '):
                status, suite, test, message = (line[len('KR-STATUS '):].split('\t') + ['', '', ''])[:4]
                current['results'].append((status, suite, test, message))
            else:
                current['lines'].append(line)
    return runs


class KahluaBench(unittest.TestCase):
    """Une seule exécution de la JVM pour toute la classe."""

    output = ''
    runs: dict[str, dict] = {}

    @classmethod
    def setUpClass(cls):
        why = missing_prerequisites()
        if why:
            raise unittest.SkipTest(why)
        cls.tmp = tempfile.TemporaryDirectory()
        work = Path(cls.tmp.name)
        shutil.copyfile(STDLIB, work / 'stdlib.lua')  # J2SEPlatform.newEnvironment le lit dans le dossier courant
        compiled = subprocess.run([str(JAVA), '-jar', str(ECJ), '-21', '-nowarn', '-cp', str(JAR), '-d', str(work),
                                   str(BENCH / 'KRun.java')], capture_output=True, text=True, timeout=300)
        if compiled.returncode != 0:
            raise AssertionError('compilation de KRun.java : ' + compiled.stdout + compiled.stderr)
        args = []
        for name, path in LUA_FILES:
            if name in EVENTS_AT_LOAD:   # abonnes inscrits au chargement : table Events vide le temps du chargement
                args += ['eval:Events = {} return nil', f'load:{name}={path}', 'eval:Events = nil return nil']
            else:
                args.append(f'load:{name}={path}')
        for flt in RUNS:
            args += [f'eval:return START("{flt}")', f'ticks:{MAX_TICKS}:TICK', f'eval:return RESULT("{flt}")']
        args += EXCHANGE_EVALS
        # Fichier d'arguments du lanceur java (@fichier) : la ligne de commande Windows est limitée à 32 767
        # caractères, dépassés depuis LK08-T02. Chaque argument entre guillemets, \ et " échappés (règles des
        # fichiers d'arguments du lanceur) ; la classe principale est dans le fichier, les arguments qui la suivent
        # sont pris tels quels.
        argfile = work / 'krun.args'
        argfile.write_text('\n'.join(java_arg(a) for a in ['-cp', os.pathsep.join([str(JAR), str(work)]), 'KRun', *args]),
                           encoding='ascii')
        proc = subprocess.run([str(JAVA), '@' + str(argfile)],
                              cwd=work, capture_output=True, text=True, encoding='utf-8', errors='replace',
                              timeout=600)
        cls.output = proc.stdout + proc.stderr
        cls.runs = parse(proc.stdout)

    @classmethod
    def tearDownClass(cls):
        tmp = getattr(cls, 'tmp', None)
        if tmp is not None:
            tmp.cleanup()

    def run_of(self, label):
        self.assertIn(label, self.runs, self.output[-4000:])
        run = self.runs[label]
        self.assertTrue(run['done'], f'{label} : onDone non appelé (passage figé)\n' + self.output[-4000:])
        return run

    def statuses(self, label):
        return {(suite, test): (status, message) for status, suite, test, message in self.run_of(label)['results']}

    def test_files_load_and_ticks_end(self):
        self.assertNotIn('KRUN-ERROR', self.output, self.output[-4000:])
        self.assertNotIn('LOAD-ERROR', self.output)
        for flt in RUNS:
            self.assertIn(f'KR-STARTED {flt}', self.output)
        ticks = [int(line.split()[1]) for line in self.output.splitlines() if line.startswith('KRUN-TICKS ')]
        self.assertEqual(len(ticks), len(RUNS))
        self.assertTrue(all(n < MAX_TICKS for n in ticks), ticks)

    def test_selftest_passes(self):
        res = self.statuses('rst')
        self.assertEqual(len(res), 6, res)
        bad = {k: v for k, v in res.items() if v[0] != 'PASS'}
        self.assertEqual(bad, {})
        self.assertTrue(all(suite == 'rst.selftest' for suite, _ in res))  # rst.failures exclue par défaut
        self.assertTrue(self.run_of('rst')['lines'][-1].startswith('OK - 6 test(s): 6 pass'))

    def test_failures_give_expected_statuses_and_the_run_ends(self):
        res = self.statuses('rst.failures')
        self.assertEqual(len(res), 13, res)
        for (_suite, test), (status, message) in res.items():
            expected = test.split(' expected', 1)[0]
            self.assertEqual(status, expected, f'{test}: {message}')
        get = lambda name: res[('rst.failures', name)][1]
        self.assertEqual(get('FAIL expected: assertion in the body'), 'deliberate: expected 1, got 2')
        self.assertEqual(get('FAIL expected: assertion in a deferred step'), 'deliberate: expected 1, got 2')
        self.assertIn('expected argument of type int, got String', get('ERROR expected: Java exception in the body'))
        self.assertIn('expected argument of type int, got String',
                      get('ERROR expected: Java exception in a deferred step'))
        self.assertIn('waitUntil condition raised: ', get('ERROR expected: Java exception in a waitUntil condition'))
        self.assertIn('get returned nil', get('FAIL expected: Java exception logged by the game, the step goes on'))
        self.assertEqual(get('ERROR expected: error() in a deferred step'), 'deliberate error in a deferred step')
        self.assertEqual(get('ERROR expected: error() in a cleanup that waits'),
                         'cleanup waiting cleanup: deliberate error in a cleanup step')
        self.assertEqual(get('FAIL expected: waitUntil timeout'), 'deliberate: condition not met within 200 ms')
        self.assertTrue(self.run_of('rst.failures')['lines'][-1].startswith('FAILED - 13 test(s): 1 pass'))

    def test_codec_passes(self):
        res = self.statuses('rs.codec')
        self.assertEqual(len(res), 15)
        bad = {test: v for (_s, test), v in res.items() if v[0] != 'PASS'}
        self.assertEqual(bad, {})  # E00-T08 : « hex round trip of characters above U+00FF » passe en Kahlua

    def line(self, prefix):
        found = [line for line in self.output.splitlines() if line.startswith(prefix + ' ')]
        self.assertEqual(len(found), 1, self.output[-4000:])
        return found[0][len(prefix) + 1:]

    def test_voices_suites_declared(self):
        self.assertEqual(self.line('KR-VOICES'), 'rs.voices=5/nil rs.voices.world=3/nil')

    def test_radio_talk_logic_in_kahlua(self):
        self.assertEqual(self.line('KR-RADIOTALK'), 'truefalsefalsefalse l3,l4 200')

    def test_radio_history_in_kahlua(self):
        self.assertEqual(self.line('KR-HISTORY'), '40 t6 true 146000')

    def test_radiomodule_suites_declared(self):
        self.assertEqual(self.line('KR-RADIOMODULE'), 'rs.radiomodule=5/nil rs.radiomodule.world=2/nil')

    def test_notebook_visual_suite_declared(self):
        self.assertEqual(self.line('KR-NBVISUAL'), 'rs.notebook.visual=3/nil')

    def test_kahlua_strings_are_utf16_units(self):
        # 31 caractères dont un hors BMP : 32 unités UTF-16 en Kahlua (39 octets UTF-8 sous lupa).
        self.assertEqual(self.line('KR-CODEC'), f'utf16=true len={len(ACCENTED.encode("utf-16-le")) // 2}')

    def test_accented_request_from_kahlua_decoded_by_the_bridge(self):
        value = protocol.decode(bytes.fromhex(self.line('KR-PAYLOAD')))
        self.assertEqual(value, {'version': 2, 'kind': 'npc_talk', 'text': ACCENTED})

    def test_accented_reply_from_the_bridge_read_by_kahlua(self):
        self.assertEqual(self.line('KR-REPLY'), 'true ' + ACCENTED.encode('utf-8').hex())

    def test_old_latin1_state_keeps_checksum_and_text(self):
        old = bytes.fromhex('74313a73343a6e616d6573343a636166e9')
        a, b = 1, 0
        for x in old:
            a = (a + x) % 65521
            b = (b + a) % 65521
        self.assertEqual(self.line('KR-LEGACY'), f'{b * 65536 + a} true')

    def test_identity_logic_in_kahlua(self):
        self.assertEqual(self.line('KR-IDENTITY'), 'lk-1 lk-2 12 lk-1#2 current stale ahead unknown notEmbodied true schema')

    def test_group_types_in_kahlua(self):
        self.assertEqual(self.line('KR-GROUPTYPES'),
                         'neutrals,raiders,settlers 0 true neutrals,nomads,raiders,settlers breach 8 / bad id / '
                         'profile walker weapons entry 1: vanilla weapon not allowed Base.Spoon / '
                         'identifier already registered / 3')

    def test_groups_logic_in_kahlua(self):
        self.assertEqual(self.line('KR-GROUPS'), 'grp-1 m-2 100 43 0 -1 8 200 lk-3 false 1 leader is dead / schema m-3')

    def test_api_in_kahlua(self):
        # Memes valeurs que sous lupa (tests/test_lk_api.py) : maille 100, distance arrondie, aucun journal.
        self.assertEqual(self.line('KR-API'), '1 1 Mill 10650,9450 nil nil lk-1 1 1 lk-1 grp-1 5 1 false 10650 nil worker')

    def test_attitude_in_kahlua(self):
        # LK11-T03 : memes valeurs que sous lupa (tests/test_lk_hostility.py) : -10 prudent, 70 confiant, declin.
        self.assertEqual(self.line('KR-ATT'), 'cautious down trusting up nil 3 -15 50 0 3')

    def test_senses_model_in_kahlua(self):
        # LK05-T01 : memes valeurs que sous lupa (tests/test_lk_senses.py, ModelTests).
        self.assertEqual(self.line('KR-SENSES'), '20.000 2.500 false 5.952 true false 0.9900 run')

    def test_decisions_in_kahlua(self):
        # LK05-T02 : memes valeurs que sous lupa (tests/test_lk_decisions.py, KahluaParityTests).
        self.assertEqual(self.line('KR-DECIDE'), 'flee 146 1 602 guard 31 620 rest 12379 supply 44 61 0.205245')

    def test_alert_in_kahlua(self):
        # LK05-T08 : memes valeurs que sous lupa (tests/test_lk_alert.py, KahluaParityTests).
        self.assertEqual(self.line('KR-ALERT'), '2 z? z:5 raised seen joined 45 6 alert:al-1 false')

    def test_load_measure_in_kahlua(self):
        # LK13-T02 : memes regles que sous lupa (tests/test_lk_load.py, WrapTests et NetworkTests).
        self.assertEqual(self.line('KR-LOAD'), '7 x nil 7 4 1 6 2 1 3,4,3 true Bench load on server: 0 s, 1 ticks, '
                         'engine 6 ms/tick (max 6 ms in one tick, 1 ticks >= 1 ms), 1 subscribers measured')

    def test_groups_deferred_write_in_kahlua(self):
        # LK13-T06 : memes regles que sous lupa (tests/test_lk_groups.py, DeferredWriteTests).
        self.assertEqual(self.line('KR-GFLUSH'), 'true 0 true false 3 false,true,false 3')

    def test_npc_registry_deferred_write_and_codec_sort_in_kahlua(self):
        # LK13-T10 : memes octets que le comparateur historique ; memes regles que sous lupa (tests/test_lk_store.py).
        self.assertEqual(self.line('KR-RFLUSH'), '300 0 true false 3 false,true,false 3')

    def test_fortify_compact_form_in_kahlua(self):
        # LK13-T07 : memes chaines que sous lupa (tests/test_lk_fortify_offscreen.py, CompactFormTests).
        self.assertEqual(self.line('KR-FORT'), 'bg2,-5,0N142;wo-7,7,0W021 7:b2,-5,0N102 -2147483000:8 HAMMER '
                         f'2/8,0/0,1/114 {fort_digest("plan text")} barricade:112,105,0N wall:103,117,0W true '
                         'barricade:112,105,0N 7 -2147483000 12.5 truenil nil')

    def test_supply_in_kahlua(self):
        # LK12-T03 : memes valeurs que sous lupa (tests/test_lk_api.py, SupplyTests).
        self.assertEqual(self.line('KR-SUPPLY'), '2 grp-1-food-1 60 40 5 true 5 10 true '
                         'Base.ShotgunShellsBox offer closed 35 57 2')

    def test_events_in_kahlua(self):
        # LK12-T02 : memes regles que sous lupa (tests/test_lk_api.py, EventTests) ; disparition apres la mort.
        self.assertEqual(self.line('KR-EVENTS'), '1 0 3 0 OnLivingKnoxNeedCritical=food,OnLivingKnoxGroupCreated=Mill,'
                         'OnLivingKnoxMemberLeft=leave_group,OnLivingKnoxMemberDied=m-2,OnLivingKnoxGroupGone=dead')

    def test_simulation_in_kahlua(self):
        # Mêmes valeurs que sous lupa (tests/test_lk_simulation.py, même graine et même état de départ) ; expéditions
        # comprises depuis LK09-T02 (réserve de soins à 0 : une équipe part et revient pendant les 24 h).
        self.assertEqual(self.line('KR-SIM'), 'true 34 43 2 84 43 62 m-2 true 20 497 1')

    def test_simulation_events_in_kahlua(self):
        # LK09-T05 : événements (combat compris), mêmes valeurs que sous lupa (tests/test_lk_simulation.py).
        self.assertEqual(self.line('KR-EVT'), 'true 8 0 47 32 58 7 6 nil m-1')

    def test_appearance_logic_in_kahlua(self):
        self.assertEqual(self.line('KR-APPEARANCE'), expected_appearance())

    def test_clothes_registry_in_kahlua(self):
        self.assertEqual(self.line('KR-CLOTHES'),
                         'true true 2 Base.Tshirt_DefaultTEXTURE_TINT|Tshirt_DefaultTEXTURE_TINT|-|31,166,127|'
                         '-0.3800|0|2|TShirtDecal;Base.Shoes_Black|-|-|-|-|-|-|- clothes entry 1: bad hue / '
                         'npc lk-1: clothes entry 2: bad tint')

    def test_persona_sheets_read_like_python(self):
        # E05-T01 : accents, caractère hors BMP, BOM et U+FFFD vus en unités UTF-16 ; mêmes fiches, mêmes refus.
        for name, raw, expected_id in PERSONA_CASES:
            with self.subTest(name):
                self.assertEqual(self.line(f'KR-PERSONA-{name}'), persona_expected(raw, expected_id))
        self.assertTrue(persona_expected(PERSONA_CASES[0][1], 'walt').startswith('OK '))
        self.assertTrue(persona_expected(PERSONA_CASES[2][1], 'case').startswith('ERR '))

    def test_map_mark_in_kahlua(self):
        # E07-T04 : repère au centre de la case, libellé nettoyé de 12 unités (« Café  b x /b »), aucun doublon.
        self.assertEqual(self.line('KR-MAP'), 'added present 2 1 12 10600.5,9300.5 1/0')

    def test_map_reveal_in_kahlua(self):
        # E07-T05 : bord haut inclus (x2 - 1), flottants admis, non aligné ou trop grand refusé, carte absente.
        self.assertEqual(self.line('KR-REVEAL'), 'revealed revealed nil/bad_args nil/bad_args nil/no_map '
                         '10528,9216,10687,9375;10528,9216,10687,9375')

    def test_frequency_draw_in_kahlua(self):
        # E05-T07 : tirage, fichier de la partie et reprise au rechargement dans la VM Kahlua réelle.
        self.assertEqual(self.line('KR-DRAW'), '100600 RSFREQ1/abe 100000-101000 100600 1 100600/1')

    def test_personas_server_in_kahlua(self):
        v = 'batman_RadioSurvivor-voice-'
        self.assertEqual(self.line('KR-PERSONAS'), ' '.join([
            'frequencies=150.2', v + 'walt-150200', '150.2',
            f'{v}abe-147000,{v}walt-145000,{v}walt-146000', 'walt',
            f'{v}abe-147000,{v}walt-145000,{v}walt-146000|146000',
            f'{v}walt-145000,{v}walt-146000', 'true']))

    def test_text_cut_in_kahlua_same_as_the_bridge(self):
        # E17-T12 : unités UTF-16 en Kahlua = caractères en Python (texte du plan multilingue de base, BMP).
        sys.path.insert(0, str(ROOT / 'bridge'))
        import radio_bridge
        expected = '#'.join('|'.join(radio_bridge.cut_pieces(TEXTCUT_TEXT, n)) for n in TEXTCUT_LIMITS)
        self.assertEqual(bytes.fromhex(self.line('KR-TEXTCUT')).decode('utf-8'), expected)

    def test_missions_pass(self):
        res = self.statuses('rs.missions')
        self.assertEqual(len(res), 14)
        bad = {k: v for k, v in res.items() if v[0] != 'PASS'}
        self.assertEqual(bad, {})


class ParseTests(unittest.TestCase):
    """Lecture de la sortie du banc, sans Java."""

    def test_parse_blocks(self):
        out = ('KR-BEGIN a\nKR-DONE yes\nKR-STATUS PASS\tsuite\ttest\t\nOK - 1 test(s)\nKR-END a\n'
               'KR-BEGIN b\nKR-DONE no\nKR-END b\n')
        runs = parse(out)
        self.assertEqual(runs['a'], {'done': True, 'results': [('PASS', 'suite', 'test', '')],
                                     'lines': ['OK - 1 test(s)']})
        self.assertFalse(runs['b']['done'])


if __name__ == '__main__':
    unittest.main(verbosity=1)
