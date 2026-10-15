--[[ NPC provider interface of the notebook (E17-T02).

The notebook never talks to an NPC engine directly: it only calls Provider.xxx below. An engine plugs
itself in with Provider.register(impl). One provider at a time; until one registers, the default
provider is empty (no NPC, no body, available() false) and the notebook simply has no interlocutor.

Registration
  Provider.register(impl) -> boolean   any side. impl is a table of plain functions (no self).
      A second registration is refused with a console message; the first one stays active. The same provider
      (same name) registered again, after a Lua reload of its file, replaces the previous table.
  Provider.active() -> impl            the registered implementation, or the empty default one.

Operations delegated to the active provider (impl.<name>; a missing function behaves as empty)
  Provider.available() -> boolean      any side. False: the notebook shows "no NPC engine".
  Provider.objects() -> {[id] = obj}   any side. Bodies of the provider NPCs loaded on this machine
      (IsoGameCharacter-like objects: getX/getY/getZ, getSquare, isDead, CanSee). Never nil.
  Provider.id(object) -> id or nil     any side. Provider id of a body (number or string), nil if the
      object is not one of its NPCs. Ids name the current incarnation only; they may change.
  Provider.npc(id) -> record or nil    authority (server or solo). Data of the NPC with this id:
      signature  string, stable identity of the incarnation (bindings of the notebook fiches)
      name       string, display name ('Survivor' when absent)
      group      string, group identifier ('' when none)
      groupName  optional string, readable group name shown in the notebook (E17-T06); nil or '' when none or
                 unknown: the notebook then shows no group (never the identifier)
      hostile    true, false or nil (unknown) toward players
      traits     optional table of booleans (smoker, alcoholic, compulsiveCleaner, comicsCollector,
                 fromPoland); other keys are ignored by the notebook
  Provider.bubble(object, text, range) client. Speech bubble over a body: impl.bubble when defined,
      otherwise the vanilla addLineChatElement.

Optional operations (E17-T03), authority only; a provider without them keeps the notebook behaviour unchanged
  Provider.context(id, character, language) -> table or nil   public context of the NPC for the LLM (group,
      summary, leader, needs, attitude toward this character...): plain values only, never a secret, a home or
      exact coordinates. nil when the provider has none.
  Provider.hasSupplies() -> boolean    the provider defines supplies: the `deliver` missions (M01) of its NPCs come
      ONLY from Provider.supplies (the static catalogue RS_Config.Missions.deliver is not offered for them).
  Provider.supplies(id, character) -> { offer, ... }   open supply offers of this NPC for this notebook character
      (never nil): { ref = supplier reference (string, opaque to the notebook), offer = offer id (string),
      need = 'food' | 'medical' | 'ammo' | ..., level = reserve 0..100, value = requested value V, remaining = V
      still requested, items = { { type = 'Module.Item', value = V of one item }, ... }, hours = game hours left,
      reward = { type, count } or nil }.
  Provider.supplyOpen(ref, offer) -> true | false | nil   offer still open / closed (expired, filled, supplier
      gone) / unknown (engine not ready: nothing is decided).
  Provider.supplyDeliver(ref, offer, delivered, receipt, character) -> result | nil, reason   validated delivery
      { ['Module.Item'] = count }; idempotent by receipt (a replayed receipt returns duplicate = true and changes
      nothing). result = { applied, duplicate, value = V counted, completed, reward = { type, count } or nil
      (completion only) }. The caller removes the items only after a result.
  Provider.presence(id) -> table or nil   (E08-T08) where the NPC is, for the world observations of the notebook:
      { away = true when the NPC is away from its home (expedition in progress), x, y = home position or nil }.
      Server memory only: never sent to a client nor put in a request. nil when the provider cannot tell.
  Provider.composition(id) -> table or nil   (E10-T02) group of the NPC for its collective decisions:
      { ref = group reference (string), key = fingerprint of the living members and the leader (string, computed,
      changes on a death, a departure, an arrival or a succession), leader = true when this NPC is the leader,
      leaderName = display name of the leader or nil }. nil: no group, or the provider has no group leader.
      Server memory only (key never put in a request).
  Provider.decide(id, decision) -> true | nil, reason   (E10-T02) records a collective decision of the NPC group in
      its group journal: decision = { kind = 'offer' | 'accept', need = 'food' | 'medical' | 'ammo' | ..., with =
      character name }. Facts only, composed by the provider: never the model's speech nor the leader's reasons.
  Provider.loyalty(id) -> 'loyal' | 'steady' | 'wavering' | nil   (E10-T03) loyalty of the NPC to its group, derived
      by the provider (Living Knox: group morale and seniority of the member, nothing stored). nil: no group or unknown;
      the notebook then keeps the base personality value.
  Provider.dissent(id, d) -> { logged = boolean, heard = number } | nil, reason   (E10-T03) a member contests or refuses
      a collective decision of its group: d = { choice = 'contest' | 'refuse', about = decision fact (English, plain
      text), name = display name, text = the line the member says aloud (one line, 200 bytes at most) }. The provider
      writes the fact in the group journal (never d.text) and lets the nearby players hear d.text.
  Provider.leave(id, expect) -> { ref, from, groupName, walk } | nil, reason   (E10-T04) individual departure of the
      NPC from its group: expect = { ref, key } of Provider.composition when the request was built (composition also
      gives canLeave = true when the NPC may leave now). The provider checks them again and applies ONE transition (the
      NPC leaves; succession if it led; it forms a group of its own, ref = new group reference); walk = its physical
      departure (directive number) or nil (it may fail without undoing the departure).
  Provider.relation(id, character) -> table or nil   (E09-T04) group basis of the personal relation of the NPC toward a
      notebook character: { ref = group reference, attitude = { level, trend } (5 levels hostile, wary, cautious,
      favorable, trusting; trend up, down, stable; never a number), facts = { { key = stable fact key (string), fact =
      fact name, sign = -1 | 0 | 1, day = game day }, ... } (oldest first: facts of the group toward this character,
      seen by a member or attributable) }. nil: no group or unknown; the notebook then starts from the provider's
      hostile flag. Server memory only (keys never put in a request).
  Provider.engaged(id) -> boolean, reason   (E08-T03) the NPC is busy now (fight, hit, warning, alert): it takes no
      initiative. false when the provider cannot tell.
  Provider.say(id, text, opts) -> { id, heard = { player, ... } } | nil, reason   (E08-T03) proximity speech of the
      engine: text spoken by the body of the NPC to the players who hear it now (opts: id of the line, range, name,
      chat). nil, reason when nobody hears or the engine has no speech channel.
  Provider.bark(id, situation, opts) -> same | nil, reason   (E08-T03) short template line of the engine for a
      situation ('greet'...), opts.player = player addressed; the fallback of an initiative without bridge.

Events, emitted by the provider on the authority, listened to by the notebook
  Provider.on(event, fn)               subscribe; the same function is added once.
  Provider.emit(event, ...)            call the listeners in subscription order.
      'death'        (id, object, cause)   the NPC body with this id died (alive -> dead). The notebook
                                    ignores an id that is no longer its current incarnation. cause is
                                    optional (nil when the engine cannot tell): { cause = 'melee' |
                                    'firearm' | 'fire' | 'vehicle' | 'other' | 'unknown', killer = account
                                    name of the attributed player or nil, weapon = item type or nil,
                                    burning = true or nil }, established on the authority only (E04-T06).
      'reincarnated' (oldSignature, newId, newSignature)   the engine recreated an NPC under a new
                                    id: the notebook moves its fiche (memories, agreements, missions)
                                    to the new incarnation. Without this event nothing is migrated.

Shared rules, engine-independent (vanilla behaviour only), usable by every provider
  Provider.near(a, b, range) -> boolean        same floor, within range, IsoGameCharacter.CanSee.
  Provider.hears(source, listener, range) -> boolean  intelligible speech (ChatUtility.getScrambleValue).
  Provider.personality(signature) -> table     base personality derived from the signature only.
]]
local Provider = {}

