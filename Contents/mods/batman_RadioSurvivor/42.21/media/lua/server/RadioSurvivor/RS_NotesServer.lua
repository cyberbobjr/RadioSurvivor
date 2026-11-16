-- Radio Survivor : notes de fréquences côté autorité (E05-T09) : fréquence écrite sur la note à sa création, et
-- butin. Serveur MP ou solo. Détails : docs/specifications-techniques/notes-frequences.md.
--
-- Déclarations (E20-T11) : section [note] de chaque fiche chargée (RS_Personas, ordre des fiches) : objet, racine des
-- traductions (ou texte écrit dans la fiche, E22-T07), listes de butin à thème (loot=, glovebox=). Socle commun de
-- toute note (E24-T03) : RS_NotesBase (listes à papiers, boîte à gants, zombies). Aucune voix n'est nommée ici ;
-- fournisseur des déclarations de RS_Notes.
-- Fréquence : fournisseur de RS_Notes. Première fréquence servie de la voix (RS_Personas.served, ordre des plages de
-- la fiche), si la voix est active ; sinon nil (note sans fréquence). Les fiches sont lues à OnLoadRadioScripts
-- (IsoWorld.java:1918, 42.22 : ZomboidRadio.Init), avant GlobalModData.init (OnInitGlobalModData, l.1921) et avant
-- que le monde charge ses premiers conteneurs.
--
-- Butin : notes ajoutées aux listes déclarées (procédurales vanilla citées par des salles, relevé distmatrix.py :
-- docs/specifications-techniques/notes-frequences.md ; boîte à gants des voitures), à OnInitGlobalModData (options
-- sandbox de la partie connues, y compris en solo, base loot-distributions.md), sans doublon, puis
-- ItemPickerJava.Parse(). Un objet partagé par plusieurs voix dans une même liste y est inscrit une fois, avec la
-- somme de leurs poids. Poids de base multipliés par l'option NoteRarity (0 : aucune note). Un changement de l'option
-- ou d'une déclaration en cours de partie n'est repris qu'au prochain chargement du monde. Mod désactivé (Enabled) :
-- aucune note dans le butin.
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).
if isClient() then return end

require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Personas = require "RadioSurvivor/RS_Personas"
local Notes = require "RadioSurvivor/RS_Notes"
local Base = require "RadioSurvivor/RS_NotesBase"

local NotesServer = {}

local function log(msg)
    Const.log("notes: " .. msg)
end

-- Déclarations des notes des fiches chargées : { voice, item, key, text, loot, glovebox } ; text (lignes écrites
-- dans la fiche, E22-T07) à la place de item et key pour la note manuscrite générique.
function NotesServer.declarations()
    local out = {}
    for _, id in ipairs(Personas.ids()) do
        local sheet = Personas.get(id)
        local note = type(sheet) == "table" and sheet.note or nil
        if type(note) == "table" then
            out[#out + 1] = { voice = id, item = note.item, key = note.key, text = note.text, loot = note.loot,
                glovebox = note.glovebox }
        end
    end
    return out
end

