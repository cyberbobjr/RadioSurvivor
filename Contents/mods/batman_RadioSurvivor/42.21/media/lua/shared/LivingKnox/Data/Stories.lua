-- Living Knox : gabarits d'histoire des groupes (LK10-T01), en anglais et en français. Fiche : docs/annexes/conception/recits.md.
-- Données seules, combinées par le serveur (media/lua/server/LivingKnox/LK_Stories.lua). Le jeu exécute aussi ce
-- fichier sur les clients : il ne contient que des gabarits, jamais l'histoire tirée pour un groupe ni ses secrets.
--
-- Fragment : { id = <unique dans sa liste>, types = { <type de groupe>, ... } (absent = tous les types),
--              tags = { <étiquette>, ... }, excludes = { <étiquette>, ... }, requires = { <étiquette>, ... },
--              en = <texte anglais>, fr = <texte français>, frF = <texte français au féminin> (passés de chef) }
-- Compatibilité : deux fragments s'excluent si l'un porte une étiquette de la liste excludes de l'autre ; un fragment
-- avec requires n'est tiré que si l'un des fragments déjà choisis porte au moins une de ces étiquettes.
-- Ordre du tirage : origine, motivation, ton, passé du chef, secrets.
--
-- Contexte : Knox Country, Kentucky, juillet 1993, quelques semaines après le début de l'épidémie.
-- Formes des textes (composition du résumé, LK_Stories.summary) :
--   origine, motivation, ton : une phrase complète, sujet « ils » / « they » ;
--   passé du chef : apposition après le nom (« Leur chef est <nom>, <passé>. », « Their leader is <name>, <past>. ») :
--     en anglais avec article, en français sans article ; frF au féminin quand le chef est une femme (fr sinon) ;
--   secret : une phrase complète.
-- Littéraux français en échappements d'octets UTF-8 (\195\169 = é) : Kahlua remplace tout octet non ASCII écrit en
-- clair (base .claude/pz-knowledge/kahlua-lua.md, « Littéraux non ASCII »).
-- Repères : é \195\169, è \195\168, ê \195\170, à \195\160, â \195\162, ç \195\167, ô \195\180, î \195\174, ï \195\175,
-- ù \195\185.
require "LivingKnox/LK_Core"

local Data = {}
LivingKnox.StoryData = Data

Data.FORMAT = 1

