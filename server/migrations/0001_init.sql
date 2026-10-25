-- MacroMatrix op D1: alle tabellen uit Supabase (public), plus de kerntabellen van Better Auth.
-- Gegenereerd uit het live schema van 25-10-2026 (26 migraties) en daarna nagekeken.
--
-- Omzetting: uuid/date/timestamptz -> TEXT (tijd als ISO-8601 in UTC, 'YYYY-MM-DDTHH:MM:SS.sssZ', zoals Better
-- Auth); boolean -> INTEGER 0/1; double precision -> REAL. RLS bestaat niet in D1: elke query in de Worker filtert
-- zelf op de ingelogde gebruiker.
--
-- Gesynchroniseerde tabellen: server_ts (tijd) is server_seq (oplopend getal uit sync_seq) geworden. De triggers
-- doen wat sync_stamp en limit_rows in Supabase deden: een oudere versie negeren, de klok begrenzen op nu + 5 min,
-- user_id nooit wijzigen, hoogstens 50.000 actieve / 200.000 rijen per gebruiker en tabel.

-- Better Auth (better-auth 1.7.7, emailAndPassword + emailOTP + bearer), zoals getMigrations() ze voor SQLite maakt
create table "user" ("id" text not null primary key, "name" text not null, "email" text not null unique, "emailVerified" integer not null, "image" text, "createdAt" date not null, "updatedAt" date not null);
create table "session" ("id" text not null primary key, "expiresAt" date not null, "token" text not null unique, "createdAt" date not null, "updatedAt" date not null, "ipAddress" text, "userAgent" text, "userId" text not null references "user" ("id") on delete cascade);
create table "account" ("id" text not null primary key, "accountId" text not null, "providerId" text not null, "userId" text not null references "user" ("id") on delete cascade, "accessToken" text, "refreshToken" text, "idToken" text, "accessTokenExpiresAt" date, "refreshTokenExpiresAt" date, "scope" text, "password" text, "createdAt" date not null, "updatedAt" date not null);
create table "verification" ("id" text not null primary key, "identifier" text not null, "value" text not null, "expiresAt" date not null, "createdAt" date not null, "updatedAt" date not null);
create index "session_userId_idx" on "session" ("userId");
create index "account_userId_idx" on "account" ("userId");
create index "verification_identifier_idx" on "verification" ("identifier");

-- Teller voor server_seq (één rij)
CREATE TABLE sync_seq (id INTEGER PRIMARY KEY CHECK (id = 1), seq INTEGER NOT NULL);
INSERT INTO sync_seq (id, seq) VALUES (1, 0);

-- Tijdens een import (tool/supabase_to_d1.mjs) staan de synctriggers uit: dan komen server_seq en updated_at
-- ongewijzigd uit Supabase. De import zet dit aan en uit binnen dezelfde batch (= transactie).
CREATE TABLE import_mode (id INTEGER PRIMARY KEY CHECK (id = 1), active INTEGER NOT NULL CHECK (active IN (0, 1)));
INSERT INTO import_mode (id, active) VALUES (1, 0);


CREATE TABLE challenges (
  id TEXT NOT NULL,
  owner TEXT NOT NULL,
  template TEXT NOT NULL,
  title TEXT,
  nutrient TEXT NOT NULL,
  rule TEXT NOT NULL,
  amount REAL NOT NULL DEFAULT 0,
  days INTEGER NOT NULL,
  need INTEGER NOT NULL,
  start_day TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (id),
  FOREIGN KEY (owner) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((amount >= 0) AND (amount <= 100000))),
  CHECK (((days >= 1) AND (days <= 90))),
  CHECK (((length(template) >= 1) AND (length(template) <= 40))),
  CHECK (((title IS NULL) OR (length(title) <= 60))),
  CHECK (((length(nutrient) >= 1) AND (length(nutrient) <= 40))),
  CHECK ((rule IN ('min', 'max', 'goal'))),
  CHECK (((need >= 1) AND (need <= 90))),
  CHECK ((need <= days))
);

