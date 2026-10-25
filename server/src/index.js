// Worker "macromatrix-api": de server van MacroMatrix op Cloudflare.
//   /auth/*          inloggen (Better Auth)
//   /v1/sync/*       synchroniseren (pull, push, fetch)
//   /v1/rpc/<naam>   de functies van de app
//   /v1/live         WebSocket voor live meldingen (met een ticket van /v1/live/ticket)
import { createAuth, WEB_ORIGINS } from './auth.js';
import { cleanup, dailyBackup, restoreCheck } from './cron.js';
import { DbError, errorResponse, json } from './errors.js';
import { hubFor } from './hub.js';
import { checkTicket, makeTicket, notifyUser } from './live.js';
import { callRpc } from './rpc/index.js';
import { fetchRows, pull, push } from './sync.js';

export { UserHub } from './hub.js';
export { Internal } from './internal.js';

/** CORS voor de webversie; de app zelf stuurt geen Origin. */
function cors(request, env, response) {
  const origin = request.headers.get('origin');
  const allowed = [...WEB_ORIGINS, ...(env.EXTRA_ORIGINS ? env.EXTRA_ORIGINS.split(',') : [])];
  if (!origin || !allowed.includes(origin) || response.status === 101) return response;
  const r = new Response(response.body, response);
  r.headers.set('access-control-allow-origin', origin);
  r.headers.set('access-control-allow-headers', 'authorization, content-type');
  r.headers.set('access-control-allow-methods', 'GET, POST, OPTIONS');
  r.headers.set('access-control-expose-headers', 'set-auth-token');
  r.headers.set('access-control-max-age', '86400');
  r.headers.append('vary', 'origin');
  return r;
}

/** Ingelogde gebruiker en sessie uit de Bearer-token, of null. */
async function session(env, request) {
  if (!request.headers.get('authorization')) return null;
  const s = await createAuth(env).api.getSession({ headers: request.headers });
  return s?.user?.id ? { uid: s.user.id, sid: s.session.id } : null;
}

/** Grove limiet per sleutel (IP of gebruiker); zonder binding (lokaal) geen limiet. */
async function limited(limiter, key) {
  return limiter ? !(await limiter.limit({ key })).success : false;
}

async function body(request) {
  try {
    return await request.json();
  } catch {
    throw new DbError('PGRST102', 'Empty or invalid json');
  }
}

async function api(request, env, ctx, url) {
  const path = url.pathname;
  const ip = request.headers.get('cf-connecting-ip') ?? 'onbekend';
  if (path === '/v1/live') {
    const t = await checkTicket(env, url.searchParams.get('ticket'));
    if (!t) return json({ code: 'PGRST301', message: 'invalid ticket' }, 401);
    const headers = new Headers(request.headers);
    headers.set('x-session', t.sid);
    return hubFor(env, t.uid).fetch(new Request(request, { headers }));
  }
  // Niet ingelogd, met een meldingstoken van het toestel (achtergrondtaak zonder sessie)
  if (path === '/v1/rpc/pending_challenges' && request.method === 'POST') {
    if (await limited(env.AUTH_LIMIT, ip)) return json({ code: '429', message: 'Too many requests' }, 429);
    return json(await callRpc('pending_challenges', await body(request), { db: env.DB, env, uid: null }));
  }
  const s = await session(env, request);
  if (!s) return json({ code: 'PGRST301', message: 'not logged in' }, 401);
  const { uid } = s;
  if (await limited(env.API_LIMIT, uid)) return json({ code: '429', message: 'Too many requests' }, 429);
  const waitUntil = (p) => ctx.waitUntil(p);

  if (path === '/v1/live/ticket' && request.method === 'POST') return json({ ticket: await makeTicket(env, uid, s.sid) });
  if (path === '/v1/sync/pull' && request.method === 'GET') {
    return json(await pull(env.DB, uid, url.searchParams.get('table'), url.searchParams.get('since'), url.searchParams.get('limit')));
  }
  if (path === '/v1/sync/fetch' && request.method === 'POST') {
    const b = await body(request);
    return json(await fetchRows(env.DB, uid, b.table, b.keys));
  }
  if (path === '/v1/sync/push' && request.method === 'POST') {
    const b = await body(request);
    const saved = await push(env.DB, uid, b.table, b.rows, { insertOnly: b.insertOnly === true });
    if (Object.keys(saved).length) waitUntil(notifyUser(env, uid, { type: 'changes', tables: [b.table] }));
    return json(saved);
  }
  const m = path.match(/^\/v1\/rpc\/([a-z0-9_]{1,64})$/);
  if (m && request.method === 'POST') {
    const result = await callRpc(m[1], await body(request), { db: env.DB, env, uid, waitUntil });
    return json(result ?? null);
  }
  return json({ code: 'NOT_FOUND', message: 'not found' }, 404);
}

export default {
  /** Geplande taken (src/cron.js): 's nachts opruimen en een back-up, elke maand een hersteltest. */
  async scheduled(event, env, ctx) {
    if (event.cron === '0 4 1 * *') return ctx.waitUntil(restoreCheck(env));
    ctx.waitUntil(cleanup(env.DB).then((r) => console.log('opruimen', JSON.stringify(r))));
    if (env.BACKUP && env.BACKUP_KEY) ctx.waitUntil(dailyBackup(env));
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return cors(request, env, new Response(null, { status: 204 }));
    if (url.pathname === '/health') return cors(request, env, json({ ok: true }));
    if (url.pathname.startsWith('/auth/')) {
      // Grove bescherming per IP vóór Better Auth (die heeft zijn eigen, fijnere limieten)
      const ip = request.headers.get('cf-connecting-ip') ?? 'onbekend';
      if (await limited(env.AUTH_LIMIT, ip)) return cors(request, env, json({ code: 'RATE_LIMITED', message: 'Too many requests' }, 429));
      // Uitloggen: daarna ook de live verbinding van die sessie sluiten
      const out = url.pathname === '/auth/sign-out' ? await session(env, request).catch(() => null) : null;
      const res = await createAuth(env).handler(request);
      if (out && res.ok) ctx.waitUntil(hubFor(env, out.uid).closeSession(out.sid).catch(() => {}));
      return cors(request, env, res);
    }
    if (url.pathname.startsWith('/v1/')) {
      try {
        return cors(request, env, await api(request, env, ctx, url));
      } catch (e) {
        return cors(request, env, errorResponse(e));
      }
    }
    return cors(request, env, json({ code: 'NOT_FOUND' }, 404));
  },
};
