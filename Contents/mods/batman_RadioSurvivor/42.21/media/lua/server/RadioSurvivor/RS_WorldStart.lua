-- Monde neuf ou relance d'un monde existant, pour les états écrits dans des fichiers de l'autorité (RS_State,
-- registres Living Knox).
--
-- Piège du moteur (42.21.0) : l'argument d'OnInitGlobalModData vient de WorldDictionary.isIsNewGame()
-- (GlobalModData.java:56), posé seulement par GameLoadingState (GameLoadingState.java:253, solo et client) ; sa valeur
-- initiale est vraie (WorldDictionary.java:526). Un serveur dédié ne passe jamais par GameLoadingState : l'argument y
-- est TOUJOURS vrai, même à la relance d'un monde sauvegardé (vu le 2026-10-15 : « isNewGame = false » de la radio puis
-- « new world, empty registry » dans la même relance). Signal fiable partout : le second argument
-- d'OnLoadRadioScripts (ZomboidRadio.java:246, savedWorldVersion == -1 : map_t.bin absent sur un serveur, map_ver.bin
-- en solo), déclenché juste avant GlobalModData.init (IsoWorld.java:1905-1907).
--
-- WorldStart.isNewWorld(isNewGame) : à appeler depuis un abonné d'OnInitGlobalModData avec son argument. Rend le
-- signal de la radio s'il a été vu pendant ce chargement, sinon l'argument (rechargement du Lua, radio en échec) ; sur
-- un serveur, ce repli est signalé dans le journal.
local WorldStart = {}

WorldStart.radioNewGame = nil   -- nil : aucun OnLoadRadioScripts vu depuis le chargement de ce Lua

function WorldStart.onLoadRadioScripts(_, isNewGame)
    WorldStart.radioNewGame = isNewGame == true
end

local warned = false
function WorldStart.isNewWorld(isNewGame)
    if WorldStart.radioNewGame ~= nil then return WorldStart.radioNewGame end
    if isServer() and isNewGame == true and not warned then
        warned = true
        print("[RadioSurvivor] WARN world start: no OnLoadRadioScripts signal; trusting OnInitGlobalModData(true), "
            .. "which is always true on a dedicated server")
    end
    return isNewGame == true
end

Events.OnLoadRadioScripts.Add(WorldStart.onLoadRadioScripts)

return WorldStart
