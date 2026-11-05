require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISRichTextPanel"
require "ISUI/ISEquippedItem"
require "ISUI/ISDPadWheels"
--[[
RadioSurvivorCore: mission journal window (E18-T06, user decision of 2026-11-05). Client only, presentation only: it
shows what the authority sends (RC_MissionJournal: open missions of the player's character, notebook order and
states, RC_MissionList) and decides nothing.

Opened by a button of the vanilla sidebar (after the vanilla buttons) and, with a controller, by a slice of the
D-pad right wheel (ISDPadWheels.onDisplayRight). While it is visible it asks the list again every REFRESH_MS. With a
host (RadioSurvivor's notebook, Journal.setHost), the notebook shows the same list in its Missions tab: the button is
removed, and the wheel slice opens the host instead.
Controller: the window takes the focus when opened from the wheel; up and down move the selection, B closes.
Texts: IGUI_RC_* (Translate/<LANG>/IG_UI.json of the core mod); mission titles are the keys of their catalogue.
]]
RadioSurvivorCore = RadioSurvivorCore or {}

local Journal = {}
Journal.MODULE = "RadioSurvivorCore"
Journal.REFRESH_MS = 3000
Journal.rows = {}
Journal.host = nil
Journal.window = nil
RadioSurvivorCore.missionJournal = Journal

local function tr(key, ...)
    return getText("IGUI_RC_" .. key, ...)
end

-- One line of the list: title, requester, state shown by the notebook.
function Journal.label(row)
    local title = getText(row.titleKey or "IGUI_RC_Mission")
    local key = row.toReport and "toReport" or row.state
    return title .. " - " .. tostring(row.requester or "") .. " (" .. tr("State_" .. tostring(key)) .. ")"
end

-- Detail lines of the selected row.
function Journal.detail(row)
    local lines = {}
    if not row then
        lines[1] = tr("JournalEmpty")
        return lines
    end
    lines[#lines + 1] = getText(row.titleKey or "IGUI_RC_Mission")
    lines[#lines + 1] = tr("Requester", tostring(row.requester or ""))
    lines[#lines + 1] = tr("State_" .. tostring(row.toReport and "toReport" or row.state))
    if type(row.remainingMs) == "number" then lines[#lines + 1] = tr("TimeLeft", math.ceil(row.remainingMs / 60000)) end
    if type(row.rewardCount) == "number" and row.rewardCount > 0 and type(row.rewardType) == "string" then
        local item = getScriptManager and getScriptManager():FindItem(row.rewardType)
        lines[#lines + 1] = tr("Reward", row.rewardCount, item and item:getDisplayName() or row.rewardType)
    end
    if type(row.participants) == "table" and #row.participants > 0 then
        lines[#lines + 1] = tr("Participants", table.concat(row.participants, ", "))
    end
    if row.toReport then lines[#lines + 1] = tr("ReportHint") end
    return lines
end

-- ---------------------------------------------------------------- window

RC_UI_MissionJournal = ISCollapsableWindow:derive("RC_UI_MissionJournal")
local Window = RC_UI_MissionJournal

function Window:new(playerNum)
    local w, h = 460, 380
    local core = getCore()
    local o = ISCollapsableWindow.new(self, (core:getScreenWidth() - w) / 2, (core:getScreenHeight() - h) / 2, w, h)
    o.title = tr("Journal")
    o.playerNum = playerNum or 0
    o.resizable = false
    o.asked = 0
    return o
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + 6
    self.list = ISScrollingListBox:new(8, top, self.width - 16, 170)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 22
    self.list.font = UIFont.Small
    self.list.target = self
    self.list:setOnMouseDownFunction(self, Window.onSelect)
    self:addChild(self.list)
    self.text = ISRichTextPanel:new(8, top + 178, self.width - 16, self.height - top - 186)
    self.text:initialise()
    self.text.autosetheight = false
    self.text.background = false
    self:addChild(self.text)
    self.text:addScrollBars()
end

function Window:onSelect(row)
    self.selectedId = row and row.id or nil
    self:showDetail()
end

function Window:selected()
    for _, item in ipairs(self.list.items) do
        if item.item.id == self.selectedId then return item.item end
    end
    return nil
end

function Window:refresh()
    if not self.list then return end
    self.list:clear()
    for i, row in ipairs(Journal.rows) do
        self.list:addItem(Journal.label(row), row)
        if row.id == self.selectedId then self.list.selected = i end
    end
    if not self:selected() then
        local first = Journal.rows[1]
        self.selectedId = first and first.id or nil
        self.list.selected = first and 1 or 0
    end
    self:showDetail()
end

function Window:showDetail()
    local lines = Journal.detail(self:selected())
    if #Journal.rows == 0 then lines = { tr("JournalEmpty") } end
    self.text:setText(table.concat(lines, " <LINE> "))
    self.text:paginate()
end

function Window:update()
    if ISCollapsableWindow.update then ISCollapsableWindow.update(self) end
    local now = getTimestampMs()
    if self:isVisible() and now - self.asked >= Journal.REFRESH_MS then
        self.asked = now
        Journal.request()
    end
end

function Window:close()
    ISCollapsableWindow.close(self)
    local joypad = JoypadState and JoypadState.players[self.playerNum + 1]
    if joypad and joypad.focus == self then setJoypadFocus(self.playerNum, nil) end
end

-- Controller: up / down move the selection, B closes.
function Window:onJoypadDirUp()
    if self.list.selected > 1 then
        self.list.selected = self.list.selected - 1
        self:onSelect(self.list.items[self.list.selected].item)
    end
end

function Window:onJoypadDirDown()
    if self.list.selected < #self.list.items then
        self.list.selected = self.list.selected + 1
        self:onSelect(self.list.items[self.list.selected].item)
    end
end

function Window:onJoypadDown(button)
    if button == Joypad.BButton then self:close() end
end

-- ---------------------------------------------------------------- network

function Journal.request()
    local p = getSpecificPlayer(0)
    if p ~= nil then sendClientCommand(p, Journal.MODULE, "missions", {}) end
end

function Journal.receive(args)
    if type(args) ~= "table" or type(args.missions) ~= "table" then return end
    local rows = {}
    for _, row in ipairs(args.missions) do
        if type(row) == "table" and type(row.id) == "string" then rows[#rows + 1] = row end
    end
    Journal.rows = rows
    if Journal.window then Journal.window:refresh() end
end

function Journal.onServerCommand(module, command, args)
    if module == Journal.MODULE and command == "missions" then Journal.receive(args) end
end

-- ---------------------------------------------------------------- opening

function Journal.toggle(playerNum, joypad)
    if Journal.host then return Journal.host(playerNum) end
    local w = Journal.window
    if not w then
        w = Window:new(playerNum)
        w:initialise()
        w:addToUIManager()
        Journal.window = w
    elseif w:isVisible() then
        w:close()
        return
    else
        w:setVisible(true)
        w:bringToTop()
    end
    w.asked = getTimestampMs()
    w:refresh()
    Journal.request()
    if joypad then setJoypadFocus(w.playerNum, w) end
end

-- RadioSurvivor's notebook: shows the same list in its Missions tab (fn(playerNum) opens it). Removes the button.
function Journal.setHost(fn)
    Journal.host = fn
    local panel = ISEquippedItem.instance
    if panel and panel.rcJournal then
        panel:removeChild(panel.rcJournal)
        panel.rcJournal = nil
        panel:shrinkWrap()
    end
end

local function sidebar(panel)
    if Journal.host or panel.rcJournal or panel.playerNum ~= 0 then return end
    local h = 30
    local b = ISButton:new(0, panel.height + 8, panel.width, h, tr("JournalButton"), panel, function()
        Journal.toggle(0, false)
    end)
    b:initialise()
    b.tooltip = tr("JournalHint")
    panel:addChild(b)
    panel.rcJournal = b
    panel:shrinkWrap()
end

local previousSidebar = ISEquippedItem.initialise
function ISEquippedItem:initialise(...)
    local result = previousSidebar(self, ...)
    sidebar(self)
    return result
end

local previousWheel = ISDPadWheels.onDisplayRight
function ISDPadWheels.onDisplayRight(joypadData, ...)
    local result = previousWheel(joypadData, ...)
    local menu = getPlayerRadialMenu(joypadData.player)
    if menu and menu.javaObject ~= nil then -- the wheel was shown (not shown while paused)
        menu:addSlice(tr("JournalButton"), getTexture("media/ui/emotes/shrug.png"), Journal.toggle, joypadData.player, true)
    end
    return result
end

Events.OnServerCommand.Add(Journal.onServerCommand)
Events.OnGameStart.Add(function()
    if ISEquippedItem.instance then sidebar(ISEquippedItem.instance) end
end)

return Journal
