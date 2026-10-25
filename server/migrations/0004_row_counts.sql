-- Tellers per gebruiker en tabel voor de rijlimiet (50.000 actieve, 200.000 in totaal). De *_limit-triggers telden
-- bij elke nieuwe rij alle rijen van die gebruiker (twee keer count(*)): bij 2.000 rijen 4.000 gelezen rijen per
-- nieuwe rij, en dat groeit met elk jaar geschiedenis. Nu één rij lezen.
--
-- De teltriggers lopen altijd, ook in importmodus, zodat een import of herstel (src/backup.js) de tellers vanzelf
-- juist houdt; row_counts zelf zit niet in de back-up (afgeleide gegevens). Tabellen zonder deleted (settings, notes):
-- live = total.
CREATE TABLE row_counts (
  user_id TEXT NOT NULL,
  tbl TEXT NOT NULL,
  total INTEGER NOT NULL DEFAULT 0,
  live INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, tbl)
) WITHOUT ROWID;
CREATE TRIGGER user_row_counts AFTER DELETE ON "user" BEGIN DELETE FROM row_counts WHERE user_id = OLD.id; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'settings', count(*), count(*) FROM settings GROUP BY user_id;
DROP TRIGGER settings_limit;
CREATE TRIGGER settings_limit BEFORE INSERT ON settings
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM settings WHERE user_id = NEW.user_id AND "key" = NEW."key")
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'settings' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in settings'); END;
CREATE TRIGGER settings_count_insert AFTER INSERT ON settings
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'settings', 1, 1)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER settings_count_delete AFTER DELETE ON settings
BEGIN UPDATE row_counts SET total = total - 1, live = live - (1) WHERE user_id = OLD.user_id AND tbl = 'settings'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'foods', count(*), sum(deleted = 0) FROM foods GROUP BY user_id;
DROP TRIGGER foods_limit;
CREATE TRIGGER foods_limit BEFORE INSERT ON foods
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM foods WHERE user_id = NEW.user_id AND id = NEW.id)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'foods' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in foods'); END;
CREATE TRIGGER foods_count_insert AFTER INSERT ON foods
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'foods', 1, NEW.deleted = 0)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER foods_count_delete AFTER DELETE ON foods
BEGIN UPDATE row_counts SET total = total - 1, live = live - (OLD.deleted = 0) WHERE user_id = OLD.user_id AND tbl = 'foods'; END;
CREATE TRIGGER foods_count_deleted AFTER UPDATE OF deleted ON foods WHEN (NEW.deleted = 0) <> (OLD.deleted = 0)
BEGIN UPDATE row_counts SET live = live + (NEW.deleted = 0) - (OLD.deleted = 0) WHERE user_id = NEW.user_id AND tbl = 'foods'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'diary', count(*), sum(deleted = 0) FROM diary GROUP BY user_id;
DROP TRIGGER diary_limit;
CREATE TRIGGER diary_limit BEFORE INSERT ON diary
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM diary WHERE user_id = NEW.user_id AND id = NEW.id)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'diary' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in diary'); END;
CREATE TRIGGER diary_count_insert AFTER INSERT ON diary
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'diary', 1, NEW.deleted = 0)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER diary_count_delete AFTER DELETE ON diary
BEGIN UPDATE row_counts SET total = total - 1, live = live - (OLD.deleted = 0) WHERE user_id = OLD.user_id AND tbl = 'diary'; END;
CREATE TRIGGER diary_count_deleted AFTER UPDATE OF deleted ON diary WHEN (NEW.deleted = 0) <> (OLD.deleted = 0)
BEGIN UPDATE row_counts SET live = live + (NEW.deleted = 0) - (OLD.deleted = 0) WHERE user_id = NEW.user_id AND tbl = 'diary'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'meals', count(*), sum(deleted = 0) FROM meals GROUP BY user_id;
DROP TRIGGER meals_limit;
CREATE TRIGGER meals_limit BEFORE INSERT ON meals
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM meals WHERE user_id = NEW.user_id AND id = NEW.id)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'meals' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in meals'); END;
CREATE TRIGGER meals_count_insert AFTER INSERT ON meals
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'meals', 1, NEW.deleted = 0)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER meals_count_delete AFTER DELETE ON meals
BEGIN UPDATE row_counts SET total = total - 1, live = live - (OLD.deleted = 0) WHERE user_id = OLD.user_id AND tbl = 'meals'; END;
CREATE TRIGGER meals_count_deleted AFTER UPDATE OF deleted ON meals WHEN (NEW.deleted = 0) <> (OLD.deleted = 0)
BEGIN UPDATE row_counts SET live = live + (NEW.deleted = 0) - (OLD.deleted = 0) WHERE user_id = NEW.user_id AND tbl = 'meals'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'biometrics', count(*), sum(deleted = 0) FROM biometrics GROUP BY user_id;
DROP TRIGGER biometrics_limit;
CREATE TRIGGER biometrics_limit BEFORE INSERT ON biometrics
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM biometrics WHERE user_id = NEW.user_id AND id = NEW.id)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'biometrics' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in biometrics'); END;
CREATE TRIGGER biometrics_count_insert AFTER INSERT ON biometrics
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'biometrics', 1, NEW.deleted = 0)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER biometrics_count_delete AFTER DELETE ON biometrics
BEGIN UPDATE row_counts SET total = total - 1, live = live - (OLD.deleted = 0) WHERE user_id = OLD.user_id AND tbl = 'biometrics'; END;
CREATE TRIGGER biometrics_count_deleted AFTER UPDATE OF deleted ON biometrics WHEN (NEW.deleted = 0) <> (OLD.deleted = 0)
BEGIN UPDATE row_counts SET live = live + (NEW.deleted = 0) - (OLD.deleted = 0) WHERE user_id = NEW.user_id AND tbl = 'biometrics'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'notes', count(*), count(*) FROM notes GROUP BY user_id;
DROP TRIGGER notes_limit;
CREATE TRIGGER notes_limit BEFORE INSERT ON notes
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM notes WHERE user_id = NEW.user_id AND day = NEW.day)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'notes' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in notes'); END;
CREATE TRIGGER notes_count_insert AFTER INSERT ON notes
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'notes', 1, 1)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER notes_count_delete AFTER DELETE ON notes
BEGIN UPDATE row_counts SET total = total - 1, live = live - (1) WHERE user_id = OLD.user_id AND tbl = 'notes'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'exercise', count(*), sum(deleted = 0) FROM exercise GROUP BY user_id;
DROP TRIGGER exercise_limit;
CREATE TRIGGER exercise_limit BEFORE INSERT ON exercise
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM exercise WHERE user_id = NEW.user_id AND id = NEW.id)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'exercise' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in exercise'); END;
CREATE TRIGGER exercise_count_insert AFTER INSERT ON exercise
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'exercise', 1, NEW.deleted = 0)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER exercise_count_delete AFTER DELETE ON exercise
BEGIN UPDATE row_counts SET total = total - 1, live = live - (OLD.deleted = 0) WHERE user_id = OLD.user_id AND tbl = 'exercise'; END;
CREATE TRIGGER exercise_count_deleted AFTER UPDATE OF deleted ON exercise WHEN (NEW.deleted = 0) <> (OLD.deleted = 0)
BEGIN UPDATE row_counts SET live = live + (NEW.deleted = 0) - (OLD.deleted = 0) WHERE user_id = NEW.user_id AND tbl = 'exercise'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'fasts', count(*), sum(deleted = 0) FROM fasts GROUP BY user_id;
DROP TRIGGER fasts_limit;
CREATE TRIGGER fasts_limit BEFORE INSERT ON fasts
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM fasts WHERE user_id = NEW.user_id AND id = NEW.id)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'fasts' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in fasts'); END;
CREATE TRIGGER fasts_count_insert AFTER INSERT ON fasts
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'fasts', 1, NEW.deleted = 0)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER fasts_count_delete AFTER DELETE ON fasts
BEGIN UPDATE row_counts SET total = total - 1, live = live - (OLD.deleted = 0) WHERE user_id = OLD.user_id AND tbl = 'fasts'; END;
CREATE TRIGGER fasts_count_deleted AFTER UPDATE OF deleted ON fasts WHEN (NEW.deleted = 0) <> (OLD.deleted = 0)
BEGIN UPDATE row_counts SET live = live + (NEW.deleted = 0) - (OLD.deleted = 0) WHERE user_id = NEW.user_id AND tbl = 'fasts'; END;

