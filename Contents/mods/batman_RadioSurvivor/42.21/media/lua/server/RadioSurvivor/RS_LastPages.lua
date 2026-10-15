if isClient() then return end
--[[
Last pages of a dead notebook character (E15-T03). Authority only (dedicated server or solo). Design notes:
docs/conception/dernieres-pages.md; where the document goes: docs/derniers-pages-cadavre.md (E15-T02).

    local LastPages = require "RadioSurvivor/RS_LastPages"
    LastPages.poll()             -- one pass (answers of the bridge, delays, placement); OnTickEvenPaused every POLL_MS
    LastPages.fallbackText(log)  -- journal written by the server from the facts of a frozen life log
    LastPages.layout(text)       -- pages of the document (PAGES pages of LINES lines of WIDTH characters at most)

Death (LifeLog.onFrozen, called inside OnCharacterDeath, before the corpse exists): a token is written in the dead
player's modData (copied to the corpse, IsoDeadBody.java:378), the death square and "on fire" are noted in the frozen
log (private state RS_State, never global ModData), and ONE request kind=last_pages goes to the bridge
(RS_Transport.lastPages, hex RSV2 payload): character name, language, facts of the life log (hours, kills, profession
display name, towns, last radio phrases, closed missions, missions open at the death, rescues, totals). Never a
coordinate, a frequency, an account name or the token.
Text: the bridge answer {kind = last_pages_reply, text} (cleaned and bounded again here: MAX_TEXT characters, no
control character but line breaks, no < > [ ]), else, on an error answer, after TIMEOUT_MS (Const.BRIDGE_TIMEOUT_MS
while the bridge is seen alive, E17-T16), or after a restart that
lost the request, the fallback journal composed here from the same facts (translation keys IGUI_RS_LastPages_*,
English defaults when the mod translations are missing on the machine).
Document: vanilla Base.Notebook (CanBeWrite, 10 pages), pages written by addPage then locked by setLockedBy(LOCK):
every reader only gets "Read" (base quest-building-blocks.md "Document en lecture seule"); custom name "Last pages of
<name>"; modData RS_LastPagesToken. Placement, once the text is ready, DELAY_MS after the death and the death square
loaded here: in the corpse carrying the token within RADIUS squares (AddItem + sendAddItemToContainer on a server),
else on the ground of the death square (AddWorldInventoryItem(..., true)); always on the ground when the character
died on fire (the corpse burns with its content). Square not loaded: retried at every poll.
Once only: the frozen log is released (LifeLog.release) and the state saved BEFORE the document is placed; a crash in
between loses the document rather than doubling it. ASCII only in this file (Kahlua lexer).
Sandbox option RadioSurvivor.LastPages (E15-T04, on by default, Const.lastPages, read at every pass): off = no
request and no document. A death freezes no log (RS_LifeLog); the poll withdraws every pending request from the
bridge file and releases the frozen logs without placing anything, even a text already ready.
]]
local S = require "RadioSurvivor/RS_State"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Transport = require "RadioSurvivor/RS_Transport"
local LifeLog = require "RadioSurvivor/RS_LifeLog"

local P = {}
P.KIND = "last_pages"
P.REPLY_KIND = "last_pages_reply"
P.ITEM = "Base.Notebook"      -- literature.txt: CanBeWrite = true, PageToWrite = 10
P.PAGES = 10
P.LINES = 15                  -- ISUIWriteJournal: setMaxLines(15)
P.WIDTH = 40                  -- characters per line (350 px window): same guess as LK_Traces, to check in game
P.MAX_TEXT = 2400             -- characters of the bridge text kept (bridge: last_pages.MAX_TEXT_BYTES)
P.TIMEOUT_MS = 90000          -- no answer of a missing bridge by then: fallback journal (E17-T16: a bridge seen
                              -- alive is awaited Const.BRIDGE_TIMEOUT_MS, Const.waitMs)
P.DELAY_MS = 3000             -- placement not before (solo: the corpse may come a few updates after the event)
P.POLL_MS = 2000
P.RADIUS = 2
P.LOCK = "RadioSurvivor"      -- setLockedBy name: no reader carries it
P.TOKEN_KEY = "RS_LastPagesToken"
P.KEY = "IGUI_RS_LastPages_"

