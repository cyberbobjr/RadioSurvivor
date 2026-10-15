--[[ Living Knox provider of the notebook (E17-T03): implements RS_NPCProvider on the Living Knox engine of this mod.

Registration: when Living Knox is enabled (sandbox LivingKnox.Enabled), at OnInitGlobalModData (authority: sandbox
already read, before RS_Carnet_Server.init, which is subscribed later because server files load after shared ones),
OnGameStart and OnServerStarted (idempotent). Disabled: nothing is registered, the notebook keeps its empty provider
("No NPC engine active"). One NPC engine per server (decision of 2026-10-03): when another provider already holds
RS_NPCProvider, Living Knox is NOT registered a second time; a console warning names the active provider.

Identity: the provider id IS the Living Knox NPC id "lk-<n>" (never reused, LK_Identity), the same on the server and
on every client; it survives re-embodiments (a new body of the same NPC keeps its id), so no 'reincarnated' event is
ever emitted. signature = "lk:" .. id. A body is the current zombie of the NPC:
  authority (server, solo)  LivingKnox.Bodies.bound[id], kept only while it is in the cell zombie list;
  MP client                 LivingKnox.ZombieGuard.cache[id], kept only while it matches the roster sent by the
                            server (same onlineId, reanimated player): zombie ModData never reach a client.
Record (Provider.npc, authority): name = story leader name for the current leader of a group with a story, otherwise
a name drawn from the story name lists with the NPC number as seed (registry keeps no member name in API version 1);
group = "grp-<n>" ('' without group); groupName = name of the group (nil without group); hostile = start attitude level of the group type is "hostile" (nil without
group: unknown, no offer); traits from the group member (smoker, drinker -> alcoholic, tidy -> compulsiveCleaner).
Death: LivingKnox.Bodies.onDied (authority) emits Provider 'death' (id, body, cause).

Supplies (optional provider operations, RS_NPCProvider header): offers of LivingKnox.API.missionOffers for the
group of the NPC and the notebook character (player key of LK_Hostility), deliveries by LivingKnox.API.deliver
(receipt key = transaction token of the notebook: a replay never raises a reserve twice). A completed delivery
records the attitude fact "delivery" for the delivering character (LK_Hostility.record, attributable).
Context (Provider.context, authority): public projection for the LLM: group name and type, public summary
(LK_Stories.publicView of the composed story, in the request language; registry summary otherwise), leader name,
role, needs, morale, living members, attitude toward this character, and (E10-T02) the last collective decisions of
the group (journal entries of kind "decision" only). Never story secrets, home, area or the rest of the log.
Leader (E10-T02, authority): Provider.composition = leader flag and composition fingerprint of LivingKnox.API.composition
(computed, nothing stored); Provider.decide writes a collective decision in the group journal (Groups.addLog, kind
"decision", fact composed here, never the model's speech nor the leader's reasons).
Members (E10-T03, authority): Provider.loyalty = LivingKnox.Decisions.loyaltyOfMember (morale and seniority);
Provider.dissent = journal entry "contest" / "refusal" (fact only) and the member's line through LivingKnox.Speech.
Departure (E10-T04, authority): Provider.leave = the NPC leaves its group and forms a group of type "loners" of its
own (LK.leave, section "individual departure"); Provider.composition gives canLeave.
Presence (Provider.presence, authority, E08-T08): expedition membership and home of the group, read by the world
observation triggers of the notebook on the server only.
Initiatives (E08-T03, authority): Provider.engaged = LivingKnox.API.engaged; Provider.say / Provider.bark = the
proximity speech of LivingKnox.Speech (LK11-T04).
Relation basis (E09-T04, authority): Provider.relation = attitude of the NPC's group toward a notebook character and
its last attitude facts (LivingKnox.API.attitude, API.attitudeFacts), keys 'att:<group>:<n>'.
Group radios (E08-T06, authority): Provider.radios = groups holding a transmitter a living member can use now (group
type format 2: homeRadio, profile radio), with the NPC who answers; never a home nor a position.
]]
require 'LivingKnox/LK_Core'
require 'LivingKnox/LK_Config'

