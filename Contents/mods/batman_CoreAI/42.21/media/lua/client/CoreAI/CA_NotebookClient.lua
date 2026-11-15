--[[
CoreAI: client transport of the notebook (E21-T03). Global CoreAI.notebookClient.

Sends the notebook commands on the network module of the core mod (CA_NotebookConfig.MODULE, 'CoreAI') with the
session of the authority (world, run), keeps the last snapshot, the speech to the selected NPC (local chat and the
Say line of the Contacts page) and the answers shown over the body. Answers of the authority (OnServerCommand, or a
direct call by name in solo: Client.receive) go through a registry of client commands:
  Client.registerCommand(name, fn)  -- fn(args, player): the one owner of the command name
  Client.listen(name, fn)           -- fn(args, player): called after the owner (pages that react to a command)
A command without an owner is ignored. Owners here: identity, snapshot, error, speech, queued, offer; the pages of the
notebook and the mods own the others (quote, rep_admin, team...).
Client.hosted(): a notebook server answered the hello with its session (Client.world). An identity answered without a
session (CA_Identity alone: no notebook server, an NPC engine alone) stops the hellos of the poll.
]]
CoreAI = CoreAI or {}
if CoreAI.notebookClient then return CoreAI.notebookClient end
local Config = require 'CoreAI/CA_NotebookConfig'
local Speech = require 'CoreAI/CA_SpeechConfig'
local P = require 'CoreAI/CA_NPCProvider'
local Client = {snapshot = {contacts = {}, missions = {}, inviteTargets = {}, events = {}}, seen = {}, seenOrder = {}, inbox = {},
    commands = {}, listeners = {}}
CoreAI.notebookClient = Client
local wrappedChat, wrappedSay = false, false
local nextSync = 0
local function pack(...) return {n = select('#', ...), ...} end

function Client.send(command, args)
    local player = getSpecificPlayer(0)
    if not player then return end
    args = args or {}
    args.world, args.run = Client.world, Client.run
    sendClientCommand(player, Config.MODULE, command, args)
end

function Client.hello()
    local p = getSpecificPlayer(0)
    if p then Client.send('hello', {v = Config.VERSION, character = p:getModData().CA_Character}) end -- never empty
end

-- Speech to an NPC (E17-T06, E21-T05): ONE path for the local "say" chat (MP only, captured by the ISChat wrapper
-- below), the Say line of the notebook Contacts tab (solo and MP, no chat in solo) and the menu of an NPC engine on a
-- body (Client.talkTo). All send the same 'talk' command; the server applies the same checks (target, range, chat
-- rules, delay, budget) and builds the same npc_talk request. A chat sentence without a selected target goes to the
-- nearest NPC in range, and to nobody, silently, when none is near (decision 1 of carnet-commun-e21.md). The client
-- only greys the notebook line while an answer is awaited or too soon after a sentence (the server decides anyway).
Client.TALK_WAIT_MS = Speech.REQUEST_TIMEOUT_MS + 5000
-- Server rejections that end the wait of a sentence (notebook server: talk and poll).
local TALK_ERRORS = {Range = true, Text = true, Chat = true, Cooldown = true, Busy = true, Bridge = true, NoAnswer = true,
    Storage = true, Session = true, Identity = true}

-- E17-T11: the real game language code (ES, PTBR, ES_CL...), checked by its form; the server checks it again.
local function language()
    local lang = Translator.getLanguage()
    return Speech.languageCode(lang and lang:name())
end

-- Says the sentence aloud once the server queued it (notebook line only: the chat already said it). MP: vanilla
-- chat "say" (heard by the other players; the wrapper of processSayMessage captures only ISChat input, so no second
-- request); solo (no chat): overhead line of the character.
local function speakAloud(text)
    local p = getSpecificPlayer(0)
    if not p or type(text) ~= 'string' or text == '' then return end
    if isClient() and type(processSayMessage) == 'function' then processSayMessage(text) else p:Say(text) end
end

