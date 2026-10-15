if RS_CarnetClient then return RS_CarnetClient end
local C = require 'RadioSurvivor/RS_Config'
local P = require 'RadioSurvivor/RS_NPCProvider'
local Client = {snapshot = {contacts = {}, missions = {}, inviteTargets = {}, events = {}}, seen = {}, seenOrder = {}, inbox = {}}
RS_CarnetClient = Client
local wrappedChat, wrappedSay = false, false
local nextSync = 0
local function pack(...) return {n = select('#', ...), ...} end

function Client.send(command, args)
    local player = getSpecificPlayer(0)
    if not player then return end
    args = args or {}
    args.world, args.run = Client.world, Client.run
    sendClientCommand(player, C.MODULE, command, args)
end

function Client.hello()
    local p = getSpecificPlayer(0)
    if p then Client.send('hello', {v = C.VERSION, character = p:getModData().RS_CarnetCharacter}) end -- never empty
end

-- Speech to the selected NPC (E17-T06): ONE path for the local "say" chat (MP only, captured by the ISChat wrapper
-- below) and the Say line of the notebook Contacts tab (solo and MP, no chat in solo). Both send the same 'talk'
-- command; the server applies the same checks to both (selection, range, chat rules, delay, budget) and builds the
-- same npc_talk request. The client only greys the notebook line while an answer is awaited or too soon after a
-- sentence (the server decides anyway).
Client.TALK_WAIT_MS = C.REQUEST_TIMEOUT_MS + 5000
-- Server rejections that end the wait of a sentence (RS_Carnet_Server talk and poll).
local TALK_ERRORS = {Range = true, Text = true, Chat = true, Cooldown = true, Busy = true, Bridge = true, NoAnswer = true,
    Storage = true, Session = true, Identity = true}

-- E17-T11: the real game language code (ES, PTBR, ES_CL...), checked by its form; the server checks it again.
local function language()
    local lang = Translator.getLanguage()
    return C.languageCode(lang and lang:name())
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

-- Sends one sentence to the selected NPC. spoken: the notebook line (said aloud after the server queued it).
function Client.talk(text, spoken)
    text = tostring(text or ''):match('^%s*(.-)%s*$')
    if text == '' then return false end
    local now = getTimestampMs()
    -- Set before sending: in solo the command is queued and handled at the next update, which may answer at once.
    Client.waiting = {at = now, npc = Client.snapshot.selected, text = spoken and text or nil}
    Client.lastTalkAt = now
    Client.send('talk', {text = text, channel = 'say', language = language()})
    return true
end

-- Why the notebook cannot speak to this contact now (IGUI_RS_<key>, problem flag), or nil.
function Client.talkProblem(row)
    if not row then return 'TalkSelectFirst', false end
    if not row.alive then return 'TalkDead', true end
    if Client.snapshot.selected ~= row.id then return 'TalkSelectFirst', false end
    if not row.near then return 'TalkOutOfRange', true end
    if Client.isWaiting() then return 'TalkWaiting', false end
    if Client.lastTalkAt and getTimestampMs() - Client.lastTalkAt < C.COOLDOWN_MS then return 'Error_Cooldown', false end
    return nil
end

-- Shows an NPC answer: speech bubble over the body at once, and local chat line (MP, once the say chat is known).
-- Solo has no chat (E17-T06): bubble only, the answer is also kept in the notebook history. E17-T14: the bubble never
-- waits for the say chat, which is discovered only by a chat message (OnAddMessage) and may stay unknown; MP without
-- a known say chat yet: only the chat line is kept in the inbox (false), the bubble is not shown twice.
local function inject(args)
    if not args.bubbled then
        args.bubbled = true
        P.bubble(P.objects()[args.incarnation], args.text, C.HEARING_RANGE)
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
            if inEntry and admitted and Client.snapshot.selected and Client.snapshot.selected ~= '' then
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
            if submitted then Client.talk(submitted, false) end
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
        if P.near(player, npc, C.SELECT_RANGE) then
            local dx, dy = npc:getX() - player:getX(), npc:getY() - player:getY()
            local d = dx * dx + dy * dy
            if not distance or d < distance then nearest, distance = id, d end
        end
    end
    if nearest then Client.send('select', {incarnation = nearest})
    else Client.send('deselect'); HaloTextHelper.addBadText(player, getText('IGUI_RS_Error_Range')) end
end

