-- RadioSurvivorCore: shared core of RadioSurvivor and Living Knox (ADR adr-separation-mods.md, plan E18).
-- E18-T01: the mod exists and is required by RadioSurvivor; the shared code (tools, identity, bridge link,
-- missions, mission journal) moves here in E18-T02 to E18-T06. Loaded on every machine (media/lua/shared).
RadioSurvivorCore = RadioSurvivorCore or {}
local Core = RadioSurvivorCore

Core.MOD_ID = "batman_RadioSurvivorCore"
Core.VERSION = 1

return Core
