"""Controleert de ingebouwde voedingsdatabase op waarden die niet kunnen kloppen bij de naam van het product.

Gebruik: python3 tool/audit_foods.py assets/db/foods.db uitvoer/
Schrijft uitvoer/bevindingen.csv (één regel per verdachte waarde) en uitvoer/samenvatting.md.

Controles:
  energie      kcal past niet bij eiwit/koolhydraten/vet/vezels/alcohol (EU-factoren)
  som          eiwit + koolhydraten + vet + vezels + water + alcohol is meer dan 100 g
  deelsom      suikers + zetmeel > koolhydraten, vetzuren > vet, EPA + DHA > meervoudig onverzadigd…
  aminozuren   aminozuren passen niet bij het eiwit (meer dan het eiwit, of eiwit 0 met aminozuren)
  grens        waarde hoger dan in eender welk echt voedingsmiddel (per 100 g)
  plant        B12, cholesterol, retinol, EPA/DHA of veel vitamine D in een zuiver plantaardig product
  dier         vezels, zetmeel of veel vitamine C/bètacaroteen in zuiver vlees, vis, melk of ei
  uitschieter  meer dan 20× (of minder dan 1/20 van) de mediaan van dezelfde groep, vaak een eenheidsfout
  geschat      een aangevulde waarde (≈) die zelf een uitschieter is, of van een donor met een andere naam
"""
import csv
import json
import math
import re
import sqlite3
import statistics
import sys
from collections import defaultdict
from pathlib import Path

from build_foods import kind  # zelfde indeling plantaardig/dierlijk als bij het opbouwen

# Hoogste waarden per 100 g die in echte voedingsmiddelen voorkomen (ruim genomen; supplementen zitten niet in de database)
LIMITS = {
    'energy': 902, 'protein': 95, 'carbs': 100, 'fat': 100, 'fiber': 85, 'sugars': 100, 'starch': 92, 'water': 100,
    'alcohol': 95, 'cholesterol': 3200,  # hersenen ~3100, eigeel-poeder ~2300
    # (lever, zeewier, bakpoeder, gist en voedingssupplementen gaan hier terecht boven: die worden apart nagekeken)
    'sodium': 39400, 'potassium': 16500, 'calcium': 2700, 'magnesium': 1300, 'phosphorus': 3500, 'iron': 130,
    'zinc': 80, 'copper': 15, 'manganese': 140, 'selenium': 2000, 'iodine': 50000,  # zeewier (kombu) tot ~ 2.000.000? zie hieronder
    'vit_c': 2000, 'vit_d': 260, 'vit_e': 160, 'vit_k': 1800, 'vit_a': 30000, 'beta_carotene': 50000,
    'b1': 30, 'b2': 30, 'b3': 130, 'b5': 30, 'b6': 15, 'b9': 4000, 'b12': 110, 'choline': 1100, 'caffeine': 4000,
    'lycopene': 50000, 'lutein_zeaxanthin': 50000,
}
LIMITS['iodine'] = 400000  # gedroogd kombu kan > 200 mg/100 g bevatten

AMINOS = ('histidine', 'isoleucine', 'leucine', 'lysine', 'methionine', 'cystine', 'phenylalanine', 'tyrosine', 'threonine', 'tryptophan', 'valine')
MICROS = (
    'sodium', 'potassium', 'calcium', 'magnesium', 'phosphorus', 'iron', 'zinc', 'copper', 'manganese', 'selenium', 'iodine',
    'vit_c', 'vit_d', 'vit_e', 'vit_k', 'vit_a', 'beta_carotene', 'b1', 'b2', 'b3', 'b5', 'b6', 'b9', 'b12', 'choline', 'cholesterol',
)
# Onder deze waarde telt een verschil met de groep niet (meetruis rond nul)
FLOOR = {
    'sodium': 20, 'potassium': 50, 'calcium': 20, 'magnesium': 10, 'phosphorus': 30, 'iron': 0.5, 'zinc': 0.5, 'copper': 0.1,
    'manganese': 0.2, 'selenium': 5, 'iodine': 5, 'vit_c': 5, 'vit_d': 0.5, 'vit_e': 0.5, 'vit_k': 5, 'vit_a': 30,
    'beta_carotene': 100, 'b1': 0.05, 'b2': 0.05, 'b3': 0.5, 'b5': 0.2, 'b6': 0.05, 'b9': 10, 'b12': 0.3, 'choline': 10,
    'cholesterol': 10,
}


