// Het oude adres app.divinenet.online stuurt voortaan door naar macromatrix.eu, met hetzelfde pad (de app, de
// website en de functies staan daar). Alle andere adressen gaan gewoon verder.
export async function onRequest({ request, next }) {
  const url = new URL(request.url);
  if (url.hostname === 'app.divinenet.online') {
    url.hostname = 'macromatrix.eu';
    return Response.redirect(url.toString(), 301);
  }
  return next();
}
