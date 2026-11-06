-- Living Knox : apparence humaine des PNJ (LK02-T03). Fiche : docs/annexes/conception/apparence.md.
--
-- Deux parties :
-- * logique pure (aucun appel au moteur) : profils d'apparence en données (Appearance.LOOKS), tirage déterministe
--   d'un profil et d'une variante de tenue à partir d'une graine (le numéro du PNJ), validation et résolution d'un
--   profil complet, enregistré tel quel dans le registre (LK_Identity, schéma 2) pour qu'une réincarnation garde la
--   même apparence même si cette table change dans une version ultérieure ;
-- * Appearance.apply(zombie, profile) : appliquée par l'AUTORITÉ sur le zombie temporaire, avant DoZombieInventory,
--   le cadavre et la réanimation (le descripteur partagé envoyé aux clients est une copie figée à la réanimation,
--   SharedDescriptors.java:44-96). Les clients ne réappliquent rien.
--
-- Profil résolu (tous les champs présents) :
--   { female = bool, outfit = "Generic01".."Generic05", preset = "clean", look = <nom du profil>,
--     skin = "MaleBody01".."05" | "FemaleBody01".."05", hair = <coupe vanilla du sexe>,
--     hairColor = { r, g, b } (entiers 0-255), beard = <barbe vanilla> ou "" (toujours "" pour une femme),
--     variant = 1..500 (graine de la tenue persistante, PersistentOutfits.java:142-160) }
--
-- Vêtements concrets (LK02-T12, champ facultatif npc.clothes du registre) : liste ordonnée des visuels portés,
-- relevée sur le corps à la première incarnation (Appearance.describe) puis rejouée telle quelle aux suivantes
-- (Appearance.apply), au lieu de rejouer la variante : celle-ci ne redonne la même tenue que si la tenue, les sous-
-- vêtements (UnderwearDefinition, tirés avant elle), les vêtements et l'option NoBlackClothes sont inchangés.
--   entrée = { type = "<Module>.<Objet>", item = <nom du ClothingItem>?, alt = <modèle alternatif>?,
--              tint = { r, g, b }? (octets, comme ItemVisual.save), hue = -1..1?, base = 0..127?, choice = 0..127?,
--              decal = <nom>? }
require "LivingKnox/LK_Core"

local Appearance = LivingKnox.Appearance or {}
LivingKnox.Appearance = Appearance

-- Tenues civiles vanilla présentes pour les deux sexes (media/clothing/clothing.xml : Generic01 à Generic05).
Appearance.OUTFITS = { Generic01 = true, Generic02 = true, Generic03 = true, Generic04 = true, Generic05 = true }
Appearance.DEFAULT_OUTFIT = "Generic01"
Appearance.PRESETS = { clean = true }
Appearance.DEFAULT_PRESET = "clean"
Appearance.VARIANTS = 500 -- graines de tenue par partie (z_outfits.bin, PersistentOutfits.java:69-72)

-- Peaux humaines vanilla (PopTemplateManager.java:47-54), de la plus claire (1) à la plus foncée (5) d'après la
-- couleur moyenne de media/textures/Body/<nom>.png.
Appearance.SKINS = {
    male = { "MaleBody01", "MaleBody02", "MaleBody03", "MaleBody04", "MaleBody05" },
    female = { "FemaleBody01", "FemaleBody02", "FemaleBody03", "FemaleBody04", "FemaleBody05" },
}

-- Couleurs de cheveux vanilla de la création de personnage (media/lua/shared/NPCs/MainCreationMethods.lua:6336-6359).
Appearance.HAIR_COLORS = {
    blonde = { r = 212, g = 171, b = 69 },
    lightBrown = { r = 159, g = 108, b = 43 },
    brown = { r = 111, g = 87, b = 60 },
    darkBrown = { r = 56, g = 41, b = 27 },
    black = { r = 27, g = 23, b = 22 },
    grey = { r = 124, g = 120, b = 112 },
    auburn = { r = 134, g = 66, b = 48 },
    reddishBlonde = { r = 190, g = 133, b = 103 },
}

