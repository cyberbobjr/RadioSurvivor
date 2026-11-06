--[[
Living Knox's part of the notebook of the core mod (RadioSurvivorCore/RC_Notebook). Client only, presentation only.

- E18-T25: the text of the acts of the reputation that Living Knox reports (LK_Reputation: a member of a group killed).
- E18-T26: the relation panel of one of its NPCs toward the reader's character (LK_PersonalRelation.panel, kept by
  Living Knox since E18-T21): the server sends identifiers and game days only, every word is translated here
  (IGUI_LK_Rel*); an unknown identifier (newer server) falls back to a generic word, never a raw key. Used by the
  Contacts page of a Living Knox NPC (Notebook.contactPages.lk) and by RadioSurvivor's notebook pages
  (Notebook.relationLines, Notebook.relationLevel).
]]
local Notebook = require 'RadioSurvivorCore/RC_Notebook'

Notebook.reputationReasons['npc.memberKilled'] = 'IGUI_LK_RepReason_MemberKilled'

local function tr(key, ...) return getText('IGUI_LK_' .. key, ...) end

local REL_LEVELS = {hostile = true, wary = true, cautious = true, favorable = true, trusting = true}
local REL_TRENDS = {up = true, down = true, stable = true}
local REL_NATURES = {good = true, bad = true, neutral = true}
local function relWord(prefix, id, fallback)
    return getTextOrNull('IGUI_LK_' .. prefix .. tostring(id)) or getText('IGUI_LK_' .. prefix .. fallback)
end

-- Title of the relation section of a contact page.
function Notebook.relationTitle() return tr('RelTitle') end

-- Word of a relation level, or nil for an unknown one.
function Notebook.relationLevel(level)
    if not REL_LEVELS[level] then return nil end
    return tr('RelLevel_' .. level)
end

function Notebook.relationLines(rel)
    local when = Notebook.rep.when
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
            local what = getTextOrNull('IGUI_LK_RelFact_' .. tostring(f.fact)) or tr('RelFact_' .. nature)
            out[#out + 1] = '- ' .. tr(f.source == 'personal' and 'RelFactPersonal' or 'RelFactGroup',
                when(rel.today, f.day), what)
        end
    end
    return out
end

-- Contacts page of a Living Knox NPC (source "lk" of the core contacts, Living Knox without RadioSurvivor).
Notebook.contactPages.lk = function(_, row, line)
    line(tr('RelTitle'))
    for _, s in ipairs(Notebook.relationLines(row.relation)) do line(s) end
end

return Notebook
