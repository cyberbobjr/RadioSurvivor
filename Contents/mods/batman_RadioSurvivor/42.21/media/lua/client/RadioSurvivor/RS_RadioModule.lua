-- Radio Survivor : module « Émettre » de la fenêtre radio vanilla (E06-T02). Ajouté à chaque ISRadioWindow par
-- addModule (la fenêtre n'est pas remplacée) : deux dernières lignes reçues sur la fréquence de la radio, ligne de
-- saisie (Entrée émet), bouton « Émettre », bouton qui ouvre le carnet. Même chemin d'envoi que le menu
-- « Parler sur … » (RadioSurvivor/RS_RadioTalk.lua).
-- Visible seulement pour une radio émettrice, allumée, micro ouvert ; l'état est relu à chaque image de la fenêtre
-- (allumage et micro changent pendant qu'elle est ouverte). Saisie grisée pendant l'attente d'une réponse et l'écart
-- entre deux phrases (délai du serveur + marge, Const.clientIntervalMs), avec le motif. La fenêtre s'ouvre aussi pour un
-- talkie à la ceinture (menu « Options de l'appareil » de Belt Walkie-Talkie) : il n'émet pas de là (décision 4),
-- saisie grisée avec le motif « prenez le talkie en main » (Talk.placementProblem).
-- Focus clavier : un ISTextEntryBox garde le focus (touches du jeu bloquées) jusqu'à unfocus() ou au prochain clic
-- gauche, même fenêtre fermée (base ui-windows.md) : rendu après chaque envoi, à Échap, à la fermeture de la fenêtre
-- (ISRadioWindow:close -> clear), quand le module disparaît et après le clavier à l'écran.
-- Manette (module sélectionné par RB) : A ouvre le clavier à l'écran (sa touche Entrée émet), Y émet, X ouvre le
-- carnet ; haut et bas passent aux autres modules.
require "RadioCom/ISRadioWindow"
require "RadioCom/RadioWindowModules/RWMPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Talk = require "RadioSurvivor/RS_RadioTalk"

RS_RadioModule = RWMPanel:derive("RS_RadioModule")
local Module = RS_RadioModule
Module.Talk = Talk

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local BORDER = 10
local GAP = 4
-- Délai avant de rendre le focus après le clavier à l'écran : sa touche Entrée met un appui sur Entrée en file
-- (ISOnScreenKeyboard.lua:425-434), qui doit encore atteindre le champ pour émettre.
local OSK_RELEASE_MS = 300
local KEY_ESCAPE = 1

local function measure(text)
    return getTextManager():MeasureStringX(UIFont.Small, text)
end

-- Texte coupé à la largeur donnée (points de suspension).
local function fit(text, maxWidth)
    if measure(text) <= maxWidth then return text end
    local n = string.len(text)
    while n > 0 and measure(string.sub(text, 1, n) .. "...") > maxWidth do n = n - 1 end
    return string.sub(text, 1, n) .. "..."
end

local function openNotebook()
    local Client = require "RadioSurvivor/RS_Client"
    local Notebook = require "RadioSurvivor/RS_Notebook"
    if Client.window and Client.window:isVisible() then
        Client.window:bringToTop()
    elseif Notebook and Notebook.toggle then
        Notebook.toggle()
    end
end

function Module:new(x, y, width, height)
    local o = RWMPanel.new(self, x, y, width, height)
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end

function Module:createChildren()
    local inner = self.width - BORDER * 2
    local y = BORDER + (FONT_HGT_SMALL + 2) * Talk.LINES_PER_FREQUENCY + GAP
    self.linesTop = BORDER

    self.entry = ISTextEntryBox:new("", BORDER, y, inner, BUTTON_HGT)
    self.entry.font = UIFont.Small
    self.entry:initialise()
    self:addChild(self.entry)
    -- Réglages Java seulement après addChild (base ui-windows.md, ISTextEntryBox).
    self.entry:setMaxTextLength(Const.MAX_INPUT_CHARS)
    local panel = self
    self.entry.onCommandEntered = function() panel:send() end
    self.entry.onOtherKey = function(entry, key)
        if key == KEY_ESCAPE then panel:releaseFocus() end
    end
    y = y + BUTTON_HGT + GAP

    self.statusY = y
    y = y + FONT_HGT_SMALL + GAP

    local half = math.floor((inner - GAP) / 2)
    self.sendButton = ISButton:new(BORDER, y, half, BUTTON_HGT, getText("IGUI_RadioSurvivor_Send"), self, Module.send)
    self.notebookButton = ISButton:new(BORDER + half + GAP, y, inner - half - GAP, BUTTON_HGT,
        getText("IGUI_RS_Notebook"), self, Module.onNotebook)
    for _, b in ipairs({ self.sendButton, self.notebookButton }) do
        b:initialise()
        b.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
        b.backgroundColorMouseOver = { r = 1.0, g = 1.0, b = 1.0, a = 0.1 }
        b.borderColor = { r = 1.0, g = 1.0, b = 1.0, a = 0.3 }
        self:addChild(b)
    end
    self:setHeight(y + BUTTON_HGT + BORDER)
    self.editable = true
end

-- Rend le focus clavier au jeu (touches du personnage), sans effet si le champ ne l'a pas.
function Module:releaseFocus()
    self.oskClosedAt = nil
    if self.entry and self.entry.javaObject and self.entry:isFocused() then
        self.entry:unfocus()
    end
end

function Module:clear()
    self:releaseFocus()
    self.oskOpen = false
    RWMPanel.clear(self)
end

function Module:readFromObject(player, device, deviceData, deviceType)
    RWMPanel.readFromObject(self, player, device, deviceData, deviceType)
    self.placeholderKhz = nil
    return Talk.moduleShown(deviceData)
end

function Module:channel()
    return self.deviceData and self.deviceData:getChannel() or nil
end

function Module:send()
    if not self.player or not self.device then return end
    local text = self.entry:getText()
    if Talk.cleanText(text) ~= "" and Talk.send(self.player, self.device, text) then
        self.entry:setText("")
    end
    self:releaseFocus()
end

function Module:onNotebook()
    self:releaseFocus()
    openNotebook()
end

function Module:setInputEnabled(editable)
    if self.editable == editable then return end
    self.editable = editable
    self.entry:setEditable(editable)
    self.sendButton:setEnable(editable)
    if not editable then self:releaseFocus() end
end

function Module:update()
    RWMPanel.update(self)
    if not self.deviceData then return end
    local khz = self:channel()
    if khz ~= self.placeholderKhz then
        self.placeholderKhz = khz
        self.entry:setPlaceholderText(getText("IGUI_RadioSurvivor_Talk", Const.frequencyLabel(khz)))
    end
    -- Talkie à la ceinture (fenêtre ouverte par « Options de l'appareil » de Belt Walkie-Talkie) : saisie grisée avec
    -- « prenez le talkie en main » (décision 4), puis attente et écart entre deux phrases.
    self.busy = Talk.placementProblem(self.player, self.device) or Talk.busyReason()
    self:setInputEnabled(self.busy == nil)
    -- Clavier à l'écran refermé : il redonne le focus clavier au champ (ISOnScreenKeyboard:hide) ; le rendre.
    if self.oskOpen and not OnScreenKeyboard.IsVisible() then
        self.oskOpen = false
        self.oskClosedAt = getTimestampMs()
    end
    if self.oskClosedAt and getTimestampMs() - self.oskClosedAt >= OSK_RELEASE_MS then
        self:releaseFocus()
    end
end

function Module:render()
    RWMPanel.render(self)
    if not self.deviceData then return end
    local inner = self.width - BORDER * 2
    local lines = Talk.lastLines(self:channel())
    local y = self.linesTop
    if #lines == 0 then
        local text = getText("IGUI_RadioSurvivor_NothingHeard", Const.frequencyLabel(self:channel()))
        self:drawText(fit(text, inner), BORDER, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
    end
    local c = Const.LINE_COLOR
    for _, line in ipairs(lines) do
        self:drawText(fit(line, inner), BORDER, y, c.r, c.g, c.b, 1, UIFont.Small)
        y = y + FONT_HGT_SMALL + 2
    end
    if self.busy then
        self:drawText(fit(self.busy, inner), BORDER, self.statusY, 1, 0.45, 0.35, 1, UIFont.Small)
    end
end

-- Manette -----------------------------------------------------------------------------------------

function Module:joypadData()
    local num = self.playerNum or (self.player and self.player:getPlayerNum())
    return num and JoypadState.players[num + 1] or nil
end

function Module:openKeyboard()
    local joypadData = self:joypadData()
    if not joypadData or not self.editable or OnScreenKeyboard.IsVisible() then return end
    local osk = OnScreenKeyboard.Show(joypadData.player, self.entry, joypadData)
    if osk then
        osk.prevFocus = joypadData.focus
        joypadData.focus = osk
        self.oskOpen = true
    end
end

function Module:onJoypadDown(button)
    if button == Joypad.AButton then
        self:openKeyboard()
    elseif button == Joypad.YButton then
        self:send()
    elseif button == Joypad.XButton then
        self:onNotebook()
    end
end

function Module:getAPrompt() return getText("IGUI_RadioSurvivor_Type") end
function Module:getXPrompt() return getText("IGUI_RS_Notebook") end
function Module:getYPrompt() return getText("IGUI_RadioSurvivor_Send") end

-- Installation dans la fenêtre radio --------------------------------------------------------------

-- Visibilité relue à chaque image : la fenêtre ne relit ses modules qu'à l'ouverture (ISRadioWindow:readFromObject).
function Module.sync(window)
    local record = window.rsTalkRecord
    if not record then return end
    local panel = record.element.subpanel
    local shown = panel.deviceData ~= nil and Talk.moduleShown(panel.deviceData)
    if shown == record.enabled then return end
    record.enabled = shown
    record.element:setVisible(shown)
    if not shown then
        panel:releaseFocus()
        if window.subFocus == record and JoypadState.players[window.playerNum + 1] then window:focusSelf() end
    end
end

-- Ajoute le module à une fenêtre (une fois) ; rend l'enregistrement { enabled, element } de ISRadioWindow:addModule.
function Module.addTo(window)
    if window.rsTalkRecord then return window.rsTalkRecord end
    window:addModule(Module:new(0, 0, window.width, 0), getText("IGUI_RadioSurvivor_Module"), false)
    window.rsTalkRecord = window.modules[#window.modules]
    -- Surcharge de l'instance seulement : la méthode de classe (vanilla ou d'un autre mod) est appelée ensuite.
    window.prerender = function(self)
        Module.sync(self)
        return ISRadioWindow.prerender(self)
    end
    return window.rsTalkRecord
end

local wrappedCreateChildren = nil

-- Enveloppe ISRadioWindow.createChildren une fois ; à refaire si le fichier vanilla est rechargé (nouvelle table).
function Module.install()
    if not ISRadioWindow or ISRadioWindow.createChildren == wrappedCreateChildren then return end
    local previous = ISRadioWindow.createChildren
    wrappedCreateChildren = function(self, ...)
        previous(self, ...)
        Module.addTo(self)
    end
    ISRadioWindow.createChildren = wrappedCreateChildren
end

Module.install()
Events.OnGameStart.Add(Module.install)
Events.OnDeviceText.Add(Talk.onDeviceText)

return Module