-- Listes d'une note : socle commun (RS_NotesBase, E24-T03) puis listes à thème de la fiche ; une liste présente
-- deux fois garde le poids le plus fort. { list, weight } dans l'ordre : socle, puis thèmes nouveaux.
local function merged(baseLists, ownLists)
    local out, at = {}, {}
    for _, lists in ipairs({ baseLists, ownLists }) do
        for _, e in ipairs(lists) do
            local i = at[e.list]
            if i then
                out[i].weight = math.max(out[i].weight, e.weight)
            else
                out[#out + 1] = { list = e.list, weight = e.weight }
                at[e.list] = #out
            end
        end
    end
    return out
end

-- Entrées de butin des notes déclarées : { voice, fullType, list, weight (poids de base, environ poids % par tirage
-- avant le facteur de rareté), vehicle = true pour VehicleDistributions }. Une entrée par voix et liste.
function NotesServer.entries()
    local out = {}
    for _, def in ipairs(Notes.voices()) do
        for _, e in ipairs(merged(Base.loot, def.loot)) do
            out[#out + 1] = { voice = def.voice, fullType = def.fullType, list = e.list, weight = e.weight }
        end
        for _, e in ipairs(merged(Base.glovebox, def.glovebox)) do
            out[#out + 1] = { voice = def.voice, fullType = def.fullType, list = e.list, weight = e.weight,
                vehicle = true }
        end
    end
    return out
end

-- Fréquence (kHz) à écrire sur une note neuve de la voix, ou nil.
function NotesServer.frequencyOf(voice)
    local sheet = Personas.get(voice)
    if not sheet or sheet.state ~= "active" then return nil end
    return Personas.served(voice)[1]
end

local function listItems(entry)
    local list
    if entry.vehicle then
        list = VehicleDistributions and VehicleDistributions[entry.list]
    else
        list = ProceduralDistributions and ProceduralDistributions.list and ProceduralDistributions.list[entry.list]
    end
    return list and list.items
end

-- Position du nom value dans items (liste nom, poids, nom, poids...), ou nil.
local function indexOf(items, value)
    for i, v in ipairs(items) do
        if v == value then return i end
    end
    return nil
end

-- Ajoute chaque note absente de sa liste, avec son poids x facteur (poids cumulés d'un objet partagé) ; nombre
-- d'entrées appliquées.
function NotesServer.addToLoot()
    if not Const.isEnabled() then
        log("mod disabled, no note added to the loot")
        return 0
    end
    local factor = Const.noteRarityFactor()
    if factor <= 0 then
        log("NoteRarity = none, no note added to the loot")
        return 0
    end
    local added, mine, missing = 0, {}, {}
    for _, entry in ipairs(NotesServer.entries()) do
        local items = listItems(entry)
        local listKey = (entry.vehicle and "vehicle:" or "") .. entry.list
        local key = listKey .. "|" .. entry.fullType
        if not items then
            if not missing[listKey] then
                missing[listKey] = true
                log("WARNING: loot list " .. entry.list .. " not found, notes skipped there")
            end
        elseif mine[key] then
            items[mine[key] + 1] = items[mine[key] + 1] + entry.weight * factor
            added = added + 1
        elseif not indexOf(items, entry.fullType) then
            table.insert(items, entry.fullType)
            table.insert(items, entry.weight * factor)
            mine[key] = #items - 1
            added = added + 1
        end
    end
    if added > 0 then
        ItemPickerJava.Parse()
        log(tostring(added) .. " loot entries added, rarity factor " .. tostring(factor))
    end
    return added
end

-- Roll after vanilla fills corpse loot (ItemPickerJava.java:587-622, 42.21.0), on every zombie corpse (E24-T03):
-- Base.corpseChance, or Base.walkieCorpseChance when the corpse carries a two-way radio, times the NoteRarity factor.
-- Remember the result on the corpse; repeated fills never roll again or duplicate the note. Candidates: every
-- declared note whose voice serves a frequency.
local CORPSE_KEY = "RadioSurvivorCorpseNote"

local function carriesWalkie(inv)
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "Radio") then
            local data = item:getDeviceData()
            if data and data:getIsTwoWay() then return true end
        end
    end
    return false
end

function NotesServer.onFillContainer(roomName, containerType, inv)
    if roomName ~= "Zombie" then return end
    local corpse = inv:getParent()
    if not corpse or not instanceof(corpse, "IsoDeadBody") then return end
    if not Const.isEnabled() or Const.noteRarityFactor() <= 0 then return end
    local md = corpse:getModData()
    local chosen = md[CORPSE_KEY]
    if chosen == nil then
        md[CORPSE_KEY] = false
        local base = carriesWalkie(inv) and Base.walkieCorpseChance or Base.corpseChance
        local chance = math.min(100, base * Const.noteRarityFactor())
        if ZombRand(10000) >= chance * 100 then return end
        local candidates = {}
        for _, def in ipairs(Notes.voices()) do
            if NotesServer.frequencyOf(def.voice) ~= nil then
                candidates[#candidates + 1] = def.fullType
            end
        end
        if #candidates == 0 then return end
        chosen = candidates[ZombRand(#candidates) + 1]
        md[CORPSE_KEY] = chosen
    end
    if not chosen then return end
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == chosen then return end
    end
    inv:AddItem(chosen)
end

Notes.declarationsProvider = NotesServer.declarations
Notes.frequencyProvider = NotesServer.frequencyOf
Events.OnInitGlobalModData.Add(NotesServer.addToLoot)
Events.OnFillContainer.Add(NotesServer.onFillContainer)

return NotesServer
