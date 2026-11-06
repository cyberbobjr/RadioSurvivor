require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISButton'
require 'ISUI/ISScrollingListBox'
require 'ISUI/ISTextEntryBox'
require 'ISUI/ISComboBox'
--[[
RadioSurvivor's pages of the notebook (E18-T24, user decision of 2026-11-06). The notebook itself (frame, bookmarks,
sidebar button, registry of tabs) belongs to the core mod (RadioSurvivorCore/RC_Notebook); this file registers the
Radio tab, fills the common Contacts, Missions and Reputation tabs with RadioSurvivor's notebook data (snapshot of
RS_CarnetServer), and registers the Team tab when Living Knox is active too (its agreements move to Living Knox with
E18-T20).
]]
local Client = require 'RadioSurvivor/RS_Client'
if Client.notebookInstalled then return RS_Notebook end
Client.notebookInstalled = true
local Notebook = require 'RadioSurvivorCore/RC_Notebook'
local UI = Notebook.ui
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
-- Radio tab (E06-T04): per-frequency history kept by the authority, unread indicator, one-click tuning.
local History = require 'RadioSurvivor/RS_RadioHistory'
-- "Say" line of the Radio tab (E06-T06): same send path, checks and delay as the radio window module.
local Talk = require 'RadioSurvivor/RS_RadioTalk'
local MissionList = require 'RadioSurvivorCore/RC_MissionList' -- E18-T06: state shown, as in the core mod

local RS_MOD, LK_MOD = 'batman_RadioSurvivor', 'batman_LivingKnox'
local COLOR, INK_TAG, DOT = UI.COLOR, UI.INK_TAG, UI.DOT
local fontHeight, width, fit = UI.fontHeight, UI.width, UI.fit
local stamp, enable, paperEntry, button = UI.stamp, UI.enable, UI.paperEntry, UI.button
-- Rich text colours of the Radio lines by kind (said, answer, heard; map mark, area revealed: brick red).
local RADIO_COLORS = {said = '0.12,0.23,0.37', reply = '0.17,0.16,0.15', heard = '0.40,0.37,0.32', mark = '0.70,0.18,0.08'}
RADIO_COLORS.reveal = RADIO_COLORS.mark
RADIO_COLORS.mission = RADIO_COLORS.mark
RADIO_COLORS.reward = RADIO_COLORS.mark
RADIO_COLORS.note = RADIO_COLORS.mark
local DEVICE_CACHE_MS = 250
-- Private note (E17-T06): multi-line text box (UITextBox2: words wrapped to its width, Enter adds a line up to
-- NOTE_LINES), NOTE_LINES lines of the small font high.
local NOTE_LINES = 4

local function tr(key, ...) return getText('IGUI_RS_' .. key, ...) end
local function clean(s) return tostring(s or ''):gsub('[<>%[%]]', ' '):gsub('[%c]', ' ') end
local function itemName(fullType)
    local script = getScriptManager():FindItem(fullType)
    return script and script:getDisplayName() or fullType
end
-- Kind of a scouted place (RS_Rescue.KINDS: house, church...), translated; an unknown kind is shown as it is.
local function placeName(kind)
    return getTextOrNull('IGUI_RS_Place_' .. tostring(kind)) or tostring(kind)
end
-- Word of a clue (E11-T09): IGUI_RS_<prefix><code>, or the code itself when unknown.
local function clueWord(prefix, code)
    return getTextOrNull('IGUI_RS_' .. prefix .. tostring(code)) or tostring(code or '')
end
-- One clue of a scouted place (RS_Rescue.clueData: { key, args } with codes and town names), in the player's
-- language; nil for an unknown key (newer server).
local CLUE_ARGS = {
    Kind = function(a) return placeName(a[1]), clueWord('ClueSize_', a[2]), clueWord('ClueFloors_', a[3]) end,
    LandmarkNext = function(a) return clueWord('Landmark_', a[1]), clueWord('Dir_', a[2]) end,
    Landmark = function(a) return clueWord('Landmark_', a[1]), clueWord('ClueDistance_', a[2]), clueWord('Dir_', a[3]) end,
    TownIn = function(a) return tostring(a[1] or '') end,
    TownOutskirts = function(a) return tostring(a[1] or '') end,
    TownCountry = function(a) return tostring(a[1] or '') end,
}
local function clueText(clue)
    if type(clue) ~= 'table' or type(clue.key) ~= 'string' then return nil end
    local key, args = 'IGUI_RS_Clue_' .. clue.key, CLUE_ARGS[clue.key]
    -- Arguments given to the existence test too: a %1 text read without them logs "Missing arguments" (Translator).
    local values = args and { args(type(clue.args) == 'table' and clue.args or {}) } or {}
    if getTextOrNull(key, unpack(values)) == nil then return nil end
    return getText(key, unpack(values))
