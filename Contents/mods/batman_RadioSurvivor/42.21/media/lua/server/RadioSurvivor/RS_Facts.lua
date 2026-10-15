if isClient() then return end
--[[
Server fact log of the day (E14-T01), read by the evening bulletin (E14-T02) and the memorial (E14-T03). Authority
only (dedicated server or solo). Design: docs/conception/chronique.md.

Stored in the private state of the notebook (RS_State: S.data.facts, server file, never a global ModData):
    { next = <number of the next fact>, list = { fact, ... }, seen = { [key] = n }, world = { grid, water, weather } }
A fact: { n, kind, day (1 = first game day), hour (0..23), <fields of its kind> }. No coordinate is ever stored: a
place is { key = TownIn | TownOutskirts | TownCountry | TownFar, town = <vanilla town name> or nil }, rounded by
RS_Rescue.town (vanilla map only; otherwise no place). No conversation text is read or stored.

Sources (closed list, Facts.KINDS):
    death        OnCharacterDeath of an IsoPlayer (fires on the dedicated server, OnPlayerDeath does not): name of the
                 character (descriptor), place of the body.
    mission      RS_Missions.onFinished (chained after RS_ObservationTriggers): success, failed, abandoned (no
                 cancellation): template, requester name, participant names, place of the requester body if loaded.
    rescue       reserved for E12-T04/T05: Facts.record('rescue', { result, requester, participants, place }).
    passage      reserved for E13 (smuggler): Facts.record('passage', { event, name, place }).
    power_cut    EveryHours poll of SandboxOptions.doesPowerGridExist: present -> absent (no Lua event exists).
    water_cut    EveryHours poll: GameTime.getWorldAgeDaysSinceBegin() < SandboxOptions.getWaterShutModifier() goes
                 from true to false (same test as IsoObject.java:2544 and ParameterWaterSupply.java:18).
    weather      EveryHours poll (RS_ObservationTriggers.weatherNow): start of a storm, tropical storm or blizzard.
    group_death  public event OnLivingKnoxMemberDied: group name, role, cause, byPlayer, offscreen, place.
    group_gone   public event OnLivingKnoxGroupGone: group name, reason.
    group_new    public event OnLivingKnoxGroupCreated: group name, type key, place (at most CAPS.group_new a day).
    Not recorded: encounters, attitudes and needs of Living Knox (they concern one player or are internal).

Bounds: at most MAX_FACTS facts (when full, the oldest fact that is not a death goes first), CAPS[kind] per kind and
day, strings cut to MAX_CHARS, at most MAX_NAMES names per list, any string with three digits in a row refused (no
coordinate can slip through a name).

Reading and purge (API of the bulletin):
    Facts.list([since]) -> { day, next, facts = { copies, oldest first } }    facts with n > since (default 0)
    Facts.purge(through) -> removed                                         the bulletin purges what it read
    Without bulletin (missed evening), Facts.expire runs at every EveryHours poll: the facts of a day are dropped at
    the start of the day after the next one (day < today - 1), so a late-evening fact still reaches the next bulletin.

Evening bulletin (E14-T02): at the EveryHours poll, once the hour of the sandbox option RadioSurvivor.ChronicleHour
is reached in the fact day (7 am to 7 am) and no bulletin was aired for that day (book.aired), Facts.bulletin reads
the log, sends to the bridge (RS_RadioServer.submit, kind=bulletin) the voice of the chronicler (Facts.CHRONICLER)
and the confirmed facts as English sentences (Facts.factText, built from the closed fields only), then airs the
bridge text on the first frequency of the chronicler, or after BULLETIN_TIMEOUT_MS (Const.BRIDGE_TIMEOUT_MS while
the bridge is seen alive, E17-T16) a fixed fallback built from the
same facts (Facts.fallbackLines, translated keys IGUI_RS_Bulletin_*, language of the authority). Then book.aired =
day and the facts read are purged. A bulletin lost by a restart before it is aired is requested again at the next
poll of the same evening. Without the radio server (RS_RadioServer) or an active chronicler: no bulletin.
Memorial (E14-T03): the deaths read by the bulletin are never given to the bridge by name (one sentence tells their
number and that the names are read at the end) nor told by the fallback; the server itself reads, at the end of the
bulletin, a translated opening line and the names of the dead (Facts.memorialLines, one name per death fact, no
text of the LLM): after the bridge lines, or before the closing line of the fallback.
Pure core (in-memory book, used by the RST suite): Facts.add(book, kind, fields, day, hour, key), Facts.read(book,
since), Facts.drop(book, through), Facts.expireBook(book, today).
Console messages in English.
]]
local S = require 'RadioSurvivor/RS_State'
local M = require 'RadioSurvivor/RS_Missions'
local Rescue = require 'RadioSurvivor/RS_Rescue'
local Triggers = require 'RadioSurvivor/RS_ObservationTriggers'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local Codec = require 'RadioSurvivor/RS_Codec'

