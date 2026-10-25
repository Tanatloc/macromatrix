// UserHub: één Durable Object per gebruiker. De toestellen van die gebruiker houden er een WebSocket open; na een
// geslaagde push (of een sociale gebeurtenis) stuurt de hub een kort bericht, en de toestellen halen dan zelf op.
// Met de Hibernation-API: een open verbinding zonder verkeer kost niets. "ping" beantwoordt Cloudflare zelf.
import { DurableObject } from 'cloudflare:workers';

export class UserHub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  /** WebSocket van een toestel (de Worker controleerde het ticket al en geeft de sessie mee in x-session). */
  async fetch(request) {
    if (request.headers.get('upgrade') !== 'websocket') return new Response('expected websocket', { status: 426 });
    // Hoogstens 20 tegelijk per gebruiker: de oudste gaat dicht
    const open = this.ctx.getWebSockets();
    for (const ws of open.slice(0, Math.max(0, open.length - 19))) ws.close(4000, 'too many connections');
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ sid: request.headers.get('x-session') });
    return new Response(null, { status: 101, webSocket: client });
  }

  /** Bericht naar alle open toestellen, bv. { type: 'changes', tables: ['diary'] }. Geeft het aantal terug. */
  async notify(message) {
    const text = JSON.stringify(message);
    let n = 0;
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(text);
        n++;
      } catch {}
    }
    return n;
  }

  /** Uitgelogd op één toestel: alleen de verbindingen van die sessie sluiten. */
  async closeSession(sid) {
    for (const ws of this.ctx.getWebSockets()) if (ws.deserializeAttachment()?.sid === sid) ws.close(4002, 'signed out');
  }

  /** Account verwijderd, overal uitgelogd of wachtwoord gewijzigd: alle verbindingen sluiten. */
  async closeAll() {
    for (const ws of this.ctx.getWebSockets()) ws.close(4001, 'account deleted');
  }

  async webSocketMessage() {
    // Toestellen sturen niets anders dan "ping" (automatisch beantwoord)
  }

  async webSocketClose(ws, code) {
    try {
      ws.close(code === 1005 ? 1000 : code);
    } catch {}
  }
}

/** De hub van een gebruiker, altijd in de EU (lokaal in wrangler dev bestaat jurisdictie niet). */
export function hubFor(env, uid) {
  let ns = env.HUB;
  try {
    ns = env.HUB.jurisdiction('eu');
  } catch {}
  return ns.get(ns.idFromName(uid));
}
