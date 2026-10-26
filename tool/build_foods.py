"""
Bouwt assets/db/foods.db: de ingebouwde database met basisvoedingsmiddelen uit meerdere bronnen.

Bronnen (zet ze in één map, elk in een eigen submap):
  ciqual/  ANSES-CIQUAL 2020, Frankrijk (Licence Ouverte): XML-zip van https://ciqual.anses.fr, uitgepakt
  slv/     Livsmedelsverket, Zweden (CC BY 4.0): ophalen met tool/fetch_slv.py
  bls4/    BLS 4.0, Max Rubner-Institut, Duitsland (CC BY 4.0): zip van https://blsdb.de/download, uitgepakt
  mvt/     Matvaretabellen, Noorwegen (NLOD): foods_en.json, foods_nb.json, food_groups_en.json
           van https://www.matvaretabellen.no/api/{en,nb}/...
  FoodData_Central_sr_legacy_food_csv_*/ en FoodData_Central_foundation_food_csv_*/
           USDA FoodData Central, VS (publiek domein): CSV-zips van https://fdc.nal.usda.gov/download-datasets
  FoodData_Central_survey_food_csv_*/
           USDA FNDDS (Survey Foods), VS (publiek domein), zelfde downloadpagina: alleen de samengestelde gerechten
           (zie fndds_rows)

Bronnen die ontbreken, worden overgeslagen.

Gebruik:
    python3 tool/build_foods.py <bronmap> assets/db/foods.db

Elke bron blijft een apart product (geen gemiddelden): definities en producten verschillen per land.
Wel worden de waarden gelijkgetrokken naar één definitie per voedingsstof:
  - koolhydraten = beschikbare koolhydraten in gewicht (Europese definitie, zonder vezels); CoFID geeft ze als
    monosacharide-equivalenten en wordt omgerekend (zie cofid_carbs_to_weight)
  - vitamine A = µg RE, retinolequivalenten (retinol + bètacaroteen / 6), zoals de EFSA-richtwaarden (zie VIT_A_BC);
    het voorgevormde retinol staat er apart bij ('retinol'), voor de EFSA-bovengrens van 3000 µg per dag
  - B3 = mg NE, niacine-equivalenten (voorgevormde niacine + tryptofaan / 60), zoals de EFSA-richtwaarde (zie niacin_ne)
Daarna worden onwaarschijnlijke gemeten waarden opgespoord en weggelaten (zie outlier_pass, verslag in
tool/outlier_report.md).
De sleutels (energy, protein, vit_c, ...) komen overeen met lib/nutrition/nutrients.dart; waarden per 100 g.
"""
import csv
import glob
import hashlib
import html
import json
import os
import random
import re
import sqlite3
import statistics
import sys
from pathlib import Path

# Volgorde in de app: lager = eerst getoond bij zoekresultaten van gelijke kwaliteit (Europa eerst)
SOURCES = {
    'ciqual': 'ANSES-CIQUAL 2025 (Frankrijk), Licence Ouverte 2.0',
    'cofid': "McCance and Widdowson's Composition of Foods Integrated Dataset 2021 (VK), Open Government Licence v3.0",
    'frida': 'Frida, DTU Fødevareinstituttet, versie 6.1 (Denemarken), CC BY 4.0',
    'bls': 'Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 (Duitsland), CC BY 4.0',
    'slv': 'Livsmedelsverket, Livsmedelsdatabasen (Zweden), CC BY 4.0',
    'mvt': 'Matvaretabellen, Mattilsynet (Noorwegen), NLOD',
    'usda_fnd': 'USDA FoodData Central, Foundation Foods (VS), publiek domein',
    'usda_sr': 'USDA FoodData Central, SR Legacy (VS), publiek domein',
    'usda_fndds': 'USDA FoodData Central, FNDDS 2021-2023 (VS), publiek domein',
}


# Vitamine A in RE (retinolequivalenten): 1 µg RE = 1 µg retinol = 6 µg bètacaroteen = 12 µg andere provitamine-A-
# carotenoïden (alfacaroteen, bètacryptoxanthine). Waarom RE en niet RAE (bètacaroteen / 12, VS): de doelen in de app
# zijn de EFSA-PRI's (2015: 750 µg man, 650 µg vrouw), en die staan in RE. Een RAE-waarde tegenover een RE-doel
# telt plantaardige vitamine A half zo zwaar (bevinding NF-17). Bronnen in RAE (USDA, Matvaretabellen) rekenen we om:
# RE = RAE + bètacaroteen / 12 + (alfacaroteen + bètacryptoxanthine) / 24.
VIT_A_BC = 6

# Niacine-equivalenten: 1 mg NE = 1 mg niacine = 60 mg tryptofaan (EFSA 2014: PRI 1,6 mg NE/MJ)
TRP_PER_NE = 60


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
    # Vitamine A als RE uit retinol en bètacaroteen, als de bron het niet zelf gaf. Zonder retinol niet:
    # bij boter of kaas zou alleen bètacaroteen/6 veel te weinig zijn (dat wordt later aangevuld)
    if 'vit_a' not in n and 'retinol' in n:
        n['vit_a'] = n.get('retinol', 0) + n.get('beta_carotene', 0) / VIT_A_BC
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
    'retinol': ('µg', [1105]),
    'beta_carotene': ('µg', [1107]),
    '_alpha_carotene': ('µg', [1108]),
    '_cryptoxanthin': ('µg', [1120]),
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
EUROPEAN = ('ciqual', 'slv', 'mvt', 'frida', 'cofid', 'bls')

# Hoofdbestanddelen: die vullen we nooit met een geschaalde waarde van een ander product aan
MACROS = {'energy', 'protein', 'carbs', 'fat', 'fiber', 'sugars', 'starch', 'water', 'alcohol', '_salt'}

USDA_SKIP_CATEGORIES = {'Quality Control Materials', 'Branded Food Products Database'}


def usda_load(d, only_ids=None, by_number=False):
    """[by_number]: food_nutrient.csv verwijst met het oude voedingsstofnummer (nutrient_nbr, bv. 208 voor energie)
    in plaats van het id (1008), zoals in FNDDS."""
    nutrients = list(read_csv(d / 'nutrient.csv'))
    units = {r['id']: r['unit_name'] for r in nutrients}
    nbr_id = {r['nutrient_nbr']: r['id'] for r in nutrients if r.get('nutrient_nbr')} if by_number else {}
    # FNDDS heeft geen food_category.csv maar de WWEIA-categorieën (zelfde kolom food_category_id in food.csv)
    if (d / 'food_category.csv').exists():
        cats = {r['id']: r['description'] for r in read_csv(d / 'food_category.csv')}
    else:
        cats = {r['wweia_food_category']: r['wweia_food_category_description'] for r in read_csv(d / 'wweia_food_category.csv')}
    foods = {}
    for r in read_csv(d / 'food.csv'):
        if only_ids is not None and r['fdc_id'] not in only_ids:
            continue
        foods[r['fdc_id']] = {'name': r['description'].strip(), 'category': cats.get(r['food_category_id'], ''), 'raw': {}, 'portions': []}
    for r in read_csv(d / 'food_nutrient.csv'):
        f = foods.get(r['fdc_id'])
        if f is not None and r['amount'] != '':
            nid = nbr_id.get(r['nutrient_id'], r['nutrient_id']) if by_number else r['nutrient_id']
            f['raw'][int(nid)] = (float(r['amount']), units.get(nid, ''))
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
    # USDA geeft vitamine A als RAE; omrekenen naar RE (zie VIT_A_BC). Ontbreekt retinol zelf, dan volgt het uit de
    # RAE min het caroteendeel (zie retinol_from_rae)
    if 'vit_a' in out:
        other = out.get('_alpha_carotene', 0) + out.get('_cryptoxanthin', 0)
        if 'retinol' not in out:
            retinol_from_rae(out, out['vit_a'], other)
        out['vit_a'] = rae_to_re(out['vit_a'], out.get('beta_carotene'), other)
    return finish({k: max(0.0, v) for k, v in out.items()})


def retinol_from_rae(n, rae, other_carotenoids=0.0):
    """Voorgevormd retinol = RAE − bètacaroteen / 12 − andere carotenoïden / 24, als de bron het niet apart gaf.
    Alleen met een gemeten bètacaroteen (anders is niet te zeggen welk deel uit caroteen komt): dan blijft het onbekend
    en wordt het later geschat zoals elke ontbrekende waarde."""
    if n.get('beta_carotene') is None:
        return
    n['retinol'] = max(0.0, rae - n['beta_carotene'] / 12 - (other_carotenoids or 0) / 24)
    CHANGES['retinol_derived'] += 1


def rae_to_re(rae, beta_carotene, other_carotenoids=0.0):
    """RAE (bètacaroteen / 12, andere / 24) naar RE (bètacaroteen / 6, andere / 12): het verschil erbij."""
    if beta_carotene or other_carotenoids:
        CHANGES['vit_a_re_from_rae'] += 1
    return rae + (beta_carotene or 0) / 12 + (other_carotenoids or 0) / 24


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


# FNDDS (Food and Nutrient Database for Dietary Studies): wat Amerikanen echt eten, als gerecht (lasagne, taco, soep,
# stoofpot, ontbijtgranen met melk). De waarden zijn door de USDA berekend uit de ingrediënten (SR Legacy en
# Foundation, met kookverliezen). We nemen alleen de samengestelde gerechten: een product met één ingrediënt is in FNDDS
# een kopie van een SR-product dat er al is (dat gaf dubbels). Babyvoeding, zuigelingenvoeding en moedermelk niet.
FNDDS_SKIP_CATEGORY = re.compile(r'^(human milk|baby |formula,)', re.I)
# Porties die niemand gebruikt of die geen portie zijn
FNDDS_SKIP_PORTION = re.compile(r'cubic inch|surface inch|oz yields', re.I)


def fndds_portions(portions):
    out = []
    for label, grams in portions:
        # De omschrijving bevat de hoeveelheid al ("1 cup"); usda_load zet er "1" voor als de kolom leeg is
        label = re.sub(r'^1 (?=\d)', '', label)
        label = re.sub(r'\s*\(NFS\)|,\s*NFS\b', '', label).strip()
        if FNDDS_SKIP_PORTION.search(label):
            continue
        if label.lower() in ('1 quantity not specified', 'quantity not specified'):
            label = '1 serving'
        out.append((label, grams))
    return out


def fndds_rows(root):
    dirs = sorted(p.parent for p in root.rglob('food.csv') if 'survey_food' in str(p))
    if not dirs:
        print('FNDDS: niet gevonden, overgeslagen')
        return
    d = dirs[-1]
    inputs = {}
    for r in read_csv(d / 'input_food.csv'):
        inputs[r['fdc_id']] = inputs.get(r['fdc_id'], 0) + 1
    for fid, f in usda_load(d, by_number=True).items():
        if inputs.get(fid, 0) < 2 or FNDDS_SKIP_CATEGORY.search(f['category']):
            continue
        yield 'usda_fndds', fid, f['name'], '', f['category'], f['raw'], fndds_portions(f['portions'])


def fndds_name(name):
    """De USDA-afkortingen weg uit de getoonde naam: "NFS" (niet nader bepaald) en "NS as to fat" (niet gezegd of er vet
    bij kwam). De oorspronkelijke naam blijft zoekbaar."""
    n = re.sub(r',\s*NFS\b', '', name)
    n = re.sub(r',?\s*NS as to [^,;]+', '', n)
    return re.sub(r'\s{2,}', ' ', n).strip(' ,')


# ─────────────────────────── CIQUAL (Frankrijk) ───────────────────────────

CIQUAL = {
    '328': 'energy', '400': 'water', '25000': 'protein', '31000': 'carbs', '32000': 'sugars', '33110': 'starch',
    '34100': 'fiber', '40000': 'fat', '40302': 'sfa', '40303': 'mufa', '40304': 'pufa',
    '41833': 'ala', '42053': 'epa', '42263': 'dha', '41826': 'la', '42046': 'aa', '75100': 'cholesterol',
    '60000': 'alcohol', '10004': '_salt', '10110': 'sodium', '10120': 'magnesium', '10150': 'phosphorus',
    '10170': 'chloride', '10190': 'potassium', '10200': 'calcium', '10251': 'manganese', '10260': 'iron',
    '10290': 'copper', '10300': 'zinc', '10340': 'selenium', '10530': 'iodine', '51200': 'retinol',
    '51330': 'beta_carotene', '52100': 'vit_d', '53100': 'vit_e', '54101': 'vit_k', '54104': 'vit_k2',
    '55100': 'vit_c', '56100': 'b1', '56200': 'b2', '56310': 'b3', '56400': 'b5', '56500': 'b6',
    '56600': 'b12', '56700': 'b9',
}


def ciqual_value(s):
    """Getal, None (niet gemeten) of ('<', grens) als de waarde onder de meetgrens lag."""
    s = s.strip().replace('&lt;', '<')
    if s in ('-', ''):
        return None
    if s == 'traces':
        return 0.0
    if s.startswith('<'):
        return ('<', float(s[1:].strip().replace(',', '.')))
    return float(s.replace(',', '.'))