function Client.isWaiting()
    local w = Client.waiting
    if w and getTimestampMs() - w.at > Client.TALK_WAIT_MS then Client.waiting, w = nil, nil end
    return w ~= nil
end

-- Sends one 'talk' command (fields: its extra arguments). awaited: {npc = fiche id of the target or nil} to wait for the
-- answer, nil for a chat sentence without a target; spoken: said aloud once the server queued it (not a chat line).
local function sendTalk(text, fields, awaited, spoken)
    text = tostring(text or ''):match('^%s*(.-)%s*$')
    if text == '' then return false end
    local now = getTimestampMs()
    -- Set before sending: in solo the command is queued and handled at the next update, which may answer at once.
    if awaited then Client.waiting = {at = now, npc = awaited.npc, text = spoken and text or nil} end
    Client.lastTalkAt = now
    local args = fields or {}
    args.text, args.channel, args.language = text, 'say', language()
    Client.send('talk', args)
    return true
end

-- Sends one sentence to the selected NPC. spoken: the notebook line (said aloud after the server queued it). chat: a
-- sentence of the say chat, which goes to the nearest NPC when no target is selected.
function Client.talk(text, spoken, chat)
    local selected = Client.snapshot.selected
    if chat and (selected == nil or selected == '') then return sendTalk(text, {chat = true}, nil, false) end
    return sendTalk(text, chat and {chat = true} or nil, {npc = selected}, spoken)
end

-- Sends one sentence to the NPC of the provider with this id (menu of an NPC engine on a body): the server selects it
-- (same checks as the 'select' command), then speaks to it; said aloud once queued.
function Client.talkTo(incarnation, text)
    if incarnation == nil then return false end
    return sendTalk(text, {incarnation = incarnation}, {}, true)
end

-- Why the notebook cannot speak to this contact now (IGUI_CA_<key>, problem flag), or nil.
function Client.talkProblem(row)
    if not row then return 'TalkSelectFirst', false end
    if not row.alive then return 'TalkDead', true end
    if Client.snapshot.selected ~= row.id then return 'TalkSelectFirst', false end
    if not row.near then return 'TalkOutOfRange', true end
    if Client.isWaiting() then return 'TalkWaiting', false end
    if Client.lastTalkAt and getTimestampMs() - Client.lastTalkAt < Speech.COOLDOWN_MS then return 'Error_Cooldown', false end
    return nil
end

-- Shows an NPC answer: speech bubble over the body at once, and local chat line (MP, once the say chat is known).
-- Solo has no chat (E17-T06): bubble only, the answer is also kept in the notebook history. E17-T14: the bubble never
-- waits for the say chat, which is discovered only by a chat message (OnAddMessage) and may stay unknown; MP without
-- a known say chat yet: only the chat line is kept in the inbox (false), the bubble is not shown twice.
local function inject(args)
    if not args.bubbled then
        args.bubbled = true
        P.bubble(P.objects()[args.incarnation], args.text, Speech.HEARING_RANGE)
    end
    if not isClient() then return true end
    local chat = Client.say and ISChat and ISChat.instance
    if not chat then return false end
    local message = Client.say:createMessage(args.text)
    message:setAuthor(args.name)
    message:setLocal(true)
    message:setOverHeadSpeech(false)
    message:setShouldAttractZombies(false)
    message:setShowInChat(true)
    Client.injecting = true
    Client.say:showMessage(message) -- never sendToServer / RangeBasedChat.sendMessageToChatMembers
    Client.injecting = false
    return true
end

