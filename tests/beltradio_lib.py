"""Vraie bibliothèque Belt Walkie-Talkie (mod requis batman_BeltRadio) pour les bancs lupa de RadioSurvivor.

RadioSurvivor n'embarque plus de copie du récepteur commun (décision 9) : les tests chargent la source du dépôt voisin
Workshop/BeltRadio (chemin relatif à ce dépôt). Sans ce dépôt, les tests qui en dépendent sont SKIP (jamais PASS) :

    from beltradio_lib import BELT_LUA, missing, lua_path, SUPPORT_REQUIRE
    reason = missing()          # None, ou la raison du SKIP
    rt.execute(f'package.path = [[{lua_path()};]] .. package.path')
    rt.execute(SUPPORT_REQUIRE)  # BatmanRadioSupport.canTransmitWith (fichier shared, chargé partout)

Doublures Java nécessaires à BatmanRadioSupport.canTransmitWith (BatmanRadio_Support.lua) : instanceof(radio,
"Radio") ; DeviceData getIsPortable, getIsTelevision, getIsTwoWay, isNoTransmit, getIsTurnedOn,
getIsBatteryPowered (getHasBattery, getPower si vrai), getMicIsMuted (hors serveur) ; joueur getPrimaryHandItem,
getSecondaryHandItem, getClothingItem_Back, isAttachedItem (radio ni en main ni sur le dos) ; isServer, isClient,
getActivatedMods (BatmanRadio_Compat : nil = Better Walkie Talkies absent).

Doublures nécessaires au bruit de réception à la ceinture (BatmanRadio_BeltNoise.lua, appelé par
BatmanRadio_Core.deliver ; option sandbox BeltRadio.BeltNoise, vraie par défaut) : DeviceData getIsTurnedOn,
getHeadphoneType (int, -1 sans écouteurs : DeviceData.java:87 et 380), getDeviceVolume, getDeviceSoundVolumeRange
(int, DeviceData.java:869) ; radio getID ; joueur getX, getY, getZ ; getTimestampMs ; global addSound(source, x, y, z,
radius, volume) (LuaManager.java:9239).
"""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BELT_ROOT = ROOT.parent / 'BeltRadio'
# RS_BELTRADIO_LUA : autre dossier media/lua de la bibliothèque (ou dossier absent, pour vérifier le SKIP).
BELT_LUA = Path(os.environ.get('RS_BELTRADIO_LUA')
                or BELT_ROOT / 'Contents' / 'mods' / 'batman_BeltRadio' / '42.21' / 'media' / 'lua')
FILES = ('shared/BatmanRadio/BatmanRadio_Support.lua', 'shared/BatmanRadio/BatmanRadio_Compat.lua',
         'client/BatmanRadio/BatmanRadio_Core.lua', 'client/BatmanRadio/BatmanRadio_BeltBattery.lua',
         'client/BatmanRadio/BatmanRadio_BeltNoise.lua')
SUPPORT_REQUIRE = 'require "BatmanRadio/BatmanRadio_Support"'
CORE_REQUIRE = 'require "BatmanRadio/BatmanRadio_Core"'


def missing() -> str | None:
    """Raison du SKIP si la bibliothèque est absente, sinon None."""
    absent = [rel for rel in FILES if not (BELT_LUA / rel).is_file()]
    if absent:
        return f'Belt Walkie-Talkie library absent ({BELT_LUA}): ' + ', '.join(absent)
    return None


def lua_path(sides=('shared', 'client')) -> str:
    """Entrées package.path des dossiers media/lua/<side> de la bibliothèque."""
    return ';'.join((BELT_LUA / side).as_posix() + '/?.lua' for side in sides)
