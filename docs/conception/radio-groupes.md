# Radio des groupes équipés

- Tâche : E08-T06 (décision Q1 du 2026-10-10 : option A, radio du groupe)
- Build : 42.21.0 — Date : 2026-10-13 — Statut : brouillon (banc hors jeu seulement)

Code : `media/lua/server/RadioSurvivor/RS_GroupRadio.lua` (autorité) ; voix engendrées `RS_Personas.setGenerated` ; routage dans `RadioSurvivor_Server.lua` (`onTalk`, `hasPending`, `onTickEvenPaused`) ; file et réponse dans `RS_Carnet_Server.lua` (`reply` délègue les demandes radio) ; fournisseur `Provider.radios` (`RS_NPCProvider.lua`, implémenté par `RS_LivingKnox.lua`) ; types au format 2 (`LK_GroupTypes.lua`, [groupes.md](groupes.md) « Format 2 »). Tests : `tests/test_group_radio.py` ; suite en jeu `rs.groupradio` (`dev/.../shared/RST/suites/RS_GroupRadio.lua`).

## Règle

1. **Équipé** : un groupe non disparu (`gone` absent) dont un membre vivant peut utiliser un poste maintenant : type au format 2 avec `homeRadio` et foyer connu, membre hors expédition (`expedition.team`, `trips.cur`) ; ou profil `radio = true` (talkie porté, même en expédition). Aucun membre vivant, tous au loin, groupe décimé ou disparu : pas équipé.
2. **Voix engendrée** : une fiche par groupe équipé, identifiant `grp_<n>` (du groupe `grp-<n>`), nom = nom du groupe, `frequency_range=75.0-149.8` (tous les postes émetteurs vanilla, comme Walt), `call_one_in=0` (aucun appel spontané), jamais écrite dans le dossier des fiches. Même tirage qu'E05-T07 (fréquence libre, à 1 MHz au moins des autres voix, mémorisée dans le fichier de la partie, gardée si le groupe redevient équipé), même chaîne sans source physique (aucune position dans le paquet, nom retiré), même tri par le serveur (E05-T08). Relu toutes les 30 s réelles : un groupe qui perd son poste perd sa chaîne.
3. **Appel** : une phrase dite sur la fréquence passe les contrôles communs (radio d'E06-T03, anti-spam, attente, délai, plafond radio), puis devient une demande `npc_talk` du **PNJ qui répond** (le chef s'il atteint un poste, sinon le plus ancien qui le peut) dans la **file ordonnée du carnet**, sous ses quotas (délai par personnage 10 s, `MAX_PER_HOUR`, `MAX_PENDING`). Fiche et contact créés comme au premier mot de vive voix ; même mémoire du pont que la proximité. Refus là-bas (personnage sans carnet, quotas, groupe plus équipé) : silence, comme une voix muette.
4. **Contexte** : celui de la proximité (nom, biographie, confiance, groupe public du fournisseur, stade d'E17-T08 : un inconnu n'apprend ni le groupe, ni son chef, ni son histoire), plus `radio.note` (consigne anglaise : pas de lieu ni de coordonnée, aucune offre par radio), **aucune offre**, ni acceptation, ni accord, ni départ.
5. **Réponse** : intention `none` et `offer` vide seulement (sinon refusée : parasites et `NoAnswer`) ; groupe encore équipé, PNJ encore dans ce groupe, fréquence encore à cette voix. Toute suite de 4 chiffres ou plus est remplacée par `...`, puis la réplique part sur la chaîne (lignes de 140 caractères, parasite en tête), l'historique du carnet de l'appelant la garde, l'échange compte pour la connaissance (E17-T08), l'appelant reçoit `done`.
6. **Sans réponse** (pont muet, délai du carnet, refus) : parasites sur la fréquence et refus `NoAnswer`.

## Pillards équipés (E08-T10, 2026-10-15)

