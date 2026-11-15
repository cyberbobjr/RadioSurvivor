require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISScrollingListBox'
require 'ISUI/ISComboBox'
--[[
CoreAI: Missions tab of the notebook (E21-T03). Client only, presentation only.

Rows: the open missions of the snapshot of the notebook server (CoreAI.notebookClient.snapshot.missions, CA_MissionList
order). Page: requester, state, the place and its clues (template view with showsPlace), the lines of the template's
view (CA_MissionViews), delay, reward, participants, the report expected (giver presentation of CA_MissionViews:
remote givers have no body to join). Buttons: accept, hand-over (delivery window, then the quote of the authority to
confirm), report, claim, abandon, invite a player near. The authority checks every gesture again.
Helpers of the rows: label, state, lot of a created reward, items of the inventory a mission accepts.
Texts: IGUI_CA_*.
]]
local Notebook = require 'CoreAI/CA_Notebook'
local Client = require 'CoreAI/CA_NotebookClient'
local MissionList = require 'CoreAI/CA_MissionList'
local Views = require 'CoreAI/CA_MissionViews'

local Missions = CoreAI.notebookMissions or {}
CoreAI.notebookMissions = Missions
if Missions.installed then return Missions end
Missions.installed = true

local UI = Notebook.ui
local fontHeight, width, fit = UI.fontHeight, UI.width, UI.fit
local stamp, enable, button = UI.stamp, UI.enable, UI.button
local function tr(key, ...) return getText('IGUI_CA_' .. key, ...) end

-- ---------------------------------------------------------------- helpers shared by the mission pages

function Missions.itemName(fullType)
    local script = getScriptManager():FindItem(fullType)
    return script and script:getDisplayName() or fullType
end

-- Kind of a scouted place (house, church...), translated; an unknown kind is shown as it is.
function Missions.placeName(kind)
    return getTextOrNull('IGUI_CA_Place_' .. tostring(kind)) or tostring(kind)
end

-- Word of a clue (E11-T09): IGUI_CA_<prefix><code>, or the code itself when unknown.
local function clueWord(prefix, code)
    return getTextOrNull('IGUI_CA_' .. prefix .. tostring(code)) or tostring(code or '')
end
-- One clue of a scouted place ({ key, args } with codes and town names), in the player's language; nil for an unknown
-- key (newer server).
local CLUE_ARGS = {
    Kind = function(a) return Missions.placeName(a[1]), clueWord('ClueSize_', a[2]), clueWord('ClueFloors_', a[3]) end,
    LandmarkNext = function(a) return clueWord('Landmark_', a[1]), clueWord('Dir_', a[2]) end,
    Landmark = function(a) return clueWord('Landmark_', a[1]), clueWord('ClueDistance_', a[2]), clueWord('Dir_', a[3]) end,
    TownIn = function(a) return tostring(a[1] or '') end,
    TownOutskirts = function(a) return tostring(a[1] or '') end,
    TownCountry = function(a) return tostring(a[1] or '') end,
}
function Missions.clueText(clue)
    if type(clue) ~= 'table' or type(clue.key) ~= 'string' then return nil end
    local key, args = 'IGUI_CA_Clue_' .. clue.key, CLUE_ARGS[clue.key]
    -- Arguments given to the existence test too: a %1 text read without them logs "Missing arguments" (Translator).
    local values = args and { args(type(clue.args) == 'table' and clue.args or {}) } or {}
    if getTextOrNull(key, unpack(values)) == nil then return nil end
    return getText(key, unpack(values))
end

-- Title of a mission row: kind of mission, then its requester.
function Missions.rowLabel(row)
    return getText(row.titleKey or 'IGUI_CA_Mission') .. ' - ' .. tostring(row.requester or '')
end

