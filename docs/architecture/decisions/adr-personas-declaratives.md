# ADR — Voix radio déclarées en un seul fichier : missions, récompenses, lieux et troc

| | |
|---|---|
| Date | 2026-11-14 (création, acceptation, précision de D06 sur les planques multiples) |
| Statut | Accepté (utilisateur, 2026-11-14) ; plan E20 terminé le 2026-11-15 |
| Décideur | utilisateur |
| Portée | `batman_RadioSurvivor` (fiches `personas/`, `RS_Persona`, `RS_MissionVoice`, `RS_VoiceDelivery` (devenu `RS_DeadDrops`, E20-T06), `RS_Rewards`, `RS_Trade*`, carnet et carte côté client), le pont (`bridge/persona_store.py`, `bridge/radio_bridge.py`) et, pour les gabarits de mission qu'il héberge, `batman_RadioSurvivorCore`. Living Knox hors portée : ses missions de PNJ, son dépôt de groupe et sa remise en main propre ne changent pas. |
| Plan associé | [E20 — Voix déclarées en un seul fichier](../../annexes/plans-termines/E20-voix-declaratives.md) (suivi des tâches dans le plan) |
| Références | [format des fiches](../../specifications-techniques/persona-format.md) ; [passeur, rendez-vous](../../annexes/conception/passeur-rendezvous.md) et [échange](../../annexes/conception/passeur-echange.md) ; principes SOLID de [developpement.md](../../developpement.md) ; [ADR des registres de routines](adr-registre-routines.md) (même patron de registre) |

## Contexte

Demandes de l'utilisateur du 2026-11-14 :

1. Définir **dans un seul fichier facile à éditer** une voix radio avec : les types de missions qu'elle propose, les
   catégories d'objets de ses récompenses (toujours tirées au hasard), les lieux de dépôt (plusieurs possibles) ; le
   moteur gère tout le reste. SOLID non négociable.
2. Des livraisons réalistes : un objet ne disparaît jamais sous les yeux du joueur.
3. Un marchand de troc par ville vanilla, pas un seul passeur pour toute la carte.
4. De nouvelles missions ; pour Darlene, une histoire qui explique pourquoi sécuriser la clinique (elle veut y revenir,
   ce qui prépare l'arrivée de Living Knox).

Relevé du code du 2026-11-14 (confirmé statiquement) :

- **Déjà déclaratif** : une fiche par voix dans `personas/`, tout fichier ajouté est chargé (`RS_Personas.lua:369`).
  Elle porte déjà `missions=`, `rewards=`, `cache_table=` et `place=`.
- **Listes fermées dans le code** (ajouter un type = modifier plusieurs fichiers) :
  `RS_MissionVoice.lua:68-69` (`V.TEMPLATES`, renommages), `:121`, `:129`, `:136` (cas `signal` et `deliver`) ;
  `RS_Notebook.lua:484-488` et `RS_MapActions.lua:203` (un booléen par type) ;
  `bridge/radio_bridge.py:1153, 1204-1242, 1553, 1602` (branches `elif kind ==`) ;
  `bridge/persona_store.py:37, 330-333` (second analyseur des fiches, avec ses propres listes fermées).
- **Récompenses ni aléatoires ni déclarées** : cycle fixe `cache` → `frequency` → `stashmap` → `lesson` par joueur
  (`RS_Rewards.lua:93-139`) ; contenu des caches figé dans le code (`RC_MissionConfig.lua:138-144` : `medical` = 4
  bandages, 1 désinfectant, 1 boîte de pilules, toujours). Une seule `cache_table` par fiche.
- **Livraison identique pour toutes les voix** : `RC_MissionConfig.lua:28-35`, 6 bandages ou draps déchirés, que la voix
  soit infirmière ou mécanicien.
- **Lieux de dépôt mêlés aux repères** : la planque est la ligne `place=` suivante, en tournant
  (`RS_MissionVoice.lua:137`), parmi les lieux que la voix peut aussi marquer sur la carte.
- **Remises irréalistes** :
  - carte d'identité pour une voix : retirée de l'inventaire au moment du compte rendu radio
    (`RC_MissionRetrieve.lua:220-238`), alors que la voix est à des kilomètres ;
  - planque : ramassée après 10 s réelles hors de 40 cases (`RS_Config.lua:4`), délai réel contraire à la décision C27
    (délais en temps de jeu) ;
  - troc : échange appliqué à la minute de jeu suivante dès que personne n'est à moins de 20 cases
    (`RS_TradeExchange.lua:41-42`), sac encore visible à l'écran.
- **Troc singleton** : un ponton (`RS_Trade.lua:88`, Riverside), un stock, un passage par semaine pour tout le serveur
  (`S.data.trade`).

## Analyse : missions dans la fiche ou dans un fichier `mission_type.txt` ?

Il faut séparer deux choses que le mot « mission » recouvre :

- le **comportement** d'un type (comment le serveur vérifie « 6 fenêtres barricadées » ou « carte déposée ») : c'est du
  code d'autorité, qu'un fichier texte ne peut pas exprimer ;
- les **paramètres** d'une mission donnée par une voix (quel lieu, quels objets, combien, quelle histoire, quelle
  récompense) : ce sont des données.

