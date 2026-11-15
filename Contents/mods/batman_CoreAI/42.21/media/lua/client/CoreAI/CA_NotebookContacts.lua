require 'ISUI/ISTextEntryBox'
--[[
CoreAI: Contacts tab of the notebook (E21-T03). Client only, presentation only.

Rows: the NPCs the reader's character knows (snapshot of the notebook server, CoreAI.notebookClient.snapshot.contacts).
Page: name, group, personality, the page of the mod that gave the contact (Notebook.contactPages[row.page or
row.source](win, row, line)) or, without one, the relation lines of the NPC engine (Notebook.relationLines), then the
exchanges kept. Buttons: talk (select the NPC as the target of the local chat), clear the target, save the private
note; "Say:" line to the selected NPC (same 'talk' command and server checks as the local chat). A row given by a
contact source of a mod (row.source, CA_Contacts: an interlocutor known without a fiche of the notebook) shows its
name, group, the page of its mod and the exchanges kept, without buttons.
Key binding CoreAISelect (Ctrl+G by default): selects the nearest NPC as the target. Notices of the page (no NPC
engine, private state not written) and footer (target of the local chat) while a notebook server answers.
Texts: IGUI_CA_*.
]]
local Notebook = require 'CoreAI/CA_Notebook'
local Client = require 'CoreAI/CA_NotebookClient'

local Contacts = CoreAI.notebookContacts or {}
CoreAI.notebookContacts = Contacts
if Contacts.installed then return Contacts end
Contacts.installed = true

local UI = Notebook.ui
local fontHeight, width = UI.fontHeight, UI.width
local stamp, enable, paperEntry = UI.stamp, UI.enable, UI.paperEntry
local Speech = require 'CoreAI/CA_SpeechConfig'
-- Private note (E17-T06): multi-line text box (UITextBox2: words wrapped to its width, Enter adds a line up to
-- NOTE_LINES), NOTE_LINES lines of the small font high.
local NOTE_LINES = 4

local function tr(key, ...) return getText('IGUI_CA_' .. key, ...) end

-- ---------------------------------------------------------------- lines shared by the contact pages

-- Name, then the readable group name only (E17-T06: never the raw id), nothing without a group.
function Contacts.headLines(row, line)
    line(row.name)
    if type(row.groupName) == 'string' and row.groupName ~= '' then line(tr('Group', row.groupName)) end
end

-- Page of the mod that gave the contact; true when it wrote one.
function Contacts.sourcePage(w, row, line)
    local page = Notebook.contactPages[row.page or row.source]
    if not page then return false end
    page(w, row, line)
    return true
end

-- Exchanges kept with this contact.
function Contacts.historyLines(row, line)
    line(tr('KnownConversations'))
    for _, speech in ipairs(type(row.history) == 'table' and row.history or {}) do
        line(tostring(speech.author) .. ' : ' .. tostring(speech.text))
    end
end

-- Relation panel of a contact (E09-T07): the lines of the NPC engine's page (Notebook.relationLines), none without it.
function Contacts.relationLines(rel)
    if Notebook.relationLines then return Notebook.relationLines(rel) end
    return {}
end

function Contacts.secondLine(row) return row.alive and tr('Contact') or tr('Dead') end

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
    w.speak:setMaxTextLength(Speech.MAX_INPUT_CHARS)
    paperEntry(w.speak, true)
    w.speak:setPlaceholderTextRGBA(0.55, 0.51, 0.43, 1)
    w.speak.onCommandEntered = function() w:sendTalk() end
    w.speak.onOtherKey = function(_, key) if key == UI.KEY_ESCAPE then w:releaseFocus() end end
    w.speakSend = w:own(stamp(w, tr('TalkSend'), function(win) win:sendTalk() end, true))
    w.speakEditable = true
    w:own(w.speak); w:own(w.note)
    w:addEntry(w.speak, 'Contacts'); w:addEntry(w.note, 'Contacts')
    w:addBlock({entry = w.speak, send = w.speakSend, label = tr('Say')})
    w:addBlock({element = w.note, height = fontHeight() * NOTE_LINES + 10})
end

