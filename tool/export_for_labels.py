"""Exporteert alle producten uit de gebouwde database met hints (LanguaL, FoodEx2, categorie) om te labelen.

Gebruik: python3 tool/export_for_labels.py assets/db/foods.db <ruwe-map> <uitvoer.jsonl>
Elke regel: {"id", "name", "local", "cat", "hints"}. De hints komen uit de LanguaL-codes van de bronnen zelf.
"""
import csv
import json
import re
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from xlsx_read import sheet_rows  # noqa: E402

# Facetten die helpen: soort (B), deel (C), verhitting (F), bereiding (G), behandeling (H), bewaring (J), verpakkingsmedium (K)
USEFUL = ('B', 'C', 'F', 'G', 'H', 'J', 'K')


def main(db_path, raw, out):
    raw = Path(raw)
    terms = {}
    text = (raw / 'langual' / 'LanguaL2017.XML').read_text(encoding='iso-8859-1')
    for m in re.finditer(r'<FTC>(\w+)</FTC>\s*<TERM[^>]*>([^<]*)</TERM>', text):
        terms[m.group(1)] = m.group(2).strip().lower()

    def describe(codes):
        out = []
        for c in codes:
            c = c.strip()
            if c[:1] in USEFUL and c in terms and 'not applicable' not in terms[c] and 'not known' not in terms[c]:
                out.append(terms[c])
        return '; '.join(dict.fromkeys(out))

    hints = {}
    # Noorwegen
    for f in json.loads((raw / 'mvt' / 'foods_en.json').read_text())['foods']:
        if f.get('langualCodes'):
            hints[f"mvt:{f['foodId']}"] = describe(f['langualCodes'])
    # Zweden (namen staan er al bij)
    for p in (raw / 'slv').glob('*.json'):
        if p.name == 'index.json':
            continue
        k = [v for v in json.loads(p.read_text()).get('klassificeringar', []) if v.get('typ') == 'LanguaL' and v.get('fasett', '')[:1] in USEFUL]
        if k:
            hints[f'slv:{p.stem}'] = '; '.join(dict.fromkeys(v['namn'].strip().lower() for v in k if 'NOT APPLICABLE' not in v['namn']))
    # Denemarken: LanguaL + FoodEx2-omschrijving
    for r in list(sheet_rows(next((raw / 'frida').glob('FCDB_*_Dataset.xlsx')), 'Food'))[1:]:
        if len(r) > 8 and r[2].strip():
            h = describe(r[8].split(','))
            fx = r[6].strip() if len(r) > 6 else ''
            hints[f'frida:{r[2].strip()}'] = '; '.join(x for x in (fx, h) if x)
    # VS: LanguaL uit SR28, gekoppeld via het NDB-nummer
    sr = {}
    for line in open(raw / 'usda_sr28' / 'LANGUAL.txt', encoding='latin-1'):
        a, b = line.strip().split('^')
        sr.setdefault(a.strip('~'), []).append(b.strip('~'))
    for d in raw.glob('FoodData_Central_*/*'):
        for name in ('sr_legacy_food.csv', 'foundation_food.csv'):
            f = d / name
            if f.exists():
                src = 'usda_sr' if 'sr_legacy' in name else 'usda_fnd'
                for row in csv.DictReader(open(f, encoding='utf-8')):
                    codes = sr.get(row['NDB_number'].zfill(5))
                    if codes:
                        hints[f"{src}:{row['fdc_id']}"] = describe(codes)

    db = sqlite3.connect(db_path)
    n = 0
    with open(out, 'w') as fh:
        for src, sid, name, local, cat in db.execute('SELECT source, source_id, name, name_local, category FROM foods ORDER BY source, source_id'):
            ref = f'{src}:{sid}'
            item = {'id': ref, 'name': name, 'cat': cat}
            if local and local != name:
                item['local'] = local
            if hints.get(ref):
                item['hints'] = hints[ref]
            fh.write(json.dumps(item, ensure_ascii=False) + '\n')
            n += 1
    print(f'{n} producten, {sum(1 for h in hints.values() if h)} met hints -> {out}')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
