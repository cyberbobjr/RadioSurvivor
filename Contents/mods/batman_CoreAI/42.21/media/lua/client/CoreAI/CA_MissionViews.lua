--[[
CoreAI: notebook views of the mission templates (E20-T01, ADR D02; moved to the core mod by E21-T03). One file per view
in client/CoreAI/MissionViews/, registered at load; the Missions tab of the notebook looks the view up when it draws a
page, so the order of loading does not matter. Adding a mission type adds a view file, never a case in the notebook.

    register(templateName, view)    view = { showsPlace = bool, detail = function(row, line, ctx) }
                                    showsPlace: the notebook writes the kind of place and its clues first;
                                    detail: lines proper to the template, written with line(text);
                                    ctx: helpers of the notebook { tr, placeName, clueText, itemName }
    setDefault(view)                view of a row without a template name or with an unknown one
    get(templateName) -> view       registered view, else the default view (nil before any registration)
    tr(key, ...) -> text            generic words of the views (IGUI_CA_<key>)

Giver presentations (E21-T03): how the missions of a kind of giver (row.donor) are presented. A mod that gives missions
registers its kind; the views never name a giver.

    registerGiver(kind, giver)      giver = { remote = bool, sections = { [templateName] = fn(row, line, ctx) },
                                    reportLine = fn(row) -> text }
                                    remote: the giver has no body to join (no hand-over or report in person);
                                    sections: lines of the giver at the section point of a template's view, written
                                    instead of the view's own lines of that point (none: the view's lines);
                                    reportLine: line of the report expected (nil: the notebook's line in person)
    giver(kind) -> giver            registered giver, else a giver in person { remote = false, sections = {} }
    section(templateName, row, line, ctx, fallback)   writes the section of the row's giver for this template, else
                                    fallback(row, line, ctx) when given
]]
local Views = {}

local views, default = {}, nil
local givers = {}
local IN_PERSON = { remote = false, sections = {} }

function Views.register(templateName, view)
    views[templateName] = view
    return view
end

function Views.setDefault(view)
    default = view
    return view
end

function Views.get(templateName)
    return templateName ~= nil and views[templateName] or default
end

function Views.tr(key, ...)
    return getText('IGUI_CA_' .. key, ...)
end

function Views.registerGiver(kind, giver)
    if type(giver.sections) ~= 'table' then giver.sections = {} end
    givers[kind] = giver
    return giver
end

function Views.giver(kind)
    return kind ~= nil and givers[kind] or IN_PERSON
end

function Views.section(templateName, row, line, ctx, fallback)
    local write = Views.giver(row.donor).sections[templateName]
    if write then return write(row, line, ctx) end
    if fallback then return fallback(row, line, ctx) end
end

return Views
