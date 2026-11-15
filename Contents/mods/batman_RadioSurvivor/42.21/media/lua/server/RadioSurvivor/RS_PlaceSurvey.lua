-- Radio Survivor: places recorded in game for the voice workshop (E22-T08, ADR atelier-voix D08). Doc:
-- docs/specifications-techniques/persona-format.md, section "Releve de lieux en jeu (E22-T08)".
--
-- A right click in the world (client/RadioSurvivor/RS_PlaceSurveyMenu.lua, solo or admin) asks the authority to record
-- the clicked square. The authority checks the rights again (CA_AdminAccess: solo = the local player; MP server =
-- capability PopmanManage), checks the coordinates, reads ITSELF what lies on the square (never trusted from the
-- client): the containers of its objects, the room and the bounds of its building. It appends one line to the survey
-- file of the working folder, Zomboid/Lua/batman_RadioSurvivor/workshop-places.txt, keeping the last MAX_RECORDS
-- lines: the voice workshop of the bridge (bridge/place_surveys.py) lists them. Nothing else is ever written.
--
-- File: a header line starting with "#", then one record per line, fields separated by a tab, each "key=value":
--   time=<real UTC yyyy-mm-dd hh:mm:ss>  game=<game date yyyy-mm-dd hh:mm>  by=<character name>  at=<x>,<y>,<z>
--   [room=<room name>]  [building=<x1>,<y1>,<x2>,<y2> (BuildingDef bounds, end exclusive)]
--   [containers=<type>:<sprite>;<type>:<sprite>... (at most CONTAINERS_MAX)]
-- Values never hold a tab, a line break, nor (inside containers) ";" or ":": those become "_".
--
-- Transport: MP, client command "surveyPlace" (module "RadioSurvivorSurvey") { op = "place", n, x, y, z } -> reply
-- "surveyReply" to the requester only { n, op, ok, err }; solo, Survey.request called directly by the menu.
-- Errors: denied (rights), bad_coords (not integers, x or y outside 0..999999, z outside -32..31), not_loaded (no
-- square there on the authority), write_failed. A refusal carries no other field.
-- ASCII only in the code (Kahlua). Log messages in English.

local Survey = RS_PlaceSurvey or {}
RS_PlaceSurvey = Survey

Survey.MODULE = "RadioSurvivorSurvey"
Survey.CMD_REQUEST = "surveyPlace"
Survey.CMD_REPLY = "surveyReply"
Survey.OP = "place"
Survey.FILE = "batman_RadioSurvivor/workshop-places.txt"
Survey.HEADER = "# RadioSurvivor places recorded for the voice workshop, one per line (tab-separated key=value): "
    .. "time game by at room building containers"
Survey.MAX_RECORDS = 200
Survey.FIELD_MAX = 64
Survey.CONTAINERS_MAX = 4
Survey.COORD_MAX = 999999
Survey.Z_MIN = -32
Survey.Z_MAX = 31
Survey.REFUSAL_LOG_MS = 60000

if isClient() then return Survey end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Access = require "CoreAI/CA_AdminAccess"

Survey.stats = Survey.stats or { requests = 0, refused = 0, done = 0 }
Survey.lastRefusalLog = Survey.lastRefusalLog or { ms = nil, muted = 0 }

local function log(msg)
    Const.log("place survey: " .. msg)
end

local function count(name)
    Survey.stats[name] = (Survey.stats[name] or 0) + 1
end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

-- Text of a field: no tab, no line break, at most FIELD_MAX characters; extra = more characters replaced by "_".
function Survey.clean(value, extra)
    if value == nil then return "" end
    local text = string.gsub(tostring(value), "[%c]", " ")
    if extra ~= nil then text = string.gsub(text, extra, "_") end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return string.sub(text, 1, Survey.FIELD_MAX)
end

-- Authority check (see the header): true, or false and the reason (English, log only).
function Survey.isAllowed(player)
    return Access.allowed(player, false)
end

-- Name of the recorder's character ("Forename Surname"), else its account name, else "?".
function Survey.recorder(player)
    local desc = player ~= nil and player.getDescriptor ~= nil and player:getDescriptor() or nil
    if desc ~= nil then
        local name = Survey.clean(tostring(desc:getForename() or "") .. " " .. tostring(desc:getSurname() or ""))
        if name ~= "" then return name end
    end
    local account = player ~= nil and player.getUsername ~= nil and player:getUsername() or nil
    if type(account) == "string" and account ~= "" then return Survey.clean(account) end
    return "?"
end

local function gameDate()
    local gt = getGameTime and getGameTime() or nil
    if gt == nil then return "-" end
    return string.format("%04d-%02d-%02d %02d:%02d", gt:getYear(), gt:getMonth() + 1, gt:getDay() + 1,
        gt:getHour(), gt:getMinutes())
end

