"""Neemt de beoordelingen van verdachte waarden over in tool/food_fixes.json en tool/label_fixes.json.

Gebruik: python3 tool/apply_review.py <review-map>   (met out/review_*.jsonl, zie review/SPEC.md)
- verdict "error": de waarde wordt vervangen (fix) of weggelaten (null, dan opnieuw aangevuld);
- verdict "others_wrong": idem voor de andere producten in fix_others;
- verdict "label": het label van het product wordt verbeterd;
- "legit": niets (beide waarden kunnen kloppen).
Bestaande correcties met de hand blijven staan; een correctie uit de review overschrijft ze niet.
"""
import json
import sys
from collections import Counter
from pathlib import Path

TOOL = Path(__file__).parent
# Voorstellen die niet overgenomen worden: ze passen niet bij de opgegeven energie van het product (dan is eerder
# het product anders dan de naam zegt dan dat één waarde fout is)
REJECT = {('mvt:06.729', 'carbs'), ('slv:7032', 'fat'), ('slv:7032', 'carbs'), ('mvt:06.130', 'carbs'),
          ('mvt:10.138', 'carbs'), ('mvt:05.075', 'carbs'), ('mvt:05.075', 'water'), ('cofid:13-339', 'carbs'),
          ('slv:6342', 'carbs'), ('usda_sr:170059', 'carbs')}
# Bijgestuurd: eiwit van de pepersaus weglaten (water 95%, dus 12,9 g eiwit kan niet), zeezout bevat bijna geen water
OVERRIDE = {('slv:7032', 'protein'): None, ('mvt:12.026', 'water'): 0.2}


PARTS = {'whole', 'white', 'yolk', 'muscle', 'muscle+skin', 'muscle+fat', 'lean', 'fat', 'skin', 'liver', 'kidney',
         'heart', 'tongue', 'brain', 'other offal', 'blood', 'bone/broth', 'fillet', 'roe', 'leaf', 'stem', 'root',
         'bulb', 'flower', 'fruit', 'seed', 'pod', 'sprout', 'peel', 'kernel', 'juice', 'concentrate', 'oil', 'flour',
         'bran', 'germ', 'starch', 'powder', 'paste', 'puree', 'jam', 'syrup', 'drink', 'product'}


def main(d):
    fixes_path = TOOL / 'food_fixes.json'
    fixes = json.loads(fixes_path.read_text())
    label_path = TOOL / 'label_fixes.json'
    label_fixes = json.loads(label_path.read_text()) if label_path.exists() else {}
    counts = Counter()

    def put(ref, key, value, why):
        entry = fixes['fixes'].setdefault(ref, {})
        if key in entry:
            return
        entry[key] = value
        reason = f'{key}: {why} (vergelijking met andere databanken)'
        entry['_waarom'] = f"{entry['_waarom']}; {reason}" if entry.get('_waarom') else reason
        counts['waarde'] += 1

    for f in sorted(Path(d).glob('out/review_*.jsonl')):
        for line in open(f):
            r = json.loads(line)
            counts[r['verdict']] += 1
            key = (r['ref'], r['nutrient'])
            if key in REJECT:
                counts['afgewezen'] += 1
                continue
            if key in OVERRIDE:
                r = dict(r, verdict='error', fix=OVERRIDE[key])
            if r['verdict'] == 'error':
                put(r['ref'], r['nutrient'], r.get('fix'), r.get('why', ''))
            elif r['verdict'] == 'others_wrong':
                for ref, v in (r.get('fix_others') or {}).items():
                    put(ref, r['nutrient'], v, r.get('why', ''))
            elif r['verdict'] == 'label' and r.get('label_fix'):
                change = {k: v for k, v in r['label_fix'].items() if k in ('f', 'p', 'c', 'fl', 'g', 'k', 'd')}
                if change.get('p') not in (None, *PARTS):
                    change['p'] = 'product'
                label_fixes.setdefault(r['ref'], {}).update(change)
    fixes_path.write_text(json.dumps(fixes, ensure_ascii=False, indent=2) + '\n')
    label_path.write_text(json.dumps(label_fixes, ensure_ascii=False, indent=2) + '\n')
    print(dict(counts), f'-> {len(fixes["fixes"])} producten met correcties, {len(label_fixes)} labelcorrecties')


if __name__ == '__main__':
    main(sys.argv[1])
