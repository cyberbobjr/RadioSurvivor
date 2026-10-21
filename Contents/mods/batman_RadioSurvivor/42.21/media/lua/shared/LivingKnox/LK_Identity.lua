-- Living Knox : identité des PNJ, logique pure (aucun appel au moteur). Fiche : docs/annexes/conception/corps-registre.md.
--
-- Registre (schéma 2), persisté par LK_Store (fichier serveur) :
--   { schema = 2, nextId = <prochain numéro>, npcs = { ["lk-<n>"] = npc } }
--   npc = { id = "lk-<n>", generation = <incarnations>, state = "virtual" | "embodied" | "dead",
--           profile = profil d'apparence RÉSOLU (LK_Appearance : female, outfit, preset, look, skin, hair,
--                     hairColor, beard, variant), tiré une fois pour toutes avec le numéro du PNJ pour graine,
--           want = { x, y, z } (position voulue), last = { x, y, z } (dernière position vue, ou absent),
--           weapon = "<Module>.<Objet>" (arme portée, LK_Equipment, LK02-T06 ; champ facultatif : un registre
--                    écrit avant reste valide sans changement de schéma),
--           clothes = vêtements concrets relevés sur le premier corps et rejoués aux suivants (LK_Appearance,
--                     LK02-T12 ; champ facultatif, même règle que weapon : la version précédente l'accepte sans le
--                     lire, car validate ne refuse aucun champ de PNJ inconnu),
--           death = cause de la mort du dernier corps (LK_Bodies, E04-T06 ; champ facultatif, même règle) :
--                   { cause = "melee" | "firearm" | "fire" | "vehicle" | "other" | "unknown",
--                     killer = compte du joueur ou absent, weapon = "<Module>.<Objet>" ou absent, burning = vrai ou absent },
--           hp = santé acceptée du dernier corps quand il a été retiré loin des joueurs (LK_Bodies.release, LK03-T04 ;
--                champ facultatif, même règle ; 0..Identity.HP_MAX),
--           hpMax = santé du corps courant à sa naissance, juste après la réanimation (robustesse du moteur), référence
--                   de la conversion santé <-> blessure abstraite du membre de groupe (LK_Materialize, LK09-T03 ;
--                   champ facultatif, même règle ; ]0..Identity.HP_MAX]),
--           bleed = saignement (fraction de hpMax perdue par heure de jeu, LK_Health, LK07-T03 ; champ facultatif,
--                   même règle ; absent = aucun saignement ; une valeur fausse est lue comme absente) }
-- Schéma 1 (LK02-T02, profile = { female, outfit, preset }) : relu puis migré (Identity.upgrade) ; sexe et tenue
-- gardés, le reste tiré avec le numéro du PNJ. Un corps déjà présent garde son ancienne apparence jusqu'à sa
-- prochaine incarnation.
-- Un identifiant n'est jamais réutilisé (nextId ne recule pas, même après l'oubli d'un PNJ).
-- Chaque nouveau corps d'un PNJ incrémente sa génération ; le corps porte dans ses ModData l'identifiant et la
-- génération de son incarnation (Identity.KEY_ID, Identity.KEY_GEN).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Appearance"

local Identity = LivingKnox.Identity or {}
LivingKnox.Identity = Identity

Identity.SCHEMA = 2
Identity.ID_PREFIX = "lk-"
Identity.KEY_ID = "lkNpcId"
Identity.KEY_GEN = "lkNpcGen"

Identity.STATE_VIRTUAL = "virtual"
Identity.STATE_EMBODIED = "embodied"
Identity.STATE_DEAD = "dead"
Identity.STATES = { virtual = true, embodied = true, dead = true }

local function Appearance() return LivingKnox.Appearance end

-- Tenues et préréglages : voir LK_Appearance.
Identity.OUTFITS = LivingKnox.Appearance.OUTFITS
Identity.DEFAULT_OUTFIT = LivingKnox.Appearance.DEFAULT_OUTFIT
Identity.PRESETS = LivingKnox.Appearance.PRESETS
Identity.DEFAULT_PRESET = LivingKnox.Appearance.DEFAULT_PRESET

-- Classement d'un corps étiqueté par rapport au registre (Identity.classify).
Identity.CURRENT = "current"        -- génération courante d'un PNJ incarné : corps légitime
Identity.STALE = "stale"            -- génération antérieure : ancien corps
Identity.AHEAD = "ahead"            -- génération postérieure au registre : incarnation inconnue
Identity.UNKNOWN = "unknown"        -- identifiant absent du registre
Identity.NOT_EMBODIED = "notEmbodied" -- PNJ connu mais virtuel ou mort : aucun corps attendu
Identity.UNTAGGED = "untagged"      -- pas d'étiquette Living Knox

local function isInteger(v)
    return type(v) == "number" and v == v and v >= 0 and math.floor(v) == v and v < 2147483648
end

function Identity.newRegistry()
    return { schema = Identity.SCHEMA, nextId = 1, npcs = {} }
end

function Identity.formatId(n)
    return Identity.ID_PREFIX .. tostring(n)
