*English: [[Usage]]*

# Utilisation

Un guide pas à pas pour le joueur. Le pont doit tourner pour que les voix et les survivants parlent
([[Installation et configuration|Installation-and-Configuration-FR]]).

## 1. Trouver une fréquence

Les voix émettent sur des fréquences tirées pour chaque partie. Elles sont écrites sur des **notes** trouvées dans le
butin : page de journal radio, fiche de patient, avis de la Garde nationale, note griffonnée, prospectus de Night Owl.
Chaque note se trouve là où sa voix l'aurait laissée (fréquence : option sandbox **Notes de fréquences dans le butin**).

Clic droit sur la note → **Inspecter** (ou **Lire**) pour l'ouvrir. Walt est la première voix à chercher : il répond à
toute heure.

![Note de fréquence de Walt](images/fr-frequency-note.png)

## 2. Parler à une voix à la radio

1. Prenez une radio émettrice **en main** : talkie-walkie, radio HAM (ou une radio militaire portée sur le dos).
2. Allumez-la et réglez-la sur la fréquence de la note.
3. Ouvrez le micro (section **Microphone** de la fenêtre radio).
4. Écrivez votre phrase dans la section **Émettre** en bas de la fenêtre radio, puis Entrée ou **Émettre**.

![La réponse de la voix entendue en jeu, au-dessus du joueur](images/fr-walkie-in-hand.png)

Le champ est grisé pendant que la voix répond ; la réponse passe sur la radio et s'affiche dans les dernières lignes
de la section. Restez bref : une voix à qui l'on parle sans pause vous demande de reprendre votre souffle. Un
talkie-walkie à la ceinture reçoit, mais n'émet pas : prenez-le en main pour parler.

![Section Émettre et réponse de Walt](images/fr-radio-transmit.png)

Chaque voix a ses heures d'écoute et se souvient de vous. L'onglet **Radio** du carnet garde ce qui s'est dit sur
chaque fréquence.

## 3. Rencontrer un groupe Living Knox

Des groupes de survivants vivent dans des maisons ou des camps du comté : colons, neutres et pillards. Un groupe a un
chef, des combattants et des ouvriers, un foyer qu'il barricade, des réserves et des besoins. Approchez doucement et
ne pointez pas d'arme : un groupe défend son foyer, et les pillards attaquent.

![Un groupe à son foyer](images/fr-group-home.png)

## 4. Parler à un survivant (Ctrl+G)

1. Près d'un survivant que vous voyez, appuyez sur **Ctrl+G** : le PNJ visible le plus proche est sélectionné (touche
   **Sélectionner un PNJ RadioSurvivor** dans les options du jeu). Le bouton **Parler** d'un contact du carnet fait
   de même.
2. Écrivez sur la ligne **Dire** du carnet (onglet **Contacts**). En multijoueur, le chat local (`/say`) marche aussi.
3. Le survivant répond dans une bulle au-dessus de sa tête. Une longue réponse arrive en plusieurs bulles.

![Un survivant répond dans une bulle](images/fr-npc-bubble.png)

Un inconnu ne dit pas tout : noms, histoire et demandes viennent après quelques échanges. **Quitter le dialogue** met
fin à la conversation.

## 5. Missions et compte rendu

Quand un survivant ou une voix demande de l'aide, l'offre apparaît dans l'onglet **Missions** du carnet (« Nouvelle
offre dans le carnet »).

- **Accepter personnellement** vous engage ; **Inviter sans engager** y associe un autre joueur ; **Abandonner pour
  le groupe** y renonce (cela coûte de la réputation).
- **Livrer** ouvre la fenêtre de livraison : choisissez les objets que le demandeur accepte.
- Les missions de reconnaissance, de recherche, de nettoyage, de récupération et de signal entourent une **zone
  approximative** sur la carte du monde : le lieu est quelque part dedans, pas au centre.
- Une fois l'objectif rempli, la mission indique **À rapporter** : retournez voir le demandeur et dites-le-lui
  (**Parler**), ou utilisez **Rendre compte** près de lui. Pour une voix radio, rappelez-la sur sa fréquence. La
  mission ne réussit qu'à ce moment, et le délai continue de courir.

![Onglet Missions avec une mission en cours](images/fr-notebook-missions.png)

![Une mission à rapporter](images/fr-notebook-report.png)

![Cercle d'une mission de reconnaissance sur la carte](images/fr-map-zone.png)

## 6. Le carnet

Le bouton **Carnet** de la barre de gauche l'ouvre.

| Onglet | Contenu |
|---|---|
| **Radio** | Historique de chaque fréquence écoutée. |
| **Contacts** | Les personnes rencontrées : groupe, tempérament, conversations entendues, votre note privée (**Enregistrer ma note privée**), et **Ce qu'on pense de vous** (attitude, tendance, accords avec votre camp). |
| **Missions** | Offres et missions : objectif, délai, récompense, participants. |
| **Réputation** | Votre réputation parmi les survivants et ce qu'on retient de vos actes. |
| **Équipe** | Votre faction et ses négociateurs (multijoueur). |

![Onglet Contacts et ce qu'on pense de vous](images/fr-notebook-contacts.png)

![Onglet Radio](images/fr-notebook-radio.png)

## 7. Réputation

Missions tenues, personnes secourues, un marchand floué, un demandeur tué : ce que vous faites est retenu. L'onglet
**Réputation** montre votre niveau (mauvaise, neutre, bonne), sa tendance et les derniers actes dont on se souvient.
L'attitude de chaque survivant envers vous est une autre chose, montrée sur sa page de contact.

![Onglet Réputation](images/fr-notebook-reputation.png)

## 8. Outils d'administration

Pour l'administrateur (solo en mode debug, ou rôle `admin` / `moderator` sur un serveur) :

- menu debug → **Living Knox - Admin** : fenêtre **Living Knox : groupes** avec chaque groupe, son foyer, ses
  membres, son histoire et son journal ; déplacer un foyer, forcer un groupe de relève ;
- clic droit sur un survivant → **Détails (Living Knox)** : la fiche de ce PNJ (besoins, santé, décision, arme), avec
  des réglages bornés, le rôle, le nom et la téléportation ;
- onglet **Réputation** → **Toutes les réputations (admin)**.

![Fenêtre d'administration Living Knox](images/fr-admin-window.png)

![Fiche d'un PNJ](images/fr-npc-sheet.png)