local function contactsDetail(w, row, line)
    local talkLine = row ~= nil and Client.snapshot.npcProvider == true
    w.speak:setVisible(talkLine); w.speakSend:setVisible(talkLine)
    if not row then line(tr('NoContactsSelect')); return false end
    if row.source then
        Contacts.headLines(row, line)
        Contacts.sourcePage(w, row, line)
        Contacts.historyLines(row, line)
        return false
    end
    Contacts.headLines(row, line)
    line(tr('Style_' .. row.personality.style))
    line(tr('Traits', row.personality.courage, row.personality.sociability, row.personality.generosity))
    if row.background ~= '' then line(row.background) end
    -- E09-T07: relation of this NPC toward the reader's character (words of the NPC engine's page, E18-T26).
    if not Contacts.sourcePage(w, row, line) and Notebook.relationLines then
        line(Notebook.relationTitle())
        for _, s in ipairs(Contacts.relationLines(row.relation)) do line(s) end
    end
    line(row.alive and (row.near and tr('UseChat') or tr('JoinRequester')) or tr('Dead'))
    Contacts.historyLines(row, line)
    w.talk:setVisible(true); enable(w.talk, row.alive and row.near)
    w.clearTarget:setVisible(true)
    w.note:setVisible(true); w.saveNote:setVisible(true)
    if w.noteNpc ~= row.id then w.note:setText(row.note or ''); w.noteNpc = row.id end
    return false
end

-- Say line of the Contacts tab (E17-T06): sentence to the selected NPC through Client.talk (same command and server
-- checks as the local chat); said aloud once the server queued it. Then gives the keyboard back to the game.
function Notebook:sendTalk()
    local text = Speech.cleanInput(self.speak:getText())
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

Contacts.page = {
    rows = function() return Client.snapshot.contacts or {} end,
    rowLabel = function(row) return row.name end,
    secondLine = Contacts.secondLine,
    create = createContacts,
    detail = contactsDetail,
    status = function(w) return w.talkStatus, w.talkIsProblem end,
    update = function(w)
        if w.speak:isVisible() then w:syncTalk() else w:releaseFocus(w.speak) end
    end,
}
Notebook.registerTab({name = 'Contacts', order = 20, color = {0.498, 0.435, 0.271},
    rows = Contacts.page.rows, rowLabel = Contacts.page.rowLabel, secondLine = Contacts.page.secondLine,
    create = Contacts.page.create, detail = Contacts.page.detail, status = Contacts.page.status,
    update = Contacts.page.update})

-- ---------------------------------------------------------------- frame hooks

-- Notices of every page while a notebook server answers: without an NPC engine the notebook has no interlocutor
-- (said on the Contacts page only); the private state of the server could not be written.
Notebook.notices[#Notebook.notices + 1] = function(_, tab, line)
    if not Client.hosted() then return end
    if tab == 'Contacts' and not Client.snapshot.npcProvider then line(tr('NoNPCProvider')) end
    if Client.snapshot.storage == false then line(tr('Error_Storage')) end
end

-- Left column wide enough for the target footer (E03-T02).
Notebook.columnWidths[#Notebook.columnWidths + 1] = function()
    if not Client.hosted() then return 0 end
    return width(tr('Target', tr('None'))) + 4
end

-- Footer of the left column: target of the local chat (unchanged text), while a notebook server answers.
Notebook.footer = function()
    if not Client.hosted() then return nil end
    local selected = Client.snapshot.selected
    local name = ''
    for _, contact in ipairs(Client.snapshot.contacts or {}) do if contact.id == selected then name = contact.name end end
    return tr('Target', name ~= '' and name or tr('None'))
end

-- Ctrl+G (configurable): selects the nearest visible NPC as the target of the local chat.
local bindingName = 'CoreAISelect'
if keyBinding then
    local present = false
    for _, b in ipairs(keyBinding) do if b.value == bindingName then present = true end end
    if not present then
        table.insert(keyBinding, {value = bindingName, key = Keyboard.KEY_G, ctrl = true})
        if getCore():getKey(bindingName) == 0 then getCore():addKeyBinding(bindingName, Keyboard.KEY_G, 0, false, true, false) end
    end
end
Events.OnKeyPressed.Add(function(key)
    if getCore():isKey(bindingName, key) and Client.hosted() then Client.selectNearest() end
end)

return Contacts