end

-- Numéro d'un identifiant "lk-<n>" (nil si le format est faux).
function Identity.idNumber(id)
    if type(id) ~= "string" then return nil end
    local digits = string.match(id, "^lk%-(%d+)$")
    if not digits or #digits > 9 then return nil end
    return tonumber(digits)
end

function Identity.isId(id)
    local n = Identity.idNumber(id)
    return n ~= nil and n >= 1
end

local function isPosition(p)
    return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
        and p.x == p.x and p.y == p.y and p.z == p.z
end
Identity.isPosition = isPosition

function Identity.position(x, y, z)
    return { x = x, y = y, z = z }
end

-- Type d'objet complet "<Module>.<Objet>" (lettres, chiffres, soulignés), forme seulement : l'existence de l'objet
-- se vérifie avec le moteur (LK_Equipment).
function Identity.isItemType(v)
    return type(v) == "string" and #v <= 128 and string.match(v, "^[%w_]+%.[%w_]+$") ~= nil
end

-- zombie, bleeding : LK07-T04 (attaquant zombie vanilla ; perte de sang, LK07-T03), sans tueur.
Identity.DEATH_CAUSES = { melee = true, firearm = true, fire = true, vehicle = true, other = true, unknown = true,
    zombie = true, bleeding = true }

-- Cause de mort relue (champ npc.death) : vrai, ou faux et une raison.
function Identity.validDeath(d)
    if type(d) ~= "table" then return false, "death is not a table" end
    if not Identity.DEATH_CAUSES[d.cause] then return false, "bad death cause" end
    if d.killer ~= nil and (type(d.killer) ~= "string" or d.killer == "" or #d.killer > 128) then
        return false, "bad killer"
    end
    if d.weapon ~= nil and not Identity.isItemType(d.weapon) then return false, "bad death weapon" end
    if d.burning ~= nil and d.burning ~= true then return false, "bad burning flag" end
    return true
end

-- Santé d'un corps gardée au registre (champ npc.hp) : nombre fini de 0 à HP_MAX (= LivingKnox.Config.REPORTS.HP_MAX,
-- short x 1000 du paquet zombie, docs/annexes/conception/sante.md).
Identity.HP_MAX = 32.767

function Identity.validHealth(v)
    return type(v) == "number" and v == v and v >= 0 and v <= Identity.HP_MAX
end

-- Profil d'apparence résolu et validé (copie), ou nil et une raison : voir Appearance.normalize. seed = numéro du
-- PNJ (défaut 1) ; un profil déjà complet ne dépend pas de la graine.
function Identity.normalizeProfile(profile, seed)
    return Appearance().normalize(profile, seed)
end

-- Nouveau PNJ virtuel (génération 0) ajouté au registre. Rend le PNJ, ou nil et une raison.
-- Le profil est résolu avec le numéro du PNJ pour graine : même entrée, même apparence pour un numéro donné.
function Identity.create(registry, profile, x, y, z)
    local p, why = Identity.normalizeProfile(profile, registry.nextId)
    if not p then return nil, why end
    local want = Identity.position(x, y, z)
    if not isPosition(want) then return nil, "position must be three numbers" end
    local id = Identity.formatId(registry.nextId)
    if registry.npcs[id] ~= nil then return nil, "identifier " .. id .. " already used (registry corrupted)" end
    registry.nextId = registry.nextId + 1
    local npc = { id = id, generation = 0, state = Identity.STATE_VIRTUAL, profile = p, want = want }
    registry.npcs[id] = npc
    return npc
end

function Identity.get(registry, id)
    if type(id) ~= "string" then return nil end
    return registry.npcs[id]
end

-- Retire un PNJ du registre ; son numéro n'est jamais réattribué.
function Identity.forget(registry, id)
    local npc = registry.npcs[id]
    registry.npcs[id] = nil
    return npc
end

-- Génération que portera le prochain corps du PNJ (sans la valider).
function Identity.nextGeneration(npc)
    return npc.generation + 1
end

-- Le PNJ a reçu un corps de génération gen.
function Identity.markEmbodied(npc, generation)
    npc.generation = generation
    npc.state = Identity.STATE_EMBODIED
end

function Identity.markVirtual(npc)
    npc.state = Identity.STATE_VIRTUAL
end

function Identity.markDead(npc)
    npc.state = Identity.STATE_DEAD
end

-- Étiquette posée dans une table de ModData (corps, cadavre).
function Identity.writeTag(modData, id, generation)
    modData[Identity.KEY_ID] = id
    modData[Identity.KEY_GEN] = generation
end

function Identity.clearTag(modData)
    modData[Identity.KEY_ID] = nil
    modData[Identity.KEY_GEN] = nil
end

-- Identifiant et génération d'une table de ModData, ou nil (étiquette absente ou malformée).
function Identity.readTag(modData)
    if type(modData) ~= "table" then return nil end
    local id, generation = modData[Identity.KEY_ID], modData[Identity.KEY_GEN]
    if not Identity.isId(id) or not isInteger(generation) or generation < 1 then return nil end
    return id, generation