-- Origines : comment le groupe s'est formé.
Data.origins = {
    { id = "church_basement", types = { "settlers", "neutrals" }, tags = { "faith" },
      en = "They first gathered in the basement of a Baptist church in Riverside, where the pastor kept the door open"
          .. " to anyone who knocked.",
      fr = "Ils se sont d'abord r\195\169unis au sous-sol d'une \195\169glise baptiste de Riverside, o\195\185 le"
          .. " pasteur laissait la porte ouverte \195\160 quiconque frappait." },
    { id = "county_road", types = { "settlers" }, tags = { "farm" },
      en = "They are three families from the same county road near Rosewood who pooled their livestock, tools and"
          .. " well water when the phones went dead.",
      fr = "Ce sont trois familles du m\195\170me chemin de comt\195\169, pr\195\168s de Rosewood, qui ont mis en"
          .. " commun b\195\170tes, outils et eau du puits quand les t\195\169l\195\169phones se sont tus." },
    { id = "evacuation_line", tags = { "evacuees" },
      en = "They met in the crowd waiting for the evacuation buses outside the Muldraugh school; the buses never came,"
          .. " and they walked away together.",
      fr = "Ils se sont rencontr\195\169s dans la foule qui attendait les cars d'\195\169vacuation devant l'\195\169cole"
          .. " de Muldraugh ; les cars ne sont jamais venus et ils sont repartis ensemble." },
    { id = "work_release", types = { "raiders" }, tags = { "crime" },
      en = "Most of them walked out of a county work-release program when the guards stopped showing up for their"
          .. " shifts.",
      fr = "La plupart sont sortis d'un programme de semi-libert\195\169 du comt\195\169 quand les gardiens ont"
          .. " cess\195\169 de venir prendre leur service." },
    { id = "roadblock", types = { "raiders", "neutrals" }, tags = { "military" },
      en = "They were National Guard reservists posted at a roadblock on the edge of the quarantine zone, until the"
          .. " radio went silent for six days straight.",
      fr = "C'\195\169taient des r\195\169servistes de la Garde nationale post\195\169s \195\160 un barrage au bord de"
          .. " la zone de quarantaine, jusqu'\195\160 ce que la radio se taise six jours d'affil\195\169e." },
    { id = "night_shift", types = { "settlers", "neutrals" }, tags = { "workers" },
      en = "They stocked shelves together on the night shift at a supermarket and barricaded themselves in the"
          .. " stockroom when the trouble reached town.",
      fr = "Ils faisaient ensemble la mise en rayon de nuit dans un supermarch\195\169 et se sont barricad\195\169s"
          .. " dans la r\195\169serve quand les ennuis ont atteint la ville." },
    { id = "trailer_park", tags = { "neighbors" },
      en = "They come from the same trailer park off the highway: neighbors who never much liked each other, but"
          .. " liked being alone even less.",
      fr = "Ils viennent du m\195\170me parc de mobile homes au bord de la nationale : des voisins qui ne s'aimaient"
          .. " gu\195\168re, mais qui aimaient encore moins rester seuls." },
    { id = "clinic", types = { "settlers", "neutrals" }, tags = { "medical" },
      en = "They are what is left of the staff and patients of a small clinic that held out until the generator ran"
          .. " dry.",
      fr = "C'est ce qui reste du personnel et des patients d'une petite clinique qui a tenu jusqu'\195\160 ce que"
          .. " le groupe \195\169lectrog\195\168ne tombe \195\160 sec." },
    { id = "bar_regulars", types = { "raiders", "neutrals" }, tags = { "bar" },
      en = "They were the regulars of a bar out on the county line, and they still drink, fight and decide"
          .. " everything together.",
      fr = "C'\195\169taient les habitu\195\169s d'un bar \195\160 la limite du comt\195\169 ; ils boivent, se"
          .. " battent et d\195\169cident encore tout ensemble." },
    { id = "campground", types = { "settlers", "neutrals" }, tags = { "strangers" },
      en = "They were strangers at a lakeside campground who stayed put when the news on their car radios turned to"
          .. " static.",
      fr = "C'\195\169taient des inconnus d'un camping au bord du lac, rest\195\169s sur place quand les nouvelles des"
          .. " autoradios se sont chang\195\169es en gr\195\169sillements." },
    { id = "pharmacy_run", types = { "raiders" }, tags = { "plunder" },
      en = "It started as a handful of people raiding the pharmacies of Muldraugh in the first week, and they found"
          .. " they were good at it.",
      fr = "Au d\195\169but, ce n'\195\169tait qu'une poign\195\169e de gens qui pillaient les pharmacies de"
          .. " Muldraugh ; ils ont d\195\169couvert qu'ils \195\169taient dou\195\169s pour \195\167a." },
    { id = "flea_market", types = { "neutrals" }, tags = { "trade" },
      en = "They were vendors at a weekend flea market who kept on bartering long after money stopped meaning"
          .. " anything.",
      fr = "C'\195\169taient des marchands d'un march\195\169 aux puces du week-end, qui ont continu\195\169 \195\160"
          .. " troquer bien apr\195\168s que l'argent a perdu toute valeur." },
    -- LK10-T05 (2026-10-10) : origines ajoutées pour que deux groupes d'une même population partagent moins souvent
    -- la leur (tirage inchangé) ; lieux génériques ou vérifiés (base knox-geography.md), aucun véhicule à poser.
    { id = "school_gym", types = { "settlers", "neutrals" }, tags = { "shelter" },
      en = "They slept on cots in a high school gym the Red Cross had opened as a shelter, and stayed on after the"
          .. " last volunteers left.",
      fr = "Ils dormaient sur des lits de camp dans le gymnase d'un lyc\195\169e transform\195\169 en abri par la"
          .. " Croix-Rouge, et y sont rest\195\169s apr\195\168s le d\195\169part des derniers b\195\169n\195\169voles." },
    { id = "farm_hands", types = { "settlers" }, tags = { "farm" },
      en = "They were seasonal hands bringing in the summer harvest on a farm outside Echo Creek, and the family that"
          .. " hired them asked them to stay.",
      fr = "C'\195\169taient des saisonniers venus pour les r\195\169coltes d'\195\169t\195\169 dans une ferme pr\195\168s"
          .. " d'Echo Creek ; la famille qui les employait leur a demand\195\169 de rester." },
    { id = "firefighters", types = { "settlers", "neutrals" }, tags = { "rescue" },
      en = "They are volunteer firefighters from a rural station and the neighbors who ran to them; their engine was"
          .. " left on a road choked with wrecks.",
      fr = "Ce sont des pompiers volontaires d'une caserne de campagne et les voisins venus se r\195\169fugier chez"
          .. " eux ; leur camion est rest\195\169 sur une route encombr\195\169e d'\195\169paves." },
    { id = "retirement_home", types = { "settlers" }, tags = { "care" },
      en = "They are the staff of a retirement home who refused to leave the residents behind, and the few residents"
          .. " still alive.",
      fr = "C'est le personnel d'une maison de retraite qui a refus\195\169 d'abandonner ses pensionnaires, et les"
          .. " quelques pensionnaires encore en vie." },
    { id = "motel_guests", types = { "settlers", "neutrals" }, tags = { "strangers" },
      en = "They were guests stranded at a motel off the highway when the roads closed, and the night manager still"
          .. " keeps the key to every room.",
      fr = "C'\195\169taient des clients d'un motel au bord de la nationale, bloqu\195\169s quand les routes ont"
          .. " \195\169t\195\169 ferm\195\169es ; le g\195\169rant de nuit garde encore la cl\195\169 de chaque"
          .. " chambre." },
    { id = "turned_back", tags = { "cordon" }, excludes = { "hope", "despair" },
      en = "They tried to slip through the cordon together near the river, were turned back by gunfire, and no longer"
          .. " believe anyone is coming for them.",
      fr = "Ils ont tent\195\169 ensemble de franchir le cordon pr\195\168s du fleuve, ont \195\169t\195\169"
          .. " repouss\195\169s par des tirs et ne croient plus que quiconque viendra les chercher." },
    { id = "county_jail", types = { "raiders" }, tags = { "crime" },
      en = "They were locked up in the county jail when the last deputy on duty opened the cells and ran for it.",
      fr = "Ils \195\169taient enferm\195\169s \195\160 la prison du comt\195\169 quand le dernier adjoint de garde a"
          .. " ouvert les cellules et pris la fuite." },
    { id = "looting_night", types = { "raiders" }, tags = { "plunder" },
      en = "They met while looting the same electronics store on the first night, and decided that splitting the take"
          .. " beat fighting over it.",
      fr = "Ils se sont rencontr\195\169s en pillant le m\195\170me magasin d'\195\169lectronique la premi\195\168re"
          .. " nuit, et ont jug\195\169 plus simple de partager le butin que de se battre pour lui." },
    { id = "hunting_club", types = { "raiders", "neutrals" }, tags = { "hunters" },
      en = "They belong to a hunting club that sat out the first weeks at its cabin in the woods, then came back down"
          .. " well armed.",
      fr = "Ils font partie d'un club de chasse qui a pass\195\169 les premi\195\168res semaines dans son chalet en"
          .. " for\195\170t, avant de redescendre bien arm\195\169s." },
    { id = "warehouse_guards", types = { "raiders" }, tags = { "crime" },
      en = "They were night guards at a distribution warehouse, and started selling what they were paid to protect"
          .. " once the owners stopped calling.",
      fr = "C'\195\169taient des gardiens de nuit d'un entrep\195\180t de distribution ; ils ont commenc\195\169"
          .. " \195\160 vendre ce qu'on les payait pour prot\195\169ger quand les patrons ont cess\195\169 d'appeler." },
    { id = "radio_hams", types = { "neutrals" }, tags = { "radio" },
      en = "They found each other on the amateur radio bands in the first week, and agreed to meet at the house with"
          .. " the tallest antenna.",
      fr = "Ils se sont trouv\195\169s sur les bandes radioamateurs d\195\168s la premi\195\168re semaine, et ont"
          .. " convenu de se retrouver chez celui qui avait la plus haute antenne." },
    { id = "bottling_plant", types = { "raiders", "neutrals" }, tags = { "workers" },
      en = "They worked the same line at a bottling plant and held out in its break room for nine days before walking"
          .. " out together.",
      fr = "Ils travaillaient sur la m\195\170me cha\195\174ne dans une usine d'embouteillage et ont tenu neuf jours"
          .. " dans la salle de pause avant de partir ensemble." },
}