-- English texts used when the mod translations are missing on this machine (getTextOrNull nil after a reload).
P.DEFAULTS = {
    Item = "Last pages of %1",
    Title = "The last pages of %1",
    Days = "I have held on for %1 days and %2 hours since it all began.",
    Kills = "I have put down %1 of the dead.",
    KillsNone = "I have not had to kill any of them.",
    Job = "Before all this, I was: %1.",
    Towns = "I went through %1.",
    TownsNone = "I never got far from where I started.",
    Missions = "I took on jobs for other survivors: %1 done, %2 failed, %3 dropped.",
    Open = "I never finished what I promised to %1.",
    OpenNoName = "I never finished one last job.",
    Rescues = "I saved %1 people, and could not save %2.",
    Radio = "My last words on the radio:",
    End = "Whoever finds this: these were my last pages.",
}

local pending = {}     -- cid -> request table in Transport.lastPages (lost at a restart: fallback then)
local pollAt = 0
local reloaded = false

function P.resetForTests()
    pending, pollAt, reloaded = {}, 0, false
    Transport.lastPages = {}
end

-- Mod translations on this machine (an MP server does not load them: Translator.loadFiles once, base api-42-21.md).
local function hasText()
    return getTextOrNull ~= nil and getTextOrNull(P.KEY .. "Title", "x") ~= nil
end

local function translated()
    if hasText() then return true end
    if not reloaded and isServer() and Translator ~= nil and Translator.loadFiles ~= nil then
        reloaded = true
        Translator.loadFiles()
        Const.log("last pages: mod translations reloaded on the server")
    end
    return hasText()
end

local function text(key, a, b, c)
    local t = translated() and getTextOrNull(P.KEY .. key, a, b, c) or nil
    if t ~= nil then return t end
    local args = { a, b, c }
    return (string.gsub(P.DEFAULTS[key], "%%(%d)", function(d) return tostring(args[tonumber(d)] or "") end))
end

local function clean(value, limit)
    if type(value) ~= "string" then return "" end
    value = Const.oneLine(string.gsub(value, "[%c<>%[%]]", " "))
    if limit and string.len(value) > limit then value = Const.oneLine(string.sub(value, 1, limit)) end
    return value
end

-- Text of the bridge: line breaks kept, other controls and < > [ ] removed, MAX_TEXT characters at most (cut at the
-- last space); nil when nothing is left.
function P.cleanText(value)
    if type(value) ~= "string" then return nil end
    value = string.gsub(value, "\r", "")
    value = string.gsub(value, "[\1-\9\11-\31\127<>%[%]]", " ")
    if string.len(value) > P.MAX_TEXT then
        value = string.sub(value, 1, P.MAX_TEXT)
        local cut = string.find(value, "%s[^%s]*$")
        if cut and cut > P.MAX_TEXT / 2 then value = string.sub(value, 1, cut - 1) end
        value = value .. "..."
    end
    if not string.find(value, "%S") then return nil end
    return value
end

local function language()
    local code = Const.callLanguage()
    if code == nil then
        local l = Translator and Translator.getLanguage and Translator.getLanguage()
        code = l and tostring(l:name()) or "EN"
    end
    if not string.match(code, "^[A-Z][A-Z_]+$") or string.len(code) > 8 then code = "EN" end
    return code
end

-- Display name of the dead character's profession (vanilla ISCharacterScreen.loadProfession), else its id.
local function professionName(character, log)
    local d = character:getDescriptor()
    local prof = d and d:getCharacterProfession() or nil
    local name
    if prof ~= nil and CharacterProfessionDefinition ~= nil then
        local def = CharacterProfessionDefinition.getCharacterProfessionDefinition(prof)
        name = def and def:getUIName() or nil
    end
    if type(name) ~= "string" or name == "" then name = log.profession end
    return clean(name, 80)
end

