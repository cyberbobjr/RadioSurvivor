-- Radio Survivor : le joueur parle dans sa radio ; le serveur (ou le jeu solo) fait répondre la voix qui tient
-- cette fréquence, s'il y en a une. Même chemin en solo et en multijoueur : sendClientCommand.
-- Le client ne connaît aucune fréquence de voix (E05-T08) : toute phrase dite dans une radio émettrice allumée part
-- au serveur avec la fréquence de la radio ; le serveur trie, et ne répond rien sur une fréquence sans voix.
local Const = require "RadioSurvivor/RadioSurvivor_Const"

-- Chemin d'envoi, attente, écart minimal et réponses : RadioSurvivor/RS_RadioTalk.lua, commun avec le module
-- « Émettre » de la fenêtre radio (RadioSurvivor/RS_RadioModule.lua, E06-T02).
local Talk = require "RadioSurvivor/RS_RadioTalk"

-- Fréquence affichée dans le menu : celle où la radio est réglée (connue du joueur).
local function talkLabel(radio)
    local data = radio:getDeviceData()
    return Const.frequencyLabel(data and data:getChannel())
end

local function onTextEntered(_target, button, player, radio)
    if button.internal ~= "OK" then return end
    Talk.send(player, radio, button.parent.entry:getText())
end

local function openTextBox(player, radio)
    local modal = ISTextBox:new(0, 0, 360, 180, getText("IGUI_RadioSurvivor_Prompt"), "", nil, onTextEntered,
        player:getPlayerNum(), player, radio)
    modal.maxChars = Const.MAX_INPUT_CHARS
    modal:initialise()
    modal:addToUIManager()
end

-- Radio proposée au menu : la radio équipée, ou une radio émettrice portée en main, sur le dos ou accrochée à la
-- ceinture ; option grisée avec le motif si elle ne convient pas (talkie à la ceinture : « prenez le talkie en main »,
-- décision 4 de Belt Walkie-Talkie). Une radio rangée (inventaire, sac) n'est pas proposée.
local function offersTalk(player, item)
    if not item or not instanceof(item, "Radio") then return false end
    if item == player:getEquipedRadio() then return true end
    local data = item:getDeviceData()
    if data == nil or data:getIsTwoWay() ~= true then return false end
    return Const.isCarriedRadio(player, item) or player:isAttachedItem(item)
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    if not Const.isEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then item = entry.items and entry.items[1] end
        if offersTalk(player, item) then
            local label = getText("IGUI_RadioSurvivor_Talk", talkLabel(item))
            local option = context:addOption(label, player, openTextBox, item)
            local problem = Talk.problem(player, item)
            if problem then
                option.notAvailable = true
                local tooltip = ISInventoryPaneContextMenu.addToolTip()
                tooltip.description = problem
                option.toolTip = tooltip
            end
            return
        end
    end
end

local function onServerCommand(module, command, args)
    if module ~= Const.MODULE then return end
    Talk.handle(command, args or {})
end

Const.clientHandler = Talk.handle
Events.OnServerCommand.Add(onServerCommand)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