def xml_records(path, tag):
    raw = Path(path).read_bytes()
    text = raw.decode('utf-8-sig') if raw.startswith(b'\xef\xbb\xbf') else raw.decode('windows-1252')
    for m in re.finditer(rf'<{tag}>(.*?)</{tag}>', text, re.S):
        yield {k: html.unescape(v.strip()) for k, v in re.findall(r'<(\w+)>(.*?)</\1>', m.group(1), re.S)}


def _ciqual_release(d):
    files = {k: sorted(glob.glob(str(d / f'{k}_[0-9]*.xml'))) for k in ('alim', 'alim_grp', 'compo')}
    if not all(files.values()):
        return None
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
                # (Zout niet: daaruit zou natrium berekend worden, en "zout < 2 g" is geen 400 mg natrium)
                if key in MACROS and key != '_salt':
                    values.setdefault(c['alim_code'], {})[key] = v[1] / 2
                else:
                    values.setdefault(c['alim_code'], {}).setdefault('_loq', {})[key] = v[1]
            elif v is not None:
                values.setdefault(c['alim_code'], {})[key] = v
    foods = {}
    for a in xml_records(files['alim'][-1], 'ALIM'):
        name = a.get('alim_nom_eng') or a['alim_nom_fr']
        foods[a['alim_code']] = (name, a['alim_nom_fr'], groups.get(a.get('alim_ssgrp_code'), ''), values.get(a['alim_code'], {}))
    return foods


def ciqual_rows(root):
    # Nieuwste uitgave (2025) eerst; producten die alleen in 2020 bestonden blijven, zodat oude dagboekregels
    # hun product terugvinden
    new = _ciqual_release(root / 'ciqual2025') or {}
    old = _ciqual_release(root / 'ciqual') or {}
    if not new and not old:
        print('CIQUAL: niet gevonden, overgeslagen')
        return
    for code in {**old, **new}:
        # 2025, tenzij daar de energie ontbreekt en 2020 die wel had (anders verdwijnt het product)
        pick = new.get(code)
        if pick is None or ('energy' not in pick[3] and code in old and 'energy' in old[code][3]):
            pick = old[code]
        name, local, group, values = pick
        yield 'ciqual', code, name, local, group, values, []


# ─────────────────────────── CoFID (Verenigd Koninkrijk) ───────────────────────────

COFID = {
    'WATER': 'water', 'PROT': 'protein', 'FAT': 'fat', 'CHO': 'carbs', 'KCALS': 'energy', 'STAR': 'starch',
    'TOTSUG': 'sugars', 'ALCO': 'alcohol', 'SUCR': '_sucrose', 'MALT': '_maltose', 'LACT': '_lactose',
    'OLIGO': '_oligo', 'TRYP60': '_tryp60', 'NIACEQU': '_ne', 'AOACFIB': 'fiber', 'ENGFIB': '_fiber_nsp', 'SATFOD': 'sfa',
    'MONOFOD': 'mufa', 'POLYFOD': 'pufa', 'FODTRANS': 'trans', 'CHOL': 'cholesterol',
    'NA': 'sodium', 'K': 'potassium', 'CA': 'calcium', 'MG': 'magnesium', 'P': 'phosphorus', 'FE': 'iron',
    'CU': 'copper', 'ZN': 'zinc', 'CL': 'chloride', 'MN': 'manganese', 'SE': 'selenium', 'I': 'iodine',
    'RET': 'retinol', 'CAREQU': 'beta_carotene', 'VITD': 'vit_d', 'VITE': 'vit_e', 'VITK1': 'vit_k',
    'THIA': 'b1', 'RIBO': 'b2', 'NIAC': 'b3', 'VITB6': 'b6', 'VITB12': 'b12', 'FOLT': 'b9', 'PANTO': 'b5',
    'BIOT': 'b7', 'VITC': 'vit_c',
    'FOD18:2cn6': 'la', 'FOD18:3cn3': 'ala', 'FOD20:4cn6': 'aa', 'FOD20:5cn3': 'epa', 'FOD22:5cn3': 'dpa',
    'FOD22:6cn3': 'dha', 'FOD22:6': 'dha',
}
COFID_GROUPS = {
    'A': 'Cereals and cereal products', 'B': 'Milk and milk products', 'C': 'Eggs', 'D': 'Vegetables',
    'F': 'Fruit', 'G': 'Nuts and seeds', 'H': 'Herbs and spices', 'J': 'Fish and fish products',
    'M': 'Meat and meat products', 'O': 'Fats and oils', 'P': 'Beverages', 'Q': 'Alcoholic beverages',
    'S': 'Sugars, preserves and snacks', 'W': 'Soups, sauces and miscellaneous foods',
}


def cofid_value(s):
    s = s.strip()
    if s in ('', 'N'):  # N = aanwezig maar niet gemeten
        return None
    if s.lower().startswith('tr'):  # spoor
        return 0.0
    try:
        return float(s)
    except ValueError:
        return None


def cofid_rows(root):
    files = sorted(glob.glob(str(root / 'cofid' / '*Composition*Dataset*.xlsx'))) or sorted(glob.glob(str(root / 'cofid' / 'CoFID_2021.xlsx')))
    if not files:
        print('CoFID: niet gevonden, overgeslagen')
        return
    from xlsx_read import sheet_rows
    foods = {}
    for sheet in ('1.3 Proximates', '1.4 Inorganics', '1.5 Vitamins', '1.12 (PUFA per 100gFood)'):
        rows = sheet_rows(files[-1], sheet)
        next(rows)
        codes = next(rows)
        next(rows)
        for r in rows:
            if not r or not r[0].strip() or len(r) < 2:
                continue
            f = foods.setdefault(r[0].strip(), {'name': r[1].strip(), 'group': r[3].strip() if len(r) > 3 else '', 'n': {}})
            for i, code in enumerate(codes):
                key = COFID.get(code.strip())
                if key and i < len(r):
                    v = cofid_value(r[i])
                    if v is not None and key not in f['n']:
                        f['n'][key] = v
    for code, f in foods.items():
        n = f['n']
        nsp = n.pop('_fiber_nsp', None)
        # Vezels: CoFID geeft AOAC-vezels (zoals de andere bronnen en EU-etiketten) en Englyst-NSP. NSP mist
        # lignine en resistent zetmeel en ligt lager (havermout 7,2 tegenover 7,8 g AOAC, bij sommige producten veel
        # meer). Er bestaat geen betrouwbare vaste omrekenfactor (het verschil hangt af van het product), dus NSP
        # alleen als AOAC ontbreekt, ongewijzigd (telling: CHANGES['cofid_fiber_nsp']).
        if 'fiber' not in n and nsp is not None:
            n['fiber'] = nsp
            CHANGES['cofid_fiber_nsp'] += 1
        cofid_carbs_to_weight(n)
        # Tryptofaan/60 (mg) is tryptofaan zelf: g tryptofaan = mg × 60 / 1000. Een gemeten tryptofaanwaarde voor de
        # aminozuren, en voor niacine-equivalenten bij producten zonder NE.
        t60 = n.pop('_tryp60', None)
        if t60 is not None and 'tryptophan' not in n:
            n['tryptophan'] = t60 * TRP_PER_NE / 1000
        yield 'cofid', code, f['name'], '', COFID_GROUPS.get(f['group'][:1], ''), n, []


# CoFID (McCance and Widdowson) geeft koolhydraten, zetmeel en suikers als monosacharide-equivalenten: wat je na
# volledige afbraak tot enkelvoudige suikers zou wegen. Andere tabellen en etiketten geven het gewicht zelf. Bij de
# afbraak komt water bij: zetmeel (C6H10O5)n → glucose ×180/162 = 1,11, een disacharide (sacharose, maltose,
# lactose) → 2 monosachariden ×360/342 = 1,05. McCance and Widdowson gebruikt zelf 1,10 en 1,05. Omrekening:
#   zetmeel ÷ 1,10; disachariden (sacharose + maltose + lactose) ÷ 1,05; monosachariden (glucose, fructose,
#   galactose) ÷ 1; oligosachariden ongewijzigd (zelden meer dan 1 g, factor tussen 1,05 en 1,10);
#   koolhydraten = oud totaal − wat zetmeel en disachariden verliezen.
# De energie verandert niet: CoFID rekende die met 3,75 kcal per g monosacharide-equivalent, en dat klopt.
# Ontbreekt het zetmeel, dan is het koolhydraten − suikers − oligosachariden. Ontbreken de losse suikers, dan
# blijven de suikers ongewijzigd (onbekend hoeveel disacharide erin zit). De losse suikers staan in CoFID ook als
# monosacharide-equivalenten (melk: lactose 4,7 = totale suikers 4,7).
COFID_STARCH_FACTOR = 1.10
COFID_DISACCHARIDE_FACTOR = 1.05
# Tellingen per regel voor het verslag (tool/FOODS_CHANGES.md)
CHANGES = {k: 0 for k in ('cofid_carbs', 'cofid_starch', 'cofid_sugars', 'cofid_sugars_unknown', 'cofid_carbs_unsplit',
                          'cofid_carbs_unsplit_starchy', 'cofid_fiber_nsp', 'vit_a_re_from_rae', 'vit_a_re_computed',
                          'retinol_derived', 'tryptophan_dropped', 'tryptophan_supported', 'niacin_ne_source',
                          'niacin_ne_source_incomplete', 'niacin_ne_trp', 'niacin_ne_trp_estimated',
                          'niacin_preformed_only', 'outliers_dropped', 'outliers_kept', 'outliers_same_food',
                          'mvt_below_loq', 'zero_not_measured', 'loq_half', 'est_same_food_scaled')}


def cofid_carbs_to_weight(n):
    starch, sugars, carbs = n.get('starch'), n.get('sugars'), n.get('carbs')
    di = [n.pop(k) for k in ('_sucrose', '_maltose', '_lactose') if k in n]
    oligo = n.pop('_oligo', None) or 0.0
    if carbs is None:
        return
    # Geen zetmeel en geen suikers gemeten: niet te zeggen hoeveel van elk. De CoFID-documentatie zegt dan: totaal
    # ÷ 1,05, tenzij het vooral zetmeel is (÷ 1,10). Dat hangt van het soort product af, en dat weten we pas uit het
    # label: zie cofid_unsplit_carbs, na het laden van de labels.
    if starch is None and sugars is None:
        if carbs > 0:
            n['_unsplit'] = True
        return
    loss = 0.0
    if starch is not None:
        n['starch'] = starch / COFID_STARCH_FACTOR
        loss += starch - n['starch']
        if starch > 0:
            CHANGES['cofid_starch'] += 1
    elif sugars is not None:
        loss += max(0.0, carbs - sugars - oligo) * (1 - 1 / COFID_STARCH_FACTOR)
    if di and sugars is not None:
        d = sum(di)
        lost = d - d / COFID_DISACCHARIDE_FACTOR
        n['sugars'] = max(0.0, sugars - lost)
        loss += lost
        if lost > 0:
            CHANGES['cofid_sugars'] += 1
    elif sugars is None:
        # Zetmeel gemeten, suikers niet: de rest zijn suikers van onbekende soort, ÷ 1,05 zoals de documentatie zegt
        rest = max(0.0, carbs - (starch or 0.0) - oligo)
        loss += rest * (1 - 1 / COFID_DISACCHARIDE_FACTOR)
        if rest > 0:
            CHANGES['cofid_sugars_unknown'] += 1
    if loss > 0:
        n['carbs'] = max(0.0, carbs - loss)
        CHANGES['cofid_carbs'] += 1


# Vooral zetmeel: granen, brood, pasta, rijst, peulvruchten, aardappelen en knollen (labelgroep), of zonder label
# een naam die zo'n product noemt
STARCHY_GROUPS = {'cereal', 'bread', 'pasta', 'rice', 'legume', 'potato/tuber', 'breakfast cereal'}
STARCHY_NAME = re.compile(r'\b(beans?|lentils?|peas|chickpeas?|flour|cornmeal|meal|millet|rice|risotto|potato\w*|yams?|'
                          r'cassava|arrowhead|breadnut|bread|pasta|noodles?|oats?|barley|rye|wheat|maize|sorghum)\b', re.I)


def cofid_unsplit_carbs(rows, labels):
    """CoFID-koolhydraten zonder zetmeel/suikers naar gewicht: ÷ 1,10 bij zetmeelrijke producten, anders ÷ 1,05
    (CoFID 2021-documentatie). Niet als geschat gemarkeerd: het is een omrekening van een gemeten waarde, zoals het
    zetmeel ÷ 1,10 hierboven; de onzekerheid (welke factor) is hooguit 5 %."""
    for r in rows:
        if not r.pop('unsplit', False) or 'carbs' not in r['nut']:
            continue
        l = labels.get(f"{r['source']}:{r['sid']}")
        starchy = l['g'] in STARCHY_GROUPS if l else bool(STARCHY_NAME.search(r['name']))
        r['nut']['carbs'] /= COFID_STARCH_FACTOR if starchy else COFID_DISACCHARIDE_FACTOR
        CHANGES['cofid_carbs_unsplit'] += 1
        CHANGES['cofid_carbs_unsplit_starchy'] += starchy


