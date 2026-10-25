// Staging-site: de bestanden van de site + de functies uit functions/api, zoals Cloudflare Pages ze serveert, maar als
// Worker met een service binding API naar de staging-server (ingang Internal). Zo test staging de functies tegen de
// eigen server. De echte site blijft op Pages.
import * as barcode from '../../functions/api/fdc/barcode.js';
import * as coach from '../../functions/api/coach.js';
import * as label from '../../functions/api/label.js';
import * as offContribute from '../../functions/api/off-contribute.js';
import * as offSearch from '../../functions/api/off/search.js';
import * as photo from '../../functions/api/photo.js';
import * as playRtdn from '../../functions/api/play-rtdn.js';
import * as playVerify from '../../functions/api/play-verify.js';
import * as recipe from '../../functions/api/recipe.js';
import * as voice from '../../functions/api/voice.js';

// Zelfde adressen als de bestandsnamen onder functions/ (zo doet Pages het)
const ROUTES = {
  '/api/coach': coach,
  '/api/fdc/barcode': barcode,
  '/api/label': label,
  '/api/off-contribute': offContribute,
  '/api/off/search': offSearch,
  '/api/photo': photo,
  '/api/play-rtdn': playRtdn,
  '/api/play-verify': playVerify,
  '/api/recipe': recipe,
  '/api/voice': voice,
};

const METHODS = { GET: 'onRequestGet', POST: 'onRequestPost', PUT: 'onRequestPut', DELETE: 'onRequestDelete' };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const mod = Object.hasOwn(ROUTES, url.pathname) ? ROUTES[url.pathname] : null;
    if (!mod) return env.ASSETS.fetch(request);
    const handler = mod[METHODS[request.method]] ?? mod.onRequest;
    if (!handler) return new Response(null, { status: 405 });
    return handler({ request, env, params: {}, data: {}, waitUntil: (p) => ctx.waitUntil(p), next: () => env.ASSETS.fetch(request) });
  },
};
