-- Inloggen (fase 2): extra velden en tabellen voor Better Auth, zoals getMigrations() ze voor deze instellingen maakt
-- (user.additionalFields en rateLimit met storage "database").

-- Welke versie van de voorwaarden je aanvaardde bij het registreren (in Supabase: raw_user_meta_data)
alter table "user" add column "termsVersion" text;
alter table "user" add column "termsAcceptedAt" text;

-- Limieten van Better Auth zelf (per IP en pad)
create table "rateLimit" ("id" text not null primary key, "key" text not null unique, "count" integer not null, "lastRequest" bigint not null);

-- Alleen op staging (TEST_OUTBOX_DOMAIN): mails naar dat testdomein komen hier terecht in plaats van in een
-- mailbox, zodat de automatische tests de code kunnen lezen. Leeg in productie.
CREATE TABLE test_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  "to" TEXT NOT NULL,
  kind TEXT NOT NULL,
  token TEXT,
  at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
