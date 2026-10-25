// Gedeelde stukken voor de controlescripts (sync_check, rpc_check): HTTP zoals de app (node:http, zonder
// Origin), testaccounts op het testdomein met de code uit test_outbox, en de live WebSocket.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import http from 'node:http';
import https from 'node:https';

export const [base, ...rest] = process.argv.slice(2);
const env = rest.includes('--env') ? rest[rest.indexOf('--env') + 1] : undefined;
// Ook op productie (--env production): alleen testaccounts op het testdomein, die het script zelf weer wist
if (env !== 'staging' && env !== 'production') throw new Error('--env staging of --env production verplicht');
const flags = [rest.includes('--local') ? '--local' : '--remote', ...(env === 'production' ? [] : ['--env', env])];
export const DOMAIN = 'test.macromatrix.invalid';
export const run = Date.now().toString(36);
export const sql = (s) => JSON.parse(execFileSync('npx', ['wrangler', 'd1', 'execute', 'DB', ...flags, '--json', '--command', s], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })).at(-1).results;

export function call(method, path, body, token) {
  const u = new URL(path, base);
  return new Promise((resolve, reject) => {
    const req = (u.protocol === 'https:' ? https : http).request(
      u,
      { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) } },
      (res) => {
        let t = '';
        res.on('data', (c) => (t += c));
        res.on('end', () => {
          let data = null;
          try {
            data = JSON.parse(t);
          } catch {}
          resolve({ status: res.statusCode, data, token: res.headers['set-auth-token'] ?? null });
        });
      },
    );
    req.on('error', reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}

/** Testaccount aanmaken, bevestigen en een sessie teruggeven. */
export async function account(name) {
  const email = `${name}-${run}@${DOMAIN}`;
  assert.equal((await call('POST', '/auth/sign-up/email', { email, password: 'geheim123', name: '' })).status, 200);
  const code = sql(`SELECT token FROM test_outbox WHERE "to" = '${email}' ORDER BY id DESC LIMIT 1`)[0].token;
  const r = await call('POST', '/auth/email-otp/verify-email', { email, otp: code });
  assert.equal(r.status, 200);
  return { email, token: r.token ?? r.data.token, id: r.data.user.id };
}
export const login = async (email) => (await call('POST', '/auth/sign-in/email', { email, password: 'geheim123' })).token;

/** WebSocket met live meldingen; geeft een functie die wacht op het volgende bericht. */
export async function live(token) {
  const { data } = await call('POST', '/v1/live/ticket', {}, token);
  const url = new URL('/v1/live', base);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.searchParams.set('ticket', data.ticket);
  const ws = new WebSocket(url);
  const queue = [];
  let waiter = null;
  ws.onmessage = (e) => {
    if (e.data === 'pong') return;
    if (waiter) {
      waiter(e.data);
      waiter = null;
    } else queue.push(e.data);
  };
  await new Promise((ok, fail) => {
    ws.onopen = ok;
    ws.onerror = () => fail(new Error('websocket'));
  });
  return {
    ws,
    next: (ms = 5000) =>
      queue.length
        ? Promise.resolve(queue.shift())
        : new Promise((ok, fail) => {
            const t = setTimeout(() => fail(new Error(`geen melding binnen ${ms} ms`)), ms);
            waiter = (m) => {
              clearTimeout(t);
              ok(m);
            };
          }),
  };
}


export const steps = [];
export async function step(name, fn) {
  await fn();
  steps.push(name);
  console.log(`  ok  ${name}`);
}

/** Testaccounts van deze run en de limieten opruimen. */
export function cleanup() {
  sql(`DELETE FROM "user" WHERE email LIKE '%-${run}@${DOMAIN}'; DELETE FROM test_outbox WHERE "to" LIKE '%-${run}@${DOMAIN}'; DELETE FROM signup_ips; DELETE FROM rateLimit`);
}
