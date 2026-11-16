# Audit UX de l'Atelier des voix (fr-FR, 1280 px et 800 px)

Périmètre : `bridge/atelier/` (app.js, steps/*.js, tradekeys.js, notekeys.js, sectionform.js, missions.js, widgets.js,
fields.js, itempicker.js, surveys.js, journal.js, verdict.js, ai.js, dialogs.js, i18n/fr.json, login.html).
Captures : `scratchpad/ux-audit/shots/<largeur>-<nn>-<écran>.png` (41 écrans par largeur, pages entières au-delà de 800 px de haut).
Les constats sont relus dans le code ; ceux marqués « capture » sont aussi visibles sur les captures.

Lecture : **présentation** = même fiche, même comportement du jeu. **DÉCISION** = change le format de la fiche, la
valeur par défaut, un choix de gameplay ou le périmètre d'une fonction : à trancher avant.

Impact : **H** = un ado bloque ou ne comprend pas sans aide ; **M** = friction, il s'en sort ; **B** = finition.

---

## 0. Bilan

| Impact | Constats | Dont décision | Dont dépendance | Présentation seule |
|---|---:|---:|---:|---:|
| H (haut) | 46 | 5 | 2 | 39 |
| M (moyen) | 47 | 5 | 0 | 42 |
| B (bas) | 18 | 4 | 0 | 14 |
| **Total** | **111** | **14** | **2** | **95** |

Les 15 décisions à trancher sont regroupées en section 11 (D01 à D11 pour les décisions, D12 et D13 pour les dépendances radio et la lecture des libellés).



---

## 1. Shell : barre du haut, liste des voix, onglets, statuts

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| S01 | Onglet « Journal » (app.js `tab.journal`, journal.js) | Un onglet technique avec lignes « pont », « jeu », « débog. », « Gravité », « Origine » (capture 39, 40) | Masquer l'onglet pour l'ado ; si gardé, une liste « Ce que les voix ont dit » sans filtres, texte seul | H | DÉCISION D01 (garder ou retirer) |
| S02 | Aide du journal (`journal.help`, `journal.no_bridge`) | « Les lignes du pont (…) » ; « relance l'atelier avec --game-log <fichier> » | Remplacer par « Ce qui s'est passé dans la radio, en direct » ; le message technique reste dans les logs | H | Présentation |
| S03 | Bouton « Importer » (`import.button`) | Mot technique ; le fichier attendu (.txt) n'est pas dit | « Ouvrir une voix (fichier) » avec sous-titre « fichier .txt » | M | Présentation |
| S04 | Bouton « Exporter » (`editor.export`) | Mot de développeur ; rien n'indique ce qui sort | « Sauvegarder une copie » | M | Présentation |
| S05 | Bouton « Aperçu de la fiche » (`editor.preview`) capture 35 | Affiche le texte brut de la fiche (`format=1`, `[place]`) | Renommer « Voir le texte du jeu » et le réserver au mode avancé (en bas de l'étape 5) | H | Présentation |
| S06 | Libellés de statut (`status.*`, voicelist.js) : « Du mod », « Ancienne version », « Modifiée », « Retirée », « Refusée par le jeu » | Vocabulaire de versions ; « Du mod » ne dit pas « voix d'origine » | « Voix d'origine », « Tu l'as changée », « Plus à l'antenne », « Le jeu refuse ta voix » ; couleurs gardées | M | Présentation |
| S07 | Légende en bas de la liste (voicelist.js, `STATUSES`) | Sept lignes de légende à côté de la liste | Une seule ligne « ● = voix refusée » ; le reste dans le tooltip du badge | M | Présentation |
| S08 | Titre « VOIX » en petites capitales monospace (`.side-h`) | Police technique, peu lisible | Titre « Tes voix » / « Voix de la radio » en texte normal | B | Présentation |
| S09 | Sous-titre « Radio Survivor : crée les voix qu'on entend à la radio » (`app.subtitle`) | Le nom du mod en premier, pas la promesse | « Invente les gens qu'on entend à la radio » | B | Présentation |
| S10 | Mise en page 800 px (capture 800-25) | La liste de voix (220 px) prend un quart de la largeur ; la rangée des étapes passe sur deux lignes | Replier la liste en bandeau horizontal scrollable (chips de voix) sous 900 px | M | Présentation |
| S11 | Badge « Enregistrée » / « Modifications non enregistrées » (`editor.saved`, `editor.unsaved`) | Mot d'état discret | Pastille verte « Sauvegardé » / orange « À sauvegarder » | B | Présentation |
| S12 | Bouton « Refusée par le jeu » en rouge dans la liste | Rouge seul pour un état ; le jeu n'est pas nommé dans la phrase | Garder la pastille, texte « Le jeu n'a pas pu lire cette voix » | M | Présentation |
| S13 | Boutons de la barre du haut (Enregistrer, Exporter, Aperçu, Essayer, Retirer) (capture 1280-25) | Cinq boutons de même poids ; « Retirer des ondes » rouge | Garder « Enregistrer » (principal) ; « Essayer », « Retirer » ; regrouper « Exporter » et « Aperçu » dans un menu « … » | M | Présentation |

## 2. Accueil et nouvelle voix (captures 00, 01, 02, 03)

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| N01 | Champ « Identifiant court » (app.js `who.id`, `who.id_help`) | Champ libre rempli automatiquement (« mae ») avec « Il devient le nom du fichier » | Ne plus afficher le champ : l'identifiant est pris du prénom, affiché en petit « Nom interne : mae » sous un lien « Changer » replié ; contrôle d'unicité à l'enregistrement | H | Présentation (le format garde le même id) |
| N02 | Champ « Nom » (`who.name`, placeholder « Prénom Nom ») | Bien, mais le placeholder ne donne pas d'exemple concret | Placeholder « Ex. Mae Tolliver » ; libellé « Comment elle s'appelle ? » | B | Présentation |
| N03 | Liste « Partir de » (`new.start_from`, `new.copy_of`) | Liste de 17 voix sous « Une copie de ... » ; la copie suppose de comprendre le format | Deux grosses cartes : « Partir de zéro » / « Partir d'une voix existante » (ouvre la liste) | M | Présentation |
| N04 | Texte d'accueil (`welcome.step1..3`, `welcome.text`) | Trois étapes numérotées, « Rien n'est enregistré tant que tu n'as pas cliqué sur Enregistrer » | Trois pictos + une phrase chacun ; « Le jeu relit ta voix en moins de 30 secondes » gardé | B | Présentation |
| N05 | Description courte (`who.description`, `who.description_help` « Pour toi seulement : le jeu ne la lit pas ») | Zone de 8 lignes pour une ligne | Champ une ligne, placeholder « Ex. Une infirmière qui veut rentrer à sa clinique » | M | Présentation |
| N06 | Choix « À l'antenne ? » (`who.state`, `choice.state.*`) | Quatre choix avec explications longues (« La voix garde sa fréquence mais ne répond pas ») | Quatre cartes avec un mot : « Elle répond », « Elle se tait », « Elle est partie », « Elle est morte » ; explication en tooltip | M | Présentation |
| N07 | Tous les champs de l'accueil sont en colonnes libellé-champ (capture 03) | Les libellés et les aides sont en deux colonnes, à gauche petit | Une question par écran (pattern « une question, une réponse ») : nom, puis description, puis état | M | Présentation |

## 3. Étape 2 « Où et quand » (captures 06, 08, 09, 10)

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| W01 | Bande de fréquence (where.js `bandEditor`, `where.band`, `where.band_low/high`) | Deux champs numériques « de [230,0] à [239,8] MHz », pas de 0,2 (capture 08) | Afficher la bande en texte « 230,0 à 239,8 MHz » avec un bouton « Changer » ; à l'ouverture d'une nouvelle voix, bande tirée toute seule ; on ne tape plus de MHz | H | Présentation (le format `frequency_range=` reste) |
| W02 | Bouton « Trouver une bande libre » (`where.find_band`) | Bouton à côté de deux champs : on ne sait pas ce qu'il fait ni pourquoi | Renommer « Tirer une bande libre » avec tooltip « Choisit une bande qu'aucune autre voix n'utilise » | M | Présentation |
| W03 | Message de chevauchement (`where.overlap`) capture 10 | « Cette bande croise celle de : Boone Tackett. » sans action | Ajouter « Tirer une autre bande » dans le même encadré | H | Présentation |
| W04 | Aide de la bande (`where.band_help`, `help.head.frequency_range.tip`) | Phrase + popover de 154 caractères sur « une bande ou des fréquences fixes » | Une phrase : « Chaque partie tire une fréquence dans cette bande. » ; le reste dans « ? » | M | Présentation |
| W05 | Radio nécessaire (`where.radio`, `choice.radio.*`) | Deux radios : « Toute radio qui émet » / « Seulement un gros poste » | Déjà prévu : choix du type de radio (autre agent). Dépendance : ne pas redessiner, retirer le libellé « Radio nécessaire » | H | Dépendance (agent radio, D12) |
| W06 | Fréquences fixes (`where.fixed`, `where.fixed_help`) | Champ texte libre « 145.0 », séparées par des virgules, visible seulement si la fiche en a | Badge « Fréquence fixe » avec la valeur ; saisie avec le même sélecteur que la bande (autre agent) | H | Dépendance (agent radio, D12) |
| W07 | Heures d'écoute (`where.hours`, `where.hours_help`) | « Une garde peut passer minuit (22:00 à 06:00) » ; « garde » est un mot technique | Trois préréglages en cartes : « Toujours », « La nuit », « Le jour » ; « Heures sur mesure » replié | H | Présentation (valeurs `listen=` identiques) |
| W08 | Heures d'écoute, champs « Début » / « Fin » (widgets.js `timeRange`) | Deux champs heure en format 24 h | Garder les champs dans « Heures sur mesure » uniquement | M | Présentation |
| W09 | « Cette voix est-elle sur la carte ? » (`where.location`, `choice.location.*`) | Trois radios ; « Choisie pour un sauvetage » ; sens de « carte » flou | « Personne ne sait où elle est » / « Elle est à un endroit précis » / « Le jeu la place pour un sauvetage » | M | Présentation |
| W10 | Coordonnées x, y, z (where.js `locationEditor`, `where.coords`) | Trois champs numériques ; l'aide demande de faire un clic droit dans le jeu | Remplacer par « Choisir dans mes relevés » (liste des cases relevées en jeu, voir M11) ; x, y, z restent visibles seulement en « Réglages avancés » | H | DÉCISION D02 (saisie manuelle des coordonnées : garder ou non) |
| W11 | Appels spontanés (`where.call_one_in`, `where.call_one_in_help`) | « Une chance sur N par heure », champ numérique, « 5 : environ un appel toutes les cinq heures » | Curseur à cinq crans : « Jamais », « Rarement », « Parfois », « Souvent » ; le nombre n'apparaît qu'en tooltip | H | DÉCISION D03 (valeurs des crans = gameplay) |
| W12 | Texte de l'appel (`where.call`, `where.call_placeholder` « Il y a quelqu'un ? Ici Mae sur %1. À vous. ») | Symbole `%1` à écrire à la main ; le texte apparaît seulement si la chance est > 0 | Bouton « Ajouter ma fréquence » qui insère le texte ; `%1` jamais visible | H | Présentation |
| W13 | Clé du texte de l'appel (`where.call_text`, `where.call_text_placeholder` « IGUI_RadioSurvivor_Call_Mae ») | Une clé de traduction affichée pour les voix du mod | Réglage avancé, caché pour une voix nouvelle | H | Présentation |
| W14 | Aide « ? » sur chaque ligne (`hint` de help.js) | Une douzaine de « ? » sur l'écran (capture 08) | Un seul « ? » par section ; le détail en popover | M | Présentation |
| W15 | Popover de la bande (capture 09) | Titre, « Dans le jeu », « Exemple » ; texte de 150 à 330 caractères | Limiter à « Ce que c'est » + « Exemple » ; 2 lignes maximum | M | Présentation |
| W16 | Libellé de section (`where.question`, « Où peut-on l'entendre, et quand ? ») | Question correcte mais trois sujets en même temps | Bon ; découper en trois questions avec un titre chacune | B | Présentation |

## 4. Étape 3 « Personnalité » (captures 11, 12)

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| P01 | Zone « Sa personnalité (en anglais) » (personality.js, `personality.prompt`, 14 lignes, `lang="en"`) | Gros bloc de texte en anglais, obligatoire ; un ado de 14 ans ne peut pas l'écrire | Mettre en premier « Décris-la en français » (IA) ; le bloc anglais devient « Modifier le texte (anglais) » replié ; si vide, l'IA s'ouvre seule | H | Présentation (le texte reste en anglais) ; voir DÉCISION D05 |
| P02 | Bouton « L'écrire avec l'IA » (`personality.ai`) | Bouton grisé si l'IA n'est pas configurée, et le message technique « copie bridge/.env.example » (`ai.unavailable`) | Pour l'ado : « L'IA n'est pas branchée : demande à l'adulte qui gère l'atelier » ; le détail technique dans le tooltip du mainteneur | H | Présentation |
| P03 | Panneau IA (ai.js `personalityPanel`, `ai.describe`, `ai.describe_help`) | Trois éléments : description, « L'écrire », « L'utiliser » ; texte d'aide « L'IA écrit la personnalité en anglais » | Garder ; remplacer l'aide par « Écris 2 ou 3 phrases, l'IA fait le reste » | M | Présentation |
| P04 | Liste des actions (personality.js, `personality.actions`, `action.*`) | Onze cases à cocher ; libellés « Donner une fréquence », « Montrer un quartier », « Laisser un sac de matériel » | Cartes avec un emoji et un mot (« Parler », « Donner des missions », « Faire du troc »…) ; « Parler » coché et verrouillé | H | Présentation (les clés `actions=` ne changent pas) ; le choix par défaut est DÉCISION D10 |
| P05 | Aide des actions (`personality.actions_help` « Parler est toujours possible. Le reste permet à la voix d'agir dans le jeu. ») | « agir dans le jeu » est vague | « Parler est toujours possible. Coche ce qu'elle peut faire en plus. » | B | Présentation |
| P06 | « Voix à faire connaître » (`personality.shares`) | Cases avec les noms de voix ; le sens de « faire connaître » demande un popover | Titre « Elle peut donner le contact de… » ; cases avec photo ou emoji | M | Présentation |
| P07 | Essai de la voix (`ai.try_*`, ai.js `tryDrawer`) | Panneau à droite : message « Ton message », « Recommencer », « Fermer » ; texte « Rien ne change dans le jeu » | Bon. Renommer « Discuter avec la voix » ; bouton « Envoyer » en icône ; placeholder gardé | M | Présentation |

## 5. Étape 4 « Missions » (captures 13 à 19)

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| M01 | Carte de lieu : `<code>` avec l'identifiant (missions.js `placeCard`, capture 18) | « clinic », « drop_dumpsters », « drop_bookstore » en petit | Supprimer l'identifiant de la carte ; tooltip seulement | H | Présentation |
| M02 | Carte de mission : `<code>` avec l'identifiant (missions.js `missionCard`, capture 15) | « scout_clinic », « clear_clinic », « secure_clinic » | Idem M01 | H | Présentation |
| M03 | Champ « Seulement après » (`mission.after`, missions.js `others`) | Options « scout_clinic (Reconnaître un bâtiment) » : l'identifiant est dans la liste | Options « 1 · Reconnaître un bâtiment » ; le numéro de la carte sert de repère | H | Présentation |
| M04 | Lieu obligatoire (`mission.target`, « Lieu (obligatoire) ») et « Lieu » en « Plus d'options » (missions.js) | Deux libellés pour le même champ selon le genre de mission | Un seul libellé « Où ça se passe ? » ; le texte « obligatoire » devient une pastille rouge | M | Présentation |
| M05 | Options des lieux dans les listes (fields.js `fieldOptions`, `label`) | « West Point clinic (11880,6878,0) » : coordonnées affichées dans chaque liste | Retirer les coordonnées du libellé ; le lieu est repéré par son nom et son icône | H | Présentation |
| M06 | Champ « Ce que dit la voix » (`mission.story`, `mission.story_placeholder`) | Obligatoire en pratique ; placeholder en anglais « I need to know what is left of my clinic. » ; 200 caractères | Garder ; bouton « Proposer » mis en premier avec « ou écris-la en anglais » ; compteur « 23 / 200 » | H | Présentation |
| M07 | Champ « Sets state » (`mission.sets_state`, `mission.sets_state_help` « Un mot (comme returned) ») | Libellé « État de l'histoire une fois réussie », exemple technique | Sortir de « Plus d'options » ; libellé « Ce qui change dans son histoire » ; exemple en français ; à cacher si vide | M | DÉCISION D08 (vocabulaire des états) |
| M08 | Libellés « Délai de ramassage (heures) », « Quoi apporter », « Combien » (`param.*`) | Jargon (« ramassage », « fourchette ») ; « Combien » ouvre deux champs « de 2 à 4 » | « Attendre combien d'heures ? » ; « Combien ? » avec un curseur à deux poignées affichant « entre 2 et 4 » | H | Présentation |
| M09 | Type de mission (`missions.type`, `typeHint`) | Bien : cartes avec explications ; le « ? » sur le type liste les réglages en jargon (`param.count` « Fenêtres et portes ») | Garder les cartes ; réglages du « ? » en phrases simples | M | Présentation |
| M10 | Cases « Sert à » d'un lieu (`places.uses`, `use.*`) (capture 14) | Quatre cases par lieu : « Repère sur la carte », « Lieu de mission », « Planque », « Rendez-vous de troc » ; 3 lieux = 12 cases | Quatre pastilles à choisir sur une ligne avec icône (carte, cible, boîte, poignée de main) ; « Planque » expliquée au survol | H | Présentation |
| M11 | Relevés en jeu (surveys.js, `surveys.*`, capture 19) | Libellés bruts du jeu : « conteneur metal_shelves », « pièce dinerkitchen », coordonnées en code `10617, 10617, 0` | Traduire conteneur et pièce via les libellés du jeu (`Metal shelves`, `Dinerkitchen`) ; coordonnées en petit | H | Présentation (texte seulement) |
| M12 | Aide « Relevés en jeu » (`surveys.help`, `help.ui.surveys.tip`) | Phrase sur « clic droit… (en solo avec le mode debug…) » et un popover avec le chemin « Zomboid/Lua/batman_RadioSurvivor/workshop-places.txt » | Texte : « Quand tu joues, fais un clic droit sur une case pour la noter. » ; le chemin disparaît de l'écran de l'ado | H | Présentation |
| M13 | Coordonnées d'un lieu (missions.js `placeCard`, `places.at`) | x, y, z en trois champs numériques ; z = 0 par défaut ; « Voir sur la carte ↗ » | Lieu créé à partir d'un relevé (complet) ; saisie manuelle en « Réglages avancés » ; lien carte : « Voir sur la carte » | H | DÉCISION D02 (coordonnées saisies à la main : garder ou non) |
| M14 | Ajouter un lieu (missions.js `places.ask`) | Demande un nom, puis crée un lieu aux coordonnées vides : invalide tant qu'on n'a pas tapé x et y | Le bouton propose : « Depuis mes relevés » / « Nouveau lieu » ; un lieu ne se crée qu'avec ses coordonnées | H | Présentation |
| M15 | Nom sur la carte (`places.label`, `places.label_help`) | Champ libre limité à 48 octets ; « Vu par les joueurs : pas de secret ici » | Compteur « 12 / 48 lettres » ; aide raccourcie « Les joueurs le voient » | M | Présentation |
| M16 | Pastilles d'étapes (`editor.steps`) et compteurs de points (`checks.title`) | Un chiffre rouge par étape, sans sens ; « 2 point(s) à regarder » | Remplacer par « À vérifier : 2 » ; puces de vérification en langage simple (checks.js) | M | Présentation |
| M17 | Panneau « Plus d'options » d'une mission (missions.js `mission.more`) | Quatre réglages (lieu, « Proposée », « Qui débloque la suivante », état) | Garder replié ; renommer « Réglages en plus » ; « Proposée » devient « Très souvent / Souvent / Parfois » (`chance.*` existant) | M | Présentation |
| M18 | Cartes des types de mission (missions.js `addMissionPanel`, capture 17) | Neuf cartes en grille, texte d'aide de 100 caractères | Garder les cartes ; icône par type ; une phrase par carte | M | Présentation |
| M19 | État vide sans mission (`missions.none` « Pas encore de mission : choisis un genre ci-dessous. ») | Bien mais le bas de l'écran est loin | Mettre les cartes de types en haut quand la liste est vide | M | Présentation |
| M20 | État vide sans lieu (`places.title`, `places.help`) | « Ses lieux (0) » replié ou ouvert, texte « Les lieux que la voix connaît… » | Message « Elle n'a encore aucun lieu. Commence par un endroit qu'on connaît. » + bouton | M | Présentation |
| M21 | Cases « Planques » d'une mission (`mission.drops`, `mission.drops_help`) | Liste des lieux avec coordonnées (cf. M05) | Idem M05 ; « Rien de coché : toutes les planques » en italique | M | Présentation |
| M22 | Champ « Délai » et « Combien » en lignes séparées (capture 15) | Une ligne par paramètre, trois types d'entrée différentes (nombre, liste, fourchette) | Une seule « carte réglages » avec le même style de champ | B | Présentation |

## 6. Étape 5 « Récompenses » (captures 20 à 23)

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| R01 | Cartes d'ajout de récompense (rewards.js, `reward.*`) | Quatre cartes « Sac de matériel », « Une fréquence », « Une leçon », « Carte de planque » ; « Une fréquence » s'explique en jargon | Icônes ; « Une fréquence » devient « Un contact radio » | M | Présentation |
| R02 | Chances (`chance.*`, `rewards.one_in` « environ 1 fois sur 3 ») | Bon : « Rarement / Normalement / Souvent » ; mais « 1 fois sur 3 » est un calcul | Garder les mots ; « environ 1 fois sur 3 » en petit ; ok | B | Présentation |
| R03 | Catégorie d'un « Sac de matériel » (fields.js `category`) | Liste « -- choisir -- » puis catégories | Mettre le choix par défaut utile (« Nourriture ») et des icônes | M | Présentation |
| R04 | « Pour aller plus loin » : Troc, Note de fréquence, Ses propres catégories (rewards.js `optionalSection`, `categoriesPanel`) | Trois panneaux repliés dont l'un demande un « identifiant de la nouvelle catégorie » | Regrouper en trois cartes « Troc », « Note », « Catégories perso » ; le champ d'identifiant est généré du nom | H | Présentation (nom) ; DÉCISION D06 (garder « Catégories perso » ?) |
| R05 | Case « Cette voix fait du troc » (rewards.js, `advanced.trade.enable`) | Coche placée dans un panneau replié, mais la case « Faire du troc » est à l'étape 3 | Une seule action : cocher « Troc » ici ajoute l'action en étape 3 (existe, `SECTION_ACTIONS`) ; afficher « Action ajoutée à l'étape 3 » | M | Présentation |
| R06 | Texte d'aide des récompenses (`rewards.help`) | « Une récompense est tirée au hasard dans cette liste… » | Une phrase : « Une seule récompense est tirée au hasard. » | B | Présentation |

## 7. Panneau Troc (captures 25 à 31)

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| T01 | Lignes de marchandises : nom + poids (`stock.js`, tradekeys.js `stockLines`, `formatKg`) | « Bouteille de whisky 1,7 kg » ; le poids est « pour information » (`help.trade.item.tip`) | Retirer le poids de la ligne ; l'afficher seulement au survol | H | Présentation |
| T02 | Quantité d'une ligne : liste « Un nombre / Dans le lot « alcool » » + « de 2 à 8 » (`amountCells`) | Deux contrôles pour une quantité ; « de » et « à » en mots | Bouton segmenté « Un nombre / Dans un lot » ; quantité en curseur « 2 à 8 » ; pour un lot, « Dans le lot » seulement | H | Présentation |
| T03 | Lots : nom (`lot.name`, `lot.name_placeholder` « nom du lot ») (tradekeys.js `lots`, capture 27) | Champ libre ; l'ado tape « Alcool » et voit « alcohol » (le nom est remis en minuscules par `lotId`) ; le nom technique est visible | Nom saisi affiché tel quel ; l'identifiant est généré et caché ; placeholder « Ex. Alcools » ; libellé « Nom du paquet » (lot = paquet) | H | Présentation (le nom technique est stocké, même format) |
| T04 | Lots : « de 2 à 5 au total », « au plus 3 sortes » (`lot.in_all`, `lot.kinds_before`, `lot.kinds_after`) | Trois champs numériques en phrase ; « sortes » est un mot de développeur | Un curseur « Entre 2 et 5 en tout » ; « Au plus 3 sortes différentes » avec un stepper ; libellés expliqués | H | Présentation (valeurs identiques) |
| T05 | Bouton « + Ajouter un lot » (`lot.add`) | Mot « lot » non expliqué | « + Ajouter un paquet » ou, mieux, « + Mettre plusieurs objets ensemble » ; aide courte en une phrase | M | Présentation (libellé) ; DÉCISION D07 si le mot change dans le modèle |
| T06 | Deux boutons « Ajouter des objets » (stock et « Ce que la voix accepte ») (capture 28) | Même libellé deux fois ; le sens diffère | Stock : « Ajouter ce qu'elle vend » ; acceptés : « Ajouter ce qu'elle prend en paiement » | H | Présentation |
| T07 | Liste « Arrive par » (`key.trade.arrival`, `choice.arrival.*`) | Select « Route / Bateau / Dépôt caché » avec « (obligatoire) » | Trois cartes avec icône (voiture, bateau, boîte) ; description courte du choix (help existant) | M | Présentation |
| T08 | Rendez-vous (`key.trade.landing`, `trade.no_landing`) | Cases de lieux « Roadside on the main road, Echo Creek » ; si aucun lieu : « ajoute un lieu marqué rendez-vous de troc » | Bouton « Créer le lieu de rendez-vous » qui ouvre un lieu déjà marqué | H | Présentation |
| T09 | Passage « tous les 4 jours » (`trade.every`, `trade.days`, `every_days`) | Champ numérique entre deux mots ; « Un passage du marchand tous les N jours de jeu (1 à 28) » | « Revient tous les [4] jours » avec curseur 1–28 ; aide raccourcie | M | Présentation |
| T10 | « Lieu tranquille depuis » (`key.trade.delay_hours`, `trade.hours_unit` « heures sans personne autour ») (capture 25) | Champ vide, sans unité claire, aide de 193 caractères sur « moins de 100 cases » | Chips « Tout de suite / 2 h / 6 h » ; valeur vide = « Tout de suite » ; aide raccourcie | H | DÉCISION D04 (valeurs des chips = gameplay) |
| T11 | Marge « de 10 % à 50 % » (`key.trade.margin`, `margin`) | Réglage caché du jeu, présenté comme un champ à remplir ; le texte dit « le jeu la compte en secret » | Retirer de l'écran principal ; « Réglages avancés » de la section, repliés ; valeur par défaut affichée « Réglage du jeu » | H | DÉCISION D09 (la marge reste-t-elle réglable par l'ado ?) |
| T12 | Accord « Ce que la voix accepte » : huit catégories + « Objets acceptés : 72 » (`accept.count`, `categoryOption`) | Compteurs techniques ; « prix au troc » (`accept.no_value`, `check.not_sellable`) | Texte « Elle prend en paiement : Bijoux (72 objets), Nourriture… » ; « prix au troc » remplacé par « qu'un marchand peut acheter » | H | Présentation |
| T13 | Phrase « Seuls les objets qui ont un prix au troc comptent » (`key.trade.accept.help`, `browser.sellable_only`) | Jargon commercial | « Seulement les objets que les marchands achètent » | M | Présentation |
| T14 | Trop de champs d'un coup (capture 25, 800 px : 9 champs, ~1 900 px de haut) | Un seul panneau très long, huit champs « obligatoire » | Découper en trois sous-étapes : « Quoi vend-elle ? » / « Quand et où ? » / « Qu'accepte-t-elle en échange ? » | H | Présentation |
| T15 | Étiquettes « (obligatoire) » (`field.required`) sur sept champs du troc | Un ado lit « obligatoire » sept fois | Une seule étoile + légende en haut « * obligatoire » | M | Présentation |
| T16 | « Marge » et « Lieu tranquille » sans valeur initiale (capture 25) | Champs vides qui ressemblent à des erreurs | Valeur par défaut affichée en gris « Par défaut » | M | Présentation |

## 8. Panneaux de la note et catégories, fenêtres annexes (captures 30 à 41)

| ID | Élément (fichier, clé) | Ce que l'ado voit | Correction proposée | Impact | Type |
|---|---|---|---|---|---|
| X01 | Note : texte (notekeys.js `noteText`, `note.text_intro`, `note.bytes` « 12 / 40 », `key.note.text.placeholder` « Mae écoute sur %1 MHz ») (capture 32) | « Écris %1 là où sa fréquence doit apparaître » ; compteur en octets ; « une lettre accentuée compte pour deux » | Compteur en caractères « 12 / 40 » ; bouton « Ajouter ma fréquence » ; ligne d'aide « Une ligne par phrase, 8 lignes maximum » | H | Présentation (la limite octets reste contrôlée par le code) |
| X02 | Avertissement « Une ligne doit contenir %1 » (`note.needs_frequency`) | Message technique | « Ajoute ta fréquence dans une ligne : bouton ci-dessus » | H | Présentation |
| X03 | Caractères interdits (`note.bad_chars` « Pas de < > ^ ni de % seul (seulement %1). ») | Liste de signes techniques | Remplacer par « Caractères non permis : < > ^ » ; le « % » seul est interdit sans message technique | M | Présentation |
| X04 | « Trouvée dans » (`key.note.loot`, placeholder « MedicalOfficeDesk ») et « Boîtes à gants » (`key.note.glovebox`, placeholder « GloveBox ») | Noms internes anglais du jeu, à taper ou choisir dans une liste | Liste à choix avec libellés français (« Bureau médical », « Boîte à gants de police ») ; saisie libre cachée | H | Présentation (les codes restent stockés) |
| X05 | « Chances de la trouver » (`stock.chance`) | Libellé d'une liste de lieux | « Elle se trouve » + les mots Rarement/Normalement/Souvent (déjà en place) | B | Présentation |
| X06 | « Sur les morts » (`key.note.corpse`, `note.corpse_switch`) | Interrupteur « Un mort qui porte un talkie peut l'avoir sur lui » | Garder ; phrase plus courte « Un zombie peut la porter » | B | Présentation |
| X07 | « Réglages avancés » de la note : « Objet de la note », « Clé du texte » (`key.note.item`, `key.note.key`, `note.own_item`) | Champ d'objet et clé de traduction pour les voix du mod | Cachés pour une voix nouvelle (déjà prévu) ; texte « Cette note est réglée par le mod » | M | Présentation |
| X08 | Catégories perso : « identifiant de la nouvelle catégorie » (rewards.js `categoriesPanel`) | Champ libre pour un identifiant technique (capture 33) | Champ « Nom de la liste » ; l'identifiant est généré (`voice.slug`, déjà en place) | H | Présentation ; DÉCISION D06 |
| X09 | « Ses propres catégories » : `<code>` avec l'identifiant (rewards.js `categoriesPanel`) | Identifiant technique affiché sur la carte | Retirer l'identifiant de la carte | M | Présentation |
| X10 | Ajout d'un objet dans le navigateur (itembrowser.js, `browser.*`, capture 30, 31) | Recherche « whisky » bien, colonnes « Catégorie » et « Poids » ; aide « nom technique gardé dans la fiche » | Retirer la colonne Poids ; aide : « Survole un objet pour voir son nom technique » déplacé en tooltip | M | Présentation |
| X11 | Navigateur : bouton « Ajouter la sélection (N) » et « Coche les objets à ajouter » (`browser.add_selected`, `browser.title_multi`) | Bon, mais le raccourci « Entrée » n'est pas dit | Ajouter « (Entrée pour cocher) » en petit | B | Présentation |
| X12 | Confirmation « Retirer « X » des ondes ? Le jeu l'enlève en moins de 30 secondes. » (`confirm.remove`, capture 34) | Phrase correcte, bouton « Retirer des ondes » rouge | Garder ; bouton « Oui, la retirer » | B | Présentation |
| X13 | Confirmation « Supprimer pour de bon la voix « X » ? » (`confirm.delete`) | Bon | Garder | B | Présentation |
| X14 | Message « Remplacer la copie de « X » par la version du mod ? » (`confirm.restore`) | « Tes modifications seront perdues » : bon ; le bouton « Revenir à la version du mod » est long | « Revenir à la version d'origine » | B | Présentation |
| X15 | Import d'une voix qui existe (app.js `importFile`, `import.exists`, capture 37) | « Une voix avec cet identifiant existe déjà (darlene). Choisis un nouvel identifiant : » + champ libre | Bouton « Importer comme une nouvelle voix » (`darlene_2` automatique) ; champ d'identifiant replié | H | Présentation |
| X16 | Glisser un fichier (`import.drop` « Dépose une fiche de voix (.txt) pour l'importer ») | « Fiche de voix », « .txt » | « Glisse ici le fichier d'une voix » | M | Présentation |
| X17 | Voix refusée : bandeau (verdict.js, `verdict.title`, capture 38) | « Le jeu a refusé cette voix, ligne 14 de la fiche » ; message anglais brut « bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM…) » ; `<code>` | Titre « La voix ne marche pas encore : à corriger dans l'étape Où et quand » ; bouton « Corriger » ; message brut replié en « Détails pour un adulte » ; la ligne 14 n'apparaît pas | H | Présentation |
| X18 | Voix refusée : texte « Tant que ce n'est pas corrigé, le jeu garde la dernière version qui marchait… » (`verdict.silent`) | Trois phrases dont une très longue | « Le jeu garde l'ancienne version en attendant. » | M | Présentation |
| X19 | Voix refusée : « Le jeu relit la fiche dans les 30 secondes » (`code.voice_saved`, `welcome.step3`) | Chiffre de délai répété partout | Dire une fois, à l'enregistrement : « Enregistrée. Le jeu la lit dans 30 secondes. » | B | Présentation |
| X20 | Journal : filtres « Voix », « Gravité », « Origine » (journal.js, capture 40) | Trois listes déroulantes de vocabulaire de développeur | Voir S01 ; si gardé : une seule liste « Voir : toutes / les voix / le jeu » | H | DÉCISION D01 (voir S01) |
| X21 | Journal : niveaux « débog. », « info », « attention », « erreur » (`journal.level.*`) | Mots de développeur ; « débog. » abrégé | Retirer le niveau de l'affichage de l'ado ; couleurs seulement | M | Présentation |
| X22 | Journal : libellé « pont » / « jeu » (`journal.source.*`) | « pont » = mot de développeur (le serveur de l'atelier) | « L'atelier » / « Le jeu » | M | Présentation |
| X23 | Connexion réseau (login.html, `login.intro`) | « entre le mot de passe écrit dans bridge/.env (ATELIER_PASSWORD) » : chemin et nom de variable pour un ado ; non capturé (mode réseau absent) | « Demande le mot de passe à l'adulte qui gère la radio. » ; détail technique dans la doc | H | Présentation ; DÉCISION D11 (qui se connecte ?) |
| X24 | Réponse 409 à l'import (console du navigateur, capture 37) | Aucune conséquence visible (import refusé proprement) | Rien à faire pour l'ado | B | Technique |

---

## 9. Comptage (lignes des tableaux 1 à 8 : H / M / B)

Compte automatique des lignes S/N/W/P/M/R/T/X : 111 constats (H 46, M 47, B 18) ; 95 présentation, 14 marqués décision, 2 dépendances.

## 10. Règles de conception (charte de l'atelier, à mettre dans docs/)

1. **Rien de technique par défaut.** Pas d'identifiant, de code, de coordonnée, de chemin, de clé de traduction ni de nom interne visible sans « Détails » fermé. Le mot de l'ado est le seul affiché.
2. **Un nombre du jeu = un choix en mots.** Curseur, cran ou pastille avec un nom (« Rarement », « La nuit », « Entre 2 et 5 ») ; le nombre n'apparaît qu'en tooltip. Jamais « une chance sur N », jamais de « MHz » à taper.
3. **Remplir, pas taper.** Ce que le jeu peut deviner (identifiant, bande libre, nom interne, valeur par défaut) est généré. L'ado ne tape que ce qu'il invente : prénom, texte de la voix, nom du lieu.
4. **Une question, une réponse, une aide.** Une question par écran ou sous-écran ; une phrase d'aide visible (12 mots maximum) ; le reste derrière « ? » ; pas de « (obligatoire) » répété.
5. **L'anglais se fait écrire, il ne se tape pas.** Tout texte imposé en anglais (personnalité, phrase de mission) part d'une description en français et de l'IA ; le texte anglais se modifie seulement dans un panneau replié.
6. **Vocabulaire de l'ado.** Dire « voix, lieu, mission, cadeau, troc, note, radio ». Interdits à l'écran : identifiant, slug, MHz, poids, kg, lot (dire « paquet »), sorte, template, paramètre, pont, octets, clé, coordonnées, format, fiche (dire « voix »). Tutoiement, phrases courtes, verbes d'action.
7. **Choisir dans une liste, jamais recopier.** Choix fermé = cartes avec icône ou pastilles ; choix multiple = cases en cartes ; quantité = curseur ou stepper ; lieu, objet, voix = liste avec recherche. Un seul style de contrôle par type de donnée dans tout l'atelier.
8. **Erreur = phrase + bouton.** Chaque message d'erreur dit quoi faire en une phrase et propose le bouton qui le fait (« Corriger », « Tirer une autre bande », « Importer comme nouvelle voix »). Le message technique du jeu reste en détails.

---

## 11. DÉCISIONS À PRENDRE (format, gameplay, périmètre)

| ID | Sujet (constats) | Pourquoi c'est une décision | Options |
|---|---|---|---|
| D01 | Onglet Journal (S01, S02, X20 à X22) | Outil de développement ou fonction pour l'ado ? | a) masquer pour l'ado ; b) garder en mode mainteneur ; c) liste « Ce que les voix ont dit » |
| D02 | Coordonnées saisies à la main (W10, M13) | Source de la position : relevé en jeu seulement, ou saisie libre | a) relevés seulement ; b) relevés + saisie avancée ; c) saisie libre comme aujourd'hui |
| D03 | Crans de fréquence d'appel (W11) | Change la fréquence des appels en jeu | a) jamais / rarement / parfois / souvent avec des valeurs proposées ; b) autres valeurs ; c) garder le nombre |
| D04 | Crans de lieu tranquille (T10) | Change le délai avant un passage du marchand | a) tout de suite / 2 h / 6 h ; b) 0 / 12 h / 24 h ; c) autre |
| D05 | Personnalité : anglais obligatoire (P01, M06) | L'IA lit l'anglais ; l'ado écrit en français | a) français accepté, traduit par l'IA avant enregistrement ; b) anglais obligatoire, IA d'aide seule ; c) les deux |
| D06 | Catégories perso et identifiants internes (R04, X08, X09) | Fonction avancée : la garder pour l'ado ? | a) cachée pour l'ado ; b) gardée avec nom auto ; c) retirée de l'atelier |
| D07 | Mot « lot » (T03, T05) | Le mot est dans le modèle (`group=`) ; renommer à l'écran sans toucher au format | a) « paquet » à l'écran ; b) « lot » gardé ; c) autre |
| D08 | État de l'histoire (M07) | Vocabulaire des états (`sets_state=`), jamais décrit à l'ado | a) liste fermée de mots ; b) champ caché ; c) texte libre gardé |
| D09 | Marge du marchand (T11) | Réglage secret du jeu : l'ado peut-il le changer ? | a) caché, valeur du jeu ; b) réglable en avancé ; c) réglable sur l'écran principal |
| D10 | Actions par défaut (P04) | « Parler » seul coché ou plus de choix pré-cochés | a) Parler seul ; b) Parler + Donner des missions ; c) choix par type de voix |
| D11 | Connexion réseau (X23) | Qui ouvre l'atelier depuis un autre appareil ? | a) l'adulte seul ; b) les amis ; c) personne (mode local) |
| D12 | Radio nécessaire et fréquences fixes (W05, W06, W04) | Déjà confié à un autre agent : ne pas redessiner ici ; dépendance d'affichage seulement | dépendance, pas de décision à prendre ici |
| D13 | Alignement des « ? » et des cartes avec le sélecteur de radio (W14, W05) | Suite de D12 | dépendance |

Notes : D01 à D11 sont les vraies décisions ; D12 et D13 sont des dépendances. Les constats marqués « décision » renvoient à ces identifiants.

---

## 12. Limites de l'audit

- Parcours réalisé en fr-FR, 1280 px et 800 px, avec une copie temporaire des voix du mod et un faux fournisseur d'IA (même montage que `tools/atelier_doc_shots.py`). Aucun fichier du dépôt modifié, aucune exécution du jeu.
- Écran de connexion réseau non capturé (mode réseau non activé) : constat X23 lu dans `login.html` et `i18n/fr.json`.
- Navigateur d'objets et sélecteur de radio lus dans le code et vus en capture (30, 31) ; le sélecteur de radio est en cours de remplacement (dépendance W05).
- Non vérifié : tactile et mobile réel ; lecteurs d'écran ; traduction anglaise (en.json) non relue ligne à ligne.
- Les pourcentages de la section 0 sont calculés sur les tableaux ; quelques lignes sont des doublons de fond regroupés (T15 et W14, X09 et M01) : gardées séparées car elles touchent des écrans différents.
