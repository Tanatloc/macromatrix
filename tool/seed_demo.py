"""
Vult een user.db met voorbeelddagen, voor screenshots (bv. voor de Play Store).

Gebruik (met de app gesloten, en na één keer opstarten zodat de tabellen bestaan):
    python3 tool/seed_demo.py <pad/naar/user.db> <pad/naar/foods.db> [aantal dagen tot en met vandaag]

Per dag dezelfde maaltijden met wat variatie in de hoeveelheden, een dalend gewicht en af en toe beweging.
"""
import json
import sqlite3
import sys
import random
import time
import uuid
from datetime import date, timedelta

# (maaltijd, zoekterm in de USDA-naam, gram)
DAY = [
    (0, 'Oats, whole grain, rolled, old fashioned', 60),
    (0, 'Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D', 250),
    (0, 'Bananas, ripe and slightly ripe, raw', 120),
    (0, 'Blueberries, raw', 80),
    (1, 'Bread, whole-wheat, commercially prepared, toasted', 70),
    (1, 'Egg, whole, cooked, hard-boiled', 100),
    (1, 'Spinach, raw', 60),
    (1, 'Tomatoes, red, ripe, raw, year round average', 120),
    (2, 'Fish, salmon, Atlantic, farmed, cooked, dry heat', 150),
    (2, 'Potatoes, boiled, cooked in skin, flesh, without salt', 250),
    (2, 'Broccoli, cooked, boiled, drained, without salt', 150),
    (2, 'Oil, olive, salad or cooking', 10),
    (3, 'Nuts, almonds, whole, raw', 30),
    (3, 'Yogurt, Greek, plain, nonfat', 170),
]


def main(user_db, foods_db, days):
    foods = sqlite3.connect(foods_db)
    user = sqlite3.connect(user_db)
    now = int(time.time() * 1000)
    rnd = random.Random(42)
    rows = []
    for meal, name, grams in DAY:
        row = foods.execute('SELECT source, source_id, name, nutrients FROM foods WHERE name = ?', (name,)).fetchone()
        if row is None:
            row = foods.execute('SELECT source, source_id, name, nutrients FROM foods WHERE name LIKE ? ORDER BY length(name) LIMIT 1',
                                (name.split(',')[0] + '%',)).fetchone()
        rows.append((meal, grams, row))
    today = date.today()
    weight = 79.5
    for d in range(days - 1, -1, -1):
        day = (today - timedelta(days=d)).isoformat()
        for i, (meal, grams, (source, sid, fname, nutrients)) in enumerate(rows):
            if rnd.random() < 0.15:
                continue  # niet elke dag precies hetzelfde
            g = round(grams * rnd.uniform(0.7, 1.3))
            user.execute(
                'INSERT INTO diary (id, day, meal, food_ref, name, brand, grams, portion_label, quantity, nutrients, created_at, updated_at) '
                'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
                (str(uuid.uuid4()), day, meal, f'{source}:{sid}', fname, None, g, None, g, nutrients, now + i, now + i),
            )
        weight -= rnd.uniform(-0.1, 0.25)
        user.execute('INSERT INTO biometrics (id, day, type, value, updated_at) VALUES (?,?,?,?,?)',
                     (str(uuid.uuid4()), day, 'weight', round(weight, 1), now))
        if d % 2 == 0:
            user.execute('INSERT INTO exercise (id, day, name, minutes, kcal, updated_at) VALUES (?,?,?,?,?,?)',
                         (str(uuid.uuid4()), day, 'Hardlopen (10 km/u)', 40, round(9.8 * weight * 40 / 60), now))
    print(f'{days} dagen ingevuld tot en met {today}')
    profile = {'sex': 'male', 'birthYear': 1998, 'weightKg': 78, 'heightCm': 182, 'activity': 'moderate', 'goal': 'maintain',
               'proteinPct': 25, 'carbsPct': 45, 'fatPct': 30, 'energyOverride': None}
    user.execute('INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?,?,?)', ('profile', json.dumps(profile), now))
    user.commit()


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1)