local EMPTY = {
    name = 'none',
    available = function() return false end,
    objects = function() return {} end,
    id = function() return nil end,
    npc = function() return nil end,
}
local registered
local listeners = {}

function Provider.register(impl)
    local name = type(impl) == 'table' and tostring(impl.name or 'unnamed') or tostring(impl)
    if type(impl) ~= 'table' then
        print('[RS_NPCProvider] refused provider ' .. name .. ': not a table')
        return false
    end
    if registered and registered.name ~= nil and registered.name == impl.name then
        registered = impl
        print('[RS_NPCProvider] provider ' .. name .. ' registered again (reload)')
        return true
    end
    if registered then
        print('[RS_NPCProvider] refused provider ' .. name .. ': provider '
            .. tostring(registered.name or 'unnamed') .. ' is already active')
        return false
    end
    registered = impl
    print('[RS_NPCProvider] provider ' .. name .. ' registered')
    return true
end

function Provider.active()
    return registered or EMPTY
end

function Provider.available()
    local impl = Provider.active()
    return type(impl.available) == 'function' and impl.available() == true
end

function Provider.objects()
    local impl = Provider.active()
    if not Provider.available() or type(impl.objects) ~= 'function' then return {} end
    return impl.objects() or {}
end

function Provider.id(object)
    local impl = Provider.active()
    if object == nil or not Provider.available() or type(impl.id) ~= 'function' then return nil end
    return impl.id(object)