-- Motivations : ce que le groupe veut maintenant.
Data.motivations = {
    { id = "hold_ground", types = { "settlers" }, tags = { "defense" },
      en = "Now they mean to hold their ground, get a late crop in before summer ends and sit out the winter.",
      fr = "D\195\169sormais, ils comptent tenir leur terrain, semer avant la fin de l'\195\169t\195\169 et passer"
          .. " l'hiver sans bouger." },
    { id = "find_relatives", types = { "settlers", "neutrals" }, tags = { "kin" },
      en = "They are still searching for relatives who were in Louisville when the cordon went up.",
      fr = "Ils cherchent encore des proches qui se trouvaient \195\160 Louisville quand le cordon a \195\169t\195\169"
          .. " dress\195\169." },
    { id = "wait_army", types = { "settlers", "neutrals" }, tags = { "hope" },
      en = "They are waiting for the army to come back for them, and keep a radio on day and night in case it does.",
      fr = "Ils attendent le retour de l'arm\195\169e et gardent une radio allum\195\169e jour et nuit, au cas"
          .. " o\195\185." },
    { id = "trade", types = { "neutrals" }, tags = { "trade" },
      en = "They want to trade fuel, batteries and medicine for food, with anyone who keeps their word.",
      fr = "Ils veulent commercer : carburant, piles et m\195\169dicaments contre de la nourriture, avec quiconque"
          .. " tient parole." },
    { id = "plunder", types = { "raiders" }, tags = { "violent", "plunder" },
      en = "They take what they need from whoever is weaker, and they have stopped asking first.",
      fr = "Ils prennent ce qu'il leur faut \195\160 plus faible qu'eux, et ils ne prennent plus la peine de"
          .. " demander." },
    { id = "road_toll", types = { "raiders" }, tags = { "violent", "power" },
      en = "They want the roads between Muldraugh and West Point to be theirs, with a toll paid in food and fuel.",
      fr = "Ils veulent que les routes entre Muldraugh et West Point leur appartiennent, avec un p\195\169age"
          .. " pay\195\169 en vivres et en carburant." },
    { id = "leave_knox", tags = { "travel" },
      en = "They want out of Knox Country, and are gathering fuel and road maps for a run past the cordon.",
      fr = "Ils veulent quitter le comt\195\169 de Knox et rassemblent carburant et cartes routi\195\168res pour"
          .. " passer le cordon." },
    { id = "cure_rumors", types = { "settlers", "neutrals" }, tags = { "hope", "medical" },
      en = "They believe someone, somewhere, is close to a cure, and they write down everything they hear about it.",
      fr = "Ils croient que quelqu'un, quelque part, est pr\195\168s d'un rem\195\168de, et ils notent tout ce"
          .. " qu'ils entendent \195\160 ce sujet." },
    { id = "revenge", types = { "raiders" }, tags = { "violent" },
      en = "They are hunting the group that burned them out of their first shelter, and treat every stranger as a"
          .. " suspect.",
      fr = "Ils traquent le groupe qui a incendi\195\169 leur premier abri et voient un suspect en chaque"
          .. " inconnu." },
    { id = "hoard", types = { "raiders", "neutrals" }, tags = { "hoard" },
      en = "They hoard ammunition and canned food as if the worst were still to come, and maybe it is.",
      fr = "Ils amassent munitions et conserves comme si le pire restait \195\160 venir, et c'est peut-\195\170tre"
          .. " le cas." },
    { id = "take_in", types = { "settlers" }, tags = { "care" },
      en = "They take in survivors who can work, and turn away no one who shows up with children.",
      fr = "Ils accueillent les survivants capables de travailler et ne refusent personne qui arrive avec des"
          .. " enfants." },
    { id = "own_town", types = { "raiders" }, tags = { "violent", "power" },
      en = "They want a town of their own to run, with people to work it and nobody to argue.",
      fr = "Ils veulent une ville bien \195\160 eux, avec des gens pour la faire tourner et personne pour"
          .. " discuter." },
    -- LK10-T05 (2026-10-10).
    { id = "clear_streets", types = { "settlers", "neutrals" }, tags = { "defense" },
      en = "They mean to clear a few streets of the dead, house by house, and barricade them for good.",
      fr = "Ils comptent vider quelques rues des morts qui y errent, maison par maison, puis les barricader pour de"
          .. " bon." },
    { id = "recruit", types = { "raiders" }, tags = { "violent", "power" },
      en = "They are recruiting anyone who can handle a gun, and they do not take no for an answer.",
      fr = "Ils recrutent quiconque sait tenir une arme, et ils n'acceptent pas qu'on leur dise non." },
    { id = "bury_dead", types = { "settlers", "neutrals" }, tags = { "grief" },
      en = "They go back to the places they fled to bury their dead properly, one name at a time.",
      fr = "Ils retournent dans les lieux qu'ils ont fuis pour enterrer dignement leurs morts, un nom apr\195\168s"
          .. " l'autre." },
}

