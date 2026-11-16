*English: [FAQ](../en/12-faq.md)*

# FAQ

**Faut-il le pont pour jouer ?**
Non. Sans lui, le jeu reste jouable : les voix radio ne répondent que par des parasites, le bulletin du soir et les
dernières pages prennent de courts textes fixes, et les PNJ restent muets. Les groupes vivent, se battent et se
fortifient quand même.

**Pourquoi les mods n'appellent-ils pas l'IA eux-mêmes ?**
Le Lua de Project Zomboid n'a aucun accès réseau, et un mod du Workshop ne peut pas lancer de programme. Le pont est un
petit programme Python qui lit les demandes du jeu dans un fichier et écrit les réponses.

**Les joueurs de mon serveur ont-ils besoin du pont ou d'une clé ?**
Non. Seule la machine qui exécute le serveur lance le pont. Les joueurs n'installent que les mods.

**Est-ce que ça coûte de l'argent ?**
Votre fournisseur d'IA facture chaque appel. Chaque message radio est un appel ; les appels spontanés, le bulletin du
soir, les dernières pages et les dialogues des PNJ aussi. Plafonnez-les avec `MaxPerHour` et les autres options
([Options sandbox](09-options-sandbox.md)), et fixez une limite de dépense chez votre fournisseur. La consommation est
notée dans `token_usage.jsonl`. Ou lancez `--offline`, gratuit (les voix répètent votre phrase).

**Quelle IA utiliser ?**
Tout fournisseur compatible avec l'API `/chat/completions` d'OpenAI, serveurs locaux compris. Voir
[Configurer le fournisseur d'IA](08-fournisseur-ia.md).

**Le passeur n'a pas pris mon sac ?**
Il ne passe que lorsque personne n'est à moins de 100 cases du lieu (en x comme en y) depuis environ une heure de jeu.
Éloignez-vous davantage, ou plus longtemps : un joueur revenu en vue remet l'attente à zéro, et l'échange se fait au
retour quand le lieu était trop loin pour être chargé.

**Comment trouver les voix ?**
Leurs fréquences sont tirées à chaque partie et jamais envoyées aux joueurs : cherchez des notes (page de journal radio,
fiche de patient, avis de la Garde nationale, note griffonnée, prospectus de radio, mot manuscrit d'un marchand)
partout où il y a des papiers, dans les boîtes à gants des voitures et sur les zombies, et **Inspectez**-les. Chaque ville vanilla a son marchand (onze en tout, Gus compris) ; un marchand peut
aussi vous présenter un voisin.
Une voix reste silencieuse jusqu'au début de son secours.

**Pourquoi la radio refuse-t-elle d'émettre depuis ma ceinture ?**
Émettre exige une radio en main ou portée sur le dos (ou posée tout près, ou l'autoradio d'un véhicule). Un talkie à la
ceinture peut écouter (avec Belt Walkie-Talkie) mais pas émettre.

**Comment parler à un PNJ ?**
Approchez-vous, appuyez sur **Ctrl+G** pour sélectionner le PNJ visible le plus proche (8 cases au plus), puis parlez
sur la ligne **Dire** du carnet ou dans le chat local (`/say`). Une phrase du chat sans PNJ sélectionné va au plus
proche à 8 cases, ou à personne. Le menu du clic droit **Parler** marche aussi. Les chats général, de faction et privé
n'atteignent pas les PNJ.

**Quels mods cocher ?**
Radio Survivor, Living Knox, ou les deux ; le Core s'ajoute tout seul. Chacun fonctionne sans l'autre. Voir
[Installation](04-installation.md).

**À quoi sert le Core ?**
Il porte ce que Radio Survivor et Living Knox partagent : lien avec le pont, carnet entier (contacts, missions,
réputation), missions, identité des personnages, historique des échanges et réputation. Activé seul, il n'apporte rien
de jouable.

**Le pont change-t-il selon les mods cochés ?**
Non. C'est un seul programme, sans option selon le montage. Il sert les voix de la radio, les PNJ, ou les deux.

**Puis-je jouer Living Knox sans la radio ?**
Oui. Living Knox seul a le carnet complet : parlez à un survivant avec **Ctrl+G**, dans le chat local (`/say`) près
de lui ou par **Parler** dans le menu du clic droit, et livrez ou réclamez ses missions depuis le carnet.

**Puis-je l'utiliser avec Bandits! ou Project A-Life ?**
Pas avec Living Knox : c'est un moteur de PNJ à part entière, et il n'y a qu'un moteur de PNJ par partie.

**Puis-je l'ajouter à une partie existante ?**
C'est possible, mais c'est une version de test : une **nouvelle partie** est vivement conseillée. Le nombre de groupes
est fixé à la création du monde.

**Puis-je changer la personnalité d'une voix ?**
Oui, en tant qu'admin du serveur : modifiez `<dossier Zomboid>/Lua/batman_RadioSurvivor/personas/<voix>.txt` (texte après `[prompt]` :
personnalité, passé, ce qu'elle tait). Elle est relue toutes les 30 s, et une fiche modifiée n'est jamais écrasée par une mise à
jour du mod.

**Est-ce que ça marche en multijoueur ?**
Oui, les mods sont pensés pour les serveurs dédiés : le serveur décide de tout, l'IA n'écrit que des paroles. Le
multijoueur est vérifié par des campagnes de tests automatiques ; signalez tout comportement étrange. Voir
[Le pont sur un serveur dédié](06-pont-sur-serveur-dedie.md).

**Deux serveurs peuvent-ils partager un pont ?**
Non. Un pont par serveur et par dossier d'échange ; donnez à chaque serveur son propre `-cachedir`.

**Que joindre à un rapport de bug ?**
`console.txt` (ou le journal du serveur) et la sortie du pont sans `--debug`. N'envoyez jamais votre `.env` ni un
journal `--debug` tel quel (il contient les prompts et les dialogues).
