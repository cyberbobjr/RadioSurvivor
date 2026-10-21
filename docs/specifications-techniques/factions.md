# Équipes et mandats de négociation (E09-T03)

Module serveur `media/lua/server/RadioSurvivor/RS_Factions.lua` (garde `isClient()`), indépendant du moteur de PNJ.
Données dans l'état privé `RS_State` (`S.data.factions`), jamais en ModData globale. Banc : `tests/test_factions.py`.

## Identifiant d'équipe

Une équipe est une faction vanilla (propriétaire + membres) ; un joueur sans faction forme une équipe à lui seul.
Chaque équipe reçoit un identifiant `fac-<n>` tiré d'un compteur persistant : un identifiant n'est jamais réutilisé.

Une faction vanilla n'a ni identifiant ni événement serveur (base `multiplayer.md`). Le module sonde
`Faction.getFactions()` au plus toutes les 2 s (`Factions.POLL_MS`, depuis le tick du carnet) et relie chaque faction à
un enregistrement, dans cet ordre :

1. **Même objet Java** qu'à un sondage précédent de la session : le serveur modifie l'objet existant pour un
   renommage, un changement de propriétaire ou de membres. Renommer la faction ne change donc rien.
2. **Après un redémarrage** (enregistrement relu de l'état, pas encore relié dans la session) : même propriétaire.
3. Sinon **majorité des membres connus** de l'enregistrement (plus de la moitié présents dans la faction). L'ancien
   propriétaire reste membre après un changement de propriétaire (`Faction.setOwner`) : renommage et changement de
   propriétaire pendant l'arrêt du serveur gardent l'identifiant.
4. Sinon nouvel identifiant.

Cas limites :

| Cas | Règle |
|---|---|
| Faction renommée | Même identifiant (même objet ; après redémarrage : propriétaire ou majorité). |
| Propriétaire changé | Même identifiant ; **les mandats sont effacés** (le nouveau propriétaire désigne les siens). |
| Faction dissoute | Enregistrement `dissolved` dès le sondage suivant ; jamais réattribué. Les 64 plus récents sont gardés. |
| Dissoute puis recréée | Nouvel identifiant, même avec le même nom, le même propriétaire et les mêmes membres. |
| Deux factions homonymes | Deux identifiants : le nom n'intervient jamais dans la reconnaissance. |
| Joueur sans faction | Équipe personnelle `fac-<n>` (kind `personal`), dont il est propriétaire. Elle ne devient jamais l'identifiant d'une faction qu'il fonde ou rejoint, et redevient la sienne s'il quitte la faction. |
| Solo | Pas de faction (panneau vanilla MP seulement) : équipe personnelle de la clé `solo`, joueur propriétaire. |

Limite : une dissolution suivie d'un arrêt brutal avant le sondage suivant (moins de 2 s) laisse l'enregistrement actif ;
au redémarrage, une faction du même propriétaire le reprendrait.

## Mandats

Le propriétaire courant d'une faction désigne au plus 5 négociateurs (`Factions.MAX_NEGOTIATORS`) parmi ses membres,
dans l'onglet **Équipe** du carnet (liste des membres, rôle de chacun, boutons « Désigner négociateur » / « Retirer le
mandat » visibles du seul propriétaire). Commande client `mandate` `{member = <compte>, action = 'grant'|'revoke'}` :
le serveur relit la faction vanilla et refuse (`MandateOwner`, `MandateMember`, `MandateFull`, `State`) si l'émetteur
n'est plus le propriétaire, si le joueur visé n'est pas membre, si la liste est pleine ou si l'action est inconnue.
Un négociateur qui quitte la faction ou en devient propriétaire perd son mandat ; il ne le retrouve pas en revenant.

## API serveur (E09-T05, E12)

```lua
local Factions = require 'RadioSurvivor/RS_Factions'
Factions.idOf(player)          -- 'fac-<n>' de l'équipe du joueur (sondage borné : jusqu'à 2 s de retard)
Factions.canConclude(player)   -- ok, reason, teamId ; relit la faction vanilla au moment de l'appel
                               -- ok : reason 'owner' (propriétaire courant, ou équipe personnelle) ou 'negotiator'
                               -- refus : 'no_mandate' (membre sans mandat), 'state' (état privé absent)
Factions.list()                -- copies triées : {id, kind, state, name, owner, members, negotiators}
Factions.designate(player, member, grant) -- ok, reason ; utilisée par la commande `mandate`
Factions.sync(force)           -- sondage (true : immédiat) ; true si l'état privé a changé
```

Clé joueur : `getUsername()` sur un serveur (clé des factions vanilla), `solo` sinon.

### Accords (E09-T05, fiche [conception/accords.md](../annexes/conception/accords.md))

```lua
Factions.negotiation(player, gid)  -- offre du serveur ou nil, raison : { team, teamName, personal, role, current,
                                   -- revision, terms = { truce = { kind, scope }, alliance = ... } }
Factions.conclude(player, gid, kind, { team, revision }, { character, npc })  -- ok, raison, accord (copie)
Factions.covered(gid, playerKey)   -- crochet LivingKnox.Hooks.covered (clé = identité de personnage du carnet)
Factions.pollApplications()        -- accords devenus applicables (copies), après le passage de décision suivant
Factions.agreementOf(gid, team), Factions.agreements(), Factions.membersOnline(team, players)
Factions.cancelAgreement(gid, team) -- tests et administration seulement
```

Un accord couvre tous les membres du groupe et les membres **actuels** de l'équipe (relus par le sondage). Il est
`pending` à sa conclusion (déjà consulté par le choix de cible), puis `applicable` et annoncé quand aucun membre ne
vise plus un joueur couvert.

## Suite en jeu proposée (séance MP finale : serveur dédié + 2 clients)

1. A crée une faction « Alpha », invite B. Carnet → Équipe : A voit « Propriétaire », B « Membre sans mandat ».
2. A sélectionne B → « Désigner négociateur » : B voit son rôle passer à Négociateur (sans rouvrir le carnet).
3. A renomme la faction en « Beta » : même liste, mêmes rôles ; console serveur : `Factions.idOf` inchangé.
4. B quitte la faction : son onglet affiche « Sans faction » ; A voit le mandat disparu.
5. A transfère la propriété à B (B réinvité) : les mandats sont effacés ; B voit les boutons, A non.
6. Redémarrage du serveur après un renommage : identifiant inchangé (`/lua` ou journal de `Factions.list()`).

Solo : onglet Équipe = « Sans faction », rôle propriétaire, aucun bouton de mandat.
