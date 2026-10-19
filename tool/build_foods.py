"""
Bouwt assets/db/foods.db: de ingebouwde database met basisvoedingsmiddelen uit meerdere bronnen.

Bronnen (zet ze in één map, elk in een eigen submap):
  ciqual/  ANSES-CIQUAL 2020, Frankrijk (Licence Ouverte): XML-zip van https://ciqual.anses.fr, uitgepakt
  slv/     Livsmedelsverket, Zweden (CC BY 4.0): ophalen met tool/fetch_slv.py
  mvt/     Matvaretabellen, Noorwegen (NLOD): foods_en.json, foods_nb.json, food_groups_en.json
           van https://www.matvaretabellen.no/api/{en,nb}/...
  FoodData_Central_sr_legacy_food_csv_*/ en FoodData_Central_foundation_food_csv_*/
           USDA FoodData Central, VS (publiek domein): CSV-zips van https://fdc.nal.usda.gov/download-datasets

Bronnen die ontbreken, worden overgeslagen.

Gebruik:
    python3 tool/build_foods.py <bronmap> assets/db/foods.db

Elke bron blijft een apart product (geen gemiddelden): definities en producten verschillen per land.
Wel worden de waarden gelijkgetrokken naar één definitie per voedingsstof:
  - koolhydraten = beschikbare koolhydraten (Europese definitie, zonder vezels)
  - vitamine A = µg RAE (retinol + bètacaroteen / 12)
De sleutels (energy, protein, vit_c, ...) komen overeen met lib/nutrition/nutrients.dart; waarden per 100 g.
"""
import csv
import glob
import hashlib
import json
import re
import sqlite3
import statistics
import sys
from pathlib import Path

# Volgorde in de app: lager = eerst getoond bij zoekresultaten van gelijke kwaliteit (Europa eerst)
SOURCES = {
    'ciqual': 'ANSES-CIQUAL 2020 (Frankrijk), Licence Ouverte',
    'slv': 'Livsmedelsverket, Livsmedelsdatabasen (Zweden), CC BY 4.0',
    'mvt': 'Matvaretabellen, Mattilsynet (Noorwegen), NLOD',
    'usda_fnd': 'USDA FoodData Central, Foundation Foods (VS), publiek domein',
    'usda_sr': 'USDA FoodData Central, SR Legacy (VS), publiek domein',
}


def sig(x):
    """Afronden op 4 beduidende cijfers, zodat de database klein blijft."""
    return float(f'{x:.4g}')


def read_csv(path):
    with open(path, newline='', encoding='utf-8') as f:
        yield from csv.DictReader(f)


def finish(n):
    """Gemeenschappelijke nabewerking voor alle bronnen: hulpwaarden omzetten en weglaten."""
    # Negatieve waarden (afrondingsfouten in "koolhydraten by difference") bestaan niet
    n = {k: max(0.0, v) if isinstance(v, float) else v for k, v in n.items() if v is not None}
    # Vitamine A als RAE uit retinol en bètacaroteen, als de bron het niet zelf als RAE gaf. Zonder retinol niet:
    # bij boter of kaas zou alleen bètacaroteen/12 veel te weinig zijn (dat wordt later aangevuld)
    if 'vit_a' not in n and '_retinol' in n:
        n['vit_a'] = n.get('_retinol', 0) + n.get('beta_carotene', 0) / 12
    # Natrium uit zout als natrium ontbreekt (zout = natrium x 2,5)
    if 'sodium' not in n and '_salt' in n:
        n['sodium'] = n['_salt'] / 2.5 * 1000
    return {k: v for k, v in n.items() if not k.startswith('_')}


def derive(n, estimated):
    """Afgeleide totalen (omega-3, omega-6) als de bron ze niet gaf. Geschat als een deel geschat is."""
    for total, parts in (('omega3', ('ala', 'epa', 'dpa', 'dha')), ('omega6', ('la', 'aa'))):
        present = [k for k in parts if k in n]
        if present and total not in n:
            n[total] = sum(n[k] for k in present)
            donors = [estimated[k] for k in present if k in estimated]
            if donors:
                estimated[total] = donors[0]


# ─────────────────────────── USDA ───────────────────────────

USDA = {
    'energy': ('kcal', [1008, 2048, 2047]),
    'protein': ('g', [1003]),
    '_carbs_diff': ('g', [1005]),
    '_carbs_sum': ('g', [1050]),
    'fiber': ('g', [1079, 2033]),
    'sugars': ('g', [2000, 1063]),
    'starch': ('g', [1009]),
    'fat': ('g', [1004, 1085]),
    'sfa': ('g', [1258]),
    'mufa': ('g', [1292]),
    'pufa': ('g', [1293]),
    'trans': ('g', [1257]),
    'cholesterol': ('mg', [1253]),
    'ala': ('g', [1404, 1270, 2018]),
    'epa': ('g', [1278, 2023]),
    'dpa': ('g', [1280, 2024]),
    'dha': ('g', [1272, 2025]),
    'la': ('g', [1316, 1269, 2016]),
    'aa': ('g', [1271, 2022]),
    'water': ('g', [1051]),
    'alcohol': ('g', [1018]),
    'caffeine': ('mg', [1057]),
    'vit_a': ('µg', [1106]),
    'beta_carotene': ('µg', [1107]),
    'vit_c': ('mg', [1162]),
    'vit_d': ('µg', [1114]),
    'vit_e': ('mg', [1109]),
    'vit_k': ('µg', [1185]),
    'vit_k2': ('µg', [1183]),
    'b1': ('mg', [1165]),
    'b2': ('mg', [1166]),
    'b3': ('mg', [1167]),
    'b5': ('mg', [1170]),
    'b6': ('mg', [1175]),
    'b7': ('µg', [1176]),
    'b9': ('µg', [1190, 1177]),
    'b12': ('µg', [1178]),
    'choline': ('mg', [1180]),
    'calcium': ('mg', [1087]),
    'iron': ('mg', [1089]),
    'magnesium': ('mg', [1090]),
    'phosphorus': ('mg', [1091]),
    'potassium': ('mg', [1092]),
    'sodium': ('mg', [1093]),
    'zinc': ('mg', [1095]),
    'copper': ('mg', [1098]),
    'manganese': ('mg', [1101]),
    'selenium': ('µg', [1103]),
    'iodine': ('µg', [1100]),
    'fluoride': ('mg', [1099]),
    'chromium': ('µg', [1096]),
    'molybdenum': ('µg', [1102]),
    'lycopene': ('µg', [1122]),
    'lutein_zeaxanthin': ('µg', [1123]),
    'histidine': ('g', [1221]),
    'isoleucine': ('g', [1212]),
    'leucine': ('g', [1213]),
    'lysine': ('g', [1214]),
    'methionine': ('g', [1215]),
    'cystine': ('g', [1216, 1232]),
    'phenylalanine': ('g', [1217]),
    'tyrosine': ('g', [1218]),
    'threonine': ('g', [1211]),
    'tryptophan': ('g', [1210]),
    'valine': ('g', [1219]),
}
FACTOR = {
    ('G', 'g'): 1, ('MG', 'mg'): 1, ('UG', 'µg'): 1, ('KCAL', 'kcal'): 1,
    ('UG', 'mg'): 0.001, ('MG', 'g'): 0.001, ('G', 'mg'): 1000,
}
# Hoofdbestanddelen: die vullen we nooit met een geschaalde waarde van een ander product aan
MACROS = {'energy', 'protein', 'carbs', 'fat', 'fiber', 'sugars', 'starch', 'water', 'alcohol', '_salt'}

