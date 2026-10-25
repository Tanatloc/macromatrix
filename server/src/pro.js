// Supporter-status (pro_status) verlengen of stopzetten voor één bron (play, duo, ...). Gedeeld door de Google
// Play-aankopen (src/internal.js) en Duo (src/rpc/duo.js). Elk in één opdracht, dus veilig bij gelijktijdige wijzigingen.

/**
 * Supporter verlengen tot [untilIso] met bron [source], nooit inkorten. Een kortere Supporter met een andere bron (met
 * de hand, als geschenk, een eigen abonnement) wordt onthouden in base_until/base_source.
 */
export function extendPro(db, user, untilIso, source, now = new Date()) {
  return db
    .prepare(
      `INSERT INTO pro_status (user_id, until, source, updated_at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT (user_id) DO UPDATE SET
         base_until = CASE WHEN pro_status.source <> ?3 THEN pro_status.until ELSE pro_status.base_until END,
         base_source = CASE WHEN pro_status.source <> ?3 THEN pro_status.source ELSE pro_status.base_source END,
         until = excluded.until, source = ?3, updated_at = excluded.updated_at
       WHERE pro_status.until < excluded.until`,
    )
    .bind(user, untilIso, source, now.toISOString());
}

/**
 * Supporter met bron [source] stopzetten op [floorIso] (nu, of de vervaldatum van iets anders dat nog loopt). Alleen
 * als de rij die bron heeft; liep er een langere andere Supporter onder (base_until), dan komt die terug.
 */
export function endPro(db, user, floorIso, source, now = new Date()) {
  return db
    .prepare(
      `UPDATE pro_status SET
         until = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN base_until ELSE ?2 END,
         source = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN base_source ELSE source END,
         base_until = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN NULL ELSE base_until END,
         base_source = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN NULL ELSE base_source END,
         updated_at = ?4
       WHERE user_id = ?1 AND source = ?3 AND until > ?2`,
    )
    .bind(user, floorIso, source, now.toISOString());
}