-- State of a mission in a sentence (CA_MissionList: an active mission whose objective is met waits for its report).
-- family: prefix of the keys (default 'MissionState_', the sentences of the notebook server's page).
function Missions.stateText(row, family)
    return tr((family or 'MissionState_') .. tostring(MissionList.stateKey(row)))
end

-- Second line of a row: the state in a short word when the full sentence is long (E03-T02: the sentence stays on the
-- page).
function Missions.secondLine(row)
    local state = row.state == 'active' and row.toReport and 'toReport' or row.state
    return getTextOrNull('IGUI_CA_StateShort_' .. tostring(state)) or tr('MissionState_' .. tostring(state))
end

-- E18-T33: items of a lot created by the requester's group (table of CA_MissionConfig.Caches), "2 x Name, ...".
function Missions.lotText(name)
    local entries = (require 'CoreAI/CA_MissionConfig').Caches.tables[name] or {}
    local parts = {}
    for _, entry in ipairs(entries) do
        local item = getScriptManager and getScriptManager():FindItem(entry[1])
        parts[#parts + 1] = tostring(entry[2]) .. ' \195\151 ' .. (item and item:getDisplayName() or entry[1])
    end
    return table.concat(parts, ', ')
end

local function inventoryItems(container, out, depth)
    if depth > 8 then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        out[#out + 1] = item
        if instanceof(item, 'InventoryContainer') then inventoryItems(item:getItemContainer(), out, depth + 1) end
    end
end

-- Items of the player a row accepts (same filter as the server: accepted type, not broken, not favourite, not equipped).
function Missions.candidates(player, row)
    local out, all = {}, {}
    if player == nil or type(row) ~= 'table' or type(row.accepted) ~= 'table' then return out end
    inventoryItems(player:getInventory(), all, 0)
    for _, item in ipairs(all) do
        if row.accepted[item:getFullType()] and item:getCondition() > 0 and not item:isFavorite()
                and not item:isEquipped() then
            out[#out + 1] = item
        end
    end
    return out
end

-- Rows of a hand-over window: "[x] name" cut to the row (ellipsis), room kept for the vanilla scroll bar (rows cut at
-- vscroll.x + 3, ISScrollingListBox.lua:494-495; E03-T07).
function Missions.drawCandidate(list, y, item)
    local mark = list.parent.chosen[item.item.id] and '[x] ' or '[ ] '
    local room = list.width - 8 - 17 - 4 - width(mark)
    list:drawText(mark .. fit(item.text, room), 8, y + 4, 1, 1, 1, 1, UIFont.Small)
    return y + list.itemheight
end

-- Window of a given size centred on the anchor (the notebook), else on the screen, always kept whole on the screen.
function Missions.centred(class, maxW, maxH, anchor)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(maxW, sw - 60), math.min(maxH, sh - 60)
    local x, y = (sw - w) / 2, (sh - h) / 2
    if anchor then
        x = anchor:getX() + (anchor:getWidth() - w) / 2
        y = anchor:getY() + (anchor:getHeight() - h) / 2
    end
    return class:new(math.floor(math.max(0, math.min(x, sw - w))), math.floor(math.max(0, math.min(y, sh - h))), w, h)
end

-- ---------------------------------------------------------------- Missions tab

-- Gesture on a mission of the page: the command with the row's mission and revision.
local function request(command, row, extra)
    if not row then return end
    local args = extra or {}
    args.mission, args.revision = row.id, row.revision
    Client.send(command, args)
end

local function createMissions(w)
    w.accept = w:addAction(stamp(w, tr('Accept'), function(win)
        local row = win.row
        win:confirm(tr('ConfirmAccept'), function() request('accept', row) end)
    end))
    w.deliver = w:addAction(stamp(w, tr('Deliver'), function(win) if win.row then win:openDelivery(win.row) end end))
    -- E11-T13: report of a met objective to the requester, next to them (the way without the bridge).
    w.report = w:addAction(stamp(w, tr('ReportButton'), function(win) request('report', win.row) end))
    w.claim = w:addAction(stamp(w, tr('ClaimShared'), function(win) request('claim', win.row) end))
    w.abandon = w:addAction(stamp(w, tr('Abandon'), function(win)
        local row = win.row
        win:confirm(tr('ConfirmAbandon'), function() request('abandon', row) end)
    end))
    w.invite = w:addAction(stamp(w, tr('Invite'), function(win)
        local target = win.inviteTargets[win.inviteChoice.selected]
        if target then request('invite', win.row, {character = target.id}) end
    end))
    w.inviteChoice = ISComboBox:new(0, 0, 100, fontHeight() + 14, w, nil)
    w.inviteChoice:initialise(); w:addChild(w.inviteChoice)
    w:own(w.inviteChoice)
    w:addBlock({element = w.inviteChoice, height = fontHeight() + 14})
end

local VIEW_CTX = {tr = Views.tr, placeName = Missions.placeName, clueText = Missions.clueText,
    itemName = Missions.itemName}

-- Page of a mission: what to do, where, how far, the reward; buttons by state.
local function missionDetail(self, row, line)
    if not row then line(tr('Empty_Missions')); return false end
    line(getText(row.titleKey)); line(tr('Requester', row.requester))
    -- E11-T13: objective met, the report to the requester is expected (in person, or on the voice's frequency).
    line(Missions.stateText(row))
    -- E11-T08: mission given by a remote giver (a radio voice): no body to join. E21-T03: presentation of the giver
    -- kind from the core registry (CA_MissionViews.registerGiver).
    local giver = Views.giver(row.donor)
    local remote = giver.remote == true
    -- E20-T01: lines proper to the template come from its view (CA_MissionViews, one file per template).
    local view = Views.get(row.template)
    if view and view.showsPlace then
        if row.placeKind and row.placeKind ~= '' then line(tr('ScoutPlace', Missions.placeName(row.placeKind))) end
        -- E11-T09: clues of the place, translated here (the server sends keys and codes only).
        local clues = {}
        for _, clue in ipairs(type(row.clues) == 'table' and row.clues or {}) do
            local said = Missions.clueText(clue)
            if said then clues[#clues + 1] = said end
        end
        if #clues > 0 then
            line(tr('ScoutClues'))
            for _, said in ipairs(clues) do line('- ' .. said) end
        end
    end
    if view then view.detail(row, line, VIEW_CTX) end
    line(tr('Time', math.ceil(row.remainingMs / 60000)))
    if row.rewardCount > 0 then line(tr('RewardShared', row.rewardCount, Missions.itemName(row.rewardType)))
    elseif row.unit == 'value' then line(tr('RewardGoodwill'))
    else line(tr('RewardInformation')) end
    line(tr('Participants', table.concat(row.participants, ', ')))
    if row.toReport then line(giver.reportLine and giver.reportLine(row) or tr('ReportInPerson', row.requester)) end
    -- E20-T01: a hand-over of items (template declaration handover, projected by the engine).
    if row.handover then line(tr('NoRefund')) end
    if row.claimedName ~= '' then line(tr('ClaimedBy', row.claimedName)) end
    if row.recovery then line(tr('Error_Recovery')) end
    if not row.near and not remote then line(tr('JoinRequester')) end
    self.accept:setVisible(row.invited and not row.engaged and (row.state == 'offer' or row.state == 'active'))
    enable(self.accept, not row.recovery)
    self.deliver:setVisible(row.engaged and row.state == 'active' and row.handover == true)
    enable(self.deliver, row.near and not row.recovery)
    self.report:setVisible(row.engaged and row.state == 'active' and row.toReport == true and not remote)
    enable(self.report, row.near and not row.recovery)
    self.claim:setVisible(row.engaged and row.state == 'success' and row.rewardCount > 0)
    enable(self.claim, row.near and row.claimedName == '' and not row.recovery)
    self.abandon:setVisible(row.engaged and row.state == 'active')
    enable(self.abandon, not row.recovery)
    if row.engaged and row.state == 'active' and not remote then
        local targets = Client.snapshot.inviteTargets or {}
        self.invite:setVisible(true); enable(self.invite, row.near and #targets > 0)
        local selected = self.inviteTargets and self.inviteTargets[self.inviteChoice.selected]
        self.inviteTargets = targets
        self.inviteChoice:clear()
        for i, target in ipairs(self.inviteTargets) do
            self.inviteChoice:addOption(target.name)
            if selected and target.id == selected.id then self.inviteChoice.selected = i end
        end
        self.inviteChoice:setVisible(true)
    end
    return false
end

Missions.page = {
    rows = function() return Client.snapshot.missions or {} end,
    rowLabel = Missions.rowLabel,
    secondLine = Missions.secondLine,
    create = createMissions,
    detail = missionDetail,
}
Notebook.registerTab({name = 'Missions', order = 30, color = {0.369, 0.478, 0.31},
    rows = Missions.page.rows, rowLabel = Missions.page.rowLabel, secondLine = Missions.page.secondLine,
    create = Missions.page.create, detail = Missions.page.detail})

-- ---------------------------------------------------------------- hand-over and quote

local Delivery = ISCollapsableWindow:derive('CA_UI_MissionDelivery')

function Delivery:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.items = ISScrollingListBox:new(12, self:titleBarHeight() + 12, self.width - 24, self.height - self:titleBarHeight() - 95)
    self.items:initialise(); self:addChild(self.items)
    self.items.itemheight = fontHeight() + 12
    self.chosen = {}
    for _, item in ipairs(Missions.candidates(getSpecificPlayer(0), self.mission)) do
        self.items:addItem(item:getDisplayName(), {id = item:getID()})
    end
    self.items:setOnMouseDownFunction(self, function(window, row)
        if window.chosen[row.id] then window.chosen[row.id] = nil
        else
            local count = 0
            for _ in pairs(window.chosen) do count = count + 1 end
            if count < window.mission.quantity - window.mission.delivered then window.chosen[row.id] = true end
        end
    end)
    self.items.doDrawItem = Missions.drawCandidate
    self.prepare = button(self, tr('ReviewDelivery'), function(window)
        local ids = {}
        for id in pairs(window.chosen) do ids[#ids + 1] = id end
        table.sort(ids)
        if #ids > 0 then request('prepare_delivery', window.mission, {items = ids}) end
    end)
    self.prepare:setX(12); self.prepare:setY(self.height - fontHeight() - 42)
end

-- Delivery window of a mission, created without being shown (read by the in-game suite rs.notebook.visual).
-- E03-T07: centred on the element anchor (the notebook), else on the screen, and always kept whole on the screen.
function Missions.newDelivery(mission, anchor)
    local window = Missions.centred(Delivery, 560, 520, anchor)
    window.title, window.mission = tr('DeliveryPieces'), mission
    window:setResizable(false); window:initialise()
    return window
end

function Notebook:openDelivery(mission)
    local window = Missions.newDelivery(mission, self)
    window:addToUIManager()
    Client.deliveryWindow = window
    return window
end

-- Quote of the authority for the chosen items: confirmed in a dialog (returned), then the hand-over is sent with its
-- token.
function Missions.confirmQuote(quote)
    if not Client.window then return end
    local text = tr('ConfirmDelivery', quote.count, quote.requester, quote.remaining)
    if quote.unit == 'value' then text = tr('ConfirmSupply', quote.count, quote.requester, quote.remaining, quote.value) end
    return Client.window:confirm(text, function()
        Client.send('confirm_delivery', {mission = quote.mission, revision = quote.revision, token = quote.token})
        if Client.deliveryWindow then Client.deliveryWindow:close() end
    end)
end

Client.registerCommand('quote', function(quote)
    if quote.world ~= Client.world or quote.run ~= Client.run then return end
    Missions.confirmQuote(quote)
end)

return Missions
