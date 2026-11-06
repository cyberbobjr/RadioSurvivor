-- Living Knox : entrée côté joueur local (client MP, solo).
-- Un serveur dédié ne fait que sommer media/lua/client sans l'exécuter ; garde défensive malgré tout.
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local Client = LivingKnox.Client or {}
LivingKnox.Client = Client

function Client.onStart()
    LivingKnox.Log.info("client %s ready (side=%s, enabled=%s)", LivingKnox.VERSION, LivingKnox.side(),
        tostring(LivingKnox.Config.isEnabled()))
end

-- OnGameStart (IngameState.enter) : à chaque entrée dans une partie, client MP comme solo.
local function onStart()
    LivingKnox.Client.onStart()
end

LivingKnox.subscribe("OnGameStart", "Client.onStart", onStart)

return Client