end

function Provider.npc(id)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.npc) ~= 'function' then return nil end
    local record = impl.npc(id)
    if type(record) ~= 'table' or type(record.signature) ~= 'string' then return nil end
    return record
end

function Provider.context(id, character, language)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.context) ~= 'function' then return nil end
    local context = impl.context(id, character, language)
    return type(context) == 'table' and context or nil
end

function Provider.presence(id)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.presence) ~= 'function' then return nil end
    local presence = impl.presence(id)
    return type(presence) == 'table' and presence or nil
end

function Provider.composition(id)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.composition) ~= 'function' then return nil end
    local c = impl.composition(id)
    if type(c) ~= 'table' or type(c.ref) ~= 'string' or type(c.key) ~= 'string' then return nil end
    return c
end

-- E09-T04: optional group basis of a personal relation.
function Provider.relation(id, character)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.relation) ~= 'function' then return nil end
    local r = impl.relation(id, character)
    if type(r) ~= 'table' or type(r.attitude) ~= 'table' or type(r.attitude.level) ~= 'string' then return nil end
    if type(r.facts) ~= 'table' then r.facts = {} end
    return r
end

function Provider.decide(id, decision)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.decide) ~= 'function' then return nil, 'unsupported' end
    return impl.decide(id, decision)
end

function Provider.engaged(id)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.engaged) ~= 'function' then return false end
    local busy, reason = impl.engaged(id)
    return busy == true, reason
end

function Provider.say(id, text, opts)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.say) ~= 'function' then return nil, 'unsupported' end
    return impl.say(id, text, opts)
end

function Provider.bark(id, situation, opts)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.bark) ~= 'function' then return nil, 'unsupported' end
    return impl.bark(id, situation, opts)
end

-- E10-T03: optional loyalty and dissent of a group member.
function Provider.loyalty(id)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.loyalty) ~= 'function' then return nil end
    local v = impl.loyalty(id)
    if v ~= 'loyal' and v ~= 'steady' and v ~= 'wavering' then return nil end
    return v
end

function Provider.dissent(id, d)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.dissent) ~= 'function' then return nil, 'unsupported' end
    return impl.dissent(id, d)
end

-- E10-T04: optional individual departure of a group member.
function Provider.leave(id, expect)
    local impl = Provider.active()
    if id == nil or not Provider.available() or type(impl.leave) ~= 'function' then return nil, 'unsupported' end
    return impl.leave(id, expect)
end

function Provider.hasSupplies()
    return Provider.available() and type(Provider.active().supplies) == 'function'
end

function Provider.supplies(id, character)
    local impl = Provider.active()
    if id == nil or not Provider.hasSupplies() then return {} end
    local list = impl.supplies(id, character)
    return type(list) == 'table' and list or {}
end

