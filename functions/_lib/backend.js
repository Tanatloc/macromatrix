// Supabase of de eigen server (Cloudflare Worker macromatrix-api, server/ in deze repo).
// Met een service binding API naar de ingang Internal van die Worker gaan de Supabase-aanroepen van deze functies
// (inloggen nakijken, functies als de gebruiker) daarheen, met hetzelfde antwoord als Supabase gaf. Zonder die binding
// verandert er niets. Dit bestand heeft geen onRequest-functies en wordt dus geen eigen adres op de site.
import { SUPABASE_URL } from './ai.js';

const reply = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

/** Een fetch die Supabase-adressen naar de eigen server stuurt als [env].API bestaat; anders gewoon [base]. */
export function backendFetch(env, base = fetch) {
  const api = env?.API;
  if (!api) return base;
  return async (url, init = {}) => {
    const u = String(url instanceof Request ? url.url : url);
    if (!u.startsWith(SUPABASE_URL)) return base(url, init);
    const path = new URL(u).pathname;
    const auth = new Headers(init.headers).get('Authorization');
    if (path === '/auth/v1/user') {
      const who = await api.session(auth);
      return who ? reply(200, who) : reply(401, { msg: 'invalid token' });
    }
    const m = path.match(/^\/rest\/v1\/rpc\/([a-z0-9_]+)$/);
    if (m) {
      let params = {};
      try {
        params = init.body ? JSON.parse(init.body) : {};
      } catch (_) {
        return reply(400, { code: 'PGRST102', message: 'Empty or invalid json' });
      }
      const r = await api.rpc(m[1], params, auth);
      return reply(r.status, r.body);
    }
    return reply(404, { code: 'PGRST202', message: `not available on this server: ${path}` });
  };
}
