-- Living Knox : registre des types de groupes et des profils de membres (LK08-T02). Fiche : docs/annexes/conception/groupes.md,
-- section « Types et profils ».
--
-- Un type se déclare dans un fichier de données Lua, sans code : le fichier appelle LivingKnox.GroupTypes.register{...}
-- au chargement. Le jeu exécute d'office chaque fichier de media/lua/shared de chaque mod actif (LuaManager.LoadDirBase,
-- ordre alphabétique insensible à la casse dans un mod, mods dans l'ordre de chargement), avant media/lua/server et
-- avant OnInitGlobalModData (relecture du registre des groupes) : un fichier de données commence donc par
-- require "LivingKnox/LK_GroupTypes" (il peut être lu avant ce fichier-ci, y compris depuis un autre mod).
-- Types livrés : media/lua/shared/LivingKnox/Data/LK_Type_<id>.lua. Un autre mod ajoute un type par un seul fichier
-- (chemin propre à ce mod) : voir la fiche.
--
-- Définition (format 1 ; tout champ inconnu, à tout niveau, la fait refuser) :
--   { format = 1, id = <minuscules, chiffres, soulignés ; 24 au plus>, nameKey = <clé de traduction du nom affiché>,
--     size = { min, max } (1 <= min <= max <= SIZE_MAX), hostility = 0..100 (hostilité de départ envers les joueurs),
--     home = "building" | "forest" (foyer préféré), morale = 0..100, needs = { food, medical, ammo } (0..100),
--     roles = { [<rôle de Config.GROUP_ROLES>] = { weight = 1..100, behaviours = { <nom de BEHAVIOURS>, ... } } },
--     profiles = { { id, role (un rôle de roles), weight = 1..1000 (rareté : petit = rare), max = 1..SIZE_MAX
--                    (facultatif : au plus max membres de ce profil par groupe), female = booléen (facultatif),
--                    looks = { <profil d'apparence LK_Appearance.LOOKS> } (facultatif : tous ceux du sexe),
--                    outfits = { <tenue LK_Appearance.OUTFITS> } (facultatif : toutes),
--                    weapons = { "<Module>.<Objet>" } (facultatif : sans arme),
--                    traits = { { id = <nom de TRAITS>, chance = 1..100 (pour cent) } } (facultatif) }, ... } }
-- Format 2 (E08-T06) = format 1 plus deux champs facultatifs de poste émetteur (radio du groupe, voix du réseau radio
-- de RadioSurvivor) : homeRadio = booléen au niveau du type (le foyer porte un poste : tout membre vivant présent au
-- foyer peut répondre) et radio = booléen dans un profil (chaque membre de ce profil porte un talkie, même en
-- expédition). En format 1, ces champs sont inconnus, donc refusés comme tout autre champ. Les deux formats sont lus.
-- Un rôle = la liste de ses comportements permis (I1.2), par leur nom seulement : LK05-T02 les implémentera. Les
-- besoins vitaux (dormir, manger, boire, fuir) ne sont pas des comportements de rôle : ils valent pour tous.
-- Définition invalide : refusée et journalisée, les autres gardées. Identifiant déjà enregistré : refusé.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Appearance"
require "LivingKnox/LK_Identity"

local GroupTypes = LivingKnox.GroupTypes or {}
LivingKnox.GroupTypes = GroupTypes

GroupTypes.FORMAT = 2               -- format courant ; FORMATS : formats lus (E08-T06)
GroupTypes.FORMATS = { [1] = true, [2] = true }
GroupTypes.ID_MAX = 24
GroupTypes.KEY_MAX = 64
GroupTypes.SIZE_MAX = 32            -- = LivingKnox.Groups.MAX_MEMBERS (serveur) ; vérifié par le banc
GroupTypes.LEVEL_MAX = 100
GroupTypes.ROLE_WEIGHT_MAX = 100
GroupTypes.PROFILE_WEIGHT_MAX = 1000
GroupTypes.MAX_PROFILES = 32
GroupTypes.MAX_LIST = 16            -- entrées au plus d'une liste (comportements, apparences, tenues, armes, traits)
GroupTypes.NEEDS = { "food", "medical", "ammo" }   -- = LivingKnox.Groups.NEEDS
GroupTypes.HOMES = { building = true, forest = true }

-- Comportements de rôle (noms réservés, aucun n'est implémenté ici ; LK05-T02 et suivantes).
GroupTypes.BEHAVIOURS = {
    guard = true, patrol = true, defend = true, fight = true, -- garde, rondes, défense du foyer, combat
    scout = true, expedition = true, scavenge = true,          -- éclaireur (I6.9), sorties, fouille
    forage = true, fish = true, garden = true, cook = true,    -- nourriture (LK05-T11, LK05-T07)
    heal = true, maintain = true, chores = true, fortify = true, -- soins, entretien, corvées, fortification
    breach = true, raid = true,                                -- casseur de barricades (I6.9), pillage
    trade = true, talk = true,                                 -- échanges et parole avec les joueurs (LK11)
}

-- Traits rares (I8.1), noms réservés : leurs effets (gestes, besoins, répliques) viendront avec LK05 et LK10.
GroupTypes.TRAITS = { smoker = true, drinker = true, tidy = true, nervous = true, keenHearing = true, strong = true }

-- Armes vanilla admises dans le module Base : objets relevés dans media/scripts/generated/items/weapon.txt (42.21),
-- chacun avec un AttachmentType connu de LivingKnox.Equipment.LOCATIONS (contrôlé par tests/test_lk_group_types.py).
-- Une arme d'un autre module (mod d'armes) n'est contrôlée que par sa forme ici, puis par Equipment.spec à l'usage.
GroupTypes.VANILLA_WEAPONS = {
    ["Base.Shotgun"] = true, ["Base.HuntingRifle"] = true, ["Base.VarmintRifle"] = true,
    ["Base.AssaultRifle"] = true, ["Base.Pistol"] = true, ["Base.Pistol2"] = true, ["Base.Revolver"] = true,
    ["Base.Revolver_Short"] = true, ["Base.BaseballBat"] = true, ["Base.HandAxe"] = true, ["Base.Axe"] = true,
    ["Base.WoodAxe"] = true, ["Base.KitchenKnife"] = true, ["Base.HuntingKnife"] = true, ["Base.Hammer"] = true,
    ["Base.Shovel"] = true, ["Base.Machete"] = true, ["Base.Crowbar"] = true, ["Base.Sledgehammer"] = true,
    ["Base.Wrench"] = true, ["Base.PipeWrench"] = true, ["Base.Nightstick"] = true, ["Base.MeatCleaver"] = true,
    ["Base.LeadPipe"] = true, ["Base.Plank"] = true, ["Base.SpearCrafted"] = true, ["Base.PickAxe"] = true,
}

GroupTypes.state = GroupTypes.state or { types = {}, refused = {} }

local function log() return LivingKnox.Log end

local TYPE_FIELDS = { format = true, id = true, nameKey = true, size = true, hostility = true, home = true,
    morale = true, needs = true, roles = true, profiles = true }
local ROLE_FIELDS = { weight = true, behaviours = true }
local PROFILE_FIELDS = { id = true, role = true, weight = true, max = true, female = true, looks = true,
    outfits = true, weapons = true, traits = true }
-- Champs ajoutés par le format 2 (E08-T06) : poste émetteur du foyer (type) ou porté par un profil.
local TYPE_FIELDS_2 = { homeRadio = true }
local PROFILE_FIELDS_2 = { radio = true }
for key in pairs(TYPE_FIELDS) do TYPE_FIELDS_2[key] = true end
for key in pairs(PROFILE_FIELDS) do PROFILE_FIELDS_2[key] = true end
local TRAIT_FIELDS = { id = true, chance = true }
local SIZE_FIELDS = { min = true, max = true }

-- Contrôles de base ------------------------------------------------------------------------------------------------

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function isId(v)
    return type(v) == "string" and #v >= 1 and #v <= GroupTypes.ID_MAX and string.match(v, "^%l[%l%d_]*$") ~= nil
end

local function isKey(v)
    return type(v) == "string" and #v >= 1 and #v <= GroupTypes.KEY_MAX and string.match(v, "^%a[%w_]*$") ~= nil
end

-- Nom du premier champ de t absent de allowed, ou nil.
local function unknownField(t, allowed)
    for key in pairs(t) do
        if not allowed[key] then return tostring(key) end
    end
    return nil
end

local function roleKnown(role)
    for _, v in ipairs(LivingKnox.Config.GROUP_ROLES) do
        if v == role then return true end
    end
    return false
end

-- Liste Lua de 1 à MAX_LIST entrées (indices 1..n sans trou ni autre clé) : rend n, ou nil et une raison.
local function listSize(list, what)
    if type(list) ~= "table" then return nil, what .. " is not a list" end
    local n = 0
    for key in pairs(list) do
        if not isInt(key, 1, GroupTypes.MAX_LIST) then return nil, what .. " is not a list of 1 to " .. GroupTypes.MAX_LIST end
        n = n + 1
    end
    if n < 1 or list[n] == nil then return nil, what .. " is not a list of 1 to " .. GroupTypes.MAX_LIST end
    return n
end

-- Liste de noms tous distincts, chacun accepté par ok(name) : rend une copie, ou nil et une raison.
local function nameList(list, what, ok)
    local n, why = listSize(list, what)
    if not n then return nil, why end
    local out, seen = {}, {}
    for i = 1, n do
        local name = list[i]
        local fine, reason = ok(name)
        if not fine then return nil, what .. " entry " .. i .. ": " .. (reason or ("unknown " .. tostring(name))) end
        if seen[name] then return nil, what .. " entry " .. i .. ": duplicate " .. name end
        seen[name] = true
        out[i] = name
    end
    return out
end

local function behaviourOk(name)
    return type(name) == "string" and GroupTypes.BEHAVIOURS[name] == true
end

local function outfitOk(name)
    return type(name) == "string" and LivingKnox.Appearance.OUTFITS[name] == true
end

-- Arme admise : forme "<Module>.<Objet>" ; dans le module Base, objet vanilla relevé (VANILLA_WEAPONS).
function GroupTypes.weaponOk(name)
    if not LivingKnox.Identity.isItemType(name) then return false, "bad item type " .. tostring(name) end
    if string.sub(name, 1, 5) == "Base." and not GroupTypes.VANILLA_WEAPONS[name] then
        return false, "vanilla weapon not allowed " .. name
    end
    return true
end

-- Contrôle d'une définition ---------------------------------------------------------------------------------------

local function validRoles(roles)
    if type(roles) ~= "table" then return nil, "roles is not a table" end
    local out, count = {}, 0
    for role, r in pairs(roles) do
        if not roleKnown(role) then return nil, "unknown role " .. tostring(role) end
        if type(r) ~= "table" then return nil, "role " .. role .. " is not a table" end
        local extra = unknownField(r, ROLE_FIELDS)
        if extra then return nil, "role " .. role .. ": unknown field " .. extra end
        if not isInt(r.weight, 1, GroupTypes.ROLE_WEIGHT_MAX) then
            return nil, "role " .. role .. ": weight must be an integer from 1 to " .. GroupTypes.ROLE_WEIGHT_MAX
        end
        local behaviours, why = nameList(r.behaviours, "role " .. role .. " behaviours", behaviourOk)
        if not behaviours then return nil, why end
        out[role] = { weight = r.weight, behaviours = behaviours }
        count = count + 1
    end
    if count == 0 then return nil, "roles is empty" end
    return out
end

local function validTraits(list, where)
    local n, why = listSize(list, where .. " traits")
    if not n then return nil, why end
    local out, seen = {}, {}
    for i = 1, n do
        local t = list[i]
        local at = where .. " trait " .. i
        if type(t) ~= "table" then return nil, at .. " is not a table" end
        local extra = unknownField(t, TRAIT_FIELDS)
        if extra then return nil, at .. ": unknown field " .. extra end
        if type(t.id) ~= "string" or not GroupTypes.TRAITS[t.id] then return nil, at .. ": unknown trait " .. tostring(t.id) end
        if seen[t.id] then return nil, at .. ": duplicate " .. t.id end
        if not isInt(t.chance, 1, 100) then return nil, at .. ": chance must be an integer from 1 to 100" end
        seen[t.id] = true
        out[i] = { id = t.id, chance = t.chance }
    end
    return out
end

local function validProfile(p, i, roles, format)
    local where = "profile " .. i
    if type(p) ~= "table" then return nil, where .. " is not a table" end
    if isId(p.id) then where = "profile " .. p.id end
    local extra = unknownField(p, format == 2 and PROFILE_FIELDS_2 or PROFILE_FIELDS)
    if extra then return nil, where .. ": unknown field " .. extra end
    if not isId(p.id) then return nil, where .. ": bad id" end
    if type(p.role) ~= "string" or roles[p.role] == nil then
        return nil, where .. ": role " .. tostring(p.role) .. " is not a role of this type"
    end
    if not isInt(p.weight, 1, GroupTypes.PROFILE_WEIGHT_MAX) then
        return nil, where .. ": weight must be an integer from 1 to " .. GroupTypes.PROFILE_WEIGHT_MAX
    end
    if p.max ~= nil and not isInt(p.max, 1, GroupTypes.SIZE_MAX) then
        return nil, where .. ": max must be an integer from 1 to " .. GroupTypes.SIZE_MAX
    end
    if p.female ~= nil and type(p.female) ~= "boolean" then return nil, where .. ": female must be a boolean" end
    if p.radio ~= nil and type(p.radio) ~= "boolean" then return nil, where .. ": radio must be a boolean" end
    local out = { id = p.id, role = p.role, weight = p.weight, max = p.max, female = p.female,
        radio = p.radio == true or nil }
    local why
    if p.looks ~= nil then
        out.looks, why = nameList(p.looks, where .. " looks", function(name)
            local look = type(name) == "string" and LivingKnox.Appearance.look(name) or nil
            if not look then return false end
            if p.female ~= nil and look.female ~= p.female then return false, "look " .. name .. " does not match female" end
            return true
        end)
        if not out.looks then return nil, why end
    end
    if p.outfits ~= nil then
        out.outfits, why = nameList(p.outfits, where .. " outfits", outfitOk)
        if not out.outfits then return nil, why end
    end
    if p.weapons ~= nil then
        out.weapons, why = nameList(p.weapons, where .. " weapons", GroupTypes.weaponOk)
        if not out.weapons then return nil, why end
    end
    if p.traits ~= nil then
        out.traits, why = validTraits(p.traits, where)
        if not out.traits then return nil, why end
    end
    return out
end

-- Définition contrôlée : rend une copie normalisée, ou nil et une raison (anglais). Logique pure.
function GroupTypes.validate(def)
    if type(def) ~= "table" then return nil, "definition is not a table" end
    if not GroupTypes.FORMATS[def.format] then
        return nil, "unknown format " .. tostring(def.format) .. " (this version reads 1 to " .. GroupTypes.FORMAT .. ")"
    end
    local extra = unknownField(def, def.format == 2 and TYPE_FIELDS_2 or TYPE_FIELDS)
    if extra then return nil, "unknown field " .. extra end
    if def.homeRadio ~= nil and type(def.homeRadio) ~= "boolean" then return nil, "homeRadio must be a boolean" end
    if not isId(def.id) then return nil, "bad id" end
    if not isKey(def.nameKey) then return nil, "bad nameKey" end
    local size = def.size
    if type(size) ~= "table" or unknownField(size, SIZE_FIELDS) or not isInt(size.min, 1, GroupTypes.SIZE_MAX)
        or not isInt(size.max, size.min, GroupTypes.SIZE_MAX) then
        return nil, "size must be { min, max } integers with 1 <= min <= max <= " .. GroupTypes.SIZE_MAX
    end
    if not isInt(def.hostility, 0, GroupTypes.LEVEL_MAX) then return nil, "hostility must be an integer from 0 to 100" end
    if type(def.home) ~= "string" or not GroupTypes.HOMES[def.home] then
        return nil, "home must be building or forest"
    end
    if not isInt(def.morale, 0, GroupTypes.LEVEL_MAX) then return nil, "morale must be an integer from 0 to 100" end
    if type(def.needs) ~= "table" then return nil, "needs is not a table" end
    local needs, allowed = {}, {}
    for _, key in ipairs(GroupTypes.NEEDS) do
        allowed[key] = true
        if not isInt(def.needs[key], 0, GroupTypes.LEVEL_MAX) then return nil, "need " .. key .. " must be 0..100" end
        needs[key] = def.needs[key]
    end
    extra = unknownField(def.needs, allowed)
    if extra then return nil, "unknown need " .. extra end
    local roles, why = validRoles(def.roles)
    if not roles then return nil, why end
    if type(def.profiles) ~= "table" then return nil, "profiles is not a list" end
    local n = 0
    for key in pairs(def.profiles) do
        if not isInt(key, 1, GroupTypes.MAX_PROFILES) then return nil, "profiles is not a list of 1 to 32" end
        n = n + 1
    end
    if n < 1 or def.profiles[n] == nil then return nil, "profiles is not a list of 1 to 32" end
    local profiles, ids, covered = {}, {}, {}
    local unbounded, capacity = false, 0
    for i = 1, n do
        local p
        p, why = validProfile(def.profiles[i], i, roles, def.format)
        if not p then return nil, why end
        if ids[p.id] then return nil, "duplicate profile " .. p.id end
        ids[p.id], covered[p.role] = true, true
        if p.max == nil then unbounded = true else capacity = capacity + p.max end
        profiles[i] = p
    end
    for role in pairs(roles) do
        if not covered[role] then return nil, "role " .. role .. " has no profile" end
    end
    if not unbounded and capacity < size.max then
        return nil, "profiles cannot fill size.max (" .. capacity .. " < " .. size.max .. ")"
    end
    return { format = def.format, id = def.id, nameKey = def.nameKey, size = { min = size.min, max = size.max },
        hostility = def.hostility, home = def.home, morale = def.morale, needs = needs, roles = roles,
        profiles = profiles, homeRadio = def.homeRadio == true or nil }
end

-- Registre ---------------------------------------------------------------------------------------------------------

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Enregistre une définition (appelé par un fichier de données). Rend vrai, ou nil et une raison ; un refus est
-- journalisé (ERROR) et gardé dans state.refused, les types déjà enregistrés restent.
function GroupTypes.register(def)
    local label = type(def) == "table" and isId(def.id) and def.id or "?"
    local t, why = GroupTypes.validate(def)
    if t and GroupTypes.state.types[t.id] then why, t = "identifier already registered", nil end
    if not t then
        local refused = GroupTypes.state.refused
        refused[#refused + 1] = { id = label, why = why }
        log().error("group type %s refused: %s", label, why)
        return nil, why
    end
    GroupTypes.state.types[t.id] = t
    log().info("group type %s registered (%s profile(s))", t.id, tostring(#t.profiles))
    return true
end

function GroupTypes.isKnown(id)
    return type(id) == "string" and GroupTypes.state.types[id] ~= nil
end

-- Copie d'un type enregistré, ou nil.
function GroupTypes.get(id)
    if not GroupTypes.isKnown(id) then return nil end
    return copy(GroupTypes.state.types[id])
end

-- LK13-T11 : type enregistré VIVANT (aucune copie), ou nil. LECTURE SEULE, comme Groups.peek : ne rien écrire dans la
-- table rendue ni dans ses sous-tables, ne pas la garder ni la rendre à un appelant qui ne connaît pas la règle. Pour
-- les lectures fréquentes de quelques champs (passage des membres : comportements d'un rôle, hostilité du type) ; une
-- table à garder ou à modifier : GroupTypes.get (copie profonde, une trentaine par passage avant LK13-T11).
function GroupTypes.peek(id)
    if not GroupTypes.isKnown(id) then return nil end
    return GroupTypes.state.types[id]
end

-- Identifiants des types enregistrés, triés (indépendants de l'ordre de chargement des mods).
function GroupTypes.ids()
    local out = {}
    for id in pairs(GroupTypes.state.types) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-- Définitions refusées depuis le chargement : { { id, why } } (copie).
function GroupTypes.refused()
    return copy(GroupTypes.state.refused)
end

return GroupTypes
