-- Living Knox : forme sauvegardée des plaies (LK21-T01, ADR adr-blessures-soins.md D01) : texte compact et validé,
-- gardé avec le registre des corps (LK21-T02). Modèle des plaies : LK_Wounds.lua.
require "LivingKnox/LK_Wounds"

local Wounds = LivingKnox.Wounds

-- ================================================================ forme sauvegardée
-- Texte compact : plaies séparées par « ; », champs par « : » :
--   kind:part:age:time:bleed:life:alcool du bandage:stitch:splint:foreign:infected:level:alcohol:harm
-- champ vide : absent (time, bandage, stitch, splint) ; drapeaux 1 ou 0 ; nombres décimaux sans exposant.
local FIELD_COUNT = 14
Wounds.BLEED_LIMIT = 1000   -- saignement d'une plaie au plus (unités vanilla) dans la forme sauvegardée
local NUMBER_PATTERN = "^%-?%d+%.?%d*$"

local function num(v)
    local s = string.format("%.6f", v)
    s = (string.gsub(s, "0+$", ""))
    s = (string.gsub(s, "%.$", ""))
    if s == "-0" then s = "0" end
    return s
end

local function opt(v)
    if v == nil then return "" end
    return num(v)
end

local function flag(v)
    return v and "1" or "0"
end

function Wounds.pack(list)
    local out = {}
    for _, w in ipairs(list) do
        local b = w.bandage
        out[#out + 1] = table.concat({ w.kind, w.part, num(w.age), opt(w.time), num(w.bleed),
            b ~= nil and num(b.life) or "", b ~= nil and flag(b.alcohol) or "", opt(w.stitch), opt(w.splint),
            flag(w.foreign), flag(w.infected), num(w.level), num(w.alcohol), num(w.harm) }, ":")
    end
    return table.concat(out, ";")
end

-- Morceaux de s séparés par sep (recherche littérale ; garde les morceaux vides).
local function split(s, sep)
    local out, i = {}, 1
    while true do
        local j = string.find(s, sep, i, true)
        if j == nil then
            out[#out + 1] = string.sub(s, i)
            return out
        end
        out[#out + 1] = string.sub(s, i, j - 1)
        i = j + 1
    end
end

local function parseNumber(s)
    if string.match(s, NUMBER_PATTERN) == nil then return nil end
    return tonumber(s)
end

local function parseFlag(s)
    if s == "1" then return true end
    if s == "0" then return false end
    return nil
end

local function parseWound(text)
    local f = split(text, ":")
    if #f ~= FIELD_COUNT then return nil end
    local w = { kind = f[1], part = f[2], age = parseNumber(f[3]), bleed = parseNumber(f[5]),
        foreign = parseFlag(f[10]), infected = parseFlag(f[11]), level = parseNumber(f[12]),
        alcohol = parseNumber(f[13]), harm = parseNumber(f[14]) }
    if f[4] ~= "" then
        w.time = parseNumber(f[4])
        if w.time == nil then return nil end
    end
    if f[6] ~= "" or f[7] ~= "" then
        local life, alc = parseNumber(f[6]), parseFlag(f[7])
        if life == nil or alc == nil then return nil end
        w.bandage = { life = life, alcohol = alc }
    end
    if f[8] ~= "" then
        w.stitch = parseNumber(f[8])
        if w.stitch == nil then return nil end
    end
    if f[9] ~= "" then
        w.splint = parseNumber(f[9])
        if w.splint == nil then return nil end
    end
    return w
end

-- Liste lue dans text (Wounds.pack), ou nil et la raison.
function Wounds.unpack(text)
    if type(text) ~= "string" then return nil, "not a string" end
    local list = {}
    if text ~= "" then
        for _, chunk in ipairs(split(text, ";")) do
            local w = parseWound(chunk)
            if w == nil then return nil, "malformed wound" end
            list[#list + 1] = w
        end
    end
    local ok, why = Wounds.valid(list)
    if not ok then return nil, why end
    return list
end

local function within(v, lo, hi)
    return LivingKnox.Num.finite(v) and v >= lo and v <= hi
end

local function woundProblem(w)
    if type(w) ~= "table" then return "wound must be a table" end
    local spec = Wounds.kindById[w.kind]
    if spec == nil then return "unknown kind" end
    if Wounds.PART[w.part] == nil then return "unknown part" end
    if not within(w.age, 0, 1e9 - 1) then return "bad age" end
    if w.time ~= nil and not within(w.time, 0, 1000) then return "bad time" end
    if not within(w.bleed, 0, Wounds.BLEED_LIMIT) then return "bad bleed" end
    local b = w.bandage
    if b ~= nil and (type(b) ~= "table" or not within(b.life, 0, 100) or type(b.alcohol) ~= "boolean") then
        return "bad bandage"
    end
    if w.stitch ~= nil and not within(w.stitch, 0, Wounds.STITCH.max) then return "bad stitch" end
    if w.splint ~= nil and not within(w.splint, 0, 100) then return "bad splint" end
    if type(w.foreign) ~= "boolean" or type(w.infected) ~= "boolean" then return "bad flags" end
    if w.foreign and spec.foreign == nil then return "foreign body on a kind without one" end
    if not within(w.level, Wounds.INFECTION.min, Wounds.INFECTION.max) then return "bad level" end
    if not within(w.alcohol, 0, 1000) then return "bad alcohol" end
    if not within(w.harm, 0, 100) then return "bad harm" end
    return nil
end

-- Vrai si list est une liste de plaies valide ; sinon faux et la raison.
function Wounds.valid(list)
    if type(list) ~= "table" then return false, "list must be a table" end
    if #list > Wounds.MAX_WOUNDS then return false, "too many wounds" end
    for i, w in ipairs(list) do
        local why = woundProblem(w)
        if why ~= nil then return false, "wound " .. i .. ": " .. why end
    end
    return true
end

return Wounds
