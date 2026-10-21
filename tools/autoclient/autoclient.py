"""Lanceur client automatique (E01-T14) : vrai client Project Zomboid 42.21, partie rstest*, suites RST, rapport.

    python RadioSurvivor/tools/autoclient/autoclient.py --suite rs.env
    python RadioSurvivor/tools/autoclient/autoclient.py --campaign solo-rs --timeout 1800
    python RadioSurvivor/tools/autoclient/autoclient.py --suite rs.npctalk --tags world     pont lancé (auto)
    python RadioSurvivor/tools/autoclient/autoclient.py --save rstest-2026-10-13 --suite rst.guard,rs.env --keep-cache
    python RadioSurvivor/tools/autoclient/autoclient.py --dry-run --suite rs.env     prépare le cache, ne lance rien

Tout se passe dans un nouveau dossier de cache temporaire (`-cachedir=`) : COPIE de la sauvegarde, copies des mods,
copie modifiée de options.ini. Rien n'est écrit dans le jeu, dans `%USERPROFILE%\\Zomboid` ni dans le Workshop Steam
(TooltipLib y est seulement lu pour être copié). Étapes :
  1. refus si un processus java.exe ou ProjectZomboid64.exe tourne déjà (attente possible : --wait-idle) ;
  2. cache : Saves/<mode>/<partie> (mods.txt réécrit avec la liste minimale), mods/ (TooltipLib, batman_BeltRadio,
     batman_CharacterReputation, batman_SignalSmoke, batman_RadioSurvivor, batman_RadioSurvivorTests) et
     mods/default.txt (même liste : pas de rechargement Lua au chargement), options.ini (fenêtré),
     Lua/batman_RadioSurvivor/tests/autoclient.txt ; les mods requis Belt Walkie-Talkie et Signal Smoke sont toujours
     copiés de leurs dépôts locaux Workshop/BeltRadio et Workshop/SignalSmoke (lus seulement), en solo comme en MP ;
  2 bis. pont Python (--bridge auto|on|off|offline ; auto = lancé si une suite choisie en a besoin, BRIDGE_SUITES) :
     bridge/radio_bridge.py --exchange <cache>\\Lua\\batman_RadioSurvivor, attendu jusqu'à « Bridge ready »
     (--bridge-timeout), arrêté à la fin dans tous les cas ; il lit lui-même sa configuration (bridge/.env ou
     variables d'environnement), jamais ouverte par cet outil ; son journal est rangé en bridge.log, chaînes de
     forme « clé » masquées (code 2 s'il y en avait) ;
  3. lancement de jre64\\bin\\java.exe depuis le dossier du jeu avec les vmArgs de ProjectZomboid64.json
     (zomboid.steam=0) et `-cachedir=… -debug -nosound -nosteam` ;
  4. le pilote Lua RST_AutoClient.lua charge la partie au menu ; l'écran de chargement attend un clic gauche
     (GameLoadingState.update lit Mouse.isButtonDown(0)) : le lanceur envoie WM_LBUTTONDOWN/UP à la fenêtre du
     processus (PostMessage, sans prendre le focus ni bouger la souris) tant que le dernier état est « load » ;
  5. fin : autoclient-result.txt complet (dernière ligne RST-END), le jeu se ferme (quitToDesktop, sauvegarde de la
     copie) ; sinon arrêt forcé du seul processus lancé, après --timeout ou --quit-timeout.
Résultats copiés dans tools/autoclient/runs/<date>-<jeton>/ : autoclient-result.txt, autoclient-status.txt,
rapports RST (*.txt), captures (Screenshots), console.txt, sortie du processus, bridge.log et token_usage.jsonl.
Codes de sortie : 0 rapport OK ; 1 tests en échec ; 2 délai, échec de démarrage ou refus ; 3 jeu ou serveur non
lancé par l'outil, ou aucun emplacement libre (--max-parallel).

Multijoueur (E01-T15) : --mp [--clients 1..4]
    python RadioSurvivor/tools/autoclient/autoclient.py --mp --server-suite rs.identity,rs.facts
    python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --server-campaign mp --timeout 5400
    python RadioSurvivor/tools/autoclient/autoclient.py --mp --suite rs.env --server-suite lk.melee --server-tags world
  1. serveur dédié de test (zombie.network.GameServer, -nosteam, mode debug par la propriété Java -Ddebug : un
     argument -debug est ignoré par GameServer ; isDebugEnabled() exigé par l'API de test, E01-T18 ; cache temporaire
     rs-mp-server-*, mêmes mods, ini
     rstest_mp : PauseEmpty, SpawnPoint fixe dans une maison de Muldraugh, ports 17391/17392, mot de passe d'admin
     tiré pour ce passage), prêt à la ligne « server is listening on port » ; comptes rs_mp2.. créés et passés
     admin par la console (adduser, setaccesslevel : un client -debug sans ConnectWithDebug est déconnecté) ;
  2. clients lancés l'un après l'autre (le suivant quand le précédent est en jeu), caches et comptes distincts, -Xmx
     borné (--client-xmx) : le pilote Lua rejoint le serveur (ConnectToServer:connect), passe la création du personnage
     (NEXT, NEXT), le lanceur clique l'écran de chargement ; quand tous sont en jeu, « go » dans
     autoclient-control.txt : le client 1 lance --suite/--campaign (RST.run) puis --server-suite/--server-campaign
     (RST.server, il est admin) ; les autres restent connectés et répondent aux étapes des suites serveur (E01-T16 :
     rôle « peer », RST.Steps : vérifications côté client, passage au niveau d'accès « user » pour les suites de
     droits, demandé par le client 1 avec /setaccesslevel ; au « quit », chacun écrit son résultat d'étapes, exigé
     comme celui du client 1) ; chaque joueur passe en mode dieu par
     la console (godmodeplayer, sauf --no-godmode : sinon les zombies du quartier tuent les joueurs immobiles) ;
     sandbox du serveur sans zombie ambiant (multiplicateurs de population de départ et de pic à 0) sauf
     --ambient-zombies : site calme comme les parties de test solo, les suites créent leurs propres zombies ;
     ini du serveur avec AntiCheatPermission=4 : un client -debug passé au niveau « user » en cours de partie serait
     sinon expulsé par l'anti-triche « Power » (paquet joueur avec le drapeau debug, AntiCheatPower) ; les droits des
     paquets et de Lua restent contrôlés (PacketAuthorization, checkPermissions) ;
  3. fin : « quit » à tous les clients (quitToDesktop), puis « quit » sur l'entrée standard du serveur ; arrêts forcés
     des seuls processus lancés ici. Pont (--bridge) sur le dossier d'échange du SERVEUR (RS_Transport y écrit).
  Résultats : runs/<date>-<jeton>/ avec server/ (sortie, server-console.txt, rapports *-server.txt, Logs) et
  client<N>/ (comme en solo, plus <stamp>-steps.txt : étapes auxquelles ce client a répondu).
  Jusqu'à 4 clients (LK13-T02) : comptes rs_mp1..rs_mp4, caches rs-mp-client<N>-*, même serveur (ports 17391/17392,
  MaxPlayers 4), lancés l'un après l'autre, clients 2..N en rôle « peer » ; mémoire affichée au départ : -Xmx total
  (N x --client-xmx + --server-xmx) et estimation avec la part native (+1,5 Go par client, +0,75 Go pour le serveur),
  avertissement si la mémoire libre est plus faible. --group-count 3..5 écrit LivingKnox.GroupCount dans le
  <serveur>_SandboxVars.lua partiel du monde neuf.

Lancements parallèles (2026-10-15) : plusieurs commandes de cet outil peuvent tourner en même temps.
  - Emplacements : --max-parallel N (défaut 3) fichiers %TEMP%\\rs-autoclient-slots\\slot-<i>.json (pid de l'outil, pids
    du jeu et du serveur qu'il a lancés) ; un lancement attend (--wait-idle) un emplacement libre ; un emplacement dont
    l'outil est mort (arrêt brutal) est repris. Les java.exe / ProjectZomboid64.exe des AUTRES lancements ne bloquent
    plus ; un jeu ou serveur non lancé par l'outil (le joueur) bloque toujours (jamais tué).
  - Ports du serveur de test : --port-base P (UDPPort = P + 1), sinon 17391 + 10 x emplacement, décalés de 10 tant
    qu'ils sont pris. Caches, comptes (même nom, serveurs distincts), fichiers de contrôle et dossier runs/ propres.
  - --shard K/N : tranche K sur N d'une --campaign / --server-campaign (entrées réparties par la durée des rapports
    précédents de runs/, la plus longue d'abord vers la tranche la moins chargée ; sans durée : tour à tour par nom),
    ordre de la campagne gardé dans la tranche ; filtre de la campagne gardé (serveur : exclusion manual) ; jamais avec
    --phases ni mp-persist. tools/autoclient/campaign_parallel.py lance N tranches et fusionne les rapports.
  - --llm fake : faux modèle local déterministe (tools/fake_llm/fake_llm.py --port P, ligne « FAKE LLM READY port=P »)
    sur un port libre, pont lancé avec OPENAI_BASE_URL=http://127.0.0.1:P/v1, OPENAI_MODEL=fake, OPENAI_KEY=fake (son
    environnement prime sur son .env, jamais lu ici) ; arrêté à la fin, journal fake_llm.log dans le dossier du run.
    python RadioSurvivor/tools/autoclient/campaign_parallel.py --shards 3 -- --mp --clients 2 --server-campaign mp \\
        --bridge on --llm fake --timeout 5400 --wait-idle 3600

Campagne de charge (LK13-T02, docs/annexes/tests/validation/charge-protocole.md) : --mp --load
    python RadioSurvivor/tools/autoclient/autoclient.py --mp --load --bridge off --timeout 3600 --wait-idle 3600
  = 4 clients, LivingKnox.GroupCount = 5, campagne serveur mp-load si RST_Campaign.lua la déclare, sinon
  --server-suite lk.load --server-tags server ; les options explicites (--clients, --group-count, --server-*) priment.

Reconnexion et redémarrage (E01-T17) : --mp --phases reconnect,restart --server-campaign mp-persist
    python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --phases reconnect,restart \\
        --server-campaign mp-persist --server-tags world --timeout 3600 --wait-idle 3600
  --server-suite / --server-campaign donnent des BASES B ; chaque B a une suite B.before (instantané, tag manual) et
  au moins une B.after-reconnect ou B.after-restart (phase_plan). Étape 0 : B.before. Puis, pour chaque action :
  « quit » à tous les clients (déconnexion, quitToDesktop), pour « restart » « quit » sur la console du serveur
  (sauvegarde), --restart-pause, relance du MÊME serveur (même cache, même monde), « setaccesslevel … admin » ; chaque
  client rejoint avec son compte (personnage existant : pas de création, RST_AutoClient écrit « load » à
  OnConnected) et un nouveau jeton ; le client 1 demande B.after-<action> puis, si une étape suivante revérifie B,
  B.before de nouveau (deux exécutions serveur successives, serverSuite=a;b). Fichiers de chaque étape archivés en
  p<étape>-*.txt (console, sortie, résultat) ; le code final est le pire des étapes.
  Action « reconnect2 » (--clients 2 ou plus) : les clients 2..N quittent et rejoignent ; le client 1 reste connecté
  (jamais de « quit » à la fin de l'étape précédente), reçoit la commande de l'étape suivante (nouveau jeton) et le
  mot « reload » dans son fichier de contrôle (RST_AutoClient relit la commande, statut « ingame », puis attend
  « go ») ; suites
  B.after-reconnect2 (ex. lk.rejoin : l'exécutant d'une consigne se reconnecte). Étape avec rst.disconnect.before
  avant reconnect2 : le « quit » du client 2 attend (QUIT_WAIT_S = 15 s au plus, puis WARNING) la ligne serveur
  « run started by account 'rs_mp2' » (son exécution rst.disconnect.slow a commencé).
  Mort réelle d'un client (rs.death) : à chaque ligne d'état « respawn: new character … », godmodeplayer de nouveau
  (sauf --no-godmode) ; un état « load » après une reprise est cliqué comme d'habitude.
  Action « modswap » (seule, LK02-T12) : mêmes suites avant et après un redémarrage (clients puis serveur arrêtés
  comme pour restart) où batman_RadioSurvivorTestClothes (dev/) est ajouté aux mods du serveur (Mods= de l'ini) et
  des clients (mods/, default.txt) : --mp --clients 2 --phases modswap --server-suite lk.appearance.
  --load : --timeout 3600 par défaut ; --load-phase-ms N écrit la globale Lua RST_LK_LOADMP_PHASE_MS = N dans la
  copie du mod de test de chaque cache (Kahlua n'a pas os.getenv).
  Copie figée : tools/autoclient/campaign_parallel.py --commit REF (worktree dans %TEMP%) ; RS_WORKSHOP_DIR (mods
  frères) et RS_AUTOCLIENT_RUNS (dossier runs/) remplacent alors les chemins relatifs à ce fichier.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Launch from a frozen copy (campaign_parallel.py --commit: git worktree outside the Workshop folder): the sister mods
# (BeltRadio, CharacterReputation, SignalSmoke) stay in the real Workshop folder (RS_WORKSHOP_DIR), the results go to
# the runs/ folder of the main repository (RS_AUTOCLIENT_RUNS). The bridge of the copy has no configuration file of
# its own (git-ignored): a real model needs OPENAI_* in the environment, --llm fake needs nothing.
WORKSHOP_DEV = Path(os.environ.get('RS_WORKSHOP_DIR') or ROOT.parent)
sys.path.append(str(Path(__file__).resolve().parents[1]))
import pz_paths  # noqa: E402  (game and Workshop folders: PZ_STEAM_LIBRARY, PZ_DIR or Steam detection)

GAME = pz_paths.game_dir()
STEAM_WORKSHOP = pz_paths.workshop_dir()
ZOMBOID = Path(os.environ.get('USERPROFILE') or str(Path.home())) / 'Zomboid'
RUNS = Path(os.environ.get('RS_AUTOCLIENT_RUNS') or Path(__file__).resolve().parent / 'runs')
TESTS_DIR = 'Lua/batman_RadioSurvivor/tests'

# (id, source) in load order: requirements first.
MODS = [
    ('TooltipLib', STEAM_WORKSHOP / '3694097672' / 'mods' / 'TooltipLib'),
    ('batman_BeltRadio', WORKSHOP_DEV / 'BeltRadio' / 'Contents' / 'mods' / 'batman_BeltRadio'),
    ('batman_CharacterReputation',
     WORKSHOP_DEV / 'CharacterReputation' / 'Contents' / 'mods' / 'batman_CharacterReputation'),
    # Required by RadioSurvivor (mod.info require=, 2026-10-15): always copied; its local repository is only read.
    ('batman_SignalSmoke', WORKSHOP_DEV / 'SignalSmoke' / 'Contents' / 'mods' / 'batman_SignalSmoke'),
    ('batman_RadioSurvivor', ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor'),
    ('batman_RadioSurvivorTests', ROOT / 'dev' / 'batman_RadioSurvivorTests'),
]
IGNORE = shutil.ignore_patterns('__pycache__', '*.pyc', '*.bak', '*.tmp', '.git')
# Python bridge (step 2): started on the exchange folder of the cache, never on %USERPROFILE%\Zomboid. It reads its
# own configuration (bridge/.env or environment variables): this tool never opens that file.
BRIDGE_SCRIPT = ROOT / 'bridge' / 'radio_bridge.py'
EXCHANGE_DIR = 'Lua/batman_RadioSurvivor'
BRIDGE_READY = 'Bridge ready'
BRIDGE_SUITES = ('rs.npctalk', 'rs.radiomodule', 'rs.relation', 'rs.conversations', 'rs.initiatives',
                 'rs.groupradio')
CAMPAIGN_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / 'client' / 'RST' / \
    'RST_Campaign.lua'
# Credential shapes searched in the stored bridge journal (the key itself is never read by this tool).
SECRET_PATTERNS = (r'\b(?:sk|gsk|xai)[-_][A-Za-z0-9_-]{16,}', r'\bAIza[A-Za-z0-9_-]{30,}', r'Bearer\s+[A-Za-z0-9._-]{8,}',
                   r'OPENAI_KEY\s*[=:]\s*\S+', r'(?i)authorization\s*[=:]\s*\S+')
BUSY_NAMES = ('java.exe', 'projectzomboid64.exe')
RESET_MARKER = 'If this file does not exist, default.txt will be reset to empty (no mods active).'
WINDOW = {'width': '1280', 'height': '720', 'fullScreen': 'false', 'borderless': 'false'}
# Multiplayer (E01-T15). The server name starts with "rstest": RST world suites are allowed on that world.
MP_SERVER_NAME = 'rstest_mp'
MP_PORT, MP_UDP_PORT = 17391, 17392
MP_SPAWN = '10656,10137,0'  # medium house of Muldraugh (media/maps/Muldraugh, KY/spawnpoints.lua)
MP_READY = ('server is listening on port', '*** SERVER STARTED')
MP_INGAME = ('ingame', 'go', 'run', 'server', 'done', 'idle')
# Parallel runs: one slot file per running launch (pid of the tool, pids of its game and server processes), ports of
# the test server moved by PORT_STEP per slot. A run killed abruptly leaves its file: a dead tool pid frees the slot.
SLOTS_DIR = Path(tempfile.gettempdir()) / 'rs-autoclient-slots'
DEFAULT_MAX_PARALLEL = 3
PORT_STEP = 10
# --llm fake: local deterministic OpenAI-compatible server (python fake_llm.py --port P prints the ready line).
FAKE_LLM_SCRIPT = ROOT / 'tools' / 'fake_llm' / 'fake_llm.py'
FAKE_LLM_READY = 'FAKE LLM READY'
MAX_CLIENTS = 4  # LK13-T02: 4 players (MaxPlayers of the test server)
# Memory estimate of an MP run (LK13-T02): -Xmx of each JVM plus what it uses outside the Java heap (game client:
# native buffers, textures, LWJGL; server: much less). Rough figures, only used for the warning.
CLIENT_NATIVE_MB, SERVER_NATIVE_MB = 1536, 768
# Load measure (LK13-T02, docs/annexes/tests/validation/charge-protocole.md): 4 clients, 5 groups (LivingKnox.GroupCount), server
# campaign mp-load when RST_Campaign.lua declares it, else the suite lk.load alone.
LOAD_CLIENTS, LOAD_GROUPS, LOAD_CAMPAIGN, LOAD_SUITE = 4, 5, 'mp-load', 'lk.load'
DEFAULT_TIMEOUT, LOAD_TIMEOUT = 900, 3600   # --timeout when not given (mp-load: about 20 min of server run)
# --load-phase-ms: Lua global RST_LK_LOADMP_PHASE_MS read by lk.loadmp (Kahlua has no os.getenv: a Lua file written
# into the copies of the development mod of every cache of the run, never into the repository).
LOAD_PHASE_GLOBAL, LOAD_PHASE_MIN_MS = 'RST_LK_LOADMP_PHASE_MS', 30000
LAUNCH_GLOBALS_FILE = Path('batman_RadioSurvivorTests') / '42.21' / 'media' / 'lua' / 'shared' / 'RST' / \
    'RST_LaunchGlobals.lua'
# Phase "modswap" (LK02-T12, lk.appearance): restart with this mod added to the mod lists of the server and clients.
MODSWAP_MOD = ('batman_RadioSurvivorTestClothes', ROOT / 'dev' / 'batman_RadioSurvivorTestClothes')


def log(message: str) -> None:
    print(time.strftime('%H:%M:%S') + ' ' + message, flush=True)


# ---------------------------------------------------------------- pure helpers (tests/test_autoclient.py)

def selected_mods() -> list[tuple[str, Path]]:
    """MODS in load order (every requirement of RadioSurvivor, Signal Smoke included, is always copied)."""
    return list(MODS)


def missing_mod_sources(mods: list[tuple[str, Path]]) -> list[str]:
    """'<id> (<source>)' of each selected mod whose source folder is missing (e.g. a sister mod not found from a
    frozen copy without RS_WORKSHOP_DIR)."""
    return [f'{m} ({src})' for m, src in mods if not src.is_dir()]


def mods_txt(mod_ids: list[str]) -> str:
    """Contents of a mods.txt / default.txt (ActiveModsFile format)."""
    lines = ['VERSION = 1,', '', 'mods', '{']
    lines += [f'    mod = {m},' for m in mod_ids]
    lines += ['}', '', 'maps', '{', '}', '']
    return '\n'.join(lines)


def patch_options(text: str, values: dict[str, str] = WINDOW) -> str:
    """Sets key=value lines of options.ini (added when missing); other lines kept as they are."""
    out, seen = [], set()
    for line in text.splitlines():
        key = line.split('=', 1)[0]
        if '=' in line and key in values:
            out.append(f'{key}={values[key]}')
            seen.add(key)
        else:
            out.append(line)
    out += [f'{k}={v}' for k, v in values.items() if k not in seen]
    return '\n'.join(out) + '\n'


def command_text(token: str, save: str, mode: str, campaign: str | None, suites: list[str] | None,
                 start_delay: int, quit_game: bool, screenshot: bool, tags: str | None = None,
                 exclude: str | None = None) -> str:
    if (campaign is None) == (not suites):
        raise ValueError('exactly one of campaign and suites')
    if campaign and (tags is not None or exclude is not None):
        raise ValueError('tags and exclude go with suites only')
    if not re.fullmatch(r'[A-Za-z0-9]+', token):
        raise ValueError('token must be alphanumeric')
    lines = ['# Written by tools/autoclient/autoclient.py (E01-T14); read by RST_AutoClient.lua.',
             f'token={token}', f'save={save}', f'mode={mode}']
    lines.append(f'campaign={campaign}' if campaign else 'suite=' + ','.join(suites))
    if tags is not None:
        lines.append('tags=' + tags)
    if exclude is not None:
        lines.append('exclude=' + exclude)
    lines += [f'startDelaySec={start_delay}', f'quit={str(quit_game).lower()}',
              f'screenshot={str(screenshot).lower()}']
    return '\n'.join(lines) + '\n'


def last_state(status_text: str, token: str) -> tuple[str | None, str]:
    """Last (state, detail) written for this token in autoclient-status.txt."""
    state, detail = None, ''
    for line in status_text.splitlines():
        parts = line.split(' ', 2)
        if len(parts) >= 2 and parts[0] == token:
            state, detail = parts[1], parts[2] if len(parts) > 2 else ''
    return state, detail


RESPAWNED = 'respawn: new character'   # detail written by RST_AutoClient.lua once a dead MP client is back in game


def respawn_count(status_text: str, token: str) -> int:
    """Lines of this token whose detail says the client respawned with a new character (MP death, rs.death): each
    one needs godmode again (the new character is a new IsoPlayer, mortal)."""
    count = 0
    for line in status_text.splitlines():
        parts = line.split(' ', 2)
        if len(parts) == 3 and parts[0] == token and RESPAWNED in parts[2]:
            count += 1
    return count


def result_complete(text: str) -> bool:
    lines = text.splitlines()
    return len(lines) >= 2 and lines[0].startswith('RST-RESULT ') and lines[-1] == 'RST-END'


def result_code(first_line: str) -> int:
    if first_line.startswith('RST-RESULT ok=true '):
        return 0
    m = re.search(r' reason=(.*)$', first_line)
    if m and m.group(1) != 'no test selected':
        return 2
    return 1


def mp_command_text(token: str, connect: str, user: str, password: str, *, campaign: str | None = None,
                    suites: list[str] | None = None, tags: str | None = None, exclude: str | None = None,
                    server_campaign: str | None = None, server_suites: list[str] | None = None,
                    server_tags: str | None = None, server_exclude: str | None = None, start_delay: int = 5,
                    screenshot: bool = True, server_timeout: int = 3600, peer: bool = False,
                    server_runs: list[list[str]] | None = None) -> str:
    """autoclient.txt of a multiplayer client (RST_AutoClient.lua): connect=, control=true, optional client run
    (campaign or suites) and server run (server_campaign or server_suites); nothing to run = idle client; peer=True
    (idle only): result file of the steps answered, written on "quit" (E01-T16). server_runs (E01-T17): successive
    server runs of one phase, written as serverSuite=a,b;c (replaces server_suites)."""
    if campaign and suites:
        raise ValueError('at most one of campaign and suites')
    if server_runs is not None:
        if server_suites or server_campaign:
            raise ValueError('server_runs replaces server_suites and server_campaign')
        if not server_runs or any(not run for run in server_runs):
            raise ValueError('server_runs: every run needs at least one suite')
        if any(re.search(r'[,;\s]', name) or not name for run in server_runs for name in run):
            raise ValueError('server_runs: suite names without ",", ";" or spaces')
        server_suites = [';'.join(','.join(run) for run in server_runs)]
    if server_campaign and server_suites:
        raise ValueError('at most one of server_campaign and server_suites')
    if (tags is not None or exclude is not None) and not suites:
        raise ValueError('tags and exclude go with suites only')
    if (server_tags is not None or server_exclude is not None) and not server_suites:
        raise ValueError('server_tags and server_exclude go with server_suites only')
    if not re.fullmatch(r'[A-Za-z0-9]+', token):
        raise ValueError('token must be alphanumeric')
    if peer and (campaign or suites or server_campaign or server_suites):
        raise ValueError('peer goes with a client without run')
    if not re.fullmatch(r'[^:\s]+:\d+', connect):
        raise ValueError('connect must be host:port')
    for value in (user, password):
        if not re.fullmatch(r'[A-Za-z0-9_.-]*', value):
            raise ValueError('user and password: letters, digits, "_", "." and "-" only')
    lines = ['# Written by tools/autoclient/autoclient.py --mp (E01-T15); read by RST_AutoClient.lua.',
             f'token={token}', f'connect={connect}', f'user={user}', f'password={password}', 'control=true']
    if campaign:
        lines.append(f'campaign={campaign}')
    if suites:
        lines.append('suite=' + ','.join(suites))
    if tags is not None:
        lines.append('tags=' + tags)
    if exclude is not None:
        lines.append('exclude=' + exclude)
    if server_campaign:
        lines.append(f'serverCampaign={server_campaign}')
    if server_suites:
        lines.append('serverSuite=' + ','.join(server_suites))
    if server_tags is not None:
        lines.append('serverTags=' + server_tags)
    if server_exclude is not None:
        lines.append('serverExclude=' + server_exclude)
    if peer:
        lines.append('peer=true')
    lines += [f'startDelaySec={start_delay}', f'serverTimeoutSec={server_timeout}', 'quit=true',
              f'screenshot={str(screenshot).lower()}']
    return '\n'.join(lines) + '\n'


def mp_server_ini(mod_ids: list[str], port: int = MP_PORT, udp_port: int = MP_UDP_PORT, max_players: int = 4,
                  spawn: str = MP_SPAWN) -> str:
    """Server/<name>.ini of the test server: private, no Steam items, fixed spawn point (no spawn choice screen:
    MapSpawnSelect.getFixedSpawnRegion), PauseEmpty (the world waits while no client is connected),
    AntiCheatPermission=4 (Policy.Disabled): the second client is a -debug client set to the access level "user" for
    the rights suites (E01-T16); AntiCheatPower would reject its player packets ("invalid mode": debug flag without
    ConnectWithDebug) and kick it (AntiCheat.act no longer kicks once the server runs with -Ddebug, the option stays
    as a second guard). Packet capabilities (PacketTypes.PacketAuthorization) and the Lua checks (checkPermissions) do not depend on this option."""
    return '\n'.join([
        'Public=false', 'Open=true', 'UPnP=false', 'PauseEmpty=true', f'DefaultPort={port}', f'UDPPort={udp_port}',
        f'MaxPlayers={max_players}', 'Mods=' + ';'.join('\\' + m for m in mod_ids), 'WorkshopItems=',
        'Map=Muldraugh, KY', f'SpawnPoint={spawn}', 'ChatStreams=s,r,a,w,y,sh,f,all', 'SaveWorldEveryMinutes=0',
        'AntiCheatPermission=4', ''])


def server_java_command(game: Path, cache: Path, admin_user: str, admin_password: str, xmx: str = '3072m',
                        server_name: str = MP_SERVER_NAME) -> list[str]:
    """Dedicated server command (same Java options as tests/run_dedicated_smoke.ps1), test cache, no Steam, debug mode
    (-Ddebug: GameServer reads the Java property, not a -debug argument; Core.debug = isDebugEnabled(), E01-T18)."""
    return [str(game / 'jre64' / 'bin' / 'java.exe'), '-Djava.awt.headless=true', '-Dzomboid.steam=0',
            '--enable-native-access=ALL-UNNAMED', '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED',
            '-XX:+UseZGC', '-XX:-CreateCoredumpOnCrash', '-XX:-OmitStackTraceInFastThrow', f'-Xmx{xmx}', '-Ddebug',
            f'-XX:ErrorFile={cache / "java-error.log"}', '-Djava.library.path=./;./natives/win64/;./natives/',
            '-cp', './;projectzomboid.jar', 'zombie.network.GameServer', f'-cachedir={cache}', '-nosteam',
            '-ip', '127.0.0.1', '-servername', server_name, '-adminusername', admin_user,
            '-adminpassword', admin_password, '-disablelog=NetworkPacket']


def with_xmx(cmd: list[str], xmx: str) -> list[str]:
    """The command with its -Xmx replaced (or added before -cp)."""
    out = [a for a in cmd if not a.startswith('-Xmx')]
    out.insert(out.index('-cp') if '-cp' in out else 1, f'-Xmx{xmx}')
    return out


def account_commands(users: list[str], password: str) -> list[str]:
    """Server console lines making each extra account an admin (ConnectWithDebug, needed by a -debug client:
    ConnectToServerState.TestTCP)."""
    lines = []
    for user in users:
        lines += [f'adduser {user} {password}', f'setaccesslevel {user} admin']
    return lines


def server_ready(text: str) -> bool:
    return any(marker in text for marker in MP_READY)


def mp_code(results: list[tuple[str, str | None]]) -> tuple[int, str]:
    """Exit code of a multiplayer run from (role, first result line or None) per client: roles "run" and "peer" need a
    complete result (a peer: the steps it answered, E01-T16), role "idle" needs None (it only stays connected). Worst
    code wins; missing result = 2."""
    code, reasons = 0, []
    for i, (role, first) in enumerate(results, 1):
        if role == 'idle':
            continue
        if first is None:
            code = 2
            reasons.append(f'client {i}: no complete result' + (' of its steps' if role == 'peer' else ''))
            continue
        c = result_code(first)
        code = max(code, c)
        if c:
            reasons.append(f'client {i}: {first}')
    return code, '; '.join(reasons)


# ---------------------------------------------------------------- phases: reconnection and restart (E01-T17)

PHASES = ('reconnect', 'reconnect2', 'restart', 'modswap')
KEPT_BY = {'reconnect2': (1,)}  # client indices that stay connected during the action (E01-T17)
PHASE_SERVER_TAGS = 'server,shared,world'  # default server filter of a phased run (RST_Server: "client" excluded)
STAGE_BEFORE = 'before'


def stage_of(action: str) -> str:
    """Suffix of the suites checked after an action: reconnect -> after-reconnect, reconnect2 -> after-reconnect2
    (client 2 alone quits and joins again, client 1 stays connected), restart -> after-restart."""
    if action not in PHASES:
        raise ValueError(f'unknown phase {action!r} (expected {", ".join(PHASES)})')
    return 'after-' + action


def declared_suite_names(lua_dir: Path) -> set[str]:
    """Names of every RST.suite("name", ...) declared under the Lua folder of the development mod."""
    names = set()
    for path in lua_dir.rglob('*.lua'):
        names.update(re.findall(r'RST\.suite\(\s*"([^"]+)"', read_text(path)))
    return names


def phase_plan(bases: list[str], phases: list[str], declared: set[str]) -> list[list[list[str]]]:
    """Server runs of each step of a phased MP run: step 0 before the first action, step k after action k.

    Each base B (e.g. rs.identity) needs a suite B.before (snapshot of the state, opt-in "manual") and at least one
    B.after-<action> for the actions asked. Step 0 runs every B.before (those of the bases checked after reconnect2
    in a last, separate run: they move the requester away). Step k runs B.after-<action k> for the bases
    that define it, then, in a second run, B.before again for those bases when a later step checks them again (fresh
    snapshot just before the next action: e.g. the restart clock of rs.identity). Returns steps -> runs -> suites;
    a step without anything to check has no run (its clients only reconnect). ValueError on an unusable plan."""
    if not phases:
        raise ValueError('no phase asked')
    if 'modswap' in phases:
        # LK02-T12: the SAME suites before and after a restart with another mod list (no .before/.after-*).
        if phases != ['modswap']:
            raise ValueError('modswap goes alone (one restart with the clothes mod added)')
        if not bases:
            raise ValueError('no suite for the modswap phase')
        for base in bases:
            if base not in declared:
                raise ValueError(f'modswap: no suite {base}')
        return [[list(bases)], [list(bases)]]
    stages = [stage_of(a) for a in phases]
    if not bases:
        raise ValueError('no base suite for the phases')
    for base in bases:
        if base + '.' + STAGE_BEFORE not in declared:
            raise ValueError(f'{base}: no suite {base}.{STAGE_BEFORE}')
        if not any(f'{base}.{st}' in declared for st in stages):
            raise ValueError(f'{base}: none of ' + ', '.join(f'{base}.{st}' for st in stages))
    # A base checked after reconnect2 (B.after-reconnect2) keeps the requester away from its place until that check
    # (lk.rejoin.before sends client 1 far away): its B.before runs in a last, separate run, so that the other
    # snapshots of the same step are taken at the players' place (run 20261015-043927: lk.walls.before ran after
    # lk.rejoin.before, its wall was placed 100 squares north and never loaded again after the reconnection).
    away = stage_of('reconnect2')

    def befores(group: list[str]) -> list[list[str]]:
        near = [f'{b}.{STAGE_BEFORE}' for b in group if f'{b}.{away}' not in declared]
        far = [f'{b}.{STAGE_BEFORE}' for b in group if f'{b}.{away}' in declared]
        return [run for run in (near, far) if run]

    steps = [befores(bases)]
    for k, stage in enumerate(stages):
        checked = [b for b in bases if f'{b}.{stage}' in declared]
        later = set(stages[k + 1:])
        again = [b for b in checked if any(f'{b}.{st}' in declared for st in later)]
        runs = []
        if checked:
            runs.append([f'{b}.{stage}' for b in checked])
        runs.extend(befores(again))
        steps.append(runs)
    return steps


# Bases whose snapshot step needs a server line before the next action: rst.disconnect.before arms client 2, which
# asks its own run (rst.disconnect.slow) once the run in progress ends; the reconnect2 action must not make it quit
# before that run started (RST_Server.lua logs "[RST] run started by account '<name>'").
QUIT_WAITS = {'rst.disconnect.before': "run started by account '{user}'"}
QUIT_WAIT_S = 15.0


def quit_wait_line(runs: list[list[str]], action: str | None, users: list[str]) -> str | None:
    """Server log text to wait for before telling the leaving clients (users) to quit at the end of a step whose
    runs are runs and whose next action is action (reconnect2 only), or None."""
    if action != 'reconnect2' or not users:
        return None
    for name, line in QUIT_WAITS.items():
        if any(name in run for run in runs):
            return line.format(user=users[0])
    return None


def wait_server_text(path: Path, offset: int, text: str, timeout: float, poll: float = 0.5) -> bool:
    """True as soon as text appears in the server log after offset characters, False after timeout seconds."""
    deadline = time.monotonic() + timeout
    while True:
        if text in read_text(path)[offset:]:
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(poll)


def ini_with_mod(ini_text: str, mod_id: str) -> str:
    """Server ini with mod_id appended to its Mods= line (once)."""
    out = []
    for line in ini_text.split('\n'):
        if line.startswith('Mods='):
            ids = [m for m in line[5:].split(';') if m]
            if '\\' + mod_id not in ids:
                ids.append('\\' + mod_id)
            line = 'Mods=' + ';'.join(ids)
        out.append(line)
    return '\n'.join(out)


def add_mod_to_caches(server_cache: Path, client_caches: list[Path], mod_ids: list[str], extra: tuple[str, Path],
                      server_name: str = MP_SERVER_NAME) -> list[str]:
    """modswap: extra copied into the mods folder of the server and of every client cache, added to the Mods= of the
    server ini and to the default.txt of every client (MP checksum: same mods on both sides). Returns mod_ids + the
    new id."""
    mod_id = extra[0]
    ids = list(mod_ids) + ([mod_id] if mod_id not in mod_ids else [])
    for cache in [server_cache] + list(client_caches):
        if not (cache / 'mods' / mod_id).exists():
            copy_mods(cache / 'mods', [extra])
    ini = server_cache / 'Server' / f'{server_name}.ini'
    ini.write_bytes(ini_with_mod(read_text(ini), mod_id).encode('utf-8'))
    for cache in client_caches:
        (cache / 'mods' / 'default.txt').write_text(mods_txt(ids), encoding='utf-8')
    return ids


def launch_globals_lua(values: dict[str, int]) -> str:
    """Lua file setting the given globals (numbers only) in every Lua state of the run."""
    lines = ['-- Written by tools/autoclient/autoclient.py for this run only (never in the repository).']
    for name, value in sorted(values.items()):
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*', name) or not isinstance(value, int):
            raise ValueError(f'bad launch global {name}={value!r}')
        lines.append(f'{name} = {value}')
    return '\n'.join(lines) + '\n'


def write_launch_globals(caches: list[Path], text: str) -> None:
    """The launch globals file in the copy of the development mod of each cache (server and clients alike)."""
    for cache in caches:
        path = cache / 'mods' / LAUNCH_GLOBALS_FILE
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode('utf-8'))


def phase_token(token: str, index: int, step: int) -> str:
    """Token of client index for step (step 0 keeps the historical form <token>c<i>)."""
    return f'{token}c{index}' if step == 0 else f'{token}c{index}p{step}'


def kept_clients(action: str | None) -> tuple[int, ...]:
    """Indices of the clients that stay connected during action (reconnect2: client 1), () for every other action."""
    return KEPT_BY.get(action or '', ())


def admin_commands(users: list[str]) -> list[str]:
    """Server console lines giving the admin role back before a reconnection (a suite may have set an account to
    "user"; a -debug client needs ConnectWithDebug at each connection)."""
    return [f'setaccesslevel {user} admin' for user in users]


def archive_for_phase(cache: Path, step: int, files: list[Path], move: tuple[Path, ...] = ()) -> list[Path]:
    """Copies files of one step (console, process output, result) into the tests folder of the cache as
    p<step>-<name>.txt, collected with the reports at the end; files listed in move are removed afterwards (the
    result file: the next process of the same cache must start without one). Returns the archived paths."""
    tests = cache / TESTS_DIR
    tests.mkdir(parents=True, exist_ok=True)
    out = []
    for f in files:
        if not f.exists():
            continue
        name = f.name if f.suffix == '.txt' else f.name + '.txt'
        target = tests / f'p{step}-{name}'
        shutil.copy2(f, target)
        out.append(target)
        if f in move:
            f.unlink()
    return out


def free_memory_mb() -> int:
    """Available physical memory (Windows GlobalMemoryStatusEx), 0 when unknown."""
    class MEMORYSTATUSEX(ctypes.Structure):
        _fields_ = [('dwLength', ctypes.c_ulong), ('dwMemoryLoad', ctypes.c_ulong),
                    ('ullTotalPhys', ctypes.c_ulonglong), ('ullAvailPhys', ctypes.c_ulonglong),
                    ('ullTotalPageFile', ctypes.c_ulonglong), ('ullAvailPageFile', ctypes.c_ulonglong),
                    ('ullTotalVirtual', ctypes.c_ulonglong), ('ullAvailVirtual', ctypes.c_ulonglong),
                    ('ullAvailExtendedVirtual', ctypes.c_ulonglong)]
    try:
        stat = MEMORYSTATUSEX()
        stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
            return int(stat.ullAvailPhys // (1024 * 1024))
    except (AttributeError, OSError):
        pass
    return 0


def xmx_mb(xmx: str) -> int:
    m = re.fullmatch(r'(\d+)([mMgG])', xmx)
    if not m:
        raise ValueError(f'bad -Xmx value {xmx!r} (e.g. 3072m or 4g)')
    return int(m.group(1)) * (1024 if m.group(2).lower() == 'g' else 1)


def memory_need_mb(clients: int, client_xmx: str, server_xmx: str) -> tuple[int, int]:
    """(total -Xmx, estimated total use) in MB of an MP run: each JVM may grow to its -Xmx, plus its native part
    (CLIENT_NATIVE_MB, SERVER_NATIVE_MB). ValueError on a bad -Xmx."""
    heap = xmx_mb(client_xmx) * clients + xmx_mb(server_xmx)
    return heap, heap + CLIENT_NATIVE_MB * clients + SERVER_NATIVE_MB


def load_plan(declared_campaigns: set[str]) -> tuple[str | None, str | None, str | None]:
    """Server run of --load: (server_campaign, server_suite, server_tags). mp-load when RST_Campaign.lua declares it,
    else lk.load alone (tag "server": no test save needed)."""
    if LOAD_CAMPAIGN in declared_campaigns:
        return LOAD_CAMPAIGN, None, None
    return None, LOAD_SUITE, 'server'


def declared_campaigns(lua_text: str) -> set[str]:
    return set(re.findall(r'RST\.CAMPAIGNS\["([^"]+)"\]\s*=', lua_text))


def java_command(game: Path, cache: Path) -> list[str]:
    """java.exe command of ProjectZomboid64.json (no game file changed), Steam off, test cache."""
    conf = json.loads((game / 'ProjectZomboid64.json').read_text(encoding='utf-8'))
    vm = [a for a in conf.get('vmArgs', []) if not a.startswith('-Dzomboid.steam=')]
    windows = conf.get('windows', {})
    if windows:
        newest = max(windows, key=lambda v: tuple(int(x) for x in v.split('.')))
        vm = list(windows[newest].get('vmArgs', [])) + vm
    vm += ['-Dzomboid.steam=0', f'-XX:ErrorFile={cache / "java-error.log"}']
    cp = ';'.join(conf.get('classpath', ['.', 'projectzomboid.jar']))
    main = conf.get('mainClass', 'zombie/gameStates/MainScreenState').replace('/', '.')
    return [str(game / 'jre64' / 'bin' / 'java.exe')] + vm + ['-cp', cp, main,
                                                              f'-cachedir={cache}', '-debug', '-nosound', '-nosteam']


def latest_test_save(saves: Path) -> str | None:
    candidates = [p for p in saves.glob('rstest*') if p.is_dir() and (p / 'map_ver.bin').exists()]
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime).name


def campaign_suites(lua_text: str, name: str) -> list[str] | None:
    """Suite names of RST.CAMPAIGNS[name] in RST_Campaign.lua; "solo" = solo-lk + solo-rs; None if unknown."""
    if name == 'solo' and not re.search(r'RST\.CAMPAIGNS\["solo"\]', lua_text):
        parts = [campaign_suites(lua_text, n) for n in ('solo-lk', 'solo-rs')]
        return None if None in parts else parts[0] + parts[1]
    m = re.search(r'RST\.CAMPAIGNS\["' + re.escape(name) + r'"\]\s*=\s*\{(.*?)\n\}', lua_text, re.S)
    if not m:
        return None
    body = re.sub(r'--[^\n]*', '', m.group(1))
    return re.findall(r'"([^"]+)"', body)


def needs_bridge(campaign: str | None, suites: list[str] | None, lua_text: str = '') -> bool:
    """True when the selection may run a suite that needs the bridge (prefix selection both ways: "rs" selects
    rs.npctalk, "rs.radiomodule.world" belongs to rs.radiomodule). Unknown campaign: True (safe side)."""
    names = suites if suites else campaign_suites(lua_text, campaign or '')
    if names is None:
        return True

    def related(a: str, b: str) -> bool:
        return a == b or a.startswith(b + '.') or b.startswith(a + '.')
    return any(related(n, b) for n in names for b in BRIDGE_SUITES)


def bridge_command(python: str, script: Path, exchange: Path, offline: bool = False) -> list[str]:
    """Bridge on the exchange folder of the cache; its configuration file is left to the bridge (default path)."""
    cmd = [python, '-u', str(script), '--exchange', str(exchange)]
    return cmd + ['--offline'] if offline else cmd


def start_bridge(cmd: list[str], log_path: Path, cwd: Path | None = None,
                 env_extra: dict[str, str] | None = None) -> subprocess.Popen:
    """env_extra: variables set for the bridge only (--llm fake: OPENAI_* of the fake server; the bridge reads its
    environment before its .env file, radio_bridge.load_config)."""
    env = dict(os.environ, PYTHONIOENCODING='utf-8', PYTHONUNBUFFERED='1', **(env_extra or {}))
    with open(log_path, 'wb') as out:
        return subprocess.Popen(cmd, cwd=str(cwd) if cwd else None, stdout=out, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, env=env)


def wait_bridge_ready(proc, log_path: Path, timeout: float, poll: float = 0.25) -> tuple[bool, str]:
    """Waits for the "Bridge ready" line of the bridge journal; fails if the bridge exits or stays silent."""
    deadline = time.monotonic() + timeout
    while True:
        if BRIDGE_READY in read_text(log_path):
            return True, ''
        if proc.poll() is not None:
            return False, f'the bridge exited (code {proc.returncode}) before "{BRIDGE_READY}"'
        if time.monotonic() >= deadline:
            return False, f'no "{BRIDGE_READY}" from the bridge after {timeout:g} s'
        time.sleep(poll)


def stop_bridge(proc) -> None:
    """Stops the bridge started by this tool (its lock file is released by the system)."""
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        kill_tree(proc.pid)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            pass


def redact_secrets(text: str, extra: list[str] = ()) -> tuple[str, int]:
    """(text with credential-shaped strings replaced, number of replacements). extra: literal values to hide (the
    OPENAI_KEY of this process environment, when set); the .env file is never read."""
    count = 0
    for value in extra:
        if value and len(value) >= 8 and value in text:
            count += text.count(value)
            text = text.replace(value, '[REDACTED]')
    for pattern in SECRET_PATTERNS:
        text, n = re.subn(pattern, '[REDACTED]', text)
        count += n
    return text, count


# ---------------------------------------------------------------- parallel runs: slots, ports, shards

def pid_alive(pid: int) -> bool:
    """True while process pid runs (Windows OpenProcess + GetExitCodeProcess; elsewhere os.kill(pid, 0))."""
    if pid is None or pid <= 0:
        return False
    if os.name != 'nt':
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return False
    try:
        code = ctypes.c_ulong()
        if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
            return False
        return code.value == 259  # STILL_ACTIVE
    finally:
        kernel32.CloseHandle(handle)


class Slot:
    """One of the --max-parallel run slots: file <SLOTS_DIR>/slot-<i>.json holding the pid of the tool and the pids of
    the game and server processes it started. A slot whose tool pid is dead (run killed) is free again."""

    def __init__(self, index: int, path: Path):
        self.index, self.path, self.children = index, path, []

    def write(self) -> None:
        data = {'tool': os.getpid(), 'children': self.children, 'started': datetime.now().isoformat(timespec='seconds')}
        tmp = self.path.with_suffix('.tmp')
        tmp.write_text(json.dumps(data), encoding='utf-8')
        os.replace(tmp, self.path)

    def add_child(self, pid: int) -> None:
        self.children.append(int(pid))
        try:
            self.write()
        except OSError:
            pass

    def release(self) -> None:
        try:
            data = json.loads(self.path.read_text(encoding='utf-8'))
            if data.get('tool') == os.getpid():
                self.path.unlink()
        except (OSError, ValueError):
            pass


def read_slot(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def acquire_slot(max_parallel: int, slots_dir: Path) -> Slot | None:
    """First free slot among 0..max_parallel-1 (file created exclusively), a dead owner's slot taken back; None when
    all are held by live runs."""
    slots_dir.mkdir(parents=True, exist_ok=True)
    for i in range(max_parallel):
        path = slots_dir / f'slot-{i}.json'
        for _ in range(2):
            try:
                fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                data = read_slot(path)
                if data is None:
                    try:  # half-written by a run killed at that instant (older than a few seconds) or being written
                        if time.time() - path.stat().st_mtime < 10:
                            break
                    except OSError:
                        continue
                elif pid_alive(data.get('tool', -1)):
                    break
                try:
                    path.unlink()
                except OSError:
                    break
                continue
            os.close(fd)
            slot = Slot(i, path)
            slot.write()
            return slot
    return None


def tool_pids(slots_dir: Path) -> set[int]:
    """Pids of the game and server processes started by the live runs of this tool (slot files)."""
    pids = set()
    if slots_dir.is_dir():
        for path in slots_dir.glob('slot-*.json'):
            data = read_slot(path)
            if data and pid_alive(data.get('tool', -1)):
                pids.update(int(p) for p in data.get('children', []) if isinstance(p, int))
    return pids


CURRENT_SLOT: Slot | None = None


def register_child(pid: int) -> None:
    """A game or server process started by this run: recorded in its slot (not a foreign game for the other runs)."""
    if CURRENT_SLOT is not None:
        CURRENT_SLOT.add_child(pid)


def release_slot() -> None:
    global CURRENT_SLOT
    if CURRENT_SLOT is not None:
        CURRENT_SLOT.release()
        CURRENT_SLOT = None


def wait_for_slot(max_parallel: int, wait_idle: int, slots_dir: Path, poll: float = 10.0) -> tuple[Slot | None, str]:
    """Waits (up to wait_idle seconds) for a free slot and for no foreign game: a java.exe / ProjectZomboid64.exe that
    no live run of this tool started (the player's game or server) blocks; the processes of the other runs do not.
    Returns (slot, '') or (None, reason)."""
    global CURRENT_SLOT
    deadline = time.monotonic() + wait_idle
    slot = None
    while True:
        if slot is None:
            slot = acquire_slot(max_parallel, slots_dir)
        busy = busy_processes(tool_pids(slots_dir)) if slot is not None else []
        if slot is not None and not busy:
            CURRENT_SLOT = slot
            return slot, ''
        if time.monotonic() >= deadline:
            if slot is not None:
                slot.release()
            why = (f'game or server not started by this tool running: {", ".join(busy)} (never killed by this tool)'
                   if slot is not None else f'all {max_parallel} run slots taken ({slots_dir})')
            return None, why
        time.sleep(poll)


def port_free(port: int, host: str = '') -> bool:
    """True when both a TCP and a UDP socket can bind port (the server uses RakNet over UDP)."""
    import socket
    for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
        s = socket.socket(socket.AF_INET, kind)
        try:
            s.bind((host, port))
        except OSError:
            return False
        finally:
            s.close()
    return True


def mp_ports(slot_index: int, port_base: int | None = None, check=port_free, tries: int = 20) -> tuple[int, int]:
    """(DefaultPort, UDPPort) of the test server of a run: --port-base, else MP_PORT + PORT_STEP x slot, moved by
    PORT_STEP while one of the two is taken. ValueError when no free pair (or the explicit base is taken)."""
    base = port_base if port_base is not None else MP_PORT + PORT_STEP * slot_index
    for k in range(1 if port_base is not None else tries):
        port = base + PORT_STEP * k
        if check(port) and check(port + 1):
            return port, port + 1
    raise ValueError(f'no free port pair from {base} (another server running?)')


def free_tcp_port() -> int:
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def parse_shard(text: str) -> tuple[int, int]:
    m = re.fullmatch(r'\s*(\d+)\s*/\s*(\d+)\s*', text or '')
    if not m or not 1 <= int(m.group(1)) <= int(m.group(2)):
        raise ValueError(f'--shard K/N with 1 <= K <= N (got {text!r})')
    return int(m.group(1)), int(m.group(2))


def report_durations(runs: Path) -> dict[str, int]:
    """Duration (ms) of each suite in the RST reports of earlier runs (runs/*/server|client*/*.txt, lines
    "<STATUS> <suite> :: <test> (<ms> ms)"), the most recent report of a suite wins."""
    found: dict[str, tuple[float, int]] = {}
    if not runs.is_dir():
        return {}
    for path in runs.glob('*/*/*.txt'):
        try:
            if path.stat().st_size > 2_000_000:
                continue
            text = path.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        if not text.startswith('RST report'):
            continue
        mtime = path.stat().st_mtime
        per: dict[str, int] = {}
        for m in re.finditer(r'(?m)^(?:PASS|FAIL|ERROR|SKIP)\s+(\S+) :: .*\((\d+) ms\)\s*$', text):
            per[m.group(1)] = per.get(m.group(1), 0) + int(m.group(2))
        for suite, ms in per.items():
            if suite not in found or found[suite][0] < mtime:
                found[suite] = (mtime, ms)
    return {s: ms for s, (_, ms) in found.items()}


def entry_duration(entry: str, durations: dict[str, int]) -> int | None:
    """Known duration of a campaign entry: its suite and the suites "<entry>.*" (prefix selection)."""
    hits = [ms for s, ms in durations.items() if s == entry or s.startswith(entry + '.')]
    return sum(hits) if hits else None


def shard_entries(entries: list[str], k: int, n: int, durations: dict[str, int] | None = None) -> list[str]:
    """Entries of shard k (1-based) of n, in the campaign order. With known durations (earlier reports): longest first
    to the least loaded shard (unknown entries count as the median, ties by name); without: round-robin over the
    names sorted. Deterministic for the same entries and durations."""
    if not 1 <= k <= n:
        raise ValueError('shard out of range')
    known = {e: entry_duration(e, durations or {}) for e in entries}
    values = sorted(v for v in known.values() if v is not None)
    owner: dict[str, int] = {}
    if values:
        median = values[len(values) // 2]
        cost = {e: (v if v is not None else median) for e, v in known.items()}
        load = [0] * n
        for e in sorted(entries, key=lambda e: (-cost[e], e)):
            i = min(range(n), key=lambda j: (load[j], j))
            owner[e] = i
            load[i] += cost[e]
    else:
        for i, e in enumerate(sorted(entries)):
            owner[e] = i % n
    return [e for e in entries if owner[e] == k - 1]


def start_fake_llm(script: Path, port: int, log_path: Path) -> subprocess.Popen:
    env = dict(os.environ, PYTHONIOENCODING='utf-8', PYTHONUNBUFFERED='1')
    with open(log_path, 'wb') as out:
        return subprocess.Popen([sys.executable, '-u', str(script), '--port', str(port)], stdout=out,
                                stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=env)


def wait_fake_llm(proc, log_path: Path, port: int, timeout: float, poll: float = 0.2) -> tuple[bool, str]:
    marker = f'{FAKE_LLM_READY} port={port}'
    deadline = time.monotonic() + timeout
    while True:
        if marker in read_text(log_path):
            return True, ''
        if proc.poll() is not None:
            return False, f'the fake LLM exited (code {proc.returncode}) before "{marker}"'
        if time.monotonic() >= deadline:
            return False, f'no "{marker}" from the fake LLM after {timeout:g} s'
        time.sleep(poll)


def fake_llm_env(port: int) -> dict[str, str]:
    """Bridge configuration of --llm fake (environment variables win over the bridge .env, never read here)."""
    return {'OPENAI_BASE_URL': f'http://127.0.0.1:{port}/v1', 'OPENAI_MODEL': 'fake', 'OPENAI_KEY': 'fake'}


class LLMService:
    """--llm fake: the local deterministic OpenAI-compatible server (tools/fake_llm/fake_llm.py) for the bridge of one
    run, on a free port, stopped at the end; its journal goes to the run folder (fake_llm.log)."""

    def __init__(self, mode: str, cache: Path):
        self.mode, self.proc, self.port = mode, None, None
        self.log_path = cache / 'fake_llm.log'

    def start(self, timeout: float) -> dict[str, str]:
        """Bridge environment ({} for --llm real). RuntimeError when the fake server does not start."""
        if self.mode != 'fake':
            return {}
        if not FAKE_LLM_SCRIPT.exists():
            raise RuntimeError(f'--llm fake: {FAKE_LLM_SCRIPT} not found')
        self.port = free_tcp_port()
        self.proc = start_fake_llm(FAKE_LLM_SCRIPT, self.port, self.log_path)
        ok, why = wait_fake_llm(self.proc, self.log_path, self.port, timeout)
        if not ok:
            raise RuntimeError(why)
        log(f'fake LLM ready (pid {self.proc.pid}, port {self.port})')
        return fake_llm_env(self.port)

    def stop(self, out: Path | None = None) -> None:
        stop_bridge(self.proc)
        if self.proc is not None:
            log(f'fake LLM stopped (code {self.proc.returncode})')
        if out is not None and self.log_path.exists():
            out.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.log_path, out / 'fake_llm.log')


# ---------------------------------------------------------------- Windows: processes and window clicks

def game_processes() -> list[tuple[str, int]]:
    """(image name, pid) of every running java.exe / ProjectZomboid64.exe."""
    out = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True, text=True, errors='replace').stdout
    found = []
    for line in out.splitlines():
        cells = [c.strip('"') for c in line.split('","')]
        if cells and cells[0].lower() in BUSY_NAMES:
            try:
                found.append((cells[0], int(cells[1])))
            except (IndexError, ValueError):
                found.append((cells[0], -1))
    return found


def busy_processes(exclude: set[int] = frozenset()) -> list[str]:
    """Game or server processes NOT started by a run of this tool (exclude: their pids, from the slot files)."""
    return [f'{name} (pid {pid})' for name, pid in game_processes() if pid not in exclude]


def find_window(pid: int) -> int | None:
    """Visible top-level window of the process (the game window), or None."""
    user32 = ctypes.windll.user32
    found = []
    proto = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

    def callback(hwnd, _):
        owner = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(ctypes.c_void_p(hwnd), ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(ctypes.c_void_p(hwnd)):
            found.append(hwnd)
        return True

    user32.EnumWindows(proto(callback), 0)
    return found[0] if found else None


def post_click(hwnd: int) -> None:
    """Left button down then up at the centre of the client area, posted to the window (no focus, no cursor move)."""
    user32 = ctypes.windll.user32

    class RECT(ctypes.Structure):
        _fields_ = [('left', ctypes.c_long), ('top', ctypes.c_long), ('right', ctypes.c_long), ('bottom', ctypes.c_long)]

    rect = RECT()
    user32.GetClientRect(ctypes.c_void_p(hwnd), ctypes.byref(rect))
    x, y = rect.right // 2, rect.bottom // 2
    lparam = (y << 16) | (x & 0xFFFF)
    user32.PostMessageW(ctypes.c_void_p(hwnd), 0x0201, 0x0001, lparam)  # WM_LBUTTONDOWN, MK_LBUTTON
    time.sleep(0.4)
    user32.PostMessageW(ctypes.c_void_p(hwnd), 0x0202, 0, lparam)  # WM_LBUTTONUP


def kill_tree(pid: int) -> None:
    subprocess.run(['taskkill', '/PID', str(pid), '/T', '/F'], capture_output=True)


# ---------------------------------------------------------------- cache

def build_cache(cache: Path, save: str, mode: str, command: str, mods: list[tuple[str, Path]] = MODS) -> None:
    source_save = ZOMBOID / 'Saves' / mode / save
    if not (source_save / 'map_ver.bin').exists():
        raise SystemExit(f'ERROR: save not found: {source_save}')
    target_save = cache / 'Saves' / mode / save
    shutil.copytree(source_save, target_save)
    ids = [m for m, _ in mods]
    (target_save / 'mods.txt').write_text(mods_txt(ids), encoding='utf-8')
    build_client_files(cache, command, mods)


def copy_mods(mods_dir: Path, mods: list[tuple[str, Path]] = MODS) -> None:
    mods_dir.mkdir(parents=True, exist_ok=True)
    for mod_id, src in mods:
        if not src.is_dir():
            raise SystemExit(f'ERROR: mod {mod_id} not found: {src}')
        shutil.copytree(src, mods_dir / mod_id, ignore=IGNORE)


def build_client_files(cache: Path, command: str, mods: list[tuple[str, Path]] = MODS) -> None:
    """Mods, default.txt, reset marker, windowed options.ini and the command of a client cache (solo or MP)."""
    ids = [m for m, _ in mods]
    mods_dir = cache / 'mods'
    copy_mods(mods_dir, mods)
    (mods_dir / 'default.txt').write_text(mods_txt(ids), encoding='utf-8')
    # Without this marker a new cache folder gets an empty default.txt at startup
    # (GameWindow.java:986 -> ZomboidFileSystem.resetDefaultModsForNewRelease("42_00")): no mod at the main menu.
    (mods_dir / 'reset-mods-42_00.txt').write_text(RESET_MARKER, encoding='utf-8')
    options = ZOMBOID / 'options.ini'
    text = options.read_text(encoding='utf-8', errors='replace') if options.exists() else ''
    (cache / 'options.ini').write_text(patch_options(text), encoding='utf-8')
    tests = cache / TESTS_DIR
    tests.mkdir(parents=True, exist_ok=True)
    (tests / 'autoclient.txt').write_bytes(command.encode('utf-8'))  # no BOM: getFileReader keeps it


def mp_server_sandbox(ambient_zombies: bool = False, group_count: int | None = None) -> str | None:
    """Server/<name>_SandboxVars.lua of the test server, or None for the vanilla defaults. Without ambient zombies:
    ZombieConfig.PopulationStartMultiplier and PopulationPeakMultiplier at 0 (target population of the native
    population manager, ZombiePopulationManager.onConfigReloaded), the Living Knox suites need a calm site as the solo
    test saves give, and the fresh Muldraugh spawn kept every test group alerted and defending (campaign of
    2026-10-14). Not Zombies = 6 ("None"): IsoWorld.getZombiesDisabled() then refuses addZombiesInOutfit outside debug
    ("Cannot spawn."), so no npc body nor test zombie; PopulationMultiplier is kept (zombie density of the missions,
    RS_MissionClear). Only the options written here change; SandboxOptions.readLuaFile keeps the others.
    group_count (LK13-T02, --group-count, --load): option LivingKnox.GroupCount (3..5) of the NEW test world, in the
    table LivingKnox (the part of the option name before the dot: IntegerSandboxOption.fromTable)."""
    if group_count is not None and not 3 <= group_count <= 5:
        raise ValueError(f'LivingKnox.GroupCount is 3..5 (got {group_count})')
    if ambient_zombies and group_count is None:
        return None
    parts, what = [], []
    if not ambient_zombies:
        parts.append('    ZombieConfig = {\n        PopulationStartMultiplier = 0.0,\n'
                     '        PopulationPeakMultiplier = 0.0,\n    },\n')
        what.append('no ambient zombie')
    if group_count is not None:
        parts.append(f'    LivingKnox = {{\n        GroupCount = {group_count},\n    }},\n')
        what.append(f'{group_count} Living Knox groups')
    return (f'-- Written by tools/autoclient/autoclient.py --mp: {", ".join(what)} (see mp_server_sandbox).\n'
            'SandboxVars = {\n    VERSION = 6,\n' + ''.join(parts) + '}\n')


def build_server_cache(cache: Path, ini_text: str, server_name: str = MP_SERVER_NAME,
                       sandbox_text: str | None = None, mods: list[tuple[str, Path]] = MODS) -> None:
    copy_mods(cache / 'mods', mods)
    (cache / 'Server').mkdir(parents=True, exist_ok=True)
    (cache / 'Server' / f'{server_name}.ini').write_bytes(ini_text.encode('utf-8'))
    if sandbox_text is not None:
        (cache / 'Server' / f'{server_name}_SandboxVars.lua').write_bytes(sandbox_text.encode('utf-8'))


def collect(cache: Path, out: Path, stdout_log: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    tests = cache / TESTS_DIR
    if tests.is_dir():
        for f in tests.glob('*.txt'):
            shutil.copy2(f, out / f.name)
    shots = cache / 'Screenshots'
    if shots.is_dir():
        for f in shots.glob('*.png'):
            shutil.copy2(f, out / f.name)
    for f in (cache / 'console.txt', stdout_log, cache / 'java-error.log', cache / EXCHANGE_DIR / 'token_usage.jsonl'):
        if f.exists():
            shutil.copy2(f, out / f.name)


def store_bridge_log(source: Path, out: Path) -> int:
    """Copies the bridge journal to the run folder with credential-shaped strings redacted; returns their count."""
    if not source.exists():
        return 0
    out.mkdir(parents=True, exist_ok=True)
    text, found = redact_secrets(read_text(source), [os.environ.get('OPENAI_KEY', '')])
    (out / 'bridge.log').write_text(text, encoding='utf-8')
    return found


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return ''


# ---------------------------------------------------------------- main

def main(argv=None) -> int:
    try:
        return _main(argv)
    finally:
        release_slot()


def _main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    what = p.add_mutually_exclusive_group()
    what.add_argument('--campaign', help='RST.campaign(name), e.g. solo-rs')
    what.add_argument('--suite', help='RST.run({ suite = {...} }): comma-separated suite names or prefixes')
    p.add_argument('--tags', help='with --suite: explicit RST filter tags, e.g. world (replaces the default '
                                  'exclusion of server and world suites)')
    p.add_argument('--exclude', help='with --suite: explicit RST exclusion list ("" = none)')
    p.add_argument('--save', help='test save name rstest* (default: the most recent Saves/Sandbox/rstest*)')
    p.add_argument('--mode', default='Sandbox')
    p.add_argument('--timeout', type=int, default=None,
                   help=f'seconds from launch to the result (default {DEFAULT_TIMEOUT}, {LOAD_TIMEOUT} with --load)')
    p.add_argument('--menu-timeout', type=int, default=300,
                   help='seconds for the Lua driver to report the main menu (default 300)')
    p.add_argument('--quit-timeout', type=int, default=120, help='seconds for the game to exit after the result')
    p.add_argument('--wait-idle', type=int, default=0, help='seconds to wait for java.exe/ProjectZomboid64 to end')
    p.add_argument('--start-delay', type=int, default=5, help='seconds in game before the run (default 5)')
    p.add_argument('--no-quit', action='store_true', help='leave the game open at the end (no forced stop)')
    p.add_argument('--no-screenshot', action='store_true')
    p.add_argument('--keep-cache', action='store_true', help='keep the temporary cache even on success')
    p.add_argument('--out', type=Path, help='result folder (default tools/autoclient/runs/<date>-<token>)')
    p.add_argument('--dry-run', action='store_true', help='build the cache and print the command, launch nothing')
    p.add_argument('--bridge', choices=('auto', 'on', 'off', 'offline'), default='auto',
                   help='Python bridge on the cache exchange folder: auto = on when a selected suite needs it '
                        f'({", ".join(BRIDGE_SUITES)}); offline = echo answers, no model (default auto)')
    p.add_argument('--bridge-timeout', type=int, default=60, help='seconds for the bridge to be ready (default 60)')
    par = p.add_argument_group('parallel runs and fake model')
    par.add_argument('--max-parallel', type=int, default=DEFAULT_MAX_PARALLEL,
                     help=f'run slots shared by the launches of this tool (default {DEFAULT_MAX_PARALLEL}): a launch '
                          'waits (--wait-idle) for a free slot; the game processes of the other launches never block '
                          'it, a game or server not started by this tool does')
    par.add_argument('--shard', help='K/N: run only shard K of N of --campaign / --server-campaign (entries split '
                                     'by the durations of earlier reports, else round-robin by name; '
                                     'not with --phases)')
    par.add_argument('--llm', choices=('real', 'fake'), default='real',
                     help='model of the bridge: real (its own configuration) or fake (tools/fake_llm/fake_llm.py on a '
                          'free port, OPENAI_BASE_URL/OPENAI_MODEL/OPENAI_KEY given to the bridge; default real)')
    mp = p.add_argument_group('multiplayer (E01-T15)')
    mp.add_argument('--mp', action='store_true', help='dedicated test server + automatic clients')
    mp.add_argument('--clients', type=int, choices=range(1, MAX_CLIENTS + 1), default=None,
                    help=f'number of clients, 1..{MAX_CLIENTS} (default 1, {LOAD_CLIENTS} with --load); client 1 runs, '
                         'the others are "peer" clients answering the steps of the server suites')
    mp.add_argument('--group-count', type=int, choices=(3, 4, 5),
                    help='sandbox option LivingKnox.GroupCount of the new test world (default: the mod default, '
                         f'{LOAD_GROUPS} with --load)')
    mp.add_argument('--load', action='store_true',
                    help=f'LK13-T02 load campaign: {LOAD_CLIENTS} clients, {LOAD_GROUPS} groups, server campaign '
                         f'{LOAD_CAMPAIGN} when RST_Campaign.lua declares it, else --server-suite {LOAD_SUITE} '
                         '--server-tags server (explicit --clients/--group-count/--server-* options win)')
    srv = mp.add_mutually_exclusive_group()
    srv.add_argument('--server-suite', help='client 1 asks RST.server({ suite = {...} }) (comma-separated)')
    srv.add_argument('--server-campaign', help='client 1 asks RST.server with the suites of RST.CAMPAIGNS[name], '
                                               'manual suites excluded (e.g. mp)')
    mp.add_argument('--server-tags', help='with --server-suite: explicit server filter tags, e.g. world')
    mp.add_argument('--server-exclude', help='with --server-suite: explicit server exclusion ("" = none)')
    mp.add_argument('--port-base', type=int,
                    help=f'DefaultPort of the test server (UDPPort = +1); default {MP_PORT} + {PORT_STEP} x run slot, '
                         'moved while taken')
    mp.add_argument('--server-timeout', type=int, default=300, help='seconds for the server to listen (default 300)')
    mp.add_argument('--no-godmode', dest='godmode', action='store_false',
                    help='leave the test players mortal (default: "godmodeplayer <account> -true" on the server '
                         'console once each client is in game: ambient zombies otherwise kill the idle players and '
                         'every later suite fails)')
    mp.add_argument('--ambient-zombies', action='store_true',
                    help='keep the vanilla zombie population of the test server (default: start and peak population '
                         'multipliers at 0, a calm site like the solo test saves; the suites create their own zombies)')
    mp.add_argument('--phases', help='E01-T17: comma-separated actions between steps, "reconnect" (every client '
                                     'quits then joins again), "reconnect2" (client 2 alone quits and joins again, '
                                     'client 1 stays connected) and/or "restart" (clients quit, "quit" on the server '
                                     'console, server launched again on the same cache, clients join again); '
                                     '--server-suite/--server-campaign then name BASES B run as B.before, '
                                     'B.after-reconnect, B.after-reconnect2, B.after-restart (e.g. --server-campaign '
                                     'mp-persist); "modswap" alone (LK02-T12): the same suites before and after a '
                                     'restart with batman_RadioSurvivorTestClothes added to the mods of the server and '
                                     'clients (e.g. --server-suite lk.appearance)')
    mp.add_argument('--restart-pause', type=int, default=120,
                    help='with --phases restart: seconds the server stays down before its relaunch (default 120: rs.identity checks that a mission clock does not run while the server is down, margin RESTART_MARGIN_MS = 120 s)')
    mp.add_argument('--load-phase-ms', type=int,
                    help=f'lk.loadmp phase length in ms (>= {LOAD_PHASE_MIN_MS}; default of the suite 300000): Lua '
                         f'global {LOAD_PHASE_GLOBAL} written into the caches of the run')
    mp.add_argument('--client-xmx', default='4096m', help='-Xmx of each client (default 4096m)')
    mp.add_argument('--server-xmx', default='3072m', help='-Xmx of the server (default 3072m)')
    args = p.parse_args(argv)
    if args.timeout is None:
        args.timeout = LOAD_TIMEOUT if args.load else DEFAULT_TIMEOUT
    if args.load_phase_ms is not None and not args.mp:
        log('ERROR: --load-phase-ms goes with --mp only')
        return 2

    if args.mp:
        return main_mp(args)
    if args.load or args.clients is not None or args.group_count is not None:
        log('ERROR: --load, --clients and --group-count go with --mp only')
        return 2
    if not args.campaign and not args.suite:
        log('ERROR: --campaign or --suite is needed (or --mp)')
        return 2
    save = args.save or latest_test_save(ZOMBOID / 'Saves' / args.mode)
    if not save or not save.lower().startswith('rstest'):
        log(f'ERROR: a test save rstest* is needed (got {save!r})')
        return 2
    suites = [s.strip() for s in args.suite.split(',') if s.strip()] if args.suite else None
    token = secrets.token_hex(6)
    if args.campaign and (args.tags is not None or args.exclude is not None):
        log('ERROR: --tags and --exclude go with --suite only')
        return 2
    if args.shard:
        error = apply_shard(args, read_text(CAMPAIGN_FILE))
        if error:
            log('ERROR: ' + error)
            return 2
        suites = [s.strip() for s in args.suite.split(',') if s.strip()]
    command = command_text(token, save, args.mode, args.campaign, suites, args.start_delay,
                           not args.no_quit, not args.no_screenshot, args.tags, args.exclude)

    if not args.dry_run:
        slot, why = wait_for_slot(args.max_parallel, args.wait_idle, SLOTS_DIR)
        if slot is None:
            log('ERROR: ' + why)
            return 3
        log(f'run slot {slot.index} of {args.max_parallel}')

    cache = Path(tempfile.mkdtemp(prefix='rs-autoclient-'))
    out = args.out or RUNS / f'{datetime.now().strftime("%Y%m%d-%H%M%S")}-{token}'
    log(f'RS_AUTOCLIENT_CACHE={cache}')
    log(f'save {args.mode}/{save}, ' + (f'campaign {args.campaign}' if args.campaign else 'suites ' + ','.join(suites)))
    mods = selected_mods()
    log('mods: ' + ', '.join(m for m, _ in mods))
    missing = missing_mod_sources(mods)
    if missing:
        log('ERROR: mod source folder(s) missing: ' + ', '.join(missing) + ' (RS_WORKSHOP_DIR from a frozen copy)')
        return 2
    build_cache(cache, save, args.mode, command, mods)
    cmd = java_command(GAME, cache)
    use_bridge = args.bridge in ('on', 'offline') or (args.bridge == 'auto' and needs_bridge(
        args.campaign, suites, read_text(CAMPAIGN_FILE) if args.campaign else ''))
    bcmd = bridge_command(sys.executable, BRIDGE_SCRIPT, cache / EXCHANGE_DIR, args.bridge == 'offline') \
        if use_bridge else None
    if args.dry_run:
        log('dry run, command: ' + subprocess.list2cmdline(cmd))
        log('dry run, bridge: ' + (subprocess.list2cmdline(bcmd) if bcmd else 'not started'))
        return 0

    tests = cache / TESTS_DIR
    status_file, result_file = tests / 'autoclient-status.txt', tests / 'autoclient-result.txt'
    stdout_log, bridge_log = cache / 'client-stdout.log', cache / 'bridge.log'
    started = time.monotonic()
    code, reason = 2, ''
    bridge = None
    llm = LLMService(args.llm if bcmd and args.bridge != 'offline' else 'real', cache)
    try:
        if bcmd:
            try:
                env = llm.start(args.bridge_timeout)
            except RuntimeError as e:
                llm.stop(out)
                return finish(cache, out, stdout_log, None, bridge_log, 2, f'{e}: game not started', started, args)
            bridge = start_bridge(bcmd, bridge_log, BRIDGE_SCRIPT.parent, env)
            ok, why = wait_bridge_ready(bridge, bridge_log, args.bridge_timeout)
            if not ok:
                reason = why + ' (journal bridge.log in the run folder): game not started'
                stop_bridge(bridge)
                llm.stop(out)
                return finish(cache, out, stdout_log, bridge, bridge_log, 2, reason, started, args)
            log(f'bridge ready (pid {bridge.pid}{", offline" if args.bridge == "offline" else ""}), '
                f'exchange {cache / EXCHANGE_DIR}')
        else:
            log('bridge not started (--bridge ' + args.bridge + ')')
        code, reason = run_client(cmd, stdout_log, status_file, result_file, token, bridge, started, args)
    finally:
        stop_bridge(bridge)  # also on an unexpected error; finish() below stops it first in the normal path
        llm.stop(out)
    return finish(cache, out, stdout_log, bridge, bridge_log, code, reason, started, args)


def finish(cache: Path, out: Path, stdout_log: Path, bridge, bridge_log: Path, code: int, reason: str,
           started: float, args) -> int:
    stop_bridge(bridge)
    if bridge is not None:
        log(f'bridge stopped (code {bridge.returncode})')
    if reason:
        log('ERROR: ' + reason)
    collect(cache, out, stdout_log)
    found = store_bridge_log(bridge_log, out)
    if found:
        log(f'ERROR: {found} credential-shaped string(s) redacted from bridge.log')
        code = 2
    log(f'results copied to {out}')
    if code == 0 and not args.keep_cache and not args.no_quit:
        shutil.rmtree(cache, ignore_errors=True)
        log('temporary cache removed')
    else:
        log(f'temporary cache kept: {cache}')
    log(f'RS_AUTOCLIENT_EXIT={code} ({int(time.monotonic() - started)} s)')
    return code


def run_client(cmd, stdout_log: Path, status_file: Path, result_file: Path, token: str, bridge, started: float,
               args) -> tuple[int, str]:
    code, reason = 2, ''
    with open(stdout_log, 'wb') as so:
        proc = subprocess.Popen(cmd, cwd=GAME, stdout=so, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    register_child(proc.pid)
    log(f'client started (pid {proc.pid}), timeout {args.timeout} s')
    last_seen, clicks, next_click, quit_deadline, bridge_warned = None, 0, 0.0, None, False
    try:
        while True:
            now = time.monotonic()
            state, detail = last_state(read_text(status_file), token)
            if state != last_seen:
                log(f'state {state}: {detail}')
                last_seen = state
            if bridge is not None and not bridge_warned and bridge.poll() is not None:
                log(f'WARNING: the bridge exited during the run (code {bridge.returncode}); see bridge.log')
                bridge_warned = True
            if state == 'load' and now >= next_click:
                hwnd = find_window(proc.pid)
                if hwnd:
                    post_click(hwnd)
                    clicks += 1
                next_click = now + 3.0
            result = read_text(result_file)
            if result_complete(result) and quit_deadline is None:
                first = result.splitlines()[0]
                log(first)
                code = result_code(first)
                if args.no_quit:
                    break
                quit_deadline = now + args.quit_timeout
            if proc.poll() is not None:
                log(f'client exited (code {proc.returncode}) after {int(now - started)} s, {clicks} click(s) posted')
                if quit_deadline is None:
                    reason = 'the client stopped without a complete autoclient-result.txt'
                    code = 2
                break
            if quit_deadline is not None and now >= quit_deadline:
                reason = f'client still running {args.quit_timeout} s after the result: killed'
                kill_tree(proc.pid)
                if code == 0:
                    code = 2
                break
            if state is None and now - started >= args.menu_timeout:
                reason = f'no status from the Lua driver after {args.menu_timeout} s (mods not loaded at the menu?): killed'
                kill_tree(proc.pid)
                code = 2
                break
            if quit_deadline is None and now - started >= args.timeout:
                reason = f'no complete result after {args.timeout} s (last state {state}): killed'
                kill_tree(proc.pid)
                code = 2
                break
            time.sleep(1.0)
    finally:
        if proc.poll() is None and not args.no_quit:
            kill_tree(proc.pid)
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            pass
    return code, reason


# ---------------------------------------------------------------- multiplayer (E01-T15)

class MPClient:
    """One automatic client of a multiplayer run (its own cache, account, command and process)."""

    def __init__(self, index: int, cache: Path, token: str, user: str, role: str):
        self.index, self.cache, self.token, self.user, self.role = index, cache, token, user, role
        tests = cache / TESTS_DIR
        self.status_file, self.result_file = tests / 'autoclient-status.txt', tests / 'autoclient-result.txt'
        self.control_file = tests / 'autoclient-control.txt'
        self.stdout_log = cache / 'client-stdout.log'
        self.proc = None
        self.state, self.detail, self.clicks, self.next_click = None, '', 0, 0.0
        self.godmode_sent = False
        self.respawns = 0   # respawns of this token already given godmode again

    def name(self) -> str:
        return f'client {self.index} ({self.user})'

    def start(self, cmd: list[str]) -> None:
        with open(self.stdout_log, 'wb') as so:
            self.proc = subprocess.Popen(cmd, cwd=GAME, stdout=so, stderr=subprocess.STDOUT,
                                         stdin=subprocess.DEVNULL)
        register_child(self.proc.pid)
        log(f'{self.name()} started (pid {self.proc.pid})')

    def poll_state(self) -> None:
        state, detail = last_state(read_text(self.status_file), self.token)
        if state != self.state or (detail != self.detail and detail.startswith('respawn: ')):
            log(f'{self.name()} state {state}: {detail}')
        self.state, self.detail = state, detail

    def new_respawns(self) -> int:
        """Respawns written since the last call (status lines 'respawn: new character ...' of the current token)."""
        total = respawn_count(read_text(self.status_file), self.token)
        fresh, self.respawns = max(0, total - self.respawns), max(total, self.respawns)
        return fresh

    def click_if_loading(self, now: float) -> None:
        if self.state == 'load' and self.proc is not None and now >= self.next_click:
            hwnd = find_window(self.proc.pid)
            if hwnd:
                post_click(hwnd)
                self.clicks += 1
            self.next_click = now + 3.0

    def control(self, words: list[str]) -> None:
        self.control_file.parent.mkdir(parents=True, exist_ok=True)
        self.control_file.write_bytes(('\n'.join(words) + '\n').encode('utf-8'))

    def result_first(self) -> str | None:
        text = read_text(self.result_file)
        return text.splitlines()[0] if result_complete(text) else None

    def running(self) -> bool:
        return self.proc is not None and self.proc.poll() is None


def send_console(proc, line: str) -> bool:
    """One line on the server console (stdin pipe, UTF-8 without BOM)."""
    try:
        proc.stdin.write((line + '\n').encode('utf-8'))
        proc.stdin.flush()
        return True
    except (OSError, ValueError):
        return False


def stop_server(proc, timeout: int) -> str:
    if proc is None or proc.poll() is not None:
        return 'server already stopped'
    if not send_console(proc, 'quit'):
        kill_tree(proc.pid)
        return 'server stdin closed: killed'
    try:
        proc.wait(timeout=timeout)
        return f'server stopped (code {proc.returncode})'
    except subprocess.TimeoutExpired:
        kill_tree(proc.pid)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            pass
        return f'server still running {timeout} s after "quit": killed'


def collect_server(cache: Path, out: Path, stdout_log: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    tests = cache / TESTS_DIR
    if tests.is_dir():
        for f in tests.glob('*.txt'):
            shutil.copy2(f, out / f.name)
    for f in (stdout_log, cache / 'server-console.txt', cache / 'java-error.log',
              cache / EXCHANGE_DIR / 'token_usage.jsonl'):
        if f.exists():
            shutil.copy2(f, out / f.name)
    logs = cache / 'Logs'
    if logs.is_dir():
        for f in logs.rglob('*.txt'):
            if f.stat().st_size < 5_000_000:
                shutil.copy2(f, out / ('Logs-' + f.name))


def apply_load_preset(args, lua_text: str) -> str | None:
    """--load (LK13-T02): fills what the caller left unset (clients, group count, server run); returns an error text
    or None. Without --load: clients 1 by default."""
    load = getattr(args, 'load', False)
    if getattr(args, 'clients', None) is None:
        args.clients = LOAD_CLIENTS if load else 1
    if not load:
        return None
    if getattr(args, 'phases', None):
        return '--load and --phases go separately'
    if getattr(args, 'group_count', None) is None:
        args.group_count = LOAD_GROUPS
    if not (args.server_suite or args.server_campaign):
        args.server_campaign, args.server_suite, tags = load_plan(declared_campaigns(lua_text))
        if args.server_suite and args.server_tags is None:
            args.server_tags = tags
    return None


def apply_shard(args, lua_text: str, runs: Path | None = None) -> str | None:
    """--shard K/N: replaces --campaign or --server-campaign by the entries of shard K, with the filter the campaign
    used (client: exclude none, RST.campaign; server: exclude manual, A.serverFilter). Error text or None."""
    try:
        k, n = parse_shard(args.shard)
    except ValueError as e:
        return str(e)
    if getattr(args, 'phases', None):
        return '--shard does not split a phased run (--phases, e.g. mp-persist): its bases depend on each other'
    server = getattr(args, 'server_campaign', None)
    client = getattr(args, 'campaign', None)
    if bool(server) == bool(client):
        return '--shard splits exactly one campaign (--campaign or --server-campaign)'
    name = server or client
    if name == 'mp-persist':
        return '--shard: mp-persist is a list of phase bases, never split'
    entries = campaign_suites(lua_text, name)
    if not entries:
        return f'unknown or empty campaign {name!r} in {CAMPAIGN_FILE.name}'
    part = shard_entries(entries, k, n, report_durations(runs if runs is not None else RUNS))
    if not part:
        return f'shard {k}/{n} of {name} is empty ({len(entries)} entries)'
    log(f'shard {k}/{n} of campaign {name}: {len(part)} of {len(entries)} entries: ' + ','.join(part))
    if server:
        args.server_campaign, args.server_suite = None, ','.join(part)
        args.server_tags, args.server_exclude = None, 'manual'
    else:
        args.campaign, args.suite = None, ','.join(part)
        args.tags, args.exclude = None, ''
    return None


def main_mp(args) -> int:
    started = time.monotonic()
    lua_text = read_text(CAMPAIGN_FILE)
    error = apply_load_preset(args, lua_text)
    if error:
        log('ERROR: ' + error)
        return 2
    phase_ms = getattr(args, 'load_phase_ms', None)
    if phase_ms is not None and phase_ms < LOAD_PHASE_MIN_MS:
        log(f'ERROR: --load-phase-ms is at least {LOAD_PHASE_MIN_MS} (lk.loadmp ignores less)')
        return 2
    if getattr(args, 'load', False):
        log(f'load campaign (LK13-T02): {args.clients} client(s), LivingKnox.GroupCount = {args.group_count}, server '
            + (f'campaign {args.server_campaign}' if args.server_campaign else f'suites {args.server_suite}'))
    if args.campaign and (args.tags is not None or args.exclude is not None):
        log('ERROR: --tags and --exclude go with --suite only')
        return 2
    if (args.server_tags is not None or args.server_exclude is not None) and not args.server_suite             and not getattr(args, 'phases', None):
        log('ERROR: --server-tags and --server-exclude go with --server-suite (or --phases) only')
        return 2
    if not (args.campaign or args.suite or args.server_campaign or args.server_suite):
        log('ERROR: --mp needs --suite, --campaign, --server-suite or --server-campaign')
        return 2
    if getattr(args, 'shard', None):
        error = apply_shard(args, lua_text)
        if error:
            log('ERROR: ' + error)
            return 2
    split = lambda text: [s.strip() for s in text.split(',') if s.strip()] if text else None  # noqa: E731
    suites, server_suites = split(args.suite), split(args.server_suite)
    phases = split(getattr(args, 'phases', None)) or []
    steps = None
    if phases:
        if args.campaign or args.suite:
            log('ERROR: --phases runs server suites only (--server-suite or --server-campaign), not --suite/--campaign')
            return 2
        bases = server_suites or campaign_suites(lua_text, args.server_campaign or '')
        if bases is None:
            log(f'ERROR: unknown campaign {args.server_campaign!r} in {CAMPAIGN_FILE.name}')
            return 2
        if any(kept_clients(a) for a in phases) and args.clients < 2:
            log('ERROR: --phases reconnect2 needs --clients 2 (client 2 reconnects while client 1 stays)')
            return 2
        try:
            steps = phase_plan(bases, phases, declared_suite_names(CAMPAIGN_FILE.parents[2]))
        except ValueError as e:
            log(f'ERROR: --phases: {e}')
            return 2
        if args.server_tags is None and args.server_exclude is None:
            # Exact suite names: every server-side suite may run (world suites included, client ones never).
            args.server_tags, args.server_exclude = PHASE_SERVER_TAGS, ''
        for k, runs in enumerate(steps):
            label = 'before' if k == 0 else f'after {phases[k - 1]}'
            log(f'step {k} ({label}): ' + (' then '.join(','.join(r) for r in runs) if runs else 'reconnection only'))
    try:
        need, estimate = memory_need_mb(args.clients, args.client_xmx, args.server_xmx)
    except ValueError as e:
        log(f'ERROR: {e}')
        return 2
    free = free_memory_mb()
    log(f'memory: {free} MB available, -Xmx total {need} MB ({args.clients} client(s) x {args.client_xmx}, '
        f'server {args.server_xmx}), about {estimate} MB with the native parts')
    if free and free < estimate:
        log('WARNING: less free memory than the estimated use (the JVMs grow up to their -Xmx only when needed; '
            'lower --client-xmx, e.g. 3072m, if the clients stall)')

    slot_index = 0
    if not args.dry_run:
        slot, why = wait_for_slot(getattr(args, 'max_parallel', DEFAULT_MAX_PARALLEL), args.wait_idle, SLOTS_DIR)
        if slot is None:
            log('ERROR: ' + why)
            return 3
        slot_index = slot.index
        log(f'run slot {slot.index} of {getattr(args, "max_parallel", DEFAULT_MAX_PARALLEL)}')
    try:
        port, udp_port = mp_ports(slot_index, getattr(args, 'port_base', None),
                                  check=(lambda _p: True) if args.dry_run else port_free)
    except ValueError as e:
        log(f'ERROR: {e}')
        return 2
    log(f'server ports {port}/{udp_port}')

    token = secrets.token_hex(6)
    password = secrets.token_hex(8)  # local test server only, new each run
    out = args.out or RUNS / f'{datetime.now().strftime("%Y%m%d-%H%M%S")}-mp-{token}'
    mods = selected_mods()
    ids = [m for m, _ in mods]
    log('mods: ' + ', '.join(ids))
    missing = missing_mod_sources(mods + ([MODSWAP_MOD] if 'modswap' in phases else []))
    if missing:
        log('ERROR: mod source folder(s) missing: ' + ', '.join(missing) + ' (RS_WORKSHOP_DIR from a frozen copy)')
        return 2
    sandbox = mp_server_sandbox(args.ambient_zombies, getattr(args, 'group_count', None))
    server_cache = Path(tempfile.mkdtemp(prefix='rs-mp-server-'))
    build_server_cache(server_cache, mp_server_ini(ids, port, udp_port, max_players=max(MAX_CLIENTS, args.clients)),
                       sandbox_text=sandbox, mods=mods)
    log(f'RS_MP_SERVER_CACHE={server_cache}')
    connect = f'127.0.0.1:{port}'

    def command_of(i: int, step: int) -> tuple[str, str, str]:
        """(command, role, token) of client i for step (always step 0 without --phases)."""
        ctoken, user = phase_token(token, i, step), f'rs_mp{i}'
        common = dict(start_delay=args.start_delay, screenshot=not args.no_screenshot, server_timeout=args.timeout)
        if i == 1 and steps is not None and steps[step]:
            return mp_command_text(ctoken, connect, user, password, server_runs=steps[step],
                                   server_tags=args.server_tags, server_exclude=args.server_exclude, **common), 'run', ctoken
        if i == 1 and steps is None:
            return mp_command_text(ctoken, connect, user, password, campaign=args.campaign, suites=suites,
                                   tags=args.tags, exclude=args.exclude, server_campaign=args.server_campaign,
                                   server_suites=server_suites, server_tags=args.server_tags,
                                   server_exclude=args.server_exclude, **common), 'run', ctoken
        return mp_command_text(ctoken, connect, user, password, peer=True, **common), 'peer', ctoken

    clients = []
    for i in range(1, args.clients + 1):
        cache = Path(tempfile.mkdtemp(prefix=f'rs-mp-client{i}-'))
        command, role, ctoken = command_of(i, 0)
        build_client_files(cache, command, mods)
        clients.append(MPClient(i, cache, ctoken, f'rs_mp{i}', role))
        log(f'RS_MP_CLIENT{i}_CACHE={cache} (account {clients[-1].user}, {role})')
    phase_ms = getattr(args, 'load_phase_ms', None)
    if phase_ms is not None:
        write_launch_globals([server_cache] + [c.cache for c in clients],
                             launch_globals_lua({LOAD_PHASE_GLOBAL: phase_ms}))
        log(f'{LOAD_PHASE_GLOBAL} = {phase_ms} (Lua global of the server and the clients, {LAUNCH_GLOBALS_FILE.name})')
    scmd = server_java_command(GAME, server_cache, clients[0].user, password, args.server_xmx)
    ccmds = [with_xmx(java_command(GAME, c.cache), args.client_xmx) for c in clients]
    every = suites, server_suites
    if steps is not None:
        every = None, sorted({name for runs in steps for run in runs for name in run})
    use_bridge = args.bridge in ('on', 'offline') or (args.bridge == 'auto' and (
        ((args.campaign or every[0]) and needs_bridge(args.campaign, every[0], lua_text))
        or ((args.server_campaign or every[1]) and needs_bridge(None if steps else args.server_campaign, every[1],
                                                                 lua_text))))
    exchange = server_cache / EXCHANGE_DIR
    bcmd = bridge_command(sys.executable, BRIDGE_SCRIPT, exchange, args.bridge == 'offline') if use_bridge else None
    if args.dry_run:
        log('dry run, server: ' + subprocess.list2cmdline(scmd).replace(password, '<password>'))
        for c, cmd in zip(clients, ccmds):
            log(f'dry run, client {c.index}: ' + subprocess.list2cmdline(cmd))
        log('dry run, bridge: ' + (subprocess.list2cmdline(bcmd) if bcmd else 'not started'))
        log('dry run, server sandbox: ' + (' '.join(sandbox.split()) if sandbox else 'vanilla defaults'))
        return 0

    srv = ServerHandle(scmd, server_cache, (port, udp_port))
    bridge = None
    bridge_log = server_cache / 'bridge.log'
    llm = LLMService(getattr(args, 'llm', 'real') if bcmd and args.bridge != 'offline' else 'real', server_cache)
    code, reason = 2, ''
    try:
        # again: building the caches takes a while and the player may have started the game
        busy = busy_processes(tool_pids(SLOTS_DIR))
        if busy:
            raise RuntimeError('game or server not started by this tool running: ' + ', '.join(busy)
                               + ' (never killed by this tool)')
        if bcmd:
            exchange.mkdir(parents=True, exist_ok=True)
            env = llm.start(args.bridge_timeout)
            bridge = start_bridge(bcmd, bridge_log, BRIDGE_SCRIPT.parent, env)
            ok, why = wait_bridge_ready(bridge, bridge_log, args.bridge_timeout)
            if not ok:
                raise RuntimeError(why + ': nothing started')
            log(f'bridge ready (pid {bridge.pid}), exchange of the SERVER {exchange}')
        srv.launch(args.server_timeout)
        for line in account_commands([c.user for c in clients[1:]], password):
            send_console(srv.proc, line)
            log('server console: ' + line.replace(password, '<password>'))
            time.sleep(1.0)
        if steps is None:
            code, reason = run_mp_clients(clients, ccmds, srv.proc, bridge, started, args)
        else:
            code, reason = run_phases(clients, ccmds, srv, bridge, started, args, steps, phases, command_of, ids)
    except RuntimeError as e:
        reason = reason or str(e)
    finally:
        for c in clients:
            if c.running():
                c.control(['go', 'quit'])
        if not stop_clients(clients, args.quit_timeout) and code == 0:
            code = 2
        if srv.proc is not None:
            log(stop_server(srv.proc, args.quit_timeout))
        stop_bridge(bridge)
        if bridge is not None:
            log(f'bridge stopped (code {bridge.returncode})')
        llm.stop(out / 'server')
    if reason:
        log('ERROR: ' + reason)
    collect_server(server_cache, out / 'server', srv.log_path)
    for c in clients:
        collect(c.cache, out / f'client{c.index}', c.stdout_log)
    found = store_bridge_log(bridge_log, out / 'server')
    if found:
        log(f'ERROR: {found} credential-shaped string(s) redacted from bridge.log')
        code = 2
    log(f'results copied to {out}')
    caches = [server_cache] + [c.cache for c in clients]
    if code == 0 and not args.keep_cache:
        for cache in caches:
            shutil.rmtree(cache, ignore_errors=True)
        log('temporary caches removed')
    else:
        log('temporary caches kept: ' + ', '.join(str(c) for c in caches))
    log(f'RS_AUTOCLIENT_EXIT={code} ({int(time.monotonic() - started)} s)')
    return code


class ServerHandle:
    """The dedicated test server of an MP run: same command and cache for every launch (a restart reopens the same
    world, Saves/Multiplayer/<server name>), one stdout log per launch (server-stdout.log, then -p<step>.log)."""

    def __init__(self, cmd: list[str], cache: Path, ports: tuple[int, int] = (MP_PORT, MP_UDP_PORT)):
        self.cmd, self.cache, self.ports = cmd, cache, ports
        self.proc = None
        self.log_path = cache / 'server-stdout.log'
        self.launches = 0

    def launch(self, timeout: int) -> None:
        """Starts the server and waits for it to listen; RuntimeError with the reason otherwise."""
        if self.launches:
            self.log_path = self.cache / f'server-stdout-p{self.launches}.log'
        self.launches += 1
        with open(self.log_path, 'wb') as so:
            self.proc = subprocess.Popen(self.cmd, cwd=GAME, stdout=so, stderr=subprocess.STDOUT,
                                         stdin=subprocess.PIPE)
        register_child(self.proc.pid)
        log(f'server started (pid {self.proc.pid}, launch {self.launches}), waiting up to {timeout} s for it to listen')
        server_started = time.monotonic()
        limit = server_started + timeout
        while not server_ready(read_text(self.log_path)):
            if 'Connection Startup Failed' in read_text(self.log_path):
                raise RuntimeError(f'RakNet could not open ports {self.ports[0]}/{self.ports[1]} (another server running?): '
                                   f'see {self.log_path.name}')
            if self.proc.poll() is not None:
                raise RuntimeError(f'the server exited (code {self.proc.returncode}) before listening')
            if time.monotonic() >= limit:
                raise RuntimeError(f'the server did not listen after {timeout} s')
            time.sleep(1.0)
        log(f'server listening after {int(time.monotonic() - server_started)} s')
        time.sleep(3.0)


def stop_clients(clients: list[MPClient], timeout: int) -> bool:
    """Waits for the clients told to "quit" to exit; kills those still running after timeout. False if any was
    killed."""
    clean = True
    for c in clients:
        if c.running():
            try:
                c.proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                log(f'{c.name()} still running {timeout} s after "quit": killed')
                kill_tree(c.proc.pid)
                clean = False
                try:
                    c.proc.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    pass
        if c.proc is not None:
            log(f'{c.name()} exited (code {c.proc.returncode}), {c.clicks} click(s) posted')
    return clean


def next_client_process(c: MPClient, step: int, token: str, command: str, role: str) -> None:
    """Prepares the cache of client c for its process of step (same account, same cache): files of the previous
    process archived (p<step-1>-*.txt), result file removed, control file emptied (it still says "go quit"), new
    command with a new token (the status file keeps the lines of the previous tokens)."""
    archive_for_phase(c.cache, step - 1, [c.cache / 'console.txt', c.stdout_log, c.result_file], move=(c.result_file,))
    c.control_file.parent.mkdir(parents=True, exist_ok=True)
    c.control_file.write_bytes(b'')
    (c.cache / TESTS_DIR / 'autoclient.txt').write_bytes(command.encode('utf-8'))
    c.token, c.role = token, role
    c.stdout_log = c.cache / f'client-stdout-p{step}.log'
    c.proc, c.state, c.detail, c.godmode_sent, c.respawns = None, None, '', False, 0


def keep_client_process(c: MPClient, step: int, token: str, command: str, role: str) -> None:
    """Prepares client c, kept connected during a reconnect2 action, for its run of step (same process): files of the
    previous run archived (p<step-1>-*.txt, result file removed), new command with a new token, then "reload" in the
    control file (RST_AutoClient.lua reads the command again and waits for "go" as after a connection)."""
    archive_for_phase(c.cache, step - 1, [c.cache / 'console.txt', c.stdout_log, c.result_file], move=(c.result_file,))
    (c.cache / TESTS_DIR / 'autoclient.txt').write_bytes(command.encode('utf-8'))
    c.token, c.role = token, role
    c.state, c.detail, c.godmode_sent, c.respawns = None, '', False, 0
    c.control(['reload'])


def run_phases(clients: list[MPClient], ccmds: list[list[str]], srv: ServerHandle, bridge, started: float, args,
               steps: list[list[list[str]]], phases: list[str], command_of,
               mod_ids: list[str] | None = None) -> tuple[int, str]:
    """Phased MP run (E01-T17): step 0, then for each action every client quits (quitToDesktop: disconnection), the
    server is stopped with "quit" (save) and launched again on the same cache for a restart, and every client joins
    again with its account (existing character) for the next step. reconnect2: client 1 is never told to quit, it
    gets the command of the next step by "reload" while client 2 (and any later one) quits and joins again. Worst code
    wins; an infrastructure failure (code 2) stops the sequence."""
    code, reasons = 0, []
    for k, runs in enumerate(steps):
        label = 'before' if k == 0 else f'after {phases[k - 1]}'
        if k > 0:
            action = phases[k - 1]
            log(f'phase {k}: {action}')
            kept = kept_clients(action)
            if not stop_clients([c for c in clients if c.index not in kept], args.quit_timeout):
                return 2, '; '.join(reasons + [f'step {k - 1}: a client did not quit'])
            if action in ('restart', 'modswap'):
                message = stop_server(srv.proc, args.quit_timeout)
                log(message)
                if 'killed' in message or srv.proc.returncode != 0:
                    return 2, '; '.join(reasons + [f'{action}: {message}'])
                archive_for_phase(srv.cache, k - 1, [srv.cache / 'server-console.txt', srv.log_path])
                if action == 'modswap':
                    ids = add_mod_to_caches(srv.cache, [c.cache for c in clients], mod_ids or [], MODSWAP_MOD)
                    log(f'modswap: {MODSWAP_MOD[0]} added to the server ini and to the clients: ' + ', '.join(ids))
                pause = getattr(args, 'restart_pause', 0) or 0
                if pause:
                    log(f'server down for {pause} s (--restart-pause)')
                    time.sleep(pause)
                srv.launch(args.server_timeout)
            for line in admin_commands([c.user for c in clients[1:] if c.index not in kept]):
                send_console(srv.proc, line)
                log('server console: ' + line)
                time.sleep(1.0)
            for c in clients:
                command, role, ctoken = command_of(c.index, k)
                if c.index in kept:
                    keep_client_process(c, k, ctoken, command, role)
                else:
                    next_client_process(c, k, ctoken, command, role)
        log(f'step {k} ({label}): ' + (' then '.join(','.join(r) for r in runs) if runs else 'reconnection only'))
        action = phases[k] if k < len(phases) else None
        keep = kept_clients(action)
        line = quit_wait_line(runs, action, [c.user for c in clients if c.index not in keep])
        wait = (srv.log_path, len(read_text(srv.log_path)), line) if line else None
        step_code, why = run_mp_clients(clients, ccmds, srv.proc, bridge, started, args, keep=keep, quit_wait=wait)
        log(f'step {k} ({label}) code {step_code}' + (f': {why}' if why else ''))
        code = max(code, step_code)
        if why:
            reasons.append(f'step {k} ({label}): {why}')
        if step_code == 2:
            break
    return code, '; '.join(reasons)


def wait_peer_results(clients: list[MPClient], timeout: float, poll: float = 1.0,
                      keep: tuple[int, ...] = ()) -> None:
    """After "quit": a peer client writes the result of its steps before leaving (RST_AutoClient.lua); waits for it
    (or for the client to exit) at most timeout seconds. Kept clients (keep: indices, never told to quit) are not
    awaited."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if all(c.result_first() is not None or not c.running() for c in clients
               if c.role == 'peer' and c.index not in keep):
            return
        time.sleep(poll)


