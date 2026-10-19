"""Vergelijkt gemeten waarden van hetzelfde voedingsmiddel (zelfde label) over alle databanken heen.

Gebruik: python3 tool/consensus.py assets/db/foods.db uitvoer.csv
Een waarde is verdacht als ze meer dan 3× afwijkt van de mediaan van de andere metingen van hetzelfde voedingsmiddel
(minstens 2 andere metingen, uit minstens 2 databanken in totaal). Geschatte waarden (≈) tellen niet mee.
"""
import csv
import json
import math
import sqlite3
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from audit_foods import FLOOR  # noqa: E402
from build_foods import C_CLASS, SIG_FLAGS, load_labels  # noqa: E402

KEYS = list(FLOOR) + ['protein', 'fat', 'carbs', 'fiber', 'water']
FLOOR_MACRO = {'protein': 0.5, 'fat': 0.5, 'carbs': 1, 'fiber': 0.5, 'water': 2}


def main(db_path, out):
    labels = load_labels()
    db = sqlite3.connect(db_path)
    groups = defaultdict(list)
    for src, sid, name, nut, est in db.execute('SELECT source, source_id, name, nutrients, estimated FROM foods'):
        ref = f'{src}:{sid}'
        l = labels.get(ref)
        if not l:
            continue
        e = json.loads(est)
        n = {k: v for k, v in json.loads(nut).items() if k not in e}
        key = (l['f'], l['p'], l['d'], C_CLASS.get(l['c'], l['c']), frozenset(set(l['fl']) & SIG_FLAGS))
        groups[key].append((ref, src[:4], name, n))
    rows = []
    for key, items in groups.items():
        if len(items) < 3 or len({s for _, s, _, _ in items}) < 2:
            continue
        for k in KEYS:
            vals = [(n[k], ref, name) for ref, _, name, n in items if k in n]
            if len(vals) < 3:
                continue
            floor = FLOOR.get(k, FLOOR_MACRO.get(k, 0.1))
            for v, ref, name in vals:
                others = [x for x, r, _ in vals if r != ref]
                med = statistics.median(others)
                ratio = max(v, floor) / max(med, floor)
                if ratio > 3 or ratio < 1 / 3:
                    rows.append({'ref': ref, 'name': name, 'food': ' / '.join(str(x) for x in key[:2]) + f" ({key[3]})",
                                 'nutrient': k, 'value': v, 'median_others': round(med, 4), 'ratio': round(ratio, 3),
                                 'others': ' '.join(f'{x:.3g}' for x in sorted(others)), 'score': abs(math.log(ratio))})
    rows.sort(key=lambda x: -x['score'])
    with open(out, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=['ref', 'name', 'food', 'nutrient', 'value', 'median_others', 'ratio', 'others', 'score'])
        w.writeheader()
        w.writerows(rows)
    print(f'{len(rows)} verdachte waarden in {len(groups)} voedingsmiddelen -> {out}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