USDA_SKIP_CATEGORIES = {'Quality Control Materials', 'Branded Food Products Database'}


def usda_load(d, only_ids=None):
    units = {r['id']: r['unit_name'] for r in read_csv(d / 'nutrient.csv')}
    cats = {r['id']: r['description'] for r in read_csv(d / 'food_category.csv')}
    foods = {}
    for r in read_csv(d / 'food.csv'):
        if only_ids is not None and r['fdc_id'] not in only_ids:
            continue
        foods[r['fdc_id']] = {'name': r['description'].strip(), 'category': cats.get(r['food_category_id'], ''), 'raw': {}, 'portions': []}
    for r in read_csv(d / 'food_nutrient.csv'):
        f = foods.get(r['fdc_id'])
        if f is not None and r['amount'] != '':
            f['raw'][int(r['nutrient_id'])] = (float(r['amount']), units.get(r['nutrient_id'], ''))
    mu = {r['id']: r['name'] for r in read_csv(d / 'measure_unit.csv')}
    for r in read_csv(d / 'food_portion.csv'):
        f = foods.get(r['fdc_id'])
        if f is None or not r['gram_weight'] or float(r['gram_weight']) <= 0:
            continue
        amount = r['amount'] or '1'
        amount = amount.rstrip('0').rstrip('.') if '.' in amount else amount
        unit = mu.get(r['measure_unit_id'], '')
        unit = '' if unit in ('undetermined', '') else unit
        rest = (r['portion_description'] or r['modifier'] or '').strip()
        f['portions'].append((' '.join(x for x in (amount, unit, rest) if x).strip(), sig(float(r['gram_weight']))))
    return foods


def usda_nutrients(raw):
    out = {}
    for key, (unit, ids) in USDA.items():
        for nid in ids:
            if nid in raw:
                value, src_unit = raw[nid]
                factor = FACTOR.get((src_unit, unit))
                if factor is None:
                    sys.exit(f'Onbekende eenheid {src_unit} -> {unit} voor {key} ({nid})')
                out[key] = value * factor
                break
    # Koolhydraten "by difference" bevatten vezels; Europese tabellen en etiketten niet
    diff, summ = out.pop('_carbs_diff', None), out.pop('_carbs_sum', None)
    if diff is not None and 'fiber' in out:
        out['carbs'] = max(0.0, diff - out['fiber'])
    elif summ is not None:
        out['carbs'] = summ
    elif diff is not None:
        out['carbs'] = diff
    return finish({k: max(0.0, v) for k, v in out.items()})


def usda_rows(root):
    sr_dirs = sorted(p.parent for p in root.rglob('food.csv') if 'sr_legacy' in str(p))
    fnd_dirs = sorted(p.parent for p in root.rglob('food.csv') if 'foundation' in str(p))
    if not sr_dirs or not fnd_dirs:
        print('USDA: niet gevonden, overgeslagen')
        return
    sr_dir, fnd_dir = sr_dirs[-1], fnd_dirs[-1]
    sr_ndb = {r['fdc_id']: r['NDB_number'] for r in read_csv(sr_dir / 'sr_legacy_food.csv')}
    fnd_ndb = {r['fdc_id']: r['NDB_number'] for r in read_csv(fnd_dir / 'foundation_food.csv')}
    sr = usda_load(sr_dir)
    fnd = usda_load(fnd_dir, only_ids=set(fnd_ndb))
    by_ndb = {ndb: fid for fid, ndb in sr_ndb.items()}
    for fid, f in sr.items():
        yield 'usda_sr', fid, f['name'], '', f['category'], f['raw'], f['portions']
    # Foundation Foods zijn nieuwer maar vaak onvolledig: aanvullen uit het overeenkomstige SR-product
    # (dezelfde USDA-code, dus hetzelfde voedingsmiddel). Beide blijven bestaan.
    for fid, f in fnd.items():
        old = sr.get(by_ndb.get(fnd_ndb[fid], ''))
        raw = dict(old['raw']) if old else {}
        raw.update(f['raw'])
        yield 'usda_fnd', fid, f['name'], '', f['category'], raw, f['portions'] or (old['portions'] if old else [])


# ─────────────────────────── CIQUAL (Frankrijk) ───────────────────────────

CIQUAL = {
    '328': 'energy', '400': 'water', '25000': 'protein', '31000': 'carbs', '32000': 'sugars', '33110': 'starch',
    '34100': 'fiber', '40000': 'fat', '40302': 'sfa', '40303': 'mufa', '40304': 'pufa',
    '41833': 'ala', '42053': 'epa', '42263': 'dha', '41826': 'la', '42046': 'aa', '75100': 'cholesterol',
    '60000': 'alcohol', '10004': '_salt', '10110': 'sodium', '10120': 'magnesium', '10150': 'phosphorus',
    '10170': 'chloride', '10190': 'potassium', '10200': 'calcium', '10251': 'manganese', '10260': 'iron',
    '10290': 'copper', '10300': 'zinc', '10340': 'selenium', '10530': 'iodine', '51200': '_retinol',
    '51330': 'beta_carotene', '52100': 'vit_d', '53100': 'vit_e', '54101': 'vit_k', '54104': 'vit_k2',
    '55100': 'vit_c', '56100': 'b1', '56200': 'b2', '56310': 'b3', '56400': 'b5', '56500': 'b6',
    '56600': 'b12', '56700': 'b9',
}


def ciqual_value(s):
    """Getal, None (niet gemeten) of ('<', grens) als de waarde onder de meetgrens lag."""
    s = s.strip()
    if s in ('-', ''):
        return None
    if s == 'traces':
        return 0.0
    if s.startswith('<'):
        return ('<', float(s[1:].strip().replace(',', '.')))
    return float(s.replace(',', '.'))


def xml_records(path, tag):
    text = Path(path).read_text(encoding='windows-1252')
    for m in re.finditer(rf'<{tag}>(.*?)</{tag}>', text, re.S):
        yield {k: v.strip() for k, v in re.findall(r'<(\w+)>(.*?)</\1>', m.group(1), re.S)}


def ciqual_rows(root):
    d = root / 'ciqual'
    files = {k: sorted(glob.glob(str(d / f'{k}_[0-9]*.xml'))) for k in ('alim', 'alim_grp', 'compo')}
    if not all(files.values()):
        print('CIQUAL: niet gevonden, overgeslagen')
        return
    groups = {}
    for g in xml_records(files['alim_grp'][-1], 'ALIM_GRP'):
        groups[g['alim_ssgrp_code']] = g['alim_ssgrp_nom_eng']
    values = {}
    for c in xml_records(files['compo'][-1], 'COMPO'):
        key = CIQUAL.get(c['const_code'])
        if key:
            v = ciqual_value(c.get('teneur', '-'))
            if isinstance(v, tuple):
                # Onder de meetgrens: bij macro's de helft van de grens; bij micro's eerst proberen aan te vullen
                # uit een andere bron (een harde 0 is vaak onrealistisch, bv. selenium in ei), anders 0
                if key in MACROS:
                    values.setdefault(c['alim_code'], {})[key] = v[1] / 2
                else:
                    values.setdefault(c['alim_code'], {}).setdefault('_loq', {})[key] = v[1]
            elif v is not None:
                values.setdefault(c['alim_code'], {})[key] = v
    for a in xml_records(files['alim'][-1], 'ALIM'):
        name = a.get('alim_nom_eng') or a['alim_nom_fr']
        yield 'ciqual', a['alim_code'], name, a['alim_nom_fr'], groups.get(a.get('alim_ssgrp_code'), ''), values.get(a['alim_code'], {}), []


