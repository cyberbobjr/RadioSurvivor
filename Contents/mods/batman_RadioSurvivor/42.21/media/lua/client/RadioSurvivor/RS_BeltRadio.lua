-- Radio Survivor : inscription auprès du récepteur commun Belt Walkie-Talkie (mod requis batman_BeltRadio, API
-- documentée dans son dépôt, docs/specifications-techniques/api-publique.md). Le mod commun gère le talkie à la ceinture :
-- réglage, écoute en solo, bulle MP d'une radio non tenue, pile. Une radio rangée (inventaire, sac) n'entend rien en solo
-- (décision 3).
-- - channels : chaînes des voix (GUID préfixé Const.VOICE_CHANNEL_PREFIX), en solo et sur un serveur hôte ; sur un
--   client MP le gestionnaire de chaînes vaut nil : liste vide. Elles sont aussi dans le registre vanilla
--   (AddChannel) : la déclaration les rend explicites, le récepteur les dédoublonne.
-- - recognize : chaque ligne d'une voix porte le code Const.LINE_CODE (server/RadioSurvivor_Server.lua, airNext),
--   transmis au client avec la ligne ; couleur des voix (Const.LINE_COLOR) pour la bulle MP. Aucune fréquence de voix
--   n'est connue du client (E05-T08) : pas de champ frequencies.
-- En solo, la couleur de la ligne affichée à la ceinture est celle de la RadioLine (Const.LINE_COLOR).
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Support = require "BatmanRadio/BatmanRadio_Core"

local Belt = {}
Belt.PROVIDER_ID = "RadioSurvivor"
-- Niveau d'API de Belt Walkie-Talkie requis (BatmanRadioSupport.VERSION).
Belt.REQUIRED_API = 1

-- Chaînes des voix du mod, copiées aussitôt : getChannelsList rend une liste Java réutilisée à chaque appel.
function Belt.channels()
    local out = {}
    local radio = getZomboidRadio()
    local manager = radio and radio:getScriptManager()
    if not manager then return out end
    local list = manager:getChannelsList()
    local prefix = Const.VOICE_CHANNEL_PREFIX
    for i = 0, list:size() - 1 do
        local channel = list:get(i)
        if channel and string.sub(tostring(channel:getGUID()), 1, string.len(prefix)) == prefix then
            out[#out + 1] = channel
        end
    end
    return out
end

-- Codes d'une ligne reçue (jetons séparés par des virgules, comme ISRadioInteractions.split) : couleur des voix si
-- l'un d'eux est Const.LINE_CODE, sinon nil.
function Belt.recognize(codes)
    if type(codes) ~= "string" then return nil end
    for token in string.gmatch(codes, "[^,]+") do
        if token == Const.LINE_CODE then return Const.LINE_COLOR end
    end
    return nil
end

function Belt.register()
    local version = BatmanRadioSupport and BatmanRadioSupport.VERSION or 0
    if version < Belt.REQUIRED_API then
        print(Const.TAG .. " WARN: Belt Walkie-Talkie API " .. Belt.REQUIRED_API .. " required, found "
            .. tostring(BatmanRadioSupport and BatmanRadioSupport.VERSION))
    end
    if type(Support) ~= "table" or type(Support.register) ~= "function" then
        print(Const.TAG .. " WARN: Belt Walkie-Talkie receiver missing (batman_BeltRadio not loaded)")
        return false
    end
    Support.register(Belt.PROVIDER_ID, { channels = Belt.channels, recognize = Belt.recognize })
    return true
end

Belt.register()

return Belt
