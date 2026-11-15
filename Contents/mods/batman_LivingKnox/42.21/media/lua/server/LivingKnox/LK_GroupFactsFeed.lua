if isClient() then return end
--[[
Living Knox feeds the public group facts of the core mod (E21-T06): its public events (LK_API, API.EVENTS
memberDied, groupGone, groupCreated) become CA_GroupFacts member_died, group_gone and group_created, with the
readable name of the group resolved here (API.getGroup), so that a reader never asks Living Knox. Authority only.

    member_died     { id, member, group, role, cause, byPlayer, offscreen, area }
    group_gone      { id, group, reason }                 group nil once the group left the registry (removed)
    group_created   { id, group, typeKey, area }          group = name of the payload, else the registry's

Subscriptions through LivingKnox.subscribe (a Lua reload replaces them, never a second one).
]]
require 'LivingKnox/LK_Core'
local API = require 'LivingKnox/LK_API'
local GroupFacts = require 'CoreAI/CA_GroupFacts'

local Feed = LivingKnox.GroupFactsFeed or {}
LivingKnox.GroupFactsFeed = Feed

local function nameOf(id)
    local view = API.getGroup(id)
    return type(view) == 'table' and type(view.name) == 'string' and view.name or nil
end

function Feed.memberDied(e)
    if type(e) ~= 'table' or type(e.group) ~= 'string' then return end
    GroupFacts.emit('member_died', { id = e.group, member = e.member, group = nameOf(e.group), role = e.role,
        cause = e.cause, byPlayer = e.byPlayer == true, offscreen = e.offscreen == true, area = e.area })
end

function Feed.groupGone(e)
    if type(e) ~= 'table' or type(e.group) ~= 'string' then return end
    GroupFacts.emit('group_gone', { id = e.group, group = nameOf(e.group), reason = e.reason })
end

function Feed.groupCreated(e)
    if type(e) ~= 'table' or type(e.group) ~= 'string' then return end
    GroupFacts.emit('group_created', { id = e.group, group = e.name or nameOf(e.group), typeKey = e.typeNameKey,
        area = e.area })
end

-- Public event of LK_API -> handler of this feed (looked up at each call: a reload keeps one subscription).
for _, kind in ipairs({ 'memberDied', 'groupGone', 'groupCreated' }) do
    LivingKnox.subscribe(API.EVENTS[kind], 'GroupFactsFeed.' .. kind, function(e) LivingKnox.GroupFactsFeed[kind](e) end)
end

return Feed
