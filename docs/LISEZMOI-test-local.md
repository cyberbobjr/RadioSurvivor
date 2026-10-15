# Radio Survivor : tester sans le Workshop

Merci de tester ! Cette version (0.3.0) est une **version de test** : il y aura des bugs. Ce guide installe le mod à
partir du zip, sans passer par le Workshop Steam. Project Zomboid **Build 42.21** est requis.

## 1. Contenu du zip

```
mods/
  batman_RadioSurvivor/   le mod (voix radio, carnet, PNJ Living Knox)
  batman_BeltRadio/       Belt Walkie-Talkie (requis)
  batman_SignalSmoke/     Signal Smoke (requis)
bridge/
  radio_bridge.py         le pont (programme Python qui parle à l'IA)
  npc_protocol.py
  persona_store.py
  bulletin.py
  last_pages.py
  .env.example            modèle de configuration
```

TooltipLib, requis par Belt Walkie-Talkie, n'est **pas** fourni : c'est un mod d'un autre auteur.

## 2. Installer les mods

1. Copiez les trois dossiers de `mods/` dans `%USERPROFILE%\Zomboid\mods\` (créez le dossier `mods` s'il n'existe
   pas). Vous devez obtenir par exemple `%USERPROFILE%\Zomboid\mods\batman_RadioSurvivor\42.21\mod.info`.
2. Abonnez-vous sur le Workshop Steam à **TooltipLib** :
   https://steamcommunity.com/sharedfiles/filedetails/?id=3694097672
3. Si vous êtes déjà abonné à Belt Walkie-Talkie ou à Signal Smoke sur le Workshop, désabonnez-vous pendant le test
   (deux copies du même mod se gênent) : gardez les copies du zip.
4. Lancez le jeu, menu **Mods**, et activez dans cet ordre : **TooltipLib**, **Belt Walkie-Talkie**,
   **Signal Smoke**, **Radio Survivor**. Désactivez Bandits! et Project A-Life s'ils sont actifs (incompatibles).
5. Quittez et relancez complètement le jeu.

## 3. Préparer le pont

1. Installez **Python 3.10 ou plus récent** (https://www.python.org, cochez « Add python.exe to PATH »). Vérifiez dans
   PowerShell : `python --version`. Aucun paquet à installer.
2. Dans le dossier `bridge`, copiez `.env.example` en `.env` et remplissez-le avec **votre** clé :

   ```
   OPENAI_KEY=<votre clé API>
   OPENAI_BASE_URL=https://api.openai.com/v1
   OPENAI_MODEL=<nom du modèle>
   ```

   Tout fournisseur compatible avec l'API OpenAI convient (OpenAI, DeepSeek, OpenRouter…) : prenez l'adresse et le
   nom de modèle dans sa documentation. Ne partagez jamais ce fichier. Pensez à fixer une limite de dépense chez le
   fournisseur : chaque message radio est un appel payant.
3. Ouvrez PowerShell dans le dossier `bridge` (clic droit dans le dossier → « Ouvrir dans le terminal ») et testez :

   ```powershell
   python radio_bridge.py --test "Allô, quelqu'un m'entend ?" --personas ..\mods\batman_RadioSurvivor\42.21\personas
   ```

   Quelques lignes de Walt doivent s'afficher. Sinon, lisez la dernière ligne (`Missing configuration`, `HTTP 401`
   = clé refusée, `HTTP 404` = adresse ou modèle faux). Sans clé, `--offline` vérifie le reste (Walt répète votre
   phrase).

## 4. Jouer

1. **Avant de charger la partie**, lancez le pont et laissez la fenêtre ouverte :

   ```powershell
   python radio_bridge.py
   ```

   Attendez la ligne `Bridge ready`. Le dossier d'échange par défaut est
   `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` : rien à régler en solo.
2. Commencez une **nouvelle partie** (conseillé). Les pages sandbox **Radio Survivor** et **Living Knox** peuvent rester
   par défaut.
3. Arrêtez le pont par **Ctrl+C** après avoir quitté la partie.

Sans pont, le jeu reste jouable, mais les voix ne répondent que « Rien que des parasites... » et les PNJ restent muets.

## 5. Quoi tester

- **Walt à la radio** : trouvez une note de fréquence dans le butin (clic droit → **Inspecter** ; la page de journal
  radio de Walt). Prenez un talkie **en main** (pas à la ceinture), allumez-le, réglez-le sur la fréquence, ouvrez le
  micro, puis tapez une phrase dans la section **Émettre** de la fenêtre de la radio. La réponse arrive en quelques
  secondes ; le terminal du pont affiche votre phrase.
- **Un groupe de survivants** : approchez-vous d'un PNJ humain, appuyez sur **Ctrl+G**, puis parlez dans le chat local
  (`/say`). Ouvrez le **Carnet** (bouton de la barre latérale) : contacts, missions, réputation.
- **Une mission** : demandez du travail à un PNJ ou à une voix, acceptez-la dans le carnet, remplissez-la, puis revenez
  en rendre compte.

Notez ce qui vous surprend : réponses bizarres, PNJ bloqués, erreurs rouges, lenteurs.

## 6. Journaux à renvoyer

- `%USERPROFILE%\Zomboid\console.txt` (journal du jeu de la dernière session ; copiez-le **avant** de relancer le jeu,
  il est écrasé à chaque lancement).
- La sortie du pont : copiez le texte de la fenêtre, ou lancez-le dès le départ avec
  `python radio_bridge.py > bridge.log 2>&1` (la fenêtre reste alors vide : tout part dans le fichier) et renvoyez
  `bridge.log`.
- N'envoyez **jamais** votre `.env` ni un journal lancé avec `--debug` (il contient vos dialogues complets).
