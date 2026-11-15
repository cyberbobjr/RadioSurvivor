require 'ISUI/ISTextEntryBox'
--[[
RadioSurvivor's Radio tab of the notebook (E06-T04, E21-T03: what remains of RS_Notebook once the common pages moved to
the core mod: CA_NotebookContacts, CA_NotebookMissions, CA_NotebookReputation). The notebook itself (frame,
bookmarks, sidebar button, registry of tabs) belongs to the core mod (CoreAI/CA_Notebook).
Radio tab: per-frequency history kept by the authority, unread indicator, one-click tuning, "Say:" line into the
radio (same send path, checks and delay as the radio window module).
]]
local Notebook = require 'CoreAI/CA_Notebook'
local Client = require 'CoreAI/CA_NotebookClient'
local Missions = require 'CoreAI/CA_NotebookMissions'
if RS_NotebookRadio then return RS_NotebookRadio end
local UI = Notebook.ui
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
-- Radio tab (E06-T04): per-frequency history kept by the authority, unread indicator, one-click tuning.
local History = require 'RadioSurvivor/RS_RadioHistory'
-- "Say" line of the Radio tab (E06-T06): same send path, checks and delay as the radio window module.
local Talk = require 'RadioSurvivor/RS_RadioTalk'

local RS_MOD = 'batman_RadioSurvivor'
local COLOR, INK_TAG, DOT = UI.COLOR, UI.INK_TAG, UI.DOT
local fontHeight, width, clean = UI.fontHeight, UI.width, UI.clean
local stamp, enable, paperEntry = UI.stamp, UI.enable, UI.paperEntry
-- Rich text colours of the Radio lines by kind (said, answer, heard; map mark, area revealed: brick red).
local RADIO_COLORS = {said = '0.12,0.23,0.37', reply = '0.17,0.16,0.15', heard = '0.40,0.37,0.32', mark = '0.70,0.18,0.08'}
RADIO_COLORS.reveal = RADIO_COLORS.mark
RADIO_COLORS.mission = RADIO_COLORS.mark
RADIO_COLORS.reward = RADIO_COLORS.mark
RADIO_COLORS.note = RADIO_COLORS.mark
local DEVICE_CACHE_MS = 250

local function tr(key, ...) return getText('IGUI_RS_' .. key, ...) end

-- Radio this character talks into from the notebook: an equipped two-way radio (hand, back), else a two-way radio
-- carried in the main inventory (belt), else the equipped one (its problem is shown). Talk.problem judges it.
local function talkDevice(player)
    if not player then return nil end
    local equipped = player:getEquipedRadio()
    local data = equipped and equipped:getDeviceData()
    if data and data:getIsTwoWay() then return equipped end
    local inventory = player:getInventory()
    local items = inventory and inventory:getItems()
    if items then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if instanceof(item, 'Radio') then
                local d = item:getDeviceData()
                if d and d:getIsTwoWay() then return item end
            end
        end
    end
    return equipped
end

RS_NotebookRadio = {}
local Radio = RS_NotebookRadio

-- Second line of a frequency row: E06-T07: the voice of the frequency once known (contact, note read, frequency
-- given), else the last line heard.
function Radio.secondLine(row)
    if row.voice then return History.voiceName(row.voice) end
    return tr('RadioLast', row.when ~= '' and row.when or '-')
end

-- Is the player reading the Radio tab right now (visible, expanded)? With khz: this frequency, selected there.
-- Otherwise a new line lights the indicator (and the dot of its frequency).
function Notebook:viewingRadio(khz)
    if not self:viewing('Radio') then return false end
    return khz == nil or (self.row ~= nil and self.row.khz == khz)
end

