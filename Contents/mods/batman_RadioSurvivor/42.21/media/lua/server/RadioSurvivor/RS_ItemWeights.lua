-- Radio Survivor : poids d'un type d'objet lu dans son script (E22-T12), source injectee dans le lecteur des fiches
-- (RS_Personas.rules, regle itemWeight) pour le stock de [trade] : la fiche ne porte plus de poids.
--
-- Poids = Weight du script, plus la contenance d'un recipient cree plein (liquide compte 1 kg par litre, base
-- api-42-21.md, "poids porte d'un objet"), sans creer d'objet (aucun OnCreate de mod lance, aucun objet a jeter) :
--   - ScriptManager.FindItem(String) -> scripting.objects.Item (ScriptManager.java:1325-1347, 42.22) ; le nom rendu
--     est compare au type demande : un module inconnu retombe sur Base (FindItem(name, true), :1333) ;
--   - Item.getActualWeight() : Weight du script, jamais negatif (Item.java:557-562, lu a :2104) ;
--   - GameEntityScript.getComponentScriptFor(ComponentType.FluidContainer) (GameEntityScript.java:128-133,
--     ComponentType.java:69) -> FluidContainerScript, ou nil sans recipient ;
--   - FluidContainerScript.getInitialFluids() non vide : l'objet est cree rempli (FluidContainer.java:113-116) ;
--     getCapacity() en litres (FluidContainerScript.java:326-328). La quantite initiale peut etre tiree plus bas
--     (InitialPercent*) : le recipient plein est la borne haute, celle du plafond de poids. Un recipient sans
--     liquide initial (gourde) est livre vide : son seul Weight.
-- Classes exposees a Lua : Item, ScriptManager, ComponentType, FluidContainerScript (LuaManager.java:2286, 2362,
-- 1851, 2262). Resultat arrondi a 0,01 kg et mis en cache par type (inconnu compris) pour la session.
-- Bancs hors jeu : ItemWeights.use(table) remplace les scripts par une table { ["Module.Type"] = kg }.
if isClient() then return end

local ItemWeights = {}

local cache = {}
local table_ = nil    -- table injectee (bancs), ou nil : scripts du jeu

local function round2(x)
    return math.floor(x * 100 + 0.5) / 100
end

local function fluidKg(script)
    local fluid = script:getComponentScriptFor(ComponentType.FluidContainer)
    if not fluid then return 0 end
    local initial = fluid:getInitialFluids()
    if initial and not initial:isEmpty() then return fluid:getCapacity() end
    return 0
end

local function scriptKg(fullType)
    local script = getScriptManager():FindItem(fullType)
    if not script or script:getFullName() ~= fullType then return nil end
    return round2(script:getActualWeight() + fluidKg(script))
end

-- Poids en kg du type complet (Module.Type), ou nil si aucun script d'objet de ce type.
function ItemWeights.of(fullType)
    if type(fullType) ~= "string" then return nil end
    if table_ then return table_[fullType] end
    local kg = cache[fullType]
    if kg == nil then
        kg = scriptKg(fullType) or false
        cache[fullType] = kg
    end
    return kg or nil
end

-- Bancs : table { ["Module.Type"] = kg } a la place des scripts ; nil revient aux scripts du jeu. Vide le cache.
function ItemWeights.use(weights)
    table_ = weights
    cache = {}
end

return ItemWeights
