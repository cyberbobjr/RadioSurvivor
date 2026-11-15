--[[
RST_PeerChecksVoices - client steps of the suite rs.notebook.voices (E06-T07: voice and listening hours of a known
frequency in the Radio tab of the notebook), asked by the authority through RST.Steps (E01-T16). Development mod only.
Load with: require "RST/RST_PeerChecksVoices" (shared: the suite that asks these steps requires it, so every client that
loads the suites has the handlers). No side effect at load time besides the handlers.

Client handlers (RST.Steps.on)
    rs.voice.read  { itemId, waitMs }: sends the REAL radio command "note_read" (module RadioSurvivor), the one the note
                   reader sends when a frequency note opens (RS_NotesReader), and waits for the history line the server
                   adds for it (history_add): PASS with data { added = true }; nothing within waitMs: FAIL (refused).
    rs.voice.tab   { khz, page }: reads the client copy of the radio history (RS_RadioHistory, the data of the Radio
                   tab; ask "rs.history" first to have it re-read from the server) and returns data { row (frequency
                   in the tab), voice (id of the known voice or nil), name (History.voiceName), hours
                   (History.hoursText: "19:00-22:00", nil = at any hour), second (second line of the frequency row,
                   RS_NotebookRadio.secondLine), lines = { "kind:text", ... }, page }. With page = true and the frequency
                   in the tab, the real notebook window is opened on the Radio tab, the frequency selected, the text of
                   its page read (page), then the window is put back as it was (tab, hidden if it was).
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_PeerChecksRadio"

RST.PeerVoices = RST.PeerVoices or {}
local PV = RST.PeerVoices
local PR = RST.PeerRadio
local Steps = RST.Steps

PV.READ_MS = 8000
PV.TAB = "Radio"

local ADDED = { history_add = true }

local function historyModule()
    local ok, H = pcall(require, "RadioSurvivor/RS_RadioHistory")
    if ok and type(H) == "table" then return H end
    return nil
end

local function rowOf(H, khz)
    for _, row in ipairs(H.sorted()) do
        if row.khz == khz then return row end
    end
    return nil
end

-- Text of the Radio page of khz in the real notebook window; the window is left as it was found.
function PV.pageText(khz)
    local ok, Notebook = pcall(require, "CoreAI/CA_Notebook")
    if not ok or type(Notebook) ~= "table" or type(Notebook.toggle) ~= "function" then return nil, "no notebook" end
    local w = Notebook.window
    local wasOpen = w ~= nil and w:isVisible()
    local oldTab = w ~= nil and w.tab or nil
    if not wasOpen then w = Notebook.toggle(0, false) end
    w:changeTab(PV.TAB)
    w.selectedId = khz
    w:refresh()
    local text = w.row ~= nil and w.row.khz == khz and w.detail.text or nil
    if oldTab ~= nil and oldTab ~= PV.TAB then w:changeTab(oldTab) end
    if not wasOpen then Notebook.toggle(0, false) end
    if text == nil then return nil, "frequency " .. tostring(khz) .. " not selectable in the Radio tab" end
    return text
end

Steps.on("rs.voice.read", function(args)
    PR.tapSolo()
    local p = getPlayer()
    if p == nil then return Steps.fail("no local player") end
    local id = tonumber(args.itemId)
    if id == nil then return Steps.fail("refused: note_read without itemId") end
    local mark = PR.seq
    sendClientCommand(p, PR.RADIO_MODULE, "note_read", { itemId = id })
    local waitMs, started = tonumber(args.waitMs) or PV.READ_MS, RST.now()
    return function(ctx)
        if PR.since(mark, PR.RADIO_MODULE, ADDED)[1] ~= nil then
            return Steps.pass("note " .. tostring(id) .. " read: history line added", { added = true })
        end
        if ctx.final or RST.now() - started >= waitMs then
            return Steps.fail("no history line within " .. waitMs .. " ms after note_read of item " .. tostring(id))
        end
        return nil
    end
end)

Steps.on("rs.voice.tab", function(args)
    local H = historyModule()
    if H == nil then return Steps.fail("RadioSurvivor/RS_RadioHistory not loaded on this client") end
    local khz = tonumber(args.khz)
    local row = khz and rowOf(H, khz) or nil
    if row == nil then return Steps.pass("frequency " .. tostring(khz) .. " not in the Radio tab", { row = false }) end
    local lines = {}
    for _, l in ipairs(H.lines(khz)) do lines[#lines + 1] = tostring(l.kind) .. ":" .. tostring(l.text) end
    local data = { row = true, lines = lines, voice = type(row.voice) == "table" and row.voice.id or nil,
        name = H.voiceName(row.voice), hours = H.hoursText(row.voice) }
    if RS_NotebookRadio ~= nil and type(RS_NotebookRadio.secondLine) == "function" then
        data.second = RS_NotebookRadio.secondLine(row)
    end
    if args.page then
        local page, why = PV.pageText(khz)
        if page == nil then return Steps.fail("Radio page not read: " .. tostring(why), data) end
        data.page = page
    end
    return Steps.pass("frequency " .. tostring(khz) .. ": voice " .. tostring(data.voice) .. ", hours "
        .. tostring(data.hours), data)
end)

return PV
