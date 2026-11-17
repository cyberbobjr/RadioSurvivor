if isClient() then return end
--[[
RadioSurvivor: what happens when a voice gives recipes on the air (E27-T04, ADR recettes-radio D05, D06, D09).

For each recipe id delivered (radio_reply "recipes": the answer of the same turn, or of a call back):
- the recipe is read from the game (ScriptManager.getCraftRecipe, ScriptManager.java:975; nil = unknown: ignored with
  a log line);
- teaching (D05, D06): only when the recipe must be learned (CraftRecipe.needToBeLearn, CraftRecipe.java:185), the
  caller's reputation level is "good" and the recipe's job (RS_RecipeJobs on its category) is one of the voice's
  jobs. IsoGameCharacter.learnRecipe (IsoGameCharacter.java:10752-10765: adds the name to the known recipes, false
  when already known) changes the server copy only; sendSyncPlayerFields(player, PF_Recipes = 1) (LuaManager.java:3730,
  GameServer.java:2306, SyncPlayerFieldsPacket.java:52-57 write / 104-111 read) sends the known recipes to the owning
  client, as vanilla ISResearchRecipe.lua:83-85 and ISReadABook.lua:372-373 do; off a server it does nothing (solo:
  the player is the server copy);
- notebook entry (D09, D10): a "recipe" line in the Radio history of the character (RS_RadioLog) on the frequency of
  the voice: text "<id>|<1 learned now by the voice | 0>", game date of the line; the client reads the recipe from
  its own game, in the player's language (client/RadioSurvivor/RS_RecipeNote.lua).
Nothing without a notebook character. Authority only. Console messages in English.
]]
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local Jobs = require 'RadioSurvivor/RS_RecipeJobs'
local Log = require 'RadioSurvivor/RS_RadioLog'

local Delivery = {}

Delivery.PF_RECIPES = 1   -- SyncPlayerFieldsPacket.PF_Recipes
Delivery.TEACH_LEVEL = 'good'

local function voiceJob(sheet, job)
    local help = type(sheet) == 'table' and sheet.help or nil
    for _, id in ipairs(help and help.jobs or {}) do
        if id == job then return true end
    end
    return false
end

-- Does this voice teach this recipe to a caller of this reputation level? (D05, D06)
function Delivery.teaches(recipe, sheet, level)
    return level == Delivery.TEACH_LEVEL and recipe:needToBeLearn() == true and voiceJob(sheet, Jobs.of(recipe:getCategory()))
end

-- Engine adapter: the player learns the recipe and the owning client gets its known recipes. True when learned now.
local function learn(player, id)
    if not player or not player:learnRecipe(id) then return false end
    sendSyncPlayerFields(player, Delivery.PF_RECIPES)
    return true
end

-- ctx = { cid, khz, sheet, player, level }; ids = recipe ids given by the voice. Returns { [id] = learned }.
function Delivery.deliver(ctx, ids)
    local out = {}
    if type(ctx) ~= 'table' or type(ctx.cid) ~= 'string' or type(ids) ~= 'table' then return out end
    local scripts = getScriptManager()
    for _, id in ipairs(ids) do
        local recipe = type(id) == 'string' and scripts:getCraftRecipe(id) or nil
        if not recipe then
            Const.log("recipe '" .. tostring(id) .. "' unknown: not noted, not taught")
        else
            local learned = Delivery.teaches(recipe, ctx.sheet, ctx.level) and learn(ctx.player, id)
            out[id] = learned
            Log.add(ctx.cid, ctx.khz, 'recipe', id .. '|' .. (learned and '1' or '0'),
                type(ctx.sheet) == 'table' and ctx.sheet.id or nil)
            if learned then Const.log("recipe '" .. id .. "' taught to " .. ctx.cid) end
        end
    end
    return out
end

return Delivery
