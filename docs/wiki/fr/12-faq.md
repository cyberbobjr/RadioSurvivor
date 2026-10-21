*English: [FAQ](../en/12-faq.md)*

# FAQ

**Faut-il le pont pour jouer ?**
Non. Sans lui, le jeu reste jouable : les voix radio ne répondent que par des parasites, le bulletin du soir et les
dernières pages prennent de courts textes fixes, et les PNJ restent muets. Les groupes vivent, se battent et se
fortifient quand même.

**Pourquoi le mod n'appelle-t-il pas l'IA lui-même ?**
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

**Comment trouver les voix ?**
Leurs fréquences sont tirées à chaque partie et jamais envoyées aux joueurs : cherchez des notes dans le butin (page de
journal radio, fiche de patient, avis de la Garde nationale, note griffonnée, prospectus de radio) et **Inspectez**-les.
Une voix reste silencieuse jusqu'au début de son secours.

**Pourquoi la radio refuse-t-elle d'émettre depuis ma ceinture ?**
Émettre exige une radio en main ou portée sur le dos (ou posée tout près, ou l'autoradio d'un véhicule). Un talkie à la
ceinture peut écouter (avec Belt Walkie-Talkie) mais pas émettre.

**Comment parler à un PNJ ?**
Approchez-vous, appuyez sur **Ctrl+G** pour sélectionner le PNJ visible le plus proche (8 cases au plus), puis parlez
dans le chat local (`/say`). Les chats général, de faction et privé n'atteignent pas les PNJ.

**Puis-je l'utiliser avec Bandits! ou Project A-Life ?**
Non. Radio Survivor a son propre moteur de PNJ (Living Knox) ; un seul moteur de PNJ par partie.

**Puis-je l'ajouter à une partie existante ?**
C'est possible, mais c'est une version de test : une **nouvelle partie** est vivement conseillée. Le nombre de groupes
est fixé à la création du monde.

**Puis-je changer la personnalité d'une voix ?**
Oui, en tant qu'admin du serveur : modifiez `<dossier d'échange>/personas/<voix>.txt` (texte après `[prompt]`, plus
`knows`, `ignores`, `secret`). Elle est relue toutes les 30 s, et une fiche modifiée n'est jamais écrasée par une mise à
jour du mod.

**Est-ce que ça marche en multijoueur ?**
Oui, le mod est pensé pour les serveurs dédiés : le serveur décide de tout, l'IA n'écrit que des paroles. Le
multijoueur est vérifié par des campagnes de tests automatiques ; signalez tout comportement étrange. Voir
[Le pont sur un serveur dédié](06-pont-sur-serveur-dedie.md).

**Deux serveurs peuvent-ils partager un pont ?**
Non. Un pont par serveur et par dossier d'échange ; donnez à chaque serveur son propre `-cachedir`.

**Que joindre à un rapport de bug ?**
`console.txt` (ou le journal du serveur) et la sortie du pont sans `--debug`. N'envoyez jamais votre `.env` ni un
journal `--debug` tel quel (il contient les prompts et les dialogues).