-- What the square holds: { room, building = { x1, y1, x2, y2 } | nil, containers = { { type, sprite } } }.
function Survey.describe(sq)
    local out = { containers = {} }
    local room = sq:getRoom()
    if room ~= nil then out.room = Survey.clean(room:getName()) end
    local building = sq:getBuilding()
    local def = building ~= nil and building:getDef() or nil
    if def ~= nil then
        out.building = { x1 = def:getX(), y1 = def:getY(), x2 = def:getX2(), y2 = def:getY2() }
    end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local sprite = object:getSprite()
        local spriteName = sprite ~= nil and sprite:getName() or nil
        for k = 0, object:getContainerCount() - 1 do
            local container = object:getContainerByIndex(k)
            if container ~= nil and #out.containers < Survey.CONTAINERS_MAX then
                out.containers[#out.containers + 1] = { type = Survey.clean(container:getType(), "[;:]"),
                    sprite = Survey.clean(spriteName, "[;:]") }
            end
        end
    end
    return out
end

-- Line of a record (see the header for the format).
function Survey.format(record)
    local fields = {
        "time=" .. record.time,
        "game=" .. record.game,
        "by=" .. Survey.clean(record.by),
        "at=" .. record.x .. "," .. record.y .. "," .. record.z,
    }
    if record.room ~= nil and record.room ~= "" then fields[#fields + 1] = "room=" .. Survey.clean(record.room) end
    local b = record.building
    if b ~= nil then fields[#fields + 1] = "building=" .. b.x1 .. "," .. b.y1 .. "," .. b.x2 .. "," .. b.y2 end
    local list = {}
    for i, c in ipairs(record.containers or {}) do list[i] = c.type .. ":" .. c.sprite end
    if #list > 0 then fields[#fields + 1] = "containers=" .. table.concat(list, ";") end
    return table.concat(fields, "\t")
end

local function readRecords()
    local lines = {}
    local reader = getFileReader(Survey.FILE, false)
    if reader == nil then return lines end
    local line = reader:readLine()
    while line ~= nil do
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then lines[#lines + 1] = line end
        line = reader:readLine()
    end
    reader:close()
    return lines
end

-- Appends one record line, keeping the last MAX_RECORDS. Returns true when written.
function Survey.append(line)
    local lines = readRecords()
    lines[#lines + 1] = line
    local first = math.max(1, #lines - Survey.MAX_RECORDS + 1)
    local writer = getFileWriter(Survey.FILE, true, false)
    if writer == nil then return false end
    writer:write(Survey.HEADER .. "\n")
    for i = first, #lines do writer:write(lines[i] .. "\n") end
    writer:close()
    return true
end

local function refuse(reply, err, player, why)
    count("refused")
    reply.err = err
    if err == "denied" then
        local slot, t = Survey.lastRefusalLog, getTimestampMs()
        if slot.ms ~= nil and t - slot.ms < Survey.REFUSAL_LOG_MS then
            slot.muted = slot.muted + 1
        else
            log("WARNING: request refused for " .. Survey.clean(player ~= nil and player.getUsername ~= nil
                and player:getUsername() or "?") .. " (" .. tostring(why) .. ")"
                .. (slot.muted > 0 and (", " .. slot.muted .. " more refusal(s) not logged") or ""))
            slot.ms, slot.muted = t, 0
        end
    end
    return reply
end

-- Handles a request of player. args = { op, n, x, y, z }. Returns the reply { n, op, ok, err }.
function Survey.request(player, args)
    count("requests")
    if type(args) ~= "table" then args = {} end
    local reply = { n = isInt(args.n, 0, 2147483647) and args.n or 0, op = Survey.OP, ok = false }
    local allowed, why = Survey.isAllowed(player)
    if not allowed then return refuse(reply, "denied", player, why) end
    local x, y, z = args.x, args.y, args.z
    if args.op ~= Survey.OP or not isInt(x, 0, Survey.COORD_MAX) or not isInt(y, 0, Survey.COORD_MAX)
            or not isInt(z, Survey.Z_MIN, Survey.Z_MAX) then
        return refuse(reply, "bad_coords")
    end
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(x, y, z) or nil
    if sq == nil then return refuse(reply, "not_loaded") end
    local record = Survey.describe(sq)
    record.time = os.date("!%Y-%m-%d %H:%M:%S")
    record.game = gameDate()
    record.by = Survey.recorder(player)
    record.x, record.y, record.z = x, y, z
    if not Survey.append(Survey.format(record)) then return refuse(reply, "write_failed") end
    count("done")
    log("place " .. x .. "," .. y .. "," .. z .. " recorded by " .. record.by)
    reply.ok = true
    return reply
end

function Survey.onClientCommand(module, command, player, args)
    if module ~= Survey.MODULE or command ~= Survey.CMD_REQUEST or not isServer() or player == nil then return end
    sendServerCommand(player, Survey.MODULE, Survey.CMD_REPLY, Survey.request(player, args))
end

-- One subscription, even when the file is read again (the function called is always the latest version).
if Events ~= nil and Events.OnClientCommand ~= nil and isServer() and not Survey.subscribed then
    Survey.subscribed = true
    Events.OnClientCommand.Add(function(module, command, player, args)
        RS_PlaceSurvey.onClientCommand(module, command, player, args)
    end)
end

return Survey