end

-- Classement d'un corps étiqueté (id, generation) : voir les constantes en tête ; rend aussi le PNJ s'il existe.
function Identity.classify(registry, id, generation)
    if id == nil then return Identity.UNTAGGED end
    local npc = registry.npcs[id]
    if npc == nil then return Identity.UNKNOWN end
    if npc.state ~= Identity.STATE_EMBODIED then return Identity.NOT_EMBODIED, npc end
    if generation < npc.generation then return Identity.STALE, npc end
    if generation > npc.generation then return Identity.AHEAD, npc end
    return Identity.CURRENT, npc
end

-- Contrôle d'un registre relu. Rend le registre, ou nil, une raison et "schema" quand le schéma est inconnu
-- (refus : fichier d'une autre version du mod) ou "invalid" quand la structure est fausse.
function Identity.validate(data)
    if type(data) ~= "table" then return nil, "registry is not a table", "invalid" end
    if data.schema ~= Identity.SCHEMA then
        return nil, "unknown registry schema " .. tostring(data.schema) .. " (this version reads "
            .. Identity.SCHEMA .. ")", "schema"
    end
    if not isInteger(data.nextId) or data.nextId < 1 then return nil, "bad nextId", "invalid" end
    if type(data.npcs) ~= "table" then return nil, "npcs is not a table", "invalid" end
    for id, npc in pairs(data.npcs) do
        local n = Identity.idNumber(id)
        if not n or n < 1 or n >= data.nextId then return nil, "bad npc identifier " .. tostring(id), "invalid" end
        if type(npc) ~= "table" or npc.id ~= id then return nil, "npc " .. id .. ": id mismatch", "invalid" end
        if not isInteger(npc.generation) then return nil, "npc " .. id .. ": bad generation", "invalid" end
        if not Identity.STATES[npc.state] then return nil, "npc " .. id .. ": bad state", "invalid" end
        if npc.state == Identity.STATE_EMBODIED and npc.generation < 1 then
            return nil, "npc " .. id .. ": embodied without a generation", "invalid"
        end
        local p, bad = Identity.normalizeProfile(npc.profile, n)
        if not p or not Appearance().same(p, npc.profile) then
            return nil, "npc " .. id .. ": bad profile" .. (bad and (" (" .. bad .. ")") or " (incomplete)"), "invalid"
        end
        if not isPosition(npc.want) then return nil, "npc " .. id .. ": bad wanted position", "invalid" end
        if npc.last ~= nil and not isPosition(npc.last) then
            return nil, "npc " .. id .. ": bad last position", "invalid"
        end
        if npc.weapon ~= nil and not Identity.isItemType(npc.weapon) then
            return nil, "npc " .. id .. ": bad weapon type", "invalid"
        end
        if npc.clothes ~= nil then
            local clothesOk, clothesWhy = Appearance().validClothes(npc.clothes)
            if not clothesOk then return nil, "npc " .. id .. ": " .. clothesWhy, "invalid" end
        end
        if npc.hp ~= nil and not Identity.validHealth(npc.hp) then
            return nil, "npc " .. id .. ": bad health", "invalid"
        end
        if npc.hpMax ~= nil and (not Identity.validHealth(npc.hpMax) or npc.hpMax <= 0) then
            return nil, "npc " .. id .. ": bad full health", "invalid"
        end
        if npc.death ~= nil then
            local deathOk, deathWhy = Identity.validDeath(npc.death)
            if not deathOk then return nil, "npc " .. id .. ": " .. deathWhy, "invalid" end
        end
    end
    return data
end

-- Migration d'un registre relu vers le schéma courant, en place, avant Identity.validate. Rend le schéma d'origine
-- si une migration a eu lieu, sinon nil (déjà au schéma courant, ou structure laissée telle quelle : validate la
-- refusera). Schéma 1 -> 2 : profil { female, outfit, preset } résolu avec le numéro du PNJ pour graine (sexe et
-- tenue gardés) ; un profil schéma 1 faux est laissé tel quel (refusé par validate).
function Identity.upgrade(data)
    if type(data) ~= "table" or data.schema ~= 1 or type(data.npcs) ~= "table" then return nil end
    local ids = {}
    for id in pairs(data.npcs) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local npc = data.npcs[id]
        local n = Identity.idNumber(id)
        local old = type(npc) == "table" and npc.profile or nil
        if n and type(old) == "table" then
            local legacy = true
            for key in pairs(old) do
                if key ~= "female" and key ~= "outfit" and key ~= "preset" then legacy = false end
            end
            local p = legacy and Identity.normalizeProfile({ female = old.female == true, outfit = old.outfit,
                preset = old.preset }, n)
            if p and type(old.female) == "boolean" then npc.profile = p end
        end
    end
    data.schema = Identity.SCHEMA
    return 1
end

-- Identifiants triés par numéro.
function Identity.sortedIds(registry)
    local ids = {}
    for id in pairs(registry.npcs) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return Identity.idNumber(a) < Identity.idNumber(b) end)
    return ids
end

return Identity
