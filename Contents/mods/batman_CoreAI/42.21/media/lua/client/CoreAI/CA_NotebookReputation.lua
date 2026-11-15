--[[
CoreAI: Reputation tab of the notebook (E21-T03, moved from CA_Notebook). Client only,
presentation only.

Page: the reputation of the reader's character (CA_Reputation.projection carried by the snapshot of the notebook
server): level, trend, last change of level, last acts with their game day; no number is shown (days become words).
The text of an act belongs to the mod that knows it (Notebook.reputationReasons[action] = translation key; an act of a
mod not active reads "a good / bad deed"). Then the lines the mods add (Notebook.reputationExtras: fn(snapshot) ->
lines, in registration order). Administrators (solo debug, MP capability PopmanManage; checked again by the server)
read every character's reputation (command rep_admin). A warning over the character when the level changes.
Notebook.reputationLines(rep) is shared with the page of Living Knox alone (CA_NotebookJournal).
Texts: IGUI_CA_*.
]]
local Notebook = require 'CoreAI/CA_Notebook'
local Client = require 'CoreAI/CA_NotebookClient'

local Reputation = CoreAI.notebookReputation or {}
CoreAI.notebookReputation = Reputation
if Reputation.installed then return Reputation end
Reputation.installed = true

local UI = Notebook.ui
local stamp, clean = UI.stamp, UI.clean
local function tr(key, ...) return getText('IGUI_CA_' .. key, ...) end

local REP_LEVELS = {bad = true, neutral = true, good = true}
local TRENDS = {up = true, down = true, stable = true}

-- When a fact happened, in words (no number): today, yesterday, this week, earlier.
local function when(today, day)
    local ago = (type(today) == 'number' and type(day) == 'number') and today - day or nil
    if ago == nil then return tr('RelWhen_earlier') end
    if ago <= 0 then return tr('RelWhen_today') end
    if ago == 1 then return tr('RelWhen_yesterday') end
    if ago < 7 then return tr('RelWhen_week') end
    return tr('RelWhen_earlier')
end
local function repLevel(level) return tr('RepLevel_' .. (REP_LEVELS[level] and level or 'neutral')) end
local function repTrend(trend) return tr('RepTrend_' .. (TRENDS[trend] and trend or 'stable')) end
-- One act: its translated text (public argument: a name), or a generic word for an act of a mod not active.
local function repReason(r)
    local key = type(r.action) == 'string' and Notebook.reputationReasons[r.action] or nil
    local args = type(r.reasonArgs) == 'table' and r.reasonArgs or {}
    local name = clean(args[1] or '') -- one value: gsub also returns a count
    local text = key and getTextOrNull(key, name)
    if text then return text end
    return tr(r.sign == 1 and 'RepReason_good' or 'RepReason_bad')
end
Notebook.rep = {when = when, level = repLevel, trend = repTrend, reason = repReason, LEVELS = REP_LEVELS,
    TRENDS = TRENDS}

function Notebook.reputationLines(rep)
    local out = {tr('GlobalReputation')}
    if type(rep) ~= 'table' or rep.available ~= true then
        out[#out + 1] = tr('ReputationUnavailable')
        return out
    end
    out[#out + 1] = tr('RepLevelLine', repLevel(rep.level)); out[#out + 1] = tr('RepTrendLine', repTrend(rep.trend))
    local change = type(rep.change) == 'table' and rep.change or nil
    if change and REP_LEVELS[change.from] and REP_LEVELS[change.to] then
        out[#out + 1] = tr('RepChanged', when(rep.today, change.day), repLevel(change.from), repLevel(change.to))
    end
    local reasons = type(rep.reasons) == 'table' and rep.reasons or {}
    if #reasons == 0 then out[#out + 1] = tr('RepNoActs')
    else
        out[#out + 1] = tr('RepLastActs')
        for _, r in ipairs(reasons) do
            local text = tr('RepAct', when(rep.today, r.day), repReason(r))
            if r.capped then text = text .. ' ' .. tr('RepCapped') end
            out[#out + 1] = '- ' .. text
        end
    end
    return out
end

-- Reputation of the snapshot, then the lines of the mods (Notebook.reputationExtras).
function Reputation.lines(snapshot)
    snapshot = type(snapshot) == 'table' and snapshot or {}
    local out = Notebook.reputationLines(snapshot.reputation)
    for _, extra in ipairs(Notebook.reputationExtras) do
        for _, s in ipairs(extra(snapshot) or {}) do out[#out + 1] = s end
    end
    return out
end

-- Administrator view (Q17), answer of the server to 'rep_admin': one line per live character and its last acts;
-- nothing before the first answer; a refusal says so.
function Reputation.adminLines(view)
    if type(view) ~= 'table' then return {} end
    if view.ok ~= true then return {tr('RepAdminDenied')} end
    local out = {tr('RepAdminTitle')}
    for _, c in ipairs(type(view.characters) == 'table' and view.characters or {}) do
        out[#out + 1] = tr('RepAdminLine', clean(c.name), repLevel(c.level), repTrend(c.trend))
        for _, r in ipairs(type(c.reasons) == 'table' and c.reasons or {}) do
            out[#out + 1] = '   - ' .. tr('RepAct', when(view.today, r.day), repReason(r))
        end
    end
    return out
end

-- Administrator button of the Reputation tab (display only: the server checks the right at each request). Solo: debug
-- mode; MP: role capability PopmanManage (same rule as the frequency and Living Knox debug tools).
function Reputation.canSeeAll()
    if not isClient() then return type(isDebugEnabled) == 'function' and isDebugEnabled() == true end
    local p = getSpecificPlayer(0)
    local cap = Capability ~= nil and Capability.PopmanManage or nil
    local role = p and cap and p:getRole() or nil
    return role ~= nil and role:hasCapability(cap) == true
end

-- E04-T04 (Q9): warning over the character when the level of its reputation changes, once per change (key n of the
-- server change). The first snapshot after loading or a new character only sets the reference: no warning for a
-- change made before. Text 'Reputation: good'; the Reputation tab keeps the line of the last change.
function Reputation.warning(rep)
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

-- A new character forgets the reference of the warning and the administrator view.
Client.listen('identity', function(args)
    if args.character ~= Client.repCharacter then Client.repChangeSeen, Client.repAdmin = nil, nil end
    Client.repCharacter = args.character
end)
Client.listen('snapshot', function(args)
    if Client.snapshot == args then Reputation.warning(args.reputation) end
end)
Client.registerCommand('rep_admin', function(args)
    Client.repAdmin = args
    if Client.window then Client.window:refresh() end
end)

Reputation.page = {
    create = function(w)
        -- E04-T14 (Q17): read-only view of every character's reputation, administrators only (checked by the server).
        w.repAdmin = w:addAction(stamp(w, tr('RepAdminButton'), function() Client.send('rep_admin') end))
    end,
    detail = function(w, _, line)
        for _, s in ipairs(Reputation.lines(Client.snapshot)) do line(s) end
        if Reputation.canSeeAll() then
            w.repAdmin:setVisible(true)
            for _, s in ipairs(Reputation.adminLines(Client.repAdmin)) do line(s) end
        end
        return false
    end,
}
Notebook.registerTab({name = 'Reputation', order = 40, color = {0.31, 0.369, 0.478}, showList = false,
    create = Reputation.page.create, detail = Reputation.page.detail})

return Reputation
