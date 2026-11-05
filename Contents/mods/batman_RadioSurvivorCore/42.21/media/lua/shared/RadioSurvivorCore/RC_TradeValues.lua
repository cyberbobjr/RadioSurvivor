-- RadioSurvivorCore: shared barter scale (value V per item, in whole points), used by the Ohio smuggler (E13) and
-- by the direct barter with a Living Knox group (LK11-T08, server/LivingKnox/LK_Trade.lua); moved to the core mod by
-- E18-T02.
-- Source: docs/specifications-techniques/passeur-table.md, validated on 2026-10-10 (decision E13-T01 (4)); vanilla
-- 42.21 identifiers read in media/scripts/generated/items (file:line in the table of the document). No item of the
-- mods is listed: any item outside the Base module is worth 0 (refused).
--
-- Entry: VALUES["Base.X"] = { v = points, k = class, cond = minimal condition (optional, 0..1 of getConditionMax),
-- cap = at most this many per visit of the smuggler (optional, E13), lot = items per point (optional: bank notes) }.
-- Classes:
--   valuables  money and jewels (section 2.1)          images   films, cameras, home video tapes (2.2)
--   papers     personal papers of the dead (2.3)       military abandoned military gear (2.4)
--   supply     what the smuggler brings (section 3): batteries, cigarettes, alcohol, coffee, seeds, radio parts
--   food, medical, ammo  items that feed the reserves of a group (section 5)
-- Unlisted supply items (categories of the real stock of a group, from the script data: DisplayCategory, fluid) take
-- the FALLBACK value of their category (choice LK11-T08, note docs/annexes/conception/troc.md); unlisted ammunition
-- (loose rounds) has none.
--
-- Prices (section 1 of the document): what one receives costs, line by line (one item type x quantity),
-- ceil(V x quantity x k) with k = (1 + margin) x multiplier; what one gives counts for floor(sum of V x multiplier).
-- The difference is not paid back (decision E13-T01 (5)).
-- ASCII code only (the Kahlua lexer turns non-ASCII literals into U+FFFD).

local TV = {}

TV.FORMAT = 1
TV.CLASSES = { "valuables", "images", "papers", "military", "supply", "food", "medical", "ammo" }

-- Fallback value per category of the real stock (LK_Stock.CATEGORIES) for an unlisted item: food, water, medical,
-- materials. Ammunition: none (only the listed boxes have a value).
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

-- 2.1 Money and jewels (smuggler only).
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

-- 2.2 Images (smuggler only).
put("images", { CameraFilm = 3 }, { cap = 6 })
put("images", { CameraDisposable = 3, Camera = 5, CameraExpensive = 10 })
put("images", { VHS_Home = 6 }, { cap = 4 })

-- 2.3 Papers of the dead (smuggler only; personal: checked by E13).
put("papers", { IDcard = 3, IDcard_Male = 3, IDcard_Female = 3, Passport = 4, PressID = 3, Badge = 3,
    Necklace_DogTag = 4, Necklace_DogTag_Male = 4, Necklace_DogTag_Female = 4, CreditCard = 1, Wallet = 1,
    Wallet_Male = 1, Wallet_Female = 1 })

-- 2.4 Military gear (condition >= 50 % for the clothes, the weapon, the mask and the tool).
put("military", { AssaultRifle = 20 }, { cond = 0.5, cap = 1 })
put("military", { ["556Clip"] = 3 })
put("military", { ["556Box"] = 8 }, { cap = 2 })
put("military", { Vest_BulletArmy = 10, Hat_Army = 3, Hat_GasMask = 5, Hat_NBCmask = 6, EntrenchingTool = 3,
    Shoes_ArmyBoots = 2 }, { cond = 0.5 })
put("military", { GasmaskFilter = 2, Bag_ALICEpack_Army = 5, WalkieTalkie5 = 6, FlashLight_AngleHead_Army = 2,
    CanteenMilitary = 1, MilitaryMedal = 4 })

