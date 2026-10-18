-- Radio Survivor : ouverture d'un document du mod dans la langue du lecteur : notes de fréquences, fréquence comprise
-- (E05-T09), et journal du dehors, édition comprise (E13-T05).
--
-- Ces documents gardent des clés et des nombres (RS_Notes, RS_OutsideNews). ISReadABook:displayPrintMedia traduit
-- info, text et title sans argument (ISReadABook.lua:252-259, 42.21) : on y place, le temps de l'appel, le texte
-- déjà composé ; getText le renvoie alors tel quel (clé inconnue, Translator.java:363-376). Les clés sont remises
-- ensuite. Seul le journal compose aussi son titre (numéro d'édition) ; son titre stocké reste l'identifiant de
-- l'édition (marque « lu », RS_OutsideNews.lua).
-- startLoadingPrintMediaTextures (ISReadABook.lua:218-247) traduirait la clé sans ses paramètres et journaliserait un
-- argument manquant ; ces mises en page n'ont que des rectangles de couleur, sans image à précharger.
-- Client et solo : perform, qui ouvre le document, ne tourne que côté client.

require "TimedActions/ISReadABook"

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Notes = require "RadioSurvivor/RS_Notes"
local News = require "RadioSurvivor/RS_OutsideNews"

-- E06-T07 : une note de fréquence lisible inscrit la voix et ses heures dans le carnet ; le serveur vérifie l'objet
-- (inventaire du joueur, ModData de l'autorité) avant de l'inscrire.
local function tellNoteRead(action, modData)
    local note = modData[Notes.MODDATA_KEY]
    if type(note) ~= "table" or not tonumber(note.khz) or not action.character or not action.item then return end
    sendClientCommand(action.character, Const.MODULE, Const.CMD.NOTE_READ, { itemId = action.item:getID() })
end

-- Fonctions d'origine conservées sur la table vanilla : un rechargement du fichier n'empile pas une seconde
-- enveloppe. D'autres mods peuvent envelopper les mêmes fonctions : chacun garde la sienne sous un autre nom.
ISReadABook.batmanRadioSurvivorDisplayPrintMedia = ISReadABook.batmanRadioSurvivorDisplayPrintMedia
    or ISReadABook.displayPrintMedia
ISReadABook.batmanRadioSurvivorLoadPrintMediaTextures = ISReadABook.batmanRadioSurvivorLoadPrintMediaTextures
    or ISReadABook.startLoadingPrintMediaTextures

-- ModData et fonction de composition du document du mod lu par l'action, ou nil (autre document).
local function documentOf(action)
    local item = action.item
    if not item or not item:hasModData() then return nil end
    local modData = item:getModData()
    if Notes.forPrintMedia(modData.printMedia) then return modData, Notes.compose end
    if News.isPrintMedia(modData.printMedia) then return modData, News.compose end
    return nil
end

function ISReadABook:startLoadingPrintMediaTextures()
    if documentOf(self) then return nil end
    return ISReadABook.batmanRadioSurvivorLoadPrintMediaTextures(self)
end

function ISReadABook:displayPrintMedia()
    local modData, compose = documentOf(self)
    if modData == nil then
        return ISReadABook.batmanRadioSurvivorDisplayPrintMedia(self)
    end
    local printMedia = modData.printMedia
    local info, text, title = printMedia.info, printMedia.text, printMedia.title
    local newInfo, newText, newTitle = compose(modData)
    if newInfo == nil then
        return ISReadABook.batmanRadioSurvivorDisplayPrintMedia(self)
    end
    printMedia.info, printMedia.text = newInfo, newText
    if newTitle ~= nil then printMedia.title = newTitle end
    -- pcall seulement pour remettre les clés : une erreur de la fenêtre est relancée telle quelle.
    local ok, result = pcall(ISReadABook.batmanRadioSurvivorDisplayPrintMedia, self)
    printMedia.info, printMedia.text, printMedia.title = info, text, title
    if not ok then error(result) end
    if compose == Notes.compose then tellNoteRead(self, modData) end
    return result
end