local function createRadio(w)
    -- "Tune my radio" under the frequency list, "Say:" line and "Transmit" under the conversation.
    w.tune = w:own(stamp(w, tr('RadioTune'), function(win) if win.row then History.tune(win.row.khz) end end))
    w.say = ISTextEntryBox:new('', 0, 0, 100, fontHeight(UIFont.Medium) + 10)
    w.say.font = UIFont.Medium
    w.say:initialise(); w:addChild(w.say)
    w.say:setMaxTextLength(Const.MAX_INPUT_CHARS)
    paperEntry(w.say, true)
    w.say:setPlaceholderTextRGBA(0.55, 0.51, 0.43, 1)
    w.say.onCommandEntered = function() w:sendSay() end
    w.say.onOtherKey = function(_, key) if key == UI.KEY_ESCAPE then w:releaseFocus() end end
    w:own(w.say); w:addEntry(w.say, 'Radio')
    w.sendRadio = w:own(stamp(w, getText('IGUI_RadioSurvivor_Send'), function(win) win:sendSay() end, true))
    w.sayEditable = true
end

-- Conversation of one frequency, oldest first; scrolled to the newest line when it changes. Reading it puts out the
-- global indicator and the dot of this frequency.
function Notebook:showRadio(row, text)
    local parts = {}
    for _, s in ipairs(text) do parts[#parts + 1] = INK_TAG .. s end
    -- E06-T07: who speaks on this frequency and when they listen, once the character knows the voice.
    if row.voice then
        local hours = History.hoursText(row.voice)
        parts[#parts + 1] = INK_TAG .. clean(tr('RadioVoice', History.voiceName(row.voice),
            hours and tr('RadioHours', hours) or tr('RadioAlways')))
    end
    local lines = History.lines(row.khz)
    for _, l in ipairs(lines) do
        local kind = RADIO_COLORS[l.kind] and l.kind or 'heard'
        -- Mission received (E11-T08): the line holds the kind of place, translated here.
        local said = kind == 'mission' and Missions.placeName(l.text) or l.text
        if kind == 'reward' then said = tr('Reward_' .. l.text) end
        if kind == 'note' then said = History.voiceName(row.voice) or tr('None') end
        parts[#parts + 1] = '<RGB:' .. RADIO_COLORS[kind] .. '> ' .. clean(tr('Radio_' .. kind, l.when, said))
    end
    if #lines == 0 then parts[#parts + 1] = INK_TAG .. clean(tr('Empty_Radio')) end
    self.tune:setVisible(true)
    self.detail:setText(table.concat(parts, ' <LINE> '))
    if self:viewingRadio() then
        History.markRead()
        History.markFrequencyRead(row.khz)
        row.unread = false
    end
    self:layout()
    local last = lines[#lines]
    local shown = tostring(row.khz) .. '#' .. #lines .. '#' .. tostring(last and last.seq)
    if shown ~= self.scrollKey and self.detail.setYScroll then self.detail:setYScroll(-100000) end
    self.scrollKey = shown
end

-- Sends the Say line through the shared path (Talk.send: same checks, waiting and delay as the radio window),
-- then gives the keyboard back to the game.
function Notebook:sendSay()
    local player = getSpecificPlayer(0)
    local text = self.say:getText()
    if Talk.cleanText(text) ~= '' and Talk.send(player, talkDevice(player), text) then self.say:setText('') end
    self:releaseFocus()
end

-- State of the Say line, read each frame on the Radio tab: greyed with the reason while waiting for an answer or
-- during the delay between two sentences; placeholder on the frequency of the radio; reason a sentence would be
-- refused, or a hint when the radio is on another frequency than the selected one.
function Notebook:syncSay()
    local now = getTimestampMs()
    if not self.deviceAt or now - self.deviceAt >= DEVICE_CACHE_MS then
        self.rsPlayer = getSpecificPlayer(0)
        self.rsDevice, self.deviceAt = talkDevice(self.rsPlayer), now
    end
    local busy = Talk.busyReason()
    local editable = busy == nil
    if self.sayEditable ~= editable then
        self.sayEditable = editable
        self.say:setEditable(editable)
        enable(self.sendRadio, editable)
        if not editable then self:releaseFocus(self.say) end
    end
    local data = self.rsDevice and self.rsDevice:getDeviceData()
    local khz = data and data:getChannel() or (self.row and self.row.khz)
    if khz ~= self.sayKhz then
        self.sayKhz = khz
        self.say:setPlaceholderText(khz and getText('IGUI_RadioSurvivor_Talk', Const.frequencyLabel(khz)) or '')
    end
    local status, problem = busy, true
    if not status and self.rsPlayer then status = Talk.problem(self.rsPlayer, self.rsDevice) end
    if not status and data and self.row and khz ~= self.row.khz then
        status, problem = tr('RadioTunedElsewhere', Const.frequencyLabel(khz), Const.frequencyLabel(self.row.khz)), false
    end
    self.sayStatus, self.sayProblem = status, problem
end

Notebook.registerTab({name = 'Radio', mods = {RS_MOD}, order = 10, color = {0.71, 0.325, 0.11},
    label = function() return tr('Radio') end,
    font = UIFont.Medium, titleColor = COLOR.blue, wideRows = true,
    header = function() return tr('RadioHeardList') end,
    rows = function() return History.sorted() end,
    rowLabel = function(row) return tr('RadioFrequency', Const.frequencyLabel(row.khz)) end,
    secondLine = Radio.secondLine,
    create = createRadio,
    detail = function(w, row, _, text)
        w.say:setVisible(true); w.sendRadio:setVisible(true)
        if row then w:showRadio(row, text); return true end
        text[#text + 1] = clean(tr('Empty_Radio'))
        return false
    end,
    listHeight = function(w, listMax, bh, gap)
        local rows = #w.list.items
        return math.max(w.list.itemheight, math.min(rows * w.list.itemheight, listMax - bh - gap))
    end,
    layoutLeft = function(w, geo, listTop, listH)
        if not w.tune:isVisible() then return end
        w.tune:setX(geo.left); w.tune:setY(listTop + listH + geo.gap)
        w.tune:setWidth(math.min(width(w.tune.title) + 24, geo.colW)); w.tune:setHeight(geo.bh)
    end,
    layout = function(w, geo)
        local fh, fhM = fontHeight(), fontHeight(UIFont.Medium)
        local entryH = fhM + 10
        local statusH = fh * 2 + 8
        local inputY = geo.bottom - entryH
        Notebook.placeSayLine({entry = w.say, send = w.sendRadio, label = tr('RadioSay')}, geo, inputY, entryH)
        geo.inputY, geo.entryH, geo.statusY = inputY, entryH, inputY - statusH
        w.detail:setX(geo.rightX); w.detail:setY(geo.detailTop); w.detail:setWidth(geo.rightW)
        w.detail:setHeight(math.max(40, geo.statusY - 4 - geo.detailTop)); w.detail:paginate()
    end,
    status = function(w) return w.sayStatus, w.sayProblem end,
    update = function(w) w:syncSay() end,
    onOpen = function() History.request() end,
    unread = function() return History.unread == true end})

-- Left column wide enough on every tab for the Radio rows and the tune button (E03-T02).
Notebook.columnWidths[#Notebook.columnWidths + 1] = function()
    return math.max(width(tr('RadioFrequency', '999.9'), UIFont.Medium) + DOT + 36,
        width(tr('RadioLast', '00/00 00:00')) + 24, width(tr('RadioHeardList')) + 4, width(tr('RadioTune')) + 24)
end
Notebook.hints[#Notebook.hints + 1] = 'IGUI_RS_SelectHint'

-- Each opening: lines received while the notebook was closed are read again (the whole history of the authority).
Notebook.onToggle[#Notebook.onToggle + 1] = function(w)
    if w:isVisible() then History.request() end
end

History.isViewing = function(khz) return Client.window ~= nil and Client.window:viewingRadio(khz) end
History.onChange = function()
    if Client.window and Client.window:isVisible() and Client.window.tab == 'Radio' then Client.window:refresh() end
end

return Radio
