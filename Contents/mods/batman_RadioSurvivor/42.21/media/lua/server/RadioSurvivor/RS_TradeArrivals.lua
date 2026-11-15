-- Radio Survivor: registry of the arrival modes of the traders (E20-T07, ADR D07). A trader sheet names its mode in
-- its [trade] section (arrival=<name>); each mode is one file of server/RadioSurvivor/TradeArrivals/ that calls
-- Arrivals.register. Adding a mode never touches the trade engine (RS_Trade, RS_TradeRun, RS_TradeExchange). The game
-- loads every server file, modes included, before the sheets are read (OnLoadRadioScripts), so they are known to
-- RS_Personas.rules (Arrivals.NAMES); the benches require each file of the folder (tests/test_personas.py).
--
-- Contract of a mode (every field required):
--   signals   set of the signals that call the trader to the landing during the meeting window, among the
--             detectors of RS_TradeRun.SIGNALS: lamp (lit lamp held in hand by a member of the booking team at the
--             landing), flare (red flare or smoke of Signal Smoke lit near the landing, a member present)
--   texts     { signal = what the caller must do, arrived = the trader is there now } English for the voice
--             context, plain words without any digit (the bridge refuses digits in these texts)
--   sounds    { approach = vanilla sound played at the landing when the trader arrives, leave = when he goes }
--   causes    ordered list of cancellation causes checked by RS_TradeRun while the run is booked, from
--             RS_TradeRun.WARN_HOURS before the window: { name, text (English, for the voice context, no digit),
--             fallback (English radio line when the translation IGUI_RS_TradeRun_Cancel_<name> is missing),
--             check(world) -> true to cancel }. world (RS_TradeRun): id, run (copy), hours, cordonLevel (index in
--             RS_Trade.CORDONS), patrolRoll() (0..99, reproducible per run), helicopterSince(hours), stormy().
-- ASCII only (Kahlua lexer).
if isClient() then return end

local Arrivals = {}

-- Name -> true, read by the sheet reader (RS_Personas.rules). Derived from the registry.
Arrivals.NAMES = {}

local registry = {}
local FIELDS = { "signals", "texts", "sounds", "causes" }

-- Registers a mode; returns false (and logs) when its declaration lacks a field of the contract.
function Arrivals.register(name, mode)
    if type(name) ~= "string" or not string.match(name, "^[a-z][a-z0-9_]*$") or type(mode) ~= "table" then
        print("[RadioSurvivor] ERROR trade arrival mode refused: bad name or declaration")
        return false
    end
    for _, field in ipairs(FIELDS) do
        if type(mode[field]) ~= "table" then
            print("[RadioSurvivor] ERROR trade arrival mode '" .. name .. "' refused: no " .. field)
            return false
        end
    end
    registry[name] = mode
    Arrivals.NAMES[name] = true
    return true
end

-- Mode registered under this name, or nil.
function Arrivals.get(name)
    return registry[name]
end

return Arrivals