CREATE TABLE roadmap_items (
  id TEXT NOT NULL,
  title_en TEXT NOT NULL,
  title_nl TEXT NOT NULL,
  desc_en TEXT NOT NULL DEFAULT '',
  desc_nl TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'idea',
  sort INTEGER NOT NULL DEFAULT 100,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (id),
  CHECK (((length(title_nl) >= 1) AND (length(title_nl) <= 120))),
  CHECK ((length(desc_nl) <= 600)),
  CHECK ((status IN ('idea', 'planned', 'building', 'early', 'done'))),
  CHECK ((length(desc_en) <= 600)),
  CHECK (((length(title_en) >= 1) AND (length(title_en) <= 120)))
);

CREATE TABLE features (
  id TEXT NOT NULL,
  title_en TEXT NOT NULL,
  title_nl TEXT NOT NULL,
  early_from TEXT,
  public_from TEXT,
  PRIMARY KEY (id),
  CHECK (((length(title_nl) >= 1) AND (length(title_nl) <= 120))),
  CHECK ((length(id) BETWEEN 1 AND 60 AND id NOT GLOB '*[^a-z0-9_]*')),
  CHECK (((length(title_en) >= 1) AND (length(title_en) <= 120)))
);

CREATE TABLE ai_reports (
  id TEXT NOT NULL,
  reporter TEXT NOT NULL,
  kind TEXT NOT NULL,
  text TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (id),
  FOREIGN KEY (reporter) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(text) >= 1) AND (length(text) <= 4000))),
  CHECK ((kind IN ('coach', 'photo', 'label', 'recipe', 'voice', 'other'))),
  CHECK (((note IS NULL) OR (length(note) <= 1000)))
);

CREATE TABLE ai_usage (
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, kind, day),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK ((kind IN ('label', 'recipe', 'coach', 'voice', 'off'))),
  CHECK (((count >= 0) AND (count <= 10000)))
);

CREATE TABLE battles (
  id TEXT NOT NULL,
  week TEXT NOT NULL,
  challenger TEXT NOT NULL,
  opponent TEXT NOT NULL,
  accepted INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (id),
  FOREIGN KEY (opponent) REFERENCES "user"(id) ON DELETE CASCADE,
  FOREIGN KEY (challenger) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK ((strftime('%w', week) = '1')),
  CHECK ((challenger <> opponent)),
  CHECK (accepted IN (0, 1))
);

CREATE TABLE biometrics (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  day TEXT NOT NULL,
  "time" TEXT,
  type TEXT NOT NULL,
  value REAL NOT NULL,
  value2 REAL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(id) <= 100) AND (length(day) <= 20) AND (length(type) <= 120) AND (COALESCE(length("time"), 0) <= 10)))
);

CREATE TABLE challenge_days (
  challenge_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  day TEXT NOT NULL,
  met INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (challenge_id, user_id, day),
  FOREIGN KEY (challenge_id) REFERENCES challenges(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (met IN (0, 1))
);

CREATE TABLE challenge_members (
  challenge_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  invited_by TEXT,
  accepted INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (challenge_id, user_id),
  FOREIGN KEY (challenge_id) REFERENCES challenges(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  FOREIGN KEY (invited_by) REFERENCES "user"(id) ON DELETE SET NULL,
  CHECK (accepted IN (0, 1))
);

CREATE TABLE diary (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  day TEXT NOT NULL,
  meal INTEGER NOT NULL,
  food_ref TEXT NOT NULL,
  name TEXT NOT NULL,
  brand TEXT,
  grams REAL NOT NULL,
  portion_label TEXT,
  quantity REAL NOT NULL,
  nutrients TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  "time" TEXT,
  repeat_id TEXT,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(id) <= 100) AND (length(day) <= 20) AND (length(food_ref) <= 200) AND (length(name) <= 500) AND (COALESCE(length(brand), 0) <= 300) AND (length(nutrients) <= 30000) AND (COALESCE(length(portion_label), 0) <= 200) AND (COALESCE(length(repeat_id), 0) <= 100) AND (COALESCE(length("time"), 0) <= 10)))
);

