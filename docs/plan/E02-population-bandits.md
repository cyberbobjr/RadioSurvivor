# E02 — Limiter la population de PNJ Bandits!

**Objectif.** Éviter des centaines de PNJ Bandits! sur un serveur : d'abord par les réglages natifs de Bandits!, puis, si l'utilisateur le décide, par un plafond optionnel appliqué par RadioSurvivor sans modifier les fichiers de Bandits!.

**Dépend de.** E00-T04 (RadioSurvivor ne coûte déjà plus rien pour les bandits jamais contactés).

**Constats sur la copie installée** (Workshop `3268487204`, `modId` `Bandits2`, variante `42.20`, lecture seule, 2026-10-03) :
- **Aucun plafond global** dans Bandits!. Deux générateurs serveur : `checkEvent` toutes les 10 minutes de jeu (`server/BanditServerSpawner.lua:1067`, inscrit ligne 1227) et l'orchestrateur des errants (`server/BanditServerWanderers.lua:797`). Les deux sont des fonctions `local` : impossibles à envelopper.
- `Bandits.General_SpawnMultiplier` (0,25 à 4, défaut 1) multiplie la chance de chaque clan, divisée par 6 (`BanditServerSpawner.lua:1111`, `BanditServerWanderers.lua:762`), **et** la taille des groupes (`BanditServerSpawner.lua:997`).
- `Bandits.General_OriginalBandits` active les clans fournis par le mod (`shared/BanditCustom.lua:233`). Chaque clan a `spawnChance`, `groupMin`/`groupMax`, `dayStart`/`dayEnd`, réglables dans l'éditeur de clans de Bandits!.
- `Bandits.General_DensityScore` est **sans effet** dans cette version : son code est commenté (`BanditServerSpawner.lua:1092-1096`).
- Une taille de groupe nulle ne crée aucun point d'apparition, et la vague est abandonnée (`BanditServerSpawner.lua:1000-1008`). ⚠ Hypothèse à confirmer : `generateSpawnPointUniform(…, 0)` renvoie une liste vide.
- Un cerveau est retiré par la commande `BanditRemove`, envoyée par un client (`server/BanditServerCommands.lua:47-55`). ⚠ Les clusters peuvent donc garder des entrées périmées : à mesurer avant de compter la population sur eux.

## Réponse immédiate (sans code)

Sur le serveur, page sandbox **Bandits** : `General_SpawnMultiplier = 0.25` (quatre fois moins de vagues et des groupes plus petits) ; si c'est encore trop, désactiver `General_OriginalBandits` et créer dans l'éditeur de clans deux ou trois clans avec une `spawnChance` faible, des groupes de 1 à 3, et des jours de début et de fin choisis. E02-T01 documente et chiffre ces réglages.

## Décisions

- 2026-10-03 — Étape abandonnée : l'utilisateur ne veut plus d'apparitions périodiques. Les apparitions automatiques de Bandits! seront coupées par le sous-mod `batman_LivingKnox` (projet `Zomboid\Workshop\LivingKnox`), qui fait vivre 3 à 5 groupes persistants. Les constats ci-dessus restent valables comme référence.

## Hors périmètre

Suppression ou désactivation de bandits existants : destructif, refusé sauf décision explicite.

## Tâches

