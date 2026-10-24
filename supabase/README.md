# Supabase: accounts en synchronisatie

De app werkt "lokaal eerst": alles staat in de lokale database en werkt zonder internet. Met een account gaan
wijzigingen op de achtergrond naar Supabase en van daar naar je andere toestellen (gsm, pc, browser).
Bij een conflict wint de laatste wijziging. Een account is verplicht: e-mail en wachtwoord (minstens 8 tekens, letters
en cijfers), bevestigd met een code per e-mail; wachtwoord vergeten gaat ook met een code.

## Stand van zaken

- Project `hvqbqgxpksxmavopngap` (regio eu-west-1, Ierland), gegevens in `supabase.json` (publieke anon-sleutel).
- Migraties toegepast (tabellen + opruimen van onbevestigde accounts na 30 dagen met pg_cron); Site URL
  `https://macromatrix.eu`; codes van 6 cijfers, 15 minuten geldig.
- Mails (Engels, zie `templates/`, met `{{ .Token }}`): *Confirm signup* (bevestigen), *Reset password* (nieuw wachtwoord),
  melding bij een gewijzigd wachtwoord.
- Mail via Brevo (smtp-relay.brevo.com:587, afzender `noreply@divinenet.online`, naam MacroMatrix), max. 60
  mails per uur; Engelse mails met de code in *Magic link* en *Confirm signup*. Getest: komt aan in de inbox.
- Aanbevolen in de DNS (Namecheap): `_dmarc` TXT `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com`.

## Eenmalig instellen

