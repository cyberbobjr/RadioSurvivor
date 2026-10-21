# E05 — Validation du réseau de voix (E05-T06)

- **Statut** : à jouer (solo, puis multijoueur). Rien de ce protocole n'a encore été exécuté en jeu.
- **Jeu** : Project Zomboid 42.21 (relever la version exacte en tête de `console.txt` et du journal du serveur).
- **Déjà prêt** : suites `rs.voices` (lecture seule) et `rs.voices.world` (phrases simulées, fiche modifiée puis
  restaurée), décrites dans l'en-tête de `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RS_Voices.lua`.
  `rs.voices` est déjà passée sur le serveur dédié de test du 2026-10-09 (5/5 PASS, voir § 5).
- **Ne recopie pas** les essais détaillés de [tests-en-jeu.md § 13](../tests-en-jeu.md) : il y renvoie
  (« Manuel », « Routage par voix », « Le serveur trie », « Appels spontanés », « Notes de fréquences »).
- **Ordre** : partie nominale d'abord. Les cas limites (budget, fiche invalide, mise à jour des fiches) restent
  dans le § 13.

## 0. Préparation commune

**Pont.** Depuis `%USERPROFILE%\Zomboid\Workshop\RadioSurvivor` : `python bridge/radio_bridge.py --offline`. Chaque
voix y répond « <Prénom>, hors ligne. Je reçois ... ». Pour un serveur dédié, ajouter
`--exchange <cache>\Lua\batman_RadioSurvivor`. Arrêter le pont, ou garder `--offline`, pendant les suites RST : elles
jouent elles-mêmes le pont et un pont relié au LLM répondrait aussi à leurs phrases.

**Fréquences de la partie.** Elles sont tirées à chaque nouvelle partie. Le journal donne une ligne
`[RadioSurvivor] personas: voice '<id>' drew <X> MHz in <plage>` par voix, et deux pour le Night Owl. En solo, les
notes donnent la même fréquence. Pour les obtenir, utiliser la commande de la console Lua du § 13 « Notes de
fréquences », étape 3. Le journal sert de référence.

**Radios** : console Lua solo, `getPlayer():getInventory():AddItem("Base.WalkieTalkie1")`. Pour parler, la radio doit
être émettrice, tenue en main (ou sur le dos pour le poste nomade), allumée, réglée et micro ouvert. Le clic droit
affiche alors « Parler sur X MHz ».

| Voix | Plage | Heures d'écoute | Talkie ordinaire qui la joint | Haut de gamme |
|---|---|---|---|---|
| Walt (`walt`) | 130,0-149,8 | toujours | `WalkieTalkie1` « Toys-R-Mine » (75-150) | `WalkieTalkie5` « Armée américaine », `ManPackRadio` (dos) : 0,2-1000 MHz |
| Darlene (`darlene`) | 115,0-129,8 | 07-10 h, 16-19 h | `WalkieTalkie1` | idem |
| Whitaker (`whitaker`) | 75,0-87,8 | (silencieuse) | `WalkieTalkie1` | idem |
| Night Owl (`nightowl`) | 88,0-107,8 et 109,0-114,8 | 19-22 h | `WalkieTalkie1` | idem |
| Cody (`cody`) | 10,0-24,8 | 22-03 h | `WalkieTalkie4` « tactique » seulement (10-500) | idem |
| Gus (`gus`) | 150,2-199,8 | 03-06 h | `WalkieTalkie2` « ValuTech » (50-200), 3 ou 4 | idem |

Aucune voix livrée n'exige un poste haut de gamme (`radio=any` partout). L'essai « basse ou haut de gamme » passe par
une fiche d'essai `radio=high_tier` (étape S5).

