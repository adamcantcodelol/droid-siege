import { RelayHub } from './relay.js';
export { RelayHub };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (path === '/ws' || path === '/relay' || path === '/health') {
      const id = env.RELAY.idFromName('global');
      const stub = env.RELAY.get(id);
      return stub.fetch(request);
    }
    // Static web build (index.html / .js / .pck / .wasm.gz / ...)
    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }
    return new Response('Droid Siege Worker up. No assets bound.', { status: 200 });
  },
};
