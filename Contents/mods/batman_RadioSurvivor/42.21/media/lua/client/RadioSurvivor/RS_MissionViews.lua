--[[
Notebook views of the mission templates (E20-T01, ADR D02): one file per view in client/RadioSurvivor/MissionViews/,
registered at load; the Missions tab of the notebook (RS_Notebook, missionDetail) looks the view up when it draws a
page, so the order of loading does not matter. Adding a mission type adds a view file, never a case in the notebook.

    register(templateName, view)    view = { showsPlace = bool, detail = function(row, line, ctx) }
                                    showsPlace: the notebook writes the kind of place and its clues first;
                                    detail: lines proper to the template, written with line(text);
                                    ctx: helpers of the notebook { tr, placeName, clueText, itemName, voice }
    setDefault(view)                view of a row without a template name or with an unknown one
    get(templateName) -> view       registered view, else the default view (nil before any registration)
]]
local Views = {}

local views, default = {}, nil

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

return Views