-- Tons : comment le groupe se conduit, surtout envers les inconnus.
Data.tones = {
    { id = "peaceful", types = { "settlers", "neutrals" }, tags = { "peaceful" },
      excludes = { "violent", "power" },
      en = "They avoid a fight whenever they can, and share their water with anyone who comes unarmed.",
      fr = "Ils \195\169vitent le combat chaque fois qu'ils le peuvent et partagent leur eau avec quiconque vient"
          .. " sans arme." },
    { id = "wary", tags = { "wary" }, excludes = { "plunder" },
      en = "They are wary of strangers, but fair with those who keep their hands where they can be seen.",
      fr = "Ils se m\195\169fient des inconnus, mais restent justes avec ceux qui gardent les mains bien en vue." },
    { id = "devout", types = { "settlers", "neutrals" }, tags = { "faith" }, excludes = { "violent", "plunder" },
      en = "They pray before every meal and read the epidemic as a judgment, though they cannot agree on what it"
          .. " punishes.",
      fr = "Ils prient avant chaque repas et voient dans l'\195\169pid\195\169mie un jugement, sans s'accorder sur ce"
          .. " qu'il punit." },
    { id = "ruthless", types = { "raiders" }, tags = { "violent" }, excludes = { "peaceful", "care", "faith" },
      en = "At night they shoot first, and they keep no prisoner they cannot feed.",
      fr = "La nuit, ils tirent les premiers et ne gardent aucun prisonnier qu'ils ne peuvent pas nourrir." },
    { id = "desperate", tags = { "desperate" }, excludes = { "power", "hoard" },
      en = "They are hungry and short of everything, which makes them unpredictable.",
      fr = "Ils ont faim et manquent de tout, ce qui les rend impr\195\169visibles." },
    { id = "businesslike", types = { "raiders", "neutrals" }, tags = { "trade" },
      en = "Nothing comes free with them: everything has a price, even directions or a night behind their walls.",
      fr = "Ils ne font rien pour rien : tout a un prix, m\195\170me un renseignement ou une nuit \195\160 l'abri"
          .. " de leurs murs." },
    { id = "disciplined", tags = { "military" },
      en = "They stand watches, ration by the book and follow orders without argument.",
      fr = "Ils montent la garde, rationnent les vivres selon le r\195\168glement et ob\195\169issent aux ordres"
          .. " sans discuter." },
    { id = "grieving", types = { "settlers", "neutrals" }, tags = { "grief" }, excludes = { "power" },
      en = "They have lost too many of their own to talk about it, and they are rarely heard laughing.",
      fr = "Ils ont perdu trop des leurs pour en parler, et on les entend rarement rire." },
    { id = "boastful", types = { "raiders" }, tags = { "violent" }, excludes = { "peaceful" },
      en = "Loud and boastful, they paint their name on the walls of every place they strip.",
      fr = "Bruyants et fanfarons, ils peignent leur nom sur les murs des lieux qu'ils d\195\169pouillent." },
}

