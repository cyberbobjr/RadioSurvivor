-- RadioSurvivorCore: new world or restart of an existing world, for the states written in files of the authority
-- (RS_State, Living Knox registries). Moved to the core mod by E18-T02 (shared: loaded on every machine, the signal
-- is only read by the authority).
--
-- Engine trap (42.21.0): the argument of OnInitGlobalModData comes from WorldDictionary.isIsNewGame()
-- (GlobalModData.java:56), set only by GameLoadingState (GameLoadingState.java:253, solo and client); its initial
-- value is true (WorldDictionary.java:526). A dedicated server never goes through GameLoadingState: the argument is
-- ALWAYS true there, even when a saved world restarts (seen on 2026-10-15: "isNewGame = false" from the radio then
-- "new world, empty registry" in the same restart). Reliable signal everywhere: the second argument of
-- OnLoadRadioScripts (ZomboidRadio.java:246, savedWorldVersion == -1: map_t.bin missing on a server, map_ver.bin in
-- solo), fired just before GlobalModData.init (IsoWorld.java:1905-1907).
--
-- WorldStart.isNewWorld(isNewGame): call it from a subscriber of OnInitGlobalModData with its argument. Returns the
-- signal of the radio when it was seen during this load, else the argument (Lua reload, radio failure); on a server,
-- this fallback is logged.
local WorldStart = {}

WorldStart.radioNewGame = nil   -- nil: no OnLoadRadioScripts seen since this Lua was loaded

function WorldStart.onLoadRadioScripts(_, isNewGame)
    WorldStart.radioNewGame = isNewGame == true
end

local warned = false
function WorldStart.isNewWorld(isNewGame)
    if WorldStart.radioNewGame ~= nil then return WorldStart.radioNewGame end
    if isServer() and isNewGame == true and not warned then
        warned = true
        print("[RadioSurvivorCore] WARN world start: no OnLoadRadioScripts signal; trusting OnInitGlobalModData(true), "
            .. "which is always true on a dedicated server")
    end
    return isNewGame == true
end

Events.OnLoadRadioScripts.Add(WorldStart.onLoadRadioScripts)

return WorldStart
