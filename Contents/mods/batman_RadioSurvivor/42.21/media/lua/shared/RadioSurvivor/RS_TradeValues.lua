-- Radio Survivor : barème de troc commun (valeur V par objet, en points entiers), partagé par le passeur de l'Ohio
-- (E13) et le troc direct avec un groupe Living Knox (LK11-T08, server/LivingKnox/LK_Trade.lua).
-- Source : docs/specifications-techniques/passeur-table.md, validée le 2026-10-10 (décision E13-T01 (4)) ; identifiants vanilla
-- 42.21 relevés dans media/scripts/generated/items (fichier:ligne dans la table du document). Aucun objet de ce mod n'y
-- figure : tout objet hors module Base vaut 0 (refusé).
--
-- Entrée : VALUES["Base.X"] = { v = points, k = classe, cond = état minimal (facultatif, 0..1 de getConditionMax),
-- cap = nombre au plus par passage du passeur (facultatif, E13), lot = objets par point (facultatif : billets) }.
-- Classes :
--   valuables  argent et bijoux (section 2.1)        images   pellicules, appareils, cassettes d'amateur (2.2)
--   papers     papiers nominatifs des morts (2.3)     military matériel militaire abandonné (2.4)
--   supply     ce que le passeur apporte (section 3) : piles, cigarettes, alcool, café, graines, pièces radio
--   food, medical, ammo  objets qui alimentent les réserves d'un groupe (section 5)
-- Les objets de ravitaillement non listés (catégories du stock réel d'un groupe, tirées des données de script :
-- DisplayCategory, fluide) prennent la valeur de repli FALLBACK de leur catégorie (choix LK11-T08, fiche
-- docs/annexes/conception/troc.md) ; les munitions non listées (cartouches en vrac) n'en ont pas.
--
-- Prix (section 1 du document) : ce que l'on reçoit coûte, ligne par ligne (un type d'objet x quantité),
-- ceil(V x quantité x k) avec k = (1 + marge) x multiplicateur ; ce que l'on donne compte pour floor(somme des V x
-- multiplicateur). L'écart n'est pas rendu (décision E13-T01 (5)).
-- Code ASCII seulement (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).

local TV = {}

TV.FORMAT = 1
TV.CLASSES = { "valuables", "images", "papers", "military", "supply", "food", "medical", "ammo" }

-- Valeur de repli par catégorie du stock réel (LK_Stock.CATEGORIES) pour un objet non listé : nourriture, eau,
-- soins, matériaux. Munitions : aucune (seules les boîtes listées ont une valeur).
TV.FALLBACK = { food = 2, water = 2, medical = 1, materials = 1 }

local VALUES = {}
TV.VALUES = VALUES

local function put(k, list, extra)
    for name, v in pairs(list) do
        local e = { v = v, k = k }
        for f, x in pairs(extra or {}) do e[f] = x end
        VALUES["Base." .. name] = e
    end
end

-- 2.1 Argent et bijoux (passeur seulement).
put("valuables", { Money = 1 }, { lot = 10, cap = 100 })
put("valuables", { MoneyBundle = 10, GoldCoin = 3, SilverCoin = 2, Diamond = 10 })
put("valuables", { GoldBar = 40, SilverBar = 20 }, { cap = 1 })
for _, hand in ipairs({ "Right", "Left" }) do
    for _, finger in ipairs({ "MiddleFinger", "RingFinger" }) do
        local p = "Ring_" .. hand .. "_" .. finger .. "_"
        put("valuables", { [p .. "Gold"] = 4, [p .. "Silver"] = 2, [p .. "SilverDiamond"] = 6, [p .. "GoldRuby"] = 6,
            [p .. "GoldDiamond"] = 8, [p .. "Signet"] = 3 })
    end
