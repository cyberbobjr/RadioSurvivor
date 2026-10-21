# ADR B17 — Dialogue avec les PNJ dans le chat de proximité

Date : 2 octobre 2026. Cible : Project Zomboid 42.21.0.

**Statut : implémentation expérimentale 0.2, parcours interactif à valider en jeu.** Le Lua et le bridge sont raccordés ; le parcours complet est testé hors jeu avec deux VM clientes et le bridge offline. Le chargement du véritable serveur dédié 42.21.0 a été exercé. Aucun dialogue avec un PNJ corporel ni rendu du carnet n'a été validé en jeu ; voir [preuves et limites](../../annexes/conception/carnet-implementation-04221.md) et [validation](../../annexes/tests/carnet-validation-04221.md).

## Contexte

Le joueur souhaite parler aux PNJ Bandits! avec le chat normal en multijoueur. Le carnet classique conserve les contacts, les informations sociales, les missions et les échanges matériels. Une fenêtre de saisie dédiée ne doit plus être nécessaire pour une conversation de proximité.

Cet ADR actualise l’accès décrit dans ADR B04 : la saisie locale passe par le chat existant. Le choix d’un raccourci configurable pour désigner l’interlocuteur est une proposition de réalisation ; sa touche exacte n’est pas fixée. Le bouton « Parler » depuis un contact connu constitue un second accès à la même sélection, sans ajouter un menu contextuel obligatoire. L’interface radio existante reste distincte.

## Preuves dans le code décompilé 42.21.0

Sources en lecture seule : `<decompiled>/42.21.0/java/`.

| Observation | Source |
| --- | --- |
| La fonction Lua globale `processSayMessage` appelle `ChatManager.sendMessageToChat(ChatType.say, message)`. | LuaManager.java (`<decompiled>/42.21.0/java/zombie/Lua/LuaManager.java:8894`) |
| L’auteur implicite est le nom d’utilisateur du joueur local. Le message est affiché localement, puis transmis au serveur ; une radio émettrice peut aussi le relayer. | ChatManager.java (`<decompiled>/42.21.0/java/zombie/chat/ChatManager.java:332`), envoi (`<decompiled>/42.21.0/java/zombie/chat/ChatManager.java:440`) |
| Le serveur reçoit, traite et redistribue les messages de chat. Ce chemin inspecté ne fournit pas d’événement Lua d’entrée exploitable comme décision serveur pour les PNJ. | ChatServer.java (`<decompiled>/42.21.0/java/zombie/network/chat/ChatServer.java:169`) |
| Le canal de proximité recherche un `IsoPlayer` à partir de l’auteur et calcule les destinataires depuis sa position. Un auteur PNJ arbitraire ne convient pas à ce chemin : sa résolution peut retourner `null`, ensuite déréférencé. | RangeBasedChat.java (`<decompiled>/42.21.0/java/zombie/chat/defaultChats/RangeBasedChat.java:75`), ChatUtility.java (`<decompiled>/42.21.0/java/zombie/chat/ChatUtility.java:155`) |
| La portée par défaut de `SayChat` vaut 30 ; ce réglage ne doit pas devenir une constante universelle de RadioSurvivor. | SayChat.java (`<decompiled>/42.21.0/java/zombie/chat/defaultChats/SayChat.java:39`) |
| `ChatMessage` et `ChatBase` sont exposés au Lua. `ChatBase.showMessage` alimente le chat par `OnAddMessage` si le canal et l’affichage sont actifs. | LuaManager.java (`<decompiled>/42.21.0/java/zombie/Lua/LuaManager.java:2623`), ChatBase.java (`<decompiled>/42.21.0/java/zombie/chat/ChatBase.java:274`) |
| La bulle native du chat `say` recherche elle aussi un joueur. Une bulle sur un PNJ demande un rendu attaché à ce PNJ. | RangeBasedChat.java (`<decompiled>/42.21.0/java/zombie/chat/defaultChats/RangeBasedChat.java:114`), IsoGameCharacter.java (`<decompiled>/42.21.0/java/zombie/characters/IsoGameCharacter.java:6711`) |

La saisie Lua installée complète ces preuves : ISChat.lua (`<PZ>/media/lua/client/Chat/ISChat.lua:465`) sélectionne le canal et respecte notamment le ralentissement du chat. Son traitement doit être conservé.

## Décision

Utiliser **le chat normal pour les paroles et le carnet pour les engagements et les transactions**. Ajouter un adaptateur Lua RadioSurvivor ; ne pas modifier les classes Java ni les sources vanilla.

1. Le joueur désigne un PNJ proche. Un indicateur discret affiche son nom et le canal. Le serveur confirme cette cible pour le personnage concerné ; s’éloigner, mourir, perdre le PNJ ou changer de cible met fin à la sélection.
2. Une phrase effectivement soumise sur le canal `say` conserve son parcours vanilla. RadioSurvivor adresse une demande distincte au serveur pour le PNJ sélectionné. Les phrases du chat général, de faction, d’administration ou les messages privés ne déclenchent pas cette demande.
3. Le serveur utilise le joueur fourni par `OnClientCommand`, vérifie la sélection, la portée, l’état du PNJ, les limites de texte et de fréquence, puis attribue un identifiant et un numéro d’ordre.
4. Une file unique par PNJ ordonne ses échanges, y compris ceux de plusieurs joueurs ou canaux. Le bridge appelle le LLM une fois pour le tour et renvoie une réponse structurée. Des PNJ différents peuvent être traités en parallèle.
5. Le serveur valide le résultat et les éventuelles intentions autorisées. Il détermine les auditeurs admissibles à l’instant de la réplique, depuis **la position du PNJ**, puis leur transmet un événement identifié.
6. Chaque client destinataire affiche localement la réplique dans le chat existant sous le nom du PNJ. La piste consiste à créer un `ChatMessage` associé au canal `say`, sans l’envoyer dans le circuit natif joueur → serveur et sans sa bulle de joueur. Une bulle facultative utilise l’objet PNJ local. Ce raccordement précis doit être vérifié avec l’API réellement exposée.

