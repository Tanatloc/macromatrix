-- Duo (25-10-2026): wie een Duo-abonnement koopt (duo_monthly of duo_yearly), kiest één vriend die ook Supporter is
-- zolang dat abonnement loopt. partner is leeg als er (nog) niemand gekozen is; changed_at houdt bij wanneer de partner
-- het laatst wijzigde (hoogstens één keer per 30 dagen, ook weghalen telt), zodat Duo niet rondgedeeld wordt.
CREATE TABLE duo_members (
  owner TEXT PRIMARY KEY REFERENCES "user"(id) ON DELETE CASCADE,
  partner TEXT UNIQUE REFERENCES "user"(id) ON DELETE SET NULL,
  changed_at TEXT NOT NULL,
  CHECK (partner IS NULL OR owner <> partner)
);

-- De Duo-producten ook in play_purchases toelaten. SQLite kan een CHECK niet wijzigen: de tabel opnieuw opbouwen met
-- dezelfde rijen (niemand verwijst ernaar).
CREATE TABLE play_purchases_new (
  purchase_token TEXT NOT NULL,
  user_id TEXT NOT NULL,
  product TEXT NOT NULL,
  linked_purchase_token TEXT,
  expiry TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (purchase_token),
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE,
  CHECK (((length(purchase_token) >= 10) AND (length(purchase_token) <= 4096))),
  CHECK ((product IN ('pro_monthly', 'pro_yearly', 'duo_monthly', 'duo_yearly')))
);
INSERT INTO play_purchases_new SELECT purchase_token, user_id, product, linked_purchase_token, expiry, updated_at FROM play_purchases;
DROP TABLE play_purchases;
ALTER TABLE play_purchases_new RENAME TO play_purchases;
CREATE INDEX play_purchases_user ON play_purchases (user_id, expiry DESC);
CREATE INDEX play_purchases_duo ON play_purchases (user_id, product, expiry);
