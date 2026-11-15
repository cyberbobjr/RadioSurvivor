# ADR — Remise en ordre SOLID du moteur Living Knox

| | |
|---|---|
| Date | 2026-11-13 (création, acceptation) |
| Statut | Accepté (confirmé par défaut le 2026-11-13, selon la règle de l'utilisateur : option recommandée appliquée, liste des choix dans le compte rendu, veto possible ; demande d'origine : « après LK15 : audit SOLID de tout Living Knox ») |
| Décideur | utilisateur |
| Portée | `batman_LivingKnox`, côté autorité et client (`media/lua/{server,client,shared}/LivingKnox`) ; aucun changement de comportement pour un joueur |
| Plan associé | [LK16 — Remise en ordre SOLID](../../annexes/plans-termines/LK16-remise-en-ordre-solid.md) (suivi des tâches dans le plan) |
| Références | [audit SOLID du 2026-11-13](../../annexes/audits/audit-solid-livingknox-2026-11-13.md) (214 constats) ; [vérification contradictoire des 34 P0](../../annexes/audits/audit-solid-livingknox-2026-11-13-verification-p0.md) ; [ADR des registres des routines](adr-registre-routines.md) ; règle « Principes SOLID dès la conception » de [`docs/developpement.md`](../../developpement.md) |

## Contexte

L'audit SOLID du 2026-11-13 relève 214 constats, dont 34 P0 : des « genres » énumérés à la main dans des moteurs
(chaînes `if kind == …`, tables parallèles), contraires à la règle du projet (au troisième cas du même genre, un
registre). La vérification contradictoire des 34 P0 en confirme 18, en réduit 14 (vrais mais moins graves, souvent des
énumérations fermées par nature) et en réfute 2. Elle propose onze chantiers regroupés (C1 à C11) et une liste de
corrections à ne pas faire, qui seraient de l'abstraction spéculative.

Le mod n'est pas publié : aucun format sauvegardé n'a à être repris (règle « pas de reprise avant publication »). Les
campagnes en jeu sont rares ; le banc hors jeu, rendu mimétique par l'étape [E19](../../annexes/plans/E19-banc-mimetique.md),
sert de filet.

## Décisions

- **D01 — Remise en ordre par chantiers, sans changement de comportement.** Chaque chantier garde les bancs hors jeu
  verts sans changer un attendu (un attendu qui change est une découverte à expliquer, jamais un rebasage), luacheck
  sans hausse, contrôles d'API (`test_doubles_api.py`, `test_mod_calls_api.py`) verts. La validation en jeu vient à la
  fin, par les campagnes solo et MP.
- **D02 — Socle commun des registres.** Un helper `LivingKnox.Registry` (inscription, liste triée par `order` puis
  identifiant, lecture, une seule politique de doublon : remplacement au rechargement) remplace les cinq copies
  actuelles (`Upkeep.registerJob`, `Routines.registerActivity`, `Decisions.registerExtension`, `Loot.registerContent`,
  types de groupes). Les registres existants gardent leur API publique.
- **D03 — Chantiers retenus, dans cet ordre.** C1 (genres de chantier de la fortification : un registre dont dérivent
  toutes les tables et la forme compacte) et C7 (tables d'aiguillage des faits publics, des opérations
  d'administration, des requêtes de parole et des réponses d'administration) d'abord, en parallèle ; puis C5 (casser
  les cycles à l'exécution par des événements), C3 (contexte de décision par inscription), C2 (comportements de
  décision par `registerExtension`) ; puis C8 (corvées), C9 (plans des routines dans leurs activités), C4 (genres
  d'expédition), C6 (ordre horaire et événements de la simulation), C11 (aménagements des foyers), C10 (obstacles :
  modèles d'itinéraire et dédoublonnage). Les nettoyages sans registre de la vérification (table morte `Raids.SIGNS`,
  constante unique des intents, tables existantes des objectifs, boucle locale de `tryDepart`) se font dans le
  chantier du module concerné.
- **D04 — Ne pas faire.** Les registres réfutés ou jugés spéculatifs par la vérification ne sont pas créés : primitives
  d'exécution des plans (F-R02), escalade du déplacement (H-D02), nature d'obstacle comme registre (D-OBS-02 : arêtes
  de tuile fermées par le moteur), origines des objets portés (C-X05), verbes de l'exécutant tant qu'il n'y en a que
  trois (H-D01), liste ordonnée des sous-règles de menace (B-C06). Ils sont réexaminés si un quatrième cas apparaît.
- **D05 — Une tâche par chantier, déléguable.** Chaque chantier est une tâche de plan, découpable en sous-tâches si
  elle dépasse un fichier moteur ; deux chantiers ne modifient jamais le même fichier en même temps.

## Alternatives écartées

| Alternative | Pour | Contre | Verdict |
|---|---|---|---|
| Tout corriger d'un coup (214 constats) | Un seul passage | Risque de régression non maîtrisable ; beaucoup de constats P2/P3 sans gain réel | écartée |
| Ne rien faire avant la publication | Aucun risque immédiat | Chaque ajout futur (sorte de chantier, genre d'expédition, comportement) touche les moteurs ; la dette grandit | écartée |
| Corriger seulement les P0 confirmés, sans socle | Moins de travail | Cinq copies de registre restent divergentes | écartée |
| **Chantiers vérifiés, dans l'ordre de dépendance, sans changement de comportement** | Gain ciblé, bancs comme filet, extension sans toucher aux moteurs | Travail étalé ; campagnes en jeu à la fin | **retenue** |

## Conséquences

- Les fichiers moteurs maigrissent ; les « genres » vivent chacun dans leur fichier, comme les tâches et les routines.
- Les formats sauvegardés (forme compacte de la fortification) peuvent changer : aucune reprise à écrire (mod non publié).
- Les campagnes en jeu de fin de plan confirment l'absence de régression ; un écart vu en jeu suit la règle du banc
  d'abord (`docs/annexes/tests/ecarts-banc-jeu.md`).
