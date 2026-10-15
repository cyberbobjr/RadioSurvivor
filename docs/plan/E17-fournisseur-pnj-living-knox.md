# E17 — Fournisseur de PNJ et passage à Living Knox

**Objectif.** Rendre le carnet indépendant du moteur de PNJ : aujourd'hui il vise Bandits! (`RS_Bandits.lua` : sélection Ctrl+G, signature, fiches, mort, audition). Le 2026-10-03, l'utilisateur a décidé que les PNJ viendront d'un moteur propre, **Living Knox**, et qu'un seul moteur de PNJ tourne par serveur. Depuis la fusion du 2026-10-08, Living Knox fait partie de ce mod (étapes `LK00` à `LK13`).

**Dépend de.** `LK12-T01` à `LK12-T03` (API publique) pour le fournisseur Living Knox ; rien pour l'interface du fournisseur.

**Sources.** [`docs/architecture-ia-multijoueur.md`](../architecture-ia-multijoueur.md) ; [`LK12`](LK12-api-radiosurvivor.md) ; `docs/carnet-implementation-04221.md` (adaptateur Bandits! actuel).

## Décisions

- 2026-10-03 — Base des PNJ : moteur propre Living Knox (jalon de décision `LK02-T09`). Repli possible sur Project A-Life ou Bandits! si le jalon échoue.
- 2026-10-08 — Fusion : Living Knox est intégré à `batman_RadioSurvivor`. Le fournisseur Living Knox (`E17-T03`) appelle donc une API interne au mod ; `LK12-T04` est abandonnée comme doublon. `E17-T04` choisit entre le moteur interne et Bandits! (et non plus entre deux mods de PNJ).
- 2026-10-08 — **E17-T01 : abandonner Bandits! tout de suite** (choix de l'utilisateur, contre l'option « provisoire » recommandée). L'adaptateur `RS_Bandits.lua` et `loadModAfter=\Bandits2` sont retirés par `E17-T02` ; tant que Living Knox n'a pas de PNJ, le carnet n'a aucun interlocuteur et seule la radio de Walt reste jouable. Conséquences : E03 réorientée (validation du carnet rejouée avec Living Knox en `E17-T03`), `E00-T06`, `E09-T02`, `E10-T01` et `E17-T04` abandonnées, E08 à E10 à réécrire sur l'API Living Knox, `LK01-T04` débloquée.
- 2026-10-11 — **E17-T08** : (1) un PNJ inconnu ne propose **aucune mission au premier contact** : une offre seulement après avoir fait connaissance (deuxième rencontre au moins une heure de jeu plus tard, ou plusieurs échanges) et seulement si le joueur demande s'il a besoin d'aide ou du travail ; (2) au premier contact, ce qu'il dit de lui-même dépend **de son caractère** (ouvert : se présente volontiers ; méfiant : reste vague), mais son groupe et le lieu de son foyer restent **toujours cachés** au premier contact.
- 2026-10-11 — **E17-T09** : une mission proposée par un PNJ s'accepte **des deux façons** : en répondant oui au PNJ dans la conversation (acceptation d'office, comme une mission de voix radio) ou par le bouton « Accepter » du carnet ; à chaque offre, message à l'écran « Nouvelle offre dans le carnet ».
- 2026-10-11 — **E17-T10** : **aucune heuristique par mots** pour comprendre le joueur (oui/non, demande d'aide, langue) : le mod vise plus de 10 langues ; le LLM juge l'intention et la langue de réponse, le serveur ne vérifie que des faits (offre ouverte, PNJ, personnage, révision, stade de connaissance).
- 2026-10-14 — **E17-T13** : un nouveau texte attend la fin de la bulle en cours du même corps (un cri urgent peut attendre) ; une réplique de plus de 200 octets perd sa fin (arrêt sur une phrase entière) ; limite de 150 caractères pensée pour l'alphabet latin, « 。 » non reconnu ; temps de lecture qui s'écoule pendant la pause (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **E17-T01** — Sort de l'intégration Bandits! dans RadioSurvivor
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier ; `E00`, `E03` (validation du carnet sur Bandits!)
  - Faire : poser la question, consigner, ajuster E00 et E03.
  - Questions : Que faire du carnet bâti sur Bandits! ? Options : le garder comme fournisseur provisoire jusqu'à ce que Living Knox soit prêt, sans nouvelle validation en jeu sur Bandits! [recommandé] / l'abandonner tout de suite et attendre Living Knox / le maintenir durablement à côté de Living Knox (deux fournisseurs).
  - Accepté si : décision consignée ; E03 réorientée ou maintenue en conséquence.
  - Tests : —
  - Preuve : décision du 2026-10-08 (section Décisions) ; E00, E03, E08 à E10, E17 et LK01 ajustées
  - Reste : —

- [x] **E17-T02** — Interface « fournisseur de PNJ »
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E17-T01
  - Fichiers : `media/lua/shared/RadioSurvivor/RS_NPCProvider.lua` ; `RS_Bandits.lua` supprimé ; `mod.info` (`loadModAfter`, description) ; `RS_Carnet_Server.lua`, `RS_Client.lua` ; `tests/test_carnet.py` ; README
  - Faire : définir les opérations dont le carnet a besoin (disponibilité, identité stable d'un PNJ, corps à portée, nom, personnalité de base, hostilité, vivant ou mort, audition, bulle de parole, événement de mort) ; le carnet n'appelle plus que cette interface. Fournisseur par défaut **vide** (aucun PNJ) tant que Living Knox n'est pas prêt ; supprimer l'adaptateur Bandits! et la dépendance déclarée ; carnet utilisable sans PNJ (onglets vides expliqués, radio de Walt intacte).
  - Accepté si : aucune référence à Bandits! dans le code du mod ; scénarios de `test_carnet.py` rejoués avec un faux fournisseur conforme à l'interface (mêmes assertions métier) ; `test_protocol.py` inchangé et au vert ; démarrage sans Bandits! sans erreur.
  - Tests : `test_carnet.py`, `test_protocol.py`.
  - Preuve : `test_carnet.py` 19/19 (faux fournisseur conforme, mêmes assertions métier, + sans fournisseur, + second fournisseur refusé), `test_protocol.py` 3/3 inchangé, `test_rst.py` 151, `test_rs_suites.py` 20, `test_kahlua.py` 6, luacheck 21 (référence abaissée de 23), `plan.py check` ; aucune occurrence de « bandit » dans `Contents` ; serveur dédié de test le 2026-10-08 sans Bandits2 : `NPC provider=none, available=false`, 41 tests dont 38 PASS, 2 échecs connus (`E00-T08`, `E00-T10`) ; E01-T09 : commit `ea06853` ; **en jeu solo le 2026-10-08** (retour de l'utilisateur) : carnet ouvert avec « Aucun moteur de PNJ actif », onglets vides, Ctrl+G sans PNJ sans erreur, radio de Walt fonctionnelle (pont non lancé : réponse de secours)
  - Reste : client MP sans Bandits!

- [x] **E17-T03** — Fournisseur Living Knox
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E17-T02, LK12-T03
  - Fichiers : `media/lua/shared/RadioSurvivor/RS_LivingKnox.lua`
  - Faire : implémenter l'interface sur l'API de Living Knox ; missions M01 alimentées par les besoins réels des groupes (offres admissibles de Living Knox) ; livraison qui remonte les réserves du groupe ; histoire du groupe dans le contexte du LLM.
  - Accepté si : parcours du carnet 0.2 rejoué avec un PNJ de Living Knox, en solo puis à deux clients.
  - Tests : banc avec une fausse API Living Knox conforme ; suites en jeu.
  - Preuve : `RS_LivingKnox.lua` : fournisseur complet de l'interface `RS_NPCProvider` sur Living Knox (identifiant `lk-<n>` stable, signature, objets côté serveur `Bodies.bound` et côté client MP `ZombieGuard.cache`, groupe `grp-<n>`, hostilité du type, traits, nom du chef de l'histoire ou nom tiré, mort par `Bodies.onDied`), inscrit seulement si `LivingKnox.Enabled`, un seul moteur de PNJ (autre fournisseur détecté = avertissement) ; mission `first_aid_v1` d'un PNJ Living Knox = offre `API.missionOffers` de la réserve la plus basse, comptée en points V (`TooMany`, `SupplyClosed` refusés avant effet), livraison `API.deliver` avec le jeton du carnet comme reçu (jamais deux fois), réputation, fait `delivery`, lot = objet de récompense, offre close = `cancelled_closed` sans malus ; `context.group` au LLM (nom, type, résumé public `Stories.publicView`, chef, rôle, besoins, moral, attitude) sans secret, foyer ni journal ; `test_carnet.py` 54/54 (`LivingKnoxCarnetTests` : parcours 0.2 rejoué avec le vrai moteur), `test_observations.py` 14/14, `scenario_supply_offer`, VM Kahlua 29/29 ; suites en jeu `rs.carnet.lk`, `rs.carnet.lk.supply` ; `tests/run_all.py` 41/41 le 2026-10-10, luacheck 17/0 et 0 ; `docs/carnet-implementation-04221.md`, `protocole-carnet-v2.md`, `tests-en-jeu.md` §14 ; LK04-T02 : commit `afe41fb` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : PNJ Living Knox sélectionné (Ctrl+G), fiche enrichie en français (nom, chef, foyer, rôle) ; **parler au PNJ impossible en solo** (le carnet passe par le chat, absent en solo) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.carnet.lk 4/4, rs.carnet.lk.supply 1/1, rs.npctalk 4/4 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; étapes carnet.contact du client 2 : contacts affichés avec le nom du groupe (« RST leave », « Barbra Watson ») (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : rs.npctalk 4/4 (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`)
  - Reste : Limites : ligne « Dire » des Contacts pour parler en solo (E17-T06) ; preuve obtenue avec le faux modèle du pont

- [ ] **E17-T04** — Choix du fournisseur au démarrage
  - État : `abandonné`
  - Cible : `solo`
  - Dépend de : E17-T03
  - Fichiers : `RS_NPCProvider.lua`
  - Faire : détection des mods actifs (`getActivatedMods`, identifiants avec et sans `\`), fournisseur choisi, message clair si aucun ou plusieurs moteurs de PNJ sont actifs.
  - Accepté si : comportement correct pour chaque combinaison de mods.
  - Tests : banc.
  - Preuve : —
  - Reste : Bandits! abandonné le 2026-10-08 (`E17-T01`) : un seul moteur de PNJ (Living Knox), plus de choix au démarrage ; la cohabitation avec les autres mods de PNJ relève de `LK01-T04`.

- [x] **E17-T05** — Dernières mentions de Bandits! dans le pont et le protocole
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E17-T02
  - Fichiers : `bridge/npc_protocol.py` (prompt « You are the real Bandits survivor », ligne 166) ; `docs/protocole-carnet-v2.md` (« état Bandits », ligne 6) ; `tests/test_protocol.py` si le prompt y est vérifié
  - Faire : formulation neutre (« survivant », fournisseur de PNJ) dans le prompt et le contrat, sans changer les champs échangés.
  - Accepté si : aucune mention de Bandits! dans `bridge/` ni dans le contrat ; `test_protocol.py` au vert.
  - Tests : `test_protocol.py`.
  - Preuve : prompt du pont (`bridge/npc_protocol.py:166`) et contrat (`docs/protocole-carnet-v2.md:6`) neutres, champs inchangés ; aucune occurrence de « bandit » dans `bridge/` ni dans le contrat ; `tests/run_all.py` 10/10 le 2026-10-09 ; E00-T10 : commit `6bd8d82`
  - Reste : —

- [x] **E17-T06** — Parler à un PNJ en solo depuis le carnet
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E17-T03
  - Fichiers : `RS_Notebook.lua` (onglet Contacts), `RS_Carnet_Server.lua`, traductions
  - Faire : constaté en jeu le 2026-10-11 : parler à un PNJ passe par le chat, absent en solo ; ajouter une ligne « Dire » dans l’onglet Contacts (même chemin et mêmes contrôles que la ligne « Dire » de l’onglet Radio) qui marche en solo et en MP ; afficher le nom du groupe au lieu de `grp-<n>` ; retour à la ligne dans la zone de note privée.
  - Accepté si : en solo, une phrase tapée dans Contacts atteint le PNJ sélectionné qui répond ; nom du groupe lisible ; note sur plusieurs lignes
  - Tests : banc ; essai solo
  - Preuve : ligne « Dire » dans l'onglet Contacts du carnet : réutilise la commande `talk` du chat (mêmes contrôles serveur, même requête `npc_talk`, chemin unique `RS_CarnetClient.talk`), phrase prononcée après acceptation (`processSayMessage` en MP, `player:Say` en solo), ligne grisée avec sa raison (pas de cible, hors de portée, mort, réponse attendue, délai) ; réponse du PNJ affichée en solo en bulle et dans l'historique ; nom du groupe Living Knox à la place de `grp-<n>` ; note privée sur 4 lignes, sauts de ligne conservés ; `test_carnet.py` 57/57 (`ContactsTalkTests` solo avec le pont hors ligne et MP sans double requête), `test_rs_suites.py` OK ; `tests/run_all.py` 44/44 le 2026-10-11, luacheck 17/0 et 0 ; `docs/carnet-implementation-04221.md` ; base `ui-windows.md` ; code principal dans `19904bb` (commit de l'utilisateur) ; **en jeu solo le 2026-10-11** (partie `2026-10-11_17-54-58`) : conversation avec un PNJ Living Knox depuis Contacts, réponse reçue, mission proposée, validé par l'utilisateur
  - Reste : en jeu solo : Ctrl+G sur un PNJ, phrase tapée dans Contacts, réponse en bulle, refus hors de portée, note sur deux lignes ; MP à la séance finale

- [x] **E17-T07** — Réponse d'un PNJ refusée en silence (« Bridge missing, invalid or expired reply »)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E17-T06
  - Fichiers : `RS_Carnet_Server.lua` (`reply`, `poll`), pont (réponse `npc_reply`)
  - Faire : constaté en jeu le 2026-10-11 (partie `rstest-1011`, 17:2x) : « comment ça va » dit à un PNJ Living Knox (Daryl Velez) → « Bridge missing, invalid or expired reply. No decision applied. » alors que le pont tourne ; la phrase est absente de l'historique du PNJ ; `reply` refuse sans aucun journal (champs, révision, texte avec caractère de contrôle, `<>[]*`, longueur, intention, offre) ; même historique : réponse en anglais à « bonjour » alors que la présentation est en français. Trouver la cause, journaliser chaque refus (anglais), rendre la réponse du pont conforme (nettoyage côté pont plutôt que refus côté jeu quand c'est sûr), langue de la réponse = langue de la phrase du joueur.
  - Accepté si : une réponse LLM avec astérisques, saut de ligne ou crochets est affichée nettoyée au lieu d'être refusée ; tout refus restant est journalisé avec sa raison ; réponse dans la langue du joueur
  - Tests : banc ; essai solo
  - Preuve : hypothèse « astérisques ou saut de ligne refusés par le jeu » écartée (déjà nettoyés par le pont, rejoué au banc) ; cause probable côté pont : sortie du modèle lue strictement (`json.loads` + `bounded_reply`, sans mode JSON) → `invalid_or_unavailable` → `NoAnswer` sans journal ; indices : 2 appels courts à 15:22 UTC dans `token_usage.jsonl`, demandes classées refusées ; langue : réponse en langue de l'interface (`options.ini` `language=EN`) ; corrigé : `npc_protocol.py` (`clean_speech` sans didascalies ni balises, une ligne, coupe à 1600 octets sur une phrase ; `parse_llm_reply` tolérant ; `model_reply` qui garde la réplique sans effet si intention/offre hors contrat ; `speech_language` : langue de la phrase du joueur), appel en mode JSON (`NpcConversations.propose`) ; `RS_Carnet_Server.lua` : chaque refus journalisé `[RS_Carnet] <kind> <id> refused: <raison>` ; `test_protocol.py` `scenario_npc_reply_cleaning` (« comment ça va » jeu en anglais → réponse en français, refus journalisé une fois) ; `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 ; `docs/protocole-carnet-v2.md` ; **en jeu solo le 2026-10-11** (partie `2026-10-11_17-54-58`) : dialogue PNJ sans refus, validé par l'utilisateur
  - Reste : en jeu solo, pont en --debug : « comment ça va » à un PNJ → réponse en français sur une ligne ; « how are you » → anglais ; en cas de NoAnswer, raison dans console.txt ; cause exacte du 11 octobre non prouvée (journal du pont perdu) ; détection de langue FR/EN par mots indices

- [x] **E17-T08** — Faire connaissance avant de se dévoiler et de proposer une mission
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E17-T07
  - Fichiers : `RS_Carnet_Server.lua` (offres, contexte `npc_talk`), `bridge/npc_protocol.py` (prompt)
  - Faire : constaté en jeu le 2026-10-11 : à un premier « salut », un PNJ Living Knox se présente en entier (nom, groupe, foyer) et propose une mission ; appliquer la décision du 2026-10-11 : stade de connaissance par PNJ et par personnage (inconnu, connu) tenu par le serveur ; aucune offre au stade inconnu ni sans demande explicite du joueur ; au premier contact, présentation selon le caractère du PNJ, groupe et foyer jamais dits.
  - Accepté si : premier « salut » → réponse sans groupe, foyer ni offre ; après avoir fait connaissance et demande d'aide → offre possible
  - Tests : banc ; essai solo
  - Preuve : stade de connaissance serveur par PNJ et personnage (`stranger` → `acquainted` : reparler ≥ 1 h de jeu après le premier échange, 4 échanges, ou mission de ce PNJ ; persisté) ; offres : aucune au stade inconnu, au stade connu seulement si la phrase demande de l'aide ou du travail (`HELP_WORDS` FR/EN, `Server.asksForWork`) ; contexte au stade inconnu sans nom du groupe, chef, histoire ni besoins ; prompt `acquaintance_prompt` : groupe, chef, membres et foyer interdits, offre interdite, présentation selon le caractère (`sociability` et style : ouvert, réservé, méfiant) ; cause de la fuite : la présentation d'enrichissement entrait dans la mémoire comme réplique dite (`talk_history`, `acknowledge`) ; `test_carnet.py` 73 (`AcquaintanceTests` 6, test LK groupe et foyer jamais appris), `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 ; `docs/protocole-carnet-v2.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.npctalk 3/3 avec le pont après le correctif `2be96e5` : inconnu sans groupe ni offre ; connu : offre de reconnaissance faite par le modèle (`20261013-211501-solo.txt`)
  - Reste : en jeu solo : premier « salut » à un PNJ inconnu → ni groupe, ni foyer, ni offre ; « besoin d’aide ? » encore inconnu → rien ; après 1 h de jeu ou 4 échanges + demande d’aide → offre possible ; consigne du prompt à vérifier avec le vrai LLM ; détection de la demande par mots-clés

- [x] **E17-T09** — Accepter une mission en répondant oui au PNJ, offre signalée à l'écran
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E17-T08
  - Fichiers : `RS_Carnet_Server.lua`, `bridge/npc_protocol.py`, `RS_Client.lua`, traductions
  - Faire : constaté en jeu le 2026-10-11 : le PNJ dit « reviens me le dire d'ici deux heures » mais la mission reste une offre tant que le joueur n'a pas cliqué « Accepter » (aucune zone sur la carte) ; décision du 2026-10-11 : acceptation par un oui dans la conversation (le pont rend une intention d'acceptation vérifiée par le serveur : offre ouverte, même PNJ, même joueur) ou par le bouton ; message « Nouvelle offre dans le carnet » à chaque offre.
  - Accepté si : « d'accord, je m'en occupe » après une offre → mission acceptée, zone sur la carte ; bouton toujours possible ; message d'offre affiché
  - Tests : banc ; essai solo
  - Preuve : acceptation par la parole : à la phrase du joueur, offre ouverte de ce PNJ pour ce personnage ajoutée au contexte (`context.acceptable`, `saidYes` par `Server.saysYes` : `YES_WORDS` sans `NO_WORDS` ni question) ; à la réponse (`spokenAcceptance`), intention `accept` du modèle ou « oui » clair → revérification serveur (même mission, offre ouverte de ce PNJ, ce personnage, même révision) puis `M.accept` comme le bouton, une seule fois ; message `IGUI_RS_NewOffer` (`HaloTextHelper.addGoodText`) une fois par offre ; zone sur la carte à l'acceptation (vérifiée) ; pont : intention `accept` admise seulement avec `acceptable`, `acceptance_prompt` ; `test_carnet.py` 79 (`SpokenAcceptanceTests` 4 + 2), `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 ; `docs/protocole-carnet-v2.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.npctalk 3/3 : « D'accord, je m'en occupe » rend la mission active, « Peut-être plus tard » garde l'offre et le bouton Accepter (`20261013-211501-solo.txt`)
  - Reste : en jeu solo : PNJ connu, « besoin d’aide ? » → offre + message « Nouvelle offre dans le carnet » ; « D’accord, je m’en occupe » → mission active, zone sur la carte ; « Peut-être plus tard ? » → reste une offre, bouton Accepter valide ; mots sans accents, FR/EN seulement ; acceptation implicite dépend du LLM

- [x] **E17-T10** — Retirer les heuristiques par mots (acceptation, demande d'aide, langue)
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E17-T09
  - Fichiers : `RS_Carnet_Server.lua`, `RS_Config.lua`, `bridge/npc_protocol.py`
  - Faire : décision du 2026-10-11 : retirer `YES_WORDS`/`NO_WORDS`/`saysYes` (E17-T09), `HELP_WORDS`/`asksForWork` (E17-T08) et `speech_language` (E17-T07) ; acceptation par la seule intention `accept` du LLM vérifiée par le serveur ; au stade connu, le catalogue d'offres est envoyé et le LLM ne propose que si le joueur demande de l'aide ou du travail ; langue de réponse = celle du joueur, jugée par le LLM.
  - Accepté si : plus aucune liste de mots ni détection de langue par mots dans le code ; comportements E17-T08/T09 conservés par le LLM et les contrôles serveur
  - Tests : banc
  - Preuve : retirés : `HELP_WORDS`, `YES_WORDS`, `NO_WORDS` (`RS_Config.lua`), `asksForWork`, `saysYes`, `context.askedForWork`, `context.saidYes` (`RS_Carnet_Server.lua`), `speech_language`, `FRENCH_HINT`, `ENGLISH_HINT` (`npc_protocol.py`) ; acceptation par la seule intention `accept` du LLM revérifiée par le serveur (offre ouverte, PNJ, personnage, révision, `M.accept` une fois) ; au stade connu, catalogue envoyé à chaque phrase et offre décidée par le LLM ; langue de réponse = langue de la phrase, jugée par le LLM (langue du jeu en simple indice) ; mode `--offline` sans lecture de la phrase ; aucune autre heuristique lexicale sur la parole du joueur trouvée ; `test_carnet.py` 77, `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 ; `docs/protocole-carnet-v2.md`
  - Reste : en jeu solo avec le vrai LLM : offre seulement sur demande d’aide (toute langue), acceptation sur un oui (toute langue), réponse dans la langue de la phrase ; indice de langue du jeu ramené à FR ou EN (args.language)

- [x] **E17-T11** — Vraie langue du jeu transmise au PNJ
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E17-T10
  - Fichiers : `RS_Carnet_Server.lua` (`talk`), `bridge/npc_protocol.py`
  - Faire : demande de l'utilisateur le 2026-10-11 : `talk` ramène la langue du jeu à FR ou EN (`args.language == 'FR' and 'FR' or 'EN'`) ; transmettre le code réel (validé par sa forme, pas par une liste de langues connues) pour l'indice de langue et le mode `--offline`.
  - Accepté si : jeu en espagnol → indice `ES` envoyé au pont ; code invalide → repli propre
  - Tests : banc
  - Preuve : code réel de la langue du jeu (nom du dossier `Translate`, `Language.name()`, `Languages.loadTranslateDirectory`) envoyé par le client (`RS_Client.lua` `language()`, qui réduisait aussi à FR/EN) et revérifié par le serveur (`talk`) avec `C.languageCode` : contrôle de forme seulement (majuscules, 2 à 8 lettres ou `_`, lettre en tête), sinon `EN` ; pont : validation par forme, noms des 29 langues vanilla, code inconnu passé tel quel ; voix radio déjà en vraie langue (`authorityLanguage`) ; `test_carnet.py` 79 (2 nouveaux), `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 ; `docs/protocole-carnet-v2.md`
  - Reste : en jeu : jeu en espagnol → indice ES au pont ; mode --offline : texte FR ou EN seulement ; radio_bridge.py call_situation retire le _ (ES_CL → ESCL) et sa table ne connaît que 9 langues (non corrigé, fichier avec modifications non commitées de l’utilisateur)

- [x] **E17-T12** — Réplique d'un PNJ découpée en bulles au milieu d'une phrase
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E17-T06, LK11-T04
  - Fichiers : à établir (découpage des répliques venues du pont avant l'affichage en bulles : `LK_Speech`, `LK_SpeechView`, fournisseur `RS_NPCProvider`, pont)
  - Faire : constat de l'utilisateur en jeu (2026-10-13) : « quand le texte provient du pont, et dit par le PNJ, les phrases sont coupées en plein milieu et je dois attendre le prochain texte pour avoir la phrase au complet, il vaudrait mieux couper les phrases au niveau d'un point ou d'une virgule ». Trouver où une réplique longue est coupée en morceaux successifs et couper à la fin d'une phrase (point, point d'exclamation ou d'interrogation, points de suspension), sinon à une virgule ou un point-virgule, sinon entre deux mots ; un morceau ne coupe jamais un mot.
  - Accepté si : au banc, une réplique longue est découpée à des fins de phrase, puis à des virgules ; en jeu, chaque bulle d'une réplique du pont se lit seule.
  - Tests : banc ; suite en jeu `rs.npctalk` (mesure des morceaux).
  - Preuve : banc `tests/test_text_cut.py` du 2026-10-13 (22 tests OK, les deux tests clés en échec sur l'ancien code) : une réplique de proximité n'est jamais découpée (une seule commande `speech`, une seule bulle) ; les morceaux successifs viennent de la radio : `RS_GroupRadio.lines` coupait au dernier espace avant 140 caractères et le pont (`radio_lines`) toute phrase de plus de 100 caractères entre deux mots ; nouveau module `RS_TextCut.pieces` (fin de phrase `.` `!` `?` `…` suivie d'un espace, « 9.5 » exclu, puis `,` `;` `:`, puis entre mots, jamais au milieu d'un caractère) et miroir Python `cut_pieces` dans le pont ; même découpe en Kahlua réelle (`test_kahlua.py` 38 OK) ; run_all 121/121 ; luacheck 16/0 ; suite `rs.groupradio` (nouveau test de découpe, mesure des lignes diffusées) ; conception `radio-groupes.md`, `parole.md` ; base `kahlua-lua.md` (`%s`, `%c`, `%p` ASCII seulement en Kahlua) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : rs.npctalk « a long answer is shown in bubble pieces of whole sentences » PASS (étape lk.speech.pieces) et rs.groupradio « a long reply is aired in lines cut at sentence ends, then commas, never inside a word (E17-T12) » PASS (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`) ; MP : mêmes tests PASS (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : Limites : « M. Dupont » compte comme une fin de phrase ; ligne courte possible ; règle appliquée avant la limite de 7 lignes radio (8 au pont)

- [x] **E17-T13** — Bulle de PNJ coupée au milieu d'une phrase
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E17-T12, LK11-T04
  - Fichiers : à établir (`LK_Speech.lua` : texte rédigé refusé au-delà de `MAX_TEXT` 200 octets, `RS_Carnet_Server.lua` `MEMBER_REPLY_BYTES`, conversations entre PNJ E08-T03/T04/T05, `LK_SpeechView.lua`, pont)
  - Faire : l'utilisateur précise (2026-10-14) que les répliques coupées en plein milieu concernent « les deux : radio et bulle ». E17-T12 a corrigé la radio ; une bulle de proximité n'est pas découpée en morceaux mais une réplique longue venue du pont est coupée quelque part (limite d'octets, découpe du pont, ligne de conversation). Trouver le chemin exact et couper à une fin de phrase (`RS_TextCut`), ou afficher les morceaux successifs coupés à une fin de phrase, jamais au milieu d'un mot.
  - Accepté si : au banc et en jeu, une réplique longue d'un PNJ en bulle (dialogue avec le joueur, conversation entre PNJ, réaction d'un membre) se lit en phrases entières.
  - Tests : banc ; `rs.npctalk`, `rs.conversations`.
  - Preuve : bancs du 2026-10-14 : `tests/test_lk_speech_pieces.py` (13 tests, 10 en échec sur l'ancien code) et `test_conversations.py` (`test_long_line_joined_in_whole_sentences`, en échec sur l'ancien code) ; chemins prouvés : (1) pont `clean_speech` coupait au dernier mot avec « ... » une réplique de 200 octets au plus (conversation, initiative, réaction de membre) dès que sa dernière fin de phrase tombait dans le premier tiers, consigne « 200 bytes » ; (2) `LK_SpeechView.show` : réponse au joueur jusqu'à 1600 octets en une seule bulle de 15 s au plus, remplacée aussitôt par la réplique suivante du même corps ; (3) `RS_Conversations.cut` coupait à l'octet le contexte envoyé au modèle ; corrections : bulle découpée par `RS_TextCut.pieces` en morceaux de 180 caractères au plus affichés l'un après l'autre (file de 16 par corps), réplique suivante en attente au lieu de remplacer ; `clean_speech` garde la dernière fin de phrase qui tient puis virgule puis mot ; consigne « two short sentences, under 150 characters » (`spoken_limit`) ; `cut` par `RS_TextCut` ; run_all 125/125 ; luacheck 15/0 ; suite `rs.npctalk` (test de réponse longue en morceaux) ; conception `parole.md` ; essai en jeu du 2026-10-14 : client automatique avec le pont et le vrai modèle (E01-T14) : rs.npctalk « a long answer is shown in bubble pieces of whole sentences, one after another » PASS (`tools/autoclient/runs/20261014-111501-57d2c373af5b/20261014-091544-solo.txt`)
  - Reste : essai solo avec le pont : `RST.run({ suite = "rs.npctalk", tags = "world" })` (réponse longue en bulles de phrases entières, dans l'ordre, chacune après la durée de lecture de la précédente).

- [x] **E17-T14** — Réponse d'un PNJ non affichée en MP avant la découverte du canal « dire »
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E17-T13, E01-T16
  - Fichiers : `RS_Client.lua`
  - Faire : constaté le 2026-10-15 (`tools/autoclient/runs/20261015-012607-mp-c75ba6661b1c`, `rs.npctalk` E17-T13) : en MP la bulle de la réponse longue n'est jamais affichée chez le client ; cause probable `RS_Client.lua:80-82` : `inject` rend `false` tant que le canal « dire » (`Client.say`) n'a pas été découvert, la réponse reste dans la boîte de réception. Afficher la réponse sans dépendre de cette découverte.
  - Accepté si : `rs.npctalk` (test E17-T13) vert en MP comme en solo.
  - Tests : banc ; `rs.npctalk` en campagne MP.
  - Preuve : cause : `ChatType` est une énumération Java non exposée à Lua, `getType():getValue()` levait « attempted index: getValue of non-table: say » à chaque message (journal client `tools/autoclient/runs/20261015-012607-mp-c75ba6661b1c/client1/console.txt`) : en MP le canal « dire » n'était jamais reconnu ; canal reconnu par `tostring(chat:getType()) == 'say'` (`RS_Client`, `LK_SpeechView`), bulle affichée aussitôt, ligne de chat seule en attente du canal ; doublures fidèles (méthode qui lève comme le Java) ; `test_answer_bubble_before_say_chat_is_known` (échoue sur l'ancien code) ; base `ui-windows.md` corrigée ; commit `a397ea6` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.npctalk 4/4, dont le test E17-T13 (bulles) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; aucune ligne `getValue of non-table` dans les quatre consoles clientes de la campagne
  - Reste : —

- [x] **E17-T15** — Délais du serveur alignés sur le pont, erreur du fournisseur remontée
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E17-T08
  - Fichiers : `RS_Carnet_Server.lua`, `bridge/radio_bridge.py`, suites du carnet
  - Faire : relevé le 2026-10-15 (campagne MP `tools/autoclient/runs/20261015-024734-mp-348bee78d4b7`, fournisseur DeepSeek en panne : 25 appels sur 26 en échec, délais de 60 s et `http_503`) : le serveur abandonne une demande après 90 s alors que le pont fait des tentatives de 60 s avec 4 travailleurs ; une réponse ou une erreur tardive est perdue, et les suites disent « is the bridge program running? » quand c'est le fournisseur qui échoue. Aligner les délais (serveur > tentatives du pont) et transmettre l'erreur du fournisseur jusqu'au serveur (réponse d'erreur du pont), visible dans le journal et les messages des suites.
  - Accepté si : au banc, pont qui rend une erreur de fournisseur = refus journalisé avec la cause, sans attente de 90 s ; suites qui nomment la cause.
  - Tests : `test_protocol.py`, bancs du pont ; campagne MP.
  - Preuve : cause (pont de la campagne MP du 2026-10-15) : `timeout=60` d'`urlopen` ne borne qu'une lecture (tentatives de 120 à 420 s), âge de la demande vérifié seulement au dépôt, serveur qui abandonne à 90 s, toute erreur rendue `invalid_or_unavailable` ; correctif : `MAX_AGE_S` 75 vérifié aussi à la prise par un travailleur (`expired`), `LLM_BUDGET_S` 60 pour toutes les tentatives (corps lu avec échéance), codes `timeout`/`http_<statut>`/`unreachable`/`bad_response` transmis au jeu, serveur `REQUEST_TIMEOUT_MS` 150 000, refus journalisés avec la cause (`Server.refusals`), suites qui nomment la cause (`R.bridgeCause`) ; bancs `test_protocol` 37 OK (`scenario_provider_errors`), `test_carnet` 85/85 ; contrat `protocole-carnet-v2.md` ; commit `589263a` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : suites qui passent par le pont vertes (rs.npctalk 4/4, rs.initiatives 4/4, rs.conversations 4/4, rs.groupradio 5/5) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : Limite : attentes des suites encore à 60 et 90 s (un fournisseur lent peut les faire échouer) ; autres délais : E17-T16

- [x] **E17-T16** — Délais de la radio de Walt, des dernières pages et du bulletin alignés sur le pont
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E17-T15
  - Fichiers : `RadioSurvivor_Const.lua`, `RS_LastPages.lua`, `RS_Facts.lua`
  - Faire : relevé le 2026-10-15 (E17-T15) : le pont peut répondre jusqu'à 135 s après l'envoi (75 + 60) ; la radio de Walt attend 120 s côté client (`Const.CLIENT_TIMEOUT_MS`) et 90 s côté serveur (`Const.TIMEOUT_MS`), les dernières pages 90 s (`RS_LastPages.P.TIMEOUT_MS`), le bulletin 60 s (`Facts.BULLETIN_TIMEOUT_MS`) : une réponse lente est perdue. Aligner chaque délai sur le pont (ou borner le pont pour ces demandes) en gardant les secours sans pont.
  - Accepté si : au banc, une réponse à 130 s est appliquée pour chaque chemin ; les secours restent déclenchés après le délai.
  - Tests : `test_protocol.py`, bancs concernés.
  - Preuve : commit `888b1b0` (attentes alignées sur le battement du pont) ; bancs du 2026-10-15 : `tests/test_protocol.py` OK, `tests/test_bulletin.py` 14 OK, `tests/test_last_pages.py` 27 OK
  - Reste : —