# ─────────────────────────── Livsmedelsverket (Zweden) ───────────────────────────

SLV = {
    ('PROT', 'g'): 'protein', ('CHO', 'g'): 'carbs', ('FIBT', 'g'): 'fiber', ('SUGAR', 'g'): 'sugars',
    ('FAT', 'g'): 'fat', ('FASAT', 'g'): 'sfa', ('FAMS', 'g'): 'mufa', ('FAPU', 'g'): 'pufa', ('FATRN', 'g'): 'trans',
    ('F18:3', 'g'): 'ala', ('F20:5', 'g'): 'epa', ('F22:5', 'g'): 'dpa', ('F22:6', 'g'): 'dha', ('F18:2', 'g'): 'la',
    ('F20:4', 'g'): 'aa', ('CHORL', 'mg'): 'cholesterol', ('WATER', 'g'): 'water', ('ALC', 'g'): 'alcohol',
    ('RETOL', 'µg'): '_retinol', ('CARTBTOT', 'µg'): 'beta_carotene', ('VITD', 'µg'): 'vit_d', ('VITE', 'mg'): 'vit_e',
    ('VITK', 'µg'): 'vit_k', ('THIACLHCL', 'mg'): 'b1', ('THIA', 'mg'): 'b1', ('RIBF', 'mg'): 'b2', ('NIA', 'mg'): 'b3',
    ('VITB6', 'mg'): 'b6', ('FOL', 'µg'): 'b9', ('VITB12', 'µg'): 'b12', ('VITC', 'mg'): 'vit_c',
    ('CA', 'mg'): 'calcium', ('FE', 'mg'): 'iron', ('MG', 'mg'): 'magnesium', ('P', 'mg'): 'phosphorus',
    ('K', 'mg'): 'potassium', ('NA', 'mg'): 'sodium', ('ZN', 'mg'): 'zinc', ('SE', 'µg'): 'selenium',
    ('ID', 'µg'): 'iodine', ('CU', 'mg'): 'copper', ('MN', 'mg'): 'manganese', ('NACL', 'g'): '_salt',
    ('STARCH', 'g'): 'starch',
}


def slv_rows(root):
    d = root / 'slv'
    if not (d / 'index.json').exists():
        print('Livsmedelsverket: niet gevonden, overgeslagen')
        return
    idx = json.loads((d / 'index.json').read_text())
    missing = 0
    for nummer, item in idx['en'].items():
        f = d / f'{nummer}.json'
        if not f.exists():
            missing += 1
            continue
        n = {}
        for v in json.loads(f.read_text())['naringsvarden']:
            if v.get('varde') is None:
                continue
            if v['euroFIRkod'] == 'ENERC':
                if v['enhet'] == 'kcal':
                    n['energy'] = float(v['varde'])
                continue
            key = SLV.get((v['euroFIRkod'], v['enhet']))
            if key and key not in n:
                n[key] = float(v['varde'])
        sv = idx['sv'].get(nummer, {}).get('namn', '')
        yield 'slv', nummer, item.get('namn') or sv, sv, '', n, []
    if missing:
        print(f'Livsmedelsverket: {missing} voedingsmiddelen nog niet opgehaald')


# ─────────────────────────── Matvaretabellen (Noorwegen) ───────────────────────────

MVT = {
    'Vann': 'water', 'Fett': 'fat', 'Mettet': 'sfa', 'Trans': 'trans', 'Enumet': 'mufa', 'Flerum': 'pufa',
    'C18:2n-6Linolsyre': 'la', 'C18:3n-3AlfaLinolensyre': 'ala', 'C20:4n-6Arakidonsyre': 'aa',
    'C20:5n-3Eikosapentaensyre': 'epa', 'C22:5n-3Dokosapentaensyre': 'dpa', 'C22:6n-3Dokosaheksaensyre': 'dha',
    'Omega-3': 'omega3', 'Omega-6': 'omega6', 'Kolest': 'cholesterol', 'Karbo': 'carbs', 'Stivel': 'starch',
    'Mono+Di': 'sugars', 'Fiber': 'fiber', 'Protein': 'protein', 'NaCl': '_salt', 'Alko': 'alcohol',
    'Vit A': 'vit_a', 'Retinol': '_retinol', 'B-karo': 'beta_carotene', 'Vit D': 'vit_d', 'Vit E': 'vit_e',
    'Vit B1': 'b1', 'Vit B2': 'b2', 'Niacin': 'b3', 'Vit B6': 'b6', 'Folat': 'b9', 'Vit B12': 'b12',
    'Vit C': 'vit_c', 'Ca': 'calcium', 'Fe': 'iron', 'Na': 'sodium', 'K': 'potassium', 'Mg': 'magnesium',
    'Zn': 'zinc', 'Se': 'selenium', 'Cu': 'copper', 'P': 'phosphorus', 'I': 'iodine',
}


def mvt_rows(root):
    d = root / 'mvt'
    if not (d / 'foods_en.json').exists():
        print('Matvaretabellen: niet gevonden, overgeslagen')
        return
    foods = json.loads((d / 'foods_en.json').read_text())['foods']
    nb = {f['foodId']: f['foodName'] for f in json.loads((d / 'foods_nb.json').read_text())['foods']} if (d / 'foods_nb.json').exists() else {}
    groups = {}
    if (d / 'food_groups_en.json').exists():
        groups = {g['foodGroupId']: g['name'] for g in json.loads((d / 'food_groups_en.json').read_text())['foodGroups']}
    for f in foods:
        n = {}
        if f.get('calories', {}).get('quantity') is not None:
            n['energy'] = float(f['calories']['quantity'])
        for c in f.get('constituents', []):
            key = MVT.get(c.get('nutrientId'))
            if key and c.get('quantity') is not None:
                n[key] = float(c['quantity'])
        portions = [
            (f"1 {p['portionName']}", sig(float(p['quantity'])))
            for p in f.get('portions', [])
            if p.get('unit') == 'g' and p.get('quantity')
        ]
        yield 'mvt', f['foodId'], f['foodName'], nb.get(f['foodId'], ''), groups.get(f.get('foodGroupId'), ''), n, portions


# ─────────────────────────── Aanvullen tussen bronnen ───────────────────────────
#
# Ontbreekt een voedingsstof bij een product (bv. vitamine B5 bij een Zweedse banaan), dan nemen we de waarde
# over van hetzelfde voedingsmiddel in een ándere bron. "Hetzelfde" is streng:
#   - dezelfde bereiding (rauw, gekookt, gebakken, gedroogd, ...);
#   - de naam van het ene product is een verfijning van het andere ("Banana" en "Bananas, raw"), of ze
#     komen grotendeels overeen;
#   - geen woord dat maar bij één van de twee staat en het product verandert (eiwit/dooier, sap, met/zonder,
#     wild/gekweekt, mager, een ander ingrediënt zoals chocolade, ...);
#   - een vergelijkbare energie (hooguit factor 1,5 verschil).
# Alleen oorspronkelijke waarden worden doorgegeven (nooit een al aangevulde waarde), Europese bronnen eerst,
# en de app toont aangevulde waarden als schatting met de bron erbij.