## Limites et garanties multijoueur

- `OnAddMessage` est un événement d’affichage, pas une preuve d’autorisation serveur. Ne pas lancer le LLM depuis chaque client qui voit un message : cela multiplierait les décisions et les coûts.
- Le raccordement à la saisie doit préserver les arguments, les retours et les restrictions vanilla. Ne pas transmettre au bridge un message bloqué par la saisie. Les règles serveur applicables au chat, dont silence, permissions et filtrage, doivent être examinées et respectées ; une commande de mod ne doit pas les contourner.
- Une demande de dialogue issue d’une commande de mod n’est pas automatiquement une preuve que le même texte a traversé le filtrage natif. Ne pas lui attribuer cette propriété sans mécanisme vérifié. Le serveur reste autoritaire sur toutes les conséquences.
- Ne jamais emprunter le nom d’un joueur réel pour faire parler un PNJ. L’auteur affiché vient de la fiche serveur, jamais de la demande client.
- La réception dépend des conditions d’audition retenues : distance, étage, bâtiments, surdité et état du récepteur sont à examiner. Un cercle autour du PNJ ne constitue pas une reproduction complète de l’audition vanilla. La sortie de portée pendant l’attente du LLM peut faire manquer sa réplique.
- Chaque réponse porte un identifiant d’événement pour éviter les doublons. Une réponse ancienne après décès, changement de monde, expiration ou changement incompatible d’état est rejetée.
- Affichage local dans le chat, bulle et bruit attirant les zombies sont des effets distincts. Ajouter une ligne ou une bulle ne prouve pas qu’un bruit de monde a été produit ; ne pas doubler celui de la parole vanilla du joueur.
- Les échanges matérialisés dans le carnet exigent une validation serveur propre. Les paroles « j’accepte » ne constituent pas, dans cette première version, une acceptation de mission à la place du bouton.

## Bridge et mémoire

Conserver `bridge/radio_bridge.py` et le transport par fichiers sur la machine serveur. Le prototype existant utilise `requests.txt`, `responses.txt`, un verrou d’instance et un historique de Walt par partie.

Introduire un protocole versionné distinguant le dialogue radio historique du dialogue avec un PNJ. Il transporte au minimum : identité stable du monde et du PNJ, session d’exécution, identifiant de demande, ordre, canal, personnage appelant, contexte connu, personnalité et révision d’état. Les sorties portent texte, corrélation et intentions bornées ; le LLM ne crée ni récompense ni transaction librement.

Séparer les historiques par monde et PNJ, en conservant les identités des interlocuteurs. Tous les joueurs parlent au même PNJ et partagent son état ; un historique par joueur créerait plusieurs versions de sa mémoire. La session d’exécution protège contre les réponses périmées ; elle ne doit pas effacer la mémoire persistante à chaque redémarrage.

Sérialiser chaque conversation sur toute la durée du tour : lire l’historique, appeler le LLM, traiter le résultat dans l’ordre. Le verrou actuel autour des seules lectures et écritures ne suffit pas à empêcher deux appels simultanés de partir du même historique. Distinguer la réponse proposée par le bridge de son application confirmée par le serveur pour ne pas mémoriser comme réalisés des actes rejetés.

## Alternatives écartées

- Injecter un auteur PNJ dans l’envoi natif `say` : ce chemin exige un joueur réel pour la portée et la bulle.
- Produire une réponse LLM sur chacun des clients : aucune autorité commune, doublons et divergences.
- Faire répondre tous les PNJ à toutes les paroles locales : interlocuteur ambigu et appels inutiles.
- Ajouter un chat global spécifique aux PNJ : il ferait entendre une conversation locale à des joueurs absents.

## Validation attendue

Serveur dédié et au moins deux clients : joueur A parle à un PNJ, joueur B proche entend une seule réponse ; B hors portée ne la reçoit pas. Déplacer le PNJ entre demande et réponse. Envoyer deux demandes simultanées au même PNJ puis à deux PNJ différents. Vérifier l’ordre, les historiques distincts, les canaux exclus, les permissions, l’absence de doublons et la préservation du chat entre joueurs.

Tester aussi PNJ mort pendant l’appel, reconnexion, redémarrage, bridge absent, réponse invalide et radio de Walt existante. Les tests simulés complètent ces essais ; ils ne remplacent pas une exécution 42.21.0.

## Documents liés

- [Spécifications Bandits! et RadioSurvivor](../../annexes/recherches/bandits-llm-specifications.md), ADR B02, B03, B04, B06 et B16.
- [Maquette visuelle du carnet](../../annexes/maquettes/interface-echanges-pz.html) et [correspondances ISUI](../../annexes/maquettes/interface-echanges-pz-notes.md). La saisie dédiée de cette maquette HTML est à actualiser selon cet ADR.
