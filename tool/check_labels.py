"""Controleert gelabelde pakketten op verschuivingen: past het voedingsmiddel ("f") bij de productnaam?

Gebruik: python3 tool/check_labels.py <labels-map>   (met in/ en out/)
Toont per pakket het aandeel labels waarvan geen woord in de naam, lokale naam of hints voorkomt, en reeksen van
4+ zulke labels na elkaar (een teken dat de labels een regel verschoven zijn).
"""
import json
import re
import sys
from pathlib import Path


def stem(w):
    return re.sub(r'(ies|es|s)$', '', w)


def fits(label, item):
    text = ' '.join(str(item.get(k, '')) for k in ('name', 'local', 'hints')).lower()
    words = {stem(w) for w in re.findall(r'[a-zà-ÿ]+', text)}
    fw = [stem(w) for w in re.findall(r'[a-zà-ÿ]+', label['f'].lower()) if len(w) >= 3]
    return not fw or any(w in words or any(x.startswith(w[:5]) for x in words if len(w) >= 5) for w in fw)


def main(d):
    d = Path(d)
    for f in sorted((d / 'out').glob('batch_*.jsonl')):
        inp = [json.loads(l) for l in open(d / 'in' / f.name)]
        out = [json.loads(l) for l in open(f)]
        if [i['id'] for i in inp[:len(out)]] != [o['id'] for o in out]:
            print(f'{f.name}: ids wijken af!')
            continue
        bad = [not fits(o, i) for o, i in zip(out, inp)]
        runs, cur = [], 0
        for k, b in enumerate(bad + [False]):
            if b:
                cur += 1
            else:
                if cur >= 4:
                    runs.append((k - cur, cur))
                cur = 0
        flag = ' <-- reeks' if runs else ''
        print(f'{f.name}: {len(out)}/{len(inp)} regels, {sum(bad)} past niet ({sum(bad) / max(1, len(out)):.0%}){flag} {runs[:3]}')


if __name__ == '__main__':
    main(sys.argv[1])
