// Worker "macromatrix-api": de server van MacroMatrix op Cloudflare.
//   /auth/*          inloggen (Better Auth)
//   /v1/sync/*       synchroniseren (pull, push, fetch)
//   /v1/rpc/<naam>   de functies van de app
//   /v1/live         WebSocket voor live meldingen (met een ticket van /v1/live/ticket)
import { createAuth, WEB_ORIGINS } from './auth.js';
import { DbError, errorResponse, json } from './errors.js';
import { hubFor } from './hub.js';
import { checkTicket, makeTicket, notifyUser } from './live.js';
import { callRpc } from './rpc/index.js';
import { fetchRows, pull, push } from './sync.js';

export { UserHub } from './hub.js';

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

/** Ingelogde gebruiker uit de Bearer-token, of null. */
async function sessionUser(env, request) {
  if (!request.headers.get('authorization')) return null;
  const s = await createAuth(env).api.getSession({ headers: request.headers });
  return s?.user?.id ?? null;
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
  if (path === '/v1/live') {
    const uid = await checkTicket(env, url.searchParams.get('ticket'));
    if (!uid) return json({ code: 'PGRST301', message: 'invalid ticket' }, 401);
    return hubFor(env, uid).fetch(request);
  }
  // Niet ingelogd, met een meldingstoken van het toestel (achtergrondtaak zonder sessie)
  if (path === '/v1/rpc/pending_challenges' && request.method === 'POST') {
    return json(await callRpc('pending_challenges', await body(request), { db: env.DB, env, uid: null }));
  }
  const uid = await sessionUser(env, request);
  if (!uid) return json({ code: 'PGRST301', message: 'not logged in' }, 401);
  const waitUntil = (p) => ctx.waitUntil(p);

  if (path === '/v1/live/ticket' && request.method === 'POST') return json({ ticket: await makeTicket(env, uid) });
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
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return cors(request, env, new Response(null, { status: 204 }));
    if (url.pathname === '/health') return cors(request, env, json({ ok: true }));
    if (url.pathname.startsWith('/auth/')) {
      // Grove bescherming per IP vóór Better Auth (die heeft zijn eigen, fijnere limieten)
      const ip = request.headers.get('cf-connecting-ip') ?? 'onbekend';
      if (env.AUTH_LIMIT && !(await env.AUTH_LIMIT.limit({ key: ip })).success) {
        return cors(request, env, json({ code: 'RATE_LIMITED', message: 'Too many requests' }, 429));
      }
      return cors(request, env, await createAuth(env).handler(request));
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
