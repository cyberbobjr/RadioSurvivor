-- Radio Survivor : notes de fréquences (E05-T09), documents lisibles trouvés dans le butin.
--
-- Une note par voix qui la déclare dans sa fiche (section [note], E20-T11 : objet, racine des traductions, listes de
-- butin à thème ; format docs/specifications-techniques/persona-format.md ; socle commun de toute note :
-- server/RadioSurvivor/RS_NotesBase.lua) ; aucune voix n'est nommée dans ce
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
-- Note écrite dans la fiche (E22-T07, ADR D07) : une fiche qui donne text= (lignes de la note, %1 = fréquence) au
-- lieu de item et key a pour note l'objet générique GENERIC_ITEM (mot manuscrit). L'autorité écrit alors aussi ce texte
-- dans la ModData (modData.RadioSurvivorNote.text, lignes séparées par un saut de ligne) : il voyage avec l'objet
-- comme la fréquence, sans fiche ni texte d'une autre voix. Le client le met en page (composeWritten) avec la fréquence ; seul
-- le titre (Print_Media_RadioSurvivor_NoteVoice_title) est une clé de traduction.
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).

local Const = require "RadioSurvivor/RadioSurvivor_Const"

local Notes = {}

Notes.MODDATA_KEY = "RadioSurvivorNote"
-- Fréquence illisible (voix sans fréquence servie à la création de la note).
Notes.SMUDGED = "???.?"
-- Note manuscrite générique (E22-T07) : objet et identifiant printMedia des notes écrites dans les fiches.
Notes.GENERIC_ITEM = "RadioSurvivor.NoteVoice"
local GENERIC_ID = "RadioSurvivor_NoteVoice"

-- Fournisseur des déclarations, posé côté autorité seulement : function() -> liste { voice, item = "Module.Type",
-- key, loot, glovebox } ou, pour une note écrite dans la fiche, { voice, text = { lignes }, loot, glovebox }
-- (section [note] des fiches chargées, dans leur ordre).
Notes.declarationsProvider = nil
-- Fournisseur de fréquence, posé côté autorité seulement : function(voice) -> kHz servi, ou nil.
Notes.frequencyProvider = nil

-- Définition d'une note d'après sa déclaration : type d'objet, clés de traduction, identifiant printMedia, et pour
-- une note écrite dans la fiche son texte (written, lignes séparées par un saut de ligne).
local function definition(decl)
    local written = type(decl.text) == "table" and #decl.text > 0 and table.concat(decl.text, "\n") or nil
    local fullType = written and Notes.GENERIC_ITEM or decl.item
    local module, itemType = string.match(fullType, "^([^%.]+)%.(.+)$")
    local id = written and GENERIC_ID or (module .. "_" .. decl.key)
    return { voice = decl.voice, type = itemType, fullType = fullType, id = id, written = written,
        titleKey = "Print_Media_" .. id .. "_title", infoKey = "Print_Media_" .. id .. "_info",
        textKey = "Print_Text_" .. id .. "_info", loot = decl.loot or {}, glovebox = decl.glovebox or {} }
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

-- Données de la ModData d'une note neuve : clés de traduction, voix, fréquence si l'autorité la connaît, texte d'une
-- note écrite dans la fiche.
function Notes.newData(def)
    local khz = nil
    if Notes.frequencyProvider then khz = tonumber(Notes.frequencyProvider(def.voice)) end
    return {
        printMedia = { id = def.id, title = def.titleKey, info = def.infoKey, text = def.textKey },
        note = { voice = def.voice, khz = khz, text = def.written },
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

-- Mise en page d'une note écrite dans la fiche (E22-T07) : page de papier jauni, une ligne manuscrite (SdfCaveat,
-- légèrement inclinée) par ligne du texte, sans retour à la ligne automatique (lignes de 40 octets au plus, contrôlées
-- par RS_Persona) ; la hauteur suit le nombre de lignes.
local PAGE_WIDTH, PAGE_MARGIN, LINE_HEIGHT = 560, 40, 48

local function withFrequency(line, label)
    return (string.gsub(line, "%%1", function() return label end))
end

-- Mise en page (info) et transcription (text) du texte written, %1 remplacé par label.
function Notes.composeWritten(written, label)
    local lines = {}
    for line in string.gmatch(written, "[^\n]+") do lines[#lines + 1] = withFrequency(line, label) end
    local height = PAGE_MARGIN * 2 + #lines * LINE_HEIGHT
    local parts = {
        "<type:parent, width:" .. PAGE_WIDTH .. ", height:" .. height .. ">",
        "<type:texture, x:0, y:0, width:" .. PAGE_WIDTH .. ", height:" .. height .. ", r:0.86, g:0.84, b:0.78, a:1>",
        "<type:texture, x:0, y:0, width:" .. PAGE_WIDTH .. ", height:12, r:0.7, g:0.68, b:0.62, a:0.8>",
    }
    for i, line in ipairs(lines) do
        local y = PAGE_MARGIN + (i - 1) * LINE_HEIGHT
        parts[#parts + 1] = "<type:text, font:SdfCaveat, x:" .. PAGE_MARGIN .. ", y:" .. y
            .. ", scaleX:1, scaleY:1, angle:-2, r:0.28, g:0.27, b:0.26, a:0.95>" .. line
    end
    return table.concat(parts), table.concat(lines, "\n")
end

-- Mise en page et transcription dans la langue courante, fréquence comprise, ou nil (autre document). Note écrite
-- dans la fiche : son texte, tel que l'auteur l'a écrit.
function Notes.compose(modData)
    if not Notes.isNote(modData) then return nil end
    local printMedia, note = modData.printMedia, modData[Notes.MODDATA_KEY]
    local label = Notes.frequencyLabel(note)
    if type(note.text) == "string" then return Notes.composeWritten(note.text, label) end
    return getText(printMedia.info, label), getText(printMedia.text, label)
end

-- Fonction globale citée par les scripts d'objets (résolue par son nom pointé, LuaManager.getFunctionObject).
RadioSurvivorNotes = RadioSurvivorNotes or {}
RadioSurvivorNotes.onCreate = function(item) Notes.onCreate(item) end

return Notes
