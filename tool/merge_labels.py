"""Voegt de gelabelde pakketten samen tot tool/food_labels.jsonl, met kleine opkuis.

Gebruik: python3 tool/merge_labels.py <labels-map>
- dezelfde namen gelijktrekken (enkelvoud/meervoud, yogurt/yoghurt, …);
- kenmerken die in de productnaam staan maar soms vergeten werden: "low sodium"/"no salt added" → unsalted,
  "weighed with bone" → with bone;
- rare kenmerken opsplitsen of weglaten.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ALLOWED_FLAGS = {
    'salted', 'unsalted', 'sweetened', 'unsweetened', 'fortified', 'added fat', 'no added fat', 'lean', 'reduced fat',
    'full fat', 'with skin', 'without skin', 'with bone', 'breaded', 'in oil', 'in water', 'in syrup', 'in juice',
    'in brine', 'in sauce', 'wild', 'farmed', 'organic', 'infant', 'brand', 'diet', 'decaffeinated', 'instant',
}
SYNONYMS = {'yogurt': 'yoghurt', 'potato crisps': 'potato chips', 'rye-wheat bread': 'rye and wheat bread'}


def main(d):
    d = Path(d)
    items = {}
    for f in (d / 'in').glob('batch_*.jsonl'):
        for line in open(f):
            x = json.loads(line)
            items[x['id']] = x
    labels = [json.loads(line) for f in sorted((d / 'out').glob('batch_*.jsonl')) for line in open(f)]
    count = Counter(l['f'].strip().lower() for l in labels)

    def canon(f):
        f = re.sub(r'\s+', ' ', f.strip().lower())
        for a, b in SYNONYMS.items():
            f = re.sub(rf'\b{a}\b', b, f)
        # Enkelvoud en meervoud: de vaakst gebruikte vorm wint
        for alt in (f[:-1] if f.endswith('s') else f + 's',):
            if alt in count and count[alt] > count.get(f, 0):
                return alt
        return f

    out = []
    for l in labels:
        name = ' '.join(str(items[l['id']].get(k, '')) for k in ('name', 'local')).lower()
        flags = set()
        for x in l['fl']:
            flags.update(p.strip() for p in x.split(','))
        if re.search(r'low sodium|no salt added|without (added )?salt|unsalted|sans sel|usaltet|osaltad', name):
            flags.add('unsalted')
            flags.discard('salted')
        if re.search(r'weighed with bone|with bones?\b|avec os|med ben', name) and 'boneless' not in name:
            flags.add('with bone')
        l = dict(l, f=canon(l['f']), fl=sorted(flags & ALLOWED_FLAGS))
        out.append(l)
    target = Path(__file__).with_name('food_labels.jsonl')
    with open(target, 'w') as fh:
        for l in sorted(out, key=lambda x: x['id']):
            fh.write(json.dumps(l, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'{len(out)} labels, {len({l["f"] for l in out})} voedingsmiddelen -> {target}')


if __name__ == '__main__':
    main(sys.argv[1])
