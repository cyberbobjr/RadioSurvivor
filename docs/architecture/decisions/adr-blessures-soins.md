# ADR — Blessures localisées, infection, sang visible et soignant de groupe

| | |
|---|---|
| Date | 2026-11-17 |
| Statut | Accepté |
| Décideur | utilisateur (« il faut faire sauter ces limites… fais ça propre, en respectant les principes SOLID », 2026-11-17) ; options de détail confirmées par défaut (D01 à D11) |
| Remplace | le saignement unique par PNJ de LK07-T03 (`npc.bleed`) et la blessure abstraite hors écran `wound` 0..100 de `LK_Simulation` ; complète [sante.md](../../annexes/conception/sante.md) |
| Plan associé | [LK21 — Blessures, infection, sang et soignant](../../annexes/plans/LK21-blessures-soins.md) |
| Références | [Recherche moteur du 2026-11-17](../../annexes/conception/blessures-moteur.md) (`BodyPart.java`, `BodyDamage.java`, `ZombiePacket.java`, `ISApplyBandage.lua`, `ISStitch.lua`, `recipes_medical.txt`, `RecipeCodeOnCreate.java`) ; [ADR simplification](adr-simplification-livingknox.md) (motif façade, registres) |

## Contexte

Les soins de Living Knox ont des limites (fiche `sante.md`, section « Limites ») :
- **Où :** au foyer seulement.
- **Matériel :** il est pris au stock, jamais fabriqué.
- **Blessures :** une seule valeur de saignement par PNJ, sans partie du corps, sans type de plaie et sans infection.
- **À l'écran :** rien ne se voit.
- **Rôle :** pas de soignant avec ses propres tâches.

L'utilisateur veut des blessures « comme pour un jeu » et un vrai rôle de soignant.

Faits du moteur (recherche du 2026-11-17, confirmés statiquement) :
- **Blessures :** le modèle de blessure du joueur (`BodyDamage`, `BodyPart`) ne tourne pas sur un `IsoZombie` (`BodyDamage.Update` sort pour un zombie, `BodyDamage.java:1812`). Il faut donc reproduire ses règles en Lua.
- **Sang :** sang, trous et visuels d'un zombie se posent par `addBlood`, `addHole` et `HumanVisual.setBlood`. En revanche, le paquet réseau d'un zombie (`ZombiePacket.java:105-146`) ne transporte ni sang ni visuel : chaque client doit les poser lui-même, à partir d'un état envoyé par l'autorité.
- **Vêtements d'un cadavre :** retirer un vêtement du conteneur d'un cadavre suffit à l'enlever du corps (`IsoDeadBody.checkClothing`).
- **Objets et recettes :** ceux du soin existent en vanilla (`RippedSheets`, `Bandage`, `Disinfectant`, `SutureNeedle`, `Splint`, recettes `RipClothing`, `CleanBandage`, `DisinfectBandage`…).

## Décisions

- **D01 — Un modèle de blessures pur, par partie du corps, aux règles du vanilla.**
  - Nouveau module partagé `LivingKnox.Wounds`, pur, sans appel au jeu. Chaque PNJ porte une liste de plaies : `{ part, kind, age, bleed, bandage = { clean, life }, disinfected, stitched, splinted, infected }`.
  - Les règles d'évolution viennent du vanilla :
    - durée de guérison par type ;
    - saignement par type ;
    - usure du bandage ;
    - chance d'infection de plaie ;
    - effet des points et de l'attelle.
  - Le module calcule l'évolution sur une durée donnée (`Wounds.advance(list, minutes, ctx)`). Le corps incarné et la simulation hors écran utilisent le même calcul.
  - **Santé générale (précisé le 2026-11-17, LK21-T02) :** la santé suit le calcul du joueur vanilla. Les dégâts d'une partie comptent selon son poids, le saignement retire de la santé générale, et la **régénération passive** du joueur éveillé et nourri (`AddGeneralHealth` 0,002 par tick, `BodyDamage.java:79`, `:1887-1928`) s'applique aux parties qui ne sont plus abîmées par une plaie. Écart mesuré avec le vanilla : 1,5 point au plus (plaie profonde au torse non soignée : 41 % par heure, mort en 17 h environ). La santé remonte donc aussi sans soin, comme pour le joueur.