def main(db_path, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(db_path)
    foods = []
    for fid, source, sid, name, cat, nut, est in db.execute('SELECT id, source, source_id, name, category, nutrients, estimated FROM foods'):
        foods.append({'id': fid, 'ref': f'{source}:{sid}', 'source': source, 'name': name, 'cat': cat or '(geen)', 'n': json.loads(nut), 'est': json.loads(est)})
    by_ref = {f['ref']: f for f in foods}
    findings = []

    def flag(f, check, key, value, detail):
        findings.append({'ref': f['ref'], 'name': f['name'], 'category': f['cat'], 'check': check, 'nutrient': key,
                         'value': value, 'estimated_from': f['est'].get(key, ''), 'detail': detail})

    # Medianen per groep (bron + categorie), alleen gemeten waarden
    groups = defaultdict(lambda: defaultdict(list))
    for f in foods:
        for k in MICROS:
            if k in f['n'] and k not in f['est']:
                groups[(f['source'], f['cat'])][k].append(f['n'][k])

    for f in foods:
        n, name = f['n'], f['name']
        g = lambda k: n.get(k, 0) or 0

        # energie (EU: 4/4/9/2/7); USDA rekent koolhydraten "by difference" maar wij slaan beschikbare koolhydraten op
        if all(k in n for k in ('protein', 'carbs', 'fat')):
            calc = 4 * g('protein') + 4 * g('carbs') + 9 * g('fat') + 2 * g('fiber') + 7 * g('alcohol')
            e = g('energy')
            if abs(calc - e) > max(25, 0.25 * max(calc, e)):
                flag(f, 'energie', 'energy', e, f'berekend uit macro\'s {calc:.0f} kcal')

        total = sum(g(k) for k in ('protein', 'carbs', 'fat', 'fiber', 'water', 'alcohol'))
        if total > 106:
            flag(f, 'som', 'total', round(total, 1), 'eiwit+koolh.+vet+vezels+water+alcohol > 100 g')

        for parts, whole, slack in ((('sugars', 'starch'), 'carbs', 2), (('sfa', 'mufa', 'pufa', 'trans'), 'fat', 1.5),
                                    (('la', 'ala', 'aa', 'epa', 'dpa', 'dha'), 'pufa', 0.6)):
            if whole in n and any(p in n for p in parts):
                s = sum(g(p) for p in parts)
                if s > n[whole] * 1.1 + slack:
                    flag(f, 'deelsom', whole, n[whole], f'{"+".join(parts)} = {s:.2f}')

        aa = sum(g(k) for k in AMINOS)
        if any(k in n for k in AMINOS):
            if g('protein') == 0 and aa > 0.3:
                flag(f, 'aminozuren', 'protein', 0, f'eiwit 0 maar aminozuren {aa:.2f} g')
            elif aa > g('protein') * 1.0 + 0.5:
                flag(f, 'aminozuren', 'protein', g('protein'), f'essentiële aminozuren {aa:.2f} g > eiwit')

        for k, lim in LIMITS.items():
            if g(k) > lim:
                flag(f, 'grens', k, n[k], f'hoger dan {lim} (bestaat niet in echte voeding)')
        for k, v in n.items():
            if isinstance(v, (int, float)) and v < 0:
                flag(f, 'grens', k, v, 'negatief')

        kd = kind(name, f['cat'])
        if kd == 'plant':
            if g('b12') > 0.3 and not re.search(r'\b(nori|laver|seaweed|algae|spirulina|chlorella|tempeh|mushroom|shiitake)\b', name, re.I):
                flag(f, 'plant', 'b12', n['b12'], 'B12 in zuiver plantaardig product')
            if g('cholesterol') > 5:
                flag(f, 'plant', 'cholesterol', n['cholesterol'], 'cholesterol in zuiver plantaardig product')
            if g('epa') + g('dha') > 0.02 and not re.search(r'\b(algae|algal|seaweed|kelp)\b', name, re.I):
                flag(f, 'plant', 'epa+dha', round(g('epa') + g('dha'), 3), 'EPA/DHA in zuiver plantaardig product')
            if g('vit_d') > 1 and not re.search(r'\b(mushrooms?|shiitake|chanterelle|morel|maitake|champignon)\b', name, re.I):
                flag(f, 'plant', 'vit_d', n['vit_d'], 'vitamine D in plantaardig product (geen paddenstoel)')
            # USDA telt ook alfa-caroteen en cryptoxanthine mee in vitamine A, dus alleen voor de Europese bronnen
            if f['source'] in ('ciqual', 'slv', 'mvt') and 'vit_a' in n and 'beta_carotene' in n and n['vit_a'] > n['beta_carotene'] / 12 * 1.8 + 30:
                flag(f, 'plant', 'vit_a', n['vit_a'], f'vitamine A veel hoger dan bètacaroteen/12 ({n["beta_carotene"] / 12:.0f}): retinol in plant?')
        elif kd == 'dier':
            if g('fiber') > 0.5:
                flag(f, 'dier', 'fiber', n['fiber'], 'vezels in zuiver dierlijk product')
            if g('starch') > 1:
                flag(f, 'dier', 'starch', n['starch'], 'zetmeel in zuiver dierlijk product')
            if g('vit_c') > 15 and not re.search(r'\b(liver|kidney|spleen|thymus|roe|heart|brain|lung|sweetbread)\b', name, re.I):
                flag(f, 'dier', 'vit_c', n['vit_c'], 'veel vitamine C in vlees/vis/zuivel')
            if g('beta_carotene') > 300:
                flag(f, 'dier', 'beta_carotene', n['beta_carotene'], 'veel bètacaroteen in vlees/vis/zuivel')
            if g('vit_k') > 60 and not re.search(r'\b(liver|cheese|natto|goose)\b', name, re.I):
                flag(f, 'dier', 'vit_k', n['vit_k'], 'veel vitamine K in vlees/vis/zuivel')

        # Uitschieters binnen dezelfde groep (ook voor geschatte waarden: die zijn het meest verdacht)
        grp = groups[(f['source'], f['cat'])]
        for k in MICROS:
            if k not in n or len(grp[k]) < 8:
                continue
            med = statistics.median(grp[k])
            v = n[k]
            floor = FLOOR[k]
            ratio = (max(v, floor) / max(med, floor))
            if ratio > 20 or ratio < 1 / 20:
                tag = 'geschat' if k in f['est'] else 'uitschieter'
                flag(f, tag, k, v, f'mediaan groep {med:.3g} (×{ratio:.3g})')

        # Geschatte waarden: past de naam van de donor?
        for k, donor_ref in f['est'].items():
            d = by_ref.get(donor_ref)
            if not d:
                continue
            if g('energy') and d['n'].get('energy') and not (1 / 1.5 <= d['n']['energy'] / g('energy') <= 1.5):
                flag(f, 'geschat', k, n.get(k), f'donor {donor_ref} "{d["name"]}" heeft {d["n"]["energy"]:.0f} kcal')

    findings.sort(key=lambda x: (x['check'], x['name']))
    with open(out / 'bevindingen.csv', 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(findings[0].keys()) if findings else ['ref'])
        w.writeheader()
        w.writerows(findings)

    per_check = defaultdict(int)
    per_food = defaultdict(set)
    for x in findings:
        per_check[x['check']] += 1
        per_food[x['ref']].add(x['check'])
    lines = [f'# Audit voedingsdatabase\n', f'{len(foods)} voedingsmiddelen, {len(findings)} bevindingen bij {len(per_food)} producten.\n',
             '| Controle | Bevindingen |', '|---|---|']
    lines += [f'| {k} | {v} |' for k, v in sorted(per_check.items(), key=lambda kv: -kv[1])]
    (out / 'samenvatting.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
