-- Recipe index file for the bridge (E27-T01, ADR recettes-radio D08, D11). Authority only (solo or server).
-- At every start of the authority (OnServerStarted on a dedicated server, OnGameStart in solo: the first of the two
-- in a Lua session), the craft recipes the game really loaded (RS_RecipeCatalog) are written to
-- Zomboid/Lua/batman_CoreAI/recipes.json, the exchange folder of the bridge (bridge/recipe_index.py rereads it when
-- it changes). Kahlua cannot rename a file: plain overwrite, the bridge keeps its previous index while a read fails.
-- Format: {"format":1,"written":<getTimestampMs>,"recipes":[<one recipe per line>]}, ASCII only (RS_Json).
-- Spec: docs/specifications-techniques/index-recettes.md. One English console line: count, bytes, milliseconds.
-- ASCII only (Kahlua lexer).
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Catalog = require "RadioSurvivor/RS_RecipeCatalog"
local Json = require "RadioSurvivor/RS_Json"

local Index = {}

Index.FILE = 'batman_CoreAI/recipes.json'
Index.FORMAT = 1

local function log(msg)
    Const.log('recipes: ' .. msg)
end

-- Writes the index of these records; returns the byte count, or nil when the file cannot be opened.
function Index.write(records, writtenMs)
    local writer = getFileWriter(Index.FILE, true, false)
    if not writer then
        log('ERROR: cannot write Zomboid/Lua/' .. Index.FILE .. '; the voices will not know the recipes')
        return nil
    end
    local bytes = 0
    local function put(s)
        writer:write(s)
        bytes = bytes + #s
    end
    put('{"format":' .. Index.FORMAT .. ',"written":' .. string.format('%.0f', writtenMs) .. ',"recipes":[')
    for i, rec in ipairs(records) do
        put((i > 1 and ',\n' or '\n') .. Json.encode(rec))
    end
    put('\n]}\n')
    writer:close()
    return bytes
end

-- Reads the loaded recipes and writes the file; returns the record count (nil when the file was not written).
function Index.export()
    local started = getTimestampMs()
    local records, skipped = Catalog.read(ScriptManager.instance)
    local bytes = Index.write(records, started)
    if not bytes then return nil end
    log(string.format('%d recipes written to %s (%d hidden skipped), %d bytes, %.0f ms', #records, Index.FILE,
        skipped, bytes, getTimestampMs() - started))
    return #records
end

local exported = false

local function onStart()
    if exported then return end
    exported = true
    Index.export()
end

if not isClient() and not RS_RecipeIndexHooked then
    RS_RecipeIndexHooked = true
    Events.OnServerStarted.Add(function() onStart() end)
    Events.OnGameStart.Add(function() onStart() end)
end

return Index
