"""Kookverliezen: hoeveel van een voedingsstof overblijft bij een bereiding (USDA Table of Nutrient Retention
Factors, Release 6, 2007; publiek domein).

Een retentiefactor is "true retention": (stof in het gekookte product × gewicht gekookt) / (stof rauw × gewicht
rauw). Het verschil in gewicht (water dat verdampt of opgenomen wordt) zit in het schalen met de droge stof;
deze factor voegt daar het eigenlijke verlies aan toe (vitamine C, B1 en foliumzuur breken af, mineralen lekken
uit in kookwater).
"""
from pathlib import Path

NUTRIENT_IDS = {
    '301': 'calcium', '303': 'iron', '304': 'magnesium', '305': 'phosphorus', '306': 'potassium', '307': 'sodium',
    '309': 'zinc', '312': 'copper', '392': 'vit_a', '321': 'beta_carotene', '337': 'lycopene',
    '338': 'lutein_zeaxanthin', '401': 'vit_c', '404': 'b1', '405': 'b2', '406': 'b3', '415': 'b6', '417': 'b9',
    '418': 'b12', '421': 'choline',
}


def load(path):
    """{code: {voedingsstof: fractie}} uit retn06.txt."""
    table = {}
    if not Path(path).exists():
        return table
    for line in open(path, encoding='latin-1'):
        parts = [x.strip('~') for x in line.rstrip('\n\r').split('^')]
        if len(parts) < 6 or parts[3] not in NUTRIENT_IDS or not parts[5]:
            continue
        table.setdefault(parts[0], {})[NUTRIENT_IDS[parts[3]]] = float(parts[5]) / 100
    return table


# Bereiding (label "c") naar de gebruikte kolom in de tabel hieronder
METHOD = {
    'boiled': 'boil', 'stewed': 'stew', 'steamed': 'steam', 'microwaved': 'steam', 'baked': 'bake',
    'roasted': 'roast', 'grilled': 'grill', 'fried': 'fry', 'deep-fried': 'fry', 'cooked': 'boil',
}

# (groep of soort, bereiding) -> code. Groepen komen uit de labels ("g", "f", "p").
CODES = {
    'egg': {'bake': '0101', 'fry': '0103', 'boil': '0105', 'stew': '0107', 'steam': '0107'},
    'greens': {'bake': '3001', 'boil': '3005', 'stew': '3005', 'steam': '3784', 'fry': '3015', 'roast': '3001', 'grill': '3001'},
    'roots': {'bake': '3451', 'roast': '3451', 'grill': '3451', 'boil': '3455', 'stew': '3455', 'steam': '3464', 'fry': '3460'},
    'vegetable': {'bake': '3771', 'roast': '3771', 'grill': '3771', 'boil': '3775', 'stew': '3775', 'steam': '3784', 'fry': '3780'},
    'potato': {'bake': '3301', 'roast': '3301', 'grill': '3301', 'boil': '3308', 'stew': '3308', 'steam': '3308', 'fry': '3315'},
    'sweet potato': {'bake': '3701', 'roast': '3701', 'grill': '3701', 'boil': '3708', 'stew': '3708', 'steam': '3708', 'fry': '3710'},
    'tomato': {'bake': '3751', 'roast': '3751', 'boil': '3751', 'stew': '3751', 'steam': '3751', 'grill': '3752', 'fry': '3752'},
    'fruit': {'bake': '0151', 'roast': '0151', 'grill': '0152', 'fry': '0153', 'boil': '0155', 'stew': '0155', 'steam': '0155'},
    'legume': {'boil': '0521', 'stew': '0521', 'steam': '0521', 'bake': '0524', 'roast': '0524', 'fry': '0525'},
    'pasta': {'boil': '0381', 'stew': '0381', 'steam': '0381', 'bake': '0382'},
    'rice': {'boil': '0431', 'stew': '0431', 'steam': '0431', 'fry': '0433'},
    'oats': {'boil': '0352', 'stew': '0352', 'steam': '0352'},
    'cereal': {'boil': '0358', 'stew': '0358', 'steam': '0302', 'bake': '0301', 'roast': '0306', 'fry': '0305'},
    'beef': {'roast': '0601', 'bake': '0601', 'grill': '0602', 'fry': '0604', 'stew': '0651', 'boil': '0653', 'steam': '0653'},
    'pork': {'grill': '1251', 'fry': '1252', 'roast': '1254', 'bake': '1254', 'stew': '1301', 'boil': '1301', 'steam': '1301'},
    'cured pork': {'grill': '1451', 'fry': '1451', 'roast': '1459', 'bake': '1459', 'boil': '1521', 'stew': '1521'},
    'bacon': {'grill': '1456', 'fry': '1456', 'roast': '1456', 'bake': '1456'},
    'lamb': {'grill': '1001', 'roast': '1004', 'bake': '1004', 'fry': '1001', 'stew': '1051', 'boil': '1055', 'steam': '1055'},
    'veal': {'grill': '1951', 'fry': '1952', 'roast': '1954', 'bake': '1954', 'stew': '2001', 'boil': '2003', 'steam': '2003'},
    'chicken': {'grill': '0801', 'fry': '0803', 'roast': '0805', 'bake': '0805', 'stew': '0851', 'boil': '0855', 'steam': '0855'},
    'turkey': {'roast': '1805', 'bake': '1805', 'grill': '1805', 'fry': '1805', 'stew': '1851', 'boil': '1851', 'steam': '1851'},
    'liver': {'fry': '1151', 'grill': '1151', 'roast': '1151', 'bake': '1151', 'boil': '1152', 'stew': '1152', 'steam': '1152'},
    'offal': {'fry': '1181', 'grill': '1181', 'roast': '1181', 'bake': '1181', 'boil': '1182', 'stew': '1182', 'steam': '1182'},
    'sausage': {'boil': '1705', 'stew': '1705', 'steam': '1705', 'grill': '1707', 'roast': '1707', 'bake': '1707', 'fry': '1709'},
    'lean fish': {'bake': '2301', 'roast': '2301', 'grill': '2305', 'fry': '2309', 'boil': '2401', 'stew': '2401', 'steam': '2401'},
    'fatty fish': {'bake': '2451', 'roast': '2451', 'grill': '2455', 'fry': '2459', 'boil': '2551', 'stew': '2551', 'steam': '2551'},
    'shellfish': {'boil': '2761', 'stew': '2761', 'steam': '2770', 'bake': '2750', 'roast': '2750', 'grill': '2753', 'fry': '2755'},
    'cheese': {'bake': '0001', 'grill': '0003', 'roast': '0003', 'boil': '0005', 'stew': '0005', 'fry': '0003'},
    'milk': {'boil': '2151', 'stew': '2151', 'steam': '2151', 'bake': '2151'},
    'nut': {'roast': '2203', 'bake': '2203', 'grill': '2202', 'fry': '2203', 'boil': '2204'},
}
BREADED = {'chicken': {'fry': '0804'}, 'pork': {'fry': '1253'}, 'veal': {'fry': '1953'}, 'lean fish': {'fry': '2310'},
           'fatty fish': {'fry': '2460'}, 'shellfish': {'fry': '2756'}}