STOPWORDS = {
    'and', 'or', 'with', 'in', 'of', 'the', 'a', 'an', 'from', 'for', 'on', 'to', 'as', 'by', 'not',
    'pulp', 'flesh', 'edible', 'part', 'portion', 'average', 'unspecified', 'imported', 'norwegian', 'swedish',
    'norway', 'sweden', 'organic', 'uht', 'pasteurised', 'pasteurized', 'sterilised',
    'fish', 'nuts', 'seeds', 'cereals', 'beverages', 'spices', 'vegetables', 'fruits', 'products',
    'prepared', 'commercial', 'commercially', 'type', 'all', 'year', 'ns', 'nfs',
    'g', 'kg', 'mg', 'ml', 'l', 'percent', 'approx', 'about', 'ready', 'eat', 'plain', 'regular', 'whole',
}
STATES = {
    'raw': 'raw', 'uncooked': 'raw', 'fresh': 'raw',
    'cooked': 'wet', 'boiled': 'wet', 'simmered': 'wet', 'steamed': 'wet', 'poached': 'wet', 'stewed': 'wet',
    'blanched': 'wet', 'braised': 'wet',
    'fried': 'dry', 'roasted': 'dry', 'baked': 'dry', 'grilled': 'dry', 'broiled': 'dry', 'toasted': 'dry',
    'sauteed': 'dry', 'microwaved': 'dry',
    'dried': 'dried', 'dehydrated': 'dried', 'dry': 'dried', 'powder': 'dried', 'powdered': 'dried',
    'canned': 'canned', 'tinned': 'canned', 'drained': 'canned', 'preserved': 'canned', 'pickled': 'canned',
    'smoked': 'smoked', 'cured': 'smoked', 'frozen': 'frozen', 'thawed': 'frozen',
}
# Woorden die een ander product of een ander deel aanduiden: komt zo'n woord maar in één van de twee
# namen voor, dan zijn het verschillende voedingsmiddelen.
SIGNIFICANT = {
    'white', 'yolk', 'whey', 'juice', 'nectar', 'oil', 'flour', 'butter', 'milk', 'cream', 'jam', 'jelly', 'sauce', 'soup',
    'chips', 'crisps', 'cake', 'cookie', 'biscuit', 'bar', 'pie', 'syrup', 'paste', 'puree', 'concentrate', 'drink',
    'liver', 'kidney', 'heart', 'tongue', 'skin', 'bone', 'skimmed', 'semi', 'nonfat', 'lowfat', 'low', 'reduced',
    'light', 'lean', 'fat', 'wild', 'farmed', 'sweetened', 'unsweetened', 'sugar', 'dark',
    'brown', 'wholemeal', 'wholegrain', 'wheat', 'red', 'green', 'yellow', 'black', 'baby', 'infant', 'fortified',
    'enriched', 'bran', 'germ', 'sprouted', 'seed', 'leaves', 'leaf', 'stalk', 'root', 'peel', 'zest',
    'without', 'added', 'vitamin', 'hydrogenated', 'margarine', 'spread', 'dressing', 'mayonnaise', 'smoothie',
    # Andere ingrediënten of smaken: staan ze maar in één naam, dan is het een ander product
    'chocolate', 'cocoa', 'vanilla', 'strawberry', 'raspberry', 'blueberry', 'cherry', 'coffee', 'honey', 'caramel',
    'nut', 'almond', 'hazelnut', 'peanut', 'walnut', 'coconut', 'rice', 'pasta', 'noodle', 'bread', 'potato',
    'tomato', 'cheese', 'ham', 'bacon', 'sausage', 'chicken', 'beef', 'pork', 'lamb', 'turkey', 'tuna', 'salmon',
    'shrimp', 'egg', 'mushroom', 'onion', 'garlic', 'apple', 'orange', 'lemon', 'banana', 'pear', 'peach',
    'pineapple', 'mango', 'carrot', 'spinach', 'pea', 'bean', 'lentil', 'corn', 'oat', 'soy', 'tofu', 'yogurt',
    'yoghurt', 'fruit', 'vegetable', 'meat', 'herring', 'mackerel', 'cod', 'sardine', 'anchovy', 'menhaden',
    # Orgaanvlees en bijproducten, en samengestelde gerechten
    'variety', 'offal', 'giblet', 'tripe', 'blood', 'brain', 'stomach', 'lung', 'spleen', 'pancreas', 'thymus',
    'sweetbread', 'gizzard', 'feet', 'ear', 'tail', 'snout', 'chitterling', 'breaded', 'battered', 'coated',
    'immature', 'mature', 'pizza', 'sandwich', 'burger', 'hamburger', 'salad', 'stew',
    'casserole', 'lasagna', 'quiche', 'wrap', 'taco', 'burrito', 'pancake', 'waffle', 'muffin', 'croissant', 'pudding',
    'dessert', 'ice', 'candy', 'cereal', 'breakfast', 'snack', 'dish', 'meal', 'babyfood', 'formula',
}
# "zonder zout" / "met zout" verandert alleen het natrium (dat bijna nooit ontbreekt): niet laten meetellen
SALT_PHRASES = re.compile(r'\b(without|with|no|low) (added )?salt( added)?\b|\bunsalted\b|\bsalted\b')


def singular(w):
    if len(w) > 4 and w.endswith('ies'):
        return w[:-3] + 'y'
    if len(w) > 4 and w.endswith(('oes', 'ches', 'shes', 'sses')):
        return w[:-2]
    if len(w) > 3 and w.endswith('s') and not w.endswith(('ss', 'us', 'is')):
        return w[:-1]
    return w


def name_profile(name):
    """(woorden van het eerste deel, alle inhoudswoorden, bereiding) van een Engelse productnaam."""
    def words(text):
        return [singular(w) for w in re.findall(r'[a-z]+', SALT_PHRASES.sub(' ', text.lower()))]
    first = [w for w in words(name.split(',')[0]) if w not in STOPWORDS and w not in STATES]
    # "no meat" / "without sugar": het woord erna is juist afwezig
    all_words = []
    for w in words(name):
        all_words.append(f'no_{w}' if all_words and all_words[-1] in ('no', 'without', 'non') else w)
    states = {STATES[w] for w in all_words if w in STATES}
    content = {w for w in all_words if w not in STOPWORDS and w not in STATES}
    return set(first), content, frozenset(states) or frozenset({'raw'})


def same_product(head1, first1, head2, first2):
    """Hetzelfde hoofdproduct: elk hoofdwoord komt in het eerste deel van de andere naam voor
    ("Halibut, Atlantic" = "Atlantic halibut", maar "Sesame butter" ≠ "Butter")."""
    return head1 == head2 or (head1 in first2 and head2 in first1)


def head_word(name):
    """Eerste inhoudswoord van de naam: het eigenlijke product ("egg" in "Egg, fried", "turkey" in "Turkey and gravy")."""
    for w in re.findall(r'[a-z]+', name.lower()):
        w = singular(w)
        if w not in STOPWORDS and w not in STATES:
            return w
    return ''