-- Passés du chef : apposition après son nom.
Data.leaderPasts = {
    { id = "deputy", tags = { "law" },
      en = "a former sheriff's deputy who stopped answering the dispatcher on the third night",
      fr = "ancien adjoint du sh\195\169rif qui a cess\195\169 de r\195\169pondre au standard la troisi\195\168me nuit",
      frF = "ancienne adjointe du sh\195\169rif qui a cess\195\169 de r\195\169pondre au standard la"
          .. " troisi\195\168me nuit" },
    { id = "preacher", types = { "settlers", "neutrals" }, tags = { "faith" },
      en = "a lay preacher who still holds a service every Sunday",
      fr = "pr\195\169dicateur la\195\175c qui c\195\169l\195\168bre encore un office chaque dimanche",
      frF = "pr\195\169dicatrice la\195\175que qui c\195\169l\195\168bre encore un office chaque dimanche" },
    { id = "tobacco_farmer", types = { "settlers" }, tags = { "farm" },
      en = "a tobacco farmer who knows every back road in the county",
      fr = "planteur de tabac qui conna\195\174t chaque chemin de traverse du comt\195\169",
      frF = "planteuse de tabac qui conna\195\174t chaque chemin de traverse du comt\195\169" },
    { id = "nurse", types = { "settlers", "neutrals" }, tags = { "medical", "care" },
      en = "a night-shift nurse who drove down from Louisville to see family and never went back",
      fr = "infirmier de nuit venu de Louisville voir sa famille et jamais reparti",
      frF = "infirmi\195\168re de nuit venue de Louisville voir sa famille et jamais repartie" },
    { id = "gulf_veteran", tags = { "military" },
      en = "a Gulf War veteran who came home two years ago and never really settled",
      fr = "v\195\169t\195\169ran de la guerre du Golfe, rentr\195\169 il y a deux ans sans jamais vraiment se poser",
      frF = "v\195\169t\195\169rane de la guerre du Golfe, rentr\195\169e il y a deux ans sans jamais vraiment se"
          .. " poser" },
    { id = "ex_convict", types = { "raiders" }, tags = { "crime" },
      en = "an ex-convict who did six years at Eddyville for armed robbery",
      fr = "ancien d\195\169tenu qui a purg\195\169 six ans \195\160 Eddyville pour vol \195\160 main arm\195\169e",
      frF = "ancienne d\195\169tenue qui a purg\195\169 six ans \195\160 Eddyville pour vol \195\160 main"
          .. " arm\195\169e" },
    { id = "foreman", types = { "settlers", "neutrals" }, tags = { "workers" },
      en = "a construction foreman used to shouting orders over the noise",
      fr = "ancien chef de chantier habitu\195\169 \195\160 crier ses ordres par-dessus le bruit",
      frF = "ancienne chef de chantier habitu\195\169e \195\160 crier ses ordres par-dessus le bruit" },
    { id = "mechanic", tags = { "skills" },
      en = "a mechanic who can fix a generator or a pump with whatever is lying around",
      fr = "m\195\169canicien capable de r\195\169parer un groupe \195\169lectrog\195\168ne ou une pompe avec ce qui"
          .. " tra\195\174ne",
      frF = "m\195\169canicienne capable de r\195\169parer un groupe \195\169lectrog\195\168ne ou une pompe avec ce"
          .. " qui tra\195\174ne" },
    { id = "chemistry_teacher", types = { "settlers", "neutrals" }, tags = { "care" },
      en = "a high school chemistry teacher who still talks to everyone like a class",
      fr = "prof de chimie au lyc\195\169e qui parle encore \195\160 tout le monde comme \195\160 une classe" },
    { id = "small_dealer", types = { "raiders", "neutrals" }, tags = { "crime" },
      en = "a small-time dealer who knows where every pharmacy in the county keeps its stock",
      fr = "petit trafiquant qui sait o\195\185 chaque pharmacie du comt\195\169 range ses stocks",
      frF = "petite trafiquante qui sait o\195\185 chaque pharmacie du comt\195\169 range ses stocks" },
    { id = "trucker", types = { "raiders", "neutrals" }, tags = { "outsider" },
      en = "a long-haul trucker who was passing through Knox when the cordon went up, and never found a way out",
      fr = "routier au long cours qui traversait Knox quand le cordon a \195\169t\195\169 dress\195\169, et n'a"
          .. " jamais trouv\195\169 d'issue",
      frF = "routi\195\168re au long cours qui traversait Knox quand le cordon a \195\169t\195\169 dress\195\169, et"
          .. " n'a jamais trouv\195\169 d'issue" },
    { id = "guard_sergeant", types = { "raiders", "neutrals" }, tags = { "military" },
      en = "a National Guard sergeant who decided the chain of command ended when the radio went quiet",
      fr = "sergent de la Garde nationale qui a d\195\169cid\195\169 que la cha\195\174ne de commandement"
          .. " s'arr\195\170tait au silence de la radio" },
    { id = "bouncer", types = { "raiders" }, tags = { "violent" },
      en = "a bar bouncer from Muldraugh who learned that people listen to the biggest one in the room",
      fr = "ancien videur d'un bar de Muldraugh qui a appris qu'on \195\169coute toujours le plus costaud de la"
          .. " salle",
      frF = "ancienne videuse d'un bar de Muldraugh qui a appris qu'on \195\169coute toujours la plus costaude de"
          .. " la salle" },
    { id = "hardware_store", types = { "settlers", "neutrals" }, tags = { "trade" },
      en = "the owner of a hardware store who writes down every nail handed out",
      fr = "patron d'une quincaillerie qui note dans un registre chaque clou distribu\195\169",
      frF = "patronne d'une quincaillerie qui note dans un registre chaque clou distribu\195\169" },
}

