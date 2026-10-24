"""
Haalt de Zweedse voedingsmiddelendatabase (Livsmedelsverket, CC BY 4.0) op via hun API.
Eén bestand per voedingsmiddel met de voedingswaarden; index.json met de namen (Engels en Zweeds).

Gebruik: python3 tool/fetch_slv.py <doelmap>
Bestanden die al bestaan worden overgeslagen, zodat je kunt hervatten.
"""
import json
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

API = 'https://dataportal.livsmedelsverket.se/livsmedel/api/v1/livsmedel'
UA = {'User-Agent': 'MacroMatrix-databuild/0.1 (https://macromatrix.eu)', 'Accept': 'application/json'}


def get(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.load(r)
        except Exception as e:  # netwerkfout of tijdelijke serverfout: even wachten en opnieuw
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def main(target):
    target = Path(target)
    target.mkdir(parents=True, exist_ok=True)
    foods = []
    for lang in (2, 1):  # 2 = Engels, 1 = Zweeds
        items = get(f'{API}?offset=0&limit=5000&sprak={lang}')['livsmedel']
        foods.append({f['nummer']: f for f in items})
    en, sv = foods
    (target / 'index.json').write_text(json.dumps({'en': en, 'sv': sv}, ensure_ascii=False))
    todo = [n for n in sorted(en) if not (target / f'{n}.json').exists()]

    def fetch(nummer):
        data = {'naringsvarden': get(f'{API}/{nummer}/naringsvarden?sprak=2')}
        (target / f'{nummer}.json').write_text(json.dumps(data, ensure_ascii=False))

    # Drie tegelijk: snel genoeg, maar niet te zwaar voor hun server
    with ThreadPoolExecutor(max_workers=3) as pool:
        for i, _ in enumerate(pool.map(fetch, todo)):
            if i % 250 == 0:
                print(f'{i}/{len(todo)}', flush=True)
    print('klaar', len(en))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
