--[[
RST_PeerChecksRep - client steps of the reputation suite rs.reputation (E04-T14). Development mod only. Load with:
require "RST/RST_PeerChecksRep" (shared: the suite requires it, so every machine that loads the suite registers the
steps; the handlers read the notebook client of THIS machine).

Steps (RST.Steps.on; solo: the local player answers in the same Lua state)
    rep.read   { refresh = bool, wait = { level?, reasonKey? } }: the reputation of the notebook snapshot of this
               client (RS_CarnetClient.snapshot.reputation), after a 'snapshot' request when refresh is true, waited
               until it matches `wait` (or the client deadline). data { available, level, trend, reasons (count),
               reasonKey (newest act), reasonArg, changeTo, lines (Reputation tab, RS_UI_Notebook.reputationLines,
               translated and joined by " / "), digit (true when a digit is shown), warned (last warning text over
               the character, RS_UI_Notebook.reputationWarning) }.
    rep.admin  {}: the notebook command 'rep_admin' (administrator view, Q17), answer read from
               RS_CarnetClient.repAdmin: data { ok, err, count, names = "a, b", score (true when a field 'score' was
               received) }.
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerRep = RST.PeerRep or {}
local PRp = RST.PeerRep
local Steps = RST.Steps

local function carnet() return RS_CarnetClient end

local function reputationOf(C)
    local snap = C and C.snapshot or nil
    return type(snap) == "table" and snap.reputation or nil, snap
end

-- Reputation of the snapshot in plain values (sent back to the authority).
function PRp.describe(C)
    local rep, snap = reputationOf(C)
    local data = { available = false }
    if type(rep) ~= "table" then return data end
    data.available = rep.available == true
    data.level, data.trend = rep.level, rep.trend
    local reasons = type(rep.reasons) == "table" and rep.reasons or {}
    data.reasons = #reasons
    if reasons[1] then
        data.reasonKey = reasons[1].reasonKey
        data.reasonArg = type(reasons[1].reasonArgs) == "table" and reasons[1].reasonArgs[1] or nil
    end
    data.changeTo = type(rep.change) == "table" and rep.change.to or nil
    local N = RS_UI_Notebook
    if N ~= nil and type(N.reputationLines) == "function" then
        local lines = N.reputationLines(rep, snap.contacts)
        local text = table.concat(lines, " / ")
        data.lines = text
        data.digit = string.find(text, "%d") ~= nil
    end
    data.warned = C.repWarned
    return data
end

local function matches(data, wait)
    if type(wait) ~= "table" then return true end
    if wait.level ~= nil and data.level ~= wait.level then return false end
    if wait.reasonKey ~= nil and data.reasonKey ~= wait.reasonKey then return false end
    return true
end

Steps.on("rep.read", function(args)
    local C = carnet()
    if C == nil then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    if args.refresh == true then C.send("snapshot") end
    return function(ctx)
        local data = PRp.describe(C)
        if matches(data, args.wait) or ctx.final then
            return Steps.pass("reputation " .. tostring(data.level) .. " (" .. tostring(data.trend) .. "), "
                .. tostring(data.reasons) .. " act(s), newest " .. tostring(data.reasonKey), data)
        end
        return nil
    end
end)

Steps.on("rep.admin", function()
    local C = carnet()
    if C == nil then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    C.repAdmin = nil
    C.send("rep_admin")
    return function(ctx)
        local view = C.repAdmin
        if type(view) == "table" then
            local names, score = {}, false
            for _, c in ipairs(type(view.characters) == "table" and view.characters or {}) do
                names[#names + 1] = tostring(c.name)
                if c.score ~= nil then score = true end
            end
            return Steps.pass("admin view ok=" .. tostring(view.ok) .. ", " .. #names .. " character(s)",
                { ok = view.ok == true, err = view.err, count = #names, names = table.concat(names, ", "),
                    score = score })
        end
        if ctx.final then return Steps.fail("no rep_admin answer") end
        return nil
    end
end)

return PRp
