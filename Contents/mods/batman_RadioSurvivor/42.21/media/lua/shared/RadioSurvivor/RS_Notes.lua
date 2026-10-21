-- Radio Survivor : notes de fréquences (E05-T09), documents lisibles trouvés dans le butin.
--
-- Une note par voix qui parle (walt, darlene, cody, gus, nightowl ; pas whitaker, silencieuse jusqu'aux secours
-- E12). Objet `literature` sans CanBeWrite (media/scripts/RadioSurvivor_notes.txt) : « Inspecter » l'ouvre dans la
-- fenêtre vanilla des documents (ISReadABook:displayPrintMedia, moteur printMedia).
--
-- Transport de la fréquence (docs/specifications-techniques/notes-frequences.md) :
--   - l'autorité (solo, serveur MP) écrit dans la ModData de l'objet, à sa création (OnCreate, appelé par
--     Item.InstanceItem quand le butin remplit un conteneur), la voix et la fréquence servie de la partie en kHz :
--     modData.RadioSurvivorNote = { voice = "walt", khz = 134200 } ; elle vient de RS_Personas, côté autorité
--     seulement (fournisseur posé par server/RadioSurvivor/RS_NotesServer.lua) ;
--   - l'objet ne garde que des clés de traduction dans modData.printMedia (title, info, text) : un serveur MP ne
--     connaît pas les traductions des mods, et un texte composé sur l'autorité serait figé dans sa langue ;
--   - le client compose le texte dans la langue du lecteur, fréquence comprise, juste avant l'ouverture
--     (client/RadioSurvivor/RS_NotesReader.lua, enveloppe de displayPrintMedia) ;
--   - la ModData d'un objet n'arrive chez un client qu'avec l'objet lui-même (contenu d'un conteneur qu'il ouvre,
--     objet au sol près de lui, inventaire) : aucune commande ne porte de fréquence.
-- Sur un client MP, OnCreate est rejoué à la réception de l'objet, sans fournisseur : il ne pose que les clés, et
-- la ModData du serveur remplace aussitôt la sienne (InventoryItem.load, base loot-distributions.md).
-- Voix absente, silencieuse, disparue ou sans fréquence servie à la création : note sans fréquence, le texte
-- affiche SMUDGED (encre délavée). Une note garde la fréquence de sa création, même si la fiche change ensuite.
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).

local Const = require "RadioSurvivor/RadioSurvivor_Const"

local Notes = {}

Notes.MODULE = "RadioSurvivor"
Notes.MODDATA_KEY = "RadioSurvivorNote"
-- Fréquence illisible (voix sans fréquence servie à la création de la note).
Notes.SMUDGED = "???.?"

-- Voix -> type d'objet (sans module). Ordre stable (tests, journal).
Notes.VOICES = {
    { voice = "walt", type = "NoteWalt" },
    { voice = "darlene", type = "NoteDarlene" },
    { voice = "cody", type = "NoteCody" },
    { voice = "gus", type = "NoteGus" },
    { voice = "nightowl", type = "NoteNightOwl" },
}

local byType, byId, byVoice = {}, {}, {}
for _, def in ipairs(Notes.VOICES) do
    def.fullType = Notes.MODULE .. "." .. def.type
    def.id = Notes.MODULE .. "_" .. def.type
    def.titleKey = "Print_Media_" .. def.id .. "_title"
    def.infoKey = "Print_Media_" .. def.id .. "_info"
    def.textKey = "Print_Text_" .. def.id .. "_info"
    byType[def.type] = def
    byId[def.id] = def
    byVoice[def.voice] = def
end

-- Fournisseur de fréquence, posé côté autorité seulement : function(voice) -> kHz servi, ou nil.
Notes.frequencyProvider = nil

function Notes.forType(itemType)
    return byType[itemType]
end

function Notes.forVoice(voice)
    return byVoice[voice]
end

-- Définition de la note d'après sa table printMedia, ou nil (autre document).
function Notes.forPrintMedia(printMedia)
    if type(printMedia) ~= "table" then return nil end
    return byId[printMedia.id]
end

-- Données de la ModData d'une note neuve : clés de traduction, voix, fréquence si l'autorité la connaît.
function Notes.newData(def)
    local khz = nil
    if Notes.frequencyProvider then khz = tonumber(Notes.frequencyProvider(def.voice)) end
    return {
        printMedia = { id = def.id, title = def.titleKey, info = def.infoKey, text = def.textKey },
        note = { voice = def.voice, khz = khz },
    }
end

-- OnCreate de chaque note (script : OnCreate = RadioSurvivorNotes.onCreate).
function Notes.onCreate(item)
    local def = item and byType[item:getType()]
    if not def then return end
    local data = Notes.newData(def)
    local modData = item:getModData()
    modData.printMedia = data.printMedia
    modData[Notes.MODDATA_KEY] = data.note
end

-- Fréquence affichée sur la note : « 134.2 » (comme le cadran des radios), ou SMUDGED.
function Notes.frequencyLabel(note)
    local khz = type(note) == "table" and tonumber(note.khz) or nil
    if khz == nil or khz <= 0 then return Notes.SMUDGED end
    return Const.frequencyLabel(khz)
end

-- Mise en page et transcription dans la langue courante, fréquence comprise, ou nil (autre document).
function Notes.compose(modData)
    local printMedia = type(modData) == "table" and modData.printMedia or nil
    local def = Notes.forPrintMedia(printMedia)
    if not def then return nil end
    local label = Notes.frequencyLabel(modData[Notes.MODDATA_KEY])
    return getText(def.infoKey, label), getText(def.textKey, label)
end

-- Fonction globale citée par les scripts d'objets (résolue par son nom pointé, LuaManager.getFunctionObject).
RadioSurvivorNotes = RadioSurvivorNotes or {}
RadioSurvivorNotes.onCreate = function(item) Notes.onCreate(item) end

return Notes
