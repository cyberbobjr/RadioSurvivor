# Conception de Living Knox : règles et journal

Ce dossier rassemble les **fiches de conception** du moteur de PNJ Living Knox (étapes `LK` du plan), une par sous-système. Il applique la règle « Écriture indépendante » de [docs/annexes/plans/README.md](../plans/README.md) (section « Règles propres à Living Knox ») et la décision du 2026-10-03 consignée dans [LK00](../plans/LK00-cadrage.md) : aucun code de Bandits! ni de Project A-Life repris, traduit ou paraphrasé.

## 1. Règle d'écriture indépendante

- **Interdit** : copier, traduire ligne à ligne, paraphraser ou réorganiser du code de Bandits! (Workshop `3268487204`) ou de Project A-Life (Workshop `3803984183`). Cela vaut aussi pour la structure d'une fonction, ses noms internes, ses tables de données et ses enchaînements d'appels. Bandits! est sous copyright de son auteur (republication refusée) ; A-Life n'a aucune licence, donc tous droits réservés ([analyse d'architecture](../../architecture/ia-multijoueur.md), §1.5).
- **Autorisé** : reprendre une **idée de jeu** (un comportement, un mécanisme ou un enchaînement visible par le joueur), à condition qu'elle soit relevée avec sa source dans [docs/annexes/recherches/idees-bandits-alife.md](../recherches/idees-bandits-alife.md) (identifiant `I…`) et citée par le champ « Idées » de la tâche.
- **Valeurs chiffrées** (rayons, délais, probabilités) : seulement des points de départ, à recalibrer par nos propres mesures ; la fiche note d'où vient la valeur retenue.
- **Pendant le travail** : le code de ces deux mods sert seulement à vérifier une idée relevée (en-tête de `idees-bandits-alife.md`). Une fonction de Living Knox se conçoit à partir des sources de la section 2.
- **Historique** : l'ancien adaptateur `RS_Bandits.lua` du carnet appelait l'API publique de Bandits! sans en reprendre le code ; il a été retiré le 2026-10-08 (`E17-T02`) au profit de l'interface `RS_NPCProvider`. Ce n'est pas un modèle pour Living Knox.

## 2. Sources autorisées

| Source | Emplacement | Usage |
|---|---|---|
| Java vanilla 42.21 décompilé | `<decompiled>\42.21.0\java` | Contraintes du moteur : propriété des zombies, paquets réseau, dégâts, chemins |
| Lua vanilla 42.21 | `<PZ>\media\lua` | API exposée, actions chronométrées, événements |
| Base de connaissances | [.claude/pz-knowledge](../../../../.claude/pz-knowledge/README.md) | Faits déjà établis ; à chercher **avant** toute investigation |
| Nos bancs hors jeu | `tests/harness.py` (serveur et deux clients simulés sous lupa), `tests/test_kahlua.py` (VM Kahlua réelle du jeu) | Logique, protocole réseau, comportement de la VM |
| Nos tests en jeu | moteur RST (`dev/batman_RadioSurvivorTests`, étape E01), serveur dédié de test `tests/run_dedicated_smoke.ps1` | Mesures réelles en solo et en MP |
| Nos mesures | fichiers de résultat RST, journaux `console.txt` datés | Calibrage des valeurs, preuve d'un comportement |

Le banc `harness.py` simule le Java d'après le code décompilé : il ne **valide** pas l'API réelle. Une contrainte du moteur qui décide d'un choix se prouve par une ligne du Java ou du Lua vanilla, ou par une mesure en jeu.

## 3. Ce que les analyses de Bandits! et d'A-Life apportent

[bandits-analyse.md](../recherches/bandits-analyse.md), [alife-analyse.md](../recherches/alife-analyse.md) et l'[analyse d'architecture](../../architecture/ia-multijoueur.md) ont servi à la décision LK00-T02. Elles restent un **retour d'expérience** :

