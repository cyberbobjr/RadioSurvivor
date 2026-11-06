--[[
Living Knox: name of an NPC as players read it (E18-T26; drawn the same way since E17, formerly inside the notebook
adapter RS_LivingKnox). Read only, any machine that holds the registries (the authority).

    Names.of(id) -> { name, group = group id or '', groupName, female, g, mid } | nil (unknown NPC)

A group leader takes the leader's name of its group story; an NPC of a loner group (E10-T04) the name of that group;
any other NPC a name drawn from the story name lists, seeded by its number (Park-Miller, no bitwise operator), else
"Survivor <n>".
]]
require "LivingKnox/LK_Core"

local Names = LivingKnox.Names or {}
LivingKnox.Names = Names

Names.LONER_TYPE = "loners" -- E10-T04: group type of an NPC who left its group (Data/LK_Type_loners.lua)
local ID_PATTERN = "^lk%-%d+$"

local function registry()
    local S = LivingKnox.Store
    if not S then return nil end
    if not S.isReady() and not S.isBlocked() then S.ensure() end
    return S.data()
end

function Names.groupOf(id)
    local G = LivingKnox.Groups
    if not G or not G.ensure() then return nil end
    local gid, mid = G.findNpc(id)
    if not gid then return nil end
    local g = G.state.data.groups[gid]
    return g, gid, mid
end

-- Composed story of a group (server memory only: it holds the secrets, never sent as is), cached by type and seed.
local stories = {}
function Names.storyOf(g)
    local St = LivingKnox.Stories
    if not St or g.storySeed == nil then return nil end
    local key = tostring(g.type) .. ":" .. tostring(g.storySeed)
    if stories[key] == nil then stories[key] = St.compose(g.type, g.storySeed) or false end
    return stories[key] or nil
end

-- Name drawn from the story name lists, seeded by the NPC number.
function Names.drawn(id, female)
    local D = LivingKnox.StoryData
    local n = tonumber(string.match(id, "%d+")) or 1
    if type(D) ~= "table" or type(D.surnames) ~= "table" then return "Survivor " .. n end
    local firsts = female and D.firstNamesFemale or D.firstNamesMale
    local m = 2147483647
    local x = (n * 7919 + 104729) % m
    local function draw(k)
        x = (x * 48271) % m
        return 1 + math.floor(x / m * k)
    end
    return firsts[draw(#firsts)] .. " " .. D.surnames[draw(#D.surnames)]
end

function Names.of(id)
    if type(id) ~= "string" or string.match(id, ID_PATTERN) == nil then return nil end
    local reg = registry()
    local n = reg and reg.npcs[id]
    if not n then return nil end
    local out = { group = "", female = type(n.profile) == "table" and n.profile.female == true }
    local g, gid, mid = Names.groupOf(id)
    local member = g and g.members[mid]
    if member then
        out.group, out.groupName, out.g, out.mid = gid, g.name, g, mid
        if type(member.female) == "boolean" then out.female = member.female end
        local story = g.leader == mid and Names.storyOf(g)
        if story then out.name = story.leader.name end
        if g.type == Names.LONER_TYPE and type(g.name) == "string" and g.name ~= "" then out.name = g.name end
    end
    out.name = out.name or Names.drawn(id, out.female)
    return out
end

return Names
