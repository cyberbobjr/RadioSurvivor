# ADR — Atelier des voix : créer et corriger les voix radio sans écrire de fiche

| | |
|---|---|
| Date | 2026-11-15 |
| Statut | Accepté |
| Décideur | utilisateur |
| Plan associé | [E22 — Atelier des voix](../../annexes/plans/E22-atelier-voix.md) |
| Références | Maquettes et comparaison : artefact « Atelier des voix » (https://claude.ai/artifact/GFFcsBVMpmRD6bRXphDss5) ; format des fiches `docs/specifications-techniques/persona-format.md` ; ADR [voix déclarées](adr-personas-declaratives.md) |

## Contexte

Depuis E20, une voix radio tient entière dans une fiche texte `personas/<id>.txt` : en-tête, lieux, missions,
récompenses, catégories, troc, note de fréquence et personnalité en anglais. Une fiche fait 80 à 130 lignes, une
cinquantaine de clés, des coordonnées, des noms de script d'objets et des identifiants qui se répondent d'une section à
l'autre. Une erreur fait refuser la fiche et ne se lit que dans `console.txt`. Le serveur relit le dossier de travail
`Zomboid/Lua/batman_RadioSurvivor/personas/` toutes les 30 s.

L'utilisateur veut un outil pour un adolescent qui crée des voix, des personnalités et des missions : Windows, Linux et
macOS, tout ajouter, modifier, corriger et supprimer, simple à utiliser. Quatre solutions ont été maquettées et
comparées (page web hors ligne, atelier servi par le pont, atelier dans le jeu, atelier du pont avec relevé de lieux en
jeu).

## Décisions

- **D01 — Atelier servi par le pont, relevé des lieux en jeu** (solution D, utilisateur, 2026-11-15). Le pont Python
  ouvre l'atelier dans le navigateur ; le mod ajoute seulement un clic droit qui relève un lieu. **Rester simple**
  (utilisateur) : bibliothèque standard Python, HTML et JavaScript sans framework ni étape de construction, écoute sur
  `127.0.0.1` seulement, un lanceur par système (`.bat`, `.sh`, `.command`).
- **D02 — L'atelier écrit dans le dossier de travail des fiches.** Jamais dans le dossier du mod. Le jeu relit la fiche
  en 30 s, sans redémarrage. Les règles existantes s'appliquent : une fiche livrée modifiée est gardée ; « revenir à la
  version livrée » supprime le fichier, que le jeu recopie au chargement suivant ; « retirer » une voix livrée vide la
  fiche (seule façon que le jeu connaît) ; une voix créée par le joueur se supprime.
- **D03 — Le jeu reste le seul juge d'une fiche.** L'interface empêche la plupart des erreurs par construction (listes,
  cartes, plages) à partir d'un **catalogue** (types de mission et leurs paramètres, natures de récompense, catégories,
  actions, plages de fréquence prises) **généré depuis le mod** et tenu à jour par un test ; aucune seconde copie des
  règles du lecteur Lua. Le verdict du jeu (refus et ligne, lus dans `console.txt`) s'affiche dans l'atelier, à la
  section fautive.
- **D04 — L'IA du pont aide à écrire** (utilisateur). L'atelier utilise le fournisseur déjà configuré pour le pont, avec
  les mêmes plafonds de coût : rédiger la personnalité en anglais à partir de quelques phrases du joueur, proposer
  l'histoire d'une mission, essayer la voix en conversation avant de la mettre en jeu. Sans fournisseur (mode
  `--offline`), ces boutons sont grisés et tout le reste fonctionne.
- **D05 — Interface en français et en anglais** (utilisateur), choisie par la langue du navigateur, anglais à défaut.
- **D06 — Exporter et importer** (utilisateur). Exporter donne la fiche `.txt` elle-même (une voix = un fichier) ;
  importer en accepte une, la soumet au même circuit, et demande un nouvel identifiant si la voix existe déjà.
- **D07 — Note de fréquence et appel spontané écrits dans la fiche** (utilisateur, 2026-11-15). Le mod fournit une
  note manuscrite générique dont le texte et les lieux de butin viennent de la fiche ; le texte de l'appel spontané peut
  être écrit dans la fiche au lieu d'une clé de traduction. Les voix livrées gardent leurs objets et leurs clés.
- **D08 — Relevé de lieux en jeu.** Clic droit « Atelier des voix : relever ce lieu » (case, conteneur, bâtiment), en
  solo ou par un admin ; le jeu ajoute le relevé à un fichier du dossier de travail que l'atelier affiche dans
  « Lieux relevés ».