-- Coupes vanilla admises (media/hairStyles/hairStyles.xml, sans les coupes noChoose réservées aux chapeaux).
Appearance.HAIRS = {
    male = { Bald = true, Picard = true, CrewCut = true, Baldspot = true, Recede = true, Messy = true, Short = true,
        Donny = true, Mullet = true, Fabian = true, MessyCurly = true, ShortAfroCurly = true, CentreParting = true,
        LeftParting = true, RightParting = true, Cornrows = true, Fresh = true, FlatTop = true, GreasedBack = true,
        Spike = true, PonyTail = true, Braids = true, Grungey = true },
    female = { Bald = true, Demi = true, Spike = true, OverEye = true, Bob = true, Bun = true, Back = true, Long = true,
        Kate = true, Long2 = true, PonyTail = true, Longcurly = true, BobCurly = true, BunCurly = true, KateCurly = true,
        ShortCurly = true, Rachel = true, CentreParting = true, LeftParting = true, RightParting = true,
        TopCurls = true, Cornrows = true, Braids = true, GreasedBack = true, Fresh = true },
}

-- Barbes vanilla (media/hairStyles/beardStyles.xml) ; "" = rasé (style vide, BeardStyles.java:38 et BeardStyle.name).
Appearance.BEARDS = { [""] = true, Chops = true, Moustache = true, Goatee = true, BeardOnly = true, Full = true,
    Long = true, LongScruffy = true, Chin = true, PointyChin = true }

-- Profils d'apparence (ordre stable : le tirage dépend de la position). Ne jamais retirer ni renommer un profil
-- utilisé : un registre relu garde ses valeurs résolues, mais une copie incomplète exigerait le nom.
Appearance.LOOKS = {
    { name = "manFairBeard", female = false, skin = 1, hair = "Short", hairColor = "brown", beard = "Full",
        outfit = "Generic01" },
    { name = "manDarkGoatee", female = false, skin = 4, hair = "CrewCut", hairColor = "black", beard = "Goatee",
        outfit = "Generic02" },
    { name = "manBlondShaven", female = false, skin = 2, hair = "LeftParting", hairColor = "blonde", beard = "",
        outfit = "Generic03" },
    { name = "manOliveChops", female = false, skin = 3, hair = "Messy", hairColor = "darkBrown", beard = "Chops",
        outfit = "Generic04" },
    { name = "manElderMoustache", female = false, skin = 5, hair = "Recede", hairColor = "grey", beard = "Moustache",
        outfit = "Generic05" },
    { name = "womanFairBun", female = true, skin = 1, hair = "Bun", hairColor = "auburn", outfit = "Generic01" },
    { name = "womanTanBob", female = true, skin = 3, hair = "Bob", hairColor = "lightBrown", outfit = "Generic02" },
    { name = "womanDarkPonytail", female = true, skin = 5, hair = "PonyTail", hairColor = "black",
        outfit = "Generic03" },
    { name = "womanBlondLong", female = true, skin = 2, hair = "Long", hairColor = "blonde", outfit = "Generic04" },
    { name = "womanBrownKate", female = true, skin = 4, hair = "Kate", hairColor = "darkBrown", outfit = "Generic05" },
}

local FIELDS = { female = true, outfit = true, preset = true, look = true, skin = true, hair = true, hairColor = true,
    beard = true, variant = true }

local byName = {}
for _, look in ipairs(Appearance.LOOKS) do byName[look.name] = look end

local function sexKey(female) return female and "female" or "male" end

local function isInteger(v, low, high)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= low and v <= high
end

local function isSkin(name, female)
    for _, s in ipairs(Appearance.SKINS[sexKey(female)]) do
        if s == name then return true end
    end
    return false
end

-- Profil d'apparence par son nom (nil si inconnu).
function Appearance.look(name)
    return byName[name]
end

