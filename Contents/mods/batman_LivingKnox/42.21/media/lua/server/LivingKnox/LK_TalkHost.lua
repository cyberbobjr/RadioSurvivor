if isClient() then return end
--[[
Living Knox: base of the NPC speech (E18-T17): the table LivingKnox.Talk and its host. Required by LK_Talk,
LK_Initiatives, LK_Conversations and LK_Incidents, in whatever order the game loads them. Authority only.

The queue, the requests and the replies are Living Knox's. The speakers and what a mod adds around them come from the
HOST, given by Talk.attach(host) (decision of 2026-11-06: each mod brings its own context):

  provider                  table of NPC functions (RS_NPCProvider contract: near, hears, say, engaged, objects, npc,
                            context, composition, loyalty, leave, decide, dissent, available)
  observations              observation log (list, field, keyOf, hour, transmit, MAX_CHAIN)
  session() -> world, run   identifiers of the requests
  fiche(id), fiches()       speaker of this id, every speaker (each { id, incarnation, name, background, alive,
                            order, revision, personality, ... }; order and revision are numbered by LK_Talk)
  find(body id), ensure(body id)   speaker of a body, without or with creation
  objects() -> { [speaker id] = loaded body }
  bound() -> { [player] = character }
  players() -> connected players
  scan()                    refreshes objects()
  characterName(character)  name of a character, nil when unknown
  save() -> boolean         saves the state of the host
  publish()                 tells the players' views that something changed
  reject(character, reason)   tells a character its sentence got no answer
  remember(npc, id, text, players)   line said by npc, kept for the players who heard it and already know it
  contactedGroups() -> { [group] = true }   groups already known to a character
  overheard(player, character, seen)        a player heard two NPCs talk
  callLanguage() -> forced language or nil
  claim(request) -> function(request, result, npc) or nil   reply handled by the host (group radio)
  talkContext(context, npc, character, player, language, group) -> offers, bound, relation binding
  talkQueued(request, player, npc, character, text)         a sentence entered the queue
  relationApply(npc, character, binding, dir, fact) -> view or nil, why
  talkActions(request, result, npc, binding, ignored) -> { applied, decided, offer } or false, why
  heard(request, result, npc, body, outcome) -> players who heard the reply
  speech(players, request, result, npc, body)   the reply reaches them
  offered(mission, character)                   a new offer is signalled to its character
  incidentDecided(agreement, incident, npc)     decision of a leader announced
]]
require "LivingKnox/LK_Core"

local Talk = LivingKnox.Talk or {}
LivingKnox.Talk = Talk

-- Field `name` of the host, read when used: the modules load before the host is attached.
local function proxy(name)
    return setmetatable({}, { __index = function(_, key)
        local host = Talk.host
        local target = host and host[name] or nil
        return target and target[key] or nil
    end })
end

Talk.provider = Talk.provider or proxy("provider")
Talk.observations = Talk.observations or proxy("observations")

return Talk
