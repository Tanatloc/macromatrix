// De body van een verzoek inlezen met een bovengrens in bytes, ook als er geen Content-Length meegestuurd wordt
// (chunked): de stroom wordt stuk voor stuk gelezen en afgebroken zodra het te veel wordt. Gebruikt door alle
// functies die een body lezen. Dit bestand heeft geen onRequest-functies en wordt dus geen eigen adres op de site.

import { json } from './ai.js';

// Geeft {bytes} terug, {error: antwoord 413} als het meer dan [max] bytes is, of {bad: true} als de stroom faalt.
// [tooBig] is de JSON van het 413-antwoord (elke functie heeft zijn eigen foutcode).
export async function readBytes(request, max, tooBig = { error: 'too_big' }) {
  const declared = Number(request.headers.get('Content-Length') ?? 0);
  if (declared > max) return { error: json(tooBig, 413) };
  if (!request.body) return { bytes: new Uint8Array(0) };
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > max) {
        await reader.cancel().catch(() => {});
        return { error: json(tooBig, 413) };
      }
      chunks.push(value);
    }
  } catch (_) {
    return { bad: true };
  }
  const all = new Uint8Array(size);
  let at = 0;
  for (const c of chunks) {
    all.set(c, at);
    at += c.length;
  }
  return { bytes: all };
}

// JSON: {value}, {error: 413} of {bad: true} (kapotte stroom of geen geldige JSON).
export async function readJson(request, max, tooBig) {
  const r = await readBytes(request, max, tooBig);
  if (!r.bytes) return r;
  try {
    return { value: JSON.parse(new TextDecoder().decode(r.bytes)) };
  } catch (_) {
    return { bad: true };
  }
}

// Multipart of een gewoon formulier: {form}, {error: 413} of {bad: true}.
export async function readForm(request, max, tooBig) {
  const r = await readBytes(request, max, tooBig);
  if (!r.bytes) return r;
  try {
    const type = request.headers.get('Content-Type') ?? '';
    return { form: await new Response(r.bytes, { headers: { 'Content-Type': type } }).formData() };
  } catch (_) {
    return { bad: true };
  }
}
