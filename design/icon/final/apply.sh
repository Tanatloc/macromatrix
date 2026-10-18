#!/bin/bash
# Zet de iconen uit design/icon/final op alle plaatsen (Android, web, Windows, site, welkomstscherm).
set -e
cd "$(dirname "$0")/../../.."
F=design/icon/final; R=android/app/src/main/res
for d in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  IFS=: read n a b <<<"$d"
  rsvg-convert -w $a $F/icon.svg -o $R/mipmap-$n/ic_launcher.png
  rsvg-convert -w $b $F/foreground.svg -o $R/mipmap-$n/ic_launcher_foreground.png
done
rsvg-convert -w 192 $F/icon.svg -o web/icons/Icon-192.png
rsvg-convert -w 512 $F/icon.svg -o web/icons/Icon-512.png
rsvg-convert -w 192 $F/maskable.svg -o web/icons/Icon-maskable-192.png
rsvg-convert -w 512 $F/maskable.svg -o web/icons/Icon-maskable-512.png
rsvg-convert -w 64 $F/icon.svg -o web/favicon.png
T=$(mktemp -d); for s in 16 24 32 48 64 128 256; do rsvg-convert -w $s $F/icon.svg -o $T/$s.png; done
magick $T/{16,24,32,48,64,128,256}.png windows/runner/resources/app_icon.ico; rm -r $T
cp $F/icon.svg site/favicon.svg
rsvg-convert -w 512 $F/icon.svg -o assets/logo.png
python3 - <<'PY'
import re
inner = re.search(r'</defs><rect[^>]*/>(.*)</svg>', open('design/icon/final/icon.svg').read(), re.S).group(1)
mark = f'<svg viewBox="152 152 720 720" aria-hidden="true">{inner}</svg>'
for p in ['site/index.html', 'site/privacy/index.html', 'site/terms/index.html']:
    t = open(p).read()
    t = re.sub(r'(<span class="logo-mark">)<svg .*?</svg>(</span>)', lambda m: m.group(1) + mark + m.group(2), t, flags=re.S)
    open(p, 'w').write(t)
PY
