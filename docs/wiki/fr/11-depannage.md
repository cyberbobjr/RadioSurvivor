*English: [Troubleshooting](../en/11-troubleshooting.md)*

# Dépannage

## Où regarder

| Journal | Où |
|---|---|
| Pont | Sa fenêtre de terminal. Pour le garder : `python radio_bridge.py > bridge.log 2>&1` ; systemd : `journalctl -u radiosurvivor-bridge`. Relancez avec `--debug` pour le détail complet (il contient les dialogues : ne pas le partager tel quel). |
| Jeu (solo, hôte) | `%USERPROFILE%\Zomboid\console.txt`, lignes `[RadioSurvivor]`, `[RS_Carnet]`, `[LK…]`. |
| Serveur dédié | Le journal console du serveur (`<Zomboid>/server-console.txt` ou le journal de votre service). |
| Dossier d'échange | `requests.txt`, `responses.txt`, `bridge-alive.txt`, `token_usage.jsonl`, `personas/`. |

## Liste de contrôle : le pont marche-t-il ?

1. Le terminal du pont affiche `Bridge ready, model …, directory …`. Sinon, lisez la dernière ligne (réglage manquant,
   autre pont en marche).
2. `Exchange directory` dans le bandeau est bien le dossier du serveur : il contient `personas/` après le premier
   chargement du monde, et `bridge-alive.txt` tant que le pont tourne.
3. Quand vous parlez à la radio, le terminal affiche `<appelant> -> walt : <phrase>`. Si rien n'apparaît, le jeu écrit
   dans un autre dossier, ou votre radio n'est pas sur la fréquence d'une voix (une phrase sur une fréquence vide est
   simplement émise, rien d'autre ne se passe).

## Voix muettes ou « Rien que des parasites... »

| Symptôme | Cause et remède |
|---|---|
| « Rien que des parasites... » après environ 90 s ; journal du serveur `no answer from the bridge for <id> (is bridge\radio_bridge.py running?)` | Aucun pont vu : arrêté, ou il surveille un autre dossier. Vérifiez `Exchange directory` et `bridge-alive.txt` dans le dossier du serveur. |
| « Rien que des parasites... » après environ 150 s, pont en marche | L'IA n'a pas répondu en 60 s, ou la demande a attendu plus de 75 s : voir `LLM error` ou `Expired request ignored` dans le pont. |
| « Rien que des parasites... » tout de suite | Le jeu n'a pas pu écrire `requests.txt` (droits sur `Zomboid/Lua`, disque plein). |
| « Trop de monde sur la fréquence, réessayez plus tard. » | `MaxPerHour` atteint ou 8 demandes en attente. Augmentez `MaxPerHour` si besoin. |
| « Il faut une radio émettrice : en main ou sur le dos (pas à la ceinture)… », ou pas de section **Émettre** | Émettre exige une radio émettrice en main ou portée sur le dos (ou posée tout près, ou la radio de votre véhicule), allumée, micro ouvert. Ni à la ceinture ni dans un sac. |
| Les PNJ ne répondent jamais ; le carnet affiche « Bridge absent, réponse invalide ou périmée. Aucune décision appliquée. » | Mêmes causes pour un dialogue de PNJ ; le journal du serveur la nomme : `no reply after 150000 ms`, `bridge error timeout`, `http_503`, `unreachable`, `bad_response`, `invalid_or_unavailable`, `expired`. |
| « Impossible de transmettre au bridge. » | `requests.txt` ne peut pas être écrit. |

## Messages du pont

| Message | Cause et remède |
|---|---|
| `Missing configuration: OPENAI_KEY, …` | `.env` introuvable (`--env` faux) ou valeur vide. Voir [Configurer le fournisseur d'IA](08-fournisseur-ia.md). |
| `Another bridge is already running on …` | Un seul pont par dossier : arrêtez l'autre (terminal, tâche planifiée, service). |
| `ModuleNotFoundError` | L'un des cinq fichiers du pont manque à côté de `radio_bridge.py`. |
| `LLM error (<id>): no valid sheet for voice 'walt' in …/personas` | Mauvais dossier d'échange, ou monde pas encore chargé. |
| `HTTP 401` / `HTTP 403` | Clé refusée ou révoquée. |
| `HTTP 404` | Nom de modèle ou `OPENAI_BASE_URL` incorrects. |
| `HTTP 429` | Quota ou limite de débit du fournisseur atteints. |
| `URLError` / `TimeoutError` / `LLM budget of 60s spent` | Pas de réseau vers l'API, pare-feu, proxy, ou modèle plus lent que 60 s. |
| `LLM answer cut by the token limit` | Réponse trop longue ; elle n'est pas affichée. Ponctuel : normal. Constant : essayez un autre modèle. |
| `Expired request ignored (<id>, <n>s)` | Demande de plus de 75 s quand le pont la prend (pont lancé tard, serveur redémarré) : normal. Fréquent : file saturée, ou serveur et pont sur des horloges différentes. |
| `reply of voice '<id>' withheld: it quotes one of its secrets` | Normal : la voix allait révéler un secret ; remplacé par des parasites. |
| `Token usage journal write failed` | Le journal de consommation n'est pas inscriptible ; le pont continue. |

## Réponses lentes

- Le pont mène au plus 4 appels à l'IA à la fois ; les autres attendent. Un modèle lent et beaucoup de joueurs
  remplissent la file, et les demandes de plus de 75 s sont abandonnées.
- Choisissez un modèle plus rapide, baissez `InitiativeFrequency` ou gardez `MaxPerHour` raisonnable.
- Avec un pont vivant, le jeu attend jusqu'à 150 s : la réponse arrive tard mais n'est pas perdue.