local P = require 'RadioSurvivor/RS_NPCProvider'

local LK = {name = 'livingknox'}
RS_LivingKnox = LK

local TAG = '[RS_LivingKnox] '
LK.LONER_TYPE = 'loners' -- E10-T04: group type of an NPC who left its group (Data/LK_Type_loners.lua)
local ID_PATTERN = '^lk%-%d+$'
local TRAITS = {smoker = 'smoker', drinker = 'alcoholic', tidy = 'compulsiveCleaner'}
local NEEDS = {food = true, medical = true, ammo = true}

local function engine() return LivingKnox end

local function isId(id) return type(id) == 'string' and string.match(id, ID_PATTERN) ~= nil end

local function authority() return not isClient() end

function LK.available()
    local E = engine()
    if type(E) ~= 'table' or type(E.Config) ~= 'table' or not E.Config.isEnabled() then return false end
    -- The authority needs the server part of the engine (media/lua/server, loaded after this file).
    if authority() then return type(E.Bodies) == 'table' and type(E.API) == 'table' end
    return true
end

-- Bodies loaded on this machine, by NPC id.
function LK.objects()
    local E, out = engine(), {}
    if authority() then
        local B = E.Bodies
        if not B or getCell() == nil then return out end
        for id, z in pairs(B.bound) do
            if z ~= nil and B.inWorld(z) then out[id] = z end
        end
        return out
    end
    local G = E.ZombieGuard
    if not G or not G.cache or not G.roster then return out end
    for id, z in pairs(G.cache) do
        local entry = G.roster.byId[id]
        if z ~= nil and entry ~= nil and not z:isDead() and z:getOnlineID() == entry.o and z:isReanimatedPlayer() then
            out[id] = z
        end
    end
    return out
end

-- Speech bubble of a notebook answer (LK11-T09): the same bubble as the Living Knox speech (LK_SpeechView, drawn by
-- the mod, colour of the former notebook bubble). Without the view (not loaded on this machine): vanilla line.
LK.BUBBLE_COLOR = {0.95, 0.9, 0.7}
function LK.bubble(object, text, range)
    local V = engine() and engine().SpeechView
    if V and V.show then return V.show(object, text, LK.BUBBLE_COLOR, LK.id(object)) end
    object:addLineChatElement(text, LK.BUBBLE_COLOR[1], LK.BUBBLE_COLOR[2], LK.BUBBLE_COLOR[3], UIFont.Medium, range,
        'RS_Speech', false, false, false, false, false, true)
end

function LK.id(object)
    for id, z in pairs(LK.objects()) do
        if rawequal(z, object) then return id end
    end
    return nil
end

-- Live registries (read only here), or nil.
local function npcRegistry()
    local S = engine().Store
    if not S then return nil end
    if not S.isReady() and not S.isBlocked() then S.ensure() end
    return S.data()
end

local function groupOf(id)
    local G = engine().Groups
    if not G or not G.ensure() then return nil end
    local gid, mid = G.findNpc(id)
    if not gid then return nil end
    local g = G.state.data.groups[gid]
    return g, gid, mid
end

-- Composed story of a group (server memory only: it holds the secrets, never sent as is), cached by type and seed.
local stories = {}
local function storyOf(g)
    local St = engine().Stories
    if not St or g.storySeed == nil then return nil end
    local key = tostring(g.type) .. ':' .. tostring(g.storySeed)
    if stories[key] == nil then stories[key] = St.compose(g.type, g.storySeed) or false end
    return stories[key] or nil
end

