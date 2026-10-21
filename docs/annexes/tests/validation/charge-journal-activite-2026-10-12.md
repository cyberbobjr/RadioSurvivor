# Coût du journal d'activité des PNJ (LK13-T14)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu (lupa), **aucune mesure en jeu ni en Kahlua**. Méthode et
  scénario : [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ; conception :
  [administration.md](../../conception/administration.md), « Panneau de debug des PNJ ».
- **Banc** : `tools/load_bench.py` (5 groupes, 4 joueurs, serveur dédié + 4 clients), une minute de mise en route puis
  60 minutes de jeu (1 500 images serveur). Script de mesure non gardé dans le dépôt : `LoadBench` du banc, enveloppes
  chronométrées (horloge `time.perf_counter`, appels imbriqués comptés une fois) de `Activity.note`,
  `Activity.behaviour` et `Activity.noteNpc` sur le serveur ; puis deux passages identiques avec et sans journal
  (`LivingKnox.Activity = nil` : tous les points d'écoute sautés), écritures des registres comptées par en-tête
  (`WRITES` du banc) et état final des trois registres encodé (`STATE_HEX`).

## Résultats (serveur, temps lupa)

| Mesure | Valeur |
|---|---|
| Appels du journal (points d'écoute) | 366 en 60 min de jeu |
| Lignes écrites | 38 (30 `behaviour`, 4 `alert`, 4 `objective`) |
| Temps total du journal | 0,457 ms, soit 0,0003 ms par image |
| Plus lourd appel | 0,044 ms |
| Moteur entier par image (LK_Load, même passage) | 0,393 ms (journal : 0,08 %) |
| Écritures `LKREG1` / `LKGRP1`, avec journal | 8 / 27 |
| Écritures `LKREG1` / `LKGRP1`, sans journal | 8 / 27 |
| Registres finaux (PNJ, groupes, attitudes) | identiques avec et sans journal |
| Erreurs d'abonnés, cinq machines | 0 |

Le temps mesuré comprend le rappel Python de l'horloge (majorant). Mémoire : au plus 200 lignes de 160 caractères
par groupe (anneau), rien de sauvegardé ; le panneau ne coûte rien fermé (aucune requête) et, ouvert, une requête
toutes les 2 s dont la réponse ne porte que les lignes nouvelles.

## Limites

Lupa n'est pas Kahlua (facteur 2,5 à 6 selon l'opération, base `kahlua-lua.md`) : même multiplié par 6, le journal
reste sous 0,002 ms par image. Les volumes de lignes dépendent du scénario du banc (aucun combat, repas ni soin dans
cette heure) ; à confirmer par le panneau en jeu (lignes reçues) et par `LivingKnox.Load` en jeu si besoin.