local function drain()
    local remaining = {}
    for _, event in ipairs(Client.inbox) do if not inject(event) then remaining[#remaining + 1] = event end end
    Client.inbox = remaining
end

-- E17-T14: ChatType is a Java enum NOT exposed to Lua: no method can be called on it (in game, getType():getValue()
-- raised "attempted index: getValue of non-table: say" on every message, so the say chat was never discovered in MP);
-- its tostring is its name (J/network/chat/ChatType.java: no toString override).
function Client.isSayChat(chat)
    if chat == nil then return false end
    local ok, kind = pcall(function() return tostring(chat:getType()) end)
    return ok and kind == 'say'
end

function Client.observeMessage(message)
    -- This event discovers the exposed ChatBase and acknowledges the local vanilla display.
    -- It NEVER sends a dialogue request, even for another player's incoming message.
    local chat = message:getChat()
    if Client.isSayChat(chat) then
        Client.say = chat
        if Client.inSay and not Client.injecting then
            local p = getSpecificPlayer(0)
            if p and message:getAuthor() == p:getUsername() and chat:isEnabled() then Client.admitted = true end
        end
    end
end

function Client.installChat()
    if not wrappedSay and type(processSayMessage) == 'function' then
        local previous = processSayMessage
        processSayMessage = function(...)
            local inEntry = Client.inEntry
            Client.inSay, Client.admitted = inEntry, false
            local result = pack(pcall(previous, ...))
            local admitted = Client.admitted
            Client.inSay = false
            if not result[1] then error(result[2]) end
            if inEntry and admitted then
                local text = select(1, ...)
                if type(text) == 'string' and checkPlayerCanUseChat('/say') then Client.submitted = text end
            end
            return unpack(result, 2, result.n)
        end
        wrappedSay = true
    end
    if not wrappedChat and ISChat and type(ISChat.onCommandEntered) == 'function' then
        local previous = ISChat.onCommandEntered
        ISChat.onCommandEntered = function(...)
            local wasInEntry = Client.inEntry
            Client.inEntry, Client.submitted = true, nil
            local result = pack(pcall(previous, ...))
            local submitted = Client.submitted
            Client.inEntry, Client.submitted = wasInEntry, nil
            if not result[1] then error(result[2]) end
            if submitted then Client.talk(submitted, false, true) end
            return unpack(result, 2, result.n)
        end
        wrappedChat = true
    end
end

function Client.selectNearest()
    if ISChat and ISChat.focused then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    local nearest, distance
    for id, npc in pairs(P.objects()) do
        if P.near(player, npc, Speech.SELECT_RANGE) then
            local dx, dy = npc:getX() - player:getX(), npc:getY() - player:getY()
            local d = dx * dx + dy * dy
            if not distance or d < distance then nearest, distance = id, d end
        end
    end
    if nearest then Client.send('select', {incarnation = nearest})
    else Client.send('deselect'); HaloTextHelper.addBadText(player, getText('IGUI_CA_Error_NpcRange')) end
end

function Client.hosted() return Client.world ~= nil end

function Client.registerCommand(name, fn) Client.commands[name] = fn end

function Client.listen(name, fn)
    local list = Client.listeners[name] or {}
    list[#list + 1] = fn
    Client.listeners[name] = list
end

function Client.receive(command, args)
    if type(args) ~= 'table' then args = {} end
    local owner = Client.commands[command]
    if not owner then return end
    local p = getSpecificPlayer(0)
    owner(args, p)
    for _, fn in ipairs(Client.listeners[command] or {}) do fn(args, p) end
end

local function refresh() if Client.window then Client.window:refresh() end end

Client.registerCommand('identity', function(args, p)
    if Client.world ~= args.world or Client.run ~= args.run or Client.character ~= args.character then
        Client.snapshot = {contacts = {}, missions = {}, inviteTargets = {}, events = {}}
        Client.inbox, Client.seen, Client.seenOrder = {}, {}, {}
    end
    Client.character, Client.world, Client.run = args.character, args.world, args.run
    -- An identity without a session comes from CA_Identity alone: no notebook server to greet again.
    Client.alone = args.world == nil
    if p then p:getModData().CA_Character = args.character end
end)

Client.registerCommand('snapshot', function(args, p)
    if args.world ~= Client.world or args.run ~= Client.run then return end
    local previous = Client.snapshot.selected
    Client.snapshot = args
    if args.selected and args.selected ~= '' and previous ~= args.selected and p then
        for _, npc in ipairs(args.contacts or {}) do
            if npc.id == args.selected then HaloTextHelper.addGoodText(p, npc.name); break end
        end
    end
    -- E11-T10: approximate areas of the active missions drawn on (or removed from) the world map (CoreAI, E21-T03).
    local MapZones = require 'CoreAI/CA_MapZones'
    if type(MapZones) == 'table' then MapZones.zones(args.missions) end
    refresh()
end)

-- Refusal of the authority (notebook, teams): one message over the character.
-- While a notebook server answers, some reasons read its own words (a selected NPC out of range).
Client.HOSTED_ERRORS = {Range = 'NpcRange'}
local function errorText(reason)
    local key = Client.hosted() and Client.HOSTED_ERRORS[reason] or reason
    return getTextOrNull('IGUI_CA_Error_' .. tostring(key)) or getText('IGUI_CA_Error_State')
end

Client.registerCommand('error', function(args, p)
    local text = errorText(args.reason)
    if p then HaloTextHelper.addBadText(p, text) end
    Client.lastError = args.reason
    if TALK_ERRORS[args.reason] then Client.waiting = nil end
    if args.reason == 'Session' or args.reason == 'Identity' then Client.world, Client.run = nil, nil; Client.hello() end
    refresh()
end)

Client.registerCommand('speech', function(args)
    if args.world ~= Client.world or args.run ~= Client.run then return end
    if type(args.id) ~= 'string' or Client.seen[args.id] then return end
    -- The answer of the awaited NPC ends the wait of the Say line. E08-T05: only the answer to this character's own
    -- sentence (request id given by 'queued'), not another player's intervention answered by the same NPC.
    -- A sentence of the menu (talkTo) knows its answer by the request id only.
    local w = Client.waiting
    if w and ((w.id and w.id == args.id) or (not w.id and w.npc ~= nil and w.npc == args.npc)) then
        Client.waiting = nil
    end
    Client.seen[args.id] = true
    Client.seenOrder[#Client.seenOrder + 1] = args.id
    if #Client.seenOrder > 256 then Client.seen[table.remove(Client.seenOrder, 1)] = nil end
    if not inject(args) then
        Client.inbox[#Client.inbox + 1] = args
        if #Client.inbox > 40 then table.remove(Client.inbox, 1) end
    end
end)

Client.registerCommand('queued', function(args)
    -- Sentence admitted by the server (talk): a notebook sentence is said aloud now, once.
    local w = Client.waiting
    if w then
        -- E08-T05: the request id of every admitted sentence (chat or notebook line) identifies its answer.
        local text = w.text
        w.text, w.id = nil, args.id
        if text then speakAloud(text) end
    end
    refresh()
end)

Client.registerCommand('offer', function(args, p)
    -- E17-T09: new mission offer made to this character: one message on screen per offer.
    if args.world ~= Client.world or args.run ~= Client.run or type(args.mission) ~= 'string' then return end
    Client.offersShown = Client.offersShown or {}
    if Client.offersShown[args.mission] then return end
    Client.offersShown[args.mission] = true
    if p then HaloTextHelper.addGoodText(p, getText('IGUI_CA_NewOffer')) end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module == Config.MODULE then Client.receive(command, args or {}) end
end)
Events.OnAddMessage.Add(Client.observeMessage)
Events.OnGameStart.Add(function() Client.installChat(); Client.hello() end)
Events.OnCreatePlayer.Add(function(num) if num == 0 then Client.hello() end end)
Events.OnTick.Add(function()
    Client.installChat()
    drain()
    local now = getTimestampMs()
    if now >= nextSync and getSpecificPlayer(0) then
        if Client.world then Client.send('snapshot') elseif not Client.alone then Client.hello() end
        -- The server pushes changes; polling only refreshes ranges and timers of an open notebook.
        local open = Client.window and Client.window:isVisible()
        nextSync = now + (open and Config.SNAPSHOT_OPEN_MS or Config.SNAPSHOT_CLOSED_MS)
    end
end)
return Client
