# Radio Survivor — améliorations de code et idées de fonctionnalités

- **Mod** : Radio Survivor (`name=batman_Radio Survivor`), `id=batman_RadioSurvivor`, `modversion=0.3.0` (build de test), variante `42.21` (`versionMin=42.21`).
- **Dépôt** : `cyberbobjr/RadioSurvivor` (public, MIT), branche unique `main` depuis le 2026-10-24 (`dev` fusionnée puis supprimée), dernier commit relu `dcd71ed` (2026-10-18, E07-T10).
- **Date** : 2026-10-21 ; **avancement mis à jour le 2026-10-23** (aucune version publiée sur le Workshop : `0.3.0` est un build de test et la publication, tâche E16-T05, reste à faire ; corrections sur `dev` jusqu'au commit `dc6a1b8`).
- **Périmètre** : relecture statique du code Lua (`Contents/mods/batman_RadioSurvivor/42.21/media/lua`, 146 fichiers, environ 70 700 lignes : radio et carnet `RS_*`, moteur de PNJ Living Knox `LK_*`), du pont Python (`bridge/`, environ 3 900 lignes), des outils (`tools/`), des tests (`tests/`, environ 140 étapes dans `run_all.py`, environ 3 180 fonctions de test) et du plan (`docs/annexes/plans/`, état lu par `tools/plan.py` en lecture seule). Base moteur : `.claude/pz-knowledge`. Aucun essai en jeu n'a été fait pour ce document.
- **Statuts** : « confirmé statiquement » = vu dans le code aux lignes citées ; « à vérifier en jeu » = déduit du code, effet réel ou coût à mesurer. Les lignes sont celles du commit `dcd71ed`.
- **Note** : `docs/` est en cours de réorganisation ; les chemins du plan sont donnés dans la nouvelle arborescence (`docs/annexes/plans/`).

Ce qui est déjà planifié n'est pas reproposé. Les tâches encore ouvertes au plan (E01-T16, E01-T19, E16-T02 à T05, LK13-T02 à T05, et les tâches `testé solo` ou `testé hors jeu` qui attendent leur validation MP) sont citées en référence quand un constat les touche.

**Points solides relevés** (rien à changer) : autorité serveur systématique avec contrôles détaillés des rapports clients (par exemple `LK_Combat.lua:1047-1107` : propriétaire, numéro de séquence, portée, ligne de tir, cadence) ; inscriptions d'événements idempotentes (`LK_Core.lua:46-56`) ; registres à deux emplacements avec somme de contrôle ; aucune heuristique de mots-clés sur le texte du joueur (recherche négative dans le Lua et le pont) ; messages de journal en anglais ; parité des traductions EN/FR (0 clé manquante sur 1 036) ; pas de traversée de chemin dans le pont (fichiers nommés par empreinte) ; listes fermées pour toutes les actions du LLM.

---

## Tableau de bord — ce qui est fait et ce qui reste

**Légende** : ✅ fait · 🟡 fait en partie · ⬜ pas commencé. « Publié » = présent dans une version du Workshop ; « non publié » = poussé sur `origin` mais pas encore publié. Le mod n'a encore **aucune version sur le Workshop** (E16-T05 à faire) ; les corrections ci-dessous sont sur `main` depuis la fusion du 2026-10-24 et décrites dans la section `Unreleased` du `CHANGELOG.md`. « Testé » : « hors jeu » = bancs Python/lupa cités dans le plan ; aucun point n'est encore vérifié en jeu. Détail de chaque point dans les parties 1 et 2, suivi fin dans `docs/annexes/plans/SUIVI.md` (tâches E11-T20 et E16-T06 à E16-T10).

**Bilan** : améliorations de code **11 faites, 3 en partie, 26 à faire** (sur 40) ; les 8 points de priorité haute sont faits, sauf C20 en partie. Idées de fonctionnalités **0 faite, 0 en partie, 25 à faire** (sur 25).

### Améliorations de code

| ID | Sujet | Priorité | État | Testé | Publié | Commit | Ce qui reste |
|---|---|---|---|---|---|---|---|
| C01 | Nom du personnage et de la radio dans le prompt système | haute | ✅ Corrigé | hors jeu | non publié | `4215bd3` | Vérifier en jeu (E16-T06) |
| C02 | Usurpation du tag `[Caller N]` | haute | ✅ Corrigé | hors jeu | non publié | `4215bd3` | Vérifier en jeu (E16-T06) |
| C03 | Repli sans `max_tokens` | haute | ✅ Corrigé | hors jeu | non publié | `4215bd3`, `69e550c` | Vérifier en jeu (E16-T06) |
| C04 | Échec d'écriture de `responses.txt`, exceptions des workers | moyenne | ⬜ À faire | — | — | — | Tout (avec le « Reste » de E16-T03) |
| C05 | Verrou global tenu pendant les réessais | moyenne | ⬜ À faire | — | — | — | Tout |
| C06 | Journal de PNJ corrompu | moyenne | ⬜ À faire | — | — | — | Tout |
| C07 | Écriture atomique sans réessai | basse | ⬜ À faire | — | — | — | Tout |
| C08 | Codes de langue déformés (`ES_CL`) | moyenne | ⬜ À faire | — | — | — | Tout |
| C09 | Demande sans `sent` qui n'expire jamais | basse | ⬜ À faire | — | — | — | Tout |
| C10 | Aucune borne de taille du prompt | moyenne | ✅ Corrigé | hors jeu | non publié | `4215bd3`, `69e550c` | Vérifier en jeu (E16-T06) |
| C11 | Journaux : texte des joueurs, erreurs, secrets en `--debug` | basse | ⬜ À faire | — | — | — | Tout |
| C12 | Corps d'erreur HTTP sans délai, pas de réessai 429/5xx | basse | ⬜ À faire | — | — | — | Tout |
| C13 | Pont : duplications et fichier monolithique | moyenne / basse | ⬜ À faire | — | — | — | Tout |
| C14 | Fichiers d'état du pont sans purge | basse | ⬜ À faire | — | — | — | Tout |
| C15 | Tests du pont manquants | moyenne | 🟡 En partie | hors jeu | non publié | `4215bd3` | Tous les cas sauf l'usurpation `[Caller N]` |
| C16 | Petits défauts du pont | basse | ⬜ À faire | — | — | — | Tout |
| C17 | Personnages morts jamais purgés | haute | ✅ Corrigé | hors jeu | non publié | `3760771`, `99dc0bc` | Vérifier sur un serveur dédié (E16-T08) |
| C18 | Encodeur plus permissif que le décodeur ; migration | haute | ✅ Corrigé | hors jeu | non publié | `3760771` | Alerte aux admins connectés ; serveur dédié (E16-T08) |
| C19 | Écriture ratée qui coupe le carnet | moyenne | ✅ Corrigé | hors jeu | non publié | `3760771` | Prévenir les admins connectés ; serveur dédié (E16-T08) |
| C20 | Sauvegarde synchrone complète et fréquente | haute | 🟡 En partie | hors jeu | non publié | `3760771` | Écriture regroupée en fin d'image (`markChanged`) ; mesurer en jeu |
| C21 | Commandes sans limite de débit | haute | ✅ Corrigé | hors jeu | non publié | `2d8cae5` | Snapshot en cache ; vérifier en MP (E16-T09) |
| C22 | Nettoyage de texte quadratique | haute | ✅ Corrigé | hors jeu | non publié | `2d8cae5` | Vérifier en MP (E16-T09) |
| C23 | Radio sans contrôles de chat | moyenne | ⬜ À faire | — | — | — | Tout |
| C24 | `select` crée une fiche avant la distance | moyenne | ⬜ À faire | — | — | — | Tout |
| C25 | Réponses du pont relues chaque seconde, deux fois | moyenne | ⬜ À faire | — | — | — | Tout |
| C26 | `getTextOrNull(clé)` sans arguments | basse | ⬜ À faire | — | — | — | Tout (avec C34) |
| C27 | Délais de mission en temps réel | moyenne | ✅ Corrigé | hors jeu | non publié | `24d6cab`, `a2a81b3` | Vérifier en jeu (E11-T20, E16-T10) |
| C28 | Chaque zombie compté republie les snapshots | moyenne | ⬜ À faire | — | — | — | Tout |
| C29 | Distance sautée si l'appelant s'est déconnecté | basse | ⬜ À faire | — | — | — | Tout |
| C30 | `Bodies.find` parcourt la liste des zombies | moyenne | ✅ Corrigé | hors jeu | non publié | `2d8cae5` | Mesurer le gain avec `LK_Load` (E16-T09) |
| C31 | Une trentaine d'abonnés réseau, sans limite | moyenne | 🟡 En partie | hors jeu | non publié | `2d8cae5` | Répartiteur unique ; vérifier en MP |
| C32 | Joueurs déconnectés gardés dans `Relay` | basse | ⬜ À faire | — | — | — | Tout |
| C33 | Table allouée à chaque image côté client | basse | ⬜ À faire | — | — | — | Tout |
| C34 | Rechargement des traductions copié 8 fois | moyenne | ⬜ À faire | — | — | — | Tout |
| C35 | Contrôle des droits d'administration copié | basse | ⬜ À faire | — | — | — | Tout |
| C36 | luacheck sans contrôle des globales | moyenne | ⬜ À faire | — | — | — | Tout |
| C37 | Pas d'intégration continue | moyenne | ⬜ À faire | — | — | — | Tout |
| C38 | Fonctions de plusieurs centaines de lignes | basse | ⬜ À faire | — | — | — | Au fil des tâches |
| C39 | Carnet sans manette, joueur 0 seulement | basse | ⬜ À faire | — | — | — | Tout (documentation d'abord) |
| C40 | Deux langues seulement | moyenne | ⬜ À faire | — | — | — | Tout (avant E16-T05) |

### Idées de fonctionnalités

| ID | Idée | Thème | Effort | État | Remarque |
|---|---|---|---|---|---|
| I01 | Radiogoniométrie | Radio | M | ⬜ Proposée | |
| I02 | Réception dégradée par la distance et l'orage | Radio | S | ⬜ Proposée | |
| I03 | Indicatifs sonores des voix | Radio | S | ⬜ Proposée | |
| I04 | Mots de passe et codes entre voix | Radio | M | ⬜ Proposée | |
| I05 | Rumeurs vérifiables | Radio | M | ⬜ Proposée | |
| I06 | Appel de détresse vers les groupes alliés | Radio | L | ⬜ Proposée | |
| I07 | Réponse radio dans la langue de l'appelant | Radio | S | ⬜ Proposée | Dépend de C08 |
| I08 | Recopier une page du carnet | Carnet | M | ⬜ Proposée | |
| I09 | Tableau d'annonces d'un foyer ami | Carnet | M | ⬜ Proposée | |
| I10 | Message écrit laissé à un groupe | Carnet | M | ⬜ Proposée | |
| I11 | Résumé hebdomadaire du personnage | Carnet | S | ⬜ Proposée | |
| I12 | Les rescapés rejoignent une colonie | Living Knox | M | ⬜ Proposée | |
| I13 | Escorte temporaire | Living Knox | L | ⬜ Proposée | |
| I14 | Commerce entre groupes hors écran | Living Knox | M | ⬜ Proposée | |
| I15 | Bois et chauffage en hiver | Living Knox | M | ⬜ Proposée | |
| I16 | Signe de reconnaissance d'une alliance | Living Knox | M | ⬜ Proposée | |
| I17 | Prisonniers et rançon | Living Knox | L | ⬜ Proposée | |
| I18 | Cimetière et mémoire du foyer | Living Knox | S à M | ⬜ Proposée | |
| I19 | Chien de garde des colons | Living Knox | M | ⬜ Proposée | Hypothèse à prototyper |
| I20 | Budget du LLM et page d'état du pont | Administration | M | ⬜ Proposée | Prérequis C03 et C10 faits ; C14 à faire |
| I21 | Modèle selon la demande et secours local | Administration | S à M | ⬜ Proposée | Dépend de C12 |
| I22 | Prompts compatibles avec le cache de préfixe | Administration | S | ⬜ Proposée | |
| I23 | Profils de réglages | Administration | S / M | ⬜ Proposée | |
| I24 | Rejeu d'une conversation | Administration | S | ⬜ Proposée | Dépend de C11 |
| I25 | Banc d'injection en `--offline` | Administration | S | ⬜ Proposée | Prérequis C01 et C02 faits (tests ciblés seulement) |

---

## Partie 1 — Améliorations de code

Priorité : **haute** (bug, sécurité ou perte de données possible), **moyenne**, **basse**. Effort : **S** (moins d'une demi-journée), **M** (un à deux jours), **L** (plus).

### Pont Python et LLM

#### C01 — Nom du personnage et nom de la radio injectés dans le prompt système
- **Problème** : `system_prompt` insère `name`, `radio`, `date` et `days` de la demande sans `safe_text` ni borne. Ces valeurs viennent du serveur (`getForename`/`getSurname`, `getDisplayName()` de la radio) avec seulement `Const.oneLine`.
- **Preuve** : `bridge/radio_bridge.py:586-594` ; `RadioSurvivor_Server.lua:461`, `:464`, `:314`.
- **Risque** : sécurité du pont et du LLM. Un nom de personnage comme « Bob. Ignore previous instructions… » arrive dans le rôle système, le plus écouté par le modèle. Cela permet aussi de faire paraphraser les secrets de la fiche, alors que `leaks_secret` ne détecte que les citations exactes.
- **Correction** : passer ces champs par `npc.safe_text` avec une borne de 48 à 64 octets, les présenter comme des données non fiables, ou les déplacer dans le message utilisateur. Ajouter un test d'injection.
- **Priorité** haute · **Effort** S · confirmé statiquement. Reste à vérifier en jeu : une radio d'inventaire renommée par le joueur porte-t-elle son nom personnalisé ?
- **Statut : corrigé (commit 4215bd3), à vérifier en jeu**
- **Avancement : ✅ corrigé, non publié (commit 4215bd3), testé hors jeu (`tests/test_bridge_guards.py`), à vérifier en jeu** — tâche E16-T06.

#### C02 — Usurpation du tag `[Caller N]` dans l'historique partagé d'une voix
- **Problème** : le message enregistré est `f"{tag} {text}"`. Un texte qui contient « [Caller 2] … » ou un faux rappel de format reste dans les 40 derniers messages relus pour tous les appelants de la voix. Le tag n'est retiré que de la sortie.
- **Preuve** : `bridge/radio_bridge.py:843`, `:871`, `:728`.
- **Risque** : sécurité et multijoueur. Un joueur peut se faire passer pour un autre dans la mémoire de la voix et orienter les réponses faites aux autres joueurs.
- **Correction** : neutraliser `[` et `]` (ou les seuls motifs `[Caller`) dans le texte joueur, ou encapsuler chaque tour entre délimiteurs déclarés non fiables. Ajouter un test.
- **Priorité** haute · **Effort** S · confirmé statiquement.
- **Statut : corrigé (commit 4215bd3), à vérifier en jeu**
- **Avancement : ✅ corrigé, non publié (commit 4215bd3), testé hors jeu (`tests/test_bridge_guards.py`), à vérifier en jeu** — tâche E16-T06.

#### C03 — Tentative de repli sans `max_tokens`
- **Problème** : le corps `minimal` n'a aucun plafond de jetons. Après une réponse vide due à un raisonnement trop long (`finish_reason=length`, cas réel du 2026-10-13), la tentative suivante part sans limite.
- **Preuve** : `bridge/radio_bridge.py:655-661`, `:700-701`.
- **Risque** : coût LLM non borné, précisément dans le cas le plus cher. Jusqu'à 3 appels par message.
- **Correction** : garder `max_tokens` (ou `max_completion_tokens`) dans le repli, ne pas relancer après `finish_reason=length`, poser un plafond de jetons par appel.
- **Priorité** haute · **Effort** S · confirmé statiquement.
- **Statut : corrigé (commit 4215bd3), à vérifier en jeu**
- **Avancement : ✅ corrigé, non publié (commits 4215bd3, 69e550c), testé hors jeu (`tests/test_bridge_guards.py`), à vérifier en jeu** — tâches E16-T06 et E16-T07 (plafond réglable).
- **Suite (2026-10-21, confirmée par l'utilisateur)** : plafond réglable dans la configuration du pont (`LLM_MAX_TOKENS`, `LLM_MAX_PROMPT_CHARS`, mêmes défauts, valeur invalide remplacée par le défaut) ; tâche `E16-T07`.

#### C04 — Un échec d'écriture de `responses.txt` arrête le pont ; exceptions des workers perdues
- **Problème** : `write_responses` lève `RuntimeError` après 50 essais, et `PermissionError` n'est pas rattrapée. La boucle `run` ne rattrape rien. Dans un worker, l'exception disparaît : le futur n'est jamais relu.
- **Preuve** : `bridge/radio_bridge.py:328-340`, `:1899-1918`, `:1923`, `:1933-1965`. Défaut voisin déjà noté dans E16-T03 (« Reste » : boucle `run()` sans pause si `requests.txt` reste illisible).
- **Risque** : bug. Le pont s'arrête si le jeu ou un antivirus garde le fichier ouvert plus de 5 s, et les voix se taisent sans message clair.
- **Correction** : `try/except (OSError, RuntimeError)` dans la boucle, avec pause et nouvel essai au tour suivant. `add_done_callback` qui journalise les exceptions des workers. À traiter avec le défaut de E16-T03.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C05 — Verrou global tenu pendant les pauses de réessai
- **Problème** : les `sleep` de réessai de l'écriture (jusqu'à 5 s) s'exécutent sous `self.lock`. Tous les workers attendent, ainsi que le battement de cœur `bridge-alive`.
- **Preuve** : `bridge/radio_bridge.py:333-339`, `:1837`, `:1887`.
- **Risque** : faux « pont absent » côté jeu, latence de toutes les voix.
- **Correction** : construire le corps sous verrou, écrire hors verrou avec un numéro de version pour garder l'ordre.
- **Priorité** moyenne · **Effort** M · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C06 — Journal de PNJ corrompu : le PNJ ne répond plus jamais
- **Problème** : `load` ne rattrape que `FileNotFoundError`. Un JSON invalide (coupure de courant, édition à la main) fait échouer chaque tour et rejeter chaque acquittement. Côté radio, `Conversations._load` repart de zéro sans rien dire et ne rattrape ni `UnicodeDecodeError` ni `OSError`, ce qui renumérote les appelants.
- **Preuve** : `bridge/radio_bridge.py:500-507`, `:1883`, `:367-377`.
- **Risque** : persistance et robustesse.
- **Correction** : renommer le fichier en `.corrupt-<horodatage>`, repartir d'un journal vide en le journalisant, rattraper aussi `UnicodeDecodeError` et `OSError`.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C07 — Écriture atomique sans réessai sous Windows
- **Problème** : `atomic_json` ne réessaie pas un `os.replace` refusé, alors que `write_responses` réessaie 50 fois.
- **Preuve** : `bridge/radio_bridge.py:477-483` contre `:333`.
- **Risque** : tour ou acquittement perdu (antivirus, indexeur).
- **Correction** : une seule fonction d'écriture atomique avec un réessai bref, utilisée partout.
- **Priorité** basse · **Effort** S · à vérifier en conditions réelles.
- **Avancement : ⬜ à faire.**

#### C08 — Codes de langue déformés pour les appels spontanés et les bulletins
- **Problème** : `re.sub(r"[^A-Za-z]", "", …)` retire le `_` : `ES_CL` devient « ESCL ». La table locale ne compte que 9 langues, alors que `npc_protocol` en connaît 28 et accepte `ES_CL`/`ES_MX`.
- **Preuve** : `bridge/radio_bridge.py:126-127`, `:746`, `:798` ; `bridge/npc_protocol.py:29`, `:710-716`.
- **Risque** : traduction. Langue mal nommée pour le modèle.
- **Correction** : réutiliser `npc.LANGUAGE_CODE` et `npc.language_name`, supprimer la table en double.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C09 — Une demande sans `sent` (ou `sent = "nan"`) n'expire jamais
- **Problème** : la valeur par défaut `now_ms` donne un âge nul, contrairement à la docstring (« unreadable: too old »). Avec `nan` ou `inf`, toutes les comparaisons sont fausses.
- **Preuve** : `bridge/radio_bridge.py:1776-1781`.
- **Risque** : bug mineur, demandes périmées traitées.
- **Correction** : `sent` absent ou non fini (`math.isfinite`) = trop ancien. Ajouter un test de `request_age`.
- **Priorité** basse · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C10 — Aucune borne de taille du prompt côté pont
- **Problème** : seul le serveur limite le contexte. Le pont sérialise tout `context`, `personality` et `offers` dans le prompt système, dans la limite de 256 Kio par enveloppe et de 1 Mo par fichier.
- **Preuve** : `bridge/npc_protocol.py:9`, `:1048-1049` ; `bridge/radio_bridge.py:271`.
- **Risque** : coût LLM. Un bogue serveur ou un contexte qui grossit peut coûter des dizaines de milliers de jetons par demande.
- **Correction** : plafond en caractères ou en jetons estimés avant l'appel, refus journalisé `prompt_too_large`.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Statut : corrigé (commit 4215bd3), à vérifier en jeu**
- **Avancement : ✅ corrigé, non publié (commits 4215bd3, 69e550c), testé hors jeu (`tests/test_bridge_guards.py`), à vérifier en jeu** — tâches E16-T06 et E16-T07 (plafond réglable).
- **Suite (2026-10-21, confirmée par l'utilisateur)** : plafond réglable dans la configuration du pont (`LLM_MAX_TOKENS`, `LLM_MAX_PROMPT_CHARS`, mêmes défauts, valeur invalide remplacée par le défaut) ; tâche `E16-T07`.

#### C11 — Journaux : texte des joueurs, corps d'erreur du fournisseur, secrets en `--debug`
- **Problème** :
  - texte et compte du joueur écrits à chaque demande, hors mode debug ;
  - jusqu'à 300 caractères du corps d'erreur HTTP journalisés ;
  - `--debug` écrit les messages complets, y compris la section des secrets des fiches.
- **Preuve** : `bridge/radio_bridge.py:1813`, `:707`, `:1832`, `:671`, `:459-462`.
- **Risque** : sécurité et vie privée. Un terminal collé dans un ticket ou sur Discord.
- **Correction** : texte joueur seulement en debug (ou tronqué), masquer les motifs `sk-…` et `Bearer …`, avertissement au lancement de `--debug`.
- **Priorité** basse · **Effort** S · confirmé statiquement (la répétition d'une clé par le fournisseur reste à vérifier).
- **Avancement : ⬜ à faire.**

#### C12 — Corps d'erreur HTTP lu sans délai ; aucun réessai sur 429/5xx
- **Problème** : `err.read()` est appelé hors `_read_body`, donc hors du budget de 60 s. Le pont s'arrête sur tout code autre que 400.
- **Preuve** : `bridge/radio_bridge.py:704`, `:710`.
- **Correction** : lire par `_read_body(err, deadline)` ; un seul réessai court sur 429/503 si le budget le permet, en respectant `Retry-After`.
- **Priorité** basse · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C13 — Pont : duplications et fichier monolithique
- **Problème** :
  - `CACHE_TABLES` et `MISSION_TEMPLATES` existent en double, dans `radio_bridge.py:1489`/`:1492` et dans `persona_store.py:28-29` ;
  - table des langues en double (C08) ;
  - réponse d'erreur construite deux fois (`:1833-1836` et `:1914-1917`) ;
  - décodage hexadécimal répété six fois (`:893`, `:947`, `:1003`, `:1037`, `:1228`, `bulletin.py:31`) ;
  - `radio_bridge.py` fait 2 014 lignes (son en-tête en annonce 1 797) et mêle transport, client LLM, historique et prompts de mission, de commerce et de réputation (`:1021-1384`).
- **Risque** : maintenabilité. Une liste fermée modifiée d'un seul côté laisse passer ou refuse à tort une action.
- **Correction** : importer les constantes de `persona_store` ; fonctions `decode_hex_field(raw, max_chars)` et `error_reply(req, code)` ; découpage en `transport.py`, `llm_client.py`, `history.py`, `prompts_*.py`.
- **Priorité** moyenne (doublons) / basse (découpage) · **Effort** M / L · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C14 — Fichiers d'état du pont qui grossissent sans fin
- **Problème** :
  - `token_usage.jsonl` sans rotation ;
  - `history_<session>[_voix].json` jamais purgés ;
  - dictionnaire `callers` jamais réduit ;
  - fichiers `npc_*.json` jamais purgés.
- **Preuve** : `bridge/radio_bridge.py:168`, `:361-365`, `:385`.
- **Correction** : rotation mensuelle du journal de jetons ; option `--prune <jours>` pour les sessions et PNJ inactifs (PNJ morts : liste fournie par le serveur).
- **Priorité** basse · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C15 — Tests du pont manquants
- **Problème** : rien ne couvre :
  - `PermissionError` à l'écriture ;
  - JSON de PNJ corrompu ;
  - `TokenUsageLog`, `request_age`, `single_instance` ;
  - `leaks_secret` en direct ;
  - usurpation `[Caller N]` ;
  - réessai 429 ;
  - code `ES_CL` côté radio.
- **Preuve** : recherche dans `tests/` (`test_protocol.py`, `test_fake_llm.py`, `test_bulletin.py`).
- **Correction** : un test ciblé par point, plus un banc d'injection rejoué en `--offline` avec un faux LLM qui « obéit » (vérifie que les bornes tiennent).
- **Priorité** moyenne · **Effort** S à M · confirmé par recherche.
- **Avancement : 🟡 en partie, non publié (commit 4215bd3)** — seule l'usurpation `[Caller N]` est couverte (`CallerTagTests` de `tests/test_bridge_guards.py`, avec C02) ; restent `PermissionError`, JSON de PNJ corrompu, `TokenUsageLog`, `request_age`, `single_instance`, `leaks_secret`, réessai 429 et `ES_CL`.

#### C16 — Petits défauts du pont
- **Problème** :
  - `radio_bridge.py:1636` journalise « 'report_mission' dropped » aussi pour `share_frequency` ;
  - `npc_protocol.py:558` contient une longue suite d'espaces au milieu d'une condition (reste d'une fusion de lignes).
- **Priorité** basse · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

### Serveur RadioSurvivor : état, persistance et commandes

Chemins relatifs à `Contents/mods/batman_RadioSurvivor/42.21/media/lua/`.

#### C17 — Personnages morts jamais purgés de l'état
- **Statut : corrigé (commit 3760771), à vérifier en jeu** — `server/RadioSurvivor/RS_StatePurge.lua` : mort datée (`retiredDay`), contacts, missions connues et historique radio vidés après 7 jours de jeu, fiche supprimée après 30 jours si aucune mission, dernières pages (journal gelé) ni réputation ne la citent ; 50 fiches par passe, une passe par jour de jeu à la sauvegarde (commit 99dc0bc).
- **Avancement : ✅ corrigé, non publié (commits 3760771, 99dc0bc), testé hors jeu (`tests/test_rs_state.py`), à vérifier sur un serveur dédié** — tâche E16-T08.
- **Problème** : à la mort, seuls `retired = true` et `record.radio = nil` sont posés. `S.data.characters[id]` et ses `contacts` (jusqu'à 40 lignes d'historique par PNJ) ne sont jamais supprimés : aucun `characters[...] = nil` dans le code. `prune` garde en plus toute fiche PNJ citée par un contact, même d'un mort.
- **Preuve** : `server/RS_Carnet_Server.lua:1300-1314`, `:1110` ; `server/RadioSurvivor/RS_Reputation.lua:371-380` (la réputation, elle, a son `prune`).
- **Risque** : persistance. Sur un serveur durable, chaque mort ajoute des données pour toujours, jusqu'au seuil de C18.
- **Correction** : purger le personnage retiré, ses contacts et ses `knownMissions` après N jours de jeu (comme `Rep.prune`), puis les fiches PNJ orphelines. Garder ce qu'utilisent les dernières pages (E15) et le mémorial (E14).
- **Priorité** haute · **Effort** M · confirmé statiquement.

#### C18 — L'encodeur accepte un état que le décodeur refuse ; aucune migration de schéma
- **Statut : corrigé (commit 3760771), à vérifier en jeu** — `encodeBytes` contrôle les mêmes limites que le décodeur (nœuds, profondeur, entrées, nombres finis) ; au-delà, purge forcée des morts puis refus sans écrire (aucun fichier illisible) ; alerte console à 70 % ; `RS_State.upgrade`/`MIGRATIONS` (aucune migration encore, schéma 2) ; un emplacement d'un schéma plus récent bloque au lieu de relire l'ancien. Alerte aux admins connectés non faite (texte joueur à traduire).
- **Avancement : ✅ corrigé, non publié (commit 3760771), testé hors jeu (`tests/test_rs_state.py`), à vérifier sur un serveur dédié** — tâche E16-T08 ; reste l'alerte aux admins connectés.
- **Problème** :
  - `encodeBytes` ne contrôle que la taille (4 Mio) ;
  - `decodeBytes` refuse au-delà de 200 000 nœuds, d'une profondeur de 12 ou de 10 000 entrées par table ;
  - la relecture de contrôle de `S.save` échoue alors et bloque le stockage ; au redémarrage, c'est l'emplacement précédent qui est relu ;
  - par ailleurs, `read` refuse tout `data.schema ~= 2` : `RS_State` n'a aucune migration (contrairement à `LK_Store`, qui migre par `Identity.upgrade`). Le premier changement de schéma bloquera les mondes existants.
- **Ordre de grandeur** : un historique radio complet fait environ 2 900 nœuds. Le seuil est atteint vers 70 personnages actifs, ou vers 700 contacts pleins.
- **Preuve** : `shared/RadioSurvivor/RS_Codec.lua:251-256` contre `:259-264`, `:282` ; `server/RadioSurvivor/RS_State.lua:22`, `:36-39`, `:63-67` ; `server/LivingKnox/LK_Store.lua:10-13`.
- **Risque** : persistance, perte des données de la session.
- **Correction** : mêmes limites contrôlées à l'encodage, avec une alerte d'administration à 70 % du seuil ; borner les registres (C17) ; `RS_State.upgrade(data)` par numéro de schéma, avec un test lupa d'un état v2 relu après passage en v3.
- **Priorité** haute · **Effort** S (limites) + M (migration) · confirmé statiquement.

#### C19 — Une erreur d'écriture passagère coupe le carnet jusqu'au redémarrage
- **Statut : corrigé (commit 3760771), à vérifier en jeu** — écriture ratée : plus de blocage, `S.dirty` gardé, nouvel essai à la sauvegarde suivante sur le même emplacement (l'autre garde le dernier bon fichier), journal au 1er échec puis tous les 20. Blocage réservé à l'état corrompu. Prévenir les admins connectés : non fait.
- **Avancement : ✅ corrigé, non publié (commit 3760771), testé hors jeu (`tests/test_rs_state.py`), à vérifier sur un serveur dédié** — tâche E16-T08 ; reste à prévenir les admins connectés.
- **Problème** : un `getFileWriter` nul, une relecture ratée ou un encodage refusé posent `S.blocked = true` pour toute la session, avec un simple `print`. Seul `S.init` remet l'indicateur à faux. Toutes les commandes répondent ensuite `Storage`.
- **Preuve** : `server/RadioSurvivor/RS_State.lua:45`, `:52-55`, `:60`, `:63-67`.
- **Risque** : persistance. Toutes les modifications de la session sont perdues sans que l'admin le sache.
- **Correction** : distinguer l'état corrompu (blocage justifié, fichiers conservés) de l'écriture ratée (nouvel essai borné, `S.dirty` gardé) ; prévenir les admins connectés et l'admin de LK13-T01.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.

#### C20 — Sauvegarde synchrone complète, lente et très fréquente
- **Statut : corrigé en partie (commit 3760771), à vérifier en jeu** — hex par table de remplacement, `unhexBytes` et somme de contrôle par blocs dans `RS_Codec` (mêmes octets, testé) ; relecture de contrôle à la première écriture et après un échec. Reste : écriture regroupée en fin d'image (`markChanged`), qui touche les 38 appels de `RS_Carnet_Server.lua`.
- **Avancement : 🟡 en partie, non publié (commit 3760771), testé hors jeu (`tests/test_rs_state.py`)** — tâche E16-T08 ; reste l'écriture regroupée en fin d'image (`markChanged`) ; gain à mesurer en jeu.
- **Problème** : chaque `S.save` fait :
  - un encodage complet ;
  - une conversion hexadécimale par `gsub` avec un appel de fonction Lua par octet ;
  - une somme de contrôle octet par octet, avec deux modulos par octet ;
  - l'écriture, puis une relecture complète (hex et décodage).

  On compte 38 appels `S.save()` dans le serveur : toutes les 5 s dès qu'une mission tourne, à chaque `note` ou `select`, deux fois par `talk`, quatre fois par livraison. `LK_Store` a déjà résolu ce problème : tables de remplacement `gsub`, somme par blocs de 16 octets, une écriture par image, relecture une fois par session (LK13-T06/T10).
- **Preuve** : `server/RadioSurvivor/RS_State.lua:49-71` ; `shared/RadioSurvivor/RS_Codec.lua:138-145`, `:308-312` ; `server/RS_Carnet_Server.lua:1207-1209` ; `server/RadioSurvivor/RS_Missions.lua:239-255` ; à comparer avec `server/LivingKnox/LK_Store.lua:69-120`.
- **Risque** : perf Kahlua (3 à 6 fois plus lent que Lua 5.1 sur ce code, base `kahlua-lua.md`), saccades du serveur qui grandissent avec l'état (C17).
- **Correction** :
  - déplacer `hexOfBytes`, `unhexOfBytes` et `checksumOfBytes` de `LK_Store` dans `RS_Codec` (mêmes octets, testé) ;
  - `S.markChanged()` plus une écriture en fin d'image, avec une écriture immédiate gardée pour les transactions de livraison et de récompense ;
  - relecture de contrôle à la première écriture seulement.
- **Priorité** haute · **Effort** M · confirmé statiquement, gain à mesurer en jeu.

#### C21 — Commandes du carnet et de la radio sans limite de débit
- **Problème** :
  - `hello`, `snapshot`, `select`, `deselect`, `note` et `mandate` n'ont aucune limite par joueur ; chacune déclenche `scan()` (tous les corps de PNJ), `M.advance`, l'encodage du snapshot et souvent `S.save()`. Seul `talk` a un délai ;
  - `history` renvoie jusqu'à 9 paquets de 40 lignes par demande ;
  - `rep_admin` journalise chaque refus sans limite, avant le contrôle d'identité, alors que `RS_FreqDebug.refuse` limite déjà ses refus.
- **Preuve** : `server/RS_Carnet_Server.lua:930-980`, `:943`, `:1083-1086` ; `server/RadioSurvivor_Server.lua:500-501` ; `server/RadioSurvivor/RS_RadioLog.lua:267-279` ; `server/RadioSurvivor/RS_FreqDebug.lua:93-106`.
- **Risque** : MP et autorité. Un client modifié peut geler le serveur ou inonder ses journaux.
- **Correction** : seau à jetons par compte à l'entrée de `Server.command` et de `onClientCommand` (même répartiteur que C31) ; snapshot en cache s'il n'a pas changé ; refus journalisés une fois par fenêtre.
- **Priorité** haute · **Effort** S · confirmé statiquement.
- **Statut : corrigé (commit 2d8cae5), à vérifier en jeu** — Seaux par compte (`RS_RateLimit`, serveur MP seulement) : `hello` 4 puis 1/2 s, `snapshot` 6 puis 1/s, `rep_admin` 3 puis 1/5 s, autres commandes du carnet 20 puis 4/s ; `history` 3 puis 1/5 s, autres commandes radio 30 puis 6/s ; commande refusée sans réponse, refus journalisés une fois par minute. Snapshot en cache non fait.
- **Avancement : ✅ corrigé, non publié (commit 2d8cae5), testé hors jeu (`tests/test_server_guards.py`), à vérifier en MP** — tâche E16-T09 ; snapshot en cache non fait.

#### C22 — Nettoyage de texte quadratique appliqué avant la troncature
- **Problème** : `Const.oneLine` utilise `^%s*(.-)%s*$`, dont le retour arrière est en O(n²) sur une longue suite d'espaces suivie d'un caractère. `onTalk` et `Log.heard` l'appliquent au texte brut du client, avant de le couper à `MAX_INPUT_CHARS`.
- **Preuve** : `shared/RadioSurvivor/RadioSurvivor_Const.lua:239-242` ; `server/RadioSurvivor_Server.lua:400-404` ; `server/RadioSurvivor/RS_RadioLog.lua:66-71`, `:251`.
- **Risque** : sécurité et perf. Un paquet `talk` de quelques dizaines de kilo-octets d'espaces bloque le fil serveur.
- **Correction** : refuser un `args.text` plus long que quatre fois la borne, tronquer avant tout `gsub`, rogner par `find("%S")` et `find("%S%s*$")`.
- **Priorité** haute · **Effort** S · coût confirmé statiquement, effet à mesurer en jeu.
- **Statut : corrigé (commit 2d8cae5), à vérifier en jeu** — `Const.oneLine` linéaire (deux `find`) ; `onTalk` ignore un texte de plus de 4 × `MAX_INPUT_CHARS` ; `Log.cleanText` coupe à 4 × `MAX_TEXT` avant tout motif.
- **Avancement : ✅ corrigé, non publié (commit 2d8cae5), testé hors jeu (`tests/test_server_guards.py`), à vérifier en MP** — tâche E16-T09.

#### C23 — La radio ignore les contrôles de chat de la parole de proximité
- **Problème** : `chatAllowed` (mort, sommeil, `isAllChatMuted`, `ChatStreams`, `detectBadWords`) ne s'applique qu'à la parole de proximité. Un joueur muet ou endormi, ou un texte filtré, atteint le LLM par la radio d'une voix ou d'un groupe. `GroupRadio.talk` ignore aussi `ChatMessageSlowModeTime`.
- **Preuve** : `server/RadioSurvivor_Server.lua:395-413` ; `server/RadioSurvivor/RS_GroupRadio.lua:119-170` ; à comparer avec `server/RS_Carnet_Server.lua:262-274`.
- **Risque** : MP et autorité. Les règles de modération du serveur sont contournées.
- **Correction** : `chatAllowed` partagé et appelé au début d'`onTalk` et de `GroupRadio.talk`.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C24 — `select` crée une fiche PNJ avant de contrôler la distance
- **Problème** : `Server.ensure(args.incarnation)` crée une entrée `S.data.npcs` pour toute incarnation envoyée par le client, avant le test `P.near`. Ces fiches ne sont purgées qu'au bout d'une heure sans corps.
- **Preuve** : `server/RS_Carnet_Server.lua:949-961` (ligne 952).
- **Risque** : MP et persistance. Énumération d'identifiants, croissance de l'état.
- **Correction** : `Server.find`, puis `P.near` sur l'objet du fournisseur, et `ensure` seulement ensuite.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C25 — Fichier de réponses du pont relu et décodé chaque seconde, deux fois
- **Problème** : `poll()` du carnet tourne sans condition à chaque seconde : lecture jusqu'à 1 Mio, décodage hex avec un appel par paire, décodage de chaque charge. La radio relit le même fichier avec son propre analyseur.
- **Preuve** : `server/RS_Carnet_Server.lua:1178` ; `server/RadioSurvivor/RS_Transport.lua:51-71` ; `server/RadioSurvivor_Server.lua:174-204`.
- **Risque** : perf.
- **Correction** : garde `#Server.pending > 0 or #T.acks > 0` (déjà présente côté radio) et un seul lecteur partagé dans `RS_Transport`.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C26 — `getTextOrNull(clé)` sans arguments sur des textes à `%1`
- **Problème** : les clés `IGUI_RadioSurvivor_Call*` et `IGUI_RS_Bulletin_*` contiennent `%1` ou `%2`. Le test d'existence sans arguments écrit « Missing arguments » au journal à chaque appel spontané ou ligne de bulletin (base `load-warnings.md`).
- **Preuve** : `server/RadioSurvivor_Server.lua:519`, `:524`, `:531` ; `server/RadioSurvivor/RS_Facts.lua:594`, `:599-600`.
- **Risque** : traduction et journal pollué.
- **Correction** : un seul `getTextOrNull(key, ...)` avec les vrais arguments, dont le retour sert directement ; à intégrer à l'assistant unique de C34.
- **Priorité** basse · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C27 — Délais de mission décomptés en temps réel, pause comprise
- **Problème** : `tick` est abonné à `OnTickEvenPaused` et `remainingMs` diminue du temps réel écoulé. Une mission de 2 h (`RS_Config.lua:223`) continue de s'écouler en pause solo (Échap) et sur un serveur vide en pause (`PauseEmpty`).
- **Preuve** : `server/RS_Carnet_Server.lua:1139`, `:1293` ; `server/RadioSurvivor/RS_Missions.lua:180-182`.
- **Risque** : bug probable ou choix non documenté. Le chrono est bien arrêté pendant l'arrêt du serveur (preuve E00-T01), mais pas pendant une pause.
- **Correction** : ne pas décompter si le jeu est en pause (vitesse 0 en solo, serveur sans joueur), ou passer aux minutes de jeu. ~~Décision à poser~~ à l'utilisateur.
- **Décision (2026-10-21, confirmée par l'utilisateur)** : les délais des missions suivent le temps de jeu (arrêt en pause, accélération en x2/x3), comme les délais vanilla.
- **Statut** : décidé, tâche `E11-T20` (temps restant et délai entre deux offres comptés en temps de jeu à vitesse normale, `RS_GameClock`) ; codé et testé hors jeu, à vérifier en jeu.
- **Avancement : ✅ corrigé, non publié (commits 24d6cab, a2a81b3), testé hors jeu (`tests/test_carnet.py`, `tests/test_kahlua.py`), à vérifier en jeu** — tâches E11-T20 (délais) et E16-T10 (lot non réclamé).
- **Suite (2026-10-21, confirmée par l'utilisateur)** : la conservation d'un lot réussi non réclamé (`UNCLAIMED_RETENTION_MS`, 7 jours réels) devient 7 jours **de jeu** (`UNCLAIMED_RETENTION_HOURS`, âge du monde), avec conversion des lots déjà enregistrés ; tâche `E16-T10`.
- **Priorité** moyenne · **Effort** S · à vérifier en jeu.

#### C28 — Chaque zombie compté republie tous les snapshots
- **Problème** : `publish()` reconstruit et encode le snapshot complet de chaque joueur connecté (missions, contacts et leur historique) pour décider s'il faut l'envoyer. Il est appelé à chaque zombie compté par une mission « nettoyer ».
- **Preuve** : `server/RadioSurvivor/RS_MissionClear.lua:283-290` ; `server/RS_Carnet_Server.lua:196-249` (encodage ligne 237).
- **Risque** : perf pendant les combats, quand le serveur est le plus chargé.
- **Correction** : `publishDirty` et publication au plus une fois par seconde dans `tick`.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C29 — Contrôle de distance d'une action sauté si l'appelant s'est déconnecté
- **Problème** : `distance()` rend `nil` sans joueur, ce qui fait sauter le refus `too_far`. L'exécuteur reçoit `ctx.player == nil` : une réponse du LLM arrivée après la déconnexion peut exécuter `mark_map`, `start_mission` ou `place_cache`.
- **Preuve** : `server/RadioSurvivor/RS_Actions.lua:129-136`, `:160-163`.
- **Risque** : MP et autorité ; erreur possible dans un exécuteur.
- **Correction** : refus `caller_gone` pour les actions liées au joueur quand `ctx.player` est nul, sauf celles déclarées sans joueur.
- **Priorité** basse · **Effort** S · contrôle sauté confirmé statiquement ; comportement des exécuteurs à vérifier.
- **Avancement : ⬜ à faire.**

### Living Knox : performance et réseau

#### C30 — `Bodies.find` parcourt toute la liste des zombies à chaque appel
- **Problème** : `Bodies.find` appelle `Bodies.inWorld`, qui fait `getCell():getZombieList():contains(z)` : un `ArrayList.contains` Java en O(nombre de zombies de la cellule). On compte 52 appels de `find` dans le Lua, dont 12 dans les modules appelés à chaque image (`LK_Relay`, `LK_Directives`, `LK_Decisions`).
- **Preuve** : `server/LivingKnox/LK_Bodies.lua:62-65`, `:444-451`.
- **Risque** : perf Kahlua et Java. Coût de PNJ incarnés × appels × zombies chargés. Avec une population élevée (plusieurs milliers de zombies autour de joueurs dispersés), cela crée des pointes. Le test lui-même est juste (base `zombies-as-npc-bodies.md` : `isDead` reste faux une fois le corps mis de côté).
- **Correction** : cache par image (`id → résultat`, invalidé au changement d'image ou à `bodyBound`/`despawn`), ou test `contains` limité au premier `find` de l'image pour chaque PNJ. Mesurer avant et après avec `LK_Load` (LK13-T02).
- **Priorité** moyenne · **Effort** S · confirmé statiquement, coût à mesurer en jeu.
- **Statut : corrigé (commit 2d8cae5), à vérifier en jeu** — Cache par PNJ du test `contains`, valable pour un même `getWorld():getFrameNo()` et un même `getTimestampMs()`, vidé par `removeBody` ; gain à mesurer avec `LK_Load`.
- **Avancement : ✅ corrigé, non publié (commit 2d8cae5), testé hors jeu (`FindCacheTests` de `tests/test_lk_bodies.py`)** — tâche E16-T09 ; gain à mesurer avec `LK_Load`.

#### C31 — Commandes réseau : environ 30 abonnés qui filtrent chacun le module, sans limite de débit
- **Problème** :
  - côté serveur, environ 15 abonnés `OnClientCommand` (`LK_Admin`, `LK_Combat`, `LK_Death`, `LK_Directives`, `LK_Health`, `LK_Relations`, `LK_Relay`, `LK_Reports`, `LK_Trade`, `LK_Equipment`, `LK_Load`, `LK_Senses`, `LK_ZombieGuard`, `RS_FreqDebug`, `RS_Carnet_Server`, `RadioSurvivor_Server`) ;
  - côté client, 16 abonnés `OnServerCommand`, chacun comparant `module`/`command` ;
  - la commande `guardHello` est traitée par plusieurs modules : `LK_Relay.onHello` parcourt alors tous les PNJ publiés, sans limite par joueur.
- **Preuve** : `server/LivingKnox/LK_Relay.lua:398-420`, `:422-427` ; `server/LivingKnox/LK_Combat.lua:1224-1232` ; `shared/LivingKnox/LK_Senses.lua:1078-1083`.
- **Risque** : MP et perf. Un client modifié qui répète `guardHello` à chaque image force des parcours complets et des renvois d'état. Chaque commande traverse aussi une trentaine de fonctions Lua.
- **Correction** : un répartiteur unique `module → command → handler` par machine (un seul abonnement), avec un compteur par compte et par commande (par exemple `hello` au plus une fois par seconde). Les gestionnaires existants restent inchangés.
- **Priorité** moyenne · **Effort** M · confirmé statiquement (l'effet d'une répétition abusive reste à mesurer).
- **Statut : corrigé (commit 2d8cae5), à vérifier en jeu** — `guardHello` limité par compte et par module (`ZombieGuard.helloAllowed` : 3 puis 1/2 s) ; répartiteur unique non fait (les abonnés restent séparés).
- **Avancement : 🟡 en partie, non publié (commit 2d8cae5), testé hors jeu (`tests/test_server_guards.py`)** — tâche E16-T09 : `guardHello` limité par compte ; répartiteur unique non fait.

#### C32 — Joueurs déconnectés gardés dans `Relay.players` et `Relay.sent`
- **Problème** : `Relay.players[name]` garde le dernier `IsoPlayer` connu et `Relay.sent[name]` n'est jamais purgé. Aucun abonné de déconnexion dans le moteur. `publish` envoie à `Relay.players[name]` tant que le compte figure dans `Relay.near`.
- **Preuve** : `server/LivingKnox/LK_Relay.lua:47`, `:173`, `:265-268`, `:295-298`, `:401-402`.
- **Risque** : MP. Envoi à un objet joueur périmé (sans effet ou erreur selon l'état de la connexion), état « important » (`pub.keep`) qui attend l'accusé d'un destinataire parti jusqu'au prochain `refresh`, et mémoire qui grandit sur un serveur à forte rotation.
- **Correction** : purge par sondage de `getOnlinePlayers()` (la base `multiplayer.md` recommande le sondage, faute d'événement serveur fiable), et `mayPublish` qui ignore les comptes hors ligne.
- **Priorité** basse · **Effort** S · à vérifier en jeu (reconnexion, puis départ définitif d'un joueur près d'un PNJ).
- **Avancement : ⬜ à faire.**

#### C33 — Allocation d'une table à chaque image côté client
- **Problème** : `drain()` reconstruit `Client.inbox` à chaque `OnTick`, même vide. Le même abonné rappelle aussi `Client.installChat()` à chaque image, ce qui ne fait que deux tests une fois installé.
- **Preuve** : `client/RadioSurvivor/RS_Client.lua:101-105`, `:283-292`.
- **Risque** : perf (ramasse-miettes Kahlua), faible.
- **Correction** : `if #Client.inbox == 0 then return end` ; `installChat` seulement jusqu'à ce que les deux enveloppes soient posées.
- **Priorité** basse · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

### Qualité, outillage, interface et publication

#### C34 — Rechargement des traductions copié dans 8 modules
- **Problème** : le motif « clé absente sur un serveur MP → `Translator.loadFiles()` une fois → `getTextOrNull` » est réécrit dans 8 fichiers, chacun avec son propre indicateur. Un serveur peut donc recharger toutes les traductions jusqu'à 8 fois, et les variantes divergent : avec ou sans test `Translator ~= nil`, surcharges sans `nil`.
- **Preuve** :
  - `server/RadioSurvivor_Server.lua:512-531` ;
  - `server/RadioSurvivor/RS_Facts.lua:592-601` ;
  - `server/RadioSurvivor/RS_LastPages.lua:83-100` ;
  - `server/RadioSurvivor/RS_RescueLost.lua:82-100` ;
  - `server/RadioSurvivor/RS_RescueScene.lua:69-89` ;
  - `server/RadioSurvivor/RS_RescueVisit.lua:328-334` ;
  - `server/RadioSurvivor/RS_TradeRun.lua:61-69` ;
  - `server/LivingKnox/LK_Traces.lua:96-106`.
- **Risque** : maintenabilité et traduction. Le prochain module oubliera le rechargement et écrira des clés brutes en MP (piège de la liste de contrôle MP, `multiplayer.md`).
- **Correction** : un module partagé `RS_Tr` (`tr(key, ...)` sans argument `nil` passé au Java, rechargement unique, journal des clés manquantes une fois) utilisé partout, avec un test lupa du chemin « serveur sans traductions ».
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C35 — Contrôle des droits d'administration copié
- **Problème** : `Admin.isAllowed` et `FreqDebug.isAllowed` sont la même fonction : `checkPermissions` + `getRole():hasCapability`, puis le mode debug en solo.
- **Preuve** : `server/LivingKnox/LK_Admin.lua:141-156` ; `server/RadioSurvivor/RS_FreqDebug.lua:76-90`.
- **Risque** : sécurité par divergence. Le jour où la règle change (base `multiplayer.md` : double contrôle exigé), un seul des deux sera corrigé.
- **Correction** : `LivingKnox.Permissions.allowed(player, capabilityName, debugOnly)` partagé.
- **Priorité** basse · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C36 — luacheck ne contrôle aucune globale
- **Problème** : `global = false`. Une faute de frappe dans un nom (lecture d'une globale inexistante, toujours `nil`) n'est jamais signalée. Le relevé des écritures ne montre que 22 globales, toutes voulues (`LivingKnox`, `RS_*`, `processSayMessage`) : la liste blanche serait courte.
- **Preuve** : `.luacheckrc:5` ; relevé `luacheck --only 111` du 2026-10-21.
- **Risque** : tests et maintenabilité. Bogues `nil` silencieux, surtout dans les chemins rarement exécutés.
- **Correction** : `globals = { 22 noms }` et `read_globals` généré depuis l'index de l'API Lua 42.21 (sources `E:\pz-decompiled\42.21.0`), à lancer d'abord en rapport sans bloquer, puis à intégrer à la référence `tests/luacheck_baseline.txt` (15 avertissements acceptés aujourd'hui).
- **Priorité** moyenne · **Effort** M · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C37 — Pas d'intégration continue sur le dépôt public
- **Problème** : pas de dossier `.github/`. `tests/run_all.py` (environ 140 étapes) n'est lancé qu'à la main. Le banc Kahlua et `check_case` passent déjà en `SKIP` sans leurs dépendances.
- **Preuve** : absence de `.github/` ; `tests/run_all.py:1-25`.
- **Risque** : tests. Une contribution externe, ou un commit fait depuis une autre machine, n'est jamais vérifiée.
- **Correction** : workflow GitHub Actions avec Python, lupa et luacheck, qui lance `run_all.py --keep-going` et `tools/plan.py check` (les SKIP sont admis). Aucune donnée privée n'est en jeu : le dépôt est déjà public.
- **Priorité** moyenne · **Effort** S · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C38 — Fonctions de plusieurs centaines de lignes
- **Problème** : plus longues fonctions de premier niveau :

  | Fonction | Lignes |
  |---|---|
  | `Obstacles.planDoorRoute` (`LK_Obstacles.lua:1957`) | 289 |
  | `reply` (`RS_Carnet_Server.lua:605`) | 201 |
  | `Obstacles.findRoute` (`LK_Obstacles.lua:1584`) | 165 |
  | `Notebook:showDetail` (`RS_Notebook.lua:585`) | 162 |
  | `parse` (`RS_Persona.lua:253`) | 154 |
  | `Simulation.simulateHour` (`LK_Simulation.lua:517`) | 147 |
  | `Care.apply` (`LK_Care.lua:356`) | 138 |
  | `Executor.follow` (`LK_Executor.lua:444`) | 134 |

  Six fichiers dépassent 1 500 lignes, dont `LK_Obstacles.lua` (2 793) et `LK_Fortify.lua` (2 717).

  Doublons voisins :
  - purge horaire des quotas `Server.times` copiée trois fois (`RS_Carnet_Server.lua:359`, `:1213`, `RS_GroupRadio.lua:138`) ;
  - détection d'hélicoptère en double, avec 500 écrit en dur (`RS_ObservationTriggers.lua:301`, `RS_TradeRun.lua:201`).
- **Risque** : maintenabilité et tests. Ces fonctions concentrent les cas particuliers (portes, chemins, réponse du LLM) ; un changement local y a des effets lointains.
- **Correction** : à chaque nouvelle tâche qui les touche, extraire les étapes nommées (par exemple `planDoorRoute` : choix de la porte, état, clé, plan de repli ; `reply` : un gestionnaire par intention), sans refonte en bloc. Les tests lupa existants servent de filet de sécurité. Pour les doublons : `Server.underQuota(now)` et une seule détection d'hélicoptère.
- **Priorité** basse · **Effort** M (au fil des tâches) · confirmé statiquement.
- **Avancement : ⬜ à faire.**

#### C39 — Carnet et fenêtres Living Knox : pas de manette, joueur 0 seulement
- **Problème** : aucune gestion de manette (`JoypadState`, `onJoypadDown`) dans `RS_Notebook.lua` ni dans les vues `client/LivingKnox/`. Le client du carnet ne s'initialise que pour le joueur 0 (`OnCreatePlayer` avec `num == 0`) et ne sonde que `getSpecificPlayer(0)` ; on compte 29 appels `getPlayer()`/`getSpecificPlayer(0)` côté client.
- **Preuve** : `client/RadioSurvivor/RS_Client.lua:281`, `:287` ; recherche négative de `JoypadState` dans `client/`.
- **Risque** : jouabilité. Un joueur à la manette ne peut pas utiliser le carnet ; en écran partagé, les joueurs 2 à 4 n'ont ni carnet ni identité.
- **Correction** : documenter la limite dans le README et la page Workshop (rapide) ; puis focus manette sur le carnet (`setJoypadFocus`, base `ui-windows.md` : `LuaOpenWindow` et focus manette à gérer soi-même) ; l'écran partagé seulement si l'utilisateur le demande.
- **Priorité** basse · **Effort** S (documentation) / M (manette) · à vérifier en jeu.
- **Avancement : ⬜ à faire.**

#### C40 — Deux langues seulement pour un mod de texte
- **Problème** : traductions EN et FR seulement (842 clés `IG_UI`, 107 `Sandbox`, 68 `Print_Text`, 12 `Print_Media`, 6 `ItemName`, 1 `UI`, parité complète). Le pont sait pourtant demander au LLM 28 langues (`npc_protocol.py:710-716`). Un joueur espagnol ou russe aura des réponses dans sa langue, mais un carnet, des notes et des documents en anglais.
- **Preuve** : `media/lua/shared/Translate/` (EN, FR).
- **Risque** : traduction et publication.
- **Correction** : avant E16-T05, ajouter au moins ES, DE, RU, PTBR, CN, à partir des fichiers EN (attention : les polices `printMedia` sont SDF latin et cyrillique seulement, base `quest-building-blocks.md` ; pas de chinois, de japonais ni de coréen dans les documents). Script de parité des clés dans `run_all.py`.
- **Priorité** moyenne (avant publication) · **Effort** M · confirmé statiquement.
- **Avancement : ⬜ à faire.**

---

## Partie 2 — Idées de fonctionnalités

Contrainte rappelée : le LLM interprète le texte du joueur ; le serveur ne vérifie que des faits (positions, objets, états, horloge) ; jamais de liste de mots-clés. Les idées déjà au plan ou écartées par l'utilisateur ne figurent pas ici :
- répliques fixes sans pont (E08-T09 : sans pont, les PNJ se taisent) ;
- véhicules des PNJ (LK00, reporté) ;
- dizaines de groupes (LK00 : 3 à 5).

### Radio

#### I01 — Radiogoniométrie : trouver d'où vient un signal
- **Description** : en écoutant un émetteur réel (radio d'un groupe Living Knox E08-T06/T10, famille à secourir E12, passeur E13), le carnet note un relèvement approximatif (« plutôt vers le nord-est ») dont l'erreur dépend de la radio (haut de gamme ou non) et de la météo. Trois relèvements pris de points éloignés permettent d'estimer une zone sur la carte.
- **Intérêt joueur** : une vraie enquête radio, sans liste de coordonnées.
- **Faisabilité moteur** : le serveur connaît la position de la source et du joueur. Haut de gamme et bornes de réglage sont fiables côté serveur (`radio-dynamic.md`). Repère sur la carte : même mécanisme que `mark_map` (E07-T04).
- **Impact MP** : calcul serveur, envoi au seul écouteur, jamais la position exacte (`radio-dynamic.md` : une émission révèle déjà sa source aux clients ; ne rien ajouter de plus précis).
- **Dépendances** : E08-T06, E12, E07-T04.
- **Coût LLM** : nul.
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I02 — Réception dégradée par la distance et l'orage
- **Description** : une voix lointaine ou un temps d'orage hachent le texte reçu (mots remplacés par « … », grésillement), avec une chance de demander de répéter.
- **Intérêt joueur** : ambiance, intérêt de monter sur un toit ou de s'équiper d'une meilleure radio.
- **Faisabilité moteur** : texte composé par le serveur ; météo lisible côté serveur (`api-42-21.md` : `getIsThunderStorming`, `WeatherPeriod`). Le moteur brouille déjà les bulles selon la distance (`ChatElement.getScrambleValue`), à reproduire sur le texte.
- **Impact MP** : le brouillage est calculé pour chaque auditeur ; le texte d'origine reste au serveur.
- **Dépendances** : aucune.
- **Coût LLM** : nul. Le texte complet reste dans l'historique de la voix.
- **Effort** : S.
- **Avancement : ⬜ pas commencé (proposée).**

#### I03 — Indicatifs sonores des voix
- **Description** : chaque voix a une courte signature (générique de la station pirate, bip du passeur, sifflement de Walt), jouée sur la radio qui reçoit avant la réplique.
- **Intérêt joueur** : reconnaître une voix sans lire, et ambiance.
- **Faisabilité moteur** : `.ogg` du mod déclarés dans un script sonore, joués sur l'émetteur de la radio (`radio-dynamic.md` : son de la radio équipée seulement, à reproduire sur un émetteur gardé). La synthèse vocale en temps réel n'est pas faisable : les sons sont chargés au démarrage.
- **Impact MP** : son local joué par chaque client à la réception de la ligne.
- **Dépendances** : clips libres de droits.
- **Coût LLM** : nul.
- **Effort** : S.
- **Avancement : ⬜ pas commencé (proposée).**

#### I04 — Mots de passe et codes entre voix
- **Description** : une voix donne un code (« dis à Gus que tu viens de la part de la Chouette : *4-Pélican* »). Saisi dans un champ « code » de la section Émettre, il ouvre une remise ou une offre ailleurs.
- **Intérêt joueur** : relier les voix entre elles, récompenser la confiance.
- **Faisabilité moteur** : le serveur tire le code, le stocke dans `RS_State` et compare la saisie du champ dédié à l'identique. C'est un fait vérifié, pas une lecture du texte libre.
- **Impact MP** : code propre à chaque personnage (pas de partage automatique) ; le partager entre joueurs est un choix de jeu.
- **Dépendances** : E07 (liste fermée : action `give_code`), E07-T10.
- **Coût LLM** : faible (une action de plus).
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I05 — Rumeurs vérifiables
- **Description** : les voix relaient des faits du serveur (E14) avec un délai et parfois une erreur volontaire (mauvais quartier, nombre exagéré), marquée côté serveur. Le joueur qui va vérifier et le dit à la voix gagne en réputation ; la voix corrige sa version.
- **Intérêt joueur** : raisons d'explorer, monde qui « parle ».
- **Faisabilité moteur** : faits déjà journalisés (`RS_Facts`, `RS_LifeLog`) ; écart choisi par le serveur ; vérification par présence du joueur sur place (fait) ; le LLM juge seulement si le joueur a fait son compte rendu (comme `report_done`, E11-T13).
- **Impact MP** : rumeurs partagées par voix, vérification par personnage.
- **Dépendances** : E14, E11-T13, E04.
- **Coût LLM** : modéré (contexte un peu plus long).
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I06 — Appel de détresse du joueur vers les groupes alliés
- **Description** : un joueur blessé ou assiégé émet sur la fréquence d'un groupe allié qu'il connaît. Selon la relation, la distance et le stock du groupe, une équipe vient l'aider ou le groupe refuse. Des pillards à l'écoute peuvent aussi venir.
- **Intérêt joueur** : les alliances servent concrètement ; le risque de la radio devient visible.
- **Faisabilité moteur** : briques existantes : expéditions physiques (LK05-T05), défense (LK05-T09), dons (LK11-T06), radio des groupes (E08-T06/T10). Le LLM qualifie l'appel ; le serveur vérifie la blessure, les zombies proches et la relation.
- **Impact MP** : décision serveur ; équipe exécutée par le propriétaire des corps.
- **Dépendances** : E09 (accords), LK05-T05, LK11-T06.
- **Coût LLM** : faible.
- **Effort** : L.
- **Avancement : ⬜ pas commencé (proposée).**

#### I07 — Réponse radio dans la langue de l'appelant
- **Description** : les réponses directes d'une voix suivent la langue du jeu de l'appelant, comme le dialogue avec les PNJ (`RS_Carnet_Server.lua:362-363`). Aujourd'hui, la radio suit `CallLanguage` ou la langue du processus serveur (`RadioSurvivor_Server.lua:435`, `:535-538`).
- **Intérêt joueur** : serveurs multilingues.
- **Faisabilité moteur** : le client envoie déjà sa langue pour les PNJ ; même champ dans la demande radio.
- **Impact MP** : une ligne radio est entendue par toutes les radios proches. Garder la langue du serveur pour les appels spontanés et le bulletin, et la langue de l'appelant pour sa réponse directe (choix à faire valider).
- **Dépendances** : C08.
- **Coût LLM** : nul.
- **Effort** : S.
- **Avancement : ⬜ pas commencé (proposée).**

### Carnet et échanges entre joueurs

#### I08 — Recopier une page du carnet pour la donner
- **Description** : avec un crayon et une feuille vanilla, recopier une fréquence, un contact ou une conversation sous forme de note lisible. Lue par un autre joueur, elle ajoute l'entrée à son carnet, comme les notes de fréquence (E05-T09, E06-T07).
- **Intérêt joueur** : commerce d'informations en MP, coopération.
- **Faisabilité moteur** : document en lecture seule (`addPage` + `setLockedBy`, base `quest-building-blocks.md`), contenu composé et contrôlé par le serveur à partir de ce que le personnage sait réellement.
- **Impact MP** : objet ordinaire, transmissible ; validation à la lecture par le serveur.
- **Dépendances** : E05-T09.
- **Coût LLM** : nul.
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I09 — Tableau d'annonces d'un foyer ami
- **Description** : un panneau dans le foyer d'un groupe colon affiche ses besoins et ses offres de mission, lisibles par tous les joueurs qui passent.
- **Intérêt joueur** : point de rendez-vous MP, missions découvertes sans parler.
- **Faisabilité moteur** : meuble vanilla posé par script (`custom-tiles-entities.md`), texte composé par le serveur (besoins réels de `LK_Needs`, offres E11-T18), clic droit « Lire ».
- **Impact MP** : objet du monde partagé ; offre prise par le premier qui l'accepte.
- **Dépendances** : E11-T18, LK08-T04.
- **Coût LLM** : nul (gabarits) ou faible (une ligne d'accroche).
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I10 — Message écrit laissé à un groupe
- **Description** : glisser une note écrite par le joueur dans la boîte aux lettres ou sur la porte d'un foyer. Le LLM la lit au prochain passage d'un membre et le groupe y répond (réponse écrite, visite, refus).
- **Intérêt joueur** : contact sans risque physique, diplomatie asynchrone.
- **Faisabilité moteur** : retrouver un objet déposé (`world-placement.md` : `getWorldObjects`, `getItemWithIDRecursiv`) ; texte de la note borné par le serveur ; décision dans la liste fermée existante.
- **Impact MP** : le serveur lit la note ; l'auteur est l'écrivain enregistré, pas le dernier qui l'a touchée.
- **Dépendances** : E09, LK11.
- **Coût LLM** : faible (un appel par note).
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I11 — Résumé hebdomadaire du personnage
- **Description** : chaque semaine de jeu, une page du carnet résume l'histoire du personnage (rencontres, missions, pertes), écrite par le LLM à partir des faits du serveur.
- **Intérêt joueur** : récit personnel, souvenir de partie ; complète les dernières pages (E15).
- **Faisabilité moteur** : faits déjà journalisés (`RS_LifeLog`) ; même chemin que `last_pages.py`.
- **Impact MP** : par personnage, envoyé au seul propriétaire.
- **Dépendances** : E15, E14.
- **Coût LLM** : faible (un appel par semaine de jeu et par personnage actif).
- **Effort** : S.
- **Avancement : ⬜ pas commencé (proposée).**

### Living Knox

#### I12 — Les rescapés rejoignent une colonie
- **Description** : une famille secourue (E12) peut, si le joueur le propose et qu'un groupe ami a de la place, rejoindre ce groupe comme nouveaux membres incarnés.
- **Intérêt joueur** : les sauvetages laissent une trace durable ; la colonie grandit grâce au joueur.
- **Faisabilité moteur** : ajout de membre déjà géré par `LK_Groups` (relève, départ E10-T04) ; marche vers le foyer par les consignes « aller à ». Le LLM du groupe accepte ou refuse ; le serveur vérifie la place et le stock.
- **Impact MP** : transition serveur unique.
- **Dépendances** : E12, LK08, E10-T04.
- **Coût LLM** : faible.
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I13 — Escorte temporaire
- **Description** : un membre d'un groupe allié accompagne le joueur pour une mission précise (« je viens avec toi jusqu'à l'école »), le suit, se défend, puis rentre au foyer.
- **Intérêt joueur** : premier « compagnon », sans système de recrutement permanent.
- **Faisabilité moteur** : consignes aller à et suivi (LK02-T07), combat (LK06), retour (LK05-T05). Aucune autorité client : le serveur décide de la cible à suivre. Le plus dur : suivre un joueur qui court ou monte en voiture (rentrer seul si l'écart dépasse un seuil).
- **Impact MP** : propriétaire du corps qui change avec le joueur suivi (base `multiplayer.md` : changements toutes les 2 s au plus) ; à valider avec E01-T16.
- **Dépendances** : E09 (alliance), LK04, LK06.
- **Coût LLM** : faible (accord et répliques).
- **Effort** : L.
- **Avancement : ⬜ pas commencé (proposée).**

#### I14 — Commerce entre groupes hors écran
- **Description** : deux groupes amis échangent leurs surplus dans la simulation horaire (nourriture contre munitions). Le passeur et la station pirate le commentent ; les prix du troc avec le joueur suivent la rareté.
- **Intérêt joueur** : économie vivante, raisons de protéger une route.
- **Faisabilité moteur** : stock abstrait cohérent avec les conteneurs (LK09-T06) ; échanges abstraits seulement, rien ne naît de rien.
- **Impact MP** : serveur seul.
- **Dépendances** : LK09, LK11-T08, E13.
- **Coût LLM** : nul (simulation) ; faible si une voix le raconte.
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I15 — Besoins de saison : bois et chauffage en hiver
- **Description** : à l'approche du froid, les groupes stockent du bois, allument poêles et cheminées, et demandent des missions de bûcheronnage ou de couvertures.
- **Intérêt joueur** : saisons visibles dans la vie des PNJ.
- **Faisabilité moteur** : poêle ou cheminée reconnus (`IsoFireplace`, `custom-tiles-entities.md`), température lisible côté serveur ; nouvelle catégorie de besoin dans `LK_Needs`.
- **Impact MP** : serveur.
- **Dépendances** : LK05-T10, E11-T18.
- **Coût LLM** : nul.
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I16 — Signe de reconnaissance d'une alliance
- **Description** : une alliance conclue (E09-T05) donne un brassard ou un ruban porté. Les autres membres du groupe reconnaissent alors le porteur et ses coéquipiers de faction sans nouvelle négociation, et un voleur qui le porte se fait démasquer par les faits (relation personnelle mauvaise).
- **Intérêt joueur** : diplomatie lisible en MP.
- **Faisabilité moteur** : objet de mod avec une marque ModData (base : reconnaître ses propres objets par ModData) ; port vérifié par `isEquipped` côté serveur ; tenue vue par la perception (LK05).
- **Impact MP** : contrôle serveur ; la ModData de l'objet est copiée avec lui.
- **Dépendances** : E09-T03/T05.
- **Coût LLM** : nul.
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I17 — Prisonniers et échange contre rançon
- **Description** : un pillard qui se rend (reddition LK06-T05) peut être gardé, désarmé, puis échangé à son groupe contre des vivres ou une trêve, négociée par radio.
- **Intérêt joueur** : issue non létale qui crée des histoires.
- **Faisabilité moteur** : reddition et sommations existantes ; maintien en place par une consigne « rester » ; négociation par `negotiate` (E09). À cadrer : le comportement d'un PNJ « prisonnier » quand le joueur s'éloigne.
- **Impact MP** : serveur ; pas de capture par un client.
- **Dépendances** : LK06-T05, E09-T05, LK11-T07.
- **Coût LLM** : faible.
- **Effort** : L.
- **Avancement : ⬜ pas commencé (proposée).**

#### I18 — Cimetière et mémoire du foyer
- **Description** : les morts d'un groupe sont enterrés près du foyer avec une croix. La tombe porte le nom ; les membres s'y recueillent et en parlent.
- **Intérêt joueur** : deuil visible ; le passage du joueur a des conséquences.
- **Faisabilité moteur** : entretien du foyer et morts portés (LK05-T10) ; tombe vanilla ; nom par une marque ou une note. Le mémorial radio existe (E14-T03).
- **Impact MP** : serveur.
- **Dépendances** : LK05-T10, E14.
- **Coût LLM** : nul.
- **Effort** : S à M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I19 — Chien de garde des colons
- **Description** : un chien d'un groupe aboie quand un intrus approche, ce qui alerte les membres.
- **Intérêt joueur** : sentinelle lisible, discrétion plus difficile.
- **Faisabilité moteur** : `IsoAnimal` simulé par le serveur seul (`zombies-as-npc-bodies.md`) ; comportement Java non remplaçable. Seul l'aboiement (son, bruit) et l'alerte (LK05-T08) sont des leviers. **Hypothèse** à prototyper : chien vanilla gardé dans un enclos du foyer.
- **Impact MP** : serveur.
- **Dépendances** : LK05-T08.
- **Coût LLM** : nul.
- **Effort** : M (incertain).
- **Avancement : ⬜ pas commencé (proposée).**

### Administration et coût du LLM

#### I20 — Budget du LLM et page d'état du pont
- **Description** : plafond de jetons par jour et par joueur (option du pont et option sandbox), fichier `bridge-status.json` (demandes, erreurs par code, latence p50/p95, jetons du jour) affiché dans la fenêtre d'administration en jeu.
- **Intérêt joueur** : l'hébergeur maîtrise sa facture.
- **Faisabilité moteur** : `token_usage.jsonl` existe déjà ; lecture par le serveur via le dossier d'échange.
- **Impact MP** : serveur et admin seulement.
- **Dépendances** : C03, C10, C14.
- **Coût LLM** : en baisse.
- **Effort** : M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I21 — Modèle selon le type de demande et secours local
- **Description** :
  - `OPENAI_MODEL_SMALL` pour les initiatives, les conversations entre PNJ et les appels spontanés ;
  - le modèle principal pour les dialogues et le commerce ;
  - un modèle local (Ollama, llama.cpp via `OPENAI_BASE_URL`) en secours si le fournisseur répond 5xx ou ne répond pas.
- **Intérêt joueur** : coût moindre, moins de silences.
- **Faisabilité moteur** : côté pont uniquement.
- **Impact MP** : aucun.
- **Dépendances** : C12.
- **Coût LLM** : en baisse.
- **Effort** : S à M.
- **Avancement : ⬜ pas commencé (proposée).**

#### I22 — Prompts compatibles avec le cache de préfixe
- **Description** : partie fixe du prompt (fiche, consignes d'actions) en tête, parties variables (date, mémoire, mission, situation) à la fin, pour profiter du cache automatique des API compatibles OpenAI.
- **Intérêt joueur** : latence et coût.
- **Faisabilité moteur** : pont ; aujourd'hui la situation est ajoutée à la fin du prompt système (`radio_bridge.py:586-594`), mais les souvenirs et l'état sont intercalés selon le mode : à mesurer.
- **Impact MP** : aucun.
- **Dépendances** : aucune.
- **Coût LLM** : en baisse.
- **Effort** : S.
- **Avancement : ⬜ pas commencé (proposée).**

#### I23 — Profils de réglages en un clic
- **Description** : dans la fenêtre d'administration, profils « monde calme », « Knox hostile », « économe en LLM » qui règlent ensemble les options du mod (47 options sandbox).
- **Intérêt joueur** : prise en main pour un hébergeur.
- **Faisabilité moteur** : les mods ne peuvent pas fournir de préréglages vanilla (`quest-building-blocks.md`) et une option changée en cours de partie n'est pas persistée en solo (`load-warnings.md`). Plus sûr : un profil documenté à coller dans `SandboxVars` à la création de la partie, ou un réglage côté pont pour le profil LLM.
- **Impact MP** : admin.
- **Dépendances** : aucune.
- **Coût LLM** : nul.
- **Effort** : S (documentation) / M (en jeu, à vérifier).
- **Avancement : ⬜ pas commencé (proposée).**

#### I24 — Rejeu d'une conversation pour le diagnostic
- **Description** : depuis le journal admin des actions (E07-T02), rejouer une demande enregistrée contre le faux LLM ou un autre modèle, et comparer l'action proposée et l'action acceptée.
- **Intérêt joueur** : indirect (bogues de voix corrigés plus vite).
- **Faisabilité moteur** : demandes déjà journalisées en debug (E05-T13).
- **Impact MP** : outil hors jeu.
- **Dépendances** : C11 (masquage des secrets).
- **Coût LLM** : à la demande.
- **Effort** : S.
- **Avancement : ⬜ pas commencé (proposée).**

#### I25 — Banc d'injection rejoué en `--offline`
- **Description** : corpus de textes hostiles (faux tags, demandes de secrets, ordres d'actions hors liste, noms de personnage piégés), rejoué contre un faux LLM qui « obéit ». Le banc vérifie que le pont et le serveur bornent tout.
- **Intérêt joueur** : serveurs publics plus sûrs.
- **Faisabilité moteur** : `test_fake_llm.py` existe.
- **Impact MP** : aucun.
- **Dépendances** : C01, C02.
- **Coût LLM** : nul.
- **Effort** : S.
- **Avancement : ⬜ pas commencé (proposée).**

---

## Partie 3 — Priorisation : les 5 actions les plus rentables

Avancement au 2026-10-23 indiqué devant chaque action.

1. ✅ **Fermer les injections et le coût non borné du pont (C01, C02, C03, C10)**. Quatre corrections de taille S, à faire avant toute publication publique (E16-T05) : nom de personnage et radio bornés, tags d'appelant neutralisés, `max_tokens` gardé au repli, plafond de prompt. Le banc I25 les verrouille. *(Fait, non publié : E16-T06 et E16-T07 ; banc I25 à faire.)*
2. ⬜ **Pont qui ne meurt plus (C04, C05, C06)**. Boucle `run` protégée, verrou libéré pendant les réessais, journaux corrompus mis de côté. Cela supprime la cause la plus probable de « les voix se taisent » chez un hébergeur Windows, et rejoint le « Reste » de E16-T03.
3. 🟡 **Sauver l'état RadioSurvivor de la croissance et du blocage (C17, C18, C19, C20)**. Purger les personnages morts, contrôler à l'encodage les limites du décodeur, ajouter une migration de schéma, réessayer une écriture ratée. Puis appliquer à `RS_State` le codec rapide et l'écriture regroupée déjà prouvés dans `LK_Store` (LK13-T06/T10). C'est le seul risque de perte de données durable relevé. *(C17, C18, C19 faits, C20 en partie : écriture regroupée à faire ; E16-T08.)*
4. ⬜ **Intégration continue et luacheck des globales (C37, C36)**. Une demi-journée pour faire tourner les ~140 étapes à chaque commit du dépôt public, puis la liste blanche des globales.
5. 🟡 **Limiter le débit et les textes reçus des clients (C21, C22, C31, puis C30)**. Un répartiteur de commandes unique, avec seau à jetons par compte, et une troncature avant tout motif. Cela ferme les gels de serveur provoqués par un client modifié. Ensuite, mesurer et mettre en cache `Bodies.find` dans la campagne LK13-T02/T04. *(C21, C22, C30 faits, C31 en partie : répartiteur unique à faire ; mesure `LK_Load` à faire ; E16-T09.)*

Côté fonctionnalités, le meilleur rapport intérêt/effort : ⬜ **I02** (réception dégradée, S, sans LLM), ⬜ **I11** (résumé hebdomadaire, S, peu de LLM), ⬜ **I08** (recopier une page, M, fort en MP), puis ⬜ **I01** (radiogoniométrie, M) : aucune n'est commencée.

---

*Document de proposition mis à jour au fil des corrections : l'état de chaque point est dans le tableau de bord en tête. Les points encore à faire attendent la validation explicite de l'utilisateur avant tout code ; chaque point retenu devient une tâche du plan (`docs/annexes/plans/`, comme E11-T20 et E16-T06 à E16-T10), avec ses décisions à poser une à une.*
