# Dernières pages d'un personnage (E15-T03)

À la mort d'un personnage du carnet, son journal est écrit d'après son relevé de vie (E15-T01) et posé, en document manuscrit en lecture seule, dans son cadavre ou à côté (méthode établie en E15-T02, `docs/derniers-pages-cadavre.md`). Code : `media/lua/server/RadioSurvivor/RS_LastPages.lua` ; pont : `bridge/last_pages.py` (branchements dans `bridge/radio_bridge.py`), liste `RS_Transport.lastPages` ; banc : `tests/test_last_pages.py` ; suite en jeu : `rs.lastpages` (`dev/batman_RadioSurvivorTests/.../suites/RS_LastPages.lua`).

## Déroulement

1. **Mort** (`OnCharacterDeath` sur l'autorité → `RS_LifeLog.characterDeath` → écouteur `LifeLog.onFrozen`, avant la création du cadavre) : jeton `lp-<n>-<ms>` posé dans la ModData du joueur (recopiée sur le cadavre, `IsoDeadBody.java:378`), case de la mort et état « en feu » notés dans le relevé figé (état privé `RS_State`), métier lu en nom affiché (`CharacterProfessionDefinition…:getUIName()`, comme `ISCharacterScreen.loadProfession`), puis **une** demande `kind=last_pages` au pont.
2. **Texte** : réponse du pont `{kind = last_pages_reply, text}`, nettoyée et bornée de nouveau par le serveur (2 400 caractères, sauts de ligne gardés, ni contrôle ni `< > [ ]`). Sinon **journal de secours** composé par le serveur avec les mêmes faits : réponse d'erreur (`invalid_or_unavailable`, `expired`), aucune réponse après `TIMEOUT_MS` (90 s), ou demande perdue par un redémarrage du serveur.
3. **Pose** (au plus tôt `DELAY_MS` = 3 s après la mort, case de la mort chargée sur l'autorité) : dans le cadavre qui porte le jeton à 2 cases au plus (`AddItem` + `sendAddItemToContainer` sur un serveur), sinon au sol de la case de la mort (`AddWorldInventoryItem(…, true)`). Mort en feu : toujours au sol (le cadavre brûle avec son contenu). Case non chargée : nouvel essai à chaque passage (toutes les 2 s).
4. **Une seule fois** : le relevé figé est libéré (`LifeLog.release`) et l'état sauvegardé **avant** la pose ; un arrêt entre les deux perd le document plutôt que de le doubler.

## Demande au pont (`kind=last_pages`)

Ligne `req=`, `kind=last_pages`, `payload=` (RSV2 hexadécimal, comme les demandes des PNJ), contenu : `id`, `kind`, `sent`, `language` (option `CallLanguage`, sinon langue de l'autorité, comme les appels spontanés), `name` (nom du personnage), `facts` = heures de survie, zombies tués, métier affiché, heure de la mort, villes, dernières phrases dites à la radio, missions closes (gabarit, issue, demandeur, type de lieu), missions encore ouvertes à la mort, secours, totaux. **Jamais** de coordonnée, de fréquence, de compte ni le jeton. Le pont refuse une charge mal formée (listes au-delà de 16, textes trop longs, issue de secours inconnue…).

Prompt (`last_pages.prompt`) : journal intime à la première personne, quelques paragraphes, 250 mots au plus ; **faits seuls**, rien d'inventé ; jamais la description de sa mort ; une mission n'est accomplie que si les faits le disent, une mission ouverte n'a jamais été finie ; ni coordonnée, ni fréquence. Aucune liste de mots ne lit le texte : le serveur ne contrôle que sa forme.

## Document

`Base.Notebook` vanilla (`CanBeWrite`, 10 pages) : pages écrites par `addPage` puis `setLockedBy("RadioSurvivor")` (tout lecteur n'a que « Lire »), nom personnalisé « Dernières pages de <nom> » (`setName` + `setCustomName`), ModData `RS_LastPagesToken`. Première page : titre « Les dernières pages de <nom> », puis le texte. Mise en pages : lignes de 40 caractères au plus coupées aux espaces, 15 lignes par page, 10 pages au plus (texte coupé, « ... » en fin). Textes du serveur : clés `IGUI_RS_LastPages_*` (EN, FR), traductions du mod rechargées une fois sur un serveur MP (`Translator.loadFiles`), textes anglais intégrés si elles manquent encore. Le texte est figé dans la langue de l'autorité au moment de la mort.

## Option sandbox `RadioSurvivor.LastPages` (E15-T04)

Booléen, **activé par défaut**, page « Radio Survivor » (`media/sandbox-options.txt`, traductions `Sandbox_RadioSurvivor_LastPages[_tooltip]` EN et FR). Lu par `Const.lastPages()` (`RadioSurvivor_Const.lua`) à chaque passage, option enregistrée d'abord puis `SandboxVars` puis défaut, comme les autres options du mod : une coupure en cours de partie est prise au passage suivant (2 s pour les pages, 15 s pour le relevé). Autorité seulement.

Désactivée :
- `RS_LifeLog` : le sondage ne relève plus rien et **efface tous les relevés conservés** (vivants et figés) ; une mort ne fige rien, donc aucun `onFrozen`, aucun jeton, aucune demande ; `LifeLog.rescue` refuse.
- `RS_LastPages` : chaque demande en attente est retirée du fichier du pont, les relevés figés sont libérés **sans document**, même si le texte était déjà prêt (case de la mort non chargée) ; `onFrozen` ne fait rien.
- Réactivée : les relevés repartent de zéro au sondage suivant (tués et heures relus sur le joueur ; villes, missions déjà élaguées et secours d'avant la coupure perdus). Une mort survenue pendant la coupure n'a jamais de document.

Décisions à confirmer (E15-T04) : effacement des relevés plutôt que mise en pause ; morts en attente abandonnées à la coupure ; option indépendante de `RadioSurvivor.Enabled`.

## Décisions à confirmer

- Objet : `Base.Notebook` vanilla (aucun objet de mod) ; « écriture manuscrite » = fenêtre vanilla du carnet (police d'interface), pas de police manuscrite `printMedia` : un document `CanBeWrite` s'ouvre dans la fenêtre d'écriture.
- Délai du pont 90 s, puis journal de secours ; pose au plus tôt 3 s après la mort ; recherche du cadavre à 2 cases.
- Demande perdue par un redémarrage : journal de secours aussitôt (pas de nouvel envoi).
- Langue : celle des appels spontanés (`CallLanguage`, sinon l'autorité).
- Nom de verrou `RadioSurvivor` ; nom de l'objet traduit côté serveur.

## Limites

- Rien n'a été mesuré en jeu ; le banc vérifie la logique avec des doublures (ordre du Java 42.21.0 établi en E15-T02).
- Le texte du LLM n'est contrôlé que dans sa forme ; la fidélité aux faits repose sur le prompt (le journal de secours, lui, n'emploie que les faits).
- Joueur relevé en zombie : son inventaire suit le zombie, le cadavre marqué n'existe pas → document au sol.
- Relevés figés avant cette tâche (sans `pages`) : laissés tels quels, oubliés par la borne `MAX_FROZEN`.
- Métier d'un autre mod sur un serveur MP : `getUIName()` peut rendre sa clé brute (traduit à la création de la définition, base `api-42-21.md`).
- Largeur de ligne (40) et rendu de la fenêtre du carnet à vérifier en jeu.

## Protocole d'essai en jeu

Nominal, serveur dédié (ou solo) avec le pont lancé, sauvegarde `rstest*` :

1. Suite automatique : `RST.server({ suite = "rs.lastpages", tags = "world" })` (solo : `RST.run({ suite = "rs.lastpages", tags = "world" })`) → 5 PASS (dont l’option `RadioSurvivor.LastPages`, E15-T04).
2. Joueur A : ouvrir le carnet (identité liée), tuer quelques zombies, parler à la radio, puis mourir (pas en feu). Console serveur : `lifelog: frozen …`, puis `last pages: text of … ready (bridge)` et `last pages: document of … placed in the corpse (bridge)`.
3. B ouvre le cadavre de A : carnet « Last pages of A » (ou « Dernières pages de A »), « Lire » seulement, texte du journal. A le voit aussi après réapparition ; déconnexion/reconnexion de B : toujours là, une seule fois.
4. Pont arrêté : refaire 2–3 ; après 90 s, `… ready (fallback)` et journal de secours (heures, zombies, villes, dernières phrases).
