*English: [AI provider configuration](../en/08-ai-provider-configuration.md)*

# Configurer le fournisseur d'IA

Le pont parle à tout fournisseur compatible avec l'**API Chat Completions d'OpenAI** : il envoie
`POST <OPENAI_BASE_URL>/chat/completions` avec `Authorization: Bearer <OPENAI_KEY>`.

## Les trois réglages

| Réglage | Sens |
|---|---|
| `OPENAI_KEY` | Votre clé d'API. |
| `OPENAI_BASE_URL` | Adresse de l'API **sans** `/chat/completions`, par exemple `https://api.openai.com/v1`. |
| `OPENAI_MODEL` | Nom du modèle chez ce fournisseur. |

Les trois sont obligatoires, sauf avec `--offline` (aucune IA, les voix répètent votre phrase).

Ils viennent des **variables d'environnement** du même nom, sinon d'un **fichier `.env`** : par défaut `.env` à côté de
`radio_bridge.py` (copie de `.env.example`), ou le fichier donné par `--env CHEMIN`. Une variable d'environnement
l'emporte sur le fichier. Format : un `NOM=valeur` par ligne, `#` pour un commentaire, `export ` accepté.

```
OPENAI_KEY=<votre clé>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<nom du modèle>
```

## Choisir un fournisseur

Tout fournisseur ou serveur local qui expose un point `/chat/completions` compatible OpenAI peut être essayé :
OpenAI, DeepSeek, OpenRouter, Mistral, ou un serveur local comme Ollama ou LM Studio. Prenez l'adresse et le nom de
modèle exacts dans la documentation du fournisseur. Un serveur local n'exige en général aucune clé : mettez une valeur
quelconque, non vide, dans `OPENAI_KEY`.

Conseils :

- Certaines voix répondent dans une structure JSON (actions comme un repère sur la carte ou une mission). Le pont
  demande le mode JSON de l'API et réessaie sans lui, ou sans `temperature`/`max_tokens`, si le fournisseur refuse un
  paramètre. Les petits modèles locaux suivent moins bien le format ; leurs réponses sont alors réduites à la parole
  seule.
- Un appel doit se terminer en **60 s** (nouvelles tentatives comprises). Un modèle lent ou un fournisseur surchargé
  donne « Rien que des parasites... » et `bridge error timeout`.
- Vérifiez l'installation par `python radio_bridge.py --test "Allô ?"` avant de jouer.

## Coût et quotas

- Chaque message radio accepté par le serveur est **un appel à l'IA** (jusqu'à deux ou trois si le fournisseur refuse
  un paramètre ou rend une réponse vide). Les appels spontanés des voix, le bulletin du soir, les dernières pages, les
  dialogues et les initiatives des PNJ sont aussi des appels.
- Limites en jeu : l'option sandbox **`MaxPerHour`** (60 par défaut, tous joueurs confondus ; `0` = illimité, à éviter
  sur un serveur public), `PlayerCooldown` (10 s), 8 demandes radio en attente au plus, un `budget=` facultatif par
  voix dans sa fiche, et des plafonds fixes de 60 dialogues de PNJ et 12 biographies par heure réelle. Voir
  [Options sandbox](09-options-sandbox.md).
- La consommation est ajoutée à `<dossier d'échange>/token_usage.jsonl` (ou `--usage-log CHEMIN`) : date UTC, modèle,
  tokens d'entrée, de sortie et total, cumuls de la session. Un compteur absent vaut `null`. Le pont n'estime aucun
  prix : multipliez par le tarif de votre fournisseur.
- **Fixez une limite de dépense mensuelle chez le fournisseur.** C'est la seule limite qui tient même si une option
  est mal réglée.

## Garder la clé secrète

- Ne collez jamais le fichier `.env`, la clé ou un journal `--debug` dans un commentaire, un ticket ou sur Discord. Le
  bandeau du pont n'affiche que `API key: configured (hidden)`.
- Sur un serveur, gardez le fichier hors des dossiers du pont, du jeu et d'échange, lisible par le seul compte du pont.
- En cas de fuite, révoquez la clé chez le fournisseur et créez-en une autre.