def gap_fill(rows):
    profiles = [name_profile(r['name']) for r in rows]
    heads = [head_word(r['name']) for r in rows]
    by_word = {}
    for i, (first, _, _) in enumerate(profiles):
        for w in first:
            by_word.setdefault(w, []).append(i)
    original = [{k: v for k, v in r['nut'].items() if k not in r.get('bio0', ())} for r in rows]
    filled_total = 0
    for i, r in enumerate(rows):
        first, content, state = profiles[i]
        kcal = r['nut'].get('energy', 0)
        candidates = set()
        for w in first:
            candidates.update(by_word.get(w, ()))
        scored = []
        for j in candidates:
            if j == i:
                continue
            # Alleen uit een andere bron (USDA SR en Foundation tellen als één bron), en hetzelfde product
            # ("Flan with eggs" is geen "Egg", "Sesame butter" geen "Butter")
            if rows[j]['source'][:4] == r['source'][:4] or not same_product(heads[i], first, heads[j], profiles[j][0]):
                continue
            f2, c2, s2 = profiles[j]
            if s2 != state or not (first <= f2 or f2 <= first):
                continue
            if (content ^ c2) & SIGNIFICANT:
                continue
            union = content | c2
            jaccard = len(content & c2) / len(union) if union else 0
            # De ene naam is een verfijning van de andere (met hooguit 2 extra woorden), of ze komen voor
            # minstens 75% overeen
            refinement = (content <= c2 or c2 <= content) and len(content ^ c2) <= 2
            if not (refinement or jaccard >= 0.75):
                continue
            k2 = original[j].get('energy', 0)
            if (kcal < 5 or k2 < 5) and max(kcal, k2) >= 5:
                continue
            if kcal >= 5 and k2 >= 5 and not (0.67 <= kcal / k2 <= 1.5):
                continue
            european = rows[j]['source'] in ('ciqual', 'slv', 'mvt')
            scored.append((-jaccard, 0 if european else 1, -len(original[j]), j))
        if not scored:
            continue
        scored.sort()
        missing = [k for k in ALL_KEYS if k not in r['nut']]
        for k in missing:
            for *_, j in scored:
                if k in original[j]:
                    r['nut'][k] = original[j][k]
                    r['est'][k] = f"{rows[j]['source']}:{rows[j]['sid']}"
                    filled_total += 1
                    break
    return filled_total


# ─────────────────────────── Controle en correcties ───────────────────────────
#
# Fouten in de bronnen zelf (eenheidsfouten, tikfouten) staan met uitleg in tool/food_fixes.json en worden
# toegepast vóór het aanvullen, zodat een fout niet doorgegeven wordt. Daarnaast vaste regels:
#   - aminozuren die niet bij het eiwit passen (meer dan het eiwit zelf) zijn per droge stof of fout: weg;
#   - een zuiver plantaardig product heeft geen B12, cholesterol, vitamine D (behalve paddenstoelen) of
#     EPA/DHA/DPA/arachidonzuur: ontbreekt het, dan is het 0, en het wordt nooit geschat uit een verrijkt product;
#   - na het aanvullen mogen geschatte deelwaarden niet groter zijn dan het totaal (suikers + zetmeel ≤
#     koolhydraten, vetzuren ≤ vet, omega-delen ≤ meervoudig onverzadigd).
FIXES_FILE = Path(__file__).with_name('food_fixes.json')

ANIMAL_WORDS = re.compile(
    r'\b(beef|pork|lamb|mutton|veal|chicken|turkey|duck|goose|hen|broiler|meat|liver|kidney|heart|tongue|tripe|ham|bacon|'
    r'sausage|salami|frankfurter|fish|salmon|tuna|cod|herring|mackerel|sardine|anchov\w*|trout|haddock|pollock|plaice|eel|'
    r'shrimps?|prawns?|crab|lobster|mussels?|oysters?|clams?|scallops?|squid|octopus|roe|caviar|eggs?|yolk|milk|cheese|'
    r'yog(h)?urt|butter|cream|whey|casein|venison|rabbit|horse|elk|moose|reindeer|deer|game|offal|gelatin|lard|tallow|'
    r'suet|blood|bone|marrow|pheasant|quail|pigeon|ostrich|bison|buffalo|goat|kefir|quark|skyr|ghee|honey|gnocchi|'
    r'souffl\w*|pancakes?|noodles?|pasta|dauphine|custard|mayonnaise|puree|creamed|mashed)\b',
    re.I,
)
MIXED_WORDS = re.compile(
    r'\b(with|and|in|w|dish|meal|sandwich|pizza|soup|salad|sauce|stew|casserole|pie|burger|breaded|battered|coated|stuffed|'
    r'filled|fortified|enriched|added|enhanced|infant|baby|babyfood|toddler|formula|supplement|mix|ready|prepared|restaurant|'
    r'fast food|cake|biscuit|cookie|bread|vegetarian|vegan|meatless|imitation|substitute|analogue|style|smoothie|juice|'
    r'drink|beverage|soymilk|tofu|silk|vitasoy|creamer|spread|burgers?|patty|patties|luncheon|meatballs|bar|cereals?)\b',
    re.I,
)
PLANT_CATS = re.compile(
    r'^(vegetables.*|fruits?( and fruit juices)?|legumes.*|nut and seed products|cereal grains and pasta|spices and herbs|'
    r'herbs( and spices)?|vegetable oils|berries|fruit and berries products|flour|potatoes and other tubers|'
    r'nuts and seeds|legumes|vegetables, raw and prepared|vegetable products|grain, rice and pasta|pasta, rice and grains|'
    r'fruit|vegetables|fruits)$',
    re.I,
)
ANIMAL_CATS = re.compile(
    r'^(beef products|pork products|lamb, veal, and game products|poultry products|finfish and shellfish products|raw meat|'
    r'cooked meat|fish, raw|fish, cooked|lean fish|fatty fish|shellfish|poultry|milk|meat|eggs?|offal)$',
    re.I,
)
PLANT_NAME_HINT = re.compile(
    r'\b(bean|beans|pea|peas|lentils?|chickpeas?|soy\w*|tofu|nuts?|almonds?|peanuts?|seeds?|rice|wheat|oats?|barley|rye|corn|'
    r'maize|flour|potato\w*|tomato\w*|carrots?|cabbage|spinach|lettuce|onions?|garlic|apples?|pears?|banana\w*|orange\w*|'
    r'berr(y|ies)|grapes?|plums?|cherr(y|ies)|peach\w*|melon|mushrooms?|kale|broccoli|cauliflower|pepper|cucumber|squash|'
    r'pumpkin|avocado|olive|coconut|dates?|figs?|raisins?|lemon|lime|herb|spice|leaves|root|sprouts?|algae|seaweed|kelp)\b',
    re.I,
)
MUSHROOM = re.compile(r'\b(mushrooms?|fungi|shiitake|chanterelles?|morels?|maitake|champignons?|enoki|portabella|crimini)\b', re.I)
ANIMAL_ONLY = ('b12', 'cholesterol', 'epa', 'dha', 'dpa', 'aa', 'vit_d')


NUT_BUTTER = re.compile(r'\b(peanut|almond|cashew|sesame|nut|seed|cocoa|shea|soy|sunflower|hazelnut|pistachio|macadamia|'
                        r'pecan|walnut|pumpkin seed)s? butter', re.I)