end
put("valuables", {
    Necklace_Gold = 4, Necklace_Silver = 2, Necklace_GoldRuby = 6, Necklace_GoldDiamond = 8,
    Necklace_SilverSapphire = 4, Necklace_SilverDiamond = 6, Necklace_SilverCrucifix = 2, Necklace_Pearl = 4,
    NecklaceLong_Gold = 5, NecklaceLong_GoldDiamond = 8, NecklaceLong_Silver = 3, NecklaceLong_SilverEmerald = 5,
    NecklaceLong_SilverSapphire = 5, NecklaceLong_SilverDiamond = 6, Necklace_Choker_Sapphire = 3,
    Necklace_Choker_Diamond = 5,
    Earring_LoopLrg_Gold = 2, Earring_LoopMed_Gold = 2, Earring_LoopSmall_Gold_Both = 2,
    Earring_LoopSmall_Gold_Top = 2, Earring_Stud_Gold = 2,
    Earring_LoopLrg_Silver = 1, Earring_LoopMed_Silver = 1, Earring_LoopSmall_Silver_Both = 1,
    Earring_LoopSmall_Silver_Top = 1, Earring_Stud_Silver = 1,
    Earring_Stone_Sapphire = 3, Earring_Stone_Emerald = 3, Earring_Stone_Ruby = 3, Earring_Dangly_Sapphire = 3,
    Earring_Dangly_Emerald = 3, Earring_Dangly_Ruby = 3, Earring_Dangly_Diamond = 5, Earring_Pearl = 2,
    Earring_Dangly_Pearl = 2,
    Bracelet_BangleRightGold = 4, Bracelet_BangleLeftGold = 4, Bracelet_ChainRightGold = 4,
    Bracelet_ChainLeftGold = 4, Bracelet_BangleRightSilver = 2, Bracelet_BangleLeftSilver = 2,
    Bracelet_ChainRightSilver = 2, Bracelet_ChainLeftSilver = 2,
    WristWatch_Right_Expensive = 8, WristWatch_Left_Expensive = 8, WristWatch_Right_ClassicGold = 5,
    WristWatch_Left_ClassicGold = 5, Pocketwatch = 3,
})

-- 2.2 Images (passeur seulement).
put("images", { CameraFilm = 3 }, { cap = 6 })
put("images", { CameraDisposable = 3, Camera = 5, CameraExpensive = 10 })
put("images", { VHS_Home = 6 }, { cap = 4 })

-- 2.3 Papiers des morts (passeur seulement ; nominatifs : contrôlés par E13).
put("papers", { IDcard = 3, IDcard_Male = 3, IDcard_Female = 3, Passport = 4, PressID = 3, Badge = 3,
    Necklace_DogTag = 4, Necklace_DogTag_Male = 4, Necklace_DogTag_Female = 4, CreditCard = 1, Wallet = 1,
    Wallet_Male = 1, Wallet_Female = 1 })

-- 2.4 Matériel militaire (état >= 50 % pour les vêtements, l'arme, le masque et l'outil).
put("military", { AssaultRifle = 20 }, { cond = 0.5, cap = 1 })
put("military", { ["556Clip"] = 3 })
put("military", { ["556Box"] = 8 }, { cap = 2 })
put("military", { Vest_BulletArmy = 10, Hat_Army = 3, Hat_GasMask = 5, Hat_NBCmask = 6, EntrenchingTool = 3,
    Shoes_ArmyBoots = 2 }, { cond = 0.5 })
put("military", { GasmaskFilter = 2, Bag_ALICEpack_Army = 5, WalkieTalkie5 = 6, FlashLight_AngleHead_Army = 2,
    CanteenMilitary = 1, MilitaryMedal = 4 })

-- 3. Ce que le passeur apporte (graines : un sachet).
put("supply", { Battery = 2, CigarettePack = 3, CigaretteCarton = 25, Whiskey = 5, Vodka = 5, Wine = 3, Wine2 = 3,
    BeerPack = 4, Coffee2 = 4, RadioReceiver = 4, RadioTransmitter = 6, Amplifier = 4, ElectricWire = 1,
    ElectronicsScrap = 1,
    CarrotBagSeed2 = 3, BroccoliBagSeed2 = 3, RedRadishBagSeed2 = 3, StrewberrieBagSeed2 = 3, TomatoBagSeed2 = 3,
    PotatoBagSeed2 = 3, CabbageBagSeed2 = 3, CornBagSeed = 3, KaleBagSeed = 3, OnionBagSeed = 3, GarlicBagSeed = 3,
    WheatBagSeed = 3, LettuceBagSeed = 3 })

