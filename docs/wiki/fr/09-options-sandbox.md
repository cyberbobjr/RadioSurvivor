*English: [Sandbox options](../en/09-sandbox-options.md)*

# Options sandbox

Deux pages dans les réglages sandbox : **Radio Survivor** et **Living Knox**. Sur un serveur dédié, elles sont dans
`<Zomboid>/Server/<nom du serveur>_SandboxVars.lua`. L'infobulle de chaque option en jeu donne le détail.

## Radio Survivor

| Option | Défaut | Rôle |
|---|---|---|
| Activer le survivant à la radio (`Enabled`) | oui | Active ou coupe toutes les voix radio. |
| Délai entre deux messages d'un joueur (`PlayerCooldown`) | 10 s | Délai réel entre deux messages envoyés à une voix. |
| Messages par heure, tous joueurs (`MaxPerHour`) | 60 | Messages radio par heure réelle pour tout le serveur ; chacun est un appel à l'IA. `0` = illimité : à éviter sur un serveur public. |
| Appels spontanés (`SpontaneousCalls`) | oui | Appels généraux des voix pendant leurs heures d'écoute ; comptés dans `MaxPerHour`. |
| Langue des appels spontanés (`CallLanguage`) | Langue du serveur | Langue du serveur, anglais ou français. Les réponses suivent toujours la langue de chaque appelant. |
| Notes de fréquences dans le butin (`NoteRarity`) | Normales | Aucune, Rares, Normales, Fréquentes. Lu au chargement du monde. |
| Heure du bulletin du soir (`ChronicleHour`) | 20 | Heure de jeu à laquelle la station pirate lit les nouvelles du jour. |
| Dernières pages des morts (`LastPages`) | oui | Le journal d'un personnage mort est laissé sur le corps. |
| Initiatives des PNJ (`InitiativeFrequency`) | Normales | Désactivées, Rares, Normales, Fréquentes : à quelle fréquence un PNJ proche prend la parole de lui-même (chaque ligne est un appel à l'IA ; au plus 2, 6 ou 12 par heure réelle). |
| Jours de réserves d'un groupe à secourir (`RescueDays`) | 3 | Temps pour rejoindre une famille assiégée (1 à 10 jours de jeu). |

Limites fixes, sans option : 8 demandes radio en attente, 5 s entre deux phrases côté client, 15 phrases par minute et
par joueur, 60 dialogues de PNJ et 12 biographies par heure réelle.

## Living Knox

| Option | Défaut | Rôle |
|---|---|---|
| Activer le moteur de PNJ Living Knox (`Enabled`) | oui | Active les groupes de survivants. Désactivé : aucun groupe ne vit, aucun PNJ n'apparaît. |
| Journal de débogage Living Knox (`Debug`) | non | Messages détaillés du moteur dans le journal console. |
| Nombre de groupes de survivants (`GroupCount`) | 4 | 3 à 5, créés une fois au démarrage du monde : à régler avant de créer le monde. |
| Part des groupes de colons / pillards / neutres (`WeightSettlers`, `WeightRaiders`, `WeightNeutrals`) | 40 / 35 / 25 | Poids relatifs des types de groupes. |
| Membres par groupe, au moins / au plus (`GroupSizeMin`, `GroupSizeMax`) | 4 / 8 | Taille des groupes. |
| Jours avant l'arrivée d'un nouveau groupe, au moins / au plus (`ReliefDaysMin`, `ReliefDaysMax`) | 2 / 5 | Délai avant qu'un groupe décimé soit remplacé ailleurs. |
| Raids des pillards sur les bases des joueurs (`RaidsEnabled`) | oui | Les pillards peuvent envoyer des éclaireurs, puis attaquer une base de joueur. |
| Jours entre deux raids (`RaidDays`) | 14 | Jours de jeu minimum entre deux raids, et avant le premier. |
| Heures avant une vengeance (`RevengeDelayHours`) | 72 | Heures de jeu entre un serment de vengeance et le départ de la première équipe. |

Les distances de combat et d'alerte (en cases) se règlent aussi : distance d'alerte face aux zombies (10), portée de
l'alerte (20), rayon du cri d'alerte (10), distances de fuite (4, 8 en cas de peur), distance d'engagement des
zombies par rôle (10), rayon de défense du foyer (8), rapport de repli (3), distance de danger pour la retraite (8),
rayon des renforts (15), rayons de sommation autour du foyer (14) et d'un membre (10), seuil de blessure (50 % de
santé) et seuil de peur (70).

## Conseillé pour un serveur public

- Gardez `MaxPerHour` assez bas pour votre budget et **jamais à 0**.
- Fixez une limite de dépense chez votre fournisseur d'IA : [Configurer le fournisseur d'IA](08-fournisseur-ia.md).
- `InitiativeFrequency` sur Rares si les paroles des PNJ coûtent trop.