def kind(name, cat):
    """'plant' of 'dier' als het product zuiver plantaardig of zuiver dierlijk is, anders None (gemengd/onbekend)."""
    name = NUT_BUTTER.sub(r'\1 nutbutter', name)  # pindakaas, sesampasta en cacaoboter zijn geen boter
    if MIXED_WORDS.search(name):
        return None
    if PLANT_CATS.match(cat or '') and not ANIMAL_WORDS.search(name):
        return 'plant'
    if ANIMAL_CATS.match(cat or '') and not PLANT_NAME_HINT.search(name):
        return 'dier'
    return None


def apply_fixes(rows):
    if not FIXES_FILE.exists():
        return 0
    fixes = json.loads(FIXES_FILE.read_text())['fixes']
    by_ref = {f"{r['source']}:{r['sid']}": r for r in rows}
    done = 0
    for ref, change in fixes.items():
        r = by_ref.get(ref)
        if r is None:
            print(f'correctie voor onbekend product {ref}')
            continue
        for k, v in change.items():
            if k == '_name':
                r['name'] = v
                continue
            if k.startswith('_'):
                continue
            if v is None:
                r['nut'].pop(k, None)
            else:
                r['nut'][k] = float(v)
            done += 1
    return done


def validate_measured(r):
    n = r['nut']
    # USDA geeft mangaan in zuigelingenvoeding soms in µg met als eenheid mg (77 "mg" = 77 µg)
    if re.search(r'\b(infant|toddler|formula)\b', r['name'], re.I) and n.get('manganese', 0) > 2:
        n['manganese'] /= 1000
    aa = sum(n.get(k, 0) for k in AMINO)
    if any(k in n for k in AMINO) and (aa > n.get('protein', 0) + 0.5 or (n.get('protein', 0) == 0 and aa > 0.3)):
        for k in AMINO:
            n.pop(k, None)
    # Totaal kleiner dan zijn gemeten delen: het totaal is fout (de delen zijn gedetailleerder gemeten)
    for total, parts in (('pufa', PUFA_PARTS), ('carbs', ('sugars', 'starch'))):
        present = [p for p in parts if p in n]
        if total in n and present:
            n[total] = max(n[total], sum(n[p] for p in present))


def plant_zeros(r):
    if kind(r['name'], r['category']) != 'plant':
        return 0
    z = 0
    for k in ANIMAL_ONLY:
        if k == 'vit_d' and MUSHROOM.search(r['name']):
            continue
        if k not in r['nut']:
            r['nut'][k] = 0.0
            r.setdefault('bio0', set()).add(k)
            z += 1
    return z


def consistency(r):
    """Geschatte deelwaarden inkorten tot ze samen met de gemeten delen niet boven het totaal uitkomen."""
    n, est = r['nut'], r['est']
    for total, parts in (('carbs', ('sugars', 'starch')), ('fat', ('sfa', 'mufa', 'pufa', 'trans')), ('pufa', tuple(PUFA_PARTS))):
        if total not in n:
            continue
        known = sum(n[p] for p in parts if p in n and p not in est)
        if total in est and known > n[total]:
            n[total] = known
        guessed = [p for p in parts if p in n and p in est]
        if not guessed:
            continue
        room = n[total] - sum(n[p] for p in parts if p in n and p not in est)
        g = sum(n[p] for p in guessed)
        if g > max(0.0, room) * 1.02 and g > 0:
            f = max(0.0, room) / g
            for p in guessed:
                n[p] *= f
    aa = sum(n.get(k, 0) for k in AMINO)
    if aa > n.get('protein', 0) * 0.65 + 0.3:
        for k in AMINO:
            if k in est:
                n.pop(k)
                est.pop(k)


# Tweede ronde, voor wat daarna nog ontbreekt: een vergelijkbaar product, ook met een andere bereiding of uit
# dezelfde bron (bv. choline voor "gebakken ei" uit "ei, rauw"). Omdat water en vet dan verschillen, schalen we:
#   - vetzuren met het vetgehalte;
#   - aminozuren met het eiwit;
#   - de rest (mineralen, vitamines, choline, cholesterol) met de vetvrije droge stof (100 - water - vet).
# Strenger op de naam dan op de bereiding: hetzelfde hoofdwoord, geen ander SIGNIFICANT woord, en de namen
# komen voor minstens de helft overeen. Hoofdbestanddelen (eiwit, koolhydraten, vet, water…) vullen we zo nooit aan.
# Bereidingen die in de tweede ronde niet tellen: het verschil in vet en water wordt weggeschaald
PREP_PHRASES = re.compile(
    r'\b((fried|cooked|baked|roasted) )?(in|with|without) (added )?(fat|oil|butter|margarine)\b|'
    r'\b(scrambled|sliced|slices|diced|chopped|pan|stir|saut[eé]e?d?|whole|halves|pieces?)\b', re.I)
PREP_WORDS = {'added', 'without'}
FATTY = {'sfa', 'mufa', 'pufa', 'trans', 'la', 'ala', 'aa', 'epa', 'dpa', 'dha'}
AMINO = {'histidine', 'isoleucine', 'leucine', 'lysine', 'methionine', 'cystine', 'phenylalanine', 'tyrosine',
         'threonine', 'tryptophan', 'valine'}


# In vet opgelost (boter, room, kaas): bij producten van bijna alleen vet en water schalen met het vet
FAT_SOLUBLE = {'vit_a', 'vit_d', 'vit_e', 'vit_k', 'beta_carotene', 'cholesterol', 'lutein_zeaxanthin', 'lycopene'}


def _fatty_product(n):
    f = _ffdm(n)
    return f is not None and f < 3 and n.get('fat', 0) > 5


def _ffdm(n):
    if 'water' not in n:
        return None
    return max(0.5, 100 - n['water'] - n.get('fat', 0) - n.get('alcohol', 0))


PUFA_PARTS = {'la', 'ala', 'aa', 'epa', 'dpa', 'dha'}
SALTY = {'sodium', 'chloride', 'iodine'}


def _scale(key, target, donor):
    if key in PUFA_PARTS and target.get('pufa') is not None and donor.get('pufa'):
        a, b = target['pufa'], donor['pufa']
    elif key in FATTY or (key in FAT_SOLUBLE and (_fatty_product(target) or _fatty_product(donor))):
        a, b = target.get('fat'), donor.get('fat')
    elif key in AMINO:
        a, b = target.get('protein'), donor.get('protein')
    else:
        a, b = _ffdm(target), _ffdm(donor)
    if a is None or b is None:
        return 1.0
    # Bijna alleen vet en water (margarine, olie): de vetvrije droge stof is te klein om betrouwbaar mee te schalen
    if key not in FATTY and key not in AMINO and key not in PUFA_PARTS and key not in FAT_SOLUBLE and min(a, b) < 3:
        return 1.0
    if b <= 0.05:
        return None if a > 0.05 else 1.0
    return min(20.0, max(0.05, a / b))


