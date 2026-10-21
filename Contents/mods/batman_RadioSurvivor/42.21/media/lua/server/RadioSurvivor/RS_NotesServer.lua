-- Radio Survivor : notes de fréquences côté autorité (E05-T09) : fréquence écrite sur la note à sa création, et
-- butin. Serveur MP ou solo. Détails : docs/specifications-techniques/notes-frequences.md.
--
-- Fréquence : fournisseur de RS_Notes. Première fréquence servie de la voix (RS_Personas.served, ordre des plages de
-- la fiche), si la voix est active ; sinon nil (note sans fréquence). Les fiches sont lues à OnLoadRadioScripts
-- (IsoWorld.java:1905, 42.21.0), avant que le monde charge ses premiers conteneurs (WorldStreamer, l.2067).
--
-- Butin : notes ajoutées à des listes procédurales vanilla 42.21 citées par des salles (relevé distmatrix.py :
-- docs/specifications-techniques/notes-frequences.md) et à la boîte à gants des voitures, à OnInitGlobalModData (options sandbox
-- de la partie connues, y compris en solo, base loot-distributions.md), sans doublon, puis ItemPickerJava.Parse(). Poids de base
-- multipliés par l'option NoteRarity (0 : aucune note). Un changement de l'option en cours de partie n'est repris
-- qu'au prochain chargement du monde. Mod désactivé (Enabled) : aucune note dans le butin.
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).
if isClient() then return end

require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Personas = require "RadioSurvivor/RS_Personas"
local Notes = require "RadioSurvivor/RS_Notes"

local NotesServer = {}

-- { voix, liste, poids de base }. Liste procédurale (ProceduralDistributions.list) sauf vehicle = true
-- (VehicleDistributions). Poids : environ poids % par tirage (rolls de la liste, 1 à 4), avant le facteur de rareté
-- et les réglages de butin du sandbox (base loot-distributions.md, « Chance d'un objet »).
NotesServer.ENTRIES = {
    -- Walt: home and general office desks (including their variants), garages, electronics and HAM radio shelves.
    -- Four rolls at weight 4 give about 15% before sandbox loot modifiers; HAM shelves have one roll.
    { voice = "walt", list = "OfficeDeskHome", weight = 4 },
    { voice = "walt", list = "OfficeDeskHomeClassy", weight = 4 },
    { voice = "walt", list = "OfficeDesk", weight = 4 },
    { voice = "walt", list = "OfficeDeskSecretary", weight = 4 },
    { voice = "walt", list = "OfficeDeskStressed", weight = 4 },
    { voice = "walt", list = "GarageTools", weight = 4 },
    { voice = "walt", list = "CrateElectronics", weight = 4 },
    { voice = "walt", list = "ElectronicStoreHAMRadio", weight = 15 },
    -- Darlene : cliniques, cabinets médicaux, pharmacies, hôpitaux, rayon santé des épiceries.
    { voice = "darlene", list = "MedicalClinicDrugs", weight = 3 },
    { voice = "darlene", list = "MedicalOfficeDesk", weight = 4 },
    { voice = "darlene", list = "HospitalRoomCounter", weight = 2 },
    { voice = "darlene", list = "StoreShelfMedical", weight = 1 },
    -- Cody : postes de police, gardiens, réserves de l'armée, surplus militaire.
    { voice = "cody", list = "PoliceDesk", weight = 5 },
    { voice = "cody", list = "PoliceFilingCabinet", weight = 3 },
    { voice = "cody", list = "SecurityDesk", weight = 3 },
    { voice = "cody", list = "ArmyStorageElectronics", weight = 3 },
    { voice = "cody", list = "ArmySurplusMisc", weight = 2 },
    -- Gus : magasins et réserves de pêche, cartons de pêche des placards, garages et remises, boîte à gants des
    -- pêcheurs.
    { voice = "gus", list = "FishingStoreGear", weight = 4 },
    { voice = "gus", list = "CrateFishing", weight = 1.5 },
    { voice = "gus", list = "FishermanGloveBox", weight = 10, vehicle = true },
    -- Night Owl : salons, présentoirs de magazines (stations-service, supérettes), rayon musique, boîte à gants.
    { voice = "nightowl", list = "LivingRoomSideTable", weight = 1 },
    { voice = "nightowl", list = "MagazineRackMixed", weight = 2 },
    { voice = "nightowl", list = "ElectronicStoreMusic", weight = 4 },
    { voice = "nightowl", list = "GloveBox", weight = 1.5, vehicle = true },
}

local function log(msg)
    Const.log("notes: " .. msg)
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

local function contains(items, value)
    for _, v in ipairs(items) do
        if v == value then return true end
    end
    return false
end

-- Ajoute chaque note absente de sa liste, avec son poids x facteur ; nombre d'entrées ajoutées.
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
    local added = 0
    for _, entry in ipairs(NotesServer.ENTRIES) do
        local def = Notes.forVoice(entry.voice)
        local items = listItems(entry)
        if not items then
            log("WARNING: loot list " .. entry.list .. " not found, note of voice '" .. entry.voice .. "' skipped")
        elseif not contains(items, def.fullType) then
            table.insert(items, def.fullType)
            table.insert(items, entry.weight * factor)
            added = added + 1
        end
    end
    if added > 0 then
        ItemPickerJava.Parse()
        log(tostring(added) .. " loot entries added, rarity factor " .. tostring(factor))
    end
    return added
end

-- Roll after vanilla fills corpse loot (ItemPickerJava.java:587-622, 42.21.0).
-- Remember the result on the corpse; repeated fills never roll again or duplicate the note.
NotesServer.CORPSE_NOTE_CHANCE = 35
local CORPSE_KEY = "RadioSurvivorCorpseNote"
local CORPSE_VOICES = { "walt", "darlene", "cody", "gus", "nightowl" }

function NotesServer.onFillContainer(roomName, containerType, inv)
    if roomName ~= "Zombie" then return end
    local corpse = inv:getParent()
    if not corpse or not instanceof(corpse, "IsoDeadBody") then return end
    if not Const.isEnabled() or Const.noteRarityFactor() <= 0 then return end
    local md = corpse:getModData()
    local chosen = md[CORPSE_KEY]
    if chosen == nil then
        local items = inv:getItems()
        local hasWalkie = false
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if instanceof(item, "Radio") then
                local data = item:getDeviceData()
                if data and data:getIsTwoWay() then hasWalkie = true break end
            end
        end
        if not hasWalkie then return end
        md[CORPSE_KEY] = false
        local chance = math.min(100, NotesServer.CORPSE_NOTE_CHANCE * Const.noteRarityFactor())
        if ZombRand(10000) >= chance * 100 then return end
        local candidates = {}
        for _, voice in ipairs(CORPSE_VOICES) do
            if NotesServer.frequencyOf(voice) ~= nil then
                candidates[#candidates + 1] = Notes.forVoice(voice).fullType
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

Notes.frequencyProvider = NotesServer.frequencyOf
Events.OnInitGlobalModData.Add(NotesServer.addToLoot)
Events.OnFillContainer.Add(NotesServer.onFillContainer)

return NotesServer
