-- Living Knox alone: a player talks to an NPC (E18-T18), client side (MP client, solo). With RadioSurvivor the notebook
-- does this and nothing here runs. Server side: server/LivingKnox/LK_TalkAlone.lua.
--
-- Two gestures. A sentence said in the chat near an NPC (OnAddMessage: the player's own message of the say chat) goes to
-- the nearest NPC; nobody near is silent. World menu "Talk" on an NPC (solo has no chat): a text box, the sentence is
-- said aloud and goes to that NPC; refusals are shown above the player either way.
-- ChatType is a Java enum not exposed to Lua, its tostring is its name (same reading as LK_SpeechView).
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_RelationsView"

local View = LivingKnox.TalkView or {}
LivingKnox.TalkView = View

-- Copies of the constants of LK_TalkAlone.lua (compared by tests/test_lk_talk_alone.py).
View.MODULE = "LivingKnox"
View.CMD_SAY = "npcSay"
View.CMD_REFUSED = "talkRefused"
View.CMD_SPEECH = "talkSpeech"
View.CMD_OFFER = "talkOffer"
View.BOX_W, View.BOX_H = 420, 120

View.state = View.state or { skip = nil }

local function language()
    local lang = Translator.getLanguage()
    return lang and lang:name() or "EN"
end

local function send(player, args)
    args.channel, args.language = "say", language()
    if isClient() then
        sendClientCommand(player, View.MODULE, View.CMD_SAY, args)
    elseif LivingKnox.TalkAlone then
        LivingKnox.TalkAlone.say(player, args)
    end
end

-- Answer of the server (MP: OnServerCommand; solo: direct call).
function View.receive(command, args)
    local player = getSpecificPlayer(0)
    if type(args) ~= "table" then return end
    if command == View.CMD_SPEECH then
        local P = LivingKnox.NpcProvider
        local body = P and P.objects()[args.npc]
        if body and type(args.text) == "string" then P.bubble(body, args.text, 30) end
    elseif command == View.CMD_REFUSED and player and type(args.reason) == "string" then
        HaloTextHelper.addBadText(player, getText("IGUI_LK_Talk_" .. args.reason))
    elseif command == View.CMD_OFFER and player then
        HaloTextHelper.addGoodText(player, getText("IGUI_LK_Talk_Offer"))
    end
end

local function onServerCommand(module, command, args)
    if module == View.MODULE and (command == View.CMD_SPEECH or command == View.CMD_REFUSED
            or command == View.CMD_OFFER) then
        View.receive(command, args)
    end
end

-- The player's own line in the say chat. A sentence of the menu is said aloud too: it already left, it is skipped.
function View.onAddMessage(message)
    local chat = message:getChat()
    local player = getSpecificPlayer(0)
    if chat == nil or player == nil or tostring(chat:getType()) ~= "say" then return end
    if message:getAuthor() ~= player:getUsername() then return end
    local text = message:getText()
    if type(text) ~= "string" or text == "" then return end
    if View.state.skip == text then
        View.state.skip = nil
        return
    end
    send(player, { text = text, chat = true })
end

-- Sentence of the menu to this NPC, said aloud (MP: say chat; solo: line over the character).
function View.sayTo(player, npc, text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text == "" then return false end
    send(player, { text = text, npc = npc })
    if isClient() and type(processSayMessage) == "function" then
        View.state.skip = text
        processSayMessage(text)
    else
        player:Say(text)
    end
    return true
end

local function onBox(target, button)
    if button.internal == "OK" then View.sayTo(target.player, target.npc, button.parent.entry:getText()) end
end

function View.open(player, npc)
    local box = ISTextBox:new(0, 0, View.BOX_W, View.BOX_H, getText("IGUI_LK_Talk_Prompt"), "",
        { player = player, npc = npc }, onBox, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
    box.entry:focus()
    return box
end

function View.fill(playerNum, context, worldObjects, test)
    if LivingKnox.radioSurvivorActive() or not LivingKnox.Config.isEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then return end
    local R = LivingKnox.RelationsView
    local npc = R ~= nil and R.bodyNear ~= nil and R.bodyNear(player, worldObjects) or nil
    if npc == nil then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    context:addOption(getText("IGUI_LK_Talk_Menu"), player, View.open, npc)
end

if Events ~= nil and not LivingKnox.radioSurvivorActive() then
    LivingKnox.subscribe("OnFillWorldObjectContextMenu", "TalkView.fill", function(playerNum, context, worldObjects, test)
        return View.fill(playerNum, context, worldObjects, test)
    end)
    LivingKnox.subscribe("OnServerCommand", "TalkView.onServerCommand", onServerCommand)
    LivingKnox.subscribe("OnAddMessage", "TalkView.onAddMessage", function(message) View.onAddMessage(message) end)
end

return View
