-- Radio Survivor: "Voice workshop: record this place" in the world context menu (E22-T08, ADR atelier-voix D08).
-- Doc: docs/specifications-techniques/persona-format.md, section "Releve de lieux en jeu (E22-T08)".
--
-- Shown only in solo, or on an MP client whose role holds the capability of the admin tools (CA_AdminAccess.canUse,
-- display only): the authority checks the rights again on every request (server/RadioSurvivor/RS_PlaceSurvey.lua).
-- The option sends the clicked square (x, y, z) only: the authority reads the containers, the room and the building
-- itself. Feedback: a halo text over the player (recorded, or not recorded).
-- Transport: MP, "surveyPlace" -> "surveyReply" (module "RadioSurvivorSurvey"); solo, RS_PlaceSurvey.request called
-- directly, its reply handled during the call.
-- ASCII only in the code (Kahlua); player text through translations (IGUI_RS_Survey_*).
if isServer() then return end

local Access = require "CoreAI/CA_AdminAccess"

local Menu = RS_PlaceSurveyMenu or {}
RS_PlaceSurveyMenu = Menu

-- Copies of the constants of RS_PlaceSurvey.lua (compared by tests/test_rs_place_survey.py).
Menu.MODULE = "RadioSurvivorSurvey"
Menu.CMD_REQUEST = "surveyPlace"
Menu.CMD_REPLY = "surveyReply"
Menu.OP = "place"

Menu.state = Menu.state or { n = 0 }

-- True when the option is shown to this player (display only: the authority decides).
function Menu.canUse(player)
    return Access.canUse(player, true)
end

-- Square of the right click: the square of the first world object picked (as vanilla corpseStorageCheck.lua).
function Menu.squareOf(worldobjects)
    for _, object in ipairs(worldobjects or {}) do
        local sq = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        if sq ~= nil then return sq end
    end
    return nil
end

-- Reply of the authority { n, op, ok, err }: halo text over the local player.
function Menu.receive(reply)
    local player = getSpecificPlayer and getSpecificPlayer(0) or nil
    if player == nil or type(reply) ~= "table" then return false end
    if reply.ok == true then
        HaloTextHelper.addGoodText(player, getText("IGUI_RS_Survey_Done"))
    else
        HaloTextHelper.addBadText(player, getText("IGUI_RS_Survey_Refused"))
    end
    return true
end

-- Option chosen: the request for square x, y, z. Returns its number.
function Menu.record(player, x, y, z)
    if player == nil then return nil end
    Menu.state.n = Menu.state.n + 1
    local args = { op = Menu.OP, n = Menu.state.n, x = x, y = y, z = z }
    if isClient() then
        sendClientCommand(player, Menu.MODULE, Menu.CMD_REQUEST, args)
    else
        local Survey = RS_PlaceSurvey
        if Survey == nil or Survey.request == nil then
            Menu.receive({ n = args.n, op = Menu.OP, ok = false, err = "not_loaded" })
        else
            Menu.receive(Survey.request(player, args))
        end
    end
    return args.n
end

function Menu.onFill(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    if player == nil or not Menu.canUse(player) then return end
    local sq = Menu.squareOf(worldobjects)
    if sq == nil then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    context:addOption(getText("IGUI_RS_Survey_Menu"), player, Menu.record, sq:getX(), sq:getY(), sq:getZ())
end

function Menu.onServerCommand(module, command, args)
    if module ~= Menu.MODULE or command ~= Menu.CMD_REPLY then return end
    Menu.receive(args)
end

-- One subscription each, even when the file is read again (the functions called are always the latest version).
if Events ~= nil and not Menu.subscribed then
    Menu.subscribed = true
    if Events.OnFillWorldObjectContextMenu ~= nil then
        Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
            return RS_PlaceSurveyMenu.onFill(playerNum, context, worldobjects, test)
        end)
    end
    if isClient() and Events.OnServerCommand ~= nil then
        Events.OnServerCommand.Add(function(module, command, args)
            RS_PlaceSurveyMenu.onServerCommand(module, command, args)
        end)
    end
end

return Menu