- **D09 — Journal en direct dans l'atelier** (utilisateur, 2026-11-15). Le pont tourne comme avant ; l'option
  `--atelier` ouvre en plus l'atelier, dans le même programme (sans IA configurée, l'atelier reste ouvert seul). L'atelier devient aussi l'écran d'administration en direct des voix : le
  journal du pont (demandes, réponses, erreurs, coûts) et les lignes des fiches dans `console.txt` s'y lisent en
  direct, filtrables par voix. Lecture seule, sur la machine seulement : le journal peut contenir les dialogues des
  joueurs.

## Mise à jour du 2026-11-16 : la personnalité est le seul texte d'une voix

Décision de l'utilisateur du 2026-11-16 : les champs `knows=`, `ignores=` et `secret=` des fiches sont retirés. Écrits
une fois pour toutes, ils mêlaient le passé du personnage et des affirmations sur la carte qui deviennent fausses en
cours de partie (« la clinique de West Point est encerclée »).

- **D10 — Le texte libre de la fiche est le seul lieu de la personnalité et du passé d'une voix.** Métier, savoir-faire,
  passé et ce que la voix tait (avec la règle de ne jamais le dire) s'y écrivent au passé ; jamais l'état actuel d'un
  lieu. Ce que la voix sait du monde vient du jeu seul : souvenirs, morts, état, mission, troc, réputation, faits du
  bulletin. Les deux lecteurs refusent ces trois clés comme toute clé inconnue (aucune reprise) ; le pont ne filtre
  plus rien d'après des secrets de fiche. Dans l'atelier, l'étape 3 devient « Personnalité » (actions permises, voix
  qu'elle peut faire connaître, personnalité) ; l'IA qui écrit la personnalité y met le passé et ce que la voix tait.
  Plan : [`E22-T14`](../../annexes/plans/E22-atelier-voix.md).

Décisions D01 à D09 inchangées par ailleurs.

## Mise à jour du 2026-11-16 : l'atelier sur le réseau, avec mot de passe

Décision de l'utilisateur du 2026-11-16 : ouvrir l'atelier depuis une tablette ou un autre PC de la maison.

- **D11 — Écoute sur le réseau sur demande, protégée par un mot de passe.** Sans option, rien ne change : écoute sur
  `127.0.0.1`, sans mot de passe (D01). L'option `--atelier-host ADRESSE` (par exemple `0.0.0.0`) ouvre l'atelier sur le
  réseau ; toute adresse autre que la boucle locale demande `ATELIER_PASSWORD` dans `bridge/.env` (10 caractères au
  moins), sinon l'atelier ne démarre pas (message en console, le pont continue). En mode réseau, **chaque** client se
  connecte, la machine elle-même comprise (un mandataire inverse sur la même machine passerait sinon). Page de
  connexion en français ou en anglais ; session par jeton aléatoire dans un cookie `HttpOnly`, `SameSite=Strict`,
  valable 7 jours, gardée en mémoire seulement (pont redémarré : nouvelle connexion) ; bouton de déconnexion. Contre
  les essais en rafale : par adresse du client (adresse réelle de la connexion, jamais `X-Forwarded-For`), 5 échecs
  bloquent 60 s, chaque échec suivant double le blocage jusqu'à 15 min, une réussite remet à zéro ; au-delà de 30
  échecs par minute toutes adresses confondues, toute connexion est refusée 60 s. Connexions, échecs, blocages et
  déconnexions vont au journal en direct (D09) et en console, avec l'adresse du client, jamais le mot de passe. Les
  demandes qui modifient exigent toujours une origine égale à l'adresse de la page ; la vérification « hôte = boucle
  locale » reste celle du mode local. HTTP simple : suffisant sur le réseau de la maison ; pour Internet, un VPN
  (Tailscale) ou un mandataire HTTPS, jamais un port ouvert sur la box. Pas de HTTPS intégré ni de comptes.
  Module `bridge/atelier_auth.py` ; plan : [`E22-T15`](../../annexes/plans/E22-atelier-voix.md).

Le « journal sur la machine seulement » de D09 vaut désormais « journal derrière le mot de passe » en mode réseau.

## Conséquences

- Le pont gagne un second rôle (atelier) ; il reste un seul programme à installer.
- Un nouveau type de mission ou une nouvelle récompense entre au catalogue par la génération, sans toucher l'interface
  (ouvert/fermé : l'interface lit les déclarations).
- Sur un serveur loué, l'atelier tourne sur la machine du serveur, ou l'on exporte la fiche et la copie à la main.

## Hors périmètre

- Hébergement en ligne de l'atelier, partage de voix entre joueurs par un service.
- Édition des fiches de Living Knox.

## Mise à jour du 2026-11-16 — D12 : un atelier sans saisie technique

- **D12** (utilisateur) : l'atelier vise des adolescents ; aucune saisie d'identifiant, de nom technique, de syntaxe ni
  de plage de nombres. La fréquence se choisit par la radio nécessaire (fréquence fixe en option) ; les lots du stock
  et tout objet se choisissent dans des listes. Plan [E24](../../annexes/plans-termines/E24-atelier-simple.md).
