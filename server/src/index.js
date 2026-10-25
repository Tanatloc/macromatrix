// Worker "macromatrix-api": de server van MacroMatrix op Cloudflare. Fase 2: alleen inloggen (/auth/*).
import { createAuth, WEB_ORIGINS } from './auth.js';

/** CORS voor de webversie; de app zelf stuurt geen Origin. */
function cors(request, env, response) {
  const origin = request.headers.get('origin');
  const allowed = [...WEB_ORIGINS, ...(env.EXTRA_ORIGINS ? env.EXTRA_ORIGINS.split(',') : [])];
  if (!origin || !allowed.includes(origin)) return response;
  const r = new Response(response.body, response);
  r.headers.set('access-control-allow-origin', origin);
  r.headers.set('access-control-allow-headers', 'authorization, content-type');
  r.headers.set('access-control-allow-methods', 'GET, POST, OPTIONS');
  r.headers.set('access-control-expose-headers', 'set-auth-token');
  r.headers.set('access-control-max-age', '86400');
  r.headers.append('vary', 'origin');
  return r;
}

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

export default {
  async fetch(request, env) {
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
    return cors(request, env, json({ code: 'NOT_FOUND' }, 404));
  },
};