- **D02 — Types de plaie ouverts à l'extension.**
  - `Wounds.registerKind(id, spec)`, une plaie par fichier (`Wounds/LK_Wound_<Kind>.lua`) : griffure, coupure, plaie profonde, morsure, balle, éclats de verre, fracture, brûlure.
  - Ajouter un type de plaie, c'est ajouter un fichier, sans modifier le moteur.
- **D03 — Les sources de blessure, ouvertes elles aussi.**
  - `Wounds.registerSource(id, spec)` traduit un coup en plaies : partie touchée et type.
  - Les sources sont :
    - l'attaque d'un zombie (griffure, coupure ou morsure, chances du vanilla) ;
    - l'arme tranchante ;
    - l'arme contondante ;
    - l'arme à feu ;
    - le feu ;
    - le verre brisé.
  - `LK_Health.applyHit` appelle la source correspondante.
  - **Verre brisé (utilisateur, 2026-11-17) :** enjamber une fenêtre brisée dont le verre n'a pas été retiré suit la règle du vanilla. Il y a 1 chance sur 2 de se blesser à une main ou un avant-bras ; dans 1 cas sur 7, c'est une plaie profonde avec des éclats, sinon une griffure (`ClimbThroughWindowState.java:532`, `BodyDamage.java:1631`, `BodyPart.java:846`). Un PNJ qui n'est ni en fuite ni en urgence retire d'abord le verre, comme l'action vanilla « retirer le verre brisé », puis enjambe.
  - `LK_Health` reste le seul écrivain de la santé : il lit le saignement total dans `Wounds`.
- **D04 — Infection.**
  - **Infection de plaie :** une plaie sale ou non bandée peut s'infecter (chances du vanilla). Une plaie infectée fait plus mal, use son bandage plus vite et s'aggrave ; il faut la désinfecter. Sa durée de guérison continue de baisser, et l'infection disparaît avec la plaie. Comme dans le jeu de base, elle ne coûte de la santé que si l'option sandbox de dégâts d'infection (`WoundInfectionFactor`) est au-dessus de 0. *(Précisé le 2026-11-17 : la première rédaction disait « saigne », contraire au vanilla, `BodyDamage.java:1957`. Précisé de nouveau le même jour, LK21-T04 : elle disait aussi « ne guérit plus », contraire au vanilla, `BodyPart.java:306-376`, `:424`.)*
  - **Infection par morsure (virus de Knox)** : elle suit la règle du vanilla et l'option sandbox de transmission du joueur. La mort survient après le délai tiré dans la table du vanilla, puis le PNJ se relève en **zombie ordinaire**. Il quitte alors le registre des PNJ et son groupe le pleure (observation `group_death`).
  - Le PNJ mordu le sait. Son groupe peut le savoir, et le journal le note.
- **D05 — Les soins, ouverts à l'extension.**
  - `Care.registerTreatment(id, spec)`, un soin par fichier (`Care/LK_Treat_<Id>.lua`) :
    - nettoyer et désinfecter ;
    - bander, ou changer un bandage sale ;
    - recoudre (aiguille et fil, ou aiguille chirurgicale) ;
    - poser une attelle ;
    - retirer des éclats ou une balle.
  - Chaque soin déclare :
    - les plaies qu'il traite ;
    - le matériel qu'il demande, par étiquette ou fonction vanilla (`isCanBandage`, `Disinfectant`…) ;
    - sa durée et son geste ;
    - son effet sur la plaie.
  - `LK_Care` choisit le blessé, le soignant et le soin le plus urgent. Il ne contient aucune règle propre à un soin.