local function list(src, f)
    local out = {}
    for _, v in ipairs(src or {}) do out[#out + 1] = f(v) end
    return out
end

local function mission(m)
    return { template = tostring(m.template or ""), result = tostring(m.result or ""),
        requester = tostring(m.requester or ""), place = tostring(m.place or "") }
end

-- Facts sent to the bridge: no coordinate, frequency, account name or token.
function P.facts(log)
    local pg = log.pages or {}
    local t = log.totals or {}
    return {
        hours = tonumber(log.hours) or 0, kills = tonumber(log.kills) or 0,
        profession = pg.profession or log.profession or "", death = tostring(log.deathWhen or ""),
        towns = list(log.towns, function(v) return tostring(v.name) end),
        phrases = list(log.phrases, function(v) return tostring(v.text) end),
        missions = list(log.missions, mission), open = list(log.open, mission),
        rescues = list(log.rescues, function(v) return { outcome = v.outcome, label = tostring(v.label or "") } end),
        totals = { success = t.success or 0, failed = t.failed or 0, cancelled = t.cancelled or 0,
            saved = t.saved or 0, missed = t.missed or 0 },
    }
end

-- Journal written by the server from the facts only (no bridge, error, delay over).
function P.fallbackText(log)
    local pg = log.pages or {}
    local paras = {}
    local hours = math.floor(tonumber(log.hours) or 0)
    paras[#paras + 1] = text("Days", tostring(math.floor(hours / 24)), tostring(hours - math.floor(hours / 24) * 24))
    local job = pg.profession or log.profession or ""
    if job ~= "" then paras[#paras + 1] = text("Job", job) end
    local kills = math.floor(tonumber(log.kills) or 0)
    paras[#paras + 1] = kills > 0 and text("Kills", tostring(kills)) or text("KillsNone")
    local towns = list(log.towns, function(v) return tostring(v.name) end)
    paras[#paras + 1] = #towns > 0 and text("Towns", table.concat(towns, ", ")) or text("TownsNone")
    local t = log.totals or {}
    if (t.success or 0) + (t.failed or 0) + (t.cancelled or 0) > 0 then
        paras[#paras + 1] = text("Missions", tostring(t.success or 0), tostring(t.failed or 0),
            tostring(t.cancelled or 0))
    end
    for _, m in ipairs(log.open or {}) do
        paras[#paras + 1] = (m.requester and m.requester ~= "") and text("Open", m.requester) or text("OpenNoName")
    end
    if (t.saved or 0) + (t.missed or 0) > 0 then
        paras[#paras + 1] = text("Rescues", tostring(t.saved or 0), tostring(t.missed or 0))
    end
    if log.phrases and #log.phrases > 0 then
        local lines = { text("Radio") }
        for _, p in ipairs(log.phrases) do lines[#lines + 1] = "- " .. tostring(p.text) end
        paras[#paras + 1] = table.concat(lines, "\n")
    end
    paras[#paras + 1] = text("End")
    return table.concat(paras, "\n\n")
end

-- Display lines of a text: wrapped at spaces, WIDTH characters at most (a longer word keeps its line); every "\n"
-- starts a line.
local function wrap(value)
    local out = {}
    for para in string.gmatch(tostring(value) .. "\n", "([^\n]*)\n") do
        local line = ""
        for word in string.gmatch(para, "%S+") do
            if line == "" then line = word
            elseif string.len(line) + 1 + string.len(word) <= P.WIDTH then line = line .. " " .. word
            else
                out[#out + 1] = line
                line = word
            end
        end
        out[#out + 1] = line
    end
    return out
end

-- Pages (texts) of the document: at most PAGES pages of LINES lines; what does not fit is cut, "..." on the last line.
function P.layout(value)
    local lines = wrap(value)
    local max = P.PAGES * P.LINES
    if #lines > max then
        for i = #lines, max + 1, -1 do lines[i] = nil end
        lines[max] = lines[max] .. " ..."
    end
    local pages, cur = {}, {}
    for _, l in ipairs(lines) do
        if #cur >= P.LINES then
            pages[#pages + 1] = table.concat(cur, "\n")
            cur = {}
        end
        cur[#cur + 1] = l
    end
    if #cur > 0 then pages[#pages + 1] = table.concat(cur, "\n") end
    return pages
end

function P.newDocument(log)
    local item = instanceItem(P.ITEM)
    if item == nil or not instanceof(item, "Literature") then return nil end
    local pages = P.layout(text("Title", log.name) .. "\n\n" .. tostring(log.pages.text))
    for i, page in ipairs(pages) do item:addPage(i, page) end
    item:setLockedBy(P.LOCK)
    item:setName(text("Item", log.name))
    item:setCustomName(true)
    item:getModData()[P.TOKEN_KEY] = log.pages.token
    return item
end

local function dropRequest(cid)
    local req = pending[cid]
    if req == nil then return end
    pending[cid] = nil
    for i = #Transport.lastPages, 1, -1 do
        if Transport.lastPages[i] == req then table.remove(Transport.lastPages, i) end
    end
    Transport.write()
end

-- LifeLog.onFrozen: inside OnCharacterDeath, before the corpse exists.
function P.onFrozen(cid, log, character)
    if type(log) ~= "table" or log.pages ~= nil or not instanceof(character, "IsoPlayer") then return end
    if not Const.lastPages() then return end
    local now = getTimestampMs()
    local token = "lp-" .. tostring(log.deathSeq or 0) .. "-" .. string.format("%.0f", now)
    character:getModData()[P.TOKEN_KEY] = token
    log.pages = { state = "asked", token = token, x = math.floor(character:getX()), y = math.floor(character:getY()),
        z = math.floor(character:getZ()), fire = character:isOnFire() and true or false, dead = now, asked = now,
        profession = professionName(character, log) }
    local req = { id = string.format("%.0f", now) .. "-" .. tostring(ZombRand(100000, 999999)) .. "-pages",
        kind = P.KIND, sent = now, language = language(), name = log.name, facts = P.facts(log) }
    log.pages.req = req.id
    pending[cid] = req
    Transport.lastPages[#Transport.lastPages + 1] = req
    if not Transport.write() then Const.log("last pages: request file not written, fallback after the delay") end
    S.dirty = true
    S.save()
end

-- Answers of the bridge by request id (RS_Transport.readNpc), read once per poll.
local function answerOf(answers, pg)
    local a = answers and answers[pg.req]
    if type(a) ~= "table" or a.kind ~= P.REPLY_KIND then return nil end
    return a
end

local function finish(cid, log, value)
    dropRequest(cid)
    local pg = log.pages
    pg.source = value and "bridge" or "fallback"
    pg.text = value or P.fallbackText(log)
    pg.state = "ready"
    S.dirty = true
    Const.log("last pages: text of " .. cid .. " ready (" .. pg.source .. ")")
end

-- Corpse within RADIUS of the death square whose modData carries the token, or nil.
local function corpseOf(pg)
    for dy = -P.RADIUS, P.RADIUS do
        for dx = -P.RADIUS, P.RADIUS do
            local sq = getCell():getGridSquare(pg.x + dx, pg.y + dy, pg.z)
            local objects = sq and sq:getStaticMovingObjects() or nil
            for i = 0, (objects and objects:size() or 0) - 1 do
                local o = objects:get(i)
                if instanceof(o, "IsoDeadBody") and o:getModData()[P.TOKEN_KEY] == pg.token
                        and o:getContainer() ~= nil then
                    return o
                end
            end
        end
    end
    return nil
end

local function place(cid, log, now)
    local pg = log.pages
    if now < (pg.dead or 0) + P.DELAY_MS then return false end
    local sq = getCell():getGridSquare(pg.x, pg.y, pg.z)
    if sq == nil then return false end
    local body = not pg.fire and corpseOf(pg) or nil
    local item = P.newDocument(log)
    -- Released and saved first: never two documents for one death.
    LifeLog.release(cid)
    S.save()
    if item == nil then
        Const.log("last pages: no writable " .. P.ITEM .. " here, nothing placed for " .. cid)
        return false
    end
    if body ~= nil then
        local container = body:getContainer()
        container:AddItem(item)
        if isServer() then sendAddItemToContainer(container, item) end
    else
        sq:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
    end
    Const.log("last pages: document of " .. cid .. " placed " .. (body and "in the corpse" or "on the ground")
        .. " (" .. pg.source .. ")")
    return true
end

-- Option RadioSurvivor.LastPages off: pending requests withdrawn, frozen logs released, nothing placed.
local function cancelAll()
    local n = 0
    local cids = {}
    for cid in pairs(pending) do cids[#cids + 1] = cid end
    for _, cid in ipairs(cids) do dropRequest(cid) end
    for _, cid in ipairs(LifeLog.frozen()) do
        if LifeLog.release(cid) then n = n + 1 end
    end
    if n > 0 or #cids > 0 then
        Const.log("last pages: option LastPages off, " .. n .. " death(s) dropped without a document")
    end
end

function P.poll()
    if not Const.lastPages() then return cancelAll() end
    local now = getTimestampMs()
    local answers, read = nil, false
    for _, cid in ipairs(LifeLog.frozen()) do
        local log = LifeLog.get(cid)
        local pg = log and log.pages
        if type(pg) == "table" and pg.state == "asked" then
            if not read then answers, read = Transport.readNpc(), true end
            local a = answerOf(answers, pg)
            if a ~= nil then
                finish(cid, log, P.cleanText(a.text))
            elseif pending[cid] == nil or now >= (pg.asked or 0) + Const.waitMs(P.TIMEOUT_MS, now) then
                finish(cid, log, nil)
            end
        end
        if type(pg) == "table" and pg.state == "ready" then place(cid, log, now) end
    end
end

function P.tick()
    local now = getTimestampMs()
    if now < pollAt then return end
    pollAt = now + P.POLL_MS
    P.poll()
end

local previous = LifeLog.onFrozen
LifeLog.onFrozen = function(cid, log, character)
    if previous then previous(cid, log, character) end
    P.onFrozen(cid, log, character)
end
Events.OnTickEvenPaused.Add(P.tick)

return P