1. **Project maken** op [supabase.com](https://supabase.com) → *New project*
   - Regio: **Central EU (Frankfurt)** (gegevens blijven in de EU)
   - Plan: *Free* om te starten (500 MB database, 50.000 actieve gebruikers per maand).
     Opgelet: een gratis project pauzeert na een week zonder gebruik. Voor echte gebruikers: *Pro* ($25/maand).
2. **Tabellen aanmaken**: *SQL Editor* → plak de inhoud van `migrations/20261016000000_init.sql` → *Run*.
3. **Inloggen met een code**: *Authentication* → *Emails* → *Templates*. Zet in **Magic link** én in
   **Confirm signup** de code in de mail, bv.:

   ```html
   <h2>Je inlogcode</h2>
   <p>Typ deze code in de app:</p>
   <p style="font-size:28px;font-weight:600;letter-spacing:4px">{{ .Token }}</p>
   <p>Heb je dit niet gevraagd? Dan mag je deze mail negeren.</p>
   ```

   Onderwerp, bv.: `Je inlogcode voor MacroMatrix`.
4. **Adressen**: *Authentication* → *URL Configuration* → *Site URL*: het adres van de webversie
   (bv. `https://macromatrix.eu`).
5. **Eigen mailserver**: de ingebouwde mail van Supabase stuurt alleen naar leden van het project (max. 2 per
   uur) en laat geen eigen mailtekst toe. Met Brevo (EU, gratis 300 mails/dag):
   - domein `divinenet.online` toevoegen en de DNS-records bij Namecheap zetten. Er mag maar één SPF-record zijn;
     het bestaande (doorsturen van mail via Namecheap) wordt
     `v=spf1 include:spf.efwd.registrar-servers.com include:spf.brevo.com ~all`;
   - *SMTP & API* → *SMTP*: login en sleutel;
   - in Supabase: *Authentication* → *Emails* → *SMTP Settings*: `smtp-relay.brevo.com`, poort 587, afzender
     `noreply@divinenet.online`, naam `MacroMatrix`. Daarna kan stap 3 (mailtekst).
6. **Gegevens voor de app**: *Project Settings* → *API*: kopieer de *Project URL* en de *anon public* key naar
   `supabase.json` in de hoofdmap van de app:

   ```json
   { "SUPABASE_URL": "https://xxxx.supabase.co", "SUPABASE_ANON_KEY": "eyJ..." }
   ```

   De anon key mag openbaar zijn (hij zit in elke app); de beveiliging per gebruiker (Row Level Security)
   zorgt dat iedereen alleen zijn eigen gegevens ziet.

## Bouwen met account

```bash
flutter build linux --release --dart-define-from-file=supabase.json
flutter build apk --release --dart-define-from-file=supabase.json
flutter build web --release --no-web-resources-cdn --dart-define-from-file=supabase.json
```

Zonder `supabase.json` bouwt de app gewoon, zonder account (alles blijft op het toestel).

## Hoe het werkt

- Wijzigingen gaan 3 seconden na de laatste wijziging naar de server; andere toestellen krijgen een live melding
  (Supabase Realtime) en halen ze binnen enkele seconden op. Daarnaast bij het openen van de app en elke 5 minuten.
- Elke lokale tabel heeft een kolom `synced` (0 = moet nog naar de server). Een gewone wijziging zet hem op 0
  (SQLite-trigger), de synchronisatie zet hem op 1 na het versturen. Zie `lib/data/user_db.dart` en
  `lib/sync/sync_engine.dart`.
- Op de server heeft elke rij `user_id` en `server_ts` (klok van de server). Toestellen halen op wat nieuwer is
  dan hun cursor, met twee minuten overlap. Een oudere versie overschrijft nooit een nieuwere (trigger
  `sync_stamp`). Verwijderen is "zacht" (`deleted = 1`).
- Herhaalde items krijgen een vaste id (`<herhaling>:<dag>`), zodat twee toestellen geen dubbele regels maken.
- Uitloggen verstuurt eerst alles en wist dan de gegevens op dat toestel. *Account verwijderen* wist de
  gebruiker en al zijn rijen (functie `delete_account`, vereist door de Play Store).

## Vroege toegang en roadmap (supporters)

Migratie `migrations/20261031000000_early_access.sql` (na `20261026000000_pro.sql`). Zonder die migratie werkt de
app gewoon: vlaggen volgen hun standaard in de app en het scherm "What's next" zegt dat het er nog niet is.

**Een nieuwe functie achter een vlag zetten** (zie ook de uitleg bovenaan `lib/sync/features.dart`):

1. In de app: een id en een standaard in `knownFeatures` (`lib/sync/features.dart`), bv. `'training_days': false`,
   en de knop of het scherm achter `featureOn(context, 'training_days')` (`lib/ui/widgets/feature_gate.dart`).
   Zolang de server geen rij voor die id heeft, geldt de standaard.
2. Na de release, in de SQL-editor: supporters nu, iedereen over 3 weken.

   ```sql
   insert into public.features (id, title_en, title_nl, early_from, public_from)
   values ('training_days', 'Training and rest days', 'Trainings- en rustdagen', now(), now() + interval '3 weeks')
   on conflict (id) do update set early_from = excluded.early_from, public_from = excluded.public_from;
   ```

**Roadmap**: de items staan in `public.roadmap_items` (de migratie zet er zes ideeën in). Alleen supporters
stemmen, hoogstens 3 stemmen tegelijk op wat nog niet klaar is; stemmen van wie geen Pro meer heeft, blijven staan
maar tellen niet mee. Beheer in de SQL-editor:

```sql
-- Een item toevoegen
insert into public.roadmap_items (title_en, title_nl, desc_en, desc_nl, status, sort)
values ('Dark widgets', 'Donkere widgets', 'Home screen widgets in dark mode.', 'Widgets op je startscherm in donkere modus.', 'idea', 70);
-- De status wijzigen: idea, planned, building of done (op wat klaar is, kan niet meer gestemd worden)
update public.roadmap_items set status = 'building' where title_en = 'Training and rest days';
```

## Testen

- `flutter test test/sync_test.dart`: twee toestellen via een nagebootste server (toevoegen, wijzigen,
  verwijderen, conflicten, herhalingen, grote hoeveelheden).
- `flutter test test/supabase_remote_test.dart`: de verzoeken naar de REST-API van Supabase.
- `supabase/tests/rls_test.mjs`: de migratie in een echte PostgreSQL (PGlite), met de beveiliging per
  gebruiker, "laatste wijziging wint" en het verwijderen van een account.
- `test/live/supabase_live_test.dart`: tegen het echte project, met twee tijdelijke testgebruikers. Maak ze met de
  service-role-sleutel (nooit in de app of in git): `POST /auth/v1/admin/users` met `email_confirm: true`, en een
  code zonder mail met `POST /auth/v1/admin/generate_link` (`type: magiclink`, veld `email_otp`). Geef URL,
  anon-sleutel, e-mails en codes mee als omgevingsvariabelen (zie de kop van het testbestand) en verwijder de
  testgebruikers nadien.