**Heure du jeu (solo).** Console : `getGameTime():setTimeOfDay(20.5)`, soit 20 h 30. Le changement s'applique tout de
suite au routage. `EveryHours`, donc un appel spontané, ne part qu'au passage de l'heure pleine suivante : laisser
tourner en vitesse ×4. En MP, l'heure est celle du serveur. On ne la règle pas : on change `listen=` dans la fiche
(étape M5).

## 1. Solo (partie `rstest-voix`)

Jeu en `-debug`, mods `batman_RadioSurvivor` et `batman_RadioSurvivorTests`, plus `batman_MilitaryDrop` s'il est
installé (collision à vérifier). Pont lancé (§ 0).

1. **Démarrage.** Créer une nouvelle partie nommée `rstest-voix`. Journal attendu : six lignes `drew` (sept
   fréquences) et sept lignes `channel of voice '<id>' created on X MHz`. Il ne doit y avoir ni `refused`,
   ni `already used`, ni `ERROR`. Avec Military Drop, sa ligne `[MilitaryDrop] radio channel on Y MHz` doit donner
   un Y différent de chaque X. Pour Gus, Walt et Darlene, la bande de Military Drop (120-170 MHz) recouvre leur plage.
2. **Suites.** Dans la console Lua :
   - `RST.server("rs.voices")` → `OK - 5 test(s)` ;
   - `RST.server({ suite = "rs.voices", tags = { "server", "world" } })` → `OK - 8 test(s)`, en 1 à 2 minutes. Ne
     pas parler à la radio et ne pas mettre en pause pendant ce temps. Les lignes `note:` donnent, pour chaque voix,
     sa fréquence, ses heures et le résultat attendu à l'heure du jeu.
3. **Notes.** Appliquer le § 13 « Notes de fréquences », étapes 3 et 4 : chaque note donne la fréquence du journal.
4. **Chaque voix sur sa fréquence**, avec le talkie ordinaire du tableau (§ 0) réglé sur la fréquence de la note.
   Régler d'abord l'heure, puis dire une phrase. Après chaque réponse, attendre 10 s, le délai entre deux messages.
   - Walt, à n'importe quelle heure → réponse.
   - Darlene à 08:00 → réponse. À 12:00 → la phrase part, rien ne revient.
   - Night Owl à 20:00, sur sa première fréquence → réponse. Puis sur la seconde (109,0-114,8) → réponse.
   - Cody à 23:00 avec `WalkieTalkie4` → réponse. Avec `WalkieTalkie1`, impossible de régler sous 75,0 : c'est
     normal.
   - Gus à 04:00 avec `WalkieTalkie2` → réponse.
   - Whitaker à 12:00 → la phrase part, aucune réponse : la voix est silencieuse.
5. **Basse et haut de gamme.** Appliquer le § 13 « Routage par voix », étapes 1 à 3. Écrire la fiche d'essai
   `essai.txt` en `radio=high_tier`, sur une fréquence absente du journal entre 75 et 150 MHz. `WalkieTalkie1` → pas
   de réponse ; `WalkieTalkie5` → réponse. Puis vider `essai.txt` (étape 5 du même essai).
6. **Rechargement d'une fiche en cours de partie.** Mettre l'heure du jeu à 12:00. Dans
   `Zomboid\Lua\batman_RadioSurvivor\personas\darlene.txt`, remplacer `listen=07:00-10:00,16:00-19:00` par
   `listen=always` et enregistrer. Dans les 30 s, le journal affiche `voice 'darlene' updated` et Darlene répond à
   12:00. Remettre la ligne d'origine : dans les 30 s, plus de réponse à 12:00. Le changement de fréquence à chaud
   se vérifie dans le § 13 « Manuel », étapes 2 à 5.
7. **Appels spontanés.** Appliquer le § 13 « Appels spontanés », étapes 1 et 2. Puis laisser tourner le jeu
   2 heures, de 03:00 à 05:00, avec deux talkies, l'un sur Gus, l'autre sur Walt : chaque appel arrive sur la
   fréquence de sa voix, une voix au plus par heure pleine, et jamais de Whitaker ni du Night Owl.
