-- Fixed requests of the E18-T04 bench (tests/test_core_bridge.py): written by the transport into requests.txt.
-- Expects T (the transport) and fills its lanes, then writes once. ASCII and UTF-8 escapes only.
local T = TRANSPORT or require "RadioSurvivor/RS_BridgeLanes"
T.session = "run-1-1-1"
T.radio = {
    { id = "r-1", sentAt = 1790000000000, kind = "radio_call", caller = "Alice", voice = "walt", name = "Alice Moss",
      date = "July 9, 1993", days = "2", radio = "93.2", text = "Bonjour, ici \195\137lise", language = "FR" },
    { id = "r-2", sentAt = 1790000000500.4, caller = "Bob", text = "Anyone?", memory = "ab01", mission = "cd02" },
}
T.npc = { { version = 2, kind = "npc_talk", id = "n-1", npc = "npc-1", text = "Salut, \195\167a va ?", offers = { "a", "b" } } }
T.acks = { { version = 2, kind = "ack", id = "n-0-ack", request = "n-0" } }
T.lastPages = { { version = 2, kind = "last_pages", id = "lp-1", cid = "character-1", lines = { "one", "two" } } }
assert(T.write())
