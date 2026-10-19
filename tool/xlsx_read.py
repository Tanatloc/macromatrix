"""Excel-bestanden (.xlsx) lezen zonder extra pakketten: een .xlsx is een zip met XML per werkblad."""
import re
import zipfile
from xml.etree import ElementTree as ET

NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'


def _col(ref):
    n = 0
    for ch in re.match(r'[A-Z]+', ref).group():
        n = n * 26 + ord(ch) - 64
    return n - 1


def sheet_rows(path, sheet):
    """Alle rijen van werkblad [sheet] als lijsten met tekst (lege cellen = '')."""
    z = zipfile.ZipFile(path)
    shared = []
    if 'xl/sharedStrings.xml' in z.namelist():
        for si in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si', NS):
            shared.append(''.join(t.text or '' for t in si.iter(f'{{{NS["m"]}}}t')))
    wb = ET.fromstring(z.read('xl/workbook.xml'))
    rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
    targets = {r.get('Id'): r.get('Target') for r in rels}
    for s in wb.find('m:sheets', NS):
        if s.get('name') == sheet:
            target = targets[s.get(REL)].lstrip('/')
            target = target if target.startswith('xl/') else f'xl/{target}'
            break
    else:
        raise KeyError(f'werkblad {sheet!r} niet gevonden in {path}')
    for _, el in ET.iterparse(z.open(target)):
        if el.tag != f'{{{NS["m"]}}}row':
            continue
        row = []
        for c in el.findall('m:c', NS):
            i = _col(c.get('r'))
            while len(row) < i:
                row.append('')
            v = c.find('m:v', NS)
            if c.get('t') == 's' and v is not None:
                row.append(shared[int(v.text)])
            elif c.get('t') == 'inlineStr':
                row.append(''.join(t.text or '' for t in c.iter(f'{{{NS["m"]}}}t')))
            else:
                row.append(v.text if v is not None and v.text is not None else '')
        yield row
        el.clear()