function Provider.supplyOpen(ref, offer)
    local impl = Provider.active()
    if not Provider.available() or type(impl.supplyOpen) ~= 'function' then return nil end
    return impl.supplyOpen(ref, offer)
end

function Provider.supplyDeliver(ref, offer, delivered, receipt, character)
    local impl = Provider.active()
    if not Provider.available() or type(impl.supplyDeliver) ~= 'function' then return nil, 'unsupported' end
    return impl.supplyDeliver(ref, offer, delivered, receipt, character)
end

function Provider.bubble(object, text, range)
    local impl = Provider.active()
    if not object or object:isDead() then return end
    if type(impl.bubble) == 'function' then return impl.bubble(object, text, range) end
    object:addLineChatElement(text, 0.95, 0.9, 0.7, UIFont.Medium, range, 'RS_Speech',
        false, false, false, false, false, true)
end

function Provider.on(event, fn)
    local list = listeners[event]
    if not list then list = {}; listeners[event] = list end
    for _, known in ipairs(list) do if known == fn then return end end
    list[#list + 1] = fn
end

function Provider.emit(event, ...)
    for _, fn in ipairs(listeners[event] or {}) do fn(...) end
end

function Provider.near(a, b, range)
    if not a or not b or a:isDead() or b:isDead() or not a:getSquare() or not b:getSquare() then return false end
    if math.floor(a:getZ()) ~= math.floor(b:getZ()) then return false end
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    if dx * dx + dy * dy > range * range then return false end
    -- Prevent an exchange through an opaque wall; verified IsoGameCharacter.CanSee.
    return a:CanSee(b)
end

-- Conservative intelligible-speech policy based on ChatUtility.getScrambleValue.
-- No scrambled text is disclosed to a listener. Deaf/asleep/dead listeners get nothing.
function Provider.hears(source, listener, baseRange)
    if not source or not listener or listener:isDead() or listener:isAsleep()
        or listener:hasTrait(CharacterTrait.DEAF) then return false end
    local sq, dest = source:getSquare(), listener:getSquare()
    if not sq or not dest then return false end
    local mod, force, display = 1, false, false
    local sb, db = sq:getBuilding(), dest:getBuilding()
    if db and sb and db == sb then
        if sq:getRoom() == dest:getRoom() then mod, display = 2, true
        elseif math.abs(listener:getZ() - source:getZ()) < 1 then mod = 2 end
    elseif db or sb then mod, force = 0.5, true end
    local dz = math.abs(listener:getZ() - source:getZ())
    if dz >= 1 then mod, force = mod - mod * dz * 0.25, true end
    local dx, dy = listener:getX() - source:getX(), listener:getY() - source:getY()
    local distance, range = math.sqrt(dx * dx + dy * dy), baseRange * mod
    return mod > 0 and distance < range and (display or (not force and distance < range * 0.6))
end

-- Personality fixed by the NPC identity, without storing anything: the same values are derived
-- whenever the NPC is first met. Park-Miller over a hash of the signature; Kahlua has no bitwise
-- operators.
local STYLES = {'Prudent', 'Direct', 'Reserved', 'Helpful'}
function Provider.personality(signature)
    local m = 2147483647
    local x = 1
    for i = 1, #signature do x = (x * 31 + string.byte(signature, i)) % m end
    if x == 0 then x = 1 end
    local function draw(n)
        x = (x * 48271) % m
        return 1 + math.floor(x / m * n)
    end
    return {style = STYLES[draw(#STYLES)], courage = draw(5), sociability = draw(5), generosity = draw(5),
        values = 'survival', motivation = 'safety', fear = 'isolation', loyalty = 'current_group', schema = 1}
end

-- Optional operation (E08-T06), authority only (kept at the end of the file: line references of rs.env).
-- Provider.radios() -> { { ref, name, speaker }, ... }: groups that hold a transmitter a living member can use now
-- (their radio voice): ref = group reference, name = group name, speaker = id of the NPC who answers. Never a home nor
-- a position. Empty when the provider has no group radios.
function Provider.radios()
    local impl = Provider.active()
    if not Provider.available() or type(impl.radios) ~= 'function' then return {} end
    local list = impl.radios()
    return type(list) == 'table' and list or {}
end

return Provider