def ensure_godmode(c: MPClient, server, args) -> None:
    """godmodeplayer on the server console once client c is in game, and again after each respawn with a new
    character (a new, mortal IsoPlayer), unless --no-godmode."""
    if not getattr(args, 'godmode', False):
        return
    if c.state in MP_INGAME and not c.godmode_sent:
        # Console of the server: GodModePlayerCommand -> setGodMod + sendPlayerExtraInfo (client too).
        send_console(server, f'godmodeplayer {c.user} -true')
        log(f'server console: godmodeplayer {c.user} -true')
        c.godmode_sent = True
        c.new_respawns()   # a respawn written before this point is covered by this command
    elif c.godmode_sent and c.new_respawns():
        send_console(server, f'godmodeplayer {c.user} -true')
        log(f'server console: godmodeplayer {c.user} -true (respawned: {c.detail})')


def run_mp_clients(clients: list[MPClient], ccmds: list[list[str]], server, bridge, started: float,
                   args, keep: tuple[int, ...] = (), quit_wait: tuple[Path, int, str] | None = None) -> tuple[int, str]:
    """Starts the clients one after the other, "go" when all are in game, waits for the results, then "quit".
    A client still running (kept connected by a reconnect2 action, its command reloaded) is not started again: its
    "ingame" status for the new token counts. keep: indices of the clients that only get "go" at the end (no "quit":
    the next action keeps them connected); their peer result is then not awaited. quit_wait = (server log, offset,
    text): once the results are complete, waits at most QUIT_WAIT_S seconds for text in the server log after offset
    before the "quit" (a warning, not a failure, when it never comes). A client that respawned after a real death
    (status detail "respawn: new character", RST_AutoClient.lua) gets "godmodeplayer" again unless --no-godmode; its
    loading screen, if any, is clicked as at the first connection."""
    if not clients[0].running():
        clients[0].start(ccmds[0])
    launched, go_sent, bridge_warned, results_at = 1, False, False, None
    stage_started = time.monotonic()
    while True:
        now = time.monotonic()
        for c in clients[:launched]:
            c.poll_state()
            c.click_if_loading(now)
            ensure_godmode(c, server, args)
        if bridge is not None and not bridge_warned and bridge.poll() is not None:
            log(f'WARNING: the bridge exited during the run (code {bridge.returncode}); see bridge.log')
            bridge_warned = True
        if server.poll() is not None:
            return 2, f'the server exited during the run (code {server.returncode})'
        for c in clients[:launched]:
            if c.proc.poll() is not None and c.result_first() is None:
                return 2, f'{c.name()} exited (code {c.proc.returncode}) in state {c.state} without a result'
            if c.state == 'error':
                return 2, f'{c.name()} failed: {c.detail}'
        current = clients[launched - 1]
        if launched < len(clients) and current.state in MP_INGAME:
            if not clients[launched].running():
                clients[launched].start(ccmds[launched])
            launched += 1
            stage_started = now
            continue
        if not go_sent and launched == len(clients) and all(c.state in MP_INGAME for c in clients):
            for c in clients:
                c.control(['go'])
            go_sent = True
            log('every client is in game: "go" written to the control files')
        if not go_sent and now - stage_started >= args.menu_timeout + 600:
            return 2, f'{current.name()} not in game after {int(now - stage_started)} s (state {current.state})'
        if go_sent:
            results = [(c.role, c.result_first()) for c in clients]
            if all(first is not None for role, first in results if role == 'run'):
                for c in clients:
                    c.poll_state()
                    ensure_godmode(c, server, args)
                lagging = [c for c in clients if c.role in ('idle', 'peer') and c.state != 'idle']
                if lagging and results_at is None:
                    results_at = now
                if lagging and now - results_at < 30:
                    time.sleep(1.0)
                    continue  # an idle client writes "idle" a moment after "go"
                if quit_wait is not None:
                    path, offset, text = quit_wait
                    log(f'waiting up to {int(QUIT_WAIT_S)} s for the server line "{text}" before "quit"')
                    if wait_server_text(path, offset, text, QUIT_WAIT_S):
                        log(f'server line seen: {text}')
                    else:
                        log(f'WARNING: server line "{text}" not seen after {int(QUIT_WAIT_S)} s: "quit" anyway')
                    quit_wait = None
                for c in clients:
                    c.control(['go'] if c.index in keep else ['go', 'quit'])
                log('results complete: "quit" written to the control files'
                    + (f' (client(s) {", ".join(str(i) for i in keep)} kept connected)' if keep else ''))
                wait_peer_results(clients, getattr(args, 'quit_timeout', 120), keep=keep)
                # A kept peer writes no result (no "quit"): counted as idle for this step.
                results = [('idle' if c.role == 'peer' and c.index in keep else c.role, c.result_first())
                           for c in clients]
                for c in clients:
                    if c.role in ('run', 'peer'):
                        log(f'{c.name()}: {c.result_first()}')
                code, why = mp_code(results)
                for c in lagging:
                    code, why = 2, (why + '; ' if why else '') + f'{c.name()} not idle (state {c.state})'
                return code, why
        if now - started >= args.timeout:
            return 2, f'no complete result after {args.timeout} s'
        time.sleep(1.0)


if __name__ == '__main__':
    sys.exit(main())
