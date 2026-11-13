"""Réseau en désordre dans les bancs multijoueurs (E19-T06, ADR banc mimétique D06).

Rejoue un scénario de banc serveur dédié + clients plusieurs fois, chaque fois sur un harnais neuf livré dans un ordre
différent, pour qu'un défaut qui suppose un ordre de livraison échoue sur au moins un ordre, sans crochet écrit pour
lui (suite rs.npctalk du 2026-11-05 : réponse de l'étape arrivée après la requête déjà répondue).

Ce que le jeu garantit (sources 42.22) et que l'aide respecte :
- commandes Lua (sendClientCommand, sendServerCommand) : paquet ClientCommand fiable NON ordonné (PacketTypes.java:491,
  reliability 2 = RELIABLE, RakNetPeerInterface.java:44-51) : deux commandes d'un même émetteur vers un même
  destinataire peuvent s'inverser, et une commande perdue puis renvoyée arrive après des commandes envoyées plus tard,
  à une image suivante ;
- paquets du moteur liés à une case (cadavre, objet, conteneur) et position du joueur : RELIABLE_ORDERED sur leur canal
  (harness.PACKET_CHANNELS) : jamais inversés entre eux dans un même flux, retardés en bloc ;
- jamais de réponse avant sa demande : un message envoyé pendant une livraison part dans un lot suivant.

Ordres (DEFAULT_ORDERS) : fifo, lifo, puis random à trois graines fixes avec retard (LATE pompes au plus).

Utilisation, dans un unittest.TestCase dont setUp construit self.h (Harness mode 'mp') et le décor :

    from net_disorder import DEFAULT_ORDERS, OwnerChange, disorder
    def test_scene_under_network_disorder(self):
        disorder(self, lambda o: self.check(self.run_scene()))
        disorder(self, scene, owner_change=OwnerChange(zombie=1001, to='B', after_ticks=20))

- Chaque rejeu part d'un harnais neuf : le premier utilise celui du setUp, les suivants appellent tearDown puis setUp ;
  le tearDown de unittest ferme le dernier. L'ordre est posé après le setUp (le décor se monte en fifo).
- Chaque rejeu tourne dans un subTest(order=<nom>) : un échec nomme l'ordre et sa graine (« random-2 »), les autres
  rejeux sont joués quand même.
- owner_change : le propriétaire du corps change pendant la scène, after_ticks images après son début, par le réseau
  (Harness.set_owner(..., via_network=True) : serveur à l'instant, clients à la livraison de leur ZombieList).
  zombie : identifiant, ou fonction (harnais) -> identifiant pour un corps créé par la scène.
"""
from __future__ import annotations

import random
from dataclasses import dataclass

LATE = 2  # pompes de retard au plus d'un message (perte puis renvoi RakNet) dans les ordres random


@dataclass(frozen=True)
class Delivery:
    """Ordre de livraison d'un rejeu : nom dans les rapports, ordre de Harness.pump, graine, retard au plus."""
    name: str
    order: str
    seed: int = 0
    delay: int = 0


DEFAULT_ORDERS = (
    Delivery('fifo', 'fifo'),
    Delivery('lifo', 'lifo'),
    Delivery('random-1', 'random', 1, LATE),
    Delivery('random-2', 'random', 2, LATE),
    Delivery('random-3', 'random', 3, LATE),
)


@dataclass(frozen=True)
class OwnerChange:
    """Changement de propriétaire d'un corps pendant la scène (lk.handover du 2026-10-15)."""
    zombie: object          # int, ou callable(harness) -> int
    to: str
    after_ticks: int

    def schedule(self, h):
        def change():
            zid = self.zombie(h) if callable(self.zombie) else self.zombie
            if zid is not None and zid in h.owners:
                h.set_owner(zid, self.to, via_network=True)
        h.at_tick(self.after_ticks, change)


def disorder(case, scenario, orders=DEFAULT_ORDERS, owner_change: OwnerChange | None = None):
    """Joue scenario(delivery) pour chaque ordre, sur un harnais neuf. Rend la liste des noms joués."""
    played = []
    for i, delivery in enumerate(orders):
        if i:
            case.tearDown()
            case.setUp()
        with case.subTest(order=delivery.name):
            h = case.h
            h.order, h.delay, h.rng = delivery.order, delivery.delay, random.Random(delivery.seed)
            if owner_change is not None:
                owner_change.schedule(h)
            scenario(delivery)
        played.append(delivery.name)
    return played
