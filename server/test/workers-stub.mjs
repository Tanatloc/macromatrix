// src/hub.js importeert cloudflare:workers, dat buiten de Worker niet bestaat: in tests volstaat een lege
// DurableObject. Als eerste importeren, en daarna de broncode dynamisch (await import(...)).
import { registerHooks } from 'node:module';

registerHooks({
  resolve: (spec, ctx, next) =>
    spec === 'cloudflare:workers' ? { url: 'data:text/javascript,export class DurableObject {}', shortCircuit: true } : next(spec, ctx),
});
