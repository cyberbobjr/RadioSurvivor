# Équipement

- Tâches : LK02-T06 (création), LK02-T13 (abonnés d'autres mods) ; suite : LK07 (mort et cadavre), LK05 (gestes déclenchés par le comportement)
- Build : 42.21.0 — Date : 2026-10-09 — Statut : brouillon

## Problème

Un PNJ armé doit montrer son arme : accrochée (dos, hanche, ceinture) au repos et en marche, en main quand il vise, garde ou frappe, pour que les nœuds `LKActorAimRifle`, `LKActorGuard1H`, `LKActorStrike1H` (LK02-T05) reçoivent la variable vanilla `Weapon`. Décision de l'utilisateur du 2026-10-09 (`docs/plan/LK02-jalon-corps-gestes.md`, Décisions) : arme **accrochée** par le serveur (`sendAttachedItem`), **mise en main** par chaque client pour les gestes, abonnés `OnEquipPrimary` qui supposent un joueur neutralisés.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `setPrimaryHandItem` déclenche `OnEquipPrimary(personnage, objet)` pour tout personnage, puis pose `Weapon`. Aucune autre méthode publique ne pose l'objet en main sans l'événement (`leftHandItem` n'est écrit ailleurs qu'au chargement). | `J/characters/IsoGameCharacter.java:2986-3024, 4919` | confirmé statiquement ; événement confirmé en jeu (solo, LK02-T10) |
| `Weapon` vaut `firearm` ou `2handed` seulement si les deux mains tiennent **le même** objet ; une arme à deux mains tenue d'une main donne `handgun` ou `1handed`. | `J/inventory/types/WeaponType.java:75-108` ; `setSecondaryHandItem` : `J/characters/IsoGameCharacter.java:3361-3375` | confirmé statiquement |
| L'abonné vanilla de la pêche est inscrit par référence (`Events.OnEquipPrimary.Add(Fishing.Handler.onEquipPrimary)`), teste `player:isLocal()` puis appelle `Fishing.Handler.handleFishing` **par la table** ; celle-ci appelle `getPlayerNum()` (solo) ou `getUsername()` (MP), absents d'un zombie. `isLocal()` d'un zombie : vrai en solo et chez le client propriétaire, faux ailleurs. | `media/lua/client/Fishing/FishingHandler.lua:15-24` ; `J/characters/IsoGameCharacter.java:13594-13596`, `J/characters/component/NetworkComponent.java:19-21` | confirmé statiquement |
| Autre abonné vanilla : `ISRadioWindow.onEquip` compare au joueur local, sans risque. | `media/lua/client/RadioCom/ISRadioWindow.lua:407-414` | confirmé statiquement |
| `setAttachedItem` refuse un emplacement absent du groupe du personnage (`checkValid`) ; pour un zombie, aucun paquet n'est envoyé. | `J/characters/AttachedItems/AttachedItems.java:43-62` ; `J/characters/IsoGameCharacter.java:3183-3206` | confirmé statiquement |
| `sendAttachedItem` (serveur) envoie l'objet sérialisé aux clients proches ; le client le pose sur le zombie de cet `onlineId`. Le serveur ne pose rien sur sa propre copie ; un client sans copie à l'envoi ne reçoit rien. | `J/Lua/LuaManager.java:9719-9724` ; `J/network/packets/GameCharacterAttachedItemPacket.java:41-105` | confirmé statiquement |
| Objet en main d'un zombie posé par le serveur : envoi `Equip` typé joueur, exception. | base `zombies-as-npc-bodies.md` ; `corps-et-animations.md` §5 | confirmé statiquement ; ⚠ exception à mesurer |
| Emplacement vanilla selon l'`AttachmentType` du script : table de la barre d'accès rapide (fichier **client**, absent d'un serveur dédié). | `media/lua/client/Hotbar/ISHotbarAttachDefinition.lua:4-22, 44-53, 77-94` ; `media/lua/shared/NPCs/AttachedLocations.lua:5-66` | confirmé statiquement |

Emplacements retenus (`LivingKnox.Equipment.LOCATIONS`) et armes de référence (`media/scripts/generated/items/weapon.txt`) :

| Arme | `AttachmentType` (ligne) | Emplacement | Mains | `Weapon` en main |
|---|---|---|---|---|
| `Base.Shotgun` | `Rifle` (11508) | `Rifle On Back` | deux (`TwoHandWeapon`, `RequiresEquippedBothHands`) | `firearm` → `LKActorAimRifle` |
| `Base.Pistol` | `Holster` (11010) | `Holster Right` | une | `handgun` → `LKActorAimHandgun` |
| `Base.BaseballBat` | `Shovel` (6681) | `Shovel Back` | deux (`TwoHandWeapon`) | `2handed` → `LKActorGuard2H`, `LKActorStrike2H` |
| `Base.HandAxe` | `Hammer` (5935) | `Belt Left` | une | `1handed` → `LKActorGuard1H`, `LKActorStrike1H` |
| `Base.Axe` | `BigWeapon` (9677) | `Big Weapon On Back` | deux | `2handed` |

Autres types : `BigBlade`/`Sword` → `Blade On Back`, `Knife`/`NotKnife` → `Belt Left Upside`, `HolsterSmall` → `Holster Right`, etc. (côté gauche de la ceinture, hanche droite pour l'étui). Une arme sans `AttachmentType` connu est refusée.

## Choix

- **Registre** : champ facultatif `npc.weapon = "Module.Objet"` (schéma 2 inchangé ; un registre sans ce champ reste valide ; `Identity.validate` refuse seulement une valeur mal formée). `LivingKnox.Equipment.setWeapon(id, type | nil)` vérifie l'objet une fois par type (`instanceItem`, `HandWeapon`, emplacement connu).
- **Serveur** : objet accroché sur sa copie du corps (`setAttachedItem`) puis `sendAttachedItem`, renvoyé quand l'arme ou l'`onlineId` change (retour de chunk) ; ancien emplacement vidé et envoyé vide. Table complète `equipState` `{ rev, w = { [id] = { t, l, h } } }` publiée à chaque changement et au client qui envoie `guardHello` ; révision croissante, table ancienne ignorée. Jamais d'objet en main.
- **Affichage (solo, chaque client)**, toutes les 3 images, sur les corps connus de `LK_Anim` : geste `aim`/`guard`/`strike` (et `shoot`/`reload` du tir, LK06-T03) → objet en main (même objet dans les deux mains pour une arme à deux mains), emplacement vidé ; autre geste → mains vides, objet accroché. L'objet passe du dos à la main et revient (aucune création à chaque geste) ; un client arrivé après ou une copie recréée accroche l'arme d'après la table. Idempotent ; objet qui n'est plus le corps courant nettoyé.
- **`OnEquipPrimary`** : enveloppe de `Fishing.Handler.handleFishing`, et d'elle seule, posée avant chaque pose en main (le fichier client est chargé après `shared`) : un personnage qui n'est pas un `IsoPlayer` est ignoré, un joueur passe à l'original sans changement. Envelopper `onEquipPrimary` serait sans effet (inscrit par référence) ; retirer l'abonné et en inscrire un autre changerait l'ordre des abonnés et dépendrait de la référence d'origine. La pose reste rare : une par changement de geste.

## Abonnés d'autres mods

Relevé LK02-T13 (2026-10-09), liste de mods de l'utilisateur du rapport RST du 2026-10-09, sources installées lues (lecture seule) : `<Steam>\steamapps\workshop\content\108600\<id>`, projets `Workshop\<Projet>\Contents\mods`, `Zomboid\mods`, vanilla `media\lua`. Recherche de `OnEquipPrimary`, `OnEquipSecondary` et `OnClothingUpdated` dans tous les `.lua` de chaque mod (toutes variantes).

| Abonné | Fichier:ligne | Côté | Suppose un joueur ? | Avec un `IsoZombie` | Appelé chez nous |
|---|---|---|---|---|---|
| Pêche (vanilla) `Fishing.Handler.onEquipPrimary` → `handleFishing` | `media/lua/client/Fishing/FishingHandler.lua:15-24` | client | oui (`getPlayerNum`/`getUsername`) | erreur si `isLocal()` ; **enveloppé** (`guardEquipEvent`) | solo, client propriétaire |
| Radio (vanilla) `ISRadioWindow.onEquip` (primaire et secondaire) | `media/lua/client/RadioCom/ISRadioWindow.lua:407-414` | client | non : `_player == getPlayer()` | rien | solo, chaque client qui pose l'arme |
| `SWMG` (`3722064198`, variante `42.13`, seule présente) `restoreEquippedWeapon` (primaire et secondaire) | `mods/Gunworks_gang_framework/42.13/media/lua/shared/WeaponSystems/Init.lua:41-52, 65-66` | partagé | non : personnage testé contre `nil` seulement | arme à distance seule : ModData, statistiques et sprite **de l'objet** restaurés (`Magazine.RestoreMagazineType`, `Underbarrel.RestoreOnLoad`, `FoldingStock`/`FoldingBipod`/`Bayonet`, `StatsFactory.ReapplyAllModifiers` qui instancie une copie de l'arme) ; aucun accès au personnage ; aucune erreur | solo, chaque client qui pose l'arme (jamais le serveur : aucun objet en main) |
| `SWMG` `checkWeaponStateOnEquip` (primaire et secondaire) | `…/WeaponSystems/Hooks/AnimationsHooks.lua:188-198` | partagé | non | arme à distance enregistrée : pièces d'arme selon les munitions (`Animations.CheckStates`, arme seule) ; aucune erreur | idem |
| `OnClothingUpdated` | `J/characters/IsoGameCharacter.java:3183-3206` | — | — | **non déclenché** : `setAttachedItem` ne le déclenche que pour un `IsoPlayer` local ; `setPrimaryHandItem`/`setSecondaryHandItem` ne le déclenchent pas (`:2986-3024, 3361-3375`) | jamais |

Aucun abonné dans : `tofmodoptionsfix` (`3560668866`), `ModLoadOrderSorter_b42` (`3423660713`), `ModManager` (`3567084868`), `mapmodmanager` (`3360392628`), `3019672735/ModComparer`, `DelranModdOrderCrashFix` (`3455645697`), `ChuckleberryFinnAlertSystem` (`3077900375`), `ModFolders` (`3779201168`), `GunMakerB42` (`3729342595`), `FirearmTeardown` et `FirearmTeardown_GoM` (`3811437777`), `GunsOfMarz` (`3722134990`), `HBVCEFb42` (`3610677934`), `GunMakerExpandedPlus` (`3806684464`), `GoMAttachmentWorkbench` (`3798555914`), `Authentic Z - Current` (`2335368829` : déclenche seulement `OnClothingUpdated` dans son code de recette, pour le joueur qui fabrique), `TooltipLib` (`3694097672`), ni dans les mods `batman_*` de la liste (`SignalSmoke`, `PZPuppeteer`, `PZDirector`, `MilitaryDrop`, `RenaultTrafic1`, `TimberChainsaw`, `TimberAuthenticZCompatibility`, `ErisFoodExpiry`). Aucun de ces mods ne remplace non plus une méthode Java par `__classmetatables`.

**Voie retenue : aucune nouvelle protection.** Le seul abonné fautif reste celui de la pêche, déjà enveloppé. Les abonnés `SWMG` ne lisent que l'arme et la remettent dans l'état qu'ils donneraient à l'arme d'un joueur (effet voulu, limité à l'objet que nous avons créé ; une instanciation de copie par pose, une pose par changement de geste). Un drapeau `LivingKnox.Equipment.equipping` ne servirait qu'à des enveloppes ciblées : sans abonné fautif, il n'est pas ajouté.

**Garde générique impossible** : `Events.OnEquipPrimary` est une table Lua qui ne contient que `Add` et `Remove` ; les abonnés sont dans une liste Java (`J/Lua/Event.java:25, 74-78`, classe non exposée). Ils ne peuvent être ni lus, ni enveloppés, ni réordonnés depuis Lua. Envelopper `Events.OnEquipPrimary.Add` ne capterait que les abonnés inscrits après notre fichier et modifierait le comportement de tous les mods.

**Limite** : un mod ajouté plus tard dont l'abonné suppose un joueur échouera une fois par pose ou retrait de l'arme (jamais par passage), chez les machines qui posent l'arme (solo, clients MP ; selon `isLocal()` s'il le teste). L'erreur est isolée par Java (`J/Lua/Event.java:52-62`) : l'objet est quand même en main et notre passage n'échoue pas (banc). Remède au cas par cas : enveloppe ciblée de la fonction fautive appelée par la table, comme pour la pêche, posée seulement si le mod est actif. Relevé à refaire quand la liste de mods change.