- une liste de **problèmes à prévoir** : propriétaire unique d'un zombie, gestes non transmis, dégâts appliqués par le propriétaire, deux mods de PNJ incompatibles (analyse d'architecture, §1) ;
- des **défauts à éviter**, rassemblés dans la section « Écarté » de `idees-bandits-alife.md` (IA exécutée par chaque client, objets créés à partir de rien, mêmes horaires pour tout le groupe…) ;
- des **points à mesurer** (analyse d'architecture, §8).

Elles n'apportent **jamais de code**. Une fiche peut citer un problème relevé par une analyse (« voir bandits-analyse.md §3 ») ; la solution, elle, s'appuie sur les sources de la section 2.

## 4. Fiche de conception par sous-système

Une fiche par sous-système : `docs/annexes/conception/<sous-système>.md`, nom court en minuscules avec tirets. Les noms déjà prévus par le plan sont :

| Fiche | Tâche qui la crée |
|---|---|
| `corps-et-animations.md` | `LK02-T01` (complétée par `LK02-T05`) |
| `corps-registre.md` | `LK02-T02` |
| `apparence.md` | `LK02-T03` |
| `neutralisation.md` | `LK02-T04` |
| `equipement.md` | `LK02-T06` |
| `consignes.md` | `LK02-T07` |
| [`rapports.md`](rapports.md) | `LK03-T02` (rapports d'état du propriétaire réel : bail, ordre, cadence, plausibilité de position, d'étage et de santé, refus journalisés ; brouillon du 2026-10-10) |
| [`deplacement.md`](deplacement.md) | `LK04-T01` (recherche de chemin d'un zombie, franchissements, portes et fenêtres en MP ; brouillon du 2026-10-10) |
| [`sante.md`](sante.md) | `LK07-T01` (dégâts subis par un corps, qui les applique en MP, santé du propriétaire, parades vanilla ; brouillon du 2026-10-10) |
| [`groupes.md`](groupes.md) | `LK08-T01` (registre serveur des groupes : schéma 1, bornes, succession du chef par API, persistance privée et contrôle au chargement ; LK08-T02 : types de groupes et profils de membres en fichiers de données Lua ; brouillon du 2026-10-10) |
| [`sites.md`](sites.md) | `LK08-T03` (choix du site d'un foyer sans charger la zone : bâtiment habitable, clairière dans les zones de forêt connues de la métagrille ou repli sur un bâtiment isolé, loin des bases et des autres foyers ; brouillon du 2026-10-10) |
| [`foyers.md`](foyers.md) | `LK08-T04` (aménagement d'un foyer au premier chargement réel de ses cases : barricades, lampe sur pile, sacs de couchage et caisse vide dans un bâtiment, feu de camp et tentes dans un camp ; objets vanilla posés une seule fois par l'autorité, marque persistante dans le registre des groupes ; brouillon du 2026-10-12) |
| [`stock.md`](stock.md) | `LK08-T06` (stock réel du groupe dans les conteneurs du foyer : catégories tirées des données de script, kit vanilla créé une seule fois après l'aménagement, inventaire de référence privé par identifiant d'objet relu quand la zone est chargée, vol constaté par l'objet retrouvé dans l'inventaire d'un joueur et rapporté à l'attitude) et `LK08-T07` (seuils selon les membres vivants, jours d'autonomie, rationnement au journal, besoins ordonnés lus par le cadre de décision) ; brouillon du 2026-10-12 |
| [`simulation.md`](simulation.md) | `LK09-T01` (simulation abstraite des groupes hors écran par heure de jeu : réserves, moral, repos, blessures, tâche par priorités, rattrapage borné, tirages reproductibles ; brouillon du 2026-10-10) |
| [`recits.md`](recits.md) | `LK10-T01` (histoires de groupe composées par le serveur en anglais et en français : gabarits, compatibilité des fragments, secrets privés ; brouillon du 2026-10-10) |
| [`journal.md`](journal.md) | `LK10-T02` (journal de récit des groupes : faits marquants datés et bornés, tirés du journal technique dans la même écriture, texte par clés de traduction EN/FR, aucun secret ; lecture admin et `API.journal` ; brouillon du 2026-10-12) |
| [`traces.md`](traces.md) | `LK10-T04` (traces lisibles en jeu : carnet vanilla en lecture seule déposé une fois au foyer d'un groupe disparu, notes sur le chef posées dans son cadavre, composés par l'autorité depuis le journal de récit et l'histoire publique ; brouillon du 2026-10-12) |
| [`attitude.md`](attitude.md) | `LK11-T03` (attitude d'un groupe envers chaque personnage joueur : valeur interne bornée, cinq niveaux et tendance sur trois faits, faits vus ou attribuables, déclin plafonné après un meurtre, persistance privée ; brouillon du 2026-10-10) |
| [`parole.md`](parole.md) | `LK11-T04` (parole de proximité : répliques courtes par situation, type, rôle et attitude, choisies par le serveur et traduites par chaque client ; bulle au-dessus du corps par `addLineChatElement`, ligne de chat locale ; envoi aux seuls auditeurs, une fois ; brouillon du 2026-10-11) |
| [`perception.md`](perception.md) | `LK05-T01` (perception des PNJ : vue selon la lumière, la ligne de vue `LosUtil.lineClear`, le champ, la posture et l'allure ; ouïe sans ligne de vue ; vigilance ; attention déterministe ; coût borné par passage ; résumé porté par le rapport d'état, filtré et gardé par l'autorité ; brouillon du 2026-10-11) |
| [`decisions.md`](decisions.md) | `LK05-T02` (cadre de décision côté autorité : objectifs du groupe notés par utilité à chaque heure de jeu, postes selon les rôles, journal du groupe ; cascade de priorités par membre, comportements en liste fermée permis par rôle, états à échéance, hasard tiré de l'identité ; sortie en consignes LK03, coût borné par passage ; brouillon du 2026-10-11) |
| [`fuite-reddition.md`](fuite-reddition.md) | `LK06-T05` (retraite selon santé, peur et moral du groupe, fuite pondérée par la proximité des menaces, reddition d'un non-combattant pacifique qui épargne le joueur tant qu'il ne frappe plus, appel à l'aide après un coup reçu et renfort des combattants proches ; brouillon du 2026-10-12) |
| [`routines.md`](routines.md) | `LK05-T03` (routines au foyer côté autorité : relevé des postes de guet, de la ronde et des couchages au premier chargement du foyer, sauvegardé avec le groupe ; quarts de 4 h, guet la nuit, ronde à l'aube ; sommeil assis près d'un lit ; menace qui interrompt ; vigilance portée par la consigne en MP ; brouillon du 2026-10-11) |
| [`besoins.md`](besoins.md) | `LK05-T06` (besoins individuels côté autorité : faim, soif, fatigue et peur de 0 à 100 par membre, sauvegardées avec lui ; pas horaire entier selon l'activité observée à l'écran ou l'horaire abstrait hors écran, même calcul et rattrapage borné ; peur montée par les menaces perçues ; envies lues par la cascade de décision ; repas abstrait en attendant LK05-T07 ; brouillon du 2026-10-11) |
| [`alerte.md`](alerte.md) | `LK05-T08` (alerte de proximité côté autorité : zombie, joueur hostile ou inconnu près du foyer ou d'un membre ; une fois par menace, niveau qui retombe en minutes de jeu ; comportement `alert` de la cascade (tâches et sommeil interrompus, regard vers la dernière position connue, geste de garde ou accroupi) ; cri : réplique, bruit et voix vanilla jouée par chaque client proche ; écouteurs pour les portes ; brouillon du 2026-10-11) |
| [`cibles.md`](cibles.md) | `LK06-T01` (choix de cible côté autorité d'après l'attitude : incident, couverture par trêve, provocation, type qui tire le premier ou avertit ; crochets facultatifs `covered` et `incident` ; ordre total sans tirage ; brouillon du 2026-10-12) |
| [`combat.md`](combat.md) | `LK06-T02` (mêlée contre un joueur : engagement par l'autorité, approche en course, regard et geste de frappe, portée et cadence de l'arme ; touche rapportée par le propriétaire, contrôlée et appliquée une seule fois par le serveur avec `DamageFromWeapon` + `sendDamage` ; comportement `fight` de la cascade ; brouillon du 2026-10-12) |
| [`zombies.md`](zombies.md) | `LK06-T04` (PNJ contre zombies vanilla : cible zombie d'un combattant, dégâts vanilla reproductibles, mort décidée par l'autorité, coup non mortel remis au client qui simule le zombie ; attaques des zombies au contact décidées par le serveur sur les seuils vanilla, dégâts par `LK_Health` ; bruit d'attrait ; brouillon du 2026-10-12) |
| [`defense.md`](defense.md) | `LK05-T09` (défense coordonnée du foyer côté autorité : déclenchée par l'alerte et une menace recensée près du foyer ; combattants valides aux postes qui donnent sur la menace, non-combattants et blessés aux abris intérieurs, renforts des membres proches ; repli à l'intérieur selon le rapport menace / combattants avec hystérésis ; tir ou mêlée depuis les postes avec une laisse portée par l'ordre de combat ; fin et marque d'après l'attaque pour les soins de LK07-T03 ; brouillon du 2026-10-12) |
| [`sommations.md`](sommations.md) | `LK11-T02` (avertissements à l'approche d'un foyer ou d'un groupe : guetteur unique, trois étapes — sommation arme en main, dernière sommation arme braquée, étape finale —, distance de sécurité et délai de tolérance selon l'attitude, sommation entendue avant toute escalade, coup de semonce réservé aux types qui tirent le premier, jamais de tir d'un groupe neutre, engagement seulement par `targetRule`, repli et reprise ; brouillon du 2026-10-12) |
| [`entretien.md`](entretien.md) | `LK05-T10` (entretien du foyer par ses membres : plein et réparation du générateur avec les matériaux du stock, sang lavé, verre brisé ramassé, effet appliqué une seule fois par l'autorité ; lumières allumées à l'entrée d'une pièce le soir ; morts et tombes non faits faute de cadavre unique ; brouillon du 2026-10-12) |
| [`expeditions.md`](expeditions.md) | `LK05-T05` (expéditions physiques des fourrageurs : bâtiment proche choisi par le serveur selon les manques du stock et la distance, conteneurs réservés, objets réels pris par catégorie dans une charge bornée, rangés au foyer et dans la référence du stock ; bascule hors écran sans perte de membre et retour abstrait reproductible ; brouillon du 2026-10-12) |
| [`nourriture.md`](nourriture.md) | `LK05-T11` (production de nourriture : cueillette en expédition de genre « forage » vers la zone de cueillette vanilla la plus proche, tirages des tables de cueillette vanilla selon le mois, l'heure et la météo, reproductibles à l'écran et hors écran, produits créés au dépôt avec les fonctions d'apparition vanilla ; arrosage des plantes du foyer avec l'eau du stock, jamais sous la pluie ; pêche et récolte non faites ; brouillon du 2026-10-12) |
| [`administration.md`](administration.md) | `LK13-T01` (outils d'administration : commandes réservées aux administrateurs, droit `PopmanManage` vérifié par le serveur à chaque requête, refus sans donnée et journalisé ; état, détail et journal des groupes, foyers en coordonnées, relève forcée, foyer déplacé vers une case contrôlée ; fenêtre du panneau d'admin en MP, console en solo ; brouillon du 2026-10-12) |
| [`aide.md`](aide.md) | `LK11-T06` (demandes d'aide : nourriture, eau ou soins demandés par un menu sur un PNJ, décision du serveur selon l'attitude et le stock réel sans passer sous la réserve visée, une demande par groupe et par période, don retiré du stock une seule fois et remis dans l'inventaire du joueur, journal du groupe, réplique motivée ; point d'entrée prévu pour une intention fermée du LLM du carnet ; brouillon du 2026-10-12) |
| [`troc.md`](troc.md) | `LK11-T08` (troc direct avec un groupe ami : fenêtre ouverte par un menu sur un PNJ, barème partagé avec le passeur de l'Ohio `RS_TradeValues.lua`, valeur selon les besoins du stock réel et marge selon l'attitude, le groupe ne cède rien sous sa réserve visée, échange appliqué en un seul appel serveur avec ordre d'écriture documenté, aucun objet dupliqué ni perdu même à la déconnexion ; brouillon du 2026-10-12) |
| [`intentions-collectives.md`](intentions-collectives.md) | `E10-T02` (chef du groupe et intentions collectives du carnet : mission de groupe proposée ou conclue par le seul chef du registre, membre qui renvoie au chef, empreinte de composition calculée `API.composition` revalidée à la réponse, décision au journal du groupe et dans le contexte des membres ; brouillon du 2026-10-12) |
| [`accords.md`](accords.md) | `E09-T05` (accords de faction trêve et alliance avec un groupe : registre privé, offre du serveur aux termes fixes, intention `negotiate`, conclusion par le chef et un joueur habilité revalidée à la réponse, crochet `covered` de `RS_Factions`, constat par `Decisions.aims` avant l'annonce ; brouillon du 2026-10-12) |
| [`relations.md`](relations.md) | `E09-T04` (relation personnelle d'un PNJ envers un personnage : écart borné à un niveau autour de l'attitude du groupe, intention `change_relation` motivée par un fait réel connu du PNJ, revalidée par le serveur ; brouillon du 2026-10-13) |
| [`contestation.md`](contestation.md) | `E10-T03` (contestation et refus d'un membre incarné : ordres du moteur refusés par règles fixes sans LLM, blessure, moral, attitude, rôle ; loyauté dérivée du moral et de l'ancienneté ; réactions `npc_member` des membres à une décision collective née d'une conversation ; journal `refusal`/`contest` et réplique entendue ; brouillon du 2026-10-13) |
| [`depart.md`](depart.md) | `E10-T04` (départ individuel `leave_group` d'un PNJ incarné : intention offerte à un personnage connu, liée au groupe et à l'empreinte de composition, revalidée puis une seule transition du registre (départ, succession, groupe `loners` d'un membre lié au même PNJ, foyer loin de l'ancien), trêves gardées comme trêves personnelles lues par le crochet `covered`, départ physique par une consigne LK03 ; brouillon du 2026-10-13) |
| [`passeur-offre.md`](passeur-offre.md) | `E13-T02` (livre du passeur : stock du passage tiré de façon reproductible, action `propose_trade` contrôlée contre la table validée, prix calculé par le serveur, offre figée par révision et réservée, mémoire des affaires qui fixe la marge permise, contexte `trade=` du LLM ; brouillon du 2026-10-13) |
| [`passeur-rendezvous.md`](passeur-rendezvous.md) | `E13-T03` (passage de la semaine réservé par la première offre figée d'une équipe, ponton de Riverside, nuit de 01:00 à 03:00, signal fusée rouge ou lampe en main, cordon tiré et monté par l'hélicoptère, annulations patrouille, hélicoptère, orage, retard annoncées à la radio ; brouillon du 2026-10-13) |
| [`passeur-echange.md`](passeur-echange.md) | `E13-T04` (échange sans contact au ponton : sac déposé, personne à moins de 20 cases, contenu évalué au barème avec conditions et plafonds, prise limitée au prix, contrepartie marquée posée dans le même sac en un seul appel serveur, tricherie refusée et notée, reprise par la marque, départ sans sac ; brouillon du 2026-10-13) |
| [`journal-du-dehors.md`](journal-du-dehors.md) | `E13-T05` (journal du dehors apporté par le passeur : document `printMedia` du mod, une édition par passage tirée de gabarits FR/EN sans secret ni fréquence, datée du jour de jeu, composée côté client, marque « lu » par édition, point d'appel `OutsideNewsServer.create(passage)` pour E13-T04, valeur de vente 2 et jamais repris ; brouillon du 2026-10-12) |
| [`vengeance.md`](vengeance.md) | `LK11-T05` (vengeance différée après la perte d'un membre tué par un joueur identifié : fait d'attitude `kill`, serment selon le type et l'attitude, délai de plusieurs jours, équipe réelle de combattants partie du foyer en expédition abstraite, traque à la dernière zone connue, corps créés seulement loin des joueurs, engagement par le choix de cible, abandon après trois traques manquées ou rancune éteinte ; brouillon du 2026-10-12) |
| [`raids.md`](raids.md) | `LK11-T07` (raids des pillards : base d'un joueur repérée par des signes lus par le serveur (refuge vanilla, générateur allumé, barricades, constructions) sur deux jours, éclaireurs réels partis du foyer qu'on peut tuer pour annuler le raid, annonce (réplique, journal, fait public), attaque par l'effectif réel en expédition abstraite, corps créés seulement loin des joueurs, forçage LK04-T04, retour ; un raid à la fois, options `RaidsEnabled` et `RaidDays` ; brouillon du 2026-10-12) |
| [`fortification.md`](fortification.md) | `LK14-T01` (barricades, murs et palissades vanilla posés par script sur le serveur, synchronisation, dégâts et réparation ; brouillon du 2026-10-10) |
| [`charge.md`](charge.md) | `LK13-T02` (mesure de charge du moteur : enveloppes des abonnés posées une fois, coût par image, par module et par abonné, fenêtre glissante, commandes réseau par type, écritures des registres, taille de l'état, budgets proposés ; requête d'administration `load`, suite `lk.load`, banc `tools/load_bench.py` ; brouillon du 2026-10-12) |
| [`../reputation-contract.md`](../../specifications-techniques/reputation-contract.md) | `E04-T02` (contrat RSREP-1 avec CharacterReputation : détection par descripteur, majeure 1 et capacités requises, identité de réputation relevée à la liaison du carnet et mémorisée pour les participants hors ligne, `recordEvent` dédupliqué par `eventId` avec ordre d'écriture `sending` puis `applied`, niveau sans valeur brute, derniers motifs par clé de traduction, repli de chaque appel, choix C1 à C6 à confirmer ; brouillon du 2026-10-13) |

Un sous-système nouveau prend sa fiche dans la tâche d'investigation ou de conception qui l'ouvre ; la tâche la cite dans son champ « Fichiers ».

### Contenu

1. **Problème** : ce que le sous-système doit permettre, en une ou deux phrases, et les tâches `LK…` concernées.
2. **Contraintes du moteur** : chaque fait avec sa preuve `fichier:ligne` (Java décompilé `J/…`, Lua vanilla) ou la référence d'une mesure, la Build (42.21.x) et un statut : `confirmé en jeu`, `confirmé statiquement` ou `hypothèse`.
3. **Choix** : la solution retenue, sa date et, s'il s'agit d'une décision de l'utilisateur, le renvoi vers la section « Décisions » de l'étape. Une fiche ne tranche pas seule une question `à décider` du plan.
4. **Alternatives écartées** : chaque option étudiée et la raison de son rejet.
5. **Idées reprises** : identifiants `I…` de `idees-bandits-alife.md`, avec ce qui en est retenu ou changé ; « aucune » sinon.
6. **Tests** : ce qui est prouvé, et où : banc `harness.py` / lupa, VM Kahlua (`test_kahlua.py`), suites RST en jeu (solo, serveur dédié, deux clients).
7. **Statut** : `brouillon`, `retenu`, `remplacé par …` ; points ouverts marqués `⚠`.

### Gabarit à copier

```markdown
# <Sous-système>

- Tâches : LK..-T.. (création), LK..-T.., LK..-T..
- Build : 42.21.x — Date : AAAA-MM-JJ — Statut : brouillon

## Problème

<Ce que le sous-système doit permettre.>

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| <fait> | `J/<chemin>.java:<ligne>` ou `media/lua/<chemin>.lua:<ligne>` ou <mesure> | confirmé statiquement |

## Choix

<Solution retenue, date ; renvoi à la décision du plan si elle vient de l'utilisateur.>

## Alternatives écartées

- <Option> : <raison>.

## Idées reprises

- <I…> : <ce qui est retenu, ce qui change> (ou « aucune »).

## Tests

- Banc lupa (`tests/harness.py`) : <tests>.
- VM Kahlua (`tests/test_kahlua.py`) : <tests ou « sans objet »>.
- En jeu (RST, serveur dédié, deux clients) : <suites, fichiers de résultat>.

## Points ouverts

- ⚠ <point à mesurer ou à décider>.
```

## 5. Liens avec le plan et la base de connaissances

- **Plan** : la fiche cite les identifiants `LK…` qu'elle sert ; la tâche cite la fiche dans « Fichiers » et sa preuve renvoie à la section de la fiche ou au test qui la valide. Une décision reste consignée dans la section « Décisions » de l'étape ([méthode](../plans/README.md)) ; la fiche la reprend sans la modifier. Un travail découvert en cours de conception devient une nouvelle tâche, jamais une extension silencieuse.
- **Base de connaissances** : un fait générique du moteur établi pour une fiche (API, piège Kahlua, comportement réseau) est aussi enregistré dans `.claude/pz-knowledge/`, reformulé sans nom de mod, avec sa preuve vanilla, puis la fiche y renvoie. Le choix propre à Living Knox, lui, reste dans la fiche.
- **Revue** : une fiche passe à `retenu` après relecture de l'utilisateur ; elle se met à jour lorsqu'une mesure en jeu dément une contrainte.
