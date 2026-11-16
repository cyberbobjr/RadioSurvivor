-- Radio Survivor : socle commun des notes de frequence (E24-T03, decision utilisateur 2026-11-16). Donnees seules.
--
-- Toute voix qui declare une note ([note] de sa fiche) est cachee ici par le jeu, sans ligne dans sa fiche :
--   - loot : listes procedurales vanilla 42.22 ou l'on trouve deja des papiers (Paperwork, Note, Notepad,
--     LetterHandwritten, SheetPaper2...), citees par des salles (Distributions.lua) ; poids de base par voix, environ
--     la chance en % par tirage, avant le facteur NoteRarity et les reglages de butin du sandbox ;
--   - glovebox : boite a gants des voitures ordinaires (VehicleDistributions.GloveBox) ;
--   - corpseChance : chance (%) qu'un zombie mort porte une note, toutes voix confondues ;
--   - walkieCorpseChance : la meme chance pour un zombie qui porte un talkie emetteur.
-- Une ligne loot= ou glovebox= de la fiche ajoute sa liste a theme ; sur une liste du socle, elle n'en garde que le
-- poids le plus fort. Choix des listes et calcul : docs/specifications-techniques/notes-frequences.md.
-- Seul l'ASCII est utilise dans le code (lexeur Kahlua).

local Base = {}

Base.loot = {
    { list = "OfficeDesk", weight = 0.1 },
    { list = "OfficeDeskHome", weight = 0.1 },
    { list = "OfficeDeskHomeClassy", weight = 0.1 },
    { list = "OfficeDeskSecretary", weight = 0.1 },
    { list = "OfficeDeskStressed", weight = 0.1 },
    { list = "OfficeDrawers", weight = 0.1 },
    { list = "FilingCabinetGeneric", weight = 0.1 },
    { list = "BedroomSidetable", weight = 0.1 },
    { list = "KitchenRandom", weight = 0.1 },
    { list = "PostOfficeSupplies", weight = 0.1 },
    { list = "PoliceDesk", weight = 0.1 },
    { list = "ClassroomDesk", weight = 0.1 },
}

Base.glovebox = {
    { list = "GloveBox", weight = 0.5 },
}

Base.corpseChance = 2
Base.walkieCorpseChance = 35

return Base