## Arme remplacée par un autre mod (LK07-T08, 2026-10-12)

**Constat** (LK07-T07, `sante.md`, « Butin absent du cadavre en jeu ») : un mod d'armes actif remplace les armes,
chargeurs et munitions vanilla dès qu'ils changent de conteneur, et l'arme vanilla **accrochée** d'un zombie à sa
première mise à jour (même emplacement, objet neuf d'un autre type, autres munitions, souvent un autre emplacement
d'accroche ; relevé en lecture seule, aucun code repris). Avant LK07-T08, notre passage reposait aussitôt l'arme du
registre (objet du mod effacé) et le registre ne connaissait que l'ancien type.

**Décision (utilisateur, 2026-10-12)** : laisser le mod remplacer le butin des PNJ comme celui des zombies ; garantir
seulement qu'un PNJ vivant ne perd ni son arme ni ses munitions.

**Choix** (aucun code ni marque du mod tiers lu ; valable pour tout remplacement) :

- Chaque objet arme créé par `LK_Equipment` porte la marque `LKWeapon` dans ses ModData (objet neuf sans ModData,
  `hasModData` faux pour une table vide, `InventoryItem.java:414-423`).
- À chaque passage, l'autorité (serveur toutes les 15 images, solo toutes les 3) relit l'objet réellement accroché à
  l'emplacement voulu (et en main hors serveur) : une `HandWeapon` d'un autre type **sans** la marque est adoptée
  (`Equipment.adoptForeign`) : registre `npc.weapon` = son type, **même objet** déplacé vers son propre emplacement
  (ancien emplacement vidé et envoyé aux clients sur un serveur), marque posée, table `equipState` republiée.
- Munitions (`Ammo.convert`) : nombre de cartouches gardé. Cartouches dans l'arme reportées (au plus la capacité,
  le reste en cartouches libres) ; cartouches libres d'un autre type échangées une pour une ; chargeurs d'un autre
  type échangés contre ceux de la nouvelle arme avec leurs cartouches, ou vidés en cartouches libres si elle n'a pas
  de chargeur (l'objet chargeur reste). Nouvelle arme sans munitions : cartouches de l'arme rendues en objets.
  Aucun état créé si les munitions de départ ne sont pas encore posées (`LK_Loot` les donnera dans le nouveau type).
- Arme inutilisable par un PNJ (emplacement inconnu, pas une `HandWeapon`) : l'arme du registre est reposée comme
  avant, une ligne de journal.
- Objet marqué d'un ancien type (registre changé pendant que le corps était déchargé) : jamais adopté.
- Combat (`LK_Combat.step`) : un ordre armé dont l'arme ne correspond plus au registre est renouvelé avec l'arme
  portée (`stats.rearmed`, « weapon changed »), sans faux « out of ammo ».
- Mort (`LK_Loot.onDeath`) : adoption faite d'abord, si le remplacement a eu lieu depuis le dernier passage.

**Limites** : la conversion change le calibre des cartouches (nombre gardé, pas le type) ; un objet non marqué d'un
ancien type sur un corps sauvegardé avant LK07-T08 serait adopté une fois ; un remplacement à un autre emplacement
que celui de l'arme voulue n'est pas vu. Décision à confirmer : conversion des munitions une pour une.

**Tests** : banc `tests/test_lk_weapon_swap.py` (doublure du remplacement : même emplacement, autre arme, autres
munitions ; MP et solo : adoption, emplacement, munitions, envoi aux clients, tir avec l'arme remplaçante, ordre
renouvelé en plein combat, revolver sans chargeur, arme inutilisable, objet marqué jamais adopté, geste à deux mains,
cadavre) ; suite en jeu `lk.weaponswap` (`RST_LKWeaponSwap.lua`) : `RST.run({ suite = "lk.weaponswap", tags = "world" })`.

## Alternatives écartées

- Objet en main en permanence : un événement par copie recréée, arme en main pendant la marche (non voulu par la décision).
- Arme posée en main par le serveur : exception `Equip` (§ contraintes).
- Lire `ISHotbarAttachDefinition` à l'exécution : fichier client, absent du serveur dédié qui décide.

## Idées reprises

- Aucune.

## Tests

- Banc lupa (`tests/test_lk_equipment.py`, 19 tests) : doublures `setPrimaryHandItem`/`setSecondaryHandItem` (événements, `Weapon` d'après `WeaponType`, exception sur le serveur), abonné de pêche vanilla simulé (échec prouvé sans garde), `sendAttachedItem` et réception (client absent à l'envoi), `getAnimationDebug` d'après `tools/anim_table.json` ; solo, serveur et deux clients, client arrivé après, copie recréée, retour de chunk, changement et retrait d'arme, refus, relecture du registre, commande `LKB.weapon`, suite `lk.equipment` exécutée sur les doublures ; abonnés d'autres mods (LK02-T13) : doublures de comportement du cadre `SWMG` et de `ISRadioWindow` (aucune erreur, arme seule modifiée, solo et deux clients, jamais sur le serveur) et abonné hypothétique qui suppose un joueur (une erreur par pose, affichage intact).
- VM Kahlua : sans objet (aucune construction propre à Kahlua).
- En jeu : suite `lk.equipment` (tag `world`, solo) ; serveur dédié de test (`-Filters rst`) : chargement sans erreur Lua, aucune suite LK exécutée.

### Protocole solo (`rstest-solo`, mod de dev)

1. Noter le nombre de lignes `handleFishing` de `console.txt`.
2. `LKB.spawn(2, 0)` ; attendre qu'il soit debout ; `LKB.weapon(1, "Base.Shotgun")` : fusil dans le dos.
3. `LKB.gesture(1, "aim")` : fusil épaulé à deux mains ; `LKB.anim(1)` : `Weapon=firearm`, nœud `LKActorAimRifle`, emplacement vide.
4. `LKB.gesture(1, "idle")` : fusil de nouveau dans le dos, mains vides.
5. Même chose avec `Base.Pistol` (hanche droite, `aim`), `Base.BaseballBat` (dos, `guard`, `strike`), `Base.HandAxe` (ceinture gauche, `guard`, `strike`).
6. `RST.run({ suite = "lk.equipment", tags = "world" })` ; `LKB.clear()`.
7. Compter de nouveau les lignes `handleFishing` : aucune nouvelle.

### Protocole MP (séance finale)

Serveur dédié de test, deux clients près du PNJ : `LKB.weapon` puis gestes (chaque client voit l'arme en main, puis accrochée) ; client 2 déconnecté, arme changée, client 2 reconnecté (arme reçue par la table) ; `server-console.txt` sans exception `Equip` ni erreur `LivingKnox`.

## Points ouverts

- ⚠ Rendu réel de chaque emplacement sur un corps de zombie (position et orientation de l'objet).
- ⚠ Propagation MP non validée : `sendAttachedItem` vers les clients présents, table `equipState` pour un client arrivé après, `onlineId` changé.
- ⚠ Abonnés `OnEquipPrimary`/`OnEquipSecondary` d'**autres mods** : liste de l'utilisateur relevée (LK02-T13, aucun fautif) ; un mod ajouté plus tard n'est pas couvert (§ Abonnés d'autres mods, limite). Relevé statique, à confirmer en jeu avec la liste de mods.
- Arme du cadavre : tranché en LK07-T05 (`sante.md`, « Butin réel du cadavre ») : l'arme est gardée dans le cadavre, accrochée et dans son conteneur ; sans cela un objet seulement accroché était perdu sur un serveur.
- ⚠ Pas d'emplacement « avec sac » : un PNJ portant un sac à dos afficherait l'arme au travers.
