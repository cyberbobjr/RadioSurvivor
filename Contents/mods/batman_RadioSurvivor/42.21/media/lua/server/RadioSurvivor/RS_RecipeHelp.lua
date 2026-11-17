if isClient() then return end
--[[
RadioSurvivor: recipe help of the voices on the server (E27-T04), between the radio requests (RadioSurvivor_Server)
and RS_RecipeSearches / RS_RecipeDelivery. The server decides time, delivery and teaching; the bridge only words.

  Help.request(req)                    a radio request of a notebook character: req.recipe = field recipe= of its
                                       pending search to this voice (absent without one), req.recipeReady = ready.
  Help.answered(req, reply, ctx)       the bridge answered req; reply = { recipes, searched } of radio_reply (nil
                                       fields when absent); ctx = { sheet, player, level } given by the server.
                                       "recipes" present on a ready call back: the search is cleared (delivered,
                                       even empty); every id given is delivered (notebook entry, teaching).
                                       "searched": kept as the new search of this caller to this voice (D07).
Authority only.
]]
local Searches = require 'RadioSurvivor/RS_RecipeSearches'
local Delivery = require 'RadioSurvivor/RS_RecipeDelivery'

local Help = {}

function Help.request(req)
    req.recipe, req.recipeReady = nil, false
    if type(req.cid) ~= 'string' then return end
    req.recipe, req.recipeReady = Searches.field(req.cid, req.voice)
end

function Help.answered(req, reply, ctx)
    if type(req) ~= 'table' or type(req.cid) ~= 'string' or type(reply) ~= 'table' then return end
    ctx = ctx or {}
    if type(reply.recipes) == 'table' then
        if req.recipeReady then Searches.clear(req.cid, req.voice) end
        Delivery.deliver({ cid = req.cid, khz = req.khz, sheet = ctx.sheet, player = ctx.player, level = ctx.level },
            reply.recipes)
    end
    if type(reply.searched) == 'table' then
        local help = type(ctx.sheet) == 'table' and ctx.sheet.help or nil
        Searches.store(req.cid, req.voice, help and help.delay or 'now', reply.searched)
    end
end

return Help
