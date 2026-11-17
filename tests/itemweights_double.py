"""Doublure des scripts d'objets du jeu pour le poids des objets du troc (E22-T12, RS_ItemWeights) dans les bancs lupa.

Hors jeu, aucun ScriptManager : les bancs qui lisent une fiche à section [trade] injectent cette table après avoir
réglé package.path (le module RS_ItemWeights se charge par require) :

    from itemweights_double import ITEM_WEIGHTS
    rt.execute(ITEM_WEIGHTS)

WEIGHTS : poids en kg de chaque type cité par les fiches livrées, relevé le 2026-11-15 dans les scripts 42.22
installés (media/scripts/generated/items, Weight du script, plus Capacity d'un FluidContainer créé rempli : Whiskey 0,7
+ 1, Vodka 1 + 1, Wine et Wine2 0,3 + 1 ; CanteenMilitary sans liquide initial : 0,2) et dans le script du mod
(RadioSurvivor.OutsideNews). Ce sont les poids que les fiches écrivaient avant E22-T12, à 0,05 kg près.
"""
from pathlib import Path

WEIGHTS = {
    'Base.3030Box': 0.6, 'Base.308Box': 0.6, 'Base.556Box': 0.5, 'Base.556Clip': 0.2, 'Base.AlcoholWipes': 0.3,
    'Base.Amplifier': 0.3, 'Base.Antibiotics': 0.1, 'Base.Bandage': 0.1, 'Base.Battery': 0.1, 'Base.BeerPack': 1.8,
    'Base.BroccoliBagSeed2': 0.1, 'Base.Bullets9mmBox': 0.8, 'Base.CabbageBagSeed2': 0.1, 'Base.CannedBolognese': 0.8,
    'Base.CannedChili': 0.8, 'Base.CannedCorn': 0.8, 'Base.CannedCornedBeef': 0.8, 'Base.CannedFruitCocktail': 0.8,
    'Base.CannedPeas': 0.8, 'Base.CannedPotato2': 0.8, 'Base.CannedTomato2': 0.8, 'Base.CanteenMilitary': 0.2,
    'Base.CarrotBagSeed2': 0.1, 'Base.CigaretteCarton': 2.0, 'Base.CigarettePack': 0.2, 'Base.Coffee2': 1.0,
    'Base.CornBagSeed': 0.1, 'Base.DriedBlackBeans': 2.0, 'Base.ElectricWire': 0.1, 'Base.ElectronicsScrap': 0.1,
    'Base.FlashLight_AngleHead_Army': 0.5, 'Base.GarlicBagSeed': 0.1, 'Base.GasmaskFilter': 0.3,
    'Base.KaleBagSeed': 0.1, 'Base.LettuceBagSeed': 0.1, 'Base.OnionBagSeed': 0.1, 'Base.Pasta': 2.0,
    'Base.PeanutButter': 0.3, 'Base.Pills': 0.2, 'Base.PotatoBagSeed2': 0.1, 'Base.RadioReceiver': 0.1,
    'Base.RadioTransmitter': 0.1, 'Base.RedRadishBagSeed2': 0.1, 'Base.Rice': 2.0, 'Base.ShotgunShellsBox': 1.5,
    'Base.StrewberrieBagSeed2': 0.1, 'Base.SutureNeedle': 0.1, 'Base.TinnedBeans': 0.8, 'Base.TinnedSoup': 0.8,
    'Base.TomatoBagSeed2': 0.1, 'Base.Vodka': 2.0, 'Base.WalkieTalkie5': 1.5, 'Base.WheatBagSeed': 0.1,
    'Base.Whiskey': 1.7, 'Base.Wine': 1.3, 'Base.Wine2': 1.3, 'RadioSurvivor.OutsideNews': 0.2,
}


def lua_table(weights: dict[str, float]) -> str:
    """Table Lua { ["Module.Type"] = kg, ... }."""
    return '{' + ', '.join(f'["{t}"] = {kg!r}' for t, kg in sorted(weights.items())) + '}'


ITEM_WEIGHTS = f'require("RadioSurvivor/RS_ItemWeights").use({lua_table(WEIGHTS)})'


# E23-T06 : règles du lecteur des fiches pour une section [trade] (modes d'arrivée inscrits, poids ci-dessus, catalogue
# partagé de catégories livré : accept=<catégorie>), comme RS_Personas.rules les donne en jeu. Expression Lua, à évaluer
# après ITEM_WEIGHTS et l'inscription des modes d'arrivée. E25-T01 : rules.places = lieux communs livrés (_places.txt,
# rendez-vous des marchands livrés), plus les sections [place <id>] propres au banc (extra_places).
PERSONAS = Path(__file__).resolve().parents[1] / 'Contents/mods/batman_RadioSurvivor/42.21/personas'
CATEGORIES = PERSONAS / '_categories.txt'
PLACES = PERSONAS / '_places.txt'


def lua_lines(lines: list[str]) -> str:
    """Table Lua de chaînes longues (une par ligne)."""
    return '{' + ', '.join('[==[' + line + ']==]' for line in lines) + '}'


def trade_rules_lua(extra_places: str = '') -> str:
    categories = lua_lines(CATEGORIES.read_text(encoding='utf-8').splitlines())
    places = lua_lines(PLACES.read_text(encoding='utf-8').splitlines() + extra_places.splitlines())
    return ('{ arrivals = require("RadioSurvivor/RS_TradeArrivals").NAMES,'
            ' itemWeight = require("RadioSurvivor/RS_ItemWeights").of,'
            f' categories = require("RadioSurvivor/RS_Persona").parseCatalogue({categories}),'
            f' places = assert(require("RadioSurvivor/RS_Persona").parsePlaces({places})) }}')

