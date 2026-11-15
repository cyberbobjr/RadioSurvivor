-- Radio Survivor : notes de fréquences (E05-T09), documents lisibles trouvés dans le butin.
--
-- Une note par voix qui la déclare dans sa fiche (section [note], E20-T11 : objet, racine des traductions, listes de
-- butin, mort au talkie ; format docs/specifications-techniques/persona-format.md) ; aucune voix n'est nommée dans ce
-- code. Objet `literature` sans CanBeWrite (media/scripts/RadioSurvivor_notes.txt) : « Inspecter » l'ouvre dans la
-- fenêtre vanilla des documents (ISReadABook:displayPrintMedia, moteur printMedia). Plusieurs voix peuvent partager
-- un objet : une note neuve de cet objet porte l'une d'elles, tirée à sa création.
--
-- Transport de la fréquence (docs/specifications-techniques/notes-frequences.md) :
--   - l'autorité (solo, serveur MP) écrit dans la ModData de l'objet, à sa création (OnCreate, appelé par
--     Item.InstanceItem quand le butin remplit un conteneur), la voix et la fréquence servie de la partie en kHz :
--     modData.RadioSurvivorNote = { voice = "<id>", khz = 134200 } ; elle vient de RS_Personas, côté autorité
--     seulement (fournisseurs posés par server/RadioSurvivor/RS_NotesServer.lua : déclarations et fréquences) ;
--   - l'objet ne garde que des clés de traduction dans modData.printMedia (title, info, text) : un serveur MP ne
--     connaît pas les traductions des mods, et un texte composé sur l'autorité serait figé dans sa langue ;
--   - le client compose le texte dans la langue du lecteur, fréquence comprise, juste avant l'ouverture
--     (client/RadioSurvivor/RS_NotesReader.lua, enveloppe de displayPrintMedia), d'après les clés de l'objet ;
--   - la ModData d'un objet n'arrive chez un client qu'avec l'objet lui-même (contenu d'un conteneur qu'il ouvre,
--     objet au sol près de lui, inventaire) : aucune commande ne porte de fréquence.
-- Sur un client MP, OnCreate est rejoué à la réception de l'objet, sans fournisseur : il ne pose rien, la ModData
-- du serveur arrive avec l'objet (InventoryItem.load, base loot-distributions.md).
-- Voix absente, silencieuse, disparue ou sans fréquence servie à la création : note sans fréquence, le texte
-- affiche SMUDGED (encre délavée). Une note garde la fréquence de sa création, même si la fiche change ensuite.
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).

local Const = require "RadioSurvivor/RadioSurvivor_Const"

local Notes = {}

Notes.MODDATA_KEY = "RadioSurvivorNote"
-- Fréquence illisible (voix sans fréquence servie à la création de la note).
Notes.SMUDGED = "???.?"

-- Fournisseur des déclarations, posé côté autorité seulement : function() -> liste { voice, item = "Module.Type",
-- key, loot, glovebox, corpse } (section [note] des fiches chargées, dans leur ordre).
Notes.declarationsProvider = nil
-- Fournisseur de fréquence, posé côté autorité seulement : function(voice) -> kHz servi, ou nil.
Notes.frequencyProvider = nil

-- Définition d'une note d'après sa déclaration : type d'objet, clés de traduction, identifiant printMedia.
local function definition(decl)
    local module, itemType = string.match(decl.item, "^([^%.]+)%.(.+)$")
    local id = module .. "_" .. decl.key
    return { voice = decl.voice, type = itemType, fullType = decl.item, id = id,
        titleKey = "Print_Media_" .. id .. "_title", infoKey = "Print_Media_" .. id .. "_info",
        textKey = "Print_Text_" .. id .. "_info", loot = decl.loot or {}, glovebox = decl.glovebox or {},
        corpse = decl.corpse == true }
end

-- Notes déclarées, dans l'ordre des fiches (liste vide sans fournisseur).
function Notes.voices()
    local out = {}
    for _, decl in ipairs(Notes.declarationsProvider and Notes.declarationsProvider() or {}) do
        out[#out + 1] = definition(decl)
    end
    return out
end

-- Notes portées par ce type d'objet (sans module).
function Notes.forType(itemType)
    local out = {}
    for _, def in ipairs(Notes.voices()) do
        if def.type == itemType then out[#out + 1] = def end
    end
    return out
end

function Notes.forVoice(voice)
    for _, def in ipairs(Notes.voices()) do
        if def.voice == voice then return def end
    end
    return nil
end

-- Vrai pour la ModData d'une note de fréquence (voix et clés posées par l'autorité) ; faux pour un autre document.
function Notes.isNote(modData)
    local printMedia = type(modData) == "table" and modData.printMedia or nil
    return type(modData) == "table" and type(modData[Notes.MODDATA_KEY]) == "table" and type(printMedia) == "table"
        and type(printMedia.info) == "string" and type(printMedia.text) == "string"
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

-- Note que porte un objet neuf de ce type : la seule déclarée, ou une tirée parmi celles dont la voix a une
-- fréquence servie (parmi toutes si aucune), ou nil.
local function chosen(itemType)
    local defs = Notes.forType(itemType)
    if #defs <= 1 then return defs[1] end
    local live = {}
    for _, def in ipairs(defs) do
        if Notes.frequencyProvider and Notes.frequencyProvider(def.voice) ~= nil then live[#live + 1] = def end
    end
    if #live == 0 then live = defs end
    return live[ZombRand(#live) + 1]
end

-- OnCreate de chaque note (script : OnCreate = RadioSurvivorNotes.onCreate).
function Notes.onCreate(item)
    local def = item and chosen(item:getType())
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
    if not Notes.isNote(modData) then return nil end
    local printMedia = modData.printMedia
    local label = Notes.frequencyLabel(modData[Notes.MODDATA_KEY])
    return getText(printMedia.info, label), getText(printMedia.text, label)
end

-- Fonction globale citée par les scripts d'objets (résolue par son nom pointé, LuaManager.getFunctionObject).
RadioSurvivorNotes = RadioSurvivorNotes or {}
RadioSurvivorNotes.onCreate = function(item) Notes.onCreate(item) end

return Notes
