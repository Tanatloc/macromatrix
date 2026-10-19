# MacroMatrix

**Know what you eat. Better together.**

MacroMatrix is a food diary that tracks all 69 nutrients (energy, macros, vitamins, minerals, fatty acids and
essential amino acids) against EFSA reference values, with a Yuka-style scanner for additives and allergens, and
friends, levels, badges and weekly battles to keep you going. European data first, privacy first.

<p>
  <img src="site/assets/img/today.webp" width="200" alt="Today">
  <img src="site/assets/img/dashboard.webp" width="200" alt="Dashboard">
  <img src="site/assets/img/scan.webp" width="200" alt="Scan">
  <img src="site/assets/img/levels-dark.webp" width="200" alt="Profile with level and badges">
</p>

- **Website and web app:** https://app.divinenet.online
- **Android:** [GitHub releases](https://github.com/Tanatloc/macromatrix-releases/releases/latest), with automatic
  updates through [Obtainium](https://github.com/ImranR98/Obtainium) (add `https://github.com/Tanatloc/macromatrix-releases`)

## Features

- **Track:** energy, macros and 69 nutrients per day, week and month, with a Nutrient Score, balances
  (omega-6 : omega-3, potassium : salt), absorption tips and "what should I still eat?"
- **Log:** search 15,000+ basic foods and millions of branded products, scan barcodes, say what you ate, favourites,
  recipes, saved meals, supplements and "same as yesterday"
- **Scan:** product score, Nutri-Score, NOVA group, additives with EFSA-based risk levels, your allergens,
  origin (EU, US, other) and better alternatives; works offline for products you scanned before
- **Friends:** friend codes, weekly leaderboard, battles with rivalry records, levels, tiered badges and titles
- **Body:** weight, measurements, fasting, a goal weight calculator and Health Connect import on Android
- **Android extras:** home screen widget, reminders, battle notifications
- English and Dutch, light and dark theme, works offline, export to CSV

## Data sources

| Source | Licence |
|---|---|
| ANSES-CIQUAL 2025 (France) | Licence Ouverte 2.0 (Etalab) |
| Frida, DTU Food Institute (Denmark) | Free use with attribution |
| McCance and Widdowson's CoFID 2021 (UK) | Open Government Licence v3.0 |
| Livsmedelsverket (Sweden) | CC BY 4.0 |
| Matvaretabellen, Mattilsynet (Norway) | NLOD |
| USDA FoodData Central (US), incl. Branded Foods | Public domain (CC0) |
| Open Food Facts (products, additives) | ODbL |

Reference values: EFSA Dietary Reference Values; essential amino acids: WHO/FAO/UNU 2007. **Not medical advice.**

## Building

You need Flutter (stable), Java 21 and the Android SDK.

```bash
flutter pub get
flutter test
flutter run -d linux                                              # desktop
flutter build apk --release --dart-define-from-file=supabase.json # Android
tool/build_site.sh                                                # website + web app in build/site
```

`supabase.json` holds the public URL and anon key of the backend; without it the app works fully offline, without
an account. To run your own backend, create a Supabase project and apply `supabase/migrations/` (see
[supabase/README.md](supabase/README.md)). Release builds are signed with a key that is not in this repository;
without it, Gradle falls back to the debug key.

More (in Dutch): [docs/ONTWIKKELEN.md](docs/ONTWIKKELEN.md).

## Structure

- `lib/nutrition/`: nutrients, reference values, scores, badges, levels, parsing of quick logs
- `lib/data/`: built-in food database, Open Food Facts and USDA clients, local user database
- `lib/sync/`: accounts, sync and friends (Supabase)
- `lib/ui/`: screens and widgets
- `functions/api/`: Cloudflare Pages Functions (search proxy, USDA lookup, speech to text)
- `supabase/migrations/`: database schema with row level security
- `tool/`: build scripts for the food database, the site and releases

## Contributing

Bug reports and ideas are welcome as issues. For code changes, open an issue first so we can agree on the approach.
Security problems: please email privacy@divinenet.online instead of opening a public issue.

## Licence

Copyright © 2026 DivineNet.

MacroMatrix is free software: you can redistribute it and/or modify it under the terms of the
[GNU Affero General Public License v3.0](LICENSE). If you run a modified version as a service, you must make your
source code available to its users.

The name **MacroMatrix** and the MacroMatrix logo are not covered by this licence: please do not use them for
modified versions or other products without permission. Data from the sources above remains under their own licences.
