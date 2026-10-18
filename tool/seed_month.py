"""
Vult een bestaand dagboek met een maand realistische maaltijden (vandaag en de 30 dagen ervoor), uit de ingebouwde
CIQUAL-producten. Dagen waarop al iets staat, worden overgeslagen. De regels staan op "nog te versturen", zodat ze bij
de volgende start van de app naar het account gaan.

Gebruik (met de app gesloten, en ingelogd in die app):
    python3 tool/seed_month.py ~/.local/share/online.divinenet.macromatrix/user.db assets/db/foods.db [dagen]
"""
import random
import sqlite3
import sys
import time
import uuid
from datetime import date, timedelta

# (ciqual-code, gram, schommeling)
BREAKFASTS = [
    [(32140, 60, .2), (19042, 250, .2), (13005, 120, .2), (13028, 80, .3)],
    [(7110, 80, .2), (22010, 100, .3), (20047, 100, .3), (12115, 25, .3)],
    [(32140, 50, .2), (13034, 150, .2), (13014, 120, .3), (19042, 200, .2)],
]
LUNCHES = [
    [(7110, 90, .2), (36018, 100, .2), (20210, 100, .3), (20047, 80, .3), (13004, 60, .3)],
    [(20587, 200, .2), (20009, 100, .3), (17270, 10, .3), (7110, 60, .3)],
    [(7110, 90, .2), (26123, 90, .2), (20047, 100, .3), (13191, 150, .2)],
]
DINNERS = [
    [(26036, 150, .15), (4003, 250, .2), (20303, 150, .2), (17270, 10, .3)],
    [(6251, 125, .15), (4003, 200, .2), (20009, 150, .2), (17270, 10, .3)],
    [(25997, 160, .15), (4003, 250, .2), (20303, 200, .2), (17270, 10, .3)],
    [(36018, 150, .15), (20587, 150, .2), (20019, 100, .3), (17270, 10, .3)],
    [(26051, 140, .15), (4003, 220, .2), (20303, 150, .2)],
]
SNACKS = [
    [(13191, 160, .2), (31074, 20, .3)],
    [(13005, 120, .2), (13021, 100, .3)],
    [(13034, 150, .2), (12115, 30, .3)],
    [(13014, 150, .3), (31074, 15, .3)],
]
TIMES = ['07:{:02d}', '12:{:02d}', '18:{:02d}', '15:{:02d}']


def main(user_db, foods_db, days):
    foods = sqlite3.connect(foods_db)
    user = sqlite3.connect(user_db)
    rnd = random.Random()
    now = int(time.time() * 1000)
    added = skipped = 0
    for d in range(days, -1, -1):
        day = (date.today() - timedelta(days=d)).isoformat()
        if user.execute('SELECT 1 FROM diary WHERE day = ? AND deleted = 0 LIMIT 1', (day,)).fetchone():
            skipped += 1
            continue
        for meal, options in enumerate([BREAKFASTS, LUNCHES, DINNERS, SNACKS]):
            if meal == 3 and rnd.random() < .25:
                continue
            t = TIMES[meal].format(rnd.randint(0, 59))
            if meal == 0:
                t = '0' + str(rnd.randint(6, 8)) + t[2:]
            for i, (code, grams, spread) in enumerate(rnd.choice(options)):
                row = foods.execute("SELECT name, nutrients FROM foods WHERE source = 'ciqual' AND source_id = ?", (str(code),)).fetchone()
                if row is None:
                    continue
                g = round(grams * 1.3 * rnd.uniform(1 - spread, 1 + spread))
                user.execute(
                    'INSERT INTO diary (id, day, meal, food_ref, name, brand, grams, portion_label, quantity, nutrients, created_at, updated_at, time) '
                    'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
                    (str(uuid.uuid4()), day, meal, f'ciqual:{code}', row[0], None, g, None, g, row[1], now + i, now + i, t),
                )
        added += 1
    user.commit()
    print(f'{added} dagen ingevuld, {skipped} overgeslagen (stond al iets)')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 30)