-- 3. What the smuggler brings (seeds: one packet).
put("supply", { Battery = 2, CigarettePack = 3, CigaretteCarton = 25, Whiskey = 5, Vodka = 5, Wine = 3, Wine2 = 3,
    BeerPack = 4, Coffee2 = 4, RadioReceiver = 4, RadioTransmitter = 6, Amplifier = 4, ElectricWire = 1,
    ElectronicsScrap = 1,
    CarrotBagSeed2 = 3, BroccoliBagSeed2 = 3, RedRadishBagSeed2 = 3, StrewberrieBagSeed2 = 3, TomatoBagSeed2 = 3,
    PotatoBagSeed2 = 3, CabbageBagSeed2 = 3, CornBagSeed = 3, KaleBagSeed = 3, OnionBagSeed = 3, GarlicBagSeed = 3,
    WheatBagSeed = 3, LettuceBagSeed = 3 })

-- 5. Reserves of a Living Knox group.
put("food", { TinnedBeans = 2, TinnedSoup = 2, CannedChili = 2, CannedCornedBeef = 2, CannedCorn = 2, CannedPeas = 2,
    CannedPotato2 = 2, CannedTomato2 = 2, CannedBolognese = 2, CannedFruitCocktail = 2, Rice = 2, Pasta = 2,
    DriedBlackBeans = 2, PeanutButter = 2 })
put("medical", { Antibiotics = 8, AntibioticsBox = 90, Bandage = 1, AlcoholWipes = 1, Disinfectant = 3, Pills = 3,
    SutureNeedle = 3 })
put("ammo", { ShotgunShellsBox = 12, ["308Box"] = 14, ["3030Box"] = 12, Bullets9mmBox = 10 })

-- Items of RadioSurvivor brought by the smuggler (section 3): sale value only. Outside the Base module, TV.value
-- leaves them at 0: they are never taken back, neither by the smuggler nor by a group. Outside news: one issue per
-- visit (E13-T05, server/RadioSurvivor/RS_OutsideNewsServer.lua).
TV.SELL_ONLY = {
    ["RadioSurvivor.OutsideNews"] = { v = 2, k = "supply", cap = 1 },
}

local function isNumber(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

-- Sale value V of a type (scale, then the items that are only sold), or 0.
function TV.sellValue(fullType)
    if type(fullType) ~= "string" then return 0 end
    local e = VALUES[fullType] or TV.SELL_ONLY[fullType]
    return e and e.v or 0
end

-- Scale entry of a full type, or nil (unlisted, outside the Base module).
function TV.entry(fullType)
    if type(fullType) ~= "string" then return nil end
    return VALUES[fullType]
end

-- True when the full type is a vanilla item of the Base module (only those are traded).
function TV.isBase(fullType)
    return type(fullType) == "string" and string.sub(fullType, 1, 5) == "Base." and #fullType > 5
end

-- Value V of a type: the scale value, else the fallback of the stock category cat (optional), else 0.
-- Returns V and the scale class (nil for a fallback).
function TV.value(fullType, cat)
    if not TV.isBase(fullType) then return 0, nil end
    local e = VALUES[fullType]
    if e ~= nil then return e.v, e.k end
    local f = cat ~= nil and TV.FALLBACK[cat] or nil
    return f or 0, nil
end

-- Price of a received line: ceil(V x n x k), k = (1 + margin) x multiplier (rounding tolerance of the floats:
-- 10 x 1.1 = 11.000000000000002).
function TV.linePrice(v, n, k)
    if not isNumber(v) or not isNumber(n) or not isNumber(k) or v <= 0 or n <= 0 then return 0 end
    return math.ceil(v * n * k - 1e-9)
end

-- Total price of what one receives: lines = { { t = full type, v = V } } (one item per entry), grouped by type in
-- the order of first appearance. Returns the total and the list { { t, n, v, price } }.
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

-- Total value of what one gives: values = { number } (V x multiplier per item), rounded down to the point.
function TV.giveTotal(values)
    local s = 0
    for _, v in ipairs(values or {}) do
        if isNumber(v) and v > 0 then s = s + v end
    end
    return math.floor(s + 1e-9)
end

return TV