- [ ] **E02-T01** — Guide des réglages natifs de population Bandits!
  - État : `abandonné`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/bandits-population.md` ; `README.md` (lien)
  - Faire : expliquer les réglages ci-dessus avec leurs lignes sources, calculer la fréquence attendue (chance par clan × multiplicateur ÷ 6 par tranche de 10 minutes de jeu) et la taille moyenne des groupes pour les clans fournis, et proposer trois profils (léger, moyen, nominal).
  - Accepté si : chaque chiffre renvoie à une ligne de code ; les points incertains portent ⚠.
  - Tests : relecture des sources.
  - Preuve : —
  - Reste : remplacé par le sous-mod LivingKnox (décision du 2026-10-03 : aucune apparition périodique de Bandits!, quelques groupes persistants à la place).

- [ ] **E02-T02** — Décider d'un plafond appliqué par RadioSurvivor
  - État : `abandonné`
  - Cible : `hors jeu`
  - Dépend de : E02-T01
  - Fichiers : ce fichier
  - Faire : poser les questions et consigner les réponses.
  - Questions : (1) Faut-il un plafond automatique ? Options : oui, en mettant temporairement le multiplicateur Bandits à 0 tant que la population dépasse le plafond [recommandé] / non, seulement les réglages natifs documentés / oui, et supprimer aussi les bandits en trop (destructif). (2) Que compter ? Options : tous les bandits connus du serveur, virtuels compris [recommandé] / seulement les bandits incarnés / seulement ceux à moins de N cases d'un joueur. (3) Valeur par défaut ? Options : 40 / 80 [recommandé] / désactivé par défaut (0).
  - Accepté si : réponses consignées ; E02-T04 ajustée ou abandonnée.
  - Tests : —
  - Preuve : —
  - Reste : remplacé par le sous-mod LivingKnox (décision du 2026-10-03 : aucune apparition périodique de Bandits!, quelques groupes persistants à la place).

- [ ] **E02-T03** — Mesure de la population Bandits! côté serveur
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E01-T05
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Population.lua` ; suite en jeu `rs.population`
  - Faire : compter les cerveaux des clusters (total, incarnés, virtuels, amicaux, hostiles) et les zombies-bandits chargés ; détecter les entrées sans corps depuis longtemps ; journaliser un résumé toutes les heures de jeu ; fonction console `RS_Population.report()` côté serveur (via `RST.server` ou commande admin).
  - Accepté si : les chiffres d'un serveur de test correspondent à l'observation ; les entrées périmées sont signalées.
  - Tests : banc `lupa` avec clusters factices ; suite serveur en jeu.
  - Preuve : —
  - Reste : remplacé par le sous-mod LivingKnox (décision du 2026-10-03 : aucune apparition périodique de Bandits!, quelques groupes persistants à la place).

- [ ] **E02-T04** — Plafond optionnel par multiplicateur temporaire
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E02-T02, E02-T03
  - Fichiers : `media/sandbox-options.txt` (`RadioSurvivor.BanditCap`, 0 = désactivé) ; traductions `Sandbox.json` ; `RS_Population.lua`
  - Faire : chaque minute de jeu, si la population comptée dépasse le plafond, mémoriser la valeur de `SandboxVars.Bandits.General_SpawnMultiplier` et la mettre à 0 ; la rétablir sous le plafond, ainsi qu'avant toute sauvegarde des options (`OnSave`) et à l'arrêt. Journaliser chaque bascule.
  - Accepté si : plafond atteint = aucune nouvelle vague par `checkEvent` ni par les errants ; valeur d'origine jamais perdue après redémarrage ou modification des options par l'admin.
  - Tests : banc `lupa` (bascule, restauration, valeur modifiée par l'admin pendant le plafond) ; suite en jeu : `BanditServer.Spawner.Type` appelé plafond atteint ne crée personne.
  - Preuve : —
  - Reste : remplacé par le sous-mod LivingKnox (décision du 2026-10-03 : aucune apparition périodique de Bandits!, quelques groupes persistants à la place).

- [ ] **E02-T05** — Validation de la population sur serveur dédié
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E02-T04
  - Fichiers : `docs/bandits-population.md` (résultats)
  - Faire : sur le serveur de test, vitesse de jeu accélérée, mesurer la population sur plusieurs jours de jeu avec le profil choisi et le plafond ; vérifier qu'une action Bandits! normale voisine (vague manuelle, combat) fonctionne.
  - Accepté si : la population reste sous le plafond (marge d'une vague) ; aucun message d'erreur Bandits! nouveau.
  - Tests : suite `rs.population` + relevé du journal.
  - Preuve : —
  - Reste : remplacé par le sous-mod LivingKnox (décision du 2026-10-03 : aucune apparition périodique de Bandits!, quelques groupes persistants à la place).
