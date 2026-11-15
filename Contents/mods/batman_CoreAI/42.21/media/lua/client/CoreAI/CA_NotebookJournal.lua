require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISScrollingListBox'
--[[
CoreAI: pages of the common tabs while no notebook server answers (Living Knox alone). TEMPORARY until E21 slice 11
(notebook server in CoreAI): this file is then deleted with the client commands of CA_MissionJournal.

Moved unchanged from CA_Notebook (E18-T06, E18-T25, E18-T26, E18-T29, E18-T33). The data come from the mission journal
of the authority (CA_MissionJournal, commands "missions", "contacts" and "reputation" of the module CoreAI, asked again
every REFRESH_MS while the tab is shown; gesture "mission" { action = deliver | claim }). The tab files
(CA_NotebookContacts, CA_NotebookMissions, CA_NotebookReputation) keep their pages; each field of those tabs reads the
page of this file while CoreAI.notebookClient.hosted() is false. Row helpers (labels, states, lot, candidates of a
hand-over, contact lines, reputation lines) are the tab files'.
]]
local Notebook = require 'CoreAI/CA_Notebook'
local Client = require 'CoreAI/CA_NotebookClient'
local Config = require 'CoreAI/CA_NotebookConfig'
local Contacts = require 'CoreAI/CA_NotebookContacts'
local Missions = require 'CoreAI/CA_NotebookMissions'
require 'CoreAI/CA_NotebookReputation'

if Notebook.Journal then return Notebook.Journal end
local REFRESH_MS = 3000
local UI = Notebook.ui
local fontHeight, stamp, enable, button = UI.fontHeight, UI.stamp, UI.enable, UI.button
local function tr(key, ...) return getText('IGUI_CA_' .. key, ...) end

-- Data of the core mod asked to the authority (CA_MissionJournal): command -> time of the last request.
local asked = {}
function Notebook.request(command)
    asked[command] = getTimestampMs()
    local p = getSpecificPlayer(0)
    if p ~= nil then sendClientCommand(p, Config.MODULE, command, {}) end
end
local function poll(command)
    if getTimestampMs() - (asked[command] or 0) >= REFRESH_MS then Notebook.request(command) end
end
local function alone() return not Client.hosted() end
local function shown(tab)
    local w = Notebook.window
    return w ~= nil and w.tab == tab and alone() and w or nil
end

-- ---------------------------------------------------------------- Missions

-- Open missions of the player's character, in the list order and states of CA_MissionList.
local Journal = {rows = {}}
Notebook.Journal = Journal -- missions tab helpers (tests, E18-T33)
Notebook.journal = Journal
function Journal.request() Notebook.request('missions') end
Journal.lotText = Missions.lotText

