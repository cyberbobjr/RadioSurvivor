-- Living Knox : tableau à colonnes des outils de debug (LK13-T15). Depuis E18-T09, le code vit dans le mod commun
-- (client/RadioSurvivorCore/RC_Table.lua, partagé avec la vue de debug des fréquences de RadioSurvivor) ; ce fichier
-- garde le nom LivingKnox.Table pour les vues de Living Knox (LK_DebugView, LK_NpcSheet).
if isServer() then return end

require "LivingKnox/LK_Core"

local Table = require "RadioSurvivorCore/RC_Table"
LivingKnox.Table = Table

return Table
