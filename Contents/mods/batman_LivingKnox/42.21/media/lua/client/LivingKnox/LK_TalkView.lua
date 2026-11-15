-- Living Knox: world menu "Talk" on one of its NPCs (E18-T18, E21-T05), client side (MP client, solo).
--
-- A text box; the sentence goes to that NPC through the notebook of the core mod (CoreAI.notebookClient.talkTo: the
-- notebook server selects the NPC, then the sentence takes the one speech path of the NPCs, said aloud once admitted).
-- Solo has no chat: this menu is its way to talk to an NPC. A sentence said in the say chat is the notebook client's.
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_RelationsView"
local Client = require "CoreAI/CA_NotebookClient"

local View = LivingKnox.TalkView or {}
LivingKnox.TalkView = View

View.BOX_W, View.BOX_H = 420, 120

-- Sentence of the menu to the NPC npc (Living Knox id). False when nothing was sent.
function View.sayTo(_, npc, text)
    if type(npc) ~= "string" then return false end
    return Client.talkTo(npc, text)
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
    if not LivingKnox.Config.isEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then return end
    local R = LivingKnox.RelationsView
    local npc = R ~= nil and R.bodyNear ~= nil and R.bodyNear(player, worldObjects) or nil
    if npc == nil then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    context:addOption(getText("IGUI_LK_Talk_Menu"), player, View.open, npc)
end

if Events ~= nil then
    LivingKnox.subscribe("OnFillWorldObjectContextMenu", "TalkView.fill", function(playerNum, context, worldObjects, test)
        return View.fill(playerNum, context, worldObjects, test)
    end)
end

return View