# ─────────────────────────── Frida (Denemarken) ───────────────────────────

FRIDA = {
    356: 'energy', 218: 'protein', 172: 'carbs', 168: 'fiber', 141: 'fat', 19: 'alcohol', 327: '_salt', 268: 'water',
    225: 'retinol', 303: 'beta_carotene', 126: 'vit_d', 135: 'vit_e', 442: 'vit_k', 164: '_vit_k1', 441: 'vit_k2',
    37: 'b1', 36: '_b1', 39: 'b2', 294: 'b3', 40: 'b6', 210: 'b5', 42: 'b7', 143: 'b9', 38: 'b12', 47: 'vit_c',
    201: 'sodium', 165: 'potassium', 108: 'calcium', 184: 'magnesium', 162: 'iron', 166: 'copper', 274: 'zinc',
    187: 'manganese', 117: 'chromium', 190: 'molybdenum', 230: 'selenium', 214: 'phosphorus', 142: 'fluoride',
    114: 'chloride', 163: 'iodine', 245: 'sugars', 243: 'starch', 248: 'sfa', 247: 'mufa', 251: 'pufa',
    261: 'trans', 71: 'la', 74: 'ala', 86: 'aa', 87: 'epa', 98: 'dpa', 99: 'dha', 115: 'cholesterol',
    159: 'histidine', 161: 'isoleucine', 180: 'leucine', 183: 'lysine', 189: 'methionine', 124: 'cystine',
    211: 'phenylalanine', 264: 'tyrosine', 258: 'threonine', 262: 'tryptophan', 266: 'valine',
    116: 'choline', 121: 'caffeine', 203: '_ne',
}
# Frida geeft aminozuren in mg en fluoride in µg; wij in g en mg
FRIDA_FACTOR = {k: 0.001 for k in ('histidine', 'isoleucine', 'leucine', 'lysine', 'methionine', 'cystine',
                                    'phenylalanine', 'tyrosine', 'threonine', 'tryptophan', 'valine', 'fluoride')}


def frida_rows(root):
    files = sorted(glob.glob(str(root / 'frida' / 'FCDB_*_Dataset.xlsx')))
    if not files:
        print('Frida: niet gevonden, overgeslagen')
        return
    from xlsx_read import sheet_rows
    groups = {}
    foods = {}
    for r in list(sheet_rows(files[-1], 'Food'))[1:]:
        if len(r) > 2 and r[2].strip():
            foods[r[2].strip()] = {'name': r[1].strip(), 'local': r[0].strip(), 'group': r[12].strip() if len(r) > 12 else '', 'n': {}}
    for r in sheet_rows(files[-1], 'Data_Normalised'):
        if len(r) < 8 or not r[3].strip().isdigit():
            continue
        f = foods.get(r[0].strip())
        key = FRIDA.get(int(r[3]))
        if f is None or key is None or r[7].strip() in ('', 'NULL'):
            continue
        try:
            v = float(r[7])
        except ValueError:
            continue
        f['n'][key] = max(0.0, v) * FRIDA_FACTOR.get(key, 1)
    for fid, f in foods.items():
        n = f['n']
        if 'vit_k' not in n and '_vit_k1' in n:
            n['vit_k'] = n['_vit_k1']
        if 'b1' not in n and '_b1' in n:
            n['b1'] = n['_b1']
        yield 'frida', fid, f['name'], f['local'], f['group'], {k: v for k, v in n.items() if k not in ('_vit_k1', '_b1')}, []


# ─────────────────────────── BLS 4.0 (Duitsland) ───────────────────────────
#
# Bundeslebensmittelschlüssel 4.0, Max Rubner-Institut (CC BY 4.0, sinds 16-12-2025 zonder licentiekosten). Excel met
# per voedingsstof een kolom "<CODE> <naam> [<eenheid>/100g]" en een kolom "<CODE> Datenherkunft" (analyse,
# receptberekening, overgenomen waarde, …). De waarden nemen we zoals BLS ze geeft, ook de eigen berekeningen (zoals bij
# CIQUAL en Livsmedelsverket); "-" is geen waarde. De Engelse naam wordt de naam, de Duitse de lokale naam.
# Code → (sleutel, eenheid in BLS, factor naar onze eenheid)
BLS = {
    'ENERCC': ('energy', 'kcal', 1), 'WATER': ('water', 'g', 1), 'ALC': ('alcohol', 'g', 1), 'PROT625': ('protein', 'g', 1),
    'FAT': ('fat', 'g', 1), 'CHO': ('carbs', 'g', 1), 'FIBT': ('fiber', 'g', 1), 'SUGAR': ('sugars', 'g', 1),
    'STARCH': ('starch', 'g', 1), 'FASAT': ('sfa', 'g', 1), 'FAMS': ('mufa', 'g', 1), 'FAPU': ('pufa', 'g', 1),
    'F18:3CN3': ('ala', 'g', 1), 'F20:5CN3': ('epa', 'g', 1), 'F22:5CN3': ('dpa', 'g', 1), 'F22:6CN3': ('dha', 'g', 1),
    'F18:2CN6': ('la', 'g', 1), 'F20:4CN6': ('aa', 'g', 1), 'CHORL': ('cholesterol', 'mg', 1),
    'HIS': ('histidine', 'g', 1), 'ILE': ('isoleucine', 'g', 1), 'LEU': ('leucine', 'g', 1), 'LYS': ('lysine', 'g', 1),
    'MET': ('methionine', 'g', 1), 'CYSTE': ('cystine', 'g', 1), 'PHE': ('phenylalanine', 'g', 1),
    'TYR': ('tyrosine', 'g', 1), 'THR': ('threonine', 'g', 1), 'TRP': ('tryptophan', 'g', 1), 'VAL': ('valine', 'g', 1),
    # Vitamine A staat al als RE (retinolequivalenten), zoals wij het willen
    'VITA': ('vit_a', 'µg', 1), 'RETOL': ('retinol', 'µg', 1), 'CARTB': ('beta_carotene', 'µg', 1),
    'VITD': ('vit_d', 'µg', 1), 'VITE': ('vit_e', 'mg', 1), 'VITK1': ('vit_k', 'µg', 1), 'VITK': ('_vit_k', 'µg', 1),
    'VITK2': ('vit_k2', 'µg', 1), 'THIA': ('b1', 'mg', 1), 'RIBF': ('b2', 'mg', 1),
    # Niacine zelf en de niacine-equivalenten (met tryptofaan), zoals bij Frida (zie niacin_ne)
    'NIA': ('b3', 'mg', 1), 'NIAEQ': ('_ne', 'mg', 1), 'PANTAC': ('b5', 'mg', 1), 'VITB6': ('b6', 'µg', 0.001),
    'BIOT': ('b7', 'µg', 1), 'FOL': ('b9', 'µg', 1), 'VITB12': ('b12', 'µg', 1), 'VITC': ('vit_c', 'mg', 1),
    'NA': ('sodium', 'mg', 1), 'NACL': ('_salt', 'g', 1), 'CLD': ('chloride', 'mg', 1), 'K': ('potassium', 'mg', 1),
    'CA': ('calcium', 'mg', 1), 'MG': ('magnesium', 'mg', 1), 'P': ('phosphorus', 'mg', 1), 'FE': ('iron', 'mg', 1),
    'ZN': ('zinc', 'mg', 1), 'ID': ('iodine', 'µg', 1), 'CU': ('copper', 'µg', 0.001), 'MN': ('manganese', 'µg', 0.001),
    'FD': ('fluoride', 'µg', 0.001), 'CR': ('chromium', 'µg', 1), 'MO': ('molybdenum', 'µg', 1),
}
# Hoofdgroep = eerste letter van de BLS-code (documentatie BLS 4.0)
BLS_GROUPS = {
    'B': 'Bread and rolls', 'C': 'Cereals and grains', 'D': 'Bakery products and snacks', 'E': 'Pasta', 'F': 'Fruit',
    'G': 'Vegetables', 'H': 'Legumes, sprouts and soy', 'K': 'Potatoes and starches', 'M': 'Milk and dairy',
    'N': 'Non-alcoholic beverages', 'P': 'Alcoholic beverages', 'Q': 'Oils and fats', 'R': 'Salt, spices and condiments',
    'S': 'Sugar, honey and sweets', 'T': 'Fish and seafood', 'U': 'Meat', 'V': 'Game, poultry and offal',
    'W': 'Sausages and meat products', 'X': 'Soups, stocks and dishes', 'Y': 'Dishes and desserts',
}
BLS_HEADER = re.compile(r'^(\S+) .*\[(.+)/100\s*g\]$')


def bls_rows(root):
    files = sorted(glob.glob(str(root / 'bls4' / '**' / 'BLS_4_0_Daten_*.xlsx'), recursive=True))
    if not files:
        print('BLS: niet gevonden, overgeslagen')
        return
    from xlsx_read import sheet_rows
    rows = sheet_rows(files[-1], Path(files[-1]).stem)
    head = next(rows)
    cols = {}
    for i, h in enumerate(head):
        m = BLS_HEADER.match(h.strip())
        if m and m.group(1) in BLS:
            key, unit, factor = BLS[m.group(1)]
            if m.group(2).strip() != unit:
                sys.exit(f'BLS: eenheid {m.group(2)} voor {m.group(1)}, verwacht {unit}')
            cols[i] = (key, factor)
    missing = set(BLS) - {head[i].split()[0] for i in cols}
    if missing:
        sys.exit(f'BLS: kolommen niet gevonden: {sorted(missing)}')
    for r in rows:
        if len(r) < 3 or not r[0].strip():
            continue
        code, local, name = r[0].strip(), r[1].strip(), r[2].strip()
        n = {}
        for i, (key, factor) in cols.items():
            v = r[i].strip().replace(',', '.') if i < len(r) else ''
            try:
                n[key] = max(0.0, float(v)) * factor
            except ValueError:
                continue
        if 'vit_k' not in n and '_vit_k' in n:
            n['vit_k'] = n['_vit_k']
        n.pop('_vit_k', None)
        yield 'bls', code, name or local, local, BLS_GROUPS.get(code[:1], ''), n, []


# ─────────────────────────── Livsmedelsverket (Zweden) ───────────────────────────