Décision de l'utilisateur du 2026-10-14 (E08-T06) : colons **et** pillards ont une radio. `LK_Type_raiders.lua` passe au format 2 avec `homeRadio = true`, sans autre changement : mêmes règles que ci-dessus (voix `grp_<n>`, plage 75,0-149,8 MHz, aucune décision par radio, règle de l'inconnu, masquage des nombres, `CallLanguage`, identité de carnet exigée). Le poste est au camp (`g.home`) : un groupe de pillards sans foyer (créé sans `home`) n'est pas équipé ; tous ses membres au loin (raid, expédition) : pas de voix jusqu'au retour. Les neutres restent sans radio (format 1). Bancs : `tests/test_group_radio.py` (types, camp de pillards = voix et chef qui répond, neutres sans voix, colons inchangés, réplique sans lieu, décision refusée, silence décimé ou dispersé, test en jeu rejoué sur le banc) ; en jeu : `rs.groupradio`, « a raiders camp is a voice, a neutrals group is none (E08-T10) » (groupes de test créés à 400 cases du joueur, sans corps, retirés ensuite).

## Découpe des répliques (E17-T12, 2026-10-13)

Constat en jeu : une réplique longue venue du pont arrivait coupée au milieu d'une phrase, la suite seulement à la
ligne suivante. Cause : le récepteur affiche chaque `RadioLine` d'une diffusion seule, l'une après l'autre (durée
vanilla selon la longueur : `RadioChannel.java:229-237`, longueur / 10 s bornée à 1,5-5 s, déjà adaptée) ; or
`RS_GroupRadio.lines` coupait au dernier espace avant 140 caractères, sans regarder la ponctuation, et le pont
(`radio_bridge.radio_lines`, voix radio comme Walt) coupait entre deux mots toute phrase de plus de 100 caractères.
La bulle de proximité d'un PNJ (`LK_SpeechView.show`) n'est jamais découpée : une réplique = une bulle, ses lignes
de 60 caractères affichées ensemble.

Règle (`shared/RadioSurvivor/RS_TextCut.lua` `pieces`, miroir Python `radio_bridge.cut_pieces`) : chaque morceau, au plus
la longueur actuelle (140 en jeu, 100 au pont), le plus long possible, coupé :

1. après une fin de phrase : `.` `!` `?` ou `…` (U+2026), éventuellement suivis de `"` `'` `)` `»`, puis d'un espace
   (« 9.5 » n'en est pas une : point suivi d'un chiffre) ;
2. sinon après `,` `;` ou `:` suivis d'un espace ;
3. sinon entre deux mots (devant une ponctuation détachée à la française, `?` `!` `:` `;` `»` `…`, seulement à défaut
   d'autre espace) ;
4. sinon (un seul mot plus long que la ligne) à la longueur, jamais au milieu d'un caractère.

Ponctuation lue caractère par caractère, aucune liste de mots ni règle de langue. Longueur : `string.len`, en unités
UTF-16 dans le jeu (base `kahlua-lua.md`), en caractères au pont ; même découpe des deux côtés vérifiée dans la VM
Kahlua réelle (`tests/test_kahlua.py`). « M. Dupont » compte comme une fin de phrase (point suivi d'un espace) :
limite admise, sans liste d'abréviations. Bancs : `tests/test_text_cut.py` ; en jeu : `rs.groupradio`.

## Décisions à confirmer (prises la nuit du 2026-10-13, utilisateur absent)

- Format 2 : champs `homeRadio` (type) et `radio` (profil), booléens ; types `settlers` et, depuis E08-T10 (décision de l'utilisateur du 2026-10-14), `raiders` dotés d'un poste au foyer (camp en forêt pour les pillards) ; neutres et solitaires sans radio.
- Plage des voix de groupe : 75,0-149,8 MHz (tous les talkies et postes HAM).
- Par radio, **aucune décision** (offre, acceptation, accord, départ) : tout se fait de vive voix ; le contenu des missions comporte des lieux.
- La règle de l'inconnu d'E17-T08 s'applique aussi par radio : un inconnu n'entend ni le nom du groupe ni son histoire (le texte d'E08-T06 cite nom, histoire et état comme contenu de la voix : ils sont donnés au stade `acquainted`).
- Masquage des suites de 4 chiffres ou plus dans les répliques (une année « 1993 » est masquée aussi).
- Langue de la demande : option `CallLanguage`, sinon langue de l'autorité (le client radio n'envoie pas sa langue).
- L'appelant doit avoir une identité de carnet (envoyée au début de partie par le client) ; sinon silence.