GREENS = {'spinach', 'kale', 'chard', 'swiss chard', 'collards', 'mustard greens', 'turnip greens', 'beet greens',
          'dandelion greens', 'amaranth leaves', 'lambsquarters', 'cabbage', 'savoy cabbage', 'brussels sprouts',
          'lettuce', 'endive', 'nettle', 'purslane', 'watercress', 'pak choi', 'bok choy', 'chinese cabbage'}


def category(label, fat):
    """Rij in CODES voor een gelabeld product, of None als er geen passende kookverliezen zijn."""
    g, f, p, fl = label.get('g'), label.get('f', ''), label.get('p'), label.get('fl', [])
    if g == 'egg':
        return 'egg'
    if g == 'offal' or p in ('liver', 'kidney', 'heart', 'tongue', 'brain', 'other offal'):
        return 'liver' if p == 'liver' or 'liver' in f else 'offal'
    if g == 'processed meat':
        if 'bacon' in f:
            return 'bacon'
        if 'sausage' in f or 'frank' in f:
            return 'sausage'
        return 'cured pork' if 'ham' in f or 'pork' in f else None
    if g in ('meat', 'poultry'):
        for kind in ('veal', 'beef', 'pork', 'lamb', 'chicken', 'turkey'):
            if kind in f:
                return kind
        if 'mutton' in f or 'goat' in f:
            return 'lamb'
        return 'chicken' if g == 'poultry' else 'beef'
    if g == 'fish':
        return 'fatty fish' if (fat or 0) >= 5 else 'lean fish'
    if g == 'shellfish':
        return 'shellfish'
    if g == 'dairy':
        return 'cheese' if 'cheese' in f else ('milk' if p == 'drink' else None)
    if g == 'potato/tuber':
        return 'sweet potato' if 'sweet potato' in f else ('potato' if 'potato' in f else 'roots')
    if g == 'vegetable':
        if 'tomato' in f:
            return 'tomato'
        if p == 'leaf' or f in GREENS or 'greens' in f:
            return 'greens'
        if p in ('root', 'bulb') or f in ('carrot', 'beetroot', 'parsnip', 'turnip', 'celeriac', 'swede', 'radish', 'onion'):
            return 'roots'
        return 'vegetable'
    if g == 'fruit':
        return 'fruit'
    if g in ('legume', 'soy product'):
        return 'legume'
    if g == 'pasta':
        return 'pasta'
    if g == 'rice':
        return 'rice'
    if g in ('cereal', 'breakfast cereal'):
        return 'oats' if 'oat' in f else 'cereal'
    if g == 'nut/seed':
        return 'nut'
    return None


def factors(table, label, fat):
    """Retentiefracties per voedingsstof voor dit (gekookte) product, of {} als het rauw is of niet van toepassing."""
    method = METHOD.get(label.get('c'))
    cat = category(label, fat)
    if not method or not cat:
        return {}
    code = None
    if 'breaded' in label.get('fl', []):
        code = BREADED.get(cat, {}).get(method)
    code = code or CODES.get(cat, {}).get(method)
    return table.get(code, {}) if code else {}