INSERT INTO row_counts (user_id, tbl, total, live) SELECT user_id, 'repeats', count(*), sum(deleted = 0) FROM repeats GROUP BY user_id;
DROP TRIGGER repeats_limit;
CREATE TRIGGER repeats_limit BEFORE INSERT ON repeats
  WHEN (SELECT active FROM import_mode) = 0 AND NOT EXISTS (SELECT 1 FROM repeats WHERE user_id = NEW.user_id AND id = NEW.id)
    AND EXISTS (SELECT 1 FROM row_counts WHERE user_id = NEW.user_id AND tbl = 'repeats' AND (live >= 50000 OR total >= 200000))
BEGIN SELECT RAISE(ABORT, 'te veel rijen in repeats'); END;
CREATE TRIGGER repeats_count_insert AFTER INSERT ON repeats
BEGIN
  INSERT INTO row_counts (user_id, tbl, total, live) VALUES (NEW.user_id, 'repeats', 1, NEW.deleted = 0)
    ON CONFLICT (user_id, tbl) DO UPDATE SET total = total + 1, live = live + excluded.live;
END;
CREATE TRIGGER repeats_count_delete AFTER DELETE ON repeats
BEGIN UPDATE row_counts SET total = total - 1, live = live - (OLD.deleted = 0) WHERE user_id = OLD.user_id AND tbl = 'repeats'; END;
CREATE TRIGGER repeats_count_deleted AFTER UPDATE OF deleted ON repeats WHEN (NEW.deleted = 0) <> (OLD.deleted = 0)
BEGIN UPDATE row_counts SET live = live + (NEW.deleted = 0) - (OLD.deleted = 0) WHERE user_id = NEW.user_id AND tbl = 'repeats'; END;

