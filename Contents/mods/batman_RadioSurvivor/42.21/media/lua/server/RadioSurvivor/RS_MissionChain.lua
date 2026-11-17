if isClient() then return end
--[[
Chained missions of a radio voice (E20-T08, ADR D04, D09). Authority only.

A voice mission is identified by the id of its [mission <id>] section of the sheet (RS_Persona). A section with
after=<id> is available to a caller only once the cited section's last outcome is a success for that caller: per
notebook character by default, per team (CA_Teams.idOf: vanilla faction, or the lone player's personal team) when the
section says scope=team. A failed (or expired, abandoned) mission of the cited section blocks its successors again
until a new success of it. A sheet without any [mission] section gives one scout job (section id 'scout').

Choice (Chain.choose, start_mission { template }): the name of an available section is that section; otherwise a
mission type, and the server draws among the available sections of that type by their weight= (injected generator,
Chain.setRandom, same pattern as RS_Rewards.setRandom). Refusals: 'locked' (the section, or every section of the type,
waits for its after=), 'bad_template' (no section and no type of that name).

Outcomes (Chain.record, a result listener of the common engine attached by RS_MissionHooks), in the private state
RS_State: per character in the voice donor record (S.data.voiceDonors[...].chain[section] = 'success' | 'failed'),
per team in S.data.voiceTeamChains['<voice>:<team>'][section]; the mission carries m.section, m.team (team of the
caller at the start) and m.setsState (sets_state= of its section). A success of a section declaring sets_state= sets
the story state of the voice (RS_VoiceStory), once.
]]
local Story = require "RadioSurvivor/RS_VoiceStory"

local Chain = {}

local SUCCESS, FAILED = "success", "failed"

local function defaultRandom(n)
    return ZombRand(n)
end

local random = defaultRandom

-- Generator of the weighted draw (random(n) -> 0..n-1; tests inject a seeded one); nil restores ZombRand.
function Chain.setRandom(fn)
    random = fn or defaultRandom
end

local function defaultTeamOf(player)
    if not player then return nil end
    return require("CoreAI/CA_Teams").idOf(player)
end

local teamOf = defaultTeamOf

-- Team of a player (stable id of CA_Teams), injectable for the benches; nil restores CA_Teams.
function Chain.setTeamOf(fn)
    teamOf = fn or defaultTeamOf
end

function Chain.teamOf(player)
    return teamOf(player)
end

-- Section given by a sheet without any [mission] section (a fresh table each time: set-ups may read it).
local function defaultSection()
    return {id = "scout", type = "scout", weight = 1, scope = "character", drops = {}, params = {},
        target = {kind = "near"}} -- E25-T01: objective near the caller, as a section without target=
end

-- [mission] sections of the sheet in file order, or the default scout.
function Chain.sections(sheet)
    local list = {}
    for _, m in ipairs(type(sheet) == "table" and type(sheet.missions) == "table" and sheet.missions or {}) do
        if type(m) == "table" and type(m.id) == "string" and type(m.type) == "string" then list[#list + 1] = m end
    end
    if #list == 0 then list[1] = defaultSection() end
    return list
end

local function characterChain(caller, create)
    local donor = caller.donor
    if type(donor) ~= "table" then return nil end
    if type(donor.chain) ~= "table" then
        if not create then return nil end
        donor.chain = {}
    end
    return donor.chain
end

local function teamChain(caller, create)
    local state = caller.state
    if type(state) ~= "table" or caller.team == nil then return nil end
    if type(state.voiceTeamChains) ~= "table" then
        if not create then return nil end
        state.voiceTeamChains = {}
    end
    local key = tostring(caller.voice) .. ":" .. tostring(caller.team)
    local chain = state.voiceTeamChains[key]
    if type(chain) ~= "table" and create then
        chain = {}
        state.voiceTeamChains[key] = chain
    end
    return type(chain) == "table" and chain or nil
end

-- Outcomes read by scope= of a section (RS_Persona: character by default).
local SCOPES = {character = characterChain, team = teamChain}

local function unlocked(section, caller)
    if section.after == nil then return true end
    local read = SCOPES[section.scope] or characterChain
    local chain = read(caller, false)
    return chain ~= nil and chain[section.after] == SUCCESS
end

-- Sections available to this caller, in file order. caller = { state, voice, donor (voice donor record of the
-- character, or nil), team (team id, or nil) }.
function Chain.available(sheet, caller)
    local open = {}
    for _, section in ipairs(Chain.sections(sheet)) do
        if unlocked(section, caller) then open[#open + 1] = section end
    end
    return open
end

local function weightOf(section)
    local w = tonumber(section.weight)
    if not w or w < 1 then return 1 end
    return math.floor(w)
end

local function draw(list)
    local total = 0
    for _, section in ipairs(list) do total = total + weightOf(section) end
    local roll = random(total)
    for _, section in ipairs(list) do
        roll = roll - weightOf(section)
        if roll < 0 then return section end
    end
    return list[#list]
end

local function anyNamed(list, field, name)
    for _, section in ipairs(list) do
        if section[field] == name then return section end
    end
    return nil
end

-- Section of the sheet the name of start_mission designates for this caller, or nil and a refusal reason.
function Chain.choose(sheet, caller, name)
    local all, open = Chain.sections(sheet), Chain.available(sheet, caller)
    local exact = anyNamed(open, "id", name)
    if exact then return exact end
    if anyNamed(all, "id", name) then return nil, "locked" end
    local same = {}
    for _, section in ipairs(open) do
        if section.type == name then same[#same + 1] = section end
    end
    if #same > 0 then return draw(same) end
    if anyNamed(all, "type", name) then return nil, "locked" end
    return nil, "bad_template"
end

-- Records the result of a closed voice mission for one of its participants (donor: voice donor record of that
-- character) and for the team of its caller; a success of a section with sets_state= sets the story state.
-- Returns true when the mission belongs to a section.
function Chain.record(state, m, result, donor)
    if type(m) ~= "table" or m.donor ~= "voice" or type(m.section) ~= "string" then return false end
    local outcome = result == SUCCESS and SUCCESS or FAILED
    local caller = {state = state, voice = m.voice, donor = donor, team = m.team}
    local mine = characterChain(caller, true)
    if mine then mine[m.section] = outcome end
    local theirs = teamChain(caller, true)
    if theirs then theirs[m.section] = outcome end
    if outcome == SUCCESS and m.setsState ~= nil then Story.set(state, m.voice, m.setsState) end
    return true
end

return Chain