Client.registerCommand('missions', function(args)
    if type(args.missions) ~= 'table' then return end
    local rows = {}
    for _, row in ipairs(args.missions) do
        if type(row) == 'table' and type(row.id) == 'string' then rows[#rows + 1] = row end
    end
    Journal.rows = rows
    local w = shown('Missions')
    if w then w:refresh() end
end)

-- E18-T29: gesture on a mission of the journal (CA_MissionJournal "mission"): hand-over or claim, next to the requester;
-- the authority checks everything and answers the list again (and "error" on a refusal).
function Journal.act(action, row, extra)
    if type(row) ~= 'table' then return end
    local args = extra or {}
    args.action, args.mission, args.revision = action, row.id, row.revision
    local p = getSpecificPlayer(0)
    if p ~= nil then sendClientCommand(p, Config.MODULE, 'mission', args) end
end

-- Hand-over window: the items of the inventory (bags included) the mission accepts, at most the count still asked
-- for; the authority checks them again (CA_Missions.deliver).
local Delivery = ISCollapsableWindow:derive('CA_UI_Delivery')
Notebook.Delivery = Delivery
Delivery.candidates = Missions.candidates

function Delivery:left()
    local row = self.mission
    return math.max(0, (tonumber(row.quantity) or 0) - (tonumber(row.delivered) or 0))
end

function Delivery:chosenIds()
    local ids = {}
    for id in pairs(self.chosen) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function Delivery:toggle(id)
    if self.chosen[id] then self.chosen[id] = nil
    elseif #self:chosenIds() < self:left() then self.chosen[id] = true end
end

function Delivery:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + 12
    self.items = ISScrollingListBox:new(12, top, self.width - 24, self.height - top - fontHeight() - 54)
    self.items:initialise(); self:addChild(self.items)
    self.items.itemheight = fontHeight() + 12
    self.chosen = {}
    for _, item in ipairs(Missions.candidates(getSpecificPlayer(0), self.mission)) do
        self.items:addItem(item:getDisplayName(), {id = item:getID()})
    end
    self.items:setOnMouseDownFunction(self, function(window, row) window:toggle(row.id) end)
    self.items.doDrawItem = Missions.drawCandidate
    self.send = button(self, tr('DeliverSend'), function(window)
        local ids = window:chosenIds()
        if #ids > 0 then
            Journal.act('deliver', window.mission, {items = ids})
            window:close()
        end
    end)
    self.send:setX(12); self.send:setY(self.height - fontHeight() - 30)
end

function Delivery:prerender()
    ISCollapsableWindow.prerender(self)
    if #self.items.items == 0 then
        self:drawText(tr('DeliverEmpty'), 16, self:titleBarHeight() + 16, 1, 1, 1, 1, UIFont.Small)
    end
end

function Delivery:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if Notebook.delivery == self then Notebook.delivery = nil end
end

-- Created without being shown (benches); centred on the notebook, kept whole on the screen.
function Delivery.create(row, anchor)
    local window = Missions.centred(Delivery, 480, 420, anchor)
    window.title, window.mission = tr('Delivery'), row
    window:setResizable(false); window:initialise()
    return window
end

function Journal.openDelivery(row, anchor)
    if Notebook.delivery then Notebook.delivery:close() end
    local window = Delivery.create(row, anchor)
    window:addToUIManager()
    Notebook.delivery = window
    return window
end

function Journal.detail(w, row, line)
    if not row then line(tr('JournalEmpty')); return false end
    line(Missions.stateText(row, 'State_'))
    line(tr('Requester', tostring(row.requester or '')))
    if type(row.remainingMs) == 'number' then line(tr('TimeLeft', math.ceil(row.remainingMs / 60000))) end
    if type(row.rewardCount) == 'number' and row.rewardCount > 0 and type(row.rewardType) == 'string' then
        line(tr('Reward', row.rewardCount, Missions.itemName(row.rewardType)))
    elseif type(row.rewardTable) == 'string' then
        line(tr('RewardLot', Missions.lotText(row.rewardTable)))
    end
    if type(row.participants) == 'table' and #row.participants > 0 then
        line(tr('Participants', table.concat(row.participants, ', ')))
    end
    if row.toReport then line(tr('ReportHint')) end
    local handover = type(row.accepted) == 'table' and row.engaged == true and row.state == 'active'
        and not row.toReport and row.donor ~= 'voice'
    if handover and type(row.quantity) == 'number' then
        line(tr('Delivered', tonumber(row.delivered) or 0, row.quantity)); line(tr('DeliverHint'))
    end
    if row.toClaim then line(tr('ClaimHint')) end
    w.journalDeliver:setVisible(handover); enable(w.journalDeliver, not row.recovery)
    w.journalClaim:setVisible(row.toClaim == true); enable(w.journalClaim, not row.recovery)
    return false
end

local missionsPage = {
    rows = function() return Journal.rows end,
    rowLabel = Missions.rowLabel,
    secondLine = function(row) return Missions.stateText(row, 'State_') end,
    create = function(w)
        w.journalDeliver = w:addAction(stamp(w, tr('Deliver'), function(win)
            if win.row then Journal.openDelivery(win.row, win) end
        end))
        w.journalClaim = w:addAction(stamp(w, tr('Claim'), function(win) Journal.act('claim', win.row) end, true))
    end,
    detail = Journal.detail,
    onOpen = function() Notebook.request('missions') end,
    update = function() poll('missions') end,
}

-- ---------------------------------------------------------------- Contacts

-- Contacts given by the active mods (CA_Contacts): rows sent by the authority, page of each source.
Notebook.contactRows = {}
Client.registerCommand('contacts', function(args)
    local rows = {}
    for _, row in ipairs(type(args.contacts) == 'table' and args.contacts or {}) do
        if type(row) == 'table' and type(row.id) == 'string' then rows[#rows + 1] = row end
    end
    Notebook.contactRows = rows
    local w = shown('Contacts')
    if w then w:refresh() end
end)

local contactsPage = {
    rows = function() return Notebook.contactRows end,
    rowLabel = function(row) return tostring(row.name or row.id) end,
    secondLine = function(row) return row.alive == false and tr('Dead') or tr('Contact') end,
    detail = function(w, row, line)
        if not row then line(tr('Empty_Contacts')); return false end
        Contacts.headLines(row, line)
        Contacts.sourcePage(w, row, line)
        Contacts.historyLines(row, line)
        return false
    end,
    onOpen = function() Notebook.request('contacts') end,
    update = function() poll('contacts') end,
}

-- ---------------------------------------------------------------- Reputation

Notebook.reputationData = nil
Client.registerCommand('reputation', function(args)
    Notebook.reputationData = type(args.reputation) == 'table' and args.reputation or nil
    local w = shown('Reputation')
    if w then w:refresh() end
end)

local reputationPage = {
    detail = function(_, _, line)
        for _, s in ipairs(Notebook.reputationLines(Notebook.reputationData)) do line(s) end
        return false
    end,
    onOpen = function() Notebook.request('reputation') end,
    update = function() poll('reputation') end,
}

-- ---------------------------------------------------------------- page of each tab by the presence of a server

local FIELDS = {'rows', 'rowLabel', 'secondLine', 'detail', 'status', 'update', 'onOpen'}
local function attach(name, page)
    local spec = Notebook.tabSpec(name)
    local hosted = {}
    for _, field in ipairs(FIELDS) do hosted[field] = spec[field] end
    for _, field in ipairs(FIELDS) do
        if hosted[field] or page[field] then
            spec[field] = function(...)
                local fn = hosted[field]
                if alone() then fn = page[field] end
                if fn then return fn(...) end
            end
        end
    end
    local create = spec.create
    spec.create = function(w)
        if create then create(w) end
        if page.create then page.create(w) end
    end
end
attach('Contacts', contactsPage)
attach('Missions', missionsPage)
attach('Reputation', reputationPage)

return Journal