- **D06 — Le soin branché par un registre, plus par son nom.** L'appel direct `Care.apply` de `LK_Decisions_Apply` est remplacé par une extension inscrite (`Decisions.registerExtension`, recouvrement). C'est le motif déjà utilisé par les postes.
- **D07 — Le rôle de soignant.** Le rôle `medic` existe déjà. Il est affiché « soignant » et reçoit ses tâches par les registres existants (`Upkeep.registerJob` et `Routines.registerChore`), un fichier par tâche :
  - **déchirer des vêtements** en tissu déchiré. Les vêtements viennent du stock du foyer ou d'un cadavre proche, et le calcul est celui de `RipClothing` du vanilla (coton : tissu ; jean et cuir : bandes, avec ciseaux) ;
  - **laver** les bandes et bandages sales à l'eau (`CleanBandage`) ;
  - **stériliser** : eau bouillante ou alcool (`DisinfectBandage`, `DisinfectRag`) ;
  - **fabriquer une attelle** quand une fracture en demande une et qu'il n'y en a pas : recette `MakeSplint` du vanilla (tissu déchiré, plus une planche, une branche ou un bâton) ;
  - **remplir la trousse** (D08) ;
  - **soigner** (D05), en priorité sur les autres tâches quand une plaie saigne.

  Sans soignant, chaque membre se soigne lui-même, plus lentement : la compétence de soin du vanilla est simulée par rôle.
- **D08 — Une vraie trousse.**
  - Le soignant porte un contenant vanilla (`FirstAidKit`), rempli au stock du foyer selon une liste cible déclarée.
  - En expédition, les soins puisent dans la trousse, sinon dans ce que porte le blessé. Au foyer, ils puisent dans la trousse, puis dans le stock.
  - Les objets sont réels : rien n'est créé hors d'une recette.
  - **Départ en expédition (utilisateur, 2026-11-17) :** quand le soignant part en expédition, le matériel médical du foyer lui est réservé en priorité. Sa trousse est complétée d'abord, avant les provisions des autres membres.
- **D09 — Soins hors du foyer.**
  - Le soin se donne aussi en expédition, pendant une halte au calme, quand aucune menace n'est perçue.
  - Une plaie qui saigne fort fait faire une halte à l'équipe.
- **D10 — Le sang et les bandages se voient, chez tous les joueurs.**
  - L'autorité envoie l'état visible des plaies : partie, sang, trou, bandage propre ou sale.
  - Chaque client le pose sur le corps qu'il voit, avec des valeurs explicites, jamais tirées au hasard, et le repose quand le corps est recréé. Le relais et les « vues » client du mod existent déjà.
  - Les bandages se voient par les objets vanilla `Bandage_<Part>` / `Bandage_<Part>_Blood`.
- **D11 — Gestes.** Les gestes de pansement vanilla (`Bob_Bandage*`, variable `BandageType`) sont ajoutés par `tools/gen_animsets.py` s'ils jouent sur un corps de zombie ; sinon on garde le geste `kneel` existant. La vérification se fait en jeu, dans la tâche des gestes.

## Règles du chantier

- **SOLID :**
  - un module par responsabilité : modèle de plaies pur, sources, soins, matériel, tâches du soignant, visuels client ;
  - les extensions passent par des registres ;
  - aucune liste fermée nouvelle ;
  - aucun `if kind == …` dans les moteurs.
- **Tests :**
  - **test rouge d'abord ;**
  - un banc pur pour `Wounds` (règles vanilla citées) ;
  - suites en jeu `lk.wounds`, `lk.care`, `lk.healer` et `lk.woundvisuals`, ajoutées aux campagnes `solo-lk` et `mp`.
- **Mod non publié :** aucune reprise des anciens champs `bleed` et `wound` (règle « pas d'héritage avant publication »).

## Conséquences

- **Ce qui change pour le joueur :**
  - un PNJ blessé saigne d'un endroit précis, avec du sang visible ;
  - le soignant du groupe coupe des vêtements, lave les bandes, porte une trousse et soigne, y compris en expédition ;
  - une morsure peut tuer un PNJ quelques jours plus tard et le relever en zombie.
- **Risques :**
  - **charge réseau :** l'état visible n'est envoyé que s'il change ;
  - **rendu du sang sur un zombie :** à prouver en jeu ;
  - **geste de pansement sur un zombie :** il a une solution de repli.