8. **Silence ailleurs.** Appliquer le § 13 « Le serveur trie », étapes 2 à 4, sur une fréquence absente du journal.

## 2. Multijoueur (serveur dédié + deux clients)

Préparer comme le § 11 « Préparer », étapes 1 et 2 : serveur `run_dedicated_smoke.ps1 -Manual`, nom
`rstest_smoke`, A = `rs_smoke_admin`, B = un nouveau compte. Relever `RS_SMOKE_CACHE=`. Lancer le pont sur le cache
du serveur (§ 0, `--exchange`). Les fiches sont dans `<cache>\Lua\batman_RadioSurvivor\personas\`.

1. **Démarrage.** Journal du serveur (`<cache>\server-console.txt`) : mêmes lignes qu'en S1. Aucun client ne doit
   recevoir de fréquence (E05-T08). Le `console.txt` de B ne cite aucune fréquence de voix.
2. **Suites**, console de A :
   - `RST.server("rs.voices")` → `OK - 5 test(s)` ;
   - `RST.server({ suite = "rs.voices", tags = { "server", "world" } })` → `OK - 8 test(s)`. Les phrases simulées
     utilisent les comptes fictifs `rstest_voices_<n>` : A et B ne sont pas bloqués.
3. **Fréquences.** Elles se lisent sur une note trouvée en jeu, ou à défaut dans le journal du serveur. Une note
   créée par la console d'un client peut rester sans fréquence (`???.?`) : la fréquence est écrite par le serveur à
   la création de l'objet. Ce cas est à noter, ce n'est pas un échec du réseau.
4. **Chaque voix.** A et B prennent un talkie (§ 0) et parlent à Walt, puis à chaque voix qui écoute à l'heure du
   serveur (heure lue dans le jeu). Attendu : réponse sur la fréquence de la voix, entendue par tout joueur réglé
   dessus. Whitaker et les voix hors de leurs heures ne répondent pas.
5. **Deux joueurs sur deux voix en même temps.** Dans `darlene.txt` du serveur, passer à `listen=always`, ce qui
   vérifie aussi le rechargement en MP. Attendre `voice 'darlene' updated` dans le journal du serveur. A se règle
   sur Walt, B sur Darlene, et ils parlent à moins de 5 s d'intervalle. Attendu :
   - A n'entend que Walt et B que Darlene ;
   - `requests.txt` contient deux demandes, `caller=rs_smoke_admin` avec `voice=walt`, et l'autre compte avec
     `voice=darlene` ;
   - le dossier d'échange contient deux historiques distincts, `history_<empreinte>.json` et
     `history_<empreinte>_darlene.json`.

   B se règle ensuite sur Walt et parle : Walt lui répond sur sa fréquence, et A et B entendent la réponse.
   Remettre `listen=` d'origine.
6. **Basse et haut de gamme.** Placer la fiche d'essai `radio=high_tier` de l'étape S5 dans le dossier du serveur.
   A, avec `WalkieTalkie5` en main, obtient une réponse. B, avec `WalkieTalkie1` sur la même fréquence, n'obtient
   aucune réponse mais entend celle de A. Vider ensuite `essai.txt`.
7. **Appels spontanés.** Dans `walt.txt` du serveur, mettre `call_one_in=1`. A et B se règlent sur Walt. À l'heure
   pleine suivante (2 min 30 réelles environ par heure de jeu), tous deux entendent le même appel, dans la langue du
   serveur : anglais pour le serveur de test, à confirmer (point E05-T05). Remettre `call_one_in=3`.
8. **Silence ailleurs.** B parle sur une fréquence sans voix : la phrase part, rien ne revient, aucune demande
   dans `requests.txt`. A, sur Walt, n'est pas gêné.

## 3. Relever dans les journaux

- **Serveur ou `console.txt` solo.** Lignes `[RadioSurvivor] personas:` : `drew`, `channel ... created`, `updated`,
  `removed`. Toute ligne `WARNING`, `ERROR`, `refused` ou `already used` est un écart. Relever aussi
  `no answer from the bridge` (pont arrêté), `call of voice ... dropped` et `[MilitaryDrop] radio channel on`.
- **Rapports RST.** Fichiers `<horodatage>-server.txt` (solo : `Zomboid\Lua\batman_RadioSurvivor\tests\` ;
  serveur : `<cache>\Lua\...\tests\`), avec les lignes `note:`.
- **Pont.** Une ligne par demande, avec la voix ; `general call of voice <id>` pour les appels.
- **`requests.txt`.** Champs `voice=` et `caller=`, jamais la fréquence.
- **Client.** Erreur Lua de `RadioSurvivor/` ou `RST/`, clé `IGUI_RadioSurvivor_…` lue telle quelle à la radio.

Écarts à signaler : une voix qui répond hors de ses heures ou sur la fréquence d'une autre, une réponse à
Whitaker, une réponse à un talkie ordinaire sur une voix `high_tier`, deux joueurs qui reçoivent la réponse de
l'autre voix, des historiques mélangés, une fréquence de voix égale à celle de Military Drop ou de l'alerte
d'urgence, une fiche de l'admin écrasée, une fréquence visible chez un client.

## 4. Résultats (à remplir)

| Étape | Solo | MP |
|---|---|---|
| Démarrage : 7 chaînes, aucune collision (dont Military Drop) | | |
| `rs.voices` (5) / `rs.voices.world` (8) | | |
| Notes = journal | | (note ou journal) |
| Chaque voix sur sa fréquence, heures respectées | | |
| Basse / haut de gamme | | |
| Rechargement d'une fiche en cours de partie | | |
| Deux joueurs sur deux voix | — | |
| Appels spontanés (langue en MP) | | |
| Silence ailleurs | | |

## 5. Déjà constaté hors jeu (2026-10-09)

- **Bancs.** `tests/test_rs_suites.py` exécute les deux suites avec le vrai moteur RST, sur le serveur simulé de
  `tests/test_personas_server.py` : six fiches livrées, routage réel de `RadioSurvivor_Server.lua`. Il couvre le
  serveur, le solo avec attente du délai et la reprise d'une sauvegarde de fiche laissée par un passage
  interrompu. Il vérifie aussi que chaque suite détecte un défaut injecté : voix mal routée, talkie ordinaire
  accepté, nom de chaîne publié, relecture inopérante. `tests/test_kahlua.py` vérifie que les deux suites se
  déclarent sans erreur dans la VM Kahlua réelle (5 et 3 tests).
- **Serveur dédié de test** (`run_dedicated_smoke.ps1 -Filters "rst,rs"`). Résultat : 53 tests, 50 PASS, 3 SKIP
  connus, aucune erreur Lua de nos mods. `rs.voices` passe 5/5 avec l'API Java réelle (chaînes du
  `RadioScriptManager`, dossier du mod, noms de chaînes). Fréquences tirées ce jour-là :

  | Voix | Fréquence(s) |
  |---|---|
  | Cody | 24,0 |
  | Darlene | 120,0 |
  | Gus | 150,8 |
  | Night Owl | 97,6 et 111,6 |
  | Walt | 142,0 |
  | Whitaker | 82,4 |

  19 autres chaînes ont été évitées. `rs.voices.world` est exclue de l'exécution automatique : il n'y a pas de
  joueur, et le serveur vide en pause ne lit pas les réponses. Elle reste à passer en solo et depuis un client.
- **Non prouvé hors jeu.** `triggerEvent("OnClientCommand", …)` avec un joueur fictif (table Lua) dans la VM du jeu,
  l'écoute réelle d'une réponse, le rendu des notes, les appels spontanés et la langue en MP.