-- Name drawn from the story name lists, seeded by the NPC number (Park-Miller, no bitwise operator).
local function drawnName(id, female)
    local D = engine().StoryData
    local n = tonumber(string.match(id, '%d+')) or 1
    if type(D) ~= 'table' or type(D.surnames) ~= 'table' then return 'Survivor ' .. n end
    local firsts = female and D.firstNamesFemale or D.firstNamesMale
    local m = 2147483647
    local x = (n * 7919 + 104729) % m
    local function draw(k)
        x = (x * 48271) % m
        return 1 + math.floor(x / m * k)
    end
    return firsts[draw(#firsts)] .. ' ' .. D.surnames[draw(#D.surnames)]
end

local function hostileType(groupType)
    local H = engine().Hostility
    if not H then return nil end
    return H.levelOf(H.startFor(groupType)) == 'hostile'
end

function LK.npc(id)
    if not isId(id) then return nil end
    local registry = npcRegistry()
    local n = registry and registry.npcs[id]
    if not n then return nil end
    local female = type(n.profile) == 'table' and n.profile.female == true
    local record = {signature = 'lk:' .. id, group = '', hostile = nil}
    local g, gid, mid = groupOf(id)
    local member = g and g.members[mid]
    if member then
        record.group = gid
        record.groupName = g.name -- E17-T06: readable name shown in the notebook (never the raw id)
        record.hostile = hostileType(g.type)
        if type(member.female) == 'boolean' then female = member.female end
        if type(member.traits) == 'table' then
            local traits = {}
            for _, t in ipairs(member.traits) do
                if TRAITS[t] then traits[TRAITS[t]] = true end
            end
            record.traits = traits
        end
        local story = g.leader == mid and storyOf(g)
        if story then record.name = story.leader.name end
        -- E10-T04: a loner group is named after the NPC who left (its name kept from its former group).
        if g.type == LK.LONER_TYPE and type(g.name) == 'string' and g.name ~= '' then record.name = g.name end
    end
    record.name = record.name or drawnName(id, female)
    return record
end

-- ---------------------------------------------------------------- context for the LLM (authority)

function LK.context(id, character, language)
    local E = engine()
    local API = E.API
    if not API or not isId(id) then return nil end
    local g, gid, mid = groupOf(id)
    if not g then return {member = false} end
    local key = nil
    if E.Hostility and E.Hostility.validPlayerKey(character) then key = character end
    local view = API.publicGroup(API.getGroup(gid, key))
    if not view then return nil end
    local out = {member = true, group = view.name, type = view.type, needs = view.needs, morale = view.morale,
        alive = view.alive, role = g.members[mid].role, isLeader = g.leader == mid}
    local story = storyOf(g)
    local public = story and E.Stories.publicView(story)
    if public then
        out.summary = E.Stories.text(public, language)
        out.leaderName = public.leader and public.leader.name or nil
    else
        out.summary = view.summary
    end
    if view.attitude then out.attitude = {level = view.attitude.level, trend = view.attitude.trend} end
    -- E10-T02: the group's last collective decisions (journal entries of kind "decision", facts composed by LK.decide,
    -- never the leader's speech nor reasons), shared by the context of every member of the group.
    local decisions = {}
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        if #decisions < LK.DECISIONS_MAX and type(e) == 'table' and e.kind == 'decision' then
            table.insert(decisions, 1, {day = e.day, text = e.text})
        end
    end
    if #decisions > 0 then out.decisions = decisions end
    return out
end

-- ---------------------------------------------------------------- leader and collective decisions (E10-T02)

LK.DECISIONS_MAX = 4
local NEED_WORDS = {food = 'food', medical = 'medical supplies', ammo = 'ammunition'}

-- Group of the NPC for its collective decisions: leader and composition fingerprint read in the group registry
-- (LivingKnox.API.composition: computed, nothing stored). nil without group or off the authority.
function LK.composition(id)
    local API = engine().API
    if not authority() or not isId(id) or not API or not API.composition then return nil end
    local g, gid, mid = groupOf(id)
    if not gid then return nil end
    local c = API.composition(gid)
    if not c then return nil end
    local chief = c.leaderNpc and LK.npc(c.leaderNpc)
    return {ref = gid, key = c.key, leader = c.leader ~= nil and c.leader == mid, alive = c.alive,
        leaderName = chief and chief.name or nil, canLeave = LK.canLeave(g, mid, c)} -- E10-T04: canLeave
end

-- Collective decision of the NPC group written in its journal (LivingKnox.Groups.addLog, kind "decision"): one English
-- fact composed here from bounded fields, never the model's speech nor the leader's reasons.
function LK.decide(id, decision)
    local G = engine().Groups
    if not authority() or not isId(id) or not G or type(decision) ~= 'table' then return nil, 'unsupported' end
    local _, gid = groupOf(id)
    if not gid then return nil, 'no group' end
    local need = NEED_WORDS[decision.need]
    local who = type(decision.with) == 'string' and string.gsub(decision.with, '%c', ' ') or ''
    if not need or who == '' then return nil, 'bad decision' end
    local text
    if decision.kind == 'offer' then text = 'The leader asked ' .. who .. ' to bring ' .. need .. ' for the group.'
    elseif decision.kind == 'accept' then text = who .. ' agreed to bring ' .. need .. ' for the group.'
    else return nil, 'bad decision kind' end
    return G.addLog(gid, 'decision', text)
end

-- E09-T04 (authority): group basis of the personal relation of the NPC toward a notebook character: attitude of its
-- group (LivingKnox.API.attitude) and the last attitude facts of the group toward the character (API.attitudeFacts:
-- seen by a member or attributable), each with a stable key 'att:<group>:<n>'. nil without group or engine.
function LK.relation(id, character)
    local E = engine()
    local API = E.API
    if not authority() or not isId(id) or not API or not API.attitudeFacts or not E.Hostility
        or not E.Hostility.validPlayerKey(character) then return nil end
    local _, gid = groupOf(id)
    if not gid then return nil end
    local attitude = API.attitude(gid, character)
    if not attitude then return nil end
    local facts = {}
    for _, f in ipairs(API.attitudeFacts(gid, character) or {}) do
        facts[#facts + 1] = {key = 'att:' .. gid .. ':' .. string.format('%.0f', f.n), fact = f.fact, sign = f.sign,
            day = f.day}
    end
    return {ref = gid, attitude = {level = attitude.level, trend = attitude.trend}, facts = facts}
end

-- E10-T03 (authority): loyalty of the member to its group, derived from the group morale and its seniority
-- (LivingKnox.Decisions.loyaltyOfMember, nothing stored). nil without group or engine.
function LK.loyalty(id)
    local D = engine().Decisions
    if not authority() or not isId(id) or not D or not D.loyaltyOfMember then return nil end
    local g, _, mid = groupOf(id)
    if not g then return nil end
    return (D.loyaltyOfMember(g, mid))
end

-- E10-T03 (authority): a member contests or refuses a collective decision. Journal entry of kind "contest" or
-- "refusal" (fact composed here from d.name and d.about, never the spoken line), then the line d.text spoken by the
-- body through the proximity speech of LK11-T04 (LivingKnox.Speech.say); nobody near: journal only.
local DISSENT_KINDS = {contest = 'contest', refuse = 'refusal'}
local DISSENT_VERBS = {contest = ' contested a group decision: ', refuse = ' refused a group decision: '}
function LK.dissent(id, d)
    local E = engine()
    local G = E.Groups
    if not authority() or not isId(id) or not G or type(d) ~= 'table' or not DISSENT_KINDS[d.choice] then
        return nil, 'bad dissent'
    end
    local _, gid = groupOf(id)
    if not gid then return nil, 'no group' end
    local name = type(d.name) == 'string' and string.gsub(d.name, '%c', ' ') or ''
    local about = type(d.about) == 'string' and string.gsub(d.about, '%c', ' ') or ''
    if name == '' or about == '' then return nil, 'bad dissent' end
    local logged = G.addLog(gid, DISSENT_KINDS[d.choice], name .. DISSENT_VERBS[d.choice] .. about) == true
    local heard = 0
    if E.Speech and type(d.text) == 'string' then
        local out, why = E.Speech.say(id, d.text, {name = name})
        if out then heard = #out.heard
        else print(TAG .. 'dissent line of ' .. id .. ' not heard: ' .. tostring(why)) end
    end
    return {logged = logged, heard = heard}
end

-- ---------------------------------------------------------------- individual departure (E10-T04, authority)
-- Fiche docs/conception/depart.md. LK.leave(id, expect): the NPC leaves its group for good and lives alone. Checked
-- again now: same group (expect.ref), same composition fingerprint (expect.key, LivingKnox.API.composition), the NPC
-- may leave (LK.canLeave: alive member of a group of at least 2 living members, not a loner group, not on an
-- expedition). Home of the loner first (LivingKnox.Sites.pick, type loners: in a ring around the old home, E10-T05,
-- LK.homeOptions; far from every group home, the old one included; no site: nothing changes). Then ONE registry
-- transaction (LivingKnox.Groups.update, written at once by Groups.flush): new group of type loners named after the
-- NPC, with that home; new member linked to the same NPC (same role, profile, sex, traits, wound and vitals), its
-- leader; journal entry "separated" (old group id); the old member leaves (Groups.applyLeave, entry "left", fact
-- memberLeft with reason "leave_group"); if it led, immediate succession (Groups.pickSuccessor, as Groups.succeed).
-- The fiche, memories, observations and relations of the notebook are keyed by the NPC, never by its group:
-- unchanged. Then the engine memory of the NPC (decision frame, combat, defense, routines) is forgotten and the body
-- walks away toward its new home by one LK03 directive (Directives.moveTo, external: never replaced by the decision
-- frame), WALK_STEPS squares tried; it may fail (no body, no reachable square) without undoing the departure; the
-- body is released to the abstract simulation like any other once no player is near (Bodies.releasePass), then lives
-- at its new home (LK_Simulation). Former companions are told nothing.

LK.WALK_STEPS = {40, 28, 16, 8} -- squares toward the new home tried in turn (LivingKnox.Directives.MAX_TRIP = 60)
LK.NAME_MAX = 64                -- = LivingKnox.Groups.NAME_MAX

local function onTeam(holder, mid)
    if type(holder) ~= 'table' or type(holder.team) ~= 'table' then return false end
    for _, k in ipairs(holder.team) do
        if k == mid then return true end
    end
    return false
end

-- true when member mid of group g (composition c) may leave its group now.
function LK.canLeave(g, mid, c)
    local m = type(g) == 'table' and type(g.members) == 'table' and g.members[mid] or nil
    if m == nil or m.alive ~= true or g.type == LK.LONER_TYPE or g.gone ~= nil then return false end
    if type(c) ~= 'table' or (c.alive or 0) < 2 then return false end
    return not onTeam(g.expedition, mid) and not onTeam(type(g.trips) == 'table' and g.trips.cur or nil, mid)
end

-- Physical departure: one walk directive toward the new home. Returns the directive number, or nil and a reason.
local function walkAway(E, id, home)
    local D, B = E.Directives, E.Bodies
    local body = B and B.bound and B.bound[id] or nil
    if not D or not D.moveTo or body == nil then return nil, 'no body loaded' end
    if B.inWorld and not B.inWorld(body) then return nil, 'body not in the world' end
    local bx, by, bz = body:getX(), body:getY(), math.floor(body:getZ())
    local dx, dy = home.x + 0.5 - bx, home.y + 0.5 - by
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return nil, 'already at its new home' end
    local why = 'no step'
    for _, step in ipairs(LK.WALK_STEPS) do
        local k = math.min(step, len)
        local v, err = D.moveTo(id, bx + dx / len * k, by + dy / len * k, bz, 'walk')
        if v then return v end
        why = err
    end
    return nil, why
end

-- E10-T05: options of Sites.pick for the home of the loner: seed "leave/<id>" and, when the old group has a home, the
-- ring around it (LivingKnox.Config.LEAVE: HOME_MIN..HOME_MAX squares, widened by tiers before the whole map).
LK.LEAVE_DEFAULT = {HOME_MIN = 400, HOME_MAX = 1200} -- = LivingKnox.Config.LEAVE when that table is missing

function LK.homeOptions(id, g)
    local opts = {seed = 'leave/' .. tostring(id)}
    local h = type(g) == 'table' and g.home or nil
    if type(h) == 'table' and type(h.x) == 'number' and type(h.y) == 'number' then
        local C = engine().Config
        local cfg = C and type(C.LEAVE) == 'table' and C.LEAVE or LK.LEAVE_DEFAULT
        opts.near = {x = h.x, y = h.y, min = cfg.HOME_MIN or LK.LEAVE_DEFAULT.HOME_MIN,
            max = cfg.HOME_MAX or LK.LEAVE_DEFAULT.HOME_MAX}
    end
    return opts
end

function LK.leave(id, expect)
    local E = engine()
    local G, API, Sites = E.Groups, E.API, E.Sites
    if not authority() or not isId(id) or not G or not API or not API.composition or not Sites or not Sites.pick then
        return nil, 'unsupported'
    end
    if type(expect) ~= 'table' or type(expect.ref) ~= 'string' or type(expect.key) ~= 'string' then
        return nil, 'bad expectation'
    end
    local g, gid, mid = groupOf(id)
    if not g or gid ~= expect.ref then return nil, 'NPC no longer in the group' end
    local c = API.composition(gid)
    if not c or c.key ~= expect.key then return nil, 'group composition changed' end
    if not LK.canLeave(g, mid, c) then return nil, 'NPC may not leave its group now' end
    local def = E.GroupTypes and E.GroupTypes.get(LK.LONER_TYPE)
    if not def then return nil, 'group type ' .. LK.LONER_TYPE .. ' not registered' end
    local name = string.sub((string.gsub(LK.npc(id).name, '%c', ' ')), 1, LK.NAME_MAX)
    local site, why = Sites.pick(LK.LONER_TYPE, LK.homeOptions(id, g))
    if not site then return nil, 'no home for the loner: ' .. tostring(why) end
    local home = {x = math.floor(site.x), y = math.floor(site.y), z = math.floor(site.z or 0)}
    local day = G.today()
    local out = G.update(function(data)
        local old = data.groups[gid]
        local m = old and old.members[mid]
        if not m or m.npc ~= id or not m.alive then return false, {why = 'NPC no longer in the group'} end
        local ng, bad = G.applyCreate(data, {type = LK.LONER_TYPE, name = name, story = '', home = home, day = day,
            needs = def.needs, morale = def.morale})
        if not ng then return false, {why = 'loner group refused: ' .. tostring(bad)} end
        local nm, refused = G.applyMember(ng, {role = m.role, npc = m.npc, profile = m.profile, female = m.female,
            traits = m.traits}, day)
        if not nm then
            data.groups[ng.id] = nil   -- identifier never reused (nextId kept)
            return true, {why = 'loner member refused: ' .. tostring(refused)}
        end
        ng.members[nm].wound, ng.members[nm].vitals = m.wound, G.copy(m.vitals)
        G.applyLeader(ng, nm, day)
        G.appendLog(ng, 'separated', gid, day)
        local wasLeader = G.applyLeave(old, mid, day, 'leave_group')
        local successor = nil
        if wasLeader then
            successor = G.pickSuccessor(old)
            if successor then G.applyLeader(old, successor, day) end
        end
        return true, {ref = ng.id, member = nm, wasLeader = wasLeader, successor = successor}
    end)
    if type(out) ~= 'table' then return nil, 'group registry not ready' end
    if out.why then return nil, out.why end
    if not G.flush() then print(TAG .. 'departure of ' .. id .. ': group registry not written now') end
    if E.Decisions and E.Decisions.forget then E.Decisions.forget(id) end
    local walk, walkWhy = walkAway(E, id, home)
    print(TAG .. id .. ' left ' .. gid .. ' (' .. mid .. (out.wasLeader and ', leader' or '') .. ') for ' .. out.ref
        .. ' (' .. LK.LONER_TYPE .. ', home ' .. home.x .. ',' .. home.y .. ',' .. home.z .. ')'
        .. (out.successor and ('; new leader of ' .. gid .. ': ' .. out.successor) or '')
        .. '; walk away: ' .. (walk and ('#' .. walk) or tostring(walkWhy)))
    return {ref = out.ref, from = gid, groupName = name, member = out.member, successor = out.successor, walk = walk,
        walkWhy = walkWhy}
end

-- ---------------------------------------------------------------- presence (authority, E08-T08)

-- Where the NPC is, for the world observations of the notebook (server memory only, never sent): away = member of the
-- team of an expedition in progress (LK_Simulation), x, y = home of its group (nil without home). An NPC without group
-- is never away. nil off the authority or for a foreign id.
function LK.presence(id)
    if not authority() or not isId(id) then return nil end
    local g, _, mid = groupOf(id)
    if not g then return {away = false} end
    local away = false
    local e = g.expedition
    if type(e) == 'table' and type(e.team) == 'table' then
        for _, k in ipairs(e.team) do
            if k == mid then away = true end
        end
    end
    local home = type(g.home) == 'table' and g.home or nil
    return {away = away, x = home and home.x or nil, y = home and home.y or nil}
end

-- E08-T03, authority: initiatives of the notebook. engaged = LivingKnox.API.engaged (hit, combat, warning, alert);
-- say / bark = the proximity speech channel of LK11-T04 (LivingKnox.Speech), nil and a reason without it.
function LK.engaged(id)
    local API = engine() and engine().API
    if not authority() or not isId(id) or not API or type(API.engaged) ~= 'function' then return false end
    return API.engaged(id)
end

function LK.say(id, text, opts)
    local S = engine() and engine().Speech
    if not authority() or not isId(id) or not S then return nil, 'speech unavailable' end
    return S.say(id, text, opts)
end

function LK.bark(id, situation, opts)
    local S = engine() and engine().Speech
    if not authority() or not isId(id) or not S then return nil, 'speech unavailable' end
    return S.bark(id, situation, opts)
end

-- ---------------------------------------------------------------- group radios (E08-T06, authority)
-- Fiche docs/conception/radio-groupes.md. A group is a voice of the radio network while it holds a transmitter that a
-- living member can use now (group type format 2, LK_GroupTypes): homeRadio = a station at its home, used by a living
-- member who is not away (expedition team, physical trip); radio = true in a profile = each member of this profile
-- carries a walkie-talkie, even away. A gone group (wiped, dispersed) or a group without a living member has no radio.
-- speaker = NPC who answers: the leader when it can reach a transmitter, otherwise the most senior member who can.
-- Read only, nothing stored; never a home nor a position in the result.

local function radioSpeaker(g, def)
    local carried = {}
    for _, p in ipairs(def.profiles or {}) do
        if p.radio == true then carried[p.id] = true end
    end
    local trip = type(g.trips) == 'table' and g.trips.cur or nil
    local function reaches(mid)
        local m = g.members[mid]
        if type(m) ~= 'table' or m.alive ~= true or not isId(m.npc) then return false end
        if carried[m.profile] then return true end
        return def.homeRadio == true and type(g.home) == 'table' and not onTeam(g.expedition, mid)
            and not onTeam(trip, mid)
    end
    if g.leader ~= nil and reaches(g.leader) then return g.members[g.leader].npc end
    local G = engine().Groups
    local ids = {}
    for mid in pairs(g.members) do ids[#ids + 1] = mid end
    table.sort(ids, function(a, b)
        local na, nb = G.memberNumber(a), G.memberNumber(b)
        if na and nb then return na < nb end
        return tostring(a) < tostring(b)
    end)
    for _, mid in ipairs(ids) do
        if reaches(mid) then return g.members[mid].npc end
    end
    return nil
end

-- { { ref = "grp-<n>", name = group name, speaker = "lk-<n>" }, ... } sorted by ref; empty off the authority or
-- before the registries are ready.
function LK.radios()
    local E = engine()
    local G, GT = E.Groups, E.GroupTypes
    local out = {}
    if not authority() or not G or not GT or not G.ensure() then return out end
    for _, gid in ipairs(G.list()) do
        local g = G.state.data.groups[gid]
        local def = type(g) == 'table' and g.gone == nil and GT.peek(g.type) or nil
        local speaker = def and radioSpeaker(g, def)
        if speaker then out[#out + 1] = {ref = gid, name = tostring(g.name or ''), speaker = speaker} end
    end
    table.sort(out, function(a, b) return a.ref < b.ref end)
    return out
end

-- ---------------------------------------------------------------- supplies (authority)

-- Open offers of the NPC group for this character, in the provider-neutral shape of RS_NPCProvider.supplies.
function LK.supplies(id, character)
    local E = engine()
    local API = E.API
    local out = {}
    if not API or not API.missionOffers or not isId(id) or type(character) ~= 'string' then return out end
    local _, gid = groupOf(id)
    if not gid then return out end
    local offers = API.missionOffers(gid, character)
    for _, o in ipairs(offers or {}) do
        if NEEDS[o.need] and o.remaining > 0 then
            local items = {}
            for _, it in ipairs(o.items) do items[#items + 1] = {type = it.type, value = it.value} end
            local reward = o.reward and o.reward.item
            out[#out + 1] = {ref = gid, offer = o.id, need = o.need, level = o.level, value = o.value,
                remaining = o.remaining, items = items, hours = o.hours,
                reward = reward and {type = reward.type, count = reward.count} or nil}
        end
    end
    return out
end

-- true: the offer is still open; false: closed (expired, filled, group gone); nil: unknown (registry not ready).
function LK.supplyOpen(ref, offer)
    local API = engine().API
    if not API or not API.missionOffers then return nil end
    local offers, why = API.missionOffers(ref)
    if not offers then
        if why ~= nil and string.find(tostring(why), 'unknown group', 1, true) then return false end
        return nil
    end
    for _, o in ipairs(offers) do
        if o.id == offer then return true end
    end
    return false
end

function LK.supplyDeliver(ref, offer, delivered, receipt, character)
    local E = engine()
    local API = E.API
    if not API or not API.deliver then return nil, 'no engine' end
    local r, why = API.deliver(ref, offer, delivered, receipt, character)
    if not r then return nil, why end
    if r.applied and r.completed and E.Hostility then
        local ok, err = E.Hostility.record(ref, character, 'delivery', {attributable = true})
        if not ok then print(TAG .. 'attitude fact delivery not recorded for ' .. tostring(ref) .. ': ' .. tostring(err)) end
    end
    local reward = r.reward and r.reward.item
    return {applied = r.applied == true, duplicate = r.duplicate == true, value = r.value, points = r.points,
        level = r.level, completed = r.completed == true,
        reward = reward and {type = reward.type, count = reward.count} or nil}
end

-- ---------------------------------------------------------------- registration

local state = {installed = false, warned = false}
LK.state = state

-- Registers the provider once Living Knox is enabled. Returns true when Living Knox is the active provider.
function LK.install()
    if state.installed then return P.active() == LK end
    local E = engine()
    if type(E) ~= 'table' or type(E.Config) ~= 'table' or not E.Config.isEnabled() then return false end
    local current = P.active()
    if current.name ~= 'none' and current.name ~= LK.name then
        if not state.warned then
            print(TAG .. 'another NPC provider (' .. tostring(current.name)
                .. ') is active: Living Knox is not registered in the notebook (one NPC engine per server)')
            state.warned = true
        end
        return false
    end
    if not P.register(LK) then return false end
    state.installed = true
    if authority() and E.Bodies then
        E.Bodies.onDied = function(id, body, cause) P.emit('death', id, body, cause) end
    end
    return true
end

Events.OnInitGlobalModData.Add(function() LK.install() end)
Events.OnGameStart.Add(function() LK.install() end)
Events.OnServerStarted.Add(function() LK.install() end)

return LK