local Facts = {pending = {}}

Facts.MAX_FACTS = 80
Facts.MAX_CHARS = 48
Facts.MAX_NAMES = 8
Facts.KEEP_DAYS = 1
Facts.DEFAULT_CAP = 16
Facts.CAPS = {death = 32, group_new = 3, weather = 3, power_cut = 1, water_cut = 1}
Facts.PLACE_KEYS = {TownIn = true, TownOutskirts = true, TownCountry = true, TownFar = true}
Facts.MISSION_RESULTS = {success = true, failed = true, abandoned = true}

-- Fields of each kind: word (identifier), name (short text), names (list of names), bool, place. required: first field.
Facts.KINDS = {
    death = {fields = {name = 'name', place = 'place'}, required = 'name'},
    mission = {fields = {template = 'word', result = 'word', requester = 'name', participants = 'names',
        place = 'place'}, required = 'result'},
    rescue = {fields = {result = 'word', requester = 'name', participants = 'names', place = 'place'},
        required = 'result'},
    passage = {fields = {event = 'word', name = 'name', place = 'place'}, required = 'event'},
    power_cut = {fields = {}},
    water_cut = {fields = {}},
    weather = {fields = {weather = 'word'}, required = 'weather'},
    group_death = {fields = {group = 'name', role = 'word', cause = 'word', byPlayer = 'bool', offscreen = 'bool',
        place = 'place'}},
    group_gone = {fields = {group = 'name', reason = 'word'}},
    group_new = {fields = {group = 'name', typeKey = 'word', place = 'place'}},
}

local function log(msg)
    Const.log('facts: ' .. msg)
end

local TOWN_NAMES = {}
for _, town in ipairs(Rescue.TOWNS) do TOWN_NAMES[town.name] = true end

-- ------------------------------------------------------------------------------------------------ validation

local function cleanName(value)
    if type(value) ~= 'string' then return nil end
    local text = Const.oneLine(string.gsub(value, '[%c<>%[%]]', ' '))
    text = string.gsub(text, '%s+', ' ')
    if text == '' or string.find(text, '%d%d%d') then return nil end
    if string.len(text) > Facts.MAX_CHARS then text = Const.oneLine(string.sub(text, 1, Facts.MAX_CHARS)) end
    return text
end

local function cleanWord(value)
    if type(value) ~= 'string' or string.len(value) > 40 or not string.find(value, '^[%w_]+$') then return nil end
    if string.find(value, '%d%d%d') then return nil end
    return value
end

local function cleanPlace(value)
    if type(value) ~= 'table' or not Facts.PLACE_KEYS[value.key] then return nil end
    for k in pairs(value) do
        if k ~= 'key' and k ~= 'town' then return nil end
    end
    if value.town ~= nil and not TOWN_NAMES[value.town] then return nil end
    return {key = value.key, town = value.town}
end

local function cleanNames(value)
    if type(value) ~= 'table' then return nil end
    local out = {}
    for _, v in ipairs(value) do
        local name = cleanName(v)
        if name and #out < Facts.MAX_NAMES then out[#out + 1] = name end
    end
    if #out == 0 then return nil end
    return out
end

local CLEAN = {name = cleanName, word = cleanWord, place = cleanPlace, names = cleanNames,
    bool = function(v) if type(v) == 'boolean' then return v end return nil end}

-- Copy of the admitted fields of a kind, or nil and the reason.
function Facts.validate(kind, fields)
    local spec = Facts.KINDS[kind]
    if not spec then return nil, 'kind' end
    if fields ~= nil and type(fields) ~= 'table' then return nil, 'fields' end
    local out = {}
    for k, v in pairs(fields or {}) do
        local type_ = spec.fields[k]
        if not type_ then return nil, 'field ' .. tostring(k) end
        out[k] = CLEAN[type_](v)
    end
    if spec.required and out[spec.required] == nil then return nil, 'missing ' .. spec.required end
    return out
end

-- ------------------------------------------------------------------------------------------------ pure core

function Facts.newBook()
    return {next = 1, list = {}, seen = {}, world = {}}
end

local function validBook(book)
    return type(book) == 'table' and type(book.list) == 'table' and type(book.seen) == 'table'
        and type(book.next) == 'number' and type(book.world) == 'table'
