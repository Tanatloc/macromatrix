-- Inloglimiet per IP + e-mailadres (src/login_limit.js): een vast venster van 60 s per sleutel. De sleutel is een
-- SHA-256 van IP en e-mailadres, nooit die zelf; 's nachts opgeruimd (src/cron.js). Zo sluit een gedeeld netwerk
-- (gsm, school, kantoor) niet iedereen buiten als één persoon veel probeert.
CREATE TABLE login_limits (
  key TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
) WITHOUT ROWID;