end
-- Relation panel of a contact (E09-T07): the server sends identifiers and game days only (RS_Relations.panel), every
-- word is translated here; an unknown identifier (newer server) falls back to a generic word, never a raw key.
local REL_LEVELS = {hostile = true, wary = true, cautious = true, favorable = true, trusting = true}
local REL_TRENDS = {up = true, down = true, stable = true}
local REL_NATURES = {good = true, bad = true, neutral = true}
local function relWord(prefix, id, fallback)
    return getTextOrNull('IGUI_RS_' .. prefix .. tostring(id)) or getText('IGUI_RS_' .. prefix .. fallback)
end
-- When a fact happened, in words (no number): today, yesterday, this week, earlier.
local function relWhen(today, day)
    local ago = (type(today) == 'number' and type(day) == 'number') and today - day or nil
    if ago == nil then return getText('IGUI_RS_RelWhen_earlier') end
    if ago <= 0 then return getText('IGUI_RS_RelWhen_today') end
    if ago == 1 then return getText('IGUI_RS_RelWhen_yesterday') end
    if ago < 7 then return getText('IGUI_RS_RelWhen_week') end
    return getText('IGUI_RS_RelWhen_earlier')
end
local function relationLines(rel)
    local out = {}
    if type(rel) ~= 'table' or not REL_LEVELS[rel.level] then
        out[1] = tr('RelUnknown')
        return out
    end
    out[#out + 1] = tr('RelLevel', tr('RelLevel_' .. rel.level),
        tr('RelTrend_' .. (REL_TRENDS[rel.trend] and rel.trend or 'stable')))
    if REL_LEVELS[rel.group] and rel.group ~= rel.level then out[#out + 1] = tr('RelGroup', tr('RelLevel_' .. rel.group)) end
    local agreements = type(rel.agreements) == 'table' and rel.agreements or {}
    for _, a in ipairs(agreements) do
        local scope = type(a.scope) == 'table' and a.scope or {}
        out[#out + 1] = tr('RelAgreement', relWord('RelKind_', a.kind, 'other'), relWord('RelState_', a.state, 'other'),
            relWord('RelScopeGroup_', scope.group, 'other'), relWord('RelScopeTeam_', scope.team, 'other'))
    end
    if #agreements == 0 then out[#out + 1] = tr('RelNoAgreement') end
    if rel.suspended == true then out[#out + 1] = tr('RelSuspended') end
    local facts = type(rel.facts) == 'table' and rel.facts or {}
    if #facts == 0 then out[#out + 1] = tr('RelNoFacts')
    else
        out[#out + 1] = tr('RelFacts')
        for _, f in ipairs(facts) do
            local nature = REL_NATURES[f.nature] and f.nature or 'neutral'
            local what = getTextOrNull('IGUI_RS_RelFact_' .. tostring(f.fact)) or tr('RelFact_' .. nature)
            out[#out + 1] = '- ' .. tr(f.source == 'personal' and 'RelFactPersonal' or 'RelFactGroup', relWhen(rel.today, f.day),
                what)
        end
    end
    return out
end

-- Reputation tab (E04-T04): internal reputation of the reader's character sent by the server (RS_Reputation
-- projection: level, trend, last acts with their game day, last change of level), translated here; no number is shown
-- (days become words). The personal relation of each known NPC is listed apart: it is not the reputation.
local REP_LEVELS = {bad = true, neutral = true, good = true}
local function repLevel(level) return tr('RepLevel_' .. (REP_LEVELS[level] and level or 'neutral')) end
local function repTrend(trend) return tr('RepTrend_' .. (REL_TRENDS[trend] and trend or 'stable')) end
-- One act: its translated reason (IGUI_RS_RepReason_*, public argument: a name), or a generic word for an unknown key.
local function repReason(r)
    local key = type(r.reasonKey) == 'string' and r.reasonKey:match('^IGUI_RS_RepReason_%a+$') and r.reasonKey or nil
    local args = type(r.reasonArgs) == 'table' and r.reasonArgs or {}
    local name = clean(args[1] or '')
    local text = key and getTextOrNull(key, name)
    if text then return text end
    return tr(r.sign == 1 and 'RepReason_good' or 'RepReason_bad')
end
local function reputationLines(rep, contacts)
    local out = {tr('GlobalReputation')}
    if type(rep) ~= 'table' or rep.available ~= true then
        out[#out + 1] = tr('ReputationUnavailable')
    else
        out[#out + 1] = tr('RepLevelLine', repLevel(rep.level)); out[#out + 1] = tr('RepTrendLine', repTrend(rep.trend))
        local change = type(rep.change) == 'table' and rep.change or nil
        if change and REP_LEVELS[change.from] and REP_LEVELS[change.to] then
            out[#out + 1] = tr('RepChanged', relWhen(rep.today, change.day), repLevel(change.from), repLevel(change.to))
        end
        local reasons = type(rep.reasons) == 'table' and rep.reasons or {}
        if #reasons == 0 then out[#out + 1] = tr('RepNoActs')
        else
            out[#out + 1] = tr('RepLastActs')
            for _, r in ipairs(reasons) do
                local text = tr('RepAct', relWhen(rep.today, r.day), repReason(r))
                if r.capped then text = text .. ' ' .. tr('RepCapped') end
                out[#out + 1] = '- ' .. text
            end
        end
    end
    out[#out + 1] = tr('PersonalTrustSeparate')
    local any = false
    for _, c in ipairs(type(contacts) == 'table' and contacts or {}) do
        local rel = type(c.relation) == 'table' and c.relation or nil
        if rel and REL_LEVELS[rel.level] and c.alive ~= false then
            out[#out + 1] = '- ' .. tr('RepTrust', c.name, tr('RelLevel_' .. rel.level))
            any = true
        end
    end
    if not any then out[#out + 1] = tr('RepNoTrust') end
    return out
end

-- Administrator view (Q17), answer of the server to 'rep_admin' (RS_Carnet_Server.reputationAdmin): one line per
-- live character and its last acts; nothing before the first answer; a refusal says so.
local function reputationAdminLines(view)
    if type(view) ~= 'table' then return {} end
    if view.ok ~= true then return {tr('RepAdminDenied')} end
    local out = {tr('RepAdminTitle')}
    for _, c in ipairs(type(view.characters) == 'table' and view.characters or {}) do
        out[#out + 1] = tr('RepAdminLine', clean(c.name), repLevel(c.level), repTrend(c.trend))
        for _, r in ipairs(type(c.reasons) == 'table' and c.reasons or {}) do
            out[#out + 1] = '   - ' .. tr('RepAct', relWhen(view.today, r.day), repReason(r))
        end
    end
    return out
end

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

RS_Notebook = {}
local RSN = RS_Notebook
RSN.relationLines = relationLines -- E09-T07: read by the benches and the in-game suite rs.relation.panel
RSN.reputationLines = reputationLines -- E04-T04: read by the benches and the in-game suite rs.reputation
RSN.reputationAdminLines = reputationAdminLines
RSN.toggle = function(...) return Notebook.toggle(...) end
RSN.newConfirm = Notebook.newConfirm

-- Administrator button of the Reputation tab (display only: the server checks the right at each request). Solo: debug
-- mode; MP: role capability PopmanManage (same rule as the frequency and Living Knox debug tools).
function RSN.canSeeAllReputations()
    if not isClient() then return type(isDebugEnabled) == 'function' and isDebugEnabled() == true end
    local p = getSpecificPlayer(0)
    local cap = Capability ~= nil and Capability.PopmanManage or nil
    local role = p and cap and p:getRole() or nil
    return role ~= nil and role:hasCapability(cap) == true
end

-- E04-T04 (Q9): warning over the character when the level of its reputation changes, once per change (key n of the
-- server change). The first snapshot after loading or a new character only sets the reference: no warning for a
-- change made before. Text 'Reputation: good'; the Reputation tab keeps the line of the last change.
function RSN.reputationWarning(rep)
    if type(rep) ~= 'table' or rep.available ~= true then return nil end
    local change = type(rep.change) == 'table' and rep.change or nil
    local n = change and change.n or 0
    local seen = Client.repChangeSeen
    Client.repChangeSeen = n
    if seen == nil or seen == n or not change or not REP_LEVELS[change.to] then return nil end
    local text = tr('RepWarn', repLevel(change.to))
    local p = getSpecificPlayer(0)
    local up = change.to == 'good' or (change.to == 'neutral' and change.from == 'bad')
    if p then
        if up then HaloTextHelper.addGoodText(p, text) else HaloTextHelper.addBadText(p, text) end
    end
    Client.repWarned = text
    return text
end

-- Snapshots and administrator answers reach the notebook through the client's receiver (RS_Client), wrapped once
-- (Client.notebookInstalled above): the vanilla event handler and the solo server both call Client.receive by name.
local baseReceive = Client.receive
function Client.receive(command, args)
    if command == 'identity' and type(args) == 'table' and args.character ~= Client.character then
        Client.repChangeSeen, Client.repAdmin = nil, nil
    end
    baseReceive(command, args)
    if command == 'snapshot' and type(args) == 'table' and Client.snapshot == args then
        RSN.reputationWarning(args.reputation)
    elseif command == 'rep_admin' and type(args) == 'table' then
        Client.repAdmin = args
        if Client.window then Client.window:refresh() end
    end
end

-- Second line of a row: last line heard (Radio), role (Team, E09-T03), state of a mission in a short word when the
-- full sentence is long (E03-T02: the sentence stays on the page), contact alive or dead.
function RSN.rowSecondLine(row)
    -- E06-T07: the voice of the frequency once known (contact, note read, frequency given), else the last line.
    if row.khz and row.voice then return History.voiceName(row.voice) end
    if row.khz then return tr('RadioLast', row.when ~= '' and row.when or '-') end
    if row.role then return tr('Role_' .. row.role) end
    -- E11-T13: an active mission whose objective is met waits for its report.
    local state = row.state and (row.state == 'active' and row.toReport and 'toReport' or row.state)
    if state then return getTextOrNull('IGUI_RS_StateShort_' .. tostring(state)) or tr('State_' .. state) end
    return row.alive and tr('Contact') or tr('Dead')
end

function Notebook:request(command, row, extra)
    row = row or self.row
    if not row then return end
    local args = extra or {}
    args.mission, args.revision = row.id, row.revision
    Client.send(command, args)
end

-- Is the player reading the Radio tab right now (visible, expanded)? With khz: this frequency, selected there.
-- Otherwise a new line lights the indicator (and the dot of its frequency).
function Notebook:viewingRadio(khz)
    if not self:viewing('Radio') then return false end
    return khz == nil or (self.row ~= nil and self.row.khz == khz)
end

-- ---------------------------------------------------------------- Radio tab

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
        local said = kind == 'mission' and placeName(l.text) or l.text
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
    secondLine = RSN.rowSecondLine,
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

-- ---------------------------------------------------------------- Contacts tab

local function createContacts(w)
    w.note = ISTextEntryBox:new('', 0, 0, 100, fontHeight() * NOTE_LINES + 10)
    w.note:initialise(); w:addChild(w.note); w.note:setMaxTextLength(2000)
    -- Settings of the Java text box, after addChild (base ui-windows.md): wrapped words and Enter for a new line.
    w.note:setMultipleLine(true); w.note:setMaxLines(NOTE_LINES)
    paperEntry(w.note, false)
    w.note.onOtherKey = function(_, key) if key == UI.KEY_ESCAPE then w:releaseFocus() end end
    w.saveNote = w:addAction(stamp(w, tr('SaveNote'), function(win)
        if win.row then Client.send('note', {npc = win.row.id, text = win.note:getText()}) end
    end))
    w.talk = w:addAction(stamp(w, tr('Talk'), function(win)
        if win.row then Client.send('select', {npc = win.row.id}) end
    end))
    w.clearTarget = w:addAction(stamp(w, tr('ClearTarget'), function() Client.send('deselect') end))
    -- E17-T06: "Say:" line to the selected NPC, in solo (no chat) and MP. Client.talk sends the same 'talk' command as
    -- the local chat: same server checks and same npc_talk request.
    w.speak = ISTextEntryBox:new('', 0, 0, 100, fontHeight(UIFont.Medium) + 10)
    w.speak.font = UIFont.Medium
    w.speak:initialise(); w:addChild(w.speak)
    w.speak:setMaxTextLength(Const.MAX_INPUT_CHARS)
    paperEntry(w.speak, true)
    w.speak:setPlaceholderTextRGBA(0.55, 0.51, 0.43, 1)
    w.speak.onCommandEntered = function() w:sendTalk() end
    w.speak.onOtherKey = function(_, key) if key == UI.KEY_ESCAPE then w:releaseFocus() end end
    w.speakSend = w:own(stamp(w, tr('TalkSend'), function(win) win:sendTalk() end, true))
    w.speakEditable = true
    w:own(w.speak); w:own(w.note)
    w:addEntry(w.speak, 'Contacts'); w:addEntry(w.note, 'Contacts')
    w:addBlock({entry = w.speak, send = w.speakSend, label = tr('RadioSay')})
    w:addBlock({element = w.note, height = fontHeight() * NOTE_LINES + 10})
end

local function contactsDetail(w, row, line)
    local talkLine = row ~= nil and Client.snapshot.npcProvider == true
    w.speak:setVisible(talkLine); w.speakSend:setVisible(talkLine)
    if not row then line(tr('Empty_Contacts')); return false end
    line(row.name)
    -- E17-T06: readable group name only (never the raw id), nothing without a group.
    if type(row.groupName) == 'string' and row.groupName ~= '' then line(tr('Group', row.groupName)) end
    line(tr('Style_' .. row.personality.style))
    line(tr('Traits', row.personality.courage, row.personality.sociability, row.personality.generosity))
    if row.background ~= '' then line(row.background) end
    -- E09-T07: relation of this NPC toward the reader's character, translated here.
    line(tr('RelTitle'))
    for _, s in ipairs(relationLines(row.relation)) do line(s) end
    line(row.alive and (row.near and tr('UseChat') or tr('JoinRequester')) or tr('Dead'))
    line(tr('KnownConversations'))
    for _, speech in ipairs(row.history or {}) do line(speech.author .. ' : ' .. speech.text) end
    w.talk:setVisible(true); enable(w.talk, row.alive and row.near)
    w.clearTarget:setVisible(true)
    w.note:setVisible(true); w.saveNote:setVisible(true)
    if w.noteNpc ~= row.id then w.note:setText(row.note or ''); w.noteNpc = row.id end
    return false
end

-- Say line of the Contacts tab (E17-T06): sentence to the selected NPC through Client.talk (same command and server
-- checks as the local chat); said aloud once the server queued it. Then gives the keyboard back to the game.
function Notebook:sendTalk()
    local text = Talk.cleanText(self.speak:getText())
    if text ~= '' and Client.talkProblem(self.row) == nil and Client.talk(text, true) then self.speak:setText('') end
    self:releaseFocus()
end

-- State of the Contacts Say line, read each frame on that tab: greyed with the reason (no target, out of range,
-- dead, answer awaited, delay between two sentences); placeholder naming the contact.
function Notebook:syncTalk()
    local row = self.row
    local reason, problem = Client.talkProblem(row)
    local editable = reason == nil
    if self.speakEditable ~= editable then
        self.speakEditable = editable
        self.speak:setEditable(editable)
        enable(self.speakSend, editable)
        if not editable then self:releaseFocus(self.speak) end
    end
    local name = row and row.name or ''
    if name ~= self.speakName then
        self.speakName = name
        self.speak:setPlaceholderText(name ~= '' and tr('TalkPlaceholder', name) or '')
    end
    self.talkStatus, self.talkIsProblem = reason and tr(reason) or nil, problem == true
end

Notebook.extendTab('Contacts', {
    rows = function() return Client.snapshot.contacts or {} end,
    rowLabel = function(row) return row.name end,
    secondLine = RSN.rowSecondLine,
    create = createContacts,
    detail = contactsDetail,
    status = function(w) return w.talkStatus, w.talkIsProblem end,
    update = function(w)
        if w.speak:isVisible() then w:syncTalk() else w:releaseFocus(w.speak) end
    end})

-- ---------------------------------------------------------------- Missions tab

local function createMissions(w)
    w.accept = w:addAction(stamp(w, tr('Accept'), function(win)
        local row = win.row
        win:confirm(tr('ConfirmAccept'), function() win:request('accept', row) end)
    end))
    w.deliver = w:addAction(stamp(w, tr('Deliver'), function(win) if win.row then win:openDelivery(win.row) end end))
    -- E11-T13: report of a met objective to the requester, next to them (the way without the bridge).
    w.report = w:addAction(stamp(w, tr('ReportButton'), function(win) win:request('report') end))
    w.claim = w:addAction(stamp(w, tr('Claim'), function(win) win:request('claim') end))
    w.abandon = w:addAction(stamp(w, tr('Abandon'), function(win)
        local row = win.row
        win:confirm(tr('ConfirmAbandon'), function() win:request('abandon', row) end)
    end))
    w.invite = w:addAction(stamp(w, tr('Invite'), function(win)
        local target = win.inviteTargets[win.inviteChoice.selected]
        if target then win:request('invite', nil, {character = target.id}) end
    end))
    w.inviteChoice = ISComboBox:new(0, 0, 100, fontHeight() + 14, w, nil)
    w.inviteChoice:initialise(); w:addChild(w.inviteChoice)
    w:own(w.inviteChoice)
    w:addBlock({element = w.inviteChoice, height = fontHeight() + 14})
end

-- Page of a mission: what to do, where, how far, the reward; buttons by state.
local function missionDetail(self, row, line)
    if not row then line(tr('Empty_Missions')); return false end
    line(getText(row.titleKey)); line(tr('Requester', row.requester))
    -- E11-T13: objective met, the report to the requester is expected (in person, or on the voice's frequency).
    line(tr('State_' .. MissionList.stateKey(row)))
    local scout = row.template == 'scout' -- E11-T03: reach a place, then report in person
    local retrieve = row.template == 'retrieve_id' -- E11-T05: bring back the ID card of a body
    local clear = row.template == 'clear' -- E11-T04: kill zombies inside the circle drawn on the map
    local recover = row.template == 'recover' -- E11-T06: carry the cache bag to the depot of the group
    local signal = row.template == 'signal' -- E11-T07: light a signal of a colour in the circle, at an hour
    -- E11-T08: mission given by a radio voice: no body to join, report on its frequency, information as reward.
    local voice = row.donor == 'voice'
    if scout or retrieve or clear or recover or signal then
        if row.placeKind and row.placeKind ~= '' then line(tr('ScoutPlace', placeName(row.placeKind))) end
        -- E11-T09: clues of the place, translated here (the server sends keys and codes only).
        local clues = {}
        for _, clue in ipairs(type(row.clues) == 'table' and row.clues or {}) do
            local said = clueText(clue)
            if said then clues[#clues + 1] = said end
        end
        if #clues > 0 then
            line(tr('ScoutClues'))
            for _, said in ipairs(clues) do line('- ' .. said) end
        end
    end
    if recover then
        if row.mapZone and not row.found then line(tr('RecoverMapZone')) end
        if row.cache and row.cache ~= '' then line(tr('RecoverCache', getText('IGUI_RS_Cache_' .. row.cache))) end
        line(row.found and tr('RecoverFound', row.foundBy) or tr('RecoverNotFound'))
        if row.depotZone then line(tr('RecoverDepotZone')) end
        line(tr('RecoverReport'))
    elseif signal then
        if row.mapZone then line(tr('SignalMapZone')) end
        line(tr('SignalColor', getText('IGUI_RS_SignalColor_' .. tostring(row.color))))
        line(tr('SignalHour', row.hour, (row.hour + row.windowHours) % 24))
        line(row.lit and tr('SignalLit', row.litBy) or tr('SignalNotLit'))
        line(tr('SignalRule')); line(tr('SignalReport'))
    elseif clear then
        if row.mapZone then line(tr('ClearMapZone')) end
        line(tr('ClearProgress', row.kills, row.target))
        for _, part in ipairs(type(row.tally) == 'table' and row.tally or {}) do
            line('- ' .. tr('ClearBy', part.name, part.count))
        end
        line(tr('ClearRule')); line(tr('ClearReport'))
    elseif retrieve then
        if row.mapZone and not row.found then line(tr('RetrieveMapZone')) end
        if row.person and row.person ~= '' then line(tr('RetrievePerson', row.person)) end
        line(row.found and tr('RetrieveFound', row.foundBy) or tr('RetrieveNotFound'))
        line(tr('RetrieveReport'))
    elseif scout then
        -- E11-T10: approximate area drawn on the world map (missions created since).
        if row.mapZone and not row.zoneReached then line(tr('ScoutMapZone')) end
        if voice then
            line(row.zoneReached and tr('ScoutReachedRadio', row.reachedBy) or tr('ScoutNotReached'))
            line(tr('ScoutReportRadio'))
        else
            line(row.zoneReached and tr('ScoutReached', row.reachedBy) or tr('ScoutNotReached')); line(tr('ScoutReport'))
        end
    elseif row.unit == 'value' then
        -- E17-T03: supply offer of a Living Knox group, counted in value points (one item = its value).
        line(tr('SupplyProgress', row.delivered, row.quantity))
        local accepted = {}
        for fullType in pairs(row.accepted) do
            accepted[#accepted + 1] = itemName(fullType) .. ' (' .. tostring((row.values or {})[fullType] or 0) .. ')'
        end
        table.sort(accepted)
        line(tr('AcceptedItems', table.concat(accepted, ', ')))
        line(tr('SupplyValues'))
    else
        line(tr('Progress', row.delivered, row.quantity))
        if voice then
            if not row.depositReady then line(tr('DeadDropApproach')) end
            line(tr(row.depositMode == 'bag' and 'DeadDropBag' or 'DeadDropBox'))
            line(tr(row.depositCollected and 'DeadDropCollected' or 'DeadDropLeave'))
        end
        local accepted = {}
        for fullType in pairs(row.accepted) do accepted[#accepted + 1] = itemName(fullType) end
        table.sort(accepted)
        line(tr('AcceptedItems', table.concat(accepted, ', ')))
        line(tr('OneUnit'))
    end
    line(tr('Time', math.ceil(row.remainingMs / 60000)))
    if row.rewardCount > 0 then line(tr('Reward', row.rewardCount, itemName(row.rewardType)))
    elseif row.unit == 'value' then line(tr('RewardGoodwill'))
    else line(tr('RewardInformation')) end
    line(tr('Participants', table.concat(row.participants, ', ')))
    if row.toReport then line(row.donor == 'voice' and tr('ReportRadio', row.requester)
        or tr('ReportInPerson', row.requester)) end
    if not scout and not clear and not recover and not signal then line(tr('NoRefund')) end
    if row.claimedName ~= '' then line(tr('ClaimedBy', row.claimedName)) end
    if row.recovery then line(tr('Error_Recovery')) end
    if not row.near and not voice then line(tr('JoinRequester')) end
    self.accept:setVisible(row.invited and not row.engaged and (row.state == 'offer' or row.state == 'active'))
    enable(self.accept, not row.recovery)
    self.deliver:setVisible(row.engaged and row.state == 'active' and not scout and not clear and not recover
        and not signal)
    enable(self.deliver, row.near and not row.recovery)
    self.report:setVisible(row.engaged and row.state == 'active' and row.toReport == true and not voice)
    enable(self.report, row.near and not row.recovery)
    self.claim:setVisible(row.engaged and row.state == 'success' and row.rewardCount > 0)
    enable(self.claim, row.near and row.claimedName == '' and not row.recovery)
    self.abandon:setVisible(row.engaged and row.state == 'active')
    enable(self.abandon, not row.recovery)
    if row.engaged and row.state == 'active' and not voice then
        self.invite:setVisible(true); enable(self.invite, row.near and #(Client.snapshot.inviteTargets or {}) > 0)
        local selected = self.inviteTargets and self.inviteTargets[self.inviteChoice.selected]
        self.inviteTargets = Client.snapshot.inviteTargets or {}
        self.inviteChoice:clear()
        for i, target in ipairs(self.inviteTargets) do
            self.inviteChoice:addOption(target.name)
            if selected and target.id == selected.id then self.inviteChoice.selected = i end
        end
        self.inviteChoice:setVisible(true)
    end
    return false
end

Notebook.extendTab('Missions', {
    rows = function() return Client.snapshot.missions or {} end,
    rowLabel = function(row) return getText(row.titleKey or 'IGUI_RC_Mission') .. ' - ' .. row.requester end,
    secondLine = RSN.rowSecondLine,
    create = createMissions,
    detail = missionDetail,
    -- The snapshot of RadioSurvivor's notebook replaces the list of the core mod (same missions, same order).
    onOpen = false, update = false})

-- ---------------------------------------------------------------- Reputation tab

Notebook.extendTab('Reputation', {
    create = function(w)
        -- E04-T14 (Q17): read-only view of every character's reputation, administrators only (checked by the server).
        w.repAdmin = w:addAction(stamp(w, tr('RepAdminButton'), function() Client.send('rep_admin') end))
    end,
    detail = function(w, _, line)
        for _, s in ipairs(RSN.reputationLines(Client.snapshot.reputation, Client.snapshot.contacts)) do line(s) end
        if RSN.canSeeAllReputations() then
            w.repAdmin:setVisible(true)
            for _, s in ipairs(RSN.reputationAdminLines(Client.repAdmin)) do line(s) end
        end
        return false
    end})

-- ---------------------------------------------------------------- Team tab

-- Team tab (E09-T03): faction or lone team, own role, mandates; the owner designates or withdraws a negotiator. Shown
-- only with Living Knox (decision of 2026-11-06: the tab of the agreements, which move to Living Knox with E18-T20).
function Notebook:showTeam(row, line)
    local team = Client.snapshot.team
    if not team then line(tr('Empty_Team')); return end
    line(team.kind == 'faction' and tr('TeamFaction', team.name) or tr('TeamPersonal'))
    line(tr('TeamYou_' .. tostring(team.role)))
    line(tr('TeamRule'))
    if team.kind ~= 'faction' then return end
    line(tr('TeamMandates', team.negotiators, team.maxNegotiators))
    if not row then return end
    line(tr('TeamMember', row.name, tr('Role_' .. tostring(row.role))))
    if team.isOwner and row.role ~= 'owner' then
        local negotiator = row.role == 'negotiator'
        self.grant:setVisible(not negotiator); self.revoke:setVisible(negotiator)
        enable(self.grant, team.negotiators < team.maxNegotiators)
    end
end

Notebook.registerTab({name = 'Team', mods = {RS_MOD, LK_MOD}, order = 50, color = {0.478, 0.31, 0.369},
    label = function() return tr('Team') end,
    rows = function() local team = Client.snapshot.team return team and team.members or {} end,
    rowLabel = function(row) return row.name end,
    secondLine = RSN.rowSecondLine,
    create = function(w)
        -- The server checks again that the sender is the current owner of the faction.
        w.grant = w:addAction(stamp(w, tr('MandateGrant'), function(win)
            if win.row then Client.send('mandate', {member = win.row.id, action = 'grant'}) end
        end))
        w.revoke = w:addAction(stamp(w, tr('MandateRevoke'), function(win)
            if win.row then Client.send('mandate', {member = win.row.id, action = 'revoke'}) end
        end))
    end,
    detail = function(w, row, line) w:showTeam(row, line); return false end})

-- ---------------------------------------------------------------- frame hooks

-- Notices of every page: without an NPC engine the notebook has no interlocutor (said on the Contacts page only,
-- Walt's radio works); the private state of the server could not be written.
Notebook.notices[#Notebook.notices + 1] = function(_, tab, line)
    if tab == 'Contacts' and not Client.snapshot.npcProvider then line(tr('NoNPCProvider')) end
    if Client.snapshot.storage == false then line(tr('Error_Storage')) end
end

-- Left column wide enough on every tab for the Radio rows, the tune button and the target footer (E03-T02).
Notebook.columnWidths[#Notebook.columnWidths + 1] = function()
    return math.max(width(tr('RadioFrequency', '999.9'), UIFont.Medium) + DOT + 36,
        width(tr('RadioLast', '00/00 00:00')) + 24, width(tr('RadioHeardList')) + 4, width(tr('RadioTune')) + 24,
        width(tr('Target', tr('None'))) + 4)
end

-- Footer of the left column: target of the local chat (unchanged text).
Notebook.footer = function()
    local selected = Client.snapshot.selected
    local name = ''
    for _, contact in ipairs(Client.snapshot.contacts or {}) do if contact.id == selected then name = contact.name end end
    return tr('Target', name ~= '' and name or tr('None'))
end
Notebook.hints[#Notebook.hints + 1] = 'IGUI_RS_SelectHint'

-- Each opening or closing: the notebook asks a fresh snapshot; lines received while it was closed are read again on
-- opening (the whole history of the authority).
Notebook.onToggle[#Notebook.onToggle + 1] = function(w)
    Client.window = w
    Client.send('snapshot')
    if w:isVisible() then History.request() end
end

History.isViewing = function(khz) return Client.window ~= nil and Client.window:viewingRadio(khz) end
History.onChange = function()
    if Client.window and Client.window:isVisible() and Client.window.tab == 'Radio' then Client.window:refresh() end
end

local Delivery = ISCollapsableWindow:derive('RS_UI_Delivery')
local function inventoryItems(container, out, depth)
    if depth > 8 then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        out[#out + 1] = item
        if instanceof(item, 'InventoryContainer') then inventoryItems(item:getItemContainer(), out, depth + 1) end
    end
end

function Delivery:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.items = ISScrollingListBox:new(12, self:titleBarHeight() + 12, self.width - 24, self.height - self:titleBarHeight() - 95)
    self.items:initialise(); self:addChild(self.items)
    self.items.itemheight = fontHeight() + 12
    self.chosen = {}
    local all = {}
    inventoryItems(getSpecificPlayer(0):getInventory(), all, 0)
    for _, item in ipairs(all) do
        if self.mission.accepted[item:getFullType()] and item:getCondition() > 0 and not item:isFavorite() and not item:isEquipped() then
            self.items:addItem(item:getDisplayName(), {id = item:getID()})
        end
    end
    self.items:setOnMouseDownFunction(self, function(window, row)
        if window.chosen[row.id] then window.chosen[row.id] = nil
        else
            local count = 0
            for _ in pairs(window.chosen) do count = count + 1 end
            if count < window.mission.quantity - window.mission.delivered then window.chosen[row.id] = true end
        end
    end)
    -- E03-T07: item names cut to the row (ellipsis), room kept for the vanilla scroll bar (rows cut at vscroll.x + 3,
    -- ISScrollingListBox.lua:494-495).
    self.items.doDrawItem = function(list, y, item)
        local mark = list.parent.chosen[item.item.id] and '[x] ' or '[ ] '
        local room = list.width - 8 - 17 - 4 - width(mark)
        list:drawText(mark .. fit(item.text, room), 8, y + 4, 1, 1, 1, 1, UIFont.Small)
        return y + list.itemheight
    end
    self.prepare = button(self, tr('ReviewDelivery'), function(window)
        local ids = {}
        for id in pairs(window.chosen) do ids[#ids + 1] = id end
        table.sort(ids)
        if #ids > 0 then Client.send('prepare_delivery', {mission = window.mission.id, revision = window.mission.revision, items = ids}) end
    end)
    self.prepare:setX(12); self.prepare:setY(self.height - fontHeight() - 42)
end

-- Delivery window of a mission, created without being shown (read by the in-game suite rs.notebook.visual).
-- E03-T07: centred on the element anchor (the notebook), else on the screen, and always kept whole on the screen.
function RSN.newDelivery(mission, anchor)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(560, sw - 60), math.min(520, sh - 60)
    local x, y = (sw - w) / 2, (sh - h) / 2
    if anchor then
        x = anchor:getX() + (anchor:getWidth() - w) / 2
        y = anchor:getY() + (anchor:getHeight() - h) / 2
    end
    x = math.floor(math.max(0, math.min(x, sw - w)))
    y = math.floor(math.max(0, math.min(y, sh - h)))
    local window = Delivery:new(x, y, w, h)
    window.title, window.mission = tr('Delivery'), mission
    window:setResizable(false); window:initialise()
    return window
end

function Notebook:openDelivery(mission)
    local window = RSN.newDelivery(mission, self)
    window:addToUIManager()
    Client.deliveryWindow = window
    return window
end

Client.confirmQuote = function(quote)
    if not Client.window then return end
    local text = tr('ConfirmDelivery', quote.count, quote.requester, quote.remaining)
    if quote.unit == 'value' then text = tr('ConfirmSupply', quote.count, quote.requester, quote.remaining, quote.value) end
    return Client.window:confirm(text, function()
        Client.send('confirm_delivery', {mission = quote.mission, revision = quote.revision, token = quote.token})
        if Client.deliveryWindow then Client.deliveryWindow:close() end
    end)
end

-- Ctrl+G (configurable): selects the nearest visible NPC as the target of the local chat.
local bindingName = 'RadioSurvivorSelect'
if keyBinding then
    local present = false
    for _, b in ipairs(keyBinding) do if b.value == bindingName then present = true end end
    if not present then
        table.insert(keyBinding, {value = bindingName, key = Keyboard.KEY_G, ctrl = true})
        if getCore():getKey(bindingName) == 0 then getCore():addKeyBinding(bindingName, Keyboard.KEY_G, 0, false, true, false) end
    end
end
Events.OnKeyPressed.Add(function(key)
    if getCore():isKey(bindingName, key) then Client.selectNearest() end
end)
return RSN
