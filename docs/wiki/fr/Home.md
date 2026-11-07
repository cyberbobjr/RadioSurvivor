*English: [Home](../en/Home.md)*

# Radio Survivor

Radio Survivor est un projet Project Zomboid **Build 42.21**, solo et multijoueur, publié comme **un seul objet
Workshop contenant trois mods**. Comté de Knox, juillet 1993 : des voix répondent à la radio, et des groupes de
survivants humains vivent, se battent et se fortifient dans le comté.

> **Version de test.** Attendez-vous à des bugs et à des changements d'équilibre. Commencez une nouvelle partie et
> gardez une copie des sauvegardes qui comptent.

## Les trois mods

| Mod | Mod ID | Apporte |
|---|---|---|
| Radio Survivor | `batman_RadioSurvivor` | La radio : six voix d'IA, l'onglet Radio du carnet, les factions |
| Living Knox | `batman_LivingKnox` | Des groupes de survivants PNJ : foyers, besoins, routines, combats |
| Radio Survivor Core | `batman_RadioSurvivorCore` | Ce que les deux partagent : missions et leur journal, lien avec le pont, identité, historique des échanges, réputation, carnet. Activé pour vous ; inutile seul |

Cochez **Radio Survivor**, **Living Knox** ou **les deux** : chacun fonctionne sans l'autre (le Core s'ajoute
toujours). Détails et ordre de chargement : [Installation](04-installation.md).

## Ce que les mods ajoutent

- **Des voix à la radio** (Radio Survivor) : Walt, une infirmière, un déserteur, une famille assiégée, une station
  pirate et un passeur, chacun sur une vraie fréquence tirée à chaque partie. Leurs fréquences se trouvent sur des
  notes dans le butin. On leur parle avec n'importe quelle radio émettrice tenue en main ou portée sur le dos (section
  **Émettre** de la fenêtre de la radio). Elles sont jouées par une IA et se souviennent de vous.
- **Carnet de terrain** (bouton **Carnet**) : contacts, missions, récompenses, réputation, et avec Radio Survivor
  l'historique radio par fréquence.
- **Groupes de survivants Living Knox** (Living Knox) : 3 à 5 groupes de PNJ humains avec un foyer, un chef, de
  vraies réserves, des besoins et des routines. Ils défendent et fortifient leur foyer, combattent les zombies et
  vivent hors écran. Colons, neutres et pillards.
- **Missions** : livrer, reconnaître, retrouver un disparu, nettoyer un lieu, récupérer une cache, faire un signal.
  Le serveur vérifie chaque objectif.
- **Secours** d'une famille assiégée, **le passeur de l'Ohio** (troc par radio), **chronique du soir** du serveur,
  **dernières pages** des morts, **réputation** (Radio Survivor).

Le serveur décide de tout : l'IA n'écrit que des paroles et choisit dans des listes fermées.

## Le pont

L'IA passe par **le pont**, un petit programme Python que vous lancez vous-même sur la machine qui exécute le serveur
(votre PC en solo). C'est le même programme quel que soit le choix de mods. Sans lui, le jeu reste jouable ; les voix
et les PNJ restent muets.

## Pages

- [Présentation](01-presentation.md) : les mods en images.
- [Installation et configuration](02-installation-et-configuration.md) : du Workshop à une partie où tout le monde parle.
- [Utilisation](03-utilisation.md) : guide du joueur pas à pas (radio, Ctrl+G, missions, carnet, outils d'admin).
- [Installation](04-installation.md) : quels mods cocher, mods requis, ordre de chargement, première partie.
- [Le pont en solo](05-pont-en-solo.md)
- [Le pont sur un serveur dédié](06-pont-sur-serveur-dedie.md)
- [Configurer le fournisseur d'IA](08-fournisseur-ia.md)
- [Options sandbox](09-options-sandbox.md)
- [Créer une voix radio](10-creer-une-voix-radio.md) : modifier une voix ou ajouter la vôtre.
- [Dépannage](11-depannage.md)
- [FAQ](12-faq.md)