CREATE TABLE exercise (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  day TEXT NOT NULL,
  name TEXT NOT NULL,
  minutes REAL,
  kcal REAL NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(id) <= 100) AND (length(day) <= 20) AND (length(name) <= 300)))
);

CREATE TABLE fasts (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  "start" INTEGER NOT NULL,
  "end" INTEGER,
  goal_hours REAL NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK ((length(id) <= 100))
);

CREATE TABLE foods (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  source TEXT NOT NULL,
  name TEXT NOT NULL,
  brand TEXT,
  barcode TEXT,
  nutrients TEXT NOT NULL,
  portions TEXT,
  extra TEXT,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(id) <= 200) AND (length(name) <= 500) AND (COALESCE(length(brand), 0) <= 300) AND (COALESCE(length(barcode), 0) <= 64) AND (COALESCE(length(source), 0) <= 40) AND (length(nutrients) <= 30000) AND (COALESCE(length(portions), 0) <= 30000) AND (COALESCE(length(extra), 0) <= 300000)))
);

CREATE TABLE friend_profiles (
  user_id TEXT NOT NULL,
  code TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  avatar TEXT,
  level INTEGER NOT NULL DEFAULT 1,
  title TEXT,
  badges TEXT,
  PRIMARY KEY (user_id),
  UNIQUE (code),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((badges IS NULL) OR (length(badges) <= 2000))),
  CHECK (((avatar IS NULL) OR (length(avatar) <= 100000))),
  CHECK (((level >= 1) AND (level <= 100000))),
  CHECK ((length(name) <= 40)),
  CHECK (((title IS NULL) OR (length(title) <= 40)))
);

CREATE TABLE friendships (
  requester TEXT NOT NULL,
  addressee TEXT NOT NULL,
  accepted INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (requester, addressee),
  FOREIGN KEY (addressee) REFERENCES "user"(id) ON DELETE CASCADE,
  FOREIGN KEY (requester) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK ((requester <> addressee)),
  CHECK (accepted IN (0, 1))
);

CREATE TABLE meals (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  items TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL DEFAULT 0,
  meal INTEGER,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((meal IS NULL) OR ((meal >= 0) AND (meal <= 10)))),
  CHECK (((length(id) <= 100) AND (length(name) <= 300) AND (length(items) <= 300000)))
);

CREATE TABLE notes (
  user_id TEXT NOT NULL,
  day TEXT NOT NULL,
  text TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(day) <= 20) AND (length(text) <= 20000)))
);

CREATE TABLE notify_tokens (
  token TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (token),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE
);

CREATE TABLE photo_usage (
  user_id TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((count >= 0) AND (count <= 10000)))
);

CREATE TABLE play_purchases (
  purchase_token TEXT NOT NULL,
  user_id TEXT NOT NULL,
  product TEXT NOT NULL,
  linked_purchase_token TEXT,
  expiry TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (purchase_token),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(purchase_token) >= 10) AND (length(purchase_token) <= 4096))),
  CHECK ((product IN ('pro_monthly', 'pro_yearly')))
);

CREATE TABLE pro_status (
  user_id TEXT NOT NULL,
  until TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  show_badge INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  frame TEXT,
  base_until TEXT,
  base_source TEXT,
  PRIMARY KEY (user_id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((base_source IS NULL) OR ((length(base_source) >= 1) AND (length(base_source) <= 40)))),
  CHECK (((length(source) >= 1) AND (length(source) <= 40))),
  CHECK (((frame IS NULL) OR (frame IN ('glow', 'orbit', 'sparkle', 'laurel', 'ripple', 'spin', 'sunburst', 'crown', 'wings', 'blades', 'royal')))),
  CHECK (show_badge IN (0, 1))
);