| Option | Pour | Contre |
|---|---|---|
| A. Tout dans la fiche de la voix (sections `[mission …]`) | un seul fichier par voix, comme demandé ; ajouter une voix = déposer un fichier ; la fiche dit déjà actions, lieux et récompenses | deux voix qui veulent la même mission la décrivent chacune (quelques lignes) |
| B. `mission_type.txt` partagé, référencé par les fiches | réutilisation de préréglages | deux fichiers à éditer et à garder cohérents ; indirection pour un gain non demandé ; le comportement reste de toute façon dans le code |
| C. Types de mission aussi en données | aucun code pour un nouveau type | impossible sans interpréteur de règles : la vérification du monde reste du code |

**Recommandation : A**, avec le comportement de chaque type dans **un fichier Lua par type, inscrit à un registre**
(patron déjà validé par l'[ADR des registres de routines](adr-registre-routines.md)). Seule exception à « un seul
fichier » : un **catalogue de catégories d'objets partagé**, livré par le mod (`personas/_categories.txt`), pour ne
pas recopier « médical = bandages, désinfectant… » dans chaque fiche ; une fiche peut toutefois déclarer ses propres
catégories dans une section `[category …]` et rester autonome.

## Décisions

- **D01 — La fiche est la seule source d'une voix.** Identité, prompt, missions proposées et leurs paramètres, lieux,
  récompenses et troc vivent dans `personas/<id>.txt`. Ajouter une voix = déposer un fichier, sans toucher au code.
- **D02 — Registre des types de mission.** Chaque type est un fichier qui s'inscrit (`Types.register(name, def)`) et
  déclare : ses paramètres et leur validation, s'il peut être donné par une voix, son mode de remise (compte rendu
  radio, planque), ses lignes de carnet, son style de carte et sa description pour le modèle. Le carnet, la carte,
  `RS_MissionVoice` et le pont lisent ces déclarations ; plus aucun `if template == "…"` ni liste de noms hors du
  registre.
- **D03 — Un seul analyseur des fiches, côté serveur.** `RS_Persona` valide toute la fiche (sections comprises, avec
  les schémas déclarés par le registre). Le pont ne lit plus que l'identité et le prompt ; les missions permises, leurs
  descriptions et le contexte arrivent par la demande du serveur. Les listes fermées de `persona_store.py` et les
  branches `elif kind` de `radio_bridge.py` disparaissent.
- **D04 — Sections de la fiche** (format indicatif, figé par la première étape du plan ; la planque de l'exemple a des
  coordonnées fictives, à relever sur la carte) :

  ```text
  [place clinic]
  at=11880,6878,0
  label=West Point clinic
  use=mark,target          ; mark : repère donnable ; target : objectif de mission ; drop : planque

  [place drop_church]
  at=11795,6950,0
  label=Behind the Baptist church
  use=drop

  [mission secure_clinic]
  type=barricade
  target=clinic
  count=6
  after=clear_clinic       ; enchaînement : proposée après la réussite de clear_clinic
  weight=3                 ; poids du tirage parmi les missions disponibles
  story=I want to go back to my clinic, but not before every window is boarded.

  [mission meds]
  type=deliver
  items=medical            ; catégorie acceptée
  quantity=2-4
  drops=any                ; toutes les planques use=drop de la fiche, au choix du joueur (ou une liste : drops=drop_church,drop_mill)

  [rewards]
  pool=cache:medical:3, cache:food:2, frequency:1, stashmap:1, lesson:Doctor:2   ; type:paramètre:poids
  ```

  Les lignes simples actuelles (`id=`, `name=`, `listen=`…) et la section `[prompt]` restent.