-- Secrets : PRIVÉS (serveur seulement, jamais envoyés aux clients ni mis en ModData globale ; LK_Stories.publicView).
Data.secrets = {
    { id = "hidden_bite", tags = { "bite" },
      en = "Their leader is hiding a bite under a bandage and has told no one.",
      fr = "Leur chef cache une morsure sous un bandage et n'en a parl\195\169 \195\160 personne." },
    { id = "leader_cache", tags = { "cache" },
      en = "Their leader keeps a cache of food and ammunition that most of the group knows nothing about.",
      fr = "Leur chef garde une cache de vivres et de munitions dont la plupart des membres ignorent tout." },
    { id = "family_killed", types = { "raiders", "neutrals" }, tags = { "violent" },
      en = "They killed a family on the Rosewood road for their car and swore never to speak of it.",
      fr = "Ils ont tu\195\169 une famille sur la route de Rosewood pour sa voiture et ont jur\195\169 de ne jamais"
          .. " en parler." },
    { id = "informer", tags = { "betrayal" },
      en = "One of them sells news of the others to a rival group for batteries.",
      fr = "L'un d'eux vend des nouvelles des autres \195\160 un groupe rival contre des piles." },
    { id = "nobody_coming", types = { "settlers", "neutrals" }, tags = { "despair" },
      en = "Two of them heard a military broadcast saying nobody is coming for Knox, and have kept it from the rest.",
      fr = "Deux d'entre eux ont entendu une \195\169mission militaire annon\195\167ant que personne ne viendrait pour"
          .. " Knox, et l'ont cach\195\169 aux autres." },
    { id = "gang_debt", types = { "raiders" }, tags = { "debt" },
      en = "They owe a bigger gang a cut of everything they take, and the last payment is late.",
      fr = "Ils doivent \195\160 une bande plus puissante une part de tout ce qu'ils prennent, et le dernier"
          .. " versement est en retard." },
    { id = "fake_medicine", types = { "settlers", "neutrals" }, tags = { "medical" },
      en = "Most of their medicine is expired pills passed off as antibiotics.",
      fr = "Leur r\195\169serve de m\195\169dicaments n'est en grande partie que des cachets p\195\169rim\195\169s"
          .. " pr\195\169sent\195\169s comme des antibiotiques." },
    { id = "deserters", types = { "raiders", "neutrals" }, tags = { "military" }, requires = { "military" },
      en = "Some of them deserted their post on the cordon and would face a firing squad if the army caught them.",
      fr = "Certains ont d\195\169sert\195\169 leur poste au cordon et seraient fusill\195\169s si l'arm\195\169e les"
          .. " retrouvait." },
    { id = "cast_out", types = { "settlers" }, tags = { "cast_out" },
      en = "They drove a sick member out in the night, and the others were told he had left on his own.",
      fr = "Ils ont chass\195\169 un malade en pleine nuit, et l'on a dit aux autres qu'il \195\169tait parti de"
          .. " lui-m\195\170me." },
    { id = "bad_well", types = { "settlers" }, tags = { "water" },
      en = "Their well is going bad, and only the leader knows how little clean water is left.",
      fr = "Leur puits se g\195\162te, et seul leur chef sait combien il reste peu d'eau potable." },
    { id = "hostage", types = { "raiders" }, tags = { "violent" },
      en = "They are holding a man from another group in a locked cellar and have not decided what to do with him.",
      fr = "Ils retiennent un homme d'un autre groupe dans une cave ferm\195\169e \195\160 cl\195\169 et n'ont pas"
          .. " d\195\169cid\195\169 de son sort." },
    { id = "split_brewing", tags = { "betrayal" },
      en = "Half the group is ready to slip away with the fuel and the guns the next time the leader is away.",
      fr = "La moiti\195\169 du groupe est pr\195\170te \195\160 filer avec le carburant et les armes d\195\168s que"
          .. " leur chef s'absentera." },
    { id = "false_name", tags = { "identity" },
      en = "Their leader's name is not real: it came from the wallet of a dead man found on the second day.",
      fr = "Le nom de leur chef n'est pas le sien : il vient du portefeuille d'un mort trouv\195\169 le"
          .. " deuxi\195\168me jour." },
    { id = "watered_fuel", types = { "neutrals" }, tags = { "fraud" }, requires = { "trade" },
      en = "The fuel they trade is cut with water, and two buyers have already broken down on the road because of it.",
      fr = "Le carburant qu'ils \195\169changent est coup\195\169 d'eau, et deux acheteurs sont d\195\169j\195\160"
          .. " tomb\195\169s en panne \195\160 cause de lui." },
    { id = "chained_dead", types = { "settlers", "neutrals" }, tags = { "cult" }, requires = { "faith" },
      en = "The most devout among them believe the dead can be saved, and keep one chained in a barn.",
      fr = "Les plus fervents croient que les morts peuvent \195\170tre sauv\195\169s et en gardent un"
          .. " encha\195\174n\195\169 dans une grange." },
    { id = "lab_worker", tags = { "knowledge" },
      en = "One of them worked at a lab near Louisville and knows more about the outbreak than they let on.",
      fr = "L'un d'eux travaillait dans un laboratoire pr\195\168s de Louisville et en sait plus sur"
          .. " l'\195\169pid\195\169mie qu'il ne veut bien l'admettre." },
    { id = "fake_distress_call", types = { "raiders" }, tags = { "violent" },
      en = "They put out a fake distress call on the radio to lure survivors into an ambush.",
      fr = "Ils diffusent un faux appel de d\195\169tresse \195\160 la radio pour attirer des survivants dans une"
          .. " embuscade." },
}