CREATE TABLE repeats (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  meal INTEGER NOT NULL,
  item TEXT NOT NULL,
  weekdays INTEGER NOT NULL,
  start_day TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(id) <= 100) AND (length(item) <= 30000) AND (COALESCE(length(start_day), 0) <= 20)))
);

CREATE TABLE roadmap_votes (
  item_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (item_id, user_id),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  FOREIGN KEY (item_id) REFERENCES roadmap_items(id) ON DELETE CASCADE
);

CREATE TABLE settings (
  user_id TEXT NOT NULL,
  "key" TEXT NOT NULL,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  server_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, key),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(key) <= 100) AND (length(value) <= 300000)))
);

CREATE TABLE signup_ips (
  ip_hash TEXT NOT NULL,
  at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE user_blocks (
  blocker TEXT NOT NULL,
  blocked TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (blocker, blocked),
  FOREIGN KEY (blocker) REFERENCES "user"(id) ON DELETE CASCADE,
  FOREIGN KEY (blocked) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK ((blocker <> blocked))
);

CREATE TABLE user_reports (
  id TEXT NOT NULL,
  reporter TEXT NOT NULL,
  reported TEXT NOT NULL,
  reason TEXT NOT NULL,
  note TEXT,
  reported_name TEXT,
  reported_avatar TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  challenge_id TEXT,
  challenge_title TEXT,
  PRIMARY KEY (id),
  FOREIGN KEY (reporter) REFERENCES "user"(id) ON DELETE CASCADE,
  FOREIGN KEY (reported) REFERENCES "user"(id) ON DELETE CASCADE,
  FOREIGN KEY (challenge_id) REFERENCES challenges(id) ON DELETE SET NULL,
  CHECK (((note IS NULL) OR (length(note) <= 500))),
  CHECK (((reported_name IS NULL) OR (length(reported_name) <= 40))),
  CHECK (((reported_avatar IS NULL) OR (length(reported_avatar) <= 100000))),
  CHECK ((reporter <> reported)),
  CHECK ((reason IN ('spam', 'harassment', 'inappropriate', 'other', 'challenge_title'))),
  CHECK (((challenge_title IS NULL) OR (length(challenge_title) <= 60)))
);

CREATE TABLE weekly_scores (
  user_id TEXT NOT NULL,
  week TEXT NOT NULL,
  score INTEGER NOT NULL,
  days INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  points INTEGER,
  mid_points INTEGER,
  PRIMARY KEY (user_id, week),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((mid_points IS NULL) OR ((mid_points >= 0) AND (mid_points <= 1000)))),
  CHECK (((days >= 1) AND (days <= 7))),
  CHECK (((score >= 0) AND (score <= 100))),
  CHECK ((strftime('%w', week) = '1')),
  CHECK (((points IS NULL) OR ((points >= 0) AND (points <= 1000)))),
  CHECK ((((points IS NULL) OR (points <= 700)) AND ((mid_points IS NULL) OR (mid_points <= 700))))
);


-- Indexen

CREATE INDEX challenges_owner ON challenges (owner);

CREATE INDEX challenge_members_user ON challenge_members (user_id);

CREATE INDEX ai_reports_reporter ON ai_reports (reporter, created_at);

CREATE INDEX meals_changes ON meals (user_id, server_seq);

CREATE INDEX settings_changes ON settings (user_id, server_seq);

CREATE INDEX foods_changes ON foods (user_id, server_seq);

CREATE INDEX diary_changes ON diary (user_id, server_seq);

CREATE INDEX notes_changes ON notes (user_id, server_seq);

CREATE INDEX biometrics_changes ON biometrics (user_id, server_seq);

CREATE INDEX exercise_changes ON exercise (user_id, server_seq);

CREATE INDEX fasts_changes ON fasts (user_id, server_seq);

CREATE INDEX repeats_changes ON repeats (user_id, server_seq);

CREATE INDEX user_blocks_blocked ON user_blocks (blocked);