def similar_fill(rows):
    profiles = [name_profile(PREP_PHRASES.sub(' ', r['name'])) for r in rows]
    heads = [head_word(r['name']) for r in rows]
    by_word = {}
    for i, (first, _, _) in enumerate(profiles):
        for w in first:
            by_word.setdefault(w, []).append(i)
    measured = [{k: v for k, v in r['nut'].items() if k not in r['est'] and k not in r.get('bio0', ())} for r in rows]
    filled = 0
    for i, r in enumerate(rows):
        missing = [k for k in ALL_KEYS if k not in r['nut'] and k not in MACROS]
        if not missing:
            continue
        first, content, state = profiles[i]
        head = heads[i]
        candidates = set()
        for w in first:
            candidates.update(by_word.get(w, ()))
        scored = []
        for j in candidates:
            if j == i:
                continue
            f2, c2, s2 = profiles[j]
            if not same_product(head, first, heads[j], f2):
                continue
            if not (first <= f2 or f2 <= first) or (content ^ c2) & SIGNIFICANT - PREP_WORDS:
                continue
            # Het eerste deel van de naam (het eigenlijke product) moet grotendeels hetzelfde zijn:
            # "Egg roll" is geen "Roll, egg"
            if len(first & f2) / len(first | f2 or {''}) < 0.5:
                continue
            union = content | c2
            jaccard = len(content & c2) / len(union) if union else 0
            if jaccard < 0.6:
                continue
            # Elk een eigen woord (bever / hert, selder / asperge): alleen als de namen verder sterk overeenkomen
            if content - c2 and c2 - content and jaccard < 0.75:
                continue
            european = rows[j]['source'] in ('ciqual', 'slv', 'mvt')
            # Dezelfde bereiding eerst: hoe kleiner het verschil in water, hoe betrouwbaarder het schalen
            scored.append((0 if s2 == state else 1, -jaccard, 0 if european else 1, -len(measured[j]), j))
        if not scored:
            continue
        scored.sort()
        for k in missing:
            for st, *_, j in scored:
                if k in measured[j]:
                    # Zout en jodium hangen af van pekelen, roken of zouten: alleen uit dezelfde bereiding
                    if k in SALTY and (st or profiles[j][2] != state):
                        continue
                    f = _scale(k, r['nut'], rows[j]['nut'])
                    if f is None:
                        continue
                    r['nut'][k] = measured[j][k] * f
                    # "~" = vergelijkbaar product, geschaald (de app toont dat anders dan "hetzelfde product")
                    r['est'][k] = f"~{rows[j]['source']}:{rows[j]['sid']}"
                    filled += 1
                    break
    return filled


# Derde ronde, voor wat dan nog ontbreekt: de mediaan van vergelijkbare producten, per gram vetvrije droge stof
# (of per gram vet / eiwit, zoals hierboven). Eerst producten met hetzelfde hoofdwoord ("cheese", "beef"), uit
# alle bronnen, met minstens 5 gemeten waarden; anders dezelfde categorie binnen de bron (minstens 15).
# Een ontbrekende waarde telt in de app als 0, en dat is bij bv. choline in vlees of jodium in vis zeker fout.
def _basis(key, n):
    if key in FATTY or (key in FAT_SOLUBLE and _fatty_product(n)):
        return n.get('fat')
    if key in AMINO:
        return n.get('protein')
    return _ffdm(n)


def last_noun(name):
    """Laatste inhoudswoord van het eerste deel van de naam ("pasta" in "Dried egg pasta, raw")."""
    part = re.split(r'\b(?:with|in|and|w|on|of|from)\b', name.split(',')[0].lower())[0]
    words = [singular(w) for w in re.findall(r'[a-z]+', part)]
    words = [w for w in words if w not in STOPWORDS and w not in STATES]
    return words[-1] if words else ''


# Plantaardige vervangers: B12 en vitamine D zijn daar vaak toegevoegd, dus nooit schatten uit verwante producten
FORTIFIABLE = re.compile(r'\b(soy\w*|tofu|vegan|vegetarian|meatless|plant|almond milk|oat drink|rice drink|silk|vitasoy|'
                         r'cereals?|juice|smoothie|formula|infant|toddler|margarine|spread|yeast)\b', re.I)


def group_fill(rows):
    measured = [{k: v for k, v in r['nut'].items() if k not in r['est'] and k not in r.get('bio0', ())} for r in rows]
    profiles = [name_profile(r['name']) for r in rows]
    # Vergelijkbaar = dezelfde betekenisvolle woorden én allebei gedroogd of allebei niet (gedroogde erwten zijn geen
    # verse erwten: vitamine C en caroteen verdwijnen bij het drogen)
    sig = [(frozenset(p[1] & SIGNIFICANT), 'dried' in p[2]) for p in profiles]
    tables = {}
    for i, r in enumerate(rows):
        if r['category'] in SKIP_GROUP_CATEGORIES:
            continue
        for key in (('n', last_noun(r['name'])), ('h', head_word(r['name'])), ('c', r['source'][:4], r['category'])):
            if key[-1]:
                tables.setdefault(key, []).append(i)
    cache = {}

    def median(group, s_t, k, minimum, fatty=False):
        if group[0] == 'a':  # zelfde hoofdwoord, ongeacht de andere woorden (laatste redmiddel)
            # In vet opgeloste vitamines mogen breed geschat worden bij boter, room en olie (gaan mee met het vet)
            if k not in BROAD_OK and not (fatty and k in FAT_SOLUBLE):
                return None
            group, s_t = ('n', group[1]), ('any', s_t[1], fatty)
        ck = (group, s_t, k)
        if ck not in cache:
            vals, top = [], 0.0
            for j in tables.get(group, ()):
                # Alleen leden met dezelfde "betekenisvolle" woorden: geen mosterdblad voor mosterd, geen eierpasta voor pasta
                if group[0] != 'c' and (sig[j][1] != s_t[1] if s_t[0] == 'any' else sig[j] != s_t):
                    continue
                # Breed schatten voor boter of olie: alleen uit andere vette producten (geen boterbonen)
                if s_t[0] == 'any' and s_t[2] and not _fatty_product(rows[j]['nut']):
                    continue
                b = _basis(k, rows[j]['nut'])
                # Per gram vetvrije droge stof is onstabiel bij bijna puur vet (boter, olie): die tellen niet mee
                if k in measured[j] and b and b > (0.5 if k in FATTY or k in AMINO else 3):
                    vals.append(measured[j][k] / b)
                    top = max(top, measured[j][k])
            cache[ck] = (statistics.median(vals), top) if len(vals) >= minimum else None
        return cache[ck]

    filled = 0
    for i, r in enumerate(rows):
        if r['category'] in SKIP_GROUP_CATEGORIES:
            continue
        # Onder de meetgrens gemeten: geen groepsgemiddelde (dat ligt vaak boven de grens), dan wordt het 0
        missing = [k for k in ALL_KEYS if k not in r['nut'] and k not in MACROS and k not in RARE and k not in r['loq']]
        if not missing:
            continue
        fortifiable = bool(FORTIFIABLE.search(r['name']))
        noun, head = last_noun(r['name']), head_word(r['name'])
        # Te algemene eerste woorden ("Beverages, …", "Snacks, …"): meteen de categorie
        if noun in GENERIC_HEADS:
            noun = ''
        if head in GENERIC_HEADS:
            head = ''
        for k in missing:
            if fortifiable and k in ('b12', 'vit_d'):
                continue
            b = _basis(k, r['nut'])
            if b is None:
                continue
            for label, group, minimum in ((f'head:{noun}', ('n', noun), 5), (f'head:{head}', ('h', head), 5),
                                          (f'cat:{r["category"]}', ('c', r['source'][:4], r['category']), 15),
                                          # Noorse en Zweedse tabellen meten bv. geen choline: dan alle producten met
                                          # hetzelfde hoofdwoord ("salad", "noodle"), uit alle bronnen
                                          (f'head:{noun}', ('a', noun), 10)):
                # Het eerste woord als groep alleen bij namen zonder komma's (Zweedse stijl: "Mustard Swedish sweet");
                # bij "Egg custards, dry mix" of "Sea belt, dried" zou dat ei of zeebaars geven
                if not group[-1] or (group[0] == 'h' and ',' in r['name']):
                    continue
                m = median(group, sig[i], k, minimum, _fatty_product(r['nut']))
                if m is not None:
                    # Nooit meer dan het hoogste gemeten product in die groep
                    r['nut'][k] = min(m[0] * b, m[1])
                    r['est'][k] = f'~~{label}'
                    filled += 1
                    break
    return filled


