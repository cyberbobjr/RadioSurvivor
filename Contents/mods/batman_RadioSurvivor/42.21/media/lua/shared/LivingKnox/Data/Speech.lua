-- Living Knox : catalogue des répliques courtes des PNJ (« barks », LK11-T04). Fiche : docs/conception/parole.md.
-- Données seules : le serveur choisit une réplique (media/lua/server/LivingKnox/LK_Speech.lua) et n'envoie que sa clé ;
-- chaque client la traduit dans SA langue (getText). Les textes sont dans Translate/EN|FR/IG_UI.json, clé
-- "IGUI_LK_Speech_<id>" : le serveur MP ne traduit pas (base api-42-21.md), et un .json garde les accents en clair.
--
-- Réplique : { id = <unique, [%w_]>, situation = <SITUATIONS>, bands = { <BANDS> } (absent = toutes les attitudes),
--              types = { <type de groupe> } (absent = tous), roles = { <rôle de membre ou "leader"> } (absent = tous) }
-- Choix (LK_Speech.pick) : répliques de la situation dont les trois listes admettent le contexte ; une réplique propre
-- au type ou au rôle pèse plus lourd (WEIGHT_TYPE, WEIGHT_ROLE) ; la dernière réplique du même PNJ est évitée quand une
-- autre convient. Chaque situation a, pour chaque attitude, au moins une réplique sans type ni rôle (checkData).
-- Les textes ne disent rien de l'état réel d'un groupe (stock, foyer, effectif) : aucun secret dans une réplique.
require "LivingKnox/LK_Core"

local Data = {}
LivingKnox.SpeechData = Data

Data.FORMAT = 1
Data.KEY_PREFIX = "IGUI_LK_Speech_"

-- Situations (liste fermée) et attitudes envers le joueur visé (niveaux de LK_Hostility regroupés).
Data.SITUATIONS = { "greet", "warn", "alert", "hurt", "hungry", "rest", "farewell", "smalltalk" }
Data.BANDS = { "friendly", "neutral", "hostile" }
Data.BAND_OF_LEVEL = { trusting = "friendly", favorable = "friendly", cautious = "neutral", wary = "hostile",
    hostile = "hostile" }
-- Couleur de la bulle selon l'attitude (I9.5) : vert pâle, blanc cassé, rouge pâle.
Data.COLORS = { friendly = { 0.75, 1.0, 0.75 }, neutral = { 0.95, 0.92, 0.8 }, hostile = { 1.0, 0.7, 0.65 } }

Data.WEIGHT_BASE = 1
Data.WEIGHT_TYPE = 2
Data.WEIGHT_ROLE = 3

local F, N, X = { "friendly" }, { "neutral" }, { "hostile" }

Data.lines = {
    -- Salut : un joueur arrive.
    { id = "greet_1", situation = "greet", bands = F },
    { id = "greet_2", situation = "greet", bands = F },
    { id = "greet_3", situation = "greet", bands = F, types = { "settlers" } },
    { id = "greet_4", situation = "greet", bands = N },
    { id = "greet_5", situation = "greet", bands = N },
    { id = "greet_6", situation = "greet", bands = N, types = { "neutrals" } },
    { id = "greet_7", situation = "greet", bands = X },
    { id = "greet_8", situation = "greet", bands = X, types = { "raiders" } },
    { id = "greet_9", situation = "greet", bands = X },
    -- Avertissement : trop près.
    { id = "warn_1", situation = "warn", bands = F },
    { id = "warn_2", situation = "warn", bands = N },
    { id = "warn_3", situation = "warn", bands = N, roles = { "leader", "deputy" } },
    { id = "warn_4", situation = "warn", bands = X },
    { id = "warn_5", situation = "warn", bands = X, types = { "raiders" } },
    { id = "warn_6", situation = "warn", bands = X },
    -- Alerte : danger (morts, mouvement) ; adressée au groupe, quelle que soit l'attitude.
    { id = "alert_1", situation = "alert" },
    { id = "alert_2", situation = "alert" },
    { id = "alert_3", situation = "alert", roles = { "fighter", "scout" } },
    { id = "alert_4", situation = "alert", types = { "raiders" } },
    -- Blessure : le PNJ lui-même.
    { id = "hurt_1", situation = "hurt" },
    { id = "hurt_2", situation = "hurt" },
    { id = "hurt_3", situation = "hurt", roles = { "medic" } },
    { id = "hurt_4", situation = "hurt" },
    -- Faim.
    { id = "hungry_1", situation = "hungry" },
    { id = "hungry_2", situation = "hungry" },
    { id = "hungry_3", situation = "hungry", bands = F },
    { id = "hungry_4", situation = "hungry", types = { "raiders" } },
    -- Repos.
    { id = "rest_1", situation = "rest" },
    { id = "rest_2", situation = "rest" },
    { id = "rest_3", situation = "rest" },
    { id = "rest_4", situation = "rest", roles = { "worker" } },
    -- Au revoir : le joueur s'éloigne.
    { id = "farewell_1", situation = "farewell", bands = F },
    { id = "farewell_2", situation = "farewell", bands = F },
    { id = "farewell_3", situation = "farewell", bands = N },
    { id = "farewell_4", situation = "farewell", bands = N },
    { id = "farewell_5", situation = "farewell", bands = X },
    { id = "farewell_6", situation = "farewell", bands = X },
    -- Propos sans engagement : réplique de secours sans pont LLM (E08-T03), conversations entre membres (E08-T04).
    { id = "smalltalk_1", situation = "smalltalk", bands = F },
    { id = "smalltalk_2", situation = "smalltalk", bands = F, types = { "settlers" } },
    { id = "smalltalk_3", situation = "smalltalk", bands = F },
    { id = "smalltalk_4", situation = "smalltalk", bands = N },
    { id = "smalltalk_5", situation = "smalltalk", bands = N },
    { id = "smalltalk_6", situation = "smalltalk", bands = X },
    { id = "smalltalk_7", situation = "smalltalk", bands = X, types = { "raiders" } },
}

return Data
