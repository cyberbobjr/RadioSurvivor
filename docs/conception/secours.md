# Secours en cours : réserves, délai et équipe (E12-T02)

Code : `media/lua/server/RadioSurvivor/RS_Rescue.lua` (section « Secours en cours ») ; référence d'API :
[docs/rescue.md](../rescue.md) ; banc : `tests/test_rescue.py` (classe `RunTests`) ; suite en jeu : `rs.rescue.run`.

## Décisions acquises (plan E12)

- Un groupe à secourir par équipe ; une équipe = une faction vanilla (propriétaire et membres) ou un joueur seul
  (identifiant `RS_Factions.idOf`, E09-T03).
- Les réserves ne baissent que si au moins un joueur est connecté ; un serveur vide ne fait mourir personne.

## Choix pris pour E12-T02 (à confirmer)

1. **Le délai est la réserve.** La voix annonce un délai en jours de jeu ; ce délai n'est pas une échéance
   d'horloge séparée mais la réserve elle-même (`days × 24` heures de jeu). Une livraison (E12-T03) repousse donc
   l'échéance, et un serveur vide la gèle. Option la plus simple : une seule grandeur, cohérente avec la règle
   « serveur vide = personne ne meurt » (une échéance d'horloge continuerait de courir sur un serveur vide).
2. **Valeurs** : 3 jours par défaut, bornés de 1 à 10 ; réserve plafonnée à 10 jours après livraisons. Depuis
   E12-T06 (décision de l'utilisateur du 2026-10-14), le délai par défaut est l'option sandbox
   `RadioSurvivor.RescueDays` (page RadioSurvivor, entier de 1 à 10, défaut 3 ; `Const.rescueDays`) : options
   enregistrées (`getSandboxOptions():getOptionByName`, à jour même après un changement en cours de partie) puis
   `SandboxVars` ; absente, non entière ou hors bornes : 3. Lue au lancement de chaque secours ; un secours en cours
   garde ses réserves. Bornes et plafond restent des constantes de `Rescue.RUN` (`MIN_DAYS`, `MAX_DAYS`,
   `MAX_RESERVE_DAYS`). Bancs : `RunTests` (option à 5, absente, hors bornes, secours en cours) et
   `RunSuiteOptionTests` de `tests/test_rescue.py` ; en jeu : test « a new rescue takes its delay from the RescueDays
   option » de `rs.rescue.run` (option changée en mémoire par `setValue`, remise ensuite), et l'option traduite
   « Jours de réserves d'un groupe à secourir » / « Days of supplies of a group to rescue » visible dans les options
   sandbox (page RadioSurvivor).
3. **Décompte continu** : l'écart d'âge du monde (`getWorldAgeHours`, flottant) entre deux sondages d'une seconde
   réelle, plutôt qu'un retrait d'une heure entière par `EveryHours` : `EveryHours` ne part qu'une fois par mise à
   jour même si plusieurs heures passent (base `api-42-21.md`), et un sondage espacé limite à une seconde réelle le
   temps de serveur vide attribué par erreur au premier joueur qui revient. `EveryHours` force seulement un sondage.
4. **Issues** : `saved`, `missed` (réserves à zéro, ou E12-T05), `abandoned` (sans fait du jour ni scène). Le mot
   `missed` reprend celui de `RS_LifeLog.rescue`. Le fait du jour `rescue` est écrit à la clôture.
5. **Une équipe dissoute** (faction disparue) garde son secours actif sous l'ancien identifiant : ses anciens
   membres reçoivent un autre identifiant et ne le voient plus. Le secours finit `missed` à zéro réserve.

## Limites

- Le premier sondage d'une session ne retire rien (au plus une seconde réelle perdue au démarrage).
- Le relevé de vie (`RS_LifeLog.rescue`) n'est pas alimenté ici : les participants d'une issue sont connus
  d'E12-T04 / E12-T05.