-- Noms des chefs tirés quand l'appelant n'en fournit pas : prénoms et noms de personnages de quatre œuvres, tirés
-- séparément (une combinaison exacte d'un personnage peut sortir : accepté). Sources :
--   TWD = The Walking Dead (série), ZN = Z Nation, BS = Black Summer,
--   NOTLD = La Nuit des morts-vivants (Night of the Living Dead, 1968 et remake de 1990).
Data.firstNamesMale = {
    "Rick",     -- TWD : Rick Grimes
    "Daryl",    -- TWD : Daryl Dixon
    "Glenn",    -- TWD : Glenn Rhee
    "Hershel",  -- TWD : Hershel Greene
    "Merle",    -- TWD : Merle Dixon
    "Shane",    -- TWD : Shane Walsh
    "Abraham",  -- TWD : Abraham Ford
    "Charles",  -- ZN : Charles Garnett
    "Alvin",    -- ZN : Alvin Murphy
    "Mack",     -- ZN : Mack Thompson
    "Simon",    -- ZN : Simon Cruller (Citizen Z)
    "Julius",   -- BS : Julius James (« Spears »)
    "Lance",    -- BS : Lance
    "William",  -- BS : William Velez
    "Ben",      -- NOTLD 1968 et 1990 : Ben
    "Johnny",   -- NOTLD 1968 : Johnny
    "Harry",    -- NOTLD 1968 et 1990 : Harry Cooper
    "Tom",      -- NOTLD 1968 et 1990 : Tom
}
Data.firstNamesFemale = {
    "Carol",    -- TWD : Carol Peletier
    "Maggie",   -- TWD : Maggie Greene
    "Andrea",   -- TWD : Andrea
    "Lori",     -- TWD : Lori Grimes
    "Beth",     -- TWD : Beth Greene
    "Sasha",    -- TWD : Sasha Williams
    "Roberta",  -- ZN : Roberta Warren
    "Addy",     -- ZN : Addy Carver
    "Cassandra", -- ZN : Cassandra
    "Lucy",     -- ZN : Lucy Murphy
    "Rose",     -- BS : Rose
    "Anna",     -- BS : Anna, fille de Rose
    "Barbara",  -- BS : Barbara Watson ; NOTLD 1990 : Barbara
    "Barbra",   -- NOTLD 1968 : Barbra
    "Helen",    -- NOTLD 1968 et 1990 : Helen Cooper
    "Karen",    -- NOTLD 1968 : Karen Cooper
    "Judy",     -- NOTLD 1968 : Judy ; 1990 : Judy Rose
    "Sarah",    -- NOTLD 1990 : Sarah Cooper
}
Data.surnames = {
    "Grimes",     -- TWD : Rick, Lori, Carl Grimes
    "Dixon",      -- TWD : Daryl, Merle Dixon
    "Greene",     -- TWD : Hershel, Maggie, Beth Greene
    "Rhee",       -- TWD : Glenn Rhee
    "Walsh",      -- TWD : Shane Walsh
    "Horvath",    -- TWD : Dale Horvath
    "Peletier",   -- TWD : Carol Peletier
    "Ford",       -- TWD : Abraham Ford
    "Porter",     -- TWD : Eugene Porter
    "Espinosa",   -- TWD : Rosita Espinosa
    "Monroe",     -- TWD : Deanna Monroe
    "Stokes",     -- TWD : Gabriel Stokes
    "Williams",   -- TWD : Tyreese, Sasha Williams
    "Garnett",    -- ZN : Charles Garnett
    "Warren",     -- ZN : Roberta Warren
    "Murphy",     -- ZN : Alvin, Lucy Murphy
    "Carver",     -- ZN : Addy Carver
    "Thompson",   -- ZN : Mack Thompson
    "Cruller",    -- ZN : Simon Cruller
    "Vasquez",    -- ZN : Javier Vasquez
    "James",      -- BS : Julius James
    "Velez",      -- BS : William Velez
    "Watson",     -- BS : Barbara Watson
    "Cooper",     -- NOTLD 1968 et 1990 : Harry, Helen, Karen (1968), Sarah (1990) Cooper
    "McClelland", -- NOTLD 1968 et 1990 : le shérif McClelland
}

return Data