SKIP_GROUP_CATEGORIES = {'Food supplements'}
# Wat zo breed geschat mag worden: stoffen die vooral met de soort product en de droge stof meegaan. Niet vitamine C,
# carotenen, vitamine A/K of jodium: die verschillen te sterk tussen producten met hetzelfde hoofdwoord
# (witte peper ≠ paprika).
BROAD_OK = {'choline', 'b5', 'manganese', 'copper', 'selenium', 'zinc', 'magnesium', 'phosphorus', 'potassium',
            'b1', 'b2', 'b3', 'b6', 'b9', 'vit_e'} | AMINO
GENERIC_HEADS = {'beverage', 'snack', 'restaurant', 'fast', 'babyfood', 'candie', 'candy', 'dessert', 'cereal', 'alcoholic',
                 'leavening', 'mix', 'spice', 'food', 'product', 'dish', 'meal', 'side', 'entree', 'sweet', 'topping',
                 'frozen', 'formula', 'infant', 'toddler', 'school', 'lunch', 'sea'}


# Zelden gemeten en zonder betrouwbaar gemiddelde: niet via een groep schatten
RARE = {'b7', 'chromium', 'molybdenum', 'fluoride', 'vit_k2', 'chloride'}


# Alle voedingsstoffen die aangevuld mogen worden. Energie niet (dat is de controle), en de totalen
# omega-3 en omega-6 worden daarna opnieuw berekend uit de delen.
ALL_KEYS = sorted(({k for k in USDA if not k.startswith('_')} | {'carbs', 'chloride'}) - {'energy', 'omega3', 'omega6'})


# ─────────────────────────── Samenvoegen ───────────────────────────

def main(root, target):
    root = Path(root).expanduser()
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.unlink(missing_ok=True)
    db = sqlite3.connect(target)
    db.executescript('''
        CREATE TABLE foods (
          id INTEGER PRIMARY KEY,
          source TEXT NOT NULL,
          source_id TEXT NOT NULL,
          name TEXT NOT NULL,
          name_local TEXT NOT NULL,
          search TEXT NOT NULL,
          category TEXT NOT NULL,
          nutrients TEXT NOT NULL,
          estimated TEXT NOT NULL,
          UNIQUE (source, source_id)
        );
        CREATE TABLE portions (food_id INTEGER NOT NULL, label TEXT NOT NULL, grams REAL NOT NULL);
        CREATE INDEX portions_food ON portions(food_id);
        CREATE TABLE sources (source TEXT PRIMARY KEY, description TEXT NOT NULL, foods INTEGER NOT NULL);
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    ''')
    rows = []
    for gen in (ciqual_rows, slv_rows, mvt_rows, usda_rows):
        for source, sid, name, local, category, raw, portions in gen(root):
            loq, retinol = {}, None
            if source.startswith('usda'):
                if category in USDA_SKIP_CATEGORIES:
                    continue
                nut = usda_nutrients(raw)
            else:
                loq = raw.pop('_loq', {})
                # Vitamine A die we zelf uit retinol + bètacaroteen berekenen: na het aanvullen van bètacaroteen opnieuw
                retinol = (raw.get('_retinol', 'unknown')) if 'vit_a' not in raw else None
                nut = finish(raw)
            if 'energy' not in nut or not name:
                continue
            rows.append({'source': source, 'sid': sid, 'name': name, 'local': local, 'category': category,
                         'nut': nut, 'est': {}, 'portions': portions, 'loq': loq, 'retinol': retinol})

    print(f'correcties uit {FIXES_FILE.name}: {apply_fixes(rows)} waarden')
    for r in rows:
        validate_measured(r)
    print(f'plantaardig zonder B12/cholesterol/…: {sum(plant_zeros(r) for r in rows)} waarden op 0')

    before = sum(len(r['nut']) for r in rows)
    filled = gap_fill(rows)
    print(f'aangevuld: {filled} waarden ({filled / before * 100:.0f}% extra), '
          f'{sum(1 for r in rows if r["est"])} van {len(rows)} producten')
    similar = similar_fill(rows)
    print(f'aangevuld uit een vergelijkbaar product (geschaald): {similar} waarden')
    grouped = group_fill(rows)
    print(f'aangevuld uit het gemiddelde van vergelijkbare producten: {grouped} waarden')
    # Wat onder de meetgrens lag en nergens anders gevonden werd, is praktisch 0
    zero = 0
    for r in rows:
        for k in r['loq']:
            if k not in r['nut']:
                r['nut'][k] = 0.0
                zero += 1
    print(f'onder de meetgrens, op 0 gezet: {zero} waarden')
    for r in rows:
        consistency(r)
        bc = r['nut'].get('beta_carotene')
        if r['retinol'] == 'unknown' and bc is not None and kind(r['name'], r['category']) == 'plant':
            # Planten bevatten geen retinol: vitamine A = bètacaroteen / 12
            r['nut']['vit_a'] = bc / 12
            r['est'].pop('vit_a', None)
            if 'beta_carotene' in r['est']:
                r['est']['vit_a'] = r['est']['beta_carotene']
        elif isinstance(r['retinol'], float) and 'beta_carotene' in r['est'] and bc:
            r['nut']['vit_a'] = r['retinol'] + bc / 12
            r['est']['vit_a'] = r['est']['beta_carotene']

    counts = {}
    for r in rows:
        nut, est = r['nut'], r['est']
        derive(nut, est)
        cur = db.execute(
            'INSERT INTO foods (source, source_id, name, name_local, search, category, nutrients, estimated) VALUES (?,?,?,?,?,?,?,?)',
            (r['source'], r['sid'], r['name'], r['local'], f"{r['name']} {r['local']}".lower(), r['category'],
             json.dumps({k: sig(v) for k, v in nut.items()}, separators=(',', ':'), ensure_ascii=False),
             json.dumps(est, separators=(',', ':'))),
        )
        for label, grams in dict.fromkeys(r['portions']):
            db.execute('INSERT INTO portions VALUES (?,?,?)', (cur.lastrowid, label, grams))
        counts[r['source']] = counts.get(r['source'], 0) + 1
    db.executemany('INSERT INTO sources VALUES (?,?,?)', [(s, SOURCES[s], c) for s, c in counts.items()])
    # Versie = vingerafdruk van alle waarden: verandert ze, dan werkt de app de dagboekregels van ingebouwde producten bij
    digest = hashlib.sha1()
    for (nut,) in db.execute('SELECT nutrients FROM foods ORDER BY id'):
        digest.update(nut.encode())
    db.execute('INSERT INTO meta VALUES (?, ?)', ('version', digest.hexdigest()[:12]))
    db.commit()
    db.execute('VACUUM')
    db.close()
    for s, c in counts.items():
        print(f'{s:9} {c:6}  {SOURCES[s]}')
    print(f'totaal {sum(counts.values())} -> {target} ({target.stat().st_size / 1e6:.1f} MB)')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
