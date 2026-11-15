if isClient() then return end
--[[
CoreAI: public facts of the human groups of an NPC engine (E21-T06), read by the other mods without naming that
engine. Authority only. The engine feeds them (its own adapter calls emit); a reader subscribes with on.

    GroupFacts.on(kind, fn) -> boolean      fn(fact) called at each emit of the kind, in subscription order;
                                            false for an unknown kind or a fn that is not a function
    GroupFacts.emit(kind, fact) -> n        calls every listener of the kind; returns how many (0 for an unknown kind
                                            or a fact that is not a table)

Kinds and fields (plain values only, no exact coordinate; group = readable name of the group, or nil when unknown):
    member_died     { id, member, group, role, cause, byPlayer, offscreen, area = { x, y, size } or nil }
    group_gone      { id, group, reason }
    group_created   { id, group, typeKey, area }
id is the identifier of the group in the engine, member the identifier of the member in its group (keys for the
readers that count a fact once). The same fact table is shared by the listeners of one emit: never modify it.
A reader subscribes once (a Lua reload of the reader must not subscribe again: guard it, or look its handler up by
name at each call). ASCII only (Kahlua lexer).
]]
local GroupFacts = {}

GroupFacts.KINDS = { member_died = true, group_gone = true, group_created = true }

local listeners = {}
for kind in pairs(GroupFacts.KINDS) do listeners[kind] = {} end

function GroupFacts.on(kind, fn)
    local list = listeners[kind]
    if not list or type(fn) ~= 'function' then return false end
    list[#list + 1] = fn
    return true
end

function GroupFacts.emit(kind, fact)
    local list = listeners[kind]
    if not list or type(fact) ~= 'table' then return 0 end
    for i = 1, #list do list[i](fact) end
    return #list
end

return GroupFacts