function Client.receive(command, args)
    local p = getSpecificPlayer(0)
    if command == 'identity' then
        if Client.world ~= args.world or Client.run ~= args.run or Client.character ~= args.character then
            Client.snapshot = {contacts = {}, missions = {}, inviteTargets = {}, events = {}}
            Client.inbox, Client.seen, Client.seenOrder = {}, {}, {}
        end
        Client.character, Client.world, Client.run = args.character, args.world, args.run
        if p then p:getModData().RS_CarnetCharacter = args.character end
    elseif command == 'snapshot' then
        if args.world ~= Client.world or args.run ~= Client.run then return end
        local previous = Client.snapshot.selected
        Client.snapshot = args
        if args.selected and args.selected ~= '' and previous ~= args.selected and p then
            for _, npc in ipairs(args.contacts or {}) do
                if npc.id == args.selected then HaloTextHelper.addGoodText(p, npc.name); break end
            end
        end
        -- E11-T10: approximate areas of the active scout missions drawn on (or removed from) the world map.
        local MapActions = require 'RadioSurvivor/RS_MapActions'
        if type(MapActions) == 'table' then MapActions.zones(args.missions) end
        if Client.window then Client.window:refresh() end
    elseif command == 'error' then
        if p then HaloTextHelper.addBadText(p, getText('IGUI_RS_Error_' .. tostring(args.reason))) end
        Client.lastError = args.reason
        if TALK_ERRORS[args.reason] then Client.waiting = nil end
        if args.reason == 'Session' or args.reason == 'Identity' then Client.world, Client.run = nil, nil; Client.hello() end
        if Client.window then Client.window:refresh() end
    elseif command == 'speech' then
        if args.world ~= Client.world or args.run ~= Client.run then return end
        if type(args.id) ~= 'string' or Client.seen[args.id] then return end
        -- The answer of the awaited NPC ends the wait of the Say line. E08-T05: only the answer to this character's own
        -- sentence (request id given by 'queued'), not another player's intervention answered by the same NPC.
        local w = Client.waiting
        if w and w.npc == args.npc and (not w.id or w.id == args.id) then Client.waiting = nil end
        Client.seen[args.id] = true
        Client.seenOrder[#Client.seenOrder + 1] = args.id
        if #Client.seenOrder > 256 then Client.seen[table.remove(Client.seenOrder, 1)] = nil end
        if not inject(args) then
            Client.inbox[#Client.inbox + 1] = args
            if #Client.inbox > 40 then table.remove(Client.inbox, 1) end
        end
    elseif command == 'queued' then
        -- Sentence admitted by the server (talk): a notebook sentence is said aloud now, once.
        local w = Client.waiting
        if w then
            -- E08-T05: the request id of every admitted sentence (chat or notebook line) identifies its answer.
            local text = w.text
            w.text, w.id = nil, args.id
            if text then speakAloud(text) end
        end
        if Client.window then Client.window:refresh() end
    elseif command == 'offer' then
        -- E17-T09: new mission offer made to this character: one message on screen per offer.
        if args.world ~= Client.world or args.run ~= Client.run or type(args.mission) ~= 'string' then return end
        Client.offersShown = Client.offersShown or {}
        if Client.offersShown[args.mission] then return end
        Client.offersShown[args.mission] = true
        if p then HaloTextHelper.addGoodText(p, getText('IGUI_RS_NewOffer')) end
    elseif command == 'agreement' then
        -- E09-T05: agreement of this player's team with a group, announced by the server once applied (its members
        -- stopped aiming at the team), once per agreement revision.
        if args.world ~= Client.world or args.run ~= Client.run or type(args.id) ~= 'string'
                or (args.kind ~= 'truce' and args.kind ~= 'alliance') then return end
        local key = args.id .. '#' .. tostring(args.revision)
        Client.agreementsShown = Client.agreementsShown or {}
        if Client.agreementsShown[key] then return end
        Client.agreementsShown[key] = true
        local name = type(args.groupName) == 'string' and args.groupName or ''
        if p then
            if name ~= '' then HaloTextHelper.addGoodText(p, getText('IGUI_RS_Agreement_' .. args.kind, name))
            else HaloTextHelper.addGoodText(p, getText('IGUI_RS_AgreementUnnamed_' .. args.kind)) end
        end
    elseif command == 'incident' then
        -- E09-T06: decision of a group leader on an incident of this player's team (maintain, repair, break), once.
        if args.world ~= Client.world or args.run ~= Client.run or type(args.id) ~= 'string'
                or (args.decision ~= 'maintain' and args.decision ~= 'repair' and args.decision ~= 'break') then return end
        Client.incidentsShown = Client.incidentsShown or {}
        if Client.incidentsShown[args.id] then return end
        Client.incidentsShown[args.id] = true
        local name = type(args.groupName) == 'string' and args.groupName or ''
        if name == '' then name = getText('IGUI_RS_IncidentGroup') end
        if p then
            local text
            if args.decision == 'repair' and type(args.category) == 'string' and args.category:match('^%a+$') then
                text = getText('IGUI_RS_Incident_repair', name, getText('IGUI_RS_RepairCategory_' .. args.category))
            elseif args.decision ~= 'repair' then
                text = getText('IGUI_RS_Incident_' .. args.decision, name)
            else return end
            if args.decision == 'break' then HaloTextHelper.addBadText(p, text)
            else HaloTextHelper.addGoodText(p, text) end
        end
    elseif command == 'quote' then
        if args.world ~= Client.world or args.run ~= Client.run then return end
        if Client.confirmQuote then Client.confirmQuote(args) end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == C.MODULE then Client.receive(command, args or {}) end
end)
Events.OnAddMessage.Add(Client.observeMessage)
Events.OnGameStart.Add(function() Client.installChat(); Client.hello() end)
Events.OnCreatePlayer.Add(function(num) if num == 0 then Client.hello() end end)
Events.OnTick.Add(function()
    Client.installChat()
    drain()
    local now = getTimestampMs()
    if now >= nextSync and getSpecificPlayer(0) then
        if Client.world then Client.send('snapshot') else Client.hello() end
        -- The server pushes changes; polling only refreshes ranges and timers of an open notebook.
        local open = Client.window and Client.window:isVisible()
        nextSync = now + (open and C.SNAPSHOT_OPEN_MS or C.SNAPSHOT_CLOSED_MS)
    end
end)
return Client
