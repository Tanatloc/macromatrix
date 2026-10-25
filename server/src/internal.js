// Ingang "Internal": alleen bereikbaar via een service binding (de functies van de website, functions/ in de repo),
// nooit vanaf het internet. Vervangt wat die functies bij Supabase deden:
// - session: het token van de gebruiker nakijken (was /auth/v1/user);
// - rpc: een functie als die gebruiker (was /rest/v1/rpc/… met zijn token);
// - de Play-aankopen en Supporter-status schrijven (was de service-role-sleutel op play_purchases en pro_status).
import { WorkerEntrypoint } from 'cloudflare:workers';
import { createAuth } from './auth.js';
import { DbError, fromD1 } from './errors.js';
import { callRpc } from './rpc/index.js';

export class Internal extends WorkerEntrypoint {
  /** { id, email } van de gebruiker achter dit Authorization-hoofd, of null. */
  async session(authorization) {
    if (!authorization) return null;
    const s = await createAuth(this.env).api.getSession({ headers: new Headers({ authorization }) });
    return s?.user ? { id: s.user.id, email: s.user.email } : null;
  }

  /** Een functie als de gebruiker achter [authorization]. Antwoord zoals PostgREST: { status, body }. */
  async rpc(name, params, authorization) {
    try {
      const who = await this.session(authorization);
      const data = await callRpc(name, params ?? {}, { db: this.env.DB, env: this.env, uid: who?.id ?? null, waitUntil: (p) => this.ctx.waitUntil(p) });
      return { status: 200, body: data ?? null };
    } catch (e) {
      const err = e instanceof DbError ? e : fromD1(e);
      return { status: err.status, body: err.toJSON() };
    }
  }

  // ── Google Play (zelfde logica als de service-role-aanroepen in functions/_lib/play.js) ──

  async findPurchase(token) {
    return this.env.DB.prepare('SELECT user_id, product, expiry FROM play_purchases WHERE purchase_token = ?').bind(token).first();
  }

  async savePurchase(row) {
    await this.env.DB.prepare(
      `INSERT INTO play_purchases (purchase_token, user_id, product, linked_purchase_token, expiry, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (purchase_token) DO UPDATE SET user_id = excluded.user_id, product = excluded.product,
         linked_purchase_token = excluded.linked_purchase_token, expiry = excluded.expiry, updated_at = excluded.updated_at`,
    )
      .bind(row.purchase_token, row.user_id, row.product, row.linked_purchase_token ?? null, row.expiry, row.updated_at)
      .run();
  }

  /** Alleen als nog niemand de aankoop heeft; geeft de eigenaar terug. */
  async claimPurchase(row) {
    await this.env.DB.prepare(
      `INSERT INTO play_purchases (purchase_token, user_id, product, linked_purchase_token, expiry, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (purchase_token) DO NOTHING`,
    )
      .bind(row.purchase_token, row.user_id, row.product, row.linked_purchase_token ?? null, row.expiry, row.updated_at)
      .run();
    return (await this.findPurchase(row.purchase_token))?.user_id ?? null;
  }

  /**
   * Supporter verlengen tot [untilIso], nooit inkorten. Een kortere Supporter met de hand of als geschenk wordt
   * onthouden in base_until/base_source. In één opdracht, dus veilig bij gelijktijdige wijzigingen.
   */
  async grantPro(user, untilIso) {
    const now = new Date().toISOString();
    await this.env.DB.prepare(
      `INSERT INTO pro_status (user_id, until, source, updated_at) VALUES (?1, ?2, 'play', ?3)
       ON CONFLICT (user_id) DO UPDATE SET
         base_until = CASE WHEN pro_status.source <> 'play' THEN pro_status.until ELSE pro_status.base_until END,
         base_source = CASE WHEN pro_status.source <> 'play' THEN pro_status.source ELSE pro_status.base_source END,
         until = excluded.until, source = 'play', updated_at = excluded.updated_at
       WHERE pro_status.until < excluded.until`,
    )
      .bind(user, untilIso, now)
      .run()
      .catch((e) => {
        throw fromD1(e);
      });
  }

  /**
   * Supporter stopzetten na een einde of terugbetaling: tot nu, of tot de vervaldatum van een ander lopend
   * Play-abonnement van hetzelfde account. Alleen een rij met source 'play'; liep er een langere Supporter met de hand
   * onder (base_until), dan komt die terug.
   */
  async revokePro(user, exceptToken, nowMs) {
    const nowIso = new Date(nowMs).toISOString();
    const other = await this.env.DB.prepare(
      'SELECT expiry FROM play_purchases WHERE user_id = ? AND purchase_token <> ? AND expiry > ? ORDER BY expiry DESC LIMIT 1',
    )
      .bind(user, exceptToken, nowIso)
      .first('expiry');
    const floor = other ? new Date(other).toISOString() : nowIso;
    await this.env.DB.prepare(
      `UPDATE pro_status SET
         until = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN base_until ELSE ?2 END,
         source = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN base_source ELSE source END,
         base_until = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN NULL ELSE base_until END,
         base_source = CASE WHEN base_until IS NOT NULL AND base_source IS NOT NULL AND base_until > ?2 THEN NULL ELSE base_source END,
         updated_at = ?3
       WHERE user_id = ?1 AND source = 'play' AND until > ?2`,
    )
      .bind(user, floor, nowIso)
      .run();
  }
}
