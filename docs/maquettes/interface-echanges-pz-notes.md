# Maquette des échanges RadioSurvivor

**Mise à jour 0.2 :** une [implémentation ISUI raccordée](../carnet-implementation-04221.md)
existe désormais. Elle conserve le carnet et le choix de fournitures ; conformément à B17,
elle utilise le chat local vanilla pour la saisie, sans reprendre la fenêtre de dialogue ni
les données fictives ci-dessous. Le parcours est testé en simulation et le serveur dédié
chargé ; les captures de cette maquette ne prouvent pas le rendu de l'ISUI réel.

[Ouvrir la maquette interactive](interface-echanges-pz.html).

Cette proposition reprend le carnet classique validé et ajoute deux fenêtres : dialogue de proximité et sélection des fournitures. Les boutons supérieurs permettent de comparer six situations, avec des données fictives. On peut aussi suivre le parcours complet : **Dialogue → Voir l’offre → Accepter → Livrer → confirmer → récupérer le lot**. Les fenêtres se déplacent et se réduisent. Fermer une fenêtre ne supprime aucun engagement.

## Construction possible dans Project Zomboid

La version observée dans `<Zomboid>/console.txt:59` est **42.21.0**. Les références ci-dessous sont les sources installées dans `<PZ>/`. Il s’agit d’une inspection statique, pas d’une validation de RadioSurvivor en jeu.

| Élément proposé | Construction Lua envisagée | Référence observée |
| --- | --- | --- |
| Dialogue et fenêtre de remise | `ISCollapsableWindow`, barre de titre, fermeture, réduction, boutons enfants | `media/lua/client/ISUI/ISCollapsableWindow.lua`, `createChildren` ligne 26, `prerender` ligne 152 |
| Carnet habillé de papier | Panneau natif avec textures de fond ; textes et contrôles dessinés séparément | `ISPanel.lua` ; `ISUIElement.lua`, `drawTextureScaled` ligne 1032, `drawTextureScaledAspect` ligne 1065, `drawTextureTiled` ligne 1109 |
| Onglets Contacts / Missions / Réputation | `ISTabPanel`, ou boutons natifs habillés avec des textures | `ISTabPanel.lua`, textures des onglets vers les lignes 116 et 148 |
| Liste des contacts et missions | `ISScrollingListBox`, sélection et défilement | `media/lua/client/ISUI/ISScrollingListBox.lua` |
| Messages et saisie | Panneau défilant, texte dynamique et `ISTextEntryBox` | `ISRichTextPanel.lua`, `ISTextEntryBox.lua` |
| Boutons avec icône | `ISButton`, `setImage`, dimensions d’image | `ISButton.lua`, `setImage` ligne 179 |

MilitaryDrop fournit déjà un exemple local de cette approche : `MilitaryDrop/Contents/mods/batman_MilitaryDrop/42.21/media/lua/client/MilitaryDrop/MilitaryDrop_RequisitionWindow.lua`. Sa fenêtre dérive de `ISPanelJoypad` (ligne 54), met les textures en cache avec `getTexture` (vers les lignes 1362–1371) et compose papier, cadre et texte dans son rendu (vers la ligne 1474). La mise en page mesure les textes et prévoit des adaptations selon les polices et les dimensions.

**Oui, on peut construire ces interfaces avec des images.** Les textures donnent la matière et les ornements ; noms, dialogues, quantités, délais et boutons restent dynamiques. Une unique image contenant toute l’interface rendrait les traductions, les changements de taille et les interactions difficiles.

Pour l’implémentation : conserver des espaces de noms `RS_UI_*`, charger les textures une fois, prévoir un fond uni de secours, mesurer les textes selon la police, découper les zones défilantes et tenir compte de la résolution ainsi que du joueur local concerné. Les coordonnées de clic doivent suivre les mêmes calculs que les coordonnées de dessin. La prise en charge de la manette demande un parcours de focus explicite ; elle n’est pas simulée ici.

## Parcours représentés

- **Dialogue** : proximité, saisie libre et réponses scénarisées à propos des fournitures, du délai et de la récompense. Aucun véritable LLM ne répond dans cette démo. Poser une question ne change pas l’offre fixe.
- **Offre** : conditions visibles avant acceptation personnelle. Le refus n’engage pas le joueur.
- **Suivi** : progression commune et participants ayant chacun accepté. Le cas illustré commence avec deux pansements déjà remis par Camille.
- **Livraison** : choix des objets propres, mélange des équivalents acceptés, plafonnement aux besoins restants, récapitulatif et confirmation. Les bandages sales sont exclus. Une remise partielle ne donne pas de réputation.
- **Retour de quête** : réussite, gain personnel pour les participants puis retrait unique du lot commun. Le retrait affiche son bénéficiaire ; le partage reste libre.
- **Fiche PNJ** : personnalité, confiance qualitative, trêve, dernières conversations et notes privées. Les notes de la maquette sont enregistrées dans le navigateur, sans connexion au jeu.
- **Réputation** : historique distinct de la confiance personnelle. Le passage illustratif à « Bonne » ne définit aucun seuil ou barème.

Le délai continue pendant les déconnexions et ne se suspend que lorsque le serveur est arrêté. Le compteur affiché est un instantané de démonstration ; il ne simule pas une horloge serveur. Les états de défaillance, l’abandon et la mort du demandeur restent décrits dans les spécifications ; cette maquette se concentre sur l’échange réussi.

## Autorité multijoueur

Dans le mod réel, les boutons enverront des demandes au serveur. Le serveur vérifiera l’identité du personnage, son engagement, la portée, le PNJ, le délai, les objets et les quantités avant le transfert. Le retrait du lot devra être atomique pour empêcher deux participants de le récupérer simultanément. Les clients afficheront ensuite l’état confirmé et partagé. Les choix d’interface présentés ici ne constituent pas une implémentation de ces garanties.

## Images utilisées

La capture de fond est une vraie scène de Project Zomboid ; voir [les sources des illustrations](illustrations/SOURCES.md). Les fenêtres ajoutées, les personnages nommés et les échanges sont fictifs. Les textures papier, carton et étiquette sont remplacées par des aplats CSS ; les petites icônes de fournitures sont des approximations CSS, à remplacer par les textures des objets réels dans la fenêtre Lua.

Le HTML reproduit la composition visuelle et les interactions. **Project Zomboid ne charge pas cette page comme une interface Lua.** La conversion ISUI 0.2 est documentée séparément ; les essais interactifs client/serveur restent à réaliser.
