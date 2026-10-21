# RadioSurvivor — consignes du projet

Le `CLAUDE.md` du dossier `%USERPROFILE%\Zomboid\Workshop` s'applique (règle immuable sur le Workshop Steam, base de connaissances obligatoire, réponses en français).

Un seul mod, `batman_RadioSurvivor` : la radio de Walt, le carnet et, depuis la fusion du 2026-10-08, le moteur de PNJ **Living Knox** (ancien projet `LivingKnox`, préfixe de plan `LK`, code prévu sous `media/lua/*/LivingKnox/`).

- Le développement suit le plan `docs/annexes/plans/` : méthode dans [docs/annexes/plans/README.md](docs/annexes/plans/README.md), état généré dans [docs/annexes/plans/SUIVI.md](docs/annexes/plans/SUIVI.md), prochaine tâche par `python RadioSurvivor/tools/plan.py next` (skill `radiosurvivor-plan`). Préfixes : `E` (radio, carnet, missions) et `LK` (moteur de PNJ).
- Une tâche à la fois ; les décisions `à décider` se posent à l'utilisateur avant tout code.
- Avant de déclarer une tâche testée : `tests/test_protocol.py`, `tests/test_carnet.py`, luacheck (sans nouvel avertissement) et `tools/plan.py check`.
- **Écriture indépendante (Living Knox)** : ne jamais copier, traduire ligne à ligne ni paraphraser du code de Bandits! (`3268487204`) ou de Project A-Life (`3803984183`). Sources de conception autorisées : Java et Lua vanilla 42.21, base `.claude/pz-knowledge`, nos propres essais. Les analyses `docs/annexes/recherches/bandits-analyse.md` et `docs/annexes/recherches/alife-analyse.md` servent de retour d'expérience (problèmes à prévoir), pas de modèle de code. L'ancien adaptateur Bandits! (`RS_Bandits.lua`) a été retiré le 2026-10-08 (`E17-T02`) : le carnet ne passe plus que par l'interface `RS_NPCProvider`.
- Dépôt GitHub **public** `cyberbobjr/RadioSurvivor` (MIT, créé le 2026-10-15 sans historique ; branches `main` et `dev`, travail sur `dev`). L'ancien dépôt privé, avec tout l'historique (548 commits, fusion de LivingKnox), est archivé sous `cyberbobjr/RadioSurvivor-dev` (remote local `archive`, branches locales `archive-dev` et `archive-main`) : **ne jamais pousser `archive-*` vers `origin`**.