-- Noms des profils, dans l'ordre de la table ; female = vrai/faux pour un seul sexe, nil pour tous.
function Appearance.lookNames(female)
    local out = {}
    for _, look in ipairs(Appearance.LOOKS) do
        if female == nil or look.female == female then out[#out + 1] = look.name end
    end
    return out
end

-- Tirage reproductible : Park-Miller (sans opérateurs binaires, quotients sous 2^31 en Kahlua), suivi d'un mélange
-- non linéaire (reste modulo 65521) : sans lui, des numéros consécutifs donnent des profils qui se suivent dans
-- la table. seed = numéro du PNJ, salt sépare les tirages indépendants (profil, variante). Six pas de chauffe.
-- Rend draw(n) -> entier de 1 à n.
local M = 2147483647
local function stream(seed, salt)
    local x = (seed * 7919 + salt * 104729 + 1) % M
    if x == 0 then x = 1 end
    local function draw(n)
        x = (x * 48271) % M
        x = (x + (x % 65521) * 31337) % M
        if x == 0 then x = 1 end
        return 1 + math.floor(x / M * n)
    end
    for _ = 1, 6 do draw(1) end
    return draw
end

-- Profil tiré pour une graine, parmi ceux d'un sexe si female est donné.
function Appearance.pickLook(seed, female)
    local names = Appearance.lookNames(female)
    return byName[names[stream(seed, 1)(#names)]]
end

-- Variante de tenue (1..500) tirée pour une graine.
function Appearance.pickVariant(seed)
    return stream(seed, 2)(Appearance.VARIANTS)
end

local function copyColor(c)
    return { r = c.r, g = c.g, b = c.b }
end

local function isColor(c)
    if type(c) ~= "table" then return false end
    for key in pairs(c) do
        if key ~= "r" and key ~= "g" and key ~= "b" then return false end
    end
    return isInteger(c.r, 0, 255) and isInteger(c.g, 0, 255) and isInteger(c.b, 0, 255)
end

local function complete(p)
    return p.female ~= nil and p.outfit ~= nil and p.skin ~= nil and p.hair ~= nil and p.hairColor ~= nil
        and p.beard ~= nil and p.variant ~= nil
end

-- Profil résolu et validé (copie), ou nil et une raison. Entrée : tout sous-ensemble des champs du profil résolu ;
-- un champ absent vient du profil nommé (look) ou, sans look, d'un profil tiré pour seed (parmi ceux du sexe
-- demandé), et la variante d'un tirage sur seed. Un look inconnu n'est admis que si le profil est complet.
function Appearance.normalize(profile, seed)
    if profile == nil then profile = {} end
    if type(profile) ~= "table" then return nil, "profile must be a table" end
    for key in pairs(profile) do
        if not FIELDS[key] then return nil, "unknown profile field " .. tostring(key) end
    end
    if seed == nil then seed = 1 end
    if not isInteger(seed, 0, 999999999) then return nil, "bad appearance seed" end
    local female = profile.female
    if female ~= nil and type(female) ~= "boolean" then return nil, "profile.female must be a boolean" end
    local look
    if profile.look ~= nil then
        if type(profile.look) ~= "string" then return nil, "profile.look must be a string" end
        look = byName[profile.look]
        if look == nil and not complete(profile) then return nil, "unknown look " .. profile.look end
        if look ~= nil and female ~= nil and look.female ~= female then
            return nil, "look " .. profile.look .. " does not match profile.female"
        end
    else
        look = Appearance.pickLook(seed, female)
    end
    if female == nil then female = look.female end
    local base = look or {}
    local p = {
        female = female,
        outfit = profile.outfit or base.outfit or Appearance.DEFAULT_OUTFIT,
        preset = profile.preset or Appearance.DEFAULT_PRESET,
        look = profile.look or look.name,
        skin = profile.skin or (base.skin and Appearance.SKINS[sexKey(female)][base.skin]),
        hair = profile.hair or base.hair,
        beard = profile.beard,
        variant = profile.variant or Appearance.pickVariant(seed),
    }
    if p.beard == nil then p.beard = female and "" or (base.beard or "") end
    local color = profile.hairColor or Appearance.HAIR_COLORS[base.hairColor]
    if not Appearance.OUTFITS[p.outfit] then return nil, "unknown outfit " .. tostring(p.outfit) end
    if not Appearance.PRESETS[p.preset] then return nil, "unknown preset " .. tostring(p.preset) end
    if not isSkin(p.skin, female) then return nil, "skin " .. tostring(p.skin) .. " is not a human skin of this sex" end
    if type(p.hair) ~= "string" or not Appearance.HAIRS[sexKey(female)][p.hair] then
        return nil, "unknown hair " .. tostring(p.hair) .. " for this sex"
    end
    if type(p.beard) ~= "string" or not Appearance.BEARDS[p.beard] then return nil, "unknown beard " .. tostring(p.beard) end
    if female and p.beard ~= "" then return nil, "a woman has no beard" end
    if not isColor(color) then return nil, "hairColor must be { r, g, b } integers from 0 to 255" end
    p.hairColor = copyColor(color)
    if not isInteger(p.variant, 1, Appearance.VARIANTS) then return nil, "variant must be an integer from 1 to 500" end
    return p
end

-- Vrai si deux profils résolus sont identiques.
function Appearance.same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key in pairs(FIELDS) do
        if key ~= "hairColor" and a[key] ~= b[key] then return false end
    end
    for key in pairs(a) do
        if not FIELDS[key] then return false end
    end
    for key in pairs(b) do
        if not FIELDS[key] then return false end
    end
    local ca, cb = a.hairColor, b.hairColor
    return type(ca) == "table" and type(cb) == "table" and ca.r == cb.r and ca.g == cb.g and ca.b == cb.b
end

-- Identifiant de tenue persistante avec une autre variante (graine), sans opérateurs binaires. Format Java
-- (PersistentOutfits.java:170-189) : bit 31 = femme, bits 16-30 = tenue, bit 15 = chapeau tombé, bits 0-14 =
-- variante 1..500. Rend nil si id n'est pas une tenue à graine.
function Appearance.outfitIdWithVariant(id, variant)
    if type(id) ~= "number" or id == 0 or not isInteger(variant, 1, Appearance.VARIANTS) then return nil end
    local raw = id
    if raw < 0 then raw = raw + 2147483648 end
    local current = (raw % 65536) % 32768
    if current < 1 or current > Appearance.VARIANTS then return nil end
    return id - current + variant
end

-- Couleur Java d'un { r, g, b } 0-255. Surcharges ImmutableColor à 4 paramètres : (float x4) et (int x4) ; Kahlua
-- range la surcharge tout-entière en dernier (MultiLuaJavaInvoker.java:19-30), la version float (0-1) est retenue.
-- c / 255 en float, relu par getRedInt et l'octet sauvegardé ((int)(r x 255f), ImmutableColor.java:187-209), rend
-- exactement c pour 0..255 (vérifié en float32 par tests/test_lk_appearance.py).
function Appearance.color(c)
    return ImmutableColor.new(c.r / 255, c.g / 255, c.b / 255, 1)
end

-- Vêtements concrets ------------------------------------------------------------------------------------------

Appearance.MAX_CLOTHES = 64 -- visuels portés au plus (une tenue vanilla en compte moins de 15)
local CLOTHES_FIELDS = { type = true, item = true, alt = true, tint = true, hue = true, base = true, choice = true,
    decal = true }

local function isName(v)
    return type(v) == "string" and #v >= 1 and #v <= 128 and string.find(v, "%s") == nil
end

-- Type d'objet complet "<Module>.<Objet>" (forme seulement ; les vêtements de mods peuvent porter d'autres
-- caractères que LK_Identity.isItemType n'admet pas).
local function isFullType(v)
    return isName(v) and string.match(v, "^[^%.]+%.[^%.].*$") ~= nil
end

-- Raison du refus d'une entrée de vêtement, ou nil si elle est valide.
local function badEntry(e)
    if type(e) ~= "table" then return "entry is not a table" end
    for key in pairs(e) do
        if not CLOTHES_FIELDS[key] then return "unknown field " .. tostring(key) end
    end
    if not isFullType(e.type) then return "bad item type" end
    if e.item ~= nil and not isName(e.item) then return "bad clothing item name" end
    if e.alt ~= nil and not isName(e.alt) then return "bad alternate model" end
    if e.decal ~= nil and not isName(e.decal) then return "bad decal" end
    if e.tint ~= nil and not isColor(e.tint) then return "bad tint" end
    if e.hue ~= nil and (type(e.hue) ~= "number" or not (e.hue >= -1 and e.hue <= 1)) then return "bad hue" end
    if e.base ~= nil and not isInteger(e.base, 0, 127) then return "bad base texture" end
    if e.choice ~= nil and not isInteger(e.choice, 0, 127) then return "bad texture choice" end
    return nil
end

-- Contrôle d'une liste de vêtements relue du registre : rend vrai, ou faux et une raison.
function Appearance.validClothes(list)
    if type(list) ~= "table" then return false, "clothes is not a list" end
    local n = 0
    for key in pairs(list) do
        if not isInteger(key, 1, Appearance.MAX_CLOTHES) then return false, "clothes is not a list" end
        n = n + 1
    end
    if n < 1 then return false, "clothes must list 1 to " .. Appearance.MAX_CLOTHES .. " entries" end
    if list[n] == nil then return false, "clothes is not a list (gap)" end
    for i = 1, n do
        local why = badEntry(list[i])
        if why then return false, "clothes entry " .. i .. ": " .. why end
    end
    return true
end

-- Clé texte d'une entrée : "type|objet|alt|r,g,b|hue|base|choice|decal" ("-" = absent). Le type est le premier champ.
function Appearance.entryKey(e)
    local t = e.tint and (e.tint.r .. "," .. e.tint.g .. "," .. e.tint.b) or "-"
    return tostring(e.type) .. "|" .. tostring(e.item or "-") .. "|" .. tostring(e.alt or "-") .. "|" .. t
        .. "|" .. (e.hue ~= nil and string.format("%.4f", e.hue) or "-") .. "|" .. tostring(e.base or "-")
        .. "|" .. tostring(e.choice or "-") .. "|" .. tostring(e.decal or "-")
end

-- Clés des entrées d'une liste de vêtements, dans l'ordre.
function Appearance.clothesKeys(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for i, e in ipairs(list) do out[i] = Appearance.entryKey(e) end
    return out
end

-- Clé texte d'une liste de vêtements, dans l'ordre (journal ; comparer avec clothesDiff, l'ordre change).
function Appearance.clothesKey(list)
    return table.concat(Appearance.clothesKeys(list), ";")
end

local function keyType(key)
    return string.match(key, "^([^|]*)") or key
end

-- Écart entre deux listes de clés d'entrées (clothesKeys), SANS tenir compte de l'ordre : l'ordre des visuels d'un
-- corps est celui des emplacements du groupe BodyLocations (WornItems.setItem, WornItems.java:57-80), qu'un mod peut
-- réordonner sans rien changer aux vêtements. Rend { removed = { clé de a }, added = { clé de b },
-- changed = { { from = clé de a, to = clé de b } } } : une clé identique des deux côtés s'apparie d'abord, puis une
-- entrée de a et une de b du même type forment un « changé ». Listes vides = mêmes vêtements.
function Appearance.diffKeys(a, b)
    local left, right = {}, {}
    for i, k in ipairs(a or {}) do left[i] = k end
    local function takeLeft(match)
        for i, k in ipairs(left) do
            if match(k) then
                table.remove(left, i)
                return k
            end
        end
        return nil
    end
    for _, k in ipairs(b or {}) do
        if takeLeft(function(x) return x == k end) == nil then right[#right + 1] = k end
    end
    local out = { removed = {}, added = {}, changed = {} }
    for _, k in ipairs(right) do
        local t = keyType(k)
        local from = takeLeft(function(x) return keyType(x) == t end)
        if from ~= nil then
            out.changed[#out.changed + 1] = { from = from, to = k }
        else
            out.added[#out.added + 1] = k
        end
    end
    for _, k in ipairs(left) do out.removed[#out.removed + 1] = k end
    return out
end

-- Écart entre deux listes d'entrées (voir diffKeys).
function Appearance.clothesDiff(a, b)
    return Appearance.diffKeys(Appearance.clothesKeys(a), Appearance.clothesKeys(b))
end

-- Vrai si deux listes décrivent les mêmes vêtements, dans n'importe quel ordre.
function Appearance.sameClothes(a, b)
    local d = Appearance.clothesDiff(a, b)
    return #d.removed + #d.added + #d.changed == 0
end

-- Vrai si le type d'objet existe dans les scripts chargés (un mod de vêtements retiré fait disparaître les siens).
-- Même test que le rejeu : ItemVisual.getScriptItem (ScriptManager.FindItem du type posé).
function Appearance.itemExists(fullType)
    if not isFullType(fullType) then return false end
    local iv = ItemVisual.new()
    iv:setItemType(fullType)
    return iv:getScriptItem() ~= nil
end

local function nonEmpty(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- Description concrète des vêtements d'un personnage (visuels de getItemVisuals, dans l'ordre), ou nil si aucun
-- visuel n'est descriptible. Lit sans rien tirer : sur un corps créé par apply, toutes les valeurs sont fixées
-- (fixVisuals). Teinte relevée en octets (getRedInt...) : c'est ce que reçoivent les clients (ItemVisual.save,
-- ItemVisual.java:299-303) et ce que relit reanimated.bin.
function Appearance.describe(chr)
    local items = chr:getItemVisuals()
    local out = {}
    for i = 0, items:size() - 1 do
        local iv = items:get(i)
        local e = { type = iv:getItemType() }
        e.item = nonEmpty(iv:getClothingItemName())
        e.alt = nonEmpty(iv:getAlternateModelName())
        local tint = iv:getTint()
        if tint ~= nil then e.tint = { r = tint:getRedInt(), g = tint:getGreenInt(), b = tint:getBlueInt() } end
        local hue = iv:getHue()
        if type(hue) == "number" and hue >= -1 and hue <= 1 then e.hue = hue end -- NULL_HUE = +infini
        local base, choice = iv:getBaseTexture(), iv:getTextureChoice()
        if isInteger(base, 0, 127) then e.base = base end
        if isInteger(choice, 0, 127) then e.choice = choice end
        local ci = iv:getClothingItem()
        if ci ~= nil then e.decal = nonEmpty(iv:getDecal(ci)) end
        if badEntry(e) == nil and #out < Appearance.MAX_CLOTHES then out[#out + 1] = e end
    end
    if #out == 0 then return nil end
    return out
end

-- Fixe les valeurs encore tirables de chaque visuel (teinte, décalage de teinte, textures, décalcomanie :
-- ItemVisual.pickUninitializedValues, ItemVisual.java:204-213) et ramène la teinte à ses octets. Le premier corps
-- est ainsi identique à ceux qui rejoueront sa description, et à ce que voient les clients MP.
local function fixVisuals(items)
    for i = 0, items:size() - 1 do
        local iv = items:get(i)
        local ci = iv:getClothingItem()
        if ci ~= nil then iv:pickUninitializedValues(ci) end
        local tint = iv:getTint()
        if tint ~= nil then
            iv:setTint(Appearance.color({ r = tint:getRedInt(), g = tint:getGreenInt(), b = tint:getBlueInt() }))
        end
    end
end

-- Remplace les visuels d'un zombie (liste vivante avant DoZombieInventory) par une description. Une entrée dont le
-- type d'objet n'existe plus (mod de vêtements retiré) est sautée. Rend le nombre posé et le nombre sauté ; si
-- aucune entrée n'est utilisable, les visuels ne sont pas touchés (posé = 0).
local function dressConcrete(z, clothes)
    local built, skipped = {}, 0
    for _, e in ipairs(clothes) do
        local iv = ItemVisual.new()
        iv:setItemType(e.type)
        if iv:getScriptItem() == nil then
            skipped = skipped + 1
        else
            if e.item then iv:setClothingItemName(e.item) end
            if e.alt then iv:setAlternateModelName(e.alt) end
            if e.tint then iv:setTint(Appearance.color(e.tint)) end
            if e.hue ~= nil then iv:setHue(e.hue) end
            if e.base ~= nil then iv:setBaseTexture(e.base) end
            if e.choice ~= nil then iv:setTextureChoice(e.choice) end
            if e.decal then iv:setDecal(e.decal) end
            built[#built + 1] = iv
        end
    end
    if #built == 0 then return 0, skipped end
    local items = z:getItemVisuals()
    items:clear()
    for _, iv in ipairs(built) do items:add(iv) end
    return #built, skipped
end

-- Applique un profil résolu à un zombie fraîchement habillé par addZombiesInOutfit, AVANT DoZombieInventory (qui
-- crée les vêtements portés à partir des visuels, WornItems.java:143-160) et avant le cadavre. Autorité seulement.
-- 1. vêtements : description concrète clothes rejouée (LK02-T12) si elle est donnée et utilisable ; sinon tenue
--    rejouée avec la variante du profil (PersistentOutfits.dressInOutfit, graines de z_outfits.bin), puis valeurs
--    tirables fixées (fixVisuals) pour que la description relevée ensuite la reproduise à l'identique ;
-- 2. objets accrochés retirés (armes plantées ajoutées à l'habillage d'un zombie, PersistentOutfits.java:279) ;
-- 3. peau humaine, coupe, barbe et couleurs (HumanVisual.java:118-263) ;
-- 4. sang, saleté et plaies du corps retirés (removeBlood, removeDirt, getBodyVisuals) ; les trous du corps
--    (HumanVisual.holes) ne sont lus par aucun rendu ;
-- 5. vêtements réparés : sang, saleté, trous et pièces de chaque ItemVisual (ItemVisual.java:617-645) ; l'état de
--    l'objet est ensuite calculé sans trou (WornItems.addItemsToItemContainer : max - 3 x trous).
-- Rend le mode d'habillage ("clothes" ou "variant"), le nombre d'entrées de clothes sautées (objet inconnu) et le
-- nombre de visuels posés depuis clothes (0 en mode "variant"). DoZombieInventory peut ensuite en perdre : deux
-- vêtements d'emplacements devenus exclusifs (un mod change les emplacements, WornItems.setItem garde le dernier).
function Appearance.apply(z, p, clothes)
    local mode, skipped, placed = "variant", 0, 0
    if clothes ~= nil then
        placed, skipped = dressConcrete(z, clothes)
        if placed > 0 then mode = "clothes" end
    end
    if mode == "variant" then
        local id = z:getPersistentOutfitID()
        local wanted = Appearance.outfitIdWithVariant(id, p.variant)
        if wanted ~= nil and wanted ~= id then z:dressInPersistentOutfitID(wanted) end
        fixVisuals(z:getItemVisuals())
    end
    z:clearAttachedItems()
    local hv = z:getHumanVisual()
    hv:setSkinTextureName(p.skin)
    hv:setHairModel(p.hair)
    if not p.female then hv:setBeardModel(p.beard) end
    local color = Appearance.color(p.hairColor)
    hv:setHairColor(color)
    hv:setNaturalHairColor(color)
    hv:setBeardColor(color)
    hv:setNaturalBeardColor(color)
    hv:removeBlood()
    hv:removeDirt()
    hv:getBodyVisuals():clear()
    local parts = BloodBodyPartType.MAX:index()
    local items = z:getItemVisuals()
    for i = 0, items:size() - 1 do
        local iv = items:get(i)
        iv:removeBlood()
        iv:removeDirt()
        for part = 0, parts - 1 do
            iv:removeHole(part)
            iv:removePatch(part)
        end
    end
    return mode, skipped, placed
end

return Appearance