SLV = {
    ('PROT', 'g'): 'protein', ('CHO', 'g'): 'carbs', ('FIBT', 'g'): 'fiber', ('SUGAR', 'g'): 'sugars',
    ('FAT', 'g'): 'fat', ('FASAT', 'g'): 'sfa', ('FAMS', 'g'): 'mufa', ('FAPU', 'g'): 'pufa', ('FATRN', 'g'): 'trans',
    ('F18:3', 'g'): 'ala', ('F20:5', 'g'): 'epa', ('F22:5', 'g'): 'dpa', ('F22:6', 'g'): 'dha', ('F18:2', 'g'): 'la',
    ('F20:4', 'g'): 'aa', ('CHORL', 'mg'): 'cholesterol', ('WATER', 'g'): 'water', ('ALC', 'g'): 'alcohol',
    ('RETOL', 'µg'): 'retinol', ('CARTBTOT', 'µg'): 'beta_carotene', ('VITD', 'µg'): 'vit_d', ('VITE', 'mg'): 'vit_e',
    ('VITK', 'µg'): 'vit_k', ('THIACLHCL', 'mg'): 'b1', ('THIA', 'mg'): 'b1', ('RIBF', 'mg'): 'b2', ('NIA', 'mg'): 'b3',
    ('VITB6', 'mg'): 'b6', ('FOL', 'µg'): 'b9', ('VITB12', 'µg'): 'b12', ('VITC', 'mg'): 'vit_c',
    ('CA', 'mg'): 'calcium', ('FE', 'mg'): 'iron', ('MG', 'mg'): 'magnesium', ('P', 'mg'): 'phosphorus',
    ('K', 'mg'): 'potassium', ('NA', 'mg'): 'sodium', ('ZN', 'mg'): 'zinc', ('SE', 'µg'): 'selenium',
    ('ID', 'µg'): 'iodine', ('CU', 'mg'): 'copper', ('MN', 'mg'): 'manganese', ('NACL', 'g'): '_salt',
    ('STARCH', 'g'): 'starch', ('NIAEQ', 'NE/mg'): '_ne',
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
    'Vit A': 'vit_a', 'Retinol': 'retinol', 'B-karo': 'beta_carotene', 'Vit D': 'vit_d', 'Vit E': 'vit_e',
    'Vit B1': 'b1', 'Vit B2': 'b2', 'Niacin': 'b3', 'Vit B6': 'b6', 'Folat': 'b9', 'Vit B12': 'b12',
    'Vit C': 'vit_c', 'Ca': 'calcium', 'Fe': 'iron', 'Na': 'sodium', 'K': 'potassium', 'Mg': 'magnesium',
    'Zn': 'zinc', 'Se': 'selenium', 'Cu': 'copper', 'P': 'phosphorus', 'I': 'iodine',
    # Niacine-equivalenten zoals Matvaretabellen ze zelf publiceert (mg), zie niacin_ne
    'NIAEQ': '_ne',
}
# Matvaretabellen-bron (sourceId) van een 0 onder de meetgrens (https://www.matvaretabellen.no/api/en/sources.json)
MVT_BELOW_LOQ = '60a'


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
                # Bron 60a = "Estimated as zero value when the analysed value is below the limit of quantification":
                # geen echte 0 maar onder de meetgrens, zoals "<" bij CIQUAL (zie mvt_below_loq)
                if c.get('sourceId') == MVT_BELOW_LOQ and n[key] == 0 and key in SANITY_MICROS:
                    n.setdefault('_loq60', set()).add(key)
        # Matvaretabellen geeft vitamine A als RAE (retinol + bètacaroteen / 12): naar RE (zie VIT_A_BC)
        if 'vit_a' in n:
            if 'retinol' not in n:
                retinol_from_rae(n, n['vit_a'])
            n['vit_a'] = rae_to_re(n['vit_a'], n.get('beta_carotene'))
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
    'enriched', 'iodised', 'iodized', 'bran', 'germ', 'sprouted', 'seed', 'leaves', 'leaf', 'stalk', 'root', 'peel', 'zest',
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
    # Alleen gemeten waarden (zie donor_values): nooit een al aangevulde waarde of een nagekeken uitschieter
    original = [donor_values(r) for r in rows]
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
            european = rows[j]['source'] in EUROPEAN
            scored.append((-jaccard, 0 if european else 1, -len(original[j]), j))
        if not scored:
            continue
        scored.sort()
        missing = [k for k in ALL_KEYS if k not in r['nut']]
        for k in missing:
            for *_, j in scored:
                if k in original[j]:
                    # Aminozuren als deel van het eiwit, zoals in de andere rondes (zie _scale)
                    f = _scale(k, r['nut'], rows[j]['nut']) if k in AMINO else 1.0
                    if f is None:
                        continue
                    r['nut'][k] = original[j][k] * f
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
# Voorgevormd retinol komt alleen uit dierlijke producten (planten hebben carotenen, zie VIT_A_BC)
ANIMAL_ONLY = ('b12', 'cholesterol', 'epa', 'dha', 'dpa', 'aa', 'vit_d', 'retinol')


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
            # De niacine-equivalenten zoals de bron ze gaf (zie niacin_ne)
            if k == '_ne':
                r['ne'] = None if v is None else float(v)
                done += 1
                continue
            if k.startswith('_'):
                continue
            # Een verbeterde vitamine A of retinol is de waarheid: niet later opnieuw uit retinol + bètacaroteen
            if k in ('vit_a', 'retinol'):
                r['retinol'] = None
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
    # Totaal kleiner dan zijn gemeten delen: het totaal is fout (de delen zijn gedetailleerder gemeten).
    # Vet laten we buiten beschouwing: dat ophogen duwt de som eiwit+koolh.+vet+… soms boven 100 g, wat
    # zichtbaarder fout is dan een vetzuuruitsplitsing die net boven het vet uitkomt.
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


# Een 0 die geen 0 is. Calcium, ijzer, magnesium, kalium, fosfor en zink zitten in elke plantaardige en dierlijke cel
# (celwanden, bladgroen, enzymen, bloed, botten): in een enkelvoudig, onbewerkt voedingsmiddel uit de groepen hieronder
# is een 0 in de bron een waarde onder de meetgrens of niet gemeten, nooit echt nul. Selenium ook bij vlees en vis
# (dieren hebben het nodig, planten niet: seleenarme grond geeft echt bijna geen selenium in granen en groenten).
# Zo'n 0 telt als ontbrekend en wordt geschat (en als geschat getoond), zoals elke ontbrekende waarde.
# Witte langkorrelrijst van Matvaretabellen had calcium 0, ijzer 0 en selenium 0 (USDA 10 mg, 0,2 mg en 7,5 µg).
# Niet bij fruit, eiwit van ei en paddenstoelen: daar ligt een deel van deze mineralen echt rond de meetgrens (zink in
# appel 0,02 mg, ijzer in eiwit 0,08 mg), en 0 is een eerlijke afronding. Niet bij zetmeel (maïszetmeel, aardappel-
# zetmeel, arrowroot: de mineralen zijn uitgewassen) en uitgeloogde of nagemaakte producten (lutefisk, zeewierkaviaar).
ZERO_MINERALS = ('calcium', 'iron', 'magnesium', 'potassium', 'phosphorus', 'zinc')
ZERO_PLANT_GROUPS = {'cereal', 'rice', 'pasta', 'bread', 'breakfast cereal', 'legume', 'vegetable', 'potato/tuber', 'nut/seed'}
ZERO_ANIMAL_GROUPS = {'meat', 'poultry', 'offal', 'fish', 'shellfish'}
ZERO_EXCEPT = re.compile(r'\b(lute?fisk|alkaline cured|seaweed caviar)\b', re.I)


# Matvaretabellen zet een meting onder de meetgrens op 0 (bron 60a, zie MVT_BELOW_LOQ), zonder de grens. Bij een
# enkelvoudig voedingsmiddel (geen gerecht, geen mengsel: KIN_GROUPS en SINGLE_EXTRA_GROUPS) behandelen we zo'n 0 als "onder de
# meetgrens" zoals bij CIQUAL: eerst aanvullen uit hetzelfde voedingsmiddel in een andere databank, anders 0 (geen
# groepsgemiddelde, dat ligt vaak boven de grens). Bij gerechten, snoep en ontbijtgranen blijft het 0: "hetzelfde
# voedingsmiddel" is daar vaak een ander recept (snoepmix zonder chocolade kreeg zo het calcium van de mix met).
SINGLE_EXTRA_GROUPS = {'rice', 'pasta', 'bread', 'dairy', 'processed meat'}


def mvt_below_loq(rows, labels):
    single = KIN_GROUPS | SINGLE_EXTRA_GROUPS
    for r in rows:
        if not r['below_loq']:
            continue
        l = labels.get(f"{r['source']}:{r['sid']}")
        if not l or l['d'] or l['k'] == 'mixed' or l['g'] not in single:
            continue
        for k in sorted(r['below_loq']):
            if r['nut'].get(k) == 0:
                r['nut'].pop(k)
                r['loq'][k] = 0.0
                CHANGES['mvt_below_loq'] += 1


def zeros_not_measured(rows, labels):
    """Een 0 voor ZERO_MINERALS (en selenium bij vlees en vis) in een enkelvoudig voedingsmiddel weglaten, zodat ze
    geschat wordt (zie uitleg hierboven). Een correctie in food_fixes.json gaat altijd voor."""
    fixed = json.loads(FIXES_FILE.read_text())['fixes'] if FIXES_FILE.exists() else {}
    for r in rows:
        ref = f"{r['source']}:{r['sid']}"
        l = labels.get(ref)
        if not l:
            continue
        # Selenium 0 in een plant: echt (seleenarme grond, vooral Scandinavië) of onder de meetgrens, maar het hangt
        # af van waar het groeide. Blijft staan, maar is geen donor voor een ander product (Amerikaanse gekookte rijst
        # kreeg zo 0 µg van de Noorse, USDA meet 7,5 µg in langkorrelrijst).
        if l['g'] in ZERO_PLANT_GROUPS and not l['d'] and l['k'] in ('plant', 'algae') and r['nut'].get('selenium') == 0:
            r['nodonor'].add('selenium')
        if l['d'] or l['p'] == 'starch' or ZERO_EXCEPT.search(r['name']):
            continue
        if l['g'] in ZERO_PLANT_GROUPS and l['k'] in ('plant', 'algae'):
            keys = ZERO_MINERALS
        elif l['g'] in ZERO_ANIMAL_GROUPS and l['k'] == 'animal':
            keys = ZERO_MINERALS + ('selenium',)
        else:
            continue
        for k in keys:
            if k in fixed.get(ref, {}):
                continue
            # Ook een 0 "onder de meetgrens" zonder grens (Matvaretabellen 60a): die zou anders weer 0 worden
            if r['nut'].get(k) == 0 or r['loq'].get(k) == 0:
                r['nut'].pop(k, None)
                r['loq'].pop(k, None)
                CHANGES['zero_not_measured'] += 1
            elif r['loq'].get(k):
                # Onder een bekende meetgrens (CIQUAL "<"): eerst aanvullen uit hetzelfde voedingsmiddel, anders de
                # helft van de grens in plaats van 0, zoals bij de hoofdbestanddelen (zie main)
                r.setdefault('loq_half', set()).add(k)


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
FAT_SOLUBLE = {'vit_a', 'retinol', 'vit_d', 'vit_e', 'vit_k', 'beta_carotene', 'cholesterol', 'lutein_zeaxanthin', 'lycopene'}


def _fatty_product(n):
    f = _ffdm(n)
    return f is not None and f < 3 and n.get('fat', 0) > 5


def _ffdm(n):
    if 'water' not in n:
        return None
    return max(0.5, 100 - n['water'] - n.get('fat', 0) - n.get('alcohol', 0))


PUFA_PARTS = {'la', 'ala', 'aa', 'epa', 'dpa', 'dha'}
SALTY = {'sodium', 'chloride', 'iodine'}


# Gewogen mét afval (dop, schil, pit, graat, been): de dop telt als vetvrije droge stof, dus schalen daarop gaf zo'n
# product veel te veel (walnoten met dop 400 µg chroom tegenover 145 in de pit). Daar schalen we op de energie, die met
# het eetbare deel meegaat. De nutriëntenlijsten van zulke producten (id), zie main.
WASTE_NAME = re.compile(r'weighed with|as purchased|including (skin|bones?|pips|shells?)', re.I)
WASTE = set()


def _scale(key, target, donor):
    if (id(target) in WASTE or id(donor) in WASTE) and key not in AMINO and key not in PUFA_PARTS:
        a, b = target.get('energy'), donor.get('energy')
        if not a or not b:
            return None
        return min(20.0, max(0.05, a / b))
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
    # Aminozuren als deel van het eiwit, maar niet uit (of naar) een product met minder dan 1 g eiwit: daar is de
    # verhouding meetruis (thee als drank met 0,1 g eiwit en 0 g tryptofaan zegt niets over theebladeren)
    if key in AMINO and min(a, b) < 1 and max(a, b) >= 1.5:
        return None
    # Bijna alleen vet en water (margarine, olie): de vetvrije droge stof is te klein om betrouwbaar mee te schalen
    if key not in FATTY and key not in AMINO and key not in PUFA_PARTS and key not in FAT_SOLUBLE and min(a, b) < 3:
        # Een drank of aftreksel (bijna alleen water) tegenover een droog product (theebladeren, gemalen koffie,
        # bouillonpoeder): niet vergelijkbaar en niet betrouwbaar te schalen, dus geen donor. Anders kreeg thee 335 µg
        # chroom per 100 ml, de waarde van de droge bladeren.
        if max(a, b) > 10:
            return None
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
    measured = [donor_values(r) for r in rows]
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
            european = rows[j]['source'] in EUROPEAN
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


# Lever bepaalt het vitamine A van een product: een groepsgemiddelde met leverpaté en leverworst erin zegt niets over een
# gewone worst (frankfurter met spek kreeg zo 1800 µg vitamine A). Voor vitamine A en retinol tellen producten met lever
# alleen mee voor andere producten met lever.
LIVER = re.compile(r'\b(liver\w*|lever\w*|p[aâ]t[eé]s?|foie|leber\w*)\b', re.I)
LIVER_KEYS = {'vit_a', 'retinol'}


def _liver_rule(rows):
    has = [bool(LIVER.search(r['name'])) for r in rows]

    def donor(k, j):
        return k in LIVER_KEYS and has[j]
    return has, donor


def group_fill(rows):
    measured = [donor_values(r) for r in rows]
    has_liver, liver_donor = _liver_rule(rows)
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

    def median(group, s_t, k, minimum, fatty=False, liver=False):
        if group[0] == 'a':  # zelfde hoofdwoord, ongeacht de andere woorden (laatste redmiddel)
            # In vet opgeloste vitamines mogen breed geschat worden bij boter, room en olie (gaan mee met het vet)
            if k not in BROAD_OK and not (fatty and k in FAT_SOLUBLE):
                return None
            group, s_t = ('n', group[1]), ('any', s_t[1], fatty)
        ck = (group, s_t, k, liver)
        if ck not in cache:
            vals, top = [], 0.0
            for j in tables.get(group, ()):
                if not liver and liver_donor(k, j):
                    continue
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
                    # Aminozuren: de hoogste verhouding tot het eiwit (zie _cap)
                    top = max(top, measured[j][k] / b if k in AMINO else measured[j][k])
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
            if k == 'caffeine' and CAFFEINE_SOURCES.search(r['name']):
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
                m = median(group, sig[i], k, minimum, _fatty_product(r['nut']), has_liver[i])
                if m is not None:
                    # Nooit meer dan het hoogste gemeten product in die groep
                    r['nut'][k] = _cap(k, m, b)
                    r['est'][k] = f'~~{label}'
                    filled += 1
                    break
    return filled


