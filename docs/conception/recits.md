# Récits des groupes

- Tâches : LK10-T01 (gabarits et combineur) ; LK10-T03 (point d'enrichissement, 2026-10-12) ; servira LK10-T02 (journal), LK10-T04 (traces en jeu), LK08-T05 (création des groupes)
- Build : 42.21.0 — Date : 2026-10-10 — Statut : brouillon

Code : gabarits `media/lua/shared/LivingKnox/Data/Stories.lua` (`LivingKnox.StoryData`, données seules), combineur `media/lua/server/LivingKnox/LK_Stories.lua` (`LivingKnox.Stories`, autorité seulement). Banc : `tests/test_lk_stories.py` (`--sample` affiche trois histoires par type).

## Problème

Chaque groupe (colons, pillards, neutres, ou type ajouté par données) reçoit une histoire courte et stable : d'où il vient, ce qu'il veut, qui le mène, comment il se conduit, et quelques secrets que les joueurs ne doivent pas lire directement. Le serveur la compose sans LLM, de façon reproductible, en anglais et en français ; le LLM pourra la compléter plus tard (LK10-T03).

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Sur un serveur MP, les traductions des mods ne sont pas chargées : `getText` rend la clé. | base `api-42-21.md` (`Translator.loadFiles` avant `loadMods`) ; `multiplayer.md` (liste MP, texte serveur en clé brute) | confirmé statiquement |
| Traductions 42.21 en `.json` seulement, routées par préfixe de clé ; aucun repli sauf l'anglais. | base `api-42-21.md` | confirmé statiquement |
| Un littéral non ASCII d'un `.lua` devient U+FFFD dans Kahlua ; les échappements d'octets UTF-8 (`\195\169`) donnent le bon caractère, compté pour une unité UTF-16. | base `kahlua-lua.md` (« Littéraux non ASCII ») | reproduit dans la VM Kahlua |
| `%` de Kahlua faux au-delà d'un quotient de 2^31 ; pas d'opérateurs binaires. | base `kahlua-lua.md` | confirmé statiquement |
| Un client MP charge aussi `media/lua/server` : garde `isClient()` en tête. Les fichiers `media/lua/shared` sont exécutés partout. | base `mod-loading.md` | confirmé statiquement |
| Aucune ModData globale pour un état privé (lisible par tout client). | base `multiplayer.md` | confirmé statiquement |

## Choix (2026-10-10)

### Langue : le serveur compose les deux langues

Le texte français et le texte anglais sont **dans les données Lua** (`en`, `fr`, `frF`), pas dans les `.json` de traduction. `Stories.compose` rend chaque élément et le résumé dans les deux langues ; le consommateur choisit par `Stories.text(story, lang)` (`"FR"`/`"fr"` → français, toute autre langue → anglais, comme `RS_Client` qui ne distingue que FR et EN).

Raisons :

- **Correct en MP sans aller-retour** : le serveur ne peut pas traduire (`getText` rend la clé). Les consommateurs prévus sont côté serveur : champ `story` du registre des groupes, journal (LK10-T02), contexte envoyé au LLM par le pont (LK10-T03), documents posés dans le foyer ou sur le chef (LK10-T04, créés par l'autorité). Avec des clés, chacun devrait transporter clés et paramètres jusqu'au client et les rendre là, et le LLM recevrait des clés.
- **Simple** : une histoire composée est un texte, sans grammaire répartie entre plusieurs clés et paramètres ; l'accord au féminin du passé du chef se règle dans la donnée (`frF`).
- **Coût accepté** : seulement deux langues (celles du mod : `Translate/EN`, `Translate/FR`), et les accents s'écrivent en échappements d'octets dans le `.lua`. Une troisième langue demanderait un champ de plus par fragment.
- **Régénérable** : `compose` est déterministe ; stocker le type et la graine suffit pour recomposer l'histoire, dans les deux langues, sans enregistrer les textes.

Le champ `story` de `LK_Groups` (une chaîne de 600 caractères au plus) recevra `story.summary.en` ou `.fr` selon le choix de la tâche qui crée les groupes (LK08-T05) ; ce n'est pas tranché ici.

### Structure

`Stories.compose(groupType, seed, opts) -> story` ou `nil, raison` :

```
story = { format = 1, type, seed,
          origin = { id, en, fr }, motivation = { id, en, fr }, tone = { id, en, fr },
          leader = { name, female, past = { id, en, fr } },  -- fr accordé au sexe du chef
          summary = { en, fr },                              -- <= 600 octets chacun
          secrets = { { id, en, fr, private = true }, ... } } -- PRIVÉ
```

- `seed` : entier (|seed| ≤ 2^50) ou chaîne non vide (par exemple l'identifiant `grp-<n>`). Tirage Park-Miller suivi d'un mélange modulo 65521 (même méthode que `LK_Appearance`, sans opérateurs binaires), salé par le type : même graine, types différents → histoires différentes.
- `opts` : `leaderName` (1..32 octets, sinon tiré parmi des prénoms et des noms de personnages de The Walking Dead, Z Nation, Black Summer et La Nuit des morts-vivants de 1968 et 1990, tirés séparément), `female` (sinon tiré), `secrets` (1..3, 2 par défaut). Les tirages se font toujours dans le même ordre : donner un nom ne décale pas l'origine ni le ton.
- Résumé : « origine. motivation. Leur chef est <nom>, <passé>. ton. » Le pire cas (plus longs fragments, nom de 32 octets) tient en 559 octets en français ; au-delà de 600 (données modifiées), le ton puis la motivation sont retirés, puis le texte est coupé, avec un avertissement au journal.

### Compatibilité des fragments

Chaque fragment porte `types` (types de groupe permis ; absent = tous), `tags`, `excludes` (étiquettes incompatibles, vérifiées dans les deux sens contre tout fragment déjà choisi) et `requires` (au moins une de ces étiquettes doit déjà être tirée). Ordre du tirage : origine, motivation, ton, passé du chef, secrets (sans remise). Exemples :

- ton `peaceful` exclut `violent` et `power` (pas de pillage, de péage ni de prise de ville) ; `devout` exclut `violent` et `plunder` ; `wary` (« méfiants mais justes ») exclut `plunder` ; `desperate` exclut `power` et `hoard` ; `ruthless` exclut `peaceful`, `care`, `faith` ;
- pillards : ni ton pacifique, pieux ou endeuillé, ni motivation d'accueil, de culture ou d'attente de l'armée ; colons : aucun fragment violent ;
- secrets par type (dette envers une bande, faux appel de détresse, otage : pillards ; puits gâté, malade chassé : colons ; carburant coupé d'eau : neutres) ; `deserters` exige une étiquette `military`, `watered_fuel` une étiquette `trade`, `chained_dead` une étiquette `faith` ;
- aucun fragment ne suppose de véhicule ni d'objet que le mod devrait poser au campement (relecture du 2026-10-10 : origines `bikers` et `truck_stop` remplacées par `bar_regulars` et `flea_market`, étiquettes `road` et `convoy` retirées, passés `mechanic` et `trucker` sans camion).

Un type ajouté par données (registre `LivingKnox.GroupTypes`, LK08-T02) sans fragment propre utilise les fragments sans `types` ; `Stories.checkData()` vérifie que chaque type du registre a au moins un fragment par catégorie et trois secrets sans condition.

### Contenu

24 origines (13 possibles pour les colons, 12 pour les pillards, 16 pour les neutres), 15 motivations, 9 tons, 14 passés de chef, 17 secrets, répartis par type ; Knox Country, juillet 1993, quelques semaines après le début de l'épidémie (Muldraugh, West Point, Riverside, Rosewood, Louisville derrière le cordon, Garde nationale, guerre du Golfe « il y a deux ans »). Aucun texte repris de Bandits! ni d'A-Life.

#Origines répétées (LK10-T05, décision du 2026-10-10) : avec 6 à 9 origines par type, 47 % des populations de 4 groupes en partageaient une (mesure sur 1 000 mondes, tirage uniforme sans biais). Le tirage est inchangé ; 12 origines et 3 motivations ont été ajoutées (lieux génériques ou vérifiés, aucun véhicule ni objet à poser). Nouvelle mesure sur 1 000 mondes : 25,8 % (258 observées, 259,4 attendues) ; 25,5 % sur 4 000 mondes.

## Secrets privés

- Marqués `private = true` un par un, et `Stories.PRIVATE_FIELDS = { "secrets" }`.
- **Jamais** envoyés aux clients, journalisés, ni écrits en ModData globale. Tout ce qui sort du serveur (commande réseau, ModData, journal, pont vers le LLM pour un texte public) passe par `Stories.publicView(story)`, copie profonde sans les champs privés.
- Les **gabarits** de secrets sont dans `media/lua/shared` (lisibles par tout joueur, comme tout fichier du mod) ; seul le **tirage** d'un groupe est privé, et il n'existe que sur l'autorité.

## Alternatives écartées

- **Clés de traduction + paramètres, rendus par le client** : correct en MP mais impose de transporter clés et paramètres jusqu'au client pour chaque usage, laisse le serveur, le journal et le LLM sans texte lisible, et répartit la grammaire (accords, ordre des mots) entre des clés. Plus lourd pour deux langues.
- **`Translator.loadFiles()` sur le serveur** (base `api-42-21.md`) : rendrait `getText` utilisable côté serveur, mais dans la seule langue du processus serveur ; un client dans l'autre langue recevrait la mauvaise.
- **Textes en clair (UTF-8) dans le `.lua`** : corrompus par le lexeur de Kahlua.
- **Histoire entièrement écrite par le LLM** : écartée ; LK10-T03 permet seulement de remplacer ou compléter le résumé public, le gabarit reste le repli sans RadioSurvivor.

## Enrichissement par un autre mod (LK10-T03, 2026-10-12)

Code : `LK_API.lua` (`API.story`, `API.enrichStory`, `API.STORY`), contrat dans [api.md](../api.md), section « Histoires
enrichies ». Banc : `tests/test_lk_api.py`, classe `StoryEnrichTests`.

- **Point d'entrée passif** : le moteur expose une lecture (`API.story`) et une écriture (`API.enrichStory`) ; il ne
  connaît pas RadioSurvivor et ne l'appelle jamais. Sans lui : aucun texte enregistré, lecture du gabarit, aucune
  erreur (banc chargé sans aucun fichier du carnet).
- **Ce qui se remplace** : le résumé public seulement, par langue (`en`, `fr`) et par cible (le groupe, ou un membre
  `m-<k>`). Origine, motivation, chef, ton et **secrets** ne sont ni lus ni modifiés ; `summary` de `listGroups` et
  `getGroup` (champ `story` du registre) garde son sens.
- **Contrôle serveur** : 600 caractères, 8 lignes, blancs de tête et de fin retirés, aucun caractère de contrôle sauf
  `
`, ni `<` ni `>` (balises de texte riche). Le serveur ne juge pas le contenu (aucune liste de mots) : il vérifie
  la forme et la version.
- **Version du gabarit** : empreinte du type, de la graine et des deux résumés composés (`t1-<graine>-<empreinte>`),
  gardée avec chaque texte. Graine, type ou gabarits changés : texte périmé, repli sur le gabarit, entrée retirée à
  l'écriture suivante. L'écrivain peut passer la version lue pour refuser une réponse arrivée après un changement.
- **Membre** : texte propre, sinon celui du groupe, sinon le gabarit ; `append` complète le texte de base après un
  saut de ligne.
- **Stockage** : `group.enrich` dans le registre privé des groupes (fichier serveur, jamais en ModData), au plus
  66 entrées ; le texte n'est jamais journalisé.

Décisions à confirmer (choix les plus simples, pris sans arbitrage) : bornes 600 / 8 lignes ; refus de `<` et `>` ;
membre qui hérite du texte du groupe ; un texte par langue (pas de traduction côté serveur) ; `summary` des vues
inchangé (le consommateur lit `API.story`).

## Idées reprises

- Aucune.

## Tests

- Banc lupa (`tests/test_lk_stories.py`, 14 tests) : données valides (`checkData`, effectifs minimaux dont 12 origines possibles par type, fragments propres à chaque type, registre LK08-T02 chargé comme en jeu), sources ASCII hors commentaires, textes propres (pas d'U+FFFD, majuscule et point final, appositions en minuscule, forme féminine présente), pire cas du résumé ≤ 600 octets par type et par langue ; cent tirages (graines 1..100) par type avec les règles revérifiées en Python à partir des données (types, exclusions dans les deux sens, conditions, secrets distincts, incohérences nommées), variété (≥ 95 résumés distincts, toutes les origines du type tirées) ; contrôle non complaisant (règle cassée → détectée) ; déterminisme (deux VM, mêmes résultats) ; options et erreurs ; type sans fragment propre ; choix de la langue ; secrets privés retirés par `publicView` (copie profonde, original intact) ; garde `isClient()` sur un client MP.
- VM Kahlua (`tests/test_kahlua.py`) : non couvert par cette tâche (fichier tenu par une autre tâche en cours) ; à ajouter : longueurs en unités UTF-16 et tirage identique à lupa.
- En jeu : sans objet (hors jeu).

## Points ouverts

- ⚠ Relecture des textes par l'utilisateur (échantillon fourni avec LK10-T01).
- ⚠ Graine en chaîne non ASCII : `string.byte` lit des octets sous lupa et des unités UTF-16 en Kahlua, donc un tirage différent ; employer une graine numérique ou ASCII (`grp-<n>`).
- Tranché par LK08-T05 ([groupes.md](groupes.md), section « Population ») : `story` = `summary.en`, plus `storySeed` qui recompose toute l'histoire (français et secrets compris) par `Stories.compose(type, storySeed)` côté autorité ; les secrets ne sont jamais stockés.
- ⚠ Prononcé au masculin en anglais pour quelques passés (« foreman ») ; pas de forme féminine anglaise prévue.
