*English: [[The bridge in singleplayer|Bridge-in-Singleplayer]]*

# Le pont en solo

Le Lua de Project Zomboid n'a aucun accès réseau. Le jeu écrit les demandes dans un fichier texte, le pont appelle
l'IA et écrit les réponses :

```
jeu → requests.txt → pont → API de l'IA
jeu ← responses.txt ← pont
```

En solo (et dans une partie hébergée depuis le menu), le pont tourne **sur votre PC**, dans une fenêtre de terminal
laissée ouverte pendant la partie.

## 1. Ce qu'il faut

- **Python 3.10 ou plus récent** (`python --version`). Aucun paquet à installer : le pont n'utilise que la
  bibliothèque standard.
- Les **cinq fichiers du pont**, gardés ensemble dans un même dossier : `radio_bridge.py`, `npc_protocol.py`,
  `persona_store.py`, `bulletin.py`, `last_pages.py`, plus `.env.example`. Prenez le pont de la même version que le
  mod.
- Une **clé d'API** d'un fournisseur compatible avec l'API OpenAI : voir
  [[Configurer le fournisseur d'IA|AI-Provider-Configuration-FR]]. Inutile avec `--offline`.

## 2. La clé

Dans le dossier du pont, copiez `.env.example` en `.env` et remplissez-le :

```
OPENAI_KEY=<votre clé>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<nom du modèle>
```

Ne partagez jamais ce fichier. Une variable d'environnement du même nom l'emporte sur lui ; un autre fichier se
désigne par `--env CHEMIN`.

## 3. Vérifier sans le jeu

Ouvrez un terminal dans le dossier du pont :

```powershell
python radio_bridge.py --test "Allô ?" --personas "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas"
```

Quelques lignes de Walt s'affichent : clé, adresse et modèle sont bons. Le dossier `personas` est rempli par le jeu au
premier chargement d'un monde ; avant cela, faites pointer `--personas` vers le dossier `42.21\personas` du mod
installé (dans le dossier du Workshop Steam) ou, depuis le dépôt de développement du mod, omettez l'option. Ajoutez
`--offline` pour vérifier sans clé (la voix répète votre phrase).

## 4. Le lancer

```powershell
python radio_bridge.py
```

Le bandeau affiche la configuration effective (la clé reste masquée), puis `Bridge ready, model …, directory …` et
`Waiting for game requests (Ctrl+C to stop)`. Chargez votre partie ; l'ordre (jeu ou pont d'abord) est indifférent.

- Dossier d'échange par défaut : `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` (le pont le crée au besoin). Si
  vous lancez le jeu avec `-cachedir=X`, ajoutez `--exchange "X\Lua\batman_RadioSurvivor"`.
- Tant qu'il tourne, le pont rafraîchit `bridge-alive.txt` dans ce dossier toutes les 5 s ; le jeu attend alors
  jusqu'à 150 s une réponse lente au lieu de passer au secours après 90 s.
- Arrêt par **Ctrl+C** (`Bridge stopped`).
- Un **seul** pont par dossier : un second refuse de démarrer.

## Options utiles

| Option | Rôle |
|---|---|
| `--offline` | Sans IA, sans clé, sans coût : les voix répètent votre phrase. Pour tester l'installation. |
| `--debug` | Journal complet dans le terminal, prompts et dialogues compris : ne pas le partager tel quel. |
| `--test "TEXTE"` | Un échange en console, sans le jeu ; `--voice ID` pour une autre voix que `walt`. |
| `--env CHEMIN` | Autre fichier de réglages. |
| `--exchange CHEMIN` | Autre dossier d'échange. |
| `--usage-log CHEMIN` | Autre journal de consommation (défaut `<exchange>/token_usage.jsonl`). |
| `--poll SECONDES` | Intervalle de lecture de `requests.txt` (défaut 0,3). |
| `--help` | Aide complète. |

Pour garder le journal dans un fichier : `python radio_bridge.py > bridge.log 2>&1`.

## Sans le pont

Le jeu reste jouable : la radio répond « Rien que des parasites... », le bulletin du soir et les dernières pages
prennent de courts textes fixes écrits par le jeu, et les PNJ restent muets. Voir [[Dépannage|Troubleshooting-FR]].