def _cap(k, m, b):
    """Groepsmediaan (per gram basis) × de basis van dit product, nooit meer dan het hoogste gemeten product in de
    groep. Bij aminozuren geldt die grens als verhouding tot het eiwit: tryptofaan in een eiwitpoeder met 80 g eiwit is
    niet begrensd door de 0,5 g van een gewoon product (anders zakt het onder 1 % van het eiwit)."""
    median, top = m
    return min(median * b, top * b if k in AMINO else top)


# Koffie, thee, cacao, cola, mate en guarana: cafeïne hangt dan af van hoeveel erin zit, niet van de groep (thee met
# melk kreeg 0,12 mg als groepswaarde, werkelijk ±20 mg per 100 ml). Geen groepsschatting; wel uit hetzelfde product.
CAFFEINE_SOURCES = re.compile(r'\b(coffee|espresso|cappuccino|latte|tea|cocoa|chocolate|cola|mate|guarana|energy drink)\b', re.I)


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


# ─────────────────────────── Aanvullen met labels ───────────────────────────
#
# Elk product heeft een label (tool/food_labels.jsonl, zie voedingsapp-data/labels/SPEC.md): voedingsmiddel,
# deel, soort (plant/dier/…), groep, bereiding, kenmerken (gezouten, verrijkt, mager, …) en of het een gerecht is.
# Daarmee herkennen we hetzelfde voedingsmiddel over alle databanken heen, in plaats van op woorden te gokken:
#   1. hetzelfde voedingsmiddel (zelfde label, ook de bereiding): de mediaan van alle gemeten waarden;
#   2. hetzelfde voedingsmiddel, andere bereiding of kenmerken: geschaald met de droge stof / het vet / het eiwit,
#      en gecorrigeerd met de kookverliezen van de USDA (tool/retention.py);
#   3. het gemiddelde van de groep (bv. vette vis, filet), uit alle databanken.
# Verrijkte en niet-verrijkte producten worden voor vitamines en mineralen nooit gemengd.
LABELS_FILE = Path(__file__).with_name('food_labels.jsonl')
C_CLASS = {'raw': 'raw', 'frozen': 'raw', 'boiled': 'wet', 'stewed': 'wet', 'steamed': 'wet', 'microwaved': 'wet',
           'cooked': 'wet', 'baked': 'dry', 'roasted': 'dry', 'grilled': 'dry', 'fried': 'dry', 'deep-fried': 'dry'}
SIG_FLAGS = {'salted', 'unsalted', 'with bone', 'sweetened', 'fortified', 'reduced fat', 'lean', 'full fat', 'breaded', 'in oil', 'in water',
             'in syrup', 'in juice', 'in brine', 'in sauce', 'diet', 'infant', 'with skin', 'without skin',
             'decaffeinated', 'instant', 'parboiled'}
# Voorgekookte rijst (parboiled, "pre-boiled", "easy cook") is geweekt en gestoomd vóór het pellen: ze neemt calcium
# op uit het weekwater (71 mg tegenover 9-28 mg in gewone witte rijst, USDA en CIQUAL) en houdt meer B1. Een eigen
# vlag (in de labels staat het niet), zodat gewone rijst niet aangevuld wordt uit voorgekookte en omgekeerd.
PARBOILED = re.compile(r'\b(parboiled|pre-?boiled|easy cook)\b', re.I)
FORTIF = {'b12', 'vit_d', 'calcium', 'iron', 'b1', 'b2', 'b3', 'b6', 'b9', 'vit_c', 'vit_a', 'vit_e', 'zinc', 'iodine'}


def load_labels():
    if not LABELS_FILE.exists():
        return {}
    labels = {}
    for line in LABELS_FILE.read_text().splitlines():
        if line.strip():
            x = json.loads(line)
            x['f'] = x['f'].strip().lower()
            x['fl'] = [f.strip().lower() for f in x.get('fl', [])]
            labels[x['id']] = x
    # Verbeteringen uit de controle van verdachte waarden (tool/apply_review.py)
    fixes = LABELS_FILE.with_name('label_fixes.json')
    if fixes.exists():
        for ref, change in json.loads(fixes.read_text()).items():
            if ref in labels:
                labels[ref].update(change)
                labels[ref]['f'] = labels[ref]['f'].strip().lower()
    return labels


def _same_key(l):
    return (l['f'], l['p'], l['d'], C_CLASS.get(l['c'], l['c']), frozenset(set(l['fl']) & SIG_FLAGS))


def _fortified(l):
    return 'fortified' in l['fl']


def label_rules(rows, labels):
    """Plantaardig (geen gerecht, niet verrijkt): geen B12, cholesterol, EPA/DHA/DPA, AA; vitamine D alleen in
    paddenstoelen (die zijn 'fungus', niet 'plant')."""
    z = 0
    for r in rows:
        l = labels.get(f"{r['source']}:{r['sid']}")
        if not l or l['k'] != 'plant' or l['d'] or _fortified(l):
            continue
        for k in ANIMAL_ONLY:
            if k not in r['nut']:
                r['nut'][k] = 0.0
                r.setdefault('bio0', set()).add(k)
                z += 1
    return z


def _only_dried(a, b):
    """Twee labels die alleen verschillen in rauw / gedroogd / diepvries, bij een plant, alg of paddenstoel."""
    plain = {'raw', 'dried', 'frozen', 'not applicable'}
    return a['k'] in ('plant', 'algae', 'fungus') and b['k'] == a['k'] and a['c'] in plain and b['c'] in plain