-- 5. Réserves d'un groupe Living Knox.
put("food", { TinnedBeans = 2, TinnedSoup = 2, CannedChili = 2, CannedCornedBeef = 2, CannedCorn = 2, CannedPeas = 2,
    CannedPotato2 = 2, CannedTomato2 = 2, CannedBolognese = 2, CannedFruitCocktail = 2, Rice = 2, Pasta = 2,
    DriedBlackBeans = 2, PeanutButter = 2 })
put("medical", { Antibiotics = 8, AntibioticsBox = 90, Bandage = 1, AlcoholWipes = 1, Disinfectant = 3, Pills = 3,
    SutureNeedle = 3 })
put("ammo", { ShotgunShellsBox = 12, ["308Box"] = 14, ["3030Box"] = 12, Bullets9mmBox = 10 })

-- Objets du mod apportés par le passeur (section 3) : valeur de vente seulement. Hors module Base, TV.value les laisse
-- à 0 : ils ne sont jamais repris, ni par le passeur ni par un groupe. Journal du dehors : une édition par passage
-- (E13-T05, server/RadioSurvivor/RS_OutsideNewsServer.lua).
TV.SELL_ONLY = {
    ["RadioSurvivor.OutsideNews"] = { v = 2, k = "supply", cap = 1 },
}

local function isNumber(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

-- Valeur V de vente d'un type (barème, puis objets du mod vendus seulement), ou 0.
function TV.sellValue(fullType)
    if type(fullType) ~= "string" then return 0 end
    local e = VALUES[fullType] or TV.SELL_ONLY[fullType]
    return e and e.v or 0
end

-- Entrée du barème pour un type complet, ou nil (non listé, hors module Base).
function TV.entry(fullType)
    if type(fullType) ~= "string" then return nil end
    return VALUES[fullType]
end

-- Vrai si le type complet est un objet vanilla du module Base (seuls ceux-là s'échangent).
function TV.isBase(fullType)
    return type(fullType) == "string" and string.sub(fullType, 1, 5) == "Base." and #fullType > 5
end

-- Valeur V d'un type : celle du barème, sinon le repli de la catégorie de stock cat (facultative), sinon 0.
-- Rend V et la classe du barème (nil pour un repli).
function TV.value(fullType, cat)
    if not TV.isBase(fullType) then return 0, nil end
    local e = VALUES[fullType]
    if e ~= nil then return e.v, e.k end
    local f = cat ~= nil and TV.FALLBACK[cat] or nil
    return f or 0, nil
end

-- Prix d'une ligne reçue : ceil(V x n x k), k = (1 + marge) x multiplicateur (tolérance d'arrondi des flottants :
-- 10 x 1,1 = 11,000000000000002).
function TV.linePrice(v, n, k)
    if not isNumber(v) or not isNumber(n) or not isNumber(k) or v <= 0 or n <= 0 then return 0 end
    return math.ceil(v * n * k - 1e-9)
end

-- Prix total de ce que l'on reçoit : lines = { { t = type complet, v = V } } (un objet par entrée), groupé par type
-- dans l'ordre de première apparition. Rend le total et la liste { { t, n, v, price } }.
function TV.askTotal(lines, k)
    local order, byType = {}, {}
    for _, l in ipairs(lines or {}) do
        local row = byType[l.t]
        if row == nil then
            row = { t = l.t, n = 0, v = l.v }
            byType[l.t] = row
            order[#order + 1] = row
        end
        row.n = row.n + 1
    end
    local total = 0
    for _, row in ipairs(order) do
        row.price = TV.linePrice(row.v, row.n, k)
        total = total + row.price
    end
    return total, order
end

-- Valeur totale de ce que l'on donne : values = { nombre } (V x multiplicateur par objet), arrondie au point inférieur.
function TV.giveTotal(values)
    local s = 0
    for _, v in ipairs(values or {}) do
        if isNumber(v) and v > 0 then s = s + v end
    end
    return math.floor(s + 1e-9)
end

return TV
