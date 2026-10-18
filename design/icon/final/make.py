"""App-icoon: "Mx" in de ring van de Nutrient Score, in de stijl van de app en de site (donkere modus):
bijna zwart, Geist (het lettertype van de app) en de macrokleuren van het donkere thema.

Gebruik: python make.py <map>   (vereist fontTools; de letters worden een pad, zodat er geen lettertype nodig is)
"""
import math, pathlib, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

out = pathlib.Path(sys.argv[1])
FONT = pathlib.Path(__file__).resolve().parents[3] / 'assets/fonts/Geist-SemiBold.ttf'
BG = ('#1A1E22', '#0D0F11')        # surface-2 -> bg (donker thema)
TRACK, INK = '#25292E', '#ECEDEF'  # line, ink
PROTEIN, CARBS, FAT = '#8FA3FF', '#E3A956', '#E08BAA'
R, SW = 330, 56
C = 2 * math.pi * R


def letters(text='Mx', size=300, spacing=-12, base=618):
    f = TTFont(FONT); gs = f.getGlyphSet(); cmap = f.getBestCmap(); k = size / f['head'].unitsPerEm
    names = [cmap[ord(c)] for c in text]
    total = sum(gs[n].width * k for n in names) + spacing * (len(names) - 1)
    x = 512 - total / 2
    pen = SVGPathPen(gs, ntos=lambda v: f'{v:.1f}')
    for n in names:
        gs[n].draw(TransformPen(pen, (k, 0, 0, -k, x, base)))
        x += gs[n].width * k + spacing
    return pen.getCommands()


def mark():
    s = f'<circle cx="512" cy="512" r="{R}" fill="none" stroke="{TRACK}" stroke-width="{SW}"/>'
    s += f'<g transform="rotate(-90 512 512)" fill="none" stroke-width="{SW}" stroke-linecap="round">'
    for col, frac, off in [(PROTEIN, 0.30, 0.0), (CARBS, 0.30, 0.34), (FAT, 0.20, 0.68)]:
        s += f'<circle cx="512" cy="512" r="{R}" stroke="{col}" stroke-dasharray="{C*frac:.1f} {C:.1f}" stroke-dashoffset="{-C*off:.1f}"/>'
    s += f'</g><path fill="{INK}" d="{letters()}"/>'
    return s


def bg(rx):
    return (f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BG[0]}"/>'
            f'<stop offset="1" stop-color="{BG[1]}"/></linearGradient></defs><rect width="1024" height="1024" rx="{rx}" fill="url(#bg)"/>')


svg = lambda body: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">{body}</svg>\n'
scaled = lambda s: f'<g transform="translate(512 512) scale({s}) translate(-512 -512)">{mark()}</g>'
(out / 'icon.svg').write_text(svg(bg(230) + mark()))
(out / 'icon-square.svg').write_text(svg(bg(0) + mark()))
(out / 'foreground.svg').write_text(svg(scaled(0.84)))   # Android adaptief: binnen de veilige cirkel
(out / 'maskable.svg').write_text(svg(bg(0) + scaled(0.8)))  # PWA maskable