def label_fill(rows, labels, retention_table):
    import retention
    refs = [f"{r['source']}:{r['sid']}" for r in rows]
    lab = [labels.get(ref) for ref in refs]
    measured = [donor_values(r) for r in rows]
    by_same, by_sim, by_group, by_g = {}, {}, {}, {}
    for i, l in enumerate(lab):
        if not l:
            continue
        by_same.setdefault(_same_key(l), []).append(i)
        by_sim.setdefault((l['f'], l['p'], l['d']), []).append(i)
        if r_ok(rows[i]):
            by_group.setdefault((l['g'], l['k'], l['d'], l['p']), []).append(i)
            by_g.setdefault((l['g'], l['k'], l['d']), []).append(i)
    rt = [retention.factors(retention_table, l, rows[i]['nut'].get('fat')) if l else {} for i, l in enumerate(lab)]
    words = [name_profile(r['name'])[1] for r in rows]

    def closest(i, donors):
        if len(donors) <= 1:
            return donors
        def sim(j):
            a, b = words[i], words[j]
            return len(a & b) / len(a | b) if a | b else 0
        scored = [(sim(j) + (0.15 if rows[j]['source'][:4] == rows[i]['source'][:4] else 0), j) for j in donors]
        top = max(x for x, _ in scored)
        return [j for x, j in scored if x >= top - 0.1]

    def ok_donor(i, j, k):
        if k in FORTIF and _fortified(lab[i]) != _fortified(lab[j]):
            return False
        return True

    counts = [0, 0, 0]
    # Ronde 1 en 2: hetzelfde voedingsmiddel
    for i, r in enumerate(rows):
        l = lab[i]
        # Voedingssupplementen: niets bijschatten, het etiket is de enige waarheid
        if not l or l['g'] == 'supplement' or not r_ok(r):
            continue
        missing = [k for k in ALL_KEYS if k not in r['nut']]
        if not missing:
            continue
        same = [j for j in by_same.get(_same_key(l), ()) if j != i]
        sim = [j for j in by_sim.get((l['f'], l['p'], l['d']), ()) if j != i and j not in same]
        for k in missing:
            donors = [j for j in same if k in measured[j] and ok_donor(i, j, k)]
            # De metingen waarvan de naam het best overeenkomt (vaak een variant uit dezelfde databank, met dezelfde
            # analyse): die voorspellen het best (gemeten met verborgen waarden, zie holdout)
            donors = closest(i, donors)
            if donors:
                # Ook bij hetzelfde voedingsmiddel verschillen vet en water (andere stukken vlees, andere
                # merken): elke meting eerst omrekenen naar dit product, dan de mediaan
                vals = []
                for j in donors:
                    f = 1.0 if k in MACROS else _scale(k, r['nut'], rows[j]['nut'])
                    if f is not None:
                        vals.append((measured[j][k] * f, j))
                if vals:
                    vals.sort()
                    r['nut'][k] = statistics.median(v for v, _ in vals)
                    r['est'][k] = refs[vals[(len(vals) - 1) // 2][1]]
                    counts[0] += 1
                    continue
            if k in MACROS:
                continue
            cands = []
            for j in sim:
                if k not in measured[j] or not ok_donor(i, j, k):
                    continue
                # Zout en jodium hangen af van zouten, pekelen of roken: alleen bij dezelfde bereiding en zoutstatus.
                # Rauw of gedroogd (zonder zout) is bij planten, algen en paddenstoelen alleen een verschil in water,
                # en dat schaalt mee: verse spirulina krijgt het jodium van gedroogde spirulina, niet van een zeewier
                if k in SALTY and (('salted' in lab[j]['fl']) != ('salted' in l['fl'])
                                   or (lab[j]['c'] != l['c'] and not _only_dried(l, lab[j]))):
                    continue
                f = _scale(k, r['nut'], rows[j]['nut'])
                if f is None:
                    continue
                v = measured[j][k] * f * rt[i].get(k, 1.0) / max(0.3, rt[j].get(k, 1.0))
                tier = 0 if C_CLASS.get(lab[j]['c'], lab[j]['c']) == C_CLASS.get(l['c'], l['c']) else (1 if lab[j]['c'] in ('raw', 'frozen', 'not applicable') else 2)
                cands.append((tier, v, j))
            if cands:
                best = min(t for t, _, _ in cands)
                keep = set(closest(i, [j for t, _, j in cands if t == best]))
                vals = sorted((v, j) for t, v, j in cands if t == best and j in keep)
                r['nut'][k] = statistics.median(v for v, _ in vals)
                r['est'][k] = '~' + refs[vals[(len(vals) - 1) // 2][1]]
                counts[1] += 1
    # Ronde 3: de groep (bv. "fish, fillet"), anders de ruimere groep ("fish"), uit alle databanken
    measured = [donor_values(r) for r in rows]
    has_liver, liver_donor = _liver_rule(rows)
    cache = {}

    def median(table, key, k, fort, minimum, liver=False):
        ck = (id(table), key, k, fort, liver)
        if ck not in cache:
            vals, top = [], 0.0
            for j in table.get(key, ()):
                if k in FORTIF and _fortified(lab[j]) != fort:
                    continue
                if not liver and liver_donor(k, j):
                    continue
                b = _basis(k, rows[j]['nut'])
                if k in measured[j] and b and b > (0.5 if k in FATTY or k in AMINO else 3):
                    vals.append(measured[j][k] / b)
                    # Aminozuren: de hoogste verhouding tot het eiwit (zie _cap)
                    top = max(top, measured[j][k] / b if k in AMINO else measured[j][k])
            cache[ck] = (statistics.median(vals), top) if len(vals) >= minimum else None
        return cache[ck]

    for i, r in enumerate(rows):
        l = lab[i]
        if not l or not r_ok(r) or l['g'] == 'supplement':
            continue
        missing = [k for k in ALL_KEYS if k not in r['nut'] and k not in MACROS and k not in RARE and k not in r['loq']]
        fort = _fortified(l)
        for k in missing:
            b = _basis(k, r['nut'])
            if b is None:
                continue
            # Eerst de producten uit de groep waarvan de naam duidelijk lijkt (bv. "pike" voor "pike, smoked")
            near = []
            for j in by_group.get((l['g'], l['k'], l['d'], l['p']), ()):
                if j == i or k not in measured[j] or (k in FORTIF and _fortified(lab[j]) != fort):
                    continue
                if not has_liver[i] and liver_donor(k, j):
                    continue
                bj = _basis(k, rows[j]['nut'])
                if not bj or bj <= (0.5 if k in FATTY or k in AMINO else 3):
                    continue
                a, c = words[i], words[j]
                simil = len(a & c) / len(a | c) if a | c else 0
                if simil >= 0.34:
                    near.append((simil, measured[j][k] / bj * b, j))
            if near:
                top = max(x for x, _, _ in near)
                vals = sorted((v, j) for x, v, j in near if x >= top - 0.1)
                r['nut'][k] = statistics.median(v for v, _ in vals)
                r['est'][k] = '~' + refs[vals[(len(vals) - 1) // 2][1]]
                counts[2] += 1
                continue
            if k == 'caffeine' and CAFFEINE_SOURCES.search(r['name']):
                continue
            for table, key, minimum, label in ((by_group, (l['g'], l['k'], l['d'], l['p']), 5, f"{l['g']}, {l['p']}"),
                                               (by_g, (l['g'], l['k'], l['d']), 10, l['g'])):
                m = median(table, key, k, fort, minimum, has_liver[i])
                if m is not None:
                    r['nut'][k] = _cap(k, m, b)
                    r['est'][k] = f'~~group:{label}'
                    counts[2] += 1
                    break
    return counts


def r_ok(r):
    return r['category'] not in SKIP_GROUP_CATEGORIES


# Alle voedingsstoffen die aangevuld mogen worden. Energie niet (dat is de controle), en de totalen
# omega-3 en omega-6 worden daarna opnieuw berekend uit de delen.
ALL_KEYS = sorted(({k for k in USDA if not k.startswith('_')} | {'carbs', 'chloride'}) - {'energy', 'omega3', 'omega6'})


# ─────────────────────────── Opschonen ───────────────────────────
#
# Laatste stap vóór het wegschrijven: waarden die niet kunnen kloppen weghalen, zodat de app ze als "onbekend"
# toont in plaats van een verzonnen of fysiek onmogelijk getal. Raakt nooit een gemeten hoofdbestanddeel aan
# (eiwit, koolhydraten, vet, water…), alleen micro's en afgeleide delen. Wat weg mag:
#   - een bijgeschatte micro (≈) die t.o.v. zijn groep een uitschieter is (> 20× of < 1/20 van de mediaan):
#     dat is een aanvulling die duidelijk de mist in ging;
#   - vezels of zetmeel in een zuiver dierlijk product (dieren maken die niet aan);
#   - B12, cholesterol, EPA/DHA of vitamine D (buiten paddenstoelen) in een zuiver plantaardig product.
# Onduidelijke gevallen (energie klopt niet met de macro's, som > 100 g, waarde boven de fysieke grens) blijven
# staan: daar is niet te zeggen welke waarde fout is. Die horen in tool/food_fixes.json na controle.
SANITY_MICROS = (
    'sodium', 'potassium', 'calcium', 'magnesium', 'phosphorus', 'iron', 'zinc', 'copper', 'manganese', 'selenium',
    'iodine', 'vit_c', 'vit_d', 'vit_e', 'vit_k', 'vit_a', 'beta_carotene', 'b1', 'b2', 'b3', 'b5', 'b6', 'b9', 'b12',
    'choline', 'cholesterol', 'retinol', 'chromium', 'molybdenum', 'tryptophan',
)
# Onder deze waarde telt een afwijking van de groep niet mee (meetruis rond nul)
SANITY_FLOOR = {
    'sodium': 20, 'potassium': 50, 'calcium': 20, 'magnesium': 10, 'phosphorus': 30, 'iron': 0.5, 'zinc': 0.5,
    'copper': 0.1, 'manganese': 0.2, 'selenium': 5, 'iodine': 5, 'vit_c': 5, 'vit_d': 0.5, 'vit_e': 0.5, 'vit_k': 5,
    'vit_a': 30, 'beta_carotene': 100, 'b1': 0.05, 'b2': 0.05, 'b3': 0.5, 'b5': 0.2, 'b6': 0.05, 'b9': 10, 'b12': 0.3,
    'choline': 10, 'cholesterol': 10, 'retinol': 30, 'chromium': 5, 'molybdenum': 10, 'tryptophan': 0.05,
}
PLANT_B12_OK = re.compile(r'\b(nori|laver|seaweed|algae|spirulina|chlorella|tempeh|mushrooms?|shiitake)\b', re.I)
PLANT_EPADHA_OK = re.compile(r'\b(algae|algal|seaweed|kelp)\b', re.I)


def sanity_pass(rows, labels=None):
    """Onmogelijke of verzonnen micro's weghalen (zie uitleg hierboven). Geeft de tellingen per soort terug."""
    # Medianen per groep (bron + categorie), alleen uit gemeten waarden — net als de audit
    groups = {}
    # Het bereik van de metingen van hetzelfde voedingsmiddel (label): een schatting daarbinnen is geen uitschieter,
    # ook als ze ver van de groep ligt (lamslever met 15 000 µg vitamine A tegenover de mediaan van alle orgaanvlees)
    labels = labels or {}
    foods = [(labels.get(f"{r['source']}:{r['sid']}") or {}).get('f') for r in rows]
    same, same_basis = {}, {}
    for r, f in zip(rows, foods):
        key = (r['source'], r['category'] or '')
        g = groups.setdefault(key, {})
        for k in SANITY_MICROS:
            if k in r['nut'] and k not in r['est']:
                g.setdefault(k, []).append(r['nut'][k])
                if f and k not in r.get('bio0', ()):
                    lo, hi = same.get((f, k), (r['nut'][k], r['nut'][k]))
                    same[(f, k)] = (min(lo, r['nut'][k]), max(hi, r['nut'][k]))
                    # Ook per gram basis (vetvrije droge stof, vet of eiwit, zie _basis): een schatting uit gedroogde
                    # spirulina voor verse is per 100 g 10× lager, per gram droge stof dezelfde
                    b = _basis(k, r['nut'])
                    if b and b > (0.5 if k in FATTY or k in AMINO else 3):
                        x = r['nut'][k] / b
                        lo, hi = same_basis.get((f, k), (x, x))
                        same_basis[(f, k)] = (min(lo, x), max(hi, x))

    def drop(r, k):
        r['nut'].pop(k, None)
        r['est'].pop(k, None)

    food_of = {id(r): f for r, f in zip(rows, foods)}
    whole_plant = {}
    for r in rows:
        l = labels.get(f"{r['source']}:{r['sid']}") or {}
        whole_plant[id(r)] = bool(l) and l['k'] in ('plant', 'algae', 'fungus') and l['g'] in KIN_GROUPS \
            and not l['d'] and not _fortified(l)
    dier = plant = est_outlier = 0
    for r in rows:
        n, est, name, cat = r['nut'], r['est'], r['name'], r['category']
        kd = kind(name, cat)
        if kd == 'dier':
            if n.get('fiber', 0) > 0.5:
                drop(r, 'fiber'); dier += 1
            if n.get('starch', 0) > 1:
                drop(r, 'starch'); dier += 1
        elif kd == 'plant':
            if n.get('b12', 0) > 0.3 and not PLANT_B12_OK.search(name):
                drop(r, 'b12'); plant += 1
            if n.get('cholesterol', 0) > 5:
                drop(r, 'cholesterol'); plant += 1
            if n.get('epa', 0) + n.get('dha', 0) > 0.02 and not PLANT_EPADHA_OK.search(name):
                drop(r, 'epa'); drop(r, 'dha'); drop(r, 'dpa'); plant += 1
            if n.get('vit_d', 0) > 1 and not MUSHROOM.search(name):
                drop(r, 'vit_d'); plant += 1
        # Geschatte uitschieters t.o.v. de groep
        g = groups.get((r['source'], cat or ''), {})
        for k in list(est):
            if k not in SANITY_MICROS or k not in n:
                continue
            vals = g.get(k, ())
            if len(vals) < 8:
                continue
            med = statistics.median(vals)
            floor = SANITY_FLOOR[k]
            ratio = max(n[k], floor) / max(med, floor)
            lo, hi = same.get((food_of[id(r)], k), (None, None))
            if lo is not None and lo / 2 <= n[k] <= hi * 2:
                continue
            if ratio > 20 or ratio < 1 / 20:
                # Een enkelvoudig plantaardig voedingsmiddel (of alg, paddenstoel) dat alleen in water verschilt van
                # de metingen (vers tegenover gedroogd): het bereik per gram basis telt (verse spirulina, jodium)
                lo, hi = same_basis.get((food_of[id(r)], k), (None, None))
                b = _basis(k, n)
                if (lo is not None and whole_plant[id(r)] and b and b > (0.5 if k in FATTY or k in AMINO else 3)
                        and lo / 2 <= n[k] / b <= hi * 2):
                    CHANGES['est_same_food_scaled'] += 1
                    continue
                drop(r, k)
                est_outlier += 1
    return dier, plant, est_outlier


# ─────────────────────────── Onwaarschijnlijke metingen ───────────────────────────
#
# Een gemeten waarde die ver boven alles uitsteekt wat vergelijkbare producten hebben, is bijna altijd een eenheids-
# of tikfout in de bron (eiwitshake met 125 mg mangaan per 100 g, bevinding SP-1). Per voedingsstof twee toetsen:
#   1. tegenover de voedingsgroep uit het label (zuivel, vis, drank, …); referentie = het 99e percentiel van de
#      gemeten waarden in die groep (met minstens 30 waarden, anders het 99,9e percentiel van alle producten):
#      verdacht als de waarde > 15× de groepsreferentie is én minstens een kwart van het 99,9e percentiel van alle
#      producten (anders gaat het om kleine absolute hoeveelheden), of als ze > 3× het 99,9e percentiel van alle
#      producten is;
#   2. tegenover dezelfde soort: dezelfde labelgroep en hetzelfde hoofdwoord van het voedingsmiddel ("monkfish",
#      "grenadier" in "roundnose grenadier"), of hetzelfde geslacht uit de Latijnse naam ("Lophius budegassa"):
#      verdacht als de waarde per gram vetvrije droge stof (of per gram vet of eiwit, zie _basis) meer dan 6× de
#      mediaan van minstens 2 andere producten van die soort is. Zo valt een enkele piek op die in de hele groep niet
#      opvalt: zeeduivel met 414 µg selenium tegenover 30-39 µg bij vier andere metingen van zeeduivel;
#   - in beide gevallen niet verdacht als hetzelfde voedingsmiddel (zelfde label) of dezelfde soort in een ander
#     product minstens een kwart van die waarde heeft: dan steunen andere metingen het (thee en mangaan, kombu en
#     jodium, paranoten en selenium).
# Tryptofaan krijgt een eigen toets (aandeel van het eiwit, zie tryptophan_check).
# Wat dan overblijft, is één voor één nagekeken. Echte uitschieters (levertraan, spirulina, gevriesdroogde paprika,
# verrijkt poeder) staan met de reden in tool/outlier_keep.json en blijven, maar zijn nooit donor bij het aanvullen
# (Gracilaria met 356 000 µg jodium klopt voor dat zeewier, maar zegt niets over verse spirulina); de rest wordt
# weggelaten en daarna opnieuw geschat zoals elke ontbrekende waarde. Supplementen in pilvorm tellen niet mee (daar
# is alles extreem). Het verslag staat in tool/outlier_report.md, telkens opnieuw geschreven bij het bouwen.
OUTLIER_KEEP = Path(__file__).with_name('outlier_keep.json')
OUTLIER_REPORT = Path(__file__).with_name('outlier_report.md')
OUTLIER_GROUP_RATIO = 15
OUTLIER_GROUP_MIN_GLOBAL = 0.25
OUTLIER_GLOBAL_RATIO = 3
OUTLIER_SUPPORT = 4
OUTLIER_KIN_RATIO = 6
OUTLIER_KIN_MIN = 2
PILL_LIKE = re.compile(r'vitamin|multi|capsule|tablet|floradix|sanasol|vitaplex|antacid', re.I)
# Latijnse naam tussen haakjes: "(Lophius budegassa)", "(Ulva sp.)"
GENUS = re.compile(r'\(([A-Z][a-z]{3,})(?: [a-z]+\.?)+\)')


def _pct(sorted_vals, p):
    return sorted_vals[min(len(sorted_vals) - 1, int(p * len(sorted_vals)))]


def _keep_list():
    return json.loads(OUTLIER_KEEP.read_text())['keep'] if OUTLIER_KEEP.exists() else {}


def donor_values(r):
    """Waarden die een ander product mag overnemen: gemeten (niet geschat), niet op 0 gezet omdat het product
    plantaardig is, en geen nagekeken uitschieter (outlier_keep.json: klopt voor dit product, zegt niets over een ander)."""
    skip = r.get('bio0', set()) | r.get('nodonor', set())
    return {k: v for k, v in r['nut'].items() if k not in r['est'] and k not in skip}


# Toets 2 alleen bij enkelvoudige, onbewerkte voedingsmiddelen (geen gerecht, geen poeder, drank of mengsel, niet
# verrijkt): bij "cornflakes" of "drank" verschillen de producten zelf. Zout en jodium niet: die hangen af van zouten
# en pekelen ("gekookt met zout"), zie KIN_NUTRIENTS. Vlees en vis als één deel (filet, spier, mager, met vet of vel).
KIN_GROUPS = {'fish', 'shellfish', 'meat', 'poultry', 'offal', 'egg', 'fruit', 'vegetable', 'nut/seed', 'legume',
              'mushroom', 'cereal', 'potato/tuber', 'herb/spice'}
KIN_KINDS = {'animal', 'plant', 'fungus', 'algae'}
FLESH = {'fillet', 'muscle', 'lean', 'muscle+fat', 'muscle+skin', 'whole'}
KIN_PARTS = FLESH | {'fruit', 'leaf', 'root', 'seed', 'kernel', 'bulb', 'stem', 'pod', 'flower', 'sprout', 'liver', 'heart',
                     'kidney', 'tongue', 'other offal', 'roe', 'bran', 'germ', 'tuber'}
# Alleen mineralen en B-vitaminen: die liggen binnen één soort dicht bij elkaar. Vitamine D (wilde of gekweekte vis),
# vitamine K en carotenen (ras, kleur, blad), vitamine C en E (bereiding in olie) en calcium (met graat of schelp)
# verschillen ook tussen echte metingen van hetzelfde voedingsmiddel te sterk.
# Een laatste woord dat een soort deel of product noemt, geen soort ("mustard seed" en "poppy seed" zijn geen familie)
KIN_GENERIC = {'seed', 'leave', 'leaf', 'berry', 'nut', 'root', 'bean', 'pepper', 'product', 'mix', 'powder', 'oil',
               'flour', 'meat', 'fish', 'vegetable', 'fruit', 'spice', 'herb', 'sprout', 'moss', 'seaweed', 'weed', 'juice',
               'drink', 'cereal', 'grain', 'mushroom', 'green', 'shoot', 'flower', 'offal', 'fillet', 'steak', 'cut'}
KIN_NUTRIENTS = {'potassium', 'magnesium', 'phosphorus', 'iron', 'zinc', 'copper', 'manganese', 'selenium', 'chromium',
                 'molybdenum', 'b1', 'b2', 'b3', 'b5', 'b6', 'b9', 'b12', 'choline'}


def kin_keys(r, l):
    """Sleutels voor "dezelfde soort" (toets 2 hierboven): labelgroep + deel + het laatste woord van het
    voedingsmiddel, of van de naam zelf ("grenadier" in "Roundnose grenadier, raw"), en het geslacht uit een Latijnse
    naam. Leeg buiten de enkelvoudige voedingsmiddelen (zie KIN_GROUPS)."""
    if not l or l.get('d') or l['g'] not in KIN_GROUPS or l['k'] not in KIN_KINDS or l['p'] not in KIN_PARTS or _fortified(l):
        return []
    part = 'flesh' if l['p'] in FLESH else l['p']
    keys = {('f', l['g'], part, l['f'].split()[-1]), ('n', l['g'], part, last_noun(re.sub(r'\([^)]*\)', ' ', r['name'])))}
    m = GENUS.search(r['name'])
    if m:
        keys.add(('genus', l['g'], part, m.group(1).lower()))
    return sorted(k for k in keys if k[-1] and (k[0] == 'genus' or k[-1] not in KIN_GENERIC))


# Tryptofaan is 1 à 1,5 % van het eiwit (vlees, vis, zuivel, granen; p99 van alle metingen 2,1 %). Een aandeel boven
# 2,5 % (bij minstens 1 g eiwit) is bijna altijd een meetfout: Frida geeft rundshart 11 %, gemalen koffie 48 % en
# schorseneer 33 %. Omdat B3 nu tryptofaan / 60 meetelt, geeft zo'n fout een B3 van 40 mg NE voor hart (werkelijk 11).
# Zulke waarden vallen weg en worden opnieuw geschat (in verhouding tot het eiwit), en de NE van de bron, die op dezelfde
# tryptofaan steunt, ook. Behalve als een andere databank voor hetzelfde voedingsmiddel ook meer dan 2 % meet
# (dadels, pecannoten: twee onafhankelijke analyses), of na controle in outlier_keep.json.
TRP_MAX_SHARE = 0.025
TRP_SUPPORT_SHARE = 0.02


def tryptophan_check(rows, labels):
    keep = _keep_list()
    refs = [f"{r['source']}:{r['sid']}" for r in rows]
    lab = [labels.get(ref) or {} for ref in refs]
    shares, by_food = {}, {}
    for i, r in enumerate(rows):
        n = r['nut']
        if 'tryptophan' in n and n.get('protein', 0) >= 1:
            shares[i] = n['tryptophan'] / n['protein']
            by_food.setdefault(lab[i].get('f') or r['name'].lower(), []).append(i)
    lines = []
    for i, share in shares.items():
        if share <= TRP_MAX_SHARE:
            continue
        r = rows[i]
        f = lab[i].get('f') or r['name'].lower()
        support = [j for j in by_food[f] if j != i and rows[j]['source'][:4] != r['source'][:4] and shares[j] > TRP_SUPPORT_SHARE]
        reason = keep.get(refs[i], {}).get('tryptophan')
        if reason:
            action = f'behouden: {reason}'
            r['nodonor'].add('tryptophan')
        elif support:
            action = f'behouden: ook {shares[support[0]] * 100:.1f} % in {refs[support[0]]}'
            CHANGES['tryptophan_supported'] += 1
        else:
            r['nut'].pop('tryptophan')
            # De NE van de bron (Frida, CoFID) rekent met dezelfde tryptofaan: ook die is fout
            r['ne'] = None
            CHANGES['tryptophan_dropped'] += 1
            action = 'weggelaten'
        lines.append(f"| {refs[i]} | {r['name']} | {lab[i].get('g') or '–'} | tryptophan | "
                     f"{sig(r['nut'].get('tryptophan', share * r['nut']['protein']))} | {share * 100:.1f} % van het eiwit | "
                     f"max {TRP_MAX_SHARE * 100:g} % | {action} |")
    return lines


def outlier_pass(rows, labels, report=None, extra_lines=()):
    keep = _keep_list()
    refs = [f"{r['source']}:{r['sid']}" for r in rows]
    lab = [labels.get(ref) or {} for ref in refs]
    skip = [r['category'] in SKIP_GROUP_CATEGORIES or bool(PILL_LIKE.search(r['name'])) for r in rows]

    def measured(i):
        r = rows[i]
        return {k: v for k, v in r['nut'].items() if k in SANITY_MICROS and k not in r.get('bio0', ()) and k not in r['est']}

    values = [measured(i) for i in range(len(rows))]
    kins = [kin_keys(rows[i], lab[i]) for i in range(len(rows))]
    by_group, by_all, by_food, by_kin = {}, {}, {}, {}
    for i, vals in enumerate(values):
        if skip[i]:
            continue
        g, f = lab[i].get('g', ''), lab[i].get('f') or rows[i]['name'].lower()
        for k, v in vals.items():
            by_group.setdefault((g, k), []).append(v)
            by_all.setdefault(k, []).append(v)
            by_food.setdefault((f, k), []).append((v, i))
            b = _basis(k, rows[i]['nut'])
            if b and b > (0.5 if k in FATTY or k in AMINO else 3):
                for key in kins[i]:
                    by_kin.setdefault((key, k), []).append((v / b, i))
    for d in (by_group, by_all):
        for vals in d.values():
            vals.sort()

    def kin_spike(i, k, v):
        """(soort, referentiewaarde voor dit product) als de waarde een piek is binnen dezelfde soort, anders None."""
        b = _basis(k, rows[i]['nut'])
        if k not in KIN_NUTRIENTS or not b or b <= (0.5 if k in FATTY or k in AMINO else 3) or v < 2 * SANITY_FLOOR[k]:
            return None
        x = v / b
        for key in kins[i]:
            others = [(y, j) for y, j in by_kin.get((key, k), ()) if j != i]
            if len(others) < OUTLIER_KIN_MIN:
                continue
            med = statistics.median(y for y, _ in others)
            if x > OUTLIER_KIN_RATIO * max(med, SANITY_FLOOR[k] / b) and not any(y >= x / OUTLIER_SUPPORT for y, _ in others):
                return key[-1], med * b
        return None

    dropped, kept, lines = 0, 0, list(extra_lines)
    for i, vals in enumerate(values):
        if skip[i]:
            continue
        g, f = lab[i].get('g', ''), lab[i].get('f') or rows[i]['name'].lower()
        for k, v in vals.items():
            floor = SANITY_FLOOR[k]
            glob = max(_pct(by_all[k], 0.999), floor)
            grp = by_group.get((g, k), ())
            ref = max(_pct(grp, 0.99), floor) if len(grp) >= 30 else glob
            rg, rgl = v / ref, v / glob
            test = None
            if (rg > OUTLIER_GROUP_RATIO and rgl > OUTLIER_GROUP_MIN_GLOBAL) or rgl > OUTLIER_GLOBAL_RATIO:
                test = 'groep'
            else:
                spike = kin_spike(i, k, v)
                if spike:
                    test, ref = f'soort: {spike[0]}', spike[1]
            if test is None:
                continue
            if any(j != i and x >= v / OUTLIER_SUPPORT for x, j in by_food.get((f, k), ())):
                continue
            reason = keep.get(refs[i], {}).get(k)
            if reason:
                kept += 1
                rows[i]['nodonor'].add(k)
                action = f'behouden: {reason}'
            else:
                rows[i]['nut'].pop(k, None)
                rows[i]['loq'].pop(k, None)
                # Vitamine A die wij uit retinol + bètacaroteen berekenden, steunt op dezelfde foute waarde
                if k in ('beta_carotene', 'retinol') and rows[i]['retinol'] is not None:
                    rows[i]['nut'].pop('vit_a', None)
                dropped += 1
                if test != 'groep':
                    CHANGES['outliers_same_food'] += 1
                action = 'weggelaten'
            lines.append(f"| {refs[i]} | {rows[i]['name']} | {g or '–'} | {k} | {sig(v)} | {sig(ref)} ({test}) | {sig(glob)} | {action} |")
    CHANGES['outliers_dropped'] += dropped
    CHANGES['outliers_kept'] += kept
    if report is not None:
        report.write_text(
            '# Onwaarschijnlijke metingen\n\n'
            'Geschreven door `tool/build_foods.py` (zie `outlier_pass` en `tryptophan_check`). Per 100 g. Referentie: '
            '"groep" = 99e percentiel van de voedingsgroep; "soort: x" = mediaan van andere producten van dezelfde soort '
            '(zelfde labelgroep en hoofdwoord, of hetzelfde Latijnse geslacht), omgerekend naar dit product; bij '
            'tryptofaan het aandeel van het eiwit. Alle = 99,9e percentiel van alle producten. Weggelaten waarden worden '
            'daarna geschat zoals elke ontbrekende waarde. Behouden staat met de reden in `tool/outlier_keep.json` (en is '
            'nooit donor bij het aanvullen), of wordt gesteund door een andere databank. Fouten die deze toetsen net '
            'missen (harder `ciqual:26091` met 168 µg selenium, 4× de andere harders; rode paprika `frida:38` met 70 µg '
            'molybdeen), staan met de reden in `tool/food_fixes.json`.\n\n'
            '| product | naam | groep | stof | waarde | referentie | alle | wat |\n|---|---|---|---|---|---|---|---|\n'
            + '\n'.join(sorted(lines)) + '\n')
    return dropped, kept


# ─────────────────────────── Niacine-equivalenten ───────────────────────────
#
# Het EFSA-doel voor B3 staat in niacine-equivalenten (1,6 mg NE per MJ): het lichaam maakt niacine uit tryptofaan,
# 60 mg tryptofaan = 1 mg niacine. De bronnen geven meestal alleen voorgevormde niacine; tegenover het NE-doel
# lijkt melk, ei of peulvruchten dan een B3-tekort te geven dat er niet is (bevinding NF-2). Dus na het aanvullen:
#   - som = voorgevormde niacine (gemeten of geschat) + tryptofaan (g) × 1000 / 60, met de gemeten of geschatte
#     tryptofaan;
#   - gaf de bron zelf niacine-equivalenten (CoFID, Frida, Matvaretabellen, Livsmedelsverket), dan die, tenzij de som
#     duidelijk hoger is: max(NE van de bron, som), met 10 % speling voor de NE van de bron (afronding, een geschatte
#     tryptofaan). Frida laat bij granen de voorgevormde niacine bewust weg (documentatie §7.2: tarwezemelen 3,4 mg
#     NE tegenover 29,6 mg niacine) en mist ze soms; CoFID heeft rekenfouten (gedroogde basilicum: niacine 6,9 +
#     tryptofaan/60 3,7, maar NE 1,6). De EFSA-definitie telt de niacine wel, dus elke bron dezelfde regel;
#   - telt de geschatte tryptofaan voor meer dan de helft van de som, dan geldt B3 ook als geschat (met dezelfde
#     herkomst), net als wanneer de voorgevormde niacine zelf geschat was;
#   - zonder tryptofaan blijft het voorgevormde niacine (een ondergrens).
# Niet tijdens het aanvullen: dan zou NE van het ene product als voorgevormde niacine bij een ander terechtkomen.
NE_SOURCE_SLACK = 0.9


def niacin_ne(rows):
    for r in rows:
        n, est = r['nut'], r['est']
        src, pre, trp = r.get('ne'), n.get('b3'), n.get('tryptophan')
        total = None if pre is None or trp is None else pre + trp * 1000 / TRP_PER_NE
        if src is not None and (total is None or src >= NE_SOURCE_SLACK * total):
            n['b3'] = src
            est.pop('b3', None)
            CHANGES['niacin_ne_source'] += 1
            continue
        if total is None:
            if pre is not None:
                CHANGES['niacin_preformed_only'] += 1
            continue
        if src is not None:
            CHANGES['niacin_ne_source_incomplete'] += 1
        part = trp * 1000 / TRP_PER_NE
        if 'tryptophan' in est and 'b3' not in est and part > pre:
            est['b3'] = est['tryptophan']
            CHANGES['niacin_ne_trp_estimated'] += 1
        n['b3'] = total
        CHANGES['niacin_ne_trp'] += 1


def retinol_consistency(rows):
    """Retinol is een deel van vitamine A (RE): een geschat retinol niet boven het totaal, een geschat totaal niet
    onder het retinol."""
    for r in rows:
        n, est = r['nut'], r['est']
        if 'retinol' in n and 'vit_a' in n and n['retinol'] > n['vit_a'] * 1.02:
            if 'retinol' in est:
                n['retinol'] = n['vit_a']
            elif 'vit_a' in est:
                n['vit_a'] = n['retinol'] + n.get('beta_carotene', 0) / VIT_A_BC


# ─────────────────────────── Nauwkeurigheidstest ───────────────────────────

HOLDOUT_KEYS = ['choline', 'b5', 'vit_k', 'iodine', 'selenium', 'vit_d', 'b12', 'manganese', 'copper', 'vit_e', 'b9',
                'b1', 'b2', 'b3', 'b6', 'vit_c', 'vit_a', 'beta_carotene', 'zinc', 'iron', 'magnesium', 'potassium',
                'calcium', 'phosphorus', 'lysine', 'cholesterol', 'ala', 'epa', 'dha']


def holdout(rows, n):
    """Verbergt n willekeurige gemeten waarden (> 0) en onthoudt ze."""
    # HOLDOUT_OLD=1: alleen uit de bronnen van vóór 26-10-2026 (zelfde steekproef met en zonder BLS en FNDDS)
    new = {'bls', 'usda_fndds'} if os.environ.get('HOLDOUT_OLD') else set()
    pool = [(i, k) for i, r in enumerate(rows) for k in HOLDOUT_KEYS
            if r['source'] not in new and r['nut'].get(k, 0) > 0 and k not in r.get('bio0', ()) and r['category'] not in SKIP_GROUP_CATEGORIES]
    if new:
        # Zelfde steekproef in beide builds: kiezen op een vaste hash van product en stof, niet op positie (een
        # verschoven lijst gaf een heel andere loting)
        def h(x):
            return hashlib.sha1(f"{rows[x[0]]['source']}:{rows[x[0]]['sid']}:{x[1]}".encode()).hexdigest()
        picked = sorted(pool, key=h)[:n]
    else:
        picked = random.Random(42).sample(pool, min(n, len(pool)))
    hidden = []
    for i, k in picked:
        hidden.append((rows[i], k, rows[i]['nut'].pop(k)))
    return hidden


def holdout_report(hidden):
    import math
    by_key, by_tier = {}, {}
    missing = 0
    for r, k, truth in hidden:
        v = r['nut'].get(k)
        if v is None:
            missing += 1
            continue
        src = r['est'].get(k, '')
        tier = 'groep' if src.startswith('~~') else 'andere bereiding' if src.startswith('~') else 'zelfde voeding'
        err = abs(math.log(max(v, 1e-6) / truth))
        for table, key in ((by_key, k), (by_tier, tier)):
            table.setdefault(key, []).append((err, v, truth))

    def line(name, items):
        errs = sorted(e for e, _, _ in items)
        med = math.exp(errs[len(errs) // 2]) - 1
        within25 = sum(1 for e in errs if e <= math.log(1.25)) / len(errs)
        within2 = sum(1 for e in errs if e <= math.log(2)) / len(errs)
        return f'| {name} | {len(items)} | {med:.0%} | {within25:.0%} | {within2:.0%} |'
    print(f'verborgen: {len(hidden)}, niet geschat: {missing}')
    print('| | aantal | typische afwijking (mediaan) | binnen ±25% | binnen 2× |')
    print('|---|---|---|---|---|')
    print(line('ALLES', [x for v in by_key.values() for x in v]))
    for t in ('zelfde voeding', 'andere bereiding', 'groep'):
        if t in by_tier:
            print(line(t, by_tier[t]))
    for k in sorted(by_key, key=lambda k: -len(by_key[k])):
        print(line(k, by_key[k]))


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
          label TEXT NOT NULL DEFAULT '',
          UNIQUE (source, source_id)
        );
        CREATE TABLE portions (food_id INTEGER NOT NULL, label TEXT NOT NULL, grams REAL NOT NULL);
        CREATE INDEX portions_food ON portions(food_id);
        CREATE TABLE sources (source TEXT PRIMARY KEY, description TEXT NOT NULL, foods INTEGER NOT NULL);
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    ''')
    rows = []
    # SKIP_SOURCES=bls,usda_fndds: zonder die bronnen bouwen (om te vergelijken, zie HOLDOUT)
    skip = set(filter(None, os.environ.get('SKIP_SOURCES', '').split(',')))
    for gen in (ciqual_rows, slv_rows, mvt_rows, frida_rows, cofid_rows, bls_rows, usda_rows, fndds_rows):
        for source, sid, name, local, category, raw, portions in gen(root):
            if source in skip:
                continue
            loq, retinol, ne, unsplit, below_loq = {}, None, None, False, set()
            if source.startswith('usda'):
                if category in USDA_SKIP_CATEGORIES:
                    continue
                nut = usda_nutrients(raw)
            else:
                loq = raw.pop('_loq', {})
                below_loq = raw.pop('_loq60', set())
                # Vitamine A die we zelf uit retinol + bètacaroteen berekenen: na het aanvullen van bètacaroteen opnieuw
                retinol = (raw.get('retinol', 'unknown')) if 'vit_a' not in raw else None
                # Niacine-equivalenten zoals de bron ze gaf (CoFID, Frida, Livsmedelsverket), zie niacin_ne
                ne = raw.get('_ne')
                unsplit = raw.get('_unsplit', False)
                if 'vit_a' not in raw and 'retinol' in raw and raw.get('beta_carotene'):
                    CHANGES['vit_a_re_computed'] += 1
                nut = finish(raw)
            if 'energy' not in nut or not name:
                continue
            rows.append({'source': source, 'sid': sid, 'name': name, 'local': local, 'category': category,
                         'nut': nut, 'est': {}, 'portions': portions, 'loq': loq, 'retinol': retinol, 'ne': ne,
                         'unsplit': unsplit, 'nodonor': set(), 'below_loq': below_loq})

    WASTE.update(id(r['nut']) for r in rows if WASTE_NAME.search(r['name']))
    print(f'correcties uit {FIXES_FILE.name}: {apply_fixes(rows)} waarden')
    for r in rows:
        validate_measured(r)
    labels = {} if os.environ.get('NOLABELS') else load_labels()
    for r in rows:
        l = labels.get(f"{r['source']}:{r['sid']}")
        if l and l['g'] == 'rice' and PARBOILED.search(r['name']) and 'parboiled' not in l['fl']:
            l['fl'].append('parboiled')
    cofid_unsplit_carbs(rows, labels)
    mvt_below_loq(rows, labels)
    zeros_not_measured(rows, labels)
    # Vóór het aanvullen: een foute meting mag niet doorgegeven worden aan andere producten
    trp_lines = tryptophan_check(rows, labels)
    dropped, kept = outlier_pass(rows, labels, report=None if os.environ.get('HOLDOUT') else OUTLIER_REPORT,
                                 extra_lines=trp_lines)
    print(f'onwaarschijnlijke metingen: {dropped} weggelaten, {kept} nagekeken en behouden (zie {OUTLIER_REPORT.name})')
    # Nauwkeurigheidstest: HOLDOUT=<aantal> verbergt zoveel gemeten waarden, laat ze schatten en vergelijkt
    hidden = holdout(rows, int(os.environ['HOLDOUT'])) if os.environ.get('HOLDOUT') else []
    labelled = sum(1 for r in rows if f"{r['source']}:{r['sid']}" in labels)
    print(f'labels: {labelled} van {len(rows)} producten')
    if labelled:
        import retention
        table = retention.load(root / 'usda_retention' / 'retn06.txt')
        print(f'plantaardig zonder B12/cholesterol/…: {label_rules(rows, labels)} waarden op 0')
        same, sim, grp = label_fill(rows, labels, table)
        print(f'aangevuld: hetzelfde voedingsmiddel {same}, andere bereiding (met kookverliezen) {sim}, groep {grp}')
    # Producten zonder label (of zonder labelbestand): de oudere aanvulling op naam
    if labelled < len(rows):
        print(f'plantaardig zonder B12/cholesterol/…: {sum(plant_zeros(r) for r in rows)} waarden op 0')
        before = sum(len(r['nut']) for r in rows)
        filled = gap_fill(rows)
        print(f'aangevuld (op naam): {filled} waarden ({filled / before * 100:.0f}% extra)')
        similar = similar_fill(rows)
        print(f'aangevuld uit een vergelijkbaar product (op naam): {similar} waarden')
        grouped = group_fill(rows)
        print(f'aangevuld uit het gemiddelde van vergelijkbare producten (op naam): {grouped} waarden')
    # Wat onder de meetgrens lag en nergens anders gevonden werd, is praktisch 0
    zero = 0
    for r in rows:
        for k in r['loq']:
            if k not in r['nut'] and not k.startswith('_'):
                # Waar 0 niet kan (zeros_not_measured): de helft van de meetgrens
                if k in r.get('loq_half', ()):
                    r['nut'][k] = r['loq'][k] / 2
                    CHANGES['loq_half'] += 1
                    continue
                r['nut'][k] = 0.0
                zero += 1
    print(f'onder de meetgrens, op 0 gezet: {zero} waarden')
    for r in rows:
        consistency(r)
    if hidden:
        holdout_report(hidden)
        return
    # Vitamine A opnieuw uit retinol + bètacaroteen, nu bètacaroteen eventueel is aangevuld
    for r in rows:
        bc = r['nut'].get('beta_carotene')
        if r['retinol'] == 'unknown' and bc is not None and kind(r['name'], r['category']) == 'plant':
            # Planten bevatten geen retinol: vitamine A = bètacaroteen / 6 (RE, zie VIT_A_BC)
            r['nut']['vit_a'] = bc / VIT_A_BC
            r['est'].pop('vit_a', None)
            if 'beta_carotene' in r['est']:
                r['est']['vit_a'] = r['est']['beta_carotene']
        elif isinstance(r['retinol'], float) and 'beta_carotene' in r['est'] and bc:
            r['nut']['vit_a'] = r['retinol'] + bc / VIT_A_BC
            # Geschat als het geschatte caroteendeel de doorslag geeft; lever (10 500 µg retinol, 33 µg uit caroteen)
            # blijft gemeten, anders haalde de controle op geschatte uitschieters het vitamine A van lever weg
            if bc / VIT_A_BC > r['retinol']:
                r['est']['vit_a'] = r['est']['beta_carotene']
            else:
                r['est'].pop('vit_a', None)
    retinol_consistency(rows)
    d, p, eo = sanity_pass(rows, labels)
    print(f'opgeschoond: dierlijk vezels/zetmeel {d}, plantaardig onmogelijk {p}, geschatte uitschieters {eo}')
    niacin_ne(rows)
    print('tellingen per regel: ' + ', '.join(f'{k} {v}' for k, v in CHANGES.items()))

    # Het label gaat mee naar de app (voor advies en voedingsgroepen), met n = in hoeveel bronnen dit voedingsmiddel
    # voorkomt: hoe meer landen het in hun tabel hebben, hoe gewoner het is
    spread = {}
    for ref, x in labels.items():
        spread.setdefault(x['f'], set()).add(ref.split(':')[0])

    def app_label(r):
        x = labels.get(f"{r['source']}:{r['sid']}")
        if not x:
            return ''
        out = {k: x[k] for k in ('f', 'g', 'p', 'k', 'c')}
        if x.get('fl'):
            out['fl'] = x['fl']
        if x.get('d'):
            out['d'] = 1
        out['n'] = len(spread[x['f']])
        return json.dumps(out, separators=(',', ':'), ensure_ascii=False)

    # Namen die in het Engels iets anders betekenen dan wat het is: Brits "potato chips" zijn frieten (NF-7), Noors
    # "Havremel" is havermeel, geen havermout (NW-13). De oude naam blijft zoekbaar.
    def display_name(r):
        n = r['name']
        if r['source'] == 'cofid':
            n = re.sub(r'^Potato chips\b', 'French fries', n)
        if r['source'] == 'mvt' and (r['local'] or '').startswith('Havremel'):
            n = re.sub(r'^Oatmeal\b', 'Oat flour', n)
        if r['source'] == 'usda_fndds':
            n = fndds_name(n)
        return n

    counts = {}
    for r in rows:
        nut, est = r['nut'], r['est']
        derive(nut, est)
        name = display_name(r)
        search = f"{name} {r['name']} {r['local']}" if name != r['name'] else f"{r['name']} {r['local']}"
        cur = db.execute(
            'INSERT INTO foods (source, source_id, name, name_local, search, category, nutrients, estimated, label) VALUES (?,?,?,?,?,?,?,?,?)',
            (r['source'], r['sid'], name, r['local'], search.lower(), r['category'],
             json.dumps({k: sig(v) for k, v in nut.items()}, separators=(',', ':'), ensure_ascii=False),
             json.dumps(est, separators=(',', ':')), app_label(r)),
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
