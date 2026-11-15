--[[
CoreAI: the one access rule of the administration and debug tools of the mods (E21-T04, design carnet-commun-e21.md:
reputation of every character, NPC debug and administration windows, frequencies of the voices). Shared: the
authority checks it at EVERY request, a client only greys or hides its button with it.

    Access.CAPABILITY                       'PopmanManage' (roles moderator and admin, J/characters/Roles.java)
    Access.allowed(player, debugInSolo)     authority: true, or false and the reason (English, logs only)
        MP server: checkPermissions(player, Capability.PopmanManage) (role of the connection,
                   LuaManager.java:2913-2919 -> AntiCheatCapability.validate) AND the role of the player holds the
                   capability (checkPermissions is true when no connection is found);
        solo:      the local player administers its game; debugInSolo: debug mode required (isDebugEnabled);
        MP client: never (the server decides).
    Access.canUse(player, soloAlways)       display only: MP client = role of the player (default: the local player)
                                            holds the capability; solo or host = debug mode, or always with soloAlways.
]]
local Access = {}
Access.CAPABILITY = 'PopmanManage'

local function debugOn()
    return isDebugEnabled ~= nil and isDebugEnabled() == true
end

local function capability()
    return Capability ~= nil and Capability[Access.CAPABILITY] or nil
end

function Access.allowed(player, debugInSolo)
    if player == nil then return false, 'no player' end
    if isClient() then return false, 'MP client' end
    if isServer() then
        local cap = capability()
        if cap == nil then return false, 'capability ' .. Access.CAPABILITY .. ' unknown' end
        if checkPermissions(player, cap) ~= true then return false, 'missing capability ' .. Access.CAPABILITY end
        local role = player.getRole ~= nil and player:getRole() or nil
        if role == nil or role:hasCapability(cap) ~= true then
            return false, 'missing capability ' .. Access.CAPABILITY .. ' (role)'
        end
        return true
    end
    if debugInSolo and not debugOn() then return false, 'debug mode off (solo)' end
    return true
end

function Access.canUse(player, soloAlways)
    if not isClient() then return soloAlways == true or debugOn() end
    player = player or (getSpecificPlayer ~= nil and getSpecificPlayer(0) or nil)
    local cap = capability()
    if player == nil or cap == nil then return false end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(cap) == true
end

return Access