- **D05 — Récompenses toujours aléatoires.** Tirage pondéré dans `pool`, puis contenu tiré dans la catégorie
  (objets et fourchettes de quantités du catalogue). Le cycle fixe de `RS_Rewards` et les tables figées de
  `RC_MissionConfig.Caches` cèdent la place au catalogue. Chaque nature de récompense (`cache`, `frequency`,
  `stashmap`, `lesson`) est une entrée d'un registre, un fichier chacune.
- **D06 — Remises réalistes, une seule règle pour toutes les voix.** Un dépôt est ramassé par la voix **seulement hors
  de vue de tout joueur** (case déchargée ou au-delà de la distance d'affichage) **et après un délai en heures de
  jeu** (valeur par défaut fixée au plan, de l'ordre d'une nuit). La carte d'identité, comme tout objet d'une mission
  de voix, se dépose à une planque ; le compte rendu radio ne retire plus rien de l'inventaire.
  Précision du 2026-11-14 (utilisateur) : **une mission propose plusieurs planques à la fois**. Le joueur dépose
  à celle de son choix parmi les planques de la mission (`drops=`), toutes marquées sur sa carte pendant la mission ;
  chacune est surveillée et ramassée par la même règle ; un dépôt partagé entre plusieurs planques se cumule jusqu'à
  la quantité demandée. Aucun tirage d'une planque unique.
- **D07 — Troc déclaré dans la fiche, état par marchand.** Une section `[trade]` porte le lieu de rendez-vous (un ou
  plusieurs lieux `use=landing`), la cadence, les heures, le stock (catégories) et le mode d'arrivée. Le moteur tient
  un état par marchand (plus `S.data.trade` unique). Les modes d'arrivée (barque, camion, planque de route) sont un
  registre, un fichier chacun, avec leur cause dans le monde (moteur de bateau ou de camion entendu, échange hors de
  vue, délai de jeu). Gus passe à ce format sans changer de comportement visible, sauf le réalisme de D06.
- **D08 — Un marchand par ville vanilla**, ajoutés comme fiches seulement : passeurs en barque au bord de l'Ohio
  (Riverside, West Point, Brandenburg, Louisville) ; arrivée par la route ou une planque pour les villes de l'intérieur
  (Muldraugh, Rosewood, March Ridge, Ekron, Irvington, Echo Creek…). Coordonnées relevées sur la carte 42.22.
- **D09 — Darlene veut rentrer à sa clinique.** Elle l'a quittée après la nuit où elle a fermé la porte aux patients
  (secret existant) et se cache ailleurs ; elle veut y revenir, mais seulement une fois les lieux sûrs. Missions
  enchaînées (`after=`) : reconnaître la clinique → nettoyer les abords → barricader les fenêtres → y déposer des
  médicaments. La dernière réussite met sa fiche dans l'état « rentrée », point d'accroche pour Living Knox plus tard,
  sans dépendance de RadioSurvivor vers Living Knox.
- **D10 — Nouveaux types de mission pour les voix**, un fichier chacun : `barricade` (fenêtres barricadées d'un lieu
  `target`), `relay` (radio posée en hauteur, alimentée et allumée), `route` (points traversés dans l'ordre), `watch`
  (rester à un point d'observation une durée de jeu, puis compte rendu), `item` (objet personnel à trouver et déposer
  à une planque). Chaque vérification passe par une mécanique vanilla relevée dans les sources 42.22 avant le code.
- **D11 — Pas de reprise.** Mod non publié avec des sauvegardes à reprendre : les six fiches livrées sont réécrites au
  nouveau format, sans migration ni lecture de l'ancien format.

## Arbitrages ouverts

Aucun. Les valeurs par défaut (délai de ramassage, distance hors de vue, poids) se fixent dans le plan et restent
éditables dans la fiche.

## Conséquences

- Ajouter une voix, une mission d'une voix, un lieu de dépôt, une récompense ou un marchand : un fichier de fiche, sans
  code. Ajouter un **type** de mission, une **nature** de récompense ou un **mode d'arrivée** : un nouveau fichier Lua
  inscrit à son registre, sans modifier le moteur.
- Le pont devient plus simple (plus de second analyseur) mais dépend du contexte envoyé par le serveur : le protocole
  du carnet (`protocole-carnet-v2.md`) est mis à jour à la même étape.
- `persona-format.md` est réécrit avec le nouveau format ; les six fiches livrées et leurs empreintes
  (`RS_Personas.KNOWN_DELIVERED`) sont régénérées.
- Coût : chantier en plusieurs étapes ; les étapes de refactor (registres, analyseur unique) ne changent aucun
  comportement et sont prouvées par la suite existante avant tout ajout.