CREATE INDEX user_reports_reporter ON user_reports (reporter, created_at);

CREATE INDEX user_reports_reported ON user_reports (reported);

CREATE INDEX friendships_addressee ON friendships (addressee);

CREATE UNIQUE INDEX battles_pair_week ON battles (week, min(challenger, opponent), max(challenger, opponent));

CREATE INDEX battles_challenger ON battles (challenger);

CREATE INDEX battles_opponent ON battles (opponent);

CREATE INDEX roadmap_votes_user ON roadmap_votes (user_id);

CREATE INDEX play_purchases_user ON play_purchases (user_id, expiry DESC);

CREATE INDEX signup_ips_hash_at ON signup_ips (ip_hash, at);


-- Synctriggers (vervangen sync_stamp en limit_rows)

CREATE TRIGGER settings_older BEFORE UPDATE ON settings
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER settings_owner BEFORE UPDATE OF user_id ON settings WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER settings_limit BEFORE INSERT ON settings
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM settings WHERE user_id = NEW.user_id AND "key" = NEW."key")
    AND ((SELECT count(*) FROM settings WHERE user_id = NEW.user_id) >= 50000 OR (SELECT count(*) FROM settings WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in settings'); END;
CREATE TRIGGER settings_stamp_insert AFTER INSERT ON settings WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE settings SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND "key" = NEW."key";
END;
CREATE TRIGGER settings_stamp_update AFTER UPDATE ON settings WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE settings SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND "key" = NEW."key";
END;

CREATE TRIGGER foods_older BEFORE UPDATE ON foods
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER foods_owner BEFORE UPDATE OF user_id ON foods WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER foods_limit BEFORE INSERT ON foods
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM foods WHERE user_id = NEW.user_id AND id = NEW.id)
    AND ((SELECT count(*) FROM foods WHERE user_id = NEW.user_id AND deleted = 0) >= 50000 OR (SELECT count(*) FROM foods WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in foods'); END;
CREATE TRIGGER foods_stamp_insert AFTER INSERT ON foods WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE foods SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
CREATE TRIGGER foods_stamp_update AFTER UPDATE ON foods WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE foods SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;

CREATE TRIGGER diary_older BEFORE UPDATE ON diary
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER diary_owner BEFORE UPDATE OF user_id ON diary WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER diary_limit BEFORE INSERT ON diary
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM diary WHERE user_id = NEW.user_id AND id = NEW.id)
    AND ((SELECT count(*) FROM diary WHERE user_id = NEW.user_id AND deleted = 0) >= 50000 OR (SELECT count(*) FROM diary WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in diary'); END;
CREATE TRIGGER diary_stamp_insert AFTER INSERT ON diary WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE diary SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
CREATE TRIGGER diary_stamp_update AFTER UPDATE ON diary WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE diary SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;

CREATE TRIGGER meals_older BEFORE UPDATE ON meals
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER meals_owner BEFORE UPDATE OF user_id ON meals WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER meals_limit BEFORE INSERT ON meals
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM meals WHERE user_id = NEW.user_id AND id = NEW.id)
    AND ((SELECT count(*) FROM meals WHERE user_id = NEW.user_id AND deleted = 0) >= 50000 OR (SELECT count(*) FROM meals WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in meals'); END;
CREATE TRIGGER meals_stamp_insert AFTER INSERT ON meals WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE meals SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
CREATE TRIGGER meals_stamp_update AFTER UPDATE ON meals WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE meals SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;

CREATE TRIGGER biometrics_older BEFORE UPDATE ON biometrics
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER biometrics_owner BEFORE UPDATE OF user_id ON biometrics WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER biometrics_limit BEFORE INSERT ON biometrics
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM biometrics WHERE user_id = NEW.user_id AND id = NEW.id)
    AND ((SELECT count(*) FROM biometrics WHERE user_id = NEW.user_id AND deleted = 0) >= 50000 OR (SELECT count(*) FROM biometrics WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in biometrics'); END;
CREATE TRIGGER biometrics_stamp_insert AFTER INSERT ON biometrics WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE biometrics SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
CREATE TRIGGER biometrics_stamp_update AFTER UPDATE ON biometrics WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE biometrics SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;

CREATE TRIGGER notes_older BEFORE UPDATE ON notes
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER notes_owner BEFORE UPDATE OF user_id ON notes WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER notes_limit BEFORE INSERT ON notes
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM notes WHERE user_id = NEW.user_id AND day = NEW.day)
    AND ((SELECT count(*) FROM notes WHERE user_id = NEW.user_id) >= 50000 OR (SELECT count(*) FROM notes WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in notes'); END;
CREATE TRIGGER notes_stamp_insert AFTER INSERT ON notes WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE notes SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND day = NEW.day;
END;
CREATE TRIGGER notes_stamp_update AFTER UPDATE ON notes WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE notes SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND day = NEW.day;
END;

CREATE TRIGGER exercise_older BEFORE UPDATE ON exercise
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER exercise_owner BEFORE UPDATE OF user_id ON exercise WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER exercise_limit BEFORE INSERT ON exercise
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM exercise WHERE user_id = NEW.user_id AND id = NEW.id)
    AND ((SELECT count(*) FROM exercise WHERE user_id = NEW.user_id AND deleted = 0) >= 50000 OR (SELECT count(*) FROM exercise WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in exercise'); END;
CREATE TRIGGER exercise_stamp_insert AFTER INSERT ON exercise WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE exercise SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
CREATE TRIGGER exercise_stamp_update AFTER UPDATE ON exercise WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE exercise SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;

CREATE TRIGGER fasts_older BEFORE UPDATE ON fasts
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER fasts_owner BEFORE UPDATE OF user_id ON fasts WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER fasts_limit BEFORE INSERT ON fasts
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM fasts WHERE user_id = NEW.user_id AND id = NEW.id)
    AND ((SELECT count(*) FROM fasts WHERE user_id = NEW.user_id AND deleted = 0) >= 50000 OR (SELECT count(*) FROM fasts WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in fasts'); END;
CREATE TRIGGER fasts_stamp_insert AFTER INSERT ON fasts WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE fasts SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
CREATE TRIGGER fasts_stamp_update AFTER UPDATE ON fasts WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE fasts SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;

CREATE TRIGGER repeats_older BEFORE UPDATE ON repeats
  WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0 AND min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000) < OLD.updated_at
BEGIN SELECT RAISE(IGNORE); END;
CREATE TRIGGER repeats_owner BEFORE UPDATE OF user_id ON repeats WHEN NEW.user_id <> OLD.user_id
BEGIN SELECT RAISE(ABORT, 'user_id kan niet wijzigen'); END;
CREATE TRIGGER repeats_limit BEFORE INSERT ON repeats
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM repeats WHERE user_id = NEW.user_id AND id = NEW.id)
    AND ((SELECT count(*) FROM repeats WHERE user_id = NEW.user_id AND deleted = 0) >= 50000 OR (SELECT count(*) FROM repeats WHERE user_id = NEW.user_id) >= 200000)
BEGIN SELECT RAISE(ABORT, 'te veel rijen in repeats'); END;
CREATE TRIGGER repeats_stamp_insert AFTER INSERT ON repeats WHEN (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE repeats SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
CREATE TRIGGER repeats_stamp_update AFTER UPDATE ON repeats WHEN NEW.server_seq = OLD.server_seq AND (SELECT active FROM import_mode) = 0
BEGIN
  UPDATE sync_seq SET seq = seq + 1;
  UPDATE repeats SET server_seq = (SELECT seq FROM sync_seq), updated_at = min(NEW.updated_at, CAST(unixepoch('subsec') * 1000 AS INTEGER) + 300000)
    WHERE user_id = NEW.user_id AND id = NEW.id;
END;