end

local function removeAt(book, i)
    local fact = table.remove(book.list, i)
    for key, n in pairs(book.seen) do
        if n == fact.n then book.seen[key] = nil end
    end
    return fact
end

-- Adds a fact to a book. key (optional): one fact per key while the fact is kept. Returns n, or nil and the reason.
function Facts.add(book, kind, fields, day, hour, key)
    if type(day) ~= 'number' or day < 1 or day ~= math.floor(day) then return nil, 'day' end
    if type(hour) ~= 'number' or hour < 0 or hour > 23 or hour ~= math.floor(hour) then return nil, 'hour' end
    local clean, reason = Facts.validate(kind, fields)
    if not clean then return nil, reason end
    if key ~= nil and book.seen[key] then return nil, 'duplicate' end
    local sameDay = 0
    for _, f in ipairs(book.list) do
        if f.kind == kind and f.day == day then sameDay = sameDay + 1 end
    end
    if sameDay >= (Facts.CAPS[kind] or Facts.DEFAULT_CAP) then return nil, 'cap' end
    if #book.list >= Facts.MAX_FACTS then
        local victim = 1
        for i, f in ipairs(book.list) do
            if f.kind ~= 'death' then victim = i; break end
        end
        removeAt(book, victim)
    end
    local fact = {n = book.next, kind = kind, day = day, hour = hour}
    for k, v in pairs(clean) do fact[k] = v end
    book.next = book.next + 1
    book.list[#book.list + 1] = fact
    if key ~= nil then book.seen[key] = fact.n end
    return fact.n
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

-- Copies of the facts with n > since, oldest first.
function Facts.read(book, since)
    since = type(since) == 'number' and since or 0
    local out = {}
    for _, f in ipairs(book.list) do
        if f.n > since then out[#out + 1] = copy(f) end
    end
    return out
end

-- Removes the facts with n <= through. Returns the number removed.
function Facts.drop(book, through)
    if type(through) ~= 'number' then return 0 end
    local removed, i = 0, 1
    while i <= #book.list do
        if book.list[i].n <= through then removeAt(book, i); removed = removed + 1 else i = i + 1 end
    end
    return removed
end

-- Removes the facts of the days before today - KEEP_DAYS. Returns the number removed.
function Facts.expireBook(book, today)
    if type(today) ~= 'number' then return 0 end
    local removed, i = 0, 1
    while i <= #book.list do
        if book.list[i].day < today - Facts.KEEP_DAYS then removeAt(book, i); removed = removed + 1 else i = i + 1 end
    end
    return removed
end

-- ------------------------------------------------------------------------------------------------ world

-- Game day (1 = first) and hour of the day (0..23, world age starts at 7 am), or nil without a clock.
function Facts.now()
    local hours = Triggers.worldHour()
    if not hours then return nil end
    return math.floor(hours / 24) + 1, (hours + 7) % 24
end

-- Place rounded to the town of (x, y), or nil (no vanilla map, no position). Never keeps the coordinates.
function Facts.place(x, y)
    if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
    local _, key, name = Rescue.town(x, y)
    if not key then return nil end
    return {key = key, town = name}
end

function Facts.placeOf(object)
    if not object or not object.getX then return nil end
    return Facts.place(object:getX(), object:getY())
end

-- English phrase of a place for a prompt ('' without place).
function Facts.placeText(place)
    if type(place) ~= 'table' then return '' end
    if place.key == 'TownIn' then return 'in ' .. tostring(place.town) end
    if place.key == 'TownOutskirts' then return 'on the outskirts of ' .. tostring(place.town) end
    if place.key == 'TownCountry' then return 'in the country, some way from ' .. tostring(place.town) end
    if place.key == 'TownFar' then return 'in the countryside, far from any town' end
    return ''
end

-- Running water of the world (true), cut (false), or nil without the options or the clock.
function Facts.waterOn()
    local options = getSandboxOptions and getSandboxOptions()
    local gt = getGameTime and getGameTime()
    if not options or not options.getWaterShutModifier or not gt or not gt.getWorldAgeDaysSinceBegin then return nil end
    return gt:getWorldAgeDaysSinceBegin() < options:getWaterShutModifier()
end

-- ------------------------------------------------------------------------------------------------ private state

-- Book of the private state, or nil before the state is loaded.
function Facts.book()
    if not S.data then return nil end
    if not validBook(S.data.facts) then S.data.facts = Facts.newBook() end
    local book = S.data.facts
    if #Facts.pending > 0 then
        local pending = Facts.pending
        Facts.pending = {}
        for _, p in ipairs(pending) do Facts.add(book, p.kind, p.fields, p.day, p.hour, p.key) end
        S.dirty = true
    end
    return book
end

-- Records a fact of the day in the private state (or in memory until the state is loaded). Returns n (nil while
-- pending), or nil and the reason.
function Facts.record(kind, fields, key)
    local day, hour = Facts.now()
    if not day then return nil, 'clock' end
    local book = Facts.book()
    if not book then
        local clean, reason = Facts.validate(kind, fields)
        if not clean then return nil, reason end
        if #Facts.pending < Facts.MAX_FACTS then
            Facts.pending[#Facts.pending + 1] = {kind = kind, fields = clean, day = day, hour = hour, key = key}
        end
        return nil, 'pending'
    end
    local n, reason = Facts.add(book, kind, fields, day, hour, key)
    if n then
        S.dirty = true
        S.save()
        log('recorded ' .. kind .. ' #' .. n)
    elseif reason ~= 'duplicate' then
        log('refused ' .. tostring(kind) .. ': ' .. tostring(reason))
    end
    return n, reason
end

function Facts.list(since)
    local day = Facts.now()
    local book = Facts.book()
    if not book then return {day = day, next = 1, facts = {}} end
    return {day = day, next = book.next, facts = Facts.read(book, since)}
end

function Facts.purge(through)
    local book = Facts.book()
    if not book then return 0 end
    local removed = Facts.drop(book, through)
    if removed > 0 then S.dirty = true; S.save() end
    return removed
end

function Facts.expire()
    local book, today = Facts.book(), Facts.now()
    if not book or not today then return 0 end
    local removed = Facts.expireBook(book, today)
    if removed > 0 then S.dirty = true end
    return removed
end

-- ------------------------------------------------------------------------------------------------ sources

-- OnCharacterDeath: players only (zombies and Living Knox bodies also raise it).
function Facts.characterDeath(character)
    if not instanceof(character, 'IsoPlayer') then return end
    local d = character:getDescriptor()
    if not d then return end
    local name = Const.oneLine((d:getForename() or '') .. ' ' .. (d:getSurname() or ''))
    local owner = isServer() and character:getUsername() or 'solo'
    local day = Facts.now()
    Facts.record('death', {name = name, place = Facts.placeOf(character)},
        'death|' .. tostring(owner) .. '|' .. name .. '|' .. tostring(day))
end

-- RS_Missions.onFinished (chained).
function Facts.missionFinished(state, mission, result)
    if type(mission) ~= 'table' or not Facts.MISSION_RESULTS[result] then return end
    local donor = type(state) == 'table' and M.donorOf(state, mission) or nil
    local requester = donor and donor.name or mission.requesterName
    local names = {}
    for _, member in pairs(mission.participants or {}) do
        if type(member) == 'table' and type(member.name) == 'string' then names[#names + 1] = member.name end
    end
    table.sort(names)
    local server = RS_CarnetServer
    local body = server and server.objects and server.objects[mission.npc]
    Facts.record('mission', {template = mission.template or 'deliver', result = result, requester = requester,
        participants = names, place = Facts.placeOf(body)}, 'mission|' .. tostring(mission.id))
end

local chained
-- Installs Facts.missionFinished after the current listener of RS_Missions (RS_ObservationTriggers.attach sets it
-- when the notebook server loads, after this file). Called again at each poll: a listener set later is wrapped too.
function Facts.chain()
    if chained and M.onFinished == chained then return end
    local previous = M.onFinished
    chained = function(state, mission, result)
        if previous then previous(state, mission, result) end
        Facts.missionFinished(state, mission, result)
    end
    M.onFinished = chained
end

local function groupName(id)
    local LK = LivingKnox
    local api = type(LK) == 'table' and LK.API
    if type(id) ~= 'string' or type(api) ~= 'table' or type(api.getGroup) ~= 'function' then return nil end
    local view = api.getGroup(id)
    return type(view) == 'table' and type(view.name) == 'string' and view.name or nil
end

local function areaPlace(area)
    if type(area) ~= 'table' then return nil end
    return Facts.place(area.x, area.y)
end

function Facts.lkMemberDied(e)
    if type(e) ~= 'table' or type(e.group) ~= 'string' then return end
    Facts.record('group_death', {group = groupName(e.group), role = e.role, cause = e.cause,
        byPlayer = e.byPlayer == true, offscreen = e.offscreen == true, place = areaPlace(e.area)},
        'lkdied|' .. e.group .. '|' .. tostring(e.member))
end

function Facts.lkGroupGone(e)
    if type(e) ~= 'table' or type(e.group) ~= 'string' then return end
    Facts.record('group_gone', {group = groupName(e.group), reason = e.reason}, 'lkgone|' .. e.group)
end

function Facts.lkGroupCreated(e)
    if type(e) ~= 'table' or type(e.group) ~= 'string' then return end
    Facts.record('group_new', {group = e.name or groupName(e.group), typeKey = e.typeNameKey,
        place = areaPlace(e.area)}, 'lknew|' .. e.group)
end

-- One poll of the world state: start of a weather episode, power and water cuts (state kept in the book).
local function transition(world, field, now, kind)
    if now == true then world[field] = true
    elseif now == false then
        if world[field] == true then Facts.record(kind, {}) end
        world[field] = false
    end
end

function Facts.hourly()
    Facts.chain()
    local book = Facts.book()
    if not book or not Facts.now() then return end
    Facts.expire()
    local world = book.world
    local before = {world.grid, world.water, world.weather}
    transition(world, 'grid', Triggers.gridPower(), 'power_cut')
    transition(world, 'water', Facts.waterOn(), 'water_cut')
    local weather = Triggers.weatherNow()
    if weather and weather ~= world.weather then
        local day = Facts.now()
        Facts.record('weather', {weather = weather}, 'weather|' .. weather .. '|' .. tostring(day))
    end
    world.weather = weather
    if before[1] ~= world.grid or before[2] ~= world.water or before[3] ~= world.weather then S.dirty = true end
    -- After the poll: a cut or a storm of this hour is in tonight's bulletin.
    Facts.bulletin()
end

-- ------------------------------------------------------------------------------------------------ evening bulletin

Facts.CHRONICLER = 'nightowl'
Facts.DEFAULT_CHRONICLE_HOUR = 20
Facts.BULLETIN_TIMEOUT_MS = 60000   -- without a bridge; a bridge seen alive: Const.BRIDGE_TIMEOUT_MS (E17-T16)
Facts.BULLETIN_MAX_FACTS = 12
Facts.BULLETIN_FACT_CHARS = 200
Facts.BULLETIN_MAX_LINES = 6
Facts.FALLBACK_MAX_FACTS = 5
Facts.MAX_TEXT_NAMES = 4
-- Bulletin waiting for the bridge (in memory only): { day, through, khz, facts }.
Facts.flight = nil

-- Hour of the bulletin (0..23): sandbox option RadioSurvivor.ChronicleHour (registered option first: in solo the
-- in-game editor does not update SandboxVars before the next load), then SandboxVars, then the default.
function Facts.chronicleHour()
    local value
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options.getOptionByName and options:getOptionByName('RadioSurvivor.ChronicleHour')
    if option then value = option:getValue() end
    if value == nil then
        local vars = SandboxVars and SandboxVars.RadioSurvivor
        value = vars and vars.ChronicleHour
    end
    value = tonumber(value)
    if not value or value < 0 or value > 23 or value ~= math.floor(value) then return Facts.DEFAULT_CHRONICLE_HOUR end
    return value
end

-- The bulletin of a fact day is due once its hour is reached; a fact day runs from 7 am to 7 am, so an hour before
-- 7 am belongs to the evening of the previous calendar day. (+ 17 instead of - 7: Kahlua's % truncates to zero.)
function Facts.bulletinDue(book, day, hour, chronicleHour)
    if book.aired == day then return false end
    return (hour + 17) % 24 >= (chronicleHour + 17) % 24
end

-- The facts told by a bulletin: at most max, the deaths first, oldest first.
function Facts.select(facts, max)
    local picked, count = {}, 0
    for pass = 1, 2 do
        for _, f in ipairs(facts) do
            if count < max and ((pass == 1) == (f.kind == 'death')) then
                picked[f.n] = true
                count = count + 1
            end
        end
    end
    local out = {}
    for _, f in ipairs(facts) do
        if picked[f.n] then out[#out + 1] = f end
    end
    return out
end

-- The facts of a bulletin split into the deaths (read by the memorial) and the others, both oldest first.
function Facts.split(facts)
    local others, deaths = {}, {}
    for _, f in ipairs(type(facts) == 'table' and facts or {}) do
        if f.kind == 'death' then deaths[#deaths + 1] = f else others[#others + 1] = f end
    end
    return others, deaths
end

-- English sentence given to the bridge instead of the names of the dead (nil without death): the names are read by
-- the server after the bulletin, so the bridge never names them.
function Facts.deathsText(count)
    if type(count) ~= 'number' or count < 1 then return nil end
    local who = count == 1 and 'One survivor' or (tostring(count) .. ' survivors')
    return who .. ' died since the last bulletin. Their names are read at the very end, after your sign-off: '
        .. 'do not name them and do not say how or where they died.'
end

local function nameList(names)
    if type(names) ~= 'table' then return nil end
    local out = {}
    for _, name in ipairs(names) do
        if #out < Facts.MAX_TEXT_NAMES then out[#out + 1] = name end
    end
    if #out == 0 then return nil end
    return table.concat(out, ', ')
end

local function withPlace(text, place)
    local where = Facts.placeText(place)
    if where == '' then return text end
    return text .. ' ' .. where
end

local WEATHER_TEXT = {storm = 'A thunderstorm broke out.', tropical_storm = 'A tropical storm hit the county.',
    blizzard = 'A blizzard swept the county.'}
local RESULT_TEXT = {success = 'was carried out', failed = 'failed', abandoned = 'was abandoned'}

-- English sentence of a fact for the prompt of the bulletin, built from its closed fields only (never a coordinate,
-- never a conversation), at most BULLETIN_FACT_CHARS characters; nil for an unknown kind.
function Facts.factText(f)
    local text
    if f.kind == 'death' then
        text = withPlace('A survivor, ' .. tostring(f.name) .. ', died', f.place) .. '.'
    elseif f.kind == 'mission' then
        text = 'A job (' .. tostring(f.template or 'job') .. ')'
        if f.requester then text = text .. ' for ' .. f.requester end
        text = text .. ' ' .. (RESULT_TEXT[f.result] or 'ended')
        local names = nameList(f.participants)
        if names then text = text .. ', taken by ' .. names end
        text = withPlace(text, f.place) .. '.'
    elseif f.kind == 'rescue' then
        text = 'A rescue ended (outcome: ' .. tostring(f.result) .. ')'
        if f.requester then text = text .. ', called by ' .. f.requester end
        local names = nameList(f.participants)
        if names then text = text .. ', rescuers: ' .. names end
        text = withPlace(text, f.place) .. '.'
    elseif f.kind == 'passage' then
        text = 'The smuggler was reported (' .. tostring(f.event) .. ')'
        if f.name then text = text .. ', ' .. f.name end
        text = withPlace(text, f.place) .. '.'
    elseif f.kind == 'power_cut' then
        text = 'The power grid went down across the county.'
    elseif f.kind == 'water_cut' then
        text = 'The running water stopped across the county.'
    elseif f.kind == 'weather' then
        text = WEATHER_TEXT[f.weather] or ('Severe weather: ' .. tostring(f.weather) .. '.')
    elseif f.kind == 'group_death' then
        text = 'A member of ' .. (f.group and ('the group ' .. f.group) or 'a group of survivors')
        if f.role then text = text .. ' (' .. f.role .. ')' end
        text = text .. ' died'
        if f.byPlayer then text = text .. ', killed by a survivor' end
        if f.cause then text = text .. ' (cause: ' .. f.cause .. ')' end
        text = withPlace(text, f.place) .. '.'
    elseif f.kind == 'group_gone' then
        text = (f.group and ('The group ' .. f.group) or 'A group of survivors') .. ' is gone'
        if f.reason then text = text .. ' (' .. f.reason .. ')' end
        text = text .. '.'
    elseif f.kind == 'group_new' then
        text = withPlace('A new group of survivors' .. (f.group and (', ' .. f.group .. ',') or '') .. ' was seen',
            f.place) .. '.'
    else
        return nil
    end
    text = string.format('Around %02d:00, ', f.hour or 0) .. text
    if string.len(text) > Facts.BULLETIN_FACT_CHARS then text = string.sub(text, 1, Facts.BULLETIN_FACT_CHARS) end
    return text
end

-- Translations of the mod are read before the mods on an MP server (getText then returns the key): reloaded once,
-- as for the fixed calls of the voices (RadioSurvivor_Server.lua callText). nil when the key is missing.
local translationsReloaded = false
local function tr(key, ...)
    if getTextOrNull(key) == nil and isServer() and not translationsReloaded and Translator and Translator.loadFiles then
        translationsReloaded = true
        Translator.loadFiles()
        log('mod translations reloaded on the server (' .. key .. ' was missing)')
    end
    if getTextOrNull(key) == nil then return nil end
    return getText(key, ...)
end

local function placeLine(place)
    if type(place) == 'table' and place.key and place.key ~= 'TownFar' and place.town then
        return tr('IGUI_RS_Bulletin_Place_' .. place.key, place.town)
    end
    if type(place) == 'table' and place.key == 'TownFar' then return tr('IGUI_RS_Bulletin_Place_TownFar') end
    return tr('IGUI_RS_Bulletin_Place_None')
end

-- Translated sentence of a fact for the fallback bulletin (language of the authority), or nil (deaths: memorial).
local function fallbackFact(f)
    local place = placeLine(f.place) or ''
    if f.kind == 'mission' and Facts.MISSION_RESULTS[f.result] then
        return tr('IGUI_RS_Bulletin_Mission_' .. f.result, f.requester or tr('IGUI_RS_Bulletin_Someone') or '', place)
    end
    if f.kind == 'rescue' then return tr('IGUI_RS_Bulletin_Rescue', place) end
    if f.kind == 'passage' then return tr('IGUI_RS_Bulletin_Passage', place) end
    if f.kind == 'power_cut' then return tr('IGUI_RS_Bulletin_PowerCut') end
    if f.kind == 'water_cut' then return tr('IGUI_RS_Bulletin_WaterCut') end
    if f.kind == 'weather' and WEATHER_TEXT[f.weather] then return tr('IGUI_RS_Bulletin_Weather_' .. f.weather) end
    if f.kind == 'group_death' then
        return tr('IGUI_RS_Bulletin_GroupDeath', f.group or tr('IGUI_RS_Bulletin_AGroup') or '', place)
    end
    if f.kind == 'group_gone' and f.group then return tr('IGUI_RS_Bulletin_GroupGone', f.group) end
    if f.kind == 'group_new' and f.group then return tr('IGUI_RS_Bulletin_GroupNew', f.group, place) end
    return nil
end

-- Fixed bulletin built from the facts (no bridge): opening, at most FALLBACK_MAX_FACTS facts other than the deaths
-- (read by the memorial), the number of the others, closing. {} when the translations are missing. Nothing
-- confirmed only when there is no fact at all (deaths included).
function Facts.fallbackLines(facts)
    local open, close = tr('IGUI_RS_Bulletin_Open'), tr('IGUI_RS_Bulletin_Close')
    if not open or not close then return {} end
    local others, deaths = Facts.split(facts)
    local lines = {open}
    local told = 0
    for _, f in ipairs(Facts.select(others, Facts.FALLBACK_MAX_FACTS)) do
        local line = fallbackFact(f)
        if line then lines[#lines + 1] = line; told = told + 1 end
    end
    if told == 0 and #deaths == 0 then
        lines[#lines + 1] = tr('IGUI_RS_Bulletin_None')
    elseif #others > told then
        lines[#lines + 1] = tr('IGUI_RS_Bulletin_More', #others - told)
    end
    lines[#lines + 1] = close
    return lines
end

-- Lines of the memorial (E14-T03): a translated opening line (when the translation exists), then the names of the
-- dead in the order of their deaths, one per death fact, joined on lines of at most Const.MAX_LINE_CHARS characters.
-- {} without death. No text of the LLM.
function Facts.memorialLines(facts)
    local _, deaths = Facts.split(facts)
    if #deaths == 0 then return {} end
    local lines = {}
    local open = tr('IGUI_RS_Bulletin_Memorial')
    if open then lines[1] = open end
    local current = nil
    for _, f in ipairs(deaths) do
        local name = type(f.name) == 'string' and f.name ~= '' and f.name or '?'
        if current and string.len(current) + 2 + string.len(name) + 1 <= Const.MAX_LINE_CHARS then
            current = current .. ', ' .. name
        else
            if current then lines[#lines + 1] = current .. '.' end
            current = name
        end
    end
    lines[#lines + 1] = current .. '.'
    return lines
end

local function radioServer()
    return type(RS_RadioServer) == 'table' and RS_RadioServer or nil
end

local silentDay
-- Starts the bulletin of the day if it is due (force: now, for the in-game suite). Returns true when it was sent
-- to the bridge or aired, or false and the reason.
function Facts.bulletin(force)
    if Facts.flight then return false, 'in flight' end
    local radio = radioServer()
    if not radio or not Const.isEnabled() then return false, 'radio' end
    local book = Facts.book()
    local day, hour = Facts.now()
    if not book or not day then return false, 'state' end
    if not force and not Facts.bulletinDue(book, day, hour, Facts.chronicleHour()) then return false, 'not due' end
    local khz = radio.frequency(Facts.CHRONICLER)
    if not khz then
        if silentDay ~= day then
            silentDay = day
            log('no evening bulletin: the chronicler (' .. Facts.CHRONICLER .. ') is not on the air')
        end
        return false, 'chronicler'
    end
    local read = Facts.list()
    local others, deaths = Facts.split(read.facts)
    local texts = {Facts.deathsText(#deaths)}
    for _, f in ipairs(Facts.select(others, Facts.BULLETIN_MAX_FACTS - #texts)) do
        local text = Facts.factText(f)
        if text then texts[#texts + 1] = text end
    end
    Facts.flight = {day = day, through = read.next - 1, khz = khz, facts = read.facts}
    local req = {kind = 'bulletin', voice = Facts.CHRONICLER, khz = khz, date = radio.date(),
        language = radio.language(), timeoutMs = Const.waitMs(Facts.BULLETIN_TIMEOUT_MS),
        facts = #texts > 0 and Codec.hexBytes(Codec.encodeBytes(texts)) or nil,
        handler = function(r, lines) RS_Facts.airBulletin(r, lines) end}
    log('evening bulletin of day ' .. day .. ': ' .. #texts .. ' fact(s) sent to the bridge')
    if not radio.submit(req) then Facts.airBulletin(req, nil) end
    return true
end

-- Airs the bulletin: the bridge lines (parasites removed, at most BULLETIN_MAX_LINES), or the fallback when the
-- bridge gave none; then marks the day as aired and purges the facts read. Dropped (asked again at the next poll)
-- when the chronicler no longer holds the frequency.
function Facts.airBulletin(req, lines)
    local flight = Facts.flight
    Facts.flight = nil
    if not flight then return end
    local radio = radioServer()
    if not radio or radio.frequency(Facts.CHRONICLER) ~= flight.khz then
        log('evening bulletin dropped: the chronicler left its frequency')
        return
    end
    local words = {}
    for _, line in ipairs(type(lines) == 'table' and lines or {}) do
        if type(line) == 'string' and not string.match(line, '^<%a%a%a%a>$') and #words < Facts.BULLETIN_MAX_LINES then
            words[#words + 1] = line
        end
    end
    local source = 'bridge'
    local memorial = Facts.memorialLines(flight.facts)
    if #words == 0 then
        words, source = Facts.fallbackLines(flight.facts), 'fallback'
        if #words == 0 then
            log('evening bulletin dropped: no translation for the fallback text')
            return
        end
        -- Fallback: the memorial before its closing line.
        local close = table.remove(words)
        for _, line in ipairs(memorial) do words[#words + 1] = line end
        words[#words + 1] = close
    else
        -- Bridge: the memorial after its text (the names are never given to the bridge).
        for _, line in ipairs(memorial) do words[#words + 1] = line end
    end
    table.insert(words, 1, '<fzzt>')
    words[#words + 1] = '<szzt>'
    radio.air(flight.khz, words)
    local book = Facts.book()
    if book then
        book.aired = flight.day
        S.dirty = true
    end
    local removed = Facts.purge(flight.through)
    if removed == 0 and book then S.save() end
    local _, deaths = Facts.split(flight.facts)
    log('evening bulletin of day ' .. flight.day .. ' aired (' .. source .. '), ' .. removed .. ' fact(s) purged, '
        .. #deaths .. ' name(s) in the memorial')
end

-- ------------------------------------------------------------------------------------------------ events

-- Event name -> handler name. Handlers are looked up in the global RS_Facts at each call: a Lua reload replaces the
-- module without adding a second subscription (Events.X.Add does not deduplicate).
local LK_EVENTS = {
    OnLivingKnoxMemberDied = 'lkMemberDied',
    OnLivingKnoxGroupGone = 'lkGroupGone',
    OnLivingKnoxGroupCreated = 'lkGroupCreated',
}

RS_Facts = Facts
if not RS_FactsHooked then
    RS_FactsHooked = true
    Events.OnCharacterDeath.Add(function(c) RS_Facts.characterDeath(c) end)
    Events.EveryHours.Add(function() RS_Facts.hourly() end)
    Events.OnServerStarted.Add(function() RS_Facts.chain() end)
    Events.OnGameStart.Add(function() RS_Facts.chain() end)
    for name, handler in pairs(LK_EVENTS) do
        -- AddEvent is idempotent (declares the name when Living Knox is not loaded yet or at all).
        if LuaEventManager and LuaEventManager.AddEvent then LuaEventManager.AddEvent(name) end
        if Events[name] then Events[name].Add(function(e) RS_Facts[handler](e) end) end
    end
end
Facts.chain()

return Facts
