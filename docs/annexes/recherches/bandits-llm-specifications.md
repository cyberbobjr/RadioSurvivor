# RadioSurvivor et Bandits! Document de travail multijoueur

Mise à jour : 3 octobre 2026. Cible : Project Zomboid 42.21.0. Statut : décisions de conception,
avec une première implémentation expérimentale 0.2 du carnet, du chat B17 et de la livraison.
Le parcours est testé en simulation et le chargement du serveur dédié a été exercé ; aucune
interaction avec deux joueurs réels n'est validée. Les limites d'identité Bandits, de réputation,
d'attribution du tueur et de persistance après crash sont détaillées dans
[l'implémentation](../conception/carnet-implementation-04221.md) et [la validation](../tests/carnet-validation-04221.md).

Ce document prépare des PNJ Bandits! capables de parler avec les joueurs et de choisir leurs intentions grâce au LLM. La priorité est une expérience cohérente sur serveur multijoueur : un PNJ possède une seule identité, une mémoire commune et un état partagé, même quand plusieurs joueurs interagissent avec lui.

**Référence visuelle :** [échanges en jeu](../maquettes/interface-echanges-pz.html), avec offre, suivi,
sélection des fournitures, retour de quête et fiche PNJ. La [note ISUI](../maquettes/interface-echanges-pz-notes.md)
relie cette maquette à l'implémentation ; ses données restent fictives. B17 remplace sa fenêtre de
dialogue par le chat local vanilla dans le mod.

**Décision acceptée : chaque PNJ créé par Bandits! possède une personnalité individuelle dès son apparition.** Cette règle inclut les PNJ amicaux et hostiles, les membres ordinaires des groupes et les personnages nommés. L’accès à cette personnalité ne dépend pas d’une première rencontre avec un joueur.

**Décision acceptée : fiche immédiate côté serveur, enrichie ensuite par le LLM.** La personnalité structurée est disponible sans attendre un appel réseau. Le LLM ajoute un passé et une expression cohérents avec cette fiche, en préservant les traits déjà établis et les faits vécus.

**Décision acceptée : les relations évoluent dans les deux sens.** La personnalité et les événements vécus peuvent conduire un PNJ hostile à accepter une trêve ou une alliance, et un PNJ amical à devenir hostile. Le LLM choisit cette évolution dans les possibilités autorisées ; le serveur vérifie ses conditions et applique un résultat partagé.

**Décision acceptée : relations personnelles et accords de faction explicites.** Chaque PNJ peut avoir une attitude différente envers chaque personnage joueur. Des accords collectifs peuvent être négociés avec une faction de joueurs sans effacer ces relations individuelles.

**Décision acceptée : représentation des factions de joueurs.** Le propriétaire et les négociateurs qu’il désigne peuvent conclure des accords au nom de leur faction. Les autres membres négocient leurs relations personnelles.

**Décision acceptée : agression pendant une trêve.** Les PNJ peuvent se défendre immédiatement contre l’agresseur. Le LLM décide ensuite du maintien, d’une demande de réparation ou de la rupture de l’accord collectif, avec validation serveur. L’agression ne rompt pas automatiquement la trêve avec toute la faction.

**Décision acceptée : proximité et radio pour les PNJ équipés.** Les joueurs peuvent s’adresser aux PNJ présents à proximité et contacter par radio ceux qui disposent d’un équipement utilisable. Les conditions de communication et la présentation sont précisées dans ADR B04.

**Décision actualisée : dialogue de proximité dans le chat normal.** Après désignation d’un interlocuteur, le joueur utilise le canal local habituel. RadioSurvivor relaie la demande au serveur et affiche les réponses du PNJ aux auditeurs admissibles. Le carnet conserve les informations et les transactions. Cette orientation remplace la fenêtre de saisie dédiée et le clic droit obligatoire ; voir [ADR B17](../../architecture/decisions/adr-b17-chat-proximite-pnj.md). L’intégration reste à valider en jeu.

**Décision acceptée : initiative des PNJ.** Un PNJ peut engager une conversation sur un événement pertinent, selon sa personnalité, à proximité ou par radio lorsqu’il est équipé. Les limites de fréquence évitent les sollicitations répétitives.

**Décision acceptée : observations personnelles et échanges parlés entre PNJ.** Chaque PNJ apprend ce qu’il observe ou entend et peut transmettre des informations à d’autres PNJ par une conversation de proximité ou par radio. Ces échanges sont rendus en jeu et peuvent être entendus par les joueurs lorsque les conditions de réception le permettent.

**Décision actualisée : rumeurs abandonnées.** Aucun système de génération, propagation ou crédibilité des rumeurs n’est prévu. Les mensonges et omissions de dialogue précédemment acceptés restent distincts ; les paroles seules ne modifient pas la réputation. Les échanges entre PNJ restent prévus pour discuter de leurs observations et informations connues.

**Fonctionnalité demandée : réputation des personnages.** Elle influence la confiance des PNJ, sans mécanisme de rumeur. L’utilisateur propose désormais de la centrer sur les missions et le comportement envers les PNJ ; les détecteurs PvP, de vols et de destructions sont mis de côté pour le périmètre initial. Les règles détaillées de malus restent à discuter.

**Décision acceptée : réputation par personnage, dans un mod autonome avec API publique.** Un nouveau personnage possède une réputation indépendante, permettant au joueur de changer de rôle RP. RadioSurvivor consulte ce mod et lui soumet les événements de ses missions ; d’autres mods peuvent lire la réputation et y contribuer selon leurs propres mécaniques. Voir le [document de conception de l’API](../../reputation-api-specifications.md).

**Décision acceptée : une réputation globale unique.** Chaque mod contributeur peut la faire augmenter ou diminuer avec un motif ; aucun système de réputation à plusieurs axes n’est prévu.

**Décision acceptée : trois niveaux de réputation visibles.** « Mauvaise », « neutre », « bonne », accompagnés des derniers actes expliquant les changements. Ces niveaux restent distincts de la confiance personnelle de chaque PNJ.

**Décision acceptée : fiche autonome « Ma réputation ».** Le mod de réputation fournit sa propre fiche, utilisable sans RadioSurvivor, avec le niveau du personnage et ses derniers gains et malus accompagnés de leurs motifs. L’accès par clic droit précédemment accepté est remis en discussion : l’utilisateur souhaite éviter l’accumulation de menus contextuels.

**Décision acceptée : amélioration de la réputation par les actes et missions.** Les actes positifs et les missions validés peuvent améliorer une mauvaise réputation ; aucune amélioration automatique par le temps écoulé n’est prévue.

**Décision acceptée : réputation neutre à la création d’un personnage.** Chaque nouveau personnage commence sans bonus ni malus hérité ; ses actes ultérieurs font évoluer sa réputation.

**Décision acceptée : missions accessibles malgré une mauvaise réputation.** Certains PNJ proposent encore des missions simples permettant de se racheter ; les missions sensibles peuvent exiger davantage de confiance. Chaque PNJ conserve le choix de traiter avec le personnage.

**Décision acceptée : missions en groupe.** Plusieurs personnages peuvent s’inscrire explicitement auprès du PNJ pour une même mission. Cela ne crée pas de réputation collective : chaque personnage conserve sa propre réputation globale.

**Décision acceptée : résultat collectif identique pour les participants engagés.** Même gain de réputation en cas de réussite et même malus en cas d’échec ou d’abandon collectif, sans mesure de contribution individuelle. Les montants restent à définir.

**Décision acceptée : récompenses matérielles facultatives.** Certaines missions offrent des objets en plus du gain de réputation, annoncés avant acceptation. Les quantités et la répartition en groupe restent à définir.

**Décision acceptée : lot matériel fixe par mission.** La quantité totale annoncée ne dépend pas du nombre de participants ; ils se partagent ce lot. Chaque participant conserve le même gain personnel de réputation.

**Décision acceptée : récupération simple et partage libre.** N’importe quel participant engagé peut récupérer le lot auprès du PNJ via le carnet. Remise unique vérifiée côté serveur, identité du bénéficiaire visible dans la fiche commune ; les joueurs se partagent ensuite les objets librement.

**Décision acceptée : inscription confirmée personnellement.** Le chef invite les joueurs ; chacun accepte lui-même la mission. Une invitation non acceptée n’engage pas le personnage et ne produit aucun gain ou malus.

**Décision acceptée : commencer par les livraisons de fournitures.** Un PNJ demande des médicaments, de la nourriture ou des outils ; la remise effective valide la mission, seul ou en groupe.

**Décision acceptée : le LLM choisit les missions parmi les offres admissibles du serveur.** Le serveur prépare les possibilités selon les besoins et ressources du PNJ. Le LLM choisit la mission, le joueur destinataire et sa présentation selon la personnalité, la confiance personnelle et la réputation globale. Quantités, délais et récompenses restent encadrés côté serveur.

**Décision acceptée : offre fixe pour la première version, négociation reportée.** Le PNJ annonce les fournitures, le délai et la récompense ; le joueur accepte ou refuse. Il peut demander des précisions sans modifier les conditions de l’offre. La négociation ne fait pas partie du périmètre initial.

**Décision acceptée : toute mission de livraison possède un délai.** L’échéance est annoncée avant acceptation, y compris pour une livraison ordinaire. Les durées et le mode de décompte restent à définir.

**Décision acceptée : départ du chrono à la première acceptation.** La première acceptation effective démarre le délai. Les participants invités qui acceptent ensuite partagent le temps restant, sans réinitialisation ni prolongation.

**Décision acceptée : aucune pause du délai pendant les déconnexions.** Accepter la mission engage le personnage jusqu’au résultat ; l’absence de tous les participants ne suspend pas le décompte et une reconnexion ne le réinitialise pas.

**Décision acceptée : pause uniquement lorsque le serveur est arrêté.** Le chrono avance en temps réel pendant le fonctionnement du serveur, même vide ou avec une simulation du monde en pause. Il reprend avec le temps restant après un arrêt ; le temps passé serveur arrêté n’est pas décompté.

**Décision acceptée : livraisons partielles et progression commune.** Les participants peuvent remettre les fournitures en plusieurs fois. La mission réussit lorsque tous les besoins sont remplis dans le délai, sans gain de réputation distinct pour chaque remise partielle.

**Décision acceptée : fournitures livrées conservées.** En cas d’échec ou d’abandon, les objets déjà remis restent au PNJ, sans remboursement automatique. Cette condition est annoncée avant acceptation.

**Décision acceptée : annulation si le PNJ demandeur meurt pendant la mission.** La livraison devenue impossible est annulée, sans malus de réputation pour les participants.

**Décision acceptée : très forte baisse personnelle si un participant tue le PNJ demandeur.** L’annulation ne produit pas de malus collectif, mais l’auteur de la mort subit une très forte baisse de sa réputation globale. Ses coéquipiers ne sont pas pénalisés pour cet acte. Le montant reste à définir.

**Décision acceptée : fenêtre « Mes missions ».** Elle présente le PNJ demandeur, les fournitures livrées et restantes, le temps restant et les participants engagés. Elle appartient à RadioSurvivor ; la fiche autonome « Ma réputation » reste fournie par le mod de réputation.

**Décision acceptée : un carnet unique dans RadioSurvivor, maquette A « Carnet classique ».** Onglets Contacts, Missions et Réputation en haut, liste à gauche et fiche détaillée à droite. La maquette A constitue la référence de conception validée. Un seul bouton « Carnet » dans la barre latérale ouvre cette interface. Le mod de réputation conserve sa fiche autonome lorsqu’il est utilisé seul ; son accès autonome reste à choisir.

**Décision acceptée : remise depuis le carnet.** Le bouton « Livrer » dans l’onglet Missions est utilisable près du PNJ demandeur. Il présente les objets et quantités à remettre avant confirmation.

**Décision acceptée : fournitures équivalentes.** Chaque besoin affiche une liste d’objets acceptés ; une pièce remise vaut une unité, sans conversion de poids, calories ou puissance. Le serveur contrôle l’admissibilité.

**Orientation demandée : factoriser la gestion de réputation avec MilitaryDrop.** Le mod commun doit servir les deux projets. MilitaryDrop possède actuellement une confiance par station, dont les règles diffèrent de la réputation individuelle RadioSurvivor. Le partage du moteur et la fusion éventuelle des valeurs sont distingués dans [ADR R04](../../reputation-api-specifications.md) ; aucun refactoring Lua n’est réalisé par cette mise à jour documentaire.

**Décision acceptée : un chef décide, les membres peuvent contester ou refuser.** Les décisions collectives d’une bande viennent de son chef ; chaque membre conserve des réactions individuelles liées à sa personnalité, sa loyauté et ses relations.

**Décision acceptée : un PNJ peut quitter sa bande sur décision du LLM.** Le départ dépend de sa personnalité, de ses liens et des événements vécus. Il constitue une transition explicite validée par le serveur ; le PNJ conserve son identité et ses souvenirs.

**Décision acceptée : le départ conserve les trêves existantes du PNJ avec les autres factions.** Aucun délai provisoire ni renégociation ne découle du seul changement d’appartenance.

**Décision acceptée : le joueur peut intervenir dans une conversation entre PNJ qu’il entend.** Il s’adresse à l’un des interlocuteurs via « Parler ». Les PNJ peuvent lui répondre, l’ignorer ou poursuivre leur échange, selon leur personnalité et la situation.

**Fonctionnalité demandée : panneau de relation avec chaque PNJ.** Le joueur doit pouvoir consulter sa confiance, sa réputation pertinente, les trêves et alliances applicables, ses dernières conversations et ses notes personnelles pour comprendre l’évolution de la relation.

**Décision acceptée : confiance affichée par niveaux qualitatifs et tendance.** L’interface emploie des libellés compréhensibles plutôt qu’un score numérique. Les niveaux exacts et leurs seuils restent à définir.

La proposition de départ est de confier au LLM les décisions sociales et les objectifs durables. Le serveur valide ces choix et les traduit en comportements Bandits! ; les mouvements et réactions immédiates restent exécutés par le système du jeu. Cette frontière reste à discuter, point par point.

## Comment utiliser ce document

Le [carnet existant](../maquettes/note-de-travail.html) est l’artefact de travail Claude téléchargé, comme confirmé par l’utilisateur le 2 octobre 2026. Son contenu a été lu et reste la référence des fonctionnalités déjà retenues. Ce document le complète pour Bandits! sans remplacer ses décisions. Les éventuels commentaires distants ne sont pas inclus dans cette lecture locale.

Les statuts ont un sens précis : **existant** désigne le code lu ; **retenu dans le carnet** désigne une décision antérieure, parfois non implémentée ; **proposé** désigne une recommandation à discuter ; **à vérifier** désigne une capacité technique non établie. Une décision proposée ne devient acceptée qu’après notre échange.

Nous traitons une seule question de conception à la fois. Après chaque réponse, mettre à jour la spécification concernée, le statut de son ADR et le journal de décisions avant de passer au point suivant.

## État et preuves disponibles

| Élément | Constat et limite |
| --- | --- |
| RadioSurvivor | `id=batman_RadioSurvivor`, variante `42.21`, `versionMin=42.21`. Le code implémente Walt à la radio, avec un pont Python par fichiers. |
| Exécution observée | `<Zomboid>/console.txt:59` indique `version=42.21.0 4a0e9546ec`. Ce journal ne constitue pas un test de la future intégration. |
| Installation | `projectzomboid.jar` installé contient `4a0e9546ec` dans les constantes de `zombie/core/Core.class`, cohérent avec le journal. Les API Bandits! ne sont pas validées par cette concordance. |
| Validation antérieure | Le carnet rapporte un essai solo le 1 octobre 2026 et des tests multijoueurs simulés. Aucun nouvel essai en jeu n’a été effectué pour ce document. |
| Bandits! | [Page officielle](https://steamcommunity.com/workshop/filedetails/?id=3268487204) : titre `[B42] Bandits NPC`, auteur Slayer, Workshop `3268487204`, modId annoncé `Bandits2`, compatibilité annoncée B42.20+ solo et multijoueur. Cette annonce ne prouve pas la capacité de notre adaptateur à piloter les PNJ. |
| Sources Bandits! locales | Copie téléchargée et lue dans `<Steam>/steamapps/workshop/content/108600/3268487204/mods/Bandits`. Une variante numérique `42.20` et un dossier `common` sont présents. `42.20/mod.info:4` confirme `id=Bandits2` ; sa description annonce B42.20+ SP/MP. |
| Portée de l’analyse Bandits! | Analyse statique des sources de la variante `42.20`, candidate pour 42.21. Le journal inspecté ne confirme pas son chargement. Aucun essai Bandits! en 42.21 ni test de notre intégration n’a été effectué. |

## Analyse des sources Bandits!

Dans cette section, les chemins abrégés partent de `<Steam>/steamapps/workshop/content/108600/3268487204/mods/Bandits/42.20/media/lua`. Les constats portent uniquement sur la copie lue le 2 octobre 2026. Ce dossier reste en lecture seule.

### Simulation cliente et données serveur

`client/BanditUpdate.lua:2071` arrête la boucle sur un serveur dédié. Côté client, `GenerateTask` puis `ProcessTask` sont exécutées (`2263`, `2269`). Le serveur crée les cerveaux des PNJ, les range dans les clusters et les transmet (`server/BanditServerSpawner.lua:427`, `432`). `shared/BanditGMD.lua` organise 32 clusters en ModData, demandés et reçus par les clients.

Il serait incorrect de décrire toute l’IA comme exécutée par un unique client propriétaire. La boucle examinée n’applique pas ce filtre globalement. En revanche, les actions de mouvement vérifient `BanditUtils.IsController` avant certains appels de cheminement (`shared/ZombieActions/ZAGoTo.lua:41`, `ZAMove.lua:23`). Ce contrôleur est choisi par distance horizontale au PNJ parmi les joueurs en ligne (`shared/BanditUtils.lua:670`). Ce choix du mod est distinct de l’autorité réseau interne du moteur Java, qui n’a pas été auditée ici.

**Conséquence proposée :** le LLM tourne une seule fois côté serveur par décision. Les clients disposent du même objectif validé ; l’exécution respecte les gardes Bandits! existantes. Les confirmations d’effet doivent être ordonnées et dédupliquées côté serveur. Tester les changements de joueur le plus proche, les distances égales et les déconnexions.

### Extension des comportements sans remplacer la boucle

`client/BanditUpdate.lua:1980` génère les tâches dans cet ordre : endurance, santé, combat, collisions, puis programme personnalisé lorsqu’aucune tâche prioritaire n’est produite et qu’aucune tâche n’est en cours. Le programme est appelé par `ZombiePrograms[program.name][program.stage](bandit)` (`2039`) et retourne `status`, `next` et `tasks`.

**Point d’extension confirmé statiquement :** ajouter un programme nommé propre au mod, par exemple `ZombiePrograms.batman_RadioSurvivor`, puis traduire l’intention serveur en tâches connues. Cela évite de remplacer `BanditUpdate.lua`. Il faut initialiser ce registre sans écraser ceux des autres mods.

**Limite :** un programme personnalisé ne précède pas les réflexes de combat. « Se retirer » peut être retardé par le combat automatique ; un cessez-le-feu n’est pas obtenu en changeant seulement le nom du programme. Le catalogue doit distinguer l’objectif accepté de son exécution effective.

### Suivi de joueur et attente

`shared/ZombiePrograms/ZPCompanion.lua:26` retrouve le maître, adapté en multijoueur par `getPlayerByOnlineID` (`client/BanditPlayer.lua:44`). Le programme suit ce joueur mais peut aussi rejoindre un poste de garde ou s’approcher d’un ennemi proche. Sans maître disponible, il produit une tâche d’attente (`ZPCompanion.lua:27`). Le suivi natif n’est donc pas une escorte strictement conforme à une consigne LLM.

`client/BanditMenu.lua:182` montre le changement de maître et de programme, suivi d’une synchronisation partielle. `Bandit.SetProgram` existe (`shared/Bandit.lua:562`), mais son paramètre `programParams` n’est pas utilisé dans le corps lu et la fonction n’envoie pas de synchronisation. Ne pas lui passer une destination en supposant qu’elle sera appliquée.

**Proposition :** conserver nos paramètres d’objectif dans un état RadioSurvivor public minimal et utiliser un programme propre pour suivre, attendre ou rejoindre une destination. Réutiliser les helpers de tâches vérifiés, sans hériter implicitement de toutes les priorités de `Companion`.

### Texte libre et voix existantes

`Bandit.Say` (`shared/Bandit.lua:1193`) attend une catégorie présente dans `Bandit.SoundTab`, choisit un son enregistré et sa traduction. L’affichage utilise `zombie:addLineChatElement` (`1236`), avec une portée locale de 14 cases calculée pour le joueur du client (`1203`). Cette fonction n’est pas un canal de texte libre pour le LLM et ne fonctionne pas comme émetteur sur serveur dédié.

**Proposition :** le serveur crée un événement de parole avec identifiant, PNJ, texte, canal et échéance ; les clients admissibles le rendent une fois via le mécanisme de sous-titres existant. La portée exacte, les obstacles et la coexistence avec les répliques natives restent à spécifier. Le serveur choisit la réplique ; aucun client ne régénère son texte au LLM. L’audio enregistré Bandits! reste distinct d’une éventuelle synthèse vocale du texte libre.

### Hostilité et négociation entre factions

`brain.hostile` et `brain.hostileP` sont initialisés au spawn (`server/BanditServerSpawner.lua:396`) ; les setters existent (`shared/Bandit.lua:584`). `hostileP` n’est pas une liste de joueurs hostiles. `BanditUtils.AreEnemies` compare notamment clans, hostilité et loyauté (`shared/BanditUtils.lua:773`). Un clan Bandits! ne constitue pas une faction vanilla de joueurs.

Après une agression, `BanditPlayer.CheckFriendlyFire` peut rendre hostiles envers les joueurs les PNJ amicaux témoins à proximité, puis changer leur programme (`client/BanditPlayer.lua:106`). En présence de Week One, cette fonction délègue à son système de témoins (`90`).

**Conséquence :** un accord avec un joueur ou une faction ne doit pas se traduire naïvement par `hostileP=false`. Il faut décider si l’accord concerne tous les joueurs ou implémenter des relations ciblées et vérifier tous les chemins de sélection des ennemis. Une protection transitoire pendant une négociation doit également être appliquée avant les tâches de combat ; le dialogue seul n’arrête pas les tirs.

### Synchronisation des cerveaux

`BanditServer.Commands.BanditUpdatePart` copie les champs reçus dans le cerveau serveur et transmet le cluster (`server/BanditServerCommands.lua:68`). Le corps lu ne contient pas de contrôle du contrôleur, de révision ni de liste fermée des champs. Cela ne permet pas à RadioSurvivor de considérer cette commande comme une validation d’une décision LLM.

`BanditBrain.Get` retourne le cerveau de l’entité locale. Au premier rattachement, `Banditize` y installe la table du cluster (`client/BanditUpdate.lua:193`, `2140`). Mais `loadBanditModData` remplace ensuite la table du cluster reçue (`shared/BanditGMD.lua:62`) et la boucle ne rattache le cerveau à ce chemin que si l’entité n’est pas encore Bandits!. La propagation d’une nouvelle table au cerveau déjà actif n’est donc pas démontrée par ces chemins ; elle doit être testée explicitement.

**Proposition :** ajouter des commandes réseau sous l’espace de noms RadioSurvivor et un traitement client des intentions validées, appliquant les seuls champs nécessaires au cerveau actif. Conserver les champs de runtime tels que les tâches, la santé et les munitions ; ne pas remplacer tout le cerveau à chaque réponse. Pour les PNJ gérés, examiner aussi une protection ciblée contre les mises à jour natives qui contredisent une intention canonique. Le serveur conserve ses objectifs séparément des tables que les clients peuvent modifier.

### Identité et persistance

Les IDs des PNJ proviennent du `PersistentOutfitID`, avec normalisation du bit du chapeau (`shared/BanditUtils.lua:616`, `634`). Les joueurs sont référencés par leur `OnlineID` en multijoueur (`661`), insuffisant à lui seul pour une mémoire durable après reconnexion.

Le cerveau contient aussi `key`, `fullname`, `permanent` et `bornCoords` (`server/BanditServerSpawner.lua:303`, `410`). Ces champs offrent des pistes pour relier une identité narrative à une incarnation ; ils ne garantissent pas seuls sa persistance. `BanditPermanent.Check` est désactivée par un retour immédiat (`client/BanditPermanent.lua:8`). Des mécanismes de groupes virtuels et de restauration existent côté serveur, mais ne prouvent pas la survie individuelle d’un même PNJ : la restauration recrée une entité et son cerveau (`server/BanditServerSpawner.lua:557`).

**Proposition :** un ID narratif durable appartient à RadioSurvivor et se relie explicitement à chaque incarnation. Un déchargement de zone ne vaut ni mort ni retour à la position de naissance. Les personnages nommés ont besoin d’un protocole de reprise, à tester avant les secours persistants.

### Écarts entre le carnet et le prototype

Le carnet décrit des réponses structurées `say` et `actions`. Le prototype lit encore seulement des lignes de texte (`RadioSurvivor_Server.lua:123`, `radio_bridge.py:249`). Le catalogue d’actions constitue donc une conception retenue, pas un moteur d’actions disponible.

Le pont utilise quatre travailleurs (`radio_bridge.py:43`). Les verrous protègent les lectures et écritures d’historique, mais pas un tour de conversation complet (`prepare:149`, `append:159`). Deux demandes peuvent être préparées avec le même passé, puis enregistrées dans leur ordre de fin. C’est un risque de cohérence déduit du code, pas une panne reproduite en jeu.

La description de `mod.info:3` indique encore « Single-player only », malgré le chemin client/serveur du prototype. Le pont découpe à 100 caractères par ligne, contre une limite de 140 côté Lua. Ces écarts sont relevés pour une future intervention ; les fichiers du mod restent inchangés dans ce travail de conception.

## Fonctionnalités proposées

| Fonctionnalité | Expérience du joueur | Condition multijoueur |
| --- | --- | --- |
| Conversation de proximité, acceptée | S’adresser à un PNJ présent ; les joueurs admissibles à proximité entendent sa réponse. | Le serveur détermine interlocuteur et destinataires ; la présentation locale ne crée aucune autorité sur le PNJ. |
| Contact radio avec un PNJ équipé, accepté | Parler à distance à un PNJ disposant d’un équipement utilisable. | Vérifier équipement, fréquence et conditions de transmission ; le prototype de chaîne radio globale ne prouve pas la portée d’un émetteur mobile. |
| Initiative de conversation des PNJ, acceptée | Un PNJ interpelle un joueur, demande de l’aide ou appelle à la radio selon sa personnalité et un événement pertinent. | Une initiative décidée côté serveur rejoint l’ordre commun du PNJ ; délais et quotas limitent les répétitions. |
| Conversations entre PNJ, acceptées | Les PNJ se racontent des événements, interrogent leurs compagnons et réagissent selon leur personnalité ; les joueurs peuvent écouter les échanges admissibles. | Mémoire individuelle, réception vérifiée, tours ordonnés côté serveur et limites de longueur et de fréquence. |
| Négociation | Demander un passage, une aide, un cessez-le-feu ou discuter une menace. | Une seule négociation active par PNJ ou groupe ; les demandes concurrentes rejoignent un ordre commun. |
| Objectifs choisis par le LLM | Accepter une escorte, tenir un rendez-vous, refuser de suivre ou choisir un repli. | Chaque intention vient d’un catalogue que l’adaptateur sait réellement exécuter. |
| Mémoire et relations | Le PNJ reconnaît les personnages, retient une aide, un mensonge déclaré ou une agression observée. | Distinguer personnage, compte et faction. Un nouveau personnage n’hérite pas implicitement des relations du précédent. |
| Personnalités individuelles dans les groupes | Chaque membre a son propre tempérament, ses motivations et sa mémoire. | Un éventuel porte-parole représente le groupe sans remplacer les personnalités de ses membres ; les règles de décision collective restent à définir. |

Le périmètre décidé couvre tous les PNJ créés par Bandits!. Le budget règle la fréquence des consultations LLM et le nombre de décisions simultanées. Il ne réduit pas le nombre de PNJ dotés d’une personnalité. La création repose sur une fiche immédiate côté serveur, puis un enrichissement LLM asynchrone selon ADR B06. Elle ne bloque pas l’apparition ou la simulation des PNJ sur une réponse réseau.

« Faire parler » désigne d’abord le texte en jeu, à proximité et à la radio. Une voix audio synthétisée reste une extension distincte : transport du son, cache, spatialisation, interruption et synchronisation demanderaient une spécification supplémentaire.

### Une première rencontre concrète

Deux joueurs croisent une bande près d’une station-service. Le chef exige qu’ils restent à distance. L’un propose des médicaments contre un passage ; l’autre lui demande simultanément une escorte.

Le serveur ouvre une rencontre unique. Le LLM reçoit les deux interventions dans un ordre défini et choisit une intention parmi les possibilités offertes : refuser, négocier le passage ou proposer une condition. Le serveur réserve et vérifie cette condition. Les deux joueurs reçoivent le même résultat et entendent la même réplique. Si un coup de feu survient pendant l’attente, les réactions immédiates continuent et la décision devenue caduque est abandonnée.

Ce scénario sert de référence pour l’acceptation multijoueur. Les drapeaux d’hostilité existent, mais un cessez-le-feu ciblé par faction et une pause de négociation restent à développer et valider.

## ADR B01 Répartition des décisions

**Statut : accepté pour l’évolution des relations par le LLM avec validation serveur ; répartition des objectifs et réflexes immédiats encore proposée.** Prolonge la règle retenue dans le carnet : catalogue fermé et validation serveur.

**Contexte.** Le LLM répond de façon asynchrone ; la situation peut changer pendant sa réponse. Nous voulons des choix motivés par une personnalité sans suspendre la simulation.

**Choix proposé.** Le LLM sélectionne une intention admissible, son objectif et ses conditions. Le serveur vérifie l’état actuel, les droits et les ressources ; il applique le choix valide sans le remplacer arbitrairement. Bandits! exécute les gestes et réactions immédiates. En cas de refus technique, le modèle reçoit le résultat réel lors du prochain échange.

| Niveau | Responsable proposé | Exemple |
| --- | --- | --- |
| Personnalité et dialogue | LLM | Ton méfiant, souvenir d’une livraison, refus argumenté. |
| Décision sociale ou objectif | LLM parmi les possibilités serveur | Négocier, accompagner, rejoindre un lieu connu, se retirer. |
| Application et contraintes | Autorité RadioSurvivor côté serveur | Vérifier cible vivante, portée, ressources et validité de l’intention. |
| Exécution immédiate | Simulation Bandits! selon son architecture vérifiée | Cheminement, animation, tir et réactions au danger. |

**Conséquences.** Le PNJ peut prendre une vraie décision avec le LLM, mais ne reçoit jamais de Lua arbitraire à exécuter. L’évolution de ses relations amicales et hostiles est acceptée dans ADR B07. Son application exige une validation des transitions d’hostilité et de leur portée multijoueur. Cela n’acte pas le pilotage par le LLM de chaque tir ou geste de combat.

**Alternative.** Confier aussi les décisions tactiques fréquentes au LLM donnerait davantage de contrôle, mais imposerait une réponse rapide et des mécanismes de secours plus complexes. Ce niveau n’est pas retenu implicitement.

## ADR B02 Autorité serveur et adaptation Bandits!

**Statut : proposé ; mécanismes client/serveur identifiés statiquement, intégration à valider en jeu.**

Un seul pont LLM tourne près du serveur dédié. Les clients transmettent des demandes et affichent les événements autorisés. Ils ne choisissent ni l’état canonique, ni les récompenses, ni l’identité du PNJ.

Bandits! calcule ses tâches côté client. Certaines actions de mouvement sont réservées au contrôleur choisi par proximité ; toute la boucle n’est pas réservée à ce seul contrôleur. RadioSurvivor distribue donc une intention unique aux clients concernés et fait appliquer explicitement sa révision au cerveau actif. Les confirmations d’effet sont vérifiées et dédupliquées côté serveur. Les changements de contrôleur ne doivent ni multiplier les appels LLM, ni rejouer les conséquences matérielles.

Créer un adaptateur isolé, activable indépendamment du dialogue radio existant. Utiliser un programme propre dans `ZombiePrograms`, le réseau RadioSurvivor et les helpers de tâches Bandits! vérifiés. L’adaptateur annonce les capacités effectivement prises en charge et se désactive proprement si elles manquent. Une dépendance optionnelle ne doit pas empêcher Walt de fonctionner sans Bandits!. Tout remplacement de module exigerait une analyse de collision et de version. Aucune écriture dans les dossiers Workshop Steam.

**Condition de passage.** Démontrer avec un serveur dédié et deux clients qu’une intention produit un seul état cohérent, y compris après déconnexion du client qui simule éventuellement le PNJ. Si le serveur ne peut ni imposer ni suivre une intention de façon fiable, conserver le dialogue et bloquer les actions concernées.

## ADR B03 Identité et mémoire des PNJ

**Statut : observations personnelles et transmissions entre PNJ acceptées ; identité durable et schéma de mémoire proposés.** La couverture de tous les PNJ est acceptée dans ADR B06 ; leurs échanges sont décrits dans ADR B11.

Attribuer une identité persistante RadioSurvivor à chaque PNJ créé par Bandits! et la relier à l’ID Bandits! issu du `PersistentOutfitID`, sans confondre cet ID d’incarnation avec l’identité narrative. `brain.key` est un candidat pour le rattachement à vérifier. Les joueurs nécessitent eux aussi une identité durable distincte de leur `OnlineID`. Mort, déchargement de zone et reconnexion sont des événements différents.

La mémoire contient les événements observés, les engagements validés et les déclarations attribuées aux joueurs. Une affirmation du joueur reste une affirmation ; le LLM ne peut pas la convertir en transfert d’objets accompli. Les relations individuelles et de faction ont des champs distincts. La politique lors d’un changement de faction reste à définir dans un échange ultérieur.

**Connaissances acceptées.** Chaque PNJ dispose de ses observations et des messages effectivement reçus. Les PNJ peuvent se transmettre des informations par des échanges parlés à proximité ou à la radio. L’appartenance à une bande ne partage pas automatiquement leurs souvenirs. Un événement enregistré dans le monde par le serveur ne devient une connaissance du PNJ qu’avec une perception ou une transmission admissible.

**Mémoire proposée.** Conserver pour chaque information son contenu, sa source, sa date, le canal de réception et son lien avec un événement ou un échange. Distinguer observation directe, déclaration d’un joueur et témoignage d’un PNJ. Les déclarations ne deviennent pas des faits validés par leur répétition. Le système de rumeurs et de révision de croyances associé est abandonné. L’état effectif d’un accord collectif est géré séparément de la façon dont chacun en a appris les raisons.

L’état canonique et les secrets restent côté serveur ; les clients reçoivent ce qu’ils peuvent entendre ou consulter. L’historique du pont aide le dialogue mais ne constitue pas la preuve d’un engagement de gameplay. Une mort invalide les décisions en vol et empêche une réapparition sous la même identité par simple reprise d’une réponse tardive.

## ADR B04 Ordre des échanges et portée de la parole

**Statut : proximité, radio pour les PNJ équipés et initiative sur événements pertinents acceptés ; accès local actualisé par [ADR B17](../../architecture/decisions/adr-b17-chat-proximite-pnj.md) ; ordre et conditions de réception à valider.**

**Canaux acceptés.** Le dialogue fonctionne à proximité des PNJ physiquement présents et par radio pour les PNJ disposant d’un équipement utilisable. La capacité de recevoir un appel n’implique pas une obligation de répondre ou de coopérer : personnalité, état courant et événement en cours alimentent le choix du PNJ.

**Proximité proposée.** Le joueur désigne un interlocuteur identifié ; le serveur vérifie sa présence et les conditions de communication. Une réplique constitue un événement audible par les joueurs admissibles présents, avec un rendu local cohérent. Les distances, les obstacles et les différences entre parler et crier restent à spécifier à partir des mécanismes du jeu. Une conversation textuelle ne suspend pas la simulation du serveur ni les réactions immédiates du PNJ.

**Radio proposée.** Le joueur doit connaître ou trouver la fréquence de contact et disposer d’un moyen d’émission adapté. Le PNJ possède une radio utilisable, avec son état, sa fréquence et ses capacités de transmission. Les contrôles d’allumage, d’alimentation, de portée et de micro doivent s’appuyer sur les données réellement disponibles et les mécanismes vérifiés du jeu. Équiper un PNJ d’une radio ne crée pas implicitement un émetteur global comparable à Walt. Le comportement des contacts radio quand leur incarnation physique est déchargée reste à concevoir.

**Interface de proximité actualisée par ADR B17.** Désigner un PNJ, puis écrire dans le chat local normal. Une touche configurable et le bouton « Parler » de sa fiche sont proposés pour sélectionner l’interlocuteur, sans menu contextuel obligatoire. Le serveur produit une seule réponse et la diffuse depuis la position du PNJ aux joueurs admissibles ; les clients l’affichent dans le chat existant. Le destinataire reste explicite lorsque plusieurs PNJ sont présents. Aucun accès aux pensées du PNJ ou aux conversations non entendues. La maquette HTML conserve pour l’instant son ancienne fenêtre de saisie et doit être adaptée lors de l’implémentation Lua.

**Interface radio retenue dans le carnet.** Utiliser le carnet radio et le module « Émettre » de la fenêtre radio vanilla déjà décidés. Leur raccordement aux contacts Bandits! reste à développer. Ce choix de dialogue de proximité ne remplace pas l’interface radio.

**Ordre proposé.** Sérialiser les tours par PNJ, ou par groupe lorsqu’un représentant parle pour lui. Autoriser le parallélisme entre rencontres indépendantes. Les sollicitations par proximité et radio d’un même PNJ rejoignent un ordre commun ; une décision reçue sur un canal ne crée pas un second état pour l’autre. Le serveur attribue un numéro d’ordre ; le pont ne décide pas du gagnant selon la vitesse de réponse du fournisseur.

Diffuser chaque réplique selon son canal : auditeurs admissibles à proximité ou réception radio admissible. Deux langues client ne doivent pas provoquer deux décisions différentes. Le texte original est unique ; une éventuelle traduction est une présentation du même événement.

Une conversation privée à proximité ne devient pas automatiquement une connaissance de toute la faction. Le PNJ connaît uniquement les faits issus des perceptions vérifiées, des transmissions reçues ou de sa fiche narrative.

**Validation proposée.** Tester deux joueurs près d’un PNJ et un autre sur sa fréquence, une demande simultanée sur les deux canaux, une radio éteinte ou hors portée et une sortie de portée pendant l’attente du LLM. Les effets de gameplay validés et l’audition d’une réplique sont des événements distincts : manquer la réception ne réinitialise ni l’accord ni la mémoire du PNJ.

**Initiative acceptée.** Un PNJ peut engager une conversation selon sa personnalité et un événement pertinent qu’il perçoit : arrivée d’un inconnu, menace, besoin d’aide, retrouvailles ou contact radio. Le LLM décide de la prise de parole dans les conditions vérifiées par le serveur. Les limites de fréquence font partie du choix retenu ; leurs valeurs restent à régler. Les personnages radio existants conservent leurs règles propres.

**Traitement proposé.** Le serveur attribue un identifiant à l’événement déclencheur, vérifie le contexte connu du PNJ et regroupe les répétitions d’un même événement. Une initiative rejoint la même file que les sollicitations des joueurs et devient caduque si sa situation change. Des délais par PNJ et destinataire empêchent de relancer la même interpellation à chaque passage dans la portée. Le rendu spontané produit une réplique audible sans ouvrir automatiquement une fenêtre. La coordination des membres d’une bande pour éviter des interpellations simultanées reste à définir ; elle conserve la personnalité de chacun.

**Validation des initiatives proposée.** Tester une arrivée simultanée de plusieurs joueurs, une sortie puis un retour rapide dans la portée, un appel radio pendant un dialogue local et une réponse tardive après la disparition de l’événement déclencheur. Vérifier une seule initiative par événement admissible, un ordre commun et l’absence de répétition après reconnexion. Le pont arrêté conserve la simulation et les répliques natives ; il ne crée aucune nouvelle décision LLM.

## ADR B05 Délais et budget

**Statut : proposé ; valeurs à régler après mesure.**

Déclencher le LLM sur un événement significatif : parole reçue, rencontre, livraison, danger nouveau ou objectif terminé. Ne pas appeler le modèle à chaque tick. Limiter le nombre de décisions simultanées et répartir les consultations entre les PNJ selon les événements et leur ancienneté dans la file. Chaque PNJ conserve sa personnalité lorsque son appel est différé. Un éventuel regroupement de décisions pour une bande doit conserver l’identité et les motivations de chacun.

Le plafond actuel de 60 demandes par heure réelle est une limite du prototype radio, pas une estimation de coût pour tous les PNJ. Prévoir des quotas partagés, une réserve pour les dialogues de joueurs et une mesure du nombre réel d’appels fournisseur, y compris les nouvelles tentatives.

Si le pont manque, si le budget est épuisé ou si une réponse arrive trop tard, le PNJ continue son comportement déterministe. Une courte réplique de secours peut annoncer son indisponibilité. Aucun engagement matériel nouveau n’est inventé. Le délai de 90 secondes du prototype ne convient pas par défaut à une rencontre locale ; fixer une échéance par type d’intention après observation des temps de réponse.

## ADR B06 Personnalité individuelle pour chaque PNJ Bandits!

**Statut : accepté pour le périmètre et la création par fiche immédiate côté serveur, enrichie ensuite par le LLM ; schéma et rattachement technique à définir.** Chaque PNJ spawné par Bandits! doit avoir une personnalité disponible dès son apparition.

**Périmètre.** Tous les PNJ vivants créés par Bandits! sont couverts, quelle que soit leur attitude ou leur place dans un groupe. La personnalité existe dès la création et reste la même lors d’une rencontre ultérieure. Les PNJ virtuels destinés à recevoir une incarnation physique doivent conserver leur identité lors de cette transition. Les cadavres de scènes décoratives n’acquièrent pas automatiquement une vie ou une conversation ; leur éventuelle biographie est un sujet distinct.

**Fondation disponible.** `makeBrain` crée déjà `brain.personality` et des particularités individuelles (`server/BanditServerSpawner.lua:376`), puis un nom (`417`). Ces propriétés natives sont préservées et peuvent contribuer au contexte LLM. Elles ne suffisent pas à définir une personnalité narrative complète : addictions et collections ne décrivent pas à elles seules valeurs, peurs ou motivations.

**Fiche proposée.** Chaque personnalité comporte une identité, un tempérament, des valeurs, des motivations, des peurs, une manière de parler et un passé compatible avec la situation. Distinguer le socle durable de l’état courant : une blessure, la faim ou une trahison peuvent modifier son humeur et ses choix sans lui réattribuer une autre personnalité. Le nom natif, le clan et les traits observés servent de contraintes de cohérence ; les souvenirs d’événements réels viennent de la mémoire serveur.

**Création acceptée.** Le serveur attribue immédiatement une fiche individuelle structurée et persistante. Le LLM l’enrichit ensuite de façon asynchrone dans ces contraintes ; un enrichissement tardif ne réécrit ni les traits déjà utilisés ni les faits vécus. Aucun client ne tire sa propre personnalité et aucun redémarrage ne la régénère. Le schéma exact et les règles de génération restent à spécifier.

**Génération proposée.** Construire le socle avec des valeurs bornées et des combinaisons cohérentes : prudence, sociabilité, empathie, loyauté, ambition, valeurs prioritaires, motivations et peurs. Tenir compte du clan, de l’occupation et des particularités natives sans donner la même fiche à tous les membres. Conserver le résultat et la version du générateur afin qu’un changement ultérieur de règles ne transforme pas les PNJ existants. Ces axes constituent une proposition de schéma, pas des paramètres décidés individuellement.

**Enrichissement proposé.** Le pont reçoit la fiche, les contraintes narratives et les faits connus. Il retourne des champs autorisés : éléments de passé compatibles, habitudes d’expression, aspirations détaillées. Le serveur vérifie la révision et les champs avant de fusionner la réponse. Les relations, les événements réellement vécus et les accords sont des données séparées ; cet appel ne les modifie pas. Une histoire de famille inventée pour le passé ne crée pas automatiquement un autre PNJ ou une mission dans le monde.

**Continuité multijoueur proposée.** Une seule demande d’enrichissement active par identité narrative. Pendant l’attente, les dialogues et décisions utilisent la fiche déjà disponible. Les décisions et incidents actifs passent avant les enrichissements de fond dans la file du pont. Un échec conserve la fiche et permet une nouvelle tentative bornée. Une reprise retrouve la fiche et l’état de son enrichissement ; une réponse périmée ne remplace pas les données actuelles. Vérifier une vague nombreuse de spawns avec le pont absent puis rétabli, sans perte de personnalité ni doublons d’enrichissement.

**Rattachement technique à établir.** Dans les sources lues, `makeBrain` et `banditize` sont locales au fichier serveur. Les créations physiques passent par l’écriture d’un cerveau dans un cluster puis sa transmission (`432`), et `spawnVirtual` écrit aussi dans un cluster (`552`). Aucun événement public de création couvrant ces chemins n’a été identifié. Il faut instrumenter depuis notre mod les chemins vérifiés et contrôler la couverture des clusters. Un balayage périodique peut assurer une réconciliation, mais ne suffit pas à prouver une attribution exactement au moment du spawn. Le test doit établir que la personnalité est attribuée avant toute utilisation par le dialogue ou la décision LLM.

**Garanties multijoueurs à spécifier.** Une seule fiche canonique par identité narrative, créée côté serveur. Les générations ou enrichissements reçoivent un identifiant et une révision ; une réponse tardive pour un PNJ mort est rejetée. La recréation d’une incarnation retrouve sa fiche. Les secrets narratifs restent hors des clusters ModData diffusés aux clients ; ils reçoivent les seules données publiques nécessaires. Les PNJ déjà présents lors de l’activation de l’intégration doivent également obtenir une fiche par réconciliation.

**Conséquences.** Une bande peut réunir un membre prudent, un chef ambitieux et un membre compatissant. Chacun possède une personnalité même lorsqu’un seul parle. Le chef décide des objectifs collectifs, et les membres peuvent contester ou refuser selon leur personnalité et leur loyauté, comme accepté dans ADR B12. La désignation du chef et le périmètre de ses mandats restent à définir.

## ADR B07 Évolution des relations dans les deux sens

**Statut : accepté pour le principe et la combinaison des relations personnelles avec des accords de faction explicites ; mécanismes d’application à définir.** L’utilisateur accepte explicitement que les relations puissent évoluer dans les deux sens. Leur portée est précisée dans ADR B08.

**Décision.** L’attitude initiale de Bandits! constitue le point de départ d’une relation qui peut évoluer. Le LLM peut choisir une trêve, un rapprochement, une alliance, une rupture ou une hostilité, en s’appuyant sur la personnalité individuelle et les événements connus du PNJ. Chaque changement est validé et enregistré côté serveur, puis appliqué de façon cohérente aux clients concernés.

**Contrat proposé.** Une transition porte l’identité du PNJ, la cible de la relation, son état précédent, son nouvel état, sa révision et les événements qui la motivent. Les états exacts et leurs effets restent à spécifier. Une déclaration de joueur peut influencer le dialogue ; seules les preuves reconnues par le serveur établissent une livraison, une attaque ou l’exécution d’un engagement. Une évolution contraire au contexte actuel est refusée et son résultat réel revient dans la mémoire du PNJ.

**Exemples de comportement souhaité.** Un PNJ hostile peut accepter une trêve après une aide et rester prudent. Un allié peut rompre sa coopération après une trahison observée. Un refus de rendre un service ne rend pas automatiquement le PNJ hostile. Les membres d’une bande conservent leurs dispositions individuelles ; le partage des témoignages et la portée d’un accord collectif restent à décider.

**Application multijoueur proposée.** Les changements sont ordonnés par relation et protégés contre les réponses LLM périmées. Un accord n’est annoncé comme effectif qu’après son application ; les tâches de combat déjà en cours doivent être examinées lors d’une trêve. Une reprise de sauvegarde conserve les relations enregistrées. Une déconnexion ne provoque pas leur réinitialisation.

**Limite technique confirmée.** Les drapeaux natifs `hostile` et `hostileP` ne fournissent pas à eux seuls une relation distincte pour chaque joueur ou faction. L’adaptateur doit traiter les chemins de ciblage, les réactions des témoins et les mises à jour de programme ; un simple changement de drapeau ne prouve pas qu’une trêve est effective. Le mécanisme de réaction immédiate à une nouvelle agression pendant une trêve reste à définir.

**Portée acceptée.** Les relations sont personnelles et peuvent être complétées par des accords de faction explicites, comme décrit dans ADR B08. Le droit de représenter une faction reste à décider puis à vérifier côté serveur.

## ADR B08 Relations personnelles et accords de faction

**Statut : accepté pour le modèle et les représentants autorisés ; règles de priorité proposées.** L’utilisateur choisit les relations personnelles complétées par des accords de faction explicitement négociés. Les mandats sont précisés dans ADR B09.

**Décision.** Chaque PNJ possède des relations distinctes avec les personnages joueurs. Un accord de faction constitue un engagement collectif enregistré séparément. Un PNJ peut apprécier Alice, se méfier de Bob et respecter une trêve avec leur faction. Appartenir à cette faction ne rend pas automatiquement tous ses membres amis du PNJ.

**Données proposées.** Une relation personnelle relie l’identité narrative du PNJ à l’identité persistante du personnage joueur, avec son attitude, ses souvenirs et sa révision. Un accord relie une faction de joueurs identifiée durablement à un PNJ ou à un groupe de PNJ explicitement représenté. Il porte son type, son périmètre, ses conditions, son état, les signataires et, si nécessaire, sa durée. Le clan Bandits! ne remplace pas l’identité de faction vanilla ; les deux systèmes restent distincts.

**Représentation acceptée.** Le propriétaire et ses négociateurs désignés peuvent engager la faction de joueurs ; chaque joueur peut négocier pour lui-même. Préciser dans chaque échange la qualité en laquelle il intervient. Le serveur vérifie son appartenance et son droit de représentation à l’ouverture de la négociation et au moment de conclure. La phrase « je parle pour tout le monde » ne confère aucun droit. Côté PNJ, un individu n’engage une bande que si un mandat de représentation est défini ; le chef ou porte-parole n’est pas automatiquement habilité par cette décision.

**Gestion d’incident acceptée.** Une nouvelle agression permet une défense ciblée contre son auteur, puis le LLM décide du devenir de la trêve selon ADR B10. Les autres membres de la faction restent couverts tant qu’une décision collective validée ne change pas l’accord. La règle générale de priorité entre une relation personnelle défavorable et une trêve reste proposée : la trêve impose la non-agression dans son périmètre, tandis que la méfiance peut modifier le dialogue et la volonté d’aider.

**Persistance proposée.** Conserver séparément les souvenirs personnels et les accords collectifs. Un départ de faction ne supprime pas les souvenirs du PNJ. Définir ultérieurement si les accords couvrent les membres actuels, les membres présents à la signature ou une liste explicite. Un renommage de faction ou une reconnexion ne doit pas déplacer un accord vers un autre groupe ; l’identifiant durable propre au mod prévu dans le carnet reste à concevoir et valider.

**Condition multijoueur.** Le serveur calcule les effets d’un accord pour une cible donnée et distribue la même révision aux clients. Le modèle peut choisir des conditions parmi les possibilités autorisées ; il ne crée pas de signataire, de mandat ou de membre de faction. Les transitions individuelles et collectives restent traçables séparément pour expliquer une attitude sans révéler les secrets narratifs.

## ADR B09 Mandats de négociation des factions de joueurs

**Statut : accepté pour les personnes autorisées ; gestion des mandats proposée.** Le propriétaire et les négociateurs qu’il désigne peuvent conclure des accords collectifs.

**Décision.** Le propriétaire est habilité à représenter sa faction et à désigner ses négociateurs. Les membres désignés peuvent conclure les accords collectifs autorisés par le système. Une personne sans mandat peut discuter, exprimer une intention ou négocier pour elle-même ; elle ne peut pas engager sa faction. Le LLM reçoit les droits vérifiés par le serveur et ne peut ni les accorder ni les élargir.

**Gestion proposée.** Un registre serveur RadioSurvivor conserve les désignations, reliées à l’identité durable de la faction et à une identité de joueur à définir précisément. Le propriétaire peut retirer une désignation. Le serveur vérifie les droits lors de l’ouverture et lors de la conclusion ; une révocation en cours de conversation empêche toute nouvelle signature collective. Un départ de faction retire le droit d’agir pour celle-ci. Les accords déjà conclus restent distincts du mandat de leur signataire : révoquer un négociateur ne les annule pas automatiquement.

**Points de continuité à définir.** La persistance du mandat après mort du personnage, le changement de propriétaire et la réattribution d’une faction demandent des règles explicites. Un `OnlineID` temporaire ne suffit pas pour identifier durablement un négociateur. L’interface de désignation reste à concevoir ; ces délégations ne sont pas présentées comme une capacité native de la faction vanilla.

**Validation multijoueur.** Tester un membre sans mandat, un négociateur autorisé, une révocation pendant un appel LLM et deux négociateurs concluant des propositions incompatibles. Le serveur sérialise les conclusions sur un même accord et contrôle leur révision. Aucun accord ne devient effectif par la seule formulation du texte du PNJ.

## ADR B10 Défense ciblée et décision sur la trêve

**Statut : accepté pour le principe ; attribution des agressions, limites de défense et application à valider.** L’utilisateur choisit une défense ciblée, suivie d’une décision du LLM sur le sort de la trêve.

**Décision.** Une agression contre un PNJ protégé par une trêve ouvre un incident attribué à son auteur. Les PNJ concernés peuvent se défendre immédiatement contre cet agresseur. Cette réaction n’attend pas la réponse du LLM. L’accord collectif conserve son état jusqu’à une nouvelle décision validée ; les autres membres de la faction ne deviennent pas des cibles par leur seule appartenance.

**Évaluation par le LLM.** Fournir les faits établis de l’incident, les informations réellement connues des PNJ, leurs personnalités, les événements antérieurs pertinents et les conditions de l’accord. Le modèle peut choisir de maintenir la trêve, demander une réparation ou la rompre. Le serveur vérifie la cible, la révision de l’accord, les conditions et les conséquences autorisées avant application. Les réparations matérielles proviennent des catégories et bornes autorisées par le serveur.

**Suivi proposé.** Chaque incident possède un identifiant, son auteur, les victimes, l’accord concerné et une révision. Regrouper les nouveaux faits d’un même incident pour éviter plusieurs décisions contradictoires ou un appel LLM par coup reçu. Une réponse devenue caduque après une nouvelle agression est revalidée ou rejetée. Une réaction de défense ne doit pas être enregistrée comme une attaque initiale et déclencher une escalade en boucle.

**Pont indisponible.** La défense reste ciblée et l’accord collectif n’est pas automatiquement rompu. L’évaluation reste en attente avec un contexte borné ; une reprise doit tenir compte des faits nouveaux avant toute application. Les conditions d’arrêt de la défense et le traitement d’un tir accidentel restent à définir. Le système ne prétend pas connaître l’intention réelle du joueur à partir d’un seul dommage.

**Limite Bandits!.** `hostileP=true` et la réaction native des témoins peuvent étendre l’hostilité à tous les joueurs. Ils ne réalisent pas la défense ciblée décidée ici. Il faut adapter le ciblage et les réactions des PNJ concernés depuis notre mod, puis tester avec plusieurs membres d’une faction et des joueurs tiers. Un simple changement de programme ou de drapeau ne suffit pas à valider ce comportement.

**Critères d’acceptation.** Tester un agresseur et un membre innocent de sa faction présents simultanément, un joueur tiers, deux agressions rapprochées, la réponse LLM tardive et le pont arrêté. Vérifier que la défense vise uniquement les auteurs reconnus, que l’accord change une seule fois par décision valide et que tous les clients observent les mêmes effets.

## ADR B11 Conversations et transmissions entre PNJ

**Statut : connaissances individuelles, conversations entre PNJ et intervention du joueur acceptées ; rumeurs abandonnées ; déroulement proposé.** Les mensonges et omissions de dialogue restent autorisés selon la personnalité, sans système de propagation de rumeurs.

**Décision.** Un PNJ peut choisir de raconter à un autre ce qu’il sait, lui poser une question ou réagir à ses propos. Les échanges utilisent la proximité ou la radio pour les PNJ équipés. La réception effective alimente la mémoire de chaque auditeur admissible, sans partage instantané de toute la mémoire de la bande. Les joueurs proches ou capables de recevoir la transmission peuvent entendre les répliques, avec les mêmes règles de portée que les autres conversations.

**Intervention du joueur — décision acceptée.** Un joueur qui entend l’échange peut s’adresser à l’un des PNJ via « Parler ». Il peut poser une question ou prendre part à une négociation spontanée. Le LLM choisit la réaction des interlocuteurs selon leur personnalité, leurs relations et la situation : répondre au joueur, l’ignorer ou poursuivre leur discussion. Cette intervention n’impose ni réponse ni acceptation de ses propos et ne lui confère aucun mandat de faction supplémentaire.

**Ordonnancement multijoueur proposé.** Le serveur vérifie la réception admissible et le destinataire, puis inscrit le message dans la conversation commune. Plusieurs interventions suivent un ordre unique côté serveur et les limites de fréquence existantes. Une réponse LLM déjà en attente est revalidée avec les nouveaux tours ; elle ne doit pas écraser une intervention récente. Les propos sont diffusés aux seuls auditeurs admissibles et ne révèlent pas les échanges antérieurs que le joueur n’a pas entendus. La priorité exacte entre intervention, tour en cours et événement urgent reste à spécifier.

**Déroulement proposé.** Le serveur crée une conversation identifiée avec des participants, un canal, un sujet et un nombre maximal de tours. Pour chaque locuteur, le pont reçoit sa personnalité et ses seules connaissances utiles, plus les répliques qu’il a effectivement reçues. Le LLM décide quoi dire, transmettre ou garder pour lui. Le serveur vérifie les références d’information, l’état des interlocuteurs et le canal avant diffusion. Un autre PNJ répond à partir de son propre contexte ; la voix et la mémoire de chacun restent distinctes.

**Transmission proposée.** Associer les informations transmises aux passages qui les expriment. Le destinataire apprend un récit seulement après une réception admissible, pas à la préparation du texte. Conserver la source initiale et la chaîne de transmission afin qu’un récit répété ne devienne pas plusieurs preuves indépendantes. Un déplacement hors portée, une radio indisponible ou une interruption peuvent empêcher la réception d’une partie de l’échange.

**Fiabilité des propos.** Les PNJ peuvent mentir ou omettre des détails selon leur personnalité et leurs intérêts. Le dialogue n’indique pas automatiquement au joueur qu’un propos est un mensonge. Cette possibilité narrative n’implique aucun système de rumeurs et ne permet pas de pénaliser la réputation d’un joueur sur la seule base d’une accusation verbale.

**Traitement des propos proposé.** Séparer les événements du monde et les affirmations émises. Une phrase ne crée pas l’événement qu’elle décrit, ne transfère pas d’objet et n’accomplit pas une mission. Le contexte d’un PNJ reste limité à ses connaissances admissibles. La réputation repose sur le registre d’événements serveur de l’ADR B15.

**Choix narratif proposé.** Le LLM peut sélectionner une stratégie de parole telle que récit sincère, omission ou tromperie motivée, avec un contenu borné aux sujets et références autorisés. Une tromperie délibérée doit être distinguée des incohérences involontaires de génération. Elle ne donne pas accès aux secrets que le locuteur ignore. Les effets matériels restent validés sur l’état réel du monde.

**Simplification retenue.** Supprimer le mécanisme proposé de crédibilité des rumeurs, de croyances dérivées et de révision par contradictions. Conserver les observations, les conversations et les événements utiles aux relations personnelles.

**Exemple.** Un témoin raconte : « Celui au manteau bleu a tiré sur Paul près de la pompe. » Son compagnon prudent demande : « Tu l’as vu toi-même ? » Le témoin répond selon les faits qu’il connaît. Un joueur à portée peut intervenir via « Parler » pour raconter sa version. Le PNJ peut l’écouter, le questionner ou poursuivre sa discussion ; la priorité technique de l’intervention reste à définir. Ni le dialogue ni l’enrichissement du passé ne créent rétroactivement l’attaque dans le monde.

**Budget et cohérence proposés.** Borner la durée, les tours et les reprises par sujet. Dédupliquer les faits déjà transmis et empêcher qu’une même information déclenche indéfiniment de nouvelles conversations. Un message joueur ou un incident urgent peut suspendre un échange de fond ; la politique de priorité reste à préciser. Conserver un état canonique côté serveur et les derniers tours nécessaires à la reprise. La transmission aux PNJ non chargés exige une simulation de contact explicite ; elle n’est pas présumée par cette décision.

**Validation.** Tester deux PNJ et deux joueurs dont un hors portée, une transmission radio reçue par une partie des participants, une répétition du même récit et une intervention du joueur. Vérifier que seuls les auditeurs admissibles apprennent les informations, qu’une affirmation ne crée aucun événement réel ni changement de réputation et que les conversations se terminent sans boucle. Ces tests restent à réaliser ; les sources Bandits! lues ne fournissent pas déjà ce protocole d’échange LLM.

## ADR B12 Chef de bande et réactions individuelles

**Statut : accepté pour la décision du chef et le droit des membres de contester ou refuser ; organisation de la bande et conséquences du refus proposées.**

**Décision.** Une bande possède un chef identifié qui prend ses décisions collectives. Chaque membre garde sa personnalité, ses connaissances et ses relations. Le LLM choisit sa réaction à un ordre : l’accepter, le contester ou refuser de le suivre, selon les informations qu’il a reçues et ses motivations. L’unanimité des membres n’est pas une condition pour que le chef prenne une décision.

**Cycle proposé.** Le serveur enregistre un ordre collectif identifié, son auteur, ses destinataires, ses conditions et sa révision. L’ordre est communiqué aux membres par un canal admissible ; sa présence dans les données serveur ne leur donne pas connaissance de raisons secrètes du chef. Chaque membre concerné reçoit son propre contexte pour décider de sa réaction. L’acceptation conduit à un objectif individuel validé, la contestation peut produire une réplique, et le refus empêche l’application de l’ordre à ce membre. Le chef peut réévaluer son choix lorsqu’il apprend les réactions, dans les limites de tours prévues.

**Accords proposés.** Conserver séparément l’ordre opérationnel et les engagements collectifs. Refuser de participer à une escorte ne rompt pas automatiquement une trêve et n’autorise pas une agression. Une signature du chef porte un périmètre explicite de représentation ; les règles de ratification, de retrait d’un membre et de maintien des accords après changement de chef restent à définir. Toute violation effective d’une trêve suit ADR B10.

**Données proposées.** Identifier durablement la bande, son chef et ses membres, avec une révision de composition. Un clan Bandits! peut servir de contexte culturel ou relationnel, mais ne suffit pas à identifier une bande précise ni son chef. Le rattachement des groupes créés par les différents chemins de spawn, la succession d’un chef mort et les échanges entre bandes restent à concevoir. Le modèle ne peut pas attribuer un mandat ou déplacer un membre par la seule formulation d’une réplique.

**Exemple.** Le chef accepte une escorte. Un membre loyal suit ; un membre blessé refuse et explique qu’il ne peut pas courir ; un membre méfiant demande une garantie. Le serveur applique uniquement les objectifs effectivement acceptés et autorisés. Les joueurs peuvent entendre les désaccords lorsqu’ils sont à portée. Le refus n’efface ni la mémoire du membre ni son appartenance à la bande ; un départ éventuel est une décision distincte régie par ADR B13.

**Validation multijoueur proposée.** Tester un chef et plusieurs membres aux réactions différentes, un membre hors portée de l’ordre, deux ordres successifs et une réponse tardive après un changement de composition. Vérifier une seule version canonique de l’ordre et des réactions, sans imposer automatiquement l’objectif aux membres qui l’ont refusé. Un quota doit répartir les évaluations individuelles ; le comportement pendant l’attente et l’interface pour expliquer les refus restent à définir.

## ADR B13 Départ individuel d’une bande

**Statut : départ décidé par le LLM et maintien des trêves existantes acceptés ; modalités de transition proposées.**

**Décision.** Un membre peut décider de quitter sa bande selon sa personnalité, sa loyauté, ses relations et son vécu. Le LLM choisit cette intention à partir de ce que le PNJ sait. Refuser un ordre ne déclenche pas automatiquement un départ. Le départ conserve l’identité, la personnalité, les relations personnelles et les souvenirs du PNJ ; il ne le fait pas rejoindre automatiquement les joueurs ou une autre bande.

**Transition serveur proposée.** Ajouter une intention structurée `leave_group`, liée au PNJ, à sa bande actuelle et à la révision de composition. Le serveur revalide l’appartenance et la décision, enregistre une transition unique et met à jour les objectifs dépendant de cette appartenance. Il conserve l’historique de la séparation et rejette les réponses tardives fondées sur une ancienne composition. Les clients reçoivent le même état canonique ; une phrase du PNJ ne modifie pas à elle seule sa bande. Le départ social et le déplacement physique sont deux étapes distinctes : une sortie sûre peut prendre du temps ou échouer.

**Communication proposée.** Le PNJ peut annoncer son départ ou partir discrètement selon ses motivations. Les autres personnages ne l’apprennent que par une observation ou une transmission admissible ; la connaissance technique du serveur ne devient pas une connaissance automatique de toute la bande. Les réactions du chef et des anciens compagnons sont des décisions individuelles ultérieures, sans hostilité automatique.

**Trêves conservées — décision acceptée.** Quitter sa bande ne modifie pas les trêves déjà applicables au PNJ avec les autres factions, y compris celles obtenues par un accord collectif. Elles restent en vigueur sans délai provisoire ni renégociation obligatoire. Une évolution ultérieure exige un motif et une décision distincts, selon les règles de relations et de trêve des ADR B07 et B10. Le serveur doit conserver ces accords indépendamment de l’appartenance actuelle, afin qu’un changement de bande ne les efface pas lors du recalcul du ciblage.

**Autres modalités proposées.** Le PNJ cesse d’être représenté par son ancien chef pour les nouveaux accords. Le traitement des dettes, promesses individuelles et obligations collectives reste à définir. Le départ d’un chef exige une règle de succession distincte ; aucune désignation par le LLM n’est encore acceptée.

**Validation multijoueur proposée.** Tester un départ avec deux clients, une trêve existante avec une autre faction, un ancien ordre encore en attente, une réponse LLM devenue caduque, un départ discret et un redémarrage du serveur. Vérifier une seule transition persistée, la conservation de la fiche et des trêves sur les deux clients et après redémarrage, l’absence d’exécution d’anciens objectifs collectifs devenus invalides et la diffusion limitée des paroles. La manière de découpler l’appartenance RadioSurvivor du clan et du ciblage natifs Bandits! reste à développer et à tester en 42.21.

## ADR B14 Panneau de relation joueur–PNJ

**Statut : panneau et contenu principal demandés par l’utilisateur ; niveaux qualitatifs de confiance acceptés ; organisation et règles de visibilité proposées.**

**Besoin.** Des décisions sociales influencées par les actes du joueur et sa réputation doivent rester compréhensibles. Une réaction ou un refus d’aide doit pouvoir être rapproché de sa relation, de sa réputation, des accords applicables et des échanges vécus.

**Contenu demandé.** Une fiche consultable pour chaque PNJ rencontré réunit un indicateur de confiance, les trêves et alliances applicables, les dernières conversations et des notes personnelles éditables par le joueur. La confiance affichée est celle du PNJ envers le personnage joueur qui consulte la fiche. Les accords personnels et les accords bénéficiant au joueur par sa faction sont distingués, conformément à ADR B08 ; la confiance et l’existence d’une trêve restent des informations séparées.

**Présentation proposée.** Ouvrir la fiche depuis la fenêtre « Parler » et retrouver les PNJ déjà rencontrés dans un carnet de contacts. Afficher le nom connu, la confiance actuelle, sa tendance récente, puis les accords avec leur portée et leurs conditions. Présenter ensuite les changements de relation compréhensibles et datés, les échanges entendus et les notes. Une fiche consultée à distance indique quand les informations ont été mises à jour ; elle ne fournit pas automatiquement la position actuelle du PNJ.

**Affichage de confiance accepté.** Utiliser des niveaux qualitatifs avec une tendance récente, sans score numérique affiché. Proposition de niveaux : « très méfiant », « méfiant », « réservé », « confiant », « très confiant ». La tendance peut être « en hausse », « stable » ou « en baisse », avec un libellé en plus d’un symbole. Ces libellés et le calcul de tendance restent proposés. La confiance ne remplace ni l’état de trêve ni l’alliance et ne détermine pas à elle seule l’hostilité. Le serveur reste responsable de l’état et de sa traduction en niveau ; le LLM ne choisit pas librement un libellé différent sur chaque client.

**Explications proposées.** Montrer les actes retenus dans la réputation et les motifs connus des changements personnels : aide apportée, promesse tenue ou dispute entendue. Afficher séparément la réputation et la confiance du PNJ ; une bonne réputation ne garantit pas sa confiance. L’interface ne révèle pas automatiquement les pensées privées du PNJ. Les notes saisies par le joueur restent ses annotations ; elles ne deviennent ni une preuve serveur ni une connaissance du PNJ.

**Multijoueur proposé.** Le serveur conserve la relation canonique pour chaque paire PNJ–personnage joueur et transmet les champs autorisés au seul joueur concerné. Deux membres d’une faction peuvent avoir des niveaux de confiance différents envers le même PNJ tout en bénéficiant du même accord collectif. L’historique présente les échanges effectivement reçus par ce personnage ; les notes personnelles restent privées, leur stockage et leur continuité à la reconnexion étant à spécifier. Les clients ne peuvent pas modifier la confiance ou les accords par une édition de la fiche.

**Exemple proposé.** « Paul — confiance : méfiant, en baisse ; trêve : active avec votre faction ; alliance : aucune ; dernier motif connu : vous a demandé des explications sur une disparition ; dernière conversation : aujourd’hui, 14 h 20. » Une note personnelle pourrait être : « Revenir avec les médicaments promis. » L’exemple illustre une présentation possible, pas une échelle déjà acceptée.

**Validation proposée.** Tester deux joueurs aux relations différentes avec le même PNJ, une trêve collective, un changement de confiance, un motif secret, une conversation hors portée et une reconnexion. Vérifier des données cohérentes avec le serveur, l’absence d’accès aux notes et conversations privées d’un autre joueur et la conservation des trêves lors du départ du PNJ de sa bande. Aucun panneau n’est encore implémenté.

## ADR B15 Réputation des joueurs fondée sur leurs actes

> Décisions du 2026-10-08 (plan, `E04-T01`) : API de CharacterReputation développée après l'arrivée des missions Living Knox ; faits enregistrés avant l'API ignorés ; consultation par un onglet du carnet et un bouton propre au mod de réputation. Bandits! n'est plus utilisé par RadioSurvivor (`E17-T01`).

**Statut : réputation globale unique par personnage, mod autonome et API publique acceptés ; missions permettant de l’améliorer demandées ; règles d’attribution et calcul proposés.** Cette fonctionnalité remplace le système de rumeurs abandonné.

**Principe demandé.** La réputation donne aux PNJ un élément pour juger un personnage, notamment avant de lui faire confiance. Nouvelle orientation proposée par l’utilisateur : missions accomplies, échouées ou acceptées mais non accomplies, et comportement grossier ou vulgaire envers les PNJ. Le périmètre initial ne prévoit plus de détecteurs de malus PvP, de vols ou de destructions. La confiance reste propre à chaque relation PNJ–personnage : le LLM prend en compte la réputation, la personnalité du PNJ et leurs interactions vécues, puis le serveur valide les changements. L’API autonome reste ouverte aux contributions d’autres mods.

**Événements proposés.** Le serveur conserve un registre identifié et persistant des actes retenus : auteur, victime ou bénéficiaire, type d’acte, date, contexte, preuve technique et résultat de validation. Un événement ne compte qu’une fois. Les paroles du LLM, accusations en dialogue et notes personnelles ne constituent pas des preuves. Les variations et leurs motifs apparaissent dans le panneau de relation, avec une présentation qualitative cohérente avec ADR B14.

| Acte envisagé | Condition à établir avant prise en compte |
| --- | --- |
| Mission accomplie | Objectif réellement atteint et validé par le serveur ; une promesse ou une déclaration ne suffit pas. |
| Mission échouée | Même malus que pour un abandon, sans évaluation des efforts ou de la tentative. Principe accepté ; montant à définir. |
| Mission annulée après la mort du PNJ demandeur | Aucun malus de mission : la livraison est devenue impossible. Annulation distincte d’un échec ou d’un abandon. |
| Participant qui tue le PNJ demandeur | Très forte baisse de réputation globale pour ce personnage uniquement, distincte du résultat de mission ; aucun malus pour ses coéquipiers. Montant et attribution serveur à établir. |
| Mission acceptée mais non accomplie | Ne pas pénaliser une mission encore en cours ; abandon ou échéance annoncée dépassée proposés comme déclencheurs. |
| Comportement envers un PNJ | Insulte ou menace dirigée proposée comme incident ; classification contextuelle par le LLM, variation bornée et dédupliquée par le serveur. Un juron isolé ne suffit pas. |

**Malus d’échec accepté.** Une mission échouée entraîne le même malus qu’une mission abandonnée, sans évaluation des efforts du personnage. Le montant reste à définir ; le LLM ne peut pas accorder une indulgence sur la base d’un récit de tentative.

**Autres modalités proposées.** Refuser une offre avant de s’engager ne pénalise pas le personnage. Une mission encore en cours ou une déconnexion ne constituent pas seules un échec ; une échéance annoncée dépassée peut clore la mission. Le LLM peut qualifier une insulte adressée à un PNJ, mais ne fixe pas librement la variation globale ; le serveur applique une règle commune avec un motif visible, au plus une fois par incident. Voir [ADR R03](../../reputation-api-specifications.md). Ces modalités restent proposées.

**Amélioration acceptée, missions proposées.** Une mauvaise réputation s’améliore par des actes positifs et des missions validés, sans récupération automatique avec le temps. Prévoir des missions issues de modèles validés : livraison de fournitures, secours ou autre service vérifiable. Le serveur fixe les conditions, la récompense de réputation et le bénéficiaire ; le LLM choisit une mission admissible et en formule la demande. Borner les gains et éviter qu’une même livraison, une mission rejouée ou des actes arrangés entre joueurs ne produisent des gains illimités. Une série de petites missions ne doit pas effacer instantanément des actes graves ; la pondération reste à définir.

**Accès accepté.** Une mauvaise réputation ne ferme pas toutes les possibilités de mission. Certains PNJ peuvent proposer des services simples pour permettre au personnage de se racheter ; les missions sensibles peuvent exiger une confiance plus élevée. Le PNJ reste libre de refuser selon sa personnalité et sa relation. RadioSurvivor gère ces offres et leurs conditions ; le mod autonome de réputation fournit l’état et enregistre les récompenses validées.

**Missions en groupe acceptées.** Le PNJ peut proposer une mission à plusieurs personnages explicitement inscrits. Le serveur conserve la mission et ses participants ; la présence à proximité ou l’appartenance à la même faction n’inscrit pas automatiquement un personnage. Résultat accepté : même gain en cas de réussite ou même malus en cas d’échec ou d’abandon collectif pour chaque participant engagé, sans évaluation des efforts individuels. La mort, le retrait et les inscriptions tardives demandent des modalités explicites. Application proposée : l’adaptateur soumet une contribution dédupliquée par mission et personnage au service de réputation.

**Identité acceptée.** La réputation suit le personnage, pas le compte joueur. Elle persiste lors des reconnexions et redémarrages pour le même personnage ; la création d’un nouveau personnage démarre une réputation indépendante et neutre, sans hériter des actes de son prédécesseur. Le mécanisme d’identification persistante reste à établir pour 42.21 ; un identifiant réseau temporaire ne suffit pas. Le joueur peut ainsi interpréter un personnage mauvais sans pénaliser tous ses futurs rôles.

**Séparation acceptée.** Le mod autonome détient la réputation et expose une API de consultation et de contribution aux autres mods. RadioSurvivor conserve les personnalités, la confiance individuelle, les dialogues et les missions ; il consulte la réputation et soumet les accomplissements validés de ses missions à l’API. Le service de réputation fonctionne sans Bandits!, RadioSurvivor ni LLM. Les mécaniques spécifiques des autres mods restent dans leurs adaptateurs. Le nom du mod, sa dépendance obligatoire ou optionnelle pour RadioSurvivor et le contrat exact restent à définir dans le [document dédié](../../reputation-api-specifications.md).

**Visibilité encore à choisir.** La réputation consultable par les PNJ peut être commune au serveur ou dépendre des factions, sans système de propagation de rumeurs. Ne pas confondre cette donnée de jeu avec les secrets personnels transmis en dialogue.

**Limites techniques.** Le cycle serveur des missions et les événements de dialogue restent à implémenter. La classification des propos par le LLM est interprétative et doit être testée sur des insultes, citations et jurons sans cible ; le serveur ne peut pas garantir une intention par la seule validation du format. Sans pont, aucun malus de langage par simple liste de mots n’est proposé. Les détecteurs PvP, de vols et de destructions sortent du périmètre initial ; leur investigation reste historique.

**Validation multijoueur proposée.** Tester une mission accomplie, encore en cours, abandonnée, expirée et devenue impossible, puis rejouer son événement après reconnexion. Tester une insulte dirigée, une citation, un juron sur les zombies et plusieurs messages d’un même incident. Vérifier un seul gain ou malus par événement, des motifs visibles, une persistance cohérente et aucune modification par une commande client non autorisée. Les règles et essais restent à réaliser.

## ADR B16 Choix contextualisé des missions par le LLM

**Statut : répartition des rôles acceptée.** Le serveur fournit les missions possibles selon les besoins et les ressources du PNJ. Le LLM choisit laquelle proposer, à quel joueur et comment la présenter, selon sa personnalité, sa confiance envers ce personnage et la réputation globale de celui-ci.

**Simplicité retenue : offre fixe, négociation reportée.** Pour la première version, les fournitures, le délai et la récompense annoncés constituent une offre fixe. Le joueur accepte ou refuse et peut demander des explications ; les réponses du LLM clarifient l’offre sans changer ses conditions. Aucun marchandage, contre-proposition ou prolongation négociée n’est prévu dans ce périmètre. La négociation pourra être réexaminée ultérieurement, sans engagement de développement.

Le PNJ n’est pas un distributeur identique pour tous les joueurs. Une soigneuse méfiante peut proposer une petite livraison permettant de faire ses preuves ; un PNJ qui connaît le personnage peut lui confier une demande plus importante. Ces situations illustrent des choix possibles, pas une progression automatique obligatoire. Une mauvaise réputation ne ferme pas toutes les missions et chaque PNJ garde son jugement personnel.

Le serveur encadre les types de mission, objets, quantités, délais et récompenses. Le LLM choisit dans ces possibilités ; il ne crée pas un objet ou une récompense sans validation. Le joueur destinataire doit encore accepter personnellement, et les autres joueurs éventuellement invités confirment leur propre engagement. La proposition seule ne démarre pas le chrono.

**Réalisation proposée.** Préparer des offres identifiées et des destinataires admissibles dans le contexte connu du PNJ. Revalider au retour du LLM les besoins, les ressources et l’état des personnages, notamment lorsque plusieurs clients sollicitent le même PNJ. Une offre devenue invalide n’engage pas le joueur ; les conditions effectives sont présentées avant acceptation. Les mécanismes de calcul des besoins, de réservation des ressources et de limitation des offres concurrentes restent à spécifier et vérifier en 42.21.

**Validation prévue.** Tester deux joueurs de réputations et relations différentes, un PNJ aux ressources insuffisantes, deux demandes simultanées et une réponse LLM devenue caduque. Vérifier que seule une offre admissible peut être acceptée et que ses conditions sont identiques dans le dialogue, le carnet et l’état serveur. Aucun test en jeu réalisé.

## Spécification M01 Livraison de fournitures

**Statut : premier type de mission accepté ; déroulement détaillé proposé.** Cette mission RadioSurvivor contribue à la réputation via l’API autonome. Elle ne remplace pas automatiquement les échanges déjà prévus pour le passeur.

**Choix de l’offre accepté, réalisation proposée.** Selon ADR B16, le serveur prépare les demandes admissibles selon les besoins et ressources du PNJ : demandeur, objets admissibles, quantités, délai, conditions de remise et récompenses prévues. Le LLM choisit une offre, son joueur destinataire et sa formulation selon la personnalité du PNJ, sa confiance personnelle et la réputation globale du personnage. Il ne crée pas librement un type d’objet, une quantité ou une récompense. Les participants acceptent personnellement les mêmes conditions avant d’être engagés.

**Offre fixe acceptée pour la première version.** Le carnet affiche les conditions annoncées. Les questions du joueur servent à les comprendre, sans modifier les quantités, le délai ou la récompense. Le LLM ne promet pas une modification par dialogue ; la négociation est reportée. Le joueur accepte ou refuse cette offre.

**Fournitures équivalentes acceptées.** Un besoin peut accepter une liste précise d’objets définie côté serveur et visible dans le carnet avant acceptation et lors de la remise. Une pièce acceptée compte pour une unité ; plusieurs types autorisés peuvent être mélangés pour compléter ce besoin. Aucune conversion selon les calories, le poids ou la puissance. Une demande spécifique peut ne contenir qu’un seul type admissible. Le LLM sélectionne une demande parmi les modèles autorisés ; il ne déclare pas une nouvelle équivalence au moment du transfert. Les listes et conditions sont conservées avec la mission acceptée, pour garder les mêmes règles pendant son déroulement.

**Exemples de conception.** « 6 pansements propres » pourrait accepter bandages propres et bandes de tissu propres, en excluant les versions sales. « 4 conserves » pourrait accepter haricots, maïs et soupe en conserve, uniquement fermés. « 2 marteaux » pourrait accepter plusieurs modèles explicitement listés et en état utilisable. Ces exemples ne constituent pas un catalogue validé d’objets 42.21 : les identifiants et les critères d’état doivent être vérifiés dans les scripts installés. Un antidouleur ne remplace pas automatiquement un antibiotique. Un même objet transféré ne compte que pour un besoin ; les quantités remises ne dépassent pas le reste demandé.

**Livraisons partielles acceptées, suivi proposé.** Les participants peuvent effectuer plusieurs remises alimentant une progression commune. Conserver une identité de mission, ses participants engagés et la liste des fournitures restant à remettre. La fenêtre « Mes missions » acceptée présente cette progression et le temps restant. Une phrase telle que « j’ai livré les médicaments » ne suffit pas à faire progresser la mission. L’accès de remise depuis le carnet est accepté ci-dessous. Une remise partielle ne produit pas un gain de réputation séparé ; le gain collectif dépend de l’achèvement complet dans le délai.

**Suivi « Mes missions » accepté dans le carnet classique.** Pour chaque mission, afficher le PNJ demandeur, les fournitures livrées et restantes, le temps restant et les participants engagés. La disposition de la maquette A est validée : onglet Missions, liste à gauche et détail de la mission sélectionnée à droite, avec les conditions acceptées et l’état courant. Le bouton « Carnet » dans la barre latérale est accepté ; la réalisation Lua et l’adaptation aux dimensions de l’écran restent à vérifier.

**Synchronisation du suivi proposée.** Le serveur fournit les missions du personnage et leurs révisions. Les participants d’une même mission voient la même progression et les mêmes engagements ; une remise validée actualise le suivi de chacun. Le client peut afficher un décompte estimé entre deux mises à jour, mais le serveur décide de l’expiration et du résultat. Une reconnexion retrouve les données persistées. La fenêtre n’expose pas les missions privées d’un autre personnage et ne modifie pas directement les quantités livrées ou la réputation.

**Remise effective acceptée, mécanisme proposé.** Le serveur vérifie le destinataire, les objets réellement disponibles, leur quantité et leur admissibilité, puis contrôle le transfert effectif avant d’enregistrer la progression. Deux joueurs remettant des objets simultanément ne peuvent pas valider deux fois le même besoin. Une reprise après interruption doit réconcilier l’inventaire et la progression, sans supposer une transaction atomique entre le monde et les fichiers. L’autorité des inventaires joueur et PNJ et les API de transfert restent à établir en 42.21.

**Accès de remise accepté, validation proposée.** Dans l’onglet Missions du carnet classique, le bouton « Livrer » ouvre une sélection des objets admissibles et des quantités à remettre. Le joueur confirme la remise ; aucun objet n’est prélevé par la seule ouverture du carnet. L’accès exige la proximité du PNJ demandeur, revalidée côté serveur au moment du transfert avec la mission et son délai. Hors portée, la fiche reste consultable mais indique qu’il faut rejoindre le PNJ. Le rayon, les contraintes de distance verticale et d’accès ainsi que la sélection dans les sacs restent à spécifier. La remise depuis une fenêtre de dialogue n’est pas l’accès retenu.

**Résultat accepté.** La livraison complète validée donne le même gain de réputation à tous les participants engagés. Échec ou abandon collectif donne le même malus, sans évaluation des efforts individuels. Le serveur enregistre un résultat final et une contribution unique par mission–personnage. Les montants et les conditions précises d’échec restent à définir.

**Mort du PNJ demandeur : annulation sans malus de mission acceptée.** Si le PNJ demandeur meurt pendant une mission encore en cours, le serveur la clôture comme « Annulée — demandeur décédé ». Ce résultat est distinct d’un échec ou d’un abandon et ne produit aucun malus de mission pour les participants. Le chrono cesse et le carnet affiche le motif commun. Un simple déchargement de zone, une absence temporaire ou un changement de groupe du PNJ ne prouve pas sa mort. Le traitement d’une mission déjà réussie dont la récompense n’a pas été récupérée reste à discuter.

**Participant responsable de la mort : sanction personnelle très forte acceptée.** Si un participant tue le PNJ demandeur, ce personnage subit une très forte baisse de réputation globale, sans pénalité pour ses coéquipiers. Cette contribution est distincte de l’annulation : aucun malus collectif d’échec ou d’abandon ne s’y ajoute. Le carnet explique le motif à l’auteur dans son historique de réputation. Le montant exact reste à définir. Le serveur doit confirmer et rattacher la mort à l’identité persistante du personnage ; ni une accusation en dialogue ni une décision du LLM ne suffit à désigner le responsable. Une contribution unique est enregistrée pour le même acte, indépendamment du nombre de missions annulées ou de clients qui signalent la mort. L’attribution technique des morts Bandits! reste à vérifier avant implémentation ; ne pas attribuer la responsabilité à un personnage sur la seule proximité.

**Récompenses matérielles facultatives acceptées.** Certaines missions prévoient des objets en plus du gain de réputation, par exemple des munitions ou des médicaments. Leur nature et leur quantité sont annoncées avant acceptation et consultables dans le carnet ; elles sont dues à la réussite. Les missions sans récompense matérielle restent possibles. Les objets autorisés proviennent des modèles contrôlés côté serveur ; le LLM ne crée pas librement une récompense. La provenance, la réservation et la remise effective restent à spécifier. RadioSurvivor gère ces objets et leur attribution ; le service commun de réputation reçoit uniquement les contributions de réputation.

**Lot matériel fixe accepté.** La récompense matérielle est un lot total par mission, à partager entre les participants. Exemple : 20 cartouches au total, que la mission soit accomplie seul ou en groupe. Accepter une invitation supplémentaire n’augmente pas cette quantité. Le carnet distingue le lot matériel commun du gain de réputation personnel identique pour chaque participant engagé.

**Récupération simple et partage libre acceptés.** Après réussite, n’importe quel participant engagé peut récupérer le lot auprès du PNJ demandeur, via le bouton « Récupérer la récompense » dans le carnet utilisable à proximité. Le serveur revalide l’identité du personnage, son engagement, la réussite, la proximité et le fait que le lot n’a pas déjà été remis. La récompense est remise une seule fois pour toute la mission, y compris face à deux demandes simultanées ou à un rejeu réseau. La fiche commune indique qui l’a récupérée ; les joueurs se partagent ensuite les objets librement, sans attribution automatique de parts ni vote de groupe. La capacité d’inventaire et la reprise après interruption relèvent de la réalisation technique à préciser et tester ; aucune garantie d’atomicité avec les inventaires n’est établie ici.

**Sort des fournitures accepté.** En cas d’échec, notamment à l’expiration du délai, ou d’abandon, le PNJ conserve les objets effectivement remis lors des livraisons partielles. Aucune restitution automatique n’est effectuée à la clôture. Cette condition apparaît dans l’offre et le carnet avant acceptation ; les objets qui n’ont pas été remis restent dans les inventaires des joueurs.

**Délai obligatoire accepté.** Chaque mission de livraison possède une échéance annoncée avant acceptation. La proposition de livraisons ordinaires sans limite est rejetée. Proposition : délai adapté aux fournitures demandées et à l’urgence, plus court pour un besoin urgent. Les durées restent à définir ; le point de départ, le décompte en temps réel pendant le fonctionnement du serveur et sa pause uniquement serveur arrêté sont acceptés ci-dessous. L’expiration proposée clôt la mission en échec et applique une seule fois le malus prévu aux participants engagés.

**Départ du chrono accepté.** Le délai commence à la première acceptation effective validée par le serveur, sans attendre les réponses aux invitations de groupe. Consulter une offre ou envoyer une invitation ne démarre pas le compteur. Les participants qui acceptent ensuite rejoignent le même décompte et voient le temps restant avant de confirmer ; leur inscription ne réinitialise ni ne prolonge la durée.

**Clôture des inscriptions à la première livraison rejetée.** Une remise partielle ne fige pas la liste des participants et n’empêche pas l’acceptation des invitations. Chaque joueur reste tenu d’accepter personnellement ; le chrono commun continue. Aucune autre limite anticipée d’inscription n’est adoptée par ce refus. Une mission déjà clôturée ne peut pas recevoir de nouveaux engagements.

**Décompte multijoueur accepté.** Le délai ne se suspend pas lorsqu’un participant ou tous les participants se déconnectent. Tous restent engagés selon les conditions acceptées ; une reconnexion ne remet pas le compteur à zéro. La proposition de pause pendant l’absence du groupe est rejetée.

**Horloge acceptée : temps réel de fonctionnement du serveur** (remplacée le 2026-10-21 par le temps de jeu, voir `docs/annexes/plans/E11-missions-generees.md`, E11-T20). Le chrono avance tant que le serveur fonctionne, indépendamment du nombre de joueurs connectés et de la pause éventuelle de la simulation du monde. Il se suspend uniquement pendant l’arrêt du serveur et reprend avec son temps restant. Une date limite absolue continuant pendant l’arrêt ne réalise pas cette règle et n’est pas retenue.

**Persistance proposée.** Conserver le temps restant, la révision et le résultat de chaque mission ; soustraire le temps réel écoulé pendant les périodes de fonctionnement du serveur. Sauvegarder régulièrement et lors d’un arrêt normal, puis reprendre le décompte au démarrage sans soustraire la durée hors ligne du serveur. Vérifier qu’un mécanisme de mise à jour fonctionne même lorsque `PauseEmpty` suspend la simulation. Après un crash, borner et documenter l’écart possible depuis la dernière sauvegarde ; ne pas promettre une exactitude non vérifiée. Une expiration produit un seul résultat final et une seule contribution de réputation par participant engagé. Les API d’horloge, de sauvegarde et de reprise restent à établir en 42.21.

**Validation proposée.** Tester une livraison solo, une mission de groupe, plusieurs remises partielles par différents participants, deux remises simultanées, des objets insuffisants ou non admissibles, une déclaration sans transfert et une interruption pendant la remise. Vérifier les quantités, l’absence de duplication ou de perte d’objets, une progression commune, aucun gain de réputation aux étapes partielles et un résultat final unique pour chaque participant engagé. Reconnecter et redémarrer entre deux remises pour vérifier la persistance de la progression. Ces essais restent à réaliser.

## Spécification du cycle de décision

Les noms de champs ci-dessous sont une proposition de contrat RadioSurvivor. Les points d’extension Bandits! sont établis dans l’analyse ci-dessus ; ce contrat et son transport ne sont pas encore implémentés.

1. Le serveur reçoit une demande et vérifie l’identité de l’appelant, le PNJ visé, le canal, la portée admissible et les quotas.
2. Il construit un contexte limité à ce que le PNJ peut savoir, avec la liste des intentions possibles et des références opaques vers les cibles autorisées.
3. Il envoie une demande au pont comportant version du protocole, identité de partie, génération du serveur, `request_id`, `npc_id`, numéro de tour, révision de décision et échéance.
4. Le pont retourne une intention structurée, ses paramètres et la réplique conditionnelle. Il ne fournit ni code, ni nom de fonction à exécuter, ni cible libre hors du catalogue.
5. Le serveur rejette les messages inconnus, expirés, dupliqués ou issus d’une autre génération ; il revalide les conditions courantes. La révision couvre les changements pertinents pour la décision, pas chaque pas du PNJ.
6. Il enregistre l’acceptation, tente l’application par l’adaptateur et suit le résultat : accepté, commencé, réussi, échoué ou annulé.
7. Il diffuse la réplique correspondant au résultat réel. « Je vous suis » n’est diffusé qu’après acceptation effective de l’objectif ; une arrivée ou une livraison n’est annoncée qu’après constat de son accomplissement.
8. Il persiste le résultat et les faits utiles à la mémoire. Une reprise après crash réconcilie l’état avant tout nouvel effet ; on ne promet pas une transaction atomique entre les fichiers et le monde du jeu.

```json
{
  "protocol_version": 2,
  "world_id": "world-demo",
  "server_epoch": "boot-demo",
  "request_id": "request-demo",
  "npc_id": "npc-demo",
  "turn": 12,
  "decision_revision": 7,
  "intent": {
    "type": "follow",
    "target_ref": "eligible-player-1"
  },
  "say_on_accept": ["Je viens avec vous. Restons près de la route."],
  "say_on_reject": ["Attendez, la situation a changé."]
}
```

Cet exemple représente un choix de suivi prévu pour l’adaptateur, pas une capacité RadioSurvivor déjà disponible. Le suivi natif existe dans Bandits!, avec des priorités propres décrites plus haut. Le serveur fixe la durée et les contraintes de l’objectif et n’accepte les textes que s’ils respectent le canal et les limites. Le JSON devra être validé aussi côté jeu ; la seule validation Python ne suffit pas.

### Catalogue initial envisagé

| Intention | Conditions proposées | État de faisabilité |
| --- | --- | --- |
| `speak` | Destinataires admissibles, texte borné, canal valide. | Sous-titres locaux via `addLineChatElement` observés ; événement de parole commun à écrire. |
| `negotiate` | Une rencontre et une offre actives ; conditions issues du serveur. | Gestion des offres à écrire ; ne modifie pas seule l’hostilité. |
| `change_relation` | Transition motivée, cible autorisée, révision courante et conditions vérifiées. | Principe accepté dans ADR B07 ; portée et ciblage Bandits! à développer et valider. |
| `leave_group` | Appartenance actuelle vérifiée, décision individuelle motivée, révision de composition courante. | Principe accepté dans ADR B13 ; transition persistante et adaptation Bandits! à écrire. |
| `follow` | Cible admissible, PNJ disponible, objectif borné. | Suivi `Companion` observé ; programme propre proposé pour respecter le contrat. |
| `hold` | Position ou zone autorisée, délai maximal. | Attente et garde observées ; priorité du combat à prendre en compte. |
| `move_to` | Destination connue référencée par le serveur, trajet admissible. | Actions `Move` et `GoTo` observées ; commande serveur et zones non chargées à valider. |
| `withdraw` | Abandonner une négociation ou rejoindre une sortie admissible. | Mouvement possible par tâches ; le programme seul ne neutralise pas le combat prioritaire. |

Le troc et les livraisons restent gérés par les stocks et preuves serveur prévus dans le carnet. Aucun transfert ne dépend d’une phrase telle que « je t’ai donné les médicaments ». Leur rattachement à des PNJ physiques viendra après la validation de l’autorité des inventaires.

## Liens avec les fonctionnalités déjà retenues

Walt reste hors carte : intégrer Bandits! ne le transforme pas automatiquement en personnage rencontrable. L’infirmière, le déserteur ou une famille pourraient recevoir une incarnation physique explicite. Chaque fiche doit distinguer voix hors carte et PNJ lié à une entité.

Le secours par faction pourrait aboutir à la rencontre d’un groupe vivant plutôt qu’à une cache et une note. Ce serait une évolution à accepter séparément : le carnet prévoit actuellement leur départ. De même, incarner le passeur ne supprime pas son passage hebdomadaire et son échange sans contact.

Le chroniqueur raconte uniquement les événements confirmés et autorisés. Il n’accède pas automatiquement aux conversations locales privées. Les dernières pages restent fondées sur les événements enregistrés ; le LLM ne peut inventer une mort ou un accomplissement de mission.

## Vérifications avant développement

L’analyse statique a identifié les métadonnées de `42.20`, les programmes, les tâches, la parole, les IDs, l’hostilité et le réseau. Avant développement, vérifier dans une nouvelle session 42.21 la variante effectivement chargée et les éventuels remplacements de modules. La présence du mod téléchargé ne prouve pas son activation.

En multijoueur, vérifier en priorité que deux clients appliquent la même révision au cerveau actif, que le contrôle du mouvement migre correctement et que les commandes natives ne contredisent pas l’objectif serveur. Établir ce que le serveur peut constater sans client proche. Vérifier ensuite le déchargement de zone, la mort, les inventaires et le redémarrage complet. Pour des accords par faction, auditer tous les chemins de ciblage et les réactions des témoins avant de promettre un cessez-le-feu sélectif.

### Critères de validation

| Situation à tester sur serveur dédié 42.21 | Résultat attendu |
| --- | --- |
| Apparition d’une vague avec plusieurs PNJ amicaux ou hostiles. | Chaque PNJ possède une fiche individuelle côté serveur, même sans dialogue ; les clients retrouvent la même identité. |
| Création en groupe, création individuelle et passage d’un état virtuel à une incarnation. | Tous les chemins sont couverts ; une incarnation retrouvée conserve sa personnalité et ses souvenirs. |
| Pont absent au spawn, puis rétabli après des rencontres. | Une personnalité existe pendant l’attente ; son enrichissement préserve les traits déjà utilisés et les événements vécus. |
| Deux joueurs donnent des demandes incompatibles au même chef. | Un ordre explicite et un seul engagement canonique ; les deux clients observent le même résultat. |
| Déconnexion du client propriétaire éventuel pendant une décision. | Reprise cohérente sans PNJ figé, ordre rejoué ou effet doublé. |
| PNJ mort ou rencontre devenue dangereuse pendant l’appel LLM. | Réponse caduque rejetée ; comportement immédiat préservé. |
| Pont arrêté, quota atteint ou réponse invalide. | Jeu fonctionnel, secours déterministe, aucun nouvel engagement fictif. |
| Zone déchargée puis revisitée ; redémarrage du serveur. | Identité et engagements conservés ou annulés selon une règle explicite ; absence de duplication. |
| Client demande une cible interdite ou un transfert inexistant. | Refus serveur et aucun changement d’inventaire ou de relation. |
| Une aide puis une trahison motivent deux changements de relation. | Les transitions validées persistent ; les clients observent la même attitude envers la cible concernée. |
| Une trêve est décidée pendant que des tâches de combat sont en cours. | Son application est confirmée avant son annonce ; une réponse tardive ne rétablit pas un accord devenu caduc. |
| Un membre attaque pendant une trêve et un membre innocent est présent. | Défense ciblée contre l’agresseur ; le sort de la trêve collective dépend d’une décision LLM validée. |
| Le pont est indisponible au moment d’une violation de trêve. | Défense ciblée maintenue ; aucune rupture collective automatique. |
| Un PNJ raconte une observation à un autre devant un joueur. | Les répliques sont rendues pour les auditeurs admissibles ; le destinataire mémorise le récit avec sa provenance. |
| Un récit circule entre plusieurs PNJ puis revient au premier. | La chaîne de transmission est conservée ; aucune duplication de preuve ni boucle de conversation illimitée. |
| Deux membres d’une faction ont des relations personnelles différentes avec le même PNJ. | Les relations restent distinctes et l’accord collectif conserve son propre périmètre. |
| Un accord de faction est conclu tandis que les droits du négociateur changent. | Le serveur revalide le droit de représentation avant de conclure ; aucune signature non autorisée. |
| Parole locale puis radio avec plusieurs auditeurs. | Seuls les destinataires admissibles entendent chaque événement ; aucun historique secret n’est livré à la reconnexion. |

Compléter ces essais par une action Bandits! normale voisine, afin de vérifier que l’adaptateur préserve son fonctionnement. Les tests hors jeu peuvent valider le protocole, l’ordre et les rejets ; ils ne prouvent ni les API Java ni la compatibilité réelle de Bandits!.

## Discussion en cours

**Point 1 tranché : tous les PNJ créés par Bandits! possèdent leur propre personnalité dès leur apparition.**

**Point 2 tranché : les relations peuvent évoluer dans les deux sens, selon la personnalité et les événements vécus.**

**Point 3 tranché : relations personnelles avec chaque personnage joueur et accords de faction explicitement négociés.**

**Point 4 tranché : le propriétaire de la faction et ses négociateurs désignés peuvent conclure les accords collectifs.**

**Point 5 tranché : défense immédiate ciblée, puis décision du LLM sur le maintien, la réparation ou la rupture de la trêve.**

**Point 6 tranché : fiche individuelle immédiate côté serveur, puis enrichissement asynchrone par le LLM.**

**Point 7 tranché : dialogue de proximité et radio pour les PNJ équipés.**

**Point 8 tranché : clic droit sur le PNJ → « Parler » → petite fenêtre de dialogue avec destinataire explicite.**

**Point 9 tranché : les PNJ peuvent engager une conversation sur des événements pertinents, selon leur personnalité, avec des limites de fréquence.**

**Point 10 tranché : observations personnelles et transmissions entre PNJ par de véritables conversations de proximité ou radio.**

**Point 11 actualisé : mensonges et omissions de dialogue conservés ; rumeurs abandonnées par décision ultérieure de l’utilisateur.**

**Point 12 tranché : un chef prend les décisions collectives ; les membres peuvent contester ou refuser selon leur personnalité et leur loyauté.**

**Point 13 tranché : un PNJ peut quitter sa bande sur décision du LLM selon sa personnalité et son vécu.**

**Point 14 tranché : les trêves existantes du PNJ avec les autres factions restent en vigueur lorsqu’il quitte sa bande.**

La proposition de protection provisoire et de clarification obligatoire est abandonnée à la demande de l’utilisateur : le changement d’appartenance ne justifie pas de modifier ces accords. Une éventuelle évolution de relation reste une décision distincte.

**Point 15 tranché : le joueur peut intervenir dans une conversation entre PNJ qu’il entend ; les PNJ choisissent leur réaction.**

**Point 16 abandonné : aucun effet de rumeurs sur la confiance.** Le panneau de relation demandé reste retenu, ADR B14. La réputation fondée sur les actes remplace cette piste, ADR B15.

**Point 17 tranché : confiance affichée par niveaux qualitatifs avec une tendance récente.** Les libellés exacts, les seuils et le calcul de tendance restent à spécifier ; aucun score numérique n’est affiché.

**Point 18 tranché : réputation propre à chaque personnage, pour préserver la liberté de RP.** La recommandation de réputation liée au compte est rejetée par l’utilisateur.

**Point 19 tranché : réputation dans un mod autonome avec API pour les autres moddeurs.** RadioSurvivor devient un consommateur et un contributeur de ce service, selon le [document dédié](../../reputation-api-specifications.md).

**Point 20 tranché : une réputation globale unique par personnage.** Les autres mods contribuent à cette même réputation avec leurs propres événements ; la proposition de plusieurs axes est abandonnée.

**Point 21 tranché : une mauvaise réputation s’améliore par les actes et les missions validés.** Aucune amélioration automatique par le temps écoulé.

**Point 22 tranché : chaque nouveau personnage commence avec une réputation neutre.** Aucun bonus ni malus hérité ; ses actes ultérieurs la font évoluer.

**Point 23 tranché : des missions simples restent accessibles avec une mauvaise réputation auprès de certains PNJ.** Les missions sensibles peuvent exiger davantage de confiance ; aucun PNJ n’est obligé d’accepter.

**Point 24 tranché : trois niveaux visibles pour la réputation globale.** « Mauvaise », « neutre », « bonne », accompagnés des derniers actes expliquant les variations ; confiance personnelle de chaque PNJ affichée séparément.

**Point 25 tranché : fiche autonome « Ma réputation ».** Niveau du personnage et derniers gains et malus avec leurs motifs, utilisables sans RadioSurvivor.

**Point 26 rouvert : accès à « Ma réputation ».** Le clic droit précédemment accepté est remis en discussion à la suite de la préférence de l’utilisateur pour éviter l’accumulation de menus contextuels. La fiche elle-même reste acceptée.

**Point 27 mis de côté : consentement PvP et malus.** Le périmètre initial de réputation est recentré sur les missions et les PNJ. L’analyse statique PvP reste conservée dans l’[investigation dédiée](../../reputation-api-specifications.md), sans règle acceptée ni développement.

**Point 28 tranché pour l’échec : même malus pour une mission échouée et une mission abandonnée.** L’utilisateur rejette une distinction selon les efforts ou une tentative. Les montants et modalités des incidents de dialogue restent à définir.

**Point 29 tranché : missions réalisables en groupe avec inscription explicite auprès du PNJ.** La réputation reste individuelle par personnage.

**Point 30 tranché : même gain ou malus pour tous les participants engagés.** Même gain en cas de réussite et même malus en cas d’échec ou d’abandon collectif, sans calcul des efforts de chaque participant.

**Point 31 tranché : chaque joueur confirme personnellement sa participation après invitation.** Le chef peut inviter, sans engager les autres à leur place. Seuls les participants ayant accepté sont concernés par le résultat de réputation.

**Point 32 tranché : commencer par les missions de livraison de fournitures.** Médicaments, nourriture ou outils demandés par un PNJ ; remise effective validée par le serveur, seul ou en groupe. Voir spécification M01 ; autorité des inventaires à vérifier avant développement.

**Point 33 tranché : un délai pour toute mission de livraison.** Échéance annoncée avant acceptation. La proposition de missions ordinaires sans délai est rejetée ; durée et décompte restent à définir.

**Point 34 tranché : pas de pause du délai lorsque les participants se déconnectent.** Accepter la mission engage le personnage jusqu’au résultat ; l’absence de tout le groupe et la reconnexion ne suspendent ni ne réinitialisent l’échéance.

**Point 35 tranché : pause uniquement pendant l’arrêt du serveur.** Décompte en temps réel tant que le serveur fonctionne, même vide ; reprise avec le temps restant après redémarrage. La proposition de date limite absolue courant pendant l’arrêt est remplacée.

**Point 36 tranché : livraisons partielles autorisées, progression commune.** Plusieurs remises par les participants ; réussite uniquement lorsque toutes les fournitures sont livrées dans le délai.

**Point 37 tranché : fenêtre « Mes missions ».** PNJ demandeur, fournitures livrées et restantes, temps restant et participants engagés. Interface RadioSurvivor distincte de la fiche autonome « Ma réputation ».

**Point 38 tranché pour le regroupement : carnet unique, maquette A validée.** L’utilisateur retient le carnet classique parmi les trois maquettes. Le point d’entrée, notamment un bouton latéral, reste à confirmer. Les alternatives ci-dessous constituent l’historique de cette discussion.

| Solution proposée | Usage et compromis |
| --- | --- |
| Carnet unique avec onglets Contacts, Missions et Réputation | Une seule interface pour les informations sociales. Réutiliser le carnet RadioSurvivor existant plutôt qu’imposer plusieurs fenêtres ; le mod de réputation doit conserver un accès autonome lorsqu’il est utilisé seul. |
| Un bouton « Carnet » dans la barre latérale | Accès visible aux mêmes onglets avec un seul bouton supplémentaire. L’emplacement et l’intégration UI 42.21 restent à vérifier. |
| Onglets dans la fenêtre du personnage | Regrouper missions et réputation avec les informations du personnage. Économise un bouton, mais peut alourdir une fenêtre vanilla et demande une intégration à auditer. |
| Raccourci clavier configurable ouvrant le carnet | Accès rapide, sans menu supplémentaire. Moins découvrable ; à proposer comme complément d’un accès visible et avec une touche libre choisie par le joueur. |

Le carnet unique et son bouton « Carnet » dans la barre latérale sont acceptés. Un raccourci configurable facultatif reste proposé. Aucun accès nouveau n’est implémenté ; l’accès « Parler » sur un PNJ n’est pas modifié par cette discussion.

### Maquettes du carnet unique

Ouvrir dans un navigateur : [trois variantes du carnet](../maquettes/carnet-preview.html). Source de la visualisation : `maquettes/carnet-unique.html`. Les données de contacts, dialogues et missions sont fictives et identiques entre variantes. Les onglets, sélections de fiches et notes sont manipulables ; les durées sont des exemples fixes, pas un chrono de jeu. Aucun transfert d’objet ni appel LLM n’est effectué.

| Variante proposée | Organisation |
| --- | --- |
| A — Carnet classique | Onglets horizontaux, liste à gauche et fiche détaillée à droite. |
| B — Dossiers visuels | Navigation latérale, choix de contacts ou missions sous forme de dossiers, fiche en dessous. |
| C — Carnet compact | Onglets horizontaux, lignes de résumé puis détail du contact ou de la mission sélectionné. |

**Choix validé : A — Carnet classique.** Cette variante est la référence pour le carnet RadioSurvivor. Contacts et Missions présentent leur liste à gauche et la fiche sélectionnée à droite ; Réputation présente le niveau global et son historique dans le même carnet. Les notes personnelles restent dans la fiche du contact. Les variantes B et C sont conservées pour l’historique de conception, sans être retenues. Les personnages, dialogues, quantités et durées d’exemple ne constituent pas des paramètres de jeu validés.

**Vérification de maquette.** Navigation dans les trois sections, sélection de contacts et édition des notes vérifiées dans Chrome sans fenêtre, à 820 et 360 pixels de largeur, sans débordement détecté ni erreur JavaScript. Les trois variantes ont été inspectées visuellement ; ce contrôle ne valide pas une intégration dans l’interface Lua 42.21. Maquette A validée par l’utilisateur ; aucune intégration en jeu réalisée.

**Point 39 tranché : un seul bouton « Carnet » dans la barre latérale.** Accès visible à l’interface validée ; point d’extension UI 42.21 à vérifier avant implémentation.

**Point 40 : architecture commune retenue comme base pour préparer une coquille.** L’utilisateur autorise un sous-agent à préparer le projet du service autonome. Identités persistantes, profils déclarés, API versionnée, événements dédupliqués et adaptateurs restent le contrat de conception dans [ADR R05](../../reputation-api-specifications.md). La réputation globale de personnage reste unique ; la confiance de station MilitaryDrop utilise le même moteur avec ses règles préservées. Préparer la structure du nouveau mod n’implémente pas ces services ni leur migration.

**Point 41 tranché : bouton « Livrer » dans l’onglet Missions, près du PNJ demandeur.** Sélection des objets et quantités puis confirmation, depuis le carnet ; validation serveur de la proximité et du transfert à développer.

**Point 42 tranché : fournitures équivalentes explicites, une pièce pour une unité.** Liste d’objets acceptés visible dans la mission, définie et validée côté serveur. Mélange des types autorisés possible ; pas de conversion selon poids, calories ou puissance. Une demande peut rester spécifique à un seul type. Exemples et limites consignés dans M01.

**Point 43 tranché : le PNJ conserve les fournitures déjà remises.** En cas d’échec ou d’abandon, aucune restitution automatique. Condition affichée avant acceptation et consignée dans M01.

**Point 44 tranché : départ du chrono à la première acceptation.** Le délai commence lorsque le premier joueur accepte effectivement la mission, sans attendre les réponses aux invitations de groupe. Les autres participants qui acceptent rejoignent le même décompte, sans le réinitialiser ni le prolonger. M01 actualisée.

**Point 45 rejeté : clôture des inscriptions à la première livraison.** Refus explicite de l’utilisateur. Une remise partielle ne ferme pas les inscriptions ; acceptation personnelle et chrono commun conservés. Aucune autre limite anticipée n’est adoptée.

**Point 46 tranché : récompense matérielle facultative en plus de la réputation.** Certaines missions offrent des objets annoncés avant acceptation et remis à la réussite, en plus du gain de réputation. Principe accepté ; provenance, réservation et répartition restent à spécifier dans RadioSurvivor, pas dans le moteur commun de réputation.

**Point 47 tranché : lot matériel fixe par mission.** Quantité totale annoncée à partager entre les participants, sans multiplication par joueur inscrit. Exemple : 20 cartouches au total, en solo comme en groupe. Chacun conserve le même gain personnel de réputation. M01 actualisée ; récupération choisie au point 48.

**Point 48 tranché : récupération par un participant puis partage libre.** Accepté avec une préférence explicite pour la simplicité. N’importe quel participant engagé peut récupérer le lot auprès du PNJ via le carnet. Remise unique vérifiée côté serveur, bénéficiaire visible dans la fiche commune, partage libre entre joueurs. M01 actualisée ; vérifications techniques de transfert à réaliser.

**Point 49 tranché : annulation sans malus de mission si le PNJ demandeur meurt pendant la mission.** La livraison devient impossible ; résultat « Annulée — demandeur décédé », distinct d’un échec ou d’un abandon. M01 et ADR B15 actualisés. La responsabilité d’un participant est traitée séparément au point 50 ; mort du demandeur après réussite encore à discuter.

**Point 50 tranché : très forte baisse de réputation pour le participant qui tue le demandeur.** Sanction de l’auteur uniquement, aucun malus pour ses coéquipiers. Contribution distincte de l’annulation sans malus collectif ; montant exact et attribution serveur à établir.

**Point 51 tranché : missions choisies par le LLM parmi les offres admissibles du serveur.** Choix de la mission, du joueur destinataire et de la formulation selon personnalité, confiance et réputation. Serveur responsable de l’admissibilité et des limites des quantités, délais et récompenses. ADR B16 et M01 actualisés.

**Point 52 reporté : négociation des conditions de mission.** Décision explicite de l’utilisateur pour garder la première version simple. Offre fixe avec fournitures, délai et récompense annoncés ; le joueur accepte ou refuse, et peut demander des précisions sans modification des conditions. Aucun marchandage ou contre-proposition dans le périmètre initial. ADR B16 et M01 actualisés.

Les conséquences matérielles des engagements restent à discuter ultérieurement.

## Journal des décisions

| Date | Sujet | Statut |
| --- | --- | --- |
| 2026-10-02 | Chat local normal pour les dialogues avec les PNJ. | Orientation consignée à la demande explicite de l’utilisateur dans [ADR B17](../../architecture/decisions/adr-b17-chat-proximite-pnj.md), après inspection du Java décompilé 42.21.0. Saisie vanilla conservée, adaptateur serveur pour les demandes et diffusion des réponses depuis le PNJ. Aucun code de jeu modifié ni test en jeu effectué. |
| 2026-10-01 | Fonctionnalités et catalogue d’actions du carnet local. | Décisions antérieures conservées ; leur implémentation n’est pas implicite. |
| 2026-10-02 | Dialogue et intentions LLM pour Bandits!, priorité multijoueur. | Orientation demandée par l’utilisateur. |
| 2026-10-02 | ADR B01 à B05 et contrat de décision. | Propositions en attente de discussion ; aucune intégration ni modification du mod. |
| 2026-10-02 | Artefact Claude et sources Bandits! téléchargées. | Le carnet HTML est confirmé comme artefact de référence. Analyse statique de la variante Bandits! `42.20` effectuée ; question initiale remplacée par le choix des PNJ concernés. |
| 2026-10-02 | Personnalité individuelle dès le spawn pour chaque PNJ Bandits!. | Accepté explicitement par l’utilisateur, ADR B06. La proposition de limiter les personnalités aux PNJ rencontrés est remplacée ; méthode de génération et évolution des relations restent proposées. |
| 2026-10-02 | Relations évoluant dans les deux sens selon personnalité et événements. | Accepté explicitement par l’utilisateur, ADR B07. ADR B01 précisé ; portée individuelle ou collective des relations encore à discuter. |
| 2026-10-02 | Relations personnelles et accords de faction explicites. | Accepté explicitement par l’utilisateur, ADR B08. Représentation des factions, priorité des accords et règles de rupture restent à définir. |
| 2026-10-02 | Propriétaire et négociateurs désignés habilités à engager la faction. | Accepté explicitement par l’utilisateur, ADR B09. Gestion et continuité des mandats proposées ; responsabilité collective en cas d’agression encore à discuter. |
| 2026-10-02 | Défense ciblée puis décision LLM sur le sort de la trêve. | Accepté explicitement par l’utilisateur, ADR B10. Attribution, limites de défense et adaptation du ciblage Bandits! restent à définir et valider. |
| 2026-10-02 | Fiche immédiate côté serveur, enrichie ensuite par le LLM. | Accepté explicitement par l’utilisateur, ADR B06 actualisé. Schéma, règles de génération et mécanisme de rattachement restent à spécifier. |
| 2026-10-02 | Dialogue de proximité et radio pour les PNJ équipés. | Accepté explicitement par l’utilisateur, ADR B04 actualisé. Conditions de réception et présentation de proximité proposées ; aucune intégration en jeu effectuée. |
| 2026-10-02 | Clic droit sur le PNJ puis « Parler » dans une petite fenêtre. | Proposition confirmée par « ok », ADR B04 actualisé. Initiative spontanée des PNJ encore proposée. |
| 2026-10-02 | Initiatives de conversation sur événements pertinents selon la personnalité. | Accepté explicitement par l’utilisateur, ADR B04 actualisé. Ordonnancement, regroupement et délais proposés ; partage des informations entre PNJ à discuter. |
| 2026-10-02 | Observations personnelles et transmissions par conversations entre PNJ. | Accepté explicitement par l’utilisateur, ADR B03 actualisé et ADR B11 créé. Réception, provenance et limites proposées ; mensonges et rumeurs à discuter. |
| 2026-10-02 | Mensonges, omissions et rumeurs selon la personnalité. | Accepté explicitement par l’utilisateur, ADR B11 actualisé. Distinction entre faits, affirmations et croyances spécifiée ; mécanismes de confiance et de révision proposés. |
| 2026-10-02 | Un chef décide, les membres peuvent contester ou refuser. | Accepté explicitement par l’utilisateur, ADR B12 créé. Désignation du chef, transmission des ordres et conséquences du refus à définir. |
| 2026-10-02 | Départ individuel d’une bande décidé par le LLM. | Accepté explicitement par l’utilisateur, ADR B13 créé et B12 actualisé. Identité conservée ; transition serveur proposée et sort de la trêve collective à discuter. |
| 2026-10-02 | Conservation des trêves après départ d’une bande. | Correction explicite de l’utilisateur intégrée dans ADR B13 : les trêves existantes restent en vigueur. Proposition de protection provisoire et de renégociation obligatoire abandonnée. |
| 2026-10-02 | Intervention du joueur dans les conversations entre PNJ entendues. | Accepté explicitement par l’utilisateur, ADR B11 actualisé. Accès via « Parler » et liberté de réaction des PNJ ; ordonnancement multijoueur proposé. |
| 2026-10-02 | Panneau de relation avec un PNJ et indicateurs visibles. | Demandé explicitement par l’utilisateur comme condition de compréhension des évolutions de confiance. ADR B14 créé : confiance, trêves, alliances, conversations et notes personnelles ; présentation proposée. |
| 2026-10-02 | Affichage de la confiance par niveaux qualitatifs. | Choix explicite de l’utilisateur intégré dans ADR B14. Niveaux et tendance visibles ; libellés, seuils et calcul proposés. |
| 2026-10-02 | Abandon des rumeurs et introduction de la réputation. | Décision explicite de l’utilisateur : système de rumeurs abandonné, y compris ses effets sur la confiance. ADR B03, B11 et B14 actualisés ; ADR B15 créé pour les actes PvP, vols, destructions et missions améliorant la réputation. Les entrées antérieures sur les rumeurs constituent l’historique d’une décision désormais remplacée. |
| 2026-10-02 | Réputation par personnage et service autonome ouvert aux mods. | Décision explicite de l’utilisateur : réputation liée au personnage pour le RP, mod distinct avec API de lecture et de contribution. ADR B15 actualisé et document de conception de l’API créé ; aucune implémentation. |
| 2026-10-02 | Une réputation globale unique. | Choix explicite de l’utilisateur pour garder le système simple. ADR B15 et contrat API proposés actualisés : les événements des mods contribuent à une même valeur ; plusieurs axes abandonnés. |
| 2026-10-02 | Amélioration par les actes et les missions. | Accepté explicitement par l’utilisateur. ADR B15 et document API actualisés : événements positifs validés, sans amélioration automatique par le temps écoulé. |
| 2026-10-02 | Réputation initiale neutre. | Accepté explicitement par l’utilisateur. ADR B15 et document API actualisés : chaque nouveau personnage commence neutre, sans bonus ni malus hérité. |
| 2026-10-02 | Missions accessibles avec une mauvaise réputation. | Proposition confirmée par l’utilisateur. ADR B15 et document API actualisés : missions simples auprès de certains PNJ, missions sensibles conditionnées à la confiance. |
| 2026-10-02 | Trois niveaux de réputation visibles. | Accepté explicitement par l’utilisateur : mauvaise, neutre, bonne, avec les derniers actes expliquant les variations. Documents de conception actualisés ; seuils internes à définir. |
| 2026-10-02 | Fiche autonome « Ma réputation ». | Accepté explicitement par l’utilisateur. Document API et document Bandits! actualisés : niveau et derniers gains et malus avec leurs motifs, sans dépendance à RadioSurvivor ; accès à choisir. |
| 2026-10-02 | Accès à « Ma réputation » par clic droit. | Accepté explicitement par l’utilisateur. Entrée dans le menu du personnage joueur ; point d’extension UI 42.21 à vérifier avant implémentation. |
| 2026-10-02 | PvPvE privilégiant l’entraide et protection des joueurs refusant le PvP. | Intention exprimée par l’utilisateur. Contrôle `AntiCheatSafety` de l’installation 42.21 analysé statiquement : sécurité de la cible seule insuffisante dans ce chemin. Consentement mutuel proposé ; aucune règle de malus adoptée, aucun test en jeu ni changement de configuration. |
| 2026-10-02 | Simplification : missions et comportement envers les PNJ. | Nouvelle proposition de l’utilisateur intégrée dans ADR B15 et ADR R03 du document API. Détecteurs PvP, de vols et de destructions mis de côté pour le périmètre initial ; échec, abandon, échéance et langage à distinguer avant de fixer les malus. |
| 2026-10-02 | Même malus pour échec et abandon de mission. | L’utilisateur rejette l’indulgence selon les efforts ou la tentative. ADR B15 et ADR R03 actualisés ; montant du malus à définir. |
| 2026-10-02 | Missions en groupe avec inscription explicite. | Principe accepté par l’utilisateur. ADR B15 et ADR R03 actualisés ; gains et malus par participant restent à choisir, réputation individuelle conservée. |
| 2026-10-02 | Même résultat de réputation pour les participants engagés. | Accepté explicitement par l’utilisateur. ADR B15 et ADR R03 actualisés : même gain si réussite, même malus si échec ou abandon collectif, sans calcul de contribution individuelle. |
| 2026-10-02 | Acceptation personnelle des missions de groupe. | Accepté explicitement par l’utilisateur. Invitation par le chef, confirmation par chaque joueur ; seuls les personnages ayant accepté sont engagés et concernés par la réputation. |
| 2026-10-02 | Premier type de mission : livraison de fournitures. | Accepté explicitement par l’utilisateur. Spécification M01 créée et document API actualisé : remise effective de médicaments, nourriture ou outils, seul ou en groupe ; déroulement détaillé et délai proposés. |
| 2026-10-02 | Délai obligatoire pour les livraisons. | L’utilisateur rejette les missions sans délai. M01 et document API actualisés : échéance annoncée pour chaque livraison ; durée et décompte multijoueur à choisir. |
| 2026-10-02 | Aucune pause pendant les déconnexions des participants. | L’utilisateur rejette la pause du compteur : une mission acceptée reste un engagement. M01 et document API actualisés ; horloge et traitement des arrêts du serveur proposés. |
| 2026-10-02 | Pause du chrono uniquement serveur arrêté. | Décision explicite de l’utilisateur : le délai avance tant que le serveur fonctionne, même sans participants connectés, et reprend avec le temps restant après arrêt. M01 et document API corrigés ; persistance et comportement sous `PauseEmpty` à vérifier. **Remplacée le 2026-10-21** (E11-T20, point C27) : le délai suit le temps de jeu. |
| 2026-10-02 | Livraisons partielles et progression commune. | Accepté explicitement par l’utilisateur. M01 et document API actualisés : plusieurs remises possibles, réussite après livraison complète dans le délai, sans gain de réputation aux étapes partielles. |
| 2026-10-02 | Fenêtre « Mes missions ». | Accepté explicitement par l’utilisateur. M01 actualisée : demandeur, fournitures livrées et restantes, temps restant et participants ; présentation, accès et synchronisation proposés. |
| 2026-10-02 | Alternatives au clic droit pour les informations sociales. | L’utilisateur exprime une préférence contre l’accumulation de menus contextuels et demande plusieurs solutions. Accès à « Ma réputation » rouvert, clic droit « Mes missions » non retenu ; carnet unique, bouton latéral, onglets personnage et raccourci proposés. |
| 2026-10-02 | Carnet unique et maquettes comparatives. | Carnet unique accepté ; trois variantes interactives A, B et C créées pour le choix de l’utilisateur. Contenus et interactions vérifiés dans le navigateur ; aucune intégration en jeu. |
| 2026-10-02 | Maquette A « Carnet classique » validée. | Choix explicite de l’utilisateur : onglets Contacts, Missions, Réputation en haut, liste à gauche et détail à droite. Référence de conception retenue ; accès au carnet et intégration Lua restent à définir. |
| 2026-10-02 | Bouton « Carnet » et réputation commune avec MilitaryDrop. | Bouton latéral accepté ; factorisation dans un mod commun demandée. Sources MilitaryDrop `42.21` analysées statiquement : confiance par station, règles propres. ADR R04 ajouté ; aucune source de mod modifiée et aucun test en jeu. |
| 2026-10-02 | Proposition robuste et ouverte aux autres mods. | Architecture détaillée dans ADR R05 à la demande de l’utilisateur : moteur autonome, adaptateurs, profils, API versionnée, reprise et migration. Réputation individuelle unique et confiance MilitaryDrop préservées ; conception uniquement. |
| 2026-10-02 | Coquille du mod commun déléguée à un sous-agent. | Autorisation explicite de l’utilisateur. Structure du nouveau projet à préparer ; aucune extraction ni migration de MilitaryDrop ou RadioSurvivor autorisée par cette seule étape. Discussion RadioSurvivor poursuivie sur l’accès à la remise de fournitures. |
| 2026-10-02 | Bouton « Livrer » dans le carnet près du PNJ. | Choix explicite de l’utilisateur. M01 actualisée : sélection des objets et quantités avant confirmation ; proximité et transfert à revalider côté serveur. |
| 2026-10-02 | Coquille CharacterReputation créée avec le sous-agent. | Projet `batman_CharacterReputation` version `0.1.0`, structure common/42.21 et modules shared/client/server. Paquet et chargement Lua contrôlés ; capacités métier indisponibles, aucune migration ni intégration des mods consommateurs, aucun test en jeu. Voir [README](../../../../CharacterReputation/README.md). |
| 2026-10-02 | Fournitures équivalentes explicites acceptées. | Liste visible d’objets acceptés, une pièce pour une unité, sans conversion de poids, calories ou puissance. M01 et point 42 actualisés ; catalogue d’objets et validation serveur à développer. |
| 2026-10-02 | Fournitures déjà remises conservées par le PNJ. | Accepté explicitement : aucune restitution automatique en cas d’échec ou d’abandon, condition annoncée avant acceptation. M01 et point 43 actualisés. |
| 2026-10-02 | Départ du chrono à la première acceptation. | Accepté explicitement : même décompte pour les participants qui rejoignent ensuite, sans réinitialisation ni prolongation. M01 et point 44 actualisés. |
| 2026-10-02 | Clôture des inscriptions à la première livraison rejetée. | Refus explicite : une remise partielle ne ferme pas les inscriptions. M01 et point 45 actualisés ; aucune autre limite anticipée adoptée. |
| 2026-10-02 | Récompenses matérielles facultatives acceptées. | Certaines missions offrent des objets annoncés avant acceptation, en plus du gain de réputation. M01 et point 46 actualisés ; modalités d’attribution à définir. |
| 2026-10-02 | Lot matériel fixe par mission accepté. | Quantité totale à partager, indépendante du nombre de participants ; gain personnel de réputation identique conservé. M01 et point 47 actualisés ; récupération à définir. |
| 2026-10-02 | Récupération simple et partage libre acceptés. | N’importe quel participant engagé retire le lot auprès du PNJ via le carnet, une seule fois ; la fiche indique qui l’a reçu. Partage libre entre joueurs, sans répartition automatique. M01 et point 48 actualisés ; aucune implémentation ni validation en jeu. |
| 2026-10-02 | Mort du PNJ demandeur : annulation sans malus. | Accepté explicitement : une mission en cours devenue impossible est annulée sans malus de réputation pour les participants. M01, ADR B15 et point 49 actualisés ; aucune implémentation en jeu. |
| 2026-10-02 | Participant qui tue le PNJ demandeur : sanction personnelle très forte. | Décision explicite : très forte baisse de réputation de l’auteur, sans pénaliser ses coéquipiers. Contribution distincte de l’annulation de mission. M01, ADR B15 et point 50 actualisés ; montant et attribution technique à établir. |
| 2026-10-02 | Choix contextualisé des missions par le LLM. | Accepté explicitement : le serveur fournit les offres admissibles selon besoins et ressources ; le LLM choisit la mission, le destinataire et la présentation selon personnalité, confiance et réputation. ADR B16, M01 et point 51 actualisés. |
| 2026-10-02 | Négociation des missions reportée. | Décision explicite pour simplifier la première version : offre fixe, acceptation ou refus, questions possibles sans modification des conditions. ADR B16, M01 et point 52 actualisés. |

## Références

- [Carnet RadioSurvivor local](../maquettes/note-de-travail.html) : décisions antérieures et validation rapportée.
- [README du prototype](../../../README.md) : installation, transport et limites actuelles.
- [Serveur Lua](../../../Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor_Server.lua) : demandes, validation et diffusion.
- [Pont Python](../../../bridge/radio_bridge.py) : conversation, parallélisme et appels LLM.
- [Métadonnées du mod](../../../Contents/mods/batman_RadioSurvivor/42.21/mod.info) : identité et version minimale.
- [Bandits NPC sur Steam](https://steamcommunity.com/workshop/filedetails/?id=3268487204) : identité publique et compatibilité annoncée, consultées le 2 octobre 2026.
- [Artefact Claude téléchargé](../maquettes/note-de-travail.html) : référence locale confirmée par l’utilisateur.
- Sources Bandits! : `<Steam>/steamapps/workshop/content/108600/3268487204/mods/Bandits/42.20`, lues uniquement. Les fichiers et lignes probants figurent dans la section d’analyse ; ils décrivent cette copie, pas une validation en jeu 42.21.
